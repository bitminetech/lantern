# Vector generator

## Run

```bash
tests/generator/run.sh ~/.cache/lantern/vectors
```

- The output folder must be outside this repo.
- It runs in the image from [platform/linux/Dockerfile](../../platform/linux/Dockerfile).
- The output folder keeps the downloads (`sources/`), the consensus-specs and beacon-APIs clones and the Python environment. A second run downloads nothing.
- Fork names after the folder, such as `fulu`, convert only those forks; spec test runner names, such as `fork_choice_compliance`, only those runners. The other entries of `manifest.txt` stay.
- A run with no names leaves only its own `.bin` files in the folder.

## Files

| File | What it holds |
|---|---|
| `run.sh` | Runs the generator in Docker |
| `generate.py` | Fetches the archives, checks their pins, writes the case files |
| `requirements.txt` | Python packages, pinned |
| `p2p.py` | The cases of the p2p helpers, from the pinned spec modules |
| `engine.py` | The cases of the Engine API client: JWTs, HTTP requests and responses |
| `reqresp.py` | The cases of the req/resp encoding, and the req/resp message types of the spec's text |
| `node.py` | The cases of the node core: an anchor, and the Status and MetaData the node answers over libp2p; the Beacon API requests and the response of each; the blob sidecars of the spec's fork choice cases with blobs |
| `config.py` | The cases of lantern_config_parse: the pinned spec configs, and hand cases with their values or fault lines |
| `app.py` | The cases of lantern_app_options: command lines with their options or fault index |
| `http_request.py` | The cases of lantern_http_request: connection bytes and the request or fault of each |
| `json_codec.py` | The cases of lantern_json_encode and lantern_json_decode: values of every container type of each fork's spec module and the JSON of each; texts that break one rule each, with their faults |
| `api_route.py` | The cases of lantern_api_route: requests and the route or fault of each; reads the operations from the beacon-APIs clone |

## Sources

| Archive | What it gives |
|---|---|
| `mainnet.tar.gz`, `minimal.tar.gz` of consensus-specs v1.7.0-beta.4 | The cases of phase0 to fulu of every runner in scope |
| `comptests.tar.gz` of the same release | The fork choice compliance cases of altair to fulu, minimal only |
| The consensus-specs clone at aa16bb4 | The type descriptors, the configs, the KZG trusted setup, and the expected results of the p2p helper cases and the node cases |
| The beacon-APIs clone at 88fc940 (v4.0.0) | The operations and parameters of the Beacon API, for the route cases |

- Each archive's SHA-256 is pinned in `generate.py`.

## Output

| File | Cases |
|---|---|
| `<preset>-<fork>-<runner>-<handler>.bin` | The spec's cases of one handler of one fork: each case's files as parts |
| `<preset>-<fork>-p2p-<function>.bin` | Lantern's cases of one p2p helper of networking.md: `config` (the values that replace the preset's), `input`, and `output`, null where the spec raises |
| `<preset>-<fork>-reqresp-<function>.bin` | Lantern's cases of one function of req-resp.md: `input`, and `output`, null or a string (`more`, `invalid`) where the function refuses the input |
| `<preset>-<fork>-engine-<function>.bin` | Lantern's cases of one function of engine-api.md: `input`, and `output`, or a string (`more`, `invalid`) where the function refuses the input |
| `<preset>-<fork>-node-p2p.bin` | Lantern's node cases over libp2p, altair to fulu: `anchor_state`, `anchor_block`, and the `status` and `metadata` the node answers |
| `<preset>-<fork>-node-api.bin` | Lantern's Beacon API cases of the node, altair to fulu: `anchor_state`, `anchor_block`, `identity`, `time_ms`, the lists `names`, `requests` and `responses`, `closes` (a byte for each request: 1 when it closes), and `offline`, the index of the first request after a failed execution engine connection |
| `<preset>-<fork>-node-blobs.bin` | Lantern's blob sidecars of the spec's `fork_choice-on_block` cases with blobs, deneb and electra: a part for each block file; made in a run with the `fork_choice` cases |
| `<preset>-<fork>-descriptors.bin` | Each SSZ container type of the fork, and each req/resp message type, with its reference `TypeDescriptor` |
| `<preset>-config.bin` | One case: `configs/<preset>.yaml` |
| `<preset>-phase0-config-parse.bin` | Lantern's cases of lantern_config_parse (config.md): `text`, the bytes of a config file, and `config`, the values it gives, or `line`, its first faulty line |
| `<preset>-<fork>-json-encode.bin` | Lantern's cases of lantern_json_encode (beacon-api.md): `type`, a container's name, `ssz`, a value's SSZ bytes, and `json`, its JSON |
| `<preset>-<fork>-json-decode.bin` | Lantern's cases of lantern_json_decode (beacon-api.md): `type`, `json`, and `ssz`, the encoding it must give, or `fault_kind`, `fault_offset` and `fault_path` |
| `<preset>-phase0-http-request.bin` | Lantern's cases of lantern_http_request (beacon-api.md): `bytes`, `head_max`, `body_max`, the `status` and `http_status`, `prefix`, the status of each shorter length, and the request's fields and parts |
| `<preset>-phase0-api-route.bin` | Lantern's cases of lantern_api_route (beacon-api.md): the request's `method` and parts, `status`, and `out`, the whole ApiRoute, or `http_status`, `fault`, `allow` and `op` |
| `<preset>-phase0-app-options.bin` | Lantern's cases of lantern_app_options (app.md): `args`, a command line, and `options`, the fields it gives, or `fault`, the index of its first faulty argument |
| `<preset>-kzg_setup.bin` | One case: the three point lists of `trusted_setup_4096.json` as bytes |
| `network/` | The network directory of the binary's start tests (tests/app/start.sh, start.ps1): tests/app/network.py of minimal and altair, 4096 validators at slot 0; made in a run with phase0 and the `app` cases |
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
