/**
 * @file client_reqresp.c
 * @brief Request/response protocol handlers and stream operations
 *
 * Implements the reqresp protocol callbacks for status exchange and
 * blocks_by_root requests, as well as stream read/write utilities.
 *
 * @note Lock ordering (acquire in this order to prevent deadlocks):
 *       1. state_lock
 *       2. status_lock
 *       3. pending_lock
 *       4. validator_lock
 *       5. connection_lock
 *       6. peer_vote_lock
 */

#include "client_internal.h"

#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/encoding/snappy.h"
#include "lantern/networking/messages.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/storage/storage.h"
#include "lantern/support/strings.h"
#include "lantern/support/log.h"

#include "libp2p/errors.h"
#include "libp2p/host.h"
#include "libp2p/stream.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "peer_id/peer_id.h"

#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * Constants
 * ============================================================================ */

/** Maximum bytes for a reqresp header varint */
#define LANTERN_REQRESP_HEADER_MAX_BYTES 10u

/* LANTERN_REQRESP_MAX_CHUNK_BYTES is defined in lantern/networking/reqresp_service.h */
/* LANTERN_REQRESP_STALL_TIMEOUT_MS is defined in lantern/networking/reqresp_service.h */
/* LANTERN_STATUS_PREVIEW_BYTES is defined in lantern/networking/reqresp_service.h */


/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static int stream_write_all(libp2p_stream_t *stream, const uint8_t *data, size_t length);
static int read_stream_varint(
    libp2p_stream_t *stream,
    uint64_t *out_value,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err);
static int discard_stream_bytes(
    libp2p_stream_t *stream,
    uint64_t length,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err);
static int read_varint_payload_chunk(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label);
static void block_request_ctx_free(struct block_request_ctx *ctx);
static bool lantern_client_process_stream_block_chunk(
    struct block_request_ctx *ctx,
    uint8_t *chunk,
    size_t chunk_len,
    const struct lantern_log_metadata *meta,
    bool *saw_block);
static void *block_request_worker(void *arg);
static void block_request_on_open(libp2p_stream_t *stream, void *user_data, int err);
static int lantern_client_schedule_blocks_request(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *root,
    bool use_legacy);
static void lantern_client_on_peer_status(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id);
static void lantern_client_adopt_peer_genesis(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text);
/* lantern_client_on_blocks_request_complete is declared in client_internal.h */


/* ============================================================================
 * Reqresp Callbacks
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
int reqresp_build_status(void *context, LanternStatusMessage *out_status)
{
    if (!context || !out_status)
    {
        return -1;
    }
    struct lantern_client *client = context;
    memset(out_status, 0, sizeof(*out_status));
    if (!client->has_state)
    {
        return 0;
    }

    out_status->finalized = client->state.latest_finalized;

    bool head_set = false;
    if (client->has_fork_choice)
    {
        LanternRoot fork_head = {{0}};
        uint64_t fork_slot = 0;
        if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0
            && lantern_fork_choice_block_info(&client->fork_choice, &fork_head, &fork_slot, NULL, NULL) == 0)
        {
            out_status->head.root = fork_head;
            out_status->head.slot = fork_slot;
            head_set = true;
        }
    }

    if (!head_set)
    {
        out_status->head.slot = client->state.latest_block_header.slot;
        if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, &out_status->head.root) != 0)
        {
            memset(&out_status->head.root, 0, sizeof(out_status->head.root));
        }
    }
    return 0;
}


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
int reqresp_handle_status(void *context, const LanternStatusMessage *peer_status, const char *peer_id)
{
    if (!context || !peer_status)
    {
        return -1;
    }
    struct lantern_client *client = context;
    char head_hex[2 * LANTERN_ROOT_SIZE + 3];
    char finalized_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));
    format_root_hex(&peer_status->finalized.root, finalized_hex, sizeof(finalized_hex));

    lantern_log_info(
        "network",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id},
        "peer status head_slot=%" PRIu64 " head_root=%s finalized_slot=%" PRIu64 " finalized_root=%s",
        peer_status->head.slot,
        head_hex[0] ? head_hex : "0x0",
        peer_status->finalized.slot,
        finalized_hex[0] ? finalized_hex : "0x0");
    lantern_client_on_peer_status(client, peer_status, peer_id);
    return 0;
}


/**
 * Handle a status request failure.
 *
 * @param context  Client instance
 * @param peer_id  Peer ID string
 * @param error    Error code
 *
 * @note Thread safety: This function acquires status_lock
 */
void reqresp_status_failure(void *context, const char *peer_id, int error)
{
    if (!context)
    {
        return;
    }
    struct lantern_client *client = context;
    char peer_copy[sizeof(((struct lantern_peer_status_entry *)0)->peer_id)];
    memset(peer_copy, 0, sizeof(peer_copy));
    if (peer_id && *peer_id)
    {
        strncpy(peer_copy, peer_id, sizeof(peer_copy) - 1);
        peer_copy[sizeof(peer_copy) - 1] = '\0';
    }
    if (error == 0)
    {
        error = LIBP2P_ERR_INTERNAL;
    }

    if (peer_copy[0] != '\0')
    {
        lantern_client_status_request_failed(client, peer_copy);
    }

    bool first_failure = true;
    if (peer_copy[0] != '\0')
    {
        if (client->status_lock_initialized)
        {
            if (pthread_mutex_lock(&client->status_lock) == 0)
            {
                if (string_list_contains(&client->status_failure_peer_ids, peer_copy))
                {
                    first_failure = false;
                }
                else
                {
                    (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
                }
                pthread_mutex_unlock(&client->status_lock);
            }
            else
            {
                if (string_list_contains(&client->status_failure_peer_ids, peer_copy))
                {
                    first_failure = false;
                }
                else
                {
                    (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
                }
            }
        }
        else if (string_list_contains(&client->status_failure_peer_ids, peer_copy))
        {
            first_failure = false;
        }
        else
        {
            (void)lantern_string_list_append(&client->status_failure_peer_ids, peer_copy);
        }
    }

    const char *reason = connection_reason_text(error);
    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_copy[0] ? peer_copy : NULL,
    };

    if (error == LIBP2P_ERR_PROTO_NEGOTIATION_FAILED || error == LIBP2P_ERR_UNSUPPORTED)
    {
        if (first_failure)
        {
            lantern_log_info(
                "reqresp",
                &meta,
                "peer does not support %s error=%d (%s)",
                LANTERN_STATUS_PROTOCOL_ID,
                error,
                reason ? reason : "-");
        }
        else
        {
            lantern_log_trace(
                "reqresp",
                &meta,
                "peer still misses %s support error=%d (%s)",
                LANTERN_STATUS_PROTOCOL_ID,
                error,
                reason ? reason : "-");
        }
        return;
    }

    if (error == LIBP2P_ERR_TIMEOUT)
    {
        if (first_failure)
        {
            lantern_log_warn(
                "reqresp",
                &meta,
                "status request to peer timed out error=%d (%s)",
                error,
                reason ? reason : "-");
        }
        else
        {
            lantern_log_debug(
                "reqresp",
                &meta,
                "status request still timing out error=%d (%s)",
                error,
                reason ? reason : "-");
        }
        return;
    }

    if (first_failure)
    {
        lantern_log_warn(
            "reqresp",
            &meta,
            "status request failed error=%d (%s)",
            error,
            reason ? reason : "-");
    }
    else
    {
        lantern_log_debug(
            "reqresp",
            &meta,
            "status request still failing error=%d (%s)",
            error,
            reason ? reason : "-");
    }
}


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
    LanternBlocksByRootResponse *out_blocks)
{
    if (!context || !out_blocks)
    {
        return -1;
    }
    struct lantern_client *client = context;
    if (!client->data_dir)
    {
        return lantern_blocks_by_root_response_resize(out_blocks, 0);
    }
    int rc = lantern_storage_collect_blocks(client->data_dir, roots, root_count, out_blocks);
    if (rc != 0)
    {
        lantern_log_error(
            "reqresp",
            &(const struct lantern_log_metadata){.validator = client->node_id},
            "failed to collect blocks from storage");
        return -1;
    }
    return 0;
}


/* ============================================================================
 * Peer Status Processing
 * ============================================================================ */

/**
 * Process a peer status message internally.
 *
 * @param client       Client instance
 * @param peer_status  Status message from peer
 * @param peer_id      Peer ID string
 *
 * @note Thread safety: This function acquires status_lock
 */
static void lantern_client_on_peer_status(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id)
{
    if (!client || !peer_status || !client->status_lock_initialized)
    {
        return;
    }
    if (!peer_id || *peer_id == '\0')
    {
        return;
    }
    if (lantern_root_is_zero(&peer_status->head.root))
    {
        return;
    }

    char head_hex[2 * LANTERN_ROOT_SIZE + 3];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));

    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    char peer_copy[sizeof(((struct lantern_peer_status_entry *)0)->peer_id)];
    memset(peer_copy, 0, sizeof(peer_copy));
    strncpy(peer_copy, peer_id, peer_cap - 1);

    LanternRoot request_root = peer_status->head.root;
    uint64_t local_slot = 0;
    bool head_known = false;
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked)
    {
        local_slot = client->state.slot;
        head_known = lantern_client_block_known_locked(client, &peer_status->head.root, NULL);
    }
    else if (client->has_state)
    {
        local_slot = client->state.slot;
        if (client->has_fork_choice)
        {
            uint64_t fork_slot = 0;
            if (lantern_fork_choice_block_info(&client->fork_choice, &peer_status->head.root, &fork_slot, NULL, NULL) == 0)
            {
                head_known = true;
            }
        }
    }
    lantern_client_unlock_state(client, state_locked);

    bool should_request = false;

    /* If we bootstrapped via genesis fallback and the peer advertises the genesis head,
       adopt the peer's head root as our anchor so that subsequent block requests use
       the correct root. */
    if (client->genesis_fallback_used && client->has_fork_choice && client->has_state
        && peer_status->head.slot == 0 && local_slot == 0 && !head_known)
    {
        lantern_client_adopt_peer_genesis(client, peer_status, peer_copy);
        head_known = true;
    }

    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return;
    }

    struct lantern_peer_status_entry *entry = lantern_client_ensure_status_entry_locked(client, peer_copy);
    if (!entry)
    {
        pthread_mutex_unlock(&client->status_lock);
        return;
    }
    entry->status_request_inflight = false;
    lantern_client_status_request_update_locked(client, entry, peer_copy, -1, "complete");

    string_list_remove(&client->status_failure_peer_ids, peer_copy);

    bool had_status = entry->has_status;
    LanternStatusMessage previous_status = entry->status;
    bool head_changed = !had_status
        || previous_status.head.slot != peer_status->head.slot
        || memcmp(previous_status.head.root.bytes, peer_status->head.root.bytes, LANTERN_ROOT_SIZE) != 0;

    entry->status = *peer_status;
    entry->has_status = true;
    bool needs_block = !head_known;
    const char *needs_block_reason = NULL;
    if (!head_known)
    {
        needs_block_reason = "head unknown locally";
    }
    if (!needs_block && head_changed && peer_status->head.slot > local_slot)
    {
        needs_block = true;
        needs_block_reason = "remote head ahead of local slot";
    }
    struct lantern_log_metadata status_meta = {
        .validator = client->node_id,
        .peer = peer_copy[0] ? peer_copy : NULL,
    };
    if (needs_block)
    {
        lantern_log_info(
            "reqresp",
            &status_meta,
            "status needs block head_slot=%" PRIu64 " local_slot=%" PRIu64 " head_root=%s reason=%s",
            peer_status->head.slot,
            local_slot,
            head_hex[0] ? head_hex : "0x0",
            needs_block_reason ? needs_block_reason : "unspecified");
    }
    if (needs_block && !entry->requested_head)
    {
        uint64_t now_ms = monotonic_millis();
        uint64_t backoff_ms = blocks_request_backoff_ms(entry->consecutive_blocks_failures);
        if (entry->consecutive_blocks_failures == 0 && backoff_ms < LANTERN_BLOCKS_REQUEST_MIN_POLL_MS)
        {
            backoff_ms = LANTERN_BLOCKS_REQUEST_MIN_POLL_MS;
        }
        bool within_backoff = entry->last_blocks_request_ms != 0
            && now_ms < entry->last_blocks_request_ms + backoff_ms;
        if (!within_backoff)
        {
            entry->requested_head = true;
            entry->last_blocks_request_ms = now_ms;
            should_request = true;
        }
        else
        {
            uint64_t resume_ms = entry->last_blocks_request_ms + backoff_ms;
            uint64_t remaining_ms = resume_ms > now_ms ? (resume_ms - now_ms) : 0;
            lantern_log_debug(
                "reqresp",
                &(const struct lantern_log_metadata){
                    .validator = client->node_id,
                    .peer = peer_copy},
                "backing off blocks_by_root head=%s failures=%u remaining_ms=%" PRIu64,
                head_hex[0] ? head_hex : "0x0",
                entry->consecutive_blocks_failures,
                remaining_ms);
        }
    }
    else if (!needs_block)
    {
        lantern_log_trace(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_copy},
            "skipping blocks_by_root for known head slot=%" PRIu64 " root=%s",
            peer_status->head.slot,
            head_hex[0] ? head_hex : "0x0");
    }

    pthread_mutex_unlock(&client->status_lock);

    if (should_request)
    {
        if (lantern_client_schedule_blocks_request(client, peer_copy, &request_root, false) != 0)
        {
            lantern_client_on_blocks_request_complete(
                client,
                peer_copy,
                &request_root,
                LANTERN_BLOCKS_REQUEST_ABORTED);
        }
    }
}


/**
 * Adopt a peer's genesis root as our anchor.
 *
 * @param client        Client instance
 * @param peer_status   Peer status message
 * @param peer_id_text  Peer ID string for logging
 *
 * @note Thread safety: This function is thread-safe
 */
static void lantern_client_adopt_peer_genesis(
    struct lantern_client *client,
    const LanternStatusMessage *peer_status,
    const char *peer_id_text)
{
    if (!client || !peer_status || !client->has_fork_choice)
    {
        return;
    }

    LanternBlock anchor;
    memset(&anchor, 0, sizeof(anchor));
    anchor.slot = 0;
    anchor.proposer_index = 0;
    /* Use the peer's advertised head root as both state_root and hint so our fork-choice
       anchor matches the peer even if we cannot reproduce their SSZ state. */
    anchor.state_root = peer_status->head.root;
    /* empty body / zero attestations */
    LanternCheckpoint zero_cp = {.root = {{0}}, .slot = 0};

    if (lantern_fork_choice_set_anchor(
            &client->fork_choice,
            &anchor,
            &peer_status->finalized,
            &peer_status->finalized,
            &peer_status->head.root)
        != 0)
    {
        lantern_log_warn(
            "fork_choice",
            &(const struct lantern_log_metadata){.validator = client->node_id, .peer = peer_id_text},
            "failed to adopt peer genesis root");
        return;
    }

    (void)lantern_fork_choice_set_block_validator_count(
        &client->fork_choice,
        &peer_status->head.root,
        client->state.config.num_validators);
    client->genesis_fallback_used = false;

    char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&peer_status->head.root, head_hex, sizeof(head_hex));
    lantern_log_info(
        "fork_choice",
        &(const struct lantern_log_metadata){.validator = client->node_id, .peer = peer_id_text},
        "adopted peer genesis head_slot=0 root=%s",
        head_hex);
}


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
    enum lantern_blocks_request_outcome outcome)
{
    if (!client || !peer_id || !client->status_lock_initialized)
    {
        return;
    }
    const size_t peer_cap = sizeof(((struct lantern_peer_status_entry *)0)->peer_id);
    uint32_t failure_count = 0;
    bool entry_found = false;
    if (pthread_mutex_lock(&client->status_lock) != 0)
    {
        return;
    }
    for (size_t i = 0; i < client->peer_status_count; ++i)
    {
        struct lantern_peer_status_entry *entry = &client->peer_status_entries[i];
        if (strncmp(entry->peer_id, peer_id, peer_cap) == 0)
        {
            entry->requested_head = false;
            switch (outcome)
            {
            case LANTERN_BLOCKS_REQUEST_SUCCESS:
                entry->consecutive_blocks_failures = 0;
                break;
            case LANTERN_BLOCKS_REQUEST_FAILED:
                if (entry->consecutive_blocks_failures < UINT32_MAX)
                {
                    entry->consecutive_blocks_failures += 1;
                }
                break;
            case LANTERN_BLOCKS_REQUEST_ABORTED:
                entry->last_blocks_request_ms = 0;
                break;
            default:
                break;
            }
            if (outcome != LANTERN_BLOCKS_REQUEST_ABORTED && entry->last_blocks_request_ms == 0)
            {
                entry->last_blocks_request_ms = monotonic_millis();
            }
            failure_count = entry->consecutive_blocks_failures;
            entry_found = true;
            break;
        }
    }
    pthread_mutex_unlock(&client->status_lock);

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    root_hex[0] = '\0';
    if (request_root)
    {
        format_root_hex(request_root, root_hex, sizeof(root_hex));
    }
    const char *outcome_text = "unknown";
    switch (outcome)
    {
    case LANTERN_BLOCKS_REQUEST_SUCCESS:
        outcome_text = "success";
        break;
    case LANTERN_BLOCKS_REQUEST_FAILED:
        outcome_text = "failed";
        break;
    case LANTERN_BLOCKS_REQUEST_ABORTED:
        outcome_text = "aborted";
        break;
    default:
        break;
    }
    lantern_log_info(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = peer_id},
        "blocks_by_root complete outcome=%s root=%s entry_found=%s consecutive_failures=%" PRIu32,
        outcome_text,
        root_hex[0] ? root_hex : "0x0",
        entry_found ? "true" : "false",
        failure_count);

    if (request_root && !lantern_root_is_zero(request_root))
    {
        bool locked = lantern_client_lock_pending(client);
        if (locked)
        {
            for (size_t i = 0; i < client->pending_blocks.length; ++i)
            {
                struct lantern_pending_block *entry = &client->pending_blocks.items[i];
                if (memcmp(entry->parent_root.bytes, request_root->bytes, LANTERN_ROOT_SIZE) == 0)
                {
                    entry->parent_requested = false;
                }
            }
            lantern_client_unlock_pending(client, locked);
        }
        else
        {
            for (size_t i = 0; i < client->pending_blocks.length; ++i)
            {
                struct lantern_pending_block *entry = &client->pending_blocks.items[i];
                if (memcmp(entry->parent_root.bytes, request_root->bytes, LANTERN_ROOT_SIZE) == 0)
                {
                    entry->parent_requested = false;
                }
            }
        }
    }

    if (outcome == LANTERN_BLOCKS_REQUEST_SUCCESS && peer_id && peer_id[0] != '\0')
    {
        peer_id_t parsed_peer = {0};
        bool parsed = false;
        if (peer_id_create_from_string(peer_id, &parsed_peer) == PEER_ID_SUCCESS)
        {
            parsed = true;
        }
        request_status_now(client, parsed ? &parsed_peer : NULL, peer_id);
        if (parsed)
        {
            peer_id_destroy(&parsed_peer);
        }
    }
}


/* ============================================================================
 * Stream I/O Utilities
 * ============================================================================ */

/**
 * Write all bytes to a stream.
 *
 * @param stream  libp2p stream
 * @param data    Data to write
 * @param length  Number of bytes to write
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int stream_write_all(libp2p_stream_t *stream, const uint8_t *data, size_t length)
{
    if (!stream || (!data && length > 0))
    {
        return -1;
    }
    size_t offset = 0;
    while (offset < length)
    {
        ssize_t written = libp2p_stream_write(stream, data + offset, length - offset);
        if (written > 0)
        {
            offset += (size_t)written;
            continue;
        }
        if (written == (ssize_t)LIBP2P_ERR_AGAIN || written == (ssize_t)LIBP2P_ERR_TIMEOUT)
        {
            continue;
        }
        return -1;
    }
    return 0;
}


/**
 * Read a varint from a stream.
 *
 * @param stream     libp2p stream
 * @param out_value  Output value
 * @param meta       Log metadata
 * @param label      Label for logging
 * @param out_err    Output error code (may be NULL)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int read_stream_varint(
    libp2p_stream_t *stream,
    uint64_t *out_value,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err)
{
    if (!stream || !out_value)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_used = 0;
    uint64_t value = 0;
    ssize_t last_err = 0;

    while (header_used < sizeof(header))
    {
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, &header[header_used], 1);
        if (n == 1)
        {
            header_used += 1;
            size_t consumed = 0;
            if (unsigned_varint_decode(header, header_used, &value, &consumed) == UNSIGNED_VARINT_OK)
            {
                lantern_log_trace(
                    "reqresp",
                    meta,
                    "%s decoded length=%" PRIu64,
                    label ? label : "varint",
                    value);
                (void)libp2p_stream_set_deadline(stream, 0);
                *out_value = value;
                if (out_err)
                {
                    *out_err = 0;
                }
                return 0;
            }
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }
        if (n == 0 || n == (ssize_t)LIBP2P_ERR_EOF || n == (ssize_t)LIBP2P_ERR_CLOSED || n == (ssize_t)LIBP2P_ERR_RESET)
        {
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            break;
        }
        last_err = n;
        break;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    if (out_err)
    {
        *out_err = last_err == 0 ? LIBP2P_ERR_INTERNAL : last_err;
    }
    lantern_log_trace(
        "reqresp",
        meta,
        "%s decode failed err=%zd bytes=%zu",
        label ? label : "varint",
        last_err == 0 ? (ssize_t)LIBP2P_ERR_INTERNAL : last_err,
        header_used);
    return -1;
}


/**
 * Discard bytes from a stream.
 *
 * @param stream   libp2p stream
 * @param length   Number of bytes to discard
 * @param meta     Log metadata
 * @param label    Label for logging
 * @param out_err  Output error code (may be NULL)
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int discard_stream_bytes(
    libp2p_stream_t *stream,
    uint64_t length,
    const struct lantern_log_metadata *meta,
    const char *label,
    ssize_t *out_err)
{
    if (!stream)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }
    uint8_t buffer[256];
    uint64_t remaining = length;
    while (remaining > 0)
    {
        size_t chunk = remaining > sizeof(buffer) ? sizeof(buffer) : (size_t)remaining;
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, buffer, chunk);
        if (n > 0)
        {
            remaining -= (size_t)n;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (out_err)
        {
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_trace(
            "reqresp",
            meta,
            "%s discard failed err=%zd remaining=%" PRIu64,
            label ? label : "context",
            n,
            remaining);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);
    lantern_log_trace(
        "reqresp",
        meta,
        "%s discarded bytes=%" PRIu64,
        label ? label : "context",
        length);
    if (out_err)
    {
        *out_err = 0;
    }
    return 0;
}


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
    bool *response_code_pending)
{
    if (!stream || !out_data || !out_len)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }
    if (out_response_code)
    {
        *out_response_code = LANTERN_REQRESP_RESPONSE_SERVER_ERROR;
    }

    char peer_text[128];
    peer_text[0] = '\0';
    const peer_id_t *peer = libp2p_stream_remote_peer(stream);
    if (peer && peer_id_to_string(peer, PEER_ID_FMT_BASE58_LEGACY, peer_text, sizeof(peer_text)) < 0)
    {
        peer_text[0] = '\0';
    }
    const struct lantern_log_metadata meta = {.peer = peer_text[0] ? peer_text : NULL};

    (void)libp2p_stream_set_read_interest(stream, true);

    uint8_t response_code = 0;
    bool expect_code = response_code_pending
        ? *response_code_pending
        : ((protocol == LANTERN_REQRESP_PROTOCOL_STATUS) || (protocol == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT));
    bool legacy_no_code = !expect_code;
    ssize_t last_err = 0;
    uint8_t frame_code = 0;
    if (expect_code)
    {
        while (true)
        {
            (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
            ssize_t n = libp2p_stream_read(stream, &response_code, 1);
            if (n == 1)
            {
                frame_code = response_code;
                break;
            }
            if (n == (ssize_t)LIBP2P_ERR_AGAIN)
            {
                continue;
            }
            (void)libp2p_stream_set_deadline(stream, 0);
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            if (out_err)
            {
                *out_err = last_err;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "response code read failed err=%zd",
                last_err);
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (response_code > LANTERN_REQRESP_RESPONSE_SERVER_ERROR)
        {
            legacy_no_code = true;
            if (out_response_code)
            {
                *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "legacy response missing code, treating first byte as header (0x%02x)",
                (unsigned)response_code);
            lantern_log_info(
                "reqresp",
                &meta,
                "response legacy framing first_byte=0x%02x",
                (unsigned)response_code);
            if (service && peer_text[0] != '\0')
            {
#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
                lantern_reqresp_service_hint_peer_legacy(service, peer_text, 1);
#endif
            }
        }
        else
        {
            if (out_response_code)
            {
                *out_response_code = response_code;
            }
            frame_code = response_code;
            lantern_log_info(
                "reqresp",
                &meta,
                "response code=%u",
                (unsigned)response_code);
            if (service && peer_text[0] != '\0')
            {
#if defined(LANTERN_REQRESP_STATUS_PROTOCOL_LEGACY) || defined(LANTERN_REQRESP_BLOCKS_BY_ROOT_PROTOCOL_LEGACY)
                lantern_reqresp_service_hint_peer_legacy(service, peer_text, 0);
#endif
            }
        }
    }
    else
    {
        if (out_response_code)
        {
            *out_response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
        }
    }
    if (response_code_pending)
    {
        *response_code_pending = false;
    }

    uint8_t header_first_byte = 0;
    if (legacy_no_code && expect_code)
    {
        header_first_byte = response_code;
    }
    else
    {
        while (true)
        {
            (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
            ssize_t n = libp2p_stream_read(stream, &header_first_byte, 1);
            if (n == 1)
            {
                break;
            }
            if (n == (ssize_t)LIBP2P_ERR_AGAIN)
            {
                continue;
            }
            (void)libp2p_stream_set_deadline(stream, 0);
            last_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
            if (out_err)
            {
                *out_err = last_err;
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "response payload header read failed err=%zd",
                last_err);
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
    }

    lantern_log_trace(
        "reqresp",
        &meta,
        "response using varint framing code=0x%02x header_first=0x%02x",
        (unsigned)frame_code,
        (unsigned)header_first_byte);

    return read_varint_payload_chunk(
        stream,
        header_first_byte,
        out_data,
        out_len,
        out_err,
        &meta,
        "chunk");
}


/**
 * Read a payload chunk with varint header.
 *
 * @param stream      libp2p stream
 * @param first_byte  First byte already read
 * @param out_data    Output data buffer (caller must free)
 * @param out_len     Output data length
 * @param out_err     Output error code (may be NULL)
 * @param meta        Log metadata
 * @param label       Label for logging
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int read_varint_payload_chunk(
    libp2p_stream_t *stream,
    uint8_t first_byte,
    uint8_t **out_data,
    size_t *out_len,
    ssize_t *out_err,
    const struct lantern_log_metadata *meta,
    const char *label)
{
    if (!stream || !out_data || !out_len)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_NULL_PTR;
        }
        return -1;
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t used = 0;
    uint64_t payload_len = 0;
    size_t consumed = 0;
    header[used++] = first_byte;

    while (true)
    {
        if (unsigned_varint_decode(header, used, &payload_len, &consumed) == UNSIGNED_VARINT_OK)
        {
            break;
        }
        if (used == sizeof(header))
        {
            if (out_err)
            {
                *out_err = LIBP2P_ERR_INTERNAL;
            }
            lantern_log_warn(
                "reqresp",
                meta,
                "%s varint header exceeded limit",
                label ? label : "chunk");
            return -1;
        }
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, &header[used], 1);
        if (n == 1)
        {
            used += 1;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (out_err)
        {
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s header read failed err=%zd",
            label ? label : "chunk",
            n);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    char header_hex[(sizeof(header) * 2) + 1];
    header_hex[0] = '\0';
    if (lantern_bytes_to_hex(header, consumed, header_hex, sizeof(header_hex), 0) != 0)
    {
        header_hex[0] = '\0';
    }

    lantern_log_info(
        "reqresp",
        meta,
        "%s payload_len=%" PRIu64 " header_hex=%s",
        label ? label : "chunk",
        payload_len,
        header_hex[0] ? header_hex : "-");
    if (payload_len > 512)
    {
        lantern_log_warn(
            "reqresp",
            meta,
            "%s suspicious large payload_len=%" PRIu64 " header_hex=%s",
            label ? label : "chunk",
            payload_len,
            header_hex[0] ? header_hex : "-");
    }

    if (payload_len > LANTERN_REQRESP_MAX_CHUNK_BYTES || payload_len > SIZE_MAX)
    {
        if (out_err)
        {
            *out_err = LIBP2P_ERR_MSG_TOO_LARGE;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload too large=%" PRIu64,
            label ? label : "chunk",
            payload_len);
        return -1;
    }

    if (payload_len == 0)
    {
        *out_data = NULL;
        *out_len = 0;
        if (out_err)
        {
            *out_err = 0;
        }
        return 0;
    }

    size_t payload_size = (size_t)payload_len;
    uint8_t *buffer = (uint8_t *)malloc(payload_size);
    if (!buffer)
    {
        if (out_err)
        {
            *out_err = -ENOMEM;
        }
        lantern_log_error(
            "reqresp",
            meta,
            "%s payload allocation failed bytes=%zu",
            label ? label : "chunk",
            payload_size);
        return -1;
    }

    size_t collected = 0;
    while (collected < payload_size)
    {
        (void)libp2p_stream_set_deadline(stream, LANTERN_REQRESP_STALL_TIMEOUT_MS);
        ssize_t n = libp2p_stream_read(stream, buffer + collected, payload_size - collected);
        if (n > 0)
        {
            collected += (size_t)n;
            continue;
        }
        if (n == (ssize_t)LIBP2P_ERR_AGAIN)
        {
            continue;
        }
        (void)libp2p_stream_set_deadline(stream, 0);
        if (collected > 0)
        {
            char partial_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            size_t preview_len = collected < LANTERN_STATUS_PREVIEW_BYTES ? collected : LANTERN_STATUS_PREVIEW_BYTES;
            if (lantern_bytes_to_hex(buffer, preview_len, partial_hex, sizeof(partial_hex), 0) != 0)
            {
                partial_hex[0] = '\0';
            }
            lantern_log_trace(
                "reqresp",
                meta,
                "%s payload partial hex=%s%s",
                label ? label : "chunk",
                partial_hex[0] ? partial_hex : "-",
                (collected > preview_len) ? "..." : "");
        }
        free(buffer);
        if (out_err)
        {
            *out_err = n == 0 ? (ssize_t)LIBP2P_ERR_EOF : n;
        }
        lantern_log_warn(
            "reqresp",
            meta,
            "%s payload read failed err=%zd collected=%zu/%zu",
            label ? label : "chunk",
            n,
            collected,
            payload_size);
        return -1;
    }
    (void)libp2p_stream_set_deadline(stream, 0);

    *out_data = buffer;
    *out_len = payload_size;
    if (out_err)
    {
        *out_err = 0;
    }
    char payload_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
    payload_hex[0] = '\0';
    size_t preview = payload_size < LANTERN_STATUS_PREVIEW_BYTES ? payload_size : LANTERN_STATUS_PREVIEW_BYTES;
    if (preview > 0
        && lantern_bytes_to_hex(buffer, preview, payload_hex, sizeof(payload_hex), 0) != 0)
    {
        payload_hex[0] = '\0';
    }
    lantern_log_info(
        "reqresp",
        meta,
        "%s payload read complete bytes=%zu%s%s",
        label ? label : "chunk",
        payload_size,
        payload_hex[0] ? " hex=" : "",
        payload_hex[0] ? payload_hex : "");
    return 0;
}


/* ============================================================================
 * Block Request Operations
 * ============================================================================ */

/**
 * Free a block request context.
 *
 * @param ctx  Context to free
 *
 * @note Thread safety: This function is thread-safe
 */
static void block_request_ctx_free(struct block_request_ctx *ctx)
{
    if (!ctx)
    {
        return;
    }
    peer_id_destroy(&ctx->peer_id);
    free(ctx);
}


/**
 * Process a block chunk from a stream.
 *
 * @param ctx        Block request context
 * @param chunk      Compressed chunk data (will be freed)
 * @param chunk_len  Length of chunk
 * @param meta       Log metadata
 * @param saw_block  Output flag set if a block was processed
 * @return true on success, false on failure
 *
 * @note Thread safety: This function acquires state_lock via lantern_client_record_block
 */
static bool lantern_client_process_stream_block_chunk(
    struct block_request_ctx *ctx,
    uint8_t *chunk,
    size_t chunk_len,
    const struct lantern_log_metadata *meta,
    bool *saw_block)
{
    if (!chunk || chunk_len == 0)
    {
        free(chunk);
        return true;
    }
    if (!ctx)
    {
        free(chunk);
        return false;
    }
    size_t raw_len = 0;
    if (lantern_snappy_uncompressed_length(chunk, chunk_len, &raw_len) != LANTERN_SNAPPY_OK || raw_len == 0)
    {
        lantern_log_error(
            "reqresp",
            meta,
            "blocks_by_root chunk snappy length failed bytes=%zu",
            chunk_len);
        free(chunk);
        return false;
    }
    uint8_t *raw_block = (uint8_t *)malloc(raw_len);
    if (!raw_block)
    {
        lantern_log_error(
            "reqresp",
            meta,
            "blocks_by_root chunk allocation failed bytes=%zu",
            raw_len);
        free(chunk);
        return false;
    }
    size_t written = raw_len;
    if (lantern_snappy_decompress(chunk, chunk_len, raw_block, raw_len, &written) != LANTERN_SNAPPY_OK)
    {
        lantern_log_error(
            "reqresp",
            meta,
            "blocks_by_root chunk decompress failed bytes=%zu",
            chunk_len);
        free(raw_block);
        free(chunk);
        return false;
    }

    LanternSignedBlock streamed_block;
    lantern_signed_block_with_attestation_init(&streamed_block);
    if (lantern_ssz_decode_signed_block(&streamed_block, raw_block, written) != 0)
    {
        lantern_log_error(
            "reqresp",
            meta,
            "blocks_by_root chunk decode failed bytes=%zu",
            written);
        lantern_signed_block_with_attestation_reset(&streamed_block);
        free(raw_block);
        free(chunk);
        return false;
    }
    free(raw_block);

    LanternRoot computed = {{0}};
    if (lantern_hash_tree_root_block(&streamed_block.message.block, &computed) != 0)
    {
        lantern_log_warn(
            "reqresp",
            meta,
            "failed to hash streamed block slot=%" PRIu64,
            streamed_block.message.block.slot);
        lantern_signed_block_with_attestation_reset(&streamed_block);
        free(chunk);
        return true;
    }

    char computed_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&computed, computed_hex, sizeof(computed_hex));
    bool matches = memcmp(computed.bytes, ctx->root.bytes, LANTERN_ROOT_SIZE) == 0;
    lantern_log_info(
        "reqresp",
        meta,
        "streamed block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s match=%s attestations=%zu",
        streamed_block.message.block.slot,
        streamed_block.message.block.proposer_index,
        computed_hex[0] ? computed_hex : "0x0",
        matches ? "true" : "false",
        streamed_block.message.block.body.attestations.length);

    lantern_client_record_block(
        ctx->client,
        &streamed_block,
        &computed,
        ctx->peer_text[0] ? ctx->peer_text : NULL,
        "reqresp");
    lantern_signed_block_with_attestation_reset(&streamed_block);
    if (saw_block)
    {
        *saw_block = true;
    }
    free(chunk);
    return true;
}


/**
 * Worker thread for processing block requests.
 *
 * @param arg  block_request_worker_args pointer
 * @return NULL
 *
 * @note Thread safety: This function runs in a separate thread
 */
static void *block_request_worker(void *arg)
{
    struct block_request_worker_args *worker = (struct block_request_worker_args *)arg;
    if (!worker)
    {
        return NULL;
    }
    struct block_request_ctx *ctx = worker->ctx;
    libp2p_stream_t *stream = worker->stream;
    free(worker);
    if (!ctx || !stream)
    {
        if (stream)
        {
            libp2p_stream_free(stream);
        }
        block_request_ctx_free(ctx);
        return NULL;
    }

    struct lantern_log_metadata meta = {
        .validator = ctx->client ? ctx->client->node_id : NULL,
        .peer = ctx->peer_text[0] ? ctx->peer_text : NULL,
    };

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&ctx->root, root_hex, sizeof(root_hex));

    LanternBlocksByRootRequest request;
    lantern_blocks_by_root_request_init(&request);

    LanternBlocksByRootResponse response_msg;
    lantern_blocks_by_root_response_init(&response_msg);

    uint8_t *payload = NULL;
    uint8_t *response = NULL;
    bool request_success = false;
    bool schedule_legacy = false;
    bool attempt_legacy = false;
    struct lantern_client *legacy_client = NULL;
    LanternRoot legacy_root = ctx->root;
    char legacy_peer[sizeof(ctx->peer_text)];
    legacy_peer[0] = '\0';

    if (lantern_root_list_resize(&request.roots, 1) != 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to size blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }
    request.roots.items[0] = ctx->root;

    size_t raw_size = sizeof(uint32_t) + (request.roots.length * LANTERN_ROOT_SIZE);
    size_t max_payload = 0;
    if (lantern_snappy_max_compressed_size(raw_size, &max_payload) != LANTERN_SNAPPY_OK)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to compute snappy size for blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    payload = (uint8_t *)malloc(max_payload);
    if (!payload)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "out of memory building blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    size_t payload_len = 0;
    if (lantern_network_blocks_by_root_request_encode_snappy(&request, payload, max_payload, &payload_len, NULL) != 0
        || payload_len == 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    if (raw_size > 0)
    {
        uint8_t *plain_bytes = (uint8_t *)malloc(raw_size);
        size_t plain_written = raw_size;
        if (plain_bytes
            && lantern_network_blocks_by_root_request_encode(&request, plain_bytes, raw_size, &plain_written) == 0)
        {
            size_t plain_preview = plain_written < LANTERN_STATUS_PREVIEW_BYTES
                ? plain_written
                : LANTERN_STATUS_PREVIEW_BYTES;
            if (plain_preview > 0)
            {
                char plain_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
                if (lantern_bytes_to_hex(
                        plain_bytes,
                        plain_preview,
                        plain_hex,
                        sizeof(plain_hex),
                        0)
                    == 0)
                {
                    lantern_log_trace(
                        "reqresp",
                        &meta,
                        "blocks_by_root request roots_hex=%s%s",
                        plain_hex,
                        (plain_written > plain_preview) ? "..." : "");
                }
            }
        }
        free(plain_bytes);
    }

    size_t payload_preview = payload_len < LANTERN_STATUS_PREVIEW_BYTES ? payload_len : LANTERN_STATUS_PREVIEW_BYTES;
    if (payload_preview > 0)
    {
        char payload_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
        if (lantern_bytes_to_hex(
                payload,
                payload_preview,
                payload_hex,
                sizeof(payload_hex),
                0)
            == 0)
        {
            lantern_log_trace(
                "reqresp",
                &meta,
                "blocks_by_root request snappy_hex=%s%s",
                payload_hex,
                (payload_len > payload_preview) ? "..." : "");
        }
    }

    uint8_t header[LANTERN_REQRESP_HEADER_MAX_BYTES];
    size_t header_len = 0;
    if (unsigned_varint_encode(payload_len, header, sizeof(header), &header_len) != UNSIGNED_VARINT_OK)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode blocks_by_root header length=%zu",
            payload_len);
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    lantern_log_info(
        "reqresp",
        &meta,
        "sending %s request root=%s bytes=%zu",
        ctx->protocol_id,
        root_hex[0] ? root_hex : "0x0",
        payload_len);

    if (stream_write_all(stream, header, header_len) != 0 || stream_write_all(stream, payload, payload_len) != 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to write blocks_by_root request");
        schedule_legacy = !ctx->using_legacy;
        goto cleanup;
    }

    struct lantern_reqresp_service *service = ctx->client ? &ctx->client->reqresp : NULL;
    bool streaming_mode = !ctx->using_legacy;
    uint8_t *initial_chunk = NULL;
    size_t initial_chunk_len = 0;
    bool initial_chunk_pending = false;
    bool response_code_pending = true;
    bool saw_block = false;

    if (ctx->using_legacy)
    {
        size_t response_len = 0;
        ssize_t read_err = 0;
        uint8_t response_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
        if (lantern_reqresp_read_response_chunk(
                service,
                stream,
                LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
                &response,
                &response_len,
                &read_err,
                &response_code,
                NULL)
            != 0)
        {
            lantern_log_error(
                "reqresp",
                &meta,
                "failed to read blocks_by_root response err=%zd",
                read_err);
            schedule_legacy = !ctx->using_legacy;
            goto cleanup;
        }

        if (response_len > 0 && response)
        {
            size_t preview_len = response_len < LANTERN_STATUS_PREVIEW_BYTES ? response_len : LANTERN_STATUS_PREVIEW_BYTES;
            char response_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            if (lantern_bytes_to_hex(response, preview_len, response_hex, sizeof(response_hex), 0) != 0)
            {
                response_hex[0] = '\0';
            }
            lantern_log_trace(
                "reqresp",
                &meta,
                "blocks_by_root raw payload_len=%zu%s%s",
                response_len,
                preview_len > 0 ? " hex=" : "",
                preview_len > 0 ? response_hex : "");
        }
        else
        {
            lantern_log_trace(
                "reqresp",
                &meta,
                "blocks_by_root raw payload_len=%zu (empty)",
                response_len);
        }

        if (response_code != LANTERN_REQRESP_RESPONSE_SUCCESS)
        {
            lantern_log_error(
                "reqresp",
                &meta,
                "blocks_by_root response returned code=%u payload_len=%zu",
                (unsigned)response_code,
                response_len);
            schedule_legacy = !ctx->using_legacy;
            goto cleanup;
        }

        if (response_len == 0 || !response)
        {
            lantern_log_info(
                "reqresp",
                &meta,
                "received 0 block(s) via %s (empty payload)",
                ctx->protocol_id);
            request_success = true;
            goto cleanup;
        }

        if (lantern_network_blocks_by_root_response_decode_snappy(&response_msg, response, response_len) != 0)
        {
            size_t preview_len = response_len < LANTERN_STATUS_PREVIEW_BYTES ? response_len : LANTERN_STATUS_PREVIEW_BYTES;
            char response_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            if (preview_len > 0
                && lantern_bytes_to_hex(response, preview_len, response_hex, sizeof(response_hex), 0) != 0)
            {
                response_hex[0] = '\0';
            }
            lantern_log_error(
                "reqresp",
                &meta,
                "failed to decode blocks_by_root response bytes=%zu%s%s",
                response_len,
                preview_len > 0 ? " hex=" : "",
                preview_len > 0 ? response_hex : "");
            if (response && response_len > 0)
            {
                char dump_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
                format_root_hex(&ctx->root, dump_root_hex, sizeof(dump_root_hex));
                const char *suffix = dump_root_hex;
                if (suffix[0] == '0' && (suffix[1] == 'x' || suffix[1] == 'X'))
                {
                    suffix += 2;
                }
                char dump_path[256];
                if (snprintf(dump_path, sizeof(dump_path), "/data/lantern_blocks_by_root_failed_%s.bin", suffix) > 0)
                {
                    FILE *dump = fopen(dump_path, "wb");
                    if (dump)
                    {
                        (void)fwrite(response, 1, response_len, dump);
                        fclose(dump);
                    }
                }
            }
            if (!streaming_mode && response && response_len > 0)
            {
                lantern_log_info(
                    "reqresp",
                    &meta,
                    "legacy decode failed; interpreting payload as streaming chunk");
                streaming_mode = true;
                response_code_pending = false;
                initial_chunk = response;
                initial_chunk_len = response_len;
                response = NULL;
                initial_chunk_pending = true;
            }
            else
            {
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
        }
        else
        {
            lantern_log_info(
                "reqresp",
                &meta,
                "received %zu block(s) via %s",
                response_msg.length,
                ctx->protocol_id);

            for (size_t i = 0; i < response_msg.length; ++i)
            {
                LanternRoot computed = {{0}};
                if (lantern_hash_tree_root_block(&response_msg.blocks[i].message.block, &computed) != 0)
                {
                    lantern_log_warn(
                        "reqresp",
                        &meta,
                        "failed to hash block index=%zu slot=%" PRIu64,
                        i,
                        response_msg.blocks[i].message.slot);
                    continue;
                }
                char computed_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
                format_root_hex(&computed, computed_hex, sizeof(computed_hex));
                bool matches = memcmp(computed.bytes, ctx->root.bytes, LANTERN_ROOT_SIZE) == 0;
                lantern_log_info(
                    "reqresp",
                    &meta,
                    "block index=%zu slot=%" PRIu64 " proposer=%" PRIu64 " root=%s match=%s attestations=%zu",
                    i,
                    response_msg.blocks[i].message.slot,
                    response_msg.blocks[i].message.proposer_index,
                    computed_hex[0] ? computed_hex : "0x0",
                    matches ? "true" : "false",
                    response_msg.blocks[i].message.body.attestations.length);

                lantern_client_record_block(
                    ctx->client,
                    &response_msg.blocks[i],
                    &computed,
                    ctx->peer_text[0] ? ctx->peer_text : NULL,
                    "reqresp");
            }

            request_success = (response_msg.length > 0);
            if (!streaming_mode)
            {
                goto cleanup;
            }
        }
    }

    if (streaming_mode)
    {
        if (initial_chunk_pending)
        {
            if (!lantern_client_process_stream_block_chunk(ctx, initial_chunk, initial_chunk_len, &meta, &saw_block))
            {
                initial_chunk = NULL;
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
            initial_chunk = NULL;
            initial_chunk_pending = false;
        }

        while (true)
        {
            uint8_t *chunk = NULL;
            size_t chunk_len = 0;
            ssize_t read_err = 0;
            uint8_t chunk_code = LANTERN_REQRESP_RESPONSE_SUCCESS;
            int chunk_rc = lantern_reqresp_read_response_chunk(
                service,
                stream,
                LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
                &chunk,
                &chunk_len,
                &read_err,
                &chunk_code,
                &response_code_pending);
            if (chunk_rc != 0)
            {
                if (read_err == (ssize_t)LIBP2P_ERR_EOF)
                {
                    read_err = 0;
                    break;
                }
                lantern_log_error(
                    "reqresp",
                    &meta,
                    "failed to read blocks_by_root chunk err=%zd",
                    read_err);
                free(chunk);
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
            if (chunk_code != LANTERN_REQRESP_RESPONSE_SUCCESS)
            {
                lantern_log_error(
                    "reqresp",
                    &meta,
                    "blocks_by_root chunk returned code=%u payload_len=%zu",
                    (unsigned)chunk_code,
                    chunk_len);
                free(chunk);
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
            if (chunk_len == 0 || !chunk)
            {
                free(chunk);
                break;
            }

            if (!lantern_client_process_stream_block_chunk(ctx, chunk, chunk_len, &meta, &saw_block))
            {
                schedule_legacy = !ctx->using_legacy;
                goto cleanup;
            }
        }
        request_success = saw_block;
    }

cleanup:
    if (!request_success && schedule_legacy && ctx->client && !ctx->using_legacy && ctx->peer_text[0] && !attempt_legacy)
    {
        attempt_legacy = true;
        legacy_client = ctx->client;
        legacy_root = ctx->root;
        strncpy(legacy_peer, ctx->peer_text, sizeof(legacy_peer) - 1u);
        legacy_peer[sizeof(legacy_peer) - 1u] = '\0';
        char retry_root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(&legacy_root, retry_root_hex, sizeof(retry_root_hex));
        lantern_log_info(
            "reqresp",
            &meta,
            "retrying blocks_by_root with legacy protocol root=%s",
            retry_root_hex[0] ? retry_root_hex : "0x0");
    }
    lantern_blocks_by_root_response_reset(&response_msg);
    if (initial_chunk)
    {
        free(initial_chunk);
    }
    free(response);
    free(payload);
    lantern_blocks_by_root_request_reset(&request);
    libp2p_stream_free(stream);
    if (ctx->client)
    {
        lantern_client_on_blocks_request_complete(
            ctx->client,
            ctx->peer_text,
            &ctx->root,
            request_success ? LANTERN_BLOCKS_REQUEST_SUCCESS : LANTERN_BLOCKS_REQUEST_FAILED);
    }

    block_request_ctx_free(ctx);

    if (attempt_legacy && legacy_client && legacy_peer[0])
    {
        if (lantern_client_schedule_blocks_request(legacy_client, legacy_peer, &legacy_root, true) != 0)
        {
            lantern_client_on_blocks_request_complete(
                legacy_client,
                legacy_peer,
                &legacy_root,
                LANTERN_BLOCKS_REQUEST_FAILED);
        }
    }
    return NULL;
}


/**
 * Callback when a block request stream opens.
 *
 * @param stream     libp2p stream
 * @param user_data  Block request context
 * @param err        Error code (0 on success)
 *
 * @note Thread safety: This function is called from libp2p thread
 */
static void block_request_on_open(libp2p_stream_t *stream, void *user_data, int err)
{
    struct block_request_ctx *ctx = (struct block_request_ctx *)user_data;
    if (!ctx)
    {
        if (stream)
        {
            libp2p_stream_free(stream);
        }
        return;
    }
    struct lantern_log_metadata meta = {
        .validator = ctx->client ? ctx->client->node_id : NULL,
        .peer = ctx->peer_text[0] ? ctx->peer_text : NULL,
    };

    lantern_log_info(
        "reqresp",
        &meta,
        "block request stream opened protocol=%s err=%d",
        ctx->protocol_id ? ctx->protocol_id : "(unknown)",
        err);

    if (err != 0 || !stream)
    {
        lantern_log_warn(
            "reqresp",
            &meta,
            "failed to open %s stream err=%d",
            ctx->protocol_id,
            err);
        bool attempted = false;
        if (!ctx->using_legacy && ctx->client && ctx->peer_text[0])
        {
            LanternRoot root = ctx->root;
            struct lantern_client *client = ctx->client;
            char peer_copy[sizeof(ctx->peer_text)];
            strncpy(peer_copy, ctx->peer_text, sizeof(peer_copy) - 1u);
            peer_copy[sizeof(peer_copy) - 1u] = '\0';
            lantern_log_info(
                "reqresp",
                &meta,
                "retrying blocks_by_root with legacy protocol after dial failure");
            if (stream)
            {
                libp2p_stream_free(stream);
            }
            block_request_ctx_free(ctx);
            attempted = true;
            if (lantern_client_schedule_blocks_request(client, peer_copy, &root, true) != 0)
            {
                lantern_client_on_blocks_request_complete(
                    client,
                    peer_copy,
                    &root,
                    LANTERN_BLOCKS_REQUEST_FAILED);
            }
        }
        if (!attempted)
        {
            if (ctx->client)
            {
                lantern_client_on_blocks_request_complete(
                    ctx->client,
                    ctx->peer_text,
                    &ctx->root,
                    LANTERN_BLOCKS_REQUEST_FAILED);
            }
            if (stream)
            {
                libp2p_stream_free(stream);
            }
            block_request_ctx_free(ctx);
        }
        return;
    }

    struct block_request_worker_args *worker = (struct block_request_worker_args *)malloc(sizeof(*worker));
    if (!worker)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to allocate worker for %s stream",
            ctx->protocol_id);
        libp2p_stream_free(stream);
        if (ctx->client)
        {
            lantern_client_on_blocks_request_complete(
                ctx->client,
                ctx->peer_text,
                &ctx->root,
                LANTERN_BLOCKS_REQUEST_FAILED);
        }
        block_request_ctx_free(ctx);
        return;
    }
    worker->ctx = ctx;
    worker->stream = stream;

    pthread_t thread;
    if (pthread_create(&thread, NULL, block_request_worker, worker) != 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to spawn blocks_by_root worker");
        free(worker);
        libp2p_stream_free(stream);
        if (ctx->client)
        {
            lantern_client_on_blocks_request_complete(
                ctx->client,
                ctx->peer_text,
                &ctx->root,
                LANTERN_BLOCKS_REQUEST_FAILED);
        }
        block_request_ctx_free(ctx);
        return;
    }
    lantern_log_info(
        "reqresp",
        &meta,
        "spawned blocks_by_root worker protocol=%s",
        ctx->protocol_id ? ctx->protocol_id : "(unknown)");
    pthread_detach(thread);
}


/**
 * Schedule a blocks_by_root request to a peer.
 *
 * @param client        Client instance
 * @param peer_id_text  Peer ID string
 * @param root          Block root to request
 * @param use_legacy    True to use legacy protocol
 * @return 0 on success, -1 on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static int lantern_client_schedule_blocks_request(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *root,
    bool use_legacy)
{
    if (!client || !peer_id_text || !root || !client->network.host)
    {
        return -1;
    }
    if (lantern_root_is_zero(root))
    {
        return -1;
    }

    if (client->debug_disable_block_requests)
    {
        lantern_log_debug(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id_text},
            "skipping blocks_by_root dial for test run");
        lantern_client_on_blocks_request_complete(
            client,
            peer_id_text,
            root,
            LANTERN_BLOCKS_REQUEST_ABORTED);
        return 0;
    }

    struct block_request_ctx *ctx = (struct block_request_ctx *)calloc(1, sizeof(*ctx));
    if (!ctx)
    {
        return -1;
    }
    ctx->client = client;
    ctx->root = *root;
    strncpy(ctx->peer_text, peer_id_text, sizeof(ctx->peer_text) - 1);
    ctx->peer_text[sizeof(ctx->peer_text) - 1] = '\0';
#if defined(LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID_LEGACY)
    bool prefer_legacy = false;
    if (!use_legacy && ctx->peer_text[0] != '\0')
    {
        prefer_legacy = lantern_reqresp_service_peer_prefers_legacy(&client->reqresp, ctx->peer_text) != 0;
    }
    bool effective_legacy = use_legacy || prefer_legacy;
    ctx->protocol_id =
        effective_legacy ? LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID_LEGACY : LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID;
    ctx->using_legacy = effective_legacy;
#else
    (void)use_legacy;
    ctx->protocol_id = LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID;
    ctx->using_legacy = false;
#endif

    if (peer_id_create_from_string(peer_id_text, &ctx->peer_id) != PEER_ID_SUCCESS)
    {
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id_text},
            "failed to parse peer id for blocks_by_root request");
        block_request_ctx_free(ctx);
        return -1;
    }

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(root, root_hex, sizeof(root_hex));
    lantern_log_info(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = ctx->peer_text[0] ? ctx->peer_text : NULL},
        "dialing peer for %s root=%s",
        ctx->protocol_id,
        root_hex[0] ? root_hex : "0x0");

    int rc = libp2p_host_open_stream_async(
        client->network.host,
        &ctx->peer_id,
        ctx->protocol_id,
        block_request_on_open,
        ctx);
    if (rc != 0)
    {
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = ctx->peer_text[0] ? ctx->peer_text : NULL},
            "libp2p open stream failed rc=%d",
            rc);
        block_request_ctx_free(ctx);
        return -1;
    }
    return 0;
}
