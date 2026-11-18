# A devnet of ethpandaops/ethereum-package from the args (participants, network_params, ...), and
# the lantern binary beside it: the network's config.yaml and genesis.ssz (the files artifact
# el_cl_genesis_data), its own address in its record, and the record of every consensus client as a
# boot node. args.lantern_image: the image of platform/docker/Dockerfile (default lantern:local);
# args.lantern_max_cpu: lantern's CPU limit in millicores (default 0, no limit); args.lantern_delay:
# seconds to wait before lantern starts, so that it syncs a chain that has moved on (default 0);
# args.lantern_data_dir: a directory for lantern's history (--data-dir), or none (default);
# args.lantern_checkpoint: true to start lantern from the finalized block of the first client and
# its post-state (--checkpoint-block, --checkpoint-state), taken from its Beacon API once its
# finalized epoch is 1 or more (default false).
ethereum = import_module("github.com/ethpandaops/ethereum-package/main.star")

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
    network_args = {key: value for key, value in args.items() if key not in ("lantern_image", "lantern_max_cpu", "lantern_delay", "lantern_data_dir", "lantern_checkpoint")}
    out = ethereum.run(plan, network_args)
    if lantern_delay > 0:
        plan.run_sh(run="sleep {0}".format(lantern_delay), wait="{0}s".format(lantern_delay + 60))
    records = [participant.cl_context.enr for participant in out.all_participants]
    extra_args = ["--data-dir", lantern_data_dir] if lantern_data_dir else []
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
    plan.add_service(
        name="lantern",
        config=ServiceConfig(
            image=lantern_image,
            cmd=[
                "--network-dir",
                "/network-configs",
                "--port",
                "9000",
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
    return out
