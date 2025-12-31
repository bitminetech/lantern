#!/usr/bin/env python3
"""Generate LeanSpec networking SSZ fixtures for Lantern tests.

This script generates SSZ fixtures that are compatible with Lantern's C implementation.
Lantern uses fixed 3112-byte signatures, while leanSpec now uses variable-length
XMSS signatures. To maintain compatibility, this script uses custom types that
encode signatures as raw bytes matching Lantern's expected format.
"""

from __future__ import annotations

import subprocess
import os
import shutil
from pathlib import Path
from typing import Sequence

from lean_spec.subspecs.networking.config import MAX_REQUEST_BLOCKS
from lean_spec.subspecs.containers import (
    Attestation,
    AttestationData,
    Checkpoint,
)
from lean_spec.subspecs.containers.slot import Slot
from lean_spec.types import Bytes32, Uint64
from lean_spec.types.byte_arrays import BaseBytes
from lean_spec.types.collections import SSZList
from lean_spec.types.container import Container

# Lantern expects fixed 3112-byte signatures, matching LANTERN_SIGNATURE_SIZE in C code.
# The leanSpec XMSS Signature is now a variable-length SSZ container, so we define
# a custom fixed-size byte array type for fixture generation.
LANTERN_SIGNATURE_SIZE = 3112
LANTERN_MAX_ATTESTATIONS = 4096


class LanternSignature(BaseBytes):
    """Fixed-size signature matching Lantern's LANTERN_SIGNATURE_SIZE (3112 bytes)."""

    LENGTH = LANTERN_SIGNATURE_SIZE


class LanternBlockSignatures(SSZList):
    """Aggregated signature list using Lantern's fixed-size signatures."""

    ELEMENT_TYPE = LanternSignature
    LIMIT = 2**40  # Matches VALIDATOR_REGISTRY_LIMIT


class LanternSignedAttestation(Container):
    """Signed attestation using Lantern's fixed-size signature format."""

    message: Attestation
    signature: LanternSignature


class LanternAttestations(SSZList):
    """Lantern block body attestations (per-validator, not aggregated)."""

    ELEMENT_TYPE = Attestation
    LIMIT = LANTERN_MAX_ATTESTATIONS


class LanternBlockBody(Container):
    """Block body matching Lantern's per-validator attestation encoding."""

    attestations: LanternAttestations


class LanternBlock(Container):
    """Block container matching Lantern's SSZ layout."""

    slot: Slot
    proposer_index: Uint64
    parent_root: Bytes32
    state_root: Bytes32
    body: LanternBlockBody


class LanternBlockWithAttestation(Container):
    """Block with proposer attestation for Lantern fixture generation."""

    block: LanternBlock
    proposer_attestation: Attestation


class LanternSignedBlockWithAttestation(Container):
    """Signed block using Lantern's fixed-size signature format."""

    message: LanternBlockWithAttestation
    signature: LanternBlockSignatures


class StatusContainer(Container):
    finalized: Checkpoint
    head: Checkpoint


class BlocksByRootRequestList(SSZList):
    ELEMENT_TYPE = Bytes32
    LIMIT = MAX_REQUEST_BLOCKS


class BlocksByRootResponseList(SSZList):
    ELEMENT_TYPE = LanternSignedBlockWithAttestation
    LIMIT = MAX_REQUEST_BLOCKS


def _crc32c(data: bytes) -> int:
    poly = 0x82F63B78
    crc = 0xFFFFFFFF
    for value in data:
        crc ^= value
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ poly
            else:
                crc >>= 1
    return (~crc) & 0xFFFFFFFF


def _mask_crc32c(crc: int) -> int:
    rotated = ((crc >> 15) | ((crc & 0xFFFFFFFF) << 17)) & 0xFFFFFFFF
    return (rotated + 0xA282EAD8) & 0xFFFFFFFF


def _le24(value: int) -> bytes:
    return bytes((value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF))


def _snappy_stream_header(frame: bytearray) -> None:
    frame.append(0xFF)
    frame.extend(_le24(6))
    frame.extend(b"sNaPpY")


def encode_snappy_uncompressed(payload: bytes) -> bytes:
    """Wrap raw bytes into a Snappy framed stream using an uncompressed chunk."""

    frame = bytearray()
    _snappy_stream_header(frame)
    frame.append(0x01)
    frame.extend(_le24(len(payload) + 4))
    crc = _mask_crc32c(_crc32c(payload))
    frame.extend(crc.to_bytes(4, byteorder="little"))
    frame.extend(payload)
    return bytes(frame)


def repeating_bytes(seed: int, length: int) -> bytes:
    return bytes(((seed + i) & 0xFF) for i in range(length))


def make_checkpoint(seed: int, slot: int) -> Checkpoint:
    return Checkpoint(root=Bytes32(repeating_bytes(seed, 32)), slot=Slot(slot))


def make_attestation(seed: int, validator_id: int, slot: int) -> Attestation:
    return Attestation(
        validator_id=Uint64(validator_id),
        data=AttestationData(
            slot=Slot(slot),
            head=make_checkpoint(seed, slot + 1),
            target=make_checkpoint(seed + 0x20, slot + 2),
            source=make_checkpoint(seed + 0x40, slot),
        ),
    )


def make_gossip_attestation(seed: int, validator_id: int, vote_slot: int) -> Attestation:
    if vote_slot < 2:
        msg = f"vote slot must be >= 2 (got {vote_slot})"
        raise ValueError(msg)
    source_slot = vote_slot - 2
    return Attestation(
        validator_id=Uint64(validator_id),
        data=AttestationData(
            slot=Slot(vote_slot),
            head=make_checkpoint(seed, vote_slot + 1),
            target=make_checkpoint(seed + 0x20, vote_slot),
            source=make_checkpoint(seed + 0x40, source_slot),
        ),
    )


def make_signatures(seed: int, count: int) -> LanternBlockSignatures:
    signatures = [LanternSignature(repeating_bytes(seed + (i * 3), LANTERN_SIGNATURE_SIZE)) for i in range(count)]
    return LanternBlockSignatures(data=signatures)


def make_signed_block(seed: int, base_slot: int, proposer_index: int, attestation_count: int) -> LanternSignedBlockWithAttestation:
    attestations: list[Attestation] = [
        make_attestation(seed + (i * 5), (proposer_index + i + seed) % 16, base_slot + i + 1)
        for i in range(attestation_count)
    ]
    block = LanternBlock(
        slot=Slot(base_slot),
        proposer_index=Uint64(proposer_index),
        parent_root=Bytes32(repeating_bytes(seed, 32)),
        state_root=Bytes32(repeating_bytes(seed + 0x50, 32)),
        body=LanternBlockBody(attestations=LanternAttestations(data=attestations)),
    )
    proposer_att = make_attestation(seed + 0x80, (proposer_index + 3) % 16, base_slot + attestation_count + 4)
    signatures = make_signatures(seed + 0xA0, len(attestations) + 1)
    return LanternSignedBlockWithAttestation(
        message=LanternBlockWithAttestation(block=block, proposer_attestation=proposer_att),
        signature=signatures,
    )


def make_gossip_signed_block(
    seed: int,
    block_slot: int,
    proposer_index: int,
    attestation_vote_slots: Sequence[int],
) -> LanternSignedBlockWithAttestation:
    attestations = [
        make_gossip_attestation(seed + (i * 5), (proposer_index + i + seed) % 16, vote_slot)
        for i, vote_slot in enumerate(attestation_vote_slots)
    ]
    block = LanternBlock(
        slot=Slot(block_slot),
        proposer_index=Uint64(proposer_index),
        parent_root=Bytes32(repeating_bytes(seed, 32)),
        state_root=Bytes32(repeating_bytes(seed + 0x50, 32)),
        body=LanternBlockBody(attestations=LanternAttestations(data=list(attestations))),
    )
    proposer_att = make_gossip_attestation(seed + 0x80, (proposer_index + 3) % 16, block_slot + 2)
    signatures = make_signatures(seed + 0xA0, len(attestations) + 1)
    return LanternSignedBlockWithAttestation(
        message=LanternBlockWithAttestation(block=block, proposer_attestation=proposer_att),
        signature=signatures,
    )


def write_fixture(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def describe_fixture(name: str, values: Sequence[str]) -> None:
    summary = ", ".join(values)
    print(f"wrote {name}: {summary}")


GOSSIP_SNAPPY_ENV = "LANTERN_GOSSIP_SNAPPY"
GOSSIP_BUILD_SUBDIR = "gossip_snappy"


def _maybe_build_gossip_tool(repo_root: Path, build_dir: Path, target_name: str) -> None:
    cmake = shutil.which("cmake")
    if not cmake:
        raise FileNotFoundError("cmake is required to build lantern_generate_gossip_snappy")
    cache = build_dir / "CMakeCache.txt"
    cmake_cmd = [cmake, "-S", str(repo_root), "-B", str(build_dir)]
    generator = os.environ.get("CMAKE_GENERATOR")
    if generator:
        cmake_cmd.extend(["-G", generator])
    if not cache.exists():
        build_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(cmake_cmd, check=True)
    subprocess.run([cmake, "--build", str(build_dir), "--target", target_name], check=True)


def _resolve_gossip_tool(repo_root: Path) -> Path:
    env_path = os.environ.get(GOSSIP_SNAPPY_ENV)
    candidates: list[Path] = []
    if env_path:
        candidates.append(Path(env_path))
    build_dir = repo_root / "build"
    alt_build_dir = build_dir / GOSSIP_BUILD_SUBDIR
    candidates.extend(
        [
            build_dir / "lantern_generate_gossip_snappy",
            build_dir / "lantern_generate_gossip_snappy.exe",
            alt_build_dir / "lantern_generate_gossip_snappy",
            alt_build_dir / "lantern_generate_gossip_snappy.exe",
        ]
    )
    for candidate in candidates:
        if candidate.exists():
            return candidate

    _maybe_build_gossip_tool(repo_root, alt_build_dir, "lantern_generate_gossip_snappy")

    for candidate in candidates:
        if candidate.exists():
            return candidate

    pretty_candidates = ", ".join(str(path) for path in candidates)
    raise FileNotFoundError(
        f"Unable to locate lantern_generate_gossip_snappy. Checked: {pretty_candidates}. "
        f"Set {GOSSIP_SNAPPY_ENV} to the executable path or let the script build it by ensuring "
        "CMake is available."
    )


def encode_gossip_fixture(
    repo_root: Path,
    kind: str,
    ssz_path: Path,
    snappy_path: Path,
) -> None:
    tool = _resolve_gossip_tool(repo_root)
    snappy_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [str(tool), kind, str(ssz_path), str(snappy_path)],
        check=True,
    )


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    fixture_dir = repo_root / "tests/fixtures/networking"

    status_fixture = StatusContainer(
        finalized=make_checkpoint(0x11, 42),
        head=make_checkpoint(0x41, 96),
    )
    status_bytes = status_fixture.encode_bytes()
    status_path = fixture_dir / "status_leanspec.ssz"
    write_fixture(status_path, status_bytes)
    describe_fixture("Status", [f"bytes={len(status_bytes)}"])
    status_snappy_path = fixture_dir / "status_leanspec.snappy"
    status_snappy = encode_snappy_uncompressed(status_bytes)
    write_fixture(status_snappy_path, status_snappy)
    describe_fixture(
        "Status Snappy",
        [f"raw={len(status_bytes)}", f"framed={len(status_snappy)}", "chunk=uncompressed"],
    )

    request_fixture = BlocksByRootRequestList(
        data=[
            Bytes32(repeating_bytes(0x21, 32)),
            Bytes32(repeating_bytes(0x52, 32)),
            Bytes32(repeating_bytes(0x83, 32)),
        ]
    )
    request_bytes = request_fixture.encode_bytes()
    request_path = fixture_dir / "blocks_by_root_request_leanspec.ssz"
    write_fixture(request_path, request_bytes)
    describe_fixture("BlocksByRoot request", [f"roots={len(request_fixture)}", f"bytes={len(request_bytes)}"])

    response_fixture = BlocksByRootResponseList(
        data=[
            make_signed_block(seed=0x10, base_slot=12, proposer_index=1, attestation_count=1),
            make_signed_block(seed=0x30, base_slot=18, proposer_index=3, attestation_count=2),
        ]
    )
    response_bytes = response_fixture.encode_bytes()
    response_path = fixture_dir / "blocks_by_root_response_leanspec.ssz"
    write_fixture(response_path, response_bytes)
    describe_fixture(
        "BlocksByRoot response",
        [f"blocks={len(response_fixture)}", f"bytes={len(response_bytes)}"],
    )

    vote_fixture = LanternSignedAttestation(
        message=make_gossip_attestation(seed=0x33, validator_id=9, vote_slot=96),
        signature=LanternSignature(repeating_bytes(0xE1, LANTERN_SIGNATURE_SIZE)),
    )
    vote_bytes = vote_fixture.encode_bytes()
    vote_path = fixture_dir / "gossip_signed_vote_leanspec.ssz"
    write_fixture(vote_path, vote_bytes)
    describe_fixture(
        "Gossip signed vote",
        [
            f"validator={int(vote_fixture.message.validator_id)}",
            f"slot={int(vote_fixture.message.data.slot)}",
            f"bytes={len(vote_bytes)}",
        ],
    )
    vote_snappy_path = fixture_dir / "gossip_signed_vote_leanspec.snappy"
    encode_gossip_fixture(repo_root, "vote", vote_path, vote_snappy_path)
    describe_fixture(
        "Gossip signed vote Snappy",
        ["encoder=lantern_generate_gossip_snappy"],
    )

    block_fixture = make_gossip_signed_block(
        seed=0x24,
        block_slot=72,
        proposer_index=5,
        attestation_vote_slots=[71, 70],
    )
    block_bytes = block_fixture.encode_bytes()
    block_path = fixture_dir / "gossip_signed_block_leanspec.ssz"
    write_fixture(block_path, block_bytes)
    describe_fixture(
        "Gossip signed block",
        [
            f"slot={int(block_fixture.message.block.slot)}",
            f"attestations={len(block_fixture.message.block.body.attestations)}",
            f"bytes={len(block_bytes)}",
        ],
    )
    block_snappy_path = fixture_dir / "gossip_signed_block_leanspec.snappy"
    encode_gossip_fixture(repo_root, "block", block_path, block_snappy_path)
    describe_fixture(
        "Gossip signed block Snappy",
        ["encoder=lantern_generate_gossip_snappy"],
    )


if __name__ == "__main__":
    main()
