/**
 * @file client_sync_blocks.c
 * @brief Block import and signature verification
 *
 * @spec subspecs/containers/block/block.py in tools/leanSpec
 * @spec subspecs/containers/state/state.py - state_transition() in tools/leanSpec
 * @spec subspecs/forkchoice/store.py - on_block() in tools/leanSpec
 *
 * Implements block signature verification, import into fork choice,
 * state transitions, and block recording.
 *
 * Related files:
 * - client_sync.c: Main sync logic and gossip handlers
 * - client_sync_votes.c: Vote processing
 *
 * @note Thread safety: Functions that access shared state acquire appropriate
 *       locks as documented. See client_internal.h for lock ordering.
 */

#include "client_internal.h"

#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/signature.h"
#include "lantern/consensus/ssz.h"
#include "lantern/consensus/state.h"
#include "lantern/storage/storage.h"
#include "lantern/support/log.h"
#include "lantern/support/strings.h"


/* ============================================================================
 * Constants
 * ============================================================================ */

enum
{
    ROOT_HEX_BUFFER_LEN = (LANTERN_ROOT_SIZE * 2u) + 3u,
};

/* ============================================================================
 * Sync Progress Helpers
 * ============================================================================ */

static void update_sync_progress_after_block(struct lantern_client *client)
{
    if (!client)
    {
        return;
    }

    uint64_t local_slot = 0;
    bool state_locked = lantern_client_lock_state(client);
    if (state_locked)
    {
        local_slot = client->state.latest_block_header.slot;
        if (client->has_fork_choice)
        {
            LanternRoot fork_head = {0};
            if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0)
            {
                uint64_t fork_slot = 0;
                if (lantern_fork_choice_block_info(
                        &client->fork_choice,
                        &fork_head,
                        &fork_slot,
                        NULL,
                        NULL)
                    == 0)
                {
                    local_slot = fork_slot;
                }
            }
        }
    }
    else if (client->has_state)
    {
        local_slot = client->state.latest_block_header.slot;
        if (client->has_fork_choice)
        {
            LanternRoot fork_head = {0};
            if (lantern_fork_choice_current_head(&client->fork_choice, &fork_head) == 0)
            {
                uint64_t fork_slot = 0;
                if (lantern_fork_choice_block_info(
                        &client->fork_choice,
                        &fork_head,
                        &fork_slot,
                        NULL,
                        NULL)
                    == 0)
                {
                    local_slot = fork_slot;
                }
            }
        }
    }
    lantern_client_unlock_state(client, state_locked);

    lantern_client_update_sync_progress(client, local_slot);
}


/* ============================================================================
 * External Functions (from client_sync_votes.c)
 * ============================================================================ */

extern bool lantern_client_verify_vote_signature(
    const struct lantern_client *client,
    const LanternSignedVote *vote,
    const LanternSignature *signature,
    const LanternState *state_override,
    const struct lantern_log_metadata *meta,
    const char *context);


/* ============================================================================
 * Block Signature Verification
 * ============================================================================ */

/**
 * Verify all signatures in a signed block.
 *
 * @spec subspecs/containers/block/block.py - SignedBlock structure
 * @spec subspecs/xmss/signature.py - XMSS signature verification
 *
 * Verifies all signatures in a signed block:
 * 1. Proposer signature (last in the signatures array)
 * 2. All attestation signatures (one per attestation in body)
 *
 * The signatures array must contain exactly N+1 signatures where N
 * is the number of attestations in the block body.
 *
 * @param client  Client instance
 * @param block   Signed block to verify
 * @param meta    Logging metadata
 * @return true if all signatures are valid
 *
 * @note Thread safety: Thread-safe, reads immutable validator registry
 */
static bool signed_block_signatures_are_valid(
    const struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block)
    {
        return false;
    }
    LanternState parent_state;
    lantern_state_init(&parent_state);
    const LanternState *state_for_sig = NULL;
    const LanternRoot parent_root = block->message.block.parent_root;

    if (lantern_root_is_zero(&parent_root))
    {
        if (client->has_state)
        {
            state_for_sig = &client->state;
        }
    }
    else
    {
        state_for_sig = lantern_client_state_for_root_locked(
            (struct lantern_client *)client,
            &parent_root,
            &parent_state,
            NULL);
    }
    if (!state_for_sig)
    {
        char parent_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
        lantern_log_warn(
            "state",
            meta,
            "missing parent state for signature verification parent_root=%s",
            parent_hex[0] ? parent_hex : "0x0");
        lantern_state_reset(&parent_state);
        return false;
    }

    const LanternAggregatedAttestations *attestations = &block->message.block.body.attestations;
    const LanternAttestationSignatures *sig_groups = &block->signatures.attestation_signatures;
    size_t att_count = attestations->length;
    bool missing_attestation_signature_payload =
        (att_count > 0) && (sig_groups->length == 0);

    if (!client->genesis.validator_registry.records)
    {
        lantern_state_reset(&parent_state);
        return true;
    }
    if (att_count > 0 && !attestations->data)
    {
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " attestations missing data length=%zu",
            block->message.block.slot,
            att_count);
        lantern_state_reset(&parent_state);
        return false;
    }
    if (att_count != sig_groups->length)
    {
        if (!missing_attestation_signature_payload)
        {
            lantern_log_warn(
                "state",
                meta,
                "signed block slot=%" PRIu64 " aggregated signature count mismatch expected=%zu actual=%zu",
                block->message.block.slot,
                att_count,
                sig_groups->length);
            lantern_state_reset(&parent_state);
            return false;
        }
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " missing attestation signatures payload; accepting legacy compatibility path attestation_count=%zu",
            block->message.block.slot,
            att_count);
    }
    if (att_count > 0 && !sig_groups->data)
    {
        if (!missing_attestation_signature_payload)
        {
            lantern_log_warn(
                "state",
                meta,
                "signed block slot=%" PRIu64 " missing aggregated signatures length=%zu",
                block->message.block.slot,
                sig_groups->length);
            lantern_state_reset(&parent_state);
            return false;
        }
    }

    size_t validator_count = lantern_state_validator_count(state_for_sig);
    const uint8_t **pubkeys = NULL;

    for (size_t i = 0; i < att_count && !missing_attestation_signature_payload; ++i)
    {
        const LanternAggregatedAttestation *att = &attestations->data[i];
        const LanternAggregatedSignatureProof *proof = &sig_groups->data[i];
        size_t bit_length = att->aggregation_bits.bit_length;
        if (bit_length == 0 || att->aggregation_bits.bytes == NULL)
        {
            return false;
        }
        if (proof->participants.bit_length != att->aggregation_bits.bit_length)
        {
            lantern_state_reset(&parent_state);
            return false;
        }
        size_t bytes = (bit_length + 7u) / 8u;
        if (bytes > 0)
        {
            if (!proof->participants.bytes
                || memcmp(proof->participants.bytes, att->aggregation_bits.bytes, bytes) != 0)
            {
                lantern_state_reset(&parent_state);
                return false;
            }
        }
        size_t participant_count = 0;
        for (size_t v = 0; v < bit_length; ++v)
        {
            if (lantern_bitlist_get(&att->aggregation_bits, v))
            {
                participant_count += 1u;
            }
        }
        if (participant_count == 0)
        {
            lantern_state_reset(&parent_state);
            return false;
        }
        pubkeys = calloc(participant_count, sizeof(*pubkeys));
        if (!pubkeys)
        {
            lantern_state_reset(&parent_state);
            return false;
        }
        size_t idx = 0;
        for (size_t v = 0; v < bit_length; ++v)
        {
            if (!lantern_bitlist_get(&att->aggregation_bits, v))
            {
                continue;
            }
            if (v >= validator_count)
            {
                free(pubkeys);
                lantern_state_reset(&parent_state);
                return false;
            }
            const uint8_t *pubkey = lantern_state_validator_pubkey(state_for_sig, v);
            if (!pubkey || lantern_validator_pubkey_is_zero(pubkey))
            {
                free(pubkeys);
                lantern_state_reset(&parent_state);
                return false;
            }
            pubkeys[idx++] = pubkey;
        }

        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&att->data, &data_root) != 0)
        {
            free(pubkeys);
            lantern_state_reset(&parent_state);
            return false;
        }
        bool sig_ok = lantern_signature_verify_aggregated(
            pubkeys,
            participant_count,
            data_root.bytes,
            sizeof(data_root.bytes),
            &proof->proof_data,
            att->data.slot);
        free(pubkeys);
        pubkeys = NULL;
        if (!sig_ok)
        {
            lantern_state_reset(&parent_state);
            return false;
        }
    }

    bool proposer_signature_present = !lantern_signature_is_zero(&block->signatures.proposer_signature);
    if (!proposer_signature_present)
    {
        if (!missing_attestation_signature_payload)
        {
            lantern_log_warn(
                "state",
                meta,
                "signed block slot=%" PRIu64 " missing proposer signature",
                block->message.block.slot);
            lantern_state_reset(&parent_state);
            return false;
        }
        lantern_log_warn(
            "state",
            meta,
            "signed block slot=%" PRIu64 " missing proposer signature; accepting legacy compatibility path",
            block->message.block.slot);
        lantern_state_reset(&parent_state);
        return true;
    }

    LanternSignedVote proposer_signed = {0};
    proposer_signed.data = block->message.proposer_attestation;
    proposer_signed.signature = block->signatures.proposer_signature;
    bool proposer_ok = lantern_client_verify_vote_signature(
        client,
        &proposer_signed,
        &proposer_signed.signature,
        state_for_sig,
        meta,
        "proposer");
    lantern_state_reset(&parent_state);
    return proposer_ok;
}

static void cache_block_aggregated_proofs_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block)
{
    if (!client || !block) {
        return;
    }
    const LanternAggregatedAttestations *attestations = &block->message.block.body.attestations;
    const LanternAttestationSignatures *proofs = &block->signatures.attestation_signatures;
    if (!attestations->data || !proofs->data) {
        return;
    }
    size_t count = attestations->length;
    if (proofs->length < count) {
        count = proofs->length;
    }
    if (count == 0) {
        return;
    }
    for (size_t i = 0; i < count; ++i) {
        LanternRoot data_root;
        if (lantern_hash_tree_root_attestation_data(&attestations->data[i].data, &data_root) != 0) {
            continue;
        }
        (void)lantern_client_agg_proof_cache_add(client, &data_root, &proofs->data[i]);
    }
}

static void persist_block_after_import(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !client->data_dir || !block)
    {
        return;
    }

    struct lantern_log_metadata fallback = {.validator = client->node_id};
    const struct lantern_log_metadata *log_meta = meta ? meta : &fallback;
    if (lantern_storage_store_block(client->data_dir, block) != 0)
    {
        lantern_log_warn(
            "storage",
            log_meta,
            "failed to persist block slot=%" PRIu64,
            block->message.block.slot);
    }
}


/* ============================================================================
 * Block Import Helpers
 * ============================================================================ */

/**
 * @brief Computes the block root if not provided.
 *
 * @param block        Signed block to hash
 * @param provided     Optional precomputed root
 * @param out_root     Output root (filled on success)
 * @param block_root   Root of the block
 * @param meta         Logging metadata
 * @return true on success, false on failure
 *
 * @note Thread safety: This function is thread-safe
 */
static bool get_block_root_local(
    const LanternSignedBlock *block,
    const LanternRoot *provided,
    LanternRoot *out_root,
    const struct lantern_log_metadata *meta)
{
    if (!block || !out_root)
    {
        return false;
    }
    if (provided)
    {
        *out_root = *provided;
        return true;
    }
    if (lantern_hash_tree_root_block(&block->message.block, out_root) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to hash block at slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }
    return true;
}


/**
 * @brief Returns true if the block should be processed.
 *
 * @param slot        Block slot
 * @param local_slot  Client state slot
 * @param root_known  Whether the block root is known
 * @param known_slot  Slot of the known root (if root_known)
 * @param meta        Logging metadata
 * @return true if block should be processed, false otherwise
 *
 * @note Thread safety: This function is thread-safe
 */
static bool should_process_block(
    uint64_t slot,
    uint64_t local_slot,
    bool root_known,
    uint64_t known_slot,
    const struct lantern_log_metadata *meta)
{
    if (root_known && slot <= known_slot)
    {
        lantern_log_trace("state", meta, "skipping known block slot=%" PRIu64, slot);
        return false;
    }
    return true;
}

enum block_parent_action
{
    BLOCK_PARENT_ACTION_UNKNOWN = 0,
    BLOCK_PARENT_ACTION_MATCHES_HEAD,
    BLOCK_PARENT_ACTION_KNOWN_OFF_HEAD,
};

struct lantern_root_chain_entry
{
    LanternRoot root;
    LanternRoot parent_root;
    uint64_t slot;
    bool has_parent;
};

struct lantern_root_chain
{
    struct lantern_root_chain_entry *items;
    size_t length;
    size_t capacity;
};

static void root_chain_reset(struct lantern_root_chain *chain)
{
    if (!chain)
    {
        return;
    }
    free(chain->items);
    chain->items = NULL;
    chain->length = 0;
    chain->capacity = 0;
}

static bool root_chain_contains(const struct lantern_root_chain *chain, const LanternRoot *root)
{
    if (!chain || !root)
    {
        return false;
    }
    for (size_t i = 0; i < chain->length; ++i)
    {
        if (memcmp(chain->items[i].root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0)
        {
            return true;
        }
    }
    return false;
}

static bool root_chain_append(
    struct lantern_root_chain *chain,
    const LanternRoot *root,
    const LanternRoot *parent_root,
    uint64_t slot,
    bool has_parent)
{
    if (!chain || !root || !parent_root)
    {
        return false;
    }
    if (chain->length == chain->capacity)
    {
        size_t next_capacity = chain->capacity > 0 ? chain->capacity + (chain->capacity / 2u) : 4u;
        if (next_capacity < chain->capacity)
        {
            return false;
        }
        if (next_capacity > SIZE_MAX / sizeof(*chain->items))
        {
            return false;
        }
        struct lantern_root_chain_entry *expanded = realloc(
            chain->items,
            next_capacity * sizeof(*expanded));
        if (!expanded)
        {
            return false;
        }
        chain->items = expanded;
        chain->capacity = next_capacity;
    }
    struct lantern_root_chain_entry *entry = &chain->items[chain->length];
    entry->root = *root;
    entry->parent_root = *parent_root;
    entry->slot = slot;
    entry->has_parent = has_parent;
    chain->length += 1u;
    return true;
}

static bool build_root_chain_locked(
    struct lantern_client *client,
    const LanternRoot *target_root,
    struct lantern_root_chain *out_chain)
{
    if (!client || !target_root || !out_chain || !client->has_fork_choice)
    {
        return false;
    }
    root_chain_reset(out_chain);

    LanternRoot current = *target_root;
    size_t steps = 0;
    while (!lantern_root_is_zero(&current))
    {
        if (steps > LANTERN_HISTORICAL_ROOTS_LIMIT)
        {
            return false;
        }
        if (root_chain_contains(out_chain, &current))
        {
            return false;
        }

        LanternRoot parent = {0};
        uint64_t slot = 0;
        bool has_parent = false;
        if (lantern_fork_choice_block_info(
                &client->fork_choice,
                &current,
                &slot,
                &parent,
                &has_parent)
            != 0)
        {
            return false;
        }

        if (!root_chain_append(out_chain, &current, &parent, slot, has_parent))
        {
            return false;
        }

        if (!has_parent || lantern_root_is_zero(&parent))
        {
            break;
        }

        current = parent;
        steps += 1u;
    }

    return out_chain->length > 0;
}

static bool resolve_replay_validator_pubkeys(
    const struct lantern_client *client,
    const struct lantern_log_metadata *meta,
    const uint8_t **out_pubkeys,
    size_t *out_validator_count,
    bool *out_allocated_pubkeys)
{
    if (!client || !out_pubkeys || !out_validator_count || !out_allocated_pubkeys)
    {
        return false;
    }

    const struct lantern_chain_config *config = &client->genesis.chain_config;
    size_t validator_count = config->validator_pubkeys_count;
    const uint8_t *pubkeys = config->validator_pubkeys;
    bool allocated_pubkeys = false;

    if (!pubkeys || validator_count == 0)
    {
        size_t registry_count = client->genesis.validator_registry.count;
        if (registry_count > 0 && registry_count == config->validator_count)
        {
            if (registry_count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state registry pubkey size overflow count=%zu",
                    registry_count);
                return false;
            }

            validator_count = registry_count;
            size_t pubkeys_len = validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
            uint8_t *buffer = calloc(pubkeys_len, sizeof(*buffer));
            if (!buffer)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state failed to allocate registry pubkey buffer len=%zu",
                    pubkeys_len);
                return false;
            }
            bool pubkey_ok = true;
            for (size_t i = 0; i < validator_count; ++i)
            {
                const struct lantern_validator_record *rec =
                    &client->genesis.validator_registry.records[i];
                uint8_t *dest = buffer + (i * LANTERN_VALIDATOR_PUBKEY_SIZE);
                if (rec->has_pubkey_bytes)
                {
                    memcpy(dest, rec->pubkey_bytes, LANTERN_VALIDATOR_PUBKEY_SIZE);
                }
                else if (rec->pubkey_hex
                         && lantern_hex_decode(
                             rec->pubkey_hex,
                             dest,
                             LANTERN_VALIDATOR_PUBKEY_SIZE)
                             == 0)
                {
                    /* decoded */
                }
                else
                {
                    pubkey_ok = false;
                    break;
                }
            }
            if (!pubkey_ok)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state failed to populate registry pubkeys");
                free(buffer);
                return false;
            }
            pubkeys = buffer;
            allocated_pubkeys = true;
        }
        else if (client->state.validators && client->state.validator_count > 0)
        {
            size_t state_count = client->state.validator_count;
            if (state_count > SIZE_MAX / LANTERN_VALIDATOR_PUBKEY_SIZE)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state state pubkey size overflow count=%zu",
                    state_count);
                return false;
            }
            validator_count = state_count;
            size_t pubkeys_len = validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
            uint8_t *buffer = calloc(pubkeys_len, sizeof(*buffer));
            if (!buffer)
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "init_replay_state failed to allocate state pubkey buffer len=%zu",
                    pubkeys_len);
                return false;
            }
            for (size_t i = 0; i < validator_count; ++i)
            {
                const LanternValidator *validator = &client->state.validators[i];
                uint8_t *dest = buffer + (i * LANTERN_VALIDATOR_PUBKEY_SIZE);
                memcpy(dest, validator->pubkey, LANTERN_VALIDATOR_PUBKEY_SIZE);
            }
            pubkeys = buffer;
            allocated_pubkeys = true;
        }
        else
        {
            lantern_log_warn(
                "state",
                meta,
                "init_replay_state missing validator pubkeys");
            return false;
        }
    }

    if (validator_count == 0)
    {
        if (allocated_pubkeys)
        {
            free((void *)pubkeys);
        }
        lantern_log_warn(
            "state",
            meta,
            "init_replay_state invalid validator_count=0");
        return false;
    }

    *out_pubkeys = pubkeys;
    *out_validator_count = validator_count;
    *out_allocated_pubkeys = allocated_pubkeys;
    return true;
}

static bool init_replay_state(const struct lantern_client *client, LanternState *out_state)
{
    if (!client || !out_state)
    {
        return false;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    lantern_state_init(out_state);

    if (client->genesis.state_bytes && client->genesis.state_size > 0)
    {
        lantern_log_debug(
            "state",
            &meta,
            "init_replay_state ignoring local genesis state bytes size=%zu",
            client->genesis.state_size);
    }

    const uint8_t *pubkeys = NULL;
    size_t validator_count = 0;
    bool allocated_pubkeys = false;
    if (!resolve_replay_validator_pubkeys(
            client,
            &meta,
            &pubkeys,
            &validator_count,
            &allocated_pubkeys))
    {
        lantern_state_reset(out_state);
        return false;
    }

    const struct lantern_chain_config *config = &client->genesis.chain_config;
    if (lantern_state_generate_genesis(
            out_state,
            config->genesis_time,
            (uint64_t)validator_count)
        != 0)
    {
        if (allocated_pubkeys)
        {
            free((void *)pubkeys);
        }
        lantern_log_warn(
            "state",
            &meta,
            "init_replay_state failed to generate genesis time=%" PRIu64 " validators=%zu",
            config->genesis_time,
            validator_count);
        lantern_state_reset(out_state);
        return false;
    }

    if (lantern_state_set_validator_pubkeys(out_state, pubkeys, validator_count) != 0)
    {
        if (allocated_pubkeys)
        {
            free((void *)pubkeys);
        }
        lantern_log_warn(
            "state",
            &meta,
            "init_replay_state failed to set validator pubkeys count=%zu",
            validator_count);
        lantern_state_reset(out_state);
        return false;
    }

    if (allocated_pubkeys)
    {
        free((void *)pubkeys);
    }

    return true;
}

static bool compute_state_head_root_locked(
    struct lantern_client *client,
    LanternRoot *out_root)
{
    if (!client || !out_root)
    {
        return false;
    }
    if (lantern_state_process_slot(&client->state) != 0)
    {
        return false;
    }
    if (lantern_hash_tree_root_block_header(&client->state.latest_block_header, out_root) != 0)
    {
        return false;
    }
    return true;
}

static bool rebuild_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *target_root,
    LanternState *out_state,
    LanternRoot *out_missing_roots,
    size_t missing_roots_cap,
    size_t *out_missing_count);

static bool state_matches_root(const LanternState *state, const LanternRoot *root)
{
    if (!state || !root)
    {
        return false;
    }
    LanternRoot state_root;
    if (lantern_hash_tree_root_state(state, &state_root) != 0)
    {
        return false;
    }
    LanternBlockHeader header = state->latest_block_header;
    header.state_root = state_root;
    LanternRoot header_root;
    if (lantern_hash_tree_root_block_header(&header, &header_root) != 0)
    {
        return false;
    }
    return memcmp(header_root.bytes, root->bytes, LANTERN_ROOT_SIZE) == 0;
}

const LanternState *lantern_client_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *root,
    LanternState *scratch,
    bool *out_is_scratch)
{
    if (out_is_scratch)
    {
        *out_is_scratch = false;
    }
    if (!client || !root)
    {
        return NULL;
    }

    if (client->has_state && state_matches_root(&client->state, root))
    {
        return &client->state;
    }

    if (!scratch)
    {
        return NULL;
    }

    if (client->data_dir && client->data_dir[0])
    {
        uint8_t *state_bytes = NULL;
        size_t state_len = 0;
        if (lantern_storage_load_state_bytes_for_root(
                client->data_dir,
                root,
                &state_bytes,
                &state_len)
            == 0
            && state_bytes
            && state_len > 0)
        {
            lantern_state_reset(scratch);
            lantern_state_init(scratch);
            if (lantern_ssz_decode_state(scratch, state_bytes, state_len) == 0)
            {
                free(state_bytes);
                if (out_is_scratch)
                {
                    *out_is_scratch = true;
                }
                return scratch;
            }
            lantern_state_reset(scratch);
            free(state_bytes);
        }
    }

    if (client->data_dir && client->data_dir[0])
    {
        lantern_state_reset(scratch);
        if (rebuild_state_for_root_locked(client, root, scratch, NULL, 0, NULL))
        {
            if (out_is_scratch)
            {
                *out_is_scratch = true;
            }
            return scratch;
        }
        lantern_state_reset(scratch);
    }

    return NULL;
}

static void adopt_state_locked(struct lantern_client *client, LanternState *state)
{
    if (!client || !state)
    {
        return;
    }
    LanternState previous = client->state;
    client->state = *state;
    lantern_state_attach_fork_choice(&client->state, &client->fork_choice);
    if (client->has_fork_choice)
    {
        if (lantern_fork_choice_update_checkpoints(
                &client->fork_choice,
                &client->state.latest_justified,
                &client->state.latest_finalized)
            != 0)
        {
            lantern_log_warn(
                "forkchoice",
                &(const struct lantern_log_metadata){.validator = client->node_id},
                "failed to sync fork choice checkpoints when adopting state slot=%" PRIu64,
                client->state.slot);
        }
    }
    lantern_state_reset(&previous);
}

static bool rebuild_state_for_root_locked(
    struct lantern_client *client,
    const LanternRoot *target_root,
    LanternState *out_state,
    LanternRoot *out_missing_roots,
    size_t missing_roots_cap,
    size_t *out_missing_count)
{
    if (!client || !target_root || !out_state)
    {
        return false;
    }
    if (out_missing_count)
    {
        *out_missing_count = 0;
    }

    struct lantern_log_metadata meta = {.validator = client->node_id};
    char target_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(target_root, target_hex, sizeof(target_hex));

    struct lantern_root_chain chain = {0};
    if (!build_root_chain_locked(client, target_root, &chain))
    {
        lantern_log_warn(
            "state",
            &meta,
            "rebuild_state failed to build root chain target=%s",
            target_hex[0] ? target_hex : "0x0");
        root_chain_reset(&chain);
        return false;
    }

    size_t root_count = 0;
    for (size_t i = 0; i < chain.length; ++i)
    {
        if (chain.items[i].slot != 0)
        {
            root_count += 1u;
        }
    }

    lantern_log_info(
        "state",
        &meta,
        "rebuild_state start target=%s chain_len=%zu root_count=%zu",
        target_hex[0] ? target_hex : "0x0",
        chain.length,
        root_count);

    LanternRoot *roots = NULL;
    if (root_count > 0)
    {
        if (!client->data_dir || !client->data_dir[0])
        {
            root_chain_reset(&chain);
            return false;
        }
        roots = calloc(root_count, sizeof(*roots));
        if (!roots)
        {
            root_chain_reset(&chain);
            return false;
        }
        size_t idx = 0;
        for (size_t i = chain.length; i-- > 0;)
        {
            if (chain.items[i].slot == 0)
            {
                continue;
            }
            roots[idx++] = chain.items[i].root;
        }
    }

    LanternBlocksByRootResponse response;
    lantern_blocks_by_root_response_init(&response);
    int collect_rc = 0;
    if (root_count > 0)
    {
        collect_rc = lantern_storage_collect_blocks(
            client->data_dir,
            roots,
            root_count,
            &response);
    }
    if (collect_rc != 0 || response.length != root_count)
    {
        lantern_log_warn(
            "state",
            &meta,
            "rebuild_state block collection mismatch target=%s collect_rc=%d expected=%zu got=%zu",
            target_hex[0] ? target_hex : "0x0",
            collect_rc,
            root_count,
            response.length);
        if (roots && root_count > 0)
        {
            LanternRoot *found_roots = NULL;
            size_t found_count = 0;
            if (response.length > 0)
            {
                found_roots = calloc(response.length, sizeof(*found_roots));
                if (found_roots)
                {
                    for (size_t i = 0; i < response.length; ++i)
                    {
                        if (lantern_hash_tree_root_block(&response.blocks[i].message.block, &found_roots[i]) == 0)
                        {
                            found_count += 1u;
                        }
                    }
                }
            }
            size_t missing = 0;
            size_t logged = 0;
            size_t missing_filled = 0;
            for (size_t i = 0; i < root_count; ++i)
            {
                bool present = false;
                if (found_roots)
                {
                    for (size_t j = 0; j < response.length; ++j)
                    {
                        if (memcmp(roots[i].bytes, found_roots[j].bytes, LANTERN_ROOT_SIZE) == 0)
                        {
                            present = true;
                            break;
                        }
                    }
                }
                if (!present)
                {
                    missing += 1u;
                    if (out_missing_roots && missing_filled < missing_roots_cap)
                    {
                        out_missing_roots[missing_filled] = roots[i];
                        missing_filled += 1u;
                    }
                    if (logged < 5)
                    {
                        char missing_hex[ROOT_HEX_BUFFER_LEN];
                        format_root_hex(&roots[i], missing_hex, sizeof(missing_hex));
                        lantern_log_warn(
                            "state",
                            &meta,
                            "rebuild_state missing block root=%s",
                            missing_hex[0] ? missing_hex : "0x0");
                        logged += 1u;
                    }
                }
            }
            if (out_missing_count)
            {
                *out_missing_count = missing_filled;
            }
            lantern_log_warn(
                "state",
                &meta,
                "rebuild_state missing_blocks=%zu found_blocks=%zu",
                missing,
                found_count);
            free(found_roots);
        }
    }
    free(roots);
    roots = NULL;
    if (collect_rc != 0 || response.length != root_count)
    {
        lantern_blocks_by_root_response_reset(&response);
        root_chain_reset(&chain);
        return false;
    }

    bool success = init_replay_state(client, out_state);
    if (!success)
    {
        lantern_log_warn(
            "state",
            &meta,
            "rebuild_state failed to initialize replay state target=%s",
            target_hex[0] ? target_hex : "0x0");
        lantern_blocks_by_root_response_reset(&response);
        root_chain_reset(&chain);
        return false;
    }

    for (size_t i = 0; i < response.length; ++i)
    {
        int transition_rc = lantern_state_transition(out_state, &response.blocks[i]);
        if (transition_rc != 0)
        {
            LanternRoot block_root = {0};
            char block_hex[ROOT_HEX_BUFFER_LEN] = {0};
            if (lantern_hash_tree_root_block(&response.blocks[i].message.block, &block_root) == 0)
            {
                format_root_hex(&block_root, block_hex, sizeof(block_hex));
            }
            lantern_log_warn(
                "state",
                &meta,
                "rebuild_state transition failed idx=%zu slot=%" PRIu64 " rc=%d root=%s",
                i,
                response.blocks[i].message.block.slot,
                transition_rc,
                block_hex[0] ? block_hex : "0x0");
            lantern_blocks_by_root_response_reset(&response);
            root_chain_reset(&chain);
            lantern_state_reset(out_state);
            return false;
        }
    }

    lantern_blocks_by_root_response_reset(&response);
    root_chain_reset(&chain);
    return true;
}


/**
 * Handle parent tracking and competing forks.
 *
 * @param client       Client instance
 * @param block        Block being imported
 * @param meta         Logging metadata
 * @param state_locked In/out state lock flag (may be cleared if unlocked here)
 * @param backfill_depth Backfill depth of the block
 * @return Parent action describing how to proceed
 *
 * @note Thread safety: Caller must hold state_lock
 */
static enum block_parent_action handle_block_parent_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    bool *state_locked,
    uint32_t backfill_depth,
    bool allow_historical)
{
    if (!client || !block || !block_root || !state_locked || !*state_locked)
    {
        return BLOCK_PARENT_ACTION_UNKNOWN;
    }

    LanternRoot parent_root = block->message.block.parent_root;
    if (lantern_root_is_zero(&parent_root))
    {
        return BLOCK_PARENT_ACTION_MATCHES_HEAD;
    }

    bool parent_known = lantern_client_block_known_locked(client, &parent_root, NULL);
    if (!parent_known)
    {
        const char *peer_text = meta && meta->peer ? meta->peer : NULL;
        lantern_client_unlock_state(client, *state_locked);
        *state_locked = false;
        lantern_client_enqueue_pending_block(
            client,
            block,
            block_root,
            &parent_root,
            peer_text,
            backfill_depth,
            allow_historical);
        return BLOCK_PARENT_ACTION_UNKNOWN;
    }

    bool have_head_root = false;
    bool parent_matches_head = false;
    LanternRoot latest_header_root = {0};

    /* Ensure state_root is filled in latest_block_header before computing its hash.
       This is required because state_root is zeroed when a block is applied and only
       filled in lazily by lantern_state_process_slot. Without this, the computed
       header root may differ from what other clients expect. */
    if (lantern_state_process_slot(&client->state) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to compute cached header state root at slot=%" PRIu64,
            client->state.slot);
    }
    else if (lantern_hash_tree_root_block_header(
                 &client->state.latest_block_header,
                 &latest_header_root) == 0)
    {
        have_head_root = true;
        parent_matches_head =
            memcmp(latest_header_root.bytes, parent_root.bytes, LANTERN_ROOT_SIZE) == 0;
    }

    if (parent_matches_head)
    {
        return BLOCK_PARENT_ACTION_MATCHES_HEAD;
    }

    if (have_head_root)
    {
        char parent_hex[ROOT_HEX_BUFFER_LEN];
        char head_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&parent_root, parent_hex, sizeof(parent_hex));
        format_root_hex(&latest_header_root, head_hex, sizeof(head_hex));
        lantern_log_debug(
            "state",
            meta,
            "block on competing fork slot=%" PRIu64 " parent=%s current_head=%s",
            block->message.block.slot,
            parent_hex[0] ? parent_hex : "0x0",
            head_hex[0] ? head_hex : "0x0");
    }

    return BLOCK_PARENT_ACTION_KNOWN_OFF_HEAD;
}

static bool add_competing_fork_block_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternCheckpoint *post_justified,
    const LanternCheckpoint *post_finalized,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block || !block_root || !client->has_fork_choice)
    {
        return false;
    }

    LanternSignedVote proposer_signed = {0};
    proposer_signed.data = block->message.proposer_attestation;
    proposer_signed.signature = block->signatures.proposer_signature;

    if (lantern_fork_choice_add_block(
            &client->fork_choice,
            &block->message.block,
            &proposer_signed,
            post_justified,
            post_finalized,
            block_root) != 0)
    {
        return false;
    }

    char block_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(block_root, block_hex, sizeof(block_hex));
    lantern_log_info(
        "forkchoice",
        meta,
        "added competing fork block to fork choice slot=%" PRIu64 " root=%s",
        block->message.block.slot,
        block_hex[0] ? block_hex : "0x0");
    return true;
}


/**
 * @brief Validates attestation constraints for the block.
 *
 * @param client  Client instance
 * @param block   Signed block
 * @param meta    Logging metadata
 * @return true if constraints pass, false otherwise
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool validate_block_vote_constraints_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block)
    {
        return false;
    }
    if (!client->has_fork_choice)
    {
        return true;
    }

    const LanternAggregatedAttestations *attestations = &block->message.block.body.attestations;
    if (attestations->length > 0 && !attestations->data)
    {
        lantern_log_warn(
            "state",
            meta,
            "block slot=%" PRIu64 " attestations missing data length=%zu",
            block->message.block.slot,
            attestations->length);
        return false;
    }
    LanternAttestations expanded;
    lantern_attestations_init(&expanded);
    size_t validator_count = lantern_state_validator_count(&client->state);
    if (lantern_expand_aggregated_attestations(attestations, validator_count, &expanded) != 0)
    {
        lantern_attestations_reset(&expanded);
        return false;
    }
    for (size_t i = 0; i < expanded.length; ++i)
    {
        if (!lantern_client_validate_vote_constraints(
                client,
                &expanded.data[i],
                "state",
                meta,
                "block attestation",
                NULL))
        {
            lantern_attestations_reset(&expanded);
            return false;
        }
    }
    lantern_attestations_reset(&expanded);

    /* Skip proposer attestation validation here - the proposer's head checkpoint
     * references the block being imported, which isn't in fork choice yet.
     * The proposer attestation will be validated during state transition. */
    return true;
}


/**
 * @brief Applies the state transition for a block.
 *
 * @param client  Client instance
 * @param block   Signed block to import
 * @param meta    Logging metadata
 * @return true on success, false on failure
 *
 * @note Thread safety: Caller must hold state_lock
 */
static bool apply_state_transition_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block)
    {
        return false;
    }

    LanternSignedBlock import_block = *block;
    if (lantern_state_transition(&client->state, &import_block) != 0)
    {
        lantern_log_warn(
            "state",
            meta,
            "state transition failed for slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }

    return true;
}


/**
 * @brief Advances fork choice time after a successful import.
 *
 * @param client  Client instance
 * @param block   Imported block (for logging)
 * @param meta    Logging metadata
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void advance_fork_choice_time_locked(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const struct lantern_log_metadata *meta)
{
    if (!client || !block || !client->has_fork_choice)
    {
        return;
    }

    uint64_t now_seconds = validator_wall_time_now_seconds();
    if (lantern_fork_choice_advance_time(&client->fork_choice, now_seconds, false) != 0)
    {
        lantern_log_debug(
            "forkchoice",
            meta,
            "advancing fork choice time failed after slot=%" PRIu64,
            block->message.block.slot);
    }
}


/**
 * @brief Computes head slot/root for logging.
 *
 * @param client        Client instance
 * @param out_head_root Output head root
 * @param out_head_slot Output head slot
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void get_head_info_locked(
    struct lantern_client *client,
    LanternRoot *out_head_root,
    uint64_t *out_head_slot)
{
    if (!client || !out_head_root || !out_head_slot)
    {
        return;
    }

    *out_head_slot = client->state.slot;
    *out_head_root = (LanternRoot){0};
    if (!client->has_fork_choice)
    {
        return;
    }

    if (lantern_fork_choice_current_head(&client->fork_choice, out_head_root) != 0)
    {
        return;
    }

    uint64_t fork_slot = 0;
    if (lantern_fork_choice_block_info(
            &client->fork_choice,
            out_head_root,
            &fork_slot,
            NULL,
            NULL) == 0)
    {
        *out_head_slot = fork_slot;
    }
}


/**
 * @brief Persists client state/votes if storage is enabled.
 *
 * @param client  Client instance
 * @param meta    Logging metadata
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void persist_state_locked(
    const struct lantern_client *client,
    const struct lantern_log_metadata *meta)
{
    if (!client || !client->data_dir)
    {
        return;
    }

    if (lantern_storage_save_state(client->data_dir, &client->state) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist state after slot=%" PRIu64,
            client->state.slot);
    }
    if (lantern_storage_save_votes(client->data_dir, &client->state) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist votes after slot=%" PRIu64,
            client->state.slot);
    }
}

/**
 * @brief Persist per-block post-state and sync indices.
 *
 * @param client     Client instance
 * @param post_state Post-state after applying the block
 * @param block      Imported block
 * @param block_root Root of the block
 * @param head_root  Current head root
 * @param head_slot  Current head slot
 * @param meta       Logging metadata
 *
 * @note Thread safety: Caller must hold state_lock
 */
static void persist_post_state_and_indices_locked(
    const struct lantern_client *client,
    const LanternState *post_state,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const LanternRoot *head_root,
    uint64_t head_slot,
    const struct lantern_log_metadata *meta)
{
    if (!client || !client->data_dir || !post_state || !block || !block_root)
    {
        return;
    }

    if (lantern_storage_store_state_for_root(client->data_dir, block_root, post_state) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist post-state slot=%" PRIu64,
            block->message.block.slot);
    }
    if (lantern_storage_store_slot_root(
            client->data_dir,
            block->message.block.slot,
            block_root)
        != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist slot index slot=%" PRIu64,
            block->message.block.slot);
    }
    if (lantern_storage_store_head_root(client->data_dir, head_slot, head_root) != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist head index slot=%" PRIu64,
            head_slot);
    }
    if (lantern_storage_store_checkpoints(
            client->data_dir,
            &post_state->latest_justified,
            &post_state->latest_finalized)
        != 0)
    {
        lantern_log_warn(
            "storage",
            meta,
            "failed to persist checkpoints slot=%" PRIu64,
            post_state->slot);
    }
}


/**
 * @brief Logs a successful block import.
 *
 * @param block      Imported block
 * @param head_root  New head root
 * @param head_slot  New head slot
 * @param meta       Logging metadata
 *
 * @note Thread safety: This function is thread-safe
 */
static void log_imported_block(
    const LanternSignedBlock *block,
    const LanternRoot *head_root,
    uint64_t head_slot,
    const struct lantern_log_metadata *meta,
    bool quiet)
{
    if (!block || !head_root)
    {
        return;
    }

    char head_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(head_root, head_hex, sizeof(head_hex));
    if (quiet)
    {
        lantern_log_debug(
            "state",
            meta,
            "imported block slot=%" PRIu64 " new_head_slot=%" PRIu64 " head_root=%s",
            block->message.block.slot,
            head_slot,
            head_hex[0] ? head_hex : "0x0");
    }
    else
    {
        lantern_log_info(
            "state",
            meta,
            "imported block slot=%" PRIu64 " new_head_slot=%" PRIu64 " head_root=%s",
            block->message.block.slot,
            head_slot,
            head_hex[0] ? head_hex : "0x0");
    }
}


/* ============================================================================
 * Block Import
 * ============================================================================ */

/**
 * Import a block into the client state and fork choice.
 *
 * @spec subspecs/containers/state/state.py - State.state_transition()
 * @spec subspecs/forkchoice/store.py - Store.on_block()
 *
 * Performs the complete block import pipeline:
 * 1. Validates block slot against local state
 * 2. Checks if block root is already known
 * 3. Handles parent tracking:
 *    - Unknown parent: queue as pending
 *    - Parent known but not head: validate, add to fork choice, process cached descendants
 *    - Parent matches head: proceed with full import
 * 4. Verifies all block signatures
 * 5. Validates attestation constraints
 * 6. Applies state transition (head-matching parents only)
 * 7. Updates fork choice
 * 8. Persists state and votes
 * 9. Processes pending children
 *
 * Per leanSpec: Blocks on competing forks are added to fork choice so
 * attestations can reference them and fork choice can determine which
 * chain has more weight.
 *
 * @param client      Client instance
 * @param block       Signed block to import
 * @param block_root  Precomputed block root (may be NULL)
 * @param meta        Logging metadata
 * @param backfill_depth Backfill depth of the block
 * @return true if block was imported successfully
 *
 * @note Thread safety: Acquires state_lock and pending_lock
 */
bool lantern_client_import_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *block_root,
    const struct lantern_log_metadata *meta,
    uint32_t backfill_depth,
    bool allow_historical)
{
    if (!client || !block || !client->has_state)
    {
        return false;
    }

    bool imported = false;
    bool state_locked = lantern_client_lock_state(client);
    if (!state_locked)
    {
        lantern_log_warn(
            "state",
            meta,
            "failed to acquire state lock for block import slot=%" PRIu64,
            block->message.block.slot);
        return false;
    }

    uint64_t local_slot = client->state.slot;
    LanternRoot block_root_local = {0};
    LanternRoot head_root = {0};
    uint64_t head_slot = 0;

    if (!get_block_root_local(block, block_root, &block_root_local, meta))
    {
        goto cleanup;
    }

    uint64_t known_slot = 0;
    bool root_known = lantern_client_block_known_locked(client, &block_root_local, &known_slot);
    if (root_known && allow_historical && block->message.block.slot <= known_slot)
    {
        lantern_client_unlock_state(client, state_locked);
        state_locked = false;
        persist_block_after_import(client, block, meta);
        lantern_client_process_pending_children(client, &block_root_local);
        lantern_client_pending_remove_by_root(client, &block_root_local);
        return false;
    }

    if (!should_process_block(
            block->message.block.slot,
            local_slot,
            root_known,
            known_slot,
            meta))
    {
        goto cleanup;
    }

    enum block_parent_action parent_action = handle_block_parent_locked(
        client,
        block,
        &block_root_local,
        meta,
        &state_locked,
        backfill_depth,
        allow_historical);
    if (parent_action == BLOCK_PARENT_ACTION_UNKNOWN)
    {
        goto cleanup;
    }
    bool parent_off_head = parent_action == BLOCK_PARENT_ACTION_KNOWN_OFF_HEAD;

    if (!signed_block_signatures_are_valid(client, block, meta))
    {
        char root_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&block_root_local, root_hex, sizeof(root_hex));
        lantern_log_warn(
            "state",
            meta,
            "signature verification failed slot=%" PRIu64 " root=%s depth=%" PRIu32,
            block->message.block.slot,
            root_hex[0] ? root_hex : "0x0",
            backfill_depth);
        goto cleanup;
    }

    if (!validate_block_vote_constraints_locked(client, block, meta))
    {
        char root_hex[ROOT_HEX_BUFFER_LEN];
        format_root_hex(&block_root_local, root_hex, sizeof(root_hex));
        lantern_log_warn(
            "state",
            meta,
            "vote constraints failed slot=%" PRIu64 " root=%s depth=%" PRIu32,
            block->message.block.slot,
            root_hex[0] ? root_hex : "0x0",
            backfill_depth);
        goto cleanup;
    }

    cache_block_aggregated_proofs_locked(client, block);

    if (parent_off_head)
    {
        LanternRoot parent_root = block->message.block.parent_root;
        LanternState replay_state;
        bool have_replay_state = false;
        bool processed = false;
        bool deferred = false;
        LanternRoot missing_roots[LANTERN_MAX_REQUEST_BLOCKS];
        size_t missing_count = 0;

        if (rebuild_state_for_root_locked(
                client,
                &parent_root,
                &replay_state,
                missing_roots,
                LANTERN_MAX_REQUEST_BLOCKS,
                &missing_count))
        {
            have_replay_state = true;
            if (lantern_state_transition(&replay_state, block) == 0)
            {
                processed = add_competing_fork_block_locked(
                    client,
                    block,
                    &block_root_local,
                    &replay_state.latest_justified,
                    &replay_state.latest_finalized,
                    meta);
            }
            else
            {
                lantern_log_warn(
                    "state",
                    meta,
                    "off-head state transition failed for slot=%" PRIu64,
                    block->message.block.slot);
            }
        }
        else
        {
            lantern_log_warn(
                "state",
                meta,
                "failed to rebuild parent state for off-head slot=%" PRIu64,
                block->message.block.slot);
            deferred = true;
            const char *peer_text = meta && meta->peer ? meta->peer : NULL;
            lantern_client_enqueue_pending_block(
                client,
                block,
                &block_root_local,
                &parent_root,
                peer_text,
                backfill_depth,
                true);
            if (missing_count > 0)
            {
                uint32_t request_depths[LANTERN_MAX_REQUEST_BLOCKS];
                uint32_t request_depth = backfill_depth + 1u;
                if (request_depth > LANTERN_MAX_BACKFILL_DEPTH)
                {
                    request_depth = LANTERN_MAX_BACKFILL_DEPTH;
                }
                for (size_t i = 0; i < missing_count; ++i)
                {
                    request_depths[i] = request_depth;
                }
                (void)lantern_client_try_schedule_blocks_request_batch(
                    client,
                    peer_text,
                    missing_roots,
                    request_depths,
                    missing_count);
            }
        }

        bool adopted_state = false;
        if (processed && client->has_fork_choice)
        {
            LanternRoot fork_head = {0};
            bool have_fork_head = lantern_fork_choice_current_head(
                &client->fork_choice,
                &fork_head)
                == 0;
            LanternRoot state_head = {0};
            bool have_state_head = have_fork_head && compute_state_head_root_locked(
                client,
                &state_head);

            if (have_fork_head && have_state_head
                && memcmp(fork_head.bytes, state_head.bytes, LANTERN_ROOT_SIZE) != 0)
            {
                if (have_replay_state
                    && memcmp(fork_head.bytes, block_root_local.bytes, LANTERN_ROOT_SIZE) == 0)
                {
                    adopt_state_locked(client, &replay_state);
                    have_replay_state = false;
                    adopted_state = true;
                }
                else
                {
                    LanternState head_state;
                    if (rebuild_state_for_root_locked(
                            client,
                            &fork_head,
                            &head_state,
                            NULL,
                            0,
                            NULL))
                    {
                        adopt_state_locked(client, &head_state);
                        adopted_state = true;
                    }
                }
            }
        }

        if (adopted_state)
        {
            persist_state_locked(client, meta);
        }

        if (processed && have_replay_state)
        {
            get_head_info_locked(client, &head_root, &head_slot);
            persist_post_state_and_indices_locked(
                client,
                &replay_state,
                block,
                &block_root_local,
                &head_root,
                head_slot,
                meta);
        }

        if (have_replay_state)
        {
            lantern_state_reset(&replay_state);
        }

        lantern_client_unlock_state(client, state_locked);
        state_locked = false;
        if (!deferred)
        {
            lantern_client_pending_remove_by_root(client, &block_root_local);
        }
        if (processed)
        {
            persist_block_after_import(client, block, meta);
            lantern_client_process_pending_children(client, &block_root_local);
            update_sync_progress_after_block(client);
        }
        return false;
    }

    if (!apply_state_transition_locked(client, block, meta))
    {
        goto cleanup;
    }

    advance_fork_choice_time_locked(client, block, meta);
    get_head_info_locked(client, &head_root, &head_slot);
    persist_state_locked(client, meta);
    persist_post_state_and_indices_locked(
        client,
        &client->state,
        block,
        &block_root_local,
        &head_root,
        head_slot,
        meta);
    imported = true;

cleanup:
    lantern_client_unlock_state(client, state_locked);

    if (imported)
    {
        persist_block_after_import(client, block, meta);
        bool quiet_log = false;
        if (client->status_lock_initialized
            && pthread_mutex_lock(&client->status_lock) == 0)
        {
            client->sync_imported_blocks += 1u;
            quiet_log = client->sync_in_progress;
            pthread_mutex_unlock(&client->status_lock);
        }
        lantern_client_pending_remove_by_root(client, &block_root_local);
        lantern_client_process_pending_children(client, &block_root_local);
        log_imported_block(block, &head_root, head_slot, meta, quiet_log);
        update_sync_progress_after_block(client);
    }

    return imported;
}


/* ============================================================================
 * Block Recording
 * ============================================================================ */

/**
 * Record a received block and attempt import.
 *
 * @spec subspecs/forkchoice/store.py - Store.on_block()
 *
 * Entry point for recording blocks received from gossip or reqresp.
 * Computes the block root if not provided, delegates to import_block
 * for processing, and persists the block after successful import.
 *
 * @param client    Client instance
 * @param block     Signed block to record
 * @param root      Precomputed block root (may be NULL)
 * @param peer_text Peer ID string (may be NULL)
 * @param context   Description of source for logging
 * @param backfill_depth Backfill depth of the block
 *
 * @note Thread safety: Acquires state_lock via lantern_client_import_block
 */
void lantern_client_record_block(
    struct lantern_client *client,
    const LanternSignedBlock *block,
    const LanternRoot *root,
    const char *peer_text,
    const char *context,
    uint32_t backfill_depth,
    bool allow_historical)
{
    if (!client || !block)
    {
        return;
    }

    LanternRoot computed_root;
    const LanternRoot *selected_root = root;
    if (!selected_root)
    {
        if (lantern_hash_tree_root_block(&block->message.block, &computed_root) != 0)
        {
            return;
        }
        selected_root = &computed_root;
    }

    char root_hex[ROOT_HEX_BUFFER_LEN];
    format_root_hex(selected_root, root_hex, sizeof(root_hex));

    struct lantern_log_metadata meta = {
        .validator = client->node_id,
        .peer = peer_text && *peer_text ? peer_text : NULL,
    };
    const char *source = NULL;
    if (context && *context)
    {
        source = context;
    }
    else if (peer_text && *peer_text)
    {
        source = "peer";
    }
    else
    {
        source = "local";
    }

    if (client->sync_in_progress)
    {
        lantern_log_debug(
            "gossip",
            &meta,
            "received block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s source=%s",
            block->message.block.slot,
            block->message.block.proposer_index,
            root_hex[0] ? root_hex : "0x0",
            source);
    }
    else
    {
        lantern_log_info(
            "gossip",
            &meta,
            "received block slot=%" PRIu64 " proposer=%" PRIu64 " root=%s source=%s",
            block->message.block.slot,
            block->message.block.proposer_index,
            root_hex[0] ? root_hex : "0x0",
            source);
    }

    lantern_client_import_block(
        client,
        block,
        selected_root,
        &meta,
        backfill_depth,
        allow_historical);
}
