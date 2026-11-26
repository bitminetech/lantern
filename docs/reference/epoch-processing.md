# Epoch processing

## Contents

### Functions

- [`lantern_process_justification_and_finalization`](#function-lantern_process_justification_and_finalization): justifies and finalizes checkpoints.
- [`lantern_get_matching_source_attestations`](#function-lantern_get_matching_source_attestations): the pending attestations of an epoch.
- [`lantern_get_matching_target_attestations`](#function-lantern_get_matching_target_attestations): those that vote for the epoch's target.
- [`lantern_get_matching_head_attestations`](#function-lantern_get_matching_head_attestations): those that also vote for the head.
- [`lantern_get_unslashed_attesting_indices`](#function-lantern_get_unslashed_attesting_indices): the unslashed validators of a set of pending attestations.
- [`lantern_get_attesting_balance`](#function-lantern_get_attesting_balance): their total effective balance.
- [`lantern_weigh_justification_and_finalization`](#function-lantern_weigh_justification_and_finalization): the checkpoint updates for given target balances.
- [`lantern_process_inactivity_updates`](#function-lantern_process_inactivity_updates): updates inactivity scores.
- [`lantern_process_rewards_and_penalties`](#function-lantern_process_rewards_and_penalties): applies the rewards and penalties of the previous epoch.
- [`lantern_get_flag_index_deltas`](#function-lantern_get_flag_index_deltas): the rewards and penalties of one participation flag.
- [`lantern_get_inactivity_penalty_deltas`](#function-lantern_get_inactivity_penalty_deltas): the inactivity penalties.
- [`lantern_get_proposer_reward`](#function-lantern_get_proposer_reward): the proposer's share of an attester's base reward.
- [`lantern_get_attestation_component_deltas`](#function-lantern_get_attestation_component_deltas): the deltas of one set of matching attestations.
- [`lantern_get_source_deltas`](#function-lantern_get_source_deltas): the deltas of the source votes.
- [`lantern_get_target_deltas`](#function-lantern_get_target_deltas): the deltas of the target votes.
- [`lantern_get_head_deltas`](#function-lantern_get_head_deltas): the deltas of the head votes.
- [`lantern_get_inclusion_delay_deltas`](#function-lantern_get_inclusion_delay_deltas): the rewards for early inclusion.
- [`lantern_get_attestation_deltas`](#function-lantern_get_attestation_deltas): all of phase0's attestation deltas.
- [`lantern_process_registry_updates`](#function-lantern_process_registry_updates): queues, ejects and activates validators.
- [`lantern_process_slashings`](#function-lantern_process_slashings): applies the correlated slashing penalties.
- [`lantern_process_eth1_data_reset`](#function-lantern_process_eth1_data_reset): clears the eth1 votes at the end of a voting period.
- [`lantern_process_pending_consolidations`](#function-lantern_process_pending_consolidations): moves balances of finished consolidations.
- [`lantern_process_effective_balance_updates`](#function-lantern_process_effective_balance_updates): updates effective balances with hysteresis.
- [`lantern_process_slashings_reset`](#function-lantern_process_slashings_reset): clears the next slashings entry.
- [`lantern_process_randao_mixes_reset`](#function-lantern_process_randao_mixes_reset): carries the RANDAO mix into the next epoch.
- [`lantern_process_historical_roots_update`](#function-lantern_process_historical_roots_update): appends a historical batch root.
- [`lantern_process_historical_summaries_update`](#function-lantern_process_historical_summaries_update): appends a historical summary.
- [`lantern_process_participation_flag_updates`](#function-lantern_process_participation_flag_updates): rotates the participation flags.
- [`lantern_process_participation_record_updates`](#function-lantern_process_participation_record_updates): rotates the pending attestations.
- [`lantern_initiate_validator_exit`](#function-lantern_initiate_validator_exit): starts the exit of a validator.
- [`lantern_get_validator_churn_limit`](#function-lantern_get_validator_churn_limit): the validators that may activate or exit in an epoch.
- [`lantern_get_validator_activation_churn_limit`](#function-lantern_get_validator_activation_churn_limit): the validators that may activate in a deneb epoch.
- [`lantern_compute_exit_epoch_and_update_churn`](#function-lantern_compute_exit_epoch_and_update_churn): the exit epoch for a balance, and the churn update.
- [`lantern_get_balance_churn_limit`](#function-lantern_get_balance_churn_limit): the balance churn limit.
- [`lantern_get_activation_exit_churn_limit`](#function-lantern_get_activation_exit_churn_limit): the churn limit of activations and exits.
- [`lantern_get_consolidation_churn_limit`](#function-lantern_get_consolidation_churn_limit): the churn limit of consolidations.
- [`lantern_process_pending_deposits`](#function-lantern_process_pending_deposits): applies the pending deposits that the churn allows.
- [`lantern_apply_pending_deposit`](#function-lantern_apply_pending_deposit): credits a deposit, or adds a validator for it.
- [`lantern_is_valid_deposit_signature`](#function-lantern_is_valid_deposit_signature): checks the proof of possession of a deposit.
- [`lantern_add_validator_to_registry`](#function-lantern_add_validator_to_registry): appends a new validator.
- [`lantern_get_validator_from_deposit`](#function-lantern_get_validator_from_deposit): the validator record of a deposit.
- [`lantern_get_index_for_new_validator`](#function-lantern_get_index_for_new_validator): the index of the next validator.
- [`lantern_set_or_append_list`](#function-lantern_set_or_append_list): sets or appends a list entry of the state.
- [`lantern_process_sync_committee_updates`](#function-lantern_process_sync_committee_updates): rotates the sync committees.
- [`lantern_get_next_sync_committee`](#function-lantern_get_next_sync_committee): the next sync committee.
- [`lantern_get_next_sync_committee_indices`](#function-lantern_get_next_sync_committee_indices): the members of the next sync committee.
- [`lantern_process_proposer_lookahead`](#function-lantern_process_proposer_lookahead): shifts the proposer lookahead by an epoch.
- [`lantern_process_epoch`](#function-lantern_process_epoch): every epoch step, in spec order.
- [`lantern_add_deltas`](#function-lantern_add_deltas): adds the entries of one list to those of another.
- [`lantern_record_room`](#function-lantern_record_room): whether previous_epoch_attestations can take the current ones.
- [`lantern_zero_deltas`](#function-lantern_zero_deltas): sets the count of an output IndexList and zeros its entries.

### Types

- [`PartSpec`](#type-partspec): where a list of the state is.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), each function at its definition in the fork of its object (include/forks.inc).
- Section: Epoch processing of `beacon-chain.md` in phase0, altair, bellatrix, capella, electra and fulu, and the electra helpers it calls.
- A list of matching attestations is an [`IndexList`](helpers.md#type-indexlist) of the offsets of PendingAttestation values from the start of the state, in the order of the state's list.
- The phase0 functions that read pending attestations take S(k) plus 24 + 8 * MAX_ATTESTATIONS * SLOTS_PER_EPOCH bytes, the matching attestations of one epoch, at the end of their scratch.

## Function `lantern_process_justification_and_finalization`

Does nothing in the first two epochs; else weighs the target balances of the previous and current epochs.

### Signature

```
lantern_process_justification_and_finalization(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of lantern_get_block_root.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Phase0: the target balances are lantern_get_attesting_balance of lantern_get_matching_target_attestations of each epoch.
- Altair and later: the total balances of the unslashed participating indices of the timely target flag.
- Altair and later: one pass over the validators sums the total active balance and both target balances, with get_unslashed_participating_indices, get_total_active_balance and get_total_balance inline; each sum is at least EFFECTIVE_BALANCE_INCREMENT, as in get_total_balance.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(3).
- Phase0: scratch S(6) and the matching attestations.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_justification_and_finalization` in the object of every fork, with `_` before it on macOS; `lantern_process_justification_and_finalization` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_get_matching_source_attestations`

The pending attestations of epoch: current_epoch_attestations when epoch is the current epoch, else previous_epoch_attestations.

### Signature

```
lantern_get_matching_source_attestations(state, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `out` | output | `IndexList` of offsets of PendingAttestation values |

### Returns

- `LANTERN_OK`: `out` holds the attestations.
- `LANTERN_INVALID_PARTICIPATION_EPOCH`: epoch is neither the previous nor the current epoch.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has no room for the list's entries.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_matching_source_attestations` in the object of phase0, with `_` before it on macOS; `lantern_get_matching_source_attestations` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `epoch`, `out`.

## Function `lantern_get_matching_target_attestations`

The matching source attestations of epoch whose target root is get_block_root of epoch.

### Signature

```
lantern_get_matching_target_attestations(state, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `out` | output | [`IndexList`](helpers.md#type-indexlist) of offsets of PendingAttestation values |

### Returns

- `LANTERN_OK`: `out` holds the attestations.
- The statuses of lantern_get_matching_source_attestations and lantern_get_block_root.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function does

- Reads the block root only when a source attestation exists, as the spec's list comprehension does.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_matching_target_attestations` in the object of phase0, with `_` before it on macOS; `lantern_get_matching_target_attestations` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `epoch`, `out`.

## Function `lantern_get_matching_head_attestations`

The matching target attestations of epoch whose beacon_block_root is get_block_root_at_slot of their slot.

### Signature

```
lantern_get_matching_head_attestations(state, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `out` | output | [`IndexList`](helpers.md#type-indexlist) of offsets of PendingAttestation values |

### Returns

- `LANTERN_OK`: `out` holds the attestations.
- The statuses of lantern_get_matching_target_attestations and lantern_get_block_root_at_slot.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_matching_head_attestations` in the object of phase0, with `_` before it on macOS; `lantern_get_matching_head_attestations` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `epoch`, `out`.

## Function `lantern_get_unslashed_attesting_indices`

The union of the attesting indices of the attestations, without slashed validators, in ascending order.

### Signature

```
lantern_get_unslashed_attesting_indices(state, attestations, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `attestations` | input | `IndexList` of offsets of PendingAttestation values |
| `scratch` | scratch | `Scratch` |
| `out` | output | `IndexList` with room for every validator |

### Returns

- `LANTERN_OK`: `out` holds the indices.
- `LANTERN_INVALID_ATTESTATION`: an attestation has fewer aggregation bits than its committee.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` or `out` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(5).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_unslashed_attesting_indices` in the object of phase0, with `_` before it on macOS; `lantern_get_unslashed_attesting_indices` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `attestations`, `scratch`, `out`.

## Function `lantern_get_attesting_balance`

lantern_get_total_balance of the unslashed attesting indices of the attestations.

### Signature

```
lantern_get_attesting_balance(state, attestations, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `attestations` | input | [`IndexList`](helpers.md#type-indexlist) of offsets of PendingAttestation values |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the balance.
- The statuses of lantern_get_unslashed_attesting_indices.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(6).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_attesting_balance` in the object of phase0, with `_` before it on macOS; `lantern_get_attesting_balance` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `attestations`, `scratch`, `out`.

## Function `lantern_weigh_justification_and_finalization`

Shifts the justification bits, justifies the previous or current epoch when its target balance is two thirds of the total, and finalizes by the four spec rules.

### Signature

```
lantern_weigh_justification_and_finalization(state, total_active_balance, previous_epoch_target_balance, current_epoch_target_balance, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `total_active_balance` | input | u64 |
| `previous_epoch_target_balance` | input | u64 |
| `current_epoch_target_balance` | input | u64 |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of lantern_get_block_root.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 256 bytes on x86-64 (return address included), 256 bytes on ARM64, 256 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_weigh_justification_and_finalization` in the object of every fork, with `_` before it on macOS; `lantern_weigh_justification_and_finalization` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `total_active_balance`, `previous_epoch_target_balance`, `current_epoch_target_balance`, `result`.

## Function `lantern_process_inactivity_updates`

In each epoch after the first, lowers the score of each eligible validator that hit the previous target and raises the others by INACTIVITY_SCORE_BIAS; outside a leak, also lowers each by INACTIVITY_SCORE_RECOVERY_RATE.

### Signature

```
lantern_process_inactivity_updates(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- One pass over the validators, with get_eligible_validator_indices and get_unslashed_participating_indices of the target flag inline: each score changes only for its own validator, so the order of the spec's loop over the eligible indices gives the same scores.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.
- Scratch: S(3).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_inactivity_updates` in the object of altair to fulu, with `_` before it on macOS; `lantern_process_inactivity_updates` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_rewards_and_penalties`

In each epoch after the first, computes the deltas of the three flags and of inactivity, then applies each.

### Signature

```
lantern_process_rewards_and_penalties(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Phase0: increases each balance by its reward and then decreases it by its penalty of lantern_get_attestation_deltas.
- Altair and later: runs get_flag_index_deltas and get_inactivity_penalty_deltas inline, in two passes over the validators.
- Pass 1 sums the effective balances of the validators active in the current epoch, and for each flag those of the validators active in the previous epoch, not slashed, with the flag in previous_epoch_participation; each sum is at least EFFECTIVE_BALANCE_INCREMENT, as in get_total_balance.
- Pass 2 changes the balance of each eligible validator: each flag's reward or penalty in flag order, then the inactivity penalty. Each delta changes only its own validator's balance, so this gives the balances of the spec's loops.
- A flag's reward is base_reward * (weight * unslashed_participating_increments) // (active_increments * WEIGHT_DENOMINATOR): the product of get_flag_index_deltas, since u64 multiplication is associative.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 208 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(11).
- Phase0: scratch S(13) and the matching attestations.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_rewards_and_penalties` in the object of every fork, with `_` before it on macOS; `lantern_process_rewards_and_penalties` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_get_flag_index_deltas`

The rewards and penalties of each validator for flag_index in the previous epoch.

### Signature

```
lantern_get_flag_index_deltas(state, flag_index, scratch, rewards, penalties) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `flag_index` | input | u64, below 3 |
| `scratch` | scratch | `Scratch` |
| `rewards` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |
| `penalties` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |

### Returns

- `LANTERN_OK`: the outputs hold the deltas.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short, or an output has room for fewer entries than there are validators.
- A `LANTERN_INVALID_*` code: a spec check of a callee failed.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 208 bytes on x86-64 (return address included), 208 bytes on ARM64, 208 bytes on RISC-V.
- Scratch: S(3).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_flag_index_deltas` in the object of altair to fulu, with `_` before it on macOS; `lantern_get_flag_index_deltas` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `flag_index`, `scratch`, `rewards`, `penalties`.

## Function `lantern_get_inactivity_penalty_deltas`

The inactivity penalty of each eligible validator that missed the previous target; rewards are 0.

### Signature

```
lantern_get_inactivity_penalty_deltas(state, config, scratch, rewards, penalties) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `rewards` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |
| `penalties` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |

### Returns

- `LANTERN_OK`: the outputs hold the deltas.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short, or an output has room for fewer entries than there are validators.
- A `LANTERN_INVALID_*` code: a spec check of a callee failed.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Phase0: in an inactivity leak, each eligible validator pays BASE_REWARDS_PER_EPOCH base rewards minus a proposer reward, and one that is no unslashed target attester also its effective balance times the finality delay // INACTIVITY_PENALTY_QUOTIENT.
- The quotient is INACTIVITY_PENALTY_QUOTIENT in phase0, _ALTAIR in altair, and _BELLATRIX from bellatrix on.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch: S(3).
- Phase0: scratch S(7) and the matching attestations.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_inactivity_penalty_deltas` in the object of every fork, with `_` before it on macOS; `lantern_get_inactivity_penalty_deltas` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `rewards`, `penalties`.

## Function `lantern_get_proposer_reward`

lantern_get_base_reward of the attester // PROPOSER_REWARD_QUOTIENT.

### Signature

```
lantern_get_proposer_reward(state, attesting_index, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `attesting_index` | input | u64 |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the reward.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(1) bytes.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_proposer_reward` in the object of phase0, with `_` before it on macOS; `lantern_get_proposer_reward` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `attesting_index`, `scratch`, `out`.

## Function `lantern_get_attestation_component_deltas`

For each eligible validator: a reward when it is an unslashed attester of the attestations, else a penalty of its base reward.

### Signature

```
lantern_get_attestation_component_deltas(state, attestations, scratch, rewards, penalties) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `attestations` | input | [`IndexList`](helpers.md#type-indexlist) of offsets of PendingAttestation values |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `rewards` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |
| `penalties` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |

### Returns

- `LANTERN_OK`: `rewards` and `penalties` hold one entry per validator.
- `LANTERN_INVALID_OVERFLOW`: a sum leaves the u64 range.
- The statuses of lantern_get_unslashed_attesting_indices and lantern_get_eligible_validator_indices.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Rewards the full base reward in an inactivity leak, else base_reward * (attesting balance // increment) // (total balance // increment).
- Computes the base reward of each validator from one total active balance, the value the spec's cached get_base_reward reads.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(7).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_attestation_component_deltas` in the object of phase0, with `_` before it on macOS; `lantern_get_attestation_component_deltas` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `attestations`, `scratch`, `rewards`, `penalties`.

## Function `lantern_get_source_deltas`

lantern_get_attestation_component_deltas of the matching source attestations of the previous epoch.

### Signature

```
lantern_get_source_deltas(state, scratch, rewards, penalties) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `rewards` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |
| `penalties` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |

### Returns

- `LANTERN_OK`: `rewards` and `penalties` hold one entry per validator.
- The statuses of lantern_get_matching_source_attestations and lantern_get_attestation_component_deltas.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(7) and the matching attestations.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_source_deltas` in the object of phase0, with `_` before it on macOS; `lantern_get_source_deltas` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `rewards`, `penalties`.

## Function `lantern_get_target_deltas`

lantern_get_attestation_component_deltas of the matching target attestations of the previous epoch.

### Signature

```
lantern_get_target_deltas(state, scratch, rewards, penalties) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `rewards` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |
| `penalties` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |

### Returns

- `LANTERN_OK`: `rewards` and `penalties` hold one entry per validator.
- The statuses of lantern_get_matching_target_attestations and lantern_get_attestation_component_deltas.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(7) and the matching attestations.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_target_deltas` in the object of phase0, with `_` before it on macOS; `lantern_get_target_deltas` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `rewards`, `penalties`.

## Function `lantern_get_head_deltas`

lantern_get_attestation_component_deltas of the matching head attestations of the previous epoch.

### Signature

```
lantern_get_head_deltas(state, scratch, rewards, penalties) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `rewards` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |
| `penalties` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |

### Returns

- `LANTERN_OK`: `rewards` and `penalties` hold one entry per validator.
- The statuses of lantern_get_matching_head_attestations and lantern_get_attestation_component_deltas.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(7) and the matching attestations.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_head_deltas` in the object of phase0, with `_` before it on macOS; `lantern_get_head_deltas` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `rewards`, `penalties`.

## Function `lantern_get_inclusion_delay_deltas`

For each unslashed source attester: its earliest attestation gives the proposer a proposer reward and the attester the rest of its base reward // the inclusion delay.

### Signature

```
lantern_get_inclusion_delay_deltas(state, scratch, rewards, penalties) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `rewards` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |
| `penalties` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |

### Returns

- `LANTERN_OK`: `rewards` holds the rewards; `penalties` is all zero.
- `LANTERN_INVALID_OVERFLOW`: a sum leaves the u64 range, or an inclusion delay is 0.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Of the attestations with the smallest delay, takes the first in list order, as the spec's min does.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch: S(9) and the matching attestations.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_inclusion_delay_deltas` in the object of phase0, with `_` before it on macOS; `lantern_get_inclusion_delay_deltas` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `rewards`, `penalties`.

## Function `lantern_get_attestation_deltas`

The sums of the source, target, head and inclusion delay rewards, and of the source, target, head and inactivity penalties.

### Signature

```
lantern_get_attestation_deltas(state, config, scratch, rewards, penalties) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `rewards` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |
| `penalties` | output | [`IndexList`](helpers.md#type-indexlist) of one entry per validator |

### Returns

- `LANTERN_OK`: `rewards` and `penalties` hold the sums.
- `LANTERN_INVALID_OVERFLOW`: a sum leaves the u64 range.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(11) and the matching attestations.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_attestation_deltas` in the object of phase0, with `_` before it on macOS; `lantern_get_attestation_deltas` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `rewards`, `penalties`.

## Function `lantern_process_registry_updates`

For each validator: queues it for activation, or ejects it when active with an effective balance at most EJECTION_BALANCE, or activates it when eligible.

### Signature

```
lantern_process_registry_updates(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of lantern_initiate_validator_exit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Before electra: queues and ejects in one pass over the validators, then activates the queue in order of (activation_eligibility_epoch, index), up to lantern_get_validator_churn_limit.
- Electra and later: activates each eligible validator.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_registry_updates` in the object of every fork, with `_` before it on macOS; `lantern_process_registry_updates` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_slashings`

Penalizes each slashed validator half way to its withdrawable epoch in proportion to the recent slashings.

### Signature

```
lantern_process_slashings(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- The multiplier is PROPORTIONAL_SLASHING_MULTIPLIER in phase0, _ALTAIR in altair, and _BELLATRIX from bellatrix on.
- Before electra: the penalty is effective_balance // increment * adjusted total // total balance * increment.
- Electra and later: the penalty is the penalty per increment times the increments of the effective balance.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_slashings` in the object of every fork, with `_` before it on macOS; `lantern_process_slashings` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_eth1_data_reset`

Empties eth1_data_votes when the next epoch starts a voting period.

### Signature

```
lantern_process_eth1_data_reset(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_eth1_data_reset` in the object of every fork, with `_` before it on macOS; `lantern_process_eth1_data_reset` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_pending_consolidations`

Moves the balance of each pending consolidation whose source is withdrawable to its target, skips slashed sources, and drops the processed entries.

### Signature

```
lantern_process_pending_consolidations(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_pending_consolidations` in the object of electra to fulu, with `_` before it on macOS; `lantern_process_pending_consolidations` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_effective_balance_updates`

Sets the effective balance of each validator whose balance left the hysteresis band.

### Signature

```
lantern_process_effective_balance_updates(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- The cap is MAX_EFFECTIVE_BALANCE before electra, and lantern_get_max_effective_balance of the validator from electra on.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_effective_balance_updates` in the object of every fork, with `_` before it on macOS; `lantern_process_effective_balance_updates` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_slashings_reset`

Sets the slashings entry of the next epoch to 0.

### Signature

```
lantern_process_slashings_reset(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_slashings_reset` in the object of every fork, with `_` before it on macOS; `lantern_process_slashings_reset` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_randao_mixes_reset`

Copies the current RANDAO mix into the entry of the next epoch.

### Signature

```
lantern_process_randao_mixes_reset(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_randao_mixes_reset` in the object of every fork, with `_` before it on macOS; `lantern_process_randao_mixes_reset` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_historical_roots_update`

When the next epoch starts a historical batch, appends hash_tree_root of HistoricalBatch(block_roots, state_roots) to historical_roots.

### Signature

```
lantern_process_historical_roots_update(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: the root is due and historical_roots has no room, or `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Hashes the state's block_roots and state_roots in place: they are laid out as one HistoricalBatch value.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_historical_roots_update` in the object of phase0 to bellatrix, with `_` before it on macOS; `lantern_process_historical_roots_update` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_historical_summaries_update`

When the next epoch starts a historical batch, appends the roots of block_roots and state_roots.

### Signature

```
lantern_process_historical_summaries_update(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: the summary is due and historical_summaries has no room, or `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Hashes with `ssz_hash_tree_root` of asm-ssz.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_historical_summaries_update` in the object of capella to fulu, with `_` before it on macOS; `lantern_process_historical_summaries_update` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_participation_flag_updates`

Moves the current participation flags to the previous ones and zeroes the current ones.

### Signature

```
lantern_process_participation_flag_updates(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_participation_flag_updates` in the object of altair to fulu, with `_` before it on macOS; `lantern_process_participation_flag_updates` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_participation_record_updates`

Moves current_epoch_attestations to previous_epoch_attestations and empties current_epoch_attestations.

### Signature

```
lantern_process_participation_record_updates(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: the previous list has less room than the current list's entries take.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_participation_record_updates` in the object of phase0, with `_` before it on macOS; `lantern_process_participation_record_updates` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_initiate_validator_exit`

Sets the exit and withdrawable epochs of a validator that has not exited, through the exit churn.

### Signature

```
lantern_initiate_validator_exit(state, index, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `index` | input | u64, below the number of validators |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or `LANTERN_INVALID_OVERFLOW` when an epoch leaves the Uint64 range.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short; the state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Before electra: the exit epoch is the latest exit epoch or the activation exit epoch of the current epoch, plus one when that epoch has lantern_get_validator_churn_limit exits.
- Electra and later: the exit epoch of lantern_compute_exit_epoch_and_update_churn.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_initiate_validator_exit` in the object of every fork, with `_` before it on macOS; `lantern_initiate_validator_exit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `index`, `config`, `scratch`, `result`.

## Function `lantern_get_validator_churn_limit`

max(MIN_PER_EPOCH_CHURN_LIMIT, the active validators of the current epoch // CHURN_LIMIT_QUOTIENT).

### Signature

```
lantern_get_validator_churn_limit(state, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_validator_churn_limit` in the object of phase0 to deneb, with `_` before it on macOS; `lantern_get_validator_churn_limit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `out`.

## Function `lantern_get_validator_activation_churn_limit`

min(MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT, lantern_get_validator_churn_limit(state)).

### Signature

```
lantern_get_validator_activation_churn_limit(state, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_validator_activation_churn_limit` in the object of deneb, with `_` before it on macOS; `lantern_get_validator_activation_churn_limit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `out`.

## Function `lantern_compute_exit_epoch_and_update_churn`

The epoch at which exit_balance may exit, with the exit churn of the state updated for it.

### Signature

```
lantern_compute_exit_epoch_and_update_churn(state, exit_balance, config, scratch, out, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `exit_balance` | input | u64 |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64 |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `out` holds the epoch and `result` is `LANTERN_VALID`, or `result` is `LANTERN_INVALID_OVERFLOW` when a Uint64 result leaves its range.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short; the state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_exit_epoch_and_update_churn` in the object of electra to fulu, with `_` before it on macOS; `lantern_compute_exit_epoch_and_update_churn` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `exit_balance`, `config`, `scratch`, `out`, `result`.

## Function `lantern_get_balance_churn_limit`

max(MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, total active balance // CHURN_LIMIT_QUOTIENT), down to a whole increment.

### Signature

```
lantern_get_balance_churn_limit(state, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the limit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_balance_churn_limit` in the object of electra to fulu, with `_` before it on macOS; `lantern_get_balance_churn_limit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `out`.

## Function `lantern_get_activation_exit_churn_limit`

min(MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT, the balance churn limit).

### Signature

```
lantern_get_activation_exit_churn_limit(state, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the limit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_activation_exit_churn_limit` in the object of electra to fulu, with `_` before it on macOS; `lantern_get_activation_exit_churn_limit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `out`.

## Function `lantern_get_consolidation_churn_limit`

The balance churn limit minus the activation and exit churn limit.

### Signature

```
lantern_get_consolidation_churn_limit(state, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the limit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_consolidation_churn_limit` in the object of electra to fulu, with `_` before it on macOS; `lantern_get_consolidation_churn_limit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `out`.

## Function `lantern_process_pending_deposits`

Applies pending deposits in order while they are finalized, under MAX_PENDING_DEPOSITS_PER_EPOCH and within the churn; postpones deposits of exited validators.

### Signature

```
lantern_process_pending_deposits(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or `LANTERN_INVALID_OVERFLOW`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short, or the validator lists have room for fewer than MAX_PENDING_DEPOSITS_PER_EPOCH new entries.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Electra: also stops at a deposit request (slot > GENESIS_SLOT) while eth1_deposit_index < deposit_requests_start_index.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 336 bytes on ARM64, 336 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_pending_deposits` in the object of electra to fulu, with `_` before it on macOS; `lantern_process_pending_deposits` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_apply_pending_deposit`

Increases the balance of the validator with the deposit's public key; when there is none and the signature is valid, adds a validator.

### Signature

```
lantern_apply_pending_deposit(state, deposit, config, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `deposit` | input | `PendingDeposit` |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |

### Returns

- `LANTERN_OK`: done.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short, or a new validator would not fit; the state is unchanged.

### Caller must

- Keep `deposit` apart from `state`.
- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_apply_pending_deposit` in the object of electra to fulu, with `_` before it on macOS; `lantern_apply_pending_deposit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `deposit`, `config`, `scratch`.

## Function `lantern_is_valid_deposit_signature`

bls.Verify(pubkey, signing root of the DepositMessage in the deposit domain, signature).

### Signature

```
lantern_is_valid_deposit_signature(deposit, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `deposit` | input | The spec's pubkey, withdrawal_credentials, amount and signature, laid out as a `DepositData`; `PendingDeposit` and `DepositRequest` share that layout |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`: `out` holds 1 for a valid signature, else 0.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Takes the domain of DOMAIN_DEPOSIT with GENESIS_FORK_VERSION and a zero root.
- Verifies with `crypto_bls_verify` of asm-crypto.
- Verifies a signature with `crypto_bls_verify` of asm-crypto.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 224 bytes on x86-64 (return address included), 224 bytes on ARM64, 224 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_valid_deposit_signature` in the object of electra to fulu, with `_` before it on macOS; `lantern_is_valid_deposit_signature` inside the object. The object of phase0 to deneb has only the local label.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `deposit`, `config`, `scratch`, `out`.

## Function `lantern_add_validator_to_registry`

Appends the validator of a deposit, its balance, zero participation flags and a zero inactivity score.

### Signature

```
lantern_add_validator_to_registry(state, pubkey, withdrawal_credentials, amount) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `pubkey` | input | BLSPubkey, 48 bytes |
| `withdrawal_credentials` | input | Bytes32 |
| `amount` | input | u64 |

### Returns

- `LANTERN_OK`: done.
- `LANTERN_BUFFER_TOO_SMALL`: one of the five lists has no room; the state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function does

- Phase0: appends the validator and its balance.
- Altair and later: also its participation flags and inactivity score.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 240 bytes on x86-64 (return address included), 240 bytes on ARM64, 240 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_add_validator_to_registry` in the object of every fork, with `_` before it on macOS; `lantern_add_validator_to_registry` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `pubkey`, `withdrawal_credentials`, `amount`.

## Function `lantern_get_validator_from_deposit`

A validator with FAR_FUTURE_EPOCH epochs and the effective balance of amount, down to an increment and up to its maximum.

### Signature

```
lantern_get_validator_from_deposit(pubkey, withdrawal_credentials, amount, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pubkey` | input | BLSPubkey, 48 bytes |
| `withdrawal_credentials` | input | Bytes32 |
| `amount` | input | u64 |
| `out` | output | `Validator` |

### Returns

- `LANTERN_OK`, always.

### Function does

- The effective balance cap is MAX_EFFECTIVE_BALANCE before electra, and lantern_get_max_effective_balance from electra on.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_validator_from_deposit` in the object of every fork, with `_` before it on macOS; `lantern_get_validator_from_deposit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `pubkey`, `withdrawal_credentials`, `amount`, `out`.

## Function `lantern_get_index_for_new_validator`

The number of validators.

### Signature

```
lantern_get_index_for_new_validator(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_index_for_new_validator` in the object of altair to fulu, with `_` before it on macOS; `lantern_get_index_for_new_validator` inside the object. The object of phase0 has only the local label.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `out`.

## Function `lantern_set_or_append_list`

Writes value at index of a list of the state, or appends it when index is the list's length.

### Signature

```
lantern_set_or_append_list(state, part, index, value) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `part` | input | `PartSpec`: an ABI argument for the spec's list |
| `index` | input | u64, at most the list's length |
| `value` | input | one entry: the stride of `part` in bytes |

### Returns

- `LANTERN_OK`: done.
- `LANTERN_BUFFER_TOO_SMALL`: an append has no room; the state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_set_or_append_list` in the object of altair to fulu, with `_` before it on macOS; `lantern_set_or_append_list` inside the object. The object of phase0 has only the local label.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `part`, `index`, `value`.

## Function `lantern_process_sync_committee_updates`

At the end of a sync committee period, the next committee becomes current and a new next committee is chosen.

### Signature

```
lantern_process_sync_committee_updates(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of a callee.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(2) + 2 * `SyncCommittee__mem` + 24 + 8 * SYNC_COMMITTEE_SIZE + 24 bytes.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_sync_committee_updates` in the object of altair to fulu, with `_` before it on macOS; `lantern_process_sync_committee_updates` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_get_next_sync_committee`

The committee of lantern_get_next_sync_committee_indices, with its aggregate public key.

### Signature

```
lantern_get_next_sync_committee(state, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `SyncCommittee` |

### Returns

- `LANTERN_OK`: `out` holds the committee.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.
- A `LANTERN_INVALID_*` code: a check of a callee failed, or the public keys do not aggregate.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Aggregates with `crypto_bls_eth_aggregate_pubkeys` of asm-crypto.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(2) + `SyncCommittee__mem` + 24 + 8 * SYNC_COMMITTEE_SIZE + 24 bytes.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_next_sync_committee` in the object of altair to fulu, with `_` before it on macOS; `lantern_get_next_sync_committee` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `out`.

## Function `lantern_get_next_sync_committee_indices`

SYNC_COMMITTEE_SIZE validators drawn from the next epoch's active validators, weighted by effective balance.

### Signature

```
lantern_get_next_sync_committee_indices(state, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `IndexList` with room for SYNC_COMMITTEE_SIZE entries |

### Returns

- `LANTERN_OK`: `out` holds the indices.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short, or `out` has room for fewer than SYNC_COMMITTEE_SIZE entries.
- `LANTERN_INVALID_NO_INDICES`: no validator is active in the next epoch.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Altair to deneb: a candidate passes when effective_balance * 255 >= MAX_EFFECTIVE_BALANCE * sha256(seed + uint_to_bytes(i // 32))[i % 32].
- Electra and later: a candidate passes when effective_balance * 65535 >= MAX_EFFECTIVE_BALANCE_ELECTRA * the two bytes at i % 16 * 2 of sha256(seed + uint_to_bytes(i // 16)).
- The shuffled index of each candidate is its entry of one lantern_compute_shuffled_permutation of the active validator count, in the second list of scratch.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 240 bytes on x86-64 (return address included), 240 bytes on ARM64, 240 bytes on RISC-V.
- Scratch: S(2).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_next_sync_committee_indices` in the object of altair to fulu, with `_` before it on macOS; `lantern_get_next_sync_committee_indices` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `out`.

## Function `lantern_process_proposer_lookahead`

Shifts the proposer lookahead by one epoch and fills the last epoch with its proposers.

### Signature

```
lantern_process_proposer_lookahead(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of a callee.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own with the mainnet preset: 368 bytes on x86-64 (return address included), 368 bytes on ARM64, 368 bytes on RISC-V.
- Stack of its own with the minimal preset: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.
- Scratch: S(2).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_proposer_lookahead` in the object of fulu, with `_` before it on macOS; `lantern_process_proposer_lookahead` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_process_epoch`

The epoch steps of the spec of its fork, in its order.

### Signature

```
lantern_process_epoch(state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of a step; on a failed check the later steps do not run.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short, or the state lacks the room of a step: MAX_PENDING_DEPOSITS_PER_EPOCH new validators, and one historical summary when one is due. Checked before any step runs.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Phase0: justification and finalization, rewards and penalties, registry updates, slashings, eth1 data reset, effective balance updates, slashings reset, RANDAO mixes reset, historical roots update, participation record updates.
- Altair and bellatrix: justification and finalization, inactivity updates, rewards and penalties, registry updates, slashings, eth1 data reset, effective balance updates, slashings reset, RANDAO mixes reset, historical roots update, participation flag updates, sync committee updates.
- Capella and deneb: the altair steps, with the historical summaries update for the historical roots update.
- Electra: the capella steps, with pending deposits and pending consolidations after the eth1 data reset.
- Fulu: the electra steps, then the proposer lookahead.
- Checks the scratch, and the room of each list it may append to, before it changes `state`; when either is short, returns `LANTERN_BUFFER_TOO_SMALL` with `state` unchanged.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: the most of its steps.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_epoch` in the object of every fork, with `_` before it on macOS; `lantern_process_epoch` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`, `result`.

## Function `lantern_add_deltas`

Adds the entries of one list to those of another.

### Signature

```
lantern_add_deltas(list, add, n) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `list` | state | u64 entries |
| `add` | input | u64 entries |
| `n` | input | u64 in a register: the entries |

### Returns

- `LANTERN_OK`: each entry of `list` holds its sum.
- `LANTERN_INVALID_OVERFLOW`: a sum leaves the u64 range.

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_add_deltas`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `list`, `add`, `n`.

## Function `lantern_record_room`

Whether previous_epoch_attestations can take the current ones.

### Signature

```
lantern_record_room(state) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |

### Returns

- `LANTERN_OK`: the part of previous_epoch_attestations has room for the entries of current_epoch_attestations.
- `LANTERN_BUFFER_TOO_SMALL`: it has not.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room named under Limits.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_record_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on x86-64 and RISC-V: rax, rcx, rdx, rsi, r8; a0, t0 to t4, a7.
- Argument order: `state`.

## Function `lantern_zero_deltas`

Sets the count of an output IndexList and zeros its entries.

### Signature

```
lantern_zero_deltas(list, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `list` | output | [`IndexList`](helpers.md#type-indexlist) |
| `n` | input | u64 in a register |

### Caller must

- `list` has room for `n` entries.

### Function does

- Writes `n` as the count of `list` and zeros its `n` entries.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_zero_deltas`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64: x0 to x3.
- Argument order: `list`, `n`.

## Type `PartSpec`

Where a list of a `BeaconState` is, for lantern_set_or_append_list.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `ref` | u64 | Offset of the list's PartRef in the state |
| 8 | `next` | u64 | Offset of the next part's PartRef, or 0 when the list's part is the last |
| 16 | `stride` | u64 | Bytes of one entry |

### Rules

- 24 bytes.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/epoch_processing/<handler>/` of each fork, for mainnet and minimal.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_process_justification_and_finalization`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_matching_source_attestations`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_matching_target_attestations`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_matching_head_attestations`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_unslashed_attesting_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_attesting_balance`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_weigh_justification_and_finalization`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_inactivity_updates`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_rewards_and_penalties`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_flag_index_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_inactivity_penalty_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_proposer_reward`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_attestation_component_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_source_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_target_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_head_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_inclusion_delay_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_attestation_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_registry_updates`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_slashings`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_eth1_data_reset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_pending_consolidations`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_effective_balance_updates`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_slashings_reset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_randao_mixes_reset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_historical_roots_update`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_historical_summaries_update`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_participation_flag_updates`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_participation_record_updates`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_initiate_validator_exit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_validator_churn_limit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_validator_activation_churn_limit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_exit_epoch_and_update_churn`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_balance_churn_limit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_activation_exit_churn_limit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_consolidation_churn_limit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_pending_deposits`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_apply_pending_deposit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_valid_deposit_signature`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_add_validator_to_registry`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_validator_from_deposit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_index_for_new_validator`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_set_or_append_list`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_sync_committee_updates`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_next_sync_committee`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_next_sync_committee_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_proposer_lookahead`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_add_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_record_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_zero_deltas`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
