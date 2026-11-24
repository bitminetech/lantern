# Light client data

## Contents

### Functions

- [`lantern_state_branch`](#function-lantern_state_branch): the Merkle branch of a sync committee or the finalized root of a state.
- [`lantern_execution_branch`](#function-lantern_execution_branch): the Merkle branch of the execution payload of a block body.
- [`lantern_is_better_update`](#function-lantern_is_better_update): whether one `LightClientUpdate` ranks above another.
- [`lantern_block_to_light_client_header`](#function-lantern_block_to_light_client_header): the `LightClientHeader` of a block.
- [`lantern_upgrade_lc_header`](#function-lantern_upgrade_lc_header): a `LightClientHeader` of an earlier fork as one of the fork.
- [`lantern_lc_object`](#function-lantern_lc_object): the SSZ bytes of a light client object from its parts.
- [`lantern_lc_anchor_header`](#function-lantern_lc_anchor_header): the `LightClientHeader` of a block's value.
- [`lantern_lc_store_size`](#function-lantern_lc_store_size): the bytes of an `LcStore`.
- [`lantern_lc_store_init`](#function-lantern_lc_store_init): an `LcStore` at an anchor.
- [`lantern_lc_store_copy`](#function-lantern_lc_store_copy): an `LcStore` in a new buffer.
- [`lantern_lc_on_block`](#function-lantern_lc_on_block): the light client data of a new block.
- [`lantern_lc_on_head`](#function-lantern_lc_on_head): the light client data of a new head and its finalized checkpoint.
- [`lantern_lc_read`](#function-lantern_lc_read): a bootstrap, a best update, or the latest finality or optimistic update.

### Types

- The spec's `LightClientHeader`, `LightClientBootstrap`, `LightClientUpdate`, `LightClientFinalityUpdate` and `LightClientOptimisticUpdate` of each fork, in include/types.inc.
- [`LcParts`](#type-lcparts): the parts of a light client object.
- [`LcStore`](#type-lcstore), [`LcRoom`](#type-lcroom), [`LcBlock`](#type-lcblock), [`LcFinalized`](#type-lcfinalized), [`LcPeriod`](#type-lcperiod), [`LcBootstrap`](#type-lcbootstrap), [`LcHeader`](#type-lcheader), [`LcCommittee`](#type-lccommittee), [`LcUpdate`](#type-lcupdate): the light client data of a node.

### Constants

- [`LC_BRANCH_CURRENT_SYNC_COMMITTEE`, `LC_BRANCH_NEXT_SYNC_COMMITTEE`, `LC_BRANCH_FINALIZED_ROOT`](#function-lantern_state_branch): the fields of a state branch.
- `LC_OBJECT_BOOTSTRAP` (0), `LC_OBJECT_UPDATE` (1), `LC_OBJECT_FINALITY_UPDATE` (2), `LC_OBJECT_OPTIMISTIC_UPDATE` (3): the kinds of [lantern_lc_object](#function-lantern_lc_object) and [lantern_lc_read](#function-lantern_lc_read).
- `LC_FREE` (0), `LC_USED` (1), `LC_MARKED` (2): the `state` of a record of an `LcStore`.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), `light-client/full-node.md` and `light-client/sync-protocol.md` of altair, capella, deneb and electra. Fulu has no light-client folder: its light client types and rules are electra's.
- Section: `block_to_light_client_header` of altair, capella and deneb `full-node.md`; `upgrade_lc_header_to_capella`, `upgrade_lc_header_to_deneb` and `upgrade_lc_header_to_electra` of their `fork.md`; `compute_merkle_proof` and the gindex functions (`current_sync_committee_gindex_at_slot`, `next_sync_committee_gindex_at_slot`, `finalized_root_gindex_at_slot`, `EXECUTION_PAYLOAD_GINDEX`); `is_better_update`, `is_sync_committee_update`, `is_finality_update`.
- `compute_merkle_proof` is asm-ssz `ssz_build_proof` (its proofs.md: the spec's name for `build_proof` of ssz-specs v0.1.0).
- The light client data of a node (the `LcStore` functions): the model of the pinned test helper [tests/core/pyspec/eth_consensus_specs/test/helpers/light_client_data_collection.py](https://github.com/ethereum/consensus-specs/blob/aa16bb4c156184e9548a997d53efaf2a228a6304/tests/core/pyspec/eth_consensus_specs/test/helpers/light_client_data_collection.py), which makes the `light_client/data_collection` vectors: `setup_lc_data_collection_test`, `_process_new_block_for_light_client`, `_create_lc_update`, `_cache_lc_data`, `_create_lc_update_from_lc_data`, `_create_lc_finality_update_from_lc_data`, `select_new_head`, `_process_head_change_for_light_client`, `_process_finalization_for_light_client`, `_create_lc_bootstrap` and the `get_light_client_*` reads. The spec's own rules for this data are `create_light_client_bootstrap`, `create_light_client_update` and the "Deriving light client data" section of altair `full-node.md`; the model applies them.

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
- The `LcStore` functions are in the common object of the core (asm/core/<ISA>/lcstore.s), and each symbol is its name; they call the fork functions above of each object's fork, the fork of a slot being the last fork of the config whose epoch is at most the slot's epoch.
- The period of a slot is compute_sync_committee_period_at_slot: the slot over `SLOTS_PER_EPOCH` times `EPOCHS_PER_SYNC_COMMITTEE_PERIOD`; the first slot of a period is the period times that.
- The participants of a `SyncAggregate` are the set bits of its `sync_committee_bits`.

### The update of an entry

The update of an `LcBlock` A (the attested block), a signature slot s, a `SyncAggregate` g and an `LcCommittee` c, as `_create_lc_update_from_lc_data` makes it, is an `LcUpdate` of the fork of A's header:

- `attested_header`: A's header.
- `finalized_header` and `finality_branch`: the `LcFinalized` of the highest slot at most A's `finalized_slot` and at least `historical_tail_slot`. When there is one, A's `finalized_slot` becomes its slot (the model's cache update for empty slots at the end of an epoch); the header is, at slot `GENESIS_SLOT`, the empty header of the fork (lantern_upgrade_lc_header of 112 zero bytes from altair), else the header of its root's `LcBlock`, through lantern_upgrade_lc_header to the fork; the branch is A's `finality_branch`. When there is none, or the store holds no `LcBlock` of its root, the header is the empty header and the branch zero roots, as `create_light_client_update` of altair full-node.md has them without a finalized block.
- `next_sync_committee` c and `next_sync_committee_branch` A's, for an update; a finality update has neither.
- `sync_aggregate` g and `signature_slot` s.

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

## Function `lantern_block_to_light_client_header`

`block_to_light_client_header(block)` of the block's fork.

### Signature

```
lantern_block_to_light_client_header(block, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `block` | input | ByteList: the SSZ bytes of a `SignedBeaconBlock` of the fork |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList: the SSZ bytes of the fork's `LightClientHeader`; for phase0, altair's |

### Returns

- `LANTERN_OK`: `out` holds them, its `count` set.
- `LANTERN_INVALID_ENCODING`: `block` is no SSZ encoding of the type.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has too little room, or `scratch` too little for the decoded block, the blinded block and the proof's work.

### Function does

- `beacon`: the block's `slot`, `proposer_index`, `parent_root`, `state_root`, and as `body_root` hash_tree_root of its body.
- From capella: `execution`, the `ExecutionPayloadHeader` that lantern_node_blinded_block puts in the body's place of the payload (node.md: `transactions_root` and `withdrawals_root` the hash_tree_root of the payload's lists; from deneb `blob_gas_used` and `excess_blob_gas` the payload's); `execution_branch`, lantern_execution_branch of the body.
- A block of the fork has an epoch of capella or later from capella on, so the spec's branch for an earlier epoch (an empty `execution`) never applies here: an earlier block's header is that of its own fork, then lantern_upgrade_lc_header.
- Phase0 has no `LightClientHeader`: its header is altair's, the beacon fields alone, as the spec's data collection makes it (`_light_client_header_for_block` takes altair's for a block before altair).

### Function never

- Writes outside `scratch`, `out` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_block_to_light_client_header` of each fork object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `block`, `scratch`, `out`.

## Function `lantern_upgrade_lc_header`

A `LightClientHeader` of the fork `from` as one of the fork: `upgrade_lc_header_to_capella`, `upgrade_lc_header_to_deneb` and `upgrade_lc_header_to_electra`, each that applies, in turn.

### Signature

```
lantern_upgrade_lc_header(header, from, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | input | ByteList: the SSZ bytes of a `LightClientHeader` of the fork `from` (altair's for phase0) |
| `from` | input | u64: `FORK_*`, at most the fork |
| `out` | output | ByteList: the SSZ bytes of the fork's `LightClientHeader` |

### Returns

- `LANTERN_OK`: `out` holds them, its `count` set.
- `LANTERN_INVALID_EVENT`: `from` is above the fork. Nothing is written.
- `LANTERN_INVALID_ENCODING`: the bytes are no header of the fork `from`: not 112 bytes before capella; from capella an offset of `execution` other than 244, or a payload header shorter than its fixed part, or whose `extra_data` offset is not its fixed size. Nothing is written.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has too little room. Nothing is written.

### Function does

- `from` before capella and the fork capella or later: `beacon`, then an empty `ExecutionPayloadHeader` of the fork (zero bytes, `extra_data` empty) and a zero `execution_branch`.
- `from` capella and the fork deneb or later: `blob_gas_used` and `excess_blob_gas` 0 join the payload header after `withdrawals_root`.
- Else the same bytes: deneb, electra and fulu share the layout, as do altair and bellatrix.

### Function never

- Writes outside `out` and its own stack.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_upgrade_lc_header` of each fork object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `header`, `from`, `out`.

## Function `lantern_lc_object`

The SSZ bytes of a `LightClientBootstrap`, `LightClientUpdate`, `LightClientFinalityUpdate` or `LightClientOptimisticUpdate` of the fork, from its parts.

### Signature

```
lantern_lc_object(kind, parts, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64: `LC_OBJECT_*` |
| `parts` | input | [`LcParts`](#type-lcparts) |
| `out` | output | ByteList: the SSZ bytes of the kind's type of the fork |

### Returns

- `LANTERN_OK`: `out` holds them, its `count` set.
- `LANTERN_NO_STATE_ANSWER`: phase0. Nothing is written.
- `LANTERN_INVALID_EVENT`: `kind` is above 3, or a branch the kind uses has more roots than the fork's type. Nothing is written.
- `LANTERN_INVALID_ENCODING`: a header the kind uses is no `LightClientHeader` of the fork: not 112 bytes before capella; from capella fewer bytes than 244 and the fork's payload header fixed part, or an offset of `execution` other than 244. Nothing is written.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has too little room. Nothing is written.

### Function does

- The fields of the kind's type in order: before capella the headers' bytes in the fixed part; from capella an offset in the fixed part for each header, and the headers' bytes after the fixed part in field order.
- Each branch with zero roots first, up to the root count of the fork's type: normalize_merkle_branch of electra `fork.md`.
- `LC_OBJECT_BOOTSTRAP`: `header`, `sync_committee`, `branch`. `LC_OBJECT_UPDATE`: `header`, `sync_committee`, `branch`, `finalized_header`, `finality_branch`, `sync_aggregate`, `signature_slot`. `LC_OBJECT_FINALITY_UPDATE`: `header`, `finalized_header`, `finality_branch`, `sync_aggregate`, `signature_slot`. `LC_OBJECT_OPTIMISTIC_UPDATE`: `header`, `sync_aggregate`, `signature_slot`.

### Function never

- Writes outside `out` and its own stack.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_lc_object` of each fork object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `kind`, `parts`, `out`.

## Function `lantern_lc_anchor_header`

The `LightClientHeader` of a `BeaconBlock` value: lantern_block_to_light_client_header of the `SignedBeaconBlock` of the block with a zero signature.

### Signature

```
lantern_lc_anchor_header(block, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `block` | input | `BeaconBlock` of the fork |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList: as lantern_block_to_light_client_header's |

### Returns

- As lantern_block_to_light_client_header; `LANTERN_BUFFER_TOO_SMALL` also when `scratch` cannot hold the block's SSZ bytes with those of lantern_block_to_light_client_header.

### Function does

- ssz_serialize of the fork's `BeaconBlock` at the end of `scratch`, after the 100 bytes of a `SignedBeaconBlock`'s fixed part (the offset 100, a zero signature), then lantern_block_to_light_client_header of those bytes with the rest of `scratch`. The signature is no field of the header.
- Restores the `size` field of `scratch`.

### Function never

- Writes outside `scratch`, `out` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_lc_anchor_header` of each fork object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `block`, `scratch`, `out`.

## Function `lantern_lc_store_size`

The bytes of an `LcStore` whose parts have the capacities of an `LcRoom`.

### Signature

```
lantern_lc_store_size(room, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `room` | input | [`LcRoom`](#type-lcroom) |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`: `size` holds `LC_STORE_FIXED` plus each capacity times its entry's bytes.
- `LANTERN_INVALID_OVERFLOW`: the size is 2^64 or more.

### ABI

- Role: L0.
- Symbol: `lantern_lc_store_size`, in the common object.
- Argument order: `room`, `size`.

## Function `lantern_lc_store_init`

An `LcStore` at an anchor: `setup_lc_data_collection_test` of the model.

### Signature

```
lantern_lc_store_init(room, config, state, block, scratch, lc) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `room` | input | `LcRoom` |
| `config` | input | `Config` |
| `state` | input | `BeaconState` of the fork of its slot: the anchor state |
| `block` | input | `BeaconBlock` of the same fork: the anchor state's block, as lantern_node_anchor or lantern_node_anchor_block gives it |
| `scratch` | scratch | `Scratch` |
| `lc` | output | `LcStore`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `lc` holds the store.
- `LANTERN_BUFFER_TOO_SMALL`: `lc` is below lantern_lc_store_size of `room`, a capacity of `room` is below 2, or `scratch` is short (as lantern_lc_on_block).
- `LANTERN_INVALID_OVERFLOW`: as lantern_lc_store_size.

### Function does

- `tail_slot`: the higher of the state's slot and the first slot of `ALTAIR_FORK_EPOCH`. `historical_tail_slot`: the state's slot.
- `latest_finalized_epoch`: the epoch of the state's `finalized_checkpoint`; `latest_finalized_slot`: that epoch's first slot; `latest_finalized_root`: its root. `latest`: none.
- The block's `LcBlock`, as lantern_lc_on_block makes one, its header lantern_lc_anchor_header of the fork of the state's slot, and an `LcFinalized` of its slot and root.
- From altair: the entry's data from the state (its branches, committees and `finalized_slot`), no best update, `latest_signature_slot` `GENESIS_SLOT`; and its `LcBootstrap`.
- Every record of the other capacities is `LC_FREE`.

### Function never

- Writes outside `scratch`, `lc` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_lc_store_init`, in the common object.
- Argument order: `room`, `config`, `state`, `block`, `scratch`, `lc`.

## Function `lantern_lc_store_copy`

The store in a new buffer with the capacities of an `LcRoom`.

### Signature

```
lantern_lc_store_copy(lc, room, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `lc` | input | `LcStore` |
| `room` | input | `LcRoom` |
| `out` | output | `LcStore`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the store.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is below lantern_lc_store_size of `room`, or a capacity of `room` is below that of `lc`.
- `LANTERN_INVALID_OVERFLOW`: as lantern_lc_store_size.

### Function does

- The same fields, entries and records; the records past `lc`'s capacities are `LC_FREE`.

### Function never

- Writes outside `out` and its own stack.

### ABI

- Role: L0.
- Symbol: `lantern_lc_store_copy`, in the common object.
- Argument order: `lc`, `room`, `out`.

## Function `lantern_lc_on_block`

The light client data of a new block and its post-state: `_process_new_block_for_light_client` of the model.

### Signature

```
lantern_lc_on_block(lc, config, state, block, cache, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `lc` | state | `LcStore` |
| `config` | input | `Config` |
| `state` | input | `BeaconState` of the fork of the block's slot: the block's post-state |
| `block` | input | ByteList: the SSZ bytes of a `SignedBeaconBlock` of that fork |
| `cache` | state | `StateCache` of the state, or 0, as lantern_state_branch takes it |
| `scratch` | scratch | `Scratch` |

### Returns

- `LANTERN_OK`: the store holds the block.
- `LANTERN_INVALID_ENCODING`: `block` is no SSZ encoding of the type.
- `LANTERN_INVALID_EVENT`: the store holds an `LcBlock` of the block's root.
- `LANTERN_INVALID_UNKNOWN_BLOCK`: the slot is at least `tail_slot` and the store holds no `LcBlock` of the parent root.
- `LANTERN_BUFFER_TOO_SMALL`: `blocks` is full, or a record part has too few free records once those nothing refers to are freed (2 headers, 2 committees, 1 update), or `scratch` is below `LC_COMPARE_SCRATCH` bytes or short for a callee.
- With each status but `LANTERN_OK` the store holds the same data.

### Function does

- The header: lantern_block_to_light_client_header of the block's fork, an `LcHeader` of that fork (altair for phase0). The root: hash_tree_root of its `beacon`, which is that of the block's message.
- An `LcBlock` of the root, the parent root, the slot, the parent's entry, the header, and from altair the body's `sync_aggregate`.
- At a slot below `tail_slot`, nothing more. Else its data, with A the parent's entry, n the participants of the block's sync aggregate, and P the period:
  - The branches: lantern_state_branch of the state for each field, with `cache`; `finalized_slot`: the first slot of the epoch of the state's `finalized_checkpoint`; `current_sync_committee` and `next_sync_committee`: those of the state, each sharing the parent's record of equal bytes.
  - A's slot below `tail_slot`: no best update and `latest_signature_slot` `GENESIS_SLOT`.
  - Else `best` A's when P of A's slot is P of the block's slot, else none; `latest_signature_slot` A's when n is below `MIN_SYNC_COMMITTEE_PARTICIPANTS`, else the block's slot.
  - Then, with n at least `MIN_SYNC_COMMITTEE_PARTICIPANTS` and the two periods equal: U, [the update of A](#the-update-of-an-entry) with the block's slot, its sync aggregate and the entry's `next_sync_committee`. U becomes `best` when there is none, or when lantern_is_better_update of U's fork gives 1 for U and `best` upgraded to that fork (each header through lantern_upgrade_lc_header, the branches as lantern_lc_object normalizes them).
- The checks of room come before any change.

### Function never

- Writes outside `lc`, `cache`, `scratch` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_lc_on_block`, in the common object.
- Argument order: `lc`, `config`, `state`, `block`, `cache`, `scratch`.

## Function `lantern_lc_on_head`

The light client data of a new head, then of a finalized checkpoint: `select_new_head` of the model, which runs `_process_head_change_for_light_client`, then the finalization with `_process_finalization_for_light_client`.

### Signature

```
lantern_lc_on_head(lc, config, head, checkpoint, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `lc` | state | `LcStore` |
| `config` | input | `Config` |
| `head` | input | Root: the head block's |
| `checkpoint` | input | Checkpoint: the finalized checkpoint, the model's of the head's post-state |
| `scratch` | scratch | `Scratch` |

### Returns

- `LANTERN_OK`: the store holds the data of the head and the checkpoint.
- `LANTERN_INVALID_UNKNOWN_BLOCK`: the store holds no `LcBlock` of `head`, or the checkpoint's epoch is not `GENESIS_EPOCH` and it holds none of its root.
- `LANTERN_BUFFER_TOO_SMALL`: `periods`, `finalized` or `bootstraps` has too little room for the call, a record part too few free records once those nothing refers to are freed (1 header, 1 update), or `scratch` is below 8 bytes plus 8 for each `LcBlock`.
- With each status but `LANTERN_OK` the store holds the same data.

### Function does

- The head, with H its entry and `low_slot` the higher of `tail_slot` and `latest_finalized_slot` (the store's before this call). At a slot of H below `tail_slot`, nothing:
  - For each period from that of H's slot down to that of `low_slot`: E, the entry of the highest slot at most the period's last slot along the parents from the last E (first H). With no E, or E below `low_slot`, the loop ends. Else E's `best`, when there is one with at least `MIN_SYNC_COMMITTEE_PARTICIPANTS` participants, becomes the `LcPeriod` of the period; else the period has no `LcPeriod`.
  - `latest`: with s H's `latest_signature_slot`, S the entry of the highest slot at most s along the parents from H, and A the entry of the highest slot below S's along the parents from S: [the finality update of A](#the-update-of-an-entry) with s and S's sync aggregate. None when s is at most `low_slot`, or there is no S, or S is at most `low_slot`, or there is no A, or A is below `low_slot`.
- Then the checkpoint, when its epoch is not `GENESIS_EPOCH` and its root's entry F has a slot above `latest_finalized_slot`:
  - An `LcFinalized` of each entry from F along the parents with a slot above `latest_finalized_slot` (the old value) and above the slot of the last `LcFinalized`; then `latest_finalized_epoch` the checkpoint's epoch, and `latest_finalized_slot` and `latest_finalized_root` F's.
  - With F at least `tail_slot`: with `low_slot` the higher of the old `latest_finalized_slot` plus 1 and `tail_slot`, and b first F's slot, while b is at least `low_slot`: E the `LcFinalized` of the highest slot at most b and at least `historical_tail_slot` (with none, the loop ends); when E is at least `low_slot` and has no `LcBootstrap`, an `LcBootstrap` of E's root, slot, and its `LcBlock`'s header, `current_sync_committee` and current branch; then b is the first slot of the epoch of E's slot plus `SLOTS_PER_EPOCH` minus 1, and the loop ends when b is below `SLOTS_PER_EPOCH`, else b goes down by `SLOTS_PER_EPOCH`.
  - The entries of slots below F's go; an entry whose parent went has no parent.
- The checks of room come before any change.

### Function never

- Writes outside `lc`, `scratch` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_lc_on_head`, in the common object.
- Argument order: `lc`, `config`, `head`, `checkpoint`, `scratch`.

## Function `lantern_lc_read`

A light client object of the store as SSZ bytes of its fork: `get_light_client_bootstrap`, `get_light_client_update_for_period`, `get_light_client_finality_update` and `get_light_client_optimistic_update` of the model.

### Signature

```
lantern_lc_read(lc, kind, key, out, fork) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `lc` | input | `LcStore` |
| `kind` | input | u64: `LC_OBJECT_*` |
| `key` | input | u64: `LC_OBJECT_BOOTSTRAP` the address of a Root; `LC_OBJECT_UPDATE` a period; else 0 |
| `out` | output | ByteList |
| `fork` | output | u64: `FORK_*` of the object |

### Returns

- `LANTERN_OK`: `out` holds the object, `fork` its fork.
- `LANTERN_NO_STATE_ANSWER`: the store holds none. Nothing is written.
- `LANTERN_INVALID_EVENT`: `kind` is above 3. Nothing is written.
- `LANTERN_BUFFER_TOO_SMALL`: as lantern_lc_object. Nothing is written.

### Function does

- `LC_OBJECT_BOOTSTRAP`: the `LcBootstrap` of the root, of its header's fork. `LC_OBJECT_UPDATE`: the `LcPeriod` of the period's update. `LC_OBJECT_FINALITY_UPDATE`: `latest`. `LC_OBJECT_OPTIMISTIC_UPDATE`: `latest`'s attested header, sync aggregate and signature slot.
- The bytes: lantern_lc_object of the record's fork.

### Function never

- Writes outside `out`, `fork` and its own stack.

### ABI

- Role: L1.
- Symbol: `lantern_lc_read`, in the common object.
- Argument order: `lc`, `kind`, `key`, `out`, `fork`.

## Type `LcParts`

The parts of a light client object, for lantern_lc_object.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `header` | pointer | A ByteList of a `LightClientHeader`: the bootstrap's `header`, else `attested_header` |
| 8 | `sync_committee` | pointer | The SSZ bytes of a `SyncCommittee`: the bootstrap's current, the update's next |
| 16 | `branch` | pointer | Roots: the bootstrap's `current_sync_committee_branch`, the update's `next_sync_committee_branch` |
| 24 | `branch_count` | u64 | Their number |
| 32 | `finalized_header` | pointer | A ByteList of a `LightClientHeader` |
| 40 | `finality_branch` | pointer | Roots |
| 48 | `finality_count` | u64 | Their number |
| 56 | `sync_aggregate` | pointer | The SSZ bytes of a `SyncAggregate` |
| 64 | `signature_slot` | u64 | |

### Rules

- `LcParts__mem` (72) bytes. lantern_lc_object reads the fields its kind uses.

## Type `LcRoom`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `blocks` | u64 | Capacity of `LcBlock` entries |
| 8 | `finalized` | u64 | Of `LcFinalized` entries |
| 16 | `periods` | u64 | Of `LcPeriod` entries |
| 24 | `bootstraps` | u64 | Of `LcBootstrap` entries |
| 32 | `headers` | u64 | Of `LcHeader` records |
| 40 | `committees` | u64 | Of `LcCommittee` records |
| 48 | `updates` | u64 | Of `LcUpdate` records |

### Rules

- `LcRoom__mem` (56) bytes.

## Type `LcStore`

The light client data of a node: the model's `LightClientDataStore` (`cache` and `db`) and the parts of its test that it reads (`blocks`, `finalized_block_roots`, `latest_finalized_epoch`, `latest_finalized_bid`, `historical_tail_slot`).

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer |
| 8 | `tail_slot` | u64 | The earliest slot with light client data |
| 16 | `historical_tail_slot` | u64 | The anchor state's slot |
| 24 | `latest_finalized_epoch` | u64 | |
| 32 | `latest_finalized_slot` | u64 | |
| 40 | `latest_finalized_root` | Root | |
| 72 | `latest` | u64 | The latest finality update: an `LcUpdate` reference, or 0 |
| 80 | `room` | `LcRoom` | The capacity of each part |
| 136 | `blocks` | u64 | `LcBlock` entries |
| 144 | `finalized` | u64 | `LcFinalized` entries |
| 152 | `periods` | u64 | `LcPeriod` entries |
| 160 | `bootstraps` | u64 | `LcBootstrap` entries |

### Rules

- `LC_STORE_FIXED` (168) bytes, then the parts at their capacities in this order: `LcBlock`, `LcFinalized`, `LcPeriod`, `LcBootstrap` entries, then `LcHeader`, `LcCommittee` and `LcUpdate` records.
- `LcBlock` entries in the order they came, so a parent's entry is before its children's; `LcFinalized` and `LcPeriod` entries in ascending slot and period; `LcBootstrap` entries in the order they came.
- A reference to a record is its index plus 1; 0 is none.
- A record is `LC_USED` while an entry, `latest` or an `LcUpdate` refers to it. A function that needs more free records of a part than there are first frees each record nothing refers to: each referred record becomes `LC_MARKED`, then each `LC_USED` one `LC_FREE` and each `LC_MARKED` one `LC_USED`.

## Type `LcBlock`

A block from the finalized one on: the model's `blocks` entry and, from `tail_slot`, its `CachedLightClientData`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | hash_tree_root of the block's message |
| 32 | `parent_root` | Root | |
| 64 | `slot` | u64 | |
| 72 | `parent` | u64 | The parent's entry index plus 1, or 0 |
| 80 | `data` | u64 | 1 with the fields below, else 0 |
| 88 | `header` | u64 | `LcHeader` reference: the block's header |
| 96 | `current_sync_committee` | u64 | `LcCommittee` reference: of the post-state |
| 104 | `next_sync_committee` | u64 | `LcCommittee` reference: of the post-state |
| 112 | `best` | u64 | `LcUpdate` reference: `current_period_best_update`, or 0 |
| 120 | `finalized_slot` | u64 | |
| 128 | `latest_signature_slot` | u64 | |
| 136 | `sync_aggregate` | `LC_AGGREGATE_ROOM` bytes | The SSZ bytes of the body's `SyncAggregate`, from altair |
| 136 + `LC_AGGREGATE_ROOM` | `current_branch` | 6 roots | `current_sync_committee_branch`, the fork's count first |
| 328 + `LC_AGGREGATE_ROOM` | `next_branch` | 6 roots | `next_sync_committee_branch` |
| 520 + `LC_AGGREGATE_ROOM` | `finality_branch` | 7 roots | |

### Rules

- `LcBlock__mem` (744 + `LC_AGGREGATE_ROOM`) bytes; `LC_AGGREGATE_ROOM` is `SYNC_COMMITTEE_SIZE` / 8 + 96 up to a multiple of 8.
- The branches' fork is that of the header.

## Type `LcFinalized`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `slot` | u64 | |
| 8 | `root` | Root | A finalized block's: the model's `finalized_block_roots` |

### Rules

- `LcFinalized__mem` (40) bytes.

## Type `LcPeriod`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `period` | u64 | |
| 8 | `update` | u64 | `LcUpdate` reference: the model's `best_updates` of the period |

### Rules

- `LcPeriod__mem` (16) bytes.

## Type `LcBootstrap`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | The block's |
| 32 | `slot` | u64 | |
| 40 | `header` | u64 | `LcHeader` reference |
| 48 | `sync_committee` | u64 | `LcCommittee` reference: the current one of the block's post-state |
| 56 | `branch` | 6 roots | `current_sync_committee_branch` |

### Rules

- `LcBootstrap__mem` (248) bytes.

## Type `LcHeader`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `state` | u64 | `LC_FREE`, `LC_USED` or `LC_MARKED` |
| 8 | `fork` | u64 | `FORK_*` of the header's type, altair or later |
| 16 | `header` | ByteList | The SSZ bytes of a `LightClientHeader`, room for `LC_HEADER_ROOM` bytes |

### Rules

- `LcHeader__mem` (40 + `LC_HEADER_ROOM`) bytes; `LC_HEADER_ROOM` (864) holds 244 bytes, a deneb `ExecutionPayloadHeader`'s fixed part and `MAX_EXTRA_DATA_BYTES`.

## Type `LcCommittee`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `state` | u64 | As `LcHeader`'s |
| 8 | `committee` | `SyncCommittee` SSZ bytes | 48 * `SYNC_COMMITTEE_SIZE` + 48 bytes |

### Rules

- `LcCommittee__mem` (56 + 48 * `SYNC_COMMITTEE_SIZE`) bytes.

## Type `LcUpdate`

An update, or a finality update.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `state` | u64 | As `LcHeader`'s |
| 8 | `fork` | u64 | `FORK_*`: that of `attested_header` |
| 16 | `attested_header` | u64 | `LcHeader` reference |
| 24 | `finalized_header` | u64 | `LcHeader` reference, of the same fork |
| 32 | `next_sync_committee` | u64 | `LcCommittee` reference; 0 in a finality update |
| 40 | `signature_slot` | u64 | |
| 48 | `next_branch` | 6 roots | `next_sync_committee_branch`, the fork's count first |
| 240 | `finality_branch` | 7 roots | |
| 464 | `sync_aggregate` | `LC_AGGREGATE_ROOM` bytes | |

### Rules

- `LcUpdate__mem` (464 + `LC_AGGREGATE_ROOM`) bytes.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/light_client/single_merkle_proof/` of altair to fulu, for mainnet and minimal.
  - `BeaconState`: the runner decodes `object` and checks lantern_state_branch of the case's field (`current_sync_committee_merkle_proof`, `next_sync_committee_merkle_proof`, `finality_root_merkle_proof`) against `branch`, with and without a `StateCache`; is_valid_merkle_branch of `leaf` at `leaf_index` must rebuild hash_tree_root of the state.
  - `BeaconBlockBody` (capella to fulu, `execution_merkle_proof`): lantern_execution_branch of `object` against `branch`.
- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/light_client/update_ranking/` of altair to fulu: the generator adds to each case, from `is_better_update` of the spec module, its answer for each ordered pair of the case's updates; lantern_is_better_update must give each.
- Lantern's cases `<preset>-<fork>-lc-header.bin` of phase0 to fulu, made by tests/generator/light_client.py with the pinned spec from the blocks of the `light_client/data_collection` cases: for each block of the fork, `block_to_light_client_header` of its fork's module (altair's for phase0); and for each header of an earlier fork, its upgrade to the fork by the spec's `upgrade_lc_header_to_*`. The runner checks lantern_block_to_light_client_header and lantern_upgrade_lc_header against them, and each output one byte short.
- consensus-spec-tests v1.7.0-beta.4, `tests/minimal/<fork>/light_client/data_collection/` of altair to fulu (the cases of bellatrix and capella cross two forks, with the fork epochs of their `config.yaml`). The runner follows the case's steps:
  - `initial_state`: lantern_node_anchor of it gives the anchor block, the model's genesis block; then lantern_lc_store_init.
  - `new_block`: the block's state transition on its parent's post-state, the state crossing each fork boundary before it (process_slots to the fork's first slot, then lantern_node_upgrade); then lantern_lc_on_block.
  - `new_head`: lantern_lc_on_head with the `finalized_checkpoint` of the head's post-state; then the checks: lantern_lc_read of each bootstrap's root and each period of `best_updates`, and of the latest finality and optimistic updates, must give the case's bytes, or `LANTERN_NO_STATE_ANSWER` where the case has none; each object's fork must be that of its `fork_digest`; `latest_finalized_epoch` and `latest_finalized_root` must be `latest_finalized_checkpoint`.
  - The runner starts with capacities of 2 and grows a part with lantern_lc_store_copy when a function gives `LANTERN_BUFFER_TOO_SMALL`, then calls it again; the store must hold the same data after it.
  - After the steps, three nodes of the case's anchor, each with a copy of the store as its light client store, meet the runner's peer (node.md, Test vectors): the first serves the light client methods, with the bootstraps of the anchor's root and of up to 7 blocks of the case, and publishes the store's updates; the second and third validate the peer's updates.
- Not run: `light_client/sync`, the light client's own sync (lantern is a beacon node).

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_state_branch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_execution_branch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_is_better_update`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_block_to_light_client_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_upgrade_lc_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_object`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_lc_anchor_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_lc_store_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_store_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_store_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_on_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_on_head`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_read`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
