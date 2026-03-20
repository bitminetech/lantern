#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "lantern/consensus/state.h"

#include "../../src/core/client_internal.h"

static int expect_case(
    const char *label,
    uint64_t persisted_slot,
    uint64_t genesis_time,
    uint32_t slot_duration_seconds,
    uint64_t now_seconds,
    bool expected_stale,
    uint64_t expected_current_slot,
    uint64_t expected_gap)
{
    LanternState state;
    lantern_state_init(&state);
    state.slot = persisted_slot;

    uint64_t current_slot = UINT64_C(9999);
    uint64_t gap = UINT64_C(9999);
    bool stale = lantern_client_persisted_state_is_stale_for_checkpoint_sync(
        &state,
        genesis_time,
        slot_duration_seconds,
        now_seconds,
        &current_slot,
        &gap);

    lantern_state_reset(&state);

    if (stale != expected_stale)
    {
        fprintf(
            stderr,
            "%s stale mismatch got=%d expected=%d\n",
            label,
            stale ? 1 : 0,
            expected_stale ? 1 : 0);
        return 1;
    }
    if (current_slot != expected_current_slot)
    {
        fprintf(
            stderr,
            "%s current slot mismatch got=%" PRIu64 " expected=%" PRIu64 "\n",
            label,
            current_slot,
            expected_current_slot);
        return 1;
    }
    if (gap != expected_gap)
    {
        fprintf(
            stderr,
            "%s gap mismatch got=%" PRIu64 " expected=%" PRIu64 "\n",
            label,
            gap,
            expected_gap);
        return 1;
    }

    return 0;
}

int main(void)
{
    if (expect_case(
            "fresh_enough_boundary",
            10u,
            1000u,
            4u,
            1000u + ((10u + 64u) * 4u),
            false,
            74u,
            64u)
        != 0)
    {
        return 1;
    }

    if (expect_case(
            "stale_beyond_boundary",
            10u,
            1000u,
            4u,
            1000u + ((10u + 65u) * 4u),
            true,
            75u,
            65u)
        != 0)
    {
        return 1;
    }

    if (expect_case(
            "before_genesis",
            0u,
            5000u,
            4u,
            4990u,
            false,
            0u,
            0u)
        != 0)
    {
        return 1;
    }

    return 0;
}
