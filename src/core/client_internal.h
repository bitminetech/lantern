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

/**
 * Cache an individual gossip signature keyed by validator and attestation root.
 *
 * @param client     Client instance (state_lock must be held)
 * @param key        Signature cache key
 * @param signature  XMSS signature to cache
 * @return 0 on success, -1 on error
 *
 * @note Thread safety: Caller must hold state_lock.
 */
int lantern_client_set_gossip_signature(
    struct lantern_client *client,
    const LanternSignatureKey *key,
    const LanternAttestationData *data,
    const LanternSignature *signature,
    uint64_t target_slot);

/**
 * Cache a newly received aggregated signature proof keyed by attestation data root.
 *
 * @note Thread safety: Caller must hold state_lock.
 */
int lantern_client_add_new_aggregated_payload(
    struct lantern_client *client,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot);

/**
 * Cache a processed aggregated signature proof in the known payload pool.
 *
 * @note Thread safety: Caller must hold state_lock.
 */
int lantern_client_add_known_aggregated_payload(
    struct lantern_client *client,
    const LanternRoot *data_root,
    const LanternAttestationData *data,
    const LanternAggregatedSignatureProof *proof,
    uint64_t target_slot);

/**
 * Promote pending aggregated payloads into the known pool.
 *
 * @note Thread safety: Caller must hold state_lock.
 */
size_t lantern_client_promote_new_aggregated_payloads(
    struct lantern_client *client);

/**
 * Prune cached signatures, attestation data, and aggregated payloads whose
 * attestation target slot is finalized.
 *
 * @param client          Client instance (state_lock must be held)
 * @param finalized_slot  Latest finalized slot boundary
 * @return Number of entries removed
 *
 * @note Thread safety: Caller must hold state_lock.
 */
size_t lantern_client_prune_finalized_attestation_material(
    struct lantern_client *client,
    uint64_t finalized_slot);

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

/**
 * Select cached aggregated proofs for block attestations.
 *
 * @note Thread safety: Acquires state_lock internally.
 */
lantern_client_error lantern_client_aggregate_attestations_for_block(
    struct lantern_client *client,
    const LanternAttestations *att_list,
    const LanternSignatureList *att_signatures,
    LanternAggregatedAttestations *out_attestations,
    LanternAttestationSignatures *out_signatures);


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
