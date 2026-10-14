import contextlib
import copy
import datetime as dt
import email.utils
import hashlib
import json
import os
import re
import sys
import tempfile
import threading
import time
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
COST_CACHE_TTL_SECONDS = int(os.environ.get("CALDOVA_COST_CACHE_TTL_SECONDS", "1800"))
COST_CACHE_MAX_STALE_SECONDS = int(os.environ.get("CALDOVA_COST_CACHE_MAX_STALE_SECONDS", "86400"))
COST_LOCK_WAIT_SECONDS = float(os.environ.get("CALDOVA_COST_LOCK_WAIT_SECONDS", "5"))
COST_LOCK_STALE_SECONDS = float(os.environ.get("CALDOVA_COST_LOCK_STALE_SECONDS", "90"))
HTTP_MAX_ATTEMPTS = int(os.environ.get("CALDOVA_HTTP_MAX_ATTEMPTS", "3"))
HTTP_MAX_RETRY_SECONDS = float(os.environ.get("CALDOVA_HTTP_MAX_RETRY_SECONDS", "10"))
COST_QUERY_LOCK = threading.Lock()
_CACHE_KEY = hashlib.sha256(SCOPE.encode("utf-8")).hexdigest()[:16]
COST_CACHE_PATH = os.environ.get(
    "CALDOVA_COST_CACHE_PATH",
    os.path.join(tempfile.gettempdir(), f"caldova-finops-cost-{_CACHE_KEY}.json"),
)
COST_LOCK_PATH = f"{COST_CACHE_PATH}.lock"


class HttpRequestError(RuntimeError):
    def __init__(self, status, method, url, detail, headers):
        self.status = status
        self.method = method
        self.url = url
        self.detail = detail
        self.headers = {str(key).lower(): str(value) for key, value in (headers or {}).items()}
        rate_limit = self.headers.get("x-ms-ratelimit-microsoft.costmanagement-qpu-remaining")
        retry_after = (
            self.headers.get("x-ms-ratelimit-microsoft.costmanagement-qpu-retry-after")
            or self.headers.get("retry-after")
            or self.headers.get("x-ms-retry-after-ms")
        )
        context = []
        if rate_limit:
            context.append(f"costManagementQpuRemaining={rate_limit}")
        if retry_after:
            context.append(f"retryAfter={retry_after}")
        suffix = f" ({'; '.join(context)})" if context else ""
        super().__init__(f"HTTP {status} for {method} {url}: {detail}{suffix}")


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _retry_delay_seconds(error):
    if error.headers.get("x-ms-ratelimit-microsoft.costmanagement-qpu-remaining") and re.search(
        r"QueriesPerHour\s*:\s*0",
        error.headers["x-ms-ratelimit-microsoft.costmanagement-qpu-remaining"],
        re.IGNORECASE,
    ):
        return -1
    value = error.headers.get("x-ms-ratelimit-microsoft.costmanagement-qpu-retry-after")
    if value:
        try:
            return min(max(float(value), 0), HTTP_MAX_RETRY_SECONDS)
        except ValueError:
            pass
    value = error.headers.get("x-ms-retry-after-ms")
    if value:
        try:
            return min(max(float(value) / 1000, 0), HTTP_MAX_RETRY_SECONDS)
        except ValueError:
            pass
    value = error.headers.get("retry-after")
    if value:
        try:
            return min(max(float(value), 0), HTTP_MAX_RETRY_SECONDS)
        except ValueError:
            try:
                retry_at = email.utils.parsedate_to_datetime(value)
                return min(max((retry_at - dt.datetime.now(dt.timezone.utc)).total_seconds(), 0), HTTP_MAX_RETRY_SECONDS)
            except (TypeError, ValueError):
                pass
    return None


def request_json(url, *, method="GET", body=None, headers=None, timeout=45, max_attempts=None):
    payload = None if body is None else json.dumps(body).encode("utf-8")
    attempts = max_attempts or HTTP_MAX_ATTEMPTS
    for attempt in range(1, attempts + 1):
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
            failure = HttpRequestError(error.code, method, url, detail, error.headers)
            retryable = error.code == 429 or 500 <= error.code < 600
            if not retryable or attempt == attempts:
                raise failure from error
            delay = _retry_delay_seconds(failure)
            if delay == -1:
                raise failure from error
            time.sleep(delay if delay is not None else min(attempt * 2, HTTP_MAX_RETRY_SECONDS))


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


def parse_utc(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None


def age_seconds(captured_at):
    captured = parse_utc(captured_at)
    if captured is None:
        return None
    return max((dt.datetime.now(dt.timezone.utc) - captured).total_seconds(), 0)


def load_cost_cache():
    try:
        with open(COST_CACHE_PATH, encoding="utf-8") as handle:
            cached = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None
    if (
        cached.get("schemaVersion") != 1
        or cached.get("scope") != SCOPE
        or not isinstance(cached.get("actualCost"), dict)
        or age_seconds(cached.get("capturedAtUtc")) is None
    ):
        return None
    return cached


def save_cost_cache(captured_at, actual, forecast):
    directory = os.path.dirname(COST_CACHE_PATH) or "."
    os.makedirs(directory, exist_ok=True)
    document = {
        "schemaVersion": 1,
        "scope": SCOPE,
        "capturedAtUtc": captured_at,
        "actualCost": actual,
        "forecast": forecast,
    }
    descriptor, temporary_path = tempfile.mkstemp(prefix=".caldova-finops-", suffix=".json", dir=directory, text=True)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(document, handle, separators=(",", ":"))
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, COST_CACHE_PATH)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.remove(temporary_path)


@contextlib.contextmanager
def cost_query_guard():
    os.makedirs(os.path.dirname(COST_LOCK_PATH) or ".", exist_ok=True)
    deadline = time.monotonic() + COST_LOCK_WAIT_SECONDS
    acquired = False
    while not acquired:
        try:
            descriptor = os.open(COST_LOCK_PATH, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(json.dumps({"pid": os.getpid(), "createdAtUtc": utc_now()}))
            acquired = True
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(COST_LOCK_PATH) > COST_LOCK_STALE_SECONDS:
                    os.remove(COST_LOCK_PATH)
                    continue
            except FileNotFoundError:
                continue
            if time.monotonic() >= deadline:
                break
            time.sleep(0.1)
    try:
        yield acquired
    finally:
        if acquired:
            with contextlib.suppress(FileNotFoundError):
                os.remove(COST_LOCK_PATH)


def cached_cost_evidence(cached, reason):
    age = age_seconds(cached["capturedAtUtc"])
    if age is None or age > COST_CACHE_MAX_STALE_SECONDS:
        return None
    actual = copy.deepcopy(cached["actualCost"])
    actual["status"] = "available"
    actual["detail"] = f"Last-known-good billed ActualCost served from cache because {reason}"
    actual["capturedAtUtc"] = cached["capturedAtUtc"]
    actual["freshness"] = "cached"
    actual["cacheAgeMinutes"] = round(age / 60, 1)
    forecast = copy.deepcopy(cached.get("forecast") or source("unsupported", "No cached forecast is available."))
    if forecast.get("status") == "available":
        forecast["detail"] = f"Last-known-good forecast served from the same cache because {reason}"
        forecast["capturedAtUtc"] = cached["capturedAtUtc"]
        forecast["freshness"] = "cached"
        forecast["cacheAgeMinutes"] = round(age / 60, 1)
    return {
        "actual": actual,
        "forecast": forecast,
        "capturedAtUtc": cached["capturedAtUtc"],
        "freshnessStatus": "cached",
        "freshnessDetail": reason,
        "cacheAgeMinutes": round(age / 60, 1),
    }


def unavailable_cost_evidence(error, *, concurrent=False):
    detail = str(error)
    return {
        "actual": source("unavailable", detail),
        "forecast": source(
            "skipped",
            "Forecast was not queried because another cost query is already running."
            if concurrent
            else "Forecast was not queried after ActualCost failed; this avoids cascading Cost Management requests.",
        ),
        "capturedAtUtc": None,
        "freshnessStatus": "unavailable",
        "freshnessDetail": detail,
        "cacheAgeMinutes": None,
    }


def get_cost_evidence(token):
    with COST_QUERY_LOCK:
        cached = load_cost_cache()
        if cached and age_seconds(cached["capturedAtUtc"]) <= COST_CACHE_TTL_SECONDS:
            return cached_cost_evidence(cached, "the successful cost snapshot is still within the cache TTL.")

        with cost_query_guard() as acquired:
            cached = load_cost_cache()
            if cached and age_seconds(cached["capturedAtUtc"]) <= COST_CACHE_TTL_SECONDS:
                return cached_cost_evidence(cached, "another request refreshed the cost snapshot.")
            if not acquired:
                fallback = cached_cost_evidence(cached, "another Cost Management query is in progress.") if cached else None
                return fallback or unavailable_cost_evidence(
                    "Another Cost Management query is in progress and no last-known-good cache exists.",
                    concurrent=True,
                )

            captured_at = utc_now()
            try:
                actual = source(
                    "available",
                    **normalized_cost(cost_query(token, "query", "ActualCost")),
                    capturedAtUtc=captured_at,
                    freshness="live",
                )
            except Exception as error:
                fallback = cached_cost_evidence(cached, f"the live ActualCost query failed: {error}") if cached else None
                return fallback or unavailable_cost_evidence(error)

            try:
                forecast = source(
                    "available",
                    **normalized_cost(cost_query(token, "forecast", "ActualCost")),
                    capturedAtUtc=captured_at,
                    freshness="live",
                )
            except Exception as error:
                forecast = source("unsupported", str(error), capturedAtUtc=captured_at, freshness="live")
            save_cost_cache(captured_at, actual, forecast)
            return {
                "actual": actual,
                "forecast": forecast,
                "capturedAtUtc": captured_at,
                "freshnessStatus": "live",
                "freshnessDetail": "Cost Management returned a new billed snapshot.",
                "cacheAgeMinutes": 0,
            }


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
    cost = get_cost_evidence(token)
    actual = cost["actual"]
    forecast = cost["forecast"]
    budgets = anomalies = advisor = consumption = None
    unsupported = []
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
        "schemaVersion": 2,
        "scope": {"subscriptionId": SUBSCRIPTION_ID, "resourceGroup": RESOURCE_GROUP, "resourceId": SCOPE},
        "capturedAtUtc": captured,
        "freshness": {
            "status": cost["freshnessStatus"],
            "maxAgeMinutes": 5 if cost["freshnessStatus"] == "live" else round(COST_CACHE_MAX_STALE_SECONDS / 60),
            "costCapturedAtUtc": cost["capturedAtUtc"],
            "costCacheAgeMinutes": cost["cacheAgeMinutes"],
            "detail": cost["freshnessDetail"],
        },
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
