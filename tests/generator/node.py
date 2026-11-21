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

blob_cases(fork, preset, cases) yields the "blobs" cases of deneb and electra from the spec's
fork_choice on_block cases: for each case whose block steps have blobs, one of the same name
whose part of each such block file is the list of the SSZ bytes of get_blob_sidecars (deneb
validator.md) of the block and the step's blobs and proofs. A step with fewer proofs or
commitments than blobs gives the sidecars of the indices that have all three.
"""

import hashlib
import json
import os
import pathlib
import re

from p2p import FORKS, U64, module, run
from reqresp import message_types

ANCHOR_EPOCH = 2


def schedule(fork):
    config = {}
    for i, name in enumerate(FORKS[1:], start=1):
        config[f"{name.upper()}_FORK_EPOCH"] = 0 if i <= FORKS.index(fork) else U64
    return config


# Validators of each status but active_ongoing at ANCHOR_EPOCH, for the API cases: activation_eligibility_epoch,
# activation_epoch, exit_epoch, withdrawable_epoch, slashed, effective balance in increments (None: FAR_FUTURE_EPOCH).
STATUS_VALIDATORS = [
    (None, None, None, None, False, 1),   # pending_initialized
    (1, None, None, None, False, 32),     # pending_queued
    (0, 0, 5, 300, False, 32),            # active_exiting
    (0, 0, 5, 300, True, 31),             # active_slashed
    (0, 0, 1, 300, False, 32),            # exited_unslashed
    (0, 0, 1, 300, True, 30),             # exited_slashed
    (0, 0, 0, 1, False, 32),              # withdrawal_possible
    (0, 0, 0, 1, False, 0),               # withdrawal_done
]


class _Keys:
    """The keys of the spec's test helpers, loaded once: validator i has pubkeys[i]."""
    def __getattr__(self, name):
        from eth_consensus_specs.test.helpers import keys
        return getattr(keys, name)


KEYS = _Keys()
BLS_VALIDATORS = (1, 3, 7)  # BLS withdrawal credentials of the key pubkeys[8191 - i], as the helpers sign changes


def anchor(spec, fork, statuses=False, epoch=ANCHOR_EPOCH, extra=0):
    """A state at the first slot of the epoch (ANCHOR_EPOCH) with 8 validators (and those of
    STATUS_VALIDATORS after them with statuses, then `extra` more active ones), and its block."""
    slot = spec.Slot(epoch * spec.SLOTS_PER_EPOCH)
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
                pubkey=spec.BLSPubkey(KEYS.pubkeys[i]),
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
    far = spec.FAR_FUTURE_EPOCH
    for k, (eligible, active, exit_, withdrawable, slashed, inc) in enumerate(STATUS_VALIDATORS if statuses else []):
        i = 8 + k
        state.validators.append(
            spec.Validator(
                pubkey=spec.BLSPubkey(KEYS.pubkeys[i]),
                withdrawal_credentials=spec.Bytes32(bytes([i]) * 32),
                effective_balance=inc * spec.EFFECTIVE_BALANCE_INCREMENT,
                slashed=slashed,
                activation_eligibility_epoch=far if eligible is None else eligible,
                activation_epoch=far if active is None else active,
                exit_epoch=far if exit_ in (None,) else exit_,
                withdrawable_epoch=far if withdrawable is None else withdrawable,
            )
        )
        state.balances.append(inc * spec.EFFECTIVE_BALANCE_INCREMENT + 1000 * i)
        if fork != "phase0":
            state.previous_epoch_participation.append(0)
            state.current_epoch_participation.append(0)
            state.inactivity_scores.append(0)
    for k in range(extra):
        i = len(state.validators)
        state.validators.append(
            spec.Validator(
                pubkey=spec.BLSPubkey(KEYS.pubkeys[i]),
                withdrawal_credentials=spec.Bytes32(bytes([i % 256]) * 32),
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
    for i in BLS_VALIDATORS:
        state.validators[i].withdrawal_credentials = spec.BLS_WITHDRAWAL_PREFIX + hashlib.sha256(KEYS.pubkeys[8191 - i]).digest()[1:]
    if fork != "phase0":  # as at genesis (altair beacon-chain.md, initialize_beacon_state_from_eth1)
        state.current_sync_committee = spec.get_next_sync_committee(state)
        state.next_sync_committee = spec.get_next_sync_committee(state)
    if FORKS.index(fork) >= FORKS.index("electra"):
        # pending items the epochs keep: deposits of slots past the finalized one, partial
        # withdrawals that only blocks take, consolidations of a source that is not withdrawable
        for k in range(3):
            state.pending_deposits.append(spec.PendingDeposit(
                pubkey=spec.BLSPubkey(KEYS.pubkeys[200 + k]), withdrawal_credentials=spec.Bytes32(b"\x01" + bytes(11) + bytes([k]) * 20),
                amount=spec.Gwei(32_000_000_000 + k), signature=spec.BLSSignature(bytes([7 + k]) * 96), slot=spec.Slot(1 + k)))
        for k in range(2):
            state.pending_partial_withdrawals.append(spec.PendingPartialWithdrawal(
                validator_index=k, amount=spec.Gwei(1_000_000_000 + k), withdrawable_epoch=epoch + 10 + k))
            state.pending_consolidations.append(spec.PendingConsolidation(source_index=1 + k, target_index=4 + k))
    if fork == "fulu":  # as at genesis and at the fork (fulu fork.md)
        state.proposer_lookahead = spec.initialize_proposer_lookahead(state)
    if statuses and fork != "phase0":  # validators live in the beacon chain, for getLiveness (node.md, node-api)
        state.current_epoch_participation[2] = 1
        state.current_epoch_participation[6] = 4
        state.previous_epoch_participation[5] = 7
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


SEEN_SETS = {1: "proposer_slots", 2: "aggregator_epochs", 3: "voluntary_exit_indices", 4: "proposer_slashing_indices",
             5: "attester_slashing_indices", 6: "attestation_validator_epochs", 7: "sync_contribution_aggregator_slots",
             8: "sync_message_validator_slots", 9: "bls_to_execution_change_indices", 10: "data_column_sidecar_tuples",
             11: "blob_sidecar_tuples"}  # SEEN_* of networking.md, SeenKey, and the spec's set of each


def pending_marks(spec, state):
    """Phase0: two attestations in each epoch list, of the first slots of the epoch whose committee 0 has
    members: in the current list all the bits of the first, in the previous list the first bit; the second
    of each with no bit."""
    spe = int(spec.SLOTS_PER_EPOCH)
    lists = ((spec.get_current_epoch(state), state.current_epoch_attestations, True),
             (spec.get_previous_epoch(state), state.previous_epoch_attestations, False))
    for epoch, atts, every in lists:
        added = 0
        for slot in range(int(epoch) * spe, (int(epoch) + 1) * spe):
            committee = spec.get_beacon_committee(state, spec.Slot(slot), spec.CommitteeIndex(0))
            if len(committee) == 0:
                continue
            bits = [added == 0 and (every or k == 0) for k in range(len(committee))]
            atts.append(spec.PendingAttestation(
                aggregation_bits=spec.AggregationBits(data=bits),
                data=spec.AttestationData(slot=slot, index=0, target=spec.Checkpoint(epoch=epoch)),
                inclusion_delay=1, proposer_index=0))
            added += 1
            if added == 2:
                break


def liveness_cases(fork, preset):
    """lantern_node_liveness (node.md, node-liveness): a state, the SeenKey entries of a Seen, the indices
    of ids, an epoch, and the byte of each index."""
    import struct
    spec = module(fork, preset)
    spe = int(spec.SLOTS_PER_EPOCH)
    for e0 in (0, ANCHOR_EPOCH):
        state, _ = run(spec, schedule(fork), lambda: anchor(spec, fork, statuses=True, epoch=e0))
        if fork == "phase0":
            run(spec, schedule(fork), lambda: pending_marks(spec, state))
        cur, prev = int(spec.get_current_epoch(state)), int(spec.get_previous_epoch(state))
        n = len(state.validators)
        keys = [(6, cur, 3, 0), (6, cur + 1, 4, 0), (6, prev, 9, 0), (2, cur, 7, 0), (2, cur + 1, 10, 0),
                (1, cur * spe + 1, 8, 0), (1, (cur + 1) * spe, 11, 0), (1, prev * spe + spe - 1, 12, 0),
                (3, cur, 13, 0), (4, cur, 14, 0), (5, cur, 15, 0), (9, cur, 13, 0), (10, cur * spe, 14, 2),
                (11, cur * spe, 15, 1), (6, cur, n + 3, 0)]
        if fork != "phase0":
            keys += [(8, cur * spe + 2, 1, 3), (7, prev * spe + 3, 0, 1), (8, (cur + 1) * spe + 1, 15, 0)]
        seen = empty_seen(spec)
        for kind, a, b, c in keys:
            if not hasattr(seen, SEEN_SETS[kind]):
                continue
            entry = (a,) if kind in (3, 4, 5, 9) else (a, b) if kind in (1, 2, 6) else (a, b, c)
            getattr(seen, SEEN_SETS[kind]).add(entry if len(entry) > 1 else entry[0])
        ids = list(range(n + 2)) + [3, n + 3]
        for e in sorted({cur, prev, cur + 1, cur + 5}):
            out = run(spec, schedule(fork), lambda: bytes(1 if is_live(spec, fork, state, seen, e, i) else 0 for i in ids))
            yield "liveness", f"state_epoch_{e0}_at_{e}", {
                "state": bytes(state.encode_bytes()),
                "keys": b"".join(struct.pack("<4Q", *k) for k in keys),
                "ids": b"".join(struct.pack("<Q", i) for i in ids),
                "epoch": e,
                "out": out,
            }


# ---------------------------------------------------------------- Rewards (beacon-api.md, getBlockRewards)

REWARD_EXTRA = 56  # active validators after the anchor's 8 and its status ones: committees of a few members


def sync_reward_values(spec, state):
    """(participant_reward, proposer_reward) of process_sync_aggregate at the state (altair beacon-chain.md)."""
    total_active_increments = int(spec.get_total_active_balance(state)) // int(spec.EFFECTIVE_BALANCE_INCREMENT)
    total_base_rewards = int(spec.get_base_reward_per_increment(state)) * total_active_increments
    max_participant_rewards = total_base_rewards * int(spec.SYNC_REWARD_WEIGHT) // int(spec.WEIGHT_DENOMINATOR) // int(spec.SLOTS_PER_EPOCH)
    participant_reward = max_participant_rewards // int(spec.SYNC_COMMITTEE_SIZE)
    proposer_reward = participant_reward * int(spec.PROPOSER_WEIGHT) // (int(spec.WEIGHT_DENOMINATOR) - int(spec.PROPOSER_WEIGHT))
    return participant_reward, proposer_reward


def block_rewards(spec, fork, pre, block, early, late):
    """The values of getBlockRewards (beacon-api.md) of the BeaconBlock on its pre-state P, with the E states
    of phase0 (None for none): (proposer_index, total, attestations, sync_aggregate, proposer_slashings,
    attester_slashings)."""
    body = block.body
    electra = FORKS.index(fork) >= FORKS.index("electra")
    quotient = int(spec.WHISTLEBLOWER_REWARD_QUOTIENT_ELECTRA if electra else spec.WHISTLEBLOWER_REWARD_QUOTIENT)
    epoch = spec.get_current_epoch(pre)
    slashed = set()
    proposer_slashings = 0
    for s in body.proposer_slashings:
        i = int(s.signed_header_1.message.proposer_index)
        proposer_slashings += int(pre.validators[i].effective_balance) // quotient
        slashed.add(i)
    attester_slashings = 0
    for s in body.attester_slashings:
        both = set(map(int, s.attestation_1.attesting_indices)) & set(map(int, s.attestation_2.attesting_indices))
        for i in sorted(both):
            if spec.is_slashable_validator(pre.validators[i], epoch) and i not in slashed:
                attester_slashings += int(pre.validators[i].effective_balance) // quotient
                slashed.add(i)
    sync = 0
    if fork != "phase0":
        sync = sum(1 for bit in body.sync_aggregate.sync_committee_bits if bit) * sync_reward_values(spec, pre)[1]
    attestations = 0
    if fork != "phase0":
        flags = {int(spec.get_current_epoch(pre)): list(map(int, pre.current_epoch_participation)),
                 int(spec.get_previous_epoch(pre)): list(map(int, pre.previous_epoch_participation))}
        denominator = (int(spec.WEIGHT_DENOMINATOR) - int(spec.PROPOSER_WEIGHT)) * int(spec.WEIGHT_DENOMINATOR) // int(spec.PROPOSER_WEIGHT)
        for a in body.attestations:
            indices = spec.get_attestation_participation_flag_indices(pre, a.data, pre.slot - a.data.slot)
            part = flags[int(a.data.target.epoch)]
            numerator = 0
            for i in sorted(spec.get_attesting_indices(pre, a)):
                for f, weight in enumerate(spec.PARTICIPATION_FLAG_WEIGHTS):
                    if f in indices and not part[i] >> f & 1:
                        part[i] |= 1 << f
                        numerator += int(spec.get_base_reward(pre, i)) * int(weight)
            attestations += numerator // denominator
    else:
        b = int(epoch)
        rewarded = {b - 1: set(), b: set()}
        lowest = {}
        for e in (early, late):
            if e is None:
                continue
            low = {}
            for pa in e.previous_epoch_attestations:
                for i in spec.get_pending_attesting_indices(e, pa):
                    low[int(i)] = min(low.get(int(i), 255), int(pa.inclusion_delay))
            lowest[id(e)] = low
        for a in body.attestations:
            t = int(a.data.target.epoch)
            e = late if t == b else early
            assert t in (b, b - 1) and e is not None
            delay = int(pre.slot - a.data.slot)
            for i in sorted(spec.get_attesting_indices(pre, a)):
                i = int(i)
                if i in rewarded[t]:
                    continue
                rewarded[t].add(i)
                if not e.validators[i].slashed and lowest[id(e)].get(i, 255) >= delay:
                    attestations += int(spec.get_base_reward(e, i)) // int(spec.PROPOSER_REWARD_QUOTIENT)
    total = attestations + sync + proposer_slashings + attester_slashings
    return (int(block.proposer_index), total, attestations, sync, proposer_slashings, attester_slashings)


def sync_rewards(spec, pre, block):
    """The items of getSyncCommitteeRewards (beacon-api.md) of the BeaconBlock on its pre-state P:
    (validator index, reward) of each member once, in index order."""
    keys = [bytes(v.pubkey) for v in pre.validators]
    places = [keys.index(bytes(k)) for k in pre.current_sync_committee.pubkeys]
    participant_reward, proposer_reward = sync_reward_values(spec, pre)
    proposer = int(block.proposer_index)
    balance = {i: int(pre.balances[i]) for i in set(places) | {proposer}}
    took = 0
    for i, bit in zip(places, block.body.sync_aggregate.sync_committee_bits):
        if bit:
            balance[i] += participant_reward
            balance[proposer] += proposer_reward
            took += proposer_reward
        else:
            balance[i] = max(0, balance[i] - participant_reward)
    return [(i, balance[i] - int(pre.balances[i]) - (took if i == proposer else 0)) for i in sorted(set(places))]


def proposer_part(spec, state, proposer):
    """The rewards get_inclusion_delay_deltas (phase0 beacon-chain.md) pays the proposer as a proposer."""
    out = 0
    matching = spec.get_matching_source_attestations(state, spec.get_previous_epoch(state))
    for index in spec.get_unslashed_attesting_indices(state, matching):
        attestation = min([a for a in matching if index in spec.get_pending_attesting_indices(state, a)],
                          key=lambda a: a.inclusion_delay)
        if int(attestation.proposer_index) == proposer:
            out += int(spec.get_proposer_reward(state, index))
    return out


def reward_attestation(spec, fork, state, slot, indices, pick, target_root=None, head_root=None):
    """An Attestation of the committees `indices` of the slot, at the state: bit k of a committee's members
    set when pick(committee index, k); its source the justified checkpoint of the target's epoch, its target
    and head the state's roots unless given."""
    epoch = spec.compute_epoch_at_slot(slot)
    source = state.current_justified_checkpoint if epoch == spec.get_current_epoch(state) else state.previous_justified_checkpoint
    electra = FORKS.index(fork) >= FORKS.index("electra")
    data = spec.AttestationData(
        slot=slot, index=0 if electra else indices[0],
        beacon_block_root=head_root if head_root is not None else spec.get_block_root_at_slot(state, slot),
        source=source,
        target=spec.Checkpoint(epoch=epoch, root=target_root if target_root is not None else spec.get_block_root(state, epoch)))
    bits = []
    for c in indices:  # each committee with one attester at least, as process_attestation asks
        committee = spec.get_beacon_committee(state, slot, c)
        some = [bool(pick(c, k)) for k in range(len(committee))]
        if not any(some):
            some[0] = True
        bits += some
    att = spec.Attestation(aggregation_bits=spec.AggregationBits(data=bits), data=data)
    if electra:
        for c in indices:
            att.committee_bits[c] = True
    return att


def reward_block(spec, fork, pre, variant):
    """A BeaconBlock at the slot of P with its proposer, attestations of both epochs, slashings and a sync
    aggregate, for node-rewards; variant changes the bits."""
    slot = int(pre.slot)
    spe = int(spec.SLOTS_PER_EPOCH)
    proposer = int(spec.get_beacon_proposer_index(pre))
    epoch = int(spec.get_current_epoch(pre))
    count = int(spec.get_committee_count_per_slot(pre, epoch))
    attestations = []
    # previous epoch: slots the inclusion window allows, two committees where there are two
    earliest = max(slot - spe, (epoch - 1) * spe)
    for s in range(earliest, min(earliest + 3, epoch * spe)):
        cs = list(range(min(count, 2)))
        if FORKS.index(fork) >= FORKS.index("electra"):
            attestations.append(reward_attestation(spec, fork, pre, s, cs, lambda c, k: (k + c + variant) % 3 != 0))
        else:
            for c in cs:
                attestations.append(reward_attestation(spec, fork, pre, s, [c], lambda c, k: (k + c + variant) % 3 != 0))
    # a wrong head, then a wrong target, of the first previous slot; then the same slot again with all bits
    wrong = spec.Root(b"\x55" * 32)
    attestations.append(reward_attestation(spec, fork, pre, earliest, [0], lambda c, k: True, head_root=wrong))
    attestations.append(reward_attestation(spec, fork, pre, earliest + 1, [0], lambda c, k: k % 2 == 0, target_root=wrong))
    attestations.append(reward_attestation(spec, fork, pre, earliest, [0], lambda c, k: True))
    # current epoch: the last two slots before the block's
    last = slot - int(spec.MIN_ATTESTATION_INCLUSION_DELAY)
    for s in range(max(epoch * spe, last - 1), last + 1):
        attestations.append(reward_attestation(spec, fork, pre, s, [0], lambda c, k: (k + variant) % 2 == 0))
    most = spec.MAX_ATTESTATIONS_ELECTRA if FORKS.index(fork) >= FORKS.index("electra") else spec.MAX_ATTESTATIONS
    assert len(attestations) <= int(most)
    active = [i for i in spec.get_active_validator_indices(pre, epoch) if i != proposer and not pre.validators[i].slashed]

    def header_of(index, root):
        return spec.SignedBeaconBlockHeader(message=spec.BeaconBlockHeader(slot=slot - 1, proposer_index=index, body_root=root))
    victims = [int(active[-1]), int(active[-2])]
    proposer_slashings = [spec.ProposerSlashing(signed_header_1=header_of(i, spec.Root(b"\x01" * 32)),
                                                signed_header_2=header_of(i, spec.Root(b"\x02" * 32))) for i in victims]

    def indexed_of(indices, root):
        data = spec.AttestationData(slot=slot - 1, index=0, beacon_block_root=root,
                                    source=pre.current_justified_checkpoint, target=spec.Checkpoint(epoch=epoch, root=root))
        ia = spec.IndexedAttestation(data=data)
        for i in sorted(indices):
            ia.attesting_indices.append(i)
        return ia
    a, b = [int(x) for x in active[:4]], [int(x) for x in active[2:6]]
    slashed_before = [i for i, v in enumerate(pre.validators) if v.slashed]
    exited = [i for i, v in enumerate(pre.validators) if not v.slashed and not spec.is_active_validator(v, epoch)]
    attester_slashings = [
        spec.AttesterSlashing(attestation_1=indexed_of(a + slashed_before[:1] + [victims[0]], spec.Root(b"\x03" * 32)),
                              attestation_2=indexed_of(a + slashed_before[:1] + [victims[0]], spec.Root(b"\x04" * 32))),
        spec.AttesterSlashing(attestation_1=indexed_of(b + exited[:1], spec.Root(b"\x05" * 32)),
                              attestation_2=indexed_of(b + exited[:1], spec.Root(b"\x06" * 32))),
    ]
    if FORKS.index(fork) < FORKS.index("electra"):
        attester_slashings = attester_slashings[:int(spec.MAX_ATTESTER_SLASHINGS)]
    else:
        attester_slashings = attester_slashings[:int(spec.MAX_ATTESTER_SLASHINGS_ELECTRA)]
    body = spec.BeaconBlockBody()
    for items, field in ((proposer_slashings, body.proposer_slashings), (attester_slashings, body.attester_slashings),
                         (attestations, body.attestations)):
        for item in items:
            field.append(item)
    if fork != "phase0":
        for k in range(int(spec.SYNC_COMMITTEE_SIZE)):
            body.sync_aggregate.sync_committee_bits[k] = (k * 7 + variant) % 4 != 0
    return spec.BeaconBlock(slot=slot, proposer_index=proposer, parent_root=spec.hash_tree_root(pre.latest_block_header),
                            body=body)


def reward_pre(spec, fork, offset, member):
    """P: the anchor of the api cases at epoch 2 processed to the first slot from `offset` slots into the epoch
    after it whose proposer is not slashed (and with `member` is in the sync committee), with flags of some
    validators set and a sync member of a balance below participant_reward (altair)."""
    state, _ = anchor(spec, fork, statuses=True, epoch=ANCHOR_EPOCH, extra=REWARD_EXTRA)
    spe = int(spec.SLOTS_PER_EPOCH)
    spec.process_slots(state, spec.Slot((ANCHOR_EPOCH + 1) * spe + offset))
    keys = [bytes(v.pubkey) for v in state.validators]
    while True:
        proposer = int(spec.get_beacon_proposer_index(state))
        members = set() if fork == "phase0" else {keys.index(bytes(k)) for k in state.current_sync_committee.pubkeys}
        if not state.validators[proposer].slashed and (not member or fork == "phase0" or proposer in members):
            break
        spec.process_slots(state, state.slot + 1)
        assert int(state.slot) % spe <= spe - 2, "reward_pre: no slot of the epoch fits"
    if fork != "phase0":
        for i in range(0, len(state.validators), 5):
            state.previous_epoch_participation[i] = 3
            state.current_epoch_participation[i] = 1
        keys = [bytes(v.pubkey) for v in state.validators]
        member = keys.index(bytes(state.current_sync_committee.pubkeys[3]))
        state.balances[member] = sync_reward_values(spec, state)[0] // 2
    return state


def rewards_check(spec, fork, pre, block, early, late, want):
    """The spec's own functions give the same proposer rewards, part by part, as block_rewards gives."""
    proposer = int(block.proposer_index)
    s = pre.copy()
    for op, field in ((spec.process_proposer_slashing, 4), (spec.process_attester_slashing, 5)):
        items = block.body.proposer_slashings if field == 4 else block.body.attester_slashings
        before = int(s.balances[proposer])
        for item in items:
            op(s, item)
        assert int(s.balances[proposer]) - before == want[field], "rewards: a slashing part differs from the spec's"
    if fork != "phase0":
        before = int(s.balances[proposer])
        for a in block.body.attestations:
            spec.process_attestation(s, a)
        assert int(s.balances[proposer]) - before == want[2], "rewards: the attestations part differs from the spec's"
        t = pre.copy()
        before = int(t.balances[proposer])
        spec.process_sync_aggregate(t, block.body.sync_aggregate)
        own = next((r for i, r in sync_rewards(spec, pre, block) if i == proposer), 0)
        assert int(t.balances[proposer]) - before - own == want[3], "rewards: the sync part differs from the spec's"
        for i, r in sync_rewards(spec, pre, block):
            took = want[3] if i == proposer else 0
            assert int(t.balances[i]) - int(pre.balances[i]) - took == r, "rewards: a member's sync reward differs"
    else:
        part = sum(proposer_part(spec, e, proposer) for e in (early, late) if e is not None)
        assert part == want[2], "rewards: the phase0 attestations part differs from get_inclusion_delay_deltas"


def reward_states(spec, pre, block, marks):
    """Phase0: E of each target epoch: the block on P, then the slots to the end of the block's epoch (early) and
    of the next (late); with marks, an earlier attestation of some attesters and a slashed attester in each."""
    spe = int(spec.SLOTS_PER_EPOCH)
    b = int(spec.get_current_epoch(pre))
    s = pre.copy()
    spec.process_block(s, block)
    out = []
    for e in (b, b + 1):
        spec.process_slots(s, spec.Slot((e + 1) * spe - 1))
        state = s.copy()
        if marks and len(state.previous_epoch_attestations):
            first = state.previous_epoch_attestations[0]  # one of the block's: an earlier copy of it, by another proposer
            if int(first.inclusion_delay) > 1:
                early_copy = first.copy()
                early_copy.inclusion_delay = 1
                early_copy.proposer_index = (int(block.proposer_index) + 1) % len(state.validators)
                rest = list(state.previous_epoch_attestations)
                state.previous_epoch_attestations = type(state.previous_epoch_attestations)(data=[early_copy] + rest)
            some = spec.get_pending_attesting_indices(state, first)
            if some:
                state.validators[sorted(some)[0]].slashed = True
        out.append(state if e > 0 or b > 0 else None)
    return (out[0] if b > 0 else None), out[1]


def rewards_cases(fork, preset):
    """lantern_node_block_rewards and lantern_node_sync_rewards (node.md, node-rewards): a pre-state, a block,
    in phase0 the E states, and the out of each."""
    import struct
    from eth_consensus_specs.utils import bls
    spec = module(fork, preset)
    assert len(KEYS.pubkeys[0]) == 48  # the keys, made while BLS is on
    bls_active = bls.bls_active
    bls.bls_active = False  # the functions check no signature
    try:
        for offset, variant, marks in ((2, 0, False), (2, 1, True), (4, 2, True)):
            def make():
                pre = reward_pre(spec, fork, offset, variant == 0)
                block = reward_block(spec, fork, pre, variant)
                early = late = None
                if fork == "phase0":
                    early, late = reward_states(spec, pre, block, marks)
                want = block_rewards(spec, fork, pre, block, early, late)
                rewards_check(spec, fork, pre, block, early, late, want)
                parts = {
                    "pre": bytes(pre.encode_bytes()),
                    "block": bytes(spec.SignedBeaconBlock(message=block).encode_bytes()),
                    "early": bytes(early.encode_bytes()) if early is not None else b"",
                    "late": bytes(late.encode_bytes()) if late is not None else b"",
                    "rewards": struct.pack("<6Q", *want),
                    "status": 0,
                }
                if fork != "phase0":
                    parts["sync"] = b"".join(struct.pack("<Qq", i, r) for i, r in sync_rewards(spec, pre, block))
                return parts
            yield "rewards", f"offset_{offset}_variant_{variant}", run_strict(spec, schedule(fork), make)
        # a pre-state not at the block's slot
        def wrong_slot():
            pre = reward_pre(spec, fork, 2, False)
            block = reward_block(spec, fork, pre, 0)
            spec.process_slots(pre, pre.slot + 1)
            return {"pre": bytes(pre.encode_bytes()), "block": bytes(spec.SignedBeaconBlock(message=block).encode_bytes()),
                    "early": b"", "late": b"", "rewards": b"", "status": lantern_status("LANTERN_INVALID_SLOT"), "sync": b""}
        yield "rewards", "pre_not_at_slot", run_strict(spec, schedule(fork), wrong_slot)
    finally:
        bls.bls_active = bls_active


def lantern_status(name):
    """The value of a status of include/lantern.inc."""
    inc = (pathlib.Path(__file__).resolve().parents[2] / "include" / "lantern.inc").read_text()
    return int(re.search(r"^\.set %s, (\d+)" % name, inc, re.M).group(1))


def op_event_messages(spec, state):
    """A valid proposer slashing and a valid attester slashing of the anchor's validators, signed with the
    test helpers' keys; and the stream of their operation events (beacon-api.md): its head, then a chunk each."""
    from eth_consensus_specs.utils import bls
    from json_codec import to_json
    epoch = spec.get_current_epoch(state)

    def header_of(index, body):  # as the pools' (pool_requests)
        h = spec.BeaconBlockHeader(slot=state.slot, proposer_index=index, parent_root=b"\x03" * 32,
                                   state_root=b"\x04" * 32, body_root=body)
        domain = spec.get_domain(state, spec.DOMAIN_BEACON_PROPOSER, spec.compute_epoch_at_slot(h.slot))
        return spec.SignedBeaconBlockHeader(message=h, signature=bls.Sign(KEYS.privkeys[index],
                                                                          spec.compute_signing_root(h, domain)))

    def indexed_of(indices, root):
        data = spec.AttestationData(slot=state.slot, index=0, beacon_block_root=root,
                                    source=state.current_justified_checkpoint,
                                    target=spec.Checkpoint(epoch=epoch, root=root))
        domain = spec.get_domain(state, spec.DOMAIN_BEACON_ATTESTER, data.target.epoch)
        sr = spec.compute_signing_root(data, domain)
        ia = spec.IndexedAttestation(data=data, signature=bls.Aggregate([bls.Sign(KEYS.privkeys[i], sr) for i in indices]))
        for i in indices:
            ia.attesting_indices.append(i)
        return ia
    ps = spec.ProposerSlashing(signed_header_1=header_of(4, b"\x01" * 32), signed_header_2=header_of(4, b"\x02" * 32))
    ats = spec.AttesterSlashing(attestation_1=indexed_of([5, 6], b"\x05" * 32), attestation_2=indexed_of([5, 6], b"\x06" * 32))
    stream = stream_head(b"HTTP/1.1", b"")
    for topic, op in (("proposer_slashing", ps), ("attester_slashing", ats)):
        text = b"event: " + topic.encode() + b"\ndata: " + to_json(op).encode() + b"\n\n"
        stream += b"%04x\r\n" % len(text) + text + b"\r\n"
    return bytes(ps.encode_bytes()), bytes(ats.encode_bytes()), stream


def cases(fork, preset):
    yield from liveness_cases(fork, preset)
    yield from rewards_cases(fork, preset)
    if fork == "phase0":  # the node runs altair to fulu, as the fork choice cases do
        return
    spec = module(fork, preset)
    state, block = run(spec, schedule(fork), lambda: anchor(spec, fork))
    status, metadata = run(spec, schedule(fork), lambda: answers(spec, fork, state, block))
    proposer_slashing, attester_slashing, op_events = run(spec, schedule(fork), lambda: op_event_messages(spec, state))
    yield "api", "anchor_epoch_2", api_cases(fork, preset)
    late = int(spec.EPOCHS_PER_HISTORICAL_VECTOR) + 6  # the lowest epochs of getEpochCommittees
    yield "api", f"anchor_epoch_{late}", api_cases(fork, preset, epoch=late)
    yield "api", "anchor_epoch_0", api_cases(fork, preset, epoch=0)
    if FORKS.index(fork) >= FORKS.index("bellatrix"):
        yield from payload_cases(fork, preset)
    yield from produce_cases(fork, preset)
    yield "p2p", "anchor_epoch_2", {
        "anchor_state": bytes(state.encode_bytes()),
        "anchor_block": bytes(block.encode_bytes()),
        "status": status,
        "metadata": metadata,
        "status_version": 2 if fork == "fulu" else 1,
        "metadata_version": 3 if fork == "fulu" else 2,
        "proposer_slashing": proposer_slashing,
        "attester_slashing": attester_slashing,
        "op_events": op_events,
    }


# ---------------------------------------------------------------- Payload preparation (node.md)

PAYLOAD_HASH = bytes([0x11]) * 32  # the anchor payload's block hash


def payload_anchor(spec, fork, epoch=ANCHOR_EPOCH, extra=0):
    """The api anchor with an execution payload in its block and its header in the state, so the
    merge is complete; from capella validators 2 and 3 have 0x01 credentials, 2 a balance past the
    maximum (a partial withdrawal) and 3 a withdrawable epoch of 0 (a full one)."""
    state, block = anchor(spec, fork, statuses=True, epoch=epoch, extra=extra)
    if FORKS.index(fork) >= FORKS.index("capella"):  # a partial withdrawal of validator 2, a full one of validator 3
        for i in (2, 3):
            state.validators[i].withdrawal_credentials = spec.Bytes32(spec.ETH1_ADDRESS_WITHDRAWAL_PREFIX + bytes(11) + bytes([0xa0 + i]) * 20)
        state.balances[2] = spec.MAX_EFFECTIVE_BALANCE + 2_000_000_000
        state.validators[3].exit_epoch = 0
        state.validators[3].withdrawable_epoch = 0
    payload = spec.ExecutionPayload(parent_hash=spec.Hash32(bytes([0x22]) * 32), fee_recipient=spec.ExecutionAddress(bytes([0x33]) * 20),
                                    block_number=7, gas_limit=30_000_000, timestamp=spec.compute_time_at_slot(state.genesis_time, state.slot),
                                    prev_randao=spec.get_randao_mix(state, spec.get_current_epoch(state)),
                                    block_hash=spec.Hash32(PAYLOAD_HASH))
    fields = {}
    header = spec.ExecutionPayloadHeader
    names = header.model_fields if hasattr(header, "model_fields") else header.fields()
    for name in names:
        if name == "transactions_root":
            fields[name] = spec.hash_tree_root(payload.transactions)
        elif name == "withdrawals_root":
            fields[name] = spec.hash_tree_root(payload.withdrawals)
        else:
            fields[name] = getattr(payload, name)
    state.latest_execution_payload_header = spec.ExecutionPayloadHeader(**fields)
    body = spec.BeaconBlockBody(execution_payload=payload)
    state.latest_block_header.body_root = spec.hash_tree_root(body)
    block = spec.BeaconBlock(slot=state.slot, body=body, state_root=spec.hash_tree_root(state))
    return state, block


def payload_cases(fork, preset):
    """node-payload: a prepareBeaconProposer of the proposer of slot S + 1, or of another validator,
    then a tick at or after the attestation due time of slot S; the engine_forkchoiceUpdated the
    node must make, from the spec's prepare_execution_payload of the anchor state at S + 1."""
    import engine
    spec = module(fork, preset)
    state, block = run(spec, schedule(fork), lambda: payload_anchor(spec, fork))
    root = spec.hash_tree_root(block)
    slot_ms = int(spec.config.SLOT_DURATION_MS)
    due_ms = slot_ms * int(spec.config.ATTESTATION_DUE_BPS) // 10000
    start = lambda slot: int(state.genesis_time) * 1000 + int(slot) * slot_ms
    a = int(state.slot)
    fcu = 1 if fork == "bellatrix" else 2 if fork == "capella" else 3

    def expected(s, fee):
        """The proposer of S + 1 and the tail of the request, from ',"method":' on."""
        def f():
            st = state.copy()
            spec.process_slots(st, spec.Slot(s + 1))
            proposer = int(spec.get_beacon_proposer_index(st))

            class Engine:
                def notify_forkchoice_updated(self, head_block_hash, safe_block_hash, finalized_block_hash, payload_attributes):
                    self.call = (head_block_hash, safe_block_hash, finalized_block_hash, payload_attributes)
            e = Engine()
            spec.prepare_execution_payload(st, spec.Hash32(PAYLOAD_HASH), spec.Hash32(PAYLOAD_HASH), spec.ExecutionAddress(fee), e)
            head, safe, fin, attrs = e.call
            fcs = {"headBlockHash": engine.d(head), "safeBlockHash": engine.d(safe), "finalizedBlockHash": engine.d(fin)}
            text = b',"method":"engine_forkchoiceUpdatedV%d","params":' % fcu
            # the payload_attributes event (beacon-api.md): the attributes in the beacon API encoding
            pa = (b'{"timestamp":' + q(attrs.timestamp) + b',"prev_randao":' + qhex(attrs.prev_randao) +
                  b',"suggested_fee_recipient":' + qhex(attrs.suggested_fee_recipient))
            if hasattr(attrs, "withdrawals"):
                pa += b',"withdrawals":[' + b",".join(
                    b'{"index":' + q(w.index) + b',"validator_index":' + q(w.validator_index) + b',"address":' +
                    qhex(w.address) + b',"amount":' + q(w.amount) + b"}" for w in attrs.withdrawals) + b"]"
            if hasattr(attrs, "parent_beacon_block_root"):
                pa += b',"parent_beacon_block_root":' + qhex(attrs.parent_beacon_block_root)
            header = st.latest_execution_payload_header
            event = (b'event: payload_attributes\ndata: {"version":"' + fork.encode() + b'","data":{"proposer_index":' +
                     q(proposer) + b',"proposal_slot":' + q(st.slot) + b',"parent_block_number":' + q(header.block_number) +
                     b',"parent_block_root":' + qhex(root) + b',"parent_block_hash":' + qhex(header.block_hash) +
                     b',"payload_attributes":' + pa + b"}}}\n\n")
            return (proposer, text + json.dumps([fcs, engine.attribute_json(fork, attrs)], separators=(",", ":")).encode() + b"}",
                    b"%04x\r\n" % len(event) + event + b"\r\n")
        return run(spec, schedule(fork), f)

    def prepare(index, fee):
        body = b'[{"validator_index":"%d","fee_recipient":"0x%s"}]' % (index, fee.hex().encode())
        return (b"POST /eth/v1/validator/prepare_beacon_proposer HTTP/1.1\r\nHost: lantern\r\nContent-Type: application/json\r\n"
                b"Content-Length: %d\r\n\r\n" % len(body) + body)

    epoch_slots = int(spec.SLOTS_PER_EPOCH)
    # (name, S, the first tick, the second tick, the proposer's or another's, the engine's payloadId)
    plans = [("head_of_slot", a, start(a), start(a) + 1, True, bytes(range(1, 9))),
             ("due_time", a + 1, start(a + 1), start(a + 1) + due_ms, True, bytes(range(9, 17))),
             ("null_payload_id", a + 1, start(a + 1), start(a + 1) + due_ms + 5, True, b""),
             ("epoch_boundary", a + epoch_slots - 1, start(a + epoch_slots - 1), start(a + epoch_slots - 1) + due_ms, True, bytes(8)),
             ("before_due_time", a + 1, start(a + 1), start(a + 1) + due_ms - 1, None, b""),
             ("another_validator", a + 1, start(a + 1), start(a + 1) + due_ms, False, b"")]
    for name, s, t0, t1, mine, pid in plans:
        fee = bytes([0x40 + len(name)]) * 20
        proposer, tail, event = expected(s, fee)
        index = proposer if mine is not False else (proposer + 1) % len(state.validators)
        due, prepared = mine is not None, mine is True  # due: the node runs the preparation
        yield "payload", name, {
            "anchor_state": bytes(state.encode_bytes()),
            "anchor_block": bytes(block.encode_bytes()),
            "time0": t0,
            "time1": t1,
            "request": prepare(index, fee),
            "response": response(200),
            "tail": tail if prepared else b"",
            "payload_id": pid,
            "payload_slot": s + 1 if due else 0,
            "payload_root": bytes(root) if due else bytes(32),
            "payload_status": (3 if pid else 0) if prepared else 0,
            "payload_proposer": proposer if prepared else 0,
            "events": stream_head(b"HTTP/1.1", b"") + (event if prepared else b""),
        }


# ---------------------------------------------------------------- Block production (beacon-api.md, produceBlockV3)

PRODUCE_CLOSES = 24  # more steps than a produceBlockV3 of an empty pool takes


def produce_cases(fork, preset):
    """node-produce: produceBlockV3 of the first slot after the anchor's of a proposer not slashed,
    with a randao reveal of the proposer's test key, and from bellatrix an empty payload of the
    engine on the attributes of the spec's prepare_execution_payload: the answer of the spec's
    block proposal, in JSON and SSZ. empty_pool: no pool entries. full_pool: an anchor
    SHARD_COMMITTEE_PERIOD epochs later with 2 SLOTS_PER_EPOCH more validators, and in the slot
    before, POSTs of each pool operation the block takes, and of those its rules leave out (an
    attester slashing of only the proposer slashing's validator, an exit of a validator the
    attester slashing slashes). skip_randao: skip_randao_verification with the point at infinity,
    the state root of process_block with no signature checks. bad_reveal: 400 for a reveal of
    another key, and for skip_randao_verification with a reveal that is not the point at infinity.
    closed: the request with its connection closed after each number of the node's steps up to
    PRODUCE_CLOSES, then answered."""
    import json_codec
    import reqresp
    from eth_consensus_specs.utils import bls
    spec = module(fork, preset)
    f = FORKS.index(fork)
    merged = f >= FORKS.index("bellatrix")
    capella = f >= FORKS.index("capella")
    electra = f >= FORKS.index("electra")
    graffiti = bytes(range(32))
    block_value = 123456789012345678901234567890
    to_json = json_codec.to_json

    def post(path, body, version=False):
        return (b"POST " + path + b" HTTP/1.1\r\nHost: lantern\r\nContent-Type: application/json\r\n"
                + (b"Eth-Consensus-Version: " + fork.encode() + b"\r\n" if version else b"")
                + b"Content-Length: %d\r\n\r\n" % len(body) + body)

    def pool_of(st, state, anchor_block, slot, proposer, body):
        """The POSTs of the pool, each VALID by the spec's gossip validation at 100 ms into the slot
        before, and the body's operations of them (the block's rules)."""
        import dataclasses
        a, epoch = int(state.slot), spec.get_current_epoch(state)
        anchor_root = spec.hash_tree_root(anchor_block)
        time_ms = int(state.genesis_time) * 1000 + (int(slot) - 1) * int(spec.config.SLOT_DURATION_MS) + 100
        store = spec.get_forkchoice_store(state, anchor_block)
        spec.on_tick(store, time_ms)
        seen = spec.Seen(**{x.name: (dict() if "dict" in str(x.type) else set()) for x in dataclasses.fields(spec.Seen)})

        def valid(name, fn, *args):
            if gossip_result(spec, fn, seen, store, *args) != "VALID":
                raise RuntimeError(f"node-produce {fork} full_pool: the spec's gossip validation refuses {name}")
        signers = [i for i in (4, 5, 0, 6, 1) if i != proposer]
        ia, ib, ic = signers[:3]
        id_ = next(i for i in (2, 6, 5, 4) if i not in (ia, ib, ic, proposer))

        def exit_of(index):
            ex = spec.VoluntaryExit(epoch=epoch, validator_index=index)
            if f >= FORKS.index("deneb"):
                domain = spec.compute_domain(spec.DOMAIN_VOLUNTARY_EXIT, spec.config.CAPELLA_FORK_VERSION, state.genesis_validators_root)
            else:
                domain = spec.get_domain(state, spec.DOMAIN_VOLUNTARY_EXIT, ex.epoch)
            return spec.SignedVoluntaryExit(message=ex, signature=bls.Sign(KEYS.privkeys[index], spec.compute_signing_root(ex, domain)))

        def header_of(index, body_root):
            h = spec.BeaconBlockHeader(slot=a, proposer_index=index, parent_root=b"\x03" * 32, state_root=b"\x04" * 32, body_root=body_root)
            domain = spec.get_domain(state, spec.DOMAIN_BEACON_PROPOSER, spec.compute_epoch_at_slot(h.slot))
            return spec.SignedBeaconBlockHeader(message=h, signature=bls.Sign(KEYS.privkeys[index], spec.compute_signing_root(h, domain)))

        def indexed_of(indices, root):
            data = spec.AttestationData(slot=a, index=0, beacon_block_root=root, source=state.current_justified_checkpoint,
                                        target=spec.Checkpoint(epoch=epoch, root=root))
            sr = spec.compute_signing_root(data, spec.get_domain(state, spec.DOMAIN_BEACON_ATTESTER, epoch))
            ia_ = spec.IndexedAttestation(data=data, signature=bls.Aggregate([bls.Sign(KEYS.privkeys[i], sr) for i in indices]))
            for i in indices:
                ia_.attesting_indices.append(i)
            return ia_

        reqs = []
        exits = [exit_of(id_), exit_of(ib)]  # the second: of a validator the attester slashing slashes
        for ex in exits:
            valid("an exit", spec.validate_voluntary_exit_gossip, ex, time_ms)
            reqs.append(post(b"/eth/v1/beacon/pool/voluntary_exits", to_json(ex).encode()))
        ps = spec.ProposerSlashing(signed_header_1=header_of(ia, b"\x01" * 32), signed_header_2=header_of(ia, b"\x02" * 32))
        valid("the proposer slashing", spec.validate_proposer_slashing_gossip, ps)
        reqs.append(post(b"/eth/v1/beacon/pool/proposer_slashings", to_json(ps).encode()))
        as1 = spec.AttesterSlashing(attestation_1=indexed_of([ia], b"\x05" * 32), attestation_2=indexed_of([ia], b"\x06" * 32))
        as2 = spec.AttesterSlashing(attestation_1=indexed_of(sorted([ib, ic]), b"\x07" * 32),
                                    attestation_2=indexed_of(sorted([ib, ic]), b"\x08" * 32))
        for x in (as1, as2):
            valid("an attester slashing", spec.validate_attester_slashing_gossip, x)
            reqs.append(post(b"/eth/v2/beacon/pool/attester_slashings", to_json(x).encode(), version=True))
        body.proposer_slashings.append(ps)
        body.attester_slashings.append(as2)
        body.voluntary_exits.append(exits[0])
        if capella:
            c = spec.BLSToExecutionChange(validator_index=7, from_bls_pubkey=KEYS.pubkeys[8191 - 7], to_execution_address=b"\x42" * 20)
            domain = spec.compute_domain(spec.DOMAIN_BLS_TO_EXECUTION_CHANGE, genesis_validators_root=state.genesis_validators_root)
            change = spec.SignedBLSToExecutionChange(message=c, signature=bls.Sign(KEYS.privkeys[8191 - 7], spec.compute_signing_root(c, domain)))
            valid("the change", spec.validate_bls_to_execution_change_gossip, change, time_ms)
            reqs.append(post(b"/eth/v1/beacon/pool/bls_to_execution_changes", ("[" + to_json(change) + "]").encode()))
            body.bls_to_execution_changes.append(change)
        # two attesters of committee 0 of the anchor's slot, aggregated as the block's one attestation
        committee = list(spec.get_beacon_committee(state, spec.Slot(a), spec.CommitteeIndex(0)))
        data = spec.AttestationData(slot=a, index=0, beacon_block_root=anchor_root, source=state.current_justified_checkpoint,
                                    target=spec.Checkpoint(epoch=epoch, root=anchor_root))
        sr = spec.compute_signing_root(data, spec.get_domain(state, spec.DOMAIN_BEACON_ATTESTER, epoch))
        places = [0, len(committee) - 1]
        sigs = [bls.Sign(KEYS.privkeys[committee[p]], sr) for p in places]
        singles = []
        for p, sig in zip(places, sigs):
            if electra:
                singles.append(spec.SingleAttestation(committee_index=0, attester_index=committee[p], data=data, signature=sig))
            else:
                bits = spec.AggregationBits(data=[False] * len(committee))
                bits[p] = True
                singles.append(spec.Attestation(aggregation_bits=bits, data=data, signature=sig))
        count = spec.get_committee_count_per_slot(state, epoch)
        for x in singles:
            valid("an attestation", spec.validate_beacon_attestation_gossip, x, time_ms, spec.compute_subnet_for_attestation(count, a, 0))
        reqs.append(post(b"/eth/v2/beacon/pool/attestations", ("[" + ",".join(to_json(x) for x in singles) + "]").encode(), version=True))
        bits = spec.AggregationBits(data=[p in places for p in range(len(committee))])
        att = spec.Attestation(aggregation_bits=bits, data=data, signature=bls.Aggregate(sigs))
        if electra:
            att.committee_bits[0] = True
        body.attestations.append(att)
        # sync committee messages of slot - 1 on the parent root, of two validators of the committee
        pubkeys = [bytes(k) for k in st.current_sync_committee.pubkeys]
        members = []
        for k in pubkeys:
            v = next(i for i, val in enumerate(st.validators) if bytes(val.pubkey) == k)
            if v not in members:
                members.append(v)
        members = members[:2]
        msg_slot = slot - 1
        parent = spec.hash_tree_root(st.latest_block_header)
        domain = spec.get_domain(st, spec.DOMAIN_SYNC_COMMITTEE, spec.compute_epoch_at_slot(msg_slot))
        sr = spec.compute_signing_root(parent, domain)
        msgs = [spec.SyncCommitteeMessage(slot=msg_slot, beacon_block_root=parent, validator_index=v,
                                          signature=bls.Sign(KEYS.privkeys[v], sr)) for v in members]
        for m in msgs:
            subnet = min(spec.compute_subnets_for_sync_committee(state, m.validator_index))
            valid("a sync committee message", spec.validate_sync_committee_message_gossip, m, time_ms, subnet)
        reqs.append(post(b"/eth/v1/beacon/pool/sync_committees", ("[" + ",".join(to_json(m) for m in msgs) + "]").encode()))
        sync_bits, sync_sigs = [], []
        for k in pubkeys:
            v = next(i for i, val in enumerate(st.validators) if bytes(val.pubkey) == k)
            sync_bits.append(v in members)
            if v in members:
                sync_sigs.append(msgs[members.index(v)].signature)
        aggregate = spec.SyncAggregate(sync_committee_signature=bls.Aggregate(sync_sigs))
        for i, bit in enumerate(sync_bits):
            aggregate.sync_committee_bits[i] = bit
        body.sync_aggregate = aggregate
        return reqs

    def build(full, skip, epoch0=None):
        if epoch0 is None:
            epoch0 = int(spec.config.SHARD_COMMITTEE_PERIOD) + ANCHOR_EPOCH if full else ANCHOR_EPOCH
        extra = 2 * int(spec.SLOTS_PER_EPOCH) if full else 0  # committees of two and more
        state, anchor_block = (payload_anchor(spec, fork, epoch0, extra) if merged
                               else anchor(spec, fork, statuses=True, epoch=epoch0, extra=extra))
        slot, st = state.slot, None
        while st is None or st.validators[proposer].slashed:  # the first slot after the anchor's of a proposer not slashed
            slot += 1
            st = state.copy()
            spec.process_slots(st, slot)
            proposer = int(spec.get_beacon_proposer_index(st))
        epoch = spec.get_current_epoch(st)
        root = spec.compute_signing_root(spec.Epoch(epoch), spec.get_domain(st, spec.DOMAIN_RANDAO, epoch))
        reveal = spec.G2_POINT_AT_INFINITY if skip else bls.Sign(KEYS.privkeys[proposer], root)
        other = bls.Sign(KEYS.privkeys[(proposer + 1) % len(st.validators)], root)  # another key's reveal
        body = spec.BeaconBlockBody(randao_reveal=reveal, eth1_data=st.eth1_data, graffiti=spec.Bytes32(graffiti))
        if f >= FORKS.index("altair"):
            body.sync_aggregate = spec.SyncAggregate(sync_committee_signature=spec.G2_POINT_AT_INFINITY)
        reqs = pool_of(st, state, anchor_block, slot, proposer, body) if full else []
        result = None
        if merged:
            class Engine:
                def notify_forkchoice_updated(self, head_block_hash, safe_block_hash, finalized_block_hash, payload_attributes):
                    self.attributes = payload_attributes
            e = Engine()
            spec.prepare_execution_payload(st, spec.Hash32(PAYLOAD_HASH), spec.Hash32(PAYLOAD_HASH), spec.ExecutionAddress(), e)
            attrs, parent = e.attributes, st.latest_execution_payload_header
            payload = spec.ExecutionPayload(parent_hash=parent.block_hash, fee_recipient=attrs.suggested_fee_recipient,
                                            state_root=spec.Bytes32(bytes([0x55]) * 32), receipts_root=spec.Bytes32(bytes([0x66]) * 32),
                                            prev_randao=attrs.prev_randao, block_number=parent.block_number + 1,
                                            gas_limit=parent.gas_limit, timestamp=attrs.timestamp, base_fee_per_gas=7,
                                            block_hash=spec.Hash32(bytes([0x44]) * 32))
            if capella:
                payload.withdrawals = type(payload.withdrawals)(data=list(attrs.withdrawals))
            body.execution_payload = payload
            if f == FORKS.index("bellatrix"):
                result = json_codec.to_engine_json(payload)
            else:
                types = reqresp.engine_result_types(spec, fork)
                t = types["GetPayloadResult"]
                fields = {"execution_payload": payload, "block_value": spec.Uint256(block_value)}
                if f >= FORKS.index("deneb"):
                    fields["blobs_bundle"] = types["BlobsBundle"]()
                    fields["should_override_builder"] = False
                result = json_codec.to_engine_json(t(**fields))
        block = spec.BeaconBlock(slot=slot, proposer_index=proposer, parent_root=spec.hash_tree_root(st.latest_block_header), body=body)
        before = int(st.balances[proposer])
        post_state = st.copy()
        active = bls.bls_active
        bls.bls_active = not skip  # skip_randao_verification: no check of the reveal's signature
        try:
            spec.process_block(post_state, block)
        finally:
            bls.bls_active = active
        block.state_root = spec.hash_tree_root(post_state)
        gained = int(post_state.balances[proposer]) - before
        if capella:
            gained += sum(int(w.amount) for w in body.execution_payload.withdrawals if int(w.validator_index) == proposer)
        return state, anchor_block, slot, reveal, block, result, max(gained, 0), reqs, bytes(root), bytes(other)

    for name, full, skip in (("empty_pool", False, False), ("full_pool", True, False), ("skip_randao", False, True)):
        made = run(spec, schedule(fork), lambda: build(full, skip))
        if made is None:
            raise RuntimeError(f"node-produce {fork} {name}: the spec refuses the block")
        state, anchor_block, slot, reveal, block, result, gwei, pool_reqs, root, other = made
        slot_ms = int(spec.config.SLOT_DURATION_MS)
        time_ms = int(state.genesis_time) * 1000 + int(slot) * slot_ms
        payload_value = block_value if capella else 0
        wei = b"%d" % gwei + (b"000000000" if gwei else b"")
        if f >= FORKS.index("deneb"):
            bc = reqresp.produce_types(spec, fork)["BlockContents"](block=block)
            data_json, data_ssz = to_json(bc).encode(), bytes(bc.encode_bytes())
        else:
            data_json, data_ssz = to_json(block).encode(), bytes(block.encode_bytes())
        head = (b"Eth-Consensus-Version: " + fork.encode() + b"\r\nEth-Execution-Payload-Blinded: false\r\n"
                b"Eth-Execution-Payload-Value: %d\r\nEth-Consensus-Block-Value: %s\r\n" % (payload_value, wei))

        def answer(body, ssz):
            return (b"HTTP/1.1 200 OK\r\nContent-Type: " + (b"application/octet-stream" if ssz else b"application/json") + b"\r\n"
                    + head + b"Content-Length: %d\r\n\r\n" % len(body) + body)
        body = (b'{"version":"' + fork.encode() + b'","execution_payload_blinded":false,"execution_payload_value":"%d",'
                b'"consensus_block_value":"%s","data":' % (payload_value, wei) + data_json + b"}")
        path = b"/eth/v3/validator/blocks/%d?randao_reveal=0x%s&graffiti=0x%s" % (int(slot), bytes(reveal).hex().encode(), graffiti.hex().encode())
        if skip:
            path += b"&skip_randao_verification="
        # the pool's POSTs in the slot before, at 100 ms; then the requests at the slot's start
        ticks = ([time_ms - slot_ms + 100] + [0] * (len(pool_reqs) - 1) if pool_reqs else []) + [time_ms, 0]
        yield "produce", name, {
            "anchor_state": bytes(state.encode_bytes()),
            "anchor_block": bytes(anchor_block.encode_bytes()),
            "time_ms": time_ms - slot_ms if pool_reqs else time_ms,
            "ticks": ticks,
            "requests": pool_reqs + [b"GET " + path + b" HTTP/1.1\r\nHost: lantern\r\n\r\n",
                                     b"GET " + path + b" HTTP/1.1\r\nHost: lantern\r\nAccept: application/octet-stream\r\n\r\n"],
            "responses": [response(200)] * len(pool_reqs) + [answer(body, False), answer(data_ssz, True)],
            "payload_id": bytes(range(1, 9)) if merged else b"",
            "result": result.encode() if result is not None else b"",
            "closes": 0,
        }
        if name != "empty_pool":
            continue
        # the connection closed after each number of the node's steps, then the request answered
        yield "produce", "closed", {
            "anchor_state": bytes(state.encode_bytes()),
            "anchor_block": bytes(anchor_block.encode_bytes()),
            "time_ms": time_ms,
            "ticks": [time_ms],
            "requests": [b"GET " + path + b" HTTP/1.1\r\nHost: lantern\r\n\r\n"],
            "responses": [answer(body, False)],
            "payload_id": bytes(range(1, 9)) if merged else b"",
            "result": result.encode() if result is not None else b"",
            "closes": PRODUCE_CLOSES,
        }
        # 400 before any engine call: a reveal of another key; the skip flag with a reveal not the point at infinity
        bad = [b"/eth/v3/validator/blocks/%d?randao_reveal=0x%s" % (int(slot), other.hex().encode()),
               b"/eth/v3/validator/blocks/%d?randao_reveal=0x%s&skip_randao_verification=" % (int(slot), bytes(reveal).hex().encode())]
        yield "produce", "bad_reveal", {
            "anchor_state": bytes(state.encode_bytes()),
            "anchor_block": bytes(anchor_block.encode_bytes()),
            "time_ms": time_ms,
            "ticks": [time_ms, 0],
            "requests": [b"GET " + q + b" HTTP/1.1\r\nHost: lantern\r\n\r\n" for q in bad],
            "responses": [error(400), error(400)],
            "payload_id": bytes(range(1, 9)) if merged else b"",
            "result": result.encode() if result is not None else b"",
            "closes": 0,
        }
    # publishBlockV2: an anchor at epoch 0, so that on_block's shuffling dependent root is a block of the store
    made = run(spec, schedule(fork), lambda: build(False, False, 0))
    if made is None:
        raise RuntimeError(f"node-publish {fork}: the spec refuses the block")
    state, anchor_block, slot, _, block = made[:5]
    yield from publish_cases(spec, fork, state, anchor_block, block,
                             int(state.genesis_time) * 1000 + int(slot) * int(spec.config.SLOT_DURATION_MS))


# ---------------------------------------------------------------- Block publishing (beacon-api.md, publishBlockV2)

PUBLISH_CLOSES = 40  # more steps than a publishBlockV2 of a block with no blobs takes


def publish_cases(spec, fork, state, anchor_block, block, time_ms):
    """node-publish: publishBlockV2 at the start of its slot of the empty_pool block of produce_cases
    on an anchor at epoch 0, signed with its proposer's test key, from deneb in a SignedBlockContents with no blobs; the spec's
    gossip validation, state transition and on_block give each block's verdict. published: the block at
    consensus_and_equivocation (200, the head), then again in SSZ (200, known). refused: the block
    signed with another key, a consensus_version of the fork before, and the block with another
    state root at consensus (each 400; the head stays). gossip: the block with another state root at
    the default level (202 once its import fails). closed: the request with its connection closed
    after each number of the node's steps up to PUBLISH_CLOSES, then answered."""
    import dataclasses
    import json_codec
    import reqresp
    from eth_consensus_specs.utils import bls, kzg
    kzg.load_trusted_setup()  # on_block's data availability check of deneb and fulu
    f = FORKS.index(fork)
    to_json = json_codec.to_json
    proposer = int(block.proposer_index)

    def signed_of(message, key):
        st = state.copy()
        spec.process_slots(st, message.slot)
        domain = spec.get_domain(st, spec.DOMAIN_BEACON_PROPOSER, spec.compute_epoch_at_slot(message.slot))
        sig = bls.Sign(KEYS.privkeys[key], spec.compute_signing_root(message, domain))
        return spec.SignedBeaconBlock(message=message, signature=sig)

    good = run(spec, schedule(fork), lambda: signed_of(block, proposer))
    bad_sig = run(spec, schedule(fork), lambda: signed_of(block, (proposer + 1) % len(state.validators)))
    wrong = block.copy()
    wrong.state_root = spec.Root(bytes([0x99]) * 32)
    bad_root = run(spec, schedule(fork), lambda: signed_of(wrong, proposer))

    def verdicts():
        store = spec.get_forkchoice_store(state, anchor_block)
        spec.on_tick(store, time_ms)
        extra = ({},) if f >= FORKS.index("bellatrix") else ()
        out = []
        for sb in (good, bad_sig, bad_root):
            seen = spec.Seen(**{x.name: (dict() if "dict" in str(x.type) else set()) for x in dataclasses.fields(spec.Seen)})
            out.append(gossip_result(spec, spec.validate_beacon_block_gossip, seen, store, sb, time_ms, *extra))
        return out
    def imports(sb):
        store = spec.get_forkchoice_store(state, anchor_block)
        spec.on_tick(store, time_ms)
        spec.on_block(store, sb)
        return spec.get_head(store).root if hasattr(spec.get_head(store), "root") else spec.get_head(store)
    gossip = run(spec, schedule(fork), verdicts)
    moves = [run(spec, schedule(fork), lambda: spec.state_transition(state.copy(), sb, True) or True) for sb in (good, bad_root)]
    heads = [run(spec, schedule(fork), lambda: imports(sb)) for sb in (good, bad_root)]
    heads = [None if h is None else bytes(h) for h in heads]
    if gossip != ["VALID", "REJECT", "VALID"] or moves != [True, None] or heads != [bytes(spec.hash_tree_root(block)), None]:
        raise RuntimeError(f"node-publish {fork}: the spec's verdicts are {gossip}, {moves} and {heads}")

    def bodies(signed):
        value = reqresp.produce_types(spec, fork)["SignedBlockContents"](signed_block=signed) if f >= FORKS.index("deneb") else signed
        return to_json(value).encode(), bytes(value.encode_bytes())

    def post(body, version=fork, level=b"", ssz=False):
        path = b"/eth/v2/beacon/blocks" + (b"?broadcast_validation=" + level if level else b"")
        return (b"POST " + path + b" HTTP/1.1\r\nHost: lantern\r\nContent-Type: " +
                (b"application/octet-stream" if ssz else b"application/json") + b"\r\nEth-Consensus-Version: " +
                version.encode() + b"\r\nContent-Length: %d\r\n\r\n" % len(body) + body)

    head = b"GET /eth/v1/beacon/blocks/head/root HTTP/1.1\r\nHost: lantern\r\n\r\n"

    def at(root, finalized):
        return response(200, b'{"execution_optimistic":false,"finalized":' + flag(finalized) + b',"data":{"root":' + qhex(root) + b"}}")
    anchor_root, root = spec.hash_tree_root(anchor_block), spec.hash_tree_root(block)
    good_json, good_ssz = bodies(good)

    def chunk(text):
        return b"%04x\r\n" % len(text) + text + b"\r\n"

    def gossip_event(r):  # block_gossip (beacon-api.md): the block's slot and root
        return chunk(b'event: block_gossip\ndata: {"slot":' + q(block.slot) + b',"block":' + qhex(r) + b"}\n\n")

    def sidecar_event(sc, r):  # blob_sidecar and data_column_sidecar (beacon-api.md)
        import hashlib
        head = b'{"block_root":' + qhex(r) + b',"index":' + q(sc.index) + b',"slot":' + q(sc.signed_block_header.message.slot)
        if hasattr(sc, "kzg_commitment"):
            vh = b"\x01" + hashlib.sha256(bytes(sc.kzg_commitment)).digest()[1:]
            return chunk(b"event: blob_sidecar\ndata: " + head + b',"kzg_commitment":' + qhex(sc.kzg_commitment) +
                         b',"versioned_hash":' + qhex(vh) + b"}\n\n")
        items = b",".join(qhex(c) for c in sc.kzg_commitments)
        return chunk(b"event: data_column_sidecar\ndata: " + head + b',"kzg_commitments":[' + items + b"]}\n\n")
    events_head = stream_head(b"HTTP/1.1", b"")
    bad_root_root = spec.hash_tree_root(wrong)
    plans = [  # the events of each: of each check that passes (block_gossip), none for the closed case
        ("published", [post(good_json, level=b"consensus_and_equivocation"), head, post(good_ssz, ssz=True)],
         [response(200), at(root, False), response(200)], 0, events_head + gossip_event(root)),
        ("refused", [post(bodies(bad_sig)[0], level=b"consensus"), post(good_json, version=FORKS[f - 1], level=b"consensus"),
                     post(bodies(bad_root)[0], level=b"consensus"), head],
         [error(400), error(400), error(400), at(anchor_root, True)], 0, events_head),
        ("gossip", [post(bodies(bad_root)[0]), head], [response(202), at(anchor_root, True)], 0,
         events_head + gossip_event(bad_root_root)),
        ("closed", [post(good_json), head], [response(200), at(root, False)], PUBLISH_CLOSES, b""),
    ]
    for name, reqs, resps, closes, events in plans:
        yield "publish", name, {
            "anchor_state": bytes(state.encode_bytes()),
            "anchor_block": bytes(anchor_block.encode_bytes()),
            "time_ms": time_ms,
            "ticks": [time_ms] + [0] * (len(reqs) - 1),
            "requests": reqs,
            "responses": resps,
            "payload_id": b"",
            "result": b"",
            "closes": closes,
            "root": bytes(root),
            "sidecars": [],
            "events": events,
        }
    if f < FORKS.index("deneb"):
        return
    # with blobs: the block with the commitments of two blobs, its state root again, signed again
    fulu = f >= FORKS.index("fulu")
    blobs = [spec.Blob(b"".join((4096 * b + j + 1).to_bytes(32, "big") for j in range(int(spec.FIELD_ELEMENTS_PER_BLOB))))
             for b in range(2)]
    commitments = [spec.KZGCommitment(kzg.blob_to_kzg_commitment(x)) for x in blobs]
    with_blobs = block.copy()
    for c in commitments:
        with_blobs.body.blob_kzg_commitments.append(c)

    def state_root_of(message):
        st = state.copy()
        spec.process_slots(st, message.slot)
        spec.process_block(st, message)
        return spec.hash_tree_root(st)
    with_blobs.state_root = run(spec, schedule(fork), lambda: state_root_of(with_blobs))
    blob_root = spec.hash_tree_root(with_blobs)
    signed = run(spec, schedule(fork), lambda: signed_of(with_blobs, proposer))
    if fulu:  # the cells and proofs of each blob; the bad ones swap the proofs of cells 0 and 1 of blob 0
        cells_proofs = [([spec.Cell(c) for c in cs], [spec.KZGProof(p) for p in ps])
                        for cs, ps in (kzg.compute_cells_and_kzg_proofs(x) for x in blobs)]
        proofs = [p for _, ps in cells_proofs for p in ps]
        swapped = list(cells_proofs[0][1])
        swapped[0], swapped[1] = swapped[1], swapped[0]
        bad_cells = [(cells_proofs[0][0], swapped), cells_proofs[1]]
        bad_proofs = [p for _, ps in bad_cells for p in ps]
        sidecars = run(spec, schedule(fork), lambda: spec.get_data_column_sidecars_from_block(signed, cells_proofs))
        bad_sidecars = run(spec, schedule(fork), lambda: spec.get_data_column_sidecars_from_block(signed, bad_cells))
    else:  # the bad ones swap the two blobs' proofs
        proofs = [spec.KZGProof(kzg.compute_blob_kzg_proof(x, c)) for x, c in zip(blobs, commitments)]
        bad_proofs = [proofs[1], proofs[0]]
        sidecars = run(spec, schedule(fork), lambda: spec.get_blob_sidecars(signed, blobs, proofs))
        bad_sidecars = run(spec, schedule(fork), lambda: spec.get_blob_sidecars(signed, blobs, bad_proofs))

    def sidecar_verdicts(items):
        store = spec.get_forkchoice_store(state, anchor_block)
        spec.on_tick(store, time_ms)
        seen = spec.Seen(**{x.name: (dict() if "dict" in str(x.type) else set()) for x in dataclasses.fields(spec.Seen)})
        out = [gossip_result(spec, spec.validate_beacon_block_gossip, seen, store, signed, time_ms, {})]
        for sc in items:
            if fulu:
                out.append(gossip_result(spec, spec.validate_data_column_sidecar_gossip, seen, store, sc, time_ms,
                                         spec.compute_subnet_for_data_column_sidecar(sc.index)))
            else:
                out.append(gossip_result(spec, spec.validate_blob_sidecar_gossip, seen, store, sc, time_ms,
                                         spec.compute_subnet_for_blob_sidecar(sc.index)))
        return out

    def blob_head():
        store = spec.get_forkchoice_store(state, anchor_block)
        spec.on_tick(store, time_ms)
        patch = ({"retrieve_column_sidecars": lambda _r: sidecars} if fulu else
                 {"retrieve_blobs_and_proofs": lambda _r: (blobs, proofs)})
        saved = {k: getattr(spec, k) for k in patch}
        for k, v in patch.items():
            setattr(spec, k, v)
        try:
            spec.on_block(store, signed)
        finally:
            for k, v in saved.items():
                setattr(spec, k, v)
        head = spec.get_head(store)
        return bytes(head.root if hasattr(head, "root") else head)
    good_v = run(spec, schedule(fork), lambda: sidecar_verdicts(sidecars))
    bad_v = run(spec, schedule(fork), lambda: sidecar_verdicts(bad_sidecars))
    if good_v != ["VALID"] * (1 + len(sidecars)) or bad_v[:2] != ["VALID", "REJECT"] or \
            run(spec, schedule(fork), blob_head) != bytes(blob_root):
        raise RuntimeError(f"node-publish {fork} blobs: the spec's verdicts are {good_v[:3]}, {bad_v[:3]}")
    contents = reqresp.produce_types(spec, fork)["SignedBlockContents"]
    fields = ({k: v.annotation for k, v in contents.model_fields.items()} if hasattr(contents, "model_fields")
              else contents.fields())  # the list types of the container itself
    good_c = contents(signed_block=signed, kzg_proofs=fields["kzg_proofs"](data=proofs), blobs=fields["blobs"](data=blobs))
    bad_c = contents(signed_block=signed, kzg_proofs=fields["kzg_proofs"](data=bad_proofs), blobs=fields["blobs"](data=blobs))
    kept = [bytes(sc.encode_bytes()) for sc in sidecars]
    blob_events = events_head + gossip_event(blob_root) + b"".join(sidecar_event(sc, blob_root) for sc in sidecars)
    blob_plans = [
        ("blobs", [post(to_json(good_c).encode(), level=b"consensus"), head], [response(200), at(blob_root, False)], 0, kept,
         blob_events),
        ("blobs_ssz", [post(bytes(good_c.encode_bytes()), ssz=True), head], [response(200), at(blob_root, False)], 0, kept,
         blob_events),
        ("bad_proof", [post(to_json(bad_c).encode(), level=b"consensus"), head], [error(400), at(anchor_root, True)], 0, [],
         events_head),
        ("blobs_closed", [post(to_json(good_c).encode()), head], [response(200), at(blob_root, False)],
         PUBLISH_CLOSES + len(sidecars) + 8, kept, b""),
    ]
    for name, reqs, resps, closes, held, events in blob_plans:
        yield "publish", name, {
            "anchor_state": bytes(state.encode_bytes()),
            "anchor_block": bytes(anchor_block.encode_bytes()),
            "time_ms": time_ms,
            "ticks": [time_ms] + [0] * (len(reqs) - 1),
            "requests": reqs,
            "responses": resps,
            "payload_id": b"",
            "result": b"",
            "closes": closes,
            "root": bytes(blob_root),
            "sidecars": held,
            "events": events,
        }


def blob_cases(fork, preset, cases):
    """cases: (name, parts) of the spec's fork_choice on_block cases of the fork."""
    if fork not in ("deneb", "electra"):
        return
    spec = module(fork, preset)
    blobs_type = spec.Blobs  # List[Blob, MAX_BLOB_COMMITMENTS_PER_BLOCK]: a blobs file of the fork choice format
    for name, parts in cases:
        out = {}
        for step in parts["steps"]:
            if "block" not in step or "blobs" not in step:
                continue
            block = spec.SignedBeaconBlock.decode_bytes(parts[step["block"]])
            blobs = list(blobs_type.decode_bytes(parts[step["blobs"]]))
            proofs = [spec.KZGProof(bytes.fromhex(p[2:])) for p in step.get("proofs") or []]
            n = min(len(blobs), len(proofs), len(block.message.body.blob_kzg_commitments))
            sidecars = spec.get_blob_sidecars(block, blobs[:n], proofs[:n])
            out[step["block"]] = [bytes(sidecar.encode_bytes()) for sidecar in sidecars]
        if out:
            yield "blobs", name, out


# ---------------------------------------------------------------- The events of a fork choice case (node.md, Test vectors)

def sse(topic, data):
    """The text of an event (beacon-api.md, eventstream)."""
    return b"event: " + topic + b"\ndata: " + data + b"\n\n"


def event_texts(spec, fork, parts):
    """The texts of the events of each step of a fork_choice case: a list of bytes, one for each step."""
    from eth_consensus_specs.utils import bls, kzg
    kzg.load_trusted_setup()  # the data availability checks of deneb and fulu
    bls_active = bls.bls_active
    bls.bls_active = False  # the case's signatures hold; the node checks them itself
    try:
        return replay(spec, fork, parts)
    finally:
        bls.bls_active = bls_active


def replay(spec, fork, parts, keep=None):
    """The texts of each step's events; with keep, a dict that takes the store and the blocks' execution_optimistic."""
    anchor_state = spec.BeaconState.decode_bytes(parts["anchor_state"])
    anchor_block = spec.BeaconBlock.decode_bytes(parts["anchor_block"])
    store = spec.get_forkchoice_store(anchor_state, anchor_block)
    spe = int(spec.SLOTS_PER_EPOCH)
    later = FORKS.index(fork) >= FORKS.index("bellatrix")
    statuses = {}   # block_hash: the status of its last payload_status step
    optimistic = {}  # block root: execution_optimistic of its import
    pow_blocks = {}

    def head_root():
        head = spec.get_head(store)
        return bytes(getattr(head, "root", head))

    def genesis_root(state):
        if int(state.slot) > 0:
            return bytes(spec.get_block_root_at_slot(state, 0))
        header = state.latest_block_header.copy()
        if header.state_root == spec.Bytes32():
            header.state_root = spec.hash_tree_root(state)
        return bytes(spec.hash_tree_root(header))

    def dependent(state, epoch):
        """get_block_root_at_slot(state, compute_start_slot_at_epoch(epoch) - 1), the genesis root on underflow."""
        if epoch < 1:
            return genesis_root(state)
        return bytes(spec.get_block_root_at_slot(state, epoch * spe - 1))

    def flag(v):
        return b"true" if v else b"false"

    if later:
        spec.get_pow_block = lambda h: pow_blocks[bytes(h)]
    last_head = head_root()
    last_slot = int(store.blocks[last_head].slot)
    last_epoch = int(store.finalized_checkpoint.epoch)
    out = []
    for step in parts["steps"]:
        texts = b""
        valid = step.get("valid", True)
        if "tick" in step:
            spec.on_tick(store, int(step["tick"]) * 1000)
        elif "block" in step:
            block = spec.SignedBeaconBlock.decode_bytes(parts[step["block"]])
            if valid and spec.hash_tree_root(block.message) not in store.blocks:  # the node skips a block it holds
                patch = {}
                if "blobs" in step:
                    blobs = list(spec.Blobs.decode_bytes(parts[step["blobs"]]))
                    proofs = [spec.KZGProof(bytes.fromhex(p[2:])) for p in step.get("proofs") or []]
                    patch["retrieve_blobs_and_proofs"] = lambda _r, b=blobs, q=proofs: (b, q)
                if "columns" in step:
                    sidecars = [spec.DataColumnSidecar.decode_bytes(parts[c]) for c in step["columns"]]

                    def columns(_r, c=sidecars):
                        assert len(c) > 0
                        return c
                    patch["retrieve_column_sidecars"] = columns
                saved = {k: getattr(spec, k) for k in patch}
                for k, v in patch.items():
                    setattr(spec, k, v)
                try:
                    spec.on_block(store, block)
                finally:
                    for k, v in saved.items():
                        setattr(spec, k, v)
                for attestation in block.message.body.attestations:
                    spec.on_attestation(store, attestation, is_from_block=True)
                for slashing in block.message.body.attester_slashings:
                    spec.on_attester_slashing(store, slashing)
                root = bytes(spec.hash_tree_root(block.message))
                opt = False
                if later:
                    h = bytes(block.message.body.execution_payload.block_hash)
                    opt = h != bytes(32) and statuses.get(h) in ("SYNCING", "ACCEPTED")
                optimistic[root] = opt
                texts += sse(b"block", b'{"slot":' + q(block.message.slot) + b',"block":' + qhex(root) +
                             b',"execution_optimistic":' + flag(opt) + b"}")
        elif "attestation" in step:
            if valid:
                spec.on_attestation(store, spec.Attestation.decode_bytes(parts[step["attestation"]]), is_from_block=False)
        elif "attester_slashing" in step:
            if valid:
                spec.on_attester_slashing(store, spec.AttesterSlashing.decode_bytes(parts[step["attester_slashing"]]))
        elif "pow_block" in step:
            pb = spec.PowBlock.decode_bytes(parts[step["pow_block"]])
            pow_blocks[bytes(pb.block_hash)] = pb
        elif "payload_status" in step:
            statuses[bytes.fromhex(step["block_hash"][2:])] = step["payload_status"]["status"]
        elif "checks" in step:
            if "head" in step["checks"]:
                want = step["checks"]["head"]
                assert head_root() == bytes.fromhex(want["root"][2:]), "replay: the head of a checks step"
        head = head_root()
        if head != last_head:
            state = store.block_states[head]
            slot = int(state.slot)
            epoch = slot // spe

            def ancestor(root, at):
                node = spec.ForkChoiceNode(root=spec.Root(root)) if hasattr(spec, "ForkChoiceNode") else spec.Root(root)
                a = spec.get_ancestor(store, node, spec.Slot(at))
                return bytes(getattr(a, "root", a))
            if not (last_slot < slot and ancestor(head, last_slot) == last_head):  # chain_reorg (beacon-api.md)
                common = next(t for t in range(min(slot, last_slot), -1, -1) if ancestor(head, t) == ancestor(last_head, t))
                texts += sse(b"chain_reorg", b'{"slot":' + q(slot) + b',"depth":' + q(last_slot - common) +
                             b',"old_head_block":' + qhex(last_head) + b',"new_head_block":' + qhex(head) +
                             b',"old_head_state":' + qhex(store.blocks[last_head].state_root) +
                             b',"new_head_state":' + qhex(store.blocks[head].state_root) + b',"epoch":' + q(epoch) +
                             b',"execution_optimistic":' + flag(optimistic.get(head, False)) + b"}")
            texts += sse(b"head", b'{"slot":' + q(slot) + b',"block":' + qhex(head) + b',"state":' +
                         qhex(spec.hash_tree_root(state)) + b',"epoch_transition":' + flag(epoch > last_slot // spe) +
                         b',"previous_duty_dependent_root":' + qhex(dependent(state, epoch - 1)) +
                         b',"current_duty_dependent_root":' + qhex(dependent(state, epoch)) +
                         b',"execution_optimistic":' + flag(optimistic.get(head, False)) + b"}")
            last_head, last_slot = head, slot
        cp = store.finalized_checkpoint
        if int(cp.epoch) > last_epoch:
            last_epoch = int(cp.epoch)
            root = bytes(cp.root)
            texts += sse(b"finalized_checkpoint", b'{"block":' + qhex(root) + b',"state":' +
                         qhex(store.blocks[root].state_root) + b',"epoch":' + q(cp.epoch) +
                         b',"execution_optimistic":' + flag(optimistic.get(root, False)) + b"}")
        out.append(texts)
    if keep is not None:
        keep.update(store=store, optimistic=optimistic, anchor=bytes(spec.hash_tree_root(anchor_block)))
    return out


def reads_texts(spec, fork, parts):
    """The requests of the node-reads case of a fork_choice case, and their answers (beacon-api.md), after a
    replay of its steps: getBlockRewards and getSyncCommitteeRewards of each block of the store, by root, and
    getSyncCommitteeRewards of the head with id items."""
    from eth_consensus_specs.utils import bls, kzg
    import api_route
    kzg.load_trusted_setup()
    assert len(KEYS.pubkeys[0]) == 48
    bls_active = bls.bls_active
    bls.bls_active = False
    keep = {}
    try:
        replay(spec, fork, parts, keep)
    finally:
        bls.bls_active = bls_active
    store, optimistic, anchor_root = keep["store"], keep["optimistic"], keep["anchor"]
    ops = {op["name"]: op for op in api_route.operations(pathlib.Path(os.environ["BEACON_APIS"]))}
    spe = int(spec.SLOTS_PER_EPOCH)
    head = spec.get_head(store)
    head = bytes(getattr(head, "root", head))
    finalized = bytes(store.finalized_checkpoint.root)

    def ancestor(root, slot):
        node = spec.ForkChoiceNode(root=spec.Root(root)) if hasattr(spec, "ForkChoiceNode") else spec.Root(root)
        a = spec.get_ancestor(store, node, spec.Slot(slot))
        return bytes(getattr(a, "root", a))

    def descends(root):  # a strict descendant of the finalized block
        return root != finalized and int(store.blocks[root].slot) > int(store.blocks[finalized].slot) and \
            ancestor(root, store.blocks[finalized].slot) == finalized
    states = {}

    def chain_state(slot):  # the state of the chain at the slot, past the head's the head's post-state brought to it
        if slot not in states:
            root = head if slot >= int(store.blocks[head].slot) else ancestor(head, slot)
            s = store.block_states[root].copy()
            if int(s.slot) < slot:
                spec.process_slots(s, spec.Slot(slot))
            states[slot] = s
        return states[slot]
    requests, answers = [], []

    def ask(op, root, body=None):
        req = api_route.request(ops[op]["method"], api_route.fill(ops[op], {"block_id": qhex(root)[1:-1]}), b"",
                                body=body or b"", content_type=b"application/json" if body else b"")
        requests.append(http(req, extra=b"Content-Length: %d\r\n" % len(body) if body else b"") + (body or b""))
    roots = sorted(store.blocks, key=lambda r: (int(store.blocks[r].slot), bytes(r)))
    for root in map(bytes, roots):
        block = store.blocks[root]
        ok = root != anchor_root and descends(root)
        kept = root != anchor_root and (ok or finalized == anchor_root or ancestor(finalized, block.slot) == root)
        values = b'{"execution_optimistic":' + flag(optimistic.get(root, False)) + b',"finalized":false,"data":'
        pre = None
        if ok:
            pre = store.block_states[bytes(block.parent_root)].copy()
            spec.process_slots(pre, block.slot)
        ask("getBlockRewards", root)
        if not ok:
            answers.append(error(404))
        else:
            early = late = None
            if fork == "phase0":
                b = int(spec.get_current_epoch(pre))
                early = chain_state((b + 1) * spe - 1) if b > 0 else None
                late = chain_state((b + 2) * spe - 1)
            r = block_rewards(spec, fork, pre, block, early, late)
            names = (b"proposer_index", b"total", b"attestations", b"sync_aggregate", b"proposer_slashings", b"attester_slashings")
            answers.append(response(200, values + b"{" + b",".join(b'"%s":%s' % (n, q(v)) for n, v in zip(names, r)) + b"}}"))
        bodies = [None]
        if ok and root == head and fork != "phase0":
            keys = [bytes(v.pubkey) for v in pre.validators]
            members = sorted({keys.index(bytes(k)) for k in pre.current_sync_committee.pubkeys})
            others = [i for i in range(len(keys)) if i not in members]
            bodies.append(b'["%d","0x%s"%s,"%d"]' % (members[0], keys[members[-1]].hex().encode(),
                                                     b',"%d"' % others[0] if others else b"", len(keys) + 7))
        for body in bodies:
            ask("getSyncCommitteeRewards", root, body)
            if not kept:
                answers.append(error(404))
            elif fork == "phase0":
                answers.append(error(400))
            elif not ok:
                answers.append(error(404))
            else:
                items = sync_rewards(spec, pre, block)
                if body is not None:
                    pick = {members[0], members[-1]} | ({others[0]} if others else set())
                    items = [(i, v) for i, v in items if i in pick]
                answers.append(response(200, values + b"[" + b",".join(b'{"validator_index":%s,"reward":"%d"}' % (q(i), v)
                                                                       for i, v in items) + b"]}"))
    # getAttestationsRewards: of the lowest and the highest epoch whose state the node holds, with id items of the
    # highest; and of the store's epoch, past its slot (404)
    store_slot = int(spec.get_current_slot(store))

    def epoch_ask(e, body=None):
        op = ops["getAttestationsRewards"]
        req = api_route.request(op["method"], api_route.fill(op, {"epoch": b"%d" % e}), b"", body=body or b"",
                                content_type=b"application/json" if body else b"")
        requests.append(http(req, extra=b"Content-Length: %d\r\n" % len(body) if body else b"") + (body or b""))
    held = []
    for e in range(0, store_slot // spe):
        x = (e + 2) * spe - 1
        if x > store_slot:
            break
        root = head if x >= int(store.blocks[head].slot) else ancestor(head, x)
        if root == finalized or descends(root):
            held.append((e, x, root))
    for k, (e, x, root) in enumerate(held[:1] + held[-1:] if len(held) > 1 else held):
        s = chain_state(x)
        fin = x <= int(store.finalized_checkpoint.epoch) * spe
        epoch_ask(e)
        answers.append(attestation_rewards_answer(spec, fork, s, optimistic.get(root, False), fin))
        if k == len(held[:1] + held[-1:]) - 1 or len(held) == 1:
            keys = [bytes(v.pubkey) for v in s.validators]
            ids = {1, 4, len(keys) - 1}
            body = b'["1","0x%s","%d","%d"]' % (keys[4].hex().encode(), len(keys) - 1, len(keys) + 9)
            epoch_ask(e, body)
            answers.append(attestation_rewards_answer(spec, fork, s, optimistic.get(root, False), fin, ids))
    epoch_ask(store_slot // spe)
    answers.append(error(404))
    return requests, answers


def attestation_reward_items(spec, fork, state):
    """getAttestationsRewards (beacon-api.md) of the state as it is: (head, target, source, inclusion_delay,
    inactivity, eligible) of each validator, from the spec's delta functions."""
    n = len(state.validators)
    prev = spec.get_previous_epoch(state)
    eligible = {int(i) for i in spec.get_eligible_validator_indices(state)}
    out = [[0, 0, 0, 0, 0, 1 if i in eligible else 0] for i in range(n)]
    if fork == "phase0":
        for k, fn in ((2, spec.get_source_deltas), (1, spec.get_target_deltas), (0, spec.get_head_deltas)):
            r, p = fn(state)
            for i in range(n):
                out[i][k] = int(r[i]) - int(p[i])
        matching = spec.get_matching_source_attestations(state, prev)
        for index in spec.get_unslashed_attesting_indices(state, matching):
            a = min([a for a in matching if index in spec.get_pending_attesting_indices(state, a)], key=lambda a: a.inclusion_delay)
            base = int(spec.get_base_reward(state, index))
            out[int(index)][3] = (base - int(spec.get_proposer_reward(state, index))) // int(a.inclusion_delay)
    else:
        for k, flag in ((2, 0), (1, 1), (0, 2)):
            r, p = spec.get_flag_index_deltas(state, flag)
            for i in range(n):
                out[i][k] = int(r[i]) - int(p[i])
    r, p = spec.get_inactivity_penalty_deltas(state)
    for i in range(n):
        out[i][4] = -int(p[i])
    return out


def ideal_reward_items(spec, fork, state):
    """The ideal_rewards of getAttestationsRewards (beacon-api.md) of the state as it is: (head, target, source,
    inclusion_delay, inactivity, effective_balance) of each effective balance step of the fork of the previous
    epoch: electra's from electra, but deneb's in electra before the epoch of the state's fork."""
    inc = int(spec.EFFECTIVE_BALANCE_INCREMENT)
    prev = int(spec.get_previous_epoch(state))
    electra = FORKS.index(fork) >= FORKS.index("electra") and not (fork == "electra" and prev < int(state.fork.epoch))
    top = int(spec.MAX_EFFECTIVE_BALANCE_ELECTRA) if electra else int(spec.MAX_EFFECTIVE_BALANCE)
    total = int(spec.get_total_active_balance(state))
    leak = bool(spec.is_in_inactivity_leak(state))
    out = []
    if fork == "phase0":
        root = int(spec.integer_squareroot(total))
        balances = [int(spec.get_attesting_balance(state, fn(state, prev))) for fn in
                    (spec.get_matching_head_attestations, spec.get_matching_target_attestations, spec.get_matching_source_attestations)]
        for k in range(1, top // inc + 1):
            base = k * inc * int(spec.BASE_REWARD_FACTOR) // root // int(spec.BASE_REWARDS_PER_EPOCH)
            part = base // int(spec.PROPOSER_REWARD_QUOTIENT)
            parts = [base if leak else base * (b // inc) // (total // inc) for b in balances]
            out.append(parts + [base - part, -(int(spec.BASE_REWARDS_PER_EPOCH) * base - part) if leak else 0, k * inc])
    else:
        per = int(spec.get_base_reward_per_increment(state))
        balances = [int(spec.get_total_balance(state, spec.get_unslashed_participating_indices(state, f, prev))) for f in (2, 1, 0)]
        weights = [int(spec.PARTICIPATION_FLAG_WEIGHTS[f]) for f in (2, 1, 0)]
        for k in range(1, top // inc + 1):
            base = k * per
            parts = [0 if leak else base * w * (b // inc) // ((total // inc) * int(spec.WEIGHT_DENOMINATOR)) for w, b in zip(weights, balances)]
            out.append(parts + [0, 0, k * inc])
    return out


def epoch_steps(spec, fork, state):
    """A copy of the state after the steps of process_epoch before process_rewards_and_penalties."""
    s = state.copy()
    spec.process_justification_and_finalization(s)
    if fork != "phase0":
        spec.process_inactivity_updates(s)
    return s


def attestation_reward_cases(fork, preset, cases):
    """node-attrewards (node.md): for each official rewards case, its pre-state and the items of
    lantern_node_attestation_rewards and lantern_node_ideal_reward in mode 0 (the state as it is) and mode 1
    (the steps of process_epoch before process_rewards_and_penalties applied)."""
    import struct
    spec = module(fork, preset)
    for name, parts in cases:
        def make():
            pre = spec.BeaconState.decode_bytes(parts["pre"])
            out = {}
            for mode in (0, 1):
                s = pre if mode == 0 else epoch_steps(spec, fork, pre)
                items = attestation_reward_items(spec, fork, s)
                ideal = ideal_reward_items(spec, fork, s)
                out[f"items_{mode}"] = b"".join(struct.pack("<qqqQqQ", *it) for it in items)
                out[f"ideal_{mode}"] = b"".join(struct.pack("<qqqQqQ", *it) for it in ideal)
            out["pre"] = parts["pre"]
            return out
        yield "attrewards", name, run_strict(spec, schedule(fork), make)


def attestation_rewards_answer(spec, fork, state, optimistic, finalized, ids=None):
    """The answer of getAttestationsRewards (beacon-api.md) of S = state: the steps of process_epoch before
    process_rewards_and_penalties on a copy, then its ideal and total items; ids a set of validator indices,
    or None for the eligible ones."""
    s = epoch_steps(spec, fork, state)
    items = attestation_reward_items(spec, fork, s)
    ideal = ideal_reward_items(spec, fork, s)

    def fields(it):
        out = b',"head":' + q(it[0]) + b',"target":' + q(it[1]) + b',"source":' + q(it[2])
        if fork == "phase0":
            out += b',"inclusion_delay":' + q(it[3])
        return out + b',"inactivity":' + q(it[4]) + b"}"
    first = b",".join(b'{"effective_balance":' + q(it[5]) + fields(it) for it in ideal)
    chosen = [i for i, it in enumerate(items) if (it[5] if ids is None else i in ids)]
    second = b",".join(b'{"validator_index":' + q(i) + fields(items[i]) for i in chosen)
    body = (b'{"execution_optimistic":' + flag(optimistic) + b',"finalized":' + flag(finalized) +
            b',"data":{"ideal_rewards":[' + first + b'],"total_rewards":[' + second + b"]}}")
    return streamed(None, body)


def reward_answers(spec, fork, block, pre, early, late, optimistic, body, kept=True):
    """The answers of getBlockRewards and of getSyncCommitteeRewards (with the id items of body, or None) of a
    block whose parent's post-state the node holds (beacon-api.md): (block rewards, sync rewards)."""
    values = b'{"execution_optimistic":' + flag(optimistic) + b',"finalized":false,"data":'
    r = block_rewards(spec, fork, pre, block, early, late)
    names = (b"proposer_index", b"total", b"attestations", b"sync_aggregate", b"proposer_slashings", b"attester_slashings")
    first = response(200, values + b"{" + b",".join(b'"%s":%s' % (n, q(v)) for n, v in zip(names, r)) + b"}}")
    if fork == "phase0":
        return first, error(400)
    items = sync_rewards(spec, pre, block)
    if body is not None:
        items = [(i, v) for i, v in items if i in body]
    return first, response(200, values + b"[" + b",".join(b'{"validator_index":%s,"reward":"%d"}' % (q(i), v) for i, v in items) + b"]}")


def transition_reads_texts(fork, preset, parts):
    """The requests of the node-reads case of a transition case, and their answers (beacon-api.md): the node
    anchors at pre with the fork before and imports each block (the runner, transition_node_case);
    getBlockRewards and getSyncCommitteeRewards of the anchor (404) and, by root, of each block whose parent
    is at or above the first slot of the highest finalized epoch the store can reach. None when pre is no
    anchor: its slot is past its latest block header's."""
    from eth_consensus_specs.utils import bls
    import api_route
    before = FORKS[FORKS.index(fork) - 1]
    spec_a, spec_b = module(before, preset), module(fork, preset)
    meta = parts["meta"]
    fork_epoch = int(meta["fork_epoch"])
    spe = int(spec_b.SLOTS_PER_EPOCH)
    fork_slot = fork_epoch * spe
    pre = spec_a.BeaconState.decode_bytes(parts["pre"])
    if int(pre.slot) != int(pre.latest_block_header.slot):
        return None
    assert len(KEYS.pubkeys[0]) == 48
    ops = {op["name"]: op for op in api_route.operations(pathlib.Path(os.environ["BEACON_APIS"]))}

    def is_b(state):
        return type(state) is spec_b.BeaconState

    def bring(state, slot):  # a copy at the slot, across the fork (node.md, the crossing)
        s = state.copy()
        if not is_b(s) and slot >= fork_slot:
            if int(s.slot) < fork_slot:
                spec_a.process_slots(s, spec_a.Slot(fork_slot))
            s = getattr(spec_b, f"upgrade_to_{fork}")(s)
        spec = spec_b if is_b(s) else spec_a
        if int(s.slot) < slot:
            spec.process_slots(s, spec.Slot(slot))
        return s

    def finalized_epochs(state):  # realized and unrealized (compute_pulled_up_tip)
        spec = spec_b if is_b(state) else spec_a
        s = state.copy()
        spec.process_justification_and_finalization(s)
        return max(int(state.finalized_checkpoint.epoch), int(s.finalized_checkpoint.epoch))
    header = pre.latest_block_header.copy()
    if header.state_root == spec_a.Bytes32():
        header.state_root = spec_a.hash_tree_root(pre)
    anchor_root = bytes(spec_a.hash_tree_root(header))
    chain = [(anchor_root, None, pre, None)]  # (root, block, post-state, pre-state P)
    highest = int(spec_a.get_current_epoch(pre))
    bls_active = bls.bls_active
    bls.bls_active = False
    try:
        for i in range(int(meta["blocks_count"])):
            enc = parts[f"blocks_{i}"]
            at = int.from_bytes(enc[:4], "little")
            slot = int.from_bytes(enc[at:at + 8], "little")
            spec = spec_b if slot // spe >= fork_epoch else spec_a
            sb = spec.SignedBeaconBlock.decode_bytes(enc)
            assert bytes(sb.message.parent_root) == chain[-1][0], "transition reads: the blocks are no chain"
            p = bring(chain[-1][2], slot)
            post = p.copy()
            spec.process_block(post, sb.message)
            chain.append((bytes(spec.hash_tree_root(sb.message)), sb.message, post, p))
            highest = max(highest, finalized_epochs(post))
        head_slot = int(chain[-1][1].slot) if len(chain) > 1 else int(pre.slot)

        def chain_state(slot):  # the state of the chain at the slot; past the head's, the head's post-state brought to it
            below = [c for c in chain if (int(c[1].slot) if c[1] is not None else int(pre.slot)) <= slot]
            return bring(below[-1][2], slot)
        requests, answers = [], []

        def ask(op, root, body=None):
            req = api_route.request(ops[op]["method"], api_route.fill(ops[op], {"block_id": qhex(root)[1:-1]}), b"",
                                    body=body or b"", content_type=b"application/json" if body else b"")
            requests.append(http(req, extra=b"Content-Length: %d\r\n" % len(body) if body else b"") + (body or b""))
        ask("getBlockRewards", anchor_root)
        answers.append(error(404))
        ask("getSyncCommitteeRewards", anchor_root)
        answers.append(error(404))
        for k in range(1, len(chain)):
            root, block, _, p = chain[k]
            parent_slot = int(chain[k - 1][1].slot) if k > 1 else int(pre.slot)
            if parent_slot < highest * spe:
                continue
            b_fork = fork if is_b(p) else before
            b_spec = spec_b if is_b(p) else spec_a
            early = late = None
            if b_fork == "phase0":
                b = int(b_spec.get_current_epoch(p))
                early = chain_state((b + 1) * spe - 1) if b > 0 else None
                late = chain_state((b + 2) * spe - 1) if b + 1 < fork_epoch else None
            first, second = run_strict(b_spec, schedule_at(b_fork, fork, fork_epoch),
                                       lambda: reward_answers(b_spec, b_fork, block, p, early, late, False, None))
            ask("getBlockRewards", root)
            answers.append(first)
            ask("getSyncCommitteeRewards", root)
            answers.append(second)
        # getAttestationsRewards of each epoch whose state is the chain's at a block at or above that bound
        for e in range(0, head_slot // spe):
            x = (e + 2) * spe - 1
            if x > head_slot:
                break
            below = [c for c in chain if (int(c[1].slot) if c[1] is not None else int(pre.slot)) <= x][-1]
            if (int(below[1].slot) if below[1] is not None else int(pre.slot)) < highest * spe:
                continue
            s = chain_state(x)
            s_fork = fork if is_b(s) else before
            s_spec = spec_b if is_b(s) else spec_a
            op = ops["getAttestationsRewards"]
            req = api_route.request(op["method"], api_route.fill(op, {"epoch": b"%d" % e}), b"")
            requests.append(http(req))
            answers.append(run_strict(s_spec, schedule_at(s_fork, fork, fork_epoch),
                                      lambda: attestation_rewards_answer(s_spec, s_fork, s, False, x <= highest * spe)))
    finally:
        bls.bls_active = bls_active
    return requests, answers


def schedule_at(fork, last, epoch):
    """The config of a module of fork in a transition to last at epoch: the forks before last at 0, last at epoch."""
    config = {}
    for i, name in enumerate(FORKS[1:], start=1):
        config[f"{name.upper()}_FORK_EPOCH"] = 0 if i < FORKS.index(last) else epoch if name == last else U64
    return config


def transition_read_cases(fork, preset, cases):
    """cases: (name, parts) of the spec's transition core cases of the fork."""
    for name, parts in cases:
        config = schedule_at(fork, fork, int(parts["meta"]["fork_epoch"]))
        spec_b = module(fork, preset)
        texts = run_strict(spec_b, config, lambda: run_strict(module(FORKS[FORKS.index(fork) - 1], preset), config,
                                                               lambda: transition_reads_texts(fork, preset, parts)))
        if texts is not None:
            yield "reads", f"transition/{name}", {"requests": texts[0], "responses": texts[1]}


def read_cases(fork, preset, cases):
    """cases: (handler, name, parts) of the spec's fork_choice get_head and on_block cases of the fork."""
    spec = module(fork, preset)
    for handler, name, parts in cases:
        requests, answers = run_strict(spec, schedule(fork), lambda: reads_texts(spec, fork, parts))
        yield "reads", f"{handler}/{name}", {"requests": requests, "responses": answers}


def event_cases(fork, preset, cases):
    """cases: (handler, name, parts) of the spec's fork_choice get_head and on_block cases of the fork."""
    if fork == "phase0":  # the node runs altair to fulu
        return
    spec = module(fork, preset)
    for handler, name, parts in cases:
        texts = run_strict(spec, schedule(fork), lambda: event_texts(spec, fork, parts))
        yield "events", f"{handler}/{name}", {"events": texts}


def run_strict(spec, config, f):
    """f() with the config changed as run does, its exceptions raised."""
    base = spec.config
    values = dict(base._asdict())
    for key, value in config.items():
        if key in values:
            values[key] = type(values[key])(value)
    spec.config = base.__class__(**values)
    try:
        return f()
    finally:
        spec.config = base


# ---------------------------------------------------------------- The Beacon API (beacon-api.md, Common rules)

REASONS = {200: b"OK", 202: b"Accepted", 206: b"Partial Content", 400: b"Bad Request", 404: b"Not Found", 405: b"Method Not Allowed",
           406: b"Not Acceptable", 413: b"Content Too Large", 414: b"URI Too Long", 415: b"Unsupported Media Type",
           431: b"Request Header Fields Too Large", 500: b"Internal Server Error", 501: b"Not Implemented",
           503: b"Service Unavailable", 505: b"HTTP Version Not Supported"}
MESSAGES = {400: b"BAD_REQUEST", 404: b"NOT_FOUND", 405: b"METHOD_NOT_ALLOWED", 406: b"NOT_ACCEPTABLE",
            413: b"CONTENT_TOO_LARGE", 414: b"URI_TOO_LONG", 415: b"UNSUPPORTED_MEDIA_TYPE",
            431: b"REQUEST_HEADER_FIELDS_TOO_LARGE", 500: b"INTERNAL_SERVER_ERROR", 501: b"NOT_IMPLEMENTED",
            503: b"SERVICE_UNAVAILABLE", 505: b"HTTP_VERSION_NOT_SUPPORTED"}
METHODS = {1: b"GET", 2: b"POST", 3: b"DELETE"}
ALLOW = {1: b"GET", 2: b"POST", 3: b"GET, POST"}
VALIDATOR_OPS = ("getStateValidators", "postStateValidators", "getStateValidator", "getStateValidatorBalances",
                 "postStateValidatorBalances", "postStateValidatorIdentities")
POOL_GETS = ("getPoolVoluntaryExits", "getPoolProposerSlashings", "getPoolAttesterSlashingsV2",
             "getPoolBLSToExecutionChanges", "getPoolAttestationsV2")
POOL_POSTS = ("submitPoolVoluntaryExit", "submitPoolProposerSlashings", "submitPoolAttesterSlashingsV2",
              "submitPoolBLSToExecutionChange", "submitPoolAttestationsV2", "publishAggregateAndProofsV2",
              "submitPoolSyncCommitteeSignatures", "publishContributionAndProofs", "prepareBeaconCommitteeSubnet",
              "prepareSyncCommitteeSubnets", "prepareBeaconProposer")
PENDING = {"getPendingDeposits": "pending_deposits", "getPendingPartialWithdrawals": "pending_partial_withdrawals",
           "getPendingConsolidations": "pending_consolidations"}
ANSWERED = ("getHealth", "getNetworkIdentity", "getNodeVersion", "getSyncingStatus", "getPeerCount", "getGenesis",
            "getBlockHeader", "getStateFinalityCheckpoints", "getBlockV2", "getStateV2", "getBlockRoot", "getStateRoot",
            "getStateFork", "getSpec", "getForkSchedule", "getDepositContract", "getEpochCommittees",
            "getProposerDuties", "produceAttestationData", "getAttesterDuties", "eventstream", "getStateRandao",
            "getEpochSyncCommittees", "getProposerLookahead", "getBlockAttestationsV2", "getBlindedBlock", "getDebugChainHeadsV2", "getDebugForkChoice", "getBlockHeaders", "getPeers", "getPeer", "getBlobSidecars", "getDebugDataColumnSidecars", "getBlobs", "getSyncCommitteeDuties", "getLiveness") + tuple(PENDING) + VALIDATOR_OPS
STATE_READS = ("getStateRandao", "getEpochSyncCommittees", "getProposerLookahead")
IDENTITY = (b"16Uiu2HAmPLe7Mzm8TsYUubgCAW1aJoeFScxrLj8ppHFivPo97bUZ",
            b"enr:-Iu4QLm7bZGdAhVwRqZ6Zf3LlnqKsBTnZGOByHQhPMQJ3pV4F3t8L9i5yJOZ0X0hiZ6q4D5V0jB7l8J3ZtYw1JDH9C4BgmlkgnY0gmlwhAoAAAGJc2VjcDI1NmsxoQPKY0yuDUmstAHYpMa2_oxVtw0RW_QAdpzBQA8yWM0xOIN0Y3CCIyg",
            b"/ip4/10.0.0.1/tcp/9000/p2p/16Uiu2HAmPLe7Mzm8TsYUubgCAW1aJoeFScxrLj8ppHFivPo97bUZ",
            b"/ip4/10.0.0.1/udp/9000/p2p/16Uiu2HAmPLe7Mzm8TsYUubgCAW1aJoeFScxrLj8ppHFivPo97bUZ",
            b"lantern/v0.1.0")
ROOMS = (64, 512, 128, 128, 64)
SLOTS_AHEAD = 5  # the tick is this many slots past the anchor's


def identity_bytes():
    out = b""
    for text, room in zip(IDENTITY, ROOMS):
        assert len(text) <= room and all(0x21 <= c <= 0x7e and c not in b'"\\' for c in text)
        out += len(text).to_bytes(8, "little") + text + bytes(room - len(text))
    assert len(out) == 936
    return out


def response(code, body=b"", close=False, keep_alive=False, allow=0, reason=True, ssz=False):
    out = b"HTTP/1.1 %d " % code + (REASONS[code] if reason else b"") + b"\r\n"
    if body:
        out += b"Content-Type: " + (b"application/octet-stream" if ssz else b"application/json") + b"\r\n"
    out += b"Content-Length: %d\r\n" % len(body)
    if code == 405:
        out += b"Allow: " + ALLOW[allow] + b"\r\n"
    if close:
        out += b"Connection: close\r\n"
    elif keep_alive:
        out += b"Connection: keep-alive\r\n"
    return out + b"\r\n" + body


def streamed(fork, body, ssz=False, close=False, keep_alive=False):
    """A streamed answer (beacon-api.md, Common rules) in its form with Content-Length; with fork None, no
    Eth-Consensus-Version."""
    out = b"HTTP/1.1 200 OK\r\nContent-Type: " + (b"application/octet-stream" if ssz else b"application/json") + b"\r\n"
    if fork is not None:
        out += b"Eth-Consensus-Version: " + fork.encode() + b"\r\n"
    out += b"Content-Length: %d\r\n" % len(body)
    if close:
        out += b"Connection: close\r\n"
    elif keep_alive:
        out += b"Connection: keep-alive\r\n"
    return out + b"\r\n" + body


def error(code, **kw):
    return response(code, b'{"code":%d,"message":"' % code + MESSAGES[code] + b'"}', **kw)


def q(v):
    return b'"%d"' % v


def qhex(b):
    return b'"0x' + bytes(b).hex().encode() + b'"'


def flag(v):
    return b"true" if v else b"false"


def http(req, version=b"HTTP/1.1", connection=b"", extra=b""):
    """The bytes of a request dict of api_route: its method, target and headers."""
    target = req["path"] + (b"?" + req["query"] if req["query"] else b"")
    out = METHODS[req["method"]] + b" " + target + b" " + version + b"\r\nHost: lantern\r\n"
    for name, key in ((b"Accept", "accept"), (b"Content-Type", "content_type"), (b"Eth-Consensus-Version", "consensus_version")):
        if req[key]:
            out += name + b": " + req[key] + b"\r\n"
    if connection:
        out += b"Connection: " + connection + b"\r\n"
    return out + extra + b"\r\n"


def constants(path):
    """The names of the rows of the Constants tables of a beacon-chain.md, in order."""
    names, on = [], False
    for line in path.read_text().split("\n"):
        if line.startswith("## "):
            on = line.strip() == "## Constants"
        elif on and line.startswith("|") and not line.startswith("| Name") and not set(line) <= set("|-: "):
            names.append(line.strip("|").split("|")[0].strip().strip("`"))
    return names


def config_bodies(fork, preset):
    """The bodies of getSpec, getForkSchedule and getDepositContract (beacon-api.md, Common rules): the
    pinned config with the fork epochs of schedule(fork), the presets, and the constants of the fulu
    module. The config keys and their kinds: CONFIG_KEYS of include/lantern.inc (config.md)."""
    import re
    from ruamel.yaml import YAML
    root = pathlib.Path(os.environ["CONSENSUS_SPECS"])
    inc = (pathlib.Path(__file__).resolve().parents[2] / "include" / "lantern.inc").read_text()
    kinds = {}
    for line in re.search(r"\.macro CONFIG_KEYS m\n(.*?)\.endm", inc, re.S).group(1).splitlines():
        name, _, kind = [x.strip() for x in line.strip()[2:].split(",")]
        kinds[name] = kind
    text = (root / "configs" / f"{preset}.yaml").read_text()
    config = dict(YAML(typ="safe").load(text))
    config.update(schedule(fork))
    sizes = {"CONFIG_KIND_VERSION": 4, "CONFIG_KIND_HASH32": 32, "CONFIG_KIND_ADDRESS": 20}

    def value(name):
        v, kind = config[name], kinds[name]
        if kind in sizes:
            return qhex(int(v).to_bytes(sizes[kind], "big"))
        if kind == "CONFIG_KIND_TEXT":
            return b'"' + str(v).encode() + b'"'
        return q(int(v))

    pairs = []
    for name in re.findall(r"^([A-Z_0-9]+):", text, re.M):
        if name == "SLOT_DURATION_MS":
            pairs.append((b"SECONDS_PER_SLOT", q(int(config[name]) // 1000)))
        if name == "BLOB_SCHEDULE":
            pairs.append((b"BLOB_SCHEDULE", b"[" + b",".join(b'{"EPOCH":' + q(e["EPOCH"]) + b',"MAX_BLOBS_PER_BLOCK":' +
                                                            q(e["MAX_BLOBS_PER_BLOCK"]) + b"}" for e in config[name] or []) + b"]"))
        elif name in kinds:
            pairs.append((name.encode(), value(name)))
    assert len(pairs) == len(kinds) + 2
    for f in FORKS:
        for name, v in YAML(typ="safe").load((root / "presets" / preset / f"{f}.yaml").read_text()).items():
            assert isinstance(v, int)
            pairs.append((name.encode(), q(v)))
    last = module("fulu", preset)
    for f in FORKS:
        for name in constants(root / "specs" / f / "beacon-chain.md"):
            v = getattr(last, name)
            if isinstance(v, bytes):
                out = qhex(v)
            elif isinstance(v, str):
                out = b'"' + v.encode() + b'"'
            elif isinstance(v, list):
                out = b"[" + b",".join(q(int(x)) for x in v) + b"]"
            else:
                out = q(int(v))
            pairs.append((name.encode(), out))
    assert len({k for k, _ in pairs}) == len(pairs)
    spec_body = b'{"data":{' + b",".join(b'"' + k + b'":' + v for k, v in pairs) + b"}}"
    version = int(config["GENESIS_FORK_VERSION"]).to_bytes(4, "big")
    forks = [(version, version, 0)]
    for f in FORKS[1:]:
        epoch = int(config[f"{f.upper()}_FORK_EPOCH"])
        if epoch != U64:
            current = int(config[f"{f.upper()}_FORK_VERSION"]).to_bytes(4, "big")
            forks.append((forks[-1][1], current, epoch))
    schedule_body = b'{"data":[' + b",".join(b'{"previous_version":' + qhex(p) + b',"current_version":' + qhex(c) +
                                             b',"epoch":' + q(e) + b"}" for p, c, e in forks) + b"]}"
    deposit_body = (b'{"data":{"chain_id":' + q(int(config["DEPOSIT_CHAIN_ID"])) + b',"address":' +
                    value("DEPOSIT_CONTRACT_ADDRESS") + b"}}")
    return {"getSpec": spec_body, "getForkSchedule": schedule_body, "getDepositContract": deposit_body}


def api_values(spec, fork, state, block):
    """The values of beacon-api.md for the node at its anchor."""
    store = spec.get_forkchoice_store(state, block)
    root = spec.hash_tree_root(block)
    state_root = spec.hash_tree_root(state)
    header = state.latest_block_header.copy()
    if header.state_root == spec.Bytes32():
        header.state_root = state_root
    assert spec.hash_tree_root(header) == root
    from json_codec import to_json

    def cp(c):
        return b'{"epoch":' + q(c.epoch) + b',"root":' + qhex(c.root) + b"}"
    payload = getattr(block.body, "execution_payload", None)
    fork_choice_body = (  # the store holds the anchor alone
        b'{"justified_checkpoint":' + cp(store.justified_checkpoint) + b',"finalized_checkpoint":' +
        cp(store.finalized_checkpoint) + b',"fork_choice_nodes":[{"slot":' + q(block.slot) + b',"block_root":' + qhex(root) +
        b',"parent_root":' + qhex(block.parent_root) + b',"justified_epoch":' + q(state.current_justified_checkpoint.epoch) +
        b',"finalized_epoch":' + q(state.finalized_checkpoint.epoch) + b',"weight":' + q(spec.get_weight(store, root)) +
        b',"validity":"valid","execution_block_hash":' + qhex(payload.block_hash if payload is not None else bytes(32)) + b"}]}")
    states = {int(block.slot): state}  # the anchor state processed to each slot to the store's
    for slot in range(int(block.slot) + 1, int(block.slot) + SLOTS_AHEAD + 1):
        s = state.copy()
        spec.process_slots(s, slot)
        states[slot] = s
    return dict(fork=fork, finalized=store.finalized_checkpoint.root == root, state_ssz=bytes(state.encode_bytes()),
                state_json=to_json(state).encode(), states=states, spec=spec,
                state_roots=[bytes(spec.hash_tree_root(states[s])) for s in (int(block.slot), int(block.slot) + 1)],
                finalized_slot=int(store.finalized_checkpoint.epoch) * int(spec.SLOTS_PER_EPOCH),
                checkpoint_slots={1: int(block.slot), 3: int(store.finalized_checkpoint.epoch) * int(spec.SLOTS_PER_EPOCH),
                                  4: int(store.justified_checkpoint.epoch) * int(spec.SLOTS_PER_EPOCH)},
                genesis_time=int(store.genesis_time_ms) // 1000, gvr=bytes(state.genesis_validators_root),
                genesis_version=bytes(spec.config.GENESIS_FORK_VERSION), root=bytes(root), slot=int(block.slot),
                header=header, cgc=int(spec.config.CUSTODY_REQUIREMENT) if fork == "fulu" else None,
                checkpoints=[state.previous_justified_checkpoint, state.current_justified_checkpoint, state.finalized_checkpoint],
                fork_choice_body=fork_choice_body)


def status_of(spec, val, epoch):
    """The status of a validator at an epoch (beacon-api.md, Common rules)."""
    if val.withdrawable_epoch <= epoch:
        return "withdrawal_done" if val.effective_balance == 0 else "withdrawal_possible"
    if val.exit_epoch <= epoch:
        return "exited_slashed" if val.slashed else "exited_unslashed"
    if val.activation_epoch <= epoch:
        if val.exit_epoch < spec.FAR_FUTURE_EPOCH:
            return "active_slashed" if val.slashed else "active_exiting"
        return "active_ongoing"
    return "pending_initialized" if val.activation_eligibility_epoch == spec.FAR_FUTURE_EPOCH else "pending_queued"


def ref_matches(state, ref):
    """The indices of a ValidatorRef's validators in a state."""
    import struct
    kind, index = struct.unpack_from("<QQ", ref)
    if kind == 1:
        return [index] if index < len(state.validators) else []
    return [i for i, val in enumerate(state.validators) if bytes(val.pubkey) == bytes(ref[16:64])]


def validator_item(spec, state, i, name):
    import api_route
    from json_codec import to_json
    val, epoch = state.validators[i], spec.compute_epoch_at_slot(state.slot)
    if name in ("getStateValidatorBalances", "postStateValidatorBalances"):
        return b'{"index":' + q(i) + b',"balance":' + q(state.balances[i]) + b"}"
    if name == "postStateValidatorIdentities":
        return b'{"index":' + q(i) + b',"pubkey":' + qhex(val.pubkey) + b',"activation_epoch":' + q(val.activation_epoch) + b"}"
    return (b'{"index":' + q(i) + b',"balance":' + q(state.balances[i]) + b',"status":"' +
            status_of(spec, val, epoch).encode() + b'","validator":' + to_json(val).encode() + b"}")


def validators_answer(v, name, route, s, values, kw):
    """The answer of a validator operation for the state s."""
    import api_route
    import struct
    spec = v["spec"]
    if name == "getStateValidator":
        found = ref_matches(s, route.validator)
        if not found:
            return error(404, **kw)
        return response(200, values + b',"data":' + validator_item(spec, s, found[0], name) + b"}", **kw)
    picked = sorted({i for r in route.refs for i in ref_matches(s, r)}) if route.refs else range(len(s.validators))
    epoch = spec.compute_epoch_at_slot(s.slot)
    if route.statuses:
        picked = [i for i in picked
                  if route.statuses >> api_route.STATUSES.index(status_of(spec, s.validators[i], epoch)) & 1]
    if name == "postStateValidatorIdentities" and route.response == 2:
        body = b"".join(struct.pack("<Q", i) + bytes(s.validators[i].pubkey) + struct.pack("<Q", s.validators[i].activation_epoch)
                        for i in picked)
        return streamed(None, body, ssz=True, **kw)
    body = values + b',"data":[' + b",".join(validator_item(spec, s, i, name) for i in picked) + b"]}"
    return streamed(None, body, **kw)


def state_read_answer(v, name, route, s, slot, values, kw):
    """getStateRandao, getEpochSyncCommittees, getProposerLookahead of the state s (beacon-api.md)."""
    import api_route
    spec, fork = v["spec"], v["fork"]  # the case's states are all of its fork
    current = int(spec.get_current_epoch(s))
    epoch = route.epoch if route.present >> api_route.P["epoch"] & 1 else current
    if name == "getStateRandao":
        n = int(spec.EPOCHS_PER_HISTORICAL_VECTOR)
        if epoch > current or current - epoch >= n:
            return error(400, **kw)
        return response(200, values + b',"data":{"randao":' + qhex(s.randao_mixes[epoch % n]) + b"}}", **kw)
    if name == "getEpochSyncCommittees":
        if not hasattr(s, "current_sync_committee"):
            return error(400, **kw)
        period = epoch // int(spec.EPOCHS_PER_SYNC_COMMITTEE_PERIOD)
        own = current // int(spec.EPOCHS_PER_SYNC_COMMITTEE_PERIOD)
        if period not in (own, own + 1):
            return error(400, **kw)
        committee = s.current_sync_committee if period == own else s.next_sync_committee
        keys = [bytes(val.pubkey) for val in s.validators]
        indices = [keys.index(bytes(k)) for k in committee.pubkeys]
        size = len(indices) // int(spec.SYNC_COMMITTEE_SUBNET_COUNT)
        aggregates = [indices[i:i + size] for i in range(0, len(indices), size)]
        body = (values + b',"data":{"validators":[' + b",".join(q(i) for i in indices) + b'],"validator_aggregates":[' +
                b",".join(b"[" + b",".join(q(i) for i in a) + b"]" for a in aggregates) + b"]}}")
        return response(200, body, **kw)
    if not hasattr(s, "proposer_lookahead"):
        return error(400, **kw)
    if route.response == 2:
        return streamed(fork, b"".join(int(i).to_bytes(8, "little") for i in s.proposer_lookahead), ssz=True, **kw)
    body = (b'{"version":"' + fork.encode() + b'",' + values[1:] + b',"data":[' +
            b",".join(q(i) for i in s.proposer_lookahead) + b"]}")
    return streamed(fork, body, **kw)


def committees_answer(v, route, s, values, kw):
    """The answer of getEpochCommittees for the state s (beacon-api.md, Common rules)."""
    import api_route
    spec = v["spec"]
    state_epoch = int(spec.get_current_epoch(s))
    given = lambda name: route.present >> api_route.P[name] & 1
    epoch = route.epoch if given("epoch") else state_epoch
    lowest = max(state_epoch + 1 - int(spec.EPOCHS_PER_HISTORICAL_VECTOR), 0)
    if epoch > state_epoch + 1 or max(epoch - int(spec.MIN_SEED_LOOKAHEAD) - 1, 0) < lowest:
        return error(400, **kw)
    if given("slot") and spec.compute_epoch_at_slot(route.slot) != epoch:
        return error(400, **kw)
    count = int(spec.get_committee_count_per_slot(s, epoch))
    if given("index") and route.index >= count:
        return error(400, **kw)
    first = epoch * int(spec.SLOTS_PER_EPOCH)
    slots = [route.slot] if given("slot") else range(first, first + int(spec.SLOTS_PER_EPOCH))
    indices = [route.index] if given("index") else range(count)
    items = [b'{"index":' + q(i) + b',"slot":' + q(slot) + b',"validators":[' +
             b",".join(q(m) for m in spec.get_beacon_committee(s, spec.Slot(slot), spec.CommitteeIndex(i))) + b"]}"
             for slot in slots for i in indices]
    return streamed(None, values + b',"data":[' + b",".join(items) + b"]}", **kw)


def duties_answer(v, route, kw, syncing):
    """The answer of getProposerDuties (beacon-api.md, Common rules)."""
    spec = v["spec"]
    if syncing:
        return error(503, **kw)
    spe = int(spec.SLOTS_PER_EPOCH)
    store_slot = v["slot"] + SLOTS_AHEAD
    epoch = route.epoch
    if epoch > store_slot // spe + 1:
        return error(400, **kw)
    first = epoch * spe
    if first > store_slot:  # the next epoch: the head's post-state brought to its first slot
        s = v["states"][v["slot"]].copy()
        spec.process_slots(s, first)
    elif first in v["states"]:
        s = v["states"][first]
    else:
        return error(404, **kw)
    items = []
    for slot in range(first, first + spe):
        at = s.copy()
        at.slot = slot
        i = int(spec.get_beacon_proposer_index(at))
        items.append(b'{"pubkey":' + qhex(s.validators[i].pubkey) + b',"validator_index":' + q(i) + b',"slot":' + q(slot) + b"}")
    root = v["root"] if first == 0 else bytes(spec.get_block_root_at_slot(s, first - 1))
    return response(200, b'{"dependent_root":' + qhex(root) + b',"execution_optimistic":false,"data":[' +
                    b",".join(items) + b"]}", **kw)


def att_data_answer(v, route, kw, syncing):
    """The answer of produceAttestationData (beacon-api.md): of the state of the chain at the slot."""
    import api_route
    from json_codec import to_json
    spec = v["spec"]
    if syncing:
        return error(503, **kw)
    if route.slot > v["slot"] + SLOTS_AHEAD or route.slot not in v["states"]:
        return error(400, **kw)
    s = v["states"][route.slot]
    epoch = spec.compute_epoch_at_slot(route.slot)
    root = v["root"]  # the chain is the anchor alone: the state's block
    target = root if spec.compute_start_slot_at_epoch(epoch) == route.slot else spec.get_block_root(s, epoch)
    electra = FORKS.index(v["fork"]) >= FORKS.index("electra")
    data = spec.AttestationData(slot=route.slot, index=0 if electra else route.committee_index, beacon_block_root=root,
                                source=s.current_justified_checkpoint, target=spec.Checkpoint(epoch=epoch, root=target))
    if route.response == api_route.SSZ:
        return response(200, bytes(data.encode_bytes()), ssz=True, **kw)
    return response(200, b'{"data":' + to_json(data).encode() + b"}", **kw)


def sync_duties_answer(v, route, kw, syncing):
    """The answer of getSyncCommitteeDuties (beacon-api.md): the places in the sync committee of `epoch` of each index
    of the body, from the head's post-state for its period and the next, else the state of the epoch's first slot."""
    import struct
    spec = v["spec"]
    if syncing:
        return error(503, **kw)
    spe = int(spec.SLOTS_PER_EPOCH)
    store_slot = v["slot"] + SLOTS_AHEAD
    epoch = route.epoch
    period = spec.compute_sync_committee_period
    if period(spec.Epoch(epoch)) > period(spec.Epoch(store_slot // spe)) + 1:
        return error(400, **kw)
    if not route.refs or any(struct.unpack_from("<Q", r, 0)[0] != 1 for r in route.refs):
        return error(400, **kw)
    head = v["states"][v["slot"]]
    hp = period(spec.get_current_epoch(head))
    if period(spec.Epoch(epoch)) in (hp, hp + 1):
        s = head
    else:
        first = epoch * spe
        if first > store_slot:  # the head's post-state brought to the epoch's first slot
            s = head.copy()
            spec.process_slots(s, first)
        elif first in v["states"]:
            s = v["states"][first]
        else:
            return error(400, **kw)
    sp = period(spec.get_current_epoch(s))
    if period(spec.Epoch(epoch)) == sp:
        pubkeys = list(s.current_sync_committee.pubkeys)
    elif period(spec.Epoch(epoch)) == sp + 1:
        pubkeys = list(s.next_sync_committee.pubkeys)
    else:
        return error(400, **kw)
    items = []
    for r in route.refs:
        i = struct.unpack_from("<Q", r, 8)[0]
        if i >= len(s.validators):
            continue
        places = [k for k, pk in enumerate(pubkeys) if pk == s.validators[i].pubkey]
        if places:
            items.append(b'{"pubkey":' + qhex(s.validators[i].pubkey) + b',"validator_index":' + q(i) +
                         b',"validator_sync_committee_indices":[' + b",".join(q(k) for k in places) + b"]}")
    return response(200, b'{"execution_optimistic":false,"data":[' + b",".join(items) + b"]}", **kw)


def attester_duties_answer(v, route, kw, syncing):
    """The answer of getAttesterDuties (beacon-api.md): get_committee_assignment of each index of the body."""
    import struct
    spec = v["spec"]
    if syncing:
        return error(503, **kw)
    spe = int(spec.SLOTS_PER_EPOCH)
    store_slot = v["slot"] + SLOTS_AHEAD
    epoch = route.epoch
    if epoch > store_slot // spe + 1:
        return error(400, **kw)
    if not route.refs or any(struct.unpack_from("<Q", r, 0)[0] != 1 for r in route.refs):
        return error(400, **kw)
    first = epoch * spe
    if first > store_slot:  # the next epoch: the head's post-state brought to its first slot
        s = v["states"][v["slot"]].copy()
        spec.process_slots(s, first)
    elif first in v["states"]:
        s = v["states"][first]
    else:
        return error(400, **kw)
    count = int(spec.get_committee_count_per_slot(s, spec.Epoch(epoch)))
    items = []
    for r in route.refs:
        i = struct.unpack_from("<Q", r, 8)[0]
        if i >= len(s.validators):
            continue
        a = spec.get_committee_assignment(s, spec.Epoch(epoch), spec.ValidatorIndex(i))
        if a is None:
            continue
        committee, ci, slot = a
        items.append(b'{"pubkey":' + qhex(s.validators[i].pubkey) + b',"validator_index":' + q(i) +
                     b',"committee_index":' + q(ci) + b',"committee_length":' + q(len(committee)) +
                     b',"committees_at_slot":' + q(count) + b',"validator_committee_index":' +
                     q(list(committee).index(i)) + b',"slot":' + q(slot) + b"}")
    if epoch < 2:  # compute_start_slot_at_epoch(epoch - 1) - 1 underflows: the genesis block's root
        root = bytes(spec.get_block_root_at_slot(s, 0)) if s.slot > 0 else v["root"]
    else:
        root = bytes(spec.get_block_root_at_slot(s, spec.compute_start_slot_at_epoch(epoch - 1) - 1))
    return response(200, b'{"dependent_root":' + qhex(root) + b',"execution_optimistic":false,"data":[' +
                    b",".join(items) + b"]}", **kw)


def empty_seen(spec):
    """The spec's Seen with every set and dict empty, as lantern_seen_init makes it."""
    import dataclasses
    return spec.Seen(**{f.name: (dict() if "dict" in str(f.type) else set()) for f in dataclasses.fields(spec.Seen)})


def is_live(spec, fork, state, seen, epoch, index):
    """getLiveness (beacon-api.md): in the beacon chain by the state's epoch lists, on the network and from
    the API by the Seen's keys of the epoch or of its slots."""
    if index >= len(state.validators):
        return False
    cur, prev = int(spec.get_current_epoch(state)), int(spec.get_previous_epoch(state))
    if fork == "phase0":
        for e, atts in ((cur, state.current_epoch_attestations), (prev, state.previous_epoch_attestations)):
            if epoch == e and any(index in spec.get_attesting_indices(state, a) for a in atts):
                return True
    else:
        if epoch == cur and state.current_epoch_participation[index] != 0:
            return True
        if epoch == prev and state.previous_epoch_participation[index] != 0:
            return True
    for keys in (seen.attestation_validator_epochs, seen.aggregator_epochs):
        if any(int(k[0]) == epoch and int(k[1]) == index for k in keys):
            return True
    spe = int(spec.SLOTS_PER_EPOCH)
    slot_sets = [seen.proposer_slots]
    if fork != "phase0":
        slot_sets += [seen.sync_message_validator_slots, seen.sync_contribution_aggregator_slots]
    return any(int(k[1]) == index and int(k[0]) // spe == epoch for keys in slot_sets for k in keys)


def liveness_answer(v, epoch, refs, kw, syncing, seen=None):
    """The answer of getLiveness (beacon-api.md) for the body's ValidatorRef items, with the head's
    post-state, the anchor state at its slot."""
    import struct
    spec = v["spec"]
    if syncing:
        return error(503, **kw)
    store_epoch = (v["slot"] + SLOTS_AHEAD) // int(spec.SLOTS_PER_EPOCH)
    if epoch < max(store_epoch - 1, 0) or epoch > store_epoch + 1:
        return error(400, **kw)
    if not refs or any(struct.unpack_from("<Q", r, 0)[0] != 1 for r in refs):
        return error(400, **kw)
    state = v["states"][v["slot"]]
    seen = seen if seen is not None else empty_seen(spec)
    items = []
    for r in refs:
        i = struct.unpack_from("<Q", r, 8)[0]
        live = is_live(spec, v["fork"], state, seen, epoch, i)
        items.append(b'{"index":' + q(i) + b',"is_live":' + (b"true" if live else b"false") + b"}")
    return response(200, b'{"data":[' + b",".join(items) + b"]}", **kw)


def stream_head(version, connection):
    """The head of an eventstream answer (beacon-api.md, eventstream)."""
    out = b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n"
    if version == b"HTTP/1.0":
        return out + b"Connection: close\r\n\r\n"
    return out + b"Transfer-Encoding: chunked\r\n" + (b"Connection: close\r\n" if connection.lower() == b"close" else b"") + b"\r\n"


def answer(v, name, route, offline, close, keep_alive, syncing=False):
    """The response of an operation the node answers, with the route's ApiRoute."""
    kw = dict(close=close, keep_alive=keep_alive)
    if name == "getProposerDuties":
        return duties_answer(v, route, kw, syncing)
    if name == "produceAttestationData":
        return att_data_answer(v, route, kw, syncing)
    if name == "getAttesterDuties":
        return attester_duties_answer(v, route, kw, syncing)
    if name == "getSyncCommitteeDuties":
        return sync_duties_answer(v, route, kw, syncing)
    if name == "getLiveness":
        return liveness_answer(v, route.epoch, route.refs, kw, syncing)

    current = v["slot"] + SLOTS_AHEAD
    if name == "getHealth":
        if not offline:
            return response(200, **kw)
        if route.syncing_status:
            return response(route.syncing_status, reason=False, **kw)
        return response(206, **kw)
    if name == "getNodeVersion":
        return response(200, b'{"data":{"version":"' + IDENTITY[4] + b'"}}', **kw)
    if name == "getNetworkIdentity":
        meta = b'{"seq_number":"0","attnets":"0x0000000000000000","syncnets":"0x00"'
        if v["cgc"] is not None:
            meta += b',"custody_group_count":' + q(v["cgc"])
        body = (b'{"data":{"peer_id":"' + IDENTITY[0] + b'","enr":"' + IDENTITY[1] + b'","p2p_addresses":["' + IDENTITY[2] +
                b'"],"discovery_addresses":["' + IDENTITY[3] + b'"],"metadata":' + meta + b"}}}")
        return response(200, body, **kw)
    if name == "getSyncingStatus":
        body = (b'{"data":{"head_slot":' + q(v["slot"]) + b',"sync_distance":' + q(current - v["slot"]) +
                b',"is_syncing":false,"is_optimistic":false,"el_offline":' + flag(offline) + b"}}")
        return response(200, body, **kw)
    if name == "getPeerCount":
        return response(200, b'{"data":{"disconnected":"0","connecting":"0","connected":"0","disconnecting":"0"}}', **kw)
    if name in ("getSpec", "getForkSchedule", "getDepositContract"):
        return response(200, v["config_bodies"][name], **kw)
    if name in ("getBlobSidecars", "getDebugDataColumnSidecars"):  # the anchor block, of no sidecars the node holds
        found = (route.id_kind in (1, 3) or (route.id_kind == 5 and route.id_slot == v["slot"]) or
                 (route.id_kind == 2 and v["slot"] == 0) or (route.id_kind == 6 and route.id_root == v["root"]))
        if not found:
            return error(404, **kw)
        blobs, fork = name == "getBlobSidecars", v["fork"]
        if (blobs and fork not in ("deneb", "electra")) or (not blobs and fork != "fulu"):
            return error(400, **kw)
        if route.response == 2:
            return streamed(fork, b"", ssz=True, **kw)
        return streamed(fork, b'{"version":"' + fork.encode() + b'","execution_optimistic":false,"finalized":true,"data":[]}', **kw)
    if name == "getBlobs":  # the anchor block, of no sidecars the node holds: no blob
        found = (route.id_kind in (1, 3) or (route.id_kind == 5 and route.id_slot == v["slot"]) or
                 (route.id_kind == 2 and v["slot"] == 0) or (route.id_kind == 6 and route.id_root == v["root"]))
        if not found:
            return error(404, **kw)
        if route.response == 2:
            return streamed(None, b"", ssz=True, **kw)
        return streamed(None, b'{"execution_optimistic":false,"finalized":true,"data":[]}', **kw)
    if name == "getPeers":  # the node has no peers
        return response(200, b'{"data":[],"meta":{"count":0}}', **kw)
    if name == "getPeer":
        return error(404, **kw)
    if name == "getBlockHeaders":  # the node holds the anchor alone, with no bytes: its header as getBlockHeader's
        h = v["header"]
        slot_given, root_given = route.present >> 7 & 1, route.present >> 13 & 1
        slot = route.slot if slot_given else (None if root_given else v["slot"])
        if (slot is None or slot == v["slot"]) and (not root_given or route.root == bytes(h.parent_root)):
            item = (b'{"root":' + qhex(v["root"]) + b',"canonical":true,"header":{"message":{"slot":' + q(h.slot) +
                    b',"proposer_index":' + q(h.proposer_index) + b',"parent_root":' + qhex(h.parent_root) + b',"state_root":' +
                    qhex(h.state_root) + b',"body_root":' + qhex(h.body_root) + b'},"signature":' + qhex(bytes(96)) + b"}}")
            body = b'{"execution_optimistic":false,"finalized":true,"data":[' + item + b"]}"
        else:
            body = b'{"execution_optimistic":false,"finalized":false,"data":[]}'
        return streamed(None, body, **kw)
    if name == "getDebugForkChoice":
        return response(200, v["fork_choice_body"], **kw)
    if name == "getDebugChainHeadsV2":  # the store holds the anchor alone: one leaf
        return response(200, b'{"data":[{"root":' + qhex(v["root"]) + b',"slot":' + q(v["slot"]) +
                        b',"execution_optimistic":false}]}', **kw)
    if name == "getGenesis":
        body = (b'{"data":{"genesis_time":' + q(v["genesis_time"]) + b',"genesis_validators_root":' + qhex(v["gvr"]) +
                b',"genesis_fork_version":' + qhex(v["genesis_version"]) + b"}}")
        return response(200, body, **kw)
    if name in ("getBlockHeader", "getBlockRoot", "getBlockV2", "getBlockAttestationsV2", "getBlindedBlock"):
        # The chain is the anchor alone: head, finalized, its slot and its root name it.
        found = (route.id_kind in (1, 3) or (route.id_kind == 5 and route.id_slot == v["slot"]) or
                 (route.id_kind == 2 and v["slot"] == 0) or (route.id_kind == 6 and route.id_root == v["root"]))
        if not found or name in ("getBlockV2", "getBlockAttestationsV2", "getBlindedBlock"):  # the anchor block's bytes are not the node's
            return error(404, **kw)
        values = b'{"execution_optimistic":false,"finalized":true,"data":{"root":' + qhex(v["root"])
        if name == "getBlockRoot":
            return response(200, values + b"}}", **kw)
        h = v["header"]
        body = (values + b',"canonical":true,"header":{"message":{"slot":' + q(h.slot) + b',"proposer_index":' + q(h.proposer_index) +
                b',"parent_root":' + qhex(h.parent_root) + b',"state_root":' + qhex(h.state_root) + b',"body_root":' +
                qhex(h.body_root) + b'},"signature":' + qhex(bytes(96)) + b"}}}")
        return response(200, body, **kw)
    if name in ("getStateRoot", "getStateFork", "getStateFinalityCheckpoints", "getStateV2", "getEpochCommittees") + VALIDATOR_OPS + \
            STATE_READS + tuple(PENDING):
        if route.id_kind in v["checkpoint_slots"]:
            slot = v["checkpoint_slots"][route.id_kind]
        elif route.id_kind == 5 or (route.id_kind == 2):
            slot = route.id_slot if route.id_kind == 5 else 0
        else:  # a state root: the head state's own, else the highest slot of its state_roots below it
            spec, head = v["spec"], v["states"][v["slot"]]
            n, slot = int(spec.SLOTS_PER_HISTORICAL_ROOT), None
            if bytes(spec.hash_tree_root(head)) == route.id_root:
                slot = v["slot"]
            else:
                for s in range(v["slot"] - 1, max(0, v["slot"] - n) - 1, -1):
                    if bytes(head.state_roots[s % n]) == route.id_root:
                        slot = s
                        break
            if slot is None:
                return error(404, **kw)
        if slot not in v["states"]:
            return error(404, **kw)
        s, spec = v["states"][slot], v["spec"]
        values = b'{"execution_optimistic":false,"finalized":' + flag(slot <= v["finalized_slot"])
        if name in VALIDATOR_OPS:
            return validators_answer(v, name, route, s, values, kw)
        if name == "getEpochCommittees":
            return committees_answer(v, route, s, values, kw)
        if name in STATE_READS:
            return state_read_answer(v, name, route, s, slot, values, kw)
        if name in PENDING:
            if not hasattr(s, PENDING[name]):
                return error(400, **kw)
            items = list(getattr(s, PENDING[name]))
            if route.response == 2:
                return streamed(v["fork"], b"".join(bytes(x.encode_bytes()) for x in items), ssz=True, **kw)
            from json_codec import to_json
            body = (b'{"version":"' + v["fork"].encode() + b'",' + values[1:] + b',"data":[' +
                    b",".join(to_json(x).encode() for x in items) + b"]}")
            return streamed(v["fork"], body, **kw)
        if name == "getStateRoot":
            return response(200, values + b',"data":{"root":' + qhex(spec.hash_tree_root(s)) + b"}}", **kw)
        if name == "getStateFork":
            f = s.fork
            return response(200, values + b',"data":{"previous_version":' + qhex(f.previous_version) + b',"current_version":' +
                            qhex(f.current_version) + b',"epoch":' + q(f.epoch) + b"}}", **kw)
        if name == "getStateFinalityCheckpoints":
            c = [s.previous_justified_checkpoint, s.current_justified_checkpoint, s.finalized_checkpoint]
            body = (values + b',"data":{"previous_justified":{"epoch":' + q(c[0].epoch) +
                    b',"root":' + qhex(c[0].root) + b'},"current_justified":{"epoch":' + q(c[1].epoch) + b',"root":' +
                    qhex(c[1].root) + b'},"finalized":{"epoch":' + q(c[2].epoch) + b',"root":' + qhex(c[2].root) + b"}}}")
            return response(200, body, **kw)
        if route.response == 2:
            return streamed(v["fork"], bytes(s.encode_bytes()), ssz=True, **kw)
        from json_codec import to_json
        body = (b'{"version":"' + v["fork"].encode() + b'",' + values[1:] + b',"data":' + to_json(s).encode() + b"}")
        return streamed(v["fork"], body, **kw)
    raise AssertionError(name)


class Route:
    """The fields of an ApiRoute the answers read, from api_route.route."""
    def __init__(self, out):
        import struct
        self.op = struct.unpack_from("<Q", out, 16)[0]
        self.response = struct.unpack_from("<Q", out, 48)[0]
        self.id_kind = struct.unpack_from("<Q", out, 72)[0]
        self.id_slot = struct.unpack_from("<Q", out, 80)[0]
        self.id_root = bytes(out[88:120])
        self.syncing_status = struct.unpack_from("<Q", out, 240)[0]
        self.validator = bytes(out[120:184])
        self.present = struct.unpack_from("<Q", out, 40)[0]
        self.root = bytes(out[296:328])
        self.epoch, self.slot, self.index, self.committee_index = struct.unpack_from("<QQQQ", out, 184)
        self.statuses = struct.unpack_from("<Q", out, 264)[0]
        at, count = struct.unpack_from("<QQ", out, 456)
        self.refs = [bytes(out[at + 64 * k:at + 64 * k + 64]) for k in range(count)]


def gossip_result(spec, fn, *args):
    """VALID, IGNORE or REJECT of a gossip validation of the spec module."""
    try:
        fn(*args)
    except spec.GossipIgnore:
        return "IGNORE"
    except spec.GossipReject:
        return "REJECT"
    return "VALID"


def pool_requests(spec, fork, v, by_name, add):
    """The pool POSTs and GETs (beacon-api.md, The pools) of a node at the anchor of v: the answers from
    the spec's gossip validation with a Seen the requests fill, each request run twice."""
    import dataclasses
    import api_route
    from json_codec import to_json
    from eth_consensus_specs.utils import bls
    state = v["states"][v["slot"]].copy()
    store = spec.get_forkchoice_store(state, v["block"])
    spec.on_tick(store, v["time_ms"])
    seen = spec.Seen(**{f.name: (dict() if "dict" in str(f.type) else set()) for f in dataclasses.fields(spec.Seen)})
    time_ms = v["time_ms"]
    epoch = int(spec.get_current_epoch(state))
    capella = FORKS.index(fork) >= FORKS.index("capella")
    electra = FORKS.index(fork) >= FORKS.index("electra")
    pool = {"exit": [], "proposer": [], "attester": [], "bls": [], "attestation": [], "aggregate": [], "sync": [],
            "contribution": []}

    def validate(kind, op):
        if kind == "exit":
            return gossip_result(spec, spec.validate_voluntary_exit_gossip, seen, store, op, time_ms)
        if kind == "proposer":
            return gossip_result(spec, spec.validate_proposer_slashing_gossip, seen, store, op)
        if kind == "attester":
            return gossip_result(spec, spec.validate_attester_slashing_gossip, seen, store, op)
        if kind == "attestation":
            return gossip_result(spec, spec.validate_beacon_attestation_gossip, seen, store, op, time_ms, subnet_of(op))
        if kind == "aggregate":
            return gossip_result(spec, spec.validate_beacon_aggregate_and_proof_gossip, seen, store, op, time_ms)
        if kind == "contribution":
            return gossip_result(spec, spec.validate_sync_committee_contribution_and_proof_gossip, seen, store, op,
                                 time_ms)
        if kind == "sync":  # each subnet of compute_subnets_for_sync_committee, else subnet 0 (beacon-api.md)
            head = spec.get_head(store)
            hs = store.block_states[getattr(head, "root", head)]
            subnets = sorted(spec.compute_subnets_for_sync_committee(hs, op.validator_index)) \
                if op.validator_index < len(hs.validators) else []
            results = [gossip_result(spec, spec.validate_sync_committee_message_gossip, seen, store, op, time_ms, n)
                       for n in subnets or [0]]
            return "VALID" if "VALID" in results else "REJECT" if "REJECT" in results else results[-1]
        return gossip_result(spec, spec.validate_bls_to_execution_change_gossip, seen, store, op, time_ms)

    def bad_request(close, keep_alive, failures=None):
        body = b'{"code":400,"message":"BAD_REQUEST"'
        if failures is not None:
            body += b',"failures":[' + b",".join(b'{"index":%d,"message":"REJECT"}' % i for i in failures) + b"]"
        return response(400, body + b"}", close=close, keep_alive=keep_alive)

    # the operation events (beacon-api.md): a stream open from here to the case's end, its bytes in a box
    event_topics = {"exit": "voluntary_exit", "proposer": "proposer_slashing", "attester": "attester_slashing",
                    "bls": "bls_to_execution_change", "contribution": "contribution_and_proof",
                    "attestation": "single_attestation" if FORKS.index(fork) >= FORKS.index("electra") else "attestation"}
    events_box = [stream_head(b"HTTP/1.1", b"")]
    topics_query = b"topics=attestation,single_attestation,voluntary_exit,bls_to_execution_change,proposer_slashing," \
                   b"attester_slashing,contribution_and_proof"
    add("events_operations", api_route.request(by_name["eventstream"]["method"], api_route.fill(by_name["eventstream"], None),
                                               topics_query), want=lambda c, k: events_box, stream=2)

    def submit(name, op_name, kind, ops, body, single=True, headers=None, content_type=b"application/json"):
        """ops: the decoded operations, or None for a body of none; run twice, as the runner does."""
        answers = []
        for run_index in range(2):
            if ops is None:
                answers.append(("bad", None))
                continue
            results = [validate(kind, op) for op in ops]
            for op, r in zip(ops, results):
                if r == "VALID":
                    pool[kind].append(pool_form(op) if kind == "attestation" else op)
                    if run_index == 0 and kind in event_topics:
                        text = b"event: " + event_topics[kind].encode() + b"\ndata: " + to_json(op).encode() + b"\n\n"
                        events_box[0] += b"%04x\r\n" % len(text) + text + b"\r\n"
            failures = [i for i, r in enumerate(results) if r == "REJECT"]
            answers.append(("ok", None) if not failures else ("bad", None if single else failures))
        if answers[0] != answers[1]:
            raise RuntimeError(f"{name}: the two runs answer differently")
        status, failures = answers[0]
        want = (lambda c, k: response(200, close=c, keep_alive=k)) if status == "ok" else \
            (lambda c, k: bad_request(c, k, failures))
        req = api_route.request(by_name[op_name]["method"], api_route.fill(by_name[op_name], None), b"",
                                content_type=content_type, **(headers or {}))
        add(name, req, body=body, want=want)
        return status, failures

    def exit_of(index, key_index):
        """Signed as the spec's test helpers sign: from deneb with capella's fork version (EIP-7044)."""
        ex = spec.VoluntaryExit(epoch=epoch, validator_index=index)
        if FORKS.index(fork) >= FORKS.index("deneb"):
            domain = spec.compute_domain(spec.DOMAIN_VOLUNTARY_EXIT, spec.config.CAPELLA_FORK_VERSION,
                                         state.genesis_validators_root)
        else:
            domain = spec.get_domain(state, spec.DOMAIN_VOLUNTARY_EXIT, ex.epoch)
        return spec.SignedVoluntaryExit(message=ex, signature=bls.Sign(KEYS.privkeys[key_index],
                                                                       spec.compute_signing_root(ex, domain)))

    def header_of(index, body):
        h = spec.BeaconBlockHeader(slot=state.slot, proposer_index=index, parent_root=b"\x03" * 32,
                                   state_root=b"\x04" * 32, body_root=body)
        domain = spec.get_domain(state, spec.DOMAIN_BEACON_PROPOSER, spec.compute_epoch_at_slot(h.slot))
        return spec.SignedBeaconBlockHeader(message=h, signature=bls.Sign(KEYS.privkeys[index],
                                                                          spec.compute_signing_root(h, domain)))

    def indexed_of(indices, root):
        data = spec.AttestationData(slot=state.slot, index=0, beacon_block_root=root,
                                    source=state.current_justified_checkpoint,
                                    target=spec.Checkpoint(epoch=epoch, root=root))
        domain = spec.get_domain(state, spec.DOMAIN_BEACON_ATTESTER, data.target.epoch)
        sr = spec.compute_signing_root(data, domain)
        ia = spec.IndexedAttestation(data=data, signature=bls.Aggregate([bls.Sign(KEYS.privkeys[i], sr) for i in indices]))
        for i in indices:
            ia.attesting_indices.append(i)
        return ia

    def change_of(index, key_index):
        c = spec.BLSToExecutionChange(validator_index=index, from_bls_pubkey=KEYS.pubkeys[8191 - index],
                                      to_execution_address=b"\x42" * 20)
        domain = spec.compute_domain(spec.DOMAIN_BLS_TO_EXECUTION_CHANGE, genesis_validators_root=state.genesis_validators_root)
        return spec.SignedBLSToExecutionChange(message=c, signature=bls.Sign(KEYS.privkeys[key_index],
                                                                             spec.compute_signing_root(c, domain)))

    good_exit = exit_of(2, 2)
    submit("pool_exit", "submitPoolVoluntaryExit", "exit", [good_exit], to_json(good_exit).encode())
    submit("pool_exit_again", "submitPoolVoluntaryExit", "exit", [good_exit], to_json(good_exit).encode())
    bad_exit = exit_of(3, 4)
    submit("pool_exit_other_key", "submitPoolVoluntaryExit", "exit", [bad_exit], to_json(bad_exit).encode())
    submit("pool_exit_no_exit", "submitPoolVoluntaryExit", "exit", None, b'{"message":{"epoch":"1"}}')
    ps = spec.ProposerSlashing(signed_header_1=header_of(4, b"\x01" * 32), signed_header_2=header_of(4, b"\x02" * 32))
    submit("pool_proposer", "submitPoolProposerSlashings", "proposer", [ps], to_json(ps).encode())
    same = spec.ProposerSlashing(signed_header_1=header_of(0, b"\x01" * 32), signed_header_2=header_of(0, b"\x01" * 32))
    submit("pool_proposer_equal", "submitPoolProposerSlashings", "proposer", [same], to_json(same).encode())
    ats = spec.AttesterSlashing(attestation_1=indexed_of([5, 6], b"\x05" * 32), attestation_2=indexed_of([5, 6], b"\x06" * 32))
    submit("pool_attester", "submitPoolAttesterSlashingsV2", "attester", [ats], to_json(ats).encode(),
           headers={"version": fork.encode()})
    other = b"deneb" if electra else b"electra"
    submit("pool_attester_other_fork", "submitPoolAttesterSlashingsV2", "attester", None, to_json(ats).encode(),
           headers={"version": other})
    if capella:
        c1 = change_of(1, 8191 - 1)
        c3 = change_of(3, 8191 - 1)  # another key's signature
        c7 = change_of(7, 8191 - 7)
        changes = [c1, c3, c7]
        body = ("[" + ",".join(to_json(c) for c in changes) + "]").encode()
        submit("pool_bls", "submitPoolBLSToExecutionChange", "bls", changes, body, single=False)
        bad = ("[" + to_json(c1) + ',{"message":1}]').encode()
        submit("pool_bls_bad_item", "submitPoolBLSToExecutionChange", "bls", None, bad, single=False)
    else:  # before capella the fork has no such type
        submit("pool_bls", "submitPoolBLSToExecutionChange", "bls", None, b"[]", single=False)
    # attestations of the committees of the slots after the anchor's: valid, again, with another
    # key's signature, of the other fork's type, of no attestation, and as SSZ
    duties = []  # (slot, committee index, place, member, committee length)
    for att_slot in range(v["slot"] + 1, v["slot"] + SLOTS_AHEAD + 1):
        s_at = v["states"][att_slot]
        for c in range(int(spec.get_committee_count_per_slot(s_at, spec.compute_epoch_at_slot(att_slot)))):
            committee = list(spec.get_beacon_committee(s_at, spec.Slot(att_slot), spec.CommitteeIndex(c)))
            duties += [(att_slot, c, p, m, len(committee)) for p, m in enumerate(committee)]

    def subnet_of(att):
        index = att.committee_index if electra else att.data.index
        count = spec.get_committee_count_per_slot(state, att.data.target.epoch)
        return spec.compute_subnet_for_attestation(count, att.data.slot, index)

    def att_of(duty, key_index):
        att_slot, c, place, member, length = duty
        s_at = v["states"][att_slot]
        att_epoch = spec.compute_epoch_at_slot(att_slot)
        boundary = spec.compute_start_slot_at_epoch(att_epoch)
        data = spec.AttestationData(slot=att_slot, index=0 if electra else c, beacon_block_root=v["root"],
                                    source=s_at.current_justified_checkpoint,
                                    target=spec.Checkpoint(epoch=att_epoch, root=v["root"] if boundary == att_slot
                                                           else spec.get_block_root(s_at, att_epoch)))
        domain = spec.get_domain(s_at, spec.DOMAIN_BEACON_ATTESTER, att_epoch)
        sig = bls.Sign(KEYS.privkeys[key_index], spec.compute_signing_root(data, domain))
        if electra:
            return spec.SingleAttestation(committee_index=c, attester_index=member, data=data, signature=sig)
        bits = spec.AggregationBits(data=[False] * length)
        bits[place] = True
        return spec.Attestation(aggregation_bits=bits, data=data, signature=sig)

    def pool_form(att):
        """(slot, committee index, the pool's Attestation): from electra the Attestation of the
        SingleAttestation's one attester in its committee of the head state, as the node gives it."""
        if not electra:
            return int(att.data.slot), int(att.data.index), att
        head = spec.get_head(store)
        hs = store.block_states[getattr(head, "root", head)]
        committee = list(spec.get_beacon_committee(hs, att.data.slot, att.committee_index))
        bits = spec.AggregationBits(data=[False] * len(committee))
        bits[committee.index(att.attester_index)] = True
        out = spec.Attestation(aggregation_bits=bits, data=att.data, signature=att.signature)
        out.committee_bits[att.committee_index] = True
        return int(att.data.slot), int(att.committee_index), out

    def json_list(items):
        return ("[" + ",".join(to_json(x) for x in items) + "]").encode()

    def ssz_list(items):  # the SSZ list: fixed size items back to back, else 4-byte offsets first
        parts = [bytes(x.encode_bytes()) for x in items]
        if electra:
            return b"".join(parts)
        offsets, at = b"", 4 * len(parts)
        for p in parts:
            offsets += at.to_bytes(4, "little")
            at += len(p)
        return offsets + b"".join(parts)
    att_version = {"version": fork.encode()}
    two = [att_of(duties[0], duties[0][3]), att_of(duties[1], duties[1][3])]
    submit("pool_attestations", "submitPoolAttestationsV2", "attestation", two, json_list(two), single=False,
           headers=att_version)
    submit("pool_attestations_again", "submitPoolAttestationsV2", "attestation", two[:1], json_list(two[:1]),
           single=False, headers=att_version)
    other_key = [att_of(duties[2], duties[3][3]), att_of(duties[3], duties[3][3])]
    submit("pool_attestations_other_key", "submitPoolAttestationsV2", "attestation", other_key,
           json_list(other_key), single=False, headers=att_version)
    submit("pool_attestations_other_fork", "submitPoolAttestationsV2", "attestation", None, json_list(two),
           single=False, headers={"version": other})
    submit("pool_attestations_no_attestation", "submitPoolAttestationsV2", "attestation", None, b'[{"data":1}]',
           single=False, headers=att_version)
    # the SSZ one: of another slot, and of another committee when the slots have two
    ssz_duty = next((d for d in duties if d[0] != duties[0][0] and d[1] != duties[0][1]), None) or \
        next(d for d in duties if d[0] != duties[0][0])
    ssz_body = ssz_list([att_of(ssz_duty, ssz_duty[3])])
    submit("pool_attestations_ssz", "submitPoolAttestationsV2", "attestation", [att_of(ssz_duty, ssz_duty[3])], ssz_body,
           single=False, headers=att_version, content_type=b"application/octet-stream")
    store_fork = fork

    def listing(items, version=None):
        body = b'{"data":[' + b",".join(to_json(x).encode() for x in items) + b"]}"
        if version:
            body = b'{"version":"' + version.encode() + b'",' + body[1:]
        return lambda c, k: streamed(version, body, close=c, keep_alive=k)

    for name, op_name, items, version in (("pool_get_exits", "getPoolVoluntaryExits", pool["exit"], None),
                                          ("pool_get_proposer", "getPoolProposerSlashings", pool["proposer"], None),
                                          ("pool_get_attester", "getPoolAttesterSlashingsV2", pool["attester"], store_fork),
                                          ("pool_get_bls", "getPoolBLSToExecutionChanges", pool["bls"], None)):
        for http in (b"HTTP/1.1", b"HTTP/1.0"):
            add(f"{name}_{http.decode()[5:]}", api_route.base(by_name[op_name]), version=http, want=listing(items, version))
    # the attestations: all, then by slot, by committee index, by both, and by a slot of none
    atts = pool["attestation"]
    if len({a[0] for a in atts}) < 2:
        raise RuntimeError("pool_get_attestations: the cases need attestations of two slots")
    first_slot, first_index = atts[0][0], atts[0][1]
    for http in (b"HTTP/1.1", b"HTTP/1.0"):
        add(f"pool_get_attestations_{http.decode()[5:]}", api_route.base(by_name["getPoolAttestationsV2"]),
            version=http, want=listing([a[2] for a in atts], store_fork))
    for name, slot, index in (("slot", first_slot, None), ("index", None, first_index),
                              ("both", first_slot, first_index), ("none", 2**63, None)):
        query = []
        if slot is not None:
            query.append(("slot", b"%d" % slot))
        if index is not None:
            query.append(("committee_index", b"%d" % index))
        items = [a[2] for a in atts if (slot is None or a[0] == slot) and (index is None or a[1] == index)]
        add(f"pool_get_attestations_{name}", api_route.base(by_name["getPoolAttestationsV2"], query),
            want=listing(items, store_fork))
    # getAggregatedAttestationV2: the aggregate of the first attestation's data in pool order, a place
    # once, as JSON (HTTP/1.1 and 1.0) and SSZ; 404 for a root of no data and for a slot of none
    agg_op = by_name["getAggregatedAttestationV2"]
    first = atts[0][2]
    data_root = spec.hash_tree_root(first.data)
    length = len(first.aggregation_bits)
    bits, sigs = spec.AggregationBits(data=[False] * length), []
    for a_slot, a_index, a in atts:
        if a_slot != first_slot or a_index != first_index or spec.hash_tree_root(a.data) != data_root:
            continue
        place = next(i for i, b in enumerate(a.aggregation_bits) if b)
        if len(a.aggregation_bits) != length or bits[place]:
            continue
        bits[place] = True
        sigs.append(a.signature)
    if len(sigs) < 2:
        raise RuntimeError("aggregate: the cases need two attestations of one data")
    agg = spec.Attestation(aggregation_bits=bits, data=first.data, signature=bls.Aggregate(sigs))
    if electra:
        agg.committee_bits[first_index] = True
    agg_body = b'{"version":"' + store_fork.encode() + b'","data":' + to_json(agg).encode() + b"}"

    def agg_request(root, slot, index, accept=b""):
        query = b"attestation_data_root=0x" + bytes(root).hex().encode() + b"&slot=%d&committee_index=%d" % (slot, index)
        return api_route.request(agg_op["method"], api_route.fill(agg_op), query, accept=accept)
    for http in (b"HTTP/1.1", b"HTTP/1.0"):
        add(f"aggregate_{http.decode()[5:]}", agg_request(data_root, first_slot, first_index), version=http,
            want=lambda c, k: streamed(store_fork, agg_body, close=c, keep_alive=k))
    add("aggregate_ssz", agg_request(data_root, first_slot, first_index, accept=b"application/octet-stream"),
        want=lambda c, k: streamed(store_fork, bytes(agg.encode_bytes()), ssz=True, close=c, keep_alive=k))
    add("aggregate_other_root", agg_request(b"\x07" * 32, first_slot, first_index),
        want=lambda c, k: error(404, close=c, keep_alive=k))
    add("aggregate_other_slot", agg_request(data_root, first_slot + 1000, first_index),
        want=lambda c, k: error(404, close=c, keep_alive=k))

    # publishAggregateAndProofsV2: the aggregate above by an aggregator of its committee (each member is
    # one: committees below TARGET_AGGREGATORS_PER_COMMITTEE), again (seen), one signed with another
    # key, with a fork of the other type, of no aggregate, and as SSZ the aggregate of another slot
    def signed_aggregate(duty, aggregate, key_index):
        s_at = v["states"][duty[0]]
        proof = spec.get_aggregate_and_proof(s_at, duty[3], aggregate, KEYS.privkeys[key_index])
        return spec.SignedAggregateAndProof(message=proof, signature=spec.get_aggregate_and_proof_signature(
            s_at, proof, KEYS.privkeys[key_index]))

    def ssz_offsets(items):  # the SSZ list of variable size items: 4-byte offsets, then the items
        parts = [bytes(x.encode_bytes()) for x in items]
        offsets, at = b"", 4 * len(parts)
        for p in parts:
            offsets += at.to_bytes(4, "little")
            at += len(p)
        return offsets + b"".join(parts)
    first_duty = next(d for d in duties if d[0] == first_slot and d[1] == first_index)
    good_agg = signed_aggregate(first_duty, agg, first_duty[3])
    submit("aggregate_post", "publishAggregateAndProofsV2", "aggregate", [good_agg], json_list([good_agg]),
           single=False, headers=att_version)
    submit("aggregate_post_again", "publishAggregateAndProofsV2", "aggregate", [good_agg], json_list([good_agg]),
           single=False, headers=att_version)
    ssz_att = next(a[2] for a in atts if a[0] != first_slot)
    ssz_agg_duty = next(d for d in duties if d[0] == int(ssz_att.data.slot) and
                        d[1] == (next(i for i, b in enumerate(ssz_att.committee_bits) if b) if electra else int(ssz_att.data.index)))
    other_agg = signed_aggregate(ssz_agg_duty, ssz_att, ssz_agg_duty[3] + 1)  # another key
    rejected = submit("aggregate_post_other_key", "publishAggregateAndProofsV2", "aggregate", [other_agg], json_list([other_agg]),
           single=False, headers=att_version)
    submit("aggregate_post_other_fork", "publishAggregateAndProofsV2", "aggregate", None, json_list([good_agg]),
           single=False, headers={"version": other})
    submit("aggregate_post_no_aggregate", "publishAggregateAndProofsV2", "aggregate", None, b'[{"message":1}]',
           single=False, headers=att_version)
    ssz_good = signed_aggregate(ssz_agg_duty, ssz_att, ssz_agg_duty[3])
    submit("aggregate_post_ssz", "publishAggregateAndProofsV2", "aggregate", [ssz_good], ssz_offsets([ssz_good]),
           single=False, headers=att_version, content_type=b"application/octet-stream")
    if rejected != ("bad", [0]) or len(pool["aggregate"]) != 2:
        raise RuntimeError("aggregate POSTs: the cases need two valid aggregates and one rejected")

    # submitPoolSyncCommitteeSignatures, from altair: messages of the store's slot for the head of
    # members of the head state's sync committee: two valid, one again (seen), one with another key's
    # signature and a valid one, one of a validator outside the committee, and of no message
    if FORKS.index(fork) >= FORKS.index("altair"):
        head = spec.get_head(store)
        hs = store.block_states[getattr(head, "root", head)]
        msg_slot = int(spec.get_current_slot(store))
        by_key = {bytes(val.pubkey): i for i, val in enumerate(hs.validators)}
        members = list(dict.fromkeys(by_key[bytes(k)] for k in hs.current_sync_committee.pubkeys))
        outside = next(i for i in range(len(hs.validators)) if i not in members)
        domain = spec.get_domain(hs, spec.DOMAIN_SYNC_COMMITTEE, spec.compute_epoch_at_slot(msg_slot))

        def sync_msg(index, key_index):
            sig = bls.Sign(KEYS.privkeys[key_index], spec.compute_signing_root(spec.Root(v["root"]), domain))
            return spec.SyncCommitteeMessage(slot=msg_slot, beacon_block_root=v["root"], validator_index=index,
                                             signature=sig)
        if len(members) < 4:
            raise RuntimeError("sync POSTs: the cases need four members of the sync committee")
        two_sync = [sync_msg(members[0], members[0]), sync_msg(members[1], members[1])]
        submit("sync_post", "submitPoolSyncCommitteeSignatures", "sync", two_sync, json_list(two_sync), single=False)
        submit("sync_post_again", "submitPoolSyncCommitteeSignatures", "sync", two_sync[:1], json_list(two_sync[:1]),
               single=False)
        bad_sync = [sync_msg(members[2], members[3]), sync_msg(members[3], members[3])]
        r1 = submit("sync_post_other_key", "submitPoolSyncCommitteeSignatures", "sync", bad_sync, json_list(bad_sync),
                    single=False)
        out_sync = [sync_msg(outside, outside)]
        r2 = submit("sync_post_outside", "submitPoolSyncCommitteeSignatures", "sync", out_sync, json_list(out_sync),
                    single=False)
        submit("sync_post_no_message", "submitPoolSyncCommitteeSignatures", "sync", None, b'[{"slot":"1"}]',
               single=False)
        if r1 != ("bad", [0]) or r2 != ("bad", [0]) or len(pool["sync"]) != 3:
            raise RuntimeError("sync POSTs: the cases need three valid messages and two rejected")

        # produceSyncCommitteeContribution: the pool's messages of the slot and root in the subcommittee
        # of the first message's first subnet, each place once, a signature per place (altair
        # validator.md); another root, a slot of none (404); NOT_VALIDATED nodes (503); a
        # subcommittee index past SYNC_COMMITTEE_SUBNET_COUNT (400)
        sub_size = int(spec.SYNC_COMMITTEE_SIZE) // int(spec.SYNC_COMMITTEE_SUBNET_COUNT)
        same_period = spec.compute_sync_committee_period(spec.get_current_epoch(hs)) == \
            spec.compute_sync_committee_period(spec.compute_epoch_at_slot(hs.slot + 1))
        committee = hs.current_sync_committee if same_period else hs.next_sync_committee
        sc = min(spec.compute_subnets_for_sync_committee(hs, members[0]))
        cbits = spec.SyncCommitteeContribution().aggregation_bits
        csigs = []
        for m in pool["sync"]:
            if m.slot != msg_slot or bytes(m.beacon_block_root) != bytes(v["root"]):
                continue
            key = bytes(hs.validators[m.validator_index].pubkey)
            places = [p - sc * sub_size for p, k in enumerate(committee.pubkeys)
                      if bytes(k) == key and p // sub_size == sc]
            if not places or any(cbits[p] for p in places):
                continue
            for p in places:
                cbits[p] = True
                csigs.append(m.signature)
        contribution = spec.SyncCommitteeContribution(slot=msg_slot, beacon_block_root=v["root"],
                                                      subcommittee_index=sc, aggregation_bits=cbits,
                                                      signature=bls.Aggregate(csigs))
        contrib_op = by_name["produceSyncCommitteeContribution"]
        contrib_body = b'{"data":' + to_json(contribution).encode() + b"}"

        def contrib_request(slot, index, root):
            query = b"slot=%d&subcommittee_index=%d&beacon_block_root=0x" % (slot, index) + bytes(root).hex().encode()
            return api_route.request(contrib_op["method"], api_route.fill(contrib_op), query)
        for http in (b"HTTP/1.1", b"HTTP/1.0"):
            add(f"contribution_{http.decode()[5:]}", contrib_request(msg_slot, sc, v["root"]), version=http,
                want=lambda c, k: streamed(None, contrib_body, close=c, keep_alive=k))
        add("contribution_other_root", contrib_request(msg_slot, sc, b"\x07" * 32),
            want=lambda c, k: error(404, close=c, keep_alive=k))
        add("contribution_other_slot", contrib_request(msg_slot + 1, sc, v["root"]),
            want=lambda c, k: error(404, close=c, keep_alive=k))
        add("contribution_not_validated", contrib_request(msg_slot, sc, v["root"]), syncing=2,
            want=lambda c, k: error(503, close=c, keep_alive=k))
        add("contribution_subcommittee_past", contrib_request(msg_slot, int(spec.SYNC_COMMITTEE_SUBNET_COUNT), v["root"]),
            want=lambda c, k: error(400, close=c, keep_alive=k))

        # publishContributionAndProofs: that contribution by an aggregator of its subcommittee (its
        # selection proof passes is_sync_committee_aggregator), first signed with another key, then
        # valid, then again (seen); and of no contribution
        sub_members = list(dict.fromkeys(by_key[bytes(k)] for p, k in enumerate(committee.pubkeys)
                                         if p // sub_size == sc))
        aggregator = next(i for i in sub_members if spec.is_sync_committee_aggregator(
            spec.get_sync_committee_selection_proof(hs, msg_slot, sc, KEYS.privkeys[i])))

        def signed_contribution(key_index):
            cp = spec.get_contribution_and_proof(hs, aggregator, contribution, KEYS.privkeys[aggregator])
            return spec.SignedContributionAndProof(message=cp, signature=spec.get_contribution_and_proof_signature(
                hs, cp, KEYS.privkeys[key_index]))
        bad_c, good_c = signed_contribution(aggregator + 1), signed_contribution(aggregator)
        r3 = submit("contribution_post_other_key", "publishContributionAndProofs", "contribution", [bad_c],
                    json_list([bad_c]), single=False)
        submit("contribution_post", "publishContributionAndProofs", "contribution", [good_c], json_list([good_c]),
               single=False)
        submit("contribution_post_again", "publishContributionAndProofs", "contribution", [good_c],
               json_list([good_c]), single=False)
        submit("contribution_post_no_contribution", "publishContributionAndProofs", "contribution", None,
               b'[{"message":1}]', single=False)
        if r3 != ("bad", [0]) or len(pool["contribution"]) != 1:
            raise RuntimeError("contribution POSTs: the cases need one valid contribution and one rejected")

    # the subscriptions (beacon-api.md): valid ones 200; a committee index not below committees_at_slot,
    # committees_at_slot 0 or past MAX_COMMITTEES_PER_SLOT, a sync committee index not below
    # SYNC_COMMITTEE_SIZE, an item of no subscription: 400
    def subscription(name, op_name, body, status):
        req = api_route.request(by_name[op_name]["method"], api_route.fill(by_name[op_name], None), b"",
                                content_type=b"application/json")
        add(name, req, body=body, want=(lambda c, k: response(200, close=c, keep_alive=k)) if status == 200
            else (lambda c, k: error(400, close=c, keep_alive=k)))

    def committee_sub(index, committee, count, slot, aggregator):
        return (b'{"validator_index":"%d","committee_index":"%d","committees_at_slot":"%d","slot":"%d",'
                b'"is_aggregator":%s}' % (index, committee, count, slot, b"true" if aggregator else b"false"))
    cur_slot = int(spec.get_current_slot(store))
    max_committees = int(spec.MAX_COMMITTEES_PER_SLOT)
    subscription("subscribe_committee", "prepareBeaconCommitteeSubnet",
                 b"[" + committee_sub(1, 0, 1, cur_slot + 1, True) + b"," + committee_sub(2, 1, 2, cur_slot, False) + b"]",
                 200)
    subscription("subscribe_committee_empty", "prepareBeaconCommitteeSubnet", b"[]", 200)
    subscription("subscribe_committee_index_past", "prepareBeaconCommitteeSubnet",
                 b"[" + committee_sub(1, 1, 1, cur_slot, True) + b"]", 400)
    subscription("subscribe_committee_none", "prepareBeaconCommitteeSubnet",
                 b"[" + committee_sub(1, 0, 0, cur_slot, True) + b"]", 400)
    subscription("subscribe_committee_too_many", "prepareBeaconCommitteeSubnet",
                 b"[" + committee_sub(1, 0, max_committees + 1, cur_slot, True) + b"]", 400)
    subscription("subscribe_committee_no_item", "prepareBeaconCommitteeSubnet", b'[{"slot":"1"}]', 400)
    if FORKS.index(fork) >= FORKS.index("altair"):
        epoch_now = cur_slot // int(spec.SLOTS_PER_EPOCH)
        size = int(spec.SYNC_COMMITTEE_SIZE)
        subscription("subscribe_sync", "prepareSyncCommitteeSubnets",
                     b'[{"validator_index":"1","sync_committee_indices":["0","%d"],"until_epoch":"%d"}]'
                     % (size - 1, epoch_now + 2), 200)
        subscription("subscribe_sync_index_past", "prepareSyncCommitteeSubnets",
                     b'[{"validator_index":"1","sync_committee_indices":["%d"],"until_epoch":"%d"}]'
                     % (size, epoch_now + 2), 400)
        subscription("subscribe_sync_no_item", "prepareSyncCommitteeSubnets", b'[{"until_epoch":"1"}]', 400)
    # prepareBeaconProposer: fee recipients of validators known or not (200); an item of no preparation (400)
    subscription("prepare_proposer", "prepareBeaconProposer",
                 b'[{"validator_index":"1","fee_recipient":"0x' + b"42" * 20 + b'"},'
                 b'{"validator_index":"9999999","fee_recipient":"0x' + b"07" * 20 + b'"}]', 200)
    subscription("prepare_proposer_no_item", "prepareBeaconProposer", b'[{"validator_index":"1"}]', 400)
    # with the store's nodes NOT_VALIDATED (syncing bit 1): the aggregate's beacon_block_root, 503
    add("aggregate_not_validated", agg_request(data_root, first_slot, first_index), syncing=2,
        want=lambda c, k: error(503, close=c, keep_alive=k))
    # getLiveness after the POSTs, of every index: the attesters, aggregators and sync committee members they named
    import struct
    live_op = by_name["getLiveness"]
    every = list(range(len(state.validators) + 2))
    live_body = b"[" + b",".join(b'"%d"' % i for i in every) + b"]"
    live_refs = [struct.pack("<QQ", 1, i) + bytes(48) for i in every]
    store_epoch = (v["slot"] + SLOTS_AHEAD) // int(spec.SLOTS_PER_EPOCH)
    for e in (store_epoch - 1, store_epoch, store_epoch + 1):
        req = api_route.request(live_op["method"], api_route.fill(live_op, {"epoch": b"%d" % e}), b"",
                                content_type=b"application/json")
        add(f"liveness_pools_{e}", req, body=live_body,
            want=lambda c, k, e=e: liveness_answer(v, e, live_refs, dict(close=c, keep_alive=k), False, seen))


def api_requests(spec, fork, v, kind="main"):
    """(name, request bytes, response, closes, offline, syncing) of each request of a node at its
    anchor; kind "late", those of getEpochCommittees at its lowest epochs; kind "genesis", those of
    getProposerDuties of an anchor at slot 0."""
    import api_route
    ops = api_route.operations(pathlib.Path(os.environ["BEACON_APIS"]))
    by_name = {op["name"]: op for op in ops}
    out = []

    def add(name, req, offline=False, version=b"HTTP/1.1", connection=b"", extra=b"", body=None, syncing=False, want=None,
            stream=0):
        if body is not None:
            req = dict(req, body=body)
            extra += b"Content-Length: %d\r\n" % len(body)
        raw = http(req, version, connection, extra) + (body or b"")
        close = connection.lower() == b"close" or (version == b"HTTP/1.0" and connection.lower() != b"keep-alive")
        keep_alive = version == b"HTTP/1.0" and not close
        status, r = api_route.route(ops, req, 1 << 24)
        stream = int(stream)
        if status != api_route.OK:
            want = error(r.http, close=close, keep_alive=keep_alive, allow=r.allow)
        else:
            route = Route(r)
            opname = ops[route.op - 1]["name"]
            if want is not None:
                want = want(close, keep_alive)
            elif opname == "eventstream":  # the head; the stream stays open
                want, stream = stream_head(version, connection), 1
            elif opname in POOL_GETS:  # an empty pool
                pool_version = fork if opname in ("getPoolAttesterSlashingsV2", "getPoolAttestationsV2") else None
                body = b'{"data":[]}' if pool_version is None else b'{"version":"%s","data":[]}' % fork.encode()
                want = streamed(pool_version, body, close=close, keep_alive=keep_alive)
            elif opname in POOL_POSTS and not req["body"]:  # a body of no operation
                want = error(400, close=close, keep_alive=keep_alive)
            elif opname in ("getAggregatedAttestationV2", "produceSyncCommitteeContribution"):  # an empty pool: none
                want = error(404, close=close, keep_alive=keep_alive)
            elif opname in ANSWERED:
                want = answer(v, opname, route, offline, close, keep_alive, syncing)
            elif opname in ("getBlockRewards", "getSyncCommitteeRewards"):  # the anchor's block has no bytes: 404
                assert req["path"].endswith(b"/head")
                want = error(404, close=close, keep_alive=keep_alive)
            elif opname == "getAttestationsRewards":  # the state of the last slot of epoch + 1: none the node holds, 404
                last = (int(route.epoch) + 2) * int(spec.SLOTS_PER_EPOCH) - 1
                assert last > v["slot"] + SLOTS_AHEAD or last not in v["states"]
                want = error(404, close=close, keep_alive=keep_alive)
            elif opname == "produceBlockV3":  # 503 while syncing; else the path's slot is at or below the head's: 400
                assert int(route.slot) <= v["slot"]
                want = error(503 if int(syncing) & 1 else 400, close=close, keep_alive=keep_alive)
            elif opname == "publishBlockV2":  # 503 while syncing; else a body of no block: 400
                assert not req["body"]
                want = error(503 if int(syncing) & 1 else 400, close=close, keep_alive=keep_alive)
            else:
                want = error(501, close=close, keep_alive=keep_alive)
        out.append((name, raw, want, close, offline, syncing, stream))

    committees = by_name["getEpochCommittees"]
    duties = by_name["getProposerDuties"]
    epoch = v["slot"] // int(spec.SLOTS_PER_EPOCH)
    current = (v["slot"] + SLOTS_AHEAD) // int(spec.SLOTS_PER_EPOCH)

    def liveness_requests():
        """getLiveness of the epochs around the store's, with validators the anchor marks live (anchor)."""
        live_op = by_name["getLiveness"]
        n = len(v["states"][v["slot"]].validators)

        def live(e, body, **headers):
            return api_route.request(live_op["method"], api_route.fill(live_op, {"epoch": b"%d" % e}), b"", body=body,
                                     content_type=b"application/json", **headers)
        marked = b'["2","5","6","0","%d","%d","2"]' % (n - 1, n + 4)
        for e in range(max(current - 2, 0), current + 3):
            add(f"liveness_{e}", live(e, marked), body=marked)
        for name, body in (("liveness_none", b""), ("liveness_empty", b"[]"),
                           ("liveness_pubkey", b'["0x' + bytes(48).hex().encode() + b'"]')):
            add(name, live(current, body), body=body if body else None)
        add("liveness_http10", live(current, marked), body=marked, version=b"HTTP/1.0")
        add("liveness_syncing", live(current, marked), body=marked, syncing=True)
    if kind == "genesis":
        for e in range(0, 3):
            add(f"duties_{e}", api_route.base(duties, path_values={"epoch": b"%d" % e}))
        liveness_requests()
        return out
    if kind == "late":  # the lowest epoch whose seed's RANDAO mix the state holds, and the one below
        lowest = epoch + 1 - int(spec.EPOCHS_PER_HISTORICAL_VECTOR) + int(spec.MIN_SEED_LOOKAHEAD) + 1
        for e in (epoch, lowest, lowest - 1):
            add(f"committees_epoch_{e}", api_route.base(committees, [("epoch", b"%d" % e)]))
        add("committees_low_slot", api_route.base(committees, [("epoch", b"%d" % lowest),
                                                              ("slot", b"%d" % (lowest * int(spec.SLOTS_PER_EPOCH) + 3))]))
        pool_requests(spec, fork, v, by_name, add)
        return out
    for op in ops:
        add(op["name"], api_route.base(op))
    for name in ANSWERED:
        add(f"{name}_offline", api_route.base(by_name[name]), offline=True)
    health = by_name["getHealth"]
    add("health_syncing_status", api_route.base(health, [("syncing_status", b"500")]))
    add("health_syncing_status_offline", api_route.base(health, [("syncing_status", b"299")]), offline=True)
    header = by_name["getBlockHeader"]
    add("header_head", api_route.base(header, path_values={"block_id": b"head"}))
    add("header_root", api_route.base(header, path_values={"block_id": qhex(v["root"])[1:-1]}))
    add("header_root_upper", api_route.base(header, path_values={"block_id": b"0x" + v["root"].hex().upper().encode()}))
    add("header_other_root", api_route.base(header, path_values={"block_id": b"0x" + bytes(32).hex().encode()}))
    for block_id in (b"genesis", b"finalized", b"16"):
        add(f"header_{block_id.decode()}", api_route.base(header, path_values={"block_id": block_id}))
    finality = by_name["getStateFinalityCheckpoints"]
    for state_id in (b"head", b"genesis", b"finalized", b"justified", b"0", b"0x" + bytes(32).hex().encode()):
        add(f"finality_{state_id.decode()[:10]}", api_route.base(finality, path_values={"state_id": state_id}))
    version = by_name["getNodeVersion"]
    add("close", api_route.base(version), connection=b"close")
    add("close_upper", api_route.base(version), connection=b"Close")
    add("keep_alive_11", api_route.base(version), connection=b"keep-alive")
    add("http10", api_route.base(version), version=b"HTTP/1.0")
    add("http10_keep_alive", api_route.base(version), version=b"HTTP/1.0", connection=b"keep-alive")
    add("http10_keep_alive_identity", api_route.base(by_name["getNetworkIdentity"]), version=b"HTTP/1.0", connection=b"keep-alive")
    add("http10_header_404", api_route.base(header, path_values={"block_id": b"genesis"}), version=b"HTTP/1.0")
    add("spec_http10", api_route.base(by_name["getSpec"]), version=b"HTTP/1.0")
    add("spec_close", api_route.base(by_name["getSpec"]), connection=b"close")
    add("fork_schedule_http10", api_route.base(by_name["getForkSchedule"]), version=b"HTTP/1.0")
    add("unknown_path", api_route.request(1, b"/eth/v1/node/bogus"))
    add("post_on_get", api_route.request(2, b"/eth/v1/node/version"))
    add("get_on_post", api_route.request(1, b"/eth/v1/validator/prepare_beacon_proposer"))
    add("delete_on_both", api_route.request(3, b"/eth/v1/beacon/states/head/validators"))
    add("delete_on_get_405_close", api_route.request(3, b"/eth/v1/node/health"), connection=b"close")
    block = by_name["getBlockV2"]
    add("accept_406", api_route.base(block, accept=b"text/html"))
    add("accept_ssz", api_route.base(block, accept=b"application/octet-stream"))
    add("bad_block_id_400", api_route.base(header, path_values={"block_id": b"0x12"}))
    state = by_name["getStateV2"]
    octet = b"application/octet-stream"
    add("state_head_json", api_route.base(state, path_values={"state_id": b"head"}))
    add("state_head_ssz", api_route.base(state, path_values={"state_id": b"head"}, accept=octet))
    add("state_head_json_http10", api_route.base(state, path_values={"state_id": b"head"}), version=b"HTTP/1.0")
    add("state_head_ssz_http10", api_route.base(state, path_values={"state_id": b"head"}, accept=octet), version=b"HTTP/1.0")
    add("state_head_ssz_http10_keep_alive", api_route.base(state, path_values={"state_id": b"head"}, accept=octet),
        version=b"HTTP/1.0", connection=b"keep-alive")
    add("state_head_json_close", api_route.base(state, path_values={"state_id": b"head"}), connection=b"close")
    for state_id in (b"genesis", b"finalized", b"0", qhex(v["root"])[1:-1]):
        add(f"state_{state_id.decode()[:10]}", api_route.base(state, path_values={"state_id": state_id}))
    for block_id in (b"head", qhex(v["root"])[1:-1], b"finalized"):
        add(f"block_{block_id.decode()[:10]}", api_route.base(block, path_values={"block_id": block_id}))
        add(f"block_{block_id.decode()[:10]}_ssz", api_route.base(block, path_values={"block_id": block_id}, accept=octet))
    root_id, other_root = qhex(v["root"])[1:-1], b"0x" + bytes(range(32)).hex().encode()
    for op in ("getBlockRoot", "getBlockHeader", "getBlockV2", "getBlockAttestationsV2", "getBlindedBlock"):
        for block_id in (b"head", b"finalized", b"genesis", b"%d" % (v["slot"] - 1), b"%d" % v["slot"], b"%d" % (v["slot"] + 1),
                         root_id, other_root):
            add(f"lookup_{op}_{block_id.decode()[:12]}", api_route.base(by_name[op], path_values={"block_id": block_id}))
    headers, parent = by_name["getBlockHeaders"], qhex(v["header"].parent_root)[1:-1]
    for key, query in (("slot", [("slot", b"%d" % v["slot"])]), ("slot_below", [("slot", b"%d" % (v["slot"] - 1))]),
                       ("slot_above", [("slot", b"%d" % (v["slot"] + 1))]), ("slot_0", [("slot", b"0")]),
                       ("parent", [("parent_root", parent)]), ("parent_anchor", [("parent_root", root_id)]),
                       ("parent_other", [("parent_root", other_root)]),
                       ("slot_parent", [("slot", b"%d" % v["slot"]), ("parent_root", parent)]),
                       ("slot_parent_other", [("slot", b"%d" % v["slot"]), ("parent_root", other_root)]),
                       ("slot_above_parent", [("slot", b"%d" % (v["slot"] + 1)), ("parent_root", parent)])):
        add(f"headers_{key}", api_route.base(headers, query))
    add("headers_http10", api_route.base(headers), version=b"HTTP/1.0")
    for op in ("getBlobSidecars", "getDebugDataColumnSidecars"):
        for block_id in (b"head", root_id, other_root, b"%d" % v["slot"]):
            add(f"sidecars_{op}_{block_id.decode()[:12]}", api_route.base(by_name[op], path_values={"block_id": block_id}))
        add(f"sidecars_{op}_ssz", api_route.base(by_name[op], path_values={"block_id": b"head"}, accept=octet))
        add(f"sidecars_{op}_indices", api_route.base(by_name[op], [("indices", b"0,3")], path_values={"block_id": b"head"}))
        add(f"sidecars_{op}_http10", api_route.base(by_name[op], path_values={"block_id": b"head"}), version=b"HTTP/1.0")
    blobs = by_name["getBlobs"]
    for block_id in (b"head", root_id, other_root, b"%d" % v["slot"]):
        add(f"blobs_{block_id.decode()[:12]}", api_route.base(blobs, path_values={"block_id": block_id}))
    add("blobs_ssz", api_route.base(blobs, path_values={"block_id": b"head"}, accept=octet))
    add("blobs_hashes", api_route.base(blobs, [("versioned_hashes", b"0x01" + b"ab" * 31 + b",0x01" + b"cd" * 31)],
                                       path_values={"block_id": b"head"}))
    add("blobs_http10", api_route.base(blobs, path_values={"block_id": b"head"}), version=b"HTTP/1.0")
    peers = by_name["getPeers"]
    for key, query in (("connected", [("state", b"connected")]), ("states", [("state", b"disconnected,connecting")]),
                       ("inbound", [("direction", b"inbound")]),
                       ("both", [("state", b"connected"), ("direction", b"inbound,outbound")])):
        add(f"peers_{key}", api_route.base(peers, query))
    add("peer_identity", api_route.base(by_name["getPeer"], path_values={"peer_id": IDENTITY[0]}))
    add("headers_close", api_route.base(headers), connection=b"close")
    for op in ("getStateRoot", "getStateFork", "getStateFinalityCheckpoints"):
        ids = [b"head", b"finalized", b"justified", b"genesis", other_root, qhex(v["state_roots"][0])[1:-1],
               qhex(v["state_roots"][1])[1:-1]]
        ids += [b"%d" % s for s in range(v["slot"], v["slot"] + SLOTS_AHEAD + 2)]
        for state_id in ids:
            add(f"lookup_{op}_{state_id.decode()[:12]}", api_route.base(by_name[op], path_values={"state_id": state_id}))
    for state_id in (b"finalized", b"%d" % (v["slot"] + 2)):
        add(f"lookup_getStateV2_{state_id.decode()}", api_route.base(state, path_values={"state_id": state_id}))
    # the state reads: of the state ids above; randao and sync committees of their epochs
    spec_v = v["spec"]
    period = int(getattr(spec_v, "EPOCHS_PER_SYNC_COMMITTEE_PERIOD", 1))  # phase0 has none: its answers are 400
    for op in STATE_READS:
        for state_id in (b"head", b"finalized", b"genesis", other_root, qhex(v["state_roots"][1])[1:-1],
                         b"%d" % (v["slot"] + 1)):
            add(f"read_{op}_{state_id.decode()[:12]}", api_route.base(by_name[op], path_values={"state_id": state_id}))
    add("read_getProposerLookahead_ssz", api_route.base(by_name["getProposerLookahead"], path_values={"state_id": b"head"},
                                                        accept=b"application/octet-stream"))
    for op in PENDING:  # the pending lists: of the state ids above, as SSZ, and over HTTP/1.0
        for state_id in (b"head", b"finalized", b"genesis", other_root, qhex(v["state_roots"][1])[1:-1],
                         b"%d" % (v["slot"] + 1)):
            add(f"pending_{op}_{state_id.decode()[:12]}", api_route.base(by_name[op], path_values={"state_id": state_id}))
        add(f"pending_{op}_ssz", api_route.base(by_name[op], path_values={"state_id": b"head"},
                                                accept=b"application/octet-stream"))
        add(f"pending_{op}_http10", api_route.base(by_name[op], path_values={"state_id": b"head"}), version=b"HTTP/1.0")
    for e in (0, epoch - 1, epoch, epoch + 1, epoch + int(spec_v.EPOCHS_PER_HISTORICAL_VECTOR)):
        add(f"read_randao_epoch_{e}", api_route.base(by_name["getStateRandao"], [("epoch", b"%d" % e)],
                                                     path_values={"state_id": b"head"}))
    for e in (0, epoch, (epoch // period + 1) * period, (epoch // period + 2) * period):
        add(f"read_sync_epoch_{e}", api_route.base(by_name["getEpochSyncCommittees"], [("epoch", b"%d" % e)],
                                                   path_values={"state_id": b"head"}))
    validators = by_name["getStateValidators"]
    add("ids_65_414", api_route.base(validators, [("id", b",".join(str(i).encode() for i in range(65)))]))
    events = by_name["eventstream"]
    for name, version, connection, topics in (("events", b"HTTP/1.1", b"", b"head,block,finalized_checkpoint"),
                                              ("events_close", b"HTTP/1.1", b"close", b"head,block,finalized_checkpoint"),
                                              ("events_http10", b"HTTP/1.0", b"", b"block"),
                                              ("events_http10_keep_alive", b"HTTP/1.0", b"keep-alive", b"block"),
                                              ("events_no_name", b"HTTP/1.1", b"", b"head,,block")):
        add(name, api_route.request(events["method"], api_route.fill(events, None), b"topics=" + topics),
            version=version, connection=connection)
    for e in range(epoch - 1, current + 3):
        add(f"duties_{e}", api_route.base(duties, path_values={"epoch": b"%d" % e}))
    add("duties_syncing", api_route.base(duties, path_values={"epoch": b"%d" % current}), syncing=True)
    att = by_name["produceAttestationData"]

    def att_data(slot, index=1, **headers):
        return api_route.request(att["method"], api_route.fill(att), b"slot=%d&committee_index=%d" % (slot, index), **headers)
    for slot in range(v["slot"] - 1, v["slot"] + SLOTS_AHEAD + 2):  # below the anchor, each slot to the store's, one past it
        add(f"att_data_{slot}", att_data(slot))
    add("att_data_index_max", att_data(v["slot"] + 1, 2**64 - 1))
    add("att_data_ssz", att_data(v["slot"] + 2, 0, accept=b"application/octet-stream"))
    add("att_data_http10", att_data(v["slot"] + 2), version=b"HTTP/1.0")
    add("att_data_syncing", att_data(v["slot"]), syncing=True)
    attester = by_name["getAttesterDuties"]
    n = len(v["states"][v["slot"]].validators)

    def att_duties(e, body, **headers):
        return api_route.request(attester["method"], api_route.fill(attester, {"epoch": b"%d" % e}), b"", body=body,
                                 content_type=b"application/json", **headers)
    some = b'["3","%d","%d","%d","3","0"]' % (n - 1, n - 8, n + 5)
    for e in range(epoch - 1, current + 3):
        add(f"att_duties_{e}", att_duties(e, some), body=some)
    for name, body in (("att_duties_none", b""), ("att_duties_empty", b"[]"),
                       ("att_duties_pubkey", b'["0x' + bytes(48).hex().encode() + b'"]')):
        add(name, att_duties(current, body), body=body if body else None)
    add("att_duties_http10", att_duties(current, some), body=some, version=b"HTTP/1.0")
    sync_duties = by_name["getSyncCommitteeDuties"]

    def sd(e, body, **headers):
        return api_route.request(sync_duties["method"], api_route.fill(sync_duties, {"epoch": b"%d" % e}), b"", body=body,
                                 content_type=b"application/json", **headers)
    every = b"[" + b",".join(b'"%d"' % i for i in range(n + 2)) + b"]"
    epsp = int(spec.EPOCHS_PER_SYNC_COMMITTEE_PERIOD)
    for e in sorted({0, epoch - 1, epoch, current, current + 1, current + epsp, epoch + epsp, current + 2 * epsp}):
        if e >= 0:
            add(f"sync_duties_{e}", sd(e, every), body=every)
    add("sync_duties_some", sd(current, some), body=some)
    for name, body in (("sync_duties_none", b""), ("sync_duties_empty", b"[]"),
                       ("sync_duties_pubkey", b'["0x' + bytes(48).hex().encode() + b'"]')):
        add(name, sd(current, body), body=body if body else None)
    add("sync_duties_http10", sd(current, some), body=some, version=b"HTTP/1.0")
    add("sync_duties_syncing", sd(current, some), body=some, syncing=True)
    add("att_duties_syncing", att_duties(current, some), body=some, syncing=True)
    liveness_requests()
    first = epoch * int(spec.SLOTS_PER_EPOCH)
    for e in range(epoch - 1, epoch + 3):
        add(f"committees_epoch_{e}", api_route.base(committees, [("epoch", b"%d" % e)]))
    for k, items in enumerate([[("slot", b"%d" % (first + 1))], [("slot", b"%d" % (first - 1))], [("index", b"0")],
                               [("index", b"1")], [("slot", b"%d" % (first + 2)), ("index", b"0")],
                               [("epoch", b"%d" % (epoch + 1)), ("slot", b"%d" % (first + int(spec.SLOTS_PER_EPOCH))),
                                ("index", b"0")]]):
        add(f"committees_{k}", api_route.base(committees, items))
    add("committees_http10", api_route.base(committees), version=b"HTTP/1.0")
    for state_id in (b"finalized", b"%d" % (v["slot"] + 2), qhex(v["state_roots"][0])[1:-1]):
        add(f"committees_{state_id.decode()[:12]}", api_route.base(committees, path_values={"state_id": state_id}))

    def pk(i):
        return b"0x" + (bytes([i + 1]) * 48).hex().encode()

    add("validators_ids", api_route.base(validators, [("id", b"0,3,15,99,3," + pk(9) + b"," + pk(200))]))
    for k, s in enumerate(api_route.STATUSES + tuple(api_route.GROUPS)):
        add(f"validators_status_{s}", api_route.base(validators, [("status", s.encode())]))
    add("validators_ids_status", api_route.base(validators, [("id", b"10,11,12," + pk(13)), ("status", b"active,exited_slashed")]))
    for state_id in (b"finalized", b"%d" % (v["slot"] + 2), qhex(v["state_roots"][1])[1:-1], other_root):
        add(f"validators_{state_id.decode()[:12]}", api_route.base(validators, [("status", b"pending")],
                                                                    path_values={"state_id": state_id}))
    add("validators_http10", api_route.base(validators), version=b"HTTP/1.0")
    add("validators_close", api_route.base(validators), connection=b"close")
    post = by_name["postStateValidators"]
    for k, body in enumerate([b"{}", b'{"ids":["1","' + pk(12) + b'"],"statuses":["exited"]}', b'{"statuses":["withdrawal"]}',
                              b'{"ids":["' + pk(15) + b'","' + pk(15) + b'"]}', b'{"ids":["7"]}x']):
        add(f"post_validators_{k}", api_route.base(post), body=body)
    add("post_validators_root", api_route.base(post, path_values={"state_id": qhex(v["state_roots"][0])[1:-1]}),
        body=b'{"ids":["2","9"]}')
    one = by_name["getStateValidator"]
    for k, vid in enumerate([b"3", pk(14), b"99", pk(250), b"16"]):
        add(f"validator_{k}", api_route.base(one, path_values={"validator_id": vid}))
    add("validator_finalized", api_route.base(one, path_values={"validator_id": b"11", "state_id": b"finalized"}))
    add("validator_root", api_route.base(one, path_values={"validator_id": pk(10), "state_id": qhex(v["state_roots"][1])[1:-1]}))
    balances = by_name["getStateValidatorBalances"]
    add("balances_ids", api_route.base(balances, [("id", b"1,2,15,77," + pk(4))]))
    post_balances = by_name["postStateValidatorBalances"]
    for k, body in enumerate([b'["0","' + pk(5) + b'"]', b"[]", b"null"]):
        add(f"post_balances_{k}", api_route.base(post_balances), body=body)
    identities = by_name["postStateValidatorIdentities"]
    for k, body in enumerate([None, b'["8","9","' + pk(1) + b'"]']):
        add(f"identities_{k}", api_route.base(identities), body=body)
        add(f"identities_{k}_ssz", api_route.base(identities, accept=octet), body=body)
    publish = by_name["publishBlockV2"]
    add("content_type_415", api_route.base(publish, content_type=b"text/plain"), extra=b"Content-Length: 0\r\n")
    add("version_missing_400", dict(api_route.base(publish), consensus_version=b""))
    return out


def http_faults():
    """(name, request bytes, status) of requests lantern_http_request finds faulty."""
    host = b"Host: lantern\r\n"
    return [
        ("head_431", b"GET /eth/v1/node/version HTTP/1.1\r\n" + host + b"X: " + b"a" * 16400 + b"\r\n\r\n", 431),
        ("body_413", b"POST /eth/v1/beacon/pool/voluntary_exits HTTP/1.1\r\n" + host + b"Content-Length: 1048577\r\n\r\n", 413),
        ("line_400", b"GET  /eth/v1/node/version HTTP/1.1\r\n" + host + b"\r\n", 400),
        ("no_host_400", b"GET /eth/v1/node/version HTTP/1.1\r\n\r\n", 400),
        ("version_505", b"GET /eth/v1/node/version HTTP/2.0\r\n" + host + b"\r\n", 505),
        ("coding_501", b"POST /eth/v1/beacon/pool/voluntary_exits HTTP/1.1\r\n" + host + b"Transfer-Encoding: gzip\r\n\r\n", 501),
    ]


def api_cases(fork, preset, epoch=ANCHOR_EPOCH):
    """The api case of an anchor at the epoch; at epoch 0, the requests of getProposerDuties alone;
    at another epoch, those of getEpochCommittees at its lowest epochs alone."""
    spec = module(fork, preset)
    # the late case's pool requests need committee members in the slots after the anchor's: about
    # 4 a slot after the 8 first validators, so that a committee has two attestations of one data
    extra = 4 * int(spec.SLOTS_PER_EPOCH) - 8 if epoch not in (ANCHOR_EPOCH, 0) else 0
    state, block = run(spec, schedule(fork), lambda: anchor(spec, fork, statuses=True, epoch=epoch, extra=extra))
    v = run(spec, schedule(fork), lambda: api_values(spec, fork, state, block))
    v["config_bodies"] = config_bodies(fork, preset)
    kind = "main" if epoch == ANCHOR_EPOCH else "genesis" if epoch == 0 else "late"
    slot_ms0 = int(spec.config.SLOT_DURATION_MS) if hasattr(spec.config, "SLOT_DURATION_MS") else int(spec.config.SECONDS_PER_SLOT) * 1000
    v["block"] = block
    v["fork"] = fork
    v["time_ms"] = v["genesis_time"] * 1000 + (v["slot"] + SLOTS_AHEAD) * slot_ms0
    reqs = run(spec, schedule(fork), lambda: api_requests(spec, fork, v, kind))
    if fork in ("altair",):  # no execution engine before bellatrix: el_offline stays false
        reqs = [r for r in reqs if not r[4]]
    names, raws, wants, closes, offline, syncing, streams = [], [], [], [], [], [], []
    for name, raw, want, close, off, sync, stream in sorted(reqs, key=lambda r: r[4]):
        names.append(name.encode())
        raws.append(raw)
        wants.append(want[0] if isinstance(want, list) else want)  # a box: an open stream's bytes at the case's end
        closes.append(1 if close and not stream else 0)
        offline.append(off)
        syncing.append(int(sync))  # bit 0 NODE_FLAG_SYNCING, bit 1 the store's nodes NOT_VALIDATED
        streams.append(stream)
    for name, raw, status in http_faults() if epoch == ANCHOR_EPOCH else []:
        names.append(name.encode())
        raws.append(raw)
        wants.append(error(status, close=True))
        closes.append(1)
        offline.append(offline[-1] if offline else False)
        syncing.append(0)
        streams.append(0)
    first_offline = offline.index(True) if True in offline else len(names)
    slot_ms = int(spec.config.SLOT_DURATION_MS) if hasattr(spec.config, "SLOT_DURATION_MS") else int(spec.config.SECONDS_PER_SLOT) * 1000
    return {
        "anchor_state": bytes(state.encode_bytes()),
        "anchor_block": bytes(block.encode_bytes()),
        "identity": identity_bytes(),
        "time_ms": (v["genesis_time"] + 0) * 1000 + (v["slot"] + SLOTS_AHEAD) * slot_ms,
        "names": names,
        "requests": raws,
        "responses": wants,
        "closes": bytes(closes),
        "syncing": bytes(syncing),
        "streams": bytes(streams),
        "offline": first_offline,
    }
