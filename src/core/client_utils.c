/**
 * @file client_utils.c
 * @brief Client utility functions and locking primitives
 *
 * Implements utility functions used across client modules including:
 * - State and pending lock management
 * - Time utilities
 * - Formatting helpers
 * - String operations
 *
 * @note Thread safety: Lock functions are thread-safe.
 */

#include "client_internal.h"

#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/time.h>
#endif

#if defined(__APPLE__)
#include <mach/mach_time.h>
#endif

#include <libp2p/errors.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/support/log.h"
#include "lantern/support/secure_mem.h"
#include "lantern/support/strings.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

#if !defined(_WIN32)
static const uint64_t CLIENT_UTILS_MILLIS_PER_SECOND = 1000ULL;
static const uint64_t CLIENT_UTILS_MICROS_PER_MILLI = 1000ULL;
static const uint64_t CLIENT_UTILS_NANOS_PER_MILLI = 1000000ULL;
static const uint64_t CLIENT_UTILS_NANOS_PER_SECOND = 1000000000ULL;
#endif

static const size_t CLIENT_UTILS_ROOT_HEX_MIN_LEN = 4;
static const size_t CLIENT_UTILS_NODE_KEY_SIZE = 32;


/* ============================================================================
 * Time Utilities
 * ============================================================================ */

/**
 * Get monotonic time in milliseconds.
 *
 * @return Monotonic milliseconds since some unspecified epoch
 *
 * @note Thread safety: This function is thread-safe
 */
uint64_t monotonic_millis(void)
{
#if defined(_WIN32)
    return (uint64_t)GetTickCount64();
#elif defined(CLOCK_MONOTONIC)
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
    {
        return 0;
    }
    if (ts.tv_sec < 0 || ts.tv_nsec < 0 || (uint64_t)ts.tv_nsec >= CLIENT_UTILS_NANOS_PER_SECOND)
    {
        return 0;
    }

    uint64_t millis = (uint64_t)ts.tv_sec;
    if (millis > UINT64_MAX / CLIENT_UTILS_MILLIS_PER_SECOND)
    {
        return 0;
    }
    millis *= CLIENT_UTILS_MILLIS_PER_SECOND;

    uint64_t nanos_part = (uint64_t)ts.tv_nsec / CLIENT_UTILS_NANOS_PER_MILLI;
    if (millis > UINT64_MAX - nanos_part)
    {
        return 0;
    }
    return millis + nanos_part;
#elif defined(__APPLE__)
    mach_timebase_info_data_t timebase = {0};
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0 || timebase.numer == 0)
    {
        return 0;
    }

    uint64_t ticks = mach_absolute_time();
    if (ticks > UINT64_MAX / timebase.numer)
    {
        return 0;
    }

    uint64_t nanos = (ticks * timebase.numer) / timebase.denom;
    return nanos / CLIENT_UTILS_NANOS_PER_MILLI;
#else
    struct timeval tv;
    if (gettimeofday(&tv, NULL) != 0)
    {
        return 0;
    }
    if (tv.tv_sec < 0 || tv.tv_usec < 0)
    {
        return 0;
    }

    uint64_t millis = (uint64_t)tv.tv_sec;
    if (millis > UINT64_MAX / CLIENT_UTILS_MILLIS_PER_SECOND)
    {
        return 0;
    }
    millis *= CLIENT_UTILS_MILLIS_PER_SECOND;

    uint64_t usec_part = (uint64_t)tv.tv_usec / CLIENT_UTILS_MICROS_PER_MILLI;
    if (millis > UINT64_MAX - usec_part)
    {
        return 0;
    }
    return millis + usec_part;
#endif
}


/**
 * Get current wall clock time in seconds.
 *
 * @return Current time as Unix timestamp
 *
 * @note Thread safety: This function is thread-safe
 */
uint64_t validator_wall_time_now_seconds(void)
{
#if defined(_WIN32)
    static const uint64_t WINDOWS_UNIX_EPOCH_DIFF_100NS = 116444736000000000ULL;
    static const uint64_t WINDOWS_100NS_PER_SECOND = 10000000ULL;

    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER uli;
    uli.LowPart = ft.dwLowDateTime;
    uli.HighPart = ft.dwHighDateTime;
    uint64_t time_100ns = (uint64_t)uli.QuadPart;
    if (time_100ns < WINDOWS_UNIX_EPOCH_DIFF_100NS)
    {
        return 0;
    }

    // FILETIME is 100-nanosecond intervals since Jan 1, 1601.
    // Convert to Unix epoch (seconds since Jan 1, 1970).
    uint64_t unix_100ns = time_100ns - WINDOWS_UNIX_EPOCH_DIFF_100NS;
    return unix_100ns / WINDOWS_100NS_PER_SECOND;
#else
    struct timeval tv;
    if (gettimeofday(&tv, NULL) != 0)
    {
        return 0;
    }
    if (tv.tv_sec < 0)
    {
        return 0;
    }
    return (uint64_t)tv.tv_sec;
#endif
}


/**
 * Sleep for specified milliseconds.
 *
 * @param ms  Milliseconds to sleep
 *
 * @note Thread safety: This function is thread-safe
 */
void validator_sleep_ms(uint32_t ms)
{
#if defined(_WIN32)
    Sleep(ms);
#else
    struct timespec ts;
    ts.tv_sec = (time_t)(ms / (uint32_t)CLIENT_UTILS_MILLIS_PER_SECOND);
    ts.tv_nsec = (long)((ms % (uint32_t)CLIENT_UTILS_MILLIS_PER_SECOND)
        * (uint32_t)CLIENT_UTILS_NANOS_PER_MILLI);
    while (nanosleep(&ts, &ts) != 0)
    {
        if (errno != EINTR)
        {
            break;
        }
    }
#endif
}


/* ============================================================================
 * State Locking
 * ============================================================================ */

/**
 * @brief Unlock a mutex and log on failure.
 */
static void unlock_mutex_with_log(
    pthread_mutex_t *mutex,
    const char *validator_id,
    const char *name)
{
    if (!mutex || !name)
    {
        return;
    }

    int unlock_rc = pthread_mutex_unlock(mutex);
    if (unlock_rc != 0)
    {
        lantern_log_warn(
            "client",
            &(const struct lantern_log_metadata){.validator = validator_id},
            "failed to unlock %s: %d",
            name,
            unlock_rc);
    }
}


/**
 * Acquire the client state lock.
 *
 * @param client  Client instance
 * @return true if lock was acquired, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_lock_state(struct lantern_client *client)
{
    if (!client || !client->state_lock_initialized)
    {
        return false;
    }
    return pthread_mutex_lock(&client->state_lock) == 0;
}


/**
 * Release the client state lock.
 *
 * @param client  Client instance
 * @param locked  Value returned from lantern_client_lock_state()
 *
 * @note Thread safety: This function is thread-safe
 */
void lantern_client_unlock_state(struct lantern_client *client, bool locked)
{
    if (locked && client && client->state_lock_initialized)
    {
        unlock_mutex_with_log(&client->state_lock, client->node_id, "state_lock");
    }
}


/**
 * Acquire the client pending blocks lock.
 *
 * @param client  Client instance
 * @return true if lock was acquired, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_lock_pending(struct lantern_client *client)
{
    if (!client || !client->pending_lock_initialized)
    {
        return false;
    }
    return pthread_mutex_lock(&client->pending_lock) == 0;
}


/**
 * Release the client pending blocks lock.
 *
 * @param client  Client instance
 * @param locked  Value returned from lantern_client_lock_pending()
 *
 * @note Thread safety: This function is thread-safe
 */
void lantern_client_unlock_pending(struct lantern_client *client, bool locked)
{
    if (locked && client && client->pending_lock_initialized)
    {
        unlock_mutex_with_log(&client->pending_lock, client->node_id, "pending_lock");
    }
}


/* ============================================================================
 * Formatting Utilities
 * ============================================================================ */

/**
 * Format a root hash as hex string.
 *
 * Produces output like "0x1234...abcd" with prefix.
 *
 * @param root     Root to format (may be NULL)
 * @param out      Output buffer
 * @param out_len  Size of output buffer
 *
 * @note Thread safety: This function is thread-safe
 */
void format_root_hex(const LanternRoot *root, char *out, size_t out_len)
{
    if (!out || out_len == 0)
    {
        return;
    }
    out[0] = '\0';

    if (!root || out_len < CLIENT_UTILS_ROOT_HEX_MIN_LEN)
    {
        return;
    }

    // Check if root is all zeros
    bool is_all_zero = true;
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i)
    {
        if (root->bytes[i] != 0)
        {
            is_all_zero = false;
            break;
        }
    }
    if (is_all_zero)
    {
        strncpy(out, "0x0", out_len - 1);
        out[out_len - 1] = '\0';
        return;
    }

    // Format as 0x + hex
    out[0] = '0';
    out[1] = 'x';
    size_t pos = 2;

    static const char hex_chars[] = "0123456789abcdef";
    for (size_t i = 0; i < LANTERN_ROOT_SIZE && pos + 2 < out_len; ++i)
    {
        out[pos++] = hex_chars[(root->bytes[i] >> 4) & 0x0F];
        out[pos++] = hex_chars[root->bytes[i] & 0x0F];
    }
    out[pos] = '\0';
}


/* ============================================================================
 * Root/Pubkey Utilities
 * ============================================================================ */

/**
 * Check if a root is all zeros.
 *
 * @param root  Root to check
 * @return true if root is NULL or all zero bytes
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_root_is_zero(const LanternRoot *root)
{
    if (!root)
    {
        return true;
    }
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i)
    {
        if (root->bytes[i] != 0)
        {
            return false;
        }
    }
    return true;
}


/**
 * Check if validator pubkey bytes are all zeros.
 *
 * @param pubkey  Pubkey bytes to check (LANTERN_VALIDATOR_PUBKEY_SIZE bytes)
 * @return true if pubkey is NULL or all zero bytes
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_validator_pubkey_is_zero(const uint8_t *pubkey)
{
    if (!pubkey)
    {
        return true;
    }
    for (size_t i = 0; i < LANTERN_VALIDATOR_PUBKEY_SIZE; ++i)
    {
        if (pubkey[i] != 0)
        {
            return false;
        }
    }
    return true;
}


/* ============================================================================
 * Vote Utilities
 * ============================================================================ */

/**
 * Set vote rejection reason with printf-style formatting.
 *
 * @param info  Rejection info structure to populate
 * @param fmt   Format string
 * @param ...   Format arguments
 *
 * @note Thread safety: This function is thread-safe
 */
void lantern_vote_rejection_set(struct lantern_vote_rejection_info *info, const char *fmt, ...)
{
    if (!info)
    {
        return;
    }
    info->has_reason = false;
    info->message[0] = '\0';

    if (!fmt)
    {
        return;
    }

    va_list args;
    va_start(args, fmt);
    int written = vsnprintf(info->message, sizeof(info->message), fmt, args);
    va_end(args);

    if (written < 0)
    {
        return;
    }

    if ((size_t)written >= sizeof(info->message))
    {
        info->message[sizeof(info->message) - 1] = '\0';
    }

    if (written > 0)
    {
        info->has_reason = true;
    }
}


/* ============================================================================
 * Slot Utilities
 * ============================================================================ */

/**
 * Get current slot from fork choice.
 *
 * @param client    Client instance
 * @param out_slot  Output slot
 * @return true on success, false on error
 *
 * @note Thread safety: This function is thread-safe
 */
bool lantern_client_current_slot(const struct lantern_client *client, uint64_t *out_slot)
{
    if (!client || !out_slot || !client->has_fork_choice)
    {
        return false;
    }
    const LanternForkChoice *store = &client->fork_choice;
    if (store->seconds_per_slot == 0)
    {
        return false;
    }
    uint64_t now = validator_wall_time_now_seconds();
    if (now == 0)
    {
        return false;
    }
    if (now < store->config.genesis_time)
    {
        *out_slot = 0;
        return true;
    }
    uint64_t elapsed = now - store->config.genesis_time;
    *out_slot = elapsed / store->seconds_per_slot;
    return true;
}


/**
 * Check if a block root is known in fork choice.
 *
 * @param client    Client instance
 * @param root      Root to check
 * @param out_slot  Output slot (may be NULL)
 * @return true if known, false otherwise
 *
 * @note Thread safety: Caller must hold state_lock
 */
bool lantern_client_block_known_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    uint64_t *out_slot)
{
    if (!client || !root || !client->has_fork_choice)
    {
        return false;
    }
    uint64_t slot = 0;
    if (lantern_fork_choice_block_info(&client->fork_choice, root, &slot, NULL, NULL) != 0)
    {
        return false;
    }
    if (out_slot)
    {
        *out_slot = slot;
    }
    return true;
}


/* ============================================================================
 * String Utilities
 * ============================================================================ */

/**
 * Set an owned string field, freeing previous value.
 *
 * @param dest   Pointer to destination string pointer
 * @param value  Value to copy
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if dest or value is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 *
 * @note Thread safety: This function is thread-safe
 */
int set_owned_string(char **dest, const char *value)
{
    if (!dest || !value)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }
    char *copy = lantern_string_duplicate(value);
    if (!copy)
    {
        return LANTERN_CLIENT_ERR_ALLOC;
    }
    free(*dest);
    *dest = copy;
    return LANTERN_CLIENT_OK;
}


/**
 * Read file contents and trim whitespace.
 *
 * @param path      File path
 * @param out_text  Output buffer (caller owns)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if path or out_text is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_CONFIG if the file cannot be read or trimmed
 *
 * @note Thread safety: This function is thread-safe
 */
int read_trimmed_file(const char *path, char **out_text)
{
    if (!path || !out_text)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    int result = LANTERN_CLIENT_OK;
    FILE *fp = NULL;
    char *buffer = NULL;

    *out_text = NULL;

    fp = fopen(path, "rb");
    if (!fp)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){0},
            "unable to open %s for reading",
            path);
        return LANTERN_CLIENT_ERR_CONFIG;
    }

    if (fseek(fp, 0, SEEK_END) != 0)
    {
        result = LANTERN_CLIENT_ERR_CONFIG;
        goto cleanup;
    }
    long file_size = ftell(fp);
    if (file_size < 0 || (uint64_t)file_size > SIZE_MAX - 1)
    {
        result = LANTERN_CLIENT_ERR_CONFIG;
        goto cleanup;
    }
    if (fseek(fp, 0, SEEK_SET) != 0)
    {
        result = LANTERN_CLIENT_ERR_CONFIG;
        goto cleanup;
    }

    size_t alloc_size = (size_t)file_size + 1;
    buffer = malloc(alloc_size);
    if (!buffer)
    {
        result = LANTERN_CLIENT_ERR_ALLOC;
        goto cleanup;
    }

    size_t read_len = fread(buffer, 1, (size_t)file_size, fp);
    if (read_len != (size_t)file_size)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){0},
            "unable to read %s: read %zu of %ld bytes",
            path,
            read_len,
            file_size);
        result = LANTERN_CLIENT_ERR_CONFIG;
        goto cleanup;
    }
    buffer[read_len] = '\0';

    char *trimmed = lantern_trim_whitespace(buffer);
    if (!trimmed)
    {
        result = LANTERN_CLIENT_ERR_CONFIG;
        goto cleanup;
    }
    size_t trimmed_len = strlen(trimmed);
    memmove(buffer, trimmed, trimmed_len + 1);
    *out_text = buffer;
    buffer = NULL;
    result = LANTERN_CLIENT_OK;

cleanup:
    if (fp)
    {
        if (fclose(fp) != 0)
        {
            lantern_log_warn(
                "client",
                &(const struct lantern_log_metadata){0},
                "failed to close %s: errno=%d",
                path,
                errno);
        }
    }
    free(buffer);
    return result;
}


/**
 * Load node key bytes from options.
 *
 * Reads from either node_key_hex or node_key_path.
 *
 * @param options  Client options
 * @param out_key  Output buffer (32 bytes)
 * @return LANTERN_CLIENT_OK on success
 * @return LANTERN_CLIENT_ERR_INVALID_PARAM if options or out_key is NULL
 * @return LANTERN_CLIENT_ERR_ALLOC if allocation fails
 * @return LANTERN_CLIENT_ERR_CONFIG if the key is missing or invalid
 *
 * @note Thread safety: This function is thread-safe
 */
int load_node_key_bytes(const struct lantern_client_options *options, uint8_t out_key[32])
{
    if (!options || !out_key)
    {
        return LANTERN_CLIENT_ERR_INVALID_PARAM;
    }

    lantern_secure_zero(out_key, CLIENT_UTILS_NODE_KEY_SIZE);

    int result = LANTERN_CLIENT_OK;
    char *owned = NULL;

    if (options->node_key_hex)
    {
        owned = lantern_string_duplicate(options->node_key_hex);
        if (!owned)
        {
            return LANTERN_CLIENT_ERR_ALLOC;
        }
    }
    else if (options->node_key_path)
    {
        int rc = read_trimmed_file(options->node_key_path, &owned);
        if (rc != LANTERN_CLIENT_OK)
        {
            return rc;
        }
    }
    else
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "--node-key or --node-key-path is required");
        return LANTERN_CLIENT_ERR_CONFIG;
    }

    char *trimmed = lantern_trim_whitespace(owned);
    if (!trimmed)
    {
        result = LANTERN_CLIENT_ERR_CONFIG;
        goto cleanup;
    }

    if (lantern_hex_decode(trimmed, out_key, CLIENT_UTILS_NODE_KEY_SIZE) != 0)
    {
        lantern_log_error(
            "client",
            &(const struct lantern_log_metadata){.validator = options->node_id},
            "invalid node key (expected 32-byte hex string)");
        result = LANTERN_CLIENT_ERR_CONFIG;
    }

cleanup:
    if (owned)
    {
        lantern_secure_zero(owned, strlen(owned));
        free(owned);
    }
    return result;
}


/**
 * Check if a string list contains a value.
 *
 * @param list   String list to search
 * @param value  Value to find
 * @return true if found, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
bool string_list_contains(const struct lantern_string_list *list, const char *value)
{
    if (!list || !value)
    {
        return false;
    }
    for (size_t i = 0; i < list->len; ++i)
    {
        if (list->items[i] && strcmp(list->items[i], value) == 0)
        {
            return true;
        }
    }
    return false;
}


/**
 * Remove a value from a string list.
 *
 * @param list   String list to modify
 * @param value  Value to remove
 *
 * @note Thread safety: Caller must hold appropriate lock
 */
void string_list_remove(struct lantern_string_list *list, const char *value)
{
    if (!list || !value)
    {
        return;
    }
    for (size_t i = 0; i < list->len; ++i)
    {
        if (list->items[i] && strcmp(list->items[i], value) == 0)
        {
            free(list->items[i]);
            for (size_t j = i; j + 1 < list->len; ++j)
            {
                list->items[j] = list->items[j + 1];
            }
            list->len--;
            list->items[list->len] = NULL;
            return;
        }
    }
}


/**
 * Get text description for connection reason code.
 *
 * @param reason  Reason code from libp2p
 * @return Static string description
 *
 * @note Thread safety: This function is thread-safe
 */
const char *connection_reason_text(int reason)
{
    switch (reason)
    {
        case 0:
            return "ok";
        case LIBP2P_ERR_NULL_PTR:
            return "null_ptr";
        case LIBP2P_ERR_AGAIN:
            return "again";
        case LIBP2P_ERR_EOF:
            return "eof";
        case LIBP2P_ERR_TIMEOUT:
            return "timeout";
        case LIBP2P_ERR_CLOSED:
            return "closed";
        case LIBP2P_ERR_RESET:
            return "reset";
        case LIBP2P_ERR_INTERNAL:
            return "internal";
        case LIBP2P_ERR_PROTO_NEGOTIATION_FAILED:
            return "protocol_negotiation_failed";
        case LIBP2P_ERR_MSG_TOO_LARGE:
            return "msg_too_large";
        case LIBP2P_ERR_UNSUPPORTED:
            return "unsupported";
        case LIBP2P_ERR_CANCELED:
            return "canceled";
        default:
            return "unknown";
    }
}
