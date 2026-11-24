# Metrics

## Contents

### Functions

- [`lantern_metrics_text`](#function-lantern_metrics_text): the Prometheus text of the metrics categories.
- [`lantern_metrics_state`](#function-lantern_metrics_state): the head state's values of the metrics.
- [`lantern_metrics_node`](#function-lantern_metrics_node): the node's and store's values of the metrics.

### Types

- [`MetricsSources`](#type-metricssources): the address of each source of values.
- [`MetricsState`](#type-metricsstate): the values from the head's post-state.
- [`MetricsNode`](#type-metricsnode): the values from the node and the store.
- [`NodeMetrics`](#type-nodemetrics): the counters and delay histograms the node step keeps.
- [`AppMetrics`](#type-appmetrics): the run time histograms the app keeps.
- [`Histogram`](#type-histogram): the counts of one histogram.
- [`MetricsProcess`](#type-metricsprocess): the process's values.
- [`MetricsGossip`](#type-metricsgossip): gossipsub's values for each topic.
- [`Profile`](#type-profile): the tick rate and tick bounds of the function timers.

### Constants

- `METRIC_BIT_<CATEGORY>_<SUB>`: the bit of a sub category, by the table of [Categories](#categories); `METRIC_BIT_BEACON` (0) for `beacon`.
- `METRICS_BEACON`, `METRICS_NETWORK`, `METRICS_PROCESSING`, `METRICS_NODE`: the bits of each category's sub categories.
- `METRICS_ALL`: the bits of every category.

## Spec

- Document: [ethereum/beacon-metrics 0af554b](https://github.com/ethereum/beacon-metrics/blob/0af554b0787887887b66e429c373f190b932c223/metrics.md): the metric names, types and Usage texts; an informative spec ("implementations are not required to implement all recommendations").
- Document: [Prometheus text exposition format 0.0.4](https://prometheus.io/docs/instrumenting/exposition_formats/#text-based-format): the text.
- Section: Interop Metrics, PeerDAS Metrics (Data column, kzg, custody metrics), Additional Metrics, Prometheus metrics collection.

## Categories

| Category | Sub categories, by bit |
|---|---|
| `beacon` | none: bit 0 |
| `network` | `peer` 1, `discovery` 2, `transport` 3, `gossip` 4, `reqresp` 5 |
| `processing` | `block` 8, `epoch` 9, `state` 10, `forkchoice` 11, `availability` 12, `gossip` 13, `engine` 14, `builder` 15, `lightclient` 16, `history` 17, `validator` 18 |
| `node` | `resource` 24, `sync` 25, `health` 26, `pool` 27, `log` 28, `api` 29, `storage` 30 |

- `beacon`: the metrics of ethereum/beacon-metrics that lantern has a source for, by their names there.
- `network`: what lantern's peers, discovery, connections, gossipsub and requests do.
- `processing`: the work on data, by stage: its counts, failures and run times, down to single functions.
- `node`: the process and the node as a whole: its resources, sync, health, pools, log, Beacon API and database.
- The metrics of a sub category are named `lantern_<category>_<sub>_<measure>`; those of `beacon` keep beacon-metrics' names.

## Common rules

- A category is a set of metrics a node may expose. The `beacon` category holds the metrics of the table below, in that order: those of beacon-metrics that lantern has a source for.
- The metric table (include/metrics_table.inc) holds every family of every category, in the order of the text; tests/generator/metrics.py writes it and include/metrics.inc from its lists. A family's entry gives its name, HELP text, type, sub category bit, source, place in the source, kind, condition, label tables and bound set.
- Each family has a source: the head's post-state (`MetricsState`), the node and the store (`MetricsNode`), the node step's counters (`NodeMetrics`), the app (`AppMetrics`, `MetricsProcess`), gossipsub (`MetricsGossip`) or the function timers (`Profile`).
- beacon-metrics leaves these out of the `beacon` category, as lantern has no source for them: the fast confirmation metrics (lantern runs no fast confirmation rule), the engine_getBlobsV2 and engine_getBlobsV3 metrics (lantern calls neither), the partial message metrics and `beacon_useful_full_columns_received_total` (lantern sends and takes no partial column messages), `beacon_custody_groups_backfilled` (lantern backfills no custody group after a raise), `beacon_data_column_sidecar_inclusion_proof_verification_seconds` (the inclusion proof check runs inside a larger work, with no run time of its own), `store_beacon_block_cache_hit_total` and `beacon_state_data_cache_misses_total` (lantern has no such caches), and `beacon_attestor_slashing_created_total` (lantern runs no slasher).
- A root as a number: bytes 24 to 32 of the root as a little-endian signed 64-bit integer (beacon-metrics: `int.from_bytes(root[24:32], byteorder='little', signed=True)`).
- `lantern_metrics_text` and `lantern_metrics_node` are in the common object of the core (asm/core/<ISA>/metrics.s), and each symbol is its name. `lantern_metrics_state` is in the object of each fork, as `lantern_<fork>_metrics_state`. Every u64 argument is passed by its address.

## The `beacon` category

| Metric | Type | Value |
|---|---|---|
| `libp2p_peers` | gauge | `MetricsNode.peers` |
| `beacon_head_slot` | gauge | `MetricsState.slot` |
| `beacon_finalized_epoch` | gauge | `MetricsState.finalized_epoch` |
| `beacon_current_justified_epoch` | gauge | `MetricsState.current_justified_epoch` |
| `beacon_previous_justified_epoch` | gauge | `MetricsState.previous_justified_epoch` |
| `beacon_current_active_validators` | gauge | `MetricsState.active_validators` |
| `beacon_reorgs_total` | counter | `NodeMetrics.reorgs` |
| `beacon_processed_deposits_total` | gauge | `MetricsState.deposit_count` |
| `beacon_data_column_sidecar_processing_requests_total` | counter | `NodeMetrics.column_requests` |
| `beacon_data_column_sidecar_processing_successes_total` | counter | `NodeMetrics.column_successes` |
| `beacon_data_column_sidecar_gossip_verification_seconds` | histogram | `AppMetrics.gossip_verification`, default bounds |
| `beacon_data_availability_reconstructed_columns_total` | counter | `NodeMetrics.reconstructed_columns` |
| `beacon_data_availability_reconstruction_time_seconds` | histogram | `AppMetrics.reconstruction`, default bounds |
| `beacon_data_column_sidecar_computation_seconds` | histogram | `AppMetrics.computation`, default bounds |
| `beacon_kzg_verification_data_column_batch_seconds` | histogram | `AppMetrics.kzg_batch`, KZG bounds |
| `beacon_custody_groups` | gauge | `MetricsNode.custody_groups` |
| `beacon_current_validators` | gauge | `MetricsState.current_validators`, by `status` |
| `beacon_previous_validators` | gauge | `MetricsState.previous_validators`, by `status` |
| `beacon_current_live_validators` | gauge | `MetricsState.current_live` |
| `beacon_previous_live_validators` | gauge | `MetricsState.previous_live` |
| `beacon_pending_deposits` | gauge | `MetricsState.pending_deposits` |
| `beacon_pending_partial_withdrawals` | gauge | `MetricsState.pending_partial_withdrawals` |
| `beacon_pending_consolidations` | gauge | `MetricsState.pending_consolidations` |
| `beacon_pending_exits` | gauge | `MetricsNode.pending_exits` |
| `beacon_previous_epoch_orphaned_blocks` | gauge | `MetricsNode.orphaned_blocks` |
| `gossipsub_mesh_peers_per_main_topic` | gauge | `MetricsGossip`: `mesh_peers` of each topic with no subnet, by `topic` |
| `beacon_attestation_delay_count` | histogram | `NodeMetrics.attestation_delay`, delay bounds |
| `local_validator_count` | gauge | `MetricsNode.local_validators` |
| `beacon_head_state_finalized_root` | gauge | `MetricsState.finalized_root` |
| `beacon_previous_justified_root` | gauge | `MetricsState.previous_justified_root` |
| `beacon_aggregates_received_total` | gauge | `NodeMetrics.aggregates_received` |
| `beacon_block_delay_count` | histogram | `NodeMetrics.block_delay`, delay bounds |
| `beacon_attestor_slashing_received_total` | gauge | `NodeMetrics.attester_slashings_received` |
| `beacon_block_proposed_total` | gauge | `NodeMetrics.blocks_proposed` |
| `beacon_attestations_published_total` | gauge | `NodeMetrics.attestations_published` |
| `beacon_processor_gossip_block_imported_total` | gauge | `NodeMetrics.gossip_blocks_imported` |
| `libp2p_pubsub_validation_failure_total` | gauge | `NodeMetrics.validation_failures` |
| `beacon_head_state_root` | gauge | `MetricsState.state_root` |
| `beacon_attestations_received_total` | gauge | `NodeMetrics.attestations_received` |
| `beacon_http_api_requests_total` | gauge | `NodeMetrics.api_requests` |
| `beacon_http_api_successes_total` | gauge | `NodeMetrics.api_successes` |
| `beacon_sync_state` | gauge | `MetricsNode.sync_state` |
| `process_cpu_seconds_total` | gauge | `MetricsProcess.cpu_us`, in seconds |
| `process_max_fds` | gauge | `MetricsProcess.max_fds` |
| `gossipsub_topic_msg_sent_bytes` | counter | `MetricsGossip`: `sent_bytes` and `sent_partial_bytes` of each topic, by `topic` and `partial` |
| `gossipsub_mesh_peer_counts` | gauge | `MetricsGossip`: mesh peers of each topic by `topic` and `supports_partial` |

- Each metric's HELP text is the Usage text of beacon-metrics, and its type the Metric type there.
- Tick bounds (the function timers of `Profile`): 0.000001, 0.000004, 0.000016, 0.000064, 0.000256, 0.001, 0.004, 0.016, 0.064, 0.256, 1.
- Default bounds (Prometheus's, as Lighthouse v8.3.3 uses for these): 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10.
- KZG bounds (Lighthouse v8.3.3, `exponential_buckets(0.002, 2.0, 10)`): 0.002, 0.004, 0.008, 0.016, 0.032, 0.064, 0.128, 0.256, 0.512, 1.024.
- Delay bounds (beacon-metrics sets none: "bucket size yet to be decided"): 0.5, 1, 2, 3, 4, 6, 8, 12, 24.
- `status`, in this order: `pending`, `active`, `exited`, `withdrawable`.

## Function `lantern_metrics_text`

The Prometheus text of the metrics of the categories.

### Signature

```
lantern_metrics_text(categories, sources, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `categories` | input | u64: the bits of the sub categories ([Categories](#categories)) |
| `sources` | input | [`MetricsSources`](#type-metricssources) |
| `out` | output | `ByteList`, its `size` set by the caller |

### Returns

- `LANTERN_OK`: `out` holds the text.
- `LANTERN_BUFFER_TOO_SMALL`: `out` has no room for the text.

### Function does

- Each family of the metric table whose bit is in `categories`, whose source is given and whose condition holds, in the order of the table: `# HELP <name> <help>`, `# TYPE <name> <type>`, then its samples. Every line ends with LF. With no such family: no bytes.
- Conditions: `state`: the `MetricsState` with `present` 1; `electra`: `present` and `electra` 1; `state_root`: `present` and `state_root_present` 1; `fulu`: the `MetricsNode` with `fulu` 1; `max_fds`: the `MetricsProcess` with `max_fds` above 0; `profile`: the `Profile` with `ticks_per_second` above 0.
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

### ABI

- Role: L1.
- Symbol: `lantern_metrics_text` (`_lantern_metrics_text` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `categories`, `sources`, `out`.

## Function `lantern_metrics_state`

The values of the metrics from a head's post-state and its block, of one fork.

### Signature

```
lantern_<fork>_metrics_state(state, block, out) -> status
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
- `current_live` and `previous_live`: the validators active at the epoch with a flag in `current_epoch_participation` or `previous_epoch_participation`; phase0: the attesting indices of the attestations of `current_epoch_attestations` or `previous_epoch_attestations` (get_attesting_indices), each validator once.
- From electra: `electra` 1, and the entries of `pending_deposits`, `pending_partial_withdrawals` and `pending_consolidations`.
- `state_root_present` 1 and `state_root` the `state_root` of the block's message as a number (bytes 148 to 180 of a `SignedBeaconBlock`), when `block` holds at least 180 bytes; else 0 and 0.

### Forks

- Every fork defines it. Phase0 counts the live validators from the pending attestations; altair on from the participation flags; electra adds the pending lists.

### ABI

- Role: L1.
- Symbol: `lantern_<fork>_metrics_state`.
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
- `local_validators`: the `NodeProposer` entries in use: the validators whose validator client gave this node prepareBeaconProposer (Prysm's tracked validators).
- `orphaned_blocks`: the imported blocks of the node with a slot in the store's previous epoch that are not ancestors of the head: by `parent_root` from the head, no block of the chain has their root.
- `sync_state`: 1 when the head's slot is the store's slot or one below; else 2 with `NODE_FLAG_SYNCING`; else 0.
- `head_block_id` and `head_state_id`: the `data_id` and `state_id` of the `NodeBlock` of the node's `head_root`; 0 and 0 with none. The caller gives their buffers to lantern_<fork>_metrics_state.

### ABI

- Role: L1.
- Symbol: `lantern_metrics_node` (`_lantern_metrics_node` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `node`, `store`, `out`.

## Type `MetricsSources`

The address of each source of values, for `lantern_metrics_text`; 0 for a source not given, whose families do not go in.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `state` | address | [`MetricsState`](#type-metricsstate) |
| 8 | `node` | address | [`MetricsNode`](#type-metricsnode) |
| 16 | `counters` | address | [`NodeMetrics`](#type-nodemetrics) |
| 24 | `app` | address | [`AppMetrics`](#type-appmetrics) |
| 32 | `process` | address | [`MetricsProcess`](#type-metricsprocess) |
| 40 | `gossip` | address | [`MetricsGossip`](#type-metricsgossip), well formed |
| 48 | `profile` | address | [`Profile`](#type-profile) |
| 56 | | | Size |

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
| 152 | `electra` | u64 | 1 from electra, else 0 |
| 160 | `pending_deposits` | u64 | |
| 168 | `pending_partial_withdrawals` | u64 | |
| 176 | `pending_consolidations` | u64 | |
| 184 | `state_root_present` | u64 | 1 when the block gave `state_root`, else 0 |
| 192 | `state_root` | i64 | The state's root as a number |
| 200 | | | Size |

## Type `MetricsNode`

The values of the metrics from the node and the store.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `peers` | u64 | |
| 8 | `fulu` | u64 | 1 from fulu, else 0 |
| 16 | `custody_groups` | u64 | |
| 24 | `pending_exits` | u64 | |
| 32 | `local_validators` | u64 | |
| 40 | `orphaned_blocks` | u64 | |
| 48 | `sync_state` | u64 | 0, 1 or 2 |
| 56 | `head_block_id` | u64 | `BufferId` of the head's `SignedBeaconBlock` bytes, or 0 |
| 64 | `head_state_id` | u64 | `BufferId` of the head's post-state, or 0 |
| 72 | | | Size |

## Type `NodeMetrics`

The counters and delay histograms of the metrics that the node step keeps, in the node's fixed fields ([node.md](node.md#type-node), `metrics`).

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `reorgs` | u64 | Head changes off the old head's chain |
| 8 | `column_requests` | u64 | data_column_sidecar gossip messages given to validation |
| 16 | `column_successes` | u64 | Those valid |
| 24 | `reconstructed_columns` | u64 | Column sidecars the reconstruction rebuilt and the node kept |
| 32 | `aggregates_received` | u64 | beacon_aggregate_and_proof gossip messages |
| 40 | `attestations_received` | u64 | beacon_attestation gossip messages |
| 48 | `attester_slashings_received` | u64 | attester_slashing gossip messages |
| 56 | `blocks_proposed` | u64 | Blocks of publishBlockV2 and publishBlindedBlockV2 that went out |
| 64 | `attestations_published` | u64 | Attestations of submitPoolAttestationsV2 that went out |
| 72 | `gossip_blocks_imported` | u64 | Blocks from gossip the node imported |
| 80 | `validation_failures` | u64 | Gossip messages whose validation gave REJECT |
| 88 | `api_requests` | u64 | Beacon API requests |
| 96 | `api_successes` | u64 | Those answered with a 2xx status |
| 104 | `attestation_delay` | [`Histogram`](#type-histogram) | Delay bounds |
| 216 | `block_delay` | [`Histogram`](#type-histogram) | Delay bounds |
| 328 | | | Size |

## Type `AppMetrics`

The run time histograms of the metrics that the app keeps.

### Layout

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 0 | `gossip_verification` | [`Histogram`](#type-histogram) | Default bounds |
| 112 | `reconstruction` | [`Histogram`](#type-histogram) | Default bounds |
| 224 | `computation` | [`Histogram`](#type-histogram) | Default bounds |
| 336 | `kzg_batch` | [`Histogram`](#type-histogram) | KZG bounds |
| 448 | | | Size |

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
| 16 | | | Size |

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

## Test vectors

- Lantern's cases `<preset>-<fork>-metrics-text.bin`, made by tests/generator/metrics.py: values of each type and the text an independent Python formatter of the rules above gives; with no category, one category and all; with `present`, `electra`, `fulu`, `state_root_present` and `max_fds` 0 and 1; with sources not given; with tick rates of 24 MHz, 1 GHz and 2.4 GHz.
- Lantern's cases `<preset>-<fork>-metrics-state.bin`, made by tests/generator/metrics.py with the pinned spec: states of the spec's test helpers, at genesis and after random validator changes and blocks, and the values the spec's functions give.
- `lantern_metrics_node`: node-mode fork_choice cases (node.md, Test vectors), after their steps: the node's peers, pool and blocks against the runner's counts.

## Results

<!-- CI generates the tick table for each function here. -->
