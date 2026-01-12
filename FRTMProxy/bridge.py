# bridge.py (VERSIONE COMPATIBILE CON IL TUO MODELLO SWIFT)
import json
import sys
import time
import uuid
import base64
from mitmproxy import http, ctx

# Regole di Map Local: key = "<host><path>", value = dict con body/headers/status
MAP_LOCAL_RULES = {}
FLOW_BY_ID = {}
FLOW_BY_KEY = {}
BREAKPOINT_RULES = {}


def flow_key(flow: http.HTTPFlow) -> str:
    """Restituisce una chiave univoca per host + path (senza query)."""
    host = flow.request.host
    path = flow.request.path.split("?", 1)[0]
    return f"{host}{path}"

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
    """Invia una riga di log sullo stdout così l'app può mostrarla."""
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
            debug_log(f"errore parsing comando: {e}")

def handle_command(cmd):
    t = cmd.get("type")
    flow_id = cmd.get("id")
    debug_log(f"comando ricevuto type={t} flow_id={flow_id}")
    flow = FLOW_BY_ID.get(flow_id)

    if t == "mock_response":
        if not flow:
            debug_log(f"flow non trovato per id={flow_id}")
            return
        body = cmd.get("body", "")
        status = cmd.get("status")
        headers = cmd.get("headers") or {}
        new_rule = {
            "body": body,
            "headers": headers or (dict(flow.response.headers) if flow and flow.response else {}),
            "status": status or (flow.response.status_code if flow and flow.response else 200),
        }
        MAP_LOCAL_RULES[flow_key(flow)] = new_rule
        ctx.log.info(f"[MAP LOCAL] registrata per {flow_key(flow)}")
        debug_log(f"regola salvata per {flow_key(flow)}: byte_body={len(body)}")

        # Se il flow ha già una response, la sovrascriviamo per coerenza nell'UI
        apply_map_local_response(flow, new_rule)

    if t == "mock_rule":
        key = cmd.get("key")
        body = cmd.get("body", "")
        status = cmd.get("status", 200)
        headers = cmd.get("headers") or {}
        enabled = cmd.get("enabled", True)
        if not key:
            debug_log("comando mock_rule senza key")
            return
        if not enabled:
            MAP_LOCAL_RULES.pop(key, None)
            debug_log(f"regola disabilitata per {key}")
            return

        MAP_LOCAL_RULES[key] = {"body": body, "headers": headers, "status": status}
        ctx.log.info(f"[MAP LOCAL] regola aggiornata per {key}")
        debug_log(f"regola aggiornata per {key}: byte_body={len(body)}")

        # se ho un flow con la stessa key aggiorno subito la response
        flow_for_key = FLOW_BY_KEY.get(key)
        if flow_for_key:
            apply_map_local_response(flow_for_key, MAP_LOCAL_RULES[key])

    if t == "delete_rule":
        key = cmd.get("key")
        if key in MAP_LOCAL_RULES:
            MAP_LOCAL_RULES.pop(key, None)
            flow_for_key = FLOW_BY_KEY.get(key)
            if flow_for_key:
                flow_for_key.response = None
            ctx.log.info(f"[MAP LOCAL] regola rimossa per {key}")
            debug_log(f"regola rimossa per {key}")
        return

    if t == "mock_request":
        if not flow:
            debug_log(f"flow non trovato per id={flow_id}")
            return
        flow.request.set_text(cmd.get("body", ""))
        headers = cmd.get("headers") or {}
        if headers:
            flow.request.headers.clear()
            flow.request.headers.update(headers)

    if t == "breakpoint_rule":
        key = cmd.get("key")
        if not key:
            debug_log("comando breakpoint_rule senza key")
            return
        request_flag = bool(cmd.get("request"))
        response_flag = bool(cmd.get("response"))
        if request_flag or response_flag:
            BREAKPOINT_RULES[key] = {"request": request_flag, "response": response_flag}
            ctx.log.info(f"[BREAKPOINT] regola aggiornata per {key}")
            debug_log(f"breakpoint abilitato {key} req={request_flag} res={response_flag}")
        else:
            BREAKPOINT_RULES.pop(key, None)
            ctx.log.info(f"[BREAKPOINT] regola rimossa per {key}")
            debug_log(f"breakpoint rimosso {key}")
        return

    if t == "breakpoint_continue":
        if not flow:
            debug_log(f"flow non trovato per id={flow_id}")
            return
        phase = cmd.get("phase")
        if phase == "request":
            old_key = flow_key(flow)
            apply_request_updates(flow, cmd.get("request"))
            new_key = flow_key(flow)
            if old_key != new_key:
                FLOW_BY_KEY.pop(old_key, None)
            FLOW_BY_ID[flow.id] = flow
            FLOW_BY_KEY[new_key] = flow
            send_flow_event(flow, "request", breakpoint_snapshot(flow, "request", "released"))
            flow.resume()
            ctx.log.info(f"[BREAKPOINT] request ripresa per {flow.request.pretty_url}")
            debug_log(f"breakpoint request rilasciato per {flow_id}")
        elif phase == "response":
            apply_response_updates(flow, cmd.get("response"))
            FLOW_BY_ID[flow.id] = flow
            FLOW_BY_KEY[flow_key(flow)] = flow
            send_flow_event(flow, "response", breakpoint_snapshot(flow, "response", "released"))
            flow.resume()
            ctx.log.info(f"[BREAKPOINT] response rilasciata per {flow.request.pretty_url}")
            debug_log(f"breakpoint response rilasciata per {flow_id}")
        else:
            debug_log(f"fase breakpoint sconosciuta: {phase}")
            flow.resume()
        return

    if t == "retry_flow":
        if not flow:
            debug_log(f"flow non trovato per id={flow_id}")
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

        try:
            ctx.master.commands.call("replay.client", [cloned_flow])
            debug_log(f"retry eseguito per {flow_key(cloned_flow)} nuovo_id={cloned_flow.id}")
            ctx.log.info(f"[RETRY] richiesta reinviata per {cloned_flow.request.pretty_url}")
        except Exception as exc:
            ctx.log.error(f"[RETRY] errore replay: {exc}")
            debug_log(f"errore retry: {exc}")


def apply_map_local_response(flow: http.HTTPFlow, rule: dict):
    """
    Applica al flow una risposta mock secondo la regola salvata.
    Viene usata sia quando arriva un comando dal client che sui nuovi flow in request().
    """
    body = rule.get("body", "")
    status = rule.get("status", 200)
    headers = dict(rule.get("headers") or {})

    # Garantisci un content-type leggibile
    if not any(h.lower() == "content-type" for h in headers):
        headers["Content-Type"] = "application/json"

    headers["X-Map-Local"] = "true"
    flow.response = http.Response.make(status, body, headers)
    ctx.log.info(f"[MAP LOCAL] risposta mock applicata a {flow.request.pretty_url}")
    debug_log(f"risposta mock inviata su {flow_key(flow)} (status {status})")


def request(flow: http.HTTPFlow):
    if is_loopback_host(flow.request.host):
        return

    # salva il flow per ricerca successiva dal comando mock
    FLOW_BY_ID[flow.id] = flow
    FLOW_BY_KEY[flow_key(flow)] = flow

    waiting_request = should_break(flow, "request")
    if waiting_request:
        flow.intercept()

    # Applica il Map Local prima di inviare la richiesta al server
    rule = MAP_LOCAL_RULES.get(flow_key(flow))
    if rule:
        debug_log(f"regola trovata per {flow_key(flow)}, applico mock")
        apply_map_local_response(flow, rule)
    else:
        debug_log(f"nessuna regola trovata per {flow_key(flow)}")

    bp_meta = breakpoint_snapshot(flow, "request", "waiting") if waiting_request else None
    send_flow_event(flow, "request", bp_meta)

def response(flow: http.HTTPFlow):
    if is_loopback_host(flow.request.host):
        return

    # aggiorna il flow in cache (serve se arriva il comando dopo la response)
    FLOW_BY_ID[flow.id] = flow
    FLOW_BY_KEY[flow_key(flow)] = flow

    waiting_response = should_break(flow, "response")
    if waiting_response:
        flow.intercept()

    bp_meta = breakpoint_snapshot(flow, "response", "waiting") if waiting_response else None
    send_flow_event(flow, "response", bp_meta)
