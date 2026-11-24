"""Check the metrics server of a running lantern binary (docs/reference/app.md, the metrics server).

Usage: python3 tests/app/metrics.py PORT

GET /metrics must give 200 with the Prometheus text type, a Content-Length of its body, and a body
of whole families of the beacon category (each a HELP line, a TYPE line and samples) with
libp2p_peers and beacon_head_slot, after which the connection closes; a second GET must do the
same. GET of another path must give 404, and POST 405 with Allow: GET. Prints a PASS or FAIL line
for each; the exit code is 1 after a FAIL.
"""

import re
import socket
import sys
import time

port = int(sys.argv[1])
fail = 0


def ask(request, timeout=10.0):
    """The bytes of the answer to request, up to the server's close: (head, body), or None."""
    deadline = time.time() + timeout
    while True:
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
            break
        except OSError:
            if time.time() > deadline:
                return None
            time.sleep(0.2)
    s.sendall(request)
    got = b""
    while True:
        part = s.recv(65536)
        if not part:
            break
        got += part
    s.close()
    head, _, body = got.partition(b"\r\n\r\n")
    return head.decode("latin-1"), body


def check(name, ok, why=""):
    global fail
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else ": " + why))
    fail |= not ok


SAMPLE = re.compile(r'^[a-zA-Z_:][a-zA-Z0-9_:]*(\{[a-zA-Z_][a-zA-Z0-9_]*="[^"]*"(,[a-zA-Z_][a-zA-Z0-9_]*="[^"]*")*\})? -?[0-9]+(\.[0-9]+)?$')


def text_ok(body):
    """'' when body is whole families of Prometheus text 0.0.4, else why not."""
    text = body.decode()
    if text and not text.endswith("\n"):
        return "no LF at the end"
    name = None
    for line in text[:-1].split("\n"):
        if line.startswith("# HELP "):
            name = line.split(" ")[2]
        elif line.startswith("# TYPE "):
            if line.split(" ")[2] != name or line.split(" ")[3] not in ("gauge", "counter", "histogram"):
                return "a TYPE line not after its HELP line: " + line
        elif not SAMPLE.match(line) or not line.startswith(name or "\0"):
            return "not a sample of its family: " + line
    return ""


for k in range(2):
    got = ask(b"GET /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    if got is None:
        check(f"GET /metrics ({k + 1})", False, "no connection")
        continue
    head, body = got
    lines = head.split("\r\n")
    want_length = f"Content-Length: {len(body)}"
    why = ""
    if lines[0] != "HTTP/1.1 200 OK":
        why = "status line " + lines[0]
    elif "Content-Type: text/plain; version=0.0.4; charset=utf-8" not in lines:
        why = "no Prometheus Content-Type"
    elif want_length not in lines:
        why = "Content-Length is not the body's " + str(len(body))
    elif "Connection: close" not in lines:
        why = "no Connection: close"
    else:
        why = text_ok(body)
        if not why and not re.search(rb"(?m)^libp2p_peers [0-9]+$", body):
            why = "no libp2p_peers sample"
        if not why and not re.search(rb"(?m)^beacon_head_slot [0-9]+$", body):
            why = "no beacon_head_slot sample"
    check(f"GET /metrics ({k + 1}): {len(body)} bytes of whole families, then the close", not why, why)

got = ask(b"GET /other HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
check("GET /other gives 404", got is not None and got[0].startswith("HTTP/1.1 404 Not Found\r\n") and got[1] == b"",
      repr(got and got[0][:40]))
got = ask(b"POST /metrics HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n")
check("POST /metrics gives 405 with Allow: GET",
      got is not None and got[0].startswith("HTTP/1.1 405 Method Not Allowed\r\n") and "Allow: GET" in got[0].split("\r\n"),
      repr(got and got[0][:60]))
sys.exit(fail)
