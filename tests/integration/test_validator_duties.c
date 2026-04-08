#include "lantern/consensus/runtime.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/slot_clock.h"

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

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
    assignment->start_index = start_index;
    assignment->count = count;
    assignment->length = (size_t)count;
    for (uint64_t i = 0; i < count; ++i) {
        assignment->indices[i] = start_index + i;
    }
    return 0;
}

#define EXPECT_EQ(actual, expected, label)                                                                              \
    do {                                                                                                                \
        if ((actual) != (expected)) {                                                                                    \
            fprintf(stderr, "%s mismatch: expected %" PRIu64 " got %" PRIu64 "\n", label,                                \
                (uint64_t)(expected), (uint64_t)(actual));                                                               \
            return 1;                                                                                                    \
        }                                                                                                                \
    } while (0)

static int expect_timepoint(
    struct lantern_consensus_runtime *runtime,
    uint64_t now,
    uint64_t expected_slot,
    enum lantern_duty_phase expected_phase,
    bool expect_local_proposer,
    uint64_t expected_local_index) {
    if (!runtime) {
        return 1;
    }

    if (lantern_consensus_runtime_update_time(runtime, now) != 0) {
        fprintf(stderr, "update_time failed at %" PRIu64 "\n", now);
        return 1;
    }

    const struct lantern_slot_timepoint *tp = lantern_consensus_runtime_current_timepoint(runtime);
    if (!tp) {
        fprintf(stderr, "timepoint missing at %" PRIu64 "\n", now);
        return 1;
    }

    if (tp->slot != expected_slot) {
        fprintf(stderr, "slot mismatch at %" PRIu64 ": expected %" PRIu64 " got %" PRIu64 "\n",
            now,
            expected_slot,
            tp->slot);
        return 1;
    }

    if (tp->phase != expected_phase) {
        fprintf(stderr, "phase mismatch at %" PRIu64 ": expected %u got %u\n",
            now,
            (unsigned)expected_phase,
            (unsigned)tp->phase);
        return 1;
    }

    uint64_t expected_slot_start = runtime->clock.genesis_time
        * 1000u
        + (expected_slot * runtime->clock.milliseconds_per_slot);
    if (tp->slot_start_time != expected_slot_start) {
        fprintf(stderr, "slot_start mismatch at %" PRIu64 ": expected %" PRIu64 " got %" PRIu64 "\n",
            now,
            expected_slot_start,
            tp->slot_start_time);
        return 1;
    }

    uint64_t interval_duration = runtime->clock.milliseconds_per_interval;
    if (tp->interval_end_time != tp->interval_start_time + interval_duration) {
        fprintf(stderr, "interval duration mismatch at %" PRIu64 "\n", now);
        return 1;
    }
    if (tp->interval_start_time > now || tp->interval_end_time <= now) {
        fprintf(stderr, "interval coverage mismatch at %" PRIu64 "\n", now);
        return 1;
    }

    bool is_local = false;
    uint64_t local_index = UINT64_C(0);
    if (lantern_consensus_runtime_local_proposer(runtime, tp->slot, &is_local, &local_index) != 0) {
        fprintf(stderr, "local proposer lookup failed for slot %" PRIu64 "\n", tp->slot);
        return 1;
    }
    if (expect_local_proposer) {
        if (!is_local) {
            fprintf(stderr, "expected local proposer at slot %" PRIu64 "\n", tp->slot);
            return 1;
        }
        if (local_index != expected_local_index) {
            fprintf(stderr, "local proposer index mismatch: expected %" PRIu64 " got %" PRIu64 "\n",
                expected_local_index,
                local_index);
            return 1;
        }
    } else if (is_local) {
        fprintf(stderr, "unexpected local proposer at slot %" PRIu64 "\n", tp->slot);
        return 1;
    }

    return 0;
}

static int run_schedule_assertions(const struct lantern_consensus_runtime *runtime) {
    if (!runtime) {
        return 1;
    }
    struct lantern_duty_schedule schedule;
    if (lantern_consensus_runtime_schedule_slot(runtime, 1, &schedule) != 0) {
        fprintf(stderr, "schedule_slot failed for slot 1\n");
        return 1;
    }
    EXPECT_EQ(schedule.slot, 1, "schedule.slot");

    uint64_t slot1_start = (runtime->clock.genesis_time * 1000u) + runtime->clock.milliseconds_per_slot;
    uint64_t interval = runtime->clock.milliseconds_per_interval;
    EXPECT_EQ(schedule.phase_start_times[0], slot1_start, "proposal start");
    EXPECT_EQ(schedule.phase_start_times[1], slot1_start + interval, "vote start");
    EXPECT_EQ(schedule.phase_start_times[2], slot1_start + interval * 2u, "aggregate start");
    EXPECT_EQ(schedule.phase_start_times[3], slot1_start + interval * 3u, "safe target start");
    EXPECT_EQ(schedule.phase_start_times[4], slot1_start + interval * 4u, "vote accept start");
    EXPECT_EQ(schedule.phase_end_times[4], slot1_start + interval * 5u, "final phase end");
    return 0;
}

int main(void) {
    struct lantern_consensus_runtime runtime;
    struct lantern_consensus_runtime_config cfg;
    lantern_consensus_runtime_config_init(&cfg);
    cfg.genesis_time = 1;
    cfg.seconds_per_slot = 4;
    cfg.intervals_per_slot = LANTERN_DUTY_PHASE_COUNT;
    cfg.validator_count = 4;

    struct lantern_validator_assignment assignment;
    if (init_range_assignment(&assignment, 1, 2) != 0) {
        fprintf(stderr, "assignment init failed\n");
        return 1;
    }

    if (lantern_consensus_runtime_init(&runtime, &cfg, &assignment) != 0) {
        fprintf(stderr, "runtime init failed\n");
        return 1;
    }

    if (lantern_consensus_runtime_validator_count(&runtime) != cfg.validator_count) {
        fprintf(stderr, "validator count mismatch\n");
        return 1;
    }

    if (run_schedule_assertions(&runtime) != 0) {
        return 1;
    }

    if (expect_timepoint(&runtime, 1000, 0, LANTERN_DUTY_PHASE_PROPOSAL, false, 0) != 0) {
        return 1;
    }
    if (expect_timepoint(&runtime, 1800, 0, LANTERN_DUTY_PHASE_VOTE, false, 0) != 0) {
        return 1;
    }
    if (expect_timepoint(&runtime, 2600, 0, LANTERN_DUTY_PHASE_AGGREGATE, false, 0) != 0) {
        return 1;
    }
    if (expect_timepoint(&runtime, 4200, 0, LANTERN_DUTY_PHASE_VOTE_ACCEPT, false, 0) != 0) {
        return 1;
    }
    if (expect_timepoint(&runtime, 5000, 1, LANTERN_DUTY_PHASE_PROPOSAL, true, 0) != 0) {
        return 1;
    }
    if (expect_timepoint(&runtime, 5800, 1, LANTERN_DUTY_PHASE_VOTE, true, 0) != 0) {
        return 1;
    }
    if (expect_timepoint(&runtime, 9000, 2, LANTERN_DUTY_PHASE_PROPOSAL, true, 1) != 0) {
        return 1;
    }
    if (expect_timepoint(&runtime, 13000, 3, LANTERN_DUTY_PHASE_PROPOSAL, false, 0) != 0) {
        return 1;
    }

    lantern_consensus_runtime_reset(&runtime);
    lantern_validator_assignment_reset(&assignment);
    puts("lantern_validator_duties_integration OK");
    return 0;
}
