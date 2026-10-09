"""Bounded HTTP stress of the real Debug GUI app, bridge, and encrypted session writer.

Launches an isolated app instance without changing system proxy or trust settings.
MCP query latency probes MainActor responsiveness, not visual frame timing.
"""
import argparse
from collections import Counter
import http.client
from http.server import ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import platform
import queue
import signal
import socket
import sqlite3
import subprocess
import tempfile
import threading
import time
import uuid

from integration_proxy import Fixture


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)] if values else None


def stats(values):
    return {"samples": len(values), "p50": percentile(values, .5),
            "p95": percentile(values, .95), "maximum": max(values) if values else None}


def process_table():
    output = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,rss=,command="],
                            capture_output=True, text=True, check=True, timeout=5).stdout
    result = {}
    for line in output.splitlines():
        fields = line.strip().split(None, 3)
        if len(fields) == 4:
            result[int(fields[0])] = {"parent": int(fields[1]), "bytes": int(fields[2]) * 1024,
                                      "command": fields[3]}
    return result


def descendants(table, parent):
    result = set()
    pending = [parent]
    while pending:
        children = [pid for pid, value in table.items() if value["parent"] in pending]
        result.update(children)
        pending = children
    return result


def free_port():
    with socket.socket() as connection:
        connection.bind(("127.0.0.1", 0))
        return connection.getsockname()[1]


def mcp_call(path, name, arguments, timeout=20):
    request = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
               "params": {"name": name, "arguments": arguments}}
    call_deadline = time.monotonic() + timeout
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(timeout)
        connection.connect(str(path))
        connection.sendall(json.dumps(request).encode() + b"\n")
        data = bytearray()
        while b"\n" not in data:
            remaining = call_deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("MCP request deadline exceeded")
            connection.settimeout(remaining)
            chunk = connection.recv(65536)
            if not chunk:
                raise RuntimeError("MCP connection ended without a response")
            data.extend(chunk)
            if len(data) > 10 * 1024 * 1024:
                raise RuntimeError("MCP response exceeded 10 MiB")
    response = json.loads(data.split(b"\n", 1)[0])
    if response.get("error"):
        raise RuntimeError("MCP protocol error: " + json.dumps(response["error"]))
    result = response["result"]
    if result.get("isError"):
        raise RuntimeError("MCP tool error: " + str(result.get("content")))
    return json.loads(next(item["text"] for item in result["content"] if item["type"] == "text"))


def stored_sessions(database):
    with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=3) as connection:
        return [{"id": row[0], "ended": row[1], "incomplete": row[2], "count": row[3]}
                for row in connection.execute("SELECT s.id,s.ended_at,s.incomplete_reason,COUNT(f.flow_id) "
                                              "FROM sessions s LEFT JOIN flows f ON f.session_id=s.id GROUP BY s.id")]


def terminate_owned(pid, command):
    # Verify identity immediately before signalling; never terminate by name globally.
    current = process_table().get(pid)
    if current and current["command"] == command:
        os.kill(pid, signal.SIGTERM)


def run(args):
    root = Path(tempfile.mkdtemp(prefix="frtm-app-stress-", dir="/tmp"))
    run_id = uuid.uuid4().hex
    app = args.app.resolve()
    executable = app / "Contents/MacOS/FRTMProxy"
    mcp = root / "FRTMProxy/Automation/mcp.sock"
    database = root / "FRTMProxy/Sessions/sessions.sqlite"
    proxy_port = free_port()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    server.daemon_threads = True
    origin_port = server.server_port
    threading.Thread(target=server.serve_forever, daemon=True).start()
    jobs = queue.Queue(maxsize=args.concurrency * 2)
    stop = threading.Event()
    producer_done = threading.Event()
    sampling_done = threading.Event()
    lock = threading.Lock()
    completed = set()
    terminal = set()
    ids = set()
    history_validation_complete = False
    errors = Counter()
    failures = []
    latency = []
    responsiveness = []
    memory = []
    owned = {}
    app_pid = None
    threads = []
    sample_thread = None
    scheduled = 0
    load_started = None
    started = time.monotonic()
    # Full history verification is deliberately paced below the MCP 120/minute policy.
    expected_pages = math.ceil(args.requests / 500)
    timeout = args.timeout or args.requests / args.rate * 1.2 + 45 + 20 + 60 + expected_pages * .75
    deadline = started + timeout
    report = {"passed": False, "scope": "Real GUI app + HTTP bridge + encrypted SQLite session writer; "
              "MCP roundtrip probes MainActor responsiveness, not visual frame timings. No TLS, large bodies, "
              "or external network traffic in this run.", "configuration": vars(args) | {"app": str(app), "report": str(args.report)},
              "platform": platform.platform(), "machine": platform.machine(), "fixtureRoot": str(root),
              "fixture": {"bodyBytes": 1024, "port": proxy_port, "originPort": origin_port}, "failures": failures}

    def memory_summary(samples, key):
        values = [item[key] for item in samples]
        tail = values[-min(30, len(values)):]
        return {"peakBytes": max(values) if values else None, "firstBytes": values[0] if values else None,
                "lastBytes": values[-1] if values else None, "tailMeanBytes": sum(tail) / len(tail) if tail else None,
                "tailChangeBytes": tail[-1] - tail[0] if tail else None}

    def remaining(cap=20):
        available = deadline - time.monotonic()
        if available <= 0:
            stop.set()
            raise TimeoutError("Global benchmark deadline exceeded")
        return min(cap, available)

    def fail(message):
        with lock:
            if len(failures) < 20:
                failures.append(message)

    def worker():
        client = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=20)
        try:
            while not stop.is_set():
                try:
                    index = jobs.get(timeout=.2)
                except queue.Empty:
                    if producer_done.is_set():
                        return
                    continue
                path = f"/stress-small/{index}"
                before = time.monotonic()
                try:
                    client.timeout = remaining()
                    client.request("GET", f"http://127.0.0.1:{origin_port}{path}")
                    response = client.getresponse()
                    body = response.read()
                    expected = json.dumps({"path": path}).encode().ljust(1024, b" ")
                    if response.status != 200 or body != expected:
                        raise RuntimeError("Fixture status/body mismatch")
                    with lock:
                        completed.add(index)
                        latency.append((time.monotonic() - before) * 1000)
                except Exception as error:
                    with lock:
                        errors[type(error).__name__] += 1
                    fail(f"Request {index}: {type(error).__name__}")
                    client.close()
                    client = http.client.HTTPConnection("127.0.0.1", proxy_port, timeout=20)
                finally:
                    jobs.task_done()
        finally:
            client.close()

    def sample():
        while not sampling_done.wait(2):
            try:
                remaining()
                table = process_table()
                if app_pid not in table:
                    fail("Owned app exited during load")
                    stop.set()
                    return
                child_ids = descendants(table, app_pid)
                engines = [pid for pid in child_ids if "mitmdump" in table[pid]["command"]]
                for pid in engines:
                    owned[pid] = table[pid]["command"]
                app_bytes = table[app_pid]["bytes"]
                engine_bytes = sum(table[pid]["bytes"] for pid in engines)
                all_child_bytes = sum(table[pid]["bytes"] for pid in child_ids)
                with lock:
                    memory.append({"seconds": round(time.monotonic() - started, 2), "appBytes": app_bytes,
                                   "engineBytes": engine_bytes, "allChildrenBytes": all_child_bytes})
                before = time.monotonic()
                mcp_call(mcp, "query_flows", {"limit": 1}, remaining())
                roundtrip = (time.monotonic() - before) * 1000
                with lock:
                    responsiveness.append(roundtrip)
                if app_bytes > args.maximum_app_rss_mib * 1024 * 1024 or engine_bytes > args.maximum_engine_rss_mib * 1024 * 1024:
                    fail("App or engine RSS exceeded configured budget")
                    stop.set()
                    return
            except Exception as error:
                fail("Responsiveness/memory sampling failed: " + type(error).__name__)
                stop.set()
                return

    try:
        hardware = subprocess.run(["/usr/sbin/sysctl", "-n", "hw.model", "machdep.cpu.brand_string", "hw.memsize"],
                                  capture_output=True, text=True, timeout=5)
        report["hardware"] = hardware.stdout.strip().splitlines()
        report["build"] = json.loads(subprocess.run(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(app / "Contents/Info.plist")],
                                 capture_output=True, text=True, check=True, timeout=5).stdout).get("CFBundleVersion")
        argv = ["/usr/bin/open", "-n", "--env", f"FRTM_UI_TEST_STORAGE={root}", str(app), "--args",
                "-FRTMStressRun", run_id, "-hasCompletedOnboarding", "YES", "-settings.autoStart", "YES",
                "-settings.defaultPort", str(proxy_port), "-settings.macosProxyOverride", "NO",
                "-settings.restrictInterceptionToActivePinnedHosts", "NO", "-settings.pinnedHosts", "",
                "-settings.pinnedApps", "", "-settings.trafficProfile", "traffic.off", "-settings.autoClear", "YES"]
        subprocess.run(argv, check=True, timeout=remaining(45), capture_output=True, text=True)
        startup_deadline = min(deadline, time.monotonic() + 45)
        while time.monotonic() < startup_deadline:
            table = process_table()
            candidates = [pid for pid, value in table.items() if str(executable) in value["command"] and run_id in value["command"]]
            if len(candidates) == 1:
                app_pid = candidates[0]
                owned[app_pid] = table[app_pid]["command"]
            if app_pid and mcp.exists() and database.exists():
                try:
                    mcp_call(mcp, "query_flows", {"limit": 1}, remaining(2))
                    with socket.create_connection(("127.0.0.1", proxy_port), timeout=1):
                        pass
                    if stored_sessions(database):
                        break
                except (OSError, RuntimeError, sqlite3.Error):
                    pass
            time.sleep(.25)
        else:
            raise TimeoutError("App, proxy, fixture storage, or MCP not ready within 45 seconds")
        report["ownedAppPID"] = app_pid
        sample_thread = threading.Thread(target=sample, daemon=True)
        sample_thread.start()
        threads = [threading.Thread(target=worker, daemon=True) for _ in range(args.concurrency)]
        for thread in threads:
            thread.start()
        load_started = time.monotonic()
        next_job = load_started
        scheduled = 0
        for index in range(args.requests):
            if stop.is_set():
                break
            delay = next_job - time.monotonic()
            if delay > 0:
                stop.wait(min(delay, remaining()))
            if stop.is_set():
                break
            while not stop.is_set():
                try:
                    jobs.put(index, timeout=min(.2, remaining()))
                    break
                except queue.Full:
                    pass
            if stop.is_set():
                break
            scheduled += 1
            next_job = max(next_job + 1 / args.rate, time.monotonic())
            if scheduled % 1000 == 0:
                print(json.dumps({"scheduled": scheduled, "completed": len(completed),
                                  "loadSeconds": round(time.monotonic() - load_started, 1)}), flush=True)
        producer_done.set()
        for thread in threads:
            thread.join(timeout=remaining(21))
        if any(thread.is_alive() for thread in threads):
            raise TimeoutError("Client workers did not stop within request timeout")
        load_elapsed = time.monotonic() - load_started
        if len(completed) != args.requests:
            fail("Client completion count mismatch")
        rate_met = load_elapsed <= args.requests / args.rate * 1.05 + 1
        if not rate_met:
            fail("Target rate missed (5% elapsed tolerance plus 1 second)")
        drain_deadline = min(deadline, time.monotonic() + 30)
        while time.monotonic() < drain_deadline:
            sessions = stored_sessions(database)
            if sum(item["count"] for item in sessions) >= len(completed):
                break
            time.sleep(.2)
        else:
            fail("Session writer did not drain in 30 seconds")
        sampling_done.set()
        sample_thread.join(timeout=remaining(21))
        if sample_thread.is_alive():
            raise TimeoutError("Sampler did not stop")
        pre_crash_sessions = stored_sessions(database)
        steady_incomplete = any(item["incomplete"] for item in pre_crash_sessions)
        if steady_incomplete:
            fail("Capture became incomplete during steady load")
        table = process_table()
        crash_injected = False
        for pid in descendants(table, app_pid):
            if "mitmdump" in table[pid]["command"]:
                owned[pid] = table[pid]["command"]
                terminate_owned(pid, owned[pid])
                crash_injected = True
        if not crash_injected:
            fail("Owned engine absent before planned crash-recovery check")
        close_deadline = min(deadline, time.monotonic() + 30)
        while time.monotonic() < close_deadline:
            sessions = stored_sessions(database)
            if sessions and all(item["ended"] is not None for item in sessions):
                break
            time.sleep(.2)
        else:
            fail("Session did not close after owned engine stopped")
        recovery_marked = bool(sessions) and all(item["incomplete"] for item in sessions)
        recovery_closed = bool(sessions) and all(item["ended"] is not None for item in sessions)
        if crash_injected and not recovery_marked:
            fail("Injected engine exit did not mark session incomplete")
        report["crashRecovery"] = {"injectedEngineSIGTERM": crash_injected,
                                   "steadyLoadIncomplete": steady_incomplete,
                                   "interruptedSessionMarked": recovery_marked,
                                   "interruptedSessionClosed": recovery_closed,
                                   "passed": crash_injected and not steady_incomplete and recovery_marked and recovery_closed}
        stored_count = sum(item["count"] for item in sessions)
        if stored_count != len(completed):
            fail("SQLite flow count differs from client completions")
        terminal, ids, duplicate_ids, corrupt = set(), set(), 0, 0
        last_call = 0.0
        for session in sessions:
            cursor = None
            seen_cursors = set()
            while True:
                wait = .75 - (time.monotonic() - last_call)
                if wait > 0:
                    time.sleep(min(wait, remaining()))
                arguments = {"sessionID": session["id"], "limit": 500}
                if cursor:
                    arguments["cursor"] = cursor
                page = mcp_call(mcp, "query_session_flows", arguments, remaining())
                last_call = time.monotonic()
                corrupt += page.get("corruptFlowCount", 0)
                for flow in page["flows"]:
                    if flow["id"] in ids:
                        duplicate_ids += 1
                    ids.add(flow["id"])
                    path = flow.get("path", "")
                    if path.startswith("/stress-small/") and flow.get("event") == "response" and (flow.get("response") or {}).get("status") == 200:
                        terminal.add(int(path.rsplit("/", 1)[1]))
                cursor = page.get("nextCursor")
                if not cursor:
                    break
                if cursor in seen_cursors:
                    raise RuntimeError("Session pagination repeated a cursor")
                seen_cursors.add(cursor)
        history_validation_complete = True
        if terminal != completed or len(ids) != stored_count or duplicate_ids or corrupt:
            fail("Persisted terminal IDs differ from successful clients, duplicate IDs, or corrupt rows")
        if not memory or not responsiveness:
            fail("No app memory/responsiveness measurements")
        report.update({"scheduled": scheduled, "completed": len(completed), "persistedFlows": stored_count,
                       "terminalIDs": len(terminal), "missingTerminalIDs": len(completed - terminal),
                       "unexpectedTerminalIDs": len(terminal - completed), "duplicateIDs": duplicate_ids, "corruptFlows": corrupt,
                       "sessions": len(sessions), "loadSeconds": round(load_elapsed, 3), "targetRateMet": rate_met,
                       "throughput": len(completed) / load_elapsed, "clientErrorCounts": dict(errors),
                       "clientLatencyMilliseconds": stats(latency), "mainActorProbeMilliseconds": stats(responsiveness),
                       "memory": {key: memory_summary(memory, key) for key in ["appBytes", "engineBytes", "allChildrenBytes"]},
                       "memorySamples": memory, "passed": not failures and not errors})
    except Exception as error:
        fail(type(error).__name__ + ": " + str(error))
    finally:
        stop.set()
        producer_done.set()
        sampling_done.set()
        server.shutdown()
        server.server_close()
        for thread in threads:
            thread.join(timeout=1)
        if sample_thread:
            sample_thread.join(timeout=1)
        try:
            table = process_table()
        except subprocess.SubprocessError:
            table = {}
            fail("Could not inspect owned processes during cleanup")
        if app_pid in table and table[app_pid]["command"] == owned.get(app_pid):
            for pid in descendants(table, app_pid):
                if "mitmdump" in table[pid]["command"]:
                    owned[pid] = table[pid]["command"]
        for pid, command in list(owned.items()):
            if args.keep_open and pid == app_pid:
                continue
            try:
                terminate_owned(pid, command)
            except (ProcessLookupError, subprocess.SubprocessError):
                pass
        time.sleep(.3)
        for pid, command in list(owned.items()):
            if args.keep_open and pid == app_pid:
                continue
            try:
                current = process_table().get(pid)
            except subprocess.SubprocessError:
                fail("Could not inspect owned PID before forced cleanup")
                continue
            if current and current["command"] == command:
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        # Preserve every collected measurement even if startup/drain/pagination fails.
        with lock:
            captured_memory = list(memory)
            captured_latency = list(latency)
            captured_probes = list(responsiveness)
            completed_count = len(completed)
            client_errors = dict(errors)
        report["historyValidationProgress"] = {"complete": history_validation_complete,
                                               "scannedIDs": len(ids), "terminalIDs": len(terminal)}
        report.update({"scheduled": scheduled, "completed": completed_count,
                       "ownedAppPID": app_pid, "clientErrorCounts": client_errors,
                       "clientLatencyMilliseconds": stats(captured_latency),
                       "mainActorProbeMilliseconds": stats(captured_probes),
                       "memorySamples": captured_memory,
                       "memory": {key: memory_summary(captured_memory, key)
                                  for key in ["appBytes", "engineBytes", "allChildrenBytes"]}})
        if load_started is not None and "loadSeconds" not in report:
            report["loadSecondsUntilFailure"] = round(time.monotonic() - load_started, 3)
        if database.exists() and "persistedFlows" not in report:
            try:
                partial_sessions = stored_sessions(database)
                report["persistedFlows"] = sum(item["count"] for item in partial_sessions)
                report["partialSessionStates"] = [{"closed": item["ended"] is not None,
                                                    "incomplete": bool(item["incomplete"]), "flowCount": item["count"]}
                                                   for item in partial_sessions]
            except sqlite3.Error as error:
                report["databaseInspectionError"] = type(error).__name__
        report["passed"] = report.get("passed", False) and not failures
        report["elapsedSeconds"] = round(time.monotonic() - started, 3)
        report["keptOpen"] = bool(args.keep_open and app_pid)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, default=str) + "\n")
        # Retain fixture-only history for reproducibility and optional manual inspection.
        print(json.dumps({key: report.get(key) for key in ["passed", "completed", "persistedFlows", "terminalIDs", "failures", "fixtureRoot", "ownedAppPID", "elapsedSeconds"]}), flush=True)
    return 0 if report["passed"] else 1


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--app", required=True, type=Path, help="Fixture-capable Debug .app bundle (optimized Debug recommended)")
    result.add_argument("--requests", type=int, default=6000, help="Use 180000 for 30-minute sustained load at 100/s")
    result.add_argument("--concurrency", type=int, default=20)
    result.add_argument("--rate", type=float, default=100)
    result.add_argument("--maximum-app-rss-mib", type=int, default=300)
    result.add_argument("--maximum-engine-rss-mib", type=int, default=500)
    result.add_argument("--timeout", type=float, default=0, help="Global seconds; default accounts for load, drain, and paced full-history verification")
    result.add_argument("--build-configuration", default="Debug -O (caller-supplied; not inferred)",
                        help="Explicit build configuration/optimization label recorded with the report")
    result.add_argument("--keep-open", action="store_true", help="Leave owned GUI app open after stopping its owned engine")
    result.add_argument("--report", type=Path, default=Path("artifacts/app-stress.json"))
    return result


if __name__ == "__main__":
    cli = parser()
    args = cli.parse_args()
    if not (1 <= args.requests <= 1_000_000 and 1 <= args.concurrency <= 100 and 0 < args.rate <= 1000
            and args.maximum_app_rss_mib >= 100 and args.maximum_engine_rss_mib >= 100 and args.timeout >= 0):
        cli.error("Invalid load, memory, or timeout bounds")
    if not (args.app / "Contents/MacOS/FRTMProxy").is_file():
        cli.error("App bundle does not contain FRTMProxy executable")
    raise SystemExit(run(args))
