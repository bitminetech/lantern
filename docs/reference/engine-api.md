# Engine API client

## Contents

### Functions

- [`lantern_get_execution_requests_list`](#function-lantern_get_execution_requests_list): the request lists of a block, as the execution layer takes them.
- [`lantern_engine_new_payload_size`](#function-lantern_engine_new_payload_size): the room lantern_engine_new_payload needs.
- [`lantern_engine_new_payload`](#function-lantern_engine_new_payload): the JSON-RPC request of engine_newPayload for a block.
- [`lantern_engine_forkchoice_updated`](#function-lantern_engine_forkchoice_updated): the JSON-RPC request of engine_forkchoiceUpdated.
- [`lantern_engine_exchange_capabilities`](#function-lantern_engine_exchange_capabilities): the JSON-RPC request of engine_exchangeCapabilities.
- [`lantern_engine_parse_response`](#function-lantern_engine_parse_response): the result of a JSON-RPC response.
- [`lantern_jwt_token`](#function-lantern_jwt_token): the JWT of an Engine API request.
- [`lantern_http_post`](#function-lantern_http_post): the HTTP/1.1 request of a JSON-RPC call.
- [`lantern_http_parse_response`](#function-lantern_http_parse_response): the status and body of an HTTP/1.1 response.

### Types

- [`ForkchoiceState`](#type-forkchoicestate): the three block hashes of engine_forkchoiceUpdated.
- [`EngineResponse`](#type-engineresponse): the result of a JSON-RPC response.
- [`HttpResponse`](#type-httpresponse): the parts of an HTTP/1.1 response.

## Spec

- Document: [execution-apis 981aa66](https://github.com/ethereum/execution-apis/tree/981aa66d79364be8322a9c358aaf0a571cca0873/src/engine): `common.md`, `authentication.md`, `paris.md`, `shanghai.md`, `cancun.md`, `prague.md`, `osaka.md`.
- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs): `get_execution_requests_list` and `kzg_commitment_to_versioned_hash` of electra and deneb `beacon-chain.md`, and the `NewPayloadRequest` of each fork.
- Document: [RFC 7519](https://www.rfc-editor.org/rfc/rfc7519) JWT and [RFC 7515](https://www.rfc-editor.org/rfc/rfc7515) JWS with HS256; [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112) HTTP/1.1 messages.

## Common rules

- As in [helpers.md](helpers.md#common-rules).
- A beacon node without validators calls three methods: engine_exchangeCapabilities, engine_newPayload and engine_forkchoiceUpdated, the latter with null payload attributes.
- The versions follow the fork of the block: bellatrix engine_newPayloadV1 and engine_forkchoiceUpdatedV1; capella V2 and V2; deneb V3 and V3; electra and fulu engine_newPayloadV4 and engine_forkchoiceUpdatedV3.
- JSON is written compact, with no spaces, in the field order of the spec's lists. A `QUANTITY` is lowercase hex with no leading zeros, `0x0` for zero; `DATA` is lowercase hex, two digits a byte.
- lantern_get_execution_requests_list, lantern_engine_new_payload_size, lantern_engine_new_payload and lantern_engine_forkchoice_updated read the fork's layouts, and are in the objects of bellatrix and later (electra and later for the first). lantern_engine_exchange_capabilities, lantern_engine_parse_response, lantern_jwt_token, lantern_http_post and lantern_http_parse_response read no fork's layouts. Each is in the common object of the core (asm/core/<ISA>/common.s), and its symbol is its name.

## Test vectors

- Lantern's cases, `<preset>-<fork>-engine-<function>.bin` of phase0 to fulu, made by tests/generator/engine.py: no official cases test these functions.
  - Requests: random blocks of the fork from the spec's `debug/random_value.py`, in each of its modes, and the JSON that the encoding rules of `common.md` give for them, with `kzg_commitment_to_versioned_hash` and `get_execution_requests_list` of the spec module.
  - Responses: JSON-RPC responses of each method that Python's `json` module writes with several spacings and member orders, with members the parser ignores, and with values the spec does not allow.
  - JWTs: the token of RFC 7519 with Python's `hmac`, `hashlib` and `base64` modules.
  - HTTP responses: messages that follow RFC 9112, split at every byte to test the `LANTERN_HTTP_MORE` results, and malformed ones.

## Function `lantern_get_execution_requests_list`

request_type + ssz_serialize(requests) for the deposits, the withdrawals and the consolidations of execution_requests, in that order, each list that is not empty.

### Signature

```
lantern_get_execution_requests_list(execution_requests, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `execution_requests` | input | `ExecutionRequests` |
| `out` | output | `ByteList`, its `size` set by the caller: for each element, its length as a u64, then its bytes |

### Returns

- `LANTERN_OK`: `out` holds the elements.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer bytes than the elements and their lengths.

### ABI

- Argument order: `execution_requests`, `out`.
- Forks: electra and later.

## Function `lantern_engine_new_payload_size`

The room in bytes that lantern_engine_new_payload needs for block: 4096 + for each transaction 8 + twice its bytes + twice the bytes of extra_data + 160 for each withdrawal + 72 for each blob commitment + for each request list 8 + twice its bytes.

### Signature

```
lantern_engine_new_payload_size(block, out) -> status
```

### Returns

- `LANTERN_OK`, always.

### ABI

- Argument order: `block`, `out`.
- Forks: bellatrix and later.

## Function `lantern_engine_new_payload`

The JSON-RPC request `{"jsonrpc":"2.0","id":id,"method":"engine_newPayloadVn","params":[...]}` of the execution payload of block.

### Signature

```
lantern_engine_new_payload(block, id, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `block` | input | `BeaconBlock` |
| `id` | input | u64: the JSON-RPC id |
| `scratch` | scratch | `Scratch` |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the request.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer bytes than lantern_engine_new_payload_size gives, or `scratch` has fewer than 64 bytes more than the request lists.

### Function does

- Bellatrix: engine_newPayloadV1 with the `ExecutionPayloadV1`. Capella: V2 with the `ExecutionPayloadV2`, its `withdrawals`. Deneb: V3 with the `ExecutionPayloadV3`, its `blobGasUsed` and `excessBlobGas`, the versioned hashes of `blob_kzg_commitments` and the block's `parent_root`. Electra and fulu: V4, which adds lantern_get_execution_requests_list of `execution_requests`.

### ABI

- Argument order: `block`, `id`, `scratch`, `out`.
- Forks: bellatrix and later.

## Function `lantern_engine_forkchoice_updated`

The JSON-RPC request `{"jsonrpc":"2.0","id":id,"method":"engine_forkchoiceUpdatedVn","params":[{"headBlockHash":...,"safeBlockHash":...,"finalizedBlockHash":...},null]}`: V1 for bellatrix, V2 for capella, V3 for deneb and later.

### Signature

```
lantern_engine_forkchoice_updated(state, id, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `ForkchoiceState` |
| `id` | input | u64 |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the request.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than 512 bytes.

### ABI

- Argument order: `state`, `id`, `out`.
- Forks: bellatrix and later.

## Function `lantern_engine_exchange_capabilities`

The JSON-RPC request of engine_exchangeCapabilities with the methods lantern calls: engine_newPayloadV1 to V4 and engine_forkchoiceUpdatedV1 to V3.

### Signature

```
lantern_engine_exchange_capabilities(id, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the request.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than 512 bytes.

### ABI

- Argument order: `id`, `out`.

## Function `lantern_engine_parse_response`

The id and the result or error of the JSON-RPC response body of a call of method.

### Signature

```
lantern_engine_parse_response(body, method, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `body` | input | `ByteList`: the HTTP body |
| `method` | input | u64: `ENGINE_METHOD_*` of include/lantern.inc, the method called |
| `out` | output | `EngineResponse` |

### Returns

- `LANTERN_OK`: `out` holds the response.
- `LANTERN_INVALID_JSON`: the body is not one JSON object with an integer `id` and a `result` or an `error` of the method's form. `out` is not valid.

### Function does

- Takes JSON as RFC 8259 writes it, with whitespace between tokens and around the object, and nothing after it.
- Ignores every member it does not read, `jsonrpc` and `validationError` included, whatever its value.
- Takes `error` before `result` when the object has both. An `error` needs an integer `code` from -2^63 to 2^63 - 1.
- engine_newPayload: `result` is a `PayloadStatusV1`: `status` is one of the five strings, and `latestValidHash` is a 32 byte `DATA`, or null, or absent.
- engine_forkchoiceUpdated: `result` has a `PayloadStatusV1` in `payloadStatus`, and `payloadId` is an 8 byte `DATA`, or null, or absent.
- engine_exchangeCapabilities: `result` is an array of strings; each name of the methods lantern calls sets its bit, and other names are ignored.
- Takes a later member of the same name over an earlier one.
- Compares names and strings byte for byte: a string with an escape matches no name.

### ABI

- Argument order: `body`, `method`, `out`.

## Function `lantern_jwt_token`

The JWS compact serialization of the claims `{"iat":iat}`, with the header `{"alg":"HS256","typ":"JWT"}` and the HMAC-SHA256 of secret: base64url(header) + `.` + base64url(claims) + `.` + base64url(mac), without padding.

### Signature

```
lantern_jwt_token(secret, iat, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `secret` | input | Bytes32: the 256 bit key of the `jwt-secret` file |
| `iat` | input | u64: the time in seconds |
| `scratch` | scratch | `Scratch` |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the token.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than 128 bytes, or `scratch` has fewer than 512 bytes.

### Function does

- Writes iat in decimal with no leading zeros.

### ABI

- Argument order: `secret`, `iat`, `scratch`, `out`.

## Function `lantern_http_post`

The bytes of an HTTP/1.1 POST of body to the path `/`, with the headers `Host`, `Content-Type: application/json`, `Authorization: Bearer` token, and `Content-Length`, in that order, each line ending in CR LF.

### Signature

```
lantern_http_post(host, token, body, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `host` | input | `ByteList`: the host and port, as `localhost:8551` |
| `token` | input | `ByteList`: from lantern_jwt_token |
| `body` | input | `ByteList`: the JSON-RPC request |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the request.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer bytes than the request.

### ABI

- Argument order: `host`, `token`, `body`, `out`.

## Function `lantern_http_parse_response`

The status code and the body of the HTTP/1.1 response at the start of `input`.

### Signature

```
lantern_http_parse_response(input, eof, body, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `input` | input | `ByteList`: the bytes of the connection not yet read |
| `eof` | input | u64: 1 when the server has closed the connection |
| `body` | output | `ByteList`, its `size` set by the caller: the body, with a chunked body joined |
| `out` | output | `HttpResponse` |

### Returns

- `LANTERN_OK`: `out` and `body` hold the response.
- `LANTERN_HTTP_MORE`: `input` ends before the response does, and `eof` is 0. Nothing is written.
- `LANTERN_INVALID_HTTP`: the status line, a header line or a chunk size line is not valid, `Content-Length` is not a decimal number or appears twice with two values, or the bytes end before the response does when `eof` is 1.
- `LANTERN_BUFFER_TOO_SMALL`: `body` has room for fewer bytes than the body.

### Function does

- Takes the status line `HTTP/1.` + one digit + a space + three digits, then a reason phrase of any bytes but CR and LF.
- Compares header names without regard to case, and takes off the spaces and tabs around a value.
- Takes the body from `Transfer-Encoding: chunked` first, then `Content-Length`, else every byte to the end of the connection, as RFC 9112 section 6.3 orders them.
- Of a chunked body, ignores chunk extensions and the trailer section.
- Takes a status of 1xx as a response with no body, which the caller skips.

### ABI

- Argument order: `input`, `eof`, `body`, `out`.

## Type `ForkchoiceState`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `head_block_hash` | Hash32 | The payload block hash of the head |
| 32 | `safe_block_hash` | Hash32 | Of the safe block |
| 64 | `finalized_block_hash` | Hash32 | Of the finalized block |

## Type `EngineResponse`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `id` | u64 | The response's id |
| 8 | `error` | u64 | 1 for an error response, else 0 |
| 16 | `error_code` | i64 | The error's code |
| 24 | `status` | u64 | `ENGINE_STATUS_*` of the `PayloadStatusV1`, else 0 |
| 32 | `has_latest_valid_hash` | u64 | 1 when `latestValidHash` is not null |
| 40 | `latest_valid_hash` | Hash32 | |
| 72 | `has_payload_id` | u64 | 1 when `payloadId` is not null |
| 80 | `payload_id` | 8 bytes | |
| 88 | `capabilities` | u64 | Bits 0 to 3: engine_newPayloadV1 to V4; bits 4 to 6: engine_forkchoiceUpdatedV1 to V3 |

- `EngineResponse__mem` (96) bytes.

| Status | `status` |
|---|---|
| `ENGINE_STATUS_VALID` (1) | `VALID` |
| `ENGINE_STATUS_INVALID` (2) | `INVALID` |
| `ENGINE_STATUS_SYNCING` (3) | `SYNCING` |
| `ENGINE_STATUS_ACCEPTED` (4) | `ACCEPTED` |
| `ENGINE_STATUS_INVALID_BLOCK_HASH` (5) | `INVALID_BLOCK_HASH` |

## Type `HttpResponse`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `status` | u64 | The status code |
| 8 | `consumed` | u64 | The bytes of `input` the response took |

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_get_execution_requests_list`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_engine_new_payload_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_engine_new_payload`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_engine_forkchoice_updated`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_engine_exchange_capabilities`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_engine_parse_response`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_jwt_token`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_http_post`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_http_parse_response`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
