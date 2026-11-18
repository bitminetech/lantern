"""Write include/trusted_setup_4096.bin, the KZG trusted setup of the binary (docs/reference/app.md):
the compressed points of presets/mainnet/trusted_setups/trusted_setup_4096.json of the pinned spec
(minimal has the same file), the 4096 of g1_lagrange, the 4096 of g1_monomial, then the 65 of
g2_monomial.

Usage: python3 tests/app/trusted_setup.py CONSENSUS_SPECS [--check]
With --check, exits 1 when the file differs from the spec's points.
"""

import json
import pathlib
import sys


def main():
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] != "--check"):
        sys.exit("usage: trusted_setup.py CONSENSUS_SPECS [--check]")
    spec = pathlib.Path(sys.argv[1])
    out = pathlib.Path(__file__).resolve().parents[2] / "include" / "trusted_setup_4096.bin"
    setups = [json.loads((spec / "presets" / p / "trusted_setups" / "trusted_setup_4096.json").read_text()) for p in ("mainnet", "minimal")]
    if setups[0] != setups[1]:
        sys.exit("the mainnet and minimal trusted setups differ")
    data = b"".join(bytes.fromhex(p[2:]) for key in ("g1_lagrange", "g1_monomial", "g2_monomial") for p in setups[0][key])
    if len(data) != 4096 * 48 * 2 + 65 * 96:
        sys.exit(f"{len(data)} bytes, not {4096 * 48 * 2 + 65 * 96}")
    if len(sys.argv) == 3:
        same = out.exists() and out.read_bytes() == data
        print(f"{out}: {'the same as' if same else 'not the same as'} the pinned spec")
        sys.exit(0 if same else 1)
    out.write_bytes(data)
    print(f"{out}: {len(data)} bytes")


if __name__ == "__main__":
    main()
