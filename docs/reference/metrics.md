# Metrics

## Contents

### Functions

- [`lantern_metrics_text`](#function-lantern_metrics_text): the Prometheus text of the metrics categories.
- [`lantern_metrics_answer`](#function-lantern_metrics_answer): the HTTP answer to a metrics server's request.
- [`lantern_metrics_observe`](#function-lantern_metrics_observe): a value joins a Histogram.
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
- `METRICS_HEAD_MAX` (4096): the longest request head of the metrics server.
- `METRICS_HEAD_ROOM` (256): the bytes of `out` that lantern_metrics_answer keeps before the text.

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
- `lantern_metrics_text`, `lantern_metrics_answer` and `lantern_metrics_node` are in the common object of the core (asm/core/<ISA>/metrics.s), and each symbol is its name. `lantern_metrics_state` is in the object of each fork, as `lantern_<fork>_metrics_state`. Every u64 argument is passed by its address.

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
| `beacon_data_column_sidecar_processing_requests_total` | counter | `AppMetrics.column_requests` |
| `beacon_data_column_sidecar_processing_successes_total` | counter | `AppMetrics.column_successes` |
| `beacon_data_column_sidecar_gossip_verification_seconds` | histogram | `AppMetrics.gossip_verification`, default bounds |
| `beacon_data_availability_reconstructed_columns_total` | counter | `AppMetrics.reconstructed_columns` |
| `beacon_data_availability_reconstruction_time_seconds` | histogram | `AppMetrics.reconstruction`, default bounds |
| `beacon_data_column_sidecar_computation_seconds` | histogram | `AppMetrics.computation`, default bounds |
| `beacon_kzg_verification_data_column_batch_seconds` | histogram | `AppMetrics.kzg_batch`, kzg bounds |
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
| `beacon_attestation_delay_count` | histogram | `AppMetrics.attestation_delay`, delay bounds |
| `local_validator_count` | gauge | `MetricsNode.local_validators` |
| `beacon_head_state_finalized_root` | gauge | `MetricsState.finalized_root` |
| `beacon_previous_justified_root` | gauge | `MetricsState.previous_justified_root` |
| `beacon_aggregates_received_total` | gauge | `AppMetrics.aggregates_received` |
| `beacon_block_delay_count` | histogram | `AppMetrics.block_delay`, delay bounds |
| `beacon_attestor_slashing_received_total` | gauge | `AppMetrics.attester_slashings_received` |
| `beacon_block_proposed_total` | gauge | `AppMetrics.blocks_proposed` |
| `beacon_attestations_published_total` | gauge | `NodeMetrics.attestations_published` |
| `beacon_processor_gossip_block_imported_total` | gauge | `AppMetrics.gossip_blocks_imported` |
| `libp2p_pubsub_validation_failure_total` | gauge | `AppMetrics.validation_failures` |
| `beacon_head_state_root` | gauge | `MetricsState.state_root` |
| `beacon_attestations_received_total` | gauge | `AppMetrics.attestations_received` |
| `beacon_http_api_requests_total` | gauge | `AppMetrics.api_requests` |
| `beacon_http_api_successes_total` | gauge | `AppMetrics.api_successes` |
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

## The `network` category

| Metric | Sub category | Type | Value | Meaning |
|---|---|---|---|---|
| `lantern_network_peer_connected` | `peer` | gauge | `MetricsNode.peers` | Connected peers |
| `lantern_network_peer_direction` | `peer` | gauge | `MetricsNode.peer_directions`, by `direction` | Connected peers by the direction of their connection |
| `lantern_network_peer_dialing` | `peer` | gauge | `MetricsNode.dialing` | Dials of the node not yet connected or failed |
| `lantern_network_peer_connections_total` | `peer` | counter | `AppMetrics.connections`, by `direction` | Connections made, by direction |
| `lantern_network_peer_dial_failures_total` | `peer` | counter | `AppMetrics.dial_failures` | Dials that failed |
| `lantern_network_peer_disconnections_total` | `peer` | counter | `AppMetrics.closed` | Connections that closed |
| `lantern_network_discovery_records_total` | `discovery` | counter | `AppMetrics.records` | Node records discv5 found and gave to the node |
| `lantern_network_discovery_lookups_total` | `discovery` | counter | `AppMetrics.lookups` | Lookups the node asked discv5 for |
| `lantern_network_discovery_datagrams_received_total` | `discovery` | counter | `AppMetrics.dv_in` | UDP datagrams discv5 received |
| `lantern_network_discovery_datagrams_sent_total` | `discovery` | counter | `AppMetrics.dv_out` | UDP datagrams discv5 sent |
| `lantern_network_discovery_step_failures_total` | `discovery` | counter | `AppMetrics.dv_failures` | discv5 steps that failed |
| `lantern_network_transport_received_bytes_total` | `transport` | counter | `AppMetrics.rx_bytes` | Bytes received on libp2p connections |
| `lantern_network_transport_sent_bytes_total` | `transport` | counter | `AppMetrics.tx_bytes` | Bytes sent on libp2p connections |
| `lantern_network_gossip_messages_total` | `gossip` | counter | `AppMetrics.gossip_results`, by `topic` and `result` | Gossip messages validated, by topic and result |
| `lantern_network_gossip_messages_held` | `gossip` | gauge | `MetricsNode.messages` | Gossip messages the node holds |
| `lantern_network_reqresp_served_total` | `reqresp` | counter | `AppMetrics.served`, by `method` | Requests of peers the node served, by method |
| `lantern_network_reqresp_streams_open` | `reqresp` | gauge | `MetricsNode.streams` | Request streams open |

## The `processing` category

| Metric | Sub category | Type | Value | Meaning |
|---|---|---|---|---|
| `lantern_processing_block_work_seconds` | `block` | histogram | `AppMetrics.work_seconds`, by `work`, work bounds | Run time of each node work of the block stage, by work kind |
| `lantern_processing_block_work_failures_total` | `block` | counter | `AppMetrics.work_failures`, by `work` | Node works of the block stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_state_work_seconds` | `state` | histogram | `AppMetrics.work_seconds`, by `work`, from element 5, work bounds | Run time of each node work of the state stage, by work kind |
| `lantern_processing_state_work_failures_total` | `state` | counter | `AppMetrics.work_failures`, by `work`, from element 5 | Node works of the state stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_forkchoice_work_seconds` | `forkchoice` | histogram | `AppMetrics.work_seconds`, by `work`, from element 9, work bounds | Run time of each node work of the forkchoice stage, by work kind |
| `lantern_processing_forkchoice_work_failures_total` | `forkchoice` | counter | `AppMetrics.work_failures`, by `work`, from element 9 | Node works of the forkchoice stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_availability_work_seconds` | `availability` | histogram | `AppMetrics.work_seconds`, by `work`, from element 12, work bounds | Run time of each node work of the availability stage, by work kind |
| `lantern_processing_availability_work_failures_total` | `availability` | counter | `AppMetrics.work_failures`, by `work`, from element 12 | Node works of the availability stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_gossip_work_seconds` | `gossip` | histogram | `AppMetrics.work_seconds`, by `work`, from element 15, work bounds | Run time of each node work of the gossip stage, by work kind |
| `lantern_processing_gossip_work_failures_total` | `gossip` | counter | `AppMetrics.work_failures`, by `work`, from element 15 | Node works of the gossip stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_engine_work_seconds` | `engine` | histogram | `AppMetrics.work_seconds`, by `work`, from element 16, work bounds | Run time of each node work of the engine stage, by work kind |
| `lantern_processing_engine_work_failures_total` | `engine` | counter | `AppMetrics.work_failures`, by `work`, from element 16 | Node works of the engine stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_builder_work_seconds` | `builder` | histogram | `AppMetrics.work_seconds`, by `work`, from element 21, work bounds | Run time of each node work of the builder stage, by work kind |
| `lantern_processing_builder_work_failures_total` | `builder` | counter | `AppMetrics.work_failures`, by `work`, from element 21 | Node works of the builder stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_lightclient_work_seconds` | `lightclient` | histogram | `AppMetrics.work_seconds`, by `work`, from element 22, work bounds | Run time of each node work of the lightclient stage, by work kind |
| `lantern_processing_lightclient_work_failures_total` | `lightclient` | counter | `AppMetrics.work_failures`, by `work`, from element 22 | Node works of the lightclient stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_history_work_seconds` | `history` | histogram | `AppMetrics.work_seconds`, by `work`, from element 27, work bounds | Run time of each node work of the history stage, by work kind |
| `lantern_processing_history_work_failures_total` | `history` | counter | `AppMetrics.work_failures`, by `work`, from element 27 | Node works of the history stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_validator_work_seconds` | `validator` | histogram | `AppMetrics.work_seconds`, by `work`, from element 30, work bounds | Run time of each node work of the validator stage, by work kind |
| `lantern_processing_validator_work_failures_total` | `validator` | counter | `AppMetrics.work_failures`, by `work`, from element 30 | Node works of the validator stage whose result was not LANTERN_OK, by work kind |
| `lantern_processing_epoch_transitions_total` | `epoch` | counter | `AppMetrics.epoch_transitions` | Slot processing works that crossed an epoch boundary |
| `lantern_processing_epoch_slots_seconds` | `epoch` | histogram | `AppMetrics.epoch_seconds`, work bounds | Run time of each slot processing work that crossed an epoch boundary |
| `lantern_processing_gossip_validation_seconds` | `gossip` | histogram | `AppMetrics.gossip_seconds`, by `topic`, work bounds | Run time of each gossip validation, by topic |

## The `node` category

| Metric | Sub category | Type | Value | Meaning |
|---|---|---|---|---|
| `lantern_node_resource_cpu_seconds_total` | `resource` | counter | `MetricsProcess.cpu_us`, in seconds | User and system CPU time |
| `lantern_node_resource_max_resident_memory_bytes` | `resource` | gauge | `MetricsProcess.max_rss_bytes` | Highest resident memory since the start |
| `lantern_node_resource_max_fds` | `resource` | gauge | `MetricsProcess.max_fds`; condition `max_fds` | The soft limit of open files |
| `lantern_node_resource_buffers` | `resource` | gauge | `MetricsProcess.buffers` | Buffers the app holds for the node |
| `lantern_node_resource_buffer_bytes` | `resource` | gauge | `MetricsProcess.buffer_bytes` | Bytes of those buffers |
| `lantern_node_resource_start_time_seconds` | `resource` | gauge | `MetricsProcess.start_s` | Unix time of the start |
| `lantern_node_sync_head_slot` | `sync` | gauge | `MetricsNode.head_slot` | Slot of the head block |
| `lantern_node_sync_store_slot` | `sync` | gauge | `MetricsNode.store_slot` | Slot of the store's time |
| `lantern_node_sync_distance` | `sync` | gauge | `MetricsNode.distance` | Slots from the head to the store's slot |
| `lantern_node_sync_state` | `sync` | gauge | `MetricsNode.sync_state` | 0 behind and not syncing, 1 synced, 2 syncing |
| `lantern_node_sync_earliest_slot` | `sync` | gauge | `MetricsNode.earliest_slot` | First slot whose blocks the node serves |
| `lantern_node_sync_backfill_slot` | `sync` | gauge | `MetricsNode.backfill_slot` | Slot below which the backfill looks for blocks |
| `lantern_node_sync_finalized_epoch` | `sync` | gauge | `MetricsNode.finalized_epoch` | The store's finalized epoch |
| `lantern_node_sync_justified_epoch` | `sync` | gauge | `MetricsNode.justified_epoch` | The store's justified epoch |
| `lantern_node_health_uptime_seconds` | `health` | gauge | `MetricsProcess.uptime_us`, in seconds | Time since the start |
| `lantern_node_health_execution_engine` | `health` | gauge | `MetricsProcess.engine` | Connection to the execution engine: 0 none, 1 dialing, 2 open |
| `lantern_node_health_step_seconds` | `health` | histogram | `AppMetrics.step_seconds`, work bounds | Run time of each node step |
| `lantern_node_pool_operations` | `pool` | gauge | `MetricsNode.pool`, by `topic` | Operations in the pool, by topic |
| `lantern_node_pool_proposers` | `pool` | gauge | `MetricsNode.local_validators` | Validators with a fee recipient from prepareBeaconProposer |
| `lantern_node_log_lines_total` | `log` | counter | `AppMetrics.log_lines`, by `level` | Log lines written, by level |
| `lantern_node_api_requests_total` | `api` | counter | `AppMetrics.api_requests` | Beacon API requests |
| `lantern_node_api_answers_total` | `api` | counter | `AppMetrics.api_classes`, by `class` | Beacon API answers, by status class |
| `lantern_node_api_connections_open` | `api` | gauge | `MetricsProcess.api_open` | Beacon API connections open |
| `lantern_node_storage_records_total` | `storage` | counter | `AppMetrics.db_records`, by `kind` | Records appended to the history's segment files, by kind |
| `lantern_node_storage_record_bytes_total` | `storage` | counter | `AppMetrics.db_bytes`, by `kind` | Bytes of those records |
| `lantern_node_storage_anchors_total` | `storage` | counter | `AppMetrics.db_anchors` | Anchor states written for a restart |
| `lantern_node_storage_segments_dropped_total` | `storage` | counter | `AppMetrics.db_drops` | Segment files deleted |
| `lantern_node_storage_write_failures_total` | `storage` | counter | `AppMetrics.db_failures` | Writes to the data directory that failed |

## Label tables

Each label table's name, its label's name, and its values in element order.

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

### ABI

- Role: L1.
- Symbol: `lantern_metrics_text` (`_lantern_metrics_text` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `categories`, `sources`, `out`.

## Function `lantern_metrics_answer`

The HTTP answer to the first request in a metrics server connection's bytes; the connection closes after it.

### Signature

```
lantern_metrics_answer(bytes, categories, sources, out) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `bytes` | input | ByteList: the connection's bytes so far |
| `categories` | input | u64: the bits of the sub categories |
| `sources` | input | [`MetricsSources`](#type-metricssources) |
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

### ABI

- Role: L1.
- Symbol: `lantern_metrics_answer` (`_lantern_metrics_answer` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `bytes`, `categories`, `sources`, `out`.

## Function `lantern_metrics_observe`

A value joins a Histogram of a bound set of microseconds.

### Signature

```
lantern_metrics_observe(histogram, bounds, value) -> status
```

### Arguments

| Name | Role | Type |
|---|---|---|
| `histogram` | input and output | [`Histogram`](#type-histogram) |
| `bounds` | input | u64: `METRIC_BOUNDS_*` of a bound set of microseconds (default, kzg, delay, work) |
| `value` | input | u64: microseconds |

### Returns

- `LANTERN_OK`.

### Function does

- `count` takes 1 more and `sum` the value more, each modulo 2^64; the bucket of the first bound at or above the value takes 1 more, or the one after the last bound when it is above them all.

### ABI

- Role: L0.
- Symbol: `lantern_metrics_observe` (`_lantern_metrics_observe` on macOS).
- Convention: the core ABI for each ISA (ARCHITECTURE.md section 6).
- Argument order: `histogram`, `bounds`, `value`.

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
- From altair: `altair` 1; `current_live` and `previous_live`: the validators active at the epoch with a flag in `current_epoch_participation` or `previous_epoch_participation`. Phase0 leaves them 0, and the two live metrics out: its live validators need the committees of each pending attestation.
- From electra: `electra` 1, and the entries of `pending_deposits`, `pending_partial_withdrawals` and `pending_consolidations`.
- `state_root_present` 1 and `state_root` the `state_root` of the block's message as a number (bytes 148 to 180 of a `SignedBeaconBlock`), when `block` holds at least 180 bytes; else 0 and 0.

### Forks

- Every fork defines it. Altair on counts the live validators from the participation flags; electra adds the pending lists.

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
- `local_validators`: the `NodeProposer` entries whose `until_epoch` is above the store's epoch: the validators whose validator client gave this node prepareBeaconProposer and still holds (Prysm's tracked validators).
- `orphaned_blocks`: the blocks of the node with status `NODE_BLOCK_IMPORTED` and a slot in the store's previous epoch (get_previous_epoch: one less than the store's, not below 0) that are not on the head's chain: the head and its ancestors by `parent_root`, up to the first one below that epoch, the first root the node holds no block of, or 2 × `SLOTS_PER_EPOCH` blocks.
- `sync_state`: 1 when the head's slot + 1 is at least the store's slot; else 2 with `NODE_FLAG_SYNCING`; else 0. With no block of `head_root` the head's slot counts as 0.
- `head_block_id` and `head_state_id`: the `data_id` and `state_id` of the `NodeBlock` of the node's `head_root`; 0 and 0 with none. The caller gives their buffers to lantern_<fork>_metrics_state.
- `pending_exits` and `pool`: the pool's entries, those of voluntary_exit, and those of each topic 1 to 13 at its topic's element.
- `peer_directions`, `dialing`, `messages` and `streams`: from the peers part by direction, `dialing`, and the entries of the messages and streams parts.
- `head_slot`, `store_slot` and `distance`: the head block's slot (0 with none), the store's slot, and `store_slot` - `head_slot` when above 0, else 0.
- `earliest_slot`, `backfill_slot`, `finalized_epoch` and `justified_epoch`: the node's, and the store's checkpoints' epochs.

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
| 48 | `sync_state` | u64 | 0, 1 or 2 |
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
| 6592 | `epoch_transitions` | u64 | SLOTS works to a later epoch than their state's |
| 6600 | `epoch_seconds` | [`Histogram`](#type-histogram) | Their run times, work bounds |
| 6712 | `gossip_seconds` | [`Histogram`](#type-histogram) x 14 | Run times of GOSSIP works by `topic`, work bounds |
| 8280 | `step_seconds` | [`Histogram`](#type-histogram) | Run time of each lantern_node_step, work bounds |
| 8392 | `log_lines` | u64 x 4 | Log lines written, by `level` |
| 8424 | `api_classes` | u64 x 4 | Answers by `class`: the status's first digit 2 to 5 |
| 8456 | `db_records` | u64 x 3 | NODE_ACT_DB_APPEND by `kind` (block, sidecar), NODE_ACT_DB_ARCHIVE (state) |
| 8480 | `db_bytes` | u64 x 3 | Bytes of the appended records' buffers, by `kind` |
| 8504 | `db_anchors` | u64 | NODE_ACT_DB_STATE actions |
| 8512 | `db_drops` | u64 | NODE_ACT_DB_DROP actions |
| 8520 | `db_failures` | u64 | Writes to the data directory that failed (a cannot write line) |
| 8528 | | | Size |

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

## Test vectors

- Lantern's cases `<preset>-<fork>-metrics-text.bin`, made by tests/generator/metrics.py: values of each type and the text an independent Python formatter of the rules above gives; with no category, one category and all; with `present`, `electra`, `fulu`, `state_root_present` and `max_fds` 0 and 1; with sources not given; with tick rates of 24 MHz, 1 GHz and 2.4 GHz.
- Lantern's cases `<preset>-phase0-metrics-observe.bin`, made by tests/generator/metrics.py: for each bound set of microseconds, Histograms of random counts and 40 values about the bounds, 0 and 2^64 - 1 (a sum that wraps), with the Histogram after each.
- Lantern's cases `<preset>-phase0-metrics-answer.bin`, made by tests/generator/metrics.py: requests written out with the status each must give (GET of `/metrics` with a query, from Prometheus, over HTTP/1.0, after empty lines, two at once; other paths and methods; no Host, HTTP/2.0, a body, a transfer coding, a head past `METRICS_HEAD_MAX`; part of a head and no bytes) over the sources of the text cases; the runner gives the exact room and one byte less.
- Lantern's cases `<preset>-<fork>-metrics-state.bin`, made by tests/generator/metrics.py with the pinned spec: states of the fork's `BeaconState` with 0 to 300 validators whose epochs lie about the state's epoch (some out of order), random participation flags, checkpoints, deposit counts and pending lists, each with no block, 179 bytes and a `SignedBeaconBlock`; and the values the spec's functions give (get_current_epoch, get_previous_epoch, is_active_validator, get_active_validator_indices).
- `lantern_metrics_node`: after each step of the node-mode runs (node.md, Test vectors), its values against the runner's own reading of the node's and the store's bytes by the rules above.

## Results

<!-- CI generates the tick table for each function here. -->
