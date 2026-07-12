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
int client_test_set_connected_peer(struct lantern_client *client, const char *peer_id_text);
void client_test_clear_connected_peers(struct lantern_client *client);

int client_test_slot_for_root(struct lantern_client *client, const LanternRoot *root, uint64_t *out_slot);
bool client_test_pending_contains_root(const struct lantern_client *client, const LanternRoot *root);
int client_test_add_known_block(
    struct lantern_client *client,
    uint64_t slot,
    const LanternRoot *parent_root,
    uint8_t state_seed,
    LanternRoot *out_root);

int client_test_load_precomputed_keypair(
    size_t validator_index,
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret);
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

int client_test_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_id_text);
int client_test_gossip_block(struct lantern_client *client, const LanternSignedBlock *block);
int client_test_gossip_vote(struct lantern_client *client, const LanternSignedVote *vote);
int client_test_gossip_vote_from(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const struct lantern_peer_id *from);
int client_test_gossip_aggregated_attestation(
    struct lantern_client *client,
    const LanternSignedAggregatedAttestation *attestation);
int client_test_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *peer_id_text);
size_t client_test_pending_block_count(const struct lantern_client *client);
size_t client_test_pending_vote_count(const struct lantern_client *client);
int client_test_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_id_text);
int client_test_pending_entry(
    const struct lantern_client *client,
    size_t index,
    LanternRoot *out_root,
    LanternRoot *out_parent_root,
    bool *out_parent_requested,
    char *out_peer_text,
    size_t peer_text_len);
void client_test_pending_reset(struct lantern_client *client);
int client_test_set_parent_requested(
    struct lantern_client *client,
    const LanternRoot *root,
    bool requested);
int client_test_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    int outcome_code);
lantern_client_error client_test_aggregate_attestation_signatures(
    struct lantern_client *client,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);
int client_test_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot);
int client_test_run_interval_aggregation(struct lantern_client *client, uint64_t slot);

#define LANTERN_TEST_BLOCKS_REQUEST_SUCCESS 0
#define LANTERN_TEST_BLOCKS_REQUEST_FAILED 1
#define LANTERN_TEST_BLOCKS_REQUEST_ABORTED 2
#define lantern_client_debug_record_vote client_test_record_vote
#define lantern_client_debug_gossip_block client_test_gossip_block
#define lantern_client_debug_gossip_vote client_test_gossip_vote
#define lantern_client_debug_gossip_aggregated_attestation client_test_gossip_aggregated_attestation
#define lantern_client_debug_import_block client_test_import_block
#define lantern_client_pending_block_count client_test_pending_block_count
#define lantern_client_pending_vote_count client_test_pending_vote_count
#define lantern_client_debug_enqueue_pending_block client_test_enqueue_pending_block
#define lantern_client_debug_pending_entry client_test_pending_entry
#define lantern_client_debug_pending_reset client_test_pending_reset
#define lantern_client_debug_set_parent_requested client_test_set_parent_requested
#define lantern_client_debug_on_blocks_request_complete client_test_on_blocks_request_complete
#define lantern_client_debug_aggregate_attestation_signatures client_test_aggregate_attestation_signatures
#define lantern_client_debug_publish_aggregated_attestations client_test_publish_aggregated_attestations
#define lantern_client_debug_run_interval_aggregation client_test_run_interval_aggregation

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_TESTS_CLIENT_TEST_HELPERS_H */
