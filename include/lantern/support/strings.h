#ifndef LANTERN_SUPPORT_STRINGS_H
#define LANTERN_SUPPORT_STRINGS_H

/**
 * @file
 * Allocate string duplicates, perform bounded string copies, and trim writable
 * strings in place.
 *
 * Allocation functions transfer ownership of successful results to the caller.
 * Copy and trim operations modify caller-owned buffers. All operations are
 * thread-safe when concurrent calls use separate writable storage.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

/** Distinguishes a complete copy from truncation and invalid input. */
enum lantern_string_copy_result
{
    LANTERN_STRING_COPY_OK = 0,
    LANTERN_STRING_COPY_TRUNCATED = 1,
    LANTERN_STRING_COPY_ERR_INVALID = -1,
};

/**
 * Allocate a duplicate of a null-terminated string.
 *
 * The caller retains ownership of `source` and owns the returned allocation.
 * Release the result with `free`. This function is thread-safe.
 *
 * @param[in] source Null-terminated string to duplicate. Must not be `NULL`.
 * @return An owned null-terminated duplicate on success.
 * @return `NULL` when `source` is `NULL` or allocation fails.
 */
char *lantern_string_duplicate(const char *source);

/**
 * Allocate a terminated copy of an exact source byte count.
 *
 * `source` must provide at least `length` readable bytes. The copied bytes can
 * contain null values. The function adds one null byte after them. The caller
 * retains ownership of `source` and owns the returned allocation. Release the
 * result with `free`. This function is thread-safe.
 *
 * @param[in] source Buffer containing at least `length` readable bytes. Must
 * not be `NULL`.
 * @param[in] length Number of source bytes to copy. Must be less than
 * `SIZE_MAX`.
 * @return An owned buffer containing the copied bytes and a final null byte.
 * @return `NULL` when `source` is `NULL`, `length` equals `SIZE_MAX`, or
 * allocation fails.
 */
char *lantern_string_duplicate_len(const char *source, size_t length);

/**
 * Copy a string into a bounded destination and add a null terminator.
 *
 * A successful call copies at most `dst_len - 1` bytes. The caller owns both
 * buffers. The buffers must not overlap. Concurrent calls must use separate
 * destinations. A null source empties a writable destination. Other invalid
 * input leaves the destination unchanged. The function writes the complete
 * source length to `out_source_len` when that output is requested.
 *
 * @param[out] dst Buffer that receives the terminated string. Must not be
 * `NULL`.
 * @param[in] dst_len Destination capacity in bytes, including the null
 * terminator. Must be greater than zero.
 * @param[in] src Null-terminated source string. Must not be `NULL`.
 * @param[out] out_source_len Optional destination for the complete source
 * length. This value can be `NULL` and remains unchanged after invalid input.
 * @return `LANTERN_STRING_COPY_OK` after copying the complete source.
 * @return `LANTERN_STRING_COPY_TRUNCATED` after copying a truncated source.
 * @return `LANTERN_STRING_COPY_ERR_INVALID` when `dst` or `src` is `NULL`, or
 * `dst_len` is zero.
 */
enum lantern_string_copy_result
lantern_string_copy(char *dst, size_t dst_len, const char *src,
                    size_t *out_source_len);

/**
 * Remove surrounding whitespace from a string in place.
 *
 * The function writes a null terminator after the last retained byte and
 * returns a pointer into `value` at the first retained byte. The caller retains
 * ownership of the original `value` pointer and must use it for deallocation.
 * Leading bytes before the returned pointer remain unchanged. Concurrent calls
 * must use separate writable strings.
 *
 * @param[in,out] value Null-terminated writable string. This value can be
 * `NULL`.
 * @return A borrowed pointer to the first retained byte, or the terminating
 * null byte when the string contains only whitespace.
 * @return `NULL` when `value` is `NULL`.
 */
char *lantern_trim_whitespace(char *value);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_SUPPORT_STRINGS_H */
