import asyncio
import importlib.util
import pathlib
import tempfile
import sys
import types
import unittest
from unittest.mock import patch


class FakeResponse:
    @staticmethod
    def make(status, body, headers):
        return types.SimpleNamespace(status_code=status, body=body, headers=headers, set_text=lambda value: None)


mitmproxy = types.ModuleType("mitmproxy")
mitmproxy.http = types.SimpleNamespace(HTTPFlow=object, Response=FakeResponse)
mitmproxy.ctx = types.SimpleNamespace(log=types.SimpleNamespace(info=lambda *_: None, error=lambda *_: None))
sys.modules.setdefault("mitmproxy", mitmproxy)

bridge_path = pathlib.Path(__file__).parents[1] / "FRTMProxy" / "bridge.py"
spec = importlib.util.spec_from_file_location("frtm_bridge", bridge_path)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class FakeHeaders(dict):
    def clear(self):
        super().clear()


class FakeRequest:
    def __init__(self):
        self.scheme = "https"
        self.host = "api.example.com"
        self.path = "/users?b=2&a=1"
        self.method = "GET"
        self.pretty_url = "https://api.example.com/users?b=2&a=1"
        self.headers = FakeHeaders({"content-type": "application/json"})
        self._body = "{}"

    def get_text(self, strict=True):
        return self._body

    def set_text(self, value):
        self._body = value

    @property
    def url(self):
        return self.pretty_url

    @url.setter
    def url(self, value):
        self.pretty_url = value
        from urllib.parse import urlsplit
        parts = urlsplit(value)
        self.scheme = parts.scheme
        self.host = parts.hostname
        self.path = parts.path + (("?" + parts.query) if parts.query else "")


class FakeFlow:
    def __init__(self):
        self.id = "flow-1"
        self.request = FakeRequest()
        self.response = None
        self.metadata = {}


class UnifiedRulesTests(unittest.TestCase):
    def setUp(self):
        bridge.TRAFFIC_RULES = []
        bridge.FLOW_BY_ID.clear()
        bridge.FLOW_BY_KEY.clear()
        bridge.FLOW_BY_MAP_LOCAL_KEY.clear()

    def test_pruning_keeps_paused_flow_but_remains_bounded(self):
        for index in range(bridge.MAX_TRACKED_FLOWS + 2):
            flow = FakeFlow()
            flow.id = str(index)
            flow.intercepted = index == 0
            bridge.FLOW_BY_ID[flow.id] = flow
        bridge.prune_flow_maps()
        self.assertEqual(len(bridge.FLOW_BY_ID), bridge.MAX_TRACKED_FLOWS)
        self.assertIn("0", bridge.FLOW_BY_ID)

    def test_body_budget_prunes_before_flow_count_and_preserves_paused(self):
        original_limit = bridge.MAX_TRACKED_BODY_BYTES
        bridge.MAX_TRACKED_BODY_BYTES = 20
        try:
            for index in range(4):
                flow = FakeFlow()
                flow.id = str(index)
                flow.request.path = "/" + str(index)
                flow.request.raw_content = b"x" * 10
                flow.intercepted = index == 0
                bridge.FLOW_BY_ID[flow.id] = flow
                bridge.FLOW_BY_KEY[bridge.flow_key(flow)] = flow
                bridge.FLOW_BY_MAP_LOCAL_KEY[bridge.map_local_key(flow)] = flow
            bridge.prune_flow_maps()
            self.assertEqual(list(bridge.FLOW_BY_ID), ["0", "3"])
            self.assertEqual(sum(bridge.tracked_body_bytes(f) for f in bridge.FLOW_BY_ID.values()), 20)
            self.assertEqual(len(bridge.FLOW_BY_KEY), 2)
            self.assertEqual(len(bridge.FLOW_BY_MAP_LOCAL_KEY), 2)
            output = []
            original_send = bridge.send
            bridge.send = output.append
            try:
                incoming = FakeFlow()
                incoming.id = "incoming"
                incoming.request.raw_content = b"y" * 11
                self.assertFalse(bridge.pause_for_breakpoint(incoming, "request"))
                self.assertIn("memory budget", output[0]["message"])
            finally:
                bridge.send = original_send
        finally:
            bridge.MAX_TRACKED_BODY_BYTES = original_limit

    def test_gc_workaround_only_runs_on_affected_python_after_byte_evictions(self):
        saved = bridge.MAX_TRACKED_BODY_BYTES, bridge.EVICTED_BODY_BYTES, bridge.sys, bridge.gc
        calls = []
        bridge.MAX_TRACKED_BODY_BYTES = 10
        bridge.gc = types.SimpleNamespace(collect=lambda: calls.append(True))
        try:
            for version, expected_calls in [((3, 14, 4), 1), ((3, 14, 5), 1)]:
                bridge.sys = types.SimpleNamespace(version_info=version)
                bridge.EVICTED_BODY_BYTES = 8 * 1024 * 1024
                flow = FakeFlow()
                flow.request.raw_content = b"x" * 20
                bridge.FLOW_BY_ID[flow.id] = flow
                bridge.prune_flow_maps()
                self.assertEqual(len(calls), expected_calls)
                self.assertFalse(bridge.FLOW_BY_ID)
        finally:
            bridge.MAX_TRACKED_BODY_BYTES, bridge.EVICTED_BODY_BYTES, bridge.sys, bridge.gc = saved

    def test_body_quota_scans_only_on_pressure_and_reclaims_deleted_files(self):
        saved = bridge.BODY_STORAGE_USED, bridge.BODY_STORAGE_REFRESH_AT, bridge.BODY_DISK_LIMIT
        try:
            with tempfile.TemporaryDirectory() as root:
                body = pathlib.Path(root, "saved.gcm")
                body.write_bytes(b"x" * 90)
                bridge.BODY_STORAGE_USED = None
                bridge.BODY_STORAGE_REFRESH_AT = 0
                bridge.BODY_DISK_LIMIT = 100
                with patch.object(bridge.os, "scandir", wraps=bridge.os.scandir) as scan:
                    with patch.object(bridge.time, "monotonic", return_value=10):
                        bridge.check_body_storage_capacity(root, 10)
                    with patch.object(bridge.time, "monotonic", return_value=20):
                        for _ in range(1000):
                            bridge.check_body_storage_capacity(root, 10)
                    self.assertEqual(scan.call_count, 1)
                    with patch.object(bridge.time, "monotonic", return_value=20):
                        with self.assertRaises(ValueError):
                            bridge.check_body_storage_capacity(root, 11)
                        with self.assertRaises(ValueError):
                            bridge.check_body_storage_capacity(root, 11)
                    self.assertEqual(scan.call_count, 2)
                    body.unlink()
                    with patch.object(bridge.time, "monotonic", return_value=26):
                        bridge.check_body_storage_capacity(root, 100)
                    self.assertEqual(bridge.BODY_STORAGE_USED, 0)
                    self.assertEqual(scan.call_count, 3)
        finally:
            bridge.BODY_STORAGE_USED, bridge.BODY_STORAGE_REFRESH_AT, bridge.BODY_DISK_LIMIT = saved

    def test_breakpoint_capacity_forwards_without_intercept(self):
        saved = bridge.BREAKPOINT_TIMERS.copy()
        bridge.BREAKPOINT_TIMERS.update({str(i): None for i in range(bridge.MAX_PAUSED_FLOWS)})
        output = []
        original_send = bridge.send
        bridge.send = output.append
        try:
            self.assertFalse(bridge.pause_for_breakpoint(FakeFlow(), "request"))
            self.assertEqual(output[0]["event"], "capture_warning")
        finally:
            bridge.send = original_send
            bridge.BREAKPOINT_TIMERS.clear()
            bridge.BREAKPOINT_TIMERS.update(saved)

    def test_binary_map_local_body_is_decoded_before_forward(self):
        flow = FakeFlow()
        bridge.apply_map_local_response(flow, {"body": "data:application/octet-stream;base64,AP8B", "status": 200})
        self.assertEqual(flow.response.body, b"\x00\xff\x01")

    def test_invalid_regex_never_matches(self):
        pattern = {"mode": "regularExpression", "value": "[", "isCaseSensitive": True}
        self.assertFalse(bridge._pattern_matches(pattern, "anything"))

    def test_matcher_canonicalizes_query(self):
        flow = FakeFlow()
        rule = {
            "matcher": {
                "host": {"mode": "exact", "value": "api.example.com", "isCaseSensitive": False},
                "query": {"mode": "exact", "value": "a=1&b=2", "isCaseSensitive": True},
            }
        }
        self.assertTrue(bridge._rule_matches(rule, flow))

    def test_map_remote_then_mock_is_terminal(self):
        flow = FakeFlow()
        bridge.TRAFFIC_RULES = [{
            "id": "rule-1",
            "isEnabled": True,
            "priority": 10,
            "matcher": {"host": {"mode": "exact", "value": "api.example.com", "isCaseSensitive": False}},
            "actions": [
                {"type": "mapRemote", "configuration": {"destinationURL": "https://staging.example.com/v2", "preservePath": True, "preserveQuery": True}},
                {"type": "mock", "configuration": {"status": 202, "headers": {}, "body": "ok"}},
            ],
        }]
        asyncio.run(bridge.apply_unified_request_rules(flow))
        self.assertEqual(flow.request.pretty_url, "https://staging.example.com/users?b=2&a=1")
        self.assertEqual(flow.response.status_code, 202)
        self.assertEqual(flow.response.headers["X-FRTM-Rule"], "rule-1")

    def test_lower_priority_rule_executes_first(self):
        flow = FakeFlow()
        bridge.TRAFFIC_RULES = [
            {
                "id": "later",
                "isEnabled": True,
                "priority": 20,
                "matcher": {},
                "actions": [{"type": "mock", "configuration": {"status": 220, "headers": {}, "body": "later"}}],
            },
            {
                "id": "first",
                "isEnabled": True,
                "priority": 0,
                "matcher": {},
                "actions": [{"type": "mock", "configuration": {"status": 201, "headers": {}, "body": "first"}}],
            },
        ]

        asyncio.run(bridge.apply_unified_request_rules(flow))

        self.assertEqual(flow.response.status_code, 201)
        self.assertEqual(flow.response.headers["X-FRTM-Rule"], "first")


if __name__ == "__main__":
    unittest.main()
