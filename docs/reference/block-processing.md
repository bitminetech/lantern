# Block processing

## Contents

### Functions

- [`lantern_process_block`](#function-lantern_process_block): every block step, in spec order.
- [`lantern_process_block_header`](#function-lantern_process_block_header): checks the header and stores it.
- [`lantern_process_withdrawals`](#function-lantern_process_withdrawals): checks and applies the payload's withdrawals.
- [`lantern_get_expected_withdrawals`](#function-lantern_get_expected_withdrawals): the withdrawals the payload must hold.
- [`lantern_get_pending_partial_withdrawals`](#function-lantern_get_pending_partial_withdrawals): the withdrawals of the pending partial withdrawals.
- [`lantern_get_validators_sweep_withdrawals`](#function-lantern_get_validators_sweep_withdrawals): the withdrawals of the validator sweep.
- [`lantern_get_balance_after_withdrawals`](#function-lantern_get_balance_after_withdrawals): a balance less the withdrawals so far.
- [`lantern_apply_withdrawals`](#function-lantern_apply_withdrawals): lowers balances by withdrawals.
- [`lantern_update_next_withdrawal_index`](#function-lantern_update_next_withdrawal_index): moves the next withdrawal index.
- [`lantern_update_pending_partial_withdrawals`](#function-lantern_update_pending_partial_withdrawals): drops processed pending partial withdrawals.
- [`lantern_update_next_withdrawal_validator_index`](#function-lantern_update_next_withdrawal_validator_index): moves the sweep start.
- [`lantern_is_fully_withdrawable_validator`](#function-lantern_is_fully_withdrawable_validator): whether all of a balance may be withdrawn.
- [`lantern_is_partially_withdrawable_validator`](#function-lantern_is_partially_withdrawable_validator): whether the excess of a balance may be withdrawn.
- [`lantern_has_eth1_withdrawal_credential`](#function-lantern_has_eth1_withdrawal_credential): whether credentials have the 0x01 prefix.
- [`lantern_has_execution_withdrawal_credential`](#function-lantern_has_execution_withdrawal_credential): whether credentials have the 0x01 or 0x02 prefix.
- [`lantern_is_eligible_for_partial_withdrawals`](#function-lantern_is_eligible_for_partial_withdrawals): whether a pending partial withdrawal may be paid.
- [`lantern_get_pending_balance_to_withdraw`](#function-lantern_get_pending_balance_to_withdraw): the pending partial withdrawals of a validator.
- [`lantern_process_execution_payload`](#function-lantern_process_execution_payload): checks the payload and stores its header.
- [`lantern_get_blob_parameters`](#function-lantern_get_blob_parameters): the blob limit of an epoch.
- [`lantern_kzg_commitment_to_versioned_hash`](#function-lantern_kzg_commitment_to_versioned_hash): the versioned hash of a commitment.
- [`lantern_compute_time_at_slot`](#function-lantern_compute_time_at_slot): the start time of a slot.
- [`lantern_process_randao`](#function-lantern_process_randao): checks the RANDAO reveal and mixes it in.
- [`lantern_process_eth1_data`](#function-lantern_process_eth1_data): counts the eth1 vote.
- [`lantern_process_operations`](#function-lantern_process_operations): applies each operation of the body.
- [`lantern_process_proposer_slashing`](#function-lantern_process_proposer_slashing): slashes a proposer of two headers.
- [`lantern_process_attester_slashing`](#function-lantern_process_attester_slashing): slashes the attesters of two conflicting attestations.
- [`lantern_process_attestation`](#function-lantern_process_attestation): records an attestation's participation flags.
- [`lantern_process_voluntary_exit`](#function-lantern_process_voluntary_exit): starts a signed exit.
- [`lantern_process_bls_to_execution_change`](#function-lantern_process_bls_to_execution_change): moves BLS credentials to an execution address.
- [`lantern_process_deposit_request`](#function-lantern_process_deposit_request): queues a deposit request.
- [`lantern_process_withdrawal_request`](#function-lantern_process_withdrawal_request): exits or queues a partial withdrawal.
- [`lantern_process_consolidation_request`](#function-lantern_process_consolidation_request): switches to compounding or queues a consolidation.
- [`lantern_is_valid_switch_to_compounding_request`](#function-lantern_is_valid_switch_to_compounding_request): whether a consolidation request switches a validator to compounding.
- [`lantern_switch_to_compounding_validator`](#function-lantern_switch_to_compounding_validator): sets the 0x02 prefix and queues the excess balance.
- [`lantern_queue_excess_active_balance`](#function-lantern_queue_excess_active_balance): moves the balance above MIN_ACTIVATION_BALANCE to a pending deposit.
- [`lantern_compute_consolidation_epoch_and_update_churn`](#function-lantern_compute_consolidation_epoch_and_update_churn): the consolidation epoch, and the churn update.
- [`lantern_process_sync_aggregate`](#function-lantern_process_sync_aggregate): checks the sync aggregate and pays its participants.
- [`lantern_slash_validator`](#function-lantern_slash_validator): slashes a validator and pays the whistleblower.
- [`lantern_is_slashable_attestation_data`](#function-lantern_is_slashable_attestation_data): whether two attestation datas conflict.
- [`lantern_is_valid_indexed_attestation`](#function-lantern_is_valid_indexed_attestation): checks the indices and signature of an indexed attestation.
- [`lantern_get_committee_indices`](#function-lantern_get_committee_indices): the set committee bits.
- [`lantern_get_committee_count_per_slot`](#function-lantern_get_committee_count_per_slot): the committees of each slot of an epoch.
- [`lantern_compute_committee`](#function-lantern_compute_committee): one committee of a shuffle.
- [`lantern_get_beacon_committee`](#function-lantern_get_beacon_committee): a committee of a slot.
- [`lantern_get_attesting_indices`](#function-lantern_get_attesting_indices): the attesters of an attestation.
- [`lantern_get_indexed_attestation`](#function-lantern_get_indexed_attestation): an attestation with its attesters.
- [`lantern_get_attestation_participation_flag_indices`](#function-lantern_get_attestation_participation_flag_indices): the flags an attestation earns.
- [`lantern_get_beacon_proposer_index`](#function-lantern_get_beacon_proposer_index): the proposer of the state's slot.
- [`lantern_get_set_bit_count`](#function-lantern_get_set_bit_count): the set bits of a bit vector.
- [`lantern_xor`](#function-lantern_xor): the xor of two Bytes32.

### Types

- [`ExpectedWithdrawals`](#type-expectedwithdrawals): the withdrawals of a payload, with what they used up.
- [`WithdrawalsSweep`](#type-withdrawalssweep): withdrawals of one source, with the next index and the entries used.
- [`BlobParameters`](#type-blobparameters): an epoch and its blob limit.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), each function at its latest definition from phase0 to fulu.
- Section: Block processing of `beacon-chain.md` in phase0, altair, bellatrix, capella, deneb, electra and fulu, with the helpers it calls.

## Common rules

- Each argument is a pointer; numbers are u64. Each function returns its status in the ABI integer return register: `LANTERN_OK`, `LANTERN_BUFFER_TOO_SMALL`, or for a function that changes no state the `LANTERN_INVALID_*` code of a failed spec check.
- A function that changes the state takes a [`Result`](helpers.md#type-result) as its last argument; it checks scratch and room before any change.
- `state` is a valid `BeaconState` value; blocks, bodies and operations are valid asm-ssz Values of their types, apart from `state`.
- Scratch is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `execution_valid` is the answer of the execution engine to the payload, given by the caller: 1 valid, 0 not.
- A function never makes an OS call and never keeps a pointer after it returns.
- Role: L1. Convention: the core ABI for each ISA (ARCHITECTURE.md section 6). Symbol: the function name (`_` prefixed on macOS).
- The `process_*` operation functions take (`state`, the operation, `config`, `scratch`, `result`) in that order.
- Signatures are verified with `crypto_bls_verify`, `crypto_bls_fast_aggregate_verify` and `crypto_bls_eth_fast_aggregate_verify` of asm-crypto; keys are combined with its `crypto_bls_g1_*` functions.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/fulu/operations/<handler>/` for mainnet and minimal.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.
  - Cases with `bls_setting` 2 were made with signature checks turned off. `runner-<preset>` skips them; `runner-<preset>-bls-off` runs only them, with the three asm-crypto signature checks replaced by tests/runner/bls_off.c as in the spec's test mode.

## Function `lantern_process_block`

process_block_header, process_withdrawals, process_execution_payload, process_randao, process_eth1_data, process_operations and process_sync_aggregate; stops at the first failed check.

### Signature

```
lantern_process_block(state, block, execution_valid, config, scratch, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` or the first failed check.
- `LANTERN_BUFFER_TOO_SMALL`: scratch, or room for the body's appends, is short. Checked before any step runs.

### Limits

- Scratch: S(10).

## Function `lantern_process_block_header`

Checks slot, proposer, parent root and that the proposer is not slashed; stores the header with a zero state root.

### Signature

```
lantern_process_block_header(state, block, config, scratch, result) -> status
```

### Limits

- Scratch: S(0).

## Function `lantern_process_withdrawals`

Checks that the payload's withdrawals are the expected ones, then applies them and moves the withdrawal indices.

### Signature

```
lantern_process_withdrawals(state, payload, config, scratch, result) -> status
```

### Limits

- Scratch: S(0).

## Function `lantern_get_expected_withdrawals`

The pending partial withdrawals, then the sweep withdrawals, from state.next_withdrawal_index.

### Signature

```
lantern_get_expected_withdrawals(state, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `ExpectedWithdrawals` |

### Returns

- `LANTERN_OK`: `out` holds the withdrawals.
- `LANTERN_BUFFER_TOO_SMALL`: scratch has fewer than 8 + 2 * the bytes of a `WithdrawalsSweep` + the bytes of a `Withdrawals` value.
- A `LANTERN_INVALID_*` code: a check of a callee failed.

## Function `lantern_get_pending_partial_withdrawals`

The withdrawable pending partial withdrawals, up to the limit after prior_withdrawals.

### Signature

```
lantern_get_pending_partial_withdrawals(state, withdrawal_index, prior_withdrawals, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `withdrawal_index` | input | u64 |
| `prior_withdrawals` | input | `Withdrawals` value |
| `scratch` | scratch | `Scratch`: 8 + the bytes of a `Withdrawals` value, for the spec's all_withdrawals |
| `out` | output | `WithdrawalsSweep` |

### Returns

- `LANTERN_OK`: `out` holds the result.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.
- `LANTERN_INVALID_VALIDATOR_INDEX`: a pending withdrawal names no validator.
- `LANTERN_INVALID_WITHDRAWALS_LIMIT`: prior_withdrawals is above the limit.

## Function `lantern_get_validators_sweep_withdrawals`

The full and partial withdrawals of up to MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP validators from next_withdrawal_validator_index.

### Signature

```
lantern_get_validators_sweep_withdrawals(state, withdrawal_index, prior_withdrawals, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `withdrawal_index` | input | u64 |
| `prior_withdrawals` | input | `Withdrawals` value |
| `scratch` | scratch | `Scratch`: 8 + the bytes of a `Withdrawals` value, for the spec's all_withdrawals |
| `out` | output | `WithdrawalsSweep` |

### Returns

- `LANTERN_OK`: `out` holds the result.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.
- `LANTERN_INVALID_VALIDATOR_INDEX`: next_withdrawal_validator_index names no validator.
- `LANTERN_INVALID_WITHDRAWALS_LIMIT`: prior_withdrawals is at MAX_WITHDRAWALS_PER_PAYLOAD or above.

## Function `lantern_get_balance_after_withdrawals`

state.balances[validator_index] less the amounts of withdrawals to it.

### Signature

```
lantern_get_balance_after_withdrawals(state, validator_index, withdrawals, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `validator_index` | input | u64 |
| `withdrawals` | input | `Withdrawals` value |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the balance.
- `LANTERN_INVALID_OVERFLOW`: the withdrawn sum is above the balance.

## Function `lantern_apply_withdrawals`

decrease_balance by each withdrawal.

### Signature

```
lantern_apply_withdrawals(state, withdrawals) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_update_next_withdrawal_index`

The last withdrawal's index plus 1, when there is one.

### Signature

```
lantern_update_next_withdrawal_index(state, withdrawals) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_update_pending_partial_withdrawals`

Drops the first processed_partial_withdrawals_count pending partial withdrawals.

### Signature

```
lantern_update_pending_partial_withdrawals(state, processed_partial_withdrawals_count) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_update_next_withdrawal_validator_index`

After a full payload, the validator after the last withdrawal; else MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP further, modulo the validator count.

### Signature

```
lantern_update_next_withdrawal_validator_index(state, withdrawals) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_is_fully_withdrawable_validator`

Execution credentials, withdrawable_epoch at most epoch, and a balance above 0.

### Signature

```
lantern_is_fully_withdrawable_validator(validator, balance, epoch, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_is_partially_withdrawable_validator`

Execution credentials, the maximum effective balance, and a balance above it.

### Signature

```
lantern_is_partially_withdrawable_validator(validator, balance, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_has_eth1_withdrawal_credential`

The first credential byte is ETH1_ADDRESS_WITHDRAWAL_PREFIX.

### Signature

```
lantern_has_eth1_withdrawal_credential(validator, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_has_execution_withdrawal_credential`

lantern_has_eth1_withdrawal_credential or lantern_has_compounding_withdrawal_credential.

### Signature

```
lantern_has_execution_withdrawal_credential(validator, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_is_eligible_for_partial_withdrawals`

Not exiting, an effective balance of at least MIN_ACTIVATION_BALANCE, and a balance above it.

### Signature

```
lantern_is_eligible_for_partial_withdrawals(validator, balance, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_get_pending_balance_to_withdraw`

The sum of the pending partial withdrawals of validator_index.

### Signature

```
lantern_get_pending_balance_to_withdraw(state, validator_index, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the sum.
- `LANTERN_INVALID_OVERFLOW`: the sum leaves the Uint64 range.

## Function `lantern_process_execution_payload`

Checks the payload's parent hash, prev_randao, timestamp, blob count and the engine's answer; stores its header.

### Signature

```
lantern_process_execution_payload(state, body, execution_valid, config, scratch, result) -> status
```

### Limits

- Scratch: S(0).

## Function `lantern_get_blob_parameters`

The last BLOB_SCHEDULE entry whose epoch is at most epoch, else the electra limit.

### Signature

```
lantern_get_blob_parameters(epoch, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `epoch` | input | u64 |
| `config` | input | `Config` |
| `out` | output | `BlobParameters` |

### Returns

- `LANTERN_OK`, always.

## Function `lantern_kzg_commitment_to_versioned_hash`

VERSIONED_HASH_VERSION_KZG + sha256(kzg_commitment)[1:].

### Signature

```
lantern_kzg_commitment_to_versioned_hash(kzg_commitment, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_compute_time_at_slot`

The start of slot in seconds: (genesis_time in ms, saturated, + slot * SLOT_DURATION_MS) // 1000.

### Signature

```
lantern_compute_time_at_slot(genesis_time, slot, config, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the time.
- `LANTERN_INVALID_OVERFLOW`: the time in ms leaves the Uint64 range.

## Function `lantern_process_randao`

Checks the proposer's RANDAO reveal of the epoch and mixes its hash into the epoch's mix.

### Signature

```
lantern_process_randao(state, body, config, scratch, result) -> status
```

### Limits

- Scratch: S(0).

## Function `lantern_process_eth1_data`

Appends the body's eth1 vote and adopts it when more than half the period voted for it.

### Signature

```
lantern_process_eth1_data(state, body, config, scratch, result) -> status
```

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: eth1_data_votes has no room.

## Function `lantern_process_operations`

Checks that the body holds no deposits, then applies each list of operations in spec order.

### Signature

```
lantern_process_operations(state, body, config, scratch, result) -> status
```

### Limits

- Scratch: S(10).

## Function `lantern_process_proposer_slashing`

Checks two different signed headers of one proposer and slot, then slashes the proposer.

### Signature

```
lantern_process_proposer_slashing(state, proposer_slashing, config, scratch, result) -> status
```

### Limits

- Scratch: S(1).

## Function `lantern_process_attester_slashing`

Checks two conflicting valid indexed attestations, then slashes each slashable validator in both.

### Signature

```
lantern_process_attester_slashing(state, attester_slashing, config, scratch, result) -> status
```

### Limits

- Scratch: S(8).

## Function `lantern_process_attestation`

Checks the attestation's epochs, delay, committees and signature, sets the flags it earns, and pays the proposer.

### Signature

```
lantern_process_attestation(state, attestation, config, scratch, result) -> status
```

### Limits

- Scratch: S(10).

## Function `lantern_process_voluntary_exit`

Checks an active, unexited, old enough validator with no pending withdrawals and a valid signature, then starts its exit.

### Signature

```
lantern_process_voluntary_exit(state, signed_voluntary_exit, config, scratch, result) -> status
```

### Limits

- Scratch: S(1).

## Function `lantern_process_bls_to_execution_change`

Checks the BLS credentials and signature, then sets 0x01 credentials with the new address.

### Signature

```
lantern_process_bls_to_execution_change(state, signed_address_change, config, scratch, result) -> status
```

### Limits

- Scratch: S(0).

## Function `lantern_process_deposit_request`

Appends a pending deposit of the request at the state's slot.

### Signature

```
lantern_process_deposit_request(state, deposit_request, config, scratch, result) -> status
```

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: pending_deposits has no room.

## Function `lantern_process_withdrawal_request`

A full exit, or a partial withdrawal of a compounding validator's excess, when the request's checks hold.

### Signature

```
lantern_process_withdrawal_request(state, withdrawal_request, config, scratch, result) -> status
```

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or pending_partial_withdrawals has no room.

### Limits

- Scratch: S(1).

## Function `lantern_process_consolidation_request`

A switch to compounding, or a queued consolidation, when the request's checks hold.

### Signature

```
lantern_process_consolidation_request(state, consolidation_request, config, scratch, result) -> status
```

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or pending_deposits or pending_consolidations has no room.

### Limits

- Scratch: S(1).

## Function `lantern_is_valid_switch_to_compounding_request`

Same source and target key of an active, unexited validator with 0x01 credentials of the source address.

### Signature

```
lantern_is_valid_switch_to_compounding_request(state, consolidation_request, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_switch_to_compounding_validator`

Sets the 0x02 prefix and queues the excess balance.

### Signature

```
lantern_switch_to_compounding_validator(state, index) -> status
```

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: pending_deposits has no room; the state is unchanged.

## Function `lantern_queue_excess_active_balance`

Moves a balance above MIN_ACTIVATION_BALANCE to a pending deposit with the infinity signature at GENESIS_SLOT.

### Signature

```
lantern_queue_excess_active_balance(state, index) -> status
```

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: pending_deposits has no room; the state is unchanged.

## Function `lantern_compute_consolidation_epoch_and_update_churn`

As lantern_compute_exit_epoch_and_update_churn, with the consolidation churn and fields.

### Signature

```
lantern_compute_consolidation_epoch_and_update_churn(state, consolidation_balance, config, scratch, out, result) -> status
```

### Limits

- Scratch: S(1).

## Function `lantern_process_sync_aggregate`

Checks the sync committee signature over the previous slot's block root, then pays or penalizes each member and pays the proposer.

### Signature

```
lantern_process_sync_aggregate(state, sync_aggregate, config, scratch, result) -> status
```

### Limits

- Scratch: S(1).

## Function `lantern_slash_validator`

Exits and slashes a validator, applies its penalty, and pays the proposer and the whistleblower.

### Signature

```
lantern_slash_validator(state, slashed_index, whistleblower_index, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `slashed_index` | input | u64 |
| `whistleblower_index` | input | u64, or a null pointer for the spec's None |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Limits

- Scratch: S(1).

## Function `lantern_is_slashable_attestation_data`

A double vote or a surround vote.

### Signature

```
lantern_is_slashable_attestation_data(data_1, data_2, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_is_valid_indexed_attestation`

Non empty, sorted and unique indices, and a valid aggregate signature of their keys.

### Signature

```
lantern_is_valid_indexed_attestation(state, indexed_attestation, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds 1 or 0.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.

### Limits

- Scratch: S(7): the public keys take 48 bytes each.

## Function `lantern_get_committee_indices`

The indices of the set bits of committee_bits, ascending.

### Signature

```
lantern_get_committee_indices(committee_bits, out) -> status
```

### Returns

- `LANTERN_OK`, always.

### Caller must

- Give `out` room for MAX_COMMITTEES_PER_SLOT entries.

## Function `lantern_get_committee_count_per_slot`

max(1, min(MAX_COMMITTEES_PER_SLOT, active validators // SLOTS_PER_EPOCH // TARGET_COMMITTEE_SIZE)).

### Signature

```
lantern_get_committee_count_per_slot(state, epoch, scratch, out) -> status
```

### Limits

- Scratch: S(1).

## Function `lantern_compute_committee`

indices[shuffled index] for each index from len(indices) * index // count to len(indices) * (index + 1) // count.

### Signature

```
lantern_compute_committee(indices, seed, index, count, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the committee.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or `out` has too little room.

### Limits

- Scratch: S(1), with n the length of indices.

## Function `lantern_get_beacon_committee`

lantern_compute_committee over the epoch's active validators with its DOMAIN_BEACON_ATTESTER seed.

### Signature

```
lantern_get_beacon_committee(state, slot, index, scratch, out) -> status
```

### Limits

- Scratch: S(2).

## Function `lantern_get_attesting_indices`

The members of the attestation's committees whose aggregation bits are set, ascending and unique.

### Signature

```
lantern_get_attesting_indices(state, attestation, scratch, out) -> status
```

### Limits

- Scratch: S(4).

## Function `lantern_get_indexed_attestation`

The attestation's data and signature with its sorted attesting indices.

### Signature

```
lantern_get_indexed_attestation(state, attestation, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `attestation` | input | `Attestation` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `IndexedAttestation` value; its `size` set by the caller |

### Limits

- Scratch: S(4).

## Function `lantern_get_attestation_participation_flag_indices`

The flags of a matching source, target and head within their delays.

### Signature

```
lantern_get_attestation_participation_flag_indices(state, data, inclusion_delay, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the flags as an `IndexList`.
- `LANTERN_INVALID_SOURCE`: the source is not the justified checkpoint.
- `LANTERN_INVALID_BLOCK_ROOT_SLOT`: a block root is out of range.

## Function `lantern_get_beacon_proposer_index`

state.proposer_lookahead[state.slot % SLOTS_PER_EPOCH].

### Signature

```
lantern_get_beacon_proposer_index(state, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_get_set_bit_count`

The set bits of a bit vector of length bits.

### Signature

```
lantern_get_set_bit_count(bits, length, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Function `lantern_xor`

The byte wise xor of two Bytes32.

### Signature

```
lantern_xor(bytes_1, bytes_2, out) -> status
```

### Returns

- `LANTERN_OK`, always.

## Type `ExpectedWithdrawals`

The withdrawals of a payload, with the entries they used up.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `processed_partial_withdrawals_count` | u64 | Pending partial withdrawals used |
| 8 | `processed_sweep_withdrawals_count` | u64 | Validators swept |
| 16 | `withdrawals` | `Withdrawals` value | Its own size, PartRef and entries |

### Rules

- 16 + 24 + MAX_WITHDRAWALS_PER_PAYLOAD * `Withdrawal__mem` bytes.

## Type `WithdrawalsSweep`

The tuple (withdrawals, withdrawal_index, processed_count) of the spec.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `withdrawal_index` | u64 | The next withdrawal index |
| 8 | `processed_count` | u64 | Entries used |
| 16 | `withdrawals` | `Withdrawals` value | Its own size, PartRef and entries |

### Rules

- 16 + 24 + MAX_WITHDRAWALS_PER_PAYLOAD * `Withdrawal__mem` bytes.

## Type `BlobParameters`

An epoch and the blob limit from it.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `epoch` | u64 | First epoch of the limit |
| 8 | `max_blobs_per_block` | u64 | The limit |

## Results

<!-- CI generates the tick table for each function here. -->
