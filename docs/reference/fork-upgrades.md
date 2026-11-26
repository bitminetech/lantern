# Fork upgrades

The upgrade of a state to each fork.

## Contents

### Functions

- [`lantern_upgrade_size`](#function-lantern_upgrade_size): the buffer size of the state that the fork's upgrade writes.
- [`lantern_upgrade_to_altair`](#function-lantern_upgrade_to_altair): a phase0 state as an altair state.
- [`lantern_translate_participation`](#function-lantern_translate_participation): the participation flags of phase0 pending attestations.
- [`lantern_upgrade_to_bellatrix`](#function-lantern_upgrade_to_bellatrix): an altair state as a bellatrix state.
- [`lantern_upgrade_to_capella`](#function-lantern_upgrade_to_capella): a bellatrix state as a capella state.
- [`lantern_upgrade_to_deneb`](#function-lantern_upgrade_to_deneb): a capella state as a deneb state.
- [`lantern_upgrade_to_electra`](#function-lantern_upgrade_to_electra): a deneb state as an electra state.
- [`lantern_upgrade_to_fulu`](#function-lantern_upgrade_to_fulu): an electra state as a fulu state.
- [`lantern_initialize_proposer_lookahead`](#function-lantern_initialize_proposer_lookahead): the proposers of the current and next epochs.
- [`lantern_sort_by_eligibility`](#function-lantern_sort_by_eligibility): sorts validator indices by activation eligibility epoch, then index.
- [`lantern_upgrade_deposit_count`](#function-lantern_upgrade_deposit_count): the pending deposits that upgrade_to_electra appends.
- [`lantern_upgrade_empty_header`](#function-lantern_upgrade_empty_header): an empty ExecutionPayloadHeader.
- [`lantern_upgrade_header`](#function-lantern_upgrade_header): the ExecutionPayloadHeader of a fork from that of the fork before.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), `fork.md` of altair, bellatrix, capella, deneb, electra and fulu.
- Section: Fork to each fork: upgrade_to_<fork> and the helpers it calls.

## Function `lantern_upgrade_size`

The bytes that lantern_upgrade_to_<fork> of the same object needs for the state it writes from pre with room.

### Signature

```
lantern_upgrade_size(pre, room, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork before |
| `room` | input | `StateRoom` |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `pre` is a valid `BeaconState` value of the fork before.
- `out` is apart from `pre`.

### Function does

- Adds the fixed part of the fork's state and, for each part, the bytes of its entries after the upgrade plus the room for its kind, rounded up to 8, as lantern_beacon_state_copy_size.
- Electra: pending_deposits holds one entry for each validator with activation_epoch FAR_FUTURE_EPOCH, and one for each other validator with a compounding credential and a balance above MIN_ACTIVATION_BALANCE.
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_upgrade_size` in the object of altair to fulu, with `_` before it on macOS; `lantern_upgrade_size` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `pre`, `room`, `size`.

## Function `lantern_upgrade_to_altair`

The altair state of a phase0 state: the shared fields, empty participation and inactivity scores, the participation of pre's previous epoch attestations, and the sync committees.

### Signature

```
lantern_upgrade_to_altair(pre, room, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of phase0 |
| `room` | input | `StateRoom` |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `BeaconState` of altair |

### Returns

- `LANTERN_OK`: `out` holds the upgraded state.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_upgrade_size gives, or `scratch` is short. Checked before `out` is written.
- The statuses of lantern_translate_participation and lantern_get_next_sync_committee.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `pre` is a valid `BeaconState` value of the fork before.
- The `size` field of `out` is its buffer size.
- `out` is apart from `pre`.

### Function does

- fork = Fork(pre.fork.current_version, ALTAIR_FORK_VERSION, the current epoch).
- Copies the fields that phase0 and altair share.
- Gives previous_epoch_participation, current_epoch_participation and inactivity_scores one zero entry for each validator.
- Calls lantern_translate_participation with pre's previous_epoch_attestations, then sets current_sync_committee and next_sync_committee each to lantern_get_next_sync_committee of `out`.
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).
- Writes into `out` a valid `BeaconState` value of its fork: the fixed part, then the parts in field order, each with the room that `room` ([`StateRoom`](state.md#type-stateroom)) gives, as lantern_beacon_state_copy does; the last part also has the rest of the buffer.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 336 bytes on ARM64, 336 bytes on RISC-V.
- Scratch: S(2) + the scratch of lantern_get_next_sync_committee.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_upgrade_to_altair` in the object of altair, with `_` before it on macOS; `lantern_upgrade_to_altair` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `pre`, `room`, `config`, `scratch`, `out`.

## Function `lantern_translate_participation`

For each pending attestation of pre's previous epoch, adds the flags of lantern_get_attestation_participation_flag_indices to the previous epoch participation of each of its attesters in state.

### Signature

```
lantern_translate_participation(state, pre, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` of altair |
| `pre` | input | `BeaconState` of phase0, whose previous_epoch_attestations are the pending attestations |
| `scratch` | scratch | `Scratch` |

### Returns

- `LANTERN_OK`: the flags are set.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.
- The statuses of lantern_get_beacon_committee and lantern_get_attestation_participation_flag_indices.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `pre` is a valid `BeaconState` value of the fork before.
- `out` is apart from `pre`.

### Function does

- Takes the attesters from the committee of each attestation's data.slot and data.index and its aggregation_bits.
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch: S(2).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_translate_participation` in the object of altair, with `_` before it on macOS; `lantern_translate_participation` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `pre`, `scratch`.

## Function `lantern_upgrade_to_bellatrix`

The bellatrix state of an altair state: the shared fields and an empty latest_execution_payload_header.

### Signature

```
lantern_upgrade_to_bellatrix(pre, room, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork before |
| `room` | input | [`StateRoom`](state.md#type-stateroom) |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | `BeaconState` of bellatrix, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the upgraded state.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_upgrade_size gives. Checked before `out` is written.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `pre` is a valid `BeaconState` value of the fork before.
- The `size` field of `out` is its buffer size.
- `out` is apart from `pre`.

### Function does

- fork = Fork(pre.fork.current_version, BELLATRIX_FORK_VERSION, the current epoch).
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).
- Writes into `out` a valid `BeaconState` value of its fork: the fixed part, then the parts in field order, each with the room that `room` ([`StateRoom`](state.md#type-stateroom)) gives, as lantern_beacon_state_copy does; the last part also has the rest of the buffer.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 336 bytes on ARM64, 336 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_upgrade_to_bellatrix` in the object of bellatrix, with `_` before it on macOS; `lantern_upgrade_to_bellatrix` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `pre`, `room`, `config`, `scratch`, `out`.

## Function `lantern_upgrade_to_capella`

The capella state of a bellatrix state: the shared fields, pre's payload header with a zero withdrawals_root, zero withdrawal indices and empty historical_summaries.

### Signature

```
lantern_upgrade_to_capella(pre, room, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork before |
| `room` | input | [`StateRoom`](state.md#type-stateroom) |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | `BeaconState` of capella, its `size` set by the caller |

### Returns

- As lantern_upgrade_to_bellatrix.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `pre` is a valid `BeaconState` value of the fork before.
- The `size` field of `out` is its buffer size.
- `out` is apart from `pre`.

### Function does

- fork = Fork(pre.fork.current_version, CAPELLA_FORK_VERSION, the current epoch).
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).
- Writes into `out` a valid `BeaconState` value of its fork: the fixed part, then the parts in field order, each with the room that `room` ([`StateRoom`](state.md#type-stateroom)) gives, as lantern_beacon_state_copy does; the last part also has the rest of the buffer.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 336 bytes on ARM64, 336 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_upgrade_to_capella` in the object of capella, with `_` before it on macOS; `lantern_upgrade_to_capella` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `pre`, `room`, `config`, `scratch`, `out`.

## Function `lantern_upgrade_to_deneb`

The deneb state of a capella state: the shared fields, and pre's payload header with zero blob_gas_used and excess_blob_gas.

### Signature

```
lantern_upgrade_to_deneb(pre, room, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork before |
| `room` | input | [`StateRoom`](state.md#type-stateroom) |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | `BeaconState` of deneb, its `size` set by the caller |

### Returns

- As lantern_upgrade_to_bellatrix.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `pre` is a valid `BeaconState` value of the fork before.
- The `size` field of `out` is its buffer size.
- `out` is apart from `pre`.

### Function does

- fork = Fork(pre.fork.current_version, DENEB_FORK_VERSION, the current epoch).
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).
- Writes into `out` a valid `BeaconState` value of its fork: the fixed part, then the parts in field order, each with the room that `room` ([`StateRoom`](state.md#type-stateroom)) gives, as lantern_beacon_state_copy does; the last part also has the rest of the buffer.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 336 bytes on ARM64, 336 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_upgrade_to_deneb` in the object of deneb, with `_` before it on macOS; `lantern_upgrade_to_deneb` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `pre`, `room`, `config`, `scratch`, `out`.

## Function `lantern_upgrade_to_electra`

The electra state of a deneb state: the shared fields, the churn fields, and pending deposits for the validators that are not active yet and for the excess balance of compounding validators.

### Signature

```
lantern_upgrade_to_electra(pre, room, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork before |
| `room` | input | [`StateRoom`](state.md#type-stateroom) |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | `BeaconState` of electra, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the upgraded state.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_upgrade_size gives, or `scratch` is short. Checked before `out` is written.
- The statuses of the churn limit functions and lantern_queue_excess_active_balance.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `pre` is a valid `BeaconState` value of the fork before.
- The `size` field of `out` is its buffer size.
- `out` is apart from `pre`.

### Function does

- fork = Fork(pre.fork.current_version, ELECTRA_FORK_VERSION, the current epoch).
- earliest_exit_epoch = max(compute_activation_exit_epoch(epoch), each exit_epoch other than FAR_FUTURE_EPOCH) + 1; earliest_consolidation_epoch = compute_activation_exit_epoch(epoch); deposit_requests_start_index = UNSET_DEPOSIT_REQUESTS_START_INDEX.
- exit_balance_to_consume = lantern_get_activation_exit_churn_limit; consolidation_balance_to_consume = lantern_get_consolidation_churn_limit, of `out`.
- In the order of (activation_eligibility_epoch, index), each validator with activation_epoch FAR_FUTURE_EPOCH gets balance 0, effective_balance 0 and activation_eligibility_epoch FAR_FUTURE_EPOCH, and its balance goes to a PendingDeposit with its pubkey and credentials, the G2 point at infinity as signature and GENESIS_SLOT.
- Then lantern_queue_excess_active_balance for each validator with a compounding credential, in index order.
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).
- Writes into `out` a valid `BeaconState` value of its fork: the fixed part, then the parts in field order, each with the room that `room` ([`StateRoom`](state.md#type-stateroom)) gives, as lantern_beacon_state_copy does; the last part also has the rest of the buffer.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 336 bytes on ARM64, 336 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_upgrade_to_electra` in the object of electra, with `_` before it on macOS; `lantern_upgrade_to_electra` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `pre`, `room`, `config`, `scratch`, `out`.

## Function `lantern_upgrade_to_fulu`

The fulu state of an electra state: the shared fields and proposer_lookahead from lantern_initialize_proposer_lookahead.

### Signature

```
lantern_upgrade_to_fulu(pre, room, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork before |
| `room` | input | [`StateRoom`](state.md#type-stateroom) |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | `BeaconState` of fulu, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the upgraded state.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_upgrade_size gives, or `scratch` is short. Checked before `out` is written.
- The statuses of lantern_initialize_proposer_lookahead.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `pre` is a valid `BeaconState` value of the fork before.
- The `size` field of `out` is its buffer size.
- `out` is apart from `pre`.

### Function does

- fork = Fork(pre.fork.current_version, FULU_FORK_VERSION, the current epoch).
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).
- Writes into `out` a valid `BeaconState` value of its fork: the fixed part, then the parts in field order, each with the room that `room` ([`StateRoom`](state.md#type-stateroom)) gives, as lantern_beacon_state_copy does; the last part also has the rest of the buffer.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 336 bytes on ARM64, 336 bytes on RISC-V.
- Scratch: the scratch of lantern_initialize_proposer_lookahead.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_upgrade_to_fulu` in the object of fulu, with `_` before it on macOS; `lantern_upgrade_to_fulu` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `pre`, `room`, `config`, `scratch`, `out`.

## Function `lantern_initialize_proposer_lookahead`

The proposers of each slot of the current epoch and the MIN_SEED_LOOKAHEAD epochs after it, from lantern_get_beacon_proposer_indices.

### Signature

```
lantern_initialize_proposer_lookahead(state, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of fulu |
| `scratch` | scratch | `Scratch` |
| `out` | output | `ProposerLookahead`: (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH validator indices |

### Returns

- `LANTERN_OK`: `out` holds the lookahead.
- The statuses of lantern_get_beacon_proposer_indices.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- The `size` field of `out` is its buffer size.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: the scratch of lantern_get_beacon_proposer_indices.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_initialize_proposer_lookahead` in the object of fulu, with `_` before it on macOS; `lantern_initialize_proposer_lookahead` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `out`.

## Function `lantern_sort_by_eligibility`

Sorts validator indices by activation eligibility epoch, then index.

### Signature

```
lantern_sort_by_eligibility(indices, n, validators)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `indices` | state | `n` u64 validator indices |
| `n` | input | u64 in a register |
| `validators` | input | the validators of the state |

### Function does

- Sorts the indices by (activation_eligibility_epoch, index), with heapsort.

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sort_by_eligibility`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `indices`, `n`, `validators`.

## Function `lantern_upgrade_deposit_count`

The pending deposits that upgrade_to_electra appends.

### Signature

```
lantern_upgrade_deposit_count(pre) -> count
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of deneb |

### Caller must

- `pre` is a valid `BeaconState` value of the fork before.
- `out` is apart from `pre`.

### Function does

- Returns the pending deposits that upgrade_to_electra appends for `pre`.
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_upgrade_deposit_count`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64: x0 to x8.
- Argument order: `pre`.

## Function `lantern_upgrade_empty_header`

An empty ExecutionPayloadHeader.

### Signature

```
lantern_upgrade_empty_header(header)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | output | `ExecutionPayloadHeader` of bellatrix |

### Function does

- Writes ExecutionPayloadHeader(): every field zero, and an empty extra_data.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_upgrade_empty_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `header`.

## Function `lantern_upgrade_header`

The ExecutionPayloadHeader of a fork from that of the fork before.

### Signature

```
lantern_upgrade_header(header, pre)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | output | `ExecutionPayloadHeader` of the object's fork |
| `pre` | input | `ExecutionPayloadHeader` of the fork before |

### Caller must

- `pre` is a valid `BeaconState` value of the fork before.
- `out` is apart from `pre`.

### Function does

- Copies the fields of `pre` and its extra_data; the fields the fork adds are zero.
- Reads `pre` with the layouts of the fork before: include/types.inc of that fork, each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.
- Changes `pre`.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 48 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_upgrade_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `header`, `pre`.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/fork/fork/` of altair to fulu, for mainnet and minimal: `pre` in the fork before, `post` in the fork.
- `tests/<preset>/<fork>/transition/core/`: blocks across `fork_epoch`. The runner applies the blocks up to `fork_block` with the fork before, then lantern_process_slots of the fork before to the first slot of `fork_epoch`, then lantern_upgrade_to_<fork>, then the other blocks with the fork.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.
  - Cases with `bls_setting` 2 run in `runner-<preset>-<fork>-bls-off`, as in block-processing.md.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_upgrade_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_upgrade_to_altair`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_translate_participation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_to_bellatrix`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_upgrade_to_capella`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_upgrade_to_deneb`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_upgrade_to_electra`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_upgrade_to_fulu`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_initialize_proposer_lookahead`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_sort_by_eligibility`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_deposit_count`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_empty_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
