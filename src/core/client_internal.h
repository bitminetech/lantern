/**
 * @file client_internal.h
 * @brief Internal declarations for the client module
 *
 * This header contains internal types, constants, and function declarations
 * shared across client implementation files. It is NOT part of the public API.
 *
 * This is the main internal header that includes specialized headers:
 * - client_sync_internal.h: Block/vote synchronization
 * - client_services_internal.h: Networking, validator, HTTP, reqresp services
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 */

#ifndef LANTERN_CLIENT_INTERNAL_H
#define LANTERN_CLIENT_INTERNAL_H

#include "lantern/core/client.h"
#include "lantern/consensus/containers.h"
#include "lantern/support/log.h"

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif


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
 * Get current wall clock time in milliseconds.
 *
 * @return Current time as Unix timestamp in milliseconds
 *
 * @note Thread safety: This function is thread-safe
 */
uint64_t validator_wall_time_now_millis(void);


/**
 * Sleep for specified milliseconds.
 *
 * @param ms  Milliseconds to sleep
 *
 * @note Thread safety: This function is thread-safe
 */
void validator_sleep_ms(uint32_t ms);


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


const char *lantern_sync_state_name(LanternSyncState state);


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


/**
 * Remove a value from a string list.
 *
 * @param list   String list to modify
 * @param value  Value to remove
 *
 * @note Thread safety: Caller must hold appropriate lock
 */


/**
 * Get text description for connection reason code.
 *
 * @param reason  Reason code from libp2p
 * @return Static string description or NULL
 *
 * @note Thread safety: This function is thread-safe
 */
const char *connection_reason_text(int reason);

/**
 * Decide whether a persisted state is too stale to trust when checkpoint sync
 * is available.
 *
 * Computes the expected wall-clock slot from genesis time, then compares it
 * against the persisted state's slot.
 *
 * @param persisted_state             Persisted state loaded from storage
 * @param genesis_time                Chain genesis Unix time in seconds
 * @param now_seconds                 Current Unix time in seconds
 * @param out_expected_current_slot   Optional output for expected slot
 * @param out_gap                     Optional output for slot gap
 *
 * @return true when the persisted state should be discarded in favor of
 *         checkpoint sync
 */
bool lantern_client_persisted_state_is_stale_for_checkpoint_sync(
    const LanternState *persisted_state,
    uint64_t genesis_time,
    uint64_t now_seconds,
    uint64_t *out_expected_current_slot,
    uint64_t *out_gap);

size_t lantern_client_attestation_committee_count(const struct lantern_client *client);

/**
 * Advance fork choice by exactly one interval and sync crossed payload-pool transitions.
 *
 * Caller must hold state_lock or otherwise guarantee exclusive access to the
 * client store and fork-choice state.
 */
int lantern_client_tick_fork_choice_interval_locked(
    struct lantern_client *client,
    bool has_proposal);

/**
 * Move fork choice time directly to a later interval without replaying skipped intervals.
 *
 * Caller must hold state_lock or otherwise guarantee exclusive access to the
 * client store and fork-choice state.
 */
int lantern_client_skip_fork_choice_intervals_locked(
    struct lantern_client *client,
    uint64_t target_interval);

/**
 * Catch fork choice up to a target interval using ChainService-style skip and yield semantics.
 *
 * The helper may release state_lock between interval ticks so other threads can
 * process gossip and block imports while catch-up is in progress.
 */
int lantern_client_chain_service_tick_to(
    struct lantern_client *client,
    uint64_t target_interval,
    bool has_proposal,
    uint64_t *out_skipped_to_interval,
    uint64_t *out_ticked_intervals);

/**
 * Advance fork choice time and sync the aggregated payload pools for crossed intervals.
 *
 * Caller must hold state_lock or otherwise guarantee exclusive access to the
 * client store and fork-choice state.
 */
int lantern_client_advance_fork_choice_time_locked(
    struct lantern_client *client,
    uint64_t now_milliseconds,
    bool has_proposal);

/* ============================================================================
 * Lock Functions
 * ============================================================================ */

void lantern_client_unlock_mutex(
    pthread_mutex_t *mutex,
    const char *validator_id,
    const char *name,
    const char *component);

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

#ifdef __cplusplus
}
#endif

/* Include specialized internal headers */
#include "client_sync_internal.h"
#include "client_services_internal.h"

#endif /* LANTERN_CLIENT_INTERNAL_H */
