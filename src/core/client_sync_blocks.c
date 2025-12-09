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
