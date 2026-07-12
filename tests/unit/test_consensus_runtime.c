#include "lantern/consensus/runtime.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int init_range_assignment(
    struct lantern_validator_assignment *assignment,
    uint64_t start_index,
    uint64_t count) {
    if (!assignment || count == 0) {
        return -1;
    }
    lantern_validator_assignment_init(assignment);
    assignment->indices = malloc(count * sizeof(*assignment->indices));
    if (!assignment->indices) {
        return -1;
    }
    assignment->length = (size_t)count;
    for (uint64_t i = 0; i < count; ++i) {
        assignment->indices[i] = start_index + i;
    }
    return 0;
}

static int test_runtime_time_update(void) {
    struct lantern_validator_assignment assignment;
    if (init_range_assignment(&assignment, 2, 1) != 0) {
        fprintf(stderr, "assignment init failed\n");
        return 1;
    }
    int rc = 1;

    struct lantern_consensus_runtime_config config;
    lantern_consensus_runtime_config_init(&config);
    config.genesis_time = 1;
    config.validator_count = 4;

    struct lantern_consensus_runtime runtime;
    if (lantern_consensus_runtime_init(&runtime, &config, &assignment) != 0) {
        fprintf(stderr, "runtime init failed\n");
        goto cleanup;
    }

    if (lantern_consensus_runtime_update_time(&runtime, 5000) != 0) {
        fprintf(stderr, "runtime update time failed\n");
        goto cleanup_runtime;
    }
    const struct lantern_slot_timepoint *tp = lantern_consensus_runtime_current_timepoint(&runtime);
    if (!tp) {
        fprintf(stderr, "missing timepoint\n");
        goto cleanup_runtime;
    }
    if (tp->slot != 1 || tp->interval_index != 0) {
        fprintf(stderr, "unexpected timepoint slot=%llu interval=%u\n",
            (unsigned long long)tp->slot,
            tp->interval_index);
        goto cleanup_runtime;
    }
    if (tp->phase != LANTERN_DUTY_PHASE_PROPOSAL) {
        fprintf(stderr, "unexpected phase %u\n", tp->phase);
        goto cleanup_runtime;
    }

    rc = 0;

cleanup_runtime:
    lantern_consensus_runtime_reset(&runtime);
cleanup:
    lantern_validator_assignment_reset(&assignment);
    return rc;
}

static int test_local_proposer_detection(void) {
    struct lantern_validator_assignment assignment;
    if (init_range_assignment(&assignment, 2, 1) != 0) {
        fprintf(stderr, "assignment init failed\n");
        return 1;
    }
    int rc = 1;

    struct lantern_consensus_runtime_config config;
    lantern_consensus_runtime_config_init(&config);
    config.genesis_time = 0;
    config.validator_count = 4;

    struct lantern_consensus_runtime runtime;
    if (lantern_consensus_runtime_init(&runtime, &config, &assignment) != 0) {
        fprintf(stderr, "runtime init failed\n");
        goto cleanup;
    }

    bool is_local = false;
    uint64_t local_index = 0;
    if (lantern_consensus_runtime_local_proposer(&runtime, 5, &is_local, &local_index) != 0) {
        fprintf(stderr, "local proposer query failed\n");
        goto cleanup_runtime;
    }
    if (is_local) {
        fprintf(stderr, "slot 5 should not be local proposer\n");
        goto cleanup_runtime;
    }

    if (lantern_consensus_runtime_local_proposer(&runtime, 6, &is_local, &local_index) != 0) {
        fprintf(stderr, "local proposer query failed\n");
        goto cleanup_runtime;
    }
    if (!is_local || local_index != 0) {
        fprintf(stderr, "slot 6 should map to local validator index 0\n");
        goto cleanup_runtime;
    }

    if (runtime.validator_count != 4) {
        fprintf(stderr, "validator count mismatch\n");
        goto cleanup_runtime;
    }
    rc = 0;

cleanup_runtime:
    lantern_consensus_runtime_reset(&runtime);
cleanup:
    lantern_validator_assignment_reset(&assignment);
    return rc;
}

int main(void) {
    if (test_runtime_time_update() != 0) {
        return 1;
    }
    if (test_local_proposer_detection() != 0) {
        return 1;
    }
    puts("lantern_consensus_runtime_test OK");
    return 0;
}
