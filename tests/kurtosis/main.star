# A devnet of ethpandaops/ethereum-package from the args (participants, network_params, ...), and
# the lantern binary beside it: the network's config.yaml and genesis.ssz (the files artifact
# el_cl_genesis_data), its own address in its record, and the record of every consensus client as a
# boot node. args.lantern_image: the image of platform/docker/Dockerfile (default lantern:local).
ethereum = import_module("github.com/ethpandaops/ethereum-package/main.star")


def run(plan, args={}):
    lantern_image = args.get("lantern_image", "lantern:local")
    network_args = {key: value for key, value in args.items() if key != "lantern_image"}
    out = ethereum.run(plan, network_args)
    records = [participant.cl_context.enr for participant in out.all_participants]
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
            ],
            files={"/network-configs": "el_cl_genesis_data"},
            ports={
                "http": PortSpec(number=5052, application_protocol="http"),
                "tcp": PortSpec(number=9000, transport_protocol="TCP", wait=None),
                "udp": PortSpec(number=9000, transport_protocol="UDP", wait=None),
            },
        ),
    )
    return out
