#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "${ROOT_DIR}"

if [[ -d "${ROOT_DIR}/.git" ]]; then
    if [[ "${LANTERN_BOOTSTRAP_SKIP_SUBMODULE_SYNC:-0}" == "1" ]]; then
        echo "bootstrap: skipping submodule sync (requested)" >&2
    else
        git submodule update --init --recursive \
            external/c-libp2p \
            external/c-ssz \
            external/c-leanvm-xmss
    fi
else
    echo "bootstrap: skipping submodule sync (git metadata unavailable)" >&2
fi
