#include "lantern/consensus/slot_clock.h"
#include "lantern/consensus/state.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

static const uint64_t local_validators[] = {1u, 2u};

static bool local_proposer(uint64_t slot, size_t *out_local_index)
{
    uint64_t proposer = 0u;
    if (lantern_proposer_for_slot(slot, 4u, &proposer) != 0)
    {
        return false;
    }
    for (size_t i = 0u; i < sizeof(local_validators) / sizeof(local_validators[0]); ++i)
    {
        if (local_validators[i] == proposer)
        {
            *out_local_index = i;
            return true;
        }
    }
    return false;
}

static int expect_duty(
    uint64_t now,
    uint64_t expected_slot,
    enum lantern_duty_phase expected_phase,
    bool expected_local,
    size_t expected_local_index)
{
    uint64_t interval = 0u;
    if (lantern_slot_clock_total_interval(1u, now, &interval) != 0
        || interval / LANTERN_INTERVALS_PER_SLOT != expected_slot
        || interval % LANTERN_INTERVALS_PER_SLOT != (uint64_t)expected_phase)
    {
        fprintf(stderr, "duty mismatch at %llu\n", (unsigned long long)now);
        return 1;
    }
    size_t local_index = 0u;
    bool is_local = local_proposer(expected_slot, &local_index);
    if (is_local != expected_local || (is_local && local_index != expected_local_index))
    {
        fprintf(stderr, "local proposer mismatch at slot %llu\n", (unsigned long long)expected_slot);
        return 1;
    }
    return 0;
}

int main(void)
{
    if (expect_duty(1000u, 0u, LANTERN_DUTY_PHASE_PROPOSAL, false, 0u) != 0
        || expect_duty(1800u, 0u, LANTERN_DUTY_PHASE_VOTE, false, 0u) != 0
        || expect_duty(2600u, 0u, LANTERN_DUTY_PHASE_AGGREGATE, false, 0u) != 0
        || expect_duty(4200u, 0u, LANTERN_DUTY_PHASE_VOTE_ACCEPT, false, 0u) != 0
        || expect_duty(5000u, 1u, LANTERN_DUTY_PHASE_PROPOSAL, true, 0u) != 0
        || expect_duty(9000u, 2u, LANTERN_DUTY_PHASE_PROPOSAL, true, 1u) != 0
        || expect_duty(13000u, 3u, LANTERN_DUTY_PHASE_PROPOSAL, false, 0u) != 0)
    {
        return 1;
    }
    puts("lantern_validator_duties_integration OK");
    return 0;
}
