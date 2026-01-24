# ![Lantern](docs/assets/lantern_logo.svg)

[![CI](https://github.com/Pier-Two/lantern/actions/workflows/ci.yml/badge.svg)](https://github.com/Pier-Two/lantern/actions/workflows/ci.yml)
[![Docker Image Version](https://img.shields.io/docker/v/piertwo/lantern?sort=semver)](https://hub.docker.com/r/piertwo/lantern)
[![Docker Pulls](https://img.shields.io/docker/pulls/piertwo/lantern)](https://hub.docker.com/r/piertwo/lantern)

Lantern is a C implementation of [Lean Consensus](https://github.com/leanEthereum/leanSpec.git) for Ethereum.

## Requirements

Make sure you have the following tools installed before building.

- CMake 3.20+
- C compiler
- [Rust](https://www.rust-lang.org/tools/install) (for XMSS bindings)

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
./tools/fixtures/fill_consensus_fixtures.sh
```

Networking fixtures:

```sh
uv run --directory tools/leanSpec python ../../tools/fixtures/generate_networking_ssz.py
```

## License

MIT — see [LICENSE](LICENSE).
