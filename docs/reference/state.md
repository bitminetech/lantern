# Beacon state buffers

## Contents

### Functions

- [`lantern_beacon_state_copy_size`](#function-lantern_beacon_state_copy_size): the buffer size of a copy of a state with room.
- [`lantern_beacon_state_copy`](#function-lantern_beacon_state_copy): copies a state into a new buffer with room in its lists.
- [`lantern_copy`](#function-lantern_copy): copies bytes.

### Types

- [`StateRoom`](#type-stateroom): the free entries a copy gives each list of the state.

## Spec

- Document: ARCHITECTURE.md section 6, "Memory preparation": the resize function of a type.
- Section: lantern's own functions. The state transition appends to the lists of a `BeaconState` within the room of their parts.

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

- Adds the fixed part of the state and, for each of its 12 parts, the bytes of its entries plus the room for its kind, rounded up to 8.
- Gives the part of `latest_execution_payload_header` room for an `extra_data` of MAX_EXTRA_DATA_BYTES.

### ABI

- Role: L1.
- Symbol: `lantern_beacon_state_copy_size`.
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
- Symbol: `lantern_beacon_state_copy`.
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
- Symbol: `lantern_copy`.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). It returns no status.
- Argument order: `dst`, `src`, `n`.

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

### Rules

- 48 bytes.
- historical_roots gets no room: no fork after capella appends to it.

## Results

<!-- CI generates the tick table for each function here. -->
