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

#include "peer_id/peer_id.h"

#include "lantern/consensus/containers.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
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
    VALIDATOR_PUBKEY_HEX_BUFFER_LEN = (LANTERN_VALIDATOR_PUBKEY_SIZE * 2u) + 3u,
};


/* ============================================================================
 * Validator Record Access
 * ============================================================================ */

/**
 * Get validator record from genesis registry.
 *
 * @spec subspecs/containers/validator.py - Validator container
 *
 * Retrieves a validator record from the genesis registry by index.
 * The registry is populated during genesis initialization and remains
 * immutable after that.
 *
 * @param client        Client instance
 * @param validator_id  Validator index
 * @return Validator record or NULL if not found
 *
 * @note Thread safety: Assumes registry is immutable after init
 */
const struct lantern_validator_record *lantern_client_get_validator_record(
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
static const char *peer_id_to_text(const peer_id_t *from, char *out, size_t out_len)
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

    if (peer_id_to_string(from, PEER_ID_FMT_BASE58_LEGACY, out, out_len) < 0)
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
    const peer_id_t *from,
    void *context)
{
    if (!block || !context)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;

    char peer_text[PEER_TEXT_BUFFER_LEN];
    const char *peer_id_text = peer_id_to_text(from, peer_text, sizeof(peer_text));

    lantern_client_record_block(client, block, NULL, peer_id_text, "gossip", 0, false);
    return LANTERN_CLIENT_OK;
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
    const peer_id_t *from,
    void *context)
{
    if (!vote || !context)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    struct lantern_client *client = context;

    char peer_text[PEER_TEXT_BUFFER_LEN];
    const char *peer_id_text = peer_id_to_text(from, peer_text, sizeof(peer_text));

    lantern_client_note_vote_delivery(client, peer_id_text, vote);
    lantern_client_record_vote(client, vote, peer_id_text);
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
    LanternBlock *block = &stored_anchor.message.block;
    block->slot = anchor_block->slot;
    block->proposer_index = anchor_block->proposer_index;
    block->parent_root = anchor_block->parent_root;
    block->state_root = anchor_block->state_root;

    LanternRoot computed_root;
    const LanternRoot *root_for_vote = anchor_root;
    const LanternRoot *root_to_log = anchor_root;
    if (!root_for_vote)
    {
        if (lantern_hash_tree_root_block(block, &computed_root) == 0)
        {
            root_for_vote = &computed_root;
            root_to_log = root_for_vote;
        }
    }

    if (root_for_vote)
    {
        LanternVote *vote = &stored_anchor.message.proposer_attestation;
        LanternCheckpoint anchor_checkpoint = {
            .root = *root_for_vote,
            .slot = block->slot,
        };
        vote->validator_id = block->proposer_index;
        vote->slot = block->slot;
        vote->head = anchor_checkpoint;
        vote->target = anchor_checkpoint;
        vote->source = anchor_checkpoint;
    }
    char root_hex[ROOT_HEX_BUFFER_LEN];
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
 * @brief Compute genesis anchor roots for fork choice initialization.
 *
 * @param client             Client instance
 * @param meta               Logging metadata
 * @param out_state_root     Output computed state root
 * @param out_anchor_header  Output anchor header (state_root updated)
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
    LanternBlockHeader *out_anchor_header,
    LanternRoot *out_anchor_root)
{
    if (!client || !meta || !out_state_root || !out_anchor_header || !out_anchor_root)
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

    if (lantern_hash_tree_root_state(state_for_hash, out_state_root) != 0)
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

    *out_anchor_header = client->state.latest_block_header;
    out_anchor_header->state_root = *out_state_root;

    if (lantern_hash_tree_root_block_header(out_anchor_header, out_anchor_root) != 0)
    {
        lantern_log_error("forkchoice", meta, "failed to hash anchor block header");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }

    return LANTERN_CLIENT_OK;
}


/**
 * @brief Log genesis anchor roots for debugging mismatches.
 *
 * @param meta         Logging metadata
 * @param anchor_root  Anchor block root
 * @param state_root   Anchor state root
 * @param body_root    Anchor body root
 * @param slot         Anchor slot
 *
 * @note Thread safety: This function is thread-safe
 */
static void log_genesis_anchor_roots(
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
        "genesis anchor_root=%s state_root=%s body_root=%s slot=%" PRIu64,
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
 * 2. Computes anchor block header with actual state_root (not zero)
 * 3. Sets fork choice anchor with anchor checkpoints
 * 4. Persists anchor block to storage
 *
 * According to leanSpec's Store.get_forkchoice_store, the anchor block
 * used for fork choice MUST have state_root = hash_tree_root(state).
 * This is different from the state's latest_block_header which starts
 * with state_root = ZERO.
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
    LanternBlockHeader anchor_header;
    LanternRoot anchor_root;
    int root_rc = compute_fork_choice_anchor_roots(
        client,
        &meta,
        &anchor_state_root,
        &anchor_header,
        &anchor_root);
    if (root_rc != LANTERN_CLIENT_OK)
    {
        return root_rc;
    }

    log_genesis_anchor_roots(
        &meta,
        &anchor_root,
        &anchor_state_root,
        &anchor_header.body_root,
        anchor_header.slot);

    LanternBlock anchor;
    memset(&anchor, 0, sizeof(anchor));
    anchor.slot = client->state.latest_block_header.slot;
    anchor.proposer_index = client->state.latest_block_header.proposer_index;
    anchor.parent_root = client->state.latest_block_header.parent_root;
    anchor.state_root = anchor_state_root;
    lantern_block_body_init(&anchor.body);

    LanternCheckpoint anchor_checkpoint;
    anchor_checkpoint.root = anchor_root;
    anchor_checkpoint.slot = anchor.slot;

    /*
     * Seed fork-choice with anchor_checkpoint (whose root matches the anchor
     * block that set_anchor registers in the tree).  This guarantees
     * lmd_ghost_compute can always find its start_root during block restore.
     *
     * Real persisted checkpoints are synced to the store AFTER
     * restore_persisted_blocks() via lantern_fork_choice_restore_checkpoints().
     */
    if (lantern_fork_choice_set_anchor(
            &client->fork_choice,
            &anchor,
            &anchor_checkpoint,
            &anchor_checkpoint,
            &anchor_root)
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
        if (lantern_storage_store_state_for_root(
                client->data_dir,
                &anchor_root,
                &client->state)
            != 0)
        {
            lantern_log_warn(
                "storage",
                &meta,
                "failed to persist anchor state");
        }
    }
    lantern_block_body_reset(&anchor.body);
    lantern_state_attach_fork_choice(&client->state, &client->fork_choice);
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
 * @spec subspecs/forkchoice/store.py - Block restoration
 *
 * Loads all persisted blocks from storage, sorts them by slot,
 * and adds them to fork choice. This allows the client to resume
 * from a previous state after restart.
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

    for (size_t i = 0; i < list.length; ++i)
    {
        const struct lantern_persisted_block *entry = &list.items[i];
        const LanternBlock *block = &entry->block.message.block;
        const LanternVote *vote = &entry->block.message.proposer_attestation;
        LanternSignedVote persisted_proposer;
        const LanternSignedVote *proposer_ptr = NULL;
        if (vote->slot == block->slot && vote->validator_id == block->proposer_index)
        {
            memset(&persisted_proposer, 0, sizeof(persisted_proposer));
            persisted_proposer.data = *vote;
            persisted_proposer.signature = entry->block.signatures.proposer_signature;
            proposer_ptr = &persisted_proposer;
        }
        if (lantern_fork_choice_add_block(
                &client->fork_choice,
                block,
                proposer_ptr,
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
    if (lantern_fork_choice_restore_checkpoints(
            &client->fork_choice,
            &client->state.latest_justified,
            &client->state.latest_finalized)
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
 * @brief Update a registry record from a state pubkey fallback.
 *
 * Copies the pubkey bytes into the registry record and refreshes the
 * cached hex string when possible.
 *
 * @param record  Registry record to update
 * @param pubkey  Pubkey bytes (LANTERN_VALIDATOR_PUBKEY_SIZE bytes)
 * @param meta    Logging metadata
 * @param index   Validator index (for logging)
 *
 * @note Thread safety: Caller must ensure exclusive access during initialization
 */
static void update_registry_record_from_state_pubkey(
    struct lantern_validator_record *record,
    const uint8_t *pubkey,
    const struct lantern_log_metadata *meta,
    size_t index)
{
    if (!record || !pubkey || !meta)
    {
        return;
    }

    memcpy(record->pubkey_bytes, pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE);
    record->has_pubkey_bytes = true;

    char hex[VALIDATOR_PUBKEY_HEX_BUFFER_LEN];
    if (lantern_bytes_to_hex(pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE, hex, sizeof(hex), 1) != 0)
    {
        return;
    }

    char *dup = lantern_string_duplicate(hex);
    if (!dup)
    {
        lantern_log_warn(
            "client",
            meta,
            "failed to allocate pubkey hex for validator=%zu",
            index);
        return;
    }

    free(record->pubkey_hex);
    record->pubkey_hex = dup;
}


/**
 * @brief Populate a packed validator pubkey buffer from registry/state sources.
 *
 * Writes a packed array of validator pubkeys into `packed` and opportunistically
 * fills missing registry pubkeys from the state.
 *
 * @param client              Client instance
 * @param registry            Validator registry (must have records)
 * @param state_count         Validator count in state
 * @param packed              Output packed buffer (count * LANTERN_VALIDATOR_PUBKEY_SIZE bytes)
 * @param count               Number of validators to write
 * @param meta                Logging metadata
 * @param out_registry_used   Output count of pubkeys sourced from registry
 * @param out_state_used      Output count of pubkeys sourced from state fallback
 * @param out_missing_pubkeys Output count of missing pubkeys
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL
 *
 * @note Thread safety: Caller must ensure exclusive access during initialization
 */
static int populate_validator_pubkeys(
    struct lantern_client *client,
    struct lantern_validator_registry *registry,
    size_t state_count,
    uint8_t *packed,
    size_t count,
    const struct lantern_log_metadata *meta,
    size_t *out_registry_used,
    size_t *out_state_used,
    size_t *out_missing_pubkeys)
{
    if (!client || !registry || !registry->records || !packed || !meta
        || !out_registry_used || !out_state_used || !out_missing_pubkeys)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    *out_registry_used = 0;
    *out_state_used = 0;
    *out_missing_pubkeys = 0;

    for (size_t i = 0; i < count; ++i)
    {
        struct lantern_validator_record *record = &registry->records[i];
        const uint8_t *registry_pub = NULL;
        if (record->has_pubkey_bytes && !lantern_validator_pubkey_is_zero(record->pubkey_bytes))
        {
            registry_pub = record->pubkey_bytes;
        }

        const uint8_t *state_pub = NULL;
        if (state_count > i)
        {
            state_pub = lantern_state_validator_pubkey(&client->state, i);
        }
        if (state_pub && lantern_validator_pubkey_is_zero(state_pub))
        {
            state_pub = NULL;
        }

        const uint8_t *chosen = registry_pub ? registry_pub : state_pub;
        size_t offset = i * LANTERN_VALIDATOR_PUBKEY_SIZE;
        if (chosen)
        {
            memcpy(packed + offset, chosen, LANTERN_VALIDATOR_PUBKEY_SIZE);
            if (!registry_pub && state_pub)
            {
                update_registry_record_from_state_pubkey(record, state_pub, meta, i);
                ++(*out_state_used);
            }
            else if (registry_pub)
            {
                ++(*out_registry_used);
            }
        }
        else
        {
            memset(packed + offset, 0, LANTERN_VALIDATOR_PUBKEY_SIZE);
            ++(*out_missing_pubkeys);
        }
    }

    return LANTERN_CLIENT_OK;
}


/**
 * Refresh state validator pubkeys from genesis registry.
 *
 * @spec subspecs/containers/validator.py - Validator pubkey management
 *
 * Synchronizes validator public keys between the genesis registry
 * and the state. Merges keys from both sources, preferring genesis
 * registry when available, falling back to state pubkeys otherwise.
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

    bool have_registry = registry->records && registry_count > 0;
    if (!have_registry)
    {
        if (state_count == 0)
        {
            if (lantern_state_set_validator_pubkeys(&client->state, NULL, 0) != 0)
            {
                return LANTERN_CLIENT_ERR_RUNTIME;
            }
            return LANTERN_CLIENT_OK;
        }
        lantern_log_info(
            "client",
            &meta,
            "validator registry missing; retaining existing state pubkeys count=%zu",
            state_count);
        return LANTERN_CLIENT_OK;
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
    if (count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    size_t total_bytes = count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *packed = malloc(total_bytes);
    if (!packed)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    size_t registry_used = 0;
    size_t state_used = 0;
    size_t missing_pubkeys = 0;
    int pack_rc = populate_validator_pubkeys(
        client,
        registry,
        state_count,
        packed,
        count,
        &meta,
        &registry_used,
        &state_used,
        &missing_pubkeys);
    if (pack_rc != LANTERN_CLIENT_OK)
    {
        free(packed);
        return pack_rc;
    }
    int rc = lantern_state_set_validator_pubkeys(&client->state, packed, count);
    free(packed);
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
        "refreshed validator pubkeys count=%zu registry=%zu state_fallback=%zu missing=%zu "
        "local_validators=%zu enabled=%zu",
        count,
        registry_used,
        state_used,
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
    strncpy(entry->peer_id, peer_id, sizeof(entry->peer_id) - 1u);
    entry->peer_id[sizeof(entry->peer_id) - 1u] = '\0';
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
                    "reqresp",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = request->peer_id[0] ? request->peer_id : NULL},
                    "blocks_by_root request timed out request_id=%" PRIu64
                    " age_ms=%" PRIu64 " keeping inflight slot until completion",
                    request->request_id,
                    age_ms);
                i += 1u;
                continue;
            }

            lantern_log_warn(
                "reqresp",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = request->peer_id[0] ? request->peer_id : NULL},
                "blocks_by_root request hard timeout request_id=%" PRIu64
                " age_ms=%" PRIu64 " releasing inflight slot",
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
 * synced, it requests the missing parent via reqresp. In IDLE, it
 * relies on gossip for normal block propagation.
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
        return false;
    }
    if (root_count > LANTERN_MAX_REQUEST_BLOCKS)
    {
        return false;
    }
    if (client->debug_disable_block_requests)
    {
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
            return false;
        }
        if (depths && depths[i] > LANTERN_MAX_BACKFILL_DEPTH)
        {
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
                    "reqresp",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = peer_text},
                    "blocks_by_root requested peer not eligible connected=%s inflight=%" PRIu32
                    " failures=%" PRIu32 " has_status=%s status_age_ms=%" PRIu64,
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
                    "reqresp",
                    &(const struct lantern_log_metadata){
                        .validator = client->node_id,
                        .peer = peer_text},
                    "blocks_by_root preferred peer busy inflight=%" PRIu32
                    " max=%" PRIu32 " roots=%zu; deferring request",
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
            "reqresp",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "blocks_by_root request skipped: no eligible peers roots=%zu connected=%zu status_entries=%zu "
            "connected_entries=%zu has_status=%zu fresh=%zu stale=%zu inflight_full=%zu",
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
    strncpy(selected_peer, entry->peer_id, copy_cap - 1u);
    selected_peer[copy_cap - 1u] = '\0';
    uint64_t request_id = 0u;
    if (!reserve_active_blocks_request_locked(
            client,
            selected_peer,
            now_ms,
            LANTERN_BLOCKS_REQUEST_TIMEOUT_MS,
            &request_id))
    {
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = selected_peer[0] ? selected_peer : NULL},
            "blocks_by_root request skipped: unable to reserve request tracking entry");
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
            depths,
            root_count,
            request_id)
        != 0)
    {
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = selected_peer},
            "blocks_by_root request scheduling failed roots=%zu",
            root_count);
        lantern_client_on_blocks_request_complete_batch_with_id(
            client,
            request_id,
            selected_peer,
            roots,
            root_count,
            LANTERN_BLOCKS_REQUEST_ABORTED);
        return false;
    }

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

    if (candidate_count == 0 && peer_text && *peer_text)
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

void lantern_client_enqueue_pending_block(
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
        return;
    }

    LanternRoot block_root_local = *block_root;
    LanternRoot parent_root_local = *parent_root;

    bool locked = lantern_client_lock_pending(client);
    if (!locked)
    {
        return;
    }

    struct lantern_pending_block_list *list = &client->pending_blocks;
    bool request_parent_now =
        request_parent || client->sync_state != LANTERN_SYNC_STATE_IDLE;
    bool allow_parent_requests = client->sync_state != LANTERN_SYNC_STATE_IDLE;
    if (backfill_depth > LANTERN_MAX_BACKFILL_DEPTH)
    {
        backfill_depth = LANTERN_MAX_BACKFILL_DEPTH;
    }
    struct lantern_pending_block *existing = pending_block_list_find(list, &block_root_local);

    if (existing)
    {
        bool should_request =
            allow_parent_requests && request_parent_now && !existing->parent_requested;
        LanternRoot request_root = existing->parent_root;
        bool parent_cached = pending_block_list_find(list, &request_root) != NULL;
        char peer_copy[PEER_TEXT_BUFFER_LEN];
        peer_copy[0] = '\0';
        if (peer_text && *peer_text)
        {
            strncpy(peer_copy, peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
        }
        if (backfill_depth < existing->backfill_depth)
        {
            existing->backfill_depth = backfill_depth;
        }
        if (peer_text && *peer_text)
        {
            if (existing->peer_text[0] == '\0' || strcmp(existing->peer_text, peer_text) != 0)
            {
                strncpy(existing->peer_text, peer_text, sizeof(existing->peer_text) - 1u);
                existing->peer_text[sizeof(existing->peer_text) - 1u] = '\0';
            }
        }
        existing->received_ms = monotonic_millis();
        size_t pending_len = list->length;
        bool parent_requested = existing->parent_requested;
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
            existing->backfill_depth,
            pending_len,
            parent_cached ? "true" : "false",
            parent_requested ? "true" : "false",
            should_request ? "true" : "false");
        if (should_request && !parent_cached
            && existing->backfill_depth < LANTERN_MAX_BACKFILL_DEPTH)
        {
            uint32_t request_depth = existing->backfill_depth + 1u;
        if (try_schedule_blocks_request(
                client,
                peer_copy[0] ? peer_copy : NULL,
                &request_root,
                request_depth))
            {
                mark_pending_parent_requested(client, &request_root, true);
            }
        }
        return;
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
                return;
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
            block->message.block.slot);
        return;
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

    lantern_client_unlock_pending(client, locked);

    if (client->sync_in_progress)
    {
        lantern_log_debug(
            "state",
            &meta,
            "queued block slot=%" PRIu64 " root=%s waiting for parent=%s (via gossip)",
            block->message.block.slot,
            block_hex[0] ? block_hex : "0x0",
            parent_hex[0] ? parent_hex : "0x0");
    }
    else
    {
        lantern_log_info(
            "state",
            &meta,
            "queued block slot=%" PRIu64 " root=%s waiting for parent=%s (via gossip)",
            block->message.block.slot,
            block_hex[0] ? block_hex : "0x0",
            parent_hex[0] ? parent_hex : "0x0");
    }

    if (allow_parent_requests && request_parent_now && !parent_cached
        && entry->backfill_depth < LANTERN_MAX_BACKFILL_DEPTH)
    {
        char peer_copy[PEER_TEXT_BUFFER_LEN];
        peer_copy[0] = '\0';
        if (peer_text && *peer_text)
        {
            strncpy(peer_copy, peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
        }
        uint32_t request_depth = entry->backfill_depth + 1u;
        if (try_schedule_blocks_request(
                client,
                peer_copy[0] ? peer_copy : NULL,
                &parent_root_local,
                request_depth))
        {
            mark_pending_parent_requested(client, &parent_root_local, true);
        }
    }

    lantern_log_debug(
        "sync",
        &meta,
        "pending enqueue root=%s parent=%s depth=%" PRIu32 " pending=%zu parent_cached=%s "
        "request_parent=%s",
        block_hex[0] ? block_hex : "0x0",
        parent_hex[0] ? parent_hex : "0x0",
        entry->backfill_depth,
        pending_len,
        parent_cached ? "true" : "false",
        (allow_parent_requests && request_parent_now) ? "true" : "false");
}


/**
 * Process pending children of a newly imported block.
 *
 * @spec subspecs/forkchoice/store.py - Chain reconstruction
 *
 * After importing a block, checks if any pending blocks can now
 * be imported (because their parent just became available).
 * Recursively processes any chains of pending blocks.
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
    while (true)
    {
        bool locked = lantern_client_lock_pending(client);
        if (!locked)
        {
            return;
        }

        size_t pending_count = 0;
        for (size_t i = 0; i < client->pending_blocks.length; ++i)
        {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            if (memcmp(entry->parent_root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) == 0)
            {
                pending_count += 1u;
            }
        }

        if (pending_count == 0)
        {
            lantern_client_unlock_pending(client, locked);
            break;
        }

        struct pending_child_replay *replays =
            calloc(pending_count, sizeof(*replays));
        if (!replays)
        {
            lantern_client_unlock_pending(client, locked);
            return;
        }

        size_t replay_count = 0;
        for (size_t i = client->pending_blocks.length; i-- > 0;)
        {
            struct lantern_pending_block *entry = &client->pending_blocks.items[i];
            if (memcmp(entry->parent_root.bytes, parent_root->bytes, LANTERN_ROOT_SIZE) != 0)
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
                replays[replay_count].slot = entry->block.message.block.slot;
                replays[replay_count].backfill_depth = entry->backfill_depth;
                replays[replay_count].peer_text[0] = '\0';
                if (entry->peer_text[0])
                {
                    strncpy(
                        replays[replay_count].peer_text,
                        entry->peer_text,
                        sizeof(replays[replay_count].peer_text) - 1u);
                    replays[replay_count]
                        .peer_text[sizeof(replays[replay_count].peer_text) - 1u] = '\0';
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
        for (size_t i = 0; i < replay_count; ++i)
        {
            struct lantern_log_metadata meta = {
                .validator = client->node_id,
                .peer = replays[i].peer_text[0] ? replays[i].peer_text : NULL,
            };
            bool imported = lantern_client_import_block(
                client,
                &replays[i].block,
                &replays[i].root,
                &meta,
                replays[i].backfill_depth,
                true);
            if (imported)
            {
                imported_count += 1u;
            }
            lantern_signed_block_with_attestation_reset(&replays[i].block);
        }
        free(replays);

        char parent_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(parent_root, parent_hex, sizeof(parent_hex));
        lantern_log_debug(
            "sync",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "pending children processed parent=%s pending=%zu replayed=%zu imported=%zu",
            parent_hex[0] ? parent_hex : "0x0",
            pending_count,
            replay_count,
            imported_count);

        if (imported_count == 0)
        {
            break;
        }
    }
}
