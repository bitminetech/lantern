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
static const size_t LANTERN_SNAPPY_INPUT_MARGIN_BYTES = 15u;
static const unsigned int LANTERN_SNAPPY_MIN_HASH_TABLE_BITS = 8u;
static const unsigned int LANTERN_SNAPPY_MAX_HASH_TABLE_BITS = 15u;
static const uint32_t LANTERN_SNAPPY_HASH_MULTIPLIER = UINT32_C(0x1E35A7BD);
static const uint8_t LANTERN_SNAPPY_RAW_LITERAL = 0x00u;
static const uint8_t LANTERN_SNAPPY_RAW_COPY_1 = 0x01u;
static const uint8_t LANTERN_SNAPPY_RAW_COPY_2 = 0x02u;
static const uint8_t LANTERN_SNAPPY_RAW_COPY_4 = 0x03u;
static const size_t LANTERN_SNAPPY_RAW_MAX_INLINE_LITERAL = 60u;
static const size_t LANTERN_SNAPPY_RAW_LITERAL_1_BYTE = 60u;
static const size_t LANTERN_SNAPPY_RAW_MIN_COPY_1_LENGTH = 4u;
static const size_t LANTERN_SNAPPY_RAW_MAX_COPY_1_LENGTH = 11u;
static const size_t LANTERN_SNAPPY_RAW_MAX_COPY_1_OFFSET = 2047u;
static const size_t LANTERN_SNAPPY_RAW_MAX_COPY_2_OFFSET = 65535u;

static const uint8_t LANTERN_SNAPPY_STREAM_IDENTIFIER_MAGIC[
    LANTERN_SNAPPY_STREAM_IDENTIFIER_LEN] = {
    's',
    'N',
    'a',
    'P',
    'p',
    'Y',
};

static size_t raw_varint32_size(uint32_t value)
{
    size_t size = 1u;
    while (value >= 0x80u)
    {
        value >>= 7u;
        ++size;
    }
    return size;
}

static int raw_write_varint32(
    uint32_t value,
    uint8_t *out,
    size_t out_len,
    size_t *written)
{
    if (!out || !written)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t required = raw_varint32_size(value);
    if (out_len < required)
    {
        *written = required;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    size_t index = 0u;
    do
    {
        uint8_t byte = (uint8_t)(value & 0x7fu);
        value >>= 7u;
        if (value != 0u)
        {
            byte |= 0x80u;
        }
        out[index++] = byte;
    } while (value != 0u);

    *written = index;
    return LANTERN_SNAPPY_OK;
}

static size_t raw_literal_tag_size(size_t length)
{
    if (length <= LANTERN_SNAPPY_RAW_MAX_INLINE_LITERAL)
    {
        return 1u;
    }
    if (length <= 256u)
    {
        return 2u;
    }
    if (length <= 65536u)
    {
        return 3u;
    }
    if (length <= 16777216u)
    {
        return 4u;
    }
    return 5u;
}

static int raw_write_literal_tag(
    size_t length,
    uint8_t *out,
    size_t out_len,
    size_t *written)
{
    if (!out || !written || length == 0u)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t required = raw_literal_tag_size(length);
    if (out_len < required)
    {
        *written = required;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    if (length <= LANTERN_SNAPPY_RAW_MAX_INLINE_LITERAL)
    {
        out[0] = (uint8_t)(((length - 1u) << 2u) | LANTERN_SNAPPY_RAW_LITERAL);
    }
    else
    {
        uint32_t len_minus_1 = (uint32_t)(length - 1u);
        size_t marker = LANTERN_SNAPPY_RAW_LITERAL_1_BYTE + (required - 2u);
        out[0] = (uint8_t)((marker << 2u) | LANTERN_SNAPPY_RAW_LITERAL);
        for (size_t i = 1u; i < required; ++i)
        {
            out[i] = (uint8_t)((len_minus_1 >> (8u * (i - 1u))) & 0xffu);
        }
    }

    *written = required;
    return LANTERN_SNAPPY_OK;
}

static size_t raw_copy_tag_size(size_t length, size_t offset)
{
    if (offset == 0u || length == 0u)
    {
        return 0u;
    }
    if (offset <= LANTERN_SNAPPY_RAW_MAX_COPY_1_OFFSET
        && length >= LANTERN_SNAPPY_RAW_MIN_COPY_1_LENGTH
        && length <= LANTERN_SNAPPY_RAW_MAX_COPY_1_LENGTH)
    {
        return 2u;
    }
    if (offset <= LANTERN_SNAPPY_RAW_MAX_COPY_2_OFFSET && length <= 64u)
    {
        return 3u;
    }
    if (length <= 64u)
    {
        return 5u;
    }
    return 0u;
}

static int raw_write_copy_tag(
    size_t length,
    size_t offset,
    uint8_t *out,
    size_t out_len,
    size_t *written)
{
    if (!out || !written)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t required = raw_copy_tag_size(length, offset);
    if (required == 0u)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    if (out_len < required)
    {
        *written = required;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    if (required == 2u)
    {
        uint8_t offset_high = (uint8_t)((offset >> 8u) & 0x07u);
        out[0] = (uint8_t)(
            (offset_high << 5u)
            | ((uint8_t)(length - LANTERN_SNAPPY_RAW_MIN_COPY_1_LENGTH) << 2u)
            | LANTERN_SNAPPY_RAW_COPY_1);
        out[1] = (uint8_t)(offset & 0xffu);
    }
    else if (required == 3u)
    {
        out[0] = (uint8_t)(((length - 1u) << 2u) | LANTERN_SNAPPY_RAW_COPY_2);
        out[1] = (uint8_t)(offset & 0xffu);
        out[2] = (uint8_t)((offset >> 8u) & 0xffu);
    }
    else
    {
        out[0] = (uint8_t)(((length - 1u) << 2u) | LANTERN_SNAPPY_RAW_COPY_4);
        out[1] = (uint8_t)(offset & 0xffu);
        out[2] = (uint8_t)((offset >> 8u) & 0xffu);
        out[3] = (uint8_t)((offset >> 16u) & 0xffu);
        out[4] = (uint8_t)((offset >> 24u) & 0xffu);
    }

    *written = required;
    return LANTERN_SNAPPY_OK;
}

static unsigned int raw_compute_table_bits(size_t block_size)
{
    unsigned int bits = LANTERN_SNAPPY_MIN_HASH_TABLE_BITS;
    size_t target = block_size / 4u;
    while ((((size_t)1u) << bits) < target && bits < LANTERN_SNAPPY_MAX_HASH_TABLE_BITS)
    {
        ++bits;
    }
    return bits;
}

static uint32_t raw_hash_4_bytes(const uint8_t *data, size_t pos, unsigned int table_bits)
{
    uint32_t value = (uint32_t)data[pos]
        | ((uint32_t)data[pos + 1u] << 8u)
        | ((uint32_t)data[pos + 2u] << 16u)
        | ((uint32_t)data[pos + 3u] << 24u);
    uint32_t hash = value * LANTERN_SNAPPY_HASH_MULTIPLIER;
    return hash >> (32u - table_bits);
}

static bool raw_matches_at(const uint8_t *data, size_t first, size_t second)
{
    return memcmp(data + first, data + second, 4u) == 0;
}

static size_t raw_extend_match(
    const uint8_t *data,
    size_t data_len,
    size_t match_pos,
    size_t current_pos)
{
    size_t length = 4u;
    while (length < 64u
        && current_pos + length < data_len
        && data[match_pos + length] == data[current_pos + length])
    {
        ++length;
    }
    return length;
}

static int raw_emit_literal(
    const uint8_t *literal,
    size_t literal_len,
    uint8_t *out,
    size_t out_len,
    size_t *written)
{
    if (!out || !written || (!literal && literal_len > 0u))
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t tag_len = 0u;
    int rc = raw_write_literal_tag(literal_len, out, out_len, &tag_len);
    if (rc != LANTERN_SNAPPY_OK)
    {
        return rc;
    }
    if (out_len - tag_len < literal_len)
    {
        *written = tag_len + literal_len;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    if (literal_len > 0u)
    {
        memcpy(out + tag_len, literal, literal_len);
    }
    *written = tag_len + literal_len;
    return LANTERN_SNAPPY_OK;
}

static int raw_compress_block(
    const uint8_t *block,
    size_t block_len,
    uint8_t *out,
    size_t out_len,
    size_t *written)
{
    if (!out || !written || (!block && block_len > 0u))
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    *written = 0u;

    if (block_len == 0u)
    {
        return LANTERN_SNAPPY_OK;
    }
    if (block_len < 4u)
    {
        return raw_emit_literal(block, block_len, out, out_len, written);
    }

    unsigned int table_bits = raw_compute_table_bits(block_len);
    size_t table_size = ((size_t)1u) << table_bits;
    ptrdiff_t *table = (ptrdiff_t *)malloc(table_size * sizeof(*table));
    if (!table)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    for (size_t i = 0u; i < table_size; ++i)
    {
        table[i] = (ptrdiff_t)-1;
    }

    size_t produced = 0u;
    size_t literal_start = 0u;
    size_t ip = 0u;

    while (ip + LANTERN_SNAPPY_INPUT_MARGIN_BYTES < block_len)
    {
        uint32_t hash_val = raw_hash_4_bytes(block, ip, table_bits);
        ptrdiff_t match_pos = table[hash_val];
        table[hash_val] = (ptrdiff_t)ip;

        if (match_pos >= 0 && raw_matches_at(block, (size_t)match_pos, ip))
        {
            if (ip > literal_start)
            {
                size_t literal_written = 0u;
                int rc = raw_emit_literal(
                    block + literal_start,
                    ip - literal_start,
                    out + produced,
                    out_len - produced,
                    &literal_written);
                if (rc != LANTERN_SNAPPY_OK)
                {
                    free(table);
                    return rc;
                }
                produced += literal_written;
            }

            size_t match_length = raw_extend_match(block, block_len, (size_t)match_pos, ip);
            size_t copy_written = 0u;
            int rc = raw_write_copy_tag(
                match_length,
                ip - (size_t)match_pos,
                out + produced,
                out_len - produced,
                &copy_written);
            if (rc != LANTERN_SNAPPY_OK)
            {
                free(table);
                return rc;
            }
            produced += copy_written;
            ip += match_length;
            literal_start = ip;

            if (match_length > 1u && ip + LANTERN_SNAPPY_INPUT_MARGIN_BYTES < block_len)
            {
                for (size_t skip = ip - match_length + 1u; skip < ip - 1u; skip += 2u)
                {
                    uint32_t skip_hash = raw_hash_4_bytes(block, skip, table_bits);
                    table[skip_hash] = (ptrdiff_t)skip;
                }
            }
        }
        else
        {
            ++ip;
        }
    }

    if (literal_start < block_len)
    {
        size_t literal_written = 0u;
        int rc = raw_emit_literal(
            block + literal_start,
            block_len - literal_start,
            out + produced,
            out_len - produced,
            &literal_written);
        if (rc != LANTERN_SNAPPY_OK)
        {
            free(table);
            return rc;
        }
        produced += literal_written;
    }

    free(table);
    *written = produced;
    return LANTERN_SNAPPY_OK;
}

static int raw_compress_deterministic(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written)
{
    if ((!input && input_len > 0u) || !output || !written)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    *written = 0u;
    if (input_len > UINT32_MAX)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t offset = 0u;
    size_t header_written = 0u;
    int rc = raw_write_varint32((uint32_t)input_len, output, output_len, &header_written);
    if (rc != LANTERN_SNAPPY_OK)
    {
        return rc;
    }
    offset += header_written;

    while (input_len > 0u)
    {
        size_t chunk_len = input_len > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            ? LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            : input_len;
        size_t chunk_written = 0u;
        rc = raw_compress_block(input, chunk_len, output + offset, output_len - offset, &chunk_written);
        if (rc != LANTERN_SNAPPY_OK)
        {
            return rc;
        }
        offset += chunk_written;
        input += chunk_len;
        input_len -= chunk_len;
    }

    *written = offset;
    return LANTERN_SNAPPY_OK;
}

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

    while (remaining > 0)
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
    }

    *max_size = total;
    return LANTERN_SNAPPY_OK;
}


static int process_framed(
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
    if ((!input && input_len > 0u) || !output || !written)
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

    if (input_len == 0u)
    {
        *written = (size_t)(cursor - output);
        return LANTERN_SNAPPY_OK;
    }

    const uint8_t *input_cursor = input;
    size_t remaining = input_len;

    while (remaining > 0)
    {
        size_t chunk_input_len = remaining > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            ? LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            : remaining;

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

        size_t compressed_len = 0u;
        int snappy_rc = raw_compress_deterministic(
            input_cursor,
            chunk_input_len,
            payload,
            output_len - payload_offset,
            &compressed_len);
        if (snappy_rc != LANTERN_SNAPPY_OK)
        {
            result = LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            goto cleanup;
        }

        uint32_t crc = mask_crc32c(crc32c(input_cursor, chunk_input_len));
        write_le32(crc, crc_ptr);

        size_t payload_len = compressed_len;
        uint8_t chunk_type = (uint8_t)LANTERN_SNAPPY_CHUNK_COMPRESSED;
        if (compressed_len >= chunk_input_len)
        {
            chunk_type = (uint8_t)LANTERN_SNAPPY_CHUNK_UNCOMPRESSED;
            if (chunk_input_len > 0u)
            {
                memcpy(payload, input_cursor, chunk_input_len);
            }
            payload_len = chunk_input_len;
        }

        cursor[0] = chunk_type;
        size_t chunk_payload_len = (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES + payload_len;
        if (chunk_payload_len > (size_t)LANTERN_SNAPPY_MAX_CHUNK_LEN)
        {
            result = LANTERN_SNAPPY_ERROR_INVALID_INPUT;
            goto cleanup;
        }

        write_le24((uint32_t)chunk_payload_len, chunk_len_bytes);
        cursor += (size_t)LANTERN_SNAPPY_CHUNK_HEADER_BYTES + chunk_payload_len;

        input_cursor += chunk_input_len;
        remaining -= chunk_input_len;
    }

    *written = (size_t)(cursor - output);
    result = LANTERN_SNAPPY_OK;

cleanup:
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
    if ((!input && input_len > 0u) || !output || !written)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t required = input_len == 0u ? 1u : snappy_max_compressed_length(input_len);
    if (output_len < required)
    {
        *written = required;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }
    return raw_compress_deterministic(input, input_len, output, output_len, written);
}


bool lantern_snappy_is_framed(const uint8_t *input, size_t input_len)
{
    if (!input)
    {
        return false;
    }

    size_t offset = 0;
    struct lantern_snappy_chunk_view chunk = {0};
    bool has_chunk = false;

    int rc = parse_next_chunk(input, input_len, &offset, &chunk, &has_chunk);
    if (rc != LANTERN_SNAPPY_OK || !has_chunk)
    {
        return false;
    }

    return validate_stream_identifier(&chunk) == LANTERN_SNAPPY_OK;
}


/**
 * Computes the uncompressed length of raw (unframed) Snappy input.
 *
 * @param input      Input buffer (raw Snappy).
 * @param input_len  Input length in bytes.
 * @param result     Output pointer receiving the uncompressed length in bytes.
 *
 * @return LANTERN_SNAPPY_OK on success.
 * @return LANTERN_SNAPPY_ERROR_INVALID_INPUT on invalid arguments or malformed data.
 *
 * @note Thread safety: This function is thread-safe.
 */
int lantern_snappy_uncompressed_length_raw(const uint8_t *input, size_t input_len, size_t *result)
{
    if (!input || !result)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }
    if (lantern_snappy_is_framed(input, input_len))
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t raw_length = 0;
    if (!snappy_uncompressed_length((const char *)input, input_len, &raw_length))
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    *result = raw_length;
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
    if (process_framed(input, input_len, NULL, 0u, &framed_length) == LANTERN_SNAPPY_OK)
    {
        *result = framed_length;
        return LANTERN_SNAPPY_OK;
    }

    return lantern_snappy_uncompressed_length_raw(input, input_len, result);
}


/**
 * Decompresses raw (unframed) Snappy input into an output buffer.
 *
 * @param input       Input buffer (raw Snappy).
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
int lantern_snappy_decompress_raw(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written)
{
    if (!input || !written || (!output && output_len > 0u))
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t expected = 0;
    if (lantern_snappy_uncompressed_length_raw(input, input_len, &expected) != LANTERN_SNAPPY_OK)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    if (output_len < expected)
    {
        *written = expected;
        return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
    }

    if (expected == 0u)
    {
        *written = 0u;
        return LANTERN_SNAPPY_OK;
    }

    if (snappy_uncompress((const char *)input, input_len, (char *)output) != 0)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    *written = expected;
    return LANTERN_SNAPPY_OK;
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
    if (!input || !written || (!output && output_len > 0u))
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t expected = 0;
    if (process_framed(input, input_len, NULL, 0u, &expected) == LANTERN_SNAPPY_OK)
    {
        if (output_len < expected)
        {
            *written = expected;
            return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
        }

        if (expected == 0u)
        {
            *written = 0u;
            return LANTERN_SNAPPY_OK;
        }

        return process_framed(input, input_len, output, output_len, written);
    }

    return lantern_snappy_decompress_raw(input, input_len, output, output_len, written);
}

static int process_framed(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written)
{
    if (!input || !written || (!output && output_len > 0u))
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    size_t offset = 0u;
    size_t produced = 0u;
    struct lantern_snappy_chunk_view chunk = {0};
    bool has_chunk = false;
    if (parse_next_chunk(input, input_len, &offset, &chunk, &has_chunk) != LANTERN_SNAPPY_OK
        || !has_chunk
        || validate_stream_identifier(&chunk) != LANTERN_SNAPPY_OK)
    {
        return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
    }

    while (offset < input_len)
    {
        if (parse_next_chunk(input, input_len, &offset, &chunk, &has_chunk) != LANTERN_SNAPPY_OK
            || !has_chunk)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
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
        if ((chunk.type != (uint8_t)LANTERN_SNAPPY_CHUNK_COMPRESSED
             && chunk.type != (uint8_t)LANTERN_SNAPPY_CHUNK_UNCOMPRESSED)
            || chunk.payload_len < (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }

        const uint8_t *data = chunk.payload + (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES;
        size_t data_len = chunk.payload_len - (size_t)LANTERN_SNAPPY_CHUNK_CRC_BYTES;
        bool compressed = chunk.type == (uint8_t)LANTERN_SNAPPY_CHUNK_COMPRESSED;
        size_t chunk_len = data_len;
        if (compressed
            && !snappy_uncompressed_length((const char *)data, data_len, &chunk_len))
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }
        if (chunk_len > LANTERN_SNAPPY_MAX_UNCOMPRESSED_CHUNK_SIZE
            || produced > SIZE_MAX - chunk_len)
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }
        if (output)
        {
            if (produced > output_len || chunk_len > output_len - produced)
            {
                *written = produced + chunk_len;
                return LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL;
            }
            if (compressed)
            {
                if (snappy_uncompress(
                        (const char *)data,
                        data_len,
                        (char *)output + produced)
                    != 0)
                {
                    return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
                }
            }
            else if (chunk_len > 0u)
            {
                memcpy(output + produced, data, chunk_len);
            }
        }
        if ((output || !compressed)
            && read_le32(chunk.payload)
                   != mask_crc32c(crc32c(output ? output + produced : data, chunk_len)))
        {
            return LANTERN_SNAPPY_ERROR_INVALID_INPUT;
        }
        produced += chunk_len;
    }

    *written = produced;
    return LANTERN_SNAPPY_OK;
}
