#!/usr/bin/env python3
"""Fetch, check and convert the consensus spec tests into binary case files.

Usage: python tests/generator/generate.py OUT_DIR [RUNNER ...]

Run it through tests/generator/run.sh, which uses the image from
platform/linux/Dockerfile and the packages in requirements.txt. The file
format is in README.md next to this script. With RUNNER names, only those
spec test runners are converted.
"""
import hashlib
import json
import os
import pathlib
import re
import struct
import sys
import tarfile
import urllib.request

import snappy
from ruamel.yaml import YAML
from ssz.container import Container

import descriptor  # asm-ssz tests/generator/descriptor.py, at the pin in platform/deps.sh

RELEASE = "https://github.com/ethereum/consensus-specs/releases/download/v1.7.0-beta.4/"
ARCHIVES = {  # SHA-256 of each archive of consensus-specs v1.7.0-beta.4 (aa16bb4)
    "mainnet": "67762986572372a08d3b182535aa760433c86e174e14e0bbd756f350dd19398c",
    "minimal": "26d09aea70c62ed235a120a95082d544ab1c2e6fe36bd35ea1bd5da62f3b7b68",
}
# The fork choice compliance cases of the release, made by the spec's
# tests/generators/compliance_runners: the minimal preset only.
COMPTESTS = ("comptests.tar.gz", "minimal", "ccb3149d29e4179e852499f1a3d121424dbac22745375908cd9059350aece746")
FORK = "fulu"
# Spec test runners outside lantern's scope (README of the repo: Fulu only, no
# light client server, no fork upgrade, no genesis from eth1, no fast confirmation).
SKIP = {"light_client", "fork", "transition", "genesis", "fast_confirmation"}
CASE = re.compile(r"tests/(mainnet|minimal)/(\w+)/(\w+)/(\w+)/(\w+)/([^/]+)/([^/]+)$")

MAGIC = b"LANTVEC1"
T_INT, T_BYTES, T_STRING, T_BOOL, T_LIST, T_MAP, T_NULL, T_UINT256, T_NEG_INT = 1, 2, 3, 4, 5, 6, 7, 8, 9


def fail(text):
    sys.exit("generate.py: " + text)


def u64(n):
    return struct.pack("<Q", n)


def blob(data):
    return u64(len(data)) + data


def tlv(value):
    """Encode a YAML value, or SSZ bytes, as a tagged value (README.md)."""
    if value is None:
        return bytes([T_NULL])
    if isinstance(value, bool):
        return bytes([T_BOOL, 1 if value else 0])
    if isinstance(value, int):
        if 0 <= value < 1 << 64:
            return bytes([T_INT]) + u64(value)
        if 0 <= value < 1 << 256:
            return bytes([T_UINT256]) + value.to_bytes(32, "little")
        if -(1 << 63) <= value < 0:
            return bytes([T_NEG_INT]) + struct.pack("<q", value)
        fail(f"integer {value} does not fit in 256 bits")
    if isinstance(value, (bytes, bytearray)):
        return bytes([T_BYTES]) + blob(bytes(value))
    if isinstance(value, str):
        if re.fullmatch(r"0x([0-9a-fA-F]{2})*", value):
            return bytes([T_BYTES]) + blob(bytes.fromhex(value[2:]))
        return bytes([T_STRING]) + blob(value.encode())
    if isinstance(value, (list, tuple)):
        return bytes([T_LIST]) + u64(len(value)) + b"".join(tlv(v) for v in value)
    if isinstance(value, dict):
        out = bytearray([T_MAP]) + u64(len(value))
        for key, v in value.items():
            out += blob(str(key).encode()) + tlv(v)
        return bytes(out)
    fail(f"cannot encode {type(value).__name__}")


def fetch(url, sha256, path):
    """Download url to path once, then check its SHA-256 pin."""
    if not path.exists():
        request = urllib.request.Request(url, headers={"User-Agent": "lantern-vector-generator"})
        with urllib.request.urlopen(request) as response, open(path, "wb") as f:
            while chunk := response.read(1 << 20):
                f.write(chunk)
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    if h.hexdigest() != sha256:
        fail(f"{url} has SHA-256 {h.hexdigest()}, expected {sha256}")


def read_cases(archive, runners):
    """Yield (runner, handler, suite, case, {file name: bytes}) for the Fulu cases of one archive."""
    current, files = None, {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            m = CASE.search(member.name) if member.isfile() else None
            if not m or m.group(3) in SKIP:
                continue
            # Fulu cases, and the shuffling cases, which only phase0 holds.
            if m.group(2) != FORK and (m.group(2), m.group(3)) != ("phase0", "shuffling"):
                continue
            if runners and m.group(3) not in runners:
                continue
            key = m.groups()[2:6]
            if key != current:
                if current:
                    yield (*current, files)
                current, files = key, {}
            files[m.group(7)] = tar.extractfile(member).read()
    if current:
        yield (*current, files)


def case_parts(name, files):
    """The parts of one case: each file, by name without its extension."""
    yaml = YAML(typ="safe")
    parts = {}
    for file, data in sorted(files.items()):
        stem, _, ext = file.partition(".")
        if ext == "ssz_snappy":
            parts[stem] = snappy.uncompress(data)
        elif ext == "yaml":
            parts[stem] = yaml.load(data)
        else:
            fail(f"{name}: file {file} has an unknown kind")
    return parts


def write_file(path, cases):
    data = bytearray(MAGIC + u64(len(cases)))
    for name, parts in cases:
        data += blob(name.encode()) + tlv(parts)
    path.write_bytes(data)
    return len(cases), hashlib.sha256(data).hexdigest()


def write_descriptors(path, preset):
    """Every SSZ container type of the Fulu spec, with its reference descriptor."""
    spec = __import__(f"eth_consensus_specs.{FORK}.{preset}", fromlist=["*"])
    types = {}
    for name in sorted(dir(spec)):
        t = getattr(spec, name)
        if isinstance(t, type) and issubclass(t, Container) and t is not Container and t.__name__ == name:
            try:
                types[name] = descriptor.build(t)
            except ValueError:
                continue  # a kind outside asm-ssz's scope, such as a progressive type of a later fork
    return write_file(path, [(name, {"descriptor": d}) for name, d in types.items()])


def write_kzg_setup(path, preset):
    """The KZG trusted setup of the preset, presets/<preset>/trusted_setups/trusted_setup_4096.json
    of the pinned spec, as one case of three byte strings: the compressed points of each list."""
    spec = pathlib.Path(os.environ["CONSENSUS_SPECS"])
    setup = json.loads((spec / "presets" / preset / "trusted_setups" / "trusted_setup_4096.json").read_text())
    parts = {key: b"".join(bytes.fromhex(p[2:]) for p in setup[key]) for key in ("g1_lagrange", "g1_monomial", "g2_monomial")}
    return write_file(path, [("trusted_setup", parts)])


def write_config(path, preset):
    """The config of the preset, configs/<preset>.yaml of the pinned spec, as one case."""
    spec = pathlib.Path(os.environ["CONSENSUS_SPECS"])
    config = YAML(typ="safe").load((spec / "configs" / f"{preset}.yaml").read_text())
    return write_file(path, [("config", config)])


def main():
    if len(sys.argv) < 2:
        fail("usage: generate.py OUT_DIR [RUNNER ...]")
    out = pathlib.Path(sys.argv[1])
    runners = set(sys.argv[2:])
    sources = out / "sources"
    sources.mkdir(parents=True, exist_ok=True)
    manifest = []
    for preset, sha256 in ARCHIVES.items():
        archives = [(f"{preset}.tar.gz", sha256)]
        if preset == COMPTESTS[1]:
            archives.append((COMPTESTS[0], COMPTESTS[2]))
        for name, digest in archives:
            fetch(RELEASE + name, digest, sources / name)
        count, digest = write_descriptors(out / f"{preset}-descriptors.bin", preset)
        manifest.append((f"{preset}-descriptors.bin", count, digest))
        count, digest = write_config(out / f"{preset}-config.bin", preset)
        manifest.append((f"{preset}-config.bin", count, digest))
        count, digest = write_kzg_setup(out / f"{preset}-kzg_setup.bin", preset)
        manifest.append((f"{preset}-kzg_setup.bin", count, digest))
        groups = {}
        for archive, _ in archives:
            for runner, handler, suite, case, files in read_cases(sources / archive, runners):
                name = f"{suite}/{case}"
                groups.setdefault((runner, handler), []).append((name, case_parts(name, files)))
        for (runner, handler), cases in sorted(groups.items()):
            file = f"{preset}-{runner}-{handler}.bin"
            count, digest = write_file(out / file, cases)
            manifest.append((file, count, digest))
            print(f"{file}: {count} cases")
    # With RUNNER names, the entries of the other files stay.
    path = out / "manifest.txt"
    entries = {}
    if runners and path.exists():
        entries = {line.split()[0]: line for line in path.read_text().splitlines() if line}
    entries.update({file: f"{file} {count} {digest}" for file, count, digest in manifest})
    path.write_text("\n".join(entries[file] for file in sorted(entries)) + "\n")


if __name__ == "__main__":
    main()
