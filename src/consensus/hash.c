#include "lantern/consensus/hash.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "ssz.h"
#include "pq-bindings-c-rust.h"
#include "lantern/consensus/ssz.h"

#define LANTERN_RETURN_IF_SSZ_ERROR(expr) \
    do { \
        ssz_error_t lantern_err__ = (expr); \
        if (lantern_err__ != SSZ_SUCCESS) { \
            return lantern_err__; \
        } \
    } while (0)

/* XMSS signature layout constants (LeanSpec prod config). */
static const size_t LANTERN_XMSS_FP_BYTES = 4u;
static const size_t LANTERN_XMSS_HASH_LEN_FE = 8u;
static const size_t LANTERN_XMSS_RAND_LEN_FE = 7u;
static const size_t LANTERN_XMSS_HASH_DIGEST_BYTES =
    (LANTERN_XMSS_HASH_LEN_FE * LANTERN_XMSS_FP_BYTES);
static const size_t LANTERN_XMSS_RHO_BYTES =
    (LANTERN_XMSS_RAND_LEN_FE * LANTERN_XMSS_FP_BYTES);
static const size_t LANTERN_XMSS_SIGNATURE_FIXED_SECTION =
    (SSZ_BYTES_PER_LENGTH_OFFSET + LANTERN_XMSS_RHO_BYTES + SSZ_BYTES_PER_LENGTH_OFFSET);
static size_t xmss_node_list_limit(void) {
    uint64_t lifetime = pq_get_lifetime();
    if (lifetime == 0u || (lifetime & (lifetime - 1u)) != 0u) {
        return (size_t)1u << 17;
    }

    unsigned int log_lifetime = 0u;
    while (log_lifetime < 63u && (UINT64_C(1) << log_lifetime) < lifetime) {
        ++log_lifetime;
    }

    unsigned int exponent = (log_lifetime / 2u) + 1u;
    if (exponent >= (sizeof(size_t) * 8u)) {
        return 0u;
    }

    return (size_t)1u << exponent;
}

static ssz_error_t chunk_from_uint64(uint64_t value, ssz_chunk_t *out) {
    return ssz_hash_tree_root_uint64(value, out);
}

static void chunk_from_root(const LanternRoot *root, ssz_chunk_t *out) {
    memcpy(out->bytes, root->bytes, SSZ_BYTES_PER_CHUNK);
}

static void root_from_chunk(const ssz_chunk_t *chunk, LanternRoot *out_root) {
    memcpy(out_root->bytes, chunk->bytes, SSZ_BYTES_PER_CHUNK);
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

static ssz_error_t merkleize_chunks(
    const ssz_chunk_t *chunks,
    size_t chunk_count,
    size_t limit,
    LanternRoot *out_root) {
    if (!out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    uint64_t effective_limit = limit == 0u ? SSZ_NO_LIMIT : (uint64_t)limit;
    ssz_chunk_t temp_root;
    ssz_error_t err = ssz_merkleize(chunks, chunk_count, effective_limit, NULL, NULL, &temp_root);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    root_from_chunk(&temp_root, out_root);
    return SSZ_SUCCESS;
}

static ssz_error_t hash_byte_vector(const uint8_t *bytes, size_t length, LanternRoot *out_root) {
    if (!out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    ssz_chunk_t root;
    ssz_error_t err = ssz_hash_tree_root_vector_fixed(
        bytes,
        length,
        sizeof(uint8_t),
        NULL,
        NULL,
        &root);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}

static ssz_error_t hash_byte_list(const uint8_t *bytes, size_t length, size_t max_length, LanternRoot *out_root) {
    if (!out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    ssz_chunk_t root;
    ssz_error_t err = ssz_hash_tree_root_list_fixed(
        bytes,
        length,
        max_length,
        sizeof(uint8_t),
        NULL,
        NULL,
        &root);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}

static ssz_error_t hash_digest_list_root(
    const uint8_t *chunks,
    size_t count,
    LanternRoot *out_root) {
    if (!out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (count > 0 && !chunks) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    size_t limit = xmss_node_list_limit();
    if (limit == 0u) {
        return SSZ_ERR_OVERFLOW;
    }
    ssz_chunk_t *roots = NULL;
    if (count > 0) {
        roots = calloc(count, sizeof(*roots));
        if (!roots) {
            return SSZ_ERR_HASH_FAILURE;
        }
        for (size_t i = 0; i < count; ++i) {
            memcpy(roots[i].bytes, chunks + (i * SSZ_BYTES_PER_CHUNK), SSZ_BYTES_PER_CHUNK);
        }
    }
    ssz_chunk_t root;
    ssz_error_t err = ssz_hash_tree_root_list_roots(
        roots,
        count,
        limit,
        NULL,
        NULL,
        &root);
    free(roots);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}

static ssz_error_t hash_xmss_signature(const LanternSignature *signature, LanternRoot *out_root) {
    if (!signature || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    const uint8_t *data = signature->bytes;
    const size_t data_len = LANTERN_SIGNATURE_SIZE;

    if (data_len < LANTERN_XMSS_SIGNATURE_FIXED_SECTION) {
        return SSZ_ERR_ENCODING_INVALID;
    }

    uint32_t path_offset = read_u32_le(data);
    uint32_t hashes_offset = read_u32_le(data + SSZ_BYTES_PER_LENGTH_OFFSET + LANTERN_XMSS_RHO_BYTES);

    if (path_offset != LANTERN_XMSS_SIGNATURE_FIXED_SECTION) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    if (hashes_offset < path_offset || hashes_offset > data_len) {
        return SSZ_ERR_OFFSET_INVALID;
    }

    size_t path_len = hashes_offset - path_offset;
    if (path_len < SSZ_BYTES_PER_LENGTH_OFFSET) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    uint32_t siblings_offset = read_u32_le(data + path_offset);
    if (siblings_offset != SSZ_BYTES_PER_LENGTH_OFFSET) {
        return SSZ_ERR_OFFSET_INVALID;
    }
    size_t siblings_start = path_offset + siblings_offset;
    if (siblings_start > hashes_offset) {
        return SSZ_ERR_OFFSET_INVALID;
    }
    size_t siblings_len = hashes_offset - siblings_start;
    if (siblings_len % LANTERN_XMSS_HASH_DIGEST_BYTES != 0) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    size_t siblings_count = siblings_len / LANTERN_XMSS_HASH_DIGEST_BYTES;
    size_t node_limit = xmss_node_list_limit();
    if (node_limit == 0u) {
        return SSZ_ERR_OVERFLOW;
    }
    if (siblings_count > node_limit) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }

    size_t hashes_len = data_len - hashes_offset;
    if (hashes_len % LANTERN_XMSS_HASH_DIGEST_BYTES != 0) {
        return SSZ_ERR_ENCODING_INVALID;
    }
    size_t hashes_count = hashes_len / LANTERN_XMSS_HASH_DIGEST_BYTES;
    if (hashes_count > node_limit) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }

    LanternRoot siblings_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_digest_list_root(data + siblings_start, siblings_count, &siblings_root));

    LanternRoot hashes_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_digest_list_root(data + hashes_offset, hashes_count, &hashes_root));

    ssz_chunk_t chunks[3];
    chunk_from_root(&siblings_root, &chunks[0]);
    memset(chunks[1].bytes, 0, sizeof(chunks[1].bytes));
    memcpy(chunks[1].bytes, data + SSZ_BYTES_PER_LENGTH_OFFSET, LANTERN_XMSS_RHO_BYTES);
    chunk_from_root(&hashes_root, &chunks[2]);
    return merkleize_chunks(chunks, 3, 0, out_root);
}

static ssz_error_t hash_validator(
    const uint8_t *attestation_pubkey,
    const uint8_t *proposal_pubkey,
    uint64_t index,
    LanternRoot *out_root) {
    if (!out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot attestation_pubkey_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_byte_vector(
        attestation_pubkey,
        LANTERN_VALIDATOR_PUBKEY_SIZE,
        &attestation_pubkey_root));
    LanternRoot proposal_pubkey_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_byte_vector(
        proposal_pubkey,
        LANTERN_VALIDATOR_PUBKEY_SIZE,
        &proposal_pubkey_root));
    ssz_chunk_t chunks[3];
    chunk_from_root(&attestation_pubkey_root, &chunks[0]);
    chunk_from_root(&proposal_pubkey_root, &chunks[1]);
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(index, &chunks[2]));
    return merkleize_chunks(chunks, 3, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_config(const LanternConfig *config, LanternRoot *out_root) {
    if (!config || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    ssz_chunk_t chunks[1];
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(config->genesis_time, &chunks[0]));
    return merkleize_chunks(chunks, 1, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_checkpoint(const LanternCheckpoint *checkpoint, LanternRoot *out_root) {
    if (!checkpoint || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    ssz_chunk_t chunks[2];
    chunk_from_root(&checkpoint->root, &chunks[0]);
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(checkpoint->slot, &chunks[1]));
    return merkleize_chunks(chunks, 2, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_attestation_data(const LanternAttestationData *data, LanternRoot *out_root) {
    if (!data || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot head_root;
    LanternRoot target_root;
    LanternRoot source_root;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_checkpoint(&data->head, &head_root));
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_checkpoint(&data->target, &target_root));
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_checkpoint(&data->source, &source_root));
    ssz_chunk_t chunks[4];
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(data->slot, &chunks[0]));
    chunk_from_root(&head_root, &chunks[1]);
    chunk_from_root(&target_root, &chunks[2]);
    chunk_from_root(&source_root, &chunks[3]);
    return merkleize_chunks(chunks, 4, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_vote(const LanternVote *vote, LanternRoot *out_root) {
    if (!vote || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot data_root;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_attestation_data(&vote->data, &data_root));
    ssz_chunk_t chunks[2];
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(vote->validator_id, &chunks[0]));
    chunk_from_root(&data_root, &chunks[1]);
    return merkleize_chunks(chunks, 2, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_signed_vote(const LanternSignedVote *vote, LanternRoot *out_root) {
    if (!vote || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot data_root;
    LanternRoot signature_root;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_attestation_data(&vote->data.data, &data_root));
    LANTERN_RETURN_IF_SSZ_ERROR(hash_xmss_signature(&vote->signature, &signature_root));
    ssz_chunk_t chunks[3];
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(vote->data.validator_id, &chunks[0]));
    chunk_from_root(&data_root, &chunks[1]);
    chunk_from_root(&signature_root, &chunks[2]);
    return merkleize_chunks(chunks, 3, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_signature(const LanternSignature *signature, LanternRoot *out_root) {
    return hash_xmss_signature(signature, out_root);
}

ssz_error_t lantern_hash_tree_root_validator(const LanternValidator *validator, LanternRoot *out_root) {
    if (!validator || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    return hash_validator(
        validator->attestation_pubkey,
        validator->proposal_pubkey,
        validator->index,
        out_root);
}

ssz_error_t lantern_hash_tree_root_aggregated_attestation(const LanternAggregatedAttestation *attestation, LanternRoot *out_root) {
    if (!attestation || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (attestation->aggregation_bits.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }
    LanternRoot bits_root;
    size_t bits_per_chunk = SSZ_BYTES_PER_CHUNK * 8u;
    size_t bitlist_limit = (LANTERN_VALIDATOR_REGISTRY_LIMIT + bits_per_chunk - 1u) / bits_per_chunk;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_merkleize_bitlist(&attestation->aggregation_bits, bitlist_limit, &bits_root));
    LanternRoot data_root;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_attestation_data(&attestation->data, &data_root));
    ssz_chunk_t chunks[2];
    chunk_from_root(&bits_root, &chunks[0]);
    chunk_from_root(&data_root, &chunks[1]);
    return merkleize_chunks(chunks, 2, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_aggregated_signature_proof(
    const LanternAggregatedSignatureProof *proof,
    LanternRoot *out_root) {
    if (!proof || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (proof->participants.bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }
    if (proof->proof_data.length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return SSZ_ERR_LIMIT_EXCEEDED;
    }
    LanternRoot participants_root;
    size_t bits_per_chunk = SSZ_BYTES_PER_CHUNK * 8u;
    size_t bitlist_limit = (LANTERN_VALIDATOR_REGISTRY_LIMIT + bits_per_chunk - 1u) / bits_per_chunk;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_merkleize_bitlist(&proof->participants, bitlist_limit, &participants_root));
    LanternRoot proof_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_byte_list(
        proof->proof_data.data,
        proof->proof_data.length,
        LANTERN_AGG_PROOF_MAX_BYTES,
        &proof_root));
    ssz_chunk_t chunks[2];
    chunk_from_root(&participants_root, &chunks[0]);
    chunk_from_root(&proof_root, &chunks[1]);
    return merkleize_chunks(chunks, 2, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_multi_message_aggregate(
    const LanternByteList *aggregate,
    LanternRoot *out_root) {
    if (!aggregate || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    const uint8_t *raw = NULL;
    size_t raw_len = 0u;
    LANTERN_RETURN_IF_SSZ_ERROR(
        lantern_ssz_multi_message_aggregate_raw_span(aggregate, &raw, &raw_len));
    LanternRoot proof_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_byte_list(
        raw,
        raw_len,
        LANTERN_AGG_PROOF_MAX_BYTES,
        &proof_root));
    ssz_chunk_t chunks[1];
    chunk_from_root(&proof_root, &chunks[0]);
    return merkleize_chunks(chunks, 1, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_signed_aggregated_attestation(
    const LanternSignedAggregatedAttestation *attestation,
    LanternRoot *out_root) {
    if (!attestation || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot data_root;
    LanternRoot proof_root;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_attestation_data(&attestation->data, &data_root));
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_aggregated_signature_proof(&attestation->proof, &proof_root));
    ssz_chunk_t chunks[2];
    chunk_from_root(&data_root, &chunks[0]);
    chunk_from_root(&proof_root, &chunks[1]);
    return merkleize_chunks(chunks, 2, 0, out_root);
}

ssz_error_t lantern_merkleize_root_list(
    const struct lantern_root_list *list,
    size_t limit,
    LanternRoot *out_root) {
    if (!list || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    size_t count = list->length;
    ssz_chunk_t root;
    ssz_chunk_t *roots = NULL;
    if (count > 0) {
        if (!list->items) {
            return SSZ_ERR_INVALID_ARGUMENT;
        }
        roots = calloc(count, sizeof(*roots));
        if (!roots) {
            return SSZ_ERR_HASH_FAILURE;
        }
        for (size_t i = 0; i < count; ++i) {
            chunk_from_root(&list->items[i], &roots[i]);
        }
    }
    ssz_error_t err = ssz_hash_tree_root_list_roots(roots, count, limit, NULL, NULL, &root);
    free(roots);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}

ssz_error_t lantern_merkleize_bitlist(
    const struct lantern_bitlist *bitlist,
    size_t limit,
    LanternRoot *out_root) {
    if (!bitlist || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    size_t bit_count = bitlist->bit_length;
    if (bit_count > 0 && !bitlist->bytes) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (limit > (SIZE_MAX / (SSZ_BYTES_PER_CHUNK * 8u))) {
        return SSZ_ERR_OVERFLOW;
    }
    size_t bitfield_len = bit_count ? ((bit_count + 7u) / 8u) : 0u;
    uint64_t bit_limit = (uint64_t)limit * (uint64_t)SSZ_BYTES_PER_CHUNK * 8u;
    ssz_chunk_t root;
    ssz_error_t err = ssz_hash_tree_root_bitlist(
        bitlist->bytes,
        bitfield_len,
        bit_count,
        bit_limit,
        NULL,
        NULL,
        &root);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}

static ssz_error_t hash_aggregated_attestations(const LanternAggregatedAttestations *attestations, LanternRoot *out_root) {
    if (!attestations || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    size_t count = attestations->length;
    ssz_chunk_t *chunks = NULL;
    if (count > 0) {
        if (!attestations->data) {
            return SSZ_ERR_INVALID_ARGUMENT;
        }
        if (count > LANTERN_MAX_ATTESTATIONS) {
            return SSZ_ERR_LIMIT_EXCEEDED;
        }
        chunks = calloc(count, sizeof(*chunks));
        if (!chunks) {
            return SSZ_ERR_HASH_FAILURE;
        }
        for (size_t i = 0; i < count; ++i) {
            LanternRoot att_root;
            ssz_error_t err = lantern_hash_tree_root_aggregated_attestation(&attestations->data[i], &att_root);
            if (err != SSZ_SUCCESS) {
                free(chunks);
                return err;
            }
            chunk_from_root(&att_root, &chunks[i]);
        }
    }
    ssz_chunk_t root;
    ssz_error_t err = ssz_hash_tree_root_list_roots(
        chunks,
        attestations->length,
        LANTERN_MAX_ATTESTATIONS,
        NULL,
        NULL,
        &root);
    free(chunks);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}

ssz_error_t lantern_hash_tree_root_block_body(const LanternBlockBody *body, LanternRoot *out_root) {
    if (!body || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot att_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_aggregated_attestations(&body->attestations, &att_root));
    ssz_chunk_t chunks[1];
    chunk_from_root(&att_root, &chunks[0]);
    return merkleize_chunks(chunks, 1, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_block_header(const LanternBlockHeader *header, LanternRoot *out_root) {
    if (!header || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    ssz_chunk_t chunks[5];
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(header->slot, &chunks[0]));
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(header->proposer_index, &chunks[1]));
    chunk_from_root(&header->parent_root, &chunks[2]);
    chunk_from_root(&header->state_root, &chunks[3]);
    chunk_from_root(&header->body_root, &chunks[4]);
    return merkleize_chunks(chunks, 5, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_block(const LanternBlock *block, LanternRoot *out_root) {
    if (!block || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot body_root;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_block_body(&block->body, &body_root));
    ssz_chunk_t chunks[5];
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(block->slot, &chunks[0]));
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(block->proposer_index, &chunks[1]));
    chunk_from_root(&block->parent_root, &chunks[2]);
    chunk_from_root(&block->state_root, &chunks[3]);
    chunk_from_root(&body_root, &chunks[4]);
    return merkleize_chunks(chunks, 5, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_signed_block(const LanternSignedBlock *block, LanternRoot *out_root) {
    if (!block || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot message_root;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_block(&block->block, &message_root));
    LanternRoot proof_root;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_multi_message_aggregate(&block->proof, &proof_root));
    ssz_chunk_t chunks[2];
    chunk_from_root(&message_root, &chunks[0]);
    chunk_from_root(&proof_root, &chunks[1]);
    return merkleize_chunks(chunks, 2, 0, out_root);
}

struct lantern_merkle_cache_box {
    ssz_merkle_cache_t cache;
    ssz_merkle_cache_storage_t storage;
    ssz_merkle_cache_sync_workspace_t workspace;
    ssz_chunk_t *nodes;
    uint64_t *leaf_dirty_bits;
    size_t *leaf_dirty_word_idx;
    uint64_t *parent_dirty_bits[2];
    size_t *parent_dirty_word_idx[2];
    ssz_chunk_t *gather_pairs;
    ssz_chunk_t *gather_hashes;
    size_t *gather_parent_indices;
    uint64_t *token_values;
    uint64_t *token_valid_bits;
    ssz_chunk_t *root_batch_roots;
    bool bound;
};

struct lantern_state_hash_cache {
    struct lantern_merkle_cache_box state_root;
    struct lantern_merkle_cache_box validators;
};

static void merkle_cache_box_reset(struct lantern_merkle_cache_box *box) {
    if (!box) {
        return;
    }
    free(box->nodes);
    free(box->leaf_dirty_bits);
    free(box->leaf_dirty_word_idx);
    free(box->parent_dirty_bits[0]);
    free(box->parent_dirty_bits[1]);
    free(box->parent_dirty_word_idx[0]);
    free(box->parent_dirty_word_idx[1]);
    free(box->gather_pairs);
    free(box->gather_hashes);
    free(box->gather_parent_indices);
    free(box->token_values);
    free(box->token_valid_bits);
    free(box->root_batch_roots);
    memset(box, 0, sizeof(*box));
}

static void *cache_alloc(size_t count, size_t item_size) {
    return count == 0u ? NULL : calloc(count, item_size);
}

static bool cache_allocation_missing(const void *ptr, size_t count) {
    return count != 0u && !ptr;
}

static ssz_error_t merkle_cache_box_bind(
    struct lantern_merkle_cache_box *box,
    uint64_t initial_leaf_count,
    uint64_t leaf_limit,
    uint64_t reserved_leaf_capacity,
    uint64_t logical_length,
    bool mix_in_length,
    bool with_tokens) {
    if (!box) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (box->bound) {
        return SSZ_SUCCESS;
    }

    ssz_merkle_cache_config_t config;
    memset(&config, 0, sizeof(config));
    config.struct_size = sizeof(config);
    config.initial_leaf_count = initial_leaf_count;
    config.leaf_limit = leaf_limit;
    config.reserved_leaf_capacity = reserved_leaf_capacity;
    config.logical_length = logical_length;
    config.mix_in_length = mix_in_length;
    config.hash_fn = NULL;

    ssz_merkle_cache_requirements_t req;
    ssz_error_t err = ssz_merkle_cache_requirements(&config, &req);
    if (err != SSZ_SUCCESS) {
        return err;
    }

    box->nodes = cache_alloc(req.nodes_count, sizeof(*box->nodes));
    box->leaf_dirty_bits = cache_alloc(req.leaf_dirty_words, sizeof(*box->leaf_dirty_bits));
    box->leaf_dirty_word_idx = cache_alloc(req.leaf_dirty_words, sizeof(*box->leaf_dirty_word_idx));
    box->parent_dirty_bits[0] = cache_alloc(req.parent_dirty_words, sizeof(*box->parent_dirty_bits[0]));
    box->parent_dirty_bits[1] = cache_alloc(req.parent_dirty_words, sizeof(*box->parent_dirty_bits[1]));
    box->parent_dirty_word_idx[0] = cache_alloc(req.parent_dirty_words, sizeof(*box->parent_dirty_word_idx[0]));
    box->parent_dirty_word_idx[1] = cache_alloc(req.parent_dirty_words, sizeof(*box->parent_dirty_word_idx[1]));
    box->gather_pairs = cache_alloc(req.gather_pairs_count, sizeof(*box->gather_pairs));
    box->gather_hashes = cache_alloc(req.gather_hashes_count, sizeof(*box->gather_hashes));
    box->gather_parent_indices = cache_alloc(req.gather_parent_indices_count, sizeof(*box->gather_parent_indices));
    box->root_batch_roots = cache_alloc(req.root_batch_roots_count, sizeof(*box->root_batch_roots));
    if (with_tokens) {
        box->token_values = cache_alloc(req.token_values_count, sizeof(*box->token_values));
        box->token_valid_bits = cache_alloc(req.token_valid_words, sizeof(*box->token_valid_bits));
    }

    if (cache_allocation_missing(box->nodes, req.nodes_count)
        || cache_allocation_missing(box->leaf_dirty_bits, req.leaf_dirty_words)
        || cache_allocation_missing(box->leaf_dirty_word_idx, req.leaf_dirty_words)
        || cache_allocation_missing(box->parent_dirty_bits[0], req.parent_dirty_words)
        || cache_allocation_missing(box->parent_dirty_bits[1], req.parent_dirty_words)
        || cache_allocation_missing(box->parent_dirty_word_idx[0], req.parent_dirty_words)
        || cache_allocation_missing(box->parent_dirty_word_idx[1], req.parent_dirty_words)
        || cache_allocation_missing(box->gather_pairs, req.gather_pairs_count)
        || cache_allocation_missing(box->gather_hashes, req.gather_hashes_count)
        || cache_allocation_missing(box->gather_parent_indices, req.gather_parent_indices_count)
        || cache_allocation_missing(box->root_batch_roots, req.root_batch_roots_count)
        || (with_tokens && cache_allocation_missing(box->token_values, req.token_values_count))
        || (with_tokens && cache_allocation_missing(box->token_valid_bits, req.token_valid_words))) {
        merkle_cache_box_reset(box);
        return SSZ_ERR_HASH_FAILURE;
    }

    box->storage.struct_size = sizeof(box->storage);
    box->storage.nodes = box->nodes;
    box->storage.nodes_count = req.nodes_count;
    box->storage.leaf_dirty_bits = box->leaf_dirty_bits;
    box->storage.leaf_dirty_words = req.leaf_dirty_words;
    box->storage.leaf_dirty_word_idx = box->leaf_dirty_word_idx;
    box->storage.leaf_dirty_word_idx_count = req.leaf_dirty_words;
    box->storage.parent_dirty_bits[0] = box->parent_dirty_bits[0];
    box->storage.parent_dirty_bits[1] = box->parent_dirty_bits[1];
    box->storage.parent_dirty_words = req.parent_dirty_words;
    box->storage.parent_dirty_word_idx[0] = box->parent_dirty_word_idx[0];
    box->storage.parent_dirty_word_idx[1] = box->parent_dirty_word_idx[1];
    box->storage.parent_dirty_word_idx_count = req.parent_dirty_words;
    box->storage.gather_pairs = box->gather_pairs;
    box->storage.gather_pairs_count = req.gather_pairs_count;
    box->storage.gather_hashes = box->gather_hashes;
    box->storage.gather_hashes_count = req.gather_hashes_count;
    box->storage.gather_parent_indices = box->gather_parent_indices;
    box->storage.gather_parent_indices_count = req.gather_parent_indices_count;
    box->storage.token_values = box->token_values;
    box->storage.token_values_count = with_tokens ? req.token_values_count : 0u;
    box->storage.token_valid_bits = box->token_valid_bits;
    box->storage.token_valid_words = with_tokens ? req.token_valid_words : 0u;

    box->workspace.struct_size = sizeof(box->workspace);
    box->workspace.root_batch_roots = box->root_batch_roots;
    box->workspace.root_batch_roots_count = req.root_batch_roots_count;

    err = ssz_merkle_cache_bind(&config, &box->storage, &box->cache);
    if (err != SSZ_SUCCESS) {
        merkle_cache_box_reset(box);
        return err;
    }
    box->bound = true;
    return SSZ_SUCCESS;
}

static struct lantern_state_hash_cache *state_hash_cache_ensure(LanternState *state) {
    if (!state) {
        return NULL;
    }
    if (!state->hash_cache) {
        state->hash_cache = calloc(1u, sizeof(*state->hash_cache));
    }
    return state->hash_cache;
}

void lantern_state_hash_cache_reset(LanternState *state) {
    if (!state || !state->hash_cache) {
        return;
    }
    merkle_cache_box_reset(&state->hash_cache->state_root);
    merkle_cache_box_reset(&state->hash_cache->validators);
    free(state->hash_cache);
    state->hash_cache = NULL;
}

static ssz_error_t hash_state_validators_stateless(const LanternState *state, LanternRoot *out_root) {
    if (!state || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    if (state->validator_count == 0) {
        ssz_chunk_t root;
        ssz_error_t err = ssz_hash_tree_root_list_roots(
            NULL, 0u, LANTERN_VALIDATOR_REGISTRY_LIMIT, NULL, NULL, &root);
        if (err == SSZ_SUCCESS) {
            root_from_chunk(&root, out_root);
        }
        return err;
    }
    if (!state->validators) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    ssz_chunk_t *validator_chunks = calloc(state->validator_count, sizeof(*validator_chunks));
    if (!validator_chunks) {
        return SSZ_ERR_HASH_FAILURE;
    }
    for (size_t i = 0; i < state->validator_count; ++i) {
        LanternRoot validator_root;
        ssz_error_t err = hash_validator(
                state->validators[i].attestation_pubkey,
                state->validators[i].proposal_pubkey,
                state->validators[i].index,
                &validator_root);
        if (err != SSZ_SUCCESS) {
            free(validator_chunks);
            return err;
        }
        chunk_from_root(&validator_root, &validator_chunks[i]);
    }
    ssz_chunk_t root;
    ssz_error_t err = ssz_hash_tree_root_list_roots(
        validator_chunks,
        state->validator_count,
        LANTERN_VALIDATOR_REGISTRY_LIMIT,
        NULL,
        NULL,
        &root);
    free(validator_chunks);
    if (err != SSZ_SUCCESS) {
        return err;
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}

struct validator_cache_ctx {
    const LanternState *state;
};

static void fnv1a_update(uint64_t *hash, const uint8_t *bytes, size_t len) {
    const uint64_t fnv_prime = UINT64_C(1099511628211);
    if (!hash || (!bytes && len > 0u)) {
        return;
    }
    for (size_t i = 0; i < len; ++i) {
        *hash ^= bytes[i];
        *hash *= fnv_prime;
    }
}

static uint64_t validator_cache_token_one(const LanternValidator *validator) {
    uint64_t hash = UINT64_C(1469598103934665603);
    fnv1a_update(&hash, validator->attestation_pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE);
    fnv1a_update(&hash, validator->proposal_pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE);
    uint8_t index_le[sizeof(uint64_t)];
    for (size_t i = 0; i < sizeof(index_le); ++i) {
        index_le[i] = (uint8_t)((validator->index >> (i * 8u)) & 0xFFu);
    }
    fnv1a_update(&hash, index_le, sizeof(index_le));
    return hash == 0u ? 1u : hash;
}

static ssz_error_t validator_cache_token(const void *ctx, uint64_t member_id, uint64_t *out_token) {
    const struct validator_cache_ctx *cache_ctx = ctx;
    if (!cache_ctx || !cache_ctx->state || !out_token || member_id >= cache_ctx->state->validator_count) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    *out_token = validator_cache_token_one(&cache_ctx->state->validators[member_id]);
    return SSZ_SUCCESS;
}

static ssz_error_t validator_cache_root_one(
    const LanternState *state,
    uint64_t member_id,
    ssz_chunk_t *out_root) {
    if (!state || !state->validators || !out_root || member_id >= state->validator_count) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot root;
    const LanternValidator *validator = &state->validators[member_id];
    LANTERN_RETURN_IF_SSZ_ERROR(hash_validator(
        validator->attestation_pubkey,
        validator->proposal_pubkey,
        validator->index,
        &root));
    chunk_from_root(&root, out_root);
    return SSZ_SUCCESS;
}

static ssz_error_t validator_cache_root(const void *ctx, uint64_t member_id, ssz_chunk_t *out_root) {
    const struct validator_cache_ctx *cache_ctx = ctx;
    return validator_cache_root_one(cache_ctx ? cache_ctx->state : NULL, member_id, out_root);
}

static ssz_error_t validator_cache_root_batch(
    const void *ctx,
    uint64_t start_index,
    uint64_t count,
    ssz_chunk_t *out_roots) {
    const struct validator_cache_ctx *cache_ctx = ctx;
    if (!cache_ctx || !cache_ctx->state || !out_roots) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    for (uint64_t i = 0; i < count; ++i) {
        ssz_error_t err = validator_cache_root_one(cache_ctx->state, start_index + i, &out_roots[i]);
        if (err != SSZ_SUCCESS) {
            return err;
        }
    }
    return SSZ_SUCCESS;
}

static ssz_error_t hash_state_validators_cached(LanternState *state, LanternRoot *out_root) {
    if (!state || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    struct lantern_state_hash_cache *cache = state_hash_cache_ensure(state);
    if (!cache) {
        return hash_state_validators_stateless(state, out_root);
    }
    if (merkle_cache_box_bind(
            &cache->validators,
            0u,
            LANTERN_VALIDATOR_REGISTRY_LIMIT,
            LANTERN_VALIDATOR_REGISTRY_LIMIT,
            0u,
            true,
            true)
        != SSZ_SUCCESS) {
        return hash_state_validators_stateless(state, out_root);
    }

    struct validator_cache_ctx ctx = {.state = state};
    ssz_member_codec_t codec = {
        .ctx = &ctx,
        .write = NULL,
        .read = NULL,
        .root = validator_cache_root,
    };
    ssz_merkle_cache_sync_composite_opts_t opts;
    memset(&opts, 0, sizeof(opts));
    opts.struct_size = sizeof(opts);
    opts.ctx = &ctx;
    opts.token = validator_cache_token;
    opts.root_batch = validator_cache_root_batch;
    opts.workspace = &cache->validators.workspace;

    ssz_error_t err = ssz_merkle_cache_sync_composite(
        &cache->validators.cache,
        state->validator_count,
        LANTERN_VALIDATOR_REGISTRY_LIMIT,
        &codec,
        &opts);
    if (err != SSZ_SUCCESS) {
        return hash_state_validators_stateless(state, out_root);
    }
    ssz_chunk_t root;
    if (ssz_merkle_cache_root(&cache->validators.cache, &root) != SSZ_SUCCESS) {
        return hash_state_validators_stateless(state, out_root);
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}

static ssz_error_t state_field_chunks(
    const LanternState *state,
    const LanternRoot *validators_root,
    ssz_chunk_t chunks[10]) {
    if (!state || !validators_root || !chunks) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }

    LanternRoot config_root;
    LanternRoot header_root;
    LanternRoot justified_root;
    LanternRoot finalized_root;
    LanternRoot historical_root;
    LanternRoot justified_slots_root;
    LanternRoot justification_roots_root;
    LanternRoot justification_validators_root;

    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_config(&state->config, &config_root));
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_block_header(&state->latest_block_header, &header_root));
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_checkpoint(&state->latest_justified, &justified_root));
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_hash_tree_root_checkpoint(&state->latest_finalized, &finalized_root));
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_merkleize_root_list(&state->historical_block_hashes, LANTERN_HISTORICAL_ROOTS_LIMIT, &historical_root));
    size_t bits_per_chunk = SSZ_BYTES_PER_CHUNK * 8u;
    size_t justified_chunk_limit = (LANTERN_HISTORICAL_ROOTS_LIMIT + bits_per_chunk - 1u) / bits_per_chunk;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_merkleize_bitlist(&state->justified_slots, justified_chunk_limit, &justified_slots_root));
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_merkleize_root_list(
        &state->justification_roots,
        LANTERN_HISTORICAL_ROOTS_LIMIT,
        &justification_roots_root));
    size_t justification_validators_chunk_limit =
        (LANTERN_JUSTIFICATION_VALIDATORS_LIMIT + bits_per_chunk - 1u) / bits_per_chunk;
    LANTERN_RETURN_IF_SSZ_ERROR(lantern_merkleize_bitlist(
            &state->justification_validators,
            justification_validators_chunk_limit,
            &justification_validators_root));

    chunk_from_root(&config_root, &chunks[0]);
    LANTERN_RETURN_IF_SSZ_ERROR(chunk_from_uint64(state->slot, &chunks[1]));
    chunk_from_root(&header_root, &chunks[2]);
    chunk_from_root(&justified_root, &chunks[3]);
    chunk_from_root(&finalized_root, &chunks[4]);
    chunk_from_root(&historical_root, &chunks[5]);
    chunk_from_root(&justified_slots_root, &chunks[6]);
    chunk_from_root(validators_root, &chunks[7]);
    chunk_from_root(&justification_roots_root, &chunks[8]);
    chunk_from_root(&justification_validators_root, &chunks[9]);
    return SSZ_SUCCESS;
}

ssz_error_t lantern_hash_tree_root_state(const LanternState *state, LanternRoot *out_root) {
    if (!state || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot validators_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_state_validators_stateless(state, &validators_root));
    ssz_chunk_t chunks[10];
    LANTERN_RETURN_IF_SSZ_ERROR(state_field_chunks(state, &validators_root, chunks));
    return merkleize_chunks(chunks, 10, 0, out_root);
}

ssz_error_t lantern_hash_tree_root_state_cached(LanternState *state, LanternRoot *out_root) {
    if (!state || !out_root) {
        return SSZ_ERR_INVALID_ARGUMENT;
    }
    LanternRoot validators_root;
    LANTERN_RETURN_IF_SSZ_ERROR(hash_state_validators_cached(state, &validators_root));
    ssz_chunk_t chunks[10];
    LANTERN_RETURN_IF_SSZ_ERROR(state_field_chunks(state, &validators_root, chunks));

    struct lantern_state_hash_cache *cache = state_hash_cache_ensure(state);
    if (!cache
        || merkle_cache_box_bind(&cache->state_root, 0u, SSZ_NO_LIMIT, 10u, 0u, false, false) != SSZ_SUCCESS) {
        return merkleize_chunks(chunks, 10, 0, out_root);
    }
    if (ssz_merkle_cache_update_root_range(&cache->state_root.cache, 0u, chunks, 10u) != SSZ_SUCCESS) {
        return merkleize_chunks(chunks, 10, 0, out_root);
    }
    ssz_chunk_t root;
    if (ssz_merkle_cache_root(&cache->state_root.cache, &root) != SSZ_SUCCESS) {
        return merkleize_chunks(chunks, 10, 0, out_root);
    }
    root_from_chunk(&root, out_root);
    return SSZ_SUCCESS;
}
