# Devnet-2 Readiness Progress and Required Work

This document tracks what remains to make Lantern devnet-2 ready. It is intentionally detailed so the work can be split and executed in parallel. Update this file as items are completed or clarified.

## Current Status (Known)
- **c-leanvm-xmss bindings**: Implemented and tested (C example builds/runs on macOS and Linux). Submodule exists at `external/c-leanvm-xmss`.
- **XMSS aggregation API**: Exposed via C bindings, including aggregation proof encode/decode and verify.
- **Build tooling**: Makefile added for `c-leanvm-xmss`. `Cargo.lock` committed (important for dependency pinning).
- **Rust toolchain requirement**: `leansig` now uses edition2024, so a recent Rust/Cargo is required. Linux testing succeeded with `rust:latest` (Cargo 1.92).
- **LeanSpec audit (constants + wire formats)**: Updated gossipsub heartbeat interval (0.7s), fixed SSZ offsets for variable-length signatures (SignedAttestation + BlockSignatures), and regenerated fixtures/vectors.

## Required Work (High-Level)
1. **Integrate XMSS bindings into Lantern build**
2. **Replace devnet-1 signature/key paths with XMSS (devnet-2)**
3. **Align protocol constants and serialization with devnet-2 spec**
4. **Update aggregation flows (proof format, size expectations, verification)**
5. **Regenerate fixtures and update tests**
6. **Update CI/toolchain requirements**
7. **Confirm devnet-2 behavior end-to-end (node sync, block validation, consensus)**

## Detailed Task Breakdown

### 1) Build + Dependency Integration
- **Submodule update**: Ensure the parent repo points at the latest commit of `external/c-leanvm-xmss`.
- **CMake/Build system**:
  - Add include path for `external/c-leanvm-xmss/include`.
  - Link against `libleanvm_xmss_c` (static or shared).
  - Ensure rpath is set (macOS `@loader_path`, Linux `./target/release` or install path).
- **Headers**:
  - Ensure `leanvm-xmss.h` is installed/copied where Lantern expects public headers.
  - If Lantern relies on a single umbrella header, update it to include XMSS bindings.
- **Toolchain**:
  - Document Rust/Cargo minimum version (edition2024 requirement).
  - For builds inside CI/Docker, use a current Rust image (e.g., `rust:latest`).
  - Use `cargo build --locked` to keep dependency pins stable.

### 2) Replace Signature/Key Usage (Devnet-2 XMSS)
- **Key generation**:
  - Replace any devnet-1 keygen (hash-sig) paths with XMSS keygen.
  - Confirm activation epoch and lifetime parameters are pulled from devnet-2 spec.
- **Signing**:
  - Replace signing calls to use XMSS bindings.
  - Ensure message length (32 bytes) and epoch handling align with XMSS expectations.
- **Verification**:
  - Update all signature verification paths to use XMSS.
  - Update SSZ-based verification where public key/signature are serialized.
- **Serialization**:
  - Ensure key/signature serialization formats match devnet-2 spec (SSZ).
  - Confirm key and signature sizes (public key 52 bytes, signature 3112 bytes).

### 3) Protocol Constants and Wire Formats
- **LeanSpec review required**:
  - Identify devnet-2 changes in `tools/leanSpec` (message formats, epochs, domains, etc).
  - Update Lantern constants to match devnet-2 spec.
- **Consensus inputs**:
  - Confirm any hash-to-field or message hashing uses the devnet-2 XMSS scheme.
  - Update any domain separation tags if spec changed.
- **Genesis/Config**:
  - Update genesis and consensus fixtures to devnet-2 values.
  - Ensure any config files or CLI defaults reflect devnet-2 parameters.
  - **Notes from audit**:
    - Gossipsub heartbeat interval is 0.7s (700ms); Lantern updated to match.
    - SignedAttestation and BlockSignatures are SSZ variable-length containers (signature offsets required).
    - `LANTERN_SIGNED_VOTE_SSZ_SIZE` now includes the 4-byte offset (total 3252 bytes).
    - BlockSignatures fixed section is 8 bytes (two offsets); size calculations updated for gossip sizing.
    - XMSS signature hash-tree-root now follows the SSZ container layout (path, rho, hashes).
    - Networking fixtures + SSZ vectors regenerated to reflect the offset changes.
    - ReqResp blocks_by_root snappy protocol string corrected (no `lean_` prefix).

### 4) Aggregation Support
- **Aggregation proof generation**:
  - Replace devnet-1 aggregation (if present) with XMSS aggregation.
  - Ensure buffer sizing for proofs is adequate (real proofs are large).
- **Aggregation verification**:
  - Wire `pq_verify_aggregated_signatures` into the code paths that verify aggregated signatures.
  - Ensure the proof encoding/decoding format matches the bindings (version + proof_len + randomness_count + proof + randomness).
- **Performance considerations**:
  - Consider parallelization / precomputation hooks if needed.
  - Make sure proofs are not recomputed unnecessarily.

### 5) Tests + Fixtures
- **Unit tests**:
  - Update all signature-related tests to use XMSS.
  - Add tests for aggregation proof serialization/deserialization if missing.
- **Integration tests**:
  - Update any block/tx validation tests that assume devnet-1 keys/signatures.
  - Ensure signature verification in block processing uses XMSS.
- **Fixture regeneration**:
  - Regenerate genesis and consensus fixtures to use XMSS keys/signatures.
  - Verify test vectors (if any) against the new bindings.

### 6) CI + Tooling
- **Rust toolchain**:
  - Update CI to install/use a Rust toolchain that supports edition2024.
  - For Linux CI, use a current Rust docker image.
- **Build flags**:
  - Ensure `cargo build --locked` is used to keep the dependency graph stable.
  - Consider caching Cargo git dependencies in CI to reduce build time.

### 7) End-to-End Validation
- **Node startup**:
  - Confirm node starts with XMSS keys and can produce valid signatures.
- **Network compatibility**:
  - Confirm devnet-2 nodes can connect, sync, and validate each other’s blocks.
- **Consensus validation**:
  - Ensure the entire signature path for block/tx validation is XMSS.
- **Performance checks**:
  - Capture basic metrics for sign/verify and aggregation proof generation time.

## Open Questions / Pending Inputs
- **LeanSpec devnet-2 details**: Specific changes to message formats, epochs, and constants must be pulled from `tools/leanSpec`.
- **Branch workflow**: Confirm the devnet-2 branch should fully replace devnet-1 code paths (no parallel legacy logic).
- **Deployment environment**: Confirm any environment constraints (CI, Docker, OS targets).
- **Lean-quickstart scope**: Changes for `tools/lean-quickstart` are ignored here and will be handled by its maintainers.

## Completed Items (update as you go)
- [x] `c-leanvm-xmss` bindings implemented and tested locally (macOS + Linux).
- [x] Makefile for example build/run.
- [x] Submodule present under `external/`.
- [x] Lantern build wired to `c-leanvm-xmss` (CMake dependency + include path + bootstrap).
- [x] Replaced hash-sig key paths/options with XMSS (CLI/env/defaults/fixtures + validator config `xmssDir`).
- [x] Full constants/wire-format audit against latest `tools/leanSpec` (domains, limits, epochs, SSZ offsets) + fixtures updated.
- [x] Fork-choice fixtures regenerated from `tools/leanSpec` and synced into `tests/fixtures/consensus/fork_choice/devnet`.
- [x] Lantern test suite verified after fixture refresh (`ctest --test-dir build --output-on-failure`).
