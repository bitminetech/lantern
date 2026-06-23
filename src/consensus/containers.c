#include "lantern/consensus/containers.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static void *grow_capacity(
    void *items,
    size_t *capacity,
    size_t required,
    size_t element_size,
    size_t initial_capacity) {
    if (!capacity || element_size == 0 || initial_capacity == 0) {
        return NULL;
    }
    if (*capacity >= required) {
        return items;
    }
    size_t new_capacity = *capacity == 0 ? initial_capacity : *capacity;
    while (new_capacity < required) {
        if (new_capacity > SIZE_MAX / 2) {
            return NULL;
        }
        new_capacity *= 2;
    }
    if (new_capacity > SIZE_MAX / element_size) {
        return NULL;
    }
    void *grown = realloc(items, new_capacity * element_size);
    if (!grown) {
        return NULL;
    }
    *capacity = new_capacity;
    return grown;
}

#define ENSURE_CAPACITY(list, field, required, initial_capacity)                         \
    do {                                                                                \
        void *grown = grow_capacity(                                                    \
            (list)->field,                                                              \
            &(list)->capacity,                                                          \
            (required),                                                                 \
            sizeof(*(list)->field),                                                     \
            (initial_capacity));                                                        \
        if (!grown) {                                                                   \
            return -1;                                                                  \
        }                                                                               \
        (list)->field = grown;                                                          \
    } while (0)

void lantern_attestations_init(LanternAttestations *list) {
    if (!list) {
        return;
    }
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

void lantern_attestations_reset(LanternAttestations *list) {
    if (!list) {
        return;
    }
    free(list->data);
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

int lantern_attestations_append(LanternAttestations *list, const LanternVote *vote) {
    if (!list || !vote) {
        return -1;
    }
    ENSURE_CAPACITY(list, data, list->length + 1, 4);
    list->data[list->length++] = *vote;
    return 0;
}

int lantern_attestations_resize(LanternAttestations *list, size_t new_length) {
    if (!list) {
        return -1;
    }
    if (new_length == 0) {
        if (list->data && list->length > 0) {
            memset(list->data, 0, list->length * sizeof(*list->data));
        }
        list->length = 0;
        return 0;
    }
    ENSURE_CAPACITY(list, data, new_length, 4);
    if (!list->data) {
        return -1;
    }
    size_t old_length = list->length;
    if (new_length > old_length) {
        size_t start = old_length;
        size_t added = new_length - old_length;
        memset(&list->data[start], 0, added * sizeof(*list->data));
    } else if (new_length < old_length) {
        size_t removed = old_length - new_length;
        memset(&list->data[new_length], 0, removed * sizeof(*list->data));
    }
    list->length = new_length;
    return 0;
}

void lantern_validator_indices_init(LanternValidatorIndices *indices) {
    if (!indices) {
        return;
    }
    indices->data = NULL;
    indices->length = 0;
    indices->capacity = 0;
}

void lantern_validator_indices_reset(LanternValidatorIndices *indices) {
    if (!indices) {
        return;
    }
    free(indices->data);
    indices->data = NULL;
    indices->length = 0;
    indices->capacity = 0;
}

int lantern_validator_indices_append(LanternValidatorIndices *indices, LanternValidatorIndex index) {
    if (!indices || index >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (indices->length >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    ENSURE_CAPACITY(indices, data, indices->length + 1, 4);
    indices->data[indices->length++] = index;
    return 0;
}

int lantern_validator_indices_resize(LanternValidatorIndices *indices, size_t new_length) {
    if (!indices || new_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (new_length == 0) {
        if (indices->data && indices->length > 0) {
            memset(indices->data, 0, indices->length * sizeof(*indices->data));
        }
        indices->length = 0;
        return 0;
    }
    ENSURE_CAPACITY(indices, data, new_length, 4);
    if (!indices->data) {
        return -1;
    }
    size_t old_length = indices->length;
    if (new_length > old_length) {
        memset(&indices->data[old_length], 0, (new_length - old_length) * sizeof(*indices->data));
    } else if (new_length < old_length) {
        memset(&indices->data[new_length], 0, (old_length - new_length) * sizeof(*indices->data));
    }
    indices->length = new_length;
    return 0;
}

int lantern_validator_index_compute_subnet_id(
    LanternValidatorIndex index,
    size_t num_committees,
    size_t *out_subnet_id) {
    if (!out_subnet_id || num_committees == 0) {
        return -1;
    }
    *out_subnet_id = (size_t)index % num_committees;
    return 0;
}

int lantern_aggregation_bits_from_validator_indices(
    struct lantern_bitlist *out_bits,
    const LanternValidatorIndices *indices) {
    if (!out_bits || !indices || indices->length == 0 || !indices->data) {
        return -1;
    }
    if (indices->length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }

    LanternValidatorIndex max_index = 0;
    for (size_t i = 0; i < indices->length; ++i) {
        LanternValidatorIndex index = indices->data[i];
        if (index >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
            return -1;
        }
        if (index > max_index) {
            max_index = index;
        }
    }

    if (lantern_bitlist_resize(out_bits, (size_t)max_index + 1u) != 0) {
        return -1;
    }
    for (size_t i = 0; i < indices->length; ++i) {
        if (lantern_bitlist_set(out_bits, (size_t)indices->data[i], true) != 0) {
            return -1;
        }
    }
    return 0;
}

int lantern_aggregation_bits_to_validator_indices(
    const struct lantern_bitlist *bits,
    LanternValidatorIndices *out_indices) {
    if (!bits || !out_indices || bits->bit_length == 0) {
        return -1;
    }
    if (bits->bit_length > LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    if (!bits->bytes) {
        return -1;
    }
    if (lantern_validator_indices_resize(out_indices, 0) != 0) {
        return -1;
    }
    for (size_t i = 0; i < bits->bit_length; ++i) {
        if (lantern_bitlist_get(bits, i)
            && lantern_validator_indices_append(out_indices, (LanternValidatorIndex)i) != 0) {
            (void)lantern_validator_indices_resize(out_indices, 0);
            return -1;
        }
    }
    if (out_indices->length == 0) {
        return -1;
    }
    return 0;
}

void lantern_bitlist_init(struct lantern_bitlist *list) {
    if (!list) {
        return;
    }
    list->bytes = NULL;
    list->bit_length = 0;
    list->capacity = 0;
}

void lantern_bitlist_reset(struct lantern_bitlist *list) {
    if (!list) {
        return;
    }
    free(list->bytes);
    list->bytes = NULL;
    list->bit_length = 0;
    list->capacity = 0;
}

int lantern_bitlist_resize(struct lantern_bitlist *list, size_t new_bit_length) {
    if (!list) {
        return -1;
    }
    if (new_bit_length == 0) {
        if (list->bytes && list->bit_length > 0) {
            size_t old_bytes = (list->bit_length + 7u) / 8u;
            memset(list->bytes, 0, old_bytes);
        }
        list->bit_length = 0;
        return 0;
    }
    size_t required_bytes = (new_bit_length + 7u) / 8u;
    ENSURE_CAPACITY(list, bytes, required_bytes, 4);
    if (!list->bytes) {
        return -1;
    }
    size_t old_bytes = (list->bit_length + 7u) / 8u;
    if (required_bytes > old_bytes) {
        memset(list->bytes + old_bytes, 0, required_bytes - old_bytes);
    }
    if (new_bit_length < list->bit_length && required_bytes > 0) {
        size_t start_bit = new_bit_length;
        size_t start_byte = start_bit / 8u;
        size_t start_bit_offset = start_bit % 8u;
        if (start_byte < required_bytes) {
            if (start_bit_offset > 0) {
                uint8_t mask = (uint8_t)((1u << start_bit_offset) - 1u);
                list->bytes[start_byte] &= mask;
                ++start_byte;
            }
            if (start_byte < required_bytes) {
                memset(list->bytes + start_byte, 0, required_bytes - start_byte);
            }
        }
        if (required_bytes < old_bytes) {
            memset(list->bytes + required_bytes, 0, old_bytes - required_bytes);
        }
    }
    list->bit_length = new_bit_length;
    return 0;
}

bool lantern_bitlist_get(const struct lantern_bitlist *list, size_t index) {
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

int lantern_bitlist_set(struct lantern_bitlist *list, size_t index, bool value) {
    if (!list || !list->bytes || index >= list->bit_length) {
        return -1;
    }
    size_t byte_index = index / 8u;
    if (byte_index >= list->capacity) {
        return -1;
    }
    uint8_t mask = (uint8_t)(1u << (index % 8u));
    if (value) {
        list->bytes[byte_index] |= mask;
    } else {
        list->bytes[byte_index] &= (uint8_t)~mask;
    }
    return 0;
}

void lantern_byte_list_init(LanternByteList *list) {
    if (!list) {
        return;
    }
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

void lantern_byte_list_reset(LanternByteList *list) {
    if (!list) {
        return;
    }
    free(list->data);
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

int lantern_byte_list_resize(LanternByteList *list, size_t new_length) {
    if (!list) {
        return -1;
    }
    if (new_length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return -1;
    }
    if (new_length == 0) {
        if (list->data && list->length > 0) {
            memset(list->data, 0, list->length);
        }
        list->length = 0;
        return 0;
    }
    ENSURE_CAPACITY(list, data, new_length, 64);
    if (!list->data) {
        return -1;
    }
    if (new_length > list->length) {
        memset(list->data + list->length, 0, new_length - list->length);
    } else if (new_length < list->length) {
        memset(list->data + new_length, 0, list->length - new_length);
    }
    list->length = new_length;
    return 0;
}

int lantern_byte_list_copy(LanternByteList *dst, const LanternByteList *src) {
    if (!dst || !src) {
        return -1;
    }
    if (src->length == 0) {
        lantern_byte_list_reset(dst);
        lantern_byte_list_init(dst);
        return 0;
    }
    if (src->length > LANTERN_AGG_PROOF_MAX_BYTES) {
        return -1;
    }
    ENSURE_CAPACITY(dst, data, src->length, 64);
    if (!dst->data || (src->length > 0 && !src->data)) {
        return -1;
    }
    memcpy(dst->data, src->data, src->length);
    dst->length = src->length;
    return 0;
}

void lantern_aggregated_attestation_init(LanternAggregatedAttestation *attestation) {
    if (!attestation) {
        return;
    }
    lantern_bitlist_init(&attestation->aggregation_bits);
    memset(&attestation->data, 0, sizeof(attestation->data));
}

void lantern_aggregated_attestation_reset(LanternAggregatedAttestation *attestation) {
    if (!attestation) {
        return;
    }
    lantern_bitlist_reset(&attestation->aggregation_bits);
    memset(&attestation->data, 0, sizeof(attestation->data));
}

int lantern_aggregated_attestation_copy(
    LanternAggregatedAttestation *dst,
    const LanternAggregatedAttestation *src) {
    if (!dst || !src) {
        return -1;
    }
    dst->data = src->data;
    if (lantern_bitlist_resize(&dst->aggregation_bits, src->aggregation_bits.bit_length) != 0) {
        return -1;
    }
    size_t byte_len = (src->aggregation_bits.bit_length + 7u) / 8u;
    if (byte_len > 0) {
        if (!src->aggregation_bits.bytes || !dst->aggregation_bits.bytes) {
            return -1;
        }
        memcpy(dst->aggregation_bits.bytes, src->aggregation_bits.bytes, byte_len);
    }
    return 0;
}

void lantern_aggregated_attestations_init(LanternAggregatedAttestations *list) {
    if (!list) {
        return;
    }
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

void lantern_aggregated_attestations_reset(LanternAggregatedAttestations *list) {
    if (!list) {
        return;
    }
    if (list->data) {
        for (size_t i = 0; i < list->length; ++i) {
            lantern_aggregated_attestation_reset(&list->data[i]);
        }
    }
    free(list->data);
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

int lantern_aggregated_attestations_append(
    LanternAggregatedAttestations *list,
    const LanternAggregatedAttestation *attestation) {
    if (!list || !attestation) {
        return -1;
    }
    ENSURE_CAPACITY(list, data, list->length + 1, 4);
    if (list->length >= list->capacity) {
        return -1;
    }
    lantern_aggregated_attestation_init(&list->data[list->length]);
    if (lantern_aggregated_attestation_copy(&list->data[list->length], attestation) != 0) {
        lantern_aggregated_attestation_reset(&list->data[list->length]);
        return -1;
    }
    list->length += 1;
    return 0;
}

int lantern_aggregated_attestations_copy(
    LanternAggregatedAttestations *dst,
    const LanternAggregatedAttestations *src) {
    if (!dst || !src) {
        return -1;
    }
    if (src->length == 0) {
        lantern_aggregated_attestations_reset(dst);
        lantern_aggregated_attestations_init(dst);
        return 0;
    }
    ENSURE_CAPACITY(dst, data, src->length, 4);
    for (size_t i = dst->length; i < src->length; ++i) {
        lantern_aggregated_attestation_init(&dst->data[i]);
    }
    for (size_t i = 0; i < src->length; ++i) {
        if (lantern_aggregated_attestation_copy(&dst->data[i], &src->data[i]) != 0) {
            return -1;
        }
    }
    dst->length = src->length;
    return 0;
}

int lantern_aggregated_attestations_resize(LanternAggregatedAttestations *list, size_t new_length) {
    if (!list) {
        return -1;
    }
    if (new_length == 0) {
        if (list->data && list->length > 0) {
            for (size_t i = 0; i < list->length; ++i) {
                lantern_aggregated_attestation_reset(&list->data[i]);
            }
        }
        list->length = 0;
        return 0;
    }
    ENSURE_CAPACITY(list, data, new_length, 4);
    size_t old_length = list->length;
    if (new_length > old_length) {
        for (size_t i = old_length; i < new_length; ++i) {
            lantern_aggregated_attestation_init(&list->data[i]);
        }
    } else if (new_length < old_length) {
        for (size_t i = new_length; i < old_length; ++i) {
            lantern_aggregated_attestation_reset(&list->data[i]);
        }
    }
    list->length = new_length;
    return 0;
}

int lantern_expand_aggregated_attestations(
    const LanternAggregatedAttestations *aggregated,
    size_t validator_count,
    LanternAttestations *out_attestations) {
    if (!aggregated || !out_attestations) {
        return -1;
    }
    if (lantern_attestations_resize(out_attestations, 0) != 0) {
        return -1;
    }
    if (validator_count == 0 || aggregated->length == 0) {
        return 0;
    }
    if (!aggregated->data) {
        return -1;
    }
    int rc = 0;
    for (size_t i = 0; i < aggregated->length; ++i) {
        const LanternAggregatedAttestation *att = &aggregated->data[i];
        size_t bit_length = att->aggregation_bits.bit_length;
        if (bit_length > 0 && !att->aggregation_bits.bytes) {
            rc = -1;
            break;
        }
        for (size_t v = 0; v < bit_length; ++v) {
            if (!lantern_bitlist_get(&att->aggregation_bits, v)) {
                continue;
            }
            if (v >= validator_count) {
                rc = -1;
                break;
            }
            if (out_attestations->length >= LANTERN_MAX_ATTESTATIONS) {
                rc = -1;
                break;
            }
            LanternVote vote;
            memset(&vote, 0, sizeof(vote));
            vote.validator_id = (uint64_t)v;
            vote.slot = att->data.slot;
            vote.head = att->data.head;
            vote.target = att->data.target;
            vote.source = att->data.source;
            if (lantern_attestations_append(out_attestations, &vote) != 0) {
                rc = -1;
                break;
            }
        }
        if (rc != 0) {
            break;
        }
    }
    if (rc != 0) {
        (void)lantern_attestations_resize(out_attestations, 0);
    }
    return rc;
}

void lantern_aggregated_signature_proof_init(LanternAggregatedSignatureProof *proof) {
    if (!proof) {
        return;
    }
    lantern_bitlist_init(&proof->participants);
    lantern_byte_list_init(&proof->proof_data);
}

void lantern_aggregated_signature_proof_reset(LanternAggregatedSignatureProof *proof) {
    if (!proof) {
        return;
    }
    lantern_bitlist_reset(&proof->participants);
    lantern_byte_list_reset(&proof->proof_data);
}

int lantern_aggregated_signature_proof_copy(
    LanternAggregatedSignatureProof *dst,
    const LanternAggregatedSignatureProof *src) {
    if (!dst || !src) {
        return -1;
    }
    if (lantern_bitlist_resize(&dst->participants, src->participants.bit_length) != 0) {
        return -1;
    }
    size_t byte_len = (src->participants.bit_length + 7u) / 8u;
    if (byte_len > 0) {
        if (!src->participants.bytes || !dst->participants.bytes) {
            return -1;
        }
        memcpy(dst->participants.bytes, src->participants.bytes, byte_len);
    }
    if (lantern_byte_list_copy(&dst->proof_data, &src->proof_data) != 0) {
        return -1;
    }
    return 0;
}

void lantern_signed_aggregated_attestation_init(LanternSignedAggregatedAttestation *attestation) {
    if (!attestation) {
        return;
    }
    memset(&attestation->data, 0, sizeof(attestation->data));
    lantern_aggregated_signature_proof_init(&attestation->proof);
}

void lantern_signed_aggregated_attestation_reset(LanternSignedAggregatedAttestation *attestation) {
    if (!attestation) {
        return;
    }
    memset(&attestation->data, 0, sizeof(attestation->data));
    lantern_aggregated_signature_proof_reset(&attestation->proof);
}

void lantern_attestation_signatures_init(LanternAttestationSignatures *list) {
    if (!list) {
        return;
    }
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

void lantern_attestation_signatures_reset(LanternAttestationSignatures *list) {
    if (!list) {
        return;
    }
    if (list->data) {
        for (size_t i = 0; i < list->length; ++i) {
            lantern_aggregated_signature_proof_reset(&list->data[i]);
        }
    }
    free(list->data);
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

int lantern_attestation_signatures_append(
    LanternAttestationSignatures *list,
    const LanternAggregatedSignatureProof *proof) {
    if (!list || !proof) {
        return -1;
    }
    ENSURE_CAPACITY(list, data, list->length + 1, 4);
    if (list->length >= list->capacity) {
        return -1;
    }
    lantern_aggregated_signature_proof_init(&list->data[list->length]);
    if (lantern_aggregated_signature_proof_copy(&list->data[list->length], proof) != 0) {
        lantern_aggregated_signature_proof_reset(&list->data[list->length]);
        return -1;
    }
    list->length += 1;
    return 0;
}

int lantern_attestation_signatures_resize(LanternAttestationSignatures *list, size_t new_length) {
    if (!list) {
        return -1;
    }
    if (new_length == 0) {
        if (list->data && list->length > 0) {
            for (size_t i = 0; i < list->length; ++i) {
                lantern_aggregated_signature_proof_reset(&list->data[i]);
            }
        }
        list->length = 0;
        return 0;
    }
    ENSURE_CAPACITY(list, data, new_length, 4);
    size_t old_length = list->length;
    if (new_length > old_length) {
        for (size_t i = old_length; i < new_length; ++i) {
            lantern_aggregated_signature_proof_init(&list->data[i]);
        }
    } else if (new_length < old_length) {
        for (size_t i = new_length; i < old_length; ++i) {
            lantern_aggregated_signature_proof_reset(&list->data[i]);
        }
    }
    list->length = new_length;
    return 0;
}

void lantern_signature_list_init(LanternSignatureList *list) {
    if (!list) {
        return;
    }
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

void lantern_signature_list_reset(LanternSignatureList *list) {
    if (!list) {
        return;
    }
    free(list->data);
    list->data = NULL;
    list->length = 0;
    list->capacity = 0;
}

int lantern_signature_list_append(LanternSignatureList *list, const LanternSignature *signature) {
    if (!list || !signature) {
        return -1;
    }
    ENSURE_CAPACITY(list, data, list->length + 1, 4);
    list->data[list->length++] = *signature;
    return 0;
}

int lantern_signature_list_resize(LanternSignatureList *list, size_t new_length) {
    if (!list) {
        return -1;
    }
    if (new_length == 0) {
        if (list->data && list->length > 0) {
            memset(list->data, 0, list->length * sizeof(*list->data));
        }
        list->length = 0;
        return 0;
    }
    ENSURE_CAPACITY(list, data, new_length, 4);
    if (!list->data) {
        return -1;
    }
    size_t old_length = list->length;
    if (new_length > old_length) {
        size_t start = old_length;
        size_t added = new_length - old_length;
        memset(&list->data[start], 0, added * sizeof(*list->data));
    } else if (new_length < old_length) {
        size_t removed = old_length - new_length;
        memset(&list->data[new_length], 0, removed * sizeof(*list->data));
    }
    list->length = new_length;
    return 0;
}

void lantern_block_body_init(LanternBlockBody *body) {
    if (!body) {
        return;
    }
    lantern_aggregated_attestations_init(&body->attestations);
}

void lantern_block_body_reset(LanternBlockBody *body) {
    if (!body) {
        return;
    }
    lantern_aggregated_attestations_reset(&body->attestations);
}

void lantern_block_init(LanternBlock *block) {
    if (!block) {
        return;
    }
    memset(block, 0, sizeof(*block));
    lantern_block_body_init(&block->body);
}

void lantern_block_reset(LanternBlock *block) {
    if (!block) {
        return;
    }
    lantern_block_body_reset(&block->body);
    memset(block, 0, sizeof(*block));
}

void lantern_signed_block_init(LanternSignedBlock *block) {
    if (!block) {
        return;
    }
    lantern_block_init(&block->block);
    lantern_byte_list_init(&block->proof);
}

void lantern_signed_block_reset(LanternSignedBlock *block) {
    if (!block) {
        return;
    }
    lantern_block_reset(&block->block);
    lantern_byte_list_reset(&block->proof);
}
