#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/hash.h"

/* Exercise static exchange handling without adding test hooks to production code. */
#define lantern_reqresp_service_init lantern_reqresp_service_init_for_test
#define lantern_reqresp_service_reset lantern_reqresp_service_reset_for_test
#define lantern_reqresp_service_request_status lantern_reqresp_service_request_status_for_test
#define lantern_reqresp_service_request_blocks lantern_reqresp_service_request_blocks_for_test
#define lantern_reqresp_service_start lantern_reqresp_service_start_for_test
#define lantern_reqresp_stream_from_ops lantern_reqresp_stream_from_ops_for_test
#define lantern_reqresp_stream_free lantern_reqresp_stream_free_for_test
#define lantern_reqresp_read_response_chunk lantern_reqresp_read_response_chunk_for_test
#define lantern_reqresp_stall_timeout_ms lantern_reqresp_stall_timeout_ms_for_test
#include "../../src/networking/reqresp_service.c"
#undef lantern_reqresp_service_init
#undef lantern_reqresp_service_reset
#undef lantern_reqresp_service_request_status
#undef lantern_reqresp_service_request_blocks
#undef lantern_reqresp_service_start
#undef lantern_reqresp_stream_from_ops
#undef lantern_reqresp_stream_free
#undef lantern_reqresp_read_response_chunk
#undef lantern_reqresp_stall_timeout_ms

#define CHECK(cond)                                                                  \
    do {                                                                             \
        if (!(cond)) {                                                               \
            fprintf(stderr, "check failed: %s (%s:%d)\n", #cond, __FILE__, __LINE__); \
            abort();                                                                 \
        }                                                                            \
    } while (0)

struct test_blocks_context {
    size_t handled_count;
    int complete_called;
    int complete_success;
};

static int test_handle_block_response(
    void *context,
    const LanternSignedBlock *block,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len,
    const char *peer_id) {
    (void)block;
    (void)raw_block_ssz;
    (void)raw_block_ssz_len;
    (void)peer_id;
    struct test_blocks_context *test_context = (struct test_blocks_context *)context;
    if (!test_context) {
        return -1;
    }
    test_context->handled_count += 1u;
    return 0;
}

static void test_blocks_request_complete(
    void *context,
    const char *peer_id,
    const LanternRoot *roots,
    size_t root_count,
    uint64_t request_id,
    int success) {
    (void)peer_id;
    (void)roots;
    (void)root_count;
    (void)request_id;
    struct test_blocks_context *test_context = (struct test_blocks_context *)context;
    if (!test_context) {
        return;
    }
    test_context->complete_called += 1;
    test_context->complete_success = success;
}

static int run_blocks_exchange(
    const LanternRoot *roots,
    size_t root_count,
    const LanternSignedBlock *blocks,
    size_t block_count,
    size_t *out_handled_count,
    int *out_complete_called,
    int *out_complete_success) {
    if (!roots || root_count == 0u || (!blocks && block_count > 0u)
        || !out_handled_count || !out_complete_called || !out_complete_success) {
        return -1;
    }

    struct test_blocks_context test_context;
    memset(&test_context, 0, sizeof(test_context));

    struct lantern_reqresp_service service;
    memset(&service, 0, sizeof(service));
    service.callbacks.context = &test_context;
    service.callbacks.handle_block_response = test_handle_block_response;
    service.callbacks.blocks_request_complete = test_blocks_request_complete;

    struct lantern_reqresp_exchange exchange;
    memset(&exchange, 0, sizeof(exchange));
    exchange.service = &service;
    exchange.kind = LANTERN_REQRESP_PROTOCOL_BLOCKS_BY_ROOT;
    exchange.outbound = 1;
    exchange.root_count = root_count;
    snprintf(exchange.peer_id_text, sizeof(exchange.peer_id_text), "%s", "test-peer");

    exchange.roots = (LanternRoot *)calloc(root_count, sizeof(*exchange.roots));
    exchange.roots_matched = (bool *)calloc(root_count, sizeof(*exchange.roots_matched));
    if (!exchange.roots || !exchange.roots_matched) {
        free(exchange.roots);
        free(exchange.roots_matched);
        return -1;
    }
    memcpy(exchange.roots, roots, root_count * sizeof(*exchange.roots));

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
    *out_complete_success = test_context.complete_success;

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
    int complete_success = 0;
    CHECK(
        run_blocks_exchange(
            roots,
            2u,
            blocks,
            2u,
            &handled_count,
            &complete_called,
            &complete_success)
        == 0);
    CHECK(handled_count == 2u);
    CHECK(complete_called == 1);
    CHECK(complete_success == 1);

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
    int complete_success = 1;
    CHECK(
        run_blocks_exchange(
            roots,
            2u,
            &blocks[0],
            1u,
            &handled_count,
            &complete_called,
            &complete_success)
        == 0);
    CHECK(handled_count == 1u);
    CHECK(complete_called == 1);
    CHECK(complete_success == 0);

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
    int complete_success = 1;
    CHECK(
        run_blocks_exchange(
            &requested_root,
            1u,
            &block,
            1u,
            &handled_count,
            &complete_called,
            &complete_success)
        == 0);
    CHECK(handled_count == 0u);
    CHECK(complete_called == 1);
    CHECK(complete_success == 0);

    lantern_signed_block_reset(&block);
}

int main(void) {
    test_blocks_by_root_full_batch_succeeds();
    test_blocks_by_root_partial_batch_fails_on_close();
    test_blocks_by_root_unrequested_block_fails_before_callback();
    puts("lantern_reqresp_service_test OK");
    return 0;
}
