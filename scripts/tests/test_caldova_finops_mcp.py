import importlib.util
import io
import json
import os
import pathlib
import sys
import tempfile
import unittest
import urllib.error
from unittest import mock


SCRIPT_PATH = pathlib.Path(__file__).resolve().parents[1] / "caldova-finops-mcp.py"


class JsonResponse:
    def __init__(self, value):
        self.value = value

    def __enter__(self):
        return io.StringIO(json.dumps(self.value))

    def __exit__(self, *_):
        return False


def http_error(status, headers=None):
    return urllib.error.HTTPError(
        "https://management.azure.com/cost",
        status,
        "failure",
        headers or {},
        io.BytesIO(b'{"error":{"message":"throttled"}}'),
    )


class CaldovaFinOpsTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        cache_path = os.path.join(self.temporary_directory.name, "cost-cache.json")
        environment = {
            "CALDOVA_SUBSCRIPTION_ID": "sub-test",
            "CALDOVA_RESOURCE_GROUP": "rg-caldova-test",
            "CALDOVA_EXPECTED_RESOURCE_GROUP": "rg-caldova-test",
            "CALDOVA_COST_CACHE_PATH": cache_path,
            "CALDOVA_COST_LOCK_WAIT_SECONDS": "0",
            "CALDOVA_HTTP_MAX_RETRY_SECONDS": "10",
        }
        self.environment = mock.patch.dict(os.environ, environment, clear=False)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        name = f"caldova_finops_mcp_test_{id(self)}"
        specification = importlib.util.spec_from_file_location(name, SCRIPT_PATH)
        self.module = importlib.util.module_from_spec(specification)
        sys.modules[name] = self.module
        self.addCleanup(sys.modules.pop, name, None)
        specification.loader.exec_module(self.module)

    def seed_cache(self, *, captured_at=None):
        captured = captured_at or self.module.utc_now()
        actual = self.module.source(
            "available",
            total=12.5,
            currency="USD",
            columns=["PreTaxCost", "Currency"],
            rows=[[12.5, "USD"]],
            capturedAtUtc=captured,
            freshness="live",
        )
        forecast = self.module.source("unsupported", "Insufficient history.", capturedAtUtc=captured, freshness="live")
        self.module.save_cost_cache(captured, actual, forecast)

    def test_request_json_retries_with_cost_management_retry_header(self):
        throttled = http_error(
            429,
            {
                "x-ms-ratelimit-microsoft.costmanagement-qpu-remaining": "QueriesPerHour:2,QueriesPer10Sec:0",
                "x-ms-ratelimit-microsoft.costmanagement-qpu-retry-after": "2",
            },
        )
        with (
            mock.patch.object(self.module.urllib.request, "urlopen", side_effect=[throttled, JsonResponse({"ok": True})]) as urlopen,
            mock.patch.object(self.module.time, "sleep") as sleep,
        ):
            result = self.module.request_json("https://management.azure.com/cost")
        self.assertEqual({"ok": True}, result)
        self.assertEqual(2, urlopen.call_count)
        sleep.assert_called_once_with(2.0)

    def test_request_json_does_not_retry_exhausted_hourly_quota(self):
        throttled = http_error(
            429,
            {
                "x-ms-ratelimit-microsoft.costmanagement-qpu-remaining": "QueriesPerHour:0,QueriesPerMin:8,QueriesPer10Sec:0",
                "x-ms-ratelimit-microsoft.costmanagement-qpu-retry-after": "2",
            },
        )
        with (
            mock.patch.object(self.module.urllib.request, "urlopen", side_effect=throttled) as urlopen,
            mock.patch.object(self.module.time, "sleep") as sleep,
        ):
            with self.assertRaises(self.module.HttpRequestError) as raised:
                self.module.request_json("https://management.azure.com/cost")
        self.assertIn("QueriesPerHour:0", str(raised.exception))
        self.assertEqual(1, urlopen.call_count)
        sleep.assert_not_called()

    def test_successful_cost_snapshot_is_cached(self):
        actual = {
            "columns": ["PreTaxCost", "Currency"],
            "rows": [[9.25, "USD"]],
        }
        forecast = {
            "columns": ["PreTaxCost", "Currency"],
            "rows": [[11.75, "USD"]],
        }
        with mock.patch.object(self.module, "cost_query", side_effect=[actual, forecast]) as cost_query:
            first = self.module.get_cost_evidence("token")
            second = self.module.get_cost_evidence("token")
        self.assertEqual("live", first["freshnessStatus"])
        self.assertEqual("cached", second["freshnessStatus"])
        self.assertEqual(9.25, second["actual"]["total"])
        self.assertEqual("available", second["actual"]["status"])
        self.assertIn("within the cache TTL", second["actual"]["detail"])
        self.assertEqual(2, cost_query.call_count)

    def test_throttled_actual_uses_last_known_good_and_skips_forecast(self):
        self.seed_cache()
        self.module.COST_CACHE_TTL_SECONDS = -1
        throttled = self.module.HttpRequestError(
            429,
            "POST",
            "https://management.azure.com/cost",
            "throttled",
            {"x-ms-ratelimit-microsoft.costmanagement-qpu-remaining": "QueriesPerHour:0"},
        )
        with mock.patch.object(self.module, "cost_query", side_effect=throttled) as cost_query:
            evidence = self.module.get_cost_evidence("token")
        self.assertEqual("cached", evidence["freshnessStatus"])
        self.assertEqual("available", evidence["actual"]["status"])
        self.assertEqual(12.5, evidence["actual"]["total"])
        self.assertIn("Last-known-good billed ActualCost", evidence["actual"]["detail"])
        self.assertEqual(1, cost_query.call_count)

    def test_concurrent_query_uses_cache_without_duplicate_call(self):
        self.seed_cache()
        self.module.COST_CACHE_TTL_SECONDS = -1
        pathlib.Path(self.module.COST_LOCK_PATH).write_text("busy", encoding="utf-8")
        with mock.patch.object(self.module, "cost_query") as cost_query:
            evidence = self.module.get_cost_evidence("token")
        self.assertEqual("cached", evidence["freshnessStatus"])
        self.assertIn("another Cost Management query is in progress", evidence["actual"]["detail"])
        cost_query.assert_not_called()

    def test_throttled_without_cache_never_reports_zero(self):
        throttled = self.module.HttpRequestError(429, "POST", "url", "throttled", {})
        with mock.patch.object(self.module, "cost_query", side_effect=throttled) as cost_query:
            evidence = self.module.get_cost_evidence("token")
        self.assertEqual("unavailable", evidence["actual"]["status"])
        self.assertNotIn("total", evidence["actual"])
        self.assertEqual("skipped", evidence["forecast"]["status"])
        self.assertEqual(1, cost_query.call_count)

    def test_mcp_initialize_list_and_call_smoke(self):
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
            {
                "jsonrpc": "2.0",
                "id": 3,
                "method": "tools/call",
                "params": {"name": "get_caldova_finops", "arguments": {}},
            },
        ]
        standard_input = io.StringIO("".join(json.dumps(message) + "\n" for message in messages))
        standard_output = io.StringIO()
        result = {"schemaVersion": 2, "capturedAtUtc": "2026-10-14T12:00:00Z", "actualCost": {"status": "available"}}
        with (
            mock.patch.object(self.module.sys, "stdin", standard_input),
            mock.patch.object(self.module.sys, "stdout", standard_output),
            mock.patch.object(self.module, "get_finops", return_value=result),
        ):
            self.module.main()
        responses = [json.loads(line) for line in standard_output.getvalue().splitlines()]
        self.assertEqual("caldova-finops", responses[0]["result"]["serverInfo"]["name"])
        self.assertEqual("get_caldova_finops", responses[1]["result"]["tools"][0]["name"])
        self.assertFalse(responses[2]["result"]["isError"])
        self.assertEqual(result, responses[2]["result"]["structuredContent"])


if __name__ == "__main__":
    unittest.main()
