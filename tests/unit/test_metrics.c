#include <assert.h>
#include <string.h>

#include "lantern/metrics/lean_metrics.h"

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
    assert(snapshot.fork_choice_block_time.counts[0] == 1);
    assert(snapshot.fork_choice_block_time.counts[2] >= 1);
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

    struct lean_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    lean_metrics_snapshot(&snapshot);

    assert(snapshot.pq_sig_individual_signatures_total == 2);
    assert(snapshot.pq_sig_individual_signatures_valid_total == 1);
    assert(snapshot.pq_sig_individual_signatures_invalid_total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_valid_total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_invalid_total == 1);
    assert(snapshot.pq_sig_attestations_in_aggregated_signatures_total == 4);
    assert(snapshot.pq_signature_signing_time.total == 1);
    assert(snapshot.pq_signature_verification_time.total == 1);
    assert(snapshot.pq_sig_attestation_signatures_building_time.total == 1);
    assert(snapshot.pq_sig_aggregated_signatures_verification_time.total == 2);
    return 0;
}

static int test_committee_aggregation_metrics(void) {
    lean_metrics_reset();
    lean_metrics_record_committee_signature_aggregation(0.08, 2);
    lean_metrics_record_committee_signature_aggregation(0.12, 1);

    struct lean_metrics_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    lean_metrics_snapshot(&snapshot);

    assert(snapshot.committee_aggregated_attestations_total == 3);
    assert(snapshot.committee_signatures_aggregation_time.total == 2);
    assert(snapshot.committee_signatures_aggregation_time.sum > 0.0);
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
    if (test_pq_signature_metrics() != 0) {
        return 1;
    }
    if (test_committee_aggregation_metrics() != 0) {
        return 1;
    }
    return 0;
}
