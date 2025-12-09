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
 *       6. peer_vote_lock
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
 * Validator Record Functions
 * ============================================================================ */

/**
 * Get a validator record from the genesis registry.
 *
 * @param client         Client instance
 * @param global_index   Validator global index
 * @return Pointer to validator record, or NULL if not found
 *
 * @note Thread safety: This function is thread-safe (read-only access)
 */
const struct lantern_validator_record *lantern_client_get_validator_record(
    const struct lantern_client *client,
    uint64_t global_index);


#ifdef __cplusplus
}
#endif

/* Include specialized internal headers */
#include "client_sync_internal.h"
#include "client_services_internal.h"

#endif /* LANTERN_CLIENT_INTERNAL_H */
