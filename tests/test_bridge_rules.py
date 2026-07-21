import asyncio
import importlib.util
import pathlib
import sys
import types
import unittest


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

    def get_text(self):
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


class UnifiedRulesTests(unittest.TestCase):
    def setUp(self):
        bridge.TRAFFIC_RULES = []
        bridge.FLOW_BY_ID.clear()
        bridge.FLOW_BY_KEY.clear()
        bridge.FLOW_BY_MAP_LOCAL_KEY.clear()

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
