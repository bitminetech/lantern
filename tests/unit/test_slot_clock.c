#include "lantern/consensus/slot_clock.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

static int expect_interval(uint64_t now, uint64_t expected)
{
    uint64_t interval = UINT64_MAX;
    if (lantern_slot_clock_total_interval(1u, now, &interval) != 0
        || interval != expected)
    {
        fprintf(
            stderr,
            "interval at %" PRIu64 "ms: expected %" PRIu64 ", got %" PRIu64 "\n",
            now,
            expected,
            interval);
        return 1;
    }
    return 0;
}

int main(void)
{
    if (expect_interval(1000u, 0u) != 0
        || expect_interval(1750u, 0u) != 0
        || expect_interval(1850u, 1u) != 0
        || expect_interval(2600u, 2u) != 0
        || expect_interval(4200u, 4u) != 0
        || expect_interval(5000u, 5u) != 0
        || expect_interval(15400u, 18u) != 0)
    {
        return 1;
    }

    uint64_t slot_start = 0u;
    if (lantern_slot_clock_slot_start_time(2u, 3u, &slot_start) != 0
        || slot_start != 14000u)
    {
        fprintf(stderr, "slot start mismatch: got %" PRIu64 "\n", slot_start);
        return 1;
    }

    uint64_t interval = 0u;
    if (lantern_slot_clock_total_interval(1u, 999u, &interval) <= 0
        || lantern_slot_clock_total_interval(UINT64_MAX, UINT64_MAX, &interval) >= 0
        || lantern_slot_clock_slot_start_time(0u, UINT64_MAX, &slot_start) >= 0)
    {
        fputs("invalid clock input accepted\n", stderr);
        return 1;
    }

    puts("lantern_slot_clock_test OK");
    return 0;
}
