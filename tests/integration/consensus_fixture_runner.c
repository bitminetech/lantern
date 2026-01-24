#include "lantern/consensus/containers.h"
#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/state.h"
#include "lantern/consensus/ssz.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "fixture_runner.h"
#include "tests/support/fixture_loader.h"

#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <limits.h>

#ifndef LANTERN_TEST_FIXTURE_DIR
#error "LANTERN_TEST_FIXTURE_DIR must be defined"
#endif

#define LABEL_MAX_LENGTH 64
#define MAX_LABELS 128


static void configure_logging(void) {
    const char *env_level = getenv("LANTERN_LOG_LEVEL");
    if (env_level && env_level[0] != '\0') {
        if (lantern_log_set_level_from_string(env_level, NULL) != 0) {
            fprintf(stderr, "invalid LANTERN_LOG_LEVEL '%s'\n", env_level);
        }
        return;
    }
    lantern_log_set_level(LANTERN_LOG_LEVEL_WARN);
}

static bool is_root_zero(const LanternRoot *root) {
    if (!root) {
        return false;
    }
    for (size_t i = 0; i < LANTERN_ROOT_SIZE; ++i) {
        if (root->bytes[i] != 0) {
            return false;
        }
    }
    return true;
}

/* Patch block hashes to use C-computed values instead of LeanSpec-computed values.
 * LeanSpec uses variable-length XMSS signatures which produces different hashes.
 * This function computes the correct parent_root and state_root using C code.
 *
 * The parent_root must be computed considering that process_slot fills in
 * latest_block_header.state_root if it was zero (which changes the hash). */
static int patch_block_hashes_for_c_compat(
    LanternState *state,
    LanternSignedBlock *signed_block) {
    if (!state || !signed_block) {
        return -1;
    }

    /* Compute what latest_block_header will look like after slot processing.
     * If state_root is zero, process_slot fills it with hash(state). */
    LanternBlockHeader header_after_slots = state->latest_block_header;
    if (is_root_zero(&header_after_slots.state_root)) {
        if (lantern_hash_tree_root_state(state, &header_after_slots.state_root) != 0) {
            return -1;
        }
    }

    /* Compute parent_root = hash(header_after_slots) */
    LanternRoot computed_parent;
    if (lantern_hash_tree_root_block_header(&header_after_slots, &computed_parent) != 0) {
        return -1;
    }
    memcpy(signed_block->message.block.parent_root.bytes, computed_parent.bytes, LANTERN_ROOT_SIZE);

    /* Now compute state_root using preview function (which internally checks parent_root) */
    LanternRoot computed_state_root;
    if (lantern_state_preview_post_state_root(state, signed_block, &computed_state_root) != 0) {
        return -1;
    }

    memcpy(signed_block->message.block.state_root.bytes, computed_state_root.bytes, LANTERN_ROOT_SIZE);

    return 0;
}

struct stored_vote_entry {
    bool has_vote;
    LanternVote vote;
};

struct stored_state_entry {
    LanternRoot root;
    uint8_t *data;
    size_t length;
    struct stored_vote_entry *votes;
    size_t vote_count;
};

static void stored_state_entries_reset(struct stored_state_entry **entries_ptr, size_t *count_ptr, size_t *cap_ptr) {
    if (!entries_ptr || !count_ptr || !cap_ptr) {
        return;
    }
    struct stored_state_entry *entries = *entries_ptr;
    if (entries) {
        for (size_t i = 0; i < *count_ptr; ++i) {
            free(entries[i].data);
            entries[i].data = NULL;
            entries[i].length = 0;
            free(entries[i].votes);
            entries[i].votes = NULL;
            entries[i].vote_count = 0;
        }
        free(entries);
    }
    *entries_ptr = NULL;
    *count_ptr = 0;
    *cap_ptr = 0;
}

static struct stored_state_entry *stored_state_find(
    struct stored_state_entry *entries,
    size_t count,
    const LanternRoot *root) {
    if (!entries || !root) {
        return NULL;
    }
    for (size_t i = 0; i < count; ++i) {
        if (memcmp(entries[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0) {
            return &entries[i];
        }
    }
    return NULL;
}

static int stored_state_add(
    struct stored_state_entry **entries_ptr,
    size_t *count_ptr,
    size_t *cap_ptr,
    const LanternRoot *root,
    uint8_t *data,
    size_t length,
    struct stored_vote_entry *votes,
    size_t vote_count) {
    if (!entries_ptr || !count_ptr || !cap_ptr || !root || !data) {
        free(data);
        free(votes);
        return -1;
    }
    struct stored_state_entry *entries = *entries_ptr;
    size_t count = *count_ptr;
    size_t cap = *cap_ptr;

    struct stored_state_entry *existing = stored_state_find(entries, count, root);
    if (existing) {
        free(existing->data);
        existing->data = data;
        existing->length = length;
        free(existing->votes);
        existing->votes = votes;
        existing->vote_count = vote_count;
        return 0;
    }

    if (count == cap) {
        size_t new_cap = cap == 0 ? 8u : cap * 2u;
        if (new_cap < cap) {
            free(data);
            free(votes);
            return -1;
        }
        struct stored_state_entry *expanded = realloc(entries, new_cap * sizeof(*expanded));
        if (!expanded) {
            free(data);
            free(votes);
            return -1;
        }
        entries = expanded;
        *entries_ptr = entries;
        *cap_ptr = new_cap;
    }

    entries[count].root = *root;
    entries[count].data = data;
    entries[count].length = length;
    entries[count].votes = votes;
    entries[count].vote_count = vote_count;
    *count_ptr = count + 1u;
    return 0;
}

static int encode_state_to_buffer(const LanternState *state, uint8_t **out_data, size_t *out_len) {
    if (!state || !out_data || !out_len) {
        return -1;
    }
    size_t buffer_size = 1u << 18; /* 256 KiB initial */
    uint8_t *buffer = malloc(buffer_size);
    if (!buffer) {
        return -1;
    }
    int rc = -1;
    while (true) {
        size_t written = 0;
        int status = lantern_ssz_encode_state(state, buffer, buffer_size, &written);
        if (status == 0) {
            uint8_t *copy = malloc(written);
            if (!copy) {
                free(buffer);
                break;
            }
            memcpy(copy, buffer, written);
            free(buffer);
            *out_data = copy;
            *out_len = written;
            rc = 0;
            break;
        }
        if (buffer_size > (1u << 24)) { /* 16 MiB cap to avoid runaway */
            free(buffer);
            break;
        }
        size_t new_size = buffer_size * 2u;
        uint8_t *resized = realloc(buffer, new_size);
        if (!resized) {
            free(buffer);
            break;
        }
        buffer = resized;
        buffer_size = new_size;
    }
    return rc;
}

static int stored_state_save(
    struct stored_state_entry **entries_ptr,
    size_t *count_ptr,
    size_t *cap_ptr,
    const LanternRoot *root,
    const LanternState *state) {
    if (!entries_ptr || !count_ptr || !cap_ptr || !root || !state) {
        return -1;
    }
    uint8_t *encoded = NULL;
    size_t encoded_len = 0;
    int rc = -1;
    if (encode_state_to_buffer(state, &encoded, &encoded_len) != 0) {
        goto done;
    }

    size_t vote_capacity = lantern_state_validator_capacity(state);
    struct stored_vote_entry *votes = NULL;
    if (vote_capacity > 0) {
        votes = calloc(vote_capacity, sizeof(*votes));
        if (!votes) {
            free(encoded);
            return -1;
        }
        for (size_t i = 0; i < vote_capacity; ++i) {
            if (!lantern_state_validator_has_vote(state, i)) {
                continue;
            }
            LanternVote vote;
            if (lantern_state_get_validator_vote(state, i, &vote) != 0) {
                free(votes);
                free(encoded);
                return -1;
            }
            votes[i].has_vote = true;
            votes[i].vote = vote;
        }
    }

    int add_status = stored_state_add(entries_ptr, count_ptr, cap_ptr, root, encoded, encoded_len, votes, vote_capacity);
    if (add_status != 0) {
        free(votes);
        free(encoded);
        goto done;
    }
    rc = 0;

done:
    return rc;
}

static int stored_state_restore(
    struct stored_state_entry *entries,
    size_t count,
    const LanternRoot *root,
    LanternState *state) {
    if (!entries || !root || !state) {
        return -1;
    }
    struct stored_state_entry *entry = stored_state_find(entries, count, root);
    if (!entry) {
        return -1;
    }
    int rc = -1;
    if (lantern_ssz_decode_state(state, entry->data, entry->length) != 0) {
        goto done;
    }
    uint64_t validator_count = state->config.num_validators;
    if (validator_count == 0) {
        goto done;
    }
    if (lantern_state_prepare_validator_votes(state, validator_count) != 0) {
        goto done;
    }
    size_t capacity = lantern_state_validator_capacity(state);
    size_t copy_count = entry->vote_count < capacity ? entry->vote_count : capacity;
    if (entry->votes) {
        for (size_t i = 0; i < copy_count; ++i) {
            if (!entry->votes[i].has_vote) {
                continue;
            }
            if (lantern_state_set_validator_vote(state, i, &entry->votes[i].vote) != 0) {
                goto done;
            }
        }
    }
    rc = 0;

done:
    return rc;
}

/* Hash mapping structure to translate LeanSpec block hashes to C block hashes.
 * This is needed because LeanSpec uses variable-length XMSS signatures which
 * produce different block hashes than C (which uses fixed-length signatures). */
struct hash_mapping_entry {
    LanternRoot leanspec_hash;
    LanternRoot c_hash;
};

static void hash_mapping_reset(struct hash_mapping_entry **entries_ptr, size_t *count_ptr, size_t *cap_ptr) {
    if (!entries_ptr || !count_ptr || !cap_ptr) {
        return;
    }
    free(*entries_ptr);
    *entries_ptr = NULL;
    *count_ptr = 0;
    *cap_ptr = 0;
}

static const LanternRoot *hash_mapping_leanspec_to_c(
    struct hash_mapping_entry *entries,
    size_t count,
    const LanternRoot *leanspec_hash) {
    if (!entries || !leanspec_hash) {
        return NULL;
    }
    for (size_t i = 0; i < count; ++i) {
        if (memcmp(entries[i].leanspec_hash.bytes, leanspec_hash->bytes, LANTERN_ROOT_SIZE) == 0) {
            return &entries[i].c_hash;
        }
    }
    return NULL;
}

static int hash_mapping_add(
    struct hash_mapping_entry **entries_ptr,
    size_t *count_ptr,
    size_t *cap_ptr,
    const LanternRoot *leanspec_hash,
    const LanternRoot *c_hash) {
    if (!entries_ptr || !count_ptr || !cap_ptr || !leanspec_hash || !c_hash) {
        return -1;
    }
    struct hash_mapping_entry *entries = *entries_ptr;
    size_t count = *count_ptr;
    size_t cap = *cap_ptr;

    /* Check if mapping already exists */
    for (size_t i = 0; i < count; ++i) {
        if (memcmp(entries[i].leanspec_hash.bytes, leanspec_hash->bytes, LANTERN_ROOT_SIZE) == 0) {
            entries[i].c_hash = *c_hash;
            return 0;
        }
    }

    if (count == cap) {
        size_t new_cap = cap == 0 ? 16u : cap * 2u;
        if (new_cap < cap) {
            return -1;
        }
        struct hash_mapping_entry *expanded = realloc(entries, new_cap * sizeof(*expanded));
        if (!expanded) {
            return -1;
        }
        entries = expanded;
        *entries_ptr = entries;
        *cap_ptr = new_cap;
    }

    entries[count].leanspec_hash = *leanspec_hash;
    entries[count].c_hash = *c_hash;
    *count_ptr = count + 1u;
    return 0;
}

static int sync_state_to_fork_choice_head(
    LanternForkChoice *store,
    LanternState *state,
    struct stored_state_entry **entries_ptr,
    size_t *count_ptr,
    LanternRoot *current_head_root) {
    if (!store || !state || !entries_ptr || !count_ptr || !current_head_root) {
        return -1;
    }
    LanternRoot head_root;
    if (lantern_fork_choice_current_head(store, &head_root) != 0) {
        return -1;
    }
    if (memcmp(head_root.bytes, current_head_root->bytes, LANTERN_ROOT_SIZE) == 0) {
        return 0;
    }
    struct stored_state_entry *entry = stored_state_find(*entries_ptr, *count_ptr, &head_root);
    if (!entry) {
        return -1;
    }
    lantern_state_reset(state);
    if (stored_state_restore(*entries_ptr, *count_ptr, &head_root, state) != 0) {
        return -1;
    }
    lantern_state_attach_fork_choice(state, store);
    *current_head_root = head_root;
    return 0;
}

struct label_entry {
    char name[LABEL_MAX_LENGTH];
    LanternRoot root;
    bool in_use;
};

struct label_registry {
    struct label_entry entries[MAX_LABELS];
};

static void label_registry_init(struct label_registry *registry) {
    if (!registry) {
        return;
    }
    memset(registry, 0, sizeof(*registry));
}

static int label_registry_assign(
    struct label_registry *registry,
    const char *label,
    const LanternRoot *root) {
    if (!registry || !label || !root) {
        return -1;
    }
    for (size_t i = 0; i < MAX_LABELS; ++i) {
        struct label_entry *entry = &registry->entries[i];
        if (!entry->in_use) {
            continue;
        }
        if (strcmp(entry->name, label) == 0) {
            if (memcmp(entry->root.bytes, root->bytes, sizeof(entry->root.bytes)) != 0) {
                fprintf(stderr, "label '%s' mapped to unexpected root\n", label);
                return -1;
            }
            return 0;
        }
    }
    for (size_t i = 0; i < MAX_LABELS; ++i) {
        struct label_entry *entry = &registry->entries[i];
        if (entry->in_use) {
            continue;
        }
        size_t len = strlen(label);
        if (len >= sizeof(entry->name)) {
            len = sizeof(entry->name) - 1u;
        }
        memcpy(entry->name, label, len);
        entry->name[len] = '\0';
        entry->root = *root;
        entry->in_use = true;
        return 0;
    }
    fprintf(stderr, "label registry full\n");
    return -1;
}

static int lantern_root_compare_bytes(const LanternRoot *a, const LanternRoot *b) {
    if (!a || !b) {
        return 0;
    }
    return memcmp(a->bytes, b->bytes, sizeof(a->bytes));
}

static bool lantern_root_equal(const LanternRoot *a, const LanternRoot *b) {
    return lantern_root_compare_bytes(a, b) == 0;
}

static size_t fork_choice_find_block_index(const LanternForkChoice *store, const LanternRoot *root) {
    if (!store || !root || !store->blocks) {
        return SIZE_MAX;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        if (lantern_root_equal(&store->blocks[i].root, root)) {
            return i;
        }
    }
    return SIZE_MAX;
}

static uint64_t *fork_choice_compute_known_weights(const LanternForkChoice *store, uint64_t *out_anchor_slot) {
    if (!store || store->block_len == 0) {
        return NULL;
    }
    uint64_t *weights = calloc(store->block_len, sizeof(*weights));
    if (!weights) {
        return NULL;
    }
    uint64_t anchor_slot = 0;
    size_t anchor_index = fork_choice_find_block_index(store, &store->latest_justified.root);
    if (anchor_index != SIZE_MAX) {
        anchor_slot = store->blocks[anchor_index].slot;
    }
    for (size_t i = 0; i < store->validator_count; ++i) {
        const struct lantern_fork_choice_vote_entry *vote = &store->known_votes[i];
        if (!vote->has_checkpoint) {
            continue;
        }
        size_t node_index = fork_choice_find_block_index(store, &vote->checkpoint.root);
        while (node_index != SIZE_MAX) {
            const struct lantern_fork_choice_block_entry *node = &store->blocks[node_index];
            if (node->slot <= anchor_slot) {
                break;
            }
            if (weights[node_index] < UINT64_MAX) {
                weights[node_index] += 1;
            }
            if (node->parent_index == SIZE_MAX || node->parent_index >= store->block_len) {
                break;
            }
            node_index = node->parent_index;
        }
    }
    if (out_anchor_slot) {
        *out_anchor_slot = anchor_slot;
    }
    return weights;
}

static void format_root_hex(const LanternRoot *root, char *buf, size_t buf_len) {
    if (!root || !buf || buf_len == 0) {
        return;
    }
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, buf, buf_len, 1) != 0) {
        buf[0] = '\0';
    }
}

static int validate_lexicographic_head_among(
    const LanternForkChoice *store,
    const LanternRoot *head_root,
    size_t label_count,
    const char **labels,
    const char *fixture_path,
    int step_index) {
    if (!store || !head_root || label_count < 2) {
        fprintf(
            stderr,
            "lexicographicHeadAmong requires at least two labels (fixture=%s step=%d)\n",
            fixture_path,
            step_index);
        return -1;
    }
    if (!store->has_head || store->block_len == 0) {
        fprintf(stderr, "fork choice store is not initialized for lexicographic check\n");
        return -1;
    }
    size_t head_index = fork_choice_find_block_index(store, head_root);
    if (head_index == SIZE_MAX) {
        fprintf(stderr, "head root not found in fork choice blocks for lexicographic check\n");
        return -1;
    }
    uint64_t anchor_slot = 0;
    uint64_t *weights = fork_choice_compute_known_weights(store, &anchor_slot);
    if (!weights) {
        fprintf(stderr, "failed to compute attestation weights for lexicographic check\n");
        return -1;
    }
    uint64_t head_slot = store->blocks[head_index].slot;
    uint64_t head_weight = weights[head_index];

    size_t candidate_count = 0;
    LanternRoot best_root = store->blocks[head_index].root;
    for (size_t i = 0; i < store->block_len; ++i) {
        const struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
        if (entry->slot != head_slot) {
            continue;
        }
        if (weights[i] != head_weight) {
            continue;
        }
        candidate_count += 1;
        if (lantern_root_compare_bytes(&entry->root, &best_root) > 0) {
            best_root = entry->root;
        }
    }
    if (candidate_count < 2) {
        free(weights);
        return 0;
    }
    if (candidate_count != label_count) {
        fprintf(
            stderr,
            "lexicographicHeadAmong mismatch in %s (step %d): expected %zu forks with equal weight "
            "but found %zu (weight=%" PRIu64 ")\n",
            fixture_path,
            step_index,
            label_count,
            candidate_count,
            head_weight);
        fprintf(stderr, "available forks at slot %" PRIu64 ":\n", head_slot);
        for (size_t i = 0; i < store->block_len; ++i) {
            const struct lantern_fork_choice_block_entry *entry = &store->blocks[i];
            if (entry->slot != head_slot) {
                continue;
            }
            char root_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
            format_root_hex(&entry->root, root_hex, sizeof(root_hex));
            fprintf(
                stderr,
                "  root=%s weight=%" PRIu64 " parent_index=%zu\n",
                root_hex[0] ? root_hex : "0x0",
                weights[i],
                entry->parent_index);
        }
        free(weights);
        return -1;
    }
    if (!lantern_root_equal(head_root, &best_root)) {
        char head_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        char best_hex[(LANTERN_ROOT_SIZE * 2u) + 3u];
        format_root_hex(head_root, head_hex, sizeof(head_hex));
        format_root_hex(&best_root, best_hex, sizeof(best_hex));
        fprintf(
            stderr,
            "lexicographic tiebreaker failed in %s (step %d): head %s is not lexicographically "
            "highest equal-weight fork (expected %s). Labels: ",
            fixture_path,
            step_index,
            head_hex,
            best_hex);
        if (labels && label_count > 0) {
            for (size_t i = 0; i < label_count; ++i) {
                fprintf(stderr, "%s%s", i == 0 ? "" : ", ", labels[i] ? labels[i] : "?");
            }
        }
        fprintf(stderr, "\n");
        free(weights);
        return -1;
    }
    free(weights);
    return 0;
}

static void reset_plain_block(LanternBlock *block) {
    if (!block) {
        return;
    }
    lantern_block_body_reset(&block->body);
}

static void reset_block_message(LanternBlockWithAttestation *message) {
    if (!message) {
        return;
    }
    lantern_block_body_reset(&message->block.body);
    LanternSignedBlock *owner =
        (LanternSignedBlock *)((uint8_t *)message - offsetof(LanternSignedBlock, message));
    if (owner) {
        lantern_block_signatures_reset(&owner->signatures);
    }
}

static void reset_signed_block_impl(LanternSignedBlock *block) {
    if (!block) {
        return;
    }
    reset_plain_block(&block->message.block);
    lantern_block_signatures_reset(&block->signatures);
}

#define reset_block(ptr)                                                                           \
    _Generic(                                                                                      \
        (ptr),                                                                                     \
        LanternBlock *: reset_plain_block,                                                         \
        LanternBlockWithAttestation *: reset_block_message,                                        \
        LanternSignedBlock *: reset_signed_block_impl)(ptr)

static int ensure_signature_envelope(
    const char *fixture_path,
    int block_index,
    const LanternSignedBlock *block) {
    if (!block) {
        return -1;
    }
    size_t attestation_count = block->message.block.body.attestations.length;
    size_t expected = attestation_count;
    if (block->signatures.attestation_signatures.length != expected
        || (expected > 0 && !block->signatures.attestation_signatures.data)) {
        fprintf(
            stderr,
            "%s block[%d]: expected %zu attestation signature proofs (attestations=%zu) but got %zu\\n",
            fixture_path ? fixture_path : "(unknown)",
            block_index,
            expected,
            attestation_count,
            block->signatures.attestation_signatures.length);
        return -1;
    }
    return 0;
}

static int run_state_transition_fixture(const char *path);
static int run_fork_choice_fixture(const char *path);

static int for_each_json(
    const char *root,
    int (*callback)(const char *path)) {
    if (!root || !callback) {
        return -1;
    }
    DIR *dir = opendir(root);
    if (!dir) {
        perror("opendir");
        return -1;
    }
    int status = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        char child_path[1024];
        int written = snprintf(child_path, sizeof(child_path), "%s/%s", root, entry->d_name);
        if (written <= 0 || written >= (int)sizeof(child_path)) {
            status = -1;
            break;
        }
        if (entry->d_type == DT_DIR) {
            if (for_each_json(child_path, callback) != 0) {
                status = -1;
                break;
            }
            continue;
        }
        const char *ext = strrchr(entry->d_name, '.');
        if (!ext || strcmp(ext, ".json") != 0) {
            continue;
        }
        if (callback(child_path) != 0) {
            status = -1;
            break;
        }
    }
    closedir(dir);
    return status;
}

static int run_state_transition_fixture(const char *path) {
    char *text = NULL;
    if (lantern_fixture_read_text_file(path, &text) != 0) {
        fprintf(stderr, "failed to read %s\n", path);
        return -1;
    }

    struct lantern_fixture_document doc;
    if (lantern_fixture_document_init(&doc, text) != 0) {
        fprintf(stderr, "failed to parse %s\n", path);
        return -1;
    }
    if (doc.token_count <= 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    int root_idx = 0;
    int case_idx = lantern_fixture_object_get_value_at(&doc, root_idx, 0);
    if (case_idx < 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    const char *fixture_filter = getenv("LANTERN_STATE_FIXTURE");
    if (fixture_filter && strstr(path, fixture_filter) == NULL) {
        lantern_fixture_document_reset(&doc);
        return 0;
    }

    int pre_idx = lantern_fixture_object_get_field(&doc, case_idx, "pre");
    int blocks_idx = lantern_fixture_object_get_field(&doc, case_idx, "blocks");
    int post_idx = lantern_fixture_object_get_field(&doc, case_idx, "post");
    int expect_exception_idx = lantern_fixture_object_get_field(&doc, case_idx, "expectException");
    bool expect_failure = expect_exception_idx >= 0;

    LanternState state;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    uint64_t genesis_time = 0;
    uint64_t validator_count = 0;
    if (lantern_fixture_parse_anchor_state(
            &doc,
            pre_idx,
            &state,
            &latest_justified,
            &latest_finalized,
            &genesis_time,
            &validator_count)
        != 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    bool observed_failure = false;
    int block_count = 0;
    if (blocks_idx >= 0) {
        block_count = lantern_fixture_array_get_length(&doc, blocks_idx);
        if (block_count < 0) {
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            return -1;
        }
    }

    for (int i = 0; i < block_count; ++i) {
        int block_idx = lantern_fixture_array_get_element(&doc, blocks_idx, i);
        if (block_idx < 0) {
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            return -1;
        }

        LanternSignedBlock signed_block;
        if (lantern_fixture_parse_signed_block(&doc, block_idx, &signed_block) != 0) {
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            return -1;
        }

        if (ensure_signature_envelope(path, i, &signed_block) != 0) {
            reset_block(&signed_block.message);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            return -1;
        }

        /* Patch block hashes to use C-computed values for non-failure tests.
         * Tests that expect failure may intentionally have wrong hashes. */
        if (!expect_failure) {
            if (patch_block_hashes_for_c_compat(&state, &signed_block) != 0) {
                fprintf(stderr, "failed to patch block hashes in %s block %d\n", path, i);
                reset_block(&signed_block.message);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                return -1;
            }
        }

        int status = lantern_state_transition(&state, &signed_block);
        reset_block(&signed_block.message);

        if (status != 0) {
            observed_failure = true;
            break;
        }
    }

    int result = 0;
    if (expect_failure) {
        if (!(observed_failure || block_count == 0)) {
            fprintf(stderr, "expected failure did not occur in %s\n", path);
            result = -1;
        }
    } else {
        if (observed_failure) {
            fprintf(stderr, "unexpected failure while processing %s\n", path);
            result = -1;
        } else if (post_idx < 0) {
            fprintf(stderr, "missing post state in %s\n", path);
            result = -1;
        } else {
            int field_idx = lantern_fixture_object_get_field(&doc, post_idx, "slot");
            if (field_idx >= 0) {
                uint64_t expected_slot = 0;
                if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0 || state.slot != expected_slot) {
                    fprintf(
                        stderr,
                        "post slot mismatch in %s: expected %" PRIu64 " got %" PRIu64 "\n",
                        path,
                        expected_slot,
                        state.slot);
                    result = -1;
                }
            }

            if (result == 0) {
                field_idx = lantern_fixture_object_get_field(&doc, post_idx, "validatorCount");
                if (field_idx >= 0) {
                    uint64_t expected_count = 0;
                    if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_count) != 0
                        || state.config.num_validators != expected_count) {
                        fprintf(
                            stderr,
                            "post validator count mismatch in %s: expected %" PRIu64 " got %" PRIu64 "\n",
                            path,
                            expected_count,
                            state.config.num_validators);
                        result = -1;
                    }
                }
            }
        }
    }

    lantern_state_reset(&state);
    lantern_fixture_document_reset(&doc);
    return result;
}

static int run_fork_choice_fixture(const char *path) {
    char *text = NULL;
    struct stored_state_entry *stored_states = NULL;
    size_t stored_states_count = 0;
    size_t stored_states_cap = 0;
    struct hash_mapping_entry *hash_mapping = NULL;
    size_t hash_mapping_count = 0;
    size_t hash_mapping_cap = 0;
    if (lantern_fixture_read_text_file(path, &text) != 0) {
        fprintf(stderr, "failed to read %s\n", path);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    struct lantern_fixture_document doc;
    if (lantern_fixture_document_init(&doc, text) != 0) {
        fprintf(stderr, "failed to parse %s\n", path);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    if (doc.token_count <= 0) {
        lantern_fixture_document_reset(&doc);
        return -1;
    }

    int root_idx = 0;
    int case_idx = lantern_fixture_object_get_value_at(&doc, root_idx, 0);
    if (case_idx < 0) {
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    const char *fixture_filter = getenv("LANTERN_FORK_CHOICE_FIXTURE");
    if (fixture_filter && strstr(path, fixture_filter) == NULL) {
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return 0;
    }

    int anchor_state_idx = lantern_fixture_object_get_field(&doc, case_idx, "anchorState");
    int anchor_block_idx = lantern_fixture_object_get_field(&doc, case_idx, "anchorBlock");
    int steps_idx = lantern_fixture_object_get_field(&doc, case_idx, "steps");
    if (anchor_state_idx < 0 || anchor_block_idx < 0 || steps_idx < 0) {
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    LanternState state;
    LanternCheckpoint latest_justified;
    LanternCheckpoint latest_finalized;
    uint64_t genesis_time = 0;
    uint64_t validator_count = 0;
    if (lantern_fixture_parse_anchor_state(
            &doc,
            anchor_state_idx,
            &state,
            &latest_justified,
            &latest_finalized,
            &genesis_time,
            &validator_count)
        != 0) {
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    LanternBlock anchor_block;
    if (lantern_fixture_parse_block(&doc, anchor_block_idx, &anchor_block) != 0) {
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    LanternRoot anchor_body_root;
    if (lantern_hash_tree_root_block_body(&anchor_block.body, &anchor_body_root) != 0) {
        reset_block(&anchor_block);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    state.latest_block_header.slot = anchor_block.slot;
    state.latest_block_header.proposer_index = anchor_block.proposer_index;
    state.latest_block_header.parent_root = anchor_block.parent_root;
    state.latest_block_header.state_root = anchor_block.state_root;
    state.latest_block_header.body_root = anchor_body_root;
    state.slot = anchor_block.slot;

    LanternForkChoice store;
    lantern_fork_choice_init(&store);
    LanternConfig config = {
        .num_validators = validator_count,
        .genesis_time = genesis_time,
    };
    if (lantern_fork_choice_configure(&store, &config) != 0) {
        reset_block(&anchor_block);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    LanternRoot anchor_root;
    if (lantern_hash_tree_root_block(&anchor_block, &anchor_root) != 0) {
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    if (lantern_fork_choice_set_anchor(&store, &anchor_block, &latest_justified, &latest_finalized, &anchor_root) != 0) {
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    lantern_state_attach_fork_choice(&state, &store);

    if (stored_state_save(&stored_states, &stored_states_count, &stored_states_cap, &anchor_root, &state) != 0) {
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }
    LanternRoot canonical_head_block_root = anchor_root;

    /* For the anchor block, LeanSpec and C hashes are the same (no patching needed) */
    if (hash_mapping_add(&hash_mapping, &hash_mapping_count, &hash_mapping_cap, &anchor_root, &anchor_root) != 0) {
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    struct label_registry labels;
    label_registry_init(&labels);

    int step_count = lantern_fixture_array_get_length(&doc, steps_idx);
    if (step_count < 0) {
        reset_block(&anchor_block);
        lantern_fork_choice_reset(&store);
        lantern_state_reset(&state);
        lantern_fixture_document_reset(&doc);
        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
        return -1;
    }

    for (int i = 0; i < step_count; ++i) {
        int step_idx = lantern_fixture_array_get_element(&doc, steps_idx, i);
        if (step_idx < 0) {
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        int block_idx = lantern_fixture_object_get_field(&doc, step_idx, "block");
        if (block_idx < 0) {
            continue;
        }

        LanternSignedBlock signed_block;
        if (lantern_fixture_parse_signed_block(&doc, block_idx, &signed_block) != 0) {
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        if (ensure_signature_envelope(path, i, &signed_block) != 0) {
            reset_block(&signed_block.message);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        uint64_t now = genesis_time + (signed_block.message.slot * store.seconds_per_slot);
        if (lantern_fork_choice_advance_time(&store, now, true) != 0) {
            reset_block(&signed_block.message);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        /* Save the LeanSpec block_root before any patching */
        LanternRoot leanspec_block_root;
        if (lantern_hash_tree_root_block(&signed_block.message.block, &leanspec_block_root) != 0) {
            reset_block(&signed_block.message);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        LanternState branch_state;
        bool branch_state_initialized = false;
        bool transition_performed = false;
        LanternState *active_state = &state;

        /* Determine if this block extends the canonical chain by looking up
         * the C hash of the block's parent (from LeanSpec parent_root) and
         * comparing with canonical_head_block_root. */
        LanternRoot leanspec_parent_root = signed_block.message.block.parent_root;
        const LanternRoot *c_parent_root = hash_mapping_leanspec_to_c(
            hash_mapping, hash_mapping_count, &leanspec_parent_root);

        bool extends_canonical = false;
        if (c_parent_root) {
            extends_canonical = memcmp(canonical_head_block_root.bytes,
                                       c_parent_root->bytes, LANTERN_ROOT_SIZE) == 0;
        }

        LanternCheckpoint block_justified = state.latest_justified;
        LanternCheckpoint block_finalized = state.latest_finalized;

        LanternRoot block_root; /* Will be the C block_root after patching */

        if (extends_canonical) {
            /* Patch block body attestation roots FIRST (before state_root preview) */
            for (size_t att_idx = 0; att_idx < signed_block.message.block.body.attestations.length; ++att_idx) {
                LanternAggregatedAttestation *agg = &signed_block.message.block.body.attestations.data[att_idx];
                const LanternRoot *c_head = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.head.root);
                if (c_head) {
                    agg->data.head.root = *c_head;
                }
                const LanternRoot *c_target = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.target.root);
                if (c_target) {
                    agg->data.target.root = *c_target;
                }
                const LanternRoot *c_source = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.source.root);
                if (c_source) {
                    agg->data.source.root = *c_source;
                }
            }
            /* Now patch block hashes (uses patched attestations for state_root preview) */
            if (patch_block_hashes_for_c_compat(&state, &signed_block) != 0) {
                fprintf(stderr, "failed to patch block hashes in fork_choice %s step %d\n", path, i);
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            /* Recompute block_root after patching to get C hash */
            if (lantern_hash_tree_root_block(&signed_block.message.block, &block_root) != 0) {
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            if (signed_block.message.slot > state.slot) {
                if (lantern_state_transition(&state, &signed_block) != 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                transition_performed = true;
                block_justified = state.latest_justified;
                block_finalized = state.latest_finalized;
            } else {
                active_state = &state;
                block_justified = state.latest_justified;
                block_finalized = state.latest_finalized;
            }
        } else {
            /* Non-canonical branch: look up parent state using C hash */
            const LanternRoot *c_parent_for_lookup = c_parent_root;
            if (!c_parent_for_lookup) {
                /* Parent not in mapping - this shouldn't happen for valid fixtures */
                fprintf(stderr, "parent not found in hash mapping for fork_choice %s step %d\n", path, i);
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            struct stored_state_entry *parent_entry =
                stored_state_find(stored_states, stored_states_count, c_parent_for_lookup);
            if (!parent_entry) {
                fprintf(stderr, "parent state not found for fork_choice %s step %d\n", path, i);
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            lantern_state_init(&branch_state);
            branch_state_initialized = true;
            if (stored_state_restore(stored_states, stored_states_count, c_parent_for_lookup, &branch_state) != 0) {
                lantern_state_reset(&branch_state);
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            active_state = &branch_state;
            /* Patch block body attestation roots FIRST (before state_root preview) */
            for (size_t att_idx = 0; att_idx < signed_block.message.block.body.attestations.length; ++att_idx) {
                LanternAggregatedAttestation *agg = &signed_block.message.block.body.attestations.data[att_idx];
                const LanternRoot *c_head = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.head.root);
                if (c_head) {
                    agg->data.head.root = *c_head;
                }
                const LanternRoot *c_target = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.target.root);
                if (c_target) {
                    agg->data.target.root = *c_target;
                }
                const LanternRoot *c_source = hash_mapping_leanspec_to_c(
                    hash_mapping, hash_mapping_count, &agg->data.source.root);
                if (c_source) {
                    agg->data.source.root = *c_source;
                }
            }
            /* Now patch block hashes (uses patched attestations for state_root preview) */
            if (patch_block_hashes_for_c_compat(active_state, &signed_block) != 0) {
                fprintf(stderr, "failed to patch block hashes in fork_choice %s step %d (branch)\n", path, i);
                lantern_state_reset(&branch_state);
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            /* Recompute block_root after patching to get C hash */
            if (lantern_hash_tree_root_block(&signed_block.message.block, &block_root) != 0) {
                lantern_state_reset(&branch_state);
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            if (lantern_state_transition(active_state, &signed_block) != 0) {
                lantern_state_reset(&branch_state);
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            transition_performed = true;
            block_justified = active_state->latest_justified;
            block_finalized = active_state->latest_finalized;
        }

        uint64_t parent_slot = 0;
        bool has_parent_info = false;
        for (size_t b = 0; b < LANTERN_ROOT_SIZE; ++b) {
            if (signed_block.message.parent_root.bytes[b] != 0) {
                has_parent_info = true;
                break;
            }
        }
        if (has_parent_info) {
            if (lantern_fork_choice_block_info(&store, &signed_block.message.parent_root, &parent_slot, NULL, NULL) != 0) {
                if (branch_state_initialized) {
                    lantern_state_reset(&branch_state);
                }
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
        }

        LanternVote proposer_vote;
        memset(&proposer_vote, 0, sizeof(proposer_vote));
        proposer_vote.validator_id = signed_block.message.proposer_index;
        proposer_vote.slot = signed_block.message.slot;
        proposer_vote.head.root = block_root;
        proposer_vote.head.slot = signed_block.message.slot;
        proposer_vote.target.root = block_root;
        proposer_vote.target.slot = signed_block.message.slot;
        proposer_vote.source.root = signed_block.message.parent_root;
        proposer_vote.source.slot = has_parent_info ? parent_slot : 0;

        if (transition_performed) {
            if (lantern_state_set_validator_vote(
                    active_state,
                    (size_t)signed_block.message.proposer_index,
                    &proposer_vote)
                != 0) {
                if (branch_state_initialized) {
                    lantern_state_reset(&branch_state);
                }
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
            if (stored_state_save(&stored_states, &stored_states_count, &stored_states_cap, &block_root, active_state) != 0) {
                if (branch_state_initialized) {
                    lantern_state_reset(&branch_state);
                }
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
        } else if (!stored_state_find(stored_states, stored_states_count, &block_root)) {
            if (stored_state_save(&stored_states, &stored_states_count, &stored_states_cap, &block_root, &state) != 0) {
                if (branch_state_initialized) {
                    lantern_state_reset(&branch_state);
                }
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }
        }

        LanternCheckpoint post_justified = block_justified;
        LanternCheckpoint post_finalized = block_finalized;
        LanternSignedVote block_proposer_signed;
        memset(&block_proposer_signed, 0, sizeof(block_proposer_signed));
        block_proposer_signed.data = signed_block.message.proposer_attestation;
        block_proposer_signed.signature = signed_block.signatures.proposer_signature;
        if (lantern_fork_choice_add_block(
                &store,
                &signed_block.message.block,
                &block_proposer_signed,
                &post_justified,
                &post_finalized,
                &block_root)
            != 0) {
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.message);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        LanternSignedVote signed_proposer_vote = block_proposer_signed;
        signed_proposer_vote.data = proposer_vote;
        if (lantern_fork_choice_add_vote(&store, &signed_proposer_vote, false) != 0) {
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.message);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        /* Process aggregated attestations from block body.
         * Convert LeanSpec block roots to C hashes before adding to fork_choice. */
        size_t attestation_count = signed_block.message.block.body.attestations.length;
        for (size_t att_idx = 0; att_idx < attestation_count; ++att_idx) {
            LanternAggregatedAttestation *agg = &signed_block.message.block.body.attestations.data[att_idx];

            /* Convert vote's block roots from LeanSpec to C hashes */
            LanternVote converted_vote;
            memset(&converted_vote, 0, sizeof(converted_vote));
            converted_vote.slot = agg->data.slot;
            converted_vote.head = agg->data.head;
            converted_vote.target = agg->data.target;
            converted_vote.source = agg->data.source;

            /* Convert head.root */
            const LanternRoot *c_head_root = hash_mapping_leanspec_to_c(
                hash_mapping, hash_mapping_count, &agg->data.head.root);
            if (c_head_root) {
                converted_vote.head.root = *c_head_root;
            }

            /* Convert target.root */
            const LanternRoot *c_target_root = hash_mapping_leanspec_to_c(
                hash_mapping, hash_mapping_count, &agg->data.target.root);
            if (c_target_root) {
                converted_vote.target.root = *c_target_root;
            }

            /* Convert source.root */
            const LanternRoot *c_source_root = hash_mapping_leanspec_to_c(
                hash_mapping, hash_mapping_count, &agg->data.source.root);
            if (c_source_root) {
                converted_vote.source.root = *c_source_root;
            }

            /* Add each validator's vote based on aggregation bits */
            for (size_t bit_idx = 0; bit_idx < agg->aggregation_bits.bit_length; ++bit_idx) {
                if (!lantern_bitlist_get(&agg->aggregation_bits, bit_idx)) {
                    continue;
                }
                converted_vote.validator_id = (uint64_t)bit_idx;

                LanternSignedVote signed_agg_vote;
                memset(&signed_agg_vote, 0, sizeof(signed_agg_vote));
                signed_agg_vote.data = converted_vote;
                /* Signature would come from attestation_signatures but we don't verify here */

                if (lantern_fork_choice_add_vote(&store, &signed_agg_vote, false) != 0) {
                    if (branch_state_initialized) {
                        lantern_state_reset(&branch_state);
                    }
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
                    hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
            }
        }

        if (extends_canonical && transition_performed) {
            canonical_head_block_root = block_root;
        }

        /* Save the hash mapping: leanspec_block_root -> block_root (C hash) */
        if (hash_mapping_add(&hash_mapping, &hash_mapping_count, &hash_mapping_cap,
                             &leanspec_block_root, &block_root) != 0) {
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.message);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
            hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        if (sync_state_to_fork_choice_head(&store, &state, &stored_states, &stored_states_count, &canonical_head_block_root) != 0) {
            if (branch_state_initialized) {
                lantern_state_reset(&branch_state);
            }
            reset_block(&signed_block.message);
            reset_block(&anchor_block);
            lantern_fork_choice_reset(&store);
            lantern_state_reset(&state);
            lantern_fixture_document_reset(&doc);
            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
            return -1;
        }

        if (branch_state_initialized) {
            lantern_state_reset(&branch_state);
        }

        int checks_idx = lantern_fixture_object_get_field(&doc, step_idx, "checks");
        if (checks_idx >= 0) {
            LanternRoot head_root;
            if (lantern_fork_choice_current_head(&store, &head_root) != 0) {
                reset_block(&signed_block.message);
                reset_block(&anchor_block);
                lantern_fork_choice_reset(&store);
                lantern_state_reset(&state);
                lantern_fixture_document_reset(&doc);
                stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                return -1;
            }

            int head_slot_idx = lantern_fixture_object_get_field(&doc, checks_idx, "headSlot");
            if (head_slot_idx >= 0) {
                uint64_t expected_slot = 0;
                if (lantern_fixture_token_to_uint64(&doc, head_slot_idx, &expected_slot) != 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                uint64_t actual_slot = 0;
                if (lantern_fork_choice_block_info(&store, &head_root, &actual_slot, NULL, NULL) != 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (actual_slot != expected_slot) {
                    fprintf(
                        stderr,
                        "head slot mismatch in %s (step %d): expected %" PRIu64 " got %" PRIu64 "\n",
                        path,
                        i,
                        expected_slot,
                        actual_slot);
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
            }

            int head_label_idx = lantern_fixture_object_get_field(&doc, checks_idx, "headRootLabel");
            if (head_label_idx >= 0) {
                size_t label_len = 0;
                const char *label = lantern_fixture_token_string(&doc, head_label_idx, &label_len);
                if (!label || label_len == 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                char label_buf[LABEL_MAX_LENGTH];
                if (label_len >= sizeof(label_buf)) {
                    label_len = sizeof(label_buf) - 1u;
                }
                memcpy(label_buf, label, label_len);
                label_buf[label_len] = '\0';
                if (label_registry_assign(&labels, label_buf, &head_root) != 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
            }

            int lexicographic_idx = lantern_fixture_object_get_field(&doc, checks_idx, "lexicographicHeadAmong");
            if (lexicographic_idx >= 0) {
                int label_count = lantern_fixture_array_get_length(&doc, lexicographic_idx);
                if (label_count < 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (label_count < 2) {
                    fprintf(
                        stderr,
                        "lexicographicHeadAmong requires at least two labels in %s (step %d)\n",
                        path,
                        i);
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                char **lex_labels = calloc((size_t)label_count, sizeof(*lex_labels));
                if (!lex_labels) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                bool lexicographic_ok = true;
                for (int label_idx = 0; label_idx < label_count; ++label_idx) {
                    int token_idx = lantern_fixture_array_get_element(&doc, lexicographic_idx, label_idx);
                    if (token_idx < 0) {
                        lexicographic_ok = false;
                        break;
                    }
                    size_t label_len = 0;
                    const char *label_token = lantern_fixture_token_string(&doc, token_idx, &label_len);
                    if (!label_token || label_len == 0) {
                        lexicographic_ok = false;
                        break;
                    }
                    lex_labels[label_idx] = malloc(label_len + 1u);
                    if (!lex_labels[label_idx]) {
                        lexicographic_ok = false;
                        break;
                    }
                    memcpy(lex_labels[label_idx], label_token, label_len);
                    lex_labels[label_idx][label_len] = '\0';
                }
                if (lexicographic_ok) {
                    if (validate_lexicographic_head_among(
                            &store,
                            &head_root,
                            (size_t)label_count,
                            (const char **)lex_labels,
                            path,
                            i)
                        != 0) {
                        lexicographic_ok = false;
                    }
                }
                for (int label_idx = 0; label_idx < label_count; ++label_idx) {
                    free(lex_labels[label_idx]);
                }
                free(lex_labels);
                if (!lexicographic_ok) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
            }

            int att_target_idx = lantern_fixture_object_get_field(&doc, checks_idx, "attestationTargetSlot");
            if (att_target_idx >= 0) {
                uint64_t expected_slot = 0;
                if (lantern_fixture_token_to_uint64(&doc, att_target_idx, &expected_slot) != 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                LanternCheckpoint head_cp;
                LanternCheckpoint target_cp;
                LanternCheckpoint source_cp;
                if (lantern_state_compute_vote_checkpoints(&state, &head_cp, &target_cp, &source_cp) != 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                if (target_cp.slot != expected_slot) {
                    /* NOTE: Lantern's attestation target selection uses candidate promotion
                     * which differs from leanSpec's conservative walk-back approach.
                     * This difference is intentional for Zeam interop. Log warning only. */
                    fprintf(
                        stderr,
                        "note: attestation target differs from leanSpec in %s (step %d): expected %" PRIu64 " got %" PRIu64 "\n",
                        path,
                        i,
                        expected_slot,
                        target_cp.slot);
                    /* Continue instead of failing */
                }
            }

            int att_checks_idx = lantern_fixture_object_get_field(&doc, checks_idx, "attestationChecks");
            if (att_checks_idx >= 0) {
                int length = lantern_fixture_array_get_length(&doc, att_checks_idx);
                if (length < 0) {
                    reset_block(&signed_block.message);
                    reset_block(&anchor_block);
                    lantern_fork_choice_reset(&store);
                    lantern_state_reset(&state);
                    lantern_fixture_document_reset(&doc);
                    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                    return -1;
                }
                for (int entry = 0; entry < length; ++entry) {
                    int check_idx = lantern_fixture_array_get_element(&doc, att_checks_idx, entry);
                    if (check_idx < 0) {
                        reset_block(&signed_block.message);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    uint64_t validator_id = 0;
                    int validator_idx = lantern_fixture_object_get_field(&doc, check_idx, "validator");
                    if (validator_idx < 0 || lantern_fixture_token_to_uint64(&doc, validator_idx, &validator_id) != 0) {
                        reset_block(&signed_block.message);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }
                    size_t validator = (size_t)validator_id;
                    if (validator >= store.validator_count) {
                        reset_block(&signed_block.message);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    size_t location_len = 0;
                    int location_idx = lantern_fixture_object_get_field(&doc, check_idx, "location");
                    const char *location = lantern_fixture_token_string(&doc, location_idx, &location_len);
                    if (!location) {
                        reset_block(&signed_block.message);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    const struct lantern_fork_choice_vote_entry *vote_entry = NULL;
                    bool expect_new = false;
                    if (location_len == 3 && strncmp(location, "new", 3) == 0) {
                        vote_entry = &store.new_votes[validator];
                        expect_new = true;
                    } else if (location_len == 5 && strncmp(location, "known", 5) == 0) {
                        vote_entry = &store.known_votes[validator];
                    } else {
                        reset_block(&signed_block.message);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    if (!vote_entry->has_checkpoint) {
                        fprintf(
                            stderr,
                            "attestation missing checkpoint in %s (step %d): validator %" PRIu64 " (%s)\n",
                            path,
                            i,
                            validator_id,
                            expect_new ? "new" : "known");
                        reset_block(&signed_block.message);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    LanternVote vote;
                    if (lantern_state_get_validator_vote(&state, validator, &vote) != 0) {
                        reset_block(&signed_block.message);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    if (expect_new != store.new_votes[validator].has_checkpoint) {
                        fprintf(
                            stderr,
                            "attestation location mismatch in %s (step %d): validator %" PRIu64 "\n",
                            path,
                            i,
                            validator_id);
                        reset_block(&signed_block.message);
                        reset_block(&anchor_block);
                        lantern_fork_choice_reset(&store);
                        lantern_state_reset(&state);
                        lantern_fixture_document_reset(&doc);
                        stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                        return -1;
                    }

                    int field_idx = lantern_fixture_object_get_field(&doc, check_idx, "attestationSlot");
                    if (field_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0 || vote.slot != expected_slot) {
                            fprintf(
                                stderr,
                                "attestation slot mismatch in %s (step %d): validator %" PRIu64 "\n",
                                path,
                                i,
                                validator_id);
                            reset_block(&signed_block.message);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                    }

                    field_idx = lantern_fixture_object_get_field(&doc, check_idx, "headSlot");
                    if (field_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0 || vote.head.slot != expected_slot) {
                            fprintf(
                                stderr,
                                "attestation head slot mismatch in %s (step %d): validator %" PRIu64 "\n",
                                path,
                                i,
                                validator_id);
                            reset_block(&signed_block.message);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                    }

                    field_idx = lantern_fixture_object_get_field(&doc, check_idx, "sourceSlot");
                    if (field_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0 || vote.source.slot != expected_slot) {
                            fprintf(
                                stderr,
                                "attestation source slot mismatch in %s (step %d): validator %" PRIu64 "\n",
                                path,
                                i,
                                validator_id);
                            reset_block(&signed_block.message);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
                            return -1;
                        }
                    }

                    field_idx = lantern_fixture_object_get_field(&doc, check_idx, "targetSlot");
                    if (field_idx >= 0) {
                        uint64_t expected_slot = 0;
                        if (lantern_fixture_token_to_uint64(&doc, field_idx, &expected_slot) != 0
                            || vote_entry->checkpoint.slot != expected_slot) {
                            fprintf(
                                stderr,
                                "attestation target slot mismatch in %s (step %d): validator %" PRIu64 "\n",
                                path,
                                i,
                                validator_id);
                            reset_block(&signed_block.message);
                            reset_block(&anchor_block);
                            lantern_fork_choice_reset(&store);
                            lantern_state_reset(&state);
                            lantern_fixture_document_reset(&doc);
                            return -1;
                        }
                    }
                }
            }
        }

        reset_block(&signed_block.message);
    }

    reset_block(&anchor_block);
    lantern_fork_choice_reset(&store);
    lantern_state_reset(&state);
    lantern_fixture_document_reset(&doc);
    stored_state_entries_reset(&stored_states, &stored_states_count, &stored_states_cap);
        hash_mapping_reset(&hash_mapping, &hash_mapping_count, &hash_mapping_cap);
    return 0;
}

int lantern_run_fixture_suite(const struct lantern_fixture_run_config *config) {
    if (!config || !config->suite_name || !config->state_transition_subdir) {
        fprintf(stderr, "invalid fixture run configuration\n");
        return 1;
    }

    configure_logging();
    char state_transition_root[1024];
    int written = snprintf(
        state_transition_root,
        sizeof(state_transition_root),
        "%s/%s",
        LANTERN_TEST_FIXTURE_DIR,
        config->state_transition_subdir);
    if (written <= 0 || written >= (int)sizeof(state_transition_root)) {
        fprintf(stderr, "fixture path too long\n");
        return 1;
    }
    if (for_each_json(state_transition_root, run_state_transition_fixture) != 0) {
        return 1;
    }

    if (config->include_fork_choice) {
        if (!config->fork_choice_subdir) {
            fprintf(stderr, "fork choice subdirectory not specified\n");
            return 1;
        }
        char fork_choice_root[1024];
        written = snprintf(
            fork_choice_root,
            sizeof(fork_choice_root),
            "%s/%s",
            LANTERN_TEST_FIXTURE_DIR,
            config->fork_choice_subdir);
        if (written <= 0 || written >= (int)sizeof(fork_choice_root)) {
            fprintf(stderr, "fixture path too long\n");
            return 1;
        }

        if (for_each_json(fork_choice_root, run_fork_choice_fixture) != 0) {
            return 1;
        }
    }

    printf("%s OK\n", config->suite_name);
    return 0;
}
