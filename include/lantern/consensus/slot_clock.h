#ifndef LANTERN_CONSENSUS_SLOT_CLOCK_H
#define LANTERN_CONSENSUS_SLOT_CLOCK_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    LANTERN_SECONDS_PER_SLOT = 4u,
    LANTERN_INTERVALS_PER_SLOT = 5u,
    LANTERN_MILLISECONDS_PER_SLOT = LANTERN_SECONDS_PER_SLOT * 1000u,
    LANTERN_MILLISECONDS_PER_INTERVAL =
        LANTERN_MILLISECONDS_PER_SLOT / LANTERN_INTERVALS_PER_SLOT,
};

enum lantern_duty_phase {
    LANTERN_DUTY_PHASE_PROPOSAL = 0,
    LANTERN_DUTY_PHASE_VOTE = 1,
    LANTERN_DUTY_PHASE_AGGREGATE = 2,
    LANTERN_DUTY_PHASE_SAFE_TARGET = 3,
    LANTERN_DUTY_PHASE_VOTE_ACCEPT = 4,
};

int lantern_slot_clock_total_interval(
    uint64_t genesis_time,
    uint64_t now_milliseconds,
    uint64_t *out_interval);
int lantern_slot_clock_slot_start_time(
    uint64_t genesis_time,
    uint64_t slot,
    uint64_t *out_start_time);
#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CONSENSUS_SLOT_CLOCK_H */
