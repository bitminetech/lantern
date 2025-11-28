#ifndef LANTERN_ENCODING_SNAPPY_H
#define LANTERN_ENCODING_SNAPPY_H

#include <stddef.h>
#include <stdint.h>

enum lantern_snappy_error {
    LANTERN_SNAPPY_OK = 0,
    LANTERN_SNAPPY_ERROR_INVALID_INPUT = -1,
    LANTERN_SNAPPY_ERROR_BUFFER_TOO_SMALL = -2,
    LANTERN_SNAPPY_ERROR_UNSUPPORTED = -3,
};

int lantern_snappy_max_compressed_size(size_t input_len, size_t *max_size);

/* Max compressed size for raw (unframed) snappy - no framing overhead. */
int lantern_snappy_max_compressed_size_raw(size_t input_len, size_t *max_size);

int lantern_snappy_compress(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written);

/* Raw (unframed) Snappy compression. Useful when the peer expects a plain
 * Snappy block instead of the Snappy framed stream with CRCs. */
int lantern_snappy_compress_raw(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written);

int lantern_snappy_uncompressed_length(
    const uint8_t *input,
    size_t input_len,
    size_t *result);

int lantern_snappy_decompress(
    const uint8_t *input,
    size_t input_len,
    uint8_t *output,
    size_t output_len,
    size_t *written);

#endif /* LANTERN_ENCODING_SNAPPY_H */
