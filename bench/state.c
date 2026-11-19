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
    return 0;
}
