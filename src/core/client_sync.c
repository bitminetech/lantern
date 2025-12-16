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

    lantern_client_record_block(client, block, NULL, peer_id_text, "gossip");
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
    const LanternRoot *root_to_log = anchor_root;
    if (!root_to_log)
    {
        if (lantern_hash_tree_root_block(block, &computed_root) == 0)
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

    if (lantern_hash_tree_root_state(&client->state, out_state_root) != 0)
    {
        lantern_log_error("forkchoice", meta, "failed to hash anchor state");
        return LANTERN_CLIENT_ERR_RUNTIME;
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
 * 3. Sets fork choice anchor with justified/finalized checkpoints
 * 4. Updates state checkpoint roots to match anchor
 * 5. Persists anchor block to storage
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
            &meta,
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
            &meta,
            "failed to set fork choice anchor");
        return LANTERN_CLIENT_ERR_RUNTIME;
    }
    if (memcmp(
            client->state.latest_justified.root.bytes,
            anchor_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0)
    {
        client->state.latest_justified.root = anchor_root;
        lantern_log_debug(
            "forkchoice",
            &meta,
            "updated justified checkpoint root to anchor");
    }
    if (memcmp(
            client->state.latest_finalized.root.bytes,
            anchor_root.bytes,
            LANTERN_ROOT_SIZE)
        != 0)
    {
        client->state.latest_finalized.root = anchor_root;
        lantern_log_debug(
            "forkchoice",
            &meta,
            "updated finalized checkpoint root to anchor");
    }
    persist_anchor_block(client, &anchor, &anchor_root);
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


/**
 * Enqueue a pending block for later processing.
 *
 * @spec subspecs/forkchoice/store.py - Orphan block handling
 *
 * Queues a block whose parent is not yet known. The block will be
 * imported once its parent arrives via gossip. Does NOT immediately
 * request the parent via reqresp - relies on gossip for normal block
 * propagation.
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
        char dropped_hex[ROOT_HEX_BUFFER_LEN];
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

    char block_hex[ROOT_HEX_BUFFER_LEN];
    char parent_hex[ROOT_HEX_BUFFER_LEN];
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
        LanternSignedBlock replay;
        LanternRoot child_root;
        char peer_copy[PEER_TEXT_BUFFER_LEN];
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
