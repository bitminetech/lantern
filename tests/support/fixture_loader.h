#ifndef LANTERN_TESTS_FIXTURE_LOADER_H
#define LANTERN_TESTS_FIXTURE_LOADER_H

#include <stddef.h>
#include <stdint.h>

#define JSMN_HEADER
#include "jsmn.h"
#undef JSMN_HEADER
#include "lantern/consensus/containers.h"
#include "lantern/consensus/state.h"

struct lantern_fixture_document {
    char *text;
    size_t length;
    jsmntok_t *tokens;
    int token_count;
};

int lantern_fixture_read_text_file(const char *path, char **out_buf);

int lantern_fixture_document_init(struct lantern_fixture_document *doc, char *text);
void lantern_fixture_document_reset(struct lantern_fixture_document *doc);

const jsmntok_t *lantern_fixture_token(const struct lantern_fixture_document *doc, int index);
int lantern_fixture_object_get_field(
    const struct lantern_fixture_document *doc,
    int object_index,
    const char *name);
int lantern_fixture_object_get_value_at(
    const struct lantern_fixture_document *doc,
    int object_index,
    int value_index);
int lantern_fixture_array_get_length(const struct lantern_fixture_document *doc, int array_index);
int lantern_fixture_array_get_element(
    const struct lantern_fixture_document *doc,
    int array_index,
    int position);

int lantern_fixture_token_to_uint64(
    const struct lantern_fixture_document *doc,
    int index,
    uint64_t *out_value);
int lantern_fixture_token_to_root(
    const struct lantern_fixture_document *doc,
    int index,
    LanternRoot *root);
const char *lantern_fixture_token_string(
    const struct lantern_fixture_document *doc,
    int index,
    size_t *out_length);

int lantern_fixture_parse_anchor_state(
    const struct lantern_fixture_document *doc,
    int anchor_state_index,
    LanternState *state,
    LanternCheckpoint *latest_justified,
    LanternCheckpoint *latest_finalized,
    uint64_t *genesis_time,
    uint64_t *validator_count);

int lantern_fixture_parse_attestation_data(
    const struct lantern_fixture_document *doc,
    int data_obj_idx,
    LanternAttestationData *out_data);

int lantern_fixture_parse_block(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternBlock *block);

int lantern_fixture_parse_attestation_message(
    const struct lantern_fixture_document *doc,
    int attestation_idx,
    LanternSignedVote *vote);

int lantern_fixture_parse_aggregated_attestation(
    const struct lantern_fixture_document *doc,
    int entry_idx,
    LanternAggregatedAttestation *out_attestation);

int lantern_fixture_parse_signature_proof(
    const struct lantern_fixture_document *doc,
    int proof_idx,
    LanternAggregatedSignatureProof *out_proof);

int lantern_fixture_parse_signed_block(
    const struct lantern_fixture_document *doc,
    int object_index,
    LanternSignedBlock *signed_block);

#endif /* LANTERN_TESTS_FIXTURE_LOADER_H */
