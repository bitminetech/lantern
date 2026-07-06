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
static void persist_finalized_state_if_advanced_locked(
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
static void persist_post_state_and_indices_locked(
    const struct lantern_client *client,
    const LanternState *post_state,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *head_root,
    uint64_t head_slot,
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
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
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
    if (state_locked || client->has_state)
    {
        local_slot = client->state.latest_block_header.slot;
        if (client->has_fork_choice)
        {
            LanternRoot fork_head = {0};
            if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0)
            {
                uint64_t fork_slot = 0;
                if (lantern_fork_choice_block_info(
                        &client->fork_choice,
                        &fork_head,
                        &fork_slot,
                        NULL,
                        NULL)
                    == 0)
                {
                    local_slot = fork_slot;
                }
            }
        }
    }
    lantern_client_unlock_state(client, state_locked);

    lantern_client_update_sync_progress(client, local_slot);
}

static void update_network_view_after_import(
    struct lantern_client *client,
    uint64_t block_slot,
    uint64_t finalized_slot)
{
    if (!client)
    {
        return;
    }

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
    if (!client->network_view.has_latest_observed_head_slot
        || block_slot > client->network_view.latest_observed_head_slot)
    {
        client->network_view.latest_observed_head_slot = block_slot;
        client->network_view.has_latest_observed_head_slot = true;
        changed = true;
    }
    if (!client->network_view.has_network_finalized_slot
        || finalized_slot > client->network_view.network_finalized_slot)
    {
        client->network_view.network_finalized_slot = finalized_slot;
        client->network_view.has_network_finalized_slot = true;
        changed = true;
    }
    uint64_t head = client->network_view.latest_observed_head_slot;
    uint64_t finalized = client->network_view.network_finalized_slot;
    bool has_head = client->network_view.has_latest_observed_head_slot;
    bool has_finalized = client->network_view.has_network_finalized_slot;
    if (changed)
    {
        lantern_log_info(
            "status",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "network_view head %s%" PRIu64 ", finalized %s%" PRIu64,
            has_head ? "" : "-",
            has_head ? head : 0u,
            has_finalized ? "" : "-",
            has_finalized ? finalized : 0u);
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
    if (!client || !block) {
        return;
    }
    const LanternAggregatedAttestations *attestations = &block->block.body.attestations;
    if (attestations->length == 0u) {
        return;
    }
    if (!attestations->data) {
        return;
    }

    if (block->proof.length == 0u || !block->proof.data) {
        return;
    }

    for (size_t i = 0; i < attestations->length; ++i) {
        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&attestations->data[i].data, &data_root) != SSZ_SUCCESS) {
            continue;
        }
        (void)lantern_store_add_attestation_data(
            &client->store,
            &data_root,
            &attestations->data[i].data,
            attestations->data[i].data.target.slot);
    }
}

static bool sync_validator_votes_from_preview_locked(
    struct lantern_client *client,
    const LanternStore *preview_store)
{
    if (!client || !preview_store)
    {
        return false;
    }
    if (!preview_store->validator_votes || preview_store->validator_votes_len == 0u)
    {
        return true;
    }
    if (lantern_store_prepare_validator_votes(
            &client->store,
            (uint64_t)preview_store->validator_votes_len)
        != 0)
    {
        return false;
    }
    memcpy(
        client->store.validator_votes,
        preview_store->validator_votes,
        preview_store->validator_votes_len * sizeof(*preview_store->validator_votes));
    return true;
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
    LanternState *post_state,
    LanternStore *post_store,
    bool require_current_parent)
{
    if (!client || !block || !block_root || !post_state || !post_store)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
    };
    char root_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(block_root, root_hex, sizeof(root_hex));
    if (client->sync_in_progress)
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
    uint64_t committed_finalized_slot = 0u;
    bool committed = false;

    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    pre_transition_finalized = client->state.latest_finalized;
    LanternRoot current_head_root = {0};
    bool have_current_head = false;
    if (client->has_fork_choice)
    {
        have_current_head =
            lantern_fork_choice_current_head(&client->fork_choice, &current_head_root) == 0;
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

        if (require_current_parent)
        {
            return LANTERN_CLIENT_ERR_IGNORED;
        }
        lantern_client_error import_result = LANTERN_CLIENT_ERR_RUNTIME;
        bool imported = lantern_client_import_block_internal(
            client,
            block,
            block_root,
            &meta,
            0u,
            false,
            NULL,
            0u,
            true,
            NULL,
            &import_result);
        if (!imported && import_result != LANTERN_CLIENT_OK)
        {
            return import_result;
        }
        return lantern_client_publish_block(client, block);
    }

    if (client->has_fork_choice
        && lantern_fork_choice_add_block_with_state(
               &client->fork_choice,
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

    if (!sync_validator_votes_from_preview_locked(client, post_store))
    {
        lantern_client_unlock_state(client, state_locked);
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    lantern_client_cache_block_aggregated_proofs_locked(client, block);
    committed_finalized_slot = post_state->latest_finalized.slot;
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
        persist_finalized_state_if_advanced_locked(
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
        persist_post_state_and_indices_locked(
            client,
            &client->state,
            block,
            block_root,
            &head_root,
            head_slot,
            &meta);
        lantern_client_unlock_state(client, state_locked);
    }

    if (committed)
    {
        persist_block_after_import(client, block, &meta);
        update_network_view_after_import(client, block->block.slot, committed_finalized_slot);
        if (client->status_lock_initialized
            && pthread_mutex_lock(&client->status_lock) == 0)
        {
            client->sync_imported_blocks += 1u;
            pthread_mutex_unlock(&client->status_lock);
        }
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
    LanternState *post_state,
    LanternStore *post_store)
{
    return commit_and_publish_local_block(
        client,
        block,
        block_root,
        post_state,
        post_store,
        false);
}

int lantern_client_commit_and_publish_current_head_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    LanternState *post_state,
    LanternStore *post_store)
{
    return commit_and_publish_local_block(
        client,
        block,
        block_root,
        post_state,
        post_store,
        true);
}

static int encode_block_ssz(
    const LanternSignedBlock *block,
    uint8_t **out_data,
    size_t *out_len)
{
    if (!block || !out_data || !out_len)
    {
        return -1;
    }

    *out_data = NULL;
    *out_len = 0;

    size_t encoded_capacity = 0;
    if (lantern_ssz_encode_signed_block(block, NULL, 0, &encoded_capacity) != SSZ_SUCCESS
        || encoded_capacity == 0)
    {
        return -1;
    }

    uint8_t *buffer = malloc(encoded_capacity);
    if (!buffer)
    {
        return -1;
    }

    size_t written = 0;
    const ssz_error_t encode_rc = lantern_ssz_encode_signed_block(
        block,
        buffer,
        encoded_capacity,
        &written);
    if (encode_rc != 0 || written == 0 || written > encoded_capacity)
    {
        free(buffer);
        return -1;
    }

    *out_data = buffer;
    *out_len = written;
    return 0;
}

static void persist_invalid_block_on_state_transition_failure(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    const struct lantern_log_metadata *meta)
{
    if (!client || !client->data_dir || !block || !block_root)
    {
        return;
    }

    uint8_t *encoded_block = NULL;
    size_t encoded_block_len = 0;
    const uint8_t *bytes_to_write = raw_block_ssz;
    size_t bytes_to_write_len = raw_block_ssz_len;

    if (!bytes_to_write || bytes_to_write_len == 0)
    {
        if (encode_block_ssz(block, &encoded_block, &encoded_block_len) != 0)
        {
            lantern_log_warn(
                "storage",
                meta,
                "failed to encode invalid block slot=%" PRIu64 " for persistence",
                block->block.slot);
            return;
        }
        bytes_to_write = encoded_block;
        bytes_to_write_len = encoded_block_len;
    }

    if (lantern_storage_store_invalid_block_bytes_for_root(
            client->data_dir,
            block_root,
            bytes_to_write,
            bytes_to_write_len)
        != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist invalid block slot=%" PRIu64,
            block->block.slot);
    }

    free(encoded_block);
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

struct lantern_root_chain_entry
{
    LanternRoot root;
    LanternRoot parent_root;
    uint64_t slot;
    bool has_parent;
};

struct lantern_root_chain
{
    struct lantern_root_chain_entry *items;
    size_t length;
    size_t capacity;
};

static void root_chain_reset(struct lantern_root_chain *chain)
{
    if (!chain)
    {
        return;
    }
    free(chain->items);
    chain->items = NULL;
    chain->length = 0;
    chain->capacity = 0;
}

static bool root_chain_contains(const struct lantern_root_chain *chain, const LanternRoot *root)
{
    if (!chain || !root)
    {
        return false;
    }
    for (size_t i = 0; i < chain->length; ++i)
    {
        if (memcmp(chain->items[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return true;
        }
    }
    return false;
}

static bool root_chain_append(
    struct lantern_root_chain *chain,
    const LanternRoot *root,
    const LanternRoot *parent_root,
    uint64_t slot,
    bool has_parent)
{
    if (!chain || !root || !parent_root)
    {
        return false;
    }
    if (chain->length == chain->capacity)
    {
        size_t next_capacity = chain->capacity > 0 ? chain->capacity + (chain->capacity / 2u) : 4u;
        if (next_capacity < chain->capacity)
        {
            return false;
        }
        if (next_capacity > SIZE_MAX / sizeof(*chain->items))
        {
            return false;
        }
        struct lantern_root_chain_entry *expanded = realloc(
            chain->items,
            next_capacity * sizeof(*expanded));
        if (!expanded)
        {
            return false;
        }
        chain->items = expanded;
        chain->capacity = next_capacity;
    }
    struct lantern_root_chain_entry *entry = &chain->items[chain->length];
    entry->root = *root;
    entry->parent_root = *parent_root;
    entry->slot = slot;
    entry->has_parent = has_parent;
    chain->length += 1u;
    return true;
}

static bool build_root_chain_locked(
    struct lantern_client *client,
    const LanternRoot *target_root,
    const LanternRoot *stop_root,
    bool allow_stop_at_or_before_slot,
    uint64_t stop_slot,
    struct lantern_root_chain *out_chain)
{
    if (!client || !target_root || !out_chain || !client->has_fork_choice)
    {
        return false;
    }
    root_chain_reset(out_chain);

    LanternRoot current = *target_root;
    const bool has_stop_root = stop_root && !lantern_root_is_zero(stop_root);
    bool reached_stop_boundary = false;
    size_t steps = 0;
    while (!lantern_root_is_zero(&current))
    {
        if (steps > LANTERN_HISTORICAL_ROOTS_LIMIT)
        {
            return false;
        }
        if (root_chain_contains(out_chain, &current))
        {
            return false;
        }

        LanternRoot parent = {0};
        uint64_t slot = 0;
        bool has_parent = false;
        if (lantern_fork_choice_block_info(
                &client->fork_choice,
                &current,
                &slot,
                &parent,
                &has_parent)
            != 0)
        {
            return false;
        }

        if (has_stop_root
            && memcmp(current.bytes, stop_root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            reached_stop_boundary = true;
            break;
        }

        if (allow_stop_at_or_before_slot && slot <= stop_slot)
        {
            reached_stop_boundary = true;
            break;
        }

        if (!root_chain_append(out_chain, &current, &parent, slot, has_parent))
        {
            return false;
        }

        if (!has_parent || lantern_root_is_zero(&parent))
        {
            break;
        }

        current = parent;
        steps += 1u;
    }

    if (has_stop_root || allow_stop_at_or_before_slot)
    {
        return reached_stop_boundary;
    }

    return out_chain->length > 0;
}

static bool resolve_replay_validator_pubkeys(
    const struct lantern_client *client,
    const struct lantern_log_metadata *meta,
    const uint8_t **out_attestation_pubkeys,
    const uint8_t **out_proposal_pubkeys,
    size_t *out_validator_count,
    bool *out_allocated_pubkeys)
{
    if (!client
        || !out_attestation_pubkeys
        || !out_proposal_pubkeys
        || !out_validator_count
        || !out_allocated_pubkeys)
    {
        return false;
    }

    const struct lantern_chain_config *config = &client->genesis.chain_config;
    size_t validator_count = config->validator_pubkeys_count;
    const uint8_t *attestation_pubkeys = config->validator_attestation_pubkeys;
    const uint8_t *proposal_pubkeys = config->validator_proposal_pubkeys;
    bool allocated_pubkeys = false;

    if (!attestation_pubkeys || !proposal_pubkeys || validator_count == 0)
    {
        size_t registry_count = client->genesis.validator_registry.count;
        if (registry_count > 0 && registry_count == config->validator_count)
        {
            if (registry_count > (SIZE_MAX / 2u) / LANTERN_VALIDATOR_PUBKEY_SIZE)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state registry pubkey size overflow count=%zu",
                    registry_count);
                return false;
            }

            validator_count = registry_count;
            size_t pubkeys_len = validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
            uint8_t *buffer = calloc(pubkeys_len * 2u, sizeof(*buffer));
            if (!buffer)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state failed to allocate registry pubkey buffers len=%zu",
                    pubkeys_len * 2u);
                return false;
            }
            uint8_t *attestation_buffer = buffer;
            uint8_t *proposal_buffer = buffer + pubkeys_len;
            bool pubkey_ok = true;
            for (size_t i = 0; i < validator_count; ++i)
            {
                const struct lantern_validator_record *rec =
                    &client->genesis.validator_registry.records[i];
                uint8_t *dest = attestation_buffer + (i * LANTERN_VALIDATOR_PUBKEY_SIZE);
                if (rec->has_pubkey_bytes)
                {
                    memcpy(dest, rec->pubkey_bytes, LANTERN_VALIDATOR_PUBKEY_SIZE);
                }
                else if (rec->pubkey_hex
                         && lantern_hex_decode(
                             rec->pubkey_hex,
                             dest,
                             LANTERN_VALIDATOR_PUBKEY_SIZE)
                             == 0)
                {
                    /* decoded */
                }
                else
                {
                    pubkey_ok = false;
                    break;
                }
                memcpy(
                    proposal_buffer + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                    dest,
                    LANTERN_VALIDATOR_PUBKEY_SIZE);
            }
            if (!pubkey_ok)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state failed to populate registry pubkeys");
                free(buffer);
                return false;
            }
            attestation_pubkeys = attestation_buffer;
            proposal_pubkeys = proposal_buffer;
            allocated_pubkeys = true;
        }
        else if (client->state.validators && client->state.validator_count > 0)
        {
            size_t state_count = client->state.validator_count;
            if (state_count > (SIZE_MAX / 2u) / LANTERN_VALIDATOR_PUBKEY_SIZE)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state state pubkey size overflow count=%zu",
                    state_count);
                return false;
            }
            validator_count = state_count;
            size_t pubkeys_len = validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
            uint8_t *buffer = calloc(pubkeys_len * 2u, sizeof(*buffer));
            if (!buffer)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state failed to allocate state pubkey buffers len=%zu",
                    pubkeys_len * 2u);
                return false;
            }
            uint8_t *attestation_buffer = buffer;
            uint8_t *proposal_buffer = buffer + pubkeys_len;
            for (size_t i = 0; i < validator_count; ++i)
            {
                const LanternValidator *validator = &client->state.validators[i];
                memcpy(
                    attestation_buffer + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                    validator->attestation_pubkey,
                    LANTERN_VALIDATOR_PUBKEY_SIZE);
                memcpy(
                    proposal_buffer + (i * LANTERN_VALIDATOR_PUBKEY_SIZE),
                    validator->proposal_pubkey,
                    LANTERN_VALIDATOR_PUBKEY_SIZE);
            }
            attestation_pubkeys = attestation_buffer;
            proposal_pubkeys = proposal_buffer;
            allocated_pubkeys = true;
        }
        else
        {
            lantern_log_warn(
                "state",
                meta,
                "init_replay_state missing validator pubkeys");
            return false;
        }
    }

    if (validator_count == 0)
    {
        if (allocated_pubkeys)
        {
            free((void *)attestation_pubkeys);
        }
        lantern_log_warn(
            "state",
            meta,
            "init_replay_state invalid validator_count=0");
        return false;
    }

    *out_attestation_pubkeys = attestation_pubkeys;
    *out_proposal_pubkeys = proposal_pubkeys;
    *out_validator_count = validator_count;
    *out_allocated_pubkeys = allocated_pubkeys;
    return true;
}

static bool init_replay_state(const struct lantern_client *client, LanternState *out_state)
{
    if (!client || !out_state)
    {
        return false;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    lantern_state_reset(out_state);
    lantern_state_init(out_state);

    if (client->genesis.state_bytes && client->genesis.state_size > 0)
    {
        lantern_log_debug(
            "state",
            &meta,
            "init_replay_state ignoring local genesis state bytes size=%zu",
            client->genesis.state_size);
    }

    const uint8_t *attestation_pubkeys = NULL;
    const uint8_t *proposal_pubkeys = NULL;
    size_t validator_count = 0;
    bool allocated_pubkeys = false;
    if (!resolve_replay_validator_pubkeys(
            client,
            &meta,
            &attestation_pubkeys,
            &proposal_pubkeys,
            &validator_count,
            &allocated_pubkeys))
    {
        lantern_state_reset(out_state);
        return false;
    }

    const struct lantern_chain_config *config = &client->genesis.chain_config;
    if (lantern_state_generate_genesis(
            out_state,
            config->genesis_time,
            (uint64_t)validator_count)
        != 0)
    {
        if (allocated_pubkeys)
        {
            free((void *)attestation_pubkeys);
        }
        lantern_log_warn(
            "state",
            &meta,
            "init_replay_state failed to generate genesis time=%" PRIu64 " validators=%zu",
            config->genesis_time,
            validator_count);
        lantern_state_reset(out_state);
        return false;
    }

    if (lantern_state_set_validator_pubkeys_dual(
            out_state,
            attestation_pubkeys,
            proposal_pubkeys,
            validator_count)
        != 0)
    {
        if (allocated_pubkeys)
        {
            free((void *)attestation_pubkeys);
        }
        lantern_log_warn(
            "state",
            &meta,
            "init_replay_state failed to set validator pubkey pairs count=%zu",
            validator_count);
        lantern_state_reset(out_state);
        return false;
    }

    if (allocated_pubkeys)
    {
        free((void *)attestation_pubkeys);
    }

    return true;
}

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
    if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, out_root) != SSZ_SUCCESS)
    {
        return false;
    }
    return true;
}

static bool rebuild_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *target_root,
    LanternState *out_state,
    LanternRoot *out_missing_roots,
    size_t missing_roots_cap,
    size_t *out_missing_count);
static void cache_rebuilt_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    const LanternState *state,
    const struct lantern_log_metadata *meta,
    const char *context);

static bool state_matches_root(const LanternState *state, const LanternRoot *root)
{
    if (!state || !root)
    {
        return false;
    }
    LanternRoot state_root;
    if (lantern_hash_tree_root_state(state, &state_root) != SSZ_SUCCESS)
    {
        return false;
    }
    LanternBlockHeader header = state->latest_block_header;
    header.state_root = state_root;
    LanternRoot header_root;
    if (lantern_hash_tree_root_block_header(&header, &header_root) != SSZ_SUCCESS)
    {
        return false;
    }
    return memcmp(header_root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0;
}

static bool load_snapshot_state_for_root_locked(
    const struct lantern_client *client,
    const LanternRoot *root,
    LanternState *out_state,
    size_t *out_state_len)
{
    if (out_state_len)
    {
        *out_state_len = 0;
    }
    if (!client || !root || !out_state || !client->data_dir || client->data_dir[0] == '\0')
    {
        return false;
    }

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
        return false;
    }

    LanternState decoded;
    lantern_state_init(&decoded);
    bool decoded_owned = true;
    bool loaded = false;
    if (lantern_ssz_decode_state(&decoded, state_bytes, state_len) == SSZ_SUCCESS)
    {
        lantern_state_reset(out_state);
        *out_state = decoded;
        decoded_owned = false;
        loaded = true;
        if (out_state_len)
        {
            *out_state_len = state_len;
        }
    }

    if (decoded_owned)
    {
        lantern_state_reset(&decoded);
    }
    free(state_bytes);
    return loaded;
}

static bool load_replay_base_from_finalized_locked(
    struct lantern_client *client,
    const LanternRoot *finalized_root,
    LanternState *out_state,
    const char **out_source,
    size_t *out_source_len)
{
    if (out_source)
    {
        *out_source = NULL;
    }
    if (out_source_len)
    {
        *out_source_len = 0;
    }
    if (!client || !finalized_root || !out_state || lantern_root_is_zero(finalized_root))
    {
        return false;
    }

    if (client->has_state && state_matches_root(&client->state, finalized_root))
    {
        if (lantern_state_clone(&client->state, out_state) == 0)
        {
            if (out_source)
            {
                *out_source = "head";
            }
            return true;
        }
    }

    if (client->has_fork_choice)
    {
        const LanternState *cached_state =
            lantern_fork_choice_block_state(&client->fork_choice, finalized_root);
        if (cached_state && lantern_state_clone(cached_state, out_state) == 0)
        {
            if (out_source)
            {
                *out_source = "fork_choice_cache";
            }
            return true;
        }
    }

    if (client->data_dir && client->data_dir[0] != '\0')
    {
        LanternState persisted_finalized;
        lantern_state_init(&persisted_finalized);
        if (lantern_storage_load_finalized_state(client->data_dir, &persisted_finalized) == 0
            && state_matches_root(&persisted_finalized, finalized_root))
        {
            *out_state = persisted_finalized;
            if (out_source)
            {
                *out_source = "finalized_state";
            }
            return true;
        }
        lantern_state_reset(&persisted_finalized);
    }

    size_t snapshot_len = 0;
    if (load_snapshot_state_for_root_locked(client, finalized_root, out_state, &snapshot_len))
    {
        cache_rebuilt_state_for_root_locked(
            client,
            finalized_root,
            out_state,
            NULL,
            "finalized_base_snapshot");
        if (out_source)
        {
            *out_source = "state_for_root";
        }
        if (out_source_len)
        {
            *out_source_len = snapshot_len;
        }
        return true;
    }

    if (client->data_dir && client->data_dir[0] != '\0')
    {
        LanternState persisted;
        lantern_state_init(&persisted);
        if (lantern_storage_load_state(client->data_dir, &persisted) == 0
            && state_matches_root(&persisted, finalized_root))
        {
            *out_state = persisted;
            if (out_source)
            {
                *out_source = "state";
            }
            return true;
        }
        lantern_state_reset(&persisted);
    }

    return false;
}

static void cache_rebuilt_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    const LanternState *state,
    const struct lantern_log_metadata *meta,
    const char *context)
{
    if (!client || !root || !state)
    {
        return;
    }

    if (client->has_fork_choice
        && lantern_fork_choice_set_block_state(&client->fork_choice, root, state) != 0)
    {
        char root_hex[ROOT_HEX_BUFFER_LEN];
        struct lantern_log_metadata fallback_meta = {.validator = client->node_id};
        const struct lantern_log_metadata *log_meta = meta ? meta : &fallback_meta;
        format_root_hex(root, root_hex, sizeof(root_hex));
        lantern_log_warn(
            "forkchoice",
            log_meta,
            "failed to cache in-memory state root=%s slot=%" PRIu64 " context=%s",
            root_hex[0] ? root_hex : "0x0",
            state->slot,
            context ? context : "unknown");
    }

    if (!client->data_dir || !client->data_dir[0])
    {
        return;
    }

    if (lantern_storage_store_state_for_root(client->data_dir, root, state) != 0)
    {
        char root_hex[ROOT_HEX_BUFFER_LEN];
        struct lantern_log_metadata fallback_meta = {.validator = client->node_id};
        const struct lantern_log_metadata *log_meta = meta ? meta : &fallback_meta;
        format_root_hex(root, root_hex, sizeof(root_hex));
        lantern_log_warn(
            "storage",
            log_meta,
            "failed to cache rebuilt state root=%s slot=%" PRIu64 " context=%s",
            root_hex[0] ? root_hex : "0x0",
            state->slot,
            context ? context : "unknown");
    }
}

const LanternState *lantern_client_state_for_root_local_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    LanternState *scratch,
    bool *out_is_scratch)
{
    if (out_is_scratch)
    {
        *out_is_scratch = false;
    }
    if (!client || !root)
    {
        return NULL;
    }

    if (client->has_state && state_matches_root(&client->state, root))
    {
        return &client->state;
    }

    if (client->has_fork_choice)
    {
        const LanternState *cached_state =
            lantern_fork_choice_block_state(&client->fork_choice, root);
        if (cached_state)
        {
            return cached_state;
        }
    }

    if (!scratch)
    {
        return NULL;
    }

    if (client->data_dir && client->data_dir[0])
    {
        size_t snapshot_len = 0;
        if (load_snapshot_state_for_root_locked(client, root, scratch, &snapshot_len))
        {
            (void)snapshot_len;
            cache_rebuilt_state_for_root_locked(
                client,
                root,
                scratch,
                NULL,
                "state_for_root_snapshot");
            if (out_is_scratch)
            {
                *out_is_scratch = true;
            }
            return scratch;
        }
    }

    if (client->data_dir && client->data_dir[0] && scratch)
    {
        lantern_state_reset(scratch);
        lantern_state_init(scratch);
        if (load_replay_base_from_finalized_locked(
                client,
                root,
                scratch,
                NULL,
                NULL))
        {
            if (out_is_scratch)
            {
                *out_is_scratch = true;
            }
            return scratch;
        }
        lantern_state_reset(scratch);
    }

    return NULL;
}

const LanternState *lantern_client_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    LanternState *scratch,
    bool *out_is_scratch)
{
    const LanternState *state = lantern_client_state_for_root_local_locked(
        client,
        root,
        scratch,
        out_is_scratch);
    if (state)
    {
        return state;
    }

    if (client->data_dir && client->data_dir[0])
    {
        lantern_state_reset(scratch);
        if (rebuild_state_for_root_locked(client, root, scratch, NULL, 0, NULL))
        {
            if (out_is_scratch)
            {
                *out_is_scratch = true;
            }
            return scratch;
        }
        lantern_state_reset(scratch);
    }

    return NULL;
}

bool lantern_client_find_missing_state_root_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    LanternRoot *out_missing_root)
{
    if (!client || !root || !out_missing_root || !client->has_fork_choice)
    {
        return false;
    }

    memset(out_missing_root, 0, sizeof(*out_missing_root));

    LanternRoot replay_stop_root = {0};
    uint64_t replay_stop_slot = 0;
    uint64_t anchor_slot = 0;
    bool allow_anchor_slot_stop = false;

    const LanternCheckpoint *fork_latest_finalized =
        lantern_fork_choice_latest_finalized(&client->fork_choice);
    if (fork_latest_finalized)
    {
        replay_stop_root = fork_latest_finalized->root;
        replay_stop_slot = fork_latest_finalized->slot;
    }
    else if (client->has_state)
    {
        replay_stop_root = client->state.latest_finalized.root;
        replay_stop_slot = client->state.latest_finalized.slot;
    }

    if (!lantern_root_is_zero(&replay_stop_root))
    {
        const LanternRoot *anchor_root =
            lantern_fork_choice_anchor_root(&client->fork_choice);
        if (anchor_root
            && memcmp(
                   anchor_root->bytes,
                   replay_stop_root.bytes,
                   LANTERN_ROOT_SIZE)
                == 0
            && lantern_fork_choice_anchor_slot(
                   &client->fork_choice,
                   &anchor_slot)
                == 0
            && replay_stop_slot < anchor_slot)
        {
            allow_anchor_slot_stop = true;
        }
    }

    LanternRoot current = *root;
    size_t steps = 0;
    while (!lantern_root_is_zero(&current))
    {
        if (steps > LANTERN_HISTORICAL_ROOTS_LIMIT)
        {
            return false;
        }

        uint64_t slot = 0;
        LanternRoot parent = {0};
        bool has_parent = false;
        if (lantern_fork_choice_block_info(
                &client->fork_choice,
                &current,
                &slot,
                &parent,
                &has_parent)
            != 0)
        {
            *out_missing_root = current;
            return true;
        }

        if (!lantern_root_is_zero(&replay_stop_root)
            && memcmp(
                   current.bytes,
                   replay_stop_root.bytes,
                   LANTERN_ROOT_SIZE)
                == 0)
        {
            return false;
        }

        if (allow_anchor_slot_stop && slot <= anchor_slot)
        {
            return false;
        }

        if (!has_parent || lantern_root_is_zero(&parent))
        {
            if (!lantern_root_is_zero(&replay_stop_root) || allow_anchor_slot_stop)
            {
                *out_missing_root = current;
                return true;
            }
            return false;
        }

        current = parent;
        steps += 1u;
    }

    return false;
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
    if (client->has_fork_choice)
    {
        if (lantern_fork_choice_update_checkpoints(
                &client->fork_choice,
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

static bool rebuild_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *target_root,
    LanternState *out_state,
    LanternRoot *out_missing_roots,
    size_t missing_roots_cap,
    size_t *out_missing_count)
{
    if (!client || !target_root || !out_state)
    {
        return false;
    }
    lantern_state_reset(out_state);
    if (out_missing_count)
    {
        *out_missing_count = 0;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    char target_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(target_root, target_hex, sizeof(target_hex));

    if (client->has_fork_choice)
    {
        const LanternState *cached_state =
            lantern_fork_choice_block_state(&client->fork_choice, target_root);
        if (cached_state)
        {
            if (lantern_state_clone(cached_state, out_state) == 0)
            {
                lantern_log_debug(
                    "state",
                    &meta,
                    "rebuild_state used fork-choice cache target=%s",
                    target_hex[0] ? target_hex : "0x0");
                return true;
            }
            lantern_state_reset(out_state);
            lantern_log_warn(
                "state",
                &meta,
                "rebuild_state failed to clone fork-choice cache target=%s",
                target_hex[0] ? target_hex : "0x0");
        }
    }

    size_t snapshot_len = 0;
    if (load_snapshot_state_for_root_locked(client, target_root, out_state, &snapshot_len))
    {
        cache_rebuilt_state_for_root_locked(
            client,
            target_root,
            out_state,
            &meta,
            "rebuild_snapshot");
        lantern_log_debug(
            "state",
            &meta,
            "rebuild_state loaded snapshot target=%s bytes=%zu",
            target_hex[0] ? target_hex : "0x0",
            snapshot_len);
        return true;
    }

    struct lantern_root_chain chain = {0};
    LanternState replay_base_state;
    lantern_state_init(&replay_base_state);
    bool have_replay_base_state = false;
    bool use_finalized_shortcut = false;
    LanternRoot replay_stop_root = {0};
    uint64_t replay_stop_slot = 0;
    uint64_t anchor_slot = 0;
    bool allow_anchor_slot_stop = false;
    char replay_stop_hex[ROOT_HEX_BUFFER_LEN] = {0};

    if (client->has_fork_choice)
    {
        const LanternCheckpoint *fork_latest_finalized =
            lantern_fork_choice_latest_finalized(&client->fork_choice);
        if (fork_latest_finalized)
        {
            replay_stop_root = fork_latest_finalized->root;
            replay_stop_slot = fork_latest_finalized->slot;
        }
    }
    else if (client->has_state)
    {
        replay_stop_root = client->state.latest_finalized.root;
        replay_stop_slot = client->state.latest_finalized.slot;
    }
    if (!lantern_root_is_zero(&replay_stop_root))
    {
        if (client->has_fork_choice)
        {
            const LanternRoot *anchor_root =
                lantern_fork_choice_anchor_root(&client->fork_choice);
            if (anchor_root
                && memcmp(
                       anchor_root->bytes,
                       replay_stop_root.bytes,
                       LANTERN_ROOT_SIZE)
                    == 0
                && lantern_fork_choice_anchor_slot(
                       &client->fork_choice,
                       &anchor_slot)
                    == 0
                && replay_stop_slot < anchor_slot)
            {
                allow_anchor_slot_stop = true;
            }
        }

        const char *replay_base_source = NULL;
        size_t replay_base_bytes = 0;
        format_root_hex(&replay_stop_root, replay_stop_hex, sizeof(replay_stop_hex));
        if (!load_replay_base_from_finalized_locked(
                client,
                &replay_stop_root,
                &replay_base_state,
                &replay_base_source,
                &replay_base_bytes))
        {
            lantern_log_error(
                "state",
                &meta,
                "rebuild_state missing finalized replay base target=%s finalized=%s",
                target_hex[0] ? target_hex : "0x0",
                replay_stop_hex[0] ? replay_stop_hex : "0x0");
            root_chain_reset(&chain);
            return false;
        }

        have_replay_base_state = true;
        if (!build_root_chain_locked(
                client,
                target_root,
                &replay_stop_root,
                allow_anchor_slot_stop,
                anchor_slot,
                &chain))
        {
            lantern_log_error(
                "state",
                &meta,
                "rebuild_state failed to build finalized root chain target=%s finalized=%s",
                target_hex[0] ? target_hex : "0x0",
                replay_stop_hex[0] ? replay_stop_hex : "0x0");
            root_chain_reset(&chain);
            lantern_state_reset(&replay_base_state);
            return false;
        }

        use_finalized_shortcut = true;
        lantern_log_info(
            "state",
            &meta,
            "rebuild_state using finalized base target=%s finalized=%s source=%s bytes=%zu stop=%s",
            target_hex[0] ? target_hex : "0x0",
            replay_stop_hex[0] ? replay_stop_hex : "0x0",
            replay_base_source ? replay_base_source : "unknown",
            replay_base_bytes,
            allow_anchor_slot_stop ? "anchor_slot" : "exact_root");
    }
    else if (!build_root_chain_locked(client, target_root, NULL, false, 0, &chain))
    {
        lantern_log_warn(
            "state",
            &meta,
            "rebuild_state failed to build root chain target=%s",
            target_hex[0] ? target_hex : "0x0");
        root_chain_reset(&chain);
        if (have_replay_base_state)
        {
            lantern_state_reset(&replay_base_state);
        }
        return false;
    }

    size_t root_count = 0;
    for (size_t i = 0; i < chain.length; ++i)
    {
        if (chain.items[i].slot != 0)
        {
            root_count += 1u;
        }
    }

    lantern_log_info(
        "state",
        &meta,
        "rebuild_state start target=%s mode=%s chain_len=%zu root_count=%zu",
        target_hex[0] ? target_hex : "0x0",
        use_finalized_shortcut ? "finalized" : "genesis",
        chain.length,
        root_count);

    LanternRoot *roots = NULL;
    if (root_count > 0)
    {
        if (!client->data_dir || !client->data_dir[0])
        {
            root_chain_reset(&chain);
            if (have_replay_base_state)
            {
                lantern_state_reset(&replay_base_state);
            }
            return false;
        }
        roots = calloc(root_count, sizeof(*roots));
        if (!roots)
        {
            root_chain_reset(&chain);
            if (have_replay_base_state)
            {
                lantern_state_reset(&replay_base_state);
            }
            return false;
        }
        size_t idx = 0;
        for (size_t i = chain.length; i-- > 0;)
        {
            if (chain.items[i].slot == 0)
            {
                continue;
            }
            roots[idx++] = chain.items[i].root;
        }
    }

    LanternSignedBlockList response;
    lantern_signed_block_list_init(&response);
    int collect_rc = 0;
    if (root_count > 0)
    {
        collect_rc = lantern_storage_collect_blocks(
            client->data_dir,
            roots,
            root_count,
            &response);
    }
    if (collect_rc != 0 || response.length != root_count)
    {
        lantern_log_warn(
            "state",
            &meta,
            "rebuild_state block collection mismatch target=%s collect_rc=%d expected=%zu got=%zu",
            target_hex[0] ? target_hex : "0x0",
            collect_rc,
            root_count,
            response.length);
        if (roots && root_count > 0)
        {
            LanternRoot *found_roots = NULL;
            size_t found_count = 0;
            if (response.length > 0)
            {
                found_roots = calloc(response.length, sizeof(*found_roots));
                if (found_roots)
                {
                    for (size_t i = 0; i < response.length; ++i)
                    {
                        if (lantern_hash_tree_root_block(&response.blocks[i].block, &found_roots[i]) == SSZ_SUCCESS)
                        {
                            found_count += 1u;
                        }
                    }
                }
            }
            size_t missing = 0;
            size_t logged = 0;
            size_t missing_filled = 0;
            for (size_t i = 0; i < root_count; ++i)
            {
                bool present = false;
                if (found_roots)
                {
                    for (size_t j = 0; j < response.length; ++j)
                    {
                        if (memcmp(roots[i].bytes, found_roots[j].bytes, LANTERN_ROOT_SIZE) == 0)
                        {
                            present = true;
                            break;
                        }
                    }
                }
                if (!present)
                {
                    missing += 1u;
                    if (out_missing_roots && missing_filled < missing_roots_cap)
                    {
                        out_missing_roots[missing_filled] = roots[i];
                        missing_filled += 1u;
                    }
                    if (logged < 5)
                    {
                        char missing_hex[ROOT_HEX_BUFFER_LEN];
                        format_root_hex(&roots[i], missing_hex, sizeof(missing_hex));
                        lantern_log_warn(
                            "state",
                            &meta,
                            "rebuild_state missing block root=%s",
                            missing_hex[0] ? missing_hex : "0x0");
                        logged += 1u;
                    }
                }
            }
            if (out_missing_count)
            {
                *out_missing_count = missing_filled;
            }
            lantern_log_warn(
                "state",
                &meta,
                "rebuild_state missing_blocks=%zu found_blocks=%zu",
                missing,
                found_count);
            free(found_roots);
        }
    }
    free(roots);
    roots = NULL;
    if (collect_rc != 0 || response.length != root_count)
    {
        lantern_signed_block_list_reset(&response);
        root_chain_reset(&chain);
        if (have_replay_base_state)
        {
            lantern_state_reset(&replay_base_state);
        }
        return false;
    }

    bool success = false;
    if (use_finalized_shortcut)
    {
        lantern_state_reset(out_state);
        *out_state = replay_base_state;
        lantern_state_init(&replay_base_state);
        have_replay_base_state = false;
        success = true;
    }
    else
    {
        success = init_replay_state(client, out_state);
    }
    if (!success)
    {
        lantern_log_warn(
            "state",
            &meta,
            "rebuild_state failed to initialize replay state target=%s mode=%s",
            target_hex[0] ? target_hex : "0x0",
            use_finalized_shortcut ? "finalized" : "genesis");
        lantern_signed_block_list_reset(&response);
        root_chain_reset(&chain);
        if (have_replay_base_state)
        {
            lantern_state_reset(&replay_base_state);
        }
        return false;
    }

    LanternStore replay_store;
    lantern_store_init(&replay_store);
    if (lantern_store_prepare_validator_votes(&replay_store, out_state->config.num_validators) != 0)
    {
        lantern_signed_block_list_reset(&response);
        root_chain_reset(&chain);
        lantern_state_reset(out_state);
        if (have_replay_base_state)
        {
            lantern_state_reset(&replay_base_state);
        }
        lantern_store_reset(&replay_store);
        return false;
    }

    for (size_t i = 0; i < response.length; ++i)
    {
        int transition_rc = lantern_state_transition(out_state, &replay_store, &response.blocks[i]);
        if (transition_rc != 0)
        {
            LanternRoot block_root = {0};
            char block_hex[ROOT_HEX_BUFFER_LEN] = {0};
            if (lantern_hash_tree_root_block(&response.blocks[i].block, &block_root) == SSZ_SUCCESS)
            {
                format_root_hex(&block_root, block_hex, sizeof(block_hex));
            }
            lantern_log_warn(
                "state",
                &meta,
                "rebuild_state transition failed idx=%zu slot=%" PRIu64 " rc=%d root=%s",
                i,
                response.blocks[i].block.slot,
                transition_rc,
                block_hex[0] ? block_hex : "0x0");
            lantern_signed_block_list_reset(&response);
            root_chain_reset(&chain);
            lantern_state_reset(out_state);
            if (have_replay_base_state)
            {
                lantern_state_reset(&replay_base_state);
            }
            lantern_store_reset(&replay_store);
            return false;
        }
    }

    lantern_store_reset(&replay_store);
    lantern_signed_block_list_reset(&response);
    root_chain_reset(&chain);
    if (have_replay_base_state)
    {
        lantern_state_reset(&replay_base_state);
    }
    cache_rebuilt_state_for_root_locked(
        client,
        target_root,
        out_state,
        &meta,
        "rebuild_state");
    return true;
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

        LanternRoot head_root = {0};
        uint64_t head_slot = client->state.slot;
        if (client->has_fork_choice
            && lantern_fork_choice_current_head(&client->fork_choice, &head_root) == 0)
        {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(
                    &client->fork_choice,
                    &head_root,
                    &fork_slot,
                    NULL,
                    NULL)
                == 0)
            {
                head_slot = fork_slot;
            }
        }
        const LanternRoot *anchor_root =
            client->has_fork_choice
                ? lantern_fork_choice_anchor_root(&client->fork_choice)
                : NULL;
        uint64_t anchor_slot = 0;
        bool have_anchor_slot =
            client->has_fork_choice
            && lantern_fork_choice_anchor_slot(&client->fork_choice, &anchor_slot) == 0;
        const LanternCheckpoint *store_latest_justified =
            client->has_fork_choice
                ? lantern_fork_choice_latest_justified(&client->fork_choice)
                : NULL;
        const LanternCheckpoint *store_latest_finalized =
            client->has_fork_choice
                ? lantern_fork_choice_latest_finalized(&client->fork_choice)
                : NULL;
        char block_hex[ROOT_HEX_BUFFER_LEN];
        char parent_hex[ROOT_HEX_BUFFER_LEN];
        char head_hex[ROOT_HEX_BUFFER_LEN];
        char anchor_hex[ROOT_HEX_BUFFER_LEN];
        char justified_hex[ROOT_HEX_BUFFER_LEN];
        char finalized_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(block_root, block_hex, sizeof(block_hex));
        format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
        format_root_hex(&head_root, head_hex, sizeof(head_hex));
        format_root_hex(anchor_root, anchor_hex, sizeof(anchor_hex));
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
            have_anchor_slot ? anchor_slot : 0u,
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

    /*
     * client->state may be adopted from replay when fork choice switches heads.
     * Late-arriving blocks from slots already covered by that adopted state
     * must be replayed from their parent state instead of transitioning the
     * adopted head state directly, or state_transition() will reject them as
     * stale and the ancestor never gets imported into fork choice.
     */
    if (block->block.slot <= client->state.slot)
    {
        lantern_log_debug(
            "state",
            meta,
            "routing late block to off-head replay slot=%" PRIu64 " state_slot=%" PRIu64,
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
    if (!client || !block || !block_root || !client->has_fork_choice)
    {
        return false;
    }

    if (lantern_fork_choice_add_block_with_state(
            &client->fork_choice,
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
    if (!client->has_fork_choice)
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
    LanternAttestations expanded;
    lantern_attestations_init(&expanded);
    size_t validator_count = lantern_state_validator_count(&client->state);
    if (lantern_expand_aggregated_attestations(attestations, validator_count, &expanded) != 0)
    {
        lantern_attestations_reset(&expanded);
        return false;
    }
    size_t skipped_constraints = 0;
    for (size_t i = 0; i < expanded.length; ++i)
    {
        struct lantern_vote_rejection_info rejection;
        memset(&rejection, 0, sizeof(rejection));
        if (!lantern_client_validate_vote_constraints(
                client,
                &expanded.data[i],
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
            continue;
        }
    }
    lantern_attestations_reset(&expanded);

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

    if (!client->has_runtime)
    {
        return;
    }
    struct lantern_slot_timepoint now_tp;
    uint64_t now_milliseconds = validator_wall_time_now_millis();
    if (lantern_slot_clock_compute(&client->runtime.clock, now_milliseconds, &now_tp) != 0)
    {
        return;
    }
    /* Live blocks only: skip backfill/sync imports of past slots, whose import
     * time bears no relation to their slot boundary. */
    if (now_tp.slot != block->block.slot)
    {
        return;
    }
    uint64_t slot_start_ms = 0;
    if (lantern_slot_clock_slot_start_time(&client->runtime.clock, block->block.slot, &slot_start_ms) != 0
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
    const struct lantern_log_metadata *meta)
{
    if (!client || !block)
    {
        return false;
    }

    LanternSignedBlock import_block = *block;
    if (lantern_state_transition(&client->state, &client->store, &import_block) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "state transition failed for slot=%" PRIu64,
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
    if (!client || !block || !client->has_fork_choice)
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

static bool historical_import_floor_slot_locked(
    struct lantern_client *client,
    uint64_t *out_finalized_slot)
{
    if (out_finalized_slot)
    {
        *out_finalized_slot = 0;
    }
    if (!client || !out_finalized_slot || !client->has_fork_choice)
    {
        return false;
    }

    const LanternCheckpoint *latest_finalized =
        lantern_fork_choice_latest_finalized(&client->fork_choice);
    if (!latest_finalized)
    {
        return false;
    }

    *out_finalized_slot = latest_finalized->slot;
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

static bool finalized_slot_advanced(
    const LanternCheckpoint *previous_finalized,
    const LanternCheckpoint *current_finalized)
{
    if (!previous_finalized || !current_finalized)
    {
        return false;
    }
    return current_finalized->slot > previous_finalized->slot;
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
    if (!finalized_slot_advanced(previous_finalized, current_finalized))
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
    if (!client || !previous_finalized || !client->has_fork_choice)
    {
        return;
    }

    const LanternCheckpoint *current_finalized = &client->state.latest_finalized;
    if (!finalized_checkpoint_advanced(previous_finalized, current_finalized))
    {
        return;
    }

    if (lantern_fork_choice_prune_states(&client->fork_choice) != 0)
    {
        lantern_log_warn(
            "forkchoice",
            meta,
            "failed to prune fork choice states finalized_slot=%" PRIu64,
            current_finalized->slot);
    }
}

static void persist_finalized_state_if_advanced_locked(
    struct lantern_client *client,
    const LanternCheckpoint *previous_finalized,
    const struct lantern_log_metadata *meta)
{
    if (!client
        || !previous_finalized
        || !client->data_dir
        || client->data_dir[0] == '\0')
    {
        return;
    }

    struct lantern_log_metadata fallback_meta = {.validator = client->node_id};
    const struct lantern_log_metadata *log_meta = meta ? meta : &fallback_meta;

    const LanternCheckpoint *current_finalized = &client->state.latest_finalized;
    if (!finalized_checkpoint_advanced(previous_finalized, current_finalized))
    {
        return;
    }

    char finalized_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(&current_finalized->root, finalized_hex, sizeof(finalized_hex));

    const LanternState *finalized_state = NULL;
    LanternState loaded_finalized_state;
    lantern_state_init(&loaded_finalized_state);
    bool loaded_finalized_state_owned = false;

    if (client->has_fork_choice)
    {
        finalized_state =
            lantern_fork_choice_block_state(&client->fork_choice, &current_finalized->root);
        if (finalized_state
            && !state_matches_root(finalized_state, &current_finalized->root))
        {
            finalized_state = NULL;
        }
    }
    if (!finalized_state
        && client->has_state
        && state_matches_root(&client->state, &current_finalized->root))
    {
        finalized_state = &client->state;
    }
    if (!finalized_state
        && load_snapshot_state_for_root_locked(
               client,
               &current_finalized->root,
               &loaded_finalized_state,
               NULL))
    {
        loaded_finalized_state_owned = true;
        if (state_matches_root(&loaded_finalized_state, &current_finalized->root))
        {
            finalized_state = &loaded_finalized_state;
        }
    }
    if (!finalized_state)
    {
        lantern_log_warn(
            "storage",
            log_meta,
            "failed to find finalized replay state finalized_slot=%" PRIu64 " root=%s head_slot=%" PRIu64,
            current_finalized->slot,
            finalized_hex[0] ? finalized_hex : "0x0",
            client->state.slot);
        goto cleanup;
    }

    if (lantern_storage_store_state_for_root(
            client->data_dir,
            &current_finalized->root,
            finalized_state)
        != 0)
    {
        lantern_log_warn(
            "storage",
            log_meta,
            "failed to persist finalized root state finalized_slot=%" PRIu64 " root=%s head_slot=%" PRIu64,
            current_finalized->slot,
            finalized_hex[0] ? finalized_hex : "0x0",
            client->state.slot);
        goto cleanup;
    }

    if (lantern_storage_save_finalized_state(client->data_dir, finalized_state) != 0)
    {
        lantern_log_warn(
            "storage",
            log_meta,
            "failed to persist finalized replay state finalized_slot=%" PRIu64 " head_slot=%" PRIu64,
            current_finalized->slot,
            client->state.slot);
        goto cleanup;
    }

    lantern_log_info(
        "storage",
        log_meta,
        "persisted finalized replay state slot=%" PRIu64 " root=%s head_slot=%" PRIu64,
        current_finalized->slot,
        finalized_hex[0] ? finalized_hex : "0x0",
        client->state.slot);

    int pruned = lantern_storage_prune_before_slot(
        client->data_dir,
        current_finalized->slot,
        &current_finalized->root,
        1u);
    if (pruned < 0)
    {
        lantern_log_warn(
            "storage",
            log_meta,
            "failed to prune persisted pre-finalized data finalized_slot=%" PRIu64
            " root=%s",
            current_finalized->slot,
            finalized_hex[0] ? finalized_hex : "0x0");
    }
    else if (pruned > 0)
    {
        lantern_log_info(
            "storage",
            log_meta,
            "pruned persisted pre-finalized data finalized_slot=%" PRIu64
            " root=%s entries=%d",
            current_finalized->slot,
            finalized_hex[0] ? finalized_hex : "0x0",
            pruned);
    }

cleanup:
    if (loaded_finalized_state_owned)
    {
        lantern_state_reset(&loaded_finalized_state);
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
    if (lantern_storage_save_votes(client->data_dir, &client->state, &client->store) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist votes after slot=%" PRIu64,
            client->state.slot);
    }
}

/**
 * @brief Persist per-block post-state and sync indices.
 *
 * @param client     Client instance
 * @param post_state Post-state after applying the block
 * @param block      Imported block
 * @param block_root Root of the block
 * @param head_root  Current head root
 * @param head_slot  Current head slot
 * @param meta       Logging metadata
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void persist_post_state_and_indices_locked(
    const struct lantern_client *client,
    const LanternState *post_state,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *head_root,
    uint64_t head_slot,
    const struct lantern_log_metadata *meta)
{
    if (!client || !client->data_dir || !post_state || !block || !block_root)
    {
        return;
    }

    if (lantern_storage_store_state_for_root(client->data_dir, block_root, post_state) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist post-state slot=%" PRIu64,
            block->block.slot);
    }
    if (lantern_storage_store_slot_root(
            client->data_dir,
            block->block.slot,
            block_root)
        != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist slot index slot=%" PRIu64,
            block->block.slot);
    }
    if (lantern_storage_store_head_root(client->data_dir, head_slot, head_root) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist head index slot=%" PRIu64,
            head_slot);
    }
    if (lantern_storage_store_checkpoints(
            client->data_dir,
            &post_state->latest_justified,
            &post_state->latest_finalized)
        != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist checkpoints slot=%" PRIu64,
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
 * @param backfill_depth Backfill depth of the block
 * @param raw_block_ssz Optional raw SSZ bytes for the block
 * @param raw_block_ssz_len Length of `raw_block_ssz`
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
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    bool drain_pending_children,
    bool *out_children_ready,
    lantern_client_error *out_result)
{
    if (out_children_ready)
    {
        *out_children_ready = false;
    }
    if (!client || !block || !client->has_state)
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
        LanternRoot parent_root = block->block.parent_root;
        LanternState replay_state;
        lantern_state_init(&replay_state);
        bool have_replay_state = false;
        bool processed = false;
        bool deferred = false;
        uint64_t observed_finalized_slot = 0u;
        LanternRoot missing_roots[LANTERN_MAX_REQUEST_BLOCKS];
        size_t missing_count = 0;

        if (rebuild_state_for_root_locked(
                client,
                &parent_root,
                &replay_state,
                missing_roots,
                LANTERN_MAX_REQUEST_BLOCKS,
                &missing_count))
        {
            have_replay_state = true;
            LanternStore replay_store;
            lantern_store_init(&replay_store);
            bool replay_store_ready =
                lantern_store_prepare_validator_votes(&replay_store, replay_state.config.num_validators) == 0;
            if (replay_store_ready
                && lantern_state_transition(&replay_state, &replay_store, block) == 0)
            {
                processed = add_competing_fork_block_locked(
                    client,
                    block,
                    &block_root_local,
                    &replay_state,
                    &replay_state.latest_justified,
                    &replay_state.latest_finalized,
                    meta);
                if (processed)
                {
                    observed_finalized_slot = replay_state.latest_finalized.slot;
                }
            }
            else
            {
                persist_invalid_block_on_state_transition_failure(
                    client,
                    block,
                    &block_root_local,
                    raw_block_ssz,
                    raw_block_ssz_len,
                    meta);
                lantern_log_warn(
                    "state",
                    meta,
                    "off-head state transition failed for slot=%" PRIu64,
                    block->block.slot);
                log_import_rejected(block, &block_root_local, import_source, "state_transition_failed", meta);
            }
            lantern_store_reset(&replay_store);
        }
        else
        {
            lantern_log_warn(
                "state",
                meta,
                "failed to rebuild parent state for off-head slot=%" PRIu64,
                block->block.slot);
            const char *peer_text = meta && meta->peer ? meta->peer : NULL;
            deferred = lantern_client_enqueue_pending_block(
                client,
                block,
                &block_root_local,
                &parent_root,
                peer_text,
                backfill_depth,
                true);
            if (missing_count > 0)
            {
                uint32_t request_depths[LANTERN_MAX_REQUEST_BLOCKS];
                uint32_t request_depth = backfill_depth + 1u;
                if (request_depth > LANTERN_MAX_BACKFILL_DEPTH)
                {
                    request_depth = LANTERN_MAX_BACKFILL_DEPTH;
                }
                for (size_t i = 0; i < missing_count; ++i)
                {
                    request_depths[i] = request_depth;
                }
                (void)lantern_client_try_schedule_blocks_request_batch(
                    client,
                    peer_text,
                    missing_roots,
                    request_depths,
                    missing_count);
            }
        }

        bool adopted_state = false;
        LanternCheckpoint pre_adopt_finalized = client->state.latest_finalized;
        if (processed && client->has_fork_choice)
        {
            LanternRoot fork_head = {0};
            bool have_fork_head = lantern_fork_choice_current_head(
                &client->fork_choice,
                &fork_head)
                == 0;
            LanternRoot state_head = {0};
            bool have_state_head = have_fork_head && compute_state_head_root_locked(
                client,
                &state_head);

            if (have_fork_head && have_state_head
                && memcmp(fork_head.bytes, state_head.bytes, LANTERN_ROOT_SIZE) != 0)
            {
                if (have_replay_state
                    && memcmp(fork_head.bytes, block_root_local.bytes, LANTERN_ROOT_SIZE) == 0)
                {
                    adopt_state_locked(client, &replay_state);
                    have_replay_state = false;
                    adopted_state = true;
                }
                else
                {
                    LanternState head_state;
                    lantern_state_init(&head_state);
                    if (rebuild_state_for_root_locked(
                            client,
                            &fork_head,
                            &head_state,
                            NULL,
                            0,
                            NULL))
                    {
                        adopt_state_locked(client, &head_state);
                        adopted_state = true;
                    }
                    else
                    {
                        lantern_state_reset(&head_state);
                    }
                }
            }
        }

        if (adopted_state)
        {
            persist_finalized_state_if_advanced_locked(
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

        if (processed && have_replay_state)
        {
            get_head_info_locked(client, &head_root, &head_slot);
            persist_post_state_and_indices_locked(
                client,
                &replay_state,
                block,
                &block_root_local,
                &head_root,
                head_slot,
                meta);
        }

        if (have_replay_state)
        {
            lantern_state_reset(&replay_state);
        }

        lantern_client_unlock_state(client, state_locked);
        state_locked = false;
        if (!deferred)
        {
            lantern_client_pending_remove_by_root(client, &block_root_local);
        }
        if (processed)
        {
            persist_block_after_import(client, block, meta);
            update_network_view_after_import(client, block->block.slot, observed_finalized_slot);
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
        if (processed)
        {
            import_result = LANTERN_CLIENT_OK;
        }
        else if (deferred)
        {
            import_result = LANTERN_CLIENT_OK;
        }
        else
        {
            import_result = LANTERN_CLIENT_ERR_IGNORED;
        }
        if (out_result)
        {
            *out_result = import_result;
        }
        return false;
    }

    LanternCheckpoint pre_transition_finalized = client->state.latest_finalized;
    uint64_t imported_finalized_slot = 0u;
    if (!apply_state_transition_locked(client, block, meta))
    {
        log_import_rejected(block, &block_root_local, import_source, "state_transition_failed", meta);
        persist_invalid_block_on_state_transition_failure(
            client,
            block,
            &block_root_local,
            raw_block_ssz,
            raw_block_ssz_len,
            meta);
        goto cleanup;
    }

    lantern_client_cache_block_aggregated_proofs_locked(client, block);

    persist_finalized_state_if_advanced_locked(
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
    persist_post_state_and_indices_locked(
        client,
        &client->state,
        block,
        &block_root_local,
        &head_root,
        head_slot,
        meta);
    imported_finalized_slot = client->state.latest_finalized.slot;
    imported = true;

cleanup:
    lantern_client_unlock_state(client, state_locked);

    if (imported)
    {
        import_result = LANTERN_CLIENT_OK;
        persist_block_after_import(client, block, meta);
        update_network_view_after_import(client, block->block.slot, imported_finalized_slot);
        bool quiet_log = false;
        if (client->status_lock_initialized
            && pthread_mutex_lock(&client->status_lock) == 0)
        {
            client->sync_imported_blocks += 1u;
            quiet_log = client->sync_in_progress;
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
    bool allow_historical,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len)
{
    return lantern_client_import_block_internal(
        client,
        block,
        block_root,
        meta,
        backfill_depth,
        allow_historical,
        raw_block_ssz,
        raw_block_ssz_len,
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
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    bool *out_children_ready)
{
    return lantern_client_import_block_internal(
        client,
        block,
        block_root,
        meta,
        backfill_depth,
        allow_historical,
        raw_block_ssz,
        raw_block_ssz_len,
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
 * @param raw_block_ssz Optional raw SSZ bytes for the block
 * @param raw_block_ssz_len Length of `raw_block_ssz`
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
    bool allow_historical,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len)
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

    if (client->sync_in_progress)
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
        raw_block_ssz,
        raw_block_ssz_len,
        true,
        NULL,
        &import_result);
    return import_result;
}
