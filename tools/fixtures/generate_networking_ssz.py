#!/usr/bin/env python3
"""Generate LeanSpec networking SSZ fixtures for Lantern tests.

This script relies on LeanSpec container definitions to ensure fixture
serialization matches the specification.
"""

from __future__ import annotations

from pathlib import Path
from typing import Sequence

try:
    from lean_spec.subspecs.containers.attestation import (
        AggregatedAttestation,
        Attestation,
        AttestationData,
        SignedAttestation,
    )
    from lean_spec.subspecs.containers.block import (
        AggregatedAttestations,
        AttestationSignatures,
        Block,
        BlockBody,
        BlockSignatures,
        BlockWithAttestation,
        SignedBlockWithAttestation,
    )
    from lean_spec.subspecs.containers.checkpoint import Checkpoint
    from lean_spec.subspecs.containers.slot import Slot
    from lean_spec.subspecs.networking.reqresp.message import (
        BlocksByRootRequest,
        RequestedBlockRoots,
        Status,
    )
    from lean_spec.subspecs.networking.config import MAX_REQUEST_BLOCKS
    from lean_spec.subspecs.xmss.aggregation import AggregatedSignatureProof
    from lean_spec.subspecs.xmss.constants import TARGET_CONFIG
    from lean_spec.subspecs.xmss.containers import Signature
    from lean_spec.subspecs.xmss.types import (
        HashDigestList,
        HashDigestVector,
        HashTreeOpening,
        Randomness,
    )
    from lean_spec.snappy import compress as raw_snappy_compress, frame_compress
    from lean_spec.subspecs.koalabear import Fp, P_BYTES
    from lean_spec.types import Bytes32, SSZList, Uint64
    from lean_spec.types.byte_arrays import ByteListMiB
except ModuleNotFoundError as exc:
    raise SystemExit(
        "Missing LeanSpec dependencies. Run `uv sync --directory tools/leanSpec` "
        "and then `uv run --directory tools/leanSpec python ../../tools/fixtures/generate_networking_ssz.py`."
    ) from exc


def repeating_bytes(seed: int, length: int) -> bytes:
    return bytes(((seed + i) & 0xFF) for i in range(length))


class _FpStream:
    def __init__(self, seed: int) -> None:
        self._value = seed

    def take(self, count: int) -> list[Fp]:
        values = [Fp(self._value + i) for i in range(count)]
        self._value += count
        return values


def _expected_signature_ssz_bytes() -> int:
    hash_vec_bytes = TARGET_CONFIG.HASH_LEN_FE * P_BYTES
    path_bytes = TARGET_CONFIG.LOG_LIFETIME * hash_vec_bytes
    hashes_bytes = TARGET_CONFIG.DIMENSION * hash_vec_bytes
    rho_bytes = TARGET_CONFIG.RAND_LEN_FE * P_BYTES
    signature_header = (2 * 4) + rho_bytes
    path_container_overhead = 4
    return signature_header + path_container_overhead + path_bytes + hashes_bytes


EXPECTED_SIGNATURE_SSZ_BYTES = _expected_signature_ssz_bytes()


def make_signature(seed: int) -> Signature:
    stream = _FpStream(seed)
    path = HashTreeOpening(
        siblings=HashDigestList(
            data=[
                HashDigestVector(data=stream.take(TARGET_CONFIG.HASH_LEN_FE))
                for _ in range(TARGET_CONFIG.LOG_LIFETIME)
            ]
        )
    )
    rho = Randomness(data=stream.take(TARGET_CONFIG.RAND_LEN_FE))
    hashes = HashDigestList(
        data=[
            HashDigestVector(data=stream.take(TARGET_CONFIG.HASH_LEN_FE))
            for _ in range(TARGET_CONFIG.DIMENSION)
        ]
    )
    signature = Signature(path=path, rho=rho, hashes=hashes)
    encoded_len = len(signature.encode_bytes())
    if encoded_len != EXPECTED_SIGNATURE_SSZ_BYTES:
        raise ValueError(
            f"Signature SSZ length mismatch: expected {EXPECTED_SIGNATURE_SSZ_BYTES}, got {encoded_len}"
        )
    return signature


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


def make_attestation_signatures(
    seed: int,
    aggregated_attestations: Sequence[AggregatedAttestation],
    proof_len: int = 8,
) -> AttestationSignatures:
    proofs: list[AggregatedSignatureProof] = []
    for i, attestation in enumerate(aggregated_attestations):
        proof_seed = seed + (i * 3)
        proofs.append(
            AggregatedSignatureProof(
                participants=attestation.aggregation_bits,
                proof_data=ByteListMiB(data=repeating_bytes(proof_seed, proof_len)),
            )
        )
    return AttestationSignatures(data=proofs)


def make_block_signatures(
    seed: int,
    aggregated_attestations: Sequence[AggregatedAttestation],
) -> BlockSignatures:
    attestation_signatures = make_attestation_signatures(seed, aggregated_attestations)
    proposer_seed = seed + (len(aggregated_attestations) * 3)
    proposer_signature = make_signature(proposer_seed)
    return BlockSignatures(
        attestation_signatures=attestation_signatures,
        proposer_signature=proposer_signature,
    )


def make_signed_block(
    seed: int,
    base_slot: int,
    proposer_index: int,
    attestation_count: int,
) -> SignedBlockWithAttestation:
    attestations: list[Attestation] = [
        make_attestation(seed + (i * 5), (proposer_index + i + seed) % 16, base_slot + i + 1)
        for i in range(attestation_count)
    ]
    aggregated_attestations = AggregatedAttestation.aggregate_by_data(attestations)
    block = Block(
        slot=Slot(base_slot),
        proposer_index=Uint64(proposer_index),
        parent_root=Bytes32(repeating_bytes(seed, 32)),
        state_root=Bytes32(repeating_bytes(seed + 0x50, 32)),
        body=BlockBody(attestations=AggregatedAttestations(data=aggregated_attestations)),
    )
    proposer_att = make_attestation(seed + 0x80, (proposer_index + 3) % 16, base_slot + attestation_count + 4)
    signatures = make_block_signatures(seed + 0xA0, aggregated_attestations)
    return SignedBlockWithAttestation(
        message=BlockWithAttestation(block=block, proposer_attestation=proposer_att),
        signature=signatures,
    )


def make_gossip_signed_block(
    seed: int,
    block_slot: int,
    proposer_index: int,
    attestation_vote_slots: Sequence[int],
) -> SignedBlockWithAttestation:
    attestations = [
        make_gossip_attestation(seed + (i * 5), (proposer_index + i + seed) % 16, vote_slot)
        for i, vote_slot in enumerate(attestation_vote_slots)
    ]
    aggregated_attestations = AggregatedAttestation.aggregate_by_data(attestations)
    block = Block(
        slot=Slot(block_slot),
        proposer_index=Uint64(proposer_index),
        parent_root=Bytes32(repeating_bytes(seed, 32)),
        state_root=Bytes32(repeating_bytes(seed + 0x50, 32)),
        body=BlockBody(attestations=AggregatedAttestations(data=aggregated_attestations)),
    )
    proposer_att = make_gossip_attestation(seed + 0x80, (proposer_index + 3) % 16, block_slot + 2)
    signatures = make_block_signatures(seed + 0xA0, aggregated_attestations)
    return SignedBlockWithAttestation(
        message=BlockWithAttestation(block=block, proposer_attestation=proposer_att),
        signature=signatures,
    )


def write_fixture(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def describe_fixture(name: str, values: Sequence[str]) -> None:
    summary = ", ".join(values)
    print(f"wrote {name}: {summary}")


def encode_gossip_fixture(ssz_path: Path, snappy_path: Path) -> None:
    snappy = raw_snappy_compress(ssz_path.read_bytes())
    write_fixture(snappy_path, snappy)


class BlocksByRootResponseFixture(SSZList[SignedBlockWithAttestation]):
    LIMIT = MAX_REQUEST_BLOCKS


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    fixture_dir = repo_root / "tests/fixtures/networking"

    status_fixture = Status(
        finalized=make_checkpoint(0x11, 42),
        head=make_checkpoint(0x41, 96),
    )
    status_bytes = status_fixture.encode_bytes()
    status_path = fixture_dir / "status_leanspec.ssz"
    write_fixture(status_path, status_bytes)
    describe_fixture("Status", [f"bytes={len(status_bytes)}"])
    status_snappy_path = fixture_dir / "status_leanspec.snappy"
    status_snappy = frame_compress(status_bytes)
    write_fixture(status_snappy_path, status_snappy)
    describe_fixture(
        "Status Snappy",
        [f"raw={len(status_bytes)}", f"framed={len(status_snappy)}", "chunk=uncompressed"],
    )

    request_fixture = BlocksByRootRequest(
        roots=RequestedBlockRoots(
            data=[
                Bytes32(repeating_bytes(0x21, 32)),
                Bytes32(repeating_bytes(0x52, 32)),
                Bytes32(repeating_bytes(0x83, 32)),
            ]
        )
    )
    request_bytes = request_fixture.encode_bytes()
    request_path = fixture_dir / "blocks_by_root_request_leanspec.ssz"
    write_fixture(request_path, request_bytes)
    describe_fixture(
        "BlocksByRoot request",
        [f"roots={len(request_fixture.roots)}", f"bytes={len(request_bytes)}"],
    )

    response_fixture = BlocksByRootResponseFixture(
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

    vote_attestation = make_gossip_attestation(seed=0x33, validator_id=9, vote_slot=96)
    vote_fixture = SignedAttestation(
        validator_id=vote_attestation.validator_id,
        data=vote_attestation.data,
        signature=make_signature(0xE1),
    )
    vote_bytes = vote_fixture.encode_bytes()
    vote_path = fixture_dir / "gossip_signed_vote_leanspec.ssz"
    write_fixture(vote_path, vote_bytes)
    describe_fixture(
        "Gossip signed vote",
        [
            f"validator={int(vote_fixture.validator_id)}",
            f"slot={int(vote_fixture.data.slot)}",
            f"bytes={len(vote_bytes)}",
        ],
    )
    vote_snappy_path = fixture_dir / "gossip_signed_vote_leanspec.snappy"
    encode_gossip_fixture(vote_path, vote_snappy_path)
    describe_fixture(
        "Gossip signed vote Snappy",
        ["encoder=lean_spec.snappy"],
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
    encode_gossip_fixture(block_path, block_snappy_path)
    describe_fixture(
        "Gossip signed block Snappy",
        ["encoder=lean_spec.snappy"],
    )


if __name__ == "__main__":
    main()
