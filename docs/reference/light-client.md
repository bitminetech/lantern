# Light client data

## Contents

### Functions

- [`lantern_state_branch`](#function-lantern_state_branch): the Merkle branch of a sync committee or the finalized root of a state.
- [`lantern_execution_branch`](#function-lantern_execution_branch): the Merkle branch of the execution payload of a block body.
- [`lantern_is_better_update`](#function-lantern_is_better_update): whether one `LightClientUpdate` ranks above another.

### Types

- The spec's `LightClientHeader`, `LightClientBootstrap`, `LightClientUpdate`, `LightClientFinalityUpdate` and `LightClientOptimisticUpdate` of each fork, in include/types.inc.

### Constants

- [`LC_BRANCH_CURRENT_SYNC_COMMITTEE`, `LC_BRANCH_NEXT_SYNC_COMMITTEE`, `LC_BRANCH_FINALIZED_ROOT`](#function-lantern_state_branch): the fields of a state branch.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), `light-client/full-node.md` and `light-client/sync-protocol.md` of altair, capella, deneb and electra. Fulu has no light-client folder: its light client types and rules are electra's.
- Section: `compute_merkle_proof` and the gindex functions (`current_sync_committee_gindex_at_slot`, `next_sync_committee_gindex_at_slot`, `finalized_root_gindex_at_slot`, `EXECUTION_PAYLOAD_GINDEX`); `is_better_update`, `is_sync_committee_update`, `is_finality_update`.
- `compute_merkle_proof` is asm-ssz `ssz_build_proof` (its proofs.md: the spec's name for `build_proof` of ssz-specs v0.1.0).

## Common rules

- As in [helpers.md](helpers.md#common-rules): each function is a fork function, `lantern_<fork>_<name>`. Phase0 has no light client data: each phase0 function gives `LANTERN_NO_STATE_ANSWER` and writes nothing.
- The generalized indices of the fork of the object:

| Field | Altair to deneb | Electra, fulu | Branch roots |
|---|---|---|---|
| `current_sync_committee` of `BeaconState` | 54 | 86 | 5; electra 6 |
| `next_sync_committee` of `BeaconState` | 55 | 87 | 5; electra 6 |
| `finalized_checkpoint.root` of `BeaconState` | 105 | 169 | 6; electra 7 |
| `execution_payload` of `BeaconBlockBody`, from capella | 25 | 25 | 4 |

- A branch is the sibling of each node on the path from the leaf up to the root, in that order, 32 bytes each, as `compute_merkle_proof` gives it.
- A light client object's fork is that of the slot of its `attested_header.beacon.slot` (a bootstrap's: `header.beacon.slot`); its bytes are those of the fork's type.

## Function `lantern_state_branch`

The branch of a field of a state, as `compute_merkle_proof(state, gindex)` gives it.

### Signature

```
lantern_state_branch(state, field, cache, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `field` | input | u64: `LC_BRANCH_CURRENT_SYNC_COMMITTEE` (0), `LC_BRANCH_NEXT_SYNC_COMMITTEE` (1) or `LC_BRANCH_FINALIZED_ROOT` (2) |
| `cache` | state | `StateCache`, or 0 |
| `scratch` | scratch | `Scratch` |
| `out` | output | the branch roots of the field's row of the table, 32 bytes each |

### Returns

- `LANTERN_OK`: `out` holds the branch.
- `LANTERN_INVALID_EVENT`: `field` is above 2. Nothing is written.
- `LANTERN_BUFFER_TOO_SMALL`: as lantern_state_root.

### Caller must

- Pass a valid `BeaconState` value of the fork in `state`, and a `cache` as lantern_state_root takes it.
- Keep `out` apart from the other arguments.

### Function does

- Takes the roots of the state's fields as lantern_state_root does, the cache brought up to the state the same way; with `cache` 0, or a tree's capacity passed, the roots of ssz_hash_tree_root of each field.
- `LC_BRANCH_FINALIZED_ROOT`: the first root is hash_tree_root of `finalized_checkpoint.epoch`; the others are those of the field `finalized_checkpoint`.
- The others: the siblings of the field's leaf in the tree of the field roots, padded with zero chunks to the next power of two, from the leaf's level up.

### Function never

- Writes outside `cache`, `scratch`, `out` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_state_branch`, as in [helpers.md](helpers.md#common-rules).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `field`, `cache`, `scratch`, `out`.

## Function `lantern_execution_branch`

The branch of the execution payload of a block body, as `compute_merkle_proof(body, EXECUTION_PAYLOAD_GINDEX)` gives it.

### Signature

```
lantern_execution_branch(body, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `body` | input | ByteList: the SSZ bytes of a `BeaconBlockBody` of the fork |
| `scratch` | scratch | `Scratch` |
| `out` | output | 4 roots, 32 bytes each |

### Returns

- `LANTERN_OK`: `out` holds the branch.
- `LANTERN_NO_STATE_ANSWER`: a fork before capella. Nothing is written.
- `LANTERN_INVALID_ENCODING`: the bytes are no `BeaconBlockBody` of the fork. Nothing is written.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` cannot hold the decoded body and the proof's work. Nothing is written.

### Function does

- Decodes the body with ssz_decode of the fork's `BeaconBlockBody` at the end of `scratch`, then ssz_build_proof at generalized index 25.

### Function never

- Writes outside `scratch`, `out` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_execution_branch`, of capella to fulu; altair and bellatrix give `LANTERN_NO_STATE_ANSWER`.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `body`, `scratch`, `out`.

## Function `lantern_is_better_update`

`is_better_update(new_update, old_update)` of two updates of the fork.

### Signature

```
lantern_is_better_update(new, old, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `new` | input | ByteList: the SSZ bytes of a `LightClientUpdate` of the fork |
| `old` | input | ByteList: the same |
| `out` | output | u64: 1 when `new` ranks above `old`, else 0 |

### Returns

- `LANTERN_OK`: `out` holds the answer.
- `LANTERN_INVALID_ENCODING`: either is too short for the type's fixed part, or, from capella, an offset of a header points outside its bytes or before the fixed part. Nothing is written.

### Function does

- Reads the fields the rules compare from the bytes: `sync_aggregate.sync_committee_bits`, `attested_header.beacon.slot`, `finalized_header.beacon.slot`, `signature_slot`, and whether `next_sync_committee_branch` and `finality_branch` are all zero bytes.
- Then the rules of `is_better_update` in order: supermajority (participants times 3 at least `SYNC_COMMITTEE_SIZE` times 2), the count of participants without supermajority, a relevant sync committee (`is_sync_committee_update` and the periods of the attested header and the signature slot equal), finality (`is_finality_update`), sync committee finality (the periods of the finalized and attested headers equal), the count of participants, the lower attested slot, the lower signature slot.

### Function never

- Writes outside `out` and its own stack.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_is_better_update`, as in [helpers.md](helpers.md#common-rules).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `new`, `old`, `out`.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/light_client/single_merkle_proof/` of altair to fulu, for mainnet and minimal.
  - `BeaconState`: the runner decodes `object` and checks lantern_state_branch of the case's field (`current_sync_committee_merkle_proof`, `next_sync_committee_merkle_proof`, `finality_root_merkle_proof`) against `branch`, with and without a `StateCache`; is_valid_merkle_branch of `leaf` at `leaf_index` must rebuild hash_tree_root of the state.
  - `BeaconBlockBody` (capella to fulu, `execution_merkle_proof`): lantern_execution_branch of `object` against `branch`.
- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/light_client/update_ranking/` of altair to fulu: the generator adds to each case, from `is_better_update` of the spec module, its answer for each ordered pair of the case's updates; lantern_is_better_update must give each.
- Not run: `light_client/sync`, the light client's own sync (lantern is a beacon node), and, until the node collects light client data, `light_client/data_collection`.

## Results

<!-- CI generates the tick table for each function here. -->
