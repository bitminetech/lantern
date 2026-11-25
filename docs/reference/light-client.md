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
- [`lantern_lc_add_block`](#function-lantern_lc_add_block): adds the LcBlock of a block and its post-state to an LcStore.
- [`lantern_lc_add_bootstrap`](#function-lantern_lc_add_bootstrap): adds the LcBootstrap of an LcFinalized to an LcStore.
- [`lantern_lc_alloc`](#function-lantern_lc_alloc): takes a free record of a part of an LcStore.
- [`lantern_lc_ancestor`](#function-lantern_lc_ancestor): the entry of the highest slot at most a slot along the parents of an entry.
- [`lantern_lc_at`](#function-lantern_lc_at): the address of an entry or record of a part of an LcStore.
- [`lantern_lc_beacon_root`](#function-lantern_lc_beacon_root): hash_tree_root of a BeaconBlockHeader.
- [`lantern_lc_better`](#function-lantern_lc_better): whether a new LcUpdate is better than an old one.
- [`lantern_lc_better_parts`](#function-lantern_lc_better_parts): the LcParts of an LcUpdate of a fork, for lantern_lc_better.
- [`lantern_lc_collect`](#function-lantern_lc_collect): frees the records of an LcStore that nothing refers to.
- [`lantern_lc_committee`](#function-lantern_lc_committee): an LcCommittee reference of sync committee bytes.
- [`lantern_lc_empty_header`](#function-lantern_lc_empty_header): a new LcHeader that holds the empty header of a fork.
- [`lantern_lc_equal`](#function-lantern_lc_equal): whether two byte strings of a multiple of 8 bytes are equal.
- [`lantern_lc_finalized_at`](#function-lantern_lc_finalized_at): the LcFinalized of the highest slot at most a slot.
- [`lantern_lc_find_block`](#function-lantern_lc_find_block): the LcBlock of a root in an LcStore.
- [`lantern_lc_free_count`](#function-lantern_lc_free_count): the free records of a part of an LcStore.
- [`lantern_lc_make_update`](#function-lantern_lc_make_update): a new LcUpdate: the update of an entry with a signature slot, a sync aggregate and a committee.
- [`lantern_lc_mark`](#function-lantern_lc_mark): marks a record of an LcStore as referred to.
- [`lantern_lc_mem`](#function-lantern_lc_mem): the bytes of an entry or record of a part of an LcStore.
- [`lantern_lc_part`](#function-lantern_lc_part): the first entry or record of a part of an LcStore.
- [`lantern_lc_participants`](#function-lantern_lc_participants): the participants of a SyncAggregate.
- [`lantern_lc_prune`](#function-lantern_lc_prune): drops the LcBlock entries of slots below a slot.
- [`lantern_lc_ref`](#function-lantern_lc_ref): the address of a record of an LcStore from its reference.
- [`lantern_lc_reserve`](#function-lantern_lc_reserve): whether an LcStore has free headers, committees and updates.
- [`lantern_lc_set_period`](#function-lantern_lc_set_period): sets the update of a period of an LcStore.
- [`lantern_lc_update_fields`](#function-lantern_lc_update_fields): the fields of a LightClientUpdate that is_better_update compares.
- [`lantern_node_lc_chunk`](#function-lantern_node_lc_chunk): one light client object as a response chunk of a stream.
- [`lantern_node_lc_due`](#function-lantern_node_lc_due): queues the light client updates that are due for gossip.
- [`lantern_node_lc_due_ms`](#function-lantern_node_lc_due_ms): the due time of a light client update of a signature slot.
- [`lantern_node_lc_error_chunk`](#function-lantern_node_lc_error_chunk): a response chunk of an error result.
- [`lantern_node_lc_event`](#function-lantern_node_lc_event): queues the API event of a light client topic.
- [`lantern_node_lc_head_done`](#function-lantern_node_lc_head_done): handles the end of a NODE_WORK_LC_HEAD.
- [`lantern_node_lc_new`](#function-lantern_node_lc_new): whether the update of a light client work's event is new for a topic.
- [`lantern_node_lc_publish_work`](#function-lantern_node_lc_publish_work): queues a NODE_WORK_LC_PUBLISH of a topic.
- [`lantern_node_lc_published`](#function-lantern_node_lc_published): handles the end of a NODE_WORK_LC_PUBLISH.
- [`lantern_node_lc_request`](#function-lantern_node_lc_request): starts serving a light client request of a stream.
- [`lantern_node_lc_served`](#function-lantern_node_lc_served): handles the end of a NODE_WORK_LC_SERVE.
- [`lantern_node_lc_set`](#function-lantern_node_lc_set): sets the fields of a light client topic from a work's event.
- [`lantern_node_lc_slots`](#function-lantern_node_lc_slots): the fields of the latest update of a light client work.
- [`lantern_node_lc_validated`](#function-lantern_node_lc_validated): handles the end of a NODE_WORK_LC_GOSSIP.
- [`lantern_node_run_lc`](#function-lantern_node_run_lc): runs a NODE_WORK_LC_BLOCK or NODE_WORK_LC_HEAD work.
- [`lantern_node_run_lc_gossip`](#function-lantern_node_run_lc_gossip): runs a NODE_WORK_LC_PUBLISH or NODE_WORK_LC_GOSSIP work.
- [`lantern_node_run_lc_serve`](#function-lantern_node_run_lc_serve): runs a NODE_WORK_LC_SERVE work.
- [`lantern_node_api_lc`](#function-lantern_node_api_lc): starts a light client read of the Beacon API.
- [`lantern_node_api_lc_read`](#function-lantern_node_api_lc_read): the light client read of a NODE_WORK_API_ENCODE.

### Types

- [`LcParts`](#type-lcparts): the parts of a light client object.
- [`LcRoom`](#type-lcroom): LcRoom.
- [`LcStore`](#type-lcstore): the light client data of a node: the model's `LightClientDataStore` (`cache` and `db`) and the parts of its test that it reads (`blocks`, `finalized_block_roots`, `latest_finalized_epoch`, `latest_finalized_bid`, `historical_tail_slot`).
- [`LcBlock`](#type-lcblock): a block from the finalized one on: the model's `blocks` entry and, from `tail_slot`, its `CachedLightClientData`.
- [`LcFinalized`](#type-lcfinalized): LcFinalized.
- [`LcPeriod`](#type-lcperiod): LcPeriod.
- [`LcBootstrap`](#type-lcbootstrap): LcBootstrap.
- [`LcHeader`](#type-lcheader): LcHeader.
- [`LcCommittee`](#type-lccommittee): LcCommittee.
- [`LcUpdate`](#type-lcupdate): an update, or a finality update.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), `light-client/full-node.md` and `light-client/sync-protocol.md` of altair, capella, deneb and electra. Fulu has no light-client folder: its light client types and rules are electra's.
- Section: `block_to_light_client_header` of altair, capella and deneb `full-node.md`; `upgrade_lc_header_to_capella`, `upgrade_lc_header_to_deneb` and `upgrade_lc_header_to_electra` of their `fork.md`; `compute_merkle_proof` and the gindex functions (`current_sync_committee_gindex_at_slot`, `next_sync_committee_gindex_at_slot`, `finalized_root_gindex_at_slot`, `EXECUTION_PAYLOAD_GINDEX`); `is_better_update`, `is_sync_committee_update`, `is_finality_update`.
- `compute_merkle_proof` is asm-ssz `ssz_build_proof` (its proofs.md: the spec's name for `build_proof` of ssz-specs v0.1.0).
- The light client data of a node (the `LcStore` functions): the model of the pinned test helper [tests/core/pyspec/eth_consensus_specs/test/helpers/light_client_data_collection.py](https://github.com/ethereum/consensus-specs/blob/aa16bb4c156184e9548a997d53efaf2a228a6304/tests/core/pyspec/eth_consensus_specs/test/helpers/light_client_data_collection.py), which makes the `light_client/data_collection` vectors: `setup_lc_data_collection_test`, `_process_new_block_for_light_client`, `_create_lc_update`, `_cache_lc_data`, `_create_lc_update_from_lc_data`, `_create_lc_finality_update_from_lc_data`, `select_new_head`, `_process_head_change_for_light_client`, `_process_finalization_for_light_client`, `_create_lc_bootstrap` and the `get_light_client_*` reads. The spec's own rules for this data are `create_light_client_bootstrap`, `create_light_client_update` and the "Deriving light client data" section of altair `full-node.md`; the model applies them.

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
- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Takes the roots of the state's fields as lantern_state_root does, the cache brought up to the state the same way; with `cache` 0, or a tree's capacity passed, the roots of ssz_hash_tree_root of each field.
- `LC_BRANCH_FINALIZED_ROOT`: the first root is hash_tree_root of `finalized_checkpoint.epoch`; the others are those of the field `finalized_checkpoint`.
- The others: the siblings of the field's leaf in the tree of the field roots, padded with zero chunks to the next power of two, from the leaf's level up.
- Phase0 has no light client data: the phase0 object's copy returns `LANTERN_NO_STATE_ANSWER` and writes nothing.
- The generalized index of `current_sync_committee` of `BeaconState`: 54 in altair to deneb, 86 in electra and fulu; its branch has 5; electra 6 roots.
- The generalized index of `next_sync_committee` of `BeaconState`: 55 in altair to deneb, 87 in electra and fulu; its branch has 5; electra 6 roots.
- The generalized index of `finalized_checkpoint.root` of `BeaconState`: 105 in altair to deneb, 169 in electra and fulu; its branch has 6; electra 7 roots.

### Function never

- Writes outside `cache`, `scratch`, `out` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_state_branch` in the object of every fork, with `_` before it on macOS; `lantern_state_branch` inside the object.
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
- Phase0 has no light client data: the phase0 object's copy returns `LANTERN_NO_STATE_ANSWER` and writes nothing.
- The generalized index of `execution_payload` of `BeaconBlockBody`, from capella: 25 in altair to deneb, 25 in electra and fulu; its branch has 4 roots.
- A branch is the sibling of each node on the path from the leaf up to the root, in that order, 32 bytes each, as `compute_merkle_proof` gives it.

### Function never

- Writes outside `scratch`, `out` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_execution_branch` in the object of every fork, with `_` before it on macOS; `lantern_execution_branch` inside the object.
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
- Phase0 has no light client data: the phase0 object's copy returns `LANTERN_NO_STATE_ANSWER` and writes nothing.
- The participants of a `SyncAggregate` are the set bits of its `sync_committee_bits`.

### Function never

- Writes outside `out` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 160 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_is_better_update` in the object of every fork, with `_` before it on macOS; `lantern_is_better_update` inside the object.
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
- Phase0 has no light client data: the phase0 object's copy returns `LANTERN_NO_STATE_ANSWER` and writes nothing.

### Function never

- Writes outside `scratch`, `out` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_block_to_light_client_header` in the object of every fork, with `_` before it on macOS; `lantern_block_to_light_client_header` inside the object.
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
- Phase0 has no light client data: the phase0 object's copy returns `LANTERN_NO_STATE_ANSWER` and writes nothing.

### Function never

- Writes outside `out` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_upgrade_lc_header` in the object of every fork, with `_` before it on macOS; `lantern_upgrade_lc_header` inside the object.
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
- Phase0 has no light client data: the phase0 object's copy returns `LANTERN_NO_STATE_ANSWER` and writes nothing.
- A light client object's fork is that of the slot of its `attested_header.beacon.slot` (a bootstrap's: `header.beacon.slot`); its bytes are those of the fork's type.

### Function never

- Writes outside `out` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_lc_object` in the object of every fork, with `_` before it on macOS; `lantern_lc_object` inside the object.
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
- Phase0 has no light client data: the phase0 object's copy returns `LANTERN_NO_STATE_ANSWER` and writes nothing.

### Function never

- Writes outside `scratch`, `out` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_lc_anchor_header` in the object of every fork, with `_` before it on macOS; `lantern_lc_anchor_header` inside the object.
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

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_store_size`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
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

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- `tail_slot`: the higher of the state's slot and the first slot of `ALTAIR_FORK_EPOCH`. `historical_tail_slot`: the state's slot.
- `latest_finalized_epoch`: the epoch of the state's `finalized_checkpoint`; `latest_finalized_slot`: that epoch's first slot; `latest_finalized_root`: its root. `latest`: 0, no update.
- The block's `LcBlock`, as lantern_lc_on_block makes one, its header lantern_lc_anchor_header of the fork of the state's slot, and an `LcFinalized` of its slot and root.
- From altair: the entry's data from the state (its branches, committees and `finalized_slot`), no best update, `latest_signature_slot` `GENESIS_SLOT`; and its `LcBootstrap`.
- Every record of the other capacities is `LC_FREE`.

### Function never

- Writes outside `scratch`, `lc` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_store_init`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
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
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_store_copy`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
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

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- The header: lantern_block_to_light_client_header of the block's fork, an `LcHeader` of that fork (altair for phase0). The root: hash_tree_root of its `beacon`, which is that of the block's message.
- An `LcBlock` of the root, the parent root, the slot, the parent's entry, the header, and from altair the body's `sync_aggregate`.
- At a slot below `tail_slot`, nothing more. Else its data, with A the parent's entry, n the participants of the block's sync aggregate, and P the period:
  - The branches: lantern_state_branch of the state for each field, with `cache`; `finalized_slot`: the first slot of the epoch of the state's `finalized_checkpoint`; `current_sync_committee` and `next_sync_committee`: those of the state, each sharing the parent's record of equal bytes.
  - A's slot below `tail_slot`: no best update and `latest_signature_slot` `GENESIS_SLOT`.
  - Else `best` A's when P of A's slot is P of the block's slot, else none; `latest_signature_slot` A's when n is below `MIN_SYNC_COMMITTEE_PARTICIPANTS`, else the block's slot.
  - Then, with n at least `MIN_SYNC_COMMITTEE_PARTICIPANTS` and the two periods equal: U, [the update of A](#function-lantern_lc_make_update) with the block's slot, its sync aggregate and the entry's `next_sync_committee`. U becomes `best` when there is none, or when lantern_is_better_update of U's fork gives 1 for U and `best` upgraded to that fork (each header through lantern_upgrade_lc_header, the branches as lantern_lc_object normalizes them).
- The checks of room come before any change.

### Function never

- Writes outside `lc`, `cache`, `scratch` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_on_block`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
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
  - `latest`: with s H's `latest_signature_slot`, S the entry of the highest slot at most s along the parents from H, and A the entry of the highest slot below S's along the parents from S: [the finality update of A](#function-lantern_lc_make_update) with s and S's sync aggregate. None when s is at most `low_slot`, or there is no S, or S is at most `low_slot`, or there is no A, or A is below `low_slot`.
- Then the checkpoint, when its epoch is not `GENESIS_EPOCH` and its root's entry F has a slot above `latest_finalized_slot`:
  - An `LcFinalized` of each entry from F along the parents with a slot above `latest_finalized_slot` (the old value) and above the slot of the last `LcFinalized`; then `latest_finalized_epoch` the checkpoint's epoch, and `latest_finalized_slot` and `latest_finalized_root` F's.
  - With F at least `tail_slot`: with `low_slot` the higher of the old `latest_finalized_slot` plus 1 and `tail_slot`, and b first F's slot, while b is at least `low_slot`: E the `LcFinalized` of the highest slot at most b and at least `historical_tail_slot` (with none, the loop ends); when E is at least `low_slot` and has no `LcBootstrap`, an `LcBootstrap` of E's root, slot, and its `LcBlock`'s header, `current_sync_committee` and current branch; then b is the first slot of the epoch of E's slot plus `SLOTS_PER_EPOCH` minus 1, and the loop ends when b is below `SLOTS_PER_EPOCH`, else b goes down by `SLOTS_PER_EPOCH`.
  - The entries of slots below F's go; an entry whose parent went has no parent.
- The checks of room come before any change.

### Function never

- Writes outside `lc`, `scratch` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_on_head`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
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
- A light client object's fork is that of the slot of its `attested_header.beacon.slot` (a bootstrap's: `header.beacon.slot`); its bytes are those of the fork's type.

### Function never

- Writes outside `out`, `fork` and its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_read`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `lc`, `kind`, `key`, `out`, `fork`.

## Function `lantern_lc_add_block`

Adds the LcBlock of a block and its post-state to an LcStore.

### Signature

```
lantern_lc_add_block(store, config, state, block, cache, scratch, anchor) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `config` | input | [`Config`](helpers.md#type-config) |
| `state` | input | `BeaconState`: the block's post-state |
| `block` | input | ByteList: the SSZ bytes of the `SignedBeaconBlock` |
| `cache` | state | [`StateCache`](state.md#type-statecache), or 0 |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `anchor` | input | u64 in a register: 1 for the anchor of lantern_lc_store_init, else 0 for lantern_lc_on_block |

### Returns

- `LANTERN_OK`: the store holds the block's LcBlock and the updates it makes.
- `LANTERN_BUFFER_TOO_SMALL`: a part of the store or `scratch` is short.
- `LANTERN_INVALID_ENCODING`, `LANTERN_INVALID_EVENT` or `LANTERN_INVALID_UNKNOWN_BLOCK`: the block does not fit the store.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Does the steps of the spec's light client data collection for one block, as the pinned light_client_data_collection.py does.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_add_block`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64 `anchor` is in rax.
- Argument order: `store`, `config`, `state`, `block`, `cache`, `scratch`, `anchor`.

## Function `lantern_lc_add_bootstrap`

Adds the LcBootstrap of an LcFinalized to an LcStore.

### Signature

```
lantern_lc_add_bootstrap(store, finalized)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `finalized` | input | [`LcFinalized`](#type-lcfinalized) |

### Caller must

- The store has room for one more bootstrap.

### Function does

- Adds an [`LcBootstrap`](#type-lcbootstrap) of the root when the store holds none of it and holds its LcBlock with data.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_add_bootstrap`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`, `finalized`.

## Function `lantern_lc_alloc`

Takes a free record of a part of an LcStore.

### Signature

```
lantern_lc_alloc(store, part) -> reference
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `part` | input | u64 in a register: the part |

### Function does

- Marks a free record of the part `LC_USED` and returns its reference, or 0 when there is none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_alloc`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13; rax, rcx, rdx, r8; a0, a2 to a4, a7, t0 to t4.
- Argument order: `store`, `part`.

## Function `lantern_lc_ancestor`

The entry of the highest slot at most a slot along the parents of an entry.

### Signature

```
lantern_lc_ancestor(store, entry, slot) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `entry` | input | u64 in a register: an entry, its index plus 1 |
| `slot` | input | u64 in a register |

### Function does

- Returns the entry (index plus 1) of the highest slot at most `slot` along the parents from `entry`, or 0.

### Function never

- Writes memory but its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_ancestor`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x8 to x15; rax, rcx, rdx, rsi, r8, r9; a0 to a5, a7, t0 to t4.
- Argument order: `store`, `entry`, `slot`.

## Function `lantern_lc_at`

The address of an entry or record of a part of an LcStore.

### Signature

```
lantern_lc_at(store, part, index) -> address
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `part` | input | u64 in a register |
| `index` | input | u64 in a register |

### Function does

- Returns the address of entry or record `index` of the part.

### Function never

- Writes memory but its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_at`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It keeps `part` and `index`: x1 and x2 on ARM64; a1 to a5 on RISC-V; rdi, rsi, rdx and r9 on x86-64.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, r8; a0, a7, t0 to t4.
- Argument order: `store`, `part`, `index`.

## Function `lantern_lc_beacon_root`

hash_tree_root of a BeaconBlockHeader.

### Signature

```
lantern_lc_beacon_root(header, out)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | input | the 112 SSZ bytes of a `BeaconBlockHeader`; 8-aligned on RISC-V |
| `out` | output | Bytes32 |

### Function does

- Writes hash_tree_root of the header: its 8 chunks hashed pairwise with crypto_sha256 of asm-crypto.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 416 bytes on x86-64 (return address included), 416 bytes on ARM64, 416 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_beacon_root`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `header`, `out`.

## Function `lantern_lc_better`

Whether a new LcUpdate is better than an old one.

### Signature

```
lantern_lc_better(store, new, old, scratch) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `new` | input | [`LcUpdate`](#type-lcupdate) |
| `old` | input | [`LcUpdate`](#type-lcupdate) |
| `scratch` | scratch | `LC_COMPARE_SCRATCH` bytes, checked by the caller |

### Function does

- Returns 1 when lantern_is_better_update of the new update's fork gives 1 for it and the old update upgraded to that fork, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_better`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`, `new`, `old`, `scratch`.

## Function `lantern_lc_better_parts`

The LcParts of an LcUpdate of a fork, for lantern_lc_better.

### Signature

```
lantern_lc_better_parts(store, update, parts, fork)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `update` | input | [`LcUpdate`](#type-lcupdate) |
| `parts` | output | [`LcParts`](#type-lcparts) |
| `fork` | input | u64 in a register |

### Function does

- Writes the LcParts of the update for the fork, with the branches at their counts.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 16 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_better_parts`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On ARM64 it takes the store in x19, the fork in x24, the update in x25 and the parts in x26, the registers of lantern_lc_better; on x86-64 and RISC-V they are its arguments.
- Registers it changes, on ARM64: x0 to x2, x9 to x12.
- Argument order: `store`, `update`, `parts`, `fork`.

## Function `lantern_lc_collect`

Frees the records of an LcStore that nothing refers to.

### Signature

```
lantern_lc_collect(store)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |

### Function does

- Marks the records that nothing refers to, then makes them `LC_FREE` ([`LcStore`](#type-lcstore), Rules).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_collect`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`.

## Function `lantern_lc_committee`

An LcCommittee reference of sync committee bytes.

### Signature

```
lantern_lc_committee(store, bytes, a, b) -> reference
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `bytes` | input | the SSZ bytes of a `SyncCommittee`; 8-aligned on RISC-V |
| `a` | input | u64 in a register: a reference, or 0 |
| `b` | input | u64 in a register: a reference, or 0 |

### Function does

- Returns `a` or `b` when its committee's bytes equal `bytes`, else the reference of a new record that holds them.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_committee`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`, `bytes`, `a`, `b`.

## Function `lantern_lc_empty_header`

A new LcHeader that holds the empty header of a fork.

### Signature

```
lantern_lc_empty_header(store, fork) -> reference
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `fork` | input | u64 in a register |

### Caller must

- The store has room for the header, reserved before.

### Function does

- Returns the reference of a new [`LcHeader`](#type-lcheader): lantern_upgrade_lc_header of 112 zero bytes from altair to the fork.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 240 bytes on x86-64 (return address included), 240 bytes on ARM64, 240 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_empty_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`, `fork`.

## Function `lantern_lc_equal`

Whether two byte strings of a multiple of 8 bytes are equal.

### Signature

```
lantern_lc_equal(a, b, n) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | `n` bytes; 8-aligned on RISC-V |
| `b` | input | `n` bytes; 8-aligned on RISC-V |
| `n` | input | u64 in a register: a multiple of 8 |

### Function does

- Returns 1 when the bytes are equal, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_equal`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9, x10; rax, rcx; a0, t0, t1.
- Argument order: `a`, `b`, `n`.

## Function `lantern_lc_finalized_at`

The LcFinalized of the highest slot at most a slot.

### Signature

```
lantern_lc_finalized_at(store, slot) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `slot` | input | u64 in a register |

### Function does

- Returns the [`LcFinalized`](#type-lcfinalized) of the highest slot at most `slot` and at least `historical_tail_slot`, or 0.

### Function never

- Writes memory but its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_finalized_at`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x15; rax, rcx, rdx, rsi, r8, r9; a0 to a5, t0 to t3.
- Argument order: `store`, `slot`.

## Function `lantern_lc_find_block`

The LcBlock of a root in an LcStore.

### Signature

```
lantern_lc_find_block(store, root) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `root` | input | Bytes32 |

### Function does

- Returns the index plus 1 of the [`LcBlock`](#type-lcblock) of `root`, or 0.

### Function never

- Writes memory but its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_find_block`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x8 to x15; rax, rcx, rdx, rsi, r8, r9, r11, xmm0 to xmm2; a0, a1, a3 to a7, t0 to t3.
- Argument order: `store`, `root`.

## Function `lantern_lc_free_count`

The free records of a part of an LcStore.

### Signature

```
lantern_lc_free_count(store, part) -> count
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `part` | input | u64 in a register |

### Function does

- Returns the records of the part that are `LC_FREE`.

### Function never

- Writes memory but its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_free_count`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x14; rax, rcx, rdx, r8, r9; a0, a2 to a4, a7, t0 to t4.
- Argument order: `store`, `part`.

## Function `lantern_lc_make_update`

A new LcUpdate: the update of an entry with a signature slot, a sync aggregate and a committee.

### Signature

```
lantern_lc_make_update(store, entry, signature_slot, aggregate, committee) -> reference
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `entry` | input | u64 in a register: the reference of the attested block's [`LcBlock`](#type-lcblock) |
| `signature_slot` | input | u64 in a register |
| `aggregate` | input | `SyncAggregate` |
| `committee` | input | u64 in a register: an [`LcCommittee`](#type-lccommittee) reference, or 0 for a finality update |

### Caller must

- The store has room for the update and one LcHeader, reserved before.

### Function does

- Returns the reference of a new [`LcUpdate`](#type-lcupdate) of the fork of the attested block's header, as `_create_lc_update_from_lc_data` makes it.
- The update's `attested_header`: A's header.
- The update's `finalized_header` and `finality_branch`: the `LcFinalized` of the highest slot at most A's `finalized_slot` and at least `historical_tail_slot`. When there is one, A's `finalized_slot` becomes its slot (the model's cache update for empty slots at the end of an epoch); the header is, at slot `GENESIS_SLOT`, the empty header of the fork (lantern_upgrade_lc_header of 112 zero bytes from altair), else the header of its root's `LcBlock`, through lantern_upgrade_lc_header to the fork; the branch is A's `finality_branch`. When there is none, or the store holds no `LcBlock` of its root, the header is the empty header and the branch zero roots, as `create_light_client_update` of altair full-node.md has them without a finalized block.
- The update's `next_sync_committee` c and `next_sync_committee_branch` A's, for an update; a finality update has neither.
- The update's `sync_aggregate` g and `signature_slot` s.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_make_update`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`, `entry`, `signature_slot`, `aggregate`, `committee`.

## Function `lantern_lc_mark`

Marks a record of an LcStore as referred to.

### Signature

```
lantern_lc_mark(store, part, reference)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `part` | input | u64 in a register |
| `reference` | input | u64 in a register: a reference, or 0 for none |

### Function does

- Makes the record `LC_MARKED`; does nothing for 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_mark`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, r8; a0, a7, t0 to t4.
- Argument order: `store`, `part`, `reference`.

## Function `lantern_lc_mem`

The bytes of an entry or record of a part of an LcStore.

### Signature

```
lantern_lc_mem(part) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `part` | input | u64 in a register |

### Function does

- Returns the bytes of an entry or record of the part.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_mem`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- `part` is in x1, rsi, a1 and the bytes come back in x12, rcx, t3 on ARM64, x86-64, RISC-V.
- Argument order: `part`.

## Function `lantern_lc_part`

The first entry or record of a part of an LcStore.

### Signature

```
lantern_lc_part(store, part) -> address
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `part` | input | u64 in a register |

### Function does

- Returns the address of the part's first entry or record.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_part`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx; a0, t0 to t3.
- Argument order: `store`, `part`.

## Function `lantern_lc_participants`

The participants of a SyncAggregate.

### Signature

```
lantern_lc_participants(bits) -> count
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bits` | input | the `sync_committee_bits` of a `SyncAggregate` |

### Function does

- Returns the set bits: the participants of the aggregate.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_participants`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11, v0; rax, rcx, rdx, rsi; a0, t0 to t3.
- Argument order: `bits`.

## Function `lantern_lc_prune`

Drops the LcBlock entries of slots below a slot.

### Signature

```
lantern_lc_prune(store, slot, scratch)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `slot` | input | u64 in a register |
| `scratch` | scratch | 8 bytes for each entry, checked by the caller |

### Function does

- Drops the [`LcBlock`](#type-lcblock) entries of slots below `slot`, and gives the kept ones their new indices.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_prune`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`, `slot`, `scratch`.

## Function `lantern_lc_ref`

The address of a record of an LcStore from its reference.

### Signature

```
lantern_lc_ref(store, part, reference) -> address
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`LcStore`](#type-lcstore) |
| `part` | input | u64 in a register |
| `reference` | input | u64 in a register: not 0 |

### Function does

- Returns the address of the record.

### Function never

- Writes memory but its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_ref`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It keeps `part` and `reference` on RISC-V (a1 to a5) and x86-64 (rdi, rsi, rdx, r9).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, r8; a0, a7, t0 to t4.
- Argument order: `store`, `part`, `reference`.

## Function `lantern_lc_reserve`

Whether an LcStore has free headers, committees and updates.

### Signature

```
lantern_lc_reserve(store, headers, committees, updates) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `headers` | input | u64 in a register |
| `committees` | input | u64 in a register |
| `updates` | input | u64 in a register |

### Returns

- `LANTERN_OK`: the store has that many free records of each part.
- `LANTERN_BUFFER_TOO_SMALL`: it has not, once the records nothing refers to are freed.

### Function does

- Frees the records nothing refers to (lantern_lc_collect) when the free ones are short.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_reserve`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`, `headers`, `committees`, `updates`.

## Function `lantern_lc_set_period`

Sets the update of a period of an LcStore.

### Signature

```
lantern_lc_set_period(store, period, update)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | [`LcStore`](#type-lcstore) |
| `period` | input | u64 in a register |
| `update` | input | u64 in a register: an [`LcUpdate`](#type-lcupdate) reference, or 0 for none |

### Caller must

- The store has room for one more period, checked before.

### Function does

- Makes the [`LcPeriod`](#type-lcperiod) of `period` refer to `update`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_set_period`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `store`, `period`, `update`.

## Function `lantern_lc_update_fields`

The fields of a LightClientUpdate that is_better_update compares.

### Signature

```
lantern_lc_update_fields(update) -> (status, participants, attested_slot, finalized_slot, signature_slot, has_committee, has_finality)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `update` | input | ByteList: the SSZ bytes of a `LightClientUpdate` of the object's fork |

### Function does

- Returns 0 and the fields: the participants, attested_header.beacon.slot, finalized_header.beacon.slot, signature_slot, 1 with a next_sync_committee_branch not all zero, and 1 with a finality_branch not all zero.
- Returns 1 for bytes that are no update of the fork.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_lc_update_fields`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64 the values come back in rax, rcx, rdx, rsi, rdi, r8, r9; on RISC-V in a0 to a6; on ARM64 in x0 to x6.
- Argument order: `update`.

## Function `lantern_node_lc_chunk`

One light client object as a response chunk of a stream.

### Signature

```
lantern_node_lc_chunk(lc, kind, key, object, out, scratch, node) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `lc` | input | [`LcStore`](#type-lcstore) |
| `kind` | input | u64: the kind of object, as lantern_lc_read takes it |
| `key` | input | u64: the key, as lantern_lc_read takes it |
| `object` | output | the object's bytes |
| `out` | state | ByteList: the chunks of the response |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `node` | input | `Node` |

### Returns

- The statuses of lantern_lc_read and lantern_reqresp_write_chunk.
- `LANTERN_INVALID_ENCODING`: the object's bytes do not fit a chunk.

### Function does

- Reads the object with lantern_lc_read, then writes its response chunk after the bytes of `out`: result 0, and as context compute_fork_digest of the epoch of its attested slot.
- Leaves the size of `scratch` as it came.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_chunk`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64 `node` is in r10.
- Argument order: `lc`, `kind`, `key`, `object`, `out`, `scratch`, `node`.

## Function `lantern_node_lc_due`

Queues the light client updates that are due for gossip.

### Signature

```
lantern_node_lc_due()
```

### Function does

- At a quiet point of the step, with `lc_pending` not 0, `time_ms` at least `lc_due` and room for two works: queues a `NODE_WORK_LC_PUBLISH` of each topic of `lc_pending`, which becomes 0 (node.md, The light client gossip).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_due`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.

## Function `lantern_node_lc_due_ms`

The due time of a light client update of a signature slot.

### Signature

```
lantern_node_lc_due_ms(slot) -> time_ms
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 in a register: the signature slot |

### Function does

- Returns the genesis time + `slot` * `SLOT_DURATION_MS` + get_sync_message_due_ms(), in Unix milliseconds.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_due_ms`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11; rax, rcx, rdx; a0, a7, t0 to t2.
- Argument order: `slot`.

## Function `lantern_node_lc_error_chunk`

A response chunk of an error result.

### Signature

```
lantern_node_lc_error_chunk(result, payload, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `result` | input | u64 in a register: the response code |
| `payload` | input | ByteList: the error message |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | state | ByteList: the chunks of the response |

### Returns

- The statuses of lantern_reqresp_write_chunk.

### Function does

- Writes a response chunk of the result with no context bytes after the bytes of `out`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_error_chunk`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `result`, `payload`, `scratch`, `out`.

## Function `lantern_node_lc_event`

Queues the API event of a light client topic.

### Signature

```
lantern_node_lc_event(topic, arg)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64 in a register: the event topic |
| `arg` | input | u64 in a register: the work's argument; on ARM64 only |

### Function does

- When an API entry subscribes to the topic, queues a `NODE_WORK_API_EVENT` of it with the light client store as `state_c`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `topic`, `arg`.

## Function `lantern_node_lc_head_done`

Handles the end of a NODE_WORK_LC_HEAD.

### Signature

```
lantern_node_lc_head_done()
```

### Function does

- With a latest update, the bit of each topic it is new for joins `lc_pending`, and `lc_due` becomes its due time (node.md, The light client gossip).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_head_done`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the event in x21, r12, s3; the actions in x24, r15, s6.

## Function `lantern_node_lc_new`

Whether the update of a light client work's event is new for a topic.

### Signature

```
lantern_node_lc_new(event, topic) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of a light client work |
| `topic` | input | u64 in a register |

### Function does

- Returns 1 when the update of the event's fields is new for the topic (node.md, The light client gossip), else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_new`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx; a0, a7, t0, t1.
- Argument order: `event`, `topic`.

## Function `lantern_node_lc_publish_work`

Queues a NODE_WORK_LC_PUBLISH of a topic.

### Signature

```
lantern_node_lc_publish_work(topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | u64 in a register |

### Function does

- Queues a `NODE_WORK_LC_PUBLISH` of the topic with the light client store as `state_c`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_publish_work`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `topic`.

## Function `lantern_node_lc_published`

Handles the end of a NODE_WORK_LC_PUBLISH.

### Signature

```
lantern_node_lc_published()
```

### Function does

- For `LANTERN_VALID` of an update new for its topic: sets the topic's fields; then with `NODE_FLAG_SUBSCRIBED` its bytes at `NodeEvent_chunk` go out on the topic, and its API event is queued (node.md, The light client gossip).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_published`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the event in x21, r12, s3; the actions in x24, r15, s6.

## Function `lantern_node_lc_request`

Starts serving a light client request of a stream.

### Signature

```
lantern_node_lc_request(entry, bytes, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | state | `NodeStream`: the stream's entry |
| `bytes` | input | the request's `n` bytes, or 0 for none |
| `n` | input | u64 in a register |

### Function does

- Puts the bytes under a new id and queues a `NODE_WORK_LC_SERVE` of them with the light client store as `state_c`.
- The stream takes `NODE_STREAM_SERVING`, its list empty.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_request`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `entry`, `bytes`, `n`.

## Function `lantern_node_lc_served`

Handles the end of a NODE_WORK_LC_SERVE.

### Signature

```
lantern_node_lc_served()
```

### Function does

- Frees the work's bytes, then sends the chunks to the stream in a `STREAM_WRITE` and a `STREAM_CLOSE`, or a `STREAM_RESET`; then the stream's entry goes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 112 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_served`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the event in x21, r12, s3; the actions in x24, r15, s6.

## Function `lantern_node_lc_set`

Sets the fields of a light client topic from a work's event.

### Signature

```
lantern_node_lc_set(event, topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `NodeEvent` of a light client work |
| `topic` | input | u64 in a register |

### Function does

- The fields of the topic take the update of the event (node.md, The light client gossip).

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_set`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Registers it changes, on ARM64, x86-64, RISC-V: x9, x10; rcx; a7, t0, t1.
- Argument order: `event`, `topic`.

## Function `lantern_node_lc_slots`

The fields of the latest update of a light client work.

### Signature

```
lantern_node_lc_slots(lc, event) -> found
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `lc` | input | [`LcStore`](#type-lcstore) |
| `event` | state | `NodeEvent` of a light client work |

### Function does

- Writes the latest update's fields into the event: its finalized slot, its attested slot, its supermajority, 1, and its signature slot.
- Returns 1, or 0 with no latest update.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_slots`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `lc`, `event`.

## Function `lantern_node_lc_validated`

Handles the end of a NODE_WORK_LC_GOSSIP.

### Signature

```
lantern_node_lc_validated()
```

### Function does

- Gives an ACCEPT for `LANTERN_VALID` of an update new for its topic that is due by `time_ms` + `MAXIMUM_GOSSIP_CLOCK_DISPARITY`, with the topic's fields and its API event; else an IGNORE.
- Then the work's bytes and the message's entry go.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_lc_validated`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the store in x20, rbp, s2; the event in x21, r12, s3; the actions in x24, r15, s6.

## Function `lantern_node_run_lc`

Runs a NODE_WORK_LC_BLOCK or NODE_WORK_LC_HEAD work.

### Signature

```
lantern_node_run_lc(node, store, work, state_a, data, state_c, scratch, event) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | `Node` |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `work` | input | `NodeWork` |
| `state_a` | input | `BeaconState` |
| `data` | input | ByteList: the work's data |
| `state_c` | state | [`LcStore`](#type-lcstore) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `event` | output | `NodeEvent` |

### Returns

- `LANTERN_OK`: `event` holds the result.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` or the store is short.
- `LANTERN_INVALID_EVENT`: the work is not one it runs.

### Function does

- A light client work of lantern_node_run (node.md): lantern_lc_on_block or lantern_lc_on_head, then the latest update's fields; or the gossip and serve works through lantern_node_run_lc_gossip and lantern_node_run_lc_serve.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_run_lc`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On ARM64 x8 holds the event's room; on x86-64 `scratch` and `event` are in r10 and r11.
- Argument order: `node`, `store`, `work`, `state_a`, `data`, `state_c`, `scratch`, `event`.

## Function `lantern_node_run_lc_gossip`

Runs a NODE_WORK_LC_PUBLISH or NODE_WORK_LC_GOSSIP work.

### Signature

```
lantern_node_run_lc_gossip(node, work, data, lc, scratch, event, room) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | `Node` |
| `work` | input | `NodeWork` |
| `data` | input | ByteList: for gossip, the message's bytes |
| `lc` | input | [`LcStore`](#type-lcstore) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `event` | output | `NodeEvent` |
| `room` | input | u64 in a register: the event's room |

### Returns

- `LANTERN_OK`: `event` holds the result.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` or the event's room is short.
- `LANTERN_INVALID_EVENT`: the work's topic is not a light client topic.

### Function does

- Writes the latest update of the topic `arg` as a ByteList: at `NodeEvent_chunk` of the event for PUBLISH, at the end of `scratch` for GOSSIP, where it is matched against `data`; then its fields and the result.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_run_lc_gossip`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64 `room` is in r10.
- Argument order: `node`, `work`, `data`, `lc`, `scratch`, `event`, `room`.

## Function `lantern_node_run_lc_serve`

Runs a NODE_WORK_LC_SERVE work.

### Signature

```
lantern_node_run_lc_serve(node, work, data, lc, scratch, event, room) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | `Node` |
| `work` | input | `NodeWork` |
| `data` | input | ByteList: the request's bytes |
| `lc` | input | [`LcStore`](#type-lcstore) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `event` | output | `NodeEvent` |
| `room` | input | u64 in a register: the event's room |

### Returns

- `LANTERN_OK`: the event holds the response chunks at `NodeEvent_chunk`.
- `LANTERN_BUFFER_TOO_SMALL`, `LANTERN_INVALID_ENCODING` or `LANTERN_NO_STATE_ANSWER`: as the chunk functions give them.

### Function does

- Writes the response chunks of the light client method `arg` at `NodeEvent_chunk` of the event.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_run_lc_serve`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64 `room` is in r10.
- Argument order: `node`, `work`, `data`, `lc`, `scratch`, `event`, `room`.

## Function `lantern_node_api_lc`

Starts a light client read of the Beacon API.

### Signature

```
lantern_node_api_lc(route, connection, flags) -> zero
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `route` | input | the request's route |
| `connection` | input | u64 in a register |
| `flags` | input | u64 in a register: the answer flags |

### Function does

- Puts the request's bytes under a new id and queues a `NODE_WORK_API_ENCODE` with the light client store as `state_c`; returns 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_lc`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1; the actions in x24, r15, s6.
- Argument order: `route`, `connection`, `flags`.

## Function `lantern_node_api_lc_read`

The light client read of a NODE_WORK_API_ENCODE.

### Signature

```
lantern_node_api_lc_read(lc, work, data, scratch, view) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `lc` | input | [`LcStore`](#type-lcstore) |
| `work` | input | `NodeWork` |
| `data` | input | ByteList |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `view` | output | `ApiView` |

### Returns

- `LANTERN_OK`: the view holds the answer.
- `LANTERN_BUFFER_TOO_SMALL`, `LANTERN_INVALID_EVENT` or `LANTERN_NO_STATE_ANSWER`: the read failed.

### Function does

- For getLightClientUpdatesByRange: writes the store, periods, JSON room and cursor into the view, which its body reads.
- Else writes the object's SSZ bytes (`ApiView_lc_bytes`), its fork, and as JSON its JSON (`ApiView_lc_json`); with no object, `ApiView_status` 404.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 112 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_node_api_lc_read`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the node in x19, rbx, s1.
- Argument order: `lc`, `work`, `data`, `scratch`, `view`.

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

The capacities of the parts of an LcStore.

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

A finalized block that an LcStore keeps: its slot, its header and its finality branch.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `slot` | u64 | |
| 8 | `root` | Root | A finalized block's: the model's `finalized_block_roots` |

### Rules

- `LcFinalized__mem` (40) bytes.

## Type `LcPeriod`

The best update of one sync committee period in an LcStore.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `period` | u64 | |
| 8 | `update` | u64 | `LcUpdate` reference: the model's `best_updates` of the period |

### Rules

- `LcPeriod__mem` (16) bytes.
- The period of a slot is compute_sync_committee_period_at_slot: the slot over `SLOTS_PER_EPOCH` times `EPOCHS_PER_SYNC_COMMITTEE_PERIOD`; the first slot of a period is the period times that.

## Type `LcBootstrap`

An LcStore record of a light client bootstrap.

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

An LcStore record of a light client header of a fork.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `state` | u64 | `LC_FREE`, `LC_USED` or `LC_MARKED` |
| 8 | `fork` | u64 | `FORK_*` of the header's type, altair or later |
| 16 | `header` | ByteList | The SSZ bytes of a `LightClientHeader`, room for `LC_HEADER_ROOM` bytes |

### Rules

- `LcHeader__mem` (40 + `LC_HEADER_ROOM`) bytes; `LC_HEADER_ROOM` (864) holds 244 bytes, a deneb `ExecutionPayloadHeader`'s fixed part and `MAX_EXTRA_DATA_BYTES`.

## Type `LcCommittee`

An LcStore record of a sync committee.

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
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_execution_branch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_is_better_update`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_block_to_light_client_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_upgrade_lc_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
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
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_store_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_store_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_on_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_on_head`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_lc_read`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
