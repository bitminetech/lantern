/**
 * @file client_validator.c
 * @brief Validator service and duty management
 *
 * Implements the validator service thread, block proposal,
 * attestation publishing, and vote signing.
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#include "client_services_internal.h"

#include <inttypes.h>
#include <pthread.h>
#include <string.h>

#include "client_internal.h"

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/runtime.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/networking/gossipsub_service.h"
#include "lantern/support/log.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

/** Sleep interval when validator service cannot run (ms). */
static const uint32_t VALIDATOR_SERVICE_IDLE_SLEEP_MS = 200;

/** Sleep interval between validator service iterations (ms). */
static const uint32_t VALIDATOR_SERVICE_POLL_SLEEP_MS = 50;


/* ============================================================================
 * Mutex Utilities
 * ============================================================================ */

/**
 * @brief Unlock a mutex and log on failure.
 *
 * @note Thread safety: This function is thread-safe
 */
static void unlock_mutex_with_log(
    pthread_mutex_t *mutex,
    const char *validator_id,
    const char *name)
{
    if (!mutex || !name)
    {
        return;
    }
    int unlock_rc = pthread_mutex_unlock(mutex);
    if (unlock_rc != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = validator_id},
            "failed to unlock %s: %d",
            name,
            unlock_rc);
    }
}


/* ============================================================================
 * Validator Duty State
 * ============================================================================ */

/**
 * Reset validator duty state.
 *
 * @param state  Duty state to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void validator_duty_state_reset(struct lantern_validator_duty_state *state)
{
    if (!state)
    {
        return;
    }
    memset(state, 0, sizeof(*state));
}


/* ============================================================================
 * Vote Time Utilities
 * ============================================================================ */

/**
 * Compute wall-clock time for a vote slot.
 *
 * Calculates the Unix timestamp (in seconds) at which the given vote slot
 * begins, based on genesis time and seconds per slot configuration.
 *
 * @param client       Client instance (must have fork_choice initialized)
 * @param vote_slot    Slot number to compute time for
 * @param out_seconds  Output for computed time in seconds (Unix timestamp)
 *
 * @return true on success
 * @return false if client is NULL, fork_choice not initialized, out_seconds
 *         is NULL, or computed time overflows uint64_t
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_vote_time_seconds(
    const struct lantern_client *client,
    uint64_t vote_slot,
    uint64_t *out_seconds)
{
    if (!client || !client->has_fork_choice || !out_seconds)
    {
        return false;
    }
    uint32_t seconds_per_slot = client->fork_choice.seconds_per_slot;
    if (seconds_per_slot == 0)
    {
        seconds_per_slot = 1;
    }
    uint64_t slot_for_time = vote_slot;
    if (slot_for_time != UINT64_MAX)
    {
        slot_for_time += 1u;
    }

#if defined(__SIZEOF_INT128__)
    __uint128_t slot_offset = (__uint128_t)slot_for_time * (uint64_t)seconds_per_slot;
    __uint128_t result = slot_offset + (__uint128_t)client->fork_choice.config.genesis_time;
    if (result > UINT64_MAX)
    {
        return false;
    }
    *out_seconds = (uint64_t)result;
#else
    /* Fallback for platforms without 128-bit integers */
    uint64_t genesis_time = client->fork_choice.config.genesis_time;
    /* Check for overflow in multiplication */
    if (seconds_per_slot != 0 && slot_for_time > UINT64_MAX / seconds_per_slot)
    {
        return false;
    }
    uint64_t slot_offset = slot_for_time * (uint64_t)seconds_per_slot;
    /* Check for overflow in addition */
    if (slot_offset > UINT64_MAX - genesis_time)
    {
        return false;
    }
    *out_seconds = slot_offset + genesis_time;
#endif
    return true;
}


/* ============================================================================
 * Validator Service Checks
 * ============================================================================ */

/**
 * Check if the validator service should run.
 *
 * @param client  Client instance
 * @return true if service should run, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool validator_service_should_run(const struct lantern_client *client)
{
    if (!client)
    {
        return false;
    }
    if (!client->has_state || !client->has_runtime || !client->has_fork_choice)
    {
        return false;
    }
    if (!client->gossip_running || client->local_validator_count == 0)
    {
        return false;
    }
    return true;
}


/**
 * Check if a validator is enabled.
 *
 * @param client       Client instance
 * @param local_index  Local validator index
 * @return true if enabled, false otherwise
 *
 * @note Thread safety: This function acquires validator_lock
 */
bool validator_is_enabled(const struct lantern_client *client, size_t local_index)
{
    if (!client || local_index >= client->local_validator_count)
    {
        return false;
    }
    if (!client->validator_enabled)
    {
        return true;
    }
    if (!client->validator_lock_initialized)
    {
        return client->validator_enabled[local_index];
    }
    pthread_mutex_t *lock = (pthread_mutex_t *)&client->validator_lock;
    if (pthread_mutex_lock(lock) != 0)
    {
        return client->validator_enabled[local_index];
    }
    bool enabled = client->validator_enabled[local_index];
    unlock_mutex_with_log(lock, client->node_id, "validator_lock");
    return enabled;
}


/**
 * Get the global index for a local validator.
 *
 * @param client       Client instance
 * @param local_index  Local validator index
 * @return Global index, or UINT64_MAX on error
 *
 * @note Thread safety: This function is thread-safe
 */
uint64_t validator_global_index(const struct lantern_client *client, size_t local_index)
{
    if (!client || !client->local_validators || local_index >= client->local_validator_count)
    {
        return UINT64_MAX;
    }
    return client->local_validators[local_index].global_index;
}


/* ============================================================================
 * Vote Signing and Storage
 * ============================================================================ */

/**
 * Sign a vote with a validator's secret key.
 *
 * @param validator  Local validator
 * @param slot       Slot number
 * @param vote       Vote to sign (modified in place)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_VALIDATOR on hashing or signing failure
 *
 * @note Thread safety: This function is thread-safe
 */
int validator_sign_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    LanternSignedVote *vote)
{
    if (!validator || !vote || !validator->secret_key)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_vote(&vote->data, &vote_root) != 0)
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }
    if (!lantern_signature_sign(
            validator->secret_key,
            slot,
            vote_root.bytes,
            sizeof(vote_root.bytes),
            &vote->signature))
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }
    return LANTERN_CLIENT_OK;
}


/**
 * @brief Collect parent root, checkpoints, and attestations for a new block.
 *
 * Computes the parent root and vote checkpoints from state, signs the
 * proposer's vote, and collects attestations/signatures to include in the
 * proposed block.
 *
 * @param client            Client instance
 * @param slot              Slot number
 * @param local             Local validator
 * @param out_parent_root   Output for selected parent root
 * @param out_proposer_vote Output for the proposer's signed vote
 * @param att_list          Initialized attestation list to populate
 * @param att_signatures    Initialized signature list to populate
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_RUNTIME on lock/state errors
 * @return Propagated error codes from validator_sign_vote()
 *
 * @note Thread safety: This function acquires state_lock
 */
static lantern_client_error validator_build_block_collect_attestations(
    struct lantern_client *client,
    uint64_t slot,
    struct lantern_local_validator *local,
    LanternRoot *out_parent_root,
    LanternSignedVote *out_proposer_vote,
    LanternAttestations *att_list,
    LanternBlockSignatures *att_signatures)
{
    lantern_client_error result = LANTERN_CLIENT_OK;

    if (!client || !local || !out_parent_root || !out_proposer_vote || !att_list || !att_signatures)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    if (!client->has_state)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }

    if (lantern_state_select_block_parent(&client->state, out_parent_root) != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }

    LanternCheckpoint head_cp;
    LanternCheckpoint target_cp;
    LanternCheckpoint source_cp;
    if (lantern_state_compute_vote_checkpoints(
            &client->state,
            &head_cp,
            &target_cp,
            &source_cp)
        != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }

    out_proposer_vote->data.validator_id = local->global_index;
    out_proposer_vote->data.slot = slot;
    out_proposer_vote->data.head = head_cp;
    out_proposer_vote->data.target = target_cp;
    out_proposer_vote->data.source = source_cp;

    result = (lantern_client_error)validator_sign_vote(local, slot, out_proposer_vote);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    if (lantern_state_collect_attestations_for_block(
            &client->state,
            slot,
            local->global_index,
            out_parent_root,
            out_proposer_vote,
            att_list,
            att_signatures)
        != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
        goto cleanup;
    }

cleanup:
    lantern_client_unlock_state(client, state_locked);
    return result;
}


/**
 * @brief Populate a signed block from collected attestations and signatures.
 *
 * Initializes the block message fields, copies attestations into the body,
 * and fills the signatures array with attestation signatures followed by the
 * proposer signature.
 *
 * @param slot           Slot number
 * @param proposer_index Proposer's global validator index
 * @param parent_root    Parent block root
 * @param proposer_vote  Proposer's signed vote
 * @param att_list       Collected attestations
 * @param att_signatures Collected attestation signatures
 * @param out_block      Block to populate
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_RUNTIME on overflow or inconsistent inputs
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation/copy failures
 *
 * @note Thread safety: This function is thread-safe
 */
static lantern_client_error validator_build_block_populate_message(
    uint64_t slot,
    uint64_t proposer_index,
    const LanternRoot *parent_root,
    const LanternSignedVote *proposer_vote,
    const LanternAttestations *att_list,
    const LanternBlockSignatures *att_signatures,
    LanternSignedBlock *out_block)
{
    if (!parent_root || !proposer_vote || !att_list || !att_signatures || !out_block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternBlock *message_block = &out_block->message.block;
    message_block->slot = slot;
    message_block->proposer_index = proposer_index;
    message_block->parent_root = *parent_root;
    memset(&message_block->state_root, 0, sizeof(message_block->state_root));

    if (lantern_attestations_copy(&message_block->body.attestations, att_list) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    out_block->message.proposer_attestation = proposer_vote->data;

    if (message_block->body.attestations.length > SIZE_MAX - 1u)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    size_t signature_count = message_block->body.attestations.length + 1u;
    if (lantern_block_signatures_resize(&out_block->signatures, signature_count) != 0)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    for (size_t i = 0; i + 1u < signature_count; ++i)
    {
        if (i < att_signatures->length && att_signatures->data)
        {
            out_block->signatures.data[i] = att_signatures->data[i];
        }
        else
        {
            memset(out_block->signatures.data[i].bytes, 0, LANTERN_SIGNATURE_SIZE);
        }
    }
    out_block->signatures.data[signature_count - 1u] = proposer_vote->signature;

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Preview post-state root for a built block.
 *
 * Computes the expected post-state root for the proposed block without
 * mutating state.
 *
 * @param client         Client instance
 * @param block          Built block to preview
 * @param out_state_root Output for the computed post-state root
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_RUNTIME on lock/state failures
 *
 * @note Thread safety: This function acquires state_lock
 */
static lantern_client_error validator_build_block_preview_state_root(
    struct lantern_client *client,
    LanternSignedBlock *block,
    LanternRoot *out_state_root)
{
    if (!client || !block || !out_state_root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    lantern_client_error result = LANTERN_CLIENT_OK;
    if (lantern_state_preview_post_state_root(&client->state, block, out_state_root) != 0)
    {
        result = LANTERN_CLIENT_ERR_RUNTIME;
    }
    lantern_client_unlock_state(client, state_locked);
    return result;
}


/**
 * Refresh a cached vote with updated checkpoints and re-sign if needed.
 *
 * Compares the vote's source checkpoint with the provided source. If they
 * differ, updates all checkpoints (head, target, source) and re-signs the
 * vote using the validator's secret key.
 *
 * @param validator  Local validator with signing key (must have secret_key set)
 * @param slot       Slot for signing context
 * @param head       New head checkpoint
 * @param target     New target checkpoint
 * @param source     New source checkpoint
 * @param vote       Vote to update (modified in place)
 * @param out_refreshed Optional output flag set to true when the vote is
 *        updated and re-signed
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL parameters
 * @return LANTERN_CLIENT_ERR_VALIDATOR when the validator key is missing or
 *         signing fails
 *
 * @note Thread safety: Caller must ensure exclusive access to validator
 */
int lantern_validator_refresh_cached_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    const LanternCheckpoint *head,
    const LanternCheckpoint *target,
    const LanternCheckpoint *source,
    LanternSignedVote *vote,
    bool *out_refreshed)
{
    bool refreshed = false;

    if (out_refreshed)
    {
        *out_refreshed = false;
    }
    if (!validator || !head || !target || !source || !vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (!validator->secret_key)
    {
        return LANTERN_CLIENT_ERR_VALIDATOR;
    }

    /* If the source checkpoint is unchanged, no refresh is required. */
    if (vote->data.source.slot != source->slot
        || memcmp(vote->data.source.root.bytes, source->root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        vote->data.head = *head;
        vote->data.target = *target;
        vote->data.source = *source;

        if (validator_sign_vote(validator, slot, vote) != 0)
        {
            return LANTERN_CLIENT_ERR_VALIDATOR;
        }
        refreshed = true;
    }

    if (out_refreshed)
    {
        *out_refreshed = refreshed;
    }
    return LANTERN_CLIENT_OK;
}


/**
 * Store a vote in the client state.
 *
 * @param client  Client instance
 * @param vote    Vote to store
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL input or index overflow
 * @return LANTERN_CLIENT_ERR_RUNTIME if state is unavailable or lock fails
 *
 * @note Thread safety: This function acquires state_lock
 */
int validator_store_vote(struct lantern_client *client, const LanternSignedVote *vote)
{
    if (!client || !vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (!client->has_state)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (vote->data.validator_id > SIZE_MAX)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    int rc = lantern_state_set_signed_validator_vote(
        &client->state,
        (size_t)vote->data.validator_id,
        vote);
    lantern_client_unlock_state(client, state_locked);
    if (rc != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to store attestation validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    return LANTERN_CLIENT_OK;
}


/**
 * Publish a vote to the network.
 *
 * @param client  Client instance
 * @param vote    Vote to publish
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_NETWORK if gossip publish fails
 *
 * @note Thread safety: This function is thread-safe
 */
int validator_publish_vote(struct lantern_client *client, const LanternSignedVote *vote)
{
    if (!client || !vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (client->has_fork_choice)
    {
        if (lantern_fork_choice_add_vote(&client->fork_choice, vote, false) != 0)
        {
            lantern_log_debug(
                "validator",
                &meta,
                "failed to enqueue vote into fork choice validator=%" PRIu64 " slot=%" PRIu64,
                vote->data.validator_id,
                vote->data.slot);
        }
    }
    int rc = lantern_gossipsub_service_publish_vote(&client->gossip, vote);
    if (rc != 0)
    {
        lantern_log_warn(
            "gossip",
            &meta,
            "failed to publish attestation validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    lantern_log_info(
        "gossip",
        &meta,
        "published attestation validator=%" PRIu64 " slot=%" PRIu64,
        vote->data.validator_id,
        vote->data.slot);
    return LANTERN_CLIENT_OK;
}


/**
 * Publish a signed block via gossipsub.
 *
 * Broadcasts the signed block to all connected peers via the gossipsub
 * network. Logs the block root and attestation count on success.
 *
 * @param client  Client with active gossip service (gossip_running must be true)
 * @param block   Signed block to publish
 *
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL parameters
 * @return LANTERN_CLIENT_ERR_NETWORK if gossip is inactive or publish fails
 *
 * @note Thread safety: Acquires gossip lock internally
 */
int lantern_client_publish_block(struct lantern_client *client, const LanternSignedBlock *block)
{
    if (!client || !block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (!client->gossip_running)
    {
        lantern_log_error(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "cannot publish block at slot %" PRIu64 ": gossip service inactive",
            block->message.block.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    if (lantern_gossipsub_service_publish_block(&client->gossip, block) != 0)
    {
        lantern_log_error(
            "gossip",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to publish block at slot %" PRIu64,
            block->message.block.slot);
        return LANTERN_CLIENT_ERR_NETWORK;
    }

    LanternRoot block_root;
    char root_hex[2 * LANTERN_ROOT_SIZE + 3];
    if (lantern_hash_tree_root_block(&block->message.block, &block_root) == 0)
    {
        format_root_hex(&block_root, root_hex, sizeof(root_hex));
    }
    else
    {
        root_hex[0] = '\0';
    }

    lantern_log_info(
        "gossip",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "published block slot=%" PRIu64 " root=%s attestations=%zu",
        block->message.block.slot,
        root_hex[0] ? root_hex : "0x0",
        block->message.block.body.attestations.length);
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Block Building and Proposal
 * ============================================================================ */

/**
 * Build a block for a validator.
 *
 * @param client            Client instance
 * @param slot              Slot number
 * @param local_index       Local validator index
 * @param out_block         Output for the built block
 * @param out_proposer_vote Output for the proposer's vote
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on bad input
 * @return LANTERN_CLIENT_ERR_RUNTIME on state/runtime errors
 * @return LANTERN_CLIENT_ERR_VALIDATOR on signing failures
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation/copy failures
 *
 * @note Thread safety: This function acquires state_lock
 */
int validator_build_block(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index,
    LanternSignedBlock *out_block,
    LanternSignedVote *out_proposer_vote)
{
    lantern_client_error result = LANTERN_CLIENT_OK;
    LanternRoot parent_root;
    LanternAttestations att_list;
    LanternBlockSignatures att_signatures;
    bool att_list_initialized = false;
    bool att_signatures_initialized = false;

    if (!client || !out_block || !out_proposer_vote)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (local_index >= client->local_validator_count || !client->local_validators)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_local_validator *local = &client->local_validators[local_index];
    lantern_signed_block_with_attestation_init(out_block);
    memset(out_proposer_vote, 0, sizeof(*out_proposer_vote));

    lantern_attestations_init(&att_list);
    att_list_initialized = true;
    lantern_block_signatures_init(&att_signatures);
    att_signatures_initialized = true;

    result = validator_build_block_collect_attestations(
        client,
        slot,
        local,
        &parent_root,
        out_proposer_vote,
        &att_list,
        &att_signatures);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    result = validator_build_block_populate_message(
        slot,
        local->global_index,
        &parent_root,
        out_proposer_vote,
        &att_list,
        &att_signatures,
        out_block);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    LanternRoot computed_state_root;
    result = validator_build_block_preview_state_root(client, out_block, &computed_state_root);
    if (result != LANTERN_CLIENT_OK)
    {
        goto cleanup;
    }

    out_block->message.block.state_root = computed_state_root;
    result = LANTERN_CLIENT_OK;

cleanup:
    if (att_list_initialized)
    {
        lantern_attestations_reset(&att_list);
    }
    if (att_signatures_initialized)
    {
        lantern_block_signatures_reset(&att_signatures);
    }
    if (result != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_with_attestation_reset(out_block);
    }
    return result;
}


/**
 * Propose a block for a validator.
 *
 * @param client       Client instance
 * @param slot         Slot number
 * @param local_index  Local validator index
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_RUNTIME if validator service prerequisites are
 *         not met
 * @return Propagated error codes from validator_build_block() or
 *         lantern_client_publish_block()
 *
 * @note Thread safety: This function acquires validator_lock
 */
int validator_propose_block(struct lantern_client *client, uint64_t slot, size_t local_index)
{
    if (!validator_service_should_run(client))
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    LanternSignedBlock block;
    LanternSignedVote proposer_vote;
    lantern_signed_block_with_attestation_init(&block);
    memset(&proposer_vote, 0, sizeof(proposer_vote));

    int rc = validator_build_block(client, slot, local_index, &block, &proposer_vote);
    if (rc != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_with_attestation_reset(&block);
        return rc;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    lantern_log_info(
        "validator",
        &meta,
        "proposing block slot=%" PRIu64 " proposer=%" PRIu64,
        slot,
        block.message.block.proposer_index);

    lantern_client_record_block(client, &block, NULL, NULL, "local");
    rc = lantern_client_publish_block(client, &block);
    if (rc != LANTERN_CLIENT_OK)
    {
        lantern_signed_block_with_attestation_reset(&block);
        return rc;
    }

    if (client->validator_lock_initialized && pthread_mutex_lock(&client->validator_lock) == 0)
    {
        if (local_index < client->local_validator_count)
        {
            struct lantern_local_validator *local = &client->local_validators[local_index];
            local->last_proposed_slot = slot;
            local->pending_attestation = proposer_vote;
            local->pending_attestation_slot = slot;
            local->has_pending_attestation = true;
        }
        unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
    }

    lantern_signed_block_with_attestation_reset(&block);
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Attestation Publishing
 * ============================================================================ */

/**
 * Publish attestations for all enabled validators.
 *
 * @param client  Client instance
 * @param slot    Slot number
 * @return LANTERN_CLIENT_OK on success (even if individual publishes fail)
 * @return LANTERN_CLIENT_ERR_RUNTIME when prerequisites are not satisfied or
 *         locks fail
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM when inputs are NULL or no local
 *         validators are configured
 *
 * @note Thread safety: This function acquires state_lock and validator_lock
 */
int validator_publish_attestations(struct lantern_client *client, uint64_t slot)
{
    lantern_client_error result = LANTERN_CLIENT_OK;

    if (!validator_service_should_run(client))
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (!client->local_validators || client->local_validator_count == 0)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternCheckpoint head_cp;
    LanternCheckpoint target_cp;
    LanternCheckpoint source_cp;
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (lantern_state_compute_vote_checkpoints(
            &client->state,
            &head_cp,
            &target_cp,
            &source_cp)
        != 0)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    lantern_client_unlock_state(client, state_locked);

    bool have_lock = false;
    if (client->validator_lock_initialized)
    {
        if (pthread_mutex_lock(&client->validator_lock) != 0)
        {
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        have_lock = true;
    }

    for (size_t i = 0; i < client->local_validator_count; ++i)
    {
        bool enabled = client->validator_enabled ? client->validator_enabled[i] : true;
        if (!enabled)
        {
            continue;
        }
        struct lantern_local_validator *validator = &client->local_validators[i];
        if (validator->last_attested_slot == slot)
        {
            continue;
        }
        LanternSignedVote vote;
        if (validator->has_pending_attestation && validator->pending_attestation_slot == slot)
        {
            vote = validator->pending_attestation;
        }
        else
        {
            memset(&vote, 0, sizeof(vote));
            vote.data.validator_id = validator->global_index;
            vote.data.slot = slot;
            vote.data.head = head_cp;
            vote.data.target = target_cp;
            vote.data.source = source_cp;
            int sign_rc = validator_sign_vote(validator, slot, &vote);
            if (sign_rc != LANTERN_CLIENT_OK)
            {
                if (result == LANTERN_CLIENT_OK)
                {
                    result = (lantern_client_error)sign_rc;
                }
                continue;
            }
        }
        validator->last_attested_slot = slot;
        validator->has_pending_attestation = false;

        int store_rc = validator_store_vote(client, &vote);
        if (store_rc != LANTERN_CLIENT_OK && result == LANTERN_CLIENT_OK)
        {
            result = (lantern_client_error)store_rc;
        }
        int publish_rc = validator_publish_vote(client, &vote);
        if (publish_rc != LANTERN_CLIENT_OK && result == LANTERN_CLIENT_OK)
        {
            result = (lantern_client_error)publish_rc;
        }
    }

    if (have_lock)
    {
        unlock_mutex_with_log(&client->validator_lock, client->node_id, "validator_lock");
    }
    return result;
}


/* ============================================================================
 * Validator Service Thread
 * ============================================================================ */

/**
 * Validator service thread function.
 *
 * @param arg  Client instance
 * @return NULL
 *
 * @note Thread safety: This function runs in a separate thread
 */
void *validator_thread(void *arg)
{
    struct lantern_client *client = arg;
    if (!client)
    {
        return NULL;
    }

    while (__atomic_load_n(&client->validator_stop_flag, __ATOMIC_RELAXED) == 0)
    {
        if (!validator_service_should_run(client))
        {
            validator_sleep_ms(VALIDATOR_SERVICE_IDLE_SLEEP_MS);
            continue;
        }

        uint64_t now = validator_wall_time_now_seconds();
        if (client->has_runtime)
        {
            if (lantern_consensus_runtime_update_time(&client->runtime, now) != 0)
            {
                validator_sleep_ms(VALIDATOR_SERVICE_POLL_SLEEP_MS);
                continue;
            }
        }

        const struct lantern_slot_timepoint *tp =
            lantern_consensus_runtime_current_timepoint(&client->runtime);
        if (!tp)
        {
            validator_sleep_ms(VALIDATOR_SERVICE_POLL_SLEEP_MS);
            continue;
        }

        struct lantern_validator_duty_state *duty = &client->validator_duty;
        if (!duty->have_timepoint || duty->last_slot != tp->slot)
        {
            duty->have_timepoint = true;
            duty->last_slot = tp->slot;
            duty->slot_proposed = false;
            duty->slot_attested = false;
            duty->pending_local_proposal = false;
            duty->pending_local_index = 0;

            bool is_local = false;
            uint64_t local_index = 0;
            if (lantern_consensus_runtime_local_proposer(
                    &client->runtime,
                    tp->slot,
                    &is_local,
                    &local_index)
                == 0
                && is_local
                && local_index < client->local_validator_count)
            {
                duty->pending_local_proposal = true;
                duty->pending_local_index = local_index;
            }
        }
        duty->last_interval = tp->interval_index;

        if (client->has_fork_choice)
        {
            bool has_proposal = duty->slot_proposed;
            (void)lantern_fork_choice_advance_time(&client->fork_choice, now, has_proposal);
        }

        switch (tp->phase)
        {
            case LANTERN_DUTY_PHASE_PROPOSAL:
                if (duty->pending_local_proposal && !duty->slot_proposed)
                {
                    if (validator_propose_block(
                            client,
                            tp->slot,
                            (size_t)duty->pending_local_index)
                        == LANTERN_CLIENT_OK)
                    {
                        duty->slot_proposed = true;
                    }
                }
                break;

            case LANTERN_DUTY_PHASE_VOTE:
                if (!duty->slot_attested)
                {
                    if (validator_publish_attestations(client, tp->slot) == LANTERN_CLIENT_OK)
                    {
                        duty->slot_attested = true;
                    }
                }
                break;

            default:
                break;
        }

        validator_sleep_ms(VALIDATOR_SERVICE_POLL_SLEEP_MS);
    }
    return NULL;
}


/**
 * Start the validator service.
 *
 * Spawns the validator service thread which handles block proposals and
 * attestation publishing. The service requires local validators and runtime
 * to be configured. If already started, returns success without action.
 *
 * @param client  Client instance
 *
 * @return LANTERN_CLIENT_OK on success, or if service is already running or
 *         prerequisites are missing
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if client is NULL
 * @return LANTERN_CLIENT_ERR_RUNTIME if the thread cannot be created
 *
 * @note Thread safety: This function is thread-safe
 */
int start_validator_service(struct lantern_client *client)
{
    if (!client)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->validator_thread_started)
    {
        return LANTERN_CLIENT_OK;
    }
    if (client->local_validator_count == 0 || !client->has_runtime)
    {
        return LANTERN_CLIENT_OK;
    }
    validator_duty_state_reset(&client->validator_duty);
    __atomic_store_n(&client->validator_stop_flag, 0, __ATOMIC_RELAXED);
    if (pthread_create(&client->validator_thread, NULL, validator_thread, client) != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to start validator service thread");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    client->validator_thread_started = true;
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator service started");
    return LANTERN_CLIENT_OK;
}


/**
 * Stop the validator service.
 *
 * Signals the validator service thread to stop and waits for it to exit.
 * Safe to call even if the service was never started.
 *
 * @param client  Client instance (may be NULL)
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_validator_service(struct lantern_client *client)
{
    if (!client || !client->validator_thread_started)
    {
        return;
    }
    __atomic_store_n(&client->validator_stop_flag, 1, __ATOMIC_RELAXED);
    int join_rc = pthread_join(client->validator_thread, NULL);
    if (join_rc != 0)
    {
        lantern_log_warn(
            "validator",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pthread_join failed: %d",
            join_rc);
    }
    client->validator_thread_started = false;
    lantern_log_info(
        "validator",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "validator service stopped");
}
