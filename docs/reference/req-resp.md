# Req/resp encoding

## Contents

### Functions

- [`lantern_reqresp_protocol_parse`](#function-lantern_reqresp_protocol_parse): the method and version of a protocol ID.
- [`lantern_reqresp_protocol_id`](#function-lantern_reqresp_protocol_id): the protocol ID of a method and version.
- [`lantern_reqresp_chunk_size`](#function-lantern_reqresp_chunk_size): the most bytes one encoded chunk takes.
- [`lantern_reqresp_write_chunk`](#function-lantern_reqresp_write_chunk): appends one encoded request or response chunk.
- [`lantern_reqresp_read_header`](#function-lantern_reqresp_read_header): reads the result, context bytes and length of a chunk.
- [`lantern_reqresp_read_payload`](#function-lantern_reqresp_read_payload): reads the SSZ bytes of a chunk.
- [`lantern_ssz_size_bounds`](#function-lantern_ssz_size_bounds): the least and most SSZ bytes of a type.

### Types

- [`ReqRespProtocol`](#type-reqrespprotocol): a method and its version.
- [`ChunkHeader`](#type-chunkheader): the parts of a chunk before its payload.
- [`SizeBounds`](#type-sizebounds): the least and most SSZ bytes of a type.
- The message types of the methods: [include/types.inc](../../include/types.inc), Req/resp messages.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/specs).
- Section: `p2p-interface.md` of phase0, The Req/Resp domain: Protocol identification, Req/Resp interaction, Encoding strategies; of altair, Req-Resp interaction; the Messages of phase0, altair, deneb and fulu; Design decision rationale, What are SSZ type size bounds.

## Common rules

- As in [helpers.md](helpers.md#common-rules).
- A stream carries one request, then the chunks of its response. The functions here encode and decode one chunk; the caller keeps the stream's bytes and its state.
- Every function reads no fork's layouts. Each is in the common object of the core (asm/core/<ISA>/common.s), and its symbol is its name.

## Test vectors

- Lantern's cases, `<preset>-<fork>-reqresp-<function>.bin` of phase0 to fulu, made by tests/generator/reqresp.py: no official cases test the encoding.
  - The chunks come from the spec's text with python-snappy 0.7.3 framing: valid chunks of each message type, and chunks the spec calls invalid input (a length prefix over 10 bytes or over 2^64 - 1, a payload that ends early, a compressed payload over max_compressed_len, a bad frame).
  - The size bounds come from the SSZ types of the spec modules, by the rules of remerkleable's `min_byte_length` and `max_byte_length`, the reference that the spec's "What are SSZ type size bounds" links.
  - The message types of [include/types.inc](../../include/types.inc) also have reference descriptors in `<preset>-<fork>-descriptors.bin`, built from the spec's text by the same file.
  - lantern_reqresp_write_chunk has no expected bytes, since two Snappy compressors may differ: the runner reads each chunk it writes back with lantern_reqresp_read_header and lantern_reqresp_read_payload.

## Function `lantern_reqresp_protocol_parse`

The method and version of a protocol ID `/eth2/beacon_chain/req/` + the method name + `/` + the version + `/ssz_snappy`.

### Signature

```
lantern_reqresp_protocol_parse(id, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | `ByteList` |
| `out` | output | `ReqRespProtocol` |

### Returns

- `LANTERN_OK`: `out` holds the method and version.
- `LANTERN_INVALID_PROTOCOL`: the ID is not one of the protocols of [Type ReqRespProtocol](#type-reqrespprotocol). Nothing is written.

### ABI

- Argument order: `id`, `out`.

## Function `lantern_reqresp_protocol_id`

The protocol ID of a method and version.

### Signature

```
lantern_reqresp_protocol_id(protocol, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `protocol` | input | `ReqRespProtocol` |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the ID.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer bytes than the ID.
- `LANTERN_INVALID_PROTOCOL`: the method and version are not a protocol of the table.

### ABI

- Argument order: `protocol`, `out`.

## Function `lantern_reqresp_chunk_size`

The most bytes lantern_reqresp_write_chunk writes for a payload of n bytes: 1 + 4 + 10 + the size snappy_frame_compress_size gives, less its 24 byte header.

### Signature

```
lantern_reqresp_chunk_size(n, out) -> status
```

### Returns

- `LANTERN_OK`: `out` holds the size.
- `LANTERN_INVALID_OVERFLOW`: the size does not fit in a u64.

### ABI

- Argument order: `n`, `out`.

## Function `lantern_reqresp_write_chunk`

Appends one chunk after the bytes `out` holds: the result byte, the context bytes, the length of the payload as an unsigned protobuf varint, then the payload in Snappy frames.

### Signature

```
lantern_reqresp_write_chunk(header, payload, scratch, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `header` | input | `ChunkHeader`: `kind`, `result` and the context bytes; `length` is ignored |
| `payload` | input | `ByteList`: the SSZ bytes |
| `scratch` | scratch | `Scratch` |
| `out` | state | `ByteList`: its `size`, `offset` 24 and `count` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds its bytes, then the chunk.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than lantern_reqresp_chunk_size more bytes, or `scratch` has fewer than `SNAPPY_SCRATCH_FRAME` + 24 + lantern_reqresp_chunk_size bytes. `out` is unchanged.

### Function does

- A request chunk has no result byte and no context bytes. A response chunk with a result other than 0 has no context bytes, as altair p2p-interface.md says.
- Writes the shortest varint.
- Writes the frames that snappy_frame_compress of asm-snappy writes, through `scratch`, then copies them after the header.
- Writes no frame for an empty payload, not even the stream identifier: a reader takes 0 bytes for it, and the next bytes are the next chunk.

### ABI

- Argument order: `header`, `payload`, `scratch`, `out`.

## Function `lantern_reqresp_read_header`

The result byte, the context bytes and the payload length at the start of `input`.

### Signature

```
lantern_reqresp_read_header(input, header) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `input` | input | `ByteList`: the bytes of the stream not yet read |
| `header` | state | `ChunkHeader`: `kind` and `context_length` set by the caller |

### Returns

- `LANTERN_OK`: `header` holds the result, the context bytes, the length and the bytes it read.
- `LANTERN_REQRESP_MORE`: `input` ends before the header does. Nothing is written.
- `LANTERN_INVALID_CHUNK`: the length prefix has more than 10 bytes or does not fit in a u64.

### Function does

- Accepts a length prefix that is not the shortest: the spec says it SHOULD be the shortest.
- Reads no context bytes for a request, or for a response with a result other than 0.
- Leaves the check of the length against the type's bounds and `MAX_PAYLOAD_SIZE` to the caller, who knows the type.

### ABI

- Argument order: `input`, `header`.

## Function `lantern_reqresp_read_payload`

The `length` SSZ bytes of a chunk's payload, from the Snappy frames at the start of `input`.

### Signature

```
lantern_reqresp_read_payload(input, start, length, eof, scratch, out, consumed) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `input` | input | `ByteList`: the stream's bytes |
| `start` | input | u64: where the frames start in `input`, after the header |
| `length` | input | u64 |
| `eof` | input | u64: 1 when the peer has closed its side, so no more bytes come |
| `scratch` | scratch | `Scratch` |
| `out` | output | `ByteList`, its `size` set by the caller |
| `consumed` | output | u64: the bytes after `start` the frames took |

### Returns

- `LANTERN_OK`: `out` holds the `length` bytes.
- `LANTERN_REQRESP_MORE`: the frames end before `length` bytes, within max_compressed_len(`length`) bytes, and `eof` is 0.
- `LANTERN_INVALID_CHUNK`: `start` is after the end of `input`, a frame is not valid, the frames give more than `length` bytes, the frames end before `length` bytes when `eof` is 1, or they take more than max_compressed_len(`length`) bytes.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has room for fewer than `length` bytes, or `scratch` has fewer than 24 bytes plus the bytes it reads, rounded up to 8.

### Function does

- Reads at most max_compressed_len(`length`) bytes after `start`, as the spec says; it copies them to `scratch`, since asm-snappy reads a ByteList whose bytes start at an offset of 24.
- Reads no frame for a `length` of 0, so `consumed` is 0.
- Leaves the bytes after the frames to the caller: for a request, and for a response of one chunk, the spec takes more bytes as invalid input.

### ABI

- Argument order: `input`, `start`, `length`, `eof`, `scratch`, `out`, `consumed`.

## Function `lantern_ssz_size_bounds`

The least and the most bytes of the SSZ encoding of a type: the size bounds of the spec's Design decision rationale.

### Signature

```
lantern_ssz_size_bounds(type, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `type` | input | asm-ssz `TypeDescriptor` |
| `out` | output | `SizeBounds` |

### Returns

- `LANTERN_OK`: `out` holds the bounds; a maximum above 2^64 - 1 is 2^64 - 1.

### ABI

- Argument order: `type`, `out`.

## Type `ReqRespProtocol`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `method` | u64 | `REQRESP_*` of include/lantern.inc |
| 8 | `version` | u64 | The schema version |

| Method | Name | Versions |
|---|---|---|
| `REQRESP_STATUS` (1) | `status` | 1, 2 |
| `REQRESP_GOODBYE` (2) | `goodbye` | 1 |
| `REQRESP_BEACON_BLOCKS_BY_RANGE` (3) | `beacon_blocks_by_range` | 1, 2 |
| `REQRESP_BEACON_BLOCKS_BY_ROOT` (4) | `beacon_blocks_by_root` | 1, 2 |
| `REQRESP_PING` (5) | `ping` | 1 |
| `REQRESP_METADATA` (6) | `metadata` | 1, 2, 3 |
| `REQRESP_BLOB_SIDECARS_BY_RANGE` (7) | `blob_sidecars_by_range` | 1 |
| `REQRESP_BLOB_SIDECARS_BY_ROOT` (8) | `blob_sidecars_by_root` | 1 |
| `REQRESP_DATA_COLUMN_SIDECARS_BY_RANGE` (9) | `data_column_sidecars_by_range` | 1 |
| `REQRESP_DATA_COLUMN_SIDECARS_BY_ROOT` (10) | `data_column_sidecars_by_root` | 1 |
| `REQRESP_BEACON_BLOCKS_BY_HEAD` (11) | `beacon_blocks_by_head` | 1 |
| `REQRESP_LIGHT_CLIENT_BOOTSTRAP` (12) | `light_client_bootstrap` | 1 |
| `REQRESP_LIGHT_CLIENT_UPDATES_BY_RANGE` (13) | `light_client_updates_by_range` | 1 |
| `REQRESP_LIGHT_CLIENT_FINALITY_UPDATE` (14) | `light_client_finality_update` | 1 |
| `REQRESP_LIGHT_CLIENT_OPTIMISTIC_UPDATE` (15) | `light_client_optimistic_update` | 1 |

- `ReqRespProtocol__mem` (16) bytes.

## Type `ChunkHeader`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `kind` | u64 | `CHUNK_REQUEST` (0) or `CHUNK_RESPONSE` (1) |
| 8 | `context_length` | u64 | 0, or 4 for the `ForkDigest`-context of a response |
| 16 | `result` | u64 | The response code, 0 to 255; 0 for a request |
| 24 | `context` | 4 bytes, in a u64 | The context bytes |
| 32 | `length` | u64 | The length of the SSZ payload |
| 40 | `header_bytes` | u64 | The bytes before the payload |

- `ChunkHeader__mem` (48) bytes.

## Type `SizeBounds`

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `min` | u64 | The least bytes |
| 8 | `max` | u64 | The most bytes |

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_reqresp_protocol_parse`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_reqresp_protocol_id`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_reqresp_chunk_size`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_reqresp_write_chunk`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_reqresp_read_header`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_reqresp_read_payload`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_ssz_size_bounds`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ |  |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
