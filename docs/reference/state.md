# Beacon state buffers

Copies of states, and their hash caches.

## Contents

### Functions

- [`lantern_beacon_state_copy_size`](#function-lantern_beacon_state_copy_size): the buffer size of a copy of a state with room.
- [`lantern_beacon_state_copy`](#function-lantern_beacon_state_copy): copies a state into a new buffer with room in its lists.
- [`lantern_copy`](#function-lantern_copy): copies bytes.
- [`lantern_state_cache_size`](#function-lantern_state_cache_size): the bytes of a hash cache for a number of validators.
- [`lantern_state_cache_init`](#function-lantern_state_cache_init): lays out an empty hash cache.
- [`lantern_state_root`](#function-lantern_state_root): the hash tree root of a state, from a hash cache it brings up to date.
- [`lantern_state_root_pool`](#function-lantern_state_root_pool): lantern_state_root, with the large trees hashed by jobs on a pool of threads.
- [`lantern_sr_root`](#function-lantern_sr_root): lantern_state_root with a pool or none.
- [`lantern_sr_hash`](#function-lantern_sr_hash): sHA-256 of two 32-byte nodes.
- [`lantern_sr_layout`](#function-lantern_sr_layout): lays out the trees of a StateCache for a number of validators.
- [`lantern_sr_tree`](#function-lantern_sr_tree): the root of one field of a state, from its CacheTree.
- [`lantern_sr_job`](#function-lantern_sr_job): a job of lantern_sr_tree: the leaves and lower levels of a range.
- [`lantern_sr_leaves`](#function-lantern_sr_leaves): the leaves of a range of a CacheTree.
- [`lantern_sr_levels`](#function-lantern_sr_levels): the parents of dirty nodes, level by level, of a range of a CacheTree.
- [`lantern_sr_post`](#function-lantern_sr_post): the root of a CacheTree from its top.
- [`lantern_sr_clean`](#function-lantern_sr_clean): empties a CacheTree after a failure.
- [`lantern_sr_zeros`](#function-lantern_sr_zeros): the zero hash of each depth from 0 to 40.
- [`lantern_zero`](#function-lantern_zero): writes zero bytes.

### Types

- [`StateRoom`](#type-stateroom): the free entries a copy gives each list of the state.
- [`StateCache`](#type-statecache): the Merkle trees of the large fields of the last state hashed.
- [`CacheTree`](#type-cachetree): the tree of one field.
- [`SrCtx`](#type-srctx): the work of lantern_sr_tree on one tree, or of one job on a range of it.

## Spec

- Document: ARCHITECTURE.md section 6, "Memory preparation": the resize function of a type.
- Section: lantern's own functions. The state transition appends to the lists of a `BeaconState` within the room of their parts.
- lantern_state_root: `hash_tree_root` of ssz-specs v0.1.0, as [asm-ssz](https://github.com/bitminetech/asm-ssz/blob/3c8c9b405efe432bc0153aa3d0a9a5d31e6d3328/docs/reference/merkleization.md) gives it: `merkleize` with the zero hashes of each depth, and `mix_in_length` for a list.

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

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_beacon_state_copy_size` in the object of every fork, with `_` before it on macOS; `lantern_beacon_state_copy_size` inside the object.
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
- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_beacon_state_copy` in the object of every fork, with `_` before it on macOS; `lantern_beacon_state_copy` inside the object.
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
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_copy`, local to its object.
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

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_state_cache_size` in the object of every fork, with `_` before it on macOS; `lantern_state_cache_size` inside the object.
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

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_state_cache_init` in the object of every fork, with `_` before it on macOS; `lantern_state_cache_init` inside the object.
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

- lantern_sr_root with the cache's `pool`, or with none when `cache` is 0: with a pool, the jobs of lantern_state_root_pool, and the same root.
- With `cache` 0, in phase0, or when a field of a tree has more leaves than the tree's capacity: ssz_hash_tree_root of the state, with the cache left as it is.
- Else merkleize of the roots of the state's fields:
  - A field of a tree: its leaves are its chunks for a list or vector of basic values, the last padded with zeros, or the hash tree root of each element for a list of containers. With n leaves, a leaf at an index of at least `count`, or whose chunk or element bytes (`copy` bytes) differ from the tree's, takes the new chunk or root, its copy takes the element's bytes, and it is dirty; with n below `count`, leaf n - 1 is dirty too. Level by level, each node with a dirty child takes the hash of its two children, a child past the ceil(n / 2^k) nodes of level k being the zero hash of depth k, and is dirty; the child's bit clears. The node at level ceil(log2(n)), hashed with the zero hash of each depth up to the depth of the field's limit, is the root of a vector; a list's is mixed with its length. With n 0, the zero hash of the limit's depth. `count` takes n.
  - Another field: ssz_hash_tree_root of its type: an inline value (Uint64, Bytes32, JustificationBits, Fork, BeaconBlockHeader, Eth1Data, Checkpoint, SyncCommittee), or the nested value of the part of latest_execution_payload_header.
- The root is that of ssz_hash_tree_root of the state for any contents an earlier call left in the cache: the cache changes only the time.

### Function never

- Writes outside `cache`, `scratch`, `out` and its own stack.
- Makes an OS call other than through lantern_shell_pool_run, with the cache's pool.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V: it goes on to lantern_sr_root with no pool.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_state_root` in the object of every fork, with `_` before it on macOS; `lantern_state_root` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `cache`, `scratch`, `out`.

## Function `lantern_state_root_pool`

hash_tree_root(state) as lantern_state_root gives it, with the large trees hashed by jobs on a pool of threads.

### Signature

```
lantern_state_root_pool(state, cache, scratch, out, pool) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `cache` | state | `StateCache`, or 0 |
| `scratch` | scratch | `Scratch` |
| `out` | output | Bytes32 |
| `pool` | state | [`ShellPool`](shell.md#type-shellpool) of lantern_shell_pool_start, or 0 |

### Returns

- As lantern_state_root.

### Caller must

- As lantern_state_root.
- Keep `pool` free of other runs while it runs; the pool's threads read `state` and write `cache` and the end of `scratch`.

### Function does

- Gives the root, the status and the cache that lantern_state_root gives, for every pool: each tree of at least 2 x `SR_JOB_MIN` (4096) leaves is split by lantern_sr_tree into jobs on the pool.
- With `pool` 0: lantern_state_root.

### Function never

- Makes an OS call other than through lantern_shell_pool_run.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_state_root_pool` in the object of every fork, with `_` before it on macOS; `lantern_state_root_pool` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `cache`, `scratch`, `out`, `pool`.

## Function `lantern_sr_root`

lantern_state_root with a pool or none.

### Signature

```
lantern_sr_root(state, cache, scratch, out, pool) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `cache` | state | `StateCache`, or 0 |
| `scratch` | scratch | `Scratch` |
| `out` | output | Bytes32 |
| `pool` | state | `ShellPool`, or 0 |

### Returns

- As lantern_state_root.

### Function does

- The steps of lantern_state_root (Function does there); each field of a tree goes to lantern_sr_tree with `pool`.

### Function never

- Makes an OS call other than through lantern_shell_pool_run.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_root`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `cache`, `scratch`, `out`, `pool`.

## Function `lantern_sr_hash`

SHA-256 of two 32-byte nodes.

### Signature

```
lantern_sr_hash(left, right, out)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `left` | input | 32 bytes |
| `right` | input | 32 bytes |
| `out` | output | 32 bytes; it may be `left` or `right` |

### Function does

- Writes SHA-256 of the 64 bytes `left` then `right` to `out`, with crypto_sha256 of asm-crypto.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_hash`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the work area in x23, r14, s5.
- Argument order: `left`, `right`, `out`.

## Function `lantern_sr_layout`

Lays out the trees of a StateCache for a number of validators.

### Signature

```
lantern_sr_layout(validators, cache) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validators` | input | u64 in a register |
| `cache` | output | [`StateCache`](#type-statecache), or 0 |

### Function does

- Returns the bytes of the cache.
- When `cache` is not 0, writes the layout of each tree into it.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_layout`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `validators`, `cache`.

## Function `lantern_sr_tree`

The root of one field of a state, from its CacheTree, with jobs on a pool for a large tree.

### Signature

```
lantern_sr_tree(tree, data, count, bytes, descriptor, depth, list, root, pool) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `tree` | state | [`CacheTree`](#type-cachetree) |
| `data` | input | the elements |
| `count` | input | u64 in a register: the elements |
| `bytes` | input | u64 in a register: the bytes of an element of a basic type, or 0 for containers |
| `descriptor` | input | the asm-ssz type descriptor of the containers |
| `depth` | input | u64 in a register: the depth of the limit |
| `list` | input | u64 in a register: 1 for a list, whose root mixes in the count |
| `root` | output | 32 bytes |
| `pool` | state | `ShellPool`, or 0 |

### Returns

- 0: `root` holds the root.
- 1: the leaves pass the tree's capacity.
- A status of ssz_hash_tree_root of asm-ssz.

### Function does

- Hashes again only the leaves that changed and the nodes above them, and records the new leaves: lantern_sr_leaves of every leaf, lantern_sr_levels from level 0, then lantern_sr_post.
- With fewer leaves n than the tree's `count`: leaf n - 1 is dirty first.
- With a pool and n of at least 2 x `SR_JOB_MIN`: jobs of R leaves, R the larger of `SR_JOB_MIN` and the power of two at or above ceil(n / `SR_JOBS_MAX`), so at most `SR_JOBS_MAX` (64) jobs. Job j takes leaves j R to the lower of (j + 1) R and n, and levels 0 to log2(R) - 7, in a region of `SR_JOB_BYTES` (12288) bytes at the end of the scratch's front: its SrCtx, its area of zero hashes and hash input, and 7936 bytes of scratch. The ranges of the jobs at each of those levels are whole words of dirty bits apart, so no two jobs write one byte. lantern_shell_pool_run runs them; then lantern_sr_levels from level log2(R) - 6 over all leaves, then lantern_sr_post.
- No pool, fewer leaves, or a front too short for the regions: the work of one thread.
- A job that fails: lantern_sr_clean, then the work of one thread from no leaves. A failure there: lantern_sr_clean and its status.
- The root is the same for every pool and every order of the jobs.

### Function never

- Makes an OS call other than through lantern_shell_pool_run.

### Limits

- Stack of its own: 288 bytes on x86-64 (return address included), 288 bytes on ARM64, 288 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_tree`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the cache in x20, rbp, s2; the scratch, its front's size set, in x21, r12, s3; the work area in x23, r14, s5.
- On x86-64, `bytes` and `descriptor` share rcx (a descriptor is an address above 4095), and r8 holds `depth` + 256 for a list; `root` is in r9.
- `pool` is in x8, rax, t6.
- Argument order: `tree`, `data`, `count`, `bytes`, `descriptor`, `depth`, `list`, `root`, `pool`.

## Function `lantern_sr_job`

A job of lantern_sr_tree: the leaves and the lower levels of one range.

### Signature

```
lantern_sr_job(regions, index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `regions` | state | the regions of the jobs, `SR_JOB_BYTES` apart, each starting with an [`SrCtx`](#type-srctx) |
| `index` | input | u64 in a register: the job |

### Function does

- lantern_sr_leaves of its SrCtx; its status into the SrCtx's `status`; with status 0, lantern_sr_levels from level 0 to its `levels`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_job`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- A ShellJob function (shell.md): its status is not read.
- Argument order: `regions`, `index`.

## Function `lantern_sr_leaves`

The leaves lo to hi of a CacheTree: those that changed take their new chunk or root and are dirty.

### Signature

```
lantern_sr_leaves(context) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | state | [`SrCtx`](#type-srctx) |

### Returns

- 0, or a status of ssz_hash_tree_root.

### Function does

- For each leaf of the range: a chunk, the last of the field padded with zeros, or the hash tree root of an element (with the SrCtx's scratch) when its copy differs; a leaf at or past `old` always takes it. Its dirty bit sets.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_leaves`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `context`.

## Function `lantern_sr_levels`

From one level up to the SrCtx's `levels`, the parents of the dirty nodes of its range.

### Signature

```
lantern_sr_levels(context, first) -> nothing
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | state | [`SrCtx`](#type-srctx) |
| `first` | input | u64 in a register: the level to start at |

### Function does

- At each level k from `first` while the level holds more than one node and k is below `levels`: each dirty node of the words of dirty bits of lo / 2^k to hi / 2^k (rounded up) gives its parent the hash of it and its sibling, a sibling past the level being the zero hash of depth k; the parent is dirty and the word clears.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_levels`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `context`, `first`.

## Function `lantern_sr_post`

The root of a CacheTree from its top.

### Signature

```
lantern_sr_post(context) -> nothing
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | state | [`SrCtx`](#type-srctx) |

### Function does

- Clears the top's dirty bit; `out` takes the top node, or with no leaves the zero hash of the limit's depth; then hashes it with the zero hash of each depth up to the limit's; mixes in `count` for a list; the tree's `count` takes the leaves.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_post`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `context`.

## Function `lantern_sr_clean`

Empties a CacheTree after a failure.

### Signature

```
lantern_sr_clean(context) -> nothing
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `context` | state | [`SrCtx`](#type-srctx) |

### Function does

- The tree's `count` and the SrCtx's `old` take 0, and every word of dirty bits of each level takes 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_clean`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- A leaf.
- Argument order: `context`.

## Function `lantern_sr_zeros`

The zero hash of each depth from 0 to 40.

### Signature

```
lantern_sr_zeros()
```

### Function does

- Copies the zero hash of each depth 0 to 40 into the work area from `sr_zero_hashes` (include/zero_hashes.inc): depth 0 is 32 zero bytes, depth d + 1 is SHA-256 of depth d twice. The constants replace 40 SHA-256 calls of each lantern_state_root.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sr_zeros`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the work area in x23, r14, s5.

## Function `lantern_zero`

Writes zero bytes.

### Signature

```
lantern_zero(dst, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `dst` | output | `n` bytes |
| `n` | input | u64 in a register |

### Function does

- Writes `n` zero bytes at `dst`.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_zero`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1; rax, rcx, rdi; a0 to a2.
- Argument order: `dst`, `n`.

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
| 16 | `pool` | u64 | A [`ShellPool`](shell.md#type-shellpool) whose jobs hash its large trees (lantern_state_root), or 0 |
| 24 | `trees` | `CacheTree` × `STATE_CACHE_TREES` | The trees, in the order of the Rules |

### Rules

- Tree 0, validators: Validator roots, copies of 128 bytes; capacity `validators`.
- Tree 1, balances: Chunks; capacity ceil(`validators` / 4).
- Tree 2, inactivity_scores: Chunks; capacity ceil(`validators` / 4).
- Tree 3, previous_epoch_participation: Chunks; capacity ceil(`validators` / 32).
- Tree 4, current_epoch_participation: Chunks; capacity ceil(`validators` / 32).
- Tree 5, block_roots: Chunks; capacity SLOTS_PER_HISTORICAL_ROOT.
- Tree 6, state_roots: Chunks; capacity SLOTS_PER_HISTORICAL_ROOT.
- Tree 7, randao_mixes: Chunks; capacity EPOCHS_PER_HISTORICAL_VECTOR.
- Tree 8, slashings: Chunks; capacity EPOCHS_PER_SLASHINGS_VECTOR / 4.
- Tree 9, historical_roots: Chunks; capacity `STATE_CACHE_HISTORICAL_ROOTS`.
- Tree 10, eth1_data_votes: Eth1Data roots, copies of `Eth1Data__mem` bytes; capacity EPOCHS_PER_ETH1_VOTING_PERIOD * SLOTS_PER_EPOCH.
- Tree 11, historical_summaries: HistoricalSummary roots, copies of `HistoricalSummary__mem` bytes; capacity `STATE_CACHE_LIST`.
- Tree 12, pending_deposits: PendingDeposit roots, copies of `PendingDeposit__mem` bytes; capacity `STATE_CACHE_PENDING_DEPOSITS`.
- Tree 13, pending_partial_withdrawals: PendingPartialWithdrawal roots, copies of `PendingPartialWithdrawal__mem` bytes; capacity `STATE_CACHE_LIST`.
- Tree 14, pending_consolidations: PendingConsolidation roots, copies of `PendingConsolidation__mem` bytes; capacity `STATE_CACHE_LIST`.
- Tree 15, proposer_lookahead: Chunks; capacity (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH / 4.
- 24 + 48 * `STATE_CACHE_TREES` bytes of header, then the bytes of each tree.
- lantern_state_cache_init sets `pool` to 0; its owner may set it to a pool it started.
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

## Type `SrCtx`

The work of lantern_sr_tree on one tree, or of one job on a range of it.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `tree` | u64 | The CacheTree |
| 8 | `data` | u64 | The elements |
| 16 | `count` | u64 | The elements |
| 24 | `elem` | u64 | The bytes of a basic element, or 0 |
| 32 | `desc` | u64 | The type descriptor of a container element |
| 40 | `depth` | u64 | The depth of the limit |
| 48 | `list` | u64 | 1 for a list |
| 56 | `out` | u64 | The root's 32 bytes |
| 64 | `front` | u64 | The scratch size its ssz calls get |
| 72 | `bytes` | u64 | count x elem |
| 80 | `leaves` | u64 | The leaves of the tree |
| 88 | `cache` | u64 | The StateCache |
| 96 | `scratch` | u64 | Its scratch |
| 104 | `area` | u64 | Its area: the zero hashes, a hash input, a chunk |
| 112 | `status` | u64 | A job's status |
| 120 | `lo` | u64 | The first leaf of its range |
| 128 | `hi` | u64 | The leaf after its range |
| 136 | `levels` | u64 | The levels it hashes |
| 144 | `pool` | u64 | A ShellPool, or 0 |
| 152 | `old` | u64 | The tree's count before |

### Rules

- `SrCtx__mem` (160) bytes.

## Test vectors

- Each runner process keeps one `StateCache` of lantern_state_cache_size(4096) from lantern_state_cache_init, and the config of every call names it at `CONFIG_STATE_CACHE`, so each state transition of the vectors hashes through it.
- The state of each case that the runner compares with a `post` state: lantern_state_root with that cache, and with 0, must give ssz_hash_tree_root of the state. The runner counts them in a NOTE.
- Once a process, the first such state grown to 3 x 4096 + 100 validators: lantern_state_root_pool with a pool of 4 threads and a cache of its own must give ssz_hash_tree_root with the cache empty, unchanged, after changes in each grown list, and with 50 validators fewer; then lantern_state_root with that pool as the cache's `pool`, with 10 balances fewer.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_beacon_state_copy_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_beacon_state_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
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
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_state_cache_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_state_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_sr_hash`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_sr_layout`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_sr_tree`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_sr_zeros`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_zero`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
