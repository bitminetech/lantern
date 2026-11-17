# Engine API client

## Contents

### Functions

- [`lantern_jwt_token`](#function-lantern_jwt_token): the JWT of an Engine API request.
- [`lantern_http_post`](#function-lantern_http_post): the HTTP/1.1 request of a JSON-RPC call.
- [`lantern_http_parse_response`](#function-lantern_http_parse_response): the status and body of an HTTP/1.1 response.

### Types

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
- lantern_jwt_token, lantern_http_post and lantern_http_parse_response read no fork's layouts. Each is in the common object of the core (asm/core/<ISA>/common.s), and its symbol is its name.

## Test vectors

- Lantern's cases, `<preset>-<fork>-engine-<function>.bin` of phase0 to fulu, made by tests/generator/engine.py: no official cases test these functions.
  - JWTs: the token of RFC 7519 with Python's `hmac`, `hashlib` and `base64` modules.
  - HTTP responses: messages that follow RFC 9112, split at every byte to test the `LANTERN_HTTP_MORE` results, and malformed ones.

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

## Type `HttpResponse`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `status` | u64 | The status code |
| 8 | `consumed` | u64 | The bytes of `input` the response took |

## Results

<!-- CI generates the tick table for each function here. -->
