# Beacon state buffers

## Contents

### Functions

- [`lantern_beacon_state_copy_size`](#function-lantern_beacon_state_copy_size): the buffer size of a copy of a state with room.
- [`lantern_beacon_state_copy`](#function-lantern_beacon_state_copy): copies a state into a new buffer with room in its lists.
- [`lantern_copy`](#function-lantern_copy): copies bytes.
- [`lantern_state_cache_size`](#function-lantern_state_cache_size): the bytes of a hash cache for a number of validators.
- [`lantern_state_cache_init`](#function-lantern_state_cache_init): lays out an empty hash cache.
- [`lantern_state_root`](#function-lantern_state_root): the hash tree root of a state, from a hash cache it brings up to date.

### Types

- [`StateRoom`](#type-stateroom): the free entries a copy gives each list of the state.
- [`StateCache`](#type-statecache): the Merkle trees of the large fields of the last state hashed.
- [`CacheTree`](#type-cachetree): the tree of one field.

## Spec

- Document: ARCHITECTURE.md section 6, "Memory preparation": the resize function of a type.
- Section: lantern's own functions. The state transition appends to the lists of a `BeaconState` within the room of their parts.
- lantern_state_root: `hash_tree_root` of ssz-specs v0.1.0, as [asm-ssz](https://github.com/bitminetech/asm-ssz/blob/3c8c9b405efe432bc0153aa3d0a9a5d31e6d3328/docs/reference/merkleization.md) gives it: `merkleize` with the zero hashes of each depth, and `mix_in_length` for a list.

## Test vectors

- Each runner process keeps one `StateCache` of lantern_state_cache_size(4096) from lantern_state_cache_init, and the config of every call names it at `CONFIG_STATE_CACHE`, so each state transition of the vectors hashes through it.
- The state of each case that the runner compares with a `post` state: lantern_state_root with that cache, and with 0, must give ssz_hash_tree_root of the state. The runner counts them in a NOTE.

## Function `lantern_beacon_state_copy_size`

The bytes that lantern_beacon_state_copy needs for a copy of state with room.

### Signature

```
lantern_beacon_state_copy_size(state, room, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `room` | input | `StateRoom` |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- Pass a valid `BeaconState` value in `state`.

### Function does

- Adds the fixed part of the state and, for each of its parts, the bytes of its entries plus the room for its kind, rounded up to 8.
- Phase0: the entries of previous_epoch_attestations and current_epoch_attestations are nested values, each starting with its size.
- Gives the part of `latest_execution_payload_header` room for an `extra_data` of MAX_EXTRA_DATA_BYTES.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_beacon_state_copy_size`, as in [helpers.md](helpers.md#common-rules).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `room`, `size`.

## Function `lantern_beacon_state_copy`

Copies state into out, with the parts laid out in field order and room after the entries of each.

### Signature

```
lantern_beacon_state_copy(state, room, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `room` | input | `StateRoom` |
| `out` | output | `BeaconState` |

### Returns

- `LANTERN_OK`: `out` holds the copy.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_beacon_state_copy_size gives.

### Caller must

- Pass a valid `BeaconState` value in `state`.
- Set the `size` field of `out` to its buffer size.
- Keep `state` and `out` apart.

### Function does

- Writes a valid `BeaconState` that holds the same value as `state`.
- Gives each part the room of lantern_beacon_state_copy_size, and the last part the rest of the buffer.
- Keeps the `size` of `out`.

### Function never

- Writes outside `out` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_beacon_state_copy`, as in [helpers.md](helpers.md#common-rules).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `room`, `out`.

## Function `lantern_copy`

Copies n bytes from src to dst.

### Signature

```
lantern_copy(dst, src, n) -> nothing
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | n bytes |
| `src` | input | n bytes |
| `n` | input | u64 in a register |

### Caller must

- Keep `dst` and `src` apart, or pass dst below src.

### Function never

- Reads or writes outside the n bytes of each.

### ABI

- Role: L0.
- Symbol: the local label `lantern_copy` in each object of the core.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns no status.
- Argument order: `dst`, `src`, `n`.

## Function `lantern_state_cache_size`

The bytes of a `StateCache` for a number of validators.

### Signature

```
lantern_state_cache_size(validators, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validators` | input | u64 |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Function does

- The header, then for each tree of the [`StateCache`](#type-statecache) table in order: its nodes, 32 bytes for each of ceil(capacity / 2^k) nodes at each level k from 0 up to the level of one node; its dirty bits, ceil(nodes of the level / 64) u64 at each level; and its copies, `copy` bytes for each of `capacity` leaves.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_state_cache_size`, as in [helpers.md](helpers.md#common-rules).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `validators`, `size`.

## Function `lantern_state_cache_init`

Lays out an empty `StateCache` for a number of validators.

### Signature

```
lantern_state_cache_init(validators, cache) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validators` | input | u64 |
| `cache` | output | `StateCache`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `cache` is empty.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `cache` is below what lantern_state_cache_size gives.

### Function does

- Writes `validators` and each `CacheTree` with the capacity of the table, `count` 0, the offsets of lantern_state_cache_size's order, and every dirty bit 0.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_state_cache_init`, as in [helpers.md](helpers.md#common-rules).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `validators`, `cache`.

## Function `lantern_state_root`

hash_tree_root(state), from the trees of a `StateCache`, which it brings up to that state.

### Signature

```
lantern_state_root(state, cache, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `cache` | state | `StateCache`, or 0 |
| `scratch` | scratch | `Scratch` |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`: `out` holds the root.
- `LANTERN_BUFFER_TOO_SMALL`: with a cache, `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes; else as ssz_hash_tree_root.

### Caller must

- Pass a valid `BeaconState` value in `state`.
- Pass a `cache` that lantern_state_cache_init laid out, with the same preset.
- Keep `cache` apart from `state`, `scratch` and `out`.

### Function does

- With `cache` 0, in phase0, or when a field of a tree has more leaves than the tree's capacity: ssz_hash_tree_root of the state, with the cache left as it is.
- Else merkleize of the roots of the state's fields:
  - A field of a tree: its leaves are its chunks for a list or vector of basic values, the last padded with zeros, or the hash tree root of each element for a list of containers. With n leaves, a leaf at an index of at least `count`, or whose chunk or element bytes (`copy` bytes) differ from the tree's, takes the new chunk or root, its copy takes the element's bytes, and it is dirty; with n below `count`, leaf n - 1 is dirty too. Level by level, each node with a dirty child takes the hash of its two children, a child past the ceil(n / 2^k) nodes of level k being the zero hash of depth k, and is dirty; the child's bit clears. The node at level ceil(log2(n)), hashed with the zero hash of each depth up to the depth of the field's limit, is the root of a vector; a list's is mixed with its length. With n 0, the zero hash of the limit's depth. `count` takes n.
  - Another field: ssz_hash_tree_root of its type: an inline value (Uint64, Bytes32, JustificationBits, Fork, BeaconBlockHeader, Eth1Data, Checkpoint, SyncCommittee), or the nested value of the part of latest_execution_payload_header.
- The root is that of ssz_hash_tree_root of the state for any contents an earlier call left in the cache: the cache changes only the time.

### Function never

- Writes outside `cache`, `scratch`, `out` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_state_root`, as in [helpers.md](helpers.md#common-rules).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `cache`, `scratch`, `out`.

## Type `StateRoom`

The free entries that a copy gives each list of a `BeaconState`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `validators` | u64 | Entries of room in validators, balances, both epoch participations and inactivity_scores |
| 8 | `eth1_data_votes` | u64 | Entries of room in eth1_data_votes |
| 16 | `historical_summaries` | u64 | Entries of room in historical_summaries |
| 24 | `pending_deposits` | u64 | Entries of room in pending_deposits |
| 32 | `pending_partial_withdrawals` | u64 | Entries of room in pending_partial_withdrawals |
| 40 | `pending_consolidations` | u64 | Entries of room in pending_consolidations |
| 48 | `historical_roots` | u64 | Entries of room in historical_roots |
| 56 | `pending_attestations` | u64 | Entries of room in each of previous_epoch_attestations and current_epoch_attestations, each the size of a PendingAttestation with the longest aggregation_bits |

### Rules

- 64 bytes.
- A copy uses the fields of the lists that its fork's state holds.

## Type `StateCache`

The Merkle trees of the large fields of the last state that lantern_state_root hashed with it.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this field included |
| 8 | `validators` | u64 | The validators it was laid out for |
| 16 | `trees` | `CacheTree` × `STATE_CACHE_TREES` | The trees, in the order of the table |

### Trees

| Tree | Field | Leaves | Capacity |
|---|---|---|---|
| 0 | validators | Validator roots, copies of 128 bytes | `validators` |
| 1 | balances | Chunks | ceil(`validators` / 4) |
| 2 | inactivity_scores | Chunks | ceil(`validators` / 4) |
| 3 | previous_epoch_participation | Chunks | ceil(`validators` / 32) |
| 4 | current_epoch_participation | Chunks | ceil(`validators` / 32) |
| 5 | block_roots | Chunks | SLOTS_PER_HISTORICAL_ROOT |
| 6 | state_roots | Chunks | SLOTS_PER_HISTORICAL_ROOT |
| 7 | randao_mixes | Chunks | EPOCHS_PER_HISTORICAL_VECTOR |
| 8 | slashings | Chunks | EPOCHS_PER_SLASHINGS_VECTOR / 4 |
| 9 | historical_roots | Chunks | `STATE_CACHE_HISTORICAL_ROOTS` |
| 10 | eth1_data_votes | Eth1Data roots, copies of `Eth1Data__mem` bytes | EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH |
| 11 | historical_summaries | HistoricalSummary roots, copies of `HistoricalSummary__mem` bytes | `STATE_CACHE_LIST` |
| 12 | pending_deposits | PendingDeposit roots, copies of `PendingDeposit__mem` bytes | `STATE_CACHE_PENDING_DEPOSITS` |
| 13 | pending_partial_withdrawals | PendingPartialWithdrawal roots, copies of `PendingPartialWithdrawal__mem` bytes | `STATE_CACHE_LIST` |
| 14 | pending_consolidations | PendingConsolidation roots, copies of `PendingConsolidation__mem` bytes | `STATE_CACHE_LIST` |
| 15 | proposer_lookahead | Chunks | (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH / 4 |

### Rules

- 16 + 48 * `STATE_CACHE_TREES` bytes of header, then the bytes of each tree.
- A tree of a field that the state's fork does not hold keeps its `count`.

## Type `CacheTree`

The Merkle tree of one field of the last state hashed.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `capacity` | u64 | The leaves it holds |
| 8 | `count` | u64 | The leaves of the last root; 0 for none |
| 16 | `nodes` | u64 | The offset in the cache of its level 0; each level follows the one below |
| 24 | `dirty` | u64 | The offset in the cache of the dirty bits of its level 0, a u64 for each 64 nodes; each level follows the one below |
| 32 | `copies` | u64 | The offset in the cache of the copies of its elements, or 0 |
| 40 | `copy` | u64 | The bytes of the copy of an element, or 0 |

### Rules

- 48 bytes.
- Level 0 holds the leaves: a chunk, or an element's root.
- Its nodes below `count` at each level are those of the last root; its dirty bits are 0 between calls.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_beacon_state_copy_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_beacon_state_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_state_cache_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_state_cache_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_state_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
