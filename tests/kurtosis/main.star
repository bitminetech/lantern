# A devnet of ethpandaops/ethereum-package from the args (participants, network_params, ...), and
# the lantern binary beside it: the network's config.yaml and genesis.ssz (the files artifact
# el_cl_genesis_data), its own address in its record, and the record of every consensus client as a
# boot node. args.lantern_image: the image of platform/docker/Dockerfile (default lantern:local);
# args.lantern_max_cpu: lantern's CPU limit in millicores (default 0, no limit); args.lantern_delay:
# seconds to wait before lantern starts, so that it syncs a chain that has moved on (default 0);
# args.lantern_data_dir: a directory for lantern's history (--data-dir, with --archive), or none (default);
# args.lantern_checkpoint: true to start lantern from the finalized block of the first client and
# its post-state (--checkpoint-block, --checkpoint-state), taken from its Beacon API once its
# finalized epoch is 1 or more (default false); args.lantern_assertoor: true to run Assertoor with
# lantern as its one consensus endpoint, beside the first client's geth, and the test "lantern" of
# ASSERTOOR_TESTS at its start (default false); args.lantern_vc: a client (lighthouse, prysm, teku, nimbus,
# lodestar) whose validator client runs keys LANTERN_VC_FIRST to LANTERN_VC_LAST - 1 of the mnemonic with
# lantern as its one beacon node, and lantern then takes the second participant's geth as its execution
# client (default none); args.lantern_vc_image: that validator client's image.
ethereum = import_module("github.com/ethpandaops/ethereum-package/main.star")

# The keys of lantern's validator client: those of the mnemonic past the first participant's 64.
LANTERN_VC_FIRST = 64
LANTERN_VC_LAST = 128

# The keystore tool of ethereum-package (src/prelaunch_data_generator/validator_keystores), pinned by digest.
ETH2_VAL_TOOLS_IMAGE = "protolambda/eth2-val-tools:latest@sha256:7fb4e35dd39845407e1c61b39a992202cd9ceb6203a5928ab1e00151401c4fae"

# The keystores of those keys in every client's layout, in /keys, as ethereum-package makes them; and
# the prysm wallet's password.
KEYSTORES_SH = """/app/eth2-val-tools keystores --insecure --prysm-pass password --out-loc /keys --source-mnemonic "MNEMONIC" --source-min FIRST --source-max LAST && chmod 0777 -R /keys/teku-keys && chmod 0600 -R /keys/secrets && echo 'password' > /keys/prysm-password.txt && ls /keys"""

# The fee recipient of ethereum-package's validator clients (its VALIDATING_REWARDS_ACCOUNT).
FEE_RECIPIENT = "0x8943545177806ED17B9F23F0a21ee5948eCaa776"

# Assertoor v0.1.2, its latest release, pinned by digest.
ASSERTOOR_IMAGE = "ethpandaops/assertoor:v0.1.2@sha256:aba67ca18ea77bece68abe1cca171642d9212c2c399d18740969105ae3442078"

# Its config: lantern as the one endpoint, the API without the frontend, and one test of the checks
# that read the Beacon API (Assertoor's tasks of v0.1.2), each over lantern; then operations of the
# validators of ethereum-package's default mnemonic (its DEFAULT_MNEMONIC, src/package_io/constants.star)
# through lantern's pool POSTs, each awaited in a block: lantern publishes them, the client includes them;
# and attestations of the two validators that no validator client runs (tests/app/devnet.sh), from
# their duties (getEpochCommittees) and lantern's produceAttestationData, through
# submitPoolAttestationsV2. Those two never vote otherwise, so the target votes have a floor of 95%.
ASSERTOOR_CONFIG = """endpoints:
- name: "lantern"
  consensusUrl: "{{ .LanternURL }}"
  executionUrl: "{{ .ElURL }}"
web:
  server:
    host: "0.0.0.0"
    port: "8080"
  frontend:
    enabled: false
  api:
    enabled: true
database:
  engine: "sqlite"
  sqlite:
    file: "/app/assertoor-database.sqlite"
tests:
- id: lantern
  name: "lantern answers Assertoor's Beacon API reads"
  timeout: 1h
  schedule:
    startup: true
  tasks:
  - name: check_clients_are_healthy
    title: "lantern is ready"
    timeout: 15m
    config:
      clientPattern: "lantern"
      minClientCount: 1
  - name: check_consensus_sync_status
    title: "lantern is synced"
    timeout: 20m
    config:
      clientPattern: "lantern"
  - name: check_consensus_identity
    title: "lantern's identity"
    timeout: 5m
    config:
      clientPattern: "lantern"
      minClientCount: 1
  - name: run_tasks_concurrent
    title: "the chain through lantern"
    timeout: 40m
    config:
      tasks:
      - name: check_consensus_slot_range
        title: "the chain reaches epoch 3"
        config:
          minEpochNumber: 3
      - name: check_consensus_block_proposals
        title: "blocks arrive through the event stream"
        config:
          blockCount: 2
      - name: check_consensus_proposer_duty
        title: "proposer duties"
      - name: check_consensus_finality
        title: "finality"
        config:
          minFinalizedEpochs: 2
          maxUnfinalizedEpochs: 3
      - name: check_consensus_attestation_stats
        title: "attestation stats, from the committees"
        config:
          minTargetPercent: 95
          minHeadPercent: 80
          minCheckedEpochs: 2
      - name: check_consensus_reorgs
        title: "reorgs"
        config:
          maxReorgsPerEpoch: 2
          minCheckEpochCount: 1
      - name: check_consensus_forks
        title: "forks"
  - name: run_tasks_concurrent
    title: "operations through lantern's pool POSTs, in blocks"
    timeout: 30m
    config:
      tasks:
      - name: generate_exits
        title: "two voluntary exits"
        config:
          limitTotal: 2
          limitPerSlot: 1
          mnemonic: "MNEMONIC"
          startIndex: 100
          indexCount: 2
          clientPattern: "lantern"
          awaitInclusion: true
      - name: generate_bls_changes
        title: "two BLS to execution changes"
        config:
          limitTotal: 2
          limitPerSlot: 1
          mnemonic: "MNEMONIC"
          startIndex: 104
          indexCount: 2
          targetAddress: "0x8943545177806ED17B9F23F0a21ee5948eCaa776"
          clientPattern: "lantern"
          awaitInclusion: true
      - name: generate_slashings
        title: "a proposer slashing"
        config:
          slashingType: proposer
          limitTotal: 1
          limitPerSlot: 1
          mnemonic: "MNEMONIC"
          startIndex: 108
          indexCount: 1
          clientPattern: "lantern"
          awaitInclusion: true
      - name: generate_slashings
        title: "an attester slashing"
        config:
          slashingType: attester
          limitTotal: 1
          limitPerSlot: 1
          mnemonic: "MNEMONIC"
          startIndex: 110
          indexCount: 1
          clientPattern: "lantern"
          awaitInclusion: true
      - name: generate_attestations
        title: "attestations of two epochs of the validators no client runs"
        config:
          limitEpochs: 2
          mnemonic: "MNEMONIC"
          startIndex: 128
          indexCount: 2
          clientPattern: "lantern"
""".replace("MNEMONIC", "giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete")

MNEMONIC = "giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"


# The command of CLIENT's validator client with the beacon node URL and the keys at /validator-keys, as
# ethereum-package's src/vc/CLIENT.star gives it (prysm over the REST API).
def vc_cmd(client, url):
    if client == "lighthouse":
        return ["lighthouse", "vc", "--testnet-dir=/network-configs", "--validators-dir=/validator-keys/keys", "--secrets-dir=/validator-keys/secrets", "--init-slashing-protection", "--beacon-nodes=" + url, "--suggested-fee-recipient=" + FEE_RECIPIENT]
    if client == "lodestar":
        return ["validator", "--paramsFile=/network-configs/config.yaml", "--beaconNodes=" + url, "--suggestedFeeRecipient=" + FEE_RECIPIENT, "--useProduceBlockV3", "--disableKeystoresThreadPool", "--keystoresDir=/validator-keys/keys", "--secretsDir=/validator-keys/secrets"]
    if client == "teku":
        return ["validator-client", "--network=/network-configs/config.yaml", "--beacon-node-api-endpoint=" + url, "--validators-proposer-default-fee-recipient=" + FEE_RECIPIENT, "--validator-keys=/validator-keys/teku-keys:/validator-keys/teku-secrets"]
    if client == "nimbus":
        return ["--beacon-node=" + url, "--suggested-fee-recipient=" + FEE_RECIPIENT, "--validators-dir=/validator-keys/nimbus-keys", "--secrets-dir=/validator-keys/secrets"]
    if client == "prysm":
        return ["--accept-terms-of-use=true", "--chain-config-file=/network-configs/config.yaml", "--suggested-fee-recipient=" + FEE_RECIPIENT, "--beacon-rest-api-provider=" + url, "--enable-beacon-rest-api", "--wallet-dir=/validator-keys/prysm", "--wallet-password-file=/validator-keys/prysm-password.txt"]
    fail("no validator client for " + client)

# The finalized block and its post-state of the Beacon API at URL, as SSZ, in /checkpoint.
CHECKPOINT_SH = """mkdir -p /checkpoint
until [ "$(curl -sf URL/eth/v1/beacon/states/head/finality_checkpoints | jq -r .data.finalized.epoch)" -ge 1 ] 2>/dev/null; do sleep 6; done
header=$(curl -sf URL/eth/v1/beacon/headers/finalized)
root=$(echo "$header" | jq -r .data.root)
state=$(echo "$header" | jq -r .data.header.message.state_root)
curl -sf -H 'Accept: application/octet-stream' -o /checkpoint/block.ssz URL/eth/v2/beacon/blocks/$root
curl -sf -H 'Accept: application/octet-stream' -o /checkpoint/state.ssz URL/eth/v2/debug/beacon/states/$state
ls -l /checkpoint"""


def run(plan, args={}):
    lantern_image = args.get("lantern_image", "lantern:local")
    lantern_max_cpu = args.get("lantern_max_cpu", 0)
    lantern_delay = args.get("lantern_delay", 0)
    lantern_data_dir = args.get("lantern_data_dir", "")
    lantern_checkpoint = args.get("lantern_checkpoint", False)
    lantern_assertoor = args.get("lantern_assertoor", False)
    lantern_vc = args.get("lantern_vc", "")
    lantern_vc_image = args.get("lantern_vc_image", "")
    network_args = {key: value for key, value in args.items() if key not in ("lantern_image", "lantern_max_cpu", "lantern_delay", "lantern_data_dir", "lantern_checkpoint", "lantern_assertoor", "lantern_vc", "lantern_vc_image")}
    out = ethereum.run(plan, network_args)
    if lantern_delay > 0:
        plan.run_sh(run="sleep {0}".format(lantern_delay), wait="{0}s".format(lantern_delay + 60))
    records = [participant.cl_context.enr for participant in out.all_participants]
    extra_args = ["--data-dir", lantern_data_dir, "--archive"] if lantern_data_dir else []
    files = {"/network-configs": "el_cl_genesis_data"}
    if lantern_checkpoint:
        url = out.all_participants[0].cl_context.beacon_http_url
        plan.run_sh(
            run=CHECKPOINT_SH.replace("URL", url),
            store=[StoreSpec(src="/checkpoint/", name="lantern_checkpoint")],
            wait="40m",
            description="the checkpoint of lantern",
        )
        files["/checkpoint"] = "lantern_checkpoint"
        extra_args += ["--checkpoint-state", "/checkpoint/state.ssz", "--checkpoint-block", "/checkpoint/block.ssz"]
    if lantern_vc:
        el = out.all_participants[1].el_context
        files["/jwt"] = "jwt_file"
        extra_args += ["--execution-endpoint", "http://{0}:{1}".format(el.ip_addr, el.engine_rpc_port_num), "--jwt-secret", "/jwt/jwtsecret"]
    lantern = plan.add_service(
        name="lantern",
        config=ServiceConfig(
            image=lantern_image,
            cmd=[
                "--network-dir",
                "/network-configs",
                "--port",
                "9000",
                "--http-address",
                "0.0.0.0",
                "--http-port",
                "5052",
                "--enr-address",
                "KURTOSIS_IP_ADDR_PLACEHOLDER",
                "--boot-nodes",
                ",".join(records),
            ] + extra_args,
            files=files,
            max_cpu=lantern_max_cpu,
            ports={
                "http": PortSpec(number=5052, application_protocol="http"),
                "tcp": PortSpec(number=9000, transport_protocol="TCP", wait=None),
                "udp": PortSpec(number=9000, transport_protocol="UDP", wait=None),
            },
        ),
    )
    if lantern_vc:
        plan.add_service(
            name="lantern-vc-keys",
            config=ServiceConfig(image=ETH2_VAL_TOOLS_IMAGE, entrypoint=["sleep", "99999"]),
        )
        made = plan.exec(
            service_name="lantern-vc-keys",
            description="the keystores of lantern's validator client",
            recipe=ExecRecipe(command=["sh", "-c", KEYSTORES_SH.replace("MNEMONIC", MNEMONIC).replace("FIRST", str(LANTERN_VC_FIRST)).replace("LAST", str(LANTERN_VC_LAST))]),
        )
        plan.verify(made["code"], "==", 0)
        keys = plan.store_service_files("lantern-vc-keys", "/keys/", name="lantern_vc_keys", depends_on=made["output"])
        plan.add_service(
            name="lantern-vc",
            config=ServiceConfig(
                image=lantern_vc_image,
                cmd=vc_cmd(lantern_vc, "http://{0}:5052".format(lantern.ip_address)),
                files={"/network-configs": "el_cl_genesis_data", "/validator-keys": keys},
            ),
        )
    if lantern_assertoor:
        data = {
            "LanternURL": "http://{0}:5052".format(lantern.ip_address),
            "ElURL": out.all_participants[0].el_context.rpc_http_url,
        }
        files = plan.render_templates(
            config={"assertoor.yaml": struct(template=ASSERTOOR_CONFIG, data=data)},
            name="lantern_assertoor_config",
        )
        plan.add_service(
            name="assertoor",
            config=ServiceConfig(
                image=ASSERTOOR_IMAGE,
                cmd=["--config", "/config/assertoor.yaml"],
                files={"/config": files},
                ports={"http": PortSpec(number=8080, application_protocol="http", wait="5m")},
            ),
        )
    return out
