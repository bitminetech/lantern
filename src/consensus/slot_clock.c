#include "lantern/consensus/slot_clock.h"

#include <limits.h>

static int genesis_milliseconds(uint64_t genesis_time, uint64_t *out) {
    if (!out || genesis_time > UINT64_MAX / 1000u) {
        return -1;
    }
    *out = genesis_time * 1000u;
    return 0;
}

int lantern_slot_clock_total_interval(
    uint64_t genesis_time,
    uint64_t now_milliseconds,
    uint64_t *out_interval) {
    uint64_t genesis_ms = 0;
    if (!out_interval || genesis_milliseconds(genesis_time, &genesis_ms) != 0) {
        return -1;
    }
    if (now_milliseconds < genesis_ms) {
        return 1;
    }
    *out_interval = (now_milliseconds - genesis_ms) / LANTERN_MILLISECONDS_PER_INTERVAL;
    return 0;
}

int lantern_slot_clock_slot_start_time(
    uint64_t genesis_time,
    uint64_t slot,
    uint64_t *out_start_time) {
    uint64_t genesis_ms = 0;
    if (!out_start_time || genesis_milliseconds(genesis_time, &genesis_ms) != 0) {
        return -1;
    }
    if (slot > (UINT64_MAX - genesis_ms) / LANTERN_MILLISECONDS_PER_SLOT) {
        return -1;
    }
    *out_start_time = genesis_ms + (slot * LANTERN_MILLISECONDS_PER_SLOT);
    return 0;
}
