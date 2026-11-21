"""Cases of lantern's eth1 follower functions (docs/reference/eth1.md).

The requests and the JSON follow execution-apis common.md; the logs follow the deposit contract's
DepositEvent (five ABI `bytes` values, amount and index little endian); the tree follows the
pinned spec: its root is hash_tree_root of the list of DepositData, and each proof must pass the
spec's is_valid_merkle_branch of depth DEPOSIT_CONTRACT_TREE_DEPTH + 1, as process_deposit checks
it. Values come from SHA-256 of a counter, so every run gives the same cases.

cases(preset) yields (kind, name, parts) with kind one of requests, block, logs, tree:
- requests: kind 0 (eth_getBlockByNumber) with number, id; kind 1 (eth_getLogs) with address,
  from, to, id; text the request.
- block: text; status (0 LANTERN_OK, 1 LANTERN_INVALID_JSON); number, timestamp, hash.
- logs: text; status (0, 1 LANTERN_INVALID_JSON, 2 LANTERN_INVALID_DEPOSIT_LOG); entries the
  Eth1Deposit bytes.
- tree: datas (DepositData, 184 bytes each); leaves (32 bytes each); roots the root after each push;
  proofs [count, index, proof].
"""

import hashlib
import json
import struct

TOPIC = bytes.fromhex("649bbc62d0e31342afea4e5cd82d4049e7e1ee912fc0889aa790803be39038c5")
U64 = (1 << 64) - 1
OK, INVALID_JSON, INVALID_LOG = 0, 1, 2


def made(*parts, n=32):
    out = b""
    k = 0
    while len(out) < n:
        out += hashlib.sha256(repr(parts + (k,)).encode()).digest()
        k += 1
    return out[:n]


def qty(n):
    return hex(n)


def data(b):
    return "0x" + b.hex()


def request_block(number, rid):
    num = "latest" if number == U64 else qty(number)
    return ('{"jsonrpc":"2.0","id":%d,"method":"eth_getBlockByNumber","params":["%s",false]}' % (rid, num)).encode()


def request_logs(address, frm, to, rid):
    return ('{"jsonrpc":"2.0","id":%d,"method":"eth_getLogs","params":[{"address":"%s","topics":["%s"],"fromBlock":"%s","toBlock":"%s"}]}'
            % (rid, data(address), data(TOPIC), qty(frm), qty(to))).encode()


def abi_bytes(values):
    """The ABI encoding of a tuple of dynamic bytes values."""
    head, tail = b"", b""
    off = 32 * len(values)
    for v in values:
        head += off.to_bytes(32, "big")
        enc = len(v).to_bytes(32, "big") + v + b"\0" * (-len(v) % 32)
        tail += enc
        off += len(enc)
    return head + tail


def deposit(k):
    """A made up DepositData's fields: pubkey, withdrawal_credentials, amount, signature."""
    return made("pk", k, n=48), made("wc", k), int.from_bytes(made("am", k, n=8), "little") % (64 * 10**9), made("sig", k, n=96)


def log_of(k, block, index, removed=None, topic=TOPIC, data_bytes=None, extra=False):
    pk, wc, am, sig = deposit(k)
    d = data_bytes if data_bytes is not None else abi_bytes([pk, wc, am.to_bytes(8, "little"), sig, index.to_bytes(8, "little")])
    o = {"address": data(made("addr", n=20)), "topics": [data(topic)], "data": data(d), "blockNumber": qty(block),
         "transactionHash": data(made("tx", k)), "transactionIndex": "0x0", "blockHash": data(made("bh", block)),
         "logIndex": qty(k)}
    if removed is not None:
        o["removed"] = removed
    if extra:
        o["extra"] = {"a": [1, 2, {"b": None}], "c": "x"}
    return o


def entry(k, block, index):
    pk, wc, am, sig = deposit(k)
    return struct.pack("<QQ", block, index) + pk + wc + struct.pack("<Q", am) + sig


def dumps(v, style):
    if style == 0:
        return json.dumps(v, separators=(",", ":")).encode()
    if style == 1:
        return json.dumps(v, indent=2).encode()
    return (" \n" + json.dumps(v, separators=(", ", " : ")) + "\t ").encode()


def cases(preset):
    spec = __import__(f"eth_consensus_specs.phase0.{preset}", fromlist=["*"])
    depth = int(spec.DEPOSIT_CONTRACT_TREE_DEPTH)
    # requests
    for i, (number, rid) in enumerate([(0, 1), (1, 7), (255, 2**32), (2**40 + 5, 9), (U64 - 1, 3), (U64, 0)]):
        yield "requests", f"block_{i}", {"kind": 0, "number": number, "id": rid, "text": request_block(number, rid)}
    for i, (frm, to, rid) in enumerate([(0, 0, 1), (0, 999, 2), (12345, 13344, 77), (U64 - 1, U64 - 1, 5)]):
        address = made("contract", i, n=20)
        yield "requests", f"logs_{i}", {"kind": 1, "address": address, "from": frm, "to": to, "id": rid,
                                        "text": request_logs(address, frm, to, rid)}
    # blocks
    for i in range(6):
        number, ts, h = int.from_bytes(made("n", i, n=4), "little"), 1_600_000_000 + 12 * i, made("hash", i)
        o = {"number": qty(number), "hash": data(h), "timestamp": qty(ts), "parentHash": data(made("p", i)),
             "transactions": [], "uncles": [], "extraData": "0x", "baseFeePerGas": "0x7"}
        if i % 2:
            o = dict(reversed(list(o.items())))
        yield "block", f"block_{i}", {"text": dumps(o, i % 3), "status": OK, "number": number, "timestamp": ts, "hash": h}
    bad = [b"null", b"[]", b'{"number":"0x1","hash":"0x' + b"00" * 32 + b'"}', b'{"number":"0x01","hash":"0x' + b"00" * 32 + b'","timestamp":"0x1"}',
           b'{"number":"0x1","hash":"0x' + b"00" * 31 + b'","timestamp":"0x1"}', b'{"number":"0x10000000000000000","hash":"0x' + b"00" * 32 + b'","timestamp":"0x1"}',
           b'{"number":"0x1","hash":"0x' + b"00" * 32 + b'","timestamp":"0x1"} x', b'{"number":"0x","hash":"0x' + b"00" * 32 + b'","timestamp":"0x1"}']
    for i, t in enumerate(bad):
        yield "block", f"bad_{i}", {"text": t, "status": INVALID_JSON, "number": 0, "timestamp": 0, "hash": bytes(32)}
    # logs
    yield "logs", "empty", {"text": b"[]", "status": OK, "entries": b""}
    for n in (1, 3, 8):
        logs = [log_of(k, 100 + k // 2, k, removed=(False if k % 2 else None), extra=bool(k % 3 == 2)) for k in range(n)]
        ents = b"".join(entry(k, 100 + k // 2, k) for k in range(n))
        yield "logs", f"logs_{n}", {"text": dumps(logs, n % 3), "status": OK, "entries": ents}
    logs = [log_of(0, 5, 0), log_of(1, 6, 1, removed=True), log_of(2, 7, 2)]
    yield "logs", "removed", {"text": dumps(logs, 0), "status": OK, "entries": entry(0, 5, 0) + entry(2, 7, 2)}
    yield "logs", "other_topic", {"text": dumps([log_of(0, 5, 0, topic=made("t"))], 0), "status": INVALID_JSON, "entries": b""}
    pk, wc, am, sig = deposit(0)
    good = abi_bytes([pk, wc, am.to_bytes(8, "little"), sig, (0).to_bytes(8, "little")])
    wrong = [
        abi_bytes([pk[:47], wc, am.to_bytes(8, "little"), sig, (0).to_bytes(8, "little")]),
        abi_bytes([pk, wc, am.to_bytes(8, "little"), sig, (0).to_bytes(9, "little")]),
        good[:-1],
        good + b"\0" * 32,
        good[:160 + 32 + 48] + b"\1" + good[160 + 32 + 49:],  # a padding byte that is not zero
        (161).to_bytes(32, "big") + good[32:],
    ]
    for i, d in enumerate(wrong):
        yield "logs", f"bad_data_{i}", {"text": dumps([log_of(0, 5, 0, data_bytes=d)], 0), "status": INVALID_LOG, "entries": b""}
    for i, t in enumerate([b"{}", b"[1]", b'[{"blockNumber":"0x1"}]', b"[", b'[{"blockNumber":"0x1","topics":[],"data":"0x"}]']):
        yield "logs", f"bad_json_{i}", {"text": t, "status": INVALID_JSON, "entries": b""}
    # the tree
    for n in (1, 2, 5, 16, 33):
        datas = []
        leaves, roots, raw = b"", b"", b""
        for k in range(n):
            pk, wc, am, sig = deposit(1000 * n + k)
            d = spec.DepositData(pubkey=spec.BLSPubkey(pk), withdrawal_credentials=spec.Bytes32(wc), amount=spec.Gwei(am),
                                 signature=spec.BLSSignature(sig))
            datas.append(d)
            raw += pk + wc + am.to_bytes(8, "little") + sig
            leaves += bytes(spec.hash_tree_root(d))
            roots += bytes(spec.hash_tree_root(spec.DepositDataList(data=datas)))
        proofs = []
        for count in sorted({1, n // 2 or 1, n}):
            root = spec.hash_tree_root(spec.DepositDataList(data=datas[:count]))
            for index in sorted({0, count // 2, count - 1}):
                proof = proof_of([leaves[32 * j:32 * j + 32] for j in range(count)], index, depth)
                leaf = spec.hash_tree_root(datas[index])
                if not spec.is_valid_merkle_branch(leaf, [spec.Bytes32(p) for p in proof], depth + 1, index, root):
                    raise AssertionError("eth1.py: a proof the spec does not take")
                proofs.append([count, index, b"".join(proof)])
        yield "tree", f"tree_{n}", {"datas": raw, "leaves": leaves, "roots": roots, "proofs": proofs}


def proof_of(leaves, index, depth):
    """The branch of leaf index in the depth-deep tree of leaves, then the count as 32 little endian bytes."""
    zero = [bytes(32)]
    for _ in range(depth):
        zero.append(hashlib.sha256(zero[-1] * 2).digest())
    level = list(leaves)
    out = []
    i = index
    for d in range(depth):
        sib = i ^ 1
        out.append(level[sib] if sib < len(level) else zero[d])
        nxt = []
        for j in range(0, len(level), 2):
            a = level[j]
            b = level[j + 1] if j + 1 < len(level) else zero[d]
            nxt.append(hashlib.sha256(a + b).digest())
        level = nxt
        i //= 2
    out.append(len(leaves).to_bytes(32, "little"))
    return out
