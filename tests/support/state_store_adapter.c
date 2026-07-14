#include "state_store_adapter.h"

#include <string.h>

#undef lantern_state_process_attestations

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
        return slot->store;
    }
    struct lantern_test_state_store_slot *slots = lantern_test_state_store_slots();
    for (size_t i = 0; i < LANTERN_TEST_STATE_STORE_SLOT_CAP; ++i) {
        if (!slots[i].in_use) {
            slots[i].in_use = true;
            slots[i].state = state;
            slots[i].store = &slots[i].owned_store;
            lantern_store_init(slots[i].store);
            return slots[i].store;
        }
    }
    return NULL;
}

const LanternStore *lantern_test_state_store_find(const LanternState *state) {
    struct lantern_test_state_store_slot *slot = lantern_test_state_store_find_slot(state);
    return slot ? slot->store : NULL;
}

void lantern_test_state_store_release(LanternState *state) {
    struct lantern_test_state_store_slot *slot = lantern_test_state_store_find_slot(state);
    if (!slot) {
        return;
    }
    if (slot->store == &slot->owned_store) {
        lantern_store_reset(slot->store);
    }
    memset(slot, 0, sizeof(*slot));
}

int lantern_test_state_process_attestations(
    LanternState *state,
    const LanternAttestations *attestations) {
    if (!state || !attestations || attestations->length > LANTERN_MAX_ATTESTATIONS
        || (attestations->length > 0 && !attestations->data)) {
        return -1;
    }
    LanternAggregatedAttestations aggregated;
    lantern_aggregated_attestations_init(&aggregated);
    int rc = 0;
    for (size_t i = 0; i < attestations->length; ++i) {
        const LanternVote *vote = &attestations->data[i];
        if (vote->validator_id >= state->validator_count) {
            continue;
        }
        LanternAggregatedAttestation attestation;
        lantern_aggregated_attestation_init(&attestation);
        attestation.data = vote->data;
        size_t validator_id = (size_t)vote->validator_id;
        if (lantern_bitlist_resize(&attestation.aggregation_bits, validator_id + 1u) != 0
            || lantern_bitlist_set(&attestation.aggregation_bits, validator_id, true) != 0
            || lantern_aggregated_attestations_append(&aggregated, &attestation) != 0) {
            rc = -1;
        }
        lantern_aggregated_attestation_reset(&attestation);
        if (rc != 0) {
            break;
        }
    }
    if (rc == 0) {
        rc = lantern_state_process_attestations(state, &aggregated);
    }
    lantern_aggregated_attestations_reset(&aggregated);
    return rc;
}
