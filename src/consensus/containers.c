#include "lantern/consensus/containers.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static int ensure_capacity(LanternAttestations *list, size_t required) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required) {
        return 0;
    }

    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }

    LanternVote *items = realloc(list->data, new_capacity * sizeof(*items));
    if (!items) {
        return -1;
    }

    list->data = items;
    list->capacity = new_capacity;
    return 0;
}

static int ensure_signature_list_capacity(LanternSignatureList *list, size_t required) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required) {
        return 0;
    }

    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }

    LanternSignature *items = realloc(list->data, new_capacity * sizeof(*items));
    if (!items) {
        return -1;
    }

    list->data = items;
    list->capacity = new_capacity;
    return 0;
}

static int ensure_aggregated_att_capacity(LanternAggregatedAttestations *list, size_t required) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required) {
        return 0;
    }
    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }

    LanternAggregatedAttestation *items = realloc(list->data, new_capacity * sizeof(*items));
    if (!items) {
        return -1;
    }
    list->data = items;
    list->capacity = new_capacity;
    return 0;
}

static int ensure_attestation_signature_capacity(LanternAttestationSignatures *list, size_t required) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required) {
        return 0;
    }
    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }

    LanternAggregatedSignatureProof *items = realloc(list->data, new_capacity * sizeof(*items));
    if (!items) {
        return -1;
    }
    list->data = items;
    list->capacity = new_capacity;
    return 0;
}

static int ensure_byte_capacity(LanternByteList *list, size_t required) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required) {
        return 0;
    }
    size_t new_capacity = list->capacity == 0 ? 64 : list->capacity;
    while (new_capacity < required) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }

    uint8_t *items = realloc(list->data, new_capacity * sizeof(*items));
    if (!items) {
        return -1;
    }
    list->data = items;
    list->capacity = new_capacity;
    return 0;
}

static int ensure_bit_capacity(struct lantern_bitlist *list, size_t required_bytes) {
    if (!list) {
        return -1;
    }
    if (list->capacity >= required_bytes) {
        return 0;
    }
    size_t new_capacity = list->capacity == 0 ? 4 : list->capacity;
    while (new_capacity < required_bytes) {
        if (new_capacity > (SIZE_MAX / 2)) {
            return -1;
        }
        new_capacity *= 2;
    }
    uint8_t *bytes = realloc(list->bytes, new_capacity * sizeof(*bytes));
    if (!bytes) {
        return -1;
    }
    list->bytes = bytes;
    list->capacity = new_capacity;
    return 0;
}

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
    if (ensure_capacity(list, list->length + 1) != 0) {
        return -1;
    }
    list->data[list->length++] = *vote;
    return 0;
}

int lantern_attestations_copy(LanternAttestations *dst, const LanternAttestations *src) {
    if (!dst || !src) {
        return -1;
    }
    if (src->length == 0) {
        lantern_attestations_reset(dst);
        lantern_attestations_init(dst);
        return 0;
    }
    if (ensure_capacity(dst, src->length) != 0) {
        return -1;
    }
    memcpy(dst->data, src->data, src->length * sizeof(*src->data));
    dst->length = src->length;
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
    if (ensure_capacity(list, new_length) != 0) {
        return -1;
    }
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
    if (ensure_bit_capacity(list, required_bytes) != 0) {
        return -1;
    }
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
    if (ensure_byte_capacity(list, new_length) != 0) {
        return -1;
    }
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
    if (ensure_byte_capacity(dst, src->length) != 0) {
        return -1;
    }
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
    if (ensure_aggregated_att_capacity(list, list->length + 1) != 0) {
        return -1;
    }
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
    if (ensure_aggregated_att_capacity(dst, src->length) != 0) {
        return -1;
    }
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
    if (ensure_aggregated_att_capacity(list, new_length) != 0) {
        return -1;
    }
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

int lantern_wrap_attestations_as_aggregated(
    const LanternAttestations *attestations,
    LanternAggregatedAttestations *out_aggregated) {
    if (!attestations || !out_aggregated) {
        return -1;
    }
    if (lantern_aggregated_attestations_resize(out_aggregated, 0) != 0) {
        return -1;
    }
    if (attestations->length == 0) {
        return 0;
    }
    if (!attestations->data) {
        return -1;
    }
    for (size_t i = 0; i < attestations->length; ++i) {
        const LanternVote *vote = &attestations->data[i];
        if (vote->validator_id >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
            return -1;
        }
        LanternAggregatedAttestation att;
        lantern_aggregated_attestation_init(&att);
        att.data.slot = vote->slot;
        att.data.head = vote->head;
        att.data.target = vote->target;
        att.data.source = vote->source;
        size_t bit_length = (size_t)vote->validator_id + 1u;
        if (lantern_bitlist_resize(&att.aggregation_bits, bit_length) != 0) {
            lantern_aggregated_attestation_reset(&att);
            return -1;
        }
        if (lantern_bitlist_set(&att.aggregation_bits, (size_t)vote->validator_id, true) != 0) {
            lantern_aggregated_attestation_reset(&att);
            return -1;
        }
        if (lantern_aggregated_attestations_append(out_aggregated, &att) != 0) {
            lantern_aggregated_attestation_reset(&att);
            return -1;
        }
        lantern_aggregated_attestation_reset(&att);
    }
    return 0;
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
    if (ensure_attestation_signature_capacity(list, list->length + 1) != 0) {
        return -1;
    }
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

int lantern_attestation_signatures_copy(
    LanternAttestationSignatures *dst,
    const LanternAttestationSignatures *src) {
    if (!dst || !src) {
        return -1;
    }
    if (src->length == 0) {
        lantern_attestation_signatures_reset(dst);
        lantern_attestation_signatures_init(dst);
        return 0;
    }
    if (ensure_attestation_signature_capacity(dst, src->length) != 0) {
        return -1;
    }
    for (size_t i = dst->length; i < src->length; ++i) {
        lantern_aggregated_signature_proof_init(&dst->data[i]);
    }
    for (size_t i = 0; i < src->length; ++i) {
        if (lantern_aggregated_signature_proof_copy(&dst->data[i], &src->data[i]) != 0) {
            return -1;
        }
    }
    dst->length = src->length;
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
    if (ensure_attestation_signature_capacity(list, new_length) != 0) {
        return -1;
    }
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
    if (ensure_signature_list_capacity(list, list->length + 1) != 0) {
        return -1;
    }
    list->data[list->length++] = *signature;
    return 0;
}

int lantern_signature_list_copy(LanternSignatureList *dst, const LanternSignatureList *src) {
    if (!dst || !src) {
        return -1;
    }
    if (src->length == 0) {
        lantern_signature_list_reset(dst);
        lantern_signature_list_init(dst);
        return 0;
    }
    if (ensure_signature_list_capacity(dst, src->length) != 0) {
        return -1;
    }
    memcpy(dst->data, src->data, src->length * sizeof(*src->data));
    dst->length = src->length;
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
    if (ensure_signature_list_capacity(list, new_length) != 0) {
        return -1;
    }
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

void lantern_block_signatures_init(LanternBlockSignatures *signatures) {
    if (!signatures) {
        return;
    }
    lantern_attestation_signatures_init(&signatures->attestation_signatures);
    memset(&signatures->proposer_signature, 0, sizeof(signatures->proposer_signature));
}

void lantern_block_signatures_reset(LanternBlockSignatures *signatures) {
    if (!signatures) {
        return;
    }
    lantern_attestation_signatures_reset(&signatures->attestation_signatures);
    memset(&signatures->proposer_signature, 0, sizeof(signatures->proposer_signature));
}

int lantern_block_signatures_copy(LanternBlockSignatures *dst, const LanternBlockSignatures *src) {
    if (!dst || !src) {
        return -1;
    }
    if (lantern_attestation_signatures_copy(&dst->attestation_signatures, &src->attestation_signatures) != 0) {
        return -1;
    }
    dst->proposer_signature = src->proposer_signature;
    return 0;
}

void lantern_block_body_init(LanternBlockBody *body) {
    if (!body) {
        return;
    }
    lantern_aggregated_attestations_init(&body->attestations);
    body->legacy_plain_attestation_layout = false;
}

void lantern_block_body_reset(LanternBlockBody *body) {
    if (!body) {
        return;
    }
    lantern_aggregated_attestations_reset(&body->attestations);
    body->legacy_plain_attestation_layout = false;
}

void lantern_block_with_attestation_init(LanternBlockWithAttestation *block) {
    if (!block) {
        return;
    }
    memset(block, 0, sizeof(*block));
    lantern_block_body_init(&block->block.body);
}

void lantern_block_with_attestation_reset(LanternBlockWithAttestation *block) {
    if (!block) {
        return;
    }
    lantern_block_body_reset(&block->block.body);
    memset(block, 0, sizeof(*block));
}

void lantern_signed_block_with_attestation_init(LanternSignedBlockWithAttestation *block) {
    if (!block) {
        return;
    }
    lantern_block_with_attestation_init(&block->message);
    lantern_block_signatures_init(&block->signatures);
}

void lantern_signed_block_with_attestation_reset(LanternSignedBlockWithAttestation *block) {
    if (!block) {
        return;
    }
    lantern_block_with_attestation_reset(&block->message);
    lantern_block_signatures_reset(&block->signatures);
}
