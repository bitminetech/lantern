/**
 * @file server.c
 * @brief Prometheus metrics HTTP endpoint.
 *
 * Exposes a Prometheus-compatible metrics endpoint:
 * - GET /metrics
 *
 * Metrics are generated from a caller-provided snapshot callback.
 *
 * @spec Prometheus exposition format 0.0.4 and POSIX sockets/pthreads.
 */

#include "lantern/metrics/server.h"

#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/version.h"

#define ARRAY_LEN(x) (sizeof(x) / sizeof((x)[0]))

static const size_t LANTERN_METRICS_BODY_INITIAL_CAP = 2048;
static const char LANTERN_METRICS_ENDPOINT_PATH[] = "/metrics";
static const char *const kLeanDirectionLabels[LEAN_METRICS_DIR_COUNT] = {"inbound", "outbound"};
static const char *const kLeanConnectionResultLabels[LEAN_METRICS_CONN_RESULT_COUNT] = {"success", "timeout", "error"};
static const char *const kLeanDisconnectionReasonLabels[LEAN_METRICS_DISCONNECT_REASON_COUNT] =
    {"timeout", "remote_close", "local_close", "error"};
static const char *const kLeanAggregatorSkippedReasonLabels[LEAN_METRICS_AGGREGATOR_SKIPPED_REASON_COUNT] =
    {"not_aggregator", "not_synced", "missing_state", "spawn_failed", "other"};
static const char *const kLeanSyncStatusLabels[] = {"idle", "syncing", "synced"};

/**
 * Metrics server module-specific error codes.
 */
enum
{
    LANTERN_METRICS_SERVER_OK = 0,
    LANTERN_METRICS_SERVER_ERR_INVALID_PARAM = -1,
    LANTERN_METRICS_SERVER_ERR_OUT_OF_MEMORY = -2,
    LANTERN_METRICS_SERVER_ERR_OVERFLOW = -3,
    LANTERN_METRICS_SERVER_ERR_IO = -4,
    LANTERN_METRICS_SERVER_ERR_FORMATTING = -5,
    LANTERN_METRICS_SERVER_ERR_MALFORMED_REQUEST = -6,
    LANTERN_METRICS_SERVER_ERR_UNAVAILABLE = -7,
};

static const char METRICS_JSON_MALFORMED_REQUEST[] = "{\"error\":\"malformed request\"}";
static const char METRICS_JSON_UNKNOWN_ENDPOINT[] = "{\"error\":\"unknown endpoint\"}";
static const char METRICS_JSON_UNAVAILABLE[] = "{\"error\":\"metrics unavailable\"}";
static const char METRICS_JSON_FORMATTING_FAILED[] = "{\"error\":\"metrics formatting failed\"}";

static const char *metrics_client_label(const struct lantern_metrics_snapshot *snapshot)
{
    if (!snapshot || snapshot->lean_client_label[0] == '\0')
    {
        return "unknown";
    }
    return snapshot->lean_client_label;
}

/**
 * @brief Append a single Prometheus metric with a uint64 value.
 */
static int append_metric_uint64(
    struct lantern_http_buffer *buf,
    const char *name,
    const char *help,
    const char *type,
    uint64_t value)
{
    return lantern_http_buffer_appendf(
        buf,
        "# HELP %s %s\n"
        "# TYPE %s %s\n"
        "%s %" PRIu64 "\n",
        name,
        help,
        name,
        type,
        name,
        value);
}


/**
 * @brief Append a single Prometheus metric with a size_t value.
 */
static int append_metric_size_t(
    struct lantern_http_buffer *buf,
    const char *name,
    const char *help,
    const char *type,
    size_t value)
{
    return lantern_http_buffer_appendf(
        buf,
        "# HELP %s %s\n"
        "# TYPE %s %s\n"
        "%s %zu\n",
        name,
        help,
        name,
        type,
        name,
        value);
}


/**
 * @brief Append a Prometheus histogram from a lean metrics snapshot.
 */
static int append_histogram_metrics(
    struct lantern_http_buffer *buf,
    const char *name,
    const char *help,
    const struct lean_metrics_histogram_snapshot *hist)
{
    if (!buf || !name || !help || !hist)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    int rc = lantern_http_buffer_appendf(
        buf,
        "# HELP %s %s\n"
        "# TYPE %s histogram\n",
        name,
        help,
        name);
    if (rc != 0)
    {
        return rc;
    }

    size_t bucket_count = hist->bucket_count;
    if (bucket_count > LEAN_METRICS_MAX_BUCKETS)
    {
        bucket_count = LEAN_METRICS_MAX_BUCKETS;
    }

    uint64_t cumulative_count = 0;
    for (size_t i = 0; i < bucket_count; ++i)
    {
        double bound = hist->buckets[i];
        cumulative_count += hist->counts[i];
        rc = lantern_http_buffer_appendf(
            buf,
            "%s_bucket{le=\"%.9g\"} %" PRIu64 "\n",
            name,
            bound,
            cumulative_count);
        if (rc != 0)
        {
            return rc;
        }
    }

    rc = lantern_http_buffer_appendf(
        buf,
        "%s_bucket{le=\"+Inf\"} %" PRIu64 "\n",
        name,
        hist->total);
    if (rc != 0)
    {
        return rc;
    }

    rc = lantern_http_buffer_appendf(
        buf,
        "%s_sum %.9f\n"
        "%s_count %" PRIu64 "\n",
        name,
        hist->sum,
        name,
        hist->total);
    if (rc != 0)
    {
        return rc;
    }

    return 0;
}

enum metric_scalar_source
{
    METRIC_SCALAR_SNAPSHOT_U64,
    METRIC_SCALAR_SNAPSHOT_SIZE,
    METRIC_SCALAR_LEAN_U64,
};

struct metric_scalar_desc
{
    const char *name;
    const char *help;
    const char *type;
    enum metric_scalar_source source;
    size_t offset;
};

struct metric_client_size_t_desc
{
    const char *name;
    const char *help;
    const char *type;
    size_t offset;
};

struct metric_histogram_desc
{
    const char *name;
    const char *help;
    size_t offset;
};

struct peer_vote_metric_desc
{
    const char *name;
    const char *help;
    const char *type;
    size_t offset;
};

static uint64_t metric_read_u64(const void *base, size_t offset)
{
    uint64_t value = 0;
    memcpy(&value, (const unsigned char *)base + offset, sizeof(value));
    return value;
}

static size_t metric_read_size_t(const void *base, size_t offset)
{
    size_t value = 0;
    memcpy(&value, (const unsigned char *)base + offset, sizeof(value));
    return value;
}

static const struct lean_metrics_histogram_snapshot *metric_histogram_at(
    const struct lean_metrics_snapshot *lean,
    size_t offset)
{
    return (const struct lean_metrics_histogram_snapshot *)((const unsigned char *)lean + offset);
}

static int append_metric_scalar(
    struct lantern_http_buffer *buf,
    const struct lantern_metrics_snapshot *snapshot,
    const struct metric_scalar_desc *desc)
{
    const struct lean_metrics_snapshot *lean = &snapshot->lean_metrics;
    switch (desc->source)
    {
    case METRIC_SCALAR_SNAPSHOT_U64:
        return append_metric_uint64(
            buf,
            desc->name,
            desc->help,
            desc->type,
            metric_read_u64(snapshot, desc->offset));
    case METRIC_SCALAR_SNAPSHOT_SIZE:
        return append_metric_size_t(
            buf,
            desc->name,
            desc->help,
            desc->type,
            metric_read_size_t(snapshot, desc->offset));
    case METRIC_SCALAR_LEAN_U64:
        return append_metric_uint64(
            buf,
            desc->name,
            desc->help,
            desc->type,
            metric_read_u64(lean, desc->offset));
    }
    return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
}

static int append_metric_scalars(
    struct lantern_http_buffer *buf,
    const struct lantern_metrics_snapshot *snapshot,
    const struct metric_scalar_desc *descs,
    size_t count)
{
    for (size_t i = 0; i < count; ++i)
    {
        int rc = append_metric_scalar(buf, snapshot, &descs[i]);
        if (rc != 0)
        {
            return rc;
        }
    }
    return 0;
}

static int append_client_size_t_metrics(
    struct lantern_http_buffer *buf,
    const struct lantern_metrics_snapshot *snapshot,
    const struct metric_client_size_t_desc *descs,
    size_t count)
{
    const char *client_label = metrics_client_label(snapshot);
    for (size_t i = 0; i < count; ++i)
    {
        int rc = lantern_http_buffer_appendf(
            buf,
            "# HELP %s %s\n"
            "# TYPE %s %s\n"
            "%s{client=\"%s\"} %zu\n",
            descs[i].name,
            descs[i].help,
            descs[i].name,
            descs[i].type,
            descs[i].name,
            client_label,
            metric_read_size_t(snapshot, descs[i].offset));
        if (rc != 0)
        {
            return rc;
        }
    }
    return 0;
}

static int append_histogram_descs(
    struct lantern_http_buffer *buf,
    const struct lean_metrics_snapshot *lean,
    const struct metric_histogram_desc *descs,
    size_t count)
{
    for (size_t i = 0; i < count; ++i)
    {
        int rc = append_histogram_metrics(
            buf,
            descs[i].name,
            descs[i].help,
            metric_histogram_at(lean, descs[i].offset));
        if (rc != 0)
        {
            return rc;
        }
    }
    return 0;
}

static int append_peer_vote_metric(
    struct lantern_http_buffer *buf,
    const struct lantern_metrics_snapshot *snapshot,
    const struct peer_vote_metric_desc *desc,
    size_t count)
{
    int rc = lantern_http_buffer_appendf(
        buf,
        "# HELP %s %s\n"
        "# TYPE %s %s\n",
        desc->name,
        desc->help,
        desc->name,
        desc->type);
    if (rc != 0)
    {
        return rc;
    }

    for (size_t i = 0; i < count; ++i)
    {
        const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
        char peer_id[sizeof(metric->peer_id)];
        (void)lantern_string_copy(peer_id, sizeof(peer_id), metric->peer_id);

        rc = lantern_http_buffer_appendf(
            buf,
            "%s{peer=\"%s\"} %" PRIu64 "\n",
            desc->name,
            peer_id,
            metric_read_u64(metric, desc->offset));
        if (rc != 0)
        {
            return rc;
        }
    }
    return 0;
}

static const struct metric_scalar_desc kChainScalarsBeforeClient[] = {
    {"lean_node_start_time_seconds", "Start timestamp", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_node_start_time_seconds)},
    {"lean_head_slot", "Latest slot of the lean chain", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_head_slot)},
    {"lean_current_slot", "Current slot of the lean chain", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_current_slot)},
    {"lean_safe_target_slot", "Safe target slot", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_safe_target_slot)},
    {"lean_latest_justified_slot", "Latest justified slot observed by state transition", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_latest_justified_slot)},
    {"lean_latest_finalized_slot", "Latest finalized slot observed by state transition", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_latest_finalized_slot)},
    {"lean_justified_slot", "Current justified slot", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_justified_slot)},
    {"lean_finalized_slot", "Current finalized slot", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_finalized_slot)},
    {"lean_validators_count", "Number of validators connected to this client", "gauge", METRIC_SCALAR_SNAPSHOT_SIZE, offsetof(struct lantern_metrics_snapshot, lean_validators_count)},
};

static const struct metric_client_size_t_desc kClientLabelScalars[] = {
    {"lean_connected_peers", "Number of connected peers", "gauge", offsetof(struct lantern_metrics_snapshot, lean_connected_peers)},
    {"lean_gossip_mesh_peers", "Number of peers in the gossipsub mesh", "gauge", offsetof(struct lantern_metrics_snapshot, lean_gossip_mesh_peers)},
};

static const struct metric_scalar_desc kChainScalarsAfterClient[] = {
    {"lean_gossip_signatures", "Current number of gossip signatures in fork-choice store", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_gossip_signatures)},
    {"lean_latest_new_aggregated_payloads", "Current number of new aggregated payloads", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_latest_new_aggregated_payloads)},
    {"lean_latest_known_aggregated_payloads", "Current number of known aggregated payloads", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_latest_known_aggregated_payloads)},
    {"lean_is_aggregator", "Validator is_aggregator status (1=true, 0=false)", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_is_aggregator)},
    {"lean_attestation_committee_subnet", "Current committee attestation subnet", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_attestation_committee_subnet)},
    {"lean_attestation_committee_count", "Number of attestation committees", "gauge", METRIC_SCALAR_SNAPSHOT_U64, offsetof(struct lantern_metrics_snapshot, lean_attestation_committee_count)},
};

static const struct metric_scalar_desc kLeanScalarsBeforeAggregation[] = {
    {"lean_block_building_success_total", "Successful block builds", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, block_building_success_total)},
    {"lean_block_building_failures_total", "Failed block builds (exception in build_block)", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, block_building_failures_total)},
    {"lean_gossip_validation_worker_count", "Number of gossip validation workers", "gauge", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, gossip_validation_worker_count)},
    {"lean_fork_choice_reorgs_total", "Total number of fork choice reorgs", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, fork_choice_reorgs_total)},
    {"lean_attestations_valid_total", "Total number of valid attestations", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, attestations_valid_total)},
    {"lean_attestations_invalid_total", "Total number of invalid attestations", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, attestations_invalid_total)},
    {"lean_pq_sig_attestation_signatures_total", "Total number of individual attestation signatures", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, pq_sig_attestation_signatures_total)},
    {"lean_pq_sig_attestation_signatures_valid_total", "Total number of valid individual attestation signatures", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, pq_sig_attestation_signatures_valid_total)},
    {"lean_pq_sig_attestation_signatures_invalid_total", "Total number of invalid individual attestation signatures", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, pq_sig_attestation_signatures_invalid_total)},
    {"lean_pq_sig_aggregated_signatures_total", "Total number of aggregated signatures", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, pq_sig_aggregated_signatures_total)},
    {"lean_pq_sig_aggregated_signatures_valid_total", "Total number of valid aggregated signatures", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, pq_sig_aggregated_signatures_valid_total)},
    {"lean_pq_sig_aggregated_signatures_invalid_total", "Total number of invalid aggregated signatures", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, pq_sig_aggregated_signatures_invalid_total)},
    {"lean_pq_sig_attestations_in_aggregated_signatures_total", "Total number of attestations included into aggregated signatures", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, pq_sig_attestations_in_aggregated_signatures_total)},
};

static const struct metric_scalar_desc kLeanStateScalars[] = {
    {"lean_state_transition_slots_processed_total", "Total number of processed slots during state transitions", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, state_transition_slots_processed_total)},
    {"lean_state_transition_attestations_processed_total", "Total number of attestations processed during state transitions", "counter", METRIC_SCALAR_LEAN_U64, offsetof(struct lean_metrics_snapshot, state_transition_attestations_processed_total)},
};

static const struct peer_vote_metric_desc kPeerVoteMetrics[] = {
    {"lean_gossip_votes_received_total", "Vote gossip messages received per peer", "counter", offsetof(struct lantern_peer_vote_metric, received_total)},
    {"lean_gossip_votes_accepted_total", "Vote gossip messages accepted per peer", "counter", offsetof(struct lantern_peer_vote_metric, accepted_total)},
    {"lean_gossip_votes_rejected_total", "Vote gossip messages rejected per peer", "counter", offsetof(struct lantern_peer_vote_metric, rejected_total)},
    {"lean_gossip_votes_last_validator_id", "Last validator id observed per peer", "gauge", offsetof(struct lantern_peer_vote_metric, last_validator_id)},
    {"lean_gossip_votes_last_slot", "Last vote slot observed per peer", "gauge", offsetof(struct lantern_peer_vote_metric, last_slot)},
};

static const struct metric_histogram_desc kLeanHistograms[] = {
    {"lean_block_aggregated_payloads", "Number of aggregated_payloads in a block", offsetof(struct lean_metrics_snapshot, block_aggregated_payloads)},
    {"lean_block_building_payload_aggregation_time_seconds", "Time taken to build aggregated_payloads during block building", offsetof(struct lean_metrics_snapshot, block_building_payload_aggregation_time)},
    {"lean_block_building_time_seconds", "Time taken to build a block", offsetof(struct lean_metrics_snapshot, block_building_time)},
    {"lean_attestations_production_time_seconds", "Time taken to produce attestation", offsetof(struct lean_metrics_snapshot, attestations_production_time)},
    {"lean_fork_choice_block_processing_time_seconds", "Time taken to process block in fork choice", offsetof(struct lean_metrics_snapshot, fork_choice_block_time)},
    {"lean_fork_choice_reorg_depth", "Depth of fork choice reorgs (in blocks)", offsetof(struct lean_metrics_snapshot, fork_choice_reorg_depth)},
    {"lean_tick_interval_duration_seconds", "Elapsed time between clock ticks in seconds", offsetof(struct lean_metrics_snapshot, tick_interval_duration)},
    {"lean_attestation_validation_time_seconds", "Time taken to validate attestation", offsetof(struct lean_metrics_snapshot, attestation_validation_time)},
    {"lean_state_transition_time_seconds", "Time to process state transition", offsetof(struct lean_metrics_snapshot, state_transition_time)},
    {"lean_state_transition_slots_processing_time_seconds", "Time taken to process slots during state transition", offsetof(struct lean_metrics_snapshot, state_slots_time)},
    {"lean_state_transition_block_processing_time_seconds", "Time taken to process block during state transition", offsetof(struct lean_metrics_snapshot, state_block_time)},
    {"lean_state_transition_attestations_processing_time_seconds", "Time taken to process attestations during state transition", offsetof(struct lean_metrics_snapshot, state_attestations_time)},
    {"lean_pq_sig_attestation_signing_time_seconds", "Time taken to sign an attestation", offsetof(struct lean_metrics_snapshot, pq_sig_attestation_signing_time)},
    {"lean_pq_sig_attestation_verification_time_seconds", "Time taken to verify an attestation signature", offsetof(struct lean_metrics_snapshot, pq_sig_attestation_verification_time)},
    {"lean_pq_sig_aggregated_signatures_building_time_seconds", "Time taken to build an aggregated attestation signature", offsetof(struct lean_metrics_snapshot, pq_sig_aggregated_signatures_building_time)},
    {"lean_pq_sig_aggregated_signatures_verification_time_seconds", "Time taken to verify an aggregated attestation signature", offsetof(struct lean_metrics_snapshot, pq_sig_aggregated_signatures_verification_time)},
    {"lean_pq_sig_block_aggregated_signatures_verification_time_seconds", "Wall-clock time spent verifying aggregated attestation signatures in a block", offsetof(struct lean_metrics_snapshot, pq_sig_block_aggregated_signatures_verification_time)},
    {"lean_committee_signatures_aggregation_time_seconds", "Time taken to aggregate committee signatures", offsetof(struct lean_metrics_snapshot, committee_signatures_aggregation_time)},
    {"lantern_block_build_stage_vote_collection_seconds", "Per-duty time spent collecting aggregation votes", offsetof(struct lean_metrics_snapshot, block_build_stage_vote_collection_time)},
    {"lantern_block_build_stage_key_sig_deserialize_seconds", "Per-duty time spent deserializing aggregation keys and signatures", offsetof(struct lean_metrics_snapshot, block_build_stage_key_sig_deserialize_time)},
    {"lantern_block_build_stage_pq_aggregate_seconds", "Per-duty time spent in post-quantum signature aggregation", offsetof(struct lean_metrics_snapshot, block_build_stage_pq_aggregate_time)},
    {"lantern_block_build_stage_proof_copy_seconds", "Per-duty time spent copying aggregated proofs", offsetof(struct lean_metrics_snapshot, block_build_stage_proof_copy_time)},
    {"lantern_block_build_stage_lock_waits_seconds", "Per-duty time spent waiting for validator state locks", offsetof(struct lean_metrics_snapshot, block_build_stage_lock_waits_time)},
    {"lantern_block_build_stage_other_prover_setup_seconds", "Per-duty time spent in prover setup and other unclassified work", offsetof(struct lean_metrics_snapshot, block_build_stage_other_prover_setup_time)},
    {"lean_gossip_block_size_bytes", "Bytes size of a gossip block message", offsetof(struct lean_metrics_snapshot, gossip_block_size_bytes)},
    {"lean_gossip_attestation_size_bytes", "Bytes size of a gossip attestation message", offsetof(struct lean_metrics_snapshot, gossip_attestation_size_bytes)},
    {"lean_gossip_aggregation_size_bytes", "Bytes size of a gossip aggregated attestation message", offsetof(struct lean_metrics_snapshot, gossip_aggregation_size_bytes)},
    {"lantern_attestation_inclusion_delay_slots", "Slots between an included attestation's data slot and the block that included it", offsetof(struct lean_metrics_snapshot, attestation_inclusion_delay_slots)},
    {"lantern_block_import_slot_offset_seconds", "Seconds from the start of a block's slot until the block was imported", offsetof(struct lean_metrics_snapshot, block_import_slot_offset_seconds)},
};


/**
 * @brief Append chain and lean subsystem metrics.
 */
static int append_lean_chain_metrics(
    struct lantern_http_buffer *buf,
    const struct lantern_metrics_snapshot *snapshot)
{
    if (!buf || !snapshot)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }
    const struct lean_metrics_snapshot *lean = &snapshot->lean_metrics;

    int rc = lantern_http_buffer_appendf(
        buf,
        "# HELP lean_node_info Node information (always 1)\n"
        "# TYPE lean_node_info gauge\n"
        "lean_node_info{name=\"%s\",version=\"%s\"} 1\n",
        LANTERN_CLIENT_NAME,
        LANTERN_VERSION);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_scalars(
        buf,
        snapshot,
        kChainScalarsBeforeClient,
        ARRAY_LEN(kChainScalarsBeforeClient));
    if (rc != 0)
    {
        return rc;
    }

    rc = append_client_size_t_metrics(
        buf,
        snapshot,
        kClientLabelScalars,
        ARRAY_LEN(kClientLabelScalars));
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_scalars(
        buf,
        snapshot,
        kChainScalarsAfterClient,
        ARRAY_LEN(kChainScalarsAfterClient));
    if (rc != 0)
    {
        return rc;
    }

    rc = lantern_http_buffer_appendf(
        buf,
        "# HELP lean_node_sync_status Node sync status\n"
        "# TYPE lean_node_sync_status gauge\n");
    if (rc != 0)
    {
        return rc;
    }
    for (size_t i = 0; i < ARRAY_LEN(kLeanSyncStatusLabels); ++i)
    {
        rc = lantern_http_buffer_appendf(
            buf,
            "lean_node_sync_status{status=\"%s\"} %" PRIu64 "\n",
            kLeanSyncStatusLabels[i],
            snapshot->lean_node_sync_status == i ? UINT64_C(1) : UINT64_C(0));
        if (rc != 0)
        {
            return rc;
        }
    }

    rc = append_metric_scalars(
        buf,
        snapshot,
        kLeanScalarsBeforeAggregation,
        ARRAY_LEN(kLeanScalarsBeforeAggregation));
    if (rc != 0)
    {
        return rc;
    }

    rc = lantern_http_buffer_appendf(
        buf,
        "# HELP lean_aggregator_skipped_total Total number of aggregation cycles skipped before submission\n"
        "# TYPE lean_aggregator_skipped_total counter\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t reason = 0; reason < LEAN_METRICS_AGGREGATOR_SKIPPED_REASON_COUNT; ++reason)
    {
        rc = lantern_http_buffer_appendf(
            buf,
            "lean_aggregator_skipped_total{reason=\"%s\"} %" PRIu64 "\n",
            kLeanAggregatorSkippedReasonLabels[reason],
            lean->aggregator_skipped_total[reason]);
        if (rc != 0)
        {
            return rc;
        }
    }

    rc = lantern_http_buffer_appendf(
        buf,
        "# HELP lean_finalizations_total Total number of finalization attempts\n"
        "# TYPE lean_finalizations_total counter\n"
        "lean_finalizations_total{result=\"success\"} %" PRIu64 "\n"
        "lean_finalizations_total{result=\"error\"} %" PRIu64 "\n",
        lean->finalizations_success_total,
        lean->finalizations_error_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = lantern_http_buffer_appendf(
        buf,
        "# HELP lantern_attestation_head_votes_total Gossip attestation votes by whether the voted head trailed the vote slot\n"
        "# TYPE lantern_attestation_head_votes_total counter\n"
        "lantern_attestation_head_votes_total{head=\"fresh\"} %" PRIu64 "\n"
        "lantern_attestation_head_votes_total{head=\"stale\"} %" PRIu64 "\n",
        lean->attestation_head_votes_fresh_total,
        lean->attestation_head_votes_stale_total);
    if (rc != 0)
    {
        return rc;
    }

    return append_metric_scalars(
        buf,
        snapshot,
        kLeanStateScalars,
        ARRAY_LEN(kLeanStateScalars));
}


/**
 * @brief Append per-peer vote gossip metrics.
 */
static int append_peer_vote_metrics(
    struct lantern_http_buffer *buf,
    const struct lantern_metrics_snapshot *snapshot)
{
    if (!buf || !snapshot)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }
    if (snapshot->peer_vote_metrics_count == 0)
    {
        return 0;
    }

    size_t count = snapshot->peer_vote_metrics_count;
    if (count > LANTERN_METRICS_MAX_PEER_VOTE_STATS)
    {
        count = LANTERN_METRICS_MAX_PEER_VOTE_STATS;
    }

    for (size_t metric_index = 0; metric_index < ARRAY_LEN(kPeerVoteMetrics); ++metric_index)
    {
        int rc = append_peer_vote_metric(buf, snapshot, &kPeerVoteMetrics[metric_index], count);
        if (rc != 0)
        {
            return rc;
        }
    }

    return 0;
}

/**
 * @brief Append peer connection metrics derived from the lean metrics snapshot.
 */
static int append_lean_peer_connection_metrics(
    struct lantern_http_buffer *buf,
    const struct lean_metrics_snapshot *lean)
{
    if (!buf || !lean)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    int rc = lantern_http_buffer_appendf(
        buf,
        "# HELP lean_peer_connection_events_total Total number of peer connection events\n"
        "# TYPE lean_peer_connection_events_total counter\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t dir = 0; dir < LEAN_METRICS_DIR_COUNT; ++dir)
    {
        for (size_t res = 0; res < LEAN_METRICS_CONN_RESULT_COUNT; ++res)
        {
            rc = lantern_http_buffer_appendf(
                buf,
                "lean_peer_connection_events_total{direction=\"%s\",result=\"%s\"} %" PRIu64 "\n",
                kLeanDirectionLabels[dir],
                kLeanConnectionResultLabels[res],
                lean->peer_connection_events_total[dir][res]);
            if (rc != 0)
            {
                return rc;
            }
        }
    }

    rc = lantern_http_buffer_appendf(
        buf,
        "# HELP lean_peer_disconnection_events_total Total number of peer disconnection events\n"
        "# TYPE lean_peer_disconnection_events_total counter\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t dir = 0; dir < LEAN_METRICS_DIR_COUNT; ++dir)
    {
        for (size_t reason = 0; reason < LEAN_METRICS_DISCONNECT_REASON_COUNT; ++reason)
        {
            rc = lantern_http_buffer_appendf(
                buf,
                "lean_peer_disconnection_events_total{direction=\"%s\",reason=\"%s\"} %" PRIu64 "\n",
                kLeanDirectionLabels[dir],
                kLeanDisconnectionReasonLabels[reason],
                lean->peer_disconnection_events_total[dir][reason]);
            if (rc != 0)
            {
                return rc;
            }
        }
    }

    return 0;
}


/**
 * @brief Append histogram metrics derived from the lean metrics snapshot.
 */
static int append_lean_histograms(
    struct lantern_http_buffer *buf,
    const struct lean_metrics_snapshot *lean)
{
    if (!buf || !lean)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    return append_histogram_descs(
        buf,
        lean,
        kLeanHistograms,
        ARRAY_LEN(kLeanHistograms));
}


/**
 * Format a metrics snapshot as a Prometheus text body.
 *
 * @param snapshot Metrics snapshot (not modified).
 * @param out_body Output heap buffer (caller owns on success).
 * @param out_len  Output body length in bytes (excluding terminator).
 *
 * @return 0 on success.
 * @return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_METRICS_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_METRICS_SERVER_ERR_OVERFLOW on size overflow.
 * @return LANTERN_METRICS_SERVER_ERR_FORMATTING on formatting failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int format_metrics_body(
    const struct lantern_metrics_snapshot *snapshot,
    char **out_body,
    size_t *out_len)
{
    if (!snapshot || !out_body || !out_len)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    int result = 0;
    struct lantern_http_buffer buf;
    memset(&buf, 0, sizeof(buf));

    result = lantern_http_buffer_init(&buf, LANTERN_METRICS_BODY_INITIAL_CAP);
    if (result != 0)
    {
        return result;
    }

    result = append_lean_chain_metrics(&buf, snapshot);
    if (result != 0)
    {
        goto cleanup;
    }

    result = append_peer_vote_metrics(&buf, snapshot);
    if (result != 0)
    {
        goto cleanup;
    }

    result = append_lean_peer_connection_metrics(&buf, &snapshot->lean_metrics);
    if (result != 0)
    {
        goto cleanup;
    }

    result = append_lean_histograms(&buf, &snapshot->lean_metrics);
    if (result != 0)
    {
        goto cleanup;
    }

    *out_body = buf.data;
    *out_len = buf.len;
    buf.data = NULL;
    result = 0;

cleanup:
    lantern_http_buffer_free(&buf);
    return result;
}

int lantern_metrics_format_prometheus(
    const struct lantern_metrics_snapshot *snapshot,
    char **out_body,
    size_t *out_len)
{
    if (!snapshot || !out_body || !out_len)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }
    int result = format_metrics_body(snapshot, out_body, out_len);
    if (result != 0)
    {
        return result;
    }
    return 0;
}

int lantern_metrics_handle_http(
    void *context,
    const struct lantern_http_request *request)
{
    struct lantern_metrics_http_handler *handler = context;
    if (!handler || !request)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }
    const char *log_module = handler->log_module ? handler->log_module : "metrics";
    const char *unavailable_json =
        handler->unavailable_json ? handler->unavailable_json : METRICS_JSON_UNAVAILABLE;
    const char *formatting_json =
        handler->formatting_failed_json
            ? handler->formatting_failed_json
            : METRICS_JSON_FORMATTING_FAILED;

    if (!handler->callbacks.snapshot)
    {
        int rc = lantern_http_send_json_error(
            request->client_fd,
            503,
            "Service Unavailable",
            unavailable_json);
        lantern_log_error(
            log_module,
            &(const struct lantern_log_metadata){.peer = request->peer},
            "metrics callback missing rc=%d",
            rc);
        return rc;
    }

    struct lantern_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    if (handler->callbacks.snapshot(handler->callbacks.context, &snapshot) != 0)
    {
        int rc = lantern_http_send_json_error(
            request->client_fd,
            503,
            "Service Unavailable",
            unavailable_json);
        lantern_log_error(
            log_module,
            &(const struct lantern_log_metadata){.peer = request->peer},
            "snapshot failed rc=%d",
            rc);
        return rc;
    }

    char *body = NULL;
    size_t body_len = 0;
    int result = format_metrics_body(&snapshot, &body, &body_len);
    if (result != 0)
    {
        int rc = lantern_http_send_json_error(
            request->client_fd,
            500,
            "Internal Server Error",
            formatting_json);
        lantern_log_error(
            log_module,
            &(const struct lantern_log_metadata){.peer = request->peer},
            "formatting failed result=%d send_rc=%d",
            result,
            rc);
        return rc;
    }

    result = lantern_http_send_response(
        request->client_fd,
        200,
        "OK",
        LANTERN_METRICS_CONTENT_TYPE,
        body,
        body_len);
    free(body);
    if (result != 0)
    {
        lantern_log_error(
            log_module,
            &(const struct lantern_log_metadata){.peer = request->peer},
            "send failed rc=%d",
            result);
        return result;
    }

    lantern_log_info(
        log_module,
        &(const struct lantern_log_metadata){.peer = request->peer},
        "%s %s -> 200",
        request->method,
        request->path);
    return 0;
}

static int handle_standalone_metrics_route(
    void *context,
    const struct lantern_http_request *request)
{
    struct lantern_metrics_server *server = context;
    if (!server)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }
    return lantern_metrics_handle_http(&server->handler, request);
}

static const struct lantern_http_route kMetricsRoutes[] = {
    {"GET", LANTERN_METRICS_ENDPOINT_PATH, handle_standalone_metrics_route},
};

void lantern_metrics_server_init(struct lantern_metrics_server *server)
{
    if (!server)
    {
        return;
    }

    memset(server, 0, sizeof(*server));
    lantern_http_core_init(&server->core);
    server->port = 0;
}

int lantern_metrics_server_start(
    struct lantern_metrics_server *server,
    uint16_t port,
    const struct lantern_metrics_callbacks *callbacks)
{
    if (!server || !callbacks || !callbacks->snapshot)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    server->callbacks = *callbacks;
    server->handler.callbacks = *callbacks;
    server->handler.log_module = "metrics";
    server->handler.unavailable_json = METRICS_JSON_UNAVAILABLE;
    server->handler.formatting_failed_json = METRICS_JSON_FORMATTING_FAILED;
    server->port = port;

    struct lantern_http_core_config config;
    memset(&config, 0, sizeof(config));
    config.port = port;
    config.log_module = "metrics";
    config.listen_label = "metrics server";
    config.malformed_json = METRICS_JSON_MALFORMED_REQUEST;
    config.unknown_json = METRICS_JSON_UNKNOWN_ENDPOINT;
    config.method_cap = LANTERN_HTTP_CORE_METHOD_CAP;
    config.path_cap = LANTERN_HTTP_CORE_METRICS_PATH_CAP;
    config.listen_backlog = LANTERN_HTTP_CORE_LISTEN_BACKLOG;
    config.capture_bound_port = false;
    config.context = server;
    config.routes = kMetricsRoutes;
    config.route_count = ARRAY_LEN(kMetricsRoutes);

    int rc = lantern_http_core_start(&server->core, &config);
    return rc == 0 ? 0 : LANTERN_METRICS_SERVER_ERR_IO;
}

void lantern_metrics_server_stop(struct lantern_metrics_server *server)
{
    if (!server)
    {
        return;
    }

    lantern_http_core_stop(&server->core);
}
