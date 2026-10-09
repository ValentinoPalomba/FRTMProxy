"""Bounded local engine stress; no system proxy/trust changes or third-party packages."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import http.client
import json
import math
from pathlib import Path
import platform
import queue
import subprocess
import threading
import time
import integration_proxy as fixture


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * fraction) - 1)] if ordered else None


def run(args):
    fixture.WORKER = str(Path(args.worker).resolve())
    harness = fixture.ProxyIntegration
    harness.setUpClass()
    instance = harness()
    stop = threading.Event()
    collection_done = threading.Event()
    lock = threading.Lock()
    completed, terminal, seen_flow_ids = set(), set(), set()
    failures, memory, warnings, bridge_stats = [], [], [], []
    latencies = {"small": [], "large": []}
    duplicates = 0
    client_errors = Counter()
    jobs = queue.Queue(maxsize=args.concurrency * 2)
    started = time.monotonic()
    report = {}

    def drain():
        nonlocal duplicates
        while not collection_done.is_set() or not harness.events.empty():
            try:
                event = harness.events.get(timeout=0.1)
            except queue.Empty:
                continue
            path = (event.get("request") or {}).get("url", "").split(f":{harness.origin}", 1)[-1]
            with lock:
                if event.get("event") == "capture_stats":
                    bridge_stats.append(dict(event, seconds=round(time.monotonic() - started, 2)))
                if event.get("event") == "capture_warning":
                    if len(warnings) < 20: warnings.append(event.get("message"))
                if path.startswith("/stress-") and event.get("event") in ("response", "error"):
                    if path in terminal or event.get("id") in seen_flow_ids: duplicates += 1
                    terminal.add(path)
                    seen_flow_ids.add(event.get("id"))
                    if event.get("event") == "error" and len(failures) < 20: failures.append("capture error: " + path)

    def sample():
        while not stop.wait(1):
            result = subprocess.run(["/bin/ps", "-o", "rss=", "-p", str(harness.process.pid)], capture_output=True, text=True, timeout=5)
            if result.returncode == 0 and result.stdout.strip():
                rss = int(result.stdout.strip()) * 1024
                with lock: memory.append({"seconds": round(time.monotonic() - started, 2), "bytes": rss})
                if args.diagnostics:
                    harness.process.stdin.write('{"type":"capture_stats"}\n')
                    harness.process.stdin.flush()
                if rss > args.maximum_rss_mib * 1024 * 1024:
                    with lock: failures.append("engine RSS exceeded budget")
                    stop.set()
                    return

    def worker():
        client = http.client.HTTPConnection("127.0.0.1", harness.port, timeout=20)
        try:
            while True:
                job = jobs.get()
                if job is None: return
                if stop.is_set(): continue
                kind, index = job
                path = f"/stress-{kind}/{index}"
                before = time.monotonic()
                try:
                    client.request("GET", f"http://127.0.0.1:{harness.origin}{path}")
                    response = client.getresponse()
                    body = response.read()
                    expected = json.dumps({"path": path}).encode().ljust(1024, b" ") if kind == "small" else b"x" * (2 * 1024 * 1024 + 7)
                    if response.status != 200 or body != expected: raise AssertionError("status or byte mismatch")
                    with lock:
                        completed.add(path)
                        latencies[kind].append((time.monotonic() - before) * 1000)
                except Exception as error:
                    with lock:
                        client_errors[type(error).__name__] += 1
                        if len(failures) < 20: failures.append(f"{path}: {error}")
                    client.close()
                    client = http.client.HTTPConnection("127.0.0.1", harness.port, timeout=20)
        finally:
            client.close()

    threads = []
    try:
        instance.configure([])
        # Drain stderr continuously so logging cannot block the measured process.
        def drain_stderr():
            for _ in harness.process.stderr: pass
        threading.Thread(target=drain_stderr, daemon=True).start()
        threads = [threading.Thread(target=drain), threading.Thread(target=sample)]
        for thread in threads: thread.start()
        with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
            futures = [pool.submit(worker) for _ in range(args.concurrency)]
            deadline = time.monotonic()
            scheduled = 0
            for kind, count in [("small", args.requests), ("large", args.large_requests)]:
                for index in range(count):
                    if stop.is_set(): break
                    remaining = deadline - time.monotonic()
                    if remaining > 0: time.sleep(remaining)
                    jobs.put((kind, index))
                    scheduled += 1
                    # Keep the offered rate anchored to the start time. Timer
                    # oversleep must not accumulate across every request; the
                    # bounded jobs queue still applies backpressure at capacity.
                    deadline += 1 / args.rate
                    if scheduled % 1000 == 0:
                        print(json.dumps({"scheduled": scheduled, "completed": len(completed), "elapsed": round(time.monotonic() - started, 1), "rss": memory[-1] if memory else None}), flush=True)
                if stop.is_set(): break
            for _ in futures: jobs.put(None)
            for future in futures: future.result()
        drain_deadline = time.monotonic() + 15
        while time.monotonic() < drain_deadline and not completed.issubset(terminal): time.sleep(0.1)
        elapsed = time.monotonic() - started
        if args.requests + args.large_requests != len(completed): failures.append("client completion count mismatch")
        if completed != terminal: failures.append("terminal event IDs differ from client completions")
        if duplicates: failures.append("duplicate terminal event / flow ID")
        if not memory: failures.append("no engine RSS measurements")
        # Allow scheduler jitter, while rejecting a nominal 100/s run that slows
        # down with a growing capture directory. Include all body sizes in the load.
        rate_met = elapsed <= (args.requests + args.large_requests) / args.rate * 1.05 + 1
        if not rate_met: failures.append("target rate missed (5% elapsed-time tolerance plus 1s)")
        report = {"passed": not failures and not warnings, "platform": platform.platform(), "machine": platform.machine(),
                  "worker": fixture.WORKER, "engine": json.loads((fixture.ROOT / "FRTMProxy/Resources/mitmdump.metadata.json").read_text())["mitmproxyVersion"],
                  "requests": args.requests, "largeRequests": args.large_requests, "concurrency": args.concurrency, "targetRate": args.rate,
                  "scheduled": scheduled, "completed": len(completed), "terminalEvents": len(terminal), "duplicates": duplicates,
                  "clientErrorCounts": dict(client_errors), "targetRateMet": rate_met,
                  "elapsedSeconds": round(elapsed, 3), "throughput": round(len(completed) / elapsed, 2),
                  "latencyMilliseconds": {kind: {"p50": percentile(values, .5), "p95": percentile(values, .95)} for kind, values in latencies.items()},
                  "memorySamples": memory, "bridgeSamples": bridge_stats, "failures": failures, "captureWarnings": warnings,
                  "scope": "HTTP engine + bridge only; no app UI/session writer or TLS overhead benchmark",
                  "hardware": subprocess.run(["/usr/sbin/sysctl", "-n", "hw.model", "machdep.cpu.brand_string"], capture_output=True, text=True, check=True).stdout.strip().splitlines()}
    finally:
        stop.set()
        collection_done.set()
        for thread in threads: thread.join(timeout=5)
        harness.tearDownClass()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    return 0 if report.get("passed") else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", required=True)
    parser.add_argument("--diagnostics", action="store_true", help="Sample bridge counters; extra commands may influence GC timing")
    parser.add_argument("--requests", type=int, default=3000)
    parser.add_argument("--large-requests", type=int, default=256)
    parser.add_argument("--concurrency", type=int, default=20)
    parser.add_argument("--rate", type=float, default=100)
    parser.add_argument("--maximum-rss-mib", type=int, default=500)
    parser.add_argument("--report", type=Path, default=Path("artifacts/proxy-stress.json"))
    args = parser.parse_args()
    if not (1 <= args.requests <= 1_000_000 and 0 <= args.large_requests <= 10_000 and 1 <= args.concurrency <= 100 and 0 < args.rate <= 1000 and args.maximum_rss_mib >= 100):
        parser.error("invalid load or memory bounds")
    raise SystemExit(run(args))
