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
#include <stdio.h>
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
 * 2. Reads response in legacy or streaming mode
 * 3. Decodes and imports received blocks
 * 4. Falls back to legacy protocol on streaming failures
 *
 * Legacy vs Streaming modes:
 * - Legacy: Single response with all blocks in one SSZ container
 * - Streaming: Multiple response chunks, one block per chunk
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

    ssize_t write_err = 0;
    if (stream_write_all(stream, header, header_len, &write_err) != 0
        || stream_write_all(stream, payload, payload_len, &write_err) != 0)
    {
        lantern_log_error(
            "reqresp",
            &meta,
            "failed to write blocks_by_root request err=%zd",
            write_err);
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
 * On dial failure with the modern protocol, automatically retries
 * with the legacy protocol for backwards compatibility.
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


/* ============================================================================
 * Public Block Request API
 * ============================================================================ */

/**
 * Schedule a blocks_by_root request to a peer.
 *
 * @spec subspecs/networking/reqresp/message.py - BlocksByRoot protocol
 *
 * Initiates an async stream dial to the peer for the blocks_by_root
 * protocol. The request will be processed in block_request_on_open
 * when the dial completes.
 *
 * Protocol selection:
 * - Modern protocol preferred by default
 * - Legacy protocol used if peer prefers it or use_legacy is true
 * - Automatic fallback to legacy on modern protocol failures
 *
 * @param client        Client instance
 * @param peer_id_text  Peer ID string
 * @param root          Block root to request
 * @param use_legacy    True to use legacy protocol
 * @return 0 on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if any parameter is NULL, the peer ID is invalid, or the root is zero
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_NETWORK if stream dialing fails or networking is unavailable
 *
 * @note Thread safety: This function is thread-safe
 */
int lantern_client_schedule_blocks_request(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *root,
    bool use_legacy)
{
    if (!client || !peer_id_text || !root)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (!client->network.host)
    {
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    if (lantern_root_is_zero(root))
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
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
        return LANTERN_CLIENT_ERR_ALLOC;
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
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
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
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    return 0;
}
