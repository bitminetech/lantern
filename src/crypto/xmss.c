/**
 * @file xmss.c
 * @brief XMSS key loading helpers
 *
 * Provides helpers to load post-quantum XMSS keys from JSON or SSZ
 * data sources.
 */

#include "lantern/crypto/xmss.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pq-bindings-c-rust.h"

#include "lantern/support/secure_mem.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

static const char XMSS_JSON_SUFFIX[] = ".json";
static const size_t XMSS_JSON_SUFFIX_LEN = sizeof(XMSS_JSON_SUFFIX) - 1u;


/* ============================================================================
 * Error Codes
 * ============================================================================ */

enum
{
    LANTERN_XMSS_OK = 0,
    LANTERN_XMSS_ERR_INVALID_PARAM = -1,
    LANTERN_XMSS_ERR_IO = -2,
    LANTERN_XMSS_ERR_OUT_OF_MEMORY = -3,
    LANTERN_XMSS_ERR_OVERFLOW = -4,
    LANTERN_XMSS_ERR_TRUNCATED = -5,
    LANTERN_XMSS_ERR_DESERIALIZE = -6,
};


/* ============================================================================
 * Local Helpers
 * ============================================================================ */

/**
 * @brief Securely clear and free a buffer.
 *
 * @param data    Buffer to clear (may be NULL)
 * @param length  Buffer length in bytes
 *
 * @note Thread safety: This function is thread-safe.
 */
static void xmss_secure_free(uint8_t *data, size_t length)
{
    if (!data)
    {
        return;
    }

    if (length > 0)
    {
        lantern_secure_zero(data, length);
    }

    free(data);
}


/**
 * @brief Read a file into a newly allocated buffer.
 *
 * @param path        File path to read
 * @param out_data    Output buffer (caller owns on success)
 * @param out_length  Output buffer length in bytes
 *
 * @return LANTERN_XMSS_OK on success
 * @return LANTERN_XMSS_ERR_INVALID_PARAM on invalid inputs or empty file
 * @return LANTERN_XMSS_ERR_IO on filesystem errors
 * @return LANTERN_XMSS_ERR_OUT_OF_MEMORY on allocation failure
 * @return LANTERN_XMSS_ERR_OVERFLOW on size overflow
 * @return LANTERN_XMSS_ERR_TRUNCATED on short read
 *
 * @note Thread safety: This function is thread-safe.
 */
static int read_file_bytes(const char *path, uint8_t **out_data, size_t *out_length)
{
    if (!path || !out_data || !out_length)
    {
        return LANTERN_XMSS_ERR_INVALID_PARAM;
    }

    *out_data = NULL;
    *out_length = 0;

    FILE *fp = fopen(path, "rb");
    if (!fp)
    {
        return LANTERN_XMSS_ERR_IO;
    }

    int result = LANTERN_XMSS_ERR_IO;
    long file_size_long = 0;
    size_t file_size = 0;
    uint8_t *buffer = NULL;

    if (fseek(fp, 0, SEEK_END) != 0)
    {
        result = LANTERN_XMSS_ERR_IO;
        goto cleanup;
    }

    file_size_long = ftell(fp);
    if (file_size_long < 0)
    {
        result = LANTERN_XMSS_ERR_IO;
        goto cleanup;
    }

    if (file_size_long == 0)
    {
        result = LANTERN_XMSS_ERR_INVALID_PARAM;
        goto cleanup;
    }

    if ((unsigned long long)file_size_long > (unsigned long long)SIZE_MAX)
    {
        result = LANTERN_XMSS_ERR_OVERFLOW;
        goto cleanup;
    }

    file_size = (size_t)file_size_long;

    if (fseek(fp, 0, SEEK_SET) != 0)
    {
        result = LANTERN_XMSS_ERR_IO;
        goto cleanup;
    }

    buffer = malloc(file_size * sizeof(*buffer));
    if (!buffer)
    {
        result = LANTERN_XMSS_ERR_OUT_OF_MEMORY;
        goto cleanup;
    }

    size_t read_len = fread(buffer, sizeof(*buffer), file_size, fp);
    if (read_len != file_size)
    {
        result = LANTERN_XMSS_ERR_TRUNCATED;
        goto cleanup;
    }

    *out_data = buffer;
    *out_length = read_len;
    buffer = NULL;
    result = LANTERN_XMSS_OK;

cleanup:
    if (buffer)
    {
        xmss_secure_free(buffer, file_size);
    }
    fclose(fp);
    return result;
}


/**
 * @brief Check whether a file path ends with ".json".
 *
 * @param path File path to check
 *
 * @return true if the path ends with ".json", false otherwise
 *
 * @note Thread safety: This function is thread-safe.
 */
static bool is_json_file(const char *path)
{
    if (!path)
    {
        return false;
    }

    size_t len = strlen(path);
    if (len < XMSS_JSON_SUFFIX_LEN)
    {
        return false;
    }

    return strcmp(path + len - XMSS_JSON_SUFFIX_LEN, XMSS_JSON_SUFFIX) == 0;
}


/* ============================================================================
 * Public API
 * ============================================================================ */

/**
 * Load a secret key from SSZ-encoded bytes.
 *
 * @param data     Input buffer containing SSZ-encoded secret key bytes
 * @param length   Length of the input buffer in bytes
 * @param out_key  Output secret key handle (allocated by the PQ library)
 *
 * @return LANTERN_XMSS_OK on success
 * @return LANTERN_XMSS_ERR_INVALID_PARAM on invalid inputs
 * @return LANTERN_XMSS_ERR_DESERIALIZE on parse failure
 *
 * @note Ownership: Caller must free `*out_key` with `pq_secret_key_free`.
 * @note Thread safety: This function is thread-safe.
 */
int lantern_xmss_load_secret_bytes(
    const uint8_t *data,
    size_t length,
    struct PQSignatureSchemeSecretKey **out_key)
{
    if (!data || length == 0 || !out_key)
    {
        return LANTERN_XMSS_ERR_INVALID_PARAM;
    }

    *out_key = NULL;

    enum PQSigningError rc = pq_secret_key_deserialize(data, length, out_key);
    if (rc != Success || !*out_key)
    {
        return LANTERN_XMSS_ERR_DESERIALIZE;
    }

    return LANTERN_XMSS_OK;
}


/**
 * Load a public key from SSZ-encoded bytes.
 *
 * @param data     Input buffer containing SSZ-encoded public key bytes
 * @param length   Length of the input buffer in bytes
 * @param out_key  Output public key handle (allocated by the PQ library)
 *
 * @return LANTERN_XMSS_OK on success
 * @return LANTERN_XMSS_ERR_INVALID_PARAM on invalid inputs
 * @return LANTERN_XMSS_ERR_DESERIALIZE on parse failure
 *
 * @note Ownership: Caller must free `*out_key` with `pq_public_key_free`.
 * @note Thread safety: This function is thread-safe.
 */
int lantern_xmss_load_public_bytes(
    const uint8_t *data,
    size_t length,
    struct PQSignatureSchemePublicKey **out_key)
{
    if (!data || length == 0 || !out_key)
    {
        return LANTERN_XMSS_ERR_INVALID_PARAM;
    }

    *out_key = NULL;

    enum PQSigningError rc = pq_public_key_deserialize(data, length, out_key);
    if (rc != Success || !*out_key)
    {
        return LANTERN_XMSS_ERR_DESERIALIZE;
    }

    return LANTERN_XMSS_OK;
}


/**
 * Load a secret key from a JSON or SSZ file.
 *
 * @param path     File path to read
 * @param out_key  Output secret key handle (allocated by the PQ library)
 *
 * @return LANTERN_XMSS_OK on success
 * @return LANTERN_XMSS_ERR_INVALID_PARAM on invalid inputs
 * @return LANTERN_XMSS_ERR_IO on filesystem errors
 * @return LANTERN_XMSS_ERR_OUT_OF_MEMORY on allocation failure
 * @return LANTERN_XMSS_ERR_OVERFLOW on size overflow
 * @return LANTERN_XMSS_ERR_TRUNCATED on short read
 * @return LANTERN_XMSS_ERR_DESERIALIZE on parse failure
 *
 * @note Ownership: Caller must free `*out_key` with `pq_secret_key_free`.
 * @note Thread safety: This function is thread-safe.
 */
int lantern_xmss_load_secret_file(
    const char *path,
    struct PQSignatureSchemeSecretKey **out_key)
{
    if (!path || !out_key)
    {
        return LANTERN_XMSS_ERR_INVALID_PARAM;
    }

    *out_key = NULL;

    uint8_t *data = NULL;
    size_t length = 0;
    int result = read_file_bytes(path, &data, &length);
    if (result != LANTERN_XMSS_OK)
    {
        return result;
    }

    if (is_json_file(path))
    {
        enum PQSigningError err = pq_secret_key_from_json(data, length, out_key);
        result = (err == Success && *out_key)
            ? LANTERN_XMSS_OK
            : LANTERN_XMSS_ERR_DESERIALIZE;
    }
    else
    {
        result = lantern_xmss_load_secret_bytes(data, length, out_key);
    }

    xmss_secure_free(data, length);
    return result;
}


/**
 * Load a public key from a JSON or SSZ file.
 *
 * @param path     File path to read
 * @param out_key  Output public key handle (allocated by the PQ library)
 *
 * @return LANTERN_XMSS_OK on success
 * @return LANTERN_XMSS_ERR_INVALID_PARAM on invalid inputs
 * @return LANTERN_XMSS_ERR_IO on filesystem errors
 * @return LANTERN_XMSS_ERR_OUT_OF_MEMORY on allocation failure
 * @return LANTERN_XMSS_ERR_OVERFLOW on size overflow
 * @return LANTERN_XMSS_ERR_TRUNCATED on short read
 * @return LANTERN_XMSS_ERR_DESERIALIZE on parse failure
 *
 * @note Ownership: Caller must free `*out_key` with `pq_public_key_free`.
 * @note Thread safety: This function is thread-safe.
 */
int lantern_xmss_load_public_file(
    const char *path,
    struct PQSignatureSchemePublicKey **out_key)
{
    if (!path || !out_key)
    {
        return LANTERN_XMSS_ERR_INVALID_PARAM;
    }

    *out_key = NULL;

    uint8_t *data = NULL;
    size_t length = 0;
    int result = read_file_bytes(path, &data, &length);
    if (result != LANTERN_XMSS_OK)
    {
        return result;
    }

    if (is_json_file(path))
    {
        enum PQSigningError err = pq_public_key_from_json(data, length, out_key);
        result = (err == Success && *out_key)
            ? LANTERN_XMSS_OK
            : LANTERN_XMSS_ERR_DESERIALIZE;
    }
    else
    {
        result = lantern_xmss_load_public_bytes(data, length, out_key);
    }

    free(data);
    return result;
}


/**
 * Check whether the XMSS backend is available.
 *
 * @return true when the XMSS scheme reports a positive lifetime
 *
 * @note Thread safety: This function is thread-safe.
 */
bool lantern_xmss_is_available(void)
{
    /*
     * pq_get_lifetime() is part of the public XMSS C bindings API. A non-zero
     * lifetime means the Rust bindings initialised correctly and returned the
     * scheme configuration constants.
     */
    return pq_get_lifetime() > 0u;
}
