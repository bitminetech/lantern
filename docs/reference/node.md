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

### Types

- [`Node`](#type-node): the state of the node.
- [`NodeRoom`](#type-noderoom): the capacities of a `Node`.
- [`NodeBlock`](#type-nodeblock): a block the node knows.
- [`NodeCheckpoint`](#type-nodecheckpoint): a checkpoint state the node keeps.
- [`NodePeer`](#type-nodepeer): a connected libp2p peer.
- [`NodeStream`](#type-nodestream): a req/resp stream a peer opened.
- [`NodeMessage`](#type-nodemessage): a gossip message the node holds.
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
- libp2p's actions go out in a `NODE_ACT_P2P_LIST` action. The shell does its shell requests in order; the node took its application notices.
- The node's queue (`p2p_out`) is one ByteList of libp2p events inside the node. libp2p_step reads it in place.
- A stream carries one request and one answer, as the req/resp functions of [req-resp.md](req-resp.md) encode them.
- lantern_node_size, lantern_node_init, lantern_node_copy, lantern_node_step, lantern_node_run and lantern_node_protocols are in the common object of the core (asm/core/<ISA>/node.s), and each symbol is its name.
- lantern_node_import, lantern_node_block_root, lantern_node_attestation, lantern_node_attester_slashing and lantern_node_gossip are in each fork object (asm/core/<ISA>/nodehooks.s), exported as `lantern_<fork>_<name>`.

## Test vectors

- The fork_choice files of [fork-choice.md](fork-choice.md#test-vectors), a second time, through the node: each case reports a second time with ` (node)` after its name.
  - The runner plays the shell: a table of `BufferId` to buffer, the actions of each step in order, each `NODE_ACT_WORK` run when it comes, its event to the next step, until a step gives no work.
  - Its config sets the epoch of each fork up to the runner's fork to 0 and of each later fork to 2^64 - 1.
  - Each step of the case is events: `tick` a `NODE_EV_TICK`, `block` a `NODE_EV_BLOCK` with the block's data availability, `attestation` a `NODE_EV_ATTESTATION`, `attester_slashing` a `NODE_EV_ATTESTER_SLASHING`, `pow_block` a `NODE_EV_POW_BLOCK`.
  - After a valid block it sends the block's attestations, with `is_from_block` 1, and attester slashings as events of one step.
  - A valid block must be `NODE_BLOCK_IMPORTED`, an invalid block must not. An attestation or slashing is valid when the result of its last work is `LANTERN_VALID`.
  - The checks read the store, the node's `head_root`, and the post-state the node keeps for the head.
  - Cases with `payload_status` steps run only directly.
  - A non-zero status of lantern_node_step or lantern_node_run must leave the node, the store and the work's state byte for byte unchanged.
- Lantern's cases `<preset>-<fork>-node-p2p.bin` of altair to fulu, made by tests/generator/node.py with the pinned spec: an anchor state and block at the first slot of epoch 2, and the Status and MetaData the node answers.
  - The answers come from get_forkchoice_store, get_head and compute_fork_digest of the spec module, with each fork up to the case's at epoch 0 and each later fork at 2^64 - 1.
  - The runner plays the network between the node's libp2p state and a bare asm-libp2p peer, as tests/runner of asm-libp2p does. The peer dials the node and opens one stream for each request.
  - Status (v2 in fulu, v1 before) and MetaData (v3 in fulu, v2 before) must be the case's; Ping must give 0; Goodbye must close with no answer.
  - The node's peer entry must hold the peer's ID and the Status it sent.
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
  - The runner's peer dials the node and sends a Status whose head is the chain's last block; it answers each BeaconBlocksByRange request of the node with the chain's blocks in the range.
  - Each block of the chain must be `NODE_BLOCK_IMPORTED`, and the node's `head_root` must be the chain's last block.

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

- Room: `actions` has the event bytes + 512 per event + 128 per known block + 512 bytes free, and `LIBP2P_ACTIONS_MIN` + 40 more with `p2p`; with `p2p`, `p2p_out` has room for the libp2p events of the `NODE_EV_P2P` events, and `scratch` holds as many bytes again and `LIBP2P_SCRATCH_SIZE`; the blocks part has an entry free per `NODE_EV_BLOCK` and per `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`, and `NODE_SYNC_BATCH` more with `p2p`; the checkpoints part has 2 free per `NODE_EV_WORK_DONE`, and 2; the pow blocks part has an entry free per `NODE_EV_POW_BLOCK`; `scratch` has `LANTERN_SCRATCH_FIXED` + 64 + 16 bytes per store node.
- Before any change: the root of each `NODE_EV_BLOCK`, with lantern_node_block_root of the fork of its slot. A status of that call is the step's.
- `NODE_EV_TICK`: sets `time_ms` of the node, then on_tick of the fork of the new slot.
- `NODE_EV_BLOCK`: for a root the node does not know, a `NODE_ACT_BYTES_PUT` of the bytes and a `NodeBlock` in `NODE_BLOCK_WAITING`. Bytes that are no `SignedBeaconBlock` are dropped.
- A waiting block whose parent is imported: a `NODE_ACT_STATE_COPY` of the parent's post-state and a `NODE_WORK_IMPORT_BLOCK`; the block is `NODE_BLOCK_IMPORTING`. A waiting block whose parent is invalid becomes `NODE_BLOCK_INVALID`.
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
- `STREAM_INBOUND`: a `NodeStream` of the protocol's method and version, or a `STREAM_RESET` when the streams part is full. `STREAM_DATA`: the bytes join the stream's request, or a `STREAM_RESET` when they pass its room. `STREAM_EOF`: the request is complete. `STREAM_RESET`: the stream goes.
- A request is read when its bytes are complete: Status is kept in the `NodePeer` and answered with the node's Status of the same version; Ping is answered with `metadata_seq`; MetaData, on the stream's opening, with the node's MetaData of the same version; Goodbye gets a `STREAM_CLOSE`. A request that is not valid gets result 1, InvalidRequest; a method of no answer below gets result 3, ResourceUnavailable.
- BeaconBlocksByRange: a `start_slot` before `earliest_slot` gets ResourceUnavailable. Otherwise the blocks of the chain of `head_root`, by `parent_root`, with a slot in `start_slot` to `start_slot` + `count`, in slot order; `count` is at most `MAX_REQUEST_BLOCKS_DENEB` from deneb on, else `MAX_REQUEST_BLOCKS`, and at most the BufferIds a stream's request room holds.
- BeaconBlocksByRoot: the imported blocks of the roots the node knows, in the request's order; the request has at most that many roots.
- The anchor, with no bytes, is not sent. No block: a `STREAM_CLOSE` with no chunk. Else the stream keeps the BufferIds and takes `NODE_STREAM_SERVE`.
- After the head, each stream in `NODE_STREAM_SERVE` gets a `NODE_WORK_SERVE` of its next block and takes `NODE_STREAM_SERVING`, while the actions have room for the work and 4096 bytes; a stream left waiting makes `wakeup` the tick's time.
- `NODE_EV_WORK_DONE` of `NODE_WORK_SERVE`: the chunk goes out in a `STREAM_WRITE`, then the stream's next block, or a `STREAM_CLOSE` after the last; a result other than `LANTERN_VALID`, or no room in `p2p_out`, gives a `STREAM_RESET`.
- An answer is one chunk of lantern_reqresp_write_chunk in a `STREAM_WRITE`, then a `STREAM_CLOSE`; then the stream goes.
- The node's Status: compute_fork_digest of the store's epoch, the store's finalized checkpoint, `head_root` and its slot, and `earliest_slot`. Its MetaData: `metadata_seq`, no attestation or sync subnets, and `CUSTODY_REQUIREMENT` custody groups.
- After the head, with `p2p`: a `SUBSCRIBE` of each topic of the fork of the store's epoch at compute_fork_digest of that epoch, once for each digest, when `p2p_out` has 8192 bytes free. The topics: beacon_block, beacon_aggregate_and_proof, voluntary_exit, proposer_slashing and attester_slashing; from altair sync_committee_contribution_and_proof; from capella bls_to_execution_change; in deneb and electra blob_sidecar of each subnet.
- `MESSAGE`: a `MESSAGE_ID` of compute_message_id of the fork of the store's slot, then a `NodeMessage` when the messages part has room. Its data uncompressed with Snappy goes in a `NODE_ACT_BYTES_PUT`, and for a block, a blob sidecar or a column sidecar the slot and parent root of its block header go in the entry. Data that is no Snappy block of at most `MAX_PAYLOAD_SIZE` bytes makes the entry `NODE_MESSAGE_CORRUPT`; data that does not fit in `scratch` or the actions makes it `NODE_MESSAGE_NO_ROOM`.
- `MESSAGE_STATUS` of `LIBP2P_MSG_NEW` for an entry with bytes: a `NODE_WORK_GOSSIP` with the head's post-state, the post-state of the justified root, and for a block, a blob sidecar or a column sidecar whose parent is imported at an earlier slot a `NODE_ACT_STATE_COPY` of the parent's post-state; the entry takes `NODE_MESSAGE_VALIDATING`. With no bytes, or no room in the actions, a `VALIDATION` of `LIBP2P_IGNORE`, or `LIBP2P_REJECT` for `NODE_MESSAGE_CORRUPT`. Any other status: the bytes and the entry go.
- After the subscriptions and the serving, with `p2p`: the response bytes of each stream in `NODE_STREAM_RESPONSE` are read. Then, with no `NODE_FLAG_SYNCING`, a BeaconBlocksByRange (v2 from altair, v1 before) to the first peer with a Status of the node's `fork_digest` whose `head_slot` is at least the start slot: the start slot is the head's slot + 1, or `sync_slot` when that is higher; the count is at most `NODE_SYNC_BATCH` and reaches the peer's `head_slot`; the step is 1. The node takes `NODE_FLAG_SYNCING`, and `sync_slot` becomes the start slot + the count. A response that waits for room makes `wakeup` the tick's time.
- A request of the node: a `NodeStream` in `NODE_STREAM_OPENING` whose list holds the request chunk, its `handle` a tag with bit 63 set, and an `OPEN_STREAM` of the protocol ID. `STREAM_OPENED` of the tag: the stream takes its handle and `NODE_STREAM_RESPONSE`, its request goes in a `STREAM_WRITE` with a `STREAM_CLOSE`, and its list then holds the response. `STREAM_FAILED` of the tag: the stream goes.
- A response chunk is read when its bytes are complete, with a ForkDigest context for BeaconBlocksByRange v2. A Status is kept in the `NodePeer`, as a Status request is. A block of at least 184 and at most `MAX_PAYLOAD_SIZE` bytes, when the actions and the blocks part have room: a `NodeBlock` in `NODE_BLOCK_HASHING` with root 0, the slot and parent root of its bytes and `data_available` 1, a `NODE_ACT_BYTES_PUT` of its bytes, and a `NODE_WORK_SYNC_BLOCK` of its index. The stream goes after a Status chunk, after its last chunk and `STREAM_EOF`, after a chunk whose result is not 0, and with a `STREAM_RESET` after a chunk that is not valid. A stream of the node's BeaconBlocksByRange that goes ends `NODE_FLAG_SYNCING`.
- `NODE_EV_WORK_DONE` of `NODE_WORK_SYNC_BLOCK` for a block in `NODE_BLOCK_HASHING`: `LANTERN_VALID` and a root the node does not know, the block takes the root and `NODE_BLOCK_WAITING`, then imports as a `NODE_EV_BLOCK` does; else `NODE_BLOCK_INVALID` and a `NODE_ACT_BYTES_FREE` of its bytes.
- `NODE_EV_WORK_DONE` of `NODE_WORK_GOSSIP`: a `VALIDATION` of `LIBP2P_ACCEPT` for `LANTERN_VALID`, `LIBP2P_REJECT` for `LANTERN_GOSSIP_REJECT`, else `LIBP2P_IGNORE`; a `NODE_ACT_STATE_FREE` of the proposer state. A valid beacon_block of a root the node does not know keeps its bytes as a `NodeBlock` in `NODE_BLOCK_WAITING` with `data_available` 1, then imports as a `NODE_EV_BLOCK` does. A valid attester_slashing with a justified state keeps its bytes for a `NODE_WORK_ATTESTER_SLASHING` with that state. Else the bytes go. The entry goes.

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

- `NODE_WORK_IMPORT_BLOCK`: lantern_node_import of the fork of the block's slot, with `BlockOptions` of `PAYLOAD_STATUS_VALID` (`PAYLOAD_STATUS_NOT_VALIDATED` with `NODE_FLAG_OPTIMISTIC`) and the block's `data_available`. `LANTERN_NEED_JUSTIFIED_STATE` becomes the result.
- `NODE_WORK_JUSTIFIED_STATE`: lantern_store_justified_checkpoint_state with `state_a`.
- `NODE_WORK_TARGET_STATE`: lantern_store_target_checkpoint_state of `state_a` to the `NodeCheckpoint` at index `target`.
- `NODE_WORK_ATTESTATION`: lantern_node_attestation of the fork of the attestation's slot; `is_from_block` is the work's `arg`.
- `NODE_WORK_ATTESTER_SLASHING`: lantern_node_attester_slashing of the fork of the store's slot.
- `NODE_WORK_SERVE`: the response chunk of the block in `data`, with lantern_reqresp_write_chunk, as a ByteList at `NodeEvent_chunk` of the event; its context bytes are compute_fork_digest of the block's epoch for version 2, none for version 1. The event's `size` then covers the chunk.
- `NODE_WORK_SYNC_BLOCK`: lantern_node_block_root of the fork of the block's slot, its root at `NodeEvent_root`.
- `NODE_WORK_GOSSIP`: lantern_node_gossip of the fork of the store's slot, with a `NodeGossip` of `seen`, the store, `time_ms`, the topic and subnet of `arg`, `state_a` as head, `state_b` as proposer, `state_c` as justified, `settings` and the node's config. The root of a valid beacon_block goes at `NodeEvent_root`.
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
lantern_node_block_root(data, scratch, root, result) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `data` | input | ByteList |
| `scratch` | scratch | `Scratch` |
| `root` | output | Root |
| `result` | output | `Result` |

### Returns

- `LANTERN_OK`: `result` is `LANTERN_VALID` and `root` holds the root, or `result` is `LANTERN_INVALID_ENCODING`.
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
lantern_node_gossip(args, data, scratch, result, root) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `args` | input | `NodeGossip` |
| `data` | input | ByteList: the uncompressed message |
| `scratch` | scratch | `Scratch` |
| `result` | output | `Result` |
| `root` | output | Root |

### Returns

- `LANTERN_OK`: `result` is that of the topic's lantern_validate_<topic>_gossip, `LANTERN_GOSSIP_REJECT` when `data` is no value of the topic's type, or `LANTERN_GOSSIP_IGNORE` for a topic of no type in the fork or a proposer state whose slots do not run.
- `LANTERN_BUFFER_TOO_SMALL`: as the topic's function or lantern_process_slots, or `scratch` cannot hold the decoded value.

### Function does

- The types: beacon_block `SignedBeaconBlock`, beacon_aggregate_and_proof `SignedAggregateAndProof`, beacon_attestation `Attestation` (`SingleAttestation` from electra), voluntary_exit `SignedVoluntaryExit`, proposer_slashing `ProposerSlashing`, attester_slashing `AttesterSlashing`, sync_committee_contribution_and_proof `SignedContributionAndProof`, sync_committee `SyncCommitteeMessage`, bls_to_execution_change `SignedBLSToExecutionChange`, blob_sidecar `BlobSidecar`, data_column_sidecar `DataColumnSidecar`.
- beacon_block, blob_sidecar and data_column_sidecar: lantern_process_slots of the proposer state to the slot of the message's block header, when the state is before it. With no proposer state, the head state is the proposer state.
- Bellatrix beacon_block: the justified state, or the head state with none.
- A valid beacon_block: hash_tree_root of its message in `root`.
- Decodes into the end of `scratch`; the scratch `size` is restored on return.

### ABI

- Export: `lantern_<fork>_node_gossip` of each fork object.

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
| 256 | `config` | `Config` | |

### Rules

- `NODE_FIXED` (256 + `CONFIG_SIZE`) bytes of fixed fields; the parts follow in the order blocks, checkpoints, pow_blocks, peers, streams, messages, p2p_out.
- The capacity of a part is its bytes up to the next part over its entry's bytes; `p2p_out` is the last part.
- `NODE_FLAG_OPTIMISTIC`: blocks are imported as `PAYLOAD_STATUS_NOT_VALIDATED`.
- `NODE_FLAG_JUSTIFIED_PENDING`: a `NODE_WORK_JUSTIFIED_STATE` is queued.
- `NODE_FLAG_SUBSCRIBED`: the topics of `fork_digest` are subscribed.
- `NODE_FLAG_SYNCING`: a BeaconBlocksByRange request of the node is open.

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

## Type `NodeBlock`

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `root` | Root | hash_tree_root of the block |
| 32 | `parent_root` | Root | |
| 64 | `slot` | u64 | |
| 72 | `data_id` | u64 | `BufferId` of the `SignedBeaconBlock`'s SSZ bytes |
| 80 | `state_id` | u64 | `BufferId` of its post-state, 0 until its import is queued |
| 88 | `status` | u64 | `NODE_BLOCK_WAITING`, `NODE_BLOCK_IMPORTING`, `NODE_BLOCK_IMPORTED`, `NODE_BLOCK_INVALID`, or `NODE_BLOCK_HASHING` while a `NODE_WORK_SYNC_BLOCK` of its root is queued (root 0) |
| 96 | `data_available` | u64 | 1 or 0, from its `NODE_EV_BLOCK` |
| 104 | `result` | u64 | The result of its last import |

### Rules

- `NodeBlock__mem` (112) bytes.

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
| 16 | `arg` | u64 | `NODE_EV_TICK`: time_ms; `NODE_EV_BLOCK`: data_available; `NODE_EV_ATTESTATION`: is_from_block; `NODE_EV_P2P`: the libp2p event starts here |
| 24 | `bytes` | ByteList | `NODE_EV_BLOCK`, `NODE_EV_ATTESTATION`, `NODE_EV_ATTESTER_SLASHING`, `NODE_EV_POW_BLOCK`: the SSZ bytes, offset 24 |

### Rules

- `NODE_EV_TICK`: 24 bytes or more.
- An event with `bytes`: its ByteList's offset is 24 and its bytes end inside the event.
- `NODE_EV_WORK_DONE`: `NODE_EV_WORK_DONE_SIZE` bytes; offsets 16 to 71 are those of the work's `NodeAction`, `result` at `NodeEvent_result`, and a Checkpoint at `NodeEvent_checkpoint` for `LANTERN_NEED_TARGET_STATE`. For `NODE_WORK_SERVE`, a ByteList of the chunk at `NodeEvent_chunk`, offset 24, inside the event. For `NODE_WORK_GOSSIP` of a valid beacon_block, its root at `NodeEvent_root`.
- `NODE_EV_P2P`: a libp2p shell result `Event` from 16, its size a multiple of 8 inside the event; only with `p2p`.
- `NODE_EV_PAYLOAD_STATUS` is `LANTERN_INVALID_EVENT` in this version.

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
| 56 | `target` | u64 | `NODE_ACT_WORK`: a `NodeBlock` index (also of a SYNC_BLOCK), a `NodeCheckpoint` index, a stream Handle, or a message Handle |
| 64 | `arg` | u64 | `NODE_ACT_WORK`: `is_from_block` of an attestation, the epoch of a checkpoint, the protocol version of a SERVE, or topic + 256 * subnet of a GOSSIP |

### Rules

- `NODE_ACT_BYTES_PUT`: keep the ByteList at 24 as the bytes of the id at 16.
- `NODE_ACT_STATE_COPY`: copy the state of the id at 16 as the id at 24.
- `NODE_ACT_STATE_FREE`, `NODE_ACT_BYTES_FREE`: free the id at 16.
- `NODE_ACT_WORK`: `NODE_ACT_WORK_SIZE` bytes; call lantern_node_run.
- `NODE_ACT_P2P_LIST`: a ByteList of libp2p `Action` values from 16, offset 24; do its DIAL, ADOPT, REFUSE, SEND, CLOSE and SEND_DATAGRAM in order, and skip the others.

## Results

<!-- CI generates the tick table for each function here. -->
