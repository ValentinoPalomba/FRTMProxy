"""Exercise the shipped bridge and engine with real local HTTP/TLS/stream/WS clients.

No system proxy or trust-store settings are changed. All certificates/state live in a temp folder.
Run after building: python3 tests/integration_proxy.py --worker /absolute/path/to/FRTMProxy
"""
import argparse
import base64
import hashlib
import fcntl
import http.client
import json
import os
from pathlib import Path
import queue
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
WORKER = None


class Fixture(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        result = json.dumps({"body": base64.b64encode(body).decode(),
                             "duplicates": self.headers.get_all("X-Duplicate"),
                             "empty": self.headers.get("X-Empty"),
                             "contentLength": self.headers.get_all("Content-Length")}).encode()
        self.send_header("Content-Length", str(len(result)))
        self.end_headers()
        self.wfile.write(result)

    def do_GET(self):
        if self.path == "/ws":
            key = self.headers["Sec-WebSocket-Key"]
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            self.wfile.write(b"\x81\x05hello\x88\x02\x03\xe8")
            self.wfile.flush()
            self.close_connection = True
            return
        if self.path in ("/sse", "/ndjson"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream" if self.path == "/sse" else "application/x-ndjson")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for index in range(3):
                time.sleep(0.2)
                payload = (f'data: {{"index":{index},"text":"caffè"}}\n\n' if self.path == "/sse" else f'{{"index":{index}}}\n').encode()
                self.wfile.write(f"{len(payload):x}\r\n".encode() + payload + b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
            return
        if self.path == "/slow":
            time.sleep(3)
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/echo")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path.startswith("/stress-small/"):
            body = json.dumps({"path": self.path}).encode().ljust(1024, b" ")
        elif self.path.startswith("/stress-large/"):
            body = b"x" * (2 * 1024 * 1024 + 7)
        elif self.path == "/multiline":
            body = b"first\n\nsecond\r\n\r\nthird"
        elif self.path == "/large":
            body = b"x" * (2 * 1024 * 1024 + 7)
        else:
            body = json.dumps({"path": self.path, "marker": self.headers.get("X-Script", "")}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Set-Cookie", "first=1")
        self.send_header("Set-Cookie", "second=2")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Cancellation is expected to disconnect a slow client.


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class ProxyIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="frtmproxy-test-")
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.bodies = Path(cls.temp.name) / "bodies"
        cls.bodies.mkdir(mode=0o700)
        cls.origin = cls.server.server_port
        cls.port = free_port()
        cls.events = queue.Queue()
        cls.history = []
        environment = dict(os.environ, FRTMPROXY_STARTUP_ID="integration", FRTMPROXY_SCRIPT_WORKER=WORKER or "", FRTMPROXY_BODY_DIRECTORY=str(cls.bodies), FRTMPROXY_BODY_KEY=base64.b64encode(bytes(32)).decode())
        # Never inherit a recovery parent from a development app invocation.
        environment.pop("FRTMPROXY_PARENT_PID", None)
        resources = Path(WORKER).resolve().parent.parent / "Resources" if WORKER else ROOT / "FRTMProxy/Resources"
        bridge = resources / "bridge.py" if WORKER else ROOT / "FRTMProxy/bridge.py"
        cls.process = subprocess.Popen([str(resources / "mitmproxy.app/Contents/MacOS/mitmdump"), "-q", "-p", str(cls.port),
            "-s", str(bridge), "--set", f"confdir={cls.temp.name}",
            "--set", "ssl_insecure=false", "--set", "connection_strategy=lazy"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment, text=True)

        def collect():
            for line in cls.process.stdout:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                cls.events.put(event)

        threading.Thread(target=collect, daemon=True).start()
        try:
            cls.wait_event(lambda e: e.get("event") == "proxy_ready")
        except Exception:
            cls.process.terminate()
            cls.process.wait(timeout=5)
            diagnostic = cls.process.stderr.read()
            cls.server.shutdown()
            cls.server.server_close()
            cls.temp.cleanup()
            raise AssertionError("Proxy failed to start: " + diagnostic)


    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        try:
            cls.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait()
        cls.server.shutdown()
        cls.server.server_close()
        for stream in (cls.process.stdin, cls.process.stdout, cls.process.stderr):
            stream.close()
        cls.temp.cleanup()

    @classmethod
    def wait_event(cls, predicate, timeout=45):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                event = cls.events.get(timeout=max(0.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            cls.history.append(event)
            if predicate(event):
                return event
        raise AssertionError("Expected bridge event did not arrive")

    def configure(self, actions, matcher=None):
        revision = time.time_ns()
        rules = [{"id": "fixture", "priority": 0, "isEnabled": True, "matcher": matcher or {}, "actions": actions}] if actions else []
        self.process.stdin.write(json.dumps({"type": "replace_rules", "revision": revision, "document": {"rules": rules}}) + "\n")
        self.process.stdin.flush()
        self.wait_event(lambda e: e.get("event") == "rules_ack" and e.get("revision") == revision)

    def fetch(self, path):
        client = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        client.request("GET", f"http://127.0.0.1:{self.origin}{path}")
        response = client.getresponse()
        status, body = response.status, response.read()
        client.close()
        event = self.wait_event(lambda e: e.get("event") == "response" and path in (e.get("request") or {}).get("url", ""))
        return status, body, event

    def test_localhost_and_duplicate_headers(self):
        self.configure([])
        status, body, event = self.fetch("/echo")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["path"], "/echo")
        cookies = [h["value"] for h in event["response"]["headerFields"] if h["name"].lower() == "set-cookie"]
        self.assertEqual(cookies, ["first=1", "second=2"])
        self.assertEqual(event["response"]["httpVersion"], "HTTP/1.1")

    def composer_probe(self, url, proxy=True, check=True, **options):
        if not WORKER:
            self.skipTest("Composer client probe requires a built Debug app")
        payload = {"url": url}
        if proxy:
            pem = Path(self.temp.name) / "mitmproxy-ca-cert.pem"
            der = ssl.PEM_cert_to_DER_cert(pem.read_text())
            payload.update(proxyPort=self.port, certificate=base64.b64encode(der).decode())
        payload.update(options)
        completed = subprocess.run([WORKER, "--composer-probe"], input=json.dumps(payload).encode(),
                                   capture_output=True, timeout=15)
        if check:
            self.assertEqual(completed.returncode, 0, completed.stderr.decode())
            return json.loads(completed.stdout)
        return completed

    def test_composer_uses_proxy_and_preserves_body(self):
        self.configure([])
        result = self.composer_probe(f"http://127.0.0.1:{self.origin}/multiline")
        self.assertEqual(base64.b64decode(result["body"]), b"first\n\nsecond\r\n\r\nthird")
        self.assertEqual(result["status"], 200)
        self.assertEqual([field["value"] for field in result["headerFields"] if field["name"].lower() == "set-cookie"], ["first=1", "second=2"])
        event = self.wait_event(lambda e: e.get("event") == "response" and "/multiline" in e.get("request", {}).get("url", ""))
        self.assertEqual(event["response"]["status"], 200)
        large = self.composer_probe(f"http://127.0.0.1:{self.origin}/large")
        self.assertEqual(len(base64.b64decode(large["body"])), 2 * 1024 * 1024)
        self.assertEqual(large["byteCount"], 2 * 1024 * 1024 + 7)

    def test_composer_cancellation_routing_failure_and_redirect(self):
        self.configure([])
        start = time.monotonic()
        cancelled = self.composer_probe(f"http://127.0.0.1:{self.origin}/slow", check=False, cancelAfterMillis=150)
        self.assertNotEqual(cancelled.returncode, 0)
        self.assertLess(time.monotonic() - start, 2)
        broken_proxy = self.composer_probe(f"http://127.0.0.1:{self.origin}/echo", check=False, proxyPort=free_port())
        self.assertNotEqual(broken_proxy.returncode, 0)
        redirect = self.composer_probe(f"http://127.0.0.1:{self.origin}/redirect")
        self.assertEqual(redirect["status"], 302)

    def test_composer_replays_binary_and_duplicate_request_headers(self):
        self.configure([])
        original = bytes(range(256)) + b"\x00\r\n\r\n"
        result = self.composer_probe(f"http://127.0.0.1:{self.origin}/echo", method="POST",
            body=base64.b64encode(original).decode(), bodyIsBase64=True,
            headerFields=[{"name": "X-Duplicate", "value": "first"}, {"name": "X-Duplicate", "value": "second"},
                          {"name": "X-Empty", "value": ""}, {"name": "Content-Length", "value": "999999"},
                          {"name": "Transfer-Encoding", "value": "chunked"}])
        echoed = json.loads(base64.b64decode(result["body"]))
        self.assertEqual(base64.b64decode(echoed["body"]), original)
        self.assertEqual(echoed["duplicates"], ["first", "second"])
        self.assertEqual(echoed["empty"], "")
        self.assertEqual(echoed["contentLength"], [str(len(original))])
        literal = self.composer_probe(f"http://127.0.0.1:{self.origin}/a/../echo?ids[0]=1")
        self.assertEqual(json.loads(base64.b64decode(literal["body"]))["path"], "/a/../echo?ids[0]=1")

    def test_header_matcher_wildcard_and_case_sensitivity(self):
        actions = [{"type": "mock", "configuration": {"status": 202, "body": "matched", "headers": {}}}]
        def send(value):
            return self.composer_probe(f"http://127.0.0.1:{self.origin}/header-match",
                headerFields=[{"name": "x-environment", "value": value}])
        matcher = {"headers": [{"name": "X-Environment", "value": {
            "mode": "wildcard", "value": "stage*", "isCaseSensitive": False}}]}
        self.configure(actions, matcher)
        self.assertEqual(send("STAGE-DEV")["status"], 202)
        self.assertEqual(send("production")["status"], 200)
        matcher["headers"][0]["value"]["isCaseSensitive"] = True
        self.configure(actions, matcher)
        self.assertEqual(send("STAGE-DEV")["status"], 200)
        self.assertEqual(send("stage-dev")["status"], 202)

    def test_body_storage_is_leased_for_active_capture(self):
        with (self.bodies / ".capture.lock").open("rb") as lease:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(lease.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_mock_is_observed_by_the_client(self):
        self.configure([{"type": "mock", "configuration": {"status": 202, "body": "mocked", "headers": {}}}])
        status, body, _ = self.fetch("/mock")
        self.assertEqual((status, body), (202, b"mocked"))
        self.configure([{"type": "mock", "configuration": {"status": 201,
            "body": "data:application/octet-stream;base64,AP8B", "headers": {}}}])
        status, body, _ = self.fetch("/mock-binary")
        self.assertEqual((status, body), (201, b"\x00\xff\x01"))

    def test_live_sse_and_ndjson(self):
        self.configure([])
        for path in ("/sse", "/ndjson"):
            _, body, terminal = self.fetch(path)
            streams = [e for e in self.history if e.get("id") == terminal["id"] and e.get("event") == "response_stream"]
            self.assertTrue(streams)
            self.assertTrue(all(e["id"] == terminal["id"] for e in streams))
            self.assertEqual(terminal["response"]["body"].encode(), body)
            self.assertEqual(terminal["response"]["byteCount"], len(body))
            self.assertIsNone(streams[0]["responseTimestamp"])
            self.assertLess(streams[0]["timestamp"], terminal["timestamp"])

    def test_large_preview_is_explicitly_truncated(self):
        self.configure([])
        _, body, event = self.fetch("/large")
        self.assertEqual(len(body), 2 * 1024 * 1024 + 7)
        self.assertTrue(event["response"]["bodyTruncated"])
        self.assertLessEqual(len(event["response"]["body"].encode()), 2 * 1024 * 1024)
        reference = event["response"]["originalBodyReference"]
        stored = (self.bodies / reference).read_bytes()
        self.assertEqual(len(stored), len(body) + 28)
        self.assertNotIn(b"x" * 100, stored)
        self.assertEqual((self.bodies / reference).stat().st_mode & 0o777, 0o600)

    def test_scripts_modify_current_request_and_response(self):
        if not WORKER:
            self.skipTest("Pass --worker to test JavaScriptCore")
        self.configure([{"type": "script", "configuration": {"source":
            "function onRequest(flow) { return {headers: {'X-Script':'yes'}}; } "
            "function onResponse(flow) { return {status:201,body:flow.response.body+' transformed'}; }",
            "responseOnly": False}}])
        status, body, event = self.fetch("/script")
        self.assertEqual(status, 201)
        self.assertIn(b'"marker": "yes"', body)
        self.assertTrue(body.endswith(b" transformed"))
        self.assertEqual(event["response"]["body"].encode(), body)

    def test_infinite_script_times_out_and_proxy_survives(self):
        if not WORKER:
            self.skipTest("Pass --worker to test JavaScriptCore")
        self.configure([{"type": "script", "configuration": {"source": "function transform(flow){while(true){}}", "responseOnly": True}}])
        start = time.monotonic()
        status, _, terminal = self.fetch("/infinite")
        self.assertEqual(status, 200)
        self.assertLess(time.monotonic() - start, 6)
        self.assertTrue(any(e.get("id") == terminal["id"] and e.get("event") == "script_error" for e in self.history))
        self.configure([])
        self.assertEqual(self.fetch("/healthy")[0], 200)

    def test_websocket_frame_and_close_are_captured(self):
        self.configure([])
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as client:
            client.sendall((f"GET http://127.0.0.1:{self.origin}/ws HTTP/1.1\r\nHost: 127.0.0.1:{self.origin}\r\n"
                "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
                "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n").encode())
            received = b""
            while b"hello" not in received:
                received += client.recv(4096)
            # Masked close acknowledgement, as required from clients.
            client.sendall(b"\x88\x82\x00\x00\x00\x00\x03\xe8")
        event = self.wait_event(lambda e: e.get("event") == "websocket_message")
        self.assertEqual(event["websocket_message"]["content"], "hello")
        self.wait_event(lambda e: e.get("event") == "websocket_end" and e.get("id") == event["id"])

    def test_untrusted_upstream_certificate_is_rejected(self):
        self.configure([])
        cert, key = Path(self.temp.name) / "invalid.pem", Path(self.temp.name) / "invalid.key"
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-keyout", str(key), "-out", str(cert)], check=True, capture_output=True)
        tls = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        tls.socket = context.wrap_socket(tls.socket, server_side=True)
        threading.Thread(target=tls.serve_forever, daemon=True).start()
        try:
            client_context = ssl.create_default_context(cafile=str(Path(self.temp.name) / "mitmproxy-ca-cert.pem"))
            client = http.client.HTTPSConnection("127.0.0.1", self.port, context=client_context, timeout=10)
            client.set_tunnel("127.0.0.1", tls.server_port)
            client.request("GET", "/untrusted")
            response = client.getresponse()
            self.assertEqual(response.status, 502)
            result = self.composer_probe(f"https://127.0.0.1:{tls.server_port}/untrusted")
            self.assertEqual(result["status"], 502)
            rejected = self.composer_probe(f"https://127.0.0.1:{tls.server_port}/untrusted", proxy=False, check=False)
            self.assertNotEqual(rejected.returncode, 0)
            response.read()
            client.close()
        finally:
            tls.shutdown()
            tls.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker")
    arguments = parser.parse_args()
    WORKER = arguments.worker
    unittest.main(argv=[__file__, "-v"])
