#include <stdio.h>
#include <string.h>

#include "lantern/core/client.h"

static int test_idle_gossip_not_ignored(void)
{
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.node_id = "test_idle_gossip";
    client.sync_state = LANTERN_SYNC_STATE_IDLE;

    LanternSignedBlock block;
    memset(&block, 0, sizeof(block));
    lantern_block_body_init(&block.message.body);
    block.message.slot = 1;

    int block_rc = lantern_client_debug_gossip_block(&client, &block);
    lantern_block_body_reset(&block.message.body);
    if (block_rc != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "idle block gossip was not accepted rc=%d\n", block_rc);
        return 1;
    }

    LanternSignedVote vote;
    memset(&vote, 0, sizeof(vote));
    vote.data.validator_id = 0;
    vote.data.slot = 1;

    int vote_rc = lantern_client_debug_gossip_vote(&client, &vote);
    if (vote_rc != LANTERN_CLIENT_OK)
    {
        fprintf(stderr, "idle vote gossip was not accepted rc=%d\n", vote_rc);
        return 1;
    }

    return 0;
}

int main(void)
{
    if (test_idle_gossip_not_ignored() != 0)
    {
        return 1;
    }

    puts("lantern_client_gossip_test OK");
    return 0;
}
