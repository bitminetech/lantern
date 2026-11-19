/*
 * State benchmarks at mainnet scale (bench/README.md): a mainnet fulu state from the vectors, grown
 * to N validators by repeating its own, then the time of a copy, hash_tree_root, process_epoch and
 * process_slots across an epoch boundary. The runner's helpers come from tests/runner/runner.c.
 * Usage: bench-state VECTOR_DIR [N]
 */
#define _POSIX_C_SOURCE 199309L /* clock_gettime */
#define main runner_main
#include "../tests/runner/runner.c"
#undef main
#include <time.h>

ABI uint64_t LF(get_beacon_committee)(const void *state, const void *slot, const void *index, void *cache, void *scratch,
                                        void *out);
ABI uint64_t LF(is_valid_indexed_attestation)(const void *state, const void *indexed, void *cache, void *scratch, void *out);
ABI uint64_t LF(get_committee_count_per_slot)(const void *state, const void *epoch, void *cache, void *scratch, void *out);
ABI uint64_t LF(get_beacon_proposer_index)(const void *state, void *out);
ABI uint64_t LF(get_expected_withdrawals)(const void *state, void *scratch, void *out);

static double now_s(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

/*
 * is_valid_indexed_attestation of k indices spread over the validators, with a real signature of
 * another message: every key check and the pairing run, and the result is 0.
 */
static void time_indexed(const uint8_t *state, uint64_t n, uint64_t k, uint8_t *pubkeys, uint8_t *scratch, uint64_t ssize) {
    if (k > n) k = n;
    uint64_t len = 228 + 8 * k, vsize = 0, valid = 9;
    uint8_t *enc = calloc(1, (size_t)len), msg[32] = {1};
    const char *why = NULL;
    enc[0] = 228; /* the offset of attesting_indices, after data (128) and signature (96) */
    test_sign(0, msg, enc + 132, &why);
    for (uint64_t i = 0; i < k; i++) wr64(enc + 228 + 8 * i, i * (n / k));
    uint8_t *value = decode(type_by_name("IndexedAttestation"), enc, len, &vsize, &why);
    if (!value) {
        printf("is_valid_indexed_attestation, %llu keys: %s\n", (unsigned long long)k, why ? why : "no value");
        free(enc);
        return;
    }
    for (int r = 0; r < 3; r++) { /* no cache; a PubkeyCache that the first call fills; the filled one */
        void *c = r ? pubkeys : NULL;
        wr64(scratch, ssize);
        double a = now_s();
        uint64_t st = CALL(LF(is_valid_indexed_attestation), state, value, c, scratch, &valid);
        double t = now_s() - a;
        printf("is_valid_indexed_attestation, %llu keys, %s: %.4f s, %.1f us a key (status %llu, valid %llu)\n",
               (unsigned long long)k, r == 0 ? "no cache" : r == 1 ? "cache empty" : "cache filled", t, t * 1e6 / (double)k,
               (unsigned long long)st, (unsigned long long)valid);
    }
    free(value);
    free(enc);
}

/* Bytes that grow at the end: the SSZ encoding of the block. */
typedef struct {
    uint8_t *p;
    uint64_t len, cap;
} bytes_t;

/* n zero bytes at the end of b. */
static uint8_t *put(bytes_t *b, uint64_t n) {
    if (b->len + n > b->cap) {
        b->cap = 2 * (b->len + n);
        uint8_t *q = realloc(b->p, (size_t)b->cap);
        if (!q) {
            fprintf(stderr, "out of memory\n");
            exit(2);
        }
        b->p = q;
    }
    uint8_t *at = b->p + b->len;
    memset(at, 0, (size_t)n);
    b->len += n;
    return at;
}

/* An SSZ offset. */
static void put_offset(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (8 * i));
}

/* A copy of the state, with room as the node gives its copies. */
static uint8_t *state_dup(const uint8_t *st, const uint64_t *keep) {
    uint64_t need = 0;
    CALL(LF(beacon_state_copy_size), st, keep, &need);
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(LF(beacon_state_copy), st, keep, out) != 0) fprintf(stderr, "state copy status\n");
    return out;
}

/* The signing root of the 32-byte root of an object under the state's domain of type dt at epoch. */
static void bench_signing_root(const uint8_t *st, uint8_t dt, uint64_t epoch, const uint8_t *root, uint8_t *scratch,
                               uint64_t ssize, uint8_t *out) {
    uint8_t type[4] = {dt, 0, 0, 0}, domain[32];
    wr64(scratch, ssize);
    if (CALL(LF(get_domain), st, type, &epoch, scratch, domain) != 0) fprintf(stderr, "get_domain status\n");
    signing_root(root, domain, out);
}

/*
 * The Attestation, in SSZ, of every committee of aslot with every bit set, signed: the secret key
 * of validator v is v % have + 1, as the state repeats its first have validators, so the aggregate
 * signature is the signature of the sum of the attesters' secret keys.
 */
static uint8_t *full_attestation(const uint8_t *st, uint64_t aslot, uint64_t have, uint8_t *ccache, uint8_t *committee,
                                 uint8_t *scratch, uint64_t ssize, uint64_t *olen, uint64_t *keys) {
    uint64_t epoch = aslot / SLOTS_PER_EPOCH_RUNNER, count = 0, bits = 0, sum = 0;
    uint64_t now = rd64(st + 48) / SLOTS_PER_EPOCH_RUNNER; /* NODE_STATE_SLOT 48 */
    const char *why = NULL;
    wr64(scratch, ssize);
    if (CALL(LF(get_committee_count_per_slot), st, &epoch, ccache, scratch, &count) != 0) why = "get_committee_count_per_slot";
    for (uint64_t c = 0; c < count && !why; c++) {
        wr64(committee, 24 + 8 * 65536);
        wr64(scratch, ssize);
        if (CALL(LF(get_beacon_committee), st, &aslot, &c, ccache, scratch, committee) != 0) why = "get_beacon_committee";
        const uint8_t *e = committee + rd64(committee + 8);
        for (uint64_t i = 0, m = rd64(committee + 16); i < m && !why; i++) sum += rd64(e + 8 * i) % have + 1;
        bits += rd64(committee + 16);
    }
    *olen = 236 + bits / 8 + 1;
    uint8_t *enc = calloc(1, (size_t)*olen), data[128], dr[32], sr[32];
    const uint8_t *roots = st + field_offset("BeaconState", 5);
    put_offset(enc, 236); /* aggregation_bits, after data (128), signature (96) and committee_bits (8) */
    memset(data, 0, sizeof data);
    wr64(data, aslot);
    memcpy(data + 16, roots + 32 * (aslot % 8192), 32);                         /* beacon_block_root: the head */
    memcpy(data + 48, st + field_offset("BeaconState", epoch == now ? 19 : 18), 40); /* source: the justified checkpoint */
    wr64(data + 88, epoch);                                                       /* target */
    memcpy(data + 96, roots + 32 * ((epoch * SLOTS_PER_EPOCH_RUNNER) % 8192), 32);
    memcpy(enc + 4, data, 128);
    if (!why) root_of("AttestationData", data, dr, &why);
    if (!why) bench_signing_root(st, 1, epoch, dr, scratch, ssize, sr); /* DOMAIN_BEACON_ATTESTER */
    if (!why) test_sign(sum - 1, sr, enc + 132, &why);
    for (uint64_t c = 0; c < count; c++) enc[228 + c / 8] |= (uint8_t)(1 << (c % 8));
    for (uint64_t i = 0; i < bits; i++) enc[236 + i / 8] |= (uint8_t)(1 << (i % 8));
    enc[236 + bits / 8] |= (uint8_t)(1 << (bits % 8)); /* the delimiter bit */
    if (why) {
        printf("block: attestation of slot %llu: %s\n", (unsigned long long)aslot, why);
        free(enc);
        return NULL;
    }
    *keys = bits;
    return enc;
}

/*
 * process_block of a full block at the 10th slot of the epoch of st, an epoch's first slot: 8
 * attestations, each of every committee of one of the 8 slots before, with every bit set; a sync
 * aggregate of the whole committee; the expected withdrawals; every signature valid. With the
 * committee and public key caches empty, then filled; then lantern_state_root of the state after,
 * with the StateCache; then process_attestation and process_sync_aggregate alone.
 */
static void time_block(uint8_t *st, const uint64_t *keep, uint64_t n, uint64_t have, uint8_t *cache, uint8_t *pubkeys,
                       uint8_t *scratch, uint64_t ssize) {
    uint64_t ccsize = 0, one = 1, r = 0, valid = 9, prop = 0, s = rd64(st + 48), keys = 0; /* NODE_STATE_SLOT 48 */
    const char *why = NULL;
    CALL(LF(committee_cache_size), &n, &ccsize);
    uint8_t *ccache = buffer(ccsize), *committee = buffer(24 + 8 * 65536), root[32], sr[32];
    wr64(ccache, ccsize);
    CALL(LF(committee_cache_init), &n, ccache);
    wr64(config + CONFIG_STATE_CACHE, (uint64_t)(uintptr_t)cache);
    wr64(config + CONFIG_COMMITTEE_CACHE, (uint64_t)(uintptr_t)ccache);
    wr64(config + CONFIG_PUBKEY_CACHE, (uint64_t)(uintptr_t)pubkeys);
    s = s - s % SLOTS_PER_EPOCH_RUNNER + 10;
    if (s <= rd64(st + 48)) s += SLOTS_PER_EPOCH_RUNNER;
    wr64(scratch, ssize);
    if (CALL(LF(process_slots), st, &s, config, scratch, &r) != 0 || r != 0) why = "process_slots";
    wr64(scratch, ssize);
    if (!why && CALL(LF(state_root), st, cache, scratch, root) != 0) why = "state_root";
    uint64_t epoch = s / SLOTS_PER_EPOCH_RUNNER;
    if (!why && CALL(LF(get_beacon_proposer_index), st, &prop) != 0) why = "get_beacon_proposer_index";
    /* The attestations of the 8 slots before s. */
    uint8_t *att[8] = {0};
    uint64_t alen[8] = {0}, akeys[8] = {0}, atotal = 0;
    for (int a = 0; a < 8 && !why; a++) {
        att[a] = full_attestation(st, s - 1 - (uint64_t)a, have, ccache, committee, scratch, ssize, &alen[a], &akeys[a]);
        if (!att[a]) why = "attestation";
        atotal += alen[a];
        keys += akeys[a];
    }
    /* The sync aggregate: the members' secret keys from the place of their keys among the first have validators. */
    const uint8_t *sync_keys = st + field_offset("BeaconState", 22);
    const uint8_t *vals = nested(st, field_offset("BeaconState", 11));
    uint64_t sync_sum = 0;
    for (uint64_t k = 0; k < 512 && !why; k++) {
        uint64_t j = 0;
        while (j < have && memcmp(vals + 128 * j, sync_keys + 48 * k, 48)) j++;
        if (j == have) why = "a sync committee key is not among the first validators";
        sync_sum += j + 1;
    }
    /* The expected withdrawals, as the payload must hold them. */
    uint64_t wsize = 16 + 24 + 16 * 48, wstride = (field_offset("Withdrawal", 3) + 8 + 7) & ~(uint64_t)7;
    uint8_t *ew = buffer(wsize);
    memset(ew, 0, (size_t)wsize);
    wr64(scratch, ssize);
    if (!why && CALL(LF(get_expected_withdrawals), st, scratch, ew) != 0) why = "get_expected_withdrawals";
    uint64_t wcount = why ? 0 : rd64(ew + 32);
    const uint8_t *we = ew + 16 + rd64(ew + 24);
    if (why) {
        printf("block: %s\n", why);
        goto out;
    }
    /* BeaconBlockBody: the fixed part (396 bytes), then the lists in field order. */
    bytes_t body = {0};
    uint8_t *f = put(&body, 396), chunk[32] = {0};
    wr64(chunk, epoch);
    bench_signing_root(st, 2, epoch, chunk, scratch, ssize, sr); /* randao_reveal: DOMAIN_RANDAO */
    test_sign(prop % have, sr, f, &why);
    memcpy(f + 96, st + field_offset("BeaconState", 8), 72); /* eth1_data: the state's, so no vote changes it */
    memset(f + 220, 0xff, 64);                               /* sync_committee_bits */
    bench_signing_root(st, 7, (s - 1) / SLOTS_PER_EPOCH_RUNNER, st + field_offset("BeaconState", 5) + 32 * ((s - 1) % 8192),
                       scratch, ssize, sr); /* DOMAIN_SYNC_COMMITTEE, the block root of the previous slot */
    if (!why) test_sign(sync_sum - 1, sr, f + 284, &why);
    put_offset(body.p + 200, body.len); /* proposer_slashings, attester_slashings: none */
    put_offset(body.p + 204, body.len);
    put_offset(body.p + 208, body.len); /* attestations */
    uint64_t at = body.len, pos = 32;
    put(&body, 32 + atotal);
    for (int a = 0; a < 8; a++) {
        put_offset(body.p + at + 4 * a, pos);
        memcpy(body.p + at + pos, att[a], (size_t)alen[a]);
        pos += alen[a];
    }
    put_offset(body.p + 212, body.len); /* deposits, voluntary_exits: none */
    put_offset(body.p + 216, body.len);
    put_offset(body.p + 380, body.len); /* execution_payload */
    uint8_t *p = put(&body, 528 + 44 * wcount);
    const uint8_t *hdr = nested(st, field_offset("BeaconState", 24));
    memcpy(p, hdr + field_offset("ExecutionPayloadHeader", 12), 32);                         /* parent_hash */
    memcpy(p + 372, st + field_offset("BeaconState", 13) + 32 * (epoch % 65536), 32);       /* prev_randao */
    wr64(p + 404, rd64(hdr + field_offset("ExecutionPayloadHeader", 6)) + 1);                 /* block_number */
    wr64(p + 412, 36000000);                                                                  /* gas_limit */
    wr64(p + 428, rd64(st + field_offset("BeaconState", 0)) + s * rd64(config + 104) / 1000); /* timestamp */
    put_offset(p + 436, 528);                                                                 /* extra_data: empty */
    memset(p + 472, 0x11, 32);                                                                /* block_hash */
    put_offset(p + 504, 528);                                                                 /* transactions: none */
    put_offset(p + 508, 528);                                                                 /* withdrawals */
    for (uint64_t w = 0; w < wcount; w++) {
        const uint8_t *e = we + wstride * w;
        uint8_t *o = p + 528 + 44 * w;
        wr64(o, rd64(e));
        wr64(o + 8, rd64(e + field_offset("Withdrawal", 1)));
        memcpy(o + 16, e + field_offset("Withdrawal", 2), 20);
        wr64(o + 36, rd64(e + field_offset("Withdrawal", 3)));
    }
    put_offset(body.p + 384, body.len); /* bls_to_execution_changes, blob_kzg_commitments: none */
    put_offset(body.p + 388, body.len);
    put_offset(body.p + 392, body.len); /* execution_requests: three empty lists */
    uint8_t *q = put(&body, 12);
    put_offset(q, 12);
    put_offset(q + 4, 12);
    put_offset(q + 8, 12);
    /* SignedBeaconBlock: the message's offset, the signature, then the BeaconBlock. */
    bytes_t sbe = {0};
    put(&sbe, 100 + 84);
    put_offset(sbe.p, 100);
    uint8_t *m = sbe.p + 100;
    wr64(m, s);
    wr64(m + 8, prop);
    root_of("BeaconBlockHeader", st + field_offset("BeaconState", 4), m + 16, &why); /* parent_root */
    put_offset(m + 80, 84);
    memcpy(put(&sbe, body.len), body.p, (size_t)body.len);
    uint64_t vsize = 0;
    uint8_t *sb = why ? NULL : decode(type_by_name("SignedBeaconBlock"), sbe.p, sbe.len, &vsize, &why);
    const uint8_t *msg = sb ? nested(sb, field_offset("SignedBeaconBlock", 0)) : NULL;
    if (sb) root_of("BeaconBlock", msg, root, &why);
    if (sb && !why) {
        bench_signing_root(st, 0, epoch, root, scratch, ssize, sr); /* DOMAIN_BEACON_PROPOSER */
        test_sign(prop % have, sr, sb + field_offset("SignedBeaconBlock", 1), &why);
    }
    printf("block: slot %llu, proposer %llu, %llu bytes, 8 attestations of %llu keys, %llu withdrawals%s%s\n",
           (unsigned long long)s, (unsigned long long)prop, (unsigned long long)sbe.len, (unsigned long long)keys,
           (unsigned long long)wcount, why ? ": " : "", why ? why : "");
    if (sb && !why) {
        wr64(scratch, ssize);
        double a = now_s();
        uint64_t st1 = CALL(LF(verify_block_signature), st, sb, scratch, &valid);
        printf("verify_block_signature: %.4f s (status %llu, valid %llu)\n", now_s() - a, (unsigned long long)st1,
               (unsigned long long)valid);
        for (int run = 0; run < 2; run++) { /* the committee and public key caches empty, then filled by the first run */
            if (run == 0) {
                CALL(LF(committee_cache_init), &n, ccache);
                CALL(LF(pubkey_cache_init), &n, pubkeys);
            }
            uint8_t *b = state_dup(st, keep);
            wr64(scratch, ssize);
            r = 9;
            a = now_s();
            st1 = CALL(LF(process_block), b, msg, &one, config, scratch, &r);
            double t = now_s() - a;
            printf("process_block, caches %s: %.4f s (status %llu, result %llu)\n", run ? "filled" : "empty", t,
                   (unsigned long long)st1, (unsigned long long)r);
            if (run == 1) { /* the state root after the block, with the StateCache of the state before */
                uint8_t got[32], want[32];
                const char *rwhy = NULL;
                wr64(scratch, ssize);
                a = now_s();
                st1 = CALL(LF(state_root), b, cache, scratch, got);
                t = now_s() - a;
                root_of("BeaconState", b, want, &rwhy);
                printf("lantern_state_root after the block, with the cache: %.4f s (status %llu)%s\n", t,
                       (unsigned long long)st1, rwhy || memcmp(got, want, 32) ? " (root differs)" : "");
            }
            free(b);
        }
        /* The parts alone, with the caches filled: one attestation, then the sync aggregate. */
        uint8_t *b = state_dup(st, keep), *av = decode(type_by_name("Attestation"), att[0], alen[0], &vsize, &why);
        const uint8_t *bodyv = nested(msg, field_offset("BeaconBlock", 4));
        if (av) {
            wr64(scratch, ssize);
            r = 9;
            a = now_s();
            st1 = CALL(LF(process_attestation), b, av, config, scratch, &r);
            printf("process_attestation, %llu keys: %.4f s (status %llu, result %llu)\n",
                   (unsigned long long)akeys[0], now_s() - a, (unsigned long long)st1, (unsigned long long)r);
            free(av);
        }
        wr64(scratch, ssize);
        r = 9;
        a = now_s();
        st1 = CALL(LF(process_sync_aggregate), b, bodyv + field_offset("BeaconBlockBody", 8), config, scratch, &r);
        printf("process_sync_aggregate, members among the first %llu validators: %.4f s (status %llu, result %llu)\n",
               (unsigned long long)have, now_s() - a, (unsigned long long)st1, (unsigned long long)r);
        free(b);
        /*
         * The search of each member's index: in this state each key repeats every have validators, so
         * the search ends early. With every key before the last have validators changed, it runs
         * through all but have of them, as in a state of n distinct keys at worst.
         */
        b = state_dup(st, keep);
        uint8_t *bv = (uint8_t *)nested(b, field_offset("BeaconState", 11));
        for (uint64_t i = 0; i + have < n; i++) memset(bv + 128 * i, 0, 48);
        wr64(scratch, ssize);
        r = 9;
        a = now_s();
        st1 = CALL(LF(process_sync_aggregate), b, bodyv + field_offset("BeaconBlockBody", 8), config, scratch, &r);
        printf("process_sync_aggregate, members among the last %llu validators: %.4f s (status %llu, result %llu)\n",
               (unsigned long long)have, now_s() - a, (unsigned long long)st1, (unsigned long long)r);
        free(b);
    }
    free(sb);
    free(body.p);
    free(sbe.p);
out:
    for (int a = 0; a < 8; a++) free(att[a]);
    free(ew);
    free(committee);
    free(ccache);
    wr64(config + CONFIG_COMMITTEE_CACHE, 0);
    wr64(config + CONFIG_PUBKEY_CACHE, 0);
}

/* The list of BeaconState field f with entries of esize bytes: entries i >= count take entry i % count, up to n. */
static void grow_list(uint8_t *state, int f, uint64_t esize, uint64_t n) {
    uint64_t ref = field_offset("BeaconState", f), count = rd64(state + ref + 8);
    uint8_t *base = state + rd64(state + ref);
    for (uint64_t i = count; i < n; i++) memcpy(base + i * esize, base + (i % count) * esize, (size_t)esize);
    wr64(state + ref + 8, n);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s VECTOR_DIR [VALIDATORS]\n", argv[0]);
        return 2;
    }
    uint64_t n = argc > 2 ? strtoull(argv[2], NULL, 10) : 1000000;
    load_config(argv[1]);
    case_file f;
    if (!read_file(argv[1], "mainnet-fulu-epoch_processing-rewards_and_penalties.bin", &f)) {
        fprintf(stderr, "no mainnet fulu epoch_processing vectors in %s\n", argv[1]);
        return 2;
    }
    const char *name, *why = NULL;
    uint64_t len, slen, size = 0;
    tv parts = next_case(&f, &name, &len);
    case_config(parts);
    uint8_t *small = load_state(tv_bytes(tv_get(parts, "pre"), &slen), slen, &size, &why);
    if (!small) {
        fprintf(stderr, "load_state: %s\n", why);
        return 2;
    }
    uint64_t have = rd64(small + field_offset("BeaconState", 11) + 8);
    uint64_t room[8] = {n, 64, 4, 9000, 64, 64, 4, 4096}, need = 0; /* StateRoom: validators first */
    CALL(LF(beacon_state_copy_size), small, room, &need);
    uint8_t *state = buffer(need);
    wr64(state, need);
    if (CALL(LF(beacon_state_copy), small, room, state) != 0) {
        fprintf(stderr, "beacon_state_copy status\n");
        return 2;
    }
    grow_list(state, 11, 128, n); /* validators, balances, the participations, inactivity_scores */
    grow_list(state, 12, 8, n);
    grow_list(state, 15, 1, n);
    grow_list(state, 16, 1, n);
    grow_list(state, 21, 8, n);
    printf("validators: %llu (from %llu), state buffer: %llu MB\n", (unsigned long long)n, (unsigned long long)have,
           (unsigned long long)(need >> 20));
    uint64_t ssize = 1ull << 28, result = 0;
    uint8_t *scratch = buffer(ssize);
    uint8_t root[32];
    double t0 = now_s();
    uint8_t *copy = buffer(need);
    wr64(copy, need);
    uint64_t keep[8] = {64, 64, 4, 9000, 64, 64, 4, 4096}; /* room as the node gives its copies */
    CALL(LF(beacon_state_copy_size), state, keep, &need);
    free(copy);
    copy = buffer(need);
    wr64(copy, need);
    if (CALL(LF(beacon_state_copy), state, keep, copy) != 0) fprintf(stderr, "copy status\n");
    double t1 = now_s();
    printf("state copy: %.3f s\n", t1 - t0);
    root_of("BeaconState", state, root, &why);
    double t2 = now_s();
    printf("hash_tree_root: %.3f s%s\n", t2 - t1, why ? " (failed)" : "");
    /* lantern_state_root with a StateCache for n validators: empty, filled, then after one slot. */
    uint64_t csize = 0;
    CALL(LF(state_cache_size), &n, &csize);
    uint8_t *cache = buffer(csize);
    wr64(cache, csize);
    CALL(LF(state_cache_init), &n, cache);
    uint8_t got[32];
    const char *rwhy = NULL;
    double c0 = now_s();
    wr64(scratch, ssize);
    if (CALL(LF(state_root), state, cache, scratch, got) != 0 || memcmp(got, root, 32)) rwhy = "differs";
    double c1 = now_s();
    wr64(scratch, ssize);
    if (CALL(LF(state_root), state, cache, scratch, got) != 0 || memcmp(got, root, 32)) rwhy = "differs";
    double c2 = now_s();
    printf("state cache: %llu MB; state_root empty %.3f s, unchanged %.3f s%s\n", (unsigned long long)(csize >> 20), c1 - c0,
           c2 - c1, rwhy ? " (root differs)" : "");
    {   /* get_beacon_committee of the state's slot, index 0: with no cache, then a CommitteeCache empty and filled */
        uint64_t ccsize = 0, cslot = rd64(state + 48), cidx = 0; /* NODE_STATE_SLOT 48 */
        CALL(LF(committee_cache_size), &n, &ccsize);
        uint8_t *ccache = buffer(ccsize), *committee = buffer(24 + 8 * 65536);
        wr64(ccache, ccsize);
        CALL(LF(committee_cache_init), &n, ccache);
        double k[4];
        uint64_t ks[3];
        k[0] = now_s();
        for (int r = 0; r < 3; r++) {
            wr64(committee, 24 + 8 * 65536);
            wr64(scratch, ssize);
            ks[r] = CALL(LF(get_beacon_committee), state, &cslot, &cidx, r ? ccache : NULL, scratch, committee);
            k[r + 1] = now_s();
        }
        printf("get_beacon_committee: %llu members; no cache %.4f s, cache empty %.4f s, filled %.6f s (status %llu %llu %llu)\n",
               (unsigned long long)rd64(committee + 16), k[1] - k[0], k[2] - k[1], k[3] - k[2], (unsigned long long)ks[0],
               (unsigned long long)ks[1], (unsigned long long)ks[2]);
        free(ccache);
        free(committee);
    }
    uint64_t pksize = 0;
    CALL(LF(pubkey_cache_size), &n, &pksize);
    uint8_t *pubkeys = buffer(pksize);
    wr64(pubkeys, pksize);
    CALL(LF(pubkey_cache_init), &n, pubkeys);
    time_indexed(state, n, 488, pubkeys, scratch, ssize);    /* one committee at 1000000 validators */
    time_indexed(state, n, 31232, pubkeys, scratch, ssize);  /* 64 of them: an electra aggregate of every committee of a slot */
    wr64(config + CONFIG_STATE_CACHE, (uint64_t)(uintptr_t)cache);
    {
        uint8_t *one = buffer(need);
        wr64(one, need);
        CALL(LF(beacon_state_copy), state, keep, one);
        uint64_t s1 = rd64(one + 48) + 1, r1 = 0; /* NODE_STATE_SLOT 48 */
        if ((s1 % SLOTS_PER_EPOCH_RUNNER) == 0) { /* past the epoch's end first, untimed */
            s1++;
            wr64(scratch, ssize);
            CALL(LF(process_slots), one, &s1, config, scratch, &r1);
            s1++;
        }
        wr64(scratch, ssize);
        double a = now_s();
        uint64_t st1 = CALL(LF(process_slots), one, &s1, config, scratch, &r1);
        printf("process_slots of one slot inside an epoch, with the cache: %.3f s (status %llu, result %llu)\n",
               now_s() - a, (unsigned long long)st1, (unsigned long long)r1);
        free(one);
    }
    wr64(config + CONFIG_STATE_CACHE, 0);
    t2 = now_s();
    for (int k = 0; EPOCH[k].handler; k++) { /* each epoch step alone, on a copy */
        uint8_t *one = buffer(need);
        wr64(one, need);
        CALL(LF(beacon_state_copy), state, keep, one);
        wr64(scratch, ssize);
        double a = now_s();
        uint64_t r1 = 0, s1 = checked_call(EPOCH[k].name, (uint64_t)(uintptr_t)EPOCH[k].fn, (const void *const[]){one, config, scratch, &r1}, 4);
        printf("  %-40s %8.3f s (status %llu, result %llu)\n", EPOCH[k].name, now_s() - a, (unsigned long long)s1, (unsigned long long)r1);
        free(one);
    }
    t2 = now_s();
    wr64(scratch, ssize);
    uint64_t st = CALL(LF(process_epoch), state, config, scratch, &result);
    double t3 = now_s();
    printf("process_epoch: %.3f s (status %llu, result %llu)\n", t3 - t2, (unsigned long long)st, (unsigned long long)result);
    uint64_t slot = rd64(copy + 48) + SLOTS_PER_EPOCH_RUNNER; /* NODE_STATE_SLOT 48: one epoch later */
    slot -= slot % SLOTS_PER_EPOCH_RUNNER;
    wr64(config + CONFIG_STATE_CACHE, (uint64_t)(uintptr_t)cache);
    wr64(scratch, ssize);
    t3 = now_s();
    st = CALL(LF(process_slots), copy, &slot, config, scratch, &result);
    double t4 = now_s();
    printf("process_slots to the next epoch, with the cache: %.3f s (status %llu, result %llu)\n", t4 - t3,
           (unsigned long long)st, (unsigned long long)result);
    free(state);
    time_block(copy, keep, n, have, cache, pubkeys, scratch, ssize);
    return 0;
}
