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
- `das-core.md` of fulu, Custody sampling: the node samples the columns of the groups of get_custody_groups(node_id, max(`SAMPLES_PER_SLOT`, custody_group_count)); its custody groups are the first custody_group_count of them. Column gossip: the node joins the subnets of the columns it samples.
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
- Backfill (fc_backfill_check, after fc_sync_check, for a case whose chain has two blocks or more), and in fulu a second time with the peer's Status `earliest_available_slot` the slot of the chain's last block: a new node with `NODE_FLAG_DB` starts from the post-state and the block of the chain's last block, as a checkpoint start does, at the case's last tick, and gets a peer whose Status head is that block. The peer answers each BeaconBlocksByRange with the chain's blocks of the range, the anchor block of the case included. Each block of the chain from the last down to the case anchor's child must reach the `Db` with its root, each with the sidecars of the case (the peer answers BlobSidecarsByRange and DataColumnSidecarsByRange too), and `backfill_slot` and `earliest_slot` must be the lowest of them. Run again with the signature of one block changed: that block and those below it must not reach the `Db`.
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
  - The node has `NODE_FLAG_DISCV5`: its `NODE_ACT_DISCV5` actions must set `eth2` to lantern_compute_enr_fork_id at the anchor's epoch, `attnets` to the bits of the node's subnets at that epoch (lantern_compute_subscribed_subnets of its node ID), from altair `syncnets` to 1 zero byte, in fulu `cgc` to `CUSTODY_REQUIREMENT` and `nfd` to lantern_compute_next_fork_digest, and ask for a lookup.
- The `fork_choice-get_head` and `fork_choice-on_block` cases in node mode, after their steps: the runner opens the same network, and the node serves the chain of the case's last checked head, which the runner builds from the case's valid blocks by `parent_root`.
  - BeaconBlocksByRange v2 from the anchor's slot to the head's must give each block of the chain, in slot order.
  - BeaconBlocksByRoot v2 of the head, a root of no block, and the chain's first block must give the head and the first block.
  - Each chunk must have result 0, the block's SSZ bytes, and compute_fork_digest of the block's epoch as context bytes.
- The `fork_choice-get_head` and `fork_choice-on_block` cases a third time, over gossip: each case reports with ` (gossip)` after its name.
  - Only cases with no `payload_status` step whose valid blocks each have their own slot and come at or after the start of that slot.
  - The runner opens the same network. The node's topics must reach the peer.
  - Each valid block goes from the peer as a beacon_block message, Snappy compressed, on the topic of the block's epoch. The node must import it.
  - Each valid attester slashing goes from the peer on the attester_slashing topic of the last tick's epoch. One the node does not apply goes again as a `NODE_EV_ATTESTER_SLASHING`. A case with valid attester slashings must apply one over gossip.
  - Each valid attestation goes from the peer first as a `SignedAggregateAndProof` on the beacon_aggregate_and_proof topic of the last tick's epoch: its first attester aggregates it, signed with the pyspec test keys (validator i has the secret key i + 1); from electra, only an attestation of one committee. The vote the node applies from it must be valid. One the node does not apply goes again as a `NODE_EV_ATTESTATION`. The runner counts both in a NOTE.
  - The other steps go as in node mode; the checks must hold.
- The same cases in node mode, after the serving check: a new node at the case's anchor, at the case's last tick, syncs the chain of the last checked head.
  - The runner's peer has a secp256k1 key. The node gets a `NODE_EV_ENR` of the peer's record, made with asm-discv5 from that key, with an `ip`, a `tcp` port and the `eth2` of lantern_compute_enr_fork_id at the case's epoch. The node must dial the peer and send its Status; the peer answers with a Status whose head is the chain's last block, and answers each BeaconBlocksByRange request of the node with the chain's blocks in the range.
  - It answers each BlobSidecarsByRange request with the sidecars of the case's `node-blobs` case of the chain's blocks in the range, in (slot, index) order, with compute_fork_digest of the slot's epoch as context bytes.
  - Each block of the chain must be `NODE_BLOCK_IMPORTED`, and the node's `head_root` must be the chain's last block.
  - Each sidecar it sent must be a `NODE_BLOB_VALID` entry of the node.
  - Then the node serves them: BlobSidecarsByRange v1 from the anchor's slot to the head's must give each sidecar of the chain in (slot, index) order; BlobSidecarsByRoot v1 of the chain's sidecars from the last block to the first, with an identifier of no sidecar among them, must give those sidecars in that order. Each chunk must have result 0, the sidecar's SSZ bytes, and compute_fork_digest of its slot's epoch as context bytes.
  - A case with sidecars syncs again with a new node and no sidecars in the answers: no block of the chain with blob commitments, and no later one, may be `NODE_BLOCK_IMPORTED`.
  - In fulu, the node's `node_id` is the node ID of the peer's key, so its columns hold the peer's custody columns of any custody group count. The peer answers each GetMetaData v3 request with `custody_group_count` `NUMBER_OF_CUSTODY_GROUPS`, and each DataColumnSidecarsByRange request with the column sidecars of the case's `columns` steps of the chain's blocks in the range and of the request's columns, in (slot, index) order, with compute_fork_digest of the slot's epoch as context bytes. Each such request must ask for the node's columns, in ascending order.
  - Each column sidecar it sent must be a `NODE_BLOB_VALID` entry of the node.
  - Then the node serves them: DataColumnSidecarsByRange v1 of every column from the anchor's slot to the head's must give each of those sidecars in (slot, index) order; DataColumnSidecarsByRoot v1 of the chain's blocks from the last to the first, each with the node's columns and one column it does not sample, then an identifier of a root of no block, must give those sidecars in that order. Each chunk must have result 0, the sidecar's SSZ bytes, and compute_fork_digest of its slot's epoch as context bytes.
  - A fulu case with column sidecars syncs again with a new node and a peer whose MetaData gives `CUSTODY_REQUIREMENT` custody groups and whose answers hold no sidecars: each DataColumnSidecarsByRange of the node must ask for the columns of get_custody_groups(the peer's node ID, `CUSTODY_REQUIREMENT`), in ascending order, and no block of the chain with blob commitments, and no later one, may be `NODE_BLOCK_IMPORTED`.
- Lantern's cases `<preset>-<fork>-node-api.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec: the anchor of the `p2p` cases, an `ApiIdentity`, a time, and requests with the response of each, written by the rules of [beacon-api.md](beacon-api.md#common-rules) from the spec's values.
  - The runner gives the node a `NODE_EV_TICK` of the time and a `NODE_EV_API_IDENTITY`, then each request on its own connection: lantern_http_request with `head_max` 16384 and `body_max` 1048576, then a `NODE_EV_API` of its `HttpRequest`, of `LANTERN_OK` or `LANTERN_INVALID_HTTP`; it plays the shell until the node settles.
  - The bytes of the connection's `NODE_ACT_API_SEND` actions must be the case's response, the last with `last` 1 and no other; the connection must get one `NODE_ACT_API_CLOSE` after them when the case says it closes, else none.
  - Requests: each operation the node answers; the head by `head` and by its root, and another root (404); each other operation (501); route faults (400, 404, 405 with `Allow`, 406, 414, 415); faulty requests (400, 413, 431, 501, 505); `Connection: close`; HTTP/1.0 with and without `keep-alive`; getHealth with `syncing_status`; getStateV2 of `head` as JSON and as SSZ, over HTTP/1.1 and HTTP/1.0; getBlockV2 of `head`, whose anchor block has no bytes (404).
  - The runner keeps each id of a `NODE_ACT_STATE_BYTES`, with lantern_node_state_bytes of the fork of the state's slot, and gives a `NODE_EV_API_SENT` of the connection after each `NODE_ACT_API_SEND` with `last` 0.
  - Each request runs twice: with an event of `NodeEvent_api_bytes` + 24 + `NODE_API_CHUNK` bytes for each `NODE_WORK_API_CHUNK`, then with 2048 bytes after the chunk's ByteList header, or a 512th of the case's response when that is more, so that a large answer goes in some hundreds of chunks.
  - A response with `Transfer-Encoding: chunked` counts as the response with `Content-Length` of its chunks' bytes in place of that field and those bytes as its body; its chunks must keep RFC 9112 section 7.1. A JSON response over HTTP/1.0 with neither field counts as the response with `Content-Length` of its bytes after `Eth-Consensus-Version`, or after `Content-Type` with no `Eth-Consensus-Version`, and the connection must get a `NODE_ACT_API_CLOSE`.
  - After each answer the node must hold no `NodeApi` entry, each id of a `NODE_ACT_STATE_BYTES` must have had its `NODE_ACT_BYTES_FREE`, and the runner must hold the buffers it held before the request.
  - eventstream of `head,block,finalized_checkpoint` over HTTP/1.1, with and without `Connection: close`, and of `block` over HTTP/1.0, with and without `keep-alive`, and a topic of no name (400). For the two streams, the case's `streams` byte of the request is 1: the sends must be the head with `last` 0 and no close; then the runner gives a `NODE_EV_API_CLOSED` of the connection, and the node must hold no `NodeApi` entry.
  - The pools, in the case of the anchor at epoch EPOCHS_PER_HISTORICAL_VECTOR + 6 (past `SHARD_COMMITTEE_PERIOD`), whose validators have the keys of the spec's test helpers and some the BLS withdrawal credentials of other keys of them: submitPoolVoluntaryExit of a valid exit, of it again (seen: 200), of one with another key's signature (400) and of a body of no exit (400); submitPoolProposerSlashings of a valid slashing and of one of two equal headers (400); submitPoolAttesterSlashingsV2 of a valid slashing, and with a fork of another `AttesterSlashing` type (400); submitPoolBLSToExecutionChange of three changes whose second has another key's signature (400, its failure), and of a list with an item of no change (400); then the four pool GETs, each over HTTP/1.1 and HTTP/1.0. The answers come from the gossip validation of the spec module, with a `Seen` the case's requests fill in order, as each request runs twice (the two rooms of the runner). The runner gives the store the node's fork epochs, as the spec module has them, and after each answer holds no other buffers than those of the operations the pool took.
  - getProposerDuties: the epochs from the anchor's epoch - 1 to the epoch of the store's slot + 2, and one while the runner holds `NODE_FLAG_SYNCING` (the case's `syncing` byte of the request); in a third case, an anchor at slot 0, the epochs 0 to 2.
  - produceAttestationData: each slot from the anchor's - 1 to the store's + 1 with `committee_index` 1, one with `committee_index` 2^64 - 1, as SSZ, over HTTP/1.0, and one while the runner holds `NODE_FLAG_SYNCING`.
  - getAttesterDuties: the epochs from the anchor's epoch - 1 to the epoch of the store's slot + 2 with indices of active and inactive validators, one past the validator count and one twice; no body, an empty array, a public key, over HTTP/1.0, and one while the runner holds `NODE_FLAG_SYNCING`.
  - getEpochCommittees: of `head` with no query, each `epoch` from the state's epoch - 1 to its epoch + 2, a `slot` of the epoch and one of another, `index` 0 and 1, a `slot` with an `index`, over HTTP/1.0, and with a `state_id` of `finalized`, of a slot and of a root; and in a second case, an anchor at epoch EPOCHS_PER_HISTORICAL_VECTOR + 6, the lowest epoch beacon-api.md takes and the one below it.
  - The six validator operations, of an anchor state with 8 more validators, one of each status but `active_ongoing`: each status and group of `status`; `id` items of indices and public keys, known, unknown and given twice; the bodies of the three POSTs; getStateValidator of an index and of a key, and of ones no validator has (404); the identities as SSZ; over HTTP/1.0 and with `Connection: close`; and with a `state_id` of a state root.
  - getSpec, getForkSchedule and getDepositContract, from the pinned config, presets and the spec module's constants, with the node's fork epochs; getSpec also over HTTP/1.0 and with `Connection: close`, and getForkSchedule over HTTP/1.0.
  - Lookup requests, the states from process_slots of the anchor state: getBlockRoot, getBlockHeader and getBlockV2 of `head`, `finalized`, `genesis`, the anchor's slot and the slots before and after it, the anchor's root and another root; getStateRoot, getStateFork and getStateFinalityCheckpoints of `head`, `finalized`, `justified`, `genesis`, the anchor's slot, each slot after it to the store's slot and the slot after that, the anchor state's root, the root of the state of the anchor's slot + 1, and another root; getStateV2 as JSON of `finalized` and of the anchor's slot + 2.
  - getStateV2 of `head` as SSZ with the small event, and a `NODE_EV_API_CLOSED` of the connection after its first chunk: the connection must get no more actions, and the node must hold no `NodeApi` entry and must free the state's bytes.
- The `fork_choice-get_head` and `fork_choice-on_block` cases in node mode, after their steps: getBlockHeader of `head` must answer 200 with the node's `head_root` as `root` and the slot of its block, and getStateFinalityCheckpoints of `head` with the checkpoints of the post-state the node keeps for the head.
  - The chain: the case's valid blocks from the node's `head_root` by `parent_root`. For each slot after the anchor's to the head's, getBlockRoot of the slot must answer the root of the chain's block of that slot, or 404 for a slot with none.
  - For each slot from the head's to the store's, at most an epoch and a slot past the head's: getStateRoot of the slot must answer the hash_tree_root of the head's post-state, processed to that slot with lantern_process_slots of the fork of the head's slot (from a slot it does not reach, the rest is skipped).
  - For each valid block of the case the node holds: getBlockHeader of its root must answer 200, with `canonical` true when it is on the chain, else false.
  - For each slot from the anchor's to the head's, at most `SLOTS_PER_HISTORICAL_ROOT` below the head's: getStateRoot of the state root of that slot (the head's post-state's hash_tree_root, or its `state_roots` entry) must answer that root; or 404, for a slot below that of the block of the store's finalized root.
  - getBlockV2 of `head` as SSZ must answer 200 with the SSZ bytes of the case's head block, and as JSON with `version` the name of the fork of its slot and a `data` that lantern_json_decode of the fork's `SignedBeaconBlock` gives as those bytes. A head that is the case's anchor must answer 404.
  - getStateV2 of `head` as SSZ must answer 200 with lantern_node_state_bytes of the post-state the node keeps for the head, and as JSON with a `data` that lantern_json_decode of the fork's `BeaconState` gives as those bytes.
  - Each a second time with 2048 bytes of room for each chunk, or a 128th of the state's SSZ bytes when that is more.
- Lantern's cases `<preset>-<fork>-node-events.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec: one for each `fork_choice-get_head` and `fork_choice-on_block` case, named after its handler and its name, `get_head/` or `on_block/` and the case's name. Its part `events` is a list with the text of the events (beacon-api.md, eventstream) the node must send in each step of the case, from a replay of the steps with the spec module:
  - get_forkchoice_store of the anchor state and block; a tick: on_tick of the step's seconds times 1000; a valid block: on_block, then on_attestation with `is_from_block` true of each attestation of its body and on_attester_slashing of each attester slashing, with the step's blobs and proofs (deneb, electra) or columns (fulu) as the data of retrieve_blobs_and_proofs or retrieve_column_sidecars; an attestation and an attester slashing: on_attestation and on_attester_slashing; a step with `valid` false, or a block the store holds already, as the node skips it: no change. A valid step the spec module refuses, or a `checks` step whose head is not the replay's, stops the generator.
  - The texts of a step: a block event for a valid block; then a head event when get_head is not the head of the last head event (at first the anchor's root); then a finalized_checkpoint event when the store's finalized epoch is above that of the last one (at first the anchor store's).
  - `execution_optimistic`: true for a block from bellatrix whose payload has a nonzero `block_hash` and whose last `payload_status` step before its block step, of that hash, is `SYNCING` or `ACCEPTED`.
  - The runner runs the case in node mode with three event streams, opened after the anchor: of `head,block,finalized_checkpoint` over HTTP/1.1, and of `block,chain_reorg` over HTTP/1.0, each with a `NODE_EV_API_SENT` after each send; and of `finalized_checkpoint,head,block` over HTTP/1.1 with none. After each step, the bytes of each stream's sends in the step, the chunks of HTTP/1.1 decoded, must be the step's texts of its topics; the third must get a `NODE_ACT_API_CLOSE` in place of the event whose bytes, with the head's and those of the events before it, would pass `NODE_API_CHUNK`, and no more actions. After the case, a `NODE_EV_API_CLOSED` of each stream: the node must hold no `NodeApi` entry.
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
- `LANTERN_INVALID_EVENT`: with `NODE_FLAG_ENGINE`, `engine_host_len` is above `NODE_ENGINE_HOST_MAX`.
- `LANTERN_INVALID_CUSTODY_GROUP`: max(`SAMPLES_PER_SLOT`, `CUSTODY_REQUIREMENT`) of `config` is above `NUMBER_OF_CUSTODY_GROUPS` or 128.

### Function does

- The node keeps the anchor's `node_id`; `attnets` is 0 until its first subscription.
- The node's `columns`: each column of compute_columns_for_custody_group of each group of get_custody_groups(the anchor's `node_id`, max(`SAMPLES_PER_SLOT`, `CUSTODY_REQUIREMENT`)) of `config`.
- With `NODE_FLAG_ENGINE`, the node keeps the anchor's `jwt_secret` and `engine_host`; its first JSON-RPC id is 1, and it takes `NODE_FLAG_FCU`, so the anchor's head goes to the engine first.

### Caller must

- Keep the anchor state as `BufferId` 1.
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

- Room: `actions` has the event bytes + 512 per event + `NODE_ACT_WORK_SIZE` per vote of each `NODE_EV_WORK_DONE` of a valid `NODE_WORK_IMPORT_BLOCK` (its `NodeEvent_index` + `NodeEvent_root` counts) + 384 per known block + 160 per `NodeBlob` entry + 32 per `NodeCheckpoint` entry + 2048 bytes free (the crossing of a fork boundary takes 208), and `LIBP2P_ACTIONS_MIN` + 40 more with `p2p`; with `p2p`, `p2p_out` has room for the libp2p events of the `NODE_EV_P2P` events, and `scratch` holds as many bytes again and `LIBP2P_SCRATCH_SIZE`; the blocks part has an entry free per `NODE_EV_BLOCK` and per `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`, and `NODE_SYNC_BATCH` more with `p2p`; the blobs part has an entry free per `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`, and with `p2p` `NODE_SYNC_BATCH` times the largest of `MAX_BLOBS_PER_BLOCK`, `MAX_BLOBS_PER_BLOCK_ELECTRA` and the count of `columns` more; the checkpoints part has 2 free per `NODE_EV_WORK_DONE`, and 2; the pow blocks part has an entry free per `NODE_EV_POW_BLOCK`; `engine_in` has room for the bytes of the `NODE_EV_ENGINE` events; `scratch` has `LANTERN_SCRATCH_FIXED` + 64 + 16 bytes per store node + 8 per `NodeBlock` entry, and `DISCV5_ENR_SIZE` + `DISCV5_ENR_SCRATCH` more with a `NODE_EV_ENR`, and `NODE_API_SCRATCH` (8192) + 4 bytes per byte of the `query` and 16 per byte of the `body` of the largest request more with a `NODE_EV_API`; `actions` has 2048 more, and 16 per byte of its `body`, per `NODE_EV_API`; the api part has an entry free per `NODE_EV_API`; `scratch` has `NODE_API_SCRATCH` more, and `actions` 2048 more, per `NODE_EV_WORK_DONE` of `NODE_WORK_API_LOOKUP`; `actions` has 1024 more per event for each `NodeApi` entry of eventstream, and 2 times `NODE_ACT_WORK_SIZE` more, and `NODE_ACT_WORK_SIZE` more for each pool entry; per `NODE_EV_WORK_DONE` of `NODE_WORK_API_SUBMIT`, `actions` has 2048 more and, of `LANTERN_VALID`, its bytes once more, and the api part an entry free; with `NODE_FLAG_SUBSCRIBED` and `p2p`, `p2p_out` has room for 2 times its bytes and 512 more per operation, and `scratch` the largest of `SNAPPY_SCRATCH_COMPRESS` + 192 + its bytes more; the pool part asks for no room: a full pool keeps no more operations, and those still go out.
- Before any change: the root of each `NODE_EV_BLOCK`, with lantern_node_block_root of the fork of its slot. A status of that call is the step's.
- On `LANTERN_BUFFER_TOO_SMALL`, `short`: `NODE_SHORT_ACTIONS` for the room of `actions`, and for `LIBP2P_BUFFER_TOO_SMALL` of libp2p_step (its scratch is the step's own); `NODE_SHORT_NODE` for a part of the node, with `room` the byte offset in `NodeRoom` of its capacity (`blocks`, `checkpoints`, `pow_blocks`, `p2p_out`, `blobs`, `engine_bytes` or `api_streams`); `NODE_SHORT_SCRATCH` for `scratch`, and for `LANTERN_BUFFER_TOO_SMALL` of lantern_node_block_root.
- The prune, after libp2p's first round and before the node's events, when the store's finalized epoch is above `pruned_epoch`: lantern_store_prune with the step's scratch; on its success `pruned_epoch` takes that epoch, and with F the block of the finalized root:
  - F, imported with no post-state, gets it again first (the rebuild below), while its ancestors keep theirs.
  - Each imported ancestor of F, by `parent_root`, gets a `NODE_ACT_STATE_FREE` of any post-state and `state_id` 0; its bytes and sidecars stay, for the node serves the chain.
  - An imported block with a post-state, or above F's slot, and no node in the store is of another branch: a `NODE_ACT_STATE_FREE` of any post-state and a `NODE_ACT_BYTES_FREE`, and its entry is free.
  - A `NODE_BLOCK_INVALID`, `NODE_BLOCK_WAITING`, `NODE_BLOCK_BLOBS` or `NODE_BLOCK_PAYLOAD` block at or below F's slot: a `NODE_ACT_BYTES_FREE` of any bytes, and its entry is free.
  - A `NODE_BLOB_INVALID` entry is free; a `NODE_BLOB_VALID` entry at or below F's slot whose block is neither imported nor in `NODE_BLOCK_BACKFILL`: a `NODE_ACT_BYTES_FREE`, and its entry is free.
  - A `NodeCheckpoint` below the finalized epoch: a `NODE_ACT_STATE_FREE` of its state, except `anchor_state_id`, which goes with the anchor block; its entry is free.
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
- A waiting block whose parent is imported: a `NODE_ACT_STATE_COPY` of the parent's post-state and a `NODE_WORK_IMPORT_BLOCK`; the block is `NODE_BLOCK_IMPORTING`. A parent with no post-state above F's slot gets it again first; one at or below F's slot is an ancestor of F, as below. When the fork of the block's slot is later than that of the parent's slot, the copy first crosses each fork boundary between them, and the import gets the last state.
- The crossing of a fork boundary by a state copy `a` of a fork to the next fork: a `NODE_WORK_SLOTS` of `a` to the next fork's first slot, when `a` is before it; a `NODE_ACT_STATE_COPY` of the copied state as `b`, a buffer for the upgrade; a `NODE_WORK_UPGRADE` of `a` into `b` with the next fork as `arg`; a `NODE_ACT_STATE_FREE` of `a`. Then `b` is the copy. The shell does the actions in order, so a work reads what the works before it wrote. A waiting block whose parent is invalid becomes `NODE_BLOCK_INVALID`.
- With `NODE_FLAG_ENGINE`, a waiting block of bellatrix or later whose parent is imported takes `NODE_BLOCK_PAYLOAD` instead, with `retry` 0: its import waits for the execution engine's answer.
- `NODE_EV_ATTESTATION`: a `NODE_ACT_BYTES_PUT` of the bytes and a `NODE_WORK_ATTESTATION` with the target checkpoint state, or 0 when the node has none.
- `NODE_EV_ATTESTER_SLASHING`: a `NODE_ACT_BYTES_PUT` of the bytes and a `NODE_WORK_ATTESTER_SLASHING` with the post-state of the justified root.
- The votes of an imported block (phase0 `fork-choice.md`: on_attestation and on_attester_slashing run whenever an attestation or an attester slashing is received, those of a block too): for each attestation of its body, by index, a `NODE_WORK_BLOCK_ATTESTATION` with the block's bytes and the index as `arg`; then for each attester slashing of its body, by index, a `NODE_WORK_BLOCK_SLASHING` with the block's bytes, the index as `arg` and the post-state of the justified root. The counts are those of the import's event: attestations at `NodeEvent_index`, attester slashings at `NodeEvent_root`. Each of these works adds 1 to `event_votes`, and its `NODE_EV_WORK_DONE` takes 1 off.
- `NODE_EV_WORK_DONE` of `NODE_WORK_BLOCK_ATTESTATION` with `LANTERN_NEED_TARGET_STATE`: the target checkpoint state, then the same work again with it. The block's bytes stay.
- `NODE_EV_POW_BLOCK`: adds the `PowBlock` to the node.
- `NODE_EV_WORK_DONE` of `NODE_WORK_IMPORT_BLOCK`: valid, the block is `NODE_BLOCK_IMPORTED`, a block event goes (the events, below), its votes go to fork choice, and its waiting children are imported; `LANTERN_NEED_JUSTIFIED_STATE`, a `NODE_WORK_JUSTIFIED_STATE` and the same import again; else `NODE_BLOCK_INVALID` and a `NODE_ACT_STATE_FREE` of its state.
- `NODE_EV_WORK_DONE` of `NODE_WORK_ATTESTATION` with `LANTERN_NEED_TARGET_STATE`: the target checkpoint state, then the same attestation again with it.
- A checkpoint state the node does not have: a `NODE_ACT_STATE_COPY` of the post-state of the checkpoint's root, a `NodeCheckpoint`, and a `NODE_WORK_TARGET_STATE`. A root's block with no post-state above F's slot gets it again first. When the fork of the checkpoint epoch's first slot is later than that of the root's slot, the copy first crosses each fork boundary between them, and the `NodeCheckpoint` and the work get the last state.
- An attestation or slashing done: a `NODE_ACT_BYTES_FREE` of its bytes.
- The head: get_head of the fork of the store's slot into `head_root`, or a `NODE_WORK_JUSTIFIED_STATE` when it returns `LANTERN_NEED_JUSTIFIED_STATE`.
- The events (beacon-api.md, eventstream), each to the `NodeApi` entries of eventstream whose topics have its bit (`API_TOPIC_*`):
  - block: at the import of a block, its text: the block's slot and root, `execution_optimistic` from its `payload_status`.
  - head and finalized_checkpoint at a quiet point: after the head, once the head's post-state is back (the rule of the post-states the node lets go, above), with `event_votes` 0, so that the votes of each block the node imports are in fork choice first.
  - head: at a quiet point, when `head_root` is not `event_head`: `event_head` and `event_slot` take the head's root and slot; with an entry of the topic, a `NODE_WORK_API_EVENT` with the head's post-state as `state_a` and as `arg` `API_TOPIC_HEAD` + 2^8 times the values: 1 `epoch_transition` (the epoch of the head's slot above that of the old `event_slot`), 2 `execution_optimistic`.
  - finalized_checkpoint: then, when the store's finalized epoch is above `event_epoch`: `event_epoch` takes it; with an entry of the topic, a `NODE_WORK_API_EVENT` with the bytes of the finalized root's block as `data` (its `NODE_DB_REF` when the `Db` holds them), else its post-state as `state_a`, and as `arg` `API_TOPIC_FINALIZED_CHECKPOINT` + 2^8 times the values (2 `execution_optimistic`) + 2^16 times the epoch. A block with neither gives no event.
  - `NODE_EV_WORK_DONE` of `NODE_WORK_API_EVENT`: `LANTERN_VALID`, the text at `NodeEvent_chunk` goes to the entries of the topic of `arg` % 2^8. Another result: no event.
  - To an entry: a `NODE_ACT_API_SEND` of the text with `last` 0, in one chunk of RFC 9112 section 7.1 with `API_STREAM_CHUNKED`; its `sent` grows by the bytes sent. When `sent` would pass `NODE_API_CHUNK`, the stream falls behind: a `NODE_ACT_API_CLOSE` of the connection in its place, and the stream ends.
- libp2p first, before the node's events: libp2p_step with the queued events, then the `NODE_EV_P2P` events, after them in the queue. The first libp2p_step takes at most half the action room left, when that half is enough, so the notices have room. When it accepts k of n P2P events, with k < n, the P2P events it did not take leave the queue, the step handles the node's events before the next P2P event, and gives that count as `accepted`. A status of libp2p_step leaves the queue as it was.
- `PEER_CONNECTED`: a `NodePeer`, or a `DISCONNECT` when the peers part is full. `PEER_DISCONNECTED`: the peer and its streams go.
- `PEER_CONNECTED` and `DIAL_FAILED` of a tag with `NODE_DIAL_TAG`: `dialing` takes 1 less. A `PEER_CONNECTED` of `LIBP2P_OUTBOUND` that gets a `NodePeer`: a Status request (v2 from fulu, v1 before) with the node's Status, as a request of the node.
- `NODE_EV_ENR`, with `p2p`: the record of discv5_enr_decode, with an `ip`, a `tcp` pair of 1 or 2 bytes, an `eth2` pair whose first 4 bytes are compute_fork_digest of the store's epoch, and a `secp256k1` key whose peer ID (the identity multihash of the protobuf secp256k1 public key) no `NodePeer` has, gets a `DIAL` over TCP to that address with that peer ID and a tag with `NODE_DIAL_TAG`, when `dialing` + the peers are below the capacity of the peers part and `p2p_out` has room; `dialing` takes 1 more. Another record changes nothing.
- With `NODE_FLAG_DISCV5`, at each subscription to a new `fork_digest`: a `NODE_ACT_DISCV5` of `SET_ENTRY` events: `eth2`, lantern_compute_enr_fork_id at the store's epoch; `attnets`, the bits of `attnets` (bit i of byte i / 8 for subnet i); from altair `syncnets`, 1 zero byte; from fulu `cgc`, `CUSTODY_REQUIREMENT` in big-endian bytes with no leading zero, and `nfd`, lantern_compute_next_fork_digest.
- With `NODE_FLAG_DISCV5`, after the head: when `dialing` + the peers are below the capacity of the peers part, and `time_ms` is at least `lookup_ms` + `NODE_LOOKUP_MS` or `lookup_ms` is 0, a `NODE_ACT_DISCV5` of a `LOOKUP` event whose target is the tick's 32 entropy bytes; `lookup_ms` takes `time_ms`.
- `STREAM_INBOUND`: a `NodeStream` of the protocol's method and version, or a `STREAM_RESET` when the streams part is full. `STREAM_DATA`: the bytes join the stream's request, or a `STREAM_RESET` when they pass its room. `STREAM_EOF`: the request is complete. `STREAM_RESET`: the stream goes.
- A Status the node reads, of a request or a response, is kept in the `NodePeer`; then the peer gets a `DISCONNECT` and loses `NODE_PEER_STATUS` when its `fork_digest` is not compute_fork_digest of the store's epoch, `next_digest` or `old_digest`, or when its finalized epoch is not `GENESIS_EPOCH`, is at most the store's finalized epoch, and its finalized root is not the store's finalized root (the same epoch) or the root of the `Db`'s last block at or before the epoch's first slot (an earlier epoch, when the `Db` holds one).
- A request is read when its bytes are complete: Status is kept in the `NodePeer` and answered with the node's Status of the same version; Ping is answered with `metadata_seq`; MetaData, on the stream's opening, with the node's MetaData of the same version; Goodbye gets a `STREAM_CLOSE`. A request that is not valid gets result 1, InvalidRequest; a method of no answer below gets result 3, ResourceUnavailable.
- BeaconBlocksByRange: a `start_slot` before the lower of `earliest_slot` and `backfill_slot` gets ResourceUnavailable. Otherwise, in slot order, the blocks of the `Db` with a slot in `start_slot` to `start_slot` + `count` below `db_next_slot`, as `NODE_DB_REF`s, then the blocks of the chain of `head_root`, by `parent_root`, with a slot from `db_next_slot` in that range; `count` is at most `MAX_REQUEST_BLOCKS_DENEB` from deneb on, else `MAX_REQUEST_BLOCKS`, and at most the BufferIds a stream's request room holds.
- BeaconBlocksByRoot: the imported blocks of the roots the node knows, or else the `Db`'s blocks of those roots (lantern_db_find_root), in the request's order; the request has at most that many roots.
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
- The node's Status: compute_fork_digest of the store's epoch, the store's finalized checkpoint (with a zero root when its epoch is `GENESIS_EPOCH`: p2p-interface.md, "defaults to `Root(b'\x00' * 32)` for the genesis finalized checkpoint"), `head_root` and its slot, and `earliest_slot`. Its MetaData: `metadata_seq`, the subnets of `attnets`, no sync subnets, and `CUSTODY_REQUIREMENT` custody groups.
- After the head, with `p2p`, one change a step, when `p2p_out` has 8192 bytes free (altair `p2p-interface.md`, Transitioning the gossip: a node SHOULD subscribe to the post-fork topics in advance of the fork, and SHOULD unsubscribe from the pre-fork topics two epochs after it):
  - When compute_fork_digest of the store's epoch is not `fork_digest`: it becomes `fork_digest`, and `attnets` the subnets of the store's epoch (below), then the record entries below; a `SUBSCRIBE` of each topic of the fork of that epoch at that digest, unless it is `next_digest`, whose topics are there; `next_digest` becomes 0. A `fork_digest` before it becomes `old_digest`, with the fork of the epoch before as `old_fork` and the store's epoch + `NODE_SUBSCRIBE_AHEAD` (2) as `old_epoch`.
  - Else, when compute_fork_digest of the store's epoch + `NODE_SUBSCRIBE_AHEAD` is neither `fork_digest` nor `next_digest`: it becomes `next_digest`, with a `SUBSCRIBE` of each topic of the fork of that epoch at that digest.
  - Else, when the subnets of the store's epoch are not `attnets`: an `UNSUBSCRIBE` of beacon_attestation of each subnet of `attnets` not among them and a `SUBSCRIBE` of each new one, at `fork_digest` and at `next_digest` when it is not 0; `attnets` takes them, with the record entries below.
  - The subnets of an epoch: those of lantern_compute_subscribed_subnet(the node ID, the epoch, index) for each index below `SUBNETS_PER_NODE` (phase0 `p2p-interface.md`, Attestation subnet subscription: a beacon node should stay subscribed to `SUBNETS_PER_NODE` subnets, chosen from its node ID, for `EPOCHS_PER_SUBNET_SUBSCRIPTION` epochs, and set their bits in its record's `attnets`). Each change of `attnets` adds 1 to `metadata_seq` (MetaData: `seq_number` grows when `attnets` changes).
  - Else, from `old_epoch` on, an `UNSUBSCRIBE` of each topic of `old_fork` at `old_digest`, which becomes 0.
  - The topics of a fork: beacon_block, beacon_aggregate_and_proof, beacon_attestation of each subnet of `attnets`, voluntary_exit, proposer_slashing and attester_slashing; from altair sync_committee_contribution_and_proof; from capella bls_to_execution_change; in deneb and electra blob_sidecar of each subnet; from fulu data_column_sidecar of compute_subnet_for_data_column_sidecar of each column of `columns`, once for each subnet.
- `MESSAGE`: a `MESSAGE_ID` of compute_message_id of the fork of the store's slot, then a `NodeMessage` when the messages part has room. Its data uncompressed with Snappy goes in a `NODE_ACT_BYTES_PUT`, and for a block, a blob sidecar or a column sidecar the slot and parent root of its block header go in the entry; for a beacon_aggregate_and_proof the slot of its aggregate's data, by the offsets of its bytes (the message's at byte 0, the aggregate's at byte 8 of the message, the slot at byte 4 of the aggregate), or 2^64 - 1 when the bytes do not hold one. Data that is no Snappy block of at most `MAX_PAYLOAD_SIZE` bytes makes the entry `NODE_MESSAGE_CORRUPT`; data that does not fit in `scratch` or the actions makes it `NODE_MESSAGE_NO_ROOM`. A topic whose ForkDigest is not `fork_digest` makes it `NODE_MESSAGE_OTHER_DIGEST`, its data unread, for an IGNORE (altair `p2p-interface.md`, Transitioning the gossip: after a fork, peers on the pre-fork topics MUST NOT be scored down; before it, messages on the post-fork topics can be IGNORED); a topic of no name counts as of `fork_digest`.
- `MESSAGE_STATUS` of `LIBP2P_MSG_NEW` for an entry with bytes: a `NODE_WORK_GOSSIP` with the head's post-state, the post-state of the justified root, and for a block, a blob sidecar or a column sidecar whose parent is imported at an earlier slot of the same fork a `NODE_ACT_STATE_COPY` of its post-state, which a parent above F's slot with none gets again first; the entry takes `NODE_MESSAGE_VALIDATING`. With no bytes, or no room in the actions, a `VALIDATION` of `LIBP2P_IGNORE`, or `LIBP2P_REJECT` for `NODE_MESSAGE_CORRUPT`. Any other status: the bytes and the entry go.
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
- With `NODE_FLAG_ENGINE`, after the head: with no call in flight (`engine_method` 0) and the store's slot at least `engine_wait`, the first block in `NODE_BLOCK_PAYLOAD` whose `retry` is at most the store's slot gets a `NODE_WORK_NEW_PAYLOAD` with the id `engine_id`, takes `NODE_BLOCK_EXECUTING`, and is the call in flight; with none, and `NODE_FLAG_FCU`, a `NODE_WORK_FORKCHOICE` when the fork of the store's slot is bellatrix or later. Each call takes the next id.
- A `head_root` that changes with `NODE_FLAG_ENGINE` sets `NODE_FLAG_FCU`; a `NODE_WORK_FORKCHOICE` clears it.
- `NODE_EV_WORK_DONE` of `NODE_WORK_NEW_PAYLOAD` or `NODE_WORK_FORKCHOICE`: `LANTERN_VALID`, its request goes out in a `NODE_ACT_ENGINE`. Another result ends the call; for engine_newPayload, `LANTERN_NO_PAYLOAD` imports the block with `PAYLOAD_STATUS_VALID`, and any other makes it `NODE_BLOCK_INVALID` with a `NODE_ACT_BYTES_FREE` of its bytes.
- `NODE_EV_ENGINE` with arg 0: its bytes join `engine_in`. When they hold a whole response of lantern_http_parse_response, the response leaves `engine_in` and lantern_engine_parse_response of the method in flight reads its body. A status other than 200, a body that is no answer of the method, a JSON-RPC error or another id is a failed call. arg 1: the call in flight failed, and `engine_in` empties.
- A failed engine_newPayload: the block takes `NODE_BLOCK_PAYLOAD` with `retry` the store's slot + 1 (optimistic-sync.md: no optimistic import, the block MAY be queued). A failed call makes `engine_wait` the store's slot + 1; a failed engine_forkchoiceUpdated sets `NODE_FLAG_FCU` again. The call ends.
- engine_newPayload answered: `VALID`, the block is imported with `PAYLOAD_STATUS_VALID`. `SYNCING` or `ACCEPTED`, the block is imported with `PAYLOAD_STATUS_NOT_VALIDATED` when it is an optimistic candidate: its parent's `BlockNode.block_hash` is not zero, or its slot + `SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY` is at most the store's slot; else it takes `NODE_BLOCK_PAYLOAD` with `retry` the store's slot + 1. `INVALID` or `INVALID_BLOCK_HASH`, the block is `NODE_BLOCK_INVALID`, its bytes go, and `latestValidHash` applies from its parent. The call ends.
- engine_forkchoiceUpdated answered: `VALID`, lantern_store_payload_status of the head's node with `PAYLOAD_STATUS_VALID`; `INVALID` or `INVALID_BLOCK_HASH`, `latestValidHash` applies from the head, the head included. The call ends.
- `latestValidHash` applies from a block of the store: up the chain from it, by `parent_root`, each block whose `block_hash` is not `latestValidHash` gets lantern_store_payload_status with `PAYLOAD_STATUS_INVALIDATED`, until the block whose `block_hash` is `latestValidHash`. A zero hash stops at the first block whose `block_hash` is zero. With null, or a hash no block of the chain has, only the block in question (a block of the store) gets it.
- `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`: a `VALIDATION` of `LIBP2P_ACCEPT` for `LANTERN_VALID`, `LIBP2P_REJECT` for `LANTERN_GOSSIP_REJECT`, else `LIBP2P_IGNORE`; a `NODE_ACT_STATE_FREE` of the proposer state. A valid beacon_block of a root the node does not know keeps its bytes as a `NodeBlock` with the blob count at `NodeEvent_index`, which waits for its blobs. A valid blob_sidecar keeps its bytes as a `NodeBlob` in `NODE_BLOB_VALID` of the root at `NodeEvent_root`, the index at `NodeEvent_index` and the message's slot, when the node holds no `NODE_BLOB_VALID` entry of that root and index. A valid data_column_sidecar of a column of `columns` keeps its bytes as a `NodeBlob` in `NODE_BLOB_VALID` of the root at `NodeEvent_root`, the index at `NodeEvent_index` and the message's slot, when the node holds no `NODE_BLOB_VALID` entry of that root and index. A valid attester_slashing with a justified state keeps its bytes for a `NODE_WORK_ATTESTER_SLASHING` with that state. A valid voluntary_exit, proposer_slashing, attester_slashing or bls_to_execution_change keeps its bytes as a `NodePool` entry too (the pool, below), when the pool has an entry free. A valid beacon_aggregate_and_proof keeps its bytes and its entry, in `NODE_MESSAGE_VOTE`, for fork choice from the slot after its aggregate's (phase0 `fork-choice.md`: an attestation affects the fork choice of later slots only), when the messages part has more than half its capacity free after it. Else the bytes go. The entry goes, but an entry kept for its vote.

- `NODE_EV_API` (beacon-api.md, Common rules): the answer to the request, in one `NODE_ACT_API_SEND` of its connection with `last` 1, then a `NODE_ACT_API_CLOSE` of it when the connection closes after the answer.
  - An `HttpRequest` with a `status`: the error of that status.
  - Else lantern_api_route of the request, its `ApiRoute` in `scratch`. `LANTERN_INVALID_ROUTE`: the error of its `status`.
  - getHealth, getNetworkIdentity, getNodeVersion, getSyncingStatus, getPeerCount, getGenesis, getForkSchedule and getDepositContract: the answer of the node, the store and the config.
  - getSpec: a `NODE_WORK_API_ENCODE` with no state and no `data`, the connection as `target`, and as `arg` the operation + 2^8 times the answer flags.
  - The block of a `block_id` and the state of a `state_id`, as beacon-api.md gives them: the walk of the chain by `parent_root` from the head's `NodeBlock`; below its lowest block, the `Db`'s `DbSlot` of a slot or lantern_db_find_root of a root; the bytes of a `Db` block a `NODE_DB_REF` of its record.
  - A state at a slot past its post-state's, or past its `NodeCheckpoint`'s: a `NODE_ACT_STATE_COPY` of it, the copy across the fork boundaries to the slot (the crossing), then a `NODE_WORK_SLOTS` of the copy to the slot when it is below it; after the copy's last use, a `NODE_ACT_STATE_FREE` of it.
  - getBlockRoot: the answer at once.
  - getBlockHeader, getStateRoot, getStateFork and getStateFinalityCheckpoints: a `NODE_WORK_API_ENCODE`, the connection as `target`, and as `arg` the operation + 2^8 times the answer flags (`API_ANSWER_CLOSE` 1, `API_ANSWER_HTTP10` 2) + 2^16 times the values (`API_VALUE_CANONICAL` 1, `API_VALUE_FINALIZED` 2, `API_VALUE_OPTIMISTIC` 4) + 2^24 times: for getBlockHeader the block's `NodeBlock` index + 1, or 0 for a block of the `Db`; for the others the state's slot. getBlockHeader: the block's bytes as `data`, or 0; with none, its post-state as `state_a`. The others: the state as `state_a`.
  - getBlockV2 and getStateV2: a stream (below).
  - getStateValidator: a `NODE_ACT_BYTES_PUT` of the route's `validator` (a `ValidatorRef`) to a new id; a `NODE_WORK_API_ENCODE` as above with the state as `state_a` and that id as `data`; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id.
  - getStateValidators, postStateValidators, getStateValidatorBalances, postStateValidatorBalances and postStateValidatorIdentities: a stream (below) of the state.
  - getEpochCommittees: the error 400 for an epoch or a slot that beacon-api.md refuses, from the state's slot; else a stream (below) of the state.
  - eventstream: the first free `NodeApi` entry, else the next, with the connection, the operation, `API_STREAM_STARTED`, `API_STREAM_CHUNKED` over HTTP/1.1 (and `API_STREAM_CLOSE` with `Connection: close`), `API_STREAM_CLOSE` and `API_STREAM_HTTP10` over HTTP/1.0, the route's `topics` at byte 0 of `cursor`; a `NODE_ACT_API_SEND` of the head (beacon-api.md, eventstream) with `last` 0, and `sent` its bytes. The entry stays to the stream's end.
  - getPoolVoluntaryExits, getPoolBLSToExecutionChanges, getPoolProposerSlashings and getPoolAttesterSlashingsV2: a stream (below) of the pool.
  - submitPoolVoluntaryExit, submitPoolProposerSlashings, submitPoolAttesterSlashingsV2 and submitPoolBLSToExecutionChange: a `NODE_ACT_BYTES_PUT` of the request's body to a new id, and a `NODE_WORK_API_SUBMIT` with the head's post-state as `state_a`, that id as `data`, the connection as `target`, and as `arg` the operation + 2^8 times the answer flags + 2^16 times the fork of the store's slot. submitPoolAttesterSlashingsV2 whose `consensus_version` names a fork of another `AttesterSlashing` type than the fork of the store's slot (electra's from electra on, phase0's before): the error 400, and no work. A body of no bytes: the error 400, and no work. A head with no post-state: the error 500, and no work.
  - getProposerDuties: 503 with `NODE_FLAG_SYNCING`; 400 for an epoch above the epoch of the store's slot + 1; then the state of the epoch's first slot, as for a `state_id` of that slot, or past the store's slot the head's post-state brought to it; a `NODE_WORK_API_ENCODE` of it, `arg` as for the state operations with that slot.
  - produceAttestationData: 503 with `NODE_FLAG_SYNCING`; 400 for a `slot` past the store's slot; then the state of `slot`, as for a `state_id` of that slot (none: 400); 503 when it is optimistic; a `NODE_ACT_BYTES_PUT` of `committee_index` (8 bytes) to a new id, and a `NODE_WORK_API_ENCODE` of the state as `state_a` and that id as `data`, `arg` as for the state operations with that slot, and `API_ANSWER_SSZ` (4) among the answer flags for an SSZ `response`; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id.
  - getAttesterDuties: 503 with `NODE_FLAG_SYNCING`; 400 for an epoch above the epoch of the store's slot + 1, for no `ValidatorRef` item or one of a public key; then the state of the epoch's first slot, as for getProposerDuties (none: 400); a `NODE_ACT_BYTES_PUT` of the route's `ValidatorRef` items to a new id, and a `NODE_WORK_API_ENCODE` of the state as `state_a` and that id as `data`, `arg` as for the state operations with that slot; after its `NODE_EV_WORK_DONE`, a `NODE_ACT_BYTES_FREE` of the id.
  - A `state_id` of a root: a `NodeApi` entry with `API_STREAM_LOOKUP`, the connection, the operation, the answer flags and `API_STREAM_SSZ` for `response` `API_TYPE_SSZ`, the root in the first 32 bytes of its `cursor`, the route's `statuses` at byte 32 of it, its `validator` at byte 40, and its `epoch`, `slot`, `index` and `present` at bytes 104, 112, 120 and 128; for the six validator operations the ids as for their stream (below), as `data` with `API_STREAM_OWN`; and a `NODE_WORK_API_LOOKUP` with the head's post-state as `state_a`, the connection as `target` and the entry's index as `arg`.
- `NODE_EV_WORK_DONE` of `NODE_WORK_API_LOOKUP`, of the `NodeApi` entry at index `arg`: the entry ends. Without `API_STREAM_GONE`: with a slot at `NodeEvent_index`, the answer of the entry's operation for the `state_id` of that slot, as for a `NODE_EV_API` with its answer flags, `statuses`, `validator`, `epoch`, `slot`, `index`, `present` and ids, whose `data` the answer takes; with 2^64 - 1 there, the error 404 (and the ids' `NODE_ACT_BYTES_FREE`).
  - Every other operation: 501.
- A stream: the first free `NodeApi` entry, else the next, with the connection, the operation, the answer flags (`API_STREAM_CLOSE`, `API_STREAM_HTTP10`), `API_STREAM_SSZ` for `response` `API_TYPE_SSZ`, `API_STREAM_OPTIMISTIC` and `API_STREAM_FINALIZED` as beacon-api.md gives `execution_optimistic` and `finalized`, the slot of the block or the state and its fork, and `sent` and `cursor` zero; then a `NODE_WORK_API_CHUNK` of it, and `API_STREAM_BUSY`.
  - getBlockV2: `data` the block's bytes; with none, the error 404 and no stream.
  - getStateV2: a `NODE_ACT_STATE_BYTES` of the state (the copy at its slot, then the copy's `NODE_ACT_STATE_FREE`) to a new id, which is `data`, with `API_STREAM_OWN`.
  - The five validator streams: `state` the state's id, with `API_STREAM_OWN_STATE` when it is the lookup's copy; the route's `statuses` at byte 8 of `cursor`; with `id` items, `data` a `NODE_ACT_BYTES_PUT` of the route's list of `ValidatorRef` items to a new id, with `API_STREAM_OWN`; else `data` 0.
  - The pool streams: `fork` the fork of the store's slot; `slot` the index of the pool's first entry of the operation's topic (for getPoolAttesterSlashingsV2, of an `AttesterSlashing` type that is that fork's), `data` its bytes and `sent` its fork; with none, `data` 0.
  - getEpochCommittees: `state` as for the validator streams, `data` 0; in `cursor`, the first slot (`slot`, else the epoch's first) at byte 0, the epoch at 24, `slot` at 40 and `index` at 48 (2^64 - 1 for one not given).
- `NODE_EV_WORK_DONE` of `NODE_WORK_API_CHUNK`, of the `NodeApi` entry at index `arg`: `API_STREAM_BUSY` clears.
  - A pool stream whose event has `API_STREAM_ITEM_DONE`, with `LANTERN_VALID`: the next pool entry after `slot` that the stream answers (as at its start) becomes `slot`, its bytes `data`, its fork `sent`, and `cursor` zero; with none, `data` 0. Bytes of the entry before that the stream owns (`API_STREAM_OWN`) get a `NODE_ACT_BYTES_FREE`, and `API_STREAM_OWN` clears.
  - With `API_STREAM_GONE`: the stream ends.
  - `LANTERN_VALID`: the entry takes `sent`, `flags` and `cursor` of the event; a `NODE_ACT_API_SEND` of the chunk at `NodeEvent_api_bytes` to the connection, with `last` 1 when `API_STREAM_DONE` is set, else 0. With `API_STREAM_DONE`: a `NODE_ACT_API_CLOSE` after it when `API_STREAM_CLOSE` is set, and the stream ends.
  - Another result: before `API_STREAM_STARTED`, the error 500 to the connection; after it, a `NODE_ACT_API_CLOSE` of the connection (the answer stops short). The stream ends.
- `NODE_EV_WORK_DONE` of `NODE_WORK_API_SUBMIT`: a `NODE_ACT_BYTES_FREE` of the body's id (`data`). With `LANTERN_INVALID_ENCODING`, or another result than `LANTERN_VALID`: the error 400 to the connection `target`. Else, for each operation of the event (the run, below), in order:
  - `LANTERN_VALID`: a `NODE_ACT_BYTES_PUT` of its SSZ bytes to a new id, kept as a `NodePool` entry of its topic and of the fork of `arg` / 2^16 when the pool has an entry free; with `NODE_FLAG_SUBSCRIBED`, the publish of the bytes on its topic; an attester slashing also gets a `NODE_WORK_ATTESTER_SLASHING` of that id with the post-state of the justified root, as one from gossip does. An id no entry keeps and no work reads gets its `NODE_ACT_BYTES_FREE`.
  - `LANTERN_GOSSIP_REJECT`: a failure, with the operation's place in the body.
  - Another result: nothing.
  - Then the answer (beacon-api.md, the pool POSTs) to the connection, with the answer flags of `arg`: 200, or 400 with the failures.
- The pool: the `NodePool` entries, each a voluntary_exit, proposer_slashing, attester_slashing or bls_to_execution_change that passed its gossip validation; a new entry takes the first free entry. A `NODE_ACT_BYTES_FREE` of an id a pool entry has as `data` does not go: the entry keeps the bytes until it goes.
  - At the quiet point of a head event (above), when `head_root` changes: each entry in `NODE_POOL_KEPT` gets a `NODE_WORK_POOL_CHECK` with the head's post-state as `state_a`, its bytes as `data`, its index as `target` and its topic as `arg`, and takes `NODE_POOL_CHECKING`; with no head post-state, none.
  - `NODE_EV_WORK_DONE` of `NODE_WORK_POOL_CHECK`, of the entry at index `target` in `NODE_POOL_CHECKING`: `LANTERN_VALID`, it takes `NODE_POOL_KEPT`; else a `NODE_ACT_BYTES_FREE` of its bytes, and it is free (topic 0).
- The publish of SSZ bytes on a topic, with `NODE_FLAG_SUBSCRIBED` (phase0 `p2p-interface.md`, Topics and messages: the data of a message is the SSZ bytes compressed with Snappy's block format): a `LIBP2P_EVENT_PUBLISH` at the end of `p2p_out`, the topic lantern_gossip_topic of `fork_digest` and the topic's name, the data snappy_compress of the bytes, and the ID compute_message_id of the fork of the store's slot of that topic and the bytes; none when `p2p_out` has no room for it. libp2p's `LIBP2P_ACTION_PUBLISHED` that answers it changes nothing.
- `NODE_EV_API_SENT` of the connection of a `NodeApi` entry of eventstream: its `sent` is 0. Of another entry without `API_STREAM_BUSY`: a `NODE_WORK_API_CHUNK` of it, and `API_STREAM_BUSY`. Another `NODE_EV_API_SENT` is skipped.
- `NODE_EV_API_CLOSED` of the connection of a `NodeApi` entry: with `API_STREAM_BUSY`, the entry takes `API_STREAM_GONE`; else the stream ends. Another is skipped.
- The end of a stream: with `API_STREAM_OWN`, a `NODE_ACT_BYTES_FREE` of its `data`; with `API_STREAM_OWN_STATE`, a `NODE_ACT_STATE_FREE` of its `state`; its entry is free (connection 0), and the api part's count drops past the free entries at its end.
- A `NODE_ACT_BYTES_FREE` of an id that a `NodeApi` entry has as `data` without `API_STREAM_OWN` does not go: the entry takes `API_STREAM_OWN`, and frees the bytes at its end. So with a `NODE_ACT_STATE_FREE` of an id that an entry has as `state` without `API_STREAM_OWN_STATE`: the entry takes `API_STREAM_OWN_STATE`. The node changes no state it keeps, so the entry reads the same state to its end.
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
- `LANTERN_INVALID_EVENT`: the work is of no kind, or names no `NodeCheckpoint`; a `NODE_WORK_API_ENCODE` of another operation, of a block index past the blocks part, getBlockHeader with neither `data` nor `state_a` or with neither `data` nor a block index, another but getSpec with no `state_a`; a `NODE_WORK_API_CHUNK` of an index past the api part, of a free entry or one of another operation, with no `data` for getBlockV2 and getStateV2, or with no `state_a` for the validator streams; a `NODE_WORK_API_LOOKUP` with no `state_a`; a `NODE_WORK_API_EVENT` of another topic, of head with no `state_a`, or of finalized_checkpoint with neither `data` nor `state_a`; a `NODE_WORK_API_SUBMIT` of another operation, or with no `state_a` or `data`; a `NODE_WORK_POOL_CHECK` of another topic, or with no `state_a` or `data`.

### Caller must

- On `LANTERN_BUFFER_TOO_SMALL`, grow the store with lantern_store_copy, or `state_a` with lantern_beacon_state_copy, or `scratch`, or for a SERVE, NEW_PAYLOAD, FORKCHOICE, API_ENCODE or API_CHUNK work `event`, then call again.

### Function does

- `NODE_WORK_IMPORT_BLOCK`: lantern_node_import of the fork of the block's slot, with `BlockOptions` of `PAYLOAD_STATUS_VALID` (`PAYLOAD_STATUS_NOT_VALIDATED` with `NODE_FLAG_OPTIMISTIC`; the block's `payload_status` with `NODE_FLAG_ENGINE`), the block's `data_available`, and `slots_done` 1 when `state_a` is at the block's slot and that slot is the first of its fork. `LANTERN_NEED_JUSTIFIED_STATE` becomes the result. A `state_a` whose slot's fork is not that of the block's slot gives the result `LANTERN_INVALID_SLOT`.
- `NODE_WORK_SLOTS`: lantern_process_slots of the fork of the slot of `state_a`, of `state_a` to the slot `arg`.
- `NODE_WORK_REPLAY`: lantern_node_replay of the fork of the block's slot, of the block in `data` on `state_a`; a `state_a` whose slot's fork is not the block's gives `LANTERN_INVALID_SLOT`.
- `NODE_WORK_UPGRADE`: lantern_node_upgrade of the fork `arg`, of `state_a` into `state_b`, with a `StateRoom` of 1024 validators, 2048 eth1_data_votes, 64 historical_summaries, 1024 pending_deposits, 64 pending_partial_withdrawals, 64 pending_consolidations, 4 historical_roots and 4096 pending_attestations, as the binary's anchor has, and the node's config. A fork `arg` outside altair to fulu, or a `state_a` not at that fork's first slot, gives the result `LANTERN_INVALID_SLOT`.
- `NODE_WORK_JUSTIFIED_STATE`: lantern_store_justified_checkpoint_state with `state_a`.
- `NODE_WORK_TARGET_STATE`: lantern_store_target_checkpoint_state of `state_a` to the `NodeCheckpoint` at index `target`.
- `NODE_WORK_ATTESTATION`: lantern_node_attestation of the fork of the attestation's slot; `is_from_block` is the work's `arg`.
- `NODE_WORK_GOSSIP_VOTE`: the aggregate of the `SignedAggregateAndProof` in `data` (the message's offset at byte 0, the aggregate's at byte 8 of the message, to the end of the bytes), as a ByteList at the end of `scratch`, then as `NODE_WORK_ATTESTATION` with `is_from_block` 0. Bytes that do not hold it give `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_BLOCK_ATTESTATION` and `NODE_WORK_BLOCK_SLASHING`: the attestation or attester slashing at index `arg` of the body of the `SignedBeaconBlock` in `data`, its SSZ bytes as a ByteList at the end of `scratch`, then as `NODE_WORK_ATTESTATION` with `is_from_block` 1, or as `NODE_WORK_ATTESTER_SLASHING`. The body's attester_slashings and attestations are its fields 4 and 5 in every fork: offsets at bytes 204 and 208 of the body, after randao_reveal, eth1_data and graffiti. An index past the list, or bytes that do not hold it, give `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_IMPORT_BLOCK` of a valid block: the counts of its body's attestations at `NodeEvent_index` and attester slashings at `NodeEvent_root`.
- `NODE_WORK_ATTESTER_SLASHING`: lantern_node_attester_slashing of the fork of the store's slot; a state whose slot's fork is another gives the result `LANTERN_GOSSIP_IGNORE`.
- `NODE_WORK_SERVE`: the response chunk of the block, blob sidecar or column sidecar in `data`, with lantern_reqresp_write_chunk, as a ByteList at `NodeEvent_chunk` of the event; its context bytes are compute_fork_digest of the epoch of the block's slot (blocks of version 2, and BeaconBlocksByHead) or of the sidecar's block header slot (the blob and column methods), none for blocks of version 1. The event's `size` then covers the chunk.
- `NODE_WORK_SYNC_BLOCK`: lantern_node_block_root of the fork of the block's slot, its root at `NodeEvent_root` and its blob count at `NodeEvent_index`.
- `NODE_WORK_BACKFILL`: lantern_node_block_root of the fork of the block's slot, its root at `NodeEvent_root`; then, for `LANTERN_VALID`, lantern_node_backfill of the fork of the slot of `state_a`, of the block in `data` and that root.
- `NODE_WORK_NEW_PAYLOAD`: lantern_node_new_payload of the fork of the block's slot (bellatrix and later; before it `LANTERN_NO_PAYLOAD`), its request a ByteList at `NodeEvent_chunk`. The event's `size` then covers it.
- `NODE_WORK_FORKCHOICE`: engine_forkchoiceUpdated of the fork of the store's slot with the `block_hash` of the store's nodes of `head_root`, the justified checkpoint's root (safe) and the finalized checkpoint's root, in an HTTP POST to `engine_host` with a JWT of `jwt_secret` and the time `time_ms` / 1000, a ByteList at `NodeEvent_chunk`; `LANTERN_INVALID_UNKNOWN_BLOCK` when the store has no node of one of those roots, `LANTERN_NO_PAYLOAD` before bellatrix or when the head's `block_hash` is zero (no call).
- `NODE_WORK_BLOB`: with `arg` 0, a `BlobSidecar`: lantern_node_blob_sidecar of the fork of its slot when it is deneb or electra; with `arg` 1, a `DataColumnSidecar`: lantern_node_column_sidecar when the fork of its slot is fulu. Each with the node's config and `settings`, the root at `NodeEvent_root`; a slot of another fork gives the result `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_GOSSIP`: lantern_node_gossip of the fork of the store's slot, with a `NodeGossip` of `seen`, the store, `time_ms`, the topic and subnet of `arg`, `state_a` as head, `state_b` as proposer, `state_c` as justified, `settings` and the node's config, its `root` at `NodeEvent_root` and its `index` at `NodeEvent_index`. A proposer or justified state whose slot's fork is not that of the store's slot is passed as 0; a head state whose slot's fork is not that of the store's slot gives the result `LANTERN_GOSSIP_IGNORE`, as at a fork's first slots, before the node imports a block of the new fork.
- `NODE_WORK_API_ENCODE`: the response of the operation in `arg` (beacon-api.md, Common rules), with the answer flags and the values of `arg`, as a ByteList at `NodeEvent_chunk` of the event; the event's `size` then covers it.
  - getBlockHeader: the header of the block in `data` with lantern_node_block_header of the fork of its slot; with no `data`, the `latest_block_header` of `state_a`, its `state_root` lantern_state_root of the fork of the state's slot (with the `StateCache` of the node's config) when it is zero, and a zero signature. The root: that of the `NodeBlock` at index `arg` / 2^24 - 1, else lantern_node_block_root of `data`. Bytes that do not hold a block give the result `LANTERN_INVALID_ENCODING`.
  - getStateRoot: lantern_state_root of the fork of the state's slot, with the `StateCache` of the node's config. getStateFork: the state's `fork`. getStateFinalityCheckpoints: lantern_node_state_checkpoints of `state_a`.
  - getSpec: of the node's config, the preset and the constants (include/api_spec.inc); it reads no state.
  - getProposerDuties: lantern_node_proposers of the fork of the state's slot, of `state_a`, with the node's config.
  - produceAttestationData: lantern_node_attestation_data of the fork of the state's slot, of `state_a` and the u64 at byte 0 of `data`, with the node's config; `data` of fewer than 8 bytes gives `LANTERN_INVALID_ENCODING`.
  - getAttesterDuties: lantern_node_attester_duties of the fork of the state's slot, of `state_a` and the `ValidatorRef` items of `data`, with the node's config, into `scratch`; then the answer of each item in order.
  - getStateValidator: the validator of the `ValidatorRef` in `data`, in `state_a`: the one of its index, or the first whose `pubkey` is its public key; with none, the error 404 in place of the response.
  - A `state_a` of these three whose slot is not `arg` / 2^24 gives the result `LANTERN_INVALID_SLOT`: the work that brought it to that slot failed.
- `NODE_WORK_API_SUBMIT`: the operations of the body in `data` (beacon-api.md, the pool POSTs), as a ByteList at `NodeEvent_chunk` of the event, the event's `size` covering it, and their count at `NodeEvent_index`.
  - The body: lantern_json_decode of the type of the operation `arg` % 2^8, of the fork `arg` / 2^16, into `scratch`; for submitPoolBLSToExecutionChange, a JSON array, each item decoded so (from capella; before, the fork has no such type: `LANTERN_INVALID_ENCODING`). A body that is no such text: the result `LANTERN_INVALID_ENCODING`.
  - Each operation in order: lantern_node_gossip of the fork `arg` / 2^16, with a `NodeGossip` of `seen`, the store, `time_ms`, the operation's topic, subnet 0, `state_a` as head, no proposer or justified state, and the node's config. Its record: the result's code (u64), then a ByteList of its SSZ bytes (offset 24, `size` 24 + the bytes to a multiple of 8, zero bytes after them).
  - Before the first: `seen` with fewer free `keys` entries than the operations gives `LANTERN_BUFFER_TOO_SMALL`, so that no check of a list adds to `seen` before one is short.
- `NODE_WORK_POOL_CHECK`: lantern_node_gossip of the fork of the store's slot of the topic `arg` for the bytes in `data`, as for `NODE_WORK_API_SUBMIT`, with an empty `Seen` at the end of `scratch` (lantern_seen_init of a `SeenRoom` of `keys` the bytes' length / 8 + 1, and no other room): its result's code is the event's result. A `scratch` without room for that `Seen` and `LANTERN_SCRATCH_FIXED` bytes before it, a lantern_node_gossip of `LANTERN_BUFFER_TOO_SMALL`, and a `state_a` of another fork than the store's slot give `LANTERN_GOSSIP_IGNORE`.
- `NODE_WORK_API_EVENT`: the text of the event of the topic `arg` % 2^8 (beacon-api.md, eventstream), `event: <topic>` LF `data: <JSON>` LF LF, as a ByteList at `NodeEvent_chunk` of the event; the event's `size` then covers it.
  - head: lantern_node_event_roots of the fork of the slot of `state_a`, with the node's config: `block`, `state` and the two dependent roots; `slot` the state's; `epoch_transition` and `execution_optimistic` from `arg` / 2^8 (1 and 2).
  - finalized_checkpoint: with `data`, the block's root by lantern_node_block_root of the fork of its slot and its message's `state_root`; else the block root and state root of lantern_node_event_roots of `state_a`. `epoch` `arg` / 2^16; `execution_optimistic` from `arg` / 2^8 % 2^8 (2). Bytes that do not hold a block give `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_API_LOOKUP`: the slot whose state on the chain of `state_a` has the root in the first 32 bytes of the `cursor` of the `NodeApi` entry at index `arg`, at `NodeEvent_index`: the slot of `state_a` when it is lantern_state_root of the fork of its slot (with the `StateCache` of the node's config), else the slot s below it, at most `SLOTS_PER_HISTORICAL_ROOT` below, whose entry s % `SLOTS_PER_HISTORICAL_ROOT` of its `state_roots` it is, the highest; else 2^64 - 1. An index past the api part, or of an entry without `API_STREAM_LOOKUP`, gives 2^64 - 1.
- `NODE_WORK_API_CHUNK`: the next chunk of the answer of the `NodeApi` entry at index `arg` (beacon-api.md, Common rules, the streamed answers), from the SSZ bytes in `data`, at `NodeEvent_api` of the event: the entry's `sent` and `flags` and its `cursor` after the chunk, then a ByteList of the chunk's bytes at `NodeEvent_api_bytes`, offset 24; the event's `size` then covers it.
  - A chunk is at most `NODE_API_CHUNK` (65536) bytes, and at most the room of the event after the ByteList's header. With less than `NODE_API_FIRST_ROOM` (1024) bytes of room for the first chunk, or 64 for a later one (1024 for a validator stream, which writes an item in each chunk): `LANTERN_BUFFER_TOO_SMALL`.
  - The first chunk, without `API_STREAM_STARTED`: the head of the answer, then as much of the body as fits; it sets `API_STREAM_STARTED`. A later chunk goes on with the body.
  - `data` of no bytes, or whose slot is not the entry's `slot` (a state's u64 at byte 40, a `SignedBeaconBlock`'s at byte 100), gives the result `LANTERN_INVALID_ENCODING`.
  - The validator streams: the items of the validators of `state_a` from the index at byte 0 of the cursor (`position`), with the status bits at byte 8 of it and the `ValidatorRef` items of `data` (none with `data` 0), as many as fit; `position` then the next index. A `state_a` whose slot is not the entry's gives the result `LANTERN_INVALID_SLOT`.
  - Their `scratch`: 8 bytes for every 64 validators, a bit for each that the items name; with public keys among the items, 8 bytes more for each slot of a table of the keys, the least power of two at least twice their count.
  - getEpochCommittees: the committees of `state_a` (lantern_get_beacon_committee of the fork of the state's slot, with the node's `CommitteeCache`) from the slot at byte 0 of the cursor and the index at byte 8, and within a committee from the member at byte 16, as many as fit; get_committee_count_per_slot of the epoch at byte 56. In the first chunk, an `index` at or past that count gives the error 400 as the whole answer. Its `scratch`: a list of (validators / (SLOTS_PER_EPOCH * the count) + 1) u64, then that of lantern_get_beacon_committee.
  - The pool streams: the head and `{"data":[` (getPoolAttesterSlashingsV2: `{"version":"<fork>","data":[`, the fork `fork`); then, with `data`, the JSON of the bytes of the pool entry at `slot` by lantern_node_json of the entry's fork (`sent`) and the kind of the GET's topic, from `cursor`, after `,` when `API_STREAM_ITEMS` is set; once it is whole, `API_STREAM_ITEMS` and `API_STREAM_ITEM_DONE` in the event. With `data` 0: `]}`, and `API_STREAM_DONE`. A chunk holds the JSON of one entry at most.
  - SSZ: the bytes of `data` from `sent`; `sent` counts them.
  - JSON: the body's start, then lantern_json_encode_ssz of `cursor` (lantern_node_json of the fork of the entry, `SignedBeaconBlock` for getBlockV2 and `BeaconState` for getStateV2), then `}` once the cursor is whole. A first chunk that holds the whole body has `Content-Length`; else, with `API_STREAM_HTTP10`, it sets `API_STREAM_CLOSE`, and else `API_STREAM_CHUNKED`, and each chunk then holds the body's bytes in one chunk of RFC 9112 section 7.1, the last also `0` CRLF CRLF.
  - The chunk that ends the body sets `API_STREAM_DONE`.
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

- The types: beacon_block `SignedBeaconBlock`, beacon_aggregate_and_proof `SignedAggregateAndProof`, beacon_attestation `Attestation` (`SingleAttestation` from electra), voluntary_exit `SignedVoluntaryExit`, proposer_slashing `ProposerSlashing`, attester_slashing `AttesterSlashing`, sync_committee_contribution_and_proof `SignedContributionAndProof`, sync_committee `SyncCommitteeMessage`, bls_to_execution_change `SignedBLSToExecutionChange`, blob_sidecar `BlobSidecar`, data_column_sidecar `DataColumnSidecar`.
- beacon_block, blob_sidecar and data_column_sidecar: lantern_process_slots of the proposer state to the slot of the message's block header, when the state is before it. With no proposer state, the head state is the proposer state.
- Bellatrix beacon_block: the justified state, or the head state with none.
- A valid beacon_block: hash_tree_root of its message in `root`, the length of its body's `blob_kzg_commitments` (0 before deneb) in `index`.
- A valid blob_sidecar or data_column_sidecar: hash_tree_root of its `signed_block_header.message` in `root`, its `index` in `index`.
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
| `kind` | input | u64: `NODE_JSON_BLOCK` (0) `SignedBeaconBlock`, `NODE_JSON_STATE` (1) `BeaconState`, `NODE_JSON_EXIT` (2) `SignedVoluntaryExit`, `NODE_JSON_PROPOSER_SLASHING` (3) `ProposerSlashing`, `NODE_JSON_ATTESTER_SLASHING` (4) `AttesterSlashing`, `NODE_JSON_BLS_CHANGE` (5) `SignedBLSToExecutionChange` |
| `ssz` | input | ByteList: a valid SSZ encoding of the type |
| `cursor` | state | `JsonCursor` of [beacon-api.md](beacon-api.md#type-jsoncursor) |
| `out` | output | ByteList |

### Returns

- As lantern_json_encode_ssz; `LANTERN_INVALID_EVENT` for another `kind`, or for a type the fork does not have (`SignedBLSToExecutionChange` before capella).

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
| 712 | `attnets` | u64 | The attestation subnets the node is subscribed to: bit i for subnet i |
| 720 | `sidecar_floor` | u64 | With `NODE_FLAG_DB`: the `Db` holds no sidecar below this slot; the `Db`'s first slot at the start |
| 728 | `config` | `Config` | |
| 728 + `CONFIG_SIZE` | `api_identity` | `ApiIdentity` of [beacon-api.md](beacon-api.md#type-apiidentity) | Of the last `NODE_EV_API_IDENTITY`; its texts empty at the start |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` | `api` | PartRef | `NodeApi` entries |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 16 | `event_head` | Root | The head of the last head event; the anchor's root at the start |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 48 | `event_slot` | u64 | The slot of `event_head`'s block |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 56 | `event_epoch` | u64 | The store's finalized epoch at the last finalized_checkpoint event; the anchor's finalized epoch at the start |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 64 | `event_votes` | u64 | The `NODE_WORK_BLOCK_ATTESTATION` and `NODE_WORK_BLOCK_SLASHING` works queued and not done |
| 728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 72 | `pool` | PartRef | `NodePool` entries: the pool |

### Rules

- `NODE_FIXED` (728 + `CONFIG_SIZE` + `API_IDENTITY_SIZE` + 88) bytes of fixed fields; the parts follow in the order blocks, checkpoints, pow_blocks, peers, streams, messages, blobs, api, pool, p2p_out, engine_in, db.
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

## Type `NodePool`

An operation of the pool (beacon-api.md, the pools).

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `topic` | u64 | `GOSSIP_VOLUNTARY_EXIT`, `GOSSIP_PROPOSER_SLASHING`, `GOSSIP_ATTESTER_SLASHING` or `GOSSIP_BLS_TO_EXECUTION_CHANGE`; 0 for a free entry |
| 8 | `state` | u64 | `NODE_POOL_KEPT` (1), or `NODE_POOL_CHECKING` (2) while its `NODE_WORK_POOL_CHECK` is queued |
| 16 | `data_id` | u64 | `BufferId` of its SSZ bytes |
| 24 | `length` | u64 | The bytes of its SSZ bytes |
| 32 | `fork` | u64 | `FORK_*` of the type it was decoded with |

### Rules

- `NodePool__mem` (40) bytes.
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

### Rules

- `NodePeer__mem` (192) bytes.

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
| 8 | `op` | u64 | `API_OP_GET_BLOCK_V2`, `API_OP_GET_STATE_V2`, one of the five validator streams, `API_OP_GET_EPOCH_COMMITTEES`, `API_OP_EVENTSTREAM`, or one of the four pool streams |
| 16 | `flags` | u64 | `API_STREAM_*` |
| 24 | `data` | u64 | The `BufferId` of the SSZ bytes, or a `NODE_DB_REF`; the validator streams: of the `ValidatorRef` items, or 0 |
| 32 | `fork` | u64 | `FORK_*` of the block's or the state's slot |
| 40 | `sent` | u64 | SSZ: the bytes of `data` sent; eventstream: the bytes sent since the last `NODE_EV_API_SENT`; a pool stream: the fork of the entry at `slot` |
| 48 | `cursor` | `JsonCursor` | JSON: where lantern_json_encode_ssz goes on; the validator streams: the next index at 0, the status bits at 8; eventstream: the topic bits at 0 |
| 648 | `slot` | u64 | The slot of the block or the state; a pool stream: the index of the pool entry it writes |
| 656 | `state` | u64 | The validator streams: the id of the state they read |

### Rules

- `NodeApi__mem` (664) bytes.
- `flags`: `API_STREAM_CLOSE` (1) the connection closes after the answer; `API_STREAM_HTTP10` (2) an HTTP/1.0 request; `API_STREAM_SSZ` (4) the answer is SSZ, else JSON; `API_STREAM_OWN` (8) the stream frees `data` at its end; `API_STREAM_BUSY` (16) a `NODE_WORK_API_CHUNK` is queued; `API_STREAM_GONE` (32) the connection closed; `API_STREAM_STARTED` (64) the head went; `API_STREAM_CHUNKED` (128) the body goes with `Transfer-Encoding: chunked`; `API_STREAM_OPTIMISTIC` (256) and `API_STREAM_FINALIZED` (512) the JSON's `execution_optimistic` and `finalized`; `API_STREAM_DONE` (1024), in a `NODE_EV_WORK_DONE` only, the chunk ends the answer; `API_STREAM_LOOKUP` (2048) the entry waits for a `NODE_WORK_API_LOOKUP`, and sends no chunk; `API_STREAM_OWN_STATE` (4096) the stream frees `state` at its end; `API_STREAM_ITEMS` (8192) a pool stream wrote an entry; `API_STREAM_ITEM_DONE` (16384), in a `NODE_EV_WORK_DONE` only, the chunk ends an entry.
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
| 216 | | | Size |

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
- `NODE_ACT_STATE_COPY`: copy the state of the id at 16 as the id at 24.
- `NODE_ACT_STATE_FREE`, `NODE_ACT_BYTES_FREE`: free the id at 16.
- `NODE_ACT_WORK`: `NODE_ACT_WORK_SIZE` bytes; call lantern_node_run.
- `NODE_ACT_P2P_LIST`: a ByteList of libp2p `Action` values from 16, offset 24; do its DIAL, ADOPT, REFUSE, SEND, CLOSE and SEND_DATAGRAM in order, and skip the others.
- `NODE_ACT_DISCV5`: a ByteList at 24, offset 24, of asm-discv5 events: pass them to discv5_step.
- `NODE_ACT_DB_APPEND` (`NODE_ACT_DB_APPEND_SIZE`, 128 bytes): 16 a `BufferId` of bytes, 24 a segment's number, 32 1 for a sidecar segment and 0 for a block segment, 40 an offset, 48 a `DbRecord`. Write the record at the offset of the segment file, its end: the `DbRecord`, the bytes, and zero bytes to a multiple of 8. The first record of a segment that a run writes truncates the file to its offset first, so a torn end or an older run's records go.
- `NODE_ACT_DB_STATE` (`NODE_ACT_DB_STATE_SIZE`, 40 bytes): 16 the `BufferId` of a finalized block's post-state, 24 the `BufferId` of the block's SSZ bytes, 32 its slot. The shell may keep them, so that a later start has an anchor whose blocks the `Db` holds.
- `NODE_ACT_DB_DROP` (`NODE_ACT_DB_DROP_SIZE`, 32 bytes): 16 a segment, 24 1 for a sidecar segment, else 0. The shell deletes the segment's file; a later record of that segment starts a new file.
- A `NODE_DB_REF` is a `BufferId` with bit 63 set: bit 62 set for a sidecar segment, the segment's number in bits 48 to 61, and the offset of a record in bits 0 to 47. As the `data` of a SERVE, API_ENCODE or API_CHUNK work it names the SSZ bytes of that record: the shell gives lantern_node_run the record's ByteList at its byte 56, in place in the segment's memory.
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
