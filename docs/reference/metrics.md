# Metrics

Prometheus metrics.

## Contents

### Functions

- [`lantern_metrics_text`](#function-lantern_metrics_text): the Prometheus text of the metrics categories.
- [`lantern_metrics_answer`](#function-lantern_metrics_answer): the HTTP answer to a metrics server's request.
- [`lantern_metrics_observe`](#function-lantern_metrics_observe): a value joins a Histogram.
- [`lantern_metrics_state`](#function-lantern_metrics_state): the head state's values of the metrics.
- [`lantern_metrics_node`](#function-lantern_metrics_node): the node's and store's values of the metrics.
- [`lantern_mt_dec`](#function-lantern_mt_dec): writes the decimal digits of a number.
- [`lantern_mt_histogram`](#function-lantern_mt_histogram): writes the samples of a histogram.
- [`lantern_mt_label`](#function-lantern_mt_label): writes one label of a sample.
- [`lantern_mt_le`](#function-lantern_mt_le): writes the start of a histogram bound's label.
- [`lantern_mt_name`](#function-lantern_mt_name): writes the name of the current table entry.
- [`lantern_mt_open`](#function-lantern_mt_open): writes the start of a sample.
- [`lantern_mt_pair`](#function-lantern_mt_pair): writes a label pair of a sample.
- [`lantern_mt_put`](#function-lantern_mt_put): writes bytes at the cursor.
- [`lantern_mt_sdec`](#function-lantern_mt_sdec): writes a signed decimal number.
- [`lantern_mt_seconds`](#function-lantern_mt_seconds): writes microseconds as seconds.
- [`lantern_mt_text`](#function-lantern_mt_text): writes a text of the metric table.
- [`lantern_mt_ticks_us`](#function-lantern_mt_ticks_us): cPU counter ticks as microseconds.
- [`lantern_mt_topic`](#function-lantern_mt_topic): writes the name of the current entry and the topic label of a GossipTopic.
- [`lantern_mt_value`](#function-lantern_mt_value): writes the end of a sample.

### Types

- [`MetricsState`](#type-metricsstate): the values from the head's post-state.
- [`MetricsNode`](#type-metricsnode): the values from the node and the store.
- [`NodeMetrics`](#type-nodemetrics): the counters and delay histograms the node step keeps.
- [`AppMetrics`](#type-appmetrics): the run time histograms the app keeps.
- [`Histogram`](#type-histogram): the counts of one histogram.
- [`MetricsProcess`](#type-metricsprocess): the process's values.
- [`MetricsGossip`](#type-metricsgossip): gossipsub's values for each topic.
- [`Profile`](#type-profile): the tick rate and tick bounds of the function timers.
- [`MetricEntry`](#type-metricentry): one family of the metric table (include/metrics_table.inc), which lantern_metrics_text writes.
- [`MetricLabel`](#type-metriclabel): a label table of the metric table: a label's name and its values in element order.

## Spec

- Document: [ethereum/beacon-metrics 0af554b](https://github.com/ethereum/beacon-metrics/blob/0af554b0787887887b66e429c373f190b932c223/metrics.md): the metric names, types and Usage texts; an informative spec ("implementations are not required to implement all recommendations").
- Document: [Prometheus text exposition format 0.0.4](https://prometheus.io/docs/instrumenting/exposition_formats/#text-based-format): the text.
- Section: Interop Metrics, PeerDAS Metrics (Data column, kzg, custody metrics), Additional Metrics, Prometheus metrics collection.

## Function `lantern_metrics_text`

The Prometheus text of the metrics of the categories.

### Signature

```
lantern_metrics_text(categories, state, node, counters, app, process, gossip, profile, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `categories` | input | u64: the bits of the sub categories ([`MetricEntry`](#type-metricentry)) |
| `state` | input | [`MetricsState`](#type-metricsstate), or 0 |
| `node` | input | [`MetricsNode`](#type-metricsnode), or 0 |
| `counters` | input | [`NodeMetrics`](#type-nodemetrics), or 0 |
| `app` | input | [`AppMetrics`](#type-appmetrics), or 0 |
| `process` | input | [`MetricsProcess`](#type-metricsprocess), or 0 |
| `gossip` | input | [`MetricsGossip`](#type-metricsgossip), well formed, or 0 |
| `profile` | input | [`Profile`](#type-profile), or 0 |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the text.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has no room for the text.

### Function does

- A source of 0 is not given; its families do not go in.
- Each family of the metric table whose bit is in `categories`, whose source is given and whose condition holds, in the order of the table: `# HELP <name> <help>`, `# TYPE <name> <type>`, then its samples. Every line ends with LF. With no such family: no bytes.
- Conditions: `state`: the `MetricsState` with `present` 1; `altair`: `present` and `altair` 1; `electra`: `present` and `electra` 1; `state_root`: `present` and `state_root_present` 1; `fulu`: the `MetricsNode` with `fulu` 1; `max_fds`: the `MetricsProcess` with `max_fds` above 0; `profile`: the `Profile` with `ticks_per_second` above 0.
- A value (u64 kind): `<name><labels> <value>`, in decimal.
- A root kind: `<name> <value>`, the value a signed decimal.
- A seconds kind: `<name> <seconds>`, the microseconds as `<s>.<six digits>`.
- Labels: with no label table, no labels; else `{<label>="<value>"}`, or `{<label1>="<value1>",<label2>="<value2>"}` with two tables.
- An array kind: one u64 for each pair of label values, the second label's values first: element e at e × 8 has the first label's value e / n2 and the second's e % n2, n2 the second table's value count (1 with one table).
- A histogram (hist kind, or array_hist kind with a Histogram for each element as above): `<name>_bucket{<labels>,le="<bound>"} <n>` for each bound of its bound set, n the values at or below it; `<name>_bucket{<labels>,le="+Inf"} <count>`; `<name>_sum<labels> <seconds>`; `<name>_count<labels> <count>`. With no labels, `{le="<bound>"}` and no braces after `_sum` and `_count`.
- A histogram of the tick bounds: `sum` is in ticks; its seconds are `sum` × 10^6 / `ticks_per_second` microseconds, rounded down; the largest u64 when that is 2^64 or more.
- `gossipsub_mesh_peers_per_main_topic`: `<name>{topic="<topic>"} <mesh_peers>` for each topic with no subnet, in the order of `gossip`.
- `gossipsub_topic_msg_sent_bytes`: `<name>{topic="<topic>",partial="false"} <sent_bytes>` and `<name>{topic="<topic>",partial="true"} <sent_partial_bytes>` for each topic.
- `gossipsub_mesh_peer_counts`: `<name>{topic="<topic>",supports_partial="false"} <mesh_peers - mesh_partial_peers>` and `<name>{topic="<topic>",supports_partial="true"} <mesh_partial_peers>` for each topic.
- A gossipsub family goes in only with a topic for it.

### Function never

- Writes past `out`'s `size`.
- Reads a source whose address is 0.
- Makes an OS call.

### Limits

- Stack of its own: 272 bytes on x86-64 (return address included), 240 bytes on ARM64, 240 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_metrics_text`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `categories`, `state`, `node`, `counters`, `app`, `process`, `gossip`, `profile`, `out`.

## Function `lantern_metrics_answer`

The HTTP answer to the first request in a metrics server connection's bytes; the connection closes after it.

### Signature

```
lantern_metrics_answer(bytes, categories, state, node, counters, app, process, gossip, profile, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | ByteList: the connection's bytes so far |
| `categories` | input | u64: the bits of the sub categories |
| `state` | input | [`MetricsState`](#type-metricsstate), or 0 |
| `node` | input | [`MetricsNode`](#type-metricsnode), or 0 |
| `counters` | input | [`NodeMetrics`](#type-nodemetrics), or 0 |
| `app` | input | [`AppMetrics`](#type-appmetrics), or 0 |
| `process` | input | [`MetricsProcess`](#type-metricsprocess), or 0 |
| `gossip` | input | [`MetricsGossip`](#type-metricsgossip), well formed, or 0 |
| `profile` | input | [`Profile`](#type-profile), or 0 |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the answer.
- `LANTERN_HTTP_MORE`: `bytes` holds no whole request yet.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has fewer than 24 + `HTTP_REQUEST_FIXED` + 64 + `METRICS_HEAD_ROOM` + the bytes' length bytes, or, for a 200, fewer than `METRICS_HEAD_ROOM` + 24 + the text's length.

### Function does

- Reads the request with lantern_http_request ([beacon-api.md](beacon-api.md#function-lantern_http_request)), with `head_max` `METRICS_HEAD_MAX` and `body_max` 0, its `HttpRequest` in `out`'s room.
- The status: the fault's status of `LANTERN_INVALID_HTTP`; else 405 for a method other than GET; else 404 for a `path` other than `/metrics` (the query does not count); else 200.
- 200: `HTTP/1.1 200 OK`, `Content-Type: text/plain; version=0.0.4; charset=utf-8`, `Content-Length: <n>` and `Connection: close`, each line ending with CRLF, an empty line, then the n bytes of lantern_metrics_text of `categories` and `sources`.
- Another status: `HTTP/1.1 <status> <reason>` with the reason phrase of the Beacon API's status table, `Allow: GET` for 405, `Content-Length: 0` and `Connection: close`, then the empty line.

### Function never

- Writes past `out`'s `size`.
- Makes an OS call.

### Limits

- Stack of its own: 240 bytes on x86-64 (return address included), 224 bytes on ARM64, 224 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_metrics_answer`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `bytes`, `categories`, `state`, `node`, `counters`, `app`, `process`, `gossip`, `profile`, `out`.

## Function `lantern_metrics_observe`

A value joins a Histogram of a bound set of microseconds.

### Signature

```
lantern_metrics_observe(histogram, bounds, value) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `histogram` | state | [`Histogram`](#type-histogram) |
| `bounds` | input | u64: `METRIC_BOUNDS_*` of a bound set of microseconds (default, kzg, delay, work) |
| `value` | input | u64: microseconds |

### Returns

- `LANTERN_OK`.

### Function does

- `count` takes 1 more and `sum` the value more, each modulo 2^64; the bucket of the first bound at or above the value takes 1 more, or the one after the last bound when it is above them all.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_metrics_observe`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `histogram`, `bounds`, `value`.

## Function `lantern_metrics_state`

The values of the metrics from a head's post-state and its block, of one fork.

### Signature

```
lantern_metrics_state(state, block, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `state` | input | `BeaconState` of the fork, well formed |
| `block` | input | `ByteList`: the SSZ bytes of the `SignedBeaconBlock` whose post-state `state` is, or no bytes (an anchor) |
| `out` | output | [`MetricsState`](#type-metricsstate) |

### Returns

- `LANTERN_OK`: `out` holds the values, `present` 1.

### Function does

- `slot`, the three checkpoints' epochs and the finalized and previous justified roots as numbers: the state's.
- `deposit_count`: `eth1_data.deposit_count` (Lighthouse v8.3.3).
- `active_validators`: the validators active at get_current_epoch(state).
- `current_validators` and `previous_validators`: at get_current_epoch(state) and get_previous_epoch(state), each validator by status: `pending` with `activation_epoch` above the epoch; `active` with is_active_validator; `exited` with `exit_epoch` at most the epoch and `withdrawable_epoch` above it; `withdrawable` with `withdrawable_epoch` at most the epoch.
- From altair: `altair` 1; `current_live` and `previous_live`: the validators active at the epoch with a flag in `current_epoch_participation` or `previous_epoch_participation`. Phase0 leaves them 0, and the two live metrics out: its live validators need the committees of each pending attestation.
- From electra: `electra` 1, and the entries of `pending_deposits`, `pending_partial_withdrawals` and `pending_consolidations`.
- `state_root_present` 1 and `state_root` the `state_root` of the block's message as a number (bytes 148 to 180 of a `SignedBeaconBlock`), when `block` holds at least 180 bytes; else 0 and 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_<fork>_metrics_state` in the object of every fork, with `_` before it on macOS; `lantern_metrics_state` inside the object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `state`, `block`, `out`.

## Function `lantern_metrics_node`

The values of the metrics from the node and its store.

### Signature

```
lantern_metrics_node(node, store, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `node` | input | `Node` ([node.md](node.md#type-node)), well formed |
| `store` | input | `Store`, the node's |
| `out` | output | [`MetricsNode`](#type-metricsnode) |

### Returns

- `LANTERN_OK`: `out` holds the values.

### Function does

- `peers`: the entries of the peers part.
- `fulu`: 1 when the fork of the store's slot is fulu or later; then `custody_groups`: the node's `custody_count`.
- `pending_exits`: the pool's entries of voluntary_exit.
- `local_validators`: the `NodeProposer` entries whose `until_epoch` is above the store's epoch: the validators whose validator client gave this node prepareBeaconProposer and still holds (Prysm's tracked validators).
- `orphaned_blocks`: the blocks of the node with status `NODE_BLOCK_IMPORTED` and a slot in the store's previous epoch (get_previous_epoch: one less than the store's, not below 0) that are not on the head's chain: the head and its ancestors by `parent_root`, up to the first one below that epoch, the first root the node holds no block of, or 2 × `SLOTS_PER_EPOCH` blocks.
- `sync_state`: 1 when the head's slot + 1 is at least the store's slot; else 2 with `NODE_FLAG_SYNCING`; else 0 when a peer with `NODE_PEER_STATUS` and the node's `fork_digest` has a `head_slot` above the head's slot + 1, or no such peer has a Status; else 1. With no block of `head_root` the head's slot counts as 0.
- The case: slots with no block leave the head behind the store's slot while no peer has a later block; the sync asks only for blocks a peer's Status shows (node.md, the sync), so the node is synced then (Hoodi, 2026-11-24: one missed slot gave 0).
- `head_block_id` and `head_state_id`: the `data_id` and `state_id` of the `NodeBlock` of the node's `head_root`; 0 and 0 with none. The caller gives their buffers to lantern_<fork>_metrics_state.
- `pending_exits` and `pool`: the pool's entries, those of voluntary_exit, and those of each topic 1 to 13 at its topic's element.
- `peer_directions`, `dialing`, `messages` and `streams`: from the peers part by direction, `dialing`, and the entries of the messages and streams parts.
- `head_slot`, `store_slot` and `distance`: the head block's slot (0 with none), the store's slot, and `store_slot` - `head_slot` when above 0, else 0.
- `earliest_slot`, `backfill_slot`, `finalized_epoch` and `justified_epoch`: the node's, and the store's checkpoints' epochs.

### Function never

- Makes an OS call.

### Limits

- Stack of its own with the mainnet preset: 624 bytes on x86-64 (return address included), 608 bytes on ARM64, 608 bytes on RISC-V.
- Stack of its own with the minimal preset: 240 bytes on x86-64 (return address included), 224 bytes on ARM64, 224 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_metrics_node`, with `_` before it on macOS.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `node`, `store`, `out`.

## Function `lantern_mt_dec`

Writes the decimal digits of a number.

### Signature

```
lantern_mt_dec(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | u64 in a register |

### Function does

- Writes the decimal digits of `value` at the cursor.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_dec`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9 to x15; rax, rcx, rdx, rsi, rdi, r8; a0, a1, t0 to t5.
- Argument order: `value`.

## Function `lantern_mt_histogram`

Writes the samples of a histogram.

### Signature

```
lantern_mt_histogram(histogram, bounds, labels, rate)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `histogram` | input | [`Histogram`](#type-histogram) |
| `bounds` | input | the bound set's record |
| `labels` | input | the LabelState of the family |
| `rate` | input | u64 in a register: the ticks per second, for a set of ticks |

### Function does

- Writes a `_bucket` sample for each bound with `le`, then `_sum` and `_count`, with the family's labels.
- Writes the bounds and the sum in seconds; a set of ticks is turned into microseconds with `rate` first (lantern_mt_ticks_us).

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 64 bytes on x86-64 (return address included), 64 bytes on ARM64, 64 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_histogram`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Registers it reads, on ARM64, x86-64, RISC-V: the table entry in x23, r14, s5.
- Argument order: `histogram`, `bounds`, `labels`, `rate`.

## Function `lantern_mt_label`

Writes one label of a sample.

### Signature

```
lantern_mt_label(table, index)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `table` | input | [`MetricLabel`](#type-metriclabel): a label table's record |
| `index` | input | u64 in a register: the value index |

### Function does

- Writes `name="value"` of the label table and the value.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_label`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Argument order: `table`, `index`.

## Function `lantern_mt_le`

Writes the start of a histogram bound's label.

### Signature

```
lantern_mt_le(first)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `first` | input | u64 in a register: 0 for the first label |

### Function does

- Writes `{` when `first` is 0, else `,`; then `le="`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 16 bytes on x86-64 (return address included), 16 bytes on ARM64, 16 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_le`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Registers it changes, on x86-64: rax, rcx, rsi, rdi.
- Argument order: `first`.

## Function `lantern_mt_name`

Writes the name of the current table entry.

### Signature

```
lantern_mt_name()
```

### Function does

- Writes the name of the entry.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_name`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Registers it reads, on ARM64, x86-64, RISC-V: the table entry in x23, r14, s5.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9, x10; rax, rcx, rsi, rdi; a0, a1, t0, t1.

## Function `lantern_mt_open`

Writes the start of a sample.

### Signature

```
lantern_mt_open(suffix, length, labels) -> brace
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `suffix` | input | `length` bytes, or none |
| `length` | input | u64 in a register: 0 for no suffix |
| `labels` | input | the LabelState of the family |

### Function does

- Writes the entry's name, the suffix, then `{` and the labels when the LabelState has a label.
- Returns 1 when a `{` went out, else 0.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_open`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Registers it reads, on ARM64, x86-64, RISC-V: the table entry in x23, r14, s5.
- Argument order: `suffix`, `length`, `labels`.

## Function `lantern_mt_pair`

Writes a label pair of a sample.

### Signature

```
lantern_mt_pair(name, name_length, value, value_length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `name` | input | `name_length` bytes |
| `name_length` | input | u64 in a register |
| `value` | input | `value_length` bytes |
| `value_length` | input | u64 in a register |

### Function does

- Writes `,<name>="<value>"`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_pair`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Argument order: `name`, `name_length`, `value`, `value_length`.

## Function `lantern_mt_put`

Writes bytes at the cursor.

### Signature

```
lantern_mt_put(bytes, n)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | `n` bytes |
| `n` | input | u64 in a register |

### Function does

- Copies the bytes to the cursor and moves it, when they fit in the room; else sets the full flag.

### Function never

- Calls another function.
- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_put`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9, x10; rax, rcx, rsi, rdi; a0, a1, t0, t1.
- Argument order: `bytes`, `n`.

## Function `lantern_mt_sdec`

Writes a signed decimal number.

### Signature

```
lantern_mt_sdec(value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `value` | input | i64 in a register |

### Function does

- Writes `-` for a negative value, then its decimal digits.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_sdec`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Argument order: `value`.

## Function `lantern_mt_seconds`

Writes microseconds as seconds.

### Signature

```
lantern_mt_seconds(us)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `us` | input | u64 in a register: microseconds |

### Function does

- Writes the whole seconds, `.`, then six digits.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 48 bytes on x86-64 (return address included), 48 bytes on ARM64, 48 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_seconds`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Argument order: `us`.

## Function `lantern_mt_text`

Writes a text of the metric table.

### Signature

```
lantern_mt_text(offset, length)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `offset` | input | u32 in a register: its offset in `metrics_texts` |
| `length` | input | u64 in a register |

### Function does

- Writes the `length` bytes at `metrics_texts` + `offset`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 8 bytes on x86-64 (return address included), 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_text`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Registers it reads, on ARM64: `metrics_texts` in x19.
- Registers it changes, on ARM64, x86-64, RISC-V: x0, x1, x9, x10; rax, rcx, rsi, rdi; a0, a1, t0, t1.
- Argument order: `offset`, `length`.

## Function `lantern_mt_ticks_us`

CPU counter ticks as microseconds.

### Signature

```
lantern_mt_ticks_us(ticks, rate) -> us
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `ticks` | input | u64 in a register |
| `rate` | input | u64 in a register: ticks per second |

### Function does

- Returns `ticks` * 10^6 / `rate` by long division of the 128-bit product, the largest u64 when the quotient does not fit, and 0 when `rate` is 0.

### Function never

- Calls another function.
- Writes memory.
- Makes an OS call.

### Limits

- Stack of its own: 0 bytes on ARM64, 0 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_ticks_us`, local to its object. Only ARM64 and RISC-V have it.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it changes, on ARM64 and RISC-V: x0, x9 to x14; a0, t0 to t5.
- Argument order: `ticks`, `rate`.

## Function `lantern_mt_topic`

Writes the name of the current entry and the topic label of a GossipTopic.

### Signature

```
lantern_mt_topic(topic)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `topic` | input | `GossipTopic` of `MetricsGossip` |

### Function does

- Writes the entry's name and `{topic="<name>"`.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_topic`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Registers it reads, on ARM64, x86-64, RISC-V: the table entry in x23, r14, s5.
- Argument order: `topic`.

## Function `lantern_mt_value`

Writes the end of a sample.

### Signature

```
lantern_mt_value(brace, value)
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `brace` | input | u64 in a register: 1 when a `{` went out |
| `value` | input | u64 in a register |

### Function does

- Writes `}` when `brace` is 1, then a space, the decimal `value` and LF.

### Function never

- Makes an OS call.

### Limits

- Stack of its own: 32 bytes on x86-64 (return address included), 32 bytes on ARM64, 32 bytes on RISC-V.

### ABI

- Role: L0.
- Symbol: `lantern_mt_value`, local to its object.
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Registers it uses, on ARM64, x86-64, RISC-V: the cursor in x20, r12, s2; the end of the room in x21, r13, s3; the full flag in x22, r15, s4, which becomes 1 when the room runs out, and nothing is written from then on.
- Argument order: `brace`, `value`.

## Type `MetricsState`

The values of the metrics from the head's post-state.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `present` | u64 | 1 when the values are a state's, else 0 |
| 8 | `slot` | u64 | |
| 16 | `finalized_epoch` | u64 | |
| 24 | `current_justified_epoch` | u64 | |
| 32 | `previous_justified_epoch` | u64 | |
| 40 | `active_validators` | u64 | |
| 48 | `deposit_count` | u64 | |
| 56 | `finalized_root` | i64 | The root as a number |
| 64 | `previous_justified_root` | i64 | The root as a number |
| 72 | `current_validators` | u64 x 4 | By status, in the status order |
| 104 | `previous_validators` | u64 x 4 | By status |
| 136 | `current_live` | u64 | |
| 144 | `previous_live` | u64 | |
| 152 | `altair` | u64 | 1 from altair, else 0 |
| 160 | `electra` | u64 | 1 from electra, else 0 |
| 168 | `pending_deposits` | u64 | |
| 176 | `pending_partial_withdrawals` | u64 | |
| 184 | `pending_consolidations` | u64 | |
| 192 | `state_root_present` | u64 | 1 when the block gave `state_root`, else 0 |
| 200 | `state_root` | i64 | The state's root as a number |
| 208 | | | Size |

## Type `MetricsNode`

The values of the metrics from the node and the store.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `peers` | u64 | Entries of the peers part |
| 8 | `fulu` | u64 | 1 from fulu, else 0 |
| 16 | `custody_groups` | u64 |  |
| 24 | `pending_exits` | u64 |  |
| 32 | `local_validators` | u64 |  |
| 40 | `orphaned_blocks` | u64 |  |
| 48 | `sync_state` | u64 | 0 behind, 1 synced, 2 syncing |
| 56 | `head_block_id` | u64 | `BufferId` of the head's `SignedBeaconBlock` bytes, or 0 |
| 64 | `head_state_id` | u64 | `BufferId` of the head's post-state, or 0 |
| 72 | `peer_directions` | u64 x 2 | Peers by `NodePeer.direction`: inbound, outbound |
| 88 | `dialing` | u64 | `Node.dialing` |
| 96 | `head_slot` | u64 | The head block's slot, or 0 |
| 104 | `store_slot` | u64 | The store's slot |
| 112 | `distance` | u64 | `store_slot` - `head_slot`, or 0 |
| 120 | `earliest_slot` | u64 | `Node.earliest_slot` |
| 128 | `backfill_slot` | u64 | `Node.backfill_slot` |
| 136 | `finalized_epoch` | u64 | The store's finalized checkpoint's epoch |
| 144 | `justified_epoch` | u64 | The store's justified checkpoint's epoch |
| 152 | `messages` | u64 | Entries of the messages part |
| 160 | `streams` | u64 | Entries of the streams part |
| 168 | `pool` | u64 x 14 | Pool entries by `topic`, the topic numbers 1 to 13; element 0 stays 0 |
| 280 | | | Size |

## Type `NodeMetrics`

The counters of the metrics that the node step keeps, in the node's fixed fields ([node.md](node.md#type-node), `metrics`).

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `reorgs` | u64 | Head changes off the old head's chain |
| 8 | `attestations_published` | u64 | Attestations of submitPoolAttestationsV2 that went out on their topic |
| 16 | | | Size |

## Type `AppMetrics`

The counters and run time histograms of the metrics that the app keeps (app.md, the metrics), from the works it runs, the events it gives the node and the actions it performs.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `gossip_verification` | [`Histogram`](#type-histogram) | Run times of GOSSIP works of data_column_sidecar, default bounds |
| 112 | `reconstruction` | [`Histogram`](#type-histogram) | Run times of RECONSTRUCT works, default bounds |
| 224 | `computation` | [`Histogram`](#type-histogram) | Run times of PUBLISH_SIDECARS works, default bounds |
| 336 | `kzg_batch` | [`Histogram`](#type-histogram) | Run times of BLOB works of a column sidecar (arg 1), KZG bounds |
| 448 | `attestation_delay` | [`Histogram`](#type-histogram) | For each valid beacon_attestation, the store's time less its slot's start, delay bounds |
| 560 | `block_delay` | [`Histogram`](#type-histogram) | For each valid beacon_block, the same |
| 672 | `column_requests` | u64 | GOSSIP works of data_column_sidecar |
| 680 | `column_successes` | u64 | Those of LANTERN_VALID |
| 688 | `reconstructed_columns` | u64 | For each RECONSTRUCT of LANTERN_VALID, NUMBER_OF_COLUMNS less the ByteLists of its data |
| 696 | `aggregates_received` | u64 | GOSSIP works of beacon_aggregate_and_proof |
| 704 | `attestations_received` | u64 | GOSSIP works of beacon_attestation |
| 712 | `attester_slashings_received` | u64 | GOSSIP works of attester_slashing |
| 720 | `blocks_proposed` | u64 | PUBLISH_CHECK works of LANTERN_VALID |
| 728 | `gossip_blocks_imported` | u64 | GOSSIP works of beacon_block of LANTERN_VALID |
| 736 | `validation_failures` | u64 | GOSSIP works of LANTERN_GOSSIP_REJECT |
| 744 | `api_requests` | u64 | NODE_EV_API events |
| 752 | `api_successes` | u64 | Answers whose status is 2xx |
| 760 | `connections` | u64 x 2 | ACCEPTED, then CONNECTED events of the libp2p shell for the node |
| 776 | `dial_failures` | u64 | DIAL_FAILED events |
| 784 | `closed` | u64 | CLOSED events |
| 792 | `records` | u64 | Records discv5 found (NODE_FOUND) |
| 800 | `lookups` | u64 | NODE_ACT_DISCV5 actions |
| 808 | `dv_in` | u64 | Datagrams of discv5 received |
| 816 | `dv_out` | u64 | Datagrams discv5 sent |
| 824 | `dv_failures` | u64 | discv5 steps that failed |
| 832 | `rx_bytes` | u64 | Bytes of RECEIVED events |
| 840 | `tx_bytes` | u64 | Bytes of SENT events |
| 848 | `gossip_results` | u64 x 42 | GOSSIP works by `topic` and `result` |
| 1184 | `served` | u64 x 16 | SERVE works by `method` |
| 1312 | `work_seconds` | [`Histogram`](#type-histogram) x 44 | Run time of each work, by the kind's slot (`METRIC_WORK_SLOTS`), work bounds |
| 6240 | `work_failures` | u64 x 44 | Works of a result other than LANTERN_OK, by slot |
| 6592 | `epoch_transitions` | u64 | SLOTS works to, and IMPORT_BLOCK works of a block in, a later epoch than their state's slot |
| 6600 | `epoch_seconds` | [`Histogram`](#type-histogram) | Their run times, work bounds |
| 6712 | `gossip_seconds` | [`Histogram`](#type-histogram) x 14 | Run times of GOSSIP works by `topic`, work bounds |
| 8280 | `step_seconds` | [`Histogram`](#type-histogram) | Run time of each lantern_node_step, work bounds |
| 8392 | `log_lines` | u64 x 4 | Log lines written, by `level` |
| 8424 | `api_classes` | u64 x 4 | Answers by `class`: the status's first digit 2 to 5 |
| 8456 | `db_records` | u64 x 3 | NODE_ACT_DB_APPEND by `kind` (block, sidecar), NODE_ACT_DB_ARCHIVE (state) |
| 8480 | `db_bytes` | u64 x 3 | Bytes of the appended records' buffers, by `kind` |
| 8504 | `db_anchors` | u64 | anchor.ssz files written (app.md, `NODE_ACT_DB_STATE`) |
| 8512 | `db_drops` | u64 | NODE_ACT_DB_DROP actions |
| 8520 | `db_failures` | u64 | Writes to the data directory that failed (a cannot write line) |
| 8528 | `anchor_seconds` | [`Histogram`](#type-histogram) | Run time of each anchor.ssz write, from lantern_node_state_bytes to the synced directory, default bounds |
| 8640 | | | Size |

## Type `Histogram`

The counts of one histogram.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `count` | u64 | The values |
| 8 | `sum` | u64 | Their sum, in microseconds; in ticks for the tick bounds |
| 16 | `buckets` | u64 x 12 | Entry i: the values above bound i - 1 and at most bound i; the entry after the last bound: those above it |
| 112 | | | Size |

### Rules

- A value goes in the first bucket whose bound it does not pass, `count` takes 1 more and `sum` the value more.

## Type `MetricsProcess`

The process's values.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `cpu_us` | u64 | User and system CPU time, in microseconds |
| 8 | `max_fds` | u64 | The soft limit of open files, or 0 for none |
| 16 | `max_rss_bytes` | u64 | The highest resident memory since the start |
| 24 | `buffers` | u64 | Entries of the app's BufferId table |
| 32 | `buffer_bytes` | u64 | Their bytes |
| 40 | `start_s` | u64 | The Unix time of the start, in seconds |
| 48 | `uptime_us` | u64 | Microseconds since the start |
| 56 | `engine` | u64 | 0 no execution engine connection, 1 dialing, 2 open |
| 64 | `api_open` | u64 | Beacon API connections open |
| 72 | | | Size |

## Type `MetricsGossip`

gossipsub's values for each topic: a value with one part, of `GossipTopic` entries.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `size` | u64 | |
| 8 | `topics` | PartRef | `GossipTopic` entries |
| 24 | | | Fixed size |

`GossipTopic`:

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `name_length` | u64 | At most 64 |
| 8 | `name` | 64 bytes | The topic's name |
| 72 | `subnet` | u64 | 1 for a topic of a subnet, else 0 |
| 80 | `mesh_peers` | u64 | |
| 88 | `mesh_partial_peers` | u64 | Those that support partial messages |
| 96 | `sent_bytes` | u64 | Bytes of whole messages published to it |
| 104 | `sent_partial_bytes` | u64 | Bytes of partial messages |
| 112 | | | Size |

## Type `Profile`

The tick rate and the tick bounds of the function timers. The core reads the CPU's counter at the start and end of a timed function (`rdtsc` on x86-64, `cntvct_el0` on ARM64, `rdtime` on RISC-V) and adds the ticks to the function's Histogram.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `ticks_per_second` | u64 | The counter's ticks in one second, or 0 when not known |
| 8 | `bounds` | u64 x 11 | The tick bounds in ticks: bound i's seconds × `ticks_per_second`, rounded |
| 96 | | | Size |

### Rules

- The app finds `ticks_per_second` against its clock and writes `bounds` before the first timed function.

## Type `MetricEntry`

One family of the metric table (include/metrics_table.inc), which lantern_metrics_text writes.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `name` | u32 | Offset of the name in `metrics_texts` |
| 4 | `name_len` | u32 | Bytes of the name |
| 8 | `help` | u32 | Offset of the HELP text in `metrics_texts` |
| 12 | `help_len` | u32 | Bytes of the HELP text |
| 16 | `type` | u32 | `METRIC_TYPE_*`: gauge, counter or histogram |
| 20 | `source` | u32 | `METRIC_SRC_*`: the source of its values |
| 24 | `offset` | u32 | The place of its value in the source |
| 28 | `kind` | u16 | `METRIC_KIND_*`: how the value is read |
| 30 | `cond` | u16 | `METRIC_COND_*`: when the family is written |
| 32 | `bit` | u32 | `METRIC_BIT_*`: its sub category |
| 36 | `label1` | u16 | Its first label table, or 0 |
| 38 | `label2` | u16 | Its second label table, or 0 |
| 40 | `bounds` | u32 | `METRIC_BOUNDS_*`: its bound set, or 0 |
| 44 | `count` | u32 | Its series: the product of the value counts of its label tables |

### Rules

- Category `beacon`: sub categories by bit: none, bit 0.
- Category `network`: sub categories by bit: `peer` 1, `discovery` 2, `transport` 3, `gossip` 4, `reqresp` 5.
- Category `processing`: sub categories by bit: `block` 8, `epoch` 9, `state` 10, `forkchoice` 11, `availability` 12, `gossip` 13, `engine` 14, `builder` 15, `lightclient` 16, `history` 17, `validator` 18.
- Category `node`: sub categories by bit: `resource` 24, `sync` 25, `health` 26, `pool` 27, `log` 28, `api` 29, `storage` 30.
- `beacon`: the metrics of ethereum/beacon-metrics that lantern has a source for, by their names there.
- `network`: what lantern's peers, discovery, connections, gossipsub and requests do.
- `processing`: the work on data, by stage: its counts, failures and run times, down to single functions.
- `node`: the process and the node as a whole: its resources, sync, health, pools, log, Beacon API and database.
- The metrics of a sub category are named `lantern_<category>_<sub>_<measure>`; those of `beacon` keep beacon-metrics' names.
- A category is a set of metrics a node may expose. The `beacon` category holds the metrics of the table below, in that order: those of beacon-metrics that lantern has a source for.
- The table (include/metrics_table.inc) holds every family of every category, in the order of the text; tests/generator/metrics.py writes it and include/metrics.inc from its lists.
- Each family has a source: the head's post-state (`MetricsState`), the node and the store (`MetricsNode`), the node step's counters (`NodeMetrics`), the app (`AppMetrics`, `MetricsProcess`), gossipsub (`MetricsGossip`) or the function timers (`Profile`).
- A root as a number: bytes 24 to 32 of the root as a little-endian signed 64-bit integer (beacon-metrics: `int.from_bytes(root[24:32], byteorder='little', signed=True)`).
- `libp2p_peers`: category `beacon`, gauge, from `MetricsNode.peers`.
- `beacon_head_slot`: category `beacon`, gauge, from `MetricsState.slot`.
- `beacon_finalized_epoch`: category `beacon`, gauge, from `MetricsState.finalized_epoch`.
- `beacon_current_justified_epoch`: category `beacon`, gauge, from `MetricsState.current_justified_epoch`.
- `beacon_previous_justified_epoch`: category `beacon`, gauge, from `MetricsState.previous_justified_epoch`.
- `beacon_current_active_validators`: category `beacon`, gauge, from `MetricsState.active_validators`.
- `beacon_reorgs_total`: category `beacon`, counter, from `NodeMetrics.reorgs`.
- `beacon_processed_deposits_total`: category `beacon`, gauge, from `MetricsState.deposit_count`.
- `beacon_data_column_sidecar_processing_requests_total`: category `beacon`, counter, from `AppMetrics.column_requests`.
- `beacon_data_column_sidecar_processing_successes_total`: category `beacon`, counter, from `AppMetrics.column_successes`.
- `beacon_data_column_sidecar_gossip_verification_seconds`: category `beacon`, histogram, from `AppMetrics.gossip_verification`, default bounds.
- `beacon_data_availability_reconstructed_columns_total`: category `beacon`, counter, from `AppMetrics.reconstructed_columns`.
- `beacon_data_availability_reconstruction_time_seconds`: category `beacon`, histogram, from `AppMetrics.reconstruction`, default bounds.
- `beacon_data_column_sidecar_computation_seconds`: category `beacon`, histogram, from `AppMetrics.computation`, default bounds.
- `beacon_kzg_verification_data_column_batch_seconds`: category `beacon`, histogram, from `AppMetrics.kzg_batch`, kzg bounds.
- `beacon_custody_groups`: category `beacon`, gauge, from `MetricsNode.custody_groups`.
- `beacon_current_validators`: category `beacon`, gauge, from `MetricsState.current_validators`, by `status`.
- `beacon_previous_validators`: category `beacon`, gauge, from `MetricsState.previous_validators`, by `status`.
- `beacon_current_live_validators`: category `beacon`, gauge, from `MetricsState.current_live`.
- `beacon_previous_live_validators`: category `beacon`, gauge, from `MetricsState.previous_live`.
- `beacon_pending_deposits`: category `beacon`, gauge, from `MetricsState.pending_deposits`.
- `beacon_pending_partial_withdrawals`: category `beacon`, gauge, from `MetricsState.pending_partial_withdrawals`.
- `beacon_pending_consolidations`: category `beacon`, gauge, from `MetricsState.pending_consolidations`.
- `beacon_pending_exits`: category `beacon`, gauge, from `MetricsNode.pending_exits`.
- `beacon_previous_epoch_orphaned_blocks`: category `beacon`, gauge, from `MetricsNode.orphaned_blocks`.
- `gossipsub_mesh_peers_per_main_topic`: category `beacon`, gauge, from `MetricsGossip`: `mesh_peers` of each topic with no subnet, by `topic`.
- `beacon_attestation_delay_count`: category `beacon`, histogram, from `AppMetrics.attestation_delay`, delay bounds.
- `local_validator_count`: category `beacon`, gauge, from `MetricsNode.local_validators`.
- `beacon_head_state_finalized_root`: category `beacon`, gauge, from `MetricsState.finalized_root`.
- `beacon_previous_justified_root`: category `beacon`, gauge, from `MetricsState.previous_justified_root`.
- `beacon_aggregates_received_total`: category `beacon`, gauge, from `AppMetrics.aggregates_received`.
- `beacon_block_delay_count`: category `beacon`, histogram, from `AppMetrics.block_delay`, delay bounds.
- `beacon_attestor_slashing_received_total`: category `beacon`, gauge, from `AppMetrics.attester_slashings_received`.
- `beacon_block_proposed_total`: category `beacon`, gauge, from `AppMetrics.blocks_proposed`.
- `beacon_attestations_published_total`: category `beacon`, gauge, from `NodeMetrics.attestations_published`.
- `beacon_processor_gossip_block_imported_total`: category `beacon`, gauge, from `AppMetrics.gossip_blocks_imported`.
- `libp2p_pubsub_validation_failure_total`: category `beacon`, gauge, from `AppMetrics.validation_failures`.
- `beacon_head_state_root`: category `beacon`, gauge, from `MetricsState.state_root`.
- `beacon_attestations_received_total`: category `beacon`, gauge, from `AppMetrics.attestations_received`.
- `beacon_http_api_requests_total`: category `beacon`, gauge, from `AppMetrics.api_requests`.
- `beacon_http_api_successes_total`: category `beacon`, gauge, from `AppMetrics.api_successes`.
- `beacon_sync_state`: category `beacon`, gauge, from `MetricsNode.sync_state`.
- `process_cpu_seconds_total`: category `beacon`, gauge, from `MetricsProcess.cpu_us`, in seconds.
- `process_max_fds`: category `beacon`, gauge, from `MetricsProcess.max_fds`.
- `gossipsub_topic_msg_sent_bytes`: category `beacon`, counter, from `MetricsGossip`: `sent_bytes` and `sent_partial_bytes` of each topic, by `topic` and `partial`.
- `gossipsub_mesh_peer_counts`: category `beacon`, gauge, from `MetricsGossip`: mesh peers of each topic by `topic` and `supports_partial`.
- Each metric's HELP text is the Usage text of beacon-metrics, and its type the Metric type there.
- Tick bounds (the function timers of `Profile`): 0.000001, 0.000004, 0.000016, 0.000064, 0.000256, 0.001, 0.004, 0.016, 0.064, 0.256, 1.
- Default bounds (Prometheus's, as Lighthouse v8.3.3 uses for these): 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10.
- KZG bounds (Lighthouse v8.3.3, `exponential_buckets(0.002, 2.0, 10)`): 0.002, 0.004, 0.008, 0.016, 0.032, 0.064, 0.128, 0.256, 0.512, 1.024.
- Delay bounds (beacon-metrics sets none: "bucket size yet to be decided"): 0.5, 1, 2, 3, 4, 6, 8, 12, 24.
- `status`, in this order: `pending`, `active`, `exited`, `withdrawable`.
- `lantern_network_peer_connected`: category `network`, sub category `peer`, gauge, from `MetricsNode.peers`: connected peers.
- `lantern_network_peer_direction`: category `network`, sub category `peer`, gauge, from `MetricsNode.peer_directions`, by `direction`: connected peers by the direction of their connection.
- `lantern_network_peer_dialing`: category `network`, sub category `peer`, gauge, from `MetricsNode.dialing`: dials of the node not yet connected or failed.
- `lantern_network_peer_connections_total`: category `network`, sub category `peer`, counter, from `AppMetrics.connections`, by `direction`: connections made, by direction.
- `lantern_network_peer_dial_failures_total`: category `network`, sub category `peer`, counter, from `AppMetrics.dial_failures`: dials that failed.
- `lantern_network_peer_disconnections_total`: category `network`, sub category `peer`, counter, from `AppMetrics.closed`: connections that closed.
- `lantern_network_discovery_records_total`: category `network`, sub category `discovery`, counter, from `AppMetrics.records`: node records discv5 found and gave to the node.
- `lantern_network_discovery_lookups_total`: category `network`, sub category `discovery`, counter, from `AppMetrics.lookups`: lookups the node asked discv5 for.
- `lantern_network_discovery_datagrams_received_total`: category `network`, sub category `discovery`, counter, from `AppMetrics.dv_in`: uDP datagrams discv5 received.
- `lantern_network_discovery_datagrams_sent_total`: category `network`, sub category `discovery`, counter, from `AppMetrics.dv_out`: uDP datagrams discv5 sent.
- `lantern_network_discovery_step_failures_total`: category `network`, sub category `discovery`, counter, from `AppMetrics.dv_failures`: discv5 steps that failed.
- `lantern_network_transport_received_bytes_total`: category `network`, sub category `transport`, counter, from `AppMetrics.rx_bytes`: bytes received on libp2p connections.
- `lantern_network_transport_sent_bytes_total`: category `network`, sub category `transport`, counter, from `AppMetrics.tx_bytes`: bytes sent on libp2p connections.
- `lantern_network_gossip_messages_total`: category `network`, sub category `gossip`, counter, from `AppMetrics.gossip_results`, by `topic` and `result`: gossip messages validated, by topic and result.
- `lantern_network_gossip_messages_held`: category `network`, sub category `gossip`, gauge, from `MetricsNode.messages`: gossip messages the node holds.
- `lantern_network_reqresp_served_total`: category `network`, sub category `reqresp`, counter, from `AppMetrics.served`, by `method`: requests of peers the node served, by method.
- `lantern_network_reqresp_streams_open`: category `network`, sub category `reqresp`, gauge, from `MetricsNode.streams`: request streams open.
- `lantern_processing_block_work_seconds`: category `processing`, sub category `block`, histogram, from `AppMetrics.work_seconds`, by `work`, work bounds: run time of each node work of the block stage, by work kind.
- `lantern_processing_block_work_failures_total`: category `processing`, sub category `block`, counter, from `AppMetrics.work_failures`, by `work`: node works of the block stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_state_work_seconds`: category `processing`, sub category `state`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 5, work bounds: run time of each node work of the state stage, by work kind.
- `lantern_processing_state_work_failures_total`: category `processing`, sub category `state`, counter, from `AppMetrics.work_failures`, by `work`, from element 5: node works of the state stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_forkchoice_work_seconds`: category `processing`, sub category `forkchoice`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 9, work bounds: run time of each node work of the forkchoice stage, by work kind.
- `lantern_processing_forkchoice_work_failures_total`: category `processing`, sub category `forkchoice`, counter, from `AppMetrics.work_failures`, by `work`, from element 9: node works of the forkchoice stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_availability_work_seconds`: category `processing`, sub category `availability`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 12, work bounds: run time of each node work of the availability stage, by work kind.
- `lantern_processing_availability_work_failures_total`: category `processing`, sub category `availability`, counter, from `AppMetrics.work_failures`, by `work`, from element 12: node works of the availability stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_gossip_work_seconds`: category `processing`, sub category `gossip`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 15, work bounds: run time of each node work of the gossip stage, by work kind.
- `lantern_processing_gossip_work_failures_total`: category `processing`, sub category `gossip`, counter, from `AppMetrics.work_failures`, by `work`, from element 15: node works of the gossip stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_engine_work_seconds`: category `processing`, sub category `engine`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 16, work bounds: run time of each node work of the engine stage, by work kind.
- `lantern_processing_engine_work_failures_total`: category `processing`, sub category `engine`, counter, from `AppMetrics.work_failures`, by `work`, from element 16: node works of the engine stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_builder_work_seconds`: category `processing`, sub category `builder`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 21, work bounds: run time of each node work of the builder stage, by work kind.
- `lantern_processing_builder_work_failures_total`: category `processing`, sub category `builder`, counter, from `AppMetrics.work_failures`, by `work`, from element 21: node works of the builder stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_lightclient_work_seconds`: category `processing`, sub category `lightclient`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 22, work bounds: run time of each node work of the lightclient stage, by work kind.
- `lantern_processing_lightclient_work_failures_total`: category `processing`, sub category `lightclient`, counter, from `AppMetrics.work_failures`, by `work`, from element 22: node works of the lightclient stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_history_work_seconds`: category `processing`, sub category `history`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 27, work bounds: run time of each node work of the history stage, by work kind.
- `lantern_processing_history_work_failures_total`: category `processing`, sub category `history`, counter, from `AppMetrics.work_failures`, by `work`, from element 27: node works of the history stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_validator_work_seconds`: category `processing`, sub category `validator`, histogram, from `AppMetrics.work_seconds`, by `work`, from element 30, work bounds: run time of each node work of the validator stage, by work kind.
- `lantern_processing_validator_work_failures_total`: category `processing`, sub category `validator`, counter, from `AppMetrics.work_failures`, by `work`, from element 30: node works of the validator stage whose result was not LANTERN_OK, by work kind.
- `lantern_processing_epoch_transitions_total`: category `processing`, sub category `epoch`, counter, from `AppMetrics.epoch_transitions`: block imports and slot processing works that crossed an epoch boundary.
- `lantern_processing_epoch_transition_seconds`: category `processing`, sub category `epoch`, histogram, from `AppMetrics.epoch_seconds`, work bounds: run time of each block import or slot processing work that crossed an epoch boundary.
- `lantern_processing_gossip_validation_seconds`: category `processing`, sub category `gossip`, histogram, from `AppMetrics.gossip_seconds`, by `topic`, work bounds: run time of each gossip validation, by topic.
- `lantern_node_resource_cpu_seconds_total`: category `node`, sub category `resource`, counter, from `MetricsProcess.cpu_us`, in seconds: user and system CPU time.
- `lantern_node_resource_max_resident_memory_bytes`: category `node`, sub category `resource`, gauge, from `MetricsProcess.max_rss_bytes`: highest resident memory since the start.
- `lantern_node_resource_max_fds`: category `node`, sub category `resource`, gauge, from `MetricsProcess.max_fds`; condition `max_fds`: the soft limit of open files.
- `lantern_node_resource_buffers`: category `node`, sub category `resource`, gauge, from `MetricsProcess.buffers`: buffers the app holds for the node.
- `lantern_node_resource_buffer_bytes`: category `node`, sub category `resource`, gauge, from `MetricsProcess.buffer_bytes`: bytes of those buffers.
- `lantern_node_resource_start_time_seconds`: category `node`, sub category `resource`, gauge, from `MetricsProcess.start_s`: unix time of the start.
- `lantern_node_sync_head_slot`: category `node`, sub category `sync`, gauge, from `MetricsNode.head_slot`: slot of the head block.
- `lantern_node_sync_store_slot`: category `node`, sub category `sync`, gauge, from `MetricsNode.store_slot`: slot of the store's time.
- `lantern_node_sync_distance`: category `node`, sub category `sync`, gauge, from `MetricsNode.distance`: slots from the head to the store's slot.
- `lantern_node_sync_state`: category `node`, sub category `sync`, gauge, from `MetricsNode.sync_state`: 0 behind and not syncing, 1 synced, 2 syncing.
- `lantern_node_sync_earliest_slot`: category `node`, sub category `sync`, gauge, from `MetricsNode.earliest_slot`: first slot whose blocks the node serves.
- `lantern_node_sync_backfill_slot`: category `node`, sub category `sync`, gauge, from `MetricsNode.backfill_slot`: slot below which the backfill looks for blocks.
- `lantern_node_sync_finalized_epoch`: category `node`, sub category `sync`, gauge, from `MetricsNode.finalized_epoch`: the store's finalized epoch.
- `lantern_node_sync_justified_epoch`: category `node`, sub category `sync`, gauge, from `MetricsNode.justified_epoch`: the store's justified epoch.
- `lantern_node_health_uptime_seconds`: category `node`, sub category `health`, gauge, from `MetricsProcess.uptime_us`, in seconds: time since the start.
- `lantern_node_health_execution_engine`: category `node`, sub category `health`, gauge, from `MetricsProcess.engine`: connection to the execution engine: 0 none, 1 dialing, 2 open.
- `lantern_node_health_step_seconds`: category `node`, sub category `health`, histogram, from `AppMetrics.step_seconds`, work bounds: run time of each node step.
- `lantern_node_pool_operations`: category `node`, sub category `pool`, gauge, from `MetricsNode.pool`, by `topic`: operations in the pool, by topic.
- `lantern_node_pool_proposers`: category `node`, sub category `pool`, gauge, from `MetricsNode.local_validators`: validators with a fee recipient from prepareBeaconProposer.
- `lantern_node_log_lines_total`: category `node`, sub category `log`, counter, from `AppMetrics.log_lines`, by `level`: log lines written, by level.
- `lantern_node_api_requests_total`: category `node`, sub category `api`, counter, from `AppMetrics.api_requests`: beacon API requests.
- `lantern_node_api_answers_total`: category `node`, sub category `api`, counter, from `AppMetrics.api_classes`, by `class`: beacon API answers, by status class.
- `lantern_node_api_connections_open`: category `node`, sub category `api`, gauge, from `MetricsProcess.api_open`: beacon API connections open.
- `lantern_node_storage_records_total`: category `node`, sub category `storage`, counter, from `AppMetrics.db_records`, by `kind`: records appended to the history's segment files, by kind.
- `lantern_node_storage_record_bytes_total`: category `node`, sub category `storage`, counter, from `AppMetrics.db_bytes`, by `kind`: bytes of those records.
- `lantern_node_storage_anchors_total`: category `node`, sub category `storage`, counter, from `AppMetrics.db_anchors`: anchor states written for a restart.
- `lantern_node_storage_anchor_write_seconds`: category `node`, sub category `storage`, histogram, from `AppMetrics.anchor_seconds`: run time of each anchor state write, from its bytes to the synced directory.
- `lantern_node_storage_segments_dropped_total`: category `node`, sub category `storage`, counter, from `AppMetrics.db_drops`: segment files deleted.
- `lantern_node_storage_write_failures_total`: category `node`, sub category `storage`, counter, from `AppMetrics.db_failures`: writes to the data directory that failed.

## Type `MetricLabel`

A label table of the metric table: a label's name and its values in element order.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `name` | u32 | Offset of the label's name in `metrics_texts` |
| 4 | `name_len` | u32 | Bytes of the name |
| 8 | `count` | u32 | The values |
| 12 | `first` | u32 | The first of its values in `metrics_label_values` |

### Rules

- `status` (`status`): `pending`, `active`, `exited`, `withdrawable`.
- `topic` (`topic`): `other`, `beacon_block`, `beacon_aggregate_and_proof`, `beacon_attestation`, `voluntary_exit`, `proposer_slashing`, `attester_slashing`, `sync_committee_contribution_and_proof`, `sync_committee`, `bls_to_execution_change`, `blob_sidecar`, `data_column_sidecar`, `light_client_finality_update`, `light_client_optimistic_update`.
- `result` (`result`): `accept`, `ignore`, `reject`.
- `method` (`method`): `other`, `status`, `goodbye`, `beacon_blocks_by_range`, `beacon_blocks_by_root`, `ping`, `metadata`, `blob_sidecars_by_range`, `blob_sidecars_by_root`, `data_column_sidecars_by_range`, `data_column_sidecars_by_root`, `beacon_blocks_by_head`, `light_client_bootstrap`, `light_client_updates_by_range`, `light_client_finality_update`, `light_client_optimistic_update`.
- `direction` (`direction`): `inbound`, `outbound`.
- `level` (`level`): `error`, `warn`, `info`, `debug`.
- `class` (`class`): `2xx`, `3xx`, `4xx`, `5xx`.
- `kind` (`kind`): `block`, `sidecar`, `state`.
- `work_block` (`work`): `import_block`, `sync_block`, `block_attestation`, `block_slashing`, `replay`.
- `work_state` (`work`): `justified_state`, `target_state`, `slots`, `upgrade`.
- `work_forkchoice` (`work`): `attestation`, `attester_slashing`, `gossip_vote`.
- `work_availability` (`work`): `blob`, `reconstruct`, `custody`.
- `work_gossip` (`work`): `gossip`.
- `work_engine` (`work`): `new_payload`, `forkchoice`, `prepare_payload`, `get_payload`, `eth1_check`.
- `work_builder` (`work`): `produce_bid`.
- `work_lightclient` (`work`): `lc_block`, `lc_head`, `lc_serve`, `lc_gossip`, `lc_publish`.
- `work_history` (`work`): `backfill`, `archive_load`, `serve`.
- `work_validator` (`work`): `api_encode`, `api_chunk`, `api_lookup`, `api_event`, `api_submit`, `pool_check`, `produce_check`, `produce_fold`, `produce_block`, `publish_decode`, `publish_sidecars`, `publish_check`, `publish_sidecar`, `produce_eth1`.
- Work bounds (the `work` bound set): 0.00001, 0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5.

## Test vectors

- Lantern's cases `<preset>-<fork>-metrics-text.bin`, made by tests/generator/metrics.py: values of each type and the text an independent Python formatter of the rules above gives; with no category, one category and all; with `present`, `electra`, `fulu`, `state_root_present` and `max_fds` 0 and 1; with sources not given; with tick rates of 24 MHz, 1 GHz and 2.4 GHz.
- Lantern's cases `<preset>-phase0-metrics-observe.bin`, made by tests/generator/metrics.py: for each bound set of microseconds, Histograms of random counts and 40 values about the bounds, 0 and 2^64 - 1 (a sum that wraps), with the Histogram after each.
- Lantern's cases `<preset>-phase0-metrics-answer.bin`, made by tests/generator/metrics.py: requests written out with the status each must give (GET of `/metrics` with a query, from Prometheus, over HTTP/1.0, after empty lines, two at once; other paths and methods; no Host, HTTP/2.0, a body, a transfer coding, a head past `METRICS_HEAD_MAX`; part of a head and no bytes) over the sources of the text cases; the runner gives the exact room and one byte less.
- Lantern's cases `<preset>-<fork>-metrics-state.bin`, made by tests/generator/metrics.py with the pinned spec: states of the fork's `BeaconState` with 0 to 300 validators whose epochs lie about the state's epoch (some out of order), random participation flags, checkpoints, deposit counts and pending lists, each with no block, 179 bytes and a `SignedBeaconBlock`; and the values the spec's functions give (get_current_epoch, get_previous_epoch, is_active_validator, get_active_validator_indices).
- `lantern_metrics_node`: after each step of the node-mode runs (node.md, Test vectors), its values against the runner's own reading of the node's and the store's bytes by the rules above.

## Results

<!-- CI generates the tick table for each function here. -->

### `lantern_metrics_text`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_metrics_answer`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_metrics_observe`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_metrics_state`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_metrics_node`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 | ✅ | ✅ | ✅ |  |
| ARM64 | ✅ | ✅ | ✅ |  |
| RISC-V | ✅ |  |  |  |

### `lantern_mt_dec`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_histogram`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_label`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_le`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_name`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_open`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_pair`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_put`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_sdec`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_seconds`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_text`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_ticks_us`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_topic`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |

### `lantern_mt_value`

| ISA | Linux | Windows | macOS | `equal` |
|---|---|---|---|---|
| x86-64 |  |  |  |  |
| ARM64 |  |  |  |  |
| RISC-V |  |  |  |  |
