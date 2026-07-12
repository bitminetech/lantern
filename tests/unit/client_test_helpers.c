#include "client_test_helpers.h"

#include "../../src/core/client_internal.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/duties.h"
#include "lantern/consensus/signature.h"
#include "lantern/crypto/xmss.h"
#include "lantern/support/time.h"
#include "lantern/support/strings.h"

static int client_test_load_fixture_genesis_time(uint64_t *out_time);

int client_test_set_connected_peer(struct lantern_client *client, const char *peer_id_text) {
    if (!client || !peer_id_text) {
        return -1;
    }
    struct lantern_peer_id peer;
    if (lantern_peer_id_from_text(peer_id_text, &peer) != 0) {
        return -1;
    }
    struct lantern_connection_peer_ref *ref = calloc(1u, sizeof(*ref));
    if (!ref) {
        return -1;
    }
    free(client->connection_peer_refs);
    ref->conn = client;
    ref->peer = peer;
    client->connection_peer_refs = ref;
    client->connection_peer_ref_count = 1u;
    client->connection_peer_ref_capacity = 1u;
    client->connected_peers = 1u;
    return 0;
}

void client_test_clear_connected_peers(struct lantern_client *client) {
    if (!client) {
        return;
    }
    free(client->connection_peer_refs);
    client->connection_peer_refs = NULL;
    client->connection_peer_ref_count = 0u;
    client->connection_peer_ref_capacity = 0u;
    client->connected_peers = 0u;
}

lantern_client_error validator_collect_and_aggregate_attestation_signatures(
    struct lantern_client *client,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures,
    const uint64_t *scope_slot,
    struct lantern_block_build_stage_timings *stage_timings,
    bool *out_missing_state);
int validator_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot);

int client_test_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_id_text) {
    if (!client || !vote) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    lantern_client_record_vote(client, vote, peer_id_text);
    return LANTERN_CLIENT_OK;
}

int client_test_gossip_block(struct lantern_client *client, const LanternSignedBlock *block) {
    return client && block
        ? gossip_block_handler(block, NULL, NULL, 0, client)
        : LANTERN_CLIENT_ERR_INVALID_PARAM;
}

int client_test_gossip_vote(struct lantern_client *client, const LanternSignedVote *vote) {
    return client && vote
        ? gossip_vote_handler(vote, NULL, NULL, 0, client)
        : LANTERN_CLIENT_ERR_INVALID_PARAM;
}

int client_test_gossip_vote_from(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const struct lantern_peer_id *from) {
    return client && vote && from
        ? gossip_vote_handler(vote, from, NULL, 0, client)
        : LANTERN_CLIENT_ERR_INVALID_PARAM;
}

int client_test_gossip_aggregated_attestation(
    struct lantern_client *client,
    const LanternSignedAggregatedAttestation *attestation) {
    return client && attestation
        ? gossip_aggregated_attestation_handler(attestation, NULL, NULL, 0, client)
        : LANTERN_CLIENT_ERR_INVALID_PARAM;
}

int client_test_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *peer_id_text) {
    if (!client || !block || !block_root) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    return lantern_client_import_block(
               client,
               block,
               block_root,
               &(const struct lantern_log_metadata){
                   .validator = client->node_id,
                   .peer = peer_id_text},
               0,
               true,
               NULL,
               0)
        ? 1
        : 0;
}

size_t client_test_pending_block_count(const struct lantern_client *client) {
    if (!client) {
        return 0;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    size_t count = client->pending_blocks.length;
    lantern_client_unlock_pending(mutable_client, locked);
    return count;
}

size_t client_test_pending_vote_count(const struct lantern_client *client) {
    if (!client) {
        return 0;
    }
    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_state(mutable_client);
    size_t count = client->pending_gossip_votes.length;
    lantern_client_unlock_state(mutable_client, locked);
    return count;
}

int client_test_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_id_text) {
    if (!client || !block || !block_root || !parent_root) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    lantern_client_enqueue_pending_block(
        client,
        block,
        block_root,
        parent_root,
        peer_id_text,
        0,
        false);
    return LANTERN_CLIENT_OK;
}

int client_test_pending_entry(
    const struct lantern_client *client,
    size_t index,
    LanternRoot *out_root,
    LanternRoot *out_parent_root,
    bool *out_parent_requested,
    char *out_peer_text,
    size_t peer_text_len) {
    if (!client || (out_peer_text && peer_text_len == 0)) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_client *mutable_client = (struct lantern_client *)client;
    bool locked = lantern_client_lock_pending(mutable_client);
    if (index >= client->pending_blocks.length) {
        lantern_client_unlock_pending(mutable_client, locked);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    const struct lantern_pending_block *entry = &client->pending_blocks.items[index];
    if (out_root) {
        *out_root = entry->root;
    }
    if (out_parent_root) {
        *out_parent_root = entry->parent_root;
    }
    if (out_parent_requested) {
        *out_parent_requested = entry->parent_requested;
    }
    if (out_peer_text) {
        (void)lantern_string_copy(out_peer_text, peer_text_len, entry->peer_text);
    }
    lantern_client_unlock_pending(mutable_client, locked);
    return LANTERN_CLIENT_OK;
}

void client_test_pending_reset(struct lantern_client *client) {
    if (client) {
        bool locked = lantern_client_lock_pending(client);
        pending_block_list_reset(&client->pending_blocks);
        lantern_client_unlock_pending(client, locked);
    }
}

int client_test_set_parent_requested(
    struct lantern_client *client,
    const LanternRoot *root,
    bool requested) {
    if (!client || !root) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    bool locked = lantern_client_lock_pending(client);
    struct lantern_pending_block *entry = pending_block_list_find(&client->pending_blocks, root);
    if (entry) {
        entry->parent_requested = requested;
    }
    lantern_client_unlock_pending(client, locked);
    return entry ? LANTERN_CLIENT_OK : LANTERN_CLIENT_ERR_INVALID_PARAM;
}

int client_test_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    int outcome_code) {
    if (!client || !peer_id || peer_id[0] == '\0' || !request_root
        || outcome_code < LANTERN_TEST_BLOCKS_REQUEST_SUCCESS
        || outcome_code > LANTERN_TEST_BLOCKS_REQUEST_ABORTED) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    lantern_client_on_blocks_request_complete(
        client,
        peer_id,
        request_root,
        (enum lantern_blocks_request_outcome)outcome_code);
    return LANTERN_CLIENT_OK;
}

lantern_client_error client_test_aggregate_attestation_signatures(
    struct lantern_client *client,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures) {
    return validator_collect_and_aggregate_attestation_signatures(
        client,
        out_attestations,
        out_signatures,
        NULL,
        NULL,
        NULL);
}

int client_test_publish_aggregated_attestations(struct lantern_client *client, uint64_t slot) {
    return validator_publish_aggregated_attestations(client, slot);
}

int client_test_run_interval_aggregation(struct lantern_client *client, uint64_t slot) {
    if (!client) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->validator_duty.slot_aggregated || !client->validator_duty.slot_attested) {
        return LANTERN_CLIENT_ERR_IGNORED;
    }
    int rc = validator_publish_aggregated_attestations(client, slot);
    if (rc == LANTERN_CLIENT_OK) {
        client->validator_duty.slot_aggregated = true;
    }
    return rc;
}

int client_test_load_precomputed_keypair(
    size_t validator_index,
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret) {
    if (!out_pub || !out_secret) {
        return -1;
    }
    char pk_path[PATH_MAX];
    char sk_path[PATH_MAX];
    int pk_written = snprintf(
        pk_path,
        sizeof(pk_path),
        "%s/genesis/xmss-keys/validator_%zu_pk.json",
        LANTERN_TEST_FIXTURE_DIR,
        validator_index);
    if (pk_written <= 0 || (size_t)pk_written >= sizeof(pk_path)) {
        return -1;
    }
    int sk_written = snprintf(
        sk_path,
        sizeof(sk_path),
        "%s/genesis/xmss-keys/validator_%zu_sk.json",
        LANTERN_TEST_FIXTURE_DIR,
        validator_index);
    if (sk_written <= 0 || (size_t)sk_written >= sizeof(sk_path)) {
        return -1;
    }

    if (lantern_xmss_load_public_file(pk_path, out_pub) != 0 || !*out_pub) {
        fprintf(stderr, "failed to load precomputed public key from %s\n", pk_path);
        return -1;
    }
    if (lantern_xmss_load_secret_file(sk_path, out_secret) != 0 || !*out_secret) {
        fprintf(stderr, "failed to load precomputed secret key from %s\n", sk_path);
        pq_public_key_free(*out_pub);
        *out_pub = NULL;
        return -1;
    }
    return 0;
}

void client_test_fill_root(LanternRoot *root, uint8_t seed) {
    if (!root) {
        return;
    }
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        root->bytes[i] = (uint8_t)(seed + (uint8_t)i);
    }
}

void client_test_fill_root_with_index(LanternRoot *root, uint32_t index) {
    if (!root) {
        return;
    }
    memset(root->bytes, 0, sizeof(root->bytes));
    for (size_t i = 0; i < sizeof(index) && i < LANTERN_ROOT_SIZE; ++i) {
        root->bytes[i] = (uint8_t)((index >> (8u * i)) & 0xFFu);
    }
    for (size_t i = sizeof(index); i < LANTERN_ROOT_SIZE; ++i) {
        root->bytes[i] = (uint8_t)((index + i) & 0xFFu);
    }
}

int client_test_slot_for_root(struct lantern_client *client, const LanternRoot *root, uint64_t *out_slot) {
    if (!client || !root || !out_slot || !client->has_fork_choice) {
        return -1;
    }
    if (lantern_fork_choice_block_info(&client->fork_choice, root, out_slot, NULL, NULL) != 0) {
        return -1;
    }
    return 0;
}

bool client_test_pending_contains_root(const struct lantern_client *client, const LanternRoot *root) {
    if (!client || !root) {
        return false;
    }
    size_t count = lantern_client_pending_block_count(client);
    for (size_t i = 0; i < count; ++i) {
        LanternRoot candidate;
        if (lantern_client_debug_pending_entry(client, i, &candidate, NULL, NULL, NULL, 0) != 0) {
            continue;
        }
        if (memcmp(candidate.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return true;
        }
    }
    return false;
}

int client_test_add_known_block(
    struct lantern_client *client,
    uint64_t slot,
    const LanternRoot *parent_root,
    uint8_t state_seed,
    LanternRoot *out_root)
{
    if (!client || !parent_root || !out_root || !client->has_fork_choice) {
        return -1;
    }

    LanternBlock block;
    memset(&block, 0, sizeof(block));
    lantern_block_body_init(&block.body);
    block.slot = slot;
    if (lantern_proposer_for_slot(block.slot, client->state.config.num_validators, &block.proposer_index) != 0) {
        lantern_block_body_reset(&block.body);
        return -1;
    }
    block.parent_root = *parent_root;
    client_test_fill_root(&block.state_root, state_seed);

    LanternRoot block_root;
    if (lantern_hash_tree_root_block(&block, &block_root) != SSZ_SUCCESS) {
        lantern_block_body_reset(&block.body);
        return -1;
    }
    if (lantern_fork_choice_add_block(
            &client->fork_choice,
            &block,
            &client->state.latest_justified,
            &client->state.latest_finalized,
            &block_root)
        != 0) {
        lantern_block_body_reset(&block.body);
        return -1;
    }

    *out_root = block_root;
    lantern_block_body_reset(&block.body);
    return 0;
}

static void reset_vote_client_on_error(struct lantern_client *client) {
    free(client->pending_gossip_votes.items);
    client->pending_gossip_votes.items = NULL;
    client->pending_gossip_votes.length = 0;
    client->pending_gossip_votes.capacity = 0;
    if (client->has_fork_choice) {
        lantern_fork_choice_reset(&client->fork_choice);
        client->has_fork_choice = false;
    }
    lantern_store_reset(&client->store);
    if (client->has_state) {
        lantern_state_reset(&client->state);
        client->has_state = false;
    }
    if (client->state_lock_initialized) {
        pthread_mutex_destroy(&client->state_lock);
        client->state_lock_initialized = false;
    }
}

static int client_test_setup_vote_validation_client_common(
    struct lantern_client *client,
    const char *node_id,
    size_t validator_count,
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret,
    LanternRoot *anchor_root,
    LanternRoot *child_root) {
    if (!client || !out_pub || !out_secret) {
        return -1;
    }
    if (validator_count == 0) {
        validator_count = 1;
    }
    int rc = -1;
    struct PQSignatureSchemePublicKey *pub = NULL;
    struct PQSignatureSchemeSecretKey *secret = NULL;
    uint8_t *serialized_pubkeys = NULL;
    LanternBlock anchor;
    LanternBlock child;
    LanternSignedBlock child_signed;
    bool anchor_body_init = false;
    bool child_body_init = false;
    LanternRoot anchor_root_local;
    LanternRoot child_root_local;
    memset(&anchor_root_local, 0, sizeof(anchor_root_local));
    memset(&child_root_local, 0, sizeof(child_root_local));
    memset(&child_signed, 0, sizeof(child_signed));

    memset(client, 0, sizeof(*client));
    client->node_id = (char *)node_id;
    client->debug_disable_fork_choice_time = true;
    lantern_store_init(&client->store);
    lantern_state_init(&client->state);
    lantern_fork_choice_init(&client->fork_choice);
    lantern_store_attach_fork_choice(&client->store, &client->fork_choice);

    if (pthread_mutex_init(&client->state_lock, NULL) != 0) {
        fprintf(stderr, "failed to initialize state mutex for vote test\n");
        return -1;
    }
    client->state_lock_initialized = true;

    uint64_t genesis_time = 0;
    if (client_test_load_fixture_genesis_time(&genesis_time) != 0) {
        double now_seconds = lantern_time_now_seconds();
        if (now_seconds < 0.0) {
            now_seconds = 0.0;
        }
        double shifted = now_seconds >= 60.0 ? now_seconds - 60.0 : 0.0;
        genesis_time = (uint64_t)shifted;
    }

    if (lantern_state_generate_genesis(&client->state, genesis_time, (uint64_t)validator_count) != 0) {
        fprintf(stderr, "failed to generate genesis for vote test\n");
        goto finish;
    }
    client->has_state = true;

    if (lantern_store_prepare_validator_votes(&client->store, (uint64_t)validator_count) != 0) {
        fprintf(stderr, "failed to prepare store caches for vote test\n");
        goto finish;
    }

    if (lantern_fork_choice_configure(&client->fork_choice, &client->state.config) != 0) {
        fprintf(stderr, "failed to configure fork choice for vote test\n");
        goto finish;
    }

    if (client_test_load_precomputed_keypair(0u, &pub, &secret) != 0) {
        goto finish;
    }

    uint8_t serialized_pub[LANTERN_VALIDATOR_PUBKEY_SIZE];
    uintptr_t written = 0;
    enum PQSigningError serialize_err =
        pq_public_key_serialize(pub, serialized_pub, sizeof(serialized_pub), &written);
    if (serialize_err != Success || written == 0 || written > sizeof(serialized_pub)) {
        fprintf(
            stderr,
            "failed to serialize pubkey for vote test (%d) needed=%zu\n",
            (int)serialize_err,
            (size_t)written);
        goto finish;
    }
    if (written < sizeof(serialized_pub)) {
        memset(serialized_pub + written, 0, sizeof(serialized_pub) - written);
    }

    if (validator_count > (SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)) {
        fprintf(stderr, "validator count too large for pubkey array\n");
        goto finish;
    }
    size_t total_pubkeys_len = validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    serialized_pubkeys = calloc(total_pubkeys_len, 1u);
    if (!serialized_pubkeys) {
        fprintf(stderr, "failed to allocate validator pubkey array for vote test\n");
        goto finish;
    }
    for (size_t i = 0; i < validator_count; ++i) {
        memcpy(
            serialized_pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
            serialized_pub,
            LANTERN_VALIDATOR_PUBKEY_SIZE);
    }

    if (lantern_state_set_validator_pubkeys_dual(
            &client->state,
            serialized_pubkeys,
            serialized_pubkeys,
            validator_count)
        != 0) {
        fprintf(stderr, "failed to set dual validator pubkeys for vote test\n");
        goto finish;
    }
    const uint8_t *stored_pub = lantern_state_validator_attestation_pubkey(&client->state, 0);
    if (!stored_pub) {
        fprintf(stderr, "stored validator attestation pubkey missing after load\n");
        goto finish;
    }
    if (memcmp(stored_pub, serialized_pub, LANTERN_VALIDATOR_PUBKEY_SIZE) != 0) {
        fprintf(stderr, "stored validator attestation pubkey mismatch after load\n");
        goto finish;
    }

    LanternRoot anchor_state_root;
    if (lantern_hash_tree_root_state(&client->state, &anchor_state_root) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash anchor state for vote test\n");
        goto finish;
    }
    client->state.latest_block_header.state_root = anchor_state_root;

    memset(&anchor, 0, sizeof(anchor));
    lantern_block_body_init(&anchor.body);
    anchor_body_init = true;
    anchor.slot = 0;
    if (lantern_proposer_for_slot(anchor.slot, client->state.config.num_validators, &anchor.proposer_index) != 0) {
        fprintf(stderr, "failed to compute anchor proposer for vote test\n");
        goto finish;
    }
    anchor.parent_root = client->state.latest_block_header.parent_root;
    anchor.state_root = anchor_state_root;

    if (lantern_hash_tree_root_block(&anchor, &anchor_root_local) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash anchor block for vote test\n");
        goto finish;
    }
    client->state.latest_justified.root = anchor_root_local;
    client->state.latest_justified.slot = anchor.slot;
    client->state.latest_finalized = client->state.latest_justified;
    if (lantern_state_mark_justified_slot(&client->state, anchor.slot) != 0) {
        fprintf(stderr, "failed to seed justified slot window for vote test\n");
        goto finish;
    }

    if (lantern_fork_choice_set_anchor(
            &client->fork_choice,
            &anchor,
            &client->state.latest_justified,
            &client->state.latest_finalized,
            &anchor_root_local)
        != 0) {
        fprintf(stderr, "failed to set anchor for vote test\n");
        goto finish;
    }

    memset(&child, 0, sizeof(child));
    lantern_block_body_init(&child.body);
    child_body_init = true;
    child.slot = anchor.slot + 1u;
    if (lantern_proposer_for_slot(child.slot, client->state.config.num_validators, &child.proposer_index) != 0) {
        fprintf(stderr, "failed to compute child proposer for vote test\n");
        goto finish;
    }
    child.parent_root = anchor_root_local;
    child_signed.block = child;

    if (lantern_state_preview_post_state_root(
            &client->state,
            &client->store,
            &child_signed,
            &child.state_root)
        != 0) {
        fprintf(stderr, "failed to preview child post-state root for vote test\n");
        goto finish;
    }
    child_signed.block = child;

    if (lantern_hash_tree_root_block(&child, &child_root_local) != SSZ_SUCCESS) {
        fprintf(stderr, "failed to hash child block for vote test\n");
        goto finish;
    }

    if (lantern_fork_choice_add_block(
            &client->fork_choice,
            &child,
            &client->state.latest_justified,
            &client->state.latest_finalized,
            &child_root_local)
        != 0) {
        fprintf(stderr, "failed to add child block for vote test\n");
        goto finish;
    }
    client->has_fork_choice = true;

    if (lantern_state_process_slots(&client->state, child.slot) != 0) {
        fprintf(stderr, "failed to advance state slot for vote test child block\n");
        goto finish;
    }
    if (lantern_state_process_block(&client->state, &client->store, &child) != 0) {
        fprintf(stderr, "failed to process child block into vote test state\n");
        goto finish;
    }
    if (anchor_root) {
        *anchor_root = anchor_root_local;
    }
    if (child_root) {
        *child_root = child_root_local;
    }
    *out_pub = pub;
    *out_secret = secret;
    rc = 0;

finish:
    if (anchor_body_init) {
        lantern_block_body_reset(&anchor.body);
    }
    if (child_body_init) {
        lantern_block_body_reset(&child.body);
    }
    if (rc != 0) {
        if (secret) {
            pq_secret_key_free(secret);
            secret = NULL;
        }
        if (pub) {
            pq_public_key_free(pub);
            pub = NULL;
        }
        reset_vote_client_on_error(client);
    }
    free(serialized_pubkeys);
    return rc;
}

int client_test_setup_vote_validation_client(
    struct lantern_client *client,
    const char *node_id,
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret,
    LanternRoot *anchor_root,
    LanternRoot *child_root) {
    return client_test_setup_vote_validation_client_common(
        client,
        node_id,
        1u,
        out_pub,
        out_secret,
        anchor_root,
        child_root);
}

int client_test_setup_vote_validation_client_with_validator_count(
    struct lantern_client *client,
    const char *node_id,
    size_t validator_count,
    struct PQSignatureSchemePublicKey **out_pub,
    struct PQSignatureSchemeSecretKey **out_secret,
    LanternRoot *anchor_root,
    LanternRoot *child_root) {
    return client_test_setup_vote_validation_client_common(
        client,
        node_id,
        validator_count,
        out_pub,
        out_secret,
        anchor_root,
        child_root);
}

void client_test_teardown_vote_validation_client(
    struct lantern_client *client,
    struct PQSignatureSchemePublicKey *pub,
    struct PQSignatureSchemeSecretKey *secret) {
    if (secret) {
        pq_secret_key_free(secret);
    }
    if (pub) {
        pq_public_key_free(pub);
    }
    reset_vote_client_on_error(client);
}

static int client_test_load_fixture_genesis_time(uint64_t *out_time) {
    if (!out_time) {
        return -1;
    }
    char config_path[PATH_MAX];
    int written = snprintf(
        config_path,
        sizeof(config_path),
        "%s/genesis/config.yaml",
        LANTERN_TEST_FIXTURE_DIR);
    if (written <= 0 || (size_t)written >= sizeof(config_path)) {
        return -1;
    }
    FILE *fp = fopen(config_path, "r");
    if (!fp) {
        return -1;
    }
    char line[256];
    const char *needle = "GENESIS_TIME";
    while (fgets(line, sizeof(line), fp)) {
        if (strstr(line, needle) == NULL) {
            continue;
        }
        char *colon = strchr(line, ':');
        if (!colon) {
            continue;
        }
        colon += 1;
        while (*colon && isspace((unsigned char)*colon)) {
            colon++;
        }
        if (!*colon) {
            continue;
        }
        errno = 0;
        char *endptr = NULL;
        unsigned long long value = strtoull(colon, &endptr, 10);
        if (errno == 0 && endptr && endptr != colon) {
            *out_time = (uint64_t)value;
            fclose(fp);
            return 0;
        }
    }
    fclose(fp);
    return -1;
}

int client_test_sign_vote_with_secret(LanternSignedVote *vote, struct PQSignatureSchemeSecretKey *secret) {
    if (!vote || !secret) {
        return -1;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data.data, &vote_root) != SSZ_SUCCESS) {
        return -1;
    }
    if (!lantern_signature_sign(secret, vote->data.slot, &vote_root, &vote->signature)) {
        return -1;
    }
    return 0;
}
