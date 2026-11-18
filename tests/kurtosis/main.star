# A devnet of ethpandaops/ethereum-package from the args (participants, network_params, ...), and
# the lantern binary beside it: the network's config.yaml and genesis.ssz (the files artifact
# el_cl_genesis_data), its own address in its record, and the record of every consensus client as a
# boot node. args.lantern_image: the image of platform/docker/Dockerfile (default lantern:local);
# args.lantern_max_cpu: lantern's CPU limit in millicores (default 0, no limit); args.lantern_delay:
# seconds to wait before lantern starts, so that it syncs a chain that has moved on (default 0);
# args.lantern_data_dir: a directory for lantern's history (--data-dir), or none (default).
ethereum = import_module("github.com/ethpandaops/ethereum-package/main.star")


def run(plan, args={}):
    lantern_image = args.get("lantern_image", "lantern:local")
    lantern_max_cpu = args.get("lantern_max_cpu", 0)
    lantern_delay = args.get("lantern_delay", 0)
    lantern_data_dir = args.get("lantern_data_dir", "")
    network_args = {key: value for key, value in args.items() if key not in ("lantern_image", "lantern_max_cpu", "lantern_delay", "lantern_data_dir")}
    out = ethereum.run(plan, network_args)
    if lantern_delay > 0:
        plan.run_sh(run="sleep {0}".format(lantern_delay), wait="{0}s".format(lantern_delay + 60))
    records = [participant.cl_context.enr for participant in out.all_participants]
    data_dir = ["--data-dir", lantern_data_dir] if lantern_data_dir else []
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
            ] + data_dir,
            files={"/network-configs": "el_cl_genesis_data"},
            max_cpu=lantern_max_cpu,
            ports={
                "http": PortSpec(number=5052, application_protocol="http"),
                "tcp": PortSpec(number=9000, transport_protocol="TCP", wait=None),
                "udp": PortSpec(number=9000, transport_protocol="UDP", wait=None),
            },
        ),
    )
    return out
