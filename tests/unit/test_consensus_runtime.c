#include "lantern/consensus/slot_clock.h"
#include "lantern/consensus/state.h"

#include <stdint.h>
#include <stdio.h>

static int expect_duty(uint64_t now, uint64_t expected_slot, enum lantern_duty_phase expected_phase)
{
    uint64_t total_interval = 0u;
    if (lantern_slot_clock_total_interval(1u, now, &total_interval) != 0
        || total_interval / LANTERN_INTERVALS_PER_SLOT != expected_slot
        || total_interval % LANTERN_INTERVALS_PER_SLOT != (uint64_t)expected_phase)
    {
        fprintf(stderr, "unexpected duty at %llu\n", (unsigned long long)now);
        return 1;
    }
    return 0;
}

int main(void)
{
    if (expect_duty(1000u, 0u, LANTERN_DUTY_PHASE_PROPOSAL) != 0
        || expect_duty(1800u, 0u, LANTERN_DUTY_PHASE_VOTE) != 0
        || expect_duty(2600u, 0u, LANTERN_DUTY_PHASE_AGGREGATE) != 0
        || expect_duty(4200u, 0u, LANTERN_DUTY_PHASE_VOTE_ACCEPT) != 0
        || expect_duty(5000u, 1u, LANTERN_DUTY_PHASE_PROPOSAL) != 0)
    {
        return 1;
    }

    uint64_t proposer = UINT64_MAX;
    if (lantern_proposer_for_slot(5u, 4u, &proposer) != 0 || proposer != 1u
        || lantern_proposer_for_slot(6u, 4u, &proposer) != 0 || proposer != 2u)
    {
        fputs("proposer selection mismatch\n", stderr);
        return 1;
    }

    puts("lantern_consensus_runtime_test OK");
    return 0;
}
