#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANTERN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LEAN_SPEC_DIR="${LANTERN_ROOT}/tools/leanSpec"
FIXTURE_ROOT="${LANTERN_ROOT}/tests/fixtures"
CONSENSUS_DIR="${FIXTURE_ROOT}/consensus"

if [[ ! -d "${LEAN_SPEC_DIR}" ]]; then
  echo "leanSpec tools directory not found: ${LEAN_SPEC_DIR}" >&2
  exit 1
fi

TMP_OUTPUT="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_OUTPUT}"
}
trap cleanup EXIT

(
  cd "${LEAN_SPEC_DIR}"
  uv run fill --fork=Devnet --layer=consensus --clean --output "${TMP_OUTPUT}"
)

if [[ -d "${TMP_OUTPUT}/consensus" ]]; then
  GENERATED_CONSENSUS_DIR="${TMP_OUTPUT}/consensus"
else
  GENERATED_CONSENSUS_DIR="${TMP_OUTPUT}"
fi

rm -rf "${CONSENSUS_DIR}"
mkdir -p "${CONSENSUS_DIR}"
cp -R "${GENERATED_CONSENSUS_DIR}/." "${CONSENSUS_DIR}/"
