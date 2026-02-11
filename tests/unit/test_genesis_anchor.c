#include <inttypes.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "lantern/consensus/hash.h"
#include "lantern/consensus/state.h"
#include "lantern/core/client.h"

#include "../../src/core/client_sync_internal.h"

static void fill_pubkeys(uint8_t *pubkeys, size_t count)
{
    if (!pubkeys)
    {
        return;
    }
    for (size_t i = 0; i < count; ++i)
    {
        for (size_t j = 0; j < LANTERN_VALIDATOR_PUBKEY_SIZE; ++j)
        {
            pubkeys[(i * LANTERN_VALIDATOR_PUBKEY_SIZE) + j] = (uint8_t)(((i + 1u) * 31u) + j);
        }
    }
}

static int roots_equal(const LanternRoot *left, const LanternRoot *right)
{
    if (!left || !right)
    {
        return 0;
    }
    return memcmp(left->bytes, right->bytes, LANTERN_ROOT_SIZE) == 0;
}

static void fill_root(LanternRoot *root, uint8_t value)
{
    if (!root)
    {
        return;
    }
    memset(root->bytes, value, LANTERN_ROOT_SIZE);
}

int main(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "genesis_anchor_regression";
    client.has_state = true;
    lantern_state_init(&client.state);

    if (lantern_state_generate_genesis(&client.state, UINT64_C(1761717362), 3u) != 0)
    {
        fprintf(stderr, "failed to generate genesis state\n");
        return 1;
    }

    uint8_t pubkeys[3u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    fill_pubkeys(pubkeys, 3u);
    if (lantern_state_set_validator_pubkeys(&client.state, pubkeys, 3u) != 0)
    {
        fprintf(stderr, "failed to set validator pubkeys\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    LanternRoot canonical_state_root;
    if (lantern_hash_tree_root_state(&client.state, &canonical_state_root) != 0)
    {
        fprintf(stderr, "failed to hash canonical genesis state\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    LanternBlockHeader expected_anchor_header = client.state.latest_block_header;
    expected_anchor_header.state_root = canonical_state_root;

    LanternRoot expected_anchor_root;
    if (lantern_hash_tree_root_block_header(&expected_anchor_header, &expected_anchor_root) != 0)
    {
        fprintf(stderr, "failed to hash expected anchor header\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    /*
     * Simulate previously persisted bootstrap snapshots where genesis header
     * state_root was eagerly populated before restart.
     */
    client.state.latest_block_header.state_root = canonical_state_root;

    if (initialize_fork_choice(&client) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "initialize_fork_choice failed\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    LanternRoot actual_head;
    if (lantern_fork_choice_current_head(&client.fork_choice, &actual_head) != 0)
    {
        fprintf(stderr, "failed to read fork choice head\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    if (!roots_equal(&actual_head, &expected_anchor_root))
    {
        fprintf(stderr, "fork choice anchor mismatch for persisted genesis snapshot\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    if (!roots_equal(&client.state.latest_block_header.state_root, &canonical_state_root))
    {
        fprintf(stderr, "initialize_fork_choice unexpectedly rewrote genesis header state_root\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    lantern_state_reset(&client.state);
    lantern_fork_choice_reset(&client.fork_choice);

    /*
     * Restart regression: initialize_fork_choice must preserve persisted
     * justified/finalized checkpoints for non-genesis snapshots.
     */
    memset(&client, 0, sizeof(client));
    client.node_id = "fork_choice_checkpoint_restore";
    client.has_state = true;
    lantern_state_init(&client.state);

    if (lantern_state_generate_genesis(&client.state, UINT64_C(1761717362), 4u) != 0)
    {
        fprintf(stderr, "failed to generate restart regression state\n");
        return 1;
    }

    uint8_t restart_pubkeys[4u * LANTERN_VALIDATOR_PUBKEY_SIZE];
    fill_pubkeys(restart_pubkeys, 4u);
    if (lantern_state_set_validator_pubkeys(&client.state, restart_pubkeys, 4u) != 0)
    {
        fprintf(stderr, "failed to set validator pubkeys for restart regression\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    client.state.slot = 447u;
    client.state.latest_block_header.slot = 443u;
    client.state.latest_block_header.proposer_index = 1u;
    fill_root(&client.state.latest_block_header.parent_root, 0x55u);

    LanternCheckpoint expected_justified;
    LanternCheckpoint expected_finalized;
    fill_root(&expected_justified.root, 0x39u);
    expected_justified.slot = 439u;
    fill_root(&expected_finalized.root, 0x34u);
    expected_finalized.slot = 434u;
    client.state.latest_justified = expected_justified;
    client.state.latest_finalized = expected_finalized;

    LanternRoot restart_state_root;
    if (lantern_hash_tree_root_state(&client.state, &restart_state_root) != 0)
    {
        fprintf(stderr, "failed to hash restart regression state\n");
        lantern_state_reset(&client.state);
        return 1;
    }
    LanternBlockHeader restart_anchor_header = client.state.latest_block_header;
    restart_anchor_header.state_root = restart_state_root;
    LanternRoot expected_restart_anchor_root;
    if (lantern_hash_tree_root_block_header(&restart_anchor_header, &expected_restart_anchor_root) != 0)
    {
        fprintf(stderr, "failed to hash restart regression anchor header\n");
        lantern_state_reset(&client.state);
        return 1;
    }

    if (initialize_fork_choice(&client) != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "initialize_fork_choice failed for restart regression\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    LanternRoot restart_head;
    if (lantern_fork_choice_current_head(&client.fork_choice, &restart_head) != 0)
    {
        fprintf(stderr, "failed to read restart regression fork choice head\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (!roots_equal(&restart_head, &expected_restart_anchor_root))
    {
        fprintf(stderr, "restart regression head mismatch\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    /*
     * After initialize_fork_choice the store checkpoints match the anchor
     * (not the persisted state checkpoints).  Real persisted checkpoints are
     * synced later by restore_persisted_blocks → restore_checkpoints.
     */
    const LanternCheckpoint *store_justified =
        lantern_fork_choice_latest_justified(&client.fork_choice);
    const LanternCheckpoint *store_finalized =
        lantern_fork_choice_latest_finalized(&client.fork_choice);
    if (!store_justified || !store_finalized)
    {
        fprintf(stderr, "missing fork-choice checkpoints after restart init\n");
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (store_justified->slot != restart_anchor_header.slot
        || !roots_equal(&store_justified->root, &expected_restart_anchor_root))
    {
        fprintf(stderr,
            "justified checkpoint should match anchor after init "
            "(got slot=%" PRIu64 " expected slot=%" PRIu64 ")\n",
            store_justified->slot, (uint64_t)restart_anchor_header.slot);
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }
    if (store_finalized->slot != restart_anchor_header.slot
        || !roots_equal(&store_finalized->root, &expected_restart_anchor_root))
    {
        fprintf(stderr,
            "finalized checkpoint should match anchor after init "
            "(got slot=%" PRIu64 " expected slot=%" PRIu64 ")\n",
            store_finalized->slot, (uint64_t)restart_anchor_header.slot);
        lantern_state_reset(&client.state);
        lantern_fork_choice_reset(&client.fork_choice);
        return 1;
    }

    lantern_state_reset(&client.state);
    lantern_fork_choice_reset(&client.fork_choice);
    return 0;
}
