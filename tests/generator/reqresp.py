"""Cases of lantern's req/resp encoding (docs/reference/req-resp.md), and the message types.

The message types follow the text of p2p-interface.md of phase0, altair, deneb and fulu at
consensus-specs v1.7.0-beta.4 (aa16bb4), built from the fork's spec module, which gives the list
types it defines in code. The chunks follow the Req/Resp domain of phase0 and altair: a result
byte, the context bytes, the SSZ length as an unsigned protobuf varint, then Snappy frames, made
here with python-snappy 0.7.3 block compression and the framing format of google/snappy.
The size bounds follow the rules of remerkleable, the reference of the spec's "What are SSZ
type size bounds", over the types of the spec module.

message_types(spec, fork) gives the types for the descriptor cases; cases(fork, preset) yields
(handler, name, parts).
"""

import struct

import snappy
from ssz.bitfields import BitList, BitVector
from ssz.boolean import Boolean
from ssz.byte_arrays import ByteList, ByteVector
from ssz.collections import List, Vector
from ssz.container import Container
from ssz.uint import BaseUint

FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")
U64 = (1 << 64) - 1

# Methods (include/lantern.inc REQRESP_*): name and versions.
METHODS = [
    ("status", (1, 2)),
    ("goodbye", (1,)),
    ("beacon_blocks_by_range", (1, 2)),
    ("beacon_blocks_by_root", (1, 2)),
    ("ping", (1,)),
    ("metadata", (1, 2, 3)),
    ("blob_sidecars_by_range", (1,)),
    ("blob_sidecars_by_root", (1,)),
    ("data_column_sidecars_by_range", (1,)),
    ("data_column_sidecars_by_root", (1,)),
    ("beacon_blocks_by_head", (1,)),
    ("light_client_bootstrap", (1,)),
    ("light_client_updates_by_range", (1,)),
    ("light_client_finality_update", (1,)),
    ("light_client_optimistic_update", (1,)),
]


def container(spec, name, fields):
    return type(name, (Container,), {"__annotations__": dict(fields), "__module__": spec.__name__})


def api_body_types(spec, fork):
    """Lantern's containers of the JSON objects of Beacon API request bodies (beacon-APIs v4.0.0), by
    name: the items of prepareBeaconCommitteeSubnet, prepareSyncCommitteeSubnets (from altair; a
    validator has at most SYNC_COMMITTEE_SIZE places) and prepareBeaconProposer."""
    t = {"BeaconCommitteeSubscription": container(spec, "BeaconCommitteeSubscription", [
        ("validator_index", spec.ValidatorIndex), ("committee_index", spec.CommitteeIndex),
        ("committees_at_slot", spec.Uint64), ("slot", spec.Slot), ("is_aggregator", Boolean)])}
    if FORKS.index(fork) >= FORKS.index("altair"):
        indices = type("SyncCommitteeIndices", (List[spec.Uint64],),
                       {"LIMIT": int(spec.SYNC_COMMITTEE_SIZE), "__module__": spec.__name__})
        t["SyncCommitteeSubscription"] = container(spec, "SyncCommitteeSubscription", [
            ("validator_index", spec.ValidatorIndex), ("sync_committee_indices", indices),
            ("until_epoch", spec.Epoch)])
    t["ProposerPreparation"] = container(spec, "ProposerPreparation", [
        ("validator_index", spec.ValidatorIndex), ("fee_recipient", spec.ExecutionAddress)])
    return t


def engine_result_types(spec, fork):
    """Lantern's containers of the result of engine_getPayload (execution-apis 981aa66), by name:
    GetPayloadResult from capella, BlobsBundle from deneb (BlobsBundleV2 in fulu), the request
    list from electra."""
    f = FORKS.index(fork)
    t = {}
    if f < FORKS.index("capella"):
        return t

    def limited(name, base, limit):
        return type(name, (base,), {"LIMIT": int(limit), "__module__": spec.__name__})
    fields = [("execution_payload", spec.ExecutionPayload), ("block_value", spec.Uint256)]
    if f >= FORKS.index("deneb"):
        per_blob = int(spec.CELLS_PER_EXT_BLOB) if f >= FORKS.index("fulu") else 1
        bundle = container(spec, "BlobsBundle", [
            ("commitments", spec.BlobKZGCommitments),
            ("proofs", limited("BundleProofs", List[spec.KZGProof], int(spec.MAX_BLOB_COMMITMENTS_PER_BLOCK) * per_blob)),
            ("blobs", limited("BundleBlobs", List[spec.Blob], spec.MAX_BLOB_COMMITMENTS_PER_BLOCK))])
        t["BlobsBundle"] = bundle
        fields += [("blobs_bundle", bundle), ("should_override_builder", Boolean)]
    if f >= FORKS.index("electra"):
        request = limited("RequestBytes", ByteList, 1 + 192 * int(spec.MAX_DEPOSIT_REQUESTS_PER_PAYLOAD))
        fields += [("execution_requests", limited("ExecutionRequestsList", List[request], 3))]
    t["GetPayloadResult"] = container(spec, "GetPayloadResult", fields)
    return t


def produce_types(spec, fork):
    """Lantern's containers of block production and publishing (node.md, produceBlockV3 and
    publishBlockV2), by name: from deneb BlockContents, the block with the bundle's proofs and
    blobs, and SignedBlockContents, the signed block with them."""
    t = {}
    if FORKS.index(fork) >= FORKS.index("deneb"):
        bundle = engine_result_types(spec, fork)["BlobsBundle"].__annotations__
        t["SignedBlockContents"] = container(spec, "SignedBlockContents", [("signed_block", spec.SignedBeaconBlock),
                                                                           ("kzg_proofs", bundle["proofs"]), ("blobs", bundle["blobs"])])
        t["BlockContents"] = container(spec, "BlockContents", [("block", spec.BeaconBlock), ("kzg_proofs", bundle["proofs"]),
                                                               ("blobs", bundle["blobs"])])
    return t


def message_types(spec, fork):
    """The req/resp message types of the fork, by name."""
    f = FORKS.index(fork)
    t = {}
    status = [("fork_digest", spec.ForkDigest), ("finalized_root", spec.Root), ("finalized_epoch", spec.Epoch),
              ("head_root", spec.Root), ("head_slot", spec.Slot)]
    t["Status"] = container(spec, "Status", status)
    if f >= FORKS.index("fulu"):
        t["StatusV2"] = container(spec, "StatusV2", status + [("earliest_available_slot", spec.Slot)])
    meta = [("seq_number", spec.Uint64), ("attnets", spec.Attnets)]
    t["MetaData"] = container(spec, "MetaData", meta)
    if f >= FORKS.index("altair"):
        t["MetaDataV2"] = container(spec, "MetaDataV2", meta + [("syncnets", spec.Syncnets)])
    if f >= FORKS.index("fulu"):
        t["MetaDataV3"] = container(spec, "MetaDataV3", meta + [("syncnets", spec.Syncnets), ("custody_group_count", spec.Uint64)])
    t["BeaconBlocksByRangeRequest"] = container(
        spec, "BeaconBlocksByRangeRequest", [("start_slot", spec.Slot), ("count", spec.Uint64), ("step", spec.Uint64)])
    t["BeaconBlockRoots"] = spec.BeaconBlockRoots
    t["ErrorMessage"] = spec.ErrorMessage
    if fork in ("deneb", "electra"):
        t["BlobSidecarsByRangeRequest"] = container(
            spec, "BlobSidecarsByRangeRequest", [("start_slot", spec.Slot), ("count", spec.Uint64)])
        t["BlobIdentifiers"] = type("BlobIdentifiers", (List[spec.BlobIdentifier],),
                                    {"LIMIT": int(spec.compute_max_request_blob_sidecars()), "__module__": spec.__name__})
    if f >= FORKS.index("fulu"):
        t["DataColumnSidecarsByRangeRequest"] = container(
            spec, "DataColumnSidecarsByRangeRequest",
            [("start_slot", spec.Slot), ("count", spec.Uint64), ("columns", spec.DataColumnIndices)])
        t["DataColumnsByRootIdentifiers"] = spec.DataColumnsByRootIdentifiers
        t["BeaconBlocksByHeadRequest"] = container(
            spec, "BeaconBlocksByHeadRequest", [("beacon_root", spec.Root), ("count", spec.Uint64)])
    t["ENRForkID"] = container(
        spec, "ENRForkID", [("fork_digest", spec.ForkDigest), ("next_fork_version", spec.Version), ("next_fork_epoch", spec.Epoch)])
    return t


def is_fixed(t):
    return t.is_fixed_size()


def bounds(t):
    """(min, max) SSZ bytes of type t, as remerkleable's min_byte_length and max_byte_length."""
    if issubclass(t, (BaseUint, Boolean, ByteVector, BitVector)) or (issubclass(t, (Vector, Container)) and is_fixed(t)):
        n = t.fixed_size() if hasattr(t, "fixed_size") else t.get_byte_length()
        return n, n
    if issubclass(t, BitList):
        return 1, t.LIMIT // 8 + 1
    if issubclass(t, ByteList):
        return 0, t.LIMIT
    if issubclass(t, List):
        e = t.ELEMENT_TYPE
        lo, hi = bounds(e)
        return 0, t.LIMIT * (hi if is_fixed(e) else 4 + hi)
    if issubclass(t, Vector):
        lo, hi = bounds(t.ELEMENT_TYPE)
        return t.LENGTH * (4 + lo), t.LENGTH * (4 + hi)
    if issubclass(t, Container):
        lo = hi = 0
        for _, ft in t._FIELD_TYPES:
            a, b = bounds(ft)
            if is_fixed(ft):
                lo, hi = lo + a, hi + b
            else:
                lo, hi = lo + 4 + a, hi + 4 + b
        return lo, hi
    raise ValueError(f"no bounds for {t}")


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


CRC_TABLE = []
for i in range(256):
    c = i
    for _ in range(8):
        c = (c >> 1) ^ 0x82F63B78 if c & 1 else c >> 1
    CRC_TABLE.append(c)


def masked_crc(data):
    c = 0xFFFFFFFF
    for b in data:
        c = CRC_TABLE[(c ^ b) & 0xFF] ^ (c >> 8)
    c ^= 0xFFFFFFFF
    return ((((c >> 15) | (c << 17)) & 0xFFFFFFFF) + 0xA282EAD8) & 0xFFFFFFFF


STREAM_ID = b"\xff\x06\x00\x00sNaPpY"


def frame(kind, body):
    return bytes([kind]) + struct.pack("<I", len(body))[:3] + body


def frames(data, compress=True, split=65536):
    """The framing format of google/snappy: the stream identifier, then a chunk per split bytes."""
    if not data:
        return b""
    out = bytearray(STREAM_ID)
    for i in range(0, len(data), split):
        part = data[i : i + split]
        crc = struct.pack("<I", masked_crc(part))
        if compress:
            out += frame(0x00, crc + snappy.compress(part))
        else:
            out += frame(0x01, crc + part)
    return bytes(out)


def header_case(kind, context_length, result, context, length, more=b""):
    head = b""
    if kind == 1:
        head += bytes([result])
        if result == 0 and context_length:
            head += context
    head += varint(length)
    return head


def cases(fork, preset):
    spec = __import__(f"eth_consensus_specs.{fork}.{preset}", fromlist=["*"])

    # Size bounds of every root type: the spec module's containers and the message types.
    types = {}
    for name in sorted(dir(spec)):
        t = getattr(spec, name)
        if isinstance(t, type) and issubclass(t, Container) and t is not Container and t.__name__ == name:
            types[name] = t
    types.update(message_types(spec, fork))
    for name, t in sorted(types.items()):
        try:
            lo, hi = bounds(t)
        except ValueError:
            continue
        yield "ssz_size_bounds", name, {"input": {"type": name}, "output": {"min": lo, "max": min(hi, U64)}}

    # Protocol IDs.
    for m, (name, versions) in enumerate(METHODS, 1):
        for v in versions:
            pid = f"/eth2/beacon_chain/req/{name}/{v}/ssz_snappy".encode()
            yield "protocol_parse", f"{name}_{v}", {"input": {"id": pid}, "output": {"method": m, "version": v}}
            yield "protocol_id", f"{name}_{v}", {"input": {"method": m, "version": v}, "output": pid}
        bad_v = max(versions) + 1
        yield "protocol_id", f"{name}_{bad_v}", {"input": {"method": m, "version": bad_v}, "output": None}
        for k, bad in enumerate([
            f"/eth2/beacon_chain/req/{name}/{bad_v}/ssz_snappy", f"/eth2/beacon_chain/req/{name}/{versions[0]}/ssz",
            f"/eth2/beacon_chain/req/{name}/{versions[0]}/ssz_snappy/", f"/eth2/beacon_chain/req/{name}/0{versions[0]}/ssz_snappy",
            f"/eth2/beacon_chain/req/{name}//ssz_snappy", f"/eth2/beacon_chain/req/{name.upper()}/{versions[0]}/ssz_snappy",
            f"eth2/beacon_chain/req/{name}/{versions[0]}/ssz_snappy",
        ]):
            yield "protocol_parse", f"{name}_bad_{k}", {"input": {"id": bad.encode()}, "output": None}
    for k, bad in enumerate([b"", b"/eth2/beacon_chain/req/", b"/eth2/beacon_chain/req/light_client_bootstraps/1/ssz_snappy",
                             b"/meshsub/1.1.0", b"/eth2/beacon_chain/req/status/18446744073709551617/ssz_snappy"]):
        yield "protocol_parse", f"bad_{k}", {"input": {"id": bad}, "output": None}
    for k, (m, v) in enumerate([(0, 1), (16, 1), (U64, 1), (1, 0), (1, U64)]):
        yield "protocol_id", f"bad_{k}", {"input": {"method": m, "version": v}, "output": None}

    # The chunk size bound.
    for n in [0, 1, 65535, 65536, 65537, 10485760, U64 - 100, U64]:
        c = -(-n // 65536)
        size = 1 + 4 + 10 + 10 + n + 8 * c
        yield "chunk_size", f"n_{n}", {"input": {"n": n}, "output": size if size <= U64 else None}

    # Headers: (kind, context_length, bytes) -> the header, or "more" or "invalid".
    digest = bytes.fromhex("446a7232")
    heads = []
    for kind in (0, 1):
        for context_length in (0, 4) if kind else (0,):
            for result in (0, 1, 2, 3, 128, 255) if kind else (0,):
                for length in (0, 1, 127, 128, 300, 16383, 16384, 10485760, (1 << 63) + 5, U64):
                    head = header_case(kind, context_length, result, digest, length)
                    ctx = digest if kind and result == 0 and context_length else bytes(4)
                    want = {"result": result, "context": ctx, "length": length, "header_bytes": len(head)}
                    heads.append((f"{kind}_{context_length}_{result}_{length}", kind, context_length, head + b"\x00\x01", want))
                    for cut in range(len(head)):
                        heads.append((f"{kind}_{context_length}_{result}_{length}_cut{cut}", kind, context_length, head[:cut], "more"))
    heads.append(("not_shortest", 0, 0, b"\x81\x80\x80\x00", {"result": 0, "context": bytes(4), "length": 1, "header_bytes": 4}))
    heads.append(("ten_bytes_max", 0, 0, b"\xff" * 9 + b"\x01", {"result": 0, "context": bytes(4), "length": U64, "header_bytes": 10}))
    heads.append(("ten_bytes_over", 0, 0, b"\xff" * 9 + b"\x02", "invalid"))
    heads.append(("eleven_bytes", 0, 0, b"\x80" * 10 + b"\x00", "invalid"))
    heads.append(("ten_continue", 0, 0, b"\x80" * 10, "invalid"))
    heads.append(("nine_continue", 0, 0, b"\x80" * 9, "more"))
    for name, kind, context_length, data, want in heads:
        parts = {"input": {"kind": kind, "context_length": context_length, "bytes": data},
                 "output": want if isinstance(want, dict) else want}
        yield "read_header", name, parts

    # Payloads: (bytes, length, eof) -> (payload, consumed), or "more" or "invalid".
    payloads = [b"", b"\x00", bytes(range(256)) * 3, b"\x07" * 70000, bytes(range(256)) * 600]
    for k, p in enumerate(payloads):
        for compress in (True, False):
            f = frames(p, compress)
            for tail in (b"", b"\x01\x02"):
                yield "read_payload", f"{k}_{int(compress)}_{len(tail)}", {
                    "input": {"bytes": f + tail, "length": len(p), "eof": 1}, "output": {"payload": p, "consumed": len(f)}}
            if p:
                for cut in sorted({1, 4, 10, len(f) // 2, len(f) - 1}):
                    for eof in (0, 1):
                        yield "read_payload", f"{k}_{int(compress)}_cut{cut}_eof{eof}", {
                            "input": {"bytes": f[:cut], "length": len(p), "eof": eof}, "output": "invalid" if eof else "more"}
            if len(p) > 1:  # the frames give more than the length (a length of 0 reads no frame)
                yield "read_payload", f"{k}_{int(compress)}_short_length", {
                    "input": {"bytes": f, "length": len(p) - 1, "eof": 1}, "output": "invalid"}
    small = bytes(range(100))
    good = frames(small)
    bad_crc = bytearray(good)
    bad_crc[14] ^= 1
    yield "read_payload", "bad_crc", {"input": {"bytes": bytes(bad_crc), "length": 100, "eof": 1}, "output": "invalid"}
    yield "read_payload", "no_stream_id", {"input": {"bytes": good[10:], "length": 100, "eof": 1}, "output": "invalid"}
    yield "read_payload", "unskippable", {
        "input": {"bytes": STREAM_ID + frame(0x02, b"abcd") + good[10:], "length": 100, "eof": 1}, "output": "invalid"}
    skippable = STREAM_ID + frame(0x80, b"abcd") + frame(0xFE, b"") + good[10:]
    yield "read_payload", "skippable", {
        "input": {"bytes": skippable, "length": 100, "eof": 1}, "output": {"payload": small, "consumed": len(skippable)}}
    # A stream over max_compressed_len(length): padding before the data.
    padded = STREAM_ID + frame(0xFE, bytes(200)) + good[10:]
    yield "read_payload", "over_max_compressed_len", {
        "input": {"bytes": padded, "length": 100, "eof": 1}, "output": "invalid"}
    yield "read_payload", "over_max_compressed_len_more", {
        "input": {"bytes": padded, "length": 100, "eof": 0}, "output": "invalid"}

    # Chunks to write; the runner reads each back.
    for k, p in enumerate(payloads):
        for kind, context_length, result in ((0, 0, 0), (1, 0, 0), (1, 4, 0), (1, 4, 3), (1, 0, 255)):
            yield "write_chunk", f"{k}_{kind}_{context_length}_{result}", {
                "input": {"kind": kind, "context_length": context_length, "result": result, "context": digest, "payload": p},
                "output": {"read_back": True}}
