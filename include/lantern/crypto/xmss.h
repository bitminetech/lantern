#ifndef LANTERN_CRYPTO_XMSS_H
#define LANTERN_CRYPTO_XMSS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

struct PQSignatureSchemeSecretKey;
struct PQSignatureSchemePublicKey;

/**
 * Return true when the XMSS library is linked in and responsive.
 */
bool lantern_xmss_is_available(void);

int lantern_xmss_load_secret_file(
    const char *path,
    struct PQSignatureSchemeSecretKey **out_key);
int lantern_xmss_load_public_file(
    const char *path,
    struct PQSignatureSchemePublicKey **out_key);
int lantern_xmss_load_secret_bytes(
    const uint8_t *data,
    size_t length,
    struct PQSignatureSchemeSecretKey **out_key);
int lantern_xmss_load_public_bytes(
    const uint8_t *data,
    size_t length,
    struct PQSignatureSchemePublicKey **out_key);

#endif /* LANTERN_CRYPTO_XMSS_H */
