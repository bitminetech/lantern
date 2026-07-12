#include "lantern/consensus/slot_clock.h"

#include <limits.h>
#include <stddef.h>

#define LANTERN_SLOT_CLOCK_DEFAULT_SECONDS_PER_SLOT 4u
#define LANTERN_SLOT_CLOCK_DEFAULT_INTERVALS_PER_SLOT 5u
#define LANTERN_MILLISECONDS_PER_SECOND 1000u

static enum lantern_duty_phase interval_to_phase(uint32_t interval_index) {
    switch (interval_index) {
    case 0:
        return LANTERN_DUTY_PHASE_PROPOSAL;
    case 1:
        return LANTERN_DUTY_PHASE_VOTE;
    case 2:
        return LANTERN_DUTY_PHASE_AGGREGATE;
    case 3:
        return LANTERN_DUTY_PHASE_SAFE_TARGET;
    case 4:
        return LANTERN_DUTY_PHASE_VOTE_ACCEPT;
    default:
        return LANTERN_DUTY_PHASE_UNKNOWN;
    }
}

static int multiply_u64_u32(uint64_t lhs, uint32_t rhs, uint64_t *out) {
    if (!out) {
        return -1;
    }
    if (rhs == 0 || lhs == 0) {
        *out = 0;
        return 0;
    }
    if (lhs > UINT64_MAX / rhs) {
        return -1;
    }
    *out = lhs * (uint64_t)rhs;
    return 0;
}

static int multiply_u64(uint64_t lhs, uint64_t rhs, uint64_t *out) {
    if (!out) {
        return -1;
    }
    if (lhs == 0 || rhs == 0) {
        *out = 0;
        return 0;
    }
    if (lhs > UINT64_MAX / rhs) {
        return -1;
    }
    *out = lhs * rhs;
    return 0;
}

static int add_u64(uint64_t a, uint64_t b, uint64_t *out) {
    if (!out) {
        return -1;
    }
    if (a > UINT64_MAX - b) {
        return -1;
    }
    *out = a + b;
    return 0;
}

static int milliseconds_since_genesis(
    const struct lantern_slot_clock *clock,
    uint64_t now_milliseconds,
    uint64_t *out_elapsed) {
    if (!clock || !out_elapsed) {
        return -1;
    }
    uint64_t genesis_millis = 0;
    if (multiply_u64_u32(clock->genesis_time, LANTERN_MILLISECONDS_PER_SECOND, &genesis_millis) != 0) {
        return -1;
    }
    if (now_milliseconds < genesis_millis) {
        return -1;
    }
    *out_elapsed = now_milliseconds - genesis_millis;
    return 0;
}

static int validate_config(const struct lantern_slot_clock_config *config) {
    if (!config) {
        return -1;
    }
    if (config->seconds_per_slot == 0 || config->intervals_per_slot == 0) {
        return -1;
    }
    if (config->intervals_per_slot != LANTERN_DUTY_PHASE_COUNT) {
        return -1;
    }
    uint64_t milliseconds_per_slot = (uint64_t)config->seconds_per_slot * LANTERN_MILLISECONDS_PER_SECOND;
    if (milliseconds_per_slot == 0 || (milliseconds_per_slot % config->intervals_per_slot) != 0) {
        return -1;
    }
    return 0;
}

void lantern_slot_clock_config_init(struct lantern_slot_clock_config *config) {
    if (!config) {
        return;
    }
    config->genesis_time = 0;
    config->seconds_per_slot = LANTERN_SLOT_CLOCK_DEFAULT_SECONDS_PER_SLOT;
    config->intervals_per_slot = LANTERN_SLOT_CLOCK_DEFAULT_INTERVALS_PER_SLOT;
}

int lantern_slot_clock_init(struct lantern_slot_clock *clock, const struct lantern_slot_clock_config *config) {
    if (!clock) {
        return -1;
    }

    struct lantern_slot_clock_config local;
    if (config) {
        local = *config;
    } else {
        lantern_slot_clock_config_init(&local);
    }

    if (validate_config(&local) != 0) {
        return -1;
    }

    clock->genesis_time = local.genesis_time;
    clock->seconds_per_slot = local.seconds_per_slot;
    clock->intervals_per_slot = local.intervals_per_slot;
    clock->milliseconds_per_slot = (uint64_t)local.seconds_per_slot * LANTERN_MILLISECONDS_PER_SECOND;
    clock->milliseconds_per_interval = clock->milliseconds_per_slot / local.intervals_per_slot;
    return 0;
}

int lantern_slot_clock_slot_start_time(
    const struct lantern_slot_clock *clock,
    uint64_t slot,
    uint64_t *out_start_time) {
    if (!clock || !out_start_time) {
        return -1;
    }
    uint64_t slot_offset = 0;
    if (multiply_u64(slot, clock->milliseconds_per_slot, &slot_offset) != 0) {
        return -1;
    }
    uint64_t genesis_millis = 0;
    if (multiply_u64_u32(clock->genesis_time, LANTERN_MILLISECONDS_PER_SECOND, &genesis_millis) != 0) {
        return -1;
    }
    if (add_u64(genesis_millis, slot_offset, out_start_time) != 0) {
        return -1;
    }
    return 0;
}

static int interval_start_time(
    const struct lantern_slot_clock *clock,
    uint64_t slot,
    uint32_t interval_index,
    uint64_t *out_start_time) {
    if (!clock || !out_start_time) {
        return -1;
    }
    uint64_t slot_start = 0;
    if (lantern_slot_clock_slot_start_time(clock, slot, &slot_start) != 0) {
        return -1;
    }
    uint64_t interval_offset = 0;
    if (multiply_u64((uint64_t)interval_index, clock->milliseconds_per_interval, &interval_offset) != 0) {
        return -1;
    }
    if (add_u64(slot_start, interval_offset, out_start_time) != 0) {
        return -1;
    }
    return 0;
}

int lantern_slot_clock_compute(
    const struct lantern_slot_clock *clock,
    uint64_t now_milliseconds,
    struct lantern_slot_timepoint *out_timepoint) {
    if (!clock || !out_timepoint) {
        return -1;
    }
    uint64_t elapsed = 0;
    if (milliseconds_since_genesis(clock, now_milliseconds, &elapsed) != 0) {
        return -1;
    }
    if (clock->milliseconds_per_interval == 0) {
        return -1;
    }
    uint64_t intervals_since_genesis = elapsed / clock->milliseconds_per_interval;
    uint64_t slot = intervals_since_genesis / clock->intervals_per_slot;
    uint32_t interval_index = (uint32_t)(intervals_since_genesis % clock->intervals_per_slot);

    uint64_t slot_start = 0;
    if (lantern_slot_clock_slot_start_time(clock, slot, &slot_start) != 0) {
        return -1;
    }
    uint64_t interval_start = 0;
    if (interval_start_time(clock, slot, interval_index, &interval_start) != 0) {
        return -1;
    }
    uint64_t interval_end = 0;
    if (add_u64(interval_start, clock->milliseconds_per_interval, &interval_end) != 0) {
        return -1;
    }

    out_timepoint->slot = slot;
    out_timepoint->interval_index = interval_index;
    out_timepoint->slot_start_time = slot_start;
    out_timepoint->interval_start_time = interval_start;
    out_timepoint->interval_end_time = interval_end;
    out_timepoint->phase = interval_to_phase(interval_index);
    return 0;
}
