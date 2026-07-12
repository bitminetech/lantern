#ifndef LANTERN_CONSENSUS_SLOT_CLOCK_H
#define LANTERN_CONSENSUS_SLOT_CLOCK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LANTERN_DUTY_PHASE_COUNT 5u

enum lantern_duty_phase {
    LANTERN_DUTY_PHASE_PROPOSAL = 0,
    LANTERN_DUTY_PHASE_VOTE = 1,
    LANTERN_DUTY_PHASE_AGGREGATE = 2,
    LANTERN_DUTY_PHASE_SAFE_TARGET = 3,
    LANTERN_DUTY_PHASE_VOTE_ACCEPT = 4,
    LANTERN_DUTY_PHASE_UNKNOWN = 255,
};

struct lantern_slot_clock_config {
    uint64_t genesis_time;
    uint32_t seconds_per_slot;
    uint32_t intervals_per_slot;
};

struct lantern_slot_clock {
    uint64_t genesis_time;
    uint32_t seconds_per_slot;
    uint32_t intervals_per_slot;
    uint64_t milliseconds_per_slot;
    uint64_t milliseconds_per_interval;
};

struct lantern_slot_timepoint {
    uint64_t slot;
    uint32_t interval_index;
    uint64_t slot_start_time;
    uint64_t interval_start_time;
    uint64_t interval_end_time;
    enum lantern_duty_phase phase;
};

void lantern_slot_clock_config_init(struct lantern_slot_clock_config *config);
int lantern_slot_clock_init(struct lantern_slot_clock *clock, const struct lantern_slot_clock_config *config);
int lantern_slot_clock_compute(
    const struct lantern_slot_clock *clock,
    uint64_t now_milliseconds,
    struct lantern_slot_timepoint *out_timepoint);
int lantern_slot_clock_slot_start_time(
    const struct lantern_slot_clock *clock,
    uint64_t slot,
    uint64_t *out_start_time);
#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_SLOT_CLOCK_H */
