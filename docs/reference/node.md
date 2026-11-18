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
- [`lantern_node_attestation`](#function-lantern_node_attestation): on_attestation of an attestation's SSZ bytes, for one fork.
- [`lantern_node_attester_slashing`](#function-lantern_node_attester_slashing): on_attester_slashing of a slashing's SSZ bytes, for one fork.
- [`lantern_node_gossip`](#function-lantern_node_gossip): the gossip validation of a message's SSZ bytes, for one fork.
- [`lantern_node_blob_sidecar`](#function-lantern_node_blob_sidecar): the checks of a blob sidecar of a response, for deneb or electra.
- [`lantern_node_new_payload`](#function-lantern_node_new_payload): the HTTP request of engine_newPayload for a block's SSZ bytes, for one fork.
- [`lantern_node_anchor`](#function-lantern_node_anchor): the anchor state and block of a genesis state's SSZ bytes, for one fork.

### Types

- [`Node`](#type-node): the state of the node.
- [`NodeRoom`](#type-noderoom): the capacities of a `Node`.
- [`NodeBlock`](#type-nodeblock): a block the node knows.
- [`NodeCheckpoint`](#type-nodecheckpoint): a checkpoint state the node keeps.
- [`NodePeer`](#type-nodepeer): a connected libp2p peer.
- [`NodeStream`](#type-nodestream): a req/resp stream a peer opened.
- [`NodeMessage`](#type-nodemessage): a gossip message the node holds.
- [`NodeBlob`](#type-nodeblob): a blob sidecar the node holds.
- [`NodeGossip`](#type-nodegossip): the inputs of lantern_node_gossip.
- [`NodeAnchor`](#type-nodeanchor): the anchor of lantern_node_init.
- [`NodeStepResult`](#type-nodestepresult): the output of lantern_node_step.
- [`NodeEvents`](#type-nodeevents), [`NodeEvent`](#type-nodeevent): the events of lantern_node_step.
- [`NodeActions`](#type-nodeactions), [`NodeAction`](#type-nodeaction): the actions of lantern_node_step.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs), `fork-choice.md` of phase0 to fulu: the handlers, `store.block_states` and `store.checkpoint_states`.
- `p2p-interface.md` of phase0, altair and fulu, The Req/Resp domain: Status, Goodbye, Ping and MetaData, their versions, and the result codes.
- `p2p-interface.md` of phase0, Status: once the handshake completes, the client with the lower `head_slot` requests blocks with BeaconBlocksByRange.
- `p2p-interface.md` of phase0 to fulu, The gossip domain: the topics of each fork, the message-id, `MAX_PAYLOAD_SIZE`, and the validation of each topic, as [networking.md](networking.md) gives it.
- `fork-choice.md` of deneb, `is_data_available`: a block is not valid until its blobs are downloaded; the network does not promise sidecars outside `MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS`.
- `p2p-interface.md` of deneb, BlobSidecarsByRange v1: the reader checks each sidecar's format, inclusion proof and KZG proof before the next chunk.
- `p2p-interface.md` of deneb, BlobSidecarsByRange v1 and BlobSidecarsByRoot v1: the server sends the sidecars of the head's chain in (slot, index) order, or of the requested identifiers in their order, at most compute_max_request_blob_sidecars; of electra, its limit; of fulu, the deprecation: sidecars before `FULU_FORK_EPOCH`, an empty list at or after it.
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
- lantern_node_size, lantern_node_init, lantern_node_copy, lantern_node_step, lantern_node_run and lantern_node_protocols are in the common object of the core (asm/core/<ISA>/node.s), and each symbol is its name.
- lantern_node_import, lantern_node_block_root, lantern_node_attestation, lantern_node_attester_slashing and lantern_node_gossip are in each fork object (asm/core/<ISA>/nodehooks.s), exported as `lantern_<fork>_<name>`. lantern_node_blob_sidecar is in the deneb and electra objects only, lantern_node_new_payload in the bellatrix and later objects.

## Test vectors

- The fork_choice files of [fork-choice.md](fork-choice.md#test-vectors), a second time, through the node: each case reports a second time with ` (node)` after its name.
  - The runner plays the shell: a table of `BufferId` to buffer, the actions of each step in order, each `NODE_ACT_WORK` run when it comes, its event to the next step, until a step gives no work.
  - Its config sets the epoch of each fork up to the runner's fork to 0 and of each later fork to 2^64 - 1.
  - Each step of the case is events: `tick` a `NODE_EV_TICK`, `block` a `NODE_EV_BLOCK` with the block's data availability, `attestation` a `NODE_EV_ATTESTATION`, `attester_slashing` a `NODE_EV_ATTESTER_SLASHING`, `pow_block` a `NODE_EV_POW_BLOCK`.
  - After a valid block it sends the block's attestations, with `is_from_block` 1, and attester slashings as events of one step.
  - A valid block must be `NODE_BLOCK_IMPORTED`, an invalid block must not. An attestation or slashing is valid when the result of its last work is `LANTERN_VALID`.
  - The checks read the store, the node's `head_root`, and the post-state the node keeps for the head.
  - From bellatrix on, the node has `NODE_FLAG_ENGINE`, and the runner is its execution engine too. It answers each `NODE_ACT_ENGINE` request with an HTTP/1.1 response in two `NODE_EV_ENGINE` events: engine_newPayload of a `blockHash`, and engine_forkchoiceUpdated of a `headBlockHash`, with the `payloadStatus` of the case's last `payload_status` step of that hash, else `VALID` with that hash as `latestValidHash`. The request must carry a JWT of the node's secret.
  - Cases with `payload_status` steps run in node mode from bellatrix on, through the node's execution engine calls; before bellatrix only directly.
  - A non-zero status of lantern_node_step or lantern_node_run must leave the node, the store and the work's state byte for byte unchanged.
- The anchor of each fork_choice case: lantern_node_anchor of the case's `anchor_state` must give a state whose SSZ bytes are the case's `anchor_state` and a block whose SSZ bytes are the case's `anchor_block`, when that block has the default body; else `LANTERN_INVALID_ANCHOR`.
- Lantern's cases `<preset>-<fork>-node-p2p.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec: an anchor state and block at the first slot of epoch 2, and the Status and MetaData the node answers.
  - The answers come from get_forkchoice_store, get_head and compute_fork_digest of the spec module, with each fork up to the case's at epoch 0 and each later fork at 2^64 - 1.
  - The runner plays the network between the node's libp2p state and a bare asm-libp2p peer, as tests/runner of asm-libp2p does. The peer dials the node and opens one stream for each request.
  - Status (v2 in fulu, v1 before) and MetaData (v3 in fulu, v2 before) must be the case's; Ping must give 0; Goodbye must close with no answer.
  - The node's peer entry must hold the peer's ID and the Status it sent.
  - The node has `NODE_FLAG_DISCV5`: its `NODE_ACT_DISCV5` actions must set `eth2` to lantern_compute_enr_fork_id at the anchor's epoch, `attnets` to 8 zero bytes, from altair `syncnets` to 1 zero byte, in fulu `cgc` to `CUSTODY_REQUIREMENT` and `nfd` to lantern_compute_next_fork_digest, and ask for a lookup.
- The `fork_choice-get_head` and `fork_choice-on_block` cases in node mode, after their steps: the runner opens the same network, and the node serves the chain of the case's last checked head, which the runner builds from the case's valid blocks by `parent_root`.
  - BeaconBlocksByRange v2 from the anchor's slot to the head's must give each block of the chain, in slot order.
  - BeaconBlocksByRoot v2 of the head, a root of no block, and the chain's first block must give the head and the first block.
  - Each chunk must have result 0, the block's SSZ bytes, and compute_fork_digest of the block's epoch as context bytes.
- The `fork_choice-get_head` and `fork_choice-on_block` cases a third time, over gossip: each case reports with ` (gossip)` after its name.
  - Only cases with no `payload_status` step whose valid blocks each have their own slot and come at or after the start of that slot.
  - The runner opens the same network. The node's topics must reach the peer.
  - Each valid block goes from the peer as a beacon_block message, Snappy compressed, on the topic of the block's epoch. The node must import it.
  - Each valid attester slashing goes from the peer on the attester_slashing topic of the last tick's epoch. One the node does not apply goes again as a `NODE_EV_ATTESTER_SLASHING`. A case with valid attester slashings must apply one over gossip.
  - The other steps go as in node mode; the checks must hold.
- The same cases in node mode, after the serving check: a new node at the case's anchor, at the case's last tick, syncs the chain of the last checked head.
  - The runner's peer has a secp256k1 key. The node gets a `NODE_EV_ENR` of the peer's record, made with asm-discv5 from that key, with an `ip`, a `tcp` port and the `eth2` of lantern_compute_enr_fork_id at the case's epoch. The node must dial the peer and send its Status; the peer answers with a Status whose head is the chain's last block, and answers each BeaconBlocksByRange request of the node with the chain's blocks in the range.
  - It answers each BlobSidecarsByRange request with the sidecars of the case's `node-blobs` case of the chain's blocks in the range, in (slot, index) order, with compute_fork_digest of the slot's epoch as context bytes.
  - Each block of the chain must be `NODE_BLOCK_IMPORTED`, and the node's `head_root` must be the chain's last block.
  - Each sidecar it sent must be a `NODE_BLOB_VALID` entry of the node.
  - Then the node serves them: BlobSidecarsByRange v1 from the anchor's slot to the head's must give each sidecar of the chain in (slot, index) order; BlobSidecarsByRoot v1 of the chain's sidecars from the last block to the first, with an identifier of no sidecar among them, must give those sidecars in that order. Each chunk must have result 0, the sidecar's SSZ bytes, and compute_fork_digest of its slot's epoch as context bytes.
  - A case with sidecars syncs again with a new node and no sidecars in the answers: no block of the chain with blob commitments, and no later one, may be `NODE_BLOCK_IMPORTED`.
- Lantern's cases `<preset>-<fork>-node-blobs.bin` of deneb and electra, made by tests/generator/node.py with the pinned spec: one for each `fork_choice-on_block` case whose block steps have blobs, of the same name.
  - Each part is named after a block file of the case and holds the `BlobSidecar` SSZ bytes of get_blob_sidecars of the block and the step's blobs and proofs, as a list.
  - A step with fewer proofs than blobs gives the sidecars of the indices that have both.
- In gossip mode, the sidecars of a valid block go from the peer after the block, each on the blob_sidecar topic of its subnet; the node must import the block.

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
- `LANTERN_INVALID_OVERFLOW`: the size is 2^64 or more.

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

### Function does

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
- `LANTERN_BUFFER_TOO_SMALL`: `out` is smaller than lantern_node_size of `room`, or a capacity of `room` is below the entries of its part.
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
- `LANTERN_BUFFER_TOO_SMALL`: `actions`, a part of `node`, or `scratch` has too little room. Nothing is changed.

### Caller must

- Do the actions in order before the next step.
- Pass the events after `accepted` again in the next step, before new ones.
- Step again by `wakeup`.
- Grow the node with lantern_node_copy and give more room to `actions` and `scratch` on `LANTERN_BUFFER_TOO_SMALL`, then call again with the same events.

### Function does

- Room: `actions` has the event bytes + 512 per event + 128 per known block + 512 bytes free, and `LIBP2P_ACTIONS_MIN` + 40 more with `p2p`; with `p2p`, `p2p_out` has room for the libp2p events of the `NODE_EV_P2P` events, and `scratch` holds as many bytes again and `LIBP2P_SCRATCH_SIZE`; the blocks part has an entry free per `NODE_EV_BLOCK` and per `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`, and `NODE_SYNC_BATCH` more with `p2p`; the blobs part has an entry free per `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`, and with `p2p` `NODE_SYNC_BATCH` times the larger of `MAX_BLOBS_PER_BLOCK` and `MAX_BLOBS_PER_BLOCK_ELECTRA` more; the checkpoints part has 2 free per `NODE_EV_WORK_DONE`, and 2; the pow blocks part has an entry free per `NODE_EV_POW_BLOCK`; `engine_in` has room for the bytes of the `NODE_EV_ENGINE` events; `scratch` has `LANTERN_SCRATCH_FIXED` + 64 + 16 bytes per store node, and `DISCV5_ENR_SIZE` + `DISCV5_ENR_SCRATCH` more with a `NODE_EV_ENR`.
- Before any change: the root of each `NODE_EV_BLOCK`, with lantern_node_block_root of the fork of its slot. A status of that call is the step's.
- `NODE_EV_TICK`: sets `time_ms` of the node, then on_tick of the fork of the new slot.
- `NODE_EV_BLOCK`: for a root the node does not know, a `NODE_ACT_BYTES_PUT` of the bytes and a `NodeBlock` in `NODE_BLOCK_WAITING`. Bytes that are no `SignedBeaconBlock` are dropped.
- A waiting block whose parent is imported: a `NODE_ACT_STATE_COPY` of the parent's post-state and a `NODE_WORK_IMPORT_BLOCK`; the block is `NODE_BLOCK_IMPORTING`. A waiting block whose parent is invalid becomes `NODE_BLOCK_INVALID`.
- With `NODE_FLAG_ENGINE`, a waiting block of bellatrix or later whose parent is imported takes `NODE_BLOCK_PAYLOAD` instead, with `retry` 0: its import waits for the execution engine's answer.
- `NODE_EV_ATTESTATION`: a `NODE_ACT_BYTES_PUT` of the bytes and a `NODE_WORK_ATTESTATION` with the target checkpoint state, or 0 when the node has none.
- `NODE_EV_ATTESTER_SLASHING`: a `NODE_ACT_BYTES_PUT` of the bytes and a `NODE_WORK_ATTESTER_SLASHING` with the post-state of the justified root.
- `NODE_EV_POW_BLOCK`: adds the `PowBlock` to the node.
- `NODE_EV_WORK_DONE` of `NODE_WORK_IMPORT_BLOCK`: valid, the block is `NODE_BLOCK_IMPORTED` and its waiting children are imported; `LANTERN_NEED_JUSTIFIED_STATE`, a `NODE_WORK_JUSTIFIED_STATE` and the same import again; else `NODE_BLOCK_INVALID` and a `NODE_ACT_STATE_FREE` of its state.
- `NODE_EV_WORK_DONE` of `NODE_WORK_ATTESTATION` with `LANTERN_NEED_TARGET_STATE`: the target checkpoint state, then the same attestation again with it.
- A checkpoint state the node does not have: a `NODE_ACT_STATE_COPY` of the post-state of the checkpoint's root, a `NodeCheckpoint`, and a `NODE_WORK_TARGET_STATE`.
- An attestation or slashing done: a `NODE_ACT_BYTES_FREE` of its bytes.
- The head: get_head of the fork of the store's slot into `head_root`, or a `NODE_WORK_JUSTIFIED_STATE` when it returns `LANTERN_NEED_JUSTIFIED_STATE`.
- libp2p first, before the node's events: libp2p_step with the queued events, then the `NODE_EV_P2P` events, after them in the queue. The first libp2p_step takes at most half the action room left, when that half is enough, so the notices have room. When it accepts k of n P2P events, with k < n, the P2P events it did not take leave the queue, the step handles the node's events before the next P2P event, and gives that count as `accepted`. A status of libp2p_step leaves the queue as it was.
- `PEER_CONNECTED`: a `NodePeer`, or a `DISCONNECT` when the peers part is full. `PEER_DISCONNECTED`: the peer and its streams go.
- `PEER_CONNECTED` and `DIAL_FAILED` of a tag with `NODE_DIAL_TAG`: `dialing` takes 1 less. A `PEER_CONNECTED` of `LIBP2P_OUTBOUND` that gets a `NodePeer`: a Status request (v2 from fulu, v1 before) with the node's Status, as a request of the node.
- `NODE_EV_ENR`, with `p2p`: the record of discv5_enr_decode, with an `ip`, a `tcp` pair of 1 or 2 bytes, an `eth2` pair whose first 4 bytes are compute_fork_digest of the store's epoch, and a `secp256k1` key whose peer ID (the identity multihash of the protobuf secp256k1 public key) no `NodePeer` has, gets a `DIAL` over TCP to that address with that peer ID and a tag with `NODE_DIAL_TAG`, when `dialing` + the peers are below the capacity of the peers part and `p2p_out` has room; `dialing` takes 1 more. Another record changes nothing.
- With `NODE_FLAG_DISCV5`, at each subscription to a new `fork_digest`: a `NODE_ACT_DISCV5` of `SET_ENTRY` events: `eth2`, lantern_compute_enr_fork_id at the store's epoch; `attnets`, 8 zero bytes; from altair `syncnets`, 1 zero byte; from fulu `cgc`, `CUSTODY_REQUIREMENT` in big-endian bytes with no leading zero, and `nfd`, lantern_compute_next_fork_digest.
- With `NODE_FLAG_DISCV5`, after the head: when `dialing` + the peers are below the capacity of the peers part, and `time_ms` is at least `lookup_ms` + `NODE_LOOKUP_MS` or `lookup_ms` is 0, a `NODE_ACT_DISCV5` of a `LOOKUP` event whose target is the tick's 32 entropy bytes; `lookup_ms` takes `time_ms`.
- `STREAM_INBOUND`: a `NodeStream` of the protocol's method and version, or a `STREAM_RESET` when the streams part is full. `STREAM_DATA`: the bytes join the stream's request, or a `STREAM_RESET` when they pass its room. `STREAM_EOF`: the request is complete. `STREAM_RESET`: the stream goes.
- A request is read when its bytes are complete: Status is kept in the `NodePeer` and answered with the node's Status of the same version; Ping is answered with `metadata_seq`; MetaData, on the stream's opening, with the node's MetaData of the same version; Goodbye gets a `STREAM_CLOSE`. A request that is not valid gets result 1, InvalidRequest; a method of no answer below gets result 3, ResourceUnavailable.
- BeaconBlocksByRange: a `start_slot` before `earliest_slot` gets ResourceUnavailable. Otherwise the blocks of the chain of `head_root`, by `parent_root`, with a slot in `start_slot` to `start_slot` + `count`, in slot order; `count` is at most `MAX_REQUEST_BLOCKS_DENEB` from deneb on, else `MAX_REQUEST_BLOCKS`, and at most the BufferIds a stream's request room holds.
- BeaconBlocksByRoot: the imported blocks of the roots the node knows, in the request's order; the request has at most that many roots.
- BlobSidecarsByRange and BlobSidecarsByRoot, when the fork of the store's slot is deneb or later; before it, ResourceUnavailable. The sidecar limit is `MAX_REQUEST_BLOCKS_DENEB` times `MAX_BLOBS_PER_BLOCK` (deneb) or `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra and later), and at most the BufferIds a stream's request room holds.
- BlobSidecarsByRange: a `start_slot` before `earliest_slot` gets ResourceUnavailable. Otherwise the `NODE_BLOB_VALID` sidecars of the imported blocks of the chain of `head_root` with a slot in `start_slot` to `start_slot` + `count`, in (slot, index) order, up to the limit; the indices of a block are those below the larger of `MAX_BLOBS_PER_BLOCK` and `MAX_BLOBS_PER_BLOCK_ELECTRA`, and below `NODE_BLOB_MAX`.
- BlobSidecarsByRoot: the `NODE_BLOB_VALID` sidecars of the request's (block_root, index) pairs whose block is not `NODE_BLOCK_INVALID`, in the request's order; the request has at most the limit of pairs, a multiple of 40 bytes.
- The anchor, with no bytes, is not sent. No block or sidecar: a `STREAM_CLOSE` with no chunk. Else the stream keeps the BufferIds and takes `NODE_STREAM_SERVE`.
- After the head, each stream in `NODE_STREAM_SERVE` gets a `NODE_WORK_SERVE` of its next block or sidecar, with the protocol version + 256 times the method as `arg`, and takes `NODE_STREAM_SERVING`, while the actions have room for the work and 4096 bytes; a stream left waiting makes `wakeup` the tick's time.
- `NODE_EV_WORK_DONE` of `NODE_WORK_SERVE`: the chunk goes out in a `STREAM_WRITE`, then the stream's next block, or a `STREAM_CLOSE` after the last; a result other than `LANTERN_VALID`, or no room in `p2p_out`, gives a `STREAM_RESET`.
- An answer is one chunk of lantern_reqresp_write_chunk in a `STREAM_WRITE`, then a `STREAM_CLOSE`; then the stream goes.
- The node's Status: compute_fork_digest of the store's epoch, the store's finalized checkpoint, `head_root` and its slot, and `earliest_slot`. Its MetaData: `metadata_seq`, no attestation or sync subnets, and `CUSTODY_REQUIREMENT` custody groups.
- After the head, with `p2p`: a `SUBSCRIBE` of each topic of the fork of the store's epoch at compute_fork_digest of that epoch, once for each digest, when `p2p_out` has 8192 bytes free. The topics: beacon_block, beacon_aggregate_and_proof, voluntary_exit, proposer_slashing and attester_slashing; from altair sync_committee_contribution_and_proof; from capella bls_to_execution_change; in deneb and electra blob_sidecar of each subnet.
- `MESSAGE`: a `MESSAGE_ID` of compute_message_id of the fork of the store's slot, then a `NodeMessage` when the messages part has room. Its data uncompressed with Snappy goes in a `NODE_ACT_BYTES_PUT`, and for a block, a blob sidecar or a column sidecar the slot and parent root of its block header go in the entry. Data that is no Snappy block of at most `MAX_PAYLOAD_SIZE` bytes makes the entry `NODE_MESSAGE_CORRUPT`; data that does not fit in `scratch` or the actions makes it `NODE_MESSAGE_NO_ROOM`.
- `MESSAGE_STATUS` of `LIBP2P_MSG_NEW` for an entry with bytes: a `NODE_WORK_GOSSIP` with the head's post-state, the post-state of the justified root, and for a block, a blob sidecar or a column sidecar whose parent is imported at an earlier slot a `NODE_ACT_STATE_COPY` of the parent's post-state; the entry takes `NODE_MESSAGE_VALIDATING`. With no bytes, or no room in the actions, a `VALIDATION` of `LIBP2P_IGNORE`, or `LIBP2P_REJECT` for `NODE_MESSAGE_CORRUPT`. Any other status: the bytes and the entry go.
- After the subscriptions and the serving, with `p2p`: the response bytes of each stream in `NODE_STREAM_RESPONSE` are read. Then, with no `NODE_FLAG_SYNCING`, a BeaconBlocksByRange (v2 from altair, v1 before) to the first peer with a Status of the node's `fork_digest` whose `head_slot` is at least the start slot: the start slot is the head's slot + 1, or `sync_slot` when that is higher; the count is at most `NODE_SYNC_BATCH` and reaches the peer's `head_slot`; the step is 1. The node takes `NODE_FLAG_SYNCING`, and `sync_slot` becomes the start slot + the count. A response that waits for room makes `wakeup` the tick's time.
- Before that request, when the streams part has room for two entries: a BlobSidecarsByRange v1 to the same peer of the slots of the range in the blob window whose fork is deneb or electra, when there are any. The blob window: the slots of the epochs from max(the store's epoch - `MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS`, `DENEB_FORK_EPOCH`) on. With no room for it, no request.
- A request of the node: a `NodeStream` in `NODE_STREAM_OPENING` whose list holds the request chunk, its `handle` a tag with bit 63 set, and an `OPEN_STREAM` of the protocol ID. `STREAM_OPENED` of the tag: the stream takes its handle and `NODE_STREAM_RESPONSE`, its request goes in a `STREAM_WRITE` with a `STREAM_CLOSE`, and its list then holds the response. `STREAM_FAILED` of the tag: the stream goes.
- A response chunk is read when its bytes are complete, with a ForkDigest context for BeaconBlocksByRange v2. A Status is kept in the `NodePeer`, as a Status request is. A block of at least 184 and at most `MAX_PAYLOAD_SIZE` bytes, when the actions and the blocks part have room: a `NodeBlock` in `NODE_BLOCK_HASHING` with root 0, the slot and parent root of its bytes and `data_available` 1, a `NODE_ACT_BYTES_PUT` of its bytes, and a `NODE_WORK_SYNC_BLOCK` of its index. A blob sidecar, with a ForkDigest context, of the SSZ size of `BlobSidecar`, when the actions and the blobs part have room: a `NodeBlob` in `NODE_BLOB_VERIFYING` with block root 0, the index and slot of its bytes, a `NODE_ACT_BYTES_PUT` of its bytes, and a `NODE_WORK_BLOB` of its index. The stream goes after a Status chunk, after its last chunk and `STREAM_EOF`, after a chunk whose result is not 0, and with a `STREAM_RESET` after a chunk that is not valid. A stream of the node's BeaconBlocksByRange that goes ends `NODE_FLAG_SYNCING`.
- `NODE_EV_WORK_DONE` of `NODE_WORK_SYNC_BLOCK` for a block in `NODE_BLOCK_HASHING`: `LANTERN_VALID` and a root the node does not know, the block takes the root and the blob count at `NodeEvent_index`, then waits for its blobs; else `NODE_BLOCK_INVALID` and a `NODE_ACT_BYTES_FREE` of its bytes.
- A block from the network (gossip or a response) needs blobs when its slot's fork is deneb or electra, its blob count is above 0 and at most the fork's `MAX_BLOBS_PER_BLOCK` (deneb) or `MAX_BLOBS_PER_BLOCK_ELECTRA` (electra) and `NODE_BLOB_MAX`, and its slot is in the blob window. It has them when the node holds a `NODE_BLOB_VALID` entry of its root for each index below the count.
- A block that waits for its blobs: in `NODE_BLOCK_BLOBS` while it needs blobs it does not have; else `data_available` 1 and `NODE_BLOCK_WAITING`, then it imports as a `NODE_EV_BLOCK` does.
- `NODE_EV_WORK_DONE` of `NODE_WORK_BLOB` for an entry in `NODE_BLOB_VERIFYING`: `LANTERN_VALID` and no `NODE_BLOB_VALID` entry of the same root and index, the entry takes the root at `NodeEvent_root` and `NODE_BLOB_VALID`; else `NODE_BLOB_INVALID` and a `NODE_ACT_BYTES_FREE` of its bytes.
- An entry that becomes `NODE_BLOB_VALID`: the block of its root in `NODE_BLOCK_BLOBS`, if there is one, waits for its blobs again.
- With `NODE_FLAG_ENGINE`, after the head: with no call in flight (`engine_method` 0) and the store's slot at least `engine_wait`, the first block in `NODE_BLOCK_PAYLOAD` whose `retry` is at most the store's slot gets a `NODE_WORK_NEW_PAYLOAD` with the id `engine_id`, takes `NODE_BLOCK_EXECUTING`, and is the call in flight; with none, and `NODE_FLAG_FCU`, a `NODE_WORK_FORKCHOICE` when the fork of the store's slot is bellatrix or later. Each call takes the next id.
- A `head_root` that changes with `NODE_FLAG_ENGINE` sets `NODE_FLAG_FCU`; a `NODE_WORK_FORKCHOICE` clears it.
- `NODE_EV_WORK_DONE` of `NODE_WORK_NEW_PAYLOAD` or `NODE_WORK_FORKCHOICE`: `LANTERN_VALID`, its request goes out in a `NODE_ACT_ENGINE`. Another result ends the call; for engine_newPayload, `LANTERN_NO_PAYLOAD` imports the block with `PAYLOAD_STATUS_VALID`, and any other makes it `NODE_BLOCK_INVALID` with a `NODE_ACT_BYTES_FREE` of its bytes.
- `NODE_EV_ENGINE` with arg 0: its bytes join `engine_in`. When they hold a whole response of lantern_http_parse_response, the response leaves `engine_in` and lantern_engine_parse_response of the method in flight reads its body. A status other than 200, a body that is no answer of the method, a JSON-RPC error or another id is a failed call. arg 1: the call in flight failed, and `engine_in` empties.
- A failed engine_newPayload: the block takes `NODE_BLOCK_PAYLOAD` with `retry` the store's slot + 1 (optimistic-sync.md: no optimistic import, the block MAY be queued). A failed call makes `engine_wait` the store's slot + 1; a failed engine_forkchoiceUpdated sets `NODE_FLAG_FCU` again. The call ends.
- engine_newPayload answered: `VALID`, the block is imported with `PAYLOAD_STATUS_VALID`. `SYNCING` or `ACCEPTED`, the block is imported with `PAYLOAD_STATUS_NOT_VALIDATED` when it is an optimistic candidate: its parent's `BlockNode.block_hash` is not zero, or its slot + `SAFE_SLOTS_TO_IMPORT_OPTIMISTICALLY` is at most the store's slot; else it takes `NODE_BLOCK_PAYLOAD` with `retry` the store's slot + 1. `INVALID` or `INVALID_BLOCK_HASH`, the block is `NODE_BLOCK_INVALID`, its bytes go, and `latestValidHash` applies from its parent. The call ends.
- engine_forkchoiceUpdated answered: `VALID`, lantern_store_payload_status of the head's node with `PAYLOAD_STATUS_VALID`; `INVALID` or `INVALID_BLOCK_HASH`, `latestValidHash` applies from the head, the head included. The call ends.
- `latestValidHash` applies from a block of the store: up the chain from it, by `parent_root`, each block whose `block_hash` is not `latestValidHash` gets lantern_store_payload_status with `PAYLOAD_STATUS_INVALIDATED`, until the block whose `block_hash` is `latestValidHash`. A zero hash stops at the first block whose `block_hash` is zero. With null, or a hash no block of the chain has, only the block in question (a block of the store) gets it.
- `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`: a `VALIDATION` of `LIBP2P_ACCEPT` for `LANTERN_VALID`, `LIBP2P_REJECT` for `LANTERN_GOSSIP_REJECT`, else `LIBP2P_IGNORE`; a `NODE_ACT_STATE_FREE` of the proposer state. A valid beacon_block of a root the node does not know keeps its bytes as a `NodeBlock` with the blob count at `NodeEvent_index`, which waits for its blobs. A valid blob_sidecar keeps its bytes as a `NodeBlob` in `NODE_BLOB_VALID` of the root at `NodeEvent_root`, the index at `NodeEvent_index` and the message's slot, when the node holds no `NODE_BLOB_VALID` entry of that root and index. A valid attester_slashing with a justified state keeps its bytes for a `NODE_WORK_ATTESTER_SLASHING` with that state. Else the bytes go. The entry goes.

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
- `LANTERN_BUFFER_TOO_SMALL`: the store, `state_a`, `scratch` or `event` has too little room. Nothing is changed.
- `LANTERN_INVALID_EVENT`: the work is of no kind, or names no `NodeCheckpoint`.

### Caller must

- On `LANTERN_BUFFER_TOO_SMALL`, grow the store with lantern_store_copy, or `state_a` with lantern_beacon_state_copy, or `scratch`, or for a SERVE work `event`, then call again.

### Function does

- `NODE_WORK_IMPORT_BLOCK`: lantern_node_import of the fork of the block's slot, with `BlockOptions` of `PAYLOAD_STATUS_VALID` (`PAYLOAD_STATUS_NOT_VALIDATED` with `NODE_FLAG_OPTIMISTIC`; the block's `payload_status` with `NODE_FLAG_ENGINE`) and the block's `data_available`. `LANTERN_NEED_JUSTIFIED_STATE` becomes the result.
- `NODE_WORK_JUSTIFIED_STATE`: lantern_store_justified_checkpoint_state with `state_a`.
- `NODE_WORK_TARGET_STATE`: lantern_store_target_checkpoint_state of `state_a` to the `NodeCheckpoint` at index `target`.
- `NODE_WORK_ATTESTATION`: lantern_node_attestation of the fork of the attestation's slot; `is_from_block` is the work's `arg`.
- `NODE_WORK_ATTESTER_SLASHING`: lantern_node_attester_slashing of the fork of the store's slot.
- `NODE_WORK_SERVE`: the response chunk of the block or blob sidecar in `data`, with lantern_reqresp_write_chunk, as a ByteList at `NodeEvent_chunk` of the event; its context bytes are compute_fork_digest of the epoch of the block's slot (blocks of version 2) or of the sidecar's block header slot (the blob methods), none for blocks of version 1. The event's `size` then covers the chunk.
- `NODE_WORK_SYNC_BLOCK`: lantern_node_block_root of the fork of the block's slot, its root at `NodeEvent_root` and its blob count at `NodeEvent_index`.
- `NODE_WORK_NEW_PAYLOAD`: lantern_node_new_payload of the fork of the block's slot (bellatrix and later; before it `LANTERN_NO_PAYLOAD`), its request a ByteList at `NodeEvent_chunk`. The event's `size` then covers it.
- `NODE_WORK_FORKCHOICE`: engine_forkchoiceUpdated of the fork of the store's slot with the `block_hash` of the store's nodes of `head_root`, the justified checkpoint's root (safe) and the finalized checkpoint's root, in an HTTP POST to `engine_host` with a JWT of `jwt_secret` and the time `time_ms` / 1000, a ByteList at `NodeEvent_chunk`; `LANTERN_INVALID_UNKNOWN_BLOCK` when the store has no node of one of those roots, `LANTERN_NO_PAYLOAD` before bellatrix or when the head's `block_hash` is zero (no call).
- `NODE_WORK_BLOB`: lantern_node_blob_sidecar of the fork of the sidecar's slot with the node's config and `settings`, the root at `NodeEvent_root`; a slot whose fork is not deneb or electra gives the result `LANTERN_INVALID_ENCODING`.
- `NODE_WORK_GOSSIP`: lantern_node_gossip of the fork of the store's slot, with a `NodeGossip` of `seen`, the store, `time_ms`, the topic and subnet of `arg`, `state_a` as head, `state_b` as proposer, `state_c` as justified, `settings` and the node's config, its `root` at `NodeEvent_root` and its `index` at `NodeEvent_index`.
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
- A valid blob_sidecar: hash_tree_root of its `signed_block_header.message` in `root`, its `index` in `index`.
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
| 440 | `config` | `Config` | |

### Rules

- `NODE_FIXED` (440 + `CONFIG_SIZE`) bytes of fixed fields; the parts follow in the order blocks, checkpoints, pow_blocks, peers, streams, messages, blobs, p2p_out, engine_in.
- The capacity of a part is its bytes up to the next part over its entry's bytes; `p2p_out` is the last part.
- `NODE_FLAG_OPTIMISTIC`: blocks are imported as `PAYLOAD_STATUS_NOT_VALIDATED`.
- `NODE_FLAG_JUSTIFIED_PENDING`: a `NODE_WORK_JUSTIFIED_STATE` is queued.
- `NODE_FLAG_SUBSCRIBED`: the topics of `fork_digest` are subscribed.
- `NODE_FLAG_SYNCING`: a BeaconBlocksByRange request of the node is open.
- `NODE_FLAG_ENGINE`: the node drives an execution engine; `NODE_FLAG_FCU`: an engine_forkchoiceUpdated is due.
- `NODE_FLAG_DISCV5`: the shell runs asm-discv5 for the node.

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

## Type `NodeBlock`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | hash_tree_root of the block |
| 32 | `parent_root` | Root | |
| 64 | `slot` | u64 | |
| 72 | `data_id` | u64 | `BufferId` of the `SignedBeaconBlock`'s SSZ bytes |
| 80 | `state_id` | u64 | `BufferId` of its post-state, 0 until its import is queued |
| 88 | `status` | u64 | `NODE_BLOCK_WAITING`, `NODE_BLOCK_IMPORTING`, `NODE_BLOCK_IMPORTED`, `NODE_BLOCK_INVALID`, `NODE_BLOCK_HASHING` while a `NODE_WORK_SYNC_BLOCK` of its root is queued (root 0), or `NODE_BLOCK_BLOBS` while it needs blob sidecars the node does not hold |
| 96 | `data_available` | u64 | 1 or 0: from its `NODE_EV_BLOCK`, or 1 for a block from the network once its blobs are held |
| 104 | `result` | u64 | The result of its last import |
| 112 | `blobs` | u64 | For a block from the network: the length of its body's `blob_kzg_commitments`, 0 before deneb |
| 120 | `payload_status` | u64 | With `NODE_FLAG_ENGINE`: `PAYLOAD_STATUS_*` of the execution engine's answer, for its import |
| 128 | `retry` | u64 | The slot from which its engine_newPayload may go again |

### Rules

- `NodeBlock__mem` (136) bytes.
- With `NODE_FLAG_ENGINE`, the status `NODE_BLOCK_PAYLOAD` while its engine_newPayload is due, and `NODE_BLOCK_EXECUTING` while it is queued or sent.

## Type `NodeCheckpoint`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `epoch` | u64 | |
| 8 | `root` | Root | |
| 40 | `state_id` | u64 | `BufferId` of the checkpoint state |

### Rules

- `NodeCheckpoint__mem` (48) bytes. The first 40 bytes are a `Checkpoint`.

## Type `NodePeer`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `handle` | u64 | The libp2p peer Handle |
| 8 | `direction` | u64 | `LIBP2P_INBOUND` or `LIBP2P_OUTBOUND` |
| 16 | `flags` | u64 | `NODE_PEER_STATUS`: a Status of the peer was read |
| 24 | `fork_digest` | u64 | Its Status: 4 bytes |
| 32 | `finalized_root` | Root | |
| 64 | `finalized_epoch` | u64 | |
| 72 | `head_root` | Root | |
| 104 | `head_slot` | u64 | |
| 112 | `earliest_slot` | u64 | Status v2 `earliest_available_slot`, else 0 |
| 120 | `id_len` | u64 | |
| 128 | `id` | 48 bytes | The peer ID |

### Rules

- `NodePeer__mem` (176) bytes.

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
| 40 | `state` | u64 | `NODE_MESSAGE_ID`, `NODE_MESSAGE_VALIDATING`, `NODE_MESSAGE_NO_ROOM` or `NODE_MESSAGE_CORRUPT` |
| 48 | `slot` | u64 | The slot of its block header |
| 56 | `parent_root` | Root | The parent root of its block header |

### Rules

- `NodeMessage__mem` (88) bytes.

## Type `NodeBlob`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `block_root` | Root | hash_tree_root of its `signed_block_header.message`, 0 while `NODE_BLOB_VERIFYING` |
| 32 | `index` | u64 | |
| 40 | `slot` | u64 | The slot of its block header |
| 48 | `data_id` | u64 | `BufferId` of the `BlobSidecar`'s SSZ bytes |
| 56 | `status` | u64 | `NODE_BLOB_VERIFYING` while a `NODE_WORK_BLOB` of it is queued, `NODE_BLOB_VALID`, or `NODE_BLOB_INVALID` with its bytes freed |

### Rules

- `NodeBlob__mem` (64) bytes.
- The node holds at most one `NODE_BLOB_VALID` entry of each block root and index.

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

## Type `NodeStepResult`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `accepted` | u64 | Events handled, from the first |
| 8 | `wakeup` | u64 | Monotonic ms by which the next step is due: libp2p's WAKEUP, the tick's time while the node holds events for libp2p, 2^64 - 1 with no `p2p` |

## Type `NodeEvents`

The events of one step: a ByteList whose bytes are `NodeEvent` entries one after another.

## Type `NodeEvent`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the event, a multiple of 8 |
| 8 | `kind` | u64 | `NODE_EV_*` |
| 16 | `arg` | u64 | `NODE_EV_TICK`: time_ms; `NODE_EV_BLOCK`: data_available; `NODE_EV_ATTESTATION`: is_from_block; `NODE_EV_P2P`: the libp2p event starts here; `NODE_EV_ENGINE`: 0 bytes, 1 the connection failed |
| 24 | `bytes` | ByteList | `NODE_EV_BLOCK`, `NODE_EV_ATTESTATION`, `NODE_EV_ATTESTER_SLASHING`, `NODE_EV_POW_BLOCK`: the SSZ bytes; `NODE_EV_ENGINE` with arg 0: the bytes of the execution engine's connection; `NODE_EV_ENR`: a node record; offset 24 |

### Rules

- `NODE_EV_TICK`: 24 bytes or more.
- An event with `bytes`: its ByteList's offset is 24 and its bytes end inside the event.
- `NODE_EV_WORK_DONE`: `NODE_EV_WORK_DONE_SIZE` bytes; offsets 16 to 71 are those of the work's `NodeAction`, `result` at `NodeEvent_result`, and a Checkpoint at `NodeEvent_checkpoint` for `LANTERN_NEED_TARGET_STATE`. For `NODE_WORK_SERVE`, and `NODE_WORK_NEW_PAYLOAD` and `NODE_WORK_FORKCHOICE` of `LANTERN_VALID`, a ByteList of the chunk or request at `NodeEvent_chunk`, offset 24, inside the event. For `NODE_WORK_GOSSIP` of a valid beacon_block and `NODE_WORK_SYNC_BLOCK`, its root at `NodeEvent_root` and its blob count at `NodeEvent_index`; of a valid blob_sidecar, its block root at `NodeEvent_root` and its index at `NodeEvent_index`; for `NODE_WORK_BLOB`, its block root at `NodeEvent_root`.
- `NODE_EV_P2P`: a libp2p shell result `Event` from 16, its size a multiple of 8 inside the event; only with `p2p`.
- `NODE_EV_ENGINE`: arg 0 or 1; with 0, the event has `bytes`; only with `NODE_FLAG_ENGINE`.
- `NODE_EV_ENR`: has `bytes`; only with `p2p`.
- `NODE_EV_PAYLOAD_STATUS` is `LANTERN_INVALID_EVENT` in this version: the answers come in `NODE_EV_ENGINE`.

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
| 48 | `data` | u64 | `NODE_ACT_WORK`: a `BufferId` of bytes |
| 56 | `target` | u64 | `NODE_ACT_WORK`: a `NodeBlock` index (also of a SYNC_BLOCK), a `NodeCheckpoint` index, a `NodeBlob` index, a stream Handle, or a message Handle |
| 64 | `arg` | u64 | `NODE_ACT_WORK`: `is_from_block` of an attestation, the epoch of a checkpoint, the protocol version + 256 * the method of a SERVE, topic + 256 * subnet of a GOSSIP, or the JSON-RPC id of a NEW_PAYLOAD or FORKCHOICE |

### Rules

- `NODE_ACT_BYTES_PUT`: keep the ByteList at 24 as the bytes of the id at 16.
- `NODE_ACT_STATE_COPY`: copy the state of the id at 16 as the id at 24.
- `NODE_ACT_STATE_FREE`, `NODE_ACT_BYTES_FREE`: free the id at 16.
- `NODE_ACT_WORK`: `NODE_ACT_WORK_SIZE` bytes; call lantern_node_run.
- `NODE_ACT_P2P_LIST`: a ByteList of libp2p `Action` values from 16, offset 24; do its DIAL, ADOPT, REFUSE, SEND, CLOSE and SEND_DATAGRAM in order, and skip the others.
- `NODE_ACT_DISCV5`: a ByteList at 24, offset 24, of asm-discv5 events: pass them to discv5_step.
- `NODE_ACT_ENGINE`: a ByteList at 24, offset 24: write its bytes to the connection to the execution engine, opening one when there is none, and pass what the engine sends in `NODE_EV_ENGINE` events; a connection that fails or closes before an answer is a `NODE_EV_ENGINE` with arg 1.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_node_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_init`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_copy`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_step`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_run`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_node_protocols`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

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

### `lantern_node_new_payload`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
