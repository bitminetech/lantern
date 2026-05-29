#include "client_internal.h"

#include "lantern/support/log.h"

#include <stddef.h>

int lantern_client_schedule_blocks_request_batch(
    struct lantern_client *client,
    const char *peer_id_text,
    const LanternRoot *roots,
    const uint32_t *depths,
    size_t root_count,
    uint64_t request_id) {
    (void)depths;
    if (!client || !peer_id_text || !roots || root_count == 0 || root_count > LANTERN_MAX_REQUEST_BLOCKS) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    for (size_t i = 0; i < root_count; ++i) {
        if (lantern_root_is_zero(&roots[i])) {
            return LANTERN_CLIENT_ERR_INVALID_PARAM;
        }
    }
    if (client->debug_disable_block_requests) {
        lantern_client_on_blocks_request_complete_batch_with_id(
            client,
            request_id,
            peer_id_text,
            roots,
            root_count,
            LANTERN_BLOCKS_REQUEST_ABORTED);
        return 0;
    }

    struct lantern_peer_id peer_id;
    if (lantern_peer_id_from_text(peer_id_text, &peer_id) != 0) {
        lantern_client_on_blocks_request_complete_batch_with_id(
            client,
            request_id,
            peer_id_text,
            roots,
            root_count,
            LANTERN_BLOCKS_REQUEST_FAILED);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    if (lantern_reqresp_service_request_blocks(
            &client->reqresp,
            &peer_id,
            peer_id_text,
            roots,
            root_count,
            request_id)
        != 0) {
        lantern_client_on_blocks_request_complete_batch_with_id(
            client,
            request_id,
            peer_id_text,
            roots,
            root_count,
            LANTERN_BLOCKS_REQUEST_FAILED);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    return LANTERN_CLIENT_OK;
}

int lantern_client_schedule_blocks_by_range_request(
    struct lantern_client *client,
    const char *peer_id_text,
    uint64_t start_slot,
    uint64_t count,
    uint64_t request_id) {
    if (!client || !peer_id_text || count == 0u || count > LANTERN_MAX_REQUEST_BLOCKS) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (count > UINT64_MAX - start_slot) {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    if (client->debug_disable_block_requests) {
        lantern_client_on_blocks_request_complete_batch_with_id(
            client,
            request_id,
            peer_id_text,
            NULL,
            0u,
            LANTERN_BLOCKS_REQUEST_ABORTED);
        return 0;
    }

    struct lantern_peer_id peer_id;
    if (lantern_peer_id_from_text(peer_id_text, &peer_id) != 0) {
        lantern_client_on_blocks_request_complete_batch_with_id(
            client,
            request_id,
            peer_id_text,
            NULL,
            0u,
            LANTERN_BLOCKS_REQUEST_FAILED);
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    if (lantern_reqresp_service_request_blocks_by_range(
            &client->reqresp,
            &peer_id,
            peer_id_text,
            start_slot,
            count,
            request_id)
        != 0) {
        lantern_client_on_blocks_request_complete_batch_with_id(
            client,
            request_id,
            peer_id_text,
            NULL,
            0u,
            LANTERN_BLOCKS_REQUEST_FAILED);
        return LANTERN_CLIENT_ERR_NETWORK;
    }
    return LANTERN_CLIENT_OK;
}
