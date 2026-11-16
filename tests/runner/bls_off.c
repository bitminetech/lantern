/*
 * Stand-ins for the three asm-crypto signature checks that lantern calls, for
 * the signatures-off runner, runner-<preset>-bls-off. Test code.
 *
 * Cases with bls_setting 2 were made with signature checks off. In the spec's
 * test mode (tests/core/pyspec/eth_consensus_specs/utils/bls.py of the pinned
 * spec), Verify and FastAggregateVerify, and so eth_fast_aggregate_verify,
 * return True, while public key aggregation still runs. platform/objects.sh
 * renames these three functions in a copy of asm-crypto's bls12381 object to
 * <name>_real, and these take their names. Each writes 1 to valid and returns
 * CRYPTO_OK; lantern's own checks around them still run.
 */
#include <stdint.h>

#if defined(_WIN32) && defined(__x86_64__)
#define ABI __attribute__((sysv_abi))
#else
#define ABI
#endif

static uint64_t accept(void *valid) {
    *(uint64_t *)valid = 1;
    return 0;
}

ABI uint64_t crypto_bls_verify(const void *public_key, const void *message, const void *signature, void *scratch,
                               void *valid);
ABI uint64_t crypto_bls_fast_aggregate_verify(const void *public_keys, const void *message, const void *signature,
                                              void *scratch, void *valid);
ABI uint64_t crypto_bls_eth_fast_aggregate_verify(const void *public_keys, const void *message, const void *signature,
                                                  void *scratch, void *valid);

ABI uint64_t crypto_bls_verify(const void *public_key, const void *message, const void *signature, void *scratch,
                               void *valid) {
    (void)public_key, (void)message, (void)signature, (void)scratch;
    return accept(valid);
}

ABI uint64_t crypto_bls_fast_aggregate_verify(const void *public_keys, const void *message, const void *signature,
                                              void *scratch, void *valid) {
    (void)public_keys, (void)message, (void)signature, (void)scratch;
    return accept(valid);
}

ABI uint64_t crypto_bls_eth_fast_aggregate_verify(const void *public_keys, const void *message, const void *signature,
                                                  void *scratch, void *valid) {
    (void)public_keys, (void)message, (void)signature, (void)scratch;
    return accept(valid);
}
