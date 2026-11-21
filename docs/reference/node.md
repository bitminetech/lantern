# Node

## Contents

### Functions

- [`lantern_node_size`](#function-lantern_node_size): the bytes of a `Node` with given capacities.
- [`lantern_node_init`](#function-lantern_node_init): a `Node` at an anchor block and state.
- [`lantern_node_copy`](#function-lantern_node_copy): copies a `Node` into a buffer with more capacity.
- [`lantern_node_step`](#function-lantern_node_step): handles events and gives actions.
- [`lantern_node_run`](#function-lantern_node_run): does one unit of work on beacon states or stored bytes.
- [`lantern_node_protocols`](#function-lantern_node_protocols): the req/resp protocol IDs for the libp2p config.
- [`lantern_node_import`](#function-lantern_node_import): on_block of a block's SSZ bytes, for one fork.
- [`lantern_node_block_root`](#function-lantern_node_block_root): the root of a block's SSZ bytes, for one fork.
- [`lantern_node_proposers`](#function-lantern_node_proposers): the proposers of an epoch and its dependent root, from the state at its first slot, for one fork.
- [`lantern_node_event_roots`](#function-lantern_node_event_roots): the block root, state root and dependent roots of a block's post-state, for one fork.
- [`lantern_node_attestation_data`](#function-lantern_node_attestation_data): the `AttestationData` of a state's slot, for one fork.
- [`lantern_node_attester_duties`](#function-lantern_node_attester_duties): the committee assignments of validators in an epoch, for one fork.
- [`lantern_node_liveness`](#function-lantern_node_liveness): whether validators were seen live in an epoch, from a state and a `Seen`, for one fork.
- [`lantern_node_block_rewards`](#function-lantern_node_block_rewards): the proposer's rewards of a block, part by part, on its pre-state, for one fork.
- [`lantern_node_sync_rewards`](#function-lantern_node_sync_rewards): the balance changes of a block's sync aggregate, on its pre-state, for one fork.
- [`lantern_node_reward_totals`](#function-lantern_node_reward_totals): the totals of an epoch's attestation rewards, for one fork.
- [`lantern_node_attestation_rewards`](#function-lantern_node_attestation_rewards): the attestation rewards of a window of validators, for one fork.
- [`lantern_node_ideal_reward`](#function-lantern_node_ideal_reward): the attestation rewards of a validator of an effective balance that voted in time, for one fork.
- [`lantern_node_payload_parent`](#function-lantern_node_payload_parent): the block number and hash of a state's latest execution payload header, for one fork from bellatrix.
- [`lantern_node_sidecar_root`](#function-lantern_node_sidecar_root): hash_tree_root of the block header of a sidecar's SSZ bytes, for one fork from deneb.
- [`lantern_node_randao`](#function-lantern_node_randao): the RANDAO mix of an epoch in a state, for one fork.
- [`lantern_node_sync_committee`](#function-lantern_node_sync_committee): the validator indices of a state's sync committee of an epoch, for one fork.
- [`lantern_node_proposer_lookahead`](#function-lantern_node_proposer_lookahead): a state's `proposer_lookahead`, for one fork.
- [`lantern_node_weights`](#function-lantern_node_weights): get_weight of each node of a store, for one fork.
- [`lantern_node_sync_subnets`](#function-lantern_node_sync_subnets): compute_subnets_for_sync_committee of a validator, for one fork.
- [`lantern_node_sync_positions`](#function-lantern_node_sync_positions): the places of a validator in that sync committee, for one fork.
- [`lantern_node_data_root`](#function-lantern_node_data_root): hash_tree_root of an `AttestationData`'s SSZ bytes, for one fork.
- [`lantern_node_pending`](#function-lantern_node_pending): the items of a pending list of a state, for one fork.
- [`lantern_node_produce_check`](#function-lantern_node_produce_check): the proposer of a state's slot, its randao reveal checked, for one fork.
- [`lantern_node_payload_result`](#function-lantern_node_payload_result): the SSZ bytes of an engine_getPayload result, for one fork.
- [`lantern_node_produce_fold`](#function-lantern_node_produce_fold): a pool entry added to the body draft of a block to produce, for one fork.
- [`lantern_node_produce_block`](#function-lantern_node_produce_block): the block of produceBlockV3 from its draft and the engine's payload, or blinded with the builder's bid, for one fork.
- [`lantern_node_produce_bid`](#function-lantern_node_produce_bid): the valid bid of a builder's getHeader answer, for one fork.
- [`lantern_node_publish_decode`](#function-lantern_node_publish_decode): the signed block of a publishBlockV2 body, for one fork.
- [`lantern_node_publish_sidecars`](#function-lantern_node_publish_sidecars): the sidecars of a publishBlockV2 body, for one fork from deneb.
- [`lantern_node_publish_check`](#function-lantern_node_publish_check): the checks of `broadcast_validation` of a block to publish, for one fork.
- [`lantern_node_blinded_block`](#function-lantern_node_blinded_block): the blinded block of a block's SSZ bytes, for one fork.
- [`lantern_node_attestation`](#function-lantern_node_attestation): on_attestation of an attestation's SSZ bytes, for one fork.
- [`lantern_node_attester_slashing`](#function-lantern_node_attester_slashing): on_attester_slashing of a slashing's SSZ bytes, for one fork.
- [`lantern_node_gossip`](#function-lantern_node_gossip): the gossip validation of a message's SSZ bytes, for one fork.
- [`lantern_node_blob_sidecar`](#function-lantern_node_blob_sidecar): the checks of a blob sidecar of a response, for deneb or electra.
- [`lantern_node_column_sidecar`](#function-lantern_node_column_sidecar): the checks of a column sidecar of a response, for fulu.
- [`lantern_node_new_payload`](#function-lantern_node_new_payload): the HTTP request of engine_newPayload for a block's SSZ bytes, for one fork.
- [`lantern_node_db_scan`](#function-lantern_node_db_scan): adds a segment file's records to the node's `Db`.
- [`lantern_node_anchor`](#function-lantern_node_anchor): the anchor state and block of a genesis state's SSZ bytes, for one fork.
- [`lantern_node_anchor_block`](#function-lantern_node_anchor_block): the anchor state and block of a finalized state and its block, for one fork.
- [`lantern_node_state_bytes`](#function-lantern_node_state_bytes): the SSZ bytes of a state, for one fork.
- [`lantern_node_upgrade`](#function-lantern_node_upgrade): the state of the fork from a state of the fork before, for one fork.
- [`lantern_node_replay`](#function-lantern_node_replay): the post-state again of a block the node imported, for one fork.
- [`lantern_node_backfill`](#function-lantern_node_backfill): the proposer signature of an older block of the backfill, for the fork of a state.
- [`lantern_node_block_header`](#function-lantern_node_block_header): the signed header of a block's SSZ bytes, for one fork.
- [`lantern_node_state_checkpoints`](#function-lantern_node_state_checkpoints): the three checkpoints of a state, for one fork.
- [`lantern_node_json`](#function-lantern_node_json): the JSON of a block's or a state's SSZ bytes, a chunk at a time, for one fork.

### Types

- [`Node`](#type-node): the state of the node.
- [`NodeRoom`](#type-noderoom): the capacities of a `Node`.
- [`NodeBlock`](#type-nodeblock): a block the node knows.
- [`NodeCheckpoint`](#type-nodecheckpoint): a checkpoint state the node keeps.
- [`NodePeer`](#type-nodepeer): a connected libp2p peer.
- [`NodeStream`](#type-nodestream): a req/resp stream a peer opened.
- [`NodeMessage`](#type-nodemessage): a gossip message the node holds.
- [`NodeBlob`](#type-nodeblob): a blob sidecar, or from fulu a column sidecar, the node holds.
- [`NodeApi`](#type-nodeapi): a Beacon API answer the node streams.
- [`NodeGossip`](#type-nodegossip): the inputs of lantern_node_gossip.
- [`NodeAnchor`](#type-nodeanchor): the anchor of lantern_node_init.
- [`NodeStepResult`](#type-nodestepresult): the output of lantern_node_step.
- [`NodeEvents`](#type-nodeevents), [`NodeEvent`](#type-nodeevent): the events of lantern_node_step.
- [`NodeActions`](#type-nodeactions), [`NodeAction`](#type-nodeaction): the actions of lantern_node_step.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), `fork-choice.md` of phase0 to fulu: the handlers, `store.block_states` and `store.checkpoint_states`.
- `fork.md` of altair to fulu, Fork transition: the upgrade runs once process_slots has set the slot to the fork's first slot; the block of that slot then goes on from the upgraded state. A state of an older fork crosses each fork boundary in turn.
- `p2p-interface.md` of phase0, altair and fulu, The Req/Resp domain: Status, Goodbye, Ping and MetaData, their versions, and the result codes.
- `p2p-interface.md` of phase0, Status: once the handshake completes, the client with the lower `head_slot` requests blocks with BeaconBlocksByRange; after some rounds of it, a client may send Status again to learn of a higher head. Clients SHOULD disconnect on another `fork_digest`, or on a finalized checkpoint not in their chain at its epoch.
- `p2p-interface.md` of phase0 to fulu, The gossip domain: the topics of each fork, the message-id, `MAX_PAYLOAD_SIZE`, and the validation of each topic, as [networking.md](networking.md) gives it.
- `fork-choice.md` of deneb, `is_data_available`: a block is not valid until its blobs are downloaded; the network does not promise sidecars outside `MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS`.
- `p2p-interface.md` of deneb, BlobSidecarsByRange v1: the reader checks each sidecar's format, inclusion proof and KZG proof before the next chunk.
- `p2p-interface.md` of fulu, BeaconBlocksByHead v1: the blocks of the ancestry of `beacon_root`, inclusive, in descending slot order, until `min(count, MAX_REQUEST_BLOCKS_DENEB)` blocks or an ancestor outside the epochs a node must serve; at least one block when the node has the block at `beacon_root`; a ForkDigest context for each chunk.
- `p2p-interface.md` of deneb, BlobSidecarsByRange v1 and BlobSidecarsByRoot v1: the server sends the sidecars of the head's chain in (slot, index) order, or of the requested identifiers in their order, at most compute_max_request_blob_sidecars; of electra, its limit; of fulu, the deprecation: sidecars before `FULU_FORK_EPOCH`, an empty list at or after it.
- `fork-choice.md` of fulu, `is_data_available`: every column sidecar the node samples passes verify_data_column_sidecar and verify_data_column_sidecar_kzg_proofs; the network does not promise sidecars outside `MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS`.
- `das-core.md` of fulu, Custody sampling: the node samples the columns of the groups of get_custody_groups(node_id, max(`SAMPLES_PER_SLOT`, custody_group_count)); its custody groups are the first custody_group_count of them. Column gossip: the node joins the subnets of the columns it samples. A node may custody more than `CUSTODY_REQUIREMENT` groups, "up to `NUMBER_OF_CUSTODY_GROUPS`, indicating a super-full node": with `NODE_FLAG_SUPERNODE`, lantern's custody_group_count is `NUMBER_OF_CUSTODY_GROUPS`, so it samples every column.
- `p2p-interface.md` of fulu, DataColumnSidecarsByRange v1 and DataColumnSidecarsByRoot v1: the reader checks each sidecar's format, inclusion proof and KZG proofs before the next chunk; the server sends the sidecars of the head's chain in (slot, column index) order, or of the requested identifiers in their order, at most compute_max_request_data_column_sidecars. GetMetaData v3: the peer's `custody_group_count`.
- The node ID of a secp256k1 key: keccak256 of the key's 64-byte uncompressed point (x then y), the discv5 identity scheme "v4" (EIP-778). get_custody_groups reads those 32 bytes as a big-endian number, as Lighthouse does (`U256::from_be_slice` in consensus/types/src/data/data_column_custody_group.rs); a `NodeID` holds them in reverse order.
- `p2p-interface.md` of phase0 to fulu, The discovery domain: discv5: the ENR keys `eth2` (`ENRForkID`), `attnets`, `syncnets` (altair), `cgc` and `nfd` (fulu); peers whose `eth2` fork digest is the node's. The Req/Resp domain, Status: the dialing client MUST send a Status request upon connection.
- `optimistic-sync.md` of bellatrix: optimistic import, the optimistic candidate, how to apply `latestValidHash`, execution engine errors.
- [execution-apis 981aa66](https://github.com/ethereum/execution-apis/tree/981aa66d79364be8322a9c358aaf0a571cca0873/src/engine): engine_newPayload and engine_forkchoiceUpdated, with the requests and answers of [engine-api.md](engine-api.md). The safe block is the justified checkpoint's root (fork-choice `safe-block.md`).
- ARCHITECTURE.md sections 2 and 6: the event and action model; section 7: the calls to asm-libp2p.

## Common rules

- As in [helpers.md](helpers.md#common-rules) and [fork-choice.md](fork-choice.md#common-rules).
- The shell owns every buffer. The core names a beacon state or a stored byte string by a `BufferId`: a u64 from 1 that the node gives. 0 names none. The shell maps each id to its buffer.
- lantern_node_step reads no beacon state. Work on beacon states and stored bytes is a `NODE_ACT_WORK` action.
- The shell does the actions of one step in order. For a `NODE_ACT_WORK` action it calls lantern_node_run with the buffers of its ids, and passes the event that run writes to a later step.
- The node keeps `store.block_states` as the post-state id of each imported `NodeBlock`, and `store.checkpoint_states` as its `NodeCheckpoint` entries.
- The fork of a slot is the last fork whose epoch in the node's config is at most the slot's epoch. The node calls the functions of the fork of the block, the attestation, the state or the store's slot it works on.
- A state's slot is the u64 at `NODE_STATE_SLOT` of its value in every fork.
- The node owns a libp2p `State` of asm-libp2p, built by the shell with `libp2p_init` from a config whose protocol list is lantern_node_protocols. lantern_node_step calls `libp2p_step` with it: first with the libp2p events of the `NODE_EV_P2P` events and the events the node queued, then with the events the node queued in that step, up to `NODE_P2P_ROUNDS` times.
- The application's shell may run asm-discv5 for the node (`NODE_FLAG_DISCV5`): it passes each record discv5 finds, and each bootnode record, in a `NODE_EV_ENR`, and the asm-discv5 events of each `NODE_ACT_DISCV5` to discv5_step.
- libp2p's actions go out in a `NODE_ACT_P2P_LIST` action. The shell does its shell requests in order; the node took its application notices.
- The node's queue (`p2p_out`) is one ByteList of libp2p events inside the node. libp2p_step reads it in place.
- A stream carries one request and one answer, as the req/resp functions of [req-resp.md](req-resp.md) encode them.
- The node answers the Beacon API ([beacon-api.md](beacon-api.md)). The shell keeps the connections: it reads each request with lantern_http_request and passes it in a `NODE_EV_API`, one request of a connection at a time, and writes the bytes of each `NODE_ACT_API_SEND` to its connection. A connection is a u64 the shell gives. The node keeps a `NodeApi` entry for each answer it sends in more than one chunk, and no other state of a connection.
- A streamed answer goes one chunk at a time: the shell passes a `NODE_EV_API_SENT` of the connection once it has room for the next chunk, and a `NODE_EV_API_CLOSED` when the connection closes.
- lantern_node_size, lantern_node_init, lantern_node_copy, lantern_node_step, lantern_node_run and lantern_node_protocols are in the common object of the core (asm/core/<ISA>/node.s), and each symbol is its name.
- lantern_node_import, lantern_node_block_root, lantern_node_attestation, lantern_node_attester_slashing, lantern_node_gossip and lantern_node_json are in each fork object (asm/core/<ISA>/nodehooks.s), exported as `lantern_<fork>_<name>`. lantern_node_blob_sidecar is in the deneb and electra objects only, lantern_node_column_sidecar in the fulu object only, lantern_node_new_payload in the bellatrix and later objects.

## Test vectors

- The fork_choice files of [fork-choice.md](fork-choice.md#test-vectors), a second time, through the node: each case reports a second time with ` (node)` after its name.
  - The runner plays the shell: a table of `BufferId` to buffer, the actions of each step in order, each `NODE_ACT_WORK` run when it comes, its event to the next step, until a step gives no work.
  - Its config sets the epoch of each fork up to the runner's fork to 0 and of each later fork to 2^64 - 1.
  - Each step of the case is events: `tick` a `NODE_EV_TICK`, `block` a `NODE_EV_BLOCK` with the block's data availability, `attestation` a `NODE_EV_ATTESTATION`, `attester_slashing` a `NODE_EV_ATTESTER_SLASHING`, `pow_block` a `NODE_EV_POW_BLOCK`.
  - A valid block's attestations and attester slashings go to fork choice through the node's own works; the runner sends none.
  - A valid block must be `NODE_BLOCK_IMPORTED`, an invalid block must not. An attestation or slashing is valid when the result of its last work is `LANTERN_VALID`.
  - The checks read the store, the node's `head_root`, and the post-state the node keeps for the head.
  - After the steps of each event, the store's first node must be the root of its finalized checkpoint: the node pruned it.
  - The sidecar drop (drop_check): a node with `NODE_FLAG_DB` and a `Db` of three segments of slots, with a block and a sidecar in the first segment and a block in the last, at a store's slot past them and windows of 0 epochs, must give a `NODE_ACT_DB_DROP` of sidecar segments 0 and 1 and no other, `sidecar_floor` the first slot of segment 2, and an index with no sidecar below it and the same blocks.
  - Every second node the runner starts has `NODE_FLAG_DB`. Each `NODE_ACT_DB_STATE` must name a state of its slot and a buffer of bytes; lantern_node_state_bytes of the state and the block's message, as the two ByteLists of lantern_node_anchor_block, must give a state and a block of their roots, and with another `state_root` `LANTERN_INVALID_ANCHOR`. After the case, a new node of the same start given the segments with lantern_node_db_scan must take every record and hold the same index, the same segments to append to, and `db_next_slot` past the index's last block.
  - The runner's nodes with `NODE_FLAG_DB`: The runner keeps its segments in memory: each `NODE_ACT_DB_APPEND` must be at its segment's end, of the length of the bytes of its id, with the ByteList header of those bytes, and of a slot of its segment; a SERVE of a `NODE_DB_REF` gets the record's ByteList in place in the segment. A block or sidecar in the node's `Db` counts as imported or held in the checks below.
  - From bellatrix on, the node has `NODE_FLAG_ENGINE`, and the runner is its execution engine too. It answers each `NODE_ACT_ENGINE` request with an HTTP/1.1 response in two `NODE_EV_ENGINE` events: engine_newPayload of a `blockHash`, and engine_forkchoiceUpdated of a `headBlockHash`, with the `payloadStatus` of the case's last `payload_status` step of that hash, else `VALID` with that hash as `latestValidHash`. The request must carry a JWT of the node's secret.
  - Cases with `payload_status` steps run in node mode from bellatrix on, through the node's execution engine calls; before bellatrix only directly.
  - A non-zero status of lantern_node_step or lantern_node_run must leave the node, the store and the work's state byte for byte unchanged.
- After the sync of a fork_choice case's chain (fc_sync_check), a new node dials a peer whose Status has another `fork_digest`: the node must drop the peer.
- Backfill (fc_backfill_check, after fc_sync_check, for a case whose chain has two blocks or more), and in fulu a second time with the peer's Status `earliest_available_slot` the slot of the chain's last block: a new node with `NODE_FLAG_DB` starts from the post-state and the block of the chain's last block, as a checkpoint start does, at the case's last tick, and gets a peer whose Status head is that block. The peer answers each BeaconBlocksByRange with the chain's blocks of the range, the anchor block of the case included. Each block of the chain from the last down to the case anchor's child must reach the `Db` with its root, each with the sidecars of the case (the peer answers BlobSidecarsByRange and DataColumnSidecarsByRange too), and `backfill_slot` and `earliest_slot` must be the lowest of them; then getBlockHeaders of the slot of each block below the anchor, and of the root of each block below the anchor's parent as `parent_root`, must answer the `Db`'s block alone, as beacon-api.md gives it. Run again with the signature of one block changed: that block and those below it must not reach the `Db`.
- Every second pair of nodes the runner starts has `NODE_FLAG_FEW_STATES`; each `NODE_WORK_REPLAY` must give `LANTERN_VALID`; the runner counts them in a NOTE.
- The first case of each fork_choice get_head file before fulu, a third time, as ` (subscribe)`: a node whose config has the fork after the runner's at epoch 3, beside the runner's peer. At epoch 0 the peer must see the node join the topics of the runner's fork and no more; at epoch 1 those of the next fork too (from electra, the column subnets of the node's `columns`); at the fork, no change; at epoch 5 the node must leave the first ones, and no more.
- The transition/core files of [fork-upgrades.md](fork-upgrades.md#test-vectors), a second time, through the node, as the fork_choice files are: each case reports a second time with ` (node)` after its name.
  - The node's anchor is lantern_node_anchor of the fork before, of the case's `pre`; its config sets each fork before the runner's to 0 and the runner's fork to the case's `fork_epoch`. A `pre` that lantern_node_anchor refuses runs only directly.
  - Each block of the case goes in a `NODE_EV_BLOCK` after a `NODE_EV_TICK` of its slot. Each must be `NODE_BLOCK_IMPORTED`, the head must be the last block, and the post-state the node keeps for it must be the case's `post`.
  - The node has no `NODE_FLAG_ENGINE`; the runner's shell grows a state with the copy of the fork of its slot: `state_a` of a `NODE_WORK_SLOTS`, `state_b` of a `NODE_WORK_UPGRADE`.
  - A `pre` past the slot of its latest block header is no anchor (get_forkchoice_store needs that block's post-state): such a case runs only directly.
  - Bellatrix: before a block of the new fork whose payload's `parent_hash` differs from the last one given, the runner gives the node, in two `NODE_EV_POW_BLOCK` events, a PowBlock of the payload's `parent_hash` with total difficulty `TERMINAL_TOTAL_DIFFICULTY` and its parent with one less, as the fork_choice files' `pow_block` steps do, so that validate_merge_block holds for the merge transition block; the case gives none.
- Each block of each fork_choice case: lantern_node_block_header of its SSZ bytes must give the slot, proposer_index, parent_root, state_root and signature of those bytes, and a header whose hash_tree_root is the block's.
- The anchor state of each fork_choice case: lantern_node_state_checkpoints must give its previous_justified_checkpoint, current_justified_checkpoint and finalized_checkpoint.
- The anchor of each fork_choice case: lantern_node_anchor of the case's `anchor_state` must give a state whose SSZ bytes are the case's `anchor_state` and a block whose SSZ bytes are the case's `anchor_block`, when that block has the default body; else `LANTERN_INVALID_ANCHOR`.
- Lantern's cases `<preset>-<fork>-node-p2p.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec: an anchor state and block at the first slot of epoch 2, and the Status and MetaData the node answers.
  - The answers come from get_forkchoice_store, get_head and compute_fork_digest of the spec module, with each fork up to the case's at epoch 0 and each later fork at 2^64 - 1.
  - The runner plays the network between the node's libp2p state and a bare asm-libp2p peer, as tests/runner of asm-libp2p does. The peer dials the node and opens one stream for each request.
  - Status (v2 in fulu, v1 before) and MetaData (v3 in fulu, v2 before) must be the case's, the MetaData with the bits of the node's subnets as `attnets` and a `seq_number` above 0 with them; Ping must give 0; Goodbye must close with no answer.
  - The node's peer entry must hold the peer's ID and the Status it sent.
  - After each connection of the runner's network: getPeers, with no query, with `state` `connected`, with `state` `disconnected,connecting`, with each `direction`, and with both sets, must answer the peer as beacon-api.md gives it, with its connection's address (the peer's 10.0.0.1 and TCP port 40001 when the peer dials the node, the record's 10.0.0.2 and 9000 when the node dials it), or no peer; getPeer of its peer ID text must answer it, and of another, 404.
  - The node has `NODE_FLAG_DISCV5`: its `NODE_ACT_DISCV5` actions must set `eth2` to lantern_compute_enr_fork_id at the anchor's epoch, `attnets` to the bits of the node's subnets at that epoch (lantern_compute_subscribed_subnets of its node ID), from altair `syncnets` to 1 zero byte (no sync subscription yet), in fulu `cgc` to the node's custody group count and `nfd` to lantern_compute_next_fork_digest, and ask for a lookup.
  - The operation events: an eventstream of `proposer_slashing,attester_slashing` over HTTP/1.1, then from the peer a valid proposer slashing and a valid attester slashing of the anchor's validators (signed with the keys of the spec's test helpers), each Snappy compressed on its topic of the anchor's epoch. The stream's bytes must be its head, then the case's event text of each, each in one chunk.
  - The subscriptions (beacon-api.md): prepareBeaconCommitteeSubnet of an aggregator for the next slot on a subnet outside `attnets` must answer 200, and the peer must see the node join one topic; at the slot after that slot, leave one topic. From altair, prepareSyncCommitteeSubnets of index 0 to the next epoch must answer 200, and the peer must see the node join one topic, its `seq_number` one more, MetaData v2 with bit 0 of `syncnets`, and the record's `syncnets` 1; at that epoch, leave one topic, `seq_number` one more, the record's `syncnets` 0.
- The `fork_choice-get_head` and `fork_choice-on_block` cases in node mode, after their steps: the runner opens the same network, and the node serves the chain of the case's last checked head, which the runner builds from the case's valid blocks by `parent_root`.
  - BeaconBlocksByRange v2 from the anchor's slot to the head's must give each block of the chain, in slot order.
  - BeaconBlocksByRoot v2 of the head, a root of no block, and the chain's first block must give the head and the first block.
  - Each chunk must have result 0, the block's SSZ bytes, and compute_fork_digest of the block's epoch as context bytes.
  - From altair, the light client methods: GetLightClientFinalityUpdate, GetLightClientOptimisticUpdate, GetLightClientBootstrap of the anchor's root, the chain's first block, its head and an unknown root, and LightClientUpdatesByRange from period 0 with a count of 200 and of 0. Each answer must be the chunks of the node's light client store (BufferId 2) as lantern_lc_read gives its objects: result 0, the context compute_fork_digest of the object's fork for the epoch of its first header's slot, and its bytes; the updates from the first period held to the first period of none, at most `MAX_REQUEST_LIGHT_CLIENT_UPDATES`; one chunk of result 3 with no payload where a single object is missing; no chunk for a range of none.
- The light client gossip, on nodes whose light client store is a copy of a light_client data_collection case's store at its end (light-client.md, Test vectors). For each topic, the update the runner expects: lantern_lc_read of the store, which goes when its `ForkDigest` (compute_fork_digest of its fork at the epoch of its attested slot) is the node's `fork_digest` and it is new for fields at 0.
  - Publish: the peer joins both topics; with the fields at 0, `lc_pending` 3 and `lc_due` 0, the peer must get each update that goes, on its topic, Snappy compressed, the node's fields must take its slots, and `lc_pending` must be 0.
  - Validation, on a second node with the finality topic early and on a third with the optimistic topic early, the fields at 0: on the early topic, the update with its last byte changed, then the update itself at its due time less `MAXIMUM_GOSSIP_CLOCK_DISPARITY` less 1 ms, must leave the fields at 0; on the other topic the update at its due time must set the topic's fields to its slots.
- The `fork_choice-get_head` and `fork_choice-on_block` cases a third time, over gossip: each case reports with ` (gossip)` after its name.
  - Only cases with no `payload_status` step whose valid blocks each have their own slot and come at or after the start of that slot.
  - The runner opens the same network. The node's topics must reach the peer.
  - Each valid block goes from the peer as a beacon_block message, Snappy compressed, on the topic of the block's epoch. The node must import it.
  - An eventstream of `block_gossip,blob_sidecar,data_column_sidecar` over HTTP/1.1 is open before the steps. After each valid block and its sidecars go over gossip, the stream must have the events of them in order, each in one chunk: the block's, then each sidecar's, the runner's texts from the case's bytes (beacon-api.md).
  - Each valid attester slashing goes from the peer on the attester_slashing topic of the last tick's epoch. One the node does not apply goes again as a `NODE_EV_ATTESTER_SLASHING`. A case with valid attester slashings must apply one over gossip.
  - Each valid attestation goes from the peer first as a `SignedAggregateAndProof` on the beacon_aggregate_and_proof topic of the last tick's epoch: its first attester aggregates it, signed with the pyspec test keys (validator i has the secret key i + 1); from electra, only an attestation of one committee. The vote the node applies from it must be valid. One the node does not apply goes again as a `NODE_EV_ATTESTATION`. The runner counts both in a NOTE.
  - The other steps go as in node mode; the checks must hold.
- The same cases in node mode, after the serving check: a new node at the case's anchor, at the case's last tick, syncs the chain of the last checked head.
  - The runner's peer has a secp256k1 key. The node gets a `NODE_EV_ENR` of the peer's record, made with asm-discv5 from that key, with an `ip`, a `tcp` port and the `eth2` of lantern_compute_enr_fork_id at the case's epoch. The node must dial the peer and send its Status; the peer answers with a Status whose head is the chain's last block, and answers each BeaconBlocksByRange request of the node with the chain's blocks in the range.
  - It answers each BlobSidecarsByRange request with the sidecars of the case's `node-blobs` case of the chain's blocks in the range, in (slot, index) order, with compute_fork_digest of the slot's epoch as context bytes.
  - Each block of the chain must be `NODE_BLOCK_IMPORTED`, and the node's `head_root` must be the chain's last block.
  - Each sidecar it sent must be a `NODE_BLOB_VALID` entry of the node.
  - Then the node serves them: BlobSidecarsByRange v1 from the anchor's slot to the head's must give each sidecar of the chain in (slot, index) order; BlobSidecarsByRoot v1 of the chain's sidecars from the last block to the first, with an identifier of no sidecar among them, must give those sidecars in that order. Each chunk must have result 0, the sidecar's SSZ bytes, and compute_fork_digest of its slot's epoch as context bytes.
  - Then, through the Beacon API, getBlobSidecars of the root of each block of the chain with sidecars must answer, as SSZ, its sidecars one after another; as JSON, items that lantern_json_decode of `BlobSidecar` gives as those sidecars; with `indices` of its first and last sidecar, as SSZ, those two.
  - And getBlobs of the root of each such block must answer, as SSZ, the `blob` of each of its sidecars one after another; as JSON, `data` items whose hex gives those blobs; with `versioned_hashes` of the commitments of its first and last sidecar, as SSZ, those two blobs.
  - A case with sidecars syncs again with a new node and no sidecars in the answers: no block of the chain with blob commitments, and no later one, may be `NODE_BLOCK_IMPORTED`.
  - In fulu, the node's `node_id` is the node ID of the peer's key, so its columns hold the peer's custody columns of any custody group count. The peer answers each GetMetaData v3 request with `custody_group_count` `NUMBER_OF_CUSTODY_GROUPS`, and each DataColumnSidecarsByRange request with the column sidecars of the case's `columns` steps of the chain's blocks in the range and of the request's columns, in (slot, index) order, with compute_fork_digest of the slot's epoch as context bytes. Each such request must ask for the node's columns, in ascending order.
  - Each column sidecar it sent must be a `NODE_BLOB_VALID` entry of the node.
  - Then the node serves them: DataColumnSidecarsByRange v1 of every column from the anchor's slot to the head's must give each of those sidecars in (slot, index) order; DataColumnSidecarsByRoot v1 of the chain's blocks from the last to the first, each with the node's columns and one column it does not sample, then an identifier of a root of no block, must give those sidecars in that order. Each chunk must have result 0, the sidecar's SSZ bytes, and compute_fork_digest of its slot's epoch as context bytes.
  - Then, through the Beacon API, getDebugDataColumnSidecars of the root of each block of the chain with columns must answer, as SSZ, its sidecars of the node's columns one after another; as JSON, items that lantern_json_decode of `DataColumnSidecar` gives as those sidecars; with `indices` of the first and last of them, as SSZ, those two.
  - getBlobs of the root of each block of the chain with columns must answer 404: the node holds fewer than half of the columns.
  - A fulu case with column sidecars syncs again with a new node with `NODE_FLAG_SUPERNODE`. Each DataColumnSidecarsByRange of the node must ask for every column, in ascending order, and each block of the chain must be `NODE_BLOCK_IMPORTED`. getNetworkIdentity must give `custody_group_count` `NUMBER_OF_CUSTODY_GROUPS`. getBlobs of the root of each block of the chain with columns must answer, as SSZ, a blob for each of the sidecars' `kzg_commitments`, whose crypto_kzg_blob_to_kzg_commitment of asm-crypto gives that commitment; as JSON, `data` items whose hex gives those blobs; with `versioned_hashes` of its first and last commitments, as SSZ, those two blobs.
  - A fulu case with column sidecars syncs again with a new node and a peer whose MetaData gives `CUSTODY_REQUIREMENT` custody groups and whose answers hold no sidecars: each DataColumnSidecarsByRange of the node must ask for the columns of get_custody_groups(the peer's node ID, `CUSTODY_REQUIREMENT`), in ascending order, and no block of the chain with blob commitments, and no later one, may be `NODE_BLOCK_IMPORTED`.
- Lantern's cases `<preset>-<fork>-node-api.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec: the anchor of the `p2p` cases, an `ApiIdentity`, a time, and requests with the response of each, written by the rules of [beacon-api.md](beacon-api.md#common-rules) from the spec's values.
  - The runner gives the node a `NODE_EV_TICK` of the time and a `NODE_EV_API_IDENTITY`, then each request on its own connection: lantern_http_request with `head_max` 16384 and `body_max` 1048576, then a `NODE_EV_API` of its `HttpRequest`, of `LANTERN_OK` or `LANTERN_INVALID_HTTP`; it plays the shell until the node settles.
  - The bytes of the connection's `NODE_ACT_API_SEND` actions must be the case's response, the last with `last` 1 and no other; the connection must get one `NODE_ACT_API_CLOSE` after them when the case says it closes, else none.
  - Requests: each operation the node answers; the head by `head` and by its root, and another root (404); produceBlockV3 of the head's slot, and publishBlockV2 and publishBlindedBlockV2 with no body (400, or 503 while syncing); each other operation (501); route faults (400, 404, 405 with `Allow`, 406, 414, 415); faulty requests (400, 413, 431, 501, 505); `Connection: close`; HTTP/1.0 with and without `keep-alive`; getHealth with `syncing_status`; getStateV2 of `head` as JSON and as SSZ, over HTTP/1.1 and HTTP/1.0; getBlockV2 of `head`, whose anchor block has no bytes (404).
  - The runner keeps each id of a `NODE_ACT_STATE_BYTES`, with lantern_node_state_bytes of the fork of the state's slot, and gives a `NODE_EV_API_SENT` of the connection after each `NODE_ACT_API_SEND` with `last` 0.
  - Each request runs twice: with an event of `NodeEvent_api_bytes` + 24 + `NODE_API_CHUNK` bytes for each `NODE_WORK_API_CHUNK`, then with 2048 bytes after the chunk's ByteList header, or a 512th of the case's response when that is more, so that a large answer goes in some hundreds of chunks.
  - A response with `Transfer-Encoding: chunked` counts as the response with `Content-Length` of its chunks' bytes in place of that field and those bytes as its body; its chunks must keep RFC 9112 section 7.1. A JSON response over HTTP/1.0 with neither field counts as the response with `Content-Length` of its bytes after `Eth-Consensus-Version`, or after `Content-Type` with no `Eth-Consensus-Version`, and the connection must get a `NODE_ACT_API_CLOSE`.
  - After each answer the node must hold no `NodeApi` entry, each id of a `NODE_ACT_STATE_BYTES` must have had its `NODE_ACT_BYTES_FREE`, and the runner must hold the buffers it held before the request.
  - eventstream of `head,block,finalized_checkpoint` over HTTP/1.1, with and without `Connection: close`, and of `block` over HTTP/1.0, with and without `keep-alive`, and a topic of no name (400). For the two streams, the case's `streams` byte of the request is 1: the sends must be the head with `last` 0 and no close; then the runner gives a `NODE_EV_API_CLOSED` of the connection, and the node must hold no `NodeApi` entry.
  - The pools, in the case of the anchor at epoch EPOCHS_PER_HISTORICAL_VECTOR + 6 (past `SHARD_COMMITTEE_PERIOD`), with 4 x SLOTS_PER_EPOCH - 8 active validators more (committees of two members or more), whose validators have the keys of the spec's test helpers and some the BLS withdrawal credentials of other keys of them: submitPoolVoluntaryExit of a valid exit, of it again (seen: 200), of one with another key's signature (400) and of a body of no exit (400); submitPoolProposerSlashings of a valid slashing and of one of two equal headers (400); submitPoolAttesterSlashingsV2 of a valid slashing, and with a fork of another `AttesterSlashing` type (400); submitPoolBLSToExecutionChange of three changes whose second has another key's signature (400, its failure), and of a list with an item of no change (400); submitPoolAttestationsV2 of two valid attestations of the committees of the slots after the anchor's, of one of them again (seen: 200), of two whose first has another key's signature (400, its failure), with a fork of the other attestation type (400), of a list of no attestation (400), and as SSZ of one of another slot and committee; then the five pool GETs, each over HTTP/1.1 and HTTP/1.0, and getPoolAttestationsV2 with `slot`, with `committee_index`, with both, and with a slot of none; getAggregatedAttestationV2 of the first attestation's data (two attestations or more, so crypto_bls_aggregate adds signatures) over HTTP/1.1, HTTP/1.0 and as SSZ, of another root (404), of a slot of none (404), and while the runner holds every node of the store `NOT_VALIDATED` (503; the case's `syncing` byte of the request, bit 1); publishAggregateAndProofsV2 of that aggregate by an aggregator of its committee, of it again (seen: 200), of one signed with another key (400, its failure), with a fork of the other type (400), of a list of no aggregate (400), and as SSZ of the aggregate of an attestation of another slot; from altair, submitPoolSyncCommitteeSignatures of messages of the store's slot for the head by members of the head state's sync committee: two valid, one again (seen: 200), one with another key's signature and a valid one (400, its failure), one of a validator outside the committee (400), of no message (400); produceSyncCommitteeContribution of the subcommittee of the first message's first subnet over HTTP/1.1 and HTTP/1.0, of another root (404), of a slot of none (404), with `NOT_VALIDATED` nodes (503), of a subcommittee index of `SYNC_COMMITTEE_SUBNET_COUNT` (400); publishContributionAndProofs of that contribution by an aggregator of its subcommittee, signed with another key (400, its failure), valid, again (seen: 200), of no contribution (400); prepareBeaconCommitteeSubnet of an aggregator and another, of none (200), of a committee index not below `committees_at_slot`, of `committees_at_slot` 0 and above `MAX_COMMITTEES_PER_SLOT`, of an item of no subscription (400); from altair prepareSyncCommitteeSubnets of indices 0 and SYNC_COMMITTEE_SIZE - 1 (200), of an index of SYNC_COMMITTEE_SIZE (400), of an item of no subscription (400); in the other cases, with an empty pool, 404. The answers come from the gossip validation of the spec module, with a `Seen` the case's requests fill in order, as each request runs twice (the two rooms of the runner). The runner gives the store the node's fork epochs, as the spec module has them, and after each answer holds no other buffers than those of the operations the pool took.
  - getProposerDuties: the epochs from the anchor's epoch - 1 to the epoch of the store's slot + 2, and one while the runner holds `NODE_FLAG_SYNCING` (the case's `syncing` byte of the request, bit 0); in a third case, an anchor at slot 0, the epochs 0 to 2.
  - produceAttestationData: each slot from the anchor's - 1 to the store's + 1 with `committee_index` 1, one with `committee_index` 2^64 - 1, as SSZ, over HTTP/1.0, and one while the runner holds `NODE_FLAG_SYNCING`.
  - getAttesterDuties: the epochs from the anchor's epoch - 1 to the epoch of the store's slot + 2 with indices of active and inactive validators, one past the validator count and one twice; no body, an empty array, a public key, over HTTP/1.0, and one while the runner holds `NODE_FLAG_SYNCING`.
  - getSyncCommitteeDuties: epoch 0, the anchor's epoch - 1 and epoch, the epoch of the store's slot and the next, those epochs + `EPOCHS_PER_SYNC_COMMITTEE_PERIOD`, and the store's + 2 periods (400), each with every validator index and two past the count; some indices, no body, an empty array, a public key, over HTTP/1.0, and one while the runner holds `NODE_FLAG_SYNCING`.
  - getEpochCommittees: of `head` with no query, each `epoch` from the state's epoch - 1 to its epoch + 2, a `slot` of the epoch and one of another, `index` 0 and 1, a `slot` with an `index`, over HTTP/1.0, and with a `state_id` of `finalized`, of a slot and of a root; and in a second case, an anchor at epoch EPOCHS_PER_HISTORICAL_VECTOR + 6, the lowest epoch beacon-api.md takes and the one below it.
  - The six validator operations, of an anchor state with 8 more validators, one of each status but `active_ongoing`: each status and group of `status`; `id` items of indices and public keys, known, unknown and given twice; the bodies of the three POSTs; getStateValidator of an index and of a key, and of ones no validator has (404); the identities as SSZ; over HTTP/1.0 and with `Connection: close`; and with a `state_id` of a state root.
  - getSpec, getForkSchedule and getDepositContract, from the pinned config, presets and the spec module's constants, with the node's fork epochs; getSpec also over HTTP/1.0 and with `Connection: close`, and getForkSchedule over HTTP/1.0.
  - Lookup requests, the states from process_slots of the anchor state: getBlockRoot, getBlockHeader and getBlockV2 of `head`, `finalized`, `genesis`, the anchor's slot and the slots before and after it, the anchor's root and another root; getStateRoot, getStateFork and getStateFinalityCheckpoints of `head`, `finalized`, `justified`, `genesis`, the anchor's slot, each slot after it to the store's slot and the slot after that, the anchor state's root, the root of the state of the anchor's slot + 1, and another root; getStateV2 as JSON of `finalized` and of the anchor's slot + 2; getStateRandao, getEpochSyncCommittees and getProposerLookahead of `head`, `finalized`, `genesis`, another root, the root of the state of the anchor's slot + 1 and that slot, getProposerLookahead of `head` as SSZ, getStateRandao of `head` at the epochs 0, the anchor's epoch - 1, it, + 1 and + EPOCHS_PER_HISTORICAL_VECTOR, and getEpochSyncCommittees of `head` at the epochs 0, the anchor's, and the first of the next two sync committee periods. The anchor state has the sync committees of genesis (both get_next_sync_committee) from altair; from electra three pending deposits of slots past the finalized one, two pending partial withdrawals and two pending consolidations of a source that is not withdrawable, which the epochs keep. getPendingDeposits, getPendingPartialWithdrawals and getPendingConsolidations of the state ids of the reads above, of `head` as SSZ, and over HTTP/1.0.
  - getLiveness, with an anchor state whose `current_epoch_participation` flags are 1 for validator 2 and 4 for validator 6, and whose `previous_epoch_participation` flags are 7 for validator 5: the epoch of the store's slot, the one before and the one after, with indices of those validators and others, one past the validator count and one twice; the epochs past those (400); no body, an empty array, a public key (400); over HTTP/1.0; one while the runner holds `NODE_FLAG_SYNCING`. In the pools case, after its POSTs: the same epochs with the indices of the attesters, aggregators, sync committee members and contribution aggregators the POSTs named. The answers: beacon-api.md's rules with the spec module's `Seen` of the requests before.
  - The operation events, in the pools case: an eventstream of the operation topics (beacon-api.md) over HTTP/1.1 before the POSTs, its request once, its connection open to the case's end (the case's `streams` byte of the request is 2). After the last request its bytes must be its head, then the event of each valid operation of the POSTs in order, each in one chunk; then the runner gives a `NODE_EV_API_CLOSED` of it. While it is open, the node may hold its `NodeApi` entry after each answer.
  - getStateV2 of `head` as SSZ with the small event, and a `NODE_EV_API_CLOSED` of the connection after its first chunk: the connection must get no more actions, and the node must hold no `NodeApi` entry and must free the state's bytes.
- The `fork_choice-get_head` and `fork_choice-on_block` cases in node mode, after their steps: getBlockHeader of `head` must answer 200 with the node's `head_root` as `root` and the slot of its block, and getStateFinalityCheckpoints of `head` with the checkpoints of the post-state the node keeps for the head, getDebugChainHeadsV2 with the leaves of the node's store, and getDebugForkChoice with the store's checkpoints and nodes, each weight lantern_get_weight of its node, as beacon-api.md gives them.
  - The chain: the case's valid blocks from the node's `head_root` by `parent_root`. For each slot after the anchor's to the head's, getBlockRoot of the slot must answer the root of the chain's block of that slot, or 404 for a slot with none.
  - For each slot from the head's to the store's, at most an epoch and a slot past the head's: getStateRoot of the slot must answer the hash_tree_root of the head's post-state, processed to that slot with lantern_process_slots of the fork of the head's slot (from a slot it does not reach, the rest is skipped).
  - For each valid block of the case the node holds: getBlockHeader of its root must answer 200, with `canonical` true when it is on the chain, else false.
  - getBlockHeaders of each slot of a valid block of the case and of the slot after the head's, of the root of the anchor and of each such block as `parent_root`, of such a block's slot with its parent root and with another root, and with no query: the answer of beacon-api.md from the case's blocks, each header from the block's bytes; a block of the chain the node no longer holds is the `Db`'s.
  - For each slot from the anchor's to the head's, at most `SLOTS_PER_HISTORICAL_ROOT` below the head's: getStateRoot of the slot, then getStateRoot of the state root of that slot (the head's post-state's hash_tree_root, or its `state_roots` entry), must each answer that root; below the slot of the block of the store's finalized root the state comes from the replay.
  - getBlockV2 of `head` as SSZ must answer 200 with the SSZ bytes of the case's head block, and as JSON with `version` the name of the fork of its slot and a `data` that lantern_json_decode of the fork's `SignedBeaconBlock` gives as those bytes. A head that is the case's anchor must answer 404.
  - getBlindedBlock of `head` as SSZ must answer 200 with `Eth-Consensus-Version` and the SSZ bytes of a `SignedBlindedBeaconBlock` of the fork (from bellatrix; before, a `SignedBeaconBlock`) whose message has the head's root and whose signature is the head block's; as JSON, a `data` that lantern_json_decode of that type gives as those bytes; 404 for the anchor.
  - getBlockAttestationsV2 of `head` must answer 200 with `Eth-Consensus-Version` and `version` the name of the fork of its slot and a `data` that lantern_json_decode of the fork's `Attestations` gives as the bytes of the body's `attestations` of the head block; 404 for the anchor. As getBlockV2, in chunks of `NODE_API_CHUNK` and of 2048 bytes.
  - getStateV2 of `head` as SSZ must answer 200 with lantern_node_state_bytes of the post-state the node keeps for the head, and as JSON with a `data` that lantern_json_decode of the fork's `BeaconState` gives as those bytes.
  - Each a second time with 2048 bytes of room for each chunk, or a 128th of the state's SSZ bytes when that is more.
- Lantern's cases `<preset>-<fork>-node-liveness.bin` of phase0 to fulu, made by tests/generator/node.py with the pinned spec, for lantern_node_liveness: a state, the `SeenKey` entries of a `Seen`, the indices of `ids`, an epoch, and the bytes of `out`, by the rules of [beacon-api.md](beacon-api.md#common-rules) (getLiveness) with the spec's `Seen` of those keys.
  - The states: the anchor of the `api` cases at epochs 0 and 2; in phase0 with `previous_epoch_attestations` and `current_epoch_attestations` of committees of the epochs, some bits set; from altair with participation flags of some validators.
  - The keys: each of the five kinds the rules read, of the epoch, the epochs before and after, and slots of each; keys of the other kinds; a key of an index past the validators.
  - The epochs: that of the state, the one before, the one after, and the fifth after.
  - The runner fills a `Seen` of lantern_seen_init with the keys, in order, and passes `scratch` of S(6). The case's `out` must match, and `seen` and the state must keep their bytes.
- Lantern's cases `<preset>-<fork>-node-rewards.bin` of phase0 to fulu, made by tests/generator/node.py with the pinned spec, for lantern_node_block_rewards and, from altair, lantern_node_sync_rewards: a pre-state P, a block, in phase0 the states `early` and `late`, the status, the 48 bytes of `out` of lantern_node_block_rewards, and from altair the items of lantern_node_sync_rewards, by the rules of [beacon-api.md](beacon-api.md#common-rules) (getBlockRewards, getSyncCommitteeRewards).
  - P: the anchor of the `api` cases at epoch 2 with 56 more active validators, processed to a slot of epoch 3 whose proposer is not slashed (in one case a sync committee member); from altair, flags set for every fifth validator, and a member with a balance below `participant_reward`.
  - The block: attestations of three slots of the previous epoch (two committees each), of a wrong head, of a wrong target, one again of the same members, and of the last two slots of the current epoch; two proposer slashings; attester slashings whose intersections hold a validator a proposer slashing slashes, one slashed in P, one not slashable, and validators the other slashing slashes too; from altair a sync aggregate with some bits set.
  - Phase0: `early` and `late`, the block on P and the slots to the end of its epoch and of the next; in two of the cases each with an earlier copy of one of the block's attestations, by another proposer, and an attester slashed.
  - The generator checks each part against the spec's own functions: the proposer's balance changes of process_proposer_slashing, process_attester_slashing, process_attestation and process_sync_aggregate on P, and in phase0 the proposer's part of get_inclusion_delay_deltas of `early` and `late`.
  - A case with P one slot past the block's: `LANTERN_INVALID_SLOT`.
  - The runner passes `scratch` of S(6), and an `out` of lantern_node_sync_rewards a byte short of its room, which must give `LANTERN_BUFFER_TOO_SMALL`. Each input must keep its bytes.
- The `rewards` cases of the spec (basic, leak, random, inactivity_scores) also check, in mode 0, lantern_node_reward_totals and lantern_node_attestation_rewards of every validator of their pre-state against their deltas: `source`, `target` and `head` each the validator's reward less its penalty of the delta of that flag or vote, `inactivity` minus its inactivity penalty. In windows of 7 validators and one of all of them.
- Lantern's cases `<preset>-<fork>-node-attrewards.bin` of phase0 to fulu, made by tests/generator/node.py with the pinned spec: one for each case of the spec's `rewards` cases, its `pre` and, for modes 0 and 1, the items of lantern_node_attestation_rewards of every validator and of lantern_node_ideal_reward of every effective balance step (beacon-api.md), from the spec's get_flag_index_deltas, get_inactivity_penalty_deltas and the phase0 delta functions on the state, after process_justification_and_finalization and from altair process_inactivity_updates in mode 1. The phase0 inclusion_delay is the attester's part of get_inclusion_delay_deltas: (get_base_reward - get_proposer_reward) // the delay of its earliest attestation.
- Lantern's cases `<preset>-<fork>-node-reads.bin` of phase0 to fulu, made by tests/generator/node.py with the pinned spec: one for each `fork_choice-get_head` and `fork_choice-on_block` case, named as its node-events case. Its parts `requests` and `responses`: after the case's steps in node mode, each request on its own connection must give its answer, in the form with Content-Length.
  - The requests: getBlockRewards and getSyncCommitteeRewards of each block of the store, by root, in slot order; and getSyncCommitteeRewards of the head with id items: the index of the first member, the pubkey of the last, the index of a validator that is not a member, and an index past the validators.
  - The answers: beacon-api.md's rules, from a replay of the steps with the spec module, as the node-events cases have it. A block that descends from the store's finalized block has its rewards; the anchor, the finalized block and its ancestors, and a block of another branch after the finalized epoch rose: 404. getSyncCommitteeRewards in phase0 of a block the node holds: 400.
  - Also one for each `transition-core` case whose pre-state is an anchor, named `transition/` and the case's name, checked after the node of the transition case (above) imports its blocks: getBlockRewards and getSyncCommitteeRewards of the anchor (404), and of each block whose parent's slot is at least the first slot of the highest finalized epoch, realized or not, of any of the case's states, so that the store's finalized block is at or below the parent. The answers come from the blocks applied with the spec modules of both forks, the upgrade at the fork's first slot; the blocks of the fork before give the phase0 rules their E states.
- Lantern's cases `<preset>-<fork>-node-payload.bin` of bellatrix to fulu, made by tests/generator/node.py with the pinned spec: the anchor of the `api` cases, a validator index, a fee recipient, a time in the store's slot S at or after its attestation due time, and the answer of the execution engine.
  - The runner runs the node with `NODE_FLAG_ENGINE` and answers its engine calls as in the fork_choice cases. After the anchor's engine_forkchoiceUpdated, it gives a prepareBeaconProposer of the validator and fee recipient (200), then a `NODE_EV_TICK` of the time.
  - When the validator is get_beacon_proposer_index of the anchor state processed to slot S + 1: the node's next engine call must be engine_forkchoiceUpdated whose `params` are the case's, with the attributes of the spec's prepare_execution_payload of that state, the fee recipient, the justified root's block hash as safe and the finalized root's as finalized. The runner answers with the case's `payloadId`, a value or null; then `payload_slot`, `payload_root`, `payload_status` and `payload_id` must be the case's.
  - When it is another validator: the node must make no engine call after the tick, and `payload_status` must be `NODE_PAYLOAD_NONE`.
  - An eventstream of payload_attributes over HTTP/1.1 is open before the tick. After the case its bytes must be its head, then, when the node prepares, the case's text of the event in one chunk: the attributes of the spec's prepare_execution_payload in the beacon API encoding (beacon-api.md).
- Lantern's cases `<preset>-<fork>-node-produce.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec: the anchor of the `api` cases (from bellatrix that of the node-payload cases), the first slot after the anchor's whose proposer is not slashed, the requests with a time for each (0 for none), from bellatrix a `payloadId` and the engine's result, and the answers.
  - `empty_pool`: two produceBlockV3 requests of the slot at its start.
  - `full_pool`: the anchor `SHARD_COMMITTEE_PERIOD` epochs later with 2 `SLOTS_PER_EPOCH` more active validators. At 100 ms into the slot before: POSTs (200) of two voluntary exits, a proposer slashing, two attester slashings, from capella a BLS change, two attestations of one committee of the anchor's slot (from electra `SingleAttestation`s), and two sync committee messages of the slot before on the anchor's root, each valid by the spec's gossip validation; the first attester slashing slashes only the proposer slashing's validator, and the second exit is of a validator the second attester slashing slashes, so the block leaves both out. Then the two produceBlockV3 requests at the slot's start.
  - `skip_randao`: as `empty_pool`, with `skip_randao_verification` and `randao_reveal` the point at infinity; the state root is of process_block with no check of signatures.
  - `bad_reveal`: as `empty_pool`, two requests that must answer 400 before any engine call: a `randao_reveal` of another validator's key, and `skip_randao_verification` with the proposer's reveal.
  - `closed`: as `empty_pool`, its JSON request; `closes` is 24. For each count c from 0 to 23, the runner gives the request on a new connection, runs c steps of the node, then a `NODE_EV_API_CLOSED` of the connection: after the step that takes it, the node must send nothing more to the connection, and once it settles hold no `NodeApi` entry and no buffer the request made. Then the request must be answered as in `empty_pool`.
  - The produceBlockV3 requests: `randao_reveal` the proposer's signature of the epoch with the test keys, `graffiti` the bytes 0 to 31; the first with JSON, the second with `Accept: application/octet-stream`.
  - The engine's result: from the attributes of the spec's prepare_execution_payload of the anchor state processed to the slot, with the fee recipient zero, an empty payload on the anchor's, with `block_value` 123456789012345678901234567890 from capella and an empty bundle from deneb.
  - The answers: the spec's block with `eth1_data` the state's, the operations the rules of beacon-api.md take (the two attestations as one aggregate, the messages as the sync aggregate; with none, no bit and the point at infinity), the engine's payload, and `state_root` from process_block, which must accept it; consensus_block_value its rule of beacon-api.md.
  - The runner runs the node with `NODE_FLAG_ENGINE`, answers engine_forkchoiceUpdated with attributes with the case's `payloadId` and engine_getPayload with the case's result, gives a `NODE_EV_TICK` of `time_ms`, then each request after a `NODE_EV_TICK` of its time when that is not 0; each answer must be the case's, and after each request the runner's buffers must differ from those before it only by the ids the node holds (each `NodeBlock`'s bytes and post-state, each `NodeBlob`'s bytes, each pool entry's).
  - `closed`: the last close must come after the node has no event left, so the closes cover each step of the request. The closes run on the case's last request, after its tick and the requests before it.
  - The builder cases, from bellatrix, with `builder` 1: the runner runs the node with `NODE_FLAG_BUILDER` and is its builder.
  - The builder cases' anchor: its `block_roots` of the `SLOTS_PER_EPOCH` slots before its slot all differ, so no slot of the epoch before is skipped (the health of lantern_node_produce_check). It answers each builder call: registerValidator with 200 and no body; the k-th getHeader with the case's `bids` entry k, or its last entry past them; an empty entry is no answer. After the case, the requests of the node's builder calls, joined in their order, must be the case's `builders`. After each request, when the case's `after` entry is not 0, the node must have sent nothing to the connection; then a `NODE_EV_TICK` of that time, and the answer must be the case's.
  - The bid: on a payload of the engine's attributes with `fee_recipient` the registration's, two transactions, `extra_data` `builder`, `block_hash` 0x88 bytes, from capella the expected withdrawals, from deneb one commitment (the G1 point at infinity); from electra no requests; `value` 10^18 in bellatrix, the engine's `block_value` + 10^6 from capella; signed with test key 9 and compute_domain(`DOMAIN_APPLICATION_BUILDER`). The answer: `HTTP/1.1 200 OK`, `Content-Type: application/json`, `Content-Length`, the body `{"version":"<fork>","data":…}`.
  - `builder_bid`: at 100 ms into the slot before, a registerValidator (200) of the proposer, fee recipient 0x77 bytes, gas limit 30000000; then the two produceBlockV3 requests at the slot's start, each answered with the blinded block: the spec's block with the bid's payload, its state root from process_block, then blinded as builder-specs gives it.
  - `builder_boost`: as `builder_bid`, two JSON requests: `builder_boost_factor=0` (no getHeader, the local block) and `builder_boost_factor=50` (a getHeader; the local block from capella, the blinded block in bellatrix, whose local value is 0).
  - `builder_invalid`: as `builder_bid`, JSON requests each answered with the local block, the bids in turn: an answer of 204 with no body; a `version` of another fork; a fee recipient other than the registration's; a signature of another key; a parent hash other than the state's; another `prev_randao`; the timestamp of the slot after; from capella the withdrawals root of no withdrawals; from deneb one commitment more than the fork's limit.
  - `builder_late`: as `builder_bid`, its JSON request with no answer from the builder; `after` its time + 1000: then the local block.
  - `builder_unhealthy`: as `builder_bid`, on an anchor at epoch `ANCHOR_EPOCH` + 4 whose finalized epoch is 0: its JSON request with no getHeader, the local block.
  - `builder_closed`: as `builder_bid`, its JSON request, with `closes` 40 (as `closed`); each getHeader answered with the bid.
- Lantern's cases `<preset>-<fork>-node-publish.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec, run as the node-produce cases: the empty_pool block of the node-produce cases on an anchor at epoch 0 (on_block's shuffling dependent root of a later epoch is a block of the store there), signed with its proposer's test key, from deneb in a `SignedBlockContents` with no blobs. The spec's gossip validation, state_transition and on_block give each block's verdict, which the generator checks.
  - The events, in each case but the closed ones: an eventstream of `block_gossip,blob_sidecar,data_column_sidecar` over HTTP/1.1 is open before the requests. After the case its bytes must be the event of each block whose check passes and of each sidecar the node publishes, in order, each in one chunk, the case's `events` (beacon-api.md).
  - `published`: the block with `broadcast_validation=consensus_and_equivocation` (200), getBlockRoot of `head` (the block's root), then the block again in SSZ with no level (200: a block the node holds).
  - `refused`: at `consensus`, the block signed with another validator's key, the block with `Eth-Consensus-Version` of the fork before, and the block with another `state_root` signed by its proposer (each 400); then getBlockRoot of `head` (the anchor's root).
  - `gossip`: the block with another `state_root` at the default level (202: it goes out, and its import fails); then getBlockRoot of `head` (the anchor's root).
  - `closed`: as `published`'s first request, with `closes` 40; then getBlockRoot of `head` (the block's root).
  - From deneb, the block with the commitments of two blobs (its state root and signature again), with the blobs, and the spec's proofs (deneb and electra compute_blob_kzg_proof; fulu compute_cells_and_kzg_proofs), the spec's sidecars (get_blob_sidecars; fulu get_data_column_sidecars_from_block) valid by the spec's gossip validation, and on_block taking the block with them: `blobs` at `consensus` in JSON and `blobs_ssz` at the default level in SSZ (200; getBlockRoot of `head`, the block's root); `bad_proof`, the proofs swapped (deneb and electra those of the two blobs, fulu those of cells 0 and 1 of the first blob) at `consensus` (400; the anchor's root); `blobs_closed`, `blobs`' request with `closes` 40 + the count of sidecars + 8.
  - publishBlindedBlockV2, in altair: `published_blinded`, the block of `published` through publishBlindedBlockV2 (200, as publishBlockV2).
  - The blinded cases, from bellatrix: the blinded block of `builder_bid` signed with its proposer's test key, on the anchor of the builder cases, published at the slot's start with `builder` 1; the runner answers each `POST /eth/v2/builder/blinded_blocks` with the case's `submits` entry k, or its last past them, and the requests of the builder calls must be the case's `builders`. The spec's gossip validation of the full block and its state_transition give the verdicts, which the generator checks.
    - `blinded_published`: at `consensus_and_equivocation` in JSON, then at the default level in SSZ; the builder answers 202, each request 200 with the builder call of the block's JSON. The block goes to no `NodeBlock`: getBlockRoot of `head` gives the anchor's root.
    - `blinded_refused`: at `consensus`, the block signed with another key, the block with `Eth-Consensus-Version` of the fork before, the block with another `state_root` signed by its proposer, and a header with a zero `block_hash` signed by its proposer (each 400, no builder call).
    - `blinded_builder_error`: the builder answers 400: 500.
    - `blinded_no_builder`: with `builder` 0: 500.
  - Each case names the block's `root` and the SSZ bytes of the `sidecars` the node must keep: after the requests, its `NodeBlob` entries of that root in `NODE_BLOB_VALID` must be those sidecars at their indices, each of them before fulu, and in fulu one for each column of `Node_columns`; none for the cases with no blobs and for `bad_proof`. The runner loads the KZG trusted setup for the sidecars' checks, and gives a step that asks for scratch twice the room, as the app does.
- Lantern's cases `<preset>-<fork>-node-events.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec: one for each `fork_choice-get_head` and `fork_choice-on_block` case, named after its handler and its name, `get_head/` or `on_block/` and the case's name. Its part `events` is a list with the text of the events (beacon-api.md, eventstream) the node must send in each step of the case, from a replay of the steps with the spec module:
  - get_forkchoice_store of the anchor state and block; a tick: on_tick of the step's seconds times 1000; a valid block: on_block, then on_attestation with `is_from_block` true of each attestation of its body and on_attester_slashing of each attester slashing, with the step's blobs and proofs (deneb, electra) or columns (fulu) as the data of retrieve_blobs_and_proofs or retrieve_column_sidecars; an attestation and an attester slashing: on_attestation and on_attester_slashing; a step with `valid` false, or a block the store holds already, as the node skips it: no change. A valid step the spec module refuses, or a `checks` step whose head is not the replay's, stops the generator.
  - The texts of a step: a block event for a valid block; then, when get_head is not the head of the last head event (at first the anchor's root), a chain_reorg event when get_ancestor of the new head at the old head's slot is not the old head or that slot is not below the new head's, with the depth of beacon-api.md from get_ancestor of both heads at each slot, then a head event; then a finalized_checkpoint event when the store's finalized epoch is above that of the last one (at first the anchor store's).
  - `execution_optimistic`: true for a block from bellatrix whose payload has a nonzero `block_hash` and whose last `payload_status` step before its block step, of that hash, is `SYNCING` or `ACCEPTED`.
  - The runner runs the case in node mode with three event streams, opened after the anchor: of `head,block,finalized_checkpoint` over HTTP/1.1, and of `block,chain_reorg` over HTTP/1.0, each with a `NODE_EV_API_SENT` after each send; and of `finalized_checkpoint,head,block` over HTTP/1.1 with none. After each step, the bytes of each stream's sends in the step, the chunks of HTTP/1.1 decoded, must be the step's texts of its topics (chain_reorg only in the second); the third must get a `NODE_ACT_API_CLOSE` in place of the event whose bytes, with the head's and those of the events before it, would pass `NODE_API_CHUNK`, and no more actions. After the case, a `NODE_EV_API_CLOSED` of each stream: the node must hold no `NodeApi` entry.
- Lantern's cases `<preset>-<fork>-node-blobs.bin` of deneb and electra, made by tests/generator/node.py with the pinned spec: one for each `fork_choice-on_block` case whose block steps have blobs, of the same name.
  - Each part is named after a block file of the case and holds the `BlobSidecar` SSZ bytes of get_blob_sidecars of the block and the step's blobs and proofs, as a list.
  - A step with fewer proofs than blobs gives the sidecars of the indices that have both.
- In gossip mode, the sidecars of a valid block go from the peer after the block, each on the blob_sidecar topic of its subnet; the node must import the block.
- In gossip mode in fulu, the node's `node_id` is as in the sync, and the column sidecars of the node's columns of a valid block go from the peer after the block, each on the data_column_sidecar topic of its subnet; the node must import the block.

## Function `lantern_node_size`

The bytes of a `Node` whose parts have the capacities of a `NodeRoom`.

### Signature

```
lantern_node_size(room, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `room` | input | `NodeRoom` |
| `size` | output | u64 |

### Returns

- `LANTERN_OK`: `size` holds `NODE_FIXED` plus the bytes of each part.
- `LANTERN_INVALID_OVERFLOW`: the size is 2^64 or more, or `db_roots` is not a power of two.

## Function `lantern_node_init`

A node whose one block is the anchor, imported with post-state id 1, and whose one checkpoint is the anchor's epoch and root with state id 1. Its head is the anchor.

### Signature

```
lantern_node_init(room, config, anchor, flags, node) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `room` | input | `NodeRoom` |
| `config` | input | `Config` |
| `anchor` | input | `NodeAnchor` |
| `flags` | input | u64: `NODE_FLAG_*` |
| `node` | output | `Node`, its `size` set |

### Returns

- `LANTERN_OK`: the node is written.
- `LANTERN_BUFFER_TOO_SMALL`: `node` is smaller than lantern_node_size of `room`, or `room` has no block or no checkpoint.
- `LANTERN_INVALID_OVERFLOW`: as lantern_node_size.
- `LANTERN_INVALID_EVENT`: with `NODE_FLAG_ENGINE`, `engine_host_len` is above `NODE_ENGINE_HOST_MAX`; with `NODE_FLAG_BUILDER`, `builder_host_len` is.
- `LANTERN_INVALID_CUSTODY_GROUP`: max(`SAMPLES_PER_SLOT`, the node's custody group count) of `config` is above `NUMBER_OF_CUSTODY_GROUPS` or 128.

### Function does

- The node keeps the anchor's `node_id`; `attnets` is 0 until its first subscription.
- The first `BufferId` the node gives is 3: 1 is the anchor state, 2 the light client store.
- The node's custody group count: `NUMBER_OF_CUSTODY_GROUPS` with `NODE_FLAG_SUPERNODE` among `flags`, else `CUSTODY_REQUIREMENT` of `config`.
- The node's `columns`: each column of compute_columns_for_custody_group of each group of get_custody_groups(the anchor's `node_id`, max(`SAMPLES_PER_SLOT`, its custody group count)) of `config`: every column with `NODE_FLAG_SUPERNODE`.
- With `NODE_FLAG_BUILDER`, the node keeps the anchor's `builder_host`.
- With `NODE_FLAG_ENGINE`, the node keeps the anchor's `jwt_secret` and `engine_host`; its first JSON-RPC id is 1, and it takes `NODE_FLAG_FCU`, so the anchor's head goes to the engine first.

### Caller must

- Keep the anchor state as `BufferId` 1, and the light client store as `BufferId` 2: an `LcStore` of lantern_lc_store_init (light-client.md) of the anchor state and its block, with capacities of the caller's choice.
- Make the store with lantern_get_forkchoice_store of the same anchor.

## Function `lantern_node_copy`

The node in a new buffer with the capacities of a `NodeRoom`.

### Signature

```
lantern_node_copy(node, room, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | `Node` |
| `room` | input | `NodeRoom` |
| `out` | output | `Node`, its `size` set |

### Returns

- `LANTERN_OK`: `out` holds the node.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is smaller than lantern_node_size of `room`, a capacity of `room` is below the entries of its part, or lantern_db_copy of the `Db` to `db_slots` and `db_roots` fails.
- `LANTERN_INVALID_OVERFLOW`: as lantern_node_size.

## Function `lantern_node_step`

Checks every event, then handles each in order, then sets the head.

### Signature

```
lantern_node_step(node, store, p2p, tick, events, scratch, actions, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | state | `Node` |
| `store` | state | `Store` |
| `p2p` | state | asm-libp2p `State`, or 0 for a node with no network |
| `tick` | input | asm-libp2p `Tick`, with `p2p` |
| `events` | input | `NodeEvents` |
| `scratch` | scratch | `Scratch` |
| `actions` | state | `NodeActions`: the step adds its actions after the ones there |
| `result` | output | `NodeStepResult` |

### Returns

- `LANTERN_OK`: the events up to `accepted` are handled and the actions added.
- `LANTERN_INVALID_EVENT`: an event breaks the rules of `NodeEvent`, or libp2p_step takes a libp2p event as invalid. Nothing is changed.
- `LANTERN_BUFFER_TOO_SMALL`: `actions`, a part of `node`, or `scratch` has too little room; `short` of `result` names it, and `room` of `result` names the part of `node`. Nothing else is changed.

### Caller must

- Do the actions in order before the next step.
- Pass the events after `accepted` again in the next step, before new ones.
- Step again by `wakeup`.
- On `LANTERN_BUFFER_TOO_SMALL`, grow the buffer that `short` names (the node with lantern_node_copy and more of the `NodeRoom` capacity that `room` names, or more room for `actions` or `scratch`), then call again with the same events.

### Function does

- Room: `actions` has the event bytes + 512 per event + `NODE_ACT_WORK_SIZE` per vote of each `NODE_EV_WORK_DONE` of a valid `NODE_WORK_IMPORT_BLOCK` (its `NodeEvent_index` + `NodeEvent_root` counts) + 384 per known block + 160 per `NodeBlob` entry + 32 per `NodeCheckpoint` entry + 2048 bytes free (the crossing of a fork boundary takes 208), with an engine_getPayload in flight the bytes `engine_in` holds + 1072 more (the `NODE_ACT_BYTES_PUT` of its result), and `LIBP2P_ACTIONS_MIN` + 40 more with `p2p`; with `p2p`, `p2p_out` has room for the libp2p events of the `NODE_EV_P2P` events, and `scratch` holds as many bytes again and `LIBP2P_SCRATCH_SIZE`; the blocks part has an entry free per `NODE_EV_BLOCK` and per `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP` or `NODE_WORK_PUBLISH_CHECK`, and `NODE_SYNC_BATCH` more with `p2p`; the blobs part has an entry free per `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP` or `NODE_WORK_PUBLISH_SIDECAR`, and with `p2p` `NODE_SYNC_BATCH` times the largest of `MAX_BLOBS_PER_BLOCK`, `MAX_BLOBS_PER_BLOCK_ELECTRA` and the count of `columns` more; the checkpoints part has 2 free per `NODE_EV_WORK_DONE`, and 2; the pow blocks part has an entry free per `NODE_EV_POW_BLOCK`; `engine_in` has room for the bytes of the `NODE_EV_ENGINE` events; `scratch` has `LANTERN_SCRATCH_FIXED` + 64 + 16 bytes per store node + 8 per `NodeBlock` entry, and `DISCV5_ENR_SIZE` + `DISCV5_ENR_SCRATCH` more with a `NODE_EV_ENR`, and `NODE_API_SCRATCH` (8192) + 4 bytes per byte of the `query` and 16 per byte of the `body` of the largest request more with a `NODE_EV_API`; `actions` has 2048 more, and 16 per byte of its `body`, per `NODE_EV_API`; the api part has an entry free per `NODE_EV_API`; `scratch` has `NODE_API_SCRATCH` more, and `actions` 2048 more, per `NODE_EV_WORK_DONE` of `NODE_WORK_API_LOOKUP`; `actions` has 1024 more per event for each `NodeApi` entry of eventstream, and 2 times `NODE_ACT_WORK_SIZE` more, and `NODE_ACT_WORK_SIZE` more for each pool entry; per `NODE_EV_WORK_DONE` of `NODE_WORK_API_SUBMIT`, `NODE_WORK_PUBLISH_CHECK` or `NODE_WORK_PUBLISH_SIDECAR`, `actions` has 2048 more and, of `LANTERN_VALID`, its bytes once more, and the api part an entry free; with `NODE_FLAG_SUBSCRIBED` and `p2p`, `p2p_out` has room for 2 times its bytes and 512 more per operation, and `scratch` the largest of `SNAPPY_SCRATCH_COMPRESS` + 192 + its bytes more; the pool part asks for no room: a full pool keeps no more operations, and those still go out.
- Before any change: the root of each `NODE_EV_BLOCK`, with lantern_node_block_root of the fork of its slot. A status of that call is the step's.
- On `LANTERN_BUFFER_TOO_SMALL`, `short`: `NODE_SHORT_ACTIONS` for the room of `actions`, and for `LIBP2P_BUFFER_TOO_SMALL` of libp2p_step (its scratch is the step's own); `NODE_SHORT_NODE` for a part of the node, with `room` the byte offset in `NodeRoom` of its capacity (`blocks`, `checkpoints`, `pow_blocks`, `p2p_out`, `blobs`, `engine_bytes` or `api_streams`); `NODE_SHORT_SCRATCH` for `scratch`, and for `LANTERN_BUFFER_TOO_SMALL` of lantern_node_block_root.
- The prune, after libp2p's first round and before the node's events, when the store's finalized epoch is above `pruned_epoch`: lantern_store_prune with the step's scratch; on its success `pruned_epoch` takes that epoch, and with F the block of the finalized root:
  - F, imported with no post-state, gets it again first (the rebuild below), while its ancestors keep theirs.
  - Each imported ancestor of F, by `parent_root`, gets a `NODE_ACT_STATE_FREE` of any post-state and `state_id` 0 (the base state stays, below); its bytes and sidecars stay, for the node serves the chain.
  - An imported block with a post-state, or above F's slot, and no node in the store is of another branch: a `NODE_ACT_STATE_FREE` of any post-state and a `NODE_ACT_BYTES_FREE`, and its entry is free.
  - A `NODE_BLOCK_INVALID`, `NODE_BLOCK_WAITING`, `NODE_BLOCK_BLOBS` or `NODE_BLOCK_PAYLOAD` block at or below F's slot: a `NODE_ACT_BYTES_FREE` of any bytes, and its entry is free.
  - A `NODE_BLOB_INVALID` entry is free; a `NODE_BLOB_VALID` entry at or below F's slot whose block is neither imported nor in `NODE_BLOCK_BACKFILL`: a `NODE_ACT_BYTES_FREE`, and its entry is free.
  - A `NodeCheckpoint` below the finalized epoch: a `NODE_ACT_STATE_FREE` of its state, except the base state; its entry is free.
  - Bytes that a stream in `NODE_STREAM_SERVE` or `NODE_STREAM_SERVING` lists at or after its `next` stay, with their entry, until a later prune.
  - With `NODE_FLAG_DB`, before the other blocks: the chain from F down to `db_next_slot`, by `parent_root`, then from its lowest slot up, each block with bytes goes to the `Db`, but one whose root the `Db` holds already (lantern_db_find_root), as after a restart, gets no record and only its sidecars' bytes and entries go: lantern_db_add of its `DbRecord` (kind `DB_BLOCK`, index 0) at the end of the segment of its slot and a `NODE_ACT_DB_APPEND`; then each `NODE_BLOB_VALID` sidecar of its root, by index from 0 to `DB_SIDECAR_INDICES` - 1 (kind `DB_COLUMN_SIDECAR` from fulu on, else `DB_BLOB_SIDECAR`), the same way in its sidecar segment, its bytes freed and its entry free; then, for F, a `NODE_ACT_DB_STATE` of its post-state, its bytes and its slot; then the block's bytes are freed and its entry is free, but F keeps its entry. `db_next_slot` takes each block's slot + 1. A record lantern_db_add refuses ends the archive of a block until a later prune; a sidecar it refuses stays for the prune.
  - With `NODE_FLAG_DB`, an ancestor of F, or a sidecar of one, below `db_next_slot` whose bytes stay goes as the other branches do.
  - The end of a block segment: `db_block_end` for `db_block_segment`, else `backfill_end` for `backfill_segment`, else 0 (a new segment). The archive's segment is `db_block_segment` and the backfill's `backfill_segment`; a record makes its writer's segment that of its slot, and each of the two ends whose segment it is takes the record's end. So the two writers of one segment append after each other. A sidecar segment the same way, with `db_sidecar_segment`, `db_sidecar_end`, `backfill_sidecar_segment` and `backfill_sidecar_end`.
- With `NODE_FLAG_DB`, after the backfill's blocks: the sidecars the node no longer serves go (deneb and fulu `p2p-interface.md`: a node serves the sidecars of the blob window and the column window; it may drop older ones). The drop slot: the first slot of the earlier of the blob window's and the column window's first epochs, at most the `Db`'s `end_slot`, rounded down to a multiple of `DB_SEGMENT_SLOTS`, and at most 16 segments above `sidecar_floor`. When it is above `sidecar_floor`: a `NODE_ACT_DB_DROP` of each sidecar segment from that of `sidecar_floor` below it, lantern_db_drop_sidecars of the `Db` to the drop slot, `sidecar_floor` takes it, and `db_sidecar_segment` and `backfill_sidecar_segment` below it take 2^64 - 1. A sidecar below `sidecar_floor` gets no record.
- With `NODE_FLAG_DB`, before any change: the `Db` has room for twice its blocks and the `NodeBlock` entries in its root table, with a store's finalized epoch above `pruned_epoch` for the slots up to the finalized epoch's first slot, and with `backfill_start` not 2^64 - 1 (a backfill request open or not weighed) for the slots below `backfill_slot`; else `LANTERN_BUFFER_TOO_SMALL` with `NODE_SHORT_NODE` and `room` the offset of `db_slots` or `db_roots`.
- A block whose parent is imported with no post-state is no descendant of the finalized block: it becomes `NODE_BLOCK_INVALID`, and its bytes are freed.
- `NODE_EV_TICK`: sets `time_ms` of the node, then on_tick of the fork of the new slot.
- `NODE_EV_BLOCK`: for a root the node does not know, a `NODE_ACT_BYTES_PUT` of the bytes and a `NodeBlock` in `NODE_BLOCK_WAITING`. Bytes that are no `SignedBeaconBlock` are dropped.
- After the head, the post-states the node can rebuild go: each imported block above F's slot with a post-state, other than the head and the justified root, with an imported child, gets a `NODE_ACT_STATE_FREE` and `state_id` 0, when its slot is not the first of its epoch, its slot + `NODE_STATE_KEEP_SLOTS` (4) is at most the store's slot, and every imported child is of its epoch; with `NODE_FLAG_FEW_STATES`, with no rule of slots or epochs. So the node keeps the post-states of the blocks a checkpoint names, of the last slots, and of the blocks with no child. Then a head with no post-state above F's slot gets it again.
- The rebuild of the post-state of an imported block above F's slot: its path, by `parent_root`, to the nearest ancestor with a post-state, each block of it with bytes, in a list at the end of `scratch` (8 bytes for each `NodeBlock` entry); a `NODE_ACT_STATE_COPY` of the ancestor's post-state; then for each block of the path from the ancestor's child, in slot order, the copy crosses the fork boundaries to its slot (as an import's copy does) and gets a `NODE_WORK_REPLAY` with the block's bytes; the block takes the copy as its post-state. A path the node cannot follow rebuilds nothing.
- The base state: the anchor's post-state, `anchor_state_id`, at `base_slot`, the anchor's slot. The node keeps it for its life: a `NODE_ACT_STATE_FREE` of it is no action.
- The replay (beacon-api.md, the state of a `state_id`): the post-state of a block B of the chain at or below F's slot and above `base_slot` with no post-state.
  - B the block of `replay_root` with `replay_state` not 0: a `NODE_ACT_STATE_COPY` of `replay_state`.
  - Else, with no replay in flight (`replay_copy` 0), one starts: a `NODE_ACT_STATE_FREE` of any `replay_state`, which takes 0; `replay_root` and `replay_slot` B's; a `NODE_ACT_STATE_COPY` of the base state as `replay_copy`, `replay_copy_slot` `base_slot`, `replay_next` `base_slot` + 1. The request waits (`API_STREAM_REPLAY`, below).
  - With one in flight for another block, the request waits too, and starts its own when it runs again.
- Each step, at the quiet point after the produce entries: a replay in flight queues the blocks of the chain with a slot from `replay_next` to `replay_slot`, in slot order, at most `NODE_REPLAY_CHUNK` (64) a step and while the actions have room for 1024 bytes more.
  - The blocks: with `NODE_FLAG_DB`, each slot below `db_next_slot` whose `DbSlot` has a block, its record's `NODE_DB_REF`; then the `NodeBlock` entries with bytes on the path from the block of `replay_root` by `parent_root`, from `replay_next`.
  - Each: the copy crosses the fork boundaries to its slot, then a `NODE_WORK_REPLAY` of the copy with its bytes; `replay_copy_slot` takes its slot and `replay_next` its slot + 1.
  - Once `replay_next` is past `replay_slot`: `replay_state` takes the copy and `replay_copy` 0. Then each `NodeApi` entry with `API_STREAM_REPLAY` runs again (below).
  - A block of the path the node does not hold (no `DbSlot` block and no `NodeBlock` with bytes at the next slot of the path): the replay ends, `replay_copy` freed and 0, `replay_root` zero; each waiting entry runs again with no replay: 404.
- A waiting block whose parent is imported: a `NODE_ACT_STATE_COPY` of the parent's post-state and a `NODE_WORK_IMPORT_BLOCK`; the block is `NODE_BLOCK_IMPORTING`. A parent with no post-state above F's slot gets it again first; one at or below F's slot is an ancestor of F, as below. When the fork of the block's slot is later than that of the parent's slot, the copy first crosses each fork boundary between them, and the import gets the last state.
- The crossing of a fork boundary by a state copy `a` of a fork to the next fork: a `NODE_WORK_SLOTS` of `a` to the next fork's first slot, when `a` is before it; a `NODE_ACT_STATE_COPY` of the copied state as `b`, a buffer for the upgrade; a `NODE_WORK_UPGRADE` of `a` into `b` with the next fork as `arg`; a `NODE_ACT_STATE_FREE` of `a`. Then `b` is the copy. The shell does the actions in order, so a work reads what the works before it wrote. A waiting block whose parent is invalid becomes `NODE_BLOCK_INVALID`.
- With `NODE_FLAG_ENGINE`, a waiting block of bellatrix or later whose parent is imported takes `NODE_BLOCK_PAYLOAD` instead, with `retry` 0: its import waits for the execution engine's answer.
- `NODE_EV_ATTESTATION`: a `NODE_ACT_BYTES_PUT` of the bytes and a `NODE_WORK_ATTESTATION` with the target checkpoint state, or 0 when the node has none.
- `NODE_EV_ATTESTER_SLASHING`: a `NODE_ACT_BYTES_PUT` of the bytes and a `NODE_WORK_ATTESTER_SLASHING` with the post-state of the justified root.
- The votes of an imported block (phase0 `fork-choice.md`: on_attestation and on_attester_slashing run whenever an attestation or an attester slashing is received, those of a block too): for each attestation of its body, by index, a `NODE_WORK_BLOCK_ATTESTATION` with the block's bytes and the index as `arg`; then for each attester slashing of its body, by index, a `NODE_WORK_BLOCK_SLASHING` with the block's bytes, the index as `arg` and the post-state of the justified root. The counts are those of the import's event: attestations at `NodeEvent_index`, attester slashings at `NodeEvent_root`. Each of these works adds 1 to `event_votes`, and its `NODE_EV_WORK_DONE` takes 1 off.
- `NODE_EV_WORK_DONE` of `NODE_WORK_BLOCK_ATTESTATION` with `LANTERN_NEED_TARGET_STATE`: the target checkpoint state, then the same work again with it. The block's bytes stay.
- `NODE_EV_POW_BLOCK`: adds the `PowBlock` to the node.
- `NODE_EV_WORK_DONE` of `NODE_WORK_IMPORT_BLOCK`: valid, the block is `NODE_BLOCK_IMPORTED`, a block event goes (the events, below), a `NODE_WORK_LC_BLOCK` of its post-state as `state_a`, its bytes as `data` and the light client store (`BufferId` 2) as `state_c` (light-client.md: lantern_lc_on_block at each import), its votes go to fork choice, and its waiting children are imported; `LANTERN_NEED_JUSTIFIED_STATE`, a `NODE_WORK_JUSTIFIED_STATE` and the same import again; else `NODE_BLOCK_INVALID` and a `NODE_ACT_STATE_FREE` of its state.
- `NODE_EV_WORK_DONE` of `NODE_WORK_ATTESTATION` with `LANTERN_NEED_TARGET_STATE`: the target checkpoint state, then the same attestation again with it.
- A checkpoint state the node does not have: a `NODE_ACT_STATE_COPY` of the post-state of the checkpoint's root, a `NodeCheckpoint`, and a `NODE_WORK_TARGET_STATE`. A root's block with no post-state above F's slot gets it again first. When the fork of the checkpoint epoch's first slot is later than that of the root's slot, the copy first crosses each fork boundary between them, and the `NodeCheckpoint` and the work get the last state.
- An attestation or slashing done: a `NODE_ACT_BYTES_FREE` of its bytes.
- The head: get_head of the fork of the store's slot into `head_root`, or a `NODE_WORK_JUSTIFIED_STATE` when it returns `LANTERN_NEED_JUSTIFIED_STATE`.
- The events (beacon-api.md, eventstream), each to the `NodeApi` entries of eventstream whose topics have its bit (`API_TOPIC_*`):
  - block: at the import of a block, its text: the block's slot and root, `execution_optimistic` from its `payload_status`.
  - head and finalized_checkpoint at a quiet point: after the head, once the head's post-state is back (the rule of the post-states the node lets go, above), with `event_votes` 0, so that the votes of each block the node imports are in fork choice first.
  - chain_reorg: at a quiet point, when `head_root` is not `event_head`, before the head event, with an entry of the topic: the walk of the two chains by `parent_root` among the node's `NodeBlock` entries, from the old head (`event_head`) and the new head, the one at the higher slot first, to their common block. With the old head that common block, at a slot below the new head's, no event. Else a `NODE_WORK_API_EVENT` with the new head's post-state as `state_a`, the old head's block bytes as `data`, and as `arg` `API_TOPIC_CHAIN_REORG` + 2^8 times the values (2 `execution_optimistic`) + 2^16 times the depth (beacon-api.md): the old head's slot less the lowest of the two heads' slots, the slot before the old chain's first block after the common block, and the slot before the new chain's. An old head the node no longer holds, or whose walk does not meet the new head's, gives no event.
  - The light client data first: at a quiet point, when `head_root` is not `event_head`, before the head event, a `NODE_WORK_LC_HEAD` with the light client store as `state_c` (light-client.md: lantern_lc_on_head at each new head, with the store's finalized checkpoint).
  - head: at a quiet point, when `head_root` is not `event_head`: `event_head` and `event_slot` take the head's root and slot; with an entry of the topic, a `NODE_WORK_API_EVENT` with the head's post-state as `state_a` and as `arg` `API_TOPIC_HEAD` + 2^8 times the values: 1 `epoch_transition` (the epoch of the head's slot above that of the old `event_slot`), 2 `execution_optimistic`.
  - finalized_checkpoint: then, when the store's finalized epoch is above `event_epoch`: `event_epoch` takes it; with an entry of the topic, a `NODE_WORK_API_EVENT` with the bytes of the finalized root's block as `data` (its `NODE_DB_REF` when the `Db` holds them), else its post-state as `state_a`, and as `arg` `API_TOPIC_FINALIZED_CHECKPOINT` + 2^8 times the values (2 `execution_optimistic`) + 2^16 times the epoch. A block with neither gives no event.
  - light_client_finality_update and light_client_optimistic_update: when the node publishes or forwards an update on the gossip topic of the same name (the light client gossip, below), with an entry of the topic a `NODE_WORK_API_EVENT` with the light client store as `state_c` and as `arg` the topic.
  - block_gossip: at the `NODE_EV_WORK_DONE` of a `NODE_WORK_GOSSIP` of `LANTERN_VALID` of beacon_block, its text from the root at `NodeEvent_root` and the message's slot; at the `NODE_EV_WORK_DONE` of a `NODE_WORK_PUBLISH_CHECK` of `LANTERN_VALID`, from the entry's root and slot. Each written as the block event's, with an entry of the topic.
  - blob_sidecar and data_column_sidecar: at the `NODE_EV_WORK_DONE` of a `NODE_WORK_GOSSIP` of `LANTERN_VALID` of blob_sidecar or data_column_sidecar, as for the operation topics (below); at the `NODE_EV_WORK_DONE` of a valid `NODE_WORK_PUBLISH_SIDECAR`, with an entry of the topic of the entry's fork (blob_sidecar before fulu, data_column_sidecar from fulu): a `NODE_WORK_API_EVENT` of the sidecar's bytes as for the operation topics, those of its new `NodeBlob` when the node keeps it, else a `NODE_ACT_BYTES_PUT` of them to a new id before the work and a `NODE_ACT_BYTES_FREE` of it after.
  - The operation topics: at the `NODE_EV_WORK_DONE` of a `NODE_WORK_GOSSIP` of `LANTERN_VALID`, and for each `LANTERN_VALID` record of a `NODE_WORK_API_SUBMIT`, of the gossip topic voluntary_exit, bls_to_execution_change, proposer_slashing, attester_slashing, beacon_attestation or sync_committee_contribution_and_proof (and, from the network only, blob_sidecar and data_column_sidecar): with an entry of its event topic (beacon_attestation: `API_TOPIC_ATTESTATION` before electra, `API_TOPIC_SINGLE_ATTESTATION` from electra, by the fork of the validation), a `NODE_WORK_API_EVENT` with its bytes as `data` and as `arg` the event topic + 2^16 times the fork of the validation. It goes before any `NODE_ACT_BYTES_FREE` of those bytes: the shell runs it first.
  - `NODE_EV_WORK_DONE` of `NODE_WORK_API_EVENT`: `LANTERN_VALID`, the text at `NodeEvent_chunk` goes to the entries of the topic of `arg` % 2^8. Another result: no event.
  - To an entry: a `NODE_ACT_API_SEND` of the text with `last` 0, in one chunk of RFC 9112 section 7.1 with `API_STREAM_CHUNKED`; its `sent` grows by the bytes sent. When `sent` would pass `NODE_API_CHUNK`, the stream falls behind: a `NODE_ACT_API_CLOSE` of the connection in its place, and the stream ends.
- libp2p first, before the node's events: libp2p_step with the queued events, then the `NODE_EV_P2P` events, after them in the queue. The first libp2p_step takes at most half the action room left, when that half is enough, so the notices have room. When it accepts k of n P2P events, with k < n, the P2P events it did not take leave the queue, the step handles the node's events before the next P2P event, and gives that count as `accepted`. A status of libp2p_step leaves the queue as it was.
- `PEER_CONNECTED`: a `NodePeer` with the notice's handle, direction, peer ID, address and transport, or a `DISCONNECT` when the peers part is full. `PEER_DISCONNECTED`: the peer and its streams go.
- `PEER_CONNECTED` and `DIAL_FAILED` of a tag with `NODE_DIAL_TAG`: `dialing` takes 1 less. A `PEER_CONNECTED` of `LIBP2P_OUTBOUND` that gets a `NodePeer`: a Status request (v2 from fulu, v1 before) with the node's Status, as a request of the node.
- `NODE_EV_ENR`, with `p2p`: the record of discv5_enr_decode, with an `ip`, a `tcp` pair of 1 or 2 bytes, an `eth2` pair whose first 4 bytes are compute_fork_digest of the store's epoch, and a `secp256k1` key whose peer ID (the identity multihash of the protobuf secp256k1 public key) no `NodePeer` has, gets a `DIAL` over TCP to that address with that peer ID and a tag with `NODE_DIAL_TAG`, when `dialing` + the peers are below the capacity of the peers part and `p2p_out` has room; `dialing` takes 1 more. Another record changes nothing.
- With `NODE_FLAG_DISCV5`, at each subscription to a new `fork_digest`: a `NODE_ACT_DISCV5` of `SET_ENTRY` events: `eth2`, lantern_compute_enr_fork_id at the store's epoch; `attnets`, the bits of `attnets` (bit i of byte i / 8 for subnet i); from altair `syncnets`, 1 zero byte; from fulu `cgc`, the node's custody group count in big-endian bytes with no leading zero, and `nfd`, lantern_compute_next_fork_digest.
- With `NODE_FLAG_DISCV5`, after the head: when `dialing` + the peers are below the capacity of the peers part, and `time_ms` is at least `lookup_ms` + `NODE_LOOKUP_MS` or `lookup_ms` is 0, a `NODE_ACT_DISCV5` of a `LOOKUP` event whose target is the tick's 32 entropy bytes; `lookup_ms` takes `time_ms`.
- `STREAM_INBOUND`: a `NodeStream` of the protocol's method and version, or a `STREAM_RESET` when the streams part is full. `STREAM_DATA`: the bytes join the stream's request, or a `STREAM_RESET` when they pass its room. `STREAM_EOF`: the request is complete. `STREAM_RESET`: the stream goes.
- A Status the node reads, of a request or a response, is kept in the `NodePeer`; then the peer gets a `DISCONNECT` and loses `NODE_PEER_STATUS` when its `fork_digest` is not compute_fork_digest of the store's epoch, `next_digest` or `old_digest`, or when its finalized epoch is not `GENESIS_EPOCH`, is at most the store's finalized epoch, and its finalized root is not the store's finalized root (the same epoch) or the root of the `Db`'s last block at or before the epoch's first slot (an earlier epoch, when the `Db` holds one).
- A request is read when its bytes are complete: Status is kept in the `NodePeer` and answered with the node's Status of the same version; Ping is answered with `metadata_seq`; MetaData, on the stream's opening, with the node's MetaData of the same version; Goodbye gets a `STREAM_CLOSE`. A request that is not valid gets result 1, InvalidRequest; a method of no answer below gets result 3, ResourceUnavailable.
- BeaconBlocksByRange: a `start_slot` before the lower of `earliest_slot` and `backfill_slot` gets ResourceUnavailable. Otherwise, in slot order, the blocks of the `Db` with a slot in `start_slot` to `start_slot` + `count` below `db_next_slot`, as `NODE_DB_REF`s, then the blocks of the chain of `head_root`, by `parent_root`, with a slot from `db_next_slot` in that range; `count` is at most `MAX_REQUEST_BLOCKS_DENEB` from deneb on, else `MAX_REQUEST_BLOCKS`, and at most the BufferIds a stream's request room holds.
- BeaconBlocksByRoot: the imported blocks of the roots the node knows, or else the `Db`'s blocks of those roots (lantern_db_find_root), in the request's order; the request has at most that many roots.
- The light client methods (altair light-client `p2p-interface.md`, The Req/Resp domain), served from the light client store: GetLightClientBootstrap, a request of 32 bytes (the block root); LightClientUpdatesByRange, a request of 16 bytes (`start_period`, `count`); GetLightClientFinalityUpdate and GetLightClientOptimisticUpdate, with no request bytes. Each: a `NODE_ACT_BYTES_PUT` of the request's bytes to a new id (none with no bytes), and a `NODE_WORK_LC_SERVE` of that id as `data`, the light client store as `state_c`, the stream's handle as `target` and the method as `arg`; the stream takes `NODE_STREAM_SERVING`.
- `NODE_EV_WORK_DONE` of `NODE_WORK_LC_SERVE`: a `NODE_ACT_BYTES_FREE` of its `data`; `LANTERN_VALID`, the bytes at `NodeEvent_chunk` go out in a `STREAM_WRITE` and a `STREAM_CLOSE`, else a `STREAM_RESET`, or nothing with no room in `p2p_out`; then the stream goes.
- The light client gossip (altair light-client `p2p-interface.md`, The gossip domain): the topics light_client_finality_update and light_client_optimistic_update, from altair (the topics of a fork, below).
  - New for its topic: an update of finalized slot F, attested slot A and supermajority S (the fields of `NODE_WORK_LC_HEAD`) is new for light_client_finality_update when F is above `lc_finality_slot`, or equal with S 1 and `lc_finality_super` 0; new for light_client_optimistic_update when A is above `lc_optimistic_slot`. These are the IGNORE checks of the slots of each topic: the fields hold the last update the node published or forwarded.
  - Due: an update may go on gossip from genesis time + its signature slot times `SLOT_DURATION_MS` + get_sync_message_due_ms() (`SYNC_MESSAGE_DUE_BPS` times `SLOT_DURATION_MS` / `BASIS_POINTS`), the IGNORE check of the time of each topic.
  - `NODE_EV_WORK_DONE` of `NODE_WORK_LC_HEAD` of `LANTERN_VALID` with a latest update (`NodeEvent_root` + 16 is 1): the bit of each topic it is new for joins `lc_pending` (1 finality, 2 optimistic), and `lc_due` becomes its due time.
  - After the head, when `lc_pending` is not 0, `time_ms` is at least `lc_due`, and the actions have room for two works and 4096 bytes: a `NODE_WORK_LC_PUBLISH` for each bit, with the light client store as `state_c` and the topic as `arg`; `lc_pending` becomes 0.
  - `NODE_EV_WORK_DONE` of `NODE_WORK_LC_PUBLISH` of `LANTERN_VALID`, of an update new for its topic: it sets the topic's fields; with `NODE_FLAG_SUBSCRIBED` the publish of its bytes at `NodeEvent_chunk` on the topic; its event (The events).
  - `NODE_EV_WORK_DONE` of `NODE_WORK_LC_GOSSIP`: `LANTERN_VALID` of an update new for its topic, with `time_ms` + `MAXIMUM_GOSSIP_CLOCK_DISPARITY` at least its due time: a `VALIDATION` of `LIBP2P_ACCEPT`; it sets the topic's fields; its event. Else a `VALIDATION` of `LIBP2P_IGNORE`. Then a `NODE_ACT_BYTES_FREE` of its `data`, and the message's entry goes.
- BeaconBlocksByHead, when the fork of the store's slot is fulu or later; before it, ResourceUnavailable. A request of 40 bytes: `beacon_root`, `count`. The ancestry of `beacon_root`, from its block, in descending slot order: the node's imported blocks with bytes, by `parent_root`; from the first block the node keeps with no bytes, or the first root it does not keep, the `Db`'s blocks from that root's slot (lantern_db_find_root) down. At most `count`, the limit of BeaconBlocksByRange and the BufferIds a stream's request room holds; the walk stops at a block before the first slot of the epoch max(0, the store's epoch - compute_min_epochs_for_block_requests), the range a node must serve. A root of no imported block and none in the `Db`: no block.
- BlobSidecarsByRange and BlobSidecarsByRoot, when the fork of the store's slot is deneb or later; before it, ResourceUnavailable. The sidecar limit is `MAX_REQUEST_BLOCKS_DENEB` times `MAX_BLOBS_PER_BLOCK` (deneb) or `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra and later), and at most the BufferIds a stream's request room holds.
- BlobSidecarsByRange: a `start_slot` before `earliest_slot` gets ResourceUnavailable. Otherwise the `Db`'s sidecars of the slots in `start_slot` to `start_slot` + `count` below `db_next_slot`, then the `NODE_BLOB_VALID` sidecars of the imported blocks of the chain of `head_root` with a slot from `db_next_slot` in that range, whose fork is deneb or electra, in (slot, index) order, up to the limit; the indices of a block are those below the larger of `MAX_BLOBS_PER_BLOCK` and `MAX_BLOBS_PER_BLOCK_ELECTRA`, and below `NODE_BLOB_MAX`.
- BlobSidecarsByRoot: the `NODE_BLOB_VALID` sidecars of the request's (block_root, index) pairs whose block is not `NODE_BLOCK_INVALID`, or else the `Db`'s sidecars of those, whose slot's fork is deneb or electra, in the request's order; the request has at most the limit of pairs, a multiple of 40 bytes.
- DataColumnSidecarsByRange and DataColumnSidecarsByRoot, when the fork of the store's slot is fulu or later; before it, ResourceUnavailable. The sidecar limit is compute_max_request_data_column_sidecars, and at most the BufferIds a stream's request room holds. A request with a column at or above `NUMBER_OF_COLUMNS` is not valid.
- DataColumnSidecarsByRange: a request of 20 bytes and 8 bytes for each column, at most `NUMBER_OF_COLUMNS`, with the offset 20. A `start_slot` before `earliest_slot` gets ResourceUnavailable. Otherwise the `Db`'s sidecars of the slots in `start_slot` to `start_slot` + `count` below `db_next_slot`, then the `NODE_BLOB_VALID` sidecars of the imported blocks of the chain of `head_root` with a slot from `db_next_slot` in that range, whose fork is fulu or later, of the request's columns that `columns` holds, in (slot, index) order, up to the limit.
- DataColumnSidecarsByRoot: a `DataColumnsByRootIdentifiers` of at most `MAX_REQUEST_BLOCKS_DENEB` identifiers, each of 36 bytes and 8 bytes for each column, at most `NUMBER_OF_COLUMNS`, with the offset 36, and of at most the limit of columns in all. For each identifier in order, and each of its columns in order, the `NODE_BLOB_VALID` sidecar of its `block_root` and that index whose block is not `NODE_BLOCK_INVALID`, or else the `Db`'s sidecar of those, whose slot's fork is fulu or later.
- The anchor, with no bytes, is not sent. No block or sidecar: a `STREAM_CLOSE` with no chunk. Else the stream keeps the BufferIds and takes `NODE_STREAM_SERVE`.
- After the head, each `NodeMessage` in `NODE_MESSAGE_VOTE` whose slot is below the store's slot gets a `NODE_WORK_GOSSIP_VOTE` with its bytes and its handle as `target`, and takes `NODE_MESSAGE_VOTING`, while the actions have room for the work and 4096 bytes; an entry left waiting makes `wakeup` the tick's time.
- `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP_VOTE`: `LANTERN_NEED_TARGET_STATE`, the target checkpoint state, then the same work again; `LANTERN_INVALID_FUTURE_SLOT`, the entry takes `NODE_MESSAGE_VOTE` again; else the entry and its bytes go. With no entry of its handle (a later status took it, with its bytes), nothing.
- After the head, each stream in `NODE_STREAM_SERVE` gets a `NODE_WORK_SERVE` of its next block or sidecar, with the protocol version + 256 times the method as `arg`, and takes `NODE_STREAM_SERVING`, while the actions have room for the work and 4096 bytes; a stream left waiting makes `wakeup` the tick's time.
- `NODE_EV_WORK_DONE` of `NODE_WORK_SERVE`: the chunk goes out in a `STREAM_WRITE`, then the stream's next block, or a `STREAM_CLOSE` after the last; a result other than `LANTERN_VALID`, or no room in `p2p_out`, gives a `STREAM_RESET`.
- An answer is one chunk of lantern_reqresp_write_chunk in a `STREAM_WRITE`, then a `STREAM_CLOSE`; then the stream goes.
- The node's Status: compute_fork_digest of the store's epoch, the store's finalized checkpoint (with a zero root when its epoch is `GENESIS_EPOCH`: p2p-interface.md, "defaults to `Root(b'\x00' * 32)` for the genesis finalized checkpoint"), `head_root` and its slot, and `earliest_slot`. Its MetaData: `metadata_seq`, the subnets of `attnets`, the sync subnets of `syncnets`, and the node's custody group count: `NUMBER_OF_CUSTODY_GROUPS` with `NODE_FLAG_SUPERNODE`, else `CUSTODY_REQUIREMENT`.
- After the head, with `p2p`, one change a step, when `p2p_out` has 8192 bytes free (altair `p2p-interface.md`, Transitioning the gossip: a node SHOULD subscribe to the post-fork topics in advance of the fork, and SHOULD unsubscribe from the pre-fork topics two epochs after it):
  - When compute_fork_digest of the store's epoch is not `fork_digest`: it becomes `fork_digest`, `attnets` the subnets of the store's epoch (below) and `subnets` the subnets the node keeps (below), then the record entries below; a `SUBSCRIBE` of each topic of the fork of that epoch at that digest, unless it is `next_digest`, whose topics are there; `next_digest` becomes 0. A `fork_digest` before it becomes `old_digest`, with the fork of the epoch before as `old_fork` and the store's epoch + `NODE_SUBSCRIBE_AHEAD` (2) as `old_epoch`.
  - Else, when compute_fork_digest of the store's epoch + `NODE_SUBSCRIBE_AHEAD` is neither `fork_digest` nor `next_digest`: it becomes `next_digest`, with a `SUBSCRIBE` of each topic of the fork of that epoch at that digest.
  - Else, when the subnets of the store's epoch are not `attnets`: `attnets` takes them, with the record entries below.
  - Else, when the subnets the node keeps are not `subnets`: an `UNSUBSCRIBE` of beacon_attestation of each subnet of `subnets` not among them and a `SUBSCRIBE` of each new one, at `fork_digest` and at `next_digest` when it is not 0; `subnets` takes them. The subnets the node keeps: those of `attnets`, and each i whose `subnet_until[i]` is above the store's slot (an aggregator's subscription, beacon-api.md, prepareBeaconCommitteeSubnet).
  - Else, from altair, when the sync subnets the node keeps are not `syncnets`: the same events of sync_committee; `syncnets` takes them, `metadata_seq` grows by 1, with the record entries below. The sync subnets the node keeps: each i whose `sync_until[i]` is above the store's epoch (beacon-api.md, prepareSyncCommitteeSubnets; altair p2p-interface.md, MetaData: `syncnets` the sync subnets the node is subscribed to).
  - The subnets of an epoch: those of lantern_compute_subscribed_subnet(the node ID, the epoch, index) for each index below `SUBNETS_PER_NODE` (phase0 `p2p-interface.md`, Attestation subnet subscription: a beacon node should stay subscribed to `SUBNETS_PER_NODE` subnets, chosen from its node ID, for `EPOCHS_PER_SUBNET_SUBSCRIPTION` epochs, and set their bits in its record's `attnets`). Each change of `attnets` adds 1 to `metadata_seq` (MetaData: `seq_number` grows when `attnets` changes).
  - Else, from `old_epoch` on, an `UNSUBSCRIBE` of each topic of `old_fork` at `old_digest`, which becomes 0.
  - The topics of a fork: beacon_block, beacon_aggregate_and_proof, beacon_attestation of each subnet of `subnets`, voluntary_exit, proposer_slashing and attester_slashing; from altair sync_committee_contribution_and_proof, sync_committee of each subnet of `syncnets`, light_client_finality_update and light_client_optimistic_update; from capella bls_to_execution_change; in deneb and electra blob_sidecar of each subnet; from fulu data_column_sidecar of compute_subnet_for_data_column_sidecar of each column of `columns`, once for each subnet.
- `MESSAGE`: a `MESSAGE_ID` of compute_message_id of the fork of the store's slot, then a `NodeMessage` when the messages part has room. Its data uncompressed with Snappy goes in a `NODE_ACT_BYTES_PUT`, and for a block, a blob sidecar or a column sidecar the slot and parent root of its block header go in the entry; for a beacon_aggregate_and_proof the slot of its aggregate's data, by the offsets of its bytes (the message's at byte 0, the aggregate's at byte 8 of the message, the slot at byte 4 of the aggregate), or 2^64 - 1 when the bytes do not hold one. Data that is no Snappy block of at most `MAX_PAYLOAD_SIZE` bytes makes the entry `NODE_MESSAGE_CORRUPT`; data that does not fit in `scratch` or the actions makes it `NODE_MESSAGE_NO_ROOM`. A topic whose ForkDigest is not `fork_digest` makes it `NODE_MESSAGE_OTHER_DIGEST`, its data unread, for an IGNORE (altair `p2p-interface.md`, Transitioning the gossip: after a fork, peers on the pre-fork topics MUST NOT be scored down; before it, messages on the post-fork topics can be IGNORED); a topic of no name counts as of `fork_digest`.
- The builder calls (builder-specs v0.6.1, the Builder API), with `NODE_FLAG_BUILDER`: each call takes a free entry of `builder_calls` (`NODE_BUILDER_CALLS`, 4), its kind, the `NodeApi` entry it answers (2^64 - 1 for none) and `time_ms`, and goes out in a `NODE_ACT_BUILDER` of the entry's index; with no free entry, no call. Its request: HTTP/1.1 to `builder_host`, with `Host`, `Accept: application/json`, `Connection: close`, and with a body `Content-Type: application/json` and `Content-Length`.
  - `NODE_BUILDER_REGISTER` (1): registerValidator, `POST /eth/v1/builder/validators`, the body a JSON array of `SignedValidatorRegistrationV1`.
  - `NODE_BUILDER_HEADER` (2): getHeader of a produceBlockV3 entry (block production, below), `GET /eth/v1/builder/header/<slot>/<parent_hash>/<pubkey>`, the slot in decimal, the hash and the key `0x` and lower case hex; no body.
  - `NODE_BUILDER_SUBMIT` (3): submitBlindedBlockV2 of a publishBlindedBlockV2 entry (blinded block publishing, below), `POST /eth/v2/builder/blinded_blocks`, with `Eth-Consensus-Version: <fork>` after `Connection`, the body the block's JSON.
  - `NODE_EV_BUILDER` of a call: the entry goes free. Of `NODE_BUILDER_REGISTER`: nothing more (the API answer went before). Of `NODE_BUILDER_HEADER` and `NODE_BUILDER_SUBMIT`: to its entry (below), when it still waits for the call.
- `MESSAGE_STATUS` of `LIBP2P_MSG_NEW` for an entry of light_client_finality_update or light_client_optimistic_update with bytes: a `NODE_WORK_LC_GOSSIP` of its bytes as `data`, with the light client store as `state_c`, its handle as `target` and the topic as `arg`; the entry takes `NODE_MESSAGE_VALIDATING`.
- `MESSAGE_STATUS` of `LIBP2P_MSG_NEW` for an entry of another topic with bytes: a `NODE_WORK_GOSSIP` with the head's post-state, the post-state of the justified root, and for a block, a blob sidecar or a column sidecar whose parent is imported at an earlier slot of the same fork a `NODE_ACT_STATE_COPY` of its post-state, which a parent above F's slot with none gets again first; the entry takes `NODE_MESSAGE_VALIDATING`. With no bytes, or no room in the actions, a `VALIDATION` of `LIBP2P_IGNORE`, or `LIBP2P_REJECT` for `NODE_MESSAGE_CORRUPT`. Any other status: the bytes and the entry go.
- After the subscriptions and the serving, with `p2p`: the response bytes of each stream in `NODE_STREAM_RESPONSE` are read. Then, when the fork of the store's slot is fulu or later, each peer whose Status the node read and that has neither `NODE_PEER_METADATA` nor `NODE_PEER_METADATA_ASKED` gets a GetMetaData v3 request, as a request of the node with no request bytes, while the streams part has room for it and two more entries, and takes `NODE_PEER_METADATA_ASKED`. Then, with no `NODE_FLAG_SYNCING`, a BeaconBlocksByRange (v2 from altair, v1 before) to the first peer with a Status of the node's `fork_digest` whose `head_slot` is at least the start slot, and when the fork of the store's slot is fulu or later with `NODE_PEER_METADATA`: the start slot is the head's slot + 1, or `sync_slot` when that is higher; the count is at most `NODE_SYNC_BATCH` and reaches the peer's `head_slot`; the step is 1. The node takes `NODE_FLAG_SYNCING`, and `sync_slot` becomes the start slot + the count. A response that waits for room makes `wakeup` the tick's time.
- With no `NODE_FLAG_SYNCING` and no peer for that request, when the store's slot is above the start slot and `time_ms` is at least `status_ms` + `NODE_STATUS_MS` (12000), or `status_ms` is 0: a Status request (v2 from fulu, v1 before) with the node's Status to the first peer with a Status of the node's `fork_digest`, as a request of the node, when the streams part has room for it; `status_ms` takes `time_ms`. The answer is the peer's Status now, so the sync goes on as the chain grows: a peer sends its Status at connection, and then only when it chooses.
- Backfill (phase0 `p2p-interface.md`, BeaconBlocksByRange: a node that starts from a weak subjectivity checkpoint MUST backfill its blocks to epoch `current_epoch` - compute_min_epochs_for_block_requests, checking the proposer signatures and that the blocks form a chain to the checkpoint's block). The backfill target: the first slot of the epoch max(0, the store's epoch - compute_min_epochs_for_block_requests).
- With `NODE_FLAG_DB` and `p2p`, after the sync's requests: when `backfill_handle` is 0, `backfill_start` is 2^64 - 1, `backfill_root` is not zero, `backfill_next` is above the backfill target, `time_ms` is at least `backfill_ms`, and the streams part has room for three entries: a BeaconBlocksByRange (v2 from altair, v1 before) as a request of the node, of the slots from max(the backfill target, `backfill_next` - `NODE_SYNC_BATCH`) below `backfill_next`, step 1, to the first peer with a Status of the node's `fork_digest` whose `earliest_slot` is at most the start slot, and from fulu with `NODE_PEER_METADATA`, in the order of the peers part and around from `backfill_peer`; with none, the first such peer of any `earliest_slot` (fulu `p2p-interface.md`, Status v2: a node that serves every block of the sidecar retention period but not every sidecar advertises the first slot of its sidecars); after the sidecar requests of the same range as the sync's below (deneb `p2p-interface.md`, BlobSidecarsByRange, and fulu, DataColumnSidecarsByRange: a node that starts from a weak subjectivity checkpoint MUST backfill its sidecars over their serve range; fulu `das-core.md`: those of all its custody groups); with no room for them, no request. `backfill_handle` takes the request's tag, `backfill_start` the start slot, `backfill_got` 0, and `backfill_peer` the peer's index. Each block chunk of its stream adds 1 to `backfill_got`.
- Before that request, when the streams part has room for two entries: a BlobSidecarsByRange v1 to the same peer of the slots of the range in the blob window whose fork is deneb or electra, when there are any. The blob window: the slots of the epochs from max(the store's epoch - `MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS`, `DENEB_FORK_EPOCH`) on. With no room for it, no request.
- Before that request, from fulu: a DataColumnSidecarsByRange v1 of the slots of the range in the column window whose fork is fulu or later, when there are any, to each peer with `NODE_PEER_METADATA` in the order of the peers part, of the columns of `columns` in its `custody` that no earlier peer of the range was asked for, in ascending order. A peer gets none when that list is empty. With no room in the streams part for these and the BeaconBlocksByRange, or a request the node cannot open, no further request goes in the step. The column window: the slots of the epochs from max(the store's epoch - `MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS`, `FULU_FORK_EPOCH`) on.
- A request of the node: a `NodeStream` in `NODE_STREAM_OPENING` whose list holds the request chunk, its `handle` a tag with bit 63 set, and an `OPEN_STREAM` of the protocol ID. `STREAM_OPENED` of the tag: the stream takes its handle and `NODE_STREAM_RESPONSE` (and `backfill_handle`, when it is the tag, takes the handle), its request goes in a `STREAM_WRITE` with a `STREAM_CLOSE`, and its list then holds the response. `STREAM_FAILED` of the tag: the stream goes.
- A response chunk is read when its bytes are complete, with a ForkDigest context for BeaconBlocksByRange v2. A Status is kept in the `NodePeer`, as a Status request is. A block of at least 184 and at most `MAX_PAYLOAD_SIZE` bytes, when the actions and the blocks part have room: a `NodeBlock` in `NODE_BLOCK_HASHING` with root 0, the slot and parent root of its bytes and `data_available` 1, a `NODE_ACT_BYTES_PUT` of its bytes, and a `NODE_WORK_SYNC_BLOCK` of its index. A blob sidecar, with a ForkDigest context, of the SSZ size of `BlobSidecar`, when the actions and the blobs part have room: a `NodeBlob` in `NODE_BLOB_VERIFYING` with block root 0, the index and slot of its bytes, a `NODE_ACT_BYTES_PUT` of its bytes, and a `NODE_WORK_BLOB` of its index. A column sidecar, with a ForkDigest context, whose size is within the SSZ size bounds of `DataColumnSidecar`, when the actions and the blobs part have room: a `NodeBlob` in `NODE_BLOB_VERIFYING` with block root 0, the index and slot of its bytes, a `NODE_ACT_BYTES_PUT` of its bytes, and a `NODE_WORK_BLOB` of its index with `arg` 1. A MetaData v3 of 25 bytes: the peer takes `NODE_PEER_METADATA`, and as `custody` the columns of the groups of get_custody_groups(its node ID, `custody_group_count`), when `custody_group_count` is at most `NUMBER_OF_CUSTODY_GROUPS` and its peer ID holds a secp256k1 key; else its `custody` is 0. The stream goes after a Status or MetaData chunk, after its last chunk and `STREAM_EOF`, after a chunk whose result is not 0, and with a `STREAM_RESET` after a chunk that is not valid. A stream of the node's BeaconBlocksByRange that goes ends `NODE_FLAG_SYNCING`, unless it is the stream of `backfill_handle`, which then takes 0. A block of that stream goes the same way, but in `NODE_BLOCK_BF_CHECKING` with a `NODE_WORK_BACKFILL` of its index whose `state_a` is the post-state of F, the block of the store's finalized root.
- A peer ID holds a secp256k1 key when it is 39 bytes: 0x00 0x25 0x08 0x02 0x12 0x21 and the 33-byte compressed key. The peer's node ID is then the node ID of that key, with crypto_secp256k1_decompress of asm-crypto; a key that does not decompress gives the peer no `custody`.
- `NODE_EV_WORK_DONE` of `NODE_WORK_SYNC_BLOCK` for a block in `NODE_BLOCK_HASHING`: `LANTERN_VALID` and a root the node does not know, the block takes the root and the blob count at `NodeEvent_index`, then waits for its blobs; else `NODE_BLOCK_INVALID` and a `NODE_ACT_BYTES_FREE` of its bytes.
- `NODE_EV_WORK_DONE` of `NODE_WORK_BACKFILL` for a block in `NODE_BLOCK_BF_CHECKING`: `LANTERN_VALID`, the block takes the root at `NodeEvent_root`, the blob count at `NodeEvent_index`, and `NODE_BLOCK_BACKFILL`; else `NODE_BLOCK_INVALID` and a `NODE_ACT_BYTES_FREE` of its bytes.
- With `NODE_FLAG_DB`, after the head: while a block in `NODE_BLOCK_BACKFILL` has the root `backfill_root` and a slot below `backfill_slot`, and has the blobs or columns it needs (as a block from the network does), its record goes to the `Db` as the archive's do (lantern_db_add of its `DbRecord` at the end of the segment of its slot, and a `NODE_ACT_DB_APPEND`), then each of its `NODE_BLOB_VALID` sidecars by index as the archive's, their bytes freed and their entries free; `backfill_slot` and `earliest_slot` take its slot, and `backfill_root` its `parent_root`; its bytes are freed and its entry is free. A block that waits for its sidecars ends this until the next step, as does a record lantern_db_add refuses. Then, when `backfill_handle` is 0, no block is in `NODE_BLOCK_BF_CHECKING`, no `NodeBlob` below `backfill_slot` is in `NODE_BLOB_VERIFYING`, and no BlobSidecarsByRange or DataColumnSidecarsByRange request of the node is open, each block left in `NODE_BLOCK_BACKFILL` goes the same way without a record: it is no block of the chain. And the last request is weighed, when `backfill_start` is not 2^64 - 1: with `backfill_slot` below `backfill_next` (blocks joined), `backfill_next` takes `backfill_slot`; else with `backfill_got` 0 and `backfill_start` above the backfill target (no block in the range: skipped slots, or a peer without them), `backfill_next` takes `backfill_start`; else `backfill_next` takes `backfill_slot`, `backfill_ms` `time_ms` + `NODE_STATUS_MS`, and `backfill_peer` 1 more. `backfill_start` takes 2^64 - 1.
- A block from the network (gossip or a response) needs blobs when its slot's fork is deneb or electra, its blob count is above 0 and at most the fork's `MAX_BLOBS_PER_BLOCK` (deneb) or `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra) and `NODE_BLOB_MAX`, and its slot is in the blob window. It has them when the node holds a `NODE_BLOB_VALID` entry of its root for each index below the count.
- A block from the network needs columns when its slot's fork is fulu or later, its blob count is above 0, and its slot is in the column window. It has them when the node holds a `NODE_BLOB_VALID` entry of its root for each column of `columns`.
- A block that waits for its blobs: in `NODE_BLOCK_BLOBS` while it needs blobs or columns it does not have; else `data_available` 1 and `NODE_BLOCK_WAITING`, then it imports as a `NODE_EV_BLOCK` does.
- `NODE_EV_WORK_DONE` of `NODE_WORK_BLOB` for an entry in `NODE_BLOB_VERIFYING`: `LANTERN_VALID`, no `NODE_BLOB_VALID` entry of the same root and index, and for a slot whose fork is fulu or later an index that is a column of `columns`, the entry takes the root at `NodeEvent_root` and `NODE_BLOB_VALID`; else `NODE_BLOB_INVALID` and a `NODE_ACT_BYTES_FREE` of its bytes.
- An entry that becomes `NODE_BLOB_VALID`: the block of its root in `NODE_BLOCK_BLOBS`, if there is one, waits for its blobs again.
- With `NODE_FLAG_ENGINE`, after the head: with no call in flight (`engine_method` 0) and the store's slot at least `engine_wait`, the first block in `NODE_BLOCK_PAYLOAD` whose `retry` is at most the store's slot gets a `NODE_WORK_NEW_PAYLOAD` with the id `engine_id`, takes `NODE_BLOCK_EXECUTING`, and is the call in flight; with none, when the preparation of a payload is due (below) and the head's post-state is held, the preparation; with none, and `NODE_FLAG_FCU`, a `NODE_WORK_FORKCHOICE` when the fork of the store's slot is bellatrix or later. Each call takes the next id.
- A `head_root` that changes with `NODE_FLAG_ENGINE` sets `NODE_FLAG_FCU`; a `NODE_WORK_FORKCHOICE` clears it.
- Payload preparation (bellatrix `validator.md`, ExecutionPayload: a proposer calls prepare_execution_payload as soon as its inputs are known, and again when one changes). With the store's slot S, the preparation of slot S + 1 is due when all of these hold:
  - The fork of S + 1 is bellatrix or later.
  - A `proposers` entry has `until_epoch` above the store's epoch.
  - The slot of the block of `head_root` is S, or `time_ms` is at least the start of slot S plus get_attestation_due_ms (phase0 `validator.md`): genesis_time * 1000 + S * `SLOT_DURATION_MS` + `SLOT_DURATION_MS` * `ATTESTATION_DUE_BPS` / 10000.
  - `payload_slot` is not S + 1, or `payload_root` is not `head_root`.
- The preparation: `payload_slot` takes S + 1, `payload_root` `head_root`, and `payload_status` `NODE_PAYLOAD_PREPARING`; a `NODE_ACT_STATE_COPY` of the head's post-state, the copy across the fork boundaries to S + 1 (the crossing), a `NODE_WORK_SLOTS` of the copy to S + 1 when it is below it, a `NODE_WORK_PREPARE_PAYLOAD` of the copy as `state_a` with the id `engine_id` as `arg` and, as `target`, 2 with an entry of eventstream of payload_attributes (+ 1 for a preparation of produceBlockV3, below), and a `NODE_ACT_STATE_FREE` of the copy. It is the call in flight, `engine_method` `ENGINE_METHOD_FORKCHOICE_UPDATED` with `engine_target` 1 (0 for a `NODE_WORK_FORKCHOICE`), and takes the next id.
- `NODE_EV_WORK_DONE` of `NODE_WORK_PREPARE_PAYLOAD`: `LANTERN_VALID`, with the text of a payload_attributes event after its request, the text goes to the entries of the topic (the events, below); its request goes out in a `NODE_ACT_ENGINE`, `NODE_FLAG_FCU` clears, `payload_proposer` takes `NodeEvent_index` and `payload_status` `NODE_PAYLOAD_SENT`. Another result ends the call with `payload_status` `NODE_PAYLOAD_NONE`; `payload_slot` and `payload_root` stay, so the same head is not prepared again.
- Block production (beacon-api.md, produceBlockV3): a `NodeApi` entry of `API_OP_PRODUCE_BLOCK_V3`, its `member` the phase, `slot` the block's slot, `state` its state, `data` its body draft, `filter_index` the engine's result; `cursor` keeps `randao_reveal` (96 bytes), `graffiti` (32 bytes), at byte 128 1 with `skip_randao_verification`, at byte 136 `builder_boost_factor` (100 without it), at byte 152 the index + 1 of its `NODE_BUILDER_HEADER` call while that is in flight (else 0), at byte 160 the id of the builder's answer or bid (else 0), and at byte 168 the fee recipient of the proposer's registration (20 bytes). The phases, in order:
  - `NODE_PRODUCE_STATE` (1): a `NODE_ACT_STATE_COPY` of the head's post-state, the copy across the fork boundaries to `slot` and a `NODE_WORK_SLOTS` of it to `slot` when it is below it (as a lookup does), then a `NODE_WORK_PRODUCE_CHECK` of the copy. With no head post-state: 500.
  - The check's event: the proposer at `NodeEvent_root` and at byte 8 of it 1 when the chain is healthy (lantern_node_produce_check).
  - `NODE_PRODUCE_PAYLOAD` (2), from bellatrix when the head's store node has a `block_hash` that is not zero. On the way in, with `NODE_FLAG_BUILDER`: a `NODE_BUILDER_HEADER` call for the entry, of `slot`, that `block_hash` and the `pubkey` of the proposer's `NodeProposer` entry, when `builder_boost_factor` is not 0, that entry has `registered` 1, the head's `NodeBlock` has a `payload_status` other than `PAYLOAD_STATUS_NOT_VALIDATED`, and the chain is healthy; the entry keeps the call and the registration's fee recipient. Then, with no engine call in flight, first of all engine calls: when `payload_status` is `NODE_PAYLOAD_READY` with `payload_slot` `slot` and `payload_root` `head_root`, a `NODE_WORK_GET_PAYLOAD` of `payload_id` with the id `engine_id`, the call `ENGINE_METHOD_GET_PAYLOAD` with `engine_target` the entry's index; else the preparation of `slot` (as above) with 1 in its work's `target`, which takes the fee recipient zero when the proposer has no `NodeProposer` entry. A preparation that ends with no `payloadId`: 500.
  - `NODE_PRODUCE_FOLD` (3): a `NODE_ACT_BYTES_NEW` of `ProduceDraft__size` bytes, the draft; then one `NODE_WORK_PRODUCE_FOLD` at a time for each kept pool entry, with the draft as `data` and the entry's bytes as `state_b`: each work adds the entry to the draft in place. The kinds in turn (proposer slashings, attester slashings, voluntary exits, BLS changes, attestations, sync committee messages), the entries of each in the pool's order; `cursor` keeps the kind's turn at byte 144 and `filter_slot` the next pool index.
  - While a work of the entry, or its engine_getPayload, is in flight, the entry has `API_STREAM_BUSY`; when it is done, `API_STREAM_BUSY` clears, and with `API_STREAM_GONE` the entry ends with its draft, engine result and state, and answers nothing.
  - `NODE_PRODUCE_BID` (5), after the last fold, while the header call is in flight: the entry waits, with no work.
    - `NODE_EV_BUILDER` of the call: its index + 1 at byte 152 becomes 0; without the failure bit and with room in the actions, a `NODE_ACT_BYTES_PUT` of the answer's bytes to a new id, at byte 160.
    - After the head, each entry in `NODE_PRODUCE_BID` with no work in flight: when its call is in flight and `time_ms` is at least the call's `time_ms` + `BUILDER_PROPOSAL_DELAY_TOLERANCE` (1000 ms), the call answers no entry (its `NodeApi` index 2^64 - 1) and byte 152 becomes 0; then, with no call in flight and room in the actions for two works and 4096 bytes, the entry goes on.
    - Going on: with an answer at byte 160, a `NODE_WORK_PRODUCE_BID` of the copy as `state_a` and the answer as `data`. Its result `LANTERN_OK`: the bid, the event's bytes, in a `NODE_ACT_BYTES_PUT` to a new id at byte 160; another result: 0 there. Then the answer's bytes go (`NODE_ACT_BYTES_FREE`). Then the build; with no answer, the build at once.
  - `NODE_PRODUCE_BUILD` (4): a `NODE_WORK_PRODUCE_BLOCK` of the copy as `state_a`, the draft as `data`, the engine's result as `state_b` and the bid at byte 160 as `state_c` (0 for none); its result's bytes become `data`, execution_payload_value goes to `root` and consensus_block_value to `filter_slot`, 1 at `NodeEvent_checkpoint` sets `API_STREAM_PRODUCE_BLINDED`, `cursor` becomes zero, and the entry answers them as getBlockV2 answers a block's bytes, with the headers and the JSON of beacon-api.md. The copy, the draft, the result and the bid then go (`NODE_ACT_STATE_FREE`, `NODE_ACT_BYTES_FREE`).
  - An entry that ends in another way loses the same ids; with its header call in flight, the call answers no entry.
- engine_getPayload answered: lantern_engine_json_decode of the `result` (`result_offset` and `result_length` in the body) as the fork's `ExecutionPayload` (bellatrix) or `GetPayloadResult`, its SSZ bytes in a `NODE_ACT_BYTES_PUT` as the entry's `filter_index`; the entry goes on to `NODE_PRODUCE_FOLD`. A failed call, or a result that does not decode: 500. The call ends.
- Block publishing (beacon-api.md, publishBlockV2): a `NodeApi` entry of `API_OP_PUBLISH_BLOCK_V2`, its `member` the phase, `fork` the fork of `consensus_version`, `cursor` the level of `broadcast_validation` at byte 0, the answer flags at byte 8 and the blob count at byte 16, `data` the body's bytes, `filter_slot` the block's bytes, `filter_index` the sidecars' buffer, `root` the block's root and `slot` its slot (each id 0 until it is made). While a work of it is in flight it has `API_STREAM_BUSY`. A closed connection ends it as a produceBlockV3's (above), its ids gone and no answer, before its check passes; once its check passes, the publish and the import go on and the entry ends with no answer. The phases, in order:
  - `NODE_PUBLISH_DECODE` (1): a `NODE_ACT_BYTES_PUT` of the request's body to a new id, the entry's `data`, and a `NODE_WORK_PUBLISH_DECODE` of it, `arg` the fork + 2^8 with an SSZ body. Its result but `LANTERN_VALID`: 400. Else the event's bytes, the `SignedBeaconBlock`, go in a `NODE_ACT_BYTES_PUT` to a new id, the entry's `filter_slot`; the entry takes `root` from `NodeEvent_root`, `slot` from `NodeEvent_index` and the blob count from `NodeEvent_checkpoint`. A slot of another fork than `fork`: 400. A root of a `NodeBlock` but `NODE_BLOCK_INVALID`: 200, and the entry ends with its ids.
  - `NODE_PUBLISH_SIDECARS` (2), from deneb with a blob count above 0: a `NODE_ACT_BYTES_NEW` of the room of the sidecars (deneb and electra the count times the SSZ size of `BlobSidecar`, each with a 24-byte ByteList header; fulu `NUMBER_OF_COLUMNS` column sidecars of the count), its id the entry's `filter_index`, and a `NODE_WORK_PUBLISH_SIDECARS` with the body as `data` and that id as `state_b`. Its result but `LANTERN_VALID`: 400.
  - `NODE_PUBLISH_CHECK` (3): with no post-state of the block's parent: 400. Else a `NODE_ACT_STATE_COPY` of that post-state, crossed to the block's slot as a lookup's (`NODE_WORK_SLOTS` when the parent is below the slot), and a `NODE_WORK_PUBLISH_CHECK` of the copy as `state_a`, the block's bytes as `data`, the sidecars as `state_b` (0 before deneb or with no blob), the head's post-state as `state_c`, and the level as `arg`; then the copy's `NODE_ACT_STATE_FREE`. Its result but `LANTERN_VALID`: 400.
  - `NODE_PUBLISH_IMPORT` (4): the check's event holds the block's bytes. With `NODE_FLAG_SUBSCRIBED`, the publish of them on beacon_block (below, the publish of SSZ bytes); then the block's bytes (`filter_slot`) become a `NodeBlock` of the root in `NODE_BLOCK_WAITING` with `data_available` 1, as a `NODE_EV_BLOCK`'s, and it may import. Then for each sidecar i in order, one at a time, a `NODE_WORK_PUBLISH_SIDECAR` of the sidecars as `state_b` with `arg` i: its event holds the sidecar's bytes, its block root at `NodeEvent_root`, its index at `NodeEvent_index` and its slot at `NodeEvent_checkpoint`; with `NODE_FLAG_SUBSCRIBED` they go out on the topic of its subnet, and a sidecar the node keeps (each blob sidecar; the column sidecars of `columns`) goes in a `NODE_ACT_BYTES_PUT` as a `NodeBlob` in `NODE_BLOB_VALID` of the root, index and slot. After the last, the body's bytes and the sidecars' buffer go. After the head, each entry in this phase with no work in flight looks for the `NodeBlock` of its root: `NODE_BLOCK_IMPORTED`, 200; `NODE_BLOCK_INVALID`, or none, 202; another status, it waits.
- Blinded block publishing (beacon-api.md, publishBlindedBlockV2): before bellatrix, an entry of publishBlockV2. From bellatrix, an entry of `API_OP_PUBLISH_BLOCK_V2` with 1 at byte 64 of `cursor` (its parent root is at bytes 32 to 64), through the phases above with these changes:
  - `NODE_PUBLISH_DECODE`: its work's `arg` has 2^9 for a blinded block; its bytes are a `SignedBlindedBeaconBlock`. No sidecars: the builder has the blobs.
  - `NODE_PUBLISH_CHECK`: its work's `arg` has 2^8 for a blinded block. Its result `LANTERN_VALID` gives the block's JSON in the event; without `NODE_FLAG_BUILDER`, 500.
  - `NODE_PUBLISH_SUBMIT` (5), in place of the import: a `NODE_BUILDER_SUBMIT` call of the entry, its index + 1 at byte 72 of `cursor`; with no free call or no room in the actions, 500. `NODE_EV_BUILDER` of the call: when the entry still waits for it, byte 72 becomes 0, and lantern_http_parse_response of the answer with `eof` 1 gives a status of 202: 200, else, or with the failure bit, 500. The block goes to no `NodeBlock`: the full block comes over gossip.
  - A closed connection ends the entry as a publishBlockV2's before its check passes; after, the call goes out and the entry ends with no answer. A close while the call is in flight ends the entry with its ids, and the call answers no entry (its `NodeApi` index 2^64 - 1).
- `NODE_EV_WORK_DONE` of `NODE_WORK_GET_PAYLOAD`: as of `NODE_WORK_FORKCHOICE`, its request goes out in a `NODE_ACT_ENGINE`; another result ends the call with 500 to the entry.
- `NODE_EV_WORK_DONE` of `NODE_WORK_NEW_PAYLOAD` or `NODE_WORK_FORKCHOICE`: `LANTERN_VALID`, its request goes out in a `NODE_ACT_ENGINE`. Another result ends the call; for engine_newPayload, `LANTERN_NO_PAYLOAD` imports the block with `PAYLOAD_STATUS_VALID`, and any other makes it `NODE_BLOCK_INVALID` with a `NODE_ACT_BYTES_FREE` of its bytes.
- `NODE_EV_ENGINE` with arg 0: its bytes join `engine_in`. When they hold a whole response of lantern_http_parse_response, the response leaves `engine_in` and lantern_engine_parse_response of the method in flight reads its body. A status other than 200, a body that is no answer of the method, a JSON-RPC error or another id is a failed call. arg 1: the call in flight failed, and `engine_in` empties.
- A failed engine_newPayload: the block takes `NODE_BLOCK_PAYLOAD` with `retry` the store's slot + 1 (optimistic-sync.md: no optimistic import, the block MAY be queued). A failed call makes `engine_wait` the store's slot + 1; a failed engine_forkchoiceUpdated sets `NODE_FLAG_FCU` again, and of a preparation makes `payload_slot` 0 and `payload_status` `NODE_PAYLOAD_NONE`. The call ends.
- engine_newPayload answered: `VALID`, the block is imported with `PAYLOAD_STATUS_VALID`. `SYNCING` or `ACCEPTED`, the block is imported with `PAYLOAD_STATUS_NOT_VALIDATED` when it is an optimistic candidate: its parent's `BlockNode.block_hash` is not zero, or its slot + `SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY` is at most the store's slot; else it takes `NODE_BLOCK_PAYLOAD` with `retry` the store's slot + 1. `INVALID` or `INVALID_BLOCK_HASH`, the block is `NODE_BLOCK_INVALID`, its bytes go, and `latestValidHash` applies from its parent. The call ends.
- engine_forkchoiceUpdated answered: of a preparation (`engine_target` 1), a `payloadId` sets `payload_id` and `payload_status` `NODE_PAYLOAD_READY`, and a null one `payload_status` `NODE_PAYLOAD_NONE`. `VALID`, lantern_store_payload_status of the head's node with `PAYLOAD_STATUS_VALID`; `INVALID` or `INVALID_BLOCK_HASH`, `latestValidHash` applies from the head, the head included. The call ends.
- `latestValidHash` applies from a block of the store: up the chain from it, by `parent_root`, each block whose `block_hash` is not `latestValidHash` gets lantern_store_payload_status with `PAYLOAD_STATUS_INVALIDATED`, until the block whose `block_hash` is `latestValidHash`. A zero hash stops at the first block whose `block_hash` is zero. With null, or a hash no block of the chain has, only the block in question (a block of the store) gets it.
- `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`: a `VALIDATION` of `LIBP2P_ACCEPT` for `LANTERN_VALID`, `LIBP2P_REJECT` for `LANTERN_GOSSIP_REJECT`, else `LIBP2P_IGNORE`; a `NODE_ACT_STATE_FREE` of the proposer state. A valid beacon_block of a root the node does not know keeps its bytes as a `NodeBlock` with the blob count at `NodeEvent_index`, which waits for its blobs. A valid blob_sidecar keeps its bytes as a `NodeBlob` in `NODE_BLOB_VALID` of the root at `NodeEvent_root`, the index at `NodeEvent_index` and the message's slot, when the node holds no `NODE_BLOB_VALID` entry of that root and index. A valid data_column_sidecar of a column of `columns` keeps its bytes as a `NodeBlob` in `NODE_BLOB_VALID` of the root at `NodeEvent_root`, the index at `NodeEvent_index` and the message's slot, when the node holds no `NODE_BLOB_VALID` entry of that root and index. A valid attester_slashing with a justified state keeps its bytes for a `NODE_WORK_ATTESTER_SLASHING` with that state. A valid voluntary_exit, proposer_slashing, attester_slashing or bls_to_execution_change keeps its bytes as a `NodePool` entry too (the pool, below), when the pool has an entry free. A valid beacon_attestation keeps its bytes as a `NodePool` entry with the slot, the committee index and the member at `NodeEvent_root`, when the pool has an entry free for it. A valid beacon_aggregate_and_proof keeps its bytes and its entry, in `NODE_MESSAGE_VOTE`, for fork choice from the slot after its aggregate's (phase0 `fork-choice.md`: an attestation affects the fork choice of later slots only), when the messages part has more than half its capacity free after it. Else the bytes go. The entry goes, but an entry kept for its vote.

- `NODE_EV_API` (beacon-api.md, Common rules): the answer to the request, in one `NODE_ACT_API_SEND` of its connection with `last` 1, then a `NODE_ACT_API_CLOSE` of it when the connection closes after the answer.
  - An `HttpRequest` with a `status`: the error of that status.
  - Else lantern_api_route of the request, its `ApiRoute` in `scratch`. `LANTERN_INVALID_ROUTE`: the error of its `status`.
  - getHealth, getNetworkIdentity, getNodeVersion, getSyncingStatus, getPeerCount, getPeers, getPeer, getGenesis, getForkSchedule and getDepositContract: the answer of the node, the store and the config.
  - getSpec, getDebugChainHeadsV2 and getDebugForkChoice: a `NODE_WORK_API_ENCODE` with no state and no `data`, the connection as `target`, and as `arg` the operation + 2^8 times the answer flags.
  - The block of a `block_id` and the state of a `state_id`, as beacon-api.md gives them: the walk of the chain by `parent_root` from the head's `NodeBlock`; below its lowest block, the `Db`'s `DbSlot` of a slot or lantern_db_find_root of a root; the bytes of a `Db` block a `NODE_DB_REF` of its record.
  - A state at a slot past its post-state's, or past its `NodeCheckpoint`'s: a `NODE_ACT_STATE_COPY` of it, the copy across the fork boundaries to the slot (the crossing), then a `NODE_WORK_SLOTS` of the copy to the slot when it is below it; after the copy's last use, a `NODE_ACT_STATE_FREE` of it.
  - getBlockRoot: the answer at once.
  - getBlockHeader, getStateRoot, getStateFork, getStateFinalityCheckpoints, getStateRandao, getEpochSyncCommittees and getProposerLookahead: a `NODE_WORK_API_ENCODE`, the connection as `target`, and as `arg` the operation + 2^8 times the answer flags (`API_ANSWER_CLOSE` 1, `API_ANSWER_HTTP10` 2) + 2^16 times the values (`API_VALUE_CANONICAL` 1, `API_VALUE_FINALIZED` 2, `API_VALUE_OPTIMISTIC` 4) + 2^24 times: for getBlockHeader the block's `NodeBlock` index + 1, or 0 for a block of the `Db`; for the others the state's slot. getBlockHeader: the block's bytes as `data`, or 0; with none, its post-state as `state_a`. The others: the state as `state_a`.
  - getBlockV2 and getStateV2: a stream (below).
  - getBlockHeaders: a stream (below) of the blocks of its query.
  - getBlobSidecars and getDebugDataColumnSidecars: the block, as for getBlockV2; the error 400 for a block whose slot's fork is not the operation's (beacon-api.md), and no stream; else a stream (below) of the block's sidecars.
  - getBlobs: the block, as for getBlockV2; a blob stream (below) of it, or the error 404 that the blob stream gives, and no stream.
  - getLightClientBootstrap: a `NODE_ACT_BYTES_PUT` of the route's `block_root` (32 bytes) to a new id; a `NODE_WORK_API_ENCODE` with the light client store as `state_c` and that id as `data`, the connection as `target`, and as `arg` the operation + 2^8 times the answer flags (`API_ANSWER_SSZ` for an SSZ `response`); after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id. getLightClientFinalityUpdate and getLightClientOptimisticUpdate: the same with no `data`.
  - getLightClientUpdatesByRange: a `NODE_ACT_BYTES_PUT` of `start_period` and `start_period` + the lower of `count` and `MAX_REQUEST_LIGHT_CLIENT_UPDATES` (2^64 - 1 past it), 16 bytes, to a new id, and the same work with that id as `data`; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id.
  - getPendingDeposits, getPendingPartialWithdrawals and getPendingConsolidations: a stream (below) of the state; the error 400 for a state whose slot's fork is before electra, and no stream.
  - getStateRandao and getEpochSyncCommittees: as `data` a `NODE_ACT_BYTES_PUT` of the route's `epoch` (8 bytes; 2^64 - 1 when it is not given) to a new id; after the `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id. getProposerLookahead: `API_ANSWER_SSZ` among the answer flags for an SSZ `response`.
  - getStateValidator: a `NODE_ACT_BYTES_PUT` of the route's `validator` (a `ValidatorRef`) to a new id; a `NODE_WORK_API_ENCODE` as above with the state as `state_a` and that id as `data`; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id.
  - getStateValidators, postStateValidators, getStateValidatorBalances, postStateValidatorBalances and postStateValidatorIdentities: a stream (below) of the state.
  - getEpochCommittees: the error 400 for an epoch or a slot that beacon-api.md refuses, from the state's slot; else a stream (below) of the state.
  - eventstream: the first free `NodeApi` entry, else the next, with the connection, the operation, `API_STREAM_STARTED`, `API_STREAM_CHUNKED` over HTTP/1.1 (and `API_STREAM_CLOSE` with `Connection: close`), `API_STREAM_CLOSE` and `API_STREAM_HTTP10` over HTTP/1.0, the route's `topics` at byte 0 of `cursor`; a `NODE_ACT_API_SEND` of the head (beacon-api.md, eventstream) with `last` 0, and `sent` its bytes. The entry stays to the stream's end.
  - getPoolVoluntaryExits, getPoolBLSToExecutionChanges, getPoolProposerSlashings, getPoolAttesterSlashingsV2 and getPoolAttestationsV2: a stream (below) of the pool.
  - submitPoolVoluntaryExit, submitPoolProposerSlashings, submitPoolAttesterSlashingsV2, submitPoolBLSToExecutionChange, submitPoolAttestationsV2, publishAggregateAndProofsV2, submitPoolSyncCommitteeSignatures, publishContributionAndProofs, prepareBeaconCommitteeSubnet, prepareSyncCommitteeSubnets and prepareBeaconProposer: a `NODE_ACT_BYTES_PUT` of the request's body to a new id, and a `NODE_WORK_API_SUBMIT` with the head's post-state as `state_a`, that id as `data`, the connection as `target`, and as `arg` the operation + 2^8 times the answer flags (and `API_ANSWER_SSZ` for an SSZ `body`) + 2^16 times the fork of the store's slot. submitPoolAttesterSlashingsV2 whose `consensus_version` names a fork of another `AttesterSlashing` type than the fork of the store's slot (electra's from electra on, phase0's before), and submitPoolAttestationsV2 and publishAggregateAndProofsV2 whose `consensus_version` is electra or later before electra or before electra from electra (`Attestation` against `SingleAttestation`, phase0's `SignedAggregateAndProof` against electra's): the error 400, and no work. A body of no bytes: the error 400, and no work. A head with no post-state: the error 500, and no work.
  - getProposerDuties: 503 with `NODE_FLAG_SYNCING`; 400 for an epoch above the epoch of the store's slot + 1; then the state of the epoch's first slot, as for a `state_id` of that slot, or past the store's slot the head's post-state brought to it; a `NODE_WORK_API_ENCODE` of it, `arg` as for the state operations with that slot.
  - produceAttestationData: 503 with `NODE_FLAG_SYNCING`; 400 for a `slot` past the store's slot; then the state of `slot`, as for a `state_id` of that slot (none: 400); 503 when it is optimistic; a `NODE_ACT_BYTES_PUT` of `committee_index` (8 bytes) to a new id, and a `NODE_WORK_API_ENCODE` of the state as `state_a` and that id as `data`, `arg` as for the state operations with that slot, and `API_ANSWER_SSZ` (4) among the answer flags for an SSZ `response`; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id.
  - getSyncCommitteeDuties: 503 with `NODE_FLAG_SYNCING`; 400 for an epoch whose sync committee period is above that of the store's slot + 1, for no `ValidatorRef` item or one of a public key; then, when the head's post-state is of altair or later and the epoch's period is that of the head's slot (or the next), that state, and `API_VALUE_NEXT_PERIOD` (8) among the values for the next; else the state as for getAttesterDuties; then the `NODE_ACT_BYTES_PUT` of the items and the `NODE_WORK_API_ENCODE` as for getAttesterDuties, `arg` with the state's slot.
  - getAttesterDuties: 503 with `NODE_FLAG_SYNCING`; 400 for an epoch above the epoch of the store's slot + 1, for no `ValidatorRef` item or one of a public key; then the state of the epoch's first slot, as for getProposerDuties (none: 400); a `NODE_ACT_BYTES_PUT` of the route's `ValidatorRef` items to a new id, and a `NODE_WORK_API_ENCODE` of the state as `state_a` and that id as `data`, `arg` as for the state operations with that slot; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id.
  - getLiveness: 503 with `NODE_FLAG_SYNCING`; 400 for an epoch below the previous epoch of the store's slot (get_previous_epoch: 0 at epoch 0) or above its next, for no `ValidatorRef` item or one of a public key; then the head's post-state at its slot, as for a `state_id` of `head` (none: 500); a `NODE_ACT_BYTES_PUT` of the route's `ValidatorRef` items to a new id, and a `NODE_WORK_API_ENCODE` of the state as `state_a` and that id as `data`, `arg` as for the state operations with the route's `epoch` in place of the slot; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id.
  - getBlockRewards and getSyncCommitteeRewards: the block, as for getBlockV2, must be a `NodeBlock` with bytes; a block of the `Db`, or none: the error 404. getSyncCommitteeRewards of a block whose slot's fork is phase0: the error 400. Then the `NodeBlock` of its `parent_root`, with a post-state, which one above F's slot with none gets again first; with none, the error 404. P: a `NODE_ACT_STATE_COPY` of that post-state brought to the block's slot, as a lookup's state (the crossing, then `NODE_WORK_SLOTS`).
    - getBlockRewards of a phase0 block of epoch b: as `state_b` when b is above 0, the state of the chain at the last slot of b; as `state_c` when the fork of epoch b + 1 is phase0, that at the last slot of b + 1. Each as for a `state_id` of its slot, and past the store's slot the head's post-state brought to it; with none, the error 404.
    - getSyncCommitteeRewards: a `NODE_ACT_BYTES_PUT` of the route's `ValidatorRef` items to a new id, as `state_b`.
    - Then a `NODE_WORK_API_ENCODE` of P as `state_a` and the block's bytes as `data`, `arg` as for the state operations with the block's slot and the values of the block, as getBlockHeader has them; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_STATE_FREE` of each copy and a `NODE_ACT_BYTES_FREE` of the id.
  - A `state_id` of a root: a `NodeApi` entry with `API_STREAM_LOOKUP`, the connection, the operation, the answer flags and `API_STREAM_SSZ` for `response` `API_TYPE_SSZ`, the root in the first 32 bytes of its `cursor`, the route's `statuses` at byte 32 of it, its `validator` at byte 40, and its `epoch`, `slot`, `index` and `present` at bytes 104, 112, 120 and 128; for the six validator operations the ids as for their stream (below), as `data` with `API_STREAM_OWN`; and a `NODE_WORK_API_LOOKUP` with the head's post-state as `state_a`, the connection as `target` and the entry's index as `arg`.
- A `state_id` whose state needs the replay (above), for a `NODE_EV_API`: a `NodeApi` entry as for a root, with `API_STREAM_LOOKUP` and `API_STREAM_REPLAY`, the slot of the `state_id` at byte 136 of its `cursor`, and no work. When it runs again: the entry loses `API_STREAM_REPLAY` and goes on as a `NODE_WORK_API_LOOKUP` done with that slot (below); with `API_STREAM_GONE` it ends.
- `NODE_EV_WORK_DONE` of `NODE_WORK_API_LOOKUP`, of the `NodeApi` entry at index `arg`: the entry ends; with a slot whose state needs the replay, it waits instead, as above. Without `API_STREAM_GONE`: with a slot at `NodeEvent_index`, the answer of the entry's operation for the `state_id` of that slot, as for a `NODE_EV_API` with its answer flags, `statuses`, `validator`, `epoch`, `slot`, `index`, `present` and ids, whose `data` the answer takes; with 2^64 - 1 there, the error 404 (and the ids' `NODE_ACT_BYTES_FREE`).
  - Every other operation: 501.
- A stream: the first free `NodeApi` entry, else the next, with the connection, the operation, the answer flags (`API_STREAM_CLOSE`, `API_STREAM_HTTP10`), `API_STREAM_SSZ` for `response` `API_TYPE_SSZ`, `API_STREAM_OPTIMISTIC` and `API_STREAM_FINALIZED` as beacon-api.md gives `execution_optimistic` and `finalized`, the slot of the block or the state and its fork, and `sent` and `cursor` zero; then a `NODE_WORK_API_CHUNK` of it, and `API_STREAM_BUSY`.
  - getBlockV2, getBlindedBlock and getBlockAttestationsV2: `data` the block's bytes; with none, the error 404 and no stream.
  - getStateV2: a `NODE_ACT_STATE_BYTES` of the state (the copy at its slot, then the copy's `NODE_ACT_STATE_FREE`) to a new id, which is `data`, with `API_STREAM_OWN`.
  - The pending streams: `state` the state's id, with `API_STREAM_OWN_STATE` when it is the lookup's copy; `data` 0; `fork` the fork of the state's slot.
  - The five validator streams: `state` the state's id, with `API_STREAM_OWN_STATE` when it is the lookup's copy; the route's `statuses` at byte 8 of `cursor`; with `id` items, `data` a `NODE_ACT_BYTES_PUT` of the route's list of `ValidatorRef` items to a new id, with `API_STREAM_OWN`; else `data` 0.
  - getBlockHeaders: `filter_slot` the route's `slot`, the head's slot with neither `slot` nor `parent_root`, else 2^64 - 1; with `parent_root`, it at byte 32 of `cursor` and 1 at byte 64; the flags `API_STREAM_OPTIMISTIC` and `API_STREAM_FINALIZED` of all its items (beacon-api.md, getBlockHeaders); then its first item.
  - The sidecar streams, of getBlobSidecars and getDebugDataColumnSidecars: `fork` the fork of the block's slot, `slot` its slot, `root` its root; `filter_slot` and `filter_index` the bits of the `indices` given (index i: bit i of `filter_slot` for i below 64, else bit i - 64 of `filter_index`; others none), both 2^64 - 1 with none; `API_STREAM_OPTIMISTIC` and `API_STREAM_FINALIZED` of the block; then its first sidecar.
  - A sidecar of a sidecar stream, from the index i on, below 128, of a bit of the filters: `member` i, `data` its bytes, the `NodeBlob` entry's in `NODE_BLOB_VALID` of `root` and index i, else, with `NODE_FLAG_DB`, the `NODE_DB_REF` of the `Db`'s sidecar record of `slot` and index i; `sent` 0 and `cursor` zero. With none, `data` 0.
  - The blob stream, of getBlobs: `fork`, `slot`, `root`, `API_STREAM_OPTIMISTIC` and `API_STREAM_FINALIZED` as for a sidecar stream; with `versioned_hashes` items, `state` a `NODE_ACT_BYTES_PUT` of the route's list of them (Root items) to a new id, with `API_STREAM_OWN_STATE`; else `state` 0.
    - A fork before deneb: `data` 0.
    - Deneb and electra: the sidecars of a sidecar stream with every index (`filter_slot` and `filter_index` 2^64 - 1), from index 0; after a chunk with `API_STREAM_ITEM_DONE`, the sidecar from `member` + 1 on.
    - Fulu and later: the column sidecar of column c of the block is the `NodeBlob` entry's in `NODE_BLOB_VALID` of `root` and index c, else, with `NODE_FLAG_DB`, the `NODE_DB_REF` of the `Db`'s record of `slot` and index c. With one of each column from 0 to `NUMBER_OF_COLUMNS` / 2 - 1: the pairs of a blob b and a column c, from b 0 and c 0, `filter_slot` b and `member` c, `data` the sidecar of column c. With none of any column: `data` 0. Else the error 404.
    - Fulu, after a chunk with `API_STREAM_ITEM_DONE`: with `API_STREAM_BLOB_SKIP`, or at c `NUMBER_OF_COLUMNS` / 2 - 1, blob b + 1 and column 0; else column c + 1; `data` the sidecar of that column (0 when the node holds none), `sent` 0.
  - An item of getBlockHeaders: `slot` 0 for the `Db`'s block, i + 1 for the `NodeBlock` at index i; its root at byte 0 of `cursor`; `member` 1 when it is on the chain; `data` the block's bytes, its `NodeBlock`'s, else the `NODE_DB_REF` of its `Db` record (lantern_db_find_root of its root); with none, `state` its post-state. With no item, `data` and `state` 0.
  - getAggregatedAttestationV2: a pool stream of the attestations of `slot` and `committee_index` (`filter_slot`, `filter_index`), with `attestation_data_root` at byte 0 of `cursor` and `API_STREAM_FOLD`, and `API_STREAM_SSZ` for an SSZ `response`; with no entry, the error 404 and no stream.
  - produceSyncCommitteeContribution: a pool stream of the sync committee messages of `slot` (`filter_slot`) valid on the subnet `subcommittee_index` (`filter_index`: bit `filter_index` of the entry's `index`), with `beacon_block_root` at byte 0 of `cursor`, `API_STREAM_FOLD`, and `state` the head's post-state; a `subcommittee_index` not below `SYNC_COMMITTEE_SUBNET_COUNT`, the error 400; a head with no post-state, the error 500; with no entry, the error 404; each with no stream.
  - A chunk of getAggregatedAttestationV2 with `API_STREAM_FOLD` and without `API_STREAM_DONE` sends nothing, and its next `NODE_WORK_API_CHUNK` goes at once. With `data`, it folded its entry into the aggregate in `cursor`, with `API_STREAM_ITEM_DONE`: the entry goes to its next pool entry, `cursor` kept. With `data` 0 and no bytes, the fold's end: `API_STREAM_OPTIMISTIC` is set when the `BlockNode` of the store's `blocks` with the aggregate's `beacon_block_root` (fork-choice.md; a contribution's, at byte 0 of `cursor`) has `payload_status` `NOT_VALIDATED`. With `data` 0 and bytes, they are the `Attestation`'s SSZ bytes: a `NODE_ACT_BYTES_PUT` of them to a new id, which becomes `data`, with `API_STREAM_OWN`; `API_STREAM_FOLD` clears, `sent` is 0 and `cursor` zero, and the chunks after it are the answer.
  - The pool streams: `fork` the fork of the store's slot; `slot` the index of the pool's first entry the stream answers, `data` its bytes, `sent` its fork and `member` its member; with none, `data` 0. getPoolAttestationsV2: `filter_slot` the route's `slot` and `filter_index` its `committee_index`, each 2^64 - 1 when not given; the other pool streams: both 2^64 - 1.
  - The entries a pool stream answers: those of the operation's topic; for getPoolAttesterSlashingsV2, of an `AttesterSlashing` type that is that of `fork`; for getPoolAttestationsV2, of the attestation type of `fork` (electra's from electra, phase0's before), with `slot` equal to `filter_slot` and `index` equal to `filter_index` when those are not 2^64 - 1.
  - getEpochCommittees: `state` as for the validator streams, `data` 0; in `cursor`, the first slot (`slot`, else the epoch's first) at byte 0, the epoch at 24, `slot` at 40 and `index` at 48 (2^64 - 1 for one not given).
- `NODE_EV_WORK_DONE` of `NODE_WORK_API_CHUNK`, of the `NodeApi` entry at index `arg`: `API_STREAM_BUSY` clears.
  - A getBlockHeaders stream whose event has `API_STREAM_ITEM_DONE`, with `LANTERN_VALID`: its next item after `slot`.
  - A sidecar stream whose event has `API_STREAM_ITEM_DONE`, with `LANTERN_VALID`: its sidecar from `member` + 1 on.
  - A pool stream whose event has `API_STREAM_ITEM_DONE`, with `LANTERN_VALID`: the next pool entry after `slot` that the stream answers becomes `slot`, its bytes `data`, its fork `sent`, its member `member`, and `cursor` zero (kept with `API_STREAM_FOLD`); with none, `data` 0. Bytes of the entry before that the stream owns (`API_STREAM_OWN`) get a `NODE_ACT_BYTES_FREE`, and `API_STREAM_OWN` clears.
  - With `API_STREAM_GONE`: the stream ends.
  - `LANTERN_VALID`: the entry takes `sent`, `flags` and `cursor` of the event; with `API_STREAM_FOLD` and without `API_STREAM_DONE`, no send (getAggregatedAttestationV2, above), else a `NODE_ACT_API_SEND` of the chunk at `NodeEvent_api_bytes` to the connection, with `last` 1 when `API_STREAM_DONE` is set, else 0. With `API_STREAM_DONE`: a `NODE_ACT_API_CLOSE` after it when `API_STREAM_CLOSE` is set, and the stream ends.
  - Another result: before `API_STREAM_STARTED`, the error 500 to the connection; after it, a `NODE_ACT_API_CLOSE` of the connection (the answer stops short). The stream ends.
- `NODE_EV_WORK_DONE` of `NODE_WORK_API_SUBMIT`: a `NODE_ACT_BYTES_FREE` of the body's id (`data`). With `LANTERN_INVALID_ENCODING`, or another result than `LANTERN_VALID`: the error 400 to the connection `target`. Else, for each operation of the event (the run, below), in order:
  - `LANTERN_VALID`: a `NODE_ACT_BYTES_PUT` of its SSZ bytes to a new id, kept, but an aggregate or a contribution, as a `NodePool` entry of its topic and of the fork of `arg` / 2^16 when the pool has an entry free for it (an attestation with its `data.slot` and committee index from its bytes, and the member of its record); then with `NODE_FLAG_SUBSCRIBED` the publish of the bytes on its topic (an attestation on beacon_attestation of its subnet); an attester slashing also gets a `NODE_WORK_ATTESTER_SLASHING` of that id with the post-state of the justified root, as one from gossip does. An id no entry keeps and no work reads gets its `NODE_ACT_BYTES_FREE`.
  - A registration of `LANTERN_VALID`: the registration of its validator's `NodeProposer` entry (beacon-api.md, registerValidator). After the last record, with `NODE_FLAG_BUILDER` and one or more: a `NODE_BUILDER_REGISTER` call, its body `[`, for each such record in order the JSON of its `SignedValidatorRegistrationV1` `{"message":{"fee_recipient":"0x…","gas_limit":"…","timestamp":"…","pubkey":"0x…"},"signature":"0x…"}` (lower case hex, decimal in quotes) with `,` between, then `]`.
  - A subscription: with `is_aggregator`, `subnet_until` of compute_subnet_for_attestation(`committees_at_slot`, `slot`, `committee_index`) (phase0 validator.md) takes `slot` + 1 when that is more; a sync subscription: for each index i, `sync_until` of the subnet i / (SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT) takes `until_epoch` when that is more; a proposer preparation: the `NodeProposer` of its `validator_index` takes its `fee_recipient` and the store's epoch + 3 as `until_epoch`, else the first entry whose `until_epoch` is at most the store's epoch, else a new entry while the part has room (its bytes up to `p2p_out`), else none. No bytes are kept.
  - `LANTERN_GOSSIP_REJECT`: a failure, with the operation's place in the body.
  - Another result: nothing.
  - Then the answer (beacon-api.md, the pool POSTs) to the connection, with the answer flags of `arg`: 200, or 400 with the failures.
- The pool: the `NodePool` entries, each a voluntary_exit, proposer_slashing, attester_slashing, bls_to_execution_change or beacon_attestation that passed its gossip validation; a new entry takes the first free entry. A `NODE_ACT_BYTES_FREE` of an id a pool entry has as `data` does not go: the entry keeps the bytes until it goes.
  - An attestation or a sync committee message takes a free entry only at an index below 3/4 of the pool's capacity, so that the other operations always have the last quarter.
  - At the quiet point of a head event (above), when `head_root` changes: an attestation entry whose slot's epoch + 1 is below the epoch of the store's slot goes (as at a check that fails, below), and a sync committee message entry whose slot + 1 is below the store's slot (its gossip validation holds for the current slot only); then each other entry in `NODE_POOL_KEPT` gets a `NODE_WORK_POOL_CHECK` with the head's post-state as `state_a`, its bytes as `data`, its index as `target` and its topic as `arg`, and takes `NODE_POOL_CHECKING`; with no head post-state, none. An attestation gets no check: its gossip validation holds for its epoch and the next only (`ATTESTATION_PROPAGATION_SLOT_RANGE`, the current or previous epoch), and the pool keeps it that long.
  - `NODE_EV_WORK_DONE` of `NODE_WORK_POOL_CHECK`, of the entry at index `target` in `NODE_POOL_CHECKING`: `LANTERN_VALID`, it takes `NODE_POOL_KEPT`; else a `NODE_ACT_BYTES_FREE` of its bytes, and it is free (topic 0).
- The publish of SSZ bytes on a topic, with `NODE_FLAG_SUBSCRIBED` (phase0 `p2p-interface.md`, Topics and messages: the data of a message is the SSZ bytes compressed with Snappy's block format): a `LIBP2P_EVENT_PUBLISH` at the end of `p2p_out`, the topic lantern_gossip_topic of `fork_digest` and the topic's name, the data snappy_compress of the bytes, and the ID compute_message_id of the fork of the store's slot of that topic and the bytes; none when `p2p_out` has no room for it. libp2p's `LIBP2P_ACTION_PUBLISHED` that answers it changes nothing.
- `NODE_EV_API_SENT` of the connection of a `NodeApi` entry of eventstream: its `sent` is 0. Of another entry without `API_STREAM_BUSY`: a `NODE_WORK_API_CHUNK` of it, and `API_STREAM_BUSY`. Another `NODE_EV_API_SENT` is skipped.
- `NODE_EV_API_CLOSED` of the connection of a `NodeApi` entry: with `API_STREAM_BUSY`, the entry takes `API_STREAM_GONE`; else the stream ends, and a produceBlockV3 entry's draft, engine result, builder answer or bid go with it, and its header call in flight answers no entry. Another is skipped.
- The end of a stream: with `API_STREAM_OWN`, a `NODE_ACT_BYTES_FREE` of its `data`; with `API_STREAM_OWN_STATE`, a `NODE_ACT_STATE_FREE` of its `state`; its entry is free (connection 0), and the api part's count drops past the free entries at its end.
- A `NODE_ACT_BYTES_FREE` of an id that a `NodeApi` entry has as `data` without `API_STREAM_OWN` does not go: the entry takes `API_STREAM_OWN`, and frees the bytes at its end. So with a `NODE_ACT_STATE_FREE` of an id that an entry has as `state` without `API_STREAM_OWN_STATE`: the entry takes `API_STREAM_OWN_STATE`. The node changes no state it keeps, so the entry reads the same state to its end. A produceBlockV3 entry in `NODE_PRODUCE_FOLD` whose `root` is the id (the pool bytes of its fold in flight) takes `API_STREAM_PRODUCE_OWN` instead, and frees them when the fold is done; in another phase `root` holds no id.
- `NODE_EV_API_IDENTITY`: the node's `api_identity` takes the event's `ApiIdentity`.
- `NODE_EV_WORK_DONE` of `NODE_WORK_API_ENCODE`: `LANTERN_VALID`, the response at `NodeEvent_chunk` in a `NODE_ACT_API_SEND` of the connection `target` with `last` 1; another result, the error 500. With `API_ANSWER_CLOSE` in `arg`, a `NODE_ACT_API_CLOSE` after it.
- With `NODE_FLAG_ENGINE`: a `NODE_EV_ENGINE` with arg 1 sets `NODE_FLAG_EL_OFFLINE`; a whole response of lantern_http_parse_response in `engine_in` clears it.

### Function never

- Reads a beacon state or keeps an argument's address.

## Function `lantern_node_run`

One `NODE_ACT_WORK` with its buffers. It writes the `NODE_EV_WORK_DONE` event of the work.

### Signature

```
lantern_node_run(node, store, seen, work, state_a, state_b, state_c, data, settings, scratch, event) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | `Node` |
| `store` | state | `Store` |
| `seen` | state | `Seen` |
| `work` | input | `NodeAction` of kind `NODE_ACT_WORK` |
| `state_a` | state | `BeaconState`: the buffer of the work's `state_a`, or 0 |
| `state_b` | state | `BeaconState`: the buffer of the work's `state_b`, or 0 |
| `state_c` | state | `BeaconState`: the buffer of the work's `state_c`, or 0 |
| `data` | input | ByteList: the buffer of the work's `data`, or 0 |
| `settings` | input | asm-crypto `KzgSettings`, or 0 |
| `scratch` | scratch | `Scratch` |
| `event` | output | `NodeEvent`: its `size` set by the caller to the bytes of the buffer, `NODE_EV_WORK_DONE_SIZE` or more |

### Returns

- `LANTERN_OK`: `event` holds the work's fields and its `result`.
- `LANTERN_BUFFER_TOO_SMALL`: the store, `state_a`, `scratch`, `seen` or `event` has too little room. Nothing is changed.
- `LANTERN_INVALID_EVENT`: the work is of no kind, or names no `NodeCheckpoint`; a `NODE_WORK_API_ENCODE` of another operation, of a block index past the blocks part, getBlockHeader with neither `data` nor `state_a` or with neither `data` nor a block index, another but getSpec, getDebugChainHeadsV2 and getDebugForkChoice with no `state_a`; a `NODE_WORK_API_CHUNK` of an index past the api part, of a free entry or one of another operation, with no `data` for getBlockV2 and getStateV2, or with no `state_a` for the validator streams; a `NODE_WORK_API_LOOKUP` with no `state_a`; a `NODE_WORK_API_EVENT` of another topic, of head with no `state_a`, or of finalized_checkpoint with neither `data` nor `state_a`; a `NODE_WORK_API_SUBMIT` of another operation, or with no `state_a` or `data`; a `NODE_WORK_POOL_CHECK` of another topic, or with no `state_a` or `data`.

### Caller must

- On `LANTERN_BUFFER_TOO_SMALL`, grow the store with lantern_store_copy, or `state_a` with lantern_beacon_state_copy, or for a `NODE_WORK_LC_BLOCK` or `NODE_WORK_LC_HEAD` the light client store `state_c` with lantern_lc_store_copy, or `scratch`, or for a SERVE, LC_SERVE, LC_PUBLISH, NEW_PAYLOAD, FORKCHOICE, API_ENCODE, API_CHUNK, API_EVENT, PREPARE_PAYLOAD, GET_PAYLOAD, PRODUCE_BID, PRODUCE_BLOCK, PUBLISH_DECODE, PUBLISH_CHECK or PUBLISH_SIDECAR work `event`, then call again.
- Give a `NODE_WORK_PUBLISH_DECODE` or `NODE_WORK_PUBLISH_CHECK` an `event` with room for `NodeEvent_chunk` + 24 + the bytes of `data`; a `NODE_WORK_PUBLISH_CHECK` of a blinded block (`arg` bit 8) one with room for `NodeEvent_chunk` + 24 + 4 times them + 4096 + `JSON_CURSOR_SIZE` (its JSON, and the cursor at the event's end): the check changes `state_a`, so it asks for the room before it starts.

### Function does

- `NODE_WORK_IMPORT_BLOCK`: lantern_node_import of the fork of the block's slot, with `BlockOptions` of `PAYLOAD_STATUS_VALID` (`PAYLOAD_STATUS_NOT_VALIDATED` with `NODE_FLAG_OPTIMISTIC`; the block's `payload_status` with `NODE_FLAG_ENGINE`), the block's `data_available`, and `slots_done` 1 when `state_a` is at the block's slot and that slot is the first of its fork. `LANTERN_NEED_JUSTIFIED_STATE` becomes the result. A `state_a` whose slot's fork is not that of the block's slot gives the result `LANTERN_INVALID_SLOT`.
- `NODE_WORK_SLOTS`: lantern_process_slots of the fork of the slot of `state_a`, of `state_a` to the slot `arg`.
- `NODE_WORK_REPLAY`: lantern_node_replay of the fork of the block's slot, of the block in `data` (its bytes, or a `NODE_DB_REF`) on `state_a`; a `state_a` whose slot's fork is not the block's gives `LANTERN_INVALID_SLOT`.
- `NODE_WORK_UPGRADE`: lantern_node_upgrade of the fork `arg`, of `state_a` into `state_b`, with a `StateRoom` of 1024 validators, 2048 eth1_data_votes, 64 historical_summaries, 1024 pending_deposits, 64 pending_partial_withdrawals, 64 pending_consolidations, 4 historical_roots and 4096 pending_attestations, as the binary's anchor has, and the node's config. A fork `arg` outside altair to fulu, or a `state_a` not at that fork's first slot, gives the result `LANTERN_INVALID_SLOT`.
- `NODE_WORK_JUSTIFIED_STATE`: lantern_store_justified_checkpoint_state with `state_a`.
- `NODE_WORK_TARGET_STATE`: lantern_store_target_checkpoint_state of `state_a` to the `NodeCheckpoint` at index `target`.
- `NODE_WORK_ATTESTATION`: lantern_node_attestation of the fork of the attestation's slot; `is_from_block` is the work's `arg`.
- `NODE_WORK_GOSSIP_VOTE`: the aggregate of the `SignedAggregateAndProof` in `data` (the message's offset at byte 0, the aggregate's at byte 8 of the message, to the end of the bytes), as a ByteList at the end of `scratch`, then as `NODE_WORK_ATTESTATION` with `is_from_block` 0. Bytes that do not hold it give `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_BLOCK_ATTESTATION` and `NODE_WORK_BLOCK_SLASHING`: the attestation or attester slashing at index `arg` of the body of the `SignedBeaconBlock` in `data`, its SSZ bytes as a ByteList at the end of `scratch`, then as `NODE_WORK_ATTESTATION` with `is_from_block` 1, or as `NODE_WORK_ATTESTER_SLASHING`. The body's attester_slashings and attestations are its fields 4 and 5 in every fork: offsets at bytes 204 and 208 of the body, after randao_reveal, eth1_data and graffiti. An index past the list, or bytes that do not hold it, give `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_IMPORT_BLOCK` of a valid block: the counts of its body's attestations at `NodeEvent_index` and attester slashings at `NodeEvent_root`.
- `NODE_WORK_LC_BLOCK`: lantern_lc_on_block of the `LcStore` `state_c` with the node's config, `state_a`, `data` and no `StateCache`; its status but `LANTERN_BUFFER_TOO_SMALL` is the result. No `state_a`, `data` or `state_c`: `LANTERN_INVALID_EVENT`.
- `NODE_WORK_LC_HEAD`: lantern_lc_on_head of the `LcStore` `state_c` with the node's config, `head_root` and the store's finalized checkpoint; its status but `LANTERN_BUFFER_TOO_SMALL` is the result. Then, with a latest finality update in the store: its `finalized_header.beacon.slot` at `NodeEvent_index`, and at `NodeEvent_root` its `attested_header.beacon.slot`, then 1 when its participants times 3 are at least `SYNC_COMMITTEE_SIZE` times 2 (the supermajority of is_better_update), then 1, then its `signature_slot`; else zero. No `state_c`: `LANTERN_INVALID_EVENT`.
- `NODE_WORK_ATTESTER_SLASHING`: lantern_node_attester_slashing of the fork of the store's slot; a state whose slot's fork is another gives the result `LANTERN_GOSSIP_IGNORE`.
- `NODE_WORK_LC_SERVE`: the response of the light client method `arg` from the `LcStore` `state_c`, as a ByteList at `NodeEvent_chunk` of the event, each chunk by lantern_reqresp_write_chunk with the context bytes compute_fork_digest of the epoch of the object's `attested_header.beacon.slot` (a bootstrap's `header.beacon.slot`), the node's `genesis_validators_root` and config: GetLightClientBootstrap, the bootstrap of the root in `data` (lantern_lc_read); GetLightClientFinalityUpdate and GetLightClientOptimisticUpdate, the latest; LightClientUpdatesByRange, the best update of each period from `start_period`, at most the lower of `count` and `MAX_REQUEST_LIGHT_CLIENT_UPDATES`, from the first it holds to the first period of none. With no bootstrap, finality or optimistic update: one chunk of result 3 (ResourceUnavailable) and no payload. The event's `size` then covers the bytes.
- `NODE_WORK_LC_PUBLISH`: lantern_lc_read of the `LcStore` `state_c` of the kind of the topic `arg` (light_client_finality_update `LC_OBJECT_FINALITY_UPDATE`, light_client_optimistic_update `LC_OBJECT_OPTIMISTIC_UPDATE`), as a ByteList at `NodeEvent_chunk` of the event, and the latest update's fields as `NODE_WORK_LC_HEAD` gives them. The result: `LANTERN_VALID`; `LANTERN_GOSSIP_IGNORE` with no update, or when compute_fork_digest of the object's fork for the epoch of its `attested_header.beacon.slot` is not `fork_digest` (the `ForkDigest` context of the topics). The event's `size` then covers the bytes. Another topic or no `state_c`: `LANTERN_INVALID_EVENT`.
- `NODE_WORK_LC_GOSSIP`: the same object, at the end of `scratch`, and the same fields and result, but `LANTERN_GOSSIP_IGNORE` when `data` is not its bytes exactly (the full node's IGNORE check: the update matches the locally computed one), and when `scratch` has no room for the object.
- `NODE_WORK_SERVE`: the response chunk of the block, blob sidecar or column sidecar in `data`, with lantern_reqresp_write_chunk, as a ByteList at `NodeEvent_chunk` of the event; its context bytes are compute_fork_digest of the epoch of the block's slot (blocks of version 2, and BeaconBlocksByHead) or of the sidecar's block header slot (the blob and column methods), none for blocks of version 1. The event's `size` then covers the chunk.
- `NODE_WORK_SYNC_BLOCK`: lantern_node_block_root of the fork of the block's slot, its root at `NodeEvent_root` and its blob count at `NodeEvent_index`.
- `NODE_WORK_BACKFILL`: lantern_node_block_root of the fork of the block's slot, its root at `NodeEvent_root`; then, for `LANTERN_VALID`, lantern_node_backfill of the fork of the slot of `state_a`, of the block in `data` and that root.
- `NODE_WORK_NEW_PAYLOAD`: lantern_node_new_payload of the fork of the block's slot (bellatrix and later; before it `LANTERN_NO_PAYLOAD`), its request a ByteList at `NodeEvent_chunk`. The event's `size` then covers it.
- `NODE_WORK_PREPARE_PAYLOAD`: of the fork of the slot of `state_a`: the `proposers` entry of get_beacon_proposer_index of `state_a` whose `until_epoch` is above the epoch of the state's slot, else the result `LANTERN_NO_PAYLOAD`; lantern_get_payload_attributes of `state_a` with its `fee_recipient` and the node's config; then engine_forkchoiceUpdated with those attributes and the id `arg`, its head the `block_hash` of the store's node of `payload_root` (the state's `latest_execution_payload_header.block_hash`, prepare_execution_payload's `parent_hash`; `LANTERN_INVALID_UNKNOWN_BLOCK` when the store has no such node, `LANTERN_NO_PAYLOAD` when it is zero), its safe and finalized hashes as for `NODE_WORK_FORKCHOICE`, as a ByteList at `NodeEvent_chunk` in an HTTP POST as `NODE_WORK_FORKCHOICE` writes it; the proposer's index at `NodeEvent_index`. With 2 in `target`: after the request's ByteList, at its size rounded up to 8, the text of the payload_attributes event (beacon-api.md, eventstream) as a ByteList, its parent block number and hash from lantern_node_payload_parent of the fork of the state's slot. The event's `size` then covers the request and the text. With 1 in `target`, a proposer with no `proposers` entry takes a fee recipient of zero bytes.
- `NODE_WORK_GET_PAYLOAD`: lantern_engine_get_payload of the fork of the slot of the `NodeApi` entry at `target` with `payload_id` and the id `arg`, in an HTTP POST as `NODE_WORK_FORKCHOICE` writes it, as a ByteList at `NodeEvent_chunk`.
- `NODE_WORK_PRODUCE_CHECK`: lantern_node_produce_check of the fork of the slot of `state_a`, for the `NodeApi` entry at `target`: get_beacon_proposer_index of the state at `NodeEvent_root`, and at byte 8 of it 1 when the chain is healthy, else 0; with `skip_randao_verification` a `randao_reveal` that is not the point at infinity, else one that fails process_randao's check for that proposer: the result `LANTERN_INVALID_RANDAO_REVEAL` (400); an expected deposit count above 0 (beacon-api.md): `LANTERN_INVALID_DEPOSITS` (500).
- `NODE_WORK_PRODUCE_FOLD`: lantern_node_produce_fold of the fork of the slot of `state_a`: the pool entry `state_b` joins the draft `data` in place when the rules of beacon-api.md take it at `state_a`; `arg` its topic, + 2^8 times its `NodePool` `fork`, + 2^16 times its `member`.
- `NODE_WORK_PRODUCE_BLOCK`: lantern_node_produce_block of the fork of the slot of `state_a`, from the draft `data`, the engine's result `state_b` and the bid `state_c` (a ByteList, or 0), with the request of the entry at `target` and the node's config: the fork's `BeaconBlock`, `BlockContents` or `BlindedBeaconBlock` in SSZ bytes as a ByteList at `NodeEvent_chunk`, execution_payload_value at `NodeEvent_root` (32 bytes), consensus_block_value in Gwei at `NodeEvent_index`, and 1 at `NodeEvent_checkpoint` for a blinded block, else 0.
- `NODE_WORK_PRODUCE_BID`: of the builder's answer `data` (beacon-api.md, produceBlockV3, the builder): lantern_http_parse_response with `eof` 1, its body unchunked at the end of `scratch` (`LANTERN_INVALID_HTTP` when it gives no response); a status other than 200, the result `LANTERN_NO_BID`; the body an object whose first member `version` is a string and whose first member `data` is a value, other members skipped (else `LANTERN_INVALID_JSON`); `version` the name of the fork of the slot of `state_a` (else `LANTERN_INVALID_BID`). Then lantern_node_produce_bid of that fork, of the text of `data`, with the request of the entry at `target` and the node's config: the `SignedBuilderBid` in SSZ bytes as a ByteList at `NodeEvent_chunk`.
- `NODE_WORK_PUBLISH_DECODE`: lantern_node_publish_decode of the fork `arg` & 255, of the body in `data`, JSON or with `arg` bit 8 SSZ, with bit 9 a blinded block: the `SignedBeaconBlock` in SSZ bytes as a ByteList at `NodeEvent_chunk`, its hash_tree_root of the message at `NodeEvent_root`, its slot at `NodeEvent_index`, and from deneb the count of its body's `blob_kzg_commitments` at `NodeEvent_checkpoint`. `LANTERN_INVALID_ENCODING` for a body that is no value of the fork's type, or whose counts do not match (beacon-api.md).
- `NODE_WORK_PUBLISH_SIDECARS`: lantern_node_publish_sidecars of the fork of the entry, of the body in `data`, into the ByteList `state_b` in place: the sidecars of beacon-api.md, each a ByteList, back to back.
- `NODE_WORK_PUBLISH_CHECK`: lantern_node_publish_check of the fork of the slot of `state_a`: the checks of the level `arg` & 255 (beacon-api.md) of the block `data` and the sidecars `state_b`, with `state_a` the parent's post-state at the slot (process_block runs on it), `state_c` the head's, `seen` and the store, as lantern_node_gossip has them, and with `arg` bit 8 of a blinded block; its result, and with `LANTERN_VALID` the block's bytes as a ByteList at `NodeEvent_chunk`; for a blinded block its JSON there (lantern_node_json of `NODE_JSON_BLINDED_BLOCK`).
- `NODE_WORK_PUBLISH_SIDECAR`: the sidecar `arg` of the sidecars `state_b`, as a ByteList at `NodeEvent_chunk`, its block root at `NodeEvent_root`, its index at `NodeEvent_index` and its slot at `NodeEvent_checkpoint`; `LANTERN_INVALID_EVENT` past the last.
- `NODE_WORK_FORKCHOICE`: engine_forkchoiceUpdated of the fork of the store's slot with the `block_hash` of the store's nodes of `head_root`, the justified checkpoint's root (safe) and the finalized checkpoint's root, in an HTTP POST to `engine_host` with a JWT of `jwt_secret` and the time `time_ms` / 1000, a ByteList at `NodeEvent_chunk`; `LANTERN_INVALID_UNKNOWN_BLOCK` when the store has no node of one of those roots, `LANTERN_NO_PAYLOAD` before bellatrix or when the head's `block_hash` is zero (no call).
- `NODE_WORK_BLOB`: with `arg` 0, a `BlobSidecar`: lantern_node_blob_sidecar of the fork of its slot when it is deneb or electra; with `arg` 1, a `DataColumnSidecar`: lantern_node_column_sidecar when the fork of its slot is fulu. Each with the node's config and `settings`, the root at `NodeEvent_root`; a slot of another fork gives the result `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_GOSSIP`: lantern_node_gossip of the fork of the store's slot, with a `NodeGossip` of `seen`, the store, `time_ms`, the topic and subnet of `arg`, `state_a` as head, `state_b` as proposer, `state_c` as justified, `settings` and the node's config, its `root` at `NodeEvent_root` and its `index` at `NodeEvent_index`. A proposer or justified state whose slot's fork is not that of the store's slot is passed as 0; a head state whose slot's fork is not that of the store's slot gives the result `LANTERN_GOSSIP_IGNORE`, as at a fork's first slots, before the node imports a block of the new fork.
- `NODE_WORK_API_ENCODE`: the response of the operation in `arg` (beacon-api.md, Common rules), with the answer flags and the values of `arg`, as a ByteList at `NodeEvent_chunk` of the event; the event's `size` then covers it.
  - getLightClientBootstrap, getLightClientFinalityUpdate and getLightClientOptimisticUpdate: lantern_lc_read of `state_c` (the bootstrap of the root in `data`, the latest finality or optimistic update) into the end of `scratch`; as JSON, then lantern_node_json of the object's fork into the end of `scratch`, room for 4 times its bytes and 4096. No object: the error 404. No `state_c`, or no root of 32 bytes in `data` for the bootstrap: `LANTERN_INVALID_EVENT`.
  - getLightClientUpdatesByRange: for each period from the first 8 bytes of `data` below the next 8: lantern_lc_read of `state_c` (`LC_OBJECT_UPDATE`) into the end of `scratch`; from the first period with an update, up to the first with none; each as JSON with lantern_node_json of its fork, `NODE_JSON_LC_UPDATE`, into the end of `scratch`, or as SSZ with compute_fork_digest of the fork of its attested slot, the node's `genesis_validators_root` and config. No `state_c`, or `data` of other than 16 bytes: `LANTERN_INVALID_EVENT`.
  - getBlockHeader: the header of the block in `data` with lantern_node_block_header of the fork of its slot; with no `data`, the `latest_block_header` of `state_a`, its `state_root` lantern_state_root of the fork of the state's slot (with the `StateCache` of the node's config) when it is zero, and a zero signature. The root: that of the `NodeBlock` at index `arg` / 2^24 - 1, else lantern_node_block_root of `data`. Bytes that do not hold a block give the result `LANTERN_INVALID_ENCODING`.
  - getStateRoot: lantern_state_root of the fork of the state's slot, with the `StateCache` of the node's config. getStateFork: the state's `fork`. getStateFinalityCheckpoints: lantern_node_state_checkpoints of `state_a`.
  - getStateRandao: lantern_node_randao of the fork of the state's slot, of `state_a` and the u64 at byte 0 of `data`. getEpochSyncCommittees: lantern_node_sync_committee of the fork of the state's slot, of `state_a` and the u64 at byte 0 of `data`, into `scratch`. getProposerLookahead: lantern_node_proposer_lookahead of the fork of the state's slot, of `state_a`; the answer's version the fork of the state's slot. `LANTERN_NO_STATE_ANSWER` of any of them: the error 400 as the answer. `data` of fewer than 8 bytes gives `LANTERN_INVALID_ENCODING`.
  - getSpec: of the node's config, the preset and the constants (include/api_spec.inc); it reads no state.
  - getDebugChainHeadsV2: of the store's `blocks`, with 2 bits a node in `scratch`: a node is out when its `payload_status` is `PAYLOAD_STATUS_INVALIDATED` or its `parent` is out (a parent comes before its children); a leaf is a node not out that is the `parent` of no node not out. It reads no state.
  - getDebugForkChoice: lantern_node_weights of the fork of the head's slot, of the store, into `scratch`; a status of it but `LANTERN_BUFFER_TOO_SMALL` gives the error 500 as the answer. It reads no state.
  - getProposerDuties: lantern_node_proposers of the fork of the state's slot, of `state_a`, with the node's config.
  - produceAttestationData: lantern_node_attestation_data of the fork of the state's slot, of `state_a` and the u64 at byte 0 of `data`, with the node's config; `data` of fewer than 8 bytes gives `LANTERN_INVALID_ENCODING`.
  - getAttesterDuties: lantern_node_attester_duties of the fork of the state's slot, of `state_a` and the `ValidatorRef` items of `data`, with the node's config, into `scratch`; then the answer of each item in order.
  - getSyncCommitteeDuties: lantern_node_sync_committee of the fork of the state's slot, of `state_a` and the epoch of its slot (+ `EPOCHS_PER_SYNC_COMMITTEE_PERIOD` with `API_VALUE_NEXT_PERIOD`), its out at the end of `scratch`; then the answer of each `ValidatorRef` item of `data` in order. `LANTERN_NO_STATE_ANSWER`: the error 400 as the answer.
  - getLiveness: lantern_node_liveness of the fork of the state's slot, of `state_a`, the node's config, `seen`, the `ValidatorRef` items of `data` and the epoch `arg` / 2^24, its out at the end of `scratch`; then the answer of each item in order.
  - getBlockRewards: lantern_node_block_rewards of the fork of the block's slot (the u64 at byte 100 of `data`), of `state_a`, the block in `data`, `state_b`, `state_c` and the node's config, its out at the end of `scratch`; then the answer of its values. getSyncCommitteeRewards: lantern_node_sync_rewards of that fork, of `state_a` and the block in `data`, its out at the end of `scratch`; then the answer of each of its items, with `ValidatorRef` items in `state_b` only of those whose validator one names (beacon-api.md). A status of either but `LANTERN_OK` and `LANTERN_BUFFER_TOO_SMALL` is the result.
  - getStateValidator: the validator of the `ValidatorRef` in `data`, in `state_a`: the one of its index, or the first whose `pubkey` is its public key; with none, the error 404 in place of the response.
  - A `state_a` of these three whose slot is not `arg` / 2^24 gives the result `LANTERN_INVALID_SLOT`: the work that brought it to that slot failed. getLiveness takes `state_a` at its own slot, with the epoch in `arg` / 2^24.
- `NODE_WORK_API_SUBMIT`: the operations of the body in `data` (beacon-api.md, the pool POSTs), as a ByteList at `NodeEvent_chunk` of the event, the event's `size` covering it, and their count at `NodeEvent_index`.
  - The body: lantern_json_decode of the type of the operation `arg` % 2^8, of the fork `arg` / 2^16, into `scratch` (the subscriptions and prepareBeaconProposer: a JSON array of lantern's `BeaconCommitteeSubscription`, `SyncCommitteeSubscription` or `ProposerPreparation`, include/types.inc); for submitPoolBLSToExecutionChange, a JSON array, each item decoded so (from capella; before, the fork has no such type: `LANTERN_INVALID_ENCODING`). A body that is no such text: the result `LANTERN_INVALID_ENCODING`.
  - submitPoolAttestationsV2 and publishAggregateAndProofsV2: with `API_ANSWER_SSZ`, the SSZ list of the body: attestations from electra items of 240 bytes, the size of `SingleAttestation`; attestations before electra, and `SignedAggregateAndProof` items, found by the 4-byte offsets of the list (the first offset, a multiple of 4, gives the count; each at most the next and the body's length). A body that is no such list: `LANTERN_INVALID_ENCODING`. Else a JSON array, each item decoded as `Attestation` before electra and `SingleAttestation` from electra, or as the fork's `SignedAggregateAndProof` (`NODE_JSON_AGGREGATE_AND_PROOF`), `SyncCommitteeMessage` (`NODE_JSON_SYNC_COMMITTEE_MESSAGE`) or `SignedContributionAndProof` (`NODE_JSON_CONTRIBUTION_AND_PROOF`).
  - registerValidator: a JSON array of `SignedValidatorRegistrationV1`, or with `API_ANSWER_SSZ` the SSZ list of them (items of 180 bytes; a length that is no multiple of 180: `LANTERN_INVALID_ENCODING`). One scan of the validators of `state_a` finds each item's `pubkey`, through a table of the items at the end of `scratch` (a `scratch` without room for it: `LANTERN_BUFFER_TOO_SMALL`). Each item's record: `LANTERN_VALID` when it is eligible (beacon-api.md, registerValidator), else `LANTERN_GOSSIP_IGNORE`; its validator index as the second u64 (0 when it has none); then its SSZ bytes, as for an operation.
  - Each operation in order: lantern_node_gossip of the fork `arg` / 2^16, with a `NodeGossip` of `seen`, the store, `time_ms`, the operation's topic, its subnet, `state_a` as head, no proposer or justified state, and the node's config. Its record: the result's code (u64), the subnet + 2^32 times the member (u64; the member at byte 16 of lantern_node_gossip's `root` for a valid attestation, else 0), then a ByteList of its SSZ bytes (offset 24, `size` 24 + the bytes to a multiple of 8, zero bytes after them).
  - The subscriptions (prepareBeaconCommitteeSubnet, prepareSyncCommitteeSubnets) and prepareBeaconProposer: no gossip validation; each record's code is `LANTERN_VALID` and its subnet 0. An item of `BeaconCommitteeSubscription` whose `committees_at_slot` is 0 or above `MAX_COMMITTEES_PER_SLOT`, or whose `committee_index` is not below it, an item of `SyncCommitteeSubscription` with an index not below `SYNC_COMMITTEE_SIZE`, and a `ProposerPreparation` of another size than 28 bytes give the result `LANTERN_INVALID_ENCODING`.
  - The subnet: 0, but for an attestation compute_subnet_for_attestation(get_committee_count_per_slot(`state_a`, `data.target.epoch`), `data.slot`, the committee index: `data.index` before electra, `committee_index` from electra), as phase0 validator.md places it; an item whose bytes do not hold those fields has subnet 0, and its gossip validation rejects it.
  - Before the first: `seen` with fewer free `keys` entries than the operations (sync committee messages: `SYNC_COMMITTEE_SUBNET_COUNT` times their count) gives `LANTERN_BUFFER_TOO_SMALL`, so that no check of a list adds to `seen` before one is short.
- `NODE_WORK_POOL_CHECK`: lantern_node_gossip of the fork of the store's slot of the topic `arg` for the bytes in `data`, as for `NODE_WORK_API_SUBMIT`, with an empty `Seen` at the end of `scratch` (lantern_seen_init of a `SeenRoom` of `keys` the bytes' length / 8 + 1, and no other room): its result's code is the event's result. A `scratch` without room for that `Seen` and `LANTERN_SCRATCH_FIXED` bytes before it, a lantern_node_gossip of `LANTERN_BUFFER_TOO_SMALL`, and a `state_a` of another fork than the store's slot give `LANTERN_GOSSIP_IGNORE`.
- `NODE_WORK_API_EVENT`: the text of the event of the topic `arg` % 2^8 (beacon-api.md, eventstream), `event: <topic>` LF `data: <JSON>` LF LF, as a ByteList at `NodeEvent_chunk` of the event; the event's `size` then covers it.
  - blob_sidecar and data_column_sidecar: from the sidecar's bytes in `data`: `block_root` lantern_node_sidecar_root of the fork `arg` / 2^16, `index` and the header's `slot` from the bytes; for blob_sidecar `kzg_commitment` and `versioned_hash` (0x01, then the last 31 bytes of crypto_sha256 of the commitment); for data_column_sidecar each commitment of `kzg_commitments`. Bytes of no sidecar of the fork give the result `LANTERN_INVALID_ENCODING`.
  - chain_reorg: `slot`, `new_head_block` and `new_head_state` from lantern_node_event_roots of `state_a`; `old_head_block` lantern_node_block_root of `data` and `old_head_state` its message's `state_root`; `depth` `arg` / 2^16.
  - The operation topics: the JSON of lantern_node_json of the fork `arg` / 2^16, of `data` and the kind of the topic: `NODE_JSON_ATTESTATION`, `NODE_JSON_SINGLE_ATTESTATION`, `NODE_JSON_EXIT`, `NODE_JSON_BLS_CHANGE`, `NODE_JSON_PROPOSER_SLASHING`, `NODE_JSON_ATTESTER_SLASHING` or `NODE_JSON_CONTRIBUTION_AND_PROOF`, with a `JsonCursor` in `scratch`. A status of it but `LANTERN_OK` and `LANTERN_BUFFER_TOO_SMALL` gives the result `LANTERN_INVALID_ENCODING`.
  - light_client_finality_update and light_client_optimistic_update: `{"version":"<fork>","data":<data>}` of lantern_lc_read of `state_c` (`LC_OBJECT_FINALITY_UPDATE`, `LC_OBJECT_OPTIMISTIC_UPDATE`), the data the JSON of its bytes by lantern_node_json of its fork (`NODE_JSON_LC_FINALITY_UPDATE`, `NODE_JSON_LC_OPTIMISTIC_UPDATE`), in `scratch`. No update gives the result `LANTERN_NO_STATE_ANSWER`.
  - head: lantern_node_event_roots of the fork of the slot of `state_a`, with the node's config: `block`, `state` and the two dependent roots; `slot` the state's; `epoch_transition` and `execution_optimistic` from `arg` / 2^8 (1 and 2).
  - finalized_checkpoint: with `data`, the block's root by lantern_node_block_root of the fork of its slot and its message's `state_root`; else the block root and state root of lantern_node_event_roots of `state_a`. `epoch` `arg` / 2^16; `execution_optimistic` from `arg` / 2^8 % 2^8 (2). Bytes that do not hold a block give `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_API_LOOKUP`: the slot whose state on the chain of `state_a` has the root in the first 32 bytes of the `cursor` of the `NodeApi` entry at index `arg`, at `NodeEvent_index`: the slot of `state_a` when it is lantern_state_root of the fork of its slot (with the `StateCache` of the node's config), else the slot s below it, at most `SLOTS_PER_HISTORICAL_ROOT` below, whose entry s % `SLOTS_PER_HISTORICAL_ROOT` of its `state_roots` it is, the highest; else 2^64 - 1. An index past the api part, or of an entry without `API_STREAM_LOOKUP`, gives 2^64 - 1.
- `NODE_WORK_API_CHUNK`: the next chunk of the answer of the `NodeApi` entry at index `arg` (beacon-api.md, Common rules, the streamed answers), from the SSZ bytes in `data`, at `NodeEvent_api` of the event: the entry's `sent` and `flags` and its `cursor` after the chunk, then a ByteList of the chunk's bytes at `NodeEvent_api_bytes`, offset 24; the event's `size` then covers it.
  - A chunk is at most `NODE_API_CHUNK` (65536) bytes, and at most the room of the event after the ByteList's header. With less than `NODE_API_FIRST_ROOM` (1024) bytes of room for the first chunk, or 64 for a later one (1024 for a validator stream, which writes an item in each chunk): `LANTERN_BUFFER_TOO_SMALL`.
  - The first chunk, without `API_STREAM_STARTED`: the head of the answer, then as much of the body as fits; it sets `API_STREAM_STARTED`. A later chunk goes on with the body.
  - `data` of no bytes, or whose slot is not the entry's `slot` (a state's u64 at byte 40, a `SignedBeaconBlock`'s at byte 100; of produceBlockV3 a `BeaconBlock`'s at byte 0, and from deneb at the offset in the first 4 bytes of the `BlockContents`, and with `API_STREAM_PRODUCE_BLINDED` a `BlindedBeaconBlock`'s at byte 0), gives the result `LANTERN_INVALID_ENCODING`.
  - The pending streams: the items of lantern_node_pending of the fork `fork` of `state_a` (`kind` 0 for getPendingDeposits, 1 getPendingPartialWithdrawals, 2 getPendingConsolidations). JSON: the head and `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[`, then from the index at byte 0 of the cursor (`position`) the JSON of each item as many as fit, with `,` between, then `]}`; `position` then the next index. SSZ: the items' bytes, as the SSZ bytes of a getStateV2 (their count times their size is the `Content-Length`), from `sent`. A `state_a` whose slot is not the entry's gives the result `LANTERN_INVALID_SLOT`, and `LANTERN_NO_STATE_ANSWER` of lantern_node_pending the result `LANTERN_INVALID_ENCODING`.
  - The validator streams: the items of the validators of `state_a` from the index at byte 0 of the cursor (`position`), with the status bits at byte 8 of it and the `ValidatorRef` items of `data` (none with `data` 0), as many as fit; `position` then the next index. A `state_a` whose slot is not the entry's gives the result `LANTERN_INVALID_SLOT`.
  - Their `scratch`: 8 bytes for every 64 validators, a bit for each that the items name; with public keys among the items, 8 bytes more for each slot of a table of the keys, the least power of two at least twice their count.
  - getEpochCommittees: the committees of `state_a` (lantern_get_beacon_committee of the fork of the state's slot, with the node's `CommitteeCache`) from the slot at byte 0 of the cursor and the index at byte 8, and within a committee from the member at byte 16, as many as fit; get_committee_count_per_slot of the epoch at byte 56. In the first chunk, an `index` at or past that count gives the error 400 as the whole answer. Its `scratch`: a list of (validators / (SLOTS_PER_EPOCH * the count) + 1) u64, then that of lantern_get_beacon_committee.
  - The sidecar streams: as JSON, the head and `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[`, the fork `fork`; then, with `data`, the JSON of its bytes by lantern_node_json of the fork `fork`, `NODE_JSON_BLOB_SIDECAR` or `NODE_JSON_DATA_COLUMN_SIDECAR`, from `cursor`, after `,` when `API_STREAM_ITEMS` is set and the cursor is at its start; once it is whole, `API_STREAM_ITEMS` and `API_STREAM_ITEM_DONE`. With `data` 0: `]}`. As SSZ, the head, then the bytes of `data` from `sent`; at their end `API_STREAM_ITEM_DONE`; with `data` 0, nothing more. The answer, whole after the first chunk or not, as a JSON answer; a chunk holds one sidecar at most.
  - The blob stream: as JSON, the head and `{"execution_optimistic":…,"finalized":…,"data":[`, with no `Eth-Consensus-Version`; as SSZ, the head. With `data` 0: as JSON `]}`, as SSZ nothing more, and `API_STREAM_DONE`. `state_a`: the versioned hashes (Root items of a ByteList), or 0 for every blob. A blob starts with `,` when `API_STREAM_ITEMS` is set, then `"0x`, as JSON; its bytes follow, as lower case hex as JSON; as JSON `"` follows its last byte; at its end, `API_STREAM_ITEMS`.
    - Deneb and electra: `data` a `BlobSidecar`. At `sent` 0, with `state_a`, when lantern_kzg_commitment_to_versioned_hash of its `kzg_commitment` is none of the items: no bytes, and `API_STREAM_ITEM_DONE`. Else its `blob` from `sent`, as many bytes as fit; at its end `API_STREAM_ITEM_DONE`.
    - Fulu: `data` a `DataColumnSidecar`, b `filter_slot`, c `member`. At c 0 and `sent` 0: b at or past the count of its `kzg_commitments`, the answer's end, as with `data` 0; with `state_a`, when the versioned hash of commitment b is none of the items, no bytes, `API_STREAM_ITEM_DONE` and `API_STREAM_BLOB_SKIP`. Else cell b of its `column` from `sent`, as many bytes as fit; at its end `API_STREAM_ITEM_DONE`. Cells 0 to `NUMBER_OF_COLUMNS` / 2 - 1 in turn are the blob (beacon-api.md, getBlobs). A b past the cells of `column` gives the result `LANTERN_INVALID_ENCODING`.
    - A first chunk with the whole answer has `Content-Length`; else the coding of the sidecar streams. A chunk holds the bytes of one sidecar at most.
  - getBlockHeaders: the head and `{"execution_optimistic":…,"finalized":…,"data":[`, the flags of the entry; then, with `data` or `state_a`, the item `{"root":…,"canonical":…,"header":…}` after `,` when `API_STREAM_ITEMS` is set, its root at byte 0 of `cursor`, `canonical` `member`, and the header as getBlockHeader's of `data`, else of `state_a`, at the end of `scratch`; then `API_STREAM_ITEMS` and `API_STREAM_ITEM_DONE` in the event. With neither: `]}`, and `API_STREAM_DONE`. A chunk holds one item at most.
  - The pool streams: the head and `{"data":[` (getPoolAttesterSlashingsV2 and getPoolAttestationsV2: `{"version":"<fork>","data":[`, the fork `fork`); then, with `data`, the JSON of the bytes of the pool entry at `slot` by lantern_node_json of the entry's fork (`sent`) and the kind of the GET's topic, from `cursor`, after `,` when `API_STREAM_ITEMS` is set; once it is whole, `API_STREAM_ITEMS` and `API_STREAM_ITEM_DONE` in the event. With `data` 0: `]}`, and `API_STREAM_DONE`. A chunk holds the JSON of one entry at most.
  - getPoolAttestationsV2, an entry of a fork from electra: its bytes are a `SingleAttestation`, and the JSON is that of the electra `Attestation` of it, written at the end of `scratch` (`NODE_POOL_ATTESTATION_ROOM`, 1024 bytes): `aggregation_bits` of the committee's length (`member` / 2^16) with the bit at the attester's place (`member` % 2^16), its `data` and `signature`, and `committee_bits` with the bit of its `committee_index`, as the spec's aggregation of a single attester gives it. Bytes that are no `SingleAttestation`, a member of a place not below the length or of a length above `MAX_VALIDATORS_PER_COMMITTEE`, and a `committee_index` not below `MAX_COMMITTEES_PER_SLOT` give the result `LANTERN_INVALID_ENCODING`.
  - SSZ: the bytes of `data` from `sent`; `sent` counts them.
  - JSON: the body's start, then lantern_json_encode_ssz of `cursor` (lantern_node_json of the fork of the entry, `SignedBeaconBlock` for getBlockV2 and `BeaconState` for getStateV2), then `}` once the cursor is whole. getBlindedBlock: lantern_node_blinded_block of the fork of the entry, of `data`, into a ByteList at the end of `scratch` with room for the bytes of `data` + 1024 (a header's SSZ bytes, at most 616, are at most 108 more than its payload's), then its SSZ bytes, or its JSON by lantern_node_json of `NODE_JSON_BLINDED_BLOCK`, as the bytes of getBlockV2; each chunk makes it again from `data`. getBlockAttestationsV2: the fork's `Attestations` (`NODE_JSON_ATTESTATIONS`) of the bytes of the body's `attestations` in `data`, the same in every fork: the message from the 4-byte offset at byte 0, its body from the offset at byte 80 of the message, the list from the offset at byte 208 of the body to the offset at byte 212 (`deposits`), its bytes copied into a ByteList at the end of `scratch`. Offsets past the bytes or out of order give the result `LANTERN_INVALID_ENCODING`; a `scratch` without room for that ByteList, `LANTERN_BUFFER_TOO_SMALL`. A first chunk that holds the whole body has `Content-Length`; else, with `API_STREAM_HTTP10`, it sets `API_STREAM_CLOSE`, and else `API_STREAM_CHUNKED`, and each chunk then holds the body's bytes in one chunk of RFC 9112 section 7.1, the last also `0` CRLF CRLF.
  - produceBlockV3: the JSON of lantern_node_json of `NODE_JSON_BEACON_BLOCK`, from deneb `NODE_JSON_BLOCK_CONTENTS`, and with `API_STREAM_PRODUCE_BLINDED` `NODE_JSON_BLINDED_BEACON_BLOCK`; the head's fields and the body's start of beacon-api.md, `true` for the blinded block.
  - The chunk that ends the body sets `API_STREAM_DONE`.
  - getAggregatedAttestationV2: the room of a pool stream's chunk. The aggregate in `cursor`: the root at byte 0, the count at 32, the committee length at 40, `data` at 48, `signature` at 176, the bits from 272.
  - With `API_STREAM_FOLD` and `data`: no bytes, and `API_STREAM_ITEM_DONE`. `data` is the pool entry's: of the fork `sent` from electra a `SingleAttestation` (240 bytes) with its place `member` % 2^16 and its committee's length `member` / 2^16, before electra an `Attestation` (the offset 228, at most 228 + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1 bytes) with its first bit set as its place and its bits' length. The entry joins when lantern_node_data_root of the fork `fork` of its `data` is the root, and, after the first, its length is the aggregate's and its place's bit is clear: the first gives the length, `data` and `signature`; a later one's signature is added by crypto_bls_aggregate of a `BlsSignatureList` of the two at the end of `scratch`. Its place's bit is set and the count goes up. Bytes that are no such attestation, a length above `MAX_VALIDATORS_PER_COMMITTEE`, a place not below the length, and a signature crypto_bls_aggregate rejects give the result `LANTERN_INVALID_ENCODING`.
  - With `API_STREAM_FOLD` and `data` 0: a count of 0, the error 404; `API_STREAM_OPTIMISTIC`, the error 503; each as the whole answer, with `API_STREAM_DONE`. Else the chunk's bytes are the SSZ bytes of the `Attestation` of the fork `fork`: `aggregation_bits` of the length with the aggregate's bits, `data`, `signature`, from electra `committee_bits` with the bit of `filter_index` (one not below `MAX_COMMITTEES_PER_SLOT` gives the result `LANTERN_INVALID_ENCODING`); they fit the first chunk's room (the build checks it).
  - produceSyncCommitteeContribution, with `API_STREAM_FOLD` and `data`: no bytes, and `API_STREAM_ITEM_DONE`. `data` is a `SyncCommitteeMessage` (144 bytes) whose `beacon_block_root` is that at byte 0 of `cursor`: its places in the subcommittee `filter_index` (lantern_node_sync_positions of the fork `fork` of `state_a` and its `validator_index`), when none is set in the bits at byte 144 of `cursor`, are set there, and for each its `signature` joins the one at byte 48 (the first is copied, a later one added by crypto_bls_aggregate of a `BlsSignatureList` of the two at the end of `scratch`); byte 32 counts the places. Bytes of another size, no `state_a`, and a signature crypto_bls_aggregate rejects give the result `LANTERN_INVALID_ENCODING`. With `data` 0, as for getAggregatedAttestationV2, the bytes of the `SyncCommitteeContribution`: `slot` `filter_slot`, the root, `subcommittee_index` `filter_index`, the bits, the signature.
  - Without `API_STREAM_FOLD`: the answer from `data`, as getBlockV2's: as SSZ its bytes with `Content-Length`; as JSON the head and `{"version":"<fork>","data":`, the JSON by lantern_node_json of the fork `fork` and `NODE_JSON_ATTESTATION` from `cursor`, and `}`; produceSyncCommitteeContribution: `{"data":`, `NODE_JSON_SYNC_CONTRIBUTION`, and no `Eth-Consensus-Version`. `data` 0 gives the result `LANTERN_INVALID_ENCODING`.
- Bytes too short for their type give the result `LANTERN_INVALID_ENCODING`.

## Function `lantern_node_protocols`

The protocol IDs of every req/resp method and version of [req-resp.md](req-resp.md), by method, then by version: the protocol list of the node's libp2p config. A `STREAM_INBOUND` names its protocol by its index here.

### Signature

```
lantern_node_protocols(out, count) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `out` | output | ByteList of asm-libp2p `ProtocolEntry` values, its `size` set |
| `count` | output | u64 |

### Returns

- `LANTERN_OK`: `out` holds the entries and `count` their number.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer entries.

## Function `lantern_node_import`

Decodes a `SignedBeaconBlock` with the fork's types, then lantern_on_block.

### Signature

```
lantern_node_import(store, node, data, state, options, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `node` | input | `Node` |
| `data` | input | ByteList: the block's SSZ bytes |
| `state` | state | `BeaconState`: a copy of the parent's post-state |
| `options` | state | `BlockOptions` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is that of lantern_on_block, or `LANTERN_INVALID_ENCODING` when `data` is no `SignedBeaconBlock`.
- `LANTERN_BUFFER_TOO_SMALL` and `LANTERN_NEED_JUSTIFIED_STATE`: as lantern_on_block, or `scratch` cannot hold the decoded block.

### Function does

- Decodes into the end of `scratch` and passes the rest to lantern_on_block; the scratch `size` is restored on return.
- Bellatrix: sets `pow_block` and `pow_parent` of `options` from the node's `PowBlock` entries.

### ABI

- Export: `lantern_<fork>_node_import` of each fork object.

## Function `lantern_node_block_root`

hash_tree_root of the message of a `SignedBeaconBlock` in SSZ bytes.

### Signature

```
lantern_node_block_root(data, scratch, root, result, blobs) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList |
| `scratch` | scratch | `Scratch` |
| `root` | output | Root |
| `result` | output | `Result` |
| `blobs` | output | u64 |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `root` holds the root and `blobs` the length of the body's `blob_kzg_commitments` (0 before deneb), or `result` is `LANTERN_INVALID_ENCODING`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` cannot hold the decoded block.

### ABI

- Export: `lantern_<fork>_node_block_root` of each fork object.

## Function `lantern_node_proposers`

The proposers of the epoch of a state at the epoch's first slot, and the epoch's dependent root (beacon-api.md, getProposerDuties).

### Signature

```
lantern_node_proposers(state, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork, at the first slot of an epoch |
| `config` | input | `Config`: its `StateCache` |
| `scratch` | scratch | `Scratch` |
| `out` | output | 32 bytes, the dependent root; then `SLOTS_PER_EPOCH` u64, the proposer of each slot |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_INVALID_SLOT`: the state's slot is not the first of an epoch.
- `LANTERN_INVALID_VALIDATOR_INDEX`: from fulu, an entry of `proposer_lookahead` names no validator of the state.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(2) bytes.
- The statuses of lantern_get_beacon_proposer_indices and lantern_state_root.

### Function does

- The dependent root: get_block_root_at_slot(state, slot - 1); at slot 0, hash_tree_root of `latest_block_header` with lantern_state_root of the state as `state_root` when it is zero.
- The proposers: from fulu, the first `SLOTS_PER_EPOCH` entries of `proposer_lookahead`; before, lantern_get_beacon_proposer_indices of the epoch, which every fork object exports for this function.

### ABI

- Export: `lantern_<fork>_node_proposers` of each fork object.
- Argument order: `state`, `config`, `scratch`, `out`.

## Function `lantern_node_attestation_data`

The `AttestationData` that a validator of the state's slot makes (beacon-api.md, produceAttestationData).

### Signature

```
lantern_node_attestation_data(state, config, index, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork: the state of the chain at the assigned slot |
| `config` | input | `Config`: its `StateCache` |
| `index` | input | u64: the committee index |
| `scratch` | scratch | `Scratch` |
| `out` | output | 128 bytes: the SSZ encoding of the `AttestationData` |

### Returns

- `LANTERN_OK`: `out` holds it.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(2) bytes.
- The statuses of lantern_node_event_roots.

### Function does

- `slot`: the state's slot. `index`: `index` before electra, 0 from electra.
- `beacon_block_root`: the block root of lantern_node_event_roots of the state.
- `source`: the state's `current_justified_checkpoint`.
- `target`: the epoch of the state's slot; its root the block root when the slot is the epoch's first, else get_block_root(state, epoch), the `block_roots` entry of the epoch's first slot.

### ABI

- Export: `lantern_<fork>_node_attestation_data` of each fork object.
- Argument order: `state`, `config`, `index`, `scratch`, `out`.

## Function `lantern_node_attester_duties`

The committee assignments of validators in the epoch of a state at the epoch's first slot (beacon-api.md, getAttesterDuties).

### Signature

```
lantern_node_attester_duties(state, config, ids, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork, at the first slot of an epoch |
| `config` | input | `Config`: its `StateCache` and `CommitteeCache` |
| `ids` | input | ByteList of `ValidatorRef` items of `API_VALIDATOR_INDEX` |
| `scratch` | scratch | `Scratch` |
| `out` | output | 32 bytes, the dependent root; u64 the committees at a slot; then for each item of `ids`, 6 u64: 1 with an assignment else 0, its slot, committee index, committee length, place in the committee, and the validator index |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_INVALID_SLOT`: the state's slot is not the first of an epoch.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(2) bytes, a bit for each validator, and the room of lantern_get_beacon_committee.
- The statuses of lantern_node_event_roots, lantern_get_committee_count_per_slot and lantern_get_beacon_committee.

### Function does

- The dependent root: the previous duty dependent root of lantern_node_event_roots of the state.
- The committees at a slot: get_committee_count_per_slot(state, epoch).
- Each committee of each slot of the epoch, in order, with lantern_get_beacon_committee and the `CommitteeCache`; each member that an item names (a bit set for each item's index below the validator count) gives each such item its assignment, as get_committee_assignment finds it.

### ABI

- Export: `lantern_<fork>_node_attester_duties` of each fork object.
- Argument order: `state`, `config`, `ids`, `scratch`, `out`.

## Function `lantern_node_liveness`

Whether validators were seen live in an epoch, from a state and a `Seen` (beacon-api.md, getLiveness).

### Signature

```
lantern_node_liveness(state, config, seen, ids, epoch, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork |
| `config` | input | `Config`: its `CommitteeCache` |
| `seen` | input | `Seen` of [networking.md](networking.md#type-seen) |
| `ids` | input | ByteList of `ValidatorRef` items of `API_VALIDATOR_INDEX` |
| `epoch` | input | u64 |
| `scratch` | scratch | `Scratch` |
| `out` | output | A byte for each item of `ids`: 1 when its validator is live in `epoch`, else 0 |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short of the room under Limits.
- In phase0, the statuses of lantern_get_attesting_indices.

### Function does

- A byte for each validator of the state, in `scratch`, starts at 0.
- `epoch` the state's current epoch (get_current_epoch): from altair, the byte of each validator whose `current_epoch_participation` flags are not 0 is set; in phase0, the byte of each index of lantern_get_attesting_indices of each entry of `current_epoch_attestations`, with the `CommitteeCache`.
- `epoch` the state's previous epoch (get_previous_epoch): the same with `previous_epoch_participation` and `previous_epoch_attestations`. At epoch 0 both rules apply.
- Each `SeenKey` of `seen` whose `b` is below the state's validator count sets the byte of `b` when its kind is `SEEN_ATTESTATION` or `SEEN_AGGREGATOR_EPOCH` and `a` is `epoch`, or its kind is `SEEN_PROPOSER_SLOT`, `SEEN_SYNC_MESSAGE` or `SEEN_SYNC_CONTRIBUTION` and compute_epoch_at_slot(`a`) is `epoch`.
- Each item of `ids`: the byte of its index; 0 for an index at or past the validator count.

### Function never

- Writes `seen` or `state`.

### Limits

- Scratch: S(1) from altair; S(6) in phase0, the bytes and the attesting indices of one attestation, then the S(4) of lantern_get_attesting_indices.

### ABI

- Export: `lantern_<fork>_node_liveness` of each fork object.
- Argument order: `state`, `config`, `seen`, `ids`, `epoch`, `scratch`, `out`.

## Function `lantern_node_block_rewards`

The proposer's rewards of a block, part by part, on its pre-state (beacon-api.md, getBlockRewards).

### Signature

```
lantern_node_block_rewards(pre, block, early, late, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork at the block's slot: P |
| `block` | input | ByteList of the SSZ bytes of a `SignedBeaconBlock` of the fork |
| `early` | input | Phase0: the `BeaconState` E of the attestations of the epoch before the block's, at the last slot of the block's epoch; 0 at epoch 0. From altair: 0 |
| `late` | input | Phase0: the E of the attestations of the block's epoch, at the last slot of the next epoch, when that epoch is of phase0; else 0. From altair: 0 |
| `config` | input | `Config`: its fork epochs and its `CommitteeCache` |
| `scratch` | scratch | `Scratch` |
| `out` | output | 48 bytes: `proposer_index`, `total`, `attestations`, `sync_aggregate`, `proposer_slashings` and `attester_slashings`, each a u64 |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_INVALID_ENCODING`: `block` holds no `SignedBeaconBlock` of the fork, or a validator index of it is not below the validator count of `pre`.
- `LANTERN_INVALID_SLOT`: `pre` is not at the block's slot. In phase0: an attestation's target epoch is neither the block's epoch nor the one before; or the E it needs is 0, or not at the last slot of its epoch, while the fork of the slot after it is phase0.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short of the room under Limits.
- The statuses of lantern_get_attesting_indices.

### Function does

- The values of beacon-api.md, getBlockRewards.
- A byte for each validator of `pre`, in `scratch`, marks the validators the body's slashings slash, in the body's order: the proposer slashings, then the attester slashings.
- From altair: a copy of `previous_epoch_participation` and of `current_epoch_participation`, in `scratch`, takes the flags of each attestation in order, as process_attestation sets them.
- In phase0: a byte for each validator of `pre`, in `scratch`, marks the attesters the block rewarded already; and for each of `early` and `late` that is not 0, a byte for each validator holds the lowest `inclusion_delay` of the attestations of its `previous_epoch_attestations` that have the validator among their attesting indices, or 255 for none.

### Function never

- Writes `pre`, `early`, `late` or `block`.

### Limits

- Scratch: S(6) of the validator count of `pre`, and in phase0 of each of `early` and `late` that is not 0: S(1) for the bytes of the validators, S(1) for the attesting indices of one attestation, and the S(4) of lantern_get_attesting_indices. The decoded block takes the end of `scratch` first.

### ABI

- Export: `lantern_<fork>_node_block_rewards` of each fork object.
- Argument order: `pre`, `block`, `early`, `late`, `config`, `scratch`, `out`.

## Function `lantern_node_sync_rewards`

The balance changes of a block's sync aggregate, on its pre-state (beacon-api.md, getSyncCommitteeRewards).

### Signature

```
lantern_node_sync_rewards(pre, block, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork at the block's slot: P |
| `block` | input | ByteList of the SSZ bytes of a `SignedBeaconBlock` of the fork |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList, its `size` set by the caller: 16 bytes for each member, each once, in validator index order: its index (u64) and its reward (two's complement i64) |

### Returns

- `LANTERN_OK`: `out` holds the items.
- `LANTERN_NO_STATE_ANSWER`: the fork is phase0, which has no sync committee.
- `LANTERN_INVALID_ENCODING`: `block` holds no `SignedBeaconBlock` of the fork, or a pubkey of `current_sync_committee` is that of no validator.
- `LANTERN_INVALID_SLOT`: `pre` is not at the block's slot.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than 24 + 16 * `SYNC_COMMITTEE_SIZE` bytes, or `scratch` is short of the room under Limits.

### Function does

- The values of beacon-api.md, getSyncCommitteeRewards.
- The places' validators: as process_sync_aggregate's committee_indices (block-processing.md).
- The members' balances: entries of 16 bytes in `scratch`, each a member's index and its balance, the proposer's once more when it is a member.

### Function never

- Writes `pre` or `block`.

### Limits

- Scratch: S(1), then at its end, before the decoded block, 8 * `SYNC_COMMITTEE_SIZE` bytes for the places and `SYNC_TABLE_BYTES` + 24 for the hash table of process_sync_aggregate's committee_indices, where the entries go after it.

### ABI

- Export: `lantern_<fork>_node_sync_rewards` of each fork object.
- Argument order: `pre`, `block`, `scratch`, `out`.

## Function `lantern_node_reward_totals`

The totals of the attestation rewards that process_rewards_and_penalties pays for the previous epoch of a state (beacon-api.md, getAttestationsRewards).

### Signature

```
lantern_node_reward_totals(state, config, mode, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork: S |
| `config` | input | `Config`: its `INACTIVITY_SCORE_BIAS`, `INACTIVITY_SCORE_RECOVERY_RATE` and `CommitteeCache` |
| `mode` | input | u64: 0, the state as it is; 1, the steps of process_epoch before process_rewards_and_penalties too |
| `scratch` | scratch | `Scratch` |
| `out` | output | 96 bytes, the totals: below |

### Returns

- `LANTERN_OK`: `out` holds the totals.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short of the room under Limits.
- The statuses of the functions it calls, as lantern_get_block_root's.

### Function does

- `out`, each a u64: at 0 get_previous_epoch; at 8 get_finality_delay; at 16 1 in an inactivity leak (that delay above `MIN_EPOCHS_TO_INACTIVITY_PENALTY`), else 0; at 24 get_total_active_balance; at 32 from altair get_base_reward_per_increment, in phase0 integer_squareroot of the total active balance; at 40, 48 and 56 the balances of the source, target and head votes of the previous epoch (from altair get_total_balance of get_unslashed_participating_indices of each flag; in phase0 lantern_get_attesting_balance of the matching source, target and head attestations); at 64 `mode`; at 72 the largest effective balance of the fork of the previous epoch (`MAX_EFFECTIVE_BALANCE_ELECTRA` from electra, else `MAX_EFFECTIVE_BALANCE`; in electra, a previous epoch below the epoch of the state's `fork` is deneb's); at 80 and 88 `INACTIVITY_SCORE_BIAS` and `INACTIVITY_SCORE_RECOVERY_RATE` of the config.
- Mode 1: the finality delay of the finalized checkpoint that process_justification_and_finalization would leave, from the state's justification bits and checkpoints and the target balances of the previous and current epochs; the state keeps its bytes.

### Function never

- Writes `state`.

### Limits

- Scratch: S(3); in phase0 S(6) and the matching attestations.

### ABI

- Export: `lantern_<fork>_node_reward_totals` of each fork object.
- Argument order: `state`, `config`, `mode`, `scratch`, `out`.

## Function `lantern_node_attestation_rewards`

The attestation rewards of the validators `first` to `first` + `count` - 1 of a state, with its totals (beacon-api.md, getAttestationsRewards).

### Signature

```
lantern_node_attestation_rewards(state, config, totals, first, count, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork: S |
| `config` | input | `Config`: its `CommitteeCache` |
| `totals` | input | The 96 bytes of lantern_node_reward_totals of `state` |
| `first` | input | u64 |
| `count` | input | u64 |
| `scratch` | scratch | `Scratch` |
| `out` | output | 48 bytes for each validator: `head`, `target` and `source` (i64), `inclusion_delay` (u64), `inactivity` (i64), and 1 when it is eligible, else 0 (u64) |

### Returns

- `LANTERN_OK`: `out` holds the items.
- `LANTERN_INVALID_ENCODING`: `first` + `count` is past the validators.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short of the room under Limits.
- In phase0, the statuses of lantern_get_attesting_indices and lantern_get_block_root.

### Function does

- The values of beacon-api.md, getAttestationsRewards, `total_rewards`; all 0 for a validator that is not eligible (get_eligible_validator_indices).
- Mode 1, from altair: the inactivity score of each eligible validator as process_inactivity_updates leaves it, from its score, its timely target flag and whether the totals are in a leak.
- Phase0: for the validators of the window, a byte each of the matching source, target and head attestations of the previous epoch that hold them, and a byte of the lowest `inclusion_delay` among the source ones, from one walk of `previous_epoch_attestations`.

### Function never

- Writes `state` or `totals`.

### Limits

- Scratch: S(1) from altair; in phase0 S(6), 2 bytes for each validator of the window, and the matching attestations.

### ABI

- Export: `lantern_<fork>_node_attestation_rewards` of each fork object.
- Argument order: `state`, `config`, `totals`, `first`, `count`, `scratch`, `out`.

## Function `lantern_node_ideal_reward`

The attestation rewards of a validator of an effective balance that voted for all three in time, with the totals of a state (beacon-api.md, getAttestationsRewards, `ideal_rewards`).

### Signature

```
lantern_node_ideal_reward(totals, effective_balance, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `totals` | input | The 96 bytes of lantern_node_reward_totals |
| `effective_balance` | input | u64 |
| `out` | output | 48 bytes: as an item of lantern_node_attestation_rewards, with the effective balance in place of eligible |

### Returns

- `LANTERN_OK`: `out` holds the item.

### ABI

- Export: `lantern_<fork>_node_ideal_reward` of each fork object.
- Argument order: `totals`, `effective_balance`, `out`.

## Function `lantern_node_payload_parent`

The parent of the next payload: the `block_number` and `block_hash` of a state's `latest_execution_payload_header` (beacon-api.md, eventstream: payload_attributes).

### Signature

```
lantern_node_payload_parent(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork |
| `out` | output | 40 bytes: u64 the block number, then the 32 bytes of the block hash |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_INVALID_EVENT`: a fork before bellatrix.

### ABI

- Export: `lantern_<fork>_node_payload_parent` of each fork object.
- Argument order: `state`, `out`.

## Function `lantern_node_sidecar_root`

The block root of a sidecar: hash_tree_root of its `signed_block_header.message` (beacon-api.md, eventstream: blob_sidecar and data_column_sidecar).

### Signature

```
lantern_node_sidecar_root(ssz, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ssz` | input | ByteList: the SSZ bytes of a `BlobSidecar` (deneb, electra) or a `DataColumnSidecar` (from fulu) |
| `scratch` | scratch | `Scratch` |
| `out` | output | 32 bytes: the root |

### Returns

- `LANTERN_OK`: `out` holds the root.
- `LANTERN_INVALID_ENCODING`: a `BlobSidecar` of another length than its fixed size; a `DataColumnSidecar` shorter than its fixed part.
- `LANTERN_INVALID_EVENT`: a fork before deneb.
- The statuses of ssz_hash_tree_root.

### Function does

- The header: at byte 8 + `BYTES_PER_BLOB` + 96 of a `BlobSidecar`; at byte 20 of a `DataColumnSidecar`, after its index and three offsets.
- ssz_hash_tree_root of `BeaconBlockHeader` of its 112 bytes, whose layout is that of the value.

### ABI

- Export: `lantern_<fork>_node_sidecar_root` of each fork object.
- Argument order: `ssz`, `scratch`, `out`.

## Function `lantern_node_randao`

The RANDAO mix of an epoch in a state (beacon-api.md, getStateRandao).

### Signature

```
lantern_node_randao(state, epoch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork |
| `epoch` | input | u64: the epoch, or 2^64 - 1 for the epoch of the state's slot |
| `out` | output | 32 bytes: the mix |

### Returns

- `LANTERN_OK`: `out` holds get_randao_mix(state, epoch).
- `LANTERN_NO_STATE_ANSWER`: the epoch is above the state's epoch, or EPOCHS_PER_HISTORICAL_VECTOR or more below it.

### Function does

- get_randao_mix reads `randao_mixes[epoch % EPOCHS_PER_HISTORICAL_VECTOR]`, which holds the mix of `epoch` only from the state's epoch - EPOCHS_PER_HISTORICAL_VECTOR + 1 to the state's epoch; Lighthouse v8.3.3 takes the same range (get_randao_mix_index).

### ABI

- Export: `lantern_<fork>_node_randao` of each fork object.
- Argument order: `state`, `epoch`, `out`.

## Function `lantern_node_sync_committee`

The validator indices of a state's sync committee of an epoch (beacon-api.md, getEpochSyncCommittees).

### Signature

```
lantern_node_sync_committee(state, epoch, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork |
| `epoch` | input | u64: the epoch, or 2^64 - 1 for the epoch of the state's slot |
| `scratch` | scratch | `Scratch` |
| `out` | output | SYNC_COMMITTEE_SIZE u64: the index of each member, in the committee's order |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_NO_STATE_ANSWER`: the fork is phase0, or the epoch's sync committee period is neither that of the state's epoch nor the next.
- `LANTERN_INVALID_ENCODING`: a member's key is the key of no validator of the state.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than the bytes of the key table below.

### Function does

- The committee: `current_sync_committee` for the period of the state's epoch, `next_sync_committee` for the next (compute_sync_committee_period); Lighthouse v8.3.3 takes the same two (get_built_sync_committee).
- Each member's index: all_pubkeys.index(pubkey), the first validator with the key, as process_sync_aggregate finds it (block-processing.md), with the key table at the end of `scratch`.

### ABI

- Export: `lantern_<fork>_node_sync_committee` of each fork object.
- Argument order: `state`, `epoch`, `scratch`, `out`.

## Function `lantern_node_proposer_lookahead`

A state's `proposer_lookahead` (beacon-api.md, getProposerLookahead).

### Signature

```
lantern_node_proposer_lookahead(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork |
| `out` | output | (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH u64: the proposer of each slot from the state's epoch's first |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_NO_STATE_ANSWER`: the fork is before fulu, whose `BeaconState` has no `proposer_lookahead`.

### ABI

- Export: `lantern_<fork>_node_proposer_lookahead` of each fork object.
- Argument order: `state`, `out`.

## Function `lantern_node_weights`

get_weight of each node of a store (beacon-api.md, getDebugForkChoice).

### Signature

```
lantern_node_weights(store, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | `Store` |
| `scratch` | scratch | `Scratch`: 8 bytes a node, at its end |
| `out` | output | a u64 for each node of the store's `blocks`, in their order |

### Returns

- `LANTERN_OK`: `out` holds get_weight of each node.
- `LANTERN_BUFFER_TOO_SMALL`: scratch is short.
- `LANTERN_NEED_JUSTIFIED_STATE`: the store's balances are not those of its justified checkpoint (fork-choice.md, Common rules).
- `LANTERN_INVALID_UNKNOWN_BLOCK`, `LANTERN_INVALID_OVERFLOW`: a failure of the proposer boost's node or get_proposer_score, or a weight past 2^64 - 1.

### Function does

- The weights of all nodes at once, as lantern_get_head computes them (fork-choice.md), for every node of the store: each the weight lantern_get_weight gives the node.

### Caller must

- Keep `out` apart from `scratch`.

### ABI

- Export: `lantern_<fork>_node_weights` of each fork object.
- Argument order: `store`, `scratch`, `out`.

## Function `lantern_node_data_root`

hash_tree_root of an `AttestationData` in SSZ bytes (beacon-api.md, getAggregatedAttestationV2).

### Signature

```
lantern_node_data_root(data, scratch, root) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | the 128 SSZ bytes of an `AttestationData` |
| `scratch` | scratch | `Scratch` |
| `root` | output | Root |

### Returns

- `LANTERN_OK`: `root` holds hash_tree_root of the `AttestationData`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short for ssz_hash_tree_root.

### Function does

- ssz_hash_tree_root of the fork's `AttestationData` type, whose value is its 128 SSZ bytes (the build checks the layout).

### Tests

- The runner checks it against the root of each `ssz_static` case of `AttestationData`.

### ABI

- Export: `lantern_<fork>_node_data_root` of each fork object.
- Argument order: `data`, `scratch`, `root`.

## Function `lantern_node_sync_subnets`

compute_subnets_for_sync_committee (altair validator.md) of a validator (beacon-api.md, submitPoolSyncCommitteeSignatures).

### Signature

```
lantern_node_sync_subnets(state, validator_index, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `validator_index` | input | u64 |
| `out` | output | u64: bit i for subnet i |

### Returns

- `LANTERN_OK`: `out` holds the subnets: the sync committee is `current_sync_committee` when the period of the state's epoch is that of the epoch of its slot + 1, else `next_sync_committee`; subnet i for each place p of the validator's public key in its `pubkeys` with p / (SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT) = i. 0 for an index past the validators, and before altair.

### Tests

- The node-api cases of submitPoolSyncCommitteeSignatures: their answers and publishes come from the spec module's compute_subnets_for_sync_committee.

### ABI

- Export: `lantern_<fork>_node_sync_subnets` of each fork object (asm/core/<ISA>/networking.s, beside the sync committee gossip checks).
- Argument order: `state`, `validator_index`, `out`.

## Function `lantern_node_sync_positions`

The places of a validator in the sync committee that compute_subnets_for_sync_committee reads (altair validator.md; beacon-api.md, produceSyncCommitteeContribution).

### Signature

```
lantern_node_sync_positions(state, validator_index, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `validator_index` | input | u64 |
| `out` | output | SYNC_COMMITTEE_SIZE / 8 bytes: bit p for place p |

### Returns

- `LANTERN_OK`: `out` holds bit p, of byte p / 8 at bit p % 8, for each place p of the validator's public key in the sync committee of lantern_node_sync_subnets; none for an index past the validators, and before altair.

### Tests

- The node-api cases of produceSyncCommitteeContribution: their answers come from the spec module's sync committee and the validator guide's rules.

### ABI

- Export: `lantern_<fork>_node_sync_positions` of each fork object (asm/core/<ISA>/networking.s).
- Argument order: `state`, `validator_index`, `out`.

## Function `lantern_node_produce_check`

The proposer of a block to produce and the checks that come before its body (beacon-api.md, produceBlockV3).

### Signature

```
lantern_node_produce_check(state, request, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState`: at the slot of the block |
| `request` | input | 136 bytes: `randao_reveal` (96), `graffiti` (32), then u64 1 with `skip_randao_verification` |
| `scratch` | scratch | `Scratch` |
| `out` | output | 16 bytes: get_beacon_proposer_index of the state (u64), then u64 1 when the chain is healthy for a builder, else 0 |

### Returns

- `LANTERN_OK`: `out` holds the proposer and the health.
- `LANTERN_INVALID_RANDAO_REVEAL`: with skip 1, a reveal other than the point at infinity (`0xc0` and 95 zero bytes); with skip 0, a reveal that fails the bls.Verify of process_randao for the proposer, the state's current epoch and get_domain(state, DOMAIN_RANDAO).
- `LANTERN_INVALID_DEPOSITS`: the block would need deposits: before electra min(`MAX_DEPOSITS`, `eth1_data.deposit_count` - `eth1_deposit_index`) above 0 (phase0 validator.md), in electra get_eth1_pending_deposit_count above 0; never from fulu, whose process_operations takes no deposit.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.
- Another `LANTERN_INVALID_*` code: a check of a callee failed.

### Function does

- The state is not changed: the reveal is checked without mixing it in.
- The health (beacon-api.md, produceBlockV3, the builder): with S the state's slot, all of these hold:
  - max(S - 1 - the slot of `latest_block_header`, 0) is at most `BUILDER_FALLBACK_SKIPS` (3).
  - max(compute_epoch_at_slot(S) - `finalized_checkpoint.epoch`, 0) is at most `BUILDER_FALLBACK_EPOCHS_SINCE_FINALIZATION` (3).
  - Of the slots s from max(S - `SLOTS_PER_EPOCH`, 0) below S, at most `BUILDER_FALLBACK_SKIPS_PER_EPOCH` (8) are skipped: s above 0 and `block_roots[s % SLOTS_PER_HISTORICAL_ROOT]` equal to `block_roots[(s - 1) % SLOTS_PER_HISTORICAL_ROOT]` (Lighthouse's block_root_at_slot_skips_none).

### Tests

- The node-produce cases: their answers come from the spec module's block proposal; the builder cases need the health (`builder_unhealthy` its lack).

### ABI

- Export: `lantern_<fork>_node_produce_check` of each fork object (asm/core/<ISA>/nodehooks.s).
- Argument order: `state`, `request`, `scratch`, `out`.

## Function `lantern_node_payload_result`

The `result` of an engine_getPayload of the fork's version (engine-api.md) as the SSZ bytes of the fork's result type.

### Signature

```
lantern_node_payload_result(json, scratch, out, fault) -> status
```

### Arguments

As lantern_engine_json_decode, without `type`.

### Returns

As lantern_engine_json_decode of the fork's `ExecutionPayload` (bellatrix) or `GetPayloadResult` (capella and later).

### Tests

- The node-produce cases: the engine's answer there is the spec module's payload in the JSON of execution-apis.

### ABI

- Export: `lantern_<fork>_node_payload_result` of the objects of bellatrix and later (asm/core/<ISA>/nodehooks.s).
- Argument order: `json`, `scratch`, `out`, `fault`.

## Function `lantern_node_produce_fold`

A pool entry added to the `ProduceDraft` of a block to produce, when the rules of beacon-api.md (produceBlockV3) take it.

### Signature

```
lantern_node_produce_fold(state, entry, draft, arg, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState`: at the slot of the block |
| `entry` | input | ByteList: the pool entry's SSZ bytes |
| `draft` | state | ByteList: a `ProduceDraft` from offset 24 |
| `arg` | input | u64: the entry's topic, + 2^8 times its `NodePool` `fork`, + 2^16 times its `member` |
| `scratch` | scratch | `Scratch` |

### Returns

- `LANTERN_OK`: the entry joined the draft.
- `LANTERN_INVALID_ENCODING`: the rules left it out, or the bytes are no entry of the topic; the draft is not changed.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` is short.

### Function does

- A voluntary exit, proposer slashing, BLS change (from capella) or attester slashing of the fork's type: a record in the operations area while the kind has fewer than its limit, and when it does not clash with the draft's records (the kinds before it fold first): an attester slashing needs an index in both attestations (sorted, as is_valid_indexed_attestation holds them) that is no proposer slashing's proposer; a voluntary exit's validator must be no proposer slashing's proposer and in both attestations of no attester slashing.
- An attestation of the fork's type (`SingleAttestation` from electra, its place and length from `member`; an `Attestation` before, its place its one bit): when process_attestation's checks of slot, target and source hold at the state, its place joins the `DraftAggregate` of its data and committee index, a new one when there is none; a place already set, or another length, leaves it out. Its signature joins the aggregate's by crypto_bls_aggregate.
- A sync committee message (from altair) of the state's slot - 1 with the block's parent root: each place of its validator's public key in the state's `current_sync_committee` not set yet is set, and for each its signature joins the aggregate's.

### Tests

- The node-produce cases.

### ABI

- Export: `lantern_<fork>_node_produce_fold` of each fork object (asm/core/<ISA>/nodehooks.s).
- Argument order: `state`, `entry`, `draft`, `arg`, `scratch`.

## Function `lantern_node_produce_block`

The block of produceBlockV3 (beacon-api.md) from a state at its slot, its `ProduceDraft` and the engine's payload, or with a builder's bid that wins the choice the blinded block.

### Signature

```
lantern_node_produce_block(state, draft, params, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | state | `BeaconState`: at the slot of the block; process_block runs on it |
| `draft` | input | ByteList: a `ProduceDraft` from offset 24 |
| `params` | input | `ProduceParams` |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList, its `size` set: the SSZ bytes of the fork's `BeaconBlock`, from deneb of `BlockContents`; a blinded block: of `BlindedBeaconBlock` |

### Returns

- `LANTERN_OK`: `out` holds the block and the values are written.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` or `out` is short.
- Another code: the engine's result does not decode, or process_block rejects the block (its result).

### Function does

- The body of beacon-api.md: the operations in the draft's record order; the attestations of the draft's aggregates by `data.slot` descending, then `order`, at most the fork's limit, from electra those of one data joined; the draft's sync aggregate; the payload, commitments and requests of the result (bellatrix: the result is the payload; with no result, before the merge, the empty payload).
- `state_root`: hash_tree_root of the state after process_block with an execution_valid of 1, or 3 with `skip_randao_verification` (no check of the reveal's signature).
- `execution_payload_value`: the result's `block_value`, 0 in bellatrix. `consensus_block_value`: the proposer's balance after less before, plus the payload's withdrawals to the proposer, at least 0.
- With a `bid` (from bellatrix): the choice of beacon-api.md, from the result's `block_value` (0 in bellatrix), the request's `builder_boost_factor` and the bid's `value`. The local block as above; else the blinded block:
  - The payload in the body is the stand-in: the header's fields from `parent_hash` to `block_hash`, then from deneb `blob_gas_used` and `excess_blob_gas`, its `extra_data`, no transactions, and from capella the withdrawals of lantern_get_expected_withdrawals of the state; from deneb the bid's `blob_kzg_commitments`, from electra its `execution_requests`.
  - process_block of that block. `out` then holds the `BlindedBeaconBlock`: the block's bytes with the header's SSZ bytes in place of the stand-in's, and the body's offsets after the payload's (from capella) grown by the difference.
  - `state_root`: the state's `latest_block_header.body_root` becomes the hash_tree_root of the blinded body (that of the builder's full body), its `latest_execution_payload_header.transactions_root` the header's; then hash_tree_root of the state.
  - `execution_payload_value`: the bid's `value`; `consensus_block_value` as above, with the stand-in's withdrawals; 1 at `blinded`.
  - The bid is not checked again: lantern_node_produce_bid checks it.

### Tests

- The node-produce cases.

### ABI

- Export: `lantern_<fork>_node_produce_block` of each fork object (asm/core/<ISA>/nodehooks.s).
- Argument order: `state`, `draft`, `params`, `scratch`, `out`.

## Function `lantern_node_produce_bid`

The bid of a builder's answer to getHeader, when it is valid for a block to produce (beacon-api.md, produceBlockV3, the builder).

### Signature

```
lantern_node_produce_bid(state, bid, params, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState`: at the slot of the block |
| `bid` | input | ByteList: the JSON text of the `data` of the builder's getHeader answer |
| `params` | input | `ProduceParams`: its `request` and `config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList, its `size` set: the SSZ bytes of the fork's `SignedBuilderBid` |

### Returns

- `LANTERN_OK`: `out` holds a valid bid.
- `LANTERN_INVALID_JSON`: `bid` is no JSON of the fork's `SignedBuilderBid` (lantern_json_decode).
- `LANTERN_INVALID_BID`: a check of beacon-api.md fails.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` or `out` is short.
- Another code: a callee's check failed.

### Function does

- The checks of beacon-api.md (process_bid, and those of process_execution_payload that need no transactions), in that order; the fee recipient is that at byte 168 of the request.
- Its `scratch`: `JSON_DECODE_SCRATCH`, the decoded bid, and that of lantern_get_expected_withdrawals.

### Tests

- The node-produce cases of a builder.

### ABI

- Export: `lantern_<fork>_node_produce_bid` of each fork object (asm/core/<ISA>/nodehooks.s); before bellatrix `LANTERN_INVALID_BID`.
- Argument order: `state`, `bid`, `params`, `scratch`, `out`.

## Type `ProduceParams`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `request` | address | The 188 bytes of the entry's `cursor`: lantern_node_produce_check's `request`, `builder_boost_factor` at byte 136, the registration's fee recipient at byte 168 |
| 8 | `config` | address | `Config` |
| 16 | `result` | address | ByteList: the SSZ bytes of the engine's result, or 0 |
| 24 | `payload_value` | address | Where execution_payload_value goes: 32 bytes, little endian |
| 32 | `block_value` | address | Where consensus_block_value goes: u64, in Gwei |
| 40 | `bid` | address | ByteList: the SSZ bytes of a valid `SignedBuilderBid` of the fork, or 0 |
| 48 | `blinded` | address | Where 1 goes for a blinded block, else 0: u64 |

## Function `lantern_node_publish_decode`

The signed block of a publishBlockV2 body (beacon-api.md).

### Signature

```
lantern_node_publish_decode(body, json, scratch, out, facts) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `body` | input | ByteList: the request's body |
| `json` | input | u64: 1 for a JSON body, 0 for SSZ; + 2 for a blinded block (publishBlindedBlockV2, from bellatrix) |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList, its `size` set: the SSZ bytes of the `SignedBeaconBlock`, or of the `SignedBlindedBeaconBlock` |
| `facts` | output | 24 bytes: the block's slot, its blob count (0 before deneb), and 0 |

### Returns

- `LANTERN_OK`: `out` and `facts` are written.
- `LANTERN_INVALID_ENCODING`: the body is no value of the fork's type (`SignedBeaconBlock` before deneb, lantern's `SignedBlockContents` from deneb, `SignedBlindedBeaconBlock` for a blinded block), or from deneb its counts of `kzg_proofs` and `blobs` do not fit the body's `blob_kzg_commitments` (beacon-api.md), or a blinded block's header has a `block_hash` of zero.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` or `out` is short.

### Tests

- The node-publish cases.

### ABI

- Export: `lantern_<fork>_node_publish_decode` of each fork object (asm/core/<ISA>/nodehooks.s).
- Argument order: `body`, `json`, `scratch`, `out`, `facts`.

## Function `lantern_node_publish_sidecars`

The sidecars of a publishBlockV2 body (beacon-api.md), from deneb.

### Signature

```
lantern_node_publish_sidecars(body, json, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `body` | input | ByteList: the request's body, which lantern_node_publish_decode took |
| `json` | input | u64: 1 for a JSON body, 0 for SSZ |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList: the sidecars, each a ByteList of its SSZ bytes, back to back from offset 24 |

### Returns

- `LANTERN_OK`: `out` holds the sidecars.
- `LANTERN_INVALID_ENCODING`: the body does not decode.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` or `out` is short.

### Function does

- Deneb and electra: get_blob_sidecars of the block, `blobs` and `kzg_proofs`, each `kzg_commitment_inclusion_proof` by ssz_build_proof of the body.
- Fulu: get_data_column_sidecars_from_block of the block and, for each blob, crypto_kzg_compute_cells of it and its `CELLS_PER_EXT_BLOB` proofs; `NUMBER_OF_COLUMNS` sidecars.

### Tests

- The node-publish cases.

### ABI

- Export: `lantern_<fork>_node_publish_sidecars` of each fork object from deneb (asm/core/<ISA>/nodehooks.s).
- Argument order: `body`, `json`, `scratch`, `out`.

## Function `lantern_node_publish_check`

The checks of `broadcast_validation` (beacon-api.md, publishBlockV2) of a block and its sidecars.

### Signature

```
lantern_node_publish_check(gossip, block, sidecars, level, scratch) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `gossip` | input | `NodeGossip`: `state_b` the parent's post-state, changed by process_block with level 2 or 3 |
| `block` | input | ByteList: the `SignedBeaconBlock` |
| `sidecars` | input | ByteList of lantern_node_publish_sidecars, or 0 |
| `level` | input | u64: 1 gossip, 2 consensus, 3 consensus_and_equivocation; + 256 for a blinded block, a `SignedBlindedBeaconBlock` with no sidecars |
| `scratch` | scratch | `Scratch` |

### Returns

- `LANTERN_OK`: every check holds.
- The result of the first check that fails: the beacon_block topic's, then each sidecar's topic's (lantern_node_gossip; `LANTERN_GOSSIP_IGNORE` or `LANTERN_GOSSIP_REJECT`), then from level 2 process_block's, and `LANTERN_INVALID_STATE_ROOT` for another state root.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` or the state's room is short.

### Function does

- Level 3 adds no check: the beacon_block topic's checks already ignore a second block of a proposer and slot.
- A blinded block: lantern_validate_blinded_block_gossip in place of the beacon_block topic's checks; from level 2 the blinded transition of beacon-api.md (the block with the stand-in payload, in scratch, decoded, then process_block; the state's `latest_block_header.body_root` and `latest_execution_payload_header.transactions_root` then the roots of the blinded block's body and header). The checks leave `seen` as it was in every case, so the full block passes the beacon_block topic's checks when the builder's broadcast brings it.
- A status or result but `LANTERN_OK` leaves `seen` as it was: the counts of its parts (`keys`, `bits`, `blocks`, `headers`, `header_bytes`) go back to those before the call, so the entries the checks added go. The checks of these topics only add entries.

### Tests

- The node-publish cases.

### ABI

- Export: `lantern_<fork>_node_publish_check` of each fork object (asm/core/<ISA>/nodehooks.s).
- Argument order: `gossip`, `block`, `sidecars`, `level`, `scratch`.

## Function `lantern_node_pending`

The items of a pending list of a state (beacon-api.md, getPendingDeposits, getPendingPartialWithdrawals, getPendingConsolidations).

### Signature

```
lantern_node_pending(state, kind, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork |
| `kind` | input | u64: 0 `pending_deposits`, 1 `pending_partial_withdrawals`, 2 `pending_consolidations` |
| `out` | output | 3 u64: the address of the first item, the count, the bytes of an item |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_NO_STATE_ANSWER`: the fork is before electra, whose `BeaconState` has no such list, or `kind` is above 2.

### Function does

- The items lie one after another in the state, each in its SSZ encoding: `PendingDeposit` 192 bytes (`pubkey` 0, `withdrawal_credentials` 48, `amount` 80, `signature` 88, `slot` 184), `PendingPartialWithdrawal` 24 (`validator_index` 0, `amount` 8, `withdrawable_epoch` 16), `PendingConsolidation` 16 (`source_index` 0, `target_index` 8).

### ABI

- Export: `lantern_<fork>_node_pending` of each fork object.
- Argument order: `state`, `kind`, `out`.

## Function `lantern_node_blinded_block`

The blinded block of a block's SSZ bytes (beacon-api.md, getBlindedBlock).

### Signature

```
lantern_node_blinded_block(block, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `block` | input | ByteList: the SSZ bytes of a `SignedBeaconBlock` of the fork |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList: the SSZ bytes of the `SignedBlindedBeaconBlock` of the fork; before bellatrix the bytes of `block` |

### Returns

- `LANTERN_OK`: `out` holds them, its `count` set.
- `LANTERN_INVALID_ENCODING`: `block` is no SSZ encoding of the type.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has too little room, or `scratch` fewer bytes than the decoded block, `LANTERN_SCRATCH_FIXED`, the header and its hash lists take.

### Function does

- From bellatrix: the `ExecutionPayloadHeader` of the body's `execution_payload`, as process_execution_payload builds it (its `transactions_root` and, from capella, `withdrawals_root` the hash_tree_root of the payload's lists), of the block that ssz_deserialize gives in `scratch`; its SSZ bytes in the payload's place.
- The other bytes are those of `block`: the `SignedBlindedBeaconBlock` has the fields of the `SignedBeaconBlock` in their order, the body's `execution_payload_header` where its `execution_payload` is. The offsets in the body's fixed part of the fields after it (from capella `bls_to_execution_changes`, from deneb `blob_kzg_commitments`, from electra `execution_requests`) grow by the header's bytes less the payload's.
- So the blinded block has the block's hash_tree_root.

### ABI

- Export: `lantern_<fork>_node_blinded_block` of each fork object.
- Argument order: `block`, `scratch`, `out`.

## Function `lantern_node_event_roots`

The roots of a head event (beacon-api.md, eventstream) of a block's post-state.

### Signature

```
lantern_node_event_roots(state, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork: a block's post-state |
| `config` | input | `Config`: its `StateCache` |
| `scratch` | scratch | `Scratch` |
| `out` | output | 4 roots of 32 bytes: the block root, the state root, the previous and the current duty dependent roots |

### Returns

- `LANTERN_OK`: `out` holds them.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than S(2) bytes.
- The statuses of lantern_get_block_root_at_slot and lantern_state_root.

### Function does

- The state root: the `state_root` of `latest_block_header`; when it is zero, lantern_state_root of the state.
- The block root: hash_tree_root of `latest_block_header` with the state root as `state_root`.
- With e the epoch of the state's slot: get_block_root_at_slot(state, compute_start_slot_at_epoch(e - 1) - 1) and get_block_root_at_slot(state, compute_start_slot_at_epoch(e) - 1). Each that underflows is the genesis block root: get_block_root_at_slot(state, 0) when the state's slot is above 0, else the block root.

### ABI

- Export: `lantern_<fork>_node_event_roots` of each fork object.
- Argument order: `state`, `config`, `scratch`, `out`.

## Function `lantern_node_attestation`

validate_on_attestation of an `Attestation` in SSZ bytes, then on_attestation with its target checkpoint state.

### Signature

```
lantern_node_attestation(store, data, is_from_block, state, scratch, result, target) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `data` | input | ByteList |
| `is_from_block` | input | u64: 1 or 0 |
| `state` | input | `BeaconState`: `store.checkpoint_states[attestation.data.target]`, or 0 |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |
| `target` | output | Checkpoint |

### Returns

- `LANTERN_OK`: `result` is a code of lantern_validate_on_attestation, `LANTERN_NEED_TARGET_STATE` with the target in `target` when `state` is 0, that of lantern_on_attestation, or `LANTERN_INVALID_ENCODING`.
- `LANTERN_BUFFER_TOO_SMALL`: as lantern_on_attestation, or `scratch` cannot hold the decoded attestation.

### ABI

- Export: `lantern_<fork>_node_attestation` of each fork object.

## Function `lantern_node_attester_slashing`

on_attester_slashing of an `AttesterSlashing` in SSZ bytes.

### Signature

```
lantern_node_attester_slashing(store, data, state, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | state | `Store` |
| `data` | input | ByteList |
| `state` | input | `BeaconState`: `store.block_states[store.justified_checkpoint.root]` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is that of lantern_on_attester_slashing, or `LANTERN_INVALID_ENCODING`.
- `LANTERN_BUFFER_TOO_SMALL`: as lantern_on_attester_slashing, or `scratch` cannot hold the decoded slashing.

### ABI

- Export: `lantern_<fork>_node_attester_slashing` of each fork object.

## Function `lantern_node_gossip`

The gossip validation of the topic of a `NodeGossip` for SSZ bytes, decoded with the fork's types.

### Signature

```
lantern_node_gossip(args, data, scratch, result, root, index) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `args` | input | `NodeGossip` |
| `data` | input | ByteList: the uncompressed message |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |
| `root` | output | Root |
| `index` | output | u64 |

### Returns

- `LANTERN_OK`: `result` is that of the topic's lantern_validate_<topic>_gossip, `LANTERN_GOSSIP_REJECT` when `data` is no value of the topic's type, or `LANTERN_GOSSIP_IGNORE` for a topic of no type in the fork or a proposer state whose slots do not run.
- `LANTERN_BUFFER_TOO_SMALL`: as the topic's function or lantern_process_slots, or `scratch` cannot hold the decoded value.

### Function does

- The types: beacon_block `SignedBeaconBlock`, beacon_aggregate_and_proof `SignedAggregateAndProof`, beacon_attestation `Attestation` (`SingleAttestation` from electra), voluntary_exit `SignedVoluntaryExit`, proposer_slashing `ProposerSlashing`, attester_slashing `AttesterSlashing`, sync_committee_contribution_and_proof `SignedContributionAndProof`, sync_committee `SyncCommitteeMessage`, bls_to_execution_change `SignedBLSToExecutionChange`, blob_sidecar `BlobSidecar`, data_column_sidecar `DataColumnSidecar`; lantern's `GOSSIP_BLINDED_BLOCK` (64, no gossip topic: publishBlindedBlockV2's checks) `SignedBlindedBeaconBlock` from bellatrix, of lantern_validate_blinded_block_gossip, as beacon_block in every other way, with nothing in `root` and `index`.
- beacon_block, the blinded block, blob_sidecar and data_column_sidecar: lantern_process_slots of the proposer state to the slot of the message's block header, when the state is before it. With no proposer state, the head state is the proposer state.
- Bellatrix beacon_block: the justified state, or the head state with none.
- A valid beacon_block: hash_tree_root of its message in `root`, the length of its body's `blob_kzg_commitments` (0 before deneb) in `index`.
- A valid blob_sidecar or data_column_sidecar: hash_tree_root of its `signed_block_header.message` in `root`, its `index` in `index`.
- A valid sync_committee message: in `root` four u64, its `slot`, 2^`subnet`, 0 and 0.
- A valid beacon_attestation: in `root` four u64, its `data.slot`, its committee index (`data.index` before electra, `committee_index` from electra), its member and 0. The member, from electra: the place of `attester_index` in lantern_get_beacon_committee of the head state, that slot and that committee index (with the `CommitteeCache` of the config) + 2^16 times the committee's length; before electra 0. The spec's validation reads that committee of the head state too.
- Decodes into the end of `scratch`; the scratch `size` is restored on return.

### ABI

- Export: `lantern_<fork>_node_gossip` of each fork object.

## Function `lantern_node_blob_sidecar`

The checks a reader of a BlobSidecarsByRange or BlobSidecarsByRoot response makes on a `BlobSidecar` in SSZ bytes, then the root of its block.

### Signature

```
lantern_node_blob_sidecar(data, config, settings, scratch, result, root) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList |
| `config` | input | `Config` |
| `settings` | input | asm-crypto `KzgSettings` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |
| `root` | output | Root |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` and `root` holds hash_tree_root of `signed_block_header.message`; `LANTERN_INVALID_ENCODING` when `data` is no `BlobSidecar`; or `LANTERN_INVALID_BLOB_SIDECAR` when a check fails.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` cannot hold the decoded sidecar, or has less than `CRYPTO_KZG_SCRATCH` of asm-crypto after it.

### Function does

- The checks, in order: `index` is below `MAX_BLOBS_PER_BLOCK` (deneb) or `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra) of `config`; lantern_verify_blob_sidecar_inclusion_proof; `crypto_kzg_verify_blob_kzg_proof` of `blob`, `kzg_commitment` and `kzg_proof`. A blob, commitment or proof it cannot decode fails.
- Decodes into the end of `scratch`; the scratch `size` is restored on return.

### ABI

- Export: `lantern_<fork>_node_blob_sidecar` of the deneb and electra objects.

## Function `lantern_node_column_sidecar`

The checks a reader of a DataColumnSidecarsByRange or DataColumnSidecarsByRoot response makes on a `DataColumnSidecar` in SSZ bytes, then the root of its block.

### Signature

```
lantern_node_column_sidecar(data, config, settings, scratch, result, root) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList |
| `config` | input | `Config` |
| `settings` | input | asm-crypto `KzgSettings` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |
| `root` | output | Root |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` and `root` holds hash_tree_root of `signed_block_header.message`; `LANTERN_INVALID_ENCODING` when `data` is no `DataColumnSidecar`; or `LANTERN_INVALID_COLUMN_SIDECAR` when a check fails.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` cannot hold the decoded sidecar, or the room the checks need after it.

### Function does

- The checks, in order: lantern_verify_data_column_sidecar with `config`; lantern_verify_data_column_sidecar_inclusion_proof; lantern_verify_data_column_sidecar_kzg_proofs with `settings`.
- Decodes into the end of `scratch`; the scratch `size` is restored on return.

### ABI

- Export: `lantern_fulu_node_column_sidecar` of the fulu object.

## Function `lantern_node_db_scan`

Adds the records of a segment file to the node's `Db`, as a start does with the files of an earlier run.

### Signature

```
lantern_node_db_scan(node, segment, sidecars, bytes, valid) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | state | `Node` |
| `segment` | input | u64: the segment's number |
| `sidecars` | input | u64: 0 for a block segment, 1 for a sidecar segment |
| `bytes` | input | ByteList: the file's bytes from its start |
| `valid` | output | u64: the bytes of the whole records added |

### Returns

- `LANTERN_OK`, or a status of lantern_db_scan of the node's `Db` ([db.md](db.md#function-lantern_db_scan)).

### Function does

- lantern_db_scan of the node's `Db`.
- The segment is then the one of its kind the node appends to, at `valid`, unless the one it has is higher.
- `db_next_slot` takes the `Db`'s `end_slot` when that is more, and `earliest_slot` the `Db`'s first slot with a block when that is less.
- A sidecar segment: it is the backfill's sidecar segment, at `valid`, when `backfill_sidecar_segment` is 2^64 - 1. A block segment: it is the backfill's segment, at `valid`, when `backfill_segment` is 2^64 - 1. Each of its block records with a slot below `backfill_slot`: `backfill_slot` and `backfill_next` take the slot and `backfill_root` the record's `parent_root` (bytes 116 to 147 of its SSZ bytes).

### Caller must

- Pass each segment once, in ascending order, the block segments before the sidecar segments, before the node's first step; cut each file to `valid` before the node appends to it.

### ABI

- Role: L2.
- Symbol: `lantern_node_db_scan` (`_lantern_node_db_scan` on macOS), in the common object.
- Argument order: `node`, `segment`, `sidecars`, `bytes`, `valid`.

## Function `lantern_node_anchor`

The anchor of a node that starts at a genesis state: the state with room, and its block.

### Signature

```
lantern_node_anchor(data, room, scratch, state, block) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList: the SSZ bytes of a `BeaconState` of the fork |
| `room` | input | [`StateRoom`](state.md#type-stateroom) |
| `scratch` | scratch | `Scratch` |
| `state` | output | `BeaconState`, its `size` set by the caller |
| `block` | output | `BeaconBlock`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `state` and `block` hold the anchor.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` cannot hold the decoded state and the block's bytes, `state` is below lantern_beacon_state_copy_size of the decoded state and `room`, or `block` cannot hold the block.
- `LANTERN_INVALID_ENCODING`: `data` is not the SSZ bytes of a `BeaconState` of the fork.
- `LANTERN_INVALID_ANCHOR`: the `body_root` of the state's `latest_block_header` is not hash_tree_root of the default `BeaconBlockBody` of the fork, so the state is not at a block with the default body, such as genesis.

### Function does

- `state`: the decoded state, as lantern_beacon_state_copy gives it with `room`.
- `block`: the `slot`, `proposer_index` and `parent_root` of the state's `latest_block_header`; its `state_root` when not zero, else hash_tree_root of the state, as process_slot fills it; and the default `BeaconBlockBody` of the fork (the SSZ default value: zero fixed fields and empty lists).
- Restores the `size` field of `scratch`.

### ABI

- Export: `lantern_<fork>_node_anchor` of each fork object.
- Argument order: `data`, `room`, `scratch`, `state`, `block`.


## Function `lantern_node_anchor_block`

The anchor of a node that starts again from its own history: a finalized block's post-state and the block, as a `NODE_ACT_DB_STATE` named them.

### Signature

```
lantern_node_anchor_block(data, room, scratch, state, block) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList: two ByteLists, the second at the first multiple of 8 after the first: the SSZ bytes of a `BeaconState` of the fork, then those of its block's `BeaconBlock` |
| `room` | input | [`StateRoom`](state.md#type-stateroom) |
| `scratch` | scratch | `Scratch` |
| `state` | output | `BeaconState`, its `size` set by the caller |
| `block` | output | `BeaconBlock`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `state` and `block` hold the anchor.
- `LANTERN_BUFFER_TOO_SMALL`: as lantern_node_anchor, or `block` cannot hold the block's message.
- `LANTERN_INVALID_ENCODING`: `data` is not of that form (each ByteList with `offset` 24 and `size` 24 + `count`, inside `data`), or a part is not the SSZ bytes of its type.
- `LANTERN_INVALID_ANCHOR`: the block's slot is not the state's, or its `state_root` is not hash_tree_root of the state.

### Function does

- `state`: the decoded state, as lantern_beacon_state_copy gives it with `room`.
- `block`: the decoded block.
- Restores the `size` field of `scratch`.

### ABI

- Export: `lantern_<fork>_node_anchor_block` of each fork object.
- Argument order: `data`, `room`, `scratch`, `state`, `block`.

## Function `lantern_node_state_bytes`

The SSZ bytes of a beacon state of the fork.

### Signature

```
lantern_node_state_bytes(state, scratch, out, size) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList, its `size` set by the caller |
| `size` | output | u64: 24 + the bytes of the state's SSZ encoding |

### Returns

- `LANTERN_OK`: `out` holds the encoding at offset 24.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is below `size`, or `scratch` is short; `size` is written all the same when `scratch` holds what ssz_serialize_size needs.

### Function does

- ssz_serialize_size, then ssz_serialize of asm-ssz with the fork's `BeaconState` type.
- Restores the `size` field of `scratch`.

### ABI

- Export: `lantern_<fork>_node_state_bytes` of each fork object.
- Argument order: `state`, `scratch`, `out`, `size`.
## Function `lantern_node_upgrade`

upgrade_to_<fork> of the object's fork: the state of the fork from a state of the fork before, at the fork's first slot.

### Signature

```
lantern_node_upgrade(pre, room, config, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pre` | input | `BeaconState` of the fork before, at the fork's first slot |
| `room` | input | [`StateRoom`](state.md#type-stateroom) |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `out` | output | `BeaconState`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the upgraded state.
- `LANTERN_BUFFER_TOO_SMALL`: `out` is below what lantern_upgrade_size gives for `pre` and `room`, or `scratch` is short. Checked before `out` is written.
- `LANTERN_INVALID_SLOT`: phase0, which has no upgrade.
- The statuses of lantern_upgrade_to_<fork>.

### Function does

- lantern_upgrade_size, then lantern_upgrade_to_<fork> of [fork-upgrades.md](fork-upgrades.md).

### ABI

- Export: `lantern_<fork>_node_upgrade` of each fork object.
- Argument order: `pre`, `room`, `config`, `scratch`, `out`.

## Function `lantern_node_replay`

The post-state again of a block the node imported: state_transition with validate_result 0, as the node checked the block when it imported it.

### Signature

```
lantern_node_replay(data, state, config, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList: the `SignedBeaconBlock`'s SSZ bytes |
| `state` | state | `BeaconState` of the fork: the post-state of the block's parent, which becomes the block's |
| `config` | input | `Config` |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is that of lantern_state_transition, or `LANTERN_INVALID_ENCODING` when `data` is no `SignedBeaconBlock`.
- `LANTERN_BUFFER_TOO_SMALL`: as lantern_state_transition, or `scratch` cannot hold the decoded block.

### Function does

- lantern_state_transition with `TransitionOptions` of validate_result 0, execution_valid 1 and slots_done 1.
- Restores the `size` field of `scratch`.

### ABI

- Export: `lantern_<fork>_node_replay` of each fork object.
- Argument order: `data`, `state`, `config`, `scratch`, `result`.

## Function `lantern_node_backfill`

The proposer signature of a block older than a state, as a backfill checks it (phase0 `p2p-interface.md`: the signature is not part of the block's hash chain).

### Signature

```
lantern_node_backfill(data, state, config, root, scratch, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList: the `SignedBeaconBlock`'s SSZ bytes, of any fork |
| `state` | input | `BeaconState` of the fork: a state at or after the block's slot |
| `config` | input | `Config` |
| `root` | input | Root: hash_tree_root of the block's message |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID`, `LANTERN_INVALID_ENCODING` for fewer than 184 bytes, `LANTERN_INVALID_PROPOSER_INDEX` for a `proposer_index` of no validator, or `LANTERN_INVALID_BLOCK_SIGNATURE`.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` cannot hold the check.

### Function does

- The block's `slot` and `proposer_index` are bytes 100 and 108 of `data`, and its signature bytes 4 to 99, in every fork.
- A block at `GENESIS_SLOT`: `LANTERN_VALID`; the genesis block has no proposer.
- Else `LANTERN_VALID` when `proposer_index` is below the length of the state's validators and bls.Verify(the validator's pubkey, compute_signing_root(`root`, domain), signature), with domain compute_domain(`DOMAIN_BEACON_PROPOSER`, compute_fork_version(the epoch of the slot), the state's `genesis_validators_root`): the block's own fork version, as its proposer signed it. A validator's index and pubkey never change, so a later state has them.

### ABI

- Export: `lantern_<fork>_node_backfill` of each fork object.
- Argument order: `data`, `state`, `config`, `root`, `scratch`, `result`.

## Function `lantern_node_block_header`

The SignedBeaconBlockHeader of a `SignedBeaconBlock` in SSZ bytes: the message's fields, hash_tree_root of its body, and the signature.

### Signature

```
lantern_node_block_header(data, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList: the SSZ bytes of a `SignedBeaconBlock` of the fork |
| `scratch` | scratch | `Scratch` |
| `out` | output | `SignedBeaconBlockHeader`: 208 bytes |

### Returns

- `LANTERN_OK`: `out` holds the header.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` cannot hold the decoded block.
- `LANTERN_INVALID_ENCODING`: `data` is not the SSZ bytes of a `SignedBeaconBlock` of the fork.

### Function does

- Restores the `size` field of `scratch`.

### ABI

- Export: `lantern_<fork>_node_block_header` of each fork object.
- Argument order: `data`, `scratch`, `out`.

## Function `lantern_node_state_checkpoints`

The `previous_justified_checkpoint`, `current_justified_checkpoint` and `finalized_checkpoint` of a state, in that order: the finality checkpoints of the Beacon API.

### Signature

```
lantern_node_state_checkpoints(state, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork |
| `out` | output | 3 Checkpoint values: 120 bytes |

### Returns

- `LANTERN_OK`, always.

### ABI

- Export: `lantern_<fork>_node_state_checkpoints` of each fork object.
- Argument order: `state`, `out`.

## Function `lantern_node_new_payload`

The HTTP/1.1 request of engine_newPayload for the execution payload of a `SignedBeaconBlock` in SSZ bytes.

### Signature

```
lantern_node_new_payload(data, node, id, scratch, out, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList |
| `node` | input | `Node`: its `jwt_secret`, `engine_host` and `time_ms` |
| `id` | input | u64: the JSON-RPC id |
| `scratch` | scratch | `Scratch` |
| `out` | output | ByteList, its `size` set by the caller |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` and `out` holds the request; `LANTERN_NO_PAYLOAD` when the payload's `block_hash` and `parent_hash` are both zero; or `LANTERN_INVALID_ENCODING` when `data` is no `SignedBeaconBlock`.
- `LANTERN_BUFFER_TOO_SMALL`: `out` or `scratch` has too little room.

### Function does

- lantern_engine_new_payload of the block with `id`, lantern_jwt_token of `jwt_secret` with the time `time_ms` / 1000, then lantern_http_post to `engine_host`.
- A payload with zero `block_hash` and `parent_hash` is the empty payload before the merge, or one that process_execution_payload rejects after it, since `parent_hash` must then be the header's `block_hash`.
- Decodes into the end of `scratch`; the scratch `size` is restored on return.

### ABI

- Export: `lantern_<fork>_node_new_payload` of the bellatrix and later objects.

## Function `lantern_node_json`

The JSON of a block's, a state's or a pool operation's SSZ bytes, a chunk at a time, as lantern_json_encode_ssz writes it with the fork's type.

### Signature

```
lantern_node_json(kind, ssz, cursor, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64: `NODE_JSON_BLOCK` (0) `SignedBeaconBlock`, `NODE_JSON_STATE` (1) `BeaconState`, `NODE_JSON_EXIT` (2) `SignedVoluntaryExit`, `NODE_JSON_PROPOSER_SLASHING` (3) `ProposerSlashing`, `NODE_JSON_ATTESTER_SLASHING` (4) `AttesterSlashing`, `NODE_JSON_BLS_CHANGE` (5) `SignedBLSToExecutionChange`, `NODE_JSON_ATTESTATION` (6) `Attestation`, `NODE_JSON_SINGLE_ATTESTATION` (7) `SingleAttestation`, `NODE_JSON_ATTESTATIONS` (8) `Attestations`, `NODE_JSON_BLINDED_BLOCK` (9) `SignedBlindedBeaconBlock` from bellatrix, `SignedBeaconBlock` before, `NODE_JSON_BLOB_SIDECAR` (10) `BlobSidecar` of deneb and electra, `NODE_JSON_DATA_COLUMN_SIDECAR` (11) `DataColumnSidecar` from fulu, `NODE_JSON_AGGREGATE_AND_PROOF` (12) `SignedAggregateAndProof`, `NODE_JSON_SYNC_COMMITTEE_MESSAGE` (13) `SyncCommitteeMessage` from altair, `NODE_JSON_SYNC_CONTRIBUTION` (14) `SyncCommitteeContribution` from altair, `NODE_JSON_CONTRIBUTION_AND_PROOF` (15) `SignedContributionAndProof` from altair, `NODE_JSON_COMMITTEE_SUBSCRIPTION` (16) lantern's `BeaconCommitteeSubscription`, `NODE_JSON_SYNC_SUBSCRIPTION` (17) lantern's `SyncCommitteeSubscription` from altair, `NODE_JSON_PROPOSER_PREPARATION` (18) lantern's `ProposerPreparation`, `NODE_JSON_BEACON_BLOCK` (19) `BeaconBlock`, `NODE_JSON_BLOCK_CONTENTS` (20) lantern's `BlockContents` from deneb, `NODE_JSON_LC_BOOTSTRAP` (21) `LightClientBootstrap`, `NODE_JSON_LC_UPDATE` (22) `LightClientUpdate`, `NODE_JSON_LC_FINALITY_UPDATE` (23) `LightClientFinalityUpdate` and `NODE_JSON_LC_OPTIMISTIC_UPDATE` (24) `LightClientOptimisticUpdate`, from altair, `NODE_JSON_VALIDATOR_REGISTRATION` (25) `SignedValidatorRegistrationV1` of builder-specs, `NODE_JSON_BLINDED_BEACON_BLOCK` (26) `BlindedBeaconBlock` from bellatrix, `BeaconBlock` before, `NODE_JSON_BUILDER_BID` (27) `SignedBuilderBid` of builder-specs from bellatrix |
| `ssz` | input | ByteList: a valid SSZ encoding of the type |
| `cursor` | state | `JsonCursor` of [beacon-api.md](beacon-api.md#type-jsoncursor) |
| `out` | output | ByteList |

### Returns

- As lantern_json_encode_ssz; `LANTERN_INVALID_EVENT` for another `kind`, or for a type the fork does not have (`SignedBLSToExecutionChange` before capella, `SingleAttestation` before electra, `BlobSidecar` outside deneb and electra, `DataColumnSidecar` before fulu).

### Function does

- lantern_json_encode_ssz with the fork's type of the kind, of include/descriptors.inc.

### ABI

- Export: `lantern_<fork>_node_json` of each fork object.
- Argument order: `kind`, `ssz`, `cursor`, `out`.

## Type `Node`

The state of the node: a value with parts.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer |
| 8 | `next_id` | u64 | The next `BufferId` |
| 16 | `time_ms` | u64 | The time of the last `NODE_EV_TICK` |
| 24 | `head_root` | Root | The root of the last get_head |
| 56 | `anchor_state_id` | u64 | 1 |
| 64 | `blocks` | PartRef | `NodeBlock` entries |
| 80 | `checkpoints` | PartRef | `NodeCheckpoint` entries |
| 96 | `pow_blocks` | PartRef | `PowBlock` values of `POW_BLOCK_BYTES` |
| 112 | `flags` | u64 | `NODE_FLAG_*` |
| 120 | `peers` | PartRef | `NodePeer` entries |
| 136 | `streams` | PartRef | `NodeStream` entries of `stream_bytes` each |
| 152 | `p2p_out` | PartRef | One ByteList, offset 24: the libp2p events the node made for its next libp2p step |
| 168 | `stream_bytes` | u64 | `NodeStream__fixed` + the request room, a multiple of 8 |
| 176 | `metadata_seq` | u64 | MetaData `seq_number` |
| 184 | `genesis_validators_root` | Root | Of the anchor |
| 216 | `earliest_slot` | u64 | The anchor's slot: the first block the node serves |
| 224 | `messages` | PartRef | `NodeMessage` entries |
| 240 | `fork_digest` | u64 | The ForkDigest of the subscribed topics: 4 bytes |
| 248 | `sync_slot` | u64 | The least start slot of the next BeaconBlocksByRange of the node |
| 256 | `blobs` | PartRef | `NodeBlob` entries |
| 272 | `jwt_secret` | Bytes32 | The key of the Engine API's JWTs |
| 304 | `engine_host_len` | u64 | |
| 312 | `engine_host` | 64 bytes | The `Host` of the Engine API requests |
| 376 | `engine_id` | u64 | The JSON-RPC id of the next call |
| 384 | `engine_method` | u64 | `ENGINE_METHOD_*` of the call in flight, or 0 |
| 392 | `engine_target` | u64 | The `NodeBlock` index of the engine_newPayload in flight |
| 400 | `engine_wait` | u64 | After a failed call, the slot from which calls go again |
| 408 | `engine_in` | PartRef | One ByteList, offset 24: the bytes the execution engine sent and the node has not read |
| 424 | `lookup_ms` | u64 | The time of the last discv5 lookup the node asked for |
| 432 | `dialing` | u64 | The node's dials not yet connected or failed |
| 440 | `columns` | 16 bytes | The columns the node samples: bit i % 8 of byte i / 8 for column i |
| 456 | `pruned_epoch` | u64 | The store's finalized epoch at the node's last prune |
| 464 | `db` | PartRef | One `Db` of [db.md](db.md): the history the node archived |
| 480 | `db_next_slot` | u64 | With `NODE_FLAG_DB`: the canonical blocks below this slot are in the `Db`; the anchor's slot + 1 at the start |
| 488 | `db_block_segment` | u64 | The block segment of the last block record, or 2^64 - 1 |
| 496 | `db_block_end` | u64 | The bytes of that segment |
| 504 | `db_sidecar_segment` | u64 | The sidecar segment of the last sidecar record, or 2^64 - 1 |
| 512 | `db_sidecar_end` | u64 | The bytes of that segment |
| 520 | `status_ms` | u64 | The time of the node's last Status request when no peer was ahead, or 0 |
| 528 | `next_digest` | u64 | The ForkDigest whose topics the node joined ahead of its epoch, 4 bytes, or 0 |
| 536 | `old_digest` | u64 | The ForkDigest whose topics leave from `old_epoch` on, 4 bytes, or 0 |
| 544 | `old_fork` | u64 | `FORK_*` of those topics |
| 552 | `old_epoch` | u64 | |
| 560 | `backfill_handle` | u64 | The stream of the node's backfill request: its tag, then its handle; 0 for none |
| 568 | `backfill_slot` | u64 | The backfill looks for blocks below this slot: the lowest block of the `Db`'s, or the anchor's slot + 1 |
| 576 | `backfill_root` | Root | The root of the next block of the backfill: the `parent_root` of the block at `backfill_slot`; zero after the genesis block |
| 608 | `backfill_segment` | u64 | The block segment of the last backfill record, or 2^64 - 1 |
| 616 | `backfill_end` | u64 | The bytes of that segment |
| 624 | `backfill_next` | u64 | The end slot of the next backfill request |
| 632 | `backfill_ms` | u64 | The time from which the next backfill request may go |
| 640 | `backfill_peer` | u64 | The index in the peers part of the peer of the next backfill request |
| 648 | `backfill_start` | u64 | The start slot of the last backfill request, 2^64 - 1 once it is weighed |
| 656 | `backfill_got` | u64 | The blocks of the last backfill request |
| 664 | `backfill_sidecar_segment` | u64 | The sidecar segment of the last backfill sidecar record, or 2^64 - 1 |
| 672 | `backfill_sidecar_end` | u64 | The bytes of that segment |
| 680 | `node_id` | `NodeID` | The anchor's: the node ID of the node's key |
| 712 | `attnets` | u64 | The node's long-lived attestation subnets (its record's and MetaData's): bit i for subnet i |
| 720 | `sidecar_floor` | u64 | With `NODE_FLAG_DB`: the `Db` holds no sidecar below this slot; the `Db`'s first slot at the start |
| 728 | `config` | `Config` | |
| 728 + `CONFIG_SIZE` | `api_identity` | `ApiIdentity` of [beacon-api.md](beacon-api.md#type-apiidentity) | Of the last `NODE_EV_API_IDENTITY`; its texts empty at the start |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` | `api` | PartRef | `NodeApi` entries |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 16 | `event_head` | Root | The head of the last head event; the anchor's root at the start |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 48 | `event_slot` | u64 | The slot of `event_head`'s block |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 56 | `event_epoch` | u64 | The store's finalized epoch at the last finalized_checkpoint event; the anchor's finalized epoch at the start |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 64 | `event_votes` | u64 | The `NODE_WORK_BLOCK_ATTESTATION` and `NODE_WORK_BLOCK_SLASHING` works queued and not done |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 72 | `pool` | PartRef | `NodePool` entries: the pool |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 88 | `subnets` | u64 | The beacon_attestation subnets the node is subscribed to: `attnets` and an aggregator's |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 96 | `syncnets` | u64 | The sync_committee subnets the node is subscribed to: bit i for subnet i |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 104 | `sync_until` | `SYNC_COMMITTEE_SUBNET_COUNT` u64 | Each sync subnet's subscription lasts while the store's epoch is below it; 0 for none |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 104 + 8 * `SYNC_COMMITTEE_SUBNET_COUNT` | `subnet_until` | `ATTESTATION_SUBNET_COUNT` u64 | Each subnet's aggregator subscription lasts while the store's slot is below it: its slot + 1; 0 for none |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 104 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `proposers` | PartRef | `NodeProposer` entries: the fee recipients of prepareBeaconProposer |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 120 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `payload_slot` | u64 | The slot of the last payload preparation; 0 for none |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 128 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `payload_root` | Root | The `head_root` it built on |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 160 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `payload_id` | 8 bytes | The `payloadId` of the execution engine, with `NODE_PAYLOAD_READY` |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 168 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `payload_status` | u64 | `NODE_PAYLOAD_NONE` (0), `NODE_PAYLOAD_PREPARING` (1) while its work is queued, `NODE_PAYLOAD_SENT` (2) while its engine_forkchoiceUpdated is in flight, `NODE_PAYLOAD_READY` (3) with a `payload_id` |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 176 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `payload_proposer` | u64 | The validator index of the proposer of `payload_slot`, from `NODE_PAYLOAD_SENT` on |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 184 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `lc_finality_slot` | u64 | The finalized slot of the last light client finality update the node published or forwarded; 0 for none |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 192 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `lc_finality_super` | u64 | 1 when that update had a supermajority |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 200 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `lc_optimistic_slot` | u64 | The attested slot of the last light client optimistic update the node published or forwarded; 0 for none |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 208 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `lc_pending` | u64 | The light client topics whose update waits for its due time: 1 finality, 2 optimistic |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 216 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `lc_due` | u64 | The Unix time in ms from which they may go |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 224 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `builder_host_len` | u64 | With `NODE_FLAG_BUILDER` |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 232 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `builder_host` | 64 bytes | The `Host` of the Builder API requests |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 296 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `builder_calls` | `NODE_BUILDER_CALLS` (4) entries of 24 bytes | Each: its kind (0 free), the `NodeApi` entry it answers, the `time_ms` it went out |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 392 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `base_slot` | u64 | The slot of the base state, `anchor_state_id`: the anchor's |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 400 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `replay_root` | Root | The block of the last replay |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 432 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `replay_slot` | u64 | Its slot |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 440 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `replay_state` | u64 | Its post-state once the replay is queued whole, or 0 |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 448 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `replay_copy` | u64 | The copy the replay in flight brings forward, or 0 for none |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 456 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `replay_copy_slot` | u64 | Its slot |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 464 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`) | `replay_next` | u64 | The slot from which the replay in flight queues its next block |

### Rules

- `NODE_FIXED` (728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 472 + 8 * (`SYNC_COMMITTEE_SUBNET_COUNT` + `ATTESTATION_SUBNET_COUNT`)) bytes of fixed fields; the parts follow in the order blocks, checkpoints, pow_blocks, peers, streams, messages, blobs, api, pool, proposers, p2p_out, engine_in, db.
- The `Db` has the capacities of the `NodeRoom` fields `db_slots` and `db_roots`, and its `first_slot` is the lowest of the anchor's `history_slot`, its slot and the first slot of the epoch max(0, the epoch of its slot - compute_min_epochs_for_block_requests), rounded down to a multiple of `DB_SEGMENT_SLOTS`: the backfill's blocks fit in it.
- The backfill at the start: `backfill_root` the anchor's root, `backfill_slot` and `backfill_next` its slot + 1 (the anchor block's bytes come from a peer too), `backfill_segment`, `backfill_sidecar_segment` and `backfill_start` 2^64 - 1, and `backfill_handle`, `backfill_end`, `backfill_ms`, `backfill_peer` and `backfill_got` 0.
- The capacity of a part is its bytes up to the next part over its entry's bytes; `p2p_out` is the last part.
- `NODE_FLAG_OPTIMISTIC`: blocks are imported as `PAYLOAD_STATUS_NOT_VALIDATED`.
- `NODE_FLAG_JUSTIFIED_PENDING`: a `NODE_WORK_JUSTIFIED_STATE` is queued.
- `NODE_FLAG_SUBSCRIBED`: the topics of `fork_digest` are subscribed.
- `NODE_FLAG_SYNCING`: a BeaconBlocksByRange request of the node is open.
- `NODE_FLAG_ENGINE`: the node drives an execution engine; `NODE_FLAG_FCU`: an engine_forkchoiceUpdated is due.
- `NODE_FLAG_DISCV5`: the shell runs asm-discv5 for the node.
- `NODE_FLAG_DB`: the node archives the finalized history in its `Db`, and the shell keeps the segment files: it does each `NODE_ACT_DB_APPEND` and gives the bytes of a `NODE_DB_REF`.
- `NODE_FLAG_EL_OFFLINE`: the last connection to the execution engine failed or closed before an answer, and no answer came since.
- `NODE_FLAG_FEW_STATES`: the node keeps the post-states of the head, the justified root, F and the blocks with no child, and rebuilds the others when it needs them.
- `NODE_FLAG_SUPERNODE`: the node custodies every custody group: `columns` holds every column, and its MetaData and ENR give `NUMBER_OF_CUSTODY_GROUPS` (lantern_node_init).
- `NODE_FLAG_BUILDER` (2048): the node has a builder (app.md `--builder`): it keeps the anchor's `builder_host`, and makes the builder calls (below).
- `columns` has room for `NUMBER_OF_COLUMNS` of the preset, at most 128.

## Type `NodeRoom`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `blocks` | u64 | Capacity of `blocks` |
| 8 | `checkpoints` | u64 | Capacity of `checkpoints` |
| 16 | `pow_blocks` | u64 | Capacity of `pow_blocks` |
| 24 | `peers` | u64 | Capacity of `peers` |
| 32 | `streams` | u64 | Capacity of `streams` |
| 40 | `request_bytes` | u64 | Request bytes each stream holds, below 2^32 |
| 48 | `p2p_out` | u64 | Bytes of the events in `p2p_out` |
| 56 | `messages` | u64 | Capacity of `messages` |
| 64 | `blobs` | u64 | Capacity of `blobs` |
| 72 | `engine_bytes` | u64 | Bytes of `engine_in` |
| 80 | `db_slots` | u64 | Slots of the `Db`: a `DbRoom` with `db_roots` |
| 88 | `db_roots` | u64 | Roots of the `Db`, a power of two |
| 96 | `api_streams` | u64 | Capacity of `api` |
| 104 | `pool` | u64 | Capacity of `pool` |
| 112 | `proposers` | u64 | Capacity of `proposers` |

## Type `NodeProposer`

A validator's fee recipient (beacon-api.md, prepareBeaconProposer).

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `validator_index` | u64 | The validator |
| 8 | `until_epoch` | u64 | The entry holds while the store's epoch is below it; 0 for a free entry |
| 16 | `fee_recipient` | ExecutionAddress | 20 bytes |
| 40 | `registered` | u64 | 1 when the entry holds the validator's latest registration (beacon-api.md, registerValidator) |
| 48 | `registration_fee_recipient` | ExecutionAddress | 20 bytes: of the registration |
| 72 | `gas_limit` | u64 | Of the registration |
| 80 | `timestamp` | u64 | Of the registration |
| 88 | `pubkey` | BLSPubkey | 48 bytes: of the registration |

### Rules

- `NodeProposer__mem` (136) bytes.
- A free entry: `until_epoch` at most the store's epoch and `registered` 0.

## Type `ProduceDraft`

The body draft of a produceBlockV3 (beacon-api.md), which the fold works fill in place.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `aggregates` | u64 | The `DraftAggregate` entries in use |
| 8 | `ops` | u64 | The bytes in use of the operations area |
| 16 | `sync_set` | u64 | 1 once a sync committee message joined |
| 24 | `sync_bits` | `SYNC_COMMITTEE_SIZE` / 8 bytes | The sync aggregate's bits |
| 24 + `SYNC_COMMITTEE_SIZE` / 8 | `sync_signature` | 96 bytes | Their signature |
| `PRODUCE_DRAFT_AGGREGATES` | | `DraftAggregate` entries | `MAX_COMMITTEES_PER_SLOT` * `SLOTS_PER_EPOCH` of them |
| `PRODUCE_DRAFT_OPS` | | `PRODUCE_DRAFT_OPS_ROOM` bytes | The operations, each a record: its topic (u64), its length (u64), its SSZ bytes, then zero bytes to a multiple of 8 |

### Rules

- `PRODUCE_DRAFT_AGGREGATES`: 24 + `SYNC_COMMITTEE_SIZE` / 8 + 96, to a multiple of 8. `PRODUCE_DRAFT_OPS`: that + the entries' bytes. `PRODUCE_DRAFT_OPS_ROOM`: the SSZ bytes of `MAX_PROPOSER_SLASHINGS` proposer slashings, `MAX_ATTESTER_SLASHINGS` (electra: `MAX_ATTESTER_SLASHINGS_ELECTRA`) attester slashings at their largest, `MAX_VOLUNTARY_EXITS` exits and `MAX_BLS_TO_EXECUTION_CHANGES` changes, and 24 bytes for each. `ProduceDraft__size`: the operations area's end.

## Type `DraftAggregate`

The aggregate of the pool's attestations of one `AttestationData` and committee.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `data` | 128 bytes | The `AttestationData`'s SSZ bytes |
| 128 | `committee_index` | u64 | |
| 136 | `length` | u64 | The committee's length |
| 144 | `order` | u64 | The pool index of its first attestation |
| 152 | `bits` | `MAX_VALIDATORS_PER_COMMITTEE` / 8 bytes | Bit p for the attester at place p in the committee |
| 152 + `MAX_VALIDATORS_PER_COMMITTEE` / 8 | `signature` | 96 bytes | |

### Rules

- `DraftAggregate__mem` (248 + `MAX_VALIDATORS_PER_COMMITTEE` / 8) bytes.

## Type `NodePool`

An operation of the pool (beacon-api.md, the pools).

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `topic` | u64 | `GOSSIP_VOLUNTARY_EXIT`, `GOSSIP_PROPOSER_SLASHING`, `GOSSIP_ATTESTER_SLASHING`, `GOSSIP_BLS_TO_EXECUTION_CHANGE`, `GOSSIP_BEACON_ATTESTATION` or `GOSSIP_SYNC_COMMITTEE`; 0 for a free entry |
| 8 | `state` | u64 | `NODE_POOL_KEPT` (1), or `NODE_POOL_CHECKING` (2) while its `NODE_WORK_POOL_CHECK` is queued |
| 16 | `data_id` | u64 | `BufferId` of its SSZ bytes |
| 24 | `length` | u64 | The bytes of its SSZ bytes |
| 32 | `fork` | u64 | `FORK_*` of the type it was decoded with |
| 40 | `slot` | u64 | An attestation: its `data.slot`; a sync committee message: its `slot`; else 0 |
| 48 | `index` | u64 | An attestation: its committee index; a sync committee message: bit i for each subnet i it is valid on; else 0 |
| 56 | `member` | u64 | A `SingleAttestation`: the attester's place in its committee + 2^16 times the committee's length; else 0 |

### Rules

- `NodePool__mem` (64) bytes.
- A new entry takes the first free entry, else the next; the part's count drops past the free entries at its end.

## Type `NodeBlock`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | hash_tree_root of the block |
| 32 | `parent_root` | Root | |
| 64 | `slot` | u64 | |
| 72 | `data_id` | u64 | `BufferId` of the `SignedBeaconBlock`'s SSZ bytes |
| 80 | `state_id` | u64 | `BufferId` of its post-state, 0 until its import is queued; 0 too for an ancestor of F, or for a block above F's slot whose post-state the node let go (it rebuilds it) |
| 88 | `status` | u64 | `NODE_BLOCK_WAITING`, `NODE_BLOCK_IMPORTING`, `NODE_BLOCK_IMPORTED`, `NODE_BLOCK_INVALID`, `NODE_BLOCK_HASHING` while a `NODE_WORK_SYNC_BLOCK` of its root is queued (root 0), or `NODE_BLOCK_BLOBS` while it needs blob sidecars the node does not hold |
| 96 | `data_available` | u64 | 1 or 0: from its `NODE_EV_BLOCK`, or 1 for a block from the network once its blobs are held |
| 104 | `result` | u64 | The result of its last import |
| 112 | `blobs` | u64 | For a block from the network: the length of its body's `blob_kzg_commitments`, 0 before deneb |
| 120 | `payload_status` | u64 | With `NODE_FLAG_ENGINE`: `PAYLOAD_STATUS_*` of the execution engine's answer, for its import |
| 128 | `retry` | u64 | The slot from which its engine_newPayload may go again |
| 136 | `length` | u64 | The bytes of its SSZ bytes |

### Rules

- `NodeBlock__mem` (144) bytes.
- With `NODE_FLAG_ENGINE`, the status `NODE_BLOCK_PAYLOAD` while its engine_newPayload is due, and `NODE_BLOCK_EXECUTING` while it is queued or sent.
- A block of the backfill: `NODE_BLOCK_BF_CHECKING` while its `NODE_WORK_BACKFILL` is queued, then `NODE_BLOCK_BACKFILL` with its root until it joins the `Db` or goes. Neither is a block of the store.
- `NODE_BLOCK_FREE`: an entry the prune freed, with `root` and `parent_root` all 0xff bytes, `slot` 2^64 - 1, and `data_id` and `state_id` 0. A new block takes the first free entry, else the next.

## Type `NodeCheckpoint`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `epoch` | u64 | |
| 8 | `root` | Root | |
| 40 | `state_id` | u64 | `BufferId` of the checkpoint state |

### Rules

- `NodeCheckpoint__mem` (48) bytes. The first 40 bytes are a `Checkpoint`.
- An entry the prune freed has `epoch` 2^64 - 1, a `root` of all 0xff bytes and `state_id` 0. A new checkpoint takes the first free entry, else the next.

## Type `NodePeer`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `handle` | u64 | The libp2p peer Handle |
| 8 | `direction` | u64 | `LIBP2P_INBOUND` or `LIBP2P_OUTBOUND` |
| 16 | `flags` | u64 | `NODE_PEER_STATUS`: a Status of the peer was read; `NODE_PEER_METADATA_ASKED`: the node sent it a GetMetaData v3; `NODE_PEER_METADATA`: its MetaData v3 was read |
| 24 | `fork_digest` | u64 | Its Status: 4 bytes |
| 32 | `finalized_root` | Root | |
| 64 | `finalized_epoch` | u64 | |
| 72 | `head_root` | Root | |
| 104 | `head_slot` | u64 | |
| 112 | `earliest_slot` | u64 | Status v2 `earliest_available_slot`, else 0 |
| 120 | `id_len` | u64 | |
| 128 | `id` | 48 bytes | The peer ID |
| 176 | `custody` | 16 bytes | With `NODE_PEER_METADATA`, the columns the peer custodies, as `columns` of `Node` |
| 192 | `address` | asm-libp2p `Address` | The address of its connection, of `PEER_CONNECTED` |
| 224 | `transport` | u64 | `LIBP2P_TCP` or `LIBP2P_QUIC`, of `PEER_CONNECTED` |

### Rules

- `NodePeer__mem` (232) bytes.

## Type `NodeStream`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `handle` | u64 | The libp2p stream Handle |
| 8 | `peer` | u64 | The libp2p peer Handle |
| 16 | `method` | u64 | `REQRESP_*` |
| 24 | `version` | u64 | |
| 32 | `state` | u64 | `NODE_STREAM_REQUEST` or `NODE_STREAM_EOF` while the request is read; `NODE_STREAM_SERVE` or `NODE_STREAM_SERVING` while its blocks go out; `NODE_STREAM_OPENING` or `NODE_STREAM_RESPONSE` for a request of the node |
| 40 | `next` | u64 | The index of the next BufferId to send; for a request of the node, 1 after `STREAM_EOF` |
| 48 | `list` | ByteList | The request bytes, then the BufferIds of the blocks to send: `size`, `offset` 24, `count`, the bytes at 72 |

### Rules

- `stream_bytes` of the node: `NodeStream__fixed` (72) + the request room.

## Type `NodeMessage`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `handle` | u64 | The libp2p message Handle |
| 8 | `peer` | u64 | The libp2p peer Handle |
| 16 | `topic` | u64 | `GOSSIP_*`, or 0 for a topic of no name |
| 24 | `subnet` | u64 | |
| 32 | `data_id` | u64 | `BufferId` of the uncompressed bytes, or 0 |
| 40 | `state` | u64 | `NODE_MESSAGE_ID`, `NODE_MESSAGE_VALIDATING`, `NODE_MESSAGE_NO_ROOM`, `NODE_MESSAGE_CORRUPT`, `NODE_MESSAGE_OTHER_DIGEST`, or for a valid aggregate `NODE_MESSAGE_VOTE` and `NODE_MESSAGE_VOTING` |
| 48 | `slot` | u64 | The slot of its block header, or of an aggregate's data |
| 56 | `parent_root` | Root | The parent root of its block header |
| 88 | `length` | u64 | The bytes of its uncompressed data |

### Rules

- `NodeMessage__mem` (96) bytes.

## Type `NodeBlob`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `block_root` | Root | hash_tree_root of its `signed_block_header.message`, 0 while `NODE_BLOB_VERIFYING` |
| 32 | `index` | u64 | |
| 40 | `slot` | u64 | The slot of its block header |
| 48 | `data_id` | u64 | `BufferId` of the `BlobSidecar`'s SSZ bytes, or for a slot of fulu or later the `DataColumnSidecar`'s |
| 56 | `status` | u64 | `NODE_BLOB_VERIFYING` while a `NODE_WORK_BLOB` of it is queued, `NODE_BLOB_VALID`, `NODE_BLOB_INVALID` with its bytes freed, or `NODE_BLOB_FREE` after the prune, with `block_root` all 0xff bytes and `slot` 2^64 - 1 |
| 64 | `length` | u64 | The bytes of its SSZ bytes |

### Rules

- `NodeBlob__mem` (72) bytes.
- An entry of a slot whose fork is fulu or later holds a column sidecar, and `index` is its column.
- The node holds at most one `NODE_BLOB_VALID` entry of each block root and index.

## Type `NodeApi`

A Beacon API answer the node sends in chunks.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `connection` | u64 | The connection; 0 for a free entry |
| 8 | `op` | u64 | `API_OP_GET_BLOCK_V2`, `API_OP_GET_STATE_V2`, one of the five validator streams, `API_OP_GET_EPOCH_COMMITTEES`, `API_OP_EVENTSTREAM`, or one of the five pool streams |
| 16 | `flags` | u64 | `API_STREAM_*` |
| 24 | `data` | u64 | The `BufferId` of the SSZ bytes, or a `NODE_DB_REF`; the validator streams: of the `ValidatorRef` items, or 0 |
| 32 | `fork` | u64 | `FORK_*` of the block's or the state's slot |
| 40 | `sent` | u64 | SSZ: the bytes of `data` sent; eventstream: the bytes sent since the last `NODE_EV_API_SENT`; a pool stream: the fork of the entry at `slot` |
| 48 | `cursor` | `JsonCursor` | JSON: where lantern_json_encode_ssz goes on; the validator streams: the next index at 0, the status bits at 8; eventstream: the topic bits at 0 |
| 648 | `slot` | u64 | The slot of the block or the state; a pool stream: the index of the pool entry it writes |
| 656 | `state` | u64 | The validator streams: the id of the state they read; the blob stream: the id of its versioned hashes, or 0 |
| 664 | `member` | u64 | A pool stream: the `member` of the pool entry at `slot`; a sidecar stream and the blob stream: the index of the sidecar it writes |
| 672 | `filter_slot` | u64 | A pool stream: the slot its entries have, or 2^64 - 1 for any; a sidecar stream: the bits of its indices below 64; the blob stream from fulu: the blob it writes |
| 680 | `filter_index` | u64 | A pool stream: the committee index its entries have, or 2^64 - 1 for any; a sidecar stream: the bits of its indices from 64 |
| 688 | `root` | Root | A sidecar stream and the blob stream: the block's root |

### Rules

- `NodeApi__mem` (720) bytes.
- `flags`: `API_STREAM_CLOSE` (1) the connection closes after the answer; `API_STREAM_HTTP10` (2) an HTTP/1.0 request; `API_STREAM_SSZ` (4) the answer is SSZ, else JSON; `API_STREAM_OWN` (8) the stream frees `data` at its end; `API_STREAM_BUSY` (16) a `NODE_WORK_API_CHUNK` is queued; `API_STREAM_GONE` (32) the connection closed; `API_STREAM_STARTED` (64) the head went; `API_STREAM_CHUNKED` (128) the body goes with `Transfer-Encoding: chunked`; `API_STREAM_OPTIMISTIC` (256) and `API_STREAM_FINALIZED` (512) the JSON's `execution_optimistic` and `finalized`; `API_STREAM_DONE` (1024), in a `NODE_EV_WORK_DONE` only, the chunk ends the answer; `API_STREAM_LOOKUP` (2048) the entry waits for a `NODE_WORK_API_LOOKUP`, and sends no chunk; `API_STREAM_OWN_STATE` (4096) the stream frees `state` at its end; `API_STREAM_ITEMS` (8192) a pool stream wrote an entry; `API_STREAM_ITEM_DONE` (16384), in a `NODE_EV_WORK_DONE` only, the chunk ends an entry; `API_STREAM_FOLD` (32768) getAggregatedAttestationV2 folds its entries; `API_STREAM_PRODUCE_OWN` (65536) a produceBlockV3 frees the pool bytes of its fold in flight; `API_STREAM_PRODUCE_FORCED` (131072) a produceBlockV3 made its own payload preparation; `API_STREAM_BLOB_SKIP` (262144), in a `NODE_EV_WORK_DONE` only, the blob stream skips the rest of a blob; `API_STREAM_PRODUCE_BLINDED` (524288) a produceBlockV3 answers a blinded block; `API_STREAM_REPLAY` (1048576) a lookup entry waits for the replay.
- A `NODE_ACT_API_SEND` with `last` 0 is never more than `NODE_API_CHUNK` bytes, so a shell with room for two chunks in flight can take the next chunk at each `NODE_EV_API_SENT`.

## Type `NodeGossip`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `seen` | address | `Seen` |
| 8 | `store` | address | `Store` |
| 16 | `time_ms` | u64 | `current_time_ms` |
| 24 | `topic` | u64 | `GOSSIP_*` |
| 32 | `subnet` | u64 | |
| 40 | `head` | address | The head's post-state |
| 48 | `proposer` | address | A copy of the parent's post-state, or 0 |
| 56 | `justified` | address | The post-state of the justified root, or 0 |
| 64 | `settings` | address | asm-crypto `KzgSettings`, or 0 |
| 72 | `config` | address | `Config` |

### Rules

- `NodeGossip__mem` (80) bytes.

## Type `NodeAnchor`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | hash_tree_root of the anchor block |
| 32 | `slot` | u64 | |
| 40 | `genesis_validators_root` | Root | Of the anchor state |
| 72 | `jwt_secret` | Bytes32 | With `NODE_FLAG_ENGINE` |
| 104 | `engine_host_len` | u64 | With `NODE_FLAG_ENGINE`, at most `NODE_ENGINE_HOST_MAX` (64) |
| 112 | `engine_host` | 64 bytes | |
| 176 | `node_id` | `NodeID` | The node ID of the node's secp256k1 key, as a number in 32 little-endian bytes |
| 208 | `history_slot` | u64 | The first slot of the `Db`, as of the segments the shell kept: the `Db` starts at the segment of the lower of it and `slot` |
| 216 | `builder_host_len` | u64 | With `NODE_FLAG_BUILDER`, at most `NODE_ENGINE_HOST_MAX` (64) |
| 224 | `builder_host` | 64 bytes | The `Host` of the Builder API requests |
| 288 | | | Size |

## Type `NodeStepResult`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `accepted` | u64 | Events handled, from the first |
| 8 | `wakeup` | u64 | Monotonic ms by which the next step is due: libp2p's WAKEUP, the tick's time while the node holds events for libp2p, 2^64 - 1 with no `p2p` |
| 16 | `short` | u64 | With `LANTERN_BUFFER_TOO_SMALL`: the buffer with too little room, `NODE_SHORT_ACTIONS` (1), `NODE_SHORT_NODE` (2) or `NODE_SHORT_SCRATCH` (3) |
| 24 | `room` | u64 | With `NODE_SHORT_NODE`: the byte offset in `NodeRoom` of the capacity with too little room |
| 32 | | | Size |

## Type `NodeEvents`

The events of one step: a ByteList whose bytes are `NodeEvent` entries one after another.

## Type `NodeEvent`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the event, a multiple of 8 |
| 8 | `kind` | u64 | `NODE_EV_*` |
| 16 | `arg` | u64 | `NODE_EV_TICK`: time_ms; `NODE_EV_BLOCK`: data_available; `NODE_EV_ATTESTATION`: is_from_block; `NODE_EV_P2P`: the libp2p event starts here; `NODE_EV_ENGINE`: 0 bytes, 1 the connection failed; `NODE_EV_API`: the connection |
| 24 | `bytes` | ByteList | `NODE_EV_BLOCK`, `NODE_EV_ATTESTATION`, `NODE_EV_ATTESTER_SLASHING`, `NODE_EV_POW_BLOCK`: the SSZ bytes; `NODE_EV_ENGINE` with arg 0: the bytes of the execution engine's connection; `NODE_EV_ENR`: a node record; `NODE_EV_API`: an `HttpRequest`; `NODE_EV_API_IDENTITY`: an `ApiIdentity`; offset 24 |

### Rules

- `NODE_EV_TICK`: 24 bytes or more.
- An event with `bytes`: its ByteList's offset is 24 and its bytes end inside the event.
- `NODE_EV_WORK_DONE`: `NODE_EV_WORK_DONE_SIZE` bytes; offsets 16 to 71 are those of the work's `NodeAction`, `result` at `NodeEvent_result`, and a Checkpoint at `NodeEvent_checkpoint` for `LANTERN_NEED_TARGET_STATE`. For `NODE_WORK_SERVE`, and `NODE_WORK_NEW_PAYLOAD` and `NODE_WORK_FORKCHOICE` of `LANTERN_VALID`, a ByteList of the chunk or request at `NodeEvent_chunk`, offset 24, inside the event. For `NODE_WORK_BACKFILL`, the block's root at `NodeEvent_root`. For `NODE_WORK_GOSSIP` of a valid beacon_block and `NODE_WORK_SYNC_BLOCK`, its root at `NodeEvent_root` and its blob count at `NodeEvent_index`; of a valid blob_sidecar, its block root at `NodeEvent_root` and its index at `NodeEvent_index`; for `NODE_WORK_BLOB`, its block root at `NodeEvent_root`. For `NODE_WORK_API_SUBMIT` of `LANTERN_VALID`, its records (lantern_node_run) in a ByteList at `NodeEvent_chunk`, offset 24, inside the event, and their count at `NodeEvent_index`.
- `NODE_EV_P2P`: a libp2p shell result `Event` from 16, its size a multiple of 8 inside the event; only with `p2p`.
- `NODE_EV_ENGINE`: arg 0 or 1; with 0, the event has `bytes`; only with `NODE_FLAG_ENGINE`.
- `NODE_EV_BUILDER` (15): arg a builder call, + 256 for the failure bit; without it, the event has `bytes`, the builder's whole answer; only with `NODE_FLAG_BUILDER`.
- `NODE_EV_ENR`: has `bytes`; only with `p2p`.
- `NODE_EV_PAYLOAD_STATUS` is `LANTERN_INVALID_EVENT` in this version: the answers come in `NODE_EV_ENGINE`.
- `NODE_EV_API`: `arg` the connection, not 0; `bytes` an `HttpRequest` of lantern_http_request, of `LANTERN_OK` or `LANTERN_INVALID_HTTP`: its `size` the ByteList's count, at least `HTTP_REQUEST_FIXED` and a multiple of 8; with `status` 0, each of its parts inside it.
- `NODE_EV_API_IDENTITY`: `bytes` an `ApiIdentity` of `API_IDENTITY_SIZE` bytes, each text's length at most its room and its bytes as the type says.
- `NODE_EV_API_SENT`, `NODE_EV_API_CLOSED`: 24 bytes or more; `arg` the connection.
- `NODE_EV_WORK_DONE` of `NODE_WORK_API_CHUNK` with `LANTERN_VALID`: at `NodeEvent_api` (`NodeEvent_chunk`) the entry's `sent`, at + 8 its `flags`, at + 16 its `JsonCursor`, after the chunk; at `NodeEvent_api_bytes` (`NodeEvent_api` + 616) a ByteList of the chunk's bytes, offset 24, inside the event.

## Type `NodeActions`

The actions of one step: a ByteList whose bytes are `NodeAction` entries one after another. The step adds after its `count` bytes.

## Type `NodeAction`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the action, a multiple of 8 |
| 8 | `kind` | u64 | `NODE_ACT_*` |
| 16 | `work_kind` or `id` | u64 | `NODE_ACT_WORK`: `NODE_WORK_*`; else the id |
| 24 | `state_a` or `bytes` | u64 or ByteList | `NODE_ACT_WORK`: a `BufferId`; `NODE_ACT_STATE_COPY`: the new id; `NODE_ACT_BYTES_PUT`: the bytes, offset 24 |
| 32 | `state_b` | u64 | `NODE_ACT_WORK`: a `BufferId` |
| 40 | `state_c` | u64 | `NODE_ACT_WORK`: a `BufferId` |
| 48 | `data` | u64 | `NODE_ACT_WORK`: a `BufferId` of bytes, or for a SERVE, API_ENCODE or API_CHUNK a `NODE_DB_REF` |
| 56 | `target` | u64 | `NODE_ACT_WORK`: a `NodeBlock` index (also of a SYNC_BLOCK), a `NodeCheckpoint` index, a `NodeBlob` index, a stream Handle, a message Handle, or the connection of an API_ENCODE or API_CHUNK |
| 64 | `arg` | u64 | `NODE_ACT_WORK`: `is_from_block` of an attestation, the epoch of a checkpoint, the protocol version + 256 * the method of a SERVE, topic + 256 * subnet of a GOSSIP, the JSON-RPC id of a NEW_PAYLOAD or FORKCHOICE, the slot of a SLOTS, the fork of an UPGRADE, or the `NodeApi` index of an API_CHUNK |

### Rules

- `NODE_ACT_BYTES_PUT`: keep the ByteList at 24 as the bytes of the id at 16.
- `NODE_ACT_BYTES_NEW`: keep a new ByteList of the size at 24 (offset 24, length the size less 24, every byte after the header zero) as the bytes of the id at 16. Works may write those bytes.
- `NODE_ACT_STATE_COPY`: copy the state of the id at 16 as the id at 24.
- `NODE_ACT_STATE_FREE`, `NODE_ACT_BYTES_FREE`: free the id at 16.
- `NODE_ACT_WORK`: `NODE_ACT_WORK_SIZE` bytes; call lantern_node_run.
- `NODE_ACT_P2P_LIST`: a ByteList of libp2p `Action` values from 16, offset 24; do its DIAL, ADOPT, REFUSE, SEND, CLOSE and SEND_DATAGRAM in order, and skip the others.
- `NODE_ACT_DISCV5`: a ByteList at 24, offset 24, of asm-discv5 events: pass them to discv5_step.
- `NODE_ACT_DB_APPEND` (`NODE_ACT_DB_APPEND_SIZE`, 128 bytes): 16 a `BufferId` of bytes, 24 a segment's number, 32 1 for a sidecar segment and 0 for a block segment, 40 an offset, 48 a `DbRecord`. Write the record at the offset of the segment file, its end: the `DbRecord`, the bytes, and zero bytes to a multiple of 8. The first record of a segment that a run writes truncates the file to its offset first, so a torn end or an older run's records go.
- `NODE_ACT_DB_STATE` (`NODE_ACT_DB_STATE_SIZE`, 40 bytes): 16 the `BufferId` of a finalized block's post-state, 24 the `BufferId` of the block's SSZ bytes, 32 its slot. The shell may keep them, so that a later start has an anchor whose blocks the `Db` holds.
- `NODE_ACT_DB_DROP` (`NODE_ACT_DB_DROP_SIZE`, 32 bytes): 16 a segment, 24 1 for a sidecar segment, else 0. The shell deletes the segment's file; a later record of that segment starts a new file.
- `NODE_ACT_BUILDER` (16): 16 a builder call, 24 a ByteList of an HTTP request (offset 24). The shell opens a new connection to the builder, writes the bytes, and reads to the connection's end (the request has `Connection: close`), then passes the bytes it read in a `NODE_EV_BUILDER` of the call; a connection that fails before it reads any byte gives a `NODE_EV_BUILDER` with the failure bit.
- A `NODE_DB_REF` is a `BufferId` with bit 63 set: bit 62 set for a sidecar segment, the segment's number in bits 48 to 61, and the offset of a record in bits 0 to 47. As the `data` of a SERVE, API_ENCODE, API_CHUNK or REPLAY work it names the SSZ bytes of that record: the shell gives lantern_node_run the record's ByteList at its byte 56, in place in the segment's memory.
- `NODE_ACT_API_SEND`: 16 the connection, 24 `last`, 1 when the bytes end the answer, else 0; a ByteList at 32, offset 24: write its bytes to the connection, after those before. The shell reads the next request of the connection after the bytes of `last` 1.
- `NODE_ACT_API_CLOSE` (`NODE_ACT_API_CLOSE_SIZE`, 24 bytes): 16 the connection: close it once its bytes are written.
- `NODE_ACT_STATE_BYTES` (`NODE_ACT_STATE_BYTES_SIZE`, 32 bytes): 16 the id of a state, 24 a new id: keep lantern_node_state_bytes of the fork of the state's slot as the bytes of the new id, a ByteList as `NODE_ACT_BYTES_PUT` keeps one. With no room for them, keep a ByteList of no bytes.
- An API action of a connection that closed is dropped.
- `NODE_ACT_ENGINE`: a ByteList at 24, offset 24: write its bytes to the connection to the execution engine, opening one when there is none, and pass what the engine sends in `NODE_EV_ENGINE` events; a connection that fails or closes before an answer is a `NODE_EV_ENGINE` with arg 1.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_node_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_step`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_run`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_protocols`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_import`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_block_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_proposers`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_attestation_data`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_attester_duties`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_liveness`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_block_rewards`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_sync_rewards`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_payload_parent`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_sidecar_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_randao`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_sync_committee`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_proposer_lookahead`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_weights`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_data_root`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_sync_subnets`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_sync_positions`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_produce_check`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_payload_result`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_produce_fold`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_produce_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_produce_bid`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_publish_decode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_publish_sidecars`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_publish_check`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_pending`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_blinded_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_event_roots`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_attestation`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_attester_slashing`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_gossip`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_blob_sidecar`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_column_sidecar`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_db_scan`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_anchor`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_anchor_block`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_state_bytes`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_upgrade`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_replay`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_backfill`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_block_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_state_checkpoints`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_node_new_payload`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_json`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
