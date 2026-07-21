#!/usr/bin/env python3
"""MCP stdio bridge for the local, user-only FRTMProxy Unix socket."""

import json
import os
import socket
import sys


DEFAULT_SOCKET = os.path.expanduser(
    "~/Library/Application Support/FRTMProxy/Automation/mcp.sock"
)


def main() -> int:
    socket_path = os.environ.get("FRTMPROXY_MCP_SOCKET", DEFAULT_SOCKET)
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        client.connect(socket_path)
    except OSError as error:
        sys.stderr.write(f"FRTMProxy MCP is unavailable: {error}\n")
        return 1

    reader = client.makefile("rb")
    try:
        for raw_line in sys.stdin.buffer:
            if not raw_line.strip():
                continue
            try:
                request = json.loads(raw_line)
            except json.JSONDecodeError:
                request = {"id": None}
            client.sendall(raw_line.rstrip(b"\n") + b"\n")
            if "id" not in request:
                continue
            response = reader.readline()
            if not response:
                return 1
            sys.stdout.buffer.write(response)
            sys.stdout.buffer.flush()
    finally:
        reader.close()
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
