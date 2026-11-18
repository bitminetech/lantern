/*
 * The binary's startup and loop, ARM64: its own object, which only the binary links (entry.s calls
 * lantern_app_main). Requirements: docs/reference/app.md.
 */
.set ISA_ARM64, 1
.include "ssz.inc"
.include "crypto.inc"
.include "bls12381.inc"
.include "kzg.inc"
.include "preset.inc"
.include "lantern.inc"
.include "fork_numbers.inc"
.include "platform.inc"
.include "libp2p.inc"
.include "discv5.inc"
.include "macros.s"
.include "memory.s"

/*
 * The App: the state of lantern_app_main, in memory from lantern_shell_map. Pairs are an address
 * and a size. The functions below read it from x19.
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
.set app_m_prefix_len, . - app_m_prefix
app_m_option:
    .ascii "faulty option at argument "
.set app_m_option_len, . - app_m_option
app_m_read:
    .ascii "cannot read "
.set app_m_read_len, . - app_m_read
app_m_error:
    .ascii ": error "
.set app_m_error_len, . - app_m_error
app_m_line:
    .ascii ": faulty line "
.set app_m_line_len, . - app_m_line
app_m_status:
    .ascii ": status "
.set app_m_status_len, . - app_m_status
app_m_short:
    .ascii ": too short"
.set app_m_short_len, . - app_m_short
app_m_memory:
    .ascii "no memory"
.set app_m_memory_len, . - app_m_memory
app_m_store:
    .ascii "the store"
.set app_m_store_len, . - app_m_store
app_m_node:
    .ascii "the node"
.set app_m_node_len, . - app_m_node
app_m_step:
    .ascii "a node step"
.set app_m_step_len, . - app_m_step
app_m_work:
    .ascii "a work"
.set app_m_work_len, . - app_m_work
app_m_buffer:
    .ascii "an action's BufferId"
.set app_m_buffer_len, . - app_m_buffer
app_m_started:
    .ascii "started at slot "
.set app_m_started_len, . - app_m_started
app_m_fork:
    .ascii ", fork "
.set app_m_fork_len, . - app_m_fork
app_m_head:
    .ascii ", head 0x"
.set app_m_head_len, . - app_m_head
app_m_slot:
    .ascii "slot "
.set app_m_slot_len, . - app_m_slot
app_m_finalized:
    .ascii ", finalized epoch "
.set app_m_finalized_len, . - app_m_finalized
app_config_name:
    .ascii "config.yaml"
.set app_config_name_len, . - app_config_name
app_genesis_name:
    .ascii "genesis.ssz"
.set app_genesis_name_len, . - app_genesis_name
app_hex_digits:
    .ascii "0123456789abcdef"
app_m_p2p:
    .ascii "libp2p"
.set app_m_p2p_len, . - app_m_p2p
app_m_listen:
    .ascii "listen on TCP port "
.set app_m_listen_len, . - app_m_listen
app_m_listening:
    .ascii "listening on TCP port "
.set app_m_listening_len, . - app_m_listening
app_m_boot:
    .ascii "boot node "
.set app_m_boot_len, . - app_m_boot
app_m_not_enr:
    .ascii ": not an enr: record"
.set app_m_not_enr_len, . - app_m_not_enr
app_enr_prefix:
    .ascii "enr:"
app_localhost:
    .ascii "localhost"
app_m_endpoint:
    .ascii "--execution-endpoint: give an IPv4 address or localhost, a colon and a port"
.set app_m_endpoint_len, . - app_m_endpoint
app_m_jwt:
    .ascii "--jwt-secret: a file of 32 bytes in hex is needed with --execution-endpoint"
.set app_m_jwt_len, . - app_m_jwt
app_m_hex:
    .ascii ": not 32 bytes in hex"
.set app_m_hex_len, . - app_m_hex
app_m_discv5:
    .ascii "discv5"
.set app_m_discv5_len, . - app_m_discv5
app_m_bind:
    .ascii "bind UDP port "
.set app_m_bind_len, . - app_m_bind
app_m_record:
    .ascii "record enr:"
.set app_m_record_len, . - app_m_record
app_base64url_digits:
    .ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
app_base58_digits:
    .ascii "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
app_version_text:
    .ascii "lantern/v0.1.0"
.set app_version_text_len, . - app_version_text
app_m_api:
    .ascii "Beacon API on TCP port "
.set app_m_api_len, . - app_m_api
app_m_peer_id:
    .ascii ", peer id "
.set app_m_peer_id_len, . - app_m_peer_id
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

/* L0: x0 = the fork of the slot x0 with the config x1: the last fork whose epoch is at most the slot's. Uses x9-x11. */
LOCAL_FUNCTION app_fork
    UNWIND_END_PROLOGUE
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x9, x0, x9
    mov     x10, #(16 * FORK_FULU)
1:  cbz     x10, 2f
    ldr     x11, [x1, x10]
    cmp     x9, x11
    b.hs    2f
    sub     x10, x10, #16
    b       1b
2:  lsr     x0, x10, #4
    ret
END_FUNCTION app_fork

/* L0: x0 = the current slot of the store x0: (time_ms - genesis_time_ms) // SLOT_DURATION_MS, 0 before genesis. Uses x9, x10. */
LOCAL_FUNCTION app_store_slot
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #Store_time_ms]
    ldr     x10, [x0, #Store_genesis_time_ms]
    subs    x9, x9, x10
    csel    x9, xzr, x9, lo
    ldr     x10, [x0, #(Store_config + CONFIG_SLOT_DURATION_MS)]
    mov     x0, #0
    cbz     x10, 1f
    udiv    x0, x9, x10
1:  ret
END_FUNCTION app_store_slot

/* L0: x0 = 1 when the x1 bytes at x0 are the x3 bytes at x2, else 0. Uses x9, x10. */
LOCAL_FUNCTION app_name_is
    UNWIND_END_PROLOGUE
    cmp     x1, x3
    b.ne    2f
1:  cbz     x1, 3f
    ldrb    w9, [x0], #1
    ldrb    w10, [x2], #1
    cmp     w9, w10
    b.ne    2f
    sub     x1, x1, #1
    b       1b
2:  mov     x0, #0
    ret
3:  mov     x0, #1
    ret
END_FUNCTION app_name_is

/* L1: x0 = memory of x0 bytes from lantern_shell_map, zeroed, or 0. Locals: the size, the address. */
LOCAL_FUNCTION app_map
    FRAME 16
    str     x0, [sp, #16]
    add     x0, sp, #16
    add     x1, sp, #24
    CALL_GLOBAL lantern_shell_map
    ldr     x0, [sp, #24]
    UNFRAME 16
END_FUNCTION app_map

/* L1: the pair at x19 + x0 goes back to lantern_shell_unmap and becomes 0, 0. */
LOCAL_FUNCTION app_unmap
    FRAME 16
    add     x9, x19, x0
    str     x9, [sp, #16]
    ldr     x10, [x9]
    cbz     x10, 1f
    mov     x0, x9
    add     x1, x9, #8
    CALL_GLOBAL lantern_shell_unmap
    ldr     x9, [sp, #16]
    stp     xzr, xzr, [x9]
1:  UNFRAME 16
END_FUNCTION app_unmap

/* L1: the pair at x19 + x0 becomes new memory of x1 bytes, its first u64 the size: x0 = the memory, or 0. */
LOCAL_FUNCTION app_alloc
    ENTER 0
    add     x20, x19, x0
    mov     x21, x1
    mov     x0, x21
    bl      app_map
    cbz     x0, 1f
    str     x21, [x0]
    stp     x0, x21, [x20]
1:  LEAVE 0
END_FUNCTION app_alloc

/* L0: the log line starts with "lantern: ". Uses x0-x2, x9-x12. */
LOCAL_FUNCTION app_line_start
    UNWIND_END_PROLOGUE
    str     xzr, [x19, #(APP_LINE + 16)]
    ADDRESS x0, app_m_prefix
    mov     x1, #app_m_prefix_len
    b       app_line_text
END_FUNCTION app_line_start

/* L0: the x1 bytes at x0 join the log line, as far as it has room. Uses x0, x1, x9-x12. */
LOCAL_FUNCTION app_line_text
    UNWIND_END_PROLOGUE
    add     x9, x19, #APP_LINE
    ldr     x10, [x9, #16]
    mov     x11, #APP_LINE_MAX
    sub     x11, x11, x10
    cmp     x1, x11
    csel    x1, x1, x11, ls
    add     x11, x10, x1
    str     x11, [x9, #16]
    add     x9, x9, #24
    add     x9, x9, x10
1:  cbz     x1, 2f
    ldrb    w12, [x0], #1
    strb    w12, [x9], #1
    sub     x1, x1, #1
    b       1b
2:  ret
END_FUNCTION app_line_text

/* L1: the decimal digits of x0 join the log line. Locals: 24 digit bytes. */
LOCAL_FUNCTION app_line_u64
    FRAME 32
    add     x9, sp, #48                     /* the digits, from the end */
    mov     x10, #10
1:  udiv    x11, x0, x10
    msub    x12, x11, x10, x0
    add     x12, x12, #0x30
    strb    w12, [x9, #-1]!
    mov     x0, x11
    cbnz    x0, 1b
    mov     x0, x9
    add     x1, sp, #48
    sub     x1, x1, x9
    bl      app_line_text
    UNFRAME 32
END_FUNCTION app_line_u64

/* L1: the hex digits of the x1 bytes at x0 join the log line. Locals: x0, x1, then 2 digits. */
LOCAL_FUNCTION app_line_hex
    FRAME 32
    stp     x0, x1, [sp, #16]
1:  ldp     x0, x1, [sp, #16]
    cbz     x1, 2f
    ldrb    w9, [x0], #1
    sub     x1, x1, #1
    stp     x0, x1, [sp, #16]
    ADDRESS x10, app_hex_digits
    lsr     w11, w9, #4
    ldrb    w11, [x10, x11]
    strb    w11, [sp, #32]
    and     w11, w9, #15
    ldrb    w11, [x10, x11]
    strb    w11, [sp, #33]
    add     x0, sp, #32
    mov     x1, #2
    bl      app_line_text
    b       1b
2:  UNFRAME 32
END_FUNCTION app_line_hex

/* L1: the log line and an LF go to stream x0: 1 the standard output, 2 the standard error. */
LOCAL_FUNCTION app_line_end
    FRAME 16
    str     x0, [x19, #APP_STREAM]
    mov     w9, #10
    strb    w9, [sp, #16]
    add     x0, sp, #16
    mov     x1, #1
    bl      app_line_text
    add     x0, x19, #APP_STREAM
    add     x1, x19, #APP_LINE
    CALL_GLOBAL lantern_shell_write
    UNFRAME 16
END_FUNCTION app_line_end

/* L1: the path of the x1 bytes of the name at x0 in the network directory: a ByteList at APP_PATH. */
LOCAL_FUNCTION app_path
    ENTER 0
    mov     x20, x0
    mov     x21, x1
    ldp     x22, x23, [x19, #(APP_OPTIONS + AppOptions_network_dir)]
    add     x9, x23, x21                    /* the directory, /, the name: too long reads as too long */
    add     x9, x9, #1
    ADDQ    x10, x19, APP_PATH
    cmp     x9, #APP_PATH_MAX
    b.hi    1f
    str     x9, [x10, #16]
    ldr     x11, [x19, #APP_ARGS]
    add     x1, x11, x22
    add     x0, x10, #24
    mov     x2, x23
    bl      lantern_copy
    ADDQ    x10, x19, APP_PATH
    add     x0, x10, #24
    add     x0, x0, x23
    mov     w9, #0x2f                       /* / */
    strb    w9, [x0], #1
    mov     x1, x20
    mov     x2, x21
    bl      lantern_copy
    LEAVE 0
1:  mov     x9, #(APP_PATH_MAX + 1)         /* a count past the room: the shell gives its error */
    str     x9, [x10, #16]
    LEAVE 0
END_FUNCTION app_path

/* L1: the path of the log line: the bytes of APP_PATH, as far as they fit. */
LOCAL_FUNCTION app_line_path
    FRAME 0
    ADDQ    x9, x19, APP_PATH
    add     x0, x9, #24
    ldr     x1, [x9, #16]
    mov     x10, #APP_PATH_MAX
    cmp     x1, x10
    csel    x1, x1, x10, ls
    bl      app_line_text
    UNFRAME 0
END_FUNCTION app_line_path

/* L1: the file at APP_PATH, read into APP_FILE: x0 = 0, or 2 after a line on the standard error. */
LOCAL_FUNCTION app_read
    FRAME 0
    ADDQ    x0, x19, APP_PATH
    add     x1, x19, #APP_FILE
    CALL_GLOBAL lantern_shell_read_file
    ldr     x9, [x19, #APP_FILE]
    cbz     x9, 1f
    bl      app_line_start                  /* cannot read <path>: error <n> */
    ADDRESS x0, app_m_read
    mov     x1, #app_m_read_len
    bl      app_line_text
    bl      app_line_path
    ADDRESS x0, app_m_error
    mov     x1, #app_m_error_len
    bl      app_line_text
    ldr     x0, [x19, #APP_FILE]
    bl      app_line_u64
    mov     x0, #2
    bl      app_line_end
    mov     x0, #2
    UNFRAME 0
1:  mov     x0, #0
    UNFRAME 0
END_FUNCTION app_read

/* L1: the memory of APP_FILE goes back. */
LOCAL_FUNCTION app_file_free
    FRAME 16
    add     x9, x19, #APP_FILE
    ldr     x10, [x9, #8]
    cbz     x10, 1f
    add     x0, x9, #8
    add     x1, x9, #24
    CALL_GLOBAL lantern_shell_unmap
    str     xzr, [x19, #(APP_FILE + 8)]
1:  UNFRAME 16
END_FUNCTION app_file_free

/* L1: a line "<x1 bytes at x0>: status <x2>" on the standard error, then x0 = 2. Locals: x0-x2. */
LOCAL_FUNCTION app_fail_status
    FRAME 32
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    bl      app_line_start
    ldp     x0, x1, [sp, #16]
    bl      app_line_text
    ADDRESS x0, app_m_status
    mov     x1, #app_m_status_len
    bl      app_line_text
    ldr     x0, [sp, #32]
    bl      app_line_u64
    mov     x0, #2
    bl      app_line_end
    mov     x0, #2
    UNFRAME 32
END_FUNCTION app_fail_status

/*
 * L2: the start of docs/reference/app.md: the config, the anchor of genesis.ssz, the store, the
 * node and the Seen: x0 = 0, or 2 after a line on the standard error. x20 a ByteList, x21 the
 * file's size, x22 a size, x23 a size, x24 the tries. Locals: L a line number or a size.
 */
LOCAL_FUNCTION app_start
    ENTER 16
    ADDRESS x0, app_builtin_config          /* the config: the pinned config of the preset, then the network's */
    add     x1, x19, #APP_CONFIG
    add     x2, sp, #L
    CALL_GLOBAL lantern_config_parse
    ADDRESS x0, app_config_name
    mov     x1, #app_config_name_len
    bl      app_path
    bl      app_read
    cbnz    x0, 99f
    ldr     x0, [x19, #(APP_FILE + 8)]
    add     x1, x19, #APP_CONFIG
    add     x2, sp, #L
    CALL_GLOBAL lantern_config_parse
    mov     x20, x0
    bl      app_file_free
    cbz     x20, 1f
    bl      app_line_start                  /* <path>: faulty line <n> */
    bl      app_line_path
    ADDRESS x0, app_m_line
    mov     x1, #app_m_line_len
    bl      app_line_text
    ldr     x0, [sp, #L]
    bl      app_line_u64
    b       98f
1:  ADDRESS x0, app_genesis_name            /* genesis.ssz: the fork of its slot */
    mov     x1, #app_genesis_name_len
    bl      app_path
    bl      app_read
    cbnz    x0, 99f
    ldr     x20, [x19, #(APP_FILE + 8)]
    ldr     x21, [x19, #(APP_FILE + 16)]
    cmp     x21, #(40 + 8)
    b.hs    2f
    bl      app_line_start
    bl      app_line_path
    ADDRESS x0, app_m_short
    mov     x1, #app_m_short_len
    bl      app_line_text
    b       98f
2:  ldr     x0, [x20, #(24 + 40)]           /* BeaconState.slot */
    add     x1, x19, #APP_CONFIG
    bl      app_fork
    str     x0, [x19, #APP_FORK]
    add     x0, x19, #APP_STATE_ROOM
    ADDRESS x1, app_state_room
    mov     x2, #64
    bl      lantern_copy
    add     x22, x21, x21, lsl #1           /* the state: 3 times the file and 16 MiB; scratch: 2 times and 64 MiB */
    MOVQ    x9, 1 << 24
    add     x22, x22, x9
    lsl     x23, x21, #1
    MOVQ    x9, 1 << 26
    add     x23, x23, x9
    mov     x24, #0
3:  mov     x0, #APP_STATE
    mov     x1, x22
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_SCRATCH
    mov     x1, x23
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_BLOCK
    mov     x1, #APP_BLOCK_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, x20
    add     x1, x19, #APP_STATE_ROOM
    ldr     x2, [x19, #APP_SCRATCH]
    ldr     x3, [x19, #APP_STATE]
    ldr     x4, [x19, #APP_BLOCK]
    ldr     x15, [x19, #APP_FORK]
    FORK_CALL node_anchor
    cbz     x0, 4f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.ne    96f
    mov     x0, #APP_STATE                  /* more room, a few times */
    bl      app_unmap
    mov     x0, #APP_SCRATCH
    bl      app_unmap
    mov     x0, #APP_BLOCK
    bl      app_unmap
    lsl     x22, x22, #1
    lsl     x23, x23, #1
    add     x24, x24, #1
    cmp     x24, #APP_TRIES
    b.lo    3b
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
96: mov     x2, x0                          /* genesis.ssz: status <n> */
    ADDRESS x0, app_genesis_name
    mov     x1, #app_genesis_name_len
    bl      app_fail_status
    b       99f
4:  bl      app_file_free
    mov     x9, #4096                       /* the store: nodes, and validators below the file's bytes / 121 */
    mov     x10, #121
    udiv    x10, x21, x10
    add     x10, x10, x9
    add     x11, x19, #APP_STORE_ROOM
    stp     x9, x10, [x11]
    mov     x24, #0
5:  add     x0, x19, #APP_STORE_ROOM
    add     x1, sp, #L
    CALL_GLOBAL lantern_store_size
    mov     x0, #APP_STORE
    ldr     x1, [sp, #L]
    bl      app_alloc
    cbz     x0, 97f
    ldr     x0, [x19, #APP_STATE]
    ldr     x1, [x19, #APP_BLOCK]
    add     x2, x19, #APP_CONFIG
    add     x3, x19, #APP_STORE_ROOM
    ldr     x4, [x19, #APP_SCRATCH]
    ldr     x5, [x19, #APP_STORE]
    ldr     x15, [x19, #APP_FORK]
    FORK_CALL get_forkchoice_store
    cbz     x0, 6f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.ne    95f
    mov     x0, #APP_STORE
    bl      app_unmap
    add     x11, x19, #APP_STORE_ROOM
    ldp     x9, x10, [x11]
    lsl     x9, x9, #1
    lsl     x10, x10, #1
    stp     x9, x10, [x11]
    add     x24, x24, #1
    cmp     x24, #APP_TRIES
    b.lo    5b
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
95: mov     x2, x0                          /* the store: status <n> */
    ADDRESS x0, app_m_store
    mov     x1, #app_m_store_len
    bl      app_fail_status
    b       99f
6:  ldr     x9, [x19, #APP_STORE]           /* the node's anchor: the store's node 0, the state's root */
    ldr     x10, [x9, #Store_blocks]
    add     x1, x9, x10
    add     x0, x19, #APP_ANCHOR
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x19, #APP_STORE]
    ldr     x10, [x9, #Store_blocks]
    add     x10, x9, x10
    ldr     x11, [x10, #BlockNode_slot]
    str     x11, [x19, #(APP_ANCHOR + 32)]
    add     x0, x19, #(APP_ANCHOR + 40)
    ldr     x1, [x19, #APP_STATE]
    add     x1, x1, #NODE_STATE_GVR
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x19, #APP_FLAGS]           /* the shell runs discv5 for the node */
    orr     x9, x9, #NODE_FLAG_DISCV5
    str     x9, [x19, #APP_FLAGS]
    bl      app_engine_conf                 /* the execution engine */
    cbnz    x0, 99f
    add     x0, x19, #APP_NODE_ROOM         /* the node */
    ADDRESS x1, app_node_room
    mov     x2, #80
    bl      lantern_copy
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_target_peers)]
    str     x9, [x19, #(APP_NODE_ROOM + NodeRoom_peers)]
    add     x0, x19, #APP_NODE_ROOM
    add     x1, sp, #L
    CALL_GLOBAL lantern_node_size
    cbnz    x0, 94f
    mov     x0, #APP_NODE
    ldr     x1, [sp, #L]
    bl      app_alloc
    cbz     x0, 97f
    add     x0, x19, #APP_NODE_ROOM
    add     x1, x19, #APP_CONFIG
    add     x2, x19, #APP_ANCHOR
    add     x3, x19, #APP_FLAGS
    ldr     x4, [x19, #APP_NODE]
    CALL_GLOBAL lantern_node_init
    cbnz    x0, 94f
    add     x0, x19, #APP_SEEN_ROOM         /* the Seen */
    ADDRESS x1, app_seen_room
    mov     x2, #32
    bl      lantern_copy
    add     x0, x19, #APP_SEEN_ROOM
    add     x1, sp, #L
    CALL_GLOBAL lantern_seen_size
    mov     x0, #APP_SEEN
    ldr     x1, [sp, #L]
    bl      app_alloc
    cbz     x0, 97f
    add     x0, x19, #APP_SEEN_ROOM
    ldr     x1, [x19, #APP_SEEN]
    CALL_GLOBAL lantern_seen_init
    cbnz    x0, 94f
    mov     x0, #(APP_BUF_ENTRY * APP_BUFS_CAP) /* BufferId 1: the anchor state */
    bl      app_map
    cbz     x0, 97f
    str     x0, [x19, #APP_BUFS]
    mov     x9, #1
    str     x9, [x0]
    add     x12, x19, #APP_STATE
    ldp     x10, x11, [x12]
    stp     x10, x11, [x0, #8]
    mov     x10, #APP_BUFS_CAP
    add     x12, x19, #(APP_BUFS + 8)
    stp     x9, x10, [x12]
    mov     x0, #APP_ACTIONS                /* the queues of a step */
    mov     x1, #APP_QUEUE_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_EVENTS
    mov     x1, #APP_QUEUE_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #24
    stp     x9, xzr, [x0, #8]
    mov     x0, #APP_WORK_EVENT
    mov     x1, #APP_QUEUE_BYTES
    bl      app_alloc
    cbz     x0, 97f
    bl      app_line_start                  /* started at slot <s>, fork <f>, head 0x<root> */
    ADDRESS x0, app_m_started
    mov     x1, #app_m_started_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_ANCHOR + 32)]
    bl      app_line_u64
    ADDRESS x0, app_m_fork
    mov     x1, #app_m_fork_len
    bl      app_line_text
    ldr     x0, [x19, #APP_FORK]
    bl      app_line_u64
    ADDRESS x0, app_m_head
    mov     x1, #app_m_head_len
    bl      app_line_text
    add     x0, x19, #APP_ANCHOR
    mov     x1, #32
    bl      app_line_hex
    mov     x0, #1
    bl      app_line_end
    mov     x0, #0
    LEAVE 16
94: mov     x2, x0                          /* the node: status <n> */
    ADDRESS x0, app_m_node
    mov     x1, #app_m_node_len
    bl      app_fail_status
    b       99f
97: bl      app_line_start                  /* no memory */
    ADDRESS x0, app_m_memory
    mov     x1, #app_m_memory_len
    bl      app_line_text
98: mov     x0, #2
    bl      app_line_end
99: mov     x0, #2
    LEAVE 16
END_FUNCTION app_start


/* L0: x0 = the BufferId table entry of the id x0, or 0. Uses x9-x12. */
LOCAL_FUNCTION app_buf_find
    UNWIND_END_PROLOGUE
    add     x12, x19, #APP_BUFS
    ldp     x9, x10, [x12]
1:  cbz     x10, 2f
    ldr     x11, [x9]
    cmp     x11, x0
    b.eq    3f
    add     x9, x9, #APP_BUF_ENTRY
    sub     x10, x10, #1
    b       1b
2:  mov     x0, #0
    ret
3:  mov     x0, x9
    ret
END_FUNCTION app_buf_find

/* L1: a table entry of the id x0 for the memory x1 of x2 bytes: x0 = 0, or 1 for id 0, an id in use or a full table. */
LOCAL_FUNCTION app_buf_add
    FRAME 32
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    cbz     x0, 9f
    bl      app_buf_find
    cbnz    x0, 9f
    add     x12, x19, #APP_BUFS
    ldp     x9, x10, [x12]
    ldr     x11, [x12, #16]
    cmp     x10, x11
    b.hs    9f
    mov     x11, #APP_BUF_ENTRY
    madd    x9, x10, x11, x9
    ldp     x13, x14, [sp, #16]
    stp     x13, x14, [x9]
    ldr     x13, [sp, #32]
    str     x13, [x9, #16]
    add     x10, x10, #1
    str     x10, [x12, #8]
    mov     x0, #0
    UNFRAME 32
9:  mov     x0, #1
    UNFRAME 32
END_FUNCTION app_buf_add

/* L1: the buffer of the id x0 goes back to the OS, and the last entry takes its place. */
LOCAL_FUNCTION app_buf_drop
    FRAME 16
    bl      app_buf_find
    cbz     x0, 9f
    str     x0, [sp, #16]
    add     x1, x0, #16
    add     x0, x0, #8
    CALL_GLOBAL lantern_shell_unmap
    ldr     x9, [sp, #16]
    add     x12, x19, #APP_BUFS
    ldp     x10, x11, [x12]
    sub     x11, x11, #1
    str     x11, [x12, #8]
    mov     x13, #APP_BUF_ENTRY
    madd    x10, x11, x13, x10
    ldp     x13, x14, [x10]
    stp     x13, x14, [x9]
    ldr     x13, [x10, #16]
    str     x13, [x9, #16]
9:  UNFRAME 16
END_FUNCTION app_buf_drop

/* L1: x0 = new memory with a copy of the x1 bytes at x0, or 0. x20 the source, x21 the size, x22 the copy. */
LOCAL_FUNCTION app_dup
    ENTER 0
    mov     x20, x0
    mov     x21, x1
    mov     x0, x21
    bl      app_map
    cbz     x0, 9f
    mov     x22, x0
    mov     x1, x20
    mov     x2, x21
    bl      lantern_copy
    mov     x0, x22
9:  LEAVE 0
END_FUNCTION app_dup

/*
 * L1: the x1 bytes of the event at x0 join the events of the next step, which grow when full:
 * x0 = 0, or 1 with no memory. x20 the event, x21 its size, x22 the events, x23 a new size, x24 new memory.
 */
LOCAL_FUNCTION app_event_put
    ENTER 0
    mov     x20, x0
    mov     x21, x1
1:  ldr     x22, [x19, #APP_EVENTS]
    ldr     x9, [x22]
    ldr     x10, [x22, #16]
    add     x11, x10, x21
    add     x11, x11, #24
    cmp     x11, x9
    b.ls    2f
    lsl     x23, x9, #1                     /* twice the room, and the event */
    add     x23, x23, x21
    mov     x0, x23
    bl      app_map
    cbz     x0, 9f
    mov     x24, x0
    mov     x1, x22
    ldr     x2, [x22, #16]
    add     x2, x2, #24
    bl      lantern_copy
    str     x23, [x24]
    mov     x0, #APP_EVENTS
    bl      app_unmap
    add     x9, x19, #APP_EVENTS
    stp     x24, x23, [x9]
    b       1b
2:  add     x0, x22, #24
    add     x0, x0, x10
    mov     x1, x20
    mov     x2, x21
    bl      lantern_copy
    ldr     x22, [x19, #APP_EVENTS]
    ldr     x10, [x22, #16]
    add     x10, x10, x21
    str     x10, [x22, #16]
    mov     x0, #0
    LEAVE 0
9:  mov     x0, #1
    LEAVE 0
END_FUNCTION app_event_put

/*
 * L1: the node (x0 = 0), the store (1) or the Seen (2) moves to new memory, with each field of its
 * room doubled: x0 = 0, or 1. x20 the kind, x21 the pair, x22 the room, x23 the room's fields,
 * x24 the new memory. Locals: L a size, L+8 an address.
 */
LOCAL_FUNCTION app_grow
    ENTER 16
    mov     x20, x0
    mov     x9, #APP_NODE
    mov     x10, #APP_NODE_ROOM
    mov     x23, #10
    cmp     x20, #1
    b.ne    1f
    mov     x9, #APP_STORE
    mov     x10, #APP_STORE_ROOM
    mov     x23, #2
1:  cmp     x20, #2
    b.ne    2f
    mov     x9, #APP_SEEN
    mov     x10, #APP_SEEN_ROOM
    mov     x23, #4
2:  add     x21, x19, x9
    add     x22, x19, x10
    mov     x9, #0
3:  cmp     x9, x23
    b.hs    4f
    ldr     x10, [x22, x9, lsl #3]
    lsl     x10, x10, #1
    str     x10, [x22, x9, lsl #3]
    add     x9, x9, #1
    b       3b
4:  mov     x0, x22                         /* its size */
    add     x1, sp, #L
    cbnz    x20, 41f
    CALL_GLOBAL lantern_node_size
    b       43f
41: cmp     x20, #1
    b.ne    42f
    CALL_GLOBAL lantern_store_size
    b       43f
42: CALL_GLOBAL lantern_seen_size
43: cbnz    x0, 9f
    ldr     x0, [sp, #L]
    bl      app_map
    cbz     x0, 9f
    mov     x24, x0
    ldr     x9, [sp, #L]
    str     x9, [x24]
    ldr     x0, [x21]                       /* the copy */
    mov     x1, x22
    mov     x2, x24
    cbnz    x20, 51f
    CALL_GLOBAL lantern_node_copy
    b       53f
51: cmp     x20, #1
    b.ne    52f
    CALL_GLOBAL lantern_store_copy
    b       53f
52: CALL_GLOBAL lantern_seen_copy
53: cbnz    x0, 8f
    sub     x0, x21, x19
    bl      app_unmap
    ldr     x9, [sp, #L]
    stp     x24, x9, [x21]
    mov     x0, #0
    LEAVE 16
8:  str     x24, [sp, #(L + 8)]             /* the copy failed: its memory goes back */
    add     x0, sp, #(L + 8)
    add     x1, sp, #L
    CALL_GLOBAL lantern_shell_unmap
9:  mov     x0, #1
    LEAVE 16
END_FUNCTION app_grow

/*
 * L1: the state of the BufferId table entry x0 moves to new memory with twice the StateRoom of the
 * App: x0 = 0, or 1. x20 the entry, x21 the fork, x22 the new memory. Locals: L a size, L+8 an address.
 */
LOCAL_FUNCTION app_regrow
    ENTER 16
    mov     x20, x0
    add     x9, x19, #APP_STATE_ROOM
    mov     x10, #0
1:  ldr     x11, [x9, x10, lsl #3]
    lsl     x11, x11, #1
    str     x11, [x9, x10, lsl #3]
    add     x10, x10, #1
    cmp     x10, #8
    b.lo    1b
    ldr     x9, [x20, #8]                   /* the fork of the state's slot */
    ldr     x0, [x9, #NODE_STATE_SLOT]
    add     x1, x19, #APP_CONFIG
    bl      app_fork
    mov     x21, x0
    ldr     x0, [x20, #8]
    add     x1, x19, #APP_STATE_ROOM
    add     x2, sp, #L
    mov     x15, x21
    FORK_CALL beacon_state_copy_size
    ldr     x0, [sp, #L]
    bl      app_map
    cbz     x0, 9f
    mov     x22, x0
    ldr     x9, [sp, #L]
    str     x9, [x22]
    ldr     x0, [x20, #8]
    add     x1, x19, #APP_STATE_ROOM
    mov     x2, x22
    mov     x15, x21
    FORK_CALL beacon_state_copy
    cbnz    x0, 9f
    add     x0, x20, #8
    add     x1, x20, #16
    CALL_GLOBAL lantern_shell_unmap
    ldr     x9, [sp, #L]
    stp     x22, x9, [x20, #8]
    mov     x0, #0
    LEAVE 16
9:  mov     x0, #1
    LEAVE 16
END_FUNCTION app_regrow

/*
 * L2: the WORK action x0, by lantern_node_run with its buffers, again with more room while it asks
 * for it; then its WORK_DONE event joins the next step's. x20 the action, x21-x24 the entries of
 * state_a, state_b, state_c and data (or 0), x25 the tries, x26 the kind.
 */
LOCAL_FUNCTION app_work
    ENTER 0
    mov     x20, x0
    ldr     x26, [x20, #NodeAction_work_kind]
    mov     x25, #0
    ldr     x0, [x20, #NodeAction_state_a]
    bl      app_work_entry
    mov     x21, x0
    ldr     x0, [x20, #NodeAction_state_b]
    bl      app_work_entry
    mov     x22, x0
    ldr     x0, [x20, #NodeAction_state_c]
    bl      app_work_entry
    mov     x23, x0
    ldr     x0, [x20, #NodeAction_data]
    bl      app_work_entry
    mov     x24, x0
    cmn     x21, #1                         /* an id with no buffer */
    ccmn    x22, #1, #4, ne
    ccmn    x23, #1, #4, ne
    ccmn    x24, #1, #4, ne
    b.eq    90f
1:  ldr     x9, [x19, #APP_WORK_EVENT]      /* the event's room */
    ldr     x10, [x19, #(APP_WORK_EVENT + 8)]
    str     x10, [x9]
    sub     sp, sp, #32                     /* the ninth to eleventh arguments: settings, scratch, event */
    str     xzr, [sp]
    ldr     x9, [x19, #APP_SCRATCH]
    str     x9, [sp, #8]
    ldr     x9, [x19, #APP_WORK_EVENT]
    str     x9, [sp, #16]
    ldr     x0, [x19, #APP_NODE]
    ldr     x1, [x19, #APP_STORE]
    ldr     x2, [x19, #APP_SEEN]
    mov     x3, x20
    mov     x4, #0
    cbz     x21, 11f
    ldr     x4, [x21, #8]
11: mov     x5, #0
    cbz     x22, 12f
    ldr     x5, [x22, #8]
12: mov     x6, #0
    cbz     x23, 13f
    ldr     x6, [x23, #8]
13: mov     x7, #0
    cbz     x24, 14f
    ldr     x7, [x24, #8]
14: CALL_GLOBAL lantern_node_run
    add     sp, sp, #32
    cbz     x0, 8f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.ne    91f
    add     x25, x25, #1                    /* more room: as the runner's shell */
    cmp     x25, #APP_WORK_TRIES
    b.hs    91f
    cmp     x26, #NODE_WORK_SERVE           /* SERVE, NEW_PAYLOAD, FORKCHOICE: a larger event */
    b.eq    2f
    cmp     x26, #NODE_WORK_NEW_PAYLOAD
    b.eq    2f
    cmp     x26, #NODE_WORK_FORKCHOICE
    b.eq    2f
    cmp     x26, #NODE_WORK_GOSSIP          /* GOSSIP: the Seen, and the proposer state */
    b.eq    3f
    cmp     x26, #NODE_WORK_TARGET_STATE    /* TARGET_STATE, and IMPORT_BLOCK with store room: state_a */
    b.eq    4f
    cmp     x26, #NODE_WORK_IMPORT_BLOCK
    b.ne    5f
    ldr     x9, [x19, #APP_STORE]
    ldr     x9, [x9, #(Store_blocks + 8)]
    ldr     x10, [x19, #(APP_STORE_ROOM + StoreRoom_nodes)]
    cmp     x9, x10
    b.lo    4f
5:  mov     x0, #1                          /* else the store */
    bl      app_grow
    cbnz    x0, 91f
    b       1b
2:  ldr     x9, [x19, #(APP_WORK_EVENT + 8)]
    lsl     x1, x9, #2
    mov     x0, #APP_WORK_EVENT
    str     x1, [sp, #-16]!
    bl      app_unmap
    ldr     x1, [sp], #16
    mov     x0, #APP_WORK_EVENT
    bl      app_alloc
    cbz     x0, 91f
    b       1b
3:  mov     x0, #2                          /* the Seen */
    bl      app_grow
    cbnz    x0, 91f
    cbz     x22, 1b
    mov     x0, x22
    bl      app_regrow
    cbnz    x0, 91f
    b       1b
4:  cbz     x21, 91f
    mov     x0, x21
    bl      app_regrow
    cbnz    x0, 91f
    b       1b
8:  ldr     x0, [x19, #APP_WORK_EVENT]      /* the WORK_DONE event */
    ldr     x1, [x0]
    bl      app_event_put
    LEAVE 0
90: ADDRESS x0, app_m_buffer                /* an action's BufferId: status 0 */
    mov     x1, #app_m_buffer_len
    mov     x2, #0
    bl      app_fail_status
    LEAVE 0
91: mov     x2, x0                          /* a work: status <n> */
    ADDRESS x0, app_m_work
    mov     x1, #app_m_work_len
    bl      app_fail_status
    LEAVE 0
END_FUNCTION app_work

/* L0: x0 = the table entry of the BufferId x0, 0 for id 0, or 2^64 - 1 when no entry has it. Uses x9-x12, x13. */
LOCAL_FUNCTION app_work_entry
    UNWIND_END_PROLOGUE
    cbz     x0, 9f
    mov     x13, x30
    bl      app_buf_find
    mov     x30, x13
    cbnz    x0, 9f
    mov     x0, #-1
9:  ret
END_FUNCTION app_work_entry

/*
 * L2: the actions of the step, in order: BYTES_PUT, STATE_COPY, STATE_FREE and BYTES_FREE on the
 * BufferId table, WORK by app_work. x20 the next action, x21 the end, x22 its size, x23 an entry.
 */
LOCAL_FUNCTION app_actions
    ENTER 0
    ldr     x20, [x19, #APP_ACTIONS]
    ldr     x21, [x20, #16]
    add     x20, x20, #24
    add     x21, x20, x21
1:  cmp     x20, x21
    b.hs    9f
    ldr     x22, [x20]
    ldr     x9, [x20, #8]
    cmp     x9, #NODE_ACT_BYTES_PUT
    b.ne    2f
    add     x0, x20, #24                    /* BYTES_PUT: a copy of the ByteList */
    ldr     x1, [x20, #24]
    bl      app_dup
    cbz     x0, 8f
    mov     x1, x0
    ldr     x0, [x20, #16]
    ldr     x2, [x20, #24]
    bl      app_buf_add
    b       8f
2:  cmp     x9, #NODE_ACT_STATE_COPY
    b.ne    3f
    ldr     x0, [x20, #16]                  /* STATE_COPY: a copy of the source buffer */
    bl      app_buf_find
    cbz     x0, 8f
    mov     x23, x0
    ldp     x0, x1, [x23, #8]
    bl      app_dup
    cbz     x0, 8f
    mov     x1, x0
    ldr     x0, [x20, #24]
    ldr     x2, [x23, #16]
    bl      app_buf_add
    b       8f
3:  cmp     x9, #NODE_ACT_STATE_FREE
    ccmp    x9, #NODE_ACT_BYTES_FREE, #4, ne
    b.ne    4f
    ldr     x0, [x20, #16]                  /* STATE_FREE, BYTES_FREE */
    bl      app_buf_drop
    b       8f
4:  cmp     x9, #NODE_ACT_WORK
    b.ne    5f
    mov     x0, x20
    bl      app_work
    b       8f
5:  cmp     x9, #NODE_ACT_ENGINE
    b.ne    6f
    mov     x0, x20
    bl      app_engine_request
    b       8f
6:  cmp     x9, #NODE_ACT_DISCV5
    b.ne    7f
    ldr     x9, [x20, #(24 + 8)]            /* DISCV5: its events join discv5's */
    add     x0, x20, #24
    add     x0, x0, x9
    ldr     x1, [x20, #(24 + 16)]
    bl      app_dv_put
    b       8f
7:  cmp     x9, #NODE_ACT_P2P_LIST
    b.ne    8f
    ldr     x0, [x19, #APP_SHELL]           /* P2P_LIST: the shell requests of libp2p */
    add     x1, x20, #16
    ldr     x2, [x19, #APP_SHELL_EVENTS]
    CALL_GLOBAL libp2p_shell_perform
8:  add     x20, x20, x22
    b       1b
9:  LEAVE 0
END_FUNCTION app_actions

/*
 * L2: lantern_node_step with the events of the App and the libp2p state x0 and Tick x1 (both 0 with
 * no network), again with a larger node and actions while it asks for them; then the accepted
 * events leave the queue and the actions run. x20 p2p, x21 tick, x22 the tries.
 */
LOCAL_FUNCTION app_step
    ENTER 0
    mov     x20, x0
    mov     x21, x1
    mov     x22, #0
1:  ldr     x9, [x19, #APP_ACTIONS]
    mov     x10, #24
    stp     x10, xzr, [x9, #8]
    ldr     x0, [x19, #APP_NODE]
    ldr     x1, [x19, #APP_STORE]
    mov     x2, x20
    mov     x3, x21
    ldr     x4, [x19, #APP_EVENTS]
    ldr     x5, [x19, #APP_SCRATCH]
    ldr     x6, [x19, #APP_ACTIONS]
    add     x7, x19, #APP_RESULT
    CALL_GLOBAL lantern_node_step
    cbz     x0, 3f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.ne    2f
    add     x22, x22, #1
    cmp     x22, #APP_WORK_TRIES
    b.hs    2f
    mov     x0, #0                          /* a larger node, and twice the actions */
    bl      app_grow
    cbnz    x0, 2f
    ldr     x9, [x19, #(APP_ACTIONS + 8)]
    lsl     x1, x9, #1
    str     x1, [sp, #-16]!
    mov     x0, #APP_ACTIONS
    bl      app_unmap
    ldr     x1, [sp], #16
    mov     x0, #APP_ACTIONS
    bl      app_alloc
    cbz     x0, 2f
    b       1b
2:  mov     x2, x0                          /* a node step: status <n> */
    ADDRESS x0, app_m_step
    mov     x1, #app_m_step_len
    bl      app_fail_status
    LEAVE 0
3:  ldr     x9, [x19, #APP_EVENTS]          /* the accepted events leave the queue */
    ldr     x10, [x9, #16]
    add     x11, x9, #24
    mov     x12, #0
    ldr     x13, [x19, #APP_RESULT]
4:  cbz     x13, 5f
    cmp     x12, x10
    b.hs    5f
    ldr     x14, [x11, x12]
    add     x12, x12, x14
    sub     x13, x13, #1
    b       4b
5:  sub     x2, x10, x12
    str     x2, [x9, #16]
    mov     x0, x11
    add     x1, x11, x12
    bl      lantern_copy
    bl      app_actions
    LEAVE 0
END_FUNCTION app_step


/*
 * L0: x0 = the bytes of the base64url text at x0 of x1 bytes (RFC 4648 section 5, with or without
 * padding), written at x2, at most x3; or 2^64 - 1 for a byte of no digit or too many bytes. Uses x9-x15.
 */
LOCAL_FUNCTION app_base64url
    UNWIND_END_PROLOGUE
    mov     x9, #0                          /* the bits */
    mov     x10, #0                         /* their count */
    mov     x11, #0                         /* the bytes out */
1:  cbz     x1, 8f
    ldrb    w12, [x0], #1
    sub     x1, x1, #1
    cmp     w12, #0x3d                      /* = ends the digits */
    b.eq    8f
    sub     w13, w12, #0x41                 /* A to Z: 0 to 25 */
    cmp     w13, #26
    b.lo    2f
    sub     w13, w12, #0x61                 /* a to z: 26 to 51 */
    cmp     w13, #26
    add     w13, w13, #26
    b.lo    2f
    sub     w13, w12, #0x30                 /* 0 to 9: 52 to 61 */
    cmp     w13, #10
    add     w13, w13, #52
    b.lo    2f
    mov     w13, #62
    cmp     w12, #0x2d                      /* - */
    b.eq    2f
    mov     w13, #63
    cmp     w12, #0x5f                      /* _ */
    b.ne    9f
2:  orr     x9, x13, x9, lsl #6
    add     x10, x10, #6
    cmp     x10, #8
    b.lo    1b
    sub     x10, x10, #8
    cmp     x11, x3
    b.hs    9f
    lsr     x14, x9, x10
    strb    w14, [x2, x11]
    add     x11, x11, #1
    mov     x15, #1                         /* only the bits not yet out stay */
    lsl     x15, x15, x10
    sub     x15, x15, #1
    and     x9, x9, x15
    b       1b
8:  mov     x0, x11
    ret
9:  mov     x0, #-1
    ret
END_FUNCTION app_base64url

/*
 * L2: a NODE_EV_ENR event of each record of --boot-nodes, with commas between them; a line on
 * the standard error for one that is not "enr:" and base64url. x20 the next byte, x21 the end, x22
 * the record's start, x23 the record's number, x24 the event at APP_RECORD. Locals: L the record's length.
 */
LOCAL_FUNCTION app_boot_nodes
    ENTER 16
    add     x24, x19, #APP_RECORD
    ldr     x9, [x19, #APP_ARGS]
    ldp     x10, x11, [x19, #(APP_OPTIONS + AppOptions_boot_nodes)]
    add     x20, x9, x10
    add     x21, x20, x11
    mov     x23, #0
1:  cmp     x20, x21
    b.hs    9f
    mov     x22, x20                        /* a record: to a comma or the end */
2:  cmp     x20, x21
    b.hs    3f
    ldrb    w9, [x20]
    cmp     w9, #0x2c
    b.eq    3f
    add     x20, x20, #1
    b       2b
3:  sub     x1, x20, x22
    add     x20, x20, #1                    /* past the comma */
    add     x23, x23, #1
    cmp     x1, #4
    b.lo    7f
    mov     x0, x22
    str     x1, [sp, #L]
    mov     x1, #4
    ADDRESS x2, app_enr_prefix
    mov     x3, #4
    bl      app_name_is
    cbz     x0, 7f
    add     x0, x22, #4                     /* its bytes, after the event and ByteList headers */
    ldr     x1, [sp, #L]
    sub     x1, x1, #4
    add     x2, x24, #48
    mov     x3, #APP_RECORD_MAX
    bl      app_base64url
    cmn     x0, #1
    b.eq    7f
    add     x9, x0, #(48 + 7)               /* the event: size, NODE_EV_ENR, 0, then the ByteList */
    and     x9, x9, #~7
    mov     x10, #NODE_EV_ENR
    stp     x9, x10, [x24]
    sub     x11, x9, #24
    stp     xzr, x11, [x24, #16]
    mov     x12, #24
    stp     x12, x0, [x24, #32]
    mov     x0, x24
    mov     x1, x9
    bl      app_event_put
    ldr     x9, [x24, #40]                  /* and an ADD_NODE of discv5: size, kind, len, the record */
    add     x10, x9, #(DISCV5_EV_ADD_DATA + 7)
    and     x10, x10, #~7
    mov     x11, #DISCV5_EVENT_ADD_NODE
    stp     x10, x11, [x24, #24]
    str     x9, [x24, #(24 + DISCV5_EV_ADD_LEN)]
    add     x0, x24, #24
    mov     x1, x10
    bl      app_dv_put
    b       1b
7:  bl      app_line_start                  /* boot node <n>: not an enr: record */
    ADDRESS x0, app_m_boot
    mov     x1, #app_m_boot_len
    bl      app_line_text
    mov     x0, x23
    bl      app_line_u64
    ADDRESS x0, app_m_not_enr
    mov     x1, #app_m_not_enr_len
    bl      app_line_text
    mov     x0, #2
    bl      app_line_end
    b       1b
9:  LEAVE 16
END_FUNCTION app_boot_nodes

/*
 * L2: the network: a secp256k1 key, the libp2p state, the shell context with a TCP listener on
 * --port, and the boot nodes: x0 = 0, or 2 after a line on the standard error. x20 the config,
 * x21 the tries. Locals: L a size or a status, L+8 ShellParams, L+32 an Address, L+64 a ListenResult.
 */
LOCAL_FUNCTION app_net
    ENTER 112
    mov     x0, #APP_P2P_CONFIG             /* the config: the template, then the protocols */
    MOVQ    x1, LIBP2P_CFG_FIXED + 24 + APP_PROTOCOLS_MAX * LIBP2P_PROTO_SIZE
    bl      app_alloc
    cbz     x0, 97f
    mov     x20, x0
    ADDRESS x1, app_p2p_config
    mov     x2, #LIBP2P_CFG_FIXED
    bl      lantern_copy
    add     x0, x20, #LIBP2P_CFG_FIXED
    MOVQ    x9, 24 + APP_PROTOCOLS_MAX * LIBP2P_PROTO_SIZE
    mov     x10, #24
    stp     x9, x10, [x0]
    str     xzr, [x0, #16]
    add     x1, sp, #L
    CALL_GLOBAL lantern_node_protocols
    cbnz    x0, 96f
    ldr     x9, [sp, #L]
    mov     x10, #(LIBP2P_CFG_FIXED + 24)
    stp     x10, x9, [x20, #208]            /* protocols, protocols_count */
    mov     x11, #LIBP2P_PROTO_SIZE
    madd    x9, x9, x11, x10
    str     x9, [x20]
    mov     x21, #0
1:  add     x0, x19, #APP_TICK              /* a key from fresh random bytes, below the order of the curve */
    CALL_GLOBAL libp2p_shell_clock
    add     x0, x20, #16
    add     x1, x19, #(APP_TICK + LIBP2P_TICK_ENTROPY)
    mov     x2, #32
    bl      lantern_copy
    ldrb    w9, [x20, #16]
    and     w9, w9, #0x7f
    strb    w9, [x20, #16]
    add     x0, x19, #APP_KEY
    add     x1, x20, #16
    mov     x2, #32
    bl      lantern_copy
    add     x0, x19, #APP_TICK              /* the DRBG's entropy, and the time */
    CALL_GLOBAL libp2p_shell_clock
    add     x0, x20, #48
    add     x1, x19, #(APP_TICK + LIBP2P_TICK_ENTROPY)
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    str     x9, [x20, #80]
    mov     x0, x20                         /* the libp2p state */
    add     x1, sp, #L
    CALL_GLOBAL libp2p_state_size
    cbnz    x0, 96f
    mov     x0, #APP_P2P
    ldr     x1, [sp, #L]
    bl      app_alloc
    cbz     x0, 97f
    mov     x1, x0
    mov     x0, x20
    CALL_GLOBAL libp2p_init
    cbz     x0, 2f
    cmp     x0, #LIBP2P_INVALID_KEY
    b.ne    96f
    mov     x0, #APP_P2P
    bl      app_unmap
    add     x21, x21, #1
    cmp     x21, #4
    b.lo    1b
    mov     x0, #LIBP2P_INVALID_KEY
    b       96f
2:  ldr     x9, [x20, #88]                  /* the shell: a slot for each connection, and one for the execution engine */
    add     x9, x9, #1
    ldr     x10, [x20, #160]
    stp     x9, x10, [sp, #(L + 8)]
    add     x0, sp, #(L + 8)
    add     x1, sp, #L
    CALL_GLOBAL libp2p_shell_size
    cbnz    x0, 96f
    mov     x0, #APP_SHELL
    ldr     x1, [sp, #L]
    bl      app_alloc
    cbz     x0, 97f
    mov     x1, x0
    add     x0, sp, #(L + 8)
    CALL_GLOBAL libp2p_shell_init
    cbnz    x0, 96f
    mov     x0, #APP_SHELL_EVENTS
    MOVQ    x1, APP_SHELL_EVENT_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #24
    stp     x9, xzr, [x0, #8]
    ldr     x9, [x20, #160]                 /* the engine's action: a SEND of up to send_window bytes */
    add     x1, x9, #(24 + LIBP2P_ACT_SEND_DATA + 8)
    mov     x0, #APP_ENGINE_ACT
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #24
    stp     x9, xzr, [x0, #8]
    mov     x9, #4                          /* listen: TCP --port on every IPv4 address */
    ldr     x10, [x19, #(APP_OPTIONS + AppOptions_port)]
    stp     x9, x10, [sp, #(L + 32)]
    stp     xzr, xzr, [sp, #(L + 48)]
    ldr     x0, [x19, #APP_SHELL]
    add     x1, sp, #(L + 32)
    add     x2, sp, #(L + 64)
    CALL_GLOBAL libp2p_shell_listen
    ldr     x9, [sp, #(L + 64)]
    cbz     x9, 3f
    bl      app_line_start                  /* listen on TCP port <p>: error <n> */
    ADDRESS x0, app_m_listen
    mov     x1, #app_m_listen_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_port)]
    bl      app_line_u64
    ADDRESS x0, app_m_error
    mov     x1, #app_m_error_len
    bl      app_line_text
    ldr     x0, [sp, #(L + 64)]
    bl      app_line_u64
    mov     x0, #2
    bl      app_line_end
    mov     x0, #2
    LEAVE 112
3:  bl      app_api_start
    cbnz    x0, 99f
    bl      app_dv_start
    cbnz    x0, 99f
    bl      app_boot_nodes
    bl      app_line_start                  /* listening on TCP port <p> */
    ADDRESS x0, app_m_listening
    mov     x1, #app_m_listening_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_port)]
    bl      app_line_u64
    mov     x0, #1
    bl      app_line_end
    mov     x0, #0
    LEAVE 112
99: LEAVE 112
96: mov     x2, x0                          /* libp2p: status <n> */
    ADDRESS x0, app_m_p2p
    mov     x1, #app_m_p2p_len
    bl      app_fail_status
    LEAVE 112
97: bl      app_line_start                  /* no memory */
    ADDRESS x0, app_m_memory
    mov     x1, #app_m_memory_len
    bl      app_line_text
    mov     x0, #2
    bl      app_line_end
    mov     x0, #2
    LEAVE 112
END_FUNCTION app_net

/* L0: x0 = 0 and x1 = the u64 of the decimal digits x0 to x1, one or more; else x0 = 1. Uses x9-x12. */
LOCAL_FUNCTION app_number
    UNWIND_END_PROLOGUE
    cmp     x0, x1
    b.hs    9f
    mov     x9, #0
1:  cmp     x0, x1
    b.hs    8f
    ldrb    w10, [x0], #1
    sub     w10, w10, #0x30
    cmp     w10, #9
    b.hi    9f
    mov     x11, #10
    umulh   x12, x9, x11
    cbnz    x12, 9f
    mul     x9, x9, x11
    adds    x9, x9, x10
    b.cs    9f
    b       1b
8:  mov     x1, x9
    mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION app_number

/* L0: x0 = 0 and x1 = the IPv4 address of the bytes x0 to x1, its 4 bytes in order in the low bytes; else x0 = 1. Uses x9-x14. */
LOCAL_FUNCTION app_dotted
    UNWIND_END_PROLOGUE
    mov     x9, #0
    mov     x10, #0
    mov     x13, #0
1:  mov     x11, #0
    mov     x12, #0
2:  cmp     x0, x1
    b.hs    3f
    ldrb    w14, [x0]
    cmp     w14, #0x2e
    b.eq    3f
    sub     w14, w14, #0x30
    cmp     w14, #9
    b.hi    9f
    add     x12, x12, #1
    cmp     x12, #3
    b.hi    9f
    add     x11, x11, x11, lsl #2
    lsl     x11, x11, #1
    add     x11, x11, x14
    add     x0, x0, #1
    b       2b
3:  cbz     x12, 9f
    cmp     x11, #255
    b.hi    9f
    lsl     x11, x11, x13
    orr     x9, x9, x11
    add     x13, x13, #8
    add     x10, x10, #1
    cmp     x0, x1
    b.hs    4f
    add     x0, x0, #1
    cmp     x10, #4
    b.hs    9f
    b       1b
4:  cmp     x10, #4
    b.ne    9f
    mov     x1, x9
    mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION app_dotted

/*
 * L2: with --execution-endpoint, the engine: its Address, the anchor's engine_host and the
 * jwt_secret of --jwt-secret, and NODE_FLAG_ENGINE: x0 = 0, or 2 after a line on the standard
 * error. x20 the endpoint's bytes, x21 their count, x22 the colon, x23 the secret's next byte, x24
 * its end.
 */
LOCAL_FUNCTION app_engine_conf
    ENTER 0
    ldp     x20, x21, [x19, #(APP_OPTIONS + AppOptions_execution)]
    cbz     x21, 8f
    ldr     x9, [x19, #APP_ARGS]
    add     x20, x9, x20
    cmp     x21, #NODE_ENGINE_HOST_MAX      /* the Host of each request */
    b.hi    90f
    str     x21, [x19, #(APP_ANCHOR + NodeAnchor_engine_host_len)]
    add     x0, x19, #(APP_ANCHOR + NodeAnchor_engine_host)
    mov     x1, x20
    mov     x2, x21
    bl      lantern_copy
    mov     x22, x21                        /* the last colon */
1:  cbz     x22, 90f
    sub     x22, x22, #1
    ldrb    w9, [x20, x22]
    cmp     w9, #0x3a
    b.ne    1b
    add     x0, x20, x22                    /* the port */
    add     x0, x0, #1
    add     x1, x20, x21
    bl      app_number
    cbnz    x0, 90f
    cbz     x1, 90f
    mov     x9, #65535
    cmp     x1, x9
    b.hi    90f
    mov     x9, #4
    add     x10, x19, #APP_ENGINE_ADDR
    stp     x9, x1, [x10]
    stp     xzr, xzr, [x10, #16]
    mov     x0, x20                         /* the host: localhost, or an IPv4 address */
    mov     x1, x22
    ADDRESS x2, app_localhost
    mov     x3, #9
    bl      app_name_is
    MOVQ    x1, 0x0100007f                  /* 127.0.0.1 */
    cbnz    x0, 2f
    mov     x0, x20
    add     x1, x20, x22
    bl      app_dotted
    cbnz    x0, 90f
2:  str     w1, [x19, #(APP_ENGINE_ADDR + 16)]
    ldp     x9, x10, [x19, #(APP_OPTIONS + AppOptions_jwt_secret)]  /* the secret's path */
    cbz     x10, 91f
    mov     x11, #APP_PATH_MAX
    cmp     x10, x11
    b.hi    91f
    ADDQ    x11, x19, APP_PATH
    str     x10, [x11, #16]
    add     x0, x11, #24
    ldr     x12, [x19, #APP_ARGS]
    add     x1, x12, x9
    mov     x2, x10
    bl      lantern_copy
    bl      app_read
    cbnz    x0, 99f
    ldr     x9, [x19, #(APP_FILE + 8)]      /* 64 hex digits, after 0x or not, with white space around them */
    ldr     x10, [x9, #16]
    add     x23, x9, #24
    add     x24, x23, x10
    bl      app_space
    sub     x9, x24, x23
    cmp     x9, #2
    b.lo    3f
    ldrb    w9, [x23]
    ldrb    w10, [x23, #1]
    cmp     w9, #0x30
    b.ne    3f
    cmp     w10, #0x78
    b.ne    3f
    add     x23, x23, #2
3:  mov     x22, #0
4:  cmp     x22, #32
    b.hs    5f
    sub     x9, x24, x23
    cmp     x9, #2
    b.lo    92f
    ldrb    w0, [x23]
    bl      app_hex_digit
    mov     x10, x0
    ldrb    w0, [x23, #1]
    bl      app_hex_digit
    orr     x9, x0, x10
    cmp     x9, #15
    b.hi    92f
    orr     x10, x0, x10, lsl #4
    add     x11, x19, #(APP_ANCHOR + NodeAnchor_jwt_secret)
    strb    w10, [x11, x22]
    add     x23, x23, #2
    add     x22, x22, #1
    b       4b
5:  bl      app_space
    cmp     x23, x24
    b.ne    92f
    bl      app_file_free
    ldr     x9, [x19, #APP_FLAGS]
    orr     x9, x9, #NODE_FLAG_ENGINE
    str     x9, [x19, #APP_FLAGS]
8:  mov     x0, #0
    LEAVE 0
90: bl      app_line_start                  /* the endpoint's form */
    ADDRESS x0, app_m_endpoint
    mov     x1, #app_m_endpoint_len
    bl      app_line_text
    b       98f
91: bl      app_line_start                  /* no secret */
    ADDRESS x0, app_m_jwt
    mov     x1, #app_m_jwt_len
    bl      app_line_text
    b       98f
92: bl      app_file_free                   /* <path>: not 32 bytes in hex */
    bl      app_line_start
    bl      app_line_path
    ADDRESS x0, app_m_hex
    mov     x1, #app_m_hex_len
    bl      app_line_text
98: mov     x0, #2
    bl      app_line_end
99: mov     x0, #2
    LEAVE 0
END_FUNCTION app_engine_conf

/* L0: x23 moves past spaces, tabs, CR and LF, to at most x24. Uses x9. */
LOCAL_FUNCTION app_space
    UNWIND_END_PROLOGUE
1:  cmp     x23, x24
    b.hs    2f
    ldrb    w9, [x23]
    cmp     w9, #0x20
    b.eq    3f
    cmp     w9, #9
    b.lo    2f
    cmp     w9, #13
    b.hi    2f
3:  add     x23, x23, #1
    b       1b
2:  ret
END_FUNCTION app_space

/* L0: x0 = the value of the hex digit x0, or 16 when it is not one. */
LOCAL_FUNCTION app_hex_digit
    UNWIND_END_PROLOGUE
    sub     w9, w0, #0x30
    cmp     w9, #10
    b.lo    1f
    orr     w9, w0, #0x20
    sub     w9, w9, #0x61
    cmp     w9, #6
    add     w9, w9, #10
    b.lo    1f
    mov     w9, #16
1:  mov     x0, x9
    ret
END_FUNCTION app_hex_digit

/* L0: x0 = the Handle of the engine's connection: the slot after libp2p's, at its generation. Uses x9. */
LOCAL_FUNCTION app_engine_handle
    UNWIND_END_PROLOGUE
    ldr     x9, [x19, #APP_P2P_CONFIG]
    ldr     x0, [x9, #88]                   /* max_connections */
    ldr     x9, [x19, #APP_ENGINE_GEN]
    orr     x0, x0, x9, lsl #32
    ret
END_FUNCTION app_engine_handle

/*
 * L1: one shell action, the x1 bytes at x0, in the ByteList at APP_ENGINE_ACT, through
 * libp2p_shell_perform; its results join the shell's events.
 */
LOCAL_FUNCTION app_engine_perform
    FRAME 0
    ldr     x9, [x19, #APP_ENGINE_ACT]
    str     x1, [x9, #16]
    ldr     x0, [x19, #APP_SHELL]
    mov     x1, x9
    ldr     x2, [x19, #APP_SHELL_EVENTS]
    CALL_GLOBAL libp2p_shell_perform
    UNFRAME 0
END_FUNCTION app_engine_perform

/*
 * L2: the next bytes of the request on the open connection, as far as the shell's send buffer has
 * room. x20 the action, x21 the bytes.
 */
LOCAL_FUNCTION app_engine_send
    ENTER 0
    ldr     x9, [x19, #APP_ENGINE]
    cmp     x9, #2
    b.ne    9f
    ldr     x9, [x19, #APP_ENGINE_LEN]
    ldr     x10, [x19, #APP_ENGINE_SENT]
    sub     x21, x9, x10
    cbz     x21, 9f
    ldr     x11, [x19, #APP_P2P_CONFIG]
    ldr     x11, [x11, #160]                /* send_window */
    ldr     x12, [x19, #APP_ENGINE_FLIGHT]
    subs    x11, x11, x12
    b.ls    9f
    cmp     x21, x11
    csel    x21, x21, x11, ls
    ldr     x20, [x19, #APP_ENGINE_ACT]     /* SEND: connection, count, the bytes */
    add     x20, x20, #24
    add     x9, x21, #(LIBP2P_ACT_SEND_DATA + 7)
    and     x9, x9, #~7
    mov     x10, #LIBP2P_ACTION_SEND
    stp     x9, x10, [x20]
    bl      app_engine_handle
    stp     x0, x21, [x20, #LIBP2P_ACT_CONN]
    add     x0, x20, #LIBP2P_ACT_SEND_DATA
    ldr     x1, [x19, #APP_ENGINE_OUT]
    ldr     x9, [x19, #APP_ENGINE_SENT]
    add     x1, x1, x9
    mov     x2, x21
    bl      lantern_copy
    ldr     x9, [x19, #APP_ENGINE_SENT]
    add     x9, x9, x21
    str     x9, [x19, #APP_ENGINE_SENT]
    ldr     x9, [x19, #APP_ENGINE_FLIGHT]
    add     x9, x9, x21
    str     x9, [x19, #APP_ENGINE_FLIGHT]
    mov     x0, x20
    ldr     x1, [x20]
    bl      app_engine_perform
9:  LEAVE 0
END_FUNCTION app_engine_send

/*
 * L2: the NODE_ACT_ENGINE x0: its request bytes wait in APP_ENGINE_OUT; they go on the open
 * connection, or after a DIAL of the engine's Address. x20 the ByteList, x21 the count.
 */
LOCAL_FUNCTION app_engine_request
    ENTER 0
    add     x20, x0, #24
    ldr     x21, [x20, #16]
    ldr     x9, [x19, #(APP_ENGINE_OUT + 8)]   /* room for the request */
    cmp     x21, x9
    b.ls    1f
    mov     x0, #APP_ENGINE_OUT
    bl      app_unmap
    mov     x0, #APP_ENGINE_OUT
    mov     x1, x21
    bl      app_alloc
    cbz     x0, 9f
1:  ldr     x0, [x19, #APP_ENGINE_OUT]
    ldr     x9, [x20, #8]
    add     x1, x20, x9
    mov     x2, x21
    bl      lantern_copy
    str     x21, [x19, #APP_ENGINE_LEN]
    str     xzr, [x19, #APP_ENGINE_SENT]
    ldr     x9, [x19, #APP_ENGINE]
    cmp     x9, #2
    b.ne    2f
    bl      app_engine_send
    LEAVE 0
2:  cbnz    x9, 9f                          /* no connection: a DIAL */
    ldr     x9, [x19, #APP_ENGINE_GEN]
    add     x9, x9, #1
    str     x9, [x19, #APP_ENGINE_GEN]
    mov     x9, #1
    str     x9, [x19, #APP_ENGINE]
    str     xzr, [x19, #APP_ENGINE_FLIGHT]
    ldr     x20, [x19, #APP_ENGINE_ACT]
    add     x20, x20, #24
    mov     x9, #LIBP2P_ACT_DIAL_SIZE
    mov     x10, #LIBP2P_ACTION_DIAL
    stp     x9, x10, [x20]
    bl      app_engine_handle
    str     x0, [x20, #LIBP2P_ACT_CONN]
    add     x0, x20, #LIBP2P_ACT_DIAL_ADDR
    add     x1, x19, #APP_ENGINE_ADDR
    mov     x2, #32
    bl      lantern_copy
    mov     x0, x20
    mov     x1, #LIBP2P_ACT_DIAL_SIZE
    bl      app_engine_perform
9:  LEAVE 0
END_FUNCTION app_engine_request

/*
 * L2: x0 = 1 when the shell event x0 is of the engine's connection, which it then takes: CONNECTED
 * opens it, SENT frees its buffer, RECEIVED gives a NODE_EV_ENGINE of the bytes, DIAL_FAILED and
 * CLOSED end it with a NODE_EV_ENGINE of failure while the node waits for an answer; else 0.
 * x20 the event, x21 its kind. Locals: L the header of an event.
 */
LOCAL_FUNCTION app_engine_event
    ENTER 48
    mov     x20, x0
    ldr     x21, [x20, #8]
    cmp     x21, #LIBP2P_EVENT_CONNECTED
    b.lo    8f
    cmp     x21, #LIBP2P_EVENT_CLOSED
    b.hi    8f
    ldr     x9, [x19, #APP_ENGINE]
    cbz     x9, 8f
    bl      app_engine_handle
    ldr     x9, [x20, #LIBP2P_EV_CONN]
    cmp     x9, x0
    b.ne    8f
    cmp     x21, #LIBP2P_EVENT_CONNECTED
    b.ne    1f
    mov     x9, #2
    str     x9, [x19, #APP_ENGINE]
    str     xzr, [x19, #APP_ENGINE_FLIGHT]
    mov     x9, #1
    str     x9, [x19, #APP_ENGINE_DUE]
    b       9f
1:  cmp     x21, #LIBP2P_EVENT_SENT
    b.ne    2f
    ldr     x9, [x19, #APP_ENGINE_FLIGHT]
    ldr     x10, [x20, #LIBP2P_EV_COUNT]
    subs    x9, x9, x10
    csel    x9, xzr, x9, lo
    str     x9, [x19, #APP_ENGINE_FLIGHT]
    mov     x9, #1
    str     x9, [x19, #APP_ENGINE_DUE]
    b       9f
2:  cmp     x21, #LIBP2P_EVENT_RECEIVED
    b.ne    3f
    ldr     x9, [x20, #LIBP2P_EV_COUNT]     /* NODE_EV_ENGINE 0: size, kind, 0, a ByteList, the bytes */
    add     x10, x9, #(48 + 7)
    and     x10, x10, #~7
    mov     x11, #NODE_EV_ENGINE
    stp     x10, x11, [sp, #L]
    sub     x11, x10, #24
    stp     xzr, x11, [sp, #(L + 16)]
    mov     x12, #24
    stp     x12, x9, [sp, #(L + 32)]
    add     x0, sp, #L
    mov     x1, #48
    bl      app_event_put
    add     x0, x20, #LIBP2P_EV_DATA
    ldr     x1, [x20, #LIBP2P_EV_COUNT]
    add     x1, x1, #7
    and     x1, x1, #~7
    bl      app_event_put
    b       9f
3:  str     xzr, [x19, #APP_ENGINE]         /* DIAL_FAILED, CLOSED */
    str     xzr, [x19, #APP_ENGINE_LEN]
    str     xzr, [x19, #APP_ENGINE_SENT]
    ldr     x9, [x19, #APP_NODE]
    ldr     x9, [x9, #Node_engine_method]
    cbz     x9, 9f
    mov     x9, #24                         /* NODE_EV_ENGINE 1 */
    mov     x10, #NODE_EV_ENGINE
    stp     x9, x10, [sp, #L]
    mov     x9, #1
    str     x9, [sp, #(L + 16)]
    add     x0, sp, #L
    mov     x1, #24
    bl      app_event_put
9:  mov     x0, #1
    LEAVE 48
8:  mov     x0, #0
    LEAVE 48
END_FUNCTION app_engine_event

/* L1: the base64url text (RFC 4648 section 5, no padding) of the x1 bytes at x0 joins the log line. Locals: x0, x1, the bits, then 4 digits. */
LOCAL_FUNCTION app_line_base64url
    FRAME 48
    stp     x0, x1, [sp, #16]
1:  ldp     x0, x1, [sp, #16]
    cbz     x1, 9f
    mov     x9, #0                          /* up to 3 bytes: 24 bits, from the top */
    mov     x10, #0
2:  cmp     x10, #3
    b.hs    3f
    cbz     x1, 3f
    ldrb    w11, [x0], #1
    sub     x1, x1, #1
    lsl     x12, x10, #3
    mov     x13, #16
    sub     x12, x13, x12
    lsl     x11, x11, x12
    orr     x9, x9, x11
    add     x10, x10, #1
    b       2b
3:  stp     x0, x1, [sp, #16]
    ADDRESS x13, app_base64url_digits       /* 1 byte: 2 digits; 2: 3; 3: 4 */
    mov     x11, #0
4:  cmp     x11, #4
    b.hs    5f
    mov     x12, #18
    mov     x14, #6
    msub    x12, x11, x14, x12
    lsr     x14, x9, x12
    and     x14, x14, #63
    ldrb    w14, [x13, x14]
    add     x15, sp, #40
    strb    w14, [x15, x11]
    add     x11, x11, #1
    b       4b
5:  add     x0, sp, #40
    add     x1, x10, #1
    bl      app_line_text
    b       1b
9:  UNFRAME 48
END_FUNCTION app_line_base64url

/* L1: the x1 bytes of the event at x0 join the next discv5 step's events, while they have room. Uses x9-x11. */
LOCAL_FUNCTION app_dv_put
    FRAME 0
    ldr     x9, [x19, #APP_DV_EVENTS]
    ldr     x10, [x9, #16]
    add     x11, x10, x1
    add     x11, x11, #24
    ldr     x12, [x9]
    cmp     x11, x12
    b.hi    9f
    str     x11, [sp, #-16]!
    mov     x2, x1
    mov     x1, x0
    add     x0, x9, #24
    add     x0, x0, x10
    bl      lantern_copy
    ldr     x11, [sp], #16
    ldr     x9, [x19, #APP_DV_EVENTS]
    sub     x11, x11, #24
    str     x11, [x9, #16]
9:  UNFRAME 0
END_FUNCTION app_dv_put

/*
 * L2: discv5 with the key of libp2p: its state, with --enr-address and --port in the record, its UDP
 * socket on --port, and the record entry tcp: x0 = 0, or 2 after a line on the standard error.
 * Locals: L the Config (152), then an Address and a BindResult, and the tcp event.
 */
LOCAL_FUNCTION app_dv_start
    ENTER 256
    mov     x0, #APP_DV
    MOVQ    x1, DISCV5_STATE_SIZE
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_DV_SCRATCH
    MOVQ    x1, DISCV5_SCRATCH_SIZE
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_DV_EVENTS
    MOVQ    x1, APP_DV_EVENT_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #24
    stp     x9, xzr, [x0, #8]
    mov     x0, #APP_DV_ACTIONS
    MOVQ    x1, DISCV5_ACTIONS_BASE + 64 * DISCV5_ACTIONS_PER_EVENT
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_DV_OUT
    MOVQ    x1, APP_DV_OUT_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #24
    stp     x9, xzr, [x0, #8]
    add     x0, sp, #L                      /* the config: key, seq, entropy, now, endpoint, limits */
    mov     x1, #DISCV5_CFG_SIZE
    bl      lantern_zero
    add     x0, sp, #(L + DISCV5_CFG_KEY)
    add     x1, x19, #APP_KEY
    mov     x2, #32
    bl      lantern_copy
    add     x0, sp, #(L + DISCV5_CFG_SEQ)   /* seq: the Unix time in ms, so a restart gives a later record */
    CALL_GLOBAL lantern_shell_time_ms
    add     x0, x19, #APP_TICK
    CALL_GLOBAL libp2p_shell_clock
    add     x0, sp, #(L + DISCV5_CFG_ENTROPY)
    add     x1, x19, #(APP_TICK + LIBP2P_TICK_ENTROPY)
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    str     x9, [sp, #(L + DISCV5_CFG_NOW)]
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_port)]
    str     x9, [sp, #(L + DISCV5_CFG_PORT)]
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_enr_address)]
    cbz     x9, 1f
    mov     x10, #4
    str     x10, [sp, #(L + DISCV5_CFG_FAMILY)]
    str     w9, [sp, #(L + DISCV5_CFG_ADDRESS)]
1:  mov     x9, #2
    str     x9, [sp, #(L + DISCV5_CFG_BUCKET_IP_LIMIT)]
    mov     x9, #10
    str     x9, [sp, #(L + DISCV5_CFG_TABLE_IP_LIMIT)]
    mov     x9, #24
    str     x9, [sp, #(L + DISCV5_CFG_SUBNET4)]
    mov     x9, #64
    str     x9, [sp, #(L + DISCV5_CFG_SUBNET6)]
    add     x0, sp, #L
    ldr     x1, [x19, #APP_DV]
    CALL_GLOBAL discv5_init
    cbnz    x0, 96f
    mov     x9, #4                          /* its UDP socket */
    ldr     x10, [x19, #(APP_OPTIONS + AppOptions_port)]
    stp     x9, x10, [sp, #(L + 152)]
    stp     xzr, xzr, [sp, #(L + 168)]
    ldr     x0, [x19, #APP_SHELL]
    add     x1, sp, #(L + 152)
    add     x2, sp, #(L + 184)
    CALL_GLOBAL libp2p_shell_bind
    ldr     x9, [sp, #(L + 184 + LIBP2P_BR_ERROR)]
    cbnz    x9, 95f
    ldr     x9, [sp, #(L + 184 + LIBP2P_BR_SOCKET)]
    str     x9, [x19, #APP_DV_SOCKET]
    str     xzr, [x19, #APP_DV_WAKE]
    add     x0, sp, #L                      /* the entry tcp: --port, big endian */
    mov     x1, #56
    bl      lantern_zero
    mov     x9, #56
    mov     x10, #DISCV5_EVENT_SET_ENTRY
    stp     x9, x10, [sp, #L]
    mov     x9, #3
    MOVQ    x10, 0x706374                   /* tcp */
    stp     x9, x10, [sp, #(L + 16)]
    mov     x9, #2
    str     x9, [sp, #(L + 40)]
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_port)]
    rev16   w9, w9
    strh    w9, [sp, #(L + 48)]
    add     x0, sp, #L
    mov     x1, #56
    bl      app_dv_put
    mov     x0, #0
    LEAVE 256
95: bl      app_line_start                  /* bind UDP port <p>: error <n> */
    ADDRESS x0, app_m_bind
    mov     x1, #app_m_bind_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_port)]
    bl      app_line_u64
    ADDRESS x0, app_m_error
    mov     x1, #app_m_error_len
    bl      app_line_text
    ldr     x0, [sp, #(L + 184)]
    bl      app_line_u64
    mov     x0, #2
    bl      app_line_end
    mov     x0, #2
    LEAVE 256
96: mov     x2, x0                          /* discv5: status <n> */
    ADDRESS x0, app_m_discv5
    mov     x1, #app_m_discv5_len
    bl      app_fail_status
    LEAVE 256
97: bl      app_line_start
    ADDRESS x0, app_m_memory
    mov     x1, #app_m_memory_len
    bl      app_line_text
    mov     x0, #2
    bl      app_line_end
    mov     x0, #2
    LEAVE 256
END_FUNCTION app_dv_start

/*
 * L2: x0 = 1 when the shell event x0 is a DATAGRAM of discv5's socket, which then joins the next
 * discv5 step as a DATAGRAM event (the sender as an Endpoint); else 0. x20 the event. Locals: L the header.
 */
LOCAL_FUNCTION app_dv_datagram
    ENTER 64
    mov     x20, x0
    ldr     x9, [x20, #8]
    cmp     x9, #LIBP2P_EVENT_DATAGRAM
    b.ne    8f
    ldr     x9, [x20, #LIBP2P_EV_DG_SOCKET]
    ldr     x10, [x19, #APP_DV_SOCKET]
    cmp     x9, x10
    b.ne    8f
    ldr     x11, [x20, #LIBP2P_EV_DG_COUNT]
    cmp     x11, #APP_DV_DATAGRAM_MAX
    b.hi    9f
    add     x9, x11, #(DISCV5_EV_DG_DATA + 7)   /* size, DATAGRAM, the Endpoint (port, family, address), len */
    and     x9, x9, #~7
    mov     x10, #DISCV5_EVENT_DATAGRAM
    stp     x9, x10, [sp, #L]
    add     x12, x20, #LIBP2P_EV_DG_ADDR
    ldr     x13, [x12, #LIBP2P_ADDR_FAMILY]
    ldr     x14, [x12, #LIBP2P_ADDR_PORT]
    stp     x14, x13, [sp, #(L + 16)]
    ldp     x13, x14, [x12, #LIBP2P_ADDR_IP]
    stp     x13, x14, [sp, #(L + 32)]
    str     x11, [sp, #(L + 48)]
    ldr     x9, [x19, #APP_DV_EVENTS]       /* the header, then the bytes, if they fit */
    ldr     x10, [x9, #16]
    ldr     x12, [sp, #L]
    add     x12, x12, x10
    add     x12, x12, #24
    ldr     x13, [x9]
    cmp     x12, x13
    b.hi    9f
    add     x0, sp, #L
    mov     x1, #DISCV5_EV_DG_DATA
    bl      app_dv_put
    ldr     x9, [sp, #L]
    sub     x1, x9, #DISCV5_EV_DG_DATA
    add     x0, x20, #LIBP2P_EV_DG_DATA
    bl      app_dv_put
9:  mov     x0, #1
    LEAVE 64
8:  mov     x0, #0
    LEAVE 64
END_FUNCTION app_dv_datagram

/*
 * L2: a discv5 step when it has events or its WAKEUP is due; then its actions: SEND as the shell's
 * SEND_DATAGRAM, NODE_FOUND as a NODE_EV_ENR of the next node step, RECORD as a log line, WAKEUP
 * as the next time. x20 the next action, x21 the end, x22 the datagrams, x23 an event count.
 * Locals: L the header of an event.
 */
LOCAL_FUNCTION app_discv5
    ENTER 64
    ldr     x9, [x19, #APP_DV_EVENTS]
    ldr     x10, [x9, #16]
    cbnz    x10, 1f
    ldr     x11, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    ldr     x12, [x19, #APP_DV_WAKE]
    cmp     x11, x12
    b.lo    99f
1:  mov     x23, #0                         /* the action room for the events */
    add     x11, x9, #24
    add     x12, x11, x10
2:  cmp     x11, x12
    b.hs    3f
    ldr     x13, [x11]
    add     x11, x11, x13
    add     x23, x23, #1
    b       2b
3:  MOVQ    x9, DISCV5_ACTIONS_PER_EVENT
    MOVQ    x10, DISCV5_ACTIONS_BASE
    madd    x23, x23, x9, x10
    ldr     x9, [x19, #(APP_DV_ACTIONS + 8)]
    cmp     x23, x9
    b.ls    4f
    mov     x0, #APP_DV_ACTIONS
    bl      app_unmap
    mov     x0, #APP_DV_ACTIONS
    mov     x1, x23
    bl      app_alloc
    cbz     x0, 98f
4:  ldr     x9, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]    /* the Tick: now and fresh bytes */
    str     x9, [x19, #APP_DV_TICK]
    add     x0, x19, #(APP_DV_TICK + 8)
    add     x1, x19, #(APP_TICK + LIBP2P_TICK_ENTROPY)
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x19, #APP_DV_ACTIONS]
    ldr     x10, [x19, #(APP_DV_ACTIONS + 8)]
    str     x10, [x9]
    ldr     x9, [x19, #APP_DV_SCRATCH]
    ldr     x10, [x19, #(APP_DV_SCRATCH + 8)]
    str     x10, [x9]
    ldr     x0, [x19, #APP_DV]
    add     x1, x19, #APP_DV_TICK
    ldr     x2, [x19, #APP_DV_EVENTS]
    ldr     x3, [x19, #APP_DV_SCRATCH]
    ldr     x4, [x19, #APP_DV_ACTIONS]
    CALL_GLOBAL discv5_step
    ldr     x9, [x19, #APP_DV_EVENTS]
    str     xzr, [x9, #16]
    cbz     x0, 5f
    mov     x2, x0                          /* discv5: status <n>; its events are dropped */
    ADDRESS x0, app_m_discv5
    mov     x1, #app_m_discv5_len
    bl      app_fail_status
    ldr     x9, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    add     x9, x9, #1000
    str     x9, [x19, #APP_DV_WAKE]
    b       99f
5:  ldr     x9, [x19, #APP_DV_ACTIONS]
    ldr     x10, [x9, #8]
    ldr     x11, [x9, #16]
    add     x20, x9, x10
    add     x21, x20, x11
    ldr     x22, [x19, #APP_DV_OUT]
6:  cmp     x20, x21
    b.hs    90f
    ldr     x9, [x20, #8]
    cmp     x9, #DISCV5_ACTION_SEND
    b.ne    7f
    ldr     x10, [x20, #DISCV5_ACT_SEND_LEN]    /* SEND: a SEND_DATAGRAM of the socket */
    add     x11, x10, #(LIBP2P_ACT_DG_DATA + 7)
    and     x11, x11, #~7
    ldr     x12, [x22, #16]
    add     x13, x12, x11
    add     x13, x13, #24
    ldr     x14, [x22]
    cmp     x13, x14
    b.hi    80f
    add     x0, x22, #24
    add     x0, x0, x12
    sub     x13, x13, #24
    str     x13, [x22, #16]
    mov     x12, #LIBP2P_ACTION_SEND_DATAGRAM
    stp     x11, x12, [x0]
    ldr     x12, [x19, #APP_DV_SOCKET]
    str     x12, [x0, #LIBP2P_ACT_DG_SOCKET]
    ldp     x12, x13, [x20, #DISCV5_ACT_SEND_TO]    /* port, family */
    add     x14, x0, #LIBP2P_ACT_DG_ADDR
    stp     x13, x12, [x14]
    ldp     x12, x13, [x20, #(DISCV5_ACT_SEND_TO + 16)]
    stp     x12, x13, [x14, #16]
    str     x10, [x0, #LIBP2P_ACT_DG_COUNT]
    add     x0, x0, #LIBP2P_ACT_DG_DATA
    add     x1, x20, #DISCV5_ACT_SEND_DATA
    mov     x2, x10
    bl      lantern_copy
    b       80f
7:  cmp     x9, #DISCV5_ACTION_NODE_FOUND
    b.ne    71f
    ldr     x10, [x20, #DISCV5_ACT_FOUND_LEN]   /* NODE_FOUND: NODE_EV_ENR with the record */
    add     x11, x10, #(48 + 7)
    and     x11, x11, #~7
    mov     x12, #NODE_EV_ENR
    stp     x11, x12, [sp, #L]
    sub     x12, x11, #24
    stp     xzr, x12, [sp, #(L + 16)]
    mov     x12, #24
    stp     x12, x10, [sp, #(L + 32)]
    add     x0, sp, #L
    mov     x1, #48
    bl      app_event_put
    add     x0, x20, #DISCV5_ACT_FOUND_DATA
    ldr     x9, [sp, #L]
    sub     x1, x9, #48
    bl      app_event_put
    b       80f
71: cmp     x9, #DISCV5_ACTION_RECORD
    b.ne    72f
    bl      app_line_clear                  /* the view's enr: enr:<base64url> */
    ADDRESS x0, app_t_enr
    mov     x1, #4
    bl      app_line_text
    add     x0, x20, #DISCV5_ACT_RECORD_DATA
    ldr     x1, [x20, #DISCV5_ACT_RECORD_LEN]
    bl      app_line_base64url
    ldr     x0, [x19, #APP_VIEW]
    add     x0, x0, #ApiView_enr
    mov     x1, #512
    bl      app_line_to
    bl      app_line_start                  /* record enr:<base64url> */
    ADDRESS x0, app_m_record
    mov     x1, #app_m_record_len
    bl      app_line_text
    add     x0, x20, #DISCV5_ACT_RECORD_DATA
    ldr     x1, [x20, #DISCV5_ACT_RECORD_LEN]
    bl      app_line_base64url
    mov     x0, #1
    bl      app_line_end
    b       80f
72: cmp     x9, #DISCV5_ACTION_WAKEUP
    b.ne    80f
    ldr     x10, [x20, #DISCV5_ACT_WAKEUP_AT]
    str     x10, [x19, #APP_DV_WAKE]
80: ldr     x9, [x20]
    add     x20, x20, x9
    b       6b
90: ldr     x22, [x19, #APP_DV_OUT]         /* the datagrams go out */
    ldr     x9, [x22, #16]
    cbz     x9, 99f
    ldr     x0, [x19, #APP_SHELL]
    mov     x1, x22
    ldr     x2, [x19, #APP_SHELL_EVENTS]
    CALL_GLOBAL libp2p_shell_perform
    ldr     x22, [x19, #APP_DV_OUT]
    str     xzr, [x22, #16]
    b       99f
98: ldr     x9, [x19, #APP_DV_EVENTS]
    str     xzr, [x9, #16]
99: LEAVE 64
END_FUNCTION app_discv5

/*
 * L0: x0 = the base58btc text of the x1 bytes at x0 (at most 48), written at x2: a 1 for each
 * leading zero byte, then the digits. x3: a work area of 72 bytes. Uses x4, x9-x15.
 */
LOCAL_FUNCTION app_base58
    UNWIND_END_PROLOGUE
    mov     x9, #0                          /* the leading zero bytes */
1:  cmp     x9, x1
    b.hs    2f
    ldrb    w10, [x0, x9]
    cbnz    w10, 2f
    add     x9, x9, #1
    b       1b
2:  mov     x15, x9
    mov     x11, #0                         /* the digits so far, least significant at x3 + 71 */
    mov     x12, x9
3:  cmp     x12, x1                         /* each byte: digits * 256 + byte */
    b.hs    6f
    ldrb    w13, [x0, x12]
    mov     x14, #0
4:  cmp     x14, x11
    b.hs    5f
    mov     x10, #71
    sub     x10, x10, x14
    ldrb    w9, [x3, x10]
    add     x13, x13, x9, lsl #8
    mov     x9, #58
    udiv    x4, x13, x9
    msub    x9, x4, x9, x13
    strb    w9, [x3, x10]
    mov     x13, x4
    add     x14, x14, #1
    b       4b
5:  cbz     x13, 51f
    mov     x9, #58
    udiv    x4, x13, x9
    msub    x9, x4, x9, x13
    mov     x10, #71
    sub     x10, x10, x11
    strb    w9, [x3, x10]
    add     x11, x11, #1
    mov     x13, x4
    b       5b
51: add     x12, x12, #1
    b       3b
6:  mov     x0, #0                          /* the text: the ones, then the digits */
    ADDRESS x13, app_base58_digits
7:  cbz     x15, 8f
    ldrb    w9, [x13]
    strb    w9, [x2, x0]
    add     x0, x0, #1
    sub     x15, x15, #1
    b       7b
8:  cbz     x11, 9f
    mov     x10, #72
    sub     x10, x10, x11
    ldrb    w9, [x3, x10]
    ldrb    w9, [x13, x9]
    strb    w9, [x2, x0]
    add     x0, x0, #1
    sub     x11, x11, #1
    b       8b
9:  ret
END_FUNCTION app_base58

/* L1: the log line becomes empty: the text helpers then build a text in it. */
LOCAL_FUNCTION app_line_clear
    UNWIND_END_PROLOGUE
    str     xzr, [x19, #(APP_LINE + 16)]
    ret
END_FUNCTION app_line_clear

/* L1: the bytes of the log line go to the text field at x0 of the view (its length, then its bytes, at most x1). */
LOCAL_FUNCTION app_line_to
    FRAME 0
    add     x9, x19, #APP_LINE
    ldr     x2, [x9, #16]
    cmp     x2, x1
    csel    x2, x2, x1, ls
    str     x2, [x0], #8
    add     x1, x9, #24
    bl      lantern_copy
    UNFRAME 0
END_FUNCTION app_line_to

/* L1: the IPv4 address x0 (its bytes in order in the low bytes) joins the line in dotted decimal. Locals: x0, the count. */
LOCAL_FUNCTION app_line_ip4
    FRAME 16
    stp     x0, xzr, [sp, #16]
1:  ldp     x0, x9, [sp, #16]
    and     x0, x0, #0xff
    bl      app_line_u64
    ldp     x0, x9, [sp, #16]
    add     x9, x9, #1
    lsr     x0, x0, #8
    stp     x0, x9, [sp, #16]
    cmp     x9, #4
    b.hs    2f
    ADDRESS x0, app_t_dot
    mov     x1, #1
    bl      app_line_text
    b       1b
2:  UNFRAME 16
END_FUNCTION app_line_ip4

/* L1: a multiaddr /ip4/<--enr-address>/<x0: tcp or udp text>/<--port>/p2p/<peer id> to the view's field at x1, or length 0 with no --enr-address. Locals: x0, x1. */
LOCAL_FUNCTION app_multiaddr
    FRAME 16
    stp     x0, x1, [sp, #16]
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_enr_address)]
    cbnz    x9, 1f
    str     xzr, [x1]
    UNFRAME 16
1:  bl      app_line_clear
    ADDRESS x0, app_t_ip4
    mov     x1, #5
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_enr_address)]
    bl      app_line_ip4
    ldr     x0, [sp, #16]
    mov     x1, #5
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_port)]
    bl      app_line_u64
    ADDRESS x0, app_t_p2p
    mov     x1, #5
    bl      app_line_text
    ldr     x9, [x19, #APP_VIEW]
    add     x9, x9, #ApiView_peer_id
    ldr     x1, [x9], #8
    mov     x0, x9
    bl      app_line_text
    ldr     x0, [sp, #24]
    mov     x1, #128
    bl      app_line_to
    UNFRAME 16
END_FUNCTION app_multiaddr

/*
 * L2: the Beacon API: a shell context that listens on --http-port, its buffers, and the view's
 * fixed values: the peer id, the addresses, the version, and the anchor's header: x0 = 0, or 2
 * after a line on the standard error. Locals: L ShellParams or an Address, L+32 a ListenResult
 * or the public key, L+80 the peer id's multihash, L+128 base58's work area.
 */
LOCAL_FUNCTION app_api_start
    ENTER 208
    mov     x9, #APP_API_SLOTS_MAX
    MOVQ    x10, APP_API_SEND_WINDOW
    stp     x9, x10, [sp, #L]
    add     x0, sp, #L
    add     x1, sp, #(L + 32)
    CALL_GLOBAL libp2p_shell_size
    cbnz    x0, 97f
    mov     x0, #APP_API_SHELL
    ldr     x1, [sp, #(L + 32)]
    bl      app_alloc
    cbz     x0, 97f
    mov     x1, x0
    add     x0, sp, #L
    CALL_GLOBAL libp2p_shell_init
    cbnz    x0, 97f
    mov     x0, #APP_API_EVENTS
    MOVQ    x1, APP_API_EVENT_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #24
    stp     x9, xzr, [x0, #8]
    mov     x0, #APP_API_ACT
    MOVQ    x1, 24 + APP_API_SLOTS_MAX * (64 + APP_API_OUT_BYTES)
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #24
    stp     x9, xzr, [x0, #8]
    mov     x0, #APP_API_OUT
    MOVQ    x1, 24 + APP_API_OUT_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_API_REQ
    MOVQ    x1, APP_API_SLOTS_MAX * (24 + APP_API_REQ_BYTES)
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_VIEW
    mov     x1, #4096
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #4                          /* listen: TCP --http-port on every IPv4 address */
    ldr     x10, [x19, #(APP_OPTIONS + AppOptions_http_port)]
    stp     x9, x10, [sp, #L]
    stp     xzr, xzr, [sp, #(L + 16)]
    ldr     x0, [x19, #APP_API_SHELL]
    add     x1, sp, #L
    add     x2, sp, #(L + 32)
    CALL_GLOBAL libp2p_shell_listen
    ldr     x9, [sp, #(L + 32)]
    cbnz    x9, 96f
    add     x0, x19, #APP_KEY               /* the peer id: base58btc of the identity multihash of the key */
    add     x1, sp, #(L + 32)
    CALL_GLOBAL crypto_secp256k1_public_key
    cbnz    x0, 97f
    MOVQ    x9, 0x0000211202082500
    str     x9, [sp, #(L + 80)]
    add     x0, sp, #(L + 86)
    add     x1, sp, #(L + 32)
    mov     x2, #33
    bl      lantern_copy
    add     x0, sp, #(L + 80)
    mov     x1, #39
    ldr     x2, [x19, #APP_VIEW]
    add     x2, x2, #(ApiView_peer_id + 8)
    add     x3, sp, #(L + 128)
    bl      app_base58
    ldr     x9, [x19, #APP_VIEW]
    str     x0, [x9, #ApiView_peer_id]
    ldr     x0, [x19, #APP_VIEW]            /* the version */
    add     x0, x0, #ApiView_version
    mov     x9, #app_version_text_len
    str     x9, [x0], #8
    ADDRESS x1, app_version_text
    mov     x2, #app_version_text_len
    bl      lantern_copy
    ADDRESS x0, app_t_tcp                   /* the addresses */
    ldr     x1, [x19, #APP_VIEW]
    MOVQ    x9, ApiView_p2p_address
    add     x1, x1, x9
    bl      app_multiaddr
    ADDRESS x0, app_t_udp
    ldr     x1, [x19, #APP_VIEW]
    MOVQ    x9, ApiView_discovery_address
    add     x1, x1, x9
    bl      app_multiaddr
    ldr     x9, [x19, #APP_STATE]           /* the anchor's header: its state's latest_block_header, the block's state_root */
    add     x1, x9, #NODE_STATE_HEADER
    add     x0, x19, #APP_ANCHOR_HEADER
    mov     x2, #112
    bl      lantern_copy
    add     x0, x19, #(APP_ANCHOR_HEADER + 48)
    ldr     x1, [x19, #APP_BLOCK]
    add     x1, x1, #NODE_BLOCK_STATE_ROOT
    mov     x2, #32
    bl      lantern_copy
    bl      app_line_start                  /* Beacon API on TCP port <p>, peer id <id> */
    ADDRESS x0, app_m_api
    mov     x1, #app_m_api_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_http_port)]
    bl      app_line_u64
    ADDRESS x0, app_m_peer_id
    mov     x1, #app_m_peer_id_len
    bl      app_line_text
    ldr     x9, [x19, #APP_VIEW]
    add     x9, x9, #ApiView_peer_id
    ldr     x1, [x9], #8
    mov     x0, x9
    bl      app_line_text
    mov     x0, #1
    bl      app_line_end
    mov     x0, #0
    LEAVE 208
96: bl      app_line_start                  /* listen on TCP port <p>: error <n> */
    ADDRESS x0, app_m_listen
    mov     x1, #app_m_listen_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_http_port)]
    bl      app_line_u64
    ADDRESS x0, app_m_error
    mov     x1, #app_m_error_len
    bl      app_line_text
    ldr     x0, [sp, #(L + 32)]
    bl      app_line_u64
    mov     x0, #2
    bl      app_line_end
    mov     x0, #2
    LEAVE 208
97: bl      app_line_start
    ADDRESS x0, app_m_memory
    mov     x1, #app_m_memory_len
    bl      app_line_text
    mov     x0, #2
    bl      app_line_end
    mov     x0, #2
    LEAVE 208
END_FUNCTION app_api_start

/*
 * L2: the view's values of the node now: genesis, the head and its header, the head state's
 * checkpoints, the clock's slot, sync, peers and MetaData. x20 the view, x21 the head's NodeBlock,
 * x22 its fork, x23 the header.
 */
LOCAL_FUNCTION app_view_fill
    ENTER 0
    ldr     x20, [x19, #APP_VIEW]
    ldr     x9, [x19, #APP_STORE]           /* genesis */
    ldr     x9, [x9, #Store_genesis_time_ms]
    mov     x10, #1000
    udiv    x9, x9, x10
    str     x9, [x20, #ApiView_genesis_time]
    add     x0, x20, #ApiView_genesis_validators_root
    add     x1, x19, #(APP_ANCHOR + NodeAnchor_genesis_validators_root)
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x19, #(APP_CONFIG + CONFIG_GENESIS_FORK_VERSION)]
    str     x9, [x20, #ApiView_genesis_fork_version]
    ldr     x9, [x19, #APP_NODE]            /* the head's NodeBlock */
    ldr     x10, [x9, #Node_blocks]
    add     x21, x9, x10
    ldr     x11, [x9, #(Node_blocks + 8)]
1:  cbz     x11, 90f
    mov     x0, x21
    ldr     x1, [x19, #APP_NODE]
    add     x1, x1, #Node_head_root
    mov     x2, #32
    bl      app_same32
    cbnz    x0, 2f
    add     x21, x21, #NodeBlock__mem
    ldr     x9, [x19, #APP_NODE]
    ldr     x10, [x9, #Node_blocks]
    add     x10, x9, x10
    ldr     x11, [x9, #(Node_blocks + 8)]
    mov     x12, #NodeBlock__mem
    madd    x10, x11, x12, x10
    cmp     x21, x10
    b.hs    90f
    mov     x11, #1
    b       1b
2:  ldr     x9, [x21, #NodeBlock_slot]
    str     x9, [x20, #ApiView_head_slot]
    add     x0, x20, #ApiView_head_root
    mov     x1, x21
    mov     x2, #32
    bl      lantern_copy
    add     x23, x19, #APP_ANCHOR_HEADER    /* the header: the anchor's, or the block's */
    ldr     x0, [x21, #NodeBlock_data_id]
    cbz     x0, 3f
    bl      app_buf_find
    cbz     x0, 3f
    ldr     x22, [x0, #8]
    ldr     x0, [x21, #NodeBlock_slot]
    add     x1, x19, #APP_CONFIG
    bl      app_fork
    mov     x15, x0
    mov     x0, x22
    ldr     x1, [x19, #APP_SCRATCH]
    add     x2, x19, #APP_HEADER
    FORK_CALL node_block_header
    cbnz    x0, 3f
    add     x23, x19, #APP_HEADER
3:  ldr     x9, [x23, #8]
    str     x9, [x20, #ApiView_proposer_index]
    add     x0, x20, #ApiView_parent_root
    add     x1, x23, #16
    mov     x2, #(32 * 3)
    bl      lantern_copy
    add     x0, x20, #ApiView_signature
    add     x1, x23, #112
    mov     x2, #96
    bl      lantern_copy
    ldr     x0, [x21, #NodeBlock_state_id]  /* the head state's checkpoints */
    bl      app_buf_find
    cbz     x0, 4f
    ldr     x22, [x0, #8]
    ldr     x0, [x22, #NODE_STATE_SLOT]
    add     x1, x19, #APP_CONFIG
    bl      app_fork
    mov     x15, x0
    mov     x0, x22
    add     x1, x20, #ApiView_previous_justified
    FORK_CALL node_state_checkpoints
4:  ldr     x9, [x21, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x20, #ApiView_is_optimistic]
90: ldr     x0, [x19, #APP_STORE]           /* the clock, sync, peers, MetaData */
    bl      app_store_slot
    str     x0, [x20, #ApiView_current_slot]
    add     x1, x19, #APP_CONFIG
    bl      app_fork
    str     x0, [x20, #ApiView_fork]
    ldr     x9, [x19, #APP_NODE]
    ldr     x10, [x9, #Node_flags]
    ubfx    x10, x10, #3, #1                /* NODE_FLAG_SYNCING */
    str     x10, [x20, #ApiView_is_syncing]
    str     xzr, [x20, #ApiView_el_offline]
    ldr     x10, [x9, #(Node_peers + 8)]
    str     x10, [x20, #ApiView_peers]
    ldr     x10, [x9, #Node_metadata_seq]
    str     x10, [x20, #ApiView_seq_number]
    str     xzr, [x20, #ApiView_attnets]
    str     xzr, [x20, #ApiView_syncnets]
    ldr     x10, [x19, #(APP_CONFIG + CONFIG_CUSTODY_REQUIREMENT)]
    str     x10, [x20, #ApiView_custody_group_count]
    LEAVE 0
END_FUNCTION app_view_fill

/* L0: x0 = 1 when the 32 bytes at x0 are those at x1, else 0. Uses x9-x12. */
LOCAL_FUNCTION app_same32
    UNWIND_END_PROLOGUE
    ldp     x9, x10, [x0]
    ldp     x11, x12, [x1]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    1f
    ldp     x9, x10, [x0, #16]
    ldp     x11, x12, [x1, #16]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    1f
    mov     x0, #1
    ret
1:  mov     x0, #0
    ret
END_FUNCTION app_same32

/* L1: an action of x1 bytes, the x1 bytes at x0, joins the Beacon API's shell actions, when it fits. Uses x9-x11. */
LOCAL_FUNCTION app_api_act
    FRAME 0
    ldr     x9, [x19, #APP_API_ACT]
    ldr     x10, [x9, #16]
    add     x11, x10, x1
    add     x11, x11, #24
    ldr     x12, [x9]
    cmp     x11, x12
    b.hi    9f
    sub     x11, x11, #24
    str     x11, [x9, #16]
    mov     x2, x1
    mov     x1, x0
    add     x0, x9, #24
    add     x0, x0, x10
    bl      lantern_copy
9:  UNFRAME 0
END_FUNCTION app_api_act

/* L1: a CLOSE of the connection x0 joins the shell actions. Locals: the action. */
LOCAL_FUNCTION app_api_close
    FRAME 32
    mov     x9, #LIBP2P_ACT_CLOSE_SIZE
    mov     x10, #LIBP2P_ACTION_CLOSE
    stp     x9, x10, [sp, #16]
    str     x0, [sp, #(16 + LIBP2P_ACT_CONN)]
    add     x0, sp, #16
    mov     x1, #LIBP2P_ACT_CLOSE_SIZE
    bl      app_api_act
    UNFRAME 32
END_FUNCTION app_api_close

/*
 * L2: the Beacon API's sockets, without waiting: ACCEPTED takes a free slot (ADOPT) or a REFUSE,
 * RECEIVED joins its slot's request, then a complete request gets its answer (SEND, CLOSE),
 * CLOSED frees the slot; then the shell actions go out. x20 the next event, x21 the end, x22 a
 * slot's entry, x23 its request ByteList, x24 the connection. Locals: L the wait, L+8 an action.
 */
LOCAL_FUNCTION app_api_poll
    ENTER 64
    str     xzr, [sp, #L]
    ldr     x0, [x19, #APP_API_SHELL]
    add     x1, sp, #L
    ldr     x2, [x19, #APP_API_EVENTS]
    CALL_GLOBAL libp2p_shell_wait
    ldr     x9, [x19, #APP_API_EVENTS]
    ldr     x10, [x9, #8]
    ldr     x11, [x9, #16]
    add     x20, x9, x10
    add     x21, x20, x11
1:  cmp     x20, x21
    b.hs    80f
    ldr     x9, [x20, #8]
    cmp     x9, #LIBP2P_EVENT_ACCEPTED
    b.ne    3f
    add     x22, x19, #APP_API_SLOTS        /* ACCEPTED: a free slot, or REFUSE */
    mov     x10, #0
2:  cmp     x10, #APP_API_SLOTS_MAX
    b.hs    21f
    ldr     x11, [x22, #8]
    cbz     x11, 22f
    add     x22, x22, #16
    add     x10, x10, #1
    b       2b
21: mov     x9, #LIBP2P_ACT_REFUSE_SIZE
    mov     x11, #LIBP2P_ACTION_REFUSE
    stp     x9, x11, [sp, #(L + 8)]
    ldr     x9, [x20, #LIBP2P_EV_TOKEN]
    str     x9, [sp, #(L + 8 + LIBP2P_ACT_TOKEN)]
    add     x0, sp, #(L + 8)
    mov     x1, #LIBP2P_ACT_REFUSE_SIZE
    bl      app_api_act
    b       79f
22: ldr     x11, [x22]                      /* a new generation, its request empty */
    add     x11, x11, #1
    mov     x12, #1
    stp     x11, x12, [x22]
    orr     x24, x10, x11, lsl #32
    MOVQ    x13, 24 + APP_API_REQ_BYTES
    ldr     x23, [x19, #APP_API_REQ]
    madd    x23, x10, x13, x23
    mov     x9, #24
    stp     x13, x9, [x23]
    str     xzr, [x23, #16]
    mov     x9, #LIBP2P_ACT_ADOPT_SIZE
    mov     x11, #LIBP2P_ACTION_ADOPT
    stp     x9, x11, [sp, #(L + 8)]
    ldr     x9, [x20, #LIBP2P_EV_TOKEN]
    stp     x9, x24, [sp, #(L + 8 + LIBP2P_ACT_TOKEN)]
    add     x0, sp, #(L + 8)
    mov     x1, #LIBP2P_ACT_ADOPT_SIZE
    bl      app_api_act
    b       79f
3:  cmp     x9, #LIBP2P_EVENT_RECEIVED
    ccmp    x9, #LIBP2P_EVENT_CLOSED, #4, ne
    b.ne    79f
    ldr     x24, [x20, #LIBP2P_EV_CONN]     /* the slot of the connection, at its generation */
    and     x10, x24, #0xffffffff
    cmp     x10, #APP_API_SLOTS_MAX
    b.hs    79f
    add     x22, x19, #APP_API_SLOTS
    add     x22, x22, x10, lsl #4
    ldr     x11, [x22]
    cmp     x11, x24, lsr #32
    b.ne    79f
    cmp     x9, #LIBP2P_EVENT_CLOSED
    b.ne    4f
    str     xzr, [x22, #8]                  /* CLOSED: the slot is free */
    b       79f
4:  ldr     x11, [x22, #8]                  /* RECEIVED, while reading: the bytes join the request */
    cmp     x11, #1
    b.ne    79f
    MOVQ    x13, 24 + APP_API_REQ_BYTES
    ldr     x23, [x19, #APP_API_REQ]
    madd    x23, x10, x13, x23
    ldr     x11, [x23, #16]
    ldr     x2, [x20, #LIBP2P_EV_COUNT]
    add     x12, x11, x2
    MOVQ    x13, APP_API_REQ_BYTES
    cmp     x12, x13
    b.hi    6f
    str     x12, [x23, #16]
    add     x0, x23, #24
    add     x0, x0, x11
    add     x1, x20, #LIBP2P_EV_DATA
    bl      lantern_copy
    bl      app_view_fill                   /* the answer, once the request's head is complete */
    ldr     x9, [x19, #APP_API_OUT]
    MOVQ    x10, 24 + APP_API_OUT_BYTES
    str     x10, [x9]
    mov     x0, x23
    ldr     x1, [x19, #APP_VIEW]
    ldr     x2, [x19, #APP_API_OUT]
    CALL_GLOBAL lantern_api_answer
    cmp     x0, #LANTERN_HTTP_MORE
    b.eq    79f
    cbnz    x0, 6f
    ldr     x9, [x19, #APP_API_OUT]         /* SEND the response: size, kind, connection, count, the bytes */
    ldr     x10, [x9, #16]
    add     x11, x10, #(LIBP2P_ACT_SEND_DATA + 7)
    and     x11, x11, #~7
    ldr     x12, [x19, #APP_API_ACT]
    ldr     x13, [x12, #16]
    add     x14, x13, x11
    add     x14, x14, #24
    ldr     x15, [x12]
    cmp     x14, x15
    b.hi    6f
    sub     x14, x14, #24
    str     x14, [x12, #16]
    add     x0, x12, #24
    add     x0, x0, x13
    mov     x14, #LIBP2P_ACTION_SEND
    stp     x11, x14, [x0]
    stp     x24, x10, [x0, #LIBP2P_ACT_CONN]
    add     x0, x0, #LIBP2P_ACT_SEND_DATA
    add     x1, x9, #24
    mov     x2, x10
    bl      lantern_copy
6:  mov     x9, #2                          /* then CLOSE */
    str     x9, [x22, #8]
    mov     x0, x24
    bl      app_api_close
79: ldr     x9, [x20]
    add     x20, x20, x9
    b       1b
80: ldr     x9, [x19, #APP_API_EVENTS]      /* the actions go out; their results come at the next poll */
    str     xzr, [x9, #16]
    ldr     x9, [x19, #APP_API_ACT]
    ldr     x10, [x9, #16]
    cbz     x10, 9f
    ldr     x0, [x19, #APP_API_SHELL]
    mov     x1, x9
    ldr     x2, [x19, #APP_API_EVENTS]
    CALL_GLOBAL libp2p_shell_perform
    ldr     x9, [x19, #APP_API_ACT]
    str     xzr, [x9, #16]
9:  LEAVE 64
END_FUNCTION app_api_poll

/* L2: each event of the shell becomes a NODE_EV_P2P event of the next step, but those of the engine's connection. x20 the next event, x21 the end. Locals: L the header. */
LOCAL_FUNCTION app_p2p_events
    ENTER 16
    ldr     x9, [x19, #APP_SHELL_EVENTS]
    ldr     x10, [x9, #8]
    ldr     x11, [x9, #16]
    add     x20, x9, x10
    add     x21, x20, x11
1:  cmp     x20, x21
    b.hs    9f
    mov     x0, x20                         /* a datagram of discv5 */
    bl      app_dv_datagram
    cbnz    x0, 2f
    mov     x0, x20                         /* the engine's connection */
    bl      app_engine_event
    cbnz    x0, 2f
    ldr     x9, [x20]
    add     x10, x9, #16
    mov     x11, #NODE_EV_P2P
    stp     x10, x11, [sp, #L]
    add     x0, sp, #L
    mov     x1, #16
    bl      app_event_put
    mov     x0, x20
    ldr     x1, [x20]
    bl      app_event_put
2:  ldr     x9, [x20]
    add     x20, x20, x9
    b       1b
9:  ldr     x9, [x19, #APP_SHELL_EVENTS]
    str     xzr, [x9, #16]
    ldr     x9, [x19, #APP_ENGINE_DUE]      /* then more bytes of the request */
    cbz     x9, 10f
    str     xzr, [x19, #APP_ENGINE_DUE]
    bl      app_engine_send
10: LEAVE 16
END_FUNCTION app_p2p_events

/*
 * L2: the loop: the clock, a NODE_EV_TICK of the time and the shell's events, lantern_node_step
 * with libp2p, a line at each new slot, then a wait for the sockets until the node's wakeup, at
 * most APP_WAIT_MS. Locals: L the time, L+8 the wait.
 */
LOCAL_FUNCTION app_loop
    ENTER 16
1:  add     x0, x19, #APP_TICK              /* the clocks */
    CALL_GLOBAL libp2p_shell_clock
    add     x0, sp, #L
    CALL_GLOBAL lantern_shell_time_ms
    mov     x9, #24                         /* NODE_EV_TICK of the Unix time */
    mov     x10, #NODE_EV_TICK
    stp     x9, x10, [sp, #-32]!
    ldr     x11, [sp, #(32 + L)]
    str     x11, [sp, #16]
    mov     x0, sp
    mov     x1, #24
    bl      app_event_put
    add     sp, sp, #32
    bl      app_p2p_events
    ldr     x0, [x19, #APP_P2P]
    add     x1, x19, #APP_TICK
    bl      app_step
    bl      app_discv5
    ldr     x0, [x19, #APP_STORE]           /* a line at each new slot */
    bl      app_store_slot
    ldr     x9, [x19, #APP_LAST_SLOT]
    cmp     x0, x9
    b.eq    3f
    str     x0, [x19, #APP_LAST_SLOT]
    str     x0, [sp, #(L + 8)]
    bl      app_line_start                  /* slot <s>, head 0x<root>, finalized epoch <e> */
    ADDRESS x0, app_m_slot
    mov     x1, #app_m_slot_len
    bl      app_line_text
    ldr     x0, [sp, #(L + 8)]
    bl      app_line_u64
    ADDRESS x0, app_m_head
    mov     x1, #app_m_head_len
    bl      app_line_text
    ldr     x0, [x19, #APP_NODE]
    add     x0, x0, #Node_head_root
    mov     x1, #8
    bl      app_line_hex
    ADDRESS x0, app_m_finalized
    mov     x1, #app_m_finalized_len
    bl      app_line_text
    ldr     x0, [x19, #APP_STORE]
    ldr     x0, [x0, #Store_finalized_checkpoint]
    bl      app_line_u64
    mov     x0, #1
    bl      app_line_end
3:  ldr     x9, [x19, #(APP_RESULT + 8)]    /* the wait: to the node's or discv5's wakeup, at most APP_WAIT_MS */
    ldr     x13, [x19, #APP_DV_WAKE]
    cmp     x13, x9
    csel    x9, x13, x9, lo
    ldr     x10, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    subs    x11, x9, x10
    csel    x11, xzr, x11, ls
    mov     x12, #APP_WAIT_MS
    cmp     x11, x12
    csel    x11, x11, x12, lo
    str     x11, [sp, #(L + 8)]
    ldr     x0, [x19, #APP_SHELL]
    add     x1, sp, #(L + 8)
    ldr     x2, [x19, #APP_SHELL_EVENTS]
    CALL_GLOBAL libp2p_shell_wait
    bl      app_api_poll
    b       1b
END_FUNCTION app_loop

/* (args): docs/reference/app.md. x19 the App, x20 args. Locals: L the fault. */
FUNCTION lantern_app_main
    ENTER 16
    mov     x20, x0
    MOVQ    x0, APP_SIZE
    bl      app_map
    cbz     x0, 9f
    mov     x19, x0
    str     x20, [x19, #APP_ARGS]
    MOVQ    x9, 24 + APP_LINE_MAX
    mov     x10, #24
    add     x11, x19, #APP_LINE
    stp     x9, x10, [x11]
    MOVQ    x9, 24 + APP_PATH_MAX
    ADDQ    x11, x19, APP_PATH
    stp     x9, x10, [x11]
    mov     x0, x20
    add     x1, x19, #APP_OPTIONS
    add     x2, sp, #L
    CALL_GLOBAL lantern_app_options
    cbz     x0, 1f
    bl      app_line_start                  /* faulty option at argument <n> */
    ADDRESS x0, app_m_option
    mov     x1, #app_m_option_len
    bl      app_line_text
    ldr     x0, [sp, #L]
    bl      app_line_u64
    mov     x0, #2
    bl      app_line_end
    mov     x0, #1
    LEAVE 16
1:  bl      app_start
    cbnz    x0, 8f
    bl      app_net
    cbnz    x0, 8f
    bl      app_loop
8:  LEAVE 16
9:  mov     x0, #2
    LEAVE 16
END_FUNCTION lantern_app_main
