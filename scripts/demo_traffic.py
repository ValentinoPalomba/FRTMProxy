#!/usr/bin/env python3
"""Open an isolated Debug instance and populate it with local, mocked demo traffic.

Usage: python3 scripts/demo_traffic.py --app /path/to/Debug/FRTMProxy.app
The app and its owned proxy remain open. No HTTPS, production preferences,
system proxy, certificate installation, or external destinations are used.
"""

import argparse
import concurrent.futures
import http.client
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from urllib.parse import urlencode


HOSTS = (("Intesa", "intesa.demo.test"), ("CheBanca", "chebanca.demo.test"),
         ("Curl", "curl.demo.test"))
STATUSES = (200, 201, 204, 302, 401, 404, 422, 500, 200)


def identifier():
    return str(uuid.uuid4()).upper()


def pattern(value, mode="exact"):
    return {"value": value, "mode": mode, "isCaseSensitive": False}


def fixtures():
    rules, calls, profiles = [], [], []
    for name, host in HOSTS:
        profiles.append({"id": identifier(), "name": name,
                         "members": [{"host": {"_0": host}}]})
        for index, status in enumerate(STATUSES):
            path = f"/api/demo/{index}/status/{status}"
            body = "" if status == 204 else json.dumps({
                "demo": True, "profilo": name, "stato": status,
                "messaggio": "Dati dimostrativi locali: nessun conto o servizio reale.",
                "descrizione": ("Pagamento di prova e verifica dei dettagli della richiesta. " *
                                (80 if index == 8 else 2)),
                "operazioni": [{"id": f"demo-{item}", "importo": 12.5 + item,
                                "valuta": "EUR"} for item in range(5)]
            }, ensure_ascii=False)
            headers = {"Content-Type": "application/json; charset=utf-8",
                       "X-Demo": "FRTMProxy-local", "X-Demo-Profile": name}
            if status == 302:
                headers["Location"] = f"http://{host}/api/demo/0/status/200"
            rules.append({
                "schemaVersion": 1, "id": identifier(),
                "name": f"Demo {name} · {status} · {index + 1}",
                "isEnabled": True, "priority": index,
                "matcher": {"host": pattern(host), "path": pattern(path), "headers": []},
                "actions": [{"type": "mock", "configuration": {
                    "id": identifier(), "status": status, "headers": headers, "body": body}}]
            })
            calls.append((host, path, ("GET", "POST", "PUT", "DELETE")[index % 4], status))
        rules.append({
            "schemaVersion": 1, "id": identifier(), "name": f"Demo {name} · altre API",
            "isEnabled": True, "priority": 1000,
            "matcher": {"host": pattern(host), "path": pattern("/api/*", "wildcard"),
                        "headers": []},
            "actions": [{"type": "mock", "configuration": {
                "id": identifier(), "status": 200,
                "headers": {"Content-Type": "application/json; charset=utf-8",
                            "X-Demo": "FRTMProxy-local"},
                "body": json.dumps({"demo": True, "profilo": name,
                                    "messaggio": "Risposta locale per retry e Composer."})}}]
        })
        calls.extend((host, f"/api/operazioni/{index}", method, 200)
                     for index, method in enumerate(("GET", "POST", "DELETE")))
    return {"schemaVersion": 1, "rules": rules}, calls, {"profiles": profiles}


def write_default(suite, key, kind, value):
    subprocess.run(["/usr/bin/defaults", "write", suite, key, kind, str(value)],
                   check=True, capture_output=True, timeout=5)


def seed(root, port, language):
    document, calls, profiles = fixtures()
    directory = root / "FRTMProxy"
    directory.mkdir()
    (directory / "traffic-rules.json").write_text(
        json.dumps(document, ensure_ascii=False, indent=2), encoding="utf-8")
    settings_suite = "FRTMProxy.Settings.Fixture." + root.name
    for key, kind, value in (
        ("settings.defaultPort", "-int", port), ("settings.autoStart", "-bool", "YES"),
        ("settings.macosProxyOverride", "-bool", "NO"),
        ("settings.restrictInterceptionToActivePinnedHosts", "-bool", "NO"),
        ("settings.theme", "-string", "xcode-light"),
        ("settings.language", "-string", language),
        ("settings.interfaceScale", "-string", "medium")
    ):
        write_default(settings_suite, key, kind, value)
    write_default("FRTMProxy.CaptureProfiles.Fixture." + root.name,
                  "inspector.captureProfiles", "-data", json.dumps(profiles).encode().hex())
    return calls


def request(port, call, index, timeout=10):
    host, path, method, expected = call
    query = urlencode({"demo": "true", "pagina": index, "ricerca": "bonifico di prova",
                       "dettaglio": "solo dati sintetici"})
    body = (json.dumps({"demo": True, "operazione": "pagamento di prova",
                        "importo": 42.50, "riferimento": f"demo-{index}"},
                       ensure_ascii=False).encode() if method in ("POST", "PUT") else b"")
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        connection.putrequest(method, f"http://{host}{path}?{query}",
                              skip_host=True, skip_accept_encoding=True)
        for key, value in (("Host", host), ("X-Demo", "FRTMProxy-local"),
                           ("X-Request-ID", f"demo-{index}"),
                           ("X-Demo-Tag", "prima"), ("X-Demo-Tag", "seconda"),
                           ("Content-Type", "application/json; charset=utf-8"),
                           ("Content-Length", str(len(body)))):
            connection.putheader(key, value)
        connection.endheaders(body)
        response = connection.getresponse()
        response.read()
        if response.status != expected or response.getheader("X-Demo") != "FRTMProxy-local":
            raise RuntimeError(f"{method} {host}{path}: expected local mock {expected}, "
                               f"received {response.status}")
    finally:
        connection.close()


def engine_is_isolated(app_pid, root):
    processes = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,command="],
                               capture_output=True, text=True, check=True, timeout=3).stdout
    for line in processes.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) == 3 and parts[1] == str(app_pid) and "mitmdump" in parts[2]:
            if f"confdir={root}" not in parts[2]:
                raise RuntimeError("Owned engine lacks a fixture confdir; refusing demo traffic. "
                                   "Use a Debug build with isolated mitmproxy fixture configuration.")
            return True
    return False


def wait_ready(app, root, port):
    deadline = time.monotonic() + 45
    last_error = "proxy has not started"
    while time.monotonic() < deadline:
        if app.poll() is not None:
            raise RuntimeError(f"App exited with status {app.returncode}; see {root / 'app.log'}")
        if engine_is_isolated(app.pid, root):
            try:
                request(port, (HOSTS[0][1], "/api/readiness", "GET", 200), "ready", timeout=1)
                return
            except (OSError, http.client.HTTPException, RuntimeError) as error:
                last_error = str(error)
        time.sleep(0.25)
    raise RuntimeError(f"Proxy readiness timed out after 45 seconds: {last_error}")


def captured_flows(root):
    message = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
               "params": {"name": "list_flows", "arguments": {"limit": 100}}}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(3)
        client.connect(str(root / "FRTMProxy" / "Automation" / "mcp.sock"))
        client.sendall(json.dumps(message).encode() + b"\n")
        pending = bytearray()
        while b"\n" not in pending:
            chunk = client.recv(65536)
            if not chunk or len(pending) > 2_000_000:
                raise RuntimeError("Incomplete or oversized MCP response")
            pending.extend(chunk)
    result = json.loads(pending.split(b"\n", 1)[0])
    if "error" in result or result.get("result", {}).get("isError"):
        raise RuntimeError(f"MCP flow inspection failed: {result}")
    flows = json.loads(result["result"]["content"][0]["text"])
    return sum(flow.get("host") in dict(HOSTS).values() for flow in flows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Fixture-capable Debug .app bundle")
    parser.add_argument("--language", choices=("en", "it"), default="en",
                        help="Language for this isolated instance (default: en)")
    args = parser.parse_args()
    app_path = args.app.resolve()
    with (app_path / "Contents" / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    executable = app_path / "Contents" / "MacOS" / info["CFBundleExecutable"]
    binary = executable.read_bytes()
    for marker in (b"FRTM_UI_TEST_STORAGE", b"FRTMProxy.Settings.Fixture.",
                   b"FRTMProxy.CaptureProfiles.Fixture."):
        if marker not in binary:
            raise RuntimeError("App is not a fixture-capable Debug build; refusing production launch")
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    root = Path(tempfile.mkdtemp(prefix="frtm-demo-", dir="/tmp"))
    calls = seed(root, port, args.language)
    environment = dict(os.environ, FRTM_UI_TEST_STORAGE=str(root))
    arguments = [str(executable), "-hasCompletedOnboarding", "YES", "-AppleLanguages",
                 f"({args.language})", "-AppleLocale", "it_IT" if args.language == "it" else "en_US",
                 "-settings.autoStart", "YES",
                 "-settings.defaultPort", str(port), "-settings.macosProxyOverride", "NO",
                 "-settings.restrictInterceptionToActivePinnedHosts", "NO",
                 "-inspector.noiseEnabled", "NO"]
    with (root / "app.log").open("wb") as log:
        app = subprocess.Popen(arguments, env=environment, stdin=subprocess.DEVNULL,
                               stdout=log, stderr=log, start_new_session=True)
    # Persist immediately so even a failed readiness check leaves a reviewable owned process.
    report = {"appPID": app.pid, "fixtureRoot": str(root), "proxyPort": port,
              "app": str(app_path), "requests": 0, "flows": 0}
    (root / "demo-report.json").write_text(json.dumps(report, indent=2))
    try:
        wait_ready(app, root, port)
        # Four workers keep the maximum request phase bounded to nine 10-second batches.
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            futures = [pool.submit(request, port, call, index) for index, call in enumerate(calls)]
            errors = []
            for future in futures:
                try:
                    future.result()
                    report["requests"] += 1
                except Exception as error:
                    errors.append(str(error))
        if errors:
            raise RuntimeError("Demo requests failed: " + "; ".join(errors))
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            report["flows"] = captured_flows(root)
            if report["flows"] >= len(calls):
                break
            time.sleep(0.25)
        if report["flows"] < len(calls):
            raise RuntimeError(f"Only {report['flows']} demo flows visible after {len(calls)} requests")
        report["state"] = "ready"
    except Exception as error:
        report["state"] = "failed"
        report["error"] = str(error)
        raise
    finally:
        (root / "demo-report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2), flush=True)
    # Deliberately leave this app and its owned engine open for interactive retries/Composer.


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Demo failed: {error}", file=sys.stderr)
        sys.exit(1)
