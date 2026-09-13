#ifndef LANTERN_SUPPORT_STRING_LIST_H
#define LANTERN_SUPPORT_STRING_LIST_H

/**
 * @file
 * Manage an initialized list that owns duplicated null-terminated strings.
 *
 * The interface supports append, unique append, lookup, removal, independent
 * copying, and reset. The module owns its private storage, while callers own
 * the list handle. Mutations invalidate borrowed item pointers, and shared
 * access requires external synchronization when any thread can mutate a list.
 */

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

struct lantern_string_list_storage;

/**
 * Own duplicated null-terminated strings through private storage.
 *
 * The caller owns the handle. The module owns its storage and each contained
 * string. Initialize the handle before use and reset it before its lifetime
 * ends. Do not copy the handle by assignment. Use `lantern_string_list_copy`
 * to create an independent list. Synchronize all shared access when any thread
 * can mutate the list.
 */
struct lantern_string_list
{
    /** The module owns this private storage. Callers must not access it. */
    struct lantern_string_list_storage *storage;
};

/** Distinguishes success, absence, invalid input, unsafe growth, and allocation
 * failure. */
enum lantern_string_list_result
{
    LANTERN_STRING_LIST_OK = 0,
    LANTERN_STRING_LIST_NOT_FOUND = 1,
    LANTERN_STRING_LIST_ERR_INVALID = -1,
    LANTERN_STRING_LIST_ERR_RANGE = -2,
    LANTERN_STRING_LIST_ERR_ALLOC = -3,
};

/**
 * Initialize an uninitialized list as empty.
 *
 * This function allocates no storage. Calling it for an initialized nonempty
 * list leaks that list's storage. No synchronization is necessary before the
 * handle becomes shared.
 *
 * @param[out] list Uninitialized handle to initialize. A `NULL` value has no
 * effect.
 */
void lantern_string_list_init(struct lantern_string_list *list);

/**
 * Release all strings and restore an initialized list as empty.
 *
 * This function invalidates every item borrowed from `list`. It has no effect
 * for a `NULL` handle or an empty list. The caller must synchronize shared
 * access when any thread can access the list.
 *
 * @param[in,out] list Initialized handle to reset. This value can be `NULL`.
 */
void lantern_string_list_reset(struct lantern_string_list *list);

/**
 * Append an owned copy of `value` to `list`.
 *
 * The caller retains ownership of `value`. The function leaves `list`
 * unchanged if it fails. A successful append invalidates items previously
 * borrowed from the list. The caller must synchronize shared access when any
 * thread can mutate the list.
 *
 * @param[in,out] list Initialized list to modify. Must not be `NULL`.
 * @param[in] value Null-terminated string to copy. Must not be `NULL`.
 * @return `LANTERN_STRING_LIST_OK` after appending the copied string.
 * @return `LANTERN_STRING_LIST_ERR_INVALID` when an argument is `NULL`.
 * @return `LANTERN_STRING_LIST_ERR_RANGE` when the list cannot grow safely.
 * @return `LANTERN_STRING_LIST_ERR_ALLOC` when string or storage allocation
 * fails.
 */
enum lantern_string_list_result
lantern_string_list_append(struct lantern_string_list *list, const char *value);

/**
 * Append an owned copy when `value` is nonempty and absent from `list`.
 *
 * An empty or existing value returns success without changing the list. The
 * caller retains ownership of `value`. A failure leaves `list` unchanged. A
 * successful append invalidates items previously borrowed from the list. The
 * caller must synchronize shared access when any thread can mutate the list.
 *
 * @param[in,out] list Initialized list to query and possibly modify. Must not
 * be `NULL`.
 * @param[in] value Null-terminated string to query and copy. Must not be
 * `NULL`.
 * @return `LANTERN_STRING_LIST_OK` after appending the copied string or when
 * no append is necessary.
 * @return `LANTERN_STRING_LIST_ERR_INVALID` when an argument is `NULL`.
 * @return `LANTERN_STRING_LIST_ERR_RANGE` when the list cannot grow safely.
 * @return `LANTERN_STRING_LIST_ERR_ALLOC` when string or storage allocation
 * fails.
 */
enum lantern_string_list_result
lantern_string_list_append_unique(struct lantern_string_list *list,
                                  const char *value);

/**
 * Report whether `list` contains a string equal to `value`.
 *
 * This function does not modify either argument. Concurrent reads are safe
 * only while no thread can mutate the list.
 *
 * @param[in] list Initialized list to search. This value can be `NULL`.
 * @param[in] value Null-terminated string to find. This value can be `NULL`.
 * @return true when an equal string exists in `list`.
 * @return false when an argument is `NULL` or no equal string exists.
 */
bool lantern_string_list_contains(const struct lantern_string_list *list,
                                  const char *value);

/**
 * Remove and release the first string equal to `value`.
 *
 * A successful removal invalidates items previously borrowed from `list`. A
 * failed search leaves the list unchanged. The caller must synchronize shared
 * access when any thread can access the list.
 *
 * @param[in,out] list Initialized list to modify. This value can be `NULL`.
 * @param[in] value Null-terminated string to remove. This value can be `NULL`.
 * @return `LANTERN_STRING_LIST_OK` after removing the first equal string.
 * @return `LANTERN_STRING_LIST_NOT_FOUND` when no equal string exists.
 * @return `LANTERN_STRING_LIST_ERR_INVALID` when an argument is `NULL`.
 */
enum lantern_string_list_result
lantern_string_list_remove(struct lantern_string_list *list,
                           const char *value);

/**
 * Replace `dst` with an independent copy of `src`.
 *
 * The function duplicates every source string before it changes `dst`. A
 * failure leaves `dst` unchanged. A self-copy returns success without changing
 * either list. A successful copy invalidates items previously borrowed from
 * `dst`. The caller must synchronize shared access when any thread can access
 * either list.
 *
 * @param[in,out] dst Initialized destination list. Must not be `NULL`.
 * @param[in] src Initialized source list. Must not be `NULL`.
 * @return `LANTERN_STRING_LIST_OK` after replacement or a self-copy.
 * @return `LANTERN_STRING_LIST_ERR_INVALID` when an argument is `NULL`.
 * @return `LANTERN_STRING_LIST_ERR_RANGE` when private storage cannot represent
 * the source count.
 * @return `LANTERN_STRING_LIST_ERR_ALLOC` when string or storage allocation
 * fails.
 */
enum lantern_string_list_result
lantern_string_list_copy(struct lantern_string_list *dst,
                         const struct lantern_string_list *src);

/**
 * Return the number of strings stored in `list`.
 *
 * Concurrent reads are safe only while no thread can mutate the list.
 *
 * @param[in] list Initialized list to inspect. This value can be `NULL`.
 * @return The number of stored strings, or zero when `list` is `NULL` or empty.
 */
size_t lantern_string_list_count(const struct lantern_string_list *list);

/**
 * Return the string at a zero-based index.
 *
 * The caller does not own the returned string. The result remains valid until
 * the next list mutation or reset. Concurrent reads are safe only while no
 * thread can mutate the list.
 *
 * @param[in] list Initialized list to inspect. This value can be `NULL`.
 * @param[in] index Zero-based string index.
 * @return A borrowed null-terminated string when `index` is valid.
 * @return `NULL` when `list` is `NULL` or `index` is out of range.
 */
const char *lantern_string_list_get(const struct lantern_string_list *list,
                                    size_t index);

#ifdef __cplusplus
}
#endif

#endif /* LANTERN_SUPPORT_STRING_LIST_H */
