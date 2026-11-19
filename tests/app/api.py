"""The Beacon API's connections of the running binary (docs/reference/app.md, Test vectors).

Usage: python3 tests/app/api.py PORT

The binary listens on 127.0.0.1:PORT with --http-max-connections 2. The checks:
- on one connection, two getNodeVersion requests in one write, then a getHealth: three responses,
  and the connection stays open;
- a third connection, while two are open, closes with no bytes;
- a request head of 16385 bytes: 431, and the connection closes;
- DELETE on getHealth's path: 405 with Allow: GET;
- a connection with no bytes closes within 31 s.
Prints a PASS or FAIL line for each, and exits 1 when one fails.
"""

import socket
import sys
import time

VERSION = b'{"data":{"version":"lantern/v0.1.0"}}'


def connect(port, timeout=10.0):
    deadline = time.monotonic() + timeout
    while True:
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=5)
            s.settimeout(5)
            return s
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(0.2)


class Reader:
    """The responses of one connection, in order."""

    def __init__(self, sock):
        self.sock, self.buf, self.eof = sock, b"", False

    def more(self):
        data = self.sock.recv(65536)
        if not data:
            self.eof = True
        self.buf += data
        return bool(data)

    def response(self):
        """(status, headers, body) of the next response; headers in lower case."""
        while b"\r\n\r\n" not in self.buf:
            if not self.more():
                raise EOFError("the connection closed before a response")
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        lines = head.split(b"\r\n")
        status = int(lines[0].split(b" ")[1])
        headers = {}
        for line in lines[1:]:
            name, value = line.split(b":", 1)
            headers[name.strip().lower()] = value.strip()
        length = int(headers.get(b"content-length", b"0"))
        while len(self.buf) < length:
            if not self.more():
                raise EOFError("the connection closed inside a body")
        body, self.buf = self.buf[:length], self.buf[length:]
        return status, headers, body

    def closes(self, within):
        """True when the connection ends with no more bytes within the seconds given."""
        deadline = time.monotonic() + within
        self.sock.settimeout(1)
        while time.monotonic() < deadline:
            try:
                if not self.more():
                    return not self.buf
            except socket.timeout:
                continue
            except OSError:  # a reset closes it too
                return not self.buf
        return False


def request(method, path, extra=b""):
    return method + b" " + path + b" HTTP/1.1\r\nHost: lantern\r\n" + extra + b"\r\n"


def main():
    port = int(sys.argv[1])
    results = []

    def check(name, ok, why=""):
        results.append(ok)
        print(("PASS " if ok else "FAIL ") + name + ("" if ok else ": " + why), flush=True)

    a = connect(port, timeout=30)
    ra = Reader(a)
    a.sendall(request(b"GET", b"/eth/v1/node/version") * 2)
    a.sendall(request(b"GET", b"/eth/v1/node/health"))
    try:
        got = [ra.response() for _ in range(3)]
        ok = (got[0][0] == 200 and got[0][2] == VERSION and got[1][0] == 200 and got[1][2] == VERSION and
              got[2][0] in (200, 206) and got[2][2] == b"")
        a.sendall(request(b"GET", b"/eth/v1/node/version"))
        ok = ok and ra.response()[2] == VERSION
        check("pipelined requests on one connection, kept open", ok, repr(got))
    except (EOFError, OSError) as e:
        check("pipelined requests on one connection, kept open", False, repr(e))

    b = connect(port)
    rb = Reader(b)
    b.sendall(request(b"GET", b"/eth/v1/node/version"))
    try:
        ok = rb.response()[2] == VERSION
    except (EOFError, OSError):
        ok = False
    c = connect(port)
    check("a third connection closes with no bytes", ok and Reader(c).closes(10), "")
    c.close()
    b.close()
    time.sleep(1)

    d = connect(port)
    rd = Reader(d)
    try:
        d.sendall(b"GET /eth/v1/node/version HTTP/1.1\r\nHost: lantern\r\nX: " + b"a" * 16400)
        status, headers, _ = rd.response()
        check("a head of more than 16384 bytes", status == 431 and headers.get(b"connection") == b"close" and rd.closes(10),
              f"status {status}")
    except (EOFError, OSError) as e:
        check("a head of more than 16384 bytes", False, repr(e))
    d.close()
    time.sleep(1)

    e = connect(port)
    re_ = Reader(e)
    try:
        e.sendall(request(b"DELETE", b"/eth/v1/node/health"))
        status, headers, _ = re_.response()
        check("DELETE gives 405 with Allow", status == 405 and headers.get(b"allow") == b"GET", f"status {status} {headers}")
    except (EOFError, OSError) as x:
        check("DELETE gives 405 with Allow", False, repr(x))
    e.close()
    a.close()
    time.sleep(1)

    f = connect(port)
    start = time.monotonic()
    closed = Reader(f).closes(31)
    check("a connection with no bytes closes within 31 s", closed, f"open after {time.monotonic() - start:.1f} s")
    f.close()
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
