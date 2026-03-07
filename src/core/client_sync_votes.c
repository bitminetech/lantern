/**
 * @file client_sync_votes.c
 * @brief Vote (attestation) processing and validation
 *
 * @spec subspecs/containers/attestation/attestation.py in tools/leanSpec
 * @spec subspecs/forkchoice/store.py - on_attestation() in tools/leanSpec
 *
 * Implements vote signature verification, constraint validation, and
 * recording received votes to fork choice and state.
 *
 * Related files:
 * - client_sync.c: Main sync logic and gossip handlers
 * - client_sync_blocks.c: Block import logic
 *
 * @note Thread safety: Functions that access shared state acquire appropriate
 *       locks as documented. See client_internal.h for lock ordering.
 */

#include "client_internal.h"

#include <inttypes.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

enum
{
    VOTE_ROOT_HEX_BUFFER_LEN = (LANTERN_ROOT_SIZE * 2u) + 3u,
};


/* ============================================================================
 * External Functions (from client_sync.c)
 * ============================================================================ */

bool lantern_client_verify_vote_signature(
    const struct lantern_client *client,
    const LanternSignedVote *vote,
    const LanternSignature *signature,
    const LanternState *state_override,
    const struct lantern_log_metadata *meta,
    const char *context);


/* ============================================================================
 * Internal Helpers
 * ============================================================================ */

/**
 * @brief Validates a vote checkpoint against fork choice.
 *
 * @param client         Client instance
 * @param vote           Vote being validated
 * @param checkpoint     Checkpoint to validate
 * @param name           Checkpoint name for logging
 * @param log_facility   Log facility name
 * @param meta           Logging metadata
 * @param label          Vote label for logging
 * @param out_rejection  Output rejection info (may be NULL)
 * @return true if checkpoint is valid
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool validate_vote_checkpoint(
    struct lantern_client *client,
    const LanternVote *vote,
    const LanternCheckpoint *checkpoint,
    const char *name,
    const char *log_facility,
    const struct lantern_log_metadata *meta,
    const char *label,
    struct lantern_vote_rejection_info *out_rejection)
{
    char root_hex[VOTE_ROOT_HEX_BUFFER_LEN];
    format_root_hex(&checkpoint->root, root_hex, sizeof(root_hex));

    if (lantern_root_is_zero(&checkpoint->root))
    {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " %s root=%s "
            "(zero root)",
            label,
            vote->validator_id,
            vote->slot,
            name,
            root_hex[0] ? root_hex : "0x0");
        if (out_rejection)
        {
            lantern_vote_rejection_set(
                out_rejection,
                "%s checkpoint root zero slot=%" PRIu64 " root=%s",
                name,
                checkpoint->slot,
                root_hex[0] ? root_hex : "0x0");
        }
        return false;
    }

    uint64_t block_slot = 0;
    if (!lantern_client_block_known_locked(client, &checkpoint->root, &block_slot))
    {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " unknown %s root=%s",
            label,
            vote->validator_id,
            vote->slot,
            name,
            root_hex[0] ? root_hex : "0x0");
        if (out_rejection)
        {
            lantern_vote_rejection_set(
                out_rejection,
                "unknown %s root=%s slot=%" PRIu64,
                name,
                root_hex[0] ? root_hex : "0x0",
                checkpoint->slot);
            out_rejection->has_unknown_root = true;
            out_rejection->unknown_root = checkpoint->root;
            out_rejection->unknown_slot = checkpoint->slot;
        }
        return false;
    }

    if (block_slot != checkpoint->slot)
    {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " %s slot mismatch "
            "vote=%" PRIu64 " block=%" PRIu64 " root=%s",
            label,
            vote->validator_id,
            vote->slot,
            name,
            checkpoint->slot,
            block_slot,
            root_hex[0] ? root_hex : "0x0");
        if (out_rejection)
        {
            lantern_vote_rejection_set(
                out_rejection,
                "%s checkpoint slot mismatch vote=%" PRIu64 " block=%" PRIu64,
                name,
                checkpoint->slot,
                block_slot);
        }
        return false;
    }

    return true;
}


/**
 * @brief Validates vote cache availability.
 *
 * @param client     Client instance
 * @param vote       Vote to validate
 * @param meta       Logging metadata
 * @param rejection  Rejection info to populate on failure
 * @return true if vote cache state is valid
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool validate_vote_cache_state(
    const struct lantern_client *client,
    const LanternVote *vote,
    const struct lantern_log_metadata *meta,
    struct lantern_vote_rejection_info *rejection)
{
    if (!client || !vote || !rejection)
    {
        return false;
    }

    uint64_t validator_count = client->state.config.num_validators;
    bool cache_available = (validator_count != 0) && client->store.validator_votes
        && (client->store.validator_votes_len != 0);
    if (!cache_available)
    {
        lantern_log_debug(
            "gossip",
            meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " "
            "(state vote cache unavailable)",
            vote->validator_id,
            vote->slot);
        lantern_vote_rejection_set(rejection, "state vote cache unavailable");
        return false;
    }

    bool validator_in_range = (vote->validator_id < validator_count)
        && (vote->validator_id < (uint64_t)client->store.validator_votes_len);
    if (!validator_in_range)
    {
        lantern_log_debug(
            "gossip",
            meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " "
            "(validator out of range)",
            vote->validator_id,
            vote->slot);
        lantern_vote_rejection_set(
            rejection,
            "validator out of range id=%" PRIu64,
            vote->validator_id);
        return false;
    }

    return true;
}


/**
 * @brief Cache a signed validator vote in state.
 *
 * @param client     Client instance
 * @param vote       Signed vote to cache
 * @param meta       Logging metadata
 * @param rejection  Rejection info to populate on failure
 * @return true if vote is cached successfully
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool cache_state_vote_locked(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const struct lantern_log_metadata *meta,
    struct lantern_vote_rejection_info *rejection)
{
    if (!client || !vote || !meta || !rejection)
    {
        return false;
    }

    int result = lantern_store_set_signed_validator_vote(
        &client->store,
        (size_t)vote->data.validator_id,
        vote);
    if (result != 0)
    {
        lantern_log_debug(
            "state",
            meta,
            "failed to cache gossip vote validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        lantern_vote_rejection_set(
            rejection,
            "failed to cache vote validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
        return false;
    }

    return true;
}


/**
 * @brief Persist votes to storage if configured.
 *
 * @param client  Client instance
 * @param vote    Vote used for log context
 * @param meta    Logging metadata
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void persist_votes_if_configured_locked(
    const struct lantern_client *client,
    const LanternSignedVote *vote,
    const struct lantern_log_metadata *meta)
{
    if (!client || !vote || !meta || !client->data_dir)
    {
        return;
    }

    if (lantern_storage_save_votes(client->data_dir, &client->state, &client->store) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist votes after validator=%" PRIu64 " slot=%" PRIu64,
            vote->data.validator_id,
            vote->data.slot);
    }
}


/**
 * @brief Validate and apply a received vote while holding state_lock.
 *
 * @param client     Client instance
 * @param vote       Vote to validate and apply (may be modified in place)
 * @param meta       Logging metadata
 * @param rejection  Rejection info to populate on failure
 * @return true if vote was processed successfully
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool process_vote_locked(
    struct lantern_client *client,
    LanternSignedVote *vote,
    const struct lantern_log_metadata *meta,
    struct lantern_vote_rejection_info *rejection)
{
    if (!client || !vote || !meta || !rejection)
    {
        return false;
    }

    if (!client->has_fork_choice)
    {
        lantern_log_debug(
            "gossip",
            meta,
            "deferring vote validator=%" PRIu64 " slot=%" PRIu64 " (fork choice unavailable)",
            vote->data.validator_id,
            vote->data.slot);
        lantern_vote_rejection_set(rejection, "fork choice unavailable");
        return false;
    }

    if (!lantern_client_validate_vote_constraints(
            client,
            &vote->data,
            "gossip",
            meta,
            "gossip",
            rejection))
    {
        return false;
    }

    LanternState target_state;
    lantern_state_init(&target_state);
    const LanternState *sig_state = lantern_client_state_for_root_locked(
        client,
        &vote->data.target.root,
        &target_state,
        NULL);
    if (!sig_state)
    {
        char target_hex[VOTE_ROOT_HEX_BUFFER_LEN];
        format_root_hex(&vote->data.target.root, target_hex, sizeof(target_hex));
        lantern_log_debug(
            "gossip",
            meta,
            "missing target state root=%s for validator=%" PRIu64 " slot=%" PRIu64,
            target_hex[0] ? target_hex : "0x0",
            vote->data.validator_id,
            vote->data.slot);
        lantern_vote_rejection_set(
            rejection,
            "missing target state target_slot=%" PRIu64 " root=%s",
            vote->data.target.slot,
            target_hex[0] ? target_hex : "0x0");
        lantern_state_reset(&target_state);
        return false;
    }

    if (!lantern_client_verify_vote_signature(
            client,
            vote,
            &vote->signature,
            sig_state,
            meta,
            "gossip"))
    {
        lantern_log_debug(
            "gossip",
            meta,
            "rejected vote validator=%" PRIu64 " slot=%" PRIu64 " (invalid XMSS signature)",
            vote->data.validator_id,
            vote->data.slot);
        lantern_vote_rejection_set(rejection, "invalid XMSS signature");
        lantern_state_reset(&target_state);
        return false;
    }
    lantern_state_reset(&target_state);

    if (!validate_vote_cache_state(client, &vote->data, meta, rejection))
    {
        return false;
    }

    if (!cache_state_vote_locked(client, vote, meta, rejection))
    {
        return false;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data.data, &data_root) == 0)
    {
        LanternSignatureKey key = {
            .validator_index = vote->data.validator_id,
            .data_root = data_root,
        };
        if (lantern_client_set_gossip_signature(
                client,
                &key,
                &vote->data.data,
                &vote->signature,
                vote->data.target.slot)
            != 0)
        {
            lantern_log_debug(
                "state",
                meta,
                "failed to cache gossip signature validator=%" PRIu64 " slot=%" PRIu64,
                vote->data.validator_id,
                vote->data.slot);
        }
    }

    persist_votes_if_configured_locked(client, vote, meta);
    return true;
}


/* ============================================================================
 * Vote Signature Verification
 * ============================================================================ */

/**
 * Verify a vote signature using the validator's public key.
 *
 * @spec subspecs/xmss/signature.py - XMSS signature verification
 *
 * Retrieves the validator's 52-byte public key from the supplied state's
 * validator registry, then verifies the XMSS signature over the vote's
 * hash tree root.
 *
 * Per LeanSpec: Always use the 52-byte pubkey directly from state.validators[].pubkey.
 * This matches Zeam's verifyBincode which takes pubkey bytes directly from state.
 *
 * @param client     Client instance
 * @param vote       Signed vote to verify
 * @param signature  Signature to verify
 * @param state_override State to use for validator pubkey lookup
 * @param meta       Logging metadata
 * @param context    Description of signature context for logging
 * @return true if signature is valid
 *
 * @note Thread safety: Thread-safe, reads immutable validator registry
 */
bool lantern_client_verify_vote_signature(
    const struct lantern_client *client,
    const LanternSignedVote *vote,
    const LanternSignature *signature,
    const LanternState *state_override,
    const struct lantern_log_metadata *meta,
    const char *context)
{
    if (!client || !vote || !signature)
    {
        return false;
    }
    if (!state_override)
    {
        lantern_log_warn(
            "state",
            meta,
            "missing state for %s signature verification",
            context ? context : "vote");
        return false;
    }
    size_t state_validator_count = lantern_state_validator_count(state_override);
    if (state_validator_count == 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "missing validator registry for %s signature verification",
            context ? context : "vote");
        return false;
    }
    if (vote->data.validator_id >= state_validator_count)
    {
        lantern_log_warn(
            "state",
            meta,
            "validator=%" PRIu64 " exceeds %s state validator count=%zu",
            vote->data.validator_id,
            context ? context : "vote",
            state_validator_count);
        return false;
    }
    const uint8_t *pubkey_bytes = lantern_state_validator_pubkey(
        state_override,
        (size_t)vote->data.validator_id);
    if (!pubkey_bytes || lantern_validator_pubkey_is_zero(pubkey_bytes))
    {
        lantern_log_warn(
            "state",
            meta,
            "missing validator pubkey for %s signature verification",
            context ? context : "vote");
        return false;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data.data, &vote_root) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to hash attestation for validator=%" PRIu64,
            vote->data.validator_id);
        return false;
    }
    bool is_signature_valid = lantern_signature_verify(
        pubkey_bytes,
        LANTERN_VALIDATOR_PUBKEY_SIZE,
        vote->data.slot,
        signature,
        &vote_root);
    if (!is_signature_valid)
    {
        lantern_log_warn(
            "state",
            meta,
            "invalid XMSS signature validator=%" PRIu64 " slot=%" PRIu64 " context=%s",
            vote->data.validator_id,
            vote->data.slot,
            context ? context : "unknown");
    }
    return is_signature_valid;
}


/* ============================================================================
 * Vote Constraint Validation
 * ============================================================================ */

/**
 * Validate vote constraints against fork choice.
 *
 * @spec subspecs/forkchoice/store.py - on_attestation() validation
 * @spec subspecs/containers/slot.py - Slot justification rules
 *
 * Validates that a vote meets all consensus requirements:
 * 1. All checkpoint roots (source, target, head) must be non-zero
 * 2. All checkpoint roots must be known in fork choice
 * 3. Checkpoint slots must match the block slots in fork choice
 * 4. Checkpoint ordering must satisfy source <= target <= head
 * 5. Vote slot must not exceed current_slot + 1
 *
 * Per leanSpec: checks that all referenced blocks exist in the store
 * before accepting the attestation.
 *
 * @param client         Client instance
 * @param vote           Vote to validate
 * @param facility       Log facility name
 * @param meta           Logging metadata
 * @param context        Description for logging
 * @param out_rejection  Output rejection info (may be NULL)
 * @return true if vote is valid
 *
 * @note Thread safety: Caller must hold state_lock if accessing state
 */
bool lantern_client_validate_vote_constraints(
    struct lantern_client *client,
    const LanternVote *vote,
    const char *facility,
    const struct lantern_log_metadata *meta,
    const char *context,
    struct lantern_vote_rejection_info *out_rejection)
{
    if (!client || !vote || !client->has_fork_choice)
    {
        return false;
    }
    const char *log_facility = (facility && *facility) ? facility : "state";
    const char *label = (context && *context) ? context : "vote";

    if (!validate_vote_checkpoint(
            client,
            vote,
            &vote->source,
            "source",
            log_facility,
            meta,
            label,
            out_rejection))
    {
        return false;
    }

    if (!validate_vote_checkpoint(
            client,
            vote,
            &vote->target,
            "target",
            log_facility,
            meta,
            label,
            out_rejection))
    {
        return false;
    }

    if (!validate_vote_checkpoint(
            client,
            vote,
            &vote->head,
            "head",
            log_facility,
            meta,
            label,
            out_rejection))
    {
        return false;
    }

    if (vote->target.slot < vote->source.slot)
    {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " "
            "(target slot < source)",
            label,
            vote->validator_id,
            vote->slot);
        if (out_rejection)
        {
            lantern_vote_rejection_set(
                out_rejection,
                "target slot %" PRIu64 " < source slot %" PRIu64,
                vote->target.slot,
                vote->source.slot);
        }
        return false;
    }

    if (vote->head.slot < vote->target.slot)
    {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " "
            "(head slot < target)",
            label,
            vote->validator_id,
            vote->slot);
        if (out_rejection)
        {
            lantern_vote_rejection_set(
                out_rejection,
                "head slot %" PRIu64 " < target slot %" PRIu64,
                vote->head.slot,
                vote->target.slot);
        }
        return false;
    }

    uint64_t current_slot = 0;
    if (!lantern_client_current_slot(client, &current_slot))
    {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " (unable to compute current slot)",
            label,
            vote->validator_id,
            vote->slot);
        if (out_rejection)
        {
            lantern_vote_rejection_set(out_rejection, "unable to compute current slot");
        }
        return false;
    }
    uint64_t allowed_slot = current_slot == UINT64_MAX ? UINT64_MAX : current_slot + 1u;
    if (vote->slot > allowed_slot)
    {
        lantern_log_debug(
            log_facility,
            meta,
            "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " (current_slot=%" PRIu64 ")",
            label,
            vote->validator_id,
            vote->slot,
            current_slot);
        if (out_rejection)
        {
            lantern_vote_rejection_set(
                out_rejection,
                "vote slot=%" PRIu64 " exceeds allowed=%" PRIu64 " current=%" PRIu64,
                vote->slot,
                allowed_slot,
                current_slot);
        }
        return false;
    }

    return true;
}


/* ============================================================================
 * Vote Recording
 * ============================================================================ */

/**
 * Record and process a received vote.
 *
 * @spec subspecs/forkchoice/store.py - on_attestation()
 * @spec subspecs/containers/state/state.py - State.process_attestations()
 *
 * Performs the complete vote validation and recording pipeline:
 * 1. Validates vote constraints (checkpoints, slots)
 * 2. Verifies XMSS signature
 * 3. Validates vote cache availability and validator range
 * 4. Caches the signed vote in state
 * 5. Stores gossip signature/data for the staged aggregation pipeline
 * 6. Persists votes to storage
 *
 * @param client    Client instance
 * @param vote      Signed vote to record
 * @param peer_text Peer ID string (may be NULL)
 *
 * @note Thread safety: Acquires state_lock
 */
void lantern_client_record_vote(
    struct lantern_client *client,
    const LanternSignedVote *vote,
    const char *peer_text)
{
    if (!client || !vote || !client->has_state)
    {
        return;
    }

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = (peer_text && *peer_text) ? peer_text : NULL,
    };

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return;
    }

    struct lantern_vote_rejection_info rejection;
    memset(&rejection, 0, sizeof(rejection));

    LanternSignedVote vote_copy = *vote;
    char head_hex[VOTE_ROOT_HEX_BUFFER_LEN];
    char target_hex[VOTE_ROOT_HEX_BUFFER_LEN];
    char source_hex[VOTE_ROOT_HEX_BUFFER_LEN];
    format_root_hex(&vote_copy.data.head.root, head_hex, sizeof(head_hex));
    format_root_hex(&vote_copy.data.target.root, target_hex, sizeof(target_hex));
    format_root_hex(&vote_copy.data.source.root, source_hex, sizeof(source_hex));
    lantern_log_debug(
        "gossip",
        &meta,
        "received vote validator=%" PRIu64 " slot=%" PRIu64 " head=%s target=%s@%" PRIu64,
        vote_copy.data.validator_id,
        vote_copy.data.slot,
        head_hex[0] ? head_hex : "0x0",
        target_hex[0] ? target_hex : "0x0",
        vote_copy.data.target.slot);

    bool vote_processed = process_vote_locked(client, &vote_copy, &meta, &rejection);
    if (vote_processed)
    {
        lantern_log_info(
            "gossip",
            &meta,
            "processed vote validator=%" PRIu64 " slot=%" PRIu64 " head=%s target=%s@%" PRIu64
            " source=%s@%" PRIu64,
            vote_copy.data.validator_id,
            vote_copy.data.slot,
            head_hex[0] ? head_hex : "0x0",
            target_hex[0] ? target_hex : "0x0",
            vote_copy.data.target.slot,
            source_hex[0] ? source_hex : "0x0",
            vote_copy.data.source.slot);
    }
    lantern_client_unlock_state(client, state_locked);
    lantern_client_note_vote_outcome(client, peer_text, &vote_copy, vote_processed);
    if (!vote_processed)
    {
        const char *reason_text = rejection.has_reason ? rejection.message : "unknown";
        if (client->sync_in_progress)
        {
            lantern_log_debug(
                "gossip",
                &meta,
                "rejected vote validator=%" PRIu64 " slot=%" PRIu64 " head=%s target=%s@%" PRIu64
                " source=%s@%" PRIu64 " reason=%s",
                vote_copy.data.validator_id,
                vote_copy.data.slot,
                head_hex[0] ? head_hex : "0x0",
                target_hex[0] ? target_hex : "0x0",
                vote_copy.data.target.slot,
                source_hex[0] ? source_hex : "0x0",
                vote_copy.data.source.slot,
                reason_text);
        }
        else
        {
            lantern_log_info(
                "gossip",
                &meta,
                "rejected vote validator=%" PRIu64 " slot=%" PRIu64 " head=%s target=%s@%" PRIu64
                " source=%s@%" PRIu64 " reason=%s",
                vote_copy.data.validator_id,
                vote_copy.data.slot,
                head_hex[0] ? head_hex : "0x0",
                target_hex[0] ? target_hex : "0x0",
                vote_copy.data.target.slot,
                source_hex[0] ? source_hex : "0x0",
                vote_copy.data.source.slot,
                reason_text);
        }
        if (rejection.has_unknown_root && !lantern_root_is_zero(&rejection.unknown_root))
        {
            char root_hex[VOTE_ROOT_HEX_BUFFER_LEN];
            format_root_hex(&rejection.unknown_root, root_hex, sizeof(root_hex));
            lantern_log_info(
                "reqresp",
                &meta,
                "dropping vote unknown root=%s slot=%" PRIu64 " (no backfill)",
                root_hex[0] ? root_hex : "0x0",
                rejection.unknown_slot);
        }
    }
}
