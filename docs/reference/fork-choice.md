# Fork choice

## Contents

### Functions

- [`lantern_get_forkchoice_store`](#function-lantern_get_forkchoice_store): a store from an anchor state and block.
- [`lantern_store_size`](#function-lantern_store_size): the buffer size of a store with given capacities.
- [`lantern_store_copy`](#function-lantern_store_copy): copies a store into a buffer with more capacity.
- [`lantern_store_justified_checkpoint_state`](#function-lantern_store_justified_checkpoint_state): keeps what the store needs of the justified checkpoint state.
- [`lantern_get_current_slot`](#function-lantern_get_current_slot): the slot of the store's time.
- [`lantern_get_current_store_epoch`](#function-lantern_get_current_store_epoch): the epoch of the store's time.
- [`lantern_get_ancestor`](#function-lantern_get_ancestor): the ancestor of a node at a slot.
- [`lantern_get_checkpoint_block`](#function-lantern_get_checkpoint_block): the block of an epoch in the chain of a root.
- [`lantern_get_weight`](#function-lantern_get_weight): the attesting balance and boost of a node.
- [`lantern_get_filtered_node_tree`](#function-lantern_get_filtered_node_tree): the nodes of the viable branches.
- [`lantern_get_head`](#function-lantern_get_head): the head of LMD GHOST over the viable branches.
- [`lantern_on_tick`](#function-lantern_on_tick): moves the store's time forward.
- [`lantern_on_block`](#function-lantern_on_block): adds a block to the store.
- [`lantern_validate_merge_block`](#function-lantern_validate_merge_block): checks the terminal PoW block of the first payload.
- [`lantern_is_valid_terminal_pow_block`](#function-lantern_is_valid_terminal_pow_block): whether a PoW block reaches the terminal total difficulty and its parent does not.
- [`lantern_validate_on_attestation`](#function-lantern_validate_on_attestation): the store checks of an attestation.
- [`lantern_store_target_checkpoint_state`](#function-lantern_store_target_checkpoint_state): advances a block state to its checkpoint.
- [`lantern_on_attestation`](#function-lantern_on_attestation): records the votes of an attestation.
- [`lantern_on_attester_slashing`](#function-lantern_on_attester_slashing): records equivocating validators.
- [`lantern_get_proposer_head`](#function-lantern_get_proposer_head): the head to build on, or its parent for a reorg.
- [`lantern_store_payload_status`](#function-lantern_store_payload_status): records a later answer of the execution engine for a block.
- [`lantern_store_prune`](#function-lantern_store_prune): drops the nodes that do not descend from the finalized node.
- [`lantern_is_data_available`](#function-lantern_is_data_available): checks the blobs or the column sidecars of a block.
- [`lantern_verify_data_column_sidecar`](#function-lantern_verify_data_column_sidecar): checks the lengths of a column sidecar.
- [`lantern_verify_data_column_sidecar_kzg_proofs`](#function-lantern_verify_data_column_sidecar_kzg_proofs): checks the cells of a column sidecar.

### Types

- [`Store`](#type-store): the fork choice store.
- [`BlockNode`](#type-blocknode): one block of the store.
- [`StoreValidator`](#type-storevalidator): the latest message and justified balance of one validator.
- [`StoreRoom`](#type-storeroom): the capacities of a store.
- [`BlockOptions`](#type-blockoptions): the answers of the execution engine and of data availability for a block.
- [`ColumnSidecars`](#type-columnsidecars): a list of column sidecars.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), `phase0/fork-choice.md` with the changes of `bellatrix`, `capella`, `deneb` and `fulu`, `bellatrix/optimistic-sync.md`, and `fulu/p2p-interface.md` for the column sidecar checks.
- Section: Fork choice, each function at its definition in the fork of its object, from phase0 to fulu.

## Common rules

- As in [block-processing.md](block-processing.md#common-rules).
- A `ForkChoiceNode` is a u64: the index of its `BlockNode` in the store. The spec's nodes are always blocks of `store.blocks`, and a root names one node, so the index stands for the root.
- `store.blocks` is the `blocks` part of the `Store`; a `BlockNode` keeps the fields of the block that fork choice reads.
- The caller keeps `store.block_states` and `store.checkpoint_states`, and passes the state a function reads as an argument. The store keeps the fields of those states that fork choice reads again later: the post-state `current_justified_checkpoint` of each block, and the balances of the justified checkpoint state.
- `store.checkpoint_states[store.justified_checkpoint]` is read through the balances of the store. A function that reads it returns `LANTERN_NEED_JUSTIFIED_STATE`, before any change, when `balances_checkpoint` is not `justified_checkpoint`. The caller then passes that checkpoint state to lantern_store_justified_checkpoint_state and calls again.
- A function that changes the store makes every check first and changes the store only after the last check holds, so a call that fails a spec check leaves the store unchanged ("Invalid calls to handlers must not modify store").
- The config is the store's copy, made by lantern_get_forkchoice_store.
- lantern_store_size, lantern_store_copy, lantern_store_payload_status and lantern_store_prune read no fork's layouts. Each is in the common object of the core (asm/core/<ISA>/common.s), and its symbol is its name.
- A Uint64 result outside 0 to 2^64 - 1 fails with `LANTERN_INVALID_OVERFLOW`, as the spec's Uint64 does.
- Optimistic sync: each node keeps the execution engine's answer for its payload as a `PayloadValidationStatus` (`PAYLOAD_STATUS_*` of bellatrix p2p-interface.md). An `INVALIDATED` node is removed from fork choice ("Consensus engines MUST support removing blocks from fork choice that transition from `NOT_VALIDATED` to `INVALIDATED`"): it and its subtree are not in the tree of get_filtered_node_tree, so get_head never walks to them, and get_weight counts neither the latest messages for them nor a proposer boost of them.
- Spec helpers that only these functions call are L0 helpers of `asm/core/<ISA>/forkchoice.s`, named by the spec: get_voting_source, get_attestation_score, get_proposer_score, calculate_committee_fraction, update_checkpoints, update_unrealized_checkpoints, on_tick_per_slot, record_block_timeliness, get_shuffling_dependent_root, update_proposer_boost_root, compute_pulled_up_tip, update_latest_messages, is_head_weak, is_parent_strong and is_proposer_equivocation.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/fork_choice/<handler>/` of altair to fulu, for mainnet and minimal.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.
  - The runner follows `tests/formats/fork_choice/README.md` of the spec: it keeps the block states and checkpoint states, runs the attestations and attester slashings of each valid block after it, and checks `head` with lantern_get_head and `get_proposer_head` with lantern_get_proposer_head at the head and the current slot.
  - Bellatrix: the `pow_block` steps are the PowBlocks of get_pow_block; the runner passes the one whose hash is the payload's parent_hash, and its parent, in `BlockOptions`.
  - Deneb and electra: the `blobs` and `proofs` of a block step go to lantern_is_data_available with the body's blob_kzg_commitments. Fulu: the `columns` of a block step go to lantern_is_data_available.
- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/sync/optimistic/` of bellatrix to fulu: the fork choice format with `payload_status` steps.
  - The runner maps `VALID` to `PAYLOAD_STATUS_VALID`, `SYNCING` and `ACCEPTED` to `NOT_VALIDATED`, `INVALID` and `INVALID_BLOCK_HASH` to `INVALIDATED`, and passes it in `BlockOptions`.
  - For `INVALID` with a `latest_valid_hash`, it first sets `INVALIDATED` with lantern_store_payload_status on each ancestor of the block whose `block_hash` is not that hash, as the spec's test helper `add_optimistic_block` does.
- The fork choice compliance cases of the release, `comptests.tar.gz` with the SHA-256 in tests/generator/generate.py: `tests/minimal/<fork>/fork_choice_compliance/<handler>/` of altair to fulu, as `minimal-<fork>-fork_choice_compliance-<handler>.bin`.
  - Every case has `bls_setting` 2, so `runner-minimal-<fork>-bls-off` runs them.
  - The runner follows the spec's compliance runner (`tests/generators/compliance_runners/fork_choice/runner/test_run.py`): it ignores invalid attestations and attester slashings inside a valid block, and checks `viable_for_head_roots_and_weights` with lantern_get_filtered_node_tree and lantern_get_weight, and lantern_node_weights (node.md) against lantern_get_weight for every node.
- The KZG trusted setup: `presets/<preset>/trusted_setups/trusted_setup_4096.json` of the pinned spec, as `<preset>-kzg_setup.bin`.

## Function `lantern_get_forkchoice_store`

The store of the anchor: its block as the only node, its epoch and root as all four checkpoints, its state as the justified checkpoint state.

### Signature

```
lantern_get_forkchoice_store(anchor_state, anchor_block, config, room, scratch, store) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `anchor_state` | input | `BeaconState` |
| `anchor_block` | input | `BeaconBlock` |
| `config` | input | `Config` |
| `room` | input | `StoreRoom` |
| `scratch` | scratch | `Scratch` |
| `store` | output | `Store`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `store` holds the store.
- `LANTERN_BUFFER_TOO_SMALL`: `store` is below lantern_store_size of `room`, `room` has no node or fewer validators than the anchor state, or `scratch` is short.
- `LANTERN_INVALID_ANCHOR`: `anchor_block.state_root` is not hash_tree_root(anchor_state).
- `LANTERN_INVALID_OVERFLOW`: the anchor slot's time does not fit in a Uint64.

### Function does

- Sets `genesis_time_ms` to seconds_to_milliseconds(genesis_time), which gives UINT64_MAX when the product does not fit.
- Gives the anchor node `parent` `NODE_NONE`, `timely` 0, `justified_checkpoint` the anchor state's `current_justified_checkpoint`, and `unrealized_justified_checkpoint` the anchor checkpoint.
- Gives `room.nodes` and `room.validators` entries of capacity to the two parts; every `StoreValidator` starts with no latest message.
- Ends with lantern_store_justified_checkpoint_state of the anchor state.

### Limits

- Scratch: S(0).

## Function `lantern_store_size`

The bytes of a store with the capacities of room.

### Signature

```
lantern_store_size(room, size) -> status
```

### Returns

- `LANTERN_OK`: `size` holds `STORE_FIXED` + `room.nodes` * `BlockNode__mem` + `room.validators` * `StoreValidator__mem`.
- `LANTERN_INVALID_OVERFLOW`: the size does not fit in a u64.

## Function `lantern_store_copy`

Copies store into out with the capacities of room: the resize function of the `Store` (ARCHITECTURE.md section 6).

### Signature

```
lantern_store_copy(store, room, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the store.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is below lantern_store_size of the capacities, or a capacity is below the entries the store holds.

### Function does

- New `StoreValidator` entries have no latest message, no balance and no flags.

## Function `lantern_store_justified_checkpoint_state`

Keeps the balances of state as those of `store.checkpoint_states[store.justified_checkpoint]`.

### Signature

```
lantern_store_justified_checkpoint_state(store, state) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `state` | input | `BeaconState`: the checkpoint state of `store.justified_checkpoint` |

### Returns

- `LANTERN_OK`: done.
- `LANTERN_BUFFER_TOO_SMALL`: the store has fewer `StoreValidator` entries than the state has validators. The store is unchanged.
- `LANTERN_INVALID_OVERFLOW`: the sum of the balances does not fit. The store is unchanged.

### Caller must

- Pass the state of store_target_checkpoint_state for `store.justified_checkpoint`, or the anchor state for the anchor checkpoint.

### Function does

- For each entry i: `effective_balance` of validator i, `STORE_IN_REGISTRY`, and `STORE_ACTIVE_UNSLASHED` when it is active at get_current_epoch(state) and not slashed; entries past the registry get 0 and lose both flags. `STORE_EQUIVOCATING` stays.
- Sets `balances_total` to get_total_balance of the active unslashed validators, and `balances_checkpoint` to `justified_checkpoint`.

## Function `lantern_get_current_slot`

(store.time_ms - store.genesis_time_ms) // SLOT_DURATION_MS.

### Signature

```
lantern_get_current_slot(store, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the slot.
- `LANTERN_INVALID_OVERFLOW`: `time_ms` is before `genesis_time_ms`.

## Function `lantern_get_current_store_epoch`

compute_epoch_at_slot(get_current_slot(store)).

### Signature

```
lantern_get_current_store_epoch(store, out) -> status
```

### Returns

- As lantern_get_current_slot.

## Function `lantern_get_ancestor`

The node itself when its slot is at most slot, else the ancestor of its parent.

### Signature

```
lantern_get_ancestor(store, node, slot, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the node.
- `LANTERN_INVALID_UNKNOWN_BLOCK`: the walk reaches a block whose parent is not in the store.

### Caller must

- Pass a node of the store.

## Function `lantern_get_checkpoint_block`

The root of get_ancestor(root, compute_start_slot_at_epoch(epoch)).

### Signature

```
lantern_get_checkpoint_block(store, root, epoch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the Root.
- `LANTERN_INVALID_UNKNOWN_BLOCK`: root is not in the store, or the walk leaves it.
- `LANTERN_INVALID_OVERFLOW`: the start slot of epoch does not fit.

## Function `lantern_get_weight`

get_attestation_score of the node with the justified checkpoint state, plus get_proposer_score when the boosted block descends from the node.

### Signature

```
lantern_get_weight(store, node, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the Gwei.
- `LANTERN_NEED_JUSTIFIED_STATE`: see Common rules.
- `LANTERN_INVALID_UNKNOWN_BLOCK`, `LANTERN_INVALID_OVERFLOW`: a spec failure of get_ancestor or of a sum.

### Function does

- get_attestation_score: the sum of `effective_balance` over the entries with `STORE_ACTIVE_UNSLASHED`, a latest message, no `STORE_EQUIVOCATING`, and is_ancestor(latest message node, node).

## Function `lantern_get_filtered_node_tree`

The nodes of the justified node's subtree on a branch whose leaf has the store's justified and finalized checkpoints.

### Signature

```
lantern_get_filtered_node_tree(store, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | `Store` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `IndexList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the nodes, in ascending order.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or `out` has too little room.
- `LANTERN_INVALID_UNKNOWN_BLOCK`, `LANTERN_INVALID_OVERFLOW`: a spec failure of get_voting_source, get_checkpoint_block or a sum.

### Caller must

- Keep `out` apart from `scratch`.

### Function does

- Marks the subtree in index order (a parent comes before its children), then runs filter_node_tree for all its nodes at once in reverse order: a node with children is in the tree when a child is; a leaf when its voting source and finalized checkpoint block agree with the store.

### Limits

- Scratch: S(1), with n the node count of the store.

## Function `lantern_get_head`

From the justified node, the child of greatest (weight, root) among the viable nodes, until a node has no viable child.

### Signature

```
lantern_get_head(store, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the head node.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.
- `LANTERN_NEED_JUSTIFIED_STATE`: see Common rules.
- `LANTERN_INVALID_UNKNOWN_BLOCK`, `LANTERN_INVALID_OVERFLOW`: a spec failure of lantern_get_filtered_node_tree or get_weight.

### Function does

- Reads the tree of lantern_get_filtered_node_tree.
- The weights of all nodes at once: each counted latest message (as get_attestation_score counts it) adds its `effective_balance` to its node, and get_proposer_score to the proposer boost node (as get_weight adds it); then, from the last node to the first, each node adds its weight to its parent's. A parent comes before its children, so each node then holds the sum over its subtree: get_weight of the node, as is_ancestor(latest message node, node) holds exactly for the messages of its subtree. A sum past 2^64 - 1, or a failure of the boost's get_proposer_score or node, is the result of the first child whose weight it is.
- Compares roots as byte strings, first byte first.

### Limits

- Scratch: S(2), with n the node count of the store.

## Function `lantern_on_tick`

on_tick_per_slot at the start of each slot up to the slot of time_ms, then at time_ms.

### Signature

```
lantern_on_tick(store, time_ms, result) -> status
```

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or `LANTERN_INVALID_OVERFLOW` when time_ms is before `genesis_time_ms`; then the store is unchanged.

### Function does

- on_tick_per_slot: sets `time_ms`; at a new slot clears `proposer_boost_root`; at a new epoch runs update_checkpoints with the unrealized checkpoints.

## Function `lantern_on_block`

The on_block of the object's fork, with is_data_available and get_pow_block given by the caller.

### Signature

```
lantern_on_block(store, signed_block, state, options, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `signed_block` | input | `SignedBeaconBlock` |
| `state` | state | `BeaconState`: a copy of the post-state of the block's parent, which becomes the block's post-state |
| `options` | input | `BlockOptions` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when the block is in the store, or the first failed check: `LANTERN_INVALID_UNKNOWN_BLOCK` (parent), `LANTERN_INVALID_PARENT_PAYLOAD`, `LANTERN_INVALID_FUTURE_SLOT`, `LANTERN_INVALID_NOT_FINALIZED`, `LANTERN_INVALID_DATA_UNAVAILABLE`, a check of lantern_state_transition, `LANTERN_INVALID_MERGE_BLOCK`, or a spec failure of get_head, get_ancestor or compute_pulled_up_tip.
- `LANTERN_BUFFER_TOO_SMALL`: the store has no room for a node, scratch is short, or lantern_state_transition needs room in `state`. Nothing is changed.
- `LANTERN_NEED_JUSTIFIED_STATE`: see Common rules. Nothing is changed.

### Caller must

- Deneb and later: pass in `options.data_available` the value of lantern_is_data_available for the block's blobs and proofs (deneb, electra: `retrieve_blobs_and_proofs` is the caller's) or column sidecars (fulu: `retrieve_column_sidecars` is the caller's), or 0 when they cannot be retrieved.
- Bellatrix: pass in `options.pow_block` the PowBlock of get_pow_block(body.execution_payload.parent_hash) and in `options.pow_parent` that of its parent_hash, each 0 when the execution layer has none.
- Pass in `options.payload_status` the execution engine's answer for the payload: `VALID`, `NOT_VALIDATED` for an optimistic import, or `INVALIDATED`.
- Keep `state` as `store.block_states[block_root]` when the call adds a node; a known block adds none and leaves `state` unchanged.

### Function does

- A known root returns `LANTERN_VALID` before any other step.
- A parent whose payload is `INVALIDATED` fails with `LANTERN_INVALID_PARENT_PAYLOAD` (optimistic-sync.md: "The parent of the block MUST NOT have an `INVALIDATED` execution payload").
- verify_and_notify_new_payload is true when `options.payload_status` is not `INVALIDATED`.
- lantern_state_transition gets `options.slots_done` as its `slots_done`.
- Runs state_transition with validate_result, then get_head before adding the block, then computes compute_pulled_up_tip's process_justification_and_finalization on `state` and restores the four fields it changes.
- Then writes in spec order: the node, record_block_timeliness, update_proposer_boost_root, update_checkpoints, and compute_pulled_up_tip's updates.
- The node keeps `body.execution_payload.block_hash` (a zero hash before bellatrix) and `options.payload_status`. A `VALID` block makes its `NOT_VALIDATED` ancestors `VALID`, as a transition to `VALID` does.
- Deneb and later: asserts `options.data_available` after the finalized checks.
- Bellatrix: after state_transition, runs lantern_validate_merge_block when lantern_is_merge_transition_block holds for the parent's state and the body; it reads that before the state changes.

### Limits

- Scratch: that of lantern_state_transition, and S(2) with n the node count of the store, for get_head.

## Function `lantern_validate_merge_block`

The asserts of validate_merge_block: with a TERMINAL_BLOCK_HASH override, the activation epoch and the payload's parent_hash; else a PoW block and its parent that lantern_is_valid_terminal_pow_block accepts.

### Signature

```
lantern_validate_merge_block(block, pow_block, pow_parent, config) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `block` | input | `BeaconBlock` |
| `pow_block` | input | `PowBlock` of get_pow_block(block.body.execution_payload.parent_hash), or 0 for None |
| `pow_parent` | input | `PowBlock` of get_pow_block(pow_block.parent_hash), or 0 for None |
| `config` | input | `Config`: TERMINAL_TOTAL_DIFFICULTY, TERMINAL_BLOCK_HASH and TERMINAL_BLOCK_HASH_ACTIVATION_EPOCH |

### Returns

- `LANTERN_OK`: every check holds.
- `LANTERN_INVALID_MERGE_BLOCK`: a check fails, a PoW block is None, or a PoW block's hash is not the one asked for.

### ABI

- Forks: bellatrix.

## Function `lantern_is_valid_terminal_pow_block`

block.total_difficulty >= TERMINAL_TOTAL_DIFFICULTY and parent.total_difficulty < TERMINAL_TOTAL_DIFFICULTY, as Uint256.

### Signature

```
lantern_is_valid_terminal_pow_block(block, parent, config, out) -> status
```

### Returns

- `LANTERN_OK`, always: `out` is 1 or 0.

### ABI

- Forks: bellatrix.

## Function `lantern_validate_on_attestation`

The asserts of validate_on_attestation.

### Signature

```
lantern_validate_on_attestation(store, attestation, is_from_block) -> status
```

### Returns

- `LANTERN_OK`: every check holds.
- `LANTERN_INVALID_ATTESTATION_TARGET`: the target epoch is not the current or previous epoch (when `is_from_block` is 0), not the epoch of the slot, or the target root is not the checkpoint block of the head vote.
- `LANTERN_INVALID_UNKNOWN_BLOCK`: the target root or the head vote is not in the store.
- `LANTERN_INVALID_ATTESTATION_SLOT`: the head vote's block is after the attestation's slot.
- `LANTERN_INVALID_FUTURE_SLOT`: the current slot is not after the attestation's slot.
- `LANTERN_INVALID_OVERFLOW`: a slot sum does not fit.

## Function `lantern_store_target_checkpoint_state`

The base state advanced to the start slot of the target epoch, when it is before it.

### Signature

```
lantern_store_target_checkpoint_state(state, target, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState`: a copy of `store.block_states[target.root]` |
| `target` | input | `Checkpoint` |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- As lantern_process_slots; `LANTERN_INVALID_OVERFLOW` when the start slot does not fit.

### Caller must

- Keep `state` as `store.checkpoint_states[target]`. The spec skips the call when the target is already there.

## Function `lantern_on_attestation`

validate_on_attestation, then the attesting indices of the target state, is_valid_indexed_attestation, and update_latest_messages.

### Signature

```
lantern_on_attestation(store, attestation, is_from_block, target_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `attestation` | input | `Attestation` |
| `is_from_block` | input | u64: 1 or 0 |
| `target_state` | input | `BeaconState`: `store.checkpoint_states[attestation.data.target]` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, a code of lantern_validate_on_attestation, `LANTERN_INVALID_ATTESTATION` when the indexed attestation is not valid, or a failure of get_attesting_indices.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or an attesting index has no `StoreValidator` entry. The store is unchanged.

### Caller must

- Call lantern_validate_on_attestation first and make the target state only when it returns `LANTERN_OK`.

### Function does

- update_latest_messages: for each attesting index without `STORE_EQUIVOCATING`, sets the latest message to (target epoch, head vote node) when there is none or the target epoch is greater.

### Limits

- Scratch: S(8) + `FC_ATTEST_EXTRA`, with n the validators of `target_state`.

## Function `lantern_on_attester_slashing`

Marks the indices common to both attestations of a valid slashing as equivocating.

### Signature

```
lantern_on_attester_slashing(store, attester_slashing, state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `attester_slashing` | input | `AttesterSlashing` |
| `state` | input | `BeaconState`: `store.block_states[store.justified_checkpoint.root]` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or `LANTERN_INVALID_ATTESTER_SLASHING` when the data are not slashable or an indexed attestation is not valid.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a common index has no `StoreValidator` entry. The store is unchanged.

### Limits

- Scratch: S(7).

## Function `lantern_get_proposer_head`

The get_proposer_head of the object's fork: the parent of a late, weak head when a single slot reorg is safe, else the head.

### Signature

```
lantern_get_proposer_head(store, head, slot, head_state, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | `Store` |
| `head` | input | u64: a node |
| `slot` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states` of the head |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64: a node |

### Returns

- `LANTERN_OK`: `out` holds the node.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.
- `LANTERN_NEED_JUSTIFIED_STATE`: see Common rules.
- `LANTERN_INVALID_UNKNOWN_BLOCK`: the head's parent is not in the store, or a walk leaves it.
- `LANTERN_INVALID_PROPOSER_BOOST`: the head holds the proposer boost.
- `LANTERN_INVALID_OVERFLOW`, `LANTERN_INVALID_VALIDATOR_INDEX`: a spec failure of a sum, or an equivocating committee member that the justified state lacks.

### Function does

- Computes every condition, as the spec does, before it decides; is_head_weak reads the committees of `head_state` and the `effective_balance` of the store's entries.
- Before fulu: the reorg also needs shuffling_stable: slot % SLOTS_PER_EPOCH != 0.

### Limits

- Scratch: S(3), with n the validators of `head_state`.

## Function `lantern_store_payload_status`

A later answer of the execution engine for the payload of a node: `NOT_VALIDATED` to `VALID`, or `NOT_VALIDATED` to `INVALIDATED` (optimistic-sync.md, Transitioning between `VALID`, `INVALIDATED` and `NOT_VALIDATED`).

### Signature

```
lantern_store_payload_status(store, node, payload_status, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `node` | input | u64 |
| `payload_status` | input | u64: `PAYLOAD_STATUS_VALID` or `PAYLOAD_STATUS_INVALIDATED` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, or `LANTERN_INVALID_UNKNOWN_BLOCK` when node is not below the node count; then the store is unchanged.

### Function does

- A node that is not `NOT_VALIDATED`, or another payload_status, changes nothing: the spec leaves `VALID` to `INVALIDATED` and back to the user.
- `VALID`: the node and each `NOT_VALIDATED` ancestor up to the first that is not become `VALID`.
- `INVALIDATED`: the node and each `NOT_VALIDATED` descendant become `INVALIDATED`.
- Finding the node from a `latestValidHash` is the caller's: `BlockNode.block_hash` holds each payload's hash.

## Function `lantern_store_prune`

Drops each node that is neither the node of the store's finalized checkpoint nor a descendant of it. The spec keeps every block; a node of a long run cannot.

### Signature

```
lantern_store_prune(store, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `scratch` | scratch | bytes |

### Returns

- `LANTERN_OK`: the store holds the finalized node and its descendants.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short; the store is unchanged.
- `LANTERN_INVALID_UNKNOWN_BLOCK`: no node has the root of the finalized checkpoint; the store is unchanged.

### Function does

- Keeps the nodes in their order: the finalized node first, with `parent` `NODE_NONE`; each kept node's `parent` is its parent's new index.
- A `latest_node` of a dropped node becomes `NODE_NONE`; `latest_epoch` stays, so later messages compare with it as before.
- The dropped nodes are no descendants of the justified node, so get_head and get_weight give the same results.

### Limits

- Scratch: S(1), with n the node count of the store.

## Function `lantern_is_data_available`

Deneb and electra: whether verify_blob_kzg_proof_batch holds for the blobs and proofs against the commitments. Fulu: whether every column sidecar passes verify_data_column_sidecar and verify_data_column_sidecar_kzg_proofs.

### Signature

```
lantern_is_data_available(blob_kzg_commitments, blobs, proofs, settings, scratch, out) -> status      (deneb, electra)
lantern_is_data_available(sidecars, settings, config, scratch, out) -> status                        (fulu)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `blob_kzg_commitments` | input | a standalone `BlobKZGCommitments` value of the block's body: an asm-crypto `KzgCommitmentList` |
| `blobs` | input | asm-crypto `BlobList`: the blobs of retrieve_blobs_and_proofs |
| `proofs` | input | asm-crypto `KzgProofList`: the proofs of retrieve_blobs_and_proofs |
| `sidecars` | input | `ColumnSidecars`: the value of retrieve_column_sidecars |
| `settings` | input | asm-crypto `KzgSettings` of the trusted setup |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`: `out` holds 1 or 0. A KZG input that does not decode gives 0, as the spec's exception makes on_block fail.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.

### Limits

- Scratch: deneb and electra, `CRYPTO_KZG_SCRATCH` + n * `CRYPTO_KZG_SCRATCH_PER_ENTRY` of asm-crypto, with n the blobs; fulu, `DA_SCRATCH_FIXED` + n * `DA_SCRATCH_PER_BLOB`, with n the most commitments of one sidecar.

### ABI

- Forks: deneb and later.

## Function `lantern_verify_data_column_sidecar`

The index, the commitment count against the blob limit of the epoch, and the column and proof counts.

### Signature

```
lantern_verify_data_column_sidecar(sidecar, config, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds 1 or 0.

### ABI

- Forks: fulu.

## Function `lantern_verify_data_column_sidecar_kzg_proofs`

verify_cell_kzg_proof_batch of the commitments, the column index for each cell, the cells and the proofs.

### Signature

```
lantern_verify_data_column_sidecar_kzg_proofs(sidecar, settings, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds 1 or 0; 0 when a commitment, cell or proof does not decode.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.

### Caller must

- Pass a sidecar that verify_data_column_sidecar accepts.

### Function does

- Copies the four inputs into asm-crypto lists at the end of scratch and calls `crypto_kzg_verify_cell_kzg_proof_batch` with the front.

### Limits

- Scratch: `DA_SCRATCH_FIXED` + n * `DA_SCRATCH_PER_BLOB`, with n the commitments of the sidecar.

### ABI

- Forks: fulu.

## Type `Store`

The fork choice store: a value with two parts.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer |
| 8 | `time_ms` | u64 | |
| 16 | `genesis_time_ms` | u64 | |
| 24 | `justified_checkpoint` | Checkpoint | |
| 64 | `finalized_checkpoint` | Checkpoint | |
| 104 | `unrealized_justified_checkpoint` | Checkpoint | |
| 144 | `unrealized_finalized_checkpoint` | Checkpoint | |
| 184 | `proposer_boost_root` | Root | |
| 216 | `balances_checkpoint` | Checkpoint | The checkpoint whose state gave the balances |
| 256 | `balances_total` | u64 | get_total_balance of the active unslashed validators of that state |
| 264 | `blocks` | PartRef | `BlockNode` entries, in the order they were added |
| 280 | `validators` | PartRef | `StoreValidator` entries, entry i for validator i |
| 296 | `config` | `Config` | |

### Rules

- `STORE_FIXED` (296 + `CONFIG_SIZE`) bytes of fixed fields; the `blocks` part starts there, the `validators` part after it.
- A parent node has a lower index than its children.
- The capacity of `blocks` is its part's bytes over `BlockNode__mem`; the `count` of `validators` is its capacity.
- `equivocating_indices`, `latest_messages`, `block_timeliness` and `unrealized_justifications` are fields of the entries.

## Type `BlockNode`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | hash_tree_root of the block |
| 32 | `parent_root` | Root | |
| 64 | `slot` | u64 | |
| 72 | `proposer_index` | u64 | |
| 80 | `parent` | u64 | Index of the parent node, or `NODE_NONE` |
| 88 | `justified_checkpoint` | Checkpoint | `current_justified_checkpoint` of the block's post-state |
| 128 | `unrealized_justified_checkpoint` | Checkpoint | `unrealized_justifications[root]` |
| 168 | `timely` | u64 | `block_timeliness[root]`: 1 or 0; 0 for the anchor |
| 176 | `block_hash` | Hash32 | `body.execution_payload.block_hash` of the block |
| 208 | `payload_status` | u64 | `PAYLOAD_STATUS_*`: the execution engine's answer for the payload; `VALID` for the anchor |
| 216 | `finalized_epoch` | u64 | `finalized_checkpoint.epoch` of the block's post-state |

### Rules

- `BlockNode__mem` (224) bytes.

## Type `StoreValidator`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `latest_epoch` | u64 | The epoch of the latest message |
| 8 | `latest_node` | u64 | The node of the latest message, or `NODE_NONE` when there is none |
| 16 | `effective_balance` | u64 | In the justified checkpoint state |
| 24 | `flags` | u64 | `STORE_ACTIVE_UNSLASHED`, `STORE_EQUIVOCATING`, `STORE_IN_REGISTRY` |

### Rules

- `StoreValidator__mem` (32) bytes.

## Type `StoreRoom`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `nodes` | u64 | Capacity of `blocks` |
| 8 | `validators` | u64 | Capacity of `validators` |

## Type `BlockOptions`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `payload_status` | u64 | `PAYLOAD_STATUS_*`: the execution engine's answer for the payload |
| 8 | `data_available` | u64 | 1: is_data_available holds for the block; read from deneb on |
| 16 | `pow_block` | pointer | Bellatrix: the `PowBlock` of get_pow_block(body.execution_payload.parent_hash), or 0 for None |
| 24 | `pow_parent` | pointer | Bellatrix: the `PowBlock` of get_pow_block(pow_block.parent_hash), or 0 for None |
| 32 | `slots_done` | u64 | 1: `state` may be at the block's slot already, as an upgrade at the fork's first slot leaves it; lantern_state_transition gets it |

## Type `ColumnSidecars`

A standalone asm-ssz Value of List[DataColumnSidecar, NUMBER_OF_COLUMNS]: size, then a `PartRef` at 8 to the nested sidecar values.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_get_forkchoice_store`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_store_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_store_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_store_justified_checkpoint_state`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_current_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_current_store_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_ancestor`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_checkpoint_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_get_weight`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_filtered_node_tree`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_head`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_on_tick`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_on_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_merge_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_valid_terminal_pow_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_validate_on_attestation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_store_target_checkpoint_state`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_on_attestation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_on_attester_slashing`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_get_proposer_head`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_store_payload_status`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_store_prune`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_data_available`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_verify_data_column_sidecar`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_verify_data_column_sidecar_kzg_proofs`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
