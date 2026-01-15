#ifndef LANTERN_NETWORKING_MESSAGES_H
#define LANTERN_NETWORKING_MESSAGES_H

#include <stddef.h>
#include <stdint.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"

#define LANTERN_MAX_REQUEST_BLOCKS 1024u

typedef struct {
    LanternCheckpoint finalized;
    LanternCheckpoint head;
} LanternStatusMessage;

typedef struct {
    struct lantern_root_list roots;
} LanternBlocksByRootRequest;

typedef struct {
    LanternSignedBlock *blocks;
    size_t length;
    size_t capacity;
} LanternBlocksByRootResponse;

void lantern_blocks_by_root_request_init(LanternBlocksByRootRequest *req);
void lantern_blocks_by_root_request_reset(LanternBlocksByRootRequest *req);

void lantern_blocks_by_root_response_init(LanternBlocksByRootResponse *resp);
void lantern_blocks_by_root_response_reset(LanternBlocksByRootResponse *resp);
int lantern_blocks_by_root_response_resize(LanternBlocksByRootResponse *resp, size_t new_length);

int lantern_network_status_encode(
    const LanternStatusMessage *status,
    uint8_t *out,
    size_t out_len,
    size_t *written);
int lantern_network_status_decode(
    LanternStatusMessage *status,
    const uint8_t *data,
    size_t data_len);
int lantern_network_status_encode_snappy(
    const LanternStatusMessage *status,
    uint8_t *out,
    size_t out_len,
    size_t *written,
    size_t *raw_len);
int lantern_network_status_decode_snappy(
    LanternStatusMessage *status,
    const uint8_t *data,
    size_t data_len);

int lantern_network_blocks_by_root_request_encode(
    const LanternBlocksByRootRequest *req,
    uint8_t *out,
    size_t out_len,
    size_t *written);
int lantern_network_blocks_by_root_request_encode_prefixed(
    const LanternBlocksByRootRequest *req,
    uint8_t *out,
    size_t out_len,
    size_t *written);
int lantern_network_blocks_by_root_request_decode(
    LanternBlocksByRootRequest *req,
    const uint8_t *data,
    size_t data_len);
int lantern_network_blocks_by_root_request_encode_snappy(
    const LanternBlocksByRootRequest *req,
    uint8_t *out,
    size_t out_len,
    size_t *written,
    size_t *raw_len);
int lantern_network_blocks_by_root_request_decode_snappy(
    LanternBlocksByRootRequest *req,
    const uint8_t *data,
    size_t data_len);

int lantern_network_blocks_by_root_response_encode(
    const LanternBlocksByRootResponse *resp,
    uint8_t *out,
    size_t out_len,
    size_t *written);
int lantern_network_blocks_by_root_response_decode(
    LanternBlocksByRootResponse *resp,
    const uint8_t *data,
    size_t data_len);
int lantern_network_blocks_by_root_response_encode_snappy(
    const LanternBlocksByRootResponse *resp,
    uint8_t *out,
    size_t out_len,
    size_t *written,
    size_t *raw_len);
int lantern_network_blocks_by_root_response_decode_snappy(
    LanternBlocksByRootResponse *resp,
    const uint8_t *data,
    size_t data_len);

#endif /* LANTERN_NETWORKING_MESSAGES_H */
