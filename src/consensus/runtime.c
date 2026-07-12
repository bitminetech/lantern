#include "lantern/consensus/runtime.h"

#include <string.h>

void lantern_consensus_runtime_config_init(struct lantern_consensus_runtime_config *config) {
    if (!config) {
        return;
    }
    config->genesis_time = 0;
    config->seconds_per_slot = 4;
    config->intervals_per_slot = LANTERN_DUTY_PHASE_COUNT;
    config->validator_count = 0;
}

static int init_clock(
    struct lantern_slot_clock *clock,
    const struct lantern_consensus_runtime_config *config) {
    struct lantern_slot_clock_config clock_config;
    lantern_slot_clock_config_init(&clock_config);
    clock_config.genesis_time = config->genesis_time;
    clock_config.seconds_per_slot = config->seconds_per_slot;
    clock_config.intervals_per_slot = config->intervals_per_slot;
    return lantern_slot_clock_init(clock, &clock_config);
}

int lantern_consensus_runtime_init(
    struct lantern_consensus_runtime *runtime,
    const struct lantern_consensus_runtime_config *config,
    const struct lantern_validator_assignment *assignment) {
    if (!runtime || !config || !assignment) {
        return -1;
    }
    if (config->validator_count == 0) {
        return -1;
    }
    if (!lantern_validator_assignment_is_valid(assignment)) {
        return -1;
    }
    if (config->intervals_per_slot != LANTERN_DUTY_PHASE_COUNT) {
        return -1;
    }

    memset(runtime, 0, sizeof(*runtime));
    if (init_clock(&runtime->clock, config) != 0) {
        return -1;
    }
    if (lantern_validator_assignment_copy(&runtime->validator_assignment, assignment) != 0) {
        lantern_consensus_runtime_reset(runtime);
        return -1;
    }
    runtime->validator_count = config->validator_count;
    runtime->has_timepoint = false;
    runtime->initialized = true;
    return 0;
}

void lantern_consensus_runtime_reset(struct lantern_consensus_runtime *runtime) {
    if (!runtime) {
        return;
    }
    lantern_validator_assignment_reset(&runtime->validator_assignment);
    memset(runtime, 0, sizeof(*runtime));
}

int lantern_consensus_runtime_update_time(
    struct lantern_consensus_runtime *runtime,
    uint64_t now_milliseconds) {
    if (!runtime || !runtime->initialized) {
        return -1;
    }
    if (lantern_slot_clock_compute(&runtime->clock, now_milliseconds, &runtime->timepoint) != 0) {
        return -1;
    }
    runtime->has_timepoint = true;
    return 0;
}

const struct lantern_slot_timepoint *lantern_consensus_runtime_current_timepoint(
    const struct lantern_consensus_runtime *runtime) {
    if (!runtime || !runtime->initialized || !runtime->has_timepoint) {
        return NULL;
    }
    return &runtime->timepoint;
}

int lantern_consensus_runtime_local_proposer(
    const struct lantern_consensus_runtime *runtime,
    uint64_t slot,
    bool *out_is_local,
    uint64_t *out_local_validator_index) {
    if (!runtime || !runtime->initialized || !out_is_local) {
        return -1;
    }
    uint64_t proposer_index = 0;
    if (lantern_proposer_for_slot(slot, runtime->validator_count, &proposer_index) != 0) {
        return -1;
    }
    uint64_t local_index = 0;
    bool contains = lantern_validator_assignment_contains(
        &runtime->validator_assignment,
        proposer_index,
        &local_index);
    *out_is_local = contains;
    if (contains && out_local_validator_index) {
        *out_local_validator_index = local_index;
    }
    return 0;
}
