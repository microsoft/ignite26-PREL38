import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


SUBSCRIPTION_ID = os.environ["CALDOVA_SUBSCRIPTION_ID"]
RESOURCE_GROUP = os.environ["CALDOVA_RESOURCE_GROUP"]
EXPECTED_RESOURCE_GROUP = os.environ.get("CALDOVA_EXPECTED_RESOURCE_GROUP", RESOURCE_GROUP)
SCOPE = f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{RESOURCE_GROUP}"
ARM = "https://management.azure.com"
RETAIL = "https://prices.azure.com/api/retail/prices"
RETAIL_SNAPSHOT = json.loads(
    __import__("base64").b64decode(os.environ.get("CALDOVA_RETAIL_PRICE_SNAPSHOT_B64", "e30="))
)


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def request_json(url, *, method="GET", body=None, headers=None, timeout=45):
    payload = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=payload,
        method=method,
        headers={"Accept": "application/json", "Content-Type": "application/json", **(headers or {})},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:1200]
        raise RuntimeError(f"HTTP {error.code} for {method} {url}: {detail}") from error


def managed_identity_token():
    resource = "https://management.azure.com/"
    client_id = os.environ.get("AZURE_CLIENT_ID")
    if os.environ.get("IDENTITY_ENDPOINT") and os.environ.get("IDENTITY_HEADER"):
        query = {"api-version": "2019-08-01", "resource": resource}
        if client_id:
            query["client_id"] = client_id
        result = request_json(
            f"{os.environ['IDENTITY_ENDPOINT']}?{urllib.parse.urlencode(query)}",
            headers={"X-IDENTITY-HEADER": os.environ["IDENTITY_HEADER"]},
        )
        return result["access_token"]
    query = {"api-version": "2018-02-01", "resource": resource}
    if client_id:
        query["client_id"] = client_id
    result = request_json(
        f"http://169.254.169.254/metadata/identity/oauth2/token?{urllib.parse.urlencode(query)}",
        headers={"Metadata": "true"},
        timeout=10,
    )
    return result["access_token"]


def arm(path, *, api_version, method="GET", body=None, token=None):
    separator = "&" if "?" in path else "?"
    return request_json(
        f"{ARM}{path}{separator}api-version={urllib.parse.quote(api_version)}",
        method=method,
        body=body,
        headers={"Authorization": f"Bearer {token or managed_identity_token()}"},
    )


def source(status, detail=None, **values):
    return {"status": status, "detail": detail, **values}


def cost_query(token, endpoint, query_type):
    now = dt.datetime.now(dt.timezone.utc)
    start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    body = {
        "type": query_type,
        "timeframe": "Custom",
        "timePeriod": {"from": start.isoformat(), "to": now.isoformat()},
        "dataset": {
            "granularity": "Daily",
            "aggregation": {"totalCost": {"name": "PreTaxCost", "function": "Sum"}},
            "grouping": [
                {"type": "Dimension", "name": "ServiceName"},
                {"type": "Dimension", "name": "ResourceId"},
            ],
        },
    }
    result = arm(
        f"{SCOPE}/providers/Microsoft.CostManagement/{endpoint}",
        api_version="2025-03-01",
        method="POST",
        body=body,
        token=token,
    )
    properties = result.get("properties", {})
    columns = [column.get("name") for column in properties.get("columns", [])]
    rows = properties.get("rows", [])
    return {"columns": columns, "rows": rows}


def normalized_cost(data):
    columns = data["columns"]
    indexes = {name: index for index, name in enumerate(columns)}
    rows = data["rows"]
    cost_index = indexes.get("PreTaxCost")
    currency_index = indexes.get("Currency")
    total = sum(float(row[cost_index]) for row in rows) if cost_index is not None else None
    currency = rows[0][currency_index] if rows and currency_index is not None else None
    return {"total": total, "currency": currency, "columns": columns, "rows": rows}


def list_inventory(token):
    result = arm(f"{SCOPE}/resources", api_version="2021-04-01", token=token)
    detail_versions = {
        "microsoft.compute/virtualmachines": "2024-03-01",
        "microsoft.network/applicationgateways": "2024-05-01",
    }
    resources = []
    for item in result.get("value", []):
        resource_type = (item.get("type") or "").lower()
        sku = item.get("sku")
        if resource_type in detail_versions:
            try:
                detail = arm(item["id"], api_version=detail_versions[resource_type], token=token)
                if resource_type == "microsoft.compute/virtualmachines":
                    sku = {"name": detail.get("properties", {}).get("hardwareProfile", {}).get("vmSize")}
                else:
                    sku = detail.get("properties", {}).get("sku")
            except Exception:
                pass
        resources.append(
            {
                "id": item.get("id"),
                "name": item.get("name"),
                "type": item.get("type"),
                "location": item.get("location"),
                "sku": sku,
                "kind": item.get("kind"),
                "tags": item.get("tags") or {},
            }
        )
    return resources


def retail_estimates(resources):
    service_by_type = {
        "microsoft.compute/virtualmachines": "Virtual Machines",
        "microsoft.containerregistry/registries": "Container Registry",
        "microsoft.dbforpostgresql/flexibleservers": "Azure Database for PostgreSQL",
        "microsoft.network/applicationgateways": "Application Gateway",
    }
    estimates = []
    unsupported = []
    used_snapshot = False
    for resource in resources:
        resource_type = (resource.get("type") or "").lower()
        service = service_by_type.get(resource_type)
        sku = (resource.get("sku") or {}).get("name")
        region = (resource.get("location") or "").replace(" ", "")
        if not service or not sku or not region or region.lower() == "global":
            unsupported.append({"resourceId": resource.get("id"), "reason": "No safe service/SKU/region retail-price mapping."})
            continue
        filter_value = f"serviceName eq '{service}' and armRegionName eq '{region}' and priceType eq 'Consumption'"
        try:
            source_name = "Azure Retail Prices API live"
            try:
                result = request_json(f"{RETAIL}?{urllib.parse.urlencode({'$filter': filter_value})}")
                catalog = result.get("Items", [])
            except Exception:
                catalog = [
                    item for item in RETAIL_SNAPSHOT.get("items", [])
                    if item.get("serviceName") == service and item.get("armRegionName") == region
                ]
                if not catalog:
                    raise
                source_name = "Automatically refreshed Azure Retail Prices snapshot"
                used_snapshot = True
            normalized_sku = sku.lower().removeprefix("standard_")
            items = [
                item for item in catalog
                if item.get("isPrimaryMeterRegion", True)
                and float(item.get("retailPrice") or 0) > 0
                and (
                    (
                        resource_type == "microsoft.containerregistry/registries"
                        and str(item.get("skuName") or "").lower() == normalized_sku
                        and "registry unit" in str(item.get("meterName") or "").lower()
                    )
                    or (
                        resource_type == "microsoft.network/applicationgateways"
                        and normalized_sku.replace("_", " ") in str(item.get("productName") or "").lower()
                        and "fixed cost" in str(item.get("meterName") or "").lower()
                    )
                    or normalized_sku in {
                        str(item.get("armSkuName") or "").lower().removeprefix("standard_"),
                        str(item.get("skuName") or "").lower().removeprefix("standard_"),
                    }
                )
            ]
            if not items:
                unsupported.append({"resourceId": resource.get("id"), "reason": "Retail Prices returned no matching primary meter."})
                continue
            item = min(items, key=lambda value: float(value.get("retailPrice") or 0))
            unit = item.get("unitOfMeasure")
            price = float(item["retailPrice"])
            monthly = None
            assumption = "Unit price only; monthly quantity is unknown."
            if unit and "hour" in unit.lower():
                monthly = price * 730
                assumption = "730 hours/month at the lowest matching primary Consumption meter."
            elif unit and "day" in unit.lower():
                monthly = price * 30.4375
                assumption = "30.4375 days/month at the lowest matching primary Consumption meter."
            estimates.append(
                {
                    "resourceId": resource.get("id"),
                    "serviceName": service,
                    "sku": sku,
                    "region": region,
                    "retailPrice": price,
                    "currency": item.get("currencyCode"),
                    "unitOfMeasure": unit,
                    "estimatedMonthlyCost": monthly,
                    "assumption": assumption,
                    "productName": item.get("productName"),
                    "meterName": item.get("meterName"),
                    "priceSource": source_name,
                }
            )
        except Exception as error:
            unsupported.append({"resourceId": resource.get("id"), "reason": str(error)})
    return {
        "items": estimates,
        "unsupported": unsupported,
        "usedSnapshot": used_snapshot,
        "snapshotCapturedAtUtc": RETAIL_SNAPSHOT.get("capturedAtUtc") if used_snapshot else None,
    }


def get_finops():
    if RESOURCE_GROUP != EXPECTED_RESOURCE_GROUP or "/" in RESOURCE_GROUP or not RESOURCE_GROUP.startswith("rg-caldova-"):
        raise RuntimeError("Connector scope does not match the configured Caldova learner resource group.")
    captured = utc_now()
    token = managed_identity_token()
    actual = forecast = budgets = anomalies = advisor = consumption = None
    unsupported = []
    try:
        actual = source("available", **normalized_cost(cost_query(token, "query", "ActualCost")))
    except Exception as error:
        actual = source("unavailable", str(error))
    try:
        forecast = source("available", **normalized_cost(cost_query(token, "forecast", "ActualCost")))
    except Exception as error:
        forecast = source("unsupported", str(error))
    try:
        result = arm(f"{SCOPE}/providers/Microsoft.Consumption/budgets", api_version="2023-11-01", token=token)
        budgets = source("available", items=result.get("value", []))
    except Exception as error:
        budgets = source("unsupported", str(error), items=[])
    try:
        result = arm(f"{SCOPE}/providers/Microsoft.CostManagement/alerts", api_version="2025-03-01", token=token)
        anomalies = source("available", items=result.get("value", []))
    except Exception as error:
        anomalies = source("unsupported", str(error), items=[])
    try:
        query = urllib.parse.urlencode({"$filter": "Category eq 'Cost'"})
        result = arm(f"/subscriptions/{SUBSCRIPTION_ID}/providers/Microsoft.Advisor/recommendations?{query}", api_version="2023-01-01", token=token)
        group_segment = f"/resourcegroups/{RESOURCE_GROUP}/"
        items = [
            item for item in result.get("value", [])
            if group_segment in str(item.get("properties", {}).get("resourceMetadata", {}).get("resourceId", "")).lower()
        ]
        advisor = source("available", items=items)
    except Exception as error:
        advisor = source("unsupported", str(error), items=[])
    if actual["status"] != "available" or actual.get("total") is None:
        try:
            result = arm(f"{SCOPE}/providers/Microsoft.Consumption/usageDetails", api_version="2023-11-01", token=token)
            consumption = source("available", items=result.get("value", []))
        except Exception as error:
            consumption = source("unavailable", str(error), items=[])
    else:
        consumption = source("not_needed", "ActualCost returned monetary data.", items=[])
    inventory = list_inventory(token)
    estimates = retail_estimates(inventory)
    if not estimates["items"]:
        unsupported.append("No inventory item had an unambiguous hourly Retail Prices match; estimates remain unknown.")
    return {
        "schemaVersion": 1,
        "scope": {"subscriptionId": SUBSCRIPTION_ID, "resourceGroup": RESOURCE_GROUP, "resourceId": SCOPE},
        "capturedAtUtc": captured,
        "freshness": {"status": "live", "maxAgeMinutes": 5},
        "provenance": {
            "identity": "Azure SRE Agent managed identity",
            "actualCost": "Microsoft.CostManagement/query",
            "forecast": "Microsoft.CostManagement/forecast",
            "budgets": "Microsoft.Consumption/budgets",
            "anomalies": "Microsoft.CostManagement/alerts",
            "advisor": "Microsoft.Advisor/recommendations filtered to the learner resource group",
            "consumption": "Microsoft.Consumption/usageDetails",
            "inventory": "Azure Resource Manager resource-group resources",
            "estimates": "Azure Retail Prices API",
        },
        "actualCost": actual,
        "forecast": forecast,
        "budgets": budgets,
        "anomalies": anomalies,
        "advisor": advisor,
        "consumption": consumption,
        "inventory": source("available", items=inventory),
        "retailPriceEstimates": source("available" if estimates["items"] else "partial", **estimates),
        "unsupportedSources": unsupported,
        "writeOperations": "none",
    }


TOOLS = [
    {
        "name": "get_caldova_finops",
        "description": "Return live read-only FinOps evidence hard-scoped to the configured Caldova learner resource group.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    }
]


def send(identifier, result=None, error=None):
    message = {"jsonrpc": "2.0", "id": identifier}
    if error is not None:
        message["error"] = error
    else:
        message["result"] = result
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        try:
            message = json.loads(line)
            method = message.get("method")
            identifier = message.get("id")
            if method == "initialize":
                send(
                    identifier,
                    {
                        "protocolVersion": message.get("params", {}).get("protocolVersion", "2025-06-18"),
                        "capabilities": {"tools": {"listChanged": False}},
                        "serverInfo": {"name": "caldova-finops", "version": "1.0.0"},
                    },
                )
            elif method == "ping":
                send(identifier, {})
            elif method == "tools/list":
                send(identifier, {"tools": TOOLS})
            elif method == "tools/call":
                params = message.get("params", {})
                if params.get("name") != "get_caldova_finops" or params.get("arguments") not in ({}, None):
                    send(identifier, error={"code": -32602, "message": "Only get_caldova_finops with no arguments is allowed."})
                    continue
                try:
                    result = get_finops()
                    send(
                        identifier,
                        {
                            "content": [{"type": "text", "text": json.dumps(result, separators=(",", ":"))}],
                            "structuredContent": result,
                            "isError": False,
                        },
                    )
                except Exception as error:
                    send(
                        identifier,
                        {
                            "content": [{"type": "text", "text": json.dumps({"error": str(error), "capturedAtUtc": utc_now()})}],
                            "isError": True,
                        },
                    )
            elif identifier is not None:
                send(identifier, error={"code": -32601, "message": f"Unsupported MCP method: {method}"})
        except Exception as error:
            print(f"caldova-finops-mcp error: {error}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
