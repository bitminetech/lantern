#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"
#include "../../external/c-lean-libp2p/src/libp2p/libp2p_host_internal.h"

/* Exercise static exchange handling without adding test hooks to production code. */
#define lantern_reqresp_service_init lantern_reqresp_service_init_for_test
#define lantern_reqresp_service_reset lantern_reqresp_service_reset_for_test
#define lantern_reqresp_service_cancel_blocks_by_range \
    lantern_reqresp_service_cancel_blocks_by_range_for_test
#define lantern_reqresp_service_request_status lantern_reqresp_service_request_status_for_test
#define lantern_reqresp_service_request_blocks lantern_reqresp_service_request_blocks_for_test
#define lantern_reqresp_service_request_blocks_by_range lantern_reqresp_service_request_blocks_by_range_for_test
#define lantern_reqresp_service_start lantern_reqresp_service_start_for_test
#include "../../src/networking/reqresp_service.c"
#undef lantern_reqresp_service_init
#undef lantern_reqresp_service_reset
#undef lantern_reqresp_service_cancel_blocks_by_range
#undef lantern_reqresp_service_request_status
#undef lantern_reqresp_service_request_blocks
#undef lantern_reqresp_service_request_blocks_by_range
#undef lantern_reqresp_service_start

#define CHECK(cond)                                                                  \
    do {                                                                             \
        if (!(cond)) {                                                               \
            fprintf(stderr, "check failed: %s (%s:%d)\n", #cond, __FILE__, __LINE__); \
            abort();                                                                 \
        }                                                                            \
    } while (0)

struct test_blocks_context {
    size_t handled_count;
    int handle_result;
    int complete_called;
    enum lantern_reqresp_blocks_request_result complete_result;
};

struct test_range_serve_context {
    size_t collect_called;
    uint64_t start_slot;
    uint64_t count;
    size_t current_slot_called;
    uint64_t current_slot;
};

struct test_transport {
    libp2p_host_err_t read_result;
    const uint8_t *read_data;
    size_t read_len;
    size_t read_offset;
    size_t reset_called;
};

static libp2p_host_err_t test_transport_stream_read(
    void *transport,
    void *stream,
    uint8_t *out,
    size_t out_len,
    size_t *read_len,
    int *fin) {
    (void)stream;
    (void)out;
    (void)out_len;
    struct test_transport *test_transport = transport;
    CHECK(test_transport != NULL);
    CHECK(read_len != NULL);
    CHECK(fin != NULL);
    if (test_transport->read_offset < test_transport->read_len) {
        size_t remaining = test_transport->read_len - test_transport->read_offset;
        size_t copied = remaining < out_len ? remaining : out_len;
        memcpy(out, test_transport->read_data + test_transport->read_offset, copied);
        test_transport->read_offset += copied;
        *read_len = copied;
        *fin = 0;
        return LIBP2P_HOST_OK;
    }
    *read_len = 0u;
    *fin = 0;
    return test_transport->read_result;
}

static libp2p_host_err_t test_transport_stream_reset(
    void *transport,
    void *stream,
    uint64_t app_error_code) {
    (void)stream;
    (void)app_error_code;
    struct test_transport *test_transport = transport;
    CHECK(test_transport != NULL);
    test_transport->reset_called += 1u;
    return LIBP2P_HOST_OK;
}

static const libp2p_host_transport_vtable_t test_transport_vtable = {
    .stream_read = test_transport_stream_read,
    .stream_reset = test_transport_stream_reset,
};

static void init_test_host_stream(
    libp2p_host_t *host,
    libp2p_host_stream_t *stream,
    struct test_transport *transport) {
    CHECK(host != NULL);
    CHECK(stream != NULL);
    CHECK(transport != NULL);
    memset(host, 0, sizeof(*host));
    memset(stream, 0, sizeof(*stream));
    host->magic = HOST_MAGIC;
    host->state = HOST_STATE_STARTED;
    host->config.transport = &test_transport_vtable;
    host->transport = transport;
    stream->host = host;
    stream->transport_stream = transport;
    stream->state = HOST_STREAM_OPEN;
}

static int test_handle_block_response(
    void *context,
    const LanternSignedBlock *block,
    const char *peer_id,
    uint64_t request_id) {
    (void)block;
    (void)peer_id;
    (void)request_id;
    struct test_blocks_context *test_context = (struct test_blocks_context *)context;
    if (!test_context) {
        return -1;
    }
    test_context->handled_count += 1u;
    return test_context->handle_result;
}

static void test_blocks_request_complete(
    void *context,
    uint64_t request_id,
    enum lantern_reqresp_blocks_request_result result) {
    (void)request_id;
    struct test_blocks_context *test_context = (struct test_blocks_context *)context;
    if (!test_context) {
        return;
    }
    test_context->complete_called += 1;
    test_context->complete_result = result;
}

static int test_collect_blocks_by_range(
    void *context,
    uint64_t start_slot,
    uint64_t count,
    LanternSignedBlockList *out_blocks) {
    (void)out_blocks;
    struct test_range_serve_context *test_context =
        (struct test_range_serve_context *)context;
    if (!test_context) {
        return -1;
    }
    test_context->collect_called += 1u;
    test_context->start_slot = start_slot;
    test_context->count = count;
    return 0;
}

static int test_current_slot(void *context, uint64_t *out_slot) {
    struct test_range_serve_context *test_context =
        (struct test_range_serve_context *)context;
    if (!test_context || !out_slot) {
        return -1;
    }
    test_context->current_slot_called += 1u;
    *out_slot = test_context->current_slot;
    return 0;
}

static int run_blocks_exchange(
    enum lantern_reqresp_protocol_kind kind,
    const LanternRoot *roots,
    size_t root_count,
    const LanternSignedBlock *blocks,
    size_t block_count,
    uint64_t range_start_slot,
    uint64_t range_count,
    int handle_result,
    size_t *out_handled_count,
    int *out_complete_called,
    int *out_complete_result) {
    bool by_root = kind == LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT;
    if ((!by_root && kind != LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE)
        || (by_root && (!roots || root_count == 0u))
        || (!by_root && (roots || root_count != 0u))
        || (!by_root
            && (range_count == 0u || range_start_slot > UINT64_MAX - range_count))
        || (!blocks && block_count > 0u)
        || !out_handled_count || !out_complete_called || !out_complete_result) {
        return -1;
    }

    struct test_blocks_context test_context;
    memset(&test_context, 0, sizeof(test_context));
    test_context.handle_result = handle_result;

    struct lantern_reqresp_service service;
    memset(&service, 0, sizeof(service));
    service.callbacks.context = &test_context;
    service.callbacks.handle_block_response = test_handle_block_response;
    service.callbacks.blocks_request_complete = test_blocks_request_complete;

    struct lantern_reqresp_exchange exchange;
    memset(&exchange, 0, sizeof(exchange));
    exchange.service = &service;
    exchange.kind = kind;
    exchange.outbound = 1;
    exchange.range_start_slot = range_start_slot;
    exchange.range_count = range_count;
    snprintf(exchange.peer_id_text, sizeof(exchange.peer_id_text), "%s", "test-peer");

    if (by_root) {
        exchange.root_count = root_count;
        exchange.roots = (LanternRoot *)calloc(root_count, sizeof(*exchange.roots));
        exchange.roots_matched = (bool *)calloc(root_count, sizeof(*exchange.roots_matched));
        if (!exchange.roots || !exchange.roots_matched) {
            free(exchange.roots);
            free(exchange.roots_matched);
            return -1;
        }
        memcpy(exchange.roots, roots, root_count * sizeof(*exchange.roots));
    }

    int rc = 0;
    for (size_t i = 0; i < block_count && !exchange.completed; ++i) {
        uint8_t *raw = NULL;
        size_t raw_len = 0;
        if (encode_signed_block_raw(&blocks[i], &raw, &raw_len) != 0) {
            rc = -1;
            break;
        }
        if (exchange_handle_outbound_block_frame(
                &exchange,
                LANTERN_REQRESP_RESPONSE_SUCCESS,
                raw,
                raw_len)
            != 0) {
            rc = -1;
        }
        free(raw);
        if (rc != 0) {
            break;
        }
    }

    if (rc == 0 && !exchange.completed) {
        exchange_handle_outbound_closed(&exchange, 0);
    }

    *out_handled_count = test_context.handled_count;
    *out_complete_called = test_context.complete_called;
    *out_complete_result = (int)test_context.complete_result;

    free(exchange.roots);
    free(exchange.roots_matched);
    return rc;
}

static void fill_root(LanternRoot *root, uint8_t seed) {
    CHECK(root != NULL);
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        root->bytes[i] = (uint8_t)(seed + i);
    }
}

static void make_block(LanternSignedBlock *block, uint64_t slot, uint8_t seed) {
    CHECK(block != NULL);
    lantern_signed_block_init(block);
    block->block.slot = slot;
    block->block.proposer_index = seed;
    fill_root(&block->block.parent_root, (uint8_t)(seed + 1u));
    fill_root(&block->block.state_root, (uint8_t)(seed + 33u));
}

static LanternRoot block_root(const LanternSignedBlock *block) {
    LanternRoot root;
    memset(&root, 0, sizeof(root));
    CHECK(lantern_hash_tree_root_block(&block->block, &root) == SSZ_SUCCESS);
    return root;
}

static void expect_range_stream_failure(
    uint64_t start_slot,
    uint64_t count,
    const LanternSignedBlock *blocks,
    size_t block_count,
    size_t expected_handled_count) {
    size_t handled_count = 0u;
    int complete_called = 0;
    int complete_result = LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS;
    CHECK(
        run_blocks_exchange(
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE,
            NULL,
            0u,
            blocks,
            block_count,
            start_slot,
            count,
            0,
            &handled_count,
            &complete_called,
            &complete_result)
        == 0);
    CHECK(handled_count == expected_handled_count);
    CHECK(complete_called == 1);
    CHECK(complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED);
}

static void test_blocks_by_root_full_batch_succeeds(void) {
    LanternSignedBlock blocks[2];
    make_block(&blocks[0], 10u, 0x10u);
    make_block(&blocks[1], 11u, 0x20u);
    LanternRoot roots[2] = {
        block_root(&blocks[0]),
        block_root(&blocks[1]),
    };

    size_t handled_count = 0;
    int complete_called = 0;
    int complete_result = LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED;
    CHECK(
        run_blocks_exchange(
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
            roots,
            2u,
            blocks,
            2u,
            0u,
            0u,
            0,
            &handled_count,
            &complete_called,
            &complete_result)
        == 0);
    CHECK(handled_count == 2u);
    CHECK(complete_called == 1);
    CHECK(complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS);

    lantern_signed_block_reset(&blocks[1]);
    lantern_signed_block_reset(&blocks[0]);
}

static void test_blocks_by_root_partial_batch_fails_on_close(void) {
    LanternSignedBlock blocks[2];
    make_block(&blocks[0], 20u, 0x30u);
    make_block(&blocks[1], 21u, 0x40u);
    LanternRoot roots[2] = {
        block_root(&blocks[0]),
        block_root(&blocks[1]),
    };

    size_t handled_count = 0;
    int complete_called = 0;
    int complete_result = LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS;
    CHECK(
        run_blocks_exchange(
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
            roots,
            2u,
            &blocks[0],
            1u,
            0u,
            0u,
            0,
            &handled_count,
            &complete_called,
            &complete_result)
        == 0);
    CHECK(handled_count == 1u);
    CHECK(complete_called == 1);
    CHECK(complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED);

    lantern_signed_block_reset(&blocks[1]);
    lantern_signed_block_reset(&blocks[0]);
}

static void test_blocks_by_root_unrequested_block_fails_before_callback(void) {
    LanternSignedBlock block;
    make_block(&block, 30u, 0x50u);
    LanternRoot requested_root = block_root(&block);
    requested_root.bytes[0] ^= 0xffu;

    size_t handled_count = 0;
    int complete_called = 0;
    int complete_result = LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS;
    CHECK(
        run_blocks_exchange(
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
            &requested_root,
            1u,
            &block,
            1u,
            0u,
            0u,
            0,
            &handled_count,
            &complete_called,
            &complete_result)
        == 0);
    CHECK(handled_count == 0u);
    CHECK(complete_called == 1);
    CHECK(complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED);

    lantern_signed_block_reset(&block);
}

static void test_blocks_by_root_empty_batch_is_reported(void) {
    LanternRoot root;
    fill_root(&root, 0x70u);

    size_t handled_count = 0;
    int complete_called = 0;
    int complete_result = LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS;
    CHECK(
        run_blocks_exchange(
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT,
            &root,
            1u,
            NULL,
            0u,
            0u,
            0u,
            0,
            &handled_count,
            &complete_called,
            &complete_result)
        == 0);
    CHECK(handled_count == 0u);
    CHECK(complete_called == 1);
    CHECK(complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_EMPTY);
}

static void test_blocks_by_root_timeout_completes_failure_once(void) {
    struct test_blocks_context test_context;
    memset(&test_context, 0, sizeof(test_context));

    struct lantern_reqresp_service service;
    memset(&service, 0, sizeof(service));
    service.callbacks.context = &test_context;
    service.callbacks.blocks_request_complete = test_blocks_request_complete;

    struct lantern_reqresp_exchange exchange;
    memset(&exchange, 0, sizeof(exchange));
    exchange.service = &service;
    exchange.kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT;
    exchange.outbound = 1;
    exchange.request_id = 42u;
    exchange.deadline_us = 100u;
    service.exchanges = &exchange;

    reqresp_drive(NULL, 99u, &service);
    CHECK(test_context.complete_called == 0);

    reqresp_drive(NULL, 100u, &service);
    CHECK(test_context.complete_called == 1);
    CHECK(test_context.complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED);
    CHECK(exchange.completed == 1);

    reqresp_drive(NULL, 200u, &service);
    CHECK(test_context.complete_called == 1);
    exchange_handle_outbound_closed(&exchange, true);
    CHECK(test_context.complete_called == 1);
    service.exchanges = NULL;
}

static void test_blocks_by_range_closed_read_completes_success(void) {
    struct test_blocks_context test_context;
    memset(&test_context, 0, sizeof(test_context));

    struct lantern_reqresp_service service;
    memset(&service, 0, sizeof(service));
    service.callbacks.context = &test_context;
    service.callbacks.handle_block_response = test_handle_block_response;
    service.callbacks.blocks_request_complete = test_blocks_request_complete;

    struct lantern_reqresp_exchange *exchange = calloc(1u, sizeof(*exchange));
    CHECK(exchange != NULL);
    exchange->service = &service;
    exchange->kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE;
    exchange->outbound = 1;
    exchange->request_id = 43u;
    exchange->range_start_slot = 40u;
    exchange->range_count = 3u;
    service.exchanges = exchange;

    LanternSignedBlock block;
    make_block(&block, 40u, 0x75u);
    uint8_t *raw = NULL;
    size_t raw_len = 0u;
    CHECK(encode_signed_block_raw(&block, &raw, &raw_len) == 0);
    struct reqresp_buffer response = {0};
    CHECK(
        append_frame_from_raw(
            &response,
            raw,
            raw_len,
            LANTERN_REQRESP_RESPONSE_SUCCESS)
        == 0);
    free(raw);

    struct test_transport transport = {
        .read_result = LIBP2P_HOST_ERR_CLOSED,
        .read_data = response.data,
        .read_len = response.len,
    };
    libp2p_host_t host;
    libp2p_host_stream_t stream;
    init_test_host_stream(&host, &stream, &transport);
    exchange->host = &host;
    exchange->stream = &stream;
    stream.user_data = exchange;

    CHECK(
        reqresp_on_event(
            &host,
            &stream,
            LIBP2P_HOST_PROTOCOL_EVENT_READABLE,
            NULL)
        == LIBP2P_HOST_OK);
    CHECK(test_context.handled_count == 1u);
    CHECK(test_context.complete_called == 1);
    CHECK(test_context.complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS);
    CHECK(service.exchanges == NULL);
    CHECK(stream.user_data == NULL);
    reqresp_buffer_reset(&response);
    lantern_signed_block_reset(&block);
}

static void test_cancelled_range_does_not_timeout_or_complete(void) {
    struct test_blocks_context test_context;
    memset(&test_context, 0, sizeof(test_context));

    struct lantern_reqresp_service service;
    memset(&service, 0, sizeof(service));
    service.callbacks.context = &test_context;
    service.callbacks.blocks_request_complete = test_blocks_request_complete;

    struct lantern_reqresp_exchange exchange;
    memset(&exchange, 0, sizeof(exchange));
    exchange.service = &service;
    exchange.kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE;
    exchange.outbound = 1;
    exchange.request_id = 44u;
    exchange.deadline_us = 100u;
    service.exchanges = &exchange;

    struct test_transport transport = {
        .read_result = LIBP2P_HOST_ERR_WOULD_BLOCK,
    };
    libp2p_host_t host;
    libp2p_host_stream_t stream;
    init_test_host_stream(&host, &stream, &transport);
    exchange.host = &host;
    exchange.stream = &stream;

    CHECK(lantern_reqresp_service_cancel_blocks_by_range_for_test(&service, 44u));
    CHECK(exchange.completed == 1);
    CHECK(exchange.cancelled == 1);
    CHECK(exchange.deadline_us == 0u);

    reqresp_drive(NULL, 200u, &service);
    CHECK(transport.reset_called == 1u);
    CHECK(exchange.cancelled == 0);
    CHECK(test_context.complete_called == 0);

    reqresp_drive(NULL, 300u, &service);
    CHECK(transport.reset_called == 1u);
    CHECK(test_context.complete_called == 0);
    service.exchanges = NULL;
}

static void test_blocks_by_range_accepts_sparse_and_reports_clean_empty(void) {
    LanternSignedBlock blocks[2];
    make_block(&blocks[0], 40u, 0x80u);
    make_block(&blocks[1], 42u, 0x90u);
    blocks[1].block.parent_root = block_root(&blocks[0]);

    size_t handled_count = 0u;
    int complete_called = 0;
    int complete_result = LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED;
    CHECK(
        run_blocks_exchange(
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE,
            NULL,
            0u,
            blocks,
            2u,
            40u,
            3u,
            0,
            &handled_count,
            &complete_called,
            &complete_result)
        == 0);
    CHECK(handled_count == 2u);
    CHECK(complete_called == 1);
    CHECK(complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS);

    handled_count = 0u;
    complete_called = 0;
    complete_result = LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED;
    CHECK(
        run_blocks_exchange(
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE,
            NULL,
            0u,
            NULL,
            0u,
            40u,
            3u,
            0,
            &handled_count,
            &complete_called,
            &complete_result)
        == 0);
    CHECK(handled_count == 0u);
    CHECK(complete_called == 1);
    CHECK(complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_EMPTY);

    handled_count = 0u;
    complete_called = 0;
    complete_result = LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_SUCCESS;
    CHECK(
        run_blocks_exchange(
            LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE,
            NULL,
            0u,
            blocks,
            1u,
            40u,
            3u,
            -1,
            &handled_count,
            &complete_called,
            &complete_result)
        == 0);
    CHECK(handled_count == 1u);
    CHECK(complete_called == 1);
    CHECK(complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_FAILED);

    lantern_signed_block_reset(&blocks[1]);
    lantern_signed_block_reset(&blocks[0]);
}

static void test_blocks_by_range_rejects_slot_below_start(void) {
    LanternSignedBlock block;
    make_block(&block, 39u, 0xa0u);
    expect_range_stream_failure(40u, 3u, &block, 1u, 0u);
    lantern_signed_block_reset(&block);
}

static void test_blocks_by_range_rejects_slot_at_exclusive_end(void) {
    LanternSignedBlock block;
    make_block(&block, 43u, 0xb0u);
    expect_range_stream_failure(40u, 3u, &block, 1u, 0u);
    lantern_signed_block_reset(&block);
}

static void test_blocks_by_range_rejects_duplicate_slot(void) {
    LanternSignedBlock blocks[2];
    make_block(&blocks[0], 40u, 0xc0u);
    make_block(&blocks[1], 40u, 0xd0u);
    blocks[1].block.parent_root = block_root(&blocks[0]);
    expect_range_stream_failure(40u, 3u, blocks, 2u, 1u);
    lantern_signed_block_reset(&blocks[1]);
    lantern_signed_block_reset(&blocks[0]);
}

static void test_blocks_by_range_rejects_descending_slots(void) {
    LanternSignedBlock blocks[2];
    make_block(&blocks[0], 41u, 0xe0u);
    make_block(&blocks[1], 40u, 0xf0u);
    blocks[1].block.parent_root = block_root(&blocks[0]);
    expect_range_stream_failure(40u, 3u, blocks, 2u, 1u);
    lantern_signed_block_reset(&blocks[1]);
    lantern_signed_block_reset(&blocks[0]);
}

static void test_blocks_by_range_rejects_parent_discontinuity(void) {
    LanternSignedBlock blocks[2];
    make_block(&blocks[0], 40u, 0x21u);
    make_block(&blocks[1], 42u, 0x31u);
    blocks[1].block.parent_root = block_root(&blocks[0]);
    blocks[1].block.parent_root.bytes[0] ^= 0xffu;
    expect_range_stream_failure(40u, 3u, blocks, 2u, 1u);
    lantern_signed_block_reset(&blocks[1]);
    lantern_signed_block_reset(&blocks[0]);
}

static void test_blocks_by_range_resource_unavailable_is_not_clean_empty(void) {
    struct test_blocks_context test_context;
    memset(&test_context, 0, sizeof(test_context));

    struct lantern_reqresp_service service;
    memset(&service, 0, sizeof(service));
    service.callbacks.context = &test_context;
    service.callbacks.blocks_request_complete = test_blocks_request_complete;

    struct lantern_reqresp_exchange exchange;
    memset(&exchange, 0, sizeof(exchange));
    exchange.service = &service;
    exchange.kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE;
    exchange.outbound = 1;

    CHECK(
        exchange_handle_outbound_block_frame(
            &exchange,
            LANTERN_REQRESP_RESPONSE_RESOURCE_UNAVAILABLE,
            NULL,
            0u)
        == 0);
    CHECK(exchange.completed == 1);
    CHECK(test_context.complete_called == 1);
    CHECK(test_context.complete_result == LANTERN_REQRESP_BLOCKS_REQUEST_RESULT_EMPTY);
    exchange_handle_outbound_closed(&exchange, false);
    CHECK(test_context.complete_called == 1);
}

static void test_blocks_by_range_serves_beyond_history_window(void) {
    struct test_range_serve_context test_context;
    memset(&test_context, 0, sizeof(test_context));
    test_context.current_slot = LANTERN_MIN_SLOTS_FOR_BLOCK_REQUESTS + 100u;

    struct lantern_reqresp_service service;
    memset(&service, 0, sizeof(service));
    service.callbacks.context = &test_context;
    service.callbacks.collect_blocks_by_range = test_collect_blocks_by_range;
    service.callbacks.current_slot = test_current_slot;

    struct lantern_reqresp_exchange exchange;
    memset(&exchange, 0, sizeof(exchange));
    exchange.service = &service;
    exchange.kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE;

    LanternBlocksByRangeRequest request = {
        .start_slot = 1u,
        .count = 2u,
    };
    uint8_t raw[2u * sizeof(uint64_t)];
    size_t raw_len = 0u;
    CHECK(
        lantern_network_blocks_by_range_request_encode(
            &request,
            raw,
            sizeof(raw),
            &raw_len)
        == 0);
    CHECK(exchange_prepare_blocks_by_range_response(&exchange, raw, raw_len) == 0);
    CHECK(test_context.collect_called == 1u);
    CHECK(test_context.start_slot == request.start_slot);
    CHECK(test_context.count == request.count);
    CHECK(test_context.current_slot_called == 0u);
    CHECK(exchange.read_buf.len == 0u);
    reqresp_buffer_reset(&exchange.read_buf);
}

static void test_blocks_by_range_rejects_exclusive_end_overflow(void) {
    uint8_t *frame = NULL;
    size_t frame_len = 0u;
    CHECK(
        build_blocks_by_range_request_frame(
            UINT64_MAX,
            1u,
            &frame,
            &frame_len)
        != 0);
    CHECK(frame == NULL);
    CHECK(frame_len == 0u);
    CHECK(
        build_blocks_by_range_request_frame(
            UINT64_MAX - 1u,
            1u,
            &frame,
            &frame_len)
        == 0);
    CHECK(frame != NULL);
    CHECK(frame_len > 0u);
    free(frame);

    struct test_range_serve_context test_context;
    memset(&test_context, 0, sizeof(test_context));
    struct lantern_reqresp_service service;
    memset(&service, 0, sizeof(service));
    service.callbacks.context = &test_context;
    service.callbacks.collect_blocks_by_range = test_collect_blocks_by_range;

    struct lantern_reqresp_exchange exchange;
    memset(&exchange, 0, sizeof(exchange));
    exchange.service = &service;
    exchange.kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_RANGE;

    LanternBlocksByRangeRequest request = {
        .start_slot = UINT64_MAX,
        .count = 1u,
    };
    uint8_t raw[2u * sizeof(uint64_t)];
    size_t raw_len = 0u;
    CHECK(
        lantern_network_blocks_by_range_request_encode(
            &request,
            raw,
            sizeof(raw),
            &raw_len)
        == 0);
    CHECK(exchange_prepare_blocks_by_range_response(&exchange, raw, raw_len) == 0);
    CHECK(test_context.collect_called == 0u);
    CHECK(exchange.read_buf.len > 0u);
    CHECK(exchange.read_buf.data[0] == LANTERN_REQRESP_RESPONSE_INVALID_REQUEST);
    reqresp_buffer_reset(&exchange.read_buf);
}

int main(void) {
    test_blocks_by_root_full_batch_succeeds();
    test_blocks_by_root_partial_batch_fails_on_close();
    test_blocks_by_root_unrequested_block_fails_before_callback();
    test_blocks_by_root_empty_batch_is_reported();
    test_blocks_by_root_timeout_completes_failure_once();
    test_blocks_by_range_closed_read_completes_success();
    test_cancelled_range_does_not_timeout_or_complete();
    test_blocks_by_range_accepts_sparse_and_reports_clean_empty();
    test_blocks_by_range_rejects_slot_below_start();
    test_blocks_by_range_rejects_slot_at_exclusive_end();
    test_blocks_by_range_rejects_duplicate_slot();
    test_blocks_by_range_rejects_descending_slots();
    test_blocks_by_range_rejects_parent_discontinuity();
    test_blocks_by_range_resource_unavailable_is_not_clean_empty();
    test_blocks_by_range_serves_beyond_history_window();
    test_blocks_by_range_rejects_exclusive_end_overflow();
    puts("lantern_reqresp_service_test OK");
    return 0;
}
