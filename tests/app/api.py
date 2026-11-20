"""The Beacon API's connections of the running binary (docs/reference/app.md, Test vectors).

Usage: python3 tests/app/api.py PORT GENESIS

The binary listens on 127.0.0.1:PORT with --http-max-connections 2, on the network directory of
the file GENESIS (genesis.ssz: altair, 4096 validators at slot 0). The checks:
- on one connection, two getNodeVersion requests in one write, then a getHealth: three responses,
  and the connection stays open;
- a third connection, while two are open, closes with no bytes;
- a request head of 16385 bytes: 431, and the connection closes;
- DELETE on getHealth's path: 405 with Allow: GET;
- getStateV2 of head as SSZ, read 16384 bytes at a time with a pause of 20 ms after each: the
  bytes of GENESIS with Eth-Consensus-Version: altair;
- getStateV2 of head as JSON over HTTP/1.1 (chunked) and over HTTP/1.0 (closed after the body):
  version altair, data.slot "0", 4096 validators, the genesis_validators_root of GENESIS;
- getSpec, getForkSchedule and getDepositContract: the values of the config.yaml beside GENESIS;
- getStateValidators of head (chunked, 4096 validators, each active_ongoing with the pubkey and
  balance of GENESIS), postStateValidators of two ids, and getStateValidator of an index;
- a connection with no bytes closes within 31 s.
Prints a PASS or FAIL line for each, and exits 1 when one fails.
"""

import json
import os
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

    def more(self, size=65536):
        data = self.sock.recv(size)
        if not data:
            self.eof = True
        self.buf += data
        return bool(data)

    def response(self, pause=0.0):
        """(status, headers, body) of the next response; headers in lower case. A body with
        Transfer-Encoding: chunked is decoded; one with no length ends when the connection closes."""
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
        if headers.get(b"transfer-encoding") == b"chunked":
            body = b""
            while True:
                while b"\r\n" not in self.buf:
                    if not self.more():
                        raise EOFError("the connection closed inside a chunk size")
                size, rest = self.buf.split(b"\r\n", 1)
                n = int(size, 16)
                while len(rest) < n + 2:
                    if not self.more():
                        raise EOFError("the connection closed inside a chunk")
                    size, rest = self.buf.split(b"\r\n", 1)
                if rest[n:n + 2] != b"\r\n":
                    raise EOFError("a chunk without its CRLF")
                body += rest[:n]
                self.buf = rest[n + 2:]
                if n == 0:
                    return status, headers, body
        if b"content-length" not in headers:
            while self.more():
                pass
            body, self.buf = self.buf, b""
            return status, headers, body
        length = int(headers[b"content-length"])
        while len(self.buf) < length:
            if pause:
                time.sleep(pause)
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


def config_values(path):
    """The top-level scalar values of a config.yaml, as texts: quotes and comments dropped."""
    values = {}
    for line in open(path, encoding="utf-8"):
        if line[:1].isalpha() and ":" in line:
            key, value = line.split(":", 1)
            value = value.split("#", 1)[0].strip().strip("'\"")
            if value:
                values[key.strip()] = value
    return values


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

    genesis = open(sys.argv[2], "rb").read()
    g = connect(port)
    rg = Reader(g)
    try:  # SSZ, read slowly: the shell's send buffer fills, and the node waits for room
        g.sendall(request(b"GET", b"/eth/v2/debug/beacon/states/head", b"Accept: application/octet-stream\r\n"))
        rg.more = lambda size=16384, more=rg.more: more(size)
        status, headers, body = rg.response(pause=0.02)
        check("getStateV2 SSZ, read slowly", status == 200 and body == genesis and headers.get(b"eth-consensus-version") == b"altair",
              f"status {status}, {len(body)} bytes of {len(genesis)}, {headers}")
    except (EOFError, OSError) as x:
        check("getStateV2 SSZ, read slowly", False, repr(x))
    g.close()
    time.sleep(1)

    def state_json(name, version, connection=b""):
        h = connect(port)
        rh = Reader(h)
        try:
            h.sendall(b"GET /eth/v2/debug/beacon/states/head " + version + b"\r\nHost: lantern\r\n" + connection + b"\r\n")
            status, headers, body = rh.response()
            doc = json.loads(body)
            data = doc["data"]
            ok = (status == 200 and doc["version"] == "altair" and data["slot"] == "0" and len(data["validators"]) == 4096 and
                  data["genesis_validators_root"] == "0x" + genesis[8:40].hex())
            if version == b"HTTP/1.1":
                ok = ok and headers.get(b"transfer-encoding") == b"chunked"
            else:
                ok = ok and headers.get(b"connection") == b"close" and rh.eof
            check(name, ok, f"status {status}, {headers}, {len(body)} bytes")
        except (EOFError, OSError, ValueError, KeyError) as x:
            check(name, False, repr(x))
        h.close()
        time.sleep(1)

    state_json("getStateV2 JSON, chunked", b"HTTP/1.1")
    state_json("getStateV2 JSON over HTTP/1.0, closed after the body", b"HTTP/1.0")

    config = config_values(os.path.join(os.path.dirname(sys.argv[2]), "config.yaml"))
    k = connect(port)
    rk = Reader(k)
    try:  # three answers of the node's config on one connection
        k.sendall(request(b"GET", b"/eth/v1/config/spec") + request(b"GET", b"/eth/v1/config/fork_schedule") +
                  request(b"GET", b"/eth/v1/config/deposit_contract"))
        got = [rk.response() for _ in range(3)]
        spec, forks, deposit = (json.loads(body)["data"] for _, _, body in got)
        genesis_version, altair_version = config["GENESIS_FORK_VERSION"].lower(), config["ALTAIR_FORK_VERSION"].lower()
        ok = (all(status == 200 for status, _, _ in got) and spec["CONFIG_NAME"] == config["CONFIG_NAME"] and
              spec["GENESIS_FORK_VERSION"] == genesis_version and spec["DEPOSIT_CHAIN_ID"] == config["DEPOSIT_CHAIN_ID"] and
              spec["SECONDS_PER_SLOT"] == str(int(config["SLOT_DURATION_MS"]) // 1000) and spec["SLOTS_PER_EPOCH"] == "8")
        check("getSpec", ok, repr({key: spec.get(key) for key in ("CONFIG_NAME", "GENESIS_FORK_VERSION", "DEPOSIT_CHAIN_ID",
                                                                   "SECONDS_PER_SLOT", "SLOTS_PER_EPOCH")}))
        want = [{"previous_version": genesis_version, "current_version": genesis_version, "epoch": "0"},
                {"previous_version": genesis_version, "current_version": altair_version, "epoch": "0"}]
        check("getForkSchedule", forks == want, repr(forks))
        want = {"chain_id": config["DEPOSIT_CHAIN_ID"], "address": config["DEPOSIT_CONTRACT_ADDRESS"].lower()}
        check("getDepositContract", deposit == want, repr(deposit))
    except (EOFError, OSError, ValueError, KeyError) as x:
        check("getSpec, getForkSchedule and getDepositContract", False, repr(x))
    k.close()
    time.sleep(1)

    def validators(name, raw, check_data):
        v = connect(port)
        rv = Reader(v)
        try:
            v.sendall(raw)
            status, headers, body = rv.response()
            data = json.loads(body)["data"]
            ok = status == 200 and check_data(data, headers)
            check(name, ok, f"status {status}, {headers}, {len(body)} bytes")
        except (EOFError, OSError, ValueError, KeyError, IndexError) as x:
            check(name, False, repr(x))
        v.close()
        time.sleep(1)

    # The validators of GENESIS, a minimal altair BeaconState: the offsets of validators and balances
    # after the fixed fields before them (64 block and state roots); each Validator is 121 bytes, pubkey first.
    vals_at = int.from_bytes(genesis[8 + 32 + 8 + 16 + 112 + 2 * 32 * 64 + 4 + 72 + 4 + 8:][:4], "little")
    bals_at = int.from_bytes(genesis[8 + 32 + 8 + 16 + 112 + 2 * 32 * 64 + 4 + 72 + 4 + 8 + 4:][:4], "little")

    def pubkey(i):
        return "0x" + genesis[vals_at + 121 * i:vals_at + 121 * i + 48].hex()

    def balance(i):
        return str(int.from_bytes(genesis[bals_at + 8 * i:bals_at + 8 * i + 8], "little"))

    validators("getStateValidators of head, chunked", request(b"GET", b"/eth/v1/beacon/states/head/validators"),
               lambda d, h: (h.get(b"transfer-encoding") == b"chunked" and len(d) == 4096 and
                             all(x["index"] == str(i) and x["status"] == "active_ongoing" and
                                 x["validator"]["pubkey"] == pubkey(i) and x["balance"] == balance(i)
                                 for i, x in enumerate(d))))
    body = json.dumps({"ids": [pubkey(4095), "7"]}).encode()
    validators("postStateValidators of two ids",
               request(b"POST", b"/eth/v1/beacon/states/head/validators",
                       b"Content-Type: application/json\r\nContent-Length: %d\r\n" % len(body)) + body,
               lambda d, h: [x["index"] for x in d] == ["7", "4095"])
    validators("getStateValidator of an index", request(b"GET", b"/eth/v1/beacon/states/head/validators/12"),
               lambda d, h: d["index"] == "12" and d["validator"]["pubkey"] == pubkey(12))

    f = connect(port)
    start = time.monotonic()
    closed = Reader(f).closes(31)
    check("a connection with no bytes closes within 31 s", closed, f"open after {time.monotonic() - start:.1f} s")
    f.close()
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
