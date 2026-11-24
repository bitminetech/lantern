# Beacon chain helpers

## Contents

### Functions

- [`lantern_integer_squareroot`](#function-lantern_integer_squareroot): the integer square root.
- [`lantern_saturating_sub`](#function-lantern_saturating_sub): a minus b, or 0.
- [`lantern_is_active_validator`](#function-lantern_is_active_validator): whether a validator is active in an epoch.
- [`lantern_is_eligible_for_activation_queue`](#function-lantern_is_eligible_for_activation_queue): whether a validator may join the activation queue.
- [`lantern_is_eligible_for_activation`](#function-lantern_is_eligible_for_activation): whether a validator may be activated.
- [`lantern_is_slashable_validator`](#function-lantern_is_slashable_validator): whether a validator may be slashed in an epoch.
- [`lantern_is_compounding_withdrawal_credential`](#function-lantern_is_compounding_withdrawal_credential): whether credentials have the compounding prefix.
- [`lantern_has_compounding_withdrawal_credential`](#function-lantern_has_compounding_withdrawal_credential): whether a validator has compounding credentials.
- [`lantern_get_max_effective_balance`](#function-lantern_get_max_effective_balance): the most effective balance a validator may have.
- [`lantern_compute_epoch_at_slot`](#function-lantern_compute_epoch_at_slot): the epoch of a slot.
- [`lantern_compute_start_slot_at_epoch`](#function-lantern_compute_start_slot_at_epoch): the first slot of an epoch.
- [`lantern_compute_activation_exit_epoch`](#function-lantern_compute_activation_exit_epoch): the epoch when an activation or exit takes effect.
- [`lantern_is_valid_merkle_branch`](#function-lantern_is_valid_merkle_branch): checks a Merkle branch.
- [`lantern_get_current_epoch`](#function-lantern_get_current_epoch): the epoch of the state.
- [`lantern_get_previous_epoch`](#function-lantern_get_previous_epoch): the epoch before, or 0.
- [`lantern_get_block_root_at_slot`](#function-lantern_get_block_root_at_slot): a recent block root by slot.
- [`lantern_get_block_root`](#function-lantern_get_block_root): the block root at the start of an epoch.
- [`lantern_get_randao_mix`](#function-lantern_get_randao_mix): the RANDAO mix of an epoch.
- [`lantern_get_active_validator_indices`](#function-lantern_get_active_validator_indices): the active validators of an epoch.
- [`lantern_get_total_balance`](#function-lantern_get_total_balance): the sum of effective balances of a set.
- [`lantern_get_total_active_balance`](#function-lantern_get_total_active_balance): the sum of effective balances of the active validators.
- [`lantern_increase_balance`](#function-lantern_increase_balance): adds to a balance.
- [`lantern_decrease_balance`](#function-lantern_decrease_balance): subtracts from a balance, down to 0.
- [`lantern_has_flag`](#function-lantern_has_flag): whether a participation flag is set.
- [`lantern_add_flag`](#function-lantern_add_flag): sets a participation flag.
- [`lantern_get_finality_delay`](#function-lantern_get_finality_delay): epochs since finality.
- [`lantern_is_in_inactivity_leak`](#function-lantern_is_in_inactivity_leak): whether the chain leaks.
- [`lantern_get_eligible_validator_indices`](#function-lantern_get_eligible_validator_indices): the validators that get rewards and penalties.
- [`lantern_get_unslashed_participating_indices`](#function-lantern_get_unslashed_participating_indices): the unslashed active validators with a flag.
- [`lantern_get_base_reward_per_increment`](#function-lantern_get_base_reward_per_increment): the base reward of one balance increment.
- [`lantern_get_base_reward`](#function-lantern_get_base_reward): the base reward of a validator.

- [`lantern_compute_shuffled_permutation`](#function-lantern_compute_shuffled_permutation): the swap or not shuffle of 0 to index_count - 1.
- [`lantern_compute_shuffled_index`](#function-lantern_compute_shuffled_index): where one index lands in the shuffle.
- [`lantern_get_seed`](#function-lantern_get_seed): the seed of an epoch for a domain type.
- [`lantern_compute_proposer_index`](#function-lantern_compute_proposer_index): picks one proposer, weighted by effective balance.
- [`lantern_compute_proposer_indices`](#function-lantern_compute_proposer_indices): the proposers of each slot of an epoch.
- [`lantern_get_beacon_proposer_indices`](#function-lantern_get_beacon_proposer_indices): the proposers of an epoch from the state.
- [`lantern_compute_fork_data_root`](#function-lantern_compute_fork_data_root): the root of a ForkData.
- [`lantern_compute_domain`](#function-lantern_compute_domain): a signature domain.
- [`lantern_get_domain`](#function-lantern_get_domain): the domain of the state's fork for an epoch.
- [`lantern_compute_signing_root`](#function-lantern_compute_signing_root): the root that a signature signs.

### Types

- [`Config`](#type-config): the run time config values.
- [`Scratch`](#type-scratch): work memory.
- [`IndexList`](#type-indexlist): a list of u64 numbers.
- [`Result`](#type-result): the outcome of the spec checks of a function that changes a state.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), each function at its definition in the fork of its object (include/forks.inc).
- Section: Helper functions of `beacon-chain.md` in phase0, altair, electra and fulu.

## Common rules

- Each argument is a pointer. A Uint64 argument points at a u64; a Boolean output is a u64 of 0 or 1.
- Each function returns its status in the ABI integer return register: `LANTERN_OK`, `LANTERN_BUFFER_TOO_SMALL`, or the `LANTERN_INVALID_*` code of a failed spec check (include/lantern.inc).
- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- A function never makes an OS call and never keeps a pointer after it returns.
- Role: L1. Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Forks: the state transition is in the object of every fork. A function says under Function does what the forks change, and under ABI the forks that have it when not all do.
- Symbol: `lantern_<fork>_<name>` for the function `lantern_<name>`, in the object of each fork that the core builds (`FORKS` in platform/objects.sh), with `_` before it on macOS. Calls inside an object use its local label `lantern_<name>`.

## Function `lantern_integer_squareroot`

The largest x with x * x at most n.

### Signature

```
lantern_integer_squareroot(n, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `n` | input | u64 |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Function does

- Writes 4294967295 when n is 2^64 - 1, else runs the spec's Newton loop.

### ABI

- Argument order: `n`, `out`.

## Function `lantern_saturating_sub`

a - b when a > b, else 0.

### Signature

```
lantern_saturating_sub(a, b, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | u64 |
| `b` | input | u64 |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `a`, `b`, `out`.

## Function `lantern_is_active_validator`

activation_epoch <= epoch < exit_epoch.

### Signature

```
lantern_is_active_validator(validator, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `epoch` | input | u64 |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `validator`, `epoch`, `out`.

## Function `lantern_is_eligible_for_activation_queue`

activation_eligibility_epoch is FAR_FUTURE_EPOCH and effective_balance is at least MIN_ACTIVATION_BALANCE.

### Signature

```
lantern_is_eligible_for_activation_queue(validator, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`, always.

### Function does

- Before electra: effective_balance == MAX_EFFECTIVE_BALANCE; electra and later: effective_balance >= MIN_ACTIVATION_BALANCE.

### ABI

- Argument order: `validator`, `out`.

## Function `lantern_is_eligible_for_activation`

activation_eligibility_epoch is at most the finalized epoch and activation_epoch is FAR_FUTURE_EPOCH.

### Signature

```
lantern_is_eligible_for_activation(state, validator, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `validator` | input | `Validator` |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `state`, `validator`, `out`.

## Function `lantern_is_slashable_validator`

Not slashed, and activation_epoch <= epoch < withdrawable_epoch.

### Signature

```
lantern_is_slashable_validator(validator, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `epoch` | input | u64 |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `validator`, `epoch`, `out`.

## Function `lantern_is_compounding_withdrawal_credential`

The first byte of the credentials is COMPOUNDING_WITHDRAWAL_PREFIX.

### Signature

```
lantern_is_compounding_withdrawal_credential(withdrawal_credentials, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `withdrawal_credentials` | input | Bytes32 |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `withdrawal_credentials`, `out`.
- Forks: electra and later.

## Function `lantern_has_compounding_withdrawal_credential`

lantern_is_compounding_withdrawal_credential of the validator's credentials.

### Signature

```
lantern_has_compounding_withdrawal_credential(validator, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `validator`, `out`.
- Forks: electra and later.

## Function `lantern_get_max_effective_balance`

MAX_EFFECTIVE_BALANCE_ELECTRA for compounding credentials, else MIN_ACTIVATION_BALANCE.

### Signature

```
lantern_get_max_effective_balance(validator, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `validator` | input | `Validator` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `validator`, `out`.
- Forks: electra and later.

## Function `lantern_compute_epoch_at_slot`

slot // SLOTS_PER_EPOCH.

### Signature

```
lantern_compute_epoch_at_slot(slot, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `slot`, `out`.

## Function `lantern_compute_start_slot_at_epoch`

epoch * SLOTS_PER_EPOCH.

### Signature

```
lantern_compute_start_slot_at_epoch(epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `epoch` | input | u64 |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the slot.
- `LANTERN_INVALID_OVERFLOW`: the slot leaves the Uint64 range.

### ABI

- Argument order: `epoch`, `out`.

## Function `lantern_compute_activation_exit_epoch`

epoch + 1 + MAX_SEED_LOOKAHEAD.

### Signature

```
lantern_compute_activation_exit_epoch(epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `epoch` | input | u64 |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the epoch.
- `LANTERN_INVALID_OVERFLOW`: the epoch leaves the Uint64 range.

### ABI

- Argument order: `epoch`, `out`.

## Function `lantern_is_valid_merkle_branch`

Whether the leaf, hashed up with the branch for depth levels by the bits of index, gives the root.

### Signature

```
lantern_is_valid_merkle_branch(leaf, branch, depth, index, root, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `leaf` | input | Bytes32 |
| `branch` | input | depth Bytes32 values |
| `depth` | input | u64 |
| `index` | input | u64 |
| `root` | input | Bytes32 |
| `out` | output | u64: 1 when valid, else 0 |

### Returns

- `LANTERN_OK`, always.

## Function `lantern_get_current_epoch`

The epoch of state.slot.

### Signature

```
lantern_get_current_epoch(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `state`, `out`.

## Function `lantern_get_previous_epoch`

The current epoch minus 1, or 0 in epoch 0.

### Signature

```
lantern_get_previous_epoch(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `state`, `out`.

## Function `lantern_get_block_root_at_slot`

state.block_roots[slot % SLOTS_PER_HISTORICAL_ROOT], for a slot in the recent window.

### Signature

```
lantern_get_block_root_at_slot(state, slot, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `slot` | input | u64 |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`: `out` holds the root.
- `LANTERN_INVALID_BLOCK_ROOT_SLOT`: the check slot < state.slot <= slot + SLOTS_PER_HISTORICAL_ROOT failed; `out` is unwritten.

### ABI

- Argument order: `state`, `slot`, `out`.

## Function `lantern_get_block_root`

lantern_get_block_root_at_slot at the start slot of epoch.

### Signature

```
lantern_get_block_root(state, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`: `out` holds the root.
- `LANTERN_INVALID_BLOCK_ROOT_SLOT`: the check of lantern_get_block_root_at_slot failed.

### ABI

- Argument order: `state`, `epoch`, `out`.

## Function `lantern_get_randao_mix`

state.randao_mixes[epoch % EPOCHS_PER_HISTORICAL_VECTOR].

### Signature

```
lantern_get_randao_mix(state, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `state`, `epoch`, `out`.

## Function `lantern_get_active_validator_indices`

The indices of the validators active in epoch, ascending.

### Signature

```
lantern_get_active_validator_indices(state, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `out` | output | `IndexList` |

### Returns

- `LANTERN_OK`: `out` holds the indices.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer entries than there are validators.

### Caller must

- Set `out`'s size to its buffer size.

### ABI

- Argument order: `state`, `epoch`, `out`.

## Function `lantern_get_total_balance`

The sum of the effective balances of indices, and at least EFFECTIVE_BALANCE_INCREMENT.

### Signature

```
lantern_get_total_balance(state, indices, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `indices` | input | `IndexList` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- Pass distinct indices, each below the number of validators.

### ABI

- Argument order: `state`, `indices`, `out`.

## Function `lantern_get_total_active_balance`

lantern_get_total_balance of the validators active in the current epoch.

### Signature

```
lantern_get_total_active_balance(state, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the total.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(1) bytes.

### Function does

- One pass over the validators sums the effective balances of those active in the current epoch, with get_active_validator_indices and get_total_balance inline.
- Fails with `LANTERN_BUFFER_TOO_SMALL` when the index list of every validator would not fit in the scratch after its size field, as get_active_validator_indices does.

### ABI

- Argument order: `state`, `scratch`, `out`.

## Function `lantern_increase_balance`

state.balances[index] += delta.

### Signature

```
lantern_increase_balance(state, index, delta) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `index` | input | u64 |
| `delta` | input | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- Pass an index below the number of balances.

### ABI

- Argument order: `state`, `index`, `delta`.

## Function `lantern_decrease_balance`

state.balances[index] -= delta, down to 0.

### Signature

```
lantern_decrease_balance(state, index, delta) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `index` | input | u64 |
| `delta` | input | u64 |

### Returns

- `LANTERN_OK`, always.

### Caller must

- Pass an index below the number of balances.

### ABI

- Argument order: `state`, `index`, `delta`.

## Function `lantern_has_flag`

Bit flag_index of flags is set.

### Signature

```
lantern_has_flag(flags, flag_index, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `flags` | input | ParticipationFlags, 1 byte |
| `flag_index` | input | u64, below 8 |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `flags`, `flag_index`, `out`.
- Forks: altair and later.

## Function `lantern_add_flag`

flags with bit flag_index set.

### Signature

```
lantern_add_flag(flags, flag_index, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `flags` | input | ParticipationFlags, 1 byte |
| `flag_index` | input | u64, below 8 |
| `out` | output | ParticipationFlags, 1 byte |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `flags`, `flag_index`, `out`.
- Forks: altair and later.

## Function `lantern_get_finality_delay`

The previous epoch minus the finalized epoch.

### Signature

```
lantern_get_finality_delay(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `state`, `out`.

## Function `lantern_is_in_inactivity_leak`

The finality delay is above MIN_EPOCHS_TO_INACTIVITY_PENALTY.

### Signature

```
lantern_is_in_inactivity_leak(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `out` | output | Boolean |

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `state`, `out`.

## Function `lantern_get_eligible_validator_indices`

The validators active in the previous epoch, or slashed and not yet withdrawable after it, ascending.

### Signature

```
lantern_get_eligible_validator_indices(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `out` | output | `IndexList` |

### Returns

- `LANTERN_OK`: `out` holds the indices.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer entries than there are validators.

### ABI

- Argument order: `state`, `out`.

## Function `lantern_get_unslashed_participating_indices`

The unslashed validators active in epoch whose participation flags for epoch have flag_index set, ascending.

### Signature

```
lantern_get_unslashed_participating_indices(state, flag_index, epoch, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `flag_index` | input | u64, below 8 |
| `epoch` | input | u64 |
| `scratch` | scratch | `Scratch` |
| `out` | output | `IndexList` |

### Returns

- `LANTERN_OK`: `out` holds the indices.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(1) bytes, or `out` has room for fewer entries than there are validators.
- `LANTERN_INVALID_PARTICIPATION_EPOCH`: epoch is neither the previous nor the current epoch.

### ABI

- Argument order: `state`, `flag_index`, `epoch`, `scratch`, `out`.
- Forks: altair and later.

## Function `lantern_get_base_reward_per_increment`

EFFECTIVE_BALANCE_INCREMENT * BASE_REWARD_FACTOR // integer_squareroot(total active balance).

### Signature

```
lantern_get_base_reward_per_increment(state, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the reward.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(1) bytes.

### ABI

- Argument order: `state`, `scratch`, `out`.
- Forks: altair and later.

## Function `lantern_get_base_reward`

The validator's effective balance increments times the base reward per increment.

### Signature

```
lantern_get_base_reward(state, index, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `index` | input | u64 |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the reward.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(1) bytes.

### Caller must

- Pass an index below the number of validators.

### Function does

- Phase0: effective_balance * BASE_REWARD_FACTOR // integer_squareroot(total active balance) // BASE_REWARDS_PER_EPOCH.
- Altair and later: the effective balance increments times lantern_get_base_reward_per_increment.

### ABI

- Argument order: `state`, `index`, `scratch`, `out`.

## Function `lantern_compute_shuffled_permutation`

The spec's shuffle: SHUFFLE_ROUND_COUNT rounds of swap or not over 0 to index_count - 1.

### Signature

```
lantern_compute_shuffled_permutation(index_count, seed, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index_count` | input | u64 |
| `seed` | input | Bytes32 |
| `scratch` | scratch | `Scratch` |
| `out` | output | `IndexList` |

### Returns

- `LANTERN_OK`: `out` holds the permutation.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than 8 + 32 * ceil(index_count / 256) bytes, or `out` has room for fewer than index_count entries.
- `LANTERN_INVALID_SHUFFLED_INDEX`: index_count is 0, where the spec divides by 0.

### Function does

- Hashes the round's bucket sources once per round, in scratch; the spec hashes each the first time it reads it, which gives the same bytes.
- Hashes with `crypto_sha256` of asm-crypto.

### ABI

- Argument order: `index_count`, `seed`, `scratch`, `out`.

## Function `lantern_compute_shuffled_index`

The entry index of lantern_compute_shuffled_permutation(index_count, seed).

### Signature

```
lantern_compute_shuffled_index(index, index_count, seed, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64 |
| `index_count` | input | u64 |
| `seed` | input | Bytes32 |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the shuffled index.
- `LANTERN_INVALID_SHUFFLED_INDEX`: index is not below index_count.

### Function does

- The spec's compute_shuffled_index: `SHUFFLE_ROUND_COUNT` rounds on the one index, each with the pivot digest and the digest of the position's bucket.

### ABI

- Argument order: `index`, `index_count`, `seed`, `scratch`, `out`.

## Function `lantern_get_seed`

sha256(domain_type + uint_to_bytes(epoch) + the RANDAO mix of epoch + EPOCHS_PER_HISTORICAL_VECTOR - MIN_SEED_LOOKAHEAD - 1).

### Signature

```
lantern_get_seed(state, epoch, domain_type, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `domain_type` | input | DomainType, 4 bytes |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`: `out` holds the seed.
- `LANTERN_INVALID_OVERFLOW`: epoch + EPOCHS_PER_HISTORICAL_VECTOR leaves the Uint64 range.

### ABI

- Argument order: `state`, `epoch`, `domain_type`, `out`.

## Function `lantern_compute_proposer_index`

The first candidate of the shuffled indices that passes the effective balance draw.

### Signature

```
lantern_compute_proposer_index(state, indices, seed, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `indices` | input | `IndexList` of validator indices |
| `seed` | input | Bytes32 |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the proposer.
- `LANTERN_INVALID_NO_INDICES`: `indices` is empty.

### Caller must

- Pass indices below the number of validators.

### Function does

- Before electra: draws one random byte per candidate, sha256(seed + uint_to_bytes(i // 32))[i % 32], against MAX_EFFECTIVE_BALANCE.
- Electra and later: draws a 16-bit value per candidate against MAX_EFFECTIVE_BALANCE_ELECTRA.
- Runs compute_shuffled_index of each candidate inline: the pivot of each of the `SHUFFLE_ROUND_COUNT` rounds, bytes_to_uint64(sha256(seed + round)[0:8]) % total, once for the seed, then one digest of the position's bucket a round for each candidate. The pivots depend only on the seed, the round and the total, so each candidate gets the spec's index.
- Hashes the random bytes once for each 16 candidates (32 before electra): the candidates of one i // 16 (i // 32) read the same digest, as the spec's steps do.

### ABI

- Argument order: `state`, `indices`, `seed`, `scratch`, `out`.

## Function `lantern_compute_proposer_indices`

For each slot of epoch, lantern_compute_proposer_index with the seed sha256(seed + uint_to_bytes(slot)).

### Signature

```
lantern_compute_proposer_indices(state, epoch, seed, indices, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `seed` | input | Bytes32 |
| `indices` | input | `IndexList` of validator indices |
| `scratch` | scratch | `Scratch` |
| `out` | output | ProposerIndices: SLOTS_PER_EPOCH u64 |

### Returns

- `LANTERN_OK`: `out` holds the proposers.
- A `LANTERN_INVALID_*` code: a check of lantern_compute_proposer_index failed, or the start slot leaves the Uint64 range.

### ABI

- Argument order: `state`, `epoch`, `seed`, `indices`, `scratch`, `out`.
- Forks: fulu; every fork object exports it too, for lantern_node_proposers (node.md).

## Function `lantern_get_beacon_proposer_indices`

lantern_compute_proposer_indices with the active validators and the DOMAIN_BEACON_PROPOSER seed of epoch.

### Signature

```
lantern_get_beacon_proposer_indices(state, epoch, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `epoch` | input | u64 |
| `scratch` | scratch | `Scratch` |
| `out` | output | ProposerIndices: SLOTS_PER_EPOCH u64 |

### Returns

- `LANTERN_OK`: `out` holds the proposers.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(2) bytes.
- A `LANTERN_INVALID_*` code: a check of a callee failed.

### ABI

- Argument order: `state`, `epoch`, `scratch`, `out`.
- Forks: fulu; every fork object exports it too, for lantern_node_proposers (node.md).

## Function `lantern_compute_fork_data_root`

hash_tree_root(ForkData(current_version, genesis_validators_root)).

### Signature

```
lantern_compute_fork_data_root(current_version, genesis_validators_root, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `current_version` | input | Version, 4 bytes |
| `genesis_validators_root` | input | Bytes32 |
| `scratch` | scratch | `Scratch` |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`: `out` holds the root.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes.

### ABI

- Argument order: `current_version`, `genesis_validators_root`, `scratch`, `out`.

## Function `lantern_compute_domain`

domain_type + the first 28 bytes of the fork data root.

### Signature

```
lantern_compute_domain(domain_type, fork_version, genesis_validators_root, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `domain_type` | input | DomainType, 4 bytes |
| `fork_version` | input | Version, 4 bytes |
| `genesis_validators_root` | input | Bytes32 |
| `scratch` | scratch | `Scratch` |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`: `out` holds the domain.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes.

### Caller must

- Pass the spec's default values itself: GENESIS_FORK_VERSION of the config and a zero root.

### ABI

- Argument order: `domain_type`, `fork_version`, `genesis_validators_root`, `scratch`, `out`.

## Function `lantern_get_domain`

lantern_compute_domain with the state's previous fork version before the fork epoch and its current one after.

### Signature

```
lantern_get_domain(state, domain_type, epoch, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `domain_type` | input | DomainType, 4 bytes |
| `epoch` | input | u64 |
| `scratch` | scratch | `Scratch` |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`: `out` holds the domain.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes.

### Caller must

- Pass the current epoch when the spec passes None.

### ABI

- Argument order: `state`, `domain_type`, `epoch`, `scratch`, `out`.

## Function `lantern_compute_signing_root`

hash_tree_root(SigningData(hash_tree_root(object), domain)).

### Signature

```
lantern_compute_signing_root(type, object, domain, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | asm-ssz `TypeDescriptor` of the object: an ABI argument for the spec's SSZ type |
| `object` | input | asm-ssz `Value` of that type |
| `domain` | input | Bytes32 |
| `scratch` | scratch | `Scratch` |
| `out` | output | Bytes32 |

### Returns

- `LANTERN_OK`: `out` holds the root.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes, or fewer than the root node of `type` needs.

### ABI

- Argument order: `type`, `object`, `domain`, `scratch`, `out`.

## Type `Config`

The config values of the network, read at run time. Layout: the `CONFIG_*` offsets in include/lantern.inc.

### Rules

- Each value is a u64, little endian, except `CONFIG_TERMINAL_TOTAL_DIFFICULTY`, a Uint256 of 32 bytes, little endian; `CONFIG_TERMINAL_BLOCK_HASH`, a Hash32; `CONFIG_DEPOSIT_CONTRACT_ADDRESS`, 20 bytes then 12 zero bytes; and `CONFIG_PRESET_BASE` and `CONFIG_CONFIG_NAME`, a text: its length as a u64, then 64 bytes, its bytes and zero bytes after them.
- A Version takes the low 4 bytes of its u64; the other 4 bytes are 0.
- `CONFIG_BLOB_SCHEDULE` holds `CONFIG_BLOB_SCHEDULE_COUNT` entries of (EPOCH, MAX_BLOBS_PER_BLOCK), at most 32, in ascending EPOCH.
- `CONFIG_STATE_CACHE` holds the address of a [`StateCache`](state.md#type-statecache) that the caller keeps for every state root of the calls with this config, or 0. It is no value of the config file.
- `CONFIG_PUBKEY_CACHE` holds the address of a [`PubkeyCache`](block-processing.md#type-pubkeycache) that the caller keeps for the attestation signatures of the calls with this config, or 0. It is no value of the config file.
- `CONFIG_COMMITTEE_CACHE` holds the address of a [`CommitteeCache`](block-processing.md#type-committeecache) that the caller keeps for the committees of the calls with this config, or 0. It is no value of the config file.
- `CONFIG_SIZE` bytes.

## Type `Scratch`

Work memory for one call.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this field included |
| 8 | `bytes` | size - 8 bytes | Work memory |

### Rules

- Starts at a multiple of 8.
- Its contents before the call do not change any result.
- L(n) = 24 + 8 * n bytes holds one `IndexList` of n entries.
- S(k) = `LANTERN_SCRATCH_FIXED` + k * L(n) bytes, with n the number of validators of the state of the call.
- A function that needs S(k) keeps its own lists at the end of the buffer and calls each callee with the front part: the same buffer with a smaller `size`. So a function that keeps j lists and calls a callee that needs S(i) needs S(j + i).
- After a call, the `size` field may hold another value; set it again before the next call.

## Type `IndexList`

A list of u64: a standalone asm-ssz Value of List[Uint64, VALIDATOR_REGISTRY_LIMIT].

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this field included |
| 8 | `offset` | u64 | 24 |
| 16 | `count` | u64 | Number of entries |
| 24 | `entries` | u64 each | The numbers |

### Rules

- Starts at a multiple of 8.
- Room: (size - 24) / 8 entries.
- An output IndexList needs only its `size` set before the call.

## Type `Result`

The outcome of the spec checks of a call that changes a state and returned `LANTERN_OK`.

### Rules

- A u64.
- A function that changes no state has no `Result`: it returns the code of a failed check as its status, from 2 up.
- `LANTERN_VALID` (0) when every check held.
- Otherwise one of the `LANTERN_INVALID_*` codes in include/lantern.inc: the first check that failed.
- When it is not 0, a state the call changed is well formed but has no meaning, and outputs other than `result` may be unwritten.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_integer_squareroot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_saturating_sub`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_active_validator`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_eligible_for_activation_queue`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_eligible_for_activation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_slashable_validator`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_compounding_withdrawal_credential`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_has_compounding_withdrawal_credential`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_max_effective_balance`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_epoch_at_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_start_slot_at_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_activation_exit_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_valid_merkle_branch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_current_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_previous_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_block_root_at_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_block_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_randao_mix`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_active_validator_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_total_balance`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_total_active_balance`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_increase_balance`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_decrease_balance`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_has_flag`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_add_flag`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_finality_delay`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_in_inactivity_leak`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_eligible_validator_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_unslashed_participating_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_base_reward_per_increment`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_base_reward`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_shuffled_permutation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_shuffled_index`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_seed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_proposer_index`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_proposer_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_beacon_proposer_indices`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_fork_data_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_domain`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_domain`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_signing_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
