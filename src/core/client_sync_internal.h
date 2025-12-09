/**
 * @file client_sync_internal.h
 * @brief Internal declarations for block/vote synchronization
 *
 * @spec subspecs/sync/sync.py - synchronization protocol
 *
 * This header contains internal types and function declarations for
 * block and vote synchronization. It is NOT part of the public API.
 *
 * Related files:
 * - client_sync.c: Block/vote synchronization main logic
 * - client_sync_blocks.c: Block import and fork choice
 * - client_sync_votes.c: Vote processing and validation
 * - client_pending.c: Pending block management
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#ifndef LANTERN_CLIENT_SYNC_INTERNAL_H
#define LANTERN_CLIENT_SYNC_INTERNAL_H

#include "lantern/core/client.h"
#include "lantern/consensus/containers.h"
#include "lantern/support/log.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Forward declaration for peer_id_t */
typedef struct peer_id peer_id_t;


/* ============================================================================
 * Constants
 * ============================================================================ */

/** Maximum number of pending blocks to hold */
#define LANTERN_PENDING_BLOCK_LIMIT 256u


/* ============================================================================
 * Internal Types
 * ============================================================================ */

/**
 * Vote rejection information.
 *
 * Used to track why a vote was rejected for debugging.
 */
struct lantern_vote_rejection_info
{
    bool has_reason;       /**< True if rejection reason is set */
    char message[256];     /**< Rejection reason message */
};


/**
 * Persisted block entry for storage operations.
 */
struct lantern_persisted_block
{
    LanternSignedBlock block;  /**< The signed block */
    LanternRoot root;          /**< Block root hash */
};


/**
 * List of persisted blocks.
 */
struct lantern_persisted_block_list
{
    struct lantern_persisted_block *items;  /**< Array of persisted blocks */
    size_t length;                          /**< Number of items in list */
    size_t capacity;                        /**< Allocated capacity */
};


/* ============================================================================
 * Vote Functions
 * ============================================================================ */

/**
 * Set vote rejection reason with printf-style formatting.
 *
 * @param info  Rejection info structure to populate
 * @param fmt   Format string
 * @param ...   Format arguments
 *
 * @note Thread safety: This function is thread-safe
 */
void lantern_vote_rejection_set(struct lantern_vote_rejection_info *info, const char *fmt, ...);


/**
 * Get current slot from fork choice.
 *
 * @param client    Client instance
 * @param out_slot  Output slot
 * @return true on success, false on error
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_current_slot(const struct lantern_client *client, uint64_t *out_slot);


/**
 * Check if a block root is known in fork choice.
 *
 * @param client    Client instance
 * @param root      Root to check
 * @param out_slot  Output slot (may be NULL)
 * @return true if known, false otherwise
 *
 * @note Thread safety: Caller must hold state_lock
 */
bool lantern_client_block_known_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    uint64_t *out_slot);


/* ============================================================================
 * Pending Block Functions
 * ============================================================================ */

/**
 * Initialize a pending block list.
 *
 * @param list  List to initialize
 *
 * @note Thread safety: This function is thread-safe
 */
void pending_block_list_init(struct lantern_pending_block_list *list);


/**
 * Reset and free a pending block list.
 *
 * @param list  List to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void pending_block_list_reset(struct lantern_pending_block_list *list);


/**
 * Find a pending block by root.
 *
 * @param list  List to search
 * @param root  Root to find
 * @return Pointer to entry if found, NULL otherwise
 *
 * @note Thread safety: Caller must hold pending_lock
 */
struct lantern_pending_block *pending_block_list_find(
    struct lantern_pending_block_list *list,
    const LanternRoot *root);


/**
 * Remove a pending block by index.
 *
 * @param list   List to modify
 * @param index  Index to remove
 *
 * @note Thread safety: Caller must hold pending_lock
 */
void pending_block_list_remove(struct lantern_pending_block_list *list, size_t index);


/**
 * Append a pending block to the list.
 *
 * @param list         List to append to
 * @param block        Block to append
 * @param block_root   Root of the block
 * @param parent_root  Root of the parent block
 * @param peer_text    Peer ID text (may be NULL)
 * @return Pointer to new entry, or NULL on failure
 *
 * @note Thread safety: Caller must hold pending_lock
 */
struct lantern_pending_block *pending_block_list_append(
    struct lantern_pending_block_list *list,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text);


/**
 * Initialize a persisted block list.
 *
 * @param list  List to initialize
 *
 * @note Thread safety: This function is thread-safe
 */
void persisted_block_list_init(struct lantern_persisted_block_list *list);


/**
 * Reset and free a persisted block list.
 *
 * @param list  List to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void persisted_block_list_reset(struct lantern_persisted_block_list *list);


/**
 * Append a persisted block to the list.
 *
 * @param list   List to append to
 * @param block  Block to append
 * @param root   Root of the block
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int persisted_block_list_append(
    struct lantern_persisted_block_list *list,
    const LanternSignedBlock *block,
    const LanternRoot *root);


/**
 * Clone a signed block.
 *
 * @param source  Source block to clone
 * @param dest    Destination block (will be initialized)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int clone_signed_block(const LanternSignedBlock *source, LanternSignedBlock *dest);


/* ============================================================================
 * Block Sync Functions
 * ============================================================================ */

/**
 * Count enabled local validators.
 *
 * @spec subspecs/duties/duties.py - validator management
 *
 * @param client  Client instance
 * @return Number of enabled validators
 *
 * @note Thread safety: Acquires validator_lock
 */
size_t lantern_client_enabled_validator_count(struct lantern_client *client);


/**
 * Validate vote constraints against fork choice.
 *
 * @spec subspecs/attestation/attestation.py - vote validation
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
    struct lantern_vote_rejection_info *out_rejection);


/**
 * Import a block into the client state and fork choice.
 *
 * @spec subspecs/block/block.py - block processing
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
    const struct lantern_log_metadata *meta);


/**
 * Record a received block and attempt import.
 *
 * @spec subspecs/sync/sync.py - block synchronization
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
    const char *context);


/**
 * Record and process a received vote.
 *
 * @spec subspecs/attestation/attestation.py - vote processing
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
    const char *peer_text);


/**
 * Handle a block received via gossip.
 *
 * @spec subspecs/networking/gossip.py - gossip protocol
 *
 * @param block    Received block
 * @param from     Peer ID of sender
 * @param context  Client instance
 * @return 0 on success
 */
int gossip_block_handler(
    const LanternSignedBlock *block,
    const peer_id_t *from,
    void *context);


/**
 * Handle a vote received via gossip.
 *
 * @spec subspecs/networking/gossip.py - gossip protocol
 *
 * @param vote     Received vote
 * @param from     Peer ID of sender
 * @param context  Client instance
 * @return 0 on success
 */
int gossip_vote_handler(
    const LanternSignedVote *vote,
    const peer_id_t *from,
    void *context);


/**
 * Initialize fork choice from genesis state.
 *
 * @spec subspecs/fork_choice/fork_choice.py - fork choice initialization
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Should be called during initialization
 */
int initialize_fork_choice(struct lantern_client *client);


/**
 * Restore persisted blocks from storage into fork choice.
 *
 * @spec subspecs/storage/storage.py - block persistence
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Should be called during initialization
 */
int restore_persisted_blocks(struct lantern_client *client);


/**
 * Refresh state validator pubkeys from genesis registry.
 *
 * @spec subspecs/containers/state/genesis.py - validator state
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Acquires validator_lock
 */
int lantern_client_refresh_state_validators(struct lantern_client *client);


/**
 * Enqueue a pending block for later processing.
 *
 * @spec subspecs/sync/sync.py - pending block management
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
    const char *peer_text);


/**
 * Remove a pending block by root.
 *
 * @param client  Client instance
 * @param root    Block root to remove
 *
 * @note Thread safety: Acquires pending_lock
 */
void lantern_client_pending_remove_by_root(struct lantern_client *client, const LanternRoot *root);


/**
 * Process pending children of a newly imported block.
 *
 * @spec subspecs/sync/sync.py - pending block resolution
 *
 * @param client       Client instance
 * @param parent_root  Root of the newly imported parent block
 *
 * @note Thread safety: Acquires pending_lock and state_lock
 */
void lantern_client_process_pending_children(struct lantern_client *client, const LanternRoot *parent_root);


/**
 * Persist anchor block to storage.
 *
 * @spec subspecs/storage/storage.py - block persistence
 *
 * @param client        Client instance
 * @param anchor_block  Anchor block to persist
 * @param anchor_root   Anchor block root
 *
 * @note Thread safety: Thread-safe
 */
void persist_anchor_block(struct lantern_client *client, const LanternBlock *anchor_block, const LanternRoot *anchor_root);


#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CLIENT_SYNC_INTERNAL_H */
