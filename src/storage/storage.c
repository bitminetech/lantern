#include "lantern/storage/storage.h"

#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#include <dirent.h>

#if defined(_WIN32)
#include <direct.h>
#include <io.h>
#endif

#include "lantern/consensus/hash.h"
#include "lantern/consensus/ssz.h"
#include "lantern/networking/messages.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"
#include "ssz_constants.h"

#define LANTERN_STORAGE_VOTES_MAGIC "LNVOTES\0"
#define LANTERN_STORAGE_VOTES_VERSION 3u
#define LANTERN_STORAGE_BLOCKS_DIR "blocks"
#define LANTERN_STORAGE_INVALID_BLOCKS_DIR "invalid_blocks"
#define LANTERN_STORAGE_INVALID_GOSSIP_DIR "invalid_gossip"
#define LANTERN_STORAGE_STATES_DIR "states"
#define LANTERN_STORAGE_INDICES_DIR "indices"
#define LANTERN_STORAGE_SLOT_INDEX_DIR "slots"
#define LANTERN_STORAGE_STATE_FILE "state.ssz"
#define LANTERN_STORAGE_FINALIZED_STATE_FILE "finalized_state.ssz"
#define LANTERN_STORAGE_VOTES_FILE "votes.bin"
#define LANTERN_STORAGE_HEAD_FILE "head.bin"
#define LANTERN_STORAGE_CHECKPOINTS_FILE "checkpoints.bin"

#if defined(_WIN32)
#define LANTERN_STORAGE_PATH_SEP '\\'
#else
#define LANTERN_STORAGE_PATH_SEP '/'
#endif

struct lantern_storage_votes_header {
    char magic[8];
    uint32_t version;
    uint32_t reserved;
    uint64_t validator_count;
    uint64_t record_count;
};

struct lantern_storage_head_record {
    uint64_t slot;
    LanternRoot root;
};

struct lantern_storage_checkpoint_record {
    LanternCheckpoint justified;
    LanternCheckpoint finalized;
};

/*
 * Internal helpers for filesystem/path handling, SSZ size estimation, and
 * atomic file reads/writes.
 *
 * Public API: see include/lantern/storage/storage.h
 */

static int ensure_directory(const char *path) {
    if (!path) {
        return -1;
    }
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode) ? 0 : -1;
    }
#if defined(_WIN32)
    if (_mkdir(path) != 0 && errno != EEXIST) {
        return -1;
    }
#else
    if (mkdir(path, 0700) != 0 && errno != EEXIST) {
        return -1;
    }
#endif
    return 0;
}

static int join_path(const char *base, const char *leaf, char **out_path) {
    if (!base || !leaf || !out_path) {
        return -1;
    }
    const size_t base_len = strlen(base);
    const size_t leaf_len = strlen(leaf);
    bool needs_sep = false;
    if (base_len > 0) {
        const char tail = base[base_len - 1];
        needs_sep = (tail != '/' && tail != '\\');
    }
    const size_t total = base_len + (needs_sep ? 1u : 0u) + leaf_len + 1u;
    char *buffer = malloc(total);
    if (!buffer) {
        return -1;
    }
    memcpy(buffer, base, base_len);
    size_t offset = base_len;
    if (needs_sep) {
        buffer[offset++] = LANTERN_STORAGE_PATH_SEP;
    }
    memcpy(buffer + offset, leaf, leaf_len);
    buffer[offset + leaf_len] = '\0';
    *out_path = buffer;
    return 0;
}

static void free_path(char *path) {
    free(path);
}

static size_t bitlist_encoded_size(const struct lantern_bitlist *list) {
    if (!list) {
        return 0;
    }
    if (list->bit_length == 0) {
        return 1;
    }
    size_t byte_len = (list->bit_length + 7u) / 8u;
    bool needs_extra = (list->bit_length % 8u) == 0;
    return byte_len + (needs_extra ? 1u : 0u);
}

static size_t byte_list_encoded_size(const LanternByteList *list) {
    if (!list) {
        return 0;
    }
    if (list->length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return 0;
    }
    return list->length;
}

static size_t aggregated_attestation_encoded_size(const LanternAggregatedAttestation *attestation) {
    if (!attestation) {
        return 0;
    }
    if (attestation->aggregation_bits.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return 0;
    }
    size_t bits_size = bitlist_encoded_size(&attestation->aggregation_bits);
    if (bits_size == 0) {
        return 0;
    }
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_ATTESTATION_DATA_SSZ_SIZE;
    if (fixed_section > SIZE_MAX - bits_size) {
        return 0;
    }
    return fixed_section + bits_size;
}

static size_t aggregated_attestations_encoded_size(const LanternAggregatedAttestations *attestations) {
    if (!attestations) {
        return 0;
    }
    if (attestations->length == 0) {
        return 0;
    }
    if (attestations->length > LANTERN_MAX_ATTESTATIONS || !attestations->data) {
        return 0;
    }
    size_t offset_table = attestations->length * SSZ_BYTE_SIZE_OF_UINT32;
    size_t total = offset_table;
    for (size_t i = 0; i < attestations->length; ++i) {
        size_t entry_size = aggregated_attestation_encoded_size(&attestations->data[i]);
        if (entry_size == 0 || entry_size > SIZE_MAX - total) {
            return 0;
        }
        total += entry_size;
    }
    return total;
}

static size_t aggregated_signature_proof_encoded_size(const LanternAggregatedSignatureProof *proof) {
    if (!proof) {
        return 0;
    }
    if (proof->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return 0;
    }
    size_t participants_size = bitlist_encoded_size(&proof->participants);
    size_t proof_bytes = byte_list_encoded_size(&proof->proof_data);
    if (participants_size == 0 && proof->participants.bit_length != 0) {
        return 0;
    }
    size_t fixed_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    if (fixed_section > SIZE_MAX - participants_size) {
        return 0;
    }
    if (fixed_section + participants_size > SIZE_MAX - proof_bytes) {
        return 0;
    }
    return fixed_section + participants_size + proof_bytes;
}

static size_t attestation_signatures_encoded_size(const LanternAttestationSignatures *signatures) {
    if (!signatures) {
        return 0;
    }
    if (signatures->length == 0) {
        return 0;
    }
    if (signatures->length > LANTERN_MAX_BLOCK_SIGNATURES || !signatures->data) {
        return 0;
    }
    size_t offset_table = signatures->length * SSZ_BYTE_SIZE_OF_UINT32;
    size_t total = offset_table;
    for (size_t i = 0; i < signatures->length; ++i) {
        size_t entry_size = aggregated_signature_proof_encoded_size(&signatures->data[i]);
        if (entry_size == 0 || entry_size > SIZE_MAX - total) {
            return 0;
        }
        total += entry_size;
    }
    return total;
}

static size_t root_list_encoded_size(const struct lantern_root_list *list) {
    if (!list || list->length == 0) {
        return 0;
    }
    return list->length * LANTERN_ROOT_SIZE;
}

static size_t state_encoded_size(const LanternState *state) {
    if (!state) {
        return 0;
    }
    if (state->config.num_validators != (uint64_t)state->validator_count) {
        return 0;
    }
    size_t fixed = LANTERN_CONFIG_SSZ_SIZE
        + SSZ_BYTE_SIZE_OF_UINT64
        + LANTERN_BLOCK_HEADER_SSZ_SIZE
        + (2u * LANTERN_CHECKPOINT_SSZ_SIZE)
        + (5u * SSZ_BYTE_SIZE_OF_UINT32);
    size_t validator_bytes = 0;
    if (state->validator_count > 0) {
        if (!state->validators || state->validator_count > SIZE_MAX / LANTERN_VALIDATOR_SSZ_SIZE) {
            return 0;
        }
        validator_bytes = state->validator_count * LANTERN_VALIDATOR_SSZ_SIZE;
    }
    size_t variable = root_list_encoded_size(&state->historical_block_hashes)
        + bitlist_encoded_size(&state->justified_slots)
        + validator_bytes
        + root_list_encoded_size(&state->justification_roots)
        + bitlist_encoded_size(&state->justification_validators);
    return fixed + variable;
}

static size_t block_body_encoded_size(const LanternBlockBody *body) {
    if (!body) {
        return SSZ_BYTE_SIZE_OF_UINT32;
    }
    size_t att_count = body->attestations.length;
    size_t attestations_bytes = aggregated_attestations_encoded_size(&body->attestations);
    if (att_count > 0 && attestations_bytes == 0) {
        return 0;
    }
    return SSZ_BYTE_SIZE_OF_UINT32 + attestations_bytes;
}

static size_t block_encoded_size(const LanternBlock *block) {
    if (!block) {
        return 0;
    }
    size_t fixed = (SSZ_BYTE_SIZE_OF_UINT64 * 2u)
        + (LANTERN_ROOT_SIZE * 2u)
        + SSZ_BYTE_SIZE_OF_UINT32;
    size_t body_size = block_body_encoded_size(&block->body);
    if (body_size == 0) {
        return 0;
    }
    return fixed + body_size;
}

static size_t block_with_attestation_encoded_size(const LanternBlockWithAttestation *block) {
    size_t fixed = SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_VOTE_SSZ_SIZE;
    if (!block) {
        return fixed;
    }
    size_t block_size = block_encoded_size(&block->block);
    if (block_size == 0) {
        return 0;
    }
    return fixed + block_size;
}

static size_t block_signatures_encoded_size(const LanternBlockSignatures *signatures) {
    if (!signatures) {
        return 0;
    }
    size_t sig_count = signatures->attestation_signatures.length;
    size_t attestations_bytes = attestation_signatures_encoded_size(&signatures->attestation_signatures);
    if (sig_count > 0 && attestations_bytes == 0) {
        return 0;
    }
    return (SSZ_BYTE_SIZE_OF_UINT32 * 2u) + LANTERN_SIGNATURE_SIZE + attestations_bytes;
}

static size_t signed_block_encoded_size(const LanternSignedBlock *block) {
    if (!block) {
        return 0;
    }
    size_t offset_section = SSZ_BYTE_SIZE_OF_UINT32 * 2u;
    size_t message_size = block_with_attestation_encoded_size(&block->message);
    if (message_size == 0) {
        return 0;
    }
    size_t signatures_size = block_signatures_encoded_size(&block->signatures);
    if (signatures_size == 0) {
        return 0;
    }
    return offset_section + message_size + signatures_size;
}

static int write_atomic_file(const char *path, const uint8_t *data, size_t data_len) {
    if (!path || !data || data_len == 0) {
        return -1;
    }
    int rc = -1;
    FILE *fp = NULL;
    char *tmp_path = NULL;

    const size_t path_len = strlen(path);
    tmp_path = malloc(path_len + sizeof(".tmp"));
    if (!tmp_path) {
        goto cleanup;
    }
    memcpy(tmp_path, path, path_len);
    memcpy(tmp_path + path_len, ".tmp", sizeof(".tmp"));

    fp = fopen(tmp_path, "wb");
    if (!fp) {
        goto cleanup;
    }
    const size_t written = fwrite(data, 1u, data_len, fp);
    if (written != data_len) {
        goto cleanup;
    }
    if (fflush(fp) != 0) {
        goto cleanup;
    }
#if defined(_WIN32)
    if (_commit(_fileno(fp)) != 0) {
        goto cleanup;
    }
#else
    if (fsync(fileno(fp)) != 0) {
        goto cleanup;
    }
#endif
    const int close_rc = fclose(fp);
    fp = NULL;
    if (close_rc != 0) {
        goto cleanup;
    }
#if defined(_WIN32)
    if (remove(path) != 0 && errno != ENOENT) {
        goto cleanup;
    }
#endif
    if (rename(tmp_path, path) != 0) {
        goto cleanup;
    }
    rc = 0;

cleanup:
    if (fp) {
        fclose(fp);
    }
    free(tmp_path);
    return rc;
}

static int read_file_buffer(const char *path, uint8_t **out_data, size_t *out_len) {
    if (!path || !out_data || !out_len) {
        return -1;
    }
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return (errno == ENOENT) ? 1 : -1;
    }
    int rc = -1;
    uint8_t *buffer = NULL;

    if (fseek(fp, 0, SEEK_END) != 0) {
        goto cleanup;
    }
    const long file_size = ftell(fp);
    if (file_size < 0) {
        goto cleanup;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        goto cleanup;
    }
    if (file_size == 0) {
        rc = 1;
        goto cleanup;
    }
    buffer = malloc((size_t)file_size);
    if (!buffer) {
        goto cleanup;
    }
    const size_t read = fread(buffer, 1u, (size_t)file_size, fp);
    if (read != (size_t)file_size) {
        goto cleanup;
    }

    *out_data = buffer;
    *out_len = (size_t)file_size;
    buffer = NULL;
    rc = 0;

cleanup:
    fclose(fp);
    free(buffer);
    return rc;
}

static int build_blocks_dir(const char *data_dir, char **out_path) {
    return join_path(data_dir, LANTERN_STORAGE_BLOCKS_DIR, out_path);
}

static int build_invalid_blocks_dir(const char *data_dir, char **out_path) {
    return join_path(data_dir, LANTERN_STORAGE_INVALID_BLOCKS_DIR, out_path);
}

static int build_invalid_gossip_dir(const char *data_dir, char **out_path) {
    return join_path(data_dir, LANTERN_STORAGE_INVALID_GOSSIP_DIR, out_path);
}

static int build_states_dir(const char *data_dir, char **out_path) {
    return join_path(data_dir, LANTERN_STORAGE_STATES_DIR, out_path);
}

static int build_indices_dir(const char *data_dir, char **out_path) {
    return join_path(data_dir, LANTERN_STORAGE_INDICES_DIR, out_path);
}

static int build_slot_index_dir(const char *data_dir, char **out_path) {
    char *indices_dir = NULL;
    if (build_indices_dir(data_dir, &indices_dir) != 0) {
        return -1;
    }
    int rc = join_path(indices_dir, LANTERN_STORAGE_SLOT_INDEX_DIR, out_path);
    free_path(indices_dir);
    return rc;
}

static int format_utc_timestamp(char *buffer, size_t buffer_len) {
    if (!buffer || buffer_len == 0) {
        return -1;
    }

    struct timeval tv;
    if (gettimeofday(&tv, NULL) != 0) {
        return -1;
    }

    const time_t seconds = (time_t)tv.tv_sec;
    struct tm utc_tm;
#if defined(_WIN32)
    if (gmtime_s(&utc_tm, &seconds) != 0) {
        return -1;
    }
#else
    if (gmtime_r(&seconds, &utc_tm) == NULL) {
        return -1;
    }
#endif

    const int wrote = snprintf(
        buffer,
        buffer_len,
        "%04d%02d%02dT%02d%02d%02d.%06ldZ",
        utc_tm.tm_year + 1900,
        utc_tm.tm_mon + 1,
        utc_tm.tm_mday,
        utc_tm.tm_hour,
        utc_tm.tm_min,
        utc_tm.tm_sec,
        (long)tv.tv_usec);
    if (wrote < 0 || (size_t)wrote >= buffer_len) {
        return -1;
    }
    return 0;
}

static int sanitize_filename_component(const char *input, char *output, size_t output_len) {
    if (!input || !output || output_len == 0) {
        return -1;
    }

    size_t out_index = 0;
    for (size_t i = 0; input[i] != '\0'; ++i) {
        if (out_index + 1u >= output_len) {
            return -1;
        }
        const unsigned char ch = (unsigned char)input[i];
        if ((ch >= 'a' && ch <= 'z')
            || (ch >= 'A' && ch <= 'Z')
            || (ch >= '0' && ch <= '9')
            || ch == '-'
            || ch == '_') {
            output[out_index++] = (char)ch;
        } else {
            output[out_index++] = '_';
        }
    }

    if (out_index == 0) {
        return -1;
    }

    output[out_index] = '\0';
    return 0;
}

/**
 * Ensure all storage directories exist under `data_dir`.
 *
 * @param data_dir Base directory path.
 * @return 0 on success.
 * @return -1 on invalid parameters or filesystem errors.
 */
int lantern_storage_prepare(const char *data_dir) {
    if (!data_dir) {
        return -1;
    }

    int rc = -1;
    char *blocks_dir = NULL;
    char *invalid_blocks_dir = NULL;
    char *invalid_gossip_dir = NULL;
    char *states_dir = NULL;
    char *indices_dir = NULL;
    char *slot_dir = NULL;

    if (ensure_directory(data_dir) != 0) {
        goto cleanup;
    }
    if (build_blocks_dir(data_dir, &blocks_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(blocks_dir) != 0) {
        goto cleanup;
    }
    if (build_invalid_blocks_dir(data_dir, &invalid_blocks_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(invalid_blocks_dir) != 0) {
        goto cleanup;
    }
    if (build_invalid_gossip_dir(data_dir, &invalid_gossip_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(invalid_gossip_dir) != 0) {
        goto cleanup;
    }
    if (build_states_dir(data_dir, &states_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(states_dir) != 0) {
        goto cleanup;
    }
    if (build_indices_dir(data_dir, &indices_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(indices_dir) != 0) {
        goto cleanup;
    }
    if (build_slot_index_dir(data_dir, &slot_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(slot_dir) != 0) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    free_path(blocks_dir);
    free_path(invalid_blocks_dir);
    free_path(invalid_gossip_dir);
    free_path(states_dir);
    free_path(indices_dir);
    free_path(slot_dir);
    return rc;
}

/**
 * Persist `state` under `data_dir` using SSZ (`state.ssz`).
 *
 * @param data_dir Base directory path.
 * @param state State to persist.
 * @return 0 on success.
 * @return -1 on invalid parameters, encoding failure, or filesystem errors.
 */
int lantern_storage_save_state(const char *data_dir, const LanternState *state) {
    if (!data_dir || !state || state->config.num_validators == 0) {
        return -1;
    }
    int rc = -1;
    uint8_t *buffer = NULL;
    char *state_path = NULL;

    const size_t encoded_size = state_encoded_size(state);
    if (encoded_size == 0) {
        goto cleanup;
    }

    buffer = malloc(encoded_size);
    if (!buffer) {
        goto cleanup;
    }
    size_t written = 0;
    if (lantern_ssz_encode_state(state, buffer, encoded_size, &written) != 0 || written != encoded_size) {
        goto cleanup;
    }
    if (join_path(data_dir, LANTERN_STORAGE_STATE_FILE, &state_path) != 0) {
        goto cleanup;
    }
    rc = write_atomic_file(state_path, buffer, written);
    if (rc != 0) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    free_path(state_path);
    free(buffer);
    return rc;
}

/**
 * Load a persisted state from `data_dir/state.ssz`.
 *
 * On success, the contents of `state` are replaced.
 *
 * @param data_dir Base directory path.
 * @param state Output state (replaced on success).
 * @return 0 on success.
 * @return 1 if the state file is missing or empty.
 * @return -1 on invalid parameters or decode/validation errors.
 */
int lantern_storage_load_state(const char *data_dir, LanternState *state) {
    if (!data_dir || !state) {
        return -1;
    }

    int rc = -1;
    char *state_path = NULL;
    uint8_t *data = NULL;
    size_t data_len = 0;

    LanternState decoded;
    lantern_state_init(&decoded);
    bool decoded_owned = true;

    if (join_path(data_dir, LANTERN_STORAGE_STATE_FILE, &state_path) != 0) {
        goto cleanup;
    }
    rc = read_file_buffer(state_path, &data, &data_len);
    if (rc != 0) {
        goto cleanup;
    }
    if (lantern_ssz_decode_state(&decoded, data, data_len) != 0) {
        rc = -1;
        goto cleanup;
    }
    free(data);
    data = NULL;
    if (decoded.config.num_validators == 0) {
        rc = -1;
        goto cleanup;
    }
    lantern_state_reset(state);
    *state = decoded;
    decoded_owned = false;
    rc = 0;

cleanup:
    free_path(state_path);
    free(data);
    if (decoded_owned) {
        lantern_state_reset(&decoded);
    }
    return rc;
}

/**
 * Persist finalized replay state under `data_dir/finalized_state.ssz`.
 *
 * @param data_dir Base directory path.
 * @param state State to persist.
 * @return 0 on success.
 * @return -1 on invalid parameters, encoding failure, or filesystem errors.
 */
int lantern_storage_save_finalized_state(const char *data_dir, const LanternState *state) {
    if (!data_dir || !state || state->config.num_validators == 0) {
        return -1;
    }
    int rc = -1;
    uint8_t *buffer = NULL;
    char *state_path = NULL;

    const size_t encoded_size = state_encoded_size(state);
    if (encoded_size == 0) {
        goto cleanup;
    }

    buffer = malloc(encoded_size);
    if (!buffer) {
        goto cleanup;
    }
    size_t written = 0;
    if (lantern_ssz_encode_state(state, buffer, encoded_size, &written) != 0 || written != encoded_size) {
        goto cleanup;
    }
    if (join_path(data_dir, LANTERN_STORAGE_FINALIZED_STATE_FILE, &state_path) != 0) {
        goto cleanup;
    }
    rc = write_atomic_file(state_path, buffer, written);
    if (rc != 0) {
        goto cleanup;
    }

    rc = 0;

cleanup:
    free_path(state_path);
    free(buffer);
    return rc;
}

/**
 * Load a persisted finalized replay state from `data_dir/finalized_state.ssz`.
 *
 * On success, the contents of `state` are replaced.
 *
 * @param data_dir Base directory path.
 * @param state Output state (replaced on success).
 * @return 0 on success.
 * @return 1 if the finalized state file is missing or empty.
 * @return -1 on invalid parameters or decode/validation errors.
 */
int lantern_storage_load_finalized_state(const char *data_dir, LanternState *state) {
    if (!data_dir || !state) {
        return -1;
    }

    int rc = -1;
    char *state_path = NULL;
    uint8_t *data = NULL;
    size_t data_len = 0;

    LanternState decoded;
    lantern_state_init(&decoded);
    bool decoded_owned = true;

    if (join_path(data_dir, LANTERN_STORAGE_FINALIZED_STATE_FILE, &state_path) != 0) {
        goto cleanup;
    }
    rc = read_file_buffer(state_path, &data, &data_len);
    if (rc != 0) {
        goto cleanup;
    }
    if (lantern_ssz_decode_state(&decoded, data, data_len) != 0) {
        rc = -1;
        goto cleanup;
    }
    free(data);
    data = NULL;
    if (decoded.config.num_validators == 0) {
        rc = -1;
        goto cleanup;
    }
    lantern_state_reset(state);
    *state = decoded;
    decoded_owned = false;
    rc = 0;

cleanup:
    free_path(state_path);
    free(data);
    if (decoded_owned) {
        lantern_state_reset(&decoded);
    }
    return rc;
}

/**
 * Persist all present validator votes to `data_dir/votes.bin`.
 *
 * @param data_dir Base directory path.
 * @param state State containing validator votes.
 * @return 0 on success.
 * @return -1 on invalid parameters, encoding failure, or filesystem errors.
 */
int lantern_storage_save_votes(
    const char *data_dir,
    const LanternState *state,
    const LanternStore *store) {
    if (!data_dir || !state || !store || state->config.num_validators == 0) {
        return -1;
    }

    int rc = -1;
    uint8_t *buffer = NULL;
    char *votes_path = NULL;

    const size_t capacity = lantern_store_validator_capacity(store);
    if (capacity == 0) {
        goto cleanup;
    }
    size_t present = 0;
    for (size_t i = 0; i < capacity; ++i) {
        if (lantern_store_validator_has_vote(store, i)) {
            present++;
        }
    }
    struct lantern_storage_votes_header header = {0};
    memcpy(header.magic, LANTERN_STORAGE_VOTES_MAGIC, sizeof(header.magic));
    header.version = LANTERN_STORAGE_VOTES_VERSION;
    header.validator_count = capacity;
    header.record_count = present;

    const size_t payload_size = present * (sizeof(uint64_t) + LANTERN_SIGNED_VOTE_SSZ_SIZE);
    const size_t total_size = sizeof(header) + payload_size;
    buffer = malloc(total_size);
    if (!buffer) {
        goto cleanup;
    }
    uint8_t *cursor = buffer;
    memcpy(cursor, &header, sizeof(header));
    cursor += sizeof(header);

    for (size_t i = 0; i < capacity; ++i) {
        if (!lantern_store_validator_has_vote(store, i)) {
            continue;
        }
        const uint64_t validator_index = (uint64_t)i;
        for (size_t b = 0; b < sizeof(validator_index); ++b) {
            cursor[b] = (uint8_t)((validator_index >> (8u * b)) & 0xFFu);
        }
        cursor += sizeof(validator_index);

        LanternSignedVote signed_vote;
        if (lantern_store_get_signed_validator_vote(store, i, &signed_vote) != 0) {
            goto cleanup;
        }
        size_t vote_written = 0;
        if (lantern_ssz_encode_signed_vote(
                &signed_vote,
                cursor,
                LANTERN_SIGNED_VOTE_SSZ_SIZE,
                &vote_written)
                != 0
            || vote_written != LANTERN_SIGNED_VOTE_SSZ_SIZE) {
            goto cleanup;
        }
        cursor += LANTERN_SIGNED_VOTE_SSZ_SIZE;
    }

    if (join_path(data_dir, LANTERN_STORAGE_VOTES_FILE, &votes_path) != 0) {
        goto cleanup;
    }
    rc = write_atomic_file(votes_path, buffer, total_size);

cleanup:
    free_path(votes_path);
    free(buffer);
    return rc;
}

/**
 * Load persisted validator votes from `data_dir/votes.bin` into `state`.
 *
 * @param data_dir Base directory path.
 * @param state State to populate with loaded votes.
 * @return 0 on success.
 * @return 1 if the votes file is missing or empty.
 * @return -1 on invalid parameters or decode/validation errors.
 */
int lantern_storage_load_votes(const char *data_dir, LanternState *state, LanternStore *store) {
    if (!data_dir || !state || !store) {
        return -1;
    }

    int rc = -1;
    char *votes_path = NULL;
    uint8_t *data = NULL;
    size_t data_len = 0;

    if (join_path(data_dir, LANTERN_STORAGE_VOTES_FILE, &votes_path) != 0) {
        goto cleanup;
    }
    rc = read_file_buffer(votes_path, &data, &data_len);
    if (rc != 0) {
        goto cleanup;
    }
    if (data_len < sizeof(struct lantern_storage_votes_header)) {
        rc = -1;
        goto cleanup;
    }
    struct lantern_storage_votes_header header;
    memcpy(&header, data, sizeof(header));
    if (memcmp(header.magic, LANTERN_STORAGE_VOTES_MAGIC, sizeof(header.magic)) != 0) {
        rc = -1;
        goto cleanup;
    }
    bool has_signatures = false;
    size_t signed_vote_size = 0;
    if (header.version == 1u) {
        has_signatures = false;
    } else if (header.version >= 2u) {
        has_signatures = true;
        signed_vote_size = LANTERN_SIGNED_VOTE_SSZ_SIZE;
    } else {
        rc = -1;
        goto cleanup;
    }
    if (header.validator_count == 0) {
        rc = -1;
        goto cleanup;
    }
    if (state->config.num_validators == 0) {
        state->config.num_validators = header.validator_count;
    }
    if (state->config.num_validators != header.validator_count) {
        rc = -1;
        goto cleanup;
    }
    if (lantern_store_prepare_validator_votes(store, state->config.num_validators) != 0) {
        rc = -1;
        goto cleanup;
    }
    const size_t capacity = lantern_store_validator_capacity(store);
    for (size_t i = 0; i < capacity; ++i) {
        lantern_store_clear_validator_vote(store, i);
    }

    const uint8_t *cursor = data + sizeof(header);
    size_t remaining = data_len - sizeof(header);
    size_t records_read = 0;
    const size_t encoded_vote_size = has_signatures ? signed_vote_size : LANTERN_VOTE_SSZ_SIZE;
    while (records_read < header.record_count) {
        if (remaining < sizeof(uint64_t) + encoded_vote_size) {
            rc = -1;
            goto cleanup;
        }
        uint64_t validator_index = 0;
        for (size_t b = 0; b < sizeof(validator_index); ++b) {
            validator_index |= ((uint64_t)cursor[b]) << (8u * b);
        }
        cursor += sizeof(validator_index);
        remaining -= sizeof(validator_index);
        if (validator_index >= store->validator_votes_len) {
            rc = -1;
            goto cleanup;
        }
        if (has_signatures) {
            LanternSignedVote signed_vote;
            memset(&signed_vote, 0, sizeof(signed_vote));
            if (lantern_ssz_decode_signed_vote(&signed_vote, cursor, signed_vote_size) != 0) {
                rc = -1;
                goto cleanup;
            }
            cursor += signed_vote_size;
            remaining -= signed_vote_size;
            if (lantern_store_set_signed_validator_vote(store, (size_t)validator_index, &signed_vote) != 0) {
                rc = -1;
                goto cleanup;
            }
        } else {
            LanternVote vote;
            memset(&vote, 0, sizeof(vote));
            if (lantern_ssz_decode_vote(&vote, cursor, LANTERN_VOTE_SSZ_SIZE) != 0) {
                rc = -1;
                goto cleanup;
            }
            cursor += LANTERN_VOTE_SSZ_SIZE;
            remaining -= LANTERN_VOTE_SSZ_SIZE;
            if (lantern_store_set_validator_vote(store, (size_t)validator_index, &vote) != 0) {
                rc = -1;
                goto cleanup;
            }
        }
        records_read++;
    }
    if (remaining != 0) {
        rc = -1;
        goto cleanup;
    }

    rc = 0;

cleanup:
    free_path(votes_path);
    free(data);
    return rc;
}

static bool block_root_alias_matches_expected(
    const LanternSignedBlock *block,
    const LanternRoot *expected_root) {
    if (!block || !expected_root) {
        return false;
    }
    const LanternBlock *message = &block->message.block;
    const LanternVote *vote = &block->message.proposer_attestation;
    if (vote->slot != message->slot || vote->validator_id != message->proposer_index) {
        return false;
    }
    if (vote->head.slot != message->slot
        || vote->target.slot != message->slot
        || vote->source.slot != message->slot) {
        return false;
    }
    if (memcmp(vote->head.root.bytes, expected_root->bytes, LANTERN_ROOT_SIZE) != 0) {
        return false;
    }
    if (memcmp(vote->target.root.bytes, expected_root->bytes, LANTERN_ROOT_SIZE) != 0) {
        return false;
    }
    if (memcmp(vote->source.root.bytes, expected_root->bytes, LANTERN_ROOT_SIZE) != 0) {
        return false;
    }
    return true;
}

static int storage_store_block_internal(
    const char *data_dir,
    const LanternSignedBlock *block,
    const LanternRoot *root_override) {
    if (!data_dir || !block) {
        return -1;
    }

    int rc = -1;
    char *blocks_dir = NULL;
    char *block_path = NULL;
    uint8_t *buffer = NULL;

    if (build_blocks_dir(data_dir, &blocks_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(blocks_dir) != 0) {
        goto cleanup;
    }

    LanternRoot root = {0};
    if (root_override) {
        root = *root_override;
    } else if (lantern_hash_tree_root_block(&block->message.block, &root) != 0) {
        goto cleanup;
    }
    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    if (lantern_bytes_to_hex(root.bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0) != 0) {
        goto cleanup;
    }
    char filename[sizeof(root_hex) + 4];
    const int written = snprintf(filename, sizeof(filename), "%s.ssz", root_hex);
    if (written < 0 || (size_t)written >= sizeof(filename)) {
        goto cleanup;
    }

    if (join_path(blocks_dir, filename, &block_path) != 0) {
        goto cleanup;
    }

    struct stat st;
    if (stat(block_path, &st) == 0) {
        rc = 0;
        goto cleanup;
    }

    const size_t encoded_size = signed_block_encoded_size(block);
    if (encoded_size == 0) {
        lantern_log_warn(
            "storage",
            &(const struct lantern_log_metadata){0},
            "store_block size estimate failed slot=%" PRIu64 " attestations=%zu legacy_layout=%s sig_count=%zu",
            block->message.block.slot,
            block->message.block.body.attestations.length,
            block->message.block.body.legacy_plain_attestation_layout ? "true" : "false",
            block->signatures.attestation_signatures.length);
        goto cleanup;
    }
    buffer = malloc(encoded_size);
    if (!buffer) {
        goto cleanup;
    }
    size_t written_size = 0;
    const int encode_rc = lantern_ssz_encode_signed_block(block, buffer, encoded_size, &written_size);
    if (encode_rc != 0
        || written_size == 0
        || written_size > encoded_size) {
        lantern_log_warn(
            "storage",
            &(const struct lantern_log_metadata){0},
            "store_block encode failed slot=%" PRIu64 " rc=%d estimated=%zu written=%zu",
            block->message.block.slot,
            encode_rc,
            encoded_size,
            written_size);
        goto cleanup;
    }

    rc = write_atomic_file(block_path, buffer, written_size);

cleanup:
    free(buffer);
    free_path(block_path);
    free_path(blocks_dir);
    return rc;
}

/**
 * Store a signed block under `data_dir/blocks/<root>.ssz`.
 *
 * The operation is idempotent: if the block already exists on disk, this
 * function returns success without modifying it.
 *
 * @param data_dir Base directory path.
 * @param block Block to persist.
 * @return 0 on success.
 * @return -1 on invalid parameters, encoding failure, or filesystem errors.
 */
int lantern_storage_store_block(const char *data_dir, const LanternSignedBlock *block) {
    return storage_store_block_internal(data_dir, block, NULL);
}

int lantern_storage_store_block_for_root(
    const char *data_dir,
    const LanternRoot *root,
    const LanternSignedBlock *block) {
    if (!root) {
        return -1;
    }
    return storage_store_block_internal(data_dir, block, root);
}

int lantern_storage_store_invalid_block_bytes_for_root(
    const char *data_dir,
    const LanternRoot *root,
    const uint8_t *raw_block_ssz,
    size_t raw_block_ssz_len) {
    if (!data_dir || !root || !raw_block_ssz || raw_block_ssz_len == 0) {
        return -1;
    }

    int rc = -1;
    char *invalid_blocks_dir = NULL;
    char *block_path = NULL;

    if (build_invalid_blocks_dir(data_dir, &invalid_blocks_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(invalid_blocks_dir) != 0) {
        goto cleanup;
    }

    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0) != 0) {
        goto cleanup;
    }
    char filename[sizeof(root_hex) + 4];
    const int wrote = snprintf(filename, sizeof(filename), "%s.ssz", root_hex);
    if (wrote < 0 || (size_t)wrote >= sizeof(filename)) {
        goto cleanup;
    }
    if (join_path(invalid_blocks_dir, filename, &block_path) != 0) {
        goto cleanup;
    }

    rc = write_atomic_file(block_path, raw_block_ssz, raw_block_ssz_len);

cleanup:
    free_path(block_path);
    free_path(invalid_blocks_dir);
    return rc;
}

int lantern_storage_store_invalid_gossip_payload(
    const char *data_dir,
    const char *payload_type,
    const uint8_t *payload,
    size_t payload_len) {
    if (!data_dir || !payload_type || !payload || payload_len == 0) {
        return -1;
    }

    int rc = -1;
    char *invalid_gossip_dir = NULL;
    char *payload_path = NULL;
    char timestamp[32];
    char safe_payload_type[64];
    char filename[128];

    if (build_invalid_gossip_dir(data_dir, &invalid_gossip_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(invalid_gossip_dir) != 0) {
        goto cleanup;
    }
    if (format_utc_timestamp(timestamp, sizeof(timestamp)) != 0) {
        goto cleanup;
    }
    if (sanitize_filename_component(payload_type, safe_payload_type, sizeof(safe_payload_type)) != 0) {
        goto cleanup;
    }

    const int wrote = snprintf(
        filename,
        sizeof(filename),
        "%s_%s_%zub.ssz",
        timestamp,
        safe_payload_type,
        payload_len);
    if (wrote < 0 || (size_t)wrote >= sizeof(filename)) {
        goto cleanup;
    }
    if (join_path(invalid_gossip_dir, filename, &payload_path) != 0) {
        goto cleanup;
    }

    rc = write_atomic_file(payload_path, payload, payload_len);

cleanup:
    free_path(payload_path);
    free_path(invalid_gossip_dir);
    return rc;
}

/**
 * Persist `state` under `data_dir/states` using the given `root` as filename.
 *
 * @param data_dir Base directory path.
 * @param root Root used to build the on-disk filename.
 * @param state State to persist.
 * @return 0 on success.
 * @return -1 on invalid parameters, encoding failure, or filesystem errors.
 */
int lantern_storage_store_state_for_root(
    const char *data_dir,
    const LanternRoot *root,
    const LanternState *state) {
    if (!data_dir || !root || !state || state->config.num_validators == 0) {
        return -1;
    }

    int rc = -1;
    uint8_t *buffer = NULL;
    char *states_dir = NULL;
    char *state_path = NULL;

    const size_t encoded_size = state_encoded_size(state);
    if (encoded_size == 0) {
        goto cleanup;
    }
    buffer = malloc(encoded_size);
    if (!buffer) {
        goto cleanup;
    }
    size_t written = 0;
    if (lantern_ssz_encode_state(state, buffer, encoded_size, &written) != 0 || written != encoded_size) {
        goto cleanup;
    }
    if (build_states_dir(data_dir, &states_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(states_dir) != 0) {
        goto cleanup;
    }
    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0) != 0) {
        goto cleanup;
    }
    char filename[sizeof(root_hex) + 4];
    const int name_written = snprintf(filename, sizeof(filename), "%s.ssz", root_hex);
    if (name_written < 0 || (size_t)name_written >= sizeof(filename)) {
        goto cleanup;
    }
    if (join_path(states_dir, filename, &state_path) != 0) {
        goto cleanup;
    }
    rc = write_atomic_file(state_path, buffer, written);
    if (rc != 0) {
        goto cleanup;
    }
    rc = 0;

cleanup:
    free_path(state_path);
    free_path(states_dir);
    free(buffer);
    return rc;
}

/**
 * Load the raw persisted SSZ bytes for a state stored under `data_dir/states`.
 *
 * @param data_dir Base directory path.
 * @param root Root used to build the on-disk filename.
 * @param out_data Output buffer (caller must free) on success.
 * @param out_len Output length on success.
 * @return 0 on success.
 * @return 1 if the state file is missing or empty.
 * @return -1 on invalid parameters or filesystem errors.
 */
int lantern_storage_load_state_bytes_for_root(
    const char *data_dir,
    const LanternRoot *root,
    uint8_t **out_data,
    size_t *out_len) {
    if (!data_dir || !root || !out_data || !out_len) {
        return -1;
    }
    *out_data = NULL;
    *out_len = 0;

    int rc = -1;
    char *states_dir = NULL;
    char *state_path = NULL;
    uint8_t *data = NULL;
    size_t len = 0;

    if (build_states_dir(data_dir, &states_dir) != 0) {
        goto cleanup;
    }

    char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
    if (lantern_bytes_to_hex(root->bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0) != 0) {
        goto cleanup;
    }
    char filename[sizeof(root_hex) + 4];
    const int name_written = snprintf(filename, sizeof(filename), "%s.ssz", root_hex);
    if (name_written < 0 || (size_t)name_written >= sizeof(filename)) {
        goto cleanup;
    }
    if (join_path(states_dir, filename, &state_path) != 0) {
        goto cleanup;
    }

    rc = read_file_buffer(state_path, &data, &len);
    if (rc != 0) {
        if (data) {
            free(data);
            data = NULL;
        }
        rc = (rc > 0) ? 1 : -1;
        goto cleanup;
    }

    *out_data = data;
    *out_len = len;
    data = NULL;
    rc = 0;

cleanup:
    free_path(state_path);
    free_path(states_dir);
    free(data);
    return rc;
}

/**
 * Persist the mapping from a slot number to its block root on disk.
 *
 * Writes `root` into `data_dir/indices/slots/<slot>.root` using an
 * atomic write so readers never see a partial file.
 *
 * @param data_dir Base storage directory.
 * @param slot     Slot number to index.
 * @param root     32-byte block root for the slot.
 * @return 0 on success, -1 on error.
 */
int lantern_storage_store_slot_root(
    const char *data_dir,
    uint64_t slot,
    const LanternRoot *root) {
    if (!data_dir || !root) {
        return -1;
    }

    int rc = -1;
    char *slot_dir = NULL;
    char *slot_path = NULL;

    if (build_slot_index_dir(data_dir, &slot_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(slot_dir) != 0) {
        goto cleanup;
    }

    char filename[64];
    const int written = snprintf(filename, sizeof(filename), "%" PRIu64 ".root", slot);
    if (written < 0 || (size_t)written >= sizeof(filename)) {
        goto cleanup;
    }
    if (join_path(slot_dir, filename, &slot_path) != 0) {
        goto cleanup;
    }

    rc = write_atomic_file(slot_path, root->bytes, LANTERN_ROOT_SIZE);

cleanup:
    free_path(slot_path);
    free_path(slot_dir);
    return rc;
}

/**
 * Persist the current head slot and root so the node can resume after restart.
 *
 * Writes a compact `{slot, root}` record into `data_dir/indices/head.bin`
 * using an atomic write.
 *
 * @param data_dir Base storage directory.
 * @param slot     Head slot number.
 * @param root     32-byte head block root.
 * @return 0 on success, -1 on error.
 */
int lantern_storage_store_head_root(
    const char *data_dir,
    uint64_t slot,
    const LanternRoot *root) {
    if (!data_dir || !root) {
        return -1;
    }

    int rc = -1;
    char *indices_dir = NULL;
    char *head_path = NULL;

    if (build_indices_dir(data_dir, &indices_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(indices_dir) != 0) {
        goto cleanup;
    }
    if (join_path(indices_dir, LANTERN_STORAGE_HEAD_FILE, &head_path) != 0) {
        goto cleanup;
    }

    const struct lantern_storage_head_record record = {
        .slot = slot,
        .root = *root,
    };
    rc = write_atomic_file(head_path, (const uint8_t *)&record, sizeof(record));

cleanup:
    free_path(head_path);
    free_path(indices_dir);
    return rc;
}

/**
 * Persist justified and finalized checkpoint data to disk.
 *
 * Writes both checkpoints as a single record into
 * `data_dir/indices/checkpoints.bin` using an atomic write.
 *
 * @param data_dir   Base storage directory.
 * @param justified  Justified checkpoint to store.
 * @param finalized  Finalized checkpoint to store.
 * @return 0 on success, -1 on error.
 */
int lantern_storage_store_checkpoints(
    const char *data_dir,
    const LanternCheckpoint *justified,
    const LanternCheckpoint *finalized) {
    if (!data_dir || !justified || !finalized) {
        return -1;
    }

    int rc = -1;
    char *indices_dir = NULL;
    char *checkpoint_path = NULL;

    if (build_indices_dir(data_dir, &indices_dir) != 0) {
        goto cleanup;
    }
    if (ensure_directory(indices_dir) != 0) {
        goto cleanup;
    }
    if (join_path(indices_dir, LANTERN_STORAGE_CHECKPOINTS_FILE, &checkpoint_path) != 0) {
        goto cleanup;
    }

    const struct lantern_storage_checkpoint_record record = {
        .justified = *justified,
        .finalized = *finalized,
    };
    rc = write_atomic_file(
        checkpoint_path,
        (const uint8_t *)&record,
        sizeof(record));

cleanup:
    free_path(checkpoint_path);
    free_path(indices_dir);
    return rc;
}

/**
 * Collect signed blocks from disk that match the given set of roots.
 *
 * For each root in `roots`, looks up `data_dir/blocks/<hex>.ssz`, decodes
 * the block, and appends it to `out_blocks`.  Missing blocks are silently
 * skipped.
 *
 * @param data_dir   Base storage directory.
 * @param roots      Array of block roots to look up.
 * @param root_count Number of entries in `roots`.
 * @param out_blocks Output collection (resized to 0 on entry, filled on success).
 * @return 0 on success, -1 on error.
 */
int lantern_storage_collect_blocks(
    const char *data_dir,
    const LanternRoot *roots,
    size_t root_count,
    LanternSignedBlockList *out_blocks) {
    if (!data_dir || (!roots && root_count > 0) || !out_blocks) {
        return -1;
    }
    if (lantern_signed_block_list_resize(out_blocks, 0) != 0) {
        return -1;
    }

    int rc = -1;
    char *blocks_dir = NULL;

    if (build_blocks_dir(data_dir, &blocks_dir) != 0) {
        goto cleanup;
    }

    const struct lantern_log_metadata meta = {0};
    for (size_t i = 0; i < root_count; ++i) {
        char root_hex[2u * LANTERN_ROOT_SIZE + 1u];
        if (lantern_bytes_to_hex(roots[i].bytes, LANTERN_ROOT_SIZE, root_hex, sizeof(root_hex), 0) != 0) {
            goto cleanup;
        }
        char filename[sizeof(root_hex) + 4];
        const int wrote = snprintf(filename, sizeof(filename), "%s.ssz", root_hex);
        if (wrote < 0 || (size_t)wrote >= sizeof(filename)) {
            goto cleanup;
        }
        char *block_path = NULL;
        if (join_path(blocks_dir, filename, &block_path) != 0) {
            goto cleanup;
        }
        lantern_log_trace(
            "storage",
            &meta,
            "collect_blocks search root=%s path=%s",
            root_hex,
            block_path ? block_path : "null");

        uint8_t *data = NULL;
        size_t data_len = 0;
        const int read_rc = read_file_buffer(block_path, &data, &data_len);
        free_path(block_path);
        if (read_rc != 0) {
            lantern_log_debug(
                "storage",
                &meta,
                "collect_blocks miss root=%s rc=%d",
                root_hex,
                read_rc);
            continue;
        }

        const size_t current = out_blocks->length;
        if (lantern_signed_block_list_resize(out_blocks, current + 1) != 0) {
            free(data);
            goto cleanup;
        }
        LanternSignedBlock *dest = &out_blocks->blocks[current];
        if (lantern_ssz_decode_signed_block(dest, data, data_len) != 0) {
            free(data);
            goto cleanup;
        }
        LanternRoot computed;
        if (lantern_hash_tree_root_block(&dest->message.block, &computed) != 0) {
            free(data);
            goto cleanup;
        }
        if (memcmp(computed.bytes, roots[i].bytes, LANTERN_ROOT_SIZE) != 0) {
            if (!block_root_alias_matches_expected(dest, &roots[i])) {
                free(data);
                goto cleanup;
            }
            char computed_hex[2u * LANTERN_ROOT_SIZE + 1u];
            if (lantern_bytes_to_hex(computed.bytes, LANTERN_ROOT_SIZE, computed_hex, sizeof(computed_hex), 0) != 0) {
                computed_hex[0] = '\0';
            }
            lantern_log_warn(
                "storage",
                &meta,
                "collect_blocks accepted synthetic anchor alias requested=%s computed=%s",
                root_hex,
                computed_hex[0] ? computed_hex : "unknown");
        }
        lantern_log_trace(
            "storage",
            &meta,
            "collect_blocks loaded root=%s slot=%" PRIu64 " attestations=%zu",
            root_hex,
            dest->message.block.slot,
            dest->message.block.body.attestations.length);
        free(data);
    }
    rc = 0;

cleanup:
    free_path(blocks_dir);
    return rc;
}

/**
 * Iterate over every persisted block in the blocks directory.
 *
 * Opens `data_dir/blocks/`, reads each `.ssz` file, decodes the signed
 * block, derives its canonical root key from filename, and calls `visitor` with the block,
 * root, and caller-supplied `context`.  Iteration stops early if the
 * visitor returns non-zero (its return value is propagated).
 *
 * @param data_dir Base storage directory.
 * @param visitor  Callback invoked for each block.
 * @param context  Opaque pointer forwarded to the visitor.
 * @return 0 on success (all blocks visited).
 * @return 1 if the blocks directory does not exist.
 * @return -1 on I/O or decoding errors; positive visitor return values
 *         are forwarded as-is.
 */
int lantern_storage_iterate_blocks(
    const char *data_dir,
    lantern_storage_block_visitor_fn visitor,
    void *context) {
    if (!data_dir || !visitor) {
        return -1;
    }

    int rc = -1;
    char *blocks_dir = NULL;
    DIR *dir = NULL;

    if (build_blocks_dir(data_dir, &blocks_dir) != 0) {
        goto cleanup;
    }
    dir = opendir(blocks_dir);
    if (!dir) {
        rc = (errno == ENOENT) ? 1 : -1;
        goto cleanup;
    }

    rc = 0;
    const struct lantern_log_metadata meta = {0};
    struct dirent *entry = NULL;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        const size_t len = strlen(entry->d_name);
        if (len < 5 || strcmp(entry->d_name + len - 4, ".ssz") != 0) {
            continue;
        }
        char *block_path = NULL;
        if (join_path(blocks_dir, entry->d_name, &block_path) != 0) {
            rc = -1;
            break;
        }
        uint8_t *data = NULL;
        size_t data_len = 0;
        const int read_rc = read_file_buffer(block_path, &data, &data_len);
        free_path(block_path);
        if (read_rc != 0) {
            if (read_rc == 1) {
                continue;
            }
            rc = -1;
            break;
        }
        LanternSignedBlock block;
        lantern_signed_block_with_attestation_init(&block);
        if (lantern_ssz_decode_signed_block(&block, data, data_len) != 0) {
            lantern_signed_block_with_attestation_reset(&block);
            free(data);
            rc = -1;
            break;
        }
        LanternRoot computed_root;
        if (lantern_hash_tree_root_block(&block.message.block, &computed_root) != 0) {
            lantern_signed_block_with_attestation_reset(&block);
            free(data);
            rc = -1;
            break;
        }
        LanternRoot root_from_filename = {0};
        bool have_root_from_filename = false;
        if (len == ((2u * LANTERN_ROOT_SIZE) + 4u)) {
            char filename_hex[(2u * LANTERN_ROOT_SIZE) + 1u];
            memcpy(filename_hex, entry->d_name, 2u * LANTERN_ROOT_SIZE);
            filename_hex[2u * LANTERN_ROOT_SIZE] = '\0';
            have_root_from_filename =
                lantern_hex_decode(filename_hex, root_from_filename.bytes, LANTERN_ROOT_SIZE)
                == 0;
        }
        const LanternRoot *root_for_visitor = &computed_root;
        if (have_root_from_filename) {
            root_for_visitor = &root_from_filename;
            if (memcmp(computed_root.bytes, root_from_filename.bytes, LANTERN_ROOT_SIZE) != 0) {
                if (!block_root_alias_matches_expected(&block, &root_from_filename)) {
                    lantern_signed_block_with_attestation_reset(&block);
                    free(data);
                    rc = -1;
                    break;
                }
                char computed_hex[2u * LANTERN_ROOT_SIZE + 1u];
                char filename_hex[2u * LANTERN_ROOT_SIZE + 1u];
                if (lantern_bytes_to_hex(
                        computed_root.bytes,
                        LANTERN_ROOT_SIZE,
                        computed_hex,
                        sizeof(computed_hex),
                        0)
                    != 0) {
                    computed_hex[0] = '\0';
                }
                if (lantern_bytes_to_hex(
                        root_from_filename.bytes,
                        LANTERN_ROOT_SIZE,
                        filename_hex,
                        sizeof(filename_hex),
                        0)
                    != 0) {
                    filename_hex[0] = '\0';
                }
                lantern_log_warn(
                    "storage",
                    &meta,
                    "iterate_blocks accepted synthetic anchor alias filename_root=%s computed=%s",
                    filename_hex[0] ? filename_hex : "unknown",
                    computed_hex[0] ? computed_hex : "unknown");
            }
        }
        const int visit_rc = visitor(&block, root_for_visitor, context);
        lantern_signed_block_with_attestation_reset(&block);
        free(data);
        if (visit_rc != 0) {
            rc = visit_rc;
            break;
        }
    }

cleanup:
    if (dir) {
        closedir(dir);
    }
    free_path(blocks_dir);
    return rc;
}
