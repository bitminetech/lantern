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
.set APP_API_EVENT, APP_API_ACT + 16        /* pair: a NODE_EV_API event: 48 bytes, then its HttpRequest */
.set APP_API_BUF, APP_API_EVENT + 16        /* pair: each slot's ByteList of its connection's bytes, APP_API_SLOT_BYTES apart */
.set APP_IDENTITY, APP_API_BUF + 16         /* pair: a NODE_EV_API_IDENTITY event: 48 bytes, then its ApiIdentity */
.set APP_API_SLOTS, APP_IDENTITY + 16       /* pair: the slots, APP_API_SLOT bytes each */
.set APP_RECORD, APP_API_SLOTS + 16         /* a NODE_EV_ENR event of a boot node: 48 bytes, then the record */
.set APP_FILE, APP_RECORD + 48 + APP_RECORD_MAX /* FileResult */
.set APP_RESULT, APP_FILE + 32              /* NodeStepResult */
.set APP_NODE_ROOM, APP_RESULT + NodeStepResult__size         /* NodeRoom */
.set APP_STORE_ROOM, APP_NODE_ROOM + 8 * NODE_ROOM_FIELDS  /* StoreRoom */
.set APP_SEEN_ROOM, APP_STORE_ROOM + 16     /* SeenRoom */
.set APP_STATE_ROOM, APP_SEEN_ROOM + 32     /* StateRoom */
.set APP_ANCHOR, APP_STATE_ROOM + 64        /* NodeAnchor */
.set APP_BUFS, APP_ANCHOR + NodeAnchor__mem   /* the BufferId table: address, count, capacity */
.set APP_TMP, APP_BUFS + 24                 /* 64 bytes */
.set APP_LINE, APP_TMP + 64                 /* a ByteList: the log line */
.set APP_LINE_MAX, 512
.set APP_PATH, APP_LINE + 24 + APP_LINE_MAX /* a ByteList: a path */
.set APP_PATH_MAX, 4096
.set APP_KZG, APP_PATH + 24 + APP_PATH_MAX  /* pair: the KzgSettings of the trusted setup */
.set APP_PEERS, APP_KZG + 16               /* the count of connected peers of the last log line */
.set APP_DB, APP_PEERS + 8                  /* AppDb: the files of the node's history */
.set AppDb_file, 0                          /* the open segment files: blocks, then sidecars */
.set AppDb_segment, 16                      /* their segments, or 2^64 - 1 */
.set AppDb_maps, 32                         /* APP_DB_MAP_COUNT mapped segments of 32 bytes: key (bit 63 sidecars, the segment), address, size, mapped */
.set APP_DB_MAP_COUNT, 4
.set AppDb_next_map, AppDb_maps + 32 * APP_DB_MAP_COUNT /* the map a new segment takes next */
.set AppDb_view, AppDb_next_map + 8         /* a BufferId table entry (id, address, size), then a ByteList header */
.set AppDb_op, AppDb_view + 48              /* a FileOp or FileResult */
.set AppDb_anchor_slot, AppDb_op + 32      /* the slot of the anchor.ssz this run wrote, or 2^64 - 1 */
.set AppDb__size, AppDb_anchor_slot + 8
.set APP_PATH2, APP_DB + AppDb__size        /* a ByteList: a second path */
.set APP_DB_ROOTS, 4096                     /* the Db's first root table */
.set APP_SIZE, (APP_PATH2 + 24 + APP_PATH_MAX + 4095) & ~4095
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
.set APP_API_HEAD_MAX, 16384                /* HttpLimits of the Beacon API's requests */
.set APP_API_BODY_MAX, 1 << 20
.set APP_API_BUFFER, APP_API_HEAD_MAX + APP_API_BODY_MAX + APP_API_HEAD_MAX  /* the bytes a slot holds */
.set APP_API_SLOT_BYTES, 24 + APP_API_BUFFER
.set APP_API_SLOT, 48                       /* a slot: its generation, its state, its bytes held, the time of its last bytes, its bytes in flight, 1 when an API_SENT is owed */
.set APP_API_FREE, 0                        /* the states of a slot */
.set APP_API_READING, 1                     /* no answer pending: its bytes are read */
.set APP_API_ANSWERING, 2                   /* a NODE_EV_API went; the answer's last bytes have not */
.set APP_API_CLOSING, 3                     /* closed, until the shell's CLOSED */
.set APP_API_DRAINING, 4                    /* the node closed it: its bytes in flight go out, then the CLOSE */
.set APP_API_IDLE_MS, 30000
.set APP_API_SEND_WINDOW, 1 << 17
.set APP_API_EVENT_BYTES, 1 << 20
.set APP_API_ACT_BYTES, 1 << 20
.set APP_WORK_TRIES, 16                     /* the times a work grows a buffer */
.set APP_STEP_TRIES, 64                     /* the times a node step grows a buffer, one field at a time */

/* The log (app.md): the time and level before each line, and the kind of a line for app_line_end. */
.set APP_LOG_PREFIX, 30                     /* YYYY-MM-DD HH:MM:SS.mmm, a space, the level, a space */
.set APP_LOG_INFO, 1                        /* the standard output */
.set APP_LOG_ERROR, 2                       /* the standard error */
.set APP_LOG_WARN, 3                        /* the standard error */
.set APP_LOG_DEBUG, 4                       /* the standard output */

    RODATA
    .p2align 3
app_builtin_config:                         /* the pinned config of the preset: a ByteList */
    .quad app_builtin_config_end - app_builtin_config, 24, app_builtin_config_end - app_builtin_config_text
app_builtin_config_text:
    .incbin "config.yaml"
app_builtin_config_end:
    .p2align 3
app_node_room:                              /* NodeRoom; peers from --target-peers, api_streams from --http-max-connections */
    .quad 1024, 64, 1, 64, 512, 8192, 1 << 20, 4096, 1024, 1 << 20, 0, 1, 64
app_seen_room:                              /* SeenRoom */
    .quad 65536, 65536, 4096, 1 << 20
app_state_room:                             /* StateRoom */
    .quad 1024, 2048, 64, 1024, 64, 64, 4, 4096
app_log_rank:                               /* the level of each kind of line: APP_LOG_INFO to APP_LOG_DEBUG */
    .byte 2, 2, 0, 1, 3
app_log_names:                              /* each level's name in 5 bytes, at 8 bytes apart */
    .ascii "ERROR"
    .space 3
    .ascii "WARN "
    .space 3
    .ascii "INFO "
    .space 3
    .ascii "DEBUG"
    .space 3
app_m_log_work:
    .ascii "work "
.set app_m_log_work_len, 5
app_m_log_result:
    .ascii " result "
.set app_m_log_result_len, 8
app_m_log_block:
    .ascii "block "
.set app_m_log_block_len, 6
app_m_log_imported:
    .ascii " imported, "
.set app_m_log_imported_len, 11
app_m_log_attestations:
    .ascii " attestations"
.set app_m_log_attestations_len, 13
app_m_log_not:
    .ascii " not imported: result "
.set app_m_log_not_len, 22
app_m_option:
    .ascii "faulty option at argument "
.set app_m_option_len, 26
app_m_read:
    .ascii "cannot read "
.set app_m_read_len, 12
app_m_error:
    .ascii ": error "
.set app_m_error_len, 8
app_m_write:
    .ascii "cannot write "
.set app_m_write_len, 13
app_m_restart:
    .ascii "restart at slot "
.set app_m_restart_len, 16
app_m_checkpoint:
    .ascii "checkpoint at slot "
.set app_m_checkpoint_len, 19
app_anchor_name:
    .ascii "anchor.ssz"
.set app_anchor_name_len, 10
app_anchor_tmp_name:
    .ascii "anchor.tmp"
.set app_anchor_tmp_name_len, 10
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
app_m_earliest:
    .ascii ", earliest slot "
.set app_m_earliest_len, 16
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
    .ascii "Beacon API on TCP "
.set app_m_api_len, 18
app_t_colon:
    .ascii ":"
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
app_m_peers:
    .ascii "peers "
.set app_m_peers_len, 6
app_m_room:
    .ascii ": no room in buffer "
.set app_m_room_len, 20
app_m_kzg:
    .ascii "the KZG trusted setup"
.set app_m_kzg_len, 21
    .p2align 3
app_kzg_g1_lagrange:                        /* the trusted setup (docs/reference/app.md): three ByteLists */
    .quad 24 + 4096 * 48, 24, 4096 * 48
    .incbin "trusted_setup_4096.bin", 0, 4096 * 48
app_kzg_g1_monomial:
    .quad 24 + 4096 * 48, 24, 4096 * 48
    .incbin "trusted_setup_4096.bin", 4096 * 48, 4096 * 48
app_kzg_g2_monomial:
    .quad 24 + 65 * 96, 24, 65 * 96
    .incbin "trusted_setup_4096.bin", 2 * 4096 * 48, 65 * 96
.include "app_p2p.inc"
