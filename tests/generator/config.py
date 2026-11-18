"""Cases of lantern_config_parse (docs/reference/config.md).

The pinned configs/mainnet.yaml and configs/minimal.yaml of consensus-specs v1.7.0-beta.4
(aa16bb4), with the values the YAML parser of the generator (ruamel.yaml, safe) reads from
them, and hand cases with their values written out here.

cases(spec) yields (name, parts): "text", the bytes of the file, and "config", the values the
function writes (a map as the YAML parser gives one), or "line", the first faulty line.
"""

from ruamel.yaml import YAML

U64 = (1 << 64) - 1


def entries(pairs):
    return [{"EPOCH": e, "MAX_BLOBS_PER_BLOCK": m} for e, m in pairs]


HAND = [
    ("comments_and_quotes",
     b"# a comment\n---\nSLOT_DURATION_MS: 6000  # six seconds\nALTAIR_FORK_EPOCH: '5'\n"
     b"BELLATRIX_FORK_EPOCH: \"7\"\nCONFIG_NAME: 'my # net'\nGENESIS_FORK_VERSION: 0x10000038 # a version\n"
     b"   \n\t\n#SHARD_COMMITTEE_PERIOD: 9\n",
     None),
    ("crlf",
     b"FULU_FORK_EPOCH: 0\r\nFULU_FORK_VERSION: 0x70000038\r\nMAX_PAYLOAD_SIZE: 0xA00000\r\n",
     {"FULU_FORK_EPOCH": 0, "FULU_FORK_VERSION": bytes.fromhex("70000038"), "MAX_PAYLOAD_SIZE": 0xA00000}),
    ("unknown_keys",
     b"DEPOSIT_CONTRACT_ADDRESS: 0x4242424242424242424242424242424242424242\nGAS_LIMIT_SCHEDULE: []\n"
     b"SOME_MAP:\n  A: 1\n  B:\n    - x\n    - {y: 2}\nCONFIG_NAME: testnet\nGLOAS_FORK_EPOCH: 18446744073709551616\n"
     b"EJECTION_BALANCE: 16000000000\n",
     {"EJECTION_BALANCE": 16000000000}),
    ("blob_schedule_sorted",
     b"BLOB_SCHEDULE:\n  - EPOCH: 20\n    MAX_BLOBS_PER_BLOCK: 21\n  - MAX_BLOBS_PER_BLOCK: 9\n    EPOCH: 5   # first\n"
     b"  -   EPOCH: 12\n        MAX_BLOBS_PER_BLOCK: 15\n  - EPOCH: 12\n    MAX_BLOBS_PER_BLOCK: 16\nDENEB_FORK_EPOCH: 1\n",
     {"BLOB_SCHEDULE": entries([(5, 9), (12, 15), (12, 16), (20, 21)]), "DENEB_FORK_EPOCH": 1}),
    ("blob_schedule_empty", b"BLOB_SCHEDULE: []\n", {"BLOB_SCHEDULE": []}),
    ("blob_schedule_null", b"BLOB_SCHEDULE:\nSLOT_DURATION_MS: 2000\n", {"BLOB_SCHEDULE": [], "SLOT_DURATION_MS": 2000}),
    ("wide_values",
     b"MIN_GENESIS_TIME: 1700000000\n"
     b"TERMINAL_TOTAL_DIFFICULTY: 115792089237316195423570985008687907853269984665640564039457584007913129639935\n"
     b"TERMINAL_BLOCK_HASH: 0x" + b"0123456789abcdef" * 4 + b"\nFULU_FORK_EPOCH: 18446744073709551615\n"
     b"ELECTRA_FORK_EPOCH: 0xffffffffffffffff\n",
     {"MIN_GENESIS_TIME": 1700000000, "TERMINAL_TOTAL_DIFFICULTY": (1 << 256) - 1,
      "TERMINAL_BLOCK_HASH": bytes.fromhex("0123456789abcdef" * 4), "FULU_FORK_EPOCH": U64, "ELECTRA_FORK_EPOCH": U64}),
    ("key_twice", b"SLOT_DURATION_MS: 1\nSLOT_DURATION_MS: 2\n", {"SLOT_DURATION_MS": 2}),
    ("no_line_end", b"SLOT_DURATION_MS: 4000", {"SLOT_DURATION_MS": 4000}),
    ("empty", b"", {}),
]
HAND_VALUES = {"comments_and_quotes": {
    "SLOT_DURATION_MS": 6000, "ALTAIR_FORK_EPOCH": 5, "BELLATRIX_FORK_EPOCH": 7,
    "GENESIS_FORK_VERSION": bytes.fromhex("10000038")}}

SCHEDULE_33 = b"BLOB_SCHEDULE:\n" + b"".join(b"  - EPOCH: %d\n    MAX_BLOBS_PER_BLOCK: 6\n" % i for i in range(33))
FAULTS = [
    ("not_a_number", b"SLOT_DURATION_MS: twelve\n", 1),
    ("hash_after_value", b"EJECTION_BALANCE: 16000000000#5\n", 1),
    ("u64_overflow", b"# x\nFULU_FORK_EPOCH: 18446744073709551616\n", 2),
    ("u64_hex_17_digits", b"SLOT_DURATION_MS: 0x10000000000000000\n", 1),
    ("uint256_overflow",
     b"TERMINAL_TOTAL_DIFFICULTY: 115792089237316195423570985008687907853269984665640564039457584007913129639936\n", 1),
    ("version_3_bytes", b"SLOT_DURATION_MS: 1\nGENESIS_FORK_VERSION: 0x000000\n", 2),
    ("hash_31_bytes", b"TERMINAL_BLOCK_HASH: 0x" + b"00" * 31 + b"\n", 1),
    ("empty_value", b"SLOT_DURATION_MS:\n", 1),
    ("quote_no_end", b"SLOT_DURATION_MS: '12000\n", 1),
    ("quotes_differ", b"SLOT_DURATION_MS: '12000\"\n", 1),
    ("not_a_key", b"SLOT_DURATION_MS: 1\nthis is text\n", 2),
    ("bad_key_byte", b"SLOT-DURATION-MS: 1\n", 1),
    ("tab_indent", b"BLOB_SCHEDULE:\n\t- EPOCH: 1\n", 2),
    ("indented_under_scalar", b"SLOT_DURATION_MS: 1\n  EXTRA: 2\n", 2),
    ("schedule_value", b"BLOB_SCHEDULE: 5\n", 1),
    ("schedule_33", SCHEDULE_33, 66),
    ("schedule_missing_field", b"BLOB_SCHEDULE:\n  - EPOCH: 1\n    MAX_BLOBS_PER_BLOCK: 2\n  - EPOCH: 3\nSLOT_DURATION_MS: 1\n", 4),
    ("schedule_field_twice", b"BLOB_SCHEDULE:\n  - EPOCH: 1\n    EPOCH: 2\n", 3),
    ("schedule_other_key", b"BLOB_SCHEDULE:\n  - EPOCH: 1\n    MAX_BLOBS: 2\n", 3),
    ("schedule_not_entry", b"BLOB_SCHEDULE:\n  EPOCH: 1\n", 2),
    ("schedule_bad_number", b"BLOB_SCHEDULE:\n  - EPOCH: 1\n    MAX_BLOBS_PER_BLOCK: x\n", 3),
]


def cases(spec):
    for preset in ("mainnet", "minimal"):
        text = (spec / "configs" / f"{preset}.yaml").read_bytes()
        yield f"spec_{preset}", {"text": text, "config": dict(YAML(typ="safe").load(text))}
    for name, text, values in HAND:
        yield name, {"text": text, "config": values if values is not None else HAND_VALUES[name]}
    for name, text, line in FAULTS:
        yield name, {"text": text, "line": line}
