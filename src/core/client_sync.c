/**
 * @file client_sync.c
 * @brief Block and vote synchronization infrastructure
 *
 * @spec subspecs/forkchoice/store.py in tools/leanSpec
 *
 * Implements gossip handlers, fork choice initialization, block restoration
 * from storage, pending block management, and validator state refresh.
 *
 * Related files:
 * - client_sync_votes.c: Vote processing and validation
 * - client_sync_blocks.c: Block import and signature verification
 *
 * @note Thread safety: Functions that access shared state acquire appropriate
 *       locks as documented. See client_internal.h for lock ordering.
 */

#include "client_internal.h"

#include <inttypes.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/ssz.h"
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
    PEER_TEXT_BUFFER_LEN = 128,
};

void lantern_client_set_sync_state_logged(
    struct lantern_client *client,
    LanternSyncState new_state,
    const char *reason)
{
    if (!client)
    {
        return;
    }
    LanternSyncState prev_state = client->sync_state;
    if (prev_state == new_state)
    {
        return;
    }
    client->sync_state = new_state;
    lantern_log_info(
        "sync",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "%s → %s, %s",
        lantern_sync_state_name(prev_state),
        lantern_sync_state_name(new_state),
        reason && reason[0] ? reason : "state change");
}

static void backfill_session_clear_locked(struct lantern_backfill_session *session)
{
    if (!session)
    {
        return;
    }
    free(session->entries);
    memset(session, 0, sizeof(*session));
}

void lantern_client_backfill_reset(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }
    bool locked = lantern_client_lock_pending(client);
    if (locked)
    {
        backfill_session_clear_locked(&client->backfill);
        lantern_client_unlock_pending(client, locked);
    }
    else
    {
        backfill_session_clear_locked(&client->backfill);
    }
}

static bool backfill_entry_append_locked(
    struct lantern_backfill_session *session,
    const LanternRoot *root,
    const LanternRoot *parent_root,
    uint64_t slot,
    uint32_t depth,
    const char *peer_text)
{
    if (!session || !root || !parent_root)
    {
        return false;
    }
    for (size_t i = 0; i < session->length; ++i)
    {
        struct lantern_backfill_entry *entry = &session->entries[i];
        if (memcmp(entry->root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            if (depth > entry->depth)
            {
                entry->depth = depth;
            }
            if (peer_text && peer_text[0])
            {
                (void)lantern_string_copy(entry->peer_text, sizeof(entry->peer_text), peer_text);
            }
            return true;
        }
    }
    if (session->length == session->capacity)
    {
        size_t next_capacity = session->capacity == 0 ? 1024u : session->capacity * 2u;
        if (next_capacity <= session->capacity
            || next_capacity > SIZE_MAX / sizeof(*session->entries))
        {
            return false;
        }
        struct lantern_backfill_entry *grown =
            realloc(session->entries, next_capacity * sizeof(*grown));
        if (!grown)
        {
            return false;
        }
        session->entries = grown;
        session->capacity = next_capacity;
    }
    struct lantern_backfill_entry *entry = &session->entries[session->length++];
    memset(entry, 0, sizeof(*entry));
    entry->root = *root;
    entry->parent_root = *parent_root;
    entry->slot = slot;
    entry->depth = depth;
    if (peer_text && peer_text[0])
    {
        (void)lantern_string_copy(entry->peer_text, sizeof(entry->peer_text), peer_text);
    }
    return true;
}

static const struct lantern_backfill_entry *backfill_find_child_locked(
    const struct lantern_backfill_session *session,
    const LanternRoot *parent_root)
{
    const struct lantern_backfill_entry *best = NULL;
    if (!session || !parent_root)
    {
        return NULL;
    }
    for (size_t i = 0; i < session->length; ++i)
    {
        const struct lantern_backfill_entry *entry = &session->entries[i];
        if (entry->imported)
        {
            continue;
        }
        if (memcmp(entry->parent_root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) != 0)
        {
            continue;
        }
        if (!best || entry->slot < best->slot)
        {
            best = entry;
        }
    }
    return best;
}

static void backfill_mark_imported_locked(
    struct lantern_backfill_session *session,
    const LanternRoot *root)
{
    if (!session || !root)
    {
        return;
    }
    for (size_t i = 0; i < session->length; ++i)
    {
        if (memcmp(session->entries[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            session->entries[i].imported = true;
            return;
        }
    }
}

static bool backfill_parent_known(struct lantern_client *client, const LanternRoot *root)
{
    if (!client || !root)
    {
        return false;
    }
    bool locked = lantern_client_lock_state(client);
    if (!locked)
    {
        return false;
    }
    bool known = lantern_client_block_known_locked(client, root, NULL);
    lantern_client_unlock_state(client, locked);
    return known;
}

static bool backfill_import_connected_chain(struct lantern_client *client, const LanternRoot *connector_root)
{
    if (!client || !connector_root || lantern_root_is_zero(connector_root))
    {
        return false;
    }

    LanternRoot *roots = NULL;
    size_t root_count = 0;
    size_t root_capacity = 0;
    LanternRoot current = *connector_root;
    uint64_t connected_count = 0;

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return false;
    }
    if (!client->backfill.active)
    {
        lantern_client_unlock_pending(client, locked);
        return false;
    }
    for (;;)
    {
        const struct lantern_backfill_entry *child =
            backfill_find_child_locked(&client->backfill, &current);
        if (!child)
        {
            break;
        }
        if (root_count == root_capacity)
        {
            size_t next_capacity = root_capacity == 0 ? 64u : root_capacity * 2u;
            if (next_capacity <= root_capacity || next_capacity > SIZE_MAX / sizeof(*roots))
            {
                lantern_client_unlock_pending(client, locked);
                free(roots);
                return false;
            }
            LanternRoot *grown = realloc(roots, next_capacity * sizeof(*grown));
            if (!grown)
            {
                lantern_client_unlock_pending(client, locked);
                free(roots);
                return false;
            }
            roots = grown;
            root_capacity = next_capacity;
        }
        roots[root_count++] = child->root;
        current = child->root;
        connected_count += 1u;
        if (memcmp(current.bytes, client->backfill.head_root.bytes, LANTERN_ROOT_SIZE) == 0)
        {
            break;
        }
    }
    lantern_client_unlock_pending(client, locked);

    if (root_count == 0)
    {
        free(roots);
        return false;
    }

    uint64_t imported = 0;
    struct lantern_log_metadata meta = {.validator = client->node_id};
    for (size_t i = 0; i < root_count; ++i)
    {
        LanternSignedBlockList blocks;
        lantern_signed_block_list_init(&blocks);
        if (lantern_storage_collect_blocks(client->data_dir, &roots[i], 1u, &blocks) != 0
            || blocks.length == 0)
        {
            lantern_signed_block_list_reset(&blocks);
            break;
        }
        bool ok = lantern_client_import_block(
            client,
            &blocks.blocks[0],
            &roots[i],
            &meta,
            0u,
            true,
            NULL,
            0u);
        lantern_signed_block_list_reset(&blocks);
        if (!ok)
        {
            break;
        }
        imported += 1u;
        locked = lantern_client_lock_pending(client);
        if (locked)
        {
            backfill_mark_imported_locked(&client->backfill, &roots[i]);
            client->backfill.imported_count += 1u;
            lantern_client_unlock_pending(client, locked);
        }
    }

    locked = lantern_client_lock_pending(client);
    if (locked)
    {
        char head_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&client->backfill.head_root, head_hex, sizeof(head_hex));
        lantern_log_info(
            "sync",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "historical backfill connected head=%s connected=%" PRIu64 " imported=%" PRIu64
            " persisted=%" PRIu64 " dropped_gossip=%" PRIu64,
            head_hex[0] ? head_hex : "0x0",
            connected_count,
            imported,
            client->backfill.persisted_count,
            client->backfill.dropped_gossip_hints);
        if (imported == root_count
            && memcmp(roots[root_count - 1u].bytes, client->backfill.head_root.bytes, LANTERN_ROOT_SIZE) == 0)
        {
            backfill_session_clear_locked(&client->backfill);
        }
        lantern_client_unlock_pending(client, locked);
    }
    free(roots);
    return imported > 0;
}

static uint64_t backfill_anchor_slot(struct lantern_client *client, uint64_t fallback_slot)
{
    uint64_t anchor_slot = fallback_slot;
    if (client && client->has_fork_choice)
    {
        uint64_t fork_anchor_slot = 0;
        if (lantern_fork_choice_anchor_slot(&client->fork_choice, &fork_anchor_slot) == 0)
        {
            anchor_slot = fork_anchor_slot;
        }
    }
    return anchor_slot;
}

bool lantern_client_maybe_start_historical_backfill(
    struct lantern_client *client,
    const char *peer_text,
    const LanternRoot *head_root,
    uint64_t head_slot,
    uint64_t local_head_slot)
{
    if (!client || !head_root || lantern_root_is_zero(head_root))
    {
        return false;
    }
    uint64_t anchor_slot = backfill_anchor_slot(client, local_head_slot);
    if (head_slot <= anchor_slot)
    {
        return false;
    }
    uint64_t gap = head_slot - anchor_slot;
    if (gap <= LANTERN_PENDING_BLOCK_LIMIT)
    {
        return false;
    }

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return false;
    }
    if (client->backfill.active)
    {
        if (memcmp(client->backfill.head_root.bytes, head_root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            lantern_client_unlock_pending(client, locked);
            return true;
        }
        if (head_slot <= client->backfill.head_slot)
        {
            lantern_client_unlock_pending(client, locked);
            return true;
        }
        backfill_session_clear_locked(&client->backfill);
    }

    client->backfill.active = true;
    client->backfill.head_root = *head_root;
    client->backfill.frontier_root = *head_root;
    client->backfill.head_slot = head_slot;
    client->backfill.anchor_slot = anchor_slot;
    client->backfill.frontier_depth = 0;
    if (peer_text && peer_text[0])
    {
        (void)lantern_string_copy(
            client->backfill.peer_text,
            sizeof(client->backfill.peer_text),
            peer_text);
    }
    lantern_client_unlock_pending(client, locked);

    char head_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(head_root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "sync",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text && peer_text[0] ? peer_text : NULL},
        "historical backfill started head=%s head_slot=%" PRIu64 " anchor_slot=%" PRIu64
        " gap=%" PRIu64 " pending_limit=%u",
        head_hex[0] ? head_hex : "0x0",
        head_slot,
        anchor_slot,
        gap,
        (unsigned)LANTERN_PENDING_BLOCK_LIMIT);
    return true;
}

bool lantern_client_backfill_process_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    uint32_t depth)
{
    if (!client || !block || !root || lantern_root_is_zero(root))
    {
        return false;
    }

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return false;
    }
    bool matches_frontier =
        client->backfill.active
        && memcmp(client->backfill.frontier_root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0;
    uint64_t anchor_slot = client->backfill.anchor_slot;
    lantern_client_unlock_pending(client, locked);
    if (!matches_frontier)
    {
        return false;
    }

    if (lantern_storage_store_block_for_root(client->data_dir, root, block) != 0)
    {
        char root_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(root, root_hex, sizeof(root_hex));
        lantern_log_warn(
            "sync",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_text && peer_text[0] ? peer_text : NULL},
            "historical backfill failed to persist root=%s slot=%" PRIu64 " depth=%" PRIu32,
            root_hex[0] ? root_hex : "0x0",
            block->block.slot,
            depth);
        return false;
    }

    LanternRoot parent_root = block->block.parent_root;
    uint64_t persisted = 0;
    uint64_t dropped = 0;
    locked = lantern_client_lock_pending(client);
    if (locked)
    {
        if (client->backfill.active
            && memcmp(client->backfill.frontier_root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0
            && backfill_entry_append_locked(
                   &client->backfill,
                   root,
                   &parent_root,
                   block->block.slot,
                   depth,
                   peer_text))
        {
            client->backfill.frontier_root = parent_root;
            client->backfill.frontier_depth =
                depth < LANTERN_MAX_BACKFILL_DEPTH ? depth + 1u : LANTERN_MAX_BACKFILL_DEPTH;
            client->backfill.persisted_count += 1u;
            persisted = client->backfill.persisted_count;
            dropped = client->backfill.dropped_gossip_hints;
        }
        lantern_client_unlock_pending(client, locked);
    }

    char root_hex[ROOT_HEX_BUFFER_LEN];
    char parent_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(root, root_hex, sizeof(root_hex));
    format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
    lantern_log_info(
        "sync",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text && peer_text[0] ? peer_text : NULL},
        "historical backfill persisted root=%s parent=%s slot=%" PRIu64 " depth=%" PRIu32
        " anchor_slot=%" PRIu64 " persisted=%" PRIu64 " dropped_gossip=%" PRIu64,
        root_hex[0] ? root_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0",
        block->block.slot,
        depth,
        anchor_slot,
        persisted,
        dropped);

    if (backfill_parent_known(client, &parent_root))
    {
        (void)backfill_import_connected_chain(client, &parent_root);
        return true;
    }
    if (!lantern_root_is_zero(&parent_root))
    {
        uint32_t next_depth =
            depth < LANTERN_MAX_BACKFILL_DEPTH ? depth + 1u : LANTERN_MAX_BACKFILL_DEPTH;
        (void)lantern_client_try_schedule_blocks_request_batch(
            client,
            peer_text,
            &parent_root,
            &next_depth,
            1u);
    }
    return true;
}

bool lantern_client_backfill_should_drop_gossip(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    const char *context)
{
    if (!client || !block || !root || !context || strcmp(context, "gossip") != 0)
    {
        return false;
    }
    bool drop = false;
    uint64_t dropped = 0;
    uint64_t persisted = 0;
    uint64_t anchor_slot = 0;
    bool locked = lantern_client_lock_pending(client);
    if (locked)
    {
        if (client->backfill.active
            && block->block.slot > client->backfill.anchor_slot + LANTERN_PENDING_BLOCK_LIMIT)
        {
            client->backfill.dropped_gossip_hints += 1u;
            drop = true;
            dropped = client->backfill.dropped_gossip_hints;
            persisted = client->backfill.persisted_count;
            anchor_slot = client->backfill.anchor_slot;
        }
        lantern_client_unlock_pending(client, locked);
    }
    if (!drop)
    {
        return false;
    }
    char root_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(root, root_hex, sizeof(root_hex));
    lantern_log_info(
        "import",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_text && peer_text[0] ? peer_text : NULL},
        "slot %" PRIu64 ", %s, rejected, reason: backfill_window"
        ", anchor_slot %" PRIu64 ", persisted %" PRIu64 ", dropped_gossip %" PRIu64,
        block->block.slot,
        root_hex[0] ? root_hex : "0x0",
        anchor_slot,
        persisted,
        dropped);
    return true;
}

/* ============================================================================
 * Enabled Validator Count
 * ============================================================================ */

/**
 * Count enabled local validators.
 *
 * @spec subspecs/containers/validator.py - Validator registry
 *
 * Counts the number of locally-managed validators that are currently
 * enabled for voting and block proposal.
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
 * Gossip Handlers
 * ============================================================================ */

/**
 * @brief Convert a peer ID to text for logging.
 *
 * @param from     Peer ID (may be NULL)
 * @param out      Output buffer
 * @param out_len  Output buffer length
 * @return Peer ID text, or NULL if unavailable
 *
 * @note Thread safety: This function is thread-safe
 */
static const char *peer_id_to_text(const struct lantern_peer_id *from, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return NULL;
    }

    out[0] = '\0';
    if (!from)
    {
        return NULL;
    }

    if (lantern_peer_id_to_text(from, out, out_len) != 0)
    {
        out[0] = '\0';
        return NULL;
    }

    return out[0] ? out : NULL;
}

/**
 * Identify a pristine genesis-style state snapshot.
 *
 * This is used to preserve deterministic genesis anchor hashing when loading
 * older snapshots that eagerly persisted latest_block_header.state_root.
 */
static bool state_has_genesis_shape(const LanternState *state)
{
    if (!state)
    {
        return false;
    }
    if (state->slot != 0
        || state->latest_block_header.slot != 0
        || state->latest_block_header.proposer_index != 0
        || state->latest_justified.slot != 0
        || state->latest_finalized.slot != 0)
    {
        return false;
    }
    if (state->historical_block_hashes.length != 0
        || state->justified_slots.bit_length != 0
        || state->justification_roots.length != 0
        || state->justification_validators.bit_length != 0)
    {
        return false;
    }
    if (!lantern_root_is_zero(&state->latest_block_header.parent_root)
        || !lantern_root_is_zero(&state->latest_justified.root)
        || !lantern_root_is_zero(&state->latest_finalized.root))
    {
        return false;
    }
    return true;
}

/**
 * Handle a block received via gossip.
 *
 * @spec subspecs/networking/gossip - Block gossip topic
 *
 * Entry point for blocks received via the gossipsub protocol.
 * Converts the peer ID to string format and delegates to the
 * block recording function.
 *
 * @param block    Received block
 * @param from     Peer ID of sender
 * @param context  Client instance
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if block or context is NULL
 *
 * @note Thread safety: This function is thread-safe
 */
int gossip_block_handler(
    const LanternSignedBlock *block,
    const struct lantern_peer_id *from,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    void *context)
{
    if (!block || !context)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    char peer_text[PEER_TEXT_BUFFER_LEN];
    const char *peer_id_text = peer_id_to_text(from, peer_text, sizeof(peer_text));
    bool sync_idle = false;
    if (client->status_lock_initialized && pthread_mutex_lock(&client->status_lock) == 0)
    {
        sync_idle = client->sync_state == LANTERN_SYNC_STATE_IDLE;
        pthread_mutex_unlock(&client->status_lock);
    }
    else
    {
        sync_idle = client->sync_state == LANTERN_SYNC_STATE_IDLE;
    }
    if (sync_idle)
    {
        LanternRoot block_root = {0};
        char root_hex[ROOT_HEX_BUFFER_LEN];
        char parent_hex[ROOT_HEX_BUFFER_LEN];
        root_hex[0] = '\0';
        if (lantern_hash_tree_root_block(&block->block, &block_root) == SSZ_SUCCESS)
        {
            format_root_hex(&block_root, root_hex, sizeof(root_hex));
        }
        format_root_hex(&block->block.parent_root, parent_hex, sizeof(parent_hex));
        lantern_log_info(
            "import",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id_text},
            "slot %" PRIu64 ", %s, rejected, reason: sync_state=idle, via gossip, parent %s",
            block->block.slot,
            root_hex[0] ? root_hex : "0x0",
            parent_hex[0] ? parent_hex : "0x0");
        return LANTERN_CLIENT_ERR_IGNORED;
    }

    if (raw_block_ssz && raw_block_ssz_len > 0)
    {
        lean_metrics_record_gossip_block_size(raw_block_ssz_len);
    }

    return lantern_client_record_block(
        client,
        block,
        NULL,
        peer_id_text,
        "gossip",
        0,
        false,
        raw_block_ssz,
        raw_block_ssz_len);
}


/**
 * Handle a vote received via gossip.
 *
 * @spec subspecs/networking/gossip - Attestation gossip topic
 *
 * Entry point for votes (attestations) received via the gossipsub protocol.
 * Converts the peer ID to string format, notes the delivery for metrics,
 * and delegates to the vote recording function.
 *
 * @param vote     Received vote
 * @param from     Peer ID of sender
 * @param context  Client instance
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if vote or context is NULL
 *
 * @note Thread safety: This function is thread-safe
 */
int gossip_vote_handler(
    const LanternSignedVote *vote,
    const struct lantern_peer_id *from,
    const uint8_t *raw_vote_payload,
    size_t raw_vote_payload_len,
    void *context)
{
    if (!vote || !context)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    bool sync_idle = false;
    if (client->status_lock_initialized && pthread_mutex_lock(&client->status_lock) == 0)
    {
        sync_idle = client->sync_state == LANTERN_SYNC_STATE_IDLE;
        pthread_mutex_unlock(&client->status_lock);
    }
    else
    {
        sync_idle = client->sync_state == LANTERN_SYNC_STATE_IDLE;
    }
    if (sync_idle)
    {
        return LANTERN_CLIENT_ERR_IGNORED;
    }

    if (raw_vote_payload && raw_vote_payload_len > 0)
    {
        lean_metrics_record_gossip_attestation_size(raw_vote_payload_len);
    }

    char peer_text[PEER_TEXT_BUFFER_LEN];
    const char *peer_id_text = peer_id_to_text(from, peer_text, sizeof(peer_text));

    lantern_client_note_vote_delivery(client, peer_id_text, vote);
    lantern_client_record_vote(client, vote, peer_id_text);
    return LANTERN_CLIENT_OK;
}

static bool verify_and_cache_aggregated_attestation_locked(
    struct lantern_client *client,
    const LanternSignedAggregatedAttestation *attestation,
    const struct lantern_log_metadata *meta,
    LanternRoot *out_missing_root) {
    if (!client || !attestation || !meta || !client->has_state) {
        return false;
    }
    if (out_missing_root) {
        memset(out_missing_root, 0, sizeof(*out_missing_root));
    }
    if (attestation->proof.participants.bit_length == 0
        || !attestation->proof.participants.bytes
        || attestation->proof.proof_data.length == 0
        || !attestation->proof.proof_data.data) {
        return false;
    }
    LanternVote vote = {0};
    vote.slot = attestation->data.slot;
    vote.head = attestation->data.head;
    vote.target = attestation->data.target;
    vote.source = attestation->data.source;
    struct lantern_vote_rejection_info rejection;
    memset(&rejection, 0, sizeof(rejection));
    if (!lantern_client_validate_vote_constraints(
            client,
            &vote,
            "gossip",
            meta,
            "aggregated attestation",
            &rejection)) {
        if (out_missing_root && rejection.has_unknown_root) {
            *out_missing_root = rejection.unknown_root;
        }
        return false;
    }

    LanternState target_state;
    lantern_state_init(&target_state);
    LanternRoot missing_root = {0};
    const LanternState *sig_state = lantern_client_state_for_root_local_locked(
        client,
        &attestation->data.target.root,
        &target_state,
        NULL);
    if (!sig_state
        && !lantern_client_find_missing_state_root_locked(
               client,
               &attestation->data.target.root,
               &missing_root)) {
        sig_state = lantern_client_state_for_root_locked(
            client,
            &attestation->data.target.root,
            &target_state,
            NULL);
    }
    if (!sig_state) {
        if (out_missing_root) {
            *out_missing_root =
                lantern_root_is_zero(&missing_root) ? attestation->data.target.root : missing_root;
        }
        lantern_state_reset(&target_state);
        return false;
    }

    size_t validator_count = lantern_state_validator_count(sig_state);
    size_t bit_length = attestation->proof.participants.bit_length;
    if (bit_length > validator_count) {
        lantern_state_reset(&target_state);
        return false;
    }
    size_t participant_count = 0;
    for (size_t i = 0; i < bit_length; ++i) {
        if (lantern_bitlist_get(&attestation->proof.participants, i)) {
            participant_count += 1u;
        }
    }
    if (participant_count == 0) {
        lantern_state_reset(&target_state);
        return false;
    }

    const uint8_t **pubkeys = calloc(participant_count, sizeof(*pubkeys));
    if (!pubkeys) {
        lantern_state_reset(&target_state);
        return false;
    }
    size_t idx = 0;
    for (size_t i = 0; i < bit_length; ++i) {
        if (!lantern_bitlist_get(&attestation->proof.participants, i)) {
            continue;
        }
        const uint8_t *pubkey = lantern_state_validator_attestation_pubkey(sig_state, i);
        if (!pubkey || lantern_validator_pubkey_is_zero(pubkey)) {
            free(pubkeys);
            lantern_state_reset(&target_state);
            return false;
        }
        pubkeys[idx++] = pubkey;
    }

    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&attestation->data, &data_root) != SSZ_SUCCESS) {
        free(pubkeys);
        lantern_state_reset(&target_state);
        return false;
    }

    bool verified = lantern_signature_verify_aggregated(
        pubkeys,
        participant_count,
        &data_root,
        &attestation->proof.proof_data,
        attestation->data.slot);
    free(pubkeys);
    lantern_state_reset(&target_state);
    if (!verified) {
        return false;
    }
    if (lantern_store_add_new_aggregated_payload(
            &client->store,
            &data_root,
            &attestation->data,
            &attestation->proof,
            attestation->data.target.slot)
        != 0) {
        lantern_log_debug(
            "gossip",
            meta,
            "failed to cache aggregated attestation proof");
    }
    return true;
}

int gossip_aggregated_attestation_handler(
    const LanternSignedAggregatedAttestation *attestation,
    const struct lantern_peer_id *from,
    const uint8_t *raw_attestation_payload,
    size_t raw_attestation_payload_len,
    void *context)
{
    if (!attestation || !context) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;
    bool sync_idle = false;
    if (client->status_lock_initialized && pthread_mutex_lock(&client->status_lock) == 0)
    {
        sync_idle = client->sync_state == LANTERN_SYNC_STATE_IDLE;
        pthread_mutex_unlock(&client->status_lock);
    }
    else
    {
        sync_idle = client->sync_state == LANTERN_SYNC_STATE_IDLE;
    }
    if (sync_idle)
    {
        return LANTERN_CLIENT_ERR_IGNORED;
    }

    if (raw_attestation_payload && raw_attestation_payload_len > 0) {
        lean_metrics_record_gossip_aggregation_size(raw_attestation_payload_len);
    }

    char peer_text[PEER_TEXT_BUFFER_LEN];
    const char *peer_id_text = peer_id_to_text(from, peer_text, sizeof(peer_text));
    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_id_text,
        .has_slot = true,
        .slot = attestation->data.slot,
    };

    bool locked = lantern_client_lock_state(client);
    if (!locked) {
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    LanternRoot missing_root = {0};
    bool verified = verify_and_cache_aggregated_attestation_locked(
        client,
        attestation,
        &meta,
        &missing_root);
    lantern_client_unlock_state(client, locked);
    if (!verified) {
        char missing_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&missing_root, missing_hex, sizeof(missing_hex));
        lantern_log_debug(
            "gossip",
            &meta,
            "ignoring aggregated attestation slot=%" PRIu64 " missing_root=%s",
            attestation->data.slot,
            missing_hex[0] ? missing_hex : "0x0");
        return LANTERN_CLIENT_ERR_IGNORED;
    }
    lantern_log_debug(
        "gossip",
        &meta,
        "accepted aggregated attestation slot=%" PRIu64,
        attestation->data.slot);
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Anchor Block Persistence
 * ============================================================================ */

/**
 * Persist anchor block to storage.
 *
 * @spec subspecs/forkchoice/store.py - Store anchor block
 *
 * Persists the genesis anchor block to storage. This block serves
 * as the root of the fork choice tree and the starting point for
 * block import.
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
    LanternBlock *block = &stored_anchor.block;
    block->slot = anchor_block->slot;
    block->proposer_index = anchor_block->proposer_index;
    block->parent_root = anchor_block->parent_root;
    block->state_root = anchor_block->state_root;
    if (lantern_aggregated_attestations_copy(
            &block->body.attestations,
            &anchor_block->body.attestations)
        != 0)
    {
        lantern_signed_block_with_attestation_reset(&stored_anchor);
        lantern_log_warn(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to copy anchor block body for persistence");
        return;
    }

    LanternRoot computed_root;
    const LanternRoot *root_to_log = anchor_root;
    if (!root_to_log)
    {
        if (lantern_hash_tree_root_block(block, &computed_root) == SSZ_SUCCESS)
        {
            root_to_log = &computed_root;
        }
    }
    char root_hex[ROOT_HEX_BUFFER_LEN];
    root_hex[0] = '\0';
    if (root_to_log)
    {
        format_root_hex(root_to_log, root_hex, sizeof(root_hex));
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    if (root_to_log
        ? lantern_storage_store_block_for_root(client->data_dir, root_to_log, &stored_anchor) != 0
        : lantern_storage_store_block(client->data_dir, &stored_anchor) != 0)
    {
        lantern_log_warn(
            "storage",
            &meta,
            "failed to persist anchor block root=%s",
            root_hex[0] ? root_hex : "0x0");
    }
    else
    {
        lantern_log_debug(
            "storage",
            &meta,
            "persisted anchor block root=%s",
            root_hex[0] ? root_hex : "0x0");
    }
    lantern_signed_block_with_attestation_reset(&stored_anchor);
}


/* ============================================================================
 * Fork Choice Initialization
 * ============================================================================ */

static bool load_persisted_checkpoint_anchor_block(
    struct lantern_client *client,
    const struct lantern_log_metadata *meta,
    const LanternRoot *state_root,
    LanternBlock *out_anchor_block,
    LanternRoot *out_anchor_root)
{
    if (!client || !meta || !state_root || !out_anchor_block || !out_anchor_root
        || !client->data_dir)
    {
        return false;
    }

    LanternBlockHeader expected_anchor_header = client->state.latest_block_header;
    expected_anchor_header.state_root = *state_root;
    LanternRoot expected_anchor_root;
    if (lantern_hash_tree_root_block_header(&expected_anchor_header, &expected_anchor_root)
        != SSZ_SUCCESS)
    {
        lantern_log_warn(
            "forkchoice",
            meta,
            "failed to hash checkpoint state latest block header");
        return false;
    }

    uint8_t *block_bytes = NULL;
    size_t block_len = 0;
    int load_rc = lantern_storage_load_block_bytes_for_root(
        client->data_dir,
        &expected_anchor_root,
        &block_bytes,
        &block_len);
    if (load_rc != 0)
    {
        if (load_rc < 0)
        {
            lantern_log_warn(
                "forkchoice",
                meta,
                "failed to load persisted checkpoint anchor block");
        }
        return false;
    }

    LanternSignedBlock signed_anchor;
    lantern_signed_block_with_attestation_init(&signed_anchor);
    bool loaded = false;
    if (lantern_ssz_decode_signed_block(&signed_anchor, block_bytes, block_len) != SSZ_SUCCESS)
    {
        lantern_log_warn(
            "forkchoice",
            meta,
            "failed to decode persisted checkpoint anchor block");
        goto cleanup;
    }

    LanternRoot computed_root;
    if (lantern_hash_tree_root_block(&signed_anchor.block, &computed_root) != SSZ_SUCCESS)
    {
        lantern_log_warn(
            "forkchoice",
            meta,
            "failed to hash persisted checkpoint anchor block");
        goto cleanup;
    }

    if (memcmp(
            computed_root.bytes,
            expected_anchor_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0)
    {
        lantern_log_warn(
            "forkchoice",
            meta,
            "persisted checkpoint anchor block root does not match checkpoint header");
        goto cleanup;
    }

    out_anchor_block->slot = signed_anchor.block.slot;
    out_anchor_block->proposer_index = signed_anchor.block.proposer_index;
    out_anchor_block->parent_root = signed_anchor.block.parent_root;
    out_anchor_block->state_root = signed_anchor.block.state_root;
    lantern_block_body_init(&out_anchor_block->body);
    if (lantern_aggregated_attestations_copy(
            &out_anchor_block->body.attestations,
            &signed_anchor.block.body.attestations)
        != 0)
    {
        lantern_block_body_reset(&out_anchor_block->body);
        memset(out_anchor_block, 0, sizeof(*out_anchor_block));
        lantern_log_warn(
            "forkchoice",
            meta,
            "failed to copy persisted checkpoint anchor block body");
        goto cleanup;
    }
    *out_anchor_root = expected_anchor_root;
    loaded = true;

cleanup:
    free(block_bytes);
    lantern_signed_block_with_attestation_reset(&signed_anchor);
    return loaded;
}

/**
 * @brief Compute anchor roots for fork choice initialization.
 *
 * @param client             Client instance
 * @param meta               Logging metadata
 * @param out_state_root     Output computed state root
 * @param out_anchor_block   Output anchor block
 * @param out_anchor_root    Output computed anchor root
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 * @return LANTERN_CLIENT_ERR_RUNTIME on hashing failure
 *
 * @note Thread safety: Caller must ensure exclusive access during initialization
 */
static int compute_fork_choice_anchor_roots(
    struct lantern_client *client,
    const struct lantern_log_metadata *meta,
    LanternRoot *out_state_root,
    LanternBlock *out_anchor_block,
    LanternRoot *out_anchor_root)
{
    if (!client || !meta || !out_state_root || !out_anchor_block || !out_anchor_root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    const LanternState *state_for_hash = &client->state;
    LanternState normalized_state = client->state;
    bool normalized_genesis_snapshot = false;
    if (state_has_genesis_shape(&client->state)
        && !lantern_root_is_zero(&client->state.latest_block_header.state_root))
    {
        memset(
            normalized_state.latest_block_header.state_root.bytes,
            0,
            sizeof(normalized_state.latest_block_header.state_root.bytes));
        state_for_hash = &normalized_state;
        normalized_genesis_snapshot = true;
    }

    if (lantern_hash_tree_root_state(state_for_hash, out_state_root) != SSZ_SUCCESS)
    {
        lantern_log_error("forkchoice", meta, "failed to hash anchor state");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    if (normalized_genesis_snapshot)
    {
        lantern_log_warn(
            "forkchoice",
            meta,
            "normalizing persisted genesis header state_root to compute canonical anchor");
    }

    memset(out_anchor_block, 0, sizeof(*out_anchor_block));
    if (load_persisted_checkpoint_anchor_block(
            client,
            meta,
            out_state_root,
            out_anchor_block,
            out_anchor_root))
    {
        return LANTERN_CLIENT_OK;
    }

    LanternBlockBody empty_body;
    lantern_block_body_init(&empty_body);
    LanternRoot empty_body_root;
    bool empty_body_root_ok =
        lantern_hash_tree_root_block_body(&empty_body, &empty_body_root) == SSZ_SUCCESS;
    lantern_block_body_reset(&empty_body);
    if (!empty_body_root_ok
        || memcmp(
               empty_body_root.bytes,
               client->state.latest_block_header.body_root.bytes,
               LANTERN_ROOT_SIZE)
               != 0)
    {
        lantern_log_error(
            "forkchoice",
            meta,
            "missing persisted checkpoint anchor block for non-empty checkpoint header body");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    out_anchor_block->slot = client->state.latest_block_header.slot;
    out_anchor_block->proposer_index = client->state.latest_block_header.proposer_index;
    out_anchor_block->parent_root = client->state.latest_block_header.parent_root;
    out_anchor_block->state_root = *out_state_root;
    lantern_block_body_init(&out_anchor_block->body);

    if (lantern_hash_tree_root_block(out_anchor_block, out_anchor_root) != SSZ_SUCCESS)
    {
        lantern_block_body_reset(&out_anchor_block->body);
        lantern_log_error("forkchoice", meta, "failed to hash anchor block");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Log anchor roots for debugging mismatches.
 *
 * @param meta         Logging metadata
 * @param anchor_root  Anchor block root
 * @param state_root   Anchor state root
 * @param body_root    Anchor body root
 * @param slot         Anchor slot
 *
 * @note Thread safety: This function is thread-safe
 */
static void log_anchor_roots(
    const struct lantern_log_metadata *meta,
    const LanternRoot *anchor_root,
    const LanternRoot *state_root,
    const LanternRoot *body_root,
    uint64_t slot)
{
    char anchor_root_hex[ROOT_HEX_BUFFER_LEN];
    char state_root_hex[ROOT_HEX_BUFFER_LEN];
    char body_root_hex[ROOT_HEX_BUFFER_LEN];

    format_root_hex(anchor_root, anchor_root_hex, sizeof(anchor_root_hex));
    format_root_hex(state_root, state_root_hex, sizeof(state_root_hex));
    format_root_hex(body_root, body_root_hex, sizeof(body_root_hex));

    lantern_log_info(
        "forkchoice",
        meta,
        "anchor_root=%s state_root=%s body_root=%s slot=%" PRIu64,
        anchor_root_hex[0] ? anchor_root_hex : "0x0",
        state_root_hex[0] ? state_root_hex : "0x0",
        body_root_hex[0] ? body_root_hex : "0x0",
        slot);
}

/**
 * Initialize fork choice from genesis state.
 *
 * @spec subspecs/forkchoice/store.py - Store.get_forkchoice_store()
 *
 * Initializes the fork choice store from the genesis state:
 * 1. Configures fork choice with consensus parameters
 * 2. Loads the checkpoint anchor block, or reconstructs a genesis anchor
 * 3. Sets fork choice anchor with anchor checkpoints
 * 4. Persists anchor block to storage
 *
 * Current leanSpec checkpoint sync seeds Store.from_anchor with the fetched
 * finalized block paired with the fetched finalized state. Genesis bootstrap
 * still reconstructs an empty-body anchor from the embedded header.
 *
 * @param client  Client instance
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if client is NULL or missing state
 * @return LANTERN_CLIENT_ERR_RUNTIME on fork choice initialization failure
 *
 * @note Thread safety: Should be called during initialization
 */
int initialize_fork_choice(struct lantern_client *client)
{
    if (!client || !client->has_state)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    const struct lantern_log_metadata meta = {.validator = client->node_id};

    lantern_store_attach_fork_choice(&client->store, &client->fork_choice);
    lantern_fork_choice_reset(&client->fork_choice);
    if (lantern_fork_choice_configure(&client->fork_choice, &client->state.config) != 0)
    {
        lantern_log_error(
            "forkchoice",
            &meta,
            "failed to configure fork choice");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    LanternRoot anchor_state_root;
    LanternBlock anchor;
    memset(&anchor, 0, sizeof(anchor));
    LanternRoot anchor_root;
    int root_rc = compute_fork_choice_anchor_roots(
        client,
        &meta,
        &anchor_state_root,
        &anchor,
        &anchor_root);
    if (root_rc != LANTERN_CLIENT_OK)
    {
        return root_rc;
    }

    LanternRoot anchor_body_root = {0};
    if (lantern_hash_tree_root_block_body(&anchor.body, &anchor_body_root) != SSZ_SUCCESS)
    {
        lantern_block_body_reset(&anchor.body);
        lantern_log_error(
            "forkchoice",
            &meta,
            "failed to hash anchor block body");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    char anchor_root_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(
        &anchor_root,
        anchor_root_hex,
        sizeof(anchor_root_hex));

    log_anchor_roots(
        &meta,
        &anchor_root,
        &anchor_state_root,
        &anchor_body_root,
        anchor.slot);

    LanternCheckpoint anchor_checkpoint = {
        .root = anchor_root,
        .slot = anchor.slot,
    };

    /*
     * leanSpec Store.from_anchor treats the trusted anchor block as both
     * justified and finalized, regardless of the state's embedded checkpoints.
     */
    if (lantern_fork_choice_set_anchor_with_state(
            &client->fork_choice,
            &anchor,
            &anchor_checkpoint,
            &anchor_checkpoint,
            &anchor_root,
            &client->state)
        != 0)
    {
        lantern_block_body_reset(&anchor.body);
        lantern_log_error(
            "forkchoice",
            &meta,
            "failed to set fork choice anchor");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    persist_anchor_block(client, &anchor, &anchor_root);
    if (client->data_dir)
    {
        LanternState anchor_state = client->state;
        if (lantern_storage_store_state_for_root(
                client->data_dir,
                &anchor_root,
                &anchor_state)
            != 0)
        {
            lantern_log_warn(
                "storage",
                &meta,
                "failed to persist anchor state alias");
        }
    }
    lantern_block_body_reset(&anchor.body);
    client->has_fork_choice = true;
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Block Restoration from Storage
 * ============================================================================ */

/**
 * @brief Visitor callback for storage block iteration.
 *
 * @param block    Persisted block
 * @param root     Block root
 * @param context  Persisted block list
 * @return 0 on success, non-zero to abort iteration
 *
 * @note Thread safety: Should be called during initialization
 */
static int collect_block_visitor(
    const LanternSignedBlock *block,
    const LanternRoot *root,
    void *context)
{
    if (!block || !root || !context)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_persisted_block_list *list = context;
    return persisted_block_list_append(list, block, root);
}


/**
 * @brief Compare persisted blocks by slot for sorting.
 *
 * @param lhs_ptr  Left block entry
 * @param rhs_ptr  Right block entry
 * @return <0 if lhs < rhs, >0 if lhs > rhs, 0 if equal
 *
 * @note Thread safety: This function is thread-safe
 */
static int compare_blocks_by_slot(const void *lhs_ptr, const void *rhs_ptr)
{
    const struct lantern_persisted_block *lhs = lhs_ptr;
    const struct lantern_persisted_block *rhs = rhs_ptr;
    if (lhs->block.block.slot < rhs->block.block.slot)
    {
        return -1;
    }
    if (lhs->block.block.slot > rhs->block.block.slot)
    {
        return 1;
    }
    return memcmp(lhs->root.bytes, rhs->root.bytes, LANTERN_ROOT_SIZE);
}

static bool load_restored_block_state(
    const struct lantern_client *client,
    const LanternRoot *root,
    LanternState *out_state)
{
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

    lantern_state_init(out_state);
    bool loaded = lantern_ssz_decode_state(out_state, state_bytes, state_len) == SSZ_SUCCESS;
    free(state_bytes);
    if (!loaded)
    {
        lantern_state_reset(out_state);
    }
    return loaded;
}

static bool restore_keep_roots_contains(
    const LanternRoot *roots,
    size_t root_count,
    const LanternRoot *root)
{
    if (!roots || !root)
    {
        return false;
    }
    for (size_t i = 0; i < root_count; ++i)
    {
        if (memcmp(roots[i].bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return true;
        }
    }
    return false;
}

static void restore_keep_roots_append(
    LanternRoot *roots,
    size_t capacity,
    size_t *root_count,
    const LanternRoot *root)
{
    if (!roots || !root_count || !root || lantern_root_is_zero(root))
    {
        return;
    }
    if (*root_count >= capacity
        || restore_keep_roots_contains(roots, *root_count, root))
    {
        return;
    }
    roots[(*root_count)++] = *root;
}

/**
 * Restore persisted blocks from storage into fork choice.
 *
 * @spec subspecs/storage/sqlite.py - Database.prune_before_slot()
 *
 * Prunes persisted blocks/states strictly before the finalized slot, then
 * restores only the remaining finalized-or-newer block window into fork
 * choice. This keeps restart behavior aligned with LeanSpec storage pruning.
 *
 * @param client  Client instance
 * @return LANTERN_CLIENT_OK on success (including when nothing to restore)
 * @return LANTERN_CLIENT_ERR_STORAGE if block enumeration fails
 *
 * @note Thread safety: Should be called during initialization
 */
int restore_persisted_blocks(struct lantern_client *client)
{
    if (!client || !client->has_state || !client->data_dir || !client->has_fork_choice)
    {
        return LANTERN_CLIENT_OK;
    }

    LanternRoot restore_keep_roots[2];
    size_t restore_keep_root_count = 0;
    restore_keep_roots_append(
        restore_keep_roots,
        2u,
        &restore_keep_root_count,
        &client->state.latest_finalized.root);
    restore_keep_roots_append(
        restore_keep_roots,
        2u,
        &restore_keep_root_count,
        lantern_fork_choice_anchor_root(&client->fork_choice));

    const uint64_t restore_min_slot = client->state.latest_finalized.slot;
    if (restore_min_slot > 0)
    {
        int pruned = lantern_storage_prune_before_slot(
            client->data_dir,
            restore_min_slot,
            restore_keep_roots,
            restore_keep_root_count);
        if (pruned < 0)
        {
            lantern_log_warn(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to prune persisted pre-finalized data before restore finalized_slot=%" PRIu64,
                restore_min_slot);
        }
        else if (pruned > 0)
        {
            lantern_log_info(
                "storage",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "pruned persisted pre-finalized data before restore finalized_slot=%" PRIu64
                " entries=%d",
                restore_min_slot,
                pruned);
        }
    }

    struct lantern_persisted_block_list list;
    persisted_block_list_init(&list);
    int iterate_rc = lantern_storage_iterate_blocks(
        client->data_dir,
        collect_block_visitor,
        &list);
    if (iterate_rc < 0)
    {
        lantern_log_error(
            "storage",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to enumerate persisted blocks");
        persisted_block_list_reset(&list);
        return LANTERN_CLIENT_ERR_STORAGE;
    }
    if (list.length == 0)
    {
        persisted_block_list_reset(&list);
        return LANTERN_CLIENT_OK;
    }
    qsort(list.items, list.length, sizeof(list.items[0]), compare_blocks_by_slot);

    const LanternRoot *store_anchor_root =
        lantern_fork_choice_anchor_root(&client->fork_choice);
    uint64_t store_anchor_slot = 0;
    bool have_store_anchor_slot =
        lantern_fork_choice_anchor_slot(&client->fork_choice, &store_anchor_slot) == 0;
    LanternRoot store_head = {0};
    bool have_store_head =
        lantern_fork_choice_current_head(&client->fork_choice, &store_head) == 0;
    uint64_t store_head_slot = 0;
    if (have_store_head
        && lantern_fork_choice_block_info(
               &client->fork_choice,
               &store_head,
               &store_head_slot,
               NULL,
               NULL)
            != 0)
    {
        store_head_slot = 0;
    }
    const LanternCheckpoint *store_latest_justified =
        lantern_fork_choice_latest_justified(&client->fork_choice);
    const LanternCheckpoint *store_latest_finalized =
        lantern_fork_choice_latest_finalized(&client->fork_choice);
    char store_anchor_root_hex[ROOT_HEX_BUFFER_LEN];
    char store_head_hex[ROOT_HEX_BUFFER_LEN];
    char store_justified_root_hex[ROOT_HEX_BUFFER_LEN];
    char store_finalized_root_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(
        store_anchor_root,
        store_anchor_root_hex,
        sizeof(store_anchor_root_hex));
    format_root_hex(&store_head, store_head_hex, sizeof(store_head_hex));
    format_root_hex(
        store_latest_justified ? &store_latest_justified->root : NULL,
        store_justified_root_hex,
        sizeof(store_justified_root_hex));
    format_root_hex(
        store_latest_finalized ? &store_latest_finalized->root : NULL,
        store_finalized_root_hex,
        sizeof(store_finalized_root_hex));
    lantern_log_info(
        "forkchoice",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "restoring persisted blocks count=%zu anchor_slot=%" PRIu64 " anchor_root=%s"
        " head_slot=%" PRIu64 " head_root=%s justified_slot=%" PRIu64
        " justified_root=%s finalized_slot=%" PRIu64 " finalized_root=%s",
        list.length,
        have_store_anchor_slot ? store_anchor_slot : 0u,
        store_anchor_root_hex[0] ? store_anchor_root_hex : "0x0",
        have_store_head ? store_head_slot : 0u,
        have_store_head ? (store_head_hex[0] ? store_head_hex : "0x0") : "<none>",
        store_latest_justified ? store_latest_justified->slot : 0u,
        store_justified_root_hex[0] ? store_justified_root_hex : "0x0",
        store_latest_finalized ? store_latest_finalized->slot : 0u,
        store_finalized_root_hex[0] ? store_finalized_root_hex : "0x0");

    for (size_t i = 0; i < list.length; ++i)
    {
        const struct lantern_persisted_block *entry = &list.items[i];
        const LanternBlock *block = &entry->block.block;
        if (restore_min_slot > 0
            && block->slot < restore_min_slot
            && !restore_keep_roots_contains(
                   restore_keep_roots,
                   restore_keep_root_count,
                   &entry->root))
        {
            continue;
        }
        LanternState cached_post_state;
        bool have_cached_post_state = load_restored_block_state(client, &entry->root, &cached_post_state);
        const LanternCheckpoint *post_justified = &client->state.latest_justified;
        const LanternCheckpoint *post_finalized = &client->state.latest_finalized;
        if (have_cached_post_state)
        {
            post_justified = &cached_post_state.latest_justified;
            post_finalized = &cached_post_state.latest_finalized;
        }
        const LanternState *post_state_for_restore =
            have_cached_post_state ? &cached_post_state : NULL;
        bool using_canonical_anchor_state = false;
        if (store_anchor_root
            && memcmp(
                   entry->root.bytes,
                   store_anchor_root->bytes,
                   LANTERN_ROOT_SIZE)
                == 0)
        {
            post_state_for_restore = &client->state;
            using_canonical_anchor_state = true;
        }

        char block_root_hex[ROOT_HEX_BUFFER_LEN];
        char parent_root_hex[ROOT_HEX_BUFFER_LEN];
        char post_justified_root_hex[ROOT_HEX_BUFFER_LEN];
        char post_finalized_root_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&entry->root, block_root_hex, sizeof(block_root_hex));
        format_root_hex(&block->parent_root, parent_root_hex, sizeof(parent_root_hex));
        format_root_hex(
            &post_justified->root,
            post_justified_root_hex,
            sizeof(post_justified_root_hex));
        format_root_hex(
            &post_finalized->root,
            post_finalized_root_hex,
            sizeof(post_finalized_root_hex));

        bool justified_known =
            !lantern_root_is_zero(&post_justified->root)
            && lantern_fork_choice_block_info(
                   &client->fork_choice,
                   &post_justified->root,
                   NULL,
                   NULL,
                   NULL)
                == 0;
        bool finalized_known =
            !lantern_root_is_zero(&post_finalized->root)
            && lantern_fork_choice_block_info(
                   &client->fork_choice,
                   &post_finalized->root,
                   NULL,
                   NULL,
                   NULL)
                == 0;
        if (lantern_fork_choice_add_block_with_state(
                &client->fork_choice,
                block,
                post_justified,
                post_finalized,
                &entry->root,
                post_state_for_restore)
            != 0)
        {
            lantern_log_warn(
                "forkchoice",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to restore block at slot %" PRIu64
                " root=%s parent=%s cached_post_state=%s post_justified_slot=%" PRIu64
                " post_justified_root=%s post_justified_known=%s"
                " post_finalized_slot=%" PRIu64 " post_finalized_root=%s"
                " post_finalized_known=%s canonical_anchor_state=%s",
                entry->block.block.slot,
                block_root_hex[0] ? block_root_hex : "0x0",
                parent_root_hex[0] ? parent_root_hex : "0x0",
                have_cached_post_state ? "true" : "false",
                post_justified->slot,
                post_justified_root_hex[0] ? post_justified_root_hex : "0x0",
                justified_known ? "true" : "false",
                post_finalized->slot,
                post_finalized_root_hex[0] ? post_finalized_root_hex : "0x0",
                finalized_known ? "true" : "false",
                using_canonical_anchor_state ? "true" : "false");
        }
        else
        {
            lantern_client_cache_block_aggregated_proofs_locked(client, &entry->block);
        }
        if (have_cached_post_state)
        {
            lantern_state_reset(&cached_post_state);
        }
    }

    uint64_t now_milliseconds = validator_wall_time_now_millis();
    if (lantern_client_advance_fork_choice_time_locked(client, now_milliseconds, false) != 0)
    {
        lantern_log_warn(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "advancing fork choice time after restore failed");
    }

    LanternCheckpoint restored_justified = client->state.latest_justified;
    LanternCheckpoint restored_finalized = client->state.latest_finalized;
    const LanternRoot *restore_anchor_root =
        lantern_fork_choice_anchor_root(&client->fork_choice);
    uint64_t restore_anchor_slot = 0;
    bool have_restore_anchor_slot =
        lantern_fork_choice_anchor_slot(&client->fork_choice, &restore_anchor_slot) == 0;
    bool restored_justified_known =
        !lantern_root_is_zero(&restored_justified.root)
        && lantern_fork_choice_block_info(
               &client->fork_choice,
               &restored_justified.root,
               NULL,
               NULL,
               NULL)
            == 0;
    bool restored_finalized_known =
        !lantern_root_is_zero(&restored_finalized.root)
        && lantern_fork_choice_block_info(
               &client->fork_choice,
               &restored_finalized.root,
               NULL,
               NULL,
               NULL)
            == 0;
    if (restore_anchor_root && have_restore_anchor_slot)
    {
        if (!restored_justified_known && restored_justified.slot <= restore_anchor_slot)
        {
            char original_justified_hex[ROOT_HEX_BUFFER_LEN];
            char anchor_hex[ROOT_HEX_BUFFER_LEN];
            format_root_hex(
                &restored_justified.root,
                original_justified_hex,
                sizeof(original_justified_hex));
            format_root_hex(
                restore_anchor_root,
                anchor_hex,
                sizeof(anchor_hex));
            lantern_log_info(
                "forkchoice",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "rebasing restored justified checkpoint slot=%" PRIu64
                " original_root=%s anchor_slot=%" PRIu64 " anchor_root=%s",
                restored_justified.slot,
                original_justified_hex[0] ? original_justified_hex : "0x0",
                restore_anchor_slot,
                anchor_hex[0] ? anchor_hex : "0x0");
            restored_justified.root = *restore_anchor_root;
            restored_justified.slot = restore_anchor_slot;
        }
        if (!restored_finalized_known && restored_finalized.slot <= restore_anchor_slot)
        {
            char original_finalized_hex[ROOT_HEX_BUFFER_LEN];
            char anchor_hex[ROOT_HEX_BUFFER_LEN];
            format_root_hex(
                &restored_finalized.root,
                original_finalized_hex,
                sizeof(original_finalized_hex));
            format_root_hex(
                restore_anchor_root,
                anchor_hex,
                sizeof(anchor_hex));
            lantern_log_info(
                "forkchoice",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "rebasing restored finalized checkpoint slot=%" PRIu64
                " original_root=%s anchor_slot=%" PRIu64 " anchor_root=%s",
                restored_finalized.slot,
                original_finalized_hex[0] ? original_finalized_hex : "0x0",
                restore_anchor_slot,
                anchor_hex[0] ? anchor_hex : "0x0");
            restored_finalized.root = *restore_anchor_root;
            restored_finalized.slot = restore_anchor_slot;
        }
    }

    if (lantern_fork_choice_restore_checkpoints(
            &client->fork_choice,
            &restored_justified,
            &restored_finalized)
        != 0)
    {
        lantern_log_warn(
            "forkchoice",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "restoring persisted checkpoints after block restore failed");
    }

    persisted_block_list_reset(&list);
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Validator State Refresh
 * ============================================================================ */

/**
 * @brief Populate a packed pubkey buffer from registry records.
 *
 * Registry records carry one pubkey, so empty-state initialization uses it for
 * both attestation and proposal keys.
 *
 * @param registry            Validator registry (must have records)
 * @param packed_pubkeys      Output packed pubkey buffer
 * @param count               Number of validators to write
 * @param out_registry_used   Output count of pubkeys sourced from registry
 * @param out_missing_pubkeys Output count of missing pubkeys
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 *
 * @note Thread safety: Caller must ensure exclusive access during initialization
 */
static int populate_validator_pubkeys(
    struct lantern_validator_registry *registry,
    uint8_t *packed_pubkeys,
    size_t count,
    size_t *out_registry_used,
    size_t *out_missing_pubkeys)
{
    if (!registry || !registry->records || !packed_pubkeys
        || !out_registry_used || !out_missing_pubkeys)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *out_registry_used = 0;
    *out_missing_pubkeys = 0;

    for (size_t i = 0; i < count; ++i)
    {
        struct lantern_validator_record *record = &registry->records[i];
        const uint8_t *registry_pub = NULL;
        if (record->has_pubkey_bytes && !lantern_validator_pubkey_is_zero(record->pubkey_bytes))
        {
            registry_pub = record->pubkey_bytes;
        }

        size_t offset = i * LANTERN_VALIDATOR_PUBKEY_SIZE;
        if (registry_pub)
        {
            memcpy(
                packed_pubkeys + offset,
                registry_pub,
                LANTERN_VALIDATOR_PUBKEY_SIZE);
            ++(*out_registry_used);
        }
        else
        {
            memset(packed_pubkeys + offset, 0, LANTERN_VALIDATOR_PUBKEY_SIZE);
            ++(*out_missing_pubkeys);
        }
    }

    return LANTERN_CLIENT_OK;
}


/**
 * Validate existing state validator pubkeys or initialize them from genesis registry.
 *
 * @spec subspecs/containers/validator.py - Validator pubkey management
 *
 * Existing state pubkeys are part of the verified state root, so they are
 * preserved. Registry-derived initialization is only used for an empty state.
 *
 * @param client  Client instance
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if client is NULL or missing state
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_RUNTIME if state update fails
 *
 * @note Thread safety: Caller must ensure exclusive access during initialization
 */
int lantern_client_refresh_state_validators(struct lantern_client *client)
{
    if (!client || !client->has_state)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_log_metadata meta = {.validator = client->node_id};
    struct lantern_validator_registry *registry = &client->genesis.validator_registry;
    size_t registry_count = registry->count;
    size_t state_count = lantern_state_validator_count(&client->state);

    if (state_count > 0)
    {
        bool have_local_pubkeys =
            client->genesis.chain_config.validator_attestation_pubkeys
            && client->genesis.chain_config.validator_proposal_pubkeys
            && client->genesis.chain_config.validator_pubkeys_count > 0;
        if (have_local_pubkeys)
        {
            int validate_rc = lantern_client_validate_state_validator_pubkeys(
                client,
                &client->state,
                "client");
            if (validate_rc != LANTERN_CLIENT_OK)
            {
                return validate_rc;
            }
        }
        lantern_log_info(
            "client",
            &meta,
            "retaining existing state pubkeys count=%zu",
            state_count);
        return LANTERN_CLIENT_OK;
    }

    bool have_registry = registry->records && registry_count > 0;
    if (!have_registry)
    {
        if (lantern_state_set_validator_pubkeys(&client->state, NULL, 0) != 0)
        {
            return LANTERN_CLIENT_ERR_RUNTIME;
        }
        return LANTERN_CLIENT_OK;
    }

    size_t count = registry_count;
    if (count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    size_t total_bytes = count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *packed_pubkeys = malloc(total_bytes);
    if (!packed_pubkeys)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    size_t registry_used = 0;
    size_t missing_pubkeys = 0;
    int pack_rc = populate_validator_pubkeys(
        registry,
        packed_pubkeys,
        count,
        &registry_used,
        &missing_pubkeys);
    if (pack_rc != LANTERN_CLIENT_OK)
    {
        free(packed_pubkeys);
        return pack_rc;
    }
    int rc = lantern_state_set_validator_pubkeys(
        &client->state,
        packed_pubkeys,
        count);
    free(packed_pubkeys);
    if (rc != 0)
    {
        lantern_log_warn(
            "client",
            &meta,
            "failed to copy validator pubkeys into parent state");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    size_t enabled = lantern_client_enabled_validator_count(client);
    lantern_log_info(
        "client",
        &meta,
        "refreshed validator pubkeys count=%zu registry=%zu missing=%zu "
        "local_validators=%zu enabled=%zu",
        count,
        registry_used,
        missing_pubkeys,
        client->local_validator_count,
        enabled);
    return LANTERN_CLIENT_OK;
}


/* ============================================================================
 * Pending Block Management
 * ============================================================================ */

/**
 * @brief Remove a pending block by root (internal, no locking).
 *
 * @param client  Client instance
 * @param root    Block root to remove
 *
 * @note Thread safety: Caller must hold pending_lock
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
 * @spec subspecs/forkchoice/store.py - Pending block cleanup
 *
 * Removes a block from the pending queue once it has been imported.
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

static uint32_t active_blocks_requests_for_peer_locked(
    const struct lantern_client *client,
    const char *peer_id)
{
    if (!client || !peer_id || peer_id[0] == '\0')
    {
        return 0u;
    }

    uint32_t count = 0u;
    for (size_t i = 0; i < client->active_blocks_request_count; ++i)
    {
        const struct lantern_active_blocks_request *request = &client->active_blocks_requests[i];
        if (request->peer_id[0] == '\0')
        {
            continue;
        }
        if (strncmp(request->peer_id, peer_id, sizeof(request->peer_id)) == 0)
        {
            if (count < UINT32_MAX)
            {
                count += 1u;
            }
        }
    }
    return count;
}

static bool reserve_active_blocks_request_locked(
    struct lantern_client *client,
    const char *peer_id,
    uint64_t now_ms,
    uint64_t timeout_ms,
    uint64_t *out_request_id)
{
    if (!client || !peer_id || peer_id[0] == '\0' || !out_request_id)
    {
        return false;
    }

    if (client->active_blocks_request_count >= client->active_blocks_request_capacity)
    {
        size_t new_capacity = client->active_blocks_request_capacity == 0
            ? 8u
            : client->active_blocks_request_capacity * 2u;
        if (new_capacity <= client->active_blocks_request_capacity
            || new_capacity > (SIZE_MAX / sizeof(*client->active_blocks_requests)))
        {
            return false;
        }
        struct lantern_active_blocks_request *grown = realloc(
            client->active_blocks_requests,
            new_capacity * sizeof(*client->active_blocks_requests));
        if (!grown)
        {
            return false;
        }
        client->active_blocks_requests = grown;
        client->active_blocks_request_capacity = new_capacity;
    }

    if (client->next_blocks_request_id == 0u)
    {
        client->next_blocks_request_id = 1u;
    }
    uint64_t request_id = client->next_blocks_request_id;
    client->next_blocks_request_id += 1u;
    if (client->next_blocks_request_id == 0u)
    {
        client->next_blocks_request_id = 1u;
    }

    uint64_t deadline_ms = UINT64_MAX;
    if (timeout_ms < UINT64_MAX - now_ms)
    {
        deadline_ms = now_ms + timeout_ms;
    }

    struct lantern_active_blocks_request *entry =
        &client->active_blocks_requests[client->active_blocks_request_count];
    memset(entry, 0, sizeof(*entry));
    entry->request_id = request_id;
    entry->started_ms = now_ms;
    entry->deadline_ms = deadline_ms;
    (void)lantern_string_copy(entry->peer_id, sizeof(entry->peer_id), peer_id);
    client->active_blocks_request_count += 1u;
    *out_request_id = request_id;
    return true;
}

static void sweep_expired_active_blocks_requests_locked(
    struct lantern_client *client,
    uint64_t now_ms)
{
    if (!client || client->active_blocks_request_count == 0)
    {
        return;
    }

    for (size_t i = 0; i < client->active_blocks_request_count;)
    {
        struct lantern_active_blocks_request *request = &client->active_blocks_requests[i];
        if (request->deadline_ms != UINT64_MAX && now_ms >= request->deadline_ms)
        {
            uint64_t age_ms = now_ms >= request->started_ms ? now_ms - request->started_ms : 0u;
            if (!request->timeout_recorded)
            {
                request->timeout_recorded = true;
                if (LANTERN_BLOCKS_REQUEST_HARD_TIMEOUT_MS < UINT64_MAX - now_ms)
                {
                    request->deadline_ms = now_ms + LANTERN_BLOCKS_REQUEST_HARD_TIMEOUT_MS;
                }
                else
                {
                    request->deadline_ms = UINT64_MAX;
                }

                lantern_log_warn(
                    "backfill",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = request->peer_id[0] ? request->peer_id : NULL},
                    "request failed, peer %s, reason: timeout, request_id %" PRIu64
                    ", age_ms %" PRIu64,
                    request->peer_id[0] ? request->peer_id : "-",
                    request->request_id,
                    age_ms);
                i += 1u;
                continue;
            }

            lantern_log_warn(
                "backfill",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = request->peer_id[0] ? request->peer_id : NULL},
                "request failed, peer %s, reason: hard_timeout, request_id %" PRIu64
                ", age_ms %" PRIu64,
                request->peer_id[0] ? request->peer_id : "-",
                request->request_id,
                age_ms);

            size_t last = client->active_blocks_request_count - 1u;
            if (i != last)
            {
                client->active_blocks_requests[i] = client->active_blocks_requests[last];
            }
            client->active_blocks_request_count = last;
            continue;
        }
        i += 1u;
    }
}


/**
 * Enqueue a pending block for later processing.
 *
 * @spec subspecs/forkchoice/store.py - Orphan block handling
 *
 * Queues a block whose parent is not yet known. The block will be
 * imported once its parent arrives. When the client is syncing or
 * synced, it requests the missing parent via reqresp.
 *
 * @param client       Client instance
 * @param block        Block to enqueue
 * @param block_root   Block root
 * @param parent_root  Parent block root
 * @param peer_text    Peer ID string (may be NULL)
 *
 * @note Thread safety: Acquires pending_lock
 */
static bool try_schedule_blocks_request_batch(
    struct lantern_client *client,
    const char *peer_text,
    const LanternRoot *roots,
    const uint32_t *depths,
    size_t root_count)
{
    if (!client || !roots || root_count == 0)
    {
        if (client)
        {
            lantern_log_warn(
                "backfill",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "not scheduled, reason: invalid_request, roots %zu",
                root_count);
        }
        return false;
    }
    if (root_count > LANTERN_MAX_REQUEST_BLOCKS)
    {
        lantern_log_warn(
            "backfill",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "not scheduled, reason: too_many_roots, roots %zu",
            root_count);
        return false;
    }
    if (!client->status_lock_initialized)
    {
        lantern_log_warn(
            "backfill",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "not scheduled, reason: status_lock_not_initialized, roots %zu",
            root_count);
        return false;
    }
    if (client->debug_disable_block_requests)
    {
        lantern_log_info(
            "backfill",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "not scheduled, reason: block_requests_disabled, roots %zu",
            root_count);
        return false;
    }

    uint32_t min_depth = UINT32_MAX;
    uint32_t max_depth = 0;
    if (depths)
    {
        for (size_t i = 0; i < root_count; ++i)
        {
            if (depths[i] < min_depth)
            {
                min_depth = depths[i];
            }
            if (depths[i] > max_depth)
            {
                max_depth = depths[i];
            }
        }
    }

    for (size_t i = 0; i < root_count; ++i)
    {
        if (lantern_root_is_zero(&roots[i]))
        {
            lantern_log_warn(
                "backfill",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "not scheduled, reason: zero_root, roots %zu",
                root_count);
            return false;
        }
        if (depths && depths[i] > LANTERN_MAX_BACKFILL_DEPTH)
        {
            lantern_log_warn(
                "backfill",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "not scheduled, reason: depth_limit, roots %zu, depth %" PRIu32,
                root_count,
                depths[i]);
            return false;
        }
    }

    char first_root_hex[ROOT_HEX_BUFFER_LEN];
    first_root_hex[0] = '\0';
    if (root_count > 0)
    {
        format_root_hex(&roots[0], first_root_hex, sizeof(first_root_hex));
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        lantern_log_warn(
            "backfill",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "not scheduled, reason: status_lock_failed, roots %zu",
            root_count);
        return false;
    }

    uint64_t now_ms = monotonic_millis();
    sweep_expired_active_blocks_requests_locked(client, now_ms);
    struct lantern_peer_status_entry *entry = NULL;
    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    char selected_peer[PEER_TEXT_BUFFER_LEN];
    selected_peer[0] = '\0';

    if (peer_text && peer_text[0])
    {
        entry = lantern_client_ensure_status_entry_locked(client, peer_text);
        if (entry)
        {
            bool connected = lantern_client_is_peer_connected(client, peer_text);
            uint32_t inflight = active_blocks_requests_for_peer_locked(client, peer_text);
            bool inflight_full =
                inflight >= LANTERN_MAX_BLOCKS_REQUESTS_PER_PEER;
            if (!connected)
            {
                uint64_t age_ms = 0;
                if (entry->last_status_ms != 0 && now_ms >= entry->last_status_ms)
                {
                    age_ms = now_ms - entry->last_status_ms;
                }
                lantern_log_info(
                    "backfill",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = peer_text},
                    "not scheduled, peer %s, reason: peer_not_connected, roots %zu, connected %s, inflight %" PRIu32
                    ", failures %" PRIu32 ", has_status %s, status_age_ms %" PRIu64,
                    peer_text,
                    root_count,
                    connected ? "true" : "false",
                    inflight,
                    entry->consecutive_blocks_failures,
                    entry->has_status ? "true" : "false",
                    age_ms);
                entry = NULL;
            }
            else if (inflight_full)
            {
                /* Keep parent-chase continuity on the same peer. Falling back to a
                 * different peer while the preferred one is still streaming tends to
                 * produce alternating success/empty responses and slows convergence. */
                lantern_log_debug(
                    "backfill",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = peer_text},
                    "not scheduled, peer %s, reason: request_limit_hit, inflight %" PRIu32
                    ", max %" PRIu32 ", roots %zu",
                    peer_text,
                    inflight,
                    LANTERN_MAX_BLOCKS_REQUESTS_PER_PEER,
                    root_count);
                pthread_mutex_unlock(&client->status_lock);
                return false;
            }
        }
    }

    struct lantern_peer_status_entry *best_entry = entry;
    bool best_fresh = false;
    uint32_t best_inflight = entry ? active_blocks_requests_for_peer_locked(client, entry->peer_id) : 0u;
    uint32_t best_failures = entry ? entry->consecutive_blocks_failures : 0;
    uint64_t best_status_ms = entry ? entry->last_status_ms : 0;
    if (entry && entry->has_status
        && entry->last_status_ms != 0
        && now_ms >= entry->last_status_ms)
    {
        uint64_t age_ms = now_ms - entry->last_status_ms;
        if (age_ms <= LANTERN_PEER_STATUS_STALE_MS)
        {
            best_fresh = true;
        }
    }

    for (size_t i = 0; i < client->peer_status_count; ++i)
    {
        struct lantern_peer_status_entry *candidate = &client->peer_status_entries[i];
        if (!candidate->peer_id[0])
        {
            continue;
        }
        if (best_entry && candidate == best_entry)
        {
            continue;
        }
        uint32_t candidate_inflight =
            active_blocks_requests_for_peer_locked(client, candidate->peer_id);
        if (candidate_inflight >= LANTERN_MAX_BLOCKS_REQUESTS_PER_PEER)
        {
            continue;
        }
        if (!lantern_client_is_peer_connected(client, candidate->peer_id))
        {
            continue;
        }

        bool fresh = false;
        if (candidate->has_status
            && candidate->last_status_ms != 0
            && now_ms >= candidate->last_status_ms)
        {
            uint64_t age_ms = now_ms - candidate->last_status_ms;
            if (age_ms <= LANTERN_PEER_STATUS_STALE_MS)
            {
                fresh = true;
            }
        }

        if (!best_entry)
        {
            best_entry = candidate;
            best_fresh = fresh;
            best_inflight = candidate_inflight;
            best_failures = candidate->consecutive_blocks_failures;
            best_status_ms = candidate->last_status_ms;
            continue;
        }

        if (candidate->consecutive_blocks_failures < best_failures)
        {
            best_entry = candidate;
            best_fresh = fresh;
            best_inflight = candidate_inflight;
            best_failures = candidate->consecutive_blocks_failures;
            best_status_ms = candidate->last_status_ms;
            continue;
        }
        if (candidate->consecutive_blocks_failures > best_failures)
        {
            continue;
        }

        if (fresh && !best_fresh)
        {
            best_entry = candidate;
            best_fresh = true;
            best_inflight = candidate_inflight;
            best_failures = candidate->consecutive_blocks_failures;
            best_status_ms = candidate->last_status_ms;
            continue;
        }
        if (fresh == best_fresh)
        {
            if (candidate_inflight < best_inflight)
            {
                best_entry = candidate;
                best_inflight = candidate_inflight;
                best_failures = candidate->consecutive_blocks_failures;
                best_status_ms = candidate->last_status_ms;
                continue;
            }
            if (candidate_inflight == best_inflight)
            {
                if (candidate->last_status_ms > best_status_ms)
                {
                    best_entry = candidate;
                    best_status_ms = candidate->last_status_ms;
                    continue;
                }
            }
        }
    }

    entry = best_entry;
    if (!entry)
    {
        size_t connected_entries = 0;
        size_t has_status_entries = 0;
        size_t fresh_entries = 0;
        size_t inflight_full_entries = 0;
        size_t stale_entries = 0;
        for (size_t i = 0; i < client->peer_status_count; ++i)
        {
            struct lantern_peer_status_entry *candidate = &client->peer_status_entries[i];
            if (!candidate->peer_id[0])
            {
                continue;
            }
            uint32_t candidate_inflight =
                active_blocks_requests_for_peer_locked(client, candidate->peer_id);
            if (candidate_inflight >= LANTERN_MAX_BLOCKS_REQUESTS_PER_PEER)
            {
                inflight_full_entries += 1u;
            }
            bool connected = lantern_client_is_peer_connected(client, candidate->peer_id);
            if (connected)
            {
                connected_entries += 1u;
            }
            if (candidate->has_status)
            {
                has_status_entries += 1u;
                if (candidate->last_status_ms != 0 && now_ms >= candidate->last_status_ms)
                {
                    uint64_t age_ms = now_ms - candidate->last_status_ms;
                    if (age_ms <= LANTERN_PEER_STATUS_STALE_MS)
                    {
                        fresh_entries += 1u;
                    }
                    else
                    {
                        stale_entries += 1u;
                    }
                }
            }
        }
        lantern_log_info(
            "backfill",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "not scheduled, reason: no_eligible_peer, roots %zu, peers %zu, status_entries %zu, "
            "connected_entries %zu, has_status %zu, fresh %zu, stale %zu, request_limit_hit %zu",
            root_count,
            client->connected_peers,
            client->peer_status_count,
            connected_entries,
            has_status_entries,
            fresh_entries,
            stale_entries,
            inflight_full_entries);
        pthread_mutex_unlock(&client->status_lock);
        return false;
    }

    size_t copy_cap = sizeof(selected_peer);
    if (peer_cap < copy_cap)
    {
        copy_cap = peer_cap;
    }
    (void)lantern_string_copy(selected_peer, copy_cap, entry->peer_id);
    uint64_t request_id = 0u;
    if (!reserve_active_blocks_request_locked(
            client,
            selected_peer,
            now_ms,
            LANTERN_BLOCKS_REQUEST_TIMEOUT_MS,
            &request_id))
    {
        lantern_log_warn(
            "backfill",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = selected_peer[0] ? selected_peer : NULL},
            "not scheduled, peer %s, reason: request_tracking_full, roots %zu",
            selected_peer[0] ? selected_peer : "-",
            root_count);
        pthread_mutex_unlock(&client->status_lock);
        return false;
    }
    pthread_mutex_unlock(&client->status_lock);

    lantern_log_debug(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = selected_peer[0] ? selected_peer : NULL},
        "blocks_by_root scheduling request_id=%" PRIu64 " roots=%zu first_root=%s depth_min=%" PRIu32 " depth_max=%" PRIu32,
        request_id,
        root_count,
        first_root_hex[0] ? first_root_hex : "0x0",
        min_depth == UINT32_MAX ? 0u : min_depth,
        max_depth);
    if (lantern_client_schedule_blocks_request_batch(
            client,
            selected_peer,
            roots,
            root_count,
            request_id)
        != 0)
    {
        lantern_log_warn(
            "backfill",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = selected_peer},
            "not scheduled, peer %s, reason: scheduler_failed, roots %zu",
            selected_peer[0] ? selected_peer : "-",
            root_count);
        /*
         * The reqresp scheduler completes parse/open-stream failures itself so
         * the reserved request id is released exactly once.
         */
        return false;
    }

    lantern_log_info(
        "backfill",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = selected_peer[0] ? selected_peer : NULL},
        "request sent, parent %s, peer %s, roots %zu, request_id %" PRIu64,
        first_root_hex[0] ? first_root_hex : "0x0",
        selected_peer[0] ? selected_peer : "-",
        root_count,
        request_id);
    return true;
}

bool lantern_client_try_schedule_blocks_request_batch(
    struct lantern_client *client,
    const char *peer_text,
    const LanternRoot *roots,
    const uint32_t *depths,
    size_t root_count)
{
    return try_schedule_blocks_request_batch(client, peer_text, roots, depths, root_count);
}

static bool try_schedule_blocks_request(
    struct lantern_client *client,
    const char *peer_text,
    const LanternRoot *root,
    uint32_t backfill_depth)
{
    if (!client || !root || lantern_root_is_zero(root))
    {
        return false;
    }
    if (backfill_depth > LANTERN_MAX_BACKFILL_DEPTH)
    {
        return false;
    }

    const char *preferred_peer = NULL;
    if (peer_text && peer_text[0])
    {
        preferred_peer = peer_text;
    }
    return try_schedule_blocks_request_batch(
        client,
        preferred_peer,
        root,
        &backfill_depth,
        1u);
}

static void mark_pending_parent_requested(
    struct lantern_client *client,
    const LanternRoot *parent_root,
    bool requested)
{
    if (!client || !parent_root)
    {
        return;
    }

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return;
    }

    uint64_t request_ms = requested ? monotonic_millis() : 0u;

    for (size_t i = 0; i < client->pending_blocks.length; ++i)
    {
        struct lantern_pending_block *entry = &client->pending_blocks.items[i];
        if (memcmp(entry->parent_root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            entry->parent_requested = requested;
            entry->parent_requested_ms = request_ms;
        }
    }

    lantern_client_unlock_pending(client, locked);
}

static bool pending_parent_request_is_stale(
    const struct lantern_pending_block *entry,
    uint64_t now_ms)
{
    if (!entry || !entry->parent_requested)
    {
        return false;
    }
    if (entry->parent_requested_ms == 0)
    {
        return true;
    }
    return now_ms >= entry->parent_requested_ms + LANTERN_PENDING_PARENT_REQUEST_STALE_MS;
}

struct pending_parent_candidate
{
    LanternRoot child_root;
    LanternRoot parent_root;
    uint32_t request_depth;
    bool parent_cached;
};

static int pending_parent_candidate_compare(const void *left, const void *right)
{
    const struct pending_parent_candidate *left_entry = left;
    const struct pending_parent_candidate *right_entry = right;

    if (left_entry->request_depth > right_entry->request_depth)
    {
        return -1;
    }
    if (left_entry->request_depth < right_entry->request_depth)
    {
        return 1;
    }
    return memcmp(
        left_entry->parent_root.bytes,
        right_entry->parent_root.bytes,
        LANTERN_ROOT_SIZE);
}

struct pending_child_replay
{
    LanternSignedBlock block;
    LanternRoot root;
    char peer_text[PEER_TEXT_BUFFER_LEN];
    uint64_t slot;
    uint32_t backfill_depth;
};

static int pending_child_replay_compare(const void *left, const void *right)
{
    const struct pending_child_replay *left_entry = left;
    const struct pending_child_replay *right_entry = right;
    if (left_entry->slot < right_entry->slot)
    {
        return -1;
    }
    if (left_entry->slot > right_entry->slot)
    {
        return 1;
    }
    return memcmp(left_entry->root.bytes, right_entry->root.bytes, LANTERN_ROOT_SIZE);
}

struct pending_child_root_queue
{
    LanternRoot *items;
    size_t length;
    size_t capacity;
    size_t next_index;
};

static void pending_child_root_queue_init(struct pending_child_root_queue *queue)
{
    if (!queue)
    {
        return;
    }
    memset(queue, 0, sizeof(*queue));
}

static void pending_child_root_queue_reset(struct pending_child_root_queue *queue)
{
    if (!queue)
    {
        return;
    }
    free(queue->items);
    memset(queue, 0, sizeof(*queue));
}

static bool pending_child_root_queue_append(
    struct pending_child_root_queue *queue,
    const LanternRoot *root)
{
    if (!queue || !root)
    {
        return false;
    }
    if (queue->length == queue->capacity)
    {
        size_t next_capacity = queue->capacity == 0 ? 8u : (queue->capacity + (queue->capacity / 2u));
        if (next_capacity < queue->capacity)
        {
            return false;
        }
        if (next_capacity > SIZE_MAX / sizeof(*queue->items))
        {
            return false;
        }
        LanternRoot *expanded = realloc(queue->items, next_capacity * sizeof(*expanded));
        if (!expanded)
        {
            return false;
        }
        queue->items = expanded;
        queue->capacity = next_capacity;
    }
    queue->items[queue->length] = *root;
    queue->length += 1u;
    return true;
}

static bool pending_child_root_queue_next(
    struct pending_child_root_queue *queue,
    LanternRoot *out_root)
{
    if (!queue || !out_root || queue->next_index >= queue->length)
    {
        return false;
    }
    *out_root = queue->items[queue->next_index];
    queue->next_index += 1u;
    return true;
}

void lantern_client_pending_remove_branch_by_root(
    struct lantern_client *client,
    const LanternRoot *root)
{
    if (!client || !root || lantern_root_is_zero(root))
    {
        return;
    }

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return;
    }

    struct pending_child_root_queue queue;
    pending_child_root_queue_init(&queue);
    if (!pending_child_root_queue_append(&queue, root))
    {
        pending_child_root_queue_reset(&queue);
        lantern_client_unlock_pending(client, locked);
        return;
    }

    size_t removed = 0;
    LanternRoot current = {0};
    while (pending_child_root_queue_next(&queue, &current))
    {
        for (size_t i = client->pending_blocks.length; i-- > 0;)
        {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            bool root_matches =
                memcmp(entry->root.bytes, current.bytes, LANTERN_ROOT_SIZE) == 0;
            bool child_matches =
                memcmp(entry->parent_root.bytes, current.bytes, LANTERN_ROOT_SIZE) == 0;
            if (!root_matches && !child_matches)
            {
                continue;
            }

            LanternRoot child_root = entry->root;
            pending_block_list_remove(&client->pending_blocks, i);
            removed += 1u;

            if (child_matches)
            {
                (void)pending_child_root_queue_append(&queue, &child_root);
            }
        }
    }

    pending_child_root_queue_reset(&queue);
    lantern_client_unlock_pending(client, locked);

    if (removed > 0)
    {
        char root_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(root, root_hex, sizeof(root_hex));
        lantern_log_debug(
            "sync",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pruned pending branch root=%s removed=%zu",
            root_hex[0] ? root_hex : "0x0",
            removed);
    }
}

void lantern_client_request_pending_parent_after_blocks(
    struct lantern_client *client,
    const char *peer_text,
    const LanternRoot *request_root)
{
    if (!client)
    {
        return;
    }

    struct pending_parent_candidate candidates[LANTERN_PENDING_BLOCK_LIMIT];
    size_t candidate_count = 0;
    LanternRoot requested_root = {0};
    bool has_requested_root = false;
    bool prefer_requested_root = false;
    bool requested_parent_requested = false;
    bool requested_parent_stale = false;
    uint64_t now_ms = monotonic_millis();
    struct pending_parent_candidate requested_candidate = {0};
    if (request_root && !lantern_root_is_zero(request_root))
    {
        requested_root = *request_root;
        has_requested_root = true;
    }

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return;
    }

    if (has_requested_root)
    {
        for (size_t i = 0; i < client->pending_blocks.length; ++i)
        {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            if (memcmp(entry->root.bytes, requested_root.bytes, LANTERN_ROOT_SIZE) != 0)
            {
                continue;
            }
            if (lantern_root_is_zero(&entry->parent_root))
            {
                break;
            }
            if (entry->backfill_depth >= LANTERN_MAX_BACKFILL_DEPTH)
            {
                break;
            }
            requested_candidate.child_root = entry->root;
            requested_candidate.parent_root = entry->parent_root;
            requested_candidate.request_depth = entry->backfill_depth + 1u;
            requested_candidate.parent_cached = pending_block_list_find(
                &client->pending_blocks,
                &entry->parent_root)
                != NULL;
            requested_parent_requested = entry->parent_requested;
            requested_parent_stale = pending_parent_request_is_stale(entry, now_ms);
            if (requested_parent_stale)
            {
                requested_parent_requested = false;
            }
            if (!requested_candidate.parent_cached && !requested_parent_requested)
            {
                prefer_requested_root = true;
            }
            break;
        }
    }

    for (size_t i = 0; i < client->pending_blocks.length; ++i)
    {
        struct lantern_pending_block *entry = &client->pending_blocks.items[i];
        if (entry->parent_requested && !pending_parent_request_is_stale(entry, now_ms))
        {
            continue;
        }
        if (lantern_root_is_zero(&entry->parent_root))
        {
            continue;
        }
        if (entry->backfill_depth >= LANTERN_MAX_BACKFILL_DEPTH)
        {
            continue;
        }
        bool parent_cached = pending_block_list_find(
            &client->pending_blocks,
            &entry->parent_root)
            != NULL;
        if (parent_cached)
        {
            continue;
        }
        if (has_requested_root
            && memcmp(entry->parent_root.bytes, requested_root.bytes, LANTERN_ROOT_SIZE) == 0)
        {
            continue;
        }
        if (candidate_count >= LANTERN_PENDING_BLOCK_LIMIT)
        {
            break;
        }
        candidates[candidate_count].child_root = entry->root;
        candidates[candidate_count].parent_root = entry->parent_root;
        candidates[candidate_count].request_depth = entry->backfill_depth + 1u;
        candidates[candidate_count].parent_cached = parent_cached;
        candidate_count += 1u;
    }

    lantern_client_unlock_pending(client, locked);

    char requested_hex[ROOT_HEX_BUFFER_LEN];
    requested_hex[0] = '\0';
    if (has_requested_root)
    {
        format_root_hex(&requested_root, requested_hex, sizeof(requested_hex));
    }
    lantern_log_debug(
        "sync",
        &(const struct lantern_log_metadata){.validator = client->node_id},
        "pending parent scan requested_root=%s candidates=%zu prefer_requested=%s requested_parent=%s requested_parent_stale=%s",
        has_requested_root ? (requested_hex[0] ? requested_hex : "0x0") : "-",
        candidate_count,
        prefer_requested_root ? "true" : "false",
        requested_parent_requested ? "true" : "false",
        requested_parent_stale ? "true" : "false");

    if (candidate_count == 0)
    {
        locked = lantern_client_lock_pending(client);
        if (!locked)
        {
            return;
        }
        for (size_t i = 0; i < client->pending_blocks.length; ++i)
        {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            if (entry->parent_requested && !pending_parent_request_is_stale(entry, now_ms))
            {
                continue;
            }
            if (lantern_root_is_zero(&entry->parent_root))
            {
                continue;
            }
            if (entry->backfill_depth >= LANTERN_MAX_BACKFILL_DEPTH)
            {
                continue;
            }
            bool parent_cached = pending_block_list_find(
                &client->pending_blocks,
                &entry->parent_root)
                != NULL;
            if (parent_cached)
            {
                continue;
            }
            if (has_requested_root
                && memcmp(entry->parent_root.bytes, requested_root.bytes, LANTERN_ROOT_SIZE) == 0)
            {
                continue;
            }
            if (candidate_count >= LANTERN_PENDING_BLOCK_LIMIT)
            {
                break;
            }
            candidates[candidate_count].child_root = entry->root;
            candidates[candidate_count].parent_root = entry->parent_root;
            candidates[candidate_count].request_depth = entry->backfill_depth + 1u;
            candidates[candidate_count].parent_cached = parent_cached;
            candidate_count += 1u;
        }
        lantern_client_unlock_pending(client, locked);
    }

    if (candidate_count > 1u)
    {
        /* Prioritize deepest missing ancestors first so backfill converges to a
         * known anchor quickly instead of diffusing requests across shallow tips. */
        qsort(
            candidates,
            candidate_count,
            sizeof(candidates[0]),
            pending_parent_candidate_compare);
    }

    LanternRoot request_roots[LANTERN_MAX_REQUEST_BLOCKS];
    uint32_t request_depths[LANTERN_MAX_REQUEST_BLOCKS];
    size_t request_count = 0;

    if (prefer_requested_root)
    {
        if (!requested_candidate.parent_cached
            && !requested_parent_requested
            && !lantern_root_is_zero(&requested_candidate.parent_root))
        {
            request_roots[request_count] = requested_candidate.parent_root;
            request_depths[request_count] = requested_candidate.request_depth;
            request_count += 1u;
        }
    }

    for (size_t i = 0; i < candidate_count; ++i)
    {
        if (request_count >= LANTERN_MAX_REQUEST_BLOCKS)
        {
            break;
        }
        bool duplicate = false;
        for (size_t j = 0; j < request_count; ++j)
        {
            if (memcmp(
                    request_roots[j].bytes,
                    candidates[i].parent_root.bytes,
                    LANTERN_ROOT_SIZE)
                == 0)
            {
                duplicate = true;
                break;
            }
        }
        if (duplicate)
        {
            continue;
        }
        if (candidates[i].parent_cached)
        {
            continue;
        }
        request_roots[request_count] = candidates[i].parent_root;
        request_depths[request_count] = candidates[i].request_depth;
        request_count += 1u;
    }

    if (request_count == 0)
    {
        lantern_log_debug(
            "sync",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pending parent request skipped candidates=%zu",
            candidate_count);
        return;
    }

    const char *preferred_peer = (peer_text && peer_text[0]) ? peer_text : NULL;
    if (try_schedule_blocks_request_batch(
            client,
            preferred_peer,
            request_roots,
            request_depths,
            request_count))
    {
        for (size_t i = 0; i < request_count; ++i)
        {
            mark_pending_parent_requested(client, &request_roots[i], true);
        }
        lantern_log_debug(
            "sync",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pending parent request scheduled count=%zu",
            request_count);
    }
}

bool lantern_client_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text,
    uint32_t backfill_depth,
    bool request_parent)
{
    if (!client || !block || !block_root || !parent_root)
    {
        return false;
    }

    LanternRoot block_root_local = *block_root;
    LanternRoot parent_root_local = *parent_root;

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return false;
    }

    struct lantern_pending_block_list *list = &client->pending_blocks;
    bool request_parent_now =
        request_parent || client->sync_state != LANTERN_SYNC_STATE_IDLE;
    if (backfill_depth > LANTERN_MAX_BACKFILL_DEPTH)
    {
        backfill_depth = LANTERN_MAX_BACKFILL_DEPTH;
    }
    struct lantern_pending_block *existing = pending_block_list_find(list, &block_root_local);

    if (existing)
    {
        bool should_request =
            request_parent_now && !existing->parent_requested;
        LanternRoot request_root = existing->parent_root;
        bool parent_cached = pending_block_list_find(list, &request_root) != NULL;
        char peer_copy[PEER_TEXT_BUFFER_LEN];
        peer_copy[0] = '\0';
        if (peer_text && *peer_text)
        {
            (void)lantern_string_copy(peer_copy, sizeof(peer_copy), peer_text);
        }
        if (backfill_depth > existing->backfill_depth)
        {
            existing->backfill_depth = backfill_depth;
        }
        if (peer_text && *peer_text)
        {
            if (existing->peer_text[0] == '\0' || strcmp(existing->peer_text, peer_text) != 0)
            {
                (void)lantern_string_copy(
                    existing->peer_text,
                    sizeof(existing->peer_text),
                    peer_text);
            }
        }
        existing->received_ms = monotonic_millis();
        size_t pending_len = list->length;
        bool parent_requested = existing->parent_requested;
        uint32_t existing_backfill_depth = existing->backfill_depth;
        lantern_client_unlock_pending(client, locked);
        char root_hex[ROOT_HEX_BUFFER_LEN];
        char parent_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&block_root_local, root_hex, sizeof(root_hex));
        format_root_hex(&request_root, parent_hex, sizeof(parent_hex));
        lantern_log_debug(
            "sync",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_text && *peer_text ? peer_text : NULL},
            "pending update root=%s parent=%s depth=%" PRIu32 " pending=%zu parent_cached=%s "
            "parent_requested=%s should_request=%s",
            root_hex[0] ? root_hex : "0x0",
            parent_hex[0] ? parent_hex : "0x0",
            existing_backfill_depth,
            pending_len,
            parent_cached ? "true" : "false",
            parent_requested ? "true" : "false",
            should_request ? "true" : "false");
        if (should_request && !parent_cached
            && existing_backfill_depth < LANTERN_MAX_BACKFILL_DEPTH)
        {
            uint32_t request_depth = existing_backfill_depth + 1u;
            if (try_schedule_blocks_request(
                    client,
                    peer_copy[0] ? peer_copy : NULL,
                    &request_root,
                    request_depth))
            {
                mark_pending_parent_requested(client, &request_root, true);
                lantern_log_info(
                    "backfill",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = peer_copy[0] ? peer_copy : NULL},
                    "slot %" PRIu64 ", request sent, parent %s, peer %s",
                    block->block.slot,
                    parent_hex[0] ? parent_hex : "0x0",
                    peer_copy[0] ? peer_copy : "-");
            }
        }
        return true;
    }

    if (list->length >= LANTERN_PENDING_BLOCK_LIMIT && list->length > 0)
    {
        if (client->sync_state != LANTERN_SYNC_STATE_IDLE)
        {
            size_t shallowest_index = 0u;
            uint32_t shallowest_depth = list->items[0].backfill_depth;
            for (size_t i = 1; i < list->length; ++i)
            {
                if (list->items[i].backfill_depth < shallowest_depth)
                {
                    shallowest_depth = list->items[i].backfill_depth;
                    shallowest_index = i;
                }
            }

            if (backfill_depth <= shallowest_depth)
            {
                char dropped_hex[ROOT_HEX_BUFFER_LEN];
                format_root_hex(&block_root_local, dropped_hex, sizeof(dropped_hex));
                lantern_log_warn(
                    "state",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "pending block queue full while syncing; dropping shallow incoming root=%s depth=%" PRIu32
                    " shallowest_depth=%" PRIu32,
                    dropped_hex[0] ? dropped_hex : "0x0",
                    backfill_depth,
                    shallowest_depth);
                lantern_client_unlock_pending(client, locked);
                return false;
            }

            char evicted_hex[ROOT_HEX_BUFFER_LEN];
            format_root_hex(&list->items[shallowest_index].root, evicted_hex, sizeof(evicted_hex));
            lantern_log_warn(
                "state",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "pending block queue full while syncing; evicting shallow root=%s depth=%" PRIu32
                " for incoming depth=%" PRIu32,
                evicted_hex[0] ? evicted_hex : "0x0",
                shallowest_depth,
                backfill_depth);
            pending_block_list_remove(list, shallowest_index);
        }
        else
        {
            char dropped_hex[ROOT_HEX_BUFFER_LEN];
            format_root_hex(&list->items[0].root, dropped_hex, sizeof(dropped_hex));
            lantern_log_warn(
                "state",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "pending block queue full; dropping oldest root=%s",
                dropped_hex[0] ? dropped_hex : "0x0");
            pending_block_list_remove(list, 0);
        }
    }

    struct lantern_pending_block *entry = pending_block_list_append(
        list,
        block,
        &block_root_local,
        &parent_root_local,
        peer_text,
        backfill_depth);
    if (!entry)
    {
        lantern_client_unlock_pending(client, locked);
        lantern_log_warn(
            "state",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to queue pending block slot=%" PRIu64,
            block->block.slot);
        return false;
    }

    char block_hex[ROOT_HEX_BUFFER_LEN];
    char parent_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(&block_root_local, block_hex, sizeof(block_hex));
    format_root_hex(&parent_root_local, parent_hex, sizeof(parent_hex));

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_text && *peer_text ? peer_text : NULL,
    };

    entry->parent_requested = false;
    bool parent_cached = pending_block_list_find(list, &parent_root_local) != NULL;
    size_t pending_len = list->length;
    uint32_t entry_backfill_depth = entry->backfill_depth;

    lantern_client_unlock_pending(client, locked);

    bool request_scheduled = false;

    if (request_parent_now && !parent_cached
        && entry_backfill_depth < LANTERN_MAX_BACKFILL_DEPTH)
    {
        char peer_copy[PEER_TEXT_BUFFER_LEN];
        peer_copy[0] = '\0';
        if (peer_text && *peer_text)
        {
            (void)lantern_string_copy(peer_copy, sizeof(peer_copy), peer_text);
        }
        uint32_t request_depth = entry_backfill_depth + 1u;
        if (try_schedule_blocks_request(
                client,
                peer_copy[0] ? peer_copy : NULL,
                &parent_root_local,
                request_depth))
        {
            mark_pending_parent_requested(client, &parent_root_local, true);
            request_scheduled = true;
            lantern_log_info(
                "backfill",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_copy[0] ? peer_copy : NULL},
                "slot %" PRIu64 ", request sent, parent %s, peer %s",
                block->block.slot,
                parent_hex[0] ? parent_hex : "0x0",
                peer_copy[0] ? peer_copy : "-");
        }
    }

    lantern_log_info(
        "import",
        &meta,
        "slot %" PRIu64 ", %s, queued, reason: parent_missing, parent %s, requested %s",
        block->block.slot,
        block_hex[0] ? block_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0",
        request_scheduled ? "true" : "false");

    lantern_log_debug(
        "sync",
        &meta,
        "pending enqueue root=%s parent=%s depth=%" PRIu32 " pending=%zu parent_cached=%s "
        "request_parent=%s",
        block_hex[0] ? block_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0",
        entry_backfill_depth,
        pending_len,
        parent_cached ? "true" : "false",
        request_parent_now ? "true" : "false");
    return true;
}


/**
 * Process pending children of a newly imported block.
 *
 * @spec subspecs/forkchoice/store.py - Chain reconstruction
 *
 * After importing a block, checks if any pending blocks can now
 * be imported (because their parent just became available).
 * Iteratively processes any chains of pending blocks.
 *
 * @param client       Client instance
 * @param parent_root  Root of the newly imported parent block
 *
 * @note Thread safety: Acquires pending_lock and state_lock
 */
void lantern_client_process_pending_children(
    struct lantern_client *client,
    const LanternRoot *parent_root)
{
    if (!client || !parent_root)
    {
        return;
    }
    struct pending_child_root_queue parent_queue;
    pending_child_root_queue_init(&parent_queue);
    if (!pending_child_root_queue_append(&parent_queue, parent_root))
    {
        pending_child_root_queue_reset(&parent_queue);
        return;
    }

    LanternRoot current_parent = {0};
    while (pending_child_root_queue_next(&parent_queue, &current_parent))
    {
        bool locked = lantern_client_lock_pending(client);
        if (!locked)
        {
            break;
        }

        size_t pending_count = 0;
        for (size_t i = 0; i < client->pending_blocks.length; ++i)
        {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            if (memcmp(entry->parent_root.bytes, current_parent.bytes, LANTERN_ROOT_SIZE) == 0)
            {
                pending_count += 1u;
            }
        }

        if (pending_count == 0)
        {
            lantern_client_unlock_pending(client, locked);
            continue;
        }

        char parent_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&current_parent, parent_hex, sizeof(parent_hex));
        lantern_log_info(
            "sync",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pending child replay starting parent=%s pending=%zu queue_len=%zu",
            parent_hex[0] ? parent_hex : "0x0",
            pending_count,
            client->pending_blocks.length);

        struct pending_child_replay *replays =
            calloc(pending_count, sizeof(*replays));
        if (!replays)
        {
            lantern_client_unlock_pending(client, locked);
            break;
        }

        size_t replay_count = 0;
        for (size_t i = client->pending_blocks.length; i-- > 0;)
        {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            if (memcmp(entry->parent_root.bytes, current_parent.bytes, LANTERN_ROOT_SIZE) != 0)
            {
                continue;
            }
            if (clone_signed_block(&entry->block, &replays[replay_count].block) != 0)
            {
                lantern_log_warn(
                    "state",
                    &(const struct lantern_log_metadata){.validator = client->node_id},
                    "failed to clone pending child block for replay");
            }
            else
            {
                replays[replay_count].root = entry->root;
                replays[replay_count].slot = entry->block.block.slot;
                replays[replay_count].backfill_depth = entry->backfill_depth;
                replays[replay_count].peer_text[0] = '\0';
                if (entry->peer_text[0])
                {
                    (void)lantern_string_copy(
                        replays[replay_count].peer_text,
                        sizeof(replays[replay_count].peer_text),
                        entry->peer_text);
                }
                replay_count += 1u;
            }
        }

        lantern_client_unlock_pending(client, locked);

        if (replay_count == 0)
        {
            free(replays);
            continue;
        }

        qsort(replays, replay_count, sizeof(*replays), pending_child_replay_compare);

        size_t imported_count = 0;
        size_t queued_children = 0;
        for (size_t i = 0; i < replay_count; ++i)
        {
            struct lantern_log_metadata meta = {
                .validator = client->node_id,
                .peer = replays[i].peer_text[0] ? replays[i].peer_text : NULL,
            };
            bool children_ready = false;
            bool imported = lantern_client_import_block_without_pending_children(
                client,
                &replays[i].block,
                &replays[i].root,
                &meta,
                replays[i].backfill_depth,
                true,
                NULL,
                0,
                &children_ready);
            if (imported)
            {
                imported_count += 1u;
            }
            if (children_ready)
            {
                if (pending_child_root_queue_append(&parent_queue, &replays[i].root))
                {
                    queued_children += 1u;
                }
                else
                {
                    char root_hex[ROOT_HEX_BUFFER_LEN];
                    format_root_hex(&replays[i].root, root_hex, sizeof(root_hex));
                    lantern_log_warn(
                        "sync",
                        &(const struct lantern_log_metadata){.validator = client->node_id},
                        "failed to queue pending child root=%s for iterative replay",
                        root_hex[0] ? root_hex : "0x0");
                }
            }
            lantern_signed_block_with_attestation_reset(&replays[i].block);
        }
        free(replays);

        lantern_log_info(
            "sync",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pending child replay finished parent=%s pending=%zu replayed=%zu imported=%zu queued=%zu",
            parent_hex[0] ? parent_hex : "0x0",
            pending_count,
            replay_count,
            imported_count,
            queued_children);
        lantern_log_debug(
            "sync",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pending children processed parent=%s pending=%zu replayed=%zu imported=%zu queued=%zu",
            parent_hex[0] ? parent_hex : "0x0",
            pending_count,
            replay_count,
            imported_count,
            queued_children);
    }

    pending_child_root_queue_reset(&parent_queue);
}
