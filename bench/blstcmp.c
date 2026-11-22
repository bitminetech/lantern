/* Bench branch only: asm-crypto against blst on one machine, the same official verify case. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include "blst.h"
typedef uint64_t u;
extern u crypto_bls_g1_decode(const uint8_t *, u *);
extern u crypto_bls_g2_decode(const uint8_t *, u *);
extern u crypto_bls_g1_add(const u *, const u *, u *);
extern u crypto_bls_verify(const uint8_t *, const u *, const uint8_t *, u *, u *);
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static void hx(const char *s, uint8_t *o, int n) { for (int i = 0; i < n; i++) { unsigned v; sscanf(s + 2 * i, "%2x", &v); o[i] = v; } }
static u scratch[(8192 + 4096) / 8];
int main(void) {
    uint8_t pk[48], sig[96], m32[32];
    hx("b53d21a4cfd562c469cc81514d4ce5a6b577d8403d32a394dc265dd190b47fa9f829fdd7963afdf972e5e77854051f6f", pk, 48);
    hx("ae82747ddeefe4fd64cf9cedb9b04ae3e8a43420cd255e3c7cd06a8d88b7c7f8638543719981c5d16fa3527c468c25f0026704a6951bde891360c7e8d12ddee0559004ccdbe6046b55bae1b257ee97f7cdb955773d7cf29adf3ccbb9975e4eb9", sig, 96);
    memset(m32, 0xab, 32);
    const char *dst = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_";
    u msg[7]; msg[0] = sizeof msg; msg[1] = 24; msg[2] = 32; memcpy(&msg[3], m32, 32);
    scratch[0] = sizeof scratch;
    u pt[36], v = 0, s = 0; int n; double t0, a, b;
    /* a key: decode and subgroup check */
    n = 5000; t0 = now(); for (int i = 0; i < n; i++) s |= crypto_bls_g1_decode(pk, pt); a = (now() - t0) / n;
    blst_p1_affine bpk; int ok = 1;
    t0 = now(); for (int i = 0; i < n; i++) { ok &= blst_p1_uncompress(&bpk, pk) == BLST_SUCCESS; ok &= blst_p1_affine_in_g1(&bpk); } b = (now() - t0) / n;
    printf("key decode + subgroup:   asm-crypto %8.1f us   blst %8.1f us   ratio %.2f (ok %d %llu)\n", a * 1e6, b * 1e6, a / b, ok, (unsigned long long)s);
    /* a signature: decode and subgroup check */
    n = 2000; t0 = now(); for (int i = 0; i < n; i++) s |= crypto_bls_g2_decode(sig, pt); a = (now() - t0) / n;
    blst_p2_affine bsig;
    t0 = now(); for (int i = 0; i < n; i++) { ok &= blst_p2_uncompress(&bsig, sig) == BLST_SUCCESS; ok &= blst_p2_affine_in_g2(&bsig); } b = (now() - t0) / n;
    printf("sig decode + subgroup:   asm-crypto %8.1f us   blst %8.1f us   ratio %.2f (ok %d)\n", a * 1e6, b * 1e6, a / b, ok);
    /* a whole verify: key, signature, hash to G2, pairings */
    n = 300; t0 = now(); for (int i = 0; i < n; i++) s |= crypto_bls_verify(pk, msg, sig, scratch, &v); a = (now() - t0) / n;
    int bv = 1;
    t0 = now(); for (int i = 0; i < n; i++) {
        bv &= blst_p1_uncompress(&bpk, pk) == BLST_SUCCESS; bv &= blst_p1_affine_in_g1(&bpk);
        bv &= blst_p2_uncompress(&bsig, sig) == BLST_SUCCESS; bv &= blst_p2_affine_in_g2(&bsig);
        bv &= blst_core_verify_pk_in_g1(&bpk, &bsig, true, m32, 32, (const byte *)dst, strlen(dst), NULL, 0) == BLST_SUCCESS;
    } b = (now() - t0) / n;
    printf("verify:                  asm-crypto %8.1f us   blst %8.1f us   ratio %.2f (valid %llu %d)\n", a * 1e6, b * 1e6, a / b, (unsigned long long)v, bv);
    /* adding a key to a sum: asm-crypto's Jacobian add (the cached sums use its mixed add, about 0.73 of it) */
    u acc[18], p2[18]; crypto_bls_g1_decode(pk, p2); memcpy(acc, p2, 144);
    n = 200000; t0 = now(); for (int i = 0; i < n; i++) crypto_bls_g1_add(acc, p2, acc); a = (now() - t0) / n;
    blst_p1 bacc; blst_p1_from_affine(&bacc, &bpk);
    t0 = now(); for (int i = 0; i < n; i++) blst_p1_add_or_double_affine(&bacc, &bacc, &bpk); b = (now() - t0) / n;
    printf("key add (Jacobian+affine for blst): asm-crypto %6.0f ns   blst %6.0f ns   ratio %.2f\n", a * 1e9, b * 1e9, a / b);
    return 0;
}
