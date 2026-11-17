# Networking rules

## Contents

### Functions

- [`lantern_get_custody_groups`](#function-lantern_get_custody_groups): the custody groups of a node.
- [`lantern_compute_columns_for_custody_group`](#function-lantern_compute_columns_for_custody_group): the columns of a custody group.
- [`lantern_compute_subnet_for_data_column_sidecar`](#function-lantern_compute_subnet_for_data_column_sidecar): the subnet of a column.
- [`lantern_verify_data_column_sidecar_inclusion_proof`](#function-lantern_verify_data_column_sidecar_inclusion_proof): checks that a sidecar's commitments are in its block.
- [`lantern_verify_partial_data_column_header_inclusion_proof`](#function-lantern_verify_partial_data_column_header_inclusion_proof): the same check for a partial column header.
- [`lantern_verify_partial_data_column_sidecar_kzg_proofs`](#function-lantern_verify_partial_data_column_sidecar_kzg_proofs): checks the cells of a partial column.
- [`lantern_seen_size`](#function-lantern_seen_size): the buffer size of a `Seen` with given capacities.
- [`lantern_seen_init`](#function-lantern_seen_init): an empty `Seen`.
- [`lantern_seen_copy`](#function-lantern_seen_copy): copies a `Seen` into a buffer with more capacity.
- [`lantern_seen_add_block`](#function-lantern_seen_add_block): records a block that is known but has no post-state.
- [`lantern_validate_beacon_block_gossip`](#gossip-validation-functions): topic `beacon_block`.
- [`lantern_validate_beacon_aggregate_and_proof_gossip`](#gossip-validation-functions): topic `beacon_aggregate_and_proof`.
- [`lantern_validate_beacon_attestation_gossip`](#gossip-validation-functions): topic `beacon_attestation_{subnet_id}`.
- [`lantern_validate_voluntary_exit_gossip`](#gossip-validation-functions): topic `voluntary_exit`.
- [`lantern_validate_proposer_slashing_gossip`](#gossip-validation-functions): topic `proposer_slashing`.
- [`lantern_validate_attester_slashing_gossip`](#gossip-validation-functions): topic `attester_slashing`.
- [`lantern_validate_sync_committee_contribution_and_proof_gossip`](#gossip-validation-functions): topic `sync_committee_contribution_and_proof`.
- [`lantern_validate_sync_committee_message_gossip`](#gossip-validation-functions): topic `sync_committee_{subnet_id}`.
- [`lantern_validate_bls_to_execution_change_gossip`](#gossip-validation-functions): topic `bls_to_execution_change`.
- [`lantern_validate_data_column_sidecar_gossip`](#gossip-validation-functions): topic `data_column_sidecar_{subnet_id}`.
- [`lantern_validate_partial_data_column_sidecar_gossip`](#gossip-validation-functions): partial messages of `data_column_sidecar_{subnet_id}`.

### Types

- [`NodeID`](#type-nodeid): the discv5 node ID as a number.
- [`Seen`](#type-seen): the spec's `Seen`, and the blocks known without a post-state.
- [`SeenRoom`](#type-seenroom): the capacities of a `Seen`.
- [`SeenKey`](#type-seenkey), [`SeenBits`](#type-seenbits), [`SeenBlock`](#type-seenblock), [`SeenHeader`](#type-seenheader): its entries.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), each function at its latest definition from phase0 to fulu.
- Section: `fulu/das-core.md`, Custody; `p2p-interface.md` of phase0, altair, bellatrix, capella, deneb, electra and fulu, and `fulu/partial-columns/p2p-interface.md`, The gossip domain; the helpers they call from `phase0/validator.md` and `altair/validator.md`.

## Common rules

- As in [helpers.md](helpers.md#common-rules).
- The config values are those of the `config` argument ([Type Config](helpers.md#type-config)), or of the store's copy for a function that takes a `store`; `NUMBER_OF_COLUMNS` is a preset value.
- `store` is a [`Store`](fork-choice.md#type-store). As in [fork-choice.md](fork-choice.md#common-rules), the caller keeps `store.block_states`.
- `store.blocks` of the spec is the store's nodes and the `blocks` of `seen`: a root in `seen` names a block that is known, but failed its state transition or waits to be imported, so it has no post-state. A root in `store.block_states` is a node of the store.
- `block_payload_statuses` of the spec is `BlockNode.payload_status` for a node and `SeenBlock.payload_status` for a block of `seen`.
- Signatures are verified with `crypto_bls_verify` and `crypto_bls_eth_fast_aggregate_verify` of asm-crypto, KZG proofs with `crypto_kzg_verify_cell_kzg_proof_batch`.
- lantern_seen_size, lantern_seen_init, lantern_seen_copy and lantern_seen_add_block read no fork's layouts. Each is in the common object of the core (asm/core/<ISA>/common.s), and its symbol is its name.

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/fulu/networking/<handler>/`, for mainnet and minimal.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.
  - Handlers `get_custody_groups` and `compute_columns_for_custody_group`: the runner compares `result` with the output list.
  - Handlers `gossip_<topic>`: the runner follows `tests/formats/networking/gossip_validation.md` of the spec. It builds the store with lantern_get_forkchoice_store and lantern_on_block, records a `failed` or `pending` block with lantern_seen_add_block, sets a block's `payload_status` with lantern_store_payload_status, writes `finalized_checkpoint` into the store and `seen_partial_data_column_headers` into `seen`, then validates each message in order and compares `valid`, `ignore` or `reject`.
  - Each gossip case holds a `config` part, which sets every fork epoch up to fulu to 0; the runner applies it over the preset's config.
- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/fulu/merkle_proof/single_merkle_proof/BeaconBlockBody/`: the runner builds a `PartialDataColumnHeader` of the body's `blob_kzg_commitments`, the case's `branch` and a block header with the body's root, and checks that lantern_verify_partial_data_column_header_inclusion_proof accepts it, and rejects it with one branch byte changed.

## Function `lantern_get_custody_groups`

The custody_group_count custody groups of node_id, in ascending order.

### Signature

```
lantern_get_custody_groups(node_id, custody_group_count, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node_id` | input | `NodeID` |
| `custody_group_count` | input | u64 |
| `config` | input | `Config` |
| `out` | output | `IndexList` |

### Returns

- `LANTERN_OK`: `out` holds the groups.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than custody_group_count entries.
- `LANTERN_INVALID_CUSTODY_GROUP`: custody_group_count is above `NUMBER_OF_CUSTODY_GROUPS`.

### Function does

- With custody_group_count equal to `NUMBER_OF_CUSTODY_GROUPS`, writes 0 to `NUMBER_OF_CUSTODY_GROUPS` - 1.
- Otherwise hashes current_id from node_id up: the group is bytes_to_uint64(sha256(uint_to_bytes(current_id))[0:8]) % `NUMBER_OF_CUSTODY_GROUPS`, where uint_to_bytes gives the 32 bytes of the Uint256, little endian.
- Keeps the groups sorted as it adds them, so a group already in the list is found where it would go; the spec appends, then sorts.
- current_id wraps from UINT256_MAX to 0, as a 256-bit add does.

### ABI

- Argument order: `node_id`, `custody_group_count`, `config`, `out`.
- Forks: fulu.

## Function `lantern_compute_columns_for_custody_group`

The columns `NUMBER_OF_CUSTODY_GROUPS` * i + custody_group, for i from 0 below `NUMBER_OF_COLUMNS` // `NUMBER_OF_CUSTODY_GROUPS`.

### Signature

```
lantern_compute_columns_for_custody_group(custody_group, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `custody_group` | input | u64 |
| `config` | input | `Config` |
| `out` | output | `IndexList` |

### Returns

- `LANTERN_OK`: `out` holds the columns, in ascending order.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than `NUMBER_OF_COLUMNS` // `NUMBER_OF_CUSTODY_GROUPS` entries.
- `LANTERN_INVALID_CUSTODY_GROUP`: custody_group is not below `NUMBER_OF_CUSTODY_GROUPS`.

### ABI

- Argument order: `custody_group`, `config`, `out`.
- Forks: fulu.

## Function `lantern_compute_subnet_for_data_column_sidecar`

column_index % `DATA_COLUMN_SIDECAR_SUBNET_COUNT`.

### Signature

```
lantern_compute_subnet_for_data_column_sidecar(column_index, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `column_index` | input | u64 |
| `config` | input | `Config` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the subnet.
- `LANTERN_INVALID_OVERFLOW`: `DATA_COLUMN_SIDECAR_SUBNET_COUNT` is 0, so the spec's modulo raises.

### ABI

- Argument order: `column_index`, `config`, `out`.
- Forks: fulu.

## Function `lantern_verify_data_column_sidecar_inclusion_proof`

is_valid_merkle_branch of hash_tree_root(sidecar.kzg_commitments) with `kzg_commitments_inclusion_proof`, depth `KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH`, the subtree index of `blob_kzg_commitments` in `BeaconBlockBody`, and the header's `body_root`.

### Signature

```
lantern_verify_data_column_sidecar_inclusion_proof(sidecar, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `sidecar` | input | `DataColumnSidecar` |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`: `out` holds the result.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` + 24 + 48 * the commitment count bytes, rounded up to 8.

### Function does

- The subtree index is get_subtree_index(get_generalized_index(BeaconBlockBody, "blob_kzg_commitments")): 11, from the body's 13 fields.
- Hashes the list from a standalone copy in scratch, with the descriptor `lantern_type_BlobKZGCommitments`.

### ABI

- Argument order: `sidecar`, `scratch`, `out`.
- Forks: fulu.

## Function `lantern_verify_partial_data_column_header_inclusion_proof`

The check of lantern_verify_data_column_sidecar_inclusion_proof on the fields of a `PartialDataColumnHeader`.

### Signature

```
lantern_verify_partial_data_column_header_inclusion_proof(header, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | input | `PartialDataColumnHeader` |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64: 1 or 0 |

### Returns

- As lantern_verify_data_column_sidecar_inclusion_proof.

### ABI

- Argument order: `header`, `scratch`, `out`.
- Forks: fulu.

## Function `lantern_verify_partial_data_column_sidecar_kzg_proofs`

verify_cell_kzg_proof_batch of the commitments of the cells present in the bitmap, the column index as each cell index, the partial column and its proofs.

### Signature

```
lantern_verify_partial_data_column_sidecar_kzg_proofs(sidecar, header, column_index, settings, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `sidecar` | input | `PartialDataColumnSidecar` |
| `header` | input | `PartialDataColumnHeader`: its `kzg_commitments` are the spec's `all_commitments` |
| `column_index` | input | u64 |
| `settings` | input | asm-crypto `KzgSettings` |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`: `out` holds the result; 0 also when a set bit of the bitmap is not below the number of commitments, where the spec's indexing raises, or when the cells and proofs are not one per set bit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `DA_SCRATCH_FIXED` + n * `DA_SCRATCH_PER_BLOB` bytes, n the number of cells.

### ABI

- Argument order: `sidecar`, `header`, `column_index`, `settings`, `scratch`, `out`.
- Forks: fulu.

## Function `lantern_seen_size`

The bytes of a `Seen` with the capacities of room.

### Signature

```
lantern_seen_size(room, size) -> status
```

### Returns

- `LANTERN_OK`: `size` holds `SEEN_FIXED` + `room.keys` * `SeenKey__mem` + `room.bits` * `SeenBits__mem` + `room.blocks` * `SeenBlock__mem` + `room.header_bytes`.
- `LANTERN_INVALID_OVERFLOW`: the size does not fit in a u64.

## Function `lantern_seen_init`

An empty `Seen`: the spec's `Seen` with every set and dict empty, as the test helper `get_seen` makes it.

### Signature

```
lantern_seen_init(room, seen) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `room` | input | `SeenRoom` |
| `seen` | output | `Seen`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `seen` is empty, with the capacities of room.
- `LANTERN_BUFFER_TOO_SMALL`: `seen` is below lantern_seen_size of room.

## Function `lantern_seen_copy`

Copies seen into out with the capacities of room: the resize function of `Seen` (ARCHITECTURE.md section 6).

### Signature

```
lantern_seen_copy(seen, room, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the entries of seen.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is below lantern_seen_size of room, or a capacity is below what seen holds.

## Function `lantern_seen_add_block`

Records root as a block of `store.blocks` with no post-state, and its payload status: a block that failed its state transition, or waits to be imported.

### Signature

```
lantern_seen_add_block(seen, root, payload_status) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | `Seen` |
| `root` | input | Root |
| `payload_status` | input | u64: `PAYLOAD_STATUS_*`; `NOT_VALIDATED` when the execution engine has given no answer |

### Returns

- `LANTERN_OK`: root is in `seen.blocks` with payload_status; a root already there takes the new status.
- `LANTERN_BUFFER_TOO_SMALL`: `blocks` is full. Nothing is changed.

## Gossip validation functions

Each function is the spec function of its name, for one message of its topic.

### Signatures

```
lantern_validate_beacon_block_gossip(seen, store, signed_beacon_block, current_time_ms, head_state, proposer_state, scratch, result) -> status
lantern_validate_beacon_aggregate_and_proof_gossip(seen, store, signed_aggregate_and_proof, current_time_ms, head_state, scratch, result) -> status
lantern_validate_beacon_attestation_gossip(seen, store, attestation, current_time_ms, subnet_id, head_state, scratch, result) -> status
lantern_validate_voluntary_exit_gossip(seen, store, signed_voluntary_exit, current_time_ms, head_state, scratch, result) -> status
lantern_validate_proposer_slashing_gossip(seen, store, proposer_slashing, head_state, scratch, result) -> status
lantern_validate_attester_slashing_gossip(seen, store, attester_slashing, head_state, scratch, result) -> status
lantern_validate_sync_committee_contribution_and_proof_gossip(seen, store, signed_contribution_and_proof, current_time_ms, head_state, scratch, result) -> status
lantern_validate_sync_committee_message_gossip(seen, store, sync_committee_message, current_time_ms, subnet_id, head_state, scratch, result) -> status
lantern_validate_bls_to_execution_change_gossip(seen, store, signed_bls_to_execution_change, current_time_ms, head_state, scratch, result) -> status
lantern_validate_data_column_sidecar_gossip(seen, store, sidecar, current_time_ms, subnet_id, head_state, proposer_state, settings, scratch, result) -> status
lantern_validate_partial_data_column_sidecar_gossip(seen, store, sidecar, current_time_ms, group_id, column_index, head_state, proposer_state, settings, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | `Seen` |
| `store` | input | `Store` |
| the message | input | the topic's type: `SignedBeaconBlock`, `SignedAggregateAndProof`, `SingleAttestation`, `SignedVoluntaryExit`, `ProposerSlashing`, `AttesterSlashing`, `SignedContributionAndProof`, `SyncCommitteeMessage`, `SignedBLSToExecutionChange`, `DataColumnSidecar` or `PartialDataColumnSidecar` |
| `current_time_ms` | input | u64 |
| `subnet_id` | input | u64 |
| `group_id` | input | `PartialDataColumnGroupID` |
| `column_index` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `proposer_state` | input | `BeaconState`: a copy of `store.block_states` of the message's parent block after process_slots to the message's slot; read only when the parent is a node of the store and the message's slot is after the parent's |
| `settings` | input | asm-crypto `KzgSettings` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen, except that lantern_validate_partial_data_column_sidecar_gossip keeps a header it recorded before a failed cell check, as the spec does.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state and the proposer state of the spec's steps. The spec copies `store.block_states[block.parent_root]` and runs process_slots on it; the caller does that once for each parent and slot.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- is_non_strict_superset skips a seen bitfield of another length, where the spec's `zip(strict=True)` raises.
- `prior_header != header` compares the hash_tree_root of the two headers.
- The attester slashing intersection works on sorted copies of the two index lists in scratch.

### Limits

- Scratch, with n the validator count of head_state:

| Topic | Scratch |
|---|---|
| `beacon_block`, `voluntary_exit`, `proposer_slashing`, `bls_to_execution_change`, `sync_committee_{subnet_id}` | S(0) |
| `beacon_attestation_{subnet_id}` | S(3) |
| `beacon_aggregate_and_proof` | S(10) + `IndexedAttestation__fixed` + 8 |
| `sync_committee_contribution_and_proof` | S(1) + 24 + 48 * `SYNC_COMMITTEE_SIZE` / `SYNC_COMMITTEE_SUBNET_COUNT` |
| `attester_slashing` | S(7) + 72 + 8 * (a + b + min(a, b)), a and b the index counts of its two attestations |
| `data_column_sidecar_{subnet_id}`, partial columns | S(0), and what the inclusion proof and the KZG check of the sidecar need |

### ABI

- Argument order: as in the signatures. An argument after the eighth (the sixth on x86-64) is on the stack, as the core ABI says.

## Type `NodeID`

A Uint256: 32 bytes, little endian.

### Rules

- Starts at a multiple of 8.

## Type `Seen`

The spec's `Seen` of fulu, and the blocks of `store.blocks` that have no post-state: a value with four parts.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer |
| 8 | `keys` | PartRef | `SeenKey` entries: every set of the spec whose entries are numbers |
| 24 | `bits` | PartRef | `SeenBits` entries: `aggregate_data_roots` and `sync_contribution_data` |
| 40 | `blocks` | PartRef | `SeenBlock` entries |
| 56 | `headers` | PartRef | `SeenHeader` entries, back to back: `partial_data_column_headers` |
| 72 | `header_bytes` | u64 | Bytes of the `headers` part in use |

### Rules

- `SEEN_FIXED` (80) bytes of fixed fields; the parts follow in that order, and `headers` runs to the end of the buffer.
- The capacity of a part is the bytes up to the next part's offset over its entry size.

## Type `SeenRoom`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `keys` | u64 | Capacity of `keys` |
| 8 | `bits` | u64 | Capacity of `bits` |
| 16 | `blocks` | u64 | Capacity of `blocks` |
| 24 | `header_bytes` | u64 | Bytes of `headers` |

## Type `SeenKey`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `SEEN_*` of include/lantern.inc: the spec's set |
| 8 | `a` | u64 | First number of the entry |
| 16 | `b` | u64 | Second, or 0 |
| 24 | `c` | u64 | Third, or 0 |

| Kind | Set | (a, b, c) |
|---|---|---|
| `SEEN_PROPOSER_SLOT` (1) | `proposer_slots` | (slot, proposer index) |
| `SEEN_AGGREGATOR_EPOCH` (2) | `aggregator_epochs` | (epoch, aggregator index) |
| `SEEN_VOLUNTARY_EXIT` (3) | `voluntary_exit_indices` | (validator index) |
| `SEEN_PROPOSER_SLASHING` (4) | `proposer_slashing_indices` | (validator index) |
| `SEEN_ATTESTER_SLASHING` (5) | `attester_slashing_indices` | (validator index) |
| `SEEN_ATTESTATION` (6) | `attestation_validator_epochs` | (epoch, validator index) |
| `SEEN_SYNC_CONTRIBUTION` (7) | `sync_contribution_aggregator_slots` | (slot, aggregator index, subcommittee index) |
| `SEEN_SYNC_MESSAGE` (8) | `sync_message_validator_slots` | (slot, validator index, subnet ID) |
| `SEEN_BLS_CHANGE` (9) | `bls_to_execution_change_indices` | (validator index) |
| `SEEN_DATA_COLUMN` (10) | `data_column_sidecar_tuples` | (slot, proposer index, column index) |

- `SeenKey__mem` (32) bytes.

## Type `SeenBits`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `SEEN_AGGREGATE` (1) or `SEEN_CONTRIBUTION` (2) |
| 8 | `root` | Root | The aggregate's data root, or the contribution's beacon_block_root |
| 40 | `a` | u64 | The committee index, or the contribution's slot |
| 48 | `b` | u64 | 0, or the subcommittee index |
| 56 | `length` | u64 | Number of bits |
| 64 | `bits` | 256 bytes | The bits, in SSZ bit order |

- `SeenBits__mem` (320) bytes: room for `MAX_VALIDATORS_PER_COMMITTEE` bits, the most a valid aggregate holds.

## Type `SeenBlock`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | |
| 32 | `payload_status` | u64 | `PAYLOAD_STATUS_*` |

- `SeenBlock__mem` (40) bytes.

## Type `SeenHeader`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `block_root` | Root | The key of `partial_data_column_headers` |
| 32 | `header_root` | Root | hash_tree_root of the header |
| 64 | `header` | `PartialDataColumnHeader` | The header's value; its size is the entry's size minus 64 |

## Results

<!-- CI generates the tick table for each function here. -->
