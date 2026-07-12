#include "../../src/core/client_network_internal.h"

#include "lantern/core/client.h"
#include "lantern/networking/enr.h"
#include "lantern/networking/libp2p.h"
#include "lantern/support/string_list.h"

#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static const uint8_t kHostSecret[32] = {
    0xb7, 0x1c, 0x71, 0xa6, 0x7e, 0x11, 0x77, 0xad,
    0x4e, 0x90, 0x16, 0x95, 0xe1, 0xb4, 0xb9, 0xee,
    0x17, 0xae, 0x16, 0xc6, 0x66, 0x8d, 0x31, 0x3e,
    0xac, 0x2f, 0x96, 0xdb, 0xcd, 0xa3, 0xf2, 0x91,
};

static const char *kQuicOnlyEnr =
    "enr:-IW4QKbT-CoCAKBpbYNfzfFcPfYjkqHyH-5sFlVkaKlNEPN1M5M34vIYb8HyCg56m7-V13pKWZqH9ThdYtXjjavDrP4BgmlkgnY0"
    "gmlwhKwUAAqEcXVpY4IjKIlzZWNwMjU2azGhAuIbyETf2xNYGNJfCPhn95r0lyyoRpB5PCWwh53RSSgS";

static const char *kQuickstartGenesisEnrs[] = {
    "enr:-IW4QGGifTt9ypyMtChDISUNX3z4z5iPdiEPOmBoILvnDuWIKbWVmKXxZERPnw0piQyaBNCENFEPoIi-vxsnsrBig9MBgmlkgnY0"
    "gmlwhH8AAAGEcXVpY4IjKYlzZWNwMjU2azGhAhMMnGF1rmIPQ9tWgqfkNmvsG-aIyc9EJU5JFo3Tegys",
    "enr:-IW4QNQN_PFdTfuYLGmdAWNivEJLT2tSZtn5jdBOImvh0QlLAJ1p8wHvvfD7aOa1lH88oJ8ddGK_a_FWqAQT_QY4qdMBgmlkgnY0"
    "gmlwhH8AAAGEcXVpY4IjK4lzZWNwMjU2azGhA7NTxgfOmGE2EQa4HhsXxFOeHdTLYIc2MEBczymm9IUN",
    "enr:-IW4QJQOjnBJm0chbYlA2noeqKam0wtrysHXKQ09l8hDRaJVNNB28Uek24_Z61NSqG4oZwG-jWwijgl-KELuyhMRkVcBgmlkgnY0"
    "gmlwhH8AAAGEcXVpY4IjLIlzZWNwMjU2azGhArLG8gGy7-rMEg7OqV-r5BkWiIEk0fro2dSr5Idt1V5V",
    "enr:-IW4QI9EXVDvUIxTrCV51Gs2RtpmZu71S7ZP7RRg1OoSBVvGFeXkc5WleBffXwTcWX1Qa9F_N6MhH28TsGFhXkMCGvUBgmlkgnY0"
    "gmlwhH8AAAGEcXVpY4IjL4lzZWNwMjU2azGhA6Dm1X9PyyCNAm3RUGcZtG5U3imbj_MDPU5CtPnpeaKS",
};

static int validation_accepts_quickstart_enr(const char *encoded) {
    struct lantern_enr_record record;
    lantern_enr_record_init(&record);

    if (lantern_enr_record_decode(encoded, &record) != 0) {
        lantern_enr_record_reset(&record);
        return 1;
    }

    char multiaddr[256];
    struct lantern_peer_id peer_id;
    int rc = lantern_libp2p_enr_to_multiaddr(
        &record,
        multiaddr,
        sizeof(multiaddr),
        &peer_id);

    lantern_enr_record_reset(&record);

    return rc == 0 ? 0 : 1;
}

static int dial_starts_after_launch(void) {
    struct lantern_enr_record record;
    lantern_enr_record_init(&record);

    struct lantern_libp2p_host host;
    lantern_libp2p_host_init(&host);

    struct lantern_libp2p_config config = {
        .listen_multiaddr = "/ip4/127.0.0.1/udp/9310/quic-v1",
        .secp256k1_secret = kHostSecret,
        .secret_len = sizeof(kHostSecret),
        .allow_outbound_identify = 1,
    };

    if (lantern_enr_record_decode(kQuicOnlyEnr, &record) != 0) {
        lantern_enr_record_reset(&record);
        return 1;
    }

    if (lantern_libp2p_host_prepare(&host, &config) != 0
        || lantern_libp2p_host_launch(&host) != 0) {
        lantern_enr_record_reset(&record);
        lantern_libp2p_host_reset(&host);
        return 1;
    }

    char multiaddr[256];
    struct lantern_peer_id peer_id;
    if (lantern_libp2p_enr_to_multiaddr(&record, multiaddr, sizeof(multiaddr), &peer_id) != 0) {
        lantern_enr_record_reset(&record);
        lantern_libp2p_host_reset(&host);
        return 1;
    }

    int rc = lantern_libp2p_host_dial_multiaddr(&host, multiaddr);

    lantern_enr_record_reset(&record);
    lantern_libp2p_host_reset(&host);

    return rc == 0 ? 0 : 1;
}

static int connection_counter_keeps_peer_until_last_connection_closes(void) {
    static const char *peer_text = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";

    struct lantern_client client;
    memset(&client, 0, sizeof(client));

    if (pthread_mutex_init(&client.connection_lock, NULL) != 0) {
        return 1;
    }
    client.connection_lock_initialized = true;

    struct lantern_peer_id peer;
    if (lantern_peer_id_from_text(peer_text, &peer) != 0) {
        pthread_mutex_destroy(&client.connection_lock);
        return 1;
    }

    const void *conn1 = (const void *)0x1;
    const void *conn2 = (const void *)0x2;
    const void *unknown_conn = (const void *)0x3;

    connection_counter_update(&client, 1, conn1, &peer, true, LIBP2P_HOST_OK);
    connection_counter_update(&client, 1, conn2, &peer, false, LIBP2P_HOST_OK);
    int failed = !lantern_client_is_peer_connected(&client, peer_text)
        || client.connected_peers != 1u
        || client.connection_peer_ref_count != 2u;

    connection_counter_update(&client, -1, conn1, NULL, false, LIBP2P_HOST_OK);
    failed = failed || !lantern_client_is_peer_connected(&client, peer_text)
        || client.connected_peers != 1u
        || client.connection_peer_ref_count != 1u;

    connection_counter_update(&client, -1, unknown_conn, NULL, false, LIBP2P_HOST_OK);
    failed = failed || !lantern_client_is_peer_connected(&client, peer_text)
        || client.connected_peers != 1u
        || client.connection_peer_ref_count != 1u;

    connection_counter_update(&client, -1, conn2, NULL, false, LIBP2P_HOST_OK);
    failed = failed || lantern_client_is_peer_connected(&client, peer_text)
        || client.connected_peers != 0u
        || client.connection_peer_ref_count != 0u;

    pthread_mutex_destroy(&client.connection_lock);
    free(client.connection_peer_refs);

    return failed;
}

static int connection_tie_break_is_symmetric(void) {
    static const uint8_t low_local[] = {0x01};
    static const uint8_t high_local[] = {0x02};
    struct lantern_peer_id low_peer = {
        .bytes = {0x01},
        .len = 1,
    };
    struct lantern_peer_id high_peer = {
        .bytes = {0x02},
        .len = 1,
    };
    struct lantern_peer_id longer_peer = {
        .bytes = {0x01, 0x00},
        .len = 2,
    };

    int failed = 0;
    failed = failed || connection_tie_break_prefers_inbound(low_local, sizeof(low_local), &high_peer);
    failed = failed || !connection_tie_break_prefers_inbound(high_local, sizeof(high_local), &low_peer);
    failed = failed || connection_tie_break_prefers_inbound(low_local, sizeof(low_local), &longer_peer);
    failed = failed || !connection_tie_break_prefers_inbound(longer_peer.bytes, longer_peer.len, &low_peer);
    return failed;
}

int main(void) {
    for (size_t i = 0; i < sizeof(kQuickstartGenesisEnrs) / sizeof(kQuickstartGenesisEnrs[0]); ++i) {
        if (validation_accepts_quickstart_enr(kQuickstartGenesisEnrs[i]) != 0) {
            return 1;
        }
    }

    if (connection_counter_keeps_peer_until_last_connection_closes() != 0) {
        return 1;
    }

    if (connection_tie_break_is_symmetric() != 0) {
        return 1;
    }

    return dial_starts_after_launch();
}
