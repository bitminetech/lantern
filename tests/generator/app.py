"""Cases of lantern_app_options (docs/reference/app.md).

Hand cases: command lines, with the AppOptions each must give, written out here, or the index of
the first faulty argument.

cases() yields (name, parts): "args", a list of byte strings, and "options", a map of the AppOptions
fields (text fields as byte strings, numbers as integers), or "fault", an index.
"""


def ip4(a, b, c, d):
    """An IPv4 address: its 4 bytes in network order in the low bytes of a little endian u64."""
    return int.from_bytes(bytes([a, b, c, d]), "little")


DEFAULTS = {"network_dir": "", "execution": "", "jwt_secret": "", "boot_nodes": "", "port": 9000, "enr_address": 0,
            "http_port": 5052, "target_peers": 64, "data_dir": ""}


def options(**values):
    out = dict(DEFAULTS)
    out.update(values)
    return out


GOOD = [
    ("network_dir_only", ["--network-dir", "/net"], options(network_dir="/net")),
    ("every_option",
     ["--network-dir=/data/net", "--execution-endpoint", "http://el:8551", "--jwt-secret=/data/jwt.hex",
      "--boot-nodes", "enr:-AAA,enr:-BBB", "--port=30303", "--enr-address", "10.0.0.7", "--http-port", "4000",
      "--target-peers=100", "--data-dir", "/data/lantern"],
     options(network_dir="/data/net", execution="el:8551", jwt_secret="/data/jwt.hex", boot_nodes="enr:-AAA,enr:-BBB",
             port=30303, enr_address=ip4(10, 0, 0, 7), http_port=4000, target_peers=100, data_dir="/data/lantern")),
    ("execution_without_scheme", ["--execution-endpoint=127.0.0.1:8551", "--network-dir", "n"],
     options(network_dir="n", execution="127.0.0.1:8551")),
    ("option_twice", ["--port", "1", "--network-dir", "a", "--port", "65535", "--network-dir", "b"],
     options(network_dir="b", port=65535)),
    ("limits", ["--network-dir", "n", "--target-peers", "1024", "--http-port", "1", "--enr-address", "255.255.255.255"],
     options(network_dir="n", target_peers=1024, http_port=1, enr_address=ip4(255, 255, 255, 255))),
    ("address_zero", ["--network-dir", "n", "--enr-address=0.0.0.0", "--target-peers", "1"],
     options(network_dir="n", target_peers=1)),
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
    ("address_three_parts", ["--network-dir", "/n", "--enr-address", "10.0.0"], 3),
    ("address_five_parts", ["--network-dir", "/n", "--enr-address", "1.2.3.4.5"], 3),
    ("address_part_too_big", ["--network-dir", "/n", "--enr-address", "10.0.0.256"], 3),
    ("address_empty_part", ["--network-dir", "/n", "--enr-address", "10..0.1"], 3),
    ("single_dash", ["-network-dir", "/n"], 0),
]


def cases():
    """Strings go as bytes, which the runner reads as byte strings."""
    for name, args, want in GOOD:
        want = {k: v.encode() if isinstance(v, str) else v for k, v in want.items()}
        yield name, {"args": [a.encode() for a in args], "options": want}
    for name, args, fault in FAULTS:
        yield name, {"args": [a.encode() for a in args], "fault": fault}
