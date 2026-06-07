/**
 * @file metrics.c
 * @brief Prometheus metrics HTTP endpoint.
 *
 * Exposes a Prometheus-compatible metrics endpoint:
 * - GET /metrics
 *
 * Metrics are generated from a caller-provided snapshot callback.
 *
 * @spec Prometheus exposition format 0.0.4 and POSIX sockets/pthreads.
 */

#include "lantern/http/metrics.h"

#include <arpa/inet.h>
#include <errno.h>
#include <inttypes.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "lantern/http/common.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "lantern/support/version.h"

static const size_t LANTERN_METRICS_READ_BUFFER_SIZE = 4096;
static const size_t LANTERN_METRICS_BODY_DEFAULT_CAP = 1024;
static const size_t LANTERN_METRICS_BODY_INITIAL_CAP = 2048;
static const int LANTERN_METRICS_LISTEN_BACKLOG = 16;
static const char LANTERN_METRICS_ENDPOINT_PATH[] = "/metrics";
static const char *const kLeanDirectionLabels[LEAN_METRICS_DIR_COUNT] = {"inbound", "outbound"};
static const char *const kLeanConnectionResultLabels[LEAN_METRICS_CONN_RESULT_COUNT] = {"success", "timeout", "error"};
static const char *const kLeanDisconnectionReasonLabels[LEAN_METRICS_DISCONNECT_REASON_COUNT] =
    {"timeout", "remote_close", "local_close", "error"};
static const char *const kLeanAggregatorSkippedReasonLabels[LEAN_METRICS_AGGREGATOR_SKIPPED_REASON_COUNT] =
    {"not_aggregator", "not_synced", "missing_state", "spawn_failed", "other"};
static const char *const kLeanSyncStatusLabels[] = {"idle", "syncing", "synced"};

enum
{
    LANTERN_METRICS_METHOD_CAP = 8,
    LANTERN_METRICS_PATH_CAP = 128,
};

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

struct lantern_metrics_body_buffer
{
    char *data;  /**< Heap buffer (NUL-terminated). */
    size_t len;  /**< Bytes written (excluding terminator). */
    size_t cap;  /**< Allocated capacity in bytes. */
};

/**
 * @brief Initialize a dynamic metrics body buffer.
 *
 * @param buf         Buffer to initialize (modified in place).
 * @param initial_cap Initial allocation size in bytes (0 uses default).
 *
 * @return 0 on success.
 * @return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_METRICS_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int metrics_buffer_init(struct lantern_metrics_body_buffer *buf, size_t initial_cap)
{
    if (!buf)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    size_t capacity = initial_cap != 0 ? initial_cap : LANTERN_METRICS_BODY_DEFAULT_CAP;
    buf->data = malloc(capacity);
    if (!buf->data)
    {
        return LANTERN_METRICS_SERVER_ERR_OUT_OF_MEMORY;
    }

    buf->len = 0;
    buf->cap = capacity;
    buf->data[0] = '\0';
    return 0;
}


/**
 * @brief Free resources owned by a metrics body buffer.
 *
 * @param buf Buffer to free (may be NULL).
 *
 * @note Thread safety: This function is thread-safe.
 */
static void metrics_buffer_free(struct lantern_metrics_body_buffer *buf)
{
    if (!buf)
    {
        return;
    }

    free(buf->data);
    buf->data = NULL;
    buf->len = 0;
    buf->cap = 0;
}


/**
 * @brief Ensure the buffer can append the requested number of bytes.
 *
 * @param buf   Buffer to grow (modified in place).
 * @param extra Additional bytes required (excluding NUL terminator).
 *
 * @return 0 on success.
 * @return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_METRICS_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_METRICS_SERVER_ERR_OVERFLOW on size overflow.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int metrics_buffer_reserve(struct lantern_metrics_body_buffer *buf, size_t extra)
{
    if (!buf)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }
    if (extra == 0)
    {
        return 0;
    }

    if (buf->len >= SIZE_MAX - 1)
    {
        return LANTERN_METRICS_SERVER_ERR_OVERFLOW;
    }
    if (extra > (SIZE_MAX - buf->len - 1))
    {
        return LANTERN_METRICS_SERVER_ERR_OVERFLOW;
    }

    size_t required = buf->len + extra + 1;
    if (required <= buf->cap)
    {
        return 0;
    }

    size_t new_cap = buf->cap != 0 ? buf->cap : LANTERN_METRICS_BODY_DEFAULT_CAP;
    while (new_cap < required)
    {
        if (new_cap > SIZE_MAX / 2)
        {
            return LANTERN_METRICS_SERVER_ERR_OVERFLOW;
        }
        new_cap *= 2;
    }

    char *new_data = realloc(buf->data, new_cap);
    if (!new_data)
    {
        return LANTERN_METRICS_SERVER_ERR_OUT_OF_MEMORY;
    }

    buf->data = new_data;
    buf->cap = new_cap;
    return 0;
}


/**
 * @brief Append formatted text to a metrics body buffer.
 *
 * @param buf Buffer to append to (modified in place).
 * @param fmt printf-style format string.
 *
 * @return 0 on success.
 * @return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_METRICS_SERVER_ERR_OUT_OF_MEMORY on allocation failure.
 * @return LANTERN_METRICS_SERVER_ERR_OVERFLOW on size overflow.
 * @return LANTERN_METRICS_SERVER_ERR_FORMATTING on formatting failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int metrics_buffer_appendf(struct lantern_metrics_body_buffer *buf, const char *fmt, ...)
{
    if (!buf || !fmt)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    va_list args;
    va_start(args, fmt);

    va_list measure;
    va_copy(measure, args);
    int needed = vsnprintf(NULL, 0, fmt, measure);
    va_end(measure);
    if (needed < 0)
    {
        va_end(args);
        return LANTERN_METRICS_SERVER_ERR_FORMATTING;
    }

    int reserve_rc = metrics_buffer_reserve(buf, (size_t)needed);
    if (reserve_rc != 0)
    {
        va_end(args);
        return reserve_rc;
    }

    int written = vsnprintf(buf->data + buf->len, buf->cap - buf->len, fmt, args);
    va_end(args);
    if (written < 0 || written != needed)
    {
        return LANTERN_METRICS_SERVER_ERR_FORMATTING;
    }

    buf->len += (size_t)written;
    return 0;
}


/**
 * @brief Append a single Prometheus metric with a uint64 value.
 */
static int append_metric_uint64(
    struct lantern_metrics_body_buffer *buf,
    const char *name,
    const char *help,
    const char *type,
    uint64_t value)
{
    return metrics_buffer_appendf(
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
    struct lantern_metrics_body_buffer *buf,
    const char *name,
    const char *help,
    const char *type,
    size_t value)
{
    return metrics_buffer_appendf(
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
    struct lantern_metrics_body_buffer *buf,
    const char *name,
    const char *help,
    const struct lean_metrics_histogram_snapshot *hist)
{
    if (!buf || !name || !help || !hist)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    int rc = metrics_buffer_appendf(
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
        rc = metrics_buffer_appendf(
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

    rc = metrics_buffer_appendf(
        buf,
        "%s_bucket{le=\"+Inf\"} %" PRIu64 "\n",
        name,
        hist->total);
    if (rc != 0)
    {
        return rc;
    }

    rc = metrics_buffer_appendf(
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


/**
 * @brief Append chain and lean subsystem metrics.
 */
static int append_lean_chain_metrics(
    struct lantern_metrics_body_buffer *buf,
    const struct lantern_metrics_snapshot *snapshot)
{
    if (!buf || !snapshot)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    int rc = metrics_buffer_appendf(
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

    rc = append_metric_uint64(
        buf,
        "lean_node_start_time_seconds",
        "Start timestamp",
        "gauge",
        snapshot->lean_node_start_time_seconds);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_head_slot",
        "Latest slot of the lean chain",
        "gauge",
        snapshot->lean_head_slot);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_current_slot",
        "Current slot of the lean chain",
        "gauge",
        snapshot->lean_current_slot);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_safe_target_slot",
        "Safe target slot",
        "gauge",
        snapshot->lean_safe_target_slot);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_latest_justified_slot",
        "Latest justified slot observed by state transition",
        "gauge",
        snapshot->lean_latest_justified_slot);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_latest_finalized_slot",
        "Latest finalized slot observed by state transition",
        "gauge",
        snapshot->lean_latest_finalized_slot);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_justified_slot",
        "Current justified slot",
        "gauge",
        snapshot->lean_justified_slot);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_finalized_slot",
        "Current finalized slot",
        "gauge",
        snapshot->lean_finalized_slot);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_size_t(
        buf,
        "lean_validators_count",
        "Number of validators connected to this client",
        "gauge",
        snapshot->lean_validators_count);
    if (rc != 0)
    {
        return rc;
    }

    rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_connected_peers Number of connected peers\n"
        "# TYPE lean_connected_peers gauge\n"
        "lean_connected_peers{client=\"%s\"} %zu\n",
        metrics_client_label(snapshot),
        snapshot->lean_connected_peers);
    if (rc != 0)
    {
        return rc;
    }

    rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_gossip_mesh_peers Number of peers in the gossipsub mesh\n"
        "# TYPE lean_gossip_mesh_peers gauge\n"
        "lean_gossip_mesh_peers{client=\"%s\"} %zu\n",
        metrics_client_label(snapshot),
        snapshot->lean_gossip_mesh_peers);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_gossip_signatures",
        "Current number of gossip signatures in fork-choice store",
        "gauge",
        snapshot->lean_gossip_signatures);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_latest_new_aggregated_payloads",
        "Current number of new aggregated payloads",
        "gauge",
        snapshot->lean_latest_new_aggregated_payloads);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_latest_known_aggregated_payloads",
        "Current number of known aggregated payloads",
        "gauge",
        snapshot->lean_latest_known_aggregated_payloads);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_is_aggregator",
        "Validator is_aggregator status (1=true, 0=false)",
        "gauge",
        snapshot->lean_is_aggregator);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_attestation_committee_subnet",
        "Current committee attestation subnet",
        "gauge",
        snapshot->lean_attestation_committee_subnet);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_attestation_committee_count",
        "Number of attestation committees",
        "gauge",
        snapshot->lean_attestation_committee_count);
    if (rc != 0)
    {
        return rc;
    }

    rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_node_sync_status Node sync status\n"
        "# TYPE lean_node_sync_status gauge\n");
    if (rc != 0)
    {
        return rc;
    }
    for (size_t i = 0; i < (sizeof(kLeanSyncStatusLabels) / sizeof(kLeanSyncStatusLabels[0])); ++i)
    {
        rc = metrics_buffer_appendf(
            buf,
            "lean_node_sync_status{status=\"%s\"} %" PRIu64 "\n",
            kLeanSyncStatusLabels[i],
            snapshot->lean_node_sync_status == i ? UINT64_C(1) : UINT64_C(0));
        if (rc != 0)
        {
            return rc;
        }
    }

    const struct lean_metrics_snapshot *lean = &snapshot->lean_metrics;

    rc = append_metric_uint64(
        buf,
        "lean_block_building_success_total",
        "Successful block builds",
        "counter",
        lean->block_building_success_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_block_building_failures_total",
        "Failed block builds (exception in build_block)",
        "counter",
        lean->block_building_failures_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_gossip_validation_worker_count",
        "Number of gossip validation workers",
        "gauge",
        lean->gossip_validation_worker_count);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_fork_choice_reorgs_total",
        "Total number of fork choice reorgs",
        "counter",
        lean->fork_choice_reorgs_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_attestations_valid_total",
        "Total number of valid attestations",
        "counter",
        lean->attestations_valid_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_attestations_invalid_total",
        "Total number of invalid attestations",
        "counter",
        lean->attestations_invalid_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_pq_sig_attestation_signatures_total",
        "Total number of individual attestation signatures",
        "counter",
        lean->pq_sig_attestation_signatures_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_pq_sig_attestation_signatures_valid_total",
        "Total number of valid individual attestation signatures",
        "counter",
        lean->pq_sig_attestation_signatures_valid_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_pq_sig_attestation_signatures_invalid_total",
        "Total number of invalid individual attestation signatures",
        "counter",
        lean->pq_sig_attestation_signatures_invalid_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_pq_sig_aggregated_signatures_total",
        "Total number of aggregated signatures",
        "counter",
        lean->pq_sig_aggregated_signatures_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_pq_sig_aggregated_signatures_valid_total",
        "Total number of valid aggregated signatures",
        "counter",
        lean->pq_sig_aggregated_signatures_valid_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_pq_sig_aggregated_signatures_invalid_total",
        "Total number of invalid aggregated signatures",
        "counter",
        lean->pq_sig_aggregated_signatures_invalid_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_pq_sig_attestations_in_aggregated_signatures_total",
        "Total number of attestations included into aggregated signatures",
        "counter",
        lean->pq_sig_attestations_in_aggregated_signatures_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_aggregator_skipped_total Total number of aggregation cycles skipped before submission\n"
        "# TYPE lean_aggregator_skipped_total counter\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t reason = 0; reason < LEAN_METRICS_AGGREGATOR_SKIPPED_REASON_COUNT; ++reason)
    {
        rc = metrics_buffer_appendf(
            buf,
            "lean_aggregator_skipped_total{reason=\"%s\"} %" PRIu64 "\n",
            kLeanAggregatorSkippedReasonLabels[reason],
            lean->aggregator_skipped_total[reason]);
        if (rc != 0)
        {
            return rc;
        }
    }

    rc = metrics_buffer_appendf(
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

    rc = append_metric_uint64(
        buf,
        "lean_state_transition_slots_processed_total",
        "Total number of processed slots during state transitions",
        "counter",
        lean->state_transition_slots_processed_total);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_metric_uint64(
        buf,
        "lean_state_transition_attestations_processed_total",
        "Total number of attestations processed during state "
        "transitions",
        "counter",
        lean->state_transition_attestations_processed_total);
    if (rc != 0)
    {
        return rc;
    }

    return 0;
}


/**
 * @brief Append per-peer vote gossip metrics.
 */
static int append_peer_vote_metrics(
    struct lantern_metrics_body_buffer *buf,
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

    int rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_gossip_votes_received_total Vote gossip messages received per peer\n"
        "# TYPE lean_gossip_votes_received_total counter\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t i = 0; i < count; ++i)
    {
        const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
        char peer_id[sizeof(metric->peer_id)];
        (void)lantern_string_copy(peer_id, sizeof(peer_id), metric->peer_id);

        rc = metrics_buffer_appendf(
            buf,
            "lean_gossip_votes_received_total{peer=\"%s\"} %" PRIu64 "\n",
            peer_id,
            metric->received_total);
        if (rc != 0)
        {
            return rc;
        }
    }

    rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_gossip_votes_accepted_total Vote gossip messages accepted per peer\n"
        "# TYPE lean_gossip_votes_accepted_total counter\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t i = 0; i < count; ++i)
    {
        const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
        char peer_id[sizeof(metric->peer_id)];
        (void)lantern_string_copy(peer_id, sizeof(peer_id), metric->peer_id);

        rc = metrics_buffer_appendf(
            buf,
            "lean_gossip_votes_accepted_total{peer=\"%s\"} %" PRIu64 "\n",
            peer_id,
            metric->accepted_total);
        if (rc != 0)
        {
            return rc;
        }
    }

    rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_gossip_votes_rejected_total Vote gossip messages rejected per peer\n"
        "# TYPE lean_gossip_votes_rejected_total counter\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t i = 0; i < count; ++i)
    {
        const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
        char peer_id[sizeof(metric->peer_id)];
        (void)lantern_string_copy(peer_id, sizeof(peer_id), metric->peer_id);

        rc = metrics_buffer_appendf(
            buf,
            "lean_gossip_votes_rejected_total{peer=\"%s\"} %" PRIu64 "\n",
            peer_id,
            metric->rejected_total);
        if (rc != 0)
        {
            return rc;
        }
    }

    rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_gossip_votes_last_validator_id Last validator id observed per peer\n"
        "# TYPE lean_gossip_votes_last_validator_id gauge\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t i = 0; i < count; ++i)
    {
        const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
        char peer_id[sizeof(metric->peer_id)];
        (void)lantern_string_copy(peer_id, sizeof(peer_id), metric->peer_id);

        rc = metrics_buffer_appendf(
            buf,
            "lean_gossip_votes_last_validator_id{peer=\"%s\"} %" PRIu64 "\n",
            peer_id,
            metric->last_validator_id);
        if (rc != 0)
        {
            return rc;
        }
    }

    rc = metrics_buffer_appendf(
        buf,
        "# HELP lean_gossip_votes_last_slot Last vote slot observed per peer\n"
        "# TYPE lean_gossip_votes_last_slot gauge\n");
    if (rc != 0)
    {
        return rc;
    }

    for (size_t i = 0; i < count; ++i)
    {
        const struct lantern_peer_vote_metric *metric = &snapshot->peer_vote_metrics[i];
        char peer_id[sizeof(metric->peer_id)];
        (void)lantern_string_copy(peer_id, sizeof(peer_id), metric->peer_id);

        rc = metrics_buffer_appendf(
            buf,
            "lean_gossip_votes_last_slot{peer=\"%s\"} %" PRIu64 "\n",
            peer_id,
            metric->last_slot);
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
    struct lantern_metrics_body_buffer *buf,
    const struct lean_metrics_snapshot *lean)
{
    if (!buf || !lean)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    int rc = metrics_buffer_appendf(
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
            rc = metrics_buffer_appendf(
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

    rc = metrics_buffer_appendf(
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
            rc = metrics_buffer_appendf(
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
    struct lantern_metrics_body_buffer *buf,
    const struct lean_metrics_snapshot *lean)
{
    if (!buf || !lean)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    int rc = append_histogram_metrics(
        buf,
        "lean_block_aggregated_payloads",
        "Number of aggregated_payloads in a block",
        &lean->block_aggregated_payloads);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_block_building_payload_aggregation_time_seconds",
        "Time taken to build aggregated_payloads during block building",
        &lean->block_building_payload_aggregation_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_block_building_time_seconds",
        "Time taken to build a block",
        &lean->block_building_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_attestations_production_time_seconds",
        "Time taken to produce attestation",
        &lean->attestations_production_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_fork_choice_block_processing_time_seconds",
        "Time taken to process block in fork choice",
        &lean->fork_choice_block_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_fork_choice_reorg_depth",
        "Depth of fork choice reorgs (in blocks)",
        &lean->fork_choice_reorg_depth);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_tick_interval_duration_seconds",
        "Elapsed time between clock ticks in seconds",
        &lean->tick_interval_duration);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_attestation_validation_time_seconds",
        "Time taken to validate attestation",
        &lean->attestation_validation_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_state_transition_time_seconds",
        "Time to process state transition",
        &lean->state_transition_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_state_transition_slots_processing_time_seconds",
        "Time taken to process slots during state transition",
        &lean->state_slots_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_state_transition_block_processing_time_seconds",
        "Time taken to process block during state transition",
        &lean->state_block_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_state_transition_attestations_processing_time_seconds",
        "Time taken to process attestations during state transition",
        &lean->state_attestations_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_pq_sig_attestation_signing_time_seconds",
        "Time taken to sign an attestation",
        &lean->pq_sig_attestation_signing_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_pq_sig_attestation_verification_time_seconds",
        "Time taken to verify an attestation signature",
        &lean->pq_sig_attestation_verification_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_pq_sig_aggregated_signatures_building_time_seconds",
        "Time taken to build an aggregated attestation signature",
        &lean->pq_sig_aggregated_signatures_building_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_pq_sig_aggregated_signatures_verification_time_seconds",
        "Time taken to verify an aggregated attestation signature",
        &lean->pq_sig_aggregated_signatures_verification_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_pq_sig_block_aggregated_signatures_verification_time_seconds",
        "Wall-clock time spent verifying aggregated attestation signatures in a block",
        &lean->pq_sig_block_aggregated_signatures_verification_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_committee_signatures_aggregation_time_seconds",
        "Time taken to aggregate committee signatures",
        &lean->committee_signatures_aggregation_time);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_gossip_block_size_bytes",
        "Bytes size of a gossip block message",
        &lean->gossip_block_size_bytes);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_gossip_attestation_size_bytes",
        "Bytes size of a gossip attestation message",
        &lean->gossip_attestation_size_bytes);
    if (rc != 0)
    {
        return rc;
    }

    rc = append_histogram_metrics(
        buf,
        "lean_gossip_aggregation_size_bytes",
        "Bytes size of a gossip aggregated attestation message",
        &lean->gossip_aggregation_size_bytes);
    if (rc != 0)
    {
        return rc;
    }

    return 0;
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
    struct lantern_metrics_body_buffer buf;
    memset(&buf, 0, sizeof(buf));

    result = metrics_buffer_init(&buf, LANTERN_METRICS_BODY_INITIAL_CAP);
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
    metrics_buffer_free(&buf);
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


/**
 * Convert a peer address to a printable string.
 *
 * @param peer_addr Peer address (may be NULL).
 * @param out       Output buffer (NUL-terminated on return).
 * @param out_len   Output buffer length.
 *
 * @note Thread safety: This function is thread-safe.
 */
static void peer_to_text(const struct sockaddr_in *peer_addr, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return;
    }

    const char *fallback = "unknown";
    if (!peer_addr)
    {
        (void)lantern_string_copy(out, out_len, fallback);
        return;
    }

    if (!inet_ntop(AF_INET, &peer_addr->sin_addr, out, out_len))
    {
        (void)lantern_string_copy(out, out_len, fallback);
    }
}


/**
 * Parse a minimal HTTP request line (method and path).
 *
 * @param request    Request bytes (NUL-terminated).
 * @param method     Output method buffer (NUL-terminated on success).
 * @param method_len Method buffer length.
 * @param path       Output path buffer (NUL-terminated on success).
 * @param path_len   Path buffer length.
 *
 * @return 0 on success.
 * @return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_METRICS_SERVER_ERR_MALFORMED_REQUEST on parse failure.
 *
 * @note Thread safety: This function is thread-safe.
 */
static int parse_request_line(
    const char *request,
    char *method,
    size_t method_len,
    char *path,
    size_t path_len)
{
    if (!request || !method || method_len == 0 || !path || path_len == 0)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    const char *space = strchr(request, ' ');
    if (!space)
    {
        return LANTERN_METRICS_SERVER_ERR_MALFORMED_REQUEST;
    }

    size_t method_written = (size_t)(space - request);
    if (method_written == 0 || method_written >= method_len)
    {
        return LANTERN_METRICS_SERVER_ERR_MALFORMED_REQUEST;
    }

    memcpy(method, request, method_written);
    method[method_written] = '\0';

    const char *cursor = space;
    while (*cursor == ' ')
    {
        ++cursor;
    }
    if (*cursor == '\0')
    {
        return LANTERN_METRICS_SERVER_ERR_MALFORMED_REQUEST;
    }

    const char *path_start = cursor;
    while (*cursor != '\0'
        && *cursor != ' '
        && *cursor != '\r'
        && *cursor != '\n'
        && *cursor != '\t')
    {
        ++cursor;
    }

    size_t path_written = (size_t)(cursor - path_start);
    if (path_written == 0 || path_written >= path_len)
    {
        return LANTERN_METRICS_SERVER_ERR_MALFORMED_REQUEST;
    }

    memcpy(path, path_start, path_written);
    path[path_written] = '\0';
    return 0;
}


/**
 * Send an HTTP response and map common errors to metrics error codes.
 *
 * @param client_fd    Client socket file descriptor.
 * @param status_code  HTTP status code.
 * @param status_text  HTTP status text.
 * @param content_type Content-Type header value.
 * @param body         Response body (may be NULL when body_len is 0).
 * @param body_len     Response body length in bytes.
 *
 * @return 0 on success.
 * @return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_METRICS_SERVER_ERR_FORMATTING on header formatting failure.
 * @return LANTERN_METRICS_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: Caller must ensure exclusive access to client_fd.
 */
static int send_http_response(
    int client_fd,
    int status_code,
    const char *status_text,
    const char *content_type,
    const char *body,
    size_t body_len)
{
    int rc = lantern_http_send_response(
        client_fd,
        status_code,
        status_text,
        content_type,
        body,
        body_len);
    if (rc == 0)
    {
        return 0;
    }

    if (rc == -1)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }
    if (rc == -3)
    {
        return LANTERN_METRICS_SERVER_ERR_FORMATTING;
    }
    return LANTERN_METRICS_SERVER_ERR_IO;
}


/**
 * Send a JSON error response.
 *
 * @param client_fd   Client socket file descriptor.
 * @param status_code HTTP status code.
 * @param status_text HTTP status text.
 * @param json_body   JSON body (may be NULL).
 *
 * @return 0 on success.
 * @return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_METRICS_SERVER_ERR_FORMATTING on formatting failure.
 * @return LANTERN_METRICS_SERVER_ERR_IO on send failure.
 *
 * @note Thread safety: Caller must ensure exclusive access to client_fd.
 */
static int send_json_error(
    int client_fd,
    int status_code,
    const char *status_text,
    const char *json_body)
{
    if (!json_body)
    {
        return send_http_response(client_fd, status_code, status_text, "application/json", NULL, 0);
    }

    return send_http_response(
        client_fd,
        status_code,
        status_text,
        "application/json",
        json_body,
        strlen(json_body));
}


/**
 * Handle a single client connection.
 *
 * @param server    Metrics server instance.
 * @param client_fd Client socket file descriptor.
 * @param peer_addr Peer address (may be NULL).
 *
 * @note Thread safety: This function is thread-safe if callbacks are thread-safe.
 */
static void handle_client_connection(
    struct lantern_metrics_server *server,
    int client_fd,
    const struct sockaddr_in *peer_addr)
{
    if (!server || client_fd < 0)
    {
        return;
    }

    char peer_text[INET_ADDRSTRLEN];
    peer_to_text(peer_addr, peer_text, sizeof(peer_text));

    char buffer[LANTERN_METRICS_READ_BUFFER_SIZE];
    ssize_t received = -1;
    do
    {
        received = recv(client_fd, buffer, sizeof(buffer) - 1, 0);
    } while (received < 0 && errno == EINTR);

    if (received <= 0)
    {
        return;
    }
    buffer[(size_t)received] = '\0';

    char method[LANTERN_METRICS_METHOD_CAP];
    char path[LANTERN_METRICS_PATH_CAP];

    int result = parse_request_line(buffer, method, sizeof(method), path, sizeof(path));
    if (result != 0)
    {
        int rc = send_json_error(client_fd, 400, "Bad Request", METRICS_JSON_MALFORMED_REQUEST);
        if (rc == 0)
        {
            lantern_log_info(
                "metrics",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "malformed request -> 400");
        }
        else
        {
            lantern_log_error(
                "metrics",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "failed to send 400 response rc=%d",
                rc);
        }
        return;
    }

    if (strcmp(method, "GET") != 0 || strcmp(path, LANTERN_METRICS_ENDPOINT_PATH) != 0)
    {
        int rc = send_json_error(client_fd, 404, "Not Found", METRICS_JSON_UNKNOWN_ENDPOINT);
        if (rc == 0)
        {
            lantern_log_info(
                "metrics",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "%s %s -> 404",
                method,
                path);
        }
        else
        {
            lantern_log_error(
                "metrics",
                &(const struct lantern_log_metadata){.peer = peer_text},
                "failed to send 404 response rc=%d",
                rc);
        }
        return;
    }

    if (!server->callbacks.snapshot)
    {
        int rc = send_json_error(client_fd, 503, "Service Unavailable", METRICS_JSON_UNAVAILABLE);
        lantern_log_error(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "metrics callback missing rc=%d",
            rc);
        return;
    }

    struct lantern_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    if (server->callbacks.snapshot(server->callbacks.context, &snapshot) != 0)
    {
        int rc = send_json_error(client_fd, 503, "Service Unavailable", METRICS_JSON_UNAVAILABLE);
        lantern_log_error(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "snapshot failed rc=%d",
            rc);
        return;
    }

    char *body = NULL;
    size_t body_len = 0;
    result = format_metrics_body(&snapshot, &body, &body_len);
    if (result != 0)
    {
        int rc = send_json_error(
            client_fd,
            500,
            "Internal Server Error",
            METRICS_JSON_FORMATTING_FAILED);
        lantern_log_error(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "formatting failed result=%d send_rc=%d",
            result,
            rc);
        return;
    }

    result = send_http_response(
        client_fd,
        200,
        "OK",
        LANTERN_METRICS_CONTENT_TYPE,
        body,
        body_len);
    free(body);
    if (result != 0)
    {
        lantern_log_error(
            "metrics",
            &(const struct lantern_log_metadata){.peer = peer_text},
            "send failed rc=%d",
            result);
        return;
    }

    lantern_log_info(
        "metrics",
        &(const struct lantern_log_metadata){.peer = peer_text},
        "%s %s -> 200",
        method,
        path);
}


/**
 * Thread entry point for the metrics server accept loop.
 *
 * @param arg Pointer to struct lantern_metrics_server.
 * @return NULL.
 *
 * @note Thread safety: This function is not thread-safe; it is intended to run
 *       as a single server thread created by lantern_metrics_server_start().
 */
static void *lantern_metrics_thread(void *arg)
{
    struct lantern_metrics_server *server = arg;
    if (!server)
    {
        return NULL;
    }

    int listen_fd = server->listen_fd;
    for (;;)
    {
        struct sockaddr_in peer;
        socklen_t peer_len = sizeof(peer);
        int client_fd = accept(listen_fd, (struct sockaddr *)&peer, &peer_len);
        if (client_fd < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            if (errno == EBADF || errno == EINVAL)
            {
                break;
            }
            lantern_log_error("metrics", NULL, "accept failed errno=%d", errno);
            continue;
        }

        handle_client_connection(server, client_fd, &peer);
        close(client_fd);
    }

    return NULL;
}


/**
 * Initialize a metrics server structure.
 *
 * @param server Server instance to initialize (modified in place).
 *
 * @note Thread safety: Caller must not call concurrently with start/stop.
 */
void lantern_metrics_server_init(struct lantern_metrics_server *server)
{
    if (!server)
    {
        return;
    }

    memset(server, 0, sizeof(*server));
    server->listen_fd = -1;
    server->running = 0;
    server->thread_started = 0;
    server->port = 0;
}


/**
 * Start the metrics server.
 *
 * Creates a listening socket and starts a background thread to accept incoming
 * connections and serve GET /metrics.
 *
 * @param server    Server instance to start (modified in place).
 * @param port      Port to bind (0 binds an ephemeral port).
 * @param callbacks Metrics snapshot callback interface.
 *
 * @spec POSIX sockets and pthreads.
 *
 * @return 0 on success.
 * @return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM on invalid parameters.
 * @return LANTERN_METRICS_SERVER_ERR_IO on socket/bind/listen/thread creation failure.
 *
 * @note Thread safety: Caller must serialize start/stop operations.
 */
int lantern_metrics_server_start(
    struct lantern_metrics_server *server,
    uint16_t port,
    const struct lantern_metrics_callbacks *callbacks)
{
    if (!server || !callbacks || !callbacks->snapshot)
    {
        return LANTERN_METRICS_SERVER_ERR_INVALID_PARAM;
    }

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
    {
        lantern_log_error("metrics", NULL, "socket creation failed errno=%d", errno);
        return LANTERN_METRICS_SERVER_ERR_IO;
    }

    int opt = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) != 0)
    {
        lantern_log_warn("metrics", NULL, "setsockopt(SO_REUSEADDR) failed errno=%d", errno);
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0)
    {
        lantern_log_error("metrics", NULL, "bind failed errno=%d", errno);
        close(fd);
        return LANTERN_METRICS_SERVER_ERR_IO;
    }

    if (listen(fd, LANTERN_METRICS_LISTEN_BACKLOG) != 0)
    {
        lantern_log_error("metrics", NULL, "listen failed errno=%d", errno);
        close(fd);
        return LANTERN_METRICS_SERVER_ERR_IO;
    }

    server->listen_fd = fd;
    server->callbacks = *callbacks;
    server->port = port;
    server->running = 1;
    server->thread_started = 0;

    int create_rc = pthread_create(&server->thread, NULL, lantern_metrics_thread, server);
    if (create_rc != 0)
    {
        lantern_log_error("metrics", NULL, "pthread_create failed rc=%d", create_rc);
        close(fd);
        server->listen_fd = -1;
        server->running = 0;
        return LANTERN_METRICS_SERVER_ERR_IO;
    }

    server->thread_started = 1;
    lantern_log_info(
        "metrics",
        NULL,
        "metrics server listening port=%" PRIu16,
        server->port);
    return 0;
}


/**
 * Stop the metrics server if running.
 *
 * @param server Server instance to stop (modified in place).
 *
 * @note Thread safety: Caller must serialize start/stop operations.
 */
void lantern_metrics_server_stop(struct lantern_metrics_server *server)
{
    if (!server)
    {
        return;
    }

    server->running = 0;

    int listen_fd = server->listen_fd;
    server->listen_fd = -1;
    if (listen_fd >= 0)
    {
        (void)shutdown(listen_fd, SHUT_RDWR);
        close(listen_fd);
    }

    if (server->thread_started)
    {
        pthread_join(server->thread, NULL);
        server->thread_started = 0;
    }
}
