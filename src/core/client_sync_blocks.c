/**
 * @file client_sync_blocks.c
 * @brief Block import and signature verification
 *
 * @spec subspecs/containers/block/block.py in tools/leanSpec
 * @spec subspecs/containers/state/state.py - state_transition() in tools/leanSpec
 * @spec subspecs/forkchoice/store.py - on_block() in tools/leanSpec
 *
 * Implements block signature verification, import into fork choice,
 * state transitions, and block recording.
 *
 * Related files:
 * - client_sync.c: Main sync logic and gossip handlers
 * - client_sync_votes.c: Vote processing
 *
 * @note Thread safety: Functions that access shared state acquire appropriate
 *       locks as documented. See client_internal.h for lock ordering.
 */

#include "client_internal.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/state.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

enum
{
    ROOT_HEX_BUFFER_LEN = (LANTERN_ROOT_SIZE * 2u) + 3u,
};


/* ============================================================================
 * External Functions (from client_sync_votes.c)
 * ============================================================================ */

extern bool lantern_client_verify_vote_signature(
    const struct lantern_client *client,
    const LanternSignedVote *vote,
    const LanternSignature *signature,
    const struct lantern_log_metadata *meta,
    const char *context);


/* ============================================================================
 * Block Signature Verification
 * ============================================================================ */

/**
 * Verify all signatures in a signed block.
 *
 * @spec subspecs/containers/block/block.py - SignedBlock structure
 * @spec subspecs/xmss/signature.py - XMSS signature verification
 *
 * Verifies all signatures in a signed block:
 * 1. Proposer signature (last in the signatures array)
 * 2. All attestation signatures (one per attestation in body)
 *
 * The signatures array must contain exactly N+1 signatures where N
 * is the number of attestations in the block body.
 *
 * @param client  Client instance
 * @param block   Signed block to verify
 * @param meta    Logging metadata
 * @return true if all signatures are valid
 *
 * @note Thread safety: Thread-safe, reads immutable validator registry
 */
static bool signed_block_signatures_are_valid(
    const struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block)
    {
        return false;
    }
    const LanternAttestations *attestations = &block->message.block.body.attestations;
    if (attestations->length > SIZE_MAX - 1u)
    {
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " attestation count overflow length=%zu",
            block->message.block.slot,
            attestations->length);
        return false;
    }
    size_t expected_signatures = attestations->length + 1u;
    if (!client->genesis.validator_registry.records)
    {
        return true;
    }
    if (attestations->length > 0 && !attestations->data)
    {
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " attestations missing data length=%zu",
            block->message.block.slot,
            attestations->length);
        return false;
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
        LanternSignedVote signed_vote = {0};
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
    LanternSignedVote proposer_signed = {0};
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
 * Block Import Helpers
 * ============================================================================ */

/**
 * @brief Computes the block root if not provided.
 *
 * @param block        Signed block to hash
 * @param provided     Optional precomputed root
 * @param out_root     Output root (filled on success)
 * @param meta         Logging metadata
 * @return true on success, false on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static bool get_block_root_local(
    const LanternSignedBlock *block,
    const LanternRoot *provided,
    LanternRoot *out_root,
    const struct lantern_log_metadata *meta)
{
    if (!block || !out_root)
    {
        return false;
    }
    if (provided)
    {
        *out_root = *provided;
        return true;
    }
    if (lantern_hash_tree_root_block(&block->message.block, out_root) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to hash block at slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }
    return true;
}


/**
 * @brief Returns true if the block should be processed.
 *
 * @param slot        Block slot
 * @param local_slot  Client state slot
 * @param root_known  Whether the block root is known
 * @param known_slot  Slot of the known root (if root_known)
 * @param meta        Logging metadata
 * @return true if block should be processed, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
static bool should_process_block(
    uint64_t slot,
    uint64_t local_slot,
    bool root_known,
    uint64_t known_slot,
    const struct lantern_log_metadata *meta)
{
    if (root_known && slot <= known_slot)
    {
        lantern_log_trace("state", meta, "skipping known block slot=%" PRIu64, slot);
        return false;
    }
    if (slot < local_slot && !root_known)
    {
        lantern_log_debug(
            "state",
            meta,
            "ignoring block slot=%" PRIu64 " local_slot=%" PRIu64,
            slot,
            local_slot);
        return false;
    }
    return true;
}


/**
 * Handle parent tracking and competing forks.
 *
 * @param client       Client instance
 * @param block        Block being imported
 * @param block_root   Root of the block
 * @param meta         Logging metadata
 * @param state_locked In/out state lock flag (may be cleared if unlocked here)
 * @return true if import should continue, false if deferred or on error
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool handle_block_parent_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    bool *state_locked)
{
    if (!client || !block || !block_root || !state_locked || !*state_locked)
    {
        return false;
    }

    LanternRoot parent_root = block->message.block.parent_root;
    if (lantern_root_is_zero(&parent_root))
    {
        return true;
    }

    bool parent_known = lantern_client_block_known_locked(client, &parent_root, NULL);
    if (!parent_known)
    {
        const char *peer_text = meta && meta->peer ? meta->peer : NULL;
        lantern_client_unlock_state(client, *state_locked);
        *state_locked = false;
        lantern_client_enqueue_pending_block(client, block, block_root, &parent_root, peer_text);
        return false;
    }

    bool have_head_root = false;
    bool parent_matches_head = false;
    LanternRoot latest_header_root = {0};

    /* Ensure state_root is filled in latest_block_header before computing its hash.
       This is required because state_root is zeroed when a block is applied and only
       filled in lazily by lantern_state_process_slot. Without this, the computed
       header root may differ from what other clients expect. */
    if (lantern_state_process_slot(&client->state) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to compute cached header state root at slot=%" PRIu64,
            client->state.slot);
    }
    else if (lantern_hash_tree_root_block_header(
                 &client->state.latest_block_header,
                 &latest_header_root) == 0)
    {
        have_head_root = true;
        parent_matches_head =
            memcmp(latest_header_root.bytes, parent_root.bytes, LANTERN_ROOT_SIZE) == 0;
    }

    if (parent_matches_head)
    {
        return true;
    }

    const char *peer_text = meta && meta->peer ? meta->peer : NULL;

    if (have_head_root)
    {
        char parent_hex[ROOT_HEX_BUFFER_LEN];
        char head_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
        format_root_hex(&latest_header_root, head_hex, sizeof(head_hex));
        lantern_log_debug(
            "state",
            meta,
            "block on competing fork slot=%" PRIu64 " parent=%s current_head=%s",
            block->message.block.slot,
            parent_hex[0] ? parent_hex : "0x0",
            head_hex[0] ? head_hex : "0x0");
    }

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
    if (client->has_fork_choice)
    {
        LanternSignedVote proposer_signed = {0};
        proposer_signed.data = block->message.proposer_attestation;

        size_t proposer_index = block->message.block.body.attestations.length;
        if (block->signatures.data && block->signatures.length > proposer_index)
        {
            proposer_signed.signature = block->signatures.data[proposer_index];
        }

        if (lantern_fork_choice_add_block(
                &client->fork_choice,
                &block->message.block,
                &proposer_signed,
                NULL, /* No post-justified - we can't compute state transition */
                NULL, /* No post-finalized */
                block_root) == 0)
        {
            char block_hex[ROOT_HEX_BUFFER_LEN];
            format_root_hex(block_root, block_hex, sizeof(block_hex));
            lantern_log_info(
                "forkchoice",
                meta,
                "added competing fork block to fork choice slot=%" PRIu64 " root=%s",
                block->message.block.slot,
                block_hex[0] ? block_hex : "0x0");
        }
    }

    lantern_client_unlock_state(client, *state_locked);
    *state_locked = false;
    lantern_client_enqueue_pending_block(client, block, block_root, &parent_root, peer_text);
    return false;
}


/**
 * @brief Validates attestation constraints for the block.
 *
 * @param client  Client instance
 * @param block   Signed block
 * @param meta    Logging metadata
 * @return true if constraints pass, false otherwise
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool validate_block_vote_constraints_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block)
    {
        return false;
    }
    if (!client->has_fork_choice)
    {
        return true;
    }

    const LanternAttestations *attestations = &block->message.block.body.attestations;
    if (attestations->length > 0 && !attestations->data)
    {
        lantern_log_warn(
            "state",
            meta,
            "block slot=%" PRIu64 " attestations missing data length=%zu",
            block->message.block.slot,
            attestations->length);
        return false;
    }

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
            return false;
        }
    }

    /* Skip proposer attestation validation here - the proposer's head checkpoint
     * references the block being imported, which isn't in fork choice yet.
     * The proposer attestation will be validated during state transition. */
    return true;
}


/**
 * @brief Applies the state transition for a block.
 *
 * @param client  Client instance
 * @param block   Signed block to import
 * @param meta    Logging metadata
 * @return true on success, false on failure
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool apply_state_transition_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block)
    {
        return false;
    }

    LanternSignedBlock import_block = *block;
    if (lantern_state_transition(&client->state, &import_block) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "state transition failed for slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }

    return true;
}


/**
 * @brief Advances fork choice time after a successful import.
 *
 * @param client  Client instance
 * @param block   Imported block (for logging)
 * @param meta    Logging metadata
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void advance_fork_choice_time_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block || !client->has_fork_choice)
    {
        return;
    }

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


/**
 * @brief Computes head slot/root for logging.
 *
 * @param client        Client instance
 * @param out_head_root Output head root
 * @param out_head_slot Output head slot
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void get_head_info_locked(
    struct lantern_client *client,
    LanternRoot *out_head_root,
    uint64_t *out_head_slot)
{
    if (!client || !out_head_root || !out_head_slot)
    {
        return;
    }

    *out_head_slot = client->state.slot;
    *out_head_root = (LanternRoot){0};
    if (!client->has_fork_choice)
    {
        return;
    }

    if (lantern_fork_choice_current_head(&client->fork_choice, out_head_root) != 0)
    {
        return;
    }

    uint64_t fork_slot = 0;
    if (lantern_fork_choice_block_info(
            &client->fork_choice,
            out_head_root,
            &fork_slot,
            NULL,
            NULL) == 0)
    {
        *out_head_slot = fork_slot;
    }
}


/**
 * @brief Persists client state/votes if storage is enabled.
 *
 * @param client  Client instance
 * @param meta    Logging metadata
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void persist_state_locked(
    const struct lantern_client *client,
    const struct lantern_log_metadata *meta)
{
    if (!client || !client->data_dir)
    {
        return;
    }

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


/**
 * @brief Logs a successful block import.
 *
 * @param block      Imported block
 * @param head_root  New head root
 * @param head_slot  New head slot
 * @param meta       Logging metadata
 *
 * @note Thread safety: This function is thread-safe
 */
static void log_imported_block(
    const LanternSignedBlock *block,
    const LanternRoot *head_root,
    uint64_t head_slot,
    const struct lantern_log_metadata *meta)
{
    if (!block || !head_root)
    {
        return;
    }

    char head_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(head_root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "state",
        meta,
        "imported block slot=%" PRIu64 " new_head_slot=%" PRIu64 " head_root=%s",
        block->message.block.slot,
        head_slot,
        head_hex[0] ? head_hex : "0x0");
}


/* ============================================================================
 * Block Import
 * ============================================================================ */

/**
 * Import a block into the client state and fork choice.
 *
 * @spec subspecs/containers/state/state.py - State.state_transition()
 * @spec subspecs/forkchoice/store.py - Store.on_block()
 *
 * Performs the complete block import pipeline:
 * 1. Validates block slot against local state
 * 2. Checks if block root is already known
 * 3. Handles parent tracking:
 *    - Unknown parent: queue as pending
 *    - Parent on competing fork: add to fork choice without state transition
 *    - Parent matches head: proceed with full import
 * 4. Verifies all block signatures
 * 5. Validates attestation constraints
 * 6. Applies state transition
 * 7. Updates fork choice
 * 8. Persists state and votes
 * 9. Processes pending children
 *
 * Per leanSpec: Blocks on competing forks are added to fork choice so
 * attestations can reference them and fork choice can determine which
 * chain has more weight.
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

    bool imported = false;
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to acquire state lock for block import slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }

    uint64_t local_slot = client->state.slot;
    LanternRoot block_root_local = {0};
    LanternRoot head_root = {0};
    uint64_t head_slot = 0;

    if (!get_block_root_local(block, block_root, &block_root_local, meta))
    {
        goto cleanup;
    }

    uint64_t known_slot = 0;
    bool root_known = lantern_client_block_known_locked(client, &block_root_local, &known_slot);
    if (!should_process_block(block->message.block.slot, local_slot, root_known, known_slot, meta))
    {
        goto cleanup;
    }

    if (!handle_block_parent_locked(client, block, &block_root_local, meta, &state_locked))
    {
        goto cleanup;
    }

    if (!signed_block_signatures_are_valid(client, block, meta))
    {
        goto cleanup;
    }

    if (!validate_block_vote_constraints_locked(client, block, meta))
    {
        goto cleanup;
    }

    if (!apply_state_transition_locked(client, block, meta))
    {
        goto cleanup;
    }

    advance_fork_choice_time_locked(client, block, meta);
    get_head_info_locked(client, &head_root, &head_slot);
    persist_state_locked(client, meta);
    imported = true;

cleanup:
    lantern_client_unlock_state(client, state_locked);

    if (imported)
    {
        lantern_client_pending_remove_by_root(client, &block_root_local);
        lantern_client_process_pending_children(client, &block_root_local);
        log_imported_block(block, &head_root, head_slot, meta);
    }

    return imported;
}


/* ============================================================================
 * Block Recording
 * ============================================================================ */

/**
 * Record a received block and attempt import.
 *
 * @spec subspecs/forkchoice/store.py - Store.on_block()
 *
 * Entry point for recording blocks received from gossip or reqresp.
 * Computes the block root if not provided, persists the block to
 * storage, then delegates to import_block for processing.
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

    char root_hex[ROOT_HEX_BUFFER_LEN];
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
