"""Cases of lantern_json_encode (docs/reference/beacon-api.md), made with the pinned spec.

The values come from get_random_ssz_object of the pinned spec's test helpers, for every container
type of the fork's spec module: in minimal the modes zero, one, random and max, lists of at most 4
items and byte lists of at most 64 bytes; in mainnet the mode zero only, as its states are large.
The JSON is written here by the rules of lantern_json_encode, apart from the assembly: a uint as a
decimal string, Boolean as true or false, byte and bit strings as 0x and lower case hex (a bit list
with its delimiter bit), lists and vectors as arrays, containers as objects of the spec's field
names in order, no white space.

cases(fork, preset) yields (name, parts): "type", the container's name; "ssz", the value's SSZ
bytes; "json", its JSON.
"""

from random import Random

from ssz.bitfields import BitList, BitVector
from ssz.boolean import Boolean
from ssz.byte_arrays import ByteList, ByteVector
from ssz.collections import List, Vector
from ssz.container import Container
from ssz.uint import BaseUint

from eth_consensus_specs.debug.random_value import RandomizationMode, get_random_ssz_object
from p2p import module

MODES = {"minimal": ("zero", "one_count", "random", "max"), "mainnet": ("zero",)}


def to_json(value):
    if isinstance(value, Boolean):
        return "true" if value else "false"
    if isinstance(value, BaseUint):
        return '"%d"' % int(value)
    if isinstance(value, (BitList, BitVector)):
        return '"0x' + bytes(value.encode_bytes()).hex() + '"'
    if isinstance(value, (ByteList, ByteVector)):
        return '"0x' + bytes(value).hex() + '"'
    if isinstance(value, (List, Vector)):
        return "[" + ",".join(to_json(item) for item in value) + "]"
    if isinstance(value, Container):
        return "{" + ",".join('"%s":%s' % (name, to_json(getattr(value, name))) for name in type(value).model_fields) + "}"
    raise TypeError(type(value))


def containers(spec):
    for name in sorted(dir(spec)):
        t = getattr(spec, name)
        if isinstance(t, type) and issubclass(t, Container) and t is not Container and t.__name__ == name:
            yield name, t


def cases(fork, preset):
    spec = module(fork, preset)
    for name, t in containers(spec):
        for mode in MODES[preset]:
            rng = Random(f"{fork}-{name}-{mode}")
            try:
                value = get_random_ssz_object(rng, t, 64, 4, getattr(RandomizationMode, "mode_" + mode), False)
                text = to_json(value)
            except TypeError:
                break  # a kind outside phase0 to fulu, such as a progressive type: no case
            yield f"{name}_{mode}", {"type": name.encode(), "ssz": bytes(value.encode_bytes()), "json": text.encode()}


# ---------------------------------------------------------------- lantern_json_decode

SYNTAX, TYPE, NUMBER, HEX, LENGTH, FIELD, MISSING = 1, 2, 3, 4, 5, 6, 7
WS = b" \t\n\r"
DIGITS = b"0123456789"
HEXDIGITS = b"0123456789abcdefABCDEF"


class Fault(Exception):
    def __init__(self, kind, offset, path):
        self.kind, self.offset, self.path = kind, offset, list(path)


def camel(name):
    """A field's Engine API name: each _ and the letter after it as that letter in upper case."""
    parts = name.split("_")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


class Decoder:
    """The rules of lantern_json_decode, written apart from the assembly; with engine, those of
    lantern_engine_json_decode (docs/reference/engine-api.md)."""

    def __init__(self, text, engine=False):
        self.t = text
        self.n = len(text)
        self.engine = engine

    def ws(self, i):
        while i < self.n and self.t[i] in WS:
            i += 1
        return i

    def at(self, i, path):
        """The byte at i, or SYNTAX at the end when the text ended."""
        if i >= self.n:
            raise Fault(SYNTAX, self.n, path)
        return self.t[i]

    def string(self, i, path):
        """(content, end) of the string at i."""
        j = i + 1
        while True:
            c = self.at(j, path)
            if c == 0x22:
                return self.t[i + 1:j], j + 1
            if c == 0x5C or c < 0x20:
                raise Fault(SYNTAX, j, path)
            j += 1

    def number(self, i, path):
        j = i
        if self.at(j, path) == 0x2D:
            j += 1
        c = self.at(j, path)
        if c == 0x30:
            j += 1
        elif c in b"123456789":
            while j < self.n and self.t[j] in DIGITS:
                j += 1
        else:
            raise Fault(SYNTAX, j, path)
        if j < self.n and self.t[j] == 0x2E:
            j += 1
            if self.at(j, path) not in DIGITS:
                raise Fault(SYNTAX, j, path)
            while j < self.n and self.t[j] in DIGITS:
                j += 1
        if j < self.n and self.t[j] in b"eE":
            j += 1
            if self.at(j, path) in b"+-":
                j += 1
            if self.at(j, path) not in DIGITS:
                raise Fault(SYNTAX, j, path)
            while j < self.n and self.t[j] in DIGITS:
                j += 1
        return j

    def skip(self, i, path):
        """The end of the value at i, with only the checks of the text."""
        stack = []
        while True:
            i = self.ws(i)
            c = self.at(i, path)
            if c == 0x22:
                _, i = self.string(i, path)
            elif c == 0x2D or c in DIGITS:
                i = self.number(i, path)
            elif self.t.startswith(b"true", i):
                i += 4
            elif self.t.startswith(b"false", i):
                i += 5
            elif self.t.startswith(b"null", i):
                i += 4
            elif c in (0x5B, 0x7B):
                if len(stack) == 64:
                    raise Fault(SYNTAX, i, path)
                stack.append(c)
                i = self.ws(i + 1)
                close = 0x5D if c == 0x5B else 0x7D
                if self.at(i, path) == close:
                    stack.pop()
                    i += 1
                elif c == 0x7B:
                    i = self.key(i, path)
                    continue
                else:
                    continue
            else:
                raise Fault(SYNTAX, i, path)
            while True:  # after a value
                if not stack:
                    return i
                i = self.ws(i)
                c = self.at(i, path)
                top = stack[-1]
                if c == 0x2C:
                    i += 1
                    if top == 0x7B:
                        i = self.key(self.ws(i), path)
                    break
                if c == (0x5D if top == 0x5B else 0x7D):
                    stack.pop()
                    i += 1
                    continue
                raise Fault(SYNTAX, i, path)

    def key(self, i, path):
        """The end of '"name":' at i, before the value."""
        if self.at(i, path) != 0x22:
            raise Fault(SYNTAX, i, path)
        _, i = self.string(i, path)
        i = self.ws(i)
        if self.at(i, path) != 0x3A:
            raise Fault(SYNTAX, i, path)
        return i + 1

    def decode(self, typ, i, path):
        """(the SSZ bytes, the end) of a value of typ at i."""
        i = self.ws(i)
        c = self.at(i, path)
        if issubclass(typ, Container):
            if c != 0x7B:
                raise Fault(TYPE, i, path)
            names = list(typ.model_fields)
            keys = [camel(n) for n in names] if self.engine else names
            seen = {}
            j = self.ws(i + 1)
            if self.at(j, path) == 0x7D:
                end = j + 1
            else:
                while True:
                    if self.at(j, path) != 0x22:
                        raise Fault(SYNTAX, j, path)
                    name, k = self.string(j, path)
                    key = name.decode("latin-1")
                    if self.engine and key not in keys:  # another member: its value skipped
                        k = self.ws(k)
                        if self.at(k, path) != 0x3A:
                            raise Fault(SYNTAX, k, path)
                        j = self.ws(self.skip(self.ws(k + 1), path + [len(names)]))
                    else:
                        if key not in keys or names[keys.index(key)] in seen:
                            raise Fault(FIELD, j, path)
                        key = names[keys.index(key)]
                        k = self.ws(k)
                        if self.at(k, path) != 0x3A:
                            raise Fault(SYNTAX, k, path)
                        vstart = self.ws(k + 1)
                        seen[key] = vstart
                        j = self.ws(self.skip(vstart, path + [names.index(key)]))
                    c = self.at(j, path)
                    if c == 0x2C:
                        j = self.ws(j + 1)
                        continue
                    if c == 0x7D:
                        end = j + 1
                        break
                    raise Fault(SYNTAX, j, path)
            for name in names:
                if name not in seen:
                    raise Fault(MISSING, end - 1, path)
            fixed, var = [], []
            for k, name in enumerate(names):
                ftype = typ.model_fields[name].annotation
                enc, _ = self.decode(ftype, seen[name], path + [k])
                if ftype.is_fixed_size():
                    fixed.append(enc)
                else:
                    fixed.append(None)
                    var.append(enc)
            return assemble(fixed, var), end
        if issubclass(typ, (List, Vector)) and not issubclass(typ, (ByteList, ByteVector, BitList, BitVector)):
            if c != 0x5B:
                raise Fault(TYPE, i, path)
            starts = []
            j = self.ws(i + 1)
            if self.at(j, path) == 0x5D:
                end = j + 1
            else:
                while True:
                    starts.append(j)
                    j = self.ws(self.skip(j, path + [len(starts) - 1]))
                    c = self.at(j, path)
                    if c == 0x2C:
                        j = self.ws(j + 1)
                        continue
                    if c == 0x5D:
                        end = j + 1
                        break
                    raise Fault(SYNTAX, j, path)
            limit = typ.LENGTH if issubclass(typ, Vector) else typ.LIMIT
            if (issubclass(typ, Vector) and len(starts) != limit) or len(starts) > limit:
                raise Fault(LENGTH, i, path)
            etype = typ.ELEMENT_TYPE
            encs = [self.decode(etype, s, path + [k])[0] for k, s in enumerate(starts)]
            if etype.is_fixed_size():
                return b"".join(encs), end
            return assemble([None] * len(encs), encs), end
        if issubclass(typ, Boolean):
            if self.t.startswith(b"true", i):
                return b"\x01", i + 4
            if self.t.startswith(b"false", i):
                return b"\x00", i + 5
            raise Fault(TYPE, i, path)
        if c != 0x22:
            raise Fault(TYPE, i, path)
        content, end = self.string(i, path)
        if issubclass(typ, BaseUint) and self.engine:  # a QUANTITY
            w = typ.BYTE_LENGTH
            ok = len(content) >= 3 and content[:2] == b"0x" and all(ch in HEXDIGITS for ch in content[2:])
            ok = ok and (content[2:] == b"0" or content[2:3] != b"0")
            if not ok or int(content[2:], 16) >= 1 << (8 * w):
                raise Fault(NUMBER, i, path)
            return int(content[2:], 16).to_bytes(w, "little"), end
        if issubclass(typ, BaseUint):
            w = typ.BYTE_LENGTH
            if not 1 <= len(content) <= 78 or any(ch not in DIGITS for ch in content) or int(content) >= 1 << (8 * w):
                raise Fault(NUMBER, i, path)
            return int(content).to_bytes(w, "little"), end
        if len(content) < 2 or content[:2] != b"0x" or len(content) % 2 or any(ch not in HEXDIGITS for ch in content[2:]):
            raise Fault(HEX, i, path)
        raw = bytes.fromhex(content[2:].decode())
        if issubclass(typ, ByteVector):
            ok = len(raw) == typ.LENGTH
        elif issubclass(typ, ByteList):
            ok = len(raw) <= typ.LIMIT
        elif issubclass(typ, BitVector):
            nbits = typ.LENGTH
            ok = len(raw) == (nbits + 7) // 8 and (nbits % 8 == 0 or raw[-1] >> (nbits % 8) == 0)
        else:  # BitList
            ok = len(raw) >= 1 and raw[-1] != 0 and 8 * (len(raw) - 1) + raw[-1].bit_length() - 1 <= typ.LIMIT
        if not ok:
            raise Fault(HEX, i, path)
        return raw, end

    def root(self, typ):
        enc, end = self.decode(typ, 0, [])
        end = self.ws(end)
        if end != self.n:
            raise Fault(SYNTAX, end, [])
        return enc


def assemble(fixed, var):
    """SSZ of a container or list: the fixed part with a 4-byte offset for each variable item, then those."""
    size = sum(4 if f is None else len(f) for f in fixed)
    out, tail = b"", b""
    vi = 0
    for f in fixed:
        if f is None:
            out += (size + len(tail)).to_bytes(4, "little")
            tail += var[vi]
            vi += 1
        else:
            out += f
    return out + tail


def spaced(text):
    """The JSON with white space after each structural byte outside strings."""
    out, in_string = bytearray(), False
    for ch in text:
        out.append(ch)
        if ch == 0x22:
            in_string = not in_string
        elif not in_string and ch in b"{}[],:":
            out += b" \n\t\r "
    return b" " + bytes(out) + b"\n"


def reversed_fields(text):
    import json as pyjson

    def walk(v):
        if isinstance(v, dict):
            return {k: walk(v[k]) for k in reversed(list(v))}
        if isinstance(v, list):
            return [walk(x) for x in v]
        return v
    return pyjson.dumps(walk(pyjson.loads(text)), separators=(",", ":")).encode()


MUTATED = ("Checkpoint", "AttestationData", "Attestation", "Validator", "SyncCommittee", "SyncAggregate",
           "BeaconBlockBody", "ExecutionPayload", "SignedVoluntaryExit", "IndexedAttestation")


def mutations(text):
    """(name, text) of texts that break one rule each, where the text has what they change."""
    import re as pyre
    out = [("truncated", text[:len(text) // 2]), ("trailing", text + b" x"), ("no_comma", text.replace(b",", b"", 1)),
           ("escape", text.replace(b'":"', b'":"\\', 1)), ("array_root", b"[]"), ("empty", b""), ("ws_only", b" \n"),
           ("unknown_field", text.replace(b"{", b'{"bogus":"1",', 1)), ("number_root", b"12"),
           ("deep", text.replace(b":", b":" + b"[" * 70, 1))]
    m = pyre.search(rb'"([a-z_]+)":("[^"]*"|\{|\[|true|false)', text)
    if m:
        member = text[m.start():]
        depth, j = 0, m.end(1) + 2
        for j in range(m.end(1) + 2, len(text)):
            ch = text[j]
            if ch in b"{[":
                depth += 1
            elif ch in b"}]":
                depth -= 1
            if depth == 0 and (ch in b",}" if text[m.end(1) + 2] not in b"{[" else ch in b"}]"):
                break
        whole = text[m.start():j + (1 if text[m.end(1) + 2] in b"{[" else 0)]
        out.append(("missing", text.replace(whole + b",", b"", 1) if whole + b"," in text else text.replace(b"," + whole, b"", 1)))
        out.append(("duplicate", text.replace(whole, whole + b"," + whole, 1)))
    m = pyre.search(rb'":"([0-9]+)"', text)
    if m:
        s, e = m.span(1)
        for name, new in (("uint_number", None), ("uint_overflow", b"18446744073709551616" + b"0" * 60), ("uint_negative", b"-1"),
                          ("uint_empty", b""), ("uint_hex", b"0x10"), ("uint_long", b"1" * 79), ("uint_space", b"1 ")):
            out.append((name, text[:s - 1] + text[s:e] + text[e + 1:] if new is None else text[:s] + new + text[e:]))
    m = pyre.search(rb'"0x([0-9a-f]+)"', text)
    if m:
        s, e = m.span(1)
        out += [("hex_odd", text[:s] + text[s + 1:]), ("hex_char", text[:s] + b"g" + text[s + 1:]),
                ("hex_upper_x", text[:s - 1] + b"X" + text[s:]), ("hex_upper", text[:s] + text[s:e].upper() + text[e:]),
                ("hex_short", text[:s] + text[s + 2:]), ("hex_long", text[:s] + b"00" + text[s:]), ("hex_bare", text[:s - 2] + text[s:])]
    for name, old, new in (("bool_number", b":true", b":1"), ("bool_string", b":false", b':"false"'),
                           ("bitlist_zero", b'"aggregation_bits":"0x', b'"aggregation_bits":"0x00'),
                           ("object_for_uint", b'"slot":"', b'"slot":{},"x":"')):
        if old in text:
            out.append((name, text.replace(old, new, 1)))
    if b"[" in text:
        i = text.index(b"[")
        if text[i + 1:i + 2] != b"]":
            out.append(("array_item_more", text[:i + 1] + text[i + 1:].split(b"]", 1)[0].split(b",")[0] + b"," + text[i + 1:]))
        out.append(("array_for_object", text[:i] + b"{}" + text[text.index(b"]", i) + 1:] if b"]" in text[i:] else text))
    m = pyre.search(rb'\[(\{[^\[\]]*?\}|"[^"]*")[,\]]', text)
    if m:  # 70 more copies of an array's first item: past the limit of a short list
        item = m.group(1)
        out.append(("array_over", text[:m.start(1)] + (item + b",") * 70 + text[m.start(1):]))
    return out


def decode_cases(fork, preset, encode_cases):
    """(name, parts) of lantern_json_decode: valid texts with their SSZ bytes, then texts with their faults."""
    spec = module(fork, preset)
    for name, parts in encode_cases:
        t = getattr(spec, parts["type"].decode())
        for variant, text in (("", parts["json"]), ("_spaced", spaced(parts["json"])), ("_reversed", reversed_fields(parts["json"]))):
            enc = Decoder(text).root(t)
            assert enc == parts["ssz"], (name, variant)
            yield name + variant, {"type": parts["type"], "json": text, "ssz": enc}
    done = set()
    for name, parts in encode_cases:
        tname = parts["type"].decode()
        if tname not in MUTATED or tname in done or not name.endswith("_random"):
            continue
        done.add(tname)
        t = getattr(spec, tname)
        for mname, text in mutations(parts["json"]):
            try:
                enc = Decoder(text).root(t)
                yield f"{tname}_{mname}_valid", {"type": parts["type"], "json": text, "ssz": enc}
            except Fault as f:
                yield f"{tname}_{mname}", {"type": parts["type"], "json": text, "fault_kind": f.kind, "fault_offset": f.offset,
                                          "fault_path": [int(p) for p in f.path]}


# ---------------------------------------------------------------- lantern_engine_json_decode


def to_engine_json(value):
    """The Engine API's JSON (execution-apis common.md): QUANTITY, DATA, camelCase names."""
    if isinstance(value, Boolean):
        return "true" if value else "false"
    if isinstance(value, BaseUint):
        return '"0x%x"' % int(value)
    if isinstance(value, (ByteList, ByteVector)):
        return '"0x' + bytes(value).hex() + '"'
    if isinstance(value, (List, Vector)):
        return "[" + ",".join(to_engine_json(item) for item in value) + "]"
    if isinstance(value, Container):
        return "{" + ",".join('"%s":%s' % (camel(n), to_engine_json(getattr(value, n))) for n in type(value).model_fields) + "}"
    raise TypeError(type(value))


def engine_mutations(text):
    """(name, text): the texts of the Engine API that break one rule each, or that it takes."""
    import re as pyre
    out = [("unknown_member", text.replace(b"{", b'{"validationError":null,"x":{"a":[1,"b"]},', 1)),
           ("unknown_member_bad", text.replace(b"{", b'{"x":[1,},', 1)),
           ("upper_hex", pyre.sub(rb'"0x([0-9a-f]+)"', lambda m: b'"0x' + m.group(1).upper() + b'"', text))]
    m = pyre.search(rb'"([a-zA-Z]+)":"0x([0-9a-f]+)"', text)
    if m:
        s, e = m.span(2)
        out += [("leading_zero", text[:s] + b"0" + text[s:]), ("no_digit", text[:s] + text[e:]),
                ("decimal", text[:s - 2] + b"12" + text[e:]), ("odd", text[:s] + text[s + 1:] if e - s > 1 else text)]
    m = pyre.search(rb'"(gasLimit|timestamp|blockNumber)":"0x([0-9a-f]+)"', text)
    if m:
        s, e = m.span(2)
        out += [("past_width", text[:s] + b"1" + b"0" * 16 + text[e:]), ("zero_alone", text[:s] + b"0" + text[e:])]
    m = pyre.search(rb'"(parentHash|stateRoot)":"0x([0-9a-f]+)"', text)
    if m:
        s, e = m.span(2)
        out += [("data_odd", text[:s] + text[s + 1:]), ("data_short", text[:s] + text[s + 2:])]
        whole = text[m.start():e + 1]
        out += [("missing", text.replace(whole + b",", b"", 1)), ("duplicate", text.replace(whole, whole + b"," + whole, 1))]
    return out


def engine_decode_cases(fork, preset):
    """(name, parts) of lantern_engine_json_decode, from bellatrix: the result of engine_getPayload of
    the fork (its ExecutionPayload in bellatrix, else lantern's GetPayloadResult), random values in
    the modes zero, one_count and random with lists of at most 3 items, as JSON and with the changes
    of engine_mutations."""
    import reqresp
    spec = module(fork, preset)
    if fork in ("phase0", "altair"):
        return
    types = reqresp.engine_result_types(spec, fork)
    tname = "GetPayloadResult" if "GetPayloadResult" in types else "ExecutionPayload"
    t = types.get(tname) or spec.ExecutionPayload
    for mode in ("zero", "one_count", "random"):
        rng = Random(f"engine-{fork}-{mode}")
        value = get_random_ssz_object(rng, t, 64, 3, getattr(RandomizationMode, "mode_" + mode), False)
        text = to_engine_json(value).encode()
        ssz = bytes(value.encode_bytes())
        for variant, v in (("", text), ("_spaced", spaced(text)), ("_reversed", reversed_fields(text))):
            enc = Decoder(v, engine=True).root(t)
            assert enc == ssz, (mode, variant)
            yield f"{tname}_{mode}{variant}", {"type": tname.encode(), "json": v, "ssz": enc}
        if mode != "random":
            continue
        for mname, v in engine_mutations(text):
            try:
                enc = Decoder(v, engine=True).root(t)
                yield f"{tname}_{mname}_valid", {"type": tname.encode(), "json": v, "ssz": enc}
            except Fault as f:
                yield f"{tname}_{mname}", {"type": tname.encode(), "json": v, "fault_kind": f.kind, "fault_offset": f.offset,
                                          "fault_path": [int(p) for p in f.path]}
