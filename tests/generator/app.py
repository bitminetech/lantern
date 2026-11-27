"""Cases of lantern_app_options (docs/reference/app.md).

Hand cases: command lines, with the AppOptions each must give, written out here, or the index of
the first faulty argument.

cases() yields (name, parts): "args", a list of byte strings, and "options", a map of the AppOptions
fields (text fields as byte strings, numbers as integers), or "fault", an index.
"""

import metrics


def ip4(a, b, c, d):
    """An IPv4 address: its 4 bytes in network order in the low bytes of a little endian u64."""
    return int.from_bytes(bytes([a, b, c, d]), "little")


DEFAULTS = {"network_dir": "", "execution": "", "jwt_secret": "", "boot_nodes": "", "port": 9000, "enr_address": 0,
            "http_port": 5052, "target_peers": 64, "data_dir": "", "checkpoint_state": "", "checkpoint_block": "",
            "log_level": 2, "http_address": ip4(127, 0, 0, 1), "http_max_connections": 64,
            "supernode": 0, "builder": "", "archive": 0, "metrics": 1, "metrics_address": ip4(127, 0, 0, 1),
            "metrics_port": 8008, "threads": 4}


def options(**values):
    out = dict(DEFAULTS)
    out.update(values)
    return out


GOOD = [
    ("network_dir_only", ["--network-dir", "/net"], options(network_dir="/net")),
    ("every_option",
     ["--network-dir=/data/net", "--execution-endpoint", "http://el:8551", "--jwt-secret=/data/jwt.hex",
      "--boot-nodes", "enr:-AAA,enr:-BBB", "--port=30303", "--enr-address", "10.0.0.7", "--http-port", "4000",
      "--target-peers=100", "--data-dir", "/data/lantern", "--checkpoint-state", "/cp/state.ssz",
      "--checkpoint-block=/cp/block.ssz", "--log-level", "debug"],
     options(network_dir="/data/net", execution="el:8551", jwt_secret="/data/jwt.hex", boot_nodes="enr:-AAA,enr:-BBB",
             port=30303, enr_address=ip4(10, 0, 0, 7), http_port=4000, target_peers=100, data_dir="/data/lantern",
             checkpoint_state="/cp/state.ssz", checkpoint_block="/cp/block.ssz", log_level=3)),
    ("log_levels", ["--log-level=error", "--network-dir", "n"], options(network_dir="n", log_level=0)),
    ("log_level_warn", ["--network-dir", "n", "--log-level", "warn"], options(network_dir="n", log_level=1)),
    ("log_level_info", ["--log-level", "debug", "--network-dir", "n", "--log-level=info"], options(network_dir="n", log_level=2)),
    ("execution_without_scheme", ["--execution-endpoint=127.0.0.1:8551", "--network-dir", "n"],
     options(network_dir="n", execution="127.0.0.1:8551")),
    ("option_twice", ["--port", "1", "--network-dir", "a", "--port", "65535", "--network-dir", "b"],
     options(network_dir="b", port=65535)),
    ("limits", ["--network-dir", "n", "--target-peers", "1024", "--http-port", "1", "--enr-address", "255.255.255.255"],
     options(network_dir="n", target_peers=1024, http_port=1, enr_address=ip4(255, 255, 255, 255))),
    ("address_zero", ["--network-dir", "n", "--enr-address=0.0.0.0", "--target-peers", "1"],
     options(network_dir="n", target_peers=1)),
    ("http_address_and_connections", ["--http-address", "0.0.0.0", "--network-dir", "n", "--http-max-connections=1"],
     options(network_dir="n", http_address=0, http_max_connections=1)),
    ("http_limits", ["--network-dir", "n", "--http-max-connections", "4096", "--http-address=10.1.2.3"],
     options(network_dir="n", http_max_connections=4096, http_address=ip4(10, 1, 2, 3))),
    ("supernode", ["--network-dir", "n", "--supernode"], options(network_dir="n", supernode=1)),
    ("archive", ["--network-dir", "n", "--archive", "--data-dir", "/d"], options(network_dir="n", data_dir="/d", archive=1)),
    ("supernode_between", ["--supernode", "--port", "7", "--supernode", "--network-dir=n"],
     options(network_dir="n", port=7, supernode=1)),
    ("builder", ["--network-dir", "n", "--builder", "http://127.0.0.1:18550"], options(network_dir="n", builder="127.0.0.1:18550")),
    ("threads", ["--threads", "16", "--network-dir", "n"], options(network_dir="n", threads=16)),
    ("threads_limits", ["--network-dir", "n", "--threads=1", "--threads", "1024"], options(network_dir="n", threads=1024)),
    ("builder_without_scheme", ["--builder=localhost:18550", "--network-dir", "n"], options(network_dir="n", builder="localhost:18550")),
    ("metrics_beacon", ["--network-dir", "n", "--metrics", "beacon"], options(network_dir="n", metrics=1)),
    ("metrics_none", ["--network-dir", "n", "--metrics", ""], options(network_dir="n", metrics=0)),
    ("metrics_none_equals", ["--metrics=", "--network-dir", "n"], options(network_dir="n", metrics=0)),
    ("metrics_name_twice", ["--metrics=beacon,beacon", "--network-dir", "n"], options(network_dir="n", metrics=1)),
    ("metrics_none_then_beacon", ["--metrics", "", "--network-dir", "n", "--metrics", "beacon"], options(network_dir="n", metrics=1)),
    ("metrics_beacon_then_none", ["--metrics=beacon", "--network-dir", "n", "--metrics="], options(network_dir="n", metrics=0)),
    ("metrics_network", ["--network-dir", "n", "--metrics", "network"],
     options(network_dir="n", metrics=metrics.category_mask("network"))),
    ("metrics_subs", ["--metrics=network.peer,processing.availability,node.storage", "--network-dir", "n"],
     options(network_dir="n", metrics=sum(metrics.category_mask(x) for x in
                                          ["network.peer", "processing.availability", "node.storage"]))),
    ("metrics_every_category", ["--network-dir", "n", "--metrics", "beacon,network,processing,node"],
     options(network_dir="n", metrics=sum(metrics.category_mask(x) for x in ["beacon", "network", "processing", "node"]))),
    ("metrics_category_and_its_sub", ["--network-dir", "n", "--metrics", "processing.block,processing"],
     options(network_dir="n", metrics=metrics.category_mask("processing"))),
    ("metrics_address_and_port", ["--network-dir", "n", "--metrics-address", "0.0.0.0", "--metrics-port=9100"],
     options(network_dir="n", metrics_address=0, metrics_port=9100)),
    ("metrics_limits", ["--metrics-port", "65535", "--metrics-address=10.20.30.40", "--network-dir", "n"],
     options(network_dir="n", metrics_port=65535, metrics_address=ip4(10, 20, 30, 40))),
]

FAULTS = [
    ("no_arguments", [], 0),
    ("no_network_dir", ["--port", "1"], 2),
    ("unknown_option", ["--network-dir", "/n", "--foo", "x"], 2),
    ("no_value", ["--network-dir"], 0),
    ("empty_value", ["--network-dir="], 0),
    ("not_an_option", ["--network-dir", "/n", "x"], 2),
    ("port_zero", ["--network-dir", "/n", "--port", "0"], 3),
    ("port_too_big", ["--network-dir", "/n", "--port=65536"], 2),
    ("port_not_digits", ["--port", "12a", "--network-dir", "/n"], 1),
    ("port_u64_overflow", ["--port", "18446744073709551616", "--network-dir", "/n"], 1),
    ("peers_zero", ["--network-dir", "/n", "--target-peers", "0"], 3),
    ("peers_too_many", ["--network-dir", "/n", "--target-peers", "1025"], 3),
    ("threads_zero", ["--network-dir", "/n", "--threads", "0"], 3),
    ("threads_too_many", ["--threads", "1025", "--network-dir", "/n"], 1),
    ("address_three_parts", ["--network-dir", "/n", "--enr-address", "10.0.0"], 3),
    ("address_five_parts", ["--network-dir", "/n", "--enr-address", "1.2.3.4.5"], 3),
    ("address_part_too_big", ["--network-dir", "/n", "--enr-address", "10.0.0.256"], 3),
    ("address_empty_part", ["--network-dir", "/n", "--enr-address", "10..0.1"], 3),
    ("single_dash", ["-network-dir", "/n"], 0),
    ("checkpoint_state_alone", ["--network-dir", "/n", "--checkpoint-state", "s.ssz"], 4),
    ("checkpoint_block_alone", ["--checkpoint-block=b.ssz", "--network-dir", "/n"], 3),
    ("log_level_unknown", ["--network-dir", "/n", "--log-level", "trace"], 3),
    ("log_level_capitals", ["--log-level=INFO", "--network-dir", "/n"], 0),
    ("http_connections_zero", ["--network-dir", "/n", "--http-max-connections", "0"], 3),
    ("http_connections_too_many", ["--network-dir", "/n", "--http-max-connections=4097"], 2),
    ("http_address_three_parts", ["--http-address", "127.0.0", "--network-dir", "/n"], 1),
    ("http_address_part_too_big", ["--network-dir", "/n", "--http-address", "127.0.0.256"], 3),
    ("supernode_value", ["--network-dir", "/n", "--supernode=1"], 2),
    ("supernode_empty_value", ["--supernode=", "--network-dir", "/n"], 0),
    ("builder_empty_value", ["--network-dir", "/n", "--builder="], 2),
    ("builder_no_value", ["--network-dir", "/n", "--builder"], 2),
    ("archive_value", ["--network-dir", "/n", "--data-dir", "/d", "--archive=1"], 4),
    ("archive_no_data_dir", ["--network-dir", "/n", "--archive"], 3),
    ("metrics_unknown_category", ["--network-dir", "/n", "--metrics", "sync"], 3),
    ("metrics_capitals", ["--metrics=Beacon", "--network-dir", "/n"], 0),
    ("metrics_name_prefix", ["--network-dir", "/n", "--metrics", "beaco"], 3),
    ("metrics_name_longer", ["--network-dir", "/n", "--metrics", "beacons"], 3),
    ("metrics_trailing_comma", ["--network-dir", "/n", "--metrics", "beacon,"], 3),
    ("metrics_leading_comma", ["--network-dir", "/n", "--metrics=,beacon"], 2),
    ("metrics_comma_only", ["--metrics", ",", "--network-dir", "/n"], 1),
    ("metrics_no_value", ["--network-dir", "/n", "--metrics"], 2),
    ("metrics_sub_unknown", ["--network-dir", "/n", "--metrics", "network.sync"], 3),
    ("metrics_sub_of_beacon", ["--network-dir", "/n", "--metrics=beacon.head"], 2),
    ("metrics_sub_empty", ["--network-dir", "/n", "--metrics", "network."], 3),
    ("metrics_sub_no_category", ["--metrics", ".peer", "--network-dir", "/n"], 1),
    ("metrics_sub_other_category", ["--network-dir", "/n", "--metrics", "beacon,node.block"], 3),
    ("metrics_sub_two_dots", ["--network-dir", "/n", "--metrics", "network.peer.x"], 3),
    ("metrics_port_zero", ["--network-dir", "/n", "--metrics-port", "0"], 3),
    ("metrics_port_too_big", ["--metrics-port=65536", "--network-dir", "/n"], 0),
    ("metrics_address_three_parts", ["--metrics-address", "1.2.3", "--network-dir", "/n"], 1),
    ("metrics_address_empty", ["--network-dir", "/n", "--metrics-address="], 2),
]


def cases():
    """Strings go as bytes, which the runner reads as byte strings."""
    for name, args, want in GOOD:
        want = {k: v.encode() if isinstance(v, str) else v for k, v in want.items()}
        yield name, {"args": [a.encode() for a in args], "options": want}
    for name, args, fault in FAULTS:
        yield name, {"args": [a.encode() for a in args], "fault": fault}
