# Application

The binary: options, startup and the loop.

## Contents

### Functions

- [`lantern_app_options`](#function-lantern_app_options): reads the command line options.
- [`lantern_app_main`](#function-lantern_app_main): runs the beacon node.
- [`lantern_app_actions`](#function-lantern_app_actions): does the actions of a node step, in order.
- [`lantern_app_alloc`](#function-lantern_app_alloc): makes new memory for a pair of the App.
- [`lantern_app_api_action`](#function-lantern_app_api_action): does a node's NODE_ACT_API_SEND or NODE_ACT_API_CLOSE.
- [`lantern_app_api_close`](#function-lantern_app_api_close): closes a Beacon API connection.
- [`lantern_app_api_due`](#function-lantern_app_api_due): owes the node an API_SENT of a connection once its bytes in flight are few.
- [`lantern_app_api_flush`](#function-lantern_app_api_flush): sends the Beacon API's shell actions.
- [`lantern_app_api_note`](#function-lantern_app_api_note): queues a NODE_EV_API_SENT or NODE_EV_API_CLOSED for the next step.
- [`lantern_app_api_poll`](#function-lantern_app_api_poll): handles the Beacon API's sockets without waiting.
- [`lantern_app_api_read`](#function-lantern_app_api_read): reads the next request of a Beacon API slot.
- [`lantern_app_api_room`](#function-lantern_app_api_room): room for a shell action at the end of the Beacon API's actions.
- [`lantern_app_api_slot`](#function-lantern_app_api_slot): the slot of a Beacon API connection.
- [`lantern_app_api_start`](#function-lantern_app_api_start): starts the Beacon API and the node's identity texts.
- [`lantern_app_arg_path`](#function-lantern_app_arg_path): holds the path of an argument in APP_PATH.
- [`lantern_app_base58`](#function-lantern_app_base58): the base58btc text of bytes.
- [`lantern_app_base64url`](#function-lantern_app_base64url): decodes a base64url text.
- [`lantern_app_boot_nodes`](#function-lantern_app_boot_nodes): gives the node the records of --boot-nodes.
- [`lantern_app_buf_add`](#function-lantern_app_buf_add): adds a BufferId table entry.
- [`lantern_app_buf_drop`](#function-lantern_app_buf_drop): gives the buffer of an id back to the OS.
- [`lantern_app_buf_find`](#function-lantern_app_buf_find): the BufferId table entry of an id.
- [`lantern_app_buf_grow`](#function-lantern_app_buf_grow): doubles the room of the BufferId table.
- [`lantern_app_builder_answer`](#function-lantern_app_builder_answer): queues the NODE_EV_BUILDER of a builder slot's call.
- [`lantern_app_builder_conf`](#function-lantern_app_builder_conf): sets up the builder of --builder.
- [`lantern_app_builder_due`](#function-lantern_app_builder_due): moves the builder calls on after the shell's events.
- [`lantern_app_builder_event`](#function-lantern_app_builder_event): takes a shell event of a builder slot's connection.
- [`lantern_app_builder_fail`](#function-lantern_app_builder_fail): queues the NODE_EV_BUILDER of a failed builder call.
- [`lantern_app_builder_handle`](#function-lantern_app_builder_handle): the Handle of a builder slot's connection.
- [`lantern_app_builder_request`](#function-lantern_app_builder_request): starts a NODE_ACT_BUILDER call.
- [`lantern_app_bytes_join`](#function-lantern_app_bytes_join): does a NODE_ACT_BYTES_JOIN.
- [`lantern_app_categories`](#function-lantern_app_categories): reads the metrics categories of --metrics.
- [`lantern_app_checkpoint`](#function-lantern_app_checkpoint): reads the anchor of --checkpoint-state and --checkpoint-block.
- [`lantern_app_db_append`](#function-lantern_app_db_append): does a NODE_ACT_DB_APPEND.
- [`lantern_app_db_archive`](#function-lantern_app_db_archive): does a NODE_ACT_DB_ARCHIVE.
- [`lantern_app_db_custody`](#function-lantern_app_db_custody): writes custody.bin when the custody of a NODE_ACT_DB_STATE changes.
- [`lantern_app_db_drop`](#function-lantern_app_db_drop): does a NODE_ACT_DB_DROP.
- [`lantern_app_db_exists`](#function-lantern_app_db_exists): whether a block segment's file is there.
- [`lantern_app_db_file`](#function-lantern_app_db_file): a path in the data directory.
- [`lantern_app_db_fit`](#function-lantern_app_db_fit): grows the Db room to cover the history of a start from anchor.ssz.
- [`lantern_app_db_history`](#function-lantern_app_db_history): finds the history of a start from anchor.ssz.
- [`lantern_app_db_path`](#function-lantern_app_db_path): the path of a segment file in the data directory.
- [`lantern_app_db_record`](#function-lantern_app_db_record): the view entry of a record of a mapped segment.
- [`lantern_app_db_scan_all`](#function-lantern_app_db_scan_all): scans the segment files there for a start from anchor.ssz.
- [`lantern_app_db_start`](#function-lantern_app_db_start): sets up the history's files.
- [`lantern_app_db_state`](#function-lantern_app_db_state): writes anchor.ssz from a NODE_ACT_DB_STATE.
- [`lantern_app_db_write`](#function-lantern_app_db_write): writes the record of a NODE_ACT_DB_APPEND at the end of its segment file.
- [`lantern_app_decimal`](#function-lantern_app_decimal): reads a decimal number of an option.
- [`lantern_app_digits`](#function-lantern_app_digits): writes a number's decimal digits before a byte.
- [`lantern_app_discv5`](#function-lantern_app_discv5): runs a discv5 step and its actions.
- [`lantern_app_dotted`](#function-lantern_app_dotted): reads a dotted IPv4 address of an endpoint.
- [`lantern_app_dup`](#function-lantern_app_dup): copies bytes into new memory.
- [`lantern_app_dv_datagram`](#function-lantern_app_dv_datagram): takes a shell DATAGRAM of discv5's socket.
- [`lantern_app_dv_put`](#function-lantern_app_dv_put): queues an event for the next discv5 step.
- [`lantern_app_dv_start`](#function-lantern_app_dv_start): starts discv5 with the key of libp2p.
- [`lantern_app_engine_conf`](#function-lantern_app_engine_conf): sets up the execution engine of --execution-endpoint.
- [`lantern_app_engine_event`](#function-lantern_app_engine_event): takes a shell event of the engine's connection.
- [`lantern_app_engine_handle`](#function-lantern_app_engine_handle): the Handle of the engine's connection.
- [`lantern_app_engine_perform`](#function-lantern_app_engine_perform): does one shell action of the engine or the builder.
- [`lantern_app_engine_request`](#function-lantern_app_engine_request): does a NODE_ACT_ENGINE.
- [`lantern_app_engine_send`](#function-lantern_app_engine_send): sends the next bytes of the engine request.
- [`lantern_app_event_put`](#function-lantern_app_event_put): queues an event for the next node step.
- [`lantern_app_fail_status`](#function-lantern_app_fail_status): writes a failure line and gives 2.
- [`lantern_app_file_free`](#function-lantern_app_file_free): gives the memory of APP_FILE back.
- [`lantern_app_fork`](#function-lantern_app_fork): the fork of a slot.
- [`lantern_app_grow`](#function-lantern_app_grow): moves the node, the store or the Seen to new memory with more room.
- [`lantern_app_hex_digit`](#function-lantern_app_hex_digit): the value of a hex digit.
- [`lantern_app_hist_chunk`](#function-lantern_app_hist_chunk): the history's chunk of a kind for an epoch.
- [`lantern_app_hist_fail`](#function-lantern_app_hist_fail): writes a line that seen-history.bin cannot be written.
- [`lantern_app_hist_grow`](#function-lantern_app_hist_grow): doubles the room of the chunks' ByteList.
- [`lantern_app_hist_header`](#function-lantern_app_hist_header): the fixed fields of a new history.
- [`lantern_app_hist_map`](#function-lantern_app_hist_map): maps seen-history.bin again.
- [`lantern_app_hist_path`](#function-lantern_app_hist_path): the path of seen-history.bin.
- [`lantern_app_hist_put`](#function-lantern_app_hist_put): writes bytes at an offset of the history.
- [`lantern_app_hist_start`](#function-lantern_app_hist_start): sets up the Seen's history.
- [`lantern_app_hist_step`](#function-lantern_app_hist_step): moves the Seen's entries of past epochs to its history.
- [`lantern_app_hist_sync`](#function-lantern_app_hist_sync): makes the history's bytes durable.
- [`lantern_app_identity_put`](#function-lantern_app_identity_put): queues the identity's texts for the next node step.
- [`lantern_app_ipv4`](#function-lantern_app_ipv4): reads an IPv4 address of an option.
- [`lantern_app_key`](#function-lantern_app_key): makes the node's secp256k1 key.
- [`lantern_app_key_job`](#function-lantern_app_key_job): a job of lantern_app_pool: the keys of a range of validators checked.
- [`lantern_app_lc_grow`](#function-lantern_app_lc_grow): moves a light client store to a new buffer with twice the capacities.
- [`lantern_app_no_memory`](#function-lantern_app_no_memory): writes the no memory line and gives 2.
- [`lantern_app_lc_start`](#function-lantern_app_lc_start): makes the light client store as BufferId 2.
- [`lantern_app_line_base64url`](#function-lantern_app_line_base64url): adds base64url text to the log line.
- [`lantern_app_line_clear`](#function-lantern_app_line_clear): empties the log line.
- [`lantern_app_line_end`](#function-lantern_app_line_end): writes the log line.
- [`lantern_app_line_hex`](#function-lantern_app_line_hex): adds hex digits to the log line.
- [`lantern_app_line_ip4`](#function-lantern_app_line_ip4): adds an IPv4 address to the log line.
- [`lantern_app_line_path`](#function-lantern_app_line_path): adds the path of APP_PATH to the log line.
- [`lantern_app_line_start`](#function-lantern_app_line_start): starts the log line.
- [`lantern_app_line_text`](#function-lantern_app_line_text): adds bytes to the log line.
- [`lantern_app_line_to`](#function-lantern_app_line_to): copies the log line into a text field of the identity's view.
- [`lantern_app_line_u64`](#function-lantern_app_line_u64): adds a decimal number to the log line.
- [`lantern_app_log_work`](#function-lantern_app_log_work): writes the log lines of a work that ran.
- [`lantern_app_loop`](#function-lantern_app_loop): the loop of the binary.
- [`lantern_app_map`](#function-lantern_app_map): new zeroed memory from the OS.
- [`lantern_app_met_answer`](#function-lantern_app_met_answer): answers a metrics request.
- [`lantern_app_met_close`](#function-lantern_app_met_close): closes a metrics connection.
- [`lantern_app_met_delay`](#function-lantern_app_met_delay): records the delay of a message.
- [`lantern_app_met_flush`](#function-lantern_app_met_flush): sends the metrics server's shell actions.
- [`lantern_app_met_obs`](#function-lantern_app_met_obs): records a value in an AppMetrics Histogram.
- [`lantern_app_met_poll`](#function-lantern_app_met_poll): handles the metrics server's sockets without waiting.
- [`lantern_app_met_room`](#function-lantern_app_met_room): room for a shell action at the end of the metrics server's actions.
- [`lantern_app_met_send`](#function-lantern_app_met_send): sends more of a metrics answer.
- [`lantern_app_met_slot`](#function-lantern_app_met_slot): the slot of a metrics connection.
- [`lantern_app_met_sources`](#function-lantern_app_met_sources): gathers the sources of the metrics.
- [`lantern_app_met_start`](#function-lantern_app_met_start): starts the metrics server.
- [`lantern_app_met_us`](#function-lantern_app_met_us): the monotonic microseconds.
- [`lantern_app_met_work`](#function-lantern_app_met_work): records the metrics of a work that ran.
- [`lantern_app_multiaddr`](#function-lantern_app_multiaddr): writes a multiaddr of the node into a field of the identity's view.
- [`lantern_app_name_is`](#function-lantern_app_name_is): whether two byte strings are equal.
- [`lantern_app_net`](#function-lantern_app_net): starts the node's network.
- [`lantern_app_number`](#function-lantern_app_number): reads a decimal number of an endpoint.
- [`lantern_app_p2p_events`](#function-lantern_app_p2p_events): passes the shell's events on.
- [`lantern_app_path`](#function-lantern_app_path): a path in the network directory.
- [`lantern_app_pool`](#function-lantern_app_pool): starts the pool of `--threads`, gives it to the StateCache, and checks the anchor state's keys on it.
- [`lantern_app_read`](#function-lantern_app_read): reads the file at APP_PATH into APP_FILE.
- [`lantern_app_regrow`](#function-lantern_app_regrow): moves a state to new memory with twice the StateRoom.
- [`lantern_app_sig_job`](#function-lantern_app_sig_job): a job of lantern_app_sigs: the signature checks of its share of the SigTable.
- [`lantern_app_sigs`](#function-lantern_app_sigs): checks the gossip attestation signatures of a step at once on the pool.
- [`lantern_app_space`](#function-lantern_app_space): skips white space of a text.
- [`lantern_app_start`](#function-lantern_app_start): the start of the binary.
- [`lantern_app_state_bytes`](#function-lantern_app_state_bytes): does a NODE_ACT_STATE_BYTES.
- [`lantern_app_state_cache`](#function-lantern_app_state_cache): makes the state caches of the app's config.
- [`lantern_app_step`](#function-lantern_app_step): runs lantern_node_step and the actions it gives.
- [`lantern_app_store_slot`](#function-lantern_app_store_slot): the current slot of the store.
- [`lantern_app_time_text`](#function-lantern_app_time_text): writes a time as UTC text.
- [`lantern_app_unmap`](#function-lantern_app_unmap): gives a pair of the App back to the OS.
- [`lantern_app_work`](#function-lantern_app_work): does a WORK action.
- [`lantern_app_work_data`](#function-lantern_app_work_data): the table entry of a work's data.
- [`lantern_app_work_entry`](#function-lantern_app_work_entry): the table entry of a BufferId.

### Types

- [`ArgList`](#type-arglist): the command line arguments.
- [`Arg`](#type-arg): one argument of an `ArgList`.
- [`AppOptions`](#type-appoptions): the options of a run.

## Spec

- Document: ARCHITECTURE.md section 2: the consuming application owns startup and the event loop. Lantern is that application for its own core.
- Section: the binary's startup from a network directory, and its loop over the node core, libp2p, discv5 and the execution engine.

- Use: the application code is core code: the same instructions on every OS of an ISA, `asm/core/<ISA>/app.s`. It calls the functions of [shell.md](shell.md) and the shell functions of asm-libp2p.
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
- `LANTERN_INVALID_OPTION`: an argument is not an option below, an option has no value or an empty one (`--supernode` or `--archive`: a value; `--metrics` may have an empty value), a number is not decimal digits of a value in its range, an address is not 4 decimal numbers of 0 to 255 with dots between them, a `--metrics` value is not names of categories or sub categories with commas between them, `--network-dir` is missing, one of `--checkpoint-state` and `--checkpoint-block` is given without the other, or `--archive` is given without `--data-dir`; a missing option's fault is the count of arguments.

### Function does

- Takes each option as `--name value` or `--name=value`; `--supernode` and `--archive` as `--name` alone.
- `--network-dir` sets `network_dir`: a directory with `config.yaml` and `genesis.ssz`. Without it: required.
- `--execution-endpoint` sets `execution`: `host:port`, with or without `http://`. Without it: no execution engine.
- `--jwt-secret` sets `jwt_secret`: a file of 64 hex digits, with or without `0x`.
- `--boot-nodes` sets `boot_nodes`: ENRs (`enr:` and base64url), with commas between them.
- `--port` sets `port`: 1 to 65535: the TCP port of libp2p and the UDP port of discv5. Default: 9000.
- `--enr-address` sets `enr_address`: an IPv4 address in dotted decimal, for the node record.
- `--http-address` sets `http_address`: an IPv4 address in dotted decimal: the Beacon API listens on it. Default: 127.0.0.1.
- `--http-port` sets `http_port`: 1 to 65535: the Beacon API. Default: 5052.
- `--http-max-connections` sets `http_max_connections`: 1 to 4096: the Beacon API's connections at a time. Default: 64.
- `--target-peers` sets `target_peers`: 1 to 1024. Default: 64.
- `--threads` sets `threads`: 1 to 1024, the threads of lantern, its loop's included; above `SHELL_POOL_MAX` (64) the pool takes 64. Default: 4.
- `--data-dir` sets `data_dir`: a directory for the node's history: the segment files of [db.md](db.md). Without it: the node keeps its history in memory.
- `--checkpoint-state` sets `checkpoint_state`: a file of the SSZ bytes of a finalized `BeaconState`: the post-state of the checkpoint block. Without it: the node starts from `genesis.ssz`.
- `--checkpoint-block` sets `checkpoint_block`: a file of the SSZ bytes of that block's `SignedBeaconBlock`.
- `--log-level` sets `log_level`: `error`, `warn`, `info` or `debug`: the log lines of that level and the levels before it. Default: `info`.
- `--supernode`, alone, sets `supernode` to 1: the node custodies every custody group (node.md, `NODE_FLAG_SUPERNODE`). Default: 0: the groups of max(`SAMPLES_PER_SLOT`, `CUSTODY_REQUIREMENT`).
- `--builder` sets `builder`: `host:port` of a builder (mev-boost), with or without `http://`: the Builder API of builder-specs v0.6.1. Without it: no builder.
- `--archive`, alone, sets `archive` to 1: the node keeps a finalized state in its `Db` each `DB_ARCHIVE_DIFF` (256) slots, so any old state is a short replay (node.md, the archive). Default: 0: no state records.
- `--metrics` sets `metrics`: the metrics the metrics server serves, with commas between them: each a category, with all its sub categories, or `<category>.<sub>` ([metrics.md](metrics.md#type-metricentry)); an empty value: none, and no metrics server. Default: `beacon`.
- `--metrics-address` sets `metrics_address`: an IPv4 address in dotted decimal: the metrics server listens on it. Default: 127.0.0.1.
- `--metrics-port` sets `metrics_port`: 1 to 65535: the metrics server. Default: 8008.
- Keeps the last value of an option given twice.
- Drops `http://` at the start of `--execution-endpoint` and of `--builder`.
- Takes each `--metrics` name only in lowercase; a name given twice, or a sub category of a category also given, adds no more bits.
- `options` holds the defaults for the options not given; a text field is an `Arg` of the bytes of `args`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_options`, with `_` before it on macOS.
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
- A `StateCache` ([state.md](state.md#type-statecache)) for the anchor file's bytes / 121 + 65536 validators, from lantern_state_cache_size, lantern_shell_map and lantern_state_cache_init, at `CONFIG_STATE_CACHE` of the config before the store and the node start, so each state root of the node goes through it; with no memory for it, none. A `CommitteeCache` ([block-processing.md](block-processing.md#type-committeecache)) for as many validators, from lantern_committee_cache_size, lantern_shell_map and lantern_committee_cache_init, at `CONFIG_COMMITTEE_CACHE` the same way, and a `PubkeyCache` ([block-processing.md](block-processing.md#type-pubkeycache)) for as many, from lantern_pubkey_cache_size and lantern_pubkey_cache_init, at `CONFIG_PUBKEY_CACHE`. Then the pool of `--threads` (lantern_app_pool): its workers, the `StateCache`'s `pool`, and the anchor state's keys checked into the `PubkeyCache` with jobs on it.
- Makes a new secp256k1 key. Starts the store (lantern_get_forkchoice_store), the node (lantern_node_init, with `NODE_FLAG_ENGINE` and `NODE_FLAG_ETH1` when it has an execution endpoint, `NODE_FLAG_DISCV5`, `NODE_FLAG_FEW_STATES` (a mainnet state is some hundreds of MB, and the blocks past F are some tens), `NODE_FLAG_SUPERNODE` with `--supernode`, `NODE_FLAG_BUILDER` with `--builder` and its text as the anchor's `builder_host`, and the anchor's `node_id`: keccak256 of the key's uncompressed point, x then y, in reverse byte order), the libp2p state with that key, and the discv5 state with the same key, the `ip` of `--enr-address`, and the `udp` and `tcp` of `--port`.
- Decodes the KZG trusted setup with crypto_kzg_trusted_setup_of_bytes: include/trusted_setup_4096.bin, the compressed points of `presets/<preset>/trusted_setups/trusted_setup_4096.json` of the pinned spec (the same file for both presets): the 4096 of `g1_lagrange`, the 4096 of `g1_monomial`, then the 65 of `g2_monomial`.
- Listens on TCP `--port` and binds UDP `--port` on every address, through the shell of asm-libp2p, gives each boot node to discv5, and listens for the Beacon API ([beacon-api.md](beacon-api.md)) on TCP `--http-address` and `--http-port`.
- A discv5 step when it has events or its WAKEUP is due (asm-discv5 node.md, discv5_step): with the datagrams of the UDP socket and the records to add as its events, a scratch of `DISCV5_SCRATCH_SIZE` bytes, and an `ActionList` whose room, its size less its 24 header bytes (`DISCV5_BL_FIXED`), is at least `DISCV5_ACTIONS_BASE` + events × `DISCV5_ACTIONS_PER_EVENT`: at the start for 64 events, and new memory from lantern_shell_map for more. A status other than `DISCV5_OK` gives a line `discv5: status <n>`, and the step's events are dropped.
- The case it fixes (lantern on Hoodi and mainnet, 2026-11-24): the room was counted with the header, 24 bytes short, so each step of 64 events or more gave `DISCV5_BUFFER_TOO_SMALL` and lost its datagrams; 64 or more queue up while the node loads its anchor.
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
- With `--metrics` categories, the metrics server ([metrics.md](metrics.md)), through a third shell context of asm-libp2p:
  - It listens on TCP `--metrics-address` and `--metrics-port`, with `APP_MET_CONNS` (4) connections at a time, each with a send buffer of `APP_MET_WINDOW` (1 MiB); a new connection with no free slot is refused. A line `metrics on TCP <address>:<port>`; a failed listen gives `listen on TCP port <p>: error <n>` and status 2.
  - A connection's first `METRICS_HEAD_MAX` bytes go to lantern_metrics_answer, with the bits of `--metrics` and these sources: lantern_metrics_node of the node and the store; the head's `MetricsState` from lantern_<fork>_metrics_state of the fork of its state's slot, with the head block's bytes (a ByteList of no bytes when the app does not hold them), made again only when the head's `state_id` changes; the node's `NodeMetrics`; the app's `AppMetrics`.
  - `LANTERN_HTTP_MORE` waits for more bytes. `LANTERN_BUFFER_TOO_SMALL` doubles the answer's memory (`APP_MET_OUT`, 1 MiB, at first; the slot keeps it for its next connection), at most `APP_MET_TRIES` (8) times, after which the connection closes.
  - The answer goes in SENDs of at most `APP_MET_PIECE` (65536) bytes while the bytes in flight stay within `APP_MET_WINDOW`; once the last bytes are out and none is in flight, the connection closes.
  - A connection with no bytes in or out for `APP_API_IDLE_MS` closes.
- With an empty `--metrics`: no metrics server, and no socket for it.
- The metrics the app keeps (metrics.md, `AppMetrics`), whatever `--metrics` is:
  - Each work: its run time, from the clock of libp2p_shell_clock in microseconds, from before its first lantern_node_run to its WORK_DONE event, in the `work_seconds` Histogram of its kind's slot; a result other than `LANTERN_OK` adds 1 to `work_failures` of the slot. The slot of each kind is `METRIC_WORK_SLOTS` (include/metrics.inc), the kinds of each processing sub category together.
  - A GOSSIP work: by the topic of `arg` & 255 (13 or less, else 0) and its result (`LANTERN_VALID` accept, `LANTERN_GOSSIP_REJECT` reject, else ignore); its run time by topic; the counts and delays of the `beacon` category (the slot of an attestation at `NodeEvent_root`, of a block at bytes 100 to 108 of its `SignedBeaconBlock`).
  - A SERVE work: by the method of (`arg` / 256) & 255 (15 or less, else 0). A SLOTS work whose `arg`, or an IMPORT_BLOCK work whose block's slot (bytes 100 to 108 of its `SignedBeaconBlock`), is in a later epoch than the slot of its `state_a` before the run: an epoch transition and its run time (the import runs process_slots, so the epoch transition, inside it).
  - Each lantern_node_step: its run time.
  - The events of the libp2p shell that go to the node: RECEIVED and SENT add their bytes; ACCEPTED, CONNECTED, DIAL_FAILED and CLOSED add 1. Each datagram of discv5, each SEND of discv5, each NODE_FOUND and each discv5 status line add 1, as does each `NODE_ACT_DISCV5`.
  - Each log line written adds 1 by its level: error, warn, info, debug. Each `NODE_EV_API` adds 1; the first SEND of each answer adds 1 by the first digit of its status (2 to 5), and a 2xx to the successes.
  - Each `NODE_ACT_DB_APPEND` adds 1 and its buffer's bytes by kind (sidecar when its `sidecars` field is 1); `NODE_ACT_DB_ARCHIVE` 1 of kind state; `NODE_ACT_DB_DROP` 1; each `anchor.ssz` written 1, with its run time from before lantern_node_state_bytes to the synced directory; each `cannot write` line of the history 1.
- At each answer of the metrics server, `MetricsProcess`: lantern_shell_process ([shell.md](shell.md)), the BufferId table's entries and their bytes, the start's Unix time and the microseconds since it, the execution engine's connection state, and the Beacon API's slots in use.
- Loops: reads the clock; passes each libp2p shell event, each discv5 record found, each execution engine response and the time to lantern_node_step; performs its actions (on `LANTERN_BUFFER_TOO_SMALL` of lantern_node_step it grows the buffer that `short` names: the node with lantern_node_copy and twice the `NodeRoom` capacity that `room` names, or twice the room of the actions or the scratch; after 64 tries a line `a node step: no room in buffer <short>`); runs each work with lantern_node_run, with the KZG settings, and with more room when it asks; waits for the sockets of the libp2p context until the next wakeup, at most 100 ms (`APP_WAIT_MS`), and at most 5 ms (`APP_API_WAIT_MS`) while a Beacon API or metrics connection is open, since that wait does not see their sockets (they are read after it), and not at all while events wait for the next step.
- With `--builder`, each `NODE_ACT_BUILDER` takes a free slot of `APP_BUILDER_SLOTS` (4), as the node makes at most that many calls at a time (node.md, the builder calls): a new connection to the builder's address, through the execution engine's shell context, takes the request's bytes; what it reads joins the slot's buffer of `APP_BUILDER_BUFFER` (1048576) bytes. At the shell's CLOSED of the connection: a `NODE_EV_BUILDER` of the call with the bytes it read, or with the failure bit when it read none, and the slot is free. A full buffer, or `APP_BUILDER_MS` (10000) since the dial, closes the connection.
- `NODE_ACT_STATE_BYTES`: new memory from lantern_shell_map with lantern_node_state_bytes of the fork of the state's slot, kept as `NODE_ACT_BYTES_PUT` keeps bytes; with no memory, a ByteList of no bytes.
- `NODE_ACT_BYTES_JOIN`: new memory from lantern_shell_map with the ByteLists of the ids one after another, each at a multiple of 8, kept as `NODE_ACT_BYTES_PUT` keeps bytes; with no memory, or an id with no bytes, a ByteList of no bytes.
- `NODE_ACT_STATE_COPY` and `NODE_ACT_BYTES_PUT`: new memory from lantern_shell_map with a copy of the bytes. When the source is at a multiple of 8, a whole page of 4096 bytes that is all zero is not written, as the new memory is zero already: the OS keeps no memory for it, so a state's free room costs none. The last part of a page is copied, so a size that is no multiple of 8 (a state's) keeps this.
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
- `NODE_ACT_DB_STATE` of a block at the first slot of its epoch, above the slot of the last one this run wrote, so each finalized epoch whose first slot has a block (a restart begins at the last one, and syncs only the blocks after it; a restart's get_forkchoice_store takes the anchor's epoch for its checkpoints, and on_block looks up the checkpoint's block at that epoch's first slot, below a later anchor's block): the open segment files are synced; `<dir>/anchor.tmp` gets two ByteLists, the second at the first multiple of 8 after the first: lantern_node_state_bytes of the state, then the block's message, its bytes from 100 of the `SignedBeaconBlock`; it is synced, renamed over `<dir>/anchor.ssz`, and the directory is synced. A failure gives a `cannot write` line.
- Each `NODE_ACT_DB_STATE` whose `custody_count` and `custody_slot` are not those of the anchor or of the last one written: `<dir>/custody.bin` gets them, 16 bytes, synced. A failure gives a `cannot write` line.
- A start with `--checkpoint-state` and `--checkpoint-block`, and no `<dir>/anchor.ssz`, takes them in place of `genesis.ssz`: the two files go into one buffer in the form of `anchor.ssz` (the state's bytes, then the block's message from byte 100 of its `SignedBeaconBlock`) for lantern_node_anchor_block of the fork of the state's slot; a block file below 184 bytes gives a line `<path>: too short`. The anchor's `history_slot` is its slot. Then a line `checkpoint at slot <n>` on the standard output.
- A start with `--data-dir` and a `<dir>/custody.bin` of 16 bytes: the anchor's `custody_count` and `custody_slot` are its two u64.
- The Seen's history: `<dir>/seen-history.bin` with `--data-dir`, else memory (lantern_app_hist_start); each new slot moves the Seen's entries of past epochs there (lantern_app_hist_step), and each lantern_node_run reads it as `history`.
- A start with `--data-dir` and a `<dir>/anchor.ssz` reads it in place of `genesis.ssz` and of the checkpoint files, with lantern_node_anchor_block of the fork of its state's slot. The first block segment file there, from 0 to the anchor's segment, gives the anchor's `history_slot`; the `Db` has room from it to the last block segment file there from the anchor's on, and a segment more, with a power of two of roots above twice those slots. After lantern_node_init, while the `Db`'s `first_slot` leaves its room short of that end (a start from a checkpoint puts it at the backfill's target, node.md), `db_slots` doubles, then `db_roots` while it is not above twice `db_slots`, as a short room grows. Then each segment file goes to lantern_node_db_scan, the blocks', then the sidecars', then the states', and a file with bytes after its last whole record is cut there. Then a line `restart at slot <n>` on the standard output. The node syncs the blocks after the anchor from its peers; those the `Db` holds already get no second record.
- The log: each line is the UTC time of lantern_shell_time_ms as `YYYY-MM-DD HH:MM:SS.mmm`, a space, its level in 5 characters (`ERROR`, `WARN `, `INFO ` or `DEBUG`), a space, the message and an LF. A line goes out when its level is at most `log_level`, in the order error, warn, info, debug: ERROR and WARN lines to the standard error, INFO and DEBUG lines to the standard output.
  - ERROR: the lines of a faulty option or a failed start, `cannot write`, and `a node step: no room`.
  - WARN: `block <slot> not imported: result <n>` for a `NODE_WORK_IMPORT_BLOCK` whose result is neither `LANTERN_VALID` nor `LANTERN_NEED_JUSTIFIED_STATE`.
  - INFO: the lines of the start, `checkpoint at slot`, `restart at slot`, the slot line and the `peers` line; and `block <slot> imported, <a> attestations` for a `NODE_WORK_IMPORT_BLOCK` with `LANTERN_VALID`, with the count of the event.
  - DEBUG: `work <kind> result <n>` for each work that lantern_node_run ran, with its `NODE_WORK_*` kind and result.
- Writes the size of its scratch buffer into the buffer's first 8 bytes before each call that takes it (ARCHITECTURE.md section 6: a callee may leave scratch invalid, and the caller reinitialises it before reuse).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_main`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `args`.

## Function `lantern_app_actions`

Does the actions of a node step, in order.

### Signature

```
lantern_app_actions()
```

### Function does

- First lantern_app_sigs: the gossip attestation signatures of the step, checked at once on the pool.
- Does BYTES_PUT, STATE_COPY, STATE_FREE and BYTES_FREE on the BufferId table, and each WORK with lantern_app_work, in the order of the step's actions.
- Hands each Beacon API, database, discv5, engine and builder action to its part of the app.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_actions`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_alloc`

Makes new memory for a pair of the App.

### Signature

```
lantern_app_alloc(pair, bytes) -> memory
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pair` | input | u64 in a register: the offset of an address and size pair in the App |
| `bytes` | input | u64 in a register |

### Function does

- The pair at the App + `pair` becomes new memory of `bytes` bytes, its first u64 the size.
- Returns the memory, or 0 when the OS gives none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_alloc`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `pair`, `bytes`.

## Function `lantern_app_api_action`

Does a node's NODE_ACT_API_SEND or NODE_ACT_API_CLOSE.

### Signature

```
lantern_app_api_action(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- Sends the action's bytes on its connection, or closes it.
- After the bytes with last 1, starts the slot's next request.
- Drops an action of a connection that is no longer open.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_action`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_api_close`

Closes a Beacon API connection.

### Signature

```
lantern_app_api_close(connection)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |

### Function does

- Queues a CLOSE of the connection while it is open; its slot waits for the shell's CLOSED.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_close`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `connection`.

## Function `lantern_app_api_due`

Owes the node an API_SENT of a connection once its bytes in flight are few.

### Signature

```
lantern_app_api_due(slot, connection)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | the connection's slot |
| `connection` | input | u64 in a register |

### Function does

- Queues a NODE_EV_API_SENT of the connection once the slot's bytes in flight are at most `APP_API_SEND_WINDOW` - `NODE_API_CHUNK`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_due`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `slot`, `connection`.

## Function `lantern_app_api_flush`

Sends the Beacon API's shell actions.

### Signature

```
lantern_app_api_flush()
```

### Function does

- Passes the queued shell actions to libp2p_shell_perform; their results come at the next poll.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_flush`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_api_note`

Queues a NODE_EV_API_SENT or NODE_EV_API_CLOSED for the next step.

### Signature

```
lantern_app_api_note(kind, connection)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register: `NODE_EV_API_SENT` or `NODE_EV_API_CLOSED` |
| `connection` | input | u64 in a register |

### Function does

- Puts the event among the events of the next step.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_note`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `kind`, `connection`.

## Function `lantern_app_api_poll`

Handles the Beacon API's sockets without waiting.

### Signature

```
lantern_app_api_poll()
```

### Function does

- ACCEPTED takes a free slot (ADOPT) or gets a REFUSE.
- RECEIVED joins its slot's buffer, and the slot reads it.
- SENT ends a slot's draining once its bytes are out; CLOSED frees the slot.
- A slot that waits for no answer with no bytes for `APP_API_IDLE_MS` closes, as does a draining one.
- Then the shell actions go out.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 160 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_poll`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_api_read`

Reads the next request of a Beacon API slot.

### Signature

```
lantern_app_api_read(slot)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | state | the connection's slot |

### Function does

- When the slot waits for no answer: lantern_http_request of its bytes, then a NODE_EV_API of the request, or of a fault's status (413 for a full buffer with no whole request).
- The request's bytes leave the buffer, and the slot waits for the answer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_read`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `slot`.

## Function `lantern_app_api_room`

Room for a shell action at the end of the Beacon API's actions.

### Signature

```
lantern_app_api_room(bytes) -> action
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | u64 in a register |

### Function does

- Returns room for a shell action of `bytes` bytes, its bytes counted, after a flush when the actions are full; 0 when it never fits.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `bytes`.

## Function `lantern_app_api_slot`

The slot of a Beacon API connection.

### Signature

```
lantern_app_api_slot(connection) -> slot
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |

### Function does

- Returns the slot of the connection while it is open at that generation, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_slot`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11; rax, rcx, rdx; a0, a7, t0 to t2.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `connection`.

## Function `lantern_app_api_start`

Starts the Beacon API and the node's identity texts.

### Signature

```
lantern_app_api_start() -> status
```

### Returns

- 0: the API listens.
- 2: a line went to the standard error.

### Function does

- Opens a shell context with `--http-max-connections` slots that listens on `--http-address` and `--http-port`, and the slots' buffers.
- Writes the identity's texts, the peer id, the addresses and the version, in a NODE_EV_API_IDENTITY.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 304 bytes on x86-64 (return address included), 304 bytes on ARM64, 304 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_api_start`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_arg_path`

Holds the path of an argument in APP_PATH.

### Signature

```
lantern_app_arg_path(arg)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `arg` | input | [`Arg`](#type-arg) |

### Function does

- Writes the path into `APP_PATH`, or a count past its room when the path does not fit, so the shell gives its error.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_arg_path`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `arg`.

## Function `lantern_app_base58`

The base58btc text of bytes.

### Signature

```
lantern_app_base58(bytes, n, out, work) -> length
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `n` bytes, at most 48 |
| `n` | input | u64 in a register |
| `out` | output | the text |
| `work` | scratch | 72 bytes |

### Function does

- Writes a 1 for each leading zero byte, then the digits; returns the text's length.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 0 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_base58`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64: x0, x4, x9 to x15.
- Argument order: `bytes`, `n`, `out`, `work`.

## Function `lantern_app_base64url`

Decodes a base64url text.

### Signature

```
lantern_app_base64url(text, n, out, room) -> bytes
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | `n` bytes |
| `n` | input | u64 in a register |
| `out` | output | the bytes |
| `room` | input | u64 in a register: the room of `out` |

### Function does

- Decodes RFC 4648 section 5, with or without padding; returns the bytes written, or 2^64 - 1 for a byte of no digit or too many bytes.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_base64url`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x15; rax, rcx, rsi, rdi, r8 to r11; a0, t0 to t5.
- Argument order: `text`, `n`, `out`, `room`.

## Function `lantern_app_boot_nodes`

Gives the node the records of --boot-nodes.

### Signature

```
lantern_app_boot_nodes()
```

### Function does

- Queues a NODE_EV_ENR of each record of `--boot-nodes`, with commas between them.
- Writes a line on the standard error for a record that is not "enr:" and base64url.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_boot_nodes`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_buf_add`

Adds a BufferId table entry.

### Signature

```
lantern_app_buf_add(id, memory, bytes) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | u64 in a register |
| `memory` | input | the buffer |
| `bytes` | input | u64 in a register |

### Returns

- 0: the table has the entry.
- 1: `id` is 0 or in use, or there is no memory.

### Function does

- Doubles the table when it is full (lantern_app_buf_grow).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_buf_add`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `id`, `memory`, `bytes`.

## Function `lantern_app_buf_drop`

Gives the buffer of an id back to the OS.

### Signature

```
lantern_app_buf_drop(id)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | u64 in a register |

### Function does

- Unmaps the buffer, and the table's last entry takes its place.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_buf_drop`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `id`.

## Function `lantern_app_buf_find`

The BufferId table entry of an id.

### Signature

```
lantern_app_buf_find(id) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | u64 in a register |

### Function does

- Returns the entry, or 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_buf_find`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x12; rax, rcx; a0, a7, t0 to t2.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `id`.

## Function `lantern_app_buf_grow`

Doubles the room of the BufferId table.

### Signature

```
lantern_app_buf_grow() -> status
```

### Returns

- 0: the table has twice its room.
- 1: there is no memory.

### Function does

- Copies the entries into new memory and gives the old memory back with lantern_shell_unmap.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_buf_grow`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_builder_answer`

Queues the NODE_EV_BUILDER of a builder slot's call.

### Signature

```
lantern_app_builder_answer(slot, fields)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 in a register |
| `fields` | input | the slot's fields |

### Function does

- The call's NODE_EV_BUILDER joins the next step's events: with the bytes the builder sent, or with the failure bit when it sent none.
- The slot becomes free.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 80 bytes on x86-64 (return address included), 80 bytes on ARM64, 80 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_builder_answer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `slot`, `fields`.

## Function `lantern_app_builder_conf`

Sets up the builder of --builder.

### Signature

```
lantern_app_builder_conf() -> status
```

### Returns

- 0: done, or no `--builder`.
- 2: a line went to the standard error.

### Function does

- With `--builder`: the builder's Address, the anchor's builder_host, and `NODE_FLAG_BUILDER` (app.md).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_builder_conf`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_builder_due`

Moves the builder calls on after the shell's events.

### Signature

```
lantern_app_builder_due()
```

### Function does

- A call past `APP_BUILDER_MS` closes.
- An open call sends its request's next bytes as the shell's send buffer has room.
- A call to close (state 3) gets its CLOSE, then waits for CLOSED (state 4).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_builder_due`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_builder_event`

Takes a shell event of a builder slot's connection.

### Signature

```
lantern_app_builder_event(event) -> taken
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | a shell event of asm-libp2p |

### Function does

- Returns 1 when the event is of a builder slot's connection, which it then takes, else 0.
- CONNECTED opens the call, SENT frees its buffer, RECEIVED keeps the bytes (a full buffer closes it), DIAL_FAILED and CLOSED give the call's NODE_EV_BUILDER.
- Drops an event of an older connection of a slot.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_builder_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `event`.

## Function `lantern_app_builder_fail`

Queues the NODE_EV_BUILDER of a failed builder call.

### Signature

```
lantern_app_builder_fail(call)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `call` | input | u64 in a register: the call |

### Function does

- The NODE_EV_BUILDER of the failure joins the next step's events.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_builder_fail`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `call`.

## Function `lantern_app_builder_handle`

The Handle of a builder slot's connection.

### Signature

```
lantern_app_builder_handle(slot, fields) -> handle
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 in a register |
| `fields` | input | the slot's fields |

### Function does

- Returns the Handle: the slots after the engine's, at the slot's generation.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_builder_handle`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9; rax, rcx; a0, a7, t0.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `slot`, `fields`.

## Function `lantern_app_builder_request`

Starts a NODE_ACT_BUILDER call.

### Signature

```
lantern_app_builder_request(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- A free slot takes the request and dials the builder (app.md).
- With no free slot, or no memory, queues the call's NODE_EV_BUILDER of failure.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_builder_request`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_bytes_join`

Does a NODE_ACT_BYTES_JOIN.

### Signature

```
lantern_app_bytes_join(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- Puts the ByteLists of the ids one after another in new memory, each at a multiple of 8, and keeps it as the new id's (app.md).
- With no memory, or an id with no bytes, keeps a ByteList of no bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_bytes_join`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_categories`

Reads the metrics categories of --metrics.

### Signature

```
lantern_app_categories(start, end) -> (status, bits)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the text's first byte |
| `end` | input | the address after its last byte |

### Function does

- Returns 0 and the bits of the categories: names of `app_categories_table` with commas between them, none or more.
- Returns 1 for another text.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_categories`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x15; rax, rcx, rdx, rdi, r8 to r10; a0, a1, t0 to t6.
- Argument order: `start`, `end`.

## Function `lantern_app_checkpoint`

Reads the anchor of --checkpoint-state and --checkpoint-block.

### Signature

```
lantern_app_checkpoint() -> status
```

### Returns

- 0: `APP_FILE` holds the anchor.
- 2: a line went to the standard error.

### Function does

- Writes the anchor in `APP_FILE` in the form of anchor.ssz: one ByteList of two, the state's bytes, then the block's message from byte 100 of its SignedBeaconBlock.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_checkpoint`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_db_append`

Does a NODE_ACT_DB_APPEND.

### Signature

```
lantern_app_db_append(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- Calls lantern_app_db_write with the action and the table entry of its bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_append`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_db_archive`

Does a NODE_ACT_DB_ARCHIVE.

### Signature

```
lantern_app_db_archive(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- Writes the state's SSZ bytes into new memory; above offset 0, the diff of them against the record at offset 0 of the segment's file, in new memory too.
- Writes the record as a DB_APPEND's is written, in the state segments' file, and frees the memory.
- Then the NODE_EV_DB_ARCHIVE of the segment, the offset and the record (kind 0 when none was written) joins the next step's events.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 400 bytes on x86-64 (return address included), 400 bytes on ARM64, 400 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_archive`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_db_custody`

Writes custody.bin when the custody of a NODE_ACT_DB_STATE changes.

### Signature

```
lantern_app_db_custody(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- When the action's custody_count and custody_slot differ from `AppDb_custody`: writes them to <dir>/custody.bin, 16 bytes, syncs it, and `AppDb_custody` takes them.
- A failure gives a "cannot write" line on the standard error.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_custody`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_db_drop`

Does a NODE_ACT_DB_DROP.

### Signature

```
lantern_app_db_drop(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- Closes the open file of its kind when it is that segment, drops a map of it, then deletes the segment's file.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_drop`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_db_exists`

Whether a block segment's file is there.

### Signature

```
lantern_app_db_exists(segment) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `segment` | input | u64 in a register |

### Function does

- Returns 1 when the file opens to read, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_exists`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `segment`.

## Function `lantern_app_db_file`

A path in the data directory.

### Signature

```
lantern_app_db_file(name, length, out)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `name` | input | `length` bytes |
| `length` | input | u64 in a register |
| `out` | output | ByteList of `APP_PATH_MAX` bytes of room |

### Function does

- Writes <dir>/<name> of the data directory.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_file`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `name`, `length`, `out`.

## Function `lantern_app_db_fit`

Grows the Db room to cover the history of a start from anchor.ssz.

### Signature

```
lantern_app_db_fit() -> status
```

### Returns

- 0: the room covers it.
- 2: a line went to the standard error.

### Function does

- After lantern_node_init: doubles db_slots until the room covers the slots from first_slot to the end lantern_app_db_history gave, then db_roots until it is above twice db_slots, each as a short room grows.
- The Db's first_slot can be below history_slot, the backfill's target (node.md).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_fit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_db_history`

Finds the history of a start from anchor.ssz.

### Signature

```
lantern_app_db_history()
```

### Function does

- The first block segment file there, from 0 to the anchor's segment, gives the anchor's history_slot.
- The Db gets room for the slots from it to the last block segment file there, from the anchor's on, and a segment more, and a power of two of roots above twice them.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_history`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_db_path`

The path of a segment file in the data directory.

### Signature

```
lantern_app_db_path(kind, segment)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register: 0 blocks, 1 sidecars, 2 states |
| `segment` | input | u64 in a register |

### Function does

- Writes <dir>/b<n>.seg, <dir>/s<n>.seg or <dir>/a<n>.seg as a ByteList at `APP_PATH`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 128 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_path`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `kind`, `segment`.

## Function `lantern_app_db_record`

The view entry of a record of a mapped segment.

### Signature

```
lantern_app_db_record(offset, segment) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `offset` | input | u64 in a register: the record's offset |
| `segment` | input | the mapped segment |

### Function does

- Returns the AppDb's view entry of the record, its ByteList in place at byte `DbRecord_bytes` of the record.
- Returns 0 when the record is not all inside the map, or its ByteList header is not of its bytes.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_record`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On ARM64 `offset` is in x23, `segment` in x26 and the view entry in x28, the caller's registers; on x86-64 they are rdi, rsi and r10; on RISC-V a0, a1 and t6.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x13, x16; rax, rcx, rdx, r8, r9; a0, a7, t0 to t5.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `offset`, `segment`.

## Function `lantern_app_db_scan_all`

Scans the segment files there for a start from anchor.ssz.

### Signature

```
lantern_app_db_scan_all() -> status
```

### Returns

- 0: done.
- 2: a line went to the standard error.

### Function does

- Passes each segment file there, the blocks', the sidecars', then the states', from the segment of history_slot to the end of the Db's room, to lantern_node_db_scan.
- Cuts a file with bytes after its last whole record there.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_scan_all`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_db_start`

Sets up the history's files.

### Signature

```
lantern_app_db_start()
```

### Function does

- No file open, no segment mapped.
- With a data directory: the node gets `NODE_FLAG_DB` and room for a segment of slots, and the directory is made; one already there will do, and a failure shows at its first file.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_start`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_db_state`

Writes anchor.ssz from a NODE_ACT_DB_STATE.

### Signature

```
lantern_app_db_state(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- For a block at the first slot of its epoch, above the slot of the last anchor this run wrote: syncs the open segment files.
- Writes <dir>/anchor.tmp: two ByteLists, the second at the first multiple of 8 after the first: the state's SSZ bytes, then those of its block's message.
- Syncs it, renames it over <dir>/anchor.ssz, and syncs the directory.
- A failure gives a line on the standard error.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 192 bytes on x86-64 (return address included), 192 bytes on ARM64, 192 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_state`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_db_write`

Writes the record of a NODE_ACT_DB_APPEND at the end of its segment file.

### Signature

```
lantern_app_db_write(action, entry) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |
| `entry` | input | the table entry of the bytes |

### Returns

- 0: written.
- 1: a failure, with a line on the standard error; the file closes, so the next record opens it again.

### Function does

- Writes its DbRecord, its bytes and zero bytes to a multiple of 8.
- Opens a file that is not the open one of its kind, and cuts it to the record's offset first.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_db_write`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`, `entry`.

## Function `lantern_app_decimal`

Reads a decimal number of an option.

### Signature

```
lantern_app_decimal(start, end) -> (status, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the text's first byte |
| `end` | input | the address after its last byte |

### Function does

- Returns 0 and the u64 of one or more decimal digits; else 1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_decimal`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x12; rax, rcx, rdx, rdi, r8, r9; a0, a1, t0 to t3.
- Argument order: `start`, `end`.

## Function `lantern_app_digits`

Writes a number's decimal digits before a byte.

### Signature

```
lantern_app_digits(value, end, count)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u64 in a register |
| `end` | output | the byte after the digits |
| `count` | input | u64 in a register: the digits |

### Function does

- Writes `count` decimal digits of `value`, the last just before `end`.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_digits`, local to its object. Only x86-64 and RISC-V have it.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Only x86-64 and RISC-V have it.
- Registers it changes, on x86-64 and RISC-V: rax, rcx, rdx, rsi, r8; a0 to a2, t0, t1.
- Argument order: `value`, `end`, `count`.

## Function `lantern_app_discv5`

Runs a discv5 step and its actions.

### Signature

```
lantern_app_discv5()
```

### Function does

- Runs discv5_step when it has events or its WAKEUP is due.
- Then does its actions: SEND as the shell's SEND_DATAGRAM, NODE_FOUND as a NODE_EV_ENR of the next node step, RECORD as a log line, WAKEUP as the next time.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_discv5`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_dotted`

Reads a dotted IPv4 address of an endpoint.

### Signature

```
lantern_app_dotted(start, end) -> (status, address)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the text's first byte |
| `end` | input | the address after its last byte |

### Function does

- Returns 0 and the address, its 4 bytes in order in the low bytes; else 1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_dotted`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x14; rax, rcx, rdx, rdi, r8 to r11; a0, a1, t0 to t6.
- Argument order: `start`, `end`.

## Function `lantern_app_dup`

Copies bytes into new memory.

### Signature

```
lantern_app_dup(bytes, n) -> memory
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `n` bytes |
| `n` | input | u64 in a register |

### Function does

- Returns new memory with a copy of the bytes, or 0.
- With a source at a multiple of 8, a whole page of the source that is all zero bytes is not written: the new memory is zero already, and the OS keeps no memory for a page nobody writes. The last part of a page is copied.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_dup`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `bytes`, `n`.

## Function `lantern_app_dv_datagram`

Takes a shell DATAGRAM of discv5's socket.

### Signature

```
lantern_app_dv_datagram(event) -> taken
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | a shell event of asm-libp2p |

### Function does

- Returns 1 when the event is a DATAGRAM of discv5's socket, which then joins the next discv5 step as a DATAGRAM event, the sender as an Endpoint; else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 160 bytes on x86-64 (return address included), 160 bytes on ARM64, 160 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_dv_datagram`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `event`.

## Function `lantern_app_dv_put`

Queues an event for the next discv5 step.

### Signature

```
lantern_app_dv_put(event, bytes)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `bytes` bytes |
| `bytes` | input | u64 in a register |

### Function does

- The event joins the next discv5 step's events while they have room.

### Function never

- Writes memory but the events and its own stack.
- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 16 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_dv_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64: x9 to x11.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `event`, `bytes`.

## Function `lantern_app_dv_start`

Starts discv5 with the key of libp2p.

### Signature

```
lantern_app_dv_start() -> status
```

### Returns

- 0: started.
- 2: a line went to the standard error.

### Function does

- Makes the discv5 state, with `--enr-address` and `--port` in the record, its UDP socket on `--port`, and the record entry tcp.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 352 bytes on x86-64 (return address included), 352 bytes on ARM64, 352 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_dv_start`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_engine_conf`

Sets up the execution engine of --execution-endpoint.

### Signature

```
lantern_app_engine_conf() -> status
```

### Returns

- 0: done, or no `--execution-endpoint`.
- 2: a line went to the standard error.

### Function does

- With `--execution-endpoint`: the engine's Address, the anchor's engine_host, the jwt_secret of `--jwt-secret`, and `NODE_FLAG_ENGINE`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_engine_conf`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_engine_event`

Takes a shell event of the engine's connection.

### Signature

```
lantern_app_engine_event(event) -> taken
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | a shell event of asm-libp2p |

### Function does

- Returns 1 when the event is of the engine's connection, which it then takes, else 0.
- CONNECTED opens it, SENT frees its buffer, RECEIVED gives a NODE_EV_ENGINE of the bytes.
- DIAL_FAILED and CLOSED end it, with a NODE_EV_ENGINE of failure while the node waits for an answer.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_engine_event`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `event`.

## Function `lantern_app_engine_handle`

The Handle of the engine's connection.

### Signature

```
lantern_app_engine_handle() -> handle
```

### Function does

- Returns the Handle: the slot after libp2p's, at its generation.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_engine_handle`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9; rax, rcx; a0, a7, t0.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_engine_perform`

Does one shell action of the engine or the builder.

### Signature

```
lantern_app_engine_perform(action, bytes)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | `bytes` bytes: a shell action |
| `bytes` | input | u64 in a register |

### Function does

- Puts the action in the ByteList at `APP_ENGINE_ACT` and passes it to libp2p_shell_perform; its results join the shell's events.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_engine_perform`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`, `bytes`.

## Function `lantern_app_engine_request`

Does a NODE_ACT_ENGINE.

### Signature

```
lantern_app_engine_request(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- The request's bytes wait in `APP_ENGINE_OUT`; they go on the open connection, or after a DIAL of the engine's Address.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_engine_request`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_engine_send`

Sends the next bytes of the engine request.

### Signature

```
lantern_app_engine_send()
```

### Function does

- Sends the request's next bytes on the open connection, as far as the shell's send buffer has room.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_engine_send`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_event_put`

Queues an event for the next node step.

### Signature

```
lantern_app_event_put(event, bytes) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `event` | input | `bytes` bytes |
| `bytes` | input | u64 in a register |

### Returns

- 0: the event joined the next step's events.
- 1: there is no memory.

### Function does

- Grows the events when they are full.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_event_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `event`, `bytes`.

## Function `lantern_app_fail_status`

Writes a failure line and gives 2.

### Signature

```
lantern_app_fail_status(text, length, status) -> two
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `text` | input | `length` bytes |
| `length` | input | u64 in a register |
| `status` | input | u64 in a register |

### Function does

- Writes the line "<text>: status <status>" on the standard error, then returns 2.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_fail_status`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `text`, `length`, `status`.

## Function `lantern_app_file_free`

Gives the memory of APP_FILE back.

### Signature

```
lantern_app_file_free()
```

### Function does

- Unmaps the memory of `APP_FILE`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_file_free`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_fork`

The fork of a slot.

### Signature

```
lantern_app_fork(slot, config) -> fork
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `slot` | input | u64 in a register |
| `config` | input | [`Config`](helpers.md#type-config) |

### Function does

- Returns the last fork whose epoch in `config` is at most the slot's epoch.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_fork`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11; rax, rcx, rdx; a0, t0 to t2.
- Argument order: `slot`, `config`.

## Function `lantern_app_grow`

Moves the node, the store or the Seen to new memory with more room.

### Signature

```
lantern_app_grow(kind, field) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register: 0 the node, 1 the store, 2 the Seen |
| `field` | input | u64 in a register: the byte offset of a field of its room, or 2^64 - 1 for each field |

### Returns

- 0: moved.
- 1: there is no memory, or the copy failed.

### Function does

- Doubles that field of its room, or each field, and copies the value into the new memory with the copy function of its kind; the old memory goes back.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_grow`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `kind`, `field`.

## Function `lantern_app_hex_digit`

The value of a hex digit.

### Signature

```
lantern_app_hex_digit(byte) -> value
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `byte` | input | u64 in a register |

### Function does

- Returns the value of the hex digit, or 16 when it is not one.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hex_digit`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0; rax, rdi; a0, t0, t1.
- Argument order: `byte`.

## Function `lantern_app_hist_chunk`

The history's chunk of a kind for an epoch.

### Signature

```
lantern_app_hist_chunk(epoch, kind) -> chunk
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `epoch` | input | u64 in a register |
| `kind` | input | u64 in a register: a `HIST_*` kind |

### Returns

- The chunk its index entry of the epoch names for the kind, or 0.

### Function does

- Gives the chunk only when it lies inside the history's `size`, is of that kind, holds the epoch between `epoch_lo` and `epoch_hi`, and its entries fit in its bytes: an index entry a crash left before its `size` was written names no chunk.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_chunk`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the AppHist in x28, r15, s10.
- Argument order: `epoch`, `kind`.

## Function `lantern_app_hist_fail`

Writes a line that seen-history.bin cannot be written.

### Signature

```
lantern_app_hist_fail(error)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `error` | input | u64 in a register: the OS error |

### Function does

- Writes "cannot write <dir>/seen-history.bin: error <n>" on the standard error and adds 1 to the db failures metric.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_fail`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `error`.

## Function `lantern_app_hist_grow`

Doubles the room of the chunks' ByteList.

### Signature

```
lantern_app_hist_grow() -> status
```

### Returns

- 0, or 1 when the OS gives no memory; then nothing is changed.

### Function does

- Copies the ByteList's header and bytes into new memory of twice its room and gives the old memory back.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_grow`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1, and the AppHist in x28, r15, s10.

## Function `lantern_app_hist_header`

The fixed fields of a new history.

### Signature

```
lantern_app_hist_header(history)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `history` | output | the first `SEEN_HISTORY_FIXED` bytes of a [`SeenHistory`](networking.md#type-seenhistory) |

### Function does

- Writes `size` and `data_start` `SEEN_HISTORY_DATA`, `magic`, `version`, `capacity` `SEEN_HISTORY_CAPACITY`, and `first_epoch` the store's finalized epoch.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_header`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `history`.

## Function `lantern_app_hist_map`

Maps seen-history.bin again.

### Signature

```
lantern_app_hist_map()
```

### Function does

- Unmaps the file's last map, then maps the whole file to read into `AppHist_map`; 0 and 0 when that fails.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_map`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1, and the AppHist in x28, r15, s10.

## Function `lantern_app_hist_path`

The path of seen-history.bin.

### Signature

```
lantern_app_hist_path()
```

### Function does

- Writes <dir>/seen-history.bin of the data directory as a ByteList at `APP_PATH`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_path`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_hist_put`

Writes bytes at an offset of the history.

### Signature

```
lantern_app_hist_put(bytes, length, offset) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `length` bytes |
| `length` | input | u64 in a register |
| `offset` | input | u64 in a register: the history's byte the first byte goes to |

### Returns

- 0, or the OS error; 1 when the memory history cannot grow.

### Function does

- `APP_HIST_FILE`: lantern_shell_write_at of the file.
- `APP_HIST_MEMORY`: copies them into the memory, which first grows to twice its size, or to the end of the bytes when that is more, with the history's bytes copied.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1, and the AppHist in x28, r15, s10.
- Argument order: `bytes`, `length`, `offset`.

## Function `lantern_app_hist_start`

Sets up the Seen's history.

### Signature

```
lantern_app_hist_start()
```

### Caller must

- Call it after the store and the Seen are made.

### Function does

- Makes the chunks' ByteList of `APP_HIST_OUT_BYTES`; with no memory the mode is `APP_HIST_NONE`.
- With --data-dir: opens <dir>/seen-history.bin to write at offsets and maps it; a file whose map holds a `SeenHistory` of `SEEN_HISTORY_MAGIC`, `SEEN_HISTORY_VERSION`, `SEEN_HISTORY_CAPACITY` and data start `SEEN_HISTORY_DATA`, with a `size` from the data start to the map's size, stays: its chunks are the history of the node's past runs.
- Another file starts again: cut to no bytes, then to `SEEN_HISTORY_DATA` bytes of zeros, the header of lantern_app_hist_header written and synced, and mapped. The mode is `APP_HIST_FILE`.
- Without --data-dir, or when the file fails (a cannot write line): the history is memory of `SEEN_HISTORY_DATA` + `APP_HIST_ROOM` bytes with that header, mode `APP_HIST_MEMORY`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_start`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_hist_step`

Moves the Seen's entries of past epochs to its history.

### Signature

```
lantern_app_hist_step()
```

### Caller must

- Call it once at each new slot, before the next node step validates a message.

### Function does

- Nothing in mode `APP_HIST_NONE`. A file with no map is mapped again first; one that cannot be skips the step, the Seen unchanged.
- lantern_seen_archive of the Seen with the store into the chunks' ByteList, which doubles while short.
- Each chunk: when an epoch of its range has an index entry of its kind naming a chunk (lantern_app_hist_chunk), lantern_seen_chunk_merge of that chunk and this one takes this one's place; then it goes to the end of the history (lantern_app_hist_put at its `size`).
- A chunk with an epoch below `first_epoch` or past `capacity` index entries goes to no place: 1 more db failure.
- Then, each durable before the next (lantern_app_hist_sync): the chunks; the index entries from the lowest to the highest epoch of the chunks, each epoch of a chunk's range naming it for its kind; the new `size`.
- In mode `APP_HIST_FILE`, maps the file again, so the next lantern_node_run reads the new chunks.
- A failure of a write or a sync: a cannot write line, the `size` unchanged.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_step`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_hist_sync`

Makes the history's bytes durable.

### Signature

```
lantern_app_hist_sync() -> status
```

### Returns

- 0, or the OS error.

### Function does

- `APP_HIST_FILE`: lantern_shell_sync of the file. `APP_HIST_MEMORY`: nothing.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_hist_sync`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1, and the AppHist in x28, r15, s10.

## Function `lantern_app_identity_put`

Queues the identity's texts for the next node step.

### Signature

```
lantern_app_identity_put()
```

### Function does

- The identity's texts go to the next step in a NODE_EV_API_IDENTITY.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_identity_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_ipv4`

Reads an IPv4 address of an option.

### Signature

```
lantern_app_ipv4(start, end) -> (status, address)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the text's first byte |
| `end` | input | the address after its last byte |

### Function does

- Returns 0 and the address of 4 decimal numbers of 0 to 255 with dots between them, its 4 bytes in order in the low bytes; else 1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_ipv4`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x14; rax, rcx, rdx, rdi, r8 to r11; a0, a1, t0 to t6.
- Argument order: `start`, `end`.

## Function `lantern_app_key`

Makes the node's secp256k1 key.

### Signature

```
lantern_app_key() -> status
```

### Returns

- 0: `APP_KEY` holds the key.
- The statuses of the asm-crypto functions it calls.

### Function does

- Takes fresh random bytes below 2^255, and so below the order of the curve; a zero key tries again, up to 4 times.
- Writes the anchor's node_id: keccak256 of the key's point, x then y, in reverse byte order.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 336 bytes on x86-64 (return address included), 336 bytes on ARM64, 336 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_key`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_key_job`

A job of lantern_app_pool: the keys of a range of validators checked into the PubkeyCache.

### Signature

```
lantern_app_key_job(keys, index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `keys` | state | the `APP_KEYS` record: the first validator's key, the validators, the PubkeyCache |
| `index` | input | u64 in a register: the job |

### Function does

- crypto_bls_key_cache_fill of asm-crypto for the validators `APP_KEY_JOB` x `index` to the lower of `APP_KEY_JOB` x (`index` + 1) and the validators, less 1. The jobs' ranges hold no index in common, as crypto_bls_key_cache_fill requires of calls at the same time.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_key_job`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- A ShellJob function (shell.md): its status is not read.
- Argument order: `keys`, `index`.

## Function `lantern_app_lc_grow`

Moves a light client store to a new buffer with twice the capacities.

### Signature

```
lantern_app_lc_grow(entry) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | input | the table entry of the store |

### Returns

- 0: moved.
- 1: there is no memory.

### Function does

- Copies the store with lantern_lc_store_copy into a buffer with twice the capacities of each part.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 96 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_lc_grow`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `entry`.

## Function `lantern_app_no_memory`

Writes the no memory line and gives 2.

### Signature

```
lantern_app_no_memory() -> two
```

### Function does

- Writes the line "lantern: no memory" on the standard error, then returns 2.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_no_memory`, local to its object. Only x86-64 and RISC-V have it.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Only x86-64 and RISC-V have it.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_lc_start`

Makes the light client store as BufferId 2.

### Signature

```
lantern_app_lc_start() -> status
```

### Returns

- 0: the store is BufferId 2.
- 1: it could not be made.

### Function does

- Calls lantern_lc_store_init with the anchor state and block and the `APP_LC_*` capacities (node.md, lantern_node_init: Caller must).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_lc_start`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_line_base64url`

Adds base64url text to the log line.

### Signature

```
lantern_app_line_base64url(bytes, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `n` bytes |
| `n` | input | u64 in a register |

### Function does

- The base64url text of the bytes (RFC 4648 section 5, no padding) joins the log line.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_base64url`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `bytes`, `n`.

## Function `lantern_app_line_clear`

Empties the log line.

### Signature

```
lantern_app_line_clear()
```

### Function does

- The log line becomes empty, so the text helpers then build a text in it.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_clear`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on RISC-V: a7.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_line_end`

Writes the log line.

### Signature

```
lantern_app_line_end(kind)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register: `APP_LOG_INFO`, `APP_LOG_ERROR`, `APP_LOG_WARN` or `APP_LOG_DEBUG` |

### Function does

- When the kind's level is at most the log level: writes its time and level before the line and an LF after it, to the standard error for ERROR and WARN, else the standard output.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_end`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `kind`.

## Function `lantern_app_line_hex`

Adds hex digits to the log line.

### Signature

```
lantern_app_line_hex(bytes, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `n` bytes |
| `n` | input | u64 in a register |

### Function does

- The hex digits of the bytes join the log line.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_hex`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `bytes`, `n`.

## Function `lantern_app_line_ip4`

Adds an IPv4 address to the log line.

### Signature

```
lantern_app_line_ip4(address)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `address` | input | u64 in a register: its bytes in order in the low bytes |

### Function does

- The address joins the line in dotted decimal.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_ip4`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `address`.

## Function `lantern_app_line_path`

Adds the path of APP_PATH to the log line.

### Signature

```
lantern_app_line_path()
```

### Function does

- The bytes of `APP_PATH` join the log line, as far as they fit.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_path`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_line_start`

Starts the log line.

### Signature

```
lantern_app_line_start()
```

### Function does

- Starts an empty line with room for the time and the level that lantern_app_line_end writes.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_start`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on RISC-V: t0, a7.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_line_text`

Adds bytes to the log line.

### Signature

```
lantern_app_line_text(bytes, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `n` bytes |
| `n` | input | u64 in a register |

### Function does

- The bytes join the log line, as far as it has room.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x12; rax, rcx, rdx, rsi, rdi; a0, a1, a7, t0 to t3.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `bytes`, `n`.

## Function `lantern_app_line_to`

Copies the log line into a text field of the identity's view.

### Signature

```
lantern_app_line_to(field, room)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `field` | output | the text field: its length, then its bytes |
| `room` | input | u64 in a register: the most bytes |

### Function does

- Writes the line's length, then its bytes, at most `room`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_to`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `field`, `room`.

## Function `lantern_app_line_u64`

Adds a decimal number to the log line.

### Signature

```
lantern_app_line_u64(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u64 in a register |

### Function does

- The decimal digits of `value` join the log line.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_line_u64`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `value`.

## Function `lantern_app_log_work`

Writes the log lines of a work that ran.

### Signature

```
lantern_app_log_work(kind, entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register: the work's kind |
| `entry` | input | the work's data entry, or 0 |

### Function does

- Writes DEBUG work <kind> result <n> (app.md, the log).
- For a block's import: INFO block <slot> imported, <a> attestations, or WARN block <slot> not imported: result <n>.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 32 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_log_work`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On ARM64 it takes `entry` in x24 and `kind` in x26, the registers of lantern_app_work; on x86-64 in rsi and rdi, on RISC-V in a1 and a0.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `kind`, `entry`.

## Function `lantern_app_loop`

The loop of the binary.

### Signature

```
lantern_app_loop()
```

### Function does

- Reads the clock; queues a NODE_EV_TICK of the time and the shell's events; runs lantern_node_step with libp2p; at each new slot runs lantern_app_hist_step and writes a line.
- Then waits for the sockets until the node's wakeup, at most `APP_WAIT_MS`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 112 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_loop`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_map`

New zeroed memory from the OS.

### Signature

```
lantern_app_map(bytes) -> memory
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | u64 in a register |

### Function does

- Returns memory of `bytes` bytes from lantern_shell_map, zeroed, or 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_map`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `bytes`.

## Function `lantern_app_met_answer`

Answers a metrics request.

### Signature

```
lantern_app_met_answer(index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64 in a register: the slot's index |

### Function does

- While the slot reads: lantern_metrics_answer of its request bytes in its answer's memory, which doubles while short, up to `APP_MET_TRIES` times; then the answer goes out.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_answer`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `index`.

## Function `lantern_app_met_close`

Closes a metrics connection.

### Signature

```
lantern_app_met_close(connection)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |

### Function does

- Queues a CLOSE of the connection while it is open; its slot waits for the shell's CLOSED.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_close`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `connection`.

## Function `lantern_app_met_delay`

Records the delay of a message.

### Signature

```
lantern_app_met_delay(offset, slot)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `offset` | input | u64 in a register: the offset of an AppMetrics Histogram |
| `slot` | input | u64 in a register: the message's slot |

### Function does

- The delay from the slot's start to the store's time joins the Histogram, with the delay bounds.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_delay`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `offset`, `slot`.

## Function `lantern_app_met_flush`

Sends the metrics server's shell actions.

### Signature

```
lantern_app_met_flush()
```

### Function does

- Passes the queued shell actions to libp2p_shell_perform; their results come at the next poll.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_flush`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_met_obs`

Records a value in an AppMetrics Histogram.

### Signature

```
lantern_app_met_obs(offset, bounds, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `offset` | input | u64 in a register: the Histogram's offset in AppMetrics |
| `bounds` | input | u64 in a register: its bound set |
| `value` | input | u64 in a register |

### Function does

- The value joins the Histogram (lantern_metrics_observe).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_obs`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `offset`, `bounds`, `value`.

## Function `lantern_app_met_poll`

Handles the metrics server's sockets without waiting.

### Signature

```
lantern_app_met_poll()
```

### Function does

- ACCEPTED takes a free slot (ADOPT) or gets a REFUSE.
- RECEIVED joins a reading slot's request bytes, and the slot answers; SENT sends more of the answer; CLOSED frees the slot.
- A slot with no bytes for `APP_API_IDLE_MS` closes; then the shell actions go out (app.md).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_poll`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_met_room`

Room for a shell action at the end of the metrics server's actions.

### Signature

```
lantern_app_met_room(bytes) -> action
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | u64 in a register |

### Function does

- Returns room for a shell action of `bytes` bytes, its bytes counted, after a flush when the actions are full; 0 when it never fits.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_room`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `bytes`.

## Function `lantern_app_met_send`

Sends more of a metrics answer.

### Signature

```
lantern_app_met_send(index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `index` | input | u64 in a register: the slot's index |

### Function does

- Sends more of the answer while the shell's send buffer has room, in SENDs of at most `APP_MET_PIECE` bytes.
- With the last bytes out and none in flight, the connection closes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_send`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `index`.

## Function `lantern_app_met_slot`

The slot of a metrics connection.

### Signature

```
lantern_app_met_slot(connection) -> slot
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `connection` | input | u64 in a register |

### Function does

- Returns the slot of the connection while it is open at its generation, or 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_slot`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9 to x11, x16; rax, rcx, rdx; a0, a7, t0 to t2.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `connection`.

## Function `lantern_app_met_sources`

Gathers the sources of the metrics.

### Signature

```
lantern_app_met_sources()
```

### Function does

- Fills its table of the metrics sources, each then an argument of lantern_metrics_answer: lantern_metrics_node of the node and the store; the head state's values by lantern_<fork>_metrics_state, again only for a new head state; the node's counters; the app's run times.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_sources`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_met_start`

Starts the metrics server.

### Signature

```
lantern_app_met_start() -> status
```

### Returns

- 0: started, or no categories.
- 2: a line went to the standard error.

### Function does

- With `--metrics` categories: a shell context of `APP_MET_CONNS` connections that listens on `--metrics-address` and `--metrics-port`, and its buffers (app.md).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 176 bytes on x86-64 (return address included), 176 bytes on ARM64, 176 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_start`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_met_us`

The monotonic microseconds.

### Signature

```
lantern_app_met_us() -> us
```

### Function does

- Returns the monotonic microseconds of libp2p_shell_clock.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_us`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_met_work`

Records the metrics of a work that ran.

### Signature

```
lantern_app_met_work(kind, entry)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `kind` | input | u64 in a register: the work's kind |
| `entry` | input | its data's table entry, or 0 |

### Function does

- Records its run time since `APP_MET_T0`, and a result other than `LANTERN_OK`, by kind (app.md, the metrics).
- Then by kind: gossip by topic and result, the requests served by method, the column times and counts, a published block, an epoch crossed.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_met_work`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `kind`, `entry`.

## Function `lantern_app_multiaddr`

Writes a multiaddr of the node into a field of the identity's view.

### Signature

```
lantern_app_multiaddr(transport, field)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `transport` | input | the text `tcp` or `udp` |
| `field` | output | a text field of the view |

### Function does

- Writes /ip4/<`--enr-address`>/<transport>/<`--port`>/p2p/<peer id>, or length 0 with no `--enr-address`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_multiaddr`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `transport`, `field`.

## Function `lantern_app_name_is`

Whether two byte strings are equal.

### Signature

```
lantern_app_name_is(a, a_n, b, b_n) -> flag
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `a` | input | `a_n` bytes |
| `a_n` | input | u64 in a register |
| `b` | input | `b_n` bytes |
| `b_n` | input | u64 in a register |

### Function does

- Returns 1 when the bytes are equal, else 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_name_is`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9, x10; rax, rdx, rsi, rdi, r8; a0, t0, t1.
- Argument order: `a`, `a_n`, `b`, `b_n`.

## Function `lantern_app_net`

Starts the node's network.

### Signature

```
lantern_app_net() -> status
```

### Returns

- 0: started.
- 2: a line went to the standard error.

### Function does

- Makes the libp2p config from its template, the protocols of lantern_node_protocols and the key of lantern_app_key, then the libp2p state with libp2p_init.
- Makes the shell context with a slot for each connection, one for the execution engine and those of the builder, its events, and the engine's action.
- Listens on TCP `--port` on every IPv4 address, and writes a line of it.
- Starts the Beacon API, the metrics server and discv5, and gives the node the boot nodes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 208 bytes on x86-64 (return address included), 208 bytes on ARM64, 208 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_net`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_number`

Reads a decimal number of an endpoint.

### Signature

```
lantern_app_number(start, end) -> (status, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `start` | input | the text's first byte |
| `end` | input | the address after its last byte |

### Function does

- Returns 0 and the u64 of one or more decimal digits; else 1.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_number`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- It returns two values: x0, rax or a0, then x1, rdx or a1.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x12; rax, rcx, rdx, rdi, r8; a0, a1, t0 to t3.
- Argument order: `start`, `end`.

## Function `lantern_app_p2p_events`

Passes the shell's events on.

### Signature

```
lantern_app_p2p_events()
```

### Function does

- Each event of the shell becomes a NODE_EV_P2P event of the next step, but those of the engine's, the builder's and discv5's connections, which their parts take.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_p2p_events`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_path`

A path in the network directory.

### Signature

```
lantern_app_path(name, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `name` | input | `length` bytes |
| `length` | input | u64 in a register |

### Function does

- Writes the path of the name in the network directory as a ByteList at `APP_PATH`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_path`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `name`, `length`.

## Function `lantern_app_pool`

Starts the pool of `--threads`, gives it to the StateCache, and checks the anchor state's keys into the PubkeyCache on it.

### Signature

```
lantern_app_pool()
```

### Function does

- lantern_shell_pool_start of `APP_THREADS` with `threads` (shell.md): `threads` - 1 workers at most.
- With a StateCache at `CONFIG_STATE_CACHE`: its `pool` takes `APP_THREADS`, so each lantern_state_root of the node hashes its large trees on the pool.
- A worker that cannot start leaves the pool with the workers started: the node runs as with fewer threads.
- With a PubkeyCache at `CONFIG_PUBKEY_CACHE` and the anchor state: lantern_shell_pool_run of ceil(n / `APP_KEY_JOB`) jobs of lantern_app_key_job, n the state's validators, so each block and gossip check after the start finds the keys of those validators checked.

### Function never

- Makes an OS call other than through lantern_shell_pool_start and lantern_shell_pool_run.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_pool`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_read`

Reads the file at APP_PATH into APP_FILE.

### Signature

```
lantern_app_read() -> status
```

### Returns

- 0: read.
- 2: a line went to the standard error.

### Function does

- Reads the file with lantern_shell_read_file.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_read`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_regrow`

Moves a state to new memory with twice the StateRoom.

### Signature

```
lantern_app_regrow(entry) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `entry` | input | the state's BufferId table entry |

### Returns

- 0: moved.
- 1: there is no memory, or the copy failed.

### Function does

- Copies the state with lantern_beacon_state_copy of its fork into new memory with twice the App's StateRoom; the old memory goes back.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_regrow`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `entry`.

## Function `lantern_app_sig_job`

A job of lantern_app_sigs: the signature checks of its share of the SigTable.

### Signature

```
lantern_app_sig_job(record, index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `record` | state | the `APP_SIGS` record: the SigTable, the jobs n, then n scratches of `APP_SIG_SCRATCH` bytes |
| `index` | input | u64 in a register: the job |

### Function does

- For each entry k of the SigTable with k mod n the job: crypto_bls_verify of asm-crypto of its key, message and signature, its `valid` the result, with the job's own scratch.

### Function never

- Makes an OS call.
- Writes outside its share of the entries' `valid` and its scratch.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_sig_job`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- A ShellJob function (shell.md): its status is not read.
- Argument order: `record`, `index`.

## Function `lantern_app_sigs`

Before the actions of a step, checks the signatures of its beacon_attestation GOSSIP works at once on the pool, into the PubkeyCache's SigTable.

### Signature

```
lantern_app_sigs()
```

### Function does

- With a PubkeyCache and workers in the pool of `--threads`: empties the SigTable.
- For each WORK action of `NODE_WORK_GOSSIP` of the topic beacon_attestation: its bytes from the BYTES_PUT action of its `data` id before it, its head from its `state_a`, and lantern_node_sig_input into the next entry of the SigTable while it has room.
- With 2 or more entries: lantern_shell_pool_run of the lower of the entries, the workers + 1 and `APP_SIG_JOBS` (16) jobs of lantern_app_sig_job.
- Then lantern_app_actions does the actions in order; each GOSSIP work's signature check reads the SigTable (networking.md), so its result is the one of a check of its own.

### Function never

- Makes an OS call other than through lantern_shell_pool_run.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 128 bytes on ARM64, 128 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_sigs`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_space`

Skips white space of a text.

### Signature

```
lantern_app_space()
```

### Function does

- Moves the cursor past spaces, tabs, CR and LF, to at most the end.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_space`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x23, r14, s5, which it moves; the end in x24, r15, s6.
- Registers it changes, on ARM64, x86-64, RISC-V: x9; rax; t0, t1.

## Function `lantern_app_start`

The start of the binary.

### Signature

```
lantern_app_start() -> status
```

### Returns

- 0: started.
- 2: a line went to the standard error.

### Function does

- Reads the config, the anchor of genesis.ssz, anchor.ssz or the checkpoint files, then makes the store, the node and the Seen (app.md).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 112 bytes on ARM64, 112 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_start`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.

## Function `lantern_app_state_bytes`

Does a NODE_ACT_STATE_BYTES.

### Signature

```
lantern_app_state_bytes(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- Writes lantern_node_state_bytes of the fork of the state's slot into new memory, kept as the bytes of the new id.
- With no memory, keeps a ByteList of no bytes.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 144 bytes on x86-64 (return address included), 144 bytes on ARM64, 144 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_state_bytes`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_state_cache`

Makes the state caches of the app's config.

### Signature

```
lantern_app_state_cache(bytes)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | u64 in a register: the anchor file's bytes |

### Function does

- Makes a StateCache, a CommitteeCache and a PubkeyCache for `bytes` / 121 + 65536 validators, at `CONFIG_STATE_CACHE` and `CONFIG_COMMITTEE_CACHE` of the app's config.
- With no memory, makes none.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_state_cache`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `bytes`.

## Function `lantern_app_step`

Runs lantern_node_step and the actions it gives.

### Signature

```
lantern_app_step(p2p, tick) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `p2p` | state | the libp2p state, or 0 with no network |
| `tick` | input | the Tick, or 0 with no network |

### Returns

- 0: done.
- 2: a line went to the standard error.

### Function does

- Runs lantern_node_step with the App's events, again with a larger node and actions while it asks for them.
- Then the accepted events leave the queue and the actions run.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 112 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_step`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `p2p`, `tick`.

## Function `lantern_app_store_slot`

The current slot of the store.

### Signature

```
lantern_app_store_slot(store) -> slot
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `store` | input | [`Store`](fork-choice.md#type-store) |

### Function does

- Returns (time_ms - genesis_time_ms) // `SLOT_DURATION_MS`, 0 before genesis.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_store_slot`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x9, x10; rax, rcx, rdx; a0, a7, t0 to t2.
- Argument order: `store`.

## Function `lantern_app_time_text`

Writes a time as UTC text.

### Signature

```
lantern_app_time_text(ms, out)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ms` | input | u64 in a register: Unix milliseconds |
| `out` | output | 23 bytes |

### Function does

- Writes YYYY-MM-DD HH:MM:SS.mmm of the UTC time, with civil_from_days of the days since 1970.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 0 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_time_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- On ARM64 it is a leaf that changes x0 to x15 and keeps x30 in x7.
- Argument order: `ms`, `out`.

## Function `lantern_app_unmap`

Gives a pair of the App back to the OS.

### Signature

```
lantern_app_unmap(pair)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `pair` | input | u64 in a register: the offset of an address and size pair in the App |

### Function does

- Unmaps the memory with lantern_shell_unmap, and the pair becomes 0, 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_unmap`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `pair`.

## Function `lantern_app_work`

Does a WORK action.

### Signature

```
lantern_app_work(action)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `action` | input | the node's `NodeAction` |

### Function does

- Runs lantern_node_run with the work's buffers, again with more room while it asks for it; then its WORK_DONE event joins the next step's.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_work`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `action`.

## Function `lantern_app_work_data`

The table entry of a work's data.

### Signature

```
lantern_app_work_data(id, view) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | u64 in a register: the data's BufferId |
| `view` | input | u64 in a register: 0 data, 1 state_b |

### Function does

- Returns the table entry that lantern_app_work_entry gives.
- For a `NODE_DB_REF`: the AppDb's view entry `view` of its record in the segment, mapped again when the file grew past the map; or 2^64 - 1 when the record is not there.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 96 bytes on x86-64 (return address included), 96 bytes on ARM64, 96 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_work_data`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `id`, `view`.

## Function `lantern_app_work_entry`

The table entry of a BufferId.

### Signature

```
lantern_app_work_entry(id) -> entry
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `id` | input | u64 in a register |

### Function does

- Returns the entry, 0 for id 0, or 2^64 - 1 when no entry has it.

### Function never

- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 0 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_app_work_entry`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64: x0, x9 to x13.
- Registers it reads, on ARM64, x86-64, RISC-V: the App in x19, rbx, s1.
- Argument order: `id`.

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
| 200 | `metrics` | u64 | The bits of the metrics sub categories ([metrics.md](metrics.md#type-metricentry)) |
| 208 | `metrics_address` | u64 | The metrics server's IPv4 address, its 4 bytes in network order in the low bytes |
| 216 | `metrics_port` | u64 | The metrics server's port |
| 224 | | | Size |

## Test vectors

- tests/generator/app.py: command lines with their `AppOptions`, or the argument index of their fault. File: `<preset>-phase0-app-options.bin`.
- tests/app/start.sh and tests/app/start.ps1 (Windows): the binary of each target given a faulty option exits with 1 and its ERROR line, whose time has the form of the log and today's UTC date; given a network directory with no config.yaml, it exits with 2 and a "cannot read" line. CI runs them.
- tests/app/api.py, run by tests/app/start.sh and start.ps1: the binary started with `--http-max-connections 2` and the network directory that tests/generator/run.sh writes beside the vectors (tests/app/network.py, minimal, altair, 4096 validators at slot 0). On one connection, two getNodeVersion requests in one write and then a getHealth must give three responses, and the connection must stay open; on it then 50 getNodeVersion requests one after another, each sent once the one before is answered, must all be answered within 3 s; a third connection must be closed with no bytes while two are open; a request head of 16385 bytes must give 431 and the connection must close; a `DELETE` must give 405 with `Allow: GET`; getStateV2 of `head` as SSZ, read 16384 bytes at a time with a pause of 20 ms after each so that the shell's send buffer fills, must give the bytes of the directory's genesis.ssz with `Eth-Consensus-Version: altair`; as JSON, over HTTP/1.1 (chunked) and over HTTP/1.0 (closed after the body), a body whose `version` is `altair` and whose `data` has `slot` `"0"`, 4096 validators and the `genesis_validators_root` of genesis.ssz; getSpec must give the directory's config.yaml values of `CONFIG_NAME`, `GENESIS_FORK_VERSION`, `DEPOSIT_CHAIN_ID` and `SLOT_DURATION_MS` / 1000 as `SECONDS_PER_SLOT`, and the preset's `SLOTS_PER_EPOCH`; getForkSchedule phase0 and altair at epoch 0 with the config's versions; getDepositContract the config's `DEPOSIT_CHAIN_ID` and `DEPOSIT_CONTRACT_ADDRESS`; getStateValidators of `head`, chunked, the 4096 validators of genesis.ssz in order, each `active_ongoing` with its `pubkey` and `balance`; postStateValidators of a public key and an index, the two validators in index order; getStateValidator of an index, that validator; getEpochCommittees of `head`, 4 committees for each slot of epoch 0 in order, which hold each of the 4096 validators once; getProposerDuties of epoch 0, the slots 1 to 7 in order, each with the index of a validator and its `pubkey` in genesis.ssz, and as `dependent_root` the root of getBlockRoot of `genesis`; an event stream of `head`, `block` and `finalized_checkpoint` must give its head, and stay open with no bytes while a connection with no bytes must close within 31 s. tests/app/metrics.py, with `--metrics-port 18008`: GET of `/metrics`, twice, must give 200 with `Content-Type: text/plain; version=0.0.4; charset=utf-8`, a `Content-Length` of its body and whole families of Prometheus text with `libp2p_peers` and `beacon_head_slot`, then the close; GET of another path 404; POST 405 with `Allow: GET`.
- tests/app/burst.py, run by tests/app/start.sh and start.ps1 after api.py: 256 datagrams of 200 bytes that decode to no packet, sent at once to the binary's UDP `--port`; then its log must hold no line `discv5: status`.
- tests/app/network.py: a network directory (config.yaml, genesis.ssz) to run the binary with, alone or beside other clients.
- tests/app/trusted_setup.py: writes include/trusted_setup_4096.bin from the pinned spec, or with `--check` exits 1 when the file differs; CI's trusted-setup job runs the check.
- tests/app/devnet.sh: a devnet of ethpandaops/ethereum-package (tests/kurtosis/, at a pinned commit) of geth and one consensus client with all the validators, and the binary's image (platform/docker/Dockerfile) beside it with every consensus client's record as a boot node; lantern's head must reach slot 8, be a block of the client's chain and be within 2 slots of the client's head, at two checks a slot apart.
  - RESTART=1, beside lighthouse, CI's restart job: lantern with `--data-dir` and `--archive`; once its log shows finalized epoch 2 or later, it stops and starts again, must log `restart at slot` of the first slot of an epoch, and must follow again; from fulu, getNetworkIdentity's `custody_group_count` must be the one before the stop (custody.bin).
  - FORK=1, beside lighthouse, CI's fork job: electra at genesis and fulu at epoch 1 (no BPO fork), with 6-second slots; lantern's head must reach slot 40, past the fork.
  - ASSERTOOR=1, beside lighthouse, CI's assertoor job: 6-second slots, and Assertoor v0.1.2 (pinned by digest in tests/kurtosis/main.star) with lantern as its one consensus endpoint and the first geth as its execution endpoint. After lantern follows, Assertoor's test `lantern` must end in success within the wait: lantern ready and synced, its identity, then together the chain at epoch 3, two blocks from its event stream, a proposer duty, finality (2 finalized epochs, at most 3 unfinalized), attestation stats from its committees (95% target, 80% head, over 2 epochs), at most 2 reorgs an epoch, and no fork; then together, through lantern's pool POSTs (SHARD_COMMITTEE_PERIOD 1 in this devnet), two voluntary exits, two BLS to execution changes, a proposer slashing and an attester slashing of validators of ethereum-package's default mnemonic, each awaited until a block of the client includes it, and two epochs of attestations of its validators 128 and 129, which the devnet has (preregistered_validator_count 130) and no validator client runs, from their duties and lantern's produceAttestationData through submitPoolAttestationsV2. Those two vote only so, which is why the target floor is 95%.
  - CHECKPOINT=1, beside lighthouse, CI's checkpoint job: lantern, with `--data-dir` and `--archive` (the backfill's blocks go to its `Db`), starts from lighthouse's finalized block and its post-state, as SSZ from its Beacon API once its finalized epoch is 1 or more, must log `checkpoint at slot`, must follow, and its `earliest slot` must fall below the checkpoint's slot: the backfill takes lighthouse's blocks.

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

### `lantern_app_actions`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_alloc`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_action`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_close`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_due`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_flush`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_note`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_poll`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_read`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_api_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_arg_path`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_base58`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_base64url`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_boot_nodes`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_buf_add`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_buf_drop`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_buf_find`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_buf_grow`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_builder_answer`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_builder_conf`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_builder_due`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_builder_event`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_builder_fail`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_builder_handle`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_builder_request`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_bytes_join`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_categories`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_checkpoint`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_append`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_archive`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_custody`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_drop`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_exists`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_file`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_fit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_history`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_path`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_record`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_scan_all`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_state`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_db_write`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_decimal`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_digits`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_discv5`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_dotted`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_dup`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_dv_datagram`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_dv_put`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_dv_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_engine_conf`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_engine_event`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_engine_handle`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_engine_perform`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_engine_request`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_engine_send`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_event_put`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_fail_status`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_file_free`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_fork`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_grow`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_hex_digit`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_identity_put`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_ipv4`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_key`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_lc_grow`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_no_memory`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_lc_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_base64url`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_clear`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_end`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_hex`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_ip4`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_path`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_text`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_to`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_line_u64`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_log_work`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_loop`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_map`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_answer`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_close`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_delay`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_flush`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_obs`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_poll`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_room`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_send`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_sources`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_us`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_met_work`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_multiaddr`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_name_is`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_net`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_number`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_p2p_events`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_path`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_read`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_regrow`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_space`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_start`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_state_bytes`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_state_cache`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_step`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_store_slot`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_time_text`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_unmap`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_work`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_work_data`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_app_work_entry`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
