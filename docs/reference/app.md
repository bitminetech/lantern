# Application

## Contents

### Functions

- [`lantern_app_options`](#function-lantern_app_options): reads the command line options.
- [`lantern_app_main`](#function-lantern_app_main): runs the beacon node.

### Types

- [`ArgList`](#type-arglist): the command line arguments.
- [`Arg`](#type-arg): one argument of an `ArgList`.
- [`AppOptions`](#type-appoptions): the options of a run.

## Spec

- Document: ARCHITECTURE.md section 2: the consuming application owns startup and the event loop. Lantern is that application for its own core.
- Section: the binary's startup from a network directory, and its loop over the node core, libp2p, discv5 and the execution engine.

## Common rules

- The application code is core code: the same instructions on every OS of an ISA, `asm/core/<ISA>/app.s`. It makes no OS call itself; it calls the functions of [shell.md](shell.md) and the shell functions of asm-libp2p.

## Test vectors

- tests/generator/app.py: command lines with their `AppOptions`, or the argument index of their fault. File: `<preset>-phase0-app-options.bin`.
- tests/app/start.sh and tests/app/start.ps1 (Windows): the binary of each target given a faulty option exits with 1 and its line; given a network directory with no config.yaml, it exits with 2 and a "cannot read" line. CI runs them.
- tests/app/network.py: a network directory (config.yaml, genesis.ssz) to run the binary with, alone or beside other clients.
- tests/app/trusted_setup.py: writes include/trusted_setup_4096.bin from the pinned spec, or with `--check` exits 1 when the file differs; the interop job of CI runs the check.
- tests/app/devnet.sh: a devnet of ethpandaops/ethereum-package (tests/kurtosis/, at a pinned commit) of geth and one consensus client with all the validators, and the binary's image (platform/docker/Dockerfile) beside it with every consensus client's record as a boot node; lantern's head must reach slot 8, be a block of the client's chain and be within 2 slots of the client's head, at two checks a slot apart.
  - RESTART=1, beside lighthouse, CI's restart job: lantern with `--data-dir`; once its log shows finalized epoch 2 or later, it stops and starts again, must log `restart at slot`, and must follow again.
  - CHECKPOINT=1, beside lighthouse, CI's checkpoint job: lantern starts from lighthouse's finalized block and its post-state, as SSZ from its Beacon API once its finalized epoch is 1 or more, must log `checkpoint at slot`, and must follow.
- tests/app/interop.sh: the ARM64 binary beside another consensus client (lighthouse, prysm, teku, nimbus, lodestar or grandine, each image of tests/app/clients.sh, pinned by digest) on one Docker network, from the genesis of tests/app/network.py; each Beacon API must show the other node as a connected peer, and again two slots later. CI runs it for each client on an ARM64 runner.

## Function `lantern_app_options`

Reads the command line options into an `AppOptions`.

### Signature

```
lantern_app_options(args, options, fault) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `args` | input | [`ArgList`](#type-arglist) |
| `options` | output | [`AppOptions`](#type-appoptions) |
| `fault` | output | u64: the index of the first faulty argument (the one that holds a faulty value), or the argument count when `--network-dir` is missing |

### Returns

- `LANTERN_OK`: `options` holds the options.
- `LANTERN_INVALID_OPTION`: an argument is not an option below, an option has no value or an empty one, a number is not decimal digits of a value in its range, an address is not 4 decimal numbers of 0 to 255 with dots between them, `--network-dir` is missing, or one of `--checkpoint-state` and `--checkpoint-block` is given without the other; a missing option's fault is the count of arguments.

### Function does

- Takes each option as `--name value` or `--name=value`:

| Option | Field | Value | Default |
|---|---|---|---|
| `--network-dir` | `network_dir` | a directory with `config.yaml` and `genesis.ssz` | none: required |
| `--execution-endpoint` | `execution` | `host:port`, with or without `http://` | none: no execution engine |
| `--jwt-secret` | `jwt_secret` | a file of 64 hex digits, with or without `0x` | none |
| `--boot-nodes` | `boot_nodes` | ENRs (`enr:` and base64url), with commas between them | none |
| `--port` | `port` | 1 to 65535: the TCP port of libp2p and the UDP port of discv5 | 9000 |
| `--enr-address` | `enr_address` | an IPv4 address in dotted decimal, for the node record | none |
| `--http-port` | `http_port` | 1 to 65535: the Beacon API | 5052 |
| `--target-peers` | `target_peers` | 1 to 1024 | 64 |
| `--data-dir` | `data_dir` | a directory for the node's history: the segment files of [db.md](db.md) | none: the node keeps its history in memory |
| `--checkpoint-state` | `checkpoint_state` | a file of the SSZ bytes of a finalized `BeaconState`: the post-state of the checkpoint block | none: the node starts from `genesis.ssz` |
| `--checkpoint-block` | `checkpoint_block` | a file of the SSZ bytes of that block's `SignedBeaconBlock` | none |

- Keeps the last value of an option given twice.
- Drops `http://` at the start of `--execution-endpoint`.
- `options` holds the defaults for the options not given; a text field is an `Arg` of the bytes of `args`.

### ABI

- Role: L1.
- Symbol: `lantern_app_options` (`_lantern_app_options` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `args`, `options`, `fault`.

## Function `lantern_app_main`

Runs the beacon node until the process ends.

### Signature

```
lantern_app_main(args) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `args` | input | [`ArgList`](#type-arglist): the program's arguments, without its name |

### Returns

- 1: the options are faulty; a line on the standard error names the argument.
- 2: the start failed: a file is missing or faulty, or the OS gave no memory or no socket; a line on the standard error says which.

### Function does

- Reads the options with lantern_app_options.
- Reads `config.yaml` of the network directory with lantern_config_parse over the pinned config of the preset, and `genesis.ssz` with lantern_<fork>_node_anchor of the fork of its slot.
- Makes a new secp256k1 key. Starts the store (lantern_get_forkchoice_store), the node (lantern_node_init, with `NODE_FLAG_ENGINE` when it has an execution endpoint, `NODE_FLAG_DISCV5`, and the anchor's `node_id`: keccak256 of the key's uncompressed point, x then y, in reverse byte order), the libp2p state with that key, and the discv5 state with the same key, the `ip` of `--enr-address`, and the `udp` and `tcp` of `--port`.
- Decodes the KZG trusted setup with crypto_kzg_trusted_setup_of_bytes: include/trusted_setup_4096.bin, the compressed points of `presets/<preset>/trusted_setups/trusted_setup_4096.json` of the pinned spec (the same file for both presets): the 4096 of `g1_lagrange`, the 4096 of `g1_monomial`, then the 65 of `g2_monomial`.
- Listens on TCP `--port` and binds UDP `--port` on every address, through the shell of asm-libp2p, gives each boot node to discv5, and listens for the Beacon API ([beacon-api.md](beacon-api.md)) on TCP `--http-port`.
- Loops: reads the clock; passes each libp2p shell event, each discv5 record found, each execution engine response and the time to lantern_node_step; performs its actions (on `LANTERN_BUFFER_TOO_SMALL` of lantern_node_step it grows the buffer that `short` names: the node with lantern_node_copy and twice the `NodeRoom` capacity that `room` names, or twice the room of the actions or the scratch; after 64 tries a line `a node step: no room in buffer <short>`); runs each work with lantern_node_run, with the KZG settings, and with more room when it asks; waits for the sockets until the next wakeup, at most 100 ms.
- `NODE_ACT_STATE_COPY` and `NODE_ACT_BYTES_PUT`: new memory from lantern_shell_map with a copy of the bytes. When the source and its size are multiples of 8, a page of 4096 bytes that is all zero is not written, as the new memory is zero already: the OS keeps no memory for it, so a state's free room costs none.
- Writes a line to the standard output at each new head and each new finalized checkpoint, and a line `peers <n>` when the count of connected peers changes.
- With `--data-dir`: makes the directory (one already there will do), and starts the node with `NODE_FLAG_DB` and a `Db` room of `DB_SEGMENT_SLOTS` slots and `APP_DB_ROOTS` (4096) roots; a short room grows as the node's other parts do.
- The segment files of the history: `<dir>/b<n>.seg` for blocks and `<dir>/s<n>.seg` for sidecars, with n the segment's number in decimal.
- `NODE_ACT_DB_APPEND`: one file of each kind stays open. A record of another segment closes it and opens that one with lantern_shell_open to append, cut to the record's offset with lantern_shell_truncate. The record goes in three appends: its `DbRecord`, its bytes, and zero bytes to a multiple of 8. A failure gives a line `cannot write <path>: error <n>` on the standard error, and the file closes, so the next record opens it again.
- A SERVE work whose data is a `NODE_DB_REF`: lantern_node_run gets the record's own ByteList, at its byte 56, in its segment file mapped with lantern_shell_map_file. Up to `APP_DB_MAP_COUNT` (4) files stay mapped, the oldest map going first; a record past a map's end maps its file again. A record not in its file, or whose ByteList header is not of its bytes, is a buffer the work does not name.
- The Beacon API's head header: lantern_node_block_header of the head block's bytes; for a head whose bytes went to the `Db`, of its record there (lantern_db_find_root of its root, then its slot's block record); else the anchor's header.
- `NODE_ACT_DB_STATE`, the first of a run and then each one `DB_SEGMENT_SLOTS` slots or more after the last written: the open segment files are synced; `<dir>/anchor.tmp` gets two ByteLists, the second at the first multiple of 8 after the first: lantern_node_state_bytes of the state, then the block's message, its bytes from 100 of the `SignedBeaconBlock`; it is synced, renamed over `<dir>/anchor.ssz`, and the directory is synced. A failure gives a `cannot write` line.
- A start with `--checkpoint-state` and `--checkpoint-block`, and no `<dir>/anchor.ssz`, takes them in place of `genesis.ssz`: the two files go into one buffer in the form of `anchor.ssz` (the state's bytes, then the block's message from byte 100 of its `SignedBeaconBlock`) for lantern_node_anchor_block of the fork of the state's slot; a block file below 184 bytes gives a line `<path>: too short`. The anchor's `history_slot` is its slot. Then a line `checkpoint at slot <n>` on the standard output.
- A start with `--data-dir` and a `<dir>/anchor.ssz` reads it in place of `genesis.ssz` and of the checkpoint files, with lantern_node_anchor_block of the fork of its state's slot. The first block segment file there, from 0 to the anchor's segment, gives the anchor's `history_slot`; the `Db` has room from it to the last block segment file there from the anchor's on, and a segment more, with a power of two of roots above twice those slots. After lantern_node_init each segment file goes to lantern_node_db_scan, the blocks' then the sidecars', and a file with bytes after its last whole record is cut there. Then a line `restart at slot <n>` on the standard output. The node syncs the blocks after the anchor from its peers; those the `Db` holds already get no second record.
- Writes the size of its scratch buffer into the buffer's first 8 bytes before each call that takes it (ARCHITECTURE.md section 6: a callee may leave scratch invalid, and the caller reinitialises it before reuse).

### ABI

- Role: L2.
- Symbol: `lantern_app_main` (`_lantern_app_main` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `args`.

## Type `ArgList`

The command line arguments, in one buffer.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | Bytes of the buffer |
| 8 | `args` | PartRef | The [`Arg`](#type-arg) entries, one for each argument, in order |
| 24 | `bytes` | PartRef | The bytes of the arguments, in UTF-8 |

### Rules

- Each `Arg` lies inside the `bytes` part.
- The shell's entry point builds it.

## Type `Arg`

One argument, as a place in the bytes of its `ArgList`.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `start` | u64 | Where its bytes start, from the start of the `ArgList` |
| 8 | `length` | u64 | Its byte count, without a terminating zero |

## Type `AppOptions`

The options of a run. A text field is an [`Arg`](#type-arg) of the bytes of the `ArgList`; length 0 means not given.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `network_dir` | `Arg` | The network directory |
| 16 | `execution` | `Arg` | `host:port` of the execution engine, without `http://` |
| 32 | `jwt_secret` | `Arg` | The path of the JWT secret file |
| 48 | `boot_nodes` | `Arg` | The boot node records, with commas between them |
| 64 | `port` | u64 | The libp2p TCP and discv5 UDP port |
| 72 | `enr_address` | u64 | The IPv4 address, its 4 bytes in network order in the low bytes, or 0 |
| 80 | `http_port` | u64 | The Beacon API port |
| 88 | `target_peers` | u64 | The peers to keep |
| 96 | `data_dir` | `Arg` | The directory of the node's history |
| 112 | `checkpoint_state` | `Arg` | The path of the checkpoint state file |
| 128 | `checkpoint_block` | `Arg` | The path of the checkpoint block file |
| 144 | | | Size |

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_app_options`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_app_main`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
