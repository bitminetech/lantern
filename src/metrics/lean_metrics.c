#include "lantern/metrics/lean_metrics.h"

#include <pthread.h>
#include <string.h>

#define ARRAY_LEN(x) (sizeof(x) / sizeof((x)[0]))

struct lean_histogram {
    const double *bounds;
    size_t bucket_count;
    uint64_t counts[LEAN_METRICS_MAX_BUCKETS + 1u];
    double sum;
    uint64_t total;
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
static const double kGossipBlockSizeBuckets[] = {10000.0, 50000.0, 100000.0, 250000.0, 500000.0, 1000000.0, 2000000.0, 5000000.0};
static const double kGossipAttestationSizeBuckets[] = {512.0, 1024.0, 2048.0, 4096.0, 8192.0, 16384.0};
static const double kGossipAggregationSizeBuckets[] = {1024.0, 4096.0, 16384.0, 65536.0, 131072.0, 262144.0, 524288.0, 1048576.0};

static pthread_mutex_t g_metrics_lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t g_attestations_valid_total = 0;
static uint64_t g_attestations_invalid_total = 0;
static uint64_t g_pq_sig_attestation_signatures_total = 0;
static uint64_t g_pq_sig_attestation_signatures_valid_total = 0;
static uint64_t g_pq_sig_attestation_signatures_invalid_total = 0;
static uint64_t g_pq_sig_aggregated_signatures_total = 0;
static uint64_t g_pq_sig_aggregated_signatures_valid_total = 0;
static uint64_t g_pq_sig_aggregated_signatures_invalid_total = 0;
static uint64_t g_pq_sig_attestations_in_aggregated_signatures_total = 0;
static uint64_t g_committee_aggregated_attestations_total = 0;
static uint64_t g_fork_choice_reorgs_total = 0;
static uint64_t g_finalizations_success_total = 0;
static uint64_t g_finalizations_error_total = 0;
static uint64_t g_block_building_success_total = 0;
static uint64_t g_block_building_failures_total = 0;
static uint64_t g_peer_connection_events_total[LEAN_METRICS_DIR_COUNT][LEAN_METRICS_CONN_RESULT_COUNT];
static uint64_t g_peer_disconnection_events_total[LEAN_METRICS_DIR_COUNT][LEAN_METRICS_DISCONNECT_REASON_COUNT];
static uint64_t g_state_slots_processed_total = 0;
static uint64_t g_state_attestations_processed_total = 0;

static struct lean_histogram g_hist_block_aggregated_payloads = {
    .bounds = kBlockAggregatedPayloadBuckets,
    .bucket_count = ARRAY_LEN(kBlockAggregatedPayloadBuckets),
};
static struct lean_histogram g_hist_block_building_payload_aggregation = {
    .bounds = kBlockPayloadAggregationBuckets,
    .bucket_count = ARRAY_LEN(kBlockPayloadAggregationBuckets),
};
static struct lean_histogram g_hist_block_building = {
    .bounds = kBlockBuildingBuckets,
    .bucket_count = ARRAY_LEN(kBlockBuildingBuckets),
};
static struct lean_histogram g_hist_fork_choice_block = {
    .bounds = kForkChoiceBlockBuckets,
    .bucket_count = ARRAY_LEN(kForkChoiceBlockBuckets),
};
static struct lean_histogram g_hist_fork_choice_reorg_depth = {
    .bounds = kReorgDepthBuckets,
    .bucket_count = ARRAY_LEN(kReorgDepthBuckets),
};
static struct lean_histogram g_hist_attestation_validation = {
    .bounds = kDefaultShortBuckets,
    .bucket_count = ARRAY_LEN(kDefaultShortBuckets),
};
static struct lean_histogram g_hist_state_transition = {
    .bounds = kStateTransitionBuckets,
    .bucket_count = ARRAY_LEN(kStateTransitionBuckets),
};
static struct lean_histogram g_hist_state_slots = {
    .bounds = kDefaultShortBuckets,
    .bucket_count = ARRAY_LEN(kDefaultShortBuckets),
};
static struct lean_histogram g_hist_state_block = {
    .bounds = kDefaultShortBuckets,
    .bucket_count = ARRAY_LEN(kDefaultShortBuckets),
};
static struct lean_histogram g_hist_state_attestations = {
    .bounds = kDefaultShortBuckets,
    .bucket_count = ARRAY_LEN(kDefaultShortBuckets),
};
static struct lean_histogram g_hist_pq_sig_attestation_signing = {
    .bounds = kDefaultShortBuckets,
    .bucket_count = ARRAY_LEN(kDefaultShortBuckets),
};
static struct lean_histogram g_hist_pq_sig_attestation_verification = {
    .bounds = kDefaultShortBuckets,
    .bucket_count = ARRAY_LEN(kDefaultShortBuckets),
};
static struct lean_histogram g_hist_pq_sig_aggregated_signatures_building = {
    .bounds = kPqSigAggregatedSignatureBuckets,
    .bucket_count = ARRAY_LEN(kPqSigAggregatedSignatureBuckets),
};
static struct lean_histogram g_hist_pq_sig_aggregated_signatures_verification = {
    .bounds = kPqSigAggregatedSignatureBuckets,
    .bucket_count = ARRAY_LEN(kPqSigAggregatedSignatureBuckets),
};
static struct lean_histogram g_hist_committee_signatures_aggregation = {
    .bounds = kCommitteeAggregationBuckets,
    .bucket_count = ARRAY_LEN(kCommitteeAggregationBuckets),
};
static struct lean_histogram g_hist_gossip_block_size = {
    .bounds = kGossipBlockSizeBuckets,
    .bucket_count = ARRAY_LEN(kGossipBlockSizeBuckets),
};
static struct lean_histogram g_hist_gossip_attestation_size = {
    .bounds = kGossipAttestationSizeBuckets,
    .bucket_count = ARRAY_LEN(kGossipAttestationSizeBuckets),
};
static struct lean_histogram g_hist_gossip_aggregation_size = {
    .bounds = kGossipAggregationSizeBuckets,
    .bucket_count = ARRAY_LEN(kGossipAggregationSizeBuckets),
};

static double sanitize_duration(double seconds) {
    if (seconds < 0.0) {
        return 0.0;
    }
    return seconds;
}

static void histogram_reset(struct lean_histogram *hist) {
    if (!hist) {
        return;
    }
    memset(hist->counts, 0, sizeof(hist->counts));
    hist->sum = 0.0;
    hist->total = 0;
}

static void histogram_observe(struct lean_histogram *hist, double value) {
    if (!hist) {
        return;
    }
    double sample = sanitize_duration(value);
    size_t bucket = hist->bucket_count;
    for (size_t i = 0; i < hist->bucket_count; ++i) {
        if (sample <= hist->bounds[i]) {
            bucket = i;
            break;
        }
    }
    if (bucket < hist->bucket_count) {
        hist->counts[bucket] += 1;
    } else {
        hist->counts[hist->bucket_count] += 1;
    }
    hist->sum += sample;
    hist->total += 1;
}

static void histogram_snapshot(struct lean_metrics_histogram_snapshot *dest, const struct lean_histogram *src) {
    if (!dest || !src) {
        return;
    }
    size_t bucket_count = src->bucket_count;
    if (bucket_count > LEAN_METRICS_MAX_BUCKETS) {
        bucket_count = LEAN_METRICS_MAX_BUCKETS;
    }
    dest->bucket_count = bucket_count;
    memset(dest->buckets, 0, sizeof(dest->buckets));
    memset(dest->counts, 0, sizeof(dest->counts));
    for (size_t i = 0; i < bucket_count; ++i) {
        dest->buckets[i] = src->bounds[i];
    }
    for (size_t i = 0; i < bucket_count; ++i) {
        dest->counts[i] = src->counts[i];
    }
    dest->counts[bucket_count] = src->counts[src->bucket_count];
    dest->sum = src->sum;
    dest->total = src->total;
}

void lean_metrics_reset(void) {
    pthread_mutex_lock(&g_metrics_lock);
    g_attestations_valid_total = 0;
    g_attestations_invalid_total = 0;
    g_pq_sig_attestation_signatures_total = 0;
    g_pq_sig_attestation_signatures_valid_total = 0;
    g_pq_sig_attestation_signatures_invalid_total = 0;
    g_pq_sig_aggregated_signatures_total = 0;
    g_pq_sig_aggregated_signatures_valid_total = 0;
    g_pq_sig_aggregated_signatures_invalid_total = 0;
    g_pq_sig_attestations_in_aggregated_signatures_total = 0;
    g_committee_aggregated_attestations_total = 0;
    g_fork_choice_reorgs_total = 0;
    g_finalizations_success_total = 0;
    g_finalizations_error_total = 0;
    g_block_building_success_total = 0;
    g_block_building_failures_total = 0;
    memset(g_peer_connection_events_total, 0, sizeof(g_peer_connection_events_total));
    memset(g_peer_disconnection_events_total, 0, sizeof(g_peer_disconnection_events_total));
    g_state_slots_processed_total = 0;
    g_state_attestations_processed_total = 0;
    histogram_reset(&g_hist_block_aggregated_payloads);
    histogram_reset(&g_hist_block_building_payload_aggregation);
    histogram_reset(&g_hist_block_building);
    histogram_reset(&g_hist_fork_choice_block);
    histogram_reset(&g_hist_fork_choice_reorg_depth);
    histogram_reset(&g_hist_attestation_validation);
    histogram_reset(&g_hist_state_transition);
    histogram_reset(&g_hist_state_slots);
    histogram_reset(&g_hist_state_block);
    histogram_reset(&g_hist_state_attestations);
    histogram_reset(&g_hist_pq_sig_attestation_signing);
    histogram_reset(&g_hist_pq_sig_attestation_verification);
    histogram_reset(&g_hist_pq_sig_aggregated_signatures_building);
    histogram_reset(&g_hist_pq_sig_aggregated_signatures_verification);
    histogram_reset(&g_hist_committee_signatures_aggregation);
    histogram_reset(&g_hist_gossip_block_size);
    histogram_reset(&g_hist_gossip_attestation_size);
    histogram_reset(&g_hist_gossip_aggregation_size);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_block_aggregated_payloads(size_t count) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_block_aggregated_payloads, (double)count);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_block_building_payload_aggregation_time(double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_block_building_payload_aggregation, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_block_building_time(double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_block_building, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_block_building_success(void) {
    pthread_mutex_lock(&g_metrics_lock);
    g_block_building_success_total += 1;
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_block_building_failure(void) {
    pthread_mutex_lock(&g_metrics_lock);
    g_block_building_failures_total += 1;
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_fork_choice_block_time(double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_fork_choice_block, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_fork_choice_reorg(size_t depth) {
    if (depth == 0) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    g_fork_choice_reorgs_total += 1;
    histogram_observe(&g_hist_fork_choice_reorg_depth, (double)depth);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_attestation_validation(double seconds, bool valid) {
    pthread_mutex_lock(&g_metrics_lock);
    if (valid) {
        g_attestations_valid_total += 1;
    } else {
        g_attestations_invalid_total += 1;
    }
    histogram_observe(&g_hist_attestation_validation, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_state_transition(double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_state_transition, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_state_transition_slots(uint64_t slots_processed, double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    g_state_slots_processed_total += slots_processed;
    histogram_observe(&g_hist_state_slots, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_state_transition_block(double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_state_block, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_state_transition_attestations(uint64_t count, double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    g_state_attestations_processed_total += count;
    histogram_observe(&g_hist_state_attestations, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_finalization_attempt(bool success) {
    pthread_mutex_lock(&g_metrics_lock);
    if (success) {
        g_finalizations_success_total += 1;
    } else {
        g_finalizations_error_total += 1;
    }
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_pq_signature_signing(double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    g_pq_sig_attestation_signatures_total += 1;
    histogram_observe(&g_hist_pq_sig_attestation_signing, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_pq_signature_verification(double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_pq_sig_attestation_verification, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_pq_signature_verification_result(bool valid) {
    pthread_mutex_lock(&g_metrics_lock);
    if (valid) {
        g_pq_sig_attestation_signatures_valid_total += 1;
    } else {
        g_pq_sig_attestation_signatures_invalid_total += 1;
    }
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_pq_aggregated_signature_build(size_t attestation_count, double seconds) {
    pthread_mutex_lock(&g_metrics_lock);
    g_pq_sig_aggregated_signatures_total += 1;
    g_pq_sig_attestations_in_aggregated_signatures_total += (uint64_t)attestation_count;
    histogram_observe(&g_hist_pq_sig_aggregated_signatures_building, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_pq_aggregated_signature_verification(double seconds, bool valid) {
    pthread_mutex_lock(&g_metrics_lock);
    if (valid) {
        g_pq_sig_aggregated_signatures_valid_total += 1;
    } else {
        g_pq_sig_aggregated_signatures_invalid_total += 1;
    }
    histogram_observe(&g_hist_pq_sig_aggregated_signatures_verification, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_committee_signature_aggregation(double seconds, uint64_t aggregated_attestations) {
    pthread_mutex_lock(&g_metrics_lock);
    g_committee_aggregated_attestations_total += aggregated_attestations;
    histogram_observe(&g_hist_committee_signatures_aggregation, seconds);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_peer_connection(
    lean_metrics_direction_t direction,
    lean_metrics_connection_result_t result) {
    if (direction >= LEAN_METRICS_DIR_COUNT || result >= LEAN_METRICS_CONN_RESULT_COUNT) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    g_peer_connection_events_total[direction][result] += 1;
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_peer_disconnection(
    lean_metrics_direction_t direction,
    lean_metrics_disconnection_reason_t reason) {
    if (direction >= LEAN_METRICS_DIR_COUNT || reason >= LEAN_METRICS_DISCONNECT_REASON_COUNT) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    g_peer_disconnection_events_total[direction][reason] += 1;
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_gossip_block_size(size_t bytes_len) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_gossip_block_size, (double)bytes_len);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_gossip_attestation_size(size_t bytes_len) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_gossip_attestation_size, (double)bytes_len);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_record_gossip_aggregation_size(size_t bytes_len) {
    pthread_mutex_lock(&g_metrics_lock);
    histogram_observe(&g_hist_gossip_aggregation_size, (double)bytes_len);
    pthread_mutex_unlock(&g_metrics_lock);
}

void lean_metrics_snapshot(struct lean_metrics_snapshot *out) {
    if (!out) {
        return;
    }
    pthread_mutex_lock(&g_metrics_lock);
    out->attestations_valid_total = g_attestations_valid_total;
    out->attestations_invalid_total = g_attestations_invalid_total;
    out->pq_sig_attestation_signatures_total = g_pq_sig_attestation_signatures_total;
    out->pq_sig_attestation_signatures_valid_total = g_pq_sig_attestation_signatures_valid_total;
    out->pq_sig_attestation_signatures_invalid_total = g_pq_sig_attestation_signatures_invalid_total;
    out->pq_sig_aggregated_signatures_total = g_pq_sig_aggregated_signatures_total;
    out->pq_sig_aggregated_signatures_valid_total = g_pq_sig_aggregated_signatures_valid_total;
    out->pq_sig_aggregated_signatures_invalid_total = g_pq_sig_aggregated_signatures_invalid_total;
    out->pq_sig_attestations_in_aggregated_signatures_total = g_pq_sig_attestations_in_aggregated_signatures_total;
    out->committee_aggregated_attestations_total = g_committee_aggregated_attestations_total;
    out->fork_choice_reorgs_total = g_fork_choice_reorgs_total;
    out->finalizations_success_total = g_finalizations_success_total;
    out->finalizations_error_total = g_finalizations_error_total;
    out->block_building_success_total = g_block_building_success_total;
    out->block_building_failures_total = g_block_building_failures_total;
    for (size_t dir = 0; dir < LEAN_METRICS_DIR_COUNT; ++dir) {
        for (size_t res = 0; res < LEAN_METRICS_CONN_RESULT_COUNT; ++res) {
            out->peer_connection_events_total[dir][res] = g_peer_connection_events_total[dir][res];
        }
    }
    for (size_t dir = 0; dir < LEAN_METRICS_DIR_COUNT; ++dir) {
        for (size_t reason = 0; reason < LEAN_METRICS_DISCONNECT_REASON_COUNT; ++reason) {
            out->peer_disconnection_events_total[dir][reason] = g_peer_disconnection_events_total[dir][reason];
        }
    }
    out->state_transition_slots_processed_total = g_state_slots_processed_total;
    out->state_transition_attestations_processed_total = g_state_attestations_processed_total;
    histogram_snapshot(&out->block_aggregated_payloads, &g_hist_block_aggregated_payloads);
    histogram_snapshot(
        &out->block_building_payload_aggregation_time,
        &g_hist_block_building_payload_aggregation);
    histogram_snapshot(&out->block_building_time, &g_hist_block_building);
    histogram_snapshot(&out->fork_choice_block_time, &g_hist_fork_choice_block);
    histogram_snapshot(&out->fork_choice_reorg_depth, &g_hist_fork_choice_reorg_depth);
    histogram_snapshot(&out->attestation_validation_time, &g_hist_attestation_validation);
    histogram_snapshot(&out->state_transition_time, &g_hist_state_transition);
    histogram_snapshot(&out->state_slots_time, &g_hist_state_slots);
    histogram_snapshot(&out->state_block_time, &g_hist_state_block);
    histogram_snapshot(&out->state_attestations_time, &g_hist_state_attestations);
    histogram_snapshot(&out->pq_sig_attestation_signing_time, &g_hist_pq_sig_attestation_signing);
    histogram_snapshot(&out->pq_sig_attestation_verification_time, &g_hist_pq_sig_attestation_verification);
    histogram_snapshot(
        &out->pq_sig_aggregated_signatures_building_time,
        &g_hist_pq_sig_aggregated_signatures_building);
    histogram_snapshot(
        &out->pq_sig_aggregated_signatures_verification_time,
        &g_hist_pq_sig_aggregated_signatures_verification);
    histogram_snapshot(
        &out->committee_signatures_aggregation_time,
        &g_hist_committee_signatures_aggregation);
    histogram_snapshot(&out->gossip_block_size_bytes, &g_hist_gossip_block_size);
    histogram_snapshot(&out->gossip_attestation_size_bytes, &g_hist_gossip_attestation_size);
    histogram_snapshot(&out->gossip_aggregation_size_bytes, &g_hist_gossip_aggregation_size);
    pthread_mutex_unlock(&g_metrics_lock);
}
