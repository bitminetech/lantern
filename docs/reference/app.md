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
- tests/app/start.sh and tests/app/start.ps1 (Windows): the binary of each target given a faulty option exits with 1 and its ERROR line, whose time has the form of the log and today's UTC date; given a network directory with no config.yaml, it exits with 2 and a "cannot read" line. CI runs them.
- tests/app/api.py, run by tests/app/start.sh and start.ps1: the binary started with `--http-max-connections 2` and the network directory that tests/generator/run.sh writes beside the vectors (tests/app/network.py, minimal, altair, 4096 validators at slot 0). On one connection, two getNodeVersion requests in one write and then a getHealth must give three responses, and the connection must stay open; on it then 50 getNodeVersion requests one after another, each sent once the one before is answered, must all be answered within 3 s; a third connection must be closed with no bytes while two are open; a request head of 16385 bytes must give 431 and the connection must close; a `DELETE` must give 405 with `Allow: GET`; getStateV2 of `head` as SSZ, read 16384 bytes at a time with a pause of 20 ms after each so that the shell's send buffer fills, must give the bytes of the directory's genesis.ssz with `Eth-Consensus-Version: altair`; as JSON, over HTTP/1.1 (chunked) and over HTTP/1.0 (closed after the body), a body whose `version` is `altair` and whose `data` has `slot` `"0"`, 4096 validators and the `genesis_validators_root` of genesis.ssz; getSpec must give the directory's config.yaml values of `CONFIG_NAME`, `GENESIS_FORK_VERSION`, `DEPOSIT_CHAIN_ID` and `SLOT_DURATION_MS` / 1000 as `SECONDS_PER_SLOT`, and the preset's `SLOTS_PER_EPOCH`; getForkSchedule phase0 and altair at epoch 0 with the config's versions; getDepositContract the config's `DEPOSIT_CHAIN_ID` and `DEPOSIT_CONTRACT_ADDRESS`; getStateValidators of `head`, chunked, the 4096 validators of genesis.ssz in order, each `active_ongoing` with its `pubkey` and `balance`; postStateValidators of a public key and an index, the two validators in index order; getStateValidator of an index, that validator; getEpochCommittees of `head`, 4 committees for each slot of epoch 0 in order, which hold each of the 4096 validators once; getProposerDuties of epoch 0, the 8 slots of the epoch in order, each with the index of a validator and its `pubkey` in genesis.ssz, and as `dependent_root` the root of getBlockRoot of `genesis`; an event stream of `head`, `block` and `finalized_checkpoint` must give its head, and stay open with no bytes while a connection with no bytes must close within 31 s.
- tests/app/network.py: a network directory (config.yaml, genesis.ssz) to run the binary with, alone or beside other clients.
- tests/app/trusted_setup.py: writes include/trusted_setup_4096.bin from the pinned spec, or with `--check` exits 1 when the file differs; CI's trusted-setup job runs the check.
- tests/app/devnet.sh: a devnet of ethpandaops/ethereum-package (tests/kurtosis/, at a pinned commit) of geth and one consensus client with all the validators, and the binary's image (platform/docker/Dockerfile) beside it with every consensus client's record as a boot node; lantern's head must reach slot 8, be a block of the client's chain and be within 2 slots of the client's head, at two checks a slot apart.
  - RESTART=1, beside lighthouse, CI's restart job: lantern with `--data-dir` and `--archive`; once its log shows finalized epoch 2 or later, it stops and starts again, must log `restart at slot`, and must follow again.
  - FORK=1, beside lighthouse, CI's fork job: electra at genesis and fulu at epoch 1 (no BPO fork), with 6-second slots; lantern's head must reach slot 40, past the fork.
  - ASSERTOOR=1, beside lighthouse, CI's assertoor job: 6-second slots, and Assertoor v0.1.2 (pinned by digest in tests/kurtosis/main.star) with lantern as its one consensus endpoint and the first geth as its execution endpoint. After lantern follows, Assertoor's test `lantern` must end in success within the wait: lantern ready and synced, its identity, then together the chain at epoch 3, two blocks from its event stream, a proposer duty, finality (2 finalized epochs, at most 3 unfinalized), attestation stats from its committees (95% target, 80% head, over 2 epochs), at most 2 reorgs an epoch, and no fork; then together, through lantern's pool POSTs (SHARD_COMMITTEE_PERIOD 1 in this devnet), two voluntary exits, two BLS to execution changes, a proposer slashing and an attester slashing of validators of ethereum-package's default mnemonic, each awaited until a block of the client includes it, and two epochs of attestations of its validators 128 and 129, which the devnet has (preregistered_validator_count 130) and no validator client runs, from their duties and lantern's produceAttestationData through submitPoolAttestationsV2. Those two vote only so, which is why the target floor is 95%.
  - CHECKPOINT=1, beside lighthouse, CI's checkpoint job: lantern, with `--data-dir` and `--archive` (the backfill's blocks go to its `Db`), starts from lighthouse's finalized block and its post-state, as SSZ from its Beacon API once its finalized epoch is 1 or more, must log `checkpoint at slot`, must follow, and its `earliest slot` must fall below the checkpoint's slot: the backfill takes lighthouse's blocks.

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
- `LANTERN_INVALID_OPTION`: an argument is not an option below, an option has no value or an empty one (`--supernode` or `--archive`: a value), a number is not decimal digits of a value in its range, an address is not 4 decimal numbers of 0 to 255 with dots between them, `--network-dir` is missing, one of `--checkpoint-state` and `--checkpoint-block` is given without the other, or `--archive` is given without `--data-dir`; a missing option's fault is the count of arguments.

### Function does

- Takes each option as `--name value` or `--name=value`; `--supernode` and `--archive` as `--name` alone:

| Option | Field | Value | Default |
|---|---|---|---|
| `--network-dir` | `network_dir` | a directory with `config.yaml` and `genesis.ssz` | none: required |
| `--execution-endpoint` | `execution` | `host:port`, with or without `http://` | none: no execution engine |
| `--jwt-secret` | `jwt_secret` | a file of 64 hex digits, with or without `0x` | none |
| `--boot-nodes` | `boot_nodes` | ENRs (`enr:` and base64url), with commas between them | none |
| `--port` | `port` | 1 to 65535: the TCP port of libp2p and the UDP port of discv5 | 9000 |
| `--enr-address` | `enr_address` | an IPv4 address in dotted decimal, for the node record | none |
| `--http-address` | `http_address` | an IPv4 address in dotted decimal: the Beacon API listens on it | 127.0.0.1 |
| `--http-port` | `http_port` | 1 to 65535: the Beacon API | 5052 |
| `--http-max-connections` | `http_max_connections` | 1 to 4096: the Beacon API's connections at a time | 64 |
| `--target-peers` | `target_peers` | 1 to 1024 | 64 |
| `--data-dir` | `data_dir` | a directory for the node's history: the segment files of [db.md](db.md) | none: the node keeps its history in memory |
| `--checkpoint-state` | `checkpoint_state` | a file of the SSZ bytes of a finalized `BeaconState`: the post-state of the checkpoint block | none: the node starts from `genesis.ssz` |
| `--checkpoint-block` | `checkpoint_block` | a file of the SSZ bytes of that block's `SignedBeaconBlock` | none |
| `--log-level` | `log_level` | `error`, `warn`, `info` or `debug`: the log lines of that level and the levels before it | `info` |
| `--supernode` | `supernode` | none: 1, the node custodies every custody group (node.md, `NODE_FLAG_SUPERNODE`) | 0: the groups of max(`SAMPLES_PER_SLOT`, `CUSTODY_REQUIREMENT`) |
| `--builder` | `builder` | `host:port` of a builder (mev-boost), with or without `http://`: the Builder API of builder-specs v0.6.1 | none: no builder |
| `--archive` | `archive` | none: 1, the node keeps a finalized state in its `Db` each `DB_ARCHIVE_DIFF` (256) slots, so any old state is a short replay (node.md, the archive) | 0: no state records |

- Keeps the last value of an option given twice.
- Drops `http://` at the start of `--execution-endpoint` and of `--builder`.
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
- A `StateCache` ([state.md](state.md#type-statecache)) for the anchor file's bytes / 121 + 65536 validators, from lantern_state_cache_size, lantern_shell_map and lantern_state_cache_init, at `CONFIG_STATE_CACHE` of the config before the store and the node start, so each state root of the node goes through it; with no memory for it, none. A `CommitteeCache` ([block-processing.md](block-processing.md#type-committeecache)) for as many validators, from lantern_committee_cache_size, lantern_shell_map and lantern_committee_cache_init, at `CONFIG_COMMITTEE_CACHE` the same way, and a `PubkeyCache` ([block-processing.md](block-processing.md#type-pubkeycache)) for as many, from lantern_pubkey_cache_size and lantern_pubkey_cache_init, at `CONFIG_PUBKEY_CACHE`.
- Makes a new secp256k1 key. Starts the store (lantern_get_forkchoice_store), the node (lantern_node_init, with `NODE_FLAG_ENGINE` and `NODE_FLAG_ETH1` when it has an execution endpoint, `NODE_FLAG_DISCV5`, `NODE_FLAG_FEW_STATES` (a mainnet state is some hundreds of MB, and the blocks past F are some tens), `NODE_FLAG_SUPERNODE` with `--supernode`, `NODE_FLAG_BUILDER` with `--builder` and its text as the anchor's `builder_host`, and the anchor's `node_id`: keccak256 of the key's uncompressed point, x then y, in reverse byte order), the libp2p state with that key, and the discv5 state with the same key, the `ip` of `--enr-address`, and the `udp` and `tcp` of `--port`.
- Decodes the KZG trusted setup with crypto_kzg_trusted_setup_of_bytes: include/trusted_setup_4096.bin, the compressed points of `presets/<preset>/trusted_setups/trusted_setup_4096.json` of the pinned spec (the same file for both presets): the 4096 of `g1_lagrange`, the 4096 of `g1_monomial`, then the 65 of `g2_monomial`.
- Listens on TCP `--port` and binds UDP `--port` on every address, through the shell of asm-libp2p, gives each boot node to discv5, and listens for the Beacon API ([beacon-api.md](beacon-api.md)) on TCP `--http-address` and `--http-port`.
- The Beacon API's connections, through a second shell context of asm-libp2p:
  - A new connection takes a free slot of `--http-max-connections`; with none free, it is refused. The node's `NodeRoom` has `api_streams` `--http-max-connections`, `pool` 4096 (`APP_POOL`): the pool's operations (node.md, `NodePool`), `proposers` 4096 (`APP_PROPOSERS`): the fee recipients of prepareBeaconProposer (node.md, `NodeProposer`), `eth1_blocks` and `eth1_deposits` 4096: the eth1 follower's window and deposits (node.md), and `responses` 16 (`APP_RESPONSES`) of `response_bytes` 13 MiB (`APP_RESPONSE_BYTES`): the replies to the node's own requests, each up to a chunk of `MAX_PAYLOAD_SIZE` (node.md, `NodeResponse`).
  - Its bytes join the slot's buffer of `APP_API_BUFFER` bytes: `APP_API_HEAD_MAX` (16384) + `APP_API_BODY_MAX` (1048576) + `APP_API_HEAD_MAX`.
  - While the slot waits for no answer, lantern_http_request reads the buffer with `head_max` `APP_API_HEAD_MAX` and `body_max` `APP_API_BODY_MAX`. `LANTERN_OK` or `LANTERN_INVALID_HTTP`: a `NODE_EV_API` of the slot's connection and the `HttpRequest`, and the slot waits for the answer. `LANTERN_HTTP_MORE` with a full buffer: a `NODE_EV_API` of an `HttpRequest` with `status` 413. The `used` bytes leave the buffer.
  - `NODE_ACT_API_SEND`: its bytes go to the connection; with `last` 1 the slot waits for no answer, and the buffer is read again. `NODE_ACT_API_CLOSE`: the connection closes once its bytes are sent: at once with no bytes in flight, else at the SENT event that leaves none, since the shell's CLOSE drops the bytes it still holds. An action of a slot's older connection, or of one that closes, is dropped.
  - A slot counts its bytes in flight: those of each `NODE_ACT_API_SEND` it took, less those of each SENT event of the shell. After a `NODE_ACT_API_SEND` with `last` 0, a `NODE_EV_API_SENT` of the connection goes to a later step once its bytes in flight are at most `APP_API_SEND_WINDOW` (131072) - `NODE_API_CHUNK` (65536), at once when they are already; so the shell's send buffer of `APP_API_SEND_WINDOW` bytes never overflows.
  - The shell's CLOSED of a slot's connection: a `NODE_EV_API_CLOSED` of it, and the slot is free.
  - A connection whose slot waits for no answer, with no bytes in 30000 ms (`APP_API_IDLE_MS`), closes; so does one that waits to close with no bytes sent in that time.
  - The connection of a slot is its index + 2^32 times its generation, which grows by 1 with each new connection of the slot.
  - A `NODE_EV_API_IDENTITY` at the start and at each record of discv5: the peer ID in base58btc, `enr:` and the record in base64url, `/ip4/<--enr-address>/tcp/<--port>/p2p/<peer ID>` and the same with `udp` (empty with no `--enr-address`), and the version `lantern/v0.1.0`.
- Loops: reads the clock; passes each libp2p shell event, each discv5 record found, each execution engine response and the time to lantern_node_step; performs its actions (on `LANTERN_BUFFER_TOO_SMALL` of lantern_node_step it grows the buffer that `short` names: the node with lantern_node_copy and twice the `NodeRoom` capacity that `room` names, or twice the room of the actions or the scratch; after 64 tries a line `a node step: no room in buffer <short>`); runs each work with lantern_node_run, with the KZG settings, and with more room when it asks; waits for the sockets of the libp2p context until the next wakeup, at most 100 ms (`APP_WAIT_MS`), and at most 5 ms (`APP_API_WAIT_MS`) while a Beacon API connection is open, since that wait does not see the API's sockets (they are read after it), and not at all while events wait for the next step.
- With `--builder`, each `NODE_ACT_BUILDER` takes a free slot of `APP_BUILDER_SLOTS` (4), as the node makes at most that many calls at a time (node.md, the builder calls): a new connection to the builder's address, through the execution engine's shell context, takes the request's bytes; what it reads joins the slot's buffer of `APP_BUILDER_BUFFER` (1048576) bytes. At the shell's CLOSED of the connection: a `NODE_EV_BUILDER` of the call with the bytes it read, or with the failure bit when it read none, and the slot is free. A full buffer, or `APP_BUILDER_MS` (10000) since the dial, closes the connection.
- `NODE_ACT_STATE_BYTES`: new memory from lantern_shell_map with lantern_node_state_bytes of the fork of the state's slot, kept as `NODE_ACT_BYTES_PUT` keeps bytes; with no memory, a ByteList of no bytes.
- `NODE_ACT_BYTES_JOIN`: new memory from lantern_shell_map with the ByteLists of the ids one after another, each at a multiple of 8, kept as `NODE_ACT_BYTES_PUT` keeps bytes; with no memory, or an id with no bytes, a ByteList of no bytes.
- `NODE_ACT_STATE_COPY` and `NODE_ACT_BYTES_PUT`: new memory from lantern_shell_map with a copy of the bytes. When the source and its size are multiples of 8, a page of 4096 bytes that is all zero is not written, as the new memory is zero already: the OS keeps no memory for it, so a state's free room costs none.
- The BufferId table: an entry of the id, the address and the size of each buffer the node's actions keep (`NODE_ACT_BYTES_PUT`, `NODE_ACT_STATE_COPY`, `NODE_ACT_BYTES_NEW`, `NODE_ACT_BYTES_JOIN`, `NODE_ACT_STATE_BYTES`). It starts with room for `APP_BUFS_CAP` (64) entries; a full table moves to new memory from lantern_shell_map with twice the room, and its old memory goes back to lantern_shell_unmap. With no memory for that, the new buffer is not kept, and a work of its id logs `an action's BufferId`.
- Writes a line `slot <s>, head 0x<the head root's first 8 bytes>, finalized epoch <e>, earliest slot <n>` to the standard output at each new slot of the store, with the node's `earliest_slot` (it falls as the backfill's blocks join the history), and a line `peers <n>` when the count of connected peers changes.
- With `--data-dir`: makes the directory (one already there will do), and starts the node with `NODE_FLAG_DB` and a `Db` room of `DB_SEGMENT_SLOTS` slots and `APP_DB_ROOTS` (4096) roots; a short room grows as the node's other parts do. The anchor's `archive_slots` is `DB_ARCHIVE_DIFF` (256) with `--archive`, else 0.
- The segment files of the history: `<dir>/b<n>.seg` for blocks, `<dir>/s<n>.seg` for sidecars and `<dir>/a<n>.seg` for states, with n the segment's number in decimal.
- `NODE_ACT_DB_APPEND`: one file of each kind stays open. A record of another segment closes it and opens that one with lantern_shell_open to append, cut to the record's offset with lantern_shell_truncate. The record goes in three appends: its `DbRecord`, its bytes, and zero bytes to a multiple of 8. A failure gives a line `cannot write <path>: error <n>` on the standard error, and the file closes, so the next record opens it again.
- A SERVE work whose data is a `NODE_DB_REF`: lantern_node_run gets the record's own ByteList, at its byte 56, in its segment file mapped with lantern_shell_map_file. Up to `APP_DB_MAP_COUNT` (4) files stay mapped, the oldest map going first; a record past a map's end maps its file again. A record not in its file, or whose ByteList header is not of its bytes, is a buffer the work does not name.
- An API_ENCODE or API_CHUNK work whose data is a `NODE_DB_REF` gets the record's ByteList as a SERVE work does. An API_CHUNK work's event has room for `NodeEvent_api_bytes` + 24 + `NODE_API_CHUNK` bytes.
- `NODE_ACT_DB_ARCHIVE`: the state's bytes in new memory from lantern_shell_map with lantern_node_state_bytes of the fork of its slot; above offset 0, the diff of lantern_db_state_diff against the record at offset 0 of the segment's file, mapped as a SERVE's record is, in new memory too. The record goes as a `NODE_ACT_DB_APPEND`'s does, in the state segments' open file, with the `DbRecord`'s ByteList header and `length` of its bytes; the memory is then freed. The node's next step gets a `NODE_EV_DB_ARCHIVE` of the segment, the offset and the `DbRecord`, of kind 0 after a failure, which also gives a `cannot write` line.
- A `NODE_WORK_ARCHIVE_LOAD` gets its `data` and its `state_b`, `NODE_DB_REF`s, as a SERVE work gets its `data`.
- `NODE_ACT_DB_DROP`: the segment's file goes: the open file of its kind closes when it is that segment, a map of it goes, and the file is deleted with lantern_shell_remove.
- `NODE_ACT_DB_STATE`, the first of a run and then each one `DB_SEGMENT_SLOTS` slots or more after the last written: the open segment files are synced; `<dir>/anchor.tmp` gets two ByteLists, the second at the first multiple of 8 after the first: lantern_node_state_bytes of the state, then the block's message, its bytes from 100 of the `SignedBeaconBlock`; it is synced, renamed over `<dir>/anchor.ssz`, and the directory is synced. A failure gives a `cannot write` line.
- Each `NODE_ACT_DB_STATE` whose `custody_count` and `custody_slot` are not those of the anchor or of the last one written: `<dir>/custody.bin` gets them, 16 bytes, synced. A failure gives a `cannot write` line.
- A start with `--checkpoint-state` and `--checkpoint-block`, and no `<dir>/anchor.ssz`, takes them in place of `genesis.ssz`: the two files go into one buffer in the form of `anchor.ssz` (the state's bytes, then the block's message from byte 100 of its `SignedBeaconBlock`) for lantern_node_anchor_block of the fork of the state's slot; a block file below 184 bytes gives a line `<path>: too short`. The anchor's `history_slot` is its slot. Then a line `checkpoint at slot <n>` on the standard output.
- A start with `--data-dir` and a `<dir>/custody.bin` of 16 bytes: the anchor's `custody_count` and `custody_slot` are its two u64.
- A start with `--data-dir` and a `<dir>/anchor.ssz` reads it in place of `genesis.ssz` and of the checkpoint files, with lantern_node_anchor_block of the fork of its state's slot. The first block segment file there, from 0 to the anchor's segment, gives the anchor's `history_slot`; the `Db` has room from it to the last block segment file there from the anchor's on, and a segment more, with a power of two of roots above twice those slots. After lantern_node_init, while the `Db`'s `first_slot` leaves its room short of that end (a start from a checkpoint puts it at the backfill's target, node.md), `db_slots` doubles, then `db_roots` while it is not above twice `db_slots`, as a short room grows. Then each segment file goes to lantern_node_db_scan, the blocks', then the sidecars', then the states', and a file with bytes after its last whole record is cut there. Then a line `restart at slot <n>` on the standard output. The node syncs the blocks after the anchor from its peers; those the `Db` holds already get no second record.
- The log: each line is the UTC time of lantern_shell_time_ms as `YYYY-MM-DD HH:MM:SS.mmm`, a space, its level in 5 characters (`ERROR`, `WARN `, `INFO ` or `DEBUG`), a space, the message and an LF. A line goes out when its level is at most `log_level`, in the order error, warn, info, debug: ERROR and WARN lines to the standard error, INFO and DEBUG lines to the standard output.
  - ERROR: the lines of a faulty option or a failed start, `cannot write`, and `a node step: no room`.
  - WARN: `block <slot> not imported: result <n>` for a `NODE_WORK_IMPORT_BLOCK` whose result is neither `LANTERN_VALID` nor `LANTERN_NEED_JUSTIFIED_STATE`.
  - INFO: the lines of the start, `checkpoint at slot`, `restart at slot`, the slot line and the `peers` line; and `block <slot> imported, <a> attestations` for a `NODE_WORK_IMPORT_BLOCK` with `LANTERN_VALID`, with the count of the event.
  - DEBUG: `work <kind> result <n>` for each work that lantern_node_run ran, with its `NODE_WORK_*` kind and result.
- Writes the size of its scratch buffer into the buffer's first 8 bytes before each call that takes it (ARCHITECTURE.md section 6: a callee may leave scratch invalid, and the caller reinitialises it before reuse).

### ABI

- Role: L2.
- Symbol: `lantern_app_main` (`_lantern_app_main` on macOS); in the binary's `sha` copy on x86-64 and ARM64, `lx_lantern_app_main` (README, Target profile).
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
| 144 | `log_level` | u64 | 0 error, 1 warn, 2 info, 3 debug |
| 152 | `http_address` | u64 | The Beacon API's IPv4 address, its 4 bytes in network order in the low bytes |
| 160 | `http_max_connections` | u64 | The Beacon API's connections at a time |
| 168 | `supernode` | u64 | 1 with `--supernode`, else 0 |
| 176 | `builder` | `Arg` | `host:port` of the builder, without `http://` |
| 192 | `archive` | u64 | 1 with `--archive`, else 0 |
| 200 | | | Size |

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
