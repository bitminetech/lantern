# Beacon API

## Contents

### Functions

- [`lantern_api_answer`](#function-lantern_api_answer): the HTTP response to a Beacon API request.
- [`lantern_api_route`](#function-lantern_api_route): finds the operation of a request and reads its parameters.
- [`lantern_http_request`](#function-lantern_http_request): reads one HTTP/1.1 request, head and body, from a connection's bytes.

### Types

- [`ApiRoute`](#type-apiroute): the operation of a request and its parameters.
- [`ApiView`](#type-apiview): the values of the node that the answers show.
- [`HttpLimits`](#type-httplimits): the largest request head and body a connection takes.
- [`HttpRequest`](#type-httprequest): one request, read.
- [`ValidatorRef`](#type-validatorref): a validator by index or by public key.

## Spec

- Document: [beacon-APIs v4.0.0](https://github.com/ethereum/beacon-APIs/tree/v4.0.0).
- Section: the endpoints below, of `apis/node/` and `apis/beacon/`, with the JSON of `types/`: numbers as decimal strings, byte strings as `0x` and lower case hex.
- The endpoints are those that ethereum-package and Assertoor read: `ethereum-package` waits for `/eth/v1/node/health` to give 200 or 206, and reads `data.enr`, `data.p2p_addresses[0]` and `data.peer_id` of `/eth/v1/node/identity`.
- HTTP/1.1: RFC 9112. Each response closes its connection.
- Requests: [RFC 9112](https://www.rfc-editor.org/rfc/rfc9112) sections 2 to 7 (message format, request line, fields, body length, chunked coding) and [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) section 5 (field syntax); status 431 of [RFC 6585](https://www.rfc-editor.org/rfc/rfc6585) section 5.
- Routes: the 69 paths and 76 operations of `beacon-node-oapi.yaml` and `apis/` at beacon-APIs v4.0.0 (commit 88fc940), with their parameters of `params/index.yaml` and `apis/`; percent-encoding of [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) section 2.1; `Accept` of RFC 9110 section 12.5.1; `Content-Type` of RFC 9110 section 8.3.

## Test vectors

- tests/generator/api.py: views, requests, and the response bytes of each, written out by the rules below. File: `<preset>-phase0-api-answer.bin`.
- tests/generator/http_request.py: requests and the `HttpRequest` or fault of each, by the rules of lantern_http_request, apart from the assembly. Each case also runs with its bytes cut short at every length (`LANTERN_HTTP_MORE`, or the same fault once the faulty byte is in), and with `out` one byte short. File: `<preset>-phase0-http-request.bin`.
  - Request lines: each method, origin forms with and without a query, both versions, HTTP/2.0 (505), and broken lines.
  - Fields: each read field, names in mixed case, repeated lines joined, white space before a colon, folded lines, no `Host`, two `Host` lines.
  - Bodies: `Content-Length` (zero, exact, past `body_max`, two equal values, two different values), chunked (one and many chunks, extensions, trailers, bad sizes, past `body_max`), both fields together, another coding.
  - Limits: a head of exactly `head_max` bytes and one byte more.
  - Pipelining: two requests in one buffer; `used` ends the first.
- tests/generator/api_route.py: requests and the `ApiRoute` or fault of each, by the rules of lantern_api_route, apart from the assembly. It reads the operations from the beacon-APIs clone at the pinned commit, so the table of the assembly is checked against the spec; a parameter of the spec that the rules below do not name stops it. Each case with `LANTERN_OK` also runs with `out` one byte short. File: `<preset>-phase0-api-route.bin`.
  - Every operation: its method and path with every required parameter; then each optional parameter.
  - Every path: each other method (405, `allow`), a trailing `/`, a missing and an extra segment (404).
  - Every parameter: each form of its type, and values that break it (400 and `fault`).
  - Query: repeated names, comma lists, empty items, names the operation does not take, percent-encoding (good and broken), 65 ids (414).
  - Headers: `Accept` with q-values, wildcards, parameters and broken items (406); `Content-Type` (415); `Eth-Consensus-Version` of each fork, missing and wrong (400).

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
  7. `Eth-Consensus-Version`, then `Content-Type`, then `Accept`.
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
| 456 | `list` | PartRef | `id`: `ValidatorRef` items; `indices`: u64 items; `versioned_hashes`: Root items |
| 472 | `peer_id` | PartRef | The bytes of `peer_id` |

### Rules

- The fixed part is `API_ROUTE_FIXED` (488) bytes.
- An operation takes at most one of `state_id`, `block_id` and `block_root`; one of the three roots; and one list.

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

### `lantern_api_answer`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
