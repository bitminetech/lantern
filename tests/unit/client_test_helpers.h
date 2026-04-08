#ifndef LANTERN_TESTS_CLIENT_TEST_HELPERS_H
#define LANTERN_TESTS_CLIENT_TEST_HELPERS_H

#include <stdbool.h>
#include <stdint.h>

#include "lantern/core/client.h"

#ifdef __cplusplus
extern "C" {
#endif

void client_test_fill_root(LanternRoot *root, uint8_t seed);
void client_test_fill_root_with_index(LanternRoot *root, uint32_t index);

int client_test_slot_for_root(struct lantern_client *client, const LanternRoot *root, uint64_t *out_slot);
bool client_test_pending_contains_root(const struct lantern_client *client, const LanternRoot *root);

int client_test_setup_vote_validation_client(
    struct lantern_client *client,
    const char *node_id,
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret,
    LanternRoot *anchor_root,
    LanternRoot *child_root);
int client_test_setup_vote_validation_client_with_validator_count(
    struct lantern_client *client,
    const char *node_id,
    size_t validator_count,
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret,
    LanternRoot *anchor_root,
    LanternRoot *child_root);
void client_test_teardown_vote_validation_client(
    struct lantern_client *client,
    struct PQSignatureSchemePublicKey *pub,
    struct PQSignatureSchemeSecretKey *secret);
int client_test_sign_vote_with_secret(LanternSignedVote *vote, struct PQSignatureSchemeSecretKey *secret);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_TESTS_CLIENT_TEST_HELPERS_H */
