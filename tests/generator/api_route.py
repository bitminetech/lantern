"""Cases of lantern_api_route (docs/reference/beacon-api.md).

route() below follows the rules of lantern_api_route, apart from the assembly. operations() reads
the operations from the beacon-APIs clone at the pinned commit (BEACON_APIS, from run.sh), so the
table of the assembly (include/api_routes.inc) is checked against the spec. A parameter, enum or
response of the spec that the rules do not name stops it.

cases() yields (name, parts): the request's "method", "path", "query", "accept", "content_type" and
"consensus_version"; "status"; for LANTERN_OK, "out", the whole ApiRoute; for
LANTERN_INVALID_ROUTE, "http_status", "fault", "allow" and "op".
"""
import os
import pathlib
import struct

from ruamel.yaml import YAML

OK, BUFFER_TOO_SMALL, INVALID_ROUTE = 0, 1, 64
GET, POST, OTHER = 1, 2, 3
JSON, SSZ = 1, 2
FIXED = 488
U64 = 2 ** 64
FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")
HEX = b"0123456789abcdefABCDEF"
BASE58 = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

# API_PARAM_<n>: n is the place in this tuple, from 1.
PARAMS = ("state_id", "block_id", "block_root", "validator_id", "peer_id", "epoch", "slot", "id", "status",
          "index", "committee_index", "subcommittee_index", "parent_root", "indices", "versioned_hashes",
          "broadcast_validation", "start_period", "count", "state", "direction", "syncing_status",
          "randao_reveal", "graffiti", "skip_randao_verification", "builder_boost_factor",
          "attestation_data_root", "beacon_block_root", "topics", "Eth-Consensus-Version")
P = {name: i + 1 for i, name in enumerate(PARAMS)}
NUMBERS = ("epoch", "slot", "index", "committee_index", "subcommittee_index", "start_period", "count",
           "builder_boost_factor")
ROOTS = ("parent_root", "attestation_data_root", "beacon_block_root")
LISTS = ("id", "indices", "versioned_hashes")
IDS = {b"head": 1, b"genesis": 2, b"finalized": 3, b"justified": 4}
ID_SLOT, ID_ROOT = 5, 6
STATUSES = ("pending_initialized", "pending_queued", "active_ongoing", "active_exiting", "active_slashed",
            "exited_unslashed", "exited_slashed", "withdrawal_possible", "withdrawal_done")
GROUPS = {"pending": 0b11, "active": 0b11100, "exited": 0b1100000, "withdrawal": 0b110000000}
PEER_STATES = ("disconnected", "connecting", "connected", "disconnecting")
DIRECTIONS = ("inbound", "outbound")
TOPICS = ("head", "block", "block_gossip", "attestation", "single_attestation", "voluntary_exit",
          "bls_to_execution_change", "proposer_slashing", "attester_slashing", "finalized_checkpoint",
          "chain_reorg", "contribution_and_proof", "light_client_finality_update",
          "light_client_optimistic_update", "payload_attributes", "blob_sidecar", "data_column_sidecar",
          "head_v2", "execution_payload_available")
# The validator client additions of beacon-APIs v5.0.0-beta.0 (BEACON_APIS_V5, from run.sh; beacon-api.md, Spec):
# its operations by operationId, after the 76 of v4.0.0, and its topics, after those of v4.0.0.
V5_OPS = ("getProposerDutiesV2",)
V5_TOPICS = ("head_v2", "execution_payload_available")
BROADCAST = {b"gossip": 1, b"consensus": 2, b"consensus_and_equivocation": 3}
# Flags of an operation in include/api_routes.inc.
F_SSZ_RESPONSE, F_SSZ_BODY, F_VERSION, F_ID_MAX, F_IDS_OBJECT, F_IDS_ARRAY = 1, 2, 4, 8, 16, 32
IDS_BODIES = {"postStateValidators": F_IDS_OBJECT, "postStateValidatorBalances": F_IDS_ARRAY,
              "postStateValidatorIdentities": F_IDS_ARRAY, "getSyncCommitteeRewards": F_IDS_ARRAY,
              "getAttestationsRewards": F_IDS_ARRAY, "getAttesterDuties": F_IDS_ARRAY,
              "getSyncCommitteeDuties": F_IDS_ARRAY, "getLiveness": F_IDS_ARRAY}


def sets():
    """name -> {item: bits} of each set parameter."""
    status = {s.encode(): 1 << i for i, s in enumerate(STATUSES)}
    status.update({g.encode(): b for g, b in GROUPS.items()})
    return {"status": status,
            "state": {s.encode(): 1 << i for i, s in enumerate(PEER_STATES)},
            "direction": {s.encode(): 1 << i for i, s in enumerate(DIRECTIONS)},
            "topics": {s.encode(): 1 << i for i, s in enumerate(TOPICS)}}


SETS = sets()


def fail(text):
    raise SystemExit("api_route.py: " + text)


# ---------------------------------------------------------------- The spec's operations

def load(path):
    with open(path) as f:
        return YAML(typ="safe").load(f)


def resolve(node, base):
    """Follows $ref links: (node, the file it is in)."""
    while isinstance(node, dict) and "$ref" in node:
        file, _, frag = node["$ref"].partition("#")
        base = (base.parent / file).resolve() if file else base
        node = load(base)
        for key in [k for k in frag.split("/") if k]:
            node = node[key]
    return node, base


def enum_of(schema, base):
    schema, base = resolve(schema, base)
    if schema.get("type") == "array":
        return enum_of(schema["items"], base)
    if "oneOf" in schema:
        return [v for s in schema["oneOf"] for v in enum_of(s, base)]
    return list(schema.get("enum", []))


def operation(path, method, op, file, n):
    """The dict of one operation of the spec: its name, method, template, query bits, flags."""
    name = op["operationId"]
    query = required = flags = 0
    for p in op.get("parameters", []):
        p, base = resolve(p, file)
        where, pname = p["in"], p["name"]
        if where == "header":
            if pname != "Eth-Consensus-Version" or not p.get("required"):
                fail(f"{name}: header {pname}")
            if enum_of(p["schema"], base) != list(FORKS):
                fail(f"{name}: Eth-Consensus-Version values {enum_of(p['schema'], base)}")
            flags |= F_VERSION
            continue
        if pname not in P:
            fail(f"{name}: parameter {pname} has no rule in beacon-api.md")
        if where == "path":
            if "{" + pname + "}" not in path or not p.get("required"):
                fail(f"{name}: path parameter {pname}")
            continue
        if where != "query":
            fail(f"{name}: parameter {pname} in {where}")
        query |= 1 << P[pname]
        if p.get("required"):
            required |= 1 << P[pname]
        if pname in SETS:
            want = sorted(x.decode() for x in SETS[pname] if x.decode() not in V5_TOPICS)
            if sorted(enum_of(p["schema"], base)) != want:
                fail(f"{name}: {pname} values {enum_of(p['schema'], base)}")
        if pname == "broadcast_validation" and sorted(enum_of(p["schema"], base)) != sorted(x.decode() for x in BROADCAST):
            fail(f"{name}: broadcast_validation values")
        if pname == "id" and resolve(p["schema"], base)[0].get("maxItems") not in (None, 64):
            fail(f"{name}: id maxItems")
    codes = {str(c) for c in op.get("responses", {})}
    if "406" in codes:
        flags |= F_SSZ_RESPONSE
    if "415" in codes:
        flags |= F_SSZ_BODY
    if "414" in codes:
        if resolve([p for p in op["parameters"] if resolve(p, file)[0]["name"] == "id"][0], file)[0]["schema"]["maxItems"] != 64:
            fail(f"{name}: 414 without 64 ids")
        flags |= F_ID_MAX
    if "requestBody" in op:  # a body of ids: an object of ids and statuses, or an array of ids
        schema, sbase = resolve(op["requestBody"]["content"]["application/json"]["schema"], file)
        item = resolve(schema.get("items", {}), sbase)[0]
        if schema.get("type") == "object" and set(schema.get("properties", {})) == {"ids", "statuses"}:
            flags |= F_IDS_OBJECT
        elif (schema.get("type") == "array" and item.get("type") == "string" and
              "public key" in item.get("description", "") and "validator index" in item.get("description", "")):
            flags |= F_IDS_ARRAY
        elif schema.get("type") == "array" and schema.get("items", {}).get("$ref", "").endswith("/Uint64"):
            flags |= F_IDS_ARRAY  # validator indices: read as ids; a public key is the operation's 400
    if flags & (F_IDS_OBJECT | F_IDS_ARRAY) != IDS_BODIES.get(name, 0):
        fail(f"{name}: body of ids {flags}")
    template = path.encode()
    for pname in PARAMS:
        template = template.replace(b"{" + pname.encode() + b"}", bytes([P[pname]]))
    if b"{" in template:
        fail(f"{path}: a path parameter with no rule")
    return {"n": n, "name": name, "method": GET if method == "get" else POST,
                "path": path, "template": template, "query": query, "required": required, "flags": flags}


def items(spec):
    """(path, method, operation, file) of each operation of the spec's beacon-node-oapi.yaml, in order."""
    main = load(spec / "beacon-node-oapi.yaml")
    for path, ref in main["paths"].items():
        file = (spec / ref["$ref"]).resolve()
        item = load(file)
        if set(item) - {"get", "post"}:
            fail(f"{path}: methods {sorted(item)}")
        for method in ("get", "post"):
            if method in item:
                yield path, method, item[method], file


def operations(spec):
    """The operations of beacon-node-oapi.yaml of v4.0.0, in order: a dict for each; then V5_OPS of
    the v5.0.0-beta.0 clone (BEACON_APIS_V5), in their order."""
    ops = [operation(path, method, op, file, k + 1) for k, (path, method, op, file) in enumerate(items(spec))]
    paths = len(load(spec / "beacon-node-oapi.yaml")["paths"])
    if len(ops) != 76 or paths != 69:
        fail(f"{paths} paths and {len(ops)} operations, not 69 and 76")
    v5 = pathlib.Path(os.environ["BEACON_APIS_V5"])
    found = {op["operationId"]: (path, method, op, file) for path, method, op, file in items(v5)}
    for name in V5_OPS:
        if name not in found:
            fail(f"{name}: not an operation of beacon-APIs v5.0.0-beta.0")
        ops.append(operation(*found[name], len(ops) + 1))
    events = (v5 / "apis" / "eventstream" / "index.yaml").read_text()
    for topic in V5_TOPICS:
        if f"- {topic}\n" not in events:
            fail(f"{topic}: not a topic of beacon-APIs v5.0.0-beta.0")
    return ops


# ---------------------------------------------------------------- The rules

class Fault(Exception):
    def __init__(self, http, fault=0, op=0, allow=0):
        self.http, self.fault, self.op, self.allow = http, fault, op, allow


def decode(b):
    out = bytearray()
    i = 0
    while i < len(b):
        if b[i] == 0x25:
            if i + 2 >= len(b) or b[i + 1] not in HEX or b[i + 2] not in HEX:
                raise Fault(400)
            out.append(int(b[i + 1:i + 3], 16))
            i += 3
        else:
            out.append(b[i])
            i += 1
    return bytes(out)


def number(v):
    if not v or any(c not in b"0123456789" for c in v) or int(v) >= U64:
        return None
    return int(v)


def hexbytes(v, n):
    if len(v) != 2 + 2 * n or v[:2] != b"0x" or any(c not in HEX for c in v[2:]):
        return None
    return bytes.fromhex(v[2:].decode())


def identifier(v, justified):
    """(kind, slot, root) of a state_id or block_id, or None."""
    if v in IDS and (justified or v != b"justified"):
        return IDS[v], 0, bytes(32)
    if number(v) is not None:
        return ID_SLOT, number(v), bytes(32)
    if hexbytes(v, 32) is not None:
        return ID_ROOT, 0, hexbytes(v, 32)
    return None


ESCAPES = {0x22: 0x22, 0x5C: 0x5C, 0x2F: 0x2F, 0x62: 8, 0x66: 12, 0x6E: 10, 0x72: 13, 0x74: 9}


def ids_body(body, obj):
    """(ids, statuses) of a body of ids (beacon-api.md): ValidatorRef items and status bits; raises
    ValueError(0) for a body that breaks the JSON rules, ValueError(param) for a bad item."""
    i = 0

    def ws():
        nonlocal i
        while i < len(body) and body[i] in b" \t\n\r":
            i += 1

    def text():
        """A string of RFC 8259 section 7: its value, each escape decoded (a \\u of 0x80 or more as 0x80)."""
        nonlocal i
        if i >= len(body) or body[i] != 0x22:
            raise ValueError(0)
        i += 1
        out = bytearray()
        while True:
            if i >= len(body) or body[i] < 0x20:
                raise ValueError(0)
            c = body[i]
            if c == 0x22:
                i += 1
                return bytes(out)
            if c != 0x5C:
                out.append(c)
                i += 1
            elif i + 1 < len(body) and body[i + 1] in ESCAPES:
                out.append(ESCAPES[body[i + 1]])
                i += 2
            elif body[i + 1:i + 2] == b"u" and len(body[i + 2:i + 6]) == 4 and all(x in HEX for x in body[i + 2:i + 6]):
                out.append(min(int(body[i + 2:i + 6], 16), 0x80))
                i += 6
            else:
                raise ValueError(0)

    def array(param):
        nonlocal i
        out = []
        if body[i:i + 4] == b"null":
            i += 4
            return out
        if i >= len(body) or body[i] != 0x5B:
            raise ValueError(0)
        i += 1
        ws()
        if i < len(body) and body[i] == 0x5D:
            i += 1
            return out
        while True:
            ws()
            s = text()
            got = validator(s) if param == "id" else SETS["status"].get(s)
            if got is None:
                raise ValueError(P[param])
            out.append(got)
            ws()
            if i < len(body) and body[i] == 0x2C:
                i += 1
                continue
            if i < len(body) and body[i] == 0x5D:
                i += 1
                return out
            raise ValueError(0)

    ids, statuses = [], 0
    if not obj and body == b"":
        return ids, statuses
    ws()
    if obj:
        if i >= len(body) or body[i] != 0x7B:
            raise ValueError(0)
        i += 1
        ws()
        seen = set()
        if i < len(body) and body[i] == 0x7D:
            i += 1
        else:
            while True:
                ws()
                key = text()
                if key not in (b"ids", b"statuses") or key in seen:
                    raise ValueError(0)
                seen.add(key)
                ws()
                if i >= len(body) or body[i] != 0x3A:
                    raise ValueError(0)
                i += 1
                ws()
                if key == b"ids":
                    ids = array("id")
                else:
                    for bits in array("status"):
                        statuses |= bits
                ws()
                if i < len(body) and body[i] == 0x2C:
                    i += 1
                    continue
                if i < len(body) and body[i] == 0x7D:
                    i += 1
                    break
                raise ValueError(0)
    else:
        ids = array("id")
    ws()
    if i != len(body):
        raise ValueError(0)
    return ids, statuses


def validator(v):
    if number(v) is not None:
        return struct.pack("<QQ", 1, number(v)) + bytes(48)
    if hexbytes(v, 48) is not None:
        return struct.pack("<QQ", 2, 0) + hexbytes(v, 48)
    return None


def methods_of(ops, template):
    return sum(1 << (o["method"] - 1) for o in ops if o["template"] == template)


def match(template, segs):
    tsegs = template[1:].split(b"/")
    if len(tsegs) != len(segs):
        return None
    params = []
    for t, s in zip(tsegs, segs):
        if len(t) == 1 and t[0] < 0x20:
            if not s:
                return None
            params.append((PARAMS[t[0] - 1], s))
        elif t != s:
            return None
    return params


def weight(accept, media):
    """The weight (0 to 1000) that Accept gives media (b"json" or b"octet-stream")."""
    best = (-1, 0)  # (specificity, weight)
    for item in accept.split(b","):
        item = item.strip(b" \t")
        if not item:
            continue
        fields = item.split(b";")
        rng = fields[0].strip(b" \t").lower()
        w = 1000
        broken = False
        for f in fields[1:]:
            f = f.strip(b" \t")
            if f[:2].lower() == b"q=":
                q = f[2:]
                if q[:1] == b"0" and (len(q) == 1 or (q[1:2] == b"." and len(q) <= 5 and all(c in b"0123456789" for c in q[2:]))):
                    w = int((q[2:] + b"000")[:3]) if len(q) > 2 else 0
                elif q[:1] == b"1" and (len(q) == 1 or (q[1:2] == b"." and len(q) <= 5 and all(c == 0x30 for c in q[2:]))):
                    w = 1000
                else:
                    broken = True
        if broken:
            continue
        spec = 2 if rng == b"application/" + media else 1 if rng == b"application/*" else 0 if rng == b"*/*" else -1
        if spec < 0:
            continue
        if spec > best[0] or (spec == best[0] and w > best[1]):
            best = (spec, w)
    return best[1] if best[0] >= 0 else 0


def route(ops, req, size):
    """(status, out bytes or Fault) by the rules of lantern_api_route."""
    if size < FIXED:
        return BUFFER_TOO_SMALL, None
    try:
        return route_checked(ops, req, size)
    except Fault as f:
        return INVALID_ROUTE, f


def route_checked(ops, req, size):
    segs = [decode(s) for s in req["path"][1:].split(b"/")]
    found = [(o, match(o["template"], segs)) for o in ops]
    found = [(o, ps) for o, ps in found if ps is not None]
    if not found:
        raise Fault(404)
    allow = methods_of(ops, found[0][0]["template"])
    mine = [(o, ps) for o, ps in found if o["method"] == req["method"]]
    if not mine:
        raise Fault(405, allow=allow)
    op, path_params = mine[0]
    n = op["n"]

    def bad(param, http=400):
        return Fault(http, P[param], n, allow)

    items = []
    try:
        for item in req["query"].split(b"&"):
            if not item:
                continue
            name, _, value = item.partition(b"=")
            items.append((decode(name), decode(value)))
    except Fault:
        raise Fault(400, 0, n, allow)
    f = {"present": 0, "id_kind": 0, "id_slot": 0, "id_root": bytes(32), "validator": bytes(64), "root": bytes(32),
         "randao_reveal": bytes(96), "graffiti": bytes(32), "statuses": 0, "state": 0, "direction": 0, "topics": 0,
         "broadcast_validation": 1 if op["query"] >> P["broadcast_validation"] & 1 else 0, "consensus_version": 0}
    for name in NUMBERS + ("syncing_status",):
        f[name] = 0
    lst, peer = [], b""
    for pname, v in path_params:
        f["present"] |= 1 << P[pname]
        if pname in ("state_id", "block_id"):
            got = identifier(v, pname == "state_id")
            if got is None:
                raise bad(pname)
            f["id_kind"], f["id_slot"], f["id_root"] = got
        elif pname == "block_root":
            if hexbytes(v, 32) is None:
                raise bad(pname)
            f["id_kind"], f["id_root"] = ID_ROOT, hexbytes(v, 32)
        elif pname == "validator_id":
            if validator(v) is None:
                raise bad(pname)
            f["validator"] = validator(v)
        elif pname == "peer_id":
            if not 1 <= len(v) <= 128 or any(c not in BASE58 for c in v):
                raise bad(pname)
            peer = v
        elif pname in NUMBERS:
            if number(v) is None:
                raise bad(pname)
            f[pname] = number(v)
        else:
            fail(f"path parameter {pname}")
    for name, v in items:
        pname = name.decode("latin-1")
        if pname not in P or not op["query"] >> P[pname] & 1:
            continue
        bit = 1 << P[pname]
        if pname in LISTS or pname in SETS:
            for x in v.split(b","):
                if pname == "id" and op["flags"] & F_ID_MAX and len(lst) == 64:
                    raise bad(pname, 414)
                if not x:
                    raise bad(pname)
                if pname == "id":
                    got = validator(x)
                elif pname == "indices":
                    got = None if number(x) is None else struct.pack("<Q", number(x))
                elif pname == "versioned_hashes":
                    got = hexbytes(x, 32)
                else:
                    got = SETS[pname].get(x)
                if got is None:
                    raise bad(pname)
                if pname in SETS:
                    f["statuses" if pname == "status" else pname] |= got
                else:
                    lst.append(got)
            f["present"] |= bit
            continue
        if f["present"] & bit:
            raise bad(pname)
        f["present"] |= bit
        if pname in NUMBERS:
            got = number(v)
        elif pname == "syncing_status":
            got = number(v) if number(v) is not None and 100 <= number(v) <= 599 else None
        elif pname in ROOTS:
            got = hexbytes(v, 32)
        elif pname == "randao_reveal":
            got = hexbytes(v, 96)
        elif pname == "graffiti":
            got = hexbytes(v, 32)
        elif pname == "skip_randao_verification":
            got = 1 if v == b"" else None
        elif pname == "broadcast_validation":
            got = BROADCAST.get(v)
        else:
            fail(f"query parameter {pname}")
        if got is None:
            raise bad(pname)
        if pname in ROOTS:
            f["root"] = got
        elif pname in ("randao_reveal", "graffiti", "broadcast_validation") or pname in NUMBERS or pname == "syncing_status":
            f[pname] = got
    missing = op["required"] & ~f["present"]
    if missing:
        raise Fault(400, (missing & -missing).bit_length() - 1, n, allow)
    if op["flags"] & F_VERSION:
        forks = [x.encode() for x in FORKS]
        if req["consensus_version"] not in forks:
            raise bad("Eth-Consensus-Version")
        f["consensus_version"] = forks.index(req["consensus_version"])
        f["present"] |= 1 << P["Eth-Consensus-Version"]
    body = 0
    if op["method"] == POST:
        body = JSON
        if op["flags"] & F_SSZ_BODY and req["content_type"]:
            t = req["content_type"].split(b";")[0].strip(b" \t").lower()
            if t == b"application/octet-stream":
                body = SSZ
            elif t != b"application/json":
                raise Fault(415, 0, n, allow)
    if op["flags"] & (F_IDS_OBJECT | F_IDS_ARRAY):
        try:
            ids, statuses = ids_body(req.get("body", b""), op["flags"] & F_IDS_OBJECT)
        except ValueError as e:
            raise Fault(400, e.args[0], n, allow)
        lst += ids
        f["statuses"] |= statuses
        f["present"] |= (1 << P["id"] if ids else 0) | (1 << P["status"] if statuses else 0)
    response = JSON
    if op["flags"] & F_SSZ_RESPONSE and req["accept"]:
        j, s = weight(req["accept"], b"json"), weight(req["accept"], b"octet-stream")
        if j == 0 and s == 0:
            raise Fault(406, 0, n, allow)
        response = SSZ if s > j else JSON
    out = struct.pack("<9Q", 0, 0, n, allow, 0, f["present"], response, body, f["consensus_version"])
    out += struct.pack("<QQ", f["id_kind"], f["id_slot"]) + f["id_root"] + f["validator"]
    out += struct.pack("<10Q", *(f[x] for x in ("epoch", "slot", "index", "committee_index", "subcommittee_index",
                                                 "start_period", "count", "syncing_status", "builder_boost_factor",
                                                 "broadcast_validation")))
    out += struct.pack("<4Q", f["statuses"], f["state"], f["direction"], f["topics"])
    out += f["root"] + f["randao_reveal"] + f["graffiti"]
    list_bytes = b"".join(lst)
    peer_off = FIXED + len(list_bytes)
    out += struct.pack("<4Q", FIXED if lst else 0, len(lst), peer_off if peer else 0, len(peer))
    assert len(out) == FIXED
    out += list_bytes + peer + bytes(-len(peer) % 8)
    if size < len(out):
        return BUFFER_TOO_SMALL, None
    out = struct.pack("<Q", size) + out[8:]
    return OK, out


# ---------------------------------------------------------------- The cases

def h(n, k=0):
    """0x and the hex of n bytes, letters in mixed case when k is odd."""
    text = bytes((0x11 * (i + 1) + k) % 256 for i in range(n)).hex()
    return b"0x" + (text.upper() if k % 2 else text).encode()


ROOT = h(32)
PUBKEY = h(48)
GOOD = {
    "state_id": [b"head", b"genesis", b"finalized", b"justified", b"0", b"123456", b"18446744073709551615",
                 b"00042", h(32), h(32, 1)],
    "block_id": [b"head", b"genesis", b"finalized", b"0", b"7", b"18446744073709551615", h(32), h(32, 1)],
    "block_root": [h(32), h(32, 1)],
    "validator_id": [b"0", b"12", b"18446744073709551615", h(48), h(48, 1)],
    "peer_id": [b"16Uiu2HAmRZx3Y8e6Vz1eV8Q1bVzKt5Cg4vVwHPqXw7ZcR8Gd5sJt", b"1", b"z" * 128],
    "id": [b"1", b"1,2,3", b"0x" + PUBKEY[2:] + b",5", b"7,7"],
    "status": [b"active", b"pending_initialized", b"withdrawal_done,exited", b"active,active_ongoing"],
    "indices": [b"0", b"1,3,5", b"18446744073709551615"],
    "versioned_hashes": [h(32), h(32) + b"," + h(32, 1)],
    "broadcast_validation": [b"gossip", b"consensus", b"consensus_and_equivocation"],
    "state": [b"connected", b"disconnected,connecting,disconnecting"],
    "direction": [b"inbound", b"outbound,inbound"],
    "syncing_status": [b"100", b"299", b"599", b"0503"],
    "randao_reveal": [h(96), b"0xc0" + b"00" * 95],
    "graffiti": [h(32), h(32, 1)],
    "skip_randao_verification": [b""],
    "attestation_data_root": [h(32)],
    "beacon_block_root": [h(32, 1)],
    "parent_root": [h(32)],
    "topics": [b"head", b",".join(t.encode() for t in TOPICS)],
}
for name in NUMBERS:
    GOOD[name] = [b"0", b"5", b"18446744073709551615", b"0000000000000000000000001"]
BAD_NUMBER = [b"", b"-1", b"+1", b"1.0", b"18446744073709551616", b"99999999999999999999", b"0x10", b" 1", b"1a"]
BAD_HEX32 = [b"", h(31), h(33), b"0X" + h(32)[2:], b"0x" + b"g" * 64, h(32) + b" ", b"x" + h(32)[1:]]
BAD = {
    "state_id": [b"", b"Head", b"latest", b"-1", b"18446744073709551616", b"0x"] + BAD_HEX32[1:],
    "block_id": [b"justified", b"HEAD", b"1e3", b"18446744073709551616"] + BAD_HEX32[1:],
    "block_root": [b"head", b"5"] + BAD_HEX32[1:],
    "validator_id": [b"-5", b"18446744073709551616", h(47), h(49), b"0x" + b"q" * 96, b"pk"],
    "peer_id": [b"0", b"16Uiu2HAmIl", b"O", b"z" * 129, b"abc-def"],
    "id": [b"", b"1,", b",1", b"1,,2", b"x", h(47)],
    "status": [b"", b"Active", b"active,", b"unknown", b"slashed"],
    "indices": [b"", b"1,", b"a", b"18446744073709551616"],
    "versioned_hashes": [b"", h(31), h(32) + b","],
    "broadcast_validation": [b"", b"Gossip", b"full"],
    "state": [b"", b"Connected", b"open"],
    "direction": [b"", b"in"],
    "syncing_status": [b"99", b"600", b"", b"abc", b"18446744073709551616"],
    "randao_reveal": [b"", h(95), h(97), b"0xc0"],
    "graffiti": [b"", h(31), h(33)],
    "skip_randao_verification": [b"1", b"true", b"x"],
    "attestation_data_root": BAD_HEX32,
    "beacon_block_root": BAD_HEX32,
    "parent_root": BAD_HEX32,
    "topics": [b"", b"Head", b"heads", b"head,", b"head,,block"],
}
for name in NUMBERS:
    BAD[name] = BAD_NUMBER
ACCEPT = [b"application/json", b"application/octet-stream", b"*/*", b"application/*", b"text/html",
          b"application/octet-stream;q=1.0,application/json;q=0.9", b"application/json;q=0.9, application/octet-stream",
          b"application/json, application/octet-stream", b"Application/Octet-Stream", b"application/json;q=0",
          b"application/json;q=0, application/octet-stream;q=0", b"application/json;q=0,*/*;q=0.5",
          b"*/*;q=0.1, application/octet-stream;q=0.2", b"*/*;q=0.3, application/json;q=0.2",
          b"application/octet-stream;q=1.5", b"application/octet-stream;q=0.1234, application/json;q=0.1",
          b"application/octet-stream;q=.5", b"application/octet-stream;Q=0.7, application/json;q=0.6",
          b"application/json; charset=utf-8; q=0.4, application/octet-stream; q=0.5", b", ,application/octet-stream",
          b"application/octet-stream;q=1.000", b"application/octet-stream;q=1.001,application/json;q=0.001",
          b"application/octet-stream;q=0.,application/json;q=0.", b"text/*, application/*;q=0.8",
          b"application/json;q=0.5,application/json;q=0.6,application/octet-stream;q=0.55"]
CONTENT = [b"application/json", b"application/octet-stream", b"Application/OCTET-STREAM; charset=binary",
           b" application/json ;x=y", b"text/plain", b"application/ssz", b";", b"application/json2"]


class Cases:
    def __init__(self, ops):
        self.ops, self.names = ops, set()

    def case(self, name, req):
        assert name not in self.names, name
        self.names.add(name)
        status, out = route(self.ops, req, 1 << 24)
        parts = dict(req)
        if status == OK:
            parts["out"] = struct.pack("<Q", len(out)) + out[8:]
        parts["status"] = status
        if status == INVALID_ROUTE:
            parts.update({"http_status": out.http, "fault": out.fault, "allow": out.allow, "op": out.op})
        return name, parts


def request(method, path, query=b"", accept=b"", content_type=b"", version=b"", body=b""):
    return {"method": method, "path": path, "query": query, "accept": accept, "content_type": content_type,
            "consensus_version": version, "body": body}


def fill(op, values=None):
    """The op's path with each path parameter's first good value, or values[name]."""
    path = op["path"].encode()
    for name in PARAMS:
        key = b"{" + name.encode() + b"}"
        if key in path:
            path = path.replace(key, (values or {}).get(name, GOOD[name][0]))
    return path


def base(op, query_items=(), **headers):
    """A request of op with every required query parameter."""
    items = [(PARAMS[i - 1], GOOD[PARAMS[i - 1]][0]) for i in range(1, len(PARAMS) + 1) if op["required"] >> i & 1]
    items += list(query_items)
    query = b"&".join(n.encode() + b"=" + v for n, v in items)
    if op["flags"] & F_VERSION and "version" not in headers:
        headers["version"] = b"fulu"
    return request(op["method"], fill(op, headers.pop("path_values", None)), query, **headers)


IDS_100 = b"[" + b",".join(b'"%d"' % i for i in range(100)) + b"]"
ID_BODIES_ARRAY = [b"", b"[]", b" [ ] ", b'["1"]', b'["0","18446744073709551615"]', b'[ "5" ,\n\t"' + PUBKEY + b'"\r\n]',
                   b'["' + PUBKEY.upper().replace(b"0X", b"0x") + b'","7","7"]', IDS_100, b"null"]
ID_BODIES_OBJECT = [b"{}", b' { } ', b'{"ids":null,"statuses":null}', b'{"ids":[],"statuses":[]}', b'{"ids":["1","2"]}',
                    b'{"statuses":["active","withdrawal_done"]}', b'{"statuses":["pending_queued"],"ids":["' + PUBKEY + b'"]}',
                    b'{ "ids" : [ "3" ] , "statuses" : [ "exited" , "pending" ] }', b'{"ids":' + IDS_100 + b"}",
                    b'{"\\u0069ds":["\\u0031\\u0032","0\\u0078' + PUBKEY[2:] + b'"],"st\\u0061tuses":["active"]}',
                    b'{"ids":["\\u00311"]}', b'{"statuses":["\\u0061ctive"]}']
BAD_BODIES = [b'{"ids":["1"', b'{"ids":["1",]}', b'{"ids":[1]}', b'{"ids":["x"]}', b'{"ids":[""]}', b'{"ids":["0x12"]}',
              b'{"ids":["18446744073709551616"]}', b'{"ids":["1"]}x', b'{"ids":["1"]} {}', b'{"ids":["\\u0031"]}',
              b'{"ids":["1\t"]}', b'{"ids":["1"],"ids":["2"]}', b'{"other":[]}', b'{"ids":"1"}', b'{"ids":[["1"]]}',
              b'{"ids":nul}', b'{"statuses":["bogus"]}', b'{"statuses":["Active"]}', b'{"ids":["1"],}', b'{"ids":["1"];',
              b' ', b'[', b'"1"', b'{"ids":["x"],"statuses":["bogus"]}', b'{"statuses":["bogus"],"ids":["x"]}',
              b'{"ids":["\\x"]}', b'{"ids":["\\u12G4"]}', b'{"ids":["\\u003"]}', b'{"ids":["\\u00e9"]}', b'{"ids":["1\\n"]}',
              b'{"ids":["\\\\"]}', b'{"ids":["\\"]}', b'{"\\u0069d":["1"]}', b'{"ids":["' + b"1" * 201 + b'"]}',
              b'{"ids":["\\/1"]}']


def cases():
    spec = pathlib.Path(os.environ["BEACON_APIS"])
    ops = operations(spec)
    c = Cases(ops)
    for op in ops:
        name = op["name"]
        yield c.case(name, base(op))
        other = POST if op["method"] == GET else GET
        yield c.case(f"{name}_method_{other}", dict(base(op), method=other))
        yield c.case(f"{name}_method_other", dict(base(op), method=OTHER))
        for pname in PARAMS:
            if b"{" + pname.encode() + b"}" not in op["path"].encode():
                continue
            for k, v in enumerate(GOOD[pname]):
                yield c.case(f"{name}_{pname}_good_{k}", base(op, path_values={pname: v}))
            for k, v in enumerate(BAD[pname]):
                yield c.case(f"{name}_{pname}_bad_{k}", base(op, path_values={pname: v}))
        for i in range(1, len(PARAMS)):
            if not op["query"] >> i & 1:
                continue
            pname = PARAMS[i - 1]
            required = op["required"] >> i & 1
            for k, v in enumerate(GOOD[pname]):
                b = base(op)
                q = b"&".join([x for x in b["query"].split(b"&") if x and not x.startswith(pname.encode() + b"=")] +
                              [pname.encode() + b"=" + v])
                yield c.case(f"{name}_{pname}_good_{k}", dict(b, query=q))
            for k, v in enumerate(BAD[pname]):
                b = base(op)
                q = b"&".join([x for x in b["query"].split(b"&") if x and not x.startswith(pname.encode() + b"=")] +
                              [pname.encode() + b"=" + v])
                yield c.case(f"{name}_{pname}_bad_{k}", dict(b, query=q))
            b = base(op)
            twice = pname.encode() + b"=" + GOOD[pname][-1]
            yield c.case(f"{name}_{pname}_twice", dict(b, query=b["query"] + b"&" + twice + b"&" + twice if b["query"] else twice + b"&" + twice))
            if required:
                q = b"&".join(x for x in b["query"].split(b"&") if not x.startswith(pname.encode() + b"="))
                yield c.case(f"{name}_{pname}_missing", dict(b, query=q))
            yield c.case(f"{name}_{pname}_no_equals", dict(b, query=(b["query"] + b"&" if b["query"] else b"") + pname.encode()))
        yield c.case(f"{name}_query_noise", dict(base(op), query=b"&&foo=bar&" + base(op)["query"] + b"&state_id=x&=&%66oo=1&"))
        yield c.case(f"{name}_query_broken", dict(base(op), query=base(op)["query"] + b"&x=%4"))
        if op["flags"] & F_VERSION:
            for fork in FORKS:
                yield c.case(f"{name}_version_{fork}", base(op, version=fork.encode()))
            for k, v in enumerate([b"Fulu", b"gloas", b"fulu ", b"phase0,fulu"]):
                yield c.case(f"{name}_version_bad_{k}", base(op, version=v))
            yield c.case(f"{name}_version_missing", dict(base(op), consensus_version=b""))
        for k, v in enumerate(CONTENT):
            if op["method"] == POST:
                yield c.case(f"{name}_content_{k}", base(op, content_type=v))
        for k, v in enumerate(ACCEPT):
            if op["flags"] & F_SSZ_RESPONSE or k < 3:
                yield c.case(f"{name}_accept_{k}", base(op, accept=v))
        if op["flags"] & F_ID_MAX:
            ids = [str(i).encode() for i in range(64)]
            yield c.case(f"{name}_ids_64", base(op, [("id", b",".join(ids))]))
            yield c.case(f"{name}_ids_65", base(op, [("id", b",".join(ids + [b"64"]))]))
            yield c.case(f"{name}_ids_65_split", base(op, [("id", b",".join(ids[:40])), ("id", b",".join(ids[40:] + [b"x"]))]))
            yield c.case(f"{name}_ids_encoded", base(op, [("id", b"1%2C2%2c" + PUBKEY)]))
            yield c.case(f"{name}_ids_and_bad_status", base(op, [("id", b"1"), ("status", b"bogus")]))
        if op["flags"] & (F_IDS_OBJECT | F_IDS_ARRAY):
            obj = op["flags"] & F_IDS_OBJECT
            for k, v in enumerate(ID_BODIES_OBJECT if obj else ID_BODIES_ARRAY):
                yield c.case(f"{name}_body_{k}", dict(base(op), body=v))
            for k, v in enumerate(BAD_BODIES):
                yield c.case(f"{name}_body_bad_{k}", dict(base(op), body=v if obj else v.replace(b'{"ids":', b"")))
    health = [o for o in ops if o["name"] == "getHealth"][0]
    for k, path in enumerate([b"/", b"/eth", b"/eth/v1/node/health/", b"/eth/v1/node", b"/eth/v1/node/health/x",
                              b"/eth//v1/node/health", b"/eth/v1/node/healt", b"/eth/v1/node/healthz", b"/ETH/v1/node/health",
                              b"/eth/v1/beacon/headers/", b"/eth/v1/beacon/states//root", b"/eth/v9/beacon/genesis",
                              b"/eth/v1/node/%68ealth", b"/eth/v1/node/health%", b"/eth/v1/node/health%2",
                              b"/eth/v1/node/health%zz", b"/eth/v1/node/health%2F", b"/eth/v1/node%2Fhealth",
                              b"/eth/v1/beacon/headers/he%2Fad", b"/eth/v1/beacon/headers/%68%65%61%64",
                              b"/eth/v1/beacon/headers/%30x" + ROOT[2:], b"/eth/v1/beacon/headers/0%78" + ROOT[2:],
                              b"/%", b"/eth/v1/beacon/states/head/validators/%"]):
        yield c.case(f"path_{k}", request(GET, path))
    yield c.case("health_post", request(POST, b"/eth/v1/node/health"))
    yield c.case("health_query_plus", dict(base(health), query=b"syncing_status=2+99"))
    yield c.case("health_query_encoded", dict(base(health), query=b"syncing%5Fstatus=%32%39%39"))
    yield c.case("validators_both_methods", request(OTHER, b"/eth/v1/beacon/states/head/validators"))
    yield c.case("validators_status_groups", request(GET, b"/eth/v1/beacon/states/head/validators",
                                                     b"status=pending&status=exited&status=withdrawal&status=active"))
