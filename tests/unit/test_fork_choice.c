#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "lantern/consensus/fork_choice.h"
#include "lantern/consensus/hash.h"
#include "lantern/consensus/store.h"
#include "lantern/consensus/state.h"

#ifdef NDEBUG
#undef assert
#define assert(expr)                                                                          \
    do {                                                                                      \
        if (!(expr)) {                                                                        \
            fprintf(stderr, "Assertion failed: %s (%s:%d)\n", #expr, __FILE__, __LINE__);    \
            abort();                                                                          \
        }                                                                                     \
    } while (0)
#endif

static void zero_root(LanternRoot *root) {
    if (!root) {
        return;
    }
    memset(root->bytes, 0, sizeof(root->bytes));
}

static void fill_root(LanternRoot *root, uint8_t value) {
    if (!root) {
        return;
    }
    memset(root->bytes, value, sizeof(root->bytes));
}

static bool roots_equal(const LanternRoot *a, const LanternRoot *b) {
    if (!a || !b) {
        return false;
    }
    return memcmp(a->bytes, b->bytes, sizeof(a->bytes)) == 0;
}

static bool checkpoints_equal(const LanternCheckpoint *a, const LanternCheckpoint *b) {
    if (!a || !b) {
        return false;
    }
    if (a->slot != b->slot) {
        return false;
    }
    return roots_equal(&a->root, &b->root);
}

static void init_block(
    LanternBlock *block,
    uint64_t slot,
    uint64_t proposer_index,
    const LanternRoot *parent_root,
    uint8_t state_marker) {
    memset(block, 0, sizeof(*block));
    block->slot = slot;
    block->proposer_index = proposer_index;
    if (parent_root) {
        block->parent_root = *parent_root;
    } else {
        zero_root(&block->parent_root);
    }
    fill_root(&block->state_root, state_marker);
    lantern_block_body_init(&block->body);
}

static void reset_block(LanternBlock *block) {
    if (!block) {
        return;
    }
    lantern_block_body_reset(&block->body);
}

static LanternCheckpoint make_checkpoint(const LanternRoot *root, uint64_t slot) {
    LanternCheckpoint cp;
    cp.root = *root;
    cp.slot = slot;
    return cp;
}

static LanternSignedVote make_vote(
    uint64_t validator_id,
    const LanternCheckpoint *source,
    const LanternCheckpoint *target) {
    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    vote.data.validator_id = validator_id;
    vote.data.slot = target ? target->slot : 0;
    if (source) {
        vote.data.source = *source;
    } else {
        zero_root(&vote.data.source.root);
        vote.data.source.slot = 0;
    }
    if (target) {
        vote.data.target = *target;
        vote.data.head = *target;
    } else {
        zero_root(&vote.data.target.root);
        vote.data.target.slot = 0;
        zero_root(&vote.data.head.root);
        vote.data.head.slot = 0;
    }
    return vote;
}

static int build_dummy_proof(
    LanternAggregatedSignatureProof *out_proof,
    uint64_t validator_id,
    uint8_t seed) {
    if (!out_proof || validator_id >= LANTERN_VALIDATOR_REGISTRY_LIMIT) {
        return -1;
    }
    lantern_aggregated_signature_proof_init(out_proof);
    size_t bit_length = (size_t)validator_id + 1u;
    if (lantern_bitlist_resize(&out_proof->participants, bit_length) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    if (lantern_bitlist_set(&out_proof->participants, (size_t)validator_id, true) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    if (lantern_byte_list_resize(&out_proof->proof_data, 8u) != 0) {
        lantern_aggregated_signature_proof_reset(out_proof);
        return -1;
    }
    for (size_t i = 0; i < out_proof->proof_data.length; ++i) {
        out_proof->proof_data.data[i] = (uint8_t)(seed + (uint8_t)i);
    }
    return 0;
}

static int seed_known_payload(
    LanternStore *store,
    const LanternSignedVote *vote,
    uint8_t seed) {
    if (!store || !vote) {
        return -1;
    }
    const LanternAttestationData *data = &vote->data.data;
    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(data, &data_root) != 0) {
        return -1;
    }
    LanternAggregatedSignatureProof proof;
    if (build_dummy_proof(&proof, vote->data.validator_id, seed) != 0) {
        return -1;
    }
    int rc = lantern_store_add_known_aggregated_payload(
        store,
        &data_root,
        data,
        &proof,
        vote->data.target.slot);
    lantern_aggregated_signature_proof_reset(&proof);
    return rc;
}

static int seed_new_payload(
    LanternStore *store,
    const LanternSignedVote *vote,
    uint8_t seed) {
    if (!store || !vote) {
        return -1;
    }
    const LanternAttestationData *data = &vote->data.data;
    LanternRoot data_root;
    if (lantern_hash_tree_root_attestation_data(data, &data_root) != 0) {
        return -1;
    }
    LanternAggregatedSignatureProof proof;
    if (build_dummy_proof(&proof, vote->data.validator_id, seed) != 0) {
        return -1;
    }
    int rc = lantern_store_add_new_aggregated_payload(
        store,
        &data_root,
        data,
        &proof,
        vote->data.target.slot);
    lantern_aggregated_signature_proof_reset(&proof);
    return rc;
}

static const struct lantern_fork_choice_tree_node *find_tree_snapshot_node(
    const struct lantern_fork_choice_tree_snapshot *snapshot,
    const LanternRoot *root) {
    if (!snapshot || !root) {
        return NULL;
    }
    for (size_t i = 0; i < snapshot->node_count; ++i) {
        if (roots_equal(&snapshot->nodes[i].root, root)) {
            return &snapshot->nodes[i];
        }
    }
    return NULL;
}

static size_t find_block_index(
    const LanternForkChoice *store,
    const LanternRoot *root) {
    if (!store || !root) {
        return SIZE_MAX;
    }
    for (size_t i = 0; i < store->block_len; ++i) {
        if (roots_equal(&store->blocks[i].root, root)) {
            return i;
        }
    }
    return SIZE_MAX;
}

static void seed_state_allocations(
    LanternState *state,
    size_t validator_count,
    size_t history_len,
    uint8_t seed) {
    assert(state != NULL);
    assert(validator_count > 0);
    assert(validator_count <= LANTERN_VALIDATOR_REGISTRY_LIMIT);

    size_t pubkey_bytes = validator_count * LANTERN_VALIDATOR_PUBKEY_SIZE;
    uint8_t *pubkeys = calloc(pubkey_bytes, 1u);
    assert(pubkeys != NULL);
    for (size_t i = 0; i < pubkey_bytes; ++i) {
        pubkeys[i] = (uint8_t)(seed + (uint8_t)i);
    }
    assert(lantern_state_set_validator_pubkeys(state, pubkeys, validator_count) == 0);
    free(pubkeys);

    assert(lantern_root_list_resize(&state->historical_block_hashes, history_len) == 0);
    assert(lantern_root_list_resize(&state->justification_roots, history_len) == 0);
    for (size_t i = 0; i < history_len; ++i) {
        fill_root(&state->historical_block_hashes.items[i], (uint8_t)(seed + (uint8_t)i));
        fill_root(&state->justification_roots.items[i], (uint8_t)(seed + 0x40u + (uint8_t)i));
    }
    assert(lantern_bitlist_resize(&state->justified_slots, history_len) == 0);
    assert(lantern_bitlist_resize(&state->justification_validators, history_len * validator_count) == 0);
}

static void build_cached_state(
    LanternState *out_state,
    const LanternState *parent_state,
    const LanternBlock *block,
    const LanternCheckpoint *latest_justified,
    const LanternCheckpoint *latest_finalized,
    uint8_t seed) {
    assert(out_state != NULL);
    assert(parent_state != NULL);
    assert(block != NULL);

    lantern_state_init(out_state);
    assert(lantern_state_clone(parent_state, out_state) == 0);
    out_state->slot = block->slot;
    out_state->latest_block_header.slot = block->slot;
    out_state->latest_block_header.proposer_index = block->proposer_index;
    out_state->latest_block_header.parent_root = block->parent_root;
    if (latest_justified) {
        out_state->latest_justified = *latest_justified;
    }
    if (latest_finalized) {
        out_state->latest_finalized = *latest_finalized;
    }

    seed_state_allocations(
        out_state,
        (size_t)out_state->config.num_validators,
        (size_t)block->slot + 2u,
        seed);
}

static void configure_fork_choice_with_backing_store(
    LanternForkChoice *store,
    LanternStore *backing_store,
    const LanternConfig *config) {
    assert(store != NULL);
    assert(backing_store != NULL);
    assert(config != NULL);
    lantern_fork_choice_init(store);
    lantern_store_init(backing_store);
    lantern_store_attach_fork_choice(backing_store, store);
    assert(lantern_fork_choice_configure(store, config) == 0);
}

static int test_fork_choice_proposer_attestation_sequence(void) {
    LanternForkChoice store;
    LanternStore backing_store;
    lantern_fork_choice_init(&store);
    lantern_store_init(&backing_store);
    lantern_store_attach_fork_choice(&backing_store, &store);

    LanternConfig config = {.num_validators = 1, .genesis_time = 10};
    assert(lantern_fork_choice_configure(&store, &config) == 0);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0xAA);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock block_one;
    init_block(&block_one, 1, 0, &genesis_root, 0xBB);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    LanternSignedVote proposer_vote_one = make_vote(0, &genesis_cp, &block_one_cp);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_one,
            &proposer_vote_one,
            NULL,
            NULL,
            &block_one_root)
        == 0);

    LanternRoot head;
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_one_root));

    assert(lantern_fork_choice_accept_new_aggregated_payloads(&store) == 0);
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_one_root));

    LanternBlock block_two;
    init_block(&block_two, 2, 0, &block_one_root, 0xCC);
    LanternRoot block_two_root;
    assert(lantern_hash_tree_root_block(&block_two, &block_two_root) == 0);
    LanternCheckpoint block_two_cp = make_checkpoint(&block_two_root, block_two.slot);
    LanternSignedVote proposer_vote_two = make_vote(0, &block_one_cp, &block_two_cp);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_two,
            &proposer_vote_two,
            NULL,
            NULL,
            &block_two_root)
        == 0);

    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_two_root));

    assert(lantern_fork_choice_accept_new_aggregated_payloads(&store) == 0);
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_two_root));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_two);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_block_updates_checkpoints(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 3, .genesis_time = 50};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x10);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock block_one;
    init_block(&block_one, 1, 0, &genesis_root, 0x11);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_one,
            NULL,
            &block_one_cp,
            NULL,
            &block_one_root)
        == 0);

    const LanternCheckpoint *latest_justified = lantern_fork_choice_latest_justified(&store);
    assert(checkpoints_equal(latest_justified, &block_one_cp));
    const LanternCheckpoint *latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(checkpoints_equal(latest_finalized, &genesis_cp));

    LanternBlock block_two;
    init_block(&block_two, 2, 1, &block_one_root, 0x22);
    LanternRoot block_two_root;
    assert(lantern_hash_tree_root_block(&block_two, &block_two_root) == 0);
    LanternCheckpoint block_two_cp = make_checkpoint(&block_two_root, block_two.slot);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_two,
            NULL,
            &block_two_cp,
            &block_one_cp,
            &block_two_root)
        == 0);

    latest_justified = lantern_fork_choice_latest_justified(&store);
    assert(checkpoints_equal(latest_justified, &block_two_cp));
    latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(checkpoints_equal(latest_finalized, &block_one_cp));

    LanternBlock block_three;
    init_block(&block_three, 3, 2, &block_two_root, 0x33);
    LanternRoot block_three_root;
    assert(lantern_hash_tree_root_block(&block_three, &block_three_root) == 0);
    LanternCheckpoint block_three_cp = make_checkpoint(&block_three_root, block_three.slot);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_three,
            NULL,
            &block_three_cp,
            &block_two_cp,
            &block_three_root)
        == 0);

    latest_justified = lantern_fork_choice_latest_justified(&store);
    assert(checkpoints_equal(latest_justified, &block_three_cp));
    latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(checkpoints_equal(latest_finalized, &block_two_cp));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_three);
    reset_block(&block_two);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_caches_block_states(void) {
    LanternForkChoice store;
    LanternStore backing_store;
    lantern_fork_choice_init(&store);
    lantern_store_init(&backing_store);
    lantern_store_attach_fork_choice(&backing_store, &store);

    LanternConfig config = {.num_validators = 2, .genesis_time = 77};
    assert(lantern_fork_choice_configure(&store, &config) == 0);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x51);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);

    LanternState genesis_state;
    lantern_state_init(&genesis_state);
    assert(lantern_state_generate_genesis(&genesis_state, config.genesis_time, config.num_validators) == 0);
    genesis_state.latest_justified = genesis_cp;
    genesis_state.latest_finalized = genesis_cp;

    assert(
        lantern_fork_choice_set_anchor_with_state(
            &store,
            &genesis,
            &genesis_cp,
            &genesis_cp,
            &genesis_root,
            &genesis_state)
        == 0);

    const LanternState *cached_genesis =
        lantern_fork_choice_block_state(&store, &genesis_root);
    assert(cached_genesis != NULL);
    assert(cached_genesis->slot == genesis_state.slot);
    assert(checkpoints_equal(&cached_genesis->latest_justified, &genesis_cp));
    assert(checkpoints_equal(&cached_genesis->latest_finalized, &genesis_cp));

    LanternBlock child;
    init_block(&child, 1, 1, &genesis_root, 0x52);
    LanternRoot child_root;
    assert(lantern_hash_tree_root_block(&child, &child_root) == 0);
    LanternCheckpoint child_cp = make_checkpoint(&child_root, child.slot);

    LanternState child_state;
    lantern_state_init(&child_state);
    assert(lantern_state_clone(&genesis_state, &child_state) == 0);
    child_state.slot = child.slot;
    child_state.latest_block_header.slot = child.slot;
    child_state.latest_block_header.proposer_index = child.proposer_index;
    child_state.latest_block_header.parent_root = child.parent_root;
    child_state.latest_justified = child_cp;
    child_state.latest_finalized = genesis_cp;

    assert(
        lantern_fork_choice_add_block_with_state(
            &store,
            &child,
            NULL,
            &child_state.latest_justified,
            &child_state.latest_finalized,
            &child_root,
            &child_state)
        == 0);

    const LanternState *cached_child = lantern_fork_choice_block_state(&store, &child_root);
    assert(cached_child != NULL);
    assert(cached_child->slot == child_state.slot);
    assert(checkpoints_equal(&cached_child->latest_justified, &child_cp));
    assert(checkpoints_equal(&cached_child->latest_finalized, &genesis_cp));

    lantern_state_reset(&child_state);
    lantern_state_reset(&genesis_state);
    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&child);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_prune_states_keeps_finalized_to_head_chain(void) {
    LanternForkChoice store;
    LanternStore backing_store;
    lantern_fork_choice_init(&store);
    lantern_store_init(&backing_store);
    lantern_store_attach_fork_choice(&backing_store, &store);

    LanternConfig config = {.num_validators = 3, .genesis_time = 91};
    assert(lantern_fork_choice_configure(&store, &config) == 0);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x61);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);

    LanternState genesis_state;
    lantern_state_init(&genesis_state);
    assert(lantern_state_generate_genesis(&genesis_state, config.genesis_time, config.num_validators) == 0);
    genesis_state.latest_justified = genesis_cp;
    genesis_state.latest_finalized = genesis_cp;
    seed_state_allocations(&genesis_state, config.num_validators, 2u, 0x20);

    assert(
        lantern_fork_choice_set_anchor_with_state(
            &store,
            &genesis,
            &genesis_cp,
            &genesis_cp,
            &genesis_root,
            &genesis_state)
        == 0);

    LanternBlock block_one;
    init_block(&block_one, 1, 1, &genesis_root, 0x62);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);

    LanternState block_one_state;
    build_cached_state(
        &block_one_state,
        &genesis_state,
        &block_one,
        &block_one_cp,
        &genesis_cp,
        0x30);
    assert(
        lantern_fork_choice_add_block_with_state(
            &store,
            &block_one,
            NULL,
            &genesis_cp,
            &genesis_cp,
            &block_one_root,
            &block_one_state)
        == 0);

    LanternBlock block_two;
    init_block(&block_two, 2, 2, &block_one_root, 0x63);
    LanternRoot block_two_root;
    assert(lantern_hash_tree_root_block(&block_two, &block_two_root) == 0);
    LanternCheckpoint block_two_cp = make_checkpoint(&block_two_root, block_two.slot);

    LanternState block_two_state;
    build_cached_state(
        &block_two_state,
        &block_one_state,
        &block_two,
        &block_two_cp,
        &genesis_cp,
        0x40);
    assert(
        lantern_fork_choice_add_block_with_state(
            &store,
            &block_two,
            NULL,
            &genesis_cp,
            &genesis_cp,
            &block_two_root,
            &block_two_state)
        == 0);

    LanternBlock block_three;
    init_block(&block_three, 3, 0, &block_two_root, 0x64);
    LanternRoot block_three_root;
    assert(lantern_hash_tree_root_block(&block_three, &block_three_root) == 0);
    LanternCheckpoint block_three_cp = make_checkpoint(&block_three_root, block_three.slot);

    LanternState block_three_state;
    build_cached_state(
        &block_three_state,
        &block_two_state,
        &block_three,
        &block_three_cp,
        &genesis_cp,
        0x50);
    assert(
        lantern_fork_choice_add_block_with_state(
            &store,
            &block_three,
            NULL,
            &genesis_cp,
            &genesis_cp,
            &block_three_root,
            &block_three_state)
        == 0);

    LanternBlock fork_two;
    init_block(&fork_two, 2, 0, &block_one_root, 0x65);
    LanternRoot fork_two_root;
    assert(lantern_hash_tree_root_block(&fork_two, &fork_two_root) == 0);

    LanternState fork_two_state;
    build_cached_state(
        &fork_two_state,
        &block_one_state,
        &fork_two,
        &block_one_cp,
        &genesis_cp,
        0x60);
    assert(
        lantern_fork_choice_add_block_with_state(
            &store,
            &fork_two,
            NULL,
            &genesis_cp,
            &genesis_cp,
            &fork_two_root,
            &fork_two_state)
        == 0);

    LanternSignedVote vote0 = make_vote(0, &genesis_cp, &block_three_cp);
    LanternSignedVote vote1 = make_vote(1, &genesis_cp, &block_three_cp);
    LanternSignedVote vote2 = make_vote(2, &genesis_cp, &block_three_cp);
    assert(seed_known_payload(&backing_store, &vote0, 0x71) == 0);
    assert(seed_known_payload(&backing_store, &vote1, 0x72) == 0);
    assert(seed_known_payload(&backing_store, &vote2, 0x73) == 0);
    assert(lantern_fork_choice_accept_new_aggregated_payloads(&store) == 0);

    LanternRoot head;
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_three_root));

    assert(lantern_fork_choice_update_checkpoints(&store, &block_three_cp, &block_two_cp) == 0);
    assert(lantern_fork_choice_prune_states(&store) == 0);

    size_t genesis_index = find_block_index(&store, &genesis_root);
    size_t block_one_index = find_block_index(&store, &block_one_root);
    size_t block_two_index = find_block_index(&store, &block_two_root);
    size_t block_three_index = find_block_index(&store, &block_three_root);
    size_t fork_two_index = find_block_index(&store, &fork_two_root);
    assert(genesis_index == SIZE_MAX);
    assert(block_one_index == SIZE_MAX);
    assert(block_two_index != SIZE_MAX);
    assert(block_three_index != SIZE_MAX);
    assert(fork_two_index == SIZE_MAX);
    assert(store.block_len == 2u);
    assert(store.blocks[block_two_index].parent_index == SIZE_MAX);
    assert(store.blocks[block_three_index].parent_index == block_two_index);
    assert(roots_equal(lantern_fork_choice_anchor_root(&store), &block_two_root));
    uint64_t anchor_slot = 0;
    assert(lantern_fork_choice_anchor_slot(&store, &anchor_slot) == 0);
    assert(anchor_slot == block_two.slot);

    assert(lantern_fork_choice_block_state(&store, &genesis_root) == NULL);
    assert(lantern_fork_choice_block_state(&store, &block_one_root) == NULL);
    assert(lantern_fork_choice_block_state(&store, &fork_two_root) == NULL);
    assert(lantern_fork_choice_block_state(&store, &block_two_root) != NULL);
    assert(lantern_fork_choice_block_state(&store, &block_three_root) != NULL);

    assert(store.states[block_two_index].has_state);
    assert(store.states[block_two_index].state.validators != NULL);
    assert(store.states[block_two_index].state.historical_block_hashes.items != NULL);
    assert(store.states[block_three_index].has_state);
    assert(store.states[block_three_index].state.validators != NULL);
    assert(store.states[block_three_index].state.historical_block_hashes.items != NULL);

    lantern_state_reset(&fork_two_state);
    lantern_state_reset(&block_three_state);
    lantern_state_reset(&block_two_state);
    lantern_state_reset(&block_one_state);
    lantern_state_reset(&genesis_state);
    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&fork_two);
    reset_block(&block_three);
    reset_block(&block_two);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_vote_flow(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 4, .genesis_time = 1};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x10);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternRoot head;
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &genesis_root));

    LanternBlock block_one;
    init_block(&block_one, 1, 0, &genesis_root, 0x21);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_one,
            NULL,
            NULL,
            NULL,
            &block_one_root)
        == 0);

    LanternBlock block_two;
    init_block(&block_two, 2, 1, &block_one_root, 0x32);
    LanternRoot block_two_root;
    assert(lantern_hash_tree_root_block(&block_two, &block_two_root) == 0);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_two,
            NULL,
            NULL,
            NULL,
            &block_two_root)
        == 0);

    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    LanternSignedVote vote0 = make_vote(0, &genesis_cp, &block_one_cp);

    assert(seed_known_payload(&backing_store, &vote0, 0x81) == 0);

    LanternSignedVote vote1 = make_vote(1, &genesis_cp, &block_one_cp);
    assert(seed_known_payload(&backing_store, &vote1, 0x82) == 0);

    assert(lantern_fork_choice_accept_new_aggregated_payloads(&store) == 0);
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_two_root));

    const LanternRoot *safe_initial = lantern_fork_choice_safe_target(&store);
    assert(safe_initial != NULL);

    LanternCheckpoint block_two_cp = make_checkpoint(&block_two_root, block_two.slot);
    LanternSignedVote vote2 = make_vote(0, &genesis_cp, &block_two_cp);
    LanternSignedVote vote3 = make_vote(1, &genesis_cp, &block_two_cp);
    LanternSignedVote vote4 = make_vote(2, &genesis_cp, &block_two_cp);

    assert(seed_new_payload(&backing_store, &vote2, 0x83) == 0);
    assert(seed_new_payload(&backing_store, &vote3, 0x84) == 0);

    assert(lantern_fork_choice_update_safe_target(&store) == 0);
    const LanternRoot *safe_after_two = lantern_fork_choice_safe_target(&store);
    assert(safe_after_two != NULL);
    assert(roots_equal(safe_after_two, safe_initial));

    assert(seed_new_payload(&backing_store, &vote4, 0x85) == 0);
    assert(lantern_fork_choice_update_safe_target(&store) == 0);
    const LanternRoot *safe_after_three = lantern_fork_choice_safe_target(&store);
    assert(safe_after_three != NULL);
    assert(roots_equal(safe_after_three, &block_two_root));

    assert(lantern_store_promote_new_aggregated_payloads(&backing_store) == 3u);
    assert(lantern_fork_choice_accept_new_aggregated_payloads(&store) == 0);
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_two_root));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_two);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_safe_target_uses_new_aggregated_payloads(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 3, .genesis_time = 25};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x41);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock block_one;
    init_block(&block_one, 1, 0, &genesis_root, 0x42);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_one,
            NULL,
            NULL,
            NULL,
            &block_one_root)
        == 0);

    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    LanternSignedVote known_vote = make_vote(0, &genesis_cp, &block_one_cp);
    assert(seed_known_payload(&backing_store, &known_vote, 0x42) == 0);

    LanternSignedVote new_vote = make_vote(1, &genesis_cp, &block_one_cp);
    assert(seed_new_payload(&backing_store, &new_vote, 0x43) == 0);

    assert(lantern_fork_choice_update_safe_target(&store) == 0);
    const LanternRoot *safe_target = lantern_fork_choice_safe_target(&store);
    assert(safe_target && roots_equal(safe_target, &genesis_root));

    LanternSignedVote live_vote = make_vote(2, &genesis_cp, &block_one_cp);
    assert(seed_new_payload(&backing_store, &live_vote, 0x44) == 0);

    assert(lantern_fork_choice_update_safe_target(&store) == 0);
    safe_target = lantern_fork_choice_safe_target(&store);
    assert(safe_target && roots_equal(safe_target, &block_one_root));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_checkpoint_progression(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 4, .genesis_time = 1};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x10);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    const LanternCheckpoint *initial_justified = lantern_fork_choice_latest_justified(&store);
    const LanternCheckpoint *initial_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(initial_justified && roots_equal(&initial_justified->root, &genesis_root));
    assert(initial_finalized && roots_equal(&initial_finalized->root, &genesis_root));

    LanternBlock block_one;
    init_block(&block_one, 1, 0, &genesis_root, 0x21);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_one,
            NULL,
            NULL,
            NULL,
            &block_one_root)
        == 0);

    assert(lantern_fork_choice_update_checkpoints(&store, &block_one_cp, NULL) == 0);
    const LanternCheckpoint *latest_justified = lantern_fork_choice_latest_justified(&store);
    assert(latest_justified);
    assert(latest_justified->slot == block_one.slot);
    assert(roots_equal(&latest_justified->root, &block_one_root));

    const LanternCheckpoint *latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(latest_finalized);
    assert(latest_finalized->slot == genesis.slot);
    assert(roots_equal(&latest_finalized->root, &genesis_root));

    LanternRoot unknown_root;
    memset(&unknown_root, 0xEE, sizeof(unknown_root));
    LanternCheckpoint unknown_cp = make_checkpoint(&unknown_root, block_one.slot + 1u);
    assert(lantern_fork_choice_update_checkpoints(&store, &unknown_cp, &unknown_cp) != 0);
    latest_justified = lantern_fork_choice_latest_justified(&store);
    latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(latest_justified);
    assert(latest_finalized);
    assert(latest_justified->slot == block_one.slot);
    assert(roots_equal(&latest_justified->root, &block_one_root));
    assert(latest_finalized->slot == genesis.slot);
    assert(roots_equal(&latest_finalized->root, &genesis_root));

    /* Regressing to older checkpoints must not overwrite progress */
    assert(lantern_fork_choice_update_checkpoints(&store, &genesis_cp, &genesis_cp) == 0);
    latest_justified = lantern_fork_choice_latest_justified(&store);
    assert(latest_justified->slot == block_one.slot);
    assert(roots_equal(&latest_justified->root, &block_one_root));

    assert(lantern_fork_choice_update_checkpoints(&store, &block_one_cp, &block_one_cp) == 0);
    latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(latest_finalized);
    assert(latest_finalized->slot == block_one.slot);
    assert(roots_equal(&latest_finalized->root, &block_one_root));

    LanternRoot head;
    assert(lantern_fork_choice_recompute_head(&store) == 0);
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_one_root));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_restore_checkpoints(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 4, .genesis_time = 1};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x41);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock block_one;
    init_block(&block_one, 1, 0, &genesis_root, 0x42);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_one,
            NULL,
            NULL,
            NULL,
            &block_one_root)
        == 0);

    LanternBlock block_two;
    init_block(&block_two, 2, 1, &block_one_root, 0x43);
    LanternRoot block_two_root;
    assert(lantern_hash_tree_root_block(&block_two, &block_two_root) == 0);
    LanternCheckpoint block_two_cp = make_checkpoint(&block_two_root, block_two.slot);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_two,
            NULL,
            NULL,
            NULL,
            &block_two_root)
        == 0);

    assert(lantern_fork_choice_update_checkpoints(&store, &block_two_cp, &block_one_cp) == 0);
    const LanternCheckpoint *latest_justified = lantern_fork_choice_latest_justified(&store);
    const LanternCheckpoint *latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(latest_justified && checkpoints_equal(latest_justified, &block_two_cp));
    assert(latest_finalized && checkpoints_equal(latest_finalized, &block_one_cp));

    assert(lantern_fork_choice_restore_checkpoints(&store, &block_one_cp, &genesis_cp) == 0);
    latest_justified = lantern_fork_choice_latest_justified(&store);
    latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(latest_justified && checkpoints_equal(latest_justified, &block_one_cp));
    assert(latest_finalized && checkpoints_equal(latest_finalized, &genesis_cp));

    LanternRoot head_before_failure;
    assert(lantern_fork_choice_current_head(&store, &head_before_failure) == 0);

    LanternCheckpoint unknown_cp = block_one_cp;
    fill_root(&unknown_cp.root, 0xEE);
    assert(lantern_fork_choice_restore_checkpoints(&store, &unknown_cp, &genesis_cp) != 0);

    const LanternCheckpoint *justified_after_restore =
        lantern_fork_choice_latest_justified(&store);
    const LanternCheckpoint *finalized_after_restore =
        lantern_fork_choice_latest_finalized(&store);
    assert(justified_after_restore && checkpoints_equal(justified_after_restore, &block_one_cp));
    assert(finalized_after_restore && checkpoints_equal(finalized_after_restore, &genesis_cp));

    LanternRoot head_after_restore;
    assert(lantern_fork_choice_current_head(&store, &head_after_restore) == 0);
    assert(roots_equal(&head_after_restore, &head_before_failure));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_two);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_anchor_metadata_survives_checkpoint_restore(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 4, .genesis_time = 1};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock anchor;
    init_block(&anchor, 8, 0, NULL, 0x51);
    LanternRoot anchor_root;
    assert(lantern_hash_tree_root_block(&anchor, &anchor_root) == 0);
    LanternCheckpoint anchor_cp = make_checkpoint(&anchor_root, anchor.slot);
    assert(lantern_fork_choice_set_anchor(&store, &anchor, &anchor_cp, &anchor_cp, &anchor_root) == 0);

    const LanternRoot *stored_anchor_root = lantern_fork_choice_anchor_root(&store);
    uint64_t stored_anchor_slot = 0;
    assert(stored_anchor_root);
    assert(roots_equal(stored_anchor_root, &anchor_root));
    assert(lantern_fork_choice_anchor_slot(&store, &stored_anchor_slot) == 0);
    assert(stored_anchor_slot == anchor.slot);

    LanternCheckpoint anchor_bootstrap_justified = anchor_cp;
    LanternCheckpoint anchor_bootstrap_finalized = anchor_cp;
    anchor_bootstrap_justified.slot = anchor.slot - 1u;
    anchor_bootstrap_finalized.slot = anchor.slot - 2u;
    assert(
        lantern_fork_choice_restore_checkpoints(
            &store,
            &anchor_bootstrap_justified,
            &anchor_bootstrap_finalized)
        == 0);
    const LanternCheckpoint *latest_justified = lantern_fork_choice_latest_justified(&store);
    const LanternCheckpoint *latest_finalized = lantern_fork_choice_latest_finalized(&store);
    assert(latest_justified);
    assert(latest_finalized);
    assert(latest_justified->slot == anchor_bootstrap_justified.slot);
    assert(latest_finalized->slot == anchor_bootstrap_finalized.slot);
    assert(roots_equal(&latest_justified->root, &anchor_root));
    assert(roots_equal(&latest_finalized->root, &anchor_root));

    LanternBlock block_one;
    init_block(&block_one, anchor.slot + 1u, 1, &anchor_root, 0x52);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_one,
            NULL,
            NULL,
            NULL,
            &block_one_root)
        == 0);

    assert(lantern_fork_choice_restore_checkpoints(&store, &block_one_cp, &anchor_cp) == 0);

    stored_anchor_root = lantern_fork_choice_anchor_root(&store);
    stored_anchor_slot = 0;
    assert(stored_anchor_root);
    assert(roots_equal(stored_anchor_root, &anchor_root));
    assert(lantern_fork_choice_anchor_slot(&store, &stored_anchor_slot) == 0);
    assert(stored_anchor_slot == anchor.slot);

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    assert(lantern_fork_choice_anchor_root(&store) == NULL);
    assert(lantern_fork_choice_anchor_slot(&store, &stored_anchor_slot) != 0);

    reset_block(&block_one);
    reset_block(&anchor);
    return 0;
}

static int test_fork_choice_restore_checkpoints_rejects_unknown_roots(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 4, .genesis_time = 1};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock anchor;
    init_block(&anchor, 8, 0, NULL, 0x61);
    LanternRoot anchor_root;
    assert(lantern_hash_tree_root_block(&anchor, &anchor_root) == 0);
    LanternCheckpoint anchor_cp = make_checkpoint(&anchor_root, anchor.slot);
    assert(lantern_fork_choice_set_anchor(&store, &anchor, &anchor_cp, &anchor_cp, &anchor_root) == 0);

    LanternCheckpoint latest_justified = anchor_cp;
    LanternCheckpoint latest_finalized = anchor_cp;
    latest_justified.slot = 5u;
    fill_root(&latest_justified.root, 0xA5);
    latest_finalized.slot = 4u;
    fill_root(&latest_finalized.root, 0xB4);

    assert(lantern_fork_choice_restore_checkpoints(
               &store,
               &latest_justified,
               &latest_finalized)
           != 0);

    const LanternCheckpoint *restored_latest_justified =
        lantern_fork_choice_latest_justified(&store);
    const LanternCheckpoint *restored_latest_finalized =
        lantern_fork_choice_latest_finalized(&store);

    assert(restored_latest_justified);
    assert(restored_latest_finalized);

    assert(checkpoints_equal(restored_latest_justified, &anchor_cp));
    assert(checkpoints_equal(restored_latest_finalized, &anchor_cp));

    LanternRoot head_root;
    assert(lantern_fork_choice_current_head(&store, &head_root) == 0);
    assert(roots_equal(&head_root, &anchor_root));

    struct lantern_fork_choice_tree_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    assert(lantern_fork_choice_snapshot_tree(&store, &snapshot) == 0);
    assert(snapshot.node_count == 1u);
    assert(checkpoints_equal(&snapshot.justified, &anchor_cp));
    assert(checkpoints_equal(&snapshot.finalized, &anchor_cp));
    lantern_fork_choice_tree_snapshot_reset(&snapshot);

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&anchor);
    return 0;
}

static int test_fork_choice_advance_time_schedules_votes(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 4, .genesis_time = 1};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x01);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock block_voted;
    init_block(&block_voted, 1, 0, &genesis_root, 0x11);
    LanternRoot block_voted_root;
    assert(lantern_hash_tree_root_block(&block_voted, &block_voted_root) == 0);
    LanternCheckpoint block_voted_cp = make_checkpoint(&block_voted_root, block_voted.slot);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_voted,
            NULL,
            NULL,
            NULL,
            &block_voted_root)
        == 0);

    LanternBlock block_competing;
    init_block(&block_competing, 2, 1, &genesis_root, 0x22);
    LanternRoot block_competing_root;
    assert(lantern_hash_tree_root_block(&block_competing, &block_competing_root) == 0);
    assert(
        lantern_fork_choice_add_block(
            &store,
            &block_competing,
            NULL,
            NULL,
            NULL,
            &block_competing_root)
        == 0);

    LanternRoot head;
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_voted_root));

    LanternSignedVote vote0 = make_vote(0, &genesis_cp, &block_voted_cp);
    LanternSignedVote vote1 = make_vote(1, &genesis_cp, &block_voted_cp);
    LanternSignedVote vote2 = make_vote(2, &genesis_cp, &block_voted_cp);
    assert(seed_new_payload(&backing_store, &vote0, 0x31) == 0);
    assert(seed_new_payload(&backing_store, &vote1, 0x32) == 0);
    assert(seed_new_payload(&backing_store, &vote2, 0x33) == 0);

    const LanternRoot *safe_initial = lantern_fork_choice_safe_target(&store);
    assert(safe_initial && roots_equal(safe_initial, &genesis_root));

    uint64_t genesis_time_ms = config.genesis_time * 1000u;
    assert(lantern_fork_choice_advance_time(&store, genesis_time_ms + 2400u, false) == 0);
    const LanternRoot *safe_after = lantern_fork_choice_safe_target(&store);
    assert(safe_after && roots_equal(safe_after, &block_voted_root));

    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_voted_root));

    assert(lantern_fork_choice_advance_time(&store, genesis_time_ms + 3200u, false) == 0);
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_voted_root));

    const LanternRoot *safe_final = lantern_fork_choice_safe_target(&store);
    assert(safe_final && roots_equal(safe_final, &block_voted_root));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_competing);
    reset_block(&block_voted);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_add_block_ignores_invalid_proposer_vote(void) {
    LanternForkChoice store;
    LanternStore backing_store;
    lantern_fork_choice_init(&store);
    lantern_store_init(&backing_store);
    lantern_store_attach_fork_choice(&backing_store, &store);

    LanternConfig config = {.num_validators = 2, .genesis_time = 100};
    assert(lantern_fork_choice_configure(&store, &config) == 0);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x01);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock parent;
    init_block(&parent, 1, 0, &genesis_root, 0x02);
    LanternRoot parent_root;
    assert(lantern_hash_tree_root_block(&parent, &parent_root) == 0);

    LanternBlock child;
    init_block(&child, 2, 1, &parent_root, 0x03);
    LanternRoot child_root;
    assert(lantern_hash_tree_root_block(&child, &child_root) == 0);
    assert(lantern_fork_choice_add_block(&store, &child, NULL, NULL, NULL, &child_root) == 0);

    uint64_t child_slot = 0;
    bool child_has_parent = true;
    assert(lantern_fork_choice_block_info(&store, &child_root, &child_slot, NULL, &child_has_parent) == 0);
    assert(child_slot == 2);
    assert(child_has_parent == false);

    LanternSignedVote bad_proposer_vote;
    memset(&bad_proposer_vote, 0, sizeof(bad_proposer_vote));
    bad_proposer_vote.data.validator_id = 1; /* wrong proposer index */
    bad_proposer_vote.data.slot = parent.slot; /* correct slot */
    bad_proposer_vote.data.target = make_checkpoint(&parent_root, parent.slot);
    bad_proposer_vote.data.head = bad_proposer_vote.data.target;

    assert(lantern_fork_choice_add_block(&store, &parent, &bad_proposer_vote, NULL, NULL, &parent_root) == 0);

    uint64_t parent_slot = 0;
    bool parent_has_parent = true;
    assert(lantern_fork_choice_block_info(&store, &parent_root, &parent_slot, NULL, &parent_has_parent) == 0);
    assert(parent_slot == parent.slot);
    assert(parent_has_parent == true);

    assert(lantern_fork_choice_block_info(&store, &child_root, &child_slot, NULL, &child_has_parent) == 0);
    assert(child_has_parent == true);

    LanternRoot head;
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &child_root));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&child);
    reset_block(&parent);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_add_block_skips_conflicting_block_attestation(void) {
    LanternForkChoice store;
    LanternStore backing_store;
    LanternConfig config = {.num_validators = 1, .genesis_time = 120};
    LanternBlock genesis;
    LanternBlock block_one;
    LanternBlock block_two_a;
    LanternBlock block_two_b;
    LanternBlock block_three;
    LanternRoot genesis_root;
    LanternRoot block_one_root;
    LanternRoot block_two_a_root;
    LanternRoot block_two_b_root;
    LanternRoot block_three_root;
    LanternCheckpoint genesis_cp;
    LanternCheckpoint block_one_cp;
    LanternCheckpoint block_two_a_cp;
    LanternCheckpoint block_two_b_cp;
    LanternSignedVote known_vote;
    LanternAttestations votes;
    int rc = 1;

    memset(&store, 0, sizeof(store));
    memset(&backing_store, 0, sizeof(backing_store));
    memset(&genesis, 0, sizeof(genesis));
    memset(&block_one, 0, sizeof(block_one));
    memset(&block_two_a, 0, sizeof(block_two_a));
    memset(&block_two_b, 0, sizeof(block_two_b));
    memset(&block_three, 0, sizeof(block_three));
    memset(&genesis_root, 0, sizeof(genesis_root));
    memset(&block_one_root, 0, sizeof(block_one_root));
    memset(&block_two_a_root, 0, sizeof(block_two_a_root));
    memset(&block_two_b_root, 0, sizeof(block_two_b_root));
    memset(&block_three_root, 0, sizeof(block_three_root));
    lantern_attestations_init(&votes);
    lantern_store_init(&backing_store);
    lantern_fork_choice_init(&store);
    lantern_store_attach_fork_choice(&backing_store, &store);

    if (lantern_fork_choice_configure(&store, &config) != 0) {
        fprintf(stderr, "failed to configure fork choice conflict test\n");
        goto cleanup;
    }

    init_block(&genesis, 0, 0, NULL, 0x10);
    if (lantern_hash_tree_root_block(&genesis, &genesis_root) != 0) {
        fprintf(stderr, "failed to hash genesis block in conflict test\n");
        goto cleanup;
    }
    genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    if (lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) != 0) {
        fprintf(stderr, "failed to set anchor in conflict test\n");
        goto cleanup;
    }

    init_block(&block_one, 1, 0, &genesis_root, 0x11);
    if (lantern_hash_tree_root_block(&block_one, &block_one_root) != 0) {
        fprintf(stderr, "failed to hash block one in conflict test\n");
        goto cleanup;
    }
    block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    if (lantern_fork_choice_add_block(&store, &block_one, NULL, NULL, NULL, &block_one_root) != 0) {
        fprintf(stderr, "failed to add block one in conflict test\n");
        goto cleanup;
    }

    init_block(&block_two_a, 2, 0, &block_one_root, 0x12);
    if (lantern_hash_tree_root_block(&block_two_a, &block_two_a_root) != 0) {
        fprintf(stderr, "failed to hash block two A in conflict test\n");
        goto cleanup;
    }
    block_two_a_cp = make_checkpoint(&block_two_a_root, block_two_a.slot);
    if (lantern_fork_choice_add_block(&store, &block_two_a, NULL, NULL, NULL, &block_two_a_root) != 0) {
        fprintf(stderr, "failed to add block two A in conflict test\n");
        goto cleanup;
    }

    init_block(&block_two_b, 2, 0, &block_one_root, 0x13);
    if (lantern_hash_tree_root_block(&block_two_b, &block_two_b_root) != 0) {
        fprintf(stderr, "failed to hash block two B in conflict test\n");
        goto cleanup;
    }
    block_two_b_cp = make_checkpoint(&block_two_b_root, block_two_b.slot);
    if (lantern_fork_choice_add_block(&store, &block_two_b, NULL, NULL, NULL, &block_two_b_root) != 0) {
        fprintf(stderr, "failed to add block two B in conflict test\n");
        goto cleanup;
    }

    known_vote = make_vote(0, &block_one_cp, &block_two_a_cp);
    if (seed_known_payload(&backing_store, &known_vote, 0x45) != 0) {
        fprintf(stderr, "failed to seed known payload in conflict test\n");
        goto cleanup;
    }
    if (backing_store.known_aggregated_payloads.length != 1u) {
        fprintf(stderr, "known payload seed mismatch in conflict test\n");
        goto cleanup;
    }

    init_block(&block_three, 3, 0, &block_two_a_root, 0x14);
    if (lantern_hash_tree_root_block(&block_three, &block_three_root) != 0) {
        fprintf(stderr, "failed to hash block three in conflict test\n");
        goto cleanup;
    }

    if (lantern_attestations_resize(&votes, 1u) != 0 || !votes.data) {
        fprintf(stderr, "failed to allocate conflicting attestation list\n");
        goto cleanup;
    }
    votes.data[0] = make_vote(0, &block_one_cp, &block_two_b_cp).data;
    if (lantern_wrap_attestations_as_aggregated(&votes, &block_three.body.attestations) != 0) {
        fprintf(stderr, "failed to build conflicting aggregated attestation\n");
        goto cleanup;
    }

    if (lantern_fork_choice_add_block(&store, &block_three, NULL, NULL, NULL, &block_three_root) != 0) {
        fprintf(stderr, "block import failed when conflicting block attestation should be skipped\n");
        goto cleanup;
    }
    if (backing_store.known_aggregated_payloads.length != 1u) {
        fprintf(stderr, "known payload pool changed after importing block attestation\n");
        goto cleanup;
    }
    if (lantern_fork_choice_block_info(&store, &block_three_root, NULL, NULL, NULL) != 0) {
        fprintf(stderr, "block missing after skipping conflicting block attestation\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_attestations_reset(&votes);
    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_three);
    reset_block(&block_two_b);
    reset_block(&block_two_a);
    reset_block(&block_one);
    reset_block(&genesis);
    return rc;
}

static int test_fork_choice_tree_snapshot_reports_weights(void) {
    LanternForkChoice store;
    LanternStore backing_store;
    lantern_fork_choice_init(&store);
    lantern_store_init(&backing_store);
    lantern_store_attach_fork_choice(&backing_store, &store);

    LanternConfig config = {.num_validators = 4, .genesis_time = 15};
    assert(lantern_fork_choice_configure(&store, &config) == 0);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x21);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock block_one;
    init_block(&block_one, 1, 1, &genesis_root, 0x22);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    assert(lantern_fork_choice_add_block(&store, &block_one, NULL, NULL, NULL, &block_one_root) == 0);

    LanternBlock block_two_a;
    init_block(&block_two_a, 2, 2, &block_one_root, 0x23);
    LanternRoot block_two_a_root;
    assert(lantern_hash_tree_root_block(&block_two_a, &block_two_a_root) == 0);
    LanternCheckpoint block_two_a_cp = make_checkpoint(&block_two_a_root, block_two_a.slot);
    assert(lantern_fork_choice_add_block(&store, &block_two_a, NULL, NULL, NULL, &block_two_a_root) == 0);

    LanternBlock block_two_b;
    init_block(&block_two_b, 2, 3, &block_one_root, 0x24);
    LanternRoot block_two_b_root;
    assert(lantern_hash_tree_root_block(&block_two_b, &block_two_b_root) == 0);
    LanternCheckpoint block_two_b_cp = make_checkpoint(&block_two_b_root, block_two_b.slot);
    assert(lantern_fork_choice_add_block(&store, &block_two_b, NULL, NULL, NULL, &block_two_b_root) == 0);

    LanternSignedVote vote0 = make_vote(0, &block_one_cp, &block_two_a_cp);
    LanternSignedVote vote1 = make_vote(1, &block_one_cp, &block_two_a_cp);
    LanternSignedVote vote2 = make_vote(2, &block_one_cp, &block_two_b_cp);
    assert(seed_known_payload(&backing_store, &vote0, 0x51) == 0);
    assert(seed_known_payload(&backing_store, &vote1, 0x61) == 0);
    assert(seed_known_payload(&backing_store, &vote2, 0x71) == 0);
    assert(lantern_fork_choice_accept_new_aggregated_payloads(&store) == 0);

    assert(lantern_fork_choice_update_checkpoints(&store, &block_one_cp, &block_one_cp) == 0);

    struct lantern_fork_choice_tree_snapshot snapshot;
    memset(&snapshot, 0, sizeof(snapshot));
    assert(lantern_fork_choice_snapshot_tree(&store, &snapshot) == 0);
    assert(snapshot.node_count == 3u);
    assert(roots_equal(&snapshot.head, &block_two_a_root));
    assert(checkpoints_equal(&snapshot.justified, &block_one_cp));
    assert(checkpoints_equal(&snapshot.finalized, &block_one_cp));

    const struct lantern_fork_choice_tree_node *block_one_node =
        find_tree_snapshot_node(&snapshot, &block_one_root);
    const struct lantern_fork_choice_tree_node *block_two_a_node =
        find_tree_snapshot_node(&snapshot, &block_two_a_root);
    const struct lantern_fork_choice_tree_node *block_two_b_node =
        find_tree_snapshot_node(&snapshot, &block_two_b_root);
    assert(block_one_node != NULL);
    assert(block_two_a_node != NULL);
    assert(block_two_b_node != NULL);

    assert(block_one_node->slot == 1u);
    assert(block_one_node->proposer_index == 1u);
    assert(block_one_node->weight == 0u);

    assert(block_two_a_node->slot == 2u);
    assert(block_two_a_node->proposer_index == 2u);
    assert(block_two_a_node->weight == 2u);
    assert(roots_equal(&block_two_a_node->parent_root, &block_one_root));

    assert(block_two_b_node->slot == 2u);
    assert(block_two_b_node->proposer_index == 3u);
    assert(block_two_b_node->weight == 1u);
    assert(roots_equal(&block_two_b_node->parent_root, &block_one_root));

    lantern_fork_choice_tree_snapshot_reset(&snapshot);
    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_two_b);
    reset_block(&block_two_a);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_block_attestation_votes_do_not_bypass_attached_payload_views(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 1, .genesis_time = 11};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0x91);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock block_one;
    init_block(&block_one, 1, 0, &genesis_root, 0x92);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    assert(lantern_fork_choice_add_block(&store, &block_one, NULL, NULL, NULL, &block_one_root) == 0);

    LanternBlock branch_a;
    init_block(&branch_a, 2, 0, &block_one_root, 0x93);
    LanternRoot branch_a_root;
    assert(lantern_hash_tree_root_block(&branch_a, &branch_a_root) == 0);
    LanternCheckpoint branch_a_cp = make_checkpoint(&branch_a_root, branch_a.slot);

    LanternBlock branch_b;
    init_block(&branch_b, 2, 0, &block_one_root, 0x94);
    LanternRoot branch_b_root;
    assert(lantern_hash_tree_root_block(&branch_b, &branch_b_root) == 0);
    LanternCheckpoint branch_b_cp = make_checkpoint(&branch_b_root, branch_b.slot);

    LanternBlock *favored_branch = &branch_a;
    LanternBlock *voted_branch = &branch_b;
    LanternRoot favored_root = branch_a_root;
    LanternRoot voted_root = branch_b_root;
    LanternCheckpoint voted_cp = branch_b_cp;
    if (memcmp(branch_b_root.bytes, branch_a_root.bytes, LANTERN_ROOT_SIZE) > 0) {
        favored_branch = &branch_b;
        voted_branch = &branch_a;
        favored_root = branch_b_root;
        voted_root = branch_a_root;
        voted_cp = branch_a_cp;
    }

    assert(
        lantern_fork_choice_add_block(
            &store,
            favored_branch,
            NULL,
            NULL,
            NULL,
            &favored_root)
        == 0);

    LanternRoot head = {0};
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &favored_root));

    LanternAttestations votes;
    lantern_attestations_init(&votes);
    assert(lantern_attestations_resize(&votes, 1u) == 0);
    votes.data[0] = make_vote(0, &block_one_cp, &voted_cp).data;
    assert(lantern_wrap_attestations_as_aggregated(&votes, &voted_branch->body.attestations) == 0);

    assert(
        lantern_fork_choice_add_block(
            &store,
            voted_branch,
            NULL,
            NULL,
            NULL,
            &voted_root)
        == 0);
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &favored_root));

    lantern_attestations_reset(&votes);
    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&branch_b);
    reset_block(&branch_a);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

static int test_fork_choice_accept_new_aggregated_payloads_updates_head(void) {
    LanternForkChoice store;
    LanternStore backing_store;

    LanternConfig config = {.num_validators = 3, .genesis_time = 19};
    configure_fork_choice_with_backing_store(&store, &backing_store, &config);

    LanternBlock genesis;
    init_block(&genesis, 0, 0, NULL, 0xA1);
    LanternRoot genesis_root;
    assert(lantern_hash_tree_root_block(&genesis, &genesis_root) == 0);
    LanternCheckpoint genesis_cp = make_checkpoint(&genesis_root, genesis.slot);
    assert(lantern_fork_choice_set_anchor(&store, &genesis, &genesis_cp, &genesis_cp, &genesis_root) == 0);

    LanternBlock block_one;
    init_block(&block_one, 1, 0, &genesis_root, 0xA2);
    LanternRoot block_one_root;
    assert(lantern_hash_tree_root_block(&block_one, &block_one_root) == 0);
    LanternCheckpoint block_one_cp = make_checkpoint(&block_one_root, block_one.slot);
    assert(lantern_fork_choice_add_block(&store, &block_one, NULL, NULL, NULL, &block_one_root) == 0);

    LanternBlock block_two_a;
    init_block(&block_two_a, 2, 1, &block_one_root, 0xA3);
    LanternRoot block_two_a_root;
    assert(lantern_hash_tree_root_block(&block_two_a, &block_two_a_root) == 0);
    LanternCheckpoint block_two_a_cp = make_checkpoint(&block_two_a_root, block_two_a.slot);
    assert(lantern_fork_choice_add_block(&store, &block_two_a, NULL, NULL, NULL, &block_two_a_root) == 0);

    LanternBlock block_two_b;
    init_block(&block_two_b, 2, 2, &block_one_root, 0xA4);
    LanternRoot block_two_b_root;
    assert(lantern_hash_tree_root_block(&block_two_b, &block_two_b_root) == 0);
    LanternCheckpoint block_two_b_cp = make_checkpoint(&block_two_b_root, block_two_b.slot);
    assert(lantern_fork_choice_add_block(&store, &block_two_b, NULL, NULL, NULL, &block_two_b_root) == 0);

    LanternSignedVote known_vote = make_vote(0, &block_one_cp, &block_two_a_cp);
    LanternSignedVote new_vote_one = make_vote(1, &block_one_cp, &block_two_b_cp);
    LanternSignedVote new_vote_two = make_vote(2, &block_one_cp, &block_two_b_cp);
    assert(seed_known_payload(&backing_store, &known_vote, 0x31) == 0);
    assert(seed_new_payload(&backing_store, &new_vote_one, 0x41) == 0);
    assert(seed_new_payload(&backing_store, &new_vote_two, 0x51) == 0);

    LanternRoot head = {0};
    assert(lantern_store_promote_new_aggregated_payloads(&backing_store) == 2u);
    assert(lantern_fork_choice_accept_new_aggregated_payloads(&store) == 0);
    assert(lantern_fork_choice_current_head(&store, &head) == 0);
    assert(roots_equal(&head, &block_two_b_root));

    lantern_store_reset(&backing_store);
    lantern_fork_choice_reset(&store);
    reset_block(&block_two_b);
    reset_block(&block_two_a);
    reset_block(&block_one);
    reset_block(&genesis);
    return 0;
}

int main(void) {
    if (test_fork_choice_proposer_attestation_sequence() != 0) {
        return 1;
    }
    if (test_fork_choice_block_updates_checkpoints() != 0) {
        return 1;
    }
    if (test_fork_choice_caches_block_states() != 0) {
        return 1;
    }
    if (test_fork_choice_prune_states_keeps_finalized_to_head_chain() != 0) {
        return 1;
    }
    if (test_fork_choice_vote_flow() != 0) {
        return 1;
    }
    if (test_fork_choice_safe_target_uses_new_aggregated_payloads() != 0) {
        return 1;
    }
    if (test_fork_choice_checkpoint_progression() != 0) {
        return 1;
    }
    if (test_fork_choice_restore_checkpoints() != 0) {
        return 1;
    }
    if (test_fork_choice_anchor_metadata_survives_checkpoint_restore() != 0) {
        return 1;
    }
    if (test_fork_choice_restore_checkpoints_rejects_unknown_roots() != 0) {
        return 1;
    }
    if (test_fork_choice_advance_time_schedules_votes() != 0) {
        return 1;
    }
    if (test_fork_choice_add_block_ignores_invalid_proposer_vote() != 0) {
        return 1;
    }
    if (test_fork_choice_add_block_skips_conflicting_block_attestation() != 0) {
        return 1;
    }
    if (test_fork_choice_tree_snapshot_reports_weights() != 0) {
        return 1;
    }
    if (test_fork_choice_block_attestation_votes_do_not_bypass_attached_payload_views() != 0) {
        return 1;
    }
    if (test_fork_choice_accept_new_aggregated_payloads_updates_head() != 0) {
        return 1;
    }
    return 0;
}
