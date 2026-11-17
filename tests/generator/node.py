"""Cases of lantern's node core over libp2p (docs/reference/node.md), made with the pinned spec.

The spec functions run in the fork's spec module that run.sh generates from consensus-specs
v1.7.0-beta.4 (aa16bb4). The answers follow p2p-interface.md of phase0, altair and fulu, the
Req/Resp domain: Status, Ping and MetaData of a node at its anchor, from get_forkchoice_store.

cases(fork, preset) yields (handler, name, parts). The parts of a "p2p" case:
- "anchor_state", "anchor_block": the SSZ bytes of the node's anchor;
- "status": the SSZ bytes of the Status the node answers (StatusV2 in fulu);
- "metadata": the SSZ bytes of the MetaData the node answers, of the fork's version;
- "status_version", "metadata_version": the protocol versions of those requests.

The config of every case: each fork up to the case's fork at epoch 0, each later fork at
2^64 - 1, as the runner gives the node.
"""

from p2p import FORKS, U64, module, run
from reqresp import message_types

ANCHOR_EPOCH = 2


def schedule(fork):
    config = {}
    for i, name in enumerate(FORKS[1:], start=1):
        config[f"{name.upper()}_FORK_EPOCH"] = 0 if i <= FORKS.index(fork) else U64
    return config


def anchor(spec, fork):
    """A state at the first slot of epoch ANCHOR_EPOCH with 8 validators, and its block."""
    slot = spec.Slot(ANCHOR_EPOCH * spec.SLOTS_PER_EPOCH)
    version = spec.config.GENESIS_FORK_VERSION if fork == "phase0" else getattr(spec.config, f"{fork.upper()}_FORK_VERSION")
    state = spec.BeaconState(
        genesis_time=1_600_000_000,
        genesis_validators_root=spec.Root(bytes(range(32, 64))),
        slot=slot,
        fork=spec.Fork(previous_version=version, current_version=version, epoch=0),
        latest_block_header=spec.BeaconBlockHeader(slot=slot, body_root=spec.hash_tree_root(spec.BeaconBlockBody())),
    )
    for i in range(8):
        state.validators.append(
            spec.Validator(
                pubkey=spec.BLSPubkey(bytes([i + 1]) * 48),
                withdrawal_credentials=spec.Bytes32(bytes([i]) * 32),
                effective_balance=spec.MAX_EFFECTIVE_BALANCE,
                activation_eligibility_epoch=0,
                activation_epoch=0,
                exit_epoch=spec.FAR_FUTURE_EPOCH,
                withdrawable_epoch=spec.FAR_FUTURE_EPOCH,
            )
        )
        state.balances.append(spec.MAX_EFFECTIVE_BALANCE)
        if fork != "phase0":
            state.previous_epoch_participation.append(0)
            state.current_epoch_participation.append(0)
            state.inactivity_scores.append(0)
    block = spec.BeaconBlock(slot=slot, state_root=spec.hash_tree_root(state))
    return state, block


def answers(spec, fork, state, block):
    store = spec.get_forkchoice_store(state, block)
    epoch = spec.get_current_store_epoch(store)
    digest = spec.compute_fork_digest(state.genesis_validators_root, epoch)
    head = spec.get_head(store)
    head = getattr(head, "root", head)  # a ForkChoiceNode from altair on, a Root before
    fields = dict(
        fork_digest=digest,
        finalized_root=store.finalized_checkpoint.root,
        finalized_epoch=store.finalized_checkpoint.epoch,
        head_root=head,
        head_slot=store.blocks[head].slot,
    )
    t = message_types(spec, fork)
    if fork == "fulu":
        status = t["StatusV2"](earliest_available_slot=block.slot, **fields)
        metadata = t["MetaDataV3"](seq_number=0, custody_group_count=spec.config.CUSTODY_REQUIREMENT)
    else:
        status = t["Status"](**fields)
        metadata = t["MetaDataV2"](seq_number=0)
    return bytes(status.encode_bytes()), bytes(metadata.encode_bytes())


def cases(fork, preset):
    if fork == "phase0":  # the node runs altair to fulu, as the fork choice cases do
        return
    spec = module(fork, preset)
    state, block = run(spec, schedule(fork), lambda: anchor(spec, fork))
    status, metadata = run(spec, schedule(fork), lambda: answers(spec, fork, state, block))
    yield "p2p", "anchor_epoch_2", {
        "anchor_state": bytes(state.encode_bytes()),
        "anchor_block": bytes(block.encode_bytes()),
        "status": status,
        "metadata": metadata,
        "status_version": 2 if fork == "fulu" else 1,
        "metadata_version": 3 if fork == "fulu" else 2,
    }
