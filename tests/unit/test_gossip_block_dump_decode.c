#include <errno.h>
#include <glob.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/containers.h"
#include "lantern/consensus/ssz.h"
#include "lantern/encoding/snappy.h"
#include "lantern/networking/gossip_payloads.h"

static const char *k_default_glob =
    LANTERN_PROJECT_SOURCE_DIR "/internal-docs/pending-issues/devnet-3-issue-3/*.ssz";

static int read_file(const char *path, uint8_t **out_data, size_t *out_len) {
    if (!path || !out_data || !out_len) {
        return -1;
    }

    *out_data = NULL;
    *out_len = 0;

    FILE *fp = fopen(path, "rb");
    if (!fp) {
        fprintf(stderr, "failed to open %s: %s\n", path, strerror(errno));
        return -1;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return -1;
    }
    long size = ftell(fp);
    if (size < 0) {
        fclose(fp);
        return -1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return -1;
    }

    uint8_t *data = NULL;
    if (size > 0) {
        data = (uint8_t *)malloc((size_t)size);
        if (!data) {
            fclose(fp);
            return -1;
        }
        size_t read_len = fread(data, 1u, (size_t)size, fp);
        if (read_len != (size_t)size) {
            free(data);
            fclose(fp);
            return -1;
        }
    }
    fclose(fp);

    *out_data = data;
    *out_len = (size_t)size;
    return 0;
}

static int read_le_u32(const uint8_t *data, size_t data_len, uint32_t *out_value) {
    if (!data || !out_value || data_len < 4u) {
        return -1;
    }
    *out_value = ((uint32_t)data[0])
        | ((uint32_t)data[1] << 8u)
        | ((uint32_t)data[2] << 16u)
        | ((uint32_t)data[3] << 24u);
    return 0;
}

static int read_le_u64(const uint8_t *data, size_t data_len, uint64_t *out_value) {
    if (!data || !out_value || data_len < 8u) {
        return -1;
    }
    *out_value = ((uint64_t)data[0])
        | ((uint64_t)data[1] << 8u)
        | ((uint64_t)data[2] << 16u)
        | ((uint64_t)data[3] << 24u)
        | ((uint64_t)data[4] << 32u)
        | ((uint64_t)data[5] << 40u)
        | ((uint64_t)data[6] << 48u)
        | ((uint64_t)data[7] << 56u);
    return 0;
}

static size_t bitlist_encoded_size_bits(size_t bit_length) {
    if (bit_length == 0) {
        return 1u;
    }
    size_t byte_len = (bit_length + 7u) / 8u;
    if ((bit_length % 8u) == 0u) {
        return byte_len + 1u;
    }
    return byte_len;
}

static size_t signed_block_max_ssz_size(void) {
    const size_t block_fixed = (sizeof(uint64_t) * 2u) + (LANTERN_ROOT_SIZE * 2u) + sizeof(uint32_t);
    const size_t body_header = sizeof(uint32_t);
    const size_t message_base = sizeof(uint32_t) + LANTERN_VOTE_SSZ_SIZE + block_fixed + body_header;
    const size_t offsets = sizeof(uint32_t) * 2u;
    size_t total = offsets + message_base;

    size_t att_bits_max = bitlist_encoded_size_bits(LANTERN_VALIDATOR_REGISTRY_LIMIT);
    size_t att_entry_max = sizeof(uint32_t) + LANTERN_ATTESTATION_DATA_SSZ_SIZE + att_bits_max;
    size_t attestations_max = (size_t)LANTERN_MAX_ATTESTATIONS * (sizeof(uint32_t) + att_entry_max);
    if (attestations_max > SIZE_MAX - total) {
        return SIZE_MAX;
    }
    total += attestations_max;

    size_t proof_entry_max = (sizeof(uint32_t) * 2u) + att_bits_max + LANTERN_AGG_PROOF_MAX_BYTES;
    size_t signatures_max = (sizeof(uint32_t) * 2u) + LANTERN_SIGNATURE_SIZE
        + ((size_t)LANTERN_MAX_BLOCK_SIGNATURES * (sizeof(uint32_t) + proof_entry_max));
    if (signatures_max > SIZE_MAX - total) {
        return SIZE_MAX;
    }
    return total + signatures_max;
}

static void print_first_offsets(const uint8_t *data, size_t data_len, size_t max_offsets) {
    if (!data || data_len < 4u || max_offsets == 0u) {
        return;
    }

    uint32_t first_offset = 0;
    if (read_le_u32(data, data_len, &first_offset) != 0) {
        return;
    }
    if (first_offset < 4u || first_offset > data_len || (first_offset % 4u) != 0u) {
        return;
    }

    size_t count = (size_t)first_offset / 4u;
    if (count == 0u) {
        return;
    }
    if (count > max_offsets) {
        count = max_offsets;
    }

    printf("      offsets:");
    for (size_t i = 0; i < count; ++i) {
        uint32_t value = 0;
        if (read_le_u32(data + (i * 4u), data_len - (i * 4u), &value) != 0) {
            break;
        }
        printf(" %u", value);
    }
    printf("\n");
}

static void inspect_attestation_region(const uint8_t *data, size_t data_len) {
    printf("    body.attestations_region_len=%zu\n", data_len);
    if (data_len == 0u) {
        printf("      body.attestations_region is empty\n");
        return;
    }
    if ((data_len % LANTERN_VOTE_SSZ_SIZE) == 0u) {
        printf(
            "      legacy_plain_vote_layout is possible: %zu votes of %zu bytes\n",
            data_len / LANTERN_VOTE_SSZ_SIZE,
            (size_t)LANTERN_VOTE_SSZ_SIZE);
    } else {
        printf(
            "      legacy_plain_vote_layout impossible: len %% %zu = %zu\n",
            (size_t)LANTERN_VOTE_SSZ_SIZE,
            data_len % LANTERN_VOTE_SSZ_SIZE);
    }

    if (data_len >= 4u) {
        uint32_t first_offset = 0;
        if (read_le_u32(data, data_len, &first_offset) == 0) {
            printf("      first_list_offset=%u\n", first_offset);
            if (first_offset >= 4u && first_offset <= data_len && (first_offset % 4u) == 0u) {
                printf("      aggregated_list_count_candidate=%zu\n", (size_t)first_offset / 4u);
                print_first_offsets(data, data_len, 6u);
            }
        }
    }
}

static void inspect_signature_region(const uint8_t *data, size_t data_len) {
    printf("    signatures_region_len=%zu\n", data_len);
    if (!data || data_len == 0u) {
        printf("      signatures region empty\n");
        return;
    }

    uint32_t first_u32 = 0;
    if (read_le_u32(data, data_len, &first_u32) != 0) {
        printf("      could not read signature region header\n");
        return;
    }
    printf("      first_u32=%u\n", first_u32);

    size_t standard_fixed = sizeof(uint32_t) + LANTERN_SIGNATURE_SIZE;
    if ((size_t)first_u32 == standard_fixed) {
        printf("      signature layout matches Lantern standard block-signatures envelope\n");
        if (data_len > standard_fixed) {
            print_first_offsets(data + standard_fixed, data_len - standard_fixed, 6u);
        }
        return;
    }

    if (first_u32 >= 4u && first_u32 <= data_len && (first_u32 % 4u) == 0u) {
        printf(
            "      signature layout looks like attestation-signatures-only list with %zu entries\n",
            (size_t)first_u32 / 4u);
        print_first_offsets(data, data_len, 6u);
        return;
    }

    printf("      signature layout does not match standard or attestation-only fallback\n");
}

static const char *check_attestation_data_sanity(const LanternAttestationData *data) {
    if (!data) {
        return "missing_attestation_data";
    }
    if (data->target.slot < data->source.slot) {
        return "target_before_source";
    }
    if (data->slot < data->target.slot) {
        return "attestation_slot_before_target";
    }
    return NULL;
}

static const char *check_block_sanity(const LanternSignedBlock *block) {
    if (!block) {
        return "missing_block";
    }

    const LanternBlock *message = &block->message.block;
    for (size_t i = 0; i < message->body.attestations.length; ++i) {
        const LanternAggregatedAttestation *att = &message->body.attestations.data[i];
        const char *att_reason = check_attestation_data_sanity(&att->data);
        if (att_reason) {
            return att_reason;
        }
    }

    const char *proposer_reason = check_attestation_data_sanity(&block->message.proposer_attestation.data);
    if (proposer_reason) {
        return proposer_reason;
    }
    if (block->message.proposer_attestation.slot < message->slot) {
        return "proposer_vote_slot_before_block_slot";
    }

    size_t sig_count = block->signatures.attestation_signatures.length;
    size_t att_count = message->body.attestations.length;
    if (sig_count > LANTERN_MAX_BLOCK_SIGNATURES) {
        return "too_many_block_signatures";
    }
    if (sig_count > 0u && sig_count != att_count) {
        return "attestation_signature_count_mismatch";
    }
    return NULL;
}

static void print_attestation_slots(const LanternSignedBlock *block) {
    if (!block) {
        return;
    }
    const LanternBlock *message = &block->message.block;
    for (size_t i = 0; i < message->body.attestations.length; ++i) {
        const LanternAggregatedAttestation *att = &message->body.attestations.data[i];
        printf(
            "    attestation[%zu] slot=%" PRIu64 " target=%" PRIu64 " source=%" PRIu64 " bitlen=%zu\n",
            i,
            att->data.slot,
            att->data.target.slot,
            att->data.source.slot,
            att->aggregation_bits.bit_length);
    }
}

static void inspect_message_section(const uint8_t *data, size_t data_len) {
    printf("    message_region_len=%zu\n", data_len);
    if (!data || data_len < 4u + LANTERN_VOTE_SSZ_SIZE) {
        printf("      message region too short for block-with-attestation\n");
        return;
    }

    uint32_t block_offset = 0;
    if (read_le_u32(data, data_len, &block_offset) != 0) {
        printf("      failed to read message.block_offset\n");
        return;
    }
    printf("      message.block_offset=%u\n", block_offset);

    LanternVote proposer_vote;
    memset(&proposer_vote, 0, sizeof(proposer_vote));
    int proposer_rc = lantern_ssz_decode_vote(&proposer_vote, data + 4u, LANTERN_VOTE_SSZ_SIZE);
    printf(
        "      proposer_vote_decode=%s validator=%" PRIu64 " slot=%" PRIu64 " target=%" PRIu64 " source=%" PRIu64 "\n",
        proposer_rc == 0 ? "ok" : "fail",
        (uint64_t)proposer_vote.validator_id,
        proposer_vote.slot,
        proposer_vote.target.slot,
        proposer_vote.source.slot);

    size_t min_size = 4u + LANTERN_VOTE_SSZ_SIZE;
    if (block_offset < min_size || block_offset > data_len) {
        printf(
            "      message.block_offset invalid: expected [%zu, %zu], got %u\n",
            min_size,
            data_len,
            block_offset);
        return;
    }

    const uint8_t *block_data = data + block_offset;
    size_t block_len = data_len - block_offset;
    printf("      block_region_len=%zu\n", block_len);
    if (block_len < 84u) {
        printf("      block region too short for Lantern block fixed section\n");
        return;
    }

    uint64_t slot = 0;
    uint64_t proposer_index = 0;
    uint32_t body_offset = 0;
    read_le_u64(block_data, block_len, &slot);
    read_le_u64(block_data + 8u, block_len - 8u, &proposer_index);
    read_le_u32(block_data + 80u, block_len - 80u, &body_offset);
    printf(
        "      block.slot=%" PRIu64 " proposer=%" PRIu64 " body_offset=%u\n",
        slot,
        proposer_index,
        body_offset);

    LanternBlock parsed_block;
    memset(&parsed_block, 0, sizeof(parsed_block));
    int block_rc = lantern_ssz_decode_block(&parsed_block, block_data, block_len);
    printf("      block_decode=%s\n", block_rc == 0 ? "ok" : "fail");
    if (block_rc == 0) {
        printf(
            "      body.attestations=%zu layout=%s\n",
            parsed_block.body.attestations.length,
            parsed_block.body.legacy_plain_attestation_layout ? "legacy_plain_votes" : "aggregated");
        lantern_block_body_reset(&parsed_block.body);
        return;
    }

    if (body_offset < 84u || body_offset > block_len) {
        printf(
            "      block.body_offset invalid: expected [%u, %zu], got %u\n",
            84u,
            block_len,
            body_offset);
        return;
    }

    const uint8_t *body_data = block_data + body_offset;
    size_t body_len = block_len - body_offset;
    printf("      block_body_region_len=%zu\n", body_len);

    LanternBlockBody body;
    memset(&body, 0, sizeof(body));
    int body_rc = lantern_ssz_decode_block_body(&body, body_data, body_len);
    printf("      block_body_decode=%s\n", body_rc == 0 ? "ok" : "fail");
    if (body_rc == 0) {
        printf(
            "      body.attestations=%zu layout=%s\n",
            body.attestations.length,
            body.legacy_plain_attestation_layout ? "legacy_plain_votes" : "aggregated");
        lantern_block_body_reset(&body);
        return;
    }

    if (body_len < 4u) {
        printf("      block body too short for attestation offset\n");
        return;
    }

    uint32_t att_offset = 0;
    read_le_u32(body_data, body_len, &att_offset);
    printf("      block_body.att_offset=%u\n", att_offset);
    if (att_offset < 4u || att_offset > body_len) {
        printf(
            "      block_body.att_offset invalid: expected [%u, %zu], got %u\n",
            4u,
            body_len,
            att_offset);
        return;
    }

    inspect_attestation_region(body_data + att_offset, body_len - att_offset);
}

static void analyze_payload(const char *path) {
    uint8_t *compressed = NULL;
    size_t compressed_len = 0;
    if (read_file(path, &compressed, &compressed_len) != 0) {
        fprintf(stderr, "failed to read %s\n", path);
        return;
    }

    printf("FILE %s\n", path);
    printf("  compressed_len=%zu\n", compressed_len);

    bool framed = lantern_snappy_is_framed(compressed, compressed_len);
    printf("  snappy_is_framed=%s\n", framed ? "true" : "false");

    size_t raw_len_raw = 0;
    int raw_len_rc = lantern_snappy_uncompressed_length_raw(compressed, compressed_len, &raw_len_raw);
    printf("  snappy_raw_length_rc=%d", raw_len_rc);
    if (raw_len_rc == LANTERN_SNAPPY_OK) {
        printf(" raw_len=%zu", raw_len_raw);
    }
    printf("\n");

    size_t raw_len_any = 0;
    int any_len_rc = lantern_snappy_uncompressed_length(compressed, compressed_len, &raw_len_any);
    printf("  snappy_auto_length_rc=%d", any_len_rc);
    if (any_len_rc == LANTERN_SNAPPY_OK) {
        printf(" raw_len=%zu", raw_len_any);
    }
    printf("\n");

    if (raw_len_rc != LANTERN_SNAPPY_OK) {
        LanternSignedBlock block;
        lantern_signed_block_with_attestation_init(&block);
        int pipeline_rc = lantern_gossip_decode_signed_block_snappy(&block, compressed, compressed_len, NULL, NULL);
        printf("  gossip_pipeline_rc=%d\n", pipeline_rc);
        lantern_signed_block_with_attestation_reset(&block);
        printf("\n");
        free(compressed);
        return;
    }

    size_t max_ssz = signed_block_max_ssz_size();
    printf("  signed_block_max_ssz_size=%zu\n", max_ssz);
    if (raw_len_raw == 0u || raw_len_raw > max_ssz) {
        printf("  raw_len out of Lantern gossip bounds\n\n");
        free(compressed);
        return;
    }

    uint8_t *raw = (uint8_t *)malloc(raw_len_raw);
    if (!raw) {
        fprintf(stderr, "failed to allocate %zu bytes for %s\n", raw_len_raw, path);
        free(compressed);
        return;
    }

    size_t raw_written = raw_len_raw;
    int decompress_rc = lantern_snappy_decompress_raw(
        compressed, compressed_len, raw, raw_len_raw, &raw_written);
    printf("  snappy_raw_decompress_rc=%d written=%zu\n", decompress_rc, raw_written);
    if (decompress_rc != LANTERN_SNAPPY_OK) {
        free(raw);
        free(compressed);
        printf("\n");
        return;
    }

    if (raw_written >= 8u) {
        uint32_t message_offset = 0;
        uint32_t signatures_offset = 0;
        read_le_u32(raw, raw_written, &message_offset);
        read_le_u32(raw + 4u, raw_written - 4u, &signatures_offset);
        printf(
            "  signed_block_offsets message=%u signatures=%u payload=%zu\n",
            message_offset,
            signatures_offset,
            raw_written);

        if (message_offset >= 8u && signatures_offset >= message_offset && signatures_offset <= raw_written) {
            inspect_message_section(raw + message_offset, signatures_offset - message_offset);
            inspect_signature_region(raw + signatures_offset, raw_written - signatures_offset);
        } else {
            printf("    signed block outer offsets are invalid for Lantern schema\n");
        }
    }

    LanternSignedBlock block;
    lantern_signed_block_with_attestation_init(&block);
    int ssz_rc = lantern_ssz_decode_signed_block(&block, raw, raw_written);
    printf("  lantern_ssz_decode_signed_block_rc=%d\n", ssz_rc);
    if (ssz_rc == 0) {
        printf(
            "  decoded_block slot=%" PRIu64 " proposer=%" PRIu64 " attestations=%zu sigs=%zu layout=%s proposer_vote_slot=%" PRIu64 "\n",
            block.message.block.slot,
            block.message.block.proposer_index,
            block.message.block.body.attestations.length,
            block.signatures.attestation_signatures.length,
            block.message.block.body.legacy_plain_attestation_layout ? "legacy_plain_votes" : "aggregated",
            block.message.proposer_attestation.slot);
        print_attestation_slots(&block);
        const char *sanity_reason = check_block_sanity(&block);
        printf(
            "  basic_block_sanity=%s",
            sanity_reason ? "fail" : "ok");
        if (sanity_reason) {
            printf(" reason=%s", sanity_reason);
        }
        printf("\n");
    }

    LanternSignedBlock pipeline_block;
    lantern_signed_block_with_attestation_init(&pipeline_block);
    int pipeline_rc = lantern_gossip_decode_signed_block_snappy(
        &pipeline_block, compressed, compressed_len, NULL, NULL);
    printf("  lantern_gossip_decode_signed_block_snappy_rc=%d\n", pipeline_rc);

    lantern_signed_block_with_attestation_reset(&pipeline_block);
    lantern_signed_block_with_attestation_reset(&block);
    free(raw);
    free(compressed);
    printf("\n");
}

int main(int argc, char **argv) {
    if (argc > 1) {
        for (int i = 1; i < argc; ++i) {
            analyze_payload(argv[i]);
        }
        return 0;
    }

    glob_t matches;
    memset(&matches, 0, sizeof(matches));
    int glob_rc = glob(k_default_glob, 0, NULL, &matches);
    if (glob_rc != 0 || matches.gl_pathc == 0u) {
        fprintf(
            stderr,
            "no payloads matched default glob: %s (glob_rc=%d)\n",
            k_default_glob,
            glob_rc);
        globfree(&matches);
        return 1;
    }

    for (size_t i = 0; i < matches.gl_pathc; ++i) {
        analyze_payload(matches.gl_pathv[i]);
    }
    globfree(&matches);
    return 0;
}
