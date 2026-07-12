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

typedef struct lantern_root_list LanternRequestedBlockRoots;

typedef struct {
    LanternRequestedBlockRoots roots;
} LanternBlocksByRootRequest;

typedef struct {
    uint64_t start_slot;
    uint64_t count;
} LanternBlocksByRangeRequest;

typedef struct {
    LanternSignedBlock *blocks;
    size_t length;
    size_t capacity;
} LanternSignedBlockList;

void lantern_blocks_by_root_request_init(LanternBlocksByRootRequest *req);
void lantern_blocks_by_root_request_reset(LanternBlocksByRootRequest *req);

void lantern_signed_block_list_init(LanternSignedBlockList *resp);
void lantern_signed_block_list_reset(LanternSignedBlockList *resp);
int lantern_signed_block_list_resize(LanternSignedBlockList *resp, size_t new_length);

int lantern_network_status_encode(
    const LanternStatusMessage *status,
    uint8_t *out,
    size_t out_len,
    size_t *written);
int lantern_network_status_decode(
    LanternStatusMessage *status,
    const uint8_t *data,
    size_t data_len);

int lantern_network_blocks_by_root_request_encode(
    const LanternBlocksByRootRequest *req,
    uint8_t *out,
    size_t out_len,
    size_t *written);
int lantern_network_blocks_by_root_request_decode(
    LanternBlocksByRootRequest *req,
    const uint8_t *data,
    size_t data_len);

int lantern_network_blocks_by_range_request_decode(
    LanternBlocksByRangeRequest *req,
    const uint8_t *data,
    size_t data_len);

#endif /* LANTERN_NETWORKING_MESSAGES_H */
