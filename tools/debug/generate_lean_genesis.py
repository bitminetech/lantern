#!/usr/bin/env python3
"""
Generate a LeanSpec-compatible genesis state and write it to an SSZ file.

Usage:
    python tools/debug/generate_lean_genesis.py <config_yaml> <output_ssz>

Reads GENESIS_TIME and VALIDATOR_COUNT from the YAML config and builds
validators using any available XMSS public keys found under
<config_dir>/xmss-keys/.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import List, Optional

import yaml
REPO_ROOT = Path(__file__).resolve().parents[1]
LEAN_SPEC_SRC = REPO_ROOT / "leanSpec" / "src"
if LEAN_SPEC_SRC.exists():
    sys.path.insert(0, str(LEAN_SPEC_SRC))

from lean_spec.subspecs.containers.state import State, Validators
from lean_spec.subspecs.containers.validator import Validator
from lean_spec.subspecs.koalabear.field import Fp
from lean_spec.subspecs.xmss.constants import PROD_CONFIG
from lean_spec.subspecs.xmss.containers import PublicKey
from lean_spec.types import Bytes52, Uint64


def load_xmss_pubkeys(count: int, xmss_dir: Path) -> List[Optional[bytes]]:
    """Return serialized XMSS public keys for each validator index."""
    results: List[Optional[bytes]] = []
    for index in range(count):
        pk_path = xmss_dir / f"validator_{index}_pk.json"
        if not pk_path.exists():
            results.append(None)
            continue
        try:
            data = json.loads(pk_path.read_text())
            root = [Fp(value=int(value)) for value in data["root"]]
            parameter = [Fp(value=int(value)) for value in data["parameter"]]
            public_key = PublicKey(root=root, parameter=parameter)
            results.append(public_key.to_bytes(PROD_CONFIG))
        except Exception as exc:  # pragma: no cover - defensive parsing
            print(f"warning: failed to parse {pk_path}: {exc}", file=sys.stderr)
            results.append(None)
    return results


def build_state(genesis_time: int, validator_count: int, xmss_dir: Path) -> bytes:
    pubkeys = load_xmss_pubkeys(validator_count, xmss_dir)
    validators = Validators(
        data=[
            Validator(
                pubkey=Bytes52(pk_bytes)
                if pk_bytes is not None
                else Bytes52.zero()
            )
            for pk_bytes in pubkeys
        ]
    )
    state = State.generate_genesis(
        genesis_time=Uint64(genesis_time), validators=validators
    )
    return state.encode_bytes()


def main() -> None:
    if len(sys.argv) != 3:
        print(
            "usage: python tools/debug/generate_lean_genesis.py <config_yaml> <output_ssz>",
            file=sys.stderr,
        )
        sys.exit(1)

    config_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    with config_path.open("r", encoding="utf-8") as fh:
        config = yaml.safe_load(fh)

    genesis_time = int(config.get("GENESIS_TIME", 0))
    validator_count = int(config.get("VALIDATOR_COUNT", 0))
    if validator_count <= 0:
        print("validator count must be positive", file=sys.stderr)
        sys.exit(1)

    xmss_dir = config_path.parent / "xmss-keys"
    if not xmss_dir.is_dir():
        print(
            f"warning: XMSS key directory {xmss_dir} missing; using zeroed pubkeys",
            file=sys.stderr,
        )

    ssz_bytes = build_state(genesis_time, validator_count, xmss_dir)
    output_path.write_bytes(ssz_bytes)
    print(
        f"Wrote genesis SSZ ({len(ssz_bytes)} bytes) to {output_path}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
