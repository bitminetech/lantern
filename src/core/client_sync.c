/**
 * @file client_sync.c
 * @brief Block and vote synchronization logic
 *
 * Implements block import, vote validation, gossip handlers, and fork choice
 * initialization for the Lantern client.
 *
 * @note Thread safety: Functions that access shared state acquire appropriate
 *       locks as documented. See client_internal.h for lock ordering.
 */

#include "client_internal.h"

#include "lantern/consensus/containers.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/state.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

#include "peer_id/peer_id.h"

#include <inttypes.h>
#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static bool lantern_client_verify_vote_signature(
    const struct lantern_client *client,
    const LanternSignedVote *vote,
    const LanternSignature *signature,
    const struct lantern_log_metadata *meta,
    const char *context);

static bool lantern_client_verify_block_signatures(
    const struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta);


/* ============================================================================
 * Validator Record Access
 * ============================================================================ */

/**
 * Get validator record from genesis registry.
 *
 * @param client        Client instance
 * @param validator_id  Validator index
 * @return Validator record or NULL if not found
 *
 * @note Thread safety: Assumes registry is immutable after init
 */
static const struct lantern_validator_record *lantern_client_get_validator_record(
    const struct lantern_client *client,
    uint64_t validator_id)
{
    if (!client || !client->genesis.validator_registry.records)
    {
        return NULL;
    }
    if (validator_id >= client->genesis.validator_registry.count)
    {
        return NULL;
    }
    return &client->genesis.validator_registry.records[validator_id];
}


/* ============================================================================
 * Enabled Validator Count
 * ============================================================================ */

/**
 * Count enabled local validators.
 *
 * @param client  Client instance
 * @return Number of enabled validators
 *
 * @note Thread safety: Acquires validator_lock
 */
size_t lantern_client_enabled_validator_count(struct lantern_client *client)
{
    if (!client)
    {
        return 0;
    }
    size_t enabled = 0;
    bool locked = false;
    if (client->validator_lock_initialized)
    {
        if (pthread_mutex_lock(&client->validator_lock) == 0)
        {
            locked = true;
        }
    }
    size_t limit = client->local_validator_count;
    if (!client->validator_enabled)
    {
        enabled = limit;
    }
    else
    {
        for (size_t i = 0; i < limit; ++i)
        {
            if (client->validator_enabled[i])
            {
                ++enabled;
            }
        }
    }
    if (locked)
    {
        pthread_mutex_unlock(&client->validator_lock);
    }
    return enabled;
}


/* ============================================================================
 * Vote Signature Verification
 * ============================================================================ */

/**
 * Verify a vote signature using the validator's public key.
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
static bool lantern_client_verify_vote_signature(
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
    // Per LeanSpec: Always use the 52-byte pubkey from state (root || parameter)
    // This matches Zeam's verifyBincode which takes pubkey bytes directly from state.validators[].pubkey
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
 * Block Signature Verification
 * ============================================================================ */

/**
 * Verify all signatures in a signed block.
 *
 * @param client  Client instance
 * @param block   Signed block to verify
 * @param meta    Logging metadata
 * @return true if all signatures are valid
 *
 * @note Thread safety: Thread-safe, reads immutable validator registry
 */
static bool lantern_client_verify_block_signatures(
    const struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block)
    {
        return false;
    }
    const LanternAttestations *attestations = &block->message.block.body.attestations;
    size_t expected_signatures = attestations->length + 1u;
    if (!client->genesis.validator_registry.records)
    {
        return true;
    }
    if (block->signatures.length == 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " missing BlockSignatures; rejecting",
            block->message.block.slot);
        return false;
    }
    if (!block->signatures.data || block->signatures.length != expected_signatures)
    {
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " signature count mismatch expected=%zu actual=%zu",
            block->message.block.slot,
            expected_signatures,
            block->signatures.length);
        return false;
    }
    for (size_t i = 0; i < attestations->length; ++i)
    {
        LanternSignedVote signed_vote;
        memset(&signed_vote, 0, sizeof(signed_vote));
        signed_vote.data = attestations->data[i];
        signed_vote.signature = block->signatures.data[i];
        if (!lantern_client_verify_vote_signature(
                client,
                &signed_vote,
                &signed_vote.signature,
                meta,
                "body"))
        {
            return false;
        }
    }
    LanternSignedVote proposer_signed;
    memset(&proposer_signed, 0, sizeof(proposer_signed));
    proposer_signed.data = block->message.proposer_attestation;
    proposer_signed.signature = block->signatures.data[attestations->length];
    return lantern_client_verify_vote_signature(
        client,
        &proposer_signed,
        &proposer_signed.signature,
        meta,
        "proposer");
}


/* ============================================================================
 * Vote Constraint Validation
 * ============================================================================ */

/**
 * Validate vote constraints against fork choice.
 *
 * Checks that all vote checkpoint roots are known in fork choice
 * and that slot numbers match.
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
 * Block Import
 * ============================================================================ */

/**
 * Import a block into the client state and fork choice.
 *
 * Validates the block, applies state transition, updates fork choice,
 * and persists state.
 *
 * @param client      Client instance
 * @param block       Signed block to import
 * @param block_root  Precomputed block root (may be NULL)
 * @param meta        Logging metadata
 * @return true if block was imported successfully
 *
 * @note Thread safety: Acquires state_lock and pending_lock
 */
bool lantern_client_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block || !client->has_state)
    {
        return false;
    }

    bool state_locked = lantern_client_lock_state(client);
    uint64_t local_slot = client->state.slot;

    LanternRoot hashed_block_root;
    const LanternRoot *effective_block_root = block_root;
    if (!effective_block_root)
    {
        if (lantern_hash_tree_root_block(&block->message.block, &hashed_block_root) != 0)
        {
            lantern_client_unlock_state(client, state_locked);
            lantern_log_warn(
                "state",
                meta,
                "failed to hash block at slot=%" PRIu64,
                block->message.block.slot);
            return false;
        }
        effective_block_root = &hashed_block_root;
    }

    LanternRoot block_root_local = *effective_block_root;

    if (block->message.block.slot < local_slot)
    {
        lantern_client_unlock_state(client, state_locked);
        lantern_log_debug(
            "state",
            meta,
            "ignoring block slot=%" PRIu64 " local_slot=%" PRIu64,
            block->message.block.slot,
            local_slot);
        return false;
    }

    uint64_t known_slot = 0;
    bool root_known = false;
    if (effective_block_root)
    {
        if (state_locked)
        {
            root_known = lantern_client_block_known_locked(client, effective_block_root, &known_slot);
        }
        else if (client->has_fork_choice)
        {
            root_known = (lantern_fork_choice_block_info(&client->fork_choice, effective_block_root, &known_slot, NULL, NULL) == 0);
        }
    }

    if (root_known && block->message.block.slot <= known_slot)
    {
        lantern_client_unlock_state(client, state_locked);
        lantern_log_trace(
            "state",
            meta,
            "skipping known block slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }

    if (block->message.block.slot < local_slot && !root_known)
    {
        lantern_client_unlock_state(client, state_locked);
        lantern_log_debug(
            "state",
            meta,
            "ignoring block slot=%" PRIu64 " local_slot=%" PRIu64,
            block->message.block.slot,
            local_slot);
        return false;
    }

    LanternRoot parent_root_local = block->message.block.parent_root;
    if (!lantern_root_is_zero(&parent_root_local))
    {
        bool parent_known = false;
        bool parent_matches_head = false;
        bool have_head_root = false;
        LanternRoot latest_header_root;
        memset(&latest_header_root, 0, sizeof(latest_header_root));
        if (state_locked)
        {
            parent_known = lantern_client_block_known_locked(client, &parent_root_local, NULL);
            /* Ensure state_root is filled in latest_block_header before computing its hash.
               This is required because state_root is zeroed when a block is applied and only
               filled in lazily by lantern_state_process_slot. Without this, the computed
               header root may differ from what other clients expect. */
            (void)lantern_state_process_slot(&client->state);
            if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &latest_header_root) == 0)
            {
                have_head_root = true;
                parent_matches_head =
                    memcmp(latest_header_root.bytes, parent_root_local.bytes, LANTERN_ROOT_SIZE) == 0;
            }
        }
        else if (client->has_fork_choice)
        {
            parent_known = (lantern_fork_choice_block_info(&client->fork_choice, &parent_root_local, NULL, NULL, NULL) == 0);
        }
        if (!parent_known)
        {
            /* Parent unknown - queue block as pending and request parent */
            const char *peer_text = meta && meta->peer ? meta->peer : NULL;
            lantern_client_unlock_state(client, state_locked);
            lantern_client_enqueue_pending_block(client, block, &block_root_local, &parent_root_local, peer_text);
            return false;
        }
        if (!parent_matches_head)
        {
            /*
             * Parent is known in fork choice but doesn't match our current head.
             * This indicates a competing fork. Per leanSpec, we should still add
             * the block to fork choice so attestations can reference it and fork
             * choice can properly determine which chain has more weight.
             *
             * We add the block to fork choice (without post-state checkpoints since
             * we can't compute state transition), then queue it for later processing.
             * If fork choice later determines this is the better chain, pending block
             * processing will handle the reorg.
             */
            const char *peer_text = meta && meta->peer ? meta->peer : NULL;
            char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            if (have_head_root)
            {
                format_root_hex(&parent_root_local, parent_hex, sizeof(parent_hex));
                format_root_hex(&latest_header_root, head_hex, sizeof(head_hex));
                lantern_log_debug(
                    "state",
                    meta,
                    "block on competing fork slot=%" PRIu64 " parent=%s current_head=%s",
                    block->message.block.slot,
                    parent_hex[0] ? parent_hex : "0x0",
                    head_hex[0] ? head_hex : "0x0");
            }

            /* Add block to fork choice even without state transition so fork choice
             * can track competing chains and attestations can reference this block */
            if (client->has_fork_choice)
            {
                LanternSignedVote proposer_signed;
                memset(&proposer_signed, 0, sizeof(proposer_signed));
                proposer_signed.data = block->message.proposer_attestation;
                size_t proposer_index = block->message.block.body.attestations.length;
                if (block->signatures.length > proposer_index && block->signatures.data)
                {
                    proposer_signed.signature = block->signatures.data[proposer_index];
                }
                if (lantern_fork_choice_add_block(
                        &client->fork_choice,
                        &block->message.block,
                        &proposer_signed,
                        NULL, /* No post-justified - we can't compute state transition */
                        NULL, /* No post-finalized */
                        &block_root_local) == 0)
                {
                    char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
                    format_root_hex(&block_root_local, block_hex, sizeof(block_hex));
                    lantern_log_info(
                        "forkchoice",
                        meta,
                        "added competing fork block to fork choice slot=%" PRIu64 " root=%s",
                        block->message.block.slot,
                        block_hex[0] ? block_hex : "0x0");
                }
            }

            lantern_client_unlock_state(client, state_locked);
            lantern_client_enqueue_pending_block(client, block, &block_root_local, &parent_root_local, peer_text);
            return false;
        }
    }

    if (!lantern_client_verify_block_signatures(client, block, meta))
    {
        lantern_client_unlock_state(client, state_locked);
        return false;
    }

    if (client->has_fork_choice)
    {
        const LanternAttestations *attestations = &block->message.block.body.attestations;
        for (size_t i = 0; i < attestations->length; ++i)
        {
            if (!lantern_client_validate_vote_constraints(
                    client,
                    &attestations->data[i],
                    "state",
                    meta,
                    "block attestation",
                    NULL))
            {
                lantern_client_unlock_state(client, state_locked);
                return false;
            }
        }
        /* Skip proposer attestation validation here - the proposer's head checkpoint
         * references the block being imported, which isn't in fork choice yet.
         * The proposer attestation will be validated during state transition. */
    }

    LanternSignedBlock import_block = *block;

    if (lantern_state_transition(&client->state, &import_block) != 0)
    {
        lantern_client_unlock_state(client, state_locked);
        lantern_log_warn(
            "state",
            meta,
            "state transition failed for slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }

    if (client->has_fork_choice)
    {
        uint64_t now_seconds = validator_wall_time_now_seconds();
        if (lantern_fork_choice_advance_time(&client->fork_choice, now_seconds, false) != 0)
        {
            lantern_log_debug(
                "forkchoice",
                meta,
                "advancing fork choice time failed after slot=%" PRIu64,
                block->message.block.slot);
        }
    }

    uint64_t head_slot = client->state.slot;
    LanternRoot head_root;
    memset(&head_root, 0, sizeof(head_root));
    if (client->has_fork_choice)
    {
        if (lantern_fork_choice_current_head(&client->fork_choice, &head_root) == 0)
        {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(&client->fork_choice, &head_root, &fork_slot, NULL, NULL) == 0)
            {
                head_slot = fork_slot;
            }
        }
    }

    if (client->data_dir)
    {
        if (lantern_storage_save_state(client->data_dir, &client->state) != 0)
        {
            lantern_log_warn(
                "storage",
                meta,
                "failed to persist state after slot=%" PRIu64,
                client->state.slot);
        }
        if (lantern_storage_save_votes(client->data_dir, &client->state) != 0)
        {
            lantern_log_warn(
                "storage",
                meta,
                "failed to persist votes after slot=%" PRIu64,
                client->state.slot);
        }
    }

    lantern_client_unlock_state(client, state_locked);

    lantern_client_pending_remove_by_root(client, &block_root_local);
    lantern_client_process_pending_children(client, &block_root_local);

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&head_root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "state",
        meta,
        "imported block slot=%" PRIu64 " new_head_slot=%" PRIu64 " head_root=%s",
        block->message.block.slot,
        head_slot,
        head_hex[0] ? head_hex : "0x0");

    return true;
}


/* ============================================================================
 * Block Recording
 * ============================================================================ */

/**
 * Record a received block and attempt import.
 *
 * @param client    Client instance
 * @param block     Signed block to record
 * @param root      Precomputed block root (may be NULL)
 * @param peer_text Peer ID string (may be NULL)
 * @param context   Description of source for logging
 *
 * @note Thread safety: Acquires state_lock via lantern_client_import_block
 */
void lantern_client_record_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    const char *context)
{
    if (!client || !block)
    {
        return;
    }

    LanternRoot computed_root;
    const LanternRoot *selected_root = root;
    if (!selected_root)
    {
        if (lantern_hash_tree_root_block(&block->message.block, &computed_root) != 0)
        {
            return;
        }
        selected_root = &computed_root;
    }

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(selected_root, root_hex, sizeof(root_hex));

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_text && *peer_text ? peer_text : NULL,
    };
    const char *source = NULL;
    if (context && *context)
    {
        source = context;
    }
    else if (peer_text && *peer_text)
    {
        source = "peer";
    }
    else
    {
        source = "local";
    }

    lantern_log_info(
        "gossip",
        &meta,
        "received block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s source=%s",
        block->message.block.slot,
        block->message.block.proposer_index,
        root_hex[0] ? root_hex : "0x0",
        source);

    if (client->data_dir)
    {
        if (lantern_storage_store_block(client->data_dir, block) != 0)
        {
            lantern_log_warn(
                "storage",
                &meta,
                "failed to persist block slot=%" PRIu64,
                block->message.block.slot);
        }
    }

    lantern_client_import_block(client, block, selected_root, &meta);
}


/* ============================================================================
 * Vote Recording
 * ============================================================================ */

/**
 * Record and process a received vote.
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


/* ============================================================================
 * Gossip Handlers
 * ============================================================================ */

/**
 * Handle a block received via gossip.
 *
 * @param block    Received block
 * @param from     Peer ID of sender
 * @param context  Client instance
 * @return 0 on success
 */
int gossip_block_handler(
    const LanternSignedBlock *block,
    const peer_id_t *from,
    void *context)
{
    if (!block || !context)
    {
        return -1;
    }
    struct lantern_client *client = context;

    char peer_text[128];
    peer_text[0] = '\0';
    if (from && peer_id_to_string(from, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
    {
        peer_text[0] = '\0';
    }

    lantern_client_record_block(client, block, NULL, peer_text[0] ? peer_text : NULL, "gossip");
    return 0;
}


/**
 * Handle a vote received via gossip.
 *
 * @param vote     Received vote
 * @param from     Peer ID of sender
 * @param context  Client instance
 * @return 0 on success
 */
int gossip_vote_handler(
    const LanternSignedVote *vote,
    const peer_id_t *from,
    void *context)
{
    if (!vote || !context)
    {
        return -1;
    }
    struct lantern_client *client = context;
    char peer_text[128];
    peer_text[0] = '\0';
    if (from)
    {
        if (peer_id_to_string(from, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
        {
            peer_text[0] = '\0';
        }
    }
    const char *peer_id_text = peer_text[0] ? peer_text : NULL;
    lantern_client_note_vote_delivery(client, peer_id_text, vote);
    lantern_client_record_vote(client, vote, peer_id_text);
    return 0;
}


/* ============================================================================
 * Anchor Block Persistence
 * ============================================================================ */

/**
 * Persist anchor block to storage.
 *
 * @param client        Client instance
 * @param anchor_block  Anchor block to persist
 * @param anchor_root   Anchor block root
 *
 * @note Thread safety: Thread-safe
 */
void persist_anchor_block(
    struct lantern_client *client,
    const LanternBlock *anchor_block,
    const LanternRoot *anchor_root)
{
    if (!client || !client->data_dir || !anchor_block)
    {
        return;
    }

    LanternSignedBlock stored_anchor;
    lantern_signed_block_with_attestation_init(&stored_anchor);
    LanternBlock *block = &stored_anchor.message.block;
    block->slot = anchor_block->slot;
    block->proposer_index = anchor_block->proposer_index;
    block->parent_root = anchor_block->parent_root;
    block->state_root = anchor_block->state_root;

    LanternRoot computed_root;
    const LanternRoot *root_to_log = anchor_root;
    if (!root_to_log)
    {
        if (lantern_hash_tree_root_block(block, &computed_root) == 0)
        {
            root_to_log = &computed_root;
        }
    }
    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    root_hex[0] = '\0';
    if (root_to_log)
    {
        format_root_hex(root_to_log, root_hex, sizeof(root_hex));
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (lantern_storage_store_block(client->data_dir, &stored_anchor) != 0)
    {
        lantern_log_warn(
            "storage",
            &meta,
            "failed to persist genesis anchor block root=%s",
            root_hex[0] ? root_hex : "0x0");
    }
    else
    {
        lantern_log_debug(
            "storage",
            &meta,
            "persisted genesis anchor block root=%s",
            root_hex[0] ? root_hex : "0x0");
    }
    lantern_signed_block_with_attestation_reset(&stored_anchor);
}


/* ============================================================================
 * Fork Choice Initialization
 * ============================================================================ */

/**
 * Initialize fork choice from genesis state.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Should be called during initialization
 */
int initialize_fork_choice(struct lantern_client *client)
{
    if (!client || !client->has_state)
    {
        return -1;
    }
    lantern_fork_choice_reset(&client->fork_choice);
    if (lantern_fork_choice_configure(&client->fork_choice, &client->state.config) != 0)
    {
        lantern_log_error(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to configure fork choice");
        return -1;
    }

    LanternRoot anchor_state_root;
    if (lantern_hash_tree_root_state(&client->state, &anchor_state_root) != 0)
    {
        lantern_log_error(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to hash anchor state");
        return -1;
    }

    /* Create a copy of the header for computing anchor_root.
     *
     * According to leanSpec's Store.get_forkchoice_store, the anchor block
     * used for fork choice MUST have state_root = hash_tree_root(state).
     * This is different from the state's latest_block_header which starts
     * with state_root = ZERO.
     *
     * We compute anchor_root from a header with the ACTUAL state_root,
     * matching Zeam's genStateBlockHeader() behavior.
     */
    LanternBlockHeader anchor_header = client->state.latest_block_header;
    anchor_header.state_root = anchor_state_root;

    LanternRoot anchor_root;
    if (lantern_hash_tree_root_block_header(&anchor_header, &anchor_root) != 0)
    {
        lantern_log_error(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to hash anchor block header");
        return -1;
    }

    /* Log the anchor root for debugging genesis mismatch issues */
    {
        char anchor_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char state_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char body_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&anchor_root, anchor_root_hex, sizeof(anchor_root_hex));
        format_root_hex(&anchor_state_root, state_root_hex, sizeof(state_root_hex));
        format_root_hex(&anchor_header.body_root, body_root_hex, sizeof(body_root_hex));
        lantern_log_info(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "genesis anchor_root=%s state_root=%s body_root=%s slot=%lu",
            anchor_root_hex,
            state_root_hex,
            body_root_hex,
            (unsigned long)anchor_header.slot);
    }

    /* Also update the state's header state_root for subsequent state transitions */
    if (memcmp(
            client->state.latest_block_header.state_root.bytes,
            anchor_state_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0)
    {
        client->state.latest_block_header.state_root = anchor_state_root;
        lantern_log_debug(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "updated genesis header state_root");
    }

    LanternBlock anchor;
    memset(&anchor, 0, sizeof(anchor));
    anchor.slot = client->state.latest_block_header.slot;
    anchor.proposer_index = client->state.latest_block_header.proposer_index;
    anchor.parent_root = client->state.latest_block_header.parent_root;
    anchor.state_root = anchor_state_root;
    lantern_block_body_init(&anchor.body);

    if (lantern_fork_choice_set_anchor(
            &client->fork_choice,
            &anchor,
            &client->state.latest_justified,
            &client->state.latest_finalized,
            &anchor_root)
        != 0)
    {
        lantern_block_body_reset(&anchor.body);
        lantern_log_error(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to set fork choice anchor");
        return -1;
    }
    if (memcmp(client->state.latest_justified.root.bytes, anchor_root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        client->state.latest_justified.root = anchor_root;
        lantern_log_debug(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "updated justified checkpoint root to anchor");
    }
    if (memcmp(client->state.latest_finalized.root.bytes, anchor_root.bytes, LANTERN_ROOT_SIZE) != 0)
    {
        client->state.latest_finalized.root = anchor_root;
        lantern_log_debug(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "updated finalized checkpoint root to anchor");
    }
    persist_anchor_block(client, &anchor, &anchor_root);
    lantern_block_body_reset(&anchor.body);
    lantern_state_attach_fork_choice(&client->state, &client->fork_choice);
    client->has_fork_choice = true;
    return 0;
}


/* ============================================================================
 * Block Restoration from Storage
 * ============================================================================ */

/**
 * Visitor callback for storage block iteration.
 */
static int collect_block_visitor(
    const LanternSignedBlock *block,
    const LanternRoot *root,
    void *context)
{
    struct lantern_persisted_block_list *list = context;
    return persisted_block_list_append(list, block, root);
}


/**
 * Compare persisted blocks by slot for sorting.
 */
static int compare_blocks_by_slot(const void *lhs_ptr, const void *rhs_ptr)
{
    const struct lantern_persisted_block *lhs = lhs_ptr;
    const struct lantern_persisted_block *rhs = rhs_ptr;
    if (lhs->block.message.block.slot < rhs->block.message.block.slot)
    {
        return -1;
    }
    if (lhs->block.message.block.slot > rhs->block.message.block.slot)
    {
        return 1;
    }
    return memcmp(lhs->root.bytes, rhs->root.bytes, LANTERN_ROOT_SIZE);
}


/**
 * Restore persisted blocks from storage into fork choice.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Should be called during initialization
 */
int restore_persisted_blocks(struct lantern_client *client)
{
    if (!client || !client->has_state || !client->data_dir || !client->has_fork_choice)
    {
        return 0;
    }
    struct lantern_persisted_block_list list;
    persisted_block_list_init(&list);
    int iterate_rc = lantern_storage_iterate_blocks(client->data_dir, collect_block_visitor, &list);
    if (iterate_rc < 0)
    {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to enumerate persisted blocks");
        persisted_block_list_reset(&list);
        return -1;
    }
    if (list.length == 0)
    {
        persisted_block_list_reset(&list);
        return 0;
    }
    qsort(list.items, list.length, sizeof(list.items[0]), compare_blocks_by_slot);

    for (size_t i = 0; i < list.length; ++i)
    {
        const struct lantern_persisted_block *entry = &list.items[i];
        LanternSignedVote persisted_proposer;
        memset(&persisted_proposer, 0, sizeof(persisted_proposer));
        persisted_proposer.data = entry->block.message.proposer_attestation;
        size_t proposer_index = entry->block.message.block.body.attestations.length;
        if (entry->block.signatures.length > proposer_index && entry->block.signatures.data)
        {
            persisted_proposer.signature = entry->block.signatures.data[proposer_index];
        }
        if (lantern_fork_choice_add_block(
                &client->fork_choice,
                &entry->block.message.block,
                &persisted_proposer,
                &client->state.latest_justified,
                &client->state.latest_finalized,
                &entry->root)
            != 0)
        {
            lantern_log_warn(
                "forkchoice",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to restore block at slot %" PRIu64,
                entry->block.message.block.slot);
        }
    }

    uint64_t now_seconds = validator_wall_time_now_seconds();
    if (lantern_fork_choice_advance_time(&client->fork_choice, now_seconds, false) != 0)
    {
        lantern_log_warn(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "advancing fork choice time after restore failed");
    }

    persisted_block_list_reset(&list);
    return 0;
}


/* ============================================================================
 * Validator State Refresh
 * ============================================================================ */

/**
 * Refresh state validator pubkeys from genesis registry.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Acquires validator_lock
 */
int lantern_client_refresh_state_validators(struct lantern_client *client)
{
    if (!client || !client->has_state)
    {
        return -1;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    struct lantern_validator_registry *registry = &client->genesis.validator_registry;
    size_t registry_count = registry->count;
    size_t state_count = lantern_state_validator_count(&client->state);

    bool have_registry = registry->records && registry_count > 0;
    if (!have_registry)
    {
        if (state_count == 0)
        {
            return lantern_state_set_validator_pubkeys(&client->state, NULL, 0);
        }
        lantern_log_info(
            "client",
            &meta,
            "validator registry missing; retaining existing state pubkeys count=%zu",
            state_count);
        return 0;
    }

    if (state_count > 0 && state_count != registry_count)
    {
        lantern_log_warn(
            "client",
            &meta,
            "validator count mismatch registry=%zu state=%zu",
            registry_count,
            state_count);
    }

    size_t count = registry_count;
    size_t total_bytes = count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *packed = malloc(total_bytes);
    if (!packed)
    {
        return -1;
    }
    size_t registry_used = 0;
    size_t state_used = 0;
    size_t missing_pubkeys = 0;
    for (size_t i = 0; i < count; ++i)
    {
        struct lantern_validator_record *record = &registry->records[i];
        const uint8_t *registry_pub =
            (record && record->has_pubkey_bytes && !lantern_validator_pubkey_is_zero(record->pubkey_bytes))
                ? record->pubkey_bytes
                : NULL;
        const uint8_t *state_pub = (state_count > i) ? lantern_state_validator_pubkey(&client->state, i) : NULL;
        if (state_pub && lantern_validator_pubkey_is_zero(state_pub))
        {
            state_pub = NULL;
        }

        const uint8_t *chosen = registry_pub ? registry_pub : state_pub;
        if (chosen)
        {
            memcpy(packed + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), chosen, LANTERN_VALIDATOR_PUBKEY_SIZE);
            if (!registry_pub && state_pub && record)
            {
                memcpy(record->pubkey_bytes, state_pub, LANTERN_VALIDATOR_PUBKEY_SIZE);
                record->has_pubkey_bytes = true;
                char hex[(LANTERN_VALIDATOR_PUBKEY_SIZE * 2u) + 3u];
                if (lantern_bytes_to_hex(
                        state_pub,
                        LANTERN_VALIDATOR_PUBKEY_SIZE,
                        hex,
                        sizeof(hex),
                        1)
                    == 0)
                {
                    free(record->pubkey_hex);
                    record->pubkey_hex = lantern_string_duplicate(hex);
                }
                ++state_used;
            }
            else if (registry_pub)
            {
                ++registry_used;
            }
        }
        else
        {
            memset(packed + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), 0, LANTERN_VALIDATOR_PUBKEY_SIZE);
            ++missing_pubkeys;
        }
    }
    int rc = lantern_state_set_validator_pubkeys(&client->state, packed, count);
    free(packed);
    if (rc != 0)
    {
        lantern_log_warn(
            "client",
            &meta,
            "failed to copy validator pubkeys into parent state");
        return -1;
    }
    size_t enabled = lantern_client_enabled_validator_count(client);
    lantern_log_info(
        "client",
        &meta,
        "refreshed validator pubkeys count=%zu registry=%zu state_fallback=%zu missing=%zu local_validators=%zu enabled=%zu",
        count,
        registry_used,
        state_used,
        missing_pubkeys,
        client->local_validator_count,
        enabled);
    return 0;
}


/* ============================================================================
 * Pending Block Management
 * ============================================================================ */

/**
 * Remove a pending block by root (internal, no locking).
 */
static void lantern_client_pending_remove_by_root_locked(
    struct lantern_client *client,
    const LanternRoot *root)
{
    if (!client || !root)
    {
        return;
    }
    struct lantern_pending_block_list *list = &client->pending_blocks;
    if (!list->items)
    {
        return;
    }
    for (size_t i = 0; i < list->length; ++i)
    {
        if (memcmp(list->items[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            pending_block_list_remove(list, i);
            break;
        }
    }
}


/**
 * Remove a pending block by root.
 *
 * @param client  Client instance
 * @param root    Block root to remove
 *
 * @note Thread safety: Acquires pending_lock
 */
void lantern_client_pending_remove_by_root(struct lantern_client *client, const LanternRoot *root)
{
    if (!client || !root)
    {
        return;
    }
    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        lantern_client_pending_remove_by_root_locked(client, root);
        return;
    }
    lantern_client_pending_remove_by_root_locked(client, root);
    lantern_client_unlock_pending(client, locked);
}


/**
 * Enqueue a pending block for later processing.
 *
 * @param client       Client instance
 * @param block        Block to enqueue
 * @param block_root   Block root
 * @param parent_root  Parent block root
 * @param peer_text    Peer ID string (may be NULL)
 *
 * @note Thread safety: Acquires pending_lock
 */
void lantern_client_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text)
{
    if (!client || !block || !block_root || !parent_root)
    {
        return;
    }

    LanternRoot block_root_local = *block_root;
    LanternRoot parent_root_local = *parent_root;
    char schedule_peer[128];
    schedule_peer[0] = '\0';
    bool schedule_parent = false;

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return;
    }

    struct lantern_pending_block_list *list = &client->pending_blocks;
    struct lantern_pending_block *existing = pending_block_list_find(list, &block_root_local);

    if (existing)
    {
        if (peer_text && *peer_text)
        {
            if (existing->peer_text[0] == '\0' || strcmp(existing->peer_text, peer_text) != 0)
            {
                strncpy(existing->peer_text, peer_text, sizeof(existing->peer_text) - 1u);
                existing->peer_text[sizeof(existing->peer_text) - 1u] = '\0';
            }
            /* Do NOT immediately request parent via req/resp - rely on gossip to deliver it.
               req/resp should only be used for sync recovery, not for normal block propagation. */
        }
        lantern_client_unlock_pending(client, locked);
        return;
    }

    if (list->length >= LANTERN_PENDING_BLOCK_LIMIT && list->length > 0)
    {
        char dropped_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&list->items[0].root, dropped_hex, sizeof(dropped_hex));
        lantern_log_warn(
            "state",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pending block queue full; dropping oldest root=%s",
            dropped_hex[0] ? dropped_hex : "0x0");
        pending_block_list_remove(list, 0);
    }

    struct lantern_pending_block *entry =
        pending_block_list_append(list, block, &block_root_local, &parent_root_local, peer_text);
    if (!entry)
    {
        lantern_client_unlock_pending(client, locked);
        lantern_log_warn(
            "state",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to queue pending block slot=%" PRIu64,
            block->message.block.slot);
        return;
    }

    char block_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    char parent_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&block_root_local, block_hex, sizeof(block_hex));
    format_root_hex(&parent_root_local, parent_hex, sizeof(parent_hex));

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_text && *peer_text ? peer_text : NULL,
    };

    /* Do NOT immediately request parent via req/resp - rely on gossip to deliver it.
       req/resp should only be used for sync recovery, not for normal block propagation.
       The parent_requested flag is no longer used for immediate requests. */
    entry->parent_requested = false;
    (void)schedule_peer;
    (void)schedule_parent;

    lantern_client_unlock_pending(client, locked);

    lantern_log_info(
        "state",
        &meta,
        "queued block slot=%" PRIu64 " root=%s waiting for parent=%s (via gossip)",
        block->message.block.slot,
        block_hex[0] ? block_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0");
}


/**
 * Process pending children of a newly imported block.
 *
 * @param client       Client instance
 * @param parent_root  Root of the newly imported parent block
 *
 * @note Thread safety: Acquires pending_lock and state_lock
 */
void lantern_client_process_pending_children(struct lantern_client *client, const LanternRoot *parent_root)
{
    if (!client || !parent_root)
    {
        return;
    }
    while (true)
    {
        LanternSignedBlock replay;
        LanternRoot child_root;
        char peer_copy[128];
        bool have_replay = false;

        bool locked = lantern_client_lock_pending(client);
        if (!locked)
        {
            return;
        }

        for (size_t i = 0; i < client->pending_blocks.length; ++i)
        {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            if (memcmp(entry->parent_root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) != 0)
            {
                continue;
            }
            if (clone_signed_block(&entry->block, &replay) != 0)
            {
                lantern_log_warn(
                    "state",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "failed to clone pending child block for replay");
            }
            else
            {
                child_root = entry->root;
                peer_copy[0] = '\0';
                if (entry->peer_text[0])
                {
                    strncpy(peer_copy, entry->peer_text, sizeof(peer_copy) - 1u);
                    peer_copy[sizeof(peer_copy) - 1u] = '\0';
                }
                have_replay = true;
            }
            pending_block_list_remove(&client->pending_blocks, i);
            break;
        }

        lantern_client_unlock_pending(client, locked);

        if (!have_replay)
        {
            break;
        }

        struct lantern_log_metadata meta = {
            .validator = client->node_id,
            .peer = peer_copy[0] ? peer_copy : NULL,
        };
        (void)lantern_client_import_block(client, &replay, &child_root, &meta);
        lantern_signed_block_with_attestation_reset(&replay);
    }
}
