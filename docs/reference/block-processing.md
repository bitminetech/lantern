# Block processing

Every block step, for every fork.

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
- [`lantern_is_merge_transition_complete`](#function-lantern_is_merge_transition_complete): whether the state holds a payload header.
- [`lantern_is_merge_transition_block`](#function-lantern_is_merge_transition_block): whether a body holds the first payload.
- [`lantern_is_execution_enabled`](#function-lantern_is_execution_enabled): whether a block runs its payload.
- [`lantern_get_blob_parameters`](#function-lantern_get_blob_parameters): the blob limit of an epoch.
- [`lantern_kzg_commitment_to_versioned_hash`](#function-lantern_kzg_commitment_to_versioned_hash): the versioned hash of a commitment.
- [`lantern_compute_time_at_slot`](#function-lantern_compute_time_at_slot): the start time of a slot.
- [`lantern_process_randao`](#function-lantern_process_randao): checks the RANDAO reveal and mixes it in.
- [`lantern_process_eth1_data`](#function-lantern_process_eth1_data): counts the eth1 vote.
- [`lantern_process_operations`](#function-lantern_process_operations): applies each operation of the body.
- [`lantern_process_deposit`](#function-lantern_process_deposit): checks a deposit's proof and applies it.
- [`lantern_apply_deposit`](#function-lantern_apply_deposit): credits a deposit, or adds a validator for it.
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
- [`lantern_committee_cache_size`](#function-lantern_committee_cache_size): the bytes of a committee cache for a number of validators.
- [`lantern_committee_cache_init`](#function-lantern_committee_cache_init): lays out an empty committee cache.
- [`lantern_pubkey_cache_size`](#function-lantern_pubkey_cache_size): the bytes of a public key cache for a number of validators.
- [`lantern_pubkey_cache_init`](#function-lantern_pubkey_cache_init): lays out an empty public key cache.
- [`lantern_attestation_memo`](#function-lantern_attestation_memo): process_attestation, with one get_base_reward_per_increment shared by the attestations of a block.
- [`lantern_block_sigs`](#function-lantern_block_sigs): the signature checks of a block's attestations at once on the pool, into the SigTable.
- [`lantern_block_sig_keys`](#function-lantern_block_sig_keys): the PubkeyCache entries of some indices, filled.
- [`lantern_block_sig_entry`](#function-lantern_block_sig_entry): the SigEntry of an indexed attestation's check.
- [`lantern_block_sig_job`](#function-lantern_block_sig_job): a job of lantern_block_sigs.
- [`lantern_indexed_attestation_valid`](#function-lantern_indexed_attestation_valid): is_valid_indexed_attestation, with the sum of the keys from the key sums of a committee cache when it can.
- [`lantern_attestation_key_sum`](#function-lantern_attestation_key_sum): the sum of the public keys of an attestation's attesting validators, from the key sums of a committee cache.
- [`lantern_key_sum_make`](#function-lantern_key_sum_make): makes the KeySum of a committee.
- [`lantern_key_sum_scan`](#function-lantern_key_sum_scan): the members of a committee whose PubkeyCache entries do not hold their keys.
- [`lantern_committee_find`](#function-lantern_committee_find): the entry of a CommitteeCache for an epoch and a key.
- [`lantern_committee_key`](#function-lantern_committee_key): the key of an epoch's shuffling in a CommitteeCache.
- [`lantern_find_pubkey`](#function-lantern_find_pubkey): the index of the validator with a public key.
- [`lantern_sync_indices`](#function-lantern_sync_indices): lantern_find_pubkeys, with the SyncIndices of a PubkeyCache.
- [`lantern_find_pubkeys`](#function-lantern_find_pubkeys): all_pubkeys.index(pubkey) for each key of a sync committee.
- [`lantern_append_pending_deposit`](#function-lantern_append_pending_deposit): appends a PendingDeposit to a state.
- [`lantern_append_withdrawal`](#function-lantern_append_withdrawal): appends a Withdrawal to a Withdrawals value.
- [`lantern_concat_withdrawals`](#function-lantern_concat_withdrawals): the list all = prior + new, for get_balance_after_withdrawals.
- [`lantern_all_zero`](#function-lantern_all_zero): whether bytes are all zero.
- [`lantern_build_payload_header`](#function-lantern_build_payload_header): the ExecutionPayloadHeader of an execution payload, for lantern_process_execution_payload.
- [`lantern_check_header_signature`](#function-lantern_check_header_signature): checks the signature of a signed block header of a proposer slashing.
- [`lantern_randao_step`](#function-lantern_randao_step): process_randao, with or without the check of the reveal's signature.
- [`lantern_sort_u64`](#function-lantern_sort_u64): sorts u64 entries ascending.
- [`lantern_validator_room`](#function-lantern_validator_room): the fewest free entries in the validator lists of a state.
- [`lantern_verify_root_signature`](#function-lantern_verify_root_signature): verifies a BLS signature over a signing root.

### Types

- [`PubkeyCache`](#type-pubkeycache): the decoded public keys of the validators.
- [`SigTable`](#type-sigtable): checked signatures with their whole inputs, in a PubkeyCache.
- [`SigEntry`](#type-sigentry): one checked signature.
- [`CommitteeCache`](#type-committeecache): the shuffled active validators of a few epochs.
- [`CommitteeEntry`](#type-committeeentry): one epoch's shuffling in a `CommitteeCache`.
- [`KeySum`](#type-keysum): the sum of one committee's public keys in a `CommitteeCache`.
- [`ExpectedWithdrawals`](#type-expectedwithdrawals): the withdrawals of a payload, with what they used up.
- [`WithdrawalsSweep`](#type-withdrawalssweep): withdrawals of one source, with the next index and the entries used.
- [`BlobParameters`](#type-blobparameters): an epoch and its blob limit.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), each function at its definition in the fork of its object (include/forks.inc).
- Section: Block processing of `beacon-chain.md` in phase0, altair, bellatrix, capella, deneb, electra and fulu, with the helpers it calls.

## Function `lantern_process_block`

process_block_header, process_withdrawals, process_execution_payload, process_randao, process_eth1_data, process_operations and process_sync_aggregate; stops at the first failed check.

### Signature

```
lantern_process_block(state, block, execution_valid, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `block` | input | `BeaconBlock` |
| `execution_valid` | input | u64: the bits under Caller must |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` or the first failed check.
- `LANTERN_BUFFER_TOO_SMALL`: scratch, or room for the body's appends, is short. Checked before any step runs.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `execution_valid`: bit 0 is the execution engine's answer to the payload, 1 valid and 0 not. Bit 1 is for block production only (beacon-api.md, produceBlockV3 with `skip_randao_verification`): no check of the RANDAO reveal's signature, and the reveal is mixed in as process_randao does.

### Function does

- Phase0: the header, RANDAO, eth1 data and operations.
- Altair and later: also the sync aggregate last.
- Bellatrix: also the execution payload after the header, when lantern_is_execution_enabled.
- Capella and later: also the withdrawals and the execution payload after the header.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(10).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_block` in the object of every fork, with `_` before it on macOS; `lantern_process_block` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `block`, `execution_valid`, `config`, `scratch`, `result`.

## Function `lantern_process_block_header`

Checks slot, proposer, parent root and that the proposer is not slashed; stores the header with a zero state root.

### Signature

```
lantern_process_block_header(state, block, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `block` | input | `BeaconBlock` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the first failed check: `LANTERN_INVALID_BLOCK_SLOT`, `LANTERN_INVALID_BLOCK_OLDER`, `LANTERN_INVALID_PROPOSER_INDEX`, `LANTERN_INVALID_VALIDATOR_INDEX`, `LANTERN_INVALID_PARENT_ROOT` or `LANTERN_INVALID_PROPOSER_SLASHED`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_block_header` in the object of every fork, with `_` before it on macOS; `lantern_process_block_header` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `block`, `config`, `scratch`, `result`.

## Function `lantern_process_withdrawals`

Checks that the payload's withdrawals are the expected ones, then applies them and moves the withdrawal indices.

### Signature

```
lantern_process_withdrawals(state, payload, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `payload` | input | `ExecutionPayload` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or `LANTERN_INVALID_WITHDRAWALS` when the payload's withdrawals are not the expected ones.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Electra and later: also drops the processed pending partial withdrawals.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_withdrawals` in the object of capella to fulu, with `_` before it on macOS; `lantern_process_withdrawals` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `payload`, `config`, `scratch`, `result`.

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

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Capella and deneb: the validator sweep, with processed_partial_withdrawals_count 0.
- Electra and later: the pending partial withdrawals, then the validator sweep.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_expected_withdrawals` in the object of capella to fulu, with `_` before it on macOS; `lantern_get_expected_withdrawals` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `out`.

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

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_pending_partial_withdrawals` in the object of electra to fulu, with `_` before it on macOS; `lantern_get_pending_partial_withdrawals` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `withdrawal_index`, `prior_withdrawals`, `scratch`, `out`.

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

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- A partial withdrawal is balance - MAX_EFFECTIVE_BALANCE in capella and deneb, and balance - lantern_get_max_effective_balance(validator) from electra on.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_validators_sweep_withdrawals` in the object of capella to fulu, with `_` before it on macOS; `lantern_get_validators_sweep_withdrawals` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `withdrawal_index`, `prior_withdrawals`, `scratch`, `out`.

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

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_balance_after_withdrawals` in the object of capella to fulu, with `_` before it on macOS; `lantern_get_balance_after_withdrawals` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `validator_index`, `withdrawals`, `out`.

## Function `lantern_apply_withdrawals`

decrease_balance by each withdrawal.

### Signature

```
lantern_apply_withdrawals(state, withdrawals) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `withdrawals` | input | `Withdrawals` value |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_apply_withdrawals` in the object of capella to fulu, with `_` before it on macOS; `lantern_apply_withdrawals` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `withdrawals`.

## Function `lantern_update_next_withdrawal_index`

The last withdrawal's index plus 1, when there is one.

### Signature

```
lantern_update_next_withdrawal_index(state, withdrawals) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `withdrawals` | input | `Withdrawals` value |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_update_next_withdrawal_index` in the object of capella to fulu, with `_` before it on macOS; `lantern_update_next_withdrawal_index` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `withdrawals`.

## Function `lantern_update_pending_partial_withdrawals`

Drops the first processed_partial_withdrawals_count pending partial withdrawals.

### Signature

```
lantern_update_pending_partial_withdrawals(state, processed_partial_withdrawals_count) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `processed_partial_withdrawals_count` | input | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_update_pending_partial_withdrawals` in the object of electra to fulu, with `_` before it on macOS; `lantern_update_pending_partial_withdrawals` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `processed_partial_withdrawals_count`.

## Function `lantern_update_next_withdrawal_validator_index`

After a full payload, the validator after the last withdrawal; else MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP further, modulo the validator count.

### Signature

```
lantern_update_next_withdrawal_validator_index(state, withdrawals) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `withdrawals` | input | `Withdrawals` value |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_update_next_withdrawal_validator_index` in the object of capella to fulu, with `_` before it on macOS; `lantern_update_next_withdrawal_validator_index` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `withdrawals`.

## Function `lantern_is_fully_withdrawable_validator`

Execution credentials, withdrawable_epoch at most epoch, and a balance above 0.

### Signature

```
lantern_is_fully_withdrawable_validator(validator, balance, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `balance` | input | u64: Gwei |
| `epoch` | input | u64 |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always.

### Function does

- Capella and deneb: the credential check is lantern_has_eth1_withdrawal_credential; electra and later: lantern_has_execution_withdrawal_credential.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_fully_withdrawable_validator` in the object of capella to fulu, with `_` before it on macOS; `lantern_is_fully_withdrawable_validator` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `validator`, `balance`, `epoch`, `out`.

## Function `lantern_is_partially_withdrawable_validator`

Execution credentials, the maximum effective balance, and a balance above it.

### Signature

```
lantern_is_partially_withdrawable_validator(validator, balance, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `balance` | input | u64: Gwei |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always.

### Function does

- Capella and deneb: lantern_has_eth1_withdrawal_credential and MAX_EFFECTIVE_BALANCE; electra and later: lantern_has_execution_withdrawal_credential and lantern_get_max_effective_balance.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_partially_withdrawable_validator` in the object of capella to fulu, with `_` before it on macOS; `lantern_is_partially_withdrawable_validator` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `validator`, `balance`, `out`.

## Function `lantern_has_eth1_withdrawal_credential`

The first credential byte is ETH1_ADDRESS_WITHDRAWAL_PREFIX.

### Signature

```
lantern_has_eth1_withdrawal_credential(validator, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_has_eth1_withdrawal_credential` in the object of capella to fulu, with `_` before it on macOS; `lantern_has_eth1_withdrawal_credential` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `validator`, `out`.

## Function `lantern_has_execution_withdrawal_credential`

lantern_has_eth1_withdrawal_credential or lantern_has_compounding_withdrawal_credential.

### Signature

```
lantern_has_execution_withdrawal_credential(validator, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_has_execution_withdrawal_credential` in the object of electra to fulu, with `_` before it on macOS; `lantern_has_execution_withdrawal_credential` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `validator`, `out`.

## Function `lantern_is_eligible_for_partial_withdrawals`

Not exiting, an effective balance of at least MIN_ACTIVATION_BALANCE, and a balance above it.

### Signature

```
lantern_is_eligible_for_partial_withdrawals(validator, balance, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `balance` | input | u64: Gwei |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_eligible_for_partial_withdrawals` in the object of electra to fulu, with `_` before it on macOS; `lantern_is_eligible_for_partial_withdrawals` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `validator`, `balance`, `out`.

## Function `lantern_get_pending_balance_to_withdraw`

The sum of the pending partial withdrawals of validator_index.

### Signature

```
lantern_get_pending_balance_to_withdraw(state, validator_index, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `validator_index` | input | u64 |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the sum.
- `LANTERN_INVALID_OVERFLOW`: the sum leaves the Uint64 range.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_pending_balance_to_withdraw` in the object of electra to fulu, with `_` before it on macOS; `lantern_get_pending_balance_to_withdraw` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `validator_index`, `out`.

## Function `lantern_process_execution_payload`

Checks the payload's parent hash, prev_randao, timestamp, blob count and the engine's answer; stores its header.

### Signature

```
lantern_process_execution_payload(state, body, execution_valid, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `body` | input | `BeaconBlockBody` |
| `execution_valid` | input | u64: the bits under Caller must |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or the first failed check: `LANTERN_INVALID_PAYLOAD_PARENT_HASH`, `LANTERN_INVALID_PAYLOAD_PREV_RANDAO`, `LANTERN_INVALID_PAYLOAD_TIMESTAMP`, `LANTERN_INVALID_BLOB_COUNT`, or `LANTERN_INVALID_PAYLOAD` when bit 0 of `execution_valid` is 0.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- `execution_valid`: bit 0 is the execution engine's answer to the payload, 1 valid and 0 not. Bit 1 is for block production only (beacon-api.md, produceBlockV3 with `skip_randao_verification`): no check of the RANDAO reveal's signature, and the reveal is mixed in as process_randao does.

### Function does

- Bellatrix: checks the parent hash only when lantern_is_merge_transition_complete.
- Deneb and later: checks the blob count against MAX_BLOBS_PER_BLOCK in deneb, MAX_BLOBS_PER_BLOCK_ELECTRA in electra, and lantern_get_blob_parameters(epoch) from fulu on.
- The header has withdrawals_root from capella on, and blob_gas_used and excess_blob_gas from deneb on.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_execution_payload` in the object of bellatrix to fulu, with `_` before it on macOS; `lantern_process_execution_payload` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `body`, `execution_valid`, `config`, `scratch`, `result`.

## Function `lantern_is_merge_transition_complete`

Whether the state's latest execution payload header differs from the empty header.

### Signature

```
lantern_is_merge_transition_complete(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always: `out` is 1 when state.latest_execution_payload_header != ExecutionPayloadHeader(), else 0.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_merge_transition_complete` in the object of bellatrix, with `_` before it on macOS; `lantern_is_merge_transition_complete` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `out`.

## Function `lantern_is_merge_transition_block`

Whether the body holds the first payload: the merge is not complete and body.execution_payload differs from the empty payload.

### Signature

```
lantern_is_merge_transition_block(state, body, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `body` | input | `BeaconBlockBody` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always: `out` is 1 or 0.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_merge_transition_block` in the object of bellatrix, with `_` before it on macOS; `lantern_is_merge_transition_block` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `body`, `out`.

## Function `lantern_is_execution_enabled`

Whether the block runs its payload: lantern_is_merge_transition_block or lantern_is_merge_transition_complete.

### Signature

```
lantern_is_execution_enabled(state, body, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `body` | input | `BeaconBlockBody` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always: `out` is 1 or 0.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_execution_enabled` in the object of bellatrix, with `_` before it on macOS; `lantern_is_execution_enabled` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `body`, `out`.

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

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_blob_parameters` in the object of fulu, with `_` before it on macOS; `lantern_get_blob_parameters` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `epoch`, `config`, `out`.

## Function `lantern_kzg_commitment_to_versioned_hash`

VERSIONED_HASH_VERSION_KZG + sha256(kzg_commitment)[1:].

### Signature

```
lantern_kzg_commitment_to_versioned_hash(kzg_commitment, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kzg_commitment` | input | `KZGCommitment`: 48 bytes |
| `out` | output | Bytes32: the versioned hash |

### Returns

- `LANTERN_OK`, always.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_kzg_commitment_to_versioned_hash` in the object of deneb to fulu, with `_` before it on macOS; `lantern_kzg_commitment_to_versioned_hash` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `kzg_commitment`, `out`.

## Function `lantern_compute_time_at_slot`

The start of slot in seconds: (genesis_time in ms, saturated, + slot * SLOT_DURATION_MS) // 1000.

### Signature

```
lantern_compute_time_at_slot(genesis_time, slot, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `genesis_time` | input | u64: seconds |
| `slot` | input | u64 |
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the time.
- `LANTERN_INVALID_OVERFLOW`: the time in ms leaves the Uint64 range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_time_at_slot` in the object of every fork, with `_` before it on macOS; `lantern_compute_time_at_slot` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `genesis_time`, `slot`, `config`, `out`.

## Function `lantern_process_randao`

Checks the proposer's RANDAO reveal of the epoch and mixes its hash into the epoch's mix.

### Signature

```
lantern_process_randao(state, body, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `body` | input | `BeaconBlockBody` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or `LANTERN_INVALID_VALIDATOR_INDEX` or `LANTERN_INVALID_RANDAO_REVEAL`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_randao` in the object of every fork, with `_` before it on macOS; `lantern_process_randao` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `body`, `config`, `scratch`, `result`.

## Function `lantern_process_eth1_data`

Appends the body's eth1 vote and adopts it when more than half the period voted for it.

### Signature

```
lantern_process_eth1_data(state, body, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `body` | input | `BeaconBlockBody` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: eth1_data_votes has no room.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_eth1_data` in the object of every fork, with `_` before it on macOS; `lantern_process_eth1_data` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `body`, `config`, `scratch`, `result`.

## Function `lantern_process_operations`

Checks that the body holds no deposits, then applies each list of operations in spec order.

### Signature

```
lantern_process_operations(state, body, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `body` | input | `BeaconBlockBody` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_DEPOSITS` when the body's deposit count is not the expected one, `LANTERN_INVALID_OVERFLOW`, or the first failed check of an operation.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch`, or the room an operation needs in `state`, is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Phase0 to deneb: asserts len(body.deposits) == min(MAX_DEPOSITS, eth1_data.deposit_count - eth1_deposit_index).
- Electra: with limit = min(eth1_data.deposit_count, deposit_requests_start_index), asserts len(body.deposits) == min(MAX_DEPOSITS, limit - eth1_deposit_index) while eth1_deposit_index < limit, else len(body.deposits) == 0.
- Phase0 to electra: applies the deposits after the attestations.
- Fulu: asserts that the body holds no deposits.
- Capella and later: also the BLS to execution changes; electra and later: also the execution requests.
- Altair and later: get_base_reward_per_increment once for all the attestations of the body. The first attestation that reaches it computes it; the others take that value. No operation of a block changes an effective balance or an active validator of the current epoch, so the value holds for every attestation.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(10).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_operations` in the object of every fork, with `_` before it on macOS; `lantern_process_operations` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `body`, `config`, `scratch`, `result`.

## Function `lantern_process_deposit`

Checks the deposit's Merkle proof against eth1_data.deposit_root at eth1_deposit_index, steps the index and applies the deposit.

### Signature

```
lantern_process_deposit(state, deposit, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `deposit` | input | `Deposit` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_DEPOSIT` when the proof fails, or `LANTERN_INVALID_OVERFLOW`.
- `LANTERN_BUFFER_TOO_SMALL`: the validator lists have no room for a new validator, or `scratch` is short. The state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the room before any change.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_deposit` in the object of phase0 to electra, with `_` before it on macOS; `lantern_process_deposit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `deposit`, `config`, `scratch`, `result`.

## Function `lantern_apply_deposit`

Adds a validator for a new public key when its deposit signature is valid, or increases the balance of the validator with the key.

### Signature

```
lantern_apply_deposit(state, data, config, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `data` | input | `DepositData`: pubkey, withdrawal_credentials, amount and signature |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |

### Returns

- `LANTERN_OK`: the deposit is applied, or skipped for an invalid signature.
- `LANTERN_BUFFER_TOO_SMALL`: a new validator has no room in the validator lists. The state is unchanged.
- Electra: `LANTERN_BUFFER_TOO_SMALL` also when pending_deposits has no room for one more entry. The state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Phase0 to deneb: a new validator gets the deposit's amount; the validator of a known key gets its balance increased.
- Electra: a new validator starts with balance 0, and the deposit, for a known key too, goes to state.pending_deposits with slot GENESIS_SLOT.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 304 bytes on x86-64 (return address included), 304 bytes on ARM64, 304 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_apply_deposit` in the object of phase0 to electra, with `_` before it on macOS; `lantern_apply_deposit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `data`, `config`, `scratch`.

## Function `lantern_process_proposer_slashing`

Checks two different signed headers of one proposer and slot, then slashes the proposer.

### Signature

```
lantern_process_proposer_slashing(state, proposer_slashing, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `proposer_slashing` | input | `ProposerSlashing` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_PROPOSER_SLASHING`, `LANTERN_INVALID_VALIDATOR_INDEX`, or the first failed check of lantern_slash_validator.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 224 bytes on x86-64 (return address included), 224 bytes on ARM64, 224 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_proposer_slashing` in the object of every fork, with `_` before it on macOS; `lantern_process_proposer_slashing` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `proposer_slashing`, `config`, `scratch`, `result`.

## Function `lantern_process_attester_slashing`

Checks two conflicting valid indexed attestations, then slashes each slashable validator in both.

### Signature

```
lantern_process_attester_slashing(state, attester_slashing, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `attester_slashing` | input | `AttesterSlashing` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_ATTESTER_SLASHING`, or the first failed check of lantern_slash_validator.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(8).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_attester_slashing` in the object of every fork, with `_` before it on macOS; `lantern_process_attester_slashing` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `attester_slashing`, `config`, `scratch`, `result`.

## Function `lantern_process_attestation`

Checks the attestation's epochs, delay, committees and signature, sets the flags it earns, and pays the proposer.

### Signature

```
lantern_process_attestation(state, attestation, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `attestation` | input | `Attestation` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_ATTESTATION`, `LANTERN_INVALID_OVERFLOW`, or the first failed check of the functions it calls.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Phase0: checks the attestation, including data.slot + SLOTS_PER_EPOCH >= state.slot and the source against the justified checkpoint of its epoch, then appends a PendingAttestation to the list of its target epoch.
- Phase0: makes every check, the signature included, and the room check before it changes the state.
- Altair to deneb: asserts data.index < get_committee_count_per_slot, and len(aggregation_bits) == len(committee) for the committee of data.index.
- Altair to capella: also asserts state.slot <= data.slot + SLOTS_PER_EPOCH.
- Electra and later: asserts data.index == 0, and takes the committees of committee_bits, each with an attester.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 144 bytes on ARM64, 160 bytes on RISC-V.
- Scratch: S(10).
- Phase0: room for one PendingAttestation in the list of the target epoch.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_attestation` in the object of every fork, with `_` before it on macOS; `lantern_process_attestation` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `attestation`, `config`, `scratch`, `result`.

## Function `lantern_process_voluntary_exit`

Checks an active, unexited, old enough validator with no pending withdrawals and a valid signature, then starts its exit.

### Signature

```
lantern_process_voluntary_exit(state, signed_voluntary_exit, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `signed_voluntary_exit` | input | `SignedVoluntaryExit` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_VOLUNTARY_EXIT`, `LANTERN_INVALID_VALIDATOR_INDEX` or `LANTERN_INVALID_OVERFLOW`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Before deneb: the domain is get_domain(state, DOMAIN_VOLUNTARY_EXIT, voluntary_exit.epoch); deneb and later: compute_domain with CAPELLA_FORK_VERSION.
- Electra and later: also asserts get_pending_balance_to_withdraw(state, index) == 0.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 224 bytes on x86-64 (return address included), 224 bytes on ARM64, 224 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_voluntary_exit` in the object of every fork, with `_` before it on macOS; `lantern_process_voluntary_exit` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `signed_voluntary_exit`, `config`, `scratch`, `result`.

## Function `lantern_process_bls_to_execution_change`

Checks the BLS credentials and signature, then sets 0x01 credentials with the new address.

### Signature

```
lantern_process_bls_to_execution_change(state, signed_address_change, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `signed_address_change` | input | `SignedBLSToExecutionChange` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` or `LANTERN_INVALID_BLS_CHANGE`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 272 bytes on x86-64 (return address included), 272 bytes on ARM64, 272 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_bls_to_execution_change` in the object of capella to fulu, with `_` before it on macOS; `lantern_process_bls_to_execution_change` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `signed_address_change`, `config`, `scratch`, `result`.

## Function `lantern_process_deposit_request`

Appends a pending deposit of the request at the state's slot.

### Signature

```
lantern_process_deposit_request(state, deposit_request, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `deposit_request` | input | `DepositRequest` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: pending_deposits has no room.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Electra: also sets deposit_requests_start_index to the request's index while it is UNSET_DEPOSIT_REQUESTS_START_INDEX.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 288 bytes on x86-64 (return address included), 288 bytes on ARM64, 288 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_deposit_request` in the object of electra to fulu, with `_` before it on macOS; `lantern_process_deposit_request` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `deposit_request`, `config`, `scratch`, `result`.

## Function `lantern_process_withdrawal_request`

A full exit, or a partial withdrawal of a compounding validator's excess, when the request's checks hold.

### Signature

```
lantern_process_withdrawal_request(state, withdrawal_request, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `withdrawal_request` | input | `WithdrawalRequest` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or pending_partial_withdrawals has no room.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_withdrawal_request` in the object of electra to fulu, with `_` before it on macOS; `lantern_process_withdrawal_request` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `withdrawal_request`, `config`, `scratch`, `result`.

## Function `lantern_process_consolidation_request`

A switch to compounding, or a queued consolidation, when the request's checks hold.

### Signature

```
lantern_process_consolidation_request(state, consolidation_request, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `consolidation_request` | input | `ConsolidationRequest` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or pending_deposits or pending_consolidations has no room.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_consolidation_request` in the object of electra to fulu, with `_` before it on macOS; `lantern_process_consolidation_request` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `consolidation_request`, `config`, `scratch`, `result`.

## Function `lantern_is_valid_switch_to_compounding_request`

Same source and target key of an active, unexited validator with 0x01 credentials of the source address.

### Signature

```
lantern_is_valid_switch_to_compounding_request(state, consolidation_request, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `consolidation_request` | input | `ConsolidationRequest` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_valid_switch_to_compounding_request` in the object of electra to fulu, with `_` before it on macOS; `lantern_is_valid_switch_to_compounding_request` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `consolidation_request`, `out`.

## Function `lantern_switch_to_compounding_validator`

Sets the 0x02 prefix and queues the excess balance.

### Signature

```
lantern_switch_to_compounding_validator(state, index) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `index` | input | u64: a validator index |

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: pending_deposits has no room; the state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_switch_to_compounding_validator` in the object of electra to fulu, with `_` before it on macOS; `lantern_switch_to_compounding_validator` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `index`.

## Function `lantern_queue_excess_active_balance`

Moves a balance above MIN_ACTIVATION_BALANCE to a pending deposit with the infinity signature at GENESIS_SLOT.

### Signature

```
lantern_queue_excess_active_balance(state, index) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `index` | input | u64: a validator index |

### Returns

- `LANTERN_BUFFER_TOO_SMALL`: pending_deposits has no room; the state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 288 bytes on x86-64 (return address included), 288 bytes on ARM64, 288 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_queue_excess_active_balance` in the object of electra to fulu, with `_` before it on macOS; `lantern_queue_excess_active_balance` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `index`.

## Function `lantern_compute_consolidation_epoch_and_update_churn`

As lantern_compute_exit_epoch_and_update_churn, with the consolidation churn and fields.

### Signature

```
lantern_compute_consolidation_epoch_and_update_churn(state, consolidation_balance, config, scratch, out, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `consolidation_balance` | input | u64: Gwei |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64: the epoch |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `out` holds the epoch; `result` is `LANTERN_VALID` or `LANTERN_INVALID_OVERFLOW`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_consolidation_epoch_and_update_churn` in the object of electra to fulu, with `_` before it on macOS; `lantern_compute_consolidation_epoch_and_update_churn` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `consolidation_balance`, `config`, `scratch`, `out`, `result`.

## Function `lantern_process_sync_aggregate`

Checks the sync committee signature over the previous slot's block root, then pays or penalizes each member and pays the proposer.

### Signature

```
lantern_process_sync_aggregate(state, sync_aggregate, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `sync_aggregate` | input | `SyncAggregate` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_SYNC_AGGREGATE` or `LANTERN_INVALID_AGGREGATE_PUBKEYS`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- With a key cache in the config (`CONFIG_PUBKEY_CACHE`), some members signed but not all, and every participant's index below the cache's `count`: committee_indices first, then crypto_bls_fast_aggregate_verify_cached of the validators' keys at the participants' indices. It equals eth_fast_aggregate_verify of the participants' keys: at least one key, and each index's key is the member's key. Else the spec's steps.
- committee_indices: all_pubkeys.index(pubkey) of each member, from the cache's SyncIndices when they hold (lantern_sync_indices), else in one pass over the validators. The distinct member keys sit in a hash table of 2 * SYNC_COMMITTEE_SIZE slots, in the scratch the keys of the signature check used. Each key takes the first validator that has it.
- A member key that no validator has: `LANTERN_INVALID_SYNC_AGGREGATE`.
- get_base_reward_per_increment from the total of its get_total_active_balance call, with get_total_active_balance once: both calls get the same state and scratch size.
- Checks the scratch and the room of `state` before any change to `state`.
- Verifies an aggregate signature with `crypto_bls_eth_fast_aggregate_verify` of asm-crypto.
- Combines public keys with the `crypto_bls_g1_*` functions of asm-crypto.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 320 bytes on x86-64 (return address included), 320 bytes on ARM64, 320 bytes on RISC-V.
- Scratch: S(1); before fulu S(2), for lantern_get_beacon_proposer_index.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_sync_aggregate` in the object of altair to fulu, with `_` before it on macOS; `lantern_process_sync_aggregate` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `sync_aggregate`, `config`, `scratch`, `result`.

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

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_VALIDATOR_INDEX` or `LANTERN_INVALID_OVERFLOW`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- The penalty quotient is MIN_SLASHING_PENALTY_QUOTIENT in phase0, _ALTAIR in altair, _BELLATRIX from bellatrix to deneb, and _ELECTRA from electra on.
- The whistleblower quotient is WHISTLEBLOWER_REWARD_QUOTIENT before electra and _ELECTRA from electra on.
- Phase0: the proposer reward is the whistleblower reward // PROPOSER_REWARD_QUOTIENT; altair and later: * PROPOSER_WEIGHT // WEIGHT_DENOMINATOR.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch: S(1).
- Before fulu: scratch S(2), for lantern_get_beacon_proposer_index.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_slash_validator` in the object of every fork, with `_` before it on macOS; `lantern_slash_validator` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `slashed_index`, `whistleblower_index`, `config`, `scratch`, `result`.

## Function `lantern_is_slashable_attestation_data`

A double vote or a surround vote.

### Signature

```
lantern_is_slashable_attestation_data(data_1, data_2, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data_1` | input | `AttestationData` |
| `data_2` | input | `AttestationData` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_slashable_attestation_data` in the object of every fork, with `_` before it on macOS; `lantern_is_slashable_attestation_data` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `data_1`, `data_2`, `out`.

## Function `lantern_is_valid_indexed_attestation`

Non empty, sorted and unique indices, and a valid aggregate signature of their keys.

### Signature

```
lantern_is_valid_indexed_attestation(state, indexed_attestation, cache, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `indexed_attestation` | input | `IndexedAttestation` |
| `cache` | state | [`PubkeyCache`](block-processing.md#type-pubkeycache), or 0 |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`: `out` holds 1 or 0.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- `cache` is a `PubkeyCache` or 0. With 0, bls.FastAggregateVerify is crypto_bls_fast_aggregate_verify of the keys, which validates each.
- With a cache whose `count` is above the largest index: crypto_bls_fast_aggregate_verify_cached of the state's validators' keys at the attesting indices. It is an asm-crypto custom function, functionally equivalent to bls.FastAggregateVerify of those keys.
- The indexed attestation itself is the `BlsIndexList` of that call: its `attesting_indices` sit at the list's offset and count.
- With a cache whose `count` is at or below the largest index: as with no cache.
- lantern_process_attestation, lantern_on_attestation and the gossip check of an aggregate's signature (networking.md) run it as an L0 form that also takes the attestation and the `CommitteeCache` its indexed attestation came from. With both caches, that form may take the keys' sum from the cache's key sums:
- For each committee of the attestation, in order: the committee's `KeySum` plus the negated key of each member without its bit, when fewer members lack the bit than have it; else the key of each member with the bit. All by crypto_bls_g1_add, from the point at infinity, each key from its `PubkeyCache` entry.
- Then crypto_bls_verify of crypto_bls_g1_compress of the sum, the signing root and the signature. bls.FastAggregateVerify is CoreVerify of point_to_pubkey of the keys' sum, and the order of the additions does not change the point.
- A `KeySum` of status 0 is made at first use. Before, crypto_bls_fast_aggregate_verify_cached of the members whose entries do not hold their keys, with the signing root and signature, fills those entries; its result is not used.
- It takes the key sums only when they save at least `KEYSUM_MIN_SAVED` additions: present - absent - 1 for each committee whose sum it takes. A first pass over the bits counts them.
- The form verifies as above, with crypto_bls_fast_aggregate_verify_cached, when the key sums save fewer additions, the epoch has no entry, a sum has status 2, a key's entry does not hold the key, or the bits do not match the committees.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.
- Scratch: S(7): the public keys take 48 bytes each.
- The L0 form: also 24 + 8 * MAX_VALIDATORS_PER_COMMITTEE bytes at the end of scratch for the members whose entries it fills.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_valid_indexed_attestation` in the object of every fork, with `_` before it on macOS; `lantern_is_valid_indexed_attestation` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `indexed_attestation`, `cache`, `scratch`, `out`.

## Function `lantern_get_committee_indices`

The indices of the set bits of committee_bits, ascending.

### Signature

```
lantern_get_committee_indices(committee_bits, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `committee_bits` | input | `Bitvector[MAX_COMMITTEES_PER_SLOT]` |
| `out` | output | [`IndexList`](helpers.md#type-indexlist) |

### Returns

- `LANTERN_OK`, always.

### Caller must

- Give `out` room for MAX_COMMITTEES_PER_SLOT entries.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_committee_indices` in the object of electra to fulu, with `_` before it on macOS; `lantern_get_committee_indices` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `committee_bits`, `out`.

## Function `lantern_get_committee_count_per_slot`

max(1, min(MAX_COMMITTEES_PER_SLOT, active validators // SLOTS_PER_EPOCH // TARGET_COMMITTEE_SIZE)).

### Signature

```
lantern_get_committee_count_per_slot(state, epoch, cache, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `cache` | state | [`CommitteeCache`](block-processing.md#type-committeecache), or 0 |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the count.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- `cache` is a `CommitteeCache` or 0. The active validators are the `count` of its entry for the epoch, when it holds one (lantern_get_beacon_committee).

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.
- Scratch: S(1).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_committee_count_per_slot` in the object of every fork, with `_` before it on macOS; `lantern_get_committee_count_per_slot` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `epoch`, `cache`, `scratch`, `out`.

## Function `lantern_compute_committee`

indices[shuffled index] for each index from len(indices) * index // count to len(indices) * (index + 1) // count.

### Signature

```
lantern_compute_committee(indices, seed, index, count, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `indices` | input | [`IndexList`](helpers.md#type-indexlist) of validator indices |
| `seed` | input | Bytes32 |
| `index` | input | u64: the committee's index |
| `count` | input | u64: the committees |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | [`IndexList`](helpers.md#type-indexlist) |

### Returns

- `LANTERN_OK`: `out` holds the committee.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has too little room.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_committee` in the object of every fork, with `_` before it on macOS; `lantern_compute_committee` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `indices`, `seed`, `index`, `count`, `scratch`, `out`.

## Function `lantern_get_beacon_committee`

lantern_compute_committee over the epoch's active validators with its DOMAIN_BEACON_ATTESTER seed.

### Signature

```
lantern_get_beacon_committee(state, slot, index, cache, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `slot` | input | u64 |
| `index` | input | u64: the committee index |
| `cache` | state | [`CommitteeCache`](block-processing.md#type-committeecache), or 0 |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | [`IndexList`](helpers.md#type-indexlist) |

### Returns

- `LANTERN_OK`: `out` holds the committee.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.
- `LANTERN_INVALID_OVERFLOW` or `LANTERN_INVALID_SHUFFLED_INDEX`: a spec check failed.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- `cache` is a `CommitteeCache` or 0. With a cache, the committee is the slice from len(indices) * index // count to len(indices) * (index + 1) // count of the shuffled list of the epoch's entry: the entry whose `epoch`, `seed`, `decision_root` and `genesis_validators_root` are those of the state, else a new one, made with lantern_compute_shuffled_permutation of the active validators and the seed, in the place of `next`, which moves on by one. It is the committee of lantern_compute_committee: entry i is indices[compute_shuffled_index(i, len(indices), seed)].
- The decision root of epoch E: get_block_root_at_slot of the last slot of epoch E - 5, from epoch 5 on; of slot 0 before, or zero at slot 0. The active validators of E are fixed by the state at the end of epoch E - 5: an activation or an exit (initiate_validator_exit, compute_activation_exit_epoch) takes effect 1 + MAX_SEED_LOOKAHEAD epochs after the epoch that sets it. So one decision root gives one set of active validators, and with the seed and the genesis validators root, one shuffled list.
- More active validators than the cache's `validators`: no entry.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 272 bytes on x86-64 (return address included), 272 bytes on ARM64, 272 bytes on RISC-V.
- Scratch: S(2).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_beacon_committee` in the object of every fork, with `_` before it on macOS; `lantern_get_beacon_committee` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `slot`, `index`, `cache`, `scratch`, `out`.

## Function `lantern_get_attesting_indices`

The members of the attestation's committees whose aggregation bits are set, ascending and unique.

### Signature

```
lantern_get_attesting_indices(state, attestation, cache, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `attestation` | input | `Attestation` |
| `cache` | state | [`CommitteeCache`](block-processing.md#type-committeecache), or 0 |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | [`IndexList`](helpers.md#type-indexlist) |

### Returns

- `LANTERN_OK`: `out` holds the indices.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.
- `LANTERN_INVALID_ATTESTATION`: the aggregation bits do not fit the committees.
- The statuses of lantern_get_beacon_committee.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Before electra: the committee of data.index. A phase0 PendingAttestation, whose aggregation_bits and data sit where those of an Attestation are, is a valid input.
- Electra and later: the committees of committee_bits, in order.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(4).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_attesting_indices` in the object of every fork, with `_` before it on macOS; `lantern_get_attesting_indices` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `attestation`, `cache`, `scratch`, `out`.

## Function `lantern_get_indexed_attestation`

The attestation's data and signature with its sorted attesting indices.

### Signature

```
lantern_get_indexed_attestation(state, attestation, cache, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `attestation` | input | `Attestation` |
| `cache` | state | `CommitteeCache`, or 0 |
| `scratch` | scratch | `Scratch` |
| `out` | output | `IndexedAttestation` value; its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the `IndexedAttestation`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.
- The statuses of lantern_get_attesting_indices.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(4).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_indexed_attestation` in the object of every fork, with `_` before it on macOS; `lantern_get_indexed_attestation` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `attestation`, `cache`, `scratch`, `out`.

## Function `lantern_get_attestation_participation_flag_indices`

The flags of a matching source, target and head within their delays.

### Signature

```
lantern_get_attestation_participation_flag_indices(state, data, inclusion_delay, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `data` | input | `AttestationData` |
| `inclusion_delay` | input | u64 |
| `out` | output | [`IndexList`](helpers.md#type-indexlist) of flag indices |

### Returns

- `LANTERN_OK`: `out` holds the flags as an `IndexList`.
- `LANTERN_INVALID_SOURCE`: the source is not the justified checkpoint.
- `LANTERN_INVALID_BLOCK_ROOT_SLOT`: a block root is out of range.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Altair to capella: the target flag also needs inclusion_delay <= SLOTS_PER_EPOCH.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_attestation_participation_flag_indices` in the object of altair to fulu, with `_` before it on macOS; `lantern_get_attestation_participation_flag_indices` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `data`, `inclusion_delay`, `out`.

## Function `lantern_get_beacon_proposer_index`

The proposer of state.slot: state.proposer_lookahead[state.slot % SLOTS_PER_EPOCH] from fulu on; before fulu, lantern_compute_proposer_index of the active validators with the seed of the slot.

### Signature

```
lantern_get_beacon_proposer_index(state, out) -> status                 (fulu)
lantern_get_beacon_proposer_index(state, scratch, out) -> status        (before fulu)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch), before fulu only |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the proposer. Fulu always returns it.
- `LANTERN_BUFFER_TOO_SMALL`: before fulu, `scratch` has fewer than S(2) bytes.
- Before fulu, the statuses of lantern_get_seed and lantern_compute_proposer_index.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Before fulu: seed = sha256(get_seed(state, epoch, DOMAIN_BEACON_PROPOSER) + uint_to_bytes(state.slot)).

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.
- Before fulu: scratch S(2).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_beacon_proposer_index` in the object of every fork, with `_` before it on macOS; `lantern_get_beacon_proposer_index` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `scratch`, `out` before fulu; `state`, `out` in fulu.

## Function `lantern_get_set_bit_count`

The set bits of a bit vector of length bits.

### Signature

```
lantern_get_set_bit_count(bits, length, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bits` | input | bytes of a bit vector |
| `length` | input | u64: the bits of `bits` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_set_bit_count` in the object of every fork, with `_` before it on macOS; `lantern_get_set_bit_count` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `bits`, `length`, `out`.

## Function `lantern_xor`

The byte wise xor of two Bytes32.

### Signature

```
lantern_xor(bytes_1, bytes_2, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes_1` | input | Bytes32 |
| `bytes_2` | input | Bytes32 |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`, always.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_xor` in the object of every fork, with `_` before it on macOS; `lantern_xor` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `bytes_1`, `bytes_2`, `out`.

## Function `lantern_committee_cache_size`

The bytes of a `CommitteeCache` for a number of validators.

### Signature

```
lantern_committee_cache_size(validators, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validators` | input | u64: the number of validators |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Function does

- `COMMITTEE_CACHE_FIXED` + `COMMITTEE_CACHE_ENTRIES` * (`CommitteeEntry__mem` + 24 + 8 * `validators` + `KEYSUM_BLOCK_BYTES`) bytes.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_committee_cache_size` in the object of every fork, with `_` before it on macOS; `lantern_committee_cache_size` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `validators`, `size`.

## Function `lantern_committee_cache_init`

Lays out an empty `CommitteeCache` for a number of validators.

### Signature

```
lantern_committee_cache_init(validators, cache) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validators` | input | u64: the number of validators |
| `cache` | output | [`CommitteeCache`](block-processing.md#type-committeecache), its `size` set by the caller |

### Returns

- `LANTERN_OK`: `cache` holds no entry.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `cache` is below what lantern_committee_cache_size gives.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_committee_cache_init` in the object of every fork, with `_` before it on macOS; `lantern_committee_cache_init` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `validators`, `cache`.

## Function `lantern_pubkey_cache_size`

The bytes of a `PubkeyCache` for a number of validators.

### Signature

```
lantern_pubkey_cache_size(validators, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validators` | input | u64: the number of validators |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Function does

- `PUBKEY_ENTRIES` + `CRYPTO_BLS_ENTRY_BYTES` * `validators` bytes (asm-crypto `include/bls12381.inc`): the fixed fields, the [`SigTable`](#type-sigtable), the SyncIndices, then the entries.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_pubkey_cache_size` in the object of every fork, with `_` before it on macOS; `lantern_pubkey_cache_size` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `validators`, `size`.

## Function `lantern_pubkey_cache_init`

Lays out an empty `PubkeyCache` for a number of validators.

### Signature

```
lantern_pubkey_cache_init(validators, cache) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validators` | input | u64: the number of validators |
| `cache` | output | [`PubkeyCache`](block-processing.md#type-pubkeycache), its `size` set by the caller |

### Returns

- `LANTERN_OK`: `key_stride` is `Validator__mem`, `offset` is `PUBKEY_ENTRIES`, `count` is `validators`, the SigTable at `PUBKEY_SIGS` is empty (`used` 0, `room` `SIG_TABLE_BYTES` - 16), the SyncIndices hold none (`valid` 0), and every entry's `status` is 0.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `cache` is below what lantern_pubkey_cache_size gives.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_pubkey_cache_init` in the object of every fork, with `_` before it on macOS; `lantern_pubkey_cache_init` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `validators`, `cache`.

## Function `lantern_attestation_memo`

process_attestation, with one get_base_reward_per_increment shared by the attestations of a block.

### Signature

```
lantern_attestation_memo(state, attestation, config, scratch, result, memo) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `attestation` | input | `Attestation` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |
| `memo` | state | u64: get_base_reward_per_increment of `state`, or 0 |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_ATTESTATION`, `LANTERN_INVALID_OVERFLOW`, or the first failed check of the functions it calls.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `memo` holds 0, or get_base_reward_per_increment of `state` as it is now.
- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Does what lantern_process_attestation does.
- Takes get_base_reward_per_increment(state) from `memo` when it is not 0; else computes it and stores it in `memo`.
- The operations of one block change no effective balance and no active validator of the current epoch, so the attestations of a block share one value.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 304 bytes on x86-64 (return address included), 288 bytes on ARM64, 288 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_attestation_memo`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `attestation`, `config`, `scratch`, `result`, `memo`.

## Function `lantern_indexed_attestation_valid`

is_valid_indexed_attestation, with the sum of the keys from the key sums of a committee cache when it can.

### Signature

```
lantern_indexed_attestation_valid(state, indexed_attestation, cache, scratch, out, attestation, committees) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `indexed_attestation` | input | `IndexedAttestation` |
| `cache` | state | [`PubkeyCache`](#type-pubkeycache), or 0 |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64: 1 or 0 |
| `attestation` | input | `Attestation` of which `indexed_attestation` is get_indexed_attestation, or 0 |
| `committees` | state | [`CommitteeCache`](#type-committeecache), or 0 |

### Returns

- `LANTERN_OK`: `out` holds 1 or 0.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.
- `LANTERN_INVALID_VALIDATOR_INDEX`: an index names no validator of `state`.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Gives what lantern_is_valid_indexed_attestation gives.
- With `attestation`, `committees` and `cache` not 0, the sum of the keys may come from the key sums of `committees` (lantern_attestation_key_sum).
- With `cache` not 0 and an entry of every index: first the SigTable's answer (lantern_sig_find_indexed), when an entry holds the same keys, signing root and signature.
- Verifies a signature with `crypto_bls_verify` of asm-crypto.
- Verifies an aggregate signature with `crypto_bls_fast_aggregate_verify` of asm-crypto.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 400 bytes on x86-64 (return address included), 400 bytes on ARM64, 400 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_indexed_attestation_valid`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `indexed_attestation`, `cache`, `scratch`, `out`, `attestation`, `committees`.

## Function `lantern_attestation_key_sum`

The sum of the public keys of an attestation's attesting validators, from the key sums of a committee cache.

### Signature

```
lantern_attestation_key_sum(state, attestation, committees, cache, out, message, signature, scratch) -> found
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `attestation` | input | `Attestation` |
| `committees` | state | [`CommitteeCache`](#type-committeecache) |
| `cache` | state | [`PubkeyCache`](#type-pubkeycache) |
| `out` | output | asm-crypto `G1Point` |
| `message` | input | Bytes32: the signing root, for lantern_key_sum_make |
| `signature` | input | 96 bytes, for lantern_key_sum_make |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch), for lantern_key_sum_make |

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Returns 1 when `out` holds the sum, else 0.
- Takes the key sum of each committee of the attestation from its [`KeySum`](#type-keysum), making it with lantern_key_sum_make when it has status 0.
- For each committee: takes its key sum less the keys of the absent members when that takes fewer additions, else adds the keys of the present members.
- Uses the key sums only when they save at least `KEYSUM_MIN_SAVED` additions.
- Combines public keys with the `crypto_bls_g1_*` functions of asm-crypto.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 928 bytes on x86-64 (return address included), 896 bytes on ARM64, 928 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_attestation_key_sum`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `attestation`, `committees`, `cache`, `out`, `message`, `signature`, `scratch`.

## Function `lantern_key_sum_make`

Makes the KeySum of a committee.

### Signature

```
lantern_key_sum_make(sum, members, count, validators, cache, message, signature, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `sum` | output | [`KeySum`](#type-keysum) |
| `members` | input | the u64 validator indices of the committee |
| `count` | input | u64: the members |
| `validators` | input | the validators of the state |
| `cache` | state | [`PubkeyCache`](#type-pubkeycache) |
| `message` | input | Bytes32 |
| `signature` | input | 96 bytes |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch); its last bytes take a list |

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Returns 1 when the KeySum has status 1, 2 when it has status 2, and 0 when a callee fails.
- Members whose cache entries do not hold their keys: first calls crypto_bls_fast_aggregate_verify_cached of asm-crypto with them, `message` and `signature`, which fills their entries; its answer is not used.
- Then adds the members' keys with crypto_bls_g1_add of asm-crypto, in member order, from the point at infinity.
- Combines public keys with the `crypto_bls_g1_*` functions of asm-crypto.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 576 bytes on x86-64 (return address included), 560 bytes on ARM64, 576 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_key_sum_make`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `sum`, `members`, `count`, `validators`, `cache`, `message`, `signature`, `scratch`.

## Function `lantern_key_sum_scan`

The members of a committee whose PubkeyCache entries do not hold their keys.

### Signature

```
lantern_key_sum_scan(members, count, validators, cache, list) -> number
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `members` | input | the u64 validator indices |
| `count` | input | u64 |
| `validators` | input | the validators of the state |
| `cache` | input | [`PubkeyCache`](#type-pubkeycache) |
| `list` | output | u64 entries, or 0 |

### Function does

- Returns how many members have an entry that does not hold their key; writes each to `list` when it is not 0.
- Returns -1 when a member is at or past the cache's count, or its entry has status 2 and the member's key.

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_key_sum_scan`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `members`, `count`, `validators`, `cache`, `list`.

## Function `lantern_committee_find`

The entry of a CommitteeCache for an epoch and a key.

### Signature

```
lantern_committee_find(cache, epoch, key) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `cache` | input | [`CommitteeCache`](#type-committeecache) |
| `epoch` | input | u64 |
| `key` | input | 96 bytes: as lantern_committee_key gives |

### Function does

- Returns the valid [`CommitteeEntry`](#type-committeeentry) of `epoch` whose 96 bytes from `seed` equal `key`, or 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_committee_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `cache`, `epoch`, `key`.

## Function `lantern_committee_key`

The key of an epoch's shuffling in a CommitteeCache.

### Signature

```
lantern_committee_key(state, epoch, key) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `key` | output | 96 bytes |

### Returns

- `LANTERN_OK`: `key` holds the key.
- The statuses of lantern_get_seed.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Writes get_seed(state, epoch, DOMAIN_BEACON_ATTESTER), then the decision root, then the state's genesis_validators_root.
- The decision root is the block root at the last slot of epoch `epoch` - 5, or at slot 0 for epochs below 5.
- Writes zero bytes for the decision root when that slot is not before the state's slot, or is more than `SLOTS_PER_HISTORICAL_ROOT` slots before it.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_committee_key`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `epoch`, `key`.

## Function `lantern_find_pubkey`

The index of the validator with a public key.

### Signature

```
lantern_find_pubkey(state, pubkey) -> index
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `pubkey` | input | 48 bytes; 4-aligned on RISC-V |

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Returns the index of the first validator whose pubkey is `pubkey`, or -1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_find_pubkey`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on x86-64: rax, rcx, rdx, r8, r9 and xmm0 to xmm4.
- Argument order: `state`, `pubkey`.

## Function `lantern_sync_indices`

lantern_find_pubkeys, with the SyncIndices of a PubkeyCache.

### Signature

```
lantern_sync_indices(state, pubkeys, out, table, cache) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `pubkeys` | input | `SYNC_COMMITTEE_SIZE` keys of 48 bytes |
| `out` | output | `SYNC_COMMITTEE_SIZE` u64 entries |
| `table` | scratch | the `table` of lantern_find_pubkeys |
| `cache` | state | [`PubkeyCache`](#type-pubkeycache), or 0 |

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Returns what lantern_find_pubkeys returns, and `out` the same.
- With `cache` and its SyncIndices `valid`: when each index k names a validator of `state` whose pubkey is key k, byte for byte, `out` takes the SyncIndices, with no pass over the validators.
- That is lantern_find_pubkeys's `out`: the pubkeys of a state's validators are distinct (a deposit of a key that a validator has tops up that validator), so the one validator with key k is the first.
- Else lantern_find_pubkeys; when it returns 0 and `cache` is not 0, its `out` becomes the SyncIndices, `valid` 1.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.
- Time: with SyncIndices that hold, `SYNC_COMMITTEE_SIZE` compares of 48 bytes, not a pass over the validators.

### ABI

- Role: L0.
- Symbol: `lantern_sync_indices`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `pubkeys`, `out`, `table`, `cache`.

## Function `lantern_find_pubkeys`

all_pubkeys.index(pubkey) for each key of a sync committee.

### Signature

```
lantern_find_pubkeys(state, pubkeys, out, table) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `pubkeys` | input | `SYNC_COMMITTEE_SIZE` keys of 48 bytes |
| `out` | output | `SYNC_COMMITTEE_SIZE` u64 entries |
| `table` | scratch | `SYNC_TABLE_BYTES` bytes; on x86-64 3 more words after them |

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Returns 0 when `out` holds, for each key, the first validator with that key; -1 when a key is missing.
- Makes one pass over the validators, with the distinct keys in a hash table at `table`.

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_find_pubkeys`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x4 to x7, x9 to x17; rax, rdi, r8 to r11, xmm0 to xmm5; a0, a4 to a7, t0 to t6.
- Argument order: `state`, `pubkeys`, `out`, `table`.

## Function `lantern_append_pending_deposit`

Appends a PendingDeposit to a state.

### Signature

```
lantern_append_pending_deposit(state, deposit) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `deposit` | input | `PendingDeposit` |

### Returns

- `LANTERN_OK`: `state.pending_deposits` holds the deposit at its end.
- `LANTERN_BUFFER_TOO_SMALL`: `pending_deposits` has no room; `state` is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_append_pending_deposit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `deposit`.

## Function `lantern_append_withdrawal`

Appends a Withdrawal to a Withdrawals value.

### Signature

```
lantern_append_withdrawal(withdrawals, index, validator_index, validator, amount)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `withdrawals` | state | `Withdrawals` value |
| `index` | input | u64 in a register |
| `validator_index` | input | u64 in a register |
| `validator` | input | `Validator` |
| `amount` | input | u64 in a register |

### Caller must

- `withdrawals` has room for one more entry.

### Function does

- Appends Withdrawal(index, validator_index, the execution address of `validator`'s withdrawal credentials, amount).

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_append_withdrawal`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `withdrawals`, `index`, `validator_index`, `validator`, `amount`.

## Function `lantern_concat_withdrawals`

The list all = prior + new, for get_balance_after_withdrawals.

### Signature

```
lantern_concat_withdrawals(all, prior, new)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `all` | output | `Withdrawals` value |
| `prior` | input | `Withdrawals` value |
| `new` | input | `Withdrawals` value |

### Caller must

- `all` has room for the entries of both.

### Function does

- Writes the entries of `prior`, then those of `new`, into `all`.

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_concat_withdrawals`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0 to x3, x9 to x12; rax, rcx, rdi, rsi, r8; a0 to a3, t0 to t3.
- Argument order: `all`, `prior`, `new`.

## Function `lantern_all_zero`

Whether bytes are all zero.

### Signature

```
lantern_all_zero(bytes, n) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `n` bytes |
| `n` | input | u64 in a register |

### Function does

- Returns 1 when the `n` bytes are all zero, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_all_zero`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `bytes`, `n`.

## Function `lantern_build_payload_header`

The ExecutionPayloadHeader of an execution payload, for lantern_process_execution_payload.

### Signature

```
lantern_build_payload_header(header, payload, scratch, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | output | `ExecutionPayloadHeader` |
| `payload` | input | `ExecutionPayload` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch), whose last `HEADER_ROOM` bytes hold `header` |
| `size` | input | u64: the size of `scratch` |

### Returns

- `LANTERN_OK`: `header` holds the header.
- The statuses of ssz_hash_tree_root of asm-ssz.

### Caller must

- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Copies the fixed fields and writes transactions_root and withdrawals_root (from capella) as hash_tree_root of their lists.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_build_payload_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- ARM64 and RISC-V take `payload`, `scratch` and `size` from the registers of lantern_process_execution_payload: x25, x23, x27; s7, s5, s9. x86-64 takes them in rsi, rdx and rcx.
- It saves the callee saved registers it uses.
- Argument order: `header`, `payload`, `scratch`, `size`.

## Function `lantern_check_header_signature`

Checks the signature of a signed block header of a proposer slashing.

### Signature

```
lantern_check_header_signature(locals) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `locals` | state | the locals of lantern_process_proposer_slashing: +8 epoch, +16 domain type, +24 domain, +56 the signing root as a ByteList |

### Returns

- 0: the signature holds.
- `LANTERN_INVALID_PROPOSER_SLASHING`: it does not.
- The statuses of lantern_get_domain and lantern_compute_signing_root.

### Function does

- Checks the signature of the signed header by the proposer with DOMAIN_BEACON_PROPOSER at the header's epoch, through lantern_verify_root_signature.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_check_header_signature`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the signed header in x25, rsi, s7; the proposer in x24, r15, s6; the state in x19, rbx, s1; the scratch in x22, r13, s4.
- Argument order: `locals`.

## Function `lantern_randao_step`

process_randao, with or without the check of the reveal's signature.

### Signature

```
lantern_randao_step(state, body, config, scratch, result, skip) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `body` | input | `BeaconBlockBody` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |
| `skip` | input | u64 in a register: 1 for block production with `skip_randao_verification`, else 0 |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_VALIDATOR_INDEX` or `LANTERN_INVALID_RANDAO_REVEAL`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- With `skip` 0: does what process_randao does.
- With `skip` 1: makes no check of the reveal's signature, and mixes the reveal in as process_randao does.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 272 bytes on x86-64 (return address included), 272 bytes on ARM64, 272 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_randao_step`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `body`, `config`, `scratch`, `result`, `skip`.

## Function `lantern_sort_u64`

Sorts u64 entries ascending.

### Signature

```
lantern_sort_u64(entries, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entries` | state | `n` u64 entries |
| `n` | input | u64 in a register |

### Function does

- Sorts the entries ascending, with heapsort.

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_sort_u64`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x2 to x8; rax, rcx, rdx, r8 to r11; a2 to a4, t0 to t4.
- Argument order: `entries`, `n`.

## Function `lantern_validator_room`

The fewest free entries in the validator lists of a state.

### Signature

```
lantern_validator_room(state) -> entries
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Returns the fewest free entries among the validator lists of `state`.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_validator_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`.

## Function `lantern_verify_root_signature`

Verifies a BLS signature over a signing root.

### Signature

```
lantern_verify_root_signature(pubkey, signature, root, scratch) -> (status, valid)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pubkey` | input | 48 bytes |
| `signature` | input | 96 bytes |
| `root` | state | 56 bytes, 8-aligned: the last 32 hold the root; the first 24 become a ByteList header |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- The status of crypto_bls_verify of asm-crypto.

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Writes a ByteList header in the first 24 bytes of `root` and calls crypto_bls_verify with it.
- Returns the status, then 1 when the signature holds, else 0.
- Verifies a signature with `crypto_bls_verify` of asm-crypto.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_verify_root_signature`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `pubkey`, `signature`, `root`, `scratch`.

## Function `lantern_block_sigs`

Before process_block, the signature checks of the block's attestations at once on the pool, into the PubkeyCache's SigTable.

### Signature

```
lantern_block_sigs(state, block, config, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState`: the state process_block takes |
| `block` | input | `BeaconBlock` |
| `config` | input | `Config` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- `LANTERN_OK`, always.

### Function does

- With a PubkeyCache at `CONFIG_PUBKEY_CACHE`, a StateCache whose `pool` has workers, and 2 or more attestations in the block: else nothing.
- Keeps at the end of `scratch` a [`BlockSigs`](#type-blocksigs) record, the job scratches, a pair of each entry and an IndexedAttestation of each attestation, sized by its bits; and leaves the front, of `LANTERN_SCRATCH_FIXED` bytes at least, to its callees.
- For each attestation, in block order: lantern_get_indexed_attestation; with some indices, each below the cache's count and the state's validators, and room in the SigTable for its entry: lantern_block_sig_keys, then lantern_block_sig_entry into the next entry. An attestation where a step fails gets no entry.
- With 2 or more entries: sorts the pairs by the keys of their entries, most first (an insertion sort, which keeps the order of equal ones), sets `next` to 0, then lantern_shell_pool_run of the lower of the entries and the jobs (the workers + 1, at most `BLOCK_SIG_JOBS`) jobs of lantern_block_sig_job.
- Each check of process_block then reads the SigTable (lantern_indexed_attestation_valid): an entry answers only a check of the same keys, message and signature, so every result is the one of a check of its own.
- Gives `scratch` its `size` back.

### Function never

- Makes an OS call other than through lantern_shell_pool_run.
- Changes `state` or `block`.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 208 bytes on x86-64 (return address included), 208 bytes on ARM64, 208 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_block_sigs`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `block`, `config`, `scratch`.

## Function `lantern_block_sig_keys`

Fills the PubkeyCache entries of some indices that do not hold their keys, so that later checks only read them.

### Signature

```
lantern_block_sig_keys(keys, indices, count, cache) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `keys` | input | key i: the 48 bytes at `keys` + 128 i: the pubkeys of a state's validators |
| `indices` | input | u64 each |
| `count` | input | u64 |
| `cache` | state | [`PubkeyCache`](#type-pubkeycache) |

### Returns

- 0: each entry holds its key.
- The status of crypto_bls_key_cache_fill when it is not 0.

### Caller must

- Pass indices below the cache's count.

### Function does

- For each index whose entry has status 0 or another key: crypto_bls_key_cache_fill of asm-crypto of that one index.
- So afterwards each index's entry has a status other than 0 and the same key: crypto_bls_fast_aggregate_verify_cached of those indices writes no entry, and calls of it may run at once.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_block_sig_keys`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `keys`, `indices`, `count`, `cache`.

## Function `lantern_block_sig_entry`

The SigEntry of the check that is_valid_indexed_attestation makes of an indexed attestation.

### Signature

```
lantern_block_sig_entry(state, indexed_attestation, entry, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `indexed_attestation` | input | `IndexedAttestation` |
| `entry` | output | [`SigEntry`](#type-sigentry) with room for its keys |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- `LANTERN_OK`: `entry` is written.
- The statuses of lantern_get_domain and lantern_compute_signing_root.

### Caller must

- Pass indices that name validators of `state`.

### Function does

- Its message: compute_signing_root of the data under get_domain(state, `DOMAIN_BEACON_ATTESTER`, data.target.epoch).
- Its keys: the pubkeys of the state's validators of the attesting indices, in order; its signature: the indexed attestation's; `valid` `SIG_UNKNOWN`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_block_sig_entry`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `indexed_attestation`, `entry`, `scratch`.

## Function `lantern_block_sig_job`

A job of lantern_block_sigs: the checks of its share of the block's entries.

### Signature

```
lantern_block_sig_job(record, index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `record` | state | [`BlockSigs`](#type-blocksigs) |
| `index` | input | u64 in a register: the job |

### Function does

- Takes pairs j from `next` (an atomic add of 1: `ldaxr` and `stlxr` on ARM64, `lock xadd` on x86-64, `amoadd.d` on RISC-V) while j is below `count`, so each pair goes to one job and a job that ends early takes more. For each: crypto_bls_fast_aggregate_verify_cached of asm-crypto of the keys of its IndexedAttestation's indices, the entry's message and signature, with the record's PubkeyCache and the job's own scratch, into the entry's `valid`.
- Reads the cache only: lantern_block_sig_keys filled each entry it reads.

### Function never

- Makes an OS call.
- Writes outside the `valid` of the entries it takes, `next` and its scratch.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_block_sig_job`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- A ShellJob function (shell.md): its status is not read.
- Argument order: `record`, `index`.

## Type `PubkeyCache`

The checked public key of each validator index: asm-crypto's [`BlsKeyCache`](https://github.com/bitminetech/asm-crypto/blob/0f80dd746dfa7a561610165065b9473e4d16a0ce/docs/reference/bls-signatures.md#type-blskeycache), whose keys are a state's validators' pubkeys.

### Rules

- `key_stride` is `Validator__mem`; `offset` is `PUBKEY_ENTRIES`; `count` is the number of validator indices it holds.
- Between its fixed fields and its entries, at `PUBKEY_SIGS` (`CRYPTO_BLS_CACHE_FIXED`), a [`SigTable`](#type-sigtable) of `SIG_TABLE_BYTES` (32 MiB: the entries of a block of 8 attestations of every committee of a slot, about 1.8 MB each at 1.2M validators, and a step's gossip): asm-crypto reads only the fixed fields and the entries.
- After the SigTable, at `PUBKEY_SYNC`, `PUBKEY_SYNC_BYTES` bytes of SyncIndices: a u64 `valid` (1 when they hold indices), then `SYNC_COMMITTEE_SIZE` u64 validator indices: the last indices lantern_sync_indices found. Then, at `PUBKEY_ENTRIES`, the entries.
- Only crypto_bls_fast_aggregate_verify_cached writes its entries, after lantern_pubkey_cache_init empties them.
- An entry answers only for the key of its 48 bytes, so one cache serves states of any chain.

## Type `BlockSigs`

The record of the jobs of lantern_block_sigs, at the end of its scratch.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `table` | u64 | The SigTable |
| 8 | `jobs` | u64 | The jobs n |
| 16 | `keys` | u64 | The pubkey of the state's first validator: key i at + 128 i |
| 24 | `cache` | u64 | The PubkeyCache |
| 32 | `count` | u64 | The entries |
| 40 | `pairs` | u64 | The address of the pairs: (entry, IndexedAttestation) of each entry, 16 bytes each, most keys first |
| 48 | `next` | u64 | The next pair a job takes: a counter the jobs add 1 to atomically |
| 56 | `scratch` | n x `BLOCK_SIG_SCRATCH` bytes | A scratch of each job |

## Type `SigTable`

Checked signatures: entries of the result of a BLS signature check with its whole inputs, which a check of the same inputs takes in place of a pairing.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `used` | u64 | Bytes of its entries |
| 8 | `room` | u64 | Bytes it has for entries |
| 16 | `entries` | [`SigEntry`](#type-sigentry) back to back | |

### Rules

- At `PUBKEY_SIGS` of a [`PubkeyCache`](#type-pubkeycache), `SIG_TABLE_BYTES` bytes in all.
- An entry answers a check only when its keys, its message and its signature are those of the check, byte for byte, and its `valid` is 0 or 1: the answer is then the check's result, since `crypto_bls_verify` and the other checks of asm-crypto are functions of those bytes.
- lantern_app_sigs empties it before the actions of each step and fills it; the checks of the step read it.
- lantern_block_sigs adds the entries of a block's attestations before process_block, and lantern_state_transition gives `used` back after it.

## Type `SigEntry`

One checked signature of a `SigTable`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `valid` | u64 | 1 or 0, the check's result; `SIG_UNKNOWN` (2) while not checked |
| 8 | `keys` | u64 | The keys k |
| 16 | `message` | ByteList | A header of 24 bytes (56, 24, 32), then the 32 bytes of the message: a signing root |
| 72 | `signature` | BLSSignature | 96 bytes |
| 168 | `key` | BLSPubkey x k | The keys, 48 bytes each |

### Rules

- 168 + 48 k bytes; `SIG_ENTRY_ONE` (216) for one key.

## Type `CommitteeCache`

The shuffled active validators of a few epochs, from states of one chain.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this field included |
| 8 | `validators` | u64 | The active validators an entry holds at most |
| 16 | `next` | u64 | The entry the next new shuffling takes |
| 24 | `entries` | [`CommitteeEntry`](#type-committeeentry) × `COMMITTEE_CACHE_ENTRIES` | Each followed by its list: an `IndexList` of 24 + 8 * `validators` bytes |
| after the entries | `key_sums` | `KEYSUM_BLOCK_BYTES` × `COMMITTEE_CACHE_ENTRIES` | Block i: the [`KeySum`](#type-keysum) of each committee of entry i |

### Rules

- The caller keeps the states of one chain on a cache: states that only the state transition changed, from one anchor.
- A block holds `SLOTS_PER_EPOCH` * `MAX_COMMITTEES_PER_SLOT` sums of `KeySum__mem` (152) bytes. Sum k is that of committee k of the epoch: index (slot % SLOTS_PER_EPOCH) * committees_per_slot + committee index, as in compute_committee.
- A new shuffling in an entry sets each `status` of its block to 0.

## Type `CommitteeEntry`

One epoch's shuffling in a `CommitteeCache`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `valid` | u64 | 1 when it holds a shuffling |
| 8 | `epoch` | u64 | The epoch |
| 16 | `count` | u64 | The epoch's active validators |
| 24 | `seed` | Bytes32 | get_seed of the epoch with DOMAIN_BEACON_ATTESTER |
| 56 | `decision_root` | Bytes32 | The decision root of the epoch |
| 88 | `genesis_validators_root` | Bytes32 | Of the state |
| 120 | (padding) | u64 | Up to `CommitteeEntry__mem` |

### Rules

- `CommitteeEntry__mem` (128) bytes, then its list.

## Type `KeySum`

The sum of one committee's public keys in a `CommitteeCache`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `status` | u64 | 0 not made; 1 made; 2 it cannot be made |
| 8 | `point` | asm-crypto `G1Point` | With status 1: the sum of the members' public keys |

### Rules

- Status 1: the point is crypto_bls_g1_add of the members' keys, in member order, from the point at infinity. Each key is the point of its `PubkeyCache` entry, of status 1 and of the 48 bytes of the validator's pubkey.
- Status 2: a member's index is at or past the `PubkeyCache` count, or its entry has status 2 and the 48 bytes of its pubkey.
- A sum holds for each state that finds the entry: the members are active in the entry's epoch, so each was in the registry at the decision root, and a validator's pubkey never changes.

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

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/operations/<handler>/` of each fork, for mainnet and minimal.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.
  - Cases with `bls_setting` 2 were made with signature checks turned off. `runner-<preset>` skips them; `runner-<preset>-bls-off` runs only them, with the three asm-crypto signature checks replaced by tests/runner/bls_off.c as in the spec's test mode.
- Each runner process keeps one `PubkeyCache` of lantern_pubkey_cache_size(4096), named at `CONFIG_PUBKEY_CACHE` of every call's config; `runner-<preset>-bls-off` names none, as the spec's tests with signatures off check no key.
- Each runner process keeps one `CommitteeCache` of lantern_committee_cache_size(4096); the config of every call names it at `CONFIG_COMMITTEE_CACHE`, and lantern_committee_cache_init empties it before each case, so the states of one case are those of one chain.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_process_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_block_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_expected_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_pending_partial_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_validators_sweep_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_balance_after_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_apply_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_update_next_withdrawal_index`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_update_pending_partial_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_update_next_withdrawal_validator_index`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_fully_withdrawable_validator`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_partially_withdrawable_validator`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_has_eth1_withdrawal_credential`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_has_execution_withdrawal_credential`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_eligible_for_partial_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_pending_balance_to_withdraw`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_execution_payload`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_is_merge_transition_complete`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_merge_transition_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_execution_enabled`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_blob_parameters`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_kzg_commitment_to_versioned_hash`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_time_at_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_randao`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_eth1_data`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_operations`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_deposit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_apply_deposit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_proposer_slashing`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_attester_slashing`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_attestation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_voluntary_exit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_bls_to_execution_change`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_deposit_request`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_withdrawal_request`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_consolidation_request`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_is_valid_switch_to_compounding_request`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_switch_to_compounding_validator`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_queue_excess_active_balance`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_consolidation_epoch_and_update_churn`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_process_sync_aggregate`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_slash_validator`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_slashable_attestation_data`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_valid_indexed_attestation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_committee_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_committee_count_per_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_committee`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_beacon_committee`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_attesting_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_indexed_attestation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_attestation_participation_flag_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_beacon_proposer_index`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_set_bit_count`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_xor`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_committee_cache_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_committee_cache_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_pubkey_cache_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_pubkey_cache_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_attestation_memo`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_indexed_attestation_valid`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_attestation_key_sum`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_key_sum_make`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_key_sum_scan`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_committee_find`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_committee_key`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_find_pubkey`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_find_pubkeys`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_append_pending_deposit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_append_withdrawal`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_concat_withdrawals`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_all_zero`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_build_payload_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_check_header_signature`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_randao_step`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_sort_u64`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_validator_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_verify_root_signature`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
