#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${LANTERN_DATA_DIR:-/data}"

run_lantern() {
    if [[ "${LANTERN_PROFILE_HEAPTRACK:-}" == "true" ]]; then
        if ! command -v heaptrack >/dev/null 2>&1; then
            echo "LANTERN_PROFILE_HEAPTRACK=true but heaptrack is not installed; rebuild image with INCLUDE_HEAPTRACK=true" >&2
            exit 1
        fi
        local node_id="${LANTERN_NODE_ID:-lantern}"
        local out_dir="${LANTERN_HEAPTRACK_DIR:-${DATA_DIR}/heaptrack}"
        mkdir -p "${out_dir}"
        local out_prefix="${out_dir}/heaptrack.${node_id}.$(date -u +%Y%m%dT%H%M%SZ)"
        echo "Launching lantern under heaptrack: trace prefix ${out_prefix}" >&2
        exec heaptrack -o "${out_prefix}" /opt/lantern/bin/lantern "$@"
    fi
    exec /opt/lantern/bin/lantern "$@"
}

if [[ "$#" -gt 0 ]]; then
    if [[ "$1" == --* ]]; then
        run_lantern "$@"
    else
        exec "$@"
    fi
fi
GENESIS_DIR="${LANTERN_GENESIS_DIR:-/genesis}"
CONFIG_DIR="${LANTERN_CONFIG_DIR:-/config}"

NODE_ID="${LANTERN_NODE_ID:-lantern_0}"
DEVNET="${LANTERN_DEVNET:-devnet}"
LISTEN_ADDRESS="${LANTERN_LISTEN_ADDRESS:-/ip4/0.0.0.0/udp/9000/quic-v1}"
HTTP_PORT="${LANTERN_HTTP_PORT:-5052}"
METRICS_PORT="${LANTERN_METRICS_PORT:-8080}"

GENESIS_CONFIG="${LANTERN_GENESIS_CONFIG:-${GENESIS_DIR}/config.yaml}"
NODES_FILE="${LANTERN_NODES_FILE:-${GENESIS_DIR}/nodes.yaml}"
GENESIS_STATE="${LANTERN_GENESIS_STATE:-${GENESIS_DIR}/genesis.ssz}"
VALIDATOR_CONFIG_DIR="${LANTERN_VALIDATOR_CONFIG_DIR:-${GENESIS_DIR}}"
ANNOTATED_VALIDATORS="${VALIDATOR_CONFIG_DIR}/annotated_validators.yaml"
VALIDATOR_CONFIG="${VALIDATOR_CONFIG_DIR}/validator-config.yaml"

NODE_KEY_HEX="${LANTERN_NODE_KEY_HEX:-}"
NODE_KEY_PATH="${LANTERN_NODE_KEY_PATH:-${CONFIG_DIR}/keys/${NODE_ID}.key}"

BOOTNODES="${LANTERN_BOOTNODES:-${NODES_FILE}}"

for required in "${GENESIS_CONFIG}" "${ANNOTATED_VALIDATORS}" "${NODES_FILE}" "${GENESIS_STATE}" "${VALIDATOR_CONFIG}"; do
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
    "--nodes-path" "${NODES_FILE}"
    "--genesis-state" "${GENESIS_STATE}"
    "--validator_config" "${VALIDATOR_CONFIG_DIR}"
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


run_lantern "${args[@]}"
