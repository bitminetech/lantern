# lantern

An Ethereum consensus client, a beacon node, in assembly.

The beacon chain on mainnet, every fork from phase0 to Fulu: state transition, fork choice, data availability, gossip and req/resp, sync, the Engine API client and storage. It runs no validators.

Standard: [asm-standard@2a19d3f](https://github.com/bitminetech/asm-standard/blob/2a19d3f7fa737af1c01720b6e891703e53a682aa/ARCHITECTURE.md)

## Reference

| File | Covers |
|---|---|
| [docs/reference/helpers.md](docs/reference/helpers.md) | Beacon chain helpers of every fork, shuffling, domains and signing roots |
| [docs/reference/state.md](docs/reference/state.md) | Beacon state buffers |
| [docs/reference/epoch-processing.md](docs/reference/epoch-processing.md) | Epoch processing of every fork |
| [docs/reference/block-processing.md](docs/reference/block-processing.md) | Block processing of every fork |
| [docs/reference/state-transition.md](docs/reference/state-transition.md) | State transition of every fork |
| [docs/reference/fork-upgrades.md](docs/reference/fork-upgrades.md) | The upgrade of a state to each fork |
| [docs/reference/genesis.md](docs/reference/genesis.md) | The phase0 genesis state |
| [docs/reference/fork-choice.md](docs/reference/fork-choice.md) | Fulu fork choice and data availability |
| [docs/reference/networking.md](docs/reference/networking.md) | Fulu networking rules: custody, gossip validation |
| [include/lantern.inc](include/lantern.inc) | Constants |
| [include/types.inc](include/types.inc) | SSZ types and layouts of each fork, phase0 to Fulu |
| [include/forks.inc](include/forks.inc) | The forks, and the names of each fork's exports |

## Targets

| OS | ISAs |
|---|---|
| Linux | x86-64, ARM64, RISC-V |
| Windows | x86-64, ARM64 |
| macOS | x86-64, ARM64 |

## Dependencies

| Repo | Commit | Functions used |
|---|---|---|
| [asm-ssz](https://github.com/bitminetech/asm-ssz) | [`3c8c9b4`](https://github.com/bitminetech/asm-ssz/tree/3c8c9b405efe432bc0153aa3d0a9a5d31e6d3328) | `ssz_hash_tree_root` |
| [asm-crypto](https://github.com/bitminetech/asm-crypto) | [`e7e0731`](https://github.com/bitminetech/asm-crypto/tree/e7e0731e379102ad15b927f1558c93b0cb1c93d4) | `crypto_sha256`, `crypto_bls_verify`, `crypto_bls_fast_aggregate_verify`, `crypto_bls_eth_fast_aggregate_verify`, `crypto_bls_eth_aggregate_pubkeys`, `crypto_bls_g1_decode`, `crypto_bls_g1_neg`, `crypto_bls_g1_add`, `crypto_bls_g1_compress`, `crypto_kzg_verify_cell_kzg_proof_batch` |
| [asm-snappy](https://github.com/bitminetech/asm-snappy) | [`b84f65a`](https://github.com/bitminetech/asm-snappy/tree/b84f65a17f51dead69d22a7f6c5a16f7b2975d2a) | <Functions> |
| [asm-libp2p](https://github.com/bitminetech/asm-libp2p) | [`84d113b`](https://github.com/bitminetech/asm-libp2p/tree/84d113b76577806c9e76eb4b820be16282157b8a) | <Functions> |
| [asm-quic](https://github.com/bitminetech/asm-quic) | [`533cdb8`](https://github.com/bitminetech/asm-quic/tree/533cdb8a777a68b5397324cf73f41ff185e76b21) | <Functions> |
| [asm-discv5](https://github.com/bitminetech/asm-discv5) | [`ba3529f`](https://github.com/bitminetech/asm-discv5/tree/ba3529f0b1ca6b9ee276c1a3c1cb8d942c865da5) | <Functions> |
| [asm-rlp](https://github.com/bitminetech/asm-rlp) | [`40cca37`](https://github.com/bitminetech/asm-rlp/tree/40cca377a1621ed660a73724192a4a0b2c059a84) | <Functions> |

## Build tools

| Used for | Tool |
|---|---|
| Client | LLVM 23.1.5, official release (`clang`, `llvm-ar`, `lld`) |
| Signatures-off test runner | `llvm-objcopy` of the same LLVM 23.1.5 release |
| Windows tests | [llvm-mingw 20261104](https://github.com/mstorsjo/llvm-mingw/releases/tag/20261104) (LLVM 23.1.5) |
| macOS tests | The host Xcode clang, because they need the macOS SDK |
| Build image | [platform/linux/Dockerfile](platform/linux/Dockerfile) on `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2` |

## Tests

| Item | Location |
|---|---|
| Vector generator | [tests/generator/](tests/generator/) |
| Test runner | [tests/runner/](tests/runner/README.md) |
| Signatures-off runner, for cases with `bls_setting` 2 | [tests/runner/bls_off.c](tests/runner/bls_off.c) |
| CI, 7 targets | [.github/workflows/ci.yml](.github/workflows/ci.yml) |

## Target profile

| ISA | Instructions |
|---|---|
| x86-64 | x86-64-v1 |
| ARM64 | Armv8.0-A |
| RISC-V | RV64GC |

| Item | Value |
|---|---|
| macOS objects | Marked for macOS 11.0 or later |

## Environment boundaries

| OS | Call | Requirements |
|---|---|---|
| <OS> | <System call or API> | <Pinned requirements and remaining assumptions> |

## Stack

| Item | Value |
|---|---|
| Stack per call | <Cap, callees included> |

## Integration

| Item | Value |
|---|---|
| <Startup, event loop, actions, wakeup, storage, shutdown> | <Value> |
