# State transition

## Contents

### Functions

- [`lantern_state_transition`](#function-lantern_state_transition): applies a signed block to a state.
- [`lantern_verify_block_signature`](#function-lantern_verify_block_signature): checks the proposer's signature of a block.
- [`lantern_process_slots`](#function-lantern_process_slots): advances a state to a later slot.
- [`lantern_process_slot`](#function-lantern_process_slot): caches the roots of one slot.

### Types

- [`TransitionOptions`](#type-transitionoptions): the spec's validate_result, and the engine's answer.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs/phase0/beacon-chain.md).
- Section: Beacon chain state transition function, phase0, with the blocks and epochs of each fork.

## Function `lantern_state_transition`

process_slots to the block's slot; with validate_result, the block signature check; process_block; with validate_result, the state root check. With `slots_done` 1 and a state at the block's slot already, no process_slots: `fork.md` of each fork runs its upgrade inside process_slots, as the slot reaches the fork's first slot, and lantern's upgrade writes a new state there (lantern_upgrade_to_<fork>), so a block at the fork's first slot goes on from that state.

### Signature

```
lantern_state_transition(state, signed_block, options, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `signed_block` | input | `SignedBeaconBlock` |
| `options` | input | `TransitionOptions` |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` or the first failed check.
- `LANTERN_BUFFER_TOO_SMALL`: scratch, or room for the slots' epochs and the block's appends, is short. Checked before the state changes.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- The state root of the check is lantern_state_root with the `StateCache` at `CONFIG_STATE_CACHE` of `config`.
- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: the most of lantern_process_slots and lantern_process_block.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_state_transition` in the object of every fork, with `_` before it on macOS; `lantern_state_transition` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `signed_block`, `options`, `config`, `scratch`, `result`.

## Function `lantern_verify_block_signature`

bls.Verify(proposer pubkey, signing root of the block in the proposer domain of the current epoch, signature).

### Signature

```
lantern_verify_block_signature(state, signed_block, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `signed_block` | input | `SignedBeaconBlock` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`: `out` holds 1 or 0.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.
- `LANTERN_INVALID_VALIDATOR_INDEX`: the proposer index names no validator.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- Each block, body and operation argument is a valid asm-ssz Value of its type.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 208 bytes on x86-64 (return address included), 208 bytes on ARM64, 208 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_verify_block_signature` in the object of every fork, with `_` before it on macOS; `lantern_verify_block_signature` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `signed_block`, `scratch`, `out`.

## Function `lantern_process_slots`

process_slot for each slot up to slot, with process_epoch at the end of each epoch.

### Signature

```
lantern_process_slots(state, slot, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `slot` | input | u64 |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_SLOT` when slot is not after state.slot, or the failed check of an epoch.
- `LANTERN_BUFFER_TOO_SMALL`: scratch, or room for the epochs crossed, is short. Checked before the state changes.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- Checks the scratch and the room of `state` before any change to `state`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: as lantern_process_epoch.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_slots` in the object of every fork, with `_` before it on macOS; `lantern_process_slots` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `slot`, `config`, `scratch`, `result`.

## Function `lantern_process_slot`

Stores the state root, fills the latest header's state root when it is zero, and stores the header's root.

### Signature

```
lantern_process_slot(state, config, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState` |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- `LANTERN_OK`: done.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short; the state is unchanged.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.
- `scratch` is S(k) of [Type Scratch](helpers.md#type-scratch), with k under Limits.

### Function does

- The state root is lantern_state_root with the `StateCache` at `CONFIG_STATE_CACHE` of `config`; the header root, `ssz_hash_tree_root` of asm-ssz.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch: S(0).

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_process_slot` in the object of every fork, with `_` before it on macOS; `lantern_process_slot` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer, and numbers are u64.
- Argument order: `state`, `config`, `scratch`.

## Type `TransitionOptions`

The spec's validate_result, the answer of the execution engine to the block's payload, and whether the slots ran.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `validate_result` | u64 | 1: check the block signature and the state root |
| 8 | `execution_valid` | u64 | 1: the execution engine accepts the payload |
| 16 | `slots_done` | u64 | 1: a state at the block's slot runs no process_slots, as after an upgrade at the fork's first slot |

### Rules

- 24 bytes.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/sanity/slots/`, `sanity/blocks/`, `finality/finality/` and `random/random/` of each fork, for mainnet and minimal.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_state_transition`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_verify_block_signature`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_slots`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_process_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
