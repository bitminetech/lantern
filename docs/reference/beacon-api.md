# Beacon API

## Contents

### Functions

- [`lantern_api_answer`](#function-lantern_api_answer): the HTTP response to a Beacon API request.

### Types

- [`ApiView`](#type-apiview): the values of the node that the answers show.

## Spec

- Document: [beacon-APIs v4.0.0](https://github.com/ethereum/beacon-APIs/tree/v4.0.0).
- Section: the endpoints below, of `apis/node/` and `apis/beacon/`, with the JSON of `types/`: numbers as decimal strings, byte strings as `0x` and lower case hex.
- The endpoints are those that ethereum-package and Assertoor read: `ethereum-package` waits for `/eth/v1/node/health` to give 200 or 206, and reads `data.enr`, `data.p2p_addresses[0]` and `data.peer_id` of `/eth/v1/node/identity`.
- HTTP/1.1: RFC 9112. Each response closes its connection.

## Test vectors

- tests/generator/api.py: views, requests, and the response bytes of each, written out by the rules below. File: `<preset>-phase0-api-answer.bin`.

## Function `lantern_api_answer`

The HTTP/1.1 response to one request of the Beacon API, from the values of a view.

### Signature

```
lantern_api_answer(request, view, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `request` | input | ByteList: the bytes of the connection so far |
| `view` | input | [`ApiView`](#type-apiview) |
| `out` | output | ByteList, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the response.
- `LANTERN_HTTP_MORE`: `request` has no empty line yet: the end of the request head.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer bytes than the response.

### Function does

- Reads the request line, `METHOD SP target SP HTTP/1.x`, up to the first CR LF, and the end of the head, the first CR LF CR LF. Reads no header and no body.
- Splits the target at its first `?`: the path, then the query.
- Gives:
  - 400, `BAD_REQUEST`, for a request line not of that form.
  - 405, `METHOD_NOT_ALLOWED`, for a method other than `GET`.
  - 404, `NOT_FOUND`, for a path not below.
- Writes the response: `HTTP/1.1`, the code and its reason, CR LF; `Content-Type: application/json` CR LF when it has a body; `Content-Length:` and the body's bytes in decimal, CR LF; `Connection: close` CR LF; CR LF; the body.
- An error body: `{"code":<code>,"message":"<message>"}`.
- Writes JSON with no space and with the fields in the order below; a number as a decimal string, a byte string as `0x` and lower case hex, a text field as its bytes, which are only `0x21` to `0x7e`.
- `GET /eth/v1/node/health`: 200 `OK`, or 206 `Partial Content` when `is_syncing`, `is_optimistic` or `el_offline` is 1; no body. A query `syncing_status=<n>` with `n` from 100 to 599 gives `n` in place of 206 (with no reason text); another value gives 400 `BAD_REQUEST`.
- `GET /eth/v1/node/identity`: `{"data":{"peer_id":…,"enr":…,"p2p_addresses":[…],"discovery_addresses":[…],"metadata":{"seq_number":…,"attnets":…,"syncnets":…,"custody_group_count":…}}}`; each address list holds the view's address, or nothing when its length is 0; `syncnets` from altair; `custody_group_count` from fulu.
- `GET /eth/v1/node/version`: `{"data":{"version":…}}`.
- `GET /eth/v1/node/syncing`: `{"data":{"head_slot":…,"sync_distance":…,"is_syncing":…,"is_optimistic":…,"el_offline":…}}`; `sync_distance` is `current_slot` minus `head_slot`, or 0 when it is below; the last three are `true` or `false`.
- `GET /eth/v1/node/peer_count`: `{"data":{"disconnected":"0","connecting":"0","connected":…,"disconnecting":"0"}}`.
- `GET /eth/v1/beacon/genesis`: `{"data":{"genesis_time":…,"genesis_validators_root":…,"genesis_fork_version":…}}`.
- `GET /eth/v1/beacon/headers/<block_id>`, with `block_id` `head` or `0x` and the 64 hex digits of the head's root: `{"execution_optimistic":…,"finalized":false,"data":{"root":…,"canonical":true,"header":{"message":{"slot":…,"proposer_index":…,"parent_root":…,"state_root":…,"body_root":…},"signature":…}}}`; `execution_optimistic` is `is_optimistic`; another `block_id` gives 404 `NOT_FOUND`.
- `GET /eth/v1/beacon/states/head/finality_checkpoints`: `{"execution_optimistic":…,"finalized":false,"data":{"previous_justified":{"epoch":…,"root":…},"current_justified":{…},"finalized":{…}}}`.

### Function never

- Writes more than `out`.

### ABI

- Role: L1.
- Symbol: `lantern_api_answer` (`_lantern_api_answer` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `request`, `view`, `out`.

## Type `ApiView`

The values of the node that the answers show, filled by the binary before each answer. A text field is a length, then that many bytes.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `genesis_time` | u64 | |
| 8 | `genesis_validators_root` | Root | |
| 40 | `genesis_fork_version` | Version | 4 bytes, then 4 zero bytes |
| 48 | `head_slot` | u64 | |
| 56 | `head_root` | Root | |
| 88 | `proposer_index` | u64 | Of the head's header |
| 96 | `parent_root` | Root | |
| 128 | `state_root` | Root | |
| 160 | `body_root` | Root | |
| 192 | `signature` | BLSSignature | Of the head's block; zero for an anchor with no block |
| 288 | `previous_justified` | Checkpoint | Epoch, then root |
| 328 | `current_justified` | Checkpoint | |
| 368 | `finalized` | Checkpoint | |
| 408 | `current_slot` | u64 | The slot of the clock |
| 416 | `is_syncing` | u64 | 1 or 0 |
| 424 | `is_optimistic` | u64 | 1 or 0 |
| 432 | `el_offline` | u64 | 1 or 0 |
| 440 | `peers` | u64 | Connected peers |
| 448 | `seq_number` | u64 | Of the node's MetaData |
| 456 | `attnets` | 8 bytes | |
| 464 | `syncnets` | 1 byte | Then 7 zero bytes |
| 472 | `custody_group_count` | u64 | |
| 480 | `fork` | u64 | `FORK_*` of the head |
| 488 | `peer_id` | text of 64 bytes | Base58btc |
| 560 | `enr` | text of 512 bytes | `enr:` and base64url |
| 1080 | `p2p_address` | text of 128 bytes | A multiaddr, or length 0 |
| 1216 | `discovery_address` | text of 128 bytes | A multiaddr, or length 0 |
| 1352 | `version` | text of 64 bytes | |
| 1424 | | | Size |

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_api_answer`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
