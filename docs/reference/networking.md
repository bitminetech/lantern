# Networking rules

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
- [`lantern_validate_beacon_block_gossip`](#gossip-validation-functions): topic `beacon_block`.
- [`lantern_validate_blinded_block_gossip`](#gossip-validation-functions): the checks of topic `beacon_block` on a blinded block (beacon-api.md, publishBlindedBlockV2), from bellatrix.
- [`lantern_validate_beacon_aggregate_and_proof_gossip`](#gossip-validation-functions): topic `beacon_aggregate_and_proof`.
- [`lantern_validate_beacon_attestation_gossip`](#gossip-validation-functions): topic `beacon_attestation_{subnet_id}`.
- [`lantern_validate_voluntary_exit_gossip`](#gossip-validation-functions): topic `voluntary_exit`.
- [`lantern_validate_proposer_slashing_gossip`](#gossip-validation-functions): topic `proposer_slashing`.
- [`lantern_validate_attester_slashing_gossip`](#gossip-validation-functions): topic `attester_slashing`.
- [`lantern_validate_sync_committee_contribution_and_proof_gossip`](#gossip-validation-functions): topic `sync_committee_contribution_and_proof`.
- [`lantern_validate_sync_committee_message_gossip`](#gossip-validation-functions): topic `sync_committee_{subnet_id}`.
- [`lantern_validate_bls_to_execution_change_gossip`](#gossip-validation-functions): topic `bls_to_execution_change`.
- [`lantern_validate_blob_sidecar_gossip`](#gossip-validation-functions): topic `blob_sidecar_{subnet_id}`.
- [`lantern_validate_data_column_sidecar_gossip`](#gossip-validation-functions): topic `data_column_sidecar_{subnet_id}`.
- [`lantern_validate_partial_data_column_sidecar_gossip`](#gossip-validation-functions): partial messages of `data_column_sidecar_{subnet_id}`.

### Types

- [`NodeID`](#type-nodeid): the discv5 node ID as a number.
- [`GossipTopic`](#type-gossiptopic): a gossip topic: its fork digest, name and subnet.
- [`Seen`](#type-seen): the spec's `Seen`, and the blocks known without a post-state.
- [`SeenRoom`](#type-seenroom): the capacities of a `Seen`.
- [`SeenKey`](#type-seenkey), [`SeenBits`](#type-seenbits), [`SeenBlock`](#type-seenblock), [`SeenHeader`](#type-seenheader): its entries.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), each function at its latest definition from phase0 to fulu.
- Section: `fulu/das-core.md`, Custody; `p2p-interface.md` of phase0, altair, bellatrix, capella, deneb, electra and fulu, and `fulu/partial-columns/p2p-interface.md`: Helpers, Maximum message sizes, The gossip domain, ENR structure, Attestation subnet subscription; `fulu/beacon-chain.md`, compute_fork_digest; the helpers they call from `validator.md` of phase0, altair, deneb and electra.

## Common rules

- As in [helpers.md](helpers.md#common-rules).
- The config values are those of the `config` argument ([Type Config](helpers.md#type-config)), or of the store's copy for a function that takes a `store`; `NUMBER_OF_COLUMNS` is a preset value.
- `store` is a [`Store`](fork-choice.md#type-store). As in [fork-choice.md](fork-choice.md#common-rules), the caller keeps `store.block_states`.
- `store.blocks` of the spec is the store's nodes and the `blocks` of `seen`: a root in `seen` names a block that is known, but failed its state transition or waits to be imported, so it has no post-state. A root in `store.block_states` is a node of the store.
- `block_payload_statuses` of the spec is `BlockNode.payload_status` for a node and `SeenBlock.payload_status` for a block of `seen`.
- Signatures are verified with `crypto_bls_verify` and `crypto_bls_eth_fast_aggregate_verify` of asm-crypto, KZG proofs with `crypto_kzg_verify_blob_kzg_proof` (deneb, electra) and `crypto_kzg_verify_cell_kzg_proof_batch` (fulu).
- lantern_seen_size, lantern_seen_init, lantern_seen_copy and lantern_seen_add_block read no fork's layouts. Each is in the common object of the core (asm/core/<ISA>/common.s), and its symbol is its name.

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

### ABI

- Argument order: `blob_index`, `config`, `out`.
- Forks: deneb and electra.

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

### ABI

- Argument order: `sidecar`, `out`.
- Forks: deneb and electra.

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

### Function does

- Phase0 gives `GENESIS_FORK_VERSION` for every epoch. Each later fork adds its own fork's epoch and version, as its p2p-interface.md does.

### ABI

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

### Function does

- Fulu: at an epoch from `FULU_FORK_EPOCH` on, xors the 4 bytes with the first 4 bytes of sha256(uint_to_bytes(epoch) + uint_to_bytes(max_blobs_per_block)) of get_blob_parameters(epoch).

### ABI

- Argument order: `genesis_validators_root`, `epoch`, `config`, `scratch`, `out`.

## Function `lantern_compute_attestation_subnet_prefix_bits`

ceillog2(`ATTESTATION_SUBNET_COUNT`) + `ATTESTATION_SUBNET_EXTRA_BITS`.

### Signature

```
lantern_compute_attestation_subnet_prefix_bits(config, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the number of bits.
- `LANTERN_INVALID_OVERFLOW`: the sum does not fit in a u64.

### ABI

- Argument order: `config`, `out`.

## Function `lantern_compute_min_epochs_for_block_requests`

`MIN_VALIDATOR_WITHDRAWABILITY_DELAY` + `CHURN_LIMIT_QUOTIENT` // 2.

### Signature

```
lantern_compute_min_epochs_for_block_requests(config, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the epochs.
- `LANTERN_INVALID_OVERFLOW`: the sum does not fit in a u64.

### ABI

- Argument order: `config`, `out`.

## Function `lantern_max_compressed_len`

32 + n + n // 6: the longest Snappy output for n bytes of input.

### Signature

```
lantern_max_compressed_len(n, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the length.
- `LANTERN_INVALID_OVERFLOW`: the length does not fit in a u64.

### ABI

- Argument order: `n`, `out`.

## Function `lantern_max_message_size`

max(max_compressed_len(`MAX_PAYLOAD_SIZE`) + 1024, 1048576).

### Signature

```
lantern_max_message_size(config, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the size.
- `LANTERN_INVALID_OVERFLOW`: a sum does not fit in a u64.

### ABI

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

### Function does

- prefix_bits is lantern_compute_attestation_subnet_prefix_bits; the node offset is node_id % `EPOCHS_PER_SUBNET_SUBSCRIPTION`, over all 256 bits.
- The permutation seed is sha256(uint_to_bytes((epoch + node offset) // `EPOCHS_PER_SUBNET_SUBSCRIPTION`)).

### ABI

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

### ABI

- Argument order: `node_id`, `epoch`, `config`, `scratch`, `out`.

## Function `lantern_compute_max_request_blob_sidecars`

`MAX_REQUEST_BLOCKS_DENEB` * `MAX_BLOBS_PER_BLOCK` (deneb), or * `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra).

### Signature

```
lantern_compute_max_request_blob_sidecars(config, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the number.
- `LANTERN_INVALID_OVERFLOW`: the product does not fit in a u64.

### ABI

- Argument order: `config`, `out`.
- Forks: deneb and electra.

## Function `lantern_compute_max_request_data_column_sidecars`

`MAX_REQUEST_BLOCKS_DENEB` * `NUMBER_OF_COLUMNS`.

### Signature

```
lantern_compute_max_request_data_column_sidecars(config, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the number.
- `LANTERN_INVALID_OVERFLOW`: the product does not fit in a u64.

### ABI

- Argument order: `config`, `out`.
- Forks: fulu.

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

### Function does

- fork_digest is lantern_compute_fork_digest(genesis_validators_root, current_epoch).
- next_fork_epoch is the least epoch after current_epoch of the forks from altair up to the object's fork, a fork epoch of `FAR_FUTURE_EPOCH` left out; fulu adds each `BLOB_SCHEDULE` epoch from `FULU_FORK_EPOCH` on, the BPO forks. With none, it is `FAR_FUTURE_EPOCH`.
- next_fork_version is lantern_compute_fork_version(next_fork_epoch), or lantern_compute_fork_version(current_epoch) when next_fork_epoch is `FAR_FUTURE_EPOCH`.

### ABI

- Argument order: `genesis_validators_root`, `current_epoch`, `config`, `scratch`, `out`.

## Function `lantern_compute_next_fork_digest`

The value of the ENR `nfd` key: lantern_compute_fork_digest at the next_fork_epoch of lantern_compute_enr_fork_id, or 4 zero bytes when that is `FAR_FUTURE_EPOCH`.

### Signature

```
lantern_compute_next_fork_digest(genesis_validators_root, current_epoch, config, scratch, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the 4 bytes.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `LANTERN_SCRATCH_FIXED` bytes.

### ABI

- Argument order: `genesis_validators_root`, `current_epoch`, `config`, `scratch`, `out`.
- Forks: fulu.

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

### ABI

- Argument order: `topic`, `out`.
- Forks: none; in the common object, its symbol is its name.

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

### ABI

- Argument order: `string`, `out`.
- Forks: none; in the common object, its symbol is its name.

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

### Function does

- When data has a valid Snappy block decompression: the first 20 bytes of sha256(`MESSAGE_DOMAIN_VALID_SNAPPY` + the decompressed bytes). Otherwise: of sha256(`MESSAGE_DOMAIN_INVALID_SNAPPY` + data).
- Altair and later put uint_to_bytes(len(topic)) + topic after the domain, as altair p2p-interface.md says.
- A valid decompression is one that `snappy_uncompress` of asm-snappy accepts with a length of at most `MAX_PAYLOAD_SIZE`. The spec states no bound; a message above it fails the gossip size limits.

### ABI

- Argument order: `topic`, `data`, `config`, `scratch`, `out`.

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
lantern_validate_blinded_block_gossip(seen, store, signed_blinded_beacon_block, current_time_ms, head_state, proposer_state, scratch, result) -> status
lantern_validate_beacon_aggregate_and_proof_gossip(seen, store, signed_aggregate_and_proof, current_time_ms, head_state, scratch, result) -> status
lantern_validate_beacon_attestation_gossip(seen, store, attestation, current_time_ms, subnet_id, head_state, scratch, result) -> status
lantern_validate_voluntary_exit_gossip(seen, store, signed_voluntary_exit, current_time_ms, head_state, scratch, result) -> status
lantern_validate_proposer_slashing_gossip(seen, store, proposer_slashing, head_state, scratch, result) -> status
lantern_validate_attester_slashing_gossip(seen, store, attester_slashing, head_state, scratch, result) -> status
lantern_validate_sync_committee_contribution_and_proof_gossip(seen, store, signed_contribution_and_proof, current_time_ms, head_state, scratch, result) -> status
lantern_validate_sync_committee_message_gossip(seen, store, sync_committee_message, current_time_ms, subnet_id, head_state, scratch, result) -> status
lantern_validate_bls_to_execution_change_gossip(seen, store, signed_bls_to_execution_change, current_time_ms, head_state, scratch, result) -> status
lantern_validate_blob_sidecar_gossip(seen, store, blob_sidecar, current_time_ms, subnet_id, head_state, proposer_state, settings, scratch, result) -> status
lantern_validate_data_column_sidecar_gossip(seen, store, sidecar, current_time_ms, subnet_id, head_state, proposer_state, settings, scratch, result) -> status
lantern_validate_partial_data_column_sidecar_gossip(seen, store, sidecar, current_time_ms, group_id, column_index, head_state, proposer_state, settings, scratch, result) -> status
```

- Bellatrix: lantern_validate_beacon_block_gossip and lantern_validate_blinded_block_gossip take `justified_state` after `proposer_state`: (seen, store, signed_beacon_block, current_time_ms, head_state, proposer_state, justified_state, scratch, result).

### Arguments

| Name | Role | Type |
|---|---|---|
| `seen` | state | `Seen` |
| `store` | input | `Store` |
| the message | input | the topic's type of the fork: `SignedBeaconBlock`, `SignedAggregateAndProof`, `Attestation` (phase0 to deneb) or `SingleAttestation` (electra and later), `SignedVoluntaryExit`, `ProposerSlashing`, `AttesterSlashing`, `SignedContributionAndProof`, `SyncCommitteeMessage`, `SignedBLSToExecutionChange`, `BlobSidecar`, `DataColumnSidecar` or `PartialDataColumnSidecar` |
| `current_time_ms` | input | u64 |
| `subnet_id` | input | u64 |
| `group_id` | input | `PartialDataColumnGroupID` |
| `column_index` | input | u64 |
| `head_state` | input | `BeaconState`: `store.block_states[get_head(store).root]` |
| `proposer_state` | input | `BeaconState`: a copy of `store.block_states` of the message's parent block after process_slots to the message's slot; read only when the parent is a node of the store and the message's slot is after the parent's |
| `justified_state` | input | `BeaconState`: `store.block_states[store.justified_checkpoint.root]` |
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
- `beacon_block`, a parent with no post-state: phase0 and altair give `LANTERN_GOSSIP_REJECT`. Bellatrix decides by is_execution_enabled(justified_state, block.body), then the parent's payload status. Capella and later decide by the parent's payload status.
- `beacon_block`, bellatrix: the payload timestamp check and the `INVALIDATED` parent check run only when is_execution_enabled(head_state, block.body) holds. Capella and later run them always.
- lantern_validate_blinded_block_gossip: the checks of `beacon_block` in the same order on a `SignedBlindedBeaconBlock`: the signature of the hash_tree_root of its `BlindedBeaconBlock` (that of the full block), the timestamp of its `execution_payload_header`, the count of its `blob_kzg_commitments`. Its execution is enabled: a blinded block has a payload. Phase0 and altair have no blinded block: `LANTERN_INVALID_EVENT`.
- `beacon_block`, the commitment limit: `MAX_BLOBS_PER_BLOCK` (deneb), `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra), the `max_blobs_per_block` of get_blob_parameters at the block's epoch (fulu).
- `beacon_attestation_{subnet_id}` and `beacon_aggregate_and_proof`, phase0 to capella: the slot is within `ATTESTATION_PROPAGATION_SLOT_RANGE` of the current slot (is_within_slot_range). Deneb and later: the slot is not in the future and its epoch is the current or previous epoch.
- `beacon_attestation_{subnet_id}`, phase0 to deneb: the message is an `Attestation`. It has exactly one aggregation bit set and as many bits as the committee; the participant is the committee member at the set bit, and is_valid_indexed_attestation checks its one signature.
- `beacon_aggregate_and_proof`, phase0 to deneb: the committee index is `data.index`, and `aggregate_data_roots` is keyed by the data root alone. Electra and later key it by the data root and the committee index.
- `voluntary_exit`, phase0 to capella: the signature domain is get_domain(state, `DOMAIN_VOLUNTARY_EXIT`, voluntary_exit.epoch). Deneb and later use the capella fork version, as process_voluntary_exit does.
- `blob_sidecar_{subnet_id}`: the index limit is `MAX_BLOBS_PER_BLOCK` (deneb) or `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra). A blob, commitment or proof that `crypto_kzg_verify_blob_kzg_proof` cannot decode gives `LANTERN_GOSSIP_REJECT`, where the spec's verify_blob_kzg_proof raises.

### Limits

- Scratch, with n the validator count of head_state:

| Topic | Scratch |
|---|---|
| `beacon_block` (fulu), `voluntary_exit`, `proposer_slashing`, `bls_to_execution_change`, `sync_committee_{subnet_id}` | S(0) |
| `beacon_block` (phase0 to electra) | S(2), with n the validator count of proposer_state: get_beacon_proposer_index |
| `blob_sidecar_{subnet_id}` | S(2), with n the validator count of proposer_state, and at least `CRYPTO_KZG_SCRATCH` of asm-crypto |
| `beacon_attestation_{subnet_id}` | S(3) |
| `beacon_aggregate_and_proof` | S(10) + `IndexedAttestation__fixed` + 8 |
| `sync_committee_contribution_and_proof` | S(1) + 24 + 48 * `SYNC_COMMITTEE_SIZE` / `SYNC_COMMITTEE_SUBNET_COUNT` |
| `attester_slashing` | S(7) + 72 + 8 * (a + b + min(a, b)), a and b the index counts of its two attestations |
| `data_column_sidecar_{subnet_id}`, partial columns | S(0), and what the inclusion proof and the KZG check of the sidecar need |

### ABI

- Argument order: as in the signatures. An argument after the eighth (the sixth on x86-64) is on the stack, as the core ABI says.
- Forks: every fork has `beacon_block`, `beacon_aggregate_and_proof`, `beacon_attestation_{subnet_id}`, `voluntary_exit`, `proposer_slashing` and `attester_slashing`. The sync committee topics are in altair and later, `bls_to_execution_change` in capella and later, `blob_sidecar_{subnet_id}` in deneb and electra, the column topics in fulu.

## Type `NodeID`

A Uint256: 32 bytes, little endian.

### Rules

- Starts at a multiple of 8.

## Type `GossipTopic`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `fork_digest` | ForkDigest, in a u64 | The 4 bytes, then 4 zero bytes |
| 8 | `name` | u64 | `GOSSIP_*` of include/lantern.inc |
| 16 | `subnet_id` | u64 | The subnet of a subnet topic, else 0 |

| Name | Topic | Subnet |
|---|---|---|
| `GOSSIP_BEACON_BLOCK` (1) | `beacon_block` | no |
| `GOSSIP_BEACON_AGGREGATE_AND_PROOF` (2) | `beacon_aggregate_and_proof` | no |
| `GOSSIP_BEACON_ATTESTATION` (3) | `beacon_attestation_{subnet_id}` | yes |
| `GOSSIP_VOLUNTARY_EXIT` (4) | `voluntary_exit` | no |
| `GOSSIP_PROPOSER_SLASHING` (5) | `proposer_slashing` | no |
| `GOSSIP_ATTESTER_SLASHING` (6) | `attester_slashing` | no |
| `GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF` (7) | `sync_committee_contribution_and_proof` | no |
| `GOSSIP_SYNC_COMMITTEE` (8) | `sync_committee_{subnet_id}` | yes |
| `GOSSIP_BLS_TO_EXECUTION_CHANGE` (9) | `bls_to_execution_change` | no |
| `GOSSIP_BLOB_SIDECAR` (10) | `blob_sidecar_{subnet_id}` | yes |
| `GOSSIP_DATA_COLUMN_SIDECAR` (11) | `data_column_sidecar_{subnet_id}` | yes |
| `GOSSIP_LIGHT_CLIENT_FINALITY_UPDATE` (12) | `light_client_finality_update` | no |
| `GOSSIP_LIGHT_CLIENT_OPTIMISTIC_UPDATE` (13) | `light_client_optimistic_update` | no |

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
| `SEEN_BLOB_SIDECAR` (11) | `blob_sidecar_tuples` | (slot, proposer index, blob index) |

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

### `lantern_get_custody_groups`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_columns_for_custody_group`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
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
| x86-64 | ✅ | ✅ |  |  |
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
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_verify_blob_sidecar_inclusion_proof`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_fork_version`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_fork_digest`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_attestation_subnet_prefix_bits`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_min_epochs_for_block_requests`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_max_compressed_len`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_max_message_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_subscribed_subnet`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_subscribed_subnets`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_max_request_blob_sidecars`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_max_request_data_column_sidecars`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_enr_fork_id`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_next_fork_digest`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_gossip_topic`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_gossip_topic_parse`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_compute_message_id`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_seen_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_seen_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_seen_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_seen_add_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
