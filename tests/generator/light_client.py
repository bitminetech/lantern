"""Cases of lantern's light client functions (docs/reference/light-client.md).

The expected values come from the spec modules of consensus-specs v1.7.0-beta.4 (aa16bb4):
block_to_light_client_header of each fork, run with the forks up to the block's at epoch 0, and upgrade_lc_header_to_capella,
upgrade_lc_header_to_deneb and upgrade_lc_header_to_electra.

header_cases(fork, preset, blocks) yields (name, parts) for the blocks of each fork, a map of
fork to a list of (name, SignedBeaconBlock SSZ bytes).
"""

import node  # schedule and run_strict: a spec module under a fork schedule

FORKS = ("phase0", "altair", "bellatrix", "capella", "deneb", "electra", "fulu")
PER_FORK = 6  # the blocks of each fork the upgrade cases take


def spec_of(fork, preset):
    return __import__(f"eth_consensus_specs.{fork}.{preset}", fromlist=["*"])


def block_fork(fork, preset, block):
    """The fork of a block of a case of fork: the first from it on whose SignedBeaconBlock its bytes are
    (a multi-fork case holds the blocks of later forks; electra and fulu share the type)."""
    for f in FORKS[FORKS.index(fork):]:
        spec = spec_of(f, preset)
        try:
            if spec.SignedBeaconBlock.decode_bytes(block).encode_bytes() == block:
                return f
        except Exception:  # not of the type
            continue
    raise ValueError(f"a block of a {fork} case is of no fork from {fork} on")


def header_of(fork, preset, block):
    """block_to_light_client_header of the block's fork, altair's before altair: (header fork, header)."""
    spec = spec_of(fork, preset)
    signed = spec.SignedBeaconBlock.decode_bytes(block)
    lc = spec_of("altair", preset) if fork == "phase0" else spec
    hfork = "altair" if fork == "phase0" else fork
    # the forks up to the block's at epoch 0, as a chain whose blocks are of their slot's fork has them
    return hfork, node.run_strict(lc, node.schedule(hfork), lambda: lc.block_to_light_client_header(signed))


def upgrade(preset, frm, header, to):
    """The header of fork frm as one of fork to, by the spec's upgrade_lc_header_to_* in turn."""
    order = FORKS.index
    if order(frm) < order("capella") <= order(to):
        header = spec_of("capella", preset).upgrade_lc_header_to_capella(header)
    if order(frm) < order("deneb") <= order(to):
        header = spec_of("deneb", preset).upgrade_lc_header_to_deneb(header)
    if order(frm) < order("electra") <= order(to):
        header = spec_of("electra", preset).upgrade_lc_header_to_electra(header)
    if order(frm) < order("fulu") <= order(to):  # fulu keeps electra's light client types
        header = spec_of("fulu", preset).LightClientHeader.decode_bytes(header.encode_bytes())
    return header


def header_cases(fork, preset, blocks):
    """lantern_block_to_light_client_header of each block of fork; lantern_upgrade_lc_header of the
    headers of the first PER_FORK blocks of each earlier fork to fork."""
    for name, block in blocks.get(fork, []):
        _, header = header_of(fork, preset, block)
        yield f"header/{name}", {"block": block, "header": header.encode_bytes()}
    if fork == "phase0":
        return
    for frm in FORKS[: FORKS.index(fork) + 1]:
        for name, block in blocks.get(frm, [])[:PER_FORK]:
            hfork, header = header_of(frm, preset, block)
            out = upgrade(preset, hfork, header, fork)
            yield f"upgrade/{frm}/{name}", {"header": header.encode_bytes(), "from": FORKS.index(frm),
                                            "out": out.encode_bytes()}
