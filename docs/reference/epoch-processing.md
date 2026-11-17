# Epoch processing

## Contents

### Functions

- [`lantern_process_justification_and_finalization`](#function-lantern_process_justification_and_finalization): justifies and finalizes checkpoints.
- [`lantern_weigh_justification_and_finalization`](#function-lantern_weigh_justification_and_finalization): the checkpoint updates for given target balances.
- [`lantern_process_inactivity_updates`](#function-lantern_process_inactivity_updates): updates inactivity scores.
- [`lantern_process_rewards_and_penalties`](#function-lantern_process_rewards_and_penalties): applies the rewards and penalties of the previous epoch.
- [`lantern_get_flag_index_deltas`](#function-lantern_get_flag_index_deltas): the rewards and penalties of one participation flag.
- [`lantern_get_inactivity_penalty_deltas`](#function-lantern_get_inactivity_penalty_deltas): the inactivity penalties.
- [`lantern_process_registry_updates`](#function-lantern_process_registry_updates): queues, ejects and activates validators.
- [`lantern_process_slashings`](#function-lantern_process_slashings): applies the correlated slashing penalties.
- [`lantern_process_eth1_data_reset`](#function-lantern_process_eth1_data_reset): clears the eth1 votes at the end of a voting period.
- [`lantern_process_pending_consolidations`](#function-lantern_process_pending_consolidations): moves balances of finished consolidations.
- [`lantern_process_effective_balance_updates`](#function-lantern_process_effective_balance_updates): updates effective balances with hysteresis.
- [`lantern_process_slashings_reset`](#function-lantern_process_slashings_reset): clears the next slashings entry.
- [`lantern_process_randao_mixes_reset`](#function-lantern_process_randao_mixes_reset): carries the RANDAO mix into the next epoch.
- [`lantern_process_historical_summaries_update`](#function-lantern_process_historical_summaries_update): appends a historical summary.
- [`lantern_process_participation_flag_updates`](#function-lantern_process_participation_flag_updates): rotates the participation flags.
- [`lantern_initiate_validator_exit`](#function-lantern_initiate_validator_exit): starts the exit of a validator.
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

### Types

- [`PartSpec`](#type-partspec): where a list of the state is.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), each function at its latest definition from phase0 to fulu.
- Section: Epoch processing of `beacon-chain.md` in phase0, altair, bellatrix, capella, electra and fulu, and the electra helpers it calls.

## Common rules

- Each argument is a pointer; numbers are u64. Each function returns its status in the ABI integer return register.
- `state` is a valid `BeaconState` value (include/types.inc) whose parts have the room each function names; `config` is a [`Config`](helpers.md#type-config); `scratch` is a [`Scratch`](helpers.md#type-scratch); `result` is a [`Result`](helpers.md#type-result).
- The scratch a function needs is S(k) of [Type Scratch](helpers.md#type-scratch), with k under its Limits. Each function checks it, and the room of each list it may append to, before it changes the state, and returns `LANTERN_BUFFER_TOO_SMALL` with the state unchanged when either is short.
- A function never makes an OS call and never keeps a pointer after it returns.
- Role, convention and symbol: as in [helpers.md](helpers.md#common-rules).
- The `process_*` functions take (`state`, `config`, `scratch`, `result`) in that order.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/fulu/epoch_processing/<handler>/` for mainnet and minimal.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.

## Function `lantern_process_justification_and_finalization`

Does nothing in the first two epochs; else weighs the target balances of the previous and current epochs.

### Signature

```
lantern_process_justification_and_finalization(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of lantern_get_block_root.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(3).

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

## Function `lantern_process_inactivity_updates`

In each epoch after the first, lowers the score of each eligible validator that hit the previous target and raises the others by INACTIVITY_SCORE_BIAS; outside a leak, also lowers each by INACTIVITY_SCORE_RECOVERY_RATE.

### Signature

```
lantern_process_inactivity_updates(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(3).

## Function `lantern_process_rewards_and_penalties`

In each epoch after the first, computes the deltas of the three flags and of inactivity, then applies each.

### Signature

```
lantern_process_rewards_and_penalties(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(11).

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

### Limits

- Scratch: S(3).

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

### Limits

- Scratch: S(3).

## Function `lantern_process_registry_updates`

For each validator: queues it for activation, or ejects it when active with an effective balance at most EJECTION_BALANCE, or activates it when eligible.

### Signature

```
lantern_process_registry_updates(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of lantern_initiate_validator_exit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(1).

## Function `lantern_process_slashings`

Penalizes each slashed validator half way to its withdrawable epoch in proportion to the recent slashings.

### Signature

```
lantern_process_slashings(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(1).

## Function `lantern_process_eth1_data_reset`

Empties eth1_data_votes when the next epoch starts a voting period.

### Signature

```
lantern_process_eth1_data_reset(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

## Function `lantern_process_pending_consolidations`

Moves the balance of each pending consolidation whose source is withdrawable to its target, skips slashed sources, and drops the processed entries.

### Signature

```
lantern_process_pending_consolidations(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

## Function `lantern_process_effective_balance_updates`

Sets the effective balance of each validator whose balance left the hysteresis band.

### Signature

```
lantern_process_effective_balance_updates(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

## Function `lantern_process_slashings_reset`

Sets the slashings entry of the next epoch to 0.

### Signature

```
lantern_process_slashings_reset(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

## Function `lantern_process_randao_mixes_reset`

Copies the current RANDAO mix into the entry of the next epoch.

### Signature

```
lantern_process_randao_mixes_reset(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

## Function `lantern_process_historical_summaries_update`

When the next epoch starts a historical batch, appends the roots of block_roots and state_roots.

### Signature

```
lantern_process_historical_summaries_update(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.
- `LANTERN_BUFFER_TOO_SMALL`: the summary is due and historical_summaries has no room, or `scratch` is short.

### Function does

- Hashes with `ssz_hash_tree_root` of asm-ssz.

## Function `lantern_process_participation_flag_updates`

Moves the current participation flags to the previous ones and zeroes the current ones.

### Signature

```
lantern_process_participation_flag_updates(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`.

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

### Limits

- Scratch: S(1).

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

### Limits

- Scratch: S(1).

## Function `lantern_get_balance_churn_limit`

max(MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA, total active balance // CHURN_LIMIT_QUOTIENT), down to a whole increment.

### Signature

```
lantern_get_balance_churn_limit(state, config, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the limit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(1).

## Function `lantern_get_activation_exit_churn_limit`

min(MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT, the balance churn limit).

### Signature

```
lantern_get_activation_exit_churn_limit(state, config, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the limit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(1).

## Function `lantern_get_consolidation_churn_limit`

The balance churn limit minus the activation and exit churn limit.

### Signature

```
lantern_get_consolidation_churn_limit(state, config, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the limit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(1).

## Function `lantern_process_pending_deposits`

Applies pending deposits in order while they are finalized, under MAX_PENDING_DEPOSITS_PER_EPOCH and within the churn; postpones deposits of exited validators.

### Signature

```
lantern_process_pending_deposits(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or `LANTERN_INVALID_OVERFLOW`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short, or the validator lists have room for fewer than MAX_PENDING_DEPOSITS_PER_EPOCH new entries.

### Limits

- Scratch: S(1).

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

### Limits

- Scratch: S(0).

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

### Function does

- Takes the domain of DOMAIN_DEPOSIT with GENESIS_FORK_VERSION and a zero root.
- Verifies with `crypto_bls_verify` of asm-crypto.

### Limits

- Scratch: S(0).

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

## Function `lantern_get_index_for_new_validator`

The number of validators.

### Signature

```
lantern_get_index_for_new_validator(state, out) -> status
```

### Returns

- `LANTERN_OK`, always.

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

## Function `lantern_process_sync_committee_updates`

At the end of a sync committee period, the next committee becomes current and a new next committee is chosen.

### Signature

```
lantern_process_sync_committee_updates(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of a callee.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(2) + 2 * `SyncCommittee__mem` + 24 + 8 * SYNC_COMMITTEE_SIZE + 24 bytes.

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

### Function does

- Aggregates with `crypto_bls_eth_aggregate_pubkeys` of asm-crypto.

### Limits

- Scratch: S(2) + `SyncCommittee__mem` + 24 + 8 * SYNC_COMMITTEE_SIZE + 24 bytes.

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

### Limits

- Scratch: S(2).

## Function `lantern_process_proposer_lookahead`

Shifts the proposer lookahead by one epoch and fills the last epoch with its proposers.

### Signature

```
lantern_process_proposer_lookahead(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of a callee.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Limits

- Scratch: S(2).

## Function `lantern_process_epoch`

The fifteen epoch steps of the spec, in its order.

### Signature

```
lantern_process_epoch(state, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the failed check of a step; on a failed check the later steps do not run.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short, or the state lacks the room of a step: MAX_PENDING_DEPOSITS_PER_EPOCH new validators, and one historical summary when one is due. Checked before any step runs.

### Limits

- Scratch: the most of its steps.

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

## Results

<!-- CI generates the tick table for each function here. -->
