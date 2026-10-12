import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


SUBSCRIPTION_ID = os.environ["CALDOVA_SUBSCRIPTION_ID"]
RESOURCE_GROUP = os.environ["CALDOVA_RESOURCE_GROUP"]
ALERT_RULE = os.environ.get("CALDOVA_GUIDED_ALERT_RULE", "Course-recommendations-unavailable")
ARM = "https://management.azure.com"
ALERTS_API_VERSION = "2019-03-01"
ALERT_ID_PREFIX = (
    f"/subscriptions/{SUBSCRIPTION_ID}/resourcegroups/{RESOURCE_GROUP}/"
    "providers/microsoft.insights/components/"
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
            content = response.read()
            return json.loads(content) if content else {}
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


def arm_alert(alert_id, *, method="GET", new_state=None, token):
    query = {"api-version": ALERTS_API_VERSION}
    path = alert_id
    if new_state:
        path = f"{path}/changeState"
        query["newState"] = new_state
    return request_json(
        f"{ARM}{path}?{urllib.parse.urlencode(query)}",
        method=method,
        headers={"Authorization": f"Bearer {token}"},
    )


def validate_alert_id(alert_id):
    normalized = str(alert_id or "").lower()
    if not normalized.startswith(ALERT_ID_PREFIX.lower()):
        raise RuntimeError("Alert ID is outside the configured Caldova learner resource group and Application Insights scope.")
    expected_suffix = "/providers/microsoft.alertsmanagement/alerts/"
    if expected_suffix not in normalized or normalized.endswith(expected_suffix):
        raise RuntimeError("Alert ID is not an Alerts Management instance for the guided Application Insights scope.")
    return str(alert_id)


def close_guided_alert(alert_id):
    alert_id = validate_alert_id(alert_id)
    token = managed_identity_token()
    before = arm_alert(alert_id, token=token)
    essentials = before.get("properties", {}).get("essentials", {})
    actual_rule = str(essentials.get("alertRule") or "").split("/")[-1]
    if actual_rule != ALERT_RULE:
        raise RuntimeError(f"Alert rule '{actual_rule or 'unknown'}' is not the permitted guided rule '{ALERT_RULE}'.")
    if essentials.get("monitorCondition") != "Resolved":
        raise RuntimeError("The guided alert cannot be closed until monitorCondition is Resolved.")
    if essentials.get("alertState") != "Closed":
        arm_alert(alert_id, method="POST", new_state="Closed", token=token)
    after = arm_alert(alert_id, token=token)
    final = after.get("properties", {}).get("essentials", {})
    if final.get("alertState") != "Closed":
        raise RuntimeError("Alerts Management did not persist alertState=Closed.")
    return {
        "schemaVersion": 1,
        "capturedAtUtc": utc_now(),
        "scope": {"subscriptionId": SUBSCRIPTION_ID, "resourceGroup": RESOURCE_GROUP},
        "alertId": alert_id,
        "alertRule": actual_rule,
        "monitorCondition": final.get("monitorCondition"),
        "alertState": final.get("alertState"),
        "allowedMutation": "Alerts Management changeState=Closed for the exact resolved guided alert only",
    }


TOOLS = [
    {
        "name": "close_guided_alert",
        "description": "Close the exact resolved Course-recommendations-unavailable alert in the configured Caldova learner resource group.",
        "inputSchema": {
            "type": "object",
            "properties": {"alertId": {"type": "string", "description": "Full Alerts Management alert resource ID."}},
            "required": ["alertId"],
            "additionalProperties": False,
        },
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
                        "serverInfo": {"name": "caldova-guided-alerts", "version": "1.0.0"},
                    },
                )
            elif method == "ping":
                send(identifier, {})
            elif method == "tools/list":
                send(identifier, {"tools": TOOLS})
            elif method == "tools/call":
                params = message.get("params", {})
                arguments = params.get("arguments") or {}
                if params.get("name") != "close_guided_alert" or set(arguments) != {"alertId"}:
                    send(identifier, error={"code": -32602, "message": "Only close_guided_alert with alertId is allowed."})
                    continue
                try:
                    result = close_guided_alert(arguments["alertId"])
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
            print(f"caldova-guided-alerts-mcp error: {error}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
