#include "lantern/crypto/hash_sig.h"

#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pq-bindings-c-rust.h"

static int read_file_bytes(const char *path, uint8_t **out_data, size_t *out_length) {
    if (!path || !out_data || !out_length) {
        return -1;
    }
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return -1;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return -1;
    }
    long file_size = ftell(fp);
    if (file_size < 0) {
        fclose(fp);
        return -1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return -1;
    }
    uint8_t *buffer = malloc((size_t)file_size);
    if (!buffer) {
        fclose(fp);
        return -1;
    }
    size_t read_len = fread(buffer, 1, (size_t)file_size, fp);
    fclose(fp);
    if (read_len != (size_t)file_size) {
        free(buffer);
        return -1;
    }
    *out_data = buffer;
    *out_length = read_len;
    return 0;
}

int lantern_hash_sig_load_secret_bytes(
    const uint8_t *data,
    size_t length,
    struct PQSignatureSchemeSecretKey **out_key) {
    if (!data || length == 0 || !out_key) {
        return -1;
    }
    // Use SSZ format (compatible with Ream's leanSig)
    enum PQSigningError rc = pq_secret_key_deserialize(data, length, out_key);
    return (rc == Success && out_key && *out_key) ? 0 : -1;
}

int lantern_hash_sig_load_public_bytes(
    const uint8_t *data,
    size_t length,
    struct PQSignatureSchemePublicKey **out_key) {
    if (!data || length == 0 || !out_key) {
        return -1;
    }
    // Use SSZ format (compatible with Ream's leanSig)
    enum PQSigningError rc = pq_public_key_deserialize(data, length, out_key);
    return (rc == Success && out_key && *out_key) ? 0 : -1;
}

static int is_json_file(const char *path) {
    if (!path) return 0;
    size_t len = strlen(path);
    return len > 5 && strcmp(path + len - 5, ".json") == 0;
}

int lantern_hash_sig_load_secret_file(
    const char *path,
    struct PQSignatureSchemeSecretKey **out_key) {
    if (!path || !out_key) {
        return -1;
    }
    uint8_t *data = NULL;
    size_t length = 0;
    if (read_file_bytes(path, &data, &length) != 0) {
        return -1;
    }

    int rc;
    if (is_json_file(path)) {
        // JSON format
        enum PQSigningError err = pq_secret_key_from_json(data, length, out_key);
        rc = (err == Success && out_key && *out_key) ? 0 : -1;
        free(data);
    } else {
        // SSZ format
        rc = lantern_hash_sig_load_secret_bytes(data, length, out_key);
        free(data);
    }
    return rc;
}

int lantern_hash_sig_load_public_file(
    const char *path,
    struct PQSignatureSchemePublicKey **out_key) {
    if (!path || !out_key) {
        return -1;
    }
    uint8_t *data = NULL;
    size_t length = 0;
    if (read_file_bytes(path, &data, &length) != 0) {
        return -1;
    }

    int rc;
    if (is_json_file(path)) {
        // JSON format
        enum PQSigningError err = pq_public_key_from_json(data, length, out_key);
        rc = (err == Success && out_key && *out_key) ? 0 : -1;
        free(data);
    } else {
        // SSZ format
        rc = lantern_hash_sig_load_public_bytes(data, length, out_key);
        free(data);
    }
    return rc;
}

bool lantern_hash_sig_is_available(void) {
    /*
     * pq_get_lifetime() is part of the public c-hash-sig API.  A non-zero
     * lifetime means the Rust bindings initialised correctly and returned the
     * scheme configuration constants.
     */
    return pq_get_lifetime() > 0u;
}
