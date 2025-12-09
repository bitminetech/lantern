/**
 * @file client_services_internal.h
 * @brief Internal declarations for validator, HTTP, and reqresp services
 *
 * @spec subspecs/networking/reqresp.py - request/response protocols
 *
 * This header contains internal types and function declarations for
 * validator service, HTTP callbacks, and request/response protocol handling.
 * It is NOT part of the public API.
 *
 * Related files:
 * - client_validator.c: Validator duty execution
 * - client_http.c: HTTP API callbacks
 * - client_reqresp.c: Request/response protocol handling
 * - client_reqresp_stream.c: Stream I/O utilities
 * - client_reqresp_blocks.c: Block request handling
 * - client_keys.c: Key management
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#ifndef LANTERN_CLIENT_SERVICES_INTERNAL_H
#define LANTERN_CLIENT_SERVICES_INTERNAL_H

#include "lantern/core/client.h"
#include "lantern/consensus/containers.h"
#include "lantern/http/server.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/networking/reqresp_service.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Include network internal header for shared types */
#include "client_network_internal.h"


/* ============================================================================
 * Validator Service Functions
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
 * @spec subspecs/slot/slot_clock.py - slot timing
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
 * @spec subspecs/duties/duties.py - validator management
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
 * @spec subspecs/xmss/sign.py - signature generation
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
 * @spec subspecs/attestation/attestation.py - vote storage
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
 * @spec subspecs/networking/gossip.py - vote gossip
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
 * @spec subspecs/block/block.py - block production
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
 * @spec subspecs/duties/proposer.py - block proposal
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
 * @spec subspecs/duties/attester.py - attestation duties
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
 * HTTP Callback Functions
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
 * Reqresp Callback Functions
 * ============================================================================ */

/**
 * Build a status message for reqresp protocol.
 *
 * @spec subspecs/networking/status.py - status protocol
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
 * @spec subspecs/networking/status.py - status protocol
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
 * @spec subspecs/networking/reqresp.py - blocks by root
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
 * @spec subspecs/networking/reqresp.py - blocks by root
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
 * @spec subspecs/networking/reqresp.py - stream protocol
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
 * Key Management Functions
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
 * @spec subspecs/xmss/keygen.py - key encoding
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
 * @spec subspecs/xmss/keygen.py - key loading
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

#endif /* LANTERN_CLIENT_SERVICES_INTERNAL_H */
