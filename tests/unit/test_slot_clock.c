#include "lantern/consensus/slot_clock.h"

#include <stdio.h>
#include <string.h>

#define CHECK_EQ(actual, expected, label)                                                                                \
    do {                                                                                                                 \
        if ((actual) != (expected)) {                                                                                    \
            fprintf(stderr, "%s mismatch: expected %llu got %llu\n", label,                                              \
                (unsigned long long)(expected), (unsigned long long)(actual));                                           \
            return 1;                                                                                                    \
        }                                                                                                                \
    } while (0)

#define CHECK_ZERO(expr, label)                                                                                          \
    do {                                                                                                                 \
        if ((expr) != 0) {                                                                                               \
            fprintf(stderr, "%s failed\n", label);                                                                       \
            return 1;                                                                                                    \
        }                                                                                                                \
    } while (0)

static int init_clock(struct lantern_slot_clock *clock, uint64_t genesis_time) {
    struct lantern_slot_clock_config cfg;
    lantern_slot_clock_config_init(&cfg);
    cfg.genesis_time = genesis_time;
    return lantern_slot_clock_init(clock, &cfg);
}

static int test_slot_progression(void) {
    struct lantern_slot_clock clock;
    if (init_clock(&clock, 1) != 0) {
        fprintf(stderr, "clock init failed\n");
        return 1;
    }

    struct lantern_slot_timepoint info;
    CHECK_ZERO(lantern_slot_clock_compute(&clock, 1000, &info), "compute genesis");
    CHECK_EQ(info.slot, 0, "slot@genesis");
    CHECK_EQ(info.interval_index, 0, "interval@genesis");
    CHECK_EQ(info.phase, LANTERN_DUTY_PHASE_PROPOSAL, "phase@genesis");
    CHECK_EQ(info.interval_start_time, 1000, "interval_start@genesis");
    CHECK_EQ(info.interval_end_time, 1800, "interval_end@genesis");

    CHECK_ZERO(lantern_slot_clock_compute(&clock, 2600, &info), "compute interval2");
    CHECK_EQ(info.slot, 0, "slot@interval2");
    CHECK_EQ(info.interval_index, 2, "interval@interval2");
    CHECK_EQ(info.phase, LANTERN_DUTY_PHASE_AGGREGATE, "phase@interval2");

    CHECK_ZERO(lantern_slot_clock_compute(&clock, 4200, &info), "compute interval4");
    CHECK_EQ(info.interval_index, 4, "interval@interval4");
    CHECK_EQ(info.phase, LANTERN_DUTY_PHASE_VOTE_ACCEPT, "phase@interval4");

    CHECK_ZERO(lantern_slot_clock_compute(&clock, 5000, &info), "compute slot1");
    CHECK_EQ(info.slot, 1, "slot@slot1");
    CHECK_EQ(info.interval_index, 0, "interval@slot1");
    CHECK_EQ(info.slot_start_time, 5000, "slot_start@slot1");

    CHECK_ZERO(lantern_slot_clock_compute(&clock, 3400, &info), "compute interval3");
    CHECK_EQ(info.interval_index, 3, "interval@interval3");
    CHECK_EQ(info.phase, LANTERN_DUTY_PHASE_SAFE_TARGET, "phase@interval3");

    return 0;
}

static int test_schedule_helpers(void) {
    struct lantern_slot_clock clock;
    if (init_clock(&clock, 2) != 0) {
        fprintf(stderr, "clock init failed\n");
        return 1;
    }

    uint64_t slot_start = 0;
    CHECK_ZERO(lantern_slot_clock_slot_start_time(&clock, 3, &slot_start), "slot start");
    CHECK_EQ(slot_start, 14000, "slot3 start");

    uint64_t vote_start = 0;
    CHECK_ZERO(
        lantern_slot_clock_phase_start_time(&clock, 3, LANTERN_DUTY_PHASE_VOTE, &vote_start),
        "phase start");
    CHECK_EQ(vote_start, slot_start + 800, "vote phase start");

    uint64_t safe_end = 0;
    CHECK_ZERO(
        lantern_slot_clock_phase_end_time(&clock, 3, LANTERN_DUTY_PHASE_SAFE_TARGET, &safe_end),
        "phase end");
    CHECK_EQ(safe_end, slot_start + 3200, "safe phase end");

    struct lantern_duty_schedule schedule;
    CHECK_ZERO(lantern_slot_clock_schedule_slot(&clock, 1, &schedule), "schedule slot");
    CHECK_EQ(schedule.slot, 1, "schedule slot index");
    CHECK_EQ(schedule.phase_start_times[0], 6000, "proposal start slot1");
    CHECK_EQ(schedule.phase_start_times[1], 6800, "vote start slot1");
    CHECK_EQ(schedule.phase_end_times[4], 10000, "vote accept end slot1");

    return 0;
}

static int test_invalid_config(void) {
    struct lantern_slot_clock clock;
    struct lantern_slot_clock_config cfg = {
        .genesis_time = 0,
        .seconds_per_slot = 4,
        .intervals_per_slot = 3,
    };
    if (lantern_slot_clock_init(&clock, &cfg) == 0) {
        fprintf(stderr, "invalid config accepted\n");
        return 1;
    }

    CHECK_ZERO(init_clock(&clock, 1), "valid clock init");
    struct lantern_slot_timepoint info;
    if (lantern_slot_clock_compute(&clock, 1000, &info) != 0) {
        fprintf(stderr, "compute at genesis failed\n");
        return 1;
    }
    if (lantern_slot_clock_compute(&clock, 999, &info) == 0) {
        fprintf(stderr, "pre-genesis compute succeeded unexpectedly\n");
        return 1;
    }
    return 0;
}

int main(void) {
    if (test_slot_progression() != 0) {
        return 1;
    }
    if (test_schedule_helpers() != 0) {
        return 1;
    }
    if (test_invalid_config() != 0) {
        return 1;
    }
    puts("lantern_slot_clock_test OK");
    return 0;
}
