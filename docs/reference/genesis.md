# Genesis

## Contents

### Functions

- [`lantern_initialize_beacon_state_from_eth1_size`](#function-lantern_initialize_beacon_state_from_eth1_size): the buffer size of a genesis state.
- [`lantern_initialize_beacon_state_from_eth1`](#function-lantern_initialize_beacon_state_from_eth1): the genesis state of an eth1 block and its deposits.
- [`lantern_is_valid_genesis_state`](#function-lantern_is_valid_genesis_state): whether a genesis state may start the chain.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs/phase0/beacon-chain.md).
- Section: Genesis, phase0. The spec defines genesis in phase0 only.

## Common rules

- As in [block-processing.md](block-processing.md#common-rules).
- `out` gets a valid phase0 `BeaconState` value: its fixed part, then its parts in field order, each with the room of [`StateRoom`](state.md#type-stateroom) as lantern_beacon_state_copy gives; the validator lists also get one entry for each deposit.
- The caller sets the `size` field of `out` to its buffer size.
- Config: GENESIS_FORK_VERSION, GENESIS_DELAY, MIN_GENESIS_TIME and MIN_GENESIS_ACTIVE_VALIDATOR_COUNT of [`Config`](helpers.md#type-config).

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/minimal/phase0/genesis/initialization/` and `genesis/validity/`.
  - File: `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.

## Function `lantern_initialize_beacon_state_from_eth1_size`

The bytes that lantern_initialize_beacon_state_from_eth1 needs for deposit_count deposits and room.

### Signature

```
lantern_initialize_beacon_state_from_eth1_size(deposit_count, room, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `deposit_count` | input | u64 |
| `room` | input | `StateRoom` |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`, always.

### ABI

- Role: L1.
- Symbol: `lantern_phase0_initialize_beacon_state_from_eth1_size`, as in [helpers.md](helpers.md#common-rules).
- Argument order: `deposit_count`, `room`, `size`.
- Forks: phase0.

## Function `lantern_initialize_beacon_state_from_eth1`

The genesis state: genesis_time, fork, eth1_data and randao_mixes from the eth1 block, each deposit processed against the deposit root of the deposits up to it, the activations, and genesis_validators_root.

### Signature

```
lantern_initialize_beacon_state_from_eth1(eth1_block_hash, eth1_timestamp, deposits, deposit_count, room, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `eth1_block_hash` | input | Bytes32 |
| `eth1_timestamp` | input | u64 |
| `deposits` | input | `deposit_count` `Deposit` values, one after another |
| `deposit_count` | input | u64 |
| `room` | input | `StateRoom` |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `BeaconState` of phase0 |

### Returns

- `LANTERN_OK`: `out` holds the genesis state.
- `LANTERN_BUFFER_TOO_SMALL`: the `size` of `out` is below what lantern_initialize_beacon_state_from_eth1_size gives, or `scratch` is short.
- `LANTERN_INVALID_OVERFLOW`: eth1_timestamp + GENESIS_DELAY leaves the Uint64 range.
- The failed check of a deposit in lantern_process_deposit, which the spec asserts.

### Function does

- The deposit root of each step is the root of the list of the deposits' data up to it, of DEPOSIT_CONTRACT_TREE_DEPTH levels with its length mixed in, kept as the deposit contract keeps it: one branch node for each level.
- genesis_validators_root is the root of the validators as a list of VALIDATOR_REGISTRY_LIMIT entries, kept the same way.

### Limits

- Scratch: the scratch of lantern_process_deposit, plus about 2.6 KiB for the trees and an empty `BeaconBlockBody`.

### ABI

- Forks: phase0.

## Function `lantern_is_valid_genesis_state`

genesis_time >= MIN_GENESIS_TIME, and at least MIN_GENESIS_ACTIVE_VALIDATOR_COUNT validators active at GENESIS_EPOCH.

### Signature

```
lantern_is_valid_genesis_state(state, config, out) -> status
```

### Returns

- `LANTERN_OK`, always: `out` is 1 or 0.

### ABI

- Forks: phase0.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_initialize_beacon_state_from_eth1_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V |  |  |  |  |

### `lantern_initialize_beacon_state_from_eth1`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V |  |  |  |  |

### `lantern_is_valid_genesis_state`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V |  |  |  |  |
