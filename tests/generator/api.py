"""Cases of lantern_api_answer (docs/reference/beacon-api.md).

The JSON follows beacon-APIs v4.0.0; the HTTP/1.1 framing follows RFC 9112. answer() below writes
each response by the rules of beacon-api.md, apart from the assembly.

cases() yields (name, parts): "view", the ApiView bytes; "request", the request bytes; and
"response", the response bytes, or "more" when the request head has no end yet.
"""

import re
import struct

TEXT = {"peer_id": (488, 64), "enr": (560, 512), "p2p_address": (1080, 128), "discovery_address": (1216, 128),
        "version": (1352, 64)}
VIEW_SIZE = 1424
FORK_ALTAIR, FORK_FULU = 1, 6


def view_bytes(v):
    b = bytearray(VIEW_SIZE)
    struct.pack_into("<Q", b, 0, v["genesis_time"])
    b[8:40] = v["genesis_validators_root"]
    b[40:44] = v["genesis_fork_version"]
    struct.pack_into("<Q", b, 48, v["head_slot"])
    b[56:88] = v["head_root"]
    struct.pack_into("<Q", b, 88, v["proposer_index"])
    b[96:128], b[128:160], b[160:192], b[192:288] = v["parent_root"], v["state_root"], v["body_root"], v["signature"]
    for i, name in enumerate(("previous_justified", "current_justified", "finalized")):
        epoch, root = v[name]
        struct.pack_into("<Q", b, 288 + 40 * i, epoch)
        b[296 + 40 * i:328 + 40 * i] = root
    for off, name in ((408, "current_slot"), (416, "is_syncing"), (424, "is_optimistic"), (432, "el_offline"),
                      (440, "peers"), (448, "seq_number")):
        struct.pack_into("<Q", b, off, v[name])
    b[456:464] = v["attnets"]
    b[464] = v["syncnets"]
    struct.pack_into("<Q", b, 472, v["custody_group_count"])
    struct.pack_into("<Q", b, 480, v["fork"])
    for name, (off, room) in TEXT.items():
        t = v[name]
        assert len(t) <= room
        struct.pack_into("<Q", b, off, len(t))
        b[off + 8:off + 8 + len(t)] = t
    return bytes(b)


def hx(b):
    return '"0x' + bytes(b).hex() + '"'


def num(n):
    return f'"{n}"'


def flag(n):
    return "true" if n else "false"


def text(t):
    return '"' + t.decode() + '"'


def response(code, reason, body):
    head = f"HTTP/1.1 {code} {reason}\r\n"
    if body:
        head += "Content-Type: application/json\r\n"
    head += f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n"
    return head.encode() + body.encode()


ERRORS = {400: ("Bad Request", "BAD_REQUEST"), 404: ("Not Found", "NOT_FOUND"), 405: ("Method Not Allowed", "METHOD_NOT_ALLOWED")}


def error(code):
    reason, message = ERRORS[code]
    return response(code, reason, f'{{"code":{code},"message":"{message}"}}')


def checkpoint(c):
    return f'{{"epoch":{num(c[0])},"root":{hx(c[1])}}}'


def answer(v, request):
    """The response bytes to request, or None while the head has no end."""
    if b"\r\n\r\n" not in request:
        return None
    line = request.split(b"\r\n", 1)[0]
    m = re.fullmatch(rb"([!-~]+) ([!-~]+) HTTP/1\.[0-9]", line)
    if not m:
        return error(400)
    if m.group(1) != b"GET":
        return error(405)
    path, _, query = m.group(2).partition(b"?")
    path = path.decode()
    if path == "/eth/v1/node/health":
        code, reason = 200, "OK"
        if v["is_syncing"] or v["is_optimistic"] or v["el_offline"]:
            code, reason = 206, "Partial Content"
            q = re.fullmatch(rb"syncing_status=([0-9]+)", query) if query else None
            if query and not (q and 100 <= int(q.group(1)) <= 599):
                return error(400)
            if q:
                code, reason = int(q.group(1)), ""
        elif query and not (re.fullmatch(rb"syncing_status=([0-9]+)", query) and 100 <= int(query[15:]) <= 599):
            return error(400)
        return response(code, reason, "")
    if path == "/eth/v1/node/identity":
        p2p = f"[{text(v['p2p_address'])}]" if v["p2p_address"] else "[]"
        disc = f"[{text(v['discovery_address'])}]" if v["discovery_address"] else "[]"
        meta = f'"seq_number":{num(v["seq_number"])},"attnets":{hx(v["attnets"])}'
        if v["fork"] >= FORK_ALTAIR:
            meta += f',"syncnets":{hx(bytes([v["syncnets"]]))}'
        if v["fork"] >= FORK_FULU:
            meta += f',"custody_group_count":{num(v["custody_group_count"])}'
        body = (f'{{"data":{{"peer_id":{text(v["peer_id"])},"enr":{text(v["enr"])},"p2p_addresses":{p2p},'
                f'"discovery_addresses":{disc},"metadata":{{{meta}}}}}}}')
        return response(200, "OK", body)
    if path == "/eth/v1/node/version":
        return response(200, "OK", f'{{"data":{{"version":{text(v["version"])}}}}}')
    if path == "/eth/v1/node/syncing":
        distance = max(v["current_slot"] - v["head_slot"], 0)
        body = (f'{{"data":{{"head_slot":{num(v["head_slot"])},"sync_distance":{num(distance)},'
                f'"is_syncing":{flag(v["is_syncing"])},"is_optimistic":{flag(v["is_optimistic"])},'
                f'"el_offline":{flag(v["el_offline"])}}}}}')
        return response(200, "OK", body)
    if path == "/eth/v1/node/peer_count":
        body = f'{{"data":{{"disconnected":"0","connecting":"0","connected":{num(v["peers"])},"disconnecting":"0"}}}}'
        return response(200, "OK", body)
    if path == "/eth/v1/beacon/genesis":
        body = (f'{{"data":{{"genesis_time":{num(v["genesis_time"])},"genesis_validators_root":'
                f'{hx(v["genesis_validators_root"])},"genesis_fork_version":{hx(v["genesis_fork_version"])}}}}}')
        return response(200, "OK", body)
    if path.startswith("/eth/v1/beacon/headers/"):
        block_id = path[len("/eth/v1/beacon/headers/"):]
        if block_id not in ("head", "0x" + bytes(v["head_root"]).hex()):
            return error(404)
        message = (f'{{"slot":{num(v["head_slot"])},"proposer_index":{num(v["proposer_index"])},'
                   f'"parent_root":{hx(v["parent_root"])},"state_root":{hx(v["state_root"])},"body_root":{hx(v["body_root"])}}}')
        body = (f'{{"execution_optimistic":{flag(v["is_optimistic"])},"finalized":false,"data":{{"root":{hx(v["head_root"])},'
                f'"canonical":true,"header":{{"message":{message},"signature":{hx(v["signature"])}}}}}}}')
        return response(200, "OK", body)
    if path == "/eth/v1/beacon/states/head/finality_checkpoints":
        body = (f'{{"execution_optimistic":{flag(v["is_optimistic"])},"finalized":false,"data":{{'
                f'"previous_justified":{checkpoint(v["previous_justified"])},"current_justified":{checkpoint(v["current_justified"])},'
                f'"finalized":{checkpoint(v["finalized"])}}}}}')
        return response(200, "OK", body)
    return error(404)


def root(n):
    return bytes((n * 37 + i * 11) & 0xFF for i in range(32))


SYNCED = {
    "genesis_time": 1_700_000_000, "genesis_validators_root": root(1), "genesis_fork_version": bytes.fromhex("10000038"),
    "head_slot": 12_345, "head_root": root(2), "proposer_index": 77, "parent_root": root(3), "state_root": root(4),
    "body_root": root(5), "signature": bytes(range(96)), "previous_justified": (383, root(6)),
    "current_justified": (384, root(7)), "finalized": (383, root(6)), "current_slot": 12_345, "is_syncing": 0,
    "is_optimistic": 0, "el_offline": 0, "peers": 3, "seq_number": 2, "attnets": bytes(8), "syncnets": 0,
    "custody_group_count": 4, "fork": FORK_FULU,
    "peer_id": b"16Uiu2HAmEKYKPjVwGxUAujkkn5dLE6HnFJWAWjZVTyc9FWjXAvRf",
    "enr": b"enr:-Ke4QFweV0lCDzuN96lQgbqHzrWgTPdWRRdfh3hB3q920kt6Aq3jsAzRqY7z5xrTjPqSQWT",
    "p2p_address": b"/ip4/10.0.0.7/tcp/9000/p2p/16Uiu2HAmEKYKPjVwGxUAujkkn5dLE6HnFJWAWjZVTyc9FWjXAvRf",
    "discovery_address": b"/ip4/10.0.0.7/udp/9000/p2p/16Uiu2HAmEKYKPjVwGxUAujkkn5dLE6HnFJWAWjZVTyc9FWjXAvRf",
    "version": b"lantern/v0.1.0",
}
SYNCING = dict(SYNCED, head_slot=9, current_slot=18_446_744_073_709_551_615, is_syncing=1, is_optimistic=1,
               el_offline=1, peers=0, seq_number=0, attnets=bytes.fromhex("ff00000000000081"), syncnets=0x0F,
               fork=FORK_ALTAIR, p2p_address=b"", discovery_address=b"", genesis_time=0)
BEHIND = dict(SYNCED, head_slot=20, current_slot=10, fork=0)

PATHS = ["/eth/v1/node/health", "/eth/v1/node/identity", "/eth/v1/node/version", "/eth/v1/node/syncing",
         "/eth/v1/node/peer_count", "/eth/v1/beacon/genesis", "/eth/v1/beacon/headers/head",
         "/eth/v1/beacon/states/head/finality_checkpoints", "/eth/v1/node/identity?id=7", "/eth/v1/node/health?syncing_status=299",
         "/eth/v1/node/health?syncing_status=600", "/eth/v1/node/health?syncing_status=abc", "/eth/v1/beacon/headers/genesis",
         "/eth/v1/beacon/headers/0x" + root(9).hex(), "/eth/v2/beacon/blocks/head", "/"]


def cases():
    for vname, v in (("synced", SYNCED), ("syncing", SYNCING), ("behind", BEHIND)):
        paths = PATHS + ["/eth/v1/beacon/headers/0x" + v["head_root"].hex()]
        for i, path in enumerate(paths):
            request = f"GET {path} HTTP/1.1\r\nHost: localhost:5052\r\nAccept: */*\r\n\r\n".encode()
            yield f"{vname}_{i}", {"view": view_bytes(v), "request": request, "response": answer(v, request)}
    for name, request in (("post", b"POST /eth/v1/node/health HTTP/1.1\r\n\r\n"),
                          ("no_version", b"GET /eth/v1/node/health\r\n\r\n"),
                          ("garbage", b"\x00\x01\r\n\r\n"),
                          ("http_1_0", b"GET /eth/v1/node/version HTTP/1.0\r\n\r\n")):
        yield name, {"view": view_bytes(SYNCED), "request": request, "response": answer(SYNCED, request)}
    yield "head_not_ended", {"view": view_bytes(SYNCED), "request": b"GET /eth/v1/node/health HTTP/1.1\r\nHost: x\r\n",
                             "more": True}
