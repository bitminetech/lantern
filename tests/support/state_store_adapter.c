#include "state_store_adapter.h"

#include <string.h>

static struct lantern_test_state_store_slot g_lantern_test_state_store_slots[LANTERN_TEST_STATE_STORE_SLOT_CAP];

struct lantern_test_state_store_slot *lantern_test_state_store_slots(void) {
    return g_lantern_test_state_store_slots;
}

struct lantern_test_state_store_slot *lantern_test_state_store_find_slot(const LanternState *state) {
    if (!state) {
        return NULL;
    }
    struct lantern_test_state_store_slot *slots = lantern_test_state_store_slots();
    for (size_t i = 0; i < LANTERN_TEST_STATE_STORE_SLOT_CAP; ++i) {
        if (slots[i].in_use && slots[i].state == state) {
            return &slots[i];
        }
    }
    return NULL;
}

LanternStore *lantern_test_state_store_ensure(LanternState *state) {
    struct lantern_test_state_store_slot *slot = lantern_test_state_store_find_slot(state);
    if (slot) {
        return &slot->store;
    }
    struct lantern_test_state_store_slot *slots = lantern_test_state_store_slots();
    for (size_t i = 0; i < LANTERN_TEST_STATE_STORE_SLOT_CAP; ++i) {
        if (!slots[i].in_use) {
            slots[i].in_use = true;
            slots[i].state = state;
            lantern_store_init(&slots[i].store);
            return &slots[i].store;
        }
    }
    return NULL;
}

const LanternStore *lantern_test_state_store_find(const LanternState *state) {
    struct lantern_test_state_store_slot *slot = lantern_test_state_store_find_slot(state);
    return slot ? &slot->store : NULL;
}

void lantern_test_state_store_release(LanternState *state) {
    struct lantern_test_state_store_slot *slot = lantern_test_state_store_find_slot(state);
    if (!slot) {
        return;
    }
    lantern_store_reset(&slot->store);
    memset(slot, 0, sizeof(*slot));
}
