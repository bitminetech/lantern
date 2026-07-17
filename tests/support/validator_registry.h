#ifndef LANTERN_TESTS_VALIDATOR_REGISTRY_H
#define LANTERN_TESTS_VALIDATOR_REGISTRY_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "lantern/consensus/state.h"

static inline int lantern_test_state_set_validator_pubkeys_dual(
    LanternState *state,
    const uint8_t *attestation_pubkeys,
    const uint8_t *proposal_pubkeys,
    size_t count) {
    if (!state || count > LANTERN_VALIDATOR_REGISTRY_LIMIT
        || count != state->validator_count
        || (count > 0u && (!state->validators || !attestation_pubkeys || !proposal_pubkeys))) {
        return -1;
    }
    for (size_t i = 0; i < count; ++i) {
        memcpy(
            state->validators[i].attestation_pubkey,
            attestation_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
        memcpy(
            state->validators[i].proposal_pubkey,
            proposal_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            LANTERN_VALIDATOR_PUBKEY_SIZE);
    }
    return 0;
}

static inline int lantern_test_state_set_validator_pubkeys(
    LanternState *state,
    const uint8_t *pubkeys,
    size_t count) {
    return lantern_test_state_set_validator_pubkeys_dual(state, pubkeys, pubkeys, count);
}

#endif /* LANTERN_TESTS_VALIDATOR_REGISTRY_H */
