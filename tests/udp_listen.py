"""Bind UDP ports on 127.0.0.1 and report what arrives, in arrival order.

usage: udp_listen.py PORT,PORT,PORT [TIMEOUT_SECONDS]

Prints "ready" once every port is bound, then one JSON line with a
{"port", "bytes"} entry per datagram, and exits when a datagram has arrived on
every port or the timeout passes.
"""

import json
import select
import socket
import sys
import time


def main() -> int:
    ports = [int(p) for p in sys.argv[1].split(",")]
    timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
    socks = {}
    for port in ports:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.bind(("127.0.0.1", port))
        socks[s] = port
    print("ready", flush=True)

    got = []
    deadline = time.monotonic() + timeout
    while len(got) < len(ports):
        left = deadline - time.monotonic()
        if left <= 0:
            break
        readable, _, _ = select.select(list(socks), [], [], left)
        for s in readable:
            data, _ = s.recvfrom(64)
            got.append({"port": socks[s], "bytes": len(data)})
    print(json.dumps(got), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
