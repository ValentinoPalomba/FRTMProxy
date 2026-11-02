"""Routing rules that do not require a running engine or network access."""
import types
import unittest
from unittest.mock import patch
from test_bridge_rules import bridge, FakeFlow, mitmproxy


class UpstreamRoutingTests(unittest.TestCase):
    def setUp(self):
        settings = {"bypass": "localhost, *.local, ::1", "auth": "alice:password"}
        for attribute, value in [
            ("UPSTREAM_SETTINGS", settings),
            ("UPSTREAM_BYPASS", ["localhost", "*.local", "::1"]),
        ]:
            patcher = patch.object(bridge, attribute, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(mitmproxy, "connection", types.SimpleNamespace(
            Server=lambda address, via=None: types.SimpleNamespace(address=address, via=via)), create=True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def flow(self):
        flow = FakeFlow()
        flow.request.scheme = "http"
        flow.client_conn = types.SimpleNamespace(proxy_mode=types.SimpleNamespace(scheme="http", address=("proxy.example", 3128)))
        flow.server_conn = types.SimpleNamespace(address=("api.example.com", 80), via=None)
        return flow

    def test_bypass_matches_case_wildcards_ipv6_and_trailing_dot(self):
        for host in ["LOCALHOST", "localhost.", "api.local", "[::1]"]:
            self.assertTrue(bridge.bypass_upstream(host), host)
        for host in ["localhost.example", "api.example", "notlocal"]:
            self.assertFalse(bridge.bypass_upstream(host), host)

    def test_breakpoint_url_edit_drops_auth_and_changes_route(self):
        flow = self.flow()
        bridge.apply_upstream_auth(flow)
        self.assertEqual(flow.server_conn.via, ("http", ("proxy.example", 3128)))
        self.assertIn("Proxy-Authorization", flow.request.headers)
        bridge.apply_request_updates(flow, {"url": "http://localhost/echo"})
        self.assertIsNone(flow.server_conn.via)
        self.assertNotIn("Proxy-Authorization", flow.request.headers)
        bridge.apply_request_updates(flow, {"url": "http://api.example.com/echo"})
        self.assertIn("Proxy-Authorization", flow.request.headers)

    def test_disabled_settings_preserve_regular_routing(self):
        with patch.object(bridge, "UPSTREAM_SETTINGS", {}):
            flow = self.flow()
            original = flow.server_conn
            bridge.apply_upstream_auth(flow)
            self.assertIs(flow.server_conn, original)
            self.assertNotIn("Proxy-Authorization", flow.request.headers)

    def test_capture_header_fields_redact_proxy_auth(self):
        class Headers(dict):
            def items(self, multi=False):
                return super().items()
        fields = bridge.header_fields(Headers({"proxy-authorization": "secret", "X-Test": "keep"}))
        self.assertEqual(fields, [{"name": "X-Test", "value": "keep"}])


if __name__ == "__main__":
    unittest.main()
