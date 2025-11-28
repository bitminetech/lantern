#include "lantern/encoding/snappy.h"

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "snappy.h"

enum {
    LANTERN_SNAPPY_CHUNK_COMPRESSED = 0x00,
    LANTERN_SNAPPY_CHUNK_UNCOMPRESSED = 0x01,
    LANTERN_SNAPPY_CHUNK_PADDING_START = 0x02,
    LANTERN_SNAPPY_CHUNK_PADDING_END = 0x7f,
    LANTERN_SNAPPY_CHUNK_RESERVED_START = 0x80,
    LANTERN_SNAPPY_CHUNK_RESERVED_END = 0xfe,
    LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER = 0xff,
};

enum {
    LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN = 6,
    LANTERN_SNAPPY_STREAM_HEADER_BYTES = 4 + LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN,
    LANTERN_SNAPPY_CHUNK_HEADER_BYTES = 4,
    LANTERN_SNAPPY_CHUNK_CRC_BYTES = 4,
    LANTERN_SNAPPY_MAX_CHUNK_LEN = 0x00ffffffu,
};

static uint32_t lantern_snappy_read_le24(const uint8_t *data) {
    return (uint32_t)data[0]
        | ((uint32_t)data[1] << 8u)
        | ((uint32_t)data[2] << 16u);
}

static void lantern_snappy_write_le24(uint32_t value, uint8_t *dst) {
    dst[0] = (uint8_t)(value & 0xffu);
    dst[1] = (uint8_t)((value >> 8u) & 0xffu);
    dst[2] = (uint8_t)((value >> 16u) & 0xffu);
}

static void lantern_snappy_write_le32(uint32_t value, uint8_t *dst) {
    dst[0] = (uint8_t)(value & 0xffu);
    dst[1] = (uint8_t)((value >> 8u) & 0xffu);
    dst[2] = (uint8_t)((value >> 16u) & 0xffu);
    dst[3] = (uint8_t)((value >> 24u) & 0xffu);
}

static uint32_t lantern_snappy_crc32c(const uint8_t *data, size_t len) {
    const uint32_t poly = 0x82f63b78u;
    uint32_t crc = 0xffffffffu;
    for (size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (int bit = 0; bit < 8; ++bit) {
            if (crc & 1u) {
                crc = (crc >> 1) ^ poly;
            } else {
                crc >>= 1;
            }
        }
    }
    return ~crc;
}

static uint32_t lantern_snappy_mask_crc32c(uint32_t crc) {
    return ((crc >> 15u) | (crc << 17u)) + 0xa282ead8u;
}

static int lantern_snappy_framed_uncompressed_length(
    const uint8_t *input,
    size_t input_len,
    size_t *result);

static int lantern_snappy_decompress_framed(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written);


int lantern_snappy_max_compressed_size(size_t input_len, size_t *max_size) {
    if (!max_size) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t raw_required = snappy_max_compressed_length(input_len);
    size_t framing_overhead = LANTERN_SNAPPY_STREAM_HEADER_BYTES
        + LANTERN_SNAPPY_CHUNK_HEADER_BYTES
        + LANTERN_SNAPPY_CHUNK_CRC_BYTES;
    if (SIZE_MAX - raw_required < framing_overhead) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    *max_size = raw_required + framing_overhead;
    return LANTERN_SNAPPY_OK;
}

int lantern_snappy_max_compressed_size_raw(size_t input_len, size_t *max_size) {
    if (!max_size) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    *max_size = snappy_max_compressed_length(input_len);
    return LANTERN_SNAPPY_OK;
}

int lantern_snappy_compress(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written) {
    if (!input || !output || !written) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t raw_required = snappy_max_compressed_length(input_len);
    size_t framing_overhead = LANTERN_SNAPPY_STREAM_HEADER_BYTES
        + LANTERN_SNAPPY_CHUNK_HEADER_BYTES
        + LANTERN_SNAPPY_CHUNK_CRC_BYTES;
    if (SIZE_MAX - raw_required < framing_overhead) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    size_t required = raw_required + framing_overhead;
    if (output_len < required) {
        *written = required;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    uint8_t *cursor = output;
    cursor[0] = LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER;
    lantern_snappy_write_le24(LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN, &cursor[1]);
    memcpy(cursor + LANTERN_SNAPPY_CHUNK_HEADER_BYTES, "sNaPpY", LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN);
    cursor += LANTERN_SNAPPY_STREAM_HEADER_BYTES;

    uint8_t *chunk = cursor;
    chunk[0] = LANTERN_SNAPPY_CHUNK_COMPRESSED;
    uint8_t *crc_ptr = chunk + LANTERN_SNAPPY_CHUNK_HEADER_BYTES;
    uint8_t *payload = crc_ptr + LANTERN_SNAPPY_CHUNK_CRC_BYTES;

    size_t payload_offset = (size_t)(payload - output);
    if (payload_offset > output_len) {
        *written = 0;
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    size_t payload_capacity = output_len - payload_offset;

    struct snappy_env env;
    if (snappy_init_env(&env) != 0) {
        return LANTERN_SNAPPY_ERROR_UNSUPPORTED;
    }

    size_t compressed_len = payload_capacity;
    int rc = snappy_compress(
        &env,
        (const char *)input,
        input_len,
        (char *)payload,
        &compressed_len);
    snappy_free_env(&env);
    if (rc != 0 || compressed_len > raw_required) {
        *written = 0;
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    uint32_t crc = lantern_snappy_mask_crc32c(lantern_snappy_crc32c(input, input_len));
    lantern_snappy_write_le32(crc, crc_ptr);

    size_t chunk_len = LANTERN_SNAPPY_CHUNK_CRC_BYTES + compressed_len;
    if (chunk_len > LANTERN_SNAPPY_MAX_CHUNK_LEN) {
        *written = 0;
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    lantern_snappy_write_le24((uint32_t)chunk_len, &chunk[1]);

    cursor += LANTERN_SNAPPY_CHUNK_HEADER_BYTES + chunk_len;
    *written = (size_t)(cursor - output);
    return LANTERN_SNAPPY_OK;
}

int lantern_snappy_compress_raw(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written) {
    if (!input || !output || !written) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t required = snappy_max_compressed_length(input_len);
    if (output_len < required) {
        *written = required;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    struct snappy_env env;
    if (snappy_init_env(&env) != 0) {
        return LANTERN_SNAPPY_ERROR_UNSUPPORTED;
    }

    size_t compressed_len = output_len;
    int rc = snappy_compress(
        &env,
        (const char *)input,
        input_len,
        (char *)output,
        &compressed_len);
    snappy_free_env(&env);
    if (rc != 0) {
        *written = 0;
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    *written = compressed_len;
    return LANTERN_SNAPPY_OK;
}

int lantern_snappy_uncompressed_length(
    const uint8_t *input,
    size_t input_len,
    size_t *result) {
    if (!input || !result) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t framed_length = 0;
    if (lantern_snappy_framed_uncompressed_length(input, input_len, &framed_length) == LANTERN_SNAPPY_OK) {
        *result = framed_length;
        return LANTERN_SNAPPY_OK;
    }

    size_t raw_length = 0;
    if (snappy_uncompressed_length((const char *)input, input_len, &raw_length)) {
        *result = raw_length;
        return LANTERN_SNAPPY_OK;
    }

    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
}

int lantern_snappy_decompress(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written) {
    if (!input || !output || !written) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t expected = 0;
    if (lantern_snappy_framed_uncompressed_length(input, input_len, &expected) == LANTERN_SNAPPY_OK) {
        if (output_len < expected) {
            *written = expected;
            return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
        }
        return lantern_snappy_decompress_framed(input, input_len, output, output_len, written);
    }

    if (!snappy_uncompressed_length((const char *)input, input_len, &expected)) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    if (output_len < expected) {
        *written = expected;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }
    int rc = snappy_uncompress((const char *)input, input_len, (char *)output);
    if (rc != 0) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    *written = expected;
    return LANTERN_SNAPPY_OK;
}

static int lantern_snappy_framed_uncompressed_length(
    const uint8_t *input,
    size_t input_len,
    size_t *result) {
    size_t pos = 0;
    size_t total = 0;

    while (pos + 4 <= input_len) {
        uint8_t chunk_type = input[pos];
        uint32_t chunk_len = lantern_snappy_read_le24(&input[pos + 1]);
        pos += 4;
        if (chunk_len > input_len - pos) {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }
        const uint8_t *chunk = &input[pos];
        pos += chunk_len;

        if (chunk_type == LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER) {
            if (chunk_len != 6 || memcmp(chunk, "sNaPpY", 6) != 0) {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }
            continue;
        }

        if (chunk_type == LANTERN_SNAPPY_CHUNK_COMPRESSED || chunk_type == LANTERN_SNAPPY_CHUNK_UNCOMPRESSED) {
            if (chunk_len < 4) {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }
            size_t payload_len = chunk_len - 4;
            const uint8_t *payload = chunk + 4;
            if (chunk_type == LANTERN_SNAPPY_CHUNK_COMPRESSED) {
                size_t chunk_expected = 0;
                if (!snappy_uncompressed_length((const char *)payload, payload_len, &chunk_expected)) {
                    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
                }
                if (SIZE_MAX - total < chunk_expected) {
                    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
                }
                total += chunk_expected;
            } else {
                if (SIZE_MAX - total < payload_len) {
                    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
                }
                total += payload_len;
            }
            continue;
        }

        if (chunk_type >= LANTERN_SNAPPY_CHUNK_PADDING_START && chunk_type <= LANTERN_SNAPPY_CHUNK_PADDING_END) {
            continue;
        }

        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (pos != input_len) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (result) {
        *result = total;
    }
    return LANTERN_SNAPPY_OK;
}

static int lantern_snappy_decompress_framed(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written) {
    size_t pos = 0;
    size_t produced = 0;

    while (pos + 4 <= input_len) {
        uint8_t chunk_type = input[pos];
        uint32_t chunk_len = lantern_snappy_read_le24(&input[pos + 1]);
        pos += 4;
        if (chunk_len > input_len - pos) {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }
        const uint8_t *chunk = &input[pos];
        pos += chunk_len;

        if (chunk_type == LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER) {
            if (chunk_len != 6 || memcmp(chunk, "sNaPpY", 6) != 0) {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }
            continue;
        }

        if (chunk_type == LANTERN_SNAPPY_CHUNK_COMPRESSED || chunk_type == LANTERN_SNAPPY_CHUNK_UNCOMPRESSED) {
            if (chunk_len < 4) {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }
            const uint8_t *payload = chunk + 4;
            size_t payload_len = chunk_len - 4;

            if (chunk_type == LANTERN_SNAPPY_CHUNK_COMPRESSED) {
                size_t chunk_expected = 0;
                if (!snappy_uncompressed_length((const char *)payload, payload_len, &chunk_expected)) {
                    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
                }
                if (produced > output_len || chunk_expected > output_len - produced) {
                    *written = produced + chunk_expected;
                    return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
                }
                if (snappy_uncompress((const char *)payload, payload_len, (char *)output + produced) != 0) {
                    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
                }
                produced += chunk_expected;
            } else {
                if (produced > output_len || payload_len > output_len - produced) {
                    *written = produced + payload_len;
                    return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
                }
                memcpy(output + produced, payload, payload_len);
                produced += payload_len;
            }
            continue;
        }

        if (chunk_type >= LANTERN_SNAPPY_CHUNK_PADDING_START && chunk_type <= LANTERN_SNAPPY_CHUNK_PADDING_END) {
            continue;
        }

        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (pos != input_len) {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    *written = produced;
    return LANTERN_SNAPPY_OK;
}
