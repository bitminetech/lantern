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
    return 0;
}
