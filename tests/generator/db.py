"""Cases of lantern's database index (docs/reference/db.md).

No outside specification defines the record format or the index: these cases follow the rules
of docs/reference/db.md, written out here as a model of the index. The records are made up:
roots and bytes from SHA-256 of a counter, so every run gives the same cases.

cases() yields (name, parts):
- room: [slots, roots]; first_slot.
- segments: in scan order, each {number, kind, bytes, status, valid}: lantern_db_scan of the bytes
  as a segment of the kind (0 blocks, 1 sidecars, 2 states) must give the status (0, or 1 for
  LANTERN_BUFFER_TOO_SMALL) and valid.
- end_slot, blocks, entries: the Db after the scans; entries the DbSlot bytes from first_slot
  below end_slot.
- find: [root, slot] pairs, 2^64 - 1 for none.
- copy_room: a larger room; lantern_db_copy to it must keep end_slot, blocks, entries and find.
- prune, pruned_first, pruned_entries, pruned_find: lantern_db_prune to prune, then the Db.

diff_cases() yields (name, parts), the cases of the state diffs (docs/reference/db.md, State diffs):
- base, state, diff: lantern_db_state_diff of base and state must give diff, and
  lantern_db_state_patch of base and diff must give state.
- base, bad: lantern_db_state_patch of base and bad must give LANTERN_INVALID_ENCODING.
"""

import hashlib
import struct

SEG = 8192  # DB_SEGMENT_SLOTS
U64 = (1 << 64) - 1
BLOCK, BLOB, COLUMN, STATE, DIFF = 1, 2, 3, 4, 5
KINDS = {0: (BLOCK,), 1: (BLOB, COLUMN), 2: (STATE, DIFF)}  # the record kinds of each kind of segment
RECORD_MAX = 1 << 32
OFFSET_MAX = 1 << 44  # DB_OFFSET_MAX
INDICES = 128  # DB_SIDECAR_INDICES
OK, SMALL, INVALID = 0, 1, 2


def made(*parts):
    """32 bytes of SHA-256 of the parts."""
    return hashlib.sha256(repr(parts).encode()).digest()


def record(kind, slot, index, root, data, length=None, header=None):
    """A record: the DbRecord header (its ByteList header of size 24 + length and offset 24), the bytes, zero bytes up to a multiple of 8."""
    n = len(data) if length is None else length
    size, offset = header or (24 + n, 24)
    return struct.pack("<QQQ", kind, slot, index) + root + struct.pack("<QQQ", size, offset, n) + data + b"\0" * (-len(data) % 8)


class Model:
    """The index of docs/reference/db.md."""

    def __init__(self, room, first):
        self.cap, self.rcap = room
        self.first = self.end = first
        self.entries = {}  # entry index: [root, block, sidecars, count, end, last, indices, state]
        self.roots = {}  # root: entry index

    def add(self, kind, slot, index, root, length, offset, header):
        if offset % 8 or offset >= OFFSET_MAX or length > RECORD_MAX or header != (24 + length, 24) or slot < self.first:
            return INVALID
        i = slot - self.first
        if i >= self.cap:
            return SMALL
        e = self.entries.get(i)
        size = 80 + length + (-length % 8)
        if kind == BLOCK:
            if (e and e[1]) or root in self.roots:
                return INVALID
            if (len(self.roots) + 1) * 2 > self.rcap:
                return SMALL
            self.entries[i] = [root, offset + 1, 0, 0, 0, 0, 0, 0]
            self.roots[root] = i
            self.end = max(self.end, slot + 1)
            return OK
        if kind in (STATE, DIFF):
            if index or not e or not e[1] or e[0] != root or e[7] or (kind == STATE) != (offset == 0):
                return INVALID
            e[7] = offset + 1
            return OK
        if kind not in (BLOB, COLUMN) or not e or not e[1] or index >= INDICES:
            return INVALID
        if e[2]:
            if e[4] != offset or index <= e[5] or size * e[3] != e[4] - (e[2] - 1):
                return INVALID
        else:
            e[2] = offset + 1
        e[3] += 1
        e[4] = offset + size
        e[5] = index
        e[6] |= 1 << index
        return OK

    def scan(self, number, seg_kind, data):
        pos, base = 0, number * SEG
        while len(data) - pos >= 80:
            kind, slot, index = struct.unpack_from("<QQQ", data, pos)
            root = data[pos + 24:pos + 56]
            hsize, hoffset, length = struct.unpack_from("<QQQ", data, pos + 56)
            if length > RECORD_MAX:
                break
            size = 80 + length + (-length % 8)
            if size > len(data) - pos or slot < base or slot - base >= SEG or kind not in KINDS[seg_kind]:
                break
            r = self.add(kind, slot, index, root, length, pos, (hsize, hoffset))
            if r == SMALL:
                return SMALL, pos
            if r == INVALID:
                break
            pos += size
        return OK, pos

    def entry_bytes(self):
        out = bytearray()
        for i in range(self.end - self.first):
            e = self.entries.get(i)
            out += e[0] + struct.pack("<QQQQQ", *e[1:6]) + e[6].to_bytes(16, "little") + struct.pack("<Q", e[7]) if e else bytes(96)
        return bytes(out)

    def find(self, root):
        i = self.roots.get(root)
        return U64 if i is None else self.first + i

    def prune(self, slot):
        if slot <= self.first:
            return
        slot = min(slot, self.end)
        k = slot - self.first
        self.entries = {i - k: e for i, e in self.entries.items() if i >= k}
        self.roots = {e[0]: i for i, e in self.entries.items() if e[1]}
        self.first = slot


class Case:
    """Segments of made up records, scanned through a Model as they are added."""

    def __init__(self, name, room, first):
        self.name, self.room, self.model = name, list(room), Model(room, first)
        self.first = first
        self.segments = []
        self.counter = 0

    def bytes_of(self, n):
        self.counter += 1
        out = b""
        while len(out) < n:
            out += made(self.name, self.counter, len(out))
        return out[:n]

    def block(self, slot):
        root = made(self.name, "block", slot)
        return record(BLOCK, slot, 0, root, self.bytes_of(40 + slot % 61)), root

    def sidecar(self, kind, slot, index):
        return record(kind, slot, index, made(self.name, "block", slot), self.bytes_of(8 + slot * 7 % 53))

    def state(self, kind, slot):
        return record(kind, slot, 0, made(self.name, "block", slot), self.bytes_of(16 + slot * 5 % 47))

    def segment(self, number, seg_kind, data):
        status, valid = self.model.scan(number, seg_kind, data)
        self.segments.append({"number": number, "kind": seg_kind, "bytes": data, "status": status, "valid": valid})

    def parts(self, extra_roots=(), copy_room=None, prune=None):
        m = self.model
        roots = list(m.roots) + list(extra_roots)
        p = {
            "room": self.room, "first_slot": self.first, "segments": self.segments,
            "end_slot": m.end, "blocks": len(m.roots), "entries": m.entry_bytes(),
            "find": [[r, m.find(r)] for r in roots],
        }
        if copy_room:
            p["copy_room"] = list(copy_room)
        if prune is not None:
            m.prune(prune)
            p.update({"prune": prune, "pruned_first": m.first, "pruned_entries": m.entry_bytes(),
                      "pruned_find": [[r, m.find(r)] for r in roots]})
        return p


def chain():
    """Blocks over two segments with blob and column sidecars; then a copy and a prune."""
    c = Case("chain", (3 * SEG, 64), SEG)
    slots1 = [SEG + s for s in (0, 1, 2, 5, 9, 31, 64, 1000, 8190, 8191)]
    slots2 = [2 * SEG + s for s in (0, 3, 4, 100, 4097)]
    data, roots = b"", []
    for s in slots1:
        r, root = c.block(s)
        data += r
        roots.append(root)
    c.segment(1, 0, data)
    data = b""
    for s in slots2:
        r, root = c.block(s)
        data += r
        roots.append(root)
    c.segment(2, 0, data)
    data = b""
    for s in slots1[1:4]:
        for i in (0, 1, 2):
            data += c.sidecar(BLOB, s, i)
    for s in slots1[5:8]:
        for i in (3, 17, 40, 99):
            data += c.sidecar(COLUMN, s, i)
    c.segment(1, 1, data)
    data = b""
    for s in slots2[:2]:
        for i in (0, 127):
            data += c.sidecar(COLUMN, s, i)
    c.segment(2, 1, data)
    c.segment(1, 2, c.state(STATE, slots1[0]) + b"".join(c.state(DIFF, s) for s in (slots1[3], slots1[6], slots1[9])))
    c.segment(2, 2, c.state(STATE, slots2[1]) + c.state(DIFF, slots2[4]))
    collide = roots[0][:8] + made("collide")[8:]  # the same first 8 bytes as a block's root
    extra = [made("none", 1), made("none", 2), collide]
    return c.name, c.parts(extra, copy_room=(6 * SEG, 128), prune=2 * SEG)


def backfill():
    """A block segment written from its last slot down, as a backfill writes."""
    c = Case("backfill", (SEG, 32), 0)
    data = b""
    for s in (900, 700, 512, 511, 3, 0):
        data += c.block(s)[0]
    c.segment(0, 0, data)
    return c.name, c.parts([made("none")], copy_room=(2 * SEG, 64), prune=512)


def torn():
    """A segment that ends inside a record, as a crash leaves one: the whole records only."""
    c = Case("torn", (SEG, 32), 0)
    data = b"".join(c.block(s)[0] for s in (1, 2, 3))
    c.segment(0, 0, data[:-20])
    c.segment(0, 1, c.sidecar(COLUMN, 1, 5) + c.sidecar(COLUMN, 1, 6)[:63])
    return c.name, c.parts()


def rule(name, build):
    c = Case(name, (2 * SEG, 32), 0)
    build(c)
    return name, c.parts()


def rules():
    """Segments whose next record breaks a rule: the scan ends before it."""
    def twice(c):
        c.segment(0, 0, c.block(5)[0] + c.block(6)[0] + c.block(5)[0] + c.block(7)[0])

    def outside(c):
        c.segment(0, 0, c.block(5)[0] + c.block(SEG + 1)[0] + c.block(6)[0])

    def same_root(c):
        r5, root = c.block(5)
        c.segment(0, 0, r5 + record(BLOCK, 9, 0, root, b"x") + c.block(10)[0])

    def no_block(c):
        c.segment(0, 0, c.block(5)[0])
        c.segment(0, 1, c.sidecar(COLUMN, 5, 1) + c.sidecar(COLUMN, 6, 1) + c.sidecar(COLUMN, 5, 2))

    def index_order(c):
        c.segment(0, 0, c.block(5)[0])
        c.segment(0, 1, c.sidecar(COLUMN, 5, 4) + c.sidecar(COLUMN, 5, 4) + c.sidecar(COLUMN, 5, 9))

    def apart(c):
        c.segment(0, 0, c.block(5)[0] + c.block(6)[0])
        c.segment(0, 1, c.sidecar(BLOB, 5, 0) + c.sidecar(BLOB, 6, 0) + c.sidecar(BLOB, 5, 1))

    def wrong_kind(c):
        c.segment(0, 0, c.block(5)[0] + c.sidecar(BLOB, 5, 0))
        c.segment(0, 1, c.sidecar(BLOB, 5, 0) + c.block(6)[0])
        c.segment(1, 1, record(7, SEG, 0, made("k"), b"abc"))
        c.segment(0, 2, c.sidecar(BLOB, 5, 1))
        c.segment(0, 0, c.state(STATE, 5))

    def other_size(c):
        c.segment(0, 0, c.block(5)[0])
        c.segment(0, 1, c.sidecar(COLUMN, 5, 1) + c.sidecar(COLUMN, 5, 2) + record(COLUMN, 5, 3, made(c.name, "block", 5), b"\1" * 99))

    def index_high(c):
        c.segment(0, 0, c.block(5)[0])
        c.segment(0, 1, c.sidecar(COLUMN, 5, 126) + c.sidecar(COLUMN, 5, 127) + c.sidecar(COLUMN, 5, 128))

    def bytes_header(c):
        r5, root = c.block(5)
        c.segment(0, 0, r5 + record(BLOCK, 6, 0, made("hdr"), b"abc", header=(28, 24)) + c.block(7)[0])

    def too_long(c):
        c.segment(0, 0, c.block(5)[0] + record(BLOCK, 6, 0, made("long"), b"", length=RECORD_MAX + 1))

    def state_diff_first(c):
        c.segment(0, 0, c.block(5)[0] + c.block(6)[0])
        c.segment(0, 2, c.state(DIFF, 5) + c.state(STATE, 6))

    def state_full_later(c):
        c.segment(0, 0, c.block(5)[0] + c.block(6)[0] + c.block(7)[0])
        c.segment(0, 2, c.state(STATE, 5) + c.state(STATE, 6) + c.state(DIFF, 7))

    def state_no_block(c):
        c.segment(0, 0, c.block(5)[0] + c.block(7)[0])
        c.segment(0, 2, c.state(STATE, 5) + c.state(DIFF, 6) + c.state(DIFF, 7))

    def state_other_root(c):
        c.segment(0, 0, c.block(5)[0] + c.block(6)[0] + c.block(7)[0])
        c.segment(0, 2, c.state(STATE, 5) + record(DIFF, 6, 0, made("other"), b"abc") + c.state(DIFF, 7))

    def state_twice(c):
        c.segment(0, 0, c.block(5)[0] + c.block(6)[0])
        c.segment(0, 2, c.state(STATE, 5) + c.state(DIFF, 5) + c.state(DIFF, 6))

    def state_index(c):
        c.segment(0, 0, c.block(5)[0] + c.block(6)[0])
        c.segment(0, 2, c.state(STATE, 5) + record(DIFF, 6, 1, made(c.name, "block", 6), b"abc"))

    def below_first(c):
        c.model = Model(c.room, 64)
        c.first = 64
        c.segment(0, 0, c.block(70)[0] + c.block(63)[0])

    return [rule(n, b) for n, b in (("block_twice", twice), ("slot_outside", outside), ("root_twice", same_root),
                                     ("sidecar_no_block", no_block), ("sidecar_index_order", index_order),
                                     ("sidecars_apart", apart), ("wrong_kind", wrong_kind),
                                     ("sidecar_other_size", other_size), ("sidecar_index_high", index_high),
                                     ("record_bytes_header", bytes_header),
                                     ("length_over_max", too_long), ("below_first_slot", below_first),
                                     ("state_diff_first", state_diff_first), ("state_full_later", state_full_later),
                                     ("state_no_block", state_no_block), ("state_other_root", state_other_root),
                                     ("state_twice", state_twice), ("state_index", state_index))]


def small():
    """A room too small: the scan stops with LANTERN_BUFFER_TOO_SMALL at the record that needs more."""
    a = Case("small_slots", (16, 32), 0)
    a.segment(0, 0, b"".join(a.block(s)[0] for s in (3, 15, 16, 17)))
    b = Case("small_roots", (SEG, 8), 0)
    b.segment(0, 0, b"".join(b.block(s)[0] for s in (1, 2, 3, 4, 5, 6)))
    return [(a.name, a.parts(copy_room=(32, 32))), (b.name, b.parts(copy_room=(SEG, 16)))]


def cases():
    yield chain()
    yield backfill()
    yield torn()
    yield from rules()
    yield from small()


def diff(base, state):
    """lantern_db_state_diff: the runs of the words of state that differ from the patch's start."""
    n = len(state)
    start = base[:n] + bytes(max(0, n - len(base)))
    words = (n + 7) // 8
    differ = [state[8 * w:8 * w + 8] != start[8 * w:8 * w + 8] for w in range(words)]
    out = struct.pack("<Q", n)
    w = 0
    while w < words:
        if not differ[w]:
            w += 1
            continue
        last, k = w, w + 1
        while k < words:
            if differ[k]:
                last, k = k, k + 1
                continue
            j = k
            while j < words and not differ[j]:
                j += 1
            if j == words or j - k > 2:
                break
            k = j
        off, end = 8 * w, min(8 * (last + 1), n)
        out += struct.pack("<QQ", off, end - off) + state[off:end] + bytes(-(end - off) % 8)
        w = last + 1
    return out


def patch(base, d):
    """lantern_db_state_patch: the state's bytes, or None for a diff that breaks a rule."""
    if len(d) < 8:
        return None
    n = struct.unpack_from("<Q", d)[0]
    out = bytearray(base[:n] + bytes(max(0, n - len(base))))
    pos, prev = 8, 0
    while pos < len(d):
        if len(d) - pos < 16:
            return None
        off, cnt = struct.unpack_from("<QQ", d, pos)
        padded = cnt + (-cnt % 8)
        if cnt == 0 or off % 8 or off < prev or cnt > n or off > n - cnt or padded > len(d) - pos - 16:
            return None
        if any(d[pos + 16 + cnt:pos + 16 + padded]):
            return None
        out[off:off + cnt] = d[pos + 16:pos + 16 + cnt]
        prev, pos = off + cnt, pos + 16 + padded
    return bytes(out)


def stream(name, n):
    """n made up bytes."""
    out = b""
    while len(out) < n:
        out += made("diff", name, len(out))
    return out[:n]


def changed(data, places):
    """data with the byte at each place changed."""
    out = bytearray(data)
    for p in places:
        out[p] ^= 0x5A
    return bytes(out)


def diff_cases():
    base = stream("base", 200)
    big = stream("big", 1 << 16)
    pairs = [
        ("equal", base, base),
        ("one_word", base, changed(base, [17])),
        ("two_words_near", base, changed(base, [16, 47])),
        ("two_words_apart", base, changed(base, [16, 55])),
        ("first_and_last_bytes", base, changed(base, [0, 199])),
        ("grow", base, changed(base, [30]) + bytes(40) + stream("tail", 13) + bytes(24) + b"\1"),
        ("grow_with_zero_words", base[:96], base[:96] + bytes(16) + b"\7" + bytes(30)),
        ("shrink", base, changed(base[:101], [100])),
        ("shrink_equal", base, base[:93]),
        ("unaligned_end", base[:101], changed(base[:101], [97])),
        ("empty_base", b"", stream("new", 50)),
        ("empty_state", base, b""),
        ("all_differ", base, stream("other", 200)),
        ("sparse_large", big, changed(big, [8 * k * k % (1 << 16) for k in range(1, 300)])),
        ("dense_large", big, b"".join(big[i:i + 4] + bytes(4) for i in range(0, 1 << 16, 8))),
    ]
    for name, b, st in pairs:
        d = diff(b, st)
        assert patch(b, d) == st and len(d) <= 24 + (len(st) + 7) // 8 * 8, name
        yield name, {"base": b, "state": st, "diff": d}
    one = diff(base, changed(base, [17, 101]))
    run = lambda off, cnt, data: struct.pack("<QQ", off, cnt) + data + bytes(-cnt % 8)
    bads = [
        ("bad_short", b"\1\2\3\4\5"),
        ("bad_run_past_length", struct.pack("<Q", 16) + run(8, 16, bytes(16))),
        ("bad_out_of_order", struct.pack("<Q", 64) + run(32, 8, b"x" * 8) + run(16, 8, b"y" * 8)),
        ("bad_overlap", struct.pack("<Q", 64) + run(16, 16, b"x" * 16) + run(24, 8, b"y" * 8)),
        ("bad_count_zero", struct.pack("<Q", 64) + run(16, 0, b"")),
        ("bad_offset_unaligned", struct.pack("<Q", 64) + run(4, 8, b"x" * 8)),
        ("bad_padding", struct.pack("<Q", 64) + struct.pack("<QQ", 16, 3) + b"abc\0\0\1\0\0"),
        ("bad_cut_short", struct.pack("<Q", 64) + struct.pack("<QQ", 16, 16) + b"x" * 8),
        ("bad_trailing", one + bytes(8)),
        ("bad_huge_count", struct.pack("<Q", 64) + struct.pack("<QQ", 8, (1 << 64) - 8) + b"x" * 8),
    ]
    for name, bad in bads:
        assert patch(base, bad) is None, name
        yield name, {"base": base, "bad": bad}
