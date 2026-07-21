#include "../../src/core/client_network_internal.h"

#include "lantern/core/client.h"
#include "lantern/metrics/lean_metrics.h"
#include "lantern/networking/enr.h"
#include "lantern/networking/libp2p.h"
#include "lantern/support/string_list.h"

#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static const uint8_t kHostSecret[32] = {
    0xb7, 0x1c, 0x71, 0xa6, 0x7e, 0x11, 0x77, 0xad,
    0x4e, 0x90, 0x16, 0x95, 0xe1, 0xb4, 0xb9, 0xee,
    0x17, 0xae, 0x16, 0xc6, 0x66, 0x8d, 0x31, 0x3e,
    0xac, 0x2f, 0x96, 0xdb, 0xcd, 0xa3, 0xf2, 0x91,
};

static const uint8_t kPeerSecret[32] = {
    0x31, 0xb4, 0xc8, 0x67, 0x02, 0x89, 0x5e, 0x1d,
    0xa6, 0x73, 0xf0, 0x42, 0x9b, 0xcd, 0x16, 0x75,
    0xe8, 0x54, 0x2f, 0x90, 0x6a, 0x13, 0xdc, 0x48,
    0x7f, 0x25, 0xb9, 0x01, 0x5c, 0xee, 0x3a, 0x64,
};

struct connection_event_counts {
    int established;
    int closed;
};

static void count_connection_events(
    struct lantern_libp2p_host *network,
    const libp2p_host_event_t *event,
    void *user_data) {
    (void)network;
    struct connection_event_counts *counts = user_data;
    if (!event || !counts) {
        return;
    }
    if (event->type == LIBP2P_HOST_EVENT_CONN_ESTABLISHED) {
        (void)__atomic_add_fetch(&counts->established, 1, __ATOMIC_RELAXED);
    } else if (event->type == LIBP2P_HOST_EVENT_CONN_CLOSED) {
        (void)__atomic_add_fetch(&counts->closed, 1, __ATOMIC_RELAXED);
    }
}

static int wait_for_event_count(const int *count, int expected) {
    const struct timespec pause = {.tv_sec = 0, .tv_nsec = 5000000};
    for (size_t attempt = 0; attempt < 600u; ++attempt) {
        if (__atomic_load_n(count, __ATOMIC_RELAXED) >= expected) {
            return 0;
        }
        (void)nanosleep(&pause, NULL);
    }
    return -1;
}

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

    connection_counter_update(&client, 1, conn1, &peer, true, LIBP2P_HOST_OK, false, 0U);
    connection_counter_update(&client, 1, conn2, &peer, false, LIBP2P_HOST_OK, false, 0U);
    int failed = !lantern_client_is_peer_connected(&client, peer_text)
        || client.connected_peers != 1u
        || client.connection_peer_ref_count != 2u;

    connection_counter_update(&client, -1, conn1, NULL, false, LIBP2P_HOST_OK, true, 0U);
    failed = failed || !lantern_client_is_peer_connected(&client, peer_text)
        || client.connected_peers != 1u
        || client.connection_peer_ref_count != 1u;

    connection_counter_update(&client, -1, unknown_conn, NULL, false, LIBP2P_HOST_OK, true, 0U);
    failed = failed || !lantern_client_is_peer_connected(&client, peer_text)
        || client.connected_peers != 1u
        || client.connection_peer_ref_count != 1u;

    connection_counter_update(&client, -1, conn2, NULL, false, LIBP2P_HOST_OK, true, 0U);
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

static int connection_recovery_respects_close_origin(void) {
    if (connection_close_should_redial(LIBP2P_HOST_ERR_CLOSED, true)) {
        return 1;
    }
    if (!connection_close_should_redial(LIBP2P_HOST_ERR_CLOSED, false)) {
        return 1;
    }
    return connection_close_should_redial(LIBP2P_HOST_OK, false) ? 1 : 0;
}

static int connection_metrics_classify_close_details(void) {
    static const char *peer_text = "16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE";
    struct lantern_client client;
    struct lantern_peer_id peer;
    int conns[3];

    memset(&client, 0, sizeof(client));
    if (pthread_mutex_init(&client.connection_lock, NULL) != 0) {
        return 1;
    }
    client.connection_lock_initialized = true;
    if (lantern_peer_id_from_text(peer_text, &peer) != 0) {
        pthread_mutex_destroy(&client.connection_lock);
        return 1;
    }

    lean_metrics_reset();

    connection_counter_update(&client, 1, &conns[0], &peer, false, LIBP2P_HOST_OK, false, 0U);
    connection_counter_update(&client, -1, &conns[0], NULL, false, LIBP2P_HOST_ERR_CLOSED, true, 73U);

    connection_counter_update(&client, 1, &conns[1], &peer, false, LIBP2P_HOST_OK, false, 0U);
    connection_counter_update(&client, -1, &conns[1], NULL, false, LIBP2P_HOST_ERR_CLOSED, false, 0U);

    connection_counter_update(&client, 1, &conns[2], &peer, false, LIBP2P_HOST_OK, false, 0U);
    connection_counter_update(&client, -1, &conns[2], NULL, false, LIBP2P_HOST_ERR_CLOSED, false, 73U);

    struct lean_metrics_snapshot snapshot;
    lean_metrics_snapshot(&snapshot);
    const uint64_t *outbound = snapshot.peer_disconnection_events_total[LEAN_METRICS_DIR_OUTBOUND];
    int failed = outbound[LEAN_METRICS_DISCONNECT_LOCAL_CLOSE] != 1U
        || outbound[LEAN_METRICS_DISCONNECT_REMOTE_CLOSE] != 1U
        || outbound[LEAN_METRICS_DISCONNECT_ERROR] != 1U
        || outbound[LEAN_METRICS_DISCONNECT_TIMEOUT] != 0U;

    pthread_mutex_destroy(&client.connection_lock);
    free(client.connection_peer_refs);
    return failed;
}

static int peer_maintenance_uses_drive_schedule(void) {
    struct lantern_client client;
    memset(&client, 0, sizeof(client));
    client.dialer_stop_flag = 1;

    peer_maintenance_drive(NULL, 100u, &client);
    if (client.peer_maintenance_next_us != 0u) {
        return 1;
    }

    if (start_peer_dialer(&client) != 0) {
        return 1;
    }
    peer_maintenance_drive(NULL, 100u, &client);
    const uint64_t interval_us = (uint64_t)LANTERN_PEER_DIAL_INTERVAL_SECONDS * 1000000u;
    if (client.peer_maintenance_next_us != 100u + interval_us) {
        return 1;
    }
    if (start_peer_dialer(&client) != 0
        || client.peer_maintenance_next_us != 100u + interval_us) {
        return 1;
    }

    peer_maintenance_drive(NULL, client.peer_maintenance_next_us - 1u, &client);
    if (client.peer_maintenance_next_us != 100u + interval_us) {
        return 1;
    }

    peer_maintenance_drive(NULL, client.peer_maintenance_next_us, &client);
    if (client.peer_maintenance_next_us != 100u + (2u * interval_us)) {
        return 1;
    }

    stop_peer_dialer(&client);
    peer_maintenance_drive(NULL, client.peer_maintenance_next_us, &client);
    return client.peer_maintenance_next_us != 100u + (2u * interval_us);
}

static int graceful_stop_precedes_same_identity_restart(void) {
    struct lantern_libp2p_host restarting;
    struct lantern_libp2p_host peer;
    struct connection_event_counts peer_events = {0};
    const char *restarting_listen = "/ip4/127.0.0.1/udp/19310/quic-v1";
    const char *peer_listen = "/ip4/127.0.0.1/udp/19311/quic-v1";
    char peer_multiaddr[256];
    char peer_text[LANTERN_LIBP2P_PEER_TEXT_MAX_BYTES];
    struct lantern_peer_id peer_id;
    int rc = 1;

    lantern_libp2p_host_init(&restarting);
    lantern_libp2p_host_init(&peer);
    struct lantern_libp2p_config restarting_config = {
        .listen_multiaddr = restarting_listen,
        .secp256k1_secret = kHostSecret,
        .secret_len = sizeof(kHostSecret),
    };
    struct lantern_libp2p_config peer_config = {
        .listen_multiaddr = peer_listen,
        .secp256k1_secret = kPeerSecret,
        .secret_len = sizeof(kPeerSecret),
    };

    if (lantern_libp2p_host_prepare(&peer, &peer_config) != 0) {
        fprintf(stderr, "failed to prepare persistent libp2p peer\n");
        goto cleanup;
    }
    memset(&peer_id, 0, sizeof(peer_id));
    memcpy(peer_id.bytes, peer.local_peer_id, peer.local_peer_id_len);
    peer_id.len = peer.local_peer_id_len;
    if (lantern_peer_id_to_text(&peer_id, peer_text, sizeof(peer_text)) < 0
        || snprintf(
               peer_multiaddr,
               sizeof(peer_multiaddr),
               "%s/p2p/%s",
               peer_listen,
               peer_text)
            < 0
        || lantern_libp2p_host_register_event_handler(
               &peer,
               count_connection_events,
               &peer_events)
            != 0
        || lantern_libp2p_host_prepare(&restarting, &restarting_config) != 0
        || lantern_libp2p_host_launch(&peer) != 0
        || lantern_libp2p_host_launch(&restarting) != 0
        || lantern_libp2p_host_dial_multiaddr(&restarting, peer_multiaddr) != 0
        || wait_for_event_count(&peer_events.established, 1) != 0) {
        fprintf(stderr, "failed to establish initial libp2p connection\n");
        goto cleanup;
    }

    lantern_libp2p_host_stop(&restarting);
    if (wait_for_event_count(&peer_events.closed, 1) != 0) {
        fprintf(stderr, "peer did not observe graceful close before restart\n");
        goto cleanup;
    }

    lantern_libp2p_host_reset(&restarting);
    if (lantern_libp2p_host_prepare(&restarting, &restarting_config) != 0
        || lantern_libp2p_host_launch(&restarting) != 0
        || lantern_libp2p_host_dial_multiaddr(&restarting, peer_multiaddr) != 0
        || wait_for_event_count(&peer_events.established, 2) != 0) {
        fprintf(stderr, "same-identity libp2p restart did not reconnect\n");
        goto cleanup;
    }

    rc = 0;

cleanup:
    lantern_libp2p_host_reset(&restarting);
    lantern_libp2p_host_reset(&peer);
    return rc;
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

    if (connection_recovery_respects_close_origin() != 0) {
        return 1;
    }

    if (connection_metrics_classify_close_details() != 0) {
        return 1;
    }

    if (peer_maintenance_uses_drive_schedule() != 0) {
        return 1;
    }

    if (graceful_stop_precedes_same_identity_restart() != 0) {
        return 1;
    }

    return dial_starts_after_launch();
}
