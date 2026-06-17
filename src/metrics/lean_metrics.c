#include "lantern/metrics/lean_metrics.h"

#include <pthread.h>
#include <stddef.h>
#include <string.h>

#define ARRAY_LEN(x) (sizeof(x) / sizeof((x)[0]))
#define HIST_OFFSET(field) offsetof(struct lean_metrics_snapshot, field)
#define TIMING_OFFSET(field) offsetof(struct lantern_block_build_stage_timings, field)

struct lean_histogram_desc {
    size_t offset;
    const double *bounds;
    size_t bucket_count;
};

struct lean_stage_timing_desc {
    size_t histogram_offset;
    size_t timing_offset;
};

static const double kDefaultShortBuckets[] = {0.005, 0.01, 0.025, 0.05, 0.1, 1.0};
static const double kForkChoiceBlockBuckets[] = {0.005, 0.01, 0.025, 0.05, 0.1, 1.0, 1.25, 1.5, 2.0, 4.0};
static const double kStateTransitionBuckets[] = {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0};
static const double kReorgDepthBuckets[] = {1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 20.0, 30.0, 50.0, 100.0};
static const double kPqSigAggregatedSignatureBuckets[] = {0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0};
static const double kCommitteeAggregationBuckets[] = {0.05, 0.1, 0.25, 0.5, 0.75, 1.0, 2.0, 3.0, 4.0};
static const double kBlockAggregatedPayloadBuckets[] = {1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0};
static const double kBlockPayloadAggregationBuckets[] = {0.1, 0.25, 0.5, 0.75, 1.0, 2.0, 3.0, 4.0};
static const double kBlockBuildingBuckets[] = {0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 0.75, 1.0};
static const double kBlockBuildStageBuckets[] =
    {0.00001, 0.000025, 0.00005, 0.0001, 0.00025, 0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.5};
static const double kTickIntervalDurationBuckets[] =
    {0.4, 0.6, 0.75, 0.8, 0.805, 0.81, 0.815, 0.82, 0.825, 0.85, 0.9, 1.0, 1.2, 1.6};
static const double kGossipBlockSizeBuckets[] = {10000.0, 50000.0, 100000.0, 250000.0, 500000.0, 1000000.0, 2000000.0, 5000000.0};
static const double kGossipAttestationSizeBuckets[] = {512.0, 1024.0, 2048.0, 4096.0, 8192.0, 16384.0};
static const double kGossipAggregationSizeBuckets[] = {1024.0, 4096.0, 16384.0, 65536.0, 131072.0, 262144.0, 524288.0, 1048576.0};
static const double kAttestationInclusionDelayBuckets[] = {1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0};
static const double kBlockImportSlotOffsetBuckets[] = {0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.6, 2.0, 3.0};

static const struct lean_histogram_desc kHistograms[] = {
    {HIST_OFFSET(block_aggregated_payloads), kBlockAggregatedPayloadBuckets, ARRAY_LEN(kBlockAggregatedPayloadBuckets)},
    {HIST_OFFSET(block_building_payload_aggregation_time), kBlockPayloadAggregationBuckets, ARRAY_LEN(kBlockPayloadAggregationBuckets)},
    {HIST_OFFSET(block_building_time), kBlockBuildingBuckets, ARRAY_LEN(kBlockBuildingBuckets)},
    {HIST_OFFSET(attestations_production_time), kBlockBuildingBuckets, ARRAY_LEN(kBlockBuildingBuckets)},
    {HIST_OFFSET(fork_choice_block_time), kForkChoiceBlockBuckets, ARRAY_LEN(kForkChoiceBlockBuckets)},
    {HIST_OFFSET(fork_choice_reorg_depth), kReorgDepthBuckets, ARRAY_LEN(kReorgDepthBuckets)},
    {HIST_OFFSET(tick_interval_duration), kTickIntervalDurationBuckets, ARRAY_LEN(kTickIntervalDurationBuckets)},
    {HIST_OFFSET(attestation_validation_time), kDefaultShortBuckets, ARRAY_LEN(kDefaultShortBuckets)},
    {HIST_OFFSET(state_transition_time), kStateTransitionBuckets, ARRAY_LEN(kStateTransitionBuckets)},
    {HIST_OFFSET(state_slots_time), kDefaultShortBuckets, ARRAY_LEN(kDefaultShortBuckets)},
    {HIST_OFFSET(state_block_time), kDefaultShortBuckets, ARRAY_LEN(kDefaultShortBuckets)},
    {HIST_OFFSET(state_attestations_time), kDefaultShortBuckets, ARRAY_LEN(kDefaultShortBuckets)},
    {HIST_OFFSET(pq_sig_attestation_signing_time), kDefaultShortBuckets, ARRAY_LEN(kDefaultShortBuckets)},
    {HIST_OFFSET(pq_sig_attestation_verification_time), kDefaultShortBuckets, ARRAY_LEN(kDefaultShortBuckets)},
    {HIST_OFFSET(pq_sig_aggregated_signatures_building_time), kPqSigAggregatedSignatureBuckets, ARRAY_LEN(kPqSigAggregatedSignatureBuckets)},
    {HIST_OFFSET(pq_sig_aggregated_signatures_verification_time), kPqSigAggregatedSignatureBuckets, ARRAY_LEN(kPqSigAggregatedSignatureBuckets)},
    {HIST_OFFSET(pq_sig_block_aggregated_signatures_verification_time), kPqSigAggregatedSignatureBuckets, ARRAY_LEN(kPqSigAggregatedSignatureBuckets)},
    {HIST_OFFSET(committee_signatures_aggregation_time), kCommitteeAggregationBuckets, ARRAY_LEN(kCommitteeAggregationBuckets)},
    {HIST_OFFSET(block_build_stage_vote_collection_time), kBlockBuildStageBuckets, ARRAY_LEN(kBlockBuildStageBuckets)},
    {HIST_OFFSET(block_build_stage_key_sig_deserialize_time), kBlockBuildStageBuckets, ARRAY_LEN(kBlockBuildStageBuckets)},
    {HIST_OFFSET(block_build_stage_pq_aggregate_time), kBlockBuildStageBuckets, ARRAY_LEN(kBlockBuildStageBuckets)},
    {HIST_OFFSET(block_build_stage_proof_copy_time), kBlockBuildStageBuckets, ARRAY_LEN(kBlockBuildStageBuckets)},
    {HIST_OFFSET(block_build_stage_lock_waits_time), kBlockBuildStageBuckets, ARRAY_LEN(kBlockBuildStageBuckets)},
    {HIST_OFFSET(block_build_stage_other_prover_setup_time), kBlockBuildStageBuckets, ARRAY_LEN(kBlockBuildStageBuckets)},
    {HIST_OFFSET(gossip_block_size_bytes), kGossipBlockSizeBuckets, ARRAY_LEN(kGossipBlockSizeBuckets)},
    {HIST_OFFSET(gossip_attestation_size_bytes), kGossipAttestationSizeBuckets, ARRAY_LEN(kGossipAttestationSizeBuckets)},
    {HIST_OFFSET(gossip_aggregation_size_bytes), kGossipAggregationSizeBuckets, ARRAY_LEN(kGossipAggregationSizeBuckets)},
    {HIST_OFFSET(attestation_inclusion_delay_slots), kAttestationInclusionDelayBuckets, ARRAY_LEN(kAttestationInclusionDelayBuckets)},
    {HIST_OFFSET(block_import_slot_offset_seconds), kBlockImportSlotOffsetBuckets, ARRAY_LEN(kBlockImportSlotOffsetBuckets)},
};

static const struct lean_stage_timing_desc kBlockBuildStageTimings[] = {
    {HIST_OFFSET(block_build_stage_vote_collection_time), TIMING_OFFSET(vote_collection_seconds)},
    {HIST_OFFSET(block_build_stage_key_sig_deserialize_time), TIMING_OFFSET(key_sig_deserialize_seconds)},
    {HIST_OFFSET(block_build_stage_pq_aggregate_time), TIMING_OFFSET(pq_aggregate_seconds)},
    {HIST_OFFSET(block_build_stage_proof_copy_time), TIMING_OFFSET(proof_copy_seconds)},
    {HIST_OFFSET(block_build_stage_lock_waits_time), TIMING_OFFSET(lock_waits_seconds)},
    {HIST_OFFSET(block_build_stage_other_prover_setup_time), TIMING_OFFSET(other_prover_setup_seconds)},
};

static pthread_mutex_t g_metrics_lock = PTHREAD_MUTEX_INITIALIZER;
static struct lean_metrics_snapshot g_metrics;
static bool g_metrics_initialized;

static struct lean_metrics_histogram_snapshot *histogram_at(size_t offset) {
    return (struct lean_metrics_histogram_snapshot *)((unsigned char *)&g_metrics + offset);
}

static double read_double_field(const void *base, size_t offset) {
    double value = 0.0;
    memcpy(&value, (const unsigned char *)base + offset, sizeof(value));
    return value;
}

static double sanitize_duration(double seconds) {
    if (seconds < 0.0) {
        return 0.0;
    }
    return seconds;
}

static void histogram_install_bounds(
    struct lean_metrics_histogram_snapshot *hist,
    const struct lean_histogram_desc *desc) {
    size_t bucket_count = desc->bucket_count;
    if (bucket_count > LEAN_METRICS_MAX_BUCKETS) {
        bucket_count = LEAN_METRICS_MAX_BUCKETS;
    }
    hist->bucket_count = bucket_count;
    memcpy(hist->buckets, desc->bounds, bucket_count * sizeof(hist->buckets[0]));
}

static void metrics_install_histograms_locked(void) {
    for (size_t i = 0; i < ARRAY_LEN(kHistograms); ++i) {
        histogram_install_bounds(histogram_at(kHistograms[i].offset), &kHistograms[i]);
    }
    g_metrics_initialized = true;
}

static void metrics_ensure_initialized_locked(void) {
    if (!g_metrics_initialized) {
        metrics_install_histograms_locked();
    }
}

static void histogram_observe_locked(size_t offset, double value) {
    metrics_ensure_initialized_locked();

    struct lean_metrics_histogram_snapshot *hist = histogram_at(offset);
    double sample = sanitize_duration(value);
    size_t bucket = hist->bucket_count;
    for (size_t i = 0; i < hist->bucket_count; ++i) {
        if (sample <= hist->buckets[i]) {
            bucket = i;
            break;
        }
    }
    hist->counts[bucket] += 1;
    hist->sum += sample;
    hist->total += 1;
}

static void record_histogram(size_t offset, double value) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe_locked(offset, value);
    pthread_mutex_unlock(&g_metrics_lock);
}

static void add_counter(uint64_t *counter, uint64_t value) {
    pthread_mutex_lock(&g_metrics_lock);
    *counter += value;
    pthread_mutex_unlock(&g_metrics_lock);
}

static void set_counter(uint64_t *counter, uint64_t value) {
    pthread_mutex_lock(&g_metrics_lock);
    *counter = value;
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_reset(void) {
    pthread_mutex_lock(&g_metrics_lock);
    memset(&g_metrics, 0, sizeof(g_metrics));
    g_metrics_initialized = false;
    metrics_ensure_initialized_locked();
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_block_aggregated_payloads(size_t count) {
    record_histogram(HIST_OFFSET(block_aggregated_payloads), (double)count);
}

void lean_metrics_record_block_building_payload_aggregation_time(double seconds) {
    record_histogram(HIST_OFFSET(block_building_payload_aggregation_time), seconds);
}

void lean_metrics_record_block_building_time(double seconds) {
    record_histogram(HIST_OFFSET(block_building_time), seconds);
}

void lean_metrics_record_attestations_production_time(double seconds) {
    record_histogram(HIST_OFFSET(attestations_production_time), seconds);
}

void lean_metrics_record_block_building_success(void) {
    add_counter(&g_metrics.block_building_success_total, 1);
}

void lean_metrics_record_block_building_failure(void) {
    add_counter(&g_metrics.block_building_failures_total, 1);
}

void lean_metrics_set_gossip_validation_worker_count(size_t count) {
    set_counter(&g_metrics.gossip_validation_worker_count, (uint64_t)count);
}

void lean_metrics_record_fork_choice_block_time(double seconds) {
    record_histogram(HIST_OFFSET(fork_choice_block_time), seconds);
}

void lean_metrics_record_fork_choice_reorg(size_t depth) {
    if (depth == 0) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.fork_choice_reorgs_total += 1;
    histogram_observe_locked(HIST_OFFSET(fork_choice_reorg_depth), (double)depth);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_tick_interval_duration(double seconds) {
    record_histogram(HIST_OFFSET(tick_interval_duration), seconds);
}

void lean_metrics_record_attestation_validation(double seconds, bool valid) {
    pthread_mutex_lock(&g_metrics_lock);
    if (valid) {
        g_metrics.attestations_valid_total += 1;
    } else {
        g_metrics.attestations_invalid_total += 1;
    }
    histogram_observe_locked(HIST_OFFSET(attestation_validation_time), seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_state_transition(double seconds) {
    record_histogram(HIST_OFFSET(state_transition_time), seconds);
}

void lean_metrics_record_state_transition_slots(uint64_t slots_processed, double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.state_transition_slots_processed_total += slots_processed;
    histogram_observe_locked(HIST_OFFSET(state_slots_time), seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_state_transition_block(double seconds) {
    record_histogram(HIST_OFFSET(state_block_time), seconds);
}

void lean_metrics_record_state_transition_attestations(uint64_t count, double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.state_transition_attestations_processed_total += count;
    histogram_observe_locked(HIST_OFFSET(state_attestations_time), seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_finalization_attempt(bool success) {
    add_counter(
        success ? &g_metrics.finalizations_success_total : &g_metrics.finalizations_error_total,
        1);
}

void lean_metrics_record_pq_signature_signing(double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.pq_sig_attestation_signatures_total += 1;
    histogram_observe_locked(HIST_OFFSET(pq_sig_attestation_signing_time), seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_pq_signature_verification(double seconds) {
    record_histogram(HIST_OFFSET(pq_sig_attestation_verification_time), seconds);
}

void lean_metrics_record_pq_signature_verification_result(bool valid) {
    add_counter(
        valid
            ? &g_metrics.pq_sig_attestation_signatures_valid_total
            : &g_metrics.pq_sig_attestation_signatures_invalid_total,
        1);
}

void lean_metrics_record_pq_aggregated_signature_build(size_t attestation_count, double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.pq_sig_aggregated_signatures_total += 1;
    g_metrics.pq_sig_attestations_in_aggregated_signatures_total += (uint64_t)attestation_count;
    histogram_observe_locked(HIST_OFFSET(pq_sig_aggregated_signatures_building_time), seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_pq_aggregated_signature_verification(double seconds, bool valid) {
    pthread_mutex_lock(&g_metrics_lock);
    if (valid) {
        g_metrics.pq_sig_aggregated_signatures_valid_total += 1;
    } else {
        g_metrics.pq_sig_aggregated_signatures_invalid_total += 1;
    }
    histogram_observe_locked(HIST_OFFSET(pq_sig_aggregated_signatures_verification_time), seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_pq_block_aggregated_signatures_verification(double seconds) {
    record_histogram(HIST_OFFSET(pq_sig_block_aggregated_signatures_verification_time), seconds);
}

void lean_metrics_record_committee_signature_aggregation(double seconds, uint64_t aggregated_attestations) {
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.committee_aggregated_attestations_total += aggregated_attestations;
    histogram_observe_locked(HIST_OFFSET(committee_signatures_aggregation_time), seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_block_build_stage_timings(
    const struct lantern_block_build_stage_timings *timings) {
    if (!timings) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    for (size_t i = 0; i < ARRAY_LEN(kBlockBuildStageTimings); ++i) {
        histogram_observe_locked(
            kBlockBuildStageTimings[i].histogram_offset,
            read_double_field(timings, kBlockBuildStageTimings[i].timing_offset));
    }
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_peer_connection(
    lean_metrics_direction_t direction,
    lean_metrics_connection_result_t result) {
    if (direction >= LEAN_METRICS_DIR_COUNT || result >= LEAN_METRICS_CONN_RESULT_COUNT) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.peer_connection_events_total[direction][result] += 1;
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_peer_disconnection(
    lean_metrics_direction_t direction,
    lean_metrics_disconnection_reason_t reason) {
    if (direction >= LEAN_METRICS_DIR_COUNT || reason >= LEAN_METRICS_DISCONNECT_REASON_COUNT) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.peer_disconnection_events_total[direction][reason] += 1;
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_aggregator_skipped(
    lean_metrics_aggregator_skipped_reason_t reason) {
    if (reason >= LEAN_METRICS_AGGREGATOR_SKIPPED_REASON_COUNT) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    g_metrics.aggregator_skipped_total[reason] += 1;
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_gossip_block_size(size_t bytes_len) {
    record_histogram(HIST_OFFSET(gossip_block_size_bytes), (double)bytes_len);
}

void lean_metrics_record_gossip_attestation_size(size_t bytes_len) {
    record_histogram(HIST_OFFSET(gossip_attestation_size_bytes), (double)bytes_len);
}

void lean_metrics_record_gossip_aggregation_size(size_t bytes_len) {
    record_histogram(HIST_OFFSET(gossip_aggregation_size_bytes), (double)bytes_len);
}

void lean_metrics_record_attestation_head_vote(bool stale) {
    add_counter(
        stale ? &g_metrics.attestation_head_votes_stale_total : &g_metrics.attestation_head_votes_fresh_total,
        1);
}

void lean_metrics_record_attestation_inclusion_delay(uint64_t slots) {
    record_histogram(HIST_OFFSET(attestation_inclusion_delay_slots), (double)slots);
}

void lean_metrics_record_block_import_slot_offset(double seconds) {
    record_histogram(HIST_OFFSET(block_import_slot_offset_seconds), seconds);
}

void lean_metrics_snapshot(struct lean_metrics_snapshot *out) {
    if (!out) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    metrics_ensure_initialized_locked();
    *out = g_metrics;
    pthread_mutex_unlock(&g_metrics_lock);
}
