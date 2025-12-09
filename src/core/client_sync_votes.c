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

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

#include <inttypes.h>
#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * External Functions (from client_sync.c)
 * ============================================================================ */

extern const struct lantern_validator_record *lantern_client_get_validator_record(
    const struct lantern_client *client,
    uint64_t validator_id);


/* ============================================================================
 * Vote Signature Verification
 * ============================================================================ */

/**
 * Verify a vote signature using the validator's public key.
 *
 * @spec subspecs/xmss/signature.py - XMSS signature verification
 *
 * Retrieves the validator's 52-byte public key from either the state's
 * validator registry or the genesis registry as fallback, then verifies
 * the XMSS signature over the vote's hash tree root.
 *
 * Per LeanSpec: Always use the 52-byte pubkey directly from state.validators[].pubkey.
 * This matches Zeam's verifyBincode which takes pubkey bytes directly from state.
 *
 * @param client     Client instance
 * @param vote       Signed vote to verify
 * @param signature  Signature to verify
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
    const struct lantern_log_metadata *meta,
    const char *context)
{
    if (!client || !vote || !signature)
    {
        return false;
    }
    const uint8_t *pubkey_bytes = NULL;
    bool state_has_registry = client && client->has_state;
    size_t state_validator_count = state_has_registry ? lantern_state_validator_count(&client->state) : 0;
    if (state_has_registry && state_validator_count > 0)
    {
        if (vote->data.validator_id >= state_validator_count)
        {
            lantern_log_warn(
                "state",
                meta,
                "validator=%" PRIu64 " exceeds parent state validator count=%zu",
                vote->data.validator_id,
                state_validator_count);
            return false;
        }
        pubkey_bytes = lantern_state_validator_pubkey(&client->state, (size_t)vote->data.validator_id);
        if (lantern_validator_pubkey_is_zero(pubkey_bytes))
        {
            pubkey_bytes = NULL;
        }
    }
    if (!pubkey_bytes)
    {
        const struct lantern_validator_record *record =
            lantern_client_get_validator_record(client, vote->data.validator_id);
        if (!record || !record->has_pubkey_bytes)
        {
            lantern_log_warn(
                "state",
                meta,
                "missing validator %s pubkey for validator=%" PRIu64,
                context ? context : "signature",
                vote->data.validator_id);
            return false;
        }
        pubkey_bytes = record->pubkey_bytes;
    }
    LanternRoot vote_root;
    if (lantern_hash_tree_root_vote(&vote->data, &vote_root) != 0)
    {
        lantern_log_warn("state", meta, "failed to hash attestation for validator=%" PRIu64, vote->data.validator_id);
        return false;
    }
    bool ok = lantern_signature_verify(
        pubkey_bytes,
        LANTERN_VALIDATOR_PUBKEY_SIZE,
        vote->data.slot,
        signature,
        vote_root.bytes,
        sizeof(vote_root.bytes));
    if (!ok)
    {
        lantern_log_warn(
            "state",
            meta,
            "invalid XMSS signature validator=%" PRIu64 " context=%s",
            vote->data.validator_id,
            context ? context : "unknown");
    }
    return ok;
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
 * 4. Vote slot must not exceed current_slot + 1
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

    struct checkpoint_rule
    {
        const LanternCheckpoint *checkpoint;
        const char *name;
    } rules[] = {
        {.checkpoint = &vote->source, .name = "source"},
        {.checkpoint = &vote->target, .name = "target"},
        {.checkpoint = &vote->head, .name = "head"},
    };

    for (size_t i = 0; i < (sizeof(rules) / sizeof(rules[0])); ++i)
    {
        const struct checkpoint_rule *rule = &rules[i];
        char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&rule->checkpoint->root, root_hex, sizeof(root_hex));
        if (lantern_root_is_zero(&rule->checkpoint->root))
        {
            lantern_log_debug(
                log_facility,
                meta,
                "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " %s root=%s (zero root)",
                label,
                vote->validator_id,
                vote->slot,
                rule->name,
                root_hex[0] ? root_hex : "0x0");
            if (out_rejection)
            {
                lantern_vote_rejection_set(
                    out_rejection,
                    "%s checkpoint root zero slot=%" PRIu64 " root=%s",
                    rule->name,
                    rule->checkpoint->slot,
                    root_hex[0] ? root_hex : "0x0");
            }
            return false;
        }
        uint64_t block_slot = 0;
        if (!lantern_client_block_known_locked(client, &rule->checkpoint->root, &block_slot))
        {
            lantern_log_debug(
                log_facility,
                meta,
                "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " unknown %s root=%s",
                label,
                vote->validator_id,
                vote->slot,
                rule->name,
                root_hex[0] ? root_hex : "0x0");
            if (out_rejection)
            {
                lantern_vote_rejection_set(
                    out_rejection,
                    "unknown %s root=%s slot=%" PRIu64,
                    rule->name,
                    root_hex[0] ? root_hex : "0x0",
                    rule->checkpoint->slot);
            }
            return false;
        }
        if (block_slot != rule->checkpoint->slot)
        {
            lantern_log_debug(
                log_facility,
                meta,
                "dropping %s validator=%" PRIu64 " slot=%" PRIu64 " %s slot mismatch vote=%" PRIu64
                " block=%" PRIu64 " root=%s",
                label,
                vote->validator_id,
                vote->slot,
                rule->name,
                rule->checkpoint->slot,
                block_slot,
                root_hex[0] ? root_hex : "0x0");
            if (out_rejection)
            {
                lantern_vote_rejection_set(
                    out_rejection,
                    "%s checkpoint slot mismatch vote=%" PRIu64 " block=%" PRIu64,
                    rule->name,
                    rule->checkpoint->slot,
                    block_slot);
            }
            return false;
        }
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
 * 3. Checks block availability in fork choice or state justified window
 * 4. Updates fork choice with the vote
 * 5. Caches vote in state
 * 6. Persists vote to storage
 *
 * Per leanSpec: Attestation validation only requires that the referenced
 * blocks (source, target, head) exist in the store. We check fork choice
 * first, then fall back to state's justified window for backwards compat.
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
    bool vote_processed = false;

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char target_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char source_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    LanternSignedVote vote_copy = *vote;
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

    if (!client->has_fork_choice)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "deferring vote validator=%" PRIu64 " slot=%" PRIu64 " (fork choice unavailable)",
            vote_copy.data.validator_id,
            vote_copy.data.slot);
        lantern_vote_rejection_set(&rejection, "fork choice unavailable");
        goto cleanup;
    }

    if (!lantern_client_validate_vote_constraints(
            client,
            &vote_copy.data,
            "gossip",
            &meta,
            "gossip",
            &rejection))
    {
        goto cleanup;
    }

    if (!lantern_client_verify_vote_signature(
            client,
            &vote_copy,
            &vote_copy.signature,
            &meta,
            "gossip"))
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "rejected vote validator=%" PRIu64 " slot=%" PRIu64 " (invalid XMSS signature)",
            vote_copy.data.validator_id,
            vote_copy.data.slot);
        lantern_vote_rejection_set(&rejection, "invalid XMSS signature");
        goto cleanup;
    }

    const LanternVote *vote_data = &vote_copy.data;
    uint64_t validator_count = client->state.config.num_validators;
    if (validator_count == 0 || !client->state.validator_votes || client->state.validator_votes_len == 0)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (state vote cache unavailable)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(&rejection, "state vote cache unavailable");
        goto cleanup;
    }
    if ((vote_data->validator_id >= validator_count)
        || (vote_data->validator_id >= (uint64_t)client->state.validator_votes_len))
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (validator out of range)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(&rejection, "validator out of range id=%" PRIu64, vote_data->validator_id);
        goto cleanup;
    }
    if (vote_data->target.slot < vote_data->source.slot)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (target slot < source)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(
            &rejection,
            "target slot %" PRIu64 " < source slot %" PRIu64,
            vote_data->target.slot,
            vote_data->source.slot);
        goto cleanup;
    }

    /*
     * Per leanSpec, attestation validation only requires that the referenced
     * blocks (source, target, head) exist in the store. We check fork choice
     * first, then fall back to state's justified window for backwards compat.
     * This allows attestations from competing forks to be processed correctly.
     */
    bool source_block_known = false;
    bool target_block_known = false;
    bool head_block_known = false;
    uint64_t source_block_slot = 0;
    uint64_t target_block_slot = 0;

    if (client->has_fork_choice)
    {
        source_block_known = (lantern_fork_choice_block_info(
            &client->fork_choice, &vote_data->source.root, &source_block_slot, NULL, NULL) == 0);
        target_block_known = (lantern_fork_choice_block_info(
            &client->fork_choice, &vote_data->target.root, &target_block_slot, NULL, NULL) == 0);
        head_block_known = (lantern_fork_choice_block_info(
            &client->fork_choice, &vote_data->head.root, NULL, NULL, NULL) == 0);
    }

    if (!source_block_known)
    {
        /* Source block not in fork choice - check state's justified window as fallback */
        if (!lantern_state_slot_in_justified_window(&client->state, vote_data->source.slot))
        {
            lantern_log_debug(
                "gossip",
                &meta,
                "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (source block unknown and outside justified window)",
                vote_data->validator_id,
                vote_data->slot);
            lantern_vote_rejection_set(
                &rejection,
                "source slot=%" PRIu64 " block unknown and outside justified window",
                vote_data->source.slot);
            goto cleanup;
        }
        bool source_is_justified = false;
        if (lantern_state_get_justified_slot_bit(&client->state, vote_data->source.slot, &source_is_justified) != 0
            || !source_is_justified)
        {
            lantern_log_debug(
                "gossip",
                &meta,
                "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (source not justified in state)",
                vote_data->validator_id,
                vote_data->slot);
            lantern_vote_rejection_set(&rejection, "source slot=%" PRIu64 " not justified", vote_data->source.slot);
            goto cleanup;
        }
    }
    else
    {
        /* Source block is in fork choice - verify checkpoint slot matches block slot */
        if (source_block_slot != vote_data->source.slot)
        {
            lantern_log_debug(
                "gossip",
                &meta,
                "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (source checkpoint slot mismatch)",
                vote_data->validator_id,
                vote_data->slot);
            lantern_vote_rejection_set(
                &rejection,
                "source checkpoint slot=%" PRIu64 " != block slot=%" PRIu64,
                vote_data->source.slot,
                source_block_slot);
            goto cleanup;
        }
    }

    if (!target_block_known && !head_block_known)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (target and head blocks unknown)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(&rejection, "target and head blocks unknown");
        goto cleanup;
    }

    if (target_block_known && target_block_slot != vote_data->target.slot)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "dropping vote validator=%" PRIu64 " slot=%" PRIu64 " (target checkpoint slot mismatch)",
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(
            &rejection,
            "target checkpoint slot=%" PRIu64 " != block slot=%" PRIu64,
            vote_data->target.slot,
            target_block_slot);
        goto cleanup;
    }

    if (lantern_state_set_signed_validator_vote(&client->state, (size_t)vote_data->validator_id, &vote_copy) != 0)
    {
        lantern_log_debug(
            "state",
            &meta,
            "failed to cache gossip vote validator=%" PRIu64 " slot=%" PRIu64,
            vote_data->validator_id,
            vote_data->slot);
        lantern_vote_rejection_set(
            &rejection,
            "failed to cache vote validator=%" PRIu64 " slot=%" PRIu64,
            vote_data->validator_id,
            vote_data->slot);
        goto cleanup;
    }

    if (client->has_fork_choice)
    {
        if (lantern_fork_choice_add_vote(&client->fork_choice, &vote_copy, false) != 0)
        {
            lantern_log_debug(
                "forkchoice",
                &meta,
                "failed to track gossip vote validator=%" PRIu64 " slot=%" PRIu64,
                vote_copy.data.validator_id,
                vote_copy.data.slot);
        }
        else
        {
            if (!client->debug_disable_fork_choice_time)
            {
                uint64_t now_seconds = 0;
                if (!lantern_client_vote_time_seconds(client, vote_copy.data.slot, &now_seconds))
                {
                    now_seconds = validator_wall_time_now_seconds();
                }
                if (lantern_fork_choice_advance_time(&client->fork_choice, now_seconds, false) != 0)
                {
                    lantern_log_debug(
                        "forkchoice",
                        &meta,
                        "advancing fork choice time failed after validator=%" PRIu64 " slot=%" PRIu64,
                        vote_copy.data.validator_id,
                        vote_copy.data.slot);
                }
            }
        }
    }

    if (client->data_dir)
    {
        if (lantern_storage_save_votes(client->data_dir, &client->state) != 0)
        {
            lantern_log_warn(
                "storage",
                &meta,
                "failed to persist votes after validator=%" PRIu64 " slot=%" PRIu64,
                vote_copy.data.validator_id,
                vote_copy.data.slot);
        }
    }

    vote_processed = true;
    lantern_log_info(
        "gossip",
        &meta,
        "processed vote validator=%" PRIu64
        " slot=%" PRIu64 " head=%s target=%s@%" PRIu64 " source=%s@%" PRIu64,
        vote_copy.data.validator_id,
        vote_copy.data.slot,
        head_hex[0] ? head_hex : "0x0",
        target_hex[0] ? target_hex : "0x0",
        vote_copy.data.target.slot,
        source_hex[0] ? source_hex : "0x0",
        vote_copy.data.source.slot);

cleanup:
    lantern_client_unlock_state(client, state_locked);
    lantern_client_note_vote_outcome(client, peer_text, &vote_copy, vote_processed);
    if (!vote_processed)
    {
        const char *reason_text = rejection.has_reason ? rejection.message : "unknown";
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
}
