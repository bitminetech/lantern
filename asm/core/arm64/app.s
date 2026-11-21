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

/* The App, at x19; the constants and the RODATA. */
.include "app.inc"

/* reg = the scratch buffer, its size written back into its first 8 bytes: a callee may leave it
 * invalid (ARCHITECTURE.md section 6). Uses x16. */
.macro SCRATCH reg
    ldr     \reg, [x19, #APP_SCRATCH]
    ldr     x16, [x19, #(APP_SCRATCH + 8)]
    str     x16, [\reg]
.endm

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

/*
 * L1: a StateCache, a CommitteeCache and a PubkeyCache for x0 / 121 + 65536 validators (x0 the anchor file's
 * bytes), at CONFIG_STATE_CACHE and CONFIG_COMMITTEE_CACHE of the app's config; none with no
 * memory. x19 the app.
 * Locals: sp+16 validators, sp+24 its bytes.
 */
LOCAL_FUNCTION app_state_cache
    FRAME 16
    mov     x9, #121
    udiv    x0, x0, x9
    MOVQ    x9, 65536
    add     x0, x0, x9
    str     x0, [sp, #16]
    add     x0, sp, #16
    add     x1, sp, #24
    ldr     x15, [x19, #APP_FORK]
    FORK_CALL state_cache_size
    ldr     x0, [sp, #24]
    bl      app_map
    cbz     x0, 1f
    ldr     x9, [sp, #24]
    str     x9, [x0]
    add     x10, x19, #APP_CONFIG
    str     x0, [x10, #CONFIG_STATE_CACHE]
    mov     x1, x0
    add     x0, sp, #16
    ldr     x15, [x19, #APP_FORK]
    FORK_CALL state_cache_init
1:  add     x0, sp, #16                     /* the CommitteeCache, for as many validators */
    add     x1, sp, #24
    ldr     x15, [x19, #APP_FORK]
    FORK_CALL committee_cache_size
    ldr     x0, [sp, #24]
    bl      app_map
    cbz     x0, 2f
    ldr     x9, [sp, #24]
    str     x9, [x0]
    add     x10, x19, #APP_CONFIG
    str     x0, [x10, #CONFIG_COMMITTEE_CACHE]
    mov     x1, x0
    add     x0, sp, #16
    ldr     x15, [x19, #APP_FORK]
    FORK_CALL committee_cache_init
2:  add     x0, sp, #16                     /* the PubkeyCache, for as many validators */
    add     x1, sp, #24
    ldr     x15, [x19, #APP_FORK]
    FORK_CALL pubkey_cache_size
    ldr     x0, [sp, #24]
    bl      app_map
    cbz     x0, 3f
    ldr     x9, [sp, #24]
    str     x9, [x0]
    add     x10, x19, #APP_CONFIG
    str     x0, [x10, #CONFIG_PUBKEY_CACHE]
    mov     x1, x0
    add     x0, sp, #16
    ldr     x15, [x19, #APP_FORK]
    FORK_CALL pubkey_cache_init
3:  mov     x0, #LANTERN_OK
    UNFRAME 16
END_FUNCTION app_state_cache

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

/* L0: the log line starts, with room for the time and the level that app_line_end writes. */
LOCAL_FUNCTION app_line_start
    UNWIND_END_PROLOGUE
    mov     x9, #APP_LOG_PREFIX
    str     x9, [x19, #(APP_LINE + 16)]
    ret
END_FUNCTION app_line_start

/*
 * L0: the UTC time of the Unix milliseconds x0, as YYYY-MM-DD HH:MM:SS.mmm, in the 23 bytes at
 * x1 (civil_from_days of the days since 1970). A leaf; uses x0-x15 and keeps x30 in x7.
 */
LOCAL_FUNCTION app_time_text
    UNWIND_END_PROLOGUE
    MOVQ    x2, 86400000
    udiv    x3, x0, x2                      /* days */
    msub    x4, x3, x2, x0                  /* milliseconds of the day */
    MOVQ    x5, 719468
    add     x3, x3, x5                      /* z */
    MOVQ    x5, 146097
    udiv    x6, x3, x5                      /* era */
    msub    x7, x6, x5, x3                  /* day of the era */
    mov     x8, #1460
    udiv    x9, x7, x8
    sub     x10, x7, x9
    MOVQ    x8, 36524
    udiv    x9, x7, x8
    add     x10, x10, x9
    MOVQ    x8, 146096
    udiv    x9, x7, x8
    sub     x10, x10, x9
    mov     x8, #365
    udiv    x10, x10, x8                    /* year of the era */
    mov     x8, #400
    madd    x11, x6, x8, x10                /* the year, from March */
    mov     x8, #365
    mul     x12, x10, x8
    add     x12, x12, x10, lsr #2
    mov     x8, #100
    udiv    x13, x10, x8
    sub     x12, x12, x13
    sub     x12, x7, x12                    /* day of the year, from March 1 */
    mov     x8, #5
    mul     x13, x12, x8
    add     x13, x13, #2
    mov     x8, #153
    udiv    x13, x13, x8                    /* month, from March */
    mul     x14, x13, x8
    add     x14, x14, #2
    mov     x8, #5
    udiv    x14, x14, x8
    sub     x14, x12, x14
    add     x14, x14, #1                    /* day */
    cmp     x13, #10
    b.hs    1f
    add     x13, x13, #3                    /* month */
    b       2f
1:  sub     x13, x13, #9
2:  cmp     x13, #2
    cinc    x11, x11, ls                    /* the year: January and February are of the next */
    mov     w8, #0x2d                       /* the separators */
    strb    w8, [x1, #4]
    strb    w8, [x1, #7]
    mov     w8, #0x20
    strb    w8, [x1, #10]
    mov     w8, #0x3a
    strb    w8, [x1, #13]
    strb    w8, [x1, #16]
    mov     w8, #0x2e
    strb    w8, [x1, #19]
    mov     x15, x1
    mov     x7, x30                         /* the return: the digits below use bl */
    add     x1, x15, #4                     /* the digits, each field from its end */
    mov     x2, #4
    mov     x0, x11
    bl      3f
    add     x1, x15, #7
    mov     x2, #2
    mov     x0, x13
    bl      3f
    add     x1, x15, #10
    mov     x2, #2
    mov     x0, x14
    bl      3f
    MOVQ    x8, 3600000
    udiv    x0, x4, x8                      /* hours */
    msub    x4, x0, x8, x4
    add     x1, x15, #13
    mov     x2, #2
    bl      3f
    MOVQ    x8, 60000
    udiv    x0, x4, x8                      /* minutes */
    msub    x4, x0, x8, x4
    add     x1, x15, #16
    mov     x2, #2
    bl      3f
    mov     x8, #1000
    udiv    x0, x4, x8                      /* seconds */
    msub    x4, x0, x8, x4
    add     x1, x15, #19
    mov     x2, #2
    bl      3f
    mov     x0, x4                          /* milliseconds */
    add     x1, x15, #23
    mov     x2, #3
    bl      3f
    mov     x30, x7
    ret
3:  mov     x9, #10                         /* x2 digits of x0 before x1; a leaf of its own, x30 the return */
4:  udiv    x10, x0, x9
    msub    x11, x10, x9, x0
    add     x11, x11, #0x30
    strb    w11, [x1, #-1]!
    mov     x0, x10
    subs    x2, x2, #1
    b.ne    4b
    ret
END_FUNCTION app_time_text

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

/*
 * L1: the log line of kind x0 (APP_LOG_INFO, ERROR, WARN or DEBUG), when its level is at most the
 * log level: its time and level before it, an LF after it, to the standard error for ERROR and
 * WARN, else the standard output. Locals: sp+16 the level, sp+24 the time, sp+32 an LF.
 */
LOCAL_FUNCTION app_line_end
    FRAME 32
    ADDRESS x9, app_log_rank
    ldrb    w10, [x9, x0]
    ldr     x11, [x19, #(APP_OPTIONS + AppOptions_log_level)]
    cmp     x10, x11
    b.hi    9f
    mov     x12, #1
    cmp     x10, #1
    b.hi    1f
    mov     x12, #2
1:  str     x12, [x19, #APP_STREAM]
    str     x10, [sp, #16]
    add     x0, sp, #24
    CALL_GLOBAL lantern_shell_time_ms
    ldr     x0, [sp, #24]
    add     x1, x19, #(APP_LINE + 24)
    bl      app_time_text
    add     x9, x19, #(APP_LINE + 24)
    mov     w10, #0x20
    strb    w10, [x9, #23]
    strb    w10, [x9, #29]
    ldr     x10, [sp, #16]
    ADDRESS x11, app_log_names
    add     x11, x11, x10, lsl #3
    ldr     w12, [x11]
    str     w12, [x9, #24]
    ldrb    w12, [x11, #4]
    strb    w12, [x9, #28]
    mov     w9, #10
    strb    w9, [sp, #32]
    add     x0, sp, #32
    mov     x1, #1
    bl      app_line_text
    add     x0, x19, #APP_STREAM
    add     x1, x19, #APP_LINE
    CALL_GLOBAL lantern_shell_write
9:  UNFRAME 32
END_FUNCTION app_line_end

/*
 * L1: the log lines of a work that ran (app.md, the log): DEBUG work <kind> result <n>; for a
 * block's import, INFO block <slot> imported, <a> attestations, or WARN block <slot> not imported:
 * result <n>. x24 the work's data entry, x26 its kind. Locals: sp+16 the result, sp+24 the slot.
 */
LOCAL_FUNCTION app_log_work
    FRAME 16
    ldr     x9, [x19, #APP_WORK_EVENT]
    ldr     x10, [x9, #NodeEvent_result]
    str     x10, [sp, #16]
    bl      app_line_start
    ADDRESS x0, app_m_log_work
    mov     x1, #app_m_log_work_len
    bl      app_line_text
    mov     x0, x26
    bl      app_line_u64
    ADDRESS x0, app_m_log_result
    mov     x1, #app_m_log_result_len
    bl      app_line_text
    ldr     x0, [sp, #16]
    bl      app_line_u64
    mov     x0, #APP_LOG_DEBUG
    bl      app_line_end
    cmp     x26, #NODE_WORK_IMPORT_BLOCK
    b.ne    9f
    ldr     x10, [sp, #16]
    cmp     x10, #LANTERN_NEED_JUSTIFIED_STATE
    b.eq    9f
    cbz     x24, 9f
    ldr     x9, [x24, #8]                   /* the block's bytes: its slot at byte 100 */
    ldr     x11, [x9, #16]
    cmp     x11, #108
    b.lo    9f
    ldr     x11, [x9, #8]
    add     x11, x9, x11
    ldr     x11, [x11, #100]
    str     x11, [sp, #24]
    bl      app_line_start
    ADDRESS x0, app_m_log_block
    mov     x1, #app_m_log_block_len
    bl      app_line_text
    ldr     x0, [sp, #24]
    bl      app_line_u64
    ldr     x10, [sp, #16]
    cbnz    x10, 1f
    ADDRESS x0, app_m_log_imported
    mov     x1, #app_m_log_imported_len
    bl      app_line_text
    ldr     x9, [x19, #APP_WORK_EVENT]
    ldr     x0, [x9, #NodeEvent_index]
    bl      app_line_u64
    ADDRESS x0, app_m_log_attestations
    mov     x1, #app_m_log_attestations_len
    bl      app_line_text
    mov     x0, #APP_LOG_INFO
    bl      app_line_end
    b       9f
1:  ADDRESS x0, app_m_log_not
    mov     x1, #app_m_log_not_len
    bl      app_line_text
    ldr     x0, [sp, #16]
    bl      app_line_u64
    mov     x0, #APP_LOG_WARN
    bl      app_line_end
9:  UNFRAME 16
END_FUNCTION app_log_work

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
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
    mov     x0, #2
    UNFRAME 0
1:  mov     x0, #0
    UNFRAME 0
END_FUNCTION app_read

/*
 * L1: APP_PATH holds the path of the Arg at x0, or a count past its room when the path does not
 * fit, so the shell gives its error.
 */
LOCAL_FUNCTION app_arg_path
    FRAME 0
    ldp     x9, x10, [x0]
    ADDQ    x11, x19, APP_PATH
    mov     x12, #APP_PATH_MAX
    cmp     x10, x12
    b.hi    1f
    str     x10, [x11, #16]
    add     x0, x11, #24
    ldr     x12, [x19, #APP_ARGS]
    add     x1, x12, x9
    mov     x2, x10
    bl      lantern_copy
    UNFRAME 0
1:  mov     x9, #(APP_PATH_MAX + 1)
    str     x9, [x11, #16]
    UNFRAME 0
END_FUNCTION app_arg_path

/*
 * L2: the anchor of --checkpoint-state and --checkpoint-block in APP_FILE, in the form of
 * anchor.ssz: one ByteList of two, the state's bytes, then the block's message from byte 100 of
 * its SignedBeaconBlock: x0 = 0, or 2 after a line on the standard error. x20 the block file's
 * ByteList, x22 its bytes, x23 the state file's ByteList, x24 its bytes, x25 the buffer's size,
 * x26 the buffer. Locals: L the block file's address and mapped size.
 */
LOCAL_FUNCTION app_checkpoint
    ENTER 16
    add     x0, x19, #(APP_OPTIONS + AppOptions_checkpoint_block)
    bl      app_arg_path
    bl      app_read
    cbnz    x0, 99f
    ldr     x20, [x19, #(APP_FILE + 8)]
    ldr     x22, [x19, #(APP_FILE + 16)]
    cmp     x22, #(100 + 84)                /* the offset and signature, then the message's fixed part */
    b.lo    90f
    ldr     x9, [x19, #(APP_FILE + 24)]
    stp     x20, x9, [sp, #L]
    str     xzr, [x19, #(APP_FILE + 8)]
    add     x0, x19, #(APP_OPTIONS + AppOptions_checkpoint_state)
    bl      app_arg_path
    bl      app_read
    cbnz    x0, 98f
    ldr     x23, [x19, #(APP_FILE + 8)]
    ldr     x24, [x19, #(APP_FILE + 16)]
    add     x9, x24, #7                     /* three ByteList headers, the state to a multiple of 8, the message */
    and     x9, x9, #~7
    add     x9, x9, #72
    sub     x10, x22, #100
    add     x25, x9, x10
    mov     x0, x25
    bl      app_map
    cbz     x0, 97f
    mov     x26, x0
    mov     x9, #24
    sub     x10, x25, #24
    stp     x25, x9, [x26]                  /* the ByteList of both */
    str     x10, [x26, #16]
    add     x10, x24, #24                   /* the state's */
    stp     x10, x9, [x26, #24]
    str     x24, [x26, #40]
    add     x0, x26, #48
    add     x1, x23, #24
    mov     x2, x24
    bl      lantern_copy
    add     x11, x24, #7                    /* the message's, at the first multiple of 8 after the state */
    and     x11, x11, #~7
    add     x11, x11, #48
    add     x11, x26, x11
    sub     x12, x22, #100
    add     x10, x12, #24
    mov     x9, #24
    stp     x10, x9, [x11]
    str     x12, [x11, #16]
    add     x0, x11, #24
    add     x1, x20, #(24 + 100)
    mov     x2, x12
    bl      lantern_copy
    bl      app_file_free                   /* the files go; the buffer takes their place */
    add     x0, sp, #L
    add     x1, sp, #(L + 8)
    CALL_GLOBAL lantern_shell_unmap
    str     xzr, [x19, #APP_FILE]
    str     x26, [x19, #(APP_FILE + 8)]
    sub     x9, x25, #24
    str     x9, [x19, #(APP_FILE + 16)]
    str     x25, [x19, #(APP_FILE + 24)]
    mov     x0, #0
    LEAVE 16
90: bl      app_file_free                   /* <path>: too short */
    bl      app_line_start
    bl      app_line_path
    ADDRESS x0, app_m_short
    mov     x1, #app_m_short_len
    bl      app_line_text
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
    b       99f
97: bl      app_file_free                   /* no memory */
    bl      app_line_start
    ADDRESS x0, app_m_memory
    mov     x1, #app_m_memory_len
    bl      app_line_text
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
98: add     x0, sp, #L                      /* the block file goes */
    add     x1, sp, #(L + 8)
    CALL_GLOBAL lantern_shell_unmap
99: mov     x0, #2
    LEAVE 16
END_FUNCTION app_checkpoint

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
    mov     x0, #APP_LOG_ERROR
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
1:  mov     x25, #0                         /* with a data directory: its anchor.ssz, when there is one */
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_data_dir + 8)]
    cbz     x9, 11f
    ADDRESS x0, app_anchor_name
    mov     x1, #app_anchor_name_len
    ADDQ    x2, x19, APP_PATH
    bl      app_db_file
    ADDQ    x0, x19, APP_PATH
    add     x1, x19, #APP_FILE
    CALL_GLOBAL lantern_shell_read_file
    ldr     x9, [x19, #APP_FILE]
    cbnz    x9, 11f
    mov     x25, #1
    b       12f
11: ldr     x9, [x19, #(APP_OPTIONS + AppOptions_checkpoint_state + 8)]  /* else the checkpoint files */
    cbz     x9, 111f
    bl      app_checkpoint
    cbnz    x0, 99f
    mov     x25, #2
    b       12f
111: ADDRESS x0, app_genesis_name           /* else genesis.ssz: the fork of its slot */
    mov     x1, #app_genesis_name_len
    bl      app_path
    bl      app_read
    cbnz    x0, 99f
12:
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
2:  mov     x9, #24                         /* BeaconState.slot, after the ByteList header of anchor.ssz's state */
    cmp     x25, #0
    csel    x9, x9, xzr, ne
    add     x9, x20, x9
    ldr     x0, [x9, #(24 + 40)]
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
    MOVQ    x26, APP_BLOCK_BYTES            /* the block: of genesis, or of anchor.ssz */
    cbz     x25, 3f
    MOVQ    x9, 1 << 20
    add     x26, x21, x9
3:  mov     x0, #APP_STATE
    mov     x1, x22
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_SCRATCH
    mov     x1, x23
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, #APP_BLOCK
    mov     x1, x26
    bl      app_alloc
    cbz     x0, 97f
    mov     x0, x20
    add     x1, x19, #APP_STATE_ROOM
    SCRATCH x2
    ldr     x3, [x19, #APP_STATE]
    ldr     x4, [x19, #APP_BLOCK]
    ldr     x15, [x19, #APP_FORK]
    cbnz    x25, 31f
    FORK_CALL node_anchor
    b       32f
31: FORK_CALL node_anchor_block
32: cbz     x0, 4f
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
    lsl     x26, x26, #1
    add     x24, x24, #1
    cmp     x24, #APP_TRIES
    b.lo    3b
    mov     x0, #LANTERN_BUFFER_TOO_SMALL
96: mov     x2, x0                          /* genesis.ssz or anchor.ssz: status <n> */
    ADDRESS x0, app_genesis_name
    mov     x1, #app_genesis_name_len
    cbz     x25, 961f
    ADDRESS x0, app_anchor_name
    mov     x1, #app_anchor_name_len
    cmp     x25, #1
    b.eq    961f
    ldp     x9, x1, [x19, #(APP_OPTIONS + AppOptions_checkpoint_state)]
    ldr     x10, [x19, #APP_ARGS]
    add     x0, x10, x9
961:
    bl      app_fail_status
    b       99f
4:  bl      app_file_free
    mov     x0, x21
    bl      app_state_cache
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
    SCRATCH x4
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
    str     x11, [x19, #(APP_ANCHOR + NodeAnchor_history_slot)]  /* anchor.ssz's history lowers it */
    add     x0, x19, #(APP_ANCHOR + 40)
    ldr     x1, [x19, #APP_STATE]
    add     x1, x1, #NODE_STATE_GVR
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x19, #APP_FLAGS]           /* the shell runs discv5 for the node */
    orr     x9, x9, #NODE_FLAG_DISCV5
    ldr     x10, [x19, #(APP_OPTIONS + AppOptions_supernode)]   /* --supernode: every custody group */
    orr     x11, x9, #NODE_FLAG_SUPERNODE
    cmp     x10, #0
    csel    x9, x11, x9, ne
    str     x9, [x19, #APP_FLAGS]
    bl      app_engine_conf                 /* the execution engine */
    cbnz    x0, 99f
    bl      app_builder_conf                /* the builder */
    cbnz    x0, 99f
    bl      app_key                         /* the key, and the anchor's node ID */
    cbnz    x0, 94f
    add     x0, x19, #APP_NODE_ROOM         /* the node */
    ADDRESS x1, app_node_room
    mov     x2, #(8 * NODE_ROOM_FIELDS)
    bl      lantern_copy
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_target_peers)]
    str     x9, [x19, #(APP_NODE_ROOM + NodeRoom_peers)]
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_http_max_connections)]
    str     x9, [x19, #(APP_NODE_ROOM + NodeRoom_api_streams)]
    bl      app_db_start                    /* the history's files */
    cmp     x25, #1
    b.ne    13f
    bl      app_db_history                  /* from anchor.ssz: the segments there */
13:
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
    cbz     x25, 14f
    cmp     x25, #1
    b.eq    141f
    bl      app_line_start                  /* checkpoint at slot <n> */
    ADDRESS x0, app_m_checkpoint
    mov     x1, #app_m_checkpoint_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_ANCHOR + 32)]
    bl      app_line_u64
    mov     x0, #APP_LOG_INFO
    bl      app_line_end
    b       14f
141: bl     app_db_scan_all                 /* from anchor.ssz: the history's segments to the node */
    cbnz    x0, 99f
    bl      app_line_start                  /* restart at slot <n> */
    ADDRESS x0, app_m_restart
    mov     x1, #app_m_restart_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_ANCHOR + 32)]
    bl      app_line_u64
    mov     x0, #APP_LOG_INFO
    bl      app_line_end
14:
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
    mov     x0, #APP_KZG                    /* the KZG trusted setup */
    MOVQ    x1, CRYPTO_KZG_SETTINGS_SIZE
    bl      app_alloc
    cbz     x0, 97f
    ADDRESS x0, app_kzg_g1_lagrange
    ADDRESS x1, app_kzg_g1_monomial
    ADDRESS x2, app_kzg_g2_monomial
    ldr     x3, [x19, #APP_KZG]
    CALL_GLOBAL crypto_kzg_trusted_setup_of_bytes
    cbnz    x0, 93f
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
    bl      app_lc_start                    /* BufferId 2: the light client store */
    cbnz    x0, 97f
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
    mov     x0, #APP_LOG_INFO
    bl      app_line_end
    mov     x0, #0
    LEAVE 16
93: mov     x2, x0                          /* the KZG trusted setup: status <n> */
    ADDRESS x0, app_m_kzg
    mov     x1, #app_m_kzg_len
    bl      app_fail_status
    b       99f
94: mov     x2, x0                          /* the node: status <n> */
    ADDRESS x0, app_m_node
    mov     x1, #app_m_node_len
    bl      app_fail_status
    b       99f
97: bl      app_line_start                  /* no memory */
    ADDRESS x0, app_m_memory
    mov     x1, #app_m_memory_len
    bl      app_line_text
98: mov     x0, #APP_LOG_ERROR
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

/*
 * L1: x0 = new memory with a copy of the x1 bytes at x0, or 0. With a source and size of
 * multiples of 8, a page of the source that is all zero bytes is not written: the new memory is
 * zero already, and the OS keeps no memory for a page nobody writes. x20 the source, x21 the
 * size, x22 the copy, x23 the page's offset, x24 its bytes.
 */
LOCAL_FUNCTION app_dup
    ENTER 0
    mov     x20, x0
    mov     x21, x1
    mov     x0, x21
    bl      app_map
    cbz     x0, 9f
    mov     x22, x0
    orr     x9, x20, x21
    tst     x9, #7
    b.eq    1f
    mov     x1, x20                         /* not multiples of 8: all of it */
    mov     x2, x21
    bl      lantern_copy
    b       8f
1:  mov     x23, #0
2:  subs    x24, x21, x23                   /* the next page: all zero, or a copy */
    b.ls    8f
    mov     x9, #4096
    cmp     x24, x9
    csel    x24, x24, x9, lo
    add     x10, x20, x23
    mov     x11, #0
3:  ldr     x12, [x10, x11]
    cbnz    x12, 4f
    add     x11, x11, #8
    cmp     x11, x24
    b.lo    3b
    b       5f
4:  add     x0, x22, x23
    mov     x1, x10
    mov     x2, x24
    bl      lantern_copy
5:  add     x23, x23, x24
    b       2b
8:  mov     x0, x22
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
 * L1: the node (x0 = 0), the store (1) or the Seen (2) moves to new memory, with the field of its
 * room at byte offset x1 doubled, or each field for x1 = 2^64 - 1: x0 = 0, or 1. x20 the kind, x21 the pair, x22 the room, x23 the room's fields,
 * x24 the new memory. Locals: L a size, L+8 an address.
 */
LOCAL_FUNCTION app_grow
    ENTER 16
    mov     x20, x0
    mov     x9, #APP_NODE
    mov     x10, #APP_NODE_ROOM
    mov     x23, #NODE_ROOM_FIELDS
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
    cmn     x1, #1                          /* one field: its offset, below the fields and a multiple of 8 */
    b.eq    31f
    lsl     x9, x23, #3
    cmp     x1, x9
    b.hs    9f
    tst     x1, #7
    b.ne    9f
    ldr     x10, [x22, x1]
    lsl     x10, x10, #1
    str     x10, [x22, x1]
    b       4f
31: mov     x9, #0
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
 * L2: x0 = 0 with the light client store as BufferId 2 (node.md, lantern_node_init: Caller must):
 * lantern_lc_store_init of the anchor state and block with the APP_LC_* capacities; else 1. x20
 * the store, x21 its size. APP_TMP: the LcRoom, then the size.
 */
LOCAL_FUNCTION app_lc_start
    ENTER 0
    add     x9, x19, #APP_TMP
    mov     x10, #APP_LC_BLOCKS
    mov     x11, #APP_LC_FINALIZED
    stp     x10, x11, [x9]
    mov     x10, #APP_LC_PERIODS
    mov     x11, #APP_LC_BOOTSTRAPS
    stp     x10, x11, [x9, #16]
    mov     x10, #APP_LC_HEADERS
    mov     x11, #APP_LC_COMMITTEES
    stp     x10, x11, [x9, #32]
    mov     x10, #APP_LC_UPDATES
    str     x10, [x9, #48]
    mov     x0, x9
    add     x1, x9, #LcRoom__mem
    CALL_GLOBAL lantern_lc_store_size
    cbnz    x0, 9f
    ldr     x21, [x19, #(APP_TMP + LcRoom__mem)]
    mov     x0, x21
    bl      app_map
    cbz     x0, 9f
    mov     x20, x0
    str     x21, [x20]
    add     x0, x19, #APP_TMP
    add     x1, x19, #APP_CONFIG
    ldr     x2, [x19, #APP_STATE]
    ldr     x3, [x19, #APP_BLOCK]
    SCRATCH x4
    mov     x5, x20
    CALL_GLOBAL lantern_lc_store_init
    cbnz    x0, 9f
    mov     x0, #NODE_LC_ID
    mov     x1, x20
    mov     x2, x21
    bl      app_buf_add
    cbnz    x0, 9f
    LEAVE 0
9:  mov     x0, #1
    LEAVE 0
END_FUNCTION app_lc_start

/*
 * L2: x0 = 0 when the light client store of the table entry x0 is in a new buffer with twice the
 * capacities of each part (lantern_lc_store_copy); else 1. x20 the entry, x21 the new buffer, x22
 * its size. APP_TMP: the LcRoom, then the size.
 */
LOCAL_FUNCTION app_lc_grow
    ENTER 0
    mov     x20, x0
    ldr     x9, [x20, #8]
    add     x10, x19, #APP_TMP
    mov     x11, #0
1:  add     x12, x9, #LcStore_room
    ldr     x12, [x12, x11, lsl #3]
    lsl     x12, x12, #1
    str     x12, [x10, x11, lsl #3]
    add     x11, x11, #1
    cmp     x11, #7
    b.lo    1b
    mov     x0, x10
    add     x1, x10, #LcRoom__mem
    CALL_GLOBAL lantern_lc_store_size
    cbnz    x0, 9f
    ldr     x22, [x19, #(APP_TMP + LcRoom__mem)]
    mov     x0, x22
    bl      app_map
    cbz     x0, 9f
    mov     x21, x0
    str     x22, [x21]
    ldr     x0, [x20, #8]
    add     x1, x19, #APP_TMP
    mov     x2, x21
    CALL_GLOBAL lantern_lc_store_copy
    cbnz    x0, 8f
    add     x0, x20, #8                     /* the old buffer goes */
    add     x1, x20, #16
    CALL_GLOBAL lantern_shell_unmap
    stp     x21, x22, [x20, #8]
    mov     x0, #0
    LEAVE 0
8:  str     x21, [sp, #-16]!                /* the new one goes */
    str     x22, [sp, #8]
    mov     x0, sp
    add     x1, sp, #8
    CALL_GLOBAL lantern_shell_unmap
    add     sp, sp, #16
9:  mov     x0, #1
    LEAVE 0
END_FUNCTION app_lc_grow

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
    bl      app_work_data
    mov     x24, x0
    cmn     x21, #1                         /* an id with no buffer */
    ccmn    x22, #1, #4, ne
    ccmn    x23, #1, #4, ne
    ccmn    x24, #1, #4, ne
    b.eq    90f
    MOVQ    x10, NodeEvent_api_bytes + 24 + NODE_API_CHUNK
    cmp     x26, #NODE_WORK_API_CHUNK       /* API_CHUNK: room for a whole chunk */
    b.eq    15f
    cmp     x26, #NODE_WORK_PUBLISH_DECODE  /* PUBLISH_DECODE and PUBLISH_CHECK: room for the bytes of data */
    b.eq    16f
    cmp     x26, #NODE_WORK_PUBLISH_CHECK
    b.ne    1f
16: cbz     x24, 1f
    ldr     x10, [x24, #16]
    add     x10, x10, #(NodeEvent_chunk + 7)
    and     x10, x10, #~7
15: ldr     x9, [x19, #(APP_WORK_EVENT + 8)]
    cmp     x9, x10
    b.hs    1f
    str     x10, [sp, #-16]!
    mov     x0, #APP_WORK_EVENT
    bl      app_unmap
    ldr     x1, [sp], #16
    mov     x0, #APP_WORK_EVENT
    bl      app_alloc
    cbz     x0, 91f
1:  ldr     x9, [x19, #APP_WORK_EVENT]      /* the event's room */
    ldr     x10, [x19, #(APP_WORK_EVENT + 8)]
    str     x10, [x9]
    sub     sp, sp, #32                     /* the ninth to eleventh arguments: settings, scratch, event */
    ldr     x9, [x19, #APP_KZG]
    str     x9, [sp]
    SCRATCH x9
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
    cmp     x26, #NODE_WORK_LC_SERVE
    b.eq    2f
    cmp     x26, #NODE_WORK_LC_PUBLISH
    b.eq    2f
    cmp     x26, #NODE_WORK_NEW_PAYLOAD
    b.eq    2f
    cmp     x26, #NODE_WORK_FORKCHOICE
    b.eq    2f
    cmp     x26, #NODE_WORK_API_ENCODE
    b.eq    2f
    cmp     x26, #NODE_WORK_API_CHUNK
    b.eq    2f
    cmp     x26, #NODE_WORK_API_EVENT
    b.eq    2f
    cmp     x26, #NODE_WORK_PREPARE_PAYLOAD
    b.eq    2f
    cmp     x26, #NODE_WORK_GET_PAYLOAD
    b.eq    2f
    cmp     x26, #NODE_WORK_PRODUCE_BLOCK
    b.eq    2f
    cmp     x26, #NODE_WORK_PUBLISH_DECODE
    b.eq    2f
    cmp     x26, #NODE_WORK_PUBLISH_SIDECAR
    b.eq    2f
    cmp     x26, #NODE_WORK_PUBLISH_CHECK   /* PUBLISH_CHECK: the Seen, and the parent's state */
    b.eq    31f
    cmp     x26, #NODE_WORK_API_SUBMIT      /* API_SUBMIT: the Seen, and a larger event */
    b.eq    7f
    cmp     x26, #NODE_WORK_GOSSIP          /* GOSSIP: the Seen, and the proposer state */
    b.eq    3f
    cmp     x26, #NODE_WORK_TARGET_STATE    /* TARGET_STATE, SLOTS, and IMPORT_BLOCK with store room: state_a */
    b.eq    4f
    cmp     x26, #NODE_WORK_SLOTS
    b.eq    4f
    cmp     x26, #NODE_WORK_REPLAY
    b.eq    4f
    cmp     x26, #NODE_WORK_UPGRADE         /* UPGRADE: state_b, the upgrade's buffer */
    b.eq    6f
    cmp     x26, #NODE_WORK_LC_BLOCK        /* the light client works: state_c, the light client store */
    b.eq    17f
    cmp     x26, #NODE_WORK_LC_HEAD
    b.eq    17f
    cmp     x26, #NODE_WORK_IMPORT_BLOCK
    b.ne    5f
    ldr     x9, [x19, #APP_STORE]
    ldr     x9, [x9, #(Store_blocks + 8)]
    ldr     x10, [x19, #(APP_STORE_ROOM + StoreRoom_nodes)]
    cmp     x9, x10
    b.lo    4f
5:  mov     x0, #1                          /* else the store */
    mov     x1, #-1
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
    mov     x1, #-1
    bl      app_grow
    cbnz    x0, 91f
    cbz     x22, 1b
    mov     x0, x22
    bl      app_regrow
    cbnz    x0, 91f
    b       1b
31: mov     x0, #2
    mov     x1, #-1
    bl      app_grow
    cbnz    x0, 91f
4:  cbz     x21, 91f
    mov     x0, x21
    bl      app_regrow
    cbnz    x0, 91f
    b       1b
6:  cbz     x22, 91f
    mov     x0, x22
    bl      app_regrow
    cbnz    x0, 91f
    b       1b
17: cbz     x23, 91f
    mov     x0, x23
    bl      app_lc_grow
    cbnz    x0, 91f
    b       1b
7:  mov     x0, #2
    mov     x1, #-1
    bl      app_grow
    cbnz    x0, 91f
    b       2b
8:  bl      app_log_work
    ldr     x0, [x19, #APP_WORK_EVENT]      /* the WORK_DONE event */
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

/*
 * L1: the history's files: no file open, no segment mapped; with a data directory, the node gets
 * NODE_FLAG_DB and room for a segment of slots, and the directory is made (one already there
 * will do; a failure shows at its first file). x27 the AppDb.
 */
LOCAL_FUNCTION app_db_start
    ENTER 0
    ADDQ    x27, x19, APP_DB
    mov     x9, #-1
    stp     x9, x9, [x27, #AppDb_segment]
    mov     x10, #0
1:  add     x11, x27, #AppDb_maps
    add     x11, x11, x10, lsl #5
    str     x9, [x11]
    str     xzr, [x11, #8]
    add     x10, x10, #1
    cmp     x10, #APP_DB_MAP_COUNT
    b.lo    1b
    str     xzr, [x27, #AppDb_next_map]
    str     x9, [x27, #AppDb_anchor_slot]
    ldr     x10, [x19, #(APP_ANCHOR + 32)]  /* the Db from the anchor's slot */
    str     x10, [x19, #(APP_ANCHOR + NodeAnchor_history_slot)]
    ldr     x21, [x19, #(APP_OPTIONS + AppOptions_data_dir + 8)]
    cbz     x21, 9f
    ldr     x9, [x19, #APP_FLAGS]
    orr     x9, x9, #NODE_FLAG_DB
    str     x9, [x19, #APP_FLAGS]
    MOVQ    x9, DB_SEGMENT_SLOTS
    str     x9, [x19, #(APP_NODE_ROOM + NodeRoom_db_slots)]
    mov     x9, #APP_DB_ROOTS
    str     x9, [x19, #(APP_NODE_ROOM + NodeRoom_db_roots)]
    cmp     x21, #APP_PATH_MAX
    b.hi    9f
    ADDQ    x22, x19, APP_PATH              /* the directory's path */
    str     x21, [x22, #16]
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_data_dir)]
    ldr     x10, [x19, #APP_ARGS]
    add     x1, x10, x9
    add     x0, x22, #24
    mov     x2, x21
    bl      lantern_copy
    mov     x0, x22
    add     x1, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_mkdir
9:  LEAVE 0
END_FUNCTION app_db_start

/* L1: the path of segment x1 of blocks (x0 0) or sidecars (1) in the data directory, <dir>/b<n>.seg or <dir>/s<n>.seg: a ByteList at APP_PATH. x20 the kind, x21 the segment, x22 the next byte. Locals: L 24 digits. */
LOCAL_FUNCTION app_db_path
    ENTER 32
    mov     x20, x0
    mov     x21, x1
    ADDQ    x22, x19, APP_PATH
    ldr     x2, [x19, #(APP_OPTIONS + AppOptions_data_dir + 8)]
    cmp     x2, #(APP_PATH_MAX - 32)
    b.hi    8f
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_data_dir)]
    ldr     x10, [x19, #APP_ARGS]
    add     x1, x10, x9
    add     x0, x22, #24
    add     x22, x0, x2
    bl      lantern_copy
    mov     w9, #0x2f                       /* / */
    strb    w9, [x22], #1
    mov     w9, #0x62                       /* b */
    mov     w10, #0x73                      /* s */
    cmp     x20, #0
    csel    w9, w10, w9, ne
    strb    w9, [x22], #1
    add     x11, sp, #(L + 24)              /* the number's digits, from the last */
    mov     x12, x21
    mov     x13, #10
1:  udiv    x14, x12, x13
    msub    x15, x14, x13, x12
    add     w15, w15, #0x30
    strb    w15, [x11, #-1]!
    mov     x12, x14
    cbnz    x12, 1b
    add     x14, sp, #(L + 24)
2:  cmp     x11, x14
    b.hs    3f
    ldrb    w15, [x11], #1
    strb    w15, [x22], #1
    b       2b
3:  mov     w9, #0x2e                       /* .seg */
    strb    w9, [x22], #1
    mov     w9, #0x73
    strb    w9, [x22], #1
    mov     w9, #0x65
    strb    w9, [x22], #1
    mov     w9, #0x67
    strb    w9, [x22], #1
    ADDQ    x10, x19, APP_PATH
    add     x9, x10, #24
    sub     x9, x22, x9
    str     x9, [x10, #16]
    LEAVE 32
8:  ADDQ    x10, x19, APP_PATH              /* a count past the room: the shell gives its error */
    mov     x9, #(APP_PATH_MAX + 1)
    str     x9, [x10, #16]
    LEAVE 32
END_FUNCTION app_db_path

/*
 * L1: NODE_ACT_DB_APPEND x0: the record at the end of its segment file, its DbRecord, its bytes
 * and zero bytes to a multiple of 8. A file that is not the open one of its kind opens, and is cut
 * to the record's offset first. A failure gives a line on the standard error, and the file closes,
 * so the next record opens it again. x20 the action, x21 the kind (0 blocks, 1 sidecars), x22 the
 * bytes' table entry, x23 the file, x27 the AppDb. Locals: L a ByteList header, L+24 a u64, L+32 zero bytes.
 */
LOCAL_FUNCTION app_db_append
    ENTER 48
    mov     x20, x0
    ADDQ    x27, x19, APP_DB
    ldr     x21, [x20, #32]
    and     x21, x21, #1
    ldr     x0, [x20, #16]
    bl      app_buf_find
    cbz     x0, 99f
    mov     x22, x0
    add     x23, x27, #AppDb_file
    add     x23, x23, x21, lsl #3
    add     x9, x27, #AppDb_segment
    ldr     x10, [x9, x21, lsl #3]
    ldr     x11, [x20, #24]
    cmp     x10, x11
    b.eq    2f
    cmn     x10, #1                         /* another file of the kind: it closes */
    b.eq    1f
    mov     x0, x23
    CALL_GLOBAL lantern_shell_close
    mov     x9, #-1
    add     x10, x27, #AppDb_segment
    str     x9, [x10, x21, lsl #3]
1:  mov     x0, x21                         /* the segment's file, to append to, cut to the offset */
    ldr     x1, [x20, #24]
    bl      app_db_path
    mov     x9, #1
    str     x9, [sp, #(L + 24)]
    ADDQ    x0, x19, APP_PATH
    add     x1, sp, #(L + 24)
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_open
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 90f
    ldr     x9, [x27, #(AppDb_op + 8)]
    str     x9, [x23]
    mov     x0, x23
    add     x1, x20, #40
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_truncate
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
    ldr     x9, [x20, #24]
    add     x10, x27, #AppDb_segment
    str     x9, [x10, x21, lsl #3]
2:  add     x9, x20, #48                    /* the DbRecord: a ByteList of the action's 64 bytes */
    add     x10, sp, #L
    sub     x9, x9, x10
    mov     x11, #24
    stp     x11, x9, [x10]
    mov     x11, #DbRecord__mem
    str     x11, [x10, #16]
    mov     x0, x23
    add     x1, sp, #L
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_append
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
    mov     x0, x23                         /* the bytes */
    ldr     x1, [x22, #8]
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_append
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
    ldr     x9, [x22, #8]                   /* zero bytes to a multiple of 8 */
    ldr     x9, [x9, #16]
    neg     x9, x9
    and     x9, x9, #7
    cbz     x9, 99f
    add     x10, sp, #L
    str     xzr, [sp, #(L + 32)]
    mov     x11, #32
    mov     x12, #24
    stp     x12, x11, [x10]
    str     x9, [x10, #16]
    mov     x0, x23
    add     x1, sp, #L
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_append
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
99: LEAVE 48
89: mov     x0, x23                         /* the file closes */
    CALL_GLOBAL lantern_shell_close
    mov     x9, #-1
    add     x10, x27, #AppDb_segment
    str     x9, [x10, x21, lsl #3]
90: ldr     x9, [x27, #AppDb_op]            /* cannot write <path>: error <n> */
    str     x9, [sp, #(L + 24)]
    mov     x0, x21
    ldr     x1, [x20, #24]
    bl      app_db_path
    bl      app_line_start
    ADDRESS x0, app_m_write
    mov     x1, #app_m_write_len
    bl      app_line_text
    bl      app_line_path
    ADDRESS x0, app_m_error
    mov     x1, #app_m_error_len
    bl      app_line_text
    ldr     x0, [sp, #(L + 24)]
    bl      app_line_u64
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
    LEAVE 48
END_FUNCTION app_db_append

/*
 * L1: NODE_ACT_DB_DROP x0: the segment's file goes: the open file of its kind, when it is that
 * segment, closes; a map of it goes; then the file is deleted. x20 the action, x21 the kind (0
 * blocks, 1 sidecars), x22 the segment, x23 the map key, x25 a map's index, x26 a map, x27 the AppDb.
 */
LOCAL_FUNCTION app_db_drop
    ENTER 0
    mov     x20, x0
    ADDQ    x27, x19, APP_DB
    ldr     x21, [x20, #24]
    and     x21, x21, #1
    ldr     x22, [x20, #16]
    add     x9, x27, #AppDb_segment         /* the open file of its kind */
    ldr     x10, [x9, x21, lsl #3]
    cmp     x10, x22
    b.ne    1f
    add     x0, x27, #AppDb_file
    add     x0, x0, x21, lsl #3
    CALL_GLOBAL lantern_shell_close
    mov     x9, #-1
    add     x10, x27, #AppDb_segment
    str     x9, [x10, x21, lsl #3]
1:  lsl     x23, x21, #63                   /* its map */
    orr     x23, x23, x22
    mov     x25, #0
2:  cmp     x25, #APP_DB_MAP_COUNT
    b.hs    4f
    add     x26, x27, #AppDb_maps
    add     x26, x26, x25, lsl #5
    ldr     x9, [x26]
    cmp     x9, x23
    b.ne    3f
    ldr     x9, [x26, #8]
    cbz     x9, 21f
    add     x0, x26, #8
    add     x1, x26, #24
    CALL_GLOBAL lantern_shell_unmap_file
21: mov     x9, #-1
    str     x9, [x26]
    str     xzr, [x26, #8]
3:  add     x25, x25, #1
    b       2b
4:  mov     x0, x21                         /* the file */
    mov     x1, x22
    bl      app_db_path
    ADDQ    x0, x19, APP_PATH
    add     x1, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_remove
    LEAVE 0
END_FUNCTION app_db_drop

/*
 * L0: x0 = the AppDb's view entry of the record at offset x23 of the mapped segment x26: its
 * ByteList in place, at byte DbRecord_bytes of the record; 0 when the record is not all inside
 * the map, or its ByteList header is not of its bytes. Uses x9-x13, x16.
 */
LOCAL_FUNCTION app_db_record
    UNWIND_END_PROLOGUE
    ldr     x9, [x26, #8]
    cbz     x9, 8f
    ldr     x10, [x26, #16]
    adds    x11, x23, #DbRecord__mem
    b.cs    8f
    cmp     x11, x10
    b.hi    8f
    add     x13, x9, x23                    /* the record, its bytes inside */
    ldr     x12, [x13, #DbRecord_length]
    sub     x10, x10, x11
    cmp     x12, x10
    b.hi    8f
    ldr     x9, [x13, #DbRecord_bytes]      /* its ByteList: size 24 + length, offset 24 */
    add     x11, x12, #24
    cmp     x9, x11
    b.ne    8f
    ldr     x9, [x13, #(DbRecord_bytes + 8)]
    cmp     x9, #24
    b.ne    8f
    ADDQ    x10, x19, APP_DB + AppDb_view
    add     x13, x13, #DbRecord_bytes
    str     x13, [x10, #8]
    mov     x0, x10
    ret
8:  mov     x0, #0
    ret
END_FUNCTION app_db_record

/*
 * L1: x0 = the table entry of a work's data BufferId x0 as app_work_entry gives; for a
 * NODE_DB_REF, the AppDb's view entry of its record in the segment, mapped again when the file
 * grew past the map, or 2^64 - 1 when the record is not there. x20 the reference, x21 the kind,
 * x22 the segment, x23 the offset, x24 the map's key, x25 a map's index, x26 a map, x27 the AppDb.
 */
LOCAL_FUNCTION app_work_data
    ENTER 0
    tbnz    x0, #63, 1f
    bl      app_work_entry
    LEAVE 0
1:  mov     x20, x0
    ADDQ    x27, x19, APP_DB
    ubfx    x21, x20, #62, #1
    ubfx    x22, x20, #48, #14
    and     x23, x20, #0xffffffffffff
    lsl     x24, x21, #63
    orr     x24, x24, x22
    mov     x25, #0                         /* the map of the segment */
2:  cmp     x25, #APP_DB_MAP_COUNT
    b.hs    5f
    add     x26, x27, #AppDb_maps
    add     x26, x26, x25, lsl #5
    ldr     x9, [x26]
    cmp     x9, x24
    b.eq    3f
    add     x25, x25, #1
    b       2b
3:  bl      app_db_record
    cbnz    x0, 9f
    b       6f
5:  ldr     x25, [x27, #AppDb_next_map]     /* else the next entry in turn */
    add     x9, x25, #1
    and     x9, x9, #(APP_DB_MAP_COUNT - 1)
    str     x9, [x27, #AppDb_next_map]
    add     x26, x27, #AppDb_maps
    add     x26, x26, x25, lsl #5
6:  ldr     x9, [x26, #8]                   /* its old map goes */
    cbz     x9, 7f
    add     x0, x26, #8
    add     x1, x26, #24
    CALL_GLOBAL lantern_shell_unmap_file
7:  mov     x9, #-1
    str     x9, [x26]
    str     xzr, [x26, #8]
    mov     x0, x21
    mov     x1, x22
    bl      app_db_path
    ADDQ    x0, x19, APP_PATH
    add     x1, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_map_file
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 8f
    ldr     x9, [x27, #(AppDb_op + 8)]
    cbz     x9, 8f
    str     x24, [x26]
    str     x9, [x26, #8]
    ldr     x9, [x27, #(AppDb_op + 16)]
    str     x9, [x26, #16]
    ldr     x9, [x27, #(AppDb_op + 24)]
    str     x9, [x26, #24]
    bl      app_db_record
    cbnz    x0, 9f
8:  mov     x0, #-1
9:  LEAVE 0
END_FUNCTION app_work_data

/* L1: <dir>/<the x1 bytes of the name at x0> of the data directory, as a ByteList at x2 of APP_PATH_MAX bytes of room. x20 the name, x21 its length, x22 the ByteList. */
LOCAL_FUNCTION app_db_file
    ENTER 0
    mov     x20, x0
    mov     x21, x1
    mov     x22, x2
    MOVQ    x9, 24 + APP_PATH_MAX
    mov     x10, #24
    stp     x9, x10, [x22]
    ldr     x2, [x19, #(APP_OPTIONS + AppOptions_data_dir + 8)]
    add     x9, x2, x21
    add     x9, x9, #1
    cmp     x9, #APP_PATH_MAX
    b.hi    8f
    str     x9, [x22, #16]
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_data_dir)]
    ldr     x10, [x19, #APP_ARGS]
    add     x1, x10, x9
    add     x0, x22, #24
    bl      lantern_copy
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_data_dir + 8)]
    add     x0, x22, #24
    add     x0, x0, x9
    mov     w9, #0x2f                       /* / */
    strb    w9, [x0], #1
    mov     x1, x20
    mov     x2, x21
    bl      lantern_copy
    LEAVE 0
8:  mov     x9, #(APP_PATH_MAX + 1)         /* a count past the room: the shell gives its error */
    str     x9, [x22, #16]
    LEAVE 0
END_FUNCTION app_db_file

/* L1: x0 = 1 when the block segment x0's file is there (it opens to read), else 0. x27 the AppDb. Locals: L the mode. */
LOCAL_FUNCTION app_db_exists
    ENTER 16
    ADDQ    x27, x19, APP_DB
    mov     x1, x0
    mov     x0, #0
    bl      app_db_path
    str     xzr, [sp, #L]
    ADDQ    x0, x19, APP_PATH
    add     x1, sp, #L
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_open
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 8f
    add     x0, x27, #(AppDb_op + 8)
    CALL_GLOBAL lantern_shell_close
    mov     x0, #1
    LEAVE 16
8:  mov     x0, #0
    LEAVE 16
END_FUNCTION app_db_exists

/*
 * L1: for a start from anchor.ssz: the first block segment file there, from 0 to the anchor's
 * segment, gives the anchor's history_slot; the Db has room for the slots from it to the last
 * block segment file there, from the anchor's on, and a segment more, and a power of two of roots
 * above twice them. x20 a segment, x21 the anchor's segment, x22 the first, x23 the last.
 */
LOCAL_FUNCTION app_db_history
    ENTER 0
    ldr     x21, [x19, #(APP_ANCHOR + 32)]
    lsr     x21, x21, #DB_SEGMENT_SHIFT
    mov     x22, x21
    mov     x20, #0
1:  cmp     x20, x21
    b.hi    2f
    mov     x0, x20
    bl      app_db_exists
    cbnz    x0, 11f
    add     x20, x20, #1
    b       1b
11: mov     x22, x20
2:  mov     x23, x21
    add     x20, x21, #1
3:  mov     x0, x20
    bl      app_db_exists
    cbz     x0, 4f
    mov     x23, x20
    add     x20, x20, #1
    b       3b
4:  lsl     x9, x22, #DB_SEGMENT_SHIFT
    str     x9, [x19, #(APP_ANCHOR + NodeAnchor_history_slot)]
    sub     x9, x23, x22
    add     x9, x9, #2
    lsl     x9, x9, #DB_SEGMENT_SHIFT
    str     x9, [x19, #(APP_NODE_ROOM + NodeRoom_db_slots)]
    lsl     x10, x9, #1
    clz     x11, x10
    mov     x12, #64
    sub     x11, x12, x11
    mov     x12, #1
    lsl     x10, x12, x11
    str     x10, [x19, #(APP_NODE_ROOM + NodeRoom_db_roots)]
    LEAVE 0
END_FUNCTION app_db_history

/*
 * L1: for a start from anchor.ssz: each segment file there, the blocks' then the sidecars', from
 * the segment of history_slot to the end of the Db's room, goes to lantern_node_db_scan; a file
 * with bytes after its last whole record is cut there: x0 = 0, or 2 after a line on the standard
 * error. x20 the kind, x21 the segment, x22 the end, x26 a status, x27 the AppDb. Locals: L a
 * ByteList header, L+24 valid, L+32 the segment, L+40 the kind, L+48 the file's size or a mode,
 * L+56 a file.
 */
LOCAL_FUNCTION app_db_scan_all
    ENTER 64
    ADDQ    x27, x19, APP_DB
    ldr     x9, [x19, #(APP_ANCHOR + NodeAnchor_history_slot)]
    lsr     x9, x9, #DB_SEGMENT_SHIFT
    ldr     x22, [x19, #(APP_NODE_ROOM + NodeRoom_db_slots)]
    lsr     x22, x22, #DB_SEGMENT_SHIFT
    add     x22, x22, x9
    mov     x20, #0
1:  ldr     x21, [x19, #(APP_ANCHOR + NodeAnchor_history_slot)]
    lsr     x21, x21, #DB_SEGMENT_SHIFT
2:  cmp     x21, x22
    b.hs    7f
    mov     x0, x20
    mov     x1, x21
    bl      app_db_path
    ADDQ    x0, x19, APP_PATH
    add     x1, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_map_file
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 6f                          /* not there */
    ldr     x9, [x27, #(AppDb_op + 8)]
    cbz     x9, 6f                          /* empty */
    add     x11, sp, #L                     /* its bytes: a ByteList of the map */
    sub     x12, x9, x11
    mov     x13, #24
    stp     x13, x12, [x11]
    ldr     x10, [x27, #(AppDb_op + 16)]
    str     x10, [x11, #16]
    str     x10, [sp, #(L + 48)]
    stp     x21, x20, [sp, #(L + 32)]
    ldr     x0, [x19, #APP_NODE]
    add     x1, sp, #(L + 32)
    add     x2, sp, #(L + 40)
    add     x3, sp, #L
    add     x4, sp, #(L + 24)
    CALL_GLOBAL lantern_node_db_scan
    mov     x26, x0
    add     x0, x27, #(AppDb_op + 8)
    add     x1, x27, #(AppDb_op + 24)
    CALL_GLOBAL lantern_shell_unmap_file
    cbnz    x26, 8f
    ldr     x9, [sp, #(L + 24)]             /* bytes after the last whole record: the file is cut there */
    ldr     x10, [sp, #(L + 48)]
    cmp     x9, x10
    b.hs    6f
    mov     x9, #1
    str     x9, [sp, #(L + 48)]
    ADDQ    x0, x19, APP_PATH
    add     x1, sp, #(L + 48)
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_open
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 6f
    ldr     x9, [x27, #(AppDb_op + 8)]
    str     x9, [sp, #(L + 56)]
    add     x0, sp, #(L + 56)
    add     x1, sp, #(L + 24)
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_truncate
    add     x0, sp, #(L + 56)
    CALL_GLOBAL lantern_shell_close
6:  add     x21, x21, #1
    b       2b
7:  add     x20, x20, #1
    cmp     x20, #2
    b.lo    1b
    mov     x0, #0
    LEAVE 64
8:  ADDQ    x9, x19, APP_PATH               /* <path>: status <n> */
    add     x0, x9, #24
    ldr     x1, [x9, #16]
    mov     x2, x26
    bl      app_fail_status
    LEAVE 64
END_FUNCTION app_db_scan_all

/*
 * L1: NODE_ACT_DB_STATE x0, with no anchor written in this run or one DB_SEGMENT_SLOTS slots
 * back: the open segment files are synced; <dir>/anchor.tmp gets two ByteLists, the second at the
 * first multiple of 8 after the first: the state's SSZ bytes, then those of its block's message;
 * it is synced and renamed over <dir>/anchor.ssz, and the directory is synced. A failure gives a
 * line on the standard error. x20 the action, x21 the state's entry, x22 the block's entry, x23
 * the state's ByteList, x24 its size, x27 the AppDb. Locals: L a ByteList header, L+24 a u64,
 * L+32 zero bytes, L+40 a size, L+48 the fork, L+56 the file, L+64 the message's ByteList header.
 */
LOCAL_FUNCTION app_db_state
    ENTER 96
    mov     x20, x0
    ADDQ    x27, x19, APP_DB
    mov     x23, #0
    ldr     x9, [x27, #AppDb_anchor_slot]
    cmn     x9, #1
    b.eq    1f
    MOVQ    x10, DB_SEGMENT_SLOTS
    add     x9, x9, x10
    ldr     x10, [x20, #32]
    cmp     x10, x9
    b.lo    99f
1:  ldr     x0, [x20, #16]
    bl      app_buf_find
    cbz     x0, 99f
    mov     x21, x0
    ldr     x0, [x20, #24]
    bl      app_buf_find
    cbz     x0, 99f
    mov     x22, x0
    mov     x9, #0                          /* the open segment files are synced */
2:  add     x10, x27, #AppDb_segment
    ldr     x11, [x10, x9, lsl #3]
    cmn     x11, #1
    b.eq    3f
    str     x9, [sp, #(L + 24)]
    add     x0, x27, #AppDb_file
    add     x0, x0, x9, lsl #3
    add     x1, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_sync
    ldr     x9, [sp, #(L + 24)]
3:  add     x9, x9, #1
    cmp     x9, #2
    b.lo    2b
    ldr     x0, [x20, #32]                  /* the state's SSZ bytes: their size, then the bytes */
    add     x1, x19, #APP_CONFIG
    bl      app_fork
    str     x0, [sp, #(L + 48)]
    mov     x9, #24
    str     x9, [sp, #L]
    str     xzr, [sp, #(L + 40)]
    mov     x15, x0
    ldr     x0, [x21, #8]
    SCRATCH x1
    add     x2, sp, #L
    add     x3, sp, #(L + 40)
    FORK_CALL node_state_bytes
    ldr     x24, [sp, #(L + 40)]
    cmp     x24, #24
    b.ls    99f
    mov     x0, x24
    bl      app_map
    cbz     x0, 99f
    mov     x23, x0
    str     x24, [x23]
    ldr     x15, [sp, #(L + 48)]
    ldr     x0, [x21, #8]
    SCRATCH x1
    mov     x2, x23
    add     x3, sp, #(L + 40)
    FORK_CALL node_state_bytes
    cbnz    x0, 98f
    ADDRESS x0, app_anchor_tmp_name         /* anchor.tmp, cut to 0 */
    mov     x1, #app_anchor_tmp_name_len
    ADDQ    x2, x19, APP_PATH
    bl      app_db_file
    mov     x9, #1
    str     x9, [sp, #(L + 24)]
    ADDQ    x0, x19, APP_PATH
    add     x1, sp, #(L + 24)
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_open
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 90f
    ldr     x9, [x27, #(AppDb_op + 8)]
    str     x9, [sp, #(L + 56)]
    str     xzr, [sp, #(L + 24)]
    add     x0, sp, #(L + 56)
    add     x1, sp, #(L + 24)
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_truncate
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
    add     x10, sp, #L                     /* the state's ByteList, its header and bytes */
    sub     x9, x23, x10
    mov     x11, #24
    stp     x11, x9, [x10]
    str     x24, [x10, #16]
    add     x0, sp, #(L + 56)
    add     x1, sp, #L
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_append
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
    neg     x9, x24                         /* zero bytes to a multiple of 8 */
    and     x9, x9, #7
    cbz     x9, 4f
    str     xzr, [sp, #(L + 32)]
    mov     x10, #24
    mov     x11, #32
    stp     x10, x11, [sp, #L]
    str     x9, [sp, #(L + 16)]
    add     x0, sp, #(L + 56)
    add     x1, sp, #L
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_append
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
4:  ldr     x9, [x22, #8]                   /* the message's ByteList: its header, then its bytes, from 100 of the SignedBeaconBlock */
    ldr     x9, [x9, #16]
    sub     x9, x9, #100
    add     x10, x9, #24
    mov     x11, #24
    stp     x10, x11, [sp, #(L + 64)]
    str     x9, [sp, #(L + 80)]
    mov     x12, #64
    stp     x11, x12, [sp, #L]
    str     x11, [sp, #(L + 16)]
    add     x0, sp, #(L + 56)
    add     x1, sp, #L
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_append
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
    ldr     x9, [x22, #8]
    ldr     x10, [x9, #8]
    add     x10, x9, x10
    add     x10, x10, #100
    add     x11, sp, #L
    sub     x10, x10, x11
    mov     x12, #24
    stp     x12, x10, [x11]
    ldr     x10, [x9, #16]
    sub     x10, x10, #100
    str     x10, [x11, #16]
    add     x0, sp, #(L + 56)
    add     x1, sp, #L
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_append
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
    add     x0, sp, #(L + 56)
    add     x1, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_sync
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 89f
    add     x0, sp, #(L + 56)
    CALL_GLOBAL lantern_shell_close
    ADDRESS x0, app_anchor_name             /* over anchor.ssz, and the directory synced */
    mov     x1, #app_anchor_name_len
    ADDQ    x2, x19, APP_PATH2
    bl      app_db_file
    ADDQ    x0, x19, APP_PATH
    ADDQ    x1, x19, APP_PATH2
    add     x2, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_rename
    ldr     x9, [x27, #AppDb_op]
    cbnz    x9, 90f
    ADDRESS x0, app_anchor_name
    mov     x1, #0
    ADDQ    x2, x19, APP_PATH
    bl      app_db_file
    ADDQ    x0, x19, APP_PATH
    add     x1, x27, #AppDb_op
    CALL_GLOBAL lantern_shell_sync_dir
    ldr     x9, [x20, #32]
    str     x9, [x27, #AppDb_anchor_slot]
    b       98f
89: add     x0, sp, #(L + 56)               /* the file closes */
    CALL_GLOBAL lantern_shell_close
90: ldr     x9, [x27, #AppDb_op]            /* cannot write <path>: error <n> */
    str     x9, [sp, #(L + 24)]
    bl      app_line_start
    ADDRESS x0, app_m_write
    mov     x1, #app_m_write_len
    bl      app_line_text
    bl      app_line_path
    ADDRESS x0, app_m_error
    mov     x1, #app_m_error_len
    bl      app_line_text
    ldr     x0, [sp, #(L + 24)]
    bl      app_line_u64
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
98: cbz     x23, 99f                        /* the bytes' memory goes back */
    str     x23, [sp, #(L + 24)]
    str     x24, [sp, #(L + 40)]
    add     x0, sp, #(L + 24)
    add     x1, sp, #(L + 40)
    CALL_GLOBAL lantern_shell_unmap
99: LEAVE 96
END_FUNCTION app_db_state

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
    cmp     x9, #NODE_ACT_DB_APPEND
    b.ne    11f
    mov     x0, x20                         /* DB_APPEND: the record in its segment file */
    bl      app_db_append
    b       8f
11: cmp     x9, #NODE_ACT_DB_DROP
    b.ne    12f
    mov     x0, x20                         /* DB_DROP: the segment's file goes */
    bl      app_db_drop
    b       8f
12: cmp     x9, #NODE_ACT_DB_STATE
    b.ne    10f
    mov     x0, x20                         /* DB_STATE: anchor.ssz */
    bl      app_db_state
    b       8f
10: cmp     x9, #NODE_ACT_STATE_BYTES
    b.ne    13f
    mov     x0, x20                         /* STATE_BYTES: the state's SSZ bytes */
    bl      app_state_bytes
    b       8f
13: cmp     x9, #NODE_ACT_BYTES_PUT
    b.ne    131f
    add     x0, x20, #24                    /* BYTES_PUT: a copy of the ByteList */
    ldr     x1, [x20, #24]
    bl      app_dup
    cbz     x0, 8f
    mov     x1, x0
    ldr     x0, [x20, #16]
    ldr     x2, [x20, #24]
    bl      app_buf_add
    b       8f
131: cmp    x9, #NODE_ACT_BYTES_NEW
    b.ne    2f
    ldr     x0, [x20, #24]                  /* BYTES_NEW: a ByteList of the size, its bytes zero */
    bl      app_map
    cbz     x0, 8f
    ldr     x9, [x20, #24]
    sub     x10, x9, #24
    mov     x11, #24
    str     x9, [x0]
    stp     x11, x10, [x0, #8]
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
    b.ne    51f
    mov     x0, x20
    bl      app_engine_request
    b       8f
51: cmp     x9, #NODE_ACT_BUILDER
    b.ne    6f
    mov     x0, x20
    bl      app_builder_request
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
    b.ne    71f
    ldr     x0, [x19, #APP_SHELL]           /* P2P_LIST: the shell requests of libp2p */
    add     x1, x20, #16
    ldr     x2, [x19, #APP_SHELL_EVENTS]
    CALL_GLOBAL libp2p_shell_perform
    b       8f
71: cmp     x9, #NODE_ACT_API_SEND
    ccmp    x9, #NODE_ACT_API_CLOSE, #4, ne
    b.ne    8f
    mov     x0, x20                         /* API_SEND, API_CLOSE: to the Beacon API's connection */
    bl      app_api_action
8:  add     x20, x20, x22
    b       1b
9:  bl      app_api_flush                   /* the answers go out now */
    LEAVE 0
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
    SCRATCH x5
    ldr     x6, [x19, #APP_ACTIONS]
    add     x7, x19, #APP_RESULT
    CALL_GLOBAL lantern_node_step
    cbz     x0, 3f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.ne    2f
    add     x22, x22, #1
    cmp     x22, #APP_STEP_TRIES
    b.hs    21f
    ldr     x9, [x19, #(APP_RESULT + NodeStepResult_short)]   /* the buffer short of room grows */
    cmp     x9, #NODE_SHORT_NODE
    b.ne    11f
    mov     x0, #0                          /* the node: the field that is short */
    ldr     x1, [x19, #(APP_RESULT + NodeStepResult_room)]
    bl      app_grow
    cbnz    x0, 21f
    b       1b
11: mov     x23, #APP_ACTIONS               /* actions, or scratch: twice the room */
    cmp     x9, #NODE_SHORT_SCRATCH
    b.ne    12f
    mov     x23, #APP_SCRATCH
12: add     x9, x19, x23
    ldr     x9, [x9, #8]
    lsl     x24, x9, #1
    mov     x0, x23
    bl      app_unmap
    mov     x0, x23
    mov     x1, x24
    bl      app_alloc
    cbz     x0, 21f
    b       1b
21: bl      app_line_start                  /* a node step: no room in buffer <short> */
    ADDRESS x0, app_m_step
    mov     x1, #app_m_step_len
    bl      app_line_text
    ADDRESS x0, app_m_room
    mov     x1, #app_m_room_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_RESULT + NodeStepResult_short)]
    bl      app_line_u64
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
    LEAVE 0
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
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
    b       1b
9:  LEAVE 16
END_FUNCTION app_boot_nodes

/*
 * L2: the network: a secp256k1 key, the libp2p state, the shell context with a TCP listener on
 * --port, and the boot nodes: x0 = 0, or 2 after a line on the standard error. x20 the config,
 * x21 the tries. Locals: L a size or a status, L+8 ShellParams, L+32 an Address, L+64 a ListenResult.
 */
/*
 * L1: a new secp256k1 key at APP_KEY from fresh random bytes, below 2^255 and so below the order
 * of the curve (a zero key tries again, up to 4 times), and the anchor's node_id: keccak256 of
 * its point, x then y, in reverse byte order: x0 = 0, or a status. x21 the tries, x22 APP_KEY.
 * Locals: L the public key (40), L+48 the point (64), L+112 a ByteList of the point (88), L+200
 * the digest (32).
 */
LOCAL_FUNCTION app_key
    ENTER 240
    mov     x21, #0
    add     x22, x19, #APP_KEY
1:  add     x0, x19, #APP_TICK
    CALL_GLOBAL libp2p_shell_clock
    mov     x0, x22
    add     x1, x19, #(APP_TICK + LIBP2P_TICK_ENTROPY)
    mov     x2, #32
    bl      lantern_copy
    ldrb    w9, [x22]
    and     w9, w9, #0x7f
    strb    w9, [x22]
    mov     x0, x22
    add     x1, sp, #L
    CALL_GLOBAL crypto_secp256k1_public_key
    cbz     x0, 2f
    add     x21, x21, #1
    cmp     x21, #4
    b.lo    1b
    LEAVE 240
2:  add     x0, sp, #L
    add     x1, sp, #(L + 48)
    CALL_GLOBAL crypto_secp256k1_decompress
    cbnz    x0, 9f
    mov     x9, #(24 + 64)                  /* keccak256(x || y) */
    mov     x10, #24
    stp     x9, x10, [sp, #(L + 112)]
    mov     x9, #64
    str     x9, [sp, #(L + 128)]
    add     x0, sp, #(L + 136)
    add     x1, sp, #(L + 48)
    mov     x2, #64
    bl      lantern_copy
    add     x0, sp, #(L + 112)
    add     x1, sp, #(L + 200)
    CALL_GLOBAL crypto_keccak256
    cbnz    x0, 9f
    add     x10, sp, #(L + 200)             /* the NodeID: the digest's bytes in reverse order */
    add     x11, x19, #(APP_ANCHOR + NodeAnchor_node_id + 31)
    mov     x9, #32
3:  ldrb    w12, [x10], #1
    strb    w12, [x11], #-1
    subs    x9, x9, #1
    b.ne    3b
    mov     x0, #0
9:  LEAVE 240
END_FUNCTION app_key

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
    add     x0, x20, #16                    /* the key of app_key */
    add     x1, x19, #APP_KEY
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
    cbnz    x0, 96f
    ldr     x9, [x20, #88]                  /* the shell: a slot for each connection, one for the execution engine, and the builder's */
    add     x9, x9, #(1 + APP_BUILDER_SLOTS)
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
    mov     x0, #APP_LOG_ERROR
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
    mov     x0, #APP_LOG_INFO
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
    mov     x0, #APP_LOG_ERROR
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
98: mov     x0, #APP_LOG_ERROR
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

/*
 * L2: with --builder, the builder: its Address, the anchor's builder_host, and NODE_FLAG_BUILDER
 * (app.md): x0 = 0, or 2 after a line on the standard error. x20 the endpoint's bytes, x21 their
 * count, x22 the colon.
 */
LOCAL_FUNCTION app_builder_conf
    ENTER 0
    ldp     x20, x21, [x19, #(APP_OPTIONS + AppOptions_builder)]
    cbz     x21, 8f
    ldr     x9, [x19, #APP_ARGS]
    add     x20, x9, x20
    cmp     x21, #NODE_ENGINE_HOST_MAX      /* the Host of each request */
    b.hi    90f
    str     x21, [x19, #(APP_ANCHOR + NodeAnchor_builder_host_len)]
    add     x0, x19, #(APP_ANCHOR + NodeAnchor_builder_host)
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
    ADDQ    x10, x19, APP_BUILDER
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
2:  ADDQ    x10, x19, APP_BUILDER
    str     w1, [x10, #16]
    ldr     x9, [x19, #APP_FLAGS]
    orr     x9, x9, #NODE_FLAG_BUILDER
    str     x9, [x19, #APP_FLAGS]
8:  mov     x0, #0
    LEAVE 0
90: bl      app_line_start                  /* the endpoint's form */
    ADDRESS x0, app_m_builder
    mov     x1, #app_m_builder_len
    bl      app_line_text
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
    mov     x0, #2
    LEAVE 0
END_FUNCTION app_builder_conf

/* L0: x0 = the Handle of the connection of the builder slot x0 (x1 its fields): the slots after the engine's, at its generation. Uses x9. */
LOCAL_FUNCTION app_builder_handle
    UNWIND_END_PROLOGUE
    ldr     x9, [x19, #APP_P2P_CONFIG]
    ldr     x9, [x9, #88]                   /* max_connections, then the engine's */
    add     x0, x0, x9
    add     x0, x0, #1
    ldr     x9, [x1, #AppBuilder_gen]
    orr     x0, x0, x9, lsl #32
    ret
END_FUNCTION app_builder_handle

/* L1: the NODE_EV_BUILDER of the failure of the call x0 joins the next step's events. Locals: the event. */
LOCAL_FUNCTION app_builder_fail
    FRAME 32
    mov     x9, #24
    mov     x10, #NODE_EV_BUILDER
    stp     x9, x10, [sp, #16]
    orr     x0, x0, #256
    str     x0, [sp, #32]
    add     x0, sp, #16
    mov     x1, #24
    bl      app_event_put
    UNFRAME 32
END_FUNCTION app_builder_fail

/*
 * L1: the NODE_EV_BUILDER of the slot x0 (fields x1) joins the next step's events: the call, with the
 * bytes the builder sent, or with the failure bit when it sent none; the slot is free. Locals: L the
 * event's head.
 */
LOCAL_FUNCTION app_builder_answer
    FRAME 64
    str     x1, [sp, #64]
    ldr     x9, [x1, #AppBuilder_got]
    ldr     x10, [x1, #AppBuilder_call]
    mov     x11, #NODE_EV_BUILDER
    cbnz    x9, 1f
    mov     x0, x10                         /* none: the failure bit */
    bl      app_builder_fail
    b       9f
1:  add     x12, x9, #(48 + 7)              /* size, kind, the call, a ByteList, the bytes */
    and     x12, x12, #~7
    stp     x12, x11, [sp, #16]
    sub     x13, x12, #24
    stp     x10, x13, [sp, #32]
    mov     x13, #24
    stp     x13, x9, [sp, #48]
    add     x0, sp, #16
    mov     x1, #48
    bl      app_event_put
    ldr     x1, [sp, #64]
    ldr     x0, [x1, #AppBuilder_buf]
    ldr     x9, [x1, #AppBuilder_len]
    add     x0, x0, x9
    ldr     x1, [x1, #AppBuilder_got]
    add     x1, x1, #7
    and     x1, x1, #~7
    bl      app_event_put
9:  ldr     x1, [sp, #64]
    str     xzr, [x1, #AppBuilder_state]
    UNFRAME 64
END_FUNCTION app_builder_answer

/*
 * L2: the NODE_ACT_BUILDER x0 (app.md): a free slot takes its request and dials the builder; with
 * none, or no memory, its NODE_EV_BUILDER of failure. x20 the action, x21 the slot, x22 its fields,
 * x23 the request's bytes, x24 their count.
 */
LOCAL_FUNCTION app_builder_request
    ENTER 0
    mov     x20, x0
    add     x9, x20, #24
    ldr     x10, [x9, #8]
    add     x23, x9, x10
    ldr     x24, [x9, #16]
    mov     x21, #0
    ADDQ    x22, x19, APP_BUILDER_SLOT0
1:  cmp     x21, #APP_BUILDER_SLOTS
    b.hs    7f
    ldr     x9, [x22, #AppBuilder_state]
    cbz     x9, 2f
    add     x22, x22, #APP_BUILDER_SLOT
    add     x21, x21, #1
    b       1b
2:  ldr     x9, [x20, #16]                  /* the call */
    str     x9, [x22, #AppBuilder_call]
    stp     xzr, xzr, [x22, #AppBuilder_sent]
    str     xzr, [x22, #AppBuilder_got]
    MOVQ    x9, APP_BUILDER_BUFFER + 8      /* room for the request and the answer */
    add     x9, x9, x24
    ldr     x10, [x22, #(AppBuilder_buf + 8)]
    cmp     x10, x9
    b.hs    3f
    sub     x0, x22, x19
    add     x0, x0, #AppBuilder_buf
    bl      app_unmap
    sub     x0, x22, x19
    add     x0, x0, #AppBuilder_buf
    MOVQ    x1, APP_BUILDER_BUFFER + 8
    add     x1, x1, x24
    bl      app_alloc
    cbz     x0, 8f
3:  ldr     x0, [x22, #AppBuilder_buf]
    mov     x1, x23
    mov     x2, x24
    bl      lantern_copy
    str     x24, [x22, #AppBuilder_len]
    ldr     x9, [x22, #AppBuilder_gen]
    add     x9, x9, #1
    str     x9, [x22, #AppBuilder_gen]
    mov     x9, #1
    str     x9, [x22, #AppBuilder_state]
    ldr     x9, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    str     x9, [x22, #AppBuilder_start]
    ldr     x20, [x19, #APP_ENGINE_ACT]     /* the DIAL */
    add     x20, x20, #24
    mov     x9, #LIBP2P_ACT_DIAL_SIZE
    mov     x10, #LIBP2P_ACTION_DIAL
    stp     x9, x10, [x20]
    mov     x0, x21
    mov     x1, x22
    bl      app_builder_handle
    str     x0, [x20, #LIBP2P_ACT_CONN]
    add     x0, x20, #LIBP2P_ACT_DIAL_ADDR
    ADDQ    x1, x19, APP_BUILDER
    mov     x2, #32
    bl      lantern_copy
    mov     x0, x20
    mov     x1, #LIBP2P_ACT_DIAL_SIZE
    bl      app_engine_perform
    LEAVE 0
7:  ldr     x0, [x20, #16]                  /* no free slot: a failure */
    bl      app_builder_fail
    LEAVE 0
8:  str     xzr, [x22, #AppBuilder_got]
    mov     x0, x21
    mov     x1, x22
    bl      app_builder_answer
    LEAVE 0
END_FUNCTION app_builder_request

/*
 * L2: x0 = 1 when the shell event x0 is of a builder slot's connection, which it then takes:
 * CONNECTED opens it, SENT frees its buffer, RECEIVED keeps the bytes (a full buffer closes it),
 * DIAL_FAILED and CLOSED give the call's NODE_EV_BUILDER; else 0. An event of an older connection
 * of a slot is dropped. x20 the event, x21 its kind, x22 the slot, x23 its fields.
 */
LOCAL_FUNCTION app_builder_event
    ENTER 0
    mov     x20, x0
    ldr     x21, [x20, #8]
    cmp     x21, #LIBP2P_EVENT_CONNECTED
    b.lo    8f
    cmp     x21, #LIBP2P_EVENT_CLOSED
    b.hi    8f
    ldr     x9, [x20, #LIBP2P_EV_CONN]
    mov     w10, w9                         /* its index, past libp2p's and the engine's */
    ldr     x11, [x19, #APP_P2P_CONFIG]
    ldr     x11, [x11, #88]
    add     x11, x11, #1
    subs    x22, x10, x11
    b.lo    8f
    cmp     x22, #APP_BUILDER_SLOTS
    b.hs    8f
    ADDQ    x23, x19, APP_BUILDER_SLOT0
    mov     x12, #APP_BUILDER_SLOT
    madd    x23, x22, x12, x23
    ldr     x12, [x23, #AppBuilder_state]
    cbz     x12, 9f
    ldr     x12, [x23, #AppBuilder_gen]
    cmp     x12, x9, lsr #32
    b.ne    9f
    cmp     x21, #LIBP2P_EVENT_CONNECTED
    b.ne    1f
    mov     x9, #2
    str     x9, [x23, #AppBuilder_state]
    b       9f
1:  cmp     x21, #LIBP2P_EVENT_SENT
    b.ne    2f
    ldr     x9, [x23, #AppBuilder_flight]
    ldr     x10, [x20, #LIBP2P_EV_COUNT]
    subs    x9, x9, x10
    csel    x9, xzr, x9, lo
    str     x9, [x23, #AppBuilder_flight]
    b       9f
2:  cmp     x21, #LIBP2P_EVENT_RECEIVED
    b.ne    3f
    ldr     x9, [x23, #(AppBuilder_buf + 8)]    /* the room after the request and the bytes so far */
    ldp     x10, x11, [x23, #AppBuilder_len]
    ldr     x12, [x23, #AppBuilder_got]
    sub     x9, x9, x10
    sub     x9, x9, x12
    sub     x9, x9, #8
    ldr     x2, [x20, #LIBP2P_EV_COUNT]
    cmp     x2, x9
    b.ls    21f
    mov     x2, x9                          /* full: the rest goes, and the connection closes */
    mov     x9, #3
    str     x9, [x23, #AppBuilder_state]
21: ldr     x0, [x23, #AppBuilder_buf]
    add     x0, x0, x10
    add     x0, x0, x12
    add     x12, x12, x2
    str     x12, [x23, #AppBuilder_got]
    add     x1, x20, #LIBP2P_EV_DATA
    bl      lantern_copy
    b       9f
3:  mov     x0, x22                         /* DIAL_FAILED, CLOSED: the answer */
    mov     x1, x23
    bl      app_builder_answer
9:  mov     x0, #1
    LEAVE 0
8:  mov     x0, #0
    LEAVE 0
END_FUNCTION app_builder_event

/*
 * L2: after the shell's events (app.md): for each slot, a call past APP_BUILDER_MS closes; an open
 * one sends its request's next bytes as the shell's send buffer has room; one to close (state 3)
 * gets its CLOSE, then waits for CLOSED (state 4). x20 the action, x21 the slot, x22 its fields,
 * x23 the bytes.
 */
LOCAL_FUNCTION app_builder_due
    ENTER 0
    mov     x21, #0
    ADDQ    x22, x19, APP_BUILDER_SLOT0
1:  cmp     x21, #APP_BUILDER_SLOTS
    b.hs    9f
    ldr     x9, [x22, #AppBuilder_state]
    cbz     x9, 7f
    cmp     x9, #2
    b.hi    3f
    ldr     x10, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]   /* the time limit */
    ldr     x11, [x22, #AppBuilder_start]
    sub     x10, x10, x11
    MOVQ    x11, APP_BUILDER_MS
    cmp     x10, x11
    b.lo    2f
    mov     x9, #3
    str     x9, [x22, #AppBuilder_state]
    b       3f
2:  cmp     x9, #2
    b.ne    7f
    ldp     x10, x11, [x22, #AppBuilder_len]    /* open: the next bytes, as the send buffer has room */
    sub     x23, x10, x11
    cbz     x23, 7f
    ldr     x12, [x19, #APP_P2P_CONFIG]
    ldr     x12, [x12, #160]                /* send_window */
    ldr     x13, [x22, #AppBuilder_flight]
    subs    x12, x12, x13
    b.ls    7f
    cmp     x23, x12
    csel    x23, x23, x12, ls
    ldr     x20, [x19, #APP_ENGINE_ACT]     /* SEND: connection, count, the bytes */
    add     x20, x20, #24
    add     x9, x23, #(LIBP2P_ACT_SEND_DATA + 7)
    and     x9, x9, #~7
    mov     x10, #LIBP2P_ACTION_SEND
    stp     x9, x10, [x20]
    mov     x0, x21
    mov     x1, x22
    bl      app_builder_handle
    stp     x0, x23, [x20, #LIBP2P_ACT_CONN]
    add     x0, x20, #LIBP2P_ACT_SEND_DATA
    ldr     x1, [x22, #AppBuilder_buf]
    ldr     x9, [x22, #AppBuilder_sent]
    add     x1, x1, x9
    mov     x2, x23
    bl      lantern_copy
    ldp     x9, x10, [x22, #AppBuilder_sent]
    add     x9, x9, x23
    add     x10, x10, x23
    stp     x9, x10, [x22, #AppBuilder_sent]
    mov     x0, x20
    ldr     x1, [x20]
    bl      app_engine_perform
    b       7f
3:  cmp     x9, #3                          /* to close: the CLOSE */
    b.ne    7f
    mov     x9, #4
    str     x9, [x22, #AppBuilder_state]
    ldr     x20, [x19, #APP_ENGINE_ACT]
    add     x20, x20, #24
    mov     x9, #LIBP2P_ACT_CLOSE_SIZE
    mov     x10, #LIBP2P_ACTION_CLOSE
    stp     x9, x10, [x20]
    mov     x0, x21
    mov     x1, x22
    bl      app_builder_handle
    str     x0, [x20, #LIBP2P_ACT_CONN]
    mov     x0, x20
    mov     x1, #LIBP2P_ACT_CLOSE_SIZE
    bl      app_engine_perform
7:  add     x22, x22, #APP_BUILDER_SLOT
    add     x21, x21, #1
    b       1b
9:  LEAVE 0
END_FUNCTION app_builder_due

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
    mov     x0, #APP_LOG_ERROR
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
    mov     x0, #APP_LOG_ERROR
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
    ldr     x0, [x19, #APP_IDENTITY]
    add     x0, x0, #(48 + ApiIdentity_enr)
    mov     x1, #512
    bl      app_line_to
    bl      app_identity_put                /* the node's identity: the new record */
    bl      app_line_start                  /* record enr:<base64url> */
    ADDRESS x0, app_m_record
    mov     x1, #app_m_record_len
    bl      app_line_text
    add     x0, x20, #DISCV5_ACT_RECORD_DATA
    ldr     x1, [x20, #DISCV5_ACT_RECORD_LEN]
    bl      app_line_base64url
    mov     x0, #APP_LOG_INFO
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
    ldr     x9, [x19, #APP_IDENTITY]
    add     x9, x9, #(48 + ApiIdentity_peer_id)
    ldr     x1, [x9], #8
    mov     x0, x9
    bl      app_line_text
    ldr     x0, [sp, #24]
    mov     x1, #128
    bl      app_line_to
    UNFRAME 16
END_FUNCTION app_multiaddr

/*
 * L2: the Beacon API: a shell context with --http-max-connections slots that listens on
 * --http-address and --http-port, the slots' buffers, and the identity's texts: the peer id, the
 * addresses and the version, in a NODE_EV_API_IDENTITY: x0 = 0, or 2 after a line on the standard
 * error. Locals: L ShellParams or an Address, L+32 a ListenResult or the public key, L+80 the peer
 * id's multihash, L+128 base58's work area.
 */
LOCAL_FUNCTION app_api_start
    ENTER 208
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_http_max_connections)]
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
    MOVQ    x1, APP_API_ACT_BYTES
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #24
    stp     x9, xzr, [x0, #8]
    mov     x0, #APP_API_EVENT
    MOVQ    x1, 48 + HTTP_REQUEST_FIXED + APP_API_BUFFER + 64
    bl      app_alloc
    cbz     x0, 97f
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_http_max_connections)]
    MOVQ    x10, APP_API_SLOT_BYTES
    mul     x1, x9, x10
    mov     x0, #APP_API_BUF
    bl      app_alloc
    cbz     x0, 97f
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_http_max_connections)]
    mov     x10, #APP_API_SLOT
    mul     x1, x9, x10
    mov     x0, #APP_API_SLOTS
    bl      app_alloc
    cbz     x0, 97f
    str     xzr, [x0]
    mov     x0, #APP_IDENTITY
    mov     x1, #(48 + API_IDENTITY_SIZE)
    bl      app_alloc
    cbz     x0, 97f
    mov     x9, #4                          /* listen: TCP --http-address, --http-port */
    ldr     x10, [x19, #(APP_OPTIONS + AppOptions_http_port)]
    stp     x9, x10, [sp, #L]
    ldr     x9, [x19, #(APP_OPTIONS + AppOptions_http_address)]
    stp     x9, xzr, [sp, #(L + 16)]
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
    ldr     x2, [x19, #APP_IDENTITY]
    add     x2, x2, #(48 + ApiIdentity_peer_id + 8)
    add     x3, sp, #(L + 128)
    bl      app_base58
    ldr     x9, [x19, #APP_IDENTITY]
    str     x0, [x9, #(48 + ApiIdentity_peer_id)]
    ldr     x0, [x19, #APP_IDENTITY]        /* the version */
    MOVQ    x9, 48 + ApiIdentity_version
    add     x0, x0, x9
    mov     x9, #app_version_text_len
    str     x9, [x0], #8
    ADDRESS x1, app_version_text
    mov     x2, #app_version_text_len
    bl      lantern_copy
    ADDRESS x0, app_t_tcp                   /* the addresses */
    ldr     x1, [x19, #APP_IDENTITY]
    MOVQ    x9, 48 + ApiIdentity_p2p_address
    add     x1, x1, x9
    bl      app_multiaddr
    ADDRESS x0, app_t_udp
    ldr     x1, [x19, #APP_IDENTITY]
    MOVQ    x9, 48 + ApiIdentity_discovery_address
    add     x1, x1, x9
    bl      app_multiaddr
    bl      app_identity_put
    bl      app_line_start                  /* Beacon API on TCP <address>:<port>, peer id <id> */
    ADDRESS x0, app_m_api
    mov     x1, #app_m_api_len
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_http_address)]
    bl      app_line_ip4
    ADDRESS x0, app_t_colon
    mov     x1, #1
    bl      app_line_text
    ldr     x0, [x19, #(APP_OPTIONS + AppOptions_http_port)]
    bl      app_line_u64
    ADDRESS x0, app_m_peer_id
    mov     x1, #app_m_peer_id_len
    bl      app_line_text
    ldr     x9, [x19, #APP_IDENTITY]
    add     x9, x9, #(48 + ApiIdentity_peer_id)
    ldr     x1, [x9], #8
    mov     x0, x9
    bl      app_line_text
    mov     x0, #APP_LOG_INFO
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
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
    mov     x0, #2
    LEAVE 208
97: bl      app_line_start
    ADDRESS x0, app_m_memory
    mov     x1, #app_m_memory_len
    bl      app_line_text
    mov     x0, #APP_LOG_ERROR
    bl      app_line_end
    mov     x0, #2
    LEAVE 208
END_FUNCTION app_api_start

/* L1: the identity's texts go to the next step in a NODE_EV_API_IDENTITY. */
LOCAL_FUNCTION app_identity_put
    FRAME 0
    ldr     x0, [x19, #APP_IDENTITY]
    mov     x9, #(48 + API_IDENTITY_SIZE)
    mov     x10, #NODE_EV_API_IDENTITY
    stp     x9, x10, [x0]
    mov     x9, #(24 + API_IDENTITY_SIZE)
    stp     xzr, x9, [x0, #16]
    mov     x9, #24
    mov     x10, #API_IDENTITY_SIZE
    stp     x9, x10, [x0, #32]
    mov     x1, #(48 + API_IDENTITY_SIZE)
    bl      app_event_put
    UNFRAME 0
END_FUNCTION app_identity_put

/* L0: x0 = the slot of the connection x0, while it is open at that generation, else 0. Uses x9-x11. */
LOCAL_FUNCTION app_api_slot
    UNWIND_END_PROLOGUE
    and     x9, x0, #0xffffffff
    ldr     x10, [x19, #(APP_OPTIONS + AppOptions_http_max_connections)]
    cmp     x9, x10
    b.hs    9f
    ldr     x10, [x19, #APP_API_SLOTS]
    mov     x11, #APP_API_SLOT
    madd    x10, x9, x11, x10
    ldp     x11, x9, [x10]
    cbz     x9, 9f
    cmp     x11, x0, lsr #32
    b.ne    9f
    mov     x0, x10
    ret
9:  mov     x0, #0
    ret
END_FUNCTION app_api_slot

/* L1: the Beacon API's shell actions go out; their results come at the next poll. */
LOCAL_FUNCTION app_api_flush
    FRAME 0
    ldr     x9, [x19, #APP_API_ACT]
    cbz     x9, 9f
    ldr     x10, [x9, #16]
    cbz     x10, 9f
    ldr     x0, [x19, #APP_API_SHELL]
    mov     x1, x9
    ldr     x2, [x19, #APP_API_EVENTS]
    CALL_GLOBAL libp2p_shell_perform
    ldr     x9, [x19, #APP_API_ACT]
    str     xzr, [x9, #16]
9:  UNFRAME 0
END_FUNCTION app_api_flush

/* L1: x0 = room for a shell action of x0 bytes at the end of the Beacon API's actions, its bytes counted, after a flush when they are full; 0 when it never fits. Locals: x0. */
LOCAL_FUNCTION app_api_room
    FRAME 16
    str     x0, [sp, #16]
    ldr     x9, [x19, #APP_API_ACT]
    ldr     x10, [x9]
    sub     x10, x10, #24
    cmp     x0, x10
    b.hi    8f
    ldr     x11, [x9, #16]
    add     x11, x11, x0
    cmp     x11, x10
    b.ls    1f
    bl      app_api_flush
1:  ldr     x9, [x19, #APP_API_ACT]
    ldr     x10, [x9, #16]
    ldr     x11, [sp, #16]
    add     x11, x10, x11
    str     x11, [x9, #16]
    add     x0, x9, #24
    add     x0, x0, x10
    UNFRAME 16
8:  mov     x0, #0
    UNFRAME 16
END_FUNCTION app_api_room

/* L1: a CLOSE of the connection x0, while it is open; its slot waits for the shell's CLOSED. Locals: x0. */
LOCAL_FUNCTION app_api_close
    FRAME 16
    str     x0, [sp, #16]
    bl      app_api_slot
    cbz     x0, 9f
    mov     x9, #APP_API_CLOSING
    str     x9, [x0, #8]
    mov     x0, #LIBP2P_ACT_CLOSE_SIZE
    bl      app_api_room
    cbz     x0, 9f
    mov     x9, #LIBP2P_ACT_CLOSE_SIZE
    mov     x10, #LIBP2P_ACTION_CLOSE
    stp     x9, x10, [x0]
    ldr     x9, [sp, #16]
    str     x9, [x0, #LIBP2P_ACT_CONN]
9:  UNFRAME 16
END_FUNCTION app_api_close

/*
 * L2: the slot x0, when it waits for no answer: lantern_http_request of its bytes, then a
 * NODE_EV_API of the request, or of a fault's status (413 for a full buffer with no whole
 * request); the request's bytes leave the buffer, and the slot waits for the answer. x22 the slot,
 * x23 its ByteList, x24 its bytes, x25 its index, x26 the event, x27 the HttpRequest's room.
 * Locals: L HttpLimits.
 */
LOCAL_FUNCTION app_api_read
    ENTER 16
    mov     x25, x0
    ldr     x22, [x19, #APP_API_SLOTS]
    mov     x9, #APP_API_SLOT
    madd    x22, x25, x9, x22
    ldr     x9, [x22, #8]
    cmp     x9, #APP_API_READING
    b.ne    99f
    ldr     x23, [x19, #APP_API_BUF]
    MOVQ    x9, APP_API_SLOT_BYTES
    madd    x23, x25, x9, x23
    ldr     x24, [x22, #16]
    cbz     x24, 99f
    mov     x10, #24
    stp     x9, x10, [x23]
    str     x24, [x23, #16]
    mov     x9, #APP_API_HEAD_MAX
    MOVQ    x10, APP_API_BODY_MAX
    stp     x9, x10, [sp, #L]
    ldr     x26, [x19, #APP_API_EVENT]
    add     x27, x24, #(HTTP_REQUEST_FIXED + 48 + 7)
    and     x27, x27, #~7
    str     x27, [x26, #48]
    mov     x0, x23
    add     x1, sp, #L
    add     x2, x26, #48
    CALL_GLOBAL lantern_http_request
    cbz     x0, 4f
    cmp     x0, #LANTERN_INVALID_HTTP
    b.eq    3f
    mov     x9, #400                        /* no room: a request too large to read */
    cmp     x0, #LANTERN_HTTP_MORE
    b.ne    2f
    MOVQ    x10, APP_API_BUFFER             /* more to come, unless the buffer is full */
    cmp     x24, x10
    b.lo    99f
    mov     x9, #413
2:  str     x9, [x26, #(48 + HttpRequest_status)]
3:  mov     x27, #HTTP_REQUEST_FIXED        /* a fault: the fixed part, with its status; the bytes go */
    str     x27, [x26, #48]
    str     xzr, [x22, #16]
    b       5f
4:  ldr     x9, [x26, #(48 + HttpRequest_used)]     /* the request's bytes leave the buffer */
    sub     x2, x24, x9
    str     x2, [x22, #16]
    add     x0, x23, #24
    add     x1, x0, x9
    bl      lantern_copy
5:  add     x9, x27, #48                    /* the event: size, kind, connection, a ByteList of the HttpRequest */
    mov     x10, #NODE_EV_API
    stp     x9, x10, [x26]
    ldr     x11, [x22]
    orr     x11, x25, x11, lsl #32
    add     x12, x27, #24
    stp     x11, x12, [x26, #16]
    mov     x10, #24
    stp     x10, x27, [x26, #32]
    mov     x0, x26
    add     x1, x27, #48
    bl      app_event_put
    mov     x9, #APP_API_ANSWERING
    str     x9, [x22, #8]
99: LEAVE 16
END_FUNCTION app_api_read

/*
 * L2: the NODE_ACT_API_SEND or NODE_ACT_API_CLOSE x0 of the node: a SEND of its bytes, or the
 * close, on its connection; after the bytes with last 1, the slot's next request. An action of a
 * connection no longer open goes. x20 the action, x22 the slot, x23 the shell action.
 */
LOCAL_FUNCTION app_api_action
    ENTER 0
    mov     x20, x0
    ldr     x0, [x20, #16]
    bl      app_api_slot
    cbz     x0, 99f
    mov     x22, x0
    ldr     x9, [x22, #8]
    cmp     x9, #APP_API_CLOSING            /* closing or draining: no more actions */
    b.hs    99f
    ldr     x9, [x20, #8]
    cmp     x9, #NODE_ACT_API_CLOSE
    b.ne    1f
    ldr     x9, [x22, #32]                  /* CLOSE: at once with no bytes in flight, else after them */
    cbnz    x9, 2f
    ldr     x0, [x20, #16]
    bl      app_api_close
    b       99f
2:  mov     x9, #APP_API_DRAINING
    ldr     x10, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    str     x9, [x22, #8]
    str     x10, [x22, #24]
    b       99f
1:  ldr     x9, [x20, #48]                  /* SEND: size, kind, connection, count, the bytes */
    add     x0, x9, #(LIBP2P_ACT_SEND_DATA + 7)
    and     x0, x0, #~7
    bl      app_api_room
    cbz     x0, 98f
    mov     x23, x0
    ldr     x9, [x20, #48]
    add     x10, x9, #(LIBP2P_ACT_SEND_DATA + 7)
    and     x10, x10, #~7
    mov     x11, #LIBP2P_ACTION_SEND
    stp     x10, x11, [x23]
    ldr     x10, [x20, #16]
    stp     x10, x9, [x23, #LIBP2P_ACT_CONN]
    add     x0, x23, #LIBP2P_ACT_SEND_DATA
    add     x1, x20, #56
    mov     x2, x9
    bl      lantern_copy
    ldr     x9, [x22, #32]                  /* its bytes are in flight */
    ldr     x10, [x20, #48]
    add     x9, x9, x10
    str     x9, [x22, #32]
    ldr     x9, [x20, #24]                  /* last: the slot reads its next request */
    cbnz    x9, 97f
    mov     x9, #1                          /* else an API_SENT is owed */
    str     x9, [x22, #40]
    mov     x0, x22
    ldr     x1, [x20, #16]
    bl      app_api_due
    b       99f
97:
    mov     x9, #APP_API_READING
    str     x9, [x22, #8]
    ldr     x9, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    str     x9, [x22, #24]
    ldr     x0, [x20, #16]
    and     x0, x0, #0xffffffff
    bl      app_api_read
    b       99f
98: ldr     x0, [x20, #16]                  /* bytes that never fit: the connection closes */
    bl      app_api_close
99: LEAVE 0
END_FUNCTION app_api_action

/* L1: a NODE_EV_API_SENT or NODE_EV_API_CLOSED (x0) of the connection x1 for the next step. Locals: the event. */
LOCAL_FUNCTION app_api_note
    FRAME 32
    mov     x9, #24
    stp     x9, x0, [sp, #16]
    str     x1, [sp, #32]
    add     x0, sp, #16
    mov     x1, #24
    bl      app_event_put
    UNFRAME 32
END_FUNCTION app_api_note

/* L1: the slot x0 of the connection x1, owing an API_SENT: it goes once the slot's bytes in flight are at most APP_API_SEND_WINDOW - NODE_API_CHUNK. */
LOCAL_FUNCTION app_api_due
    FRAME 0
    ldr     x9, [x0, #40]
    cbz     x9, 9f
    ldr     x9, [x0, #32]
    MOVQ    x10, APP_API_SEND_WINDOW - NODE_API_CHUNK
    cmp     x9, x10
    b.hi    9f
    str     xzr, [x0, #40]
    mov     x0, #NODE_EV_API_SENT
    bl      app_api_note
9:  UNFRAME 0
END_FUNCTION app_api_due

/*
 * L2: the NODE_ACT_STATE_BYTES x0: lantern_node_state_bytes of the fork of the state's slot in new
 * memory, kept as the bytes of the new id; with no memory, a ByteList of no bytes. x20 the action,
 * x21 the state's entry, x22 the bytes' size, x23 the memory. Locals: L a ByteList, L+24 the size,
 * L+32 the fork.
 */
LOCAL_FUNCTION app_state_bytes
    ENTER 48
    mov     x20, x0
    ldr     x0, [x20, #16]
    bl      app_buf_find
    cbz     x0, 9f
    mov     x21, x0
    ldr     x9, [x21, #8]
    ldr     x0, [x9, #NODE_STATE_SLOT]
    add     x1, x19, #APP_CONFIG
    bl      app_fork
    str     x0, [sp, #(L + 32)]
    mov     x9, #24                         /* the size first */
    str     x9, [sp, #L]
    str     xzr, [sp, #(L + 24)]
    mov     x15, x0
    ldr     x0, [x21, #8]
    SCRATCH x1
    add     x2, sp, #L
    add     x3, sp, #(L + 24)
    FORK_CALL node_state_bytes
    ldr     x22, [sp, #(L + 24)]
    cmp     x22, #24
    b.ls    8f
    mov     x0, x22
    bl      app_map
    cbz     x0, 8f
    mov     x23, x0
    str     x22, [x23]
    ldr     x15, [sp, #(L + 32)]
    ldr     x0, [x21, #8]
    SCRATCH x1
    mov     x2, x23
    add     x3, sp, #(L + 24)
    FORK_CALL node_state_bytes
    cbz     x0, 7f
    mov     x9, #24                         /* no bytes */
    stp     x9, xzr, [x23, #8]
7:  ldr     x0, [x20, #24]
    mov     x1, x23
    mov     x2, x22
    bl      app_buf_add
    LEAVE 48
8:  mov     x9, #24                         /* no memory: a ByteList of no bytes */
    stp     x9, x9, [sp, #L]
    str     xzr, [sp, #(L + 16)]
    add     x0, sp, #L
    mov     x1, #24
    bl      app_dup
    cbz     x0, 9f
    mov     x1, x0
    ldr     x0, [x20, #24]
    mov     x2, #24
    bl      app_buf_add
9:  LEAVE 48
END_FUNCTION app_state_bytes

/*
 * L2: the Beacon API's sockets, without waiting: ACCEPTED takes a free slot (ADOPT) or a REFUSE,
 * RECEIVED joins its slot's buffer and the slot reads it, SENT ends a slot's draining once its bytes
 * are out, CLOSED frees the slot; a slot that waits for no answer with no bytes for
 * APP_API_IDLE_MS closes, as does a draining one; then the shell actions go out. x20 the
 * next event, x21 the end, x22 a slot, x23 its ByteList or an index, x24 the connection. Locals: L
 * the wait, L+8 an action.
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
    ldr     x22, [x19, #APP_API_SLOTS]      /* ACCEPTED: a free slot, or REFUSE */
    ldr     x23, [x19, #(APP_OPTIONS + AppOptions_http_max_connections)]
    mov     x10, #0
2:  cmp     x10, x23
    b.hs    21f
    ldr     x11, [x22, #8]
    cbz     x11, 22f
    add     x22, x22, #APP_API_SLOT
    add     x10, x10, #1
    b       2b
21: mov     x0, #LIBP2P_ACT_REFUSE_SIZE
    bl      app_api_room
    cbz     x0, 79f
    mov     x9, #LIBP2P_ACT_REFUSE_SIZE
    mov     x11, #LIBP2P_ACTION_REFUSE
    stp     x9, x11, [x0]
    ldr     x9, [x20, #LIBP2P_EV_TOKEN]
    str     x9, [x0, #LIBP2P_ACT_TOKEN]
    b       79f
22: ldr     x11, [x22]                      /* a new generation, reading, no bytes, the time now */
    add     x11, x11, #1
    mov     x12, #APP_API_READING
    stp     x11, x12, [x22]
    ldr     x12, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    stp     xzr, x12, [x22, #16]
    stp     xzr, xzr, [x22, #32]            /* no bytes in flight, no API_SENT owed */
    orr     x24, x10, x11, lsl #32
    mov     x0, #LIBP2P_ACT_ADOPT_SIZE
    bl      app_api_room
    cbz     x0, 79f
    mov     x9, #LIBP2P_ACT_ADOPT_SIZE
    mov     x11, #LIBP2P_ACTION_ADOPT
    stp     x9, x11, [x0]
    ldr     x9, [x20, #LIBP2P_EV_TOKEN]
    stp     x9, x24, [x0, #LIBP2P_ACT_TOKEN]
    b       79f
3:  cmp     x9, #LIBP2P_EVENT_SENT          /* SENT: fewer bytes in flight, and an API_SENT once owed */
    b.ne    31f
    ldr     x24, [x20, #LIBP2P_EV_CONN]
    mov     x0, x24
    bl      app_api_slot
    cbz     x0, 79f
    ldr     x9, [x0, #32]
    ldr     x10, [x20, #LIBP2P_EV_COUNT]
    subs    x9, x9, x10
    csel    x9, xzr, x9, lo
    str     x9, [x0, #32]
    ldr     x10, [x0, #8]
    cmp     x10, #APP_API_DRAINING
    b.ne    32f
    ldr     x10, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]   /* draining: bytes went out; with none left, the close */
    str     x10, [x0, #24]
    cbnz    x9, 79f
    mov     x0, x24
    bl      app_api_close
    b       79f
32: mov     x1, x24
    bl      app_api_due
    b       79f
31: cmp     x9, #LIBP2P_EVENT_RECEIVED
    ccmp    x9, #LIBP2P_EVENT_CLOSED, #4, ne
    b.ne    79f
    ldr     x24, [x20, #LIBP2P_EV_CONN]     /* the slot of the connection, at its generation */
    mov     x0, x24
    bl      app_api_slot
    cbz     x0, 79f
    mov     x22, x0
    ldr     x9, [x20, #8]
    cmp     x9, #LIBP2P_EVENT_CLOSED
    b.ne    4f
    mov     x0, #NODE_EV_API_CLOSED         /* CLOSED: the node's stream ends, and the slot is free */
    mov     x1, x24
    bl      app_api_note
    stp     xzr, xzr, [x22, #8]
    b       79f
4:  ldr     x11, [x22, #8]                  /* RECEIVED, unless closing or draining: the bytes join the buffer */
    cmp     x11, #APP_API_CLOSING
    b.hs    79f
    ldr     x12, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    str     x12, [x22, #24]
    and     x23, x24, #0xffffffff
    ldr     x9, [x22, #16]
    ldr     x2, [x20, #LIBP2P_EV_COUNT]
    add     x10, x9, x2
    MOVQ    x11, APP_API_BUFFER
    cmp     x10, x11
    b.ls    5f
    ldr     x12, [x22, #8]                  /* no room: while reading, what fits (then 413); else the connection closes */
    cmp     x12, #APP_API_READING
    b.ne    6f
    sub     x2, x11, x9
    mov     x10, x11
5:  str     x10, [x22, #16]
    ldr     x0, [x19, #APP_API_BUF]
    MOVQ    x10, APP_API_SLOT_BYTES
    madd    x0, x23, x10, x0
    add     x0, x0, #24
    add     x0, x0, x9
    add     x1, x20, #LIBP2P_EV_DATA
    bl      lantern_copy
    mov     x0, x23
    bl      app_api_read
    b       79f
6:  mov     x0, x24
    bl      app_api_close
79: ldr     x9, [x20]
    add     x20, x20, x9
    b       1b
80: ldr     x9, [x19, #APP_API_EVENTS]      /* the idle connections close */
    str     xzr, [x9, #16]
    ldr     x22, [x19, #APP_API_SLOTS]
    mov     x23, #0
81: ldr     x9, [x19, #(APP_OPTIONS + AppOptions_http_max_connections)]
    cmp     x23, x9
    b.hs    85f
    ldr     x10, [x22, #8]                  /* reading, or draining, with no bytes for APP_API_IDLE_MS */
    cmp     x10, #APP_API_READING
    b.eq    82f
    cmp     x10, #APP_API_DRAINING
    b.ne    84f
82: ldr     x10, [x22, #24]
    MOVQ    x11, APP_API_IDLE_MS
    add     x10, x10, x11
    ldr     x12, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    cmp     x12, x10
    b.lo    84f
    ldr     x9, [x22]
    orr     x0, x23, x9, lsl #32
    bl      app_api_close
84: add     x22, x22, #APP_API_SLOT
    add     x23, x23, #1
    b       81b
85: bl      app_api_flush
    LEAVE 64
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
    mov     x0, x20                         /* a builder call's connection */
    bl      app_builder_event
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
    bl      app_builder_due                 /* the builder calls: their bytes, ends and time limits */
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
    ADDRESS x0, app_m_earliest              /* the first slot the node serves blocks and sidecars from: the backfill's */
    mov     x1, #app_m_earliest_len
    bl      app_line_text
    ldr     x0, [x19, #APP_NODE]
    ldr     x0, [x0, #Node_earliest_slot]
    bl      app_line_u64
    mov     x0, #APP_LOG_INFO
    bl      app_line_end
3:  ldr     x9, [x19, #APP_NODE]            /* a line when the count of connected peers changes */
    ldr     x9, [x9, #(Node_peers + 8)]
    ldr     x10, [x19, #APP_PEERS]
    cmp     x9, x10
    b.eq    4f
    str     x9, [x19, #APP_PEERS]
    bl      app_line_start                  /* peers <n> */
    ADDRESS x0, app_m_peers
    mov     x1, #app_m_peers_len
    bl      app_line_text
    ldr     x0, [x19, #APP_PEERS]
    bl      app_line_u64
    mov     x0, #APP_LOG_INFO
    bl      app_line_end
4:  ldr     x9, [x19, #(APP_RESULT + 8)]    /* the wait: to the node's or discv5's wakeup, at most APP_WAIT_MS */
    ldr     x13, [x19, #APP_DV_WAKE]
    cmp     x13, x9
    csel    x9, x13, x9, lo
    ldr     x10, [x19, #(APP_TICK + LIBP2P_TICK_NOW)]
    subs    x11, x9, x10
    csel    x11, xzr, x11, ls
    mov     x12, #APP_WAIT_MS
    cmp     x11, x12
    csel    x11, x11, x12, lo
    ldr     x9, [x19, #APP_EVENTS]          /* no wait while events wait for the next step */
    ldr     x9, [x9, #16]
    cmp     x9, #0
    csel    x11, xzr, x11, ne
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
    mov     x0, #APP_LOG_ERROR
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
