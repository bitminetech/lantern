"""Cases of lantern's Engine API client (docs/reference/engine-api.md).

JWTs follow RFC 7519 and RFC 7515 (HS256), made with Python's hmac, hashlib and base64. HTTP
messages follow RFC 9112. The JSON-RPC requests follow execution-apis 981aa66, with the values
of the spec modules of consensus-specs v1.7.0-beta.4 (aa16bb4).

cases(fork, preset) yields (handler, name, parts).
"""

import base64
import hashlib
import hmac
import json

U64 = (1 << 64) - 1


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def jwt(secret, iat):
    header = b64url(b'{"alg":"HS256","typ":"JWT"}')
    claims = b64url(b'{"iat":%d}' % iat)
    signing = header + b"." + claims
    return signing + b"." + b64url(hmac.new(secret, signing, hashlib.sha256).digest())


def http_post(host, token, body):
    return (b"POST / HTTP/1.1\r\nHost: " + host + b"\r\nContent-Type: application/json\r\nAuthorization: Bearer "
            + token + b"\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)


def chunked(body, sizes, ext=b"", trailer=b""):
    out, i = bytearray(), 0
    for n in sizes:
        out += b"%x" % n + ext + b"\r\n" + body[i : i + n] + b"\r\n"
        i += n
    assert i == len(body)
    return bytes(out) + b"0\r\n" + trailer + b"\r\n"


def http_cases():
    """(name, bytes, status, body, kind): kind "length", "chunked" or "close"."""
    body = b'{"jsonrpc":"2.0","id":1,"result":{"status":"VALID","latestValidHash":"0x' + b"ab" * 32 + b'","validationError":null}}'
    cases = [
        ("length", b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % len(body) + body, 200, body, "length"),
        ("length_case", b"HTTP/1.1 200 OK\r\ncontent-length:   %d \t\r\nX-Other: a\r\n\r\n" % len(body) + body, 200, body, "length"),
        ("length_zero", b"HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n", 401, b"", "length"),
        ("length_twice_same", b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello", 200, b"hello", "length"),
        ("chunked", b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + chunked(body, [10, 1, len(body) - 11]), 200, body, "chunked"),
        ("chunked_ext", b"HTTP/1.1 200 OK\r\ntransfer-encoding: CHUNKED\r\n\r\n" + chunked(body, [len(body)], b";a=b", b"X-T: 1\r\n"), 200, body, "chunked"),
        ("chunked_over_length", b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n" + chunked(b"hello", [2, 3]), 200, b"hello", "chunked"),
        ("chunked_hex", b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + b"1A\r\n" + b"z" * 26 + b"\r\n0\r\n\r\n", 200, b"z" * 26, "chunked"),
        ("close", b"HTTP/1.0 500 Internal Server Error\r\n\r\n" + body, 500, body, "close"),
        ("no_content", b"HTTP/1.1 204 No Content\r\n\r\n", 204, b"", "length"),
        ("continue", b"HTTP/1.1 100 Continue\r\n\r\n", 100, b"", "length"),
    ]
    return cases


def cases(fork, preset):
    yield from request_cases(fork, preset)
    secret = hashlib.sha256(b"lantern jwt").digest()
    for iat in (0, 1, 9, 10, 1700000000, 1999999999, U64):
        yield "jwt_token", f"iat_{iat}", {"input": {"secret": secret, "iat": iat}, "output": jwt(secret, iat)}
    yield "jwt_token", "zero_secret", {"input": {"secret": bytes(32), "iat": 1700000000}, "output": jwt(bytes(32), 1700000000)}

    token = jwt(secret, 1700000000)
    for k, (host, body) in enumerate([(b"localhost:8551", b'{"jsonrpc":"2.0","id":1,"method":"engine_exchangeCapabilities","params":[[]]}'),
                                      (b"10.0.0.2:8551", b""), (b"el", b"x" * 1000)]):
        yield "http_post", f"post_{k}", {"input": {"host": host, "token": token, "body": body}, "output": http_post(host, token, body)}

    for name, data, status, body, kind in http_cases():
        tail = b"HTTP/1.1 200 OK\r\n"  # the next response's first bytes
        whole = {"status": status, "body": body, "consumed": len(data)}
        if kind == "close":
            yield "http_parse_response", name, {"input": {"bytes": data, "eof": 1}, "output": whole}
        else:
            yield "http_parse_response", name, {"input": {"bytes": data + tail, "eof": 0}, "output": whole}
            yield "http_parse_response", name + "_eof", {"input": {"bytes": data, "eof": 1}, "output": whole}
        head_end = data.index(b"\r\n\r\n") + 4
        for cut in range(len(data)):
            more = {"input": {"bytes": data[:cut], "eof": 0}, "output": "more"}
            yield "http_parse_response", f"{name}_cut{cut}", more
            if kind == "close" and cut >= head_end:
                want = {"status": status, "body": data[head_end:cut], "consumed": cut}
            else:
                want = "invalid"
            yield "http_parse_response", f"{name}_cut{cut}_eof", {"input": {"bytes": data[:cut], "eof": 1}, "output": want}
    bad = [
        b"HTTP/2 200 OK\r\n\r\n", b"HTTP/1.1 20 OK\r\n\r\n", b"HTTP/1.1 2000 OK\r\n\r\n", b"HTTP/1.1  200 OK\r\n\r\n",
        b"HTTP/1.1 200OK\r\n\r\n", b"http/1.1 200 OK\r\n\r\n", b"HTTP/1.1 200 OK\nContent-Length: 0\r\n\r\n",
        b"HTTP/1.1 200 OK\r\nContent-Length: abc\r\n\r\n", b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab",
        b"HTTP/1.1 200 OK\r\nNoColon\r\n\r\n", b"HTTP/1.1 200 OK\r\n: empty\r\n\r\n",
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n",
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nabc\r\n0\r\n\r\n",
        b"HTTP/1.1 200 OK\r\nContent-Length: 99999999999999999999999\r\n\r\n",
    ]
    for k, data in enumerate(bad):
        yield "http_parse_response", f"bad_{k}", {"input": {"bytes": data, "eof": 1}, "output": "invalid"}


FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")


def q(n):
    """QUANTITY: lowercase hex, no leading zeros."""
    return "0x%x" % int(n)


def d(b):
    """DATA: lowercase hex, two digits a byte."""
    return "0x" + bytes(b).hex()


def payload_json(spec, fork, p):
    f = FORKS.index(fork)
    o = {"parentHash": d(p.parent_hash), "feeRecipient": d(p.fee_recipient), "stateRoot": d(p.state_root),
         "receiptsRoot": d(p.receipts_root), "logsBloom": d(p.logs_bloom), "prevRandao": d(p.prev_randao),
         "blockNumber": q(p.block_number), "gasLimit": q(p.gas_limit), "gasUsed": q(p.gas_used),
         "timestamp": q(p.timestamp), "extraData": d(p.extra_data), "baseFeePerGas": q(p.base_fee_per_gas),
         "blockHash": d(p.block_hash), "transactions": [d(t) for t in p.transactions]}
    if f >= FORKS.index("capella"):
        o["withdrawals"] = [{"index": q(w.index), "validatorIndex": q(w.validator_index), "address": d(w.address),
                             "amount": q(w.amount)} for w in p.withdrawals]
    if f >= FORKS.index("deneb"):
        o["blobGasUsed"] = q(p.blob_gas_used)
        o["excessBlobGas"] = q(p.excess_blob_gas)
    return o


def rpc(id_, method, params):
    return json.dumps({"jsonrpc": "2.0", "id": id_, "method": method, "params": params}, separators=(",", ":")).encode()


def new_payload_json(spec, fork, block, id_):
    f = FORKS.index(fork)
    body = block.body
    params = [payload_json(spec, fork, body.execution_payload)]
    version = 1 if f == FORKS.index("bellatrix") else 2 if f == FORKS.index("capella") else 3
    if f >= FORKS.index("deneb"):
        params.append([d(spec.kzg_commitment_to_versioned_hash(c)) for c in body.blob_kzg_commitments])
        params.append(d(block.parent_root))
    if f >= FORKS.index("electra"):
        version = 4
        params.append([d(r) for r in spec.get_execution_requests_list(body.execution_requests)])
    return rpc(id_, f"engine_newPayloadV{version}", params)


def request_cases(fork, preset):
    import random
    from eth_consensus_specs.debug import random_value as rv
    spec = __import__(f"eth_consensus_specs.{fork}.{preset}", fromlist=["*"])
    f = FORKS.index(fork)
    yield "exchange_capabilities", "id_7", {"input": {"id": 7}, "output": rpc(7, "engine_exchangeCapabilities", [[
        "engine_newPayloadV1", "engine_newPayloadV2", "engine_newPayloadV3", "engine_newPayloadV4",
        "engine_forkchoiceUpdatedV1", "engine_forkchoiceUpdatedV2", "engine_forkchoiceUpdatedV3"]])}
    if f < FORKS.index("bellatrix"):
        return
    rng = random.Random(f"{fork}-{preset}")
    fcu = 1 if f == FORKS.index("bellatrix") else 2 if f == FORKS.index("capella") else 3
    for k, id_ in enumerate((0, 1, 255, U64)):
        hashes = [bytes(rng.getrandbits(8) for _ in range(32)) for _ in range(3)]
        if k == 0:
            hashes[1] = hashes[2] = bytes(32)
        state = {"headBlockHash": d(hashes[0]), "safeBlockHash": d(hashes[1]), "finalizedBlockHash": d(hashes[2])}
        yield "forkchoice_updated", f"fcu_{k}", {"input": {"state": b"".join(hashes), "id": id_},
                                                  "output": rpc(id_, f"engine_forkchoiceUpdatedV{fcu}", [state, None])}
    modes = [rv.RandomizationMode.mode_random, rv.RandomizationMode.mode_zero, rv.RandomizationMode.mode_max,
             rv.RandomizationMode.mode_nil_count, rv.RandomizationMode.mode_one_count, rv.RandomizationMode.mode_max_count]
    for m, mode in enumerate(modes):
        for k in range(3 if m == 0 else 1):
            block = rv.get_random_ssz_object(rng, spec.BeaconBlock, 3000, 3, mode, k == 2)
            id_ = rng.choice([0, 1, 12345, U64])
            yield "new_payload", f"{mode.name}_{k}", {"input": {"block": block.encode_bytes(), "id": id_},
                                                      "output": new_payload_json(spec, fork, block, id_)}
            if f >= FORKS.index("electra"):
                reqs = spec.get_execution_requests_list(block.body.execution_requests)
                out = b"".join(len(r).to_bytes(8, "little") + bytes(r) for r in reqs)
                yield "get_execution_requests_list", f"{mode.name}_{k}", {
                    "input": {"execution_requests": block.body.execution_requests.encode_bytes()}, "output": out}
