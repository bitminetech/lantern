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

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/slot_clock.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/state.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "ssz.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

enum
{
    ROOT_HEX_BUFFER_LEN = (LANTERN_ROOT_SIZE * 2u) + 3u,
    BLOCK_AGGREGATE_SPLIT_LIMIT = 4u,
};

static void adopt_state_locked(struct lantern_client *client, LanternState *state);
static void advance_fork_choice_time_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta);
static void get_head_info_locked(
    struct lantern_client *client,
    LanternRoot *out_head_root,
    uint64_t *out_head_slot);
static bool finalized_checkpoint_advanced(
    const LanternCheckpoint *previous_finalized,
    const LanternCheckpoint *current_finalized);
static void prune_storage_if_finalized_advanced_locked(
    struct lantern_client *client,
    const LanternCheckpoint *previous_finalized,
    const struct lantern_log_metadata *meta);
static void prune_finalized_attestation_material_if_slot_advanced_locked(
    struct lantern_client *client,
    const LanternCheckpoint *previous_finalized);
static void prune_finalized_fork_choice_states_if_advanced_locked(
    struct lantern_client *client,
    const LanternCheckpoint *previous_finalized,
    const struct lantern_log_metadata *meta);
static void persist_state_locked(
    const struct lantern_client *client,
    const struct lantern_log_metadata *meta);
static void persist_post_state_locked(
    const struct lantern_client *client,
    const LanternState *post_state,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta);
static void log_imported_block(
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *head_root,
    uint64_t head_slot,
    const char *source,
    uint64_t took_ms,
    const struct lantern_log_metadata *meta,
    bool quiet);
static void log_import_rejected(
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *source,
    const char *reason,
    const struct lantern_log_metadata *meta);
static bool compute_state_head_root_locked(
    struct lantern_client *client,
    LanternRoot *out_root);
static bool lantern_client_import_block_internal(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    uint32_t backfill_depth,
    bool allow_historical,
    bool drain_pending_children,
    bool *out_children_ready,
    lantern_client_error *out_result);

/* ============================================================================
 * Sync Progress Helpers
 * ============================================================================ */

static void update_sync_progress_after_block(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }

    uint64_t local_slot = 0;
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked || client->state.validator_count > 0u)
    {
        local_slot = client->state.latest_block_header.slot;
        if (client->store.block_len > 0u)
        {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(
                    &client->store,
                    &client->store.head,
                    &fork_slot,
                    NULL,
                    NULL)
                == 0)
            {
                local_slot = fork_slot;
            }
        }
    }
    lantern_client_unlock_state(client, state_locked);

    lantern_client_update_sync_progress(client, local_slot);
}

static void update_network_view_after_import(
    struct lantern_client *client,
    const LanternRoot *block_root,
    uint64_t block_slot)
{
    if (!client || !block_root)
    {
        return;
    }

    LanternCheckpoint finalized = {0};
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked || client->state.validator_count > 0u)
    {
        finalized = client->state.latest_finalized;
        if (client->store.block_len > 0u
            && !lantern_root_is_zero(&client->store.latest_finalized.root))
        {
            finalized = client->store.latest_finalized;
        }
    }
    lantern_client_unlock_state(client, state_locked);

    bool locked = false;
    if (client->status_lock_initialized)
    {
        if (pthread_mutex_lock(&client->status_lock) != 0)
        {
            return;
        }
        locked = true;
    }

    bool changed = false;
    if (lantern_root_is_zero(&client->network_view.head.root)
        || block_slot > client->network_view.head.slot)
    {
        client->network_view.head = (LanternCheckpoint){.root = *block_root, .slot = block_slot};
        changed = true;
    }
    if (!lantern_root_is_zero(&finalized.root)
        && !lantern_root_is_zero(&client->network_view.finalized.root)
        && finalized.slot > client->network_view.finalized.slot)
    {
        client->network_view.finalized = finalized;
        changed = true;
    }
    if (changed)
    {
        lantern_log_info(
            "status",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "network_view head %s%" PRIu64 ", finalized %s%" PRIu64,
            lantern_root_is_zero(&client->network_view.head.root) ? "-" : "",
            client->network_view.head.slot,
            lantern_root_is_zero(&client->network_view.finalized.root) ? "-" : "",
            client->network_view.finalized.slot);
    }

    if (locked)
    {
        pthread_mutex_unlock(&client->status_lock);
    }
}

void lantern_client_cache_block_aggregated_proofs_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block)
{
    if (!client || !block)
    {
        return;
    }
    const LanternAggregatedAttestations *attestations = &block->block.body.attestations;
    if (attestations->length == 0u || !attestations->data)
    {
        return;
    }

    const LanternState *parent_state = NULL;
    bool parent_state_lookup_done = false;
    size_t split_attempts = 0u;

    for (size_t i = 0; i < attestations->length; ++i)
    {
        const LanternAggregatedAttestation *attestation = &attestations->data[i];
        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&attestation->data, &data_root) != SSZ_SUCCESS)
        {
            continue;
        }
        if (block->proof.length == 0u || !block->proof.data
            || split_attempts >= BLOCK_AGGREGATE_SPLIT_LIMIT
            || lantern_store_aggregated_payloads_cover_participants(
                &client->store,
                &data_root,
                &attestation->aggregation_bits))
        {
            continue;
        }

        if (!parent_state_lookup_done)
        {
            parent_state = lantern_client_state_for_root_locked(
                client,
                &block->block.parent_root);
            parent_state_lookup_done = true;
        }
        if (!parent_state)
        {
            continue;
        }

        LanternAggregatedSignatureProof recovered;
        lantern_aggregated_signature_proof_init(&recovered);
        split_attempts += 1u;
        if (!lantern_signature_split_block_type2_attestation_proof(
                parent_state,
                &block->block,
                &block->proof,
                i,
                &recovered))
        {
            lantern_aggregated_signature_proof_reset(&recovered);
            continue;
        }
        (void)lantern_store_add_new_aggregated_payload(
            &client->store,
            &data_root,
            &attestation->data,
            &recovered);
        lantern_aggregated_signature_proof_reset(&recovered);
    }

}

static void persist_block_after_import(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !client->data_dir || !block)
    {
        return;
    }

    struct lantern_log_metadata fallback = {.validator = client->node_id};
    const struct lantern_log_metadata *log_meta = meta ? meta : &fallback;
    if (lantern_storage_store_block(client->data_dir, block) != 0)
    {
        lantern_log_debug(
            "storage",
            log_meta,
            "failed to persist block slot=%" PRIu64,
            block->block.slot);
    }
}

static int commit_and_publish_local_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    LanternState *post_state)
{
    if (!client || !block || !block_root || !post_state)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
    };
    char root_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(block_root, root_hex, sizeof(root_hex));
    if (client->sync_started_ms != 0u)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "received block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s source=local",
            block->block.slot,
            block->block.proposer_index,
            root_hex[0] ? root_hex : "0x0");
    }
    else
    {
        lantern_log_info(
            "gossip",
            &meta,
            "received block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s source=local",
            block->block.slot,
            block->block.proposer_index,
            root_hex[0] ? root_hex : "0x0");
    }

    LanternCheckpoint pre_transition_finalized = {0};
    LanternRoot head_root = {0};
    uint64_t head_slot = 0u;
    bool committed = false;

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    pre_transition_finalized = client->state.latest_finalized;
    LanternRoot current_head_root = {0};
    bool have_current_head = false;
    if (client->store.block_len > 0u)
    {
        current_head_root = client->store.head;
        have_current_head = true;
    }
    if (!have_current_head)
    {
        have_current_head = compute_state_head_root_locked(client, &current_head_root);
    }
    if (!have_current_head
        || memcmp(
               current_head_root.bytes,
               block->block.parent_root.bytes,
               LANTERN_ROOT_SIZE)
            != 0)
    {
        lantern_client_unlock_state(client, state_locked);

        lantern_client_error import_result = LANTERN_CLIENT_ERR_RUNTIME;
        bool imported = lantern_client_import_block_internal(
            client,
            block,
            block_root,
            &meta,
            0u,
            false,
            true,
            NULL,
            &import_result);
        if (!imported && import_result != LANTERN_CLIENT_OK)
        {
            return import_result;
        }
        return lantern_client_publish_block(client, block);
    }

    if (client->store.block_len > 0u
        && lantern_fork_choice_add_block_with_state(
               &client->store,
               &block->block,
               &post_state->latest_justified,
               &post_state->latest_finalized,
               block_root,
               post_state)
            != 0)
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    lantern_client_cache_block_aggregated_proofs_locked(client, block);
    adopt_state_locked(client, post_state);
    lantern_state_init(post_state);
    get_head_info_locked(client, &head_root, &head_slot);
    committed = true;
    log_imported_block(block, block_root, &head_root, head_slot, "local", 0u, &meta, false);
    lantern_client_unlock_state(client, state_locked);
    state_locked = false;

    int publish_rc = lantern_client_publish_block(client, block);

    state_locked = lantern_client_lock_state(client);
    if (state_locked)
    {
        prune_storage_if_finalized_advanced_locked(
            client,
            &pre_transition_finalized,
            &meta);
        prune_finalized_attestation_material_if_slot_advanced_locked(
            client,
            &pre_transition_finalized);
        advance_fork_choice_time_locked(client, block, &meta);
        prune_finalized_fork_choice_states_if_advanced_locked(
            client,
            &pre_transition_finalized,
            &meta);
        get_head_info_locked(client, &head_root, &head_slot);
        persist_state_locked(client, &meta);
        persist_post_state_locked(
            client,
            &client->state,
            block_root,
            &meta);
        lantern_client_unlock_state(client, state_locked);
    }

    if (committed)
    {
        persist_block_after_import(client, block, &meta);
        update_network_view_after_import(client, block_root, block->block.slot);
        lantern_client_pending_remove_by_root(client, block_root);
        lantern_client_process_pending_children(client, block_root);
        update_sync_progress_after_block(client);
        lantern_client_replay_pending_gossip_votes(client);
    }

    if (publish_rc != LANTERN_CLIENT_OK)
    {
        return publish_rc;
    }
    return committed ? LANTERN_CLIENT_OK : LANTERN_CLIENT_ERR_RUNTIME;
}

int lantern_client_commit_and_publish_local_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    LanternState *post_state)
{
    return commit_and_publish_local_block(
        client,
        block,
        block_root,
        post_state);
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
 * @param block_root   Root of the block
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
    if (lantern_hash_tree_root_block(&block->block, out_root) != SSZ_SUCCESS)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to hash block at slot=%" PRIu64,
            block->block.slot);
        return false;
    }
    return true;
}


/**
 * @brief Returns true if the block should be processed.
 *
 * @param slot        Block slot
 * @param root_known  Whether the block root is known
 * @param known_slot  Slot of the known root (if root_known)
 * @param meta        Logging metadata
 * @return true if block should be processed, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
static bool should_process_block(
    uint64_t slot,
    bool root_known,
    uint64_t known_slot,
    const struct lantern_log_metadata *meta)
{
    if (root_known && slot <= known_slot)
    {
        lantern_log_trace("state", meta, "skipping known block slot=%" PRIu64, slot);
        return false;
    }
    return true;
}

enum block_parent_action
{
    BLOCK_PARENT_ACTION_UNKNOWN = 0,
    BLOCK_PARENT_ACTION_DEFERRED,
    BLOCK_PARENT_ACTION_MATCHES_HEAD,
    BLOCK_PARENT_ACTION_KNOWN_OFF_HEAD,
};

static bool compute_state_head_root_locked(
    struct lantern_client *client,
    LanternRoot *out_root)
{
    if (!client || !out_root)
    {
        return false;
    }
    if (lantern_state_process_slot(&client->state) != 0)
    {
        return false;
    }
    return lantern_hash_tree_root_block_header(
               &client->state.latest_block_header,
               out_root)
        == SSZ_SUCCESS;
}

const LanternState *lantern_client_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *root)
{
    if (!client || !root || client->store.block_len == 0u)
    {
        return NULL;
    }

    const LanternState *state =
        lantern_fork_choice_block_state(&client->store, root);
    if (state || !client->data_dir || client->data_dir[0] == '\0')
    {
        return state;
    }

    /* Finalization may evict a retained side branch's in-memory state. Its
     * keyed post-state remains on disk, so rehydrate the cache instead of
     * treating the known parent as an unresolved block gap. */
    uint8_t *state_bytes = NULL;
    size_t state_len = 0;
    if (lantern_storage_load_state_bytes_for_root(
            client->data_dir,
            root,
            &state_bytes,
            &state_len)
            != 0
        || !state_bytes
        || state_len == 0)
    {
        free(state_bytes);
        return NULL;
    }

    LanternState persisted_state;
    lantern_state_init(&persisted_state);
    bool restored =
        lantern_ssz_decode_state(&persisted_state, state_bytes, state_len) == SSZ_SUCCESS
        && lantern_fork_choice_set_block_state(
               &client->store,
               root,
               &persisted_state)
            == 0;
    free(state_bytes);
    lantern_state_reset(&persisted_state);

    return restored
        ? lantern_fork_choice_block_state(&client->store, root)
        : NULL;
}

static void adopt_state_locked(struct lantern_client *client, LanternState *state)
{
    if (!client || !state)
    {
        return;
    }
    LanternState previous = client->state;
    client->state = *state;
    lantern_state_init(state);
    if (client->store.block_len > 0u)
    {
        if (lantern_fork_choice_update_checkpoints(
                &client->store,
                &client->state.latest_justified,
                &client->state.latest_finalized)
            != 0)
        {
            lantern_log_warn(
                "forkchoice",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to sync fork choice checkpoints when adopting state slot=%" PRIu64,
                client->state.slot);
        }
    }
    lantern_state_reset(&previous);
}

/**
 * Handle parent tracking and competing forks.
 *
 * @param client       Client instance
 * @param block        Block being imported
 * @param meta         Logging metadata
 * @param state_locked In/out state lock flag (may be cleared if unlocked here)
 * @param backfill_depth Backfill depth of the block
 * @return Parent action describing how to proceed
 *
 * @note Thread safety: Caller must hold state_lock
 */
static enum block_parent_action handle_block_parent_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    bool *state_locked,
    uint32_t backfill_depth,
    bool allow_historical)
{
    if (!client || !block || !block_root || !state_locked || !*state_locked)
    {
        return BLOCK_PARENT_ACTION_UNKNOWN;
    }

    LanternRoot parent_root = block->block.parent_root;
    if (lantern_root_is_zero(&parent_root))
    {
        return BLOCK_PARENT_ACTION_MATCHES_HEAD;
    }

    bool parent_known = lantern_client_block_known_locked(client, &parent_root, NULL);
    if (!parent_known)
    {
        struct lantern_log_metadata parent_meta = {0};
        if (meta)
        {
            parent_meta = *meta;
        }
        parent_meta.has_slot = true;
        parent_meta.slot = block->block.slot;

        LanternRoot head_root = client->store.head;
        uint64_t head_slot = client->state.slot;
        if (client->store.block_len > 0u)
        {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(
                    &client->store,
                    &head_root,
                    &fork_slot,
                    NULL,
                    NULL)
                == 0)
            {
                head_slot = fork_slot;
            }
        }
        const LanternCheckpoint *anchor =
            client->store.block_len > 0u ? &client->store.anchor : NULL;
        const LanternCheckpoint *store_latest_justified =
            client->store.block_len > 0u ? &client->store.latest_justified : NULL;
        const LanternCheckpoint *store_latest_finalized =
            client->store.block_len > 0u ? &client->store.latest_finalized : NULL;
        char block_hex[ROOT_HEX_BUFFER_LEN];
        char parent_hex[ROOT_HEX_BUFFER_LEN];
        char head_hex[ROOT_HEX_BUFFER_LEN];
        char anchor_hex[ROOT_HEX_BUFFER_LEN];
        char justified_hex[ROOT_HEX_BUFFER_LEN];
        char finalized_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(block_root, block_hex, sizeof(block_hex));
        format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
        format_root_hex(&head_root, head_hex, sizeof(head_hex));
        format_root_hex(anchor ? &anchor->root : NULL, anchor_hex, sizeof(anchor_hex));
        format_root_hex(
            store_latest_justified ? &store_latest_justified->root : NULL,
            justified_hex,
            sizeof(justified_hex));
        format_root_hex(
            store_latest_finalized ? &store_latest_finalized->root : NULL,
            finalized_hex,
            sizeof(finalized_hex));
        lantern_log_info(
            "state",
            &parent_meta,
            "parent missing for block slot=%" PRIu64 " root=%s parent=%s"
            " head_slot=%" PRIu64 " head_root=%s anchor_slot=%" PRIu64
            " anchor_root=%s store_justified_slot=%" PRIu64
            " store_justified_root=%s store_finalized_slot=%" PRIu64
            " store_finalized_root=%s",
            block->block.slot,
            block_hex[0] ? block_hex : "0x0",
            parent_hex[0] ? parent_hex : "0x0",
            head_slot,
            head_hex[0] ? head_hex : "0x0",
            anchor ? anchor->slot : 0u,
            anchor_hex[0] ? anchor_hex : "0x0",
            store_latest_justified ? store_latest_justified->slot : 0u,
            justified_hex[0] ? justified_hex : "0x0",
            store_latest_finalized ? store_latest_finalized->slot : 0u,
            finalized_hex[0] ? finalized_hex : "0x0");
        const char *peer_text = meta && meta->peer ? meta->peer : NULL;
        lantern_client_unlock_state(client, *state_locked);
        *state_locked = false;
        bool queued = lantern_client_enqueue_pending_block(
            client,
            block,
            block_root,
            &parent_root,
            peer_text,
            backfill_depth,
            allow_historical);
        return queued ? BLOCK_PARENT_ACTION_DEFERRED : BLOCK_PARENT_ACTION_UNKNOWN;
    }

    /* Late blocks transition from their cached parent state, not the newer head. */
    if (block->block.slot <= client->state.slot)
    {
        lantern_log_debug(
            "state",
            meta,
            "routing late block to branch transition slot=%" PRIu64 " state_slot=%" PRIu64,
            block->block.slot,
            client->state.slot);
        return BLOCK_PARENT_ACTION_KNOWN_OFF_HEAD;
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
                 &latest_header_root) == SSZ_SUCCESS)
    {
        have_head_root = true;
        parent_matches_head =
            memcmp(latest_header_root.bytes, parent_root.bytes, LANTERN_ROOT_SIZE) == 0;
    }

    if (parent_matches_head)
    {
        return BLOCK_PARENT_ACTION_MATCHES_HEAD;
    }

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
            block->block.slot,
            parent_hex[0] ? parent_hex : "0x0",
            head_hex[0] ? head_hex : "0x0");
    }

    return BLOCK_PARENT_ACTION_KNOWN_OFF_HEAD;
}

static bool add_competing_fork_block_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternState *post_state,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block || !block_root || client->store.block_len == 0u)
    {
        return false;
    }

    if (lantern_fork_choice_add_block_with_state(
            &client->store,
            &block->block,
            post_justified,
            post_finalized,
            block_root,
            post_state) != 0)
    {
        return false;
    }

    lantern_client_cache_block_aggregated_proofs_locked(client, block);

    char block_hex[ROOT_HEX_BUFFER_LEN];
    char parent_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(block_root, block_hex, sizeof(block_hex));
    format_root_hex(&block->block.parent_root, parent_hex, sizeof(parent_hex));
    lantern_log_info(
        "import",
        meta,
        "slot %" PRIu64 ", %s, accepted off-head, parent %s, reason: known_off_current_head",
        block->block.slot,
        block_hex[0] ? block_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0");
    return true;
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
    if (client->store.block_len == 0u)
    {
        return true;
    }

    const LanternAggregatedAttestations *attestations = &block->block.body.attestations;
    if (attestations->length > 0 && !attestations->data)
    {
        lantern_log_warn(
            "state",
            meta,
            "block slot=%" PRIu64 " attestations missing data length=%zu",
            block->block.slot,
            attestations->length);
        return false;
    }
    size_t skipped_constraints = 0;
    for (size_t i = 0; i < attestations->length; ++i)
    {
        const LanternAggregatedAttestation *attestation = &attestations->data[i];
        size_t validator_id = 0;
        while (validator_id < attestation->aggregation_bits.bit_length
               && !lantern_bitlist_get(&attestation->aggregation_bits, validator_id))
        {
            validator_id += 1u;
        }
        if (validator_id == attestation->aggregation_bits.bit_length)
        {
            continue;
        }
        LanternVote vote = {
            .validator_id = (LanternValidatorIndex)validator_id,
            .data = attestation->data,
        };
        struct lantern_vote_rejection_info rejection;
        memset(&rejection, 0, sizeof(rejection));
        if (!lantern_client_validate_vote_constraints(
                client,
                &vote,
                "state",
                meta,
                "block attestation",
                &rejection))
        {
            /*
             * Block-body attestations only affect local fork-choice vote
             * tracking. A valid block can carry attestations that reference
             * roots we have not restored locally yet, so skip those votes and
             * let block import continue.
             */
            skipped_constraints += 1u;
            if (rejection.has_unknown_root)
            {
                char unknown_hex[ROOT_HEX_BUFFER_LEN];
                format_root_hex(
                    &rejection.unknown_root,
                    unknown_hex,
                    sizeof(unknown_hex));
                lantern_log_debug(
                    "state",
                    meta,
                    "skipping block attestation unknown root=%s slot=%" PRIu64
                    " block_slot=%" PRIu64,
                    unknown_hex[0] ? unknown_hex : "0x0",
                    rejection.unknown_slot,
                    block->block.slot);
            }
            else if (rejection.has_reason)
            {
                lantern_log_debug(
                    "state",
                    meta,
                    "skipping block attestation constraint failure block_slot=%" PRIu64
                    " reason=%s",
                    block->block.slot,
                    rejection.message);
            }
        }
    }

    if (skipped_constraints > 0)
    {
        lantern_log_debug(
            "state",
            meta,
            "block slot=%" PRIu64 " skipped %" PRIu64 " attestation fork-choice checks",
            block->block.slot,
            (uint64_t)skipped_constraints);
    }

    /* Skip proposer attestation validation here - the proposer's head
     * checkpoint references the block being imported, which isn't in fork
     * choice yet. Proposer attestation validity is checked in state
     * transition. */
    return true;
}


/**
 * @brief Records finality-lag diagnostics for an imported block.
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void record_block_import_metrics_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block)
{
    const LanternAggregatedAttestations *atts = &block->block.body.attestations;
    for (size_t i = 0; i < atts->length; ++i)
    {
        if (block->block.slot >= atts->data[i].data.slot)
        {
            lean_metrics_record_attestation_inclusion_delay(
                block->block.slot - atts->data[i].data.slot);
        }
    }

    uint64_t now_milliseconds = validator_wall_time_now_millis();
    uint64_t total_interval = 0u;
    if (lantern_slot_clock_total_interval(
            client->state.config.genesis_time,
            now_milliseconds,
            &total_interval)
        != 0)
    {
        return;
    }
    /* Live blocks only: skip backfill/sync imports of past slots, whose import
     * time bears no relation to their slot boundary. */
    if (total_interval / LANTERN_INTERVALS_PER_SLOT != block->block.slot)
    {
        return;
    }
    uint64_t slot_start_ms = 0;
    if (lantern_slot_clock_slot_start_time(
            client->state.config.genesis_time,
            block->block.slot,
            &slot_start_ms)
            != 0
        || now_milliseconds < slot_start_ms)
    {
        return;
    }
    lean_metrics_record_block_import_slot_offset((double)(now_milliseconds - slot_start_ms) / 1000.0);
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
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block || !block_root)
    {
        return false;
    }

    if (lantern_state_transition(&client->state, block) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "state transition failed for slot=%" PRIu64,
            block->block.slot);
        return false;
    }
    if (client->store.block_len > 0u
        && lantern_fork_choice_add_block_with_state(
               &client->store,
               &block->block,
               &client->state.latest_justified,
               &client->state.latest_finalized,
               block_root,
               &client->state)
            != 0)
    {
        lantern_log_warn(
            "forkchoice",
            meta,
            "failed to add transitioned block at slot=%" PRIu64,
            block->block.slot);
        return false;
    }

    record_block_import_metrics_locked(client, block);

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
    if (!client || !block || client->store.block_len == 0u)
    {
        return;
    }

    uint64_t now_milliseconds = validator_wall_time_now_millis();
    if (lantern_client_advance_fork_choice_time_locked(client, now_milliseconds, false) != 0)
    {
        lantern_log_debug(
            "forkchoice",
            meta,
            "advancing fork choice time failed after slot=%" PRIu64,
            block->block.slot);
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
    if (client->store.block_len == 0u)
    {
        return;
    }

    *out_head_root = client->store.head;

    uint64_t fork_slot = 0;
    if (lantern_fork_choice_block_info(
            &client->store,
            out_head_root,
            &fork_slot,
            NULL,
            NULL) == 0)
    {
        *out_head_slot = fork_slot;
    }
}

static bool historical_import_floor_slot_locked(
    struct lantern_client *client,
    uint64_t *out_finalized_slot)
{
    if (out_finalized_slot)
    {
        *out_finalized_slot = 0;
    }
    if (!client || !out_finalized_slot || client->store.block_len == 0u)
    {
        return false;
    }

    *out_finalized_slot = client->store.latest_finalized.slot;
    return true;
}

static bool finalized_checkpoint_advanced(
    const LanternCheckpoint *previous_finalized,
    const LanternCheckpoint *current_finalized)
{
    if (!previous_finalized || !current_finalized)
    {
        return false;
    }
    if (current_finalized->slot > previous_finalized->slot)
    {
        return true;
    }
    if (current_finalized->slot < previous_finalized->slot)
    {
        return false;
    }
    if (memcmp(
            current_finalized->root.bytes,
            previous_finalized->root.bytes,
            LANTERN_ROOT_SIZE)
        != 0
        && !lantern_root_is_zero(&current_finalized->root))
    {
        return true;
    }

    return false;
}

static void prune_finalized_attestation_material_if_slot_advanced_locked(
    struct lantern_client *client,
    const LanternCheckpoint *previous_finalized)
{
    if (!client || !previous_finalized)
    {
        return;
    }

    const LanternCheckpoint *current_finalized = &client->state.latest_finalized;
    if (current_finalized->slot <= previous_finalized->slot)
    {
        return;
    }

    (void)lantern_store_prune_finalized_attestation_material(
        &client->store,
        current_finalized->slot);
}

static void prune_finalized_fork_choice_states_if_advanced_locked(
    struct lantern_client *client,
    const LanternCheckpoint *previous_finalized,
    const struct lantern_log_metadata *meta)
{
    if (!client || !previous_finalized || client->store.block_len == 0u)
    {
        return;
    }

    const LanternCheckpoint *current_finalized = &client->state.latest_finalized;
    if (!finalized_checkpoint_advanced(previous_finalized, current_finalized))
    {
        return;
    }

    if (lantern_fork_choice_prune_states(&client->store) != 0)
    {
        lantern_log_warn(
            "forkchoice",
            meta,
            "failed to prune fork choice states finalized_slot=%" PRIu64,
            current_finalized->slot);
    }
}

static void prune_storage_if_finalized_advanced_locked(
    struct lantern_client *client,
    const LanternCheckpoint *previous_finalized,
    const struct lantern_log_metadata *meta)
{
    if (!client || !previous_finalized || !client->data_dir)
    {
        return;
    }
    const LanternCheckpoint *current = &client->state.latest_finalized;
    if (!finalized_checkpoint_advanced(previous_finalized, current))
    {
        return;
    }
    if (lantern_storage_prune_before_slot(
            client->data_dir,
            current->slot,
            &current->root,
            1u)
        < 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to prune persisted data before finalized slot=%" PRIu64,
            current->slot);
    }
}

/**
 * @brief Persists client state if storage is enabled.
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
}

/**
 * @brief Persist the post-state owned by a block root.
 *
 * @param client     Client instance
 * @param post_state Post-state after applying the block
 * @param block_root Root of the block
 * @param meta       Logging metadata
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void persist_post_state_locked(
    const struct lantern_client *client,
    const LanternState *post_state,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta)
{
    if (!client || !client->data_dir || !post_state || !block_root)
    {
        return;
    }

    if (lantern_storage_store_state_for_root(client->data_dir, block_root, post_state) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist post-state slot=%" PRIu64,
            post_state->slot);
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
    const LanternRoot *block_root,
    const LanternRoot *head_root,
    uint64_t head_slot,
    const char *source,
    uint64_t took_ms,
    const struct lantern_log_metadata *meta,
    bool quiet)
{
    (void)quiet;
    if (!block || !block_root || !head_root)
    {
        return;
    }

    char block_hex[ROOT_HEX_BUFFER_LEN];
    char parent_hex[ROOT_HEX_BUFFER_LEN];
    char head_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(block_root, block_hex, sizeof(block_hex));
    format_root_hex(&block->block.parent_root, parent_hex, sizeof(parent_hex));
    format_root_hex(head_root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "import",
        meta,
        "slot %" PRIu64 ", %s, via %s, parent %s, head %" PRIu64 " %s, took_ms %" PRIu64,
        block->block.slot,
        block_hex[0] ? block_hex : "0x0",
        source && source[0] ? source : "unknown",
        parent_hex[0] ? parent_hex : "0x0",
        head_slot,
        head_hex[0] ? head_hex : "0x0",
        took_ms);
}

static void log_import_rejected(
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const char *source,
    const char *reason,
    const struct lantern_log_metadata *meta)
{
    if (!block)
    {
        return;
    }
    char block_hex[ROOT_HEX_BUFFER_LEN];
    char parent_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(block_root, block_hex, sizeof(block_hex));
    format_root_hex(&block->block.parent_root, parent_hex, sizeof(parent_hex));
    lantern_log_warn(
        "import",
        meta,
        "slot %" PRIu64 ", %s, rejected, reason: %s, via %s, parent %s",
        block->block.slot,
        block_hex[0] ? block_hex : "0x0",
        reason && reason[0] ? reason : "unknown",
        source && source[0] ? source : "unknown",
        parent_hex[0] ? parent_hex : "0x0");
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
 *    - Parent known but not head: validate, add to fork choice, process cached descendants
 *    - Parent matches head: proceed with full import
 * 4. Verifies all block signatures
 * 5. Validates attestation constraints
 * 6. Applies state transition (head-matching parents only)
 * 7. Updates fork choice
 * 8. Persists the block and post-state
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
 * @param backfill_depth Backfill depth of the block
 * @return true if block was imported successfully
 *
 * @note Thread safety: Acquires state_lock and pending_lock
 */
static bool lantern_client_import_block_internal(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    uint32_t backfill_depth,
    bool allow_historical,
    bool drain_pending_children,
    bool *out_children_ready,
    lantern_client_error *out_result)
{
    if (out_children_ready)
    {
        *out_children_ready = false;
    }
    if (!client || !block || client->state.validator_count == 0u)
    {
        if (out_result)
        {
            *out_result = LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
        return false;
    }

    bool imported = false;
    bool children_ready = false;
    lantern_client_error import_result = LANTERN_CLIENT_ERR_RUNTIME;
    uint64_t import_started_ms = monotonic_millis();
    const char *import_source =
        allow_historical ? "backfill" : ((meta && meta->peer) ? "gossip" : "local");
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to acquire state lock for block import slot=%" PRIu64,
            block->block.slot);
        if (out_result)
        {
            *out_result = LANTERN_CLIENT_ERR_RUNTIME;
        }
        return false;
    }

    LanternRoot block_root_local = {0};
    LanternRoot head_root = {0};
    uint64_t head_slot = 0;

    if (!get_block_root_local(block, block_root, &block_root_local, meta))
    {
        goto cleanup;
    }

    uint64_t known_slot = 0;
    bool root_known = lantern_client_block_known_locked(client, &block_root_local, &known_slot);
    uint64_t historical_floor_slot = 0;
    bool below_historical_floor =
        !root_known
        && historical_import_floor_slot_locked(client, &historical_floor_slot)
        && block->block.slot <= historical_floor_slot;
    if (below_historical_floor)
    {
        char block_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&block_root_local, block_hex, sizeof(block_hex));
        lantern_log_debug(
            "state",
            meta,
            "dropping finalized historical block slot=%" PRIu64 " root=%s finalized_slot=%" PRIu64,
            block->block.slot,
            block_hex[0] ? block_hex : "0x0",
            historical_floor_slot);
        log_import_rejected(block, &block_root_local, import_source, "pre_finalized", meta);
        lantern_client_unlock_state(client, state_locked);
        lantern_client_pending_remove_branch_by_root(client, &block_root_local);
        if (out_result)
        {
            *out_result = LANTERN_CLIENT_ERR_IGNORED;
        }
        return false;
    }
    if (root_known && allow_historical && block->block.slot <= known_slot)
    {
        log_import_rejected(block, &block_root_local, import_source, "duplicate", meta);
        lantern_client_unlock_state(client, state_locked);
        persist_block_after_import(client, block, meta);
        if (drain_pending_children)
        {
            lantern_client_process_pending_children(client, &block_root_local);
        }
        else
        {
            children_ready = true;
        }
        lantern_client_pending_remove_by_root(client, &block_root_local);
        if (out_children_ready)
        {
            *out_children_ready = children_ready;
        }
        if (out_result)
        {
            *out_result = LANTERN_CLIENT_ERR_IGNORED;
        }
        return false;
    }

    if (!should_process_block(
            block->block.slot,
            root_known,
            known_slot,
            meta))
    {
        log_import_rejected(block, &block_root_local, import_source, "duplicate", meta);
        import_result = LANTERN_CLIENT_ERR_IGNORED;
        goto cleanup;
    }

    enum block_parent_action parent_action = handle_block_parent_locked(
        client,
        block,
        &block_root_local,
        meta,
        &state_locked,
        backfill_depth,
        allow_historical);
    if (parent_action == BLOCK_PARENT_ACTION_UNKNOWN)
    {
        import_result = LANTERN_CLIENT_ERR_IGNORED;
        goto cleanup;
    }
    if (parent_action == BLOCK_PARENT_ACTION_DEFERRED)
    {
        import_result = LANTERN_CLIENT_OK;
        goto cleanup;
    }
    bool parent_off_head = parent_action == BLOCK_PARENT_ACTION_KNOWN_OFF_HEAD;

    if (!validate_block_vote_constraints_locked(client, block, meta))
    {
        char root_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&block_root_local, root_hex, sizeof(root_hex));
        lantern_log_warn(
            "state",
            meta,
            "vote constraints failed slot=%" PRIu64 " root=%s depth=%" PRIu32,
            block->block.slot,
            root_hex[0] ? root_hex : "0x0",
            backfill_depth);
        log_import_rejected(block, &block_root_local, import_source, "vote_constraints_failed", meta);
        goto cleanup;
    }

    if (parent_off_head)
    {
        const LanternRoot parent_root = block->block.parent_root;
        const LanternState *parent_state =
            lantern_client_state_for_root_locked(client, &parent_root);
        LanternState branch_state;
        lantern_state_init(&branch_state);
        bool have_branch_state =
            parent_state && lantern_state_clone(parent_state, &branch_state) == 0;
        bool processed = false;
        bool deferred = false;
        LanternRoot previous_head = client->store.head;

        if (have_branch_state)
        {
            if (lantern_state_transition(&branch_state, block) == 0)
            {
                processed = add_competing_fork_block_locked(
                    client,
                    block,
                    &block_root_local,
                    &branch_state,
                    &branch_state.latest_justified,
                    &branch_state.latest_finalized,
                    meta);
            }
            else
            {
                log_import_rejected(
                    block,
                    &block_root_local,
                    import_source,
                    "state_transition_failed",
                    meta);
            }
        }
        else
        {
            const char *peer_text = meta && meta->peer ? meta->peer : NULL;
            deferred = lantern_client_enqueue_pending_block(
                client,
                block,
                &block_root_local,
                &parent_root,
                peer_text,
                backfill_depth,
                true);
            uint32_t request_depth =
                backfill_depth < LANTERN_MAX_BACKFILL_DEPTH
                    ? backfill_depth + 1u
                    : LANTERN_MAX_BACKFILL_DEPTH;
            (void)lantern_client_try_schedule_blocks_request_batch(
                client,
                peer_text,
                &parent_root,
                &request_depth,
                1u);
        }

        LanternCheckpoint pre_adopt_finalized = client->state.latest_finalized;
        bool adopted_state = false;
        LanternRoot fork_head = client->store.head;
        if (processed
            && memcmp(
                       client->store.head.bytes,
                       previous_head.bytes,
                       LANTERN_ROOT_SIZE)
                    != 0)
        {
            fork_head = client->store.head;
            const LanternState *cached_head =
                lantern_client_state_for_root_locked(client, &fork_head);
            LanternState head_state;
            lantern_state_init(&head_state);
            if (cached_head && lantern_state_clone(cached_head, &head_state) == 0)
            {
                adopt_state_locked(client, &head_state);
                adopted_state = true;
            }
            else
            {
                lantern_state_reset(&head_state);
            }
        }

        if (adopted_state)
        {
            prune_storage_if_finalized_advanced_locked(
                client,
                &pre_adopt_finalized,
                meta);
            prune_finalized_attestation_material_if_slot_advanced_locked(
                client,
                &pre_adopt_finalized);
            prune_finalized_fork_choice_states_if_advanced_locked(
                client,
                &pre_adopt_finalized,
                meta);
            persist_state_locked(client, meta);
        }

        if (processed)
        {
            persist_post_state_locked(
                client,
                &branch_state,
                &block_root_local,
                meta);
        }
        lantern_state_reset(&branch_state);

        lantern_client_unlock_state(client, state_locked);
        state_locked = false;
        if (!deferred)
        {
            lantern_client_pending_remove_by_root(client, &block_root_local);
        }
        if (processed)
        {
            persist_block_after_import(client, block, meta);
            update_network_view_after_import(client, &block_root_local, block->block.slot);
            if (drain_pending_children)
            {
                lantern_client_process_pending_children(client, &block_root_local);
            }
            else
            {
                children_ready = true;
            }
            update_sync_progress_after_block(client);
            lantern_client_replay_pending_gossip_votes(client);
        }
        if (out_children_ready)
        {
            *out_children_ready = children_ready;
        }
        import_result = processed || deferred
            ? LANTERN_CLIENT_OK
            : LANTERN_CLIENT_ERR_IGNORED;
        if (out_result)
        {
            *out_result = import_result;
        }
        return false;
    }

    LanternCheckpoint pre_transition_finalized = client->state.latest_finalized;
    if (!apply_state_transition_locked(client, block, &block_root_local, meta))
    {
        log_import_rejected(block, &block_root_local, import_source, "state_transition_failed", meta);
        goto cleanup;
    }

    lantern_client_cache_block_aggregated_proofs_locked(client, block);

    prune_storage_if_finalized_advanced_locked(
        client,
        &pre_transition_finalized,
        meta);
    prune_finalized_attestation_material_if_slot_advanced_locked(
        client,
        &pre_transition_finalized);
    prune_finalized_fork_choice_states_if_advanced_locked(
        client,
        &pre_transition_finalized,
        meta);
    get_head_info_locked(client, &head_root, &head_slot);
    persist_state_locked(client, meta);
    persist_post_state_locked(
        client,
        &client->state,
        &block_root_local,
        meta);
    imported = true;

cleanup:
    lantern_client_unlock_state(client, state_locked);

    if (imported)
    {
        import_result = LANTERN_CLIENT_OK;
        persist_block_after_import(client, block, meta);
        update_network_view_after_import(client, &block_root_local, block->block.slot);
        bool quiet_log = false;
        if (client->status_lock_initialized
            && pthread_mutex_lock(&client->status_lock) == 0)
        {
            quiet_log = client->sync_started_ms != 0u;
            pthread_mutex_unlock(&client->status_lock);
        }
        lantern_client_pending_remove_by_root(client, &block_root_local);
        if (drain_pending_children)
        {
            lantern_client_process_pending_children(client, &block_root_local);
        }
        else
        {
            children_ready = true;
        }
        uint64_t import_finished_ms = monotonic_millis();
        uint64_t took_ms =
            import_finished_ms >= import_started_ms ? import_finished_ms - import_started_ms : 0u;
        log_imported_block(
            block,
            &block_root_local,
            &head_root,
            head_slot,
            import_source,
            took_ms,
            meta,
            quiet_log);
        update_sync_progress_after_block(client);
        lantern_client_replay_pending_gossip_votes(client);
    }

    if (out_children_ready)
    {
        *out_children_ready = children_ready;
    }
    if (out_result)
    {
        *out_result = import_result;
    }
    return imported;
}

bool lantern_client_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    uint32_t backfill_depth,
    bool allow_historical)
{
    return lantern_client_import_block_internal(
        client,
        block,
        block_root,
        meta,
        backfill_depth,
        allow_historical,
        true,
        NULL,
        NULL);
}

bool lantern_client_import_block_without_pending_children(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    uint32_t backfill_depth,
    bool allow_historical,
    bool *out_children_ready)
{
    return lantern_client_import_block_internal(
        client,
        block,
        block_root,
        meta,
        backfill_depth,
        allow_historical,
        false,
        out_children_ready,
        NULL);
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
 * Computes the block root if not provided, delegates to import_block
 * for processing, and persists the block after successful import.
 *
 * @param client    Client instance
 * @param block     Signed block to record
 * @param root      Precomputed block root (may be NULL)
 * @param peer_text Peer ID string (may be NULL)
 * @param context   Description of source for logging
 * @param backfill_depth Backfill depth of the block
 * @return LANTERN_CLIENT_OK if the block was validated/imported or accepted into pending
 * @return LANTERN_CLIENT_ERR_IGNORED if it was duplicate, stale, or not retained
 * @return another LANTERN_CLIENT_ERR_* when validation/import failed
 *
 * @note Thread safety: Acquires state_lock via lantern_client_import_block
 */
lantern_client_error lantern_client_record_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    const char *context,
    uint32_t backfill_depth,
    bool allow_historical)
{
    if (!client || !block)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    LanternRoot computed_root;
    const LanternRoot *selected_root = root;
    if (!selected_root)
    {
        if (lantern_hash_tree_root_block(&block->block, &computed_root) != SSZ_SUCCESS)
        {
            return LANTERN_CLIENT_ERR_RUNTIME;
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

    if (client->sync_started_ms != 0u)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "received block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s source=%s",
            block->block.slot,
            block->block.proposer_index,
            root_hex[0] ? root_hex : "0x0",
            source);
    }
    else
    {
        lantern_log_info(
            "gossip",
            &meta,
            "received block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s source=%s",
            block->block.slot,
            block->block.proposer_index,
            root_hex[0] ? root_hex : "0x0",
            source);
    }

    if (lantern_client_backfill_should_drop_gossip(
            client,
            block,
            selected_root,
            peer_text,
            source))
    {
        return LANTERN_CLIENT_ERR_IGNORED;
    }

    lantern_client_error import_result = LANTERN_CLIENT_ERR_RUNTIME;
    (void)lantern_client_import_block_internal(
        client,
        block,
        selected_root,
        &meta,
        backfill_depth,
        allow_historical,
        true,
        NULL,
        &import_result);
    return import_result;
}
