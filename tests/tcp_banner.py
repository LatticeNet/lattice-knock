"""Listen on one TCP port on 127.0.0.1 and play an ssh server, or a TUN.

usage: tcp_banner.py PORT banner|silent [TIMEOUT_SECONDS]

Prints "ready" once the port is bound. In banner mode every connection gets
an ssh identification line. In silent mode a connection is accepted and held
without a byte, the way a proxy client's TUN completes a handshake whose
upstream never opens. Exits when the timeout passes.
"""

import select
import socket
import sys
import time


def main() -> int:
    port = int(sys.argv[1])
    mode = sys.argv[2]
    timeout = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(8)
    print("ready", flush=True)
    held = []
    deadline = time.monotonic() + timeout
    while True:
        left = deadline - time.monotonic()
        if left <= 0:
            break
        readable, _, _ = select.select([srv], [], [], left)
        if not readable:
            continue
        conn, _ = srv.accept()
        if mode == "banner":
            conn.sendall(b"SSH-2.0-test\r\n")
            conn.close()
        else:
            held.append(conn)
    for conn in held:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
