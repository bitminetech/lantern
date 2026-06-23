#include "lantern/networking/messages.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/ssz.h"
#include "lantern/consensus/state.h"
#include "ssz.h"
#include "lantern/networking/reqresp_service.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"

static int write_u32_le(uint32_t value, uint8_t *out, size_t out_len) {
    if (!out || out_len < sizeof(uint32_t)) {
        return -1;
    }
    out[0] = (uint8_t)(value & 0xFFu);
    out[1] = (uint8_t)((value >> 8) & 0xFFu);
    out[2] = (uint8_t)((value >> 16) & 0xFFu);
    out[3] = (uint8_t)((value >> 24) & 0xFFu);
    return 0;
}

static int read_u32_le(const uint8_t *data, size_t data_len, uint32_t *value) {
    if (!data || data_len < sizeof(uint32_t) || !value) {
        return -1;
    }
    *value = (uint32_t)data[0]
        | ((uint32_t)data[1] << 8)
        | ((uint32_t)data[2] << 16)
        | ((uint32_t)data[3] << 24);
    return 0;
}

static int read_u64_le(const uint8_t *data, size_t data_len, uint64_t *value) {
    if (!data || data_len < sizeof(uint64_t) || !value) {
        return -1;
    }
    *value = (uint64_t)data[0]
        | ((uint64_t)data[1] << 8)
        | ((uint64_t)data[2] << 16)
        | ((uint64_t)data[3] << 24)
        | ((uint64_t)data[4] << 32)
        | ((uint64_t)data[5] << 40)
        | ((uint64_t)data[6] << 48)
        | ((uint64_t)data[7] << 56);
    return 0;
}

static int ensure_block_capacity(LanternSignedBlockList *resp, size_t required) {
    if (!resp) {
        return -1;
    }
    if (resp->capacity >= required) {
        return 0;
    }
    size_t new_capacity = resp->capacity == 0 ? 4u : resp->capacity;
    while (new_capacity < required) {
        if (new_capacity > SIZE_MAX / 2u) {
            return -1;
        }
        new_capacity *= 2u;
    }
    LanternSignedBlock *blocks = realloc(resp->blocks, new_capacity * sizeof(*blocks));
    if (!blocks) {
        return -1;
    }
    resp->blocks = blocks;
    resp->capacity = new_capacity;
    return 0;
}

static void log_status_payload_debug(const char *label, const uint8_t *data, size_t length) {
    if (!data || length == 0) {
        lantern_log_warn(
            "reqresp",
            NULL,
            "%s len=%zu (no payload)",
            label ? label : "status payload",
            length);
        return;
    }
    const size_t max_preview = 256u;
    size_t preview_len = length < max_preview ? length : max_preview;
    size_t hex_capacity = (preview_len * 2u) + 1u;
    char *hex = (char *)malloc(hex_capacity);
    if (!hex) {
        lantern_log_warn(
            "reqresp",
            NULL,
            "%s len=%zu (preview alloc failed)",
            label ? label : "status payload",
            length);
        return;
    }
    if (lantern_bytes_to_hex(data, preview_len, hex, hex_capacity, 0) != 0) {
        hex[0] = '\0';
    }
    lantern_log_warn(
        "reqresp",
        NULL,
        "%s len=%zu preview=%s%s",
        label ? label : "status payload",
        length,
        hex[0] ? hex : "-",
        length > preview_len ? "..." : "");
    free(hex);
}

void lantern_blocks_by_root_request_init(LanternBlocksByRootRequest *req) {
    if (!req) {
        return;
    }
    lantern_root_list_init(&req->roots);
}

void lantern_blocks_by_root_request_reset(LanternBlocksByRootRequest *req) {
    if (!req) {
        return;
    }
    lantern_root_list_reset(&req->roots);
}

void lantern_signed_block_list_init(LanternSignedBlockList *resp) {
    if (!resp) {
        return;
    }
    resp->blocks = NULL;
    resp->length = 0;
    resp->capacity = 0;
}

void lantern_signed_block_list_reset(LanternSignedBlockList *resp) {
    if (!resp) {
        return;
    }
    if (resp->blocks) {
        for (size_t i = 0; i < resp->length; ++i) {
            lantern_signed_block_reset(&resp->blocks[i]);
        }
    }
    free(resp->blocks);
    resp->blocks = NULL;
    resp->length = 0;
    resp->capacity = 0;
}

int lantern_signed_block_list_resize(LanternSignedBlockList *resp, size_t new_length) {
    if (!resp) {
        return -1;
    }
    if (new_length == 0) {
        if (resp->blocks) {
            for (size_t i = 0; i < resp->length; ++i) {
                lantern_signed_block_reset(&resp->blocks[i]);
            }
        }
        resp->length = 0;
        return 0;
    }
    if (ensure_block_capacity(resp, new_length) != 0) {
        return -1;
    }
    if (!resp->blocks) {
        return -1;
    }
    size_t old_length = resp->length;
    if (new_length > old_length) {
        for (size_t i = old_length; i < new_length; ++i) {
            lantern_signed_block_init(&resp->blocks[i]);
        }
    } else if (new_length < old_length) {
        for (size_t i = new_length; i < old_length; ++i) {
            lantern_signed_block_reset(&resp->blocks[i]);
        }
    }
    resp->length = new_length;
    return 0;
}

static int encode_status_raw(
    const LanternStatusMessage *status,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!status || !out || !written) {
        return -1;
    }
    size_t offset = 0;
    size_t checkpoint_written = 0;
    if (lantern_ssz_encode_checkpoint(&status->finalized, out + offset, out_len - offset, &checkpoint_written) != SSZ_SUCCESS) {
        return -1;
    }
    offset += checkpoint_written;
    if (lantern_ssz_encode_checkpoint(&status->head, out + offset, out_len - offset, &checkpoint_written) != SSZ_SUCCESS) {
        return -1;
    }
    offset += checkpoint_written;
    *written = offset;
    return 0;
}

int lantern_network_status_encode(
    const LanternStatusMessage *status,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    return encode_status_raw(status, out, out_len, written);
}

int lantern_network_status_decode(
    LanternStatusMessage *status,
    const uint8_t *data,
    size_t data_len) {
    const size_t expected_len = 2u * LANTERN_CHECKPOINT_SSZ_SIZE;
    if (!status || !data) {
        return -1;
    }
    if (data_len != expected_len) {
        log_status_payload_debug("status decode invalid_len", data, data_len);
        return -1;
    }
    if (lantern_ssz_decode_checkpoint(&status->finalized, data, LANTERN_CHECKPOINT_SSZ_SIZE) != SSZ_SUCCESS) {
        log_status_payload_debug("status decode finalized_failed", data, data_len);
        return -1;
    }
    if (lantern_ssz_decode_checkpoint(
            &status->head,
            data + LANTERN_CHECKPOINT_SSZ_SIZE,
            LANTERN_CHECKPOINT_SSZ_SIZE)
        != 0) {
        log_status_payload_debug("status decode head_failed", data, data_len);
        return -1;
    }
    return 0;
}

int lantern_network_blocks_by_root_request_encode(
    const LanternBlocksByRootRequest *req,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!req || !out || !written) {
        return -1;
    }
    if (req->roots.length > LANTERN_MAX_REQUEST_BLOCKS) {
        return -1;
    }
    if (req->roots.length > (SIZE_MAX - sizeof(uint32_t)) / LANTERN_ROOT_SIZE) {
        return -1;
    }
    size_t roots_bytes = req->roots.length * LANTERN_ROOT_SIZE;
    size_t total_len = sizeof(uint32_t) + roots_bytes;
    if (out_len < total_len) {
        return -1;
    }
    /* leanSpec: BlocksByRootRequest is container {roots: RequestedBlockRoots}. */
    if (write_u32_le((uint32_t)sizeof(uint32_t), out, out_len) != 0) {
        return -1;
    }
    if (roots_bytes > 0) {
        if (!req->roots.items) {
            return -1;
        }
        memcpy(out + sizeof(uint32_t), req->roots.items, roots_bytes);
    }
    *written = total_len;
    return 0;
}

static int decode_blocks_by_root_list(
    LanternBlocksByRootRequest *req,
    const uint8_t *data,
    size_t data_len) {
    if (!req) {
        return -1;
    }
    if (data_len == 0) {
        return lantern_root_list_resize(&req->roots, 0) == 0 ? 0 : -1;
    }
    if (!data) {
        return -1;
    }
    if (data_len % LANTERN_ROOT_SIZE != 0) {
        return -1;
    }
    size_t count = data_len / LANTERN_ROOT_SIZE;
    if (count > LANTERN_MAX_REQUEST_BLOCKS) {
        return -1;
    }
    if (lantern_root_list_resize(&req->roots, (uint32_t)count) != 0) {
        return -1;
    }
    if (count > 0) {
        if (!req->roots.items) {
            return -1;
        }
        memcpy(req->roots.items, data, data_len);
    }
    return 0;
}

int lantern_network_blocks_by_root_request_decode(
    LanternBlocksByRootRequest *req,
    const uint8_t *data,
    size_t data_len) {
    if (!req) {
        return -1;
    }
    if (!data) {
        return -1;
    }

    /* Canonical SSZ container encoding: [offset=4][packed roots bytes]. */
    if (data_len >= sizeof(uint32_t)) {
        uint32_t offset = 0;
        if (read_u32_le(data, data_len, &offset) == 0) {
            if (offset == sizeof(uint32_t) && offset <= data_len) {
                size_t list_len = data_len - offset;
                if (list_len % LANTERN_ROOT_SIZE == 0) {
                    return decode_blocks_by_root_list(req, data + offset, list_len);
                }
            }
        }
    }

    return -1;
}

int lantern_network_blocks_by_range_request_decode(
    LanternBlocksByRangeRequest *req,
    const uint8_t *data,
    size_t data_len) {
    if (!req || !data || data_len != 2u * sizeof(uint64_t)) {
        return -1;
    }
    if (read_u64_le(data, data_len, &req->start_slot) != 0
        || read_u64_le(data + sizeof(uint64_t), data_len - sizeof(uint64_t), &req->count) != 0) {
        return -1;
    }
    return 0;
}

int lantern_network_signed_block_list_encode(
    const LanternSignedBlockList *resp,
    uint8_t *out,
    size_t out_len,
    size_t *written) {
    if (!resp || !out || !written) {
        return -1;
    }
    if (resp->length > LANTERN_MAX_REQUEST_BLOCKS) {
        return -1;
    }

    if (resp->length == 0) {
        *written = 0;
        return 0;
    }

    const size_t offsets_bytes = resp->length * sizeof(uint32_t);
    size_t capacity = offsets_bytes + 256u;
    if (capacity < offsets_bytes) {
        return -1;
    }

    uint8_t *buffer = NULL;
    for (unsigned attempt = 0; attempt < 16; ++attempt) {
        if (capacity < offsets_bytes) {
            capacity = offsets_bytes;
        }
        if (capacity > SIZE_MAX / 2 && attempt + 1 < 16) {
            free(buffer);
            return -1;
        }
        uint8_t *resized = (uint8_t *)realloc(buffer, capacity);
        if (!resized) {
            free(buffer);
            return -1;
        }
        buffer = resized;

        size_t payload_cursor = offsets_bytes;
        bool encode_ok = true;
        for (size_t i = 0; i < resp->length; ++i) {
            if (payload_cursor > UINT32_MAX) {
                encode_ok = false;
                break;
            }
            if (write_u32_le(
                    (uint32_t)payload_cursor,
                    buffer + (i * sizeof(uint32_t)),
                    capacity - (i * sizeof(uint32_t)))
                != 0) {
                encode_ok = false;
                break;
            }

            size_t block_written = 0;
            if (lantern_ssz_encode_signed_block(
                    &resp->blocks[i],
                    buffer + payload_cursor,
                    capacity - payload_cursor,
                    &block_written)
                != 0) {
                encode_ok = false;
                break;
            }
            if (block_written == 0 || block_written > SIZE_MAX - payload_cursor) {
                encode_ok = false;
                break;
            }
            payload_cursor += block_written;
        }

        if (!encode_ok) {
            if (capacity > SIZE_MAX / 2) {
                break;
            }
            capacity *= 2u;
            continue;
        }
        if (out_len < payload_cursor) {
            free(buffer);
            return -1;
        }
        memcpy(out, buffer, payload_cursor);
        *written = payload_cursor;
        free(buffer);
        return 0;
    }

    free(buffer);
    return -1;
}

int lantern_network_signed_block_list_decode(
    LanternSignedBlockList *resp,
    const uint8_t *data,
    size_t data_len) {
    if (!resp || (!data && data_len > 0)) {
        return -1;
    }
    if (lantern_signed_block_list_resize(resp, 0) != 0) {
        return -1;
    }
    if (data_len == 0) {
        return 0;
    }
    if (data_len < sizeof(uint32_t)) {
        return -1;
    }

    uint32_t first_offset = 0;
    if (read_u32_le(data, data_len, &first_offset) != 0) {
        return -1;
    }
    if (first_offset > data_len || (first_offset % sizeof(uint32_t)) != 0) {
        return -1;
    }

    size_t count = first_offset / sizeof(uint32_t);
    if (count == 0 || count > LANTERN_MAX_REQUEST_BLOCKS) {
        return -1;
    }
    if (lantern_signed_block_list_resize(resp, count) != 0) {
        lantern_signed_block_list_reset(resp);
        return -1;
    }

    size_t offsets_len = count * sizeof(uint32_t);
    if (data_len < offsets_len) {
        lantern_signed_block_list_reset(resp);
        return -1;
    }

    const uint8_t *offsets_region = data;
    const uint8_t *payload_region = data;
    size_t payload_total = data_len;

    uint32_t prev_offset = first_offset;
    for (size_t i = 0; i < count; ++i) {
        size_t offset_index = i * sizeof(uint32_t);
        uint32_t start_offset = 0;
        if (read_u32_le(offsets_region + offset_index, data_len - offset_index, &start_offset) != 0) {
            lantern_signed_block_list_reset(resp);
            return -1;
        }
        if (start_offset < offsets_len || start_offset > payload_total) {
            lantern_signed_block_list_reset(resp);
            return -1;
        }
        if (i > 0 && start_offset < prev_offset) {
            lantern_signed_block_list_reset(resp);
            return -1;
        }

        uint32_t end_offset = (uint32_t)payload_total;
        if (i + 1 < count) {
            size_t next_index = (i + 1) * sizeof(uint32_t);
            if (read_u32_le(offsets_region + next_index, data_len - next_index, &end_offset) != 0) {
                lantern_signed_block_list_reset(resp);
                return -1;
            }
            if (end_offset < start_offset || end_offset > payload_total) {
                lantern_signed_block_list_reset(resp);
                return -1;
            }
        }

        size_t span = (size_t)end_offset - (size_t)start_offset;
        if (span == 0) {
            lantern_signed_block_list_reset(resp);
            return -1;
        }
        LanternSignedBlock *entry = &resp->blocks[i];
        if (lantern_ssz_decode_signed_block(entry, payload_region + start_offset, span) != SSZ_SUCCESS) {
            lantern_signed_block_list_reset(resp);
            return -1;
        }
        prev_offset = start_offset;
    }

    return 0;
}
