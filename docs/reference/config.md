# Network config

## Contents

### Functions

- [`lantern_config_parse`](#function-lantern_config_parse): the values of a network config file.

## Spec

- Document: [consensus-specs v1.7.0-beta.4](https://github.com/ethereum/consensus-specs/tree/aa16bb4c156184e9548a997d53efaf2a228a6304/configs/README.md).
- Section: Configurations, Format: each configuration is a key and value mapping in YAML; a key is in `UPPER_SNAKE_CASE`; a value is an unsigned integer or a hexadecimal string with the prefix `0x`; comments may describe the values.
- The pinned `configs/mainnet.yaml` and `configs/minimal.yaml` also hold `TERMINAL_TOTAL_DIFFICULTY` above 64 bits, quoted strings, the list of mappings `BLOB_SCHEDULE`, and the empty list `[]`.

## Test vectors

- The pinned `configs/mainnet.yaml` and `configs/minimal.yaml`, whole: the result must be the values the YAML parser of the generator reads from them.
- Cases of tests/generator/config.py, each with its expected values or fault line:
  - Comments, single and double quotes, CR LF line ends, and `---`.
  - Keys lantern does not read, with nested lists and maps under them.
  - A `BLOB_SCHEDULE` out of EPOCH order, which must come out sorted, and `BLOB_SCHEDULE: []`.
  - A text with a few keys, which must leave every other value of the config as it was.
  - Faults: a value that is not a number, a u64 above 2^64 - 1, a Version of 3 bytes, a Hash32 of 31 bytes, 33 schedule entries, a schedule entry without `MAX_BLOBS_PER_BLOCK`, a line that is not a key, a quote with no end, and an indentation with a tab.
- File: `<preset>-phase0-config-parse.bin`.

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
- Reads the keys of [`Config`](helpers.md#type-config): each `CONFIG_*` name of include/lantern.inc whose key is that name, by the kinds of `CONFIG_KEYS`.
- Reads `BLOB_SCHEDULE` as `[]`, or as nothing followed by indented entries. An entry starts with a line `- EPOCH: n` or `- MAX_BLOBS_PER_BLOCK: n`; a line indented past its `-` gives its other field; each entry has both, u64 values. The entries replace the schedule, sorted by EPOCH, keeping the file order for equal EPOCH values.
- With a key given twice, keeps the last value.
- Checks every line before it writes a value, and writes nothing when a line is faulty.

### Function never

- Writes `config` when it returns `LANTERN_INVALID_CONFIG`.
- Reads past the `count` bytes of `text`.

### Effects

- None outside `config` and `line`.

### Limits

- `CONFIG_BLOB_SCHEDULE_MAX` (32) schedule entries.

### ABI

- Role: L1.
- Symbol: `lantern_config_parse` (`_lantern_config_parse` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `text`, `config`, `line`.

## Results

<!-- CI generates the tick table for each function here. -->
