# ![Lantern](docs/assets/lantern_logo.svg)

Lantern is a C implementation of [Lean Consensus](https://github.com/leanEthereum/leanSpec.git) for Ethereum.

## Requirements

Make sure you have the following tools installed before building.

- CMake 3.20+
- C compiler
- [Rust](https://www.rust-lang.org/tools/install) (for hash-sig bindings)

## Build

Configure and compile the project with CMake.

```sh
cmake -S . -B build
cmake --build build --parallel
```

## Test

Run the test suite to verify everything works correctly.

```sh
ctest --test-dir build --output-on-failure
```

## Regenerating Fixtures

Test fixtures are generated from LeanSpec. Use these scripts to refresh them.

Consensus fixtures:

```sh
./scripts/fixtures/fill_consensus_fixtures.sh
```

Networking fixtures:

```sh
cmake --build build --target lantern_generate_gossip_snappy
PYTHONPATH=tools/leanSpec/src python3 scripts/fixtures/generate_networking_ssz.py
```

## License

MIT — see [LICENSE](LICENSE).
