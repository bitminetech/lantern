#include "lantern/consensus/hash.h"
#include "lantern/support/log.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "ssz_constants.h"
#include "ssz_merkle.h"
#include "ssz_utils.h"
#include "mincrypt/sha256.h"

/* XMSS signature layout constants (LeanSpec prod config). */
static const size_t LANTERN_XMSS_FP_BYTES = 4u;
static const size_t LANTERN_XMSS_HASH_LEN_FE = 8u;
static const size_t LANTERN_XMSS_RAND_LEN_FE = 7u;
static const size_t LANTERN_XMSS_HASH_DIGEST_BYTES =
    (LANTERN_XMSS_HASH_LEN_FE * LANTERN_XMSS_FP_BYTES);
static const size_t LANTERN_XMSS_RHO_BYTES =
    (LANTERN_XMSS_RAND_LEN_FE * LANTERN_XMSS_FP_BYTES);
static const size_t LANTERN_XMSS_SIGNATURE_FIXED_SECTION =
    (SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_XMSS_RHO_BYTES + SSZ_BYTE_SIZE_OF_UINT32);
static const size_t LANTERN_XMSS_NODE_LIST_LIMIT = 1u << 17;

static void chunk_from_uint64(uint64_t value, uint8_t out[SSZ_BYTES_PER_CHUNK]) {
    memset(out, 0, SSZ_BYTES_PER_CHUNK);
    out[0] = (uint8_t)(value & 0xFFu);
    out[1] = (uint8_t)((value >> 8) & 0xFFu);
    out[2] = (uint8_t)((value >> 16) & 0xFFu);
    out[3] = (uint8_t)((value >> 24) & 0xFFu);
    out[4] = (uint8_t)((value >> 32) & 0xFFu);
    out[5] = (uint8_t)((value >> 40) & 0xFFu);
    out[6] = (uint8_t)((value >> 48) & 0xFFu);
    out[7] = (uint8_t)((value >> 56) & 0xFFu);
}

static uint32_t read_u32_le(const uint8_t *data) {
    if (!data) {
        return 0;
    }
    return (uint32_t)data[0]
        | ((uint32_t)data[1] << 8)
        | ((uint32_t)data[2] << 16)
        | ((uint32_t)data[3] << 24);
}

static int merkleize_chunks(
    const uint8_t *chunks,
    size_t chunk_count,
    size_t limit,
    LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    ssz_error_t err = ssz_merkleize(chunks, chunk_count, limit, temp_root);
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    memcpy(out_root->bytes, temp_root, SSZ_BYTES_PER_CHUNK);
    return 0;
}

static bool bitlist_bit_is_set(const struct lantern_bitlist *list, size_t index) {
    if (!list || !list->bytes || index >= list->bit_length) {
        return false;
    }
    size_t byte_index = index / 8u;
    if (byte_index >= list->capacity) {
        return false;
    }
    uint8_t mask = (uint8_t)(1u << (index % 8u));
    return (list->bytes[byte_index] & mask) != 0u;
}

static int hash_byte_vector(const uint8_t *bytes, size_t length, LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    size_t chunk_count = (length + SSZ_BYTES_PER_CHUNK - 1u) / SSZ_BYTES_PER_CHUNK;
    if (chunk_count == 0) {
        chunk_count = 1;
    }
    uint8_t *chunks = calloc(chunk_count, SSZ_BYTES_PER_CHUNK);
    if (!chunks) {
        return -1;
    }
    if (bytes && length > 0) {
        memcpy(chunks, bytes, length);
    }
    int result = merkleize_chunks(chunks, chunk_count, 0, out_root);
    free(chunks);
    return result;
}

static int hash_byte_list(const uint8_t *bytes, size_t length, size_t max_length, LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    if (length > max_length) {
        return -1;
    }
    size_t chunk_limit = (max_length + SSZ_BYTES_PER_CHUNK - 1u) / SSZ_BYTES_PER_CHUNK;
    size_t chunk_count = 0;
    if (length > 0) {
        chunk_count = (length + SSZ_BYTES_PER_CHUNK - 1u) / SSZ_BYTES_PER_CHUNK;
    }
    uint8_t *chunks = NULL;
    if (chunk_count > 0) {
        if (chunk_count > SIZE_MAX / SSZ_BYTES_PER_CHUNK) {
            return -1;
        }
        chunks = calloc(chunk_count, SSZ_BYTES_PER_CHUNK);
        if (!chunks) {
            return -1;
        }
        if (bytes) {
            memcpy(chunks, bytes, length);
        }
    }
    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    ssz_error_t err = ssz_merkleize(chunks, chunk_count, chunk_limit, temp_root);
    if (chunks) {
        free(chunks);
    }
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    err = ssz_mix_in_length(temp_root, (uint64_t)length, out_root->bytes);
    return err == SSZ_SUCCESS ? 0 : -1;
}

static int hash_digest_list_root(
    const uint8_t *chunks,
    size_t count,
    LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    if (count > 0 && !chunks) {
        return -1;
    }
    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    ssz_error_t err = ssz_merkleize(chunks, count, LANTERN_XMSS_NODE_LIST_LIMIT, temp_root);
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    err = ssz_mix_in_length(temp_root, (uint64_t)count, out_root->bytes);
    return err == SSZ_SUCCESS ? 0 : -1;
}

static int hash_xmss_signature(const LanternSignature *signature, LanternRoot *out_root) {
    if (!signature || !out_root) {
        return -1;
    }
    const uint8_t *data = signature->bytes;
    const size_t data_len = LANTERN_SIGNATURE_SIZE;

    if (data_len < LANTERN_XMSS_SIGNATURE_FIXED_SECTION) {
        return -1;
    }

    uint32_t path_offset = read_u32_le(data);
    uint32_t hashes_offset = read_u32_le(data + SSZ_BYTE_SIZE_OF_UINT32 + LANTERN_XMSS_RHO_BYTES);

    if (path_offset != LANTERN_XMSS_SIGNATURE_FIXED_SECTION) {
        return -1;
    }
    if (hashes_offset < path_offset || hashes_offset > data_len) {
        return -1;
    }

    size_t path_len = hashes_offset - path_offset;
    if (path_len < SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }
    uint32_t siblings_offset = read_u32_le(data + path_offset);
    if (siblings_offset != SSZ_BYTE_SIZE_OF_UINT32) {
        return -1;
    }
    size_t siblings_start = path_offset + siblings_offset;
    if (siblings_start > hashes_offset) {
        return -1;
    }
    size_t siblings_len = hashes_offset - siblings_start;
    if (siblings_len % LANTERN_XMSS_HASH_DIGEST_BYTES != 0) {
        return -1;
    }
    size_t siblings_count = siblings_len / LANTERN_XMSS_HASH_DIGEST_BYTES;
    if (siblings_count > LANTERN_XMSS_NODE_LIST_LIMIT) {
        return -1;
    }

    size_t hashes_len = data_len - hashes_offset;
    if (hashes_len % LANTERN_XMSS_HASH_DIGEST_BYTES != 0) {
        return -1;
    }
    size_t hashes_count = hashes_len / LANTERN_XMSS_HASH_DIGEST_BYTES;
    if (hashes_count > LANTERN_XMSS_NODE_LIST_LIMIT) {
        return -1;
    }

    LanternRoot siblings_root;
    if (hash_digest_list_root(data + siblings_start, siblings_count, &siblings_root) != 0) {
        return -1;
    }

    LanternRoot hashes_root;
    if (hash_digest_list_root(data + hashes_offset, hashes_count, &hashes_root) != 0) {
        return -1;
    }

    uint8_t rho_chunk[SSZ_BYTES_PER_CHUNK];
    memset(rho_chunk, 0, sizeof(rho_chunk));
    memcpy(rho_chunk, data + SSZ_BYTE_SIZE_OF_UINT32, LANTERN_XMSS_RHO_BYTES);
    LanternRoot rho_root;
    memcpy(rho_root.bytes, rho_chunk, SSZ_BYTES_PER_CHUNK);

    uint8_t chunks[3][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], siblings_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[1], rho_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[2], hashes_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 3, 0, out_root);
}

static int hash_validator(const uint8_t *pubkey, uint64_t index, LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    /* Validator SSZ structure: pubkey (Bytes52) + index (u64)
     * This matches Zeam's Validator struct for correct hash tree root. */
    LanternRoot pubkey_root;
    if (hash_byte_vector(pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE, &pubkey_root) != 0) {
        return -1;
    }
    uint8_t chunks[2][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], pubkey_root.bytes, SSZ_BYTES_PER_CHUNK);
    chunk_from_uint64(index, chunks[1]);
    return merkleize_chunks(&chunks[0][0], 2, 0, out_root);
}

static int zero_merkle_root(size_t chunk_limit, LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    uint64_t effective = chunk_limit;
    if (effective == 0) {
        memset(out_root->bytes, 0, LANTERN_ROOT_SIZE);
        return 0;
    }
    uint64_t padded = next_pow_of_two(effective);
    if (padded == 0) {
        return -1;
    }
    LanternRoot current;
    memset(current.bytes, 0, LANTERN_ROOT_SIZE);
    uint8_t buffer[SSZ_BYTES_PER_CHUNK * 2u];
    uint64_t depth = 0;
    while (((uint64_t)1 << depth) < padded) {
        memcpy(buffer, current.bytes, SSZ_BYTES_PER_CHUNK);
        memcpy(buffer + SSZ_BYTES_PER_CHUNK, current.bytes, SSZ_BYTES_PER_CHUNK);
        SHA256_hash(buffer, sizeof(buffer), current.bytes);
        ++depth;
    }
    *out_root = current;
    return 0;
}

static int hash_empty_list_root(size_t element_limit, LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    LanternRoot zero_root;
    size_t limit = element_limit ? element_limit : 1u;
    if (zero_merkle_root(limit, &zero_root) != 0) {
        return -1;
    }
    return ssz_mix_in_length(zero_root.bytes, 0, out_root->bytes) == SSZ_SUCCESS ? 0 : -1;
}

static int hash_empty_bitlist_root(size_t bit_limit, LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    size_t bits_per_chunk = SSZ_BYTES_PER_CHUNK * 8u;
    size_t chunk_limit = bit_limit ? ((bit_limit + bits_per_chunk - 1u) / bits_per_chunk) : 1u;
    LanternRoot zero_root;
    if (zero_merkle_root(chunk_limit, &zero_root) != 0) {
        return -1;
    }
    return ssz_mix_in_length(zero_root.bytes, 0, out_root->bytes) == SSZ_SUCCESS ? 0 : -1;
}

/**
 * Compare two LanternRoot values lexicographically.
 * Returns negative if a < b, positive if a > b, zero if equal.
 */
static int compare_roots(const void *a, const void *b) {
    return memcmp(((const LanternRoot *)a)->bytes, ((const LanternRoot *)b)->bytes, LANTERN_ROOT_SIZE);
}

/**
 * Merkleize justification roots and validators with sorted root ordering.
 * LeanSpec sorts justification roots before storing, so we must do the same
 * during hashing to ensure consistent state roots across implementations.
 */
static int merkleize_sorted_justifications(
    const struct lantern_root_list *roots,
    const struct lantern_bitlist *validators,
    size_t validator_count,
    LanternRoot *out_roots_root,
    LanternRoot *out_validators_root) {

    if (!roots || !validators || !out_roots_root || !out_validators_root) {
        return -1;
    }

    size_t root_count = roots->length;
    size_t bits_per_chunk = SSZ_BYTES_PER_CHUNK * 8u;

    /* Handle empty case */
    if (root_count == 0) {
        if (hash_empty_list_root(LANTERN_HISTORICAL_ROOTS_LIMIT, out_roots_root) != 0) {
            return -1;
        }
        if (hash_empty_bitlist_root(LANTERN_JUSTIFICATION_VALIDATORS_LIMIT, out_validators_root) != 0) {
            return -1;
        }
        return 0;
    }

    /* Allocate arrays for sorting */
    size_t *sort_indices = malloc(root_count * sizeof(size_t));
    LanternRoot *sorted_roots = malloc(root_count * sizeof(LanternRoot));
    if (!sort_indices || !sorted_roots) {
        free(sort_indices);
        free(sorted_roots);
        return -1;
    }

    /* Initialize indices and copy roots */
    for (size_t i = 0; i < root_count; ++i) {
        sort_indices[i] = i;
        memcpy(&sorted_roots[i], &roots->items[i], sizeof(LanternRoot));
    }

    /* Sort roots and track original indices using insertion sort (stable, simple) */
    for (size_t i = 1; i < root_count; ++i) {
        LanternRoot key_root = sorted_roots[i];
        size_t key_index = sort_indices[i];
        size_t j = i;
        while (j > 0 && compare_roots(&sorted_roots[j - 1], &key_root) > 0) {
            sorted_roots[j] = sorted_roots[j - 1];
            sort_indices[j] = sort_indices[j - 1];
            --j;
        }
        sorted_roots[j] = key_root;
        sort_indices[j] = key_index;
    }

    /* Create sorted root list for merkleization */
    struct lantern_root_list sorted_root_list;
    sorted_root_list.items = sorted_roots;
    sorted_root_list.length = root_count;
    sorted_root_list.capacity = root_count;

    if (lantern_merkleize_root_list(&sorted_root_list, LANTERN_HISTORICAL_ROOTS_LIMIT, out_roots_root) != 0) {
        free(sort_indices);
        free(sorted_roots);
        return -1;
    }

    /* Reorder validator bits according to sorted root order */
    size_t total_bits = validators->bit_length;
    if (total_bits == 0) {
        free(sort_indices);
        free(sorted_roots);
        if (hash_empty_bitlist_root(LANTERN_JUSTIFICATION_VALIDATORS_LIMIT, out_validators_root) != 0) {
            return -1;
        }
        return 0;
    }

    /* Create reordered bitlist */
    struct lantern_bitlist sorted_validators;
    lantern_bitlist_init(&sorted_validators);
    if (lantern_bitlist_resize(&sorted_validators, total_bits) != 0) {
        free(sort_indices);
        free(sorted_roots);
        return -1;
    }

    /* Copy bits in sorted order: for each sorted root position, copy bits from original position */
    for (size_t sorted_idx = 0; sorted_idx < root_count; ++sorted_idx) {
        size_t original_idx = sort_indices[sorted_idx];
        for (size_t v = 0; v < validator_count; ++v) {
            size_t src_bit = original_idx * validator_count + v;
            size_t dst_bit = sorted_idx * validator_count + v;
            if (src_bit < validators->bit_length && bitlist_bit_is_set(validators, src_bit)) {
                /* Set the bit in sorted_validators */
                size_t byte_index = dst_bit / 8u;
                uint8_t mask = (uint8_t)(1u << (dst_bit % 8u));
                if (byte_index < sorted_validators.capacity) {
                    sorted_validators.bytes[byte_index] |= mask;
                }
            }
        }
    }

    size_t justification_validators_chunk_limit =
        (LANTERN_JUSTIFICATION_VALIDATORS_LIMIT + bits_per_chunk - 1u) / bits_per_chunk;
    int result = lantern_merkleize_bitlist(&sorted_validators, justification_validators_chunk_limit, out_validators_root);

    lantern_bitlist_reset(&sorted_validators);
    free(sort_indices);
    free(sorted_roots);

    return result;
}

int lantern_hash_tree_root_config(const LanternConfig *config, LanternRoot *out_root) {
    if (!config || !out_root) {
        return -1;
    }
    /* Config only contains genesis_time for SSZ hashing (matches Zeam's BeamStateConfig).
     * num_validators is stored separately and not part of the SSZ-encoded config. */
    uint8_t chunks[1][SSZ_BYTES_PER_CHUNK];
    chunk_from_uint64(config->genesis_time, chunks[0]);
    return merkleize_chunks(&chunks[0][0], 1, 0, out_root);
}

int lantern_hash_tree_root_checkpoint(const LanternCheckpoint *checkpoint, LanternRoot *out_root) {
    if (!checkpoint || !out_root) {
        return -1;
    }
    uint8_t chunks[2][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], checkpoint->root.bytes, SSZ_BYTES_PER_CHUNK);
    chunk_from_uint64(checkpoint->slot, chunks[1]);
    return merkleize_chunks(&chunks[0][0], 2, 0, out_root);
}

int lantern_hash_tree_root_attestation_data(const LanternAttestationData *data, LanternRoot *out_root) {
    if (!data || !out_root) {
        return -1;
    }
    LanternRoot head_root;
    LanternRoot target_root;
    LanternRoot source_root;
    if (lantern_hash_tree_root_checkpoint(&data->head, &head_root) != 0) {
        return -1;
    }
    if (lantern_hash_tree_root_checkpoint(&data->target, &target_root) != 0) {
        return -1;
    }
    if (lantern_hash_tree_root_checkpoint(&data->source, &source_root) != 0) {
        return -1;
    }
    uint8_t chunks[4][SSZ_BYTES_PER_CHUNK];
    chunk_from_uint64(data->slot, chunks[0]);
    memcpy(chunks[1], head_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[2], target_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[3], source_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 4, 0, out_root);
}

int lantern_hash_tree_root_vote(const LanternVote *vote, LanternRoot *out_root) {
    if (!vote || !out_root) {
        return -1;
    }
    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&vote->data, &data_root) != 0) {
        return -1;
    }
    uint8_t chunks[2][SSZ_BYTES_PER_CHUNK];
    chunk_from_uint64(vote->validator_id, chunks[0]);
    memcpy(chunks[1], data_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 2, 0, out_root);
}

int lantern_hash_tree_root_aggregated_attestation(const LanternAggregatedAttestation *attestation, LanternRoot *out_root) {
    if (!attestation || !out_root) {
        return -1;
    }
    if (attestation->aggregation_bits.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    LanternRoot bits_root;
    size_t bits_per_chunk = SSZ_BYTES_PER_CHUNK * 8u;
    size_t bitlist_limit = (LANTERN_VALIDATOR_REGISTRY_LIMIT + bits_per_chunk - 1u) / bits_per_chunk;
    if (attestation->aggregation_bits.bit_length == 0) {
        if (hash_empty_bitlist_root(LANTERN_VALIDATOR_REGISTRY_LIMIT, &bits_root) != 0) {
            return -1;
        }
    } else if (lantern_merkleize_bitlist(&attestation->aggregation_bits, bitlist_limit, &bits_root) != 0) {
        return -1;
    }
    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(&attestation->data, &data_root) != 0) {
        return -1;
    }
    uint8_t chunks[2][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], bits_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[1], data_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 2, 0, out_root);
}

int lantern_hash_tree_root_aggregated_signature_proof(
    const LanternAggregatedSignatureProof *proof,
    LanternRoot *out_root) {
    if (!proof || !out_root) {
        return -1;
    }
    if (proof->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (proof->proof_data.length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return -1;
    }
    LanternRoot participants_root;
    size_t bits_per_chunk = SSZ_BYTES_PER_CHUNK * 8u;
    size_t bitlist_limit = (LANTERN_VALIDATOR_REGISTRY_LIMIT + bits_per_chunk - 1u) / bits_per_chunk;
    if (proof->participants.bit_length == 0) {
        if (hash_empty_bitlist_root(LANTERN_VALIDATOR_REGISTRY_LIMIT, &participants_root) != 0) {
            return -1;
        }
    } else if (lantern_merkleize_bitlist(&proof->participants, bitlist_limit, &participants_root) != 0) {
        return -1;
    }
    LanternRoot proof_root;
    if (hash_byte_list(
            proof->proof_data.data,
            proof->proof_data.length,
            LANTERN_AGG_PROOF_MAX_BYTES,
            &proof_root)
        != 0) {
        return -1;
    }
    uint8_t chunks[2][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], participants_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[1], proof_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 2, 0, out_root);
}

int lantern_merkleize_root_list(
    const struct lantern_root_list *list,
    size_t limit,
    LanternRoot *out_root) {
    if (!list || !out_root) {
        return -1;
    }
    size_t count = list->length;
    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    uint8_t *chunk_bytes = NULL;
    if (count > 0) {
        if (!list->items) {
            return -1;
        }
        if (count > SIZE_MAX / SSZ_BYTES_PER_CHUNK) {
            return -1;
        }
        size_t total_bytes = count * SSZ_BYTES_PER_CHUNK;
        chunk_bytes = malloc(total_bytes);
        if (!chunk_bytes) {
            return -1;
        }
        for (size_t i = 0; i < count; ++i) {
            memcpy(chunk_bytes + (i * SSZ_BYTES_PER_CHUNK), list->items[i].bytes, SSZ_BYTES_PER_CHUNK);
        }
    }
    ssz_error_t err = ssz_merkleize(chunk_bytes, count, limit, temp_root);
    if (chunk_bytes) {
        free(chunk_bytes);
    }
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    err = ssz_mix_in_length(temp_root, (uint64_t)count, out_root->bytes);
    return err == SSZ_SUCCESS ? 0 : -1;
}

int lantern_merkleize_bitlist(
    const struct lantern_bitlist *bitlist,
    size_t limit,
    LanternRoot *out_root) {
    if (!bitlist || !out_root) {
        return -1;
    }
    size_t bit_count = bitlist->bit_length;
    bool *bits = NULL;
    if (bit_count > 0) {
        if (!bitlist->bytes) {
            return -1;
        }
        bits = calloc(bit_count, sizeof(*bits));
        if (!bits) {
            return -1;
        }
        for (size_t i = 0; i < bit_count; ++i) {
            size_t byte_index = i / 8u;
            size_t bit_index = i % 8u;
            if (byte_index < bitlist->capacity) {
                bits[i] = (bitlist->bytes[byte_index] >> bit_index) & 1u;
            }
        }
    }

    size_t bitfield_len = bit_count ? ((bit_count + 7u) / 8u) : 1u;
    size_t max_chunks = (bitfield_len + SSZ_BYTES_PER_CHUNK - 1u) / SSZ_BYTES_PER_CHUNK;
    if (max_chunks == 0) {
        max_chunks = 1;
    }
    uint8_t *packed = calloc(max_chunks, SSZ_BYTES_PER_CHUNK);
    if (!packed) {
        free(bits);
        return -1;
    }
    size_t chunk_count = 0;
    ssz_error_t err = ssz_pack_bits(bits, bit_count, packed, &chunk_count);
    free(bits);
    if (err != SSZ_SUCCESS) {
        free(packed);
        return -1;
    }
    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    err = ssz_merkleize(packed, chunk_count, limit, temp_root);
    free(packed);
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    err = ssz_mix_in_length(temp_root, (uint64_t)bit_count, out_root->bytes);
    return err == SSZ_SUCCESS ? 0 : -1;
}

static int hash_aggregated_attestations(const LanternAggregatedAttestations *attestations, LanternRoot *out_root) {
    if (!attestations || !out_root) {
        return -1;
    }
    size_t count = attestations->length;
    uint8_t *chunks = NULL;
    if (count > 0) {
        if (!attestations->data) {
            return -1;
        }
        if (count > LANTERN_MAX_ATTESTATIONS) {
            return -1;
        }
        if (count > SIZE_MAX / SSZ_BYTES_PER_CHUNK) {
            return -1;
        }
        size_t total_bytes = count * SSZ_BYTES_PER_CHUNK;
        chunks = malloc(total_bytes);
        if (!chunks) {
            return -1;
        }
        for (size_t i = 0; i < count; ++i) {
            LanternRoot att_root;
            if (lantern_hash_tree_root_aggregated_attestation(&attestations->data[i], &att_root) != 0) {
                free(chunks);
                return -1;
            }
            memcpy(chunks + (i * SSZ_BYTES_PER_CHUNK), att_root.bytes, SSZ_BYTES_PER_CHUNK);
        }
    }
    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    memset(temp_root, 0, sizeof(temp_root));
    ssz_error_t err = ssz_merkleize(chunks, attestations->length, LANTERN_MAX_ATTESTATIONS, temp_root);
    if (chunks) {
        free(chunks);
    }
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    err = ssz_mix_in_length(temp_root, (uint64_t)attestations->length, out_root->bytes);
    return err == SSZ_SUCCESS ? 0 : -1;
}

static int single_participant_from_aggregate(
    const LanternAggregatedAttestation *attestation,
    uint64_t *out_validator_id) {
    if (!attestation || !out_validator_id) {
        return -1;
    }
    size_t bit_length = attestation->aggregation_bits.bit_length;
    if (bit_length == 0 || bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    bool found = false;
    uint64_t validator_id = 0;
    for (size_t i = 0; i < bit_length; ++i) {
        if (!bitlist_bit_is_set(&attestation->aggregation_bits, i)) {
            continue;
        }
        if (found) {
            return -1;
        }
        found = true;
        validator_id = (uint64_t)i;
    }
    if (!found) {
        return -1;
    }
    *out_validator_id = validator_id;
    return 0;
}

static int hash_plain_attestations_from_aggregated(
    const LanternAggregatedAttestations *attestations,
    LanternRoot *out_root) {
    if (!attestations || !out_root) {
        return -1;
    }
    size_t count = attestations->length;
    uint8_t *chunks = NULL;
    if (count > 0) {
        if (!attestations->data) {
            return -1;
        }
        if (count > LANTERN_MAX_ATTESTATIONS) {
            return -1;
        }
        if (count > SIZE_MAX / SSZ_BYTES_PER_CHUNK) {
            return -1;
        }
        chunks = malloc(count * SSZ_BYTES_PER_CHUNK);
        if (!chunks) {
            return -1;
        }
        for (size_t i = 0; i < count; ++i) {
            uint64_t validator_id = 0;
            if (single_participant_from_aggregate(&attestations->data[i], &validator_id) != 0) {
                free(chunks);
                return -1;
            }
            LanternVote vote;
            memset(&vote, 0, sizeof(vote));
            vote.validator_id = validator_id;
            vote.data = attestations->data[i].data;

            LanternRoot vote_root;
            if (lantern_hash_tree_root_vote(&vote, &vote_root) != 0) {
                free(chunks);
                return -1;
            }
            memcpy(chunks + (i * SSZ_BYTES_PER_CHUNK), vote_root.bytes, SSZ_BYTES_PER_CHUNK);
        }
    }

    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    memset(temp_root, 0, sizeof(temp_root));
    ssz_error_t err = ssz_merkleize(chunks, count, LANTERN_MAX_ATTESTATIONS, temp_root);
    if (chunks) {
        free(chunks);
    }
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    err = ssz_mix_in_length(temp_root, (uint64_t)count, out_root->bytes);
    return err == SSZ_SUCCESS ? 0 : -1;
}

static int hash_attestation_signatures(const LanternAttestationSignatures *signatures, LanternRoot *out_root) {
    if (!signatures || !out_root) {
        return -1;
    }
    size_t count = signatures->length;
    uint8_t *chunks = NULL;
    if (count > 0) {
        if (!signatures->data) {
            return -1;
        }
        if (count > LANTERN_MAX_BLOCK_SIGNATURES) {
            return -1;
        }
        if (count > SIZE_MAX / SSZ_BYTES_PER_CHUNK) {
            return -1;
        }
        size_t total_bytes = count * SSZ_BYTES_PER_CHUNK;
        chunks = malloc(total_bytes);
        if (!chunks) {
            return -1;
        }
        for (size_t i = 0; i < count; ++i) {
            LanternRoot sig_root;
            if (lantern_hash_tree_root_aggregated_signature_proof(&signatures->data[i], &sig_root) != 0) {
                free(chunks);
                return -1;
            }
            memcpy(chunks + (i * SSZ_BYTES_PER_CHUNK), sig_root.bytes, SSZ_BYTES_PER_CHUNK);
        }
    }
    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    memset(temp_root, 0, sizeof(temp_root));
    ssz_error_t err = ssz_merkleize(chunks, count, LANTERN_MAX_BLOCK_SIGNATURES, temp_root);
    if (chunks) {
        free(chunks);
    }
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    err = ssz_mix_in_length(temp_root, (uint64_t)count, out_root->bytes);
    return err == SSZ_SUCCESS ? 0 : -1;
}

static int hash_block_signatures(const LanternBlockSignatures *signatures, LanternRoot *out_root) {
    if (!signatures || !out_root) {
        return -1;
    }
    LanternRoot attestation_root;
    if (hash_attestation_signatures(&signatures->attestation_signatures, &attestation_root) != 0) {
        return -1;
    }
    LanternRoot proposer_root;
    if (hash_xmss_signature(&signatures->proposer_signature, &proposer_root) != 0) {
        return -1;
    }
    uint8_t chunks[2][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], attestation_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[1], proposer_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 2, 0, out_root);
}

int lantern_hash_tree_root_block_body(const LanternBlockBody *body, LanternRoot *out_root) {
    if (!body || !out_root) {
        return -1;
    }
    LanternRoot att_root;
    bool used_legacy_plain_hash = false;
    if (body->legacy_plain_attestation_layout
        && hash_plain_attestations_from_aggregated(&body->attestations, &att_root) == 0) {
        used_legacy_plain_hash = true;
    } else if (hash_aggregated_attestations(&body->attestations, &att_root) != 0) {
        return -1;
    }
    static bool logged_legacy_plain_hash = false;
    if (used_legacy_plain_hash && !logged_legacy_plain_hash) {
        lantern_log_warn(
            "hash",
            NULL,
            "block body root using legacy plain attestation compatibility hashing count=%zu",
            body->attestations.length);
        logged_legacy_plain_hash = true;
    }
    uint8_t chunks[1][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], att_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 1, 0, out_root);
}

int lantern_hash_tree_root_block_header(const LanternBlockHeader *header, LanternRoot *out_root) {
    if (!header || !out_root) {
        return -1;
    }
    uint8_t chunks[5][SSZ_BYTES_PER_CHUNK];
    chunk_from_uint64(header->slot, chunks[0]);
    chunk_from_uint64(header->proposer_index, chunks[1]);
    memcpy(chunks[2], header->parent_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[3], header->state_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[4], header->body_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 5, 0, out_root);
}

int lantern_hash_tree_root_block(const LanternBlock *block, LanternRoot *out_root) {
    if (!block || !out_root) {
        return -1;
    }
    LanternRoot body_root;
    if (lantern_hash_tree_root_block_body(&block->body, &body_root) != 0) {
        return -1;
    }
    uint8_t chunks[5][SSZ_BYTES_PER_CHUNK];
    chunk_from_uint64(block->slot, chunks[0]);
    chunk_from_uint64(block->proposer_index, chunks[1]);
    memcpy(chunks[2], block->parent_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[3], block->state_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[4], body_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 5, 0, out_root);
}

int lantern_hash_tree_root_block_with_attestation(
    const LanternBlockWithAttestation *block,
    LanternRoot *out_root) {
    if (!block || !out_root) {
        return -1;
    }
    LanternRoot block_root;
    LanternRoot proposer_root;
    if (lantern_hash_tree_root_block(&block->block, &block_root) != 0) {
        return -1;
    }
    if (lantern_hash_tree_root_vote(&block->proposer_attestation, &proposer_root) != 0) {
        return -1;
    }
    uint8_t chunks[2][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], block_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[1], proposer_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 2, 0, out_root);
}

int lantern_hash_tree_root_signed_block(const LanternSignedBlock *block, LanternRoot *out_root) {
    if (!block || !out_root) {
        return -1;
    }
    LanternRoot message_root;
    if (lantern_hash_tree_root_block_with_attestation(&block->message, &message_root) != 0) {
        return -1;
    }
    LanternRoot signatures_root;
    if (hash_block_signatures(&block->signatures, &signatures_root) != 0) {
        return -1;
    }
    uint8_t chunks[2][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], message_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[1], signatures_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 2, 0, out_root);
}

int lantern_hash_tree_root_state(const LanternState *state, LanternRoot *out_root) {
    if (!state || !out_root) {
        return -1;
    }

    LanternRoot config_root;
    LanternRoot header_root;
    LanternRoot justified_root;
    LanternRoot finalized_root;
    LanternRoot historical_root;
    LanternRoot justified_slots_root;
    LanternRoot justification_roots_root;
    LanternRoot justification_validators_root;
    LanternRoot validators_root;
    memset(&validators_root, 0, sizeof(validators_root));

    if (lantern_hash_tree_root_config(&state->config, &config_root) != 0) {
        return -1;
    }
    if (lantern_hash_tree_root_block_header(&state->latest_block_header, &header_root) != 0) {
        return -1;
    }
    if (lantern_hash_tree_root_checkpoint(&state->latest_justified, &justified_root) != 0) {
        return -1;
    }
    if (lantern_hash_tree_root_checkpoint(&state->latest_finalized, &finalized_root) != 0) {
        return -1;
    }
    if (state->historical_block_hashes.length == 0) {
        if (hash_empty_list_root(LANTERN_HISTORICAL_ROOTS_LIMIT, &historical_root) != 0) {
            return -1;
        }
    } else if (lantern_merkleize_root_list(&state->historical_block_hashes, LANTERN_HISTORICAL_ROOTS_LIMIT, &historical_root) != 0) {
        return -1;
    }
    size_t bits_per_chunk = SSZ_BYTES_PER_CHUNK * 8u;
    size_t justified_chunk_limit = (LANTERN_HISTORICAL_ROOTS_LIMIT + bits_per_chunk - 1u) / bits_per_chunk;
    if (state->justified_slots.bit_length == 0) {
        if (hash_empty_bitlist_root(LANTERN_HISTORICAL_ROOTS_LIMIT, &justified_slots_root) != 0) {
            return -1;
        }
    } else if (lantern_merkleize_bitlist(&state->justified_slots, justified_chunk_limit, &justified_slots_root) != 0) {
        return -1;
    }
    /* Merkleize justification roots and validators with sorted ordering.
     * LeanSpec sorts justification roots lexicographically before hashing,
     * so we must do the same to produce matching state roots. */
    if (merkleize_sorted_justifications(
            &state->justification_roots,
            &state->justification_validators,
            state->validator_count,
            &justification_roots_root,
            &justification_validators_root) != 0) {
        return -1;
    }
    if (state->validator_count == 0) {
        if (lantern_hash_tree_root_validators(NULL, 0, &validators_root) != 0) {
            return -1;
        }
    } else {
        if (!state->validators || state->validator_count > SIZE_MAX / SSZ_BYTES_PER_CHUNK) {
            return -1;
        }
        uint8_t *validator_chunks = malloc(state->validator_count * SSZ_BYTES_PER_CHUNK);
        if (!validator_chunks) {
            return -1;
        }
        for (size_t i = 0; i < state->validator_count; ++i) {
            LanternRoot validator_root;
            if (hash_validator(state->validators[i].pubkey, state->validators[i].index, &validator_root) != 0) {
                free(validator_chunks);
                return -1;
            }
            memcpy(
                validator_chunks + (i * SSZ_BYTES_PER_CHUNK),
                validator_root.bytes,
                SSZ_BYTES_PER_CHUNK);
        }
        uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
        ssz_error_t validator_err =
            ssz_merkleize(validator_chunks, state->validator_count, LANTERN_VALIDATOR_REGISTRY_LIMIT, temp_root);
        free(validator_chunks);
        if (validator_err != SSZ_SUCCESS) {
            return -1;
        }
        validator_err = ssz_mix_in_length(temp_root, (uint64_t)state->validator_count, validators_root.bytes);
        if (validator_err != SSZ_SUCCESS) {
            return -1;
        }
    }

    uint8_t chunks[10][SSZ_BYTES_PER_CHUNK];
    memcpy(chunks[0], config_root.bytes, SSZ_BYTES_PER_CHUNK);
    chunk_from_uint64(state->slot, chunks[1]);
    memcpy(chunks[2], header_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[3], justified_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[4], finalized_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[5], historical_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[6], justified_slots_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[7], validators_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[8], justification_roots_root.bytes, SSZ_BYTES_PER_CHUNK);
    memcpy(chunks[9], justification_validators_root.bytes, SSZ_BYTES_PER_CHUNK);
    return merkleize_chunks(&chunks[0][0], 10, 0, out_root);
}

int lantern_hash_tree_root_validators(const uint8_t *pubkeys, size_t count, LanternRoot *out_root) {
    if (!out_root) {
        return -1;
    }
    uint8_t *chunks = NULL;
    if (count > 0) {
        if (!pubkeys) {
            return -1;
        }
        if (count > SIZE_MAX / SSZ_BYTES_PER_CHUNK) {
            return -1;
        }
        chunks = malloc(count * SSZ_BYTES_PER_CHUNK);
        if (!chunks) {
            return -1;
        }
        for (size_t i = 0; i < count; ++i) {
            LanternRoot validator_root;
            /* Pass index i to match Zeam's Validator { pubkey, index } SSZ structure */
            if (hash_validator(pubkeys + (i * LANTERN_VALIDATOR_PUBKEY_SIZE), (uint64_t)i, &validator_root) != 0) {
                free(chunks);
                return -1;
            }
            memcpy(chunks + (i * SSZ_BYTES_PER_CHUNK), validator_root.bytes, SSZ_BYTES_PER_CHUNK);
        }
    }
    uint8_t temp_root[SSZ_BYTES_PER_CHUNK];
    ssz_error_t err = ssz_merkleize(chunks, count, LANTERN_VALIDATOR_REGISTRY_LIMIT, temp_root);
    free(chunks);
    if (err != SSZ_SUCCESS) {
        return -1;
    }
    err = ssz_mix_in_length(temp_root, (uint64_t)count, out_root->bytes);
    return err == SSZ_SUCCESS ? 0 : -1;
}
