/**
 * @file client_reqresp_blocks.c
 * @brief Block request operations for reqresp protocol
 *
 * @spec subspecs/networking/reqresp in tools/leanSpec
 *
 * Implements blocks_by_root request handling including request encoding,
 * response processing, and block import coordination.
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
#include "lantern/support/strings.h"
#include "lantern/support/log.h"

#include "libp2p/errors.h"
#include "libp2p/host.h"
#include "libp2p/stream.h"
#include "multiformats/unsigned_varint/unsigned_varint.h"
#include "peer_id/peer_id.h"

#include <inttypes.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>


/* ============================================================================
 * Constants
 * ============================================================================ */

/* ============================================================================
 * Forward Declarations
 * ============================================================================ */

static void block_request_ctx_free(struct block_request_ctx *ctx);
static bool lantern_client_process_stream_block_chunk(
    struct block_request_ctx *ctx,
    uint8_t *chunk,
    size_t chunk_len,
    const struct lantern_log_metadata *meta,
    bool *saw_block);
static void *block_request_worker(void *arg);
static void block_request_on_open(libp2p_stream_t *stream, void *user_data, int err);
static int schedule_blocks_request_batch(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *roots,
    const uint32_t *depths,
    size_t root_count);


/* ============================================================================
 * Block Request Context Management
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
    free(ctx->roots);
    free(ctx->depths);
    free(ctx);
}

/* ============================================================================
 * Block Chunk Processing
 * ============================================================================ */

/**
 * Process a block chunk from a stream.
 *
 * @spec subspecs/containers/block/block.py - SignedBlock decoding
 * @spec subspecs/ssz - SSZ deserialization
 *
 * Decompresses a snappy-encoded block chunk, decodes the SSZ block,
 * validates the block root, and records it to the client state.
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
    int snappy_len_rc = lantern_snappy_uncompressed_length(chunk, chunk_len, &raw_len);
    if (snappy_len_rc != LANTERN_SNAPPY_OK || raw_len == 0)
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
    int snappy_rc = lantern_snappy_decompress(chunk, chunk_len, raw_block, raw_len, &written);
    if (snappy_rc != LANTERN_SNAPPY_OK)
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
    int decode_rc = lantern_ssz_decode_signed_block(&streamed_block, raw_block, written);
    if (decode_rc != 0)
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
    bool matches = false;
    uint32_t backfill_depth = 0;
    if (ctx->roots && ctx->root_count > 0)
    {
        for (size_t i = 0; i < ctx->root_count; ++i)
        {
            if (memcmp(computed.bytes, ctx->roots[i].bytes, LANTERN_ROOT_SIZE) == 0)
            {
                matches = true;
                if (ctx->depths)
                {
                    backfill_depth = ctx->depths[i];
                }
                break;
            }
        }
    }
    bool quiet_log = ctx->client && ctx->client->sync_in_progress;
    if (quiet_log)
    {
        lantern_log_debug(
            "reqresp",
            meta,
            "streamed block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s match=%s depth=%" PRIu32
            " attestations=%zu",
            streamed_block.message.block.slot,
            streamed_block.message.block.proposer_index,
            computed_hex[0] ? computed_hex : "0x0",
            matches ? "true" : "false",
            backfill_depth,
            streamed_block.message.block.body.attestations.length);
    }
    else
    {
        lantern_log_info(
            "reqresp",
            meta,
            "streamed block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s match=%s depth=%" PRIu32
            " attestations=%zu",
            streamed_block.message.block.slot,
            streamed_block.message.block.proposer_index,
            computed_hex[0] ? computed_hex : "0x0",
            matches ? "true" : "false",
            backfill_depth,
            streamed_block.message.block.body.attestations.length);
    }

    lantern_client_record_block(
        ctx->client,
        &streamed_block,
        &computed,
        ctx->peer_text[0] ? ctx->peer_text : NULL,
        "reqresp",
        backfill_depth,
        true);
    lantern_signed_block_with_attestation_reset(&streamed_block);
    if (saw_block)
    {
        *saw_block = true;
    }
    free(chunk);
    return true;
}


/* ============================================================================
 * Block Request Worker Thread
 * ============================================================================ */

/**
 * Worker thread for processing block requests.
 *
 * @spec subspecs/networking/reqresp/message.py - BlocksByRoot request/response
 *
 * Handles the complete blocks_by_root request lifecycle:
 * 1. Encodes and sends the request (SSZ + snappy + varint header)
 * 2. Reads response chunks (response code + varint payload)
 * 3. Decodes and imports received blocks
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
    if (!ctx->roots || ctx->root_count == 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "blocks_by_root request missing roots");
        goto cleanup;
    }
    format_root_hex(&ctx->roots[0], root_hex, sizeof(root_hex));

    LanternBlocksByRootRequest request;
    lantern_blocks_by_root_request_init(&request);

    uint8_t *raw_request = NULL;
    uint8_t *payload = NULL;
    enum lantern_blocks_request_outcome outcome = LANTERN_BLOCKS_REQUEST_FAILED;
    bool completed = false;

    if (lantern_root_list_resize(&request.roots, ctx->root_count) != 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to size blocks_by_root request");
        goto cleanup;
    }
    for (size_t i = 0; i < ctx->root_count; ++i)
    {
        request.roots.items[i] = ctx->roots[i];
    }

    size_t raw_size = request.roots.length * LANTERN_ROOT_SIZE;
    raw_request = (uint8_t *)malloc(raw_size > 0 ? raw_size : 1u);
    if (!raw_request)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "out of memory building blocks_by_root request");
        goto cleanup;
    }

    size_t raw_written = 0;
    if (lantern_network_blocks_by_root_request_encode(&request, raw_request, raw_size, &raw_written) != 0
        || raw_written == 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode blocks_by_root request");
        goto cleanup;
    }

    size_t max_payload = 0;
    int max_rc = lantern_snappy_max_compressed_size(raw_written, &max_payload);
    if (max_rc != LANTERN_SNAPPY_OK)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to compute snappy size for blocks_by_root request");
        goto cleanup;
    }

    payload = (uint8_t *)malloc(max_payload > 0 ? max_payload : 1u);
    if (!payload)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "out of memory building blocks_by_root request");
        goto cleanup;
    }

    size_t payload_len = 0;
    int snappy_rc = lantern_snappy_compress(raw_request, raw_written, payload, max_payload, &payload_len);
    if (snappy_rc != LANTERN_SNAPPY_OK || payload_len == 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode blocks_by_root request");
        goto cleanup;
    }

    if (raw_written > 0)
    {
        size_t plain_preview = raw_written < LANTERN_STATUS_PREVIEW_BYTES
            ? raw_written
            : LANTERN_STATUS_PREVIEW_BYTES;
        if (plain_preview > 0)
        {
            char plain_hex[(LANTERN_STATUS_PREVIEW_BYTES * 2u) + 1u];
            if (lantern_bytes_to_hex(
                    raw_request,
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
                    (raw_written > plain_preview) ? "..." : "");
            }
        }
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
    if (unsigned_varint_encode(raw_written, header, sizeof(header), &header_len) != UNSIGNED_VARINT_OK)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to encode blocks_by_root header length=%zu",
            raw_written);
        goto cleanup;
    }

    lantern_log_debug(
        "reqresp",
        &meta,
        "sending %s request roots=%zu first_root=%s bytes=%zu",
        ctx->protocol_id,
        ctx->root_count,
        root_hex[0] ? root_hex : "0x0",
        payload_len);

    ssize_t write_err = 0;
    if (stream_write_all(stream, header, header_len, &write_err) != 0
        || stream_write_all(stream, payload, payload_len, &write_err) != 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to write blocks_by_root request err=%zd",
            write_err);
        goto cleanup;
    }

    struct lantern_reqresp_service *service = ctx->client ? &ctx->client->reqresp : NULL;
    bool saw_block = false;

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
            NULL);
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
            goto cleanup;
        }
        if (chunk_len == 0 || !chunk)
        {
            free(chunk);
            break;
        }

        if (!lantern_client_process_stream_block_chunk(ctx, chunk, chunk_len, &meta, &saw_block))
        {
            goto cleanup;
        }
    }
    completed = true;
    outcome = saw_block ? LANTERN_BLOCKS_REQUEST_SUCCESS : LANTERN_BLOCKS_REQUEST_EMPTY;

cleanup:
    free(payload);
    free(raw_request);
    lantern_blocks_by_root_request_reset(&request);
    libp2p_stream_free(stream);
    if (ctx->client)
    {
        lantern_client_on_blocks_request_complete_batch(
            ctx->client,
            ctx->peer_text,
            ctx->roots,
            ctx->root_count,
            completed ? outcome : LANTERN_BLOCKS_REQUEST_FAILED);
    }

    block_request_ctx_free(ctx);
    return NULL;
}


/* ============================================================================
 * Stream Open Callback
 * ============================================================================ */

/**
 * Callback when a block request stream opens.
 *
 * @spec subspecs/networking/reqresp - Stream lifecycle
 *
 * Called by libp2p when the stream dial completes. Spawns a worker
 * thread to handle the request/response exchange.
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

    lantern_log_debug(
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
        if (ctx->client)
        {
            lantern_client_on_blocks_request_complete_batch(
                ctx->client,
                ctx->peer_text,
                ctx->roots,
                ctx->root_count,
                LANTERN_BLOCKS_REQUEST_FAILED);
        }
        if (stream)
        {
            libp2p_stream_free(stream);
        }
        block_request_ctx_free(ctx);
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
            lantern_client_on_blocks_request_complete_batch(
                ctx->client,
                ctx->peer_text,
                ctx->roots,
                ctx->root_count,
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
            lantern_client_on_blocks_request_complete_batch(
                ctx->client,
                ctx->peer_text,
                ctx->roots,
                ctx->root_count,
                LANTERN_BLOCKS_REQUEST_FAILED);
        }
        block_request_ctx_free(ctx);
        return;
    }
    lantern_log_debug(
        "reqresp",
        &meta,
        "spawned blocks_by_root worker protocol=%s",
        ctx->protocol_id ? ctx->protocol_id : "(unknown)");
    pthread_detach(thread);
}


/* ============================================================================
 * Public Block Request API
 * ============================================================================ */

static int schedule_blocks_request_batch(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *roots,
    const uint32_t *depths,
    size_t root_count)
{
    if (!client || !peer_id_text || !roots || root_count == 0)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (root_count > LANTERN_MAX_BLOCKS_PER_REQUEST)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (!client->network.host)
    {
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    for (size_t i = 0; i < root_count; ++i)
    {
        if (lantern_root_is_zero(&roots[i]))
        {
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
    }

    if (client->debug_disable_block_requests)
    {
        lantern_log_debug(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id_text},
            "skipping blocks_by_root dial for test run");
        lantern_client_on_blocks_request_complete_batch(
            client,
            peer_id_text,
            roots,
            root_count,
            LANTERN_BLOCKS_REQUEST_ABORTED);
        return 0;
    }

    struct block_request_ctx *ctx = (struct block_request_ctx *)calloc(1, sizeof(*ctx));
    if (!ctx)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    ctx->roots = (LanternRoot *)calloc(root_count, sizeof(*ctx->roots));
    if (!ctx->roots)
    {
        block_request_ctx_free(ctx);
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    ctx->depths = (uint32_t *)calloc(root_count, sizeof(*ctx->depths));
    if (!ctx->depths)
    {
        block_request_ctx_free(ctx);
        return LANTERN_CLIENT_ERR_ALLOC;
    }

    ctx->client = client;
    ctx->root_count = root_count;
    ctx->protocol_id = LANTERN_BLOCKS_BY_ROOT_PROTOCOL_ID;
    strncpy(ctx->peer_text, peer_id_text, sizeof(ctx->peer_text) - 1);
    ctx->peer_text[sizeof(ctx->peer_text) - 1] = '\0';

    for (size_t i = 0; i < root_count; ++i)
    {
        ctx->roots[i] = roots[i];
        if (depths)
        {
            ctx->depths[i] = depths[i];
        }
    }

    if (peer_id_create_from_string(peer_id_text, &ctx->peer_id) != PEER_ID_SUCCESS)
    {
        lantern_log_warn(
            "reqresp",
            &(const struct lantern_log_metadata){
                .validator = client->node_id,
                .peer = peer_id_text},
            "failed to parse peer id for blocks_by_root request");
        block_request_ctx_free(ctx);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
    format_root_hex(&roots[0], root_hex, sizeof(root_hex));
    lantern_log_debug(
        "reqresp",
        &(const struct lantern_log_metadata){
            .validator = client->node_id,
            .peer = ctx->peer_text[0] ? ctx->peer_text : NULL},
        "dialing peer for %s roots=%zu first_root=%s",
        ctx->protocol_id,
        root_count,
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
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    return 0;
}

/**
 * Schedule a blocks_by_root request to a peer.
 *
 * @spec subspecs/networking/reqresp/message.py - BlocksByRoot protocol
 *
 * Initiates an async stream dial to the peer for the blocks_by_root
 * protocol. The request will be processed in block_request_on_open
 * when the dial completes.
 *
 * @param client        Client instance
 * @param peer_id_text  Peer ID string
 * @param roots         Block roots to request
 * @param depths        Backfill depth per root (may be NULL for zeros)
 * @param root_count    Number of roots
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
    size_t root_count)
{
    return schedule_blocks_request_batch(client, peer_id_text, roots, depths, root_count);
}

/**
 * Schedule a single-root blocks_by_root request to a peer.
 *
 * @spec subspecs/networking/reqresp/message.py - BlocksByRoot protocol
 *
 * @param client         Client instance
 * @param peer_id_text   Peer ID string
 * @param root           Block root to request
 * @param backfill_depth Backfill depth for the requested root
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if parameters are invalid, the peer ID is invalid, or the root is zero
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_NETWORK if stream dialing fails or networking is unavailable
 *
 * @note Thread safety: This function is thread-safe
 */
int lantern_client_schedule_blocks_request(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *root,
    uint32_t backfill_depth)
{
    if (!root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    const uint32_t depth = backfill_depth;
    return schedule_blocks_request_batch(client, peer_id_text, root, &depth, 1u);
}
