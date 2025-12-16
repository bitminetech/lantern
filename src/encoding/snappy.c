/**
 * @file snappy.c
 * @brief Snappy compression and decompression helpers (raw and framed streams).
 *
 * Supports:
 * - Raw Snappy blocks (no framing, no CRC)
 * - Snappy framed streams (stream identifier + per-chunk CRC32C + chunked compression)
 *
 * The framed format is commonly used for `/ssz_snappy` request/response payloads.
 */

#include "lantern/encoding/snappy.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "snappy.h"

enum
{
    LANTERN_SNAPPY_CHUNK_COMPRESSED = 0x00,
    LANTERN_SNAPPY_CHUNK_UNCOMPRESSED = 0x01,
    LANTERN_SNAPPY_CHUNK_PADDING_START = 0x02,
    LANTERN_SNAPPY_CHUNK_PADDING_END = 0x7f,
    LANTERN_SNAPPY_CHUNK_RESERVED_START = 0x80,
    LANTERN_SNAPPY_CHUNK_RESERVED_END = 0xfe,
    LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER = 0xff,
};

enum
{
    LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN = 6,
    LANTERN_SNAPPY_CHUNK_HEADER_BYTES = 4,
    LANTERN_SNAPPY_CHUNK_CRC_BYTES = 4,
    LANTERN_SNAPPY_STREAM_HEADER_BYTES = LANTERN_SNAPPY_CHUNK_HEADER_BYTES
        + LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN,
    LANTERN_SNAPPY_MAX_CHUNK_LEN = 0x00ffffffu,
};

static const size_t LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE = 65536u;

static const uint8_t LANTERN_SNAPPY_STREAM_IDENTIFIER_MAGIC[
    LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN] = {
    's',
    'N',
    'a',
    'P',
    'p',
    'Y',
};

/**
 * @brief Parsed view of a Snappy framed chunk.
 */
struct lantern_snappy_chunk_view
{
    uint8_t type;           /**< Chunk type byte */
    const uint8_t *payload; /**< Chunk payload bytes */
    size_t payload_len;     /**< Length of chunk payload in bytes */
};

/**
 * @brief Reads a 24-bit little-endian integer.
 */
static uint32_t read_le24(const uint8_t *data)
{
    return (uint32_t)data[0]
        | ((uint32_t)data[1] << 8u)
        | ((uint32_t)data[2] << 16u);
}


/**
 * @brief Writes a 24-bit little-endian integer.
 */
static void write_le24(uint32_t value, uint8_t *dst)
{
    dst[0] = (uint8_t)(value & 0xffu);
    dst[1] = (uint8_t)((value >> 8u) & 0xffu);
    dst[2] = (uint8_t)((value >> 16u) & 0xffu);
}


/**
 * @brief Reads a 32-bit little-endian integer.
 */
static uint32_t read_le32(const uint8_t *data)
{
    return (uint32_t)data[0]
        | ((uint32_t)data[1] << 8u)
        | ((uint32_t)data[2] << 16u)
        | ((uint32_t)data[3] << 24u);
}


/**
 * @brief Writes a 32-bit little-endian integer.
 */
static void write_le32(uint32_t value, uint8_t *dst)
{
    dst[0] = (uint8_t)(value & 0xffu);
    dst[1] = (uint8_t)((value >> 8u) & 0xffu);
    dst[2] = (uint8_t)((value >> 16u) & 0xffu);
    dst[3] = (uint8_t)((value >> 24u) & 0xffu);
}


/**
 * @brief Computes CRC32C for a byte slice.
 */
static uint32_t crc32c(const uint8_t *data, size_t len)
{
    const uint32_t poly = UINT32_C(0x82f63b78);
    uint32_t crc = UINT32_C(0xffffffff);

    for (size_t i = 0; i < len; ++i)
    {
        crc ^= (uint32_t)data[i];
        for (size_t bit = 0; bit < 8u; ++bit)
        {
            if ((crc & 1u) != 0u)
            {
                crc = (crc >> 1u) ^ poly;
            }
            else
            {
                crc >>= 1u;
            }
        }
    }

    return ~crc;
}


/**
 * @brief Applies Snappy's masking to a CRC32C value (framed stream format).
 */
static uint32_t mask_crc32c(uint32_t crc)
{
    uint32_t rotated = (crc >> 15u) | (crc << 17u);
    return rotated + UINT32_C(0xa282ead8);
}


/**
 * @brief Returns true if a chunk type is skippable padding.
 */
static bool is_padding_chunk_type(uint8_t chunk_type)
{
    return chunk_type >= (uint8_t)LANTERN_SNAPPY_CHUNK_PADDING_START
        && chunk_type <= (uint8_t)LANTERN_SNAPPY_CHUNK_PADDING_END;
}


/**
 * @brief Parses the next chunk from a framed stream.
 *
 * @param input      Input buffer
 * @param input_len  Input buffer length in bytes
 * @param offset     In/out offset into the buffer
 * @param chunk      Output chunk view
 * @param has_chunk  Set to true when a chunk is parsed, false at end-of-stream
 *
 * @return LANTERN_SNAPPY_OK on success
 * @return LANTERN_SNAPPY_ERROR_INVALID_INPUT if framing is malformed
 */
static int parse_next_chunk(
    const uint8_t *input,
    size_t input_len,
    size_t *offset,
    struct lantern_snappy_chunk_view *chunk,
    bool *has_chunk)
{
    if (!input || !offset || !chunk || !has_chunk)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (*offset == input_len)
    {
        *has_chunk = false;
        return LANTERN_SNAPPY_OK;
    }

    if (*offset > input_len)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (input_len - *offset < (size_t)LANTERN_SNAPPY_CHUNK_HEADER_BYTES)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    chunk->type = input[*offset];
    uint32_t chunk_len_u32 = read_le24(&input[*offset + 1u]);
    size_t chunk_len = (size_t)chunk_len_u32;

    *offset += (size_t)LANTERN_SNAPPY_CHUNK_HEADER_BYTES;
    if (chunk_len > input_len - *offset)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    chunk->payload = input + *offset;
    chunk->payload_len = chunk_len;
    *offset += chunk_len;

    *has_chunk = true;
    return LANTERN_SNAPPY_OK;
}


/**
 * @brief Validates the framed stream identifier chunk.
 */
static int validate_stream_identifier(const struct lantern_snappy_chunk_view *chunk)
{
    if (!chunk)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (chunk->type != (uint8_t)LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (chunk->payload_len != (size_t)LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (memcmp(chunk->payload, LANTERN_SNAPPY_STREAM_IDENTIFIER_MAGIC, chunk->payload_len) != 0)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    return LANTERN_SNAPPY_OK;
}


/**
 * @brief Computes the worst-case framed output size for an input length.
 */
static int framed_max_compressed_size(size_t input_len, size_t *max_size)
{
    if (!max_size)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t total = (size_t)LANTERN_SNAPPY_STREAM_HEADER_BYTES;
    size_t remaining = input_len;

    do
    {
        size_t chunk_len = remaining > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            ? LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            : remaining;

        size_t max_chunk_compressed = snappy_max_compressed_length(chunk_len);
        size_t chunk_overhead = (size_t)LANTERN_SNAPPY_CHUNK_HEADER_BYTES
            + (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES;

        if (SIZE_MAX - total < chunk_overhead)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }
        total += chunk_overhead;

        if (SIZE_MAX - total < max_chunk_compressed)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }
        total += max_chunk_compressed;

        remaining -= chunk_len;
    } while (remaining > 0);

    *max_size = total;
    return LANTERN_SNAPPY_OK;
}


/**
 * @brief Computes the uncompressed length of a framed Snappy stream.
 */
static int framed_uncompressed_length(const uint8_t *input, size_t input_len, size_t *result);

/**
 * @brief Decompresses a framed Snappy stream into an output buffer.
 */
static int decompress_framed(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written);


/**
 * Computes the maximum size required to compress a payload using the framed
 * Snappy stream format.
 *
 * @param input_len Length of input data in bytes.
 * @param max_size  Output pointer receiving the maximum required size in bytes.
 *
 * @return LANTERN_SNAPPY_OK on success.
 * @return LANTERN_SNAPPY_ERROR_INVALID_INPUT if `max_size` is NULL or on overflow.
 *
 * @note Thread safety: This function is thread-safe.
 */
int lantern_snappy_max_compressed_size(size_t input_len, size_t *max_size)
{
    return framed_max_compressed_size(input_len, max_size);
}


/**
 * Computes the maximum size required to compress a payload using raw (unframed)
 * Snappy.
 *
 * @param input_len Length of input data in bytes.
 * @param max_size  Output pointer receiving the maximum required size in bytes.
 *
 * @return LANTERN_SNAPPY_OK on success.
 * @return LANTERN_SNAPPY_ERROR_INVALID_INPUT if `max_size` is NULL.
 *
 * @note Thread safety: This function is thread-safe.
 */
int lantern_snappy_max_compressed_size_raw(size_t input_len, size_t *max_size)
{
    if (!max_size)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    *max_size = snappy_max_compressed_length(input_len);
    return LANTERN_SNAPPY_OK;
}


/**
 * Compresses input bytes using the framed Snappy stream format.
 *
 * Produces a stream identifier chunk followed by one or more data chunks. Each
 * data chunk contains a CRC32C (masked) of the uncompressed bytes for that chunk.
 *
 * @param input       Input data to compress.
 * @param input_len   Input length in bytes.
 * @param output      Output buffer for framed data.
 * @param output_len  Output buffer capacity in bytes.
 * @param written     Output pointer receiving bytes written (or required size on
 *                    LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL).
 *
 * @return LANTERN_SNAPPY_OK on success.
 * @return LANTERN_SNAPPY_ERROR_INVALID_INPUT on invalid arguments or overflow.
 * @return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL if `output_len` is too small.
 * @return LANTERN_SNAPPY_ERROR_UNSUPPORTED if the Snappy backend cannot initialize.
 *
 * @note Thread safety: This function is thread-safe.
 */
int lantern_snappy_compress(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written)
{
    if (!input || !output || !written)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t required = 0;
    int result = framed_max_compressed_size(input_len, &required);
    if (result != LANTERN_SNAPPY_OK)
    {
        return result;
    }

    if (output_len < required)
    {
        *written = required;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    uint8_t *cursor = output;

    cursor[0] = (uint8_t)LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER;
    write_le24((uint32_t)LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN, cursor + 1u);
    memcpy(
        cursor + (size_t)LANTERN_SNAPPY_CHUNK_HEADER_BYTES,
        LANTERN_SNAPPY_STREAM_IDENTIFIER_MAGIC,
        (size_t)LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN);
    cursor += (size_t)LANTERN_SNAPPY_STREAM_HEADER_BYTES;

    struct snappy_env env;
    bool env_initialized = false;

    if (snappy_init_env(&env) != 0)
    {
        return LANTERN_SNAPPY_ERROR_UNSUPPORTED;
    }
    env_initialized = true;

    const uint8_t *input_cursor = input;
    size_t remaining = input_len;

    do
    {
        size_t chunk_input_len = remaining > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            ? LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            : remaining;

        cursor[0] = (uint8_t)LANTERN_SNAPPY_CHUNK_COMPRESSED;
        uint8_t *chunk_len_bytes = cursor + 1u;
        uint8_t *crc_ptr = cursor + (size_t)LANTERN_SNAPPY_CHUNK_HEADER_BYTES;
        uint8_t *payload = crc_ptr + (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES;

        size_t max_chunk_compressed = snappy_max_compressed_length(chunk_input_len);
        size_t payload_offset = (size_t)(payload - output);
        if (payload_offset > output_len || output_len - payload_offset < max_chunk_compressed)
        {
            result = LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            goto cleanup;
        }

        size_t compressed_len = max_chunk_compressed;
        int snappy_rc = snappy_compress(
            &env,
            (const char *)input_cursor,
            chunk_input_len,
            (char *)payload,
            &compressed_len);
        if (snappy_rc != 0)
        {
            result = LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            goto cleanup;
        }

        uint32_t crc = mask_crc32c(crc32c(input_cursor, chunk_input_len));
        write_le32(crc, crc_ptr);

        size_t chunk_payload_len = (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES + compressed_len;
        if (chunk_payload_len > (size_t)LANTERN_SNAPPY_MAX_CHUNK_LEN)
        {
            result = LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            goto cleanup;
        }

        write_le24((uint32_t)chunk_payload_len, chunk_len_bytes);
        cursor += (size_t)LANTERN_SNAPPY_CHUNK_HEADER_BYTES + chunk_payload_len;

        input_cursor += chunk_input_len;
        remaining -= chunk_input_len;
    } while (remaining > 0);

    *written = (size_t)(cursor - output);
    result = LANTERN_SNAPPY_OK;

cleanup:
    if (env_initialized)
    {
        snappy_free_env(&env);
    }

    if (result != LANTERN_SNAPPY_OK)
    {
        *written = 0;
    }

    return result;
}


/**
 * Compresses input bytes using raw (unframed) Snappy.
 *
 * @param input       Input data to compress.
 * @param input_len   Input length in bytes.
 * @param output      Output buffer for raw Snappy data.
 * @param output_len  Output buffer capacity in bytes.
 * @param written     Output pointer receiving bytes written (or required size on
 *                    LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL).
 *
 * @return LANTERN_SNAPPY_OK on success.
 * @return LANTERN_SNAPPY_ERROR_INVALID_INPUT on invalid arguments.
 * @return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL if `output_len` is too small.
 * @return LANTERN_SNAPPY_ERROR_UNSUPPORTED if the Snappy backend cannot initialize.
 *
 * @note Thread safety: This function is thread-safe.
 */
int lantern_snappy_compress_raw(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written)
{
    if (!input || !output || !written)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t required = snappy_max_compressed_length(input_len);
    if (output_len < required)
    {
        *written = required;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    struct snappy_env env;
    if (snappy_init_env(&env) != 0)
    {
        return LANTERN_SNAPPY_ERROR_UNSUPPORTED;
    }

    size_t compressed_len = output_len;
    int snappy_rc = snappy_compress(
        &env,
        (const char *)input,
        input_len,
        (char *)output,
        &compressed_len);
    snappy_free_env(&env);

    if (snappy_rc != 0)
    {
        *written = 0;
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    *written = compressed_len;
    return LANTERN_SNAPPY_OK;
}


/**
 * Computes the uncompressed length of either a framed or raw Snappy input.
 *
 * @param input      Input buffer (framed or raw Snappy).
 * @param input_len  Input length in bytes.
 * @param result     Output pointer receiving the uncompressed length in bytes.
 *
 * @return LANTERN_SNAPPY_OK on success.
 * @return LANTERN_SNAPPY_ERROR_INVALID_INPUT on invalid arguments or malformed data.
 *
 * @note Thread safety: This function is thread-safe.
 */
int lantern_snappy_uncompressed_length(const uint8_t *input, size_t input_len, size_t *result)
{
    if (!input || !result)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t framed_length = 0;
    if (framed_uncompressed_length(input, input_len, &framed_length) == LANTERN_SNAPPY_OK)
    {
        *result = framed_length;
        return LANTERN_SNAPPY_OK;
    }

    size_t raw_length = 0;
    if (snappy_uncompressed_length((const char *)input, input_len, &raw_length))
    {
        *result = raw_length;
        return LANTERN_SNAPPY_OK;
    }

    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
}


/**
 * Decompresses either framed or raw Snappy input into an output buffer.
 *
 * @param input       Input buffer (framed or raw Snappy).
 * @param input_len   Input length in bytes.
 * @param output      Output buffer for uncompressed bytes.
 * @param output_len  Output buffer capacity in bytes.
 * @param written     Output pointer receiving bytes written (or required size on
 *                    LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL).
 *
 * @return LANTERN_SNAPPY_OK on success.
 * @return LANTERN_SNAPPY_ERROR_INVALID_INPUT on invalid arguments or malformed data.
 * @return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL if `output_len` is too small.
 *
 * @note Thread safety: This function is thread-safe.
 */
int lantern_snappy_decompress(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written)
{
    if (!input || !output || !written)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t expected = 0;
    if (framed_uncompressed_length(input, input_len, &expected) == LANTERN_SNAPPY_OK)
    {
        if (output_len < expected)
        {
            *written = expected;
            return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
        }

        return decompress_framed(input, input_len, output, output_len, written);
    }

    if (!snappy_uncompressed_length((const char *)input, input_len, &expected))
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (output_len < expected)
    {
        *written = expected;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    if (snappy_uncompress((const char *)input, input_len, (char *)output) != 0)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    *written = expected;
    return LANTERN_SNAPPY_OK;
}


static int framed_uncompressed_length(const uint8_t *input, size_t input_len, size_t *result)
{
    if (!input || !result)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t offset = 0;
    size_t total = 0;

    struct lantern_snappy_chunk_view chunk = {0};
    bool has_chunk = false;

    int rc = parse_next_chunk(input, input_len, &offset, &chunk, &has_chunk);
    if (rc != LANTERN_SNAPPY_OK || !has_chunk)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (validate_stream_identifier(&chunk) != LANTERN_SNAPPY_OK)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    while (true)
    {
        rc = parse_next_chunk(input, input_len, &offset, &chunk, &has_chunk);
        if (rc != LANTERN_SNAPPY_OK)
        {
            return rc;
        }
        if (!has_chunk)
        {
            break;
        }

        if (chunk.type == (uint8_t)LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER)
        {
            if (validate_stream_identifier(&chunk) != LANTERN_SNAPPY_OK)
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }
            continue;
        }

        if (is_padding_chunk_type(chunk.type))
        {
            continue;
        }

        if (chunk.type != (uint8_t)LANTERN_SNAPPY_CHUNK_COMPRESSED
            && chunk.type != (uint8_t)LANTERN_SNAPPY_CHUNK_UNCOMPRESSED)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        if (chunk.payload_len < (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        const uint8_t *payload = chunk.payload + (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES;
        size_t payload_len = chunk.payload_len - (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES;

        if (chunk.type == (uint8_t)LANTERN_SNAPPY_CHUNK_COMPRESSED)
        {
            size_t chunk_expected = 0;
            if (!snappy_uncompressed_length((const char *)payload, payload_len, &chunk_expected))
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }

            if (chunk_expected > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE)
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }

            if (SIZE_MAX - total < chunk_expected)
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }
            total += chunk_expected;
            continue;
        }

        if (payload_len > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        uint32_t expected_crc = read_le32(chunk.payload);
        uint32_t computed_crc = mask_crc32c(crc32c(payload, payload_len));
        if (expected_crc != computed_crc)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        if (SIZE_MAX - total < payload_len)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }
        total += payload_len;
    }

    *result = total;
    return LANTERN_SNAPPY_OK;
}


static int decompress_framed(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written)
{
    if (!input || !output || !written)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t offset = 0;
    size_t produced = 0;

    struct lantern_snappy_chunk_view chunk = {0};
    bool has_chunk = false;

    int rc = parse_next_chunk(input, input_len, &offset, &chunk, &has_chunk);
    if (rc != LANTERN_SNAPPY_OK || !has_chunk)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (validate_stream_identifier(&chunk) != LANTERN_SNAPPY_OK)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    while (true)
    {
        rc = parse_next_chunk(input, input_len, &offset, &chunk, &has_chunk);
        if (rc != LANTERN_SNAPPY_OK)
        {
            return rc;
        }
        if (!has_chunk)
        {
            break;
        }

        if (chunk.type == (uint8_t)LANTERN_SNAPPY_CHUNK_STREAM_IDENTIFIER)
        {
            if (validate_stream_identifier(&chunk) != LANTERN_SNAPPY_OK)
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }
            continue;
        }

        if (is_padding_chunk_type(chunk.type))
        {
            continue;
        }

        if (chunk.type != (uint8_t)LANTERN_SNAPPY_CHUNK_COMPRESSED
            && chunk.type != (uint8_t)LANTERN_SNAPPY_CHUNK_UNCOMPRESSED)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        if (chunk.payload_len < (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        uint32_t expected_crc = read_le32(chunk.payload);
        const uint8_t *payload = chunk.payload + (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES;
        size_t payload_len = chunk.payload_len - (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES;

        if (chunk.type == (uint8_t)LANTERN_SNAPPY_CHUNK_COMPRESSED)
        {
            size_t chunk_expected = 0;
            if (!snappy_uncompressed_length((const char *)payload, payload_len, &chunk_expected))
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }

            if (chunk_expected > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE)
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }

            if (produced > output_len || chunk_expected > output_len - produced)
            {
                if (produced > SIZE_MAX - chunk_expected)
                {
                    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
                }
                *written = produced + chunk_expected;
                return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
            }

            if (snappy_uncompress(
                    (const char *)payload,
                    payload_len,
                    (char *)output + produced)
                != 0)
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }

            uint32_t computed_crc = mask_crc32c(crc32c(output + produced, chunk_expected));
            if (expected_crc != computed_crc)
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }

            produced += chunk_expected;
            continue;
        }

        if (payload_len > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        if (produced > output_len || payload_len > output_len - produced)
        {
            if (produced > SIZE_MAX - payload_len)
            {
                return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            }
            *written = produced + payload_len;
            return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
        }

        uint32_t computed_crc = mask_crc32c(crc32c(payload, payload_len));
        if (expected_crc != computed_crc)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        memcpy(output + produced, payload, payload_len);
        produced += payload_len;
    }

    *written = produced;
    return LANTERN_SNAPPY_OK;
}
