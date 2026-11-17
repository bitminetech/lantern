# Vector generator

## Run

```bash
tests/generator/run.sh ~/.cache/lantern/vectors
```

- The output folder must be outside this repo.
- It runs in the image from [platform/linux/Dockerfile](../../platform/linux/Dockerfile).
- The output folder keeps the downloads (`sources/`), the consensus-specs clone and the Python environment. A second run downloads nothing.
- Fork names after the folder, such as `fulu`, convert only those forks; spec test runner names, such as `fork_choice_compliance`, only those runners. The other entries of `manifest.txt` stay.
- A run with no names leaves only its own `.bin` files in the folder.

## Files

| File | What it holds |
|---|---|
| `run.sh` | Runs the generator in Docker |
| `generate.py` | Fetches the archives, checks their pins, writes the case files |
| `requirements.txt` | Python packages, pinned |
| `p2p.py` | The cases of the p2p helpers, from the pinned spec modules |
| `reqresp.py` | The cases of the req/resp encoding, and the req/resp message types of the spec's text |

## Sources

| Archive | What it gives |
|---|---|
| `mainnet.tar.gz`, `minimal.tar.gz` of consensus-specs v1.7.0-beta.4 | The cases of phase0 to fulu of every runner in scope |
| `comptests.tar.gz` of the same release | The fork choice compliance cases of altair to fulu, minimal only |
| The consensus-specs clone at aa16bb4 | The type descriptors, the configs, the KZG trusted setup, and the expected results of the p2p helper cases |

- Each archive's SHA-256 is pinned in `generate.py`.

## Output

| File | Cases |
|---|---|
| `<preset>-<fork>-<runner>-<handler>.bin` | The spec's cases of one handler of one fork: each case's files as parts |
| `<preset>-<fork>-p2p-<function>.bin` | Lantern's cases of one p2p helper of networking.md: `config` (the values that replace the preset's), `input`, and `output`, null where the spec raises |
| `<preset>-<fork>-reqresp-<function>.bin` | Lantern's cases of one function of req-resp.md: `input`, and `output`, null or a string (`more`, `invalid`) where the function refuses the input |
| `<preset>-<fork>-descriptors.bin` | Each SSZ container type of the fork, and each req/resp message type, with its reference `TypeDescriptor` |
| `<preset>-config.bin` | One case: `configs/<preset>.yaml` |
| `<preset>-kzg_setup.bin` | One case: the three point lists of `trusted_setup_4096.json` as bytes |
| `manifest.txt` | Each file, its case count and its SHA-256 |

- `<preset>`: `mainnet` or `minimal`.
- `<fork>`: `phase0`, `altair`, `bellatrix`, `capella`, `deneb`, `electra` or `fulu`.
- Runners in scope: every runner of the spec tests except `light_client` and `fast_confirmation`.
- The spec writes the `shuffling` cases for phase0 only. Each fork's `shuffling` file holds them, since every fork keeps those functions.

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
