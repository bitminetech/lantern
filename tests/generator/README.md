# Vector generator

## Run

```bash
tests/generator/run.sh ~/.cache/lantern/vectors
```

- The output folder must be outside this repo.
- It runs in the image from [platform/linux/Dockerfile](../../platform/linux/Dockerfile).
- The output folder keeps the downloads (`sources/`), the consensus-specs clone and the Python environment. A second run downloads nothing.
- Spec test runner names after the folder, such as `fork_choice_compliance`, convert only those runners. The other entries of `manifest.txt` stay.

## Files

| File | What it holds |
|---|---|
| `run.sh` | Runs the generator in Docker |
| `generate.py` | Fetches the archives, checks their pins, writes the case files |
| `requirements.txt` | Python packages, pinned |

## Sources

| Archive | What it gives |
|---|---|
| `mainnet.tar.gz`, `minimal.tar.gz` of consensus-specs v1.7.0-beta.4 | The fulu cases of every runner in scope, and the phase0 shuffling cases |
| `comptests.tar.gz` of the same release | The fulu fork choice compliance cases, minimal only |
| The consensus-specs clone at aa16bb4 | The type descriptors, the configs and the KZG trusted setup |

- Each archive's SHA-256 is pinned in `generate.py`.

## Output

| File | Cases |
|---|---|
| `<preset>-<runner>-<handler>.bin` | The spec's cases of one handler: each case's files as parts |
| `<preset>-descriptors.bin` | Each SSZ container type of fulu with its reference `TypeDescriptor` |
| `<preset>-config.bin` | One case: `configs/<preset>.yaml` |
| `<preset>-kzg_setup.bin` | One case: the three point lists of `trusted_setup_4096.json` as bytes |
| `manifest.txt` | Each file, its case count and its SHA-256 |

- `<preset>`: `mainnet` or `minimal`.

## File format

| Part | Content |
|---|---|
| Magic | The 8 bytes `LANTVEC1` |
| Cases | u64 count, then each case: its name as a blob, then its parts as a tagged value |

- u64 is 8 bytes, little endian.
- A blob is a u64 length, then that many bytes.
- The parts of a spec case are a map from each file name without its extension to its content: a `.yaml` file as its value, an `.ssz_snappy` file as its SSZ bytes.

A tagged value is one tag byte, then:

| Tag | Kind | Then |
|---|---|---|
| 1 | Integer from 0 to 2^64 - 1 | u64 |
| 2 | Bytes, and a `0x` hex string | A blob |
| 3 | String | A blob of UTF-8 |
| 4 | Boolean | 1 byte, 0 or 1 |
| 5 | List | u64 count, then each value |
| 6 | Map | u64 count, then each key as a blob and its value |
| 7 | Null | Nothing |
| 8 | Integer from 2^64 to 2^256 - 1 | 32 bytes, little endian |
| 9 | Integer from -2^63 to -1 | 8 bytes, two's complement, little endian |
