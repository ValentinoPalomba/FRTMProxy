"""Local upstream routing/auth checks using the unmodified embedded engine.

No system proxy or trust-store settings are changed.
Run: python3 tests/integration_upstream_proxy.py
"""
import base64
import http.client
import json
import os
from pathlib import Path
import select
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
AUTH = "Basic " + base64.b64encode(b"alice:secret:password").decode()


class Origin(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        body = json.dumps({"route": "direct", "auth": self.headers.get("Proxy-Authorization")}).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Upstream(Origin):
    def do_GET(self):
        self.server.requests.append(("GET", self.headers.get("Proxy-Authorization")))
        body = b'{"route":"upstream"}'
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_CONNECT(self):
        self.server.requests.append(("CONNECT", self.headers.get("Proxy-Authorization")))
        host, port = self.path.rsplit(":", 1)
        with socket.create_connection((host, int(port)), timeout=5) as target:
            self.send_response(200)
            self.end_headers()
            sockets = [self.connection, target]
            while True:
                ready, _, _ = select.select(sockets, [], [], 5)
                if not ready:
                    return
                for source in ready:
                    data = source.recv(65536)
                    if not data:
                        return
                    (target if source is self.connection else self.connection).sendall(data)


def server(handler, context=None):
    instance = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    instance.daemon_threads = True
    instance.requests = []
    if context:
        instance.socket = context.wrap_socket(instance.socket, server_side=True)
    threading.Thread(target=instance.serve_forever, daemon=True).start()
    return instance


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class UpstreamIntegrationTests(unittest.TestCase):
    def test_http_and_https_upstreams(self):
        with tempfile.TemporaryDirectory(prefix="frtm-upstream-") as directory:
            cert = Path(directory) / "cert.pem"
            key = Path(directory) / "key.pem"
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                            "-subj", "/CN=localhost", "-keyout", str(key), "-out", str(cert)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.load_cert_chain(cert, key)
            origin = server(Origin)
            secure_origin = server(Origin, tls)
            self.addCleanup(origin.server_close)
            self.addCleanup(origin.shutdown)
            self.addCleanup(secure_origin.server_close)
            self.addCleanup(secure_origin.shutdown)
            for scheme in ["http", "https"]:
                with self.subTest(scheme=scheme):
                    self.check_routes(directory, scheme, tls, origin, secure_origin)
            self.check_routes(directory, "http", tls, origin, secure_origin, ignored=True)

    def check_routes(self, directory, scheme, tls, origin, secure_origin, ignored=False):
        upstream = server(Upstream, tls if scheme == "https" else None)
        self.addCleanup(upstream.server_close)
        self.addCleanup(upstream.shutdown)
        port = free_port()
        environment = dict(os.environ, FRTMPROXY_UPSTREAM=json.dumps({"bypass": " LOCALHOST, *.local ", "auth": "alice:secret:password"}))
        environment.pop("FRTMPROXY_PARENT_PID", None)
        # Keep stdin open, as in the app, and collect stdout to check redaction.
        process = subprocess.Popen([str(ROOT / "FRTMProxy/Resources/mitmproxy.app/Contents/MacOS/mitmdump"),
                                    "-q", "-p", str(port), "-s", str(ROOT / "FRTMProxy/bridge.py"),
                                    "--mode", f"upstream:{scheme}://127.0.0.1:{upstream.server_port}",
                                    "--set", f"confdir={directory}", "--set", "connection_strategy=lazy",
                                    "--set", "ssl_insecure=true"] + (["--set", f"ignore_hosts=localhost:{secure_origin.server_port}"] if ignored else []), env=environment,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        events = []
        reader = threading.Thread(target=lambda: events.extend(iter(process.stdout.readline, "")), daemon=True)
        reader.start()
        try:
            deadline = time.monotonic() + 20
            while not any('"proxy_ready"' in line for line in events):
                if process.poll() is not None or time.monotonic() > deadline:
                    raise AssertionError("Upstream fixture failed to start")
                time.sleep(0.05)
            # Alternate hosts on one client connection to detect stale routing.
            client = http.client.HTTPConnection("127.0.0.1", port, timeout=8)
            for host, expected in [("127.0.0.1", "upstream"), ("localhost", "direct"), ("127.0.0.1", "upstream")]:
                client.request("GET", f"http://{host}:{origin.server_port}/echo")
                response = client.getresponse()
                self.assertEqual(response.status, 200)
                body = json.loads(response.read())
                self.assertEqual(body["route"], expected)
                self.assertIsNone(body.get("auth"))
            client.close()
            for host, expected_connects in [("127.0.0.1", 1), ("localhost", 1)]:
                client = http.client.HTTPSConnection("127.0.0.1", port, timeout=8,
                                                    context=ssl._create_unverified_context())
                client.set_tunnel(host, secure_origin.server_port)
                client.request("GET", "/echo")
                response = client.getresponse()
                payload = response.read()
                self.assertEqual(response.status, 200, payload)
                self.assertIsNone(json.loads(payload)["auth"])
                client.close()
                self.assertEqual(sum(method == "CONNECT" for method, _ in upstream.requests), expected_connects)
            self.assertEqual(len(upstream.requests), 3)
            self.assertTrue(all(auth == AUTH for _, auth in upstream.requests))
        finally:
            process.terminate()
            process.wait(timeout=10)
            reader.join(timeout=2)
            diagnostic = process.stderr.read()
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()
        self.assertNotIn(AUTH, "".join(events))
        self.assertNotIn("secret:password", "".join(events))
        self.assertNotIn("Traceback", diagnostic)


if __name__ == "__main__":
    unittest.main()
