#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/run_local_devnet.sh start <node_count> [genesis_dir] [binary|docker]
  scripts/run_local_devnet.sh stop <node_count> [binary|docker]

Spins up or stops a local devnet with N Lantern nodes.

Args:
  mode         start | stop
  node_count   Number of nodes to start/stop (>=1)
  genesis_dir  Path to a genesis directory (optional, start only)
  runtime      binary | docker (optional; default: binary)

Environment overrides (start):
  BIN                Path to lantern_cli (default: ./build/lantern_cli)
  GENESIS_DIR        Default genesis directory if arg not provided
  REGENERATE_GENESIS 1 to refresh GENESIS_TIME + genesis.ssz (default: 1)
  GENESIS_DELAY      Seconds to add to current time (default: 30)
  BASE_PORT          Base QUIC port (default: 19200)
  BASE_METRICS       Base metrics port (default: 18200)
  BASE_HTTP          Base HTTP port (default: 5055)
  USE_VALIDATOR_CONFIG_PORTS 1 to read QUIC/metrics ports from validator-config.yaml (default: 1)
  AUTO_GENESIS       1 to auto-generate validator-config + genesis if missing (default: 1)
  GENESIS_ENR_IP     ENR IP to embed in validator-config.yaml (default: 127.0.0.1)
  GENESIS_ACTIVE_EPOCH Active epoch for generated validator-config.yaml (default: 18)
  GENESIS_KEY_TYPE   Key type for generated validator-config.yaml (default: xmss)
  GENESIS_SHUFFLE    Shuffle mode for generated validator-config.yaml (default: roundrobin)
  GENESIS_AGGREGATOR_INDEX Validator index marked with enrFields.is_aggregator=true (default: 0)
  GENESIS_GENERATOR  Path to generate-genesis.sh (default: tools/lean-quickstart/generate-genesis.sh)
  LOG_LEVEL          Lantern log level (default: info)
  DEVNET             Devnet name (default: devnet3)
  RUN_DIR            Run directory (default: /tmp/lantern-local-devnet-run)
  CLEAN_RUN_DIR      1 to delete RUN_DIR data/logs before start (default: 1)
  LEANSPEC_PY        Path to leanSpec python (default: tools/leanSpec/.venv/bin/python)
  LANTERN_IMAGE      Docker image to run (default: lantern:local)
  DOCKER_NETWORK     Docker network mode (default: host)
  DOCKER_BUILD       1 to build image before start (default: 1)
  DOCKER_BUILD_ARGS  Extra args passed to docker build (optional)
  DOCKER_LISTEN_IP   Listen IP for docker nodes (default: 127.0.0.1 for host, 0.0.0.0 otherwise)
  ENABLE_COREDUMP    1 to enable core dumps for crashes (default: 0)

Example:
  scripts/run_local_devnet.sh start 4 /tmp/lantern-local-devnet/genesis binary
  scripts/run_local_devnet.sh start 4 /tmp/lantern-local-devnet/genesis docker
  scripts/run_local_devnet.sh stop 2
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

MODE=$1
shift
case "${MODE}" in
  start|stop) ;;
  *)
    echo "error: mode must be 'start' or 'stop'" >&2
    usage
    exit 1
    ;;
esac

NODES=$1
shift
if ! [[ "${NODES}" =~ ^[0-9]+$ ]] || (( NODES < 1 )); then
  echo "error: node_count must be a positive integer" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

RUNTIME=${RUNTIME:-binary}
GENESIS_DIR_ARG=""
for arg in "$@"; do
  case "${arg}" in
    docker|binary)
      RUNTIME="${arg}"
      ;;
    *)
      if [[ -z "${GENESIS_DIR_ARG}" ]]; then
        GENESIS_DIR_ARG="${arg}"
      else
        echo "error: unexpected argument '${arg}'" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

BIN=${BIN:-"${REPO_ROOT}/build/lantern_cli"}
LEANSPEC_PY=${LEANSPEC_PY:-"${REPO_ROOT}/tools/leanSpec/.venv/bin/python"}
REGENERATE_GENESIS=${REGENERATE_GENESIS:-1}
GENESIS_DELAY=${GENESIS_DELAY:-30}
BASE_PORT=${BASE_PORT:-19200}
BASE_METRICS=${BASE_METRICS:-18200}
BASE_HTTP=${BASE_HTTP:-5055}
USE_VALIDATOR_CONFIG_PORTS=${USE_VALIDATOR_CONFIG_PORTS:-1}
AUTO_GENESIS=${AUTO_GENESIS:-1}
GENESIS_ENR_IP=${GENESIS_ENR_IP:-127.0.0.1}
GENESIS_ACTIVE_EPOCH=${GENESIS_ACTIVE_EPOCH:-18}
GENESIS_KEY_TYPE=${GENESIS_KEY_TYPE:-xmss}
GENESIS_SHUFFLE=${GENESIS_SHUFFLE:-roundrobin}
GENESIS_AGGREGATOR_INDEX=${GENESIS_AGGREGATOR_INDEX:-0}
GENESIS_GENERATOR=${GENESIS_GENERATOR:-"${REPO_ROOT}/tools/lean-quickstart/generate-genesis.sh"}
LOG_LEVEL=${LOG_LEVEL:-info}
DEVNET=${DEVNET:-devnet3}
RUN_DIR=${RUN_DIR:-/tmp/lantern-local-devnet-run}
CLEAN_RUN_DIR=${CLEAN_RUN_DIR:-1}
LANTERN_IMAGE=${LANTERN_IMAGE:-lantern:local}
DOCKER_NETWORK=${DOCKER_NETWORK:-host}
DOCKER_BUILD=${DOCKER_BUILD:-1}
DOCKER_BUILD_ARGS=${DOCKER_BUILD_ARGS:-}
DOCKER_LISTEN_IP=${DOCKER_LISTEN_IP:-}
ENABLE_COREDUMP=${ENABLE_COREDUMP:-0}

if [[ -z "${DOCKER_LISTEN_IP}" ]]; then
  if [[ "${DOCKER_NETWORK}" == "host" ]]; then
    DOCKER_LISTEN_IP="127.0.0.1"
  else
    DOCKER_LISTEN_IP="0.0.0.0"
  fi
fi

PIDS_FILE="${RUN_DIR}/pids"
META_FILE="${RUN_DIR}/meta"

read_meta_runtime() {
  if [[ -f "${META_FILE}" ]]; then
    while IFS= read -r line; do
      case "${line}" in
        RUNTIME=*)
          echo "${line#RUNTIME=}"
          return 0
          ;;
      esac
    done < "${META_FILE}"
  fi
  return 1
}


if [[ "${MODE}" == "stop" ]]; then
  meta_runtime="$(read_meta_runtime || true)"
  if [[ -n "${meta_runtime}" ]]; then
    RUNTIME="${meta_runtime}"
  fi
  if [[ -n "${GENESIS_DIR_ARG}" ]]; then
    echo "error: genesis_dir is not used with stop mode" >&2
    exit 1
  fi
  if [[ "${RUNTIME}" == "docker" ]] && ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not found in PATH" >&2
    exit 1
  fi
  if [[ ! -f "${PIDS_FILE}" ]]; then
    echo "error: no running devnet found at ${PIDS_FILE}" >&2
    exit 1
  fi
  pids=()
  while IFS= read -r line; do
    pids+=("${line}")
  done < "${PIDS_FILE}"
  total=${#pids[@]}
  if (( total == 0 )); then
    echo "no pids recorded in ${PIDS_FILE}" >&2
    exit 1
  fi
  to_stop=${NODES}
  if (( to_stop > total )); then
    to_stop=${total}
  fi
  for i in $(seq 0 $((to_stop-1))); do
    pid="${pids[$i]}"
    if [[ -n "${pid}" ]]; then
      if [[ "${RUNTIME}" == "docker" ]]; then
        docker rm -f "${pid}" >/dev/null 2>&1 || true
      else
        kill -9 "${pid}" >/dev/null 2>&1 || true
      fi
    fi
  done
  if (( to_stop < total )); then
    printf "%s\n" "${pids[@]:$to_stop}" > "${PIDS_FILE}"
  else
    : > "${PIDS_FILE}"
  fi
  echo "Stopped ${to_stop} node(s). Remaining: $((total - to_stop))"
  exit 0
fi

GENESIS_DIR=${GENESIS_DIR_ARG:-${GENESIS_DIR:-/tmp/lantern-local-devnet/genesis}}

generate_validator_config() {
  local output="${GENESIS_DIR}/validator-config.yaml"
  local aggregator_index="${GENESIS_AGGREGATOR_INDEX}"
  if ! [[ "${aggregator_index}" =~ ^[0-9]+$ ]] || (( aggregator_index >= NODES )); then
    echo "warning: GENESIS_AGGREGATOR_INDEX='${GENESIS_AGGREGATOR_INDEX}' is invalid for ${NODES} node(s); defaulting to 0" >&2
    aggregator_index=0
  fi
  mkdir -p "${GENESIS_DIR}"
  local tmp
  tmp="$(mktemp "${GENESIS_DIR}/validator-config.yaml.tmp.XXXXXX")"
  cat > "${tmp}" <<EOF
shuffle: ${GENESIS_SHUFFLE}
deployment_mode: local
config:
  activeEpoch: ${GENESIS_ACTIVE_EPOCH}
  keyType: "${GENESIS_KEY_TYPE}"
validators:
EOF
  for i in $(seq 0 $((NODES-1))); do
    local privkey
    privkey="$(LAN_NODE_INDEX="${i}" python3 - <<'PY'
import hashlib
import os
idx = int(os.environ["LAN_NODE_INDEX"])
print(hashlib.sha256(f"lantern_{idx}".encode()).hexdigest())
PY
)"
    local quic=$((BASE_PORT + i))
    local metrics=$((BASE_METRICS + i))
    cat >> "${tmp}" <<EOF
  - name: "lantern_${i}"
    privkey: "${privkey}"
    enrFields:
      ip: "${GENESIS_ENR_IP}"
      quic: ${quic}
EOF
    if (( i == aggregator_index )); then
      cat >> "${tmp}" <<EOF
      is_aggregator: true
EOF
    fi
    cat >> "${tmp}" <<EOF
    metricsPort: ${metrics}
    count: 1

EOF
  done
  mv "${tmp}" "${output}"
}

validator_config_invalid() {
  local config_path="${GENESIS_DIR}/validator-config.yaml"
  if [[ ! -f "${config_path}" ]]; then
    return 0
  fi
  if command -v yq >/dev/null 2>&1; then
    local validator_count total
    validator_count="$(yq eval '.validators | length' "${config_path}" 2>/dev/null || echo 0)"
    if [[ -z "${validator_count}" || "${validator_count}" == "null" || "${validator_count}" -eq 0 ]]; then
      return 0
    fi
    total="$(yq eval '.validators[].count' "${config_path}" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')"
    if [[ -z "${total}" || "${total}" -le 0 ]]; then
      return 0
    fi
    return 1
  fi
  if command -v rg >/dev/null 2>&1; then
    rg -q "^\s*count:\s*[0-9]+" "${config_path}" || return 0
  else
    grep -Eq "^\s*count:\s*[0-9]+" "${config_path}" || return 0
  fi
  return 1
}

generate_genesis_artifacts() {
  if [[ ! -x "${GENESIS_GENERATOR}" ]]; then
    echo "error: genesis generator not found at ${GENESIS_GENERATOR}" >&2
    echo "hint: set GENESIS_GENERATOR or generate genesis manually" >&2
    exit 1
  fi
  "${GENESIS_GENERATOR}" "${GENESIS_DIR}" --mode local --forceKeyGen
}

if [[ "${RUNTIME}" != "docker" ]]; then
  if [[ ! -x "$BIN" ]]; then
    echo "error: lantern_cli not found at $BIN" >&2
    echo "hint: build it with: cmake --build build -j 8" >&2
    exit 1
  fi
else
  if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker not found in PATH" >&2
    exit 1
  fi
fi

required_files=(
  "config.yaml"
  "validators.yaml"
  "nodes.yaml"
  "validator-config.yaml"
  "genesis.ssz"
)
missing=()
for file in "${required_files[@]}"; do
  if [[ ! -f "${GENESIS_DIR}/${file}" ]]; then
    missing+=("${file}")
  fi
done
if (( ${#missing[@]} > 0 )); then
  if [[ "${AUTO_GENESIS}" != "1" ]]; then
    printf "error: missing genesis artifacts in %s:\n" "${GENESIS_DIR}" >&2
    printf "  - %s\n" "${missing[@]}" >&2
    exit 1
  fi
  if [[ ! -f "${GENESIS_DIR}/validator-config.yaml" ]] || validator_config_invalid; then
    echo "validator-config.yaml missing/invalid; generating for ${NODES} node(s)..." >&2
    generate_validator_config
  fi
  echo "genesis artifacts missing; generating via ${GENESIS_GENERATOR}..." >&2
  generate_genesis_artifacts
  missing=()
  for file in "${required_files[@]}"; do
    if [[ ! -f "${GENESIS_DIR}/${file}" ]]; then
      missing+=("${file}")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    printf "error: genesis generation incomplete, still missing:\n" >&2
    printf "  - %s\n" "${missing[@]}" >&2
    exit 1
  fi
fi

if validator_config_invalid; then
  echo "error: validator-config.yaml missing validator counts; regenerate it and retry." >&2
  exit 1
fi

HASH_SIG_KEYS_DIR="${GENESIS_DIR}/hash-sig-keys"
HASH_SIG_KEYS_DIR_NAME="hash-sig-keys"
if [[ ! -d "${HASH_SIG_KEYS_DIR}" ]]; then
  echo "error: missing ${HASH_SIG_KEYS_DIR}" >&2
  exit 1
fi

for i in $(seq 0 $((NODES-1))); do
  if [[ ! -f "${GENESIS_DIR}/lantern_${i}.key" ]]; then
    echo "error: missing ${GENESIS_DIR}/lantern_${i}.key" >&2
    exit 1
  fi
  if [[ ! -f "${HASH_SIG_KEYS_DIR}/validator_${i}_pk.ssz" ]]; then
    echo "error: missing ${HASH_SIG_KEYS_DIR}/validator_${i}_pk.ssz" >&2
    exit 1
  fi
  if [[ ! -f "${HASH_SIG_KEYS_DIR}/validator_${i}_sk.ssz" ]]; then
    echo "error: missing ${HASH_SIG_KEYS_DIR}/validator_${i}_sk.ssz" >&2
    exit 1
  fi
done

VC_QUIC_PORTS=()
VC_METRICS_PORTS=()
if [[ "${USE_VALIDATOR_CONFIG_PORTS}" == "1" ]]; then
  if command -v rg >/dev/null 2>&1; then
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      VC_QUIC_PORTS+=("${line}")
    done < <(rg -o "quic:\\s*[0-9]+" "${GENESIS_DIR}/validator-config.yaml" | awk '{print $2}')
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      VC_METRICS_PORTS+=("${line}")
    done < <(rg -o "metricsPort:\\s*[0-9]+" "${GENESIS_DIR}/validator-config.yaml" | awk '{print $2}')
  else
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      VC_QUIC_PORTS+=("${line}")
    done < <(grep -Eo "quic:[[:space:]]*[0-9]+" "${GENESIS_DIR}/validator-config.yaml" | awk '{print $2}')
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      VC_METRICS_PORTS+=("${line}")
    done < <(grep -Eo "metricsPort:[[:space:]]*[0-9]+" "${GENESIS_DIR}/validator-config.yaml" | awk '{print $2}')
  fi
  if (( ${#VC_QUIC_PORTS[@]} == 0 )); then
    echo "warning: validator-config.yaml has no quic ports; falling back to BASE_PORT" >&2
  fi
  if (( ${#VC_METRICS_PORTS[@]} == 0 )); then
    echo "warning: validator-config.yaml has no metricsPort entries; falling back to BASE_METRICS" >&2
  fi
fi

if [[ "${REGENERATE_GENESIS}" == "1" ]]; then
  NEW_TIME=$(( $(date -u +%s) + GENESIS_DELAY ))
  if ! python3 - <<PY
import pathlib
path = pathlib.Path("${GENESIS_DIR}/config.yaml")
lines = path.read_text().splitlines()
out = []
for line in lines:
    if line.startswith("GENESIS_TIME:"):
        out.append(f"GENESIS_TIME: {int(${NEW_TIME})}")
    else:
        out.append(line)
path.write_text("\n".join(out) + "\n")
PY
  then
    echo "warning: failed to update GENESIS_TIME in config.yaml; keeping existing value" >&2
  fi

  if [[ ! -x "${LEANSPEC_PY}" ]]; then
    echo "error: leanSpec python not found at ${LEANSPEC_PY}" >&2
    echo "hint: run 'cd tools/leanSpec && uv sync' to set up leanSpec" >&2
    exit 1
  fi

  if ! GENESIS_DIR="${GENESIS_DIR}" HASH_SIG_KEYS_DIR="${HASH_SIG_KEYS_DIR}" PYTHONPATH="${REPO_ROOT}/tools/leanSpec/src" "${LEANSPEC_PY}" - <<'PY'
import os
import pathlib
import yaml
from lean_spec.subspecs.containers.state import State, Validators
from lean_spec.subspecs.containers.validator import Validator
from lean_spec.types import Bytes52, Uint64

genesis_dir = pathlib.Path(os.environ["GENESIS_DIR"])
keys_dir = pathlib.Path(os.environ["HASH_SIG_KEYS_DIR"])
config = yaml.safe_load((genesis_dir / "config.yaml").read_text())
num_validators = int(config.get("VALIDATOR_COUNT", 0))
validators = []
for i in range(num_validators):
    pk = (keys_dir / f"validator_{i}_pk.ssz").read_bytes()
    validators.append(Validator(pubkey=Bytes52(pk), index=Uint64(i)))
state = State.generate_genesis(
    genesis_time=Uint64(int(config["GENESIS_TIME"])),
    validators=Validators(data=validators),
)
(genesis_dir / "genesis.ssz").write_bytes(state.encode_bytes())
PY
  then
    echo "error: leanSpec genesis regeneration failed" >&2
    exit 1
  fi
fi

if [[ "${RUNTIME}" == "docker" && "${DOCKER_BUILD}" == "1" ]]; then
  echo "Building docker image ${LANTERN_IMAGE}..."
  git_build_args=(
    --build-arg "GIT_COMMIT=$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    --build-arg "GIT_BRANCH=$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  )
  if [[ -n "${DOCKER_BUILD_ARGS}" ]]; then
    # shellcheck disable=SC2206
    docker_build_args=(${DOCKER_BUILD_ARGS})
    docker build "${git_build_args[@]}" "${docker_build_args[@]}" -t "${LANTERN_IMAGE}" "${REPO_ROOT}"
  else
    docker build "${git_build_args[@]}" -t "${LANTERN_IMAGE}" "${REPO_ROOT}"
  fi
fi

if [[ -f "${PIDS_FILE}" ]]; then
  meta_runtime="$(read_meta_runtime || true)"
  runtime_check="${meta_runtime:-${RUNTIME}}"
  while read -r pid; do
    if [[ -z "${pid}" ]]; then
      continue
    fi
    if [[ "${runtime_check}" == "docker" ]]; then
    if command -v rg >/dev/null 2>&1; then
      if docker ps -a --format '{{.Names}}' | rg -q "^${pid}$"; then
        echo "error: devnet appears to be running (container ${pid})." >&2
        echo "hint: stop it with: ${0} stop ${NODES} docker" >&2
        exit 1
      fi
    else
      if docker ps -a --format '{{.Names}}' | grep -Eq "^${pid}$"; then
        echo "error: devnet appears to be running (container ${pid})." >&2
        echo "hint: stop it with: ${0} stop ${NODES} docker" >&2
        exit 1
      fi
    fi
    else
      if kill -0 "${pid}" >/dev/null 2>&1; then
        echo "error: devnet appears to be running (pid ${pid})." >&2
        echo "hint: stop it with: ${0} stop ${NODES}" >&2
        exit 1
      fi
    fi
  done < "${PIDS_FILE}"
fi

if [[ "${CLEAN_RUN_DIR}" == "1" && -d "${RUN_DIR}" ]]; then
  rm -rf "${RUN_DIR}/data" "${RUN_DIR}/logs" "${RUN_DIR}/pids" "${RUN_DIR}/meta"
fi

mkdir -p "${RUN_DIR}"
LOG_DIR="${RUN_DIR}/logs"
DATA_DIR="${RUN_DIR}/data"
mkdir -p "${LOG_DIR}" "${DATA_DIR}"
printf "MODE=start\nNODE_COUNT=%s\nGENESIS_DIR=%s\nRUNTIME=%s\nSTARTED_AT=%s\n" \
  "${NODES}" "${GENESIS_DIR}" "${RUNTIME}" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  > "${META_FILE}"
truncate -s 0 "${PIDS_FILE}"

if [[ "${ENABLE_COREDUMP}" == "1" ]]; then
  ulimit -c unlimited || true
fi

for i in $(seq 0 $((NODES-1))); do
  if (( ${#VC_QUIC_PORTS[@]} > i )); then
    PORT="${VC_QUIC_PORTS[$i]}"
  else
    PORT=$((BASE_PORT + i))
  fi
  if (( ${#VC_METRICS_PORTS[@]} > i )); then
    METRICS="${VC_METRICS_PORTS[$i]}"
  else
    METRICS=$((BASE_METRICS + i))
  fi
  HTTP=$((BASE_HTTP + i))
  NODE_ID="lantern_${i}"
  DATA="${DATA_DIR}/${NODE_ID}"
  mkdir -p "${DATA}"

  if [[ "${RUNTIME}" == "docker" ]]; then
    if command -v rg >/dev/null 2>&1; then
      if docker ps -a --format '{{.Names}}' | rg -q "^${NODE_ID}$"; then
        echo "error: docker container ${NODE_ID} already exists" >&2
        exit 1
      fi
    else
      if docker ps -a --format '{{.Names}}' | grep -Eq "^${NODE_ID}$"; then
        echo "error: docker container ${NODE_ID} already exists" >&2
        exit 1
      fi
    fi
    docker_args=(
      run -d
      --name "${NODE_ID}"
      -v "${GENESIS_DIR}:/genesis:ro"
      -v "${DATA}:/data"
      -v "${LOG_DIR}:/logs"
      -e "LANTERN_DATA_DIR=/data"
      -e "LANTERN_GENESIS_DIR=/genesis"
      -e "LANTERN_CONFIG_DIR=/genesis"
      -e "LANTERN_NODE_ID=${NODE_ID}"
      -e "LANTERN_DEVNET=${DEVNET}"
      -e "LANTERN_LISTEN_ADDRESS=/ip4/${DOCKER_LISTEN_IP}/udp/${PORT}/quic-v1"
      -e "LANTERN_HTTP_PORT=${HTTP}"
      -e "LANTERN_METRICS_PORT=${METRICS}"
      -e "LANTERN_NODE_KEY_PATH=/genesis/lantern_${i}.key"
      -e "LANTERN_GENESIS_CONFIG=/genesis/config.yaml"
      -e "LANTERN_VALIDATOR_REGISTRY=/genesis/validators.yaml"
      -e "LANTERN_NODES_FILE=/genesis/nodes.yaml"
      -e "LANTERN_GENESIS_STATE=/genesis/genesis.ssz"
      -e "LANTERN_VALIDATOR_CONFIG=/genesis/validator-config.yaml"
      -e "LANTERN_EXTRA_ARGS=--hash-sig-key-dir /genesis/${HASH_SIG_KEYS_DIR_NAME} --log-level ${LOG_LEVEL}${CHECKPOINT_SYNC_URL:+ --checkpoint-sync-url ${CHECKPOINT_SYNC_URL}}"
    )
    if [[ "${ENABLE_COREDUMP}" == "1" ]]; then
      docker_args+=(--ulimit core=-1)
    fi
    if [[ "${DOCKER_NETWORK}" == "host" ]]; then
      docker_args+=(--network host)
    else
      docker_args+=(--network "${DOCKER_NETWORK}")
      docker_args+=(-p "${PORT}:${PORT}/udp" -p "${HTTP}:${HTTP}" -p "${METRICS}:${METRICS}")
    fi
    docker_args+=(--entrypoint /bin/bash)
    if [[ "${ENABLE_COREDUMP}" == "1" ]]; then
      docker_args+=(
        "${LANTERN_IMAGE}"
        -lc "ulimit -c unlimited; exec /usr/local/bin/lantern-entrypoint.sh 2>&1 | tee -a /logs/${NODE_ID}.log"
      )
    else
      docker_args+=(
        "${LANTERN_IMAGE}"
        -lc "exec /usr/local/bin/lantern-entrypoint.sh 2>&1 | tee -a /logs/${NODE_ID}.log"
      )
    fi
    docker "${docker_args[@]}" >/dev/null
    echo "${NODE_ID}" >> "${PIDS_FILE}"
  else
    nohup "${BIN}" \
      --data-dir "${DATA}" \
      --genesis-config "${GENESIS_DIR}/config.yaml" \
      --validator-registry-path "${GENESIS_DIR}/validators.yaml" \
      --nodes-path "${GENESIS_DIR}/nodes.yaml" \
      --genesis-state "${GENESIS_DIR}/genesis.ssz" \
      --validator-config "${GENESIS_DIR}/validator-config.yaml" \
      --node-id "${NODE_ID}" \
      --node-key-path "${GENESIS_DIR}/lantern_${i}.key" \
      --listen-address "/ip4/127.0.0.1/udp/${PORT}/quic-v1" \
      --http-port "${HTTP}" \
      --metrics-port "${METRICS}" \
      --devnet "${DEVNET}" \
      --hash-sig-key-dir "${HASH_SIG_KEYS_DIR}" \
      --log-level "${LOG_LEVEL}" \
      >"${LOG_DIR}/${NODE_ID}.log" 2>&1 &
    echo $! >> "${PIDS_FILE}"
  fi
  sleep 0.2
done

echo "RUN_DIR=${RUN_DIR}"
echo "Logs: ${LOG_DIR}"
if (( ${#VC_METRICS_PORTS[@]} >= NODES )); then
  metrics_list=$(printf "%s " "${VC_METRICS_PORTS[@]:0:${NODES}}")
  echo "Metrics ports: ${metrics_list% }"
else
  echo "Metrics ports: ${BASE_METRICS}..$((BASE_METRICS + NODES - 1))"
fi
echo "Stop with: ${0} stop ${NODES} ${RUNTIME}"
