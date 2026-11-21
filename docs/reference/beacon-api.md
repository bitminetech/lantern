# Beacon API

## Contents

### Functions

- [`lantern_api_route`](#function-lantern_api_route): finds the operation of a request and reads its parameters.
- [`lantern_json_decode`](#function-lantern_json_decode): the SSZ encoding of a value from its JSON, strictly.
- [`lantern_json_encode`](#function-lantern_json_encode): the JSON of an SSZ value, a chunk at a time.
- [`lantern_json_encode_ssz`](#function-lantern_json_encode_ssz): the JSON of an SSZ encoding, a chunk at a time.
- [`lantern_http_request`](#function-lantern_http_request): reads one HTTP/1.1 request, head and body, from a connection's bytes.

### Types

- [`ApiIdentity`](#type-apiidentity): the texts of the node's identity that the shell knows.
- [`ApiRoute`](#type-apiroute): the operation of a request and its parameters.
- [`HttpLimits`](#type-httplimits): the largest request head and body a connection takes.
- [`HttpRequest`](#type-httprequest): one request, read.
- [`JsonCursor`](#type-jsoncursor): where lantern_json_encode goes on.
- [`JsonFault`](#type-jsonfault): why and where lantern_json_decode refused a JSON text.
- [`ValidatorRef`](#type-validatorref): a validator by index or by public key.

## Spec

- Document: [beacon-APIs v4.0.0](https://github.com/ethereum/beacon-APIs/tree/v4.0.0).
- Section: the operations of `beacon-node-oapi.yaml` and `apis/`, with the JSON of `types/`: numbers as decimal strings, byte strings as `0x` and lower case hex; an error body is an `ErrorMessage` of `types/http.yaml`.
- JSON of SSZ values: beacon-APIs `types/primitive.yaml` and the types of each fork: a uint as a decimal string, `Boolean` as `true` or `false`, byte strings and bit strings as `0x` and lower case hex, lists and vectors as arrays, containers as objects of the spec's field names.
- Responses: [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112) section 4 (status line), section 6.3 (an HTTP/1.0 body with no length ends when the connection closes), section 7.1 (chunked transfer coding) and section 9.3 (persistence: an HTTP/1.1 connection stays open unless `close`; an HTTP/1.0 connection closes unless `keep-alive`); [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) section 8.6 (`Content-Length`), section 10.2.1 (`Allow`) and section 15 (status codes and reason phrases).
- Requests: [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112) sections 2 to 7 (message format, request line, fields, body length, chunked coding) and [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) section 5 (field syntax); status 431 of [RFC 6585](https://www.rfc-editor.org/rfc/rfc6585) section 5.
- `Eth-Consensus-Version` on the responses of getBlockV2 and getStateV2: the fork of the block or the state, as beacon-APIs `apis/beacon/blocks/block.v2.yaml` and `apis/debug/state.v2.yaml` require it.
- Routes: the 69 paths and 76 operations of `beacon-node-oapi.yaml` and `apis/` at beacon-APIs v4.0.0 (commit 88fc940), with their parameters of `params/index.yaml` and `apis/`; percent-encoding of [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) section 2.1; `Accept` of RFC 9110 section 12.5.1; `Content-Type` of RFC 9110 section 8.3.

## Common rules

The answers of the node (node.md, `NODE_EV_API`) follow these rules.

- The response in one piece:
  - The status line: `HTTP/1.1`, a space, the code in decimal, a space, its reason phrase, CRLF.
  - `Content-Type: application/json` CRLF, when it has a body.
  - `Content-Length: ` and the body's bytes in decimal, CRLF; `0` with no body.
  - With 405: `Allow: ` and the methods of `allow`, `GET`, `POST` or `GET, POST`, CRLF.
  - `Connection: close` CRLF when the connection closes after it; `Connection: keep-alive` CRLF when an HTTP/1.0 request keeps it open.
  - CRLF, then the body.
- The connection closes after the response when the request has `close`, or when lantern_http_request found it faulty.
- Reason phrases: 200 `OK`, 202 `Accepted`, 206 `Partial Content`, 400 `Bad Request`, 404 `Not Found`, 405 `Method Not Allowed`, 406 `Not Acceptable`, 413 `Content Too Large`, 414 `URI Too Long`, 415 `Unsupported Media Type`, 431 `Request Header Fields Too Large`, 500 `Internal Server Error`, 501 `Not Implemented`, 503 `Service Unavailable`, 505 `HTTP Version Not Supported`. The code of getHealth's `syncing_status` has none: the line ends with the space after the code.
- An error is a status of 400 or more. Its body is `{"code":<code>,"message":"<message>"}`, with the code in decimal and the message of its status: 400 `BAD_REQUEST`, 404 `NOT_FOUND`, 405 `METHOD_NOT_ALLOWED`, 406 `NOT_ACCEPTABLE`, 413 `CONTENT_TOO_LARGE`, 414 `URI_TOO_LONG`, 415 `UNSUPPORTED_MEDIA_TYPE`, 431 `REQUEST_HEADER_FIELDS_TOO_LARGE`, 500 `INTERNAL_SERVER_ERROR`, 501 `NOT_IMPLEMENTED`, 503 `SERVICE_UNAVAILABLE`, 505 `HTTP_VERSION_NOT_SUPPORTED`.
- JSON has no white space and the fields in the order below. A number is a decimal string, a byte string `0x` and lower case hex, a text its bytes in quotes, a flag `true` or `false`.
- The values:
  - `genesis_time`: the store's `genesis_time_ms` / 1000.
  - `genesis_validators_root`: the node's. `genesis_fork_version`: `GENESIS_FORK_VERSION` of the node's config.
  - The head: the `NodeBlock` of `head_root`. `head_slot`: its slot. `is_optimistic`: its `payload_status` is `PAYLOAD_STATUS_NOT_VALIDATED`.
  - `current_slot`: the store's slot. `is_syncing`: `NODE_FLAG_SYNCING`. `el_offline`: `NODE_FLAG_EL_OFFLINE`.
  - `connected`: the `NodePeer` entries.
  - The MetaData: `seq_number` the node's `metadata_seq`; `attnets` the 8 bytes of the node's `attnets` (bit i of byte i / 8 for subnet i); from altair `syncnets` 1 zero byte; from fulu `custody_group_count` the node's custody group count (node.md, `Node`: `NUMBER_OF_CUSTODY_GROUPS` with `NODE_FLAG_SUPERNODE`, else `CUSTODY_REQUIREMENT` of the node's config). The fork is that of the store's slot.
  - The texts: the node's `api_identity`, from the last `NODE_EV_API_IDENTITY`; each is empty before one.
- getHealth: no body. 200; 206 when `is_syncing`, `is_optimistic` or `el_offline`; and then, with `syncing_status`, that code in place of 206.
- getNetworkIdentity: `{"data":{"peer_id":…,"enr":…,"p2p_addresses":[…],"discovery_addresses":[…],"metadata":{"seq_number":…,"attnets":…,"syncnets":…,"custody_group_count":…}}}`. Each address list holds its text, or nothing when the text is empty.
- getNodeVersion: `{"data":{"version":…}}`.
- getSyncingStatus: `{"data":{"head_slot":…,"sync_distance":…,"is_syncing":…,"is_optimistic":…,"el_offline":…}}`; `sync_distance` is `current_slot` minus `head_slot`, or 0 when it is below.
- getPeerCount: `{"data":{"disconnected":"0","connecting":"0","connected":…,"disconnecting":"0"}}`.
- getPeers: `{"data":[<peer>,…],"meta":{"count":…}}`, each `NodePeer` in order whose state, `connected`, is in the `state` set and whose direction is in the `direction` set, of the sets given; `count` the items, a JSON number.
- getPeer: the `NodePeer` whose `peer_id` text is the route's `peer_id`: `{"data":<peer>}`; with none, 404.
- A peer: `{"peer_id":…,"enr":null,"last_seen_p2p_address":…,"state":"connected","direction":…}`.
  - `peer_id`: base58btc of its peer ID.
  - `last_seen_p2p_address`: the multiaddr of its connection's address: `/ip4/` and the 4 bytes in decimal with `.` between, or `/ip6/` and the 8 groups of 16 bits in lower case hex with no leading zeros and `:` between; then `/tcp/` and the port for TCP, or `/udp/`, the port and `/quic-v1` for QUIC; then `/p2p/` and its `peer_id`.
  - `direction`: `inbound` or `outbound`.
- getGenesis: `{"data":{"genesis_time":…,"genesis_validators_root":…,"genesis_fork_version":…}}`.
- getDebugChainHeadsV2: `{"data":[{"root":…,"slot":…,"execution_optimistic":…},…]}`, the leaves of the fork choice tree: each node of the store's `blocks`, in their order, that no node names as its `parent`. A node whose payload is `INVALIDATED`, and each node below it, is out of the tree (fork-choice.md, optimistic sync: removed from fork choice). `execution_optimistic`: its `payload_status` is `NOT_VALIDATED`.
- getDebugForkChoice: `{"justified_checkpoint":…,"finalized_checkpoint":…,"fork_choice_nodes":[…]}`, the store's checkpoints and each node of its `blocks`, in their order: `{"slot":…,"block_root":…,"parent_root":…,"justified_epoch":…,"finalized_epoch":…,"weight":…,"validity":…,"execution_block_hash":…}`.
  - `justified_epoch` and `finalized_epoch`: the epochs of `current_justified_checkpoint` and `finalized_checkpoint` of the block's post-state (`BlockNode.justified_checkpoint`, `BlockNode.finalized_epoch`).
  - `weight`: get_weight of the node (fork-choice.md, lantern_get_weight), from lantern_node_weights.
  - `validity`: `valid`, `invalid` or `optimistic` for a `payload_status` of `VALID`, `INVALIDATED` or `NOT_VALIDATED`.
  - `execution_block_hash`: `BlockNode.block_hash`, zero before bellatrix.
  - The error 500 when lantern_node_weights fails, as when the store's balances are not those of its justified checkpoint.
- getSpec: `{"data":{…}}`, the keys and values of the node's config, the preset and the spec's constants:
  - Each key of `CONFIG_KEYS` and `BLOB_SCHEDULE`, in the order of the pinned configs/<preset>.yaml, with the node's values; and `SECONDS_PER_SLOT`, `SLOT_DURATION_MS` / 1000, right before `SLOT_DURATION_MS`, the key clients and tools read from configs before the spec gave the slot in milliseconds.
  - Then each key of the pinned presets/<preset>/phase0.yaml to fulu.yaml, in file order.
  - Then each row of the Constants tables of beacon-chain.md of phase0 to fulu, in table order.
  - Values: a number in quotes, decimal; a Version, a DomainType, a Hash32, an Address and other byte strings `0x` and lower case hex; a text in quotes; `BLOB_SCHEDULE` `[{"EPOCH":…,"MAX_BLOBS_PER_BLOCK":…},…]` in the config's order; a list of numbers `[…]`, each a number in quotes.
- getForkSchedule: `{"data":[{"previous_version":…,"current_version":…,"epoch":…},…]}`: phase0, with `GENESIS_FORK_VERSION` as both versions and epoch 0; then each fork from altair to fulu whose epoch in the node's config is below 2^64 - 1, with the version of the fork before it in the list as `previous_version`.
- getDepositContract: `{"data":{"chain_id":…,"address":…}}`: `DEPOSIT_CHAIN_ID` and `DEPOSIT_CONTRACT_ADDRESS` of the node's config.
- The block of a `block_id`, on the chain: the head's `NodeBlock` and its ancestors by `parent_root` among the node's imported blocks, then, below the lowest of them, the blocks of the `Db`:
  - `head`: the head. `finalized`: the block of the store's finalized checkpoint root. `genesis`: as the slot 0.
  - A slot: the block of that slot on the chain; none for a slot with no block on the chain, or past the head's slot.
  - A root: the node's imported block of that root, on the chain or not; else the `Db`'s block of that root.
  - None: 404.
  - `canonical`: the block is on the chain. `finalized`: on the chain, at most at the slot of the block of the store's finalized checkpoint root. `execution_optimistic`: its `payload_status` is `PAYLOAD_STATUS_NOT_VALIDATED`; false for a block of the `Db`.
  - Its bytes: those of its `NodeBlock`, or its `Db` record; the anchor's block has none until the backfill takes it.
- The state of a `state_id`: a state the node keeps, at a slot:
  - `head`: the head's post-state, at the head's slot. `genesis`: as the slot 0.
  - `finalized` and `justified`: the store's finalized checkpoint, or its current justified checkpoint: the state of its `NodeCheckpoint` when the node keeps one, else the post-state of the block of its root, at the first slot of its epoch.
  - A slot: the post-state of the block of the chain at or below that slot, at that slot; none past the store's slot.
  - A root: the slot of the chain whose state has that root: the head's post-state's own hash_tree_root, or an entry of its `state_roots`, for the slots from the head's slot - `SLOTS_PER_HISTORICAL_ROOT` to the head's; then as that slot. A root of none of them: 404.
  - A block above F's slot with no post-state gets it again first (node.md, the rebuild); a block at or below F's slot with none: 404.
  - None: 404.
  - At a slot past the post-state's: a copy of it, across the fork boundaries to that slot (node.md, the crossing), then process_slots to that slot.
  - `finalized`: its slot is at most the first slot of the epoch of the store's finalized checkpoint. `execution_optimistic`: that of the block of its post-state or checkpoint.
- getBlockRoot: the block of `block_id`: `{"execution_optimistic":…,"finalized":…,"data":{"root":…}}`.
- getBlockHeader: the block of `block_id`.
  - The header: lantern_node_block_header of the block's bytes. With none, the `latest_block_header` of its post-state, with the post-state's hash_tree_root as `state_root` when that is zero, and a zero signature; with no post-state either, 404.
  - `{"execution_optimistic":…,"finalized":…,"data":{"root":…,"canonical":…,"header":{"message":{"slot":…,"proposer_index":…,"parent_root":…,"state_root":…,"body_root":…},"signature":…}}}`.
- getBlockV2: the bytes of the block of `block_id`; with none, 404.
- getBlockHeaders: `{"execution_optimistic":…,"finalized":…,"data":[…]}`, an item for each block of the query, each the `data` of getBlockHeader of that block, `{"root":…,"canonical":…,"header":…}`, with `,` between.
  - The query: its `slot` and its `parent_root`, of those given; with neither, the head's slot as `slot`.
  - First, with `NODE_FLAG_DB`, the `Db`'s block C of the query, when one is there:
    - With `parent_root` R: R the root of the node's imported block on the chain, or of the `Db`'s block, at slot r; C the block of the first slot above r whose block is in the `Db`, while the slots are below the lowest block of the chain the node keeps; with `slot`, only when C's slot is `slot`.
    - With `slot` alone: the `Db`'s block of `slot`, when `slot` is below the lowest block of the chain the node keeps.
  - Then each of the node's imported blocks, in the order of their `NodeBlock` entries, of the slot `slot` and the `parent_root` `parent_root`, of those given; a block with no bytes and no post-state is left out.
  - `execution_optimistic`: true when an item's block is optimistic; `finalized`: true when the answer has an item and each item's block is finalized; each as getBlockHeader gives them.
  - Streamed, an item a chunk: the items' blocks are each a block's bytes.
- getBlindedBlock: the block of `block_id` blinded (lantern_node_blinded_block; with none, 404): `Eth-Consensus-Version` and `version` the fork of the block's slot, `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":<SignedBlindedBeaconBlock>}`, or with an SSZ `response` its SSZ bytes. From bellatrix the `SignedBlindedBeaconBlock` of the fork (include/types.inc), whose body has the `ExecutionPayloadHeader` of the block's payload in its place; before bellatrix the block itself, as the spec's `Phase0.SignedBeaconBlock` and `Altair.SignedBeaconBlock` answers. Streamed, as getBlockV2.
- getBlockAttestationsV2: the `attestations` of the body of the block of `block_id` (with none, 404): `Eth-Consensus-Version` and `version` the fork of the block's slot, `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[…]}`, the JSON of the fork's `Attestations` list (include/descriptors.inc). Streamed, as getBlockV2. JSON only: the spec gives no SSZ answer.
- getStateRoot: the hash_tree_root of the state of `state_id`: `{"execution_optimistic":…,"finalized":…,"data":{"root":…}}`.
- getStateFork: the `fork` of the state of `state_id`: `{"execution_optimistic":…,"finalized":…,"data":{"previous_version":…,"current_version":…,"epoch":…}}`.
- getStateFinalityCheckpoints: lantern_node_state_checkpoints of the state of `state_id`: `{"execution_optimistic":…,"finalized":…,"data":{"previous_justified":{"epoch":…,"root":…},"current_justified":{…},"finalized":{…}}}`.
- getStateRandao: lantern_node_randao of the state of `state_id` and `epoch` (the state's epoch when not given): `{"execution_optimistic":…,"finalized":…,"data":{"randao":…}}`. An epoch whose mix the state does not hold: 400.
- getEpochSyncCommittees: lantern_node_sync_committee of the state of `state_id` and `epoch` (the state's epoch when not given): `{"execution_optimistic":…,"finalized":…,"data":{"validators":[<index>,…],"validator_aggregates":[[<index>,…],…]}}`, the members' indices in order, then SYNC_COMMITTEE_SUBNET_COUNT slices of SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT of them, the subcommittees of the sync_committee_{subnet_id} topics. A state before altair, or an epoch of neither the state's sync committee period nor the next: 400.
- getPendingDeposits, getPendingPartialWithdrawals and getPendingConsolidations: the state's `pending_deposits`, `pending_partial_withdrawals` or `pending_consolidations` (lantern_node_pending): `Eth-Consensus-Version` and `version` the fork of the state's slot, `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[<item>,…]}`; with an SSZ `response`, the SSZ bytes of the list. Streamed, as getStateValidators: a list may hold millions of items. A state before electra: 400 (the spec's description).
- getProposerLookahead: lantern_node_proposer_lookahead of the state of `state_id`: `Eth-Consensus-Version` and `version` the fork of the state's slot, `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[<index>,…]}`; with an SSZ `response`, the SSZ bytes of the `List[ValidatorIndex, (MIN_SEED_LOOKAHEAD + 1) * SLOTS_PER_EPOCH]` of them. A state before fulu: 400 (the spec's description).
- getStateV2: the SSZ bytes of the state of `state_id`, by lantern_node_state_bytes.
- The answer of getBlockV2 and getStateV2 is streamed (node.md, `NodeApi`): it goes in chunks, from the SSZ bytes of the block or the state.
  - The fork: that of the slot of the block or the state, by its name: `phase0`, `altair`, `bellatrix`, `capella`, `deneb`, `electra` or `fulu`.
  - After the status line: `Content-Type: application/octet-stream` CRLF for SSZ (`response` `API_TYPE_SSZ`), else `Content-Type: application/json` CRLF; `Eth-Consensus-Version: ` and the fork's name, CRLF; then `Content-Length`, `Transfer-Encoding: chunked` CRLF, or neither, as below; then `Connection` as for a response in one piece; CRLF.
  - SSZ: `Content-Length` of the SSZ bytes; the body is the bytes.
  - JSON: the body is `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":<data>}`, its data the JSON of the SSZ bytes by lantern_json_encode_ssz with the fork's `SignedBeaconBlock` or `BeaconState`; the values those of the block or the state.
  - JSON whose whole body is in the first chunk: `Content-Length`. Else, over HTTP/1.1, `Transfer-Encoding: chunked`: each chunk of the stream holds the body's bytes in one chunk of RFC 9112 section 7.1, its size in 4 lower case hex digits, CRLF, the bytes, CRLF; the last also `0` CRLF CRLF. Over HTTP/1.0, neither field and `Connection: close`: the connection closes after the body.
- getBlobSidecars and getDebugDataColumnSidecars: the sidecars of the block of `block_id` (with none, 404) that the node holds, in index order, of the `indices` given (an index below 128; others match none): its `NodeBlob` entries of the block's root in `NODE_BLOB_VALID`, else, with `NODE_FLAG_DB`, the `Db`'s sidecar records of the block's slot.
  - getBlobSidecars: a block whose slot's fork is deneb or electra, its `BlobSidecar` items; another: 400 (the spec's versions: deneb and electra). getDebugDataColumnSidecars: a block whose slot's fork is fulu or later, its `DataColumnSidecar` items; another: 400 (the spec's version: fulu).
  - Streamed, as getStateV2, with `Eth-Consensus-Version`: the JSON body is `{"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[<the items, with , between>]}`, each item the JSON of its SSZ bytes by lantern_json_encode_ssz with the fork's type, the values those of the block; the SSZ body the items' SSZ bytes, one after another. An SSZ body takes `Content-Length` when it is whole in the first chunk, else the coding of a JSON body that is not.
- The light client data (light-client.md, the `LcStore` of the node, node.md): getLightClientBootstrap, getLightClientUpdatesByRange, getLightClientFinalityUpdate and getLightClientOptimisticUpdate, from altair.
  - getLightClientBootstrap: the `LightClientBootstrap` of `block_root` that the store holds (an epoch boundary block it finalized, or the anchor's block); with none, 404 `{"code":404,"message":"NOT_FOUND"}`. getLightClientFinalityUpdate and getLightClientOptimisticUpdate: the store's latest finality update, or its optimistic update; with none, 404.
  - These three: `Eth-Consensus-Version` the object's fork (that of its `attested_header.beacon.slot`, a bootstrap's `header.beacon.slot`); JSON `{"version":"<fork>","data":<data>}`, the data the JSON of its SSZ bytes by lantern_json_encode_ssz with the fork's type; SSZ its bytes.
  - getLightClientUpdatesByRange: the store's best update of each period from `start_period`, at most the lower of `count` and `MAX_REQUEST_LIGHT_CLIENT_UPDATES`: from the earliest it holds in that range, in period order, up to the first period of none (the spec: at least the earliest known result, in consecutive order). JSON: `[{"version":"<fork>","data":<data>},…]`. SSZ: for each, its `response_chunk_len` (u64 little endian: 4 + its bytes), its context compute_fork_digest of the epoch of its `attested_header.beacon.slot`, then its SSZ bytes. One answer with `Content-Length` and no `Eth-Consensus-Version`: at most `MAX_REQUEST_LIGHT_CLIENT_UPDATES` updates.
- getBlobs: the blobs of the block of `block_id` (with none, 404), in the order of its `blob_kzg_commitments`; with `versioned_hashes` items, only each blob whose commitment's kzg_commitment_to_versioned_hash (deneb beacon-chain.md) is an item.
  - A block whose slot's fork is before deneb: no blob.
  - Deneb and electra: the `blob` of each sidecar of the block that the node holds, as getBlobSidecars finds them, in index order.
  - Fulu and later: blob i is cell i of each of the columns 0 to `NUMBER_OF_COLUMNS` / 2 - 1, in column order, from the column sidecars the node holds, as getDebugDataColumnSidecars finds them; the count of blobs is the count of the sidecars' `kzg_commitments`.
  - The first half of the cells of an extended blob is the blob. asm-crypto kzg-cells.md: the extended blob holds the values of the blob's polynomial at the 8192-th roots of unity in bit-reversed order, so its first 4096 values are those at the 4096-th roots, in bit-reversed order: the blob's.
  - A fulu block with no column sidecar the node holds: no blob. With some, but not each of the columns 0 to `NUMBER_OF_COLUMNS` / 2 - 1: 404.
  - A supernode (`NODE_FLAG_SUPERNODE`, app.md `--supernode`) holds every column of the blocks it imports. Another node holds the columns of max(`SAMPLES_PER_SLOT`, `CUSTODY_REQUIREMENT`) custody groups, under half of them, so recover_cells_and_kzg_proofs (fulu das-core.md), which needs half, cannot rebuild a blob. The spec asks for blobs from supernodes only.
  - Streamed, as getStateValidators, with no `Eth-Consensus-Version`: the JSON body is `{"execution_optimistic":…,"finalized":…,"data":[<the blobs, with , between>]}`, each blob `"0x"` and the lower case hex of its bytes in quotes; the SSZ body the blobs back to back, the bytes of `List[Blob, MAX_BLOB_COMMITMENTS_PER_BLOCK]`. `execution_optimistic` and `finalized` of the block, as getBlobSidecars. An SSZ body takes `Content-Length` when it is whole in the first chunk, else the coding of a JSON body that is not.
- The validators of the state of `state_id`: getStateValidators, postStateValidators, getStateValidator, getStateValidatorBalances, postStateValidatorBalances and postStateValidatorIdentities.
  - A validator's status at the epoch of the state's slot: the first that holds of `withdrawal_done` (`withdrawable_epoch` at most the epoch, `effective_balance` 0), `withdrawal_possible` (`withdrawable_epoch` at most the epoch), `exited_slashed` and `exited_unslashed` (`exit_epoch` at most the epoch; `slashed` or not), `active_slashed` and `active_exiting` (`activation_epoch` at most the epoch, `exit_epoch` below `FAR_FUTURE_EPOCH`; `slashed` or not), `active_ongoing` (`activation_epoch` at most the epoch), `pending_initialized` (`activation_eligibility_epoch` `FAR_FUTURE_EPOCH`), else `pending_queued`. These are the conditions of the validator status page that beacon-APIs `ValidatorStatus` names; the page calls the balance of the two withdrawal statuses `balance`, and Lighthouse v8.3.3 reads `effective_balance` there, as lantern does.
  - The validators that answer, in index order, each once: with no `id` item, every validator of the state; else each whose index is an index item or whose `pubkey` is a public key item. With `status` bits, only those whose status has its bit.
  - An item of getStateValidators and postStateValidators: `{"index":…,"balance":…,"status":"<status>","validator":<the JSON of the Validator>}`, `balance` the validator's entry of `balances`. Of the two balance operations: `{"index":…,"balance":…}`. Of postStateValidatorIdentities: `{"index":…,"pubkey":…,"activation_epoch":…}`.
  - getStateValidator: the validator of `validator_id`, as an item of getStateValidators: `{"execution_optimistic":…,"finalized":…,"data":<item>}`; with none, 404.
  - The other five are streamed, as getStateV2 but with no `Eth-Consensus-Version`: the JSON body is `{"execution_optimistic":…,"finalized":…,"data":[<the items, with , between>]}`, the values those of the state.
  - postStateValidatorIdentities as SSZ: `Content-Length` of 64 bytes for each item: its index (u64), `pubkey`, and `activation_epoch` (u64), in order, as Lighthouse v8.3.3 writes its `Vec<ValidatorIdentityData>`; the spec names no type.
- getEpochCommittees: the committees of the state of `state_id`.
  - The epoch: `epoch`, else that of the state's slot. 400 when it is above the state's epoch + 1, or when epoch - MIN_SEED_LOOKAHEAD - 1 (0 when below) is below the state's epoch + 1 - EPOCHS_PER_HISTORICAL_VECTOR (0 when below), so that the RANDAO mix of its seed is not in the state. Lighthouse v8.3.3 gives 400 for both (`CommitteeCache::initialized`).
  - With `slot`, 400 when the slot is not of the epoch. With `index`, 400 when it is get_committee_count_per_slot of the state and the epoch, or more. The checks go in that order.
  - An item for each slot of the epoch (or `slot`), in order, and in each for each index from 0 below get_committee_count_per_slot (or `index`): `{"index":…,"slot":…,"validators":[…]}`, the members of get_beacon_committee of the state, the slot and the index, in order.
  - Streamed, as getStateValidators: `{"execution_optimistic":…,"finalized":…,"data":[<the items, with , between>]}`, the values those of the state.
- getBlockRewards and getSyncCommitteeRewards: the proposer's and the sync committee's rewards of the block of `block_id`. The spec describes the fields only; these values are those of process_block of the block's fork, as Lighthouse v8.3.3 reads them (beacon_block_reward.rs, sync_committee_rewards.rs).
  - The block: as for getBlockV2; with none, or with no bytes, 404.
  - The pre-state P: the post-state of the node's `NodeBlock` of the block's `parent_root`, brought to the block's slot as a lookup brings a state (node.md, the crossing, then process_slots). No such parent, or one with no post-state: 404, as Lighthouse v8.3.3 answers when the parent's state is not available.
  - `execution_optimistic` and `finalized`: those of the block, as for getBlockHeader.
- getBlockRewards: `{"execution_optimistic":…,"finalized":…,"data":{"proposer_index":…,"total":…,"attestations":…,"sync_aggregate":…,"proposer_slashings":…,"attester_slashings":…}}`, in Gwei.
  - `proposer_index`: the block's.
  - `proposer_slashings`: for each proposer slashing of the body, the `whistleblower_reward` of its slash_validator: its validator's `effective_balance` in P // `WHISTLEBLOWER_REWARD_QUOTIENT` (`WHISTLEBLOWER_REWARD_QUOTIENT_ELECTRA` from electra). slash_validator with no whistleblower pays the proposer all of it.
  - `attester_slashings`: the same for each validator that process_attester_slashing slashes: of the sorted intersection of the attesting indices of the slashing's two attestations, each that is slashable (is_slashable_validator at the epoch of P) and that no earlier slashing of the body slashed. Lighthouse v8.3.3 counts a validator that an earlier slashing of the same body slashed once more; process_block pays it once.
  - `sync_aggregate`: from altair, the count of the set `sync_committee_bits` of the body times the `proposer_reward` of process_sync_aggregate at P; 0 before altair.
  - `attestations`, from altair: the sum of process_attestation's `proposer_reward` at P for each attestation of the body in order: `proposer_reward_numerator` // ((`WEIGHT_DENOMINATOR` - `PROPOSER_WEIGHT`) * `WEIGHT_DENOMINATOR` // `PROPOSER_WEIGHT`), with each flag an earlier attestation of the body set counted as set.
  - `attestations`, in phase0: the proposer rewards of get_inclusion_delay_deltas for the attestations of the body, paid by the process_epoch at the end of the epoch after the attestation's target epoch.
    - The state E of an attestation of target epoch t: that of the chain at the last slot of epoch t + 1, as for a `state_id` of that slot, and past the store's slot too: the head's post-state brought to it, as Lighthouse v8.3.3 `state_at_slot` does. With none: 404 (the spec: "required state not found").
    - An E whose fork is altair or later: no reward. The upgrade turns those attestations into participation flags (altair fork.md, translate_participation).
    - For each attesting index of the attestation (get_attesting_indices at P), the first time it is one of an attestation of that target epoch in the body: get_base_reward(E, index) // `PROPOSER_REWARD_QUOTIENT`, when the validator is not slashed in E and no attestation of E's `previous_epoch_attestations` with a lower `inclusion_delay` has the index among its attesting indices.
    - Lighthouse v8.3.3 pays a validator once in a body across both target epochs; get_inclusion_delay_deltas of each epoch pays the proposer for each.
  - `total`: the sum of the four.
- getSyncCommitteeRewards: the balance changes of process_sync_aggregate at P for the body's `sync_aggregate`. A block before altair: 400; it has no sync aggregate.
  - The places: for each pubkey of P's `current_sync_committee`, in order, the index of the validator with that pubkey, as process_sync_aggregate finds them.
  - From the balances of P, in place order: a place whose bit is set adds `participant_reward` to its validator and `proposer_reward` to the proposer; another takes `participant_reward` from its validator, down to 0 at the least (decrease_balance). `participant_reward` and `proposer_reward` are those of process_sync_aggregate at P.
  - A member's reward: its balance after the places less its balance in P; for the proposer, less the proposer rewards it took. Lighthouse v8.3.3 starts from the balances of P, before the other changes of process_block.
  - The items: each member once, in validator index order; with `id` items, each member whose index or `pubkey` is an item.
  - `{"execution_optimistic":…,"finalized":…,"data":[{"validator_index":…,"reward":…},…]}`; `reward` a signed decimal in a string, with `-` before a value below 0.
- getAttestationsRewards: the rewards and penalties process_rewards_and_penalties pays for the attestations of `epoch`. The spec describes the fields only; these values are those of process_epoch of the fork of S, as Lighthouse v8.3.3 reads them (attestation_rewards.rs).
  - The state S: that of the chain at the last slot of `epoch` + 1, as for a `state_id` of that slot; none (past the store's slot): 404. On a copy of it, process_justification_and_finalization, and from altair process_inactivity_updates: the steps of process_epoch before process_rewards_and_penalties.
  - `execution_optimistic` and `finalized`: those of S, as for a state read.
  - `ideal_rewards`: an item for each effective balance from `EFFECTIVE_BALANCE_INCREMENT` to the largest of the fork of `epoch` (`MAX_EFFECTIVE_BALANCE`; `MAX_EFFECTIVE_BALANCE_ELECTRA` from electra), in steps of `EFFECTIVE_BALANCE_INCREMENT`, ascending: `{"effective_balance":…,"head":…,"target":…,"source":…,"inactivity":…}`, with `"inclusion_delay":…` after `source` when S is of phase0. The values of a validator of that effective balance that voted for all three, in time:
    - From altair: each flag's reward of get_flag_index_deltas: base_reward (the effective balance // `EFFECTIVE_BALANCE_INCREMENT` * get_base_reward_per_increment(S)) * the flag's weight * unslashed_participating_increments // (active_increments * `WEIGHT_DENOMINATOR`); 0 in an inactivity leak (is_in_inactivity_leak). `inactivity` 0.
    - Phase0: base_reward, the effective balance * `BASE_REWARD_FACTOR` // integer_squareroot(get_total_active_balance(S)) // `BASE_REWARDS_PER_EPOCH`. head, target and source: the reward of get_attestation_component_deltas of an unslashed attester, with the attesting balance of the matching head, target or source attestations of the previous epoch: base_reward in an inactivity leak (get_finality_delay above `MIN_EPOCHS_TO_INACTIVITY_PENALTY`), else base_reward * (attesting_balance // `EFFECTIVE_BALANCE_INCREMENT`) // (get_total_active_balance(S) // `EFFECTIVE_BALANCE_INCREMENT`). inclusion_delay: base_reward - get_proposer_reward, the attester's part at a delay of 1. inactivity: in a leak, -(`BASE_REWARDS_PER_EPOCH` * base_reward - get_proposer_reward); else 0.
  - `total_rewards`: an item for each validator: `{"validator_index":…,"head":…,"target":…,"source":…,"inactivity":…}`, with `"inclusion_delay":…` after `source` when S is of phase0.
    - head, target and source: the validator's reward less its penalty of get_flag_index_deltas of the flag (from altair); of get_head_deltas, get_target_deltas and get_source_deltas (phase0).
    - inactivity: minus its penalty of get_inactivity_penalty_deltas.
    - inclusion_delay (phase0): its reward of get_inclusion_delay_deltas as an attester, (base_reward - get_proposer_reward) // the inclusion delay of its earliest attestation; the proposer rewards it takes as a proposer are not part of it.
    - The validators: with no `id` item, each of get_eligible_validator_indices(S), in index order; else each validator of S whose index or `pubkey` is an item, in index order, each once, all its values 0 when it is not eligible.
  - Each value a signed decimal in a string, `-` before a value below 0.
  - Streamed, as getStateValidators: `{"execution_optimistic":…,"finalized":…,"data":{"ideal_rewards":[…],"total_rewards":[…]}}`.
- getProposerDuties: the proposers of `epoch`.
  - 503 while the node syncs (`is_syncing`), beacon-APIs `CurrentlySyncing`; Lighthouse v8.3.3 refuses its duty operations then too.
  - 400 for an epoch above the epoch of `current_slot` + 1.
  - The state: that of the chain at the epoch's first slot, as for a `state_id` of that slot; a first slot past the store's slot (the next epoch) takes the head's post-state brought to it. With none: 404, as Lighthouse v8.3.3 answers when its state lookup of the slot finds none.
  - `{"dependent_root":…,"execution_optimistic":…,"data":[…]}`, `execution_optimistic` that of the state; for each slot s of the epoch, in order, `{"pubkey":…,"validator_index":…,"slot":…}` of get_beacon_proposer_index of the state at s: from fulu `proposer_lookahead[s % SLOTS_PER_EPOCH]`; before, compute_proposer_index of the epoch's active validators with sha256(get_seed(state, epoch, DOMAIN_BEACON_PROPOSER) + uint_to_bytes(s)). These hold for any s of the epoch from the state at its first slot.
  - `dependent_root`: get_block_root_at_slot(state, the first slot - 1); for epoch 0, the genesis block's root, hash_tree_root of the state's `latest_block_header` with the state's hash_tree_root as its `state_root`.
- produceAttestationData: the `AttestationData` of `slot` and `committee_index` (phase0 validator.md, Attestation data).
  - 503 while the node syncs (`is_syncing`), as getProposerDuties; 400 for a `slot` past `current_slot`.
  - The state: that of the chain at `slot`, as for a `state_id` of that slot; a `slot` at or past the head's takes the head's post-state brought to it, the spec's `head_state` processed through the empty slots to the assigned slot. With none: 400, as the spec lists no 404.
  - 503 when the state's block is optimistic (`execution_optimistic`), as the spec's description asks.
  - `slot`; `index`: `committee_index` before electra, 0 from electra (electra validator.md); `beacon_block_root`: hash_tree_root of the state's `latest_block_header` with the state's hash_tree_root as `state_root` when it is zero; `source`: the state's `current_justified_checkpoint`; `target`: the epoch of `slot`, and the spec's `epoch_boundary_block_root`, the block root when `slot` is the epoch's first slot, else get_block_root(state, epoch).
  - JSON `{"data":{"slot":…,"index":…,"beacon_block_root":…,"source":…,"target":…}}`; with SSZ by `Accept`, the 128 bytes of its SSZ encoding with `Content-Type: application/octet-stream`. No `Eth-Consensus-Version`: the spec lists no header for it.
- getAttesterDuties: the committee assignments in `epoch` of the validators of the body (phase0 validator.md, get_committee_assignment).
  - 503 while the node syncs, as getProposerDuties; 400 for an epoch above the epoch of `current_slot` + 1; 400 for a body of no item, or with an item that is a public key: the spec's body is an array of at least one validator index.
  - The state: as for getProposerDuties, that of the epoch's first slot; with none, 400, as the spec lists no 404.
  - `{"dependent_root":…,"execution_optimistic":…,"data":[…]}`, `execution_optimistic` that of the state; for each item of the body in order whose validator has an assignment in the epoch, `{"pubkey":…,"validator_index":…,"committee_index":…,"committee_length":…,"committees_at_slot":…,"validator_committee_index":…,"slot":…}`: the member's place in the committee of get_beacon_committee, and get_committee_count_per_slot(state, epoch). An index the state does not have, or of a validator with no assignment in the epoch, gives no item; the spec names no error for it.
  - `dependent_root`: get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch - 1) - 1), the spec's description; on underflow the genesis block's root.
- getSyncCommitteeDuties: the sync committee places in `epoch` of the validators of the body (altair validator.md, is_assigned_to_sync_committee).
  - 503 while the node syncs, as getProposerDuties; 400 for an epoch whose sync committee period is above that of the epoch of `current_slot` + 1, the spec's description; 400 for a body of no item, or with an item that is a public key: the spec's body is an array of at least one validator index.
  - The state: the head's post-state when its fork is altair or later and the epoch's sync committee period is that of the head's slot or the next; else, as for getAttesterDuties, that of the epoch's first slot (none: 400).
  - The committee: lantern_node_sync_committee of the state and the epoch; with no answer, as for a state before altair, 400.
  - `{"execution_optimistic":…,"data":[…]}`, `execution_optimistic` that of the state; for each item of the body in order whose validator is in the committee, `{"pubkey":…,"validator_index":…,"validator_sync_committee_indices":[…]}`: its places in the committee, ascending. An index the state does not have, or of a validator not in the committee, gives no item.
- getLiveness: whether each validator of the body was seen live in `epoch`, from its messages "on the network, in the beacon chain, from its API" (the spec's description).
  - 503 while the node syncs, as getProposerDuties.
  - 400 for an epoch below the previous epoch of `current_slot`, or above its next epoch: the spec asks a node to "support the current and previous epoch"; the next epoch answers too, so that a client whose clock is ahead at an epoch's edge gets an answer.
  - 400 for a body of no item, or with an item that is a public key: the spec's body is an array of at least one validator index.
  - The state: the head's post-state at the head's slot, as for a `state_id` of `head` (none: 500).
  - `{"data":[…]}`: for each item of the body in order, `{"index":…,"is_live":…}`.
  - `is_live` is false for an index the state does not have. Else it is true when one of these holds:
    - In the beacon chain, for `epoch` the state's current epoch: from altair, the validator's `current_epoch_participation` flags are not 0; in phase0, the index is among get_attesting_indices of an attestation of `current_epoch_attestations`.
    - In the beacon chain, for `epoch` the state's previous epoch: the same of `previous_epoch_participation` or `previous_epoch_attestations`.
    - On the network and from the API: the node's `Seen` holds a `SEEN_ATTESTATION` or `SEEN_AGGREGATOR_EPOCH` key of `epoch` and the index, or a `SEEN_PROPOSER_SLOT`, `SEEN_SYNC_MESSAGE` or `SEEN_SYNC_CONTRIBUTION` key of a slot of `epoch` and the index (networking.md, `SeenKey`). The gossip checks of a message, from the network or from a pool POST, add these keys.
- produceBlockV3: an unsigned block of `slot` for its proposer (validator.md of each fork, Block proposal), with the payload of the node's execution engine; the node has no builder, so the block is never blinded and `builder_boost_factor` changes nothing (the spec: without a builder the node "MUST respond with a full block").
  - 503 while the node syncs (`is_syncing`), beacon-APIs `CurrentlySyncing`, as getProposerDuties.
  - 400: a `slot` at or below the head's slot, or above `current_slot` + 1; a `randao_reveal` that is no `Signature`; with `skip_randao_verification`, a `randao_reveal` other than the point at infinity (`0xc0` and 95 zero bytes, the spec's parameter); without it, a `randao_reveal` that fails the check of process_randao for the proposer of `slot` in the state below; a `graffiti` that is no 32-byte `Bytes32`; a `builder_boost_factor` past 2^64 - 1.
  - The state: the head's post-state brought to `slot`, as for produceAttestationData. Its proposer: get_beacon_proposer_index of that state.
  - The body, in the field order of the fork's `BeaconBlockBody`:
    - `randao_reveal` and `graffiti` (zero bytes without the parameter).
    - `eth1_data`: get_eth1_vote with an empty `eth1_chain`, which is the state's `eth1_data` (phase0 and electra `validator.md`): the node keeps no eth1 chain yet.
    - `deposits`: none. When the expected count of deposits is above 0 (phase0 `validator.md`: min(`MAX_DEPOSITS`, `eth1_data.deposit_count` - `eth1_deposit_index`); electra: get_eth1_pending_deposit_count), no valid block is possible without the eth1 chain: 500.
    - `proposer_slashings`, `attester_slashings`, `voluntary_exits` and `bls_to_execution_changes` (from capella): the pool's entries of the kind, in the pool's order, at most `MAX_PROPOSER_SLASHINGS`, `MAX_ATTESTER_SLASHINGS` (`MAX_ATTESTER_SLASHINGS_ELECTRA` from electra), `MAX_VOLUNTARY_EXITS` and `MAX_BLS_TO_EXECUTION_CHANGES`; attester slashings of the fork's type only. Two operations of one block must not clash: an attester slashing goes only with an index in both attestations that no proposer slashing of the block slashes, and a voluntary exit only for a validator that no slashing of the block slashes.
    - `attestations`: for each `AttestationData` of the pool's attestations that process_attestation's checks of slot and target allow at the state (its target epoch the state's current or previous epoch, `data.slot` + `MIN_ATTESTATION_INCLUSION_DELAY` at most the state's slot, before deneb at most `SLOTS_PER_EPOCH` older, and `source` the state's justified checkpoint of that epoch), the aggregate of its attesters as getAggregatedAttestationV2 builds it; from electra, the aggregates of one `data` of every committee joined by compute_on_chain_aggregate (electra `validator.md`). In order of `data.slot` descending, then the pool's order of each data's first attestation; at most `MAX_ATTESTATIONS` (`MAX_ATTESTATIONS_ELECTRA` from electra).
    - `sync_aggregate` (from altair): process_sync_committee_contributions (altair `validator.md`) of the contribution of each subcommittee, as produceSyncCommitteeContribution builds it from the pool's messages of `slot` - 1 with the block's `parent_root`, those with a participant; with none, no bit and the point at infinity.
    - `execution_payload` (from bellatrix): of engine_getPayload of the fork's version for the payload the node prepared for `slot` on the head (node.md, Payload preparation), prepared now when there is none, with the fee recipient of the proposer's `NodeProposer` entry, else zero bytes. Before the merge (bellatrix, a state with no payload header), the empty payload. `blob_kzg_commitments` (from deneb): the `commitments` of its `blobs_bundle`. `execution_requests` (from electra): lantern_get_execution_requests of its request lists.
  - The block: `slot`, the proposer's index, `parent_root` hash_tree_root of the state's `latest_block_header`, the body, and `state_root` the hash_tree_root of the state after process_block of the block, with no randao signature check when `skip_randao_verification` is given (the spec's compute_new_state_root runs the rest). A block that process_block rejects: 500.
  - `execution_payload_value`: the `blockValue` of the engine's result, 0 for engine_getPayloadV1 and before bellatrix. `consensus_block_value`: the proposer's balance after process_block less its balance before, plus the amounts of the payload's withdrawals to the proposer, at least 0, in Wei (Gwei times 10^9), the spec's "Consensus rewards paid to the proposer for this block".
  - The answer: `Eth-Consensus-Version` the fork of `slot`, `Eth-Execution-Payload-Blinded: false`, `Eth-Execution-Payload-Value` and `Eth-Consensus-Block-Value` in decimal. JSON `{"version":"<fork>","execution_payload_blinded":false,"execution_payload_value":"…","consensus_block_value":"…","data":…}`, `data` the fork's `BeaconBlock` before deneb and from deneb lantern's `BlockContents` of the block, the bundle's `proofs` as `kzg_proofs` and its `blobs`; with SSZ by `Accept`, the SSZ bytes of that value.
- publishBlockV2: a signed block for the network and the node (each fork's validator.md, Broadcast; deneb and later, the sidecars).
  - The body: the fork's `SignedBeaconBlock` before deneb; from deneb lantern's `SignedBlockContents`: `signed_block`, `kzg_proofs` (the bundle's proofs type) and `blobs`. JSON, or SSZ by `Content-Type`. `consensus_version` names the fork of that type.
  - 503 while the node syncs (`is_syncing`), as produceBlockV3.
  - 400: a body that is no such value; a `consensus_version` that is not the fork of the block's slot; deneb and electra, a count of `kzg_proofs` or `blobs` other than that of the body's `blob_kzg_commitments`; fulu, a count of `blobs` other than it, or of `kzg_proofs` other than `CELLS_PER_EXT_BLOB` times it; a block or a sidecar that fails the checks of `broadcast_validation` (below). Nothing goes out.
  - A block whose root the node holds (a `NodeBlock` of that root, of any status but `NODE_BLOCK_INVALID`): 200, and nothing goes out (the block went out before, or came in from the network).
  - The sidecars: deneb and electra get_blob_sidecars (deneb validator.md) of the block, `blobs` and `kzg_proofs`; fulu get_data_column_sidecars_from_block (fulu validator.md) of the block and, for each blob, compute_cells of it and its `CELLS_PER_EXT_BLOB` proofs of `kzg_proofs` in order.
  - `broadcast_validation` `gossip` (1): the checks of the beacon_block topic (p2p-interface.md of the fork, lantern_validate_beacon_block_gossip) at the node's head, and of each sidecar's topic (blob_sidecar, data_column_sidecar) with the same states; a result but `LANTERN_VALID` fails. `consensus` (2): also the state transition of the block on its parent's post-state, with the signature checks and execution_valid 1 (the payload's transactions are the execution engine's, at the import), whose state root is the block's. `consensus_and_equivocation` (3): also no other block of the same proposer and slot that the node saw; the beacon_block topic's check of `proposer_slots`, which `gossip` already runs, is that check.
  - Then the publish of the block on beacon_block and of each sidecar on its subnet's topic (deneb compute_subnet_for_blob_sidecar, fulu compute_subnet_for_data_column_sidecar), and the block and its sidecars go to the node as from the network: a `NodeBlock` with its data available, and the sidecars the node keeps (each blob sidecar; the column sidecars of `columns`).
  - The answer, once the block's import ends: 200 when the node imported it; 202 when it is invalid, after the publish (beacon-APIs: "successfully broadcast but failed integration"). No body.
- submitBeaconCommitteeSelections and submitSyncCommitteeSelections: 501. The spec gives them to a distributed validator middleware: "Consensus clients need not support this endpoint and may return a 501."
- eventstream: the events of `topics`, as server-sent events: the event stream format of the WHATWG HTML standard, section 9.2.
  - The head: `HTTP/1.1 200 OK` CRLF, `Content-Type: text/event-stream` CRLF, `Cache-Control: no-cache` CRLF (the two fields Lighthouse v8.3.3 sends through warp's `sse::reply`); then over HTTP/1.1 `Transfer-Encoding: chunked` CRLF, and `Connection: close` CRLF when the request has `Connection: close`; over HTTP/1.0, with or without `keep-alive`, `Connection: close` CRLF; CRLF.
  - Each event: `event: <topic>` LF `data: <JSON>` LF LF, the layout of the spec's examples. Over HTTP/1.1 each event is one chunk of RFC 9112 section 7.1, its size in 4 lower case hex digits.
  - The answer has no end. The client closes the connection, or the node closes it when the stream falls behind (node.md, `NodeApi`).
  - The topics with events: `block`, `head`, `finalized_checkpoint`, `chain_reorg`, `block_gossip`, `blob_sidecar`, `data_column_sidecar`, `payload_attributes`, and the operation topics `attestation`, `single_attestation`, `voluntary_exit`, `bls_to_execution_change`, `proposer_slashing`, `attester_slashing` and `contribution_and_proof`.
  - block: a block the node imports: `{"slot":…,"block":…,"execution_optimistic":…}`, the block's slot and root. `execution_optimistic` is true when the payload status the import takes is `PAYLOAD_STATUS_NOT_VALIDATED`.
  - head: the node's head when it changes: `{"slot":…,"block":…,"state":…,"epoch_transition":…,"previous_duty_dependent_root":…,"current_duty_dependent_root":…,"execution_optimistic":…}`.
    - `slot` and `block`: the head block's slot and root. `state`: hash_tree_root of its post-state.
    - `epoch_transition`: true when the epoch of the head's slot is above that of the old head's slot, as Lighthouse v8.3.3 sets it (beacon_chain.rs); the spec names the field only.
    - The dependent roots of the spec's description, from the post-state: get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch - 1) - 1) and get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch) - 1), epoch that of the state's slot. On underflow, the genesis block root: get_block_root_at_slot(state, 0) when the state's slot is above 0, else hash_tree_root of the state's `latest_block_header` with the state's hash_tree_root as its `state_root`.
    - `execution_optimistic`: from the head block's payload status, as for block.
  - chain_reorg: at a head event, when the new head's chain does not have the old head at the old head's slot, or the old head's slot is not below the new head's (the old head is the head of the last head event): `{"slot":…,"depth":…,"old_head_block":…,"new_head_block":…,"old_head_state":…,"new_head_state":…,"epoch":…,"execution_optimistic":…}`. The spec names the fields only; these are the values Lighthouse v8.3.3 gives (canonical_head.rs, detect_reorg and find_reorg_slot).
    - `slot` and `epoch`: the new head's slot and its epoch. `old_head_block` and `new_head_block`: the roots of the two heads; `old_head_state` and `new_head_state`: the state roots of their blocks.
    - `depth`: the old head's slot less the highest slot, at most the lower of the two heads' slots, at which both chains have the same block root; a chain's root at a slot is that of its block of the highest slot at or below it.
    - `execution_optimistic`: from the new head's payload status, as for block.
  - block_gossip: a block that passes the checks of the beacon_block topic, from the network, or from publishBlockV2 once its checks pass (each `broadcast_validation` level runs them): `{"slot":…,"block":…}`, the block's slot and root.
  - blob_sidecar: a `BlobSidecar` that passes the checks of its blob_sidecar topic, from the network, or from publishBlockV2 for each sidecar it publishes: `{"block_root":…,"index":…,"slot":…,"kzg_commitment":…,"versioned_hash":…}`. `block_root`: hash_tree_root of its `signed_block_header.message`; `slot`: that header's slot; `versioned_hash`: kzg_commitment_to_versioned_hash of its `kzg_commitment` (deneb beacon-chain.md).
  - data_column_sidecar: a `DataColumnSidecar` that passes the checks of its data_column_sidecar topic, from the network, or from publishBlockV2 for each sidecar it publishes: `{"block_root":…,"index":…,"slot":…,"kzg_commitments":[…]}`, `block_root` and `slot` as for blob_sidecar.
  - payload_attributes: each payload preparation of the node (node.md, Payload preparation) that makes its engine_forkchoiceUpdated request (the spec: the node "has computed new payload attributes"): `{"version":"<fork>","data":{"proposer_index":…,"proposal_slot":…,"parent_block_number":…,"parent_block_root":…,"parent_block_hash":…,"payload_attributes":{…}}}`.
    - `version`: the fork of `proposal_slot`, the slot of the block to build. `proposer_index`: get_beacon_proposer_index of the state at that slot.
    - `parent_block_root`: the head's root, on which the block builds. `parent_block_number` and `parent_block_hash`: the `block_number` and `block_hash` of the state's `latest_execution_payload_header`.
    - `payload_attributes`: those of lantern_get_payload_attributes, in the spec's beacon API encoding of `PayloadAttributesV<N>` (snake_case names, quoted decimal integers): `timestamp`, `prev_randao`, `suggested_fee_recipient`; from capella `withdrawals`, each `{"index":…,"validator_index":…,"address":…,"amount":…}`; from deneb `parent_beacon_block_root`.
  - The operation topics: an operation that passes the gossip validation of its gossip topic (lantern_node_gossip gives `LANTERN_VALID`), from the network or from a pool POST (the spec: "from P2P or API"): the JSON of its SSZ bytes, by lantern_json_encode_ssz with the type of the fork of that validation.
    - attestation: an `Attestation` of beacon_attestation, before electra. single_attestation: a `SingleAttestation` of beacon_attestation, from electra; the topic's messages have that type from electra.
    - voluntary_exit: a `SignedVoluntaryExit`. bls_to_execution_change: a `SignedBLSToExecutionChange`. proposer_slashing: a `ProposerSlashing`. attester_slashing: the fork's `AttesterSlashing`. contribution_and_proof: a `SignedContributionAndProof` of sync_committee_contribution_and_proof.
    - An operation that its validation ignores, as one the node has seen, gives no event.
  - light_client_finality_update and light_client_optimistic_update: the store's latest finality update when it is new, as altair light-client `p2p-interface.md` forwards one (a finalized slot above all forwarded before, or the same with a supermajority the last did not have), and its optimistic update when its attested slot is above all forwarded before: `{"version":"<fork>","data":<data>}`, as getLightClientFinalityUpdate and getLightClientOptimisticUpdate.
  - finalized_checkpoint: the store's finalized checkpoint, when its epoch rises: `{"block":…,"state":…,"epoch":…,"execution_optimistic":…}`, the checkpoint's root and epoch, and the `state_root` of that block. Lighthouse v8.3.3 sends the finalized block's `state_root` there; the spec names the field only. `execution_optimistic`: from the block's payload status, as for block.
- The pools (node.md, `NodePool`): voluntary exits, BLS to execution changes, proposer slashings, attester slashings and attestations, each kept as its SSZ bytes once it passes its gossip validation, from gossip or from the POSTs below. An operation goes when it no longer passes it at a later head; an attestation goes once its epoch is before the previous epoch of the store's slot.
  - The attestations are those of the subnets the node subscribes to and those of submitPoolAttestationsV2, each with one attester. Aggregates do not join the pool.
  - The pool also keeps sync committee messages, from the sync_committee subnets the node subscribes to and from submitPoolSyncCommitteeSignatures, each with its slot and the subnets it is valid on, until the store's slot is past its slot + 1. No pool GET answers them.
- getPoolVoluntaryExits, getPoolBLSToExecutionChanges and getPoolProposerSlashings: `{"data":[<the JSON of each pool entry of the kind, in the pool's order, with , between>]}`.
- getPoolAttesterSlashingsV2: `Eth-Consensus-Version` and `version` the fork of the store's slot; `{"version":"<fork>","data":[…]}` of the pool's attester slashings of that fork's `AttesterSlashing` type (electra's from electra on, phase0's before). The spec names neither the version nor which slashings answer; this is the fork whose type the node decodes at its slot.
- getPoolAttestationsV2: `Eth-Consensus-Version` and `version` the fork of the store's slot; `{"version":"<fork>","data":[…]}` of the pool's attestations of that fork's attestation type, with `data.slot` equal to `slot` and the committee index equal to `committee_index` when those are given. From electra the pool keeps each attestation as the `SingleAttestation` it came as, and the answer gives the electra `Attestation` of it: `aggregation_bits` of its committee's length with its attester's bit, `committee_bits` with its committee index's bit, as the spec's `Attestation` of one attester has them (the response's type).
- getAggregatedAttestationV2: the aggregate of the pool's attestations of the attestation type of the fork of the store's slot with `data.slot` `slot`, the committee index `committee_index` and a `data` whose hash_tree_root is `attestation_data_root`, in pool order: each whose attester's place in its committee no attestation before it took joins, its place's bit set in `aggregation_bits` (of its committee's length) and its signature added by crypto_bls_aggregate.
  - None: 404; a `data.beacon_block_root` of a block whose `payload_status` is `NOT_VALIDATED`: 503 (the spec's description).
  - `Eth-Consensus-Version` and `version` the fork; `{"version":"<fork>","data":<Attestation>}`, the JSON of the fork's `Attestation`, or with an SSZ `response` its SSZ bytes. From electra the electra `Attestation`, `committee_bits` with the bit of `committee_index`.
- produceSyncCommitteeContribution: the `SyncCommitteeContribution` of the pool's sync committee messages of `slot`, valid on the subnet `subcommittee_index`, with `beacon_block_root`, in pool order (altair validator.md, Construct sync committee contribution): for each whose places in the subcommittee (lantern_node_sync_positions of the head's post-state) no message before it took, the bit of each place is set and its signature added by crypto_bls_aggregate once for each place.
  - A `subcommittee_index` not below `SYNC_COMMITTEE_SUBNET_COUNT`: 400. None: 404; a `beacon_block_root` of a block whose `payload_status` is `NOT_VALIDATED`: 503 (the spec's description). A head with no post-state: 500.
  - `{"data":<SyncCommitteeContribution>}`, JSON only (the spec gives no SSZ response).
- The five are streamed, as getStateValidators: one chunk or more per entry, from the entry's SSZ bytes by lantern_json_encode_ssz of its type.
- submitPoolVoluntaryExit, submitPoolProposerSlashings, submitPoolAttesterSlashingsV2 and submitPoolBLSToExecutionChange: the body, JSON of `SignedVoluntaryExit`, `ProposerSlashing`, the `AttesterSlashing` of the fork of the store's slot, or a JSON array of `SignedBLSToExecutionChange`, each item decoded by lantern_json_decode (the spec sets no limit on the items; the body's own limit bounds them). A body that is no JSON of its type, or an array with an item that is not: 400 `{"code":400,"message":"BAD_REQUEST"}`, and no operation goes on.
  - Each operation, in the list's order: the gossip validation of its topic (lantern_node_gossip, with the node's `Seen`, as a gossip message is checked). Valid: it joins the pool and goes out on its topic (node.md, the publish). Ignored, as one the node has seen: nothing more; Lighthouse v8.3.3 answers an operation it knows with success too. Rejected: a failure.
  - The answer: 200 with no body when no operation fails. Else 400: of the three single operations `{"code":400,"message":"BAD_REQUEST"}`; of the list, the IndexedErrorMessage of beacon-APIs, `{"code":400,"message":"BAD_REQUEST","failures":[{"index":<i>,"message":"REJECT"},…]}`, an item for each rejected operation in order, `index` its place in the list as a JSON number.
  - submitPoolAttesterSlashingsV2 requires `Eth-Consensus-Version` (the route); a fork whose `AttesterSlashing` type is not that of the store's slot: 400.
- submitPoolAttestationsV2: a JSON array of the fork's attestation type, `Attestation` before electra and `SingleAttestation` from electra (the spec's description), or with `Content-Type: application/octet-stream` the SSZ list of them. `Eth-Consensus-Version` is required (the route); a fork of the other type than the fork of the store's slot: 400. A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`.
  - Each attestation, in order: the gossip validation of beacon_attestation of its subnet, compute_subnet_for_attestation of the committee count of its target epoch in the head's post-state, its slot and its committee index, as phase0 validator.md places it, with the node's `Seen`. Valid: it joins the pool and goes out on that subnet (the spec: the node MUST publish it); rejected: a failure; ignored: nothing more.
  - The answer: 200 with no body when none fails; else 400 with the IndexedErrorMessage of the failures, as for submitPoolBLSToExecutionChange.
- publishAggregateAndProofsV2: a JSON array of the fork's `SignedAggregateAndProof` (phase0's before electra, electra's from electra), or with `Content-Type: application/octet-stream` the SSZ list of them (4-byte offsets, the type is of variable size). `Eth-Consensus-Version` is required (the route); a fork of the other type than the fork of the store's slot: 400. A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`.
  - Each aggregate, in order: the gossip validation of beacon_aggregate_and_proof, with the node's `Seen`. Valid: it goes out on its topic (the spec's description: "publishes them on appropriate gossipsub topic"); it joins no pool, and fork choice takes no vote from it, as from a submitted attestation. Rejected: a failure; ignored: nothing more.
  - The answer: 200 with no body when none fails; else 400 with the IndexedErrorMessage of the failures, as for submitPoolBLSToExecutionChange.
- submitPoolSyncCommitteeSignatures, from altair: a JSON array of `SyncCommitteeMessage`. A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`.
  - Each message, in order: the gossip validation of sync_committee of each subnet of compute_subnets_for_sync_committee(the head's post-state, its `validator_index`) (altair validator.md; lantern_node_sync_subnets), with the node's `Seen`; with no such subnet (an index past the validators, or a validator outside the sync committee), that of subnet 0, which rejects it or ignores it.
  - Valid on a subnet: it joins the pool and goes out on each subnet where it is valid (the spec's description: the node "MUST publish that sync committee signature on all applicable subnets"). Else rejected on a subnet: a failure. Else nothing more.
  - The answer: 200 with no body when none fails; else 400 with the IndexedErrorMessage of the failures, as for submitPoolBLSToExecutionChange.
- publishContributionAndProofs, from altair: a JSON array of `SignedContributionAndProof`. A body that is no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`.
  - Each, in order: the gossip validation of sync_committee_contribution_and_proof, with the node's `Seen`. Valid: it goes out on its topic; it joins no pool, as an aggregate. Rejected: a failure; ignored: nothing more.
  - The answer: 200 with no body when none fails; else 400 with the IndexedErrorMessage of the failures, as for submitPoolBLSToExecutionChange.
- prepareBeaconCommitteeSubnet: a JSON array of the spec's items, decoded as lantern's `BeaconCommitteeSubscription` (`validator_index`, `committee_index`, `committees_at_slot`, `slot`, `is_aggregator`). An item whose `committees_at_slot` is 0 or above `MAX_COMMITTEES_PER_SLOT`, or whose `committee_index` is not below it, or a body of no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`, and none applies.
  - Each item with `is_aggregator`: the node joins beacon_attestation of compute_subnet_for_attestation(`committees_at_slot`, `slot`, `committee_index`) (phase0 validator.md) and keeps it until the store's slot is past `slot` (node.md, the subscriptions); the pool keeps the subnet's attestations, which getAggregatedAttestationV2 aggregates (the spec: "announce subnet topic subscription on gossipsub" and "aggregate attestations received on that subnet"). An item without it changes nothing.
  - The answer: 200 with no body.
- prepareSyncCommitteeSubnets, from altair: a JSON array of `SyncCommitteeSubscription`, lantern's container of the spec's type (`sync_committee_indices` at most `SYNC_COMMITTEE_SIZE`). An index not below `SYNC_COMMITTEE_SIZE`, or a body of no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`, and none applies.
  - Each index i of each item: the node joins sync_committee of the subnet i / (SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT) and keeps it while the store's epoch is below `until_epoch` (the spec: "The final epoch (exclusive value)"); its MetaData's and record's `syncnets` are those subnets (altair p2p-interface.md).
  - The answer: 200 with no body.
- prepareBeaconProposer: a JSON array of the spec's items, decoded as lantern's `ProposerPreparation` (`validator_index`, `fee_recipient`). A body of no such list: 400 `{"code":400,"message":"BAD_REQUEST"}`, and none applies.
  - Each item: the node's `NodeProposer` entry of its `validator_index` takes its `fee_recipient` until the store's epoch + 3, exclusive (the spec: it persists "through the epoch in which the call is submitted and for a further two epochs after that"); an index the node does not know is kept too (the spec: such requests "will be accepted"). With no entry of its index: a free entry, one past its epoch, else a new one while the part has room; else the item is dropped.
  - The answer: 200 with no body.
- Every other operation: 501.

## Test vectors

- The answers: the `api` cases of [node.md](node.md#test-vectors), through lantern_node_step and lantern_node_run, and the getBlockV2 and getStateV2 checks of its fork_choice cases in node mode.
- tests/generator/http_request.py: requests and the `HttpRequest` or fault of each, by the rules of lantern_http_request, apart from the assembly. Each case also runs with its bytes cut short at every length (`LANTERN_HTTP_MORE`, or the same fault once the faulty byte is in), and with `out` one byte short. File: `<preset>-phase0-http-request.bin`.
  - Request lines: each method, origin forms with and without a query, both versions, HTTP/2.0 (505), and broken lines.
  - Fields: each read field, names in mixed case, repeated lines joined, white space before a colon, folded lines, no `Host`, two `Host` lines.
  - Bodies: `Content-Length` (zero, exact, past `body_max`, two equal values, two different values), chunked (one and many chunks, extensions, trailers, bad sizes, past `body_max`), both fields together, another coding.
  - Limits: a head of exactly `head_max` bytes and one byte more.
  - Pipelining: two requests in one buffer; `used` ends the first.
- tests/generator/json_codec.py: values of every container type of each fork's spec module (get_random_ssz_object of the pinned spec's test helpers: in minimal the modes zero, one, random and max with lists of at most 4 items and byte lists of at most 64 bytes; in mainnet the mode zero) and the JSON of each, written by the rules of lantern_json_encode, apart from the assembly. The runner reads each value with the type of the fork's type table of that name, when lantern has it, and counts the others in a NOTE; each case also runs in chunks of 1, 7 and 64 bytes of room, and with `out` one byte short of the whole JSON (`LANTERN_JSON_MORE`), then with no room (`LANTERN_BUFFER_TOO_SMALL`). The runner also gives each case's SSZ bytes to lantern_json_encode_ssz, in the same rooms. File: `<preset>-<fork>-json-encode.bin`.
- tests/generator/json_codec.py also makes the cases of lantern_json_decode: the JSON of each `json-encode` case, with white space between its tokens and its fields in reverse order in a second copy, must give the case's SSZ bytes; then for some types, texts that break one rule each, with the `JsonFault` of each (its kind, offset and path). Each valid case also runs with `out` one byte short. File: `<preset>-<fork>-json-decode.bin`.
- tests/generator/api_route.py: requests and the `ApiRoute` or fault of each, by the rules of lantern_api_route, apart from the assembly. It reads the operations from the beacon-APIs clone at the pinned commit, so the table of the assembly is checked against the spec; a parameter of the spec that the rules below do not name stops it. Each case with `LANTERN_OK` also runs with `out` one byte short. File: `<preset>-phase0-api-route.bin`.
  - Every operation: its method and path with every required parameter; then each optional parameter.
  - Every path: each other method (405, `allow`), a trailing `/`, a missing and an extra segment (404).
  - Every parameter: each form of its type, and values that break it (400 and `fault`).
  - Query: repeated names, comma lists, empty items, names the operation does not take, percent-encoding (good and broken), 65 ids (414).
  - Headers: `Accept` with q-values, wildcards, parameters and broken items (406); `Content-Type` (415); `Eth-Consensus-Version` of each fork, missing and wrong (400).

## Function `lantern_api_route`

Finds the operation of one request and reads its parameters, by their types.

### Signature

```
lantern_api_route(request, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `request` | input | [`HttpRequest`](#type-httprequest), as lantern_http_request gave it with `LANTERN_OK` |
| `out` | output | [`ApiRoute`](#type-apiroute), its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the operation and its parameters.
- `LANTERN_INVALID_ROUTE`: `status` of `out` is the HTTP status to answer: 400, 404, 405, 406, 414 or 415. `fault`, `allow` and `op` say why.
- `LANTERN_BUFFER_TOO_SMALL`: `size` of `out` is below `API_ROUTE_FIXED`, or the request breaks no rule and `out` has room for fewer bytes than its parts.

### Function does

- Operations:
  - The 76 operations of beacon-APIs v4.0.0, numbered `API_OP_*` from 1 in the order of `paths` in `beacon-node-oapi.yaml`, `GET` before `POST` on one path.
  - Each has a method, a path template, and its parameters (include/api_routes.inc).
- Path:
  - The `path` part splits at each `/` after the first byte. Each segment is percent-decoded: `%` and two hex digits of either case is that byte. A `%` without two hex digits gives 400, `fault` 0.
  - A template matches when it has as many segments, each fixed segment is equal byte for byte, and each parameter segment `{name}` is not empty.
  - No template matches: 404.
  - A template matches, but it has no operation for the method: 405. `allow` holds its methods: bit 0 `GET`, bit 1 `POST`.
- Query:
  - The `query` part splits at each `&`. An empty item is skipped. An item splits at its first `=` into name and value; with no `=` the value is empty. Both are percent-decoded, as the path is; a broken `%` gives 400, `fault` 0.
  - A name the operation does not take is skipped.
  - A name given twice: a list or a set takes both values, in order. Any other parameter gives 400.
  - The value of a list or a set splits at each `,`. An empty item gives 400.
  - A required parameter that is missing gives 400.
- Parameters by type. A value that breaks its type gives 400, `fault` the parameter:
  - Number (`epoch`, `slot`, `index`, `committee_index`, `subcommittee_index`, `start_period`, `count`, `builder_boost_factor`): one or more decimal digits, value below 2^64.
  - `syncing_status`: a number from 100 to 599.
  - Hex: `0x` and hex digits of either case, as many as the type says.
  - `state_id`: `head`, `genesis`, `finalized`, `justified`, a number (a slot), or hex of 32 bytes (a state root).
  - `block_id`: `head`, `genesis`, `finalized`, a number (a slot), or hex of 32 bytes (a block root).
  - `block_root`: hex of 32 bytes.
  - `validator_id`, and each item of `id`: a number (an index) or hex of 48 bytes (a public key, any bytes).
  - `peer_id`: 1 to 128 bytes of the base58btc alphabet.
  - `parent_root`, `attestation_data_root`, `beacon_block_root`, each item of `versioned_hashes`: hex of 32 bytes.
  - `randao_reveal`: hex of 96 bytes. `graffiti`: hex of 32 bytes.
  - `skip_randao_verification`: an empty value.
  - `broadcast_validation`: `gossip` (1), `consensus` (2) or `consensus_and_equivocation` (3). When it is missing: 1.
  - Each item of `indices`: a number.
  - Sets, a bit for each name: `status` (the nine `ValidatorStatus` names; `pending`, `active`, `exited` and `withdrawal` set the bits of their statuses), `state` and `direction` of getPeers, `topics` of eventstream (`API_STATUS_*`, `API_PEER_*`, `API_DIRECTION_*`, `API_TOPIC_*`).
  - `id` of getStateValidators and getStateValidatorBalances: more than 64 items give 414, `fault` `API_PARAM_ID`.
- The JSON body of postStateValidators, postStateValidatorBalances, postStateValidatorIdentities, getSyncCommitteeRewards, getAttestationsRewards, getAttesterDuties, getSyncCommitteeDuties and getLiveness gives `id` and `status` items as a query does, with no limit on the count of `id` items:
  - postStateValidators (`API_FLAG_IDS_OBJECT`): an object whose members are `ids` and `statuses`, each at most once, each `null` or an array of strings. Each string of `ids` is an `id` item; each of `statuses` a `status` item. Lighthouse v8.3.3 takes this body with the same rule (`deny_unknown_fields`).
  - The other seven (`API_FLAG_IDS_ARRAY`), whose bodies the spec gives as arrays of strings, each a public key or a validator index, or for getAttesterDuties, getSyncCommitteeDuties and getLiveness each a `Uint64`, a validator index (a public key item is then the operation's 400): no body, `null`, or an array of strings, each an `id` item.
  - JSON white space (space, tab, LF and CR) may stand before and after each token. A string follows RFC 8259 section 7: between two `"`, no byte below 0x20, and each `\` starts an escape: `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, or `\u` and 4 hex digits. Its value, the key or the item, has each escape decoded; a `\u` of 0x80 or more gives a byte no item holds.
  - An empty array, `null` or a missing member gives no item: the parameter counts as not given.
  - Any other body, or bytes after its value: 400, `fault` 0. An item that breaks its type: 400, `fault` `API_PARAM_ID` or `API_PARAM_STATUS`. The first fault in the body's order is the one given.
- `Eth-Consensus-Version`, on the five operations that require it (publishBlindedBlockV2, publishBlockV2, submitPoolAttestationsV2, submitPoolAttesterSlashingsV2, publishAggregateAndProofsV2): a fork name from `phase0` to `fulu`, which sets `consensus_version` to its `FORK_*`. Missing or another value: 400, `fault` `API_PARAM_CONSENSUS_VERSION`.
- `Accept`, on the operations that can answer with SSZ (those whose responses list 406):
  - No `Accept`: JSON.
  - Items split at each `,`, white space around them trimmed, empty items skipped. An item is a media range, then parameters after `;`. The range compares without regard to case.
  - `q=` sets the item's weight: `0` to `1` with up to 3 decimals (RFC 9110 section 12.4.2). A broken `q` value skips the item. No `q`: weight 1. Other parameters are skipped.
  - `application/json` weighs by the most specific range that matches it: `application/json`, then `application/*`, then `*/*`; the highest weight among ranges of that kind. No match: weight 0. `application/octet-stream` the same way.
  - The heavier type answers; a tie answers JSON. Both weight 0: 406.
  - Other operations ignore `Accept` and answer JSON.
- `Content-Type`, on the operations that take an SSZ body (those whose responses list 415):
  - The media type before any `;`, trimmed, without regard to case: `application/json` or no `Content-Type` is JSON; `application/octet-stream` is SSZ; another type gives 415.
  - Other `POST` operations ignore it: JSON.
- Order of the checks; the first fault found is the one given:
  1. `size` of `out` below `API_ROUTE_FIXED`.
  2. The path's percent-encoding; then its template (404) and its method (405).
  3. The query's percent-encoding.
  4. The path parameters, in the order of the path.
  5. The query items, in their order; within a list or a set, its items in order. The 65th `id` gives 414 before it is read.
  6. Required query parameters: the missing one of lowest `API_PARAM_*`.
  7. `Eth-Consensus-Version`, then `Content-Type`, then the JSON body of the five operations above, then `Accept`.
  8. The room of `out`.
- On `LANTERN_OK`, every field of `out` is written; a parameter that is not given is zero, its bit of `present` clear, apart from `broadcast_validation`, which is 1 when the operation takes it. The list, then the peer id, follow the fixed part, each at a multiple of 8 bytes, with zero bytes between.
- On `LANTERN_INVALID_ROUTE`, `status`, `fault`, `allow` and `op` are written: `allow` once the path matches, `op` once its method matches too, else zero; `fault` the parameter for 400 and 414, else zero.

### Function never

- Reads more than `request` and the `size` field of `out`.
- Writes more than `out`.

### ABI

- Role: L1.
- Symbol: `lantern_api_route` (`_lantern_api_route` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `request`, `out`.

## Function `lantern_http_request`

Reads one HTTP/1.1 request, its head and its body, from the start of a connection's unread bytes.

### Signature

```
lantern_http_request(bytes, limits, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | ByteList: the connection's bytes not yet taken by a request |
| `limits` | input | [`HttpLimits`](#type-httplimits) |
| `out` | output | [`HttpRequest`](#type-httprequest), its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the request, and `used` the bytes it took.
- `LANTERN_HTTP_MORE`: `bytes` holds no whole request yet, and no fault so far.
- `LANTERN_INVALID_HTTP`: the request breaks a rule below; `status` of `out` is the HTTP status to answer, after which the connection closes.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer bytes than the request's parts.

### Function does

- Request line, `method SP request-target SP HTTP-version CRLF` (RFC 9112 section 3):
  - `method`: a token. `GET` and `POST` get their own value; another token is `HTTP_METHOD_OTHER`.
  - `request-target`: origin form, `/` and then visible bytes up to the space. Split at the first `?` into `path` and `query`.
  - `HTTP-version`: `HTTP/1.1` or `HTTP/1.0`. Another `HTTP/` version gives 505; anything else gives 400.
  - Any other fault of the line gives 400.
- A request may start after empty lines (CRLF), as RFC 9112 section 2.2 allows; they count in `used`.
- The head ends at the first CRLF CRLF after the empty lines. No end within the first `head_max` bytes of `bytes` gives 431.
- Field lines, `field-name ":" OWS field-value OWS CRLF` (RFC 9112 section 5):
  - Field names compare without regard to case.
  - White space between the name and the colon, a line that starts with white space (obsolete line folding), or a name that is no token: 400.
  - A value holds no CR, LF or NUL: else 400.
- Fields it reads, by name:
  - `Host`: HTTP/1.1 needs exactly one; none, or more than one, gives 400 (RFC 9112 section 3.2).
  - `Content-Length`: digits only; more than one line, or one list, with differing values: 400. A value above `body_max`: 413.
  - `Transfer-Encoding`: `chunked`, alone, without regard to case. Any other coding: 501. Present with `Content-Length`: 400 (RFC 9112 section 6.3 allows rejecting it as a likely smuggling attempt).
  - `Connection`: the token `close` sets `close`; HTTP/1.0 sets `close` unless the token `keep-alive` is there.
  - `Accept`, `Content-Type` and `Eth-Consensus-Version`: their values go to `accept`, `content_type` and `consensus_version`. Lines of one field join with `, ` between them, in order (RFC 9110 section 5.3).
- The body (RFC 9112 section 6):
  - `Content-Length`: that many bytes after the head.
  - `chunked`: chunks of hex size, each line followed by CRLF; after the hex digits a line may hold `;`, space or tab and then anything but CR, LF and NUL, which is skipped (chunk extensions). The last chunk is size 0; trailer lines are skipped up to the empty line. A size line with no hex digit, a size past 2^64 - 1, chunk data not followed by CRLF, or a size line longer than `head_max` gives 400. Trailer lines of more than `head_max` bytes in all give 431. A body above `body_max` gives 413, once the size line that passes it is in.
  - Neither: no body.
- `used`: the bytes from the start of `bytes` to the end of the request, chunk framing and trailers included. The next request on the connection starts there.
- `out` holds copies: `path`, `query`, the three field values and the body (unchunked), in its parts, in that order, each at a multiple of 8 bytes. Its room: `HTTP_REQUEST_FIXED` + each part's bytes rounded up to a multiple of 8.
- Faults of the head are found once the head has ended: before that, only 431.

### Function never

- Reads more than `bytes`, `limits` and the `size` field of `out`.
- Writes more than `out`.

### ABI

- Role: L1.
- Symbol: `lantern_http_request` (`_lantern_http_request` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `bytes`, `limits`, `out`.

## Function `lantern_json_decode`

Reads one value of an SSZ type from its JSON, as the Beacon API takes it, and writes the value's SSZ encoding.

### Signature

```
lantern_json_decode(type, json, scratch, out, fault) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | asm-ssz `TypeDescriptor`: a root type of a fork's type table, as for lantern_json_encode |
| `json` | input | ByteList: the JSON text |
| `scratch` | scratch | `Scratch`: at least `JSON_DECODE_SCRATCH` (6208) bytes |
| `out` | output | ByteList, its `size` set: the SSZ encoding goes from its offset 24 |
| `fault` | output | [`JsonFault`](#type-jsonfault) |

### Returns

- `LANTERN_OK`: `out` holds the SSZ encoding of the value.
- `LANTERN_INVALID_JSON`: the text breaks a rule below; `fault` says which and where.
- `LANTERN_BUFFER_TOO_SMALL`: `scratch` has fewer than `JSON_DECODE_SCRATCH` bytes, or `out` has room for fewer bytes than the encoding; `size` of `fault` is the room the encoding needs, when the text is valid.

### Function does

- The text (RFC 8259): one value, with white space (space, tab, LF, CR) allowed before and after it and between tokens.
- Strings hold no `\` and no byte below 0x20.
- Each SSZ kind, in the forms lantern_json_encode writes:
  - uint of w bytes: a string of 1 to 78 decimal digits whose value is below 2^(8w).
  - `Boolean`: `true` or `false`.
  - `ByteVector[N]`: a string, `0x` and 2N hex digits of either case.
  - `ByteList[N]`: a string, `0x` and an even count of hex digits, at most 2N.
  - `BitVector[N]`: a string, `0x` and the hex digits of ceil(N / 8) bytes, with every bit from N on zero.
  - `BitList[N]`: a string, `0x` and the hex digits of one byte or more, the last not zero; the bits below its highest set bit, the delimiter, number at most N.
  - `Vector[T, N]`: an array of N items; `List[T, N]`: an array of at most N items.
  - `Container`: an object with each field's name exactly once, in any order, and no other name.
- Order of the checks; the first fault found is the one given:
  - A value of a container: its members in text order, each name a field not seen before (`JSON_FAULT_FIELD` at the name), its value skipped with only the checks of the text; then a field not given (`JSON_FAULT_MISSING` at the `}`); then the value of each field in field order, by its kind.
  - A value of a list or vector: its items skipped in text order with only the checks of the text; then their count (`JSON_FAULT_LENGTH` at the `[`); then each item in order, by its kind.
  - A value of another kind: by its kind; a token of another JSON type gives `JSON_FAULT_TYPE` at it.
  - After the root value, only white space.
  - The checks of the text in a skipped value: strings, numbers (RFC 8259 section 6), `true`, `false`, `null`, and arrays and objects nested at most 64 deep; else `JSON_FAULT_SYNTAX`.
- `fault` on `LANTERN_INVALID_JSON`: the kind, the offset in `json` where the token at fault starts (for a text that ends early, the length of the text), and the path from the root to the value at fault: the object for a field name or a missing field, the array for a count, the value being skipped for a fault of the text inside it, else the value whose token is at fault.
- The encoding: SSZ (ssz-specs v0.1.0, as asm-ssz writes it): the fields of a container in spec order, its fixed part with 4-byte offsets, then its variable parts.

### Function never

- Reads more than `type`, the names after its field records, `json`, `scratch` and the `size` field of `out`.
- Writes more than `scratch`, `out` and `fault`.

### ABI

- Role: L1.
- Symbol: `lantern_json_decode` (`_lantern_json_decode` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `json`, `scratch`, `out`, `fault`.

## Function `lantern_json_encode`

Writes the JSON of one SSZ value, as the Beacon API shows it, a chunk at a time.

### Signature

```
lantern_json_encode(type, value, cursor, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | asm-ssz `TypeDescriptor`: a root type of a fork's type table (include/descriptors.inc), whose field records are followed by the names of its fields |
| `value` | input | asm-ssz `Value` of the type |
| `cursor` | state | [`JsonCursor`](#type-jsoncursor): all zero for a new value |
| `out` | output | ByteList: the bytes go after its `count`, up to its `size` |

### Returns

- `LANTERN_OK`: the JSON is whole, and `cursor` says so.
- `LANTERN_JSON_MORE`: `out` is full; `cursor` holds where the next call goes on.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has no room for a byte. Nothing is changed.

### Caller must

- Pass a valid value of the type.
- Pass the same `type` and `value` again with the `cursor` of the last call, until `LANTERN_OK`.

### Function does

- Each SSZ kind (beacon-APIs `types/primitive.yaml`):
  - uint: its decimal digits, in quotes.
  - `Boolean`: `true` or `false`.
  - `ByteVector`, `ByteList`: `0x` and two lower case hex digits for each byte, in quotes.
  - `BitVector`: the same, of its bytes.
  - `BitList`: the same, of its SSZ bytes: its bits, then the delimiter bit.
  - `Vector`, `List` of another kind: `[`, its items with `,` between them, `]`.
  - `Container`: `{`, then for each field in order `"name":` and its value, with `,` between them, `}`.
- No white space.
- The name of a field: the 32 bytes after the type table's field records at the same index as its field record, up to the first zero byte, or all 32.
- The bytes of all the calls of one value, in order, are the whole JSON, whatever the room of each call.

### Function never

- Reads more than `type`, the names after its field records, `value` and `cursor`.
- Writes more than `out` from its `count` and `cursor`.

### ABI

- Role: L1.
- Symbol: `lantern_json_encode` (`_lantern_json_encode` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `value`, `cursor`, `out`.

## Function `lantern_json_encode_ssz`

Writes the JSON of one SSZ encoding, as lantern_json_encode writes it for the value of that encoding, a chunk at a time.

### Signature

```
lantern_json_encode_ssz(type, ssz, cursor, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | asm-ssz `TypeDescriptor`, as for lantern_json_encode |
| `ssz` | input | ByteList: a valid SSZ encoding of the type |
| `cursor` | state | [`JsonCursor`](#type-jsoncursor): all zero for a new encoding |
| `out` | output | ByteList: the bytes go after its `count`, up to its `size` |

### Returns

- As lantern_json_encode.

### Caller must

- Pass a valid encoding of the type: one that ssz_deserialize takes.
- Pass the same `type` and `ssz` again with the `cursor` of the last call, until `LANTERN_OK`.

### Function does

- The JSON of lantern_json_encode for the value of the encoding, from the bytes of the encoding: a field of fixed size at its `ssz_offset`; a field of variable size from its 4-byte offset to the next variable field's offset, or the end; an item of a list or vector of fixed size at its index times the item's size, with the count of a list its bytes over that size; an item of variable size from its offset to the next, the count of a list its first offset over 4, or 0 with no bytes; a bit list's bytes as they are, with their delimiter.
- In `JsonCursor`, `base` of a level is the offset in `ssz` of its first byte, and `next` the offset of the byte after its last.

### Function never

- Reads more than `type`, the names after its field records, the bytes of `ssz` and `cursor`.
- Writes more than `out` from its `count` and `cursor`.

### ABI

- Role: L1.
- Symbol: `lantern_json_encode_ssz` (`_lantern_json_encode_ssz` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `type`, `ssz`, `cursor`, `out`.

## Type `ApiIdentity`

The texts of the node's identity that the shell knows. A text is a u64 length, then its room of bytes; its bytes are `0x21` to `0x7e`, but `"` and `\`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `peer_id` | text of 64 bytes | Base58btc of the libp2p peer ID |
| 72 | `enr` | text of 512 bytes | `enr:` and base64url of the node record |
| 592 | `p2p_address` | text of 128 bytes | A multiaddr of libp2p, or empty |
| 728 | `discovery_address` | text of 128 bytes | A multiaddr of discv5, or empty |
| 864 | `version` | text of 64 bytes | |
| 936 | | | Size: `API_IDENTITY_SIZE` |

## Type `ApiRoute`

The operation of one request and its parameters, by lantern_api_route.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this field included |
| 8 | `status` | u64 | With `LANTERN_INVALID_ROUTE`: the HTTP status to answer |
| 16 | `op` | u64 | `API_OP_*` |
| 24 | `allow` | u64 | The methods of the matched path: bit 0 `GET`, bit 1 `POST` |
| 32 | `fault` | u64 | `API_PARAM_*` of the parameter at fault, or 0 |
| 40 | `present` | u64 | Bit `API_PARAM_*` set for each parameter given |
| 48 | `response` | u64 | `API_TYPE_JSON` (1) or `API_TYPE_SSZ` (2) |
| 56 | `body` | u64 | 0 for `GET`; else `API_TYPE_JSON` or `API_TYPE_SSZ` |
| 64 | `consensus_version` | u64 | `FORK_*` of `Eth-Consensus-Version` |
| 72 | `id_kind` | u64 | `state_id`, `block_id` or `block_root`: `API_ID_HEAD` (1), `API_ID_GENESIS` (2), `API_ID_FINALIZED` (3), `API_ID_JUSTIFIED` (4), `API_ID_SLOT` (5) or `API_ID_ROOT` (6) |
| 80 | `id_slot` | u64 | With `API_ID_SLOT` |
| 88 | `id_root` | Root | With `API_ID_ROOT` |
| 120 | `validator` | [`ValidatorRef`](#type-validatorref) | `validator_id` |
| 184 | `epoch` | u64 | |
| 192 | `slot` | u64 | |
| 200 | `index` | u64 | |
| 208 | `committee_index` | u64 | |
| 216 | `subcommittee_index` | u64 | |
| 224 | `start_period` | u64 | |
| 232 | `count` | u64 | |
| 240 | `syncing_status` | u64 | |
| 248 | `builder_boost_factor` | u64 | |
| 256 | `broadcast_validation` | u64 | 1, 2 or 3 |
| 264 | `statuses` | u64 | `status`: bits `API_STATUS_*` |
| 272 | `peer_states` | u64 | `state`: bits `API_PEER_*` |
| 280 | `peer_directions` | u64 | `direction`: bits `API_DIRECTION_*` |
| 288 | `topics` | u64 | Bits `API_TOPIC_*` |
| 296 | `root` | Root | `parent_root`, `attestation_data_root` or `beacon_block_root` |
| 328 | `randao_reveal` | BLSSignature | |
| 424 | `graffiti` | Bytes32 | |
| 456 | `list` | PartRef | `id` of the query or the body: `ValidatorRef` items; `indices`: u64 items; `versioned_hashes`: Root items |
| 472 | `peer_id` | PartRef | The bytes of `peer_id` |

### Rules

- The fixed part is `API_ROUTE_FIXED` (488) bytes.
- An operation takes at most one of `state_id`, `block_id` and `block_root`; one of the three roots; and one list.

## Type `HttpLimits`

The largest request head and body a connection takes.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `head_max` | u64 | Bytes from the start of the connection's bytes to the end of the head, the final CRLF CRLF included |
| 8 | `body_max` | u64 | Bytes of the body, unchunked |

## Type `HttpRequest`

One request, read by lantern_http_request.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer, this field included |
| 8 | `status` | u64 | With `LANTERN_INVALID_HTTP`: the HTTP status to answer |
| 16 | `used` | u64 | Bytes of the connection the request took |
| 24 | `method` | u64 | `HTTP_METHOD_GET`, `HTTP_METHOD_POST` or `HTTP_METHOD_OTHER` |
| 32 | `version` | u64 | 10 for HTTP/1.0, 11 for HTTP/1.1 |
| 40 | `close` | u64 | 1 when the connection closes after the answer |
| 48 | `path` | PartRef | The target up to the first `?` |
| 64 | `query` | PartRef | The target after the first `?` |
| 80 | `accept` | PartRef | The `Accept` value |
| 96 | `content_type` | PartRef | The `Content-Type` value |
| 112 | `consensus_version` | PartRef | The `Eth-Consensus-Version` value |
| 128 | `body` | PartRef | The body |

### Rules

- The fixed part is `HTTP_REQUEST_FIXED` (144) bytes; the parts follow in field order, each holding bytes.
- A field that the request does not hold is a part of count 0.

## Type `JsonCursor`

Where lantern_json_encode goes on: the path from the root type to the current token, and the bytes of that token already written.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `depth` | u64 | Levels in use; 0 before the first byte |
| 8 | `done` | u64 | Bytes of the current token already written |
| 16 | `whole` | u64 | 1 once the JSON is whole |
| 24 | `levels` | 12 `JsonLevel` | The path, the root first |
| 600 | | | Size: `JSON_CURSOR_SIZE` |

### Rules

- A `JsonLevel` is 48 bytes: `node`, the index of the level's `TypeNode` in the type's descriptor; `step`, where the level is (below); `item`, the index of its next item or field; `count`, its items, or the bytes or bits of a byte or bit string; `base`, the offset from `value` of its fields (a container), its first item (a list or vector) or its bytes; `next`, the offset from `value` of its next item when its items are of variable size.
- `step` of a list, vector or container: 0 before `[` or `{`; 1 before its next item, or `]` or `}` after the last; 2 before the name of a field, or before an item after `,`; 3 while the item is written, one level deeper.
- A type has at most 12 levels, as asm-ssz allows.

## Type `JsonFault`

Why and where lantern_json_decode refused a JSON text.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `JSON_FAULT_*`, below |
| 8 | `offset` | u64 | The byte of `json` where the token at fault starts |
| 16 | `size` | u64 | With `LANTERN_BUFFER_TOO_SMALL`: the bytes of the encoding |
| 24 | `depth` | u64 | The path's levels |
| 32 | `path` | 12 u64 | For each level from the root, the field index in its container or the item index in its list or vector |
| 128 | | | Size: `JSON_FAULT_SIZE` |

### Rules

- Kinds: `JSON_FAULT_SYNTAX` (1) a text that is no JSON, or more after the value; `JSON_FAULT_TYPE` (2) a value of another JSON type than the SSZ kind takes; `JSON_FAULT_NUMBER` (3) a uint that is no decimal digits or not below its bound; `JSON_FAULT_HEX` (4) a byte or bit string that is no `0x` and hex digits, or of a wrong length or padding; `JSON_FAULT_LENGTH` (5) an array of a wrong length; `JSON_FAULT_FIELD` (6) a field name the container does not have, or given twice; `JSON_FAULT_MISSING` (7) a field missing at the end of an object, at the offset of its `}`.
- With `JSON_FAULT_SYNTAX` at the top level, `depth` is 0.

## Type `ValidatorRef`

A validator by its index or by its public key.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `API_VALIDATOR_INDEX` (1) or `API_VALIDATOR_PUBKEY` (2) |
| 8 | `index` | u64 | With `API_VALIDATOR_INDEX` |
| 16 | `pubkey` | BLSPubkey | With `API_VALIDATOR_PUBKEY` |
| 64 | | | Size |

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_api_route`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_http_request`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_json_decode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_json_encode`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_json_encode_ssz`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
