/**
 * @file rlp.c
 * @brief Recursive Length Prefix (RLP) encoding and decoding.
 *
 * Implements Ethereum RLP encoding/decoding for byte strings and lists.
 *
 * @spec Ethereum Recursive Length Prefix (RLP)
 */

#include "lantern/encoding/rlp.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/**
 * RLP module-specific error codes.
 */
enum
{
    LANTERN_RLP_OK = 0,
    LANTERN_RLP_ERR_INVALID_PARAM = -1,
    LANTERN_RLP_ERR_OUT_OF_MEMORY = -2,
    LANTERN_RLP_ERR_OVERFLOW = -3,
    LANTERN_RLP_ERR_INVALID_ENCODING = -4,
    LANTERN_RLP_ERR_TRAILING_DATA = -5,
};

static const size_t RLP_SHORT_PAYLOAD_MAX = 55;
static const size_t RLP_INITIAL_LIST_CAPACITY = 4;
static const size_t LANTERN_RLP_MAX_NESTING_DEPTH = 64;

static const uint8_t RLP_PREFIX_SINGLE_BYTE_MAX = 0x7Fu;
static const uint8_t RLP_PREFIX_SHORT_STRING_BASE = 0x80u;
static const uint8_t RLP_PREFIX_SHORT_STRING_MAX = 0xB7u;
static const uint8_t RLP_PREFIX_LONG_STRING_BASE = 0xB7u;
static const uint8_t RLP_PREFIX_LONG_STRING_MAX = 0xBFu;
static const uint8_t RLP_PREFIX_SHORT_LIST_BASE = 0xC0u;
static const uint8_t RLP_PREFIX_SHORT_LIST_MAX = 0xF7u;
static const uint8_t RLP_PREFIX_LONG_LIST_BASE = 0xF7u;

/**
 * @brief Cursor for safe incremental decoding.
 */
struct lantern_rlp_cursor
{
    const uint8_t *data; /**< Start of encoded buffer */
    size_t length;       /**< Total bytes available */
    size_t offset;       /**< Current read offset */
};

static int decode_item(struct lantern_rlp_cursor *cursor, struct lantern_rlp_view *view, size_t depth);

static int decode_list_payload(
    struct lantern_rlp_cursor *cursor,
    size_t payload_length,
    struct lantern_rlp_view *view,
    size_t depth);

/**
 * @brief Zero an RLP view (does not free child items).
 */
static void rlp_view_zero(struct lantern_rlp_view *view)
{
    if (!view)
    {
        return;
    }

    view->kind = 0;
    view->data = NULL;
    view->length = 0;
    view->items = NULL;
    view->item_count = 0;
}


/**
 * Reset an RLP view and free any owned children.
 *
 * @param view View to reset. Safe to call with NULL.
 *
 * @note Thread safety: Caller must ensure exclusive access to view.
 */
void lantern_rlp_view_reset(struct lantern_rlp_view *view)
{
    if (!view)
    {
        return;
    }

    if (view->kind == LANTERN_RLP_KIND_LIST && view->items)
    {
        for (size_t i = 0; i < view->item_count; i++)
        {
            lantern_rlp_view_reset(&view->items[i]);
        }

        free(view->items);
    }

    rlp_view_zero(view);
}


/**
 * Reset an RLP buffer and free any owned data.
 *
 * @param buffer Buffer to reset. Safe to call with NULL.
 *
 * @note Thread safety: Caller must ensure exclusive access to buffer.
 */
void lantern_rlp_buffer_reset(struct lantern_rlp_buffer *buffer)
{
    if (!buffer)
    {
        return;
    }

    free(buffer->data);
    buffer->data = NULL;
    buffer->length = 0;
}


/**
 * @brief Returns true if a + b would overflow size_t.
 */
static bool size_add_would_overflow(size_t a, size_t b, size_t *out)
{
    if (!out)
    {
        return true;
    }

    if (a > SIZE_MAX - b)
    {
        return true;
    }

    *out = a + b;
    return false;
}


/**
 * @brief Returns true if a * b would overflow size_t.
 */
static bool size_mul_would_overflow(size_t a, size_t b, size_t *out)
{
    if (!out)
    {
        return true;
    }

    if (a != 0 && b > SIZE_MAX / a)
    {
        return true;
    }

    *out = a * b;
    return false;
}


/**
 * @brief Returns the number of bytes required to represent value in big-endian.
 */
static size_t rlp_be_bytes_required(size_t value)
{
    size_t count = 0;

    do
    {
        count++;
        value >>= 8;
    } while (value != 0);

    return count;
}


/**
 * @brief Returns the number of bytes needed to encode an RLP length prefix.
 */
static size_t rlp_length_prefix_size(size_t length)
{
    if (length <= RLP_SHORT_PAYLOAD_MAX)
    {
        return 1;
    }

    return 1 + rlp_be_bytes_required(length);
}


/**
 * @brief Writes an RLP length prefix for a string or list.
 */
static int rlp_write_length_prefix(
    uint8_t *dest,
    size_t length,
    uint8_t short_base,
    uint8_t long_base,
    size_t *out_written)
{
    if (!dest || !out_written)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    if (length <= RLP_SHORT_PAYLOAD_MAX)
    {
        dest[0] = (uint8_t)(short_base + length);
        *out_written = 1;
        return LANTERN_RLP_OK;
    }

    size_t len_of_len = rlp_be_bytes_required(length);
    if (len_of_len == 0 || len_of_len > sizeof(size_t))
    {
        return LANTERN_RLP_ERR_OVERFLOW;
    }

    dest[0] = (uint8_t)(long_base + len_of_len);
    for (size_t i = 0; i < len_of_len; i++)
    {
        size_t shift = (len_of_len - i - 1) * 8;
        dest[1 + i] = (uint8_t)((length >> shift) & 0xFFu);
    }

    *out_written = 1 + len_of_len;
    return LANTERN_RLP_OK;
}


/**
 * Encode a byte string as RLP.
 *
 * @param buffer Output buffer to receive the encoded item (reset on entry).
 * @param data   Byte string to encode (may be NULL if length == 0).
 * @param length Number of bytes in data.
 *
 * On success, `buffer->data` is allocated and owned by the caller and must be freed with
 * `lantern_rlp_buffer_reset()`.
 *
 * @return 0 on success.
 * @return LANTERN_RLP_ERR_INVALID_PARAM on invalid input.
 * @return LANTERN_RLP_ERR_OUT_OF_MEMORY if allocation fails.
 * @return LANTERN_RLP_ERR_OVERFLOW if the encoded size would overflow size_t.
 *
 * @note Thread safety: Caller must ensure exclusive access to buffer.
 */
int lantern_rlp_encode_bytes(struct lantern_rlp_buffer *buffer, const uint8_t *data, size_t length)
{
    int result = LANTERN_RLP_OK;
    uint8_t *encoded = NULL;
    size_t total_length = 0;
    size_t offset = 0;

    if (!buffer || (length > 0 && !data))
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    lantern_rlp_buffer_reset(buffer);

    if (length == 1 && data[0] <= RLP_PREFIX_SINGLE_BYTE_MAX)
    {
        encoded = malloc(1);
        if (!encoded)
        {
            return LANTERN_RLP_ERR_OUT_OF_MEMORY;
        }

        encoded[0] = data[0];
        buffer->data = encoded;
        buffer->length = 1;
        return LANTERN_RLP_OK;
    }

    if (size_add_would_overflow(rlp_length_prefix_size(length), length, &total_length))
    {
        return LANTERN_RLP_ERR_OVERFLOW;
    }

    encoded = malloc(total_length);
    if (!encoded)
    {
        return LANTERN_RLP_ERR_OUT_OF_MEMORY;
    }

    size_t prefix_written = 0;
    result = rlp_write_length_prefix(
        encoded,
        length,
        RLP_PREFIX_SHORT_STRING_BASE,
        RLP_PREFIX_LONG_STRING_BASE,
        &prefix_written
    );
    if (result != LANTERN_RLP_OK)
    {
        goto cleanup;
    }

    offset += prefix_written;
    if (length > 0)
    {
        memcpy(encoded + offset, data, length);
        offset += length;
    }

    buffer->data = encoded;
    buffer->length = offset;
    encoded = NULL;

cleanup:
    free(encoded);
    if (result != LANTERN_RLP_OK)
    {
        lantern_rlp_buffer_reset(buffer);
    }
    return result;
}


/**
 * Encode a uint64 value as an RLP byte string (big-endian, minimal length).
 *
 * @param buffer Output buffer to receive the encoded item (reset on entry).
 * @param value  Value to encode.
 *
 * On success, `buffer->data` is allocated and owned by the caller and must be freed with
 * `lantern_rlp_buffer_reset()`.
 *
 * @return 0 on success.
 * @return LANTERN_RLP_ERR_INVALID_PARAM if buffer is NULL.
 * @return LANTERN_RLP_ERR_OUT_OF_MEMORY if allocation fails.
 * @return LANTERN_RLP_ERR_OVERFLOW if the encoded size would overflow size_t.
 *
 * @note Thread safety: Caller must ensure exclusive access to buffer.
 */
int lantern_rlp_encode_uint64(struct lantern_rlp_buffer *buffer, uint64_t value)
{
    if (!buffer)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    if (value == 0)
    {
        return lantern_rlp_encode_bytes(buffer, NULL, 0);
    }

    uint8_t bytes[sizeof(uint64_t)];
    for (size_t i = 0; i < sizeof(bytes); i++)
    {
        bytes[sizeof(bytes) - 1 - i] = (uint8_t)(value & 0xFFu);
        value >>= 8;
    }

    size_t first_non_zero = 0;
    while (first_non_zero < sizeof(bytes) && bytes[first_non_zero] == 0)
    {
        first_non_zero++;
    }

    return lantern_rlp_encode_bytes(buffer, bytes + first_non_zero, sizeof(bytes) - first_non_zero);
}


/**
 * Encode a list of already-RLP-encoded items into an RLP list.
 *
 * @param buffer     Output buffer to receive the encoded list (reset on entry).
 * @param items      Array of item buffers, each containing a complete RLP item.
 * @param item_count Number of items in items.
 *
 * On success, `buffer->data` is allocated and owned by the caller and must be freed with
 * `lantern_rlp_buffer_reset()`.
 *
 * @return 0 on success.
 * @return LANTERN_RLP_ERR_INVALID_PARAM on invalid input.
 * @return LANTERN_RLP_ERR_OUT_OF_MEMORY if allocation fails.
 * @return LANTERN_RLP_ERR_OVERFLOW if size calculations overflow.
 *
 * @note Thread safety: Caller must ensure exclusive access to buffer.
 */
int lantern_rlp_encode_list(
    struct lantern_rlp_buffer *buffer,
    const struct lantern_rlp_buffer *items,
    size_t item_count)
{
    int result = LANTERN_RLP_OK;

    if (!buffer)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    lantern_rlp_buffer_reset(buffer);

    if (!items && item_count > 0)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    size_t payload_length = 0;
    for (size_t i = 0; i < item_count; i++)
    {
        if (!items[i].data || items[i].length == 0)
        {
            return LANTERN_RLP_ERR_INVALID_PARAM;
        }
        if (size_add_would_overflow(payload_length, items[i].length, &payload_length))
        {
            return LANTERN_RLP_ERR_OVERFLOW;
        }
    }

    size_t total_length = 0;
    if (size_add_would_overflow(
            rlp_length_prefix_size(payload_length),
            payload_length,
            &total_length))
    {
        return LANTERN_RLP_ERR_OVERFLOW;
    }

    uint8_t *encoded = malloc(total_length);
    if (!encoded)
    {
        return LANTERN_RLP_ERR_OUT_OF_MEMORY;
    }

    size_t offset = 0;
    size_t header_written = 0;
    result = rlp_write_length_prefix(
        encoded,
        payload_length,
        RLP_PREFIX_SHORT_LIST_BASE,
        RLP_PREFIX_LONG_LIST_BASE,
        &header_written
    );
    if (result != LANTERN_RLP_OK)
    {
        free(encoded);
        return result;
    }
    offset += header_written;

    for (size_t i = 0; i < item_count; i++)
    {
        memcpy(encoded + offset, items[i].data, items[i].length);
        offset += items[i].length;
    }

    buffer->data = encoded;
    buffer->length = offset;
    return LANTERN_RLP_OK;
}


/**
 * @brief Returns true if cursor can read size bytes from offset.
 */
static bool rlp_cursor_can_read(const struct lantern_rlp_cursor *cursor, size_t offset, size_t size)
{
    if (!cursor)
    {
        return false;
    }

    return (offset <= cursor->length) && (size <= cursor->length - offset);
}


/**
 * @brief Read an RLP length (big-endian) and advance the cursor.
 */
static int rlp_cursor_read_length(
    struct lantern_rlp_cursor *cursor,
    size_t len_of_len,
    size_t *out_length)
{
    if (!cursor || !out_length)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    if (len_of_len == 0 || len_of_len > sizeof(size_t))
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    if (!rlp_cursor_can_read(cursor, cursor->offset, len_of_len))
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    if (cursor->data[cursor->offset] == 0)
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    size_t value = 0;
    for (size_t i = 0; i < len_of_len; i++)
    {
        uint8_t byte = cursor->data[cursor->offset + i];
        if (value > (SIZE_MAX >> 8))
        {
            return LANTERN_RLP_ERR_OVERFLOW;
        }
        value = (value << 8) | (size_t)byte;
    }

    cursor->offset += len_of_len;
    *out_length = value;
    return LANTERN_RLP_OK;
}


/**
 * @brief Ensures a dynamic RLP view array has at least required capacity.
 */
static int rlp_view_list_ensure_capacity(
    struct lantern_rlp_view **items,
    size_t *capacity,
    size_t required)
{
    if (!items || !capacity)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    if (*capacity >= required)
    {
        return LANTERN_RLP_OK;
    }

    size_t new_capacity = *capacity;
    if (new_capacity == 0)
    {
        new_capacity = RLP_INITIAL_LIST_CAPACITY;
    }

    while (new_capacity < required)
    {
        size_t grown = new_capacity + (new_capacity / 2);
        if (grown <= new_capacity)
        {
            return LANTERN_RLP_ERR_OVERFLOW;
        }
        new_capacity = grown;
    }

    size_t bytes = 0;
    if (size_mul_would_overflow(new_capacity, sizeof(**items), &bytes))
    {
        return LANTERN_RLP_ERR_OVERFLOW;
    }

    struct lantern_rlp_view *resized = realloc(*items, bytes);
    if (!resized)
    {
        return LANTERN_RLP_ERR_OUT_OF_MEMORY;
    }

    for (size_t i = *capacity; i < new_capacity; i++)
    {
        rlp_view_zero(&resized[i]);
    }

    *items = resized;
    *capacity = new_capacity;
    return LANTERN_RLP_OK;
}


/**
 * @brief Decode a single-byte RLP bytes item.
 */
static int decode_single_byte_item(struct lantern_rlp_cursor *cursor, struct lantern_rlp_view *view)
{
    view->kind = LANTERN_RLP_KIND_BYTES;
    view->data = &cursor->data[cursor->offset - 1];
    view->length = 1;
    return LANTERN_RLP_OK;
}


/**
 * @brief Decode a short-string RLP bytes item.
 */
static int decode_short_string_item(
    struct lantern_rlp_cursor *cursor,
    struct lantern_rlp_view *view,
    uint8_t prefix)
{
    size_t str_len = (size_t)prefix - (size_t)RLP_PREFIX_SHORT_STRING_BASE;
    if (!rlp_cursor_can_read(cursor, cursor->offset, str_len))
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    if (str_len == 1 && cursor->data[cursor->offset] <= RLP_PREFIX_SINGLE_BYTE_MAX)
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    view->kind = LANTERN_RLP_KIND_BYTES;
    view->data = cursor->data + cursor->offset;
    view->length = str_len;
    cursor->offset += str_len;
    return LANTERN_RLP_OK;
}


/**
 * @brief Decode a long-string RLP bytes item.
 */
static int decode_long_string_item(
    struct lantern_rlp_cursor *cursor,
    struct lantern_rlp_view *view,
    uint8_t prefix)
{
    size_t len_of_len = (size_t)prefix - (size_t)RLP_PREFIX_LONG_STRING_BASE;
    size_t str_len = 0;
    int result = rlp_cursor_read_length(cursor, len_of_len, &str_len);
    if (result != LANTERN_RLP_OK)
    {
        return result;
    }

    if (str_len <= RLP_SHORT_PAYLOAD_MAX)
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    if (!rlp_cursor_can_read(cursor, cursor->offset, str_len))
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    view->kind = LANTERN_RLP_KIND_BYTES;
    view->data = cursor->data + cursor->offset;
    view->length = str_len;
    cursor->offset += str_len;
    return LANTERN_RLP_OK;
}


/**
 * @brief Decode a short-list RLP item.
 */
static int decode_short_list_item(
    struct lantern_rlp_cursor *cursor,
    struct lantern_rlp_view *view,
    uint8_t prefix,
    size_t depth)
{
    size_t payload_length = (size_t)prefix - (size_t)RLP_PREFIX_SHORT_LIST_BASE;
    if (!rlp_cursor_can_read(cursor, cursor->offset, payload_length))
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    const uint8_t *payload_start = cursor->data + cursor->offset;
    int result = decode_list_payload(cursor, payload_length, view, depth);
    if (result != LANTERN_RLP_OK)
    {
        return result;
    }

    view->data = payload_start;
    view->length = payload_length;
    return LANTERN_RLP_OK;
}


/**
 * @brief Decode a long-list RLP item.
 */
static int decode_long_list_item(
    struct lantern_rlp_cursor *cursor,
    struct lantern_rlp_view *view,
    uint8_t prefix,
    size_t depth)
{
    size_t len_of_len = (size_t)prefix - (size_t)RLP_PREFIX_LONG_LIST_BASE;
    size_t payload_length = 0;
    int result = rlp_cursor_read_length(cursor, len_of_len, &payload_length);
    if (result != LANTERN_RLP_OK)
    {
        return result;
    }

    if (payload_length <= RLP_SHORT_PAYLOAD_MAX)
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    if (!rlp_cursor_can_read(cursor, cursor->offset, payload_length))
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    const uint8_t *payload_start = cursor->data + cursor->offset;
    result = decode_list_payload(cursor, payload_length, view, depth);
    if (result != LANTERN_RLP_OK)
    {
        return result;
    }

    view->data = payload_start;
    view->length = payload_length;
    return LANTERN_RLP_OK;
}


/**
 * @brief Decode an RLP item.
 */
static int decode_item(struct lantern_rlp_cursor *cursor, struct lantern_rlp_view *view, size_t depth)
{
    if (!cursor || !view)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    if (depth > LANTERN_RLP_MAX_NESTING_DEPTH)
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    rlp_view_zero(view);

    if (cursor->offset >= cursor->length)
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }

    uint8_t prefix = cursor->data[cursor->offset];
    cursor->offset++;

    if (prefix <= RLP_PREFIX_SINGLE_BYTE_MAX)
    {
        return decode_single_byte_item(cursor, view);
    }

    if (prefix <= RLP_PREFIX_SHORT_STRING_MAX)
    {
        return decode_short_string_item(cursor, view, prefix);
    }

    if (prefix <= RLP_PREFIX_LONG_STRING_MAX)
    {
        return decode_long_string_item(cursor, view, prefix);
    }

    if (prefix <= RLP_PREFIX_SHORT_LIST_MAX)
    {
        size_t next_depth = depth + 1;
        if (next_depth > LANTERN_RLP_MAX_NESTING_DEPTH)
        {
            return LANTERN_RLP_ERR_INVALID_ENCODING;
        }
        return decode_short_list_item(cursor, view, prefix, next_depth);
    }

    size_t next_depth = depth + 1;
    if (next_depth > LANTERN_RLP_MAX_NESTING_DEPTH)
    {
        return LANTERN_RLP_ERR_INVALID_ENCODING;
    }
    return decode_long_list_item(cursor, view, prefix, next_depth);
}


/**
 * @brief Decode the payload of an RLP list.
 */
static int decode_list_payload(
    struct lantern_rlp_cursor *cursor,
    size_t payload_length,
    struct lantern_rlp_view *view,
    size_t depth)
{
    if (!cursor || !view)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    struct lantern_rlp_cursor nested = {
        .data = cursor->data + cursor->offset,
        .length = payload_length,
        .offset = 0,
    };

    struct lantern_rlp_view *items = NULL;
    size_t capacity = 0;
    size_t count = 0;

    int result = LANTERN_RLP_OK;

    while (nested.offset < nested.length)
    {
        result = rlp_view_list_ensure_capacity(&items, &capacity, count + 1);
        if (result != LANTERN_RLP_OK)
        {
            goto cleanup;
        }

        result = decode_item(&nested, &items[count], depth);
        if (result != LANTERN_RLP_OK)
        {
            goto cleanup;
        }

        count++;
    }

    if (nested.offset != nested.length)
    {
        result = LANTERN_RLP_ERR_INVALID_ENCODING;
        goto cleanup;
    }

    cursor->offset += payload_length;
    view->kind = LANTERN_RLP_KIND_LIST;
    view->items = items;
    view->item_count = count;
    items = NULL;

cleanup:
    if (items)
    {
        for (size_t i = 0; i < count; i++)
        {
            lantern_rlp_view_reset(&items[i]);
        }
    }
    free(items);
    return result;
}


/**
 * Decode an RLP item.
 *
 * @param encoded        RLP-encoded data buffer.
 * @param encoded_length Length of encoded in bytes.
 * @param out_view       Output view (reset on entry).
 *
 * On success, `out_view` may contain dynamically allocated children for list items and must be
 * freed with `lantern_rlp_view_reset()`.
 *
 * @return 0 on success.
 * @return LANTERN_RLP_ERR_INVALID_PARAM on invalid input.
 * @return LANTERN_RLP_ERR_INVALID_ENCODING if the RLP encoding is malformed or non-canonical.
 * @return LANTERN_RLP_ERR_TRAILING_DATA if extra bytes remain after the item.
 *
 * @note Thread safety: Caller must ensure exclusive access to out_view.
 */
int lantern_rlp_decode(
    const uint8_t *encoded,
    size_t encoded_length,
    struct lantern_rlp_view *out_view)
{
    if (!encoded || encoded_length == 0 || !out_view)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    rlp_view_zero(out_view);

    struct lantern_rlp_cursor cursor = {
        .data = encoded,
        .length = encoded_length,
        .offset = 0,
    };

    int result = decode_item(&cursor, out_view, 0);
    if (result != LANTERN_RLP_OK)
    {
        lantern_rlp_view_reset(out_view);
        return result;
    }

    if (cursor.offset != cursor.length)
    {
        lantern_rlp_view_reset(out_view);
        return LANTERN_RLP_ERR_TRAILING_DATA;
    }

    return LANTERN_RLP_OK;
}


/**
 * Convert an RLP bytes item into a uint64 (big-endian).
 *
 * @param view      RLP view to read (must be a bytes item).
 * @param out_value Output decoded value.
 *
 * @return 0 on success.
 * @return LANTERN_RLP_ERR_INVALID_PARAM on invalid input or if the view is not a bytes item.
 *
 * @note Thread safety: Caller must ensure exclusive access to out_value.
 */
int lantern_rlp_view_as_uint64(const struct lantern_rlp_view *view, uint64_t *out_value)
{
    if (!view || !out_value)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    if (view->kind != LANTERN_RLP_KIND_BYTES)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    if (view->length > sizeof(uint64_t))
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    if (view->length > 0 && !view->data)
    {
        return LANTERN_RLP_ERR_INVALID_PARAM;
    }

    uint64_t value = 0;
    for (size_t i = 0; i < view->length; i++)
    {
        value = (value << 8) | (uint64_t)view->data[i];
    }

    *out_value = value;
    return LANTERN_RLP_OK;
}
