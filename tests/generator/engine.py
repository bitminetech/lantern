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
    yield from response_case_parts()
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
    yield "exchange_capabilities", "id_7", {"input": {"id": 7}, "output": rpc(7, "engine_exchangeCapabilities", [METHODS])}
    if f < FORKS.index("bellatrix"):
        return
    rng = random.Random(f"{fork}-{preset}")
    fcu = 1 if f == FORKS.index("bellatrix") else 2 if f == FORKS.index("capella") else 3
    for k, id_ in enumerate((0, 1, 255, U64)):
        hashes = [bytes(rng.getrandbits(8) for _ in range(32)) for _ in range(3)]
        if k == 0:
            hashes[1] = hashes[2] = bytes(32)
        state = {"headBlockHash": d(hashes[0]), "safeBlockHash": d(hashes[1]), "finalizedBlockHash": d(hashes[2])}
        yield "forkchoice_updated", f"fcu_{k}", {"input": {"state": b"".join(hashes), "attributes": b"", "id": id_},
                                                  "output": rpc(id_, f"engine_forkchoiceUpdatedV{fcu}", [state, None])}
    for k, (raw, attrs) in enumerate(payload_attributes(spec, fork, rng)):
        hashes = [bytes(rng.getrandbits(8) for _ in range(32)) for _ in range(3)]
        state = {"headBlockHash": d(hashes[0]), "safeBlockHash": d(hashes[1]), "finalizedBlockHash": d(hashes[2])}
        id_ = rng.choice([0, 1, 12345, U64])
        yield "forkchoice_updated", f"attributes_{k}", {"input": {"state": b"".join(hashes), "attributes": raw, "id": id_},
                                                         "output": rpc(id_, f"engine_forkchoiceUpdatedV{fcu}", [state, attrs])}
    gp = f - FORKS.index("bellatrix") + 1
    for k, id_ in enumerate((0, 1, 255, U64)):
        pid = bytes(rng.getrandbits(8) for _ in range(8)) if k else bytes(8)
        yield "get_payload", f"id_{k}", {"input": {"payload_id": pid, "id": id_},
                                         "output": rpc(id_, f"engine_getPayloadV{gp}", [d(pid)])}
    if f >= FORKS.index("electra"):
        yield from request_list_cases(spec, rng)
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


def payload_attributes(spec, fork, rng):
    """(the PayloadAttributes bytes of engine-api.md, the JSON of PayloadAttributesVn) for random
    values of the spec's PayloadAttributes (deneb's in electra and fulu): no withdrawal, one, and
    MAX_WITHDRAWALS_PER_PAYLOAD from capella."""
    f = FORKS.index(fork)
    pa = spec if hasattr(spec, "PayloadAttributes") else __import__(spec.__name__.replace(fork, "deneb"), fromlist=["*"])
    counts = [0] if f < FORKS.index("capella") else [0, 1, int(spec.MAX_WITHDRAWALS_PER_PAYLOAD)]
    for c, n in enumerate(counts + [n for n in counts if n]):
        withdrawals = [spec.Withdrawal(index=rng.getrandbits(64), validator_index=rng.getrandbits(64),
                                       address=bytes(rng.getrandbits(8) for _ in range(20)), amount=rng.getrandbits(64))
                       for _ in range(n)]
        if c == 1:  # the extremes of each field
            withdrawals[0] = spec.Withdrawal(index=0, validator_index=U64, address=bytes(20), amount=0)
        fields = {"timestamp": rng.choice([0, 1, rng.getrandbits(64), U64]), "prev_randao": bytes(rng.getrandbits(8) for _ in range(32)),
                  "suggested_fee_recipient": bytes(rng.getrandbits(8) for _ in range(20))}
        if f >= FORKS.index("capella"):
            fields["withdrawals"] = withdrawals
        if f >= FORKS.index("deneb"):
            fields["parent_beacon_block_root"] = bytes(rng.getrandbits(8) for _ in range(32))
        a = pa.PayloadAttributes(**fields)
        raw = (int(a.timestamp).to_bytes(8, "little") + bytes(a.prev_randao) + bytes(a.suggested_fee_recipient) + bytes(4)
               + (bytes(a.parent_beacon_block_root) if f >= FORKS.index("deneb") else bytes(32))
               + len(withdrawals).to_bytes(8, "little") + b"".join(w.encode_bytes() for w in withdrawals))
        o = {"timestamp": q(a.timestamp), "prevRandao": d(a.prev_randao), "suggestedFeeRecipient": d(a.suggested_fee_recipient)}
        if f >= FORKS.index("capella"):
            o["withdrawals"] = [{"index": q(w.index), "validatorIndex": q(w.validator_index), "address": d(w.address),
                                 "amount": q(w.amount)} for w in a.withdrawals]
        if f >= FORKS.index("deneb"):
            o["parentBeaconBlockRoot"] = d(a.parent_beacon_block_root)
        yield raw, o


def attribute_raw(spec, fork, a):
    """The PayloadAttributes bytes of engine-api.md for the spec's PayloadAttributes a."""
    f = FORKS.index(fork)
    withdrawals = list(a.withdrawals) if f >= FORKS.index("capella") else []
    return (int(a.timestamp).to_bytes(8, "little") + bytes(a.prev_randao) + bytes(a.suggested_fee_recipient) + bytes(4)
            + (bytes(a.parent_beacon_block_root) if f >= FORKS.index("deneb") else bytes(32))
            + len(withdrawals).to_bytes(8, "little") + b"".join(spec.Withdrawal.encode_bytes(w) for w in withdrawals))


def attribute_cases(fork, preset, cases):
    """payload_attributes: the attributes that the spec's prepare_execution_payload gives the
    execution engine, for the pre states of the spec's operations cases of execution_payload and
    withdrawals (cases: (name, parts)), each at a block's slot, with random fee recipients. Bellatrix
    states before the merge are left out: prepare_execution_payload asks the PoW chain there."""
    import random
    f = FORKS.index(fork)
    if f < FORKS.index("bellatrix"):
        return
    spec = __import__(f"eth_consensus_specs.{fork}.{preset}", fromlist=["*"])
    rng = random.Random(f"attributes-{fork}-{preset}")

    class Engine:
        def notify_forkchoice_updated(self, head_block_hash, safe_block_hash, finalized_block_hash, payload_attributes):
            self.attributes = payload_attributes

    for name, parts in cases:
        state = spec.BeaconState.decode_bytes(parts["pre"])
        if f == FORKS.index("bellatrix") and not spec.is_merge_transition_complete(state):
            continue
        fee = spec.ExecutionAddress(bytes(rng.getrandbits(8) for _ in range(20)))
        engine = Engine()
        inputs = {"state": parts["pre"], "fee_recipient": bytes(fee)}
        try:
            spec.prepare_execution_payload(state, spec.Hash32(), spec.Hash32(), fee, engine)
        except (AssertionError, ValueError, OverflowError):
            yield "payload_attributes", name, {"input": inputs, "output": "invalid"}
            continue
        yield "payload_attributes", name, {"input": inputs, "output": attribute_raw(spec, fork, engine.attributes)}


def ssz_list(items):
    """The SSZ bytes of a list of variable size items: an offset each, then the items."""
    head = 4 * len(items)
    out, at = b"", head
    for item in items:
        out += at.to_bytes(4, "little")
        at += len(item)
    return out + b"".join(items)


def request_list_cases(spec, rng):
    """get_execution_requests: the request lists of random ExecutionRequests, as the SSZ bytes of
    lantern's ExecutionRequestsList, and lists that are no such encoding or that the spec's asserts
    reject."""
    from eth_consensus_specs.debug import random_value as rv
    modes = [rv.RandomizationMode.mode_random, rv.RandomizationMode.mode_zero, rv.RandomizationMode.mode_max,
             rv.RandomizationMode.mode_nil_count, rv.RandomizationMode.mode_one_count, rv.RandomizationMode.mode_max_count]
    for m, mode in enumerate(modes):
        for k in range(3 if m == 0 else 1):
            reqs = rv.get_random_ssz_object(rng, spec.ExecutionRequests, 3000, 3, mode, k == 2)
            items = [bytes(r) for r in spec.get_execution_requests_list(reqs)]
            back = spec.get_execution_requests(items)
            assert back == reqs
            yield "get_execution_requests", f"{mode.name}_{k}", {"input": {"list": ssz_list(items)}, "output": back.encode_bytes()}
    dep, wd, con = (spec.DepositRequest(), spec.WithdrawalRequest(), spec.ConsolidationRequest())
    one = [b"\x00" + dep.encode_bytes(), b"\x01" + wd.encode_bytes(), b"\x02" + con.encode_bytes()]
    rejected = {
        "type_3": [b"\x03" + con.encode_bytes()],
        "type_255": [b"\xff\x00"],
        "no_data": [b"\x00"],
        "no_type": [b""],
        "descending": [one[1], one[0]],
        "repeated": [one[0], one[0]],
        "repeated_last": [one[0], one[2], one[2]],
        "partial_deposit": [b"\x00" + dep.encode_bytes()[:-1]],
        "partial_withdrawal": [b"\x01" + wd.encode_bytes() + b"\x00"],
        "partial_consolidation": [b"\x02" + con.encode_bytes()[:100]],
        "withdrawals_over_limit": [b"\x01" + wd.encode_bytes() * (int(spec.MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD) + 1)],
        "consolidations_over_limit": [b"\x02" + con.encode_bytes() * (int(spec.MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD) + 1)],
    }
    for name, items in rejected.items():
        try:
            spec.get_execution_requests(items)
        except Exception:
            pass
        else:
            raise RuntimeError(f"the spec takes the request list {name}")
        yield "get_execution_requests", name, {"input": {"list": ssz_list(items)}, "output": "invalid"}
    deposits = [b"\x00" + dep.encode_bytes() * (int(spec.MAX_DEPOSIT_REQUESTS_PER_PAYLOAD) + 1)]
    try:
        spec.get_execution_requests(deposits)
    except Exception:
        yield "get_execution_requests", "deposits_over_limit", {"input": {"list": ssz_list(deposits)}, "output": "invalid"}
    else:
        raise RuntimeError("the spec takes too many deposit requests")
    good = ssz_list(one)
    yield "get_execution_requests", "one_each", {"input": {"list": good}, "output": spec.get_execution_requests(one).encode_bytes()}
    yield "get_execution_requests", "empty", {"input": {"list": b""}, "output": spec.ExecutionRequests().encode_bytes()}
    broken = {  # no SSZ encoding of a list of at most 3 byte lists
        "short_offset": good[:3], "offset_not_4": b"\x05\x00\x00\x00" + good[4:], "offset_zero": b"\x00\x00\x00\x00" + good[4:],
        "offset_past_end": (len(good) + 1).to_bytes(4, "little") + good[4:],
        "offsets_descending": good[:4] + (int.from_bytes(good[8:12], "little")).to_bytes(4, "little") + good[4:8] + good[12:],
        "four_items": ssz_list(one + [b"\x03\x00"]),
    }
    for name, data in broken.items():
        yield "get_execution_requests", name, {"input": {"list": data}, "output": "invalid"}


STATUSES = ["VALID", "INVALID", "SYNCING", "ACCEPTED", "INVALID_BLOCK_HASH"]
METHODS = ["engine_newPayloadV1", "engine_newPayloadV2", "engine_newPayloadV3", "engine_newPayloadV4",
           "engine_forkchoiceUpdatedV1", "engine_forkchoiceUpdatedV2", "engine_forkchoiceUpdatedV3",
           "engine_getPayloadV1", "engine_getPayloadV2", "engine_getPayloadV3", "engine_getPayloadV4", "engine_getPayloadV5"]


def response_cases():
    """(name, method, body, expected or "invalid")."""
    h = "0x" + "ab" * 32
    out = []

    def want(id_, status=0, latest=None, payload_id=None, caps=0, error=None, place=(0, 0)):
        return {"id": id_, "error": 0 if error is None else 1, "error_code": 0 if error is None else error,
                "status": status, "latest_valid_hash": latest, "payload_id": payload_id, "capabilities": caps,
                "result_offset": place[0], "result_length": place[1]}

    styles = [dict(separators=(",", ":")), dict(indent=2), dict(separators=(", ", ": ")), dict(indent="\t")]
    for k, st in enumerate(STATUSES):
        for s, style in enumerate(styles):
            r = {"jsonrpc": "2.0", "id": k, "result": {"status": st, "latestValidHash": h, "validationError": None}}
            out.append((f"np_{st}_{s}", 1, json.dumps(r, **style).encode(), want(k, k + 1, bytes.fromhex(h[2:]))))
    r = {"result": {"validationError": "a \"quoted\" \\ é\nline", "status": "INVALID", "latestValidHash": None}, "id": 2 ** 64 - 1, "jsonrpc": "2.0"}
    out.append(("np_reordered", 1, json.dumps(r).encode(), want(2 ** 64 - 1, 2)))
    r = {"jsonrpc": "2.0", "id": 0, "extra": {"a": [1, 2.5e-3, -7, True, False, None, {"b": "]}\\\""}]}, "result": {"status": "SYNCING"}}
    out.append(("np_extra_members", 1, json.dumps(r).encode(), want(0, 3)))
    out.append(("np_spaces", 1, b' \r\n\t{"id" :7 ,"result":{ "status" : "ACCEPTED" , "latestValidHash" : null } }\n ', want(7, 4)))
    out.append(("np_duplicate", 1, b'{"id":1,"result":{"status":"VALID","status":"SYNCING"}}', want(1, 3)))
    err = {"jsonrpc": "2.0", "id": 3, "error": {"code": -32602, "message": "Invalid params", "data": {"err": "x"}}}
    out.append(("error", 1, json.dumps(err).encode(), want(3, error=-32602)))
    out.append(("error_and_result", 2, b'{"id":4,"result":{"payloadStatus":{"status":"VALID"}},"error":{"code":5,"message":""}}', want(4, error=5)))
    out.append(("error_code_min", 3, b'{"id":4,"error":{"code":-9223372036854775808}}', want(4, error=-(2 ** 63))))
    out.append(("error_code_max", 3, b'{"id":4,"error":{"message":"m","code":9223372036854775807}}', want(4, error=2 ** 63 - 1)))
    for pid in (None, "0x0123456789abcdef"):
        r = {"jsonrpc": "2.0", "id": 9, "result": {"payloadStatus": {"status": "VALID", "latestValidHash": h, "validationError": None}, "payloadId": pid}}
        out.append((f"fcu_{pid}", 2, json.dumps(r).encode(),
                    want(9, 1, bytes.fromhex(h[2:]), None if pid is None else bytes.fromhex(pid[2:]))))
    out.append(("fcu_no_payload_id", 2, b'{"id":9,"result":{"payloadStatus":{"status":"SYNCING","latestValidHash":null}}}', want(9, 3)))
    result = {"executionPayload": {"parentHash": h, "transactions": ["0x", "0x01"], "withdrawals": [{"index": "0x0"}]},
              "blockValue": "0x1", "blobsBundle": {"commitments": [], "proofs": [], "blobs": []},
              "shouldOverrideBuilder": False, "executionRequests": ["0x00" + "ab" * 192], "extra": [[[{"a": None}]]]}
    for s, style in enumerate(styles):
        text = json.dumps(result, **style)
        for k, (head, tail) in enumerate([('{"jsonrpc":"2.0","id":5,"result":', '}'), (' {\n  "result" : ', ' ,\n "id" : 5 }\n'),
                                          ('{"id":5,"result":{"a":[1]},"result":', ',"jsonrpc":"2.0"}')]):
            body = (head + text + tail).encode()
            out.append((f"gp_{s}_{k}", 4, body, want(5, place=(len(head.encode()), len(text.encode())))))
    out.append(("gp_empty", 4, b'{"id":6,"result":{}}', want(6, place=(len(b'{"id":6,"result":'), 2))))
    out.append(("gp_error", 4, b'{"id":6,"error":{"code":-38001,"message":"Unknown payload"}}', want(6, error=-38001)))
    for k, names in enumerate([[], METHODS, ["engine_newPayloadV1", "engine_getPayloadV5", "engine_forkchoiceUpdatedV3", "x"], ["engine_newPayloadV4"],
                               ["engine_getPayloadV1", "engine_getPayloadV2", "engine_getPayloadV6", "engine_getPayloadV3", "engine_getPayloadV4"]]):
        mask = sum(1 << METHODS.index(n) for n in names if n in METHODS)
        r = {"jsonrpc": "2.0", "id": k, "result": names}
        out.append((f"caps_{k}", 3, json.dumps(r).encode(), want(k, caps=mask)))
    bad = [
        (1, b""), (1, b"[]"), (1, b'"x"'), (1, b'{"id":1,"result":{"status":"VALID"}} x'), (1, b'{"id":1,"result":{"status":"VALID"}'),
        (1, b'{"result":{"status":"VALID"}}'), (1, b'{"id":-1,"result":{"status":"VALID"}}'), (1, b'{"id":1.5,"result":{"status":"VALID"}}'),
        (1, b'{"id":1e3,"result":{"status":"VALID"}}'), (1, b'{"id":"1","result":{"status":"VALID"}}'),
        (1, b'{"id":18446744073709551616,"result":{"status":"VALID"}}'), (1, b'{"id":1}'), (1, b'{"id":1,"result":{}}'),
        (1, b'{"id":1,"result":{"status":"valid"}}'), (1, b'{"id":1,"result":{"status":"VALID","latestValidHash":"0xab"}}'),
        (1, b'{"id":1,"result":{"status":"VALID","latestValidHash":"0x' + b"zz" * 32 + b'"}}'),
        (1, b'{"id":1,"result":{"status":"VALID","latestValidHash":7}}'), (1, b'{"id":1,"result":"VALID"}'),
        (1, b'{"id":1,"result":{"status":"VAL\\u0049D"}}'), (1, b'{"id":1,"x":"\\q","result":{"status":"VALID"}}'),
        (1, b'{"id":1,"x":[1,2,"result":{"status":"VALID"}}'), (1, b'{"id":1,"result":{"status":"VALID"},}'),
        (1, b'{"id":1 "result":{"status":"VALID"}}'), (1, b'{"id":1,"result":{"status":"VALID"}}}'),
        (1, b'{"id":1,"x":tru,"result":{"status":"VALID"}}'), (1, b'{"id":1,"x":"a\nb","result":{"status":"VALID"}}'),
        (1, b'{"id":1,"error":{"message":"m"}}'), (1, b'{"id":1,"error":{"code":1.5}}'), (1, b'{"id":1,"error":{"code":9223372036854775808}}'),
        (1, b'{"id":1,"x":01,"result":{"status":"VALID"}}'), (1, b'{"id":01,"result":{"status":"VALID"}}'),
        (2, b'{"id":1,"result":{"status":"VALID"}}'), (2, b'{"id":1,"result":{"payloadStatus":{"status":"VALID"},"payloadId":"0x01"}}'),
        (3, b'{"id":1,"result":{"status":"VALID"}}'), (3, b'{"id":1,"result":["engine_newPayloadV1",1]}'),
        (4, b'{"id":1,"result":null}'), (4, b'{"id":1,"result":[]}'), (4, b'{"id":1,"result":"0x"}'), (4, b'{"id":1}'),
        (4, b'{"id":1,"result":{"a":}}'), (4, b'{"id":1,"result":{"a":1}'), (4, b'{"id":1,"result":{"a":[1}]}}'),
    ]
    for k, (method, body) in enumerate(bad):
        out.append((f"bad_{k}", method, body, "invalid"))
    # an ignored member's value that breaks RFC 8259
    for k, value in enumerate([b"[1,]", b'{"a" 1}', b"{1:2}", b"[1:2]", b'{"a":}', b"{,}", b"[,1]", b'{"a":1,}', b"[1 2]",
                               b'{"a":1 "b":2}', b'{"a"::1}', b"[1,,2]", b"{]", b"[}", b'{"a":[}]}', b'["a":1]', b"[[[]]", b"{{}}"]):
        body = b'{"id":1,"x":' + value + b',"result":{"status":"VALID"}}'
        try:
            json.loads(body)
        except ValueError:
            out.append((f"bad_member_{k}", 1, body, "invalid"))
        else:
            raise RuntimeError(f"Python's json takes {body!r}")
    body = b'{"id":1,"x":[[],{},[{}],{"a":[]},{"b":{"c":[1,{"d":null}]}}],"result":{"status":"VALID"}}'
    out.append(("np_nested_members", 1, body, want(1, 1)))
    return out


def response_case_parts():
    for name, method, body, w in response_cases():
        if w != "invalid":
            w = dict(w)
            w["latest_valid_hash"] = w["latest_valid_hash"] if w["latest_valid_hash"] is not None else None
        yield "parse_response", name, {"input": {"body": body, "method": method}, "output": w}
