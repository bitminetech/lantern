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
 * Check if the validator service should run.
 *
 * @param client  Client instance
 * @return true if service should run, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool validator_service_should_run(const struct lantern_client *client);


/**
 * Sign a vote with a validator's secret key.
 *
 * @spec subspecs/xmss/sign.py - signature generation
 *
 * @param validator  Local validator
 * @param slot       Slot number
 * @param vote       Vote to sign (modified in place)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_VALIDATOR on hashing or signing failure
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
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL input or overflow
 * @return LANTERN_CLIENT_ERR_RUNTIME if state is unavailable or lock fails
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
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on NULL inputs
 * @return LANTERN_CLIENT_ERR_NETWORK if publish fails
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
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM on bad inputs
 * @return LANTERN_CLIENT_ERR_RUNTIME on state/runtime failures
 * @return LANTERN_CLIENT_ERR_VALIDATOR on signing failures
 * @return LANTERN_CLIENT_ERR_ALLOC on allocation/copy failures
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
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_RUNTIME if prerequisites are not met
 * @return Propagated errors from validator_build_block() or
 *         lantern_client_publish_block()
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
 * @return LANTERN_CLIENT_OK on success (best effort)
 * @return LANTERN_CLIENT_ERR_RUNTIME when prerequisites are not satisfied or
 *         locks fail
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM when inputs are NULL or no local
 *         validators are configured
 *
 * @note Thread safety: This function acquires state_lock and validator_lock
 */
int validator_publish_attestations(struct lantern_client *client, uint64_t slot);


/**
 * Timing service thread function.
 *
 * @param arg  Client instance
 * @return NULL
 *
 * @note Thread safety: This function runs in a separate thread
 */
void *timing_thread(void *arg);


/**
 * Start the timing service.
 *
 * @param client  Client instance
 * @return LANTERN_CLIENT_OK on success or when already running/missing
 *         prerequisites
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if client is NULL
 * @return LANTERN_CLIENT_ERR_RUNTIME if the service thread cannot be created
 *
 * @note Thread safety: This function is thread-safe
 */
int start_timing_service(struct lantern_client *client);


/**
 * Stop the timing service.
 *
 * @param client  Client instance
 *
 * @note Thread safety: This function is thread-safe
 */
void stop_timing_service(struct lantern_client *client);


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
 * @return LANTERN_CLIENT_OK on success or when already running/missing
 *         prerequisites
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if client is NULL
 * @return LANTERN_CLIENT_ERR_RUNTIME if the service thread cannot be created
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
 * Get current fork-choice tree snapshot for HTTP API.
 *
 * @param context       Client instance
 * @param out_snapshot  Output snapshot structure
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function may acquire state_lock
 */
int http_snapshot_fork_choice(
    void *context,
    struct lantern_http_fork_choice_snapshot *out_snapshot);


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
int http_validator_info_cb(
    void *context,
    size_t index,
    struct lantern_http_validator_info *out_info);


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

/**
 * Get finalized state SSZ bytes for checkpoint sync.
 *
 * @param context    Client instance
 * @param out_bytes  Output buffer pointer (caller owns and must free)
 * @param out_len    Output byte length
 * @return 0 on success, negative on failure
 *
 * @note Thread safety: This function may acquire state_lock
 */
int http_finalized_state_ssz_cb(void *context, uint8_t **out_bytes, size_t *out_len);


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
int reqresp_handle_status(
    void *context,
    const LanternStatusMessage *peer_status,
    const char *peer_id);


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
    LanternSignedBlockList *out_blocks);


/**
 * Handle completion of a blocks request.
 *
 * @spec subspecs/networking/reqresp.py - blocks by root
 *
 * @param client        Client instance
 * @param peer_id       Peer ID string
 * @param request_roots Roots that were requested
 * @param root_count    Number of requested roots
 * @param outcome       Request outcome
 *
 * @note Thread safety: This function acquires status_lock and pending_lock
 */
void lantern_client_on_blocks_request_complete_batch(
    struct lantern_client *client,
    const char *peer_id,
    const LanternRoot *request_roots,
    size_t root_count,
    enum lantern_blocks_request_outcome outcome);

/**
 * Handle completion of a tracked blocks request batch.
 *
 * Same as lantern_client_on_blocks_request_complete_batch(), but includes
 * the internal request tracking ID used by the active request registry.
 */
void lantern_client_on_blocks_request_complete_batch_with_id(
    struct lantern_client *client,
    uint64_t request_id,
    const char *peer_id,
    const LanternRoot *request_roots,
    size_t root_count,
    enum lantern_blocks_request_outcome outcome);

/**
 * Handle completion of a blocks request (single root).
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
 * @return 0 on success
 * @return LANTERN_REQRESP_ERR_INVALID_PARAM if required parameters are NULL
 * @return LANTERN_REQRESP_ERR_SET_READ_INTEREST if enabling read interest fails
 * @return LANTERN_REQRESP_ERR_SET_DEADLINE if setting a stream deadline fails
 * @return LANTERN_REQRESP_ERR_STREAM_READ if reading from the stream fails
 * @return LANTERN_REQRESP_ERR_VARINT_HEADER_TOO_LONG if the varint header exceeds limits
 * @return LANTERN_REQRESP_ERR_PAYLOAD_TOO_LARGE if the payload length exceeds limits
 * @return LANTERN_REQRESP_ERR_ALLOC if allocating the payload buffer fails
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

/**
 * Schedule a blocks_by_root request to a peer.
 *
 * @spec subspecs/networking/reqresp/message.py - BlocksByRoot protocol
 *
 * @param client         Client instance
 * @param peer_id_text   Peer ID string
 * @param roots          Block roots to request
 * @param depths         Backfill depth per root (may be NULL for zeros)
 * @param root_count     Number of roots
 * @param request_id     Internal request tracking ID (0 disables tracking)
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if parameters are invalid, the peer ID is invalid, or any root is zero
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_NETWORK if stream dialing fails or networking is unavailable
 *
 * @note Thread safety: This function is thread-safe
 */
int lantern_client_schedule_blocks_request_batch(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *roots,
    const uint32_t *depths,
    size_t root_count,
    uint64_t request_id);

/**
 * Write all bytes to a stream.
 *
 * Retries on AGAIN/TIMEOUT errors until all bytes are written or the
 * reqresp stall timeout window elapses.
 *
 * @param stream  libp2p stream
 * @param data    Data to write
 * @param length  Number of bytes to write
 * @param out_err Optional output error code (may be NULL)
 * @return 0 on success
 * @return LANTERN_REQRESP_ERR_INVALID_PARAM if parameters are invalid
 * @return LANTERN_REQRESP_ERR_STREAM_WRITE on stream write failure
 *
 * @note Thread safety: This function is thread-safe
 */
int stream_write_all(
    libp2p_stream_t *stream,
    const uint8_t *data,
    size_t length,
    ssize_t *out_err);


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
void lantern_client_local_validator_cleanup(struct lantern_local_validator *validator);


/**
 * Reset all local validators and free resources.
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during shutdown
 */
void lantern_client_reset_local_validators(struct lantern_client *client);


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
int lantern_client_decode_validator_secret(const char *hex, uint8_t **out_key, size_t *out_len);


/**
 * Configure xmss key sources from options and environment.
 *
 * @param client   Client instance
 * @param options  Client options
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function should be called during initialization
 */
int lantern_client_configure_xmss_sources(
    struct lantern_client *client,
    const struct lantern_client_options *options);


/**
 * Load all xmss keys for the client.
 *
 * @spec subspecs/xmss/keygen.py - key loading
 *
 * @param client  Client instance
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function should be called during initialization
 */
int lantern_client_load_xmss_keys(struct lantern_client *client);


/**
 * Free all loaded public key handles.
 *
 * @param client  Client instance
 *
 * @note Thread safety: Caller must ensure exclusive access during shutdown
 */
void lantern_client_free_xmss_pubkeys(struct lantern_client *client);


#ifdef __cplusplus
}
#endif

#endif /* LANTERN_CLIENT_SERVICES_INTERNAL_H */
