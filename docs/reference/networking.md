# Networking rules

Gossip rules, subnets, custody, topics.

## Contents

### Functions

- [`lantern_get_custody_groups`](#function-lantern_get_custody_groups): the custody groups of a node.
- [`lantern_compute_columns_for_custody_group`](#function-lantern_compute_columns_for_custody_group): the columns of a custody group.
- [`lantern_compute_subnet_for_data_column_sidecar`](#function-lantern_compute_subnet_for_data_column_sidecar): the subnet of a column.
- [`lantern_verify_data_column_sidecar_inclusion_proof`](#function-lantern_verify_data_column_sidecar_inclusion_proof): checks that a sidecar's commitments are in its block.
- [`lantern_verify_partial_data_column_header_inclusion_proof`](#function-lantern_verify_partial_data_column_header_inclusion_proof): the same check for a partial column header.
- [`lantern_verify_partial_data_column_sidecar_kzg_proofs`](#function-lantern_verify_partial_data_column_sidecar_kzg_proofs): checks the cells of a partial column.
- [`lantern_compute_subnet_for_blob_sidecar`](#function-lantern_compute_subnet_for_blob_sidecar): the subnet of a blob sidecar.
- [`lantern_verify_blob_sidecar_inclusion_proof`](#function-lantern_verify_blob_sidecar_inclusion_proof): checks that a blob sidecar's commitment is in its block.
- [`lantern_compute_fork_version`](#function-lantern_compute_fork_version): the fork version at an epoch.
- [`lantern_compute_fork_digest`](#function-lantern_compute_fork_digest): the fork digest at an epoch.
- [`lantern_compute_attestation_subnet_prefix_bits`](#function-lantern_compute_attestation_subnet_prefix_bits): the node ID bits that pick a subnet.
- [`lantern_compute_min_epochs_for_block_requests`](#function-lantern_compute_min_epochs_for_block_requests): the epochs of blocks a node serves.
- [`lantern_max_compressed_len`](#function-lantern_max_compressed_len): the longest Snappy output of n bytes.
- [`lantern_max_message_size`](#function-lantern_max_message_size): the largest gossip RPC message.
- [`lantern_compute_subscribed_subnet`](#function-lantern_compute_subscribed_subnet): one attestation subnet of a node.
- [`lantern_compute_subscribed_subnets`](#function-lantern_compute_subscribed_subnets): the attestation subnets of a node.
- [`lantern_compute_max_request_blob_sidecars`](#function-lantern_compute_max_request_blob_sidecars): the most blob sidecars of one request.
- [`lantern_compute_max_request_data_column_sidecars`](#function-lantern_compute_max_request_data_column_sidecars): the most column sidecars of one request.
- [`lantern_compute_enr_fork_id`](#function-lantern_compute_enr_fork_id): the value of the ENR `eth2` key.
- [`lantern_compute_next_fork_digest`](#function-lantern_compute_next_fork_digest): the value of the ENR `nfd` key.
- [`lantern_gossip_topic`](#function-lantern_gossip_topic): the topic string of a gossip topic.
- [`lantern_gossip_topic_parse`](#function-lantern_gossip_topic_parse): the gossip topic of a topic string.
- [`lantern_compute_message_id`](#function-lantern_compute_message_id): the message-id of a gossip message.
- [`lantern_seen_size`](#function-lantern_seen_size): the buffer size of a `Seen` with given capacities.
- [`lantern_seen_init`](#function-lantern_seen_init): an empty `Seen`.
- [`lantern_seen_copy`](#function-lantern_seen_copy): copies a `Seen` into a buffer with more capacity.
- [`lantern_seen_add_block`](#function-lantern_seen_add_block): records a block that is known but has no post-state.
- [`lantern_seen_archive`](#function-lantern_seen_archive): moves the entries of past epochs out of a `Seen`, as sorted chunks for its history.
- [`lantern_seen_recall`](#function-lantern_seen_recall): copies a message's past entries from the history back into a `Seen`.
- [`lantern_seen_forget`](#function-lantern_seen_forget): removes what lantern_seen_recall added.
- [`lantern_seen_restore`](#function-lantern_seen_restore): gives the parts of a `Seen` back the counts they had.
- [`lantern_seen_chunk_merge`](#function-lantern_seen_chunk_merge): merges two `SeenChunk` of one kind into one.
- [`lantern_seen_floors`](#function-lantern_seen_floors): the bounds lantern_seen_archive moves entries below.
- [`lantern_seen_sort`](#function-lantern_seen_sort): sorts records of words in place.
- [`lantern_seen_history_find`](#function-lantern_seen_history_find): the first entry of a key in the history's chunk of an epoch.
- [`lantern_validate_beacon_block_gossip`](#function-lantern_validate_beacon_block_gossip): topic `beacon_block`.
- [`lantern_validate_blinded_block_gossip`](#function-lantern_validate_blinded_block_gossip): the checks of topic `beacon_block` on a blinded block (beacon-api.md, publishBlindedBlockV2), from bellatrix.
- [`lantern_validate_beacon_aggregate_and_proof_gossip`](#function-lantern_validate_beacon_aggregate_and_proof_gossip): topic `beacon_aggregate_and_proof`.
- [`lantern_validate_beacon_attestation_gossip`](#function-lantern_validate_beacon_attestation_gossip): topic `beacon_attestation_{subnet_id}`.
- [`lantern_validate_voluntary_exit_gossip`](#function-lantern_validate_voluntary_exit_gossip): topic `voluntary_exit`.
- [`lantern_validate_proposer_slashing_gossip`](#function-lantern_validate_proposer_slashing_gossip): topic `proposer_slashing`.
- [`lantern_validate_attester_slashing_gossip`](#function-lantern_validate_attester_slashing_gossip): topic `attester_slashing`.
- [`lantern_validate_sync_committee_contribution_and_proof_gossip`](#function-lantern_validate_sync_committee_contribution_and_proof_gossip): topic `sync_committee_contribution_and_proof`.
- [`lantern_validate_sync_committee_message_gossip`](#function-lantern_validate_sync_committee_message_gossip): topic `sync_committee_{subnet_id}`.
- [`lantern_validate_bls_to_execution_change_gossip`](#function-lantern_validate_bls_to_execution_change_gossip): topic `bls_to_execution_change`.
- [`lantern_validate_blob_sidecar_gossip`](#function-lantern_validate_blob_sidecar_gossip): topic `blob_sidecar_{subnet_id}`.
- [`lantern_validate_data_column_sidecar_gossip`](#function-lantern_validate_data_column_sidecar_gossip): topic `data_column_sidecar_{subnet_id}`.
- [`lantern_validate_partial_data_column_sidecar_gossip`](#function-lantern_validate_partial_data_column_sidecar_gossip): partial messages of `data_column_sidecar_{subnet_id}`.
- [`lantern_block_lookup`](#function-lantern_block_lookup): where a block root is known: as a node of the store, as a block of seen, or not at all.
- [`lantern_checkpoint_is`](#function-lantern_checkpoint_is): whether get_checkpoint_block of a node is a root.
- [`lantern_commitments_in_body`](#function-lantern_commitments_in_body): is_valid_merkle_branch of a list of KZG commitments against a body root.
- [`lantern_finalized_is_ancestor`](#function-lantern_finalized_is_ancestor): whether the store's finalized checkpoint is the checkpoint block of a node.
- [`lantern_finalized_slot`](#function-lantern_finalized_slot): the first slot of the store's finalized epoch.
- [`lantern_header_checks`](#function-lantern_header_checks): the checks of a block header that the sidecar topics share.
- [`lantern_is_current_or_previous_epoch`](#function-lantern_is_current_or_previous_epoch): is_current_or_previous_epoch of the p2p spec.
- [`lantern_is_future_epoch`](#function-lantern_is_future_epoch): is_future_epoch of the p2p spec.
- [`lantern_is_future_slot`](#function-lantern_is_future_slot): is_future_slot of the p2p spec.
- [`lantern_is_within_slot_range`](#function-lantern_is_within_slot_range): is_within_slot_range of the p2p spec.
- [`lantern_seen_add_bits`](#function-lantern_seen_add_bits): appends a SeenBits entry to seen.
- [`lantern_seen_add_key`](#function-lantern_seen_add_key): appends a SeenKey entry to seen.
- [`lantern_seen_bits_room`](#function-lantern_seen_bits_room): the free SeenBits entries of seen.
- [`lantern_seen_find_block`](#function-lantern_seen_find_block): the SeenBlock of a root in seen.
- [`lantern_seen_find_header`](#function-lantern_seen_find_header): the SeenHeader of a block root in seen.
- [`lantern_seen_find_key`](#function-lantern_seen_find_key): whether seen holds a SeenKey.
- [`lantern_seen_key_room`](#function-lantern_seen_key_room): the free SeenKey entries of seen.
- [`lantern_seen_superset`](#function-lantern_seen_superset): is_non_strict_superset of the SeenBits of a key, for some bits.
- [`lantern_verify_signed`](#function-lantern_verify_signed): lantern_verify_with_domain with get_domain of a state.
- [`lantern_verify_with_domain`](#function-lantern_verify_with_domain): bls.Verify of a public key, the signing root of an object under a domain, and a signature.
- [`lantern_compressed_len`](#function-lantern_compressed_len): the most bytes of the Snappy frames of a payload, by the spec's formula.
- [`lantern_next_fork_epoch`](#function-lantern_next_fork_epoch): next_fork_epoch after an epoch, for the ENR.

### Types

- [`NodeID`](#type-nodeid): the discv5 node ID as a number.
- [`GossipTopic`](#type-gossiptopic): a gossip topic: its fork digest, name and subnet.
- [`Seen`](#type-seen): the spec's `Seen`, and the blocks known without a post-state.
- [`SeenRoom`](#type-seenroom): the capacities of a `Seen`.
- [`SeenKey`](#type-seenkey): | Offset | Field | Type | Meaning |.
- [`SeenBits`](#type-seenbits): | Offset | Field | Type | Meaning |.
- [`SeenBlock`](#type-seenblock): | Offset | Field | Type | Meaning |.
- [`SeenHeader`](#type-seenheader): | Offset | Field | Type | Meaning |.
- [`SeenHistory`](#type-seenhistory): the file of the entries of past epochs.
- [`SeenChunk`](#type-seenchunk): one kind's entries of some epochs, sorted.
- [`HistBits`](#type-histbits): the key of one aggregate bitset in a chunk.
- [`SeenRecall`](#type-seenrecall): the keys of one message.
- [`SeenMark`](#type-seenmark): what lantern_seen_recall added.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), each function at its latest definition from phase0 to fulu.
- Section: `fulu/das-core.md`, Custody; `p2p-interface.md` of phase0, altair, bellatrix, capella, deneb, electra and fulu, and `fulu/partial-columns/p2p-interface.md`: Helpers, Maximum message sizes, The gossip domain, ENR structure, Attestation subnet subscription; `fulu/beacon-chain.md`, compute_fork_digest; the helpers they call from `validator.md` of phase0, altair, deneb and electra.

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

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function does

- With custody_group_count equal to `NUMBER_OF_CUSTODY_GROUPS`, writes 0 to `NUMBER_OF_CUSTODY_GROUPS` - 1.
- Otherwise hashes current_id from node_id up: the group is bytes_to_uint64(sha256(uint_to_bytes(current_id))[0:8]) % `NUMBER_OF_CUSTODY_GROUPS`, where uint_to_bytes gives the 32 bytes of the Uint256, little endian.
- Keeps the groups sorted as it adds them, so a group already in the list is found where it would go; the spec appends, then sorts.
- current_id wraps from UINT256_MAX to 0, as a 256-bit add does.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_get_custody_groups` in the object of fulu, with `_` before it on macOS; `lantern_get_custody_groups` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `node_id`, `custody_group_count`, `config`, `out`.

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

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_columns_for_custody_group` in the object of fulu, with `_` before it on macOS; `lantern_compute_columns_for_custody_group` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `custody_group`, `config`, `out`.

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

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_subnet_for_data_column_sidecar` in the object of fulu, with `_` before it on macOS; `lantern_compute_subnet_for_data_column_sidecar` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `column_index`, `config`, `out`.

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

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_verify_data_column_sidecar_inclusion_proof` in the object of fulu, with `_` before it on macOS; `lantern_verify_data_column_sidecar_inclusion_proof` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `sidecar`, `scratch`, `out`.

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

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_verify_partial_data_column_header_inclusion_proof` in the object of fulu, with `_` before it on macOS; `lantern_verify_partial_data_column_header_inclusion_proof` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `header`, `scratch`, `out`.

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

### Function does

- Verifies the KZG proofs of cells with `crypto_kzg_verify_cell_kzg_proof_batch` of asm-crypto.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_verify_partial_data_column_sidecar_kzg_proofs` in the object of fulu, with `_` before it on macOS; `lantern_verify_partial_data_column_sidecar_kzg_proofs` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `sidecar`, `header`, `column_index`, `settings`, `scratch`, `out`.

## Function `lantern_compute_subnet_for_blob_sidecar`

blob_index % `BLOB_SIDECAR_SUBNET_COUNT` (deneb), or % `BLOB_SIDECAR_SUBNET_COUNT_ELECTRA` (electra).

### Signature

```
lantern_compute_subnet_for_blob_sidecar(blob_index, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `blob_index` | input | u64 |
| `config` | input | `Config` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the subnet.
- `LANTERN_INVALID_OVERFLOW`: the subnet count is 0, so the spec's modulo raises.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_subnet_for_blob_sidecar` in the object of deneb to electra, with `_` before it on macOS; `lantern_compute_subnet_for_blob_sidecar` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `blob_index`, `config`, `out`.

## Function `lantern_verify_blob_sidecar_inclusion_proof`

is_valid_merkle_branch of hash_tree_root(sidecar.kzg_commitment) with `kzg_commitment_inclusion_proof`, depth `KZG_COMMITMENT_INCLUSION_PROOF_DEPTH`, the subtree index of `blob_kzg_commitments[sidecar.index]` in `BeaconBlockBody`, and the header's `body_root`.

### Signature

```
lantern_verify_blob_sidecar_inclusion_proof(sidecar, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `sidecar` | input | `BlobSidecar` |
| `out` | output | u64: 1 or 0 |

### Returns

- `LANTERN_OK`: `out` holds the result.

### Function does

- The subtree index is 11 * 2^(`KZG_COMMITMENT_INCLUSION_PROOF_DEPTH` - 4) + sidecar.index: field 11 of the body's 16 leaves, the list's data root, then the element. The low `KZG_COMMITMENT_INCLUSION_PROOF_DEPTH` bits are those of the spec's index for any sidecar.index.
- hash_tree_root of the commitment is the SHA-256 of its 48 bytes and 16 zero bytes.
- The core does not assemble when 2^(`KZG_COMMITMENT_INCLUSION_PROOF_DEPTH` - 5) is not `MAX_BLOB_COMMITMENTS_PER_BLOCK`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 208 bytes on x86-64 (return address included), 208 bytes on ARM64, 208 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_verify_blob_sidecar_inclusion_proof` in the object of deneb to electra, with `_` before it on macOS; `lantern_verify_blob_sidecar_inclusion_proof` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `sidecar`, `out`.

## Function `lantern_compute_fork_version`

The version of the last fork, up to the object's fork, whose epoch is at most epoch.

### Signature

```
lantern_compute_fork_version(epoch, config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `epoch` | input | u64 |
| `config` | input | `Config` |
| `out` | output | Version, 4 bytes |

### Returns

- `LANTERN_OK`, always.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function does

- Phase0 gives `GENESIS_FORK_VERSION` for every epoch. Each later fork adds its own fork's epoch and version, as its p2p-interface.md does.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_fork_version` in the object of every fork, with `_` before it on macOS; `lantern_compute_fork_version` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `epoch`, `config`, `out`.

## Function `lantern_compute_fork_digest`

The first 4 bytes of compute_fork_data_root(compute_fork_version(epoch), genesis_validators_root).

### Signature

```
lantern_compute_fork_digest(genesis_validators_root, epoch, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `genesis_validators_root` | input | Root |
| `epoch` | input | u64 |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | ForkDigest, 4 bytes |

### Returns

- `LANTERN_OK`: `out` holds the digest.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function does

- Fulu: at an epoch from `FULU_FORK_EPOCH` on, xors the 4 bytes with the first 4 bytes of sha256(uint_to_bytes(epoch) + uint_to_bytes(max_blobs_per_block)) of get_blob_parameters(epoch).

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_fork_digest` in the object of every fork, with `_` before it on macOS; `lantern_compute_fork_digest` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `genesis_validators_root`, `epoch`, `config`, `scratch`, `out`.

## Function `lantern_compute_attestation_subnet_prefix_bits`

ceillog2(`ATTESTATION_SUBNET_COUNT`) + `ATTESTATION_SUBNET_EXTRA_BITS`.

### Signature

```
lantern_compute_attestation_subnet_prefix_bits(config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the number of bits.
- `LANTERN_INVALID_OVERFLOW`: the sum does not fit in a u64.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_attestation_subnet_prefix_bits` in the object of every fork, with `_` before it on macOS; `lantern_compute_attestation_subnet_prefix_bits` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `config`, `out`.

## Function `lantern_compute_min_epochs_for_block_requests`

`MIN_VALIDATOR_WITHDRAWABILITY_DELAY` + `CHURN_LIMIT_QUOTIENT` // 2.

### Signature

```
lantern_compute_min_epochs_for_block_requests(config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the epochs.
- `LANTERN_INVALID_OVERFLOW`: the sum does not fit in a u64.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_min_epochs_for_block_requests` in the object of every fork, with `_` before it on macOS; `lantern_compute_min_epochs_for_block_requests` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `config`, `out`.

## Function `lantern_max_compressed_len`

32 + n + n // 6: the longest Snappy output for n bytes of input.

### Signature

```
lantern_max_compressed_len(n, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `n` | input | u64 |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the length.
- `LANTERN_INVALID_OVERFLOW`: the length does not fit in a u64.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_max_compressed_len` in the object of every fork, with `_` before it on macOS; `lantern_max_compressed_len` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `n`, `out`.

## Function `lantern_max_message_size`

max(max_compressed_len(`MAX_PAYLOAD_SIZE`) + 1024, 1048576).

### Signature

```
lantern_max_message_size(config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the size.
- `LANTERN_INVALID_OVERFLOW`: a sum does not fit in a u64.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_max_message_size` in the object of every fork, with `_` before it on macOS; `lantern_max_message_size` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `config`, `out`.

## Function `lantern_compute_subscribed_subnet`

The attestation subnet index of node_id at epoch: its prefix, shuffled by the subscription period of epoch, plus index, modulo `ATTESTATION_SUBNET_COUNT`.

### Signature

```
lantern_compute_subscribed_subnet(node_id, epoch, index, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node_id` | input | `NodeID` |
| `epoch` | input | u64 |
| `index` | input | u64 |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the subnet.
- `LANTERN_INVALID_OVERFLOW`: where the spec raises: `EPOCHS_PER_SUBNET_SUBSCRIPTION` is 0, epoch + the node offset or the shuffled prefix + index does not fit in a u64, or prefix_bits is 64 or more, so 1 << prefix_bits is not a Uint64.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function does

- prefix_bits is lantern_compute_attestation_subnet_prefix_bits; the node offset is node_id % `EPOCHS_PER_SUBNET_SUBSCRIPTION`, over all 256 bits.
- The permutation seed is sha256(uint_to_bytes((epoch + node offset) // `EPOCHS_PER_SUBNET_SUBSCRIPTION`)).

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_subscribed_subnet` in the object of every fork, with `_` before it on macOS; `lantern_compute_subscribed_subnet` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `node_id`, `epoch`, `index`, `config`, `scratch`, `out`.

## Function `lantern_compute_subscribed_subnets`

lantern_compute_subscribed_subnet(node_id, epoch, index) for index from 0 below `SUBNETS_PER_NODE`.

### Signature

```
lantern_compute_subscribed_subnets(node_id, epoch, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node_id` | input | `NodeID` |
| `epoch` | input | u64 |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `IndexList` |

### Returns

- `LANTERN_OK`: `out` holds the subnets, in index order.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than `SUBNETS_PER_NODE` entries, or `scratch` is short.
- `LANTERN_INVALID_OVERFLOW`: as lantern_compute_subscribed_subnet.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_subscribed_subnets` in the object of every fork, with `_` before it on macOS; `lantern_compute_subscribed_subnets` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `node_id`, `epoch`, `config`, `scratch`, `out`.

## Function `lantern_compute_max_request_blob_sidecars`

`MAX_REQUEST_BLOCKS_DENEB` * `MAX_BLOBS_PER_BLOCK` (deneb), or * `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra).

### Signature

```
lantern_compute_max_request_blob_sidecars(config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the number.
- `LANTERN_INVALID_OVERFLOW`: the product does not fit in a u64.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_max_request_blob_sidecars` in the object of deneb to electra, with `_` before it on macOS; `lantern_compute_max_request_blob_sidecars` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `config`, `out`.

## Function `lantern_compute_max_request_data_column_sidecars`

`MAX_REQUEST_BLOCKS_DENEB` * `NUMBER_OF_COLUMNS`.

### Signature

```
lantern_compute_max_request_data_column_sidecars(config, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `config` | input | [`Config`](helpers.md#type-config) |
| `out` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the number.
- `LANTERN_INVALID_OVERFLOW`: the product does not fit in a u64.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_compute_max_request_data_column_sidecars` in the object of fulu, with `_` before it on macOS; `lantern_compute_max_request_data_column_sidecars` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `config`, `out`.

## Function `lantern_compute_enr_fork_id`

The SSZ bytes of the `ENRForkID` of the ENR `eth2` key: fork_digest, next_fork_version and next_fork_epoch at current_epoch.

### Signature

```
lantern_compute_enr_fork_id(genesis_validators_root, current_epoch, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `genesis_validators_root` | input | Root |
| `current_epoch` | input | u64: the epoch of the wall clock |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | 16 bytes: the SSZ of `ENRForkID` |

### Returns

- `LANTERN_OK`: `out` holds the value.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function does

- fork_digest is lantern_compute_fork_digest(genesis_validators_root, current_epoch).
- next_fork_epoch is the least epoch after current_epoch of the forks from altair up to the object's fork, a fork epoch of `FAR_FUTURE_EPOCH` left out; fulu adds each `BLOB_SCHEDULE` epoch from `FULU_FORK_EPOCH` on, the BPO forks. With none, it is `FAR_FUTURE_EPOCH`.
- next_fork_version is lantern_compute_fork_version(next_fork_epoch), or lantern_compute_fork_version(current_epoch) when next_fork_epoch is `FAR_FUTURE_EPOCH`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_compute_enr_fork_id` in the object of every fork, with `_` before it on macOS; `lantern_compute_enr_fork_id` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `genesis_validators_root`, `current_epoch`, `config`, `scratch`, `out`.

## Function `lantern_compute_next_fork_digest`

The value of the ENR `nfd` key: lantern_compute_fork_digest at the next_fork_epoch of lantern_compute_enr_fork_id, or 4 zero bytes when that is `FAR_FUTURE_EPOCH`.

### Signature

```
lantern_compute_next_fork_digest(genesis_validators_root, current_epoch, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `genesis_validators_root` | input | Bytes32 |
| `current_epoch` | input | u64 |
| `config` | input | [`Config`](helpers.md#type-config) |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `out` | output | `ForkDigest`: 4 bytes |

### Returns

- `LANTERN_OK`: `out` holds the 4 bytes.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_compute_next_fork_digest` in the object of fulu, with `_` before it on macOS; `lantern_compute_next_fork_digest` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `genesis_validators_root`, `current_epoch`, `config`, `scratch`, `out`.

## Function `lantern_gossip_topic`

The topic string `/eth2/` + the lowercase hex of fork_digest + `/` + the name + `/ssz_snappy`, the name with `_` and subnet_id in decimal for a subnet topic.

### Signature

```
lantern_gossip_topic(topic, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | `GossipTopic` |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the string.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer bytes than the string.
- `LANTERN_INVALID_TOPIC`: `topic.name` is not a `GOSSIP_*` name.

### Function does

- Ignores `subnet_id` for a topic with no subnet.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_gossip_topic`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `topic`, `out`.

## Function `lantern_gossip_topic_parse`

The `GossipTopic` of a topic string that lantern_gossip_topic gives.

### Signature

```
lantern_gossip_topic_parse(string, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `string` | input | `ByteList` |
| `out` | output | `GossipTopic` |

### Returns

- `LANTERN_OK`: `out` holds the topic.
- `LANTERN_INVALID_TOPIC`: the string is not `/eth2/`, 8 lowercase hex digits, `/`, a name of a `GOSSIP_*` topic, `/ssz_snappy`; or a subnet number has a leading zero, is empty or does not fit in a u64. Nothing is written.

### Function does

- Gives exactly the strings lantern_gossip_topic writes, so that topic and string map one to one.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 40 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_gossip_topic_parse`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `string`, `out`.

## Function `lantern_compute_message_id`

The 20 byte message-id of a gossip message.

### Signature

```
lantern_compute_message_id(topic, data, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | `ByteList`: the message's topic string |
| `data` | input | `ByteList`: the message's data |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | 20 bytes |

### Returns

- `LANTERN_OK`: `out` holds the message-id.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than 64 + the topic's bytes + n bytes, n the larger of the data's bytes and the length in its Snappy header when that length is at most `MAX_PAYLOAD_SIZE`.

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function does

- When data has a valid Snappy block decompression: the first 20 bytes of sha256(`MESSAGE_DOMAIN_VALID_SNAPPY` + the decompressed bytes). Otherwise: of sha256(`MESSAGE_DOMAIN_INVALID_SNAPPY` + data).
- Altair and later put uint_to_bytes(len(topic)) + topic after the domain, as altair p2p-interface.md says.
- A valid decompression is one that `snappy_uncompress` of asm-snappy accepts with a length of at most `MAX_PAYLOAD_SIZE`. The spec states no bound; a message above it fails the gossip size limits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_compute_message_id` in the object of every fork, with `_` before it on macOS; `lantern_compute_message_id` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `topic`, `data`, `config`, `scratch`, `out`.

## Function `lantern_seen_size`

The bytes of a `Seen` with the capacities of room.

### Signature

```
lantern_seen_size(room, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `room` | input | [`SeenRoom`](#type-seenroom) |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`: `size` holds `SEEN_FIXED` + `room.keys` * `SeenKey__mem` + `room.bits` * `SeenBits__mem` + `room.blocks` * `SeenBlock__mem` + `room.header_bytes`.
- `LANTERN_INVALID_OVERFLOW`: the size does not fit in a u64.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_size`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `room`, `size`.

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

### Function does

- Zeroes the bytes of every part, so that the bytes after each part's entries are zero (Rules of `Seen`).

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_init`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `room`, `seen`.

## Function `lantern_seen_copy`

Copies seen into out with the capacities of room: the resize function of `Seen` (ARCHITECTURE.md section 6).

### Signature

```
lantern_seen_copy(seen, room, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | input | [`Seen`](#type-seen) |
| `room` | input | [`SeenRoom`](#type-seenroom) |
| `out` | output | [`Seen`](#type-seen), its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the entries of seen.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is below lantern_seen_size of room, or a capacity is below what seen holds.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_copy`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `seen`, `room`, `out`.

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

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_add_block`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `seen`, `root`, `payload_status`.

## Function `lantern_seen_archive`

Moves the entries of past epochs and slots out of seen: those of the kinds the history keeps go to `out` as sorted chunks, the proven ones go; `Seen` and its history together hold the spec's sets.

### Signature

```
lantern_seen_archive(seen, store, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `out` | state | ByteList: the chunks follow its bytes |

### Returns

- `LANTERN_OK`: `out` holds after its bytes one [`SeenChunk`](#type-seenchunk) of each kind with entries that moved; seen holds the entries that stay, in their order, with zero bytes after them.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has too little room for the chunks. Nothing is changed.

### Caller must

- Validate no later message at a `current_time_ms` before `store.time_ms`.
- Pass a store whose `time_ms` and finalized epoch never go back between calls.
- Add each chunk to the history before the next validation that reads it.

### Function does

- With s the current slot of `store.time_ms` (0 before genesis), e the epoch of s - `ATTESTATION_PROPAGATION_SLOT_RANGE` - 1 (0 below 0), the first epoch kept e - 1 (0 below 0), and f the first slot of the store's finalized epoch:
  - moves a `SEEN_ATTESTATION` or `SEEN_AGGREGATOR_EPOCH` key whose epoch is below the first epoch kept, to a `HIST_ATTESTATION` or `HIST_AGGREGATOR` chunk of (epoch, index) entries;
  - moves a `SEEN_DATA_COLUMN` or `SEEN_BLOB_SIDECAR` key whose slot is below f, to a `HIST_COLUMN` or `HIST_BLOB` chunk of (slot, proposer index, index) entries;
  - moves a `SEEN_AGGREGATE` entry of `bits` whose target epoch `b` is below the first epoch kept, to a `HIST_AGGREGATE` chunk of [`HistBits`](#type-histbits) entries and their bits;
  - drops a `SEEN_PROPOSER_SLOT` key whose slot is f or below, and a `SEEN_SYNC_CONTRIBUTION` or `SEEN_SYNC_MESSAGE` key, or a `SEEN_CONTRIBUTION` entry of `bits`, whose slot is below s - 1;
  - keeps the keys by validator index (`SEEN_VOLUNTARY_EXIT`, `SEEN_PROPOSER_SLASHING`, `SEEN_ATTESTER_SLASHING`, `SEEN_BLS_CHANGE`), `blocks` and `headers`.
- A dropped key changes no result: no [REJECT] check of its message comes between its seen check and the time check that then gives [IGNORE] (the finalized slot, or is_current_slot with `MAXIMUM_GOSSIP_CLOCK_DISPARITY`).
- No valid message can add a moved key again: its epoch or slot fails the message's time check.
- Sorts each chunk's entries by their words, unsigned, in word order: (epoch, index), (slot, proposer index, index), or (data root, committee index, target epoch).
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 168 bytes on x86-64 (return address included), 144 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_archive`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `seen`, `store`, `out`.

## Function `lantern_seen_recall`

Copies into seen the entries of a message's keys that the history holds and seen does not, so that a validation sees the spec's sets.

### Signature

```
lantern_seen_recall(seen, history, recall, mark) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `history` | input | [`SeenHistory`](#type-seenhistory), or 0 |
| `recall` | input | [`SeenRecall`](#type-seenrecall) |
| `mark` | output | [`SeenMark`](#type-seenmark) |

### Returns

- `LANTERN_OK`: seen holds after its keys and bits the entries it added; `mark` says how many.
- `LANTERN_BUFFER_TOO_SMALL`: `keys` or `bits` of seen has too little room for them. Nothing is changed.
- `LANTERN_INVALID_EVENT`: `recall` has more than `SEEN_RECALL_MAX` items. Nothing is changed.

### Caller must

- Call lantern_seen_forget with `mark` after the validation that reads them, before seen is archived or copied.

### Function does

- A key item of `SEEN_ATTESTATION`, `SEEN_AGGREGATOR_EPOCH`, `SEEN_DATA_COLUMN` or `SEEN_BLOB_SIDECAR` that seen does not hold, and the chunk of its kind and epoch holds: one key.
- A `SEEN_RECALL_BITS` item (root, a, b) with no `SEEN_AGGREGATE` entry of seen of that root, a and b: one `SEEN_AGGREGATE` entry of each `HistBits` of the chunk of that key, with its bits.
- Another item kind, or a key the history lacks: nothing.
- Reads a chunk only inside the history's `size`, its entries only inside the chunk's `bytes`, and bits of at most `SEEN_BITS_BYTES`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 152 bytes on x86-64 (return address included), 160 bytes on ARM64, 176 bytes on RISC-V.
- Time: a lookup in the history is a binary search of one chunk.

### ABI

- Role: L0.
- Symbol: `lantern_seen_recall`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `seen`, `history`, `recall`, `mark`.

## Function `lantern_seen_forget`

Removes from seen the entries lantern_seen_recall added, and moves the entries added after them down.

### Signature

```
lantern_seen_forget(seen, mark) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `mark` | input | [`SeenMark`](#type-seenmark) |

### Returns

- `LANTERN_OK`, always.

### Caller must

- Pass the `mark` of the last lantern_seen_recall, with seen changed since only by entries added after its keys and bits.

### Function does

- Zeroes the bytes the removed entries leave after the others, so seen's bytes are those before lantern_seen_recall when the validation added nothing.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_forget`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `seen`, `mark`.

## Function `lantern_seen_restore`

Gives the parts of a `Seen` back the counts they had.

### Signature

```
lantern_seen_restore(seen, counts) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `counts` | input | 5 u64: the counts of `keys`, `bits` and `blocks`, the count of `headers` and `header_bytes` |

### Returns

- `LANTERN_OK`, always.

### Caller must

- Pass counts read from seen before entries were added, with seen changed since only by entries added at the end of its parts.

### Function does

- Sets each part's count, and `header_bytes`, to the one in counts.
- Zeroes the bytes of each part after its entries, so seen's bytes are those it had when the counts were read.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_restore`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `seen`, `counts`.

## Function `lantern_seen_chunk_merge`

Merges two `SeenChunk` of one kind into one.

### Signature

```
lantern_seen_chunk_merge(a, b, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | [`SeenChunk`](#type-seenchunk) |
| `b` | input | [`SeenChunk`](#type-seenchunk) of the kind of `a` |
| `out` | state | ByteList: the merged chunk follows its bytes |

### Returns

- `LANTERN_OK`: `out` holds after its bytes one `SeenChunk` of the entries of a and b.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has fewer than the bytes of a and b less `SEEN_CHUNK_FIXED` of room. Nothing is changed.

### Caller must

- Pass chunks as lantern_seen_archive writes them: entries sorted, `bytes` the end of their entries and bits, the bits of each `HistBits` inside its chunk.

### Function does

- The merged chunk: the kind of a, `epoch_lo` the lower of the two, `epoch_hi` the higher, `count` the sum, `bytes` the sum less `SEEN_CHUNK_FIXED`.
- Its entries: those of a and b in the order of lantern_seen_archive (their words, or for `HIST_AGGREGATE` the root, the committee index and the target epoch), a's first of two equal ones.
- `HIST_AGGREGATE`: the bits of each entry follow all the entries, in the entries' order, and its `bits` holds their new offset from the merged chunk's start.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_chunk_merge`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `a`, `b`, `out`.

## Function `lantern_seen_floors`

The bounds lantern_seen_archive moves entries below.

### Signature

```
lantern_seen_floors(store) -> (first epoch, first sync slot, finalized slot)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) in x1, rsi, a1 |

### Returns

- The first epoch kept, the first sync slot kept and the first slot of the finalized epoch, in x8, x9, x10 on ARM64, r8, r9, r11 on x86-64, a5, a6, a7 on RISC-V (lantern_seen_archive, Function does).

### Function does

- Reads the store's `time_ms`, its genesis time, its finalized epoch and the config values of its copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_floors`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- A leaf.

## Function `lantern_seen_sort`

Sorts records of words in place.

### Signature

```
lantern_seen_sort(records, count, words, key)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `records` | state | `count` records of `words` u64 |
| `count` | input | u64 in a register |
| `words` | input | u64 in a register: the words of a record |
| `key` | input | u64 in a register: the words compared, from the first |

### Function does

- Sorts the records by their first `key` words, unsigned and in word order: a heapsort, with no memory but the records'.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 0 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_sort`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `records`, `count`, `words`, `key`.

## Function `lantern_seen_history_find`

The first entry of a key in the history's chunk of an epoch.

### Signature

```
lantern_seen_history_find(history, kind, key, words, epoch) -> (entry, chunk)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `history` | input | [`SeenHistory`](#type-seenhistory), or 0 |
| `kind` | input | u64 in a register: a `HIST_*` kind |
| `key` | input | `words` u64 |
| `words` | input | u64 in a register: the words compared |
| `epoch` | input | u64 in a register |

### Returns

- The first entry of the chunk whose first `words` words are those of key, and the chunk; or 0.

### Function does

- Takes the index entry of the epoch for the kind, and its chunk, only when both lie inside the history's `size`, the chunk is of that kind and its entries fit in its bytes.
- Finds the entry by a binary search of the sorted entries.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_history_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `history`, `kind`, `key`, `words`, `epoch`.

## Function `lantern_validate_beacon_block_gossip`

The spec's validate_beacon_block_gossip for one message of `beacon_block`.

### Signature

```
lantern_validate_beacon_block_gossip(seen, store, signed_beacon_block, current_time_ms, head_state, proposer_state, scratch, result) -> status                (phase0, altair, capella and later)
lantern_validate_beacon_block_gossip(seen, store, signed_beacon_block, current_time_ms, head_state, proposer_state, justified_state, scratch, result) -> status   (bellatrix)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `signed_beacon_block` | input | `SignedBeaconBlock` of the fork |
| `current_time_ms` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `proposer_state` | input | `BeaconState`: a copy of `store.block_states` of the message's parent block after process_slots to the message's slot; read only when the parent is a node of the store and the message's slot is after the parent's |
| `justified_state` | input | `BeaconState`: `store.block_states[store.justified_checkpoint.root]`; bellatrix only |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state and the proposer state of the spec's steps. The spec copies `store.block_states[block.parent_root]` and runs process_slots on it; the caller does that once for each parent and slot.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- `beacon_block`, a parent with no post-state: phase0 and altair give `LANTERN_GOSSIP_REJECT`. Bellatrix decides by is_execution_enabled(justified_state, block.body), then the parent's payload status. Capella and later decide by the parent's payload status.
- `beacon_block`, bellatrix: the payload timestamp check and the `INVALIDATED` parent check run only when is_execution_enabled(head_state, block.body) holds. Capella and later run them always.
- `beacon_block`, the commitment limit: `MAX_BLOBS_PER_BLOCK` (deneb), `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra), the `max_blobs_per_block` of get_blob_parameters at the block's epoch (fulu).
- Reads the config values of the store's copy.

### Function never

- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch, fulu: S(0), with n the validator count of head_state.
- Scratch, phase0 to electra: S(2), with n the validator count of proposer_state: get_beacon_proposer_index.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_beacon_block_gossip` in the object of every fork, with `_` before it on macOS; `lantern_validate_beacon_block_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the sixth is on the stack on x86-64, as the core ABI says.
- Argument order: `seen`, `store`, `signed_beacon_block`, `current_time_ms`, `head_state`, `proposer_state`, `scratch`, `result` in phase0, altair, capella and later; bellatrix adds `justified_state` after `proposer_state`.

## Function `lantern_validate_blinded_block_gossip`

The spec's validate_blinded_block_gossip for one message of `beacon_block`.

### Signature

```
lantern_validate_blinded_block_gossip(seen, store, signed_blinded_beacon_block, current_time_ms, head_state, proposer_state, scratch, result) -> status                (phase0, altair, capella and later)
lantern_validate_blinded_block_gossip(seen, store, signed_blinded_beacon_block, current_time_ms, head_state, proposer_state, justified_state, scratch, result) -> status   (bellatrix)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `signed_blinded_beacon_block` | input | `SignedBlindedBeaconBlock` of the fork |
| `current_time_ms` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `proposer_state` | input | `BeaconState`: a copy of `store.block_states` of the message's parent block after process_slots to the message's slot; read only when the parent is a node of the store and the message's slot is after the parent's |
| `justified_state` | input | `BeaconState`: `store.block_states[store.justified_checkpoint.root]`; bellatrix only |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state and the proposer state of the spec's steps. The spec copies `store.block_states[block.parent_root]` and runs process_slots on it; the caller does that once for each parent and slot.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- `beacon_block`, a parent with no post-state: phase0 and altair give `LANTERN_GOSSIP_REJECT`. Bellatrix decides by is_execution_enabled(justified_state, block.body), then the parent's payload status. Capella and later decide by the parent's payload status.
- `beacon_block`, bellatrix: the payload timestamp check and the `INVALIDATED` parent check run only when is_execution_enabled(head_state, block.body) holds. Capella and later run them always.
- The checks of `beacon_block` in the same order on a `SignedBlindedBeaconBlock`: the signature of the hash_tree_root of its `BlindedBeaconBlock` (that of the full block), the timestamp of its `execution_payload_header`, the count of its `blob_kzg_commitments`. Its execution is enabled: a blinded block has a payload. Phase0 and altair have no blinded block: `LANTERN_INVALID_EVENT`.
- `beacon_block`, the commitment limit: `MAX_BLOBS_PER_BLOCK` (deneb), `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra), the `max_blobs_per_block` of get_blob_parameters at the block's epoch (fulu).
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch, fulu: S(0), with n the validator count of head_state.
- Scratch, phase0 to electra: S(2), with n the validator count of proposer_state: get_beacon_proposer_index.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_validate_blinded_block_gossip` in the object of every fork, with `_` before it on macOS; `lantern_validate_blinded_block_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- An argument after the sixth is on the stack on x86-64, as the core ABI says.
- Argument order: `seen`, `store`, `signed_blinded_beacon_block`, `current_time_ms`, `head_state`, `proposer_state`, `scratch`, `result` in phase0, altair, capella and later; bellatrix adds `justified_state` after `proposer_state`.

## Function `lantern_validate_beacon_aggregate_and_proof_gossip`

The spec's validate_beacon_aggregate_and_proof_gossip for one message of `beacon_aggregate_and_proof`.

### Signature

```
lantern_validate_beacon_aggregate_and_proof_gossip(seen, store, signed_aggregate_and_proof, current_time_ms, head_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `signed_aggregate_and_proof` | input | `SignedAggregateAndProof` of the fork |
| `current_time_ms` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state of the spec's steps.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- is_non_strict_superset skips a seen bitfield of another length, where the spec's `zip(strict=True)` raises.
- `beacon_attestation_{subnet_id}` and `beacon_aggregate_and_proof`, phase0 to capella: the slot is within `ATTESTATION_PROPAGATION_SLOT_RANGE` of the current slot (is_within_slot_range). Deneb and later: the slot is not in the future and its epoch is the current or previous epoch.
- `beacon_aggregate_and_proof`, phase0 to deneb: the committee index is `data.index`, and `aggregate_data_roots` is keyed by the data root alone. Electra and later key it by the data root and the committee index.
- `beacon_aggregate_and_proof`: the `SeenBits` entry holds the target epoch in `b`, for lantern_seen_archive; the data root fixes the target epoch, so an entry matches the same messages.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 256 bytes on x86-64 (return address included), 240 bytes on ARM64, 240 bytes on RISC-V.
- Scratch: S(10) + `IndexedAttestation__fixed` + 8, with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_beacon_aggregate_and_proof_gossip` in the object of every fork, with `_` before it on macOS; `lantern_validate_beacon_aggregate_and_proof_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the sixth is on the stack on x86-64, as the core ABI says.
- Argument order: `seen`, `store`, `signed_aggregate_and_proof`, `current_time_ms`, `head_state`, `scratch`, `result`.

## Function `lantern_validate_beacon_attestation_gossip`

The spec's validate_beacon_attestation_gossip for one message of `beacon_attestation_{subnet_id}`.

### Signature

```
lantern_validate_beacon_attestation_gossip(seen, store, attestation, current_time_ms, subnet_id, head_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `attestation` | input | `Attestation` (phase0 to deneb) or `SingleAttestation` (electra and later) |
| `current_time_ms` | input | u64 |
| `subnet_id` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state of the spec's steps.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- `beacon_attestation_{subnet_id}` and `beacon_aggregate_and_proof`, phase0 to capella: the slot is within `ATTESTATION_PROPAGATION_SLOT_RANGE` of the current slot (is_within_slot_range). Deneb and later: the slot is not in the future and its epoch is the current or previous epoch.
- `beacon_attestation_{subnet_id}`, phase0 to deneb: the message is an `Attestation`. It has exactly one aggregation bit set and as many bits as the committee; the participant is the committee member at the set bit, and is_valid_indexed_attestation checks its one signature.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(3), with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_beacon_attestation_gossip` in the object of every fork, with `_` before it on macOS; `lantern_validate_beacon_attestation_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the sixth is on the stack on x86-64, as the core ABI says.
- Argument order: `seen`, `store`, `attestation`, `current_time_ms`, `subnet_id`, `head_state`, `scratch`, `result`.

## Function `lantern_validate_voluntary_exit_gossip`

The spec's validate_voluntary_exit_gossip for one message of `voluntary_exit`.

### Signature

```
lantern_validate_voluntary_exit_gossip(seen, store, signed_voluntary_exit, current_time_ms, head_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `signed_voluntary_exit` | input | `SignedVoluntaryExit` |
| `current_time_ms` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state of the spec's steps.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- `voluntary_exit`, phase0 to capella: the signature domain is get_domain(state, `DOMAIN_VOLUNTARY_EXIT`, voluntary_exit.epoch). Deneb and later use the capella fork version, as process_voluntary_exit does.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.
- Scratch: S(0), with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_voluntary_exit_gossip` in the object of every fork, with `_` before it on macOS; `lantern_validate_voluntary_exit_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the sixth is on the stack on x86-64, as the core ABI says.
- Argument order: `seen`, `store`, `signed_voluntary_exit`, `current_time_ms`, `head_state`, `scratch`, `result`.

## Function `lantern_validate_proposer_slashing_gossip`

The spec's validate_proposer_slashing_gossip for one message of `proposer_slashing`.

### Signature

```
lantern_validate_proposer_slashing_gossip(seen, store, proposer_slashing, head_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `proposer_slashing` | input | `ProposerSlashing` |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state of the spec's steps.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.
- Scratch: S(0), with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_proposer_slashing_gossip` in the object of every fork, with `_` before it on macOS; `lantern_validate_proposer_slashing_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `seen`, `store`, `proposer_slashing`, `head_state`, `scratch`, `result`.

## Function `lantern_validate_attester_slashing_gossip`

The spec's validate_attester_slashing_gossip for one message of `attester_slashing`.

### Signature

```
lantern_validate_attester_slashing_gossip(seen, store, attester_slashing, head_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `attester_slashing` | input | `AttesterSlashing` of the fork |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state of the spec's steps.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- The attester slashing intersection works on sorted copies of the two index lists in scratch.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.
- Scratch: S(7) + 72 + 8 * (a + b + min(a, b)), a and b the index counts of its two attestations, with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_attester_slashing_gossip` in the object of every fork, with `_` before it on macOS; `lantern_validate_attester_slashing_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `seen`, `store`, `attester_slashing`, `head_state`, `scratch`, `result`.

## Function `lantern_validate_sync_committee_contribution_and_proof_gossip`

The spec's validate_sync_committee_contribution_and_proof_gossip for one message of `sync_committee_contribution_and_proof`.

### Signature

```
lantern_validate_sync_committee_contribution_and_proof_gossip(seen, store, signed_contribution_and_proof, current_time_ms, head_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `signed_contribution_and_proof` | input | `SignedContributionAndProof` |
| `current_time_ms` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state of the spec's steps.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- is_non_strict_superset skips a seen bitfield of another length, where the spec's `zip(strict=True)` raises.
- Verifies an aggregate signature with `crypto_bls_eth_fast_aggregate_verify` of asm-crypto.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 304 bytes on x86-64 (return address included), 272 bytes on ARM64, 272 bytes on RISC-V.
- Scratch: S(1) + 24 + 48 * `SYNC_COMMITTEE_SIZE` / `SYNC_COMMITTEE_SUBNET_COUNT`, with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_sync_committee_contribution_and_proof_gossip` in the object of altair to fulu, with `_` before it on macOS; `lantern_validate_sync_committee_contribution_and_proof_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the sixth is on the stack on x86-64, as the core ABI says.
- Argument order: `seen`, `store`, `signed_contribution_and_proof`, `current_time_ms`, `head_state`, `scratch`, `result`.

## Function `lantern_validate_sync_committee_message_gossip`

The spec's validate_sync_committee_message_gossip for one message of `sync_committee_{subnet_id}`.

### Signature

```
lantern_validate_sync_committee_message_gossip(seen, store, sync_committee_message, current_time_ms, subnet_id, head_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `sync_committee_message` | input | `SyncCommitteeMessage` |
| `current_time_ms` | input | u64 |
| `subnet_id` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state of the spec's steps.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.
- Scratch: S(0), with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_sync_committee_message_gossip` in the object of altair to fulu, with `_` before it on macOS; `lantern_validate_sync_committee_message_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the sixth is on the stack on x86-64, as the core ABI says.
- Argument order: `seen`, `store`, `sync_committee_message`, `current_time_ms`, `subnet_id`, `head_state`, `scratch`, `result`.

## Function `lantern_validate_bls_to_execution_change_gossip`

The spec's validate_bls_to_execution_change_gossip for one message of `bls_to_execution_change`.

### Signature

```
lantern_validate_bls_to_execution_change_gossip(seen, store, signed_bls_to_execution_change, current_time_ms, head_state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `signed_bls_to_execution_change` | input | `SignedBLSToExecutionChange` |
| `current_time_ms` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state of the spec's steps.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.
- Scratch: S(0), with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_bls_to_execution_change_gossip` in the object of capella to fulu, with `_` before it on macOS; `lantern_validate_bls_to_execution_change_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the sixth is on the stack on x86-64, as the core ABI says.
- Argument order: `seen`, `store`, `signed_bls_to_execution_change`, `current_time_ms`, `head_state`, `scratch`, `result`.

## Function `lantern_validate_blob_sidecar_gossip`

The spec's validate_blob_sidecar_gossip for one message of `blob_sidecar_{subnet_id}`.

### Signature

```
lantern_validate_blob_sidecar_gossip(seen, store, blob_sidecar, current_time_ms, subnet_id, head_state, proposer_state, settings, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `blob_sidecar` | input | `BlobSidecar` |
| `current_time_ms` | input | u64 |
| `subnet_id` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `proposer_state` | input | `BeaconState`: a copy of `store.block_states` of the message's parent block after process_slots to the message's slot; read only when the parent is a node of the store and the message's slot is after the parent's |
| `settings` | input | asm-crypto `KzgSettings` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state and the proposer state of the spec's steps. The spec copies `store.block_states[block.parent_root]` and runs process_slots on it; the caller does that once for each parent and slot.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- `prior_header != header` compares the two headers: their hash_tree_root, then, when those are equal, their decoded bytes, so that a hash collision cannot pass.
- `blob_sidecar_{subnet_id}`: the index limit is `MAX_BLOBS_PER_BLOCK` (deneb) or `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra). A blob, commitment or proof that `crypto_kzg_verify_blob_kzg_proof` cannot decode gives `LANTERN_GOSSIP_REJECT`, where the spec's verify_blob_kzg_proof raises.
- Verifies a KZG proof with `crypto_kzg_verify_blob_kzg_proof` of asm-crypto.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.
- Scratch: S(2), with n the validator count of proposer_state, and at least `CRYPTO_KZG_SCRATCH` of asm-crypto, with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_blob_sidecar_gossip` in the object of deneb to electra, with `_` before it on macOS; `lantern_validate_blob_sidecar_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the eighth (the sixth on x86-64) is on the stack, as the core ABI says.
- Argument order: `seen`, `store`, `blob_sidecar`, `current_time_ms`, `subnet_id`, `head_state`, `proposer_state`, `settings`, `scratch`, `result`.

## Function `lantern_validate_data_column_sidecar_gossip`

The spec's validate_data_column_sidecar_gossip for one message of `data_column_sidecar_{subnet_id}`.

### Signature

```
lantern_validate_data_column_sidecar_gossip(seen, store, sidecar, current_time_ms, subnet_id, head_state, proposer_state, settings, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `sidecar` | input | `DataColumnSidecar`, or `PartialDataColumnSidecar` for the partial check |
| `current_time_ms` | input | u64 |
| `subnet_id` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `proposer_state` | input | `BeaconState`: a copy of `store.block_states` of the message's parent block after process_slots to the message's slot; read only when the parent is a node of the store and the message's slot is after the parent's |
| `settings` | input | asm-crypto `KzgSettings` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state and the proposer state of the spec's steps. The spec copies `store.block_states[block.parent_root]` and runs process_slots on it; the caller does that once for each parent and slot.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- `prior_header != header` compares the two headers: their hash_tree_root, then, when those are equal, their decoded bytes, so that a hash collision cannot pass.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.
- Scratch: S(0), and what the inclusion proof and the KZG check of the sidecar need, with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_data_column_sidecar_gossip` in the object of fulu, with `_` before it on macOS; `lantern_validate_data_column_sidecar_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the eighth (the sixth on x86-64) is on the stack, as the core ABI says.
- Argument order: `seen`, `store`, `sidecar`, `current_time_ms`, `subnet_id`, `head_state`, `proposer_state`, `settings`, `scratch`, `result`.

## Function `lantern_validate_partial_data_column_sidecar_gossip`

The spec's validate_partial_data_column_sidecar_gossip for one message of partial columns.

### Signature

```
lantern_validate_partial_data_column_sidecar_gossip(seen, store, sidecar, current_time_ms, group_id, column_index, head_state, proposer_state, settings, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `sidecar` | input | `DataColumnSidecar`, or `PartialDataColumnSidecar` for the partial check |
| `current_time_ms` | input | u64 |
| `group_id` | input | `PartialDataColumnGroupID` |
| `column_index` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `proposer_state` | input | `BeaconState`: a copy of `store.block_states` of the message's parent block after process_slots to the message's slot; read only when the parent is a node of the store and the message's slot is after the parent's |
| `settings` | input | asm-crypto `KzgSettings` |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `result` | output | [`Result`](helpers.md#type-result) |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` when every check holds and seen holds the message, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT` for the first failed check of the spec, or the code of a spec failure that raises another exception (then the spec gives no answer for gossip). Only `LANTERN_VALID` changes seen, except that it keeps a header it recorded before a failed cell check, as the spec does.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short, or a part of seen is full when every check held. Nothing is changed: the caller grows seen with lantern_seen_copy and calls again.

### Caller must

- Pass the head state and the proposer state of the spec's steps. The spec copies `store.block_states[block.parent_root]` and runs process_slots on it; the caller does that once for each parent and slot.

### Function does

- Makes the checks in spec order, and writes to seen only after the last one: "If the result is `valid`, update the store as the validation function would".
- compute_time_at_slot_ms gives UINT64_MAX when the time does not fit in a u64, so such a slot is in the future; is_future_epoch is true when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- `prior_header != header` compares the two headers: their hash_tree_root, then, when those are equal, their decoded bytes, so that a hash collision cannot pass.
- With cells, checks that scratch holds what the KZG check needs before it records a new header, so a short scratch changes no byte of seen.
- Reads the config values of the store's copy.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 224 bytes on x86-64 (return address included), 208 bytes on ARM64, 208 bytes on RISC-V.
- Scratch: S(0), and what the inclusion proof and the KZG check of the sidecar need, with n the validator count of head_state.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_validate_partial_data_column_sidecar_gossip` in the object of fulu, with `_` before it on macOS; `lantern_validate_partial_data_column_sidecar_gossip` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- An argument after the eighth (the sixth on x86-64) is on the stack, as the core ABI says.
- Argument order: `seen`, `store`, `sidecar`, `current_time_ms`, `group_id`, `column_index`, `head_state`, `proposer_state`, `settings`, `scratch`, `result`.

## Function `lantern_block_lookup`

Where a block root is known: as a node of the store, as a block of seen, or not at all.

### Signature

```
lantern_block_lookup(store, seen, root) -> (node, where, payload_status)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `seen` | input | [`Seen`](#type-seen) |
| `root` | input | Bytes32 |

### Function does

- Returns the node of the root, or `NODE_NONE`.
- Returns as its second value 2 for a node of the store, 1 for a block of seen, 0 when the root is unknown.
- Returns as its third value the block's payload status.
- Reads the config values of the store's copy.

### Function never

- Writes memory but its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_block_lookup`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns three values: x0, x1, x2 on ARM64; rax, rdx, rcx on x86-64; a0, a1, a2 on RISC-V.
- Argument order: `store`, `seen`, `root`.

## Function `lantern_checkpoint_is`

Whether get_checkpoint_block of a node is a root.

### Signature

```
lantern_checkpoint_is(store, node, epoch, root) -> (status, flag)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `node` | input | u64 in a register: a [`ForkChoiceNode`](fork-choice.md#type-forkchoicenode) |
| `epoch` | input | u64 in a register |
| `root` | input | Bytes32 |

### Returns

- `LANTERN_OK`: the second value is 1 when get_checkpoint_block(store, node, epoch) is `root`, else 0.
- The statuses of lantern_checkpoint_block.

### Function does

- Reads the config values of the store's copy.

### Function never

- Writes memory but its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_checkpoint_is`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `store`, `node`, `epoch`, `root`.

## Function `lantern_commitments_in_body`

is_valid_merkle_branch of a list of KZG commitments against a body root.

### Signature

```
lantern_commitments_in_body(scratch, commitments, count, branch, root) -> (status, valid)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |
| `commitments` | input | `count` KZG commitments of 48 bytes |
| `count` | input | u64 in a register |
| `branch` | input | `KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH` nodes of 32 bytes |
| `root` | input | Bytes32: the body root |

### Returns

- `LANTERN_OK`: the second value is 1 when the branch holds, else 0.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Function does

- Hashes the list from a standalone copy at the end of `scratch`, then checks the branch at depth `KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH` and index `BLOB_KZG_COMMITMENTS_SUBTREE_INDEX`.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_commitments_in_body`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `scratch`, `commitments`, `count`, `branch`, `root`.

## Function `lantern_finalized_is_ancestor`

Whether the store's finalized checkpoint is the checkpoint block of a node.

### Signature

```
lantern_finalized_is_ancestor(store, node) -> (status, flag)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `node` | input | u64 in a register: a [`ForkChoiceNode`](fork-choice.md#type-forkchoicenode) |

### Returns

- As lantern_checkpoint_is, with the store's finalized epoch and root.

### Function does

- Reads the config values of the store's copy.

### Function never

- Writes memory but its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_finalized_is_ancestor`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `store`, `node`.

## Function `lantern_finalized_slot`

The first slot of the store's finalized epoch.

### Signature

```
lantern_finalized_slot(store) -> slot
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |

### Function does

- Returns compute_start_slot_at_epoch of the finalized epoch, or `UINT64_MAX` when it does not fit in a u64.
- Reads the config values of the store's copy.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_finalized_slot`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and x86-64: x0, x1; rax, rcx.
- Argument order: `store`.

## Function `lantern_header_checks`

The checks of a block header that the sidecar topics share.

### Signature

```
lantern_header_checks(header) -> (status, result, parent)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | input | `SignedBeaconBlockHeader` |

### Returns

- `LANTERN_OK`: the second value is `LANTERN_VALID`, `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT`, the third the parent node.
- `LANTERN_BUFFER_TOO_SMALL`: the scratch is short.

### Function does

- Makes the checks of the sidecar topics from lantern_is_future_slot to the finalized ancestor, in spec order.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_header_checks`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: seen in x19, rbx, s1; the store in x20, rbp, s2; current_time_ms in x22, r13, s4; the head state in x23, r14, s5; the scratch in x25, r15, s7. It changes none of them.
- It returns three values: x0, x1, x2 on ARM64; rax, rdx, rcx on x86-64; a0, a1, a2 on RISC-V.
- Argument order: `header`.

## Function `lantern_is_current_or_previous_epoch`

is_current_or_previous_epoch of the p2p spec.

### Signature

```
lantern_is_current_or_previous_epoch(store, epoch, current_time_ms) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `epoch` | input | u64 in a register |
| `current_time_ms` | input | u64 in a register |

### Function does

- Returns 1 when the current time is within epoch `epoch` or epoch `epoch` + 1, with the `MAXIMUM_GOSSIP_CLOCK_DISPARITY` allowance, as the spec's two is_within_epoch calls give, else 0.
- Reads the config values of the store's copy.

### Function never

- Writes memory but its own stack.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_is_current_or_previous_epoch`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Argument order: `store`, `epoch`, `current_time_ms`.

## Function `lantern_is_future_epoch`

is_future_epoch of the p2p spec.

### Signature

```
lantern_is_future_epoch(store, epoch, current_time_ms) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `epoch` | input | u64 in a register |
| `current_time_ms` | input | u64 in a register |

### Function does

- Returns 1 when the epoch of the slot at `current_time_ms` + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is below `epoch`, else 0.
- Returns 1 when current_time_ms + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the genesis time, where the spec's subtraction raises.
- Reads the config values of the store's copy.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_is_future_epoch`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Registers it changes, on ARM64 and x86-64: x0, x3, x4, x16; rax, rcx, rdx.
- Argument order: `store`, `epoch`, `current_time_ms`.

## Function `lantern_is_future_slot`

is_future_slot of the p2p spec.

### Signature

```
lantern_is_future_slot(store, slot, current_time_ms) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `slot` | input | u64 in a register |
| `current_time_ms` | input | u64 in a register |

### Function does

- Returns 1 when `current_time_ms` + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` is before the start of `slot`, else 0.
- A slot whose start time does not fit in a u64 is in the future.
- Reads the config values of the store's copy.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_is_future_slot`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Registers it changes, on ARM64 and x86-64: x0, x3, x4, x16, x17; rax, rcx, r8.
- Argument order: `store`, `slot`, `current_time_ms`.

## Function `lantern_is_within_slot_range`

is_within_slot_range of the p2p spec.

### Signature

```
lantern_is_within_slot_range(store, slot, slot_range, current_time_ms) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |
| `slot` | input | u64 in a register |
| `slot_range` | input | u64 in a register |
| `current_time_ms` | input | u64 in a register |

### Function does

- Returns 1 when the current time is within the inclusive slot range [`slot`, `slot` + `slot_range`], with the `MAXIMUM_GOSSIP_CLOCK_DISPARITY` allowance on both ends, else 0.
- Reads the config values of the store's copy.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L1.
- Symbol: `lantern_is_within_slot_range`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6); each argument is a pointer: a Uint64 argument points at a u64, and a Boolean output is a u64 of 0 or 1.
- Registers it changes, on ARM64 and x86-64: x0, x4 to x6, x16, x17; rax, r8, r9.
- Argument order: `store`, `slot`, `slot_range`, `current_time_ms`.

## Function `lantern_seen_add_bits`

Appends a SeenBits entry to seen.

### Signature

```
lantern_seen_add_bits(seen, kind, root, a, b, bits, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `kind` | input | u64 in a register: the key's kind |
| `root` | input | Bytes32 |
| `a` | input | u64 in a register |
| `b` | input | u64 in a register |
| `bits` | input | `length` bits |
| `length` | input | u64 in a register |

### Caller must

- `seen` has room for one more SeenBits entry.

### Function does

- Appends the SeenBits entry of the key (`kind`, `root`, `a`, `b`) with the bits.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_add_bits`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64, `bits` is in r9 and `length` in rax.
- Argument order: `seen`, `kind`, `root`, `a`, `b`, `bits`, `length`.

## Function `lantern_seen_add_key`

Appends a SeenKey entry to seen.

### Signature

```
lantern_seen_add_key(seen, kind, a, b, c)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | [`Seen`](#type-seen) |
| `kind` | input | u64 in a register |
| `a` | input | u64 in a register |
| `b` | input | u64 in a register |
| `c` | input | u64 in a register |

### Caller must

- `seen` has room for one more SeenKey entry.

### Function does

- Appends the SeenKey (`kind`, `a`, `b`, `c`).

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_add_key`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and x86-64: x5, x6; r9, r10.
- Argument order: `seen`, `kind`, `a`, `b`, `c`.

## Function `lantern_seen_bits_room`

The free SeenBits entries of seen.

### Signature

```
lantern_seen_bits_room(seen) -> entries
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | input | [`Seen`](#type-seen) |

### Function does

- Returns the free SeenBits entries.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_bits_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and x86-64: x0 to x3; rax, rcx, rdx.
- Argument order: `seen`.

## Function `lantern_seen_find_block`

The SeenBlock of a root in seen.

### Signature

```
lantern_seen_find_block(seen, root) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | input | [`Seen`](#type-seen) |
| `root` | input | Bytes32 |

### Function does

- Returns the [`SeenBlock`](#type-seenblock) of `root`, or 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_find_block`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and x86-64: x0, x2 to x9; rax, rcx, rdx, r11, xmm0 to xmm2.
- Argument order: `seen`, `root`.

## Function `lantern_seen_find_header`

The SeenHeader of a block root in seen.

### Signature

```
lantern_seen_find_header(seen, root) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | input | [`Seen`](#type-seen) |
| `root` | input | Bytes32: the block root |

### Function does

- Returns the SeenHeader of `root`, or 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_find_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and x86-64: x0, x2 to x10; rax, rcx, rdx, r11, xmm0 to xmm2.
- Argument order: `seen`, `root`.

## Function `lantern_seen_find_key`

Whether seen holds a SeenKey.

### Signature

```
lantern_seen_find_key(seen, kind, a, b, c) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | input | [`Seen`](#type-seen) |
| `kind` | input | u64 in a register |
| `a` | input | u64 in a register |
| `b` | input | u64 in a register |
| `c` | input | u64 in a register |

### Function does

- Returns 1 when `seen` holds the SeenKey (`kind`, `a`, `b`, `c`), else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_find_key`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and x86-64: x0, x5 to x8; rax, r9 to r11.
- Argument order: `seen`, `kind`, `a`, `b`, `c`.

## Function `lantern_seen_key_room`

The free SeenKey entries of seen.

### Signature

```
lantern_seen_key_room(seen) -> entries
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | input | [`Seen`](#type-seen) |

### Function does

- Returns the free SeenKey entries.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_key_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64: x0 to x2.
- Argument order: `seen`.

## Function `lantern_seen_superset`

is_non_strict_superset of the SeenBits of a key, for some bits.

### Signature

```
lantern_seen_superset(seen, kind, root, a, b, bits, length) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | input | [`Seen`](#type-seen) |
| `kind` | input | u64 in a register |
| `root` | input | Bytes32 |
| `a` | input | u64 in a register |
| `b` | input | u64 in a register |
| `bits` | input | `length` bits |
| `length` | input | u64 in a register |

### Function does

- Returns 1 when one of the key's SeenBits entries has every bit of `bits` set, else 0.
- Skips an entry whose bits have another length, where the spec's `zip(strict=True)` raises.

### Function never

- Calls another function.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_seen_superset`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64, `bits` is in r9 and `length` in rax.
- Registers it changes, on ARM64 and x86-64: x0, x7 to x13; rax, rdi, r10, r11, xmm0 to xmm2.
- Argument order: `seen`, `kind`, `root`, `a`, `b`, `bits`, `length`.

## Function `lantern_verify_signed`

lantern_verify_with_domain with get_domain of a state.

### Signature

```
lantern_verify_signed(state, domain_type, epoch, type, object, pubkey, signature, scratch) -> (status, valid)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `domain_type` | input | u32 in a register |
| `epoch` | input | u64 in a register |
| `type` | input | the asm-ssz descriptor of `object` |
| `object` | input | the signed object |
| `pubkey` | input | 48 bytes |
| `signature` | input | 96 bytes |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- The statuses of lantern_get_domain and lantern_verify_with_domain; the second value is 1 when the signature holds.

### Caller must

- `state` is a valid `BeaconState` value (include/types.inc) with every PartRef in range.

### Function does

- Computes get_domain(state, domain_type, epoch), then calls lantern_verify_with_domain.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_verify_signed`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On x86-64, `signature` and `scratch` are the two stack arguments.
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `state`, `domain_type`, `epoch`, `type`, `object`, `pubkey`, `signature`, `scratch`.

## Function `lantern_verify_with_domain`

bls.Verify of a public key, the signing root of an object under a domain, and a signature.

### Signature

```
lantern_verify_with_domain(domain, type, object, pubkey, signature, scratch) -> (status, valid)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `domain` | input | Bytes32 |
| `type` | input | the asm-ssz descriptor of `object` |
| `object` | input | the signed object |
| `pubkey` | input | 48 bytes |
| `signature` | input | 96 bytes |
| `scratch` | scratch | [`Scratch`](helpers.md#type-scratch) |

### Returns

- The statuses of lantern_compute_signing_root and lantern_verify_root_signature; the second value is 1 when the signature holds.

### Function does

- Computes compute_signing_root(object, domain), then checks the signature with lantern_verify_root_signature.

### Function never

- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_verify_with_domain`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Argument order: `domain`, `type`, `object`, `pubkey`, `signature`, `scratch`.

## Function `lantern_compressed_len`

The most bytes of the Snappy frames of a payload, by the spec's formula.

### Signature

```
lantern_compressed_len(n) -> (bytes, overflow)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `n` | input | u64 in a register |

### Function does

- Returns 32 + n + n // 6.
- Reports an overflow: ARM64 and x86-64 set the carry flag; RISC-V returns 1 in a1, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_compressed_len`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- `n` is in x0 on ARM64, rax on x86-64 and a0 on RISC-V; the result comes back in the same register.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9, x10; rax, rcx, rdx, r8; a0, a1, t0, t1.
- Argument order: `n`.

## Function `lantern_next_fork_epoch`

next_fork_epoch after an epoch, for the ENR.

### Signature

```
lantern_next_fork_epoch(epoch, config) -> epoch
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `epoch` | input | u64 in a register |
| `config` | input | [`Config`](helpers.md#type-config) |

### Caller must

- The values of `config` are those of [Type Config](helpers.md#type-config); `NUMBER_OF_COLUMNS` is a preset value.

### Function does

- Returns the least fork epoch above `epoch` among the forks from altair up to the object's fork, and from fulu on each `BLOB_SCHEDULE` epoch from `FULU_FORK_EPOCH` on; else `FAR_FUTURE_EPOCH`.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.
- Keeps a pointer after it returns.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_next_fork_epoch`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x2 to x7; rax, rcx, rdx, r8, r9; a0, a2 to a5, t0, t1.
- Argument order: `epoch`, `config`.

## Type `NodeID`

A Uint256: 32 bytes, little endian.

### Rules

- Starts at a multiple of 8.

## Type `GossipTopic`

A gossip topic: its fork digest, its name and its subnet.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `fork_digest` | ForkDigest, in a u64 | The 4 bytes, then 4 zero bytes |
| 8 | `name` | u64 | `GOSSIP_*` of include/lantern.inc |
| 16 | `subnet_id` | u64 | The subnet of a subnet topic, else 0 |

### Rules

- `GOSSIP_BEACON_BLOCK` (1): the topic `beacon_block`.
- `GOSSIP_BEACON_AGGREGATE_AND_PROOF` (2): the topic `beacon_aggregate_and_proof`.
- `GOSSIP_BEACON_ATTESTATION` (3): the topic `beacon_attestation_{subnet_id}`, with a subnet.
- `GOSSIP_VOLUNTARY_EXIT` (4): the topic `voluntary_exit`.
- `GOSSIP_PROPOSER_SLASHING` (5): the topic `proposer_slashing`.
- `GOSSIP_ATTESTER_SLASHING` (6): the topic `attester_slashing`.
- `GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF` (7): the topic `sync_committee_contribution_and_proof`.
- `GOSSIP_SYNC_COMMITTEE` (8): the topic `sync_committee_{subnet_id}`, with a subnet.
- `GOSSIP_BLS_TO_EXECUTION_CHANGE` (9): the topic `bls_to_execution_change`.
- `GOSSIP_BLOB_SIDECAR` (10): the topic `blob_sidecar_{subnet_id}`, with a subnet.
- `GOSSIP_DATA_COLUMN_SIDECAR` (11): the topic `data_column_sidecar_{subnet_id}`, with a subnet.
- `GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE` (12): the topic `light_client_finality_update`.
- `GOSSIP_LIGHT_CLIENT_OPTIMISTIC_UPDATE` (13): the topic `light_client_optimistic_update`.
- `GossipTopic__mem` (24) bytes.

## Type `Seen`

The spec's `Seen` of every fork, and the blocks of `store.blocks` that have no post-state: a value with four parts.

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
- `store.blocks` of the spec is the store's nodes and the `blocks` of seen: a root in seen names a block that is known, but failed its state transition or waits to be imported, so it has no post-state. A root in `store.block_states` is a node of the store.
- `block_payload_statuses` of the spec is `BlockNode.payload_status` for a node and `SeenBlock.payload_status` for a block of seen.
- Every byte of a part after its entries is zero: lantern_seen_init zeroes the parts, and the functions that remove entries zero what they leave.
- `Seen` holds the spec's sets for recent epochs; its history, a [`SeenHistory`](#type-seenhistory), holds the moved entries (lantern_seen_archive), and lantern_seen_recall copies a message's entries back for its validation.

## Type `SeenRoom`

The capacities of the parts of a `Seen`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `keys` | u64 | Capacity of `keys` |
| 8 | `bits` | u64 | Capacity of `bits` |
| 16 | `blocks` | u64 | Capacity of `blocks` |
| 24 | `header_bytes` | u64 | Bytes of `headers` |

## Type `SeenKey`

One entry of a set of `Seen` keyed by numbers.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `SEEN_*` of include/lantern.inc: the spec's set |
| 8 | `a` | u64 | First number of the entry |
| 16 | `b` | u64 | Second, or 0 |
| 24 | `c` | u64 | Third, or 0 |

### Rules

- `SEEN_PROPOSER_SLOT` (1): the spec's `proposer_slots`, keyed by (slot, proposer index).
- `SEEN_AGGREGATOR_EPOCH` (2): the spec's `aggregator_epochs`, keyed by (epoch, aggregator index).
- `SEEN_VOLUNTARY_EXIT` (3): the spec's `voluntary_exit_indices`, keyed by (validator index).
- `SEEN_PROPOSER_SLASHING` (4): the spec's `proposer_slashing_indices`, keyed by (validator index).
- `SEEN_ATTESTER_SLASHING` (5): the spec's `attester_slashing_indices`, keyed by (validator index).
- `SEEN_ATTESTATION` (6): the spec's `attestation_validator_epochs`, keyed by (epoch, validator index).
- `SEEN_SYNC_CONTRIBUTION` (7): the spec's `sync_contribution_aggregator_slots`, keyed by (slot, aggregator index, subcommittee index).
- `SEEN_SYNC_MESSAGE` (8): the spec's `sync_message_validator_slots`, keyed by (slot, validator index, subnet ID).
- `SEEN_BLS_CHANGE` (9): the spec's `bls_to_execution_change_indices`, keyed by (validator index).
- `SEEN_DATA_COLUMN` (10): the spec's `data_column_sidecar_tuples`, keyed by (slot, proposer index, column index).
- `SEEN_BLOB_SIDECAR` (11): the spec's `blob_sidecar_tuples`, keyed by (slot, proposer index, blob index).
- `SeenKey__mem` (32) bytes.

## Type `SeenBits`

The bits of an aggregate or a sync contribution that `Seen` keeps.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `SEEN_AGGREGATE` (1) or `SEEN_CONTRIBUTION` (2) |
| 8 | `root` | Root | The aggregate's data root, or the contribution's beacon_block_root |
| 40 | `a` | u64 | The committee index, or the contribution's slot |
| 48 | `b` | u64 | The aggregate's target epoch, or the subcommittee index |
| 56 | `length` | u64 | Number of bits |
| 64 | `bits` | 256 bytes | The bits, in SSZ bit order |

### Rules

- `SeenBits__mem` (320) bytes: room for `MAX_VALIDATORS_PER_COMMITTEE` bits, the most a valid aggregate holds.

## Type `SeenBlock`

A block of `store.blocks` with no post-state.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | hash_tree_root of the block |
| 32 | `payload_status` | u64 | `PAYLOAD_STATUS_*` |

### Rules

- `SeenBlock__mem` (40) bytes.

## Type `SeenHeader`

A partial data column header that `Seen` keeps.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `block_root` | Root | The key of `partial_data_column_headers` |
| 32 | `header_root` | Root | hash_tree_root of the header |
| 64 | `header` | `PartialDataColumnHeader` | The header's value; its size is the entry's size minus 64 |


## Type `SeenHistory`

The file of the entries lantern_seen_archive moved out of `Seen`, mapped to read.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the file in use |
| 8 | `magic` | u64 | `SEEN_HISTORY_MAGIC` |
| 16 | `version` | u64 | `SEEN_HISTORY_VERSION` (1) |
| 24 | `first_epoch` | u64 | The epoch of index entry 0 |
| 32 | `capacity` | u64 | Index entries |
| 40 | `data_start` | u64 | The offset of the first chunk |
| 64 | `index` | `capacity` * `SEEN_HISTORY_ENTRY` bytes | For each epoch, the file offset of the `SeenChunk` of each `HIST_*` kind holding it, or 0 |

### Rules

- `SEEN_HISTORY_FIXED` (64) bytes of fixed fields; `SEEN_HISTORY_ENTRY` (48) bytes an index entry, `HIST_KINDS` (5) offsets of 8 bytes and 8 zero bytes.
- Chunks follow from `data_start`, each at a multiple of 8.
- A reader takes an index entry or a chunk only when it lies inside `size`: a chunk written after the last `size` is not there yet.
- The app writes a chunk, then its epochs' index entries, then `size`, each made durable before the next (app.md).

## Type `SeenChunk`

One `HIST_*` kind's entries of some epochs, sorted.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `HIST_ATTESTATION` (0), `HIST_AGGREGATOR` (1), `HIST_COLUMN` (2), `HIST_BLOB` (3) or `HIST_AGGREGATE` (4) |
| 8 | `epoch_lo` | u64 | The lowest epoch of its entries |
| 16 | `epoch_hi` | u64 | The highest epoch of its entries |
| 24 | `count` | u64 | Entries |
| 32 | `bytes` | u64 | Bytes of the chunk, these fields included; a multiple of 8 |
| 40 | `entries` | `count` entries | Sorted by their words, unsigned, in word order |

### Rules

- `SEEN_CHUNK_FIXED` (40) bytes of fixed fields.
- `HIST_ATTESTATION` and `HIST_AGGREGATOR`: 16 bytes an entry, (epoch, index).
- `HIST_COLUMN` and `HIST_BLOB`: 24 bytes an entry, (slot, proposer index, index); its epoch is the slot's.
- `HIST_AGGREGATE`: a `HistBits` an entry, sorted by (root, committee index, target epoch); then the bits, each in whole 8 byte words.

## Type `HistBits`

The key of one `SEEN_AGGREGATE` bitset in a `HIST_AGGREGATE` chunk.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | The aggregate's data root |
| 32 | `a` | u64 | The committee index |
| 40 | `epoch` | u64 | The target epoch |
| 48 | `length` | u64 | Number of bits |
| 56 | `bits` | u64 | The offset of the bits from the chunk's start |

### Rules

- `HistBits__mem` (64) bytes.

## Type `SeenRecall`

The keys of one message whose entries lantern_seen_recall copies back.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `count` | u64 | Items, at most `SEEN_RECALL_MAX` (4) |
| 8 | `items` | `count` items of 64 bytes | Each: `kind` at 0 (a `SEEN_*` key kind, or `SEEN_RECALL_BITS`), `a` at 8, `b` at 16, `c` at 24, `root` at 32 |

### Rules

- A key item names a `SeenKey` (kind, a, b, c).
- `SEEN_RECALL_BITS` (256) names the `SEEN_AGGREGATE` bitsets of (root, a, b = the target epoch).
- `SEEN_RECALL_SIZE` bytes holds the most items.

## Type `SeenMark`

What lantern_seen_recall added, for lantern_seen_forget.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `keys` | u64 | Keys of seen before |
| 8 | `added_keys` | u64 | Keys added |
| 16 | `bits` | u64 | Bits entries of seen before |
| 24 | `added_bits` | u64 | Bits entries added |

## Test vectors

- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/networking/<handler>/` of phase0 to fulu, for mainnet and minimal.
  - File: `mainnet.tar.gz` and `minimal.tar.gz` of the release, with the SHA-256 in tests/generator/generate.py.
  - Handlers `get_custody_groups` and `compute_columns_for_custody_group` (fulu): the runner compares `result` with the output list.
  - Handlers `gossip_<topic>`: the runner follows `tests/formats/networking/gossip_validation.md` of the spec. It builds the store with lantern_get_forkchoice_store and lantern_on_block, records a `failed` or `pending` block with lantern_seen_add_block, sets a block's `payload_status` with lantern_store_payload_status, writes `finalized_checkpoint` into the store and, for fulu, `seen_partial_data_column_headers` into `seen`, then validates each message in order and compares `valid`, `ignore` or `reject`.
  - Bellatrix: the runner passes as `justified_state` the state it keeps for the root of the store's `justified_checkpoint`.
  - The runner applies the `config` part of a gossip case over the preset's config.
- Lantern's cases of the p2p helpers, `<preset>-<fork>-p2p-<function>.bin` of phase0 to fulu, made by tests/generator/p2p.py: no official cases test these functions.
  - The expected results of the spec functions come from the spec modules of consensus-specs v1.7.0-beta.4 (aa16bb4), which the generator builds: each case runs the function with the case's `config` part over the preset's config. A null `output` is where the spec raises; the runner then expects the error the function documents.
  - lantern_compute_enr_fork_id and lantern_compute_next_fork_digest follow the text of the `eth2` field and Next fork digest sections, with compute_fork_digest and compute_fork_version of the spec module. lantern_gossip_topic, lantern_gossip_topic_parse and lantern_compute_message_id follow the text of Topics and messages of phase0 and of the message-id of phase0 and altair, with python-snappy 0.7.3.
  - The runner also checks each output buffer one entry or byte short, and the guard bytes after every output.
- consensus-spec-tests v1.7.0-beta.4, `tests/<preset>/<fork>/merkle_proof/single_merkle_proof/BeaconBlockBody/` of deneb to fulu.
  - Deneb and electra: the runner builds a `BlobSidecar` of the commitment that the case's `leaf_index` names, the case's `branch` and a block header with the body's root, and checks that lantern_verify_blob_sidecar_inclusion_proof accepts it, and rejects it with one branch byte changed.
  - Fulu: the runner builds a `PartialDataColumnHeader` of the body's `blob_kzg_commitments`, the case's `branch` and a block header with the body's root, and checks that lantern_verify_partial_data_column_header_inclusion_proof accepts it, and rejects it with one branch byte changed.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_get_custody_groups`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_columns_for_custody_group`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_subnet_for_data_column_sidecar`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_verify_data_column_sidecar_inclusion_proof`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_verify_partial_data_column_header_inclusion_proof`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_verify_partial_data_column_sidecar_kzg_proofs`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compute_subnet_for_blob_sidecar`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_verify_blob_sidecar_inclusion_proof`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_fork_version`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_fork_digest`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_attestation_subnet_prefix_bits`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_min_epochs_for_block_requests`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_max_compressed_len`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_max_message_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_subscribed_subnet`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_subscribed_subnets`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_max_request_blob_sidecars`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_max_request_data_column_sidecars`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_enr_fork_id`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_next_fork_digest`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_gossip_topic`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_gossip_topic_parse`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_message_id`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_seen_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_seen_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_seen_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_seen_add_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_beacon_block_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_blinded_block_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_validate_beacon_aggregate_and_proof_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_beacon_attestation_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_voluntary_exit_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_proposer_slashing_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_attester_slashing_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_sync_committee_contribution_and_proof_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_sync_committee_message_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_bls_to_execution_change_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_blob_sidecar_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_data_column_sidecar_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_validate_partial_data_column_sidecar_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_block_lookup`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_checkpoint_is`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_commitments_in_body`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_finalized_is_ancestor`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_finalized_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_header_checks`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_current_or_previous_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_future_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_future_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_is_within_slot_range`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_seen_add_bits`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_seen_add_key`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_seen_bits_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_seen_find_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_seen_find_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_seen_find_key`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_seen_key_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_seen_superset`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_verify_signed`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_verify_with_domain`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_compressed_len`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_next_fork_epoch`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
