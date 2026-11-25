# Network config

## Contents

### Functions

- [`lantern_config_parse`](#function-lantern_config_parse): the values of a network config file.
- [`lantern_config_hex_bytes`](#function-lantern_config_hex_bytes): reads a value of 0x and hex digits of a number of bytes.
- [`lantern_config_name_is`](#function-lantern_config_name_is): whether two byte strings are equal.
- [`lantern_config_scan`](#function-lantern_config_scan): checks a config text, and writes its values into a config.
- [`lantern_config_text`](#function-lantern_config_text): reads a text value of a config.
- [`lantern_config_u64`](#function-lantern_config_u64): reads a u64 value of a config.
- [`lantern_config_uint256`](#function-lantern_config_uint256): reads a Uint256 value of a config.
- [`lantern_config_unquote`](#function-lantern_config_unquote): a config value without a pair of quotes.
- [`lantern_config_value`](#function-lantern_config_value): reads a config value of a kind.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/configs/README.md).
- Section: Configurations, Format: each configuration is a key and value mapping in YAML; a key is in `UPPER_SNAKE_CASE`; a value is an unsigned integer or a hexadecimal string with the prefix `0x`; comments may describe the values.
- The pinned `configs/mainnet.yaml` and `configs/minimal.yaml` also hold `TERMINAL_TOTAL_DIFFICULTY` above 64 bits, quoted strings, the list of mappings `BLOB_SCHEDULE`, and the empty list `[]`.

## Function `lantern_config_parse`

Writes into a config the value of each key that a network config file gives and lantern reads.

### Signature

```
lantern_config_parse(text, config, line) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | `ByteList`: the bytes of the file |
| `config` | state | [`Config`](helpers.md#type-config): the values before; the values of the file after |
| `line` | output | u64: the number of the first faulty line, from 1, or 0 |

### Returns

- `LANTERN_OK`: `config` holds the values of the file, and the values before for keys the file does not give; `line` is 0.
- `LANTERN_INVALID_CONFIG`: `line` holds the number of the first line that:
  - starts with a byte other than a space, and is not `KEY:` with nothing or a value after it;
  - gives a key lantern reads a value outside its kind, a quote with no end included;
  - is indented under a key lantern reads, other than `BLOB_SCHEDULE`;
  - under `BLOB_SCHEDULE`, is not an entry line, gives a field twice in an entry, or starts entry 33;
  - starts an entry of `BLOB_SCHEDULE` that ends without both fields.

### Caller must

- Fill `config` with the values to keep for keys the file does not give, such as the pinned config of the preset.

### Function does

- Splits the text into lines at each LF, and drops a CR before an LF.
- Takes a `#` at the start of a line, or after a space or tab and outside quotes, and the bytes after it to the line end, as a comment, and drops them. Drops the spaces and tabs at the end of a line. Skips a line that is then empty, and a line that is `---`.
- Reads a line that starts with a byte other than a space as `KEY:`, then nothing, or one or more spaces and a value. A key is one or more of `A` to `Z`, `a` to `z`, `0` to `9` and `_`.
- Gives each line that starts with a space to the key before it.
- Skips a key that lantern does not read, with its value and its indented lines.
- Reads the value of a key that lantern reads, without its quotes when it is inside a pair of `'` or a pair of `"`, by the kind of the key:
  - u64: decimal digits of a number below 2^64, or `0x` and 1 to 16 hex digits.
  - Version: `0x` and 8 hex digits: the 4 bytes in that order, then 4 zero bytes.
  - Uint256: decimal digits of a number below 2^256, little endian.
  - Hash32: `0x` and 64 hex digits: the 32 bytes in that order.
  - Address: `0x` and 40 hex digits of either case: the 20 bytes in that order, then 12 zero bytes.
  - Text: 0 to 64 bytes, each 0x20 to 0x7e but `"` and `\`: their count as a u64, then the bytes, then zero bytes to 64.
- Reads the keys of [`Config`](helpers.md#type-config): each `CONFIG_*` name of include/lantern.inc whose key is that name, by the kinds of `CONFIG_KEYS`.
- Reads `BLOB_SCHEDULE` as `[]`, or as nothing followed by indented entries. An entry starts with a line `- EPOCH: n` or `- MAX_BLOBS_PER_BLOCK: n`; a line indented past its `-` gives its other field; each entry has both, u64 values. The entries replace the schedule, sorted by EPOCH, keeping the file order for equal EPOCH values.
- With a key given twice, keeps the last value.
- Checks every line before it writes a value, and writes nothing when a line is faulty.

### Function never

- Writes `config` when it returns `LANTERN_INVALID_CONFIG`.
- Reads past the `count` bytes of `text`.
- Makes an OS call.

### Effects

- None outside `config` and `line`.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.
- `CONFIG_BLOB_SCHEDULE_MAX` (32) schedule entries.

### ABI

- Role: L0.
- Symbol: `lantern_config_parse`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `text`, `config`, `line`.

## Function `lantern_config_hex_bytes`

Reads a value of 0x and hex digits of a number of bytes.

### Signature

```
lantern_config_hex_bytes(start, end, out, n) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the value's first byte |
| `end` | input | the address after its last byte |
| `out` | output | `n` bytes |
| `n` | input | u64 in a register |

### Function does

- Returns 0 when the bytes are "0x" and 2 * `n` hex digits, whose `n` bytes go to `out` in order; else 1.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_config_hex_bytes`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, rdx, rdi, r8, r9; a0, t0 to t3.
- Argument order: `start`, `end`, `out`, `n`.

## Function `lantern_config_name_is`

Whether two byte strings are equal.

### Signature

```
lantern_config_name_is(a, a_n, b, b_n) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | `a_n` bytes |
| `a_n` | input | u64 in a register |
| `b` | input | `b_n` bytes |
| `b_n` | input | u64 in a register |

### Function does

- Returns 1 when the bytes are equal, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_config_name_is`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9, x10; rax, rdx, rsi, rdi; a0, t0, t1.
- Argument order: `a`, `a_n`, `b`, `b_n`.

## Function `lantern_config_scan`

Checks a config text, and writes its values into a config.

### Signature

```
lantern_config_scan(text, config, write) -> line
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | ByteList: the config text |
| `config` | output | [`Config`](helpers.md#type-config) |
| `write` | input | u64 in a register: 1 to write the values |

### Function does

- Returns 0, or the number of the first faulty line.
- With `write` 1, writes the values of the text into `config`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_config_scan`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `text`, `config`, `write`.

## Function `lantern_config_text`

Reads a text value of a config.

### Signature

```
lantern_config_text(start, end, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the value's first byte |
| `end` | input | the address after its last byte |
| `out` | output | a count and `CONFIG_TEXT_MAX` bytes, or 0 |

### Function does

- Returns 0 when the bytes are a text: 0 to `CONFIG_TEXT_MAX` bytes, each 0x20 to 0x7e but `"` and `\`; else 1.
- When `out` is not 0, writes the count, then the bytes, then zero bytes up to `CONFIG_TEXT_MAX`.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_config_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx, r8, r9; a0, t0 to t3.
- Argument order: `start`, `end`, `out`.

## Function `lantern_config_u64`

Reads a u64 value of a config.

### Signature

```
lantern_config_u64(start, end) -> (status, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the value's first byte |
| `end` | input | the address after its last byte |

### Function does

- Returns 0 and the value when the bytes are decimal digits, or "0x" and 1 to 16 hex digits, of a u64; else 1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_config_u64`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- The value comes back in x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x13; rax, rcx, rdx, rdi, r8 to r10; a0, a1, t0 to t4.
- Argument order: `start`, `end`.

## Function `lantern_config_uint256`

Reads a Uint256 value of a config.

### Signature

```
lantern_config_uint256(start, end, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the value's first byte |
| `end` | input | the address after its last byte |
| `out` | output | 32 bytes |

### Function does

- Returns 0 when the bytes are the decimal digits of a number below 2^256, and writes it little endian to `out`; else 1.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_config_uint256`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x14; rax, rcx, rdx, rdi, r8 to r10; a0, t0 to t6.
- Argument order: `start`, `end`, `out`.

## Function `lantern_config_unquote`

A config value without a pair of quotes.

### Signature

```
lantern_config_unquote(start, end) -> (status, start, end)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the value's first byte |
| `end` | input | the address after its last byte |

### Function does

- Returns 0 and the start and end of the bytes inside a pair of quotes, or of all the bytes when there are none; 1 for a quote with no end.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_config_unquote`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On ARM64 and RISC-V the values come back in x0 to x2 and a0 to a2; on x86-64 in rax, rdi and rsi.
- Registers it changes, on ARM64, x86-64, RISC-V: x0 to x2, x9, x10; rax, rcx, rsi, rdi; a0 to a2, t0 to t2.
- Argument order: `start`, `end`.

## Function `lantern_config_value`

Reads a config value of a kind.

### Signature

```
lantern_config_value(kind, start, end, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register: the value's kind |
| `start` | input | the value's first byte |
| `end` | input | the address after its last byte |
| `out` | output | 8 bytes (u64; a Version as 4 bytes and 4 zero bytes) or 32 bytes (Uint256, Hash32) |

### Function does

- Returns 0 when the bytes, without a pair of quotes, are a value of the kind, and writes it to `out`; else 1.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_config_value`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `kind`, `start`, `end`, `out`.

## Test vectors

- The pinned `configs/mainnet.yaml` and `configs/minimal.yaml`, whole: the result must be the values the YAML parser of the generator reads from them.
- Cases of tests/generator/config.py, each with its expected values or fault line:
  - Comments, single and double quotes, CR LF line ends, and `---`.
  - Keys lantern does not read, with nested lists and maps under them.
  - A `BLOB_SCHEDULE` out of EPOCH order, which must come out sorted, and `BLOB_SCHEDULE: []`.
  - A text with a few keys, which must leave every other value of the config as it was.
  - `DEPOSIT_CONTRACT_ADDRESS` in mixed case, and `CONFIG_NAME` and `PRESET_BASE` quoted, with a `#` inside quotes, and empty.
  - Faults: a value that is not a number, a u64 above 2^64 - 1, a Version of 3 bytes, a Hash32 of 31 bytes, an Address of 19 bytes, a Text of 65 bytes, a Text with a `"` inside `'`, 33 schedule entries, a schedule entry without `MAX_BLOBS_PER_BLOCK`, a line that is not a key, a quote with no end, and an indentation with a tab.
- File: `<preset>-phase0-config-parse.bin`.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_config_parse`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |
