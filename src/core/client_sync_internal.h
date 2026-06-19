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
#include "lantern/consensus/state.h"
#include "lantern/support/log.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Constants
 * ============================================================================ */

/**
 * Maximum parent depth for ancestor backfill requests.
 *
 * Keep this independent from the in-memory pending queue limit so a fresh
 * node can backfill deep historical ancestors without requiring a huge
 * pending list in RAM.
 */
#define LANTERN_MAX_BACKFILL_DEPTH 65535u
/** Retry parent fetches if a scheduled request does not complete within this window. */
#define LANTERN_PENDING_PARENT_REQUEST_STALE_MS 15000u
/**
 * Timeout used by outbound blocks-by-root request tracking.
 *
 * Requests that exceed this duration are expired from the active request registry
 * and treated as failed for peer scoring.
 */
#define LANTERN_BLOCKS_REQUEST_TIMEOUT_MS 12000u
/**
 * Hard cap for request tracking entry lifetime after soft timeout.
 *
 * Requests remain marked inflight after the first timeout signal so peer-side
 * stream parsing can still complete without opening parallel replacement
 * streams. If a request never completes, this hard timeout eventually releases
 * the slot.
 */
#define LANTERN_BLOCKS_REQUEST_HARD_TIMEOUT_MS 60000u


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
    bool has_unknown_root; /**< True if rejection is due to unknown checkpoint root */
    LanternRoot unknown_root; /**< Unknown checkpoint root */
    uint64_t unknown_slot; /**< Slot of unknown checkpoint */
    bool should_retry_after_block_import; /**< True if block import may unblock the vote */
    LanternRoot retry_root; /**< Root whose eventual import may unblock validation */
    uint64_t retry_slot; /**< Slot associated with retry_root */
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

bool lantern_client_checkpoint_is_ancestor_locked(
    struct lantern_client *client,
    const LanternCheckpoint *ancestor,
    const LanternCheckpoint *descendant);

bool lantern_client_maybe_start_historical_backfill(
    struct lantern_client *client,
    const char *peer_text,
    const LanternRoot *head_root,
    uint64_t head_slot,
    uint64_t local_head_slot);

bool lantern_client_backfill_process_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    uint32_t depth);

bool lantern_client_backfill_should_drop_gossip(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    const char *context);

void lantern_client_backfill_reset(struct lantern_client *client);
void lantern_client_set_sync_state_logged(
    struct lantern_client *client,
    LanternSyncState new_state,
    const char *reason);

/**
 * Get a state snapshot for a specific block root without attempting replay.
 *
 * This probes only exact local sources:
 * - the current state
 * - fork-choice cached states
 * - exact persisted state snapshots / finalized replay base snapshots
 *
 * It does not reconstruct missing states from a chain of blocks.
 *
 * @note Thread safety: Caller must hold state_lock
 */
const LanternState *lantern_client_state_for_root_local_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    LanternState *scratch,
    bool *out_is_scratch);

/**
 * Get a state snapshot for a specific block root.
 *
 * Returns a pointer to either the client's current state (if it matches the root)
 * or a scratch state populated from storage/replay. When a scratch state is used,
 * the caller must reset it with lantern_state_reset().
 *
 * @param client          Client instance
 * @param root            Block root to resolve
 * @param scratch         Scratch state storage (must be initialized)
 * @param out_is_scratch  Output true if scratch is used
 * @return Pointer to state to use, or NULL if unavailable
 *
 * @note Thread safety: Caller must hold state_lock
 */
const LanternState *lantern_client_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    LanternState *scratch,
    bool *out_is_scratch);

/**
 * Find the first missing block/root on the replay path back toward the finalized anchor.
 *
 * Returns true and populates `out_missing_root` when the ancestry required to
 * reconstruct `root` is not locally connected. Returns false when the ancestry
 * looks locally complete or the root cannot be analyzed.
 *
 * @note Thread safety: Caller must hold state_lock
 */
bool lantern_client_find_missing_state_root_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    LanternRoot *out_missing_root);

/**
 * Determine whether this node should retain an attestation signature locally.
 *
 * The signature is retained when the node is configured as an aggregator.
 * Attestation subnet selection happens at the gossip subscription layer.
 *
 * @note Caller must hold state_lock.
 */
bool lantern_client_should_cache_attestation_signature_locked(
    const struct lantern_client *client,
    const LanternVote *vote);

/**
 * Cache block-body aggregated proofs as known attestation material.
 *
 * Mirrors the block-body proof caching step from the spec's Store.on_block().
 * Caller must hold state_lock.
 */
void lantern_client_cache_block_aggregated_proofs_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block);


/* ============================================================================
 * Pending Vote Functions
 * ============================================================================ */

/**
 * Initialize a pending vote list.
 *
 * @param list  List to initialize
 *
 * @note Thread safety: This function is thread-safe
 */
void pending_vote_list_init(struct lantern_pending_vote_list *list);


/**
 * Reset and free a pending vote list.
 *
 * @param list  List to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void pending_vote_list_reset(struct lantern_pending_vote_list *list);


/**
 * Append a pending gossip vote to the list.
 *
 * @param list      List to append to
 * @param vote      Vote to append
 * @param peer_text Peer ID text (may be NULL)
 * @return Pointer to new entry, or NULL on failure
 *
 * @note Thread safety: Caller must hold state_lock when mutating client-owned lists
 */
struct lantern_pending_vote *pending_vote_list_append(
    struct lantern_pending_vote_list *list,
    const LanternSignedVote *vote,
    const char *peer_text);


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
 * @param backfill_depth Backfill depth of the block
 * @return Pointer to new entry, or NULL on failure
 *
 * @note Thread safety: Caller must hold pending_lock
 */
struct lantern_pending_block *pending_block_list_append(
    struct lantern_pending_block_list *list,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text,
    uint32_t backfill_depth);

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
 * Update sync progress using latest peer status and local slot snapshot.
 *
 * @param client     Client instance
 * @param local_slot Local slot snapshot
 *
 * @note Thread safety: This function acquires status_lock.
 */
void lantern_client_update_sync_progress(
    struct lantern_client *client,
    uint64_t local_slot);


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
 * @param backfill_depth Backfill depth of the block
 * @param allow_historical True to allow importing blocks older than local slot
 * @param raw_block_ssz Optional raw SSZ bytes for the block
 * @param raw_block_ssz_len Length of `raw_block_ssz`
 * @return true if block was imported successfully
 *
 * @note Thread safety: Acquires state_lock and pending_lock
 */
bool lantern_client_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    uint32_t backfill_depth,
    bool allow_historical,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len);

/**
 * Import a block without recursively draining its pending descendants.
 *
 * Used by the iterative pending-child replay path to avoid deep mutual
 * recursion between block import and pending-child processing.
 *
 * @param out_children_ready Optional output set when the block became known
 *                           locally and its pending children should be queued
 *                           for iterative replay.
 */
bool lantern_client_import_block_without_pending_children(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    uint32_t backfill_depth,
    bool allow_historical,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    bool *out_children_ready);

/**
 * Commit a locally built block using a precomputed post-state, then publish it.
 *
 * Used by the validator proposer fast path to avoid re-running the full local
 * state transition before gossip publish.
 */
int lantern_client_commit_and_publish_local_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    LanternState *post_state,
    LanternStore *post_store);

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
 * @param backfill_depth Backfill depth of the block
 * @param allow_historical True to allow importing blocks older than local slot
 * @param raw_block_ssz Optional raw SSZ bytes for the block
 * @param raw_block_ssz_len Length of `raw_block_ssz`
 * @return LANTERN_CLIENT_OK if the block was validated/imported
 * @return LANTERN_CLIENT_ERR_IGNORED if it was duplicate, stale, or deferred
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
    size_t raw_block_ssz_len);


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
 * Replay pending gossip votes after a successful block import.
 *
 * Drains the pending vote queue, retrying each buffered vote once against the
 * updated store. Votes that still fail are discarded.
 */
void lantern_client_replay_pending_gossip_votes(struct lantern_client *client);


/**
 * Handle a block received via gossip.
 *
 * @spec subspecs/networking/gossip.py - gossip protocol
 *
 * @param block    Received block
 * @param from     Peer ID of sender
 * @param raw_block_ssz Raw SSZ bytes for the received block (may be NULL)
 * @param raw_block_ssz_len Length of `raw_block_ssz`
 * @param context  Client instance
 * @return 0 on success
 */
int gossip_block_handler(
    const LanternSignedBlock *block,
    const struct lantern_peer_id *from,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
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
    const struct lantern_peer_id *from,
    const uint8_t *raw_vote_payload,
    size_t raw_vote_payload_len,
    void *context);

/**
 * Handle an aggregated attestation received via gossip.
 *
 * @spec subspecs/networking/gossip.py - aggregation gossip protocol
 *
 * @param attestation Received aggregated attestation
 * @param from        Peer ID of sender
 * @param context     Client instance
 * @return 0 on success
 */
int gossip_aggregated_attestation_handler(
    const LanternSignedAggregatedAttestation *attestation,
    const struct lantern_peer_id *from,
    const uint8_t *raw_attestation_payload,
    size_t raw_attestation_payload_len,
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
 * @param backfill_depth Backfill depth of the block
 * @return true if the block was queued or an existing pending entry was updated
 *
 * @note Thread safety: Acquires pending_lock
 */
bool lantern_client_enqueue_pending_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *parent_root,
    const char *peer_text,
    uint32_t backfill_depth,
    bool request_parent);

/**
 * Attempt to request parents for pending blocks after a blocks_by_root success.
 *
 * Selects an available peer for backfill requests. A provided peer ID is treated
 * as a preference but is not required.
 *
 * @param client    Client instance
 * @param peer_text Peer ID string (may be NULL/empty)
 *
 * @note Thread safety: Thread-safe; acquires pending_lock internally
 */
void lantern_client_request_pending_parent_after_blocks(
    struct lantern_client *client,
    const char *peer_text,
    const LanternRoot *request_root);

/**
 * Attempt to schedule a blocks_by_root request using peer selection.
 *
 * Selects an eligible peer based on status tracking and schedules a request
 * for the provided roots. Returns false if no eligible peer is available or
 * scheduling fails.
 *
 * @param client      Client instance
 * @param peer_text   Preferred peer ID string (may be NULL)
 * @param roots       Block roots to request
 * @param depths      Backfill depth per root (may be NULL)
 * @param root_count  Number of roots
 * @return true if scheduling succeeded, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_try_schedule_blocks_request_batch(
    struct lantern_client *client,
    const char *peer_text,
    const LanternRoot *roots,
    const uint32_t *depths,
    size_t root_count);


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
 * Remove a pending block and any pending descendants rooted under it.
 *
 * @param client  Client instance
 * @param root    Root of the dropped block
 *
 * @note Thread safety: Acquires pending_lock
 */
void lantern_client_pending_remove_branch_by_root(
    struct lantern_client *client,
    const LanternRoot *root);


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
