#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/metrics/server.h"
#include "lantern/metrics/lean_metrics.h"

static uint64_t extract_histogram_bucket_value(
    const char *body,
    const char *metric_name,
    const char *le_value)
{
    char pattern[256];
    int written = snprintf(
        pattern,
        sizeof(pattern),
        "%s_bucket{le=\"%s\"} ",
        metric_name,
        le_value);
    assert(written > 0 && (size_t)written < sizeof(pattern));

    const char *line = strstr(body, pattern);
    assert(line != NULL);
    line += strlen(pattern);
    return (uint64_t)strtoull(line, NULL, 10);
}

static uint64_t extract_histogram_count(const char *body, const char *metric_name)
{
    char pattern[256];
    int written = snprintf(pattern, sizeof(pattern), "%s_count ", metric_name);
    assert(written > 0 && (size_t)written < sizeof(pattern));

    const char *line = strstr(body, pattern);
    assert(line != NULL);
    line += strlen(pattern);
    return (uint64_t)strtoull(line, NULL, 10);
}

static void assert_histogram_cumulative(
    const char *body,
    const char *metric_name,
    const char *const *bucket_labels,
    size_t bucket_count)
{
    uint64_t previous = 0;
    for (size_t i = 0; i < bucket_count; ++i)
    {
        uint64_t current = extract_histogram_bucket_value(body, metric_name, bucket_labels[i]);
        assert(current >= previous);
        previous = current;
    }

    uint64_t inf_bucket = extract_histogram_bucket_value(body, metric_name, "+Inf");
    uint64_t total_count = extract_histogram_count(body, metric_name);
    assert(inf_bucket >= previous);
    assert(inf_bucket == total_count);
}

static int test_attestation_validation_metrics(void) {
    lean_metrics_reset();
    lean_metrics_record_attestation_validation(0.01, true);
    lean_metrics_record_attestation_validation(0.02, false);

    struct lean_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    lean_metrics_snapshot(&snapshot);

    assert(snapshot.attestations_valid_total == 1);
    assert(snapshot.attestations_invalid_total == 1);
    assert(snapshot.attestation_validation_time.total == 2);
    assert(snapshot.attestation_validation_time.sum > 0.0);
    return 0;
}

static int test_state_transition_counters(void) {
    lean_metrics_reset();
    lean_metrics_record_state_transition_slots(5, 0.05);
    lean_metrics_record_state_transition_slots(0, 0.01);
    lean_metrics_record_state_transition_attestations(3, 0.02);
    lean_metrics_record_state_transition(0.5);

    struct lean_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    lean_metrics_snapshot(&snapshot);

    assert(snapshot.state_transition_slots_processed_total == 5);
    assert(snapshot.state_transition_attestations_processed_total == 3);
    assert(snapshot.state_transition_time.total == 1);
    assert(snapshot.state_transition_time.sum > 0.0);
    return 0;
}

static int test_fork_choice_histogram(void) {
    lean_metrics_reset();
    lean_metrics_record_fork_choice_block_time(0.001);
    lean_metrics_record_fork_choice_block_time(0.5);
    lean_metrics_record_fork_choice_block_time(2.0);

    struct lean_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    lean_metrics_snapshot(&snapshot);

    assert(snapshot.fork_choice_block_time.total == 3);
    assert(snapshot.fork_choice_block_time.bucket_count == 10);
    assert(snapshot.fork_choice_block_time.counts[0] == 1);
    assert(snapshot.fork_choice_block_time.counts[5] == 1);
    assert(snapshot.fork_choice_block_time.counts[8] == 1);
    return 0;
}

static int test_tick_interval_duration_metrics(void) {
    lean_metrics_reset();
    lean_metrics_record_tick_interval_duration(0.79);
    lean_metrics_record_tick_interval_duration(1.7);

    struct lean_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    lean_metrics_snapshot(&snapshot);

    assert(snapshot.tick_interval_duration.total == 2);
    assert(snapshot.tick_interval_duration.bucket_count == 14);
    assert(snapshot.tick_interval_duration.counts[3] == 1);
    assert(snapshot.tick_interval_duration.counts[14] == 1);
    return 0;
}

static int test_pq_signature_metrics(void) {
    lean_metrics_reset();
    lean_metrics_record_pq_signature_signing(0.02);
    lean_metrics_record_pq_signature_verification(0.01);
    lean_metrics_record_pq_signature_verification_result(true);
    lean_metrics_record_pq_signature_verification_result(false);
    lean_metrics_record_pq_aggregated_signature_build(4, 0.03);
    lean_metrics_record_pq_aggregated_signature_verification(0.04, true);
    lean_metrics_record_pq_aggregated_signature_verification(0.05, false);
    lean_metrics_record_pq_block_aggregated_signatures_verification(0.06);

    struct lean_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    lean_metrics_snapshot(&snapshot);

    assert(snapshot.pq_sig_attestation_signatures_total == 1);
    assert(snapshot.pq_sig_attestation_signatures_valid_total == 1);
    assert(snapshot.pq_sig_attestation_signatures_invalid_total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_valid_total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_invalid_total == 1);
    assert(snapshot.pq_sig_attestations_in_aggregated_signatures_total == 4);
    assert(snapshot.pq_sig_attestation_signing_time.total == 1);
    assert(snapshot.pq_sig_attestation_verification_time.total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_building_time.total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_verification_time.total == 2);
    assert(snapshot.pq_sig_block_aggregated_signatures_verification_time.total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_building_time.bucket_count == 9);
    assert(snapshot.pq_sig_aggregated_signatures_verification_time.bucket_count == 9);
    assert(snapshot.pq_sig_block_aggregated_signatures_verification_time.bucket_count == 9);
    return 0;
}

static int test_committee_aggregation_metrics(void) {
    lean_metrics_reset();
    lean_metrics_record_committee_signature_aggregation(0.08, 2);
    lean_metrics_record_committee_signature_aggregation(0.12, 1);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_NOT_AGGREGATOR);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_NOT_SYNCED);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_MISSING_STATE);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_SPAWN_FAILED);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_OTHER);

    struct lean_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    lean_metrics_snapshot(&snapshot);

    assert(snapshot.committee_aggregated_attestations_total == 3);
    assert(snapshot.aggregator_skipped_total[LEAN_METRICS_AGGREGATOR_SKIPPED_NOT_AGGREGATOR] == 1);
    assert(snapshot.aggregator_skipped_total[LEAN_METRICS_AGGREGATOR_SKIPPED_NOT_SYNCED] == 1);
    assert(snapshot.aggregator_skipped_total[LEAN_METRICS_AGGREGATOR_SKIPPED_MISSING_STATE] == 1);
    assert(snapshot.aggregator_skipped_total[LEAN_METRICS_AGGREGATOR_SKIPPED_SPAWN_FAILED] == 1);
    assert(snapshot.aggregator_skipped_total[LEAN_METRICS_AGGREGATOR_SKIPPED_OTHER] == 1);
    assert(snapshot.committee_signatures_aggregation_time.total == 2);
    assert(snapshot.committee_signatures_aggregation_time.sum > 0.0);
    assert(snapshot.committee_signatures_aggregation_time.bucket_count == 9);
    assert(snapshot.committee_signatures_aggregation_time.buckets[0] == 0.05);
    assert(snapshot.committee_signatures_aggregation_time.buckets[8] == 4.0);
    return 0;
}

static int test_prometheus_metric_names(void) {
    lean_metrics_reset();
    lean_metrics_record_block_aggregated_payloads(3);
    lean_metrics_record_block_building_payload_aggregation_time(0.2);
    lean_metrics_record_block_building_time(0.3);
    lean_metrics_record_attestations_production_time(0.04);
    lean_metrics_record_block_building_success();
    lean_metrics_record_block_building_failure();
    lean_metrics_record_fork_choice_reorg(2);
    lean_metrics_record_finalization_attempt(true);
    lean_metrics_record_finalization_attempt(false);
    lean_metrics_record_pq_signature_signing(0.02);
    lean_metrics_record_pq_signature_verification(0.01);
    lean_metrics_record_pq_signature_verification_result(true);
    lean_metrics_record_pq_signature_verification_result(false);
    lean_metrics_record_pq_aggregated_signature_build(4, 0.25);
    lean_metrics_record_pq_aggregated_signature_verification(0.5, true);
    lean_metrics_record_pq_aggregated_signature_verification(0.75, false);
    lean_metrics_record_pq_block_aggregated_signatures_verification(0.8);
    lean_metrics_record_committee_signature_aggregation(0.3, 3);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_NOT_AGGREGATOR);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_NOT_SYNCED);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_MISSING_STATE);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_SPAWN_FAILED);
    lean_metrics_record_aggregator_skipped(LEAN_METRICS_AGGREGATOR_SKIPPED_OTHER);
    lean_metrics_record_peer_connection(LEAN_METRICS_DIR_INBOUND, LEAN_METRICS_CONN_RESULT_SUCCESS);
    lean_metrics_record_peer_disconnection(
        LEAN_METRICS_DIR_OUTBOUND,
        LEAN_METRICS_DISCONNECT_REMOTE_CLOSE);
    lean_metrics_record_tick_interval_duration(0.82);
    lean_metrics_set_gossip_validation_worker_count(8);
    lean_metrics_record_gossip_block_size(12000);
    lean_metrics_record_gossip_attestation_size(1024);
    lean_metrics_record_gossip_aggregation_size(4096);

    struct lantern_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    snapshot.lean_node_start_time_seconds = 123;
    snapshot.lean_head_slot = 10;
    snapshot.lean_current_slot = 11;
    snapshot.lean_safe_target_slot = 9;
    snapshot.lean_latest_justified_slot = 8;
    snapshot.lean_latest_finalized_slot = 7;
    snapshot.lean_justified_slot = 8;
    snapshot.lean_finalized_slot = 7;
    snprintf(snapshot.lean_client_label, sizeof(snapshot.lean_client_label), "%s", "lantern_0");
    snapshot.lean_validators_count = 2;
    snapshot.lean_connected_peers = 3;
    snapshot.lean_gossip_mesh_peers = 2;
    snapshot.lean_gossip_signatures = 4;
    snapshot.lean_latest_new_aggregated_payloads = 5;
    snapshot.lean_latest_known_aggregated_payloads = 6;
    snapshot.lean_is_aggregator = 1;
    snapshot.lean_attestation_committee_subnet = 2;
    snapshot.lean_attestation_committee_count = 4;
    snapshot.lean_node_sync_status = 1;
    lean_metrics_snapshot(&snapshot.lean_metrics);

    char *body = NULL;
    size_t body_len = 0;
    int rc = lantern_metrics_format_prometheus(&snapshot, &body, &body_len);
    assert(rc == 0);
    assert(body != NULL);
    assert(body_len > 0);
    if (getenv("LANTERN_TEST_PRINT_METRICS")) {
        fputs(body, stdout);
    }

    static const char *required_names[] = {
        "lean_node_info",
        "lean_node_start_time_seconds",
        "lean_pq_sig_attestation_signatures_total",
        "lean_pq_sig_attestation_signatures_valid_total",
        "lean_pq_sig_attestation_signatures_invalid_total",
        "lean_pq_sig_attestation_signing_time_seconds",
        "lean_pq_sig_attestation_verification_time_seconds",
        "lean_pq_sig_aggregated_signatures_total",
        "lean_pq_sig_aggregated_signatures_valid_total",
        "lean_pq_sig_aggregated_signatures_invalid_total",
        "lean_pq_sig_attestations_in_aggregated_signatures_total",
        "lean_pq_sig_aggregated_signatures_building_time_seconds",
        "lean_pq_sig_aggregated_signatures_verification_time_seconds",
        "lean_pq_sig_block_aggregated_signatures_verification_time_seconds",
        "lean_block_aggregated_payloads",
        "lean_block_building_payload_aggregation_time_seconds",
        "lean_block_building_time_seconds",
        "lean_attestations_production_time_seconds",
        "lean_block_building_success_total",
        "lean_block_building_failures_total",
        "lean_gossip_validation_worker_count",
        "lean_head_slot",
        "lean_current_slot",
        "lean_safe_target_slot",
        "lean_fork_choice_block_processing_time_seconds",
        "lean_attestations_valid_total",
        "lean_attestations_invalid_total",
        "lean_attestation_validation_time_seconds",
        "lean_fork_choice_reorgs_total",
        "lean_fork_choice_reorg_depth",
        "lean_gossip_signatures",
        "lean_latest_new_aggregated_payloads",
        "lean_latest_known_aggregated_payloads",
        "lean_committee_signatures_aggregation_time_seconds",
        "lean_node_sync_status",
        "lean_latest_justified_slot",
        "lean_latest_finalized_slot",
        "lean_justified_slot",
        "lean_finalized_slot",
        "lean_finalizations_total",
        "lean_state_transition_time_seconds",
        "lean_state_transition_slots_processed_total",
        "lean_state_transition_slots_processing_time_seconds",
        "lean_state_transition_block_processing_time_seconds",
        "lean_state_transition_attestations_processed_total",
        "lean_state_transition_attestations_processing_time_seconds",
        "lean_validators_count",
        "lean_is_aggregator",
        "lean_connected_peers",
        "lean_gossip_mesh_peers",
        "lean_peer_connection_events_total",
        "lean_peer_disconnection_events_total",
        "lean_aggregator_skipped_total",
        "lean_tick_interval_duration_seconds",
        "lean_attestation_committee_subnet",
        "lean_attestation_committee_count",
        "lean_gossip_block_size_bytes",
        "lean_gossip_attestation_size_bytes",
        "lean_gossip_aggregation_size_bytes",
    };
    for (size_t i = 0; i < sizeof(required_names) / sizeof(required_names[0]); ++i) {
        assert(strstr(body, required_names[i]) != NULL);
    }

    assert(strstr(body, "lean_node_info{name=\"lantern\"") != NULL);
    assert(strstr(body, "lean_connected_peers{client=\"lantern_0\"} 3") != NULL);
    assert(strstr(body, "lean_gossip_mesh_peers{client=\"lantern_0\"} 2") != NULL);
    assert(strstr(body, "lean_gossip_validation_worker_count 8") != NULL);
    assert(strstr(body, "lean_finalizations_total{result=\"success\"}") != NULL);
    assert(strstr(body, "lean_finalizations_total{result=\"error\"}") != NULL);
    assert(strstr(body, "lean_committee_signatures_aggregation_time_seconds_bucket{le=\"2\"}") != NULL);
    assert(strstr(body, "lean_node_sync_status{status=\"idle\"}") != NULL);
    assert(strstr(body, "lean_node_sync_status{status=\"syncing\"}") != NULL);
    assert(strstr(body, "lean_node_sync_status{status=\"synced\"}") != NULL);
    assert(strstr(body, "lean_peer_connection_events_total{direction=\"inbound\",result=\"success\"}") != NULL);
    assert(strstr(body, "lean_peer_disconnection_events_total{direction=\"outbound\",reason=\"remote_close\"}") != NULL);
    assert(strstr(body, "lean_aggregator_skipped_total{reason=\"not_aggregator\"} 1") != NULL);
    assert(strstr(body, "lean_aggregator_skipped_total{reason=\"not_synced\"} 1") != NULL);
    assert(strstr(body, "lean_aggregator_skipped_total{reason=\"missing_state\"} 1") != NULL);
    assert(strstr(body, "lean_aggregator_skipped_total{reason=\"spawn_failed\"} 1") != NULL);
    assert(strstr(body, "lean_aggregator_skipped_total{reason=\"other\"} 1") != NULL);
    assert(strstr(body, "lean_tick_interval_duration_seconds_bucket{le=\"0.82\"}") != NULL);

    assert(strstr(body, "lean_gossip_signatures_count") == NULL);
    assert(strstr(body, "lean_latest_new_aggregated_payloads_count") == NULL);
    assert(strstr(body, "lean_latest_known_aggregated_payloads_count") == NULL);
    assert(strstr(body, "lean_committee_attestation_subnet") == NULL);
    assert(strstr(body, "lean_committee_attestation_subnets_count") == NULL);
    assert(strstr(body, "lean_pq_sig_individual_signatures_total") == NULL);
    assert(strstr(body, "lean_pq_signature_attestation_signing_time_seconds") == NULL);
    assert(strstr(body, "lean_pq_signature_attestation_verification_time_seconds") == NULL);
    assert(strstr(body, "lean_pq_sig_attestation_signatures_building_time_seconds") == NULL);
    assert(strstr(body, "lean_sync_status") == NULL);
    assert(strstr(body, "lean_block_build_duration_seconds") == NULL);

    static const char *const kBlockBuildingTimeBuckets[] = {
        "0.01", "0.025", "0.05", "0.1", "0.25", "0.5", "0.75", "1",
    };
    assert_histogram_cumulative(
        body,
        "lean_block_building_time_seconds",
        kBlockBuildingTimeBuckets,
        sizeof(kBlockBuildingTimeBuckets) / sizeof(kBlockBuildingTimeBuckets[0]));

    free(body);
    return 0;
}

int main(void) {
    if (test_attestation_validation_metrics() != 0) {
        return 1;
    }
    if (test_state_transition_counters() != 0) {
        return 1;
    }
    if (test_fork_choice_histogram() != 0) {
        return 1;
    }
    if (test_tick_interval_duration_metrics() != 0) {
        return 1;
    }
    if (test_pq_signature_metrics() != 0) {
        return 1;
    }
    if (test_committee_aggregation_metrics() != 0) {
        return 1;
    }
    if (test_prometheus_metric_names() != 0) {
        return 1;
    }
    return 0;
}
