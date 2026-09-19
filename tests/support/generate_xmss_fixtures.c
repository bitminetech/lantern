#include "leanvm.h"

#include <stdio.h>
#include <stdlib.h>

/* Public test fixtures only. Never use these keys on a live network. */
static int write_fixture(
    const char *directory,
    size_t index,
    const char *kind,
    const uint8_t *bytes,
    size_t length)
{
    char path[4096];
    int written = snprintf(path, sizeof(path), "%s/validator_%zu_%s.ssz", directory, index, kind);
    if (written < 0 || (size_t)written >= sizeof(path)) {
        return -1;
    }
    FILE *file = fopen(path, "wb");
    if (!file) {
        perror(path);
        return -1;
    }
    int result = fwrite(bytes, 1u, length, file) == length ? 0 : -1;
    if (fclose(file) != 0) {
        result = -1;
    }
    return result;
}

static int generate_fixture(const char *directory, size_t index)
{
    struct PQSignatureSchemePublicKey *public_key = NULL;
    struct PQSignatureSchemeSecretKey *secret_key = NULL;
    uint8_t *secret_bytes = NULL;
    uint8_t public_bytes[PUBLIC_KEY_SIZE];
    uintptr_t public_length = 0;
    uintptr_t secret_length = 0;
    uint8_t probe = 0;
    int result = -1;

    if (pq_key_gen(0u, 65536u, &public_key, &secret_key) != Success
        || pq_public_key_serialize(public_key, public_bytes, sizeof(public_bytes), &public_length)
            != Success
        || public_length != sizeof(public_bytes)) {
        goto cleanup;
    }
    /* A short buffer reports the required postcard length without copying. */
    (void)pq_secret_key_serialize(secret_key, &probe, sizeof(probe), &secret_length);
    if (secret_length == 0u) {
        goto cleanup;
    }
    secret_bytes = malloc(secret_length);
    if (!secret_bytes
        || pq_secret_key_serialize(secret_key, secret_bytes, secret_length, &secret_length)
            != Success) {
        goto cleanup;
    }
    if (write_fixture(directory, index, "pk", public_bytes, public_length) != 0
        || write_fixture(directory, index, "sk", secret_bytes, secret_length) != 0) {
        goto cleanup;
    }
    result = 0;
cleanup:
    free(secret_bytes);
    pq_public_key_free(public_key);
    pq_secret_key_free(secret_key);
    return result;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "Usage: %s EXISTING_OUTPUT_DIRECTORY\n", argv[0]);
        return 1;
    }
    for (size_t index = 0; index < 2u; ++index) {
        if (generate_fixture(argv[1], index) != 0) {
            fprintf(stderr, "Failed to generate test fixture %zu\n", index);
            return 1;
        }
    }
    puts("Generated two test-only key pairs for slots 0..65535.");
    return 0;
}
