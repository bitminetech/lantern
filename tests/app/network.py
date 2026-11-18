"""Write a network directory for the lantern binary: config.yaml and genesis.ssz.

Usage: python3 tests/app/network.py OUT_DIR PRESET FORK [GENESIS_TIME] [VALIDATORS]

Runs with the generator's environment (tests/generator/run.sh): the pinned spec modules on the
path, and CONSENSUS_SPECS set. config.yaml is the pinned configs/<PRESET>.yaml with each fork up
to FORK at epoch 0 and each later fork at 2^64 - 1, each key once, and SECONDS_PER_SLOT
(SLOT_DURATION_MS / 1000) for other clients. genesis.ssz, with GENESIS_TIME (default: now)
as its genesis_time:
- with no VALIDATORS, the anchor state of tests/generator/node.py (8 validators with made up
  keys, the first slot of epoch 2) of FORK;
- with VALIDATORS, a state of FORK at slot 0 with that many active validators of the keys of
  test/helpers/keys.py (other clients need real keys), its genesis_validators_root, the sync
  committees of get_next_sync_committee from altair, and from fulu initialize_proposer_lookahead.
deploy_block.txt and deposit_contract_block.txt (0), and boot_enr.yaml (empty), go with them for
other clients.
"""

import os
import pathlib
import re
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "generator"))
from node import anchor, schedule  # noqa: E402
from p2p import module, run  # noqa: E402


def genesis(spec, fork, count):
    """A state of fork at slot 0 with count active validators of the spec's test keys."""
    from eth_consensus_specs.test.helpers.keys import pubkeys
    version = spec.config.GENESIS_FORK_VERSION if fork == "phase0" else getattr(spec.config, f"{fork.upper()}_FORK_VERSION")
    state = spec.BeaconState(
        fork=spec.Fork(previous_version=version, current_version=version, epoch=0),
        latest_block_header=spec.BeaconBlockHeader(body_root=spec.hash_tree_root(spec.BeaconBlockBody())),
    )
    for i in range(count):
        state.validators.append(spec.Validator(
            pubkey=pubkeys[i], withdrawal_credentials=spec.Bytes32(b"\x01" + bytes(11) + bytes([i + 1]) * 20),
            effective_balance=spec.MAX_EFFECTIVE_BALANCE, activation_eligibility_epoch=0, activation_epoch=0,
            exit_epoch=spec.FAR_FUTURE_EPOCH, withdrawable_epoch=spec.FAR_FUTURE_EPOCH))
        state.balances.append(spec.MAX_EFFECTIVE_BALANCE)
        if fork != "phase0":
            state.previous_epoch_participation.append(0)
            state.current_epoch_participation.append(0)
            state.inactivity_scores.append(0)
    state.genesis_validators_root = spec.hash_tree_root(state.validators)
    if fork != "phase0":
        state.current_sync_committee = spec.get_next_sync_committee(state)
        state.next_sync_committee = spec.get_next_sync_committee(state)
    if fork == "fulu":
        state.proposer_lookahead = spec.initialize_proposer_lookahead(state)
    return state


def main():
    if len(sys.argv) not in (4, 5, 6):
        sys.exit("usage: network.py OUT_DIR PRESET FORK [GENESIS_TIME] [VALIDATORS]")
    out, preset, fork = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    genesis_time = int(sys.argv[4]) if len(sys.argv) >= 5 else int(time.time())
    spec = module(fork, preset)
    config = schedule(fork)
    if len(sys.argv) == 6:
        state = run(spec, config, lambda: genesis(spec, fork, int(sys.argv[5])))
    else:
        state, _ = run(spec, config, lambda: anchor(spec, fork))
    state.genesis_time = genesis_time
    out.mkdir(parents=True, exist_ok=True)
    text = (pathlib.Path(os.environ["CONSENSUS_SPECS"]) / "configs" / f"{preset}.yaml").read_text()
    for key, value in config.items():  # each key once: other clients refuse a key given twice
        text, n = re.subn(rf"^{key}: .*$", f"{key}: {value}", text, flags=re.M)
        if not n:
            text += f"{key}: {value}\n"
    slot_ms = int(re.search(r"^SLOT_DURATION_MS: (\d+)$", text, flags=re.M).group(1))
    text += f"\n# For other clients: keys of earlier spec releases\nSECONDS_PER_SLOT: {slot_ms // 1000}\n"
    (out / "config.yaml").write_text(text)
    (out / "genesis.ssz").write_bytes(bytes(state.encode_bytes()))
    (out / "deploy_block.txt").write_text("0\n")
    (out / "deposit_contract_block.txt").write_text("0\n")
    (out / "boot_enr.yaml").write_text("[]\n")
    print(f"{out}: {preset} {fork}, genesis_time {genesis_time}, slot {int(state.slot)}")


if __name__ == "__main__":
    main()
