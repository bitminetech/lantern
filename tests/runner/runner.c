/*
 * lantern vector runner. Test code: lantern itself is assembly.
 *
 * Usage: runner-<preset> VECTOR_DIR FILE ...
 *
 * Reads the case files that tests/generator/ writes (format in its README),
 * calls lantern for every case and compares the results. Files of the other
 * preset, and files of a kind the runner does not know, are skipped. It
 * exits with status 0 only when every case of every file it runs passes.
 *
 * Buffers are allocated at the size each function asks for, with guard bytes
 * after them, and output buffers start filled with 0xA5, so a write out of
 * bounds or a read of old output contents shows up as a failure.
 *
 * Every lantern call goes through abi_call (tests/runner/abi_<ISA>.s), which
 * checks the registers the ABI says the callee keeps, and measures the stack.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) && defined(__x86_64__)
#define ABI __attribute__((sysv_abi))
#else
#define ABI
#endif

#ifndef PRESET
#error "build with -DPRESET=\"mainnet\" or -DPRESET=\"minimal\""
#endif

/* ---------------------------------------------------------------- Interfaces */

/* asm-ssz, at the pin in platform/deps.sh. */
ABI uint64_t ssz_serialize(const void *type, const void *value, void *scratch, void *serialized);
ABI uint64_t ssz_serialize_size(const void *type, const void *value, void *scratch, void *size);
ABI uint64_t ssz_deserialize(const void *type, const void *serialized, void *scratch, void *value);
ABI uint64_t ssz_deserialize_size(const void *type, const void *serialized, void *scratch, void *size);
ABI uint64_t ssz_hash_tree_root(const void *type, const void *value, void *scratch, void *root);

/* lantern: include/descriptors.inc. */
extern const uint8_t lantern_types[];

/* lantern functions: docs/reference/. */
ABI uint64_t lantern_beacon_state_copy_size(const void *state, const void *room, void *size);
ABI uint64_t lantern_beacon_state_copy(const void *state, const void *room, void *out);

ABI uint64_t lantern_compute_shuffled_permutation(const void *index_count, const void *seed, void *scratch, void *out);
ABI uint64_t lantern_compute_shuffled_index(const void *index, const void *index_count, const void *seed, void *scratch,
                                            void *out);
ABI uint64_t lantern_get_flag_index_deltas(const void *state, const void *flag_index, void *scratch, void *rewards,
                                           void *penalties);
ABI uint64_t lantern_get_inactivity_penalty_deltas(const void *state, const void *config, void *scratch, void *rewards,
                                                   void *penalties);

/* An operation: (state, operation, config, scratch, result). */
typedef ABI uint64_t (*op_fn)(void *state, const void *op, const void *config, void *scratch, void *result);
ABI uint64_t lantern_process_execution_payload(void *state, const void *body, const void *execution_valid,
                                               const void *config, void *scratch, void *result);
#define OP_FN(handler, fn, part, type) ABI uint64_t lantern_process_##fn(void *, const void *, const void *, void *, void *);
#define OPERATIONS(X)                                                                                          \
    X(block_header, block_header, block, BeaconBlock)                                                          \
    X(withdrawals, withdrawals, execution_payload, ExecutionPayload)                                           \
    X(voluntary_exit, voluntary_exit, voluntary_exit, SignedVoluntaryExit)                                     \
    X(bls_to_execution_change, bls_to_execution_change, address_change, SignedBLSToExecutionChange)           \
    X(deposit_request, deposit_request, deposit_request, DepositRequest)                                       \
    X(withdrawal_request, withdrawal_request, withdrawal_request, WithdrawalRequest)                           \
    X(consolidation_request, consolidation_request, consolidation_request, ConsolidationRequest)               \
    X(proposer_slashing, proposer_slashing, proposer_slashing, ProposerSlashing)                               \
    X(attester_slashing, attester_slashing, attester_slashing, AttesterSlashing)                               \
    X(attestation, attestation, attestation, Attestation)                                                      \
    X(sync_aggregate, sync_aggregate, sync_aggregate, SyncAggregate)
OPERATIONS(OP_FN)

ABI uint64_t lantern_process_slots(void *state, const void *slot, const void *config, void *scratch, void *result);
ABI uint64_t lantern_state_transition(void *state, const void *signed_block, const void *options, const void *config,
                                      void *scratch, void *result);

/* Fork choice: docs/reference/fork-choice.md. */
ABI uint64_t lantern_get_forkchoice_store(const void *anchor_state, const void *anchor_block, const void *config,
                                          const void *room, void *scratch, void *store);
ABI uint64_t lantern_store_size(const void *room, void *size);
ABI uint64_t lantern_store_copy(const void *store, const void *room, void *out);
ABI uint64_t lantern_store_justified_checkpoint_state(void *store, const void *state);
ABI uint64_t lantern_get_current_slot(const void *store, void *out);
ABI uint64_t lantern_on_tick(void *store, const void *time_ms, void *result);
ABI uint64_t lantern_get_head(const void *store, void *scratch, void *out);
ABI uint64_t lantern_get_filtered_node_tree(const void *store, void *scratch, void *out);
ABI uint64_t lantern_get_weight(const void *store, const void *node, void *out);
ABI uint64_t lantern_on_block(void *store, const void *signed_block, void *state, const void *options, void *scratch,
                              void *result);
ABI uint64_t lantern_validate_on_attestation(const void *store, const void *attestation, const void *is_from_block);
ABI uint64_t lantern_store_target_checkpoint_state(void *state, const void *target, const void *config, void *scratch,
                                                   void *result);
ABI uint64_t lantern_on_attestation(void *store, const void *attestation, const void *is_from_block,
                                    const void *target_state, void *scratch, void *result);
ABI uint64_t lantern_on_attester_slashing(void *store, const void *attester_slashing, const void *state, void *scratch,
                                          void *result);
ABI uint64_t lantern_get_proposer_head(const void *store, const void *head, const void *slot, const void *head_state,
                                       void *scratch, void *out);
ABI uint64_t lantern_is_data_available(const void *sidecars, const void *settings, const void *config, void *scratch,
                                       void *out);

/* asm-crypto, at the pin in platform/deps.sh. */
ABI uint64_t crypto_kzg_trusted_setup_of_bytes(const void *g1_lagrange, const void *g1_monomial,
                                               const void *g2_monomial, void *settings);

/* An epoch processing function: (state, config, scratch, result). */
typedef ABI uint64_t (*epoch_fn)(void *state, const void *config, void *scratch, void *result);
#define EPOCH_FN(name) ABI uint64_t lantern_process_##name(void *, const void *, void *, void *);
#define EPOCH_FUNCTIONS(X)                                                                                     \
    X(justification_and_finalization)                                                                          \
    X(inactivity_updates)                                                                                      \
    X(rewards_and_penalties)                                                                                   \
    X(registry_updates)                                                                                        \
    X(slashings)                                                                                               \
    X(eth1_data_reset)                                                                                         \
    X(pending_consolidations)                                                                                  \
    X(effective_balance_updates)                                                                               \
    X(slashings_reset)                                                                                         \
    X(randao_mixes_reset)                                                                                      \
    X(historical_summaries_update)                                                                             \
    X(participation_flag_updates)                                                                              \
    X(pending_deposits)                                                                                        \
    X(sync_committee_updates)                                                                                  \
    X(proposer_lookahead)                                                                                      \
    X(epoch)
EPOCH_FUNCTIONS(EPOCH_FN)

/* ---------------------------------------------------------------- ABI check */

#define STACK_CAP 65536 /* README: stack per call */
#define PAINT_BYTES (STACK_CAP + 4096)

typedef struct {
    uint64_t fn, arg[5], paint, status, fault, stack, scratch[4], arg5;
} abi_ctx;
ABI void abi_call(abi_ctx *ctx);

typedef struct {
    const char *name;
    uint64_t peak, fault, calls;
} fn_stats;

#define MAX_FUNCTIONS 512
static fn_stats stats[MAX_FUNCTIONS];
static int stats_count;

static fn_stats *stats_for(const char *name) {
    for (int i = 0; i < stats_count; i++)
        if (!strcmp(stats[i].name, name)) return &stats[i];
    if (stats_count == MAX_FUNCTIONS) {
        fprintf(stderr, "too many functions\n");
        exit(2);
    }
    stats[stats_count].name = name;
    return &stats[stats_count++];
}

/* Call lantern function f, named name, with up to 6 pointer arguments. */
__attribute__((unused)) static uint64_t checked_call(const char *name, uint64_t f, const void *const *args, size_t n) {
    abi_ctx c;
    memset(&c, 0, sizeof c);
    c.fn = f;
    for (size_t i = 0; i < n && i < 5; i++) c.arg[i] = (uint64_t)(uintptr_t)args[i];
    if (n > 5) c.arg5 = (uint64_t)(uintptr_t)args[5];
    c.paint = PAINT_BYTES;
    abi_call(&c);
    fn_stats *s = stats_for(name);
    if (c.stack > s->peak) s->peak = c.stack;
    s->fault |= c.fault;
    s->calls++;
    return c.status;
}

#define CALL(f, ...)                                                                                           \
    checked_call(#f, (uint64_t)(uintptr_t)(f), (const void *const[]){__VA_ARGS__},                             \
                 sizeof((const void *const[]){__VA_ARGS__}) / sizeof(const void *))

/* ---------------------------------------------------------------- Bytes and buffers */

#define GUARD 64
#define FILL 0xA5

static uint64_t rd64(const uint8_t *p) {
    uint64_t v = 0;
    for (int i = 7; i >= 0; i--) v = (v << 8) | p[i];
    return v;
}

static void wr64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

static void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    return p;
}

/* A buffer of n bytes, filled, with GUARD guard bytes after it. */
static uint8_t *buffer(uint64_t n) {
    uint8_t *b = xmalloc((size_t)(n + GUARD));
    memset(b, FILL, (size_t)(n + GUARD));
    return b;
}

static int guard_ok(const uint8_t *b, uint64_t n) {
    for (uint64_t i = 0; i < GUARD; i++)
        if (b[n + i] != FILL) return 0;
    return 1;
}

/* ---------------------------------------------------------------- Case files */

enum { T_INT = 1, T_BYTES, T_STRING, T_BOOL, T_LIST, T_MAP, T_NULL, T_UINT256, T_NEG_INT };
typedef const uint8_t *tv; /* a tagged value: its tag byte, then its payload */

static tv tv_skip(tv v) {
    switch (*v) {
    case T_INT:
    case T_NEG_INT: return v + 9;
    case T_BYTES:
    case T_STRING: return v + 9 + rd64(v + 1);
    case T_BOOL: return v + 2;
    case T_NULL: return v + 1;
    case T_UINT256: return v + 33;
    case T_LIST: {
        uint64_t n = rd64(v + 1);
        tv p = v + 9;
        while (n--) p = tv_skip(p);
        return p;
    }
    case T_MAP: {
        uint64_t n = rd64(v + 1);
        tv p = v + 9;
        while (n--) p = tv_skip(p + 8 + rd64(p));
        return p;
    }
    default: fprintf(stderr, "bad tag %d\n", *v); exit(2);
    }
}

/* The value of key in map m, or NULL. */
static tv tv_get(tv m, const char *key) {
    if (!m || *m != T_MAP) return NULL;
    uint64_t n = rd64(m + 1), klen = strlen(key);
    tv p = m + 9;
    while (n--) {
        uint64_t len = rd64(p);
        if (len == klen && !memcmp(p + 8, key, klen)) return p + 8 + len;
        p = tv_skip(p + 8 + len);
    }
    return NULL;
}

static uint64_t tv_u64(tv v) {
    if (!v || *v != T_INT) {
        fprintf(stderr, "expected an integer\n");
        exit(2);
    }
    return rd64(v + 1);
}

static const uint8_t *tv_bytes(tv v, uint64_t *len) {
    if (!v || *v != T_BYTES) {
        fprintf(stderr, "expected bytes\n");
        exit(2);
    }
    *len = rd64(v + 1);
    return v + 9;
}

typedef struct {
    uint8_t *data;
    uint64_t size, count, at; /* at: offset of the next case */
} case_file;

static int read_file(const char *dir, const char *name, case_file *f) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE *fp = fopen(path, "rb");
    if (!fp) return 0;
    fseek(fp, 0, SEEK_END);
    long n = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    f->data = xmalloc((size_t)n);
    f->size = (uint64_t)n;
    if (fread(f->data, 1, (size_t)n, fp) != (size_t)n || n < 16 || memcmp(f->data, "LANTVEC1", 8)) {
        fprintf(stderr, "%s: not a case file\n", path);
        exit(2);
    }
    fclose(fp);
    f->count = rd64(f->data + 8);
    f->at = 16;
    return 1;
}

/* The next case: its name (not zero ended) and its parts map. */
static tv next_case(case_file *f, const char **name, uint64_t *name_len) {
    *name_len = rd64(f->data + f->at);
    *name = (const char *)(f->data + f->at + 8);
    tv parts = f->data + f->at + 8 + *name_len;
    f->at = (uint64_t)(tv_skip(parts) - f->data);
    return parts;
}

/* ---------------------------------------------------------------- lantern types */

typedef struct {
    const char *name;
    const uint8_t *desc;
} lantern_type;

/* The root type of lantern named name, or NULL. */
static const uint8_t *type_by_name(const char *name) {
    uint64_t n = rd64(lantern_types);
    for (uint64_t i = 0; i < n; i++) {
        const uint8_t *e = lantern_types + 8 + 16 * i;
        const char *tname = (const char *)(lantern_types - rd64(e + 8));
        if (!strcmp(tname, name)) return lantern_types - rd64(e);
    }
    return NULL;
}

static const uint8_t *node_of(const uint8_t *d, uint64_t i) { return d + rd64(d + 8) + 72 * i; }
static const uint8_t *field_of(const uint8_t *d, uint64_t i) { return d + rd64(d + 24) + 32 * i; }
static const uint8_t *root_node(const uint8_t *d) { return node_of(d, rd64(d + 40)); }

static uint64_t scratch_size(const uint8_t *d) { return rd64(root_node(d) + 64); }
static uint64_t ssz_size(const uint8_t *d) { return rd64(root_node(d) + 24); }

/*
 * Compare type node ia of descriptor a with node ib of descriptor b: every
 * number of the node, then the elements or fields, to any depth. Writes the
 * first difference to why.
 */
static int same_node(const uint8_t *a, uint64_t ia, const uint8_t *b, uint64_t ib, char *why, size_t whylen,
                     const char *path) {
    static const char *const names[] = {"kind", "length", "element", "ssz", "mem", "align", "fixed", "chunks", "scratch"};
    const uint8_t *na = node_of(a, ia), *nb = node_of(b, ib);
    for (int k = 0; k < 9; k++) {
        if (k == 2) continue;
        if (rd64(na + 8 * k) != rd64(nb + 8 * k)) {
            snprintf(why, whylen, "%s: %s %llu, expected %llu", path, names[k], (unsigned long long)rd64(na + 8 * k),
                     (unsigned long long)rd64(nb + 8 * k));
            return 0;
        }
    }
    uint64_t kind = rd64(na);
    char sub[512];
    if (kind == 7 || kind == 8) {
        snprintf(sub, sizeof sub, "%s[]", path);
        return same_node(a, rd64(na + 16), b, rd64(nb + 16), why, whylen, sub);
    }
    if (kind == 9) {
        for (uint64_t k = 0; k < rd64(na + 8); k++) {
            const uint8_t *fa = field_of(a, rd64(na + 16) + k), *fb = field_of(b, rd64(nb + 16) + k);
            snprintf(sub, sizeof sub, "%s.%llu", path, (unsigned long long)k);
            for (int j = 1; j < 4; j++)
                if (rd64(fa + 8 * j) != rd64(fb + 8 * j)) {
                    snprintf(why, whylen, "%s: field word %d is %llu, expected %llu", sub, j,
                             (unsigned long long)rd64(fa + 8 * j), (unsigned long long)rd64(fb + 8 * j));
                    return 0;
                }
            if (!same_node(a, rd64(fa), b, rd64(fb), why, whylen, sub)) return 0;
        }
    }
    return 1;
}

/* ---------------------------------------------------------------- Results */

static int failures, passes;

static void report(const char *file, const char *name, uint64_t name_len, int ok, const char *why) {
    if (ok) {
        passes++;
        return;
    }
    failures++;
    printf("FAIL %s %.*s: %s\n", file, (int)name_len, name, why ? why : "");
}

/* ---------------------------------------------------------------- Handlers */

/* The reference descriptor of every type that lantern also defines. */
static void run_descriptors(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name;
        uint64_t len;
        tv parts = next_case(f, &name, &len);
        char tname[256];
        snprintf(tname, sizeof tname, "%.*s", (int)len, name);
        const uint8_t *ours = type_by_name(tname);
        if (!ours) continue;
        uint64_t dlen;
        const uint8_t *ref = tv_bytes(tv_get(parts, "descriptor"), &dlen);
        char why[512] = "";
        int ok = same_node(ours, rd64(ours + 40), ref, rd64(ref + 40), why, sizeof why, tname);
        report(file, name, len, ok, why);
    }
}

/* A serialized value as asm-ssz takes it: size, offset 24, count, then the bytes. */
static uint8_t *serialized(const uint8_t *enc, uint64_t len, uint64_t *size) {
    *size = 24 + len;
    uint8_t *s = buffer(*size);
    wr64(s, *size);
    wr64(s + 8, 24);
    wr64(s + 16, len);
    memcpy(s + 24, enc, (size_t)len);
    return s;
}

static uint8_t *scratch_for(const uint8_t *desc, uint64_t *size) {
    *size = scratch_size(desc);
    uint8_t *s = buffer(*size);
    wr64(s, *size);
    return s;
}

/* Decode enc into a new value of type desc. Returns NULL with a reason on failure. */
static uint8_t *decode(const uint8_t *desc, const uint8_t *enc, uint64_t len, uint64_t *vsize, const char **why) {
    uint64_t ssize, scsize, size = 0;
    uint8_t *ser = serialized(enc, len, &ssize), *scr = scratch_for(desc, &scsize), *value = NULL;
    if (ssz_deserialize_size(desc, ser, scr, &size) != 0) *why = "deserialize_size status";
    else {
        value = buffer(size);
        if (ssz_size(desc) == 0) wr64(value, size);
        if (ssz_deserialize(desc, ser, scr, value) != 0) *why = "deserialize status";
        else if (!guard_ok(value, size)) *why = "deserialize wrote out of bounds";
        else *vsize = size;
        if (*why) {
            free(value);
            value = NULL;
        }
    }
    free(ser);
    free(scr);
    return value;
}

/* ssz_static: decode, encode and root of one type, through lantern's descriptor. */
static void run_ssz_static(const char *file, const char *type_name, case_file *f) {
    const uint8_t *desc = type_by_name(type_name);
    if (!desc) {
        printf("SKIP %s: lantern has no type %s\n", file, type_name);
        return;
    }
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, elen, vsize = 0, scsize;
        tv parts = next_case(f, &name, &len);
        const uint8_t *enc = tv_bytes(tv_get(parts, "serialized"), &elen);
        const uint8_t *root = tv_bytes(tv_get(tv_get(parts, "roots"), "root"), &vsize);
        uint8_t *value = decode(desc, enc, elen, &vsize, &why);
        if (value) {
            uint8_t *scr = scratch_for(desc, &scsize), got[32 + GUARD];
            uint64_t need = 0;
            memset(got, FILL, sizeof got);
            if (ssz_serialize_size(desc, value, scr, &need) != 0 || need != 24 + elen) why = "serialize_size";
            else {
                uint8_t *out = buffer(need);
                wr64(out, need);
                if (ssz_serialize(desc, value, scr, out) != 0 || memcmp(out + 24, enc, (size_t)elen))
                    why = "serialize bytes";
                else if (ssz_hash_tree_root(desc, value, scr, got) != 0 || memcmp(got, root, 32))
                    why = "hash_tree_root";
                free(out);
            }
            free(scr);
            free(value);
        }
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Config */

/* include/lantern.inc: CONFIG_* offsets. Kind 0: a u64; kind 1: a 4-byte Version. */
static const struct {
    const char *name;
    uint64_t offset;
    int version;
} CONFIG_FIELDS[] = {
    {"GENESIS_FORK_VERSION", 0, 1},
    {"ALTAIR_FORK_VERSION", 8, 1},
    {"ALTAIR_FORK_EPOCH", 16, 0},
    {"BELLATRIX_FORK_VERSION", 24, 1},
    {"BELLATRIX_FORK_EPOCH", 32, 0},
    {"CAPELLA_FORK_VERSION", 40, 1},
    {"CAPELLA_FORK_EPOCH", 48, 0},
    {"DENEB_FORK_VERSION", 56, 1},
    {"DENEB_FORK_EPOCH", 64, 0},
    {"ELECTRA_FORK_VERSION", 72, 1},
    {"ELECTRA_FORK_EPOCH", 80, 0},
    {"FULU_FORK_VERSION", 88, 1},
    {"FULU_FORK_EPOCH", 96, 0},
    {"SLOT_DURATION_MS", 104, 0},
    {"MIN_VALIDATOR_WITHDRAWABILITY_DELAY", 112, 0},
    {"SHARD_COMMITTEE_PERIOD", 120, 0},
    {"EJECTION_BALANCE", 128, 0},
    {"MIN_PER_EPOCH_CHURN_LIMIT", 136, 0},
    {"CHURN_LIMIT_QUOTIENT", 144, 0},
    {"MAX_PER_EPOCH_ACTIVATION_CHURN_LIMIT", 152, 0},
    {"MIN_PER_EPOCH_CHURN_LIMIT_ELECTRA", 160, 0},
    {"MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT", 168, 0},
    {"INACTIVITY_SCORE_BIAS", 176, 0},
    {"INACTIVITY_SCORE_RECOVERY_RATE", 184, 0},
    {"MAX_BLOBS_PER_BLOCK_ELECTRA", 192, 0},
    {"PROPOSER_SCORE_BOOST", 200, 0},
    {"REORG_HEAD_WEIGHT_THRESHOLD", 208, 0},
    {"REORG_PARENT_WEIGHT_THRESHOLD", 216, 0},
    {"REORG_MAX_EPOCHS_SINCE_FINALIZATION", 224, 0},
    {"PROPOSER_REORG_CUTOFF_BPS", 232, 0},
    {"ATTESTATION_DUE_BPS", 240, 0},
    {"AGGREGATE_DUE_BPS", 248, 0},
    {"SYNC_MESSAGE_DUE_BPS", 256, 0},
    {"CONTRIBUTION_DUE_BPS", 264, 0},
    {"SAMPLES_PER_SLOT", 272, 0},
    {"NUMBER_OF_CUSTODY_GROUPS", 280, 0},
    {"CUSTODY_REQUIREMENT", 288, 0},
    {"DATA_COLUMN_SIDECAR_SUBNET_COUNT", 296, 0},
    {"MAX_REQUEST_BLOCKS_DENEB", 304, 0},
    {"MIN_EPOCHS_FOR_DATA_COLUMN_SIDECARS_REQUESTS", 312, 0},
    {"MAX_PAYLOAD_SIZE", 320, 0},
    {"MAXIMUM_GOSSIP_CLOCK_DISPARITY", 328, 0},
    {"SUBNETS_PER_NODE", 336, 0},
    {"EPOCHS_PER_SUBNET_SUBSCRIPTION", 344, 0},
    {"ATTESTATION_SUBNET_EXTRA_BITS", 352, 0},
    {"VALIDATOR_CUSTODY_REQUIREMENT", 360, 0},
    {"BALANCE_PER_ADDITIONAL_CUSTODY_GROUP", 368, 0},
    {"MIN_EPOCHS_FOR_BLOB_SIDECARS_REQUESTS", 376, 0},
};
#define CONFIG_BLOB_SCHEDULE_COUNT 384
#define CONFIG_BLOB_SCHEDULE 392
#define CONFIG_SIZE (392 + 16 * 32)

static uint8_t config[CONFIG_SIZE];

static void load_config(const char *dir) {
    case_file f;
    char name[64];
    snprintf(name, sizeof name, "%s-config.bin", PRESET);
    if (!read_file(dir, name, &f)) {
        fprintf(stderr, "%s/%s: missing\n", dir, name);
        exit(2);
    }
    const char *cname;
    uint64_t clen;
    tv map = next_case(&f, &cname, &clen);
    for (size_t i = 0; i < sizeof CONFIG_FIELDS / sizeof CONFIG_FIELDS[0]; i++) {
        tv v = tv_get(map, CONFIG_FIELDS[i].name);
        if (!v) {
            fprintf(stderr, "config: no %s\n", CONFIG_FIELDS[i].name);
            exit(2);
        }
        if (CONFIG_FIELDS[i].version) {
            /* YAML reads an unquoted 0x00000000 as a number: its 4 bytes, big endian. */
            uint8_t *dst = config + CONFIG_FIELDS[i].offset;
            memset(dst, 0, 8);
            if (*v == T_INT) {
                uint64_t n = tv_u64(v);
                for (int b = 0; b < 4; b++) dst[b] = (uint8_t)(n >> (24 - 8 * b));
            } else {
                uint64_t len;
                const uint8_t *b = tv_bytes(v, &len);
                memcpy(dst, b, len < 4 ? len : 4);
            }
        } else {
            wr64(config + CONFIG_FIELDS[i].offset, tv_u64(v));
        }
    }
    tv sched = tv_get(map, "BLOB_SCHEDULE");
    uint64_t n = sched && *sched == T_LIST ? rd64(sched + 1) : 0;
    if (n > 32) {
        fprintf(stderr, "config: BLOB_SCHEDULE has more than 32 entries\n");
        exit(2);
    }
    wr64(config + CONFIG_BLOB_SCHEDULE_COUNT, n);
    tv e = n ? sched + 9 : NULL;
    for (uint64_t i = 0; i < n; i++) {
        wr64(config + CONFIG_BLOB_SCHEDULE + 16 * i, tv_u64(tv_get(e, "EPOCH")));
        wr64(config + CONFIG_BLOB_SCHEDULE + 16 * i + 8, tv_u64(tv_get(e, "MAX_BLOBS_PER_BLOCK")));
        e = tv_skip(e);
    }
    free(f.data);
}

/* ---------------------------------------------------------------- States */

#define SCRATCH_BYTES (64u << 20)
static uint8_t *scratch_buf;

/* A fresh scratch for one call: filled, with its size set. */
static uint8_t *fresh_scratch(void) {
    memset(scratch_buf, FILL, SCRATCH_BYTES + GUARD);
    wr64(scratch_buf, SCRATCH_BYTES);
    return scratch_buf;
}

/* A state decoded from enc and copied with room in each list. NULL with a reason on failure. */
static uint8_t *load_state(const uint8_t *enc, uint64_t len, uint64_t *size, const char **why) {
    const uint8_t *desc = type_by_name("BeaconState");
    uint64_t vsize = 0;
    uint8_t *value = decode(desc, enc, len, &vsize, why);
    if (!value) return NULL;
    uint64_t room[6] = {64, 64, 4, 9000, 64, 64}, need = 0;
    CALL(lantern_beacon_state_copy_size, value, room, &need);
    uint8_t *state = buffer(need + 4096);
    wr64(state, need + 4096);
    if (CALL(lantern_beacon_state_copy, value, room, state) != 0) {
        *why = "lantern_beacon_state_copy status";
        free(state);
        state = NULL;
    } else if (!guard_ok(state, need + 4096)) {
        *why = "lantern_beacon_state_copy wrote out of bounds";
        free(state);
        state = NULL;
    }
    *size = need + 4096;
    free(value);
    return state;
}

/*
 * The resize step of ARCHITECTURE.md section 6: copy state into a new buffer
 * with each list's room times growth. The old buffer is freed.
 */
static uint8_t *regrow(uint8_t *state, uint64_t *size, uint64_t growth, const char **why) {
    uint64_t room[6] = {64 * growth, 2048 * growth, 4 * growth, 9000 * growth, 64 * growth, 64 * growth}, need = 0;
    CALL(lantern_beacon_state_copy_size, state, room, &need);
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(lantern_beacon_state_copy, state, room, out) != 0) {
        *why = "regrow: copy status";
        free(out);
        return state;
    }
    free(state);
    *size = need;
    return out;
}

/* Whether state encodes to the bytes want. */
static int state_equals(const uint8_t *state, const uint8_t *want, uint64_t len, const char **why) {
    const uint8_t *desc = type_by_name("BeaconState");
    uint64_t scsize, need = 0;
    uint8_t *scr = scratch_for(desc, &scsize);
    int ok = 0;
    if (ssz_serialize_size(desc, state, scr, &need) != 0) *why = "post state: serialize_size status";
    else {
        uint8_t *out = buffer(need);
        wr64(out, need);
        if (ssz_serialize(desc, state, scr, out) != 0) *why = "post state: serialize status";
        else if (need != 24 + len) *why = "post state: length differs";
        else if (memcmp(out + 24, want, (size_t)len)) *why = "post state: bytes differ";
        else ok = 1;
        free(out);
    }
    free(scr);
    return ok;
}

/* ---------------------------------------------------------------- Epoch processing */

static const struct {
    const char *handler, *name;
    epoch_fn fn;
} EPOCH[] = {
#define EPOCH_ENTRY(name) {#name, "lantern_process_" #name, lantern_process_##name},
    EPOCH_FUNCTIONS(EPOCH_ENTRY)
    {NULL, NULL, NULL}};

static void run_epoch(const char *file, const char *handler, case_file *f) {
    int k = 0;
    while (EPOCH[k].handler && strcmp(EPOCH[k].handler, handler)) k++;
    if (!EPOCH[k].handler) {
        printf("SKIP %s: lantern has no process_%s\n", file, handler);
        return;
    }
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        tv post = tv_get(parts, "post");
        uint8_t *state = load_state(pre, plen, &size, &why);
        if (state) {
            uint64_t result = 0xA5A5A5A5A5A5A5A5u;
            uint64_t st = checked_call(EPOCH[k].name, (uint64_t)(uintptr_t)EPOCH[k].fn,
                                       (const void *const[]){state, config, fresh_scratch(), &result}, 4);
            if (st != 0) why = "status not 0";
            else if (!guard_ok(state, size)) why = "wrote past the state";
            else if (!guard_ok(scratch_buf, SCRATCH_BYTES)) why = "wrote past the scratch";
            else if (post) {
                uint64_t qlen;
                const uint8_t *want = tv_bytes(post, &qlen);
                if (result != 0) why = "result not valid";
                else state_equals(state, want, qlen, &why);
            } else if (result == 0) why = "expected an invalid result";
            free(state);
        }
        /* The whole epoch, where the case has its states before and after. */
        tv pre_epoch = tv_get(parts, "pre_epoch");
        if (!why && pre_epoch) {
            uint64_t elen;
            const uint8_t *e = tv_bytes(pre_epoch, &elen);
            tv post_epoch = tv_get(parts, "post_epoch");
            state = load_state(e, elen, &size, &why);
            if (state) {
                uint64_t result = 0xA5A5A5A5A5A5A5A5u;
                uint64_t st = CALL(lantern_process_epoch, state, config, fresh_scratch(), &result);
                if (st != 0) why = "process_epoch: status not 0";
                else if (post_epoch) {
                    uint64_t qlen;
                    const uint8_t *want = tv_bytes(post_epoch, &qlen);
                    if (result != 0) why = "process_epoch: result not valid";
                    else if (!state_equals(state, want, qlen, &why)) why = why ? why : "process_epoch: post state";
                } else if (result == 0) why = "process_epoch: expected an invalid result";
                free(state);
            }
        }
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Operations */

static const struct {
    const char *handler, *name, *part, *type;
    op_fn fn;
} OPS[] = {
#define OP_ENTRY(handler, fn, part, type) {#handler, "lantern_process_" #fn, #part, #type, lantern_process_##fn},
    OPERATIONS(OP_ENTRY)
    {NULL, NULL, NULL, NULL, NULL}};

/* The bls_setting of a case: 0 when it has none. */
static uint64_t bls_setting(tv parts) {
    tv v = tv_get(tv_get(parts, "meta"), "bls_setting");
    return v ? tv_u64(v) : 0;
}

/*
 * Whether this runner skips a case. bls_setting 2 cases were made with
 * signature checks off: runner-<preset> skips them, and runner-<preset>-bls-off
 * (built with BLS_OFF and tests/runner/bls_off.c) runs only them.
 */
#ifdef BLS_OFF
static const int bls_off = 1;
#else
static const int bls_off = 0;
#endif
static int skipped;
static int skip_case(tv parts) {
#ifdef BLS_OFF
    int skip = bls_setting(parts) != 2;
#else
    int skip = bls_setting(parts) == 2;
#endif
    skipped += skip;
    return skip;
}

static void run_operations(const char *file, const char *handler, case_file *f) {
    int k = 0, payload = !strcmp(handler, "execution_payload");
    while (OPS[k].handler && strcmp(OPS[k].handler, handler)) k++;
    if (!payload && !OPS[k].handler) {
        printf("SKIP %s: lantern has no handler %s\n", file, handler);
        return;
    }
    const char *part = payload ? "body" : OPS[k].part, *type = payload ? "BeaconBlockBody" : OPS[k].type;
    const uint8_t *desc = type_by_name(type);
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, olen, size, vsize;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        const uint8_t *enc = tv_bytes(tv_get(parts, part), &olen);
        tv post = tv_get(parts, "post");
        uint8_t *state = load_state(pre, plen, &size, &why), *op = NULL;
        if (state) op = decode(desc, enc, olen, &vsize, &why);
        if (state && op) {
            uint64_t result = 0xA5A5A5A5A5A5A5A5u, st;
            if (payload) {
                tv ex = tv_get(tv_get(parts, "execution"), "execution_valid");
                uint64_t valid = ex && *ex == T_BOOL ? ex[1] : 1;
                st = CALL(lantern_process_execution_payload, state, op, &valid, config, fresh_scratch(), &result);
            } else {
                st = checked_call(OPS[k].name, (uint64_t)(uintptr_t)OPS[k].fn,
                                  (const void *const[]){state, op, config, fresh_scratch(), &result}, 5);
            }
            if (st != 0) why = "status not 0";
            else if (!guard_ok(state, size)) why = "wrote past the state";
            else if (!guard_ok(scratch_buf, SCRATCH_BYTES)) why = "wrote past the scratch";
            else if (post) {
                uint64_t qlen;
                const uint8_t *want = tv_bytes(post, &qlen);
                if (result != 0) {
                    static char msg[64];
                    snprintf(msg, sizeof msg, "result %llu, expected valid", (unsigned long long)result);
                    why = msg;
                } else state_equals(state, want, qlen, &why);
            } else if (result == 0) why = "expected an invalid result";
        }
        free(op);
        free(state);
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Sanity, finality, random */

/* sanity/slots: process_slots by the case's slot count. */
static void run_slots(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        uint8_t *state = load_state(pre, plen, &size, &why);
        if (state) {
            const uint8_t *desc = type_by_name("BeaconState");
            uint64_t slot_off = 0;
            /* BeaconState.slot: the u64 after genesis_time and genesis_validators_root. */
            (void)desc;
            slot_off = 8 + 8 + 32;
            uint64_t slot = rd64(state + slot_off) + tv_u64(tv_get(parts, "slots")), result = 1, st;
            uint8_t *before = buffer(size);
            for (uint64_t growth = 2;; growth *= 2) {
                memcpy(before, state, (size_t)size);
                st = CALL(lantern_process_slots, state, &slot, config, fresh_scratch(), &result);
                if (st != 1 || growth > 1024) break;
                if (memcmp(before, state, (size_t)size)) {
                    why = "BUFFER_TOO_SMALL changed the state";
                    break;
                }
                state = regrow(state, &size, growth, &why);
                free(before);
                before = buffer(size);
            }
            free(before);
            uint64_t qlen;
            const uint8_t *want = tv_bytes(tv_get(parts, "post"), &qlen);
            if (why) {
            } else if (st != 0) why = "status not 0";
            else if (result != 0) why = "result not valid";
            else state_equals(state, want, qlen, &why);
            free(state);
        }
        report(file, name, len, why == NULL, why);
    }
}

/* sanity/blocks, finality, random: state_transition of each block in turn. */
static void run_blocks(const char *file, case_file *f) {
    const uint8_t *desc = type_by_name("SignedBeaconBlock");
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        tv post = tv_get(parts, "post");
        uint64_t blocks = tv_u64(tv_get(tv_get(parts, "meta"), "blocks_count"));
        uint8_t *state = load_state(pre, plen, &size, &why);
        int invalid = 0;
        for (uint64_t b = 0; state && !why && !invalid && b < blocks; b++) {
            char key[32];
            snprintf(key, sizeof key, "blocks_%llu", (unsigned long long)b);
            uint64_t blen, vsize;
            const uint8_t *enc = tv_bytes(tv_get(parts, key), &blen);
            uint8_t *block = decode(desc, enc, blen, &vsize, &why);
            if (!block) break;
            uint64_t options[2] = {1, 1}, result = 0xA5A5A5A5A5A5A5A5u, st;
            for (uint64_t growth = 2;; growth *= 2) {
                st = CALL(lantern_state_transition, state, block, options, config, fresh_scratch(), &result);
                if (st != 1 || growth > 1024) break;
                state = regrow(state, &size, growth, &why);
            }
            if (st != 0) {
                static char msg[64];
                snprintf(msg, sizeof msg, "block %llu: status %llu", (unsigned long long)b, (unsigned long long)st);
                why = msg;
            } else if (result != 0) {
                invalid = 1;
                if (post) {
                    static char msg[64];
                    snprintf(msg, sizeof msg, "block %llu: result %llu", (unsigned long long)b, (unsigned long long)result);
                    why = msg;
                }
            }
            free(block);
        }
        if (state && !why) {
            if (post) {
                uint64_t qlen;
                const uint8_t *want = tv_bytes(post, &qlen);
                state_equals(state, want, qlen, &why);
            } else if (!invalid) why = "expected an invalid block";
        }
        free(state);
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Shuffling */

static void run_shuffling(const char *file, case_file *f) {
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, slen;
        tv m = tv_get(next_case(f, &name, &len), "mapping");
        const uint8_t *seed = tv_bytes(tv_get(m, "seed"), &slen);
        uint64_t count = tv_u64(tv_get(m, "count"));
        tv mapping = tv_get(m, "mapping");
        if (count > 0) {
            uint64_t osize = 24 + 8 * count;
            uint8_t *out = buffer(osize);
            wr64(out, osize);
            if (CALL(lantern_compute_shuffled_permutation, &count, seed, fresh_scratch(), out) != 0) why = "status";
            else if (!guard_ok(out, osize)) why = "wrote past out";
            else if (rd64(out + 16) != count) why = "count";
            else {
                tv e = mapping + 9;
                for (uint64_t k = 0; k < count && !why; k++, e = tv_skip(e))
                    if (rd64(out + 24 + 8 * k) != tv_u64(e)) why = "permutation differs";
            }
            /* compute_shuffled_index of the first and last index */
            uint64_t idx[2] = {0, count - 1};
            for (int k = 0; k < 2 && !why; k++) {
                uint64_t got = 0;
                if (CALL(lantern_compute_shuffled_index, &idx[k], &count, seed, fresh_scratch(), &got) != 0)
                    why = "shuffled_index status";
                else if (got != rd64(out + 24 + 8 * idx[k])) why = "shuffled_index differs";
            }
            uint64_t bad = count;
            if (!why && CALL(lantern_compute_shuffled_index, &bad, &count, seed, fresh_scratch(), &bad) != 5)
                why = "shuffled_index: index == count not rejected";
            free(out);
        }
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Rewards */

/* Whether the IndexList pair (rewards, penalties) equals the SSZ Deltas in want. */
static int deltas_equal(const uint8_t *rewards, const uint8_t *penalties, tv want) {
    uint64_t wlen;
    const uint8_t *w = tv_bytes(want, &wlen);
    if (wlen < 8) return 0;
    uint64_t o1 = w[0] | (uint64_t)w[1] << 8 | (uint64_t)w[2] << 16 | (uint64_t)w[3] << 24;
    uint64_t o2 = w[4] | (uint64_t)w[5] << 8 | (uint64_t)w[6] << 16 | (uint64_t)w[7] << 24;
    if (o1 != 8 || o2 < o1 || o2 > wlen) return 0;
    if (rd64(rewards + 16) * 8 != o2 - o1 || rd64(penalties + 16) * 8 != wlen - o2) return 0;
    return !memcmp(rewards + 24, w + o1, (size_t)(o2 - o1)) && !memcmp(penalties + 24, w + o2, (size_t)(wlen - o2));
}

static void run_rewards(const char *file, case_file *f) {
    static const char *const names[4] = {"source_deltas", "target_deltas", "head_deltas", "inactivity_penalty_deltas"};
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, plen, size;
        tv parts = next_case(f, &name, &len);
        const uint8_t *pre = tv_bytes(tv_get(parts, "pre"), &plen);
        uint8_t *state = load_state(pre, plen, &size, &why);
        if (state) {
            uint64_t lsize = 24 + 8 * 4096 * 64;
            uint8_t *rw = buffer(lsize), *pn = buffer(lsize);
            for (uint64_t flag = 0; flag < 4 && !why; flag++) {
                wr64(rw, lsize);
                wr64(pn, lsize);
                uint64_t st = flag < 3 ? CALL(lantern_get_flag_index_deltas, state, &flag, fresh_scratch(), rw, pn)
                                       : CALL(lantern_get_inactivity_penalty_deltas, state, config, fresh_scratch(), rw, pn);
                if (st != 0) why = "status not 0";
                else if (!deltas_equal(rw, pn, tv_get(parts, names[flag]))) why = names[flag];
            }
            free(rw);
            free(pn);
            free(state);
        }
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Fork choice */

/*
 * The fork choice tests: tests/formats/fork_choice/README.md of the spec. The
 * runner plays the node: it keeps store.block_states and store.checkpoint_states
 * (docs/reference/fork-choice.md, Common rules), grows the store and the states
 * when lantern asks for room, and gives the justified checkpoint state when
 * lantern asks for it.
 */

/* include/lantern.inc: Store, BlockNode and status codes. */
#define STORE_TIME_MS 8
#define STORE_GENESIS_TIME_MS 16
#define STORE_JUSTIFIED 24
#define STORE_FINALIZED 64
#define STORE_BOOST_ROOT 184
#define STORE_BLOCKS 264
#define STORE_VALIDATORS 280
#define NODE_BYTES 176
#define NODE_SLOT 64
#define NODE_PARENT 80
#define LANTERN_NEED_JUSTIFIED_STATE 41
#define KZG_SETTINGS_BYTES 1198368

static uint8_t *kzg_settings;

/* Decode the trusted setup of <preset>-kzg_setup.bin into kzg_settings, once. */
static void load_kzg_settings(const char *dir) {
    if (kzg_settings) return;
    case_file f;
    char name[64];
    snprintf(name, sizeof name, "%s-kzg_setup.bin", PRESET);
    if (!read_file(dir, name, &f)) {
        fprintf(stderr, "%s/%s: missing\n", dir, name);
        exit(2);
    }
    const char *cname;
    uint64_t clen, len[3], size[3];
    tv parts = next_case(&f, &cname, &clen);
    static const char *const keys[3] = {"g1_lagrange", "g1_monomial", "g2_monomial"};
    uint8_t *lists[3];
    for (int k = 0; k < 3; k++) {
        const uint8_t *b = tv_bytes(tv_get(parts, keys[k]), &len[k]);
        lists[k] = serialized(b, len[k], &size[k]);
    }
    kzg_settings = buffer(KZG_SETTINGS_BYTES);
    if (CALL(crypto_kzg_trusted_setup_of_bytes, lists[0], lists[1], lists[2], kzg_settings) != 0) {
        fprintf(stderr, "kzg setup: status not 0\n");
        exit(2);
    }
    for (int k = 0; k < 3; k++) free(lists[k]);
    free(f.data);
}

/* The mem offset of field i of the container type named name. */
static uint64_t field_offset(const char *name, uint64_t i) {
    const uint8_t *d = type_by_name(name);
    return rd64(field_of(d, rd64(root_node(d) + 16) + i) + 8);
}

/* The value at a PartRef with count 1: a nested value of a container. */
static const uint8_t *nested(const uint8_t *value, uint64_t ref) { return value + rd64(value + ref); }

typedef struct {
    uint8_t root[32];
    uint64_t epoch; /* checkpoint states only */
    uint8_t *state;
    uint64_t size;
} kept_state;

typedef struct {
    uint8_t *store;
    uint64_t size;
    kept_state *blocks, *checkpoints;
    size_t nblocks, ncheckpoints;
    uint8_t *anchor;  /* a valid state to pass where on_block reads none */
    uint64_t anchor_size;
    int compliance;   /* the compliance runner's rules: invalid operations inside a valid block are ignored */
} fc_node;

static uint8_t *copy_of(const uint8_t *b, uint64_t size) {
    uint8_t *c = buffer(size);
    memcpy(c, b, (size_t)size);
    return c;
}

static kept_state *find_kept(kept_state *v, size_t n, const uint8_t *root, uint64_t epoch, int with_epoch) {
    for (size_t i = 0; i < n; i++)
        if (!memcmp(v[i].root, root, 32) && (!with_epoch || v[i].epoch == epoch)) return &v[i];
    return NULL;
}

static void keep(kept_state **v, size_t *n, const uint8_t *root, uint64_t epoch, uint8_t *state, uint64_t size) {
    *v = realloc(*v, (*n + 1) * sizeof **v);
    if (!*v) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    memcpy((*v)[*n].root, root, 32);
    (*v)[*n].epoch = epoch;
    (*v)[*n].state = state;
    (*v)[*n].size = size;
    (*n)++;
}

/* The resize step for the store: copy it with twice the capacity of each part. */
static uint64_t node_capacity(const uint8_t *store);
static void grow_store(fc_node *n, const char **why) {
    uint64_t room[2] = {2 * node_capacity(n->store), 2 * rd64(n->store + STORE_VALIDATORS + 8)}, need = 0;
    if (CALL(lantern_store_size, room, &need) != 0) {
        *why = "lantern_store_size status";
        return;
    }
    uint8_t *out = buffer(need);
    wr64(out, need);
    if (CALL(lantern_store_copy, n->store, room, out) != 0) {
        *why = "lantern_store_copy status";
        free(out);
        return;
    }
    if (!guard_ok(out, need)) *why = "lantern_store_copy wrote out of bounds";
    free(n->store);
    n->store = out;
    n->size = need;
}

/* store.checkpoint_states[checkpoint at cp], made by store_target_checkpoint_state when missing. */
static kept_state *checkpoint_state(fc_node *n, const uint8_t *cp, const char **why) {
    uint64_t epoch = rd64(cp);
    kept_state *k = find_kept(n->checkpoints, n->ncheckpoints, cp + 8, epoch, 1);
    if (k) return k;
    kept_state *base = find_kept(n->blocks, n->nblocks, cp + 8, 0, 0);
    if (!base) {
        *why = "no block state for a checkpoint";
        return NULL;
    }
    uint64_t size = base->size, result = 1, st = 1;
    uint8_t *state = copy_of(base->state, size);
    for (uint64_t growth = 2; growth <= 1024; growth *= 2) {
        st = CALL(lantern_store_target_checkpoint_state, state, cp, config, fresh_scratch(), &result);
        if (st != 1) break;
        state = regrow(state, &size, growth, why);
    }
    if (st != 0 || result != 0) {
        *why = "store_target_checkpoint_state failed";
        free(state);
        return NULL;
    }
    keep(&n->checkpoints, &n->ncheckpoints, cp + 8, epoch, state, size);
    return &n->checkpoints[n->ncheckpoints - 1];
}

/*
 * Call a fork choice function again while it asks for the justified checkpoint
 * state or for room in the store. Returns its last status.
 */
/*
 * Call a fork choice function again while it asks for the justified checkpoint
 * state or for room. A non-zero status must leave the store, and the buffer
 * extra of extra_size bytes (or NULL), byte for byte unchanged. Returns the
 * last status.
 */
#define FC_RETRY(n, why, expr, on_small, extra, extra_size)                                                    \
    ({                                                                                                         \
        uint64_t st_ = 0;                                                                                      \
        for (int try_ = 0; try_ < 32 && !*(why); try_++) {                                                     \
            uint8_t *snap_ = copy_of((n)->store, (n)->size), *xsnap_ = (extra) ? copy_of((extra), (extra_size)) : NULL; \
            st_ = (expr);                                                                                      \
            if ((st_ == 1 || st_ == LANTERN_NEED_JUSTIFIED_STATE) &&                                           \
                (memcmp(snap_, (n)->store, (size_t)(n)->size) ||                                               \
                 ((extra) && memcmp(xsnap_, (extra), (size_t)(extra_size)))))                                  \
                *(why) = "a non-zero status changed a state";                                                  \
            free(snap_);                                                                                       \
            free(xsnap_);                                                                                      \
            if (*(why)) break;                                                                                 \
            if (st_ == LANTERN_NEED_JUSTIFIED_STATE) {                                                         \
                kept_state *k_ = checkpoint_state((n), (n)->store + STORE_JUSTIFIED, (why));                    \
                if (!k_) break;                                                                                \
                uint64_t s2_;                                                                                  \
                while ((s2_ = CALL(lantern_store_justified_checkpoint_state, (n)->store, k_->state)) == 1 &&       \
                       !*(why))                                                                                \
                    grow_store((n), (why));                                                                    \
                if (s2_ != 0) *(why) = "store_justified_checkpoint_state status";                              \
            } else if (st_ == 1) {                                                                             \
                on_small;                                                                                      \
            } else                                                                                             \
                break;                                                                                         \
        }                                                                                                      \
        st_;                                                                                                   \
    })

/* The capacity of the blocks part of the store. */
static uint64_t node_capacity(const uint8_t *store) {
    return (rd64(store + STORE_VALIDATORS) - rd64(store + STORE_BLOCKS)) / NODE_BYTES;
}

static uint64_t node_count(const fc_node *n) { return rd64(n->store + STORE_BLOCKS + 8); }
static const uint8_t *node_at(const fc_node *n, uint64_t i) {
    return n->store + rd64(n->store + STORE_BLOCKS) + NODE_BYTES * i;
}

/* on_attestation as the node runs it: validate, make the target state, then the call. */
static uint64_t fc_attestation(fc_node *n, const uint8_t *att, uint64_t from_block, const char **why) {
    uint64_t st = CALL(lantern_validate_on_attestation, n->store, att, &from_block);
    if (st != 0) return st;
    const uint8_t *target = att + field_offset("Attestation", 1) + field_offset("AttestationData", 4);
    kept_state *k = checkpoint_state(n, target, why);
    if (!k) return 0;
    uint64_t result = 0xA5A5A5A5A5A5A5A5u;
    st = FC_RETRY(n, why, CALL(lantern_on_attestation, n->store, att, &from_block, k->state, fresh_scratch(), &result),
                  grow_store(n, why), NULL, 0);
    if (st != 0) {
        *why = "on_attestation: status not 0";
        return 0;
    }
    return result;
}

static uint64_t fc_attester_slashing(fc_node *n, const uint8_t *slashing, const char **why) {
    kept_state *k = find_kept(n->blocks, n->nblocks, n->store + STORE_JUSTIFIED + 8, 0, 0);
    if (!k) {
        *why = "no state for the justified root";
        return 0;
    }
    uint64_t result = 0xA5A5A5A5A5A5A5A5u;
    uint64_t st = FC_RETRY(n, why, CALL(lantern_on_attester_slashing, n->store, slashing, k->state, fresh_scratch(), &result),
                           grow_store(n, why), NULL, 0);
    if (st != 0) {
        *why = "on_attester_slashing: status not 0";
        return 0;
    }
    return result;
}

/* The ColumnSidecars value of the column files named in list names. */
static uint8_t *column_sidecars(tv parts, tv names, uint64_t *size, const char **why) {
    const uint8_t *desc = type_by_name("DataColumnSidecar");
    uint64_t count = rd64(names + 1), total = 24;
    uint8_t **values = xmalloc(sizeof *values * (count ? count : 1));
    uint64_t *sizes = xmalloc(sizeof *sizes * (count ? count : 1));
    tv e = names + 9;
    for (uint64_t i = 0; i < count; i++, e = tv_skip(e)) {
        uint64_t elen;
        char key[128];
        snprintf(key, sizeof key, "%.*s", (int)rd64(e + 1), (const char *)(e + 9));
        const uint8_t *enc = tv_bytes(tv_get(parts, key), &elen);
        values[i] = decode(desc, enc, elen, &sizes[i], why);
        if (!values[i]) return NULL;
        total += (sizes[i] + 7) & ~(uint64_t)7;
    }
    uint8_t *list = buffer(total);
    wr64(list, total);
    wr64(list + 8, 24);
    wr64(list + 16, count);
    uint64_t at = 24;
    for (uint64_t i = 0; i < count; i++) {
        uint64_t sz = (sizes[i] + 7) & ~(uint64_t)7;
        memset(list + at, 0, (size_t)sz);
        memcpy(list + at, values[i], (size_t)sizes[i]);
        wr64(list + at, sz);
        at += sz;
        free(values[i]);
    }
    free(values);
    free(sizes);
    *size = total;
    return list;
}

/* An on_block step, then the block's attestations and attester slashings when it is valid. */
static void fc_block(fc_node *n, tv parts, tv step, const char **why) {
    char key[128];
    uint64_t blen, vsize;
    tv bname = tv_get(step, "block");
    snprintf(key, sizeof key, "%.*s", (int)rd64(bname + 1), (const char *)(bname + 9));
    tv v = tv_get(step, "valid");
    int valid = !v || (*v == T_BOOL && v[1]);
    uint8_t *signed_block = decode(type_by_name("SignedBeaconBlock"), tv_bytes(tv_get(parts, key), &blen), blen, &vsize, why);
    if (!signed_block) return;
    const uint8_t *block = nested(signed_block, field_offset("SignedBeaconBlock", 0));
    const uint8_t *parent_root = block + field_offset("BeaconBlock", 2);

    uint64_t options[2] = {1, 1};
    tv columns = tv_get(step, "columns");
    if (columns) {
        if (rd64(columns + 1) == 0) options[1] = 0; /* retrieve_column_sidecars raises: not enough data */
        else {
            uint64_t lsize;
            uint8_t *list = column_sidecars(parts, columns, &lsize, why);
            if (!list) {
                free(signed_block);
                return;
            }
            if (CALL(lantern_is_data_available, list, kzg_settings, config, fresh_scratch(), &options[1]) != 0)
                *why = "is_data_available: status not 0";
            free(list);
        }
    }

    kept_state *parent = find_kept(n->blocks, n->nblocks, parent_root, 0, 0);
    uint64_t size = parent ? parent->size : n->anchor_size, result = 0xA5A5A5A5A5A5A5A5u, st = 0;
    uint8_t *state = copy_of(parent ? parent->state : n->anchor, size);
    uint64_t before = node_count(n), growth = 2;
    /* BUFFER_TOO_SMALL: the store when it is full, else the state's lists. */
    st = FC_RETRY(n, why, CALL(lantern_on_block, n->store, signed_block, state, options, fresh_scratch(), &result),
                  if (node_count(n) == node_capacity(n->store)) grow_store(n, why);
                  else { state = regrow(state, &size, growth, why); growth *= 2; }, state, size);
    if (*why) {
    } else if (st != 0) {
        static char msg[64];
        snprintf(msg, sizeof msg, "on_block: status %llu", (unsigned long long)st);
        *why = msg;
    } else if (valid && result != 0) {
        static char msg[64];
        snprintf(msg, sizeof msg, "on_block: result %llu, expected valid", (unsigned long long)result);
        *why = msg;
    } else if (!valid && result == 0) *why = "on_block: expected an invalid block";
    if (!*why && result == 0 && node_count(n) == before + 1) {
        keep(&n->blocks, &n->nblocks, node_at(n, before), 0, state, size);
        state = NULL;
    }
    free(state);
    if (!*why && valid) {
        const uint8_t *body = nested(block, field_offset("BeaconBlock", 4));
        uint64_t ref = field_offset("BeaconBlockBody", 5);
        const uint8_t *a = body + rd64(body + ref);
        for (uint64_t i = 0, c = rd64(body + ref + 8); i < c && !*why; i++, a += rd64(a))
            if (fc_attestation(n, a, 1, why) != 0 && !*why && !n->compliance) *why = "a block attestation is not valid";
        ref = field_offset("BeaconBlockBody", 4);
        a = body + rd64(body + ref);
        for (uint64_t i = 0, c = rd64(body + ref + 8); i < c && !*why; i++, a += rd64(a))
            if (fc_attester_slashing(n, a, why) != 0 && !*why && !n->compliance)
                *why = "a block attester slashing is not valid";
    }
    free(signed_block);
}

/* The head node, through the retry rule. */
static uint64_t fc_head(fc_node *n, const char **why) {
    uint64_t head = 0;
    uint64_t st = FC_RETRY(n, why, CALL(lantern_get_head, n->store, fresh_scratch(), &head), break, NULL, 0);
    if (!*why && st != 0) *why = "get_head: status not 0";
    return head;
}

static int hex_root_equals(tv v, const uint8_t *root) {
    uint64_t len;
    const uint8_t *b = tv_bytes(v, &len);
    return len == 32 && !memcmp(b, root, 32);
}

/*
 * viable_for_head_roots_and_weights: the leaves of get_filtered_node_tree below
 * the justified node, or the justified node when the tree is empty, each with
 * get_weight. The check is a set of {root, weight}.
 */
static void fc_viable(fc_node *n, tv want, const char **why) {
    uint64_t count = node_count(n), lsize = 24 + 8 * count, nleaves = 0;
    uint8_t *tree = buffer(lsize), *in = xmalloc(count), *parent_of = xmalloc(count);
    uint64_t *leaves = xmalloc(sizeof *leaves * (count ? count : 1));
    wr64(tree, lsize);
    memset(in, 0, count);
    memset(parent_of, 0, count);
    if (CALL(lantern_get_filtered_node_tree, n->store, fresh_scratch(), tree) != 0) *why = "get_filtered_node_tree status";
    for (uint64_t k = 0; !*why && k < rd64(tree + 16); k++) in[rd64(tree + 24 + 8 * k)] = 1;
    for (uint64_t i = 0; !*why && i < count; i++) {
        uint64_t p = rd64(node_at(n, i) + NODE_PARENT);
        if (in[i] && p < count && in[p]) parent_of[p] = 1;
    }
    for (uint64_t i = 0; !*why && i < count; i++)
        if (in[i] && !parent_of[i]) leaves[nleaves++] = i;
    if (!*why && rd64(tree + 16) == 0)
        for (uint64_t i = 0; i < count; i++)
            if (!memcmp(node_at(n, i), n->store + STORE_JUSTIFIED + 8, 32)) leaves[nleaves++] = i;
    if (!*why && (*want != T_LIST || rd64(want + 1) != nleaves)) *why = "check viable_for_head_roots_and_weights: count";
    for (uint64_t k = 0; !*why && k < nleaves; k++) {
        uint64_t node = leaves[k], weight = 0, found = 0;
        uint64_t st = FC_RETRY(n, why, CALL(lantern_get_weight, n->store, &node, &weight), break, NULL, 0);
        if (*why) break;
        if (st != 0) {
            *why = "get_weight: status not 0";
            break;
        }
        tv e = want + 9;
        for (uint64_t j = 0; j < nleaves; j++, e = tv_skip(e))
            if (hex_root_equals(tv_get(e, "root"), node_at(n, node)) && tv_u64(tv_get(e, "weight")) == weight) found = 1;
        if (!found) *why = "check viable_for_head_roots_and_weights";
    }
    free(tree);
    free(in);
    free(parent_of);
    free(leaves);
}

static void fc_checks(fc_node *n, tv checks, const char **why) {
    uint64_t count = rd64(checks + 1);
    tv p = checks + 9;
    for (uint64_t i = 0; i < count && !*why; i++) {
        uint64_t klen = rd64(p);
        char key[64];
        snprintf(key, sizeof key, "%.*s", (int)klen, (const char *)(p + 8));
        tv v = p + 8 + klen;
        p = tv_skip(v);
        if (!strcmp(key, "head")) {
            uint64_t head = fc_head(n, why);
            if (*why) break;
            const uint8_t *node = node_at(n, head);
            if (rd64(node + NODE_SLOT) != tv_u64(tv_get(v, "slot")) || !hex_root_equals(tv_get(v, "root"), node))
                *why = "check head";
            /* The head is in get_filtered_node_tree, or is the justified node when the tree is empty. */
            uint64_t lsize = 24 + 8 * node_count(n);
            uint8_t *tree = buffer(lsize);
            wr64(tree, lsize);
            if (!*why && CALL(lantern_get_filtered_node_tree, n->store, fresh_scratch(), tree) != 0)
                *why = "get_filtered_node_tree: status not 0";
            else if (!*why) {
                uint64_t count = rd64(tree + 16), found = 0;
                for (uint64_t k = 0; k < count; k++) {
                    uint64_t e = rd64(tree + 24 + 8 * k);
                    if (e >= node_count(n) || (k && e <= rd64(tree + 16 + 8 * k))) *why = "filtered tree: bad entry";
                    if (e == head) found = 1;
                }
                if (!*why && !found && (count || memcmp(node, n->store + STORE_JUSTIFIED + 8, 32)))
                    *why = "filtered tree: head missing";
                if (!*why && !guard_ok(tree, lsize)) *why = "filtered tree: wrote out of bounds";
            }
            free(tree);
        } else if (!strcmp(key, "time")) {
            if (rd64(n->store + STORE_TIME_MS) / 1000 != tv_u64(v)) *why = "check time";
        } else if (!strcmp(key, "genesis_time")) {
            if (rd64(n->store + STORE_GENESIS_TIME_MS) / 1000 != tv_u64(v)) *why = "check genesis_time";
        } else if (!strcmp(key, "justified_checkpoint") || !strcmp(key, "finalized_checkpoint")) {
            const uint8_t *cp = n->store + (key[0] == 'j' ? STORE_JUSTIFIED : STORE_FINALIZED);
            if (rd64(cp) != tv_u64(tv_get(v, "epoch")) || !hex_root_equals(tv_get(v, "root"), cp + 8))
                *why = key[0] == 'j' ? "check justified_checkpoint" : "check finalized_checkpoint";
        } else if (!strcmp(key, "proposer_boost_root")) {
            if (!hex_root_equals(v, n->store + STORE_BOOST_ROOT)) *why = "check proposer_boost_root";
        } else if (!strcmp(key, "viable_for_head_roots_and_weights")) {
            fc_viable(n, v, why);
        } else if (!strcmp(key, "get_proposer_head")) {
            uint64_t head = fc_head(n, why), slot = 0, out = 0;
            if (*why) break;
            if (CALL(lantern_get_current_slot, n->store, &slot) != 0) {
                *why = "get_current_slot status";
                break;
            }
            kept_state *k = find_kept(n->blocks, n->nblocks, node_at(n, head), 0, 0);
            if (!k) {
                *why = "no state for the head";
                break;
            }
            uint64_t st = FC_RETRY(n, why, CALL(lantern_get_proposer_head, n->store, &head, &slot, k->state, fresh_scratch(), &out),
                                   break, NULL, 0);
            if (*why) break;
            if (st != 0) *why = "get_proposer_head: status not 0";
            else if (!hex_root_equals(v, node_at(n, out))) *why = "check get_proposer_head";
        } else {
            static char msg[96];
            snprintf(msg, sizeof msg, "unknown check %s", key);
            *why = msg;
        }
    }
}

/* compliance: the rules of the spec's fork choice compliance runner (tests/generators/compliance_runners). */
static void run_fork_choice(const char *file, const char *dir, case_file *f, int compliance) {
    load_kzg_settings(dir);
    for (uint64_t i = 0; i < f->count; i++) {
        const char *name, *why = NULL;
        uint64_t len, slen, blen, vsize;
        tv parts = next_case(f, &name, &len);
        if (skip_case(parts)) continue;
        fc_node n;
        memset(&n, 0, sizeof n);
        n.compliance = compliance;
        const uint8_t *enc = tv_bytes(tv_get(parts, "anchor_state"), &slen);
        n.anchor = load_state(enc, slen, &n.anchor_size, &why);
        uint8_t *anchor_block = NULL;
        if (n.anchor) anchor_block = decode(type_by_name("BeaconBlock"), tv_bytes(tv_get(parts, "anchor_block"), &blen), blen, &vsize, &why);
        if (anchor_block) {
            /* Small capacities, so that the store grows through lantern_store_copy. */
            uint64_t room[2] = {2, 1}, need = 0;
            CALL(lantern_store_size, room, &need);
            n.store = buffer(need);
            n.size = need;
            wr64(n.store, need);
            uint64_t st;
            while ((st = CALL(lantern_get_forkchoice_store, n.anchor, anchor_block, config, room, fresh_scratch(), n.store)) == 1 &&
                   room[1] < (1u << 24)) {
                room[1] *= 2;
                CALL(lantern_store_size, room, &need);
                free(n.store);
                n.store = buffer(need);
                n.size = need;
                wr64(n.store, need);
            }
            if (st != 0) why = "get_forkchoice_store: status not 0";
            else if (!guard_ok(n.store, n.size)) why = "get_forkchoice_store wrote out of bounds";
            else keep(&n.blocks, &n.nblocks, node_at(&n, 0), 0, copy_of(n.anchor, n.anchor_size), n.anchor_size);
        }
        tv steps = tv_get(parts, "steps");
        tv s = steps ? steps + 9 : NULL;
        for (uint64_t k = 0, c = steps ? rd64(steps + 1) : 0; k < c && !why; k++, s = tv_skip(s)) {
            tv v = tv_get(s, "valid");
            int valid = !v || (*v == T_BOOL && v[1]);
            if (tv_get(s, "tick")) {
                uint64_t secs = tv_u64(tv_get(s, "tick")), ms = secs > UINT64_MAX / 1000 ? UINT64_MAX : secs * 1000;
                uint64_t result = 0xA5A5A5A5A5A5A5A5u;
                if (CALL(lantern_on_tick, n.store, &ms, &result) != 0) why = "on_tick: status not 0";
                else if ((result == 0) != valid) why = "on_tick: result";
            } else if (tv_get(s, "block")) {
                fc_block(&n, parts, s, &why);
            } else if (tv_get(s, "attestation") || tv_get(s, "attester_slashing")) {
                int att = tv_get(s, "attestation") != NULL;
                tv nm = tv_get(s, att ? "attestation" : "attester_slashing");
                char key[128];
                uint64_t olen;
                snprintf(key, sizeof key, "%.*s", (int)rd64(nm + 1), (const char *)(nm + 9));
                uint8_t *op = decode(type_by_name(att ? "Attestation" : "AttesterSlashing"), tv_bytes(tv_get(parts, key), &olen),
                                     olen, &vsize, &why);
                if (op) {
                    uint64_t result = att ? fc_attestation(&n, op, 0, &why) : fc_attester_slashing(&n, op, &why);
                    if (!why && (result == 0) != valid) why = att ? "on_attestation: result" : "on_attester_slashing: result";
                    free(op);
                }
            } else if (tv_get(s, "checks")) {
                fc_checks(&n, tv_get(s, "checks"), &why);
            } else {
                why = "unknown step";
            }
            if (!why && n.store && !guard_ok(n.store, n.size)) why = "wrote past the store";
            if (!why && !guard_ok(scratch_buf, SCRATCH_BYTES)) why = "wrote past the scratch";
            if (why) {
                static char msg[160];
                snprintf(msg, sizeof msg, "step %llu: %s", (unsigned long long)k, why);
                why = msg;
            }
        }
        for (size_t k = 0; k < n.nblocks; k++) free(n.blocks[k].state);
        for (size_t k = 0; k < n.ncheckpoints; k++) free(n.checkpoints[k].state);
        free(n.blocks);
        free(n.checkpoints);
        free(n.store);
        free(n.anchor);
        free(anchor_block);
        report(file, name, len, why == NULL, why);
    }
}

/* ---------------------------------------------------------------- Main */

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s VECTOR_DIR FILE ...\n", argv[0]);
        return 2;
    }
    load_config(argv[1]);
    scratch_buf = buffer(SCRATCH_BYTES);
    const char *prefix = PRESET "-";
    size_t plen = strlen(prefix);
    for (int a = 2; a < argc; a++) {
        const char *file = argv[a];
        if (strncmp(file, prefix, plen)) continue;
        char kind[256];
        snprintf(kind, sizeof kind, "%s", file + plen);
        char *dot = strstr(kind, ".bin");
        if (dot) *dot = 0;
        case_file f;
        if (!read_file(argv[1], file, &f)) {
            printf("FAIL %s: cannot read\n", file);
            failures++;
            continue;
        }
        int before = failures, ran = passes, skips = skipped;
        /* The signatures-off runner runs only the handlers whose cases can have bls_setting 2. */
        if (!bls_off && !strcmp(kind, "descriptors")) run_descriptors(file, &f);
        else if (!bls_off && !strncmp(kind, "ssz_static-", 11)) run_ssz_static(file, kind + 11, &f);
        else if (!bls_off && !strncmp(kind, "epoch_processing-", 17)) run_epoch(file, kind + 17, &f);
        else if (!bls_off && !strcmp(kind, "shuffling-core")) run_shuffling(file, &f);
        else if (!strncmp(kind, "operations-", 11)) run_operations(file, kind + 11, &f);
        else if (!bls_off && !strcmp(kind, "sanity-slots")) run_slots(file, &f);
        else if (!strcmp(kind, "sanity-blocks") || !strcmp(kind, "finality-finality") || !strcmp(kind, "random-random"))
            run_blocks(file, &f);
        else if (!bls_off && !strncmp(kind, "rewards-", 8)) run_rewards(file, &f);
        else if (!strncmp(kind, "fork_choice-", 12)) run_fork_choice(file, argv[1], &f, 0);
        else if (!strncmp(kind, "fork_choice_compliance-", 23)) run_fork_choice(file, argv[1], &f, 1);
        else {
            free(f.data);
            continue;
        }
        if (bls_off && passes == ran && failures == before) { /* every case skipped */
            free(f.data);
            continue;
        }
        printf("%s %s: %d passed, %d failed", failures == before ? "PASS" : "FAIL", file, passes - ran,
               failures - before);
        if (skipped > skips) printf(", %d skipped (bls_setting)", skipped - skips);
        printf("\n");
        free(f.data);
    }
    for (int i = 0; i < stats_count; i++) {
        int bad = stats[i].fault || stats[i].peak > STACK_CAP;
        printf("STACK %s %llu bytes%s\n", stats[i].name, (unsigned long long)stats[i].peak, bad ? " ABI FAULT" : "");
        if (bad) failures++;
    }
    printf("%s: %d passed, %d failed\n", failures ? "FAIL" : "PASS", passes, failures);
    return failures ? 1 : 0;
}
