# bridge.py (COMPATIBLE WITH YOUR SWIFT MODEL)
import json
import os
import sys
import time
import uuid
import base64
import random
import hashlib
import fnmatch
from urllib.parse import urlsplit, parse_qsl
from mitmproxy import http, ctx

# Map Local rules: key = "<host><path>", value = dict with body/headers/status
MAP_LOCAL_RULES = {}
MAP_LOCAL_RULE_KEYS_BY_BASE = {}
MAP_LOCAL_FALLBACK_CURSOR = {}
MAP_LOCAL_SIGNATURE_CURSOR = {}
MAP_LOCAL_WILDCARD_RULES = []
FLOW_BY_ID = {}
FLOW_BY_KEY = {}
FLOW_BY_MAP_LOCAL_KEY = {}
BREAKPOINT_RULES = {}
TRAFFIC_PROFILE_DEFAULT = {
    "id": "traffic.off",
    "name": "No profile",
    "description": "",
    "latency_ms": 0,
    "jitter_ms": 0,
    "downstream_kbps": 0,
    "upstream_kbps": 0,
    "packet_loss": 0,
    "response_delay_ms": 0
}
ACTIVE_TRAFFIC_PROFILE = dict(TRAFFIC_PROFILE_DEFAULT)
DEBUG_VERBOSE = str(os.environ.get("FRTMPROXY_BRIDGE_DEBUG", "")).strip().lower() in ("1", "true", "yes", "on")


def flow_key(flow: http.HTTPFlow) -> str:
    """Returns a unique key for host + path (without query)."""
    host = flow.request.host
    path = flow.request.path.split("?", 1)[0]
    return f"{host}{path}"

def map_local_key(flow: http.HTTPFlow) -> str:
    """
    Map Local key that differentiates calls on the same path based on input.
    Format: "<host><path>#<sha256(prefix)>"
    """
    base = flow_key(flow)
    signature = canonical_request_signature(flow)
    digest = hashlib.sha256(signature.encode("utf-8")).hexdigest()[:12]
    return f"{base}#{digest}"

def base_key_from_rule_key(rule_key: str) -> str:
    if not isinstance(rule_key, str):
        return ""
    if "#" in rule_key:
        return rule_key.split("#", 1)[0]
    return rule_key

def is_wildcard_key(rule_key: str) -> bool:
    base = base_key_from_rule_key(rule_key)
    return "*" in base or "?" in base

def wildcard_score(rule_key: str) -> int:
    base = base_key_from_rule_key(rule_key)
    return sum(1 for ch in base if ch not in ("*", "?"))

def canonical_request_signature(flow: http.HTTPFlow) -> str:
    method = (flow.request.method or "GET").strip().upper()
    url = flow.request.pretty_url or ""
    query = canonical_query(url)
    content_type = _content_type(flow.request.headers).lower()
    body = flow.request.get_text() or ""
    body = body.replace("\r\n", "\n").replace("\r", "\n")
    body = canonical_body(body, content_type)
    return method + "\n" + query + "\n" + body

def canonical_query(url: str) -> str:
    try:
        parts = urlsplit(url or "")
        items = parse_qsl(parts.query or "", keep_blank_values=True)
        if not items:
            return ""
        items.sort(key=lambda kv: (kv[0], kv[1]))
        return "&".join([f"{k}={v}" for (k, v) in items])
    except Exception:
        return ""

def canonical_body(body: str, content_type: str) -> str:
    if not body:
        return ""
    ct = (content_type or "").lower()
    if "application/json" in ct:
        try:
            obj = json.loads(body)
            return json.dumps(obj, sort_keys=True, separators=(",", ":"))
        except Exception:
            return body
    if "application/x-www-form-urlencoded" in ct:
        try:
            items = parse_qsl(body, keep_blank_values=True)
            if not items:
                return ""
            items.sort(key=lambda kv: (kv[0], kv[1]))
            return "&".join([f"{k}={v}" for (k, v) in items])
        except Exception:
            return body
    return body

def track_map_local_key(rule_key: str):
    base = base_key_from_rule_key(rule_key)
    if not base:
        return
    bucket = MAP_LOCAL_RULE_KEYS_BY_BASE.setdefault(base, [])
    if rule_key not in bucket:
        bucket.append(rule_key)
    if is_wildcard_key(rule_key):
        if rule_key not in MAP_LOCAL_WILDCARD_RULES:
            MAP_LOCAL_WILDCARD_RULES.append(rule_key)

def untrack_map_local_key(rule_key: str):
    base = base_key_from_rule_key(rule_key)
    if not base:
        return
    bucket = MAP_LOCAL_RULE_KEYS_BY_BASE.get(base) or []
    if rule_key in bucket:
        bucket.remove(rule_key)
    if not bucket:
        MAP_LOCAL_RULE_KEYS_BY_BASE.pop(base, None)
        MAP_LOCAL_FALLBACK_CURSOR.pop(base, None)
    else:
        MAP_LOCAL_RULE_KEYS_BY_BASE[base] = bucket
    if rule_key in MAP_LOCAL_WILDCARD_RULES:
        MAP_LOCAL_WILDCARD_RULES.remove(rule_key)

def is_loopback_host(host: str) -> bool:
    if not host:
        return False
    h = str(host).strip().lower()
    if h == "localhost" or h == "::1" or h == "0.0.0.0":
        return True
    if h.startswith("127."):
        return True
    # Mitmproxy can surface IPv6 literals with brackets in some contexts.
    if h.startswith("[::1]"):
        return True
    return False

def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()

def debug_log(msg: str):
    """Send a log line to stdout so the app can display it."""
    if not DEBUG_VERBOSE:
        return
    sys.stdout.write(f"[DEBUG] {msg}\n")
    sys.stdout.flush()

def _content_type(headers) -> str:
    try:
        return (headers.get("content-type") or "").strip()
    except Exception:
        return ""

def _is_image_content_type(content_type: str) -> bool:
    return content_type.lower().startswith("image/")

def _as_data_url(mime: str, data: bytes) -> str:
    encoded = base64.b64encode(data).decode("ascii")
    return f"data:{mime};base64,{encoded}"

def serialize_message_body(message) -> str:
    content_type = _content_type(message.headers)
    mime = (content_type.split(";", 1)[0].strip() or "application/octet-stream")

    if _is_image_content_type(mime):
        data = message.content or b""
        return _as_data_url(mime, data)

    return message.get_text()

def traffic_profile_enabled() -> bool:
    return (ACTIVE_TRAFFIC_PROFILE or {}).get("id") != TRAFFIC_PROFILE_DEFAULT["id"]

def update_traffic_profile(profile_payload):
    global ACTIVE_TRAFFIC_PROFILE
    merged = dict(TRAFFIC_PROFILE_DEFAULT)
    if isinstance(profile_payload, dict):
        merged.update({
            "id": profile_payload.get("id", TRAFFIC_PROFILE_DEFAULT["id"]),
            "name": profile_payload.get("name", TRAFFIC_PROFILE_DEFAULT["name"]),
            "description": profile_payload.get("description", ""),
            "latency_ms": max(int(profile_payload.get("latency_ms", 0)), 0),
            "jitter_ms": max(int(profile_payload.get("jitter_ms", 0)), 0),
            "downstream_kbps": max(int(profile_payload.get("downstream_kbps", 0)), 0),
            "upstream_kbps": max(int(profile_payload.get("upstream_kbps", 0)), 0),
            "packet_loss": max(min(float(profile_payload.get("packet_loss", 0) or 0), 1), 0),
            "response_delay_ms": max(int(profile_payload.get("response_delay_ms", 0)), 0),
        })
    ACTIVE_TRAFFIC_PROFILE = merged
    ctx.log.info(f"[TRAFFIC] active profile: {merged.get('name')}")
    debug_log(f"traffic profile updated: {merged}")

def apply_profile_latency(direction: str):
    if not traffic_profile_enabled():
        return
    base = ACTIVE_TRAFFIC_PROFILE.get("latency_ms", 0)
    jitter = ACTIVE_TRAFFIC_PROFILE.get("jitter_ms", 0)
    total = base
    if jitter and jitter > 0:
        total = base + random.uniform(-jitter, jitter)
    if total <= 0:
        return
    delay = max(total / 1000.0, 0)
    time.sleep(delay)
    if DEBUG_VERBOSE:
        debug_log(f"[TRAFFIC] {direction} latency {int(delay * 1000)}ms")

def apply_profile_bandwidth(byte_count: int, kbps_limit: int, direction: str):
    if not traffic_profile_enabled():
        return
    if not byte_count or byte_count <= 0:
        return
    if not kbps_limit or kbps_limit <= 0:
        return
    bytes_per_second = max(kbps_limit * 125, 1)
    delay = byte_count / bytes_per_second
    if delay <= 0:
        return
    time.sleep(delay)
    if DEBUG_VERBOSE:
        debug_log(f"[TRAFFIC] {direction} throttled {byte_count}B in {int(delay * 1000)}ms")

def apply_profile_response_delay():
    if not traffic_profile_enabled():
        return
    delay_ms = ACTIVE_TRAFFIC_PROFILE.get("response_delay_ms", 0)
    if not delay_ms or delay_ms <= 0:
        return
    delay = max(delay_ms / 1000.0, 0)
    time.sleep(delay)
    if DEBUG_VERBOSE:
        debug_log(f"[TRAFFIC] response delay {int(delay * 1000)}ms")

def maybe_inject_packet_loss(flow: http.HTTPFlow) -> bool:
    if not traffic_profile_enabled():
        return False
    loss_rate = float(ACTIVE_TRAFFIC_PROFILE.get("packet_loss") or 0)
    if loss_rate <= 0:
        return False
    if random.random() > loss_rate:
        return False
    flow.response = http.Response.make(
        598,
        b"Simulated packet loss (traffic profile)",
        {"Content-Type": "text/plain"}
    )
    ctx.log.info("[TRAFFIC] simulated packet loss on response")
    return True

def tag_response_with_profile(flow: http.HTTPFlow):
    if not traffic_profile_enabled():
        return
    try:
        if flow.response:
            flow.response.headers["X-FRTraffic-Profile"] = ACTIVE_TRAFFIC_PROFILE.get("id", "traffic.off")
    except Exception:
        pass

def apply_profile_to_request(flow: http.HTTPFlow):
    if not traffic_profile_enabled():
        return
    apply_profile_latency("uplink")
    body = flow.request.raw_content or b""
    apply_profile_bandwidth(len(body), ACTIVE_TRAFFIC_PROFILE.get("upstream_kbps", 0), "uplink")

def apply_profile_to_response(flow: http.HTTPFlow):
    if not traffic_profile_enabled():
        return
    apply_profile_latency("downlink")
    apply_profile_response_delay()
    packet_loss = maybe_inject_packet_loss(flow)
    tag_response_with_profile(flow)
    if packet_loss:
        return
    body = b""
    try:
        if flow.response:
            body = flow.response.get_content() or b""
    except Exception:
        body = flow.response.raw_content if flow.response else b""
    apply_profile_bandwidth(len(body or b""), ACTIVE_TRAFFIC_PROFILE.get("downstream_kbps", 0), "downlink")

def try_decode_data_url(payload: str):
    if not isinstance(payload, str):
        return None
    if not payload.startswith("data:"):
        return None
    try:
        meta, b64 = payload.split(",", 1)
    except ValueError:
        return None
    if ";base64" not in meta:
        return None
    mime = meta[5:].split(";", 1)[0].strip() or "application/octet-stream"
    try:
        data = base64.b64decode(b64, validate=False)
    except Exception:
        return None
    return (mime, data)

def send_flow_event(flow: http.HTTPFlow, event: str, breakpoint_meta=None):
    client = None
    try:
        address = getattr(flow.client_conn, "address", None)
        if address and len(address) >= 2 and address[0]:
            client = {"ip": str(address[0]), "port": int(address[1])}
    except Exception:
        client = None

    payload = {
        "event": event,
        "id": flow.id,
        "timestamp": time.time(),
        "client": client,
        "request": {
            "method": flow.request.method,
            "url": flow.request.pretty_url,
            "headers": dict(flow.request.headers),
            "body": flow.request.get_text()
        },
        "response": None
    }
    if flow.response:
        payload["response"] = {
            "status": flow.response.status_code,
            "headers": dict(flow.response.headers),
            "body": serialize_message_body(flow.response)
        }
    if breakpoint_meta:
        payload["breakpoint"] = breakpoint_meta
    send(payload)

def breakpoint_snapshot(flow: http.HTTPFlow, phase: str, state: str) -> dict:
    return {
        "phase": phase,
        "state": state,
        "key": flow_key(flow)
    }

def breakpoint_rule_for(flow: http.HTTPFlow):
    return BREAKPOINT_RULES.get(flow_key(flow))

def should_break(flow: http.HTTPFlow, phase: str) -> bool:
    rule = breakpoint_rule_for(flow)
    return bool(rule and rule.get(phase))

def apply_request_updates(flow: http.HTTPFlow, payload):
    if not payload:
        return
    method = payload.get("method")
    url = payload.get("url")
    body = payload.get("body", "")
    headers = payload.get("headers") or {}

    if method:
        flow.request.method = method.upper()
    if url:
        flow.request.url = url
    flow.request.set_text(body or "")

    flow.request.headers.clear()
    for key, value in headers.items():
        flow.request.headers[str(key)] = value

def apply_response_updates(flow: http.HTTPFlow, payload):
    if not payload:
        return
    default_status = flow.response.status_code if flow.response else 200
    status = payload.get("status") or default_status
    headers = dict(payload.get("headers") or {})
    body = payload.get("body", "")

    decoded = try_decode_data_url(body)
    if decoded:
        mime, data = decoded
        if mime and "content-type" not in {k.lower(): v for k, v in headers.items()}:
            headers["Content-Type"] = mime
        flow.response = http.Response.make(status, data, headers)
    else:
        flow.response = http.Response.make(status, body, headers)
def load(loader):
    import threading
    threading.Thread(target=stdin_reader, daemon=True).start()

def stdin_reader():
    for line in sys.stdin:
        try:
            message = json.loads(line.strip())
            handle_command(message)
        except Exception as e:
            ctx.log.error(str(e))
            debug_log(f"command parse error: {e}")

def handle_command(cmd):
    t = cmd.get("type")
    flow_id = cmd.get("id")
    debug_log(f"command received type={t} flow_id={flow_id}")
    flow = FLOW_BY_ID.get(flow_id)

    if t == "traffic_profile":
        update_traffic_profile(cmd.get("profile"))
        return

    if t == "mock_response":
        if not flow:
            debug_log(f"flow not found for id={flow_id}")
            return
        body = cmd.get("body", "")
        status = cmd.get("status")
        headers = cmd.get("headers") or {}
        new_rule = {
            "body": body,
            "headers": headers or (dict(flow.response.headers) if flow and flow.response else {}),
            "status": status or (flow.response.status_code if flow and flow.response else 200),
        }
        rule_key = map_local_key(flow)
        MAP_LOCAL_RULES[rule_key] = new_rule
        track_map_local_key(rule_key)
        ctx.log.info(f"[MAP LOCAL] registered for {rule_key}")
        debug_log(f"rule saved for {rule_key}: byte_body={len(body)}")

        # If the flow already has a response, overwrite it for UI consistency.
        apply_map_local_response(flow, new_rule)

    if t == "mock_rule":
        key = cmd.get("key")
        body = cmd.get("body", "")
        status = cmd.get("status", 200)
        headers = cmd.get("headers") or {}
        enabled = cmd.get("enabled", True)
        if not key:
            debug_log("mock_rule command missing key")
            return
        if not enabled:
            MAP_LOCAL_RULES.pop(key, None)
            untrack_map_local_key(key)
            debug_log(f"rule disabled for {key}")
            return

        MAP_LOCAL_RULES[key] = {"body": body, "headers": headers, "status": status}
        track_map_local_key(key)
        ctx.log.info(f"[MAP LOCAL] rule updated for {key}")
        debug_log(f"rule updated for {key}: byte_body={len(body)}")

        # If a flow with the same key exists, update the response immediately.
        flow_for_key = FLOW_BY_MAP_LOCAL_KEY.get(key) or FLOW_BY_KEY.get(key)
        if flow_for_key:
            apply_map_local_response(flow_for_key, MAP_LOCAL_RULES[key])

    if t == "delete_rule":
        key = cmd.get("key")
        if key in MAP_LOCAL_RULES:
            MAP_LOCAL_RULES.pop(key, None)
            untrack_map_local_key(key)
            flow_for_key = FLOW_BY_MAP_LOCAL_KEY.get(key) or FLOW_BY_KEY.get(key)
            if flow_for_key:
                flow_for_key.response = None
            ctx.log.info(f"[MAP LOCAL] rule removed for {key}")
            debug_log(f"rule removed for {key}")
        return

    if t == "mock_request":
        if not flow:
            debug_log(f"flow not found for id={flow_id}")
            return
        flow.request.set_text(cmd.get("body", ""))
        headers = cmd.get("headers") or {}
        if headers:
            flow.request.headers.clear()
            flow.request.headers.update(headers)

    if t == "breakpoint_rule":
        key = cmd.get("key")
        if not key:
            debug_log("breakpoint_rule command missing key")
            return
        request_flag = bool(cmd.get("request"))
        response_flag = bool(cmd.get("response"))
        if request_flag or response_flag:
            BREAKPOINT_RULES[key] = {"request": request_flag, "response": response_flag}
            ctx.log.info(f"[BREAKPOINT] rule updated for {key}")
            debug_log(f"breakpoint enabled {key} req={request_flag} res={response_flag}")
        else:
            BREAKPOINT_RULES.pop(key, None)
            ctx.log.info(f"[BREAKPOINT] rule removed for {key}")
            debug_log(f"breakpoint removed {key}")
        return

    if t == "breakpoint_continue":
        if not flow:
            debug_log(f"flow not found for id={flow_id}")
            return
        phase = cmd.get("phase")
        if phase == "request":
            old_key = flow_key(flow)
            old_map_key = map_local_key(flow)
            apply_request_updates(flow, cmd.get("request"))
            new_key = flow_key(flow)
            new_map_key = map_local_key(flow)
            if old_key != new_key:
                FLOW_BY_KEY.pop(old_key, None)
            if old_map_key != new_map_key:
                FLOW_BY_MAP_LOCAL_KEY.pop(old_map_key, None)
            FLOW_BY_ID[flow.id] = flow
            FLOW_BY_KEY[new_key] = flow
            FLOW_BY_MAP_LOCAL_KEY[new_map_key] = flow
            send_flow_event(flow, "request", breakpoint_snapshot(flow, "request", "released"))
            flow.resume()
            ctx.log.info(f"[BREAKPOINT] request resumed for {flow.request.pretty_url}")
            debug_log(f"breakpoint request released for {flow_id}")
        elif phase == "response":
            apply_response_updates(flow, cmd.get("response"))
            FLOW_BY_ID[flow.id] = flow
            FLOW_BY_KEY[flow_key(flow)] = flow
            FLOW_BY_MAP_LOCAL_KEY[map_local_key(flow)] = flow
            send_flow_event(flow, "response", breakpoint_snapshot(flow, "response", "released"))
            flow.resume()
            ctx.log.info(f"[BREAKPOINT] response released for {flow.request.pretty_url}")
            debug_log(f"breakpoint response released for {flow_id}")
        else:
            debug_log(f"unknown breakpoint phase: {phase}")
            flow.resume()
        return

    if t == "retry_flow":
        if not flow:
            debug_log(f"flow not found for id={flow_id}")
            return

        method = (cmd.get("method") or flow.request.method or "GET").upper()
        url = cmd.get("url") or flow.request.pretty_url
        headers = cmd.get("headers") or {}
        body = cmd.get("body", "")

        cloned_flow = flow.copy()
        cloned_flow.id = str(uuid.uuid4())
        cloned_flow.response = None

        cloned_flow.request.method = method
        if url:
            cloned_flow.request.url = url
        cloned_flow.request.set_text(body or "")

        if headers:
            cloned_flow.request.headers.clear()
            cloned_flow.request.headers.update(headers)

        FLOW_BY_ID[cloned_flow.id] = cloned_flow
        FLOW_BY_KEY[flow_key(cloned_flow)] = cloned_flow
        FLOW_BY_MAP_LOCAL_KEY[map_local_key(cloned_flow)] = cloned_flow

        try:
            ctx.master.commands.call("replay.client", [cloned_flow])
            debug_log(f"retry executed for {flow_key(cloned_flow)} new_id={cloned_flow.id}")
            ctx.log.info(f"[RETRY] request resent for {cloned_flow.request.pretty_url}")
        except Exception as exc:
            ctx.log.error(f"[RETRY] replay error: {exc}")
            debug_log(f"retry error: {exc}")


def apply_map_local_response(flow: http.HTTPFlow, rule: dict):
    """
    Apply a mock response to the flow according to the saved rule.
    Used both when a command arrives from the client and on new flows in request().
    """
    body = rule.get("body", "")
    status = rule.get("status", 200)
    headers = dict(rule.get("headers") or {})

    # Ensure a readable content-type.
    if not any(h.lower() == "content-type" for h in headers):
        headers["Content-Type"] = "application/json"

    headers["X-Map-Local"] = "true"
    flow.response = http.Response.make(status, body, headers)
    ctx.log.info(f"[MAP LOCAL] mock response applied to {flow.request.pretty_url}")
    debug_log(f"mock response sent to {flow_key(flow)} (status {status})")


def request(flow: http.HTTPFlow):
    if is_loopback_host(flow.request.host):
        return

    # Save the flow for later lookup by the mock command.
    FLOW_BY_ID[flow.id] = flow
    FLOW_BY_KEY[flow_key(flow)] = flow
    FLOW_BY_MAP_LOCAL_KEY[map_local_key(flow)] = flow

    waiting_request = should_break(flow, "request")
    if waiting_request:
        flow.intercept()

    apply_profile_to_request(flow)

    # Apply Map Local before sending the request to the server.
    base = flow_key(flow)
    computed_key = map_local_key(flow)
    candidates_all = MAP_LOCAL_RULE_KEYS_BY_BASE.get(base) or []
    signature_candidates = [k for k in candidates_all if k.startswith(computed_key) and k in MAP_LOCAL_RULES]

    matched_key = None
    rule = None

    if signature_candidates:
        if len(signature_candidates) == 1:
            matched_key = signature_candidates[0]
        else:
            idx = int(MAP_LOCAL_SIGNATURE_CURSOR.get(computed_key, 0)) % len(signature_candidates)
            matched_key = signature_candidates[idx]
            MAP_LOCAL_SIGNATURE_CURSOR[computed_key] = (idx + 1) % len(signature_candidates)
        rule = MAP_LOCAL_RULES.get(matched_key)
    else:
        rule = MAP_LOCAL_RULES.get(computed_key)
        if rule:
            matched_key = computed_key
        else:
            rule = MAP_LOCAL_RULES.get(base)
            if rule:
                matched_key = base
            else:
                candidates = [k for k in candidates_all if k in MAP_LOCAL_RULES]
                if candidates:
                    idx = int(MAP_LOCAL_FALLBACK_CURSOR.get(base, 0)) % len(candidates)
                    matched_key = candidates[idx]
                    MAP_LOCAL_FALLBACK_CURSOR[base] = (idx + 1) % len(candidates)
                    rule = MAP_LOCAL_RULES.get(matched_key)
    if rule:
        if DEBUG_VERBOSE:
            debug_log(f"rule found for {matched_key}, applying mock")
        apply_map_local_response(flow, rule)
    else:
        wildcard_key = select_wildcard_rule(flow)
        if wildcard_key:
            if DEBUG_VERBOSE:
                debug_log(f"wildcard rule found for {wildcard_key}, applying mock")
            apply_map_local_response(flow, MAP_LOCAL_RULES[wildcard_key])
        else:
            if DEBUG_VERBOSE:
                debug_log(f"no rule found for {computed_key} (base {base})")

    bp_meta = breakpoint_snapshot(flow, "request", "waiting") if waiting_request else None
    send_flow_event(flow, "request", bp_meta)

def response(flow: http.HTTPFlow):
    if is_loopback_host(flow.request.host):
        return

    # Update the cached flow (needed if the command arrives after the response).
    FLOW_BY_ID[flow.id] = flow
    FLOW_BY_KEY[flow_key(flow)] = flow
    FLOW_BY_MAP_LOCAL_KEY[map_local_key(flow)] = flow

    apply_profile_to_response(flow)

    waiting_response = should_break(flow, "response")
    if waiting_response:
        flow.intercept()

    bp_meta = breakpoint_snapshot(flow, "response", "waiting") if waiting_response else None
    send_flow_event(flow, "response", bp_meta)

def websocket_start(flow: http.HTTPFlow):
    if is_loopback_host(flow.request.host):
        return
    FLOW_BY_ID[flow.id] = flow
    send_flow_event(flow, "websocket_start")

def websocket_message(flow: http.HTTPFlow):
    if is_loopback_host(flow.request.host):
        return
    if not flow.websocket or not flow.websocket.messages:
        return
    msg = flow.websocket.messages[-1]
    is_text = (msg.type == 1)  # opcode 1 = text frame, 2 = binary
    try:
        content = msg.content.decode("utf-8", errors="replace") if is_text else base64.b64encode(msg.content).decode()
    except Exception:
        content = ""
    payload = {
        "event": "websocket_message",
        "id": flow.id,
        "timestamp": time.time(),
        "websocket_message": {
            "id": str(uuid.uuid4()),
            "direction": "client" if msg.from_client else "server",
            "type": "text" if is_text else "binary",
            "content": content,
            "timestamp": time.time()
        }
    }
    send(payload)

def websocket_end(flow: http.HTTPFlow):
    if is_loopback_host(flow.request.host):
        return
    send_flow_event(flow, "websocket_end")

def select_wildcard_rule(flow: http.HTTPFlow):
    if not MAP_LOCAL_WILDCARD_RULES:
        return None
    subject = flow_key(flow)
    best_key = None
    best_score = -1
    for rule_key in MAP_LOCAL_WILDCARD_RULES:
        base = base_key_from_rule_key(rule_key)
        if not base:
            continue
        if fnmatch.fnmatchcase(subject, base):
            score = wildcard_score(rule_key)
            if score > best_score:
                best_key = rule_key
                best_score = score
    return best_key
