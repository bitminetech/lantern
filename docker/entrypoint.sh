#!/usr/bin/env bash
set -euo pipefail

# Allow users to pass explicit arguments to lantern_cli. If arguments begin
# with a flag (e.g. `--data-dir`), treat them as Lantern CLI options;
# otherwise execute the provided command verbatim (needed for gdb/lldb).
if [[ "$#" -gt 0 ]]; then
    if [[ "$1" == --* ]]; then
        exec /opt/lantern/bin/lantern "$@"
    else
        exec "$@"
    fi
fi

DATA_DIR="${LANTERN_DATA_DIR:-/data}"
GENESIS_DIR="${LANTERN_GENESIS_DIR:-/genesis}"
CONFIG_DIR="${LANTERN_CONFIG_DIR:-/config}"

NODE_ID="${LANTERN_NODE_ID:-lantern_0}"
DEVNET="${LANTERN_DEVNET:-devnet}"
LISTEN_ADDRESS="${LANTERN_LISTEN_ADDRESS:-/ip4/0.0.0.0/udp/9000/quic-v1}"
HTTP_PORT="${LANTERN_HTTP_PORT:-5052}"
METRICS_PORT="${LANTERN_METRICS_PORT:-8080}"

GENESIS_CONFIG="${LANTERN_GENESIS_CONFIG:-${GENESIS_DIR}/config.yaml}"
VALIDATOR_REGISTRY="${LANTERN_VALIDATOR_REGISTRY:-${GENESIS_DIR}/validators.yaml}"
NODES_FILE="${LANTERN_NODES_FILE:-${GENESIS_DIR}/nodes.yaml}"
GENESIS_STATE="${LANTERN_GENESIS_STATE:-${GENESIS_DIR}/genesis.ssz}"
VALIDATOR_CONFIG="${LANTERN_VALIDATOR_CONFIG:-${GENESIS_DIR}/validator-config.yaml}"

NODE_KEY_HEX="${LANTERN_NODE_KEY_HEX:-}"
NODE_KEY_PATH="${LANTERN_NODE_KEY_PATH:-${CONFIG_DIR}/keys/${NODE_ID}.key}"

BOOTNODES="${LANTERN_BOOTNODES:-${NODES_FILE}}"

for required in "${GENESIS_CONFIG}" "${VALIDATOR_REGISTRY}" "${NODES_FILE}" "${GENESIS_STATE}" "${VALIDATOR_CONFIG}"; do
    if [[ ! -f "${required}" ]]; then
        echo "Required genesis artifact not found: ${required}" >&2
        exit 1
    fi
done

if [[ -z "${NODE_KEY_HEX}" && ! -f "${NODE_KEY_PATH}" ]]; then
    echo "Node key missing; set LANTERN_NODE_KEY_HEX or provide ${NODE_KEY_PATH}" >&2
    exit 1
fi

declare -a args
args=(
    "--data-dir" "${DATA_DIR}"
    "--genesis-config" "${GENESIS_CONFIG}"
    "--validator-registry-path" "${VALIDATOR_REGISTRY}"
    "--nodes-path" "${NODES_FILE}"
    "--genesis-state" "${GENESIS_STATE}"
    "--validator-config" "${VALIDATOR_CONFIG}"
    "--node-id" "${NODE_ID}"
    "--listen-address" "${LISTEN_ADDRESS}"
    "--http-port" "${HTTP_PORT}"
    "--metrics-port" "${METRICS_PORT}"
    "--devnet" "${DEVNET}"
)

if [[ -n "${NODE_KEY_HEX}" ]]; then
    args+=("--node-key" "${NODE_KEY_HEX}")
else
    args+=("--node-key-path" "${NODE_KEY_PATH}")
fi

IFS=',' read -ra bootnode_items <<< "${BOOTNODES}"
for entry in "${bootnode_items[@]}"; do
    trimmed="${entry#"${entry%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ -n "${trimmed}" ]]; then
        args+=("--bootnodes" "${trimmed}")
    fi
done

if [[ -n "${LANTERN_EXTRA_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    extra_args=(${LANTERN_EXTRA_ARGS})
    args+=("${extra_args[@]}")
fi


exec /opt/lantern/bin/lantern "${args[@]}"