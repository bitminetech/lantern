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
.set APP_RECORD, APP_ENGINE_DUE + 8         /* a NODE_EV_ENR event of a boot node: 48 bytes, then the record */
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
    add     x10, x19, #APP_PATH
    cmp     x9, #APP_PATH_MAX
    b.hi    1f
    str     x9, [x10, #16]
    ldr     x11, [x19, #APP_ARGS]
    add     x1, x11, x22
    add     x0, x10, #24
    mov     x2, x23
    bl      lantern_copy
    add     x10, x19, #APP_PATH
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
    add     x9, x19, #APP_PATH
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
    add     x0, x19, #APP_PATH
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
6:  cmp     x9, #NODE_ACT_P2P_LIST
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
3:  bl      app_boot_nodes
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
    add     x11, x19, #APP_PATH
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
3:  ldr     x9, [x19, #(APP_RESULT + 8)]    /* the wait: to the node's wakeup, at most APP_WAIT_MS */
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
    add     x11, x19, #APP_PATH
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
