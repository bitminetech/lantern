# Genesis

The phase0 genesis state.

## Contents

### Functions

- [`lantern_initialize_beacon_state_from_eth1_size`](#function-lantern_initialize_beacon_state_from_eth1_size): the buffer size of a genesis state.
- [`lantern_initialize_beacon_state_from_eth1`](#function-lantern_initialize_beacon_state_from_eth1): the genesis state of an eth1 block and its deposits.
- [`lantern_is_valid_genesis_state`](#function-lantern_is_valid_genesis_state): whether a genesis state may start the chain.
- [`lantern_merkle_add`](#function-lantern_merkle_add): appends a leaf to a deposit tree, as the deposit contract does.
- [`lantern_merkle_root`](#function-lantern_merkle_root): the root of a deposit tree as a list, its length mixed in.
- [`lantern_merkle_zeros`](#function-lantern_merkle_zeros): the zero hashes of the levels of a deposit tree.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs/phase0/beacon-chain.md).
- Section: Genesis, phase0. The spec defines genesis in phase0 only.

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

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_initialize_beacon_state_from_eth1_size` in the object of phase0, with `_` before it on macOS; `lantern_initialize_beacon_state_from_eth1_size` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `deposit_count`, `room`, `size`.

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

### Caller must

- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.
- The `size` field of `out` is its buffer size.
- `config` is a [`Config`](helpers.md#type-config); this section reads its GENESIS_FORK_VERSION, GENESIS_DELAY, MIN_GENESIS_TIME and MIN_GENESIS_ACTIVE_VALIDATOR_COUNT.

### Function does

- The deposit root of each step is the root of the list of the deposits' data up to it, of DEPOSIT_CONTRACT_TREE_DEPTH levels with its length mixed in, kept as the deposit contract keeps it: one branch node for each level.
- genesis_validators_root is the root of the validators as a list of VALIDATOR_REGISTRY_LIMIT entries, kept the same way.
- Writes into `out` a valid phase0 `BeaconState` value: the fixed part, then the parts in field order, each with the room of `room` ([`StateRoom`](state.md#type-stateroom)) as lantern_beacon_state_copy gives; the validator lists also get one entry for each deposit.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.
- Scratch: the scratch of lantern_process_deposit, plus about 2.6 KiB for the trees and an empty `BeaconBlockBody`.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_initialize_beacon_state_from_eth1` in the object of phase0, with `_` before it on macOS; `lantern_initialize_beacon_state_from_eth1` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `eth1_block_hash`, `eth1_timestamp`, `deposits`, `deposit_count`, `room`, `config`, `scratch`, `out`.

## Function `lantern_is_valid_genesis_state`

genesis_time >= MIN_GENESIS_TIME, and at least MIN_GENESIS_ACTIVE_VALIDATOR_COUNT validators active at GENESIS_EPOCH.

### Signature

```
lantern_is_valid_genesis_state(state, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`, always: `out` is 1 or 0.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- The `size` field of `out` is its buffer size.
- `config` is a [`Config`](helpers.md#type-config); this section reads its GENESIS_FORK_VERSION, GENESIS_DELAY, MIN_GENESIS_TIME and MIN_GENESIS_ACTIVE_VALIDATOR_COUNT.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_valid_genesis_state` in the object of phase0, with `_` before it on macOS; `lantern_is_valid_genesis_state` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `out`.

## Function `lantern_merkle_add`

Appends a leaf to a deposit tree, as the deposit contract does.

### Signature

```
lantern_merkle_add(tree, leaf)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `tree` | state | the deposit tree: its size, then a branch node of each level |
| `leaf` | input | 32 bytes |

### Function does

- Adds the leaf and updates the branch as the deposit contract's deposit function does.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_merkle_add`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `tree`, `leaf`.

## Function `lantern_merkle_root`

The root of a deposit tree as a list, its length mixed in.

### Signature

```
lantern_merkle_root(tree, zeros, depth, out)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `tree` | input | the deposit tree |
| `zeros` | input | the zero hashes of each level (lantern_merkle_zeros) |
| `depth` | input | u64 in a register: the levels |
| `out` | output | 32 bytes |

### Caller must

- The `size` field of `out` is its buffer size.

### Function does

- Writes the root of the tree's leaves as a list of `depth` levels, mixed with its length.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_merkle_root`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `tree`, `zeros`, `depth`, `out`.

## Function `lantern_merkle_zeros`

The zero hashes of the levels of a deposit tree.

### Signature

```
lantern_merkle_zeros(zeros)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `zeros` | output | `MERKLE_DEPTH` hashes of 32 bytes |

### Function does

- Writes the zero hash of each level 0 to `MERKLE_DEPTH` - 1.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_merkle_zeros`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `zeros`.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/minimal/phase0/genesis/initialization/` and `genesis/validity/`.
  - File: `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_initialize_beacon_state_from_eth1_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_initialize_beacon_state_from_eth1`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_is_valid_genesis_state`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_merkle_add`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_merkle_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_merkle_zeros`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
