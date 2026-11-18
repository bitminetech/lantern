/*
 * The layout of the App, the constants and the RODATA of the binary (asm/core/<ISA>/app.s,
 * docs/reference/app.md). Included once by app.s. The same on every ISA.
 */

/*
 * The App: the state of lantern_app_main, in memory from lantern_shell_map. Pairs are an address
 * and a size. The functions of app.s read it from the App register (x19, rbx, s1).
 */
.set APP_ARGS, 0                            /* the ArgList */
.set APP_OPTIONS, 8                         /* AppOptions */
.set APP_CONFIG, APP_OPTIONS + AppOptions__size
.set APP_SCRATCH, APP_CONFIG + CONFIG_SIZE  /* pair */
.set APP_STATE, APP_SCRATCH + 16            /* pair: the anchor state, BufferId 1 */
.set APP_BLOCK, APP_STATE + 16              /* pair: the anchor block */
.set APP_STORE, APP_BLOCK + 16              /* pair */
.set APP_NODE, APP_STORE + 16               /* pair */
.set APP_SEEN, APP_NODE + 16                /* pair */
.set APP_ACTIONS, APP_SEEN + 16             /* pair: the actions of a step */
.set APP_EVENTS, APP_ACTIONS + 16           /* pair: a ByteList of the events of the next step */
.set APP_FORK, APP_EVENTS + 16              /* the fork of the genesis state */
.set APP_FLAGS, APP_FORK + 8                /* NODE_FLAG_* */
.set APP_LAST_SLOT, APP_FLAGS + 8           /* the slot of the last log line */
.set APP_STREAM, APP_LAST_SLOT + 8          /* 1 or 2, for lantern_shell_write */
.set APP_WORK_EVENT, APP_STREAM + 8         /* pair: the event buffer of a work */
.set APP_TICK, APP_WORK_EVENT + 16          /* the libp2p Tick of the step */
.set APP_KEY, APP_TICK + 64                 /* the secp256k1 key of libp2p and discv5 */
.set APP_P2P, APP_KEY + 32                  /* pair: the libp2p state */
.set APP_SHELL, APP_P2P + 16                /* pair: the asm-libp2p shell context */
.set APP_SHELL_EVENTS, APP_SHELL + 16       /* pair: a ByteList of the shell's events */
.set APP_P2P_CONFIG, APP_SHELL_EVENTS + 16  /* pair: the libp2p Config */
.set APP_ENGINE, APP_P2P_CONFIG + 16        /* 0 no connection, 1 dialing, 2 open */
.set APP_ENGINE_GEN, APP_ENGINE + 8         /* the generation of the connection's Handle */
.set APP_ENGINE_ADDR, APP_ENGINE_GEN + 8    /* the Address of the execution engine */
.set APP_ENGINE_OUT, APP_ENGINE_ADDR + 32   /* pair: the request bytes to send */
.set APP_ENGINE_LEN, APP_ENGINE_OUT + 16    /* the bytes of the request */
.set APP_ENGINE_SENT, APP_ENGINE_LEN + 8    /* the bytes given to the shell */
.set APP_ENGINE_FLIGHT, APP_ENGINE_SENT + 8 /* the bytes in the shell's send buffer */
.set APP_ENGINE_ACT, APP_ENGINE_FLIGHT + 8  /* pair: a ByteList of one shell action */
.set APP_ENGINE_DUE, APP_ENGINE_ACT + 16    /* 1 when the shell's events allow more bytes */
.set APP_DV, APP_ENGINE_DUE + 8             /* pair: the discv5 state */
.set APP_DV_SCRATCH, APP_DV + 16            /* pair */
.set APP_DV_EVENTS, APP_DV_SCRATCH + 16     /* pair: an EventList for the next discv5 step */
.set APP_DV_ACTIONS, APP_DV_EVENTS + 16     /* pair: an ActionList */
.set APP_DV_OUT, APP_DV_ACTIONS + 16        /* pair: a ByteList of the SEND_DATAGRAM shell actions */
.set APP_DV_SOCKET, APP_DV_OUT + 16         /* the UDP socket ID of discv5 */
.set APP_DV_WAKE, APP_DV_SOCKET + 8         /* the next discv5 step by this time, ms */
.set APP_DV_TICK, APP_DV_WAKE + 8           /* the discv5 Tick: now, entropy */
.set APP_API_SHELL, APP_DV_TICK + 40        /* pair: the shell context of the Beacon API */
.set APP_API_EVENTS, APP_API_SHELL + 16     /* pair: a ByteList of its events */
.set APP_API_ACT, APP_API_EVENTS + 16       /* pair: a ByteList of its shell actions */
.set APP_API_OUT, APP_API_ACT + 16          /* pair: a ByteList of a response */
.set APP_API_REQ, APP_API_OUT + 16          /* pair: a request ByteList for each connection slot */
.set APP_VIEW, APP_API_REQ + 16             /* pair: the ApiView */
.set APP_API_SLOTS, APP_VIEW + 16           /* each slot: its generation, then 0 free, 1 reading, 2 answered */
.set APP_ANCHOR_HEADER, APP_API_SLOTS + 16 * APP_API_SLOTS_MAX  /* the anchor's SignedBeaconBlockHeader */
.set APP_HEADER, APP_ANCHOR_HEADER + 208    /* a block's SignedBeaconBlockHeader */
.set APP_RECORD, APP_HEADER + 208           /* a NODE_EV_ENR event of a boot node: 48 bytes, then the record */
.set APP_FILE, APP_RECORD + 48 + APP_RECORD_MAX /* FileResult */
.set APP_RESULT, APP_FILE + 32              /* NodeStepResult */
.set APP_NODE_ROOM, APP_RESULT + 16         /* NodeRoom */
.set APP_STORE_ROOM, APP_NODE_ROOM + 80     /* StoreRoom */
.set APP_SEEN_ROOM, APP_STORE_ROOM + 16     /* SeenRoom */
.set APP_STATE_ROOM, APP_SEEN_ROOM + 32     /* StateRoom */
.set APP_ANCHOR, APP_STATE_ROOM + 64        /* NodeAnchor */
.set APP_BUFS, APP_ANCHOR + 176             /* the BufferId table: address, count, capacity */
.set APP_TMP, APP_BUFS + 24                 /* 64 bytes */
.set APP_LINE, APP_TMP + 64                 /* a ByteList: the log line */
.set APP_LINE_MAX, 512
.set APP_PATH, APP_LINE + 24 + APP_LINE_MAX /* a ByteList: a path */
.set APP_PATH_MAX, 4096
.set APP_SIZE, (APP_PATH + 24 + APP_PATH_MAX + 4095) & ~4095
.set APP_BLOCK_BYTES, 1 << 16               /* the anchor block */
.set APP_BUF_ENTRY, 24                      /* a BufferId table entry: id, address, size */
.set APP_BUFS_CAP, 4096
.set APP_QUEUE_BYTES, 1 << 20               /* the events, and the actions, of a step */
.set APP_TRIES, 8                           /* the times a start step doubles its buffers */
.set APP_WAIT_MS, 100                       /* the longest wait for the sockets */
.set APP_SHELL_EVENT_BYTES, 8 << 20
.set APP_PROTOCOLS_MAX, 64
.set APP_RECORD_MAX, 512                     /* the bytes of a boot node record */
.set APP_DV_EVENT_BYTES, 1 << 20            /* the events of a discv5 step */
.set APP_DV_OUT_BYTES, 4 << 20              /* the datagrams of a discv5 step */
.set APP_DV_DATAGRAM_MAX, 1280
.set APP_API_SLOTS_MAX, 16                  /* Beacon API connections at a time */
.set APP_API_REQ_BYTES, 8192                /* the bytes of a request */
.set APP_API_OUT_BYTES, 1 << 16
.set APP_API_SEND_WINDOW, 1 << 17
.set APP_API_EVENT_BYTES, 1 << 20
.set APP_WORK_TRIES, 16                     /* the times a work grows a buffer */

    RODATA
    .p2align 3
app_builtin_config:                         /* the pinned config of the preset: a ByteList */
    .quad app_builtin_config_end - app_builtin_config, 24, app_builtin_config_end - app_builtin_config_text
app_builtin_config_text:
    .incbin "config.yaml"
app_builtin_config_end:
    .p2align 3
app_node_room:                              /* NodeRoom; peers from --target-peers */
    .quad 1024, 64, 1, 64, 512, 8192, 1 << 20, 4096, 1024, 1 << 20
app_seen_room:                              /* SeenRoom */
    .quad 65536, 65536, 4096, 1 << 20
app_state_room:                             /* StateRoom */
    .quad 1024, 2048, 64, 1024, 64, 64, 4, 4096
app_m_prefix:
    .ascii "lantern: "
.set app_m_prefix_len, 9
app_m_option:
    .ascii "faulty option at argument "
.set app_m_option_len, 26
app_m_read:
    .ascii "cannot read "
.set app_m_read_len, 12
app_m_error:
    .ascii ": error "
.set app_m_error_len, 8
app_m_line:
    .ascii ": faulty line "
.set app_m_line_len, 14
app_m_status:
    .ascii ": status "
.set app_m_status_len, 9
app_m_short:
    .ascii ": too short"
.set app_m_short_len, 11
app_m_memory:
    .ascii "no memory"
.set app_m_memory_len, 9
app_m_store:
    .ascii "the store"
.set app_m_store_len, 9
app_m_node:
    .ascii "the node"
.set app_m_node_len, 8
app_m_step:
    .ascii "a node step"
.set app_m_step_len, 11
app_m_work:
    .ascii "a work"
.set app_m_work_len, 6
app_m_buffer:
    .ascii "an action's BufferId"
.set app_m_buffer_len, 20
app_m_started:
    .ascii "started at slot "
.set app_m_started_len, 16
app_m_fork:
    .ascii ", fork "
.set app_m_fork_len, 7
app_m_head:
    .ascii ", head 0x"
.set app_m_head_len, 9
app_m_slot:
    .ascii "slot "
.set app_m_slot_len, 5
app_m_finalized:
    .ascii ", finalized epoch "
.set app_m_finalized_len, 18
app_config_name:
    .ascii "config.yaml"
.set app_config_name_len, 11
app_genesis_name:
    .ascii "genesis.ssz"
.set app_genesis_name_len, 11
app_hex_digits:
    .ascii "0123456789abcdef"
app_m_p2p:
    .ascii "libp2p"
.set app_m_p2p_len, 6
app_m_listen:
    .ascii "listen on TCP port "
.set app_m_listen_len, 19
app_m_listening:
    .ascii "listening on TCP port "
.set app_m_listening_len, 22
app_m_boot:
    .ascii "boot node "
.set app_m_boot_len, 10
app_m_not_enr:
    .ascii ": not an enr: record"
.set app_m_not_enr_len, 20
app_enr_prefix:
    .ascii "enr:"
app_localhost:
    .ascii "localhost"
app_m_endpoint:
    .ascii "--execution-endpoint: give an IPv4 address or localhost, a colon and a port"
.set app_m_endpoint_len, 75
app_m_jwt:
    .ascii "--jwt-secret: a file of 32 bytes in hex is needed with --execution-endpoint"
.set app_m_jwt_len, 75
app_m_hex:
    .ascii ": not 32 bytes in hex"
.set app_m_hex_len, 21
app_m_discv5:
    .ascii "discv5"
.set app_m_discv5_len, 6
app_m_bind:
    .ascii "bind UDP port "
.set app_m_bind_len, 14
app_m_record:
    .ascii "record enr:"
.set app_m_record_len, 11
app_base64url_digits:
    .ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
app_base58_digits:
    .ascii "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
app_version_text:
    .ascii "lantern/v0.1.0"
.set app_version_text_len, 14
app_m_api:
    .ascii "Beacon API on TCP port "
.set app_m_api_len, 23
app_m_peer_id:
    .ascii ", peer id "
.set app_m_peer_id_len, 10
app_t_ip4:
    .ascii "/ip4/"
app_t_tcp:
    .ascii "/tcp/"
app_t_udp:
    .ascii "/udp/"
app_t_p2p:
    .ascii "/p2p/"
app_t_dot:
    .ascii "."
app_t_enr:
    .ascii "enr:"
.include "app_p2p.inc"
