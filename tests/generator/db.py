"""Cases of lantern's database index (docs/reference/db.md).

No outside specification defines the record format or the index: these cases follow the rules
of docs/reference/db.md, written out here as a model of the index. The records are made up:
roots and bytes from SHA-256 of a counter, so every run gives the same cases.

cases() yields (name, parts):
- room: [slots, roots]; first_slot.
- segments: in scan order, each {number, sidecars, bytes, status, valid}: lantern_db_scan of the
  bytes must give the status (0, or 1 for LANTERN_BUFFER_TOO_SMALL) and valid.
- end_slot, blocks, entries: the Db after the scans; entries the DbSlot bytes from first_slot
  below end_slot.
- find: [root, slot] pairs, 2^64 - 1 for none.
- copy_room: a larger room; lantern_db_copy to it must keep end_slot, blocks, entries and find.
- prune, pruned_first, pruned_entries, pruned_find: lantern_db_prune to prune, then the Db.
"""

import hashlib
import struct

SEG = 8192  # DB_SEGMENT_SLOTS
U64 = (1 << 64) - 1
BLOCK, BLOB, COLUMN = 1, 2, 3
RECORD_MAX = 1 << 32
OK, SMALL, INVALID = 0, 1, 2


def made(*parts):
    """32 bytes of SHA-256 of the parts."""
    return hashlib.sha256(repr(parts).encode()).digest()


def record(kind, slot, index, root, data, length=None):
    """A record: the DbRecord header, the bytes, zero bytes up to a multiple of 8."""
    n = len(data) if length is None else length
    return struct.pack("<QQQQ", n, kind, slot, index) + root + data + b"\0" * (-len(data) % 8)


class Model:
    """The index of docs/reference/db.md."""

    def __init__(self, room, first):
        self.cap, self.rcap = room
        self.first = self.end = first
        self.entries = {}  # entry index: [root, block, sidecars, count, end, last]
        self.roots = {}  # root: entry index

    def add(self, kind, slot, index, root, length, offset):
        if offset % 8 or offset >= 1 << 48 or length > RECORD_MAX or slot < self.first:
            return INVALID
        i = slot - self.first
        if i >= self.cap:
            return SMALL
        e = self.entries.get(i)
        size = 64 + length + (-length % 8)
        if kind == BLOCK:
            if (e and e[1]) or root in self.roots:
                return INVALID
            if (len(self.roots) + 1) * 2 > self.rcap:
                return SMALL
            self.entries[i] = [root, offset + 1, 0, 0, 0, 0]
            self.roots[root] = i
            self.end = max(self.end, slot + 1)
            return OK
        if kind not in (BLOB, COLUMN) or not e or not e[1]:
            return INVALID
        if e[2]:
            if e[4] != offset or index <= e[5]:
                return INVALID
        else:
            e[2] = offset + 1
        e[3] += 1
        e[4] = offset + size
        e[5] = index
        return OK

    def scan(self, number, sidecars, data):
        pos, base = 0, number * SEG
        while len(data) - pos >= 64:
            length, kind, slot, index = struct.unpack_from("<QQQQ", data, pos)
            root = data[pos + 32:pos + 64]
            if length > RECORD_MAX:
                break
            size = 64 + length + (-length % 8)
            if size > len(data) - pos or slot < base or slot - base >= SEG or (kind != BLOCK) != bool(sidecars):
                break
            r = self.add(kind, slot, index, root, length, pos)
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
            out += e[0] + struct.pack("<QQQQQ", *e[1:]) if e else bytes(72)
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
        return record(kind, slot, index, made(self.name, "block", slot), self.bytes_of(8 + (slot * 7 + index) % 53))

    def segment(self, number, sidecars, data):
        status, valid = self.model.scan(number, sidecars, data)
        self.segments.append({"number": number, "sidecars": sidecars, "bytes": data, "status": status, "valid": valid})

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

    def too_long(c):
        c.segment(0, 0, c.block(5)[0] + record(BLOCK, 6, 0, made("long"), b"", length=RECORD_MAX + 1))

    def below_first(c):
        c.model = Model(c.room, 64)
        c.first = 64
        c.segment(0, 0, c.block(70)[0] + c.block(63)[0])

    return [rule(n, b) for n, b in (("block_twice", twice), ("slot_outside", outside), ("root_twice", same_root),
                                     ("sidecar_no_block", no_block), ("sidecar_index_order", index_order),
                                     ("sidecars_apart", apart), ("wrong_kind", wrong_kind),
                                     ("length_over_max", too_long), ("below_first_slot", below_first))]


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
