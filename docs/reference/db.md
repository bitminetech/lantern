# Database

## Contents

### Functions

- [`lantern_db_size`](#function-lantern_db_size): the bytes of a `Db` with given capacities.
- [`lantern_db_init`](#function-lantern_db_init): an empty `Db` from a first slot.
- [`lantern_db_copy`](#function-lantern_db_copy): copies a `Db` into a buffer with more capacity.
- [`lantern_db_add`](#function-lantern_db_add): adds one record to the index.
- [`lantern_db_scan`](#function-lantern_db_scan): adds each whole record of a segment's bytes to the index.
- [`lantern_db_find_root`](#function-lantern_db_find_root): the slot of a block root.
- [`lantern_db_prune`](#function-lantern_db_prune): drops the slots below a new first slot.
- [`lantern_db_drop_sidecars`](#function-lantern_db_drop_sidecars): drops the sidecars of the slots below a slot.

### Types

- [`Db`](#type-db): the index of the stored history.
- [`DbRoom`](#type-dbroom): the capacities of a `Db`.
- [`DbSlot`](#type-dbslot): what the history holds for one slot.
- [`DbRecord`](#type-dbrecord): the header of a record in a segment.

## Spec

- Document: this file. The record format and the index are lantern's own; no outside specification defines them.
- `p2p-interface.md` of phase0 and fulu of [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs): the node serves blocks of `MIN_EPOCHS_FOR_BLOCK_REQUESTS` epochs and column sidecars of `MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS` epochs, which the history holds.
- ARCHITECTURE.md section 2: the index and the record format are core; the files are the shell's.

## Common rules

- As in [helpers.md](helpers.md#common-rules).
- The history: the finalized blocks of the canonical chain, and their blob or column sidecars, in segment files. A segment holds the records of `DB_SEGMENT_SLOTS` slots: segment `n` the slots from `n` * `DB_SEGMENT_SLOTS`. Blocks and sidecars are in separate segments, so each can be dropped on its own.
- A record is a `DbRecord` header, then its SSZ bytes, then zero bytes up to a multiple of 8. A record starts at a multiple of 8 of its segment.
- In a block segment the records are blocks, at most one for each slot, in any slot order: a backfill writes older blocks after newer ones. In a sidecar segment they are blob or column sidecars; those of one slot are together, in ascending index order.
- A `Db` indexes the history of the slots from `first_slot` below `end_slot`: for each slot the offsets of its records in their segments, and for each block its root. A record's segment follows from its slot, so the index keeps offsets only. Every u64 argument is passed by its address, as ARCHITECTURE.md section 6 asks.
- The functions read no file and make no OS call. The caller reads the segments and passes their bytes: each block segment before the sidecar segments, since a sidecar needs its slot's block.
- Every function is in the common object of the core (asm/core/<ISA>/db.s), and its symbol is its name.

## Test vectors

- Lantern's cases `<preset>-phase0-db-index.bin`, made by tests/generator/db.py, a model of the rules of this file: block and sidecar segments of made up records over several segments, each with its index.
  - lantern_db_scan of each segment's bytes must give the case's valid length, and the `Db` after all segments must hold the case's `DbSlot` entries.
  - lantern_db_find_root of each block root of the case must give its slot, and of made up roots no slot.
  - Segments that end inside a record, or whose next record breaks a rule, must give the valid length up to that record.
  - lantern_db_prune to a later first slot must leave the entries from it, and lantern_db_find_root of a dropped root no slot.
  - lantern_db_drop_sidecars to the first slot of the second segment must leave no sidecar below it, and every block and every later sidecar as they were.
  - A `Db` of small room must give `LANTERN_BUFFER_TOO_SMALL`, and lantern_db_copy to twice the room must hold the same index.

## Function `lantern_db_size`

The bytes of a `Db` whose parts have the capacities of a `DbRoom`.

### Signature

```
lantern_db_size(room, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `room` | input | `DbRoom` |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`: `size` holds `DB_FIXED` plus the bytes of each part.
- `LANTERN_INVALID_OVERFLOW`: the size is 2^64 or more, or `roots` is not a power of two.

## Function `lantern_db_init`

A `Db` of no records whose `first_slot` and `end_slot` are a slot.

### Signature

```
lantern_db_init(room, slot, db) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `room` | input | `DbRoom` |
| `slot` | input | u64 |
| `db` | output | `Db`, its `size` set |

### Returns

- `LANTERN_OK`: `db` is written.
- `LANTERN_BUFFER_TOO_SMALL`: `db` is smaller than lantern_db_size of `room`.
- `LANTERN_INVALID_OVERFLOW`: as lantern_db_size.

## Function `lantern_db_copy`

The `Db` in a new buffer with the capacities of a `DbRoom`.

### Signature

```
lantern_db_copy(db, room, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `db` | input | `Db` |
| `room` | input | `DbRoom` |
| `out` | output | `Db`, its `size` set |

### Returns

- `LANTERN_OK`: `out` holds the same index.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is smaller than lantern_db_size of `room`, `room.slots` is below `end_slot` - `first_slot`, or `room.roots` is below twice the blocks indexed.
- `LANTERN_INVALID_OVERFLOW`: as lantern_db_size.

### Function does

- Places each root again in the table of the new capacity.

## Function `lantern_db_add`

Adds one record, at an offset of its segment, to the index.

### Signature

```
lantern_db_add(db, record, offset) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `db` | state | `Db` |
| `record` | input | `DbRecord` |
| `offset` | input | u64: the byte offset of the record in its segment |

### Returns

- `LANTERN_OK`: the record is in the index.
- `LANTERN_BUFFER_TOO_SMALL`: its slot is at `first_slot` + `room.slots` or later, or a block would fill the root table past half. Nothing is changed.
- `LANTERN_INVALID_RECORD`: the record breaks a rule below. Nothing is changed.

### Function does

- The rules: `kind` is `DB_BLOCK`, `DB_BLOB_SIDECAR` or `DB_COLUMN_SIDECAR`; the slot is at least `first_slot`; `offset` is a multiple of 8 and below 2^48. A block: its slot has no block yet, and its root is in no other slot. A sidecar: its slot has a block, its index is below `DB_SIDECAR_INDICES` (128) and above the slot's `sidecar_last` when the slot has sidecars, and its offset is the end of the slot's sidecars before it, with the size of the slot's first sidecar record, or the slot has none.
- A block: the slot's `block` takes `offset` + 1 and its `root` the record's root; the root goes in the root table; `end_slot` takes the slot + 1 when that is more.
- A sidecar: the slot's `sidecars` takes `offset` + 1 when it has none, `sidecar_count` takes 1 more, `sidecar_end` takes `offset` + the record's size, `sidecar_last` its index, and `indices` its bit.
- So the sidecar records of a slot are of one size, and the record of index i lies at `sidecars` - 1 + that size times the count of the slot's indices below i: a node finds any sidecar without reading the segment.
- `length` is at most `DB_RECORD_MAX` for each kind.

## Function `lantern_db_scan`

Adds each whole record of a segment's bytes to the index, from the start, until one does not fit or breaks a rule.

### Signature

```
lantern_db_scan(db, segment, sidecars, bytes, valid) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `db` | state | `Db` |
| `segment` | input | u64: the segment's number |
| `sidecars` | input | u64: 0 for a block segment, 1 for a sidecar segment |
| `bytes` | input | ByteList: the segment's bytes from its start |
| `valid` | output | u64: the bytes of the whole records added |

### Returns

- `LANTERN_OK`: `valid` holds the end of the last record added, 0 with none.
- `LANTERN_BUFFER_TOO_SMALL`: as lantern_db_add, for the record at `valid`; the records before it are added.

### Function does

- A record fits when its header and its size are inside `bytes`, `length` is at most `DB_RECORD_MAX`, its slot is in the segment's slots, and its kind is `DB_BLOCK` in a block segment and a sidecar kind in a sidecar segment. A record that does not fit, or that lantern_db_add rejects, ends the scan.
- Calls lantern_db_add for each record that fits.

## Function `lantern_db_find_root`

The slot of the block of a root in the index.

### Signature

```
lantern_db_find_root(db, root, slot) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `db` | input | `Db` |
| `root` | input | Root |
| `slot` | output | u64: the slot, or 2^64 - 1 for none |

### Returns

- `LANTERN_OK`: `slot` is written.

## Function `lantern_db_prune`

Drops the slots below a new first slot from the index.

### Signature

```
lantern_db_prune(db, slot) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `db` | state | `Db` |
| `slot` | input | u64: the new `first_slot` |

### Returns

- `LANTERN_OK`: `first_slot` is the slot, at most `end_slot`; the entries from it move to the front, and the root table holds their roots only.

### Caller must

- Drop whole segments only: a slot that is a multiple of `DB_SEGMENT_SLOTS`, so no kept slot has records in a dropped file.

## Function `lantern_db_drop_sidecars`

Drops the sidecars of the slots below a slot from the index, as a node does once they leave their serve range (deneb and fulu `p2p-interface.md`: the node serves sidecars of `MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS` and `MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS` epochs).

### Signature

```
lantern_db_drop_sidecars(db, slot) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `db` | state | `Db` |
| `slot` | input | u64 |

### Returns

- `LANTERN_OK`: each `DbSlot` from `first_slot` below the slot and `end_slot` has `sidecars`, `sidecar_count`, `sidecar_end`, `sidecar_last` and `indices` 0; its root and block stay.

### Caller must

- Drop whole sidecar segments only: a slot that is a multiple of `DB_SEGMENT_SLOTS`.

## Type `Db`

The index of the history: a value with parts.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer |
| 8 | `first_slot` | u64 | The first slot of the index |
| 16 | `end_slot` | u64 | The slot after the highest block indexed, or `first_slot` |
| 24 | `slots` | PartRef | `DbSlot` entries: entry `i` for slot `first_slot` + `i`; its capacity in `count` |
| 40 | `roots` | PartRef | u64 entries: 0, or the slot - `first_slot` + 1 of a block; a power of two of them in `count` |
| 56 | `blocks` | u64 | The blocks indexed |

### Rules

- `DB_FIXED` (64) bytes of fixed fields; the parts follow in the order slots, roots.
- A block's root sits at the first free entry from the u64 of its first 8 bytes modulo the table's capacity, in order and around.

## Type `DbRoom`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `slots` | u64 | Capacity of `slots` |
| 8 | `roots` | u64 | Capacity of `roots`, a power of two |

## Type `DbSlot`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | Its block's root, or zero |
| 32 | `block` | u64 | 0, or the offset + 1 of its block record in its block segment |
| 40 | `sidecars` | u64 | 0, or the offset + 1 of its first sidecar record in its sidecar segment |
| 48 | `sidecar_count` | u64 | |
| 56 | `sidecar_end` | u64 | The offset after its last sidecar record |
| 64 | `sidecar_last` | u64 | The index of its last sidecar |
| 72 | `indices` | 16 bytes | The indices of its sidecars: bit i % 8 of byte i / 8 for index i |

### Rules

- `DbSlot__mem` (88) bytes.

## Type `DbRecord`

The header of a record.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `DB_BLOCK` (1), `DB_BLOB_SIDECAR` (2) or `DB_COLUMN_SIDECAR` (3) |
| 8 | `slot` | u64 | The slot of the block |
| 16 | `index` | u64 | The sidecar's index or column, 0 for a block |
| 24 | `root` | Root | The block's root |
| 56 | `bytes` | 24 bytes | A ByteList header of the SSZ bytes after the record's header: `size` 24 + `length`, `offset` 24 |
| 72 | `length` | u64 | The count of `bytes`: the SSZ bytes after the header |
| 80 | | | Size |

### Rules

- A record's size: 80 + `length`, rounded up to a multiple of 8.
- The ByteList at 56 is valid in place, so the record's bytes in a mapped segment need no copy: lantern_db_add refuses another `size` or `offset`.
- `DB_RECORD_MAX`: 2^32 bytes of `length`.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_db_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_db_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_db_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_db_add`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_db_scan`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_db_find_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_db_prune`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_db_drop_sidecars`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
