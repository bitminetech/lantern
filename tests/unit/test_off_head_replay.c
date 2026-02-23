#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "lantern/storage/storage.h"
#include "lantern/support/strings.h"

#define DEVNET_DATA_DIR "internal-docs/pending-issues/devnet-run-data/lantern_0"
#define LANTERN_STORAGE_STATE_META_VERSION 1u

struct state_meta_wire {
    uint32_t version;
    uint32_t reserved;
    uint64_t historical_roots_offset;
    uint64_t justified_slots_offset;
};

struct head_record_wire {
    uint64_t slot;
    LanternRoot root;
};

struct expected_failure_block {
    const char *root_hex;
    uint64_t slot;
};

static bool directory_exists(const char *path) {
    if (!path) {
        return false;
    }
    struct stat st;
    if (stat(path, &st) != 0) {
        return false;
    }
    return S_ISDIR(st.st_mode);
}

static bool file_exists(const char *path) {
    if (!path) {
        return false;
    }
    struct stat st;
    if (stat(path, &st) != 0) {
        return false;
    }
    return S_ISREG(st.st_mode);
}

static int read_file_bytes(const char *path, uint8_t **out_data, size_t *out_len) {
    if (!path || !out_data || !out_len) {
        return -1;
    }
    *out_data = NULL;
    *out_len = 0;

    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return (errno == ENOENT) ? 1 : -1;
    }

    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return -1;
    }
    long end_pos = ftell(fp);
    if (end_pos < 0) {
        fclose(fp);
        return -1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return -1;
    }

    if (end_pos == 0) {
        fclose(fp);
        return 1;
    }
    size_t len = (size_t)end_pos;
    uint8_t *buf = malloc(len);
    if (!buf) {
        fclose(fp);
        return -1;
    }
    size_t read = fread(buf, 1u, len, fp);
    fclose(fp);
    if (read != len) {
        free(buf);
        return -1;
    }

    *out_data = buf;
    *out_len = len;
    return 0;
}

static int parse_root_hex(const char *text, LanternRoot *out_root) {
    if (!text || !out_root) {
        return -1;
    }
    const char *hex = text;
    if (hex[0] == '0' && (hex[1] == 'x' || hex[1] == 'X')) {
        hex += 2;
    }
    if (strlen(hex) != 2u * LANTERN_ROOT_SIZE) {
        return -1;
    }
    if (lantern_hex_decode(hex, out_root->bytes, LANTERN_ROOT_SIZE) != 0) {
        return -1;
    }
    return 0;
}

static int root_to_hex(const LanternRoot *root, char *out, size_t out_len, bool with_prefix) {
    if (!root || !out || out_len == 0) {
        return -1;
    }
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, out, out_len, with_prefix ? 1 : 0) != 0) {
        out[0] = '\0';
        return -1;
    }
    return 0;
}

static int read_meta_file(const char *path, struct state_meta_wire *out_meta) {
    if (!path || !out_meta) {
        return -1;
    }
    uint8_t *data = NULL;
    size_t len = 0;
    int rc = read_file_bytes(path, &data, &len);
    if (rc != 0) {
        free(data);
        return rc;
    }
    if (len != sizeof(*out_meta)) {
        free(data);
        return -1;
    }
    memcpy(out_meta, data, sizeof(*out_meta));
    free(data);
    if (out_meta->version != LANTERN_STORAGE_STATE_META_VERSION) {
        return -1;
    }
    return 0;
}

static int load_block_by_root_filename(
    const char *data_dir,
    const LanternRoot *root,
    LanternSignedBlock *out_block) {
    if (!data_dir || !root || !out_block) {
        return -1;
    }

    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    if (root_to_hex(root, root_hex, sizeof(root_hex), false) != 0) {
        return -1;
    }

    char path[PATH_MAX];
    int written = snprintf(path, sizeof(path), "%s/blocks/%s.ssz", data_dir, root_hex);
    if (written < 0 || (size_t)written >= sizeof(path)) {
        return -1;
    }

    uint8_t *data = NULL;
    size_t len = 0;
    int rc = read_file_bytes(path, &data, &len);
    if (rc != 0) {
        free(data);
        return rc;
    }

    lantern_signed_block_with_attestation_init(out_block);
    if (lantern_ssz_decode_signed_block(out_block, data, len) != 0) {
        free(data);
        lantern_signed_block_with_attestation_reset(out_block);
        return -1;
    }

    free(data);
    return 0;
}

/*
 * This intentionally mirrors the buggy fast path in rebuild_state_for_root_locked:
 * decode SSZ snapshot bytes directly without state meta restoration or vote buffer prep.
 */
static int load_snapshot_buggy(
    const char *data_dir,
    const LanternRoot *state_root,
    LanternState *out_state) {
    if (!data_dir || !state_root || !out_state) {
        return -1;
    }
    uint8_t *state_bytes = NULL;
    size_t state_len = 0;
    if (lantern_storage_load_state_bytes_for_root(data_dir, state_root, &state_bytes, &state_len) != 0) {
        free(state_bytes);
        return -1;
    }
    lantern_state_init(out_state);
    if (lantern_ssz_decode_state(out_state, state_bytes, state_len) != 0) {
        free(state_bytes);
        lantern_state_reset(out_state);
        return -1;
    }
    free(state_bytes);
    return 0;
}

/*
 * Fixed reconstruction path for diagnostics:
 * - decode SSZ snapshot
 * - restore per-snapshot offsets from states/<root>.meta when present
 * - allocate validator_votes backing storage expected by attestation processing
 */
static int load_snapshot_fixed(
    const char *data_dir,
    const LanternRoot *state_root,
    LanternState *out_state) {
    if (load_snapshot_buggy(data_dir, state_root, out_state) != 0) {
        return -1;
    }

    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    if (root_to_hex(state_root, root_hex, sizeof(root_hex), false) != 0) {
        lantern_state_reset(out_state);
        return -1;
    }

    char meta_path[PATH_MAX];
    int path_written = snprintf(meta_path, sizeof(meta_path), "%s/states/%s.meta", data_dir, root_hex);
    if (path_written < 0 || (size_t)path_written >= sizeof(meta_path)) {
        lantern_state_reset(out_state);
        return -1;
    }

    struct state_meta_wire meta = {0};
    int meta_rc = read_meta_file(meta_path, &meta);
    if (meta_rc == 0) {
        out_state->historical_roots_offset = meta.historical_roots_offset;
        out_state->justified_slots_offset = meta.justified_slots_offset;
    } else if (meta_rc < 0) {
        lantern_state_reset(out_state);
        return -1;
    }

    if (out_state->config.num_validators == 0) {
        lantern_state_reset(out_state);
        return -1;
    }
    if (lantern_state_prepare_validator_votes(out_state, out_state->config.num_validators) != 0) {
        lantern_state_reset(out_state);
        return -1;
    }

    return 0;
}

static void print_state_summary(const char *prefix, const LanternState *state) {
    if (!prefix || !state) {
        return;
    }
    printf(
        "%s slot=%" PRIu64 " validators=%" PRIu64
        " validator_votes_ptr=%p validator_votes_len=%zu"
        " hist_offset=%" PRIu64 " just_offset=%" PRIu64 "\n",
        prefix,
        state->slot,
        state->config.num_validators,
        (void *)state->validator_votes,
        state->validator_votes_len,
        state->historical_roots_offset,
        state->justified_slots_offset);
}

static int diagnose_transition_failure(
    const char *data_dir,
    const LanternSignedBlock *block,
    bool *out_hit_expected_fail_condition) {
    if (!data_dir || !block || !out_hit_expected_fail_condition) {
        return -1;
    }
    *out_hit_expected_fail_condition = false;

    LanternState state;
    lantern_state_init(&state);
    if (load_snapshot_buggy(data_dir, &block->message.block.parent_root, &state) != 0) {
        lantern_state_reset(&state);
        return -1;
    }

    if (block->message.block.slot <= state.slot) {
        printf(
            "diagnostic: block slot %" PRIu64 " is not ahead of parent state slot %" PRIu64 "\n",
            block->message.block.slot,
            state.slot);
        lantern_state_reset(&state);
        return 0;
    }

    int slots_rc = lantern_state_process_slots(&state, block->message.block.slot);
    printf("diagnostic: lantern_state_process_slots rc=%d\n", slots_rc);
    if (slots_rc != 0) {
        lantern_state_reset(&state);
        return 0;
    }

    int header_rc = lantern_state_process_block_header(&state, &block->message.block);
    printf("diagnostic: lantern_state_process_block_header rc=%d\n", header_rc);
    if (header_rc != 0) {
        lantern_state_reset(&state);
        return 0;
    }

    size_t validator_count = 0;
    if (state.config.num_validators <= SIZE_MAX) {
        validator_count = (size_t)state.config.num_validators;
    }
    LanternAttestations expanded = {0};
    lantern_attestations_init(&expanded);
    int expand_rc = lantern_expand_aggregated_attestations(
        &block->message.block.body.attestations,
        validator_count,
        &expanded);
    printf(
        "diagnostic: lantern_expand_aggregated_attestations rc=%d expanded_len=%zu\n",
        expand_rc,
        expanded.length);
    if (expand_rc != 0) {
        lantern_attestations_reset(&expanded);
        lantern_state_reset(&state);
        return 0;
    }

    int att_rc = lantern_state_process_attestations(&state, &expanded, NULL);
    printf("diagnostic: lantern_state_process_attestations rc=%d\n", att_rc);
    printf(
        "diagnostic: validator_votes_ptr=%p validator_votes_len=%zu expected=%" PRIu64 "\n",
        (void *)state.validator_votes,
        state.validator_votes_len,
        state.config.num_validators);

    if (att_rc != 0
        && (!state.validator_votes
            || state.validator_votes_len != (size_t)state.config.num_validators)) {
        *out_hit_expected_fail_condition = true;
        printf(
            "FAIL_POINT: state.c rejects attestation processing because "
            "`!state->validator_votes || state->validator_votes_len != validator_count`\n");
    }

    lantern_attestations_reset(&expanded);
    lantern_state_reset(&state);
    return 0;
}

static int replay_target_block(
    const char *data_dir,
    const LanternRoot *block_root,
    const char *label) {
    if (!data_dir || !block_root || !label) {
        return -1;
    }

    LanternSignedBlock block;
    int load_rc = load_block_by_root_filename(data_dir, block_root, &block);
    if (load_rc != 0) {
        printf("%s: block load failed rc=%d\n", label, load_rc);
        return -1;
    }

    char block_hex[2u * LANTERN_ROOT_SIZE + 3u];
    char parent_hex[2u * LANTERN_ROOT_SIZE + 3u];
    if (root_to_hex(block_root, block_hex, sizeof(block_hex), true) != 0) {
        strcpy(block_hex, "0x?");
    }
    if (root_to_hex(&block.message.block.parent_root, parent_hex, sizeof(parent_hex), true) != 0) {
        strcpy(parent_hex, "0x?");
    }
    printf(
        "\nReplaying %s slot=%" PRIu64 " root=%s parent=%s proposer=%" PRIu64 "\n",
        label,
        block.message.block.slot,
        block_hex,
        parent_hex,
        block.message.block.proposer_index);

    LanternState buggy_state;
    lantern_state_init(&buggy_state);
    if (load_snapshot_buggy(data_dir, &block.message.block.parent_root, &buggy_state) != 0) {
        printf("%s: failed to load buggy parent snapshot\n", label);
        lantern_state_reset(&buggy_state);
        lantern_signed_block_with_attestation_reset(&block);
        return -1;
    }
    print_state_summary("buggy parent snapshot", &buggy_state);
    int buggy_transition_rc = lantern_state_transition(&buggy_state, &block);
    printf("buggy lantern_state_transition rc=%d\n", buggy_transition_rc);
    lantern_state_reset(&buggy_state);

    bool hit_expected_fail_condition = false;
    if (diagnose_transition_failure(data_dir, &block, &hit_expected_fail_condition) != 0) {
        printf("%s: failure diagnostics failed\n", label);
        lantern_signed_block_with_attestation_reset(&block);
        return -1;
    }

    LanternState fixed_state;
    lantern_state_init(&fixed_state);
    if (load_snapshot_fixed(data_dir, &block.message.block.parent_root, &fixed_state) != 0) {
        printf("%s: failed to load fixed parent snapshot\n", label);
        lantern_state_reset(&fixed_state);
        lantern_signed_block_with_attestation_reset(&block);
        return -1;
    }
    print_state_summary("fixed parent snapshot", &fixed_state);
    int fixed_transition_rc = lantern_state_transition(&fixed_state, &block);
    printf("fixed lantern_state_transition rc=%d\n", fixed_transition_rc);
    lantern_state_reset(&fixed_state);
    lantern_signed_block_with_attestation_reset(&block);

    if (buggy_transition_rc == 0) {
        printf("%s: expected buggy snapshot transition failure but got success\n", label);
        return -1;
    }
    if (!hit_expected_fail_condition) {
        printf("%s: did not hit expected attestation precondition failure\n", label);
        return -1;
    }
    if (fixed_transition_rc != 0) {
        printf("%s: fixed snapshot transition should succeed but rc=%d\n", label, fixed_transition_rc);
        return -1;
    }

    return 0;
}

static int read_head_record(const char *data_dir, struct head_record_wire *out_head) {
    if (!data_dir || !out_head) {
        return -1;
    }
    char path[PATH_MAX];
    int written = snprintf(path, sizeof(path), "%s/indices/head.bin", data_dir);
    if (written < 0 || (size_t)written >= sizeof(path)) {
        return -1;
    }

    uint8_t *bytes = NULL;
    size_t len = 0;
    int rc = read_file_bytes(path, &bytes, &len);
    if (rc != 0) {
        free(bytes);
        return -1;
    }
    if (len != sizeof(*out_head)) {
        free(bytes);
        return -1;
    }
    memcpy(out_head, bytes, sizeof(*out_head));
    free(bytes);
    return 0;
}

int main(void) {
    if (!directory_exists(DEVNET_DATA_DIR)) {
        printf("SKIP: devnet data directory missing: %s\n", DEVNET_DATA_DIR);
        return EXIT_SUCCESS;
    }

    LanternState persisted;
    lantern_state_init(&persisted);
    if (lantern_storage_load_state(DEVNET_DATA_DIR, &persisted) != 0) {
        fprintf(stderr, "failed to load persisted state from %s/state.ssz\n", DEVNET_DATA_DIR);
        lantern_state_reset(&persisted);
        return EXIT_FAILURE;
    }
    print_state_summary("persisted state", &persisted);
    lantern_state_reset(&persisted);

    char state_meta_path[PATH_MAX];
    int meta_written = snprintf(state_meta_path, sizeof(state_meta_path), "%s/state.meta", DEVNET_DATA_DIR);
    if (meta_written < 0 || (size_t)meta_written >= sizeof(state_meta_path)) {
        fprintf(stderr, "failed to build state.meta path\n");
        return EXIT_FAILURE;
    }

    struct state_meta_wire state_meta = {0};
    int state_meta_rc = read_meta_file(state_meta_path, &state_meta);
    if (state_meta_rc == 0) {
        printf(
            "state.meta version=%u historical_roots_offset=%" PRIu64 " justified_slots_offset=%" PRIu64 "\n",
            state_meta.version,
            state_meta.historical_roots_offset,
            state_meta.justified_slots_offset);
    } else {
        fprintf(stderr, "failed to read %s rc=%d\n", state_meta_path, state_meta_rc);
        return EXIT_FAILURE;
    }

    const struct expected_failure_block failing_blocks[] = {
        {
            .root_hex = "c3408383ca7fe5462b9edc7a48ec38d0603af497e7c597455529820423d63d2d",
            .slot = 3121,
        },
        {
            .root_hex = "b41f8772f299dbc0d97db0325d558fdef62ff79f3658f4bdd3a5e84ed418920b",
            .slot = 3145,
        },
        {
            .root_hex = "5b4852261cd40322fcc00551f6bbbc9aa02845b6204c66c47e5faa6f171ad2ef",
            .slot = 3153,
        },
    };

    size_t present_fail_blocks = 0;
    LanternRoot replay_roots[3];
    uint64_t replay_slots[3];
    for (size_t i = 0; i < (sizeof(failing_blocks) / sizeof(failing_blocks[0])); ++i) {
        LanternRoot root = {0};
        if (parse_root_hex(failing_blocks[i].root_hex, &root) != 0) {
            fprintf(stderr, "invalid root hex: %s\n", failing_blocks[i].root_hex);
            return EXIT_FAILURE;
        }
        char path[PATH_MAX];
        int wrote = snprintf(
            path,
            sizeof(path),
            "%s/blocks/%s.ssz",
            DEVNET_DATA_DIR,
            failing_blocks[i].root_hex);
        if (wrote < 0 || (size_t)wrote >= sizeof(path)) {
            fprintf(stderr, "path overflow for root %s\n", failing_blocks[i].root_hex);
            return EXIT_FAILURE;
        }
        if (!file_exists(path)) {
            printf(
                "missing expected failing block file slot=%" PRIu64 " root=0x%s path=%s\n",
                failing_blocks[i].slot,
                failing_blocks[i].root_hex,
                path);
            continue;
        }
        replay_roots[present_fail_blocks] = root;
        replay_slots[present_fail_blocks] = failing_blocks[i].slot;
        present_fail_blocks += 1u;
    }

    if (present_fail_blocks == 0) {
        printf(
            "no expected failing block files are present; using head block as replay surrogate "
            "to reproduce the same off-head failure condition.\n");
        struct head_record_wire head = {0};
        if (read_head_record(DEVNET_DATA_DIR, &head) != 0) {
            fprintf(stderr, "failed to read fallback head record\n");
            return EXIT_FAILURE;
        }
        replay_roots[0] = head.root;
        replay_slots[0] = head.slot;
        present_fail_blocks = 1u;
    }

    size_t replay_failures = 0;
    for (size_t i = 0; i < present_fail_blocks; ++i) {
        char label[64];
        int lbl_written = snprintf(label, sizeof(label), "target_slot_%" PRIu64, replay_slots[i]);
        if (lbl_written < 0 || (size_t)lbl_written >= sizeof(label)) {
            fprintf(stderr, "label overflow\n");
            return EXIT_FAILURE;
        }
        if (replay_target_block(DEVNET_DATA_DIR, &replay_roots[i], label) != 0) {
            replay_failures += 1u;
        }
    }

    if (replay_failures > 0) {
        fprintf(stderr, "off-head replay diagnostics failed for %zu target(s)\n", replay_failures);
        return EXIT_FAILURE;
    }

    printf(
        "\nROOT_CAUSE: off-head replay snapshot decode path omits validator vote storage initialization.\n"
        "Affected check: `state.c` attestation processing rejects states where\n"
        "`!state->validator_votes || state->validator_votes_len != validator_count`.\n"
        "The buggy path is the raw snapshot decode used by replay state reconstruction.\n");

    return EXIT_SUCCESS;
}
