# Fork upgrades

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

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), `fork.md` of altair, bellatrix, capella, deneb, electra and fulu.
- Section: Fork to each fork: upgrade_to_<fork> and the helpers it calls.

## Common rules

- As in [block-processing.md](block-processing.md#common-rules).
- `pre` is a valid `BeaconState` value of the fork before; `out` gets a valid `BeaconState` value of the function's fork.
- The object of a fork reads `pre` with the layouts of the fork before: include/types.inc for that fork, with each type name under the prefix `PRE_` (include/ssz_types.inc, `SSZ_NAMES`).
- `out` holds the fixed part, then the parts in field order, each with the room that `room` ([`StateRoom`](state.md#type-stateroom)) gives as in lantern_beacon_state_copy; the last part also has the rest of the buffer.
- The caller sets the `size` field of `out` to its buffer size, and keeps `pre` and `out` apart.
- An upgrade changes nothing in `pre`.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/fork/fork/` of altair to fulu, for mainnet and minimal: `pre` in the fork before, `post` in the fork.
- `tests/<preset>/<fork>/transition/core/`: blocks across `fork_epoch`. The runner applies the blocks up to `fork_block` with the fork before, then lantern_process_slots of the fork before to the first slot of `fork_epoch`, then lantern_upgrade_to_<fork>, then the other blocks with the fork.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.
  - Cases with `bls_setting` 2 run in `runner-<preset>-<fork>-bls-off`, as in block-processing.md.

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

### Function does

- Adds the fixed part of the fork's state and, for each part, the bytes of its entries after the upgrade plus the room for its kind, rounded up to 8, as lantern_beacon_state_copy_size.
- Electra: pending_deposits holds one entry for each validator with activation_epoch FAR_FUTURE_EPOCH, and one for each other validator with a compounding credential and a balance above MIN_ACTIVATION_BALANCE.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_upgrade_size`, as in [helpers.md](helpers.md#common-rules).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `pre`, `room`, `size`.
- Forks: altair and later.

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

### Function does

- fork = Fork(pre.fork.current_version, ALTAIR_FORK_VERSION, the current epoch).
- Copies the fields that phase0 and altair share.
- Gives previous_epoch_participation, current_epoch_participation and inactivity_scores one zero entry for each validator.
- Calls lantern_translate_participation with pre's previous_epoch_attestations, then sets current_sync_committee and next_sync_committee each to lantern_get_next_sync_committee of `out`.

### Limits

- Scratch: S(2) + the scratch of lantern_get_next_sync_committee.

### ABI

- Forks: altair.

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

### Function does

- Takes the attesters from the committee of each attestation's data.slot and data.index and its aggregation_bits.

### Limits

- Scratch: S(2).

### ABI

- Forks: altair.

## Function `lantern_upgrade_to_bellatrix`

The bellatrix state of an altair state: the shared fields and an empty latest_execution_payload_header.

### Signature

```
lantern_upgrade_to_bellatrix(pre, room, config, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the upgraded state.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_upgrade_size gives. Checked before `out` is written.

### Function does

- fork = Fork(pre.fork.current_version, BELLATRIX_FORK_VERSION, the current epoch).

### Limits

- Scratch: S(0).

### ABI

- Forks: bellatrix.

## Function `lantern_upgrade_to_capella`

The capella state of a bellatrix state: the shared fields, pre's payload header with a zero withdrawals_root, zero withdrawal indices and empty historical_summaries.

### Signature

```
lantern_upgrade_to_capella(pre, room, config, scratch, out) -> status
```

### Returns

- As lantern_upgrade_to_bellatrix.

### Function does

- fork = Fork(pre.fork.current_version, CAPELLA_FORK_VERSION, the current epoch).

### Limits

- Scratch: S(0).

### ABI

- Forks: capella.

## Function `lantern_upgrade_to_deneb`

The deneb state of a capella state: the shared fields, and pre's payload header with zero blob_gas_used and excess_blob_gas.

### Signature

```
lantern_upgrade_to_deneb(pre, room, config, scratch, out) -> status
```

### Returns

- As lantern_upgrade_to_bellatrix.

### Function does

- fork = Fork(pre.fork.current_version, DENEB_FORK_VERSION, the current epoch).

### Limits

- Scratch: S(0).

### ABI

- Forks: deneb.

## Function `lantern_upgrade_to_electra`

The electra state of a deneb state: the shared fields, the churn fields, and pending deposits for the validators that are not active yet and for the excess balance of compounding validators.

### Signature

```
lantern_upgrade_to_electra(pre, room, config, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the upgraded state.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_upgrade_size gives, or `scratch` is short. Checked before `out` is written.
- The statuses of the churn limit functions and lantern_queue_excess_active_balance.

### Function does

- fork = Fork(pre.fork.current_version, ELECTRA_FORK_VERSION, the current epoch).
- earliest_exit_epoch = max(compute_activation_exit_epoch(epoch), each exit_epoch other than FAR_FUTURE_EPOCH) + 1; earliest_consolidation_epoch = compute_activation_exit_epoch(epoch); deposit_requests_start_index = UNSET_DEPOSIT_REQUESTS_START_INDEX.
- exit_balance_to_consume = lantern_get_activation_exit_churn_limit; consolidation_balance_to_consume = lantern_get_consolidation_churn_limit, of `out`.
- In the order of (activation_eligibility_epoch, index), each validator with activation_epoch FAR_FUTURE_EPOCH gets balance 0, effective_balance 0 and activation_eligibility_epoch FAR_FUTURE_EPOCH, and its balance goes to a PendingDeposit with its pubkey and credentials, the G2 point at infinity as signature and GENESIS_SLOT.
- Then lantern_queue_excess_active_balance for each validator with a compounding credential, in index order.

### Limits

- Scratch: S(1).

### ABI

- Forks: electra.

## Function `lantern_upgrade_to_fulu`

The fulu state of an electra state: the shared fields and proposer_lookahead from lantern_initialize_proposer_lookahead.

### Signature

```
lantern_upgrade_to_fulu(pre, room, config, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the upgraded state.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_upgrade_size gives, or `scratch` is short. Checked before `out` is written.
- The statuses of lantern_initialize_proposer_lookahead.

### Function does

- fork = Fork(pre.fork.current_version, FULU_FORK_VERSION, the current epoch).

### Limits

- Scratch: the scratch of lantern_initialize_proposer_lookahead.

### ABI

- Forks: fulu.

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

### Limits

- Scratch: the scratch of lantern_get_beacon_proposer_indices.

### ABI

- Forks: fulu.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_upgrade_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_to_altair`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_translate_participation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_to_bellatrix`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_to_capella`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_to_deneb`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_to_electra`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_upgrade_to_fulu`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_initialize_proposer_lookahead`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
