#ifndef LANTERN_METRICS_LEAN_METRICS_H
#define LANTERN_METRICS_LEAN_METRICS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LEAN_METRICS_MAX_BUCKETS 10u

typedef enum {
    LEAN_METRICS_DIR_INBOUND = 0,
    LEAN_METRICS_DIR_OUTBOUND = 1,
    LEAN_METRICS_DIR_COUNT = 2
} lean_metrics_direction_t;

typedef enum {
    LEAN_METRICS_CONN_RESULT_SUCCESS = 0,
    LEAN_METRICS_CONN_RESULT_TIMEOUT = 1,
    LEAN_METRICS_CONN_RESULT_ERROR = 2,
    LEAN_METRICS_CONN_RESULT_COUNT = 3
} lean_metrics_connection_result_t;

typedef enum {
    LEAN_METRICS_DISCONNECT_TIMEOUT = 0,
    LEAN_METRICS_DISCONNECT_REMOTE_CLOSE = 1,
    LEAN_METRICS_DISCONNECT_LOCAL_CLOSE = 2,
    LEAN_METRICS_DISCONNECT_ERROR = 3,
    LEAN_METRICS_DISCONNECT_REASON_COUNT = 4
} lean_metrics_disconnection_reason_t;

struct lean_metrics_histogram_snapshot {
    size_t bucket_count;
    double buckets[LEAN_METRICS_MAX_BUCKETS];
    uint64_t counts[LEAN_METRICS_MAX_BUCKETS + 1u];
    double sum;
    uint64_t total;
};

struct lean_metrics_snapshot {
    uint64_t attestations_valid_total;
    uint64_t attestations_invalid_total;
    uint64_t pq_sig_attestation_signatures_total;
    uint64_t pq_sig_attestation_signatures_valid_total;
    uint64_t pq_sig_attestation_signatures_invalid_total;
    uint64_t pq_sig_aggregated_signatures_total;
    uint64_t pq_sig_aggregated_signatures_valid_total;
    uint64_t pq_sig_aggregated_signatures_invalid_total;
    uint64_t pq_sig_attestations_in_aggregated_signatures_total;
    uint64_t committee_aggregated_attestations_total;
    uint64_t fork_choice_reorgs_total;
    uint64_t finalizations_success_total;
    uint64_t finalizations_error_total;
    uint64_t block_building_success_total;
    uint64_t block_building_failures_total;
    uint64_t peer_connection_events_total[LEAN_METRICS_DIR_COUNT][LEAN_METRICS_CONN_RESULT_COUNT];
    uint64_t peer_disconnection_events_total[LEAN_METRICS_DIR_COUNT][LEAN_METRICS_DISCONNECT_REASON_COUNT];
    uint64_t state_transition_slots_processed_total;
    uint64_t state_transition_attestations_processed_total;
    struct lean_metrics_histogram_snapshot block_aggregated_payloads;
    struct lean_metrics_histogram_snapshot block_building_payload_aggregation_time;
    struct lean_metrics_histogram_snapshot block_building_time;
    struct lean_metrics_histogram_snapshot attestations_production_time;
    struct lean_metrics_histogram_snapshot fork_choice_block_time;
    struct lean_metrics_histogram_snapshot fork_choice_reorg_depth;
    struct lean_metrics_histogram_snapshot attestation_validation_time;
    struct lean_metrics_histogram_snapshot state_transition_time;
    struct lean_metrics_histogram_snapshot state_slots_time;
    struct lean_metrics_histogram_snapshot state_block_time;
    struct lean_metrics_histogram_snapshot state_attestations_time;
    struct lean_metrics_histogram_snapshot pq_sig_attestation_signing_time;
    struct lean_metrics_histogram_snapshot pq_sig_attestation_verification_time;
    struct lean_metrics_histogram_snapshot pq_sig_aggregated_signatures_building_time;
    struct lean_metrics_histogram_snapshot pq_sig_aggregated_signatures_verification_time;
    struct lean_metrics_histogram_snapshot committee_signatures_aggregation_time;
    struct lean_metrics_histogram_snapshot gossip_block_size_bytes;
    struct lean_metrics_histogram_snapshot gossip_attestation_size_bytes;
    struct lean_metrics_histogram_snapshot gossip_aggregation_size_bytes;
};

void lean_metrics_reset(void);
void lean_metrics_record_block_aggregated_payloads(size_t count);
void lean_metrics_record_block_building_payload_aggregation_time(double seconds);
void lean_metrics_record_block_building_time(double seconds);
void lean_metrics_record_attestations_production_time(double seconds);
void lean_metrics_record_block_building_success(void);
void lean_metrics_record_block_building_failure(void);
void lean_metrics_record_fork_choice_block_time(double seconds);
void lean_metrics_record_fork_choice_reorg(size_t depth);
void lean_metrics_record_attestation_validation(double seconds, bool valid);
void lean_metrics_record_state_transition(double seconds);
void lean_metrics_record_state_transition_slots(uint64_t slots_processed, double seconds);
void lean_metrics_record_state_transition_block(double seconds);
void lean_metrics_record_state_transition_attestations(uint64_t count, double seconds);
void lean_metrics_record_finalization_attempt(bool success);
void lean_metrics_record_pq_signature_signing(double seconds);
void lean_metrics_record_pq_signature_verification(double seconds);
void lean_metrics_record_pq_signature_verification_result(bool valid);
void lean_metrics_record_pq_aggregated_signature_build(size_t attestation_count, double seconds);
void lean_metrics_record_pq_aggregated_signature_verification(double seconds, bool valid);
void lean_metrics_record_committee_signature_aggregation(double seconds, uint64_t aggregated_attestations);
void lean_metrics_record_peer_connection(
    lean_metrics_direction_t direction,
    lean_metrics_connection_result_t result);
void lean_metrics_record_peer_disconnection(
    lean_metrics_direction_t direction,
    lean_metrics_disconnection_reason_t reason);
void lean_metrics_record_gossip_block_size(size_t bytes_len);
void lean_metrics_record_gossip_attestation_size(size_t bytes_len);
void lean_metrics_record_gossip_aggregation_size(size_t bytes_len);
void lean_metrics_snapshot(struct lean_metrics_snapshot *out);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_METRICS_LEAN_METRICS_H */
