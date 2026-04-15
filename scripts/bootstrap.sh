#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_DIR="build"
GENERATE_FIXTURES=0

usage() {
    cat <<'EOF'
Usage: ./scripts/bootstrap.sh [--fixtures] [--build-dir <dir>]

  --fixtures         Configure a build directory (if needed) and run
                     `cmake --build <dir> --target fixtures`.
  --build-dir <dir>  Build directory to use with --fixtures. Default: build
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fixtures)
            GENERATE_FIXTURES=1
            ;;
        --build-dir)
            if [[ $# -lt 2 ]]; then
                usage >&2
                exit 1
            fi
            BUILD_DIR="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
    shift
done

cd "${ROOT_DIR}"

if [[ -d "${ROOT_DIR}/.git" ]]; then
    if [[ "${LANTERN_BOOTSTRAP_SKIP_SUBMODULE_SYNC:-0}" == "1" ]]; then
        echo "bootstrap: skipping submodule sync (requested)" >&2
    else
        git submodule update --init --recursive \
            external/c-libp2p \
            external/c-ssz \
            external/c-leanvm-xmss \
            tools/leanSpec
    fi
else
    echo "bootstrap: skipping submodule sync (git metadata unavailable)" >&2
fi

if [[ "${GENERATE_FIXTURES}" == "1" ]]; then
    cmake -S . -B "${BUILD_DIR}"
    cmake --build "${BUILD_DIR}" --target fixtures
fi
