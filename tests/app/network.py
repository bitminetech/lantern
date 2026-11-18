"""Write a network directory for the lantern binary: config.yaml and genesis.ssz.

Usage: python3 tests/app/network.py OUT_DIR PRESET FORK [GENESIS_TIME]

Runs with the generator's environment (tests/generator/run.sh): the pinned spec modules on the
path, and CONSENSUS_SPECS set. config.yaml is the pinned configs/<PRESET>.yaml with each fork up
to FORK at epoch 0 and each later fork at 2^64 - 1; genesis.ssz is the anchor state of
tests/generator/node.py (8 validators, the first slot of epoch 2) of FORK, with GENESIS_TIME
(default: now) as its genesis_time.
"""

import os
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "generator"))
from node import anchor, schedule  # noqa: E402
from p2p import module, run  # noqa: E402


def main():
    if len(sys.argv) not in (4, 5):
        sys.exit("usage: network.py OUT_DIR PRESET FORK [GENESIS_TIME]")
    out, preset, fork = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    genesis_time = int(sys.argv[4]) if len(sys.argv) == 5 else int(time.time())
    spec = module(fork, preset)
    config = schedule(fork)
    state, _ = run(spec, config, lambda: anchor(spec, fork))
    state.genesis_time = genesis_time
    out.mkdir(parents=True, exist_ok=True)
    text = (pathlib.Path(os.environ["CONSENSUS_SPECS"]) / "configs" / f"{preset}.yaml").read_text()
    text += "\n# The fork schedule of this network\n" + "".join(f"{k}: {v}\n" for k, v in config.items())
    (out / "config.yaml").write_text(text)
    (out / "genesis.ssz").write_bytes(bytes(state.encode_bytes()))
    print(f"{out}: {preset} {fork}, genesis_time {genesis_time}, slot {int(state.slot)}")


if __name__ == "__main__":
    main()
