/**
 * @file client_internal.h
 * @brief Internal declarations for the client module
 *
 * This header contains internal types, constants, and function declarations
 * shared across client implementation files. It is NOT part of the public API.
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#ifndef LANTERN_CLIENT_INTERNAL_H
#define LANTERN_CLIENT_INTERNAL_H

#include "lantern/core/client.h"
#include "lantern/consensus/containers.h"
#include "lantern/http/server.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/support/log.h"

#include <libp2p/events.h>

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif


/* ============================================================================
 * Constants
 * ============================================================================ */

/** Peer dial interval in seconds */
#define LANTERN_PEER_DIAL_INTERVAL_SECONDS 5u

/** Base backoff for blocks request in milliseconds */
#define LANTERN_BLOCKS_REQUEST_BACKOFF_BASE_MS 5000u

/** Maximum backoff for blocks request in milliseconds */
#define LANTERN_BLOCKS_REQUEST_BACKOFF_MAX_MS 300000u

/** Maximum consecutive failures before max backoff */
#define LANTERN_BLOCKS_REQUEST_BACKOFF_MAX_FAILURES 8u

/** Minimum poll interval for blocks requests in milliseconds */
#define LANTERN_BLOCKS_REQUEST_MIN_POLL_MS 2000u

/** Maximum number of pending blocks to hold */
#define LANTERN_PENDING_BLOCK_LIMIT 256u

/** Peer dial timeout in milliseconds */
#define LANTERN_PEER_DIAL_TIMEOUT_MS 4000


/* ============================================================================
 * Internal Types
 * ============================================================================ */

/**
 * Outcome of a blocks request operation.
 */
enum lantern_blocks_request_outcome
{
    LANTERN_BLOCKS_REQUEST_SUCCESS = 0,
    LANTERN_BLOCKS_REQUEST_FAILED,
    LANTERN_BLOCKS_REQUEST_ABORTED
};


/**
 * Peer status tracking entry.
 *
 * Tracks the status of a connected peer including their latest status
 * message and request state.
 */
struct lantern_peer_status_entry
{
    char peer_id[128];                    /**< Peer ID string */
    LanternStatusMessage status;          /**< Latest status message from peer */
    bool has_status;                      /**< True if status has been received */
    bool requested_head;                  /**< True if head block was requested */
    bool status_request_inflight;         /**< True if status request is pending */
    uint64_t last_blocks_request_ms;      /**< Timestamp of last blocks request */
    uint32_t consecutive_blocks_failures; /**< Count of consecutive request failures */
    uint32_t outstanding_status_requests; /**< Number of outstanding status requests */
};


/**
 * Block request context for async operations.
 */
struct block_request_ctx
{
    struct lantern_client *client;  /**< Client instance */
    peer_id_t peer_id;              /**< Peer ID structure */
    char peer_text[128];            /**< Peer ID as text */
    LanternRoot root;               /**< Block root being requested */
    const char *protocol_id;        /**< Protocol ID string */
    bool using_legacy;              /**< True if using legacy protocol */
};


/**
 * Block request worker thread arguments.
 */
struct block_request_worker_args
{
    struct block_request_ctx *ctx;  /**< Request context */
    libp2p_stream_t *stream;        /**< libp2p stream */
};


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
 * Utility Functions
 * ============================================================================ */

/**
 * Get monotonic time in milliseconds.
 *
 * @return Monotonic milliseconds since some unspecified epoch
 *
 * @note Thread safety: This function is thread-safe
 */
uint64_t monotonic_millis(void);


/**
 * Get current wall clock time in seconds.
 *
 * @return Current time as Unix timestamp
 *
 * @note Thread safety: This function is thread-safe
 */
uint64_t validator_wall_time_now_seconds(void);


/**
 * Sleep for specified milliseconds.
 *
 * @param ms  Milliseconds to sleep
 *
 * @note Thread safety: This function is thread-safe
 */
void validator_sleep_ms(uint32_t ms);


/**
 * Calculate backoff time for blocks request based on failure count.
 *
 * @param failures  Number of consecutive failures
 * @return Backoff time in milliseconds
 *
 * @note Thread safety: This function is thread-safe
 */
uint64_t blocks_request_backoff_ms(uint32_t failures);


/**
 * Format a root hash as hex string.
 *
 * Produces output like "0x1234...abcd" with prefix.
 *
 * @param root     Root to format (may be NULL)
 * @param out      Output buffer
 * @param out_len  Size of output buffer
 *
 * @note Thread safety: This function is thread-safe
 */
void format_root_hex(const LanternRoot *root, char *out, size_t out_len);


/**
 * Check if a root is all zeros.
 *
 * @param root  Root to check
 * @return true if root is NULL or all zero bytes
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_root_is_zero(const LanternRoot *root);


/**
 * Check if validator pubkey bytes are all zeros.
 *
 * @param pubkey  Pubkey bytes to check (LANTERN_VALIDATOR_PUBKEY_SIZE bytes)
 * @return true if pubkey is NULL or all zero bytes
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_validator_pubkey_is_zero(const uint8_t *pubkey);


/**
 * Set an owned string field, freeing previous value.
 *
 * @param dest   Pointer to destination string pointer
 * @param value  Value to copy
 * @return 0 on success, -1 on error
 *
 * @note Thread safety: This function is thread-safe
 */
int set_owned_string(char **dest, const char *value);


/**
 * Read file contents and trim whitespace.
 *
 * @param path      File path
 * @param out_text  Output buffer (caller owns)
 * @return 0 on success, -1 on error
 *
 * @note Thread safety: This function is thread-safe
 */
int read_trimmed_file(const char *path, char **out_text);


/**
 * Load node key bytes from options.
 *
 * Reads from either node_key_hex or node_key_path.
 *
 * @param options  Client options
 * @param out_key  Output buffer (32 bytes)
 * @return 0 on success, -1 on error
 *
 * @note Thread safety: This function is thread-safe
 */
int load_node_key_bytes(const struct lantern_client_options *options, uint8_t out_key[32]);


/**
 * Check if a string list contains a value.
 *
 * @param list   String list to search
 * @param value  Value to find
 * @return true if found, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool string_list_contains(const struct lantern_string_list *list, const char *value);


/**
 * Remove a value from a string list.
 *
 * @param list   String list to modify
 * @param value  Value to remove
 *
 * @note Thread safety: Caller must hold appropriate lock
 */
void string_list_remove(struct lantern_string_list *list, const char *value);


/**
 * Get text description for connection reason code.
 *
 * @param reason  Reason code from libp2p
 * @return Static string description or NULL
 *
 * @note Thread safety: This function is thread-safe
 */
const char *connection_reason_text(int reason);


/* ============================================================================
 * Lock Functions
 * ============================================================================ */

/**
 * Acquire the client state lock.
 *
 * @param client  Client instance
 * @return true if lock was acquired, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_lock_state(struct lantern_client *client);


/**
 * Release the client state lock.
 *
 * @param client  Client instance
 * @param locked  Value returned from lantern_client_lock_state()
 *
 * @note Thread safety: This function is thread-safe
 */
void lantern_client_unlock_state(struct lantern_client *client, bool locked);


/**
 * Acquire the client pending blocks lock.
 *
 * @param client  Client instance
 * @return true if lock was acquired, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_lock_pending(struct lantern_client *client);


/**
 * Release the client pending blocks lock.
 *
 * @param client  Client instance
 * @param locked  Value returned from lantern_client_lock_pending()
 *
 * @note Thread safety: This function is thread-safe
 */
void lantern_client_unlock_pending(struct lantern_client *client, bool locked);


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
 * Block Sync Functions (client_sync.c)
 * ============================================================================ */

/**
 * Count enabled local validators.
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
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Should be called during initialization
 */
int initialize_fork_choice(struct lantern_client *client);


/**
 * Restore persisted blocks from storage into fork choice.
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
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: Acquires validator_lock
 */
int lantern_client_refresh_state_validators(struct lantern_client *client);


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
 * @param client       Client instance
 * @param parent_root  Root of the newly imported parent block
 *
 * @note Thread safety: Acquires pending_lock and state_lock
 */
void lantern_client_process_pending_children(struct lantern_client *client, const LanternRoot *parent_root);


/**
 * Persist anchor block to storage.
 *
 * @param client        Client instance
 * @param anchor_block  Anchor block to persist
 * @param anchor_root   Anchor block root
 *
 * @note Thread safety: Thread-safe
 */
void persist_anchor_block(struct lantern_client *client, const LanternBlock *anchor_block, const LanternRoot *anchor_root);


/* ============================================================================
 * Peer Status Functions
 * ============================================================================ */

/**
 * Get the capacity for peer ID strings.
 *
 * @return Size of peer_id buffer in lantern_peer_status_entry
 *
 * @note Thread safety: This function is thread-safe
 */
size_t lantern_peer_id_capacity(void);


/**
 * Find a peer status entry by peer ID.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to find
 * @return Pointer to entry if found, NULL otherwise
 *
 * @note Thread safety: Caller must hold status_lock
 */
struct lantern_peer_status_entry *lantern_client_find_status_entry_locked(
    struct lantern_client *client,
    const char *peer_id);


/**
 * Find or create a peer status entry.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to find or create
 * @return Pointer to entry, NULL on failure
 *
 * @note Thread safety: Caller must hold status_lock
 */
struct lantern_peer_status_entry *lantern_client_ensure_status_entry_locked(
    struct lantern_client *client,
    const char *peer_id);


/**
 * Find a peer vote metric entry by peer ID.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to find
 * @return Pointer to entry if found, NULL otherwise
 *
 * @note Thread safety: Caller must hold peer_vote_lock
 */
struct lantern_peer_vote_metric *lantern_client_find_vote_metric_locked(
    struct lantern_client *client,
    const char *peer_id);


/**
 * Find or create a peer vote metric entry.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to find or create
 * @return Pointer to entry, NULL on failure
 *
 * @note Thread safety: Caller must hold peer_vote_lock
 */
struct lantern_peer_vote_metric *lantern_client_ensure_vote_metric_locked(
    struct lantern_client *client,
    const char *peer_id);


/**
 * Register a peer for vote tracking.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to register
 *
 * @note Thread safety: This function acquires peer_vote_lock
 */
void lantern_client_register_vote_peer(
    struct lantern_client *client,
    const char *peer_id);


/**
 * Record a vote delivery from a peer.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID that sent the vote
 * @param vote     Vote that was received (may be NULL)
 *
 * @note Thread safety: This function acquires peer_vote_lock
 */
void lantern_client_note_vote_delivery(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote);


/**
 * Record the outcome of processing a vote from a peer.
 *
 * @param client    Client instance
 * @param peer_id   Peer ID that sent the vote
 * @param vote      Vote that was processed (may be NULL)
 * @param accepted  True if vote was accepted, false if rejected
 *
 * @note Thread safety: This function acquires peer_vote_lock
 */
void lantern_client_note_vote_outcome(
    struct lantern_client *client,
    const char *peer_id,
    const LanternSignedVote *vote,
    bool accepted);


/**
 * Try to begin a status request to a peer.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID to request status from
 * @return true if request can proceed, false if already in flight
 *
 * @note Thread safety: This function acquires status_lock
 */
bool lantern_client_try_begin_status_request(
    struct lantern_client *client,
    const char *peer_id);


/**
 * Note that a status request has started.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID the request is for
 *
 * @note Thread safety: This function acquires status_lock
 */
void lantern_client_note_status_request_start(
    struct lantern_client *client,
    const char *peer_id);


/**
 * Note that a status request has failed.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID the request was for
 *
 * @note Thread safety: This function acquires status_lock
 */
void lantern_client_status_request_failed(
    struct lantern_client *client,
    const char *peer_id);


/**
 * Update status request tracking counters.
 *
 * @param client   Client instance
 * @param entry    Peer status entry to update
 * @param peer_id  Peer ID for logging
 * @param delta    Change to apply (+1 for start, -1 for complete)
 * @param phase    Phase name for logging
 *
 * @note Thread safety: Caller must hold status_lock
 */
void lantern_client_status_request_update_locked(
    struct lantern_client *client,
    struct lantern_peer_status_entry *entry,
    const char *peer_id,
    int delta,
    const char *phase);


/* ============================================================================
 * Block Recording Functions
 * ============================================================================ */

/**
 * Record a block (log, persist, and import).
 *
 * @param client     Client instance
 * @param block      Block to record
 * @param root       Block root (may be NULL, will be computed if not provided)
 * @param peer_text  Peer ID string (may be NULL)
 * @param context    Context string for logging (may be NULL)
 *
 * @note Thread safety: This function acquires state_lock
 */
void lantern_client_record_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    const char *context);


/* ============================================================================
 * Network Functions
 * ============================================================================ */

/**
 * Reset connection counter and connected peer list.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function acquires connection_lock if initialized
 */
void connection_counter_reset(struct lantern_client *client);


/**
 * Update connection counter when a peer connects or disconnects.
 *
 * @param client   Client instance
 * @param delta    Change in connection count (+1 for connect, -1 for disconnect)
 * @param peer     Peer ID (may be NULL)
 * @param inbound  True if inbound connection
 * @param reason   Connection close reason code
 *
 * @note Thread safety: This function acquires connection_lock
 */
void connection_counter_update(
    struct lantern_client *client,
    int delta,
    const peer_id_t *peer,
    bool inbound,
    int reason);


/**
 * Check if a peer is currently connected.
 *
 * @param client   Client instance
 * @param peer_id  Peer ID string to check
 * @return true if peer is connected, false otherwise
 *
 * @note Thread safety: This function acquires connection_lock
 */
bool lantern_client_is_peer_connected(struct lantern_client *client, const char *peer_id);


/**
 * Request status from a peer immediately.
 *
 * @param client     Client instance
 * @param peer       Peer ID (may be NULL)
 * @param peer_text  Peer ID as string (may be NULL)
 *
 * @note Thread safety: This function acquires status_lock
 */
void request_status_now(struct lantern_client *client, const peer_id_t *peer, const char *peer_text);


/**
 * Seed reqresp service with peer legacy mode hints from genesis config.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void lantern_client_seed_reqresp_peer_modes(struct lantern_client *client);


/**
 * Check if a listen address is unspecified (0.0.0.0 or ::).
 *
 * @param addr  Listen address string
 * @return true if unspecified, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool listen_address_is_unspecified(const char *addr);


/**
 * Adopt listen address from validator config if current address is unspecified.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void adopt_validator_listen_address(struct lantern_client *client);


/**
 * Dial a multiaddr using the identify protocol.
 *
 * @param client      Client instance
 * @param multiaddr   Multiaddr to dial
 * @param peer_label  Label for logging
 *
 * @note Thread safety: This function is thread-safe
 */
void identify_dial_multiaddr(struct lantern_client *client, const char *multiaddr, const char *peer_label);


/**
 * Sleep for a number of seconds, checking stop flag periodically.
 *
 * @param client   Client instance
 * @param seconds  Number of seconds to sleep
 *
 * @note Thread safety: This function is thread-safe
 */
void peer_dialer_sleep(struct lantern_client *client, unsigned seconds);


/**
 * Attempt to redial a peer that disconnected due to timeout.
 *
 * @param client  Client instance
 * @param peer    Peer ID to redial
 *
 * @note Thread safety: This function acquires connection_lock
 */
void redial_peer_on_timeout(struct lantern_client *client, const peer_id_t *peer);


/**
 * Attempt to dial peers from genesis ENRs.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function acquires connection_lock
 */
void peer_dialer_attempt(struct lantern_client *client);


/**
 * Start the peer dialer service.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int start_peer_dialer(struct lantern_client *client);


/**
 * Stop the peer dialer service.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_peer_dialer(struct lantern_client *client);


/**
 * Start the ping service.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int start_ping_service(struct lantern_client *client);


/**
 * Stop the ping service.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_ping_service(struct lantern_client *client);


/**
 * Connection event callback for libp2p host.
 *
 * @param evt        Event details
 * @param user_data  Client instance
 *
 * @note Thread safety: This function is called from libp2p thread
 */
void connection_events_cb(const libp2p_event_t *evt, void *user_data);


/* ============================================================================
 * Validator Service Functions (client_validator.c)
 * ============================================================================ */

/**
 * Reset validator duty state.
 *
 * @param state  Duty state to reset
 *
 * @note Thread safety: This function is thread-safe
 */
void validator_duty_state_reset(struct lantern_validator_duty_state *state);


/**
 * Compute wall-clock time for a vote slot.
 *
 * @param client       Client instance
 * @param vote_slot    Slot number
 * @param out_seconds  Output for computed time in seconds
 * @return true on success, false on failure
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_vote_time_seconds(
    const struct lantern_client *client,
    uint64_t vote_slot,
    uint64_t *out_seconds);


/**
 * Check if the validator service should run.
 *
 * @param client  Client instance
 * @return true if service should run, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool validator_service_should_run(const struct lantern_client *client);


/**
 * Check if a validator is enabled.
 *
 * @param client       Client instance
 * @param local_index  Local validator index
 * @return true if enabled, false otherwise
 *
 * @note Thread safety: This function acquires validator_lock
 */
bool validator_is_enabled(const struct lantern_client *client, size_t local_index);


/**
 * Get the global index for a local validator.
 *
 * @param client       Client instance
 * @param local_index  Local validator index
 * @return Global index, or UINT64_MAX on error
 *
 * @note Thread safety: This function is thread-safe
 */
uint64_t validator_global_index(const struct lantern_client *client, size_t local_index);


/**
 * Sign a vote with a validator's secret key.
 *
 * @param validator  Local validator
 * @param slot       Slot number
 * @param vote       Vote to sign (modified in place)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int validator_sign_vote(
    struct lantern_local_validator *validator,
    uint64_t slot,
    LanternSignedVote *vote);


/**
 * Store a vote in the client state.
 *
 * @param client  Client instance
 * @param vote    Vote to store
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires state_lock
 */
int validator_store_vote(struct lantern_client *client, const LanternSignedVote *vote);


/**
 * Publish a vote to the network.
 *
 * @param client  Client instance
 * @param vote    Vote to publish
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int validator_publish_vote(struct lantern_client *client, const LanternSignedVote *vote);


/**
 * Build a block for a validator.
 *
 * @param client            Client instance
 * @param slot              Slot number
 * @param local_index       Local validator index
 * @param out_block         Output for the built block
 * @param out_proposer_vote Output for the proposer's vote
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires state_lock
 */
int validator_build_block(
    struct lantern_client *client,
    uint64_t slot,
    size_t local_index,
    LanternSignedBlock *out_block,
    LanternSignedVote *out_proposer_vote);


/**
 * Propose a block for a validator.
 *
 * @param client       Client instance
 * @param slot         Slot number
 * @param local_index  Local validator index
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires validator_lock
 */
int validator_propose_block(struct lantern_client *client, uint64_t slot, size_t local_index);


/**
 * Publish attestations for all enabled validators.
 *
 * @param client  Client instance
 * @param slot    Slot number
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires state_lock and validator_lock
 */
int validator_publish_attestations(struct lantern_client *client, uint64_t slot);


/**
 * Validator service thread function.
 *
 * @param arg  Client instance
 * @return NULL
 *
 * @note Thread safety: This function runs in a separate thread
 */
void *validator_thread(void *arg);


/**
 * Start the validator service.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int start_validator_service(struct lantern_client *client);


/**
 * Stop the validator service.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_validator_service(struct lantern_client *client);


/* ============================================================================
 * HTTP Callback Functions (client_http.c)
 * ============================================================================ */

/**
 * Find local validator index by global index.
 *
 * @param client        Client instance
 * @param global_index  Global validator index to find
 * @param out_index     Output for local index
 * @return 0 on success, -1 if not found
 *
 * @note Thread safety: This function is thread-safe
 */
int find_local_validator_index(
    const struct lantern_client *client,
    uint64_t global_index,
    size_t *out_index);


/**
 * Get current head snapshot for HTTP API.
 *
 * @param context       Client instance
 * @param out_snapshot  Output snapshot structure
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int http_snapshot_head(void *context, struct lantern_http_head_snapshot *out_snapshot);


/**
 * Get count of local validators for HTTP API.
 *
 * @param context  Client instance
 * @return Number of local validators
 *
 * @note Thread safety: This function is thread-safe
 */
size_t http_validator_count_cb(void *context);


/**
 * Get validator info for HTTP API.
 *
 * @param context   Client instance
 * @param index     Local validator index
 * @param out_info  Output info structure
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires validator_lock
 */
int http_validator_info_cb(void *context, size_t index, struct lantern_http_validator_info *out_info);


/**
 * Set validator enabled/disabled status for HTTP API.
 *
 * @param context       Client instance
 * @param global_index  Global validator index
 * @param enabled       New enabled status
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires validator_lock
 */
int http_set_validator_status_cb(void *context, uint64_t global_index, bool enabled);


/**
 * Get metrics snapshot for HTTP API.
 *
 * @param context       Client instance
 * @param out_snapshot  Output snapshot structure
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires state_lock and peer_vote_lock
 */
int metrics_snapshot_cb(void *context, struct lantern_metrics_snapshot *out_snapshot);


/* ============================================================================
 * Reqresp Callback Functions (client_reqresp.c)
 * ============================================================================ */

/**
 * Build a status message for reqresp protocol.
 *
 * @param context     Client instance
 * @param out_status  Output status message
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int reqresp_build_status(void *context, LanternStatusMessage *out_status);


/**
 * Handle an incoming status message from a peer.
 *
 * @param context      Client instance
 * @param peer_status  Status message from peer
 * @param peer_id      Peer ID string
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function acquires status_lock
 */
int reqresp_handle_status(void *context, const LanternStatusMessage *peer_status, const char *peer_id);


/**
 * Handle a status request failure.
 *
 * @param context  Client instance
 * @param peer_id  Peer ID string
 * @param error    Error code
 *
 * @note Thread safety: This function acquires status_lock
 */
void reqresp_status_failure(void *context, const char *peer_id, int error);


/**
 * Collect blocks for a blocks_by_root request.
 *
 * @param context     Client instance
 * @param roots       Array of block roots to collect
 * @param root_count  Number of roots
 * @param out_blocks  Output response structure
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int reqresp_collect_blocks(
    void *context,
    const LanternRoot *roots,
    size_t root_count,
    LanternBlocksByRootResponse *out_blocks);


/**
 * Handle completion of a blocks request.
 *
 * @param client        Client instance
 * @param peer_id       Peer ID string
 * @param request_root  Root that was requested
 * @param outcome       Request outcome
 *
 * @note Thread safety: This function acquires status_lock and pending_lock
 */
void lantern_client_on_blocks_request_complete(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_root,
    enum lantern_blocks_request_outcome outcome);


/**
 * Read a response chunk from a reqresp stream.
 *
 * @param service               Reqresp service (may be NULL)
 * @param stream                libp2p stream
 * @param protocol              Protocol kind
 * @param out_data              Output data buffer (caller must free)
 * @param out_len               Output data length
 * @param out_err               Output error code (may be NULL)
 * @param out_response_code     Output response code (may be NULL)
 * @param response_code_pending Tracks whether response code is still expected
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int lantern_reqresp_read_response_chunk(
    struct lantern_reqresp_service *service,
    libp2p_stream_t *stream,
    enum lantern_reqresp_protocol_kind protocol,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    uint8_t *out_response_code,
    bool *response_code_pending);


/* ============================================================================
 * Key Management Functions (client_keys.c)
 * ============================================================================ */

/**
 * Clean up a single local validator's resources.
 *
 * @param validator  Validator to clean up
 *
 * @note Thread safety: Caller must ensure exclusive access to the validator
 */
void local_validator_cleanup(struct lantern_local_validator *validator);


/**
 * Reset all local validators and free resources.
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during shutdown
 */
void reset_local_validators(struct lantern_client *client);


/**
 * Decode a hex-encoded validator secret key.
 *
 * @param hex      Hex string (with optional 0x prefix)
 * @param out_key  Output buffer (caller must free)
 * @param out_len  Output length
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
int decode_validator_secret(const char *hex, uint8_t **out_key, size_t *out_len);


/**
 * Configure hash-sig key sources from options and environment.
 *
 * @param client   Client instance
 * @param options  Client options
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function should be called during initialization
 */
int configure_hash_sig_sources(
    struct lantern_client *client,
    const struct lantern_client_options *options);


/**
 * Load all hash-sig keys for the client.
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function should be called during initialization
 */
int load_hash_sig_keys(struct lantern_client *client);


/**
 * Free all loaded public key handles.
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during shutdown
 */
void free_hash_sig_pubkeys(struct lantern_client *client);


#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CLIENT_INTERNAL_H */
