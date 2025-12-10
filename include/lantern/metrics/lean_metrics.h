#ifndef LANTERN_METRICS_LEAN_METRICS_H
#define LANTERN_METRICS_LEAN_METRICS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LEAN_METRICS_MAX_BUCKETS 10u

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
    uint64_t state_transition_slots_processed_total;
    uint64_t state_transition_attestations_processed_total;
    struct lean_metrics_histogram_snapshot fork_choice_block_time;
    struct lean_metrics_histogram_snapshot attestation_validation_time;
    struct lean_metrics_histogram_snapshot state_transition_time;
    struct lean_metrics_histogram_snapshot state_slots_time;
    struct lean_metrics_histogram_snapshot state_block_time;
    struct lean_metrics_histogram_snapshot state_attestations_time;
    struct lean_metrics_histogram_snapshot pq_signature_signing_time;
    struct lean_metrics_histogram_snapshot pq_signature_verification_time;
};

void lean_metrics_reset(void);
void lean_metrics_record_fork_choice_block_time(double seconds);
void lean_metrics_record_attestation_validation(double seconds, bool valid);
void lean_metrics_record_state_transition(double seconds);
void lean_metrics_record_state_transition_slots(uint64_t slots_processed, double seconds);
void lean_metrics_record_state_transition_block(double seconds);
void lean_metrics_record_state_transition_attestations(uint64_t count, double seconds);
void lean_metrics_record_pq_signature_signing(double seconds);
void lean_metrics_record_pq_signature_verification(double seconds);
void lean_metrics_snapshot(struct lean_metrics_snapshot *out);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_METRICS_LEAN_METRICS_H */
