/*
 * The binary's startup and loop, RISC-V: its own object, which only the binary links (entry.s calls
 * lantern_app_main). Requirements: docs/reference/app.md. The same steps as asm/core/arm64/app.s:
 * s1 holds the App (x19 there); s2 to s8 hold x20 to x26; a0 to a7 hold the arguments x0 to x7.
 * App offsets of 2048 or more go through LDQ, STQ and ADDQ, which use a7. Trailing comments use #.
 */
.set ISA_RISCV64, 1
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

/* The App, at s1; the constants and the RODATA. */
.include "app.inc"

/* reg = the scratch buffer, its size written back into its first 8 bytes: a callee may leave it
 * invalid (ARCHITECTURE.md section 6). Uses t1 and a7. */
.macro SCRATCH reg
    LDQ     \reg, s1, APP_SCRATCH
    LDQ     t1, s1, (APP_SCRATCH + 8)
    sd      t1, 0(\reg)
.endm

/* L0: a0 = the fork of the slot a0 with the config a1: the last fork whose epoch is at most the slot's. Uses t0-t2. */
LOCAL_FUNCTION app_fork
    UNWIND_END_PROLOGUE
    li      t0, SLOTS_PER_EPOCH
    divu    t0, a0, t0
    li      t1, (16 * FORK_FULU)
1:  beqz    t1, 2f
    add     t2, a1, t1
    ld      t2, 0(t2)
    bgeu    t0, t2, 2f
    addi    t1, t1, -16
    j       1b
2:  srli    a0, t1, 4
    ret
END_FUNCTION app_fork

/* L0: a0 = the current slot of the store a0: (time_ms - genesis_time_ms) // SLOT_DURATION_MS, 0 before genesis. Uses t0-t2, a7. */
LOCAL_FUNCTION app_store_slot
    UNWIND_END_PROLOGUE
    LDQ     t0, a0, Store_time_ms
    LDQ     t1, a0, Store_genesis_time_ms
    sub     t2, t0, t1
    bgeu    t0, t1, 1f
    li      t2, 0
1:  LDQ     t1, a0, (Store_config + CONFIG_SLOT_DURATION_MS)
    li      a0, 0
    beqz    t1, 2f
    divu    a0, t2, t1
2:  ret
END_FUNCTION app_store_slot

/* L0: a0 = 1 when the a1 bytes at a0 are the a3 bytes at a2, else 0. Uses t0, t1. */
LOCAL_FUNCTION app_name_is
    UNWIND_END_PROLOGUE
    bne     a1, a3, 2f
1:  beqz    a1, 3f
    lbu     t0, 0(a0)
    lbu     t1, 0(a2)
    bne     t0, t1, 2f
    addi    a0, a0, 1
    addi    a2, a2, 1
    addi    a1, a1, -1
    j       1b
2:  li      a0, 0
    ret
3:  li      a0, 1
    ret
END_FUNCTION app_name_is

/* L1: a0 = memory of a0 bytes from lantern_shell_map, zeroed, or 0. Locals: the size, the address. */
LOCAL_FUNCTION app_map
    FRAME 16
    sd      a0, 0(sp)
    mv      a0, sp
    addi    a1, sp, 8
    CALL_GLOBAL lantern_shell_map
    ld      a0, 8(sp)
    UNFRAME 16
END_FUNCTION app_map

/*
 * L1: a StateCache, a CommitteeCache and a PubkeyCache for a0 / 121 + 65536 validators (a0 the anchor file's
 * bytes), at CONFIG_STATE_CACHE and CONFIG_COMMITTEE_CACHE of the app's config; none with no
 * memory. s1 the app.
 * Locals: sp+0 validators, sp+8 its bytes.
 */
LOCAL_FUNCTION app_state_cache
    FRAME 16
    li      t0, 121
    divu    a0, a0, t0
    li      t0, 65536
    add     a0, a0, t0
    sd      a0, 0(sp)
    mv      a0, sp
    addi    a1, sp, 8
    LDQ     t6, s1, APP_FORK
    FORK_CALL state_cache_size
    ld      a0, 8(sp)
    call    app_map
    beqz    a0, 1f
    ld      t0, 8(sp)
    sd      t0, 0(a0)
    li      t0, APP_CONFIG + CONFIG_STATE_CACHE
    add     t0, s1, t0
    sd      a0, 0(t0)
    mv      a1, a0
    mv      a0, sp
    LDQ     t6, s1, APP_FORK
    FORK_CALL state_cache_init
1:  mv      a0, sp                          # the CommitteeCache, for as many validators
    addi    a1, sp, 8
    LDQ     t6, s1, APP_FORK
    FORK_CALL committee_cache_size
    ld      a0, 8(sp)
    call    app_map
    beqz    a0, 2f
    ld      t0, 8(sp)
    sd      t0, 0(a0)
    li      t0, APP_CONFIG + CONFIG_COMMITTEE_CACHE
    add     t0, s1, t0
    sd      a0, 0(t0)
    mv      a1, a0
    mv      a0, sp
    LDQ     t6, s1, APP_FORK
    FORK_CALL committee_cache_init
2:  mv      a0, sp                          # the PubkeyCache, for as many validators
    addi    a1, sp, 8
    LDQ     t6, s1, APP_FORK
    FORK_CALL pubkey_cache_size
    ld      a0, 8(sp)
    call    app_map
    beqz    a0, 3f
    ld      t0, 8(sp)
    sd      t0, 0(a0)
    li      t0, APP_CONFIG + CONFIG_PUBKEY_CACHE
    add     t0, s1, t0
    sd      a0, 0(t0)
    mv      a1, a0
    mv      a0, sp
    LDQ     t6, s1, APP_FORK
    FORK_CALL pubkey_cache_init
3:  li      a0, LANTERN_OK
    UNFRAME 16
END_FUNCTION app_state_cache

/* L1: the pair at s1 + a0 goes back to lantern_shell_unmap and becomes 0, 0. */
LOCAL_FUNCTION app_unmap
    FRAME 16
    add     t0, s1, a0
    sd      t0, 0(sp)
    ld      t1, 0(t0)
    beqz    t1, 1f
    mv      a0, t0
    addi    a1, t0, 8
    CALL_GLOBAL lantern_shell_unmap
    ld      t0, 0(sp)
    sd      zero, 0(t0)
    sd      zero, 8(t0)
1:  UNFRAME 16
END_FUNCTION app_unmap

/* L1: the pair at s1 + a0 becomes new memory of a1 bytes, its first u64 the size: a0 = the memory, or 0. */
LOCAL_FUNCTION app_alloc
    ENTER 0
    add     s2, s1, a0
    mv      s3, a1
    mv      a0, a1
    call    app_map
    beqz    a0, 1f
    sd      s3, 0(a0)
    sd      a0, 0(s2)
    sd      s3, 8(s2)
1:  LEAVE 0
END_FUNCTION app_alloc

/* L0: the log line starts, with room for the time and the level that app_line_end writes. Uses t0, a7. */
LOCAL_FUNCTION app_line_start
    UNWIND_END_PROLOGUE
    li      t0, APP_LOG_PREFIX
    STQ     t0, s1, (APP_LINE + 16)
    ret
END_FUNCTION app_line_start

/* L0: a2 digits of a0, before the byte at a1. A leaf; uses a0-a2, t0, t1. */
LOCAL_FUNCTION app_digits
    UNWIND_END_PROLOGUE
    li      t0, 10
1:  remu    t1, a0, t0
    divu    a0, a0, t0
    addi    t1, t1, 0x30
    addi    a1, a1, -1
    sb      t1, 0(a1)
    addi    a2, a2, -1
    bnez    a2, 1b
    ret
END_FUNCTION app_digits

/*
 * L1: the UTC time of the Unix milliseconds a0, as YYYY-MM-DD HH:MM:SS.mmm, in the 23 bytes at
 * a1 (civil_from_days of the days since 1970). Locals: sp+0 out, +8 the milliseconds of the day,
 * +16 year, +24 month, +32 day.
 */
LOCAL_FUNCTION app_time_text
    FRAME 48
    sd      a1, 0(sp)
    li      t0, 86400000
    divu    t1, a0, t0                      # days
    remu    t2, a0, t0
    sd      t2, 8(sp)
    li      t0, 719468
    add     t1, t1, t0                      # z
    li      t0, 146097
    divu    t2, t1, t0                      # era
    remu    t3, t1, t0                      # day of the era
    li      t0, 1460
    divu    t4, t3, t0
    sub     t5, t3, t4
    li      t0, 36524
    divu    t4, t3, t0
    add     t5, t5, t4
    li      t0, 146096
    divu    t4, t3, t0
    sub     t5, t5, t4
    li      t0, 365
    divu    t5, t5, t0                      # year of the era
    li      t0, 400
    mul     t6, t2, t0
    add     t6, t6, t5                      # the year, from March
    li      t0, 365
    mul     a2, t5, t0
    srli    a3, t5, 2
    add     a2, a2, a3
    li      t0, 100
    divu    a3, t5, t0
    sub     a2, a2, a3
    sub     a2, t3, a2                      # day of the year, from March 1
    li      t0, 5
    mul     a3, a2, t0
    addi    a3, a3, 2
    li      t0, 153
    divu    a3, a3, t0                      # month, from March
    mul     a4, a3, t0
    addi    a4, a4, 2
    li      t0, 5
    divu    a4, a4, t0
    sub     a4, a2, a4
    addi    a4, a4, 1                       # day
    sd      a4, 32(sp)
    li      t0, 10
    bgeu    a3, t0, 1f
    addi    a3, a3, 3                       # month
    j       2f
1:  addi    a3, a3, -9
2:  sd      a3, 24(sp)
    li      t0, 2
    bgtu    a3, t0, 3f
    addi    t6, t6, 1                       # the year: January and February are of the next
3:  sd      t6, 16(sp)
    ld      a1, 0(sp)                       # the separators
    li      t0, 0x2d
    sb      t0, 4(a1)
    sb      t0, 7(a1)
    li      t0, 0x20
    sb      t0, 10(a1)
    li      t0, 0x3a
    sb      t0, 13(a1)
    sb      t0, 16(a1)
    li      t0, 0x2e
    sb      t0, 19(a1)
    ld      a0, 16(sp)                      # the digits, each field from its end
    addi    a1, a1, 4
    li      a2, 4
    call    app_digits
    ld      a0, 24(sp)
    ld      a1, 0(sp)
    addi    a1, a1, 7
    li      a2, 2
    call    app_digits
    ld      a0, 32(sp)
    ld      a1, 0(sp)
    addi    a1, a1, 10
    li      a2, 2
    call    app_digits
    ld      t2, 8(sp)                       # hours
    li      t0, 3600000
    divu    a0, t2, t0
    remu    t2, t2, t0
    sd      t2, 8(sp)
    ld      a1, 0(sp)
    addi    a1, a1, 13
    li      a2, 2
    call    app_digits
    ld      t2, 8(sp)                       # minutes
    li      t0, 60000
    divu    a0, t2, t0
    remu    t2, t2, t0
    sd      t2, 8(sp)
    ld      a1, 0(sp)
    addi    a1, a1, 16
    li      a2, 2
    call    app_digits
    ld      t2, 8(sp)                       # seconds
    li      t0, 1000
    divu    a0, t2, t0
    remu    t2, t2, t0
    sd      t2, 8(sp)
    ld      a1, 0(sp)
    addi    a1, a1, 19
    li      a2, 2
    call    app_digits
    ld      a0, 8(sp)                       # milliseconds
    ld      a1, 0(sp)
    addi    a1, a1, 23
    li      a2, 3
    call    app_digits
    UNFRAME 48
END_FUNCTION app_time_text

/* L0: the a1 bytes at a0 join the log line, as far as it has room. Uses a0, a1, t0-t3, a7. */
LOCAL_FUNCTION app_line_text
    UNWIND_END_PROLOGUE
    ADDQ    t0, s1, APP_LINE
    ld      t1, 16(t0)
    li      t2, APP_LINE_MAX
    sub     t2, t2, t1
    bleu    a1, t2, 1f
    mv      a1, t2
1:  add     t2, t1, a1
    sd      t2, 16(t0)
    addi    t0, t0, 24
    add     t0, t0, t1
2:  beqz    a1, 3f
    lbu     t3, 0(a0)
    sb      t3, 0(t0)
    addi    a0, a0, 1
    addi    t0, t0, 1
    addi    a1, a1, -1
    j       2b
3:  ret
END_FUNCTION app_line_text

/* L1: the decimal digits of a0 join the log line. Locals: 32 digit bytes. */
LOCAL_FUNCTION app_line_u64
    FRAME 32
    addi    t0, sp, 32                      # the digits, from the end
    li      t1, 10
1:  remu    t2, a0, t1
    divu    a0, a0, t1
    addi    t2, t2, 0x30
    addi    t0, t0, -1
    sb      t2, 0(t0)
    bnez    a0, 1b
    mv      a0, t0
    addi    a1, sp, 32
    sub     a1, a1, t0
    call    app_line_text
    UNFRAME 32
END_FUNCTION app_line_u64

/* L1: the hex digits of the a1 bytes at a0 join the log line. Locals: a0, a1, then 2 digits. */
LOCAL_FUNCTION app_line_hex
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
1:  ld      a0, 0(sp)
    ld      a1, 8(sp)
    beqz    a1, 2f
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, -1
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    ADDRESS t1, app_hex_digits
    srli    t2, t0, 4
    add     t2, t1, t2
    lbu     t2, 0(t2)
    sb      t2, 16(sp)
    andi    t2, t0, 15
    add     t2, t1, t2
    lbu     t2, 0(t2)
    sb      t2, 17(sp)
    addi    a0, sp, 16
    li      a1, 2
    call    app_line_text
    j       1b
2:  UNFRAME 32
END_FUNCTION app_line_hex

/*
 * L1: the log line of kind a0 (APP_LOG_INFO, ERROR, WARN or DEBUG), when its level is at most the
 * log level: its time and level before it, an LF after it, to the standard error for ERROR and
 * WARN, else the standard output. Locals: sp+0 the level, +8 the time, +16 an LF.
 */
LOCAL_FUNCTION app_line_end
    FRAME 32
    ADDRESS t0, app_log_rank
    add     t0, t0, a0
    lbu     t0, 0(t0)
    LDQ     t1, s1, (APP_OPTIONS + AppOptions_log_level)
    bgtu    t0, t1, 9f
    li      t2, 2
    li      t1, 1
    bleu    t0, t1, 1f
    li      t2, 1
1:  STQ     t2, s1, APP_STREAM
    sd      t0, 0(sp)
    addi    a0, sp, 8
    CALL_GLOBAL lantern_shell_time_ms
    ld      a0, 8(sp)
    ADDQ    a1, s1, (APP_LINE + 24)
    call    app_time_text
    ADDQ    a1, s1, (APP_LINE + 24)
    li      t0, 0x20
    sb      t0, 23(a1)
    sb      t0, 29(a1)
    ld      t0, 0(sp)
    ADDRESS t1, app_log_names
    slli    t0, t0, 3
    add     t1, t1, t0
    li      t2, 0
2:  add     t3, t1, t2                      # the level's 5 bytes
    lbu     t3, 0(t3)
    add     t4, a1, t2
    sb      t3, 24(t4)
    addi    t2, t2, 1
    li      t3, 5
    bltu    t2, t3, 2b
    li      t0, 10
    sb      t0, 16(sp)
    addi    a0, sp, 16
    li      a1, 1
    call    app_line_text
    ADDQ    a0, s1, APP_STREAM
    ADDQ    a1, s1, APP_LINE
    CALL_GLOBAL lantern_shell_write
9:  UNFRAME 32
END_FUNCTION app_line_end

/*
 * L1: the log lines of a work that ran (app.md, the log): DEBUG work <kind> result <n>; for a
 * block's import, INFO block <slot> imported, <a> attestations, or WARN block <slot> not imported:
 * result <n>. a0 its kind, a1 its data entry or 0. Locals: sp+0 kind, +8 entry, +16 result,
 * +24 slot.
 */
LOCAL_FUNCTION app_log_work
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    LDQ     t0, s1, APP_WORK_EVENT
    ld      t0, NodeEvent_result(t0)
    sd      t0, 16(sp)
    call    app_line_start
    ADDRESS a0, app_m_log_work
    li      a1, app_m_log_work_len
    call    app_line_text
    ld      a0, 0(sp)
    call    app_line_u64
    ADDRESS a0, app_m_log_result
    li      a1, app_m_log_result_len
    call    app_line_text
    ld      a0, 16(sp)
    call    app_line_u64
    li      a0, APP_LOG_DEBUG
    call    app_line_end
    ld      t0, 0(sp)
    li      t1, NODE_WORK_IMPORT_BLOCK
    bne     t0, t1, 9f
    ld      t0, 16(sp)
    li      t1, LANTERN_NEED_JUSTIFIED_STATE
    beq     t0, t1, 9f
    ld      t0, 8(sp)
    beqz    t0, 9f
    ld      t0, 8(t0)                       # the block's bytes: its slot at byte 100
    ld      t1, 16(t0)
    li      t2, 108
    bltu    t1, t2, 9f
    ld      t1, 8(t0)
    add     t0, t0, t1
    addi    t0, t0, 100
    li      t1, 0                           # its 8 bytes, little endian, at any alignment
    li      t2, 7
4:  add     t3, t0, t2
    lbu     t3, 0(t3)
    slli    t1, t1, 8
    or      t1, t1, t3
    addi    t2, t2, -1
    bgez    t2, 4b
    sd      t1, 24(sp)
    call    app_line_start
    ADDRESS a0, app_m_log_block
    li      a1, app_m_log_block_len
    call    app_line_text
    ld      a0, 24(sp)
    call    app_line_u64
    ld      t0, 16(sp)
    bnez    t0, 1f
    ADDRESS a0, app_m_log_imported
    li      a1, app_m_log_imported_len
    call    app_line_text
    LDQ     t0, s1, APP_WORK_EVENT
    ld      a0, NodeEvent_index(t0)
    call    app_line_u64
    ADDRESS a0, app_m_log_attestations
    li      a1, app_m_log_attestations_len
    call    app_line_text
    li      a0, APP_LOG_INFO
    call    app_line_end
    j       9f
1:  ADDRESS a0, app_m_log_not
    li      a1, app_m_log_not_len
    call    app_line_text
    ld      a0, 16(sp)
    call    app_line_u64
    li      a0, APP_LOG_WARN
    call    app_line_end
9:  UNFRAME 32
END_FUNCTION app_log_work

/* L1: the path of the a1 bytes of the name at a0 in the network directory: a ByteList at APP_PATH. s6 the ByteList. */
LOCAL_FUNCTION app_path
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    LDQ     s4, s1, (APP_OPTIONS + AppOptions_network_dir)
    LDQ     s5, s1, (APP_OPTIONS + AppOptions_network_dir + 8)
    add     t0, s5, s3                      # the directory, /, the name: too long reads as too long
    addi    t0, t0, 1
    ADDQ    s6, s1, APP_PATH
    li      t1, APP_PATH_MAX
    bgtu    t0, t1, 1f
    sd      t0, 16(s6)
    ld      t1, APP_ARGS(s1)
    add     a1, t1, s4
    addi    a0, s6, 24
    mv      a2, s5
    call    lantern_copy
    addi    a0, s6, 24
    add     a0, a0, s5
    li      t0, 0x2f                        # /
    sb      t0, 0(a0)
    addi    a0, a0, 1
    mv      a1, s2
    mv      a2, s3
    call    lantern_copy
    LEAVE 0
1:  li      t0, (APP_PATH_MAX + 1)          # a count past the room: the shell gives its error
    sd      t0, 16(s6)
    LEAVE 0
END_FUNCTION app_path

/* L1: the path of the log line: the bytes of APP_PATH, as far as they fit. */
LOCAL_FUNCTION app_line_path
    FRAME 0
    ADDQ    t0, s1, APP_PATH
    addi    a0, t0, 24
    ld      a1, 16(t0)
    li      t1, APP_PATH_MAX
    bleu    a1, t1, 1f
    mv      a1, t1
1:  call    app_line_text
    UNFRAME 0
END_FUNCTION app_line_path

/* L1: the file at APP_PATH, read into APP_FILE: a0 = 0, or 2 after a line on the standard error. */
LOCAL_FUNCTION app_read
    FRAME 0
    ADDQ    a0, s1, APP_PATH
    ADDQ    a1, s1, APP_FILE
    CALL_GLOBAL lantern_shell_read_file
    LDQ     t0, s1, APP_FILE
    beqz    t0, 1f
    call    app_line_start                  # cannot read <path>: error <n>
    ADDRESS a0, app_m_read
    li      a1, app_m_read_len
    call    app_line_text
    call    app_line_path
    ADDRESS a0, app_m_error
    li      a1, app_m_error_len
    call    app_line_text
    LDQ     a0, s1, APP_FILE
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
    li      a0, 2
    UNFRAME 0
1:  li      a0, 0
    UNFRAME 0
END_FUNCTION app_read

/*
 * L1: APP_PATH holds the path of the Arg at a0, or a count past its room when the path does not
 * fit, so the shell gives its error.
 */
LOCAL_FUNCTION app_arg_path
    FRAME 0
    ld      a1, 0(a0)
    ld      a2, 8(a0)
    li      t0, APP_PATH_MAX
    bgtu    a2, t0, 1f
    STQ     a2, s1, (APP_PATH + 16)
    ADDQ    a0, s1, (APP_PATH + 24)
    LDQ     t0, s1, APP_ARGS
    add     a1, t0, a1
    call    lantern_copy
    UNFRAME 0
1:  li      t0, (APP_PATH_MAX + 1)
    STQ     t0, s1, (APP_PATH + 16)
    UNFRAME 0
END_FUNCTION app_arg_path

/*
 * L2: the anchor of --checkpoint-state and --checkpoint-block in APP_FILE, in the form of
 * anchor.ssz: one ByteList of two, the state's bytes, then the block's message from byte 100 of
 * its SignedBeaconBlock: a0 = 0, or 2 after a line on the standard error. s2 the block file's
 * ByteList, s4 its bytes, s5 the state file's ByteList, s6 its bytes, s7 the buffer's size, s8 the
 * buffer. Locals: L the block file's address and mapped size.
 */
LOCAL_FUNCTION app_checkpoint
    ENTER 16
    ADDQ    a0, s1, (APP_OPTIONS + AppOptions_checkpoint_block)
    call    app_arg_path
    call    app_read
    bnez    a0, 99f
    LDQ     s2, s1, (APP_FILE + 8)
    LDQ     s4, s1, (APP_FILE + 16)
    li      t0, (100 + 84)                  # the offset and signature, then the message's fixed part
    bltu    s4, t0, 90f
    LDQ     t0, s1, (APP_FILE + 24)
    sd      s2, L(sp)
    sd      t0, (L + 8)(sp)
    STQ     zero, s1, (APP_FILE + 8)
    ADDQ    a0, s1, (APP_OPTIONS + AppOptions_checkpoint_state)
    call    app_arg_path
    call    app_read
    bnez    a0, 98f
    LDQ     s5, s1, (APP_FILE + 8)
    LDQ     s6, s1, (APP_FILE + 16)
    addi    t0, s6, 7                       # three ByteList headers, the state to a multiple of 8, the message
    andi    t0, t0, -8
    addi    t0, t0, 72
    add     t0, t0, s4
    addi    s7, t0, -100
    mv      a0, s7
    call    app_map
    beqz    a0, 97f
    mv      s8, a0
    li      t1, 24                          # the ByteList of both
    sd      s7, 0(s8)
    sd      t1, 8(s8)
    addi    t0, s7, -24
    sd      t0, 16(s8)
    addi    t0, s6, 24                      # the state's
    sd      t0, 24(s8)
    sd      t1, 32(s8)
    sd      s6, 40(s8)
    addi    a0, s8, 48
    addi    a1, s5, 24
    mv      a2, s6
    call    lantern_copy
    addi    t0, s6, 7                       # the message's, at the first multiple of 8 after the state
    andi    t0, t0, -8
    addi    t0, t0, 48
    add     t2, s8, t0
    addi    t3, s4, -100
    addi    t0, t3, 24
    sd      t0, 0(t2)
    li      t1, 24
    sd      t1, 8(t2)
    sd      t3, 16(t2)
    addi    a0, t2, 24
    addi    a1, s2, (24 + 100)
    mv      a2, t3
    call    lantern_copy
    call    app_file_free                   # the files go; the buffer takes their place
    addi    a0, sp, L
    addi    a1, sp, (L + 8)
    CALL_GLOBAL lantern_shell_unmap
    STQ     zero, s1, APP_FILE
    STQ     s8, s1, (APP_FILE + 8)
    addi    t0, s7, -24
    STQ     t0, s1, (APP_FILE + 16)
    STQ     s7, s1, (APP_FILE + 24)
    li      a0, 0
    LEAVE 16
90: call    app_file_free                   # <path>: too short
    call    app_line_start
    call    app_line_path
    ADDRESS a0, app_m_short
    li      a1, app_m_short_len
    call    app_line_text
    li      a0, APP_LOG_ERROR
    call    app_line_end
    j       99f
97: call    app_file_free                   # no memory
    call    app_line_start
    ADDRESS a0, app_m_memory
    li      a1, app_m_memory_len
    call    app_line_text
    li      a0, APP_LOG_ERROR
    call    app_line_end
98: addi    a0, sp, L                       # the block file goes
    addi    a1, sp, (L + 8)
    CALL_GLOBAL lantern_shell_unmap
99: li      a0, 2
    LEAVE 16
END_FUNCTION app_checkpoint

/* L1: the memory of APP_FILE goes back. */
LOCAL_FUNCTION app_file_free
    FRAME 16
    LDQ     t0, s1, (APP_FILE + 8)
    beqz    t0, 1f
    ADDQ    a0, s1, (APP_FILE + 8)
    ADDQ    a1, s1, (APP_FILE + 24)
    CALL_GLOBAL lantern_shell_unmap
    STQ     zero, s1, (APP_FILE + 8)
1:  UNFRAME 16
END_FUNCTION app_file_free

/* L1: a line "<a1 bytes at a0>: status <a2>" on the standard error, then a0 = 2. Locals: a0-a2. */
LOCAL_FUNCTION app_fail_status
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    call    app_line_start
    ld      a0, 0(sp)
    ld      a1, 8(sp)
    call    app_line_text
    ADDRESS a0, app_m_status
    li      a1, app_m_status_len
    call    app_line_text
    ld      a0, 16(sp)
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
    li      a0, 2
    UNFRAME 32
END_FUNCTION app_fail_status

/* L1: a0 = 2 after a line "lantern: no memory" on the standard error. */
LOCAL_FUNCTION app_no_memory
    FRAME 0
    call    app_line_start
    ADDRESS a0, app_m_memory
    li      a1, app_m_memory_len
    call    app_line_text
    li      a0, APP_LOG_ERROR
    call    app_line_end
    li      a0, 2
    UNFRAME 0
END_FUNCTION app_no_memory

/*
 * L2: the start of docs/reference/app.md: the config, the anchor of genesis.ssz, the store, the
 * node and the Seen: a0 = 0, or 2 after a line on the standard error. s2 a ByteList, s3 the
 * file's size, s4 a size, s5 a size, s6 the tries. Locals: L a line number or a size.
 */
LOCAL_FUNCTION app_start
    ENTER 16
    ADDRESS a0, app_builtin_config          # the config: the pinned config of the preset, then the network's
    ADDQ    a1, s1, APP_CONFIG
    addi    a2, sp, L
    CALL_GLOBAL lantern_config_parse
    ADDRESS a0, app_config_name
    li      a1, app_config_name_len
    call    app_path
    call    app_read
    bnez    a0, 99f
    LDQ     a0, s1, (APP_FILE + 8)
    ADDQ    a1, s1, APP_CONFIG
    addi    a2, sp, L
    CALL_GLOBAL lantern_config_parse
    mv      s2, a0
    call    app_file_free
    beqz    s2, 1f
    call    app_line_start                  # <path>: faulty line <n>
    call    app_line_path
    ADDRESS a0, app_m_line
    li      a1, app_m_line_len
    call    app_line_text
    ld      a0, L(sp)
    call    app_line_u64
    j       98f
1:  li      s7, 0                           # with a data directory: its anchor.ssz, when there is one
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_data_dir + 8)
    beqz    t0, 11f
    ADDRESS a0, app_anchor_name
    li      a1, app_anchor_name_len
    ADDQ    a2, s1, APP_PATH
    call    app_db_file
    ADDQ    a0, s1, APP_PATH
    ADDQ    a1, s1, APP_FILE
    CALL_GLOBAL lantern_shell_read_file
    LDQ     t0, s1, APP_FILE
    bnez    t0, 11f
    li      s7, 1
    j       12f
11: LDQ     t0, s1, (APP_OPTIONS + AppOptions_checkpoint_state + 8)  # else the checkpoint files
    beqz    t0, 111f
    call    app_checkpoint
    bnez    a0, 99f
    li      s7, 2
    j       12f
111: ADDRESS a0, app_genesis_name           # else genesis.ssz: the fork of its slot
    li      a1, app_genesis_name_len
    call    app_path
    call    app_read
    bnez    a0, 99f
12:
    LDQ     s2, s1, (APP_FILE + 8)
    LDQ     s3, s1, (APP_FILE + 16)
    li      t0, (40 + 8)
    bgeu    s3, t0, 2f
    call    app_line_start
    call    app_line_path
    ADDRESS a0, app_m_short
    li      a1, app_m_short_len
    call    app_line_text
    j       98f
2:  snez    t0, s7                          # BeaconState.slot, after the ByteList header of anchor.ssz's state
    li      t1, 24
    mul     t0, t0, t1
    add     t0, s2, t0
    ld      a0, (24 + 40)(t0)
    ADDQ    a1, s1, APP_CONFIG
    call    app_fork
    STQ     a0, s1, APP_FORK
    ADDQ    a0, s1, APP_STATE_ROOM
    ADDRESS a1, app_state_room
    li      a2, 64
    call    lantern_copy
    slli    s4, s3, 1                       # the state: 3 times the file and 16 MiB; scratch: 2 times and 64 MiB
    add     s4, s4, s3
    li      t0, (1 << 24)
    add     s4, s4, t0
    slli    s5, s3, 1
    li      t0, (1 << 26)
    add     s5, s5, t0
    li      s6, 0
    li      s8, APP_BLOCK_BYTES             # the block: of genesis, or of anchor.ssz
    beqz    s7, 3f
    li      t0, (1 << 20)
    add     s8, s3, t0
3:  li      a0, APP_STATE
    mv      a1, s4
    call    app_alloc
    beqz    a0, 97f
    li      a0, APP_SCRATCH
    mv      a1, s5
    call    app_alloc
    beqz    a0, 97f
    li      a0, APP_BLOCK
    mv      a1, s8
    call    app_alloc
    beqz    a0, 97f
    mv      a0, s2
    ADDQ    a1, s1, APP_STATE_ROOM
    SCRATCH a2
    LDQ     a3, s1, APP_STATE
    LDQ     a4, s1, APP_BLOCK
    LDQ     t6, s1, APP_FORK
    bnez    s7, 31f
    FORK_CALL node_anchor
    j       32f
31: FORK_CALL node_anchor_block
32: beqz    a0, 4f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    bne     a0, t0, 96f
    li      a0, APP_STATE                   # more room, a few times
    call    app_unmap
    li      a0, APP_SCRATCH
    call    app_unmap
    li      a0, APP_BLOCK
    call    app_unmap
    slli    s4, s4, 1
    slli    s5, s5, 1
    slli    s8, s8, 1
    addi    s6, s6, 1
    li      t0, APP_TRIES
    bltu    s6, t0, 3b
    li      a0, LANTERN_BUFFER_TOO_SMALL
96: mv      a2, a0                          # genesis.ssz or anchor.ssz: status <n>
    ADDRESS a0, app_genesis_name
    li      a1, app_genesis_name_len
    beqz    s7, 961f
    ADDRESS a0, app_anchor_name
    li      a1, app_anchor_name_len
    li      t0, 1
    beq     s7, t0, 961f
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_checkpoint_state)
    LDQ     t0, s1, APP_ARGS
    add     a0, t0, a0
    LDQ     a1, s1, (APP_OPTIONS + AppOptions_checkpoint_state + 8)
961:
    call    app_fail_status
    j       99f
4:  call    app_file_free
    mv      a0, s3
    call    app_state_cache
    li      t0, 121                         # the store: nodes, and validators below the file's bytes / 121
    divu    t1, s3, t0
    li      t0, 4096
    add     t1, t1, t0
    STQ     t0, s1, APP_STORE_ROOM
    STQ     t1, s1, (APP_STORE_ROOM + 8)
    li      s6, 0
5:  ADDQ    a0, s1, APP_STORE_ROOM
    addi    a1, sp, L
    CALL_GLOBAL lantern_store_size
    li      a0, APP_STORE
    ld      a1, L(sp)
    call    app_alloc
    beqz    a0, 97f
    LDQ     a0, s1, APP_STATE
    LDQ     a1, s1, APP_BLOCK
    ADDQ    a2, s1, APP_CONFIG
    ADDQ    a3, s1, APP_STORE_ROOM
    SCRATCH a4
    LDQ     a5, s1, APP_STORE
    LDQ     t6, s1, APP_FORK
    FORK_CALL get_forkchoice_store
    beqz    a0, 6f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    bne     a0, t0, 95f
    li      a0, APP_STORE
    call    app_unmap
    LDQ     t0, s1, APP_STORE_ROOM
    LDQ     t1, s1, (APP_STORE_ROOM + 8)
    slli    t0, t0, 1
    slli    t1, t1, 1
    STQ     t0, s1, APP_STORE_ROOM
    STQ     t1, s1, (APP_STORE_ROOM + 8)
    addi    s6, s6, 1
    li      t0, APP_TRIES
    bltu    s6, t0, 5b
    li      a0, LANTERN_BUFFER_TOO_SMALL
95: mv      a2, a0                          # the store: status <n>
    ADDRESS a0, app_m_store
    li      a1, app_m_store_len
    call    app_fail_status
    j       99f
6:  LDQ     t0, s1, APP_STORE               # the node's anchor: the store's node 0, the state's root
    LDQ     t1, t0, Store_blocks
    add     a1, t0, t1
    ADDQ    a0, s1, APP_ANCHOR
    li      a2, 32
    call    lantern_copy
    LDQ     t0, s1, APP_STORE
    LDQ     t1, t0, Store_blocks
    add     t1, t0, t1
    LDQ     t2, t1, BlockNode_slot
    STQ     t2, s1, (APP_ANCHOR + 32)
    STQ     t2, s1, (APP_ANCHOR + NodeAnchor_history_slot)  # anchor.ssz's history lowers it
    ADDQ    a0, s1, (APP_ANCHOR + 40)
    LDQ     a1, s1, APP_STATE
    ADDQ    a1, a1, NODE_STATE_GVR
    li      a2, 32
    call    lantern_copy
    LDQ     t0, s1, APP_FLAGS               # the shell runs discv5 for the node
    ori     t0, t0, NODE_FLAG_DISCV5
    LDQ     t1, s1, (APP_OPTIONS + AppOptions_supernode)   # --supernode: every custody group
    beqz    t1, 1f
    ori     t0, t0, NODE_FLAG_SUPERNODE
1:  STQ     t0, s1, APP_FLAGS
    call    app_engine_conf                 # the execution engine
    bnez    a0, 99f
    call    app_builder_conf                # the builder
    bnez    a0, 99f
    call    app_key                         # the key, and the anchor's node ID
    bnez    a0, 94f
    ADDQ    a0, s1, APP_NODE_ROOM           # the node
    ADDRESS a1, app_node_room
    li      a2, 8 * NODE_ROOM_FIELDS
    call    lantern_copy
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_target_peers)
    STQ     t0, s1, (APP_NODE_ROOM + NodeRoom_peers)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_http_max_connections)
    STQ     t0, s1, (APP_NODE_ROOM + NodeRoom_api_streams)
    call    app_db_start                    # the history's files
    li      t0, 1
    bne     s7, t0, 13f
    call    app_db_history                  # from anchor.ssz: the segments there
13:
    ADDQ    a0, s1, APP_NODE_ROOM
    addi    a1, sp, L
    CALL_GLOBAL lantern_node_size
    bnez    a0, 94f
    li      a0, APP_NODE
    ld      a1, L(sp)
    call    app_alloc
    beqz    a0, 97f
    ADDQ    a0, s1, APP_NODE_ROOM
    ADDQ    a1, s1, APP_CONFIG
    ADDQ    a2, s1, APP_ANCHOR
    ADDQ    a3, s1, APP_FLAGS
    LDQ     a4, s1, APP_NODE
    CALL_GLOBAL lantern_node_init
    bnez    a0, 94f
    beqz    s7, 14f
    li      t0, 1
    beq     s7, t0, 141f
    call    app_line_start                  # checkpoint at slot <n>
    ADDRESS a0, app_m_checkpoint
    li      a1, app_m_checkpoint_len
    call    app_line_text
    LDQ     a0, s1, (APP_ANCHOR + 32)
    call    app_line_u64
    li      a0, APP_LOG_INFO
    call    app_line_end
    j       14f
141: call   app_db_scan_all                 # from anchor.ssz: the history's segments to the node
    bnez    a0, 99f
    call    app_line_start                  # restart at slot <n>
    ADDRESS a0, app_m_restart
    li      a1, app_m_restart_len
    call    app_line_text
    LDQ     a0, s1, (APP_ANCHOR + 32)
    call    app_line_u64
    li      a0, APP_LOG_INFO
    call    app_line_end
14:
    ADDQ    a0, s1, APP_SEEN_ROOM           # the Seen
    ADDRESS a1, app_seen_room
    li      a2, 32
    call    lantern_copy
    ADDQ    a0, s1, APP_SEEN_ROOM
    addi    a1, sp, L
    CALL_GLOBAL lantern_seen_size
    li      a0, APP_SEEN
    ld      a1, L(sp)
    call    app_alloc
    beqz    a0, 97f
    ADDQ    a0, s1, APP_SEEN_ROOM
    LDQ     a1, s1, APP_SEEN
    CALL_GLOBAL lantern_seen_init
    bnez    a0, 94f
    li      a0, APP_KZG                     # the KZG trusted setup
    li      a1, CRYPTO_KZG_SETTINGS_SIZE
    call    app_alloc
    beqz    a0, 97f
    ADDRESS a0, app_kzg_g1_lagrange
    ADDRESS a1, app_kzg_g1_monomial
    ADDRESS a2, app_kzg_g2_monomial
    LDQ     a3, s1, APP_KZG
    CALL_GLOBAL crypto_kzg_trusted_setup_of_bytes
    bnez    a0, 93f
    li      a0, (APP_BUF_ENTRY * APP_BUFS_CAP)  # BufferId 1: the anchor state
    call    app_map
    beqz    a0, 97f
    STQ     a0, s1, APP_BUFS
    li      t0, 1
    sd      t0, 0(a0)
    LDQ     t1, s1, APP_STATE
    sd      t1, 8(a0)
    LDQ     t1, s1, (APP_STATE + 8)
    sd      t1, 16(a0)
    STQ     t0, s1, (APP_BUFS + 8)
    li      t1, APP_BUFS_CAP
    STQ     t1, s1, (APP_BUFS + 16)
    call    app_lc_start                    # BufferId 2: the light client store
    bnez    a0, 97f
    li      a0, APP_ACTIONS                 # the queues of a step
    li      a1, APP_QUEUE_BYTES
    call    app_alloc
    beqz    a0, 97f
    li      a0, APP_EVENTS
    li      a1, APP_QUEUE_BYTES
    call    app_alloc
    beqz    a0, 97f
    li      t0, 24
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    li      a0, APP_WORK_EVENT
    li      a1, APP_QUEUE_BYTES
    call    app_alloc
    beqz    a0, 97f
    call    app_line_start                  # started at slot <s>, fork <f>, head 0x<root>
    ADDRESS a0, app_m_started
    li      a1, app_m_started_len
    call    app_line_text
    LDQ     a0, s1, (APP_ANCHOR + 32)
    call    app_line_u64
    ADDRESS a0, app_m_fork
    li      a1, app_m_fork_len
    call    app_line_text
    LDQ     a0, s1, APP_FORK
    call    app_line_u64
    ADDRESS a0, app_m_head
    li      a1, app_m_head_len
    call    app_line_text
    ADDQ    a0, s1, APP_ANCHOR
    li      a1, 32
    call    app_line_hex
    li      a0, APP_LOG_INFO
    call    app_line_end
    li      a0, 0
    LEAVE 16
93: mv      a2, a0                          # the KZG trusted setup: status <n>
    ADDRESS a0, app_m_kzg
    li      a1, app_m_kzg_len
    call    app_fail_status
    j       99f
94: mv      a2, a0                          # the node: status <n>
    ADDRESS a0, app_m_node
    li      a1, app_m_node_len
    call    app_fail_status
    j       99f
97: call    app_no_memory
    j       99f
98: li      a0, APP_LOG_ERROR
    call    app_line_end
99: li      a0, 2
    LEAVE 16
END_FUNCTION app_start

/* L0: a0 = the BufferId table entry of the id a0, or 0. Uses t0-t2, a7. */
LOCAL_FUNCTION app_buf_find
    UNWIND_END_PROLOGUE
    LDQ     t0, s1, APP_BUFS
    LDQ     t1, s1, (APP_BUFS + 8)
1:  beqz    t1, 2f
    ld      t2, 0(t0)
    beq     t2, a0, 3f
    addi    t0, t0, APP_BUF_ENTRY
    addi    t1, t1, -1
    j       1b
2:  li      a0, 0
    ret
3:  mv      a0, t0
    ret
END_FUNCTION app_buf_find

/* L1: a table entry of the id a0 for the memory a1 of a2 bytes: a0 = 0, or 1 for id 0, an id in use or a full table. */
LOCAL_FUNCTION app_buf_add
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    beqz    a0, 9f
    call    app_buf_find
    bnez    a0, 9f
    LDQ     t0, s1, APP_BUFS
    LDQ     t1, s1, (APP_BUFS + 8)
    LDQ     t2, s1, (APP_BUFS + 16)
    bgeu    t1, t2, 9f
    li      t2, APP_BUF_ENTRY
    mul     t2, t1, t2
    add     t0, t0, t2
    ld      t2, 0(sp)
    sd      t2, 0(t0)
    ld      t2, 8(sp)
    sd      t2, 8(t0)
    ld      t2, 16(sp)
    sd      t2, 16(t0)
    addi    t1, t1, 1
    STQ     t1, s1, (APP_BUFS + 8)
    li      a0, 0
    UNFRAME 32
9:  li      a0, 1
    UNFRAME 32
END_FUNCTION app_buf_add

/* L1: the buffer of the id a0 goes back to the OS, and the last entry takes its place. */
LOCAL_FUNCTION app_buf_drop
    FRAME 16
    call    app_buf_find
    beqz    a0, 9f
    sd      a0, 0(sp)
    addi    a1, a0, 16
    addi    a0, a0, 8
    CALL_GLOBAL lantern_shell_unmap
    ld      t0, 0(sp)                       # the entry
    LDQ     t1, s1, APP_BUFS
    LDQ     t2, s1, (APP_BUFS + 8)
    addi    t2, t2, -1
    STQ     t2, s1, (APP_BUFS + 8)
    li      t3, APP_BUF_ENTRY
    mul     t3, t2, t3
    add     t1, t1, t3                      # the last entry
    ld      t3, 0(t1)
    sd      t3, 0(t0)
    ld      t3, 8(t1)
    sd      t3, 8(t0)
    ld      t3, 16(t1)
    sd      t3, 16(t0)
9:  UNFRAME 16
END_FUNCTION app_buf_drop

/*
 * L1: a0 = new memory with a copy of the a1 bytes at a0, or 0. With a source and size of
 * multiples of 8, a page of the source that is all zero bytes is not written: the new memory is
 * zero already, and the OS keeps no memory for a page nobody writes. s2 the source, s3 the size,
 * s4 the copy, s5 the page's offset, s6 its bytes.
 */
LOCAL_FUNCTION app_dup
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    mv      a0, a1
    call    app_map
    beqz    a0, 9f
    mv      s4, a0
    or      t0, s2, s3
    andi    t0, t0, 7
    beqz    t0, 1f
    mv      a1, s2                          # not multiples of 8: all of it
    mv      a2, s3
    call    lantern_copy
    j       8f
1:  li      s5, 0
2:  bgeu    s5, s3, 8f                      # the next page: all zero, or a copy
    sub     s6, s3, s5
    li      t0, 4096
    bltu    s6, t0, 21f
    mv      s6, t0
21: add     t1, s2, s5
    li      t2, 0
3:  add     t3, t1, t2
    ld      t3, 0(t3)
    bnez    t3, 4f
    addi    t2, t2, 8
    bltu    t2, s6, 3b
    j       5f
4:  add     a0, s4, s5
    mv      a1, t1
    mv      a2, s6
    call    lantern_copy
5:  add     s5, s5, s6
    j       2b
8:  mv      a0, s4
9:  LEAVE 0
END_FUNCTION app_dup

/*
 * L1: the a1 bytes of the event at a0 join the events of the next step, which grow when full:
 * a0 = 0, or 1 with no memory. s2 the event, s3 its size, s4 the events, s5 a new size, s6 new memory.
 */
LOCAL_FUNCTION app_event_put
    ENTER 0
    mv      s2, a0
    mv      s3, a1
1:  LDQ     s4, s1, APP_EVENTS
    ld      t0, 0(s4)
    ld      t1, 16(s4)
    add     t2, t1, s3
    addi    t2, t2, 24
    bleu    t2, t0, 2f
    slli    s5, t0, 1                       # twice the room, and the event
    add     s5, s5, s3
    mv      a0, s5
    call    app_map
    beqz    a0, 9f
    mv      s6, a0
    mv      a1, s4
    ld      a2, 16(s4)
    addi    a2, a2, 24
    call    lantern_copy
    sd      s5, 0(s6)
    li      a0, APP_EVENTS
    call    app_unmap
    STQ     s6, s1, APP_EVENTS
    STQ     s5, s1, (APP_EVENTS + 8)
    j       1b
2:  addi    a0, s4, 24
    add     a0, a0, t1
    mv      a1, s2
    mv      a2, s3
    call    lantern_copy
    LDQ     s4, s1, APP_EVENTS
    ld      t1, 16(s4)
    add     t1, t1, s3
    sd      t1, 16(s4)
    li      a0, 0
    LEAVE 0
9:  li      a0, 1
    LEAVE 0
END_FUNCTION app_event_put

/*
 * L1: the node (a0 = 0), the store (1) or the Seen (2) moves to new memory, with the field of its
 * room at byte offset a1 doubled, or each field for a1 = 2^64 - 1: a0 = 0, or 1. s2 the kind, s3 the pair, s4 the room, s5 the room's fields,
 * s6 the new memory. Locals: L a size, L+8 an address.
 */
LOCAL_FUNCTION app_grow
    ENTER 16
    mv      s2, a0
    li      t0, APP_NODE
    li      t1, APP_NODE_ROOM
    li      s5, NODE_ROOM_FIELDS
    li      t2, 1
    bne     s2, t2, 1f
    li      t0, APP_STORE
    li      t1, APP_STORE_ROOM
    li      s5, 2
1:  li      t2, 2
    bne     s2, t2, 2f
    li      t0, APP_SEEN
    li      t1, APP_SEEN_ROOM
    li      s5, 4
2:  add     s3, s1, t0
    add     s4, s1, t1
    li      t0, -1                          # one field: its offset, below the fields and a multiple of 8
    beq     a1, t0, 31f
    slli    t0, s5, 3
    bgeu    a1, t0, 9f
    andi    t0, a1, 7
    bnez    t0, 9f
    add     t1, s4, a1
    ld      t2, 0(t1)
    slli    t2, t2, 1
    sd      t2, 0(t1)
    j       4f
31: li      t0, 0
3:  bgeu    t0, s5, 4f
    slli    t1, t0, 3
    add     t1, s4, t1
    ld      t2, 0(t1)
    slli    t2, t2, 1
    sd      t2, 0(t1)
    addi    t0, t0, 1
    j       3b
4:  mv      a0, s4                          # its size
    addi    a1, sp, L
    bnez    s2, 41f
    CALL_GLOBAL lantern_node_size
    j       43f
41: li      t0, 1
    bne     s2, t0, 42f
    CALL_GLOBAL lantern_store_size
    j       43f
42: CALL_GLOBAL lantern_seen_size
43: bnez    a0, 9f
    ld      a0, L(sp)
    call    app_map
    beqz    a0, 9f
    mv      s6, a0
    ld      t0, L(sp)
    sd      t0, 0(s6)
    ld      a0, 0(s3)                       # the copy
    mv      a1, s4
    mv      a2, s6
    bnez    s2, 51f
    CALL_GLOBAL lantern_node_copy
    j       53f
51: li      t0, 1
    bne     s2, t0, 52f
    CALL_GLOBAL lantern_store_copy
    j       53f
52: CALL_GLOBAL lantern_seen_copy
53: bnez    a0, 8f
    sub     a0, s3, s1
    call    app_unmap
    ld      t0, L(sp)
    sd      s6, 0(s3)
    sd      t0, 8(s3)
    li      a0, 0
    LEAVE 16
8:  sd      s6, (L + 8)(sp)                 # the copy failed: its memory goes back
    addi    a0, sp, (L + 8)
    addi    a1, sp, L
    CALL_GLOBAL lantern_shell_unmap
9:  li      a0, 1
    LEAVE 16
END_FUNCTION app_grow

/*
 * L1: the state of the BufferId table entry a0 moves to new memory with twice the StateRoom of the
 * App: a0 = 0, or 1. s2 the entry, s3 the fork, s4 the new memory. Locals: L a size.
 */
LOCAL_FUNCTION app_regrow
    ENTER 16
    mv      s2, a0
    ADDQ    t0, s1, APP_STATE_ROOM
    li      t1, 0
1:  ld      t2, 0(t0)
    slli    t2, t2, 1
    sd      t2, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, 1
    li      t2, 8
    bltu    t1, t2, 1b
    ld      t0, 8(s2)                       # the fork of the state's slot
    LDQ     a0, t0, NODE_STATE_SLOT
    ADDQ    a1, s1, APP_CONFIG
    call    app_fork
    mv      s3, a0
    ld      a0, 8(s2)
    ADDQ    a1, s1, APP_STATE_ROOM
    addi    a2, sp, L
    mv      t6, s3
    FORK_CALL beacon_state_copy_size
    ld      a0, L(sp)
    call    app_map
    beqz    a0, 9f
    mv      s4, a0
    ld      t0, L(sp)
    sd      t0, 0(s4)
    ld      a0, 8(s2)
    ADDQ    a1, s1, APP_STATE_ROOM
    mv      a2, s4
    mv      t6, s3
    FORK_CALL beacon_state_copy
    bnez    a0, 9f
    addi    a0, s2, 8
    addi    a1, s2, 16
    CALL_GLOBAL lantern_shell_unmap
    ld      t0, L(sp)
    sd      s4, 8(s2)
    sd      t0, 16(s2)
    li      a0, 0
    LEAVE 16
9:  li      a0, 1
    LEAVE 16
END_FUNCTION app_regrow

/*
 * L2: a0 = 0 with the light client store as BufferId 2 (node.md, lantern_node_init: Caller must):
 * lantern_lc_store_init of the anchor state and block with the APP_LC_* capacities; else 1. s2 the
 * store, s3 its size, s4 APP_TMP: the LcRoom, then the size.
 */
LOCAL_FUNCTION app_lc_start
    ENTER 0
    li      t0, APP_TMP
    add     s4, s1, t0
    li      t0, APP_LC_BLOCKS
    sd      t0, 0(s4)
    li      t0, APP_LC_FINALIZED
    sd      t0, 8(s4)
    li      t0, APP_LC_PERIODS
    sd      t0, 16(s4)
    li      t0, APP_LC_BOOTSTRAPS
    sd      t0, 24(s4)
    li      t0, APP_LC_HEADERS
    sd      t0, 32(s4)
    li      t0, APP_LC_COMMITTEES
    sd      t0, 40(s4)
    li      t0, APP_LC_UPDATES
    sd      t0, 48(s4)
    mv      a0, s4
    addi    a1, s4, LcRoom__mem
    CALL_GLOBAL lantern_lc_store_size
    bnez    a0, 9f
    ld      s3, LcRoom__mem(s4)
    mv      a0, s3
    call    app_map
    beqz    a0, 9f
    mv      s2, a0
    sd      s3, 0(s2)
    mv      a0, s4
    li      t0, APP_CONFIG
    add     a1, s1, t0
    LDQ     a2, s1, APP_STATE
    LDQ     a3, s1, APP_BLOCK
    SCRATCH a4
    mv      a5, s2
    CALL_GLOBAL lantern_lc_store_init
    bnez    a0, 9f
    li      a0, NODE_LC_ID
    mv      a1, s2
    mv      a2, s3
    call    app_buf_add
    bnez    a0, 9f
    LEAVE 0
9:  li      a0, 1
    LEAVE 0
END_FUNCTION app_lc_start

/*
 * L2: a0 = 0 when the light client store of the table entry a0 is in a new buffer with twice the
 * capacities of each part (lantern_lc_store_copy); else 1. s2 the entry, s3 the new buffer, s4 its
 * size, s5 APP_TMP: the LcRoom, then the size. Locals: L the new buffer and its size.
 */
LOCAL_FUNCTION app_lc_grow
    ENTER 16
    mv      s2, a0
    li      t0, APP_TMP
    add     s5, s1, t0
    ld      t0, 8(s2)
    li      t1, 0
1:  slli    t2, t1, 3
    add     t3, t0, t2
    ld      t3, LcStore_room(t3)
    slli    t3, t3, 1
    add     t2, s5, t2
    sd      t3, 0(t2)
    addi    t1, t1, 1
    li      t2, 7
    bltu    t1, t2, 1b
    mv      a0, s5
    addi    a1, s5, LcRoom__mem
    CALL_GLOBAL lantern_lc_store_size
    bnez    a0, 9f
    ld      s4, LcRoom__mem(s5)
    mv      a0, s4
    call    app_map
    beqz    a0, 9f
    mv      s3, a0
    sd      s4, 0(s3)
    ld      a0, 8(s2)
    mv      a1, s5
    mv      a2, s3
    CALL_GLOBAL lantern_lc_store_copy
    bnez    a0, 8f
    addi    a0, s2, 8                       # the old buffer goes
    addi    a1, s2, 16
    CALL_GLOBAL lantern_shell_unmap
    sd      s3, 8(s2)
    sd      s4, 16(s2)
    li      a0, 0
    LEAVE 16
8:  sd      s3, L(sp)                       # the new one goes
    sd      s4, (L + 8)(sp)
    addi    a0, sp, L
    addi    a1, sp, (L + 8)
    CALL_GLOBAL lantern_shell_unmap
9:  li      a0, 1
    LEAVE 16
END_FUNCTION app_lc_grow

/*
 * L2: the WORK action a0, by lantern_node_run with its buffers, again with more room while it asks
 * for it; then its WORK_DONE event joins the next step's. s2 the action, s3-s6 the entries of
 * state_a, state_b, state_c and data (or 0), s7 the tries, s8 the kind, s9 a size.
 */
LOCAL_FUNCTION app_work
    ENTER 0
    mv      s2, a0
    LDQ     s8, s2, NodeAction_work_kind
    li      s7, 0
    LDQ     a0, s2, NodeAction_state_a
    call    app_work_entry
    mv      s3, a0
    LDQ     a0, s2, NodeAction_state_b
    call    app_work_entry
    mv      s4, a0
    LDQ     a0, s2, NodeAction_state_c
    call    app_work_entry
    mv      s5, a0
    LDQ     a0, s2, NodeAction_data
    call    app_work_data
    mv      s6, a0
    li      t0, -1                          # an id with no buffer
    beq     s3, t0, 90f
    beq     s4, t0, 90f
    beq     s5, t0, 90f
    beq     s6, t0, 90f
    li      t1, NodeEvent_api_bytes + 24 + NODE_API_CHUNK
    li      t0, NODE_WORK_API_CHUNK         # API_CHUNK: room for a whole chunk
    beq     s8, t0, 15f
    li      t0, NODE_WORK_PUBLISH_DECODE    # PUBLISH_DECODE and PUBLISH_CHECK: room for the bytes of data
    beq     s8, t0, 16f
    li      t0, NODE_WORK_PUBLISH_CHECK
    bne     s8, t0, 1f
16: beqz    s6, 1f
    ld      t1, 16(s6)
    addi    t1, t1, NodeEvent_chunk + 7
    andi    t1, t1, -8
15: LDQ     t0, s1, (APP_WORK_EVENT + 8)
    bgeu    t0, t1, 1f
    mv      s9, t1
    li      a0, APP_WORK_EVENT
    call    app_unmap
    li      a0, APP_WORK_EVENT
    mv      a1, s9
    call    app_alloc
    beqz    a0, 91f
1:  LDQ     t0, s1, APP_WORK_EVENT          # the event's room
    LDQ     t1, s1, (APP_WORK_EVENT + 8)
    sd      t1, 0(t0)
    addi    sp, sp, -32                     # the ninth to eleventh arguments: settings, scratch, event
    LDQ     t0, s1, APP_KZG
    sd      t0, 0(sp)
    SCRATCH t2
    sd      t2, 8(sp)
    LDQ     t0, s1, APP_WORK_EVENT
    sd      t0, 16(sp)
    LDQ     a0, s1, APP_NODE
    LDQ     a1, s1, APP_STORE
    LDQ     a2, s1, APP_SEEN
    mv      a3, s2
    li      a4, 0
    beqz    s3, 11f
    ld      a4, 8(s3)
11: li      a5, 0
    beqz    s4, 12f
    ld      a5, 8(s4)
12: li      a6, 0
    beqz    s5, 13f
    ld      a6, 8(s5)
13: li      a7, 0                           # last: LDQ uses a7
    beqz    s6, 14f
    ld      a7, 8(s6)
14: CALL_GLOBAL lantern_node_run
    addi    sp, sp, 32
    beqz    a0, 8f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    bne     a0, t0, 91f
    addi    s7, s7, 1                       # more room: as the runner's shell
    li      t0, APP_WORK_TRIES
    bgeu    s7, t0, 91f
    li      t0, NODE_WORK_SERVE             # SERVE, NEW_PAYLOAD, FORKCHOICE: a larger event
    beq     s8, t0, 2f
    li      t0, NODE_WORK_LC_SERVE
    beq     s8, t0, 2f
    li      t0, NODE_WORK_LC_PUBLISH
    beq     s8, t0, 2f
    li      t0, NODE_WORK_NEW_PAYLOAD
    beq     s8, t0, 2f
    li      t0, NODE_WORK_FORKCHOICE
    beq     s8, t0, 2f
    li      t0, NODE_WORK_API_ENCODE
    beq     s8, t0, 2f
    li      t0, NODE_WORK_API_CHUNK
    beq     s8, t0, 2f
    li      t0, NODE_WORK_API_EVENT
    beq     s8, t0, 2f
    li      t0, NODE_WORK_PREPARE_PAYLOAD
    beq     s8, t0, 2f
    li      t0, NODE_WORK_GET_PAYLOAD
    beq     s8, t0, 2f
    li      t0, NODE_WORK_PRODUCE_BLOCK
    beq     s8, t0, 2f
    li      t0, NODE_WORK_PRODUCE_BID
    beq     s8, t0, 2f
    li      t0, NODE_WORK_PUBLISH_DECODE
    beq     s8, t0, 2f
    li      t0, NODE_WORK_PUBLISH_SIDECAR
    beq     s8, t0, 2f
    li      t0, NODE_WORK_PUBLISH_CHECK     # PUBLISH_CHECK: the Seen, and the parent's state
    beq     s8, t0, 31f
    li      t0, NODE_WORK_API_SUBMIT        # API_SUBMIT: the Seen, and a larger event
    beq     s8, t0, 7f
    li      t0, NODE_WORK_GOSSIP            # GOSSIP: the Seen, and the proposer state
    beq     s8, t0, 3f
    li      t0, NODE_WORK_TARGET_STATE      # TARGET_STATE, SLOTS, and IMPORT_BLOCK with store room: state_a
    beq     s8, t0, 4f
    li      t0, NODE_WORK_SLOTS
    beq     s8, t0, 4f
    li      t0, NODE_WORK_REPLAY
    beq     s8, t0, 4f
    li      t0, NODE_WORK_UPGRADE           # UPGRADE: state_b, the upgrade's buffer
    beq     s8, t0, 6f
    li      t0, NODE_WORK_LC_BLOCK          # the light client works: state_c, the light client store
    beq     s8, t0, 17f
    li      t0, NODE_WORK_LC_HEAD
    beq     s8, t0, 17f
    li      t0, NODE_WORK_IMPORT_BLOCK
    bne     s8, t0, 5f
    LDQ     t0, s1, APP_STORE
    LDQ     t0, t0, (Store_blocks + 8)
    LDQ     t1, s1, (APP_STORE_ROOM + StoreRoom_nodes)
    bltu    t0, t1, 4f
5:  li      a0, 1                           # else the store
    li      a1, -1
    call    app_grow
    bnez    a0, 91f
    j       1b
2:  LDQ     t0, s1, (APP_WORK_EVENT + 8)
    slli    s9, t0, 2
    li      a0, APP_WORK_EVENT
    call    app_unmap
    li      a0, APP_WORK_EVENT
    mv      a1, s9
    call    app_alloc
    beqz    a0, 91f
    j       1b
3:  li      a0, 2                           # the Seen
    li      a1, -1
    call    app_grow
    bnez    a0, 91f
    beqz    s4, 1b
    mv      a0, s4
    call    app_regrow
    bnez    a0, 91f
    j       1b
31: li      a0, 2
    li      a1, -1
    call    app_grow
    bnez    a0, 91f
4:  beqz    s3, 91f
    mv      a0, s3
    call    app_regrow
    bnez    a0, 91f
    j       1b
6:  beqz    s4, 91f
    mv      a0, s4
    call    app_regrow
    bnez    a0, 91f
    j       1b
17: beqz    s5, 91f
    mv      a0, s5
    call    app_lc_grow
    bnez    a0, 91f
    j       1b
7:  li      a0, 2
    li      a1, -1
    call    app_grow
    bnez    a0, 91f
    j       2b
8:  mv      a0, s8
    mv      a1, s6
    call    app_log_work
    LDQ     a0, s1, APP_WORK_EVENT          # the WORK_DONE event
    ld      a1, 0(a0)
    call    app_event_put
    LEAVE 0
90: ADDRESS a0, app_m_buffer                # an action's BufferId: status 0
    li      a1, app_m_buffer_len
    li      a2, 0
    call    app_fail_status
    LEAVE 0
91: mv      a2, a0                          # a work: status <n>
    ADDRESS a0, app_m_work
    li      a1, app_m_work_len
    call    app_fail_status
    LEAVE 0
END_FUNCTION app_work

/*
 * L1: the history's files: no file open, no segment mapped; with a data directory, the node gets
 * NODE_FLAG_DB and room for a segment of slots, and the directory is made (one already there
 * will do; a failure shows at its first file). s10 the AppDb.
 */
LOCAL_FUNCTION app_db_start
    ENTER 0
    ADDQ    s10, s1, APP_DB
    li      t0, -1
    sd      t0, AppDb_segment(s10)
    sd      t0, (AppDb_segment + 8)(s10)
    li      t1, 0
1:  slli    t2, t1, 5
    add     t2, s10, t2
    sd      t0, AppDb_maps(t2)
    sd      zero, (AppDb_maps + 8)(t2)
    addi    t1, t1, 1
    li      t2, APP_DB_MAP_COUNT
    bltu    t1, t2, 1b
    sd      zero, AppDb_next_map(s10)
    li      t0, -1
    sd      t0, AppDb_anchor_slot(s10)
    LDQ     t0, s1, (APP_ANCHOR + 32)       # the Db from the anchor's slot
    STQ     t0, s1, (APP_ANCHOR + NodeAnchor_history_slot)
    LDQ     s3, s1, (APP_OPTIONS + AppOptions_data_dir + 8)
    beqz    s3, 9f
    LDQ     t0, s1, APP_FLAGS
    ori     t0, t0, NODE_FLAG_DB
    STQ     t0, s1, APP_FLAGS
    li      t0, DB_SEGMENT_SLOTS
    STQ     t0, s1, (APP_NODE_ROOM + NodeRoom_db_slots)
    li      t0, APP_DB_ROOTS
    STQ     t0, s1, (APP_NODE_ROOM + NodeRoom_db_roots)
    li      t0, APP_PATH_MAX
    bgtu    s3, t0, 9f
    ADDQ    s4, s1, APP_PATH                # the directory's path
    sd      s3, 16(s4)
    LDQ     t0, s1, APP_ARGS
    LDQ     t1, s1, (APP_OPTIONS + AppOptions_data_dir)
    add     a1, t0, t1
    addi    a0, s4, 24
    mv      a2, s3
    call    lantern_copy
    mv      a0, s4
    addi    a1, s10, AppDb_op
    CALL_GLOBAL lantern_shell_mkdir
9:  LEAVE 0
END_FUNCTION app_db_start

/* L1: the path of segment a1 of blocks (a0 0) or sidecars (1) in the data directory, <dir>/b<n>.seg or <dir>/s<n>.seg: a ByteList at APP_PATH. s2 the kind, s3 the segment, s4 the next byte. Locals: L 24 digits. */
LOCAL_FUNCTION app_db_path
    ENTER 32
    mv      s2, a0
    mv      s3, a1
    ADDQ    s4, s1, APP_PATH
    LDQ     a2, s1, (APP_OPTIONS + AppOptions_data_dir + 8)
    li      t0, APP_PATH_MAX - 32
    bgtu    a2, t0, 8f
    LDQ     t0, s1, APP_ARGS
    LDQ     t1, s1, (APP_OPTIONS + AppOptions_data_dir)
    add     a1, t0, t1
    addi    a0, s4, 24
    add     s4, a0, a2
    call    lantern_copy
    li      t0, 0x2f                        # /
    sb      t0, 0(s4)
    li      t0, 0x62                        # b
    beqz    s2, 1f
    li      t0, 0x73                        # s
1:  sb      t0, 1(s4)
    addi    s4, s4, 2
    addi    t1, sp, L + 24                  # the number's digits, from the last
    mv      t2, s3
    li      t3, 10
2:  remu    t4, t2, t3
    divu    t2, t2, t3
    addi    t4, t4, 0x30
    addi    t1, t1, -1
    sb      t4, 0(t1)
    bnez    t2, 2b
    addi    t2, sp, L + 24
3:  bgeu    t1, t2, 4f
    lbu     t4, 0(t1)
    sb      t4, 0(s4)
    addi    t1, t1, 1
    addi    s4, s4, 1
    j       3b
4:  li      t0, 0x2e                        # .seg
    sb      t0, 0(s4)
    li      t0, 0x73
    sb      t0, 1(s4)
    li      t0, 0x65
    sb      t0, 2(s4)
    li      t0, 0x67
    sb      t0, 3(s4)
    addi    s4, s4, 4
    ADDQ    t0, s1, APP_PATH
    addi    t1, t0, 24
    sub     t1, s4, t1
    sd      t1, 16(t0)
    LEAVE 32
8:  ADDQ    t0, s1, APP_PATH                # a count past the room: the shell gives its error
    li      t1, APP_PATH_MAX + 1
    sd      t1, 16(t0)
    LEAVE 32
END_FUNCTION app_db_path

/*
 * L1: NODE_ACT_DB_APPEND a0: the record at the end of its segment file, its DbRecord, its bytes
 * and zero bytes to a multiple of 8. A file that is not the open one of its kind opens, and is cut
 * to the record's offset first. A failure gives a line on the standard error, and the file closes,
 * so the next record opens it again. s2 the action, s3 the kind (0 blocks, 1 sidecars), s4 the
 * bytes' table entry, s5 the file, s10 the AppDb. Locals: L a ByteList header, L+24 a u64, L+32 zero bytes.
 */
LOCAL_FUNCTION app_db_append
    ENTER 48
    mv      s2, a0
    ADDQ    s10, s1, APP_DB
    ld      s3, 32(s2)
    andi    s3, s3, 1
    ld      a0, 16(s2)
    call    app_buf_find
    beqz    a0, 99f
    mv      s4, a0
    slli    t0, s3, 3
    add     s5, s10, t0
    addi    s5, s5, AppDb_file
    add     t1, s10, t0
    ld      t2, AppDb_segment(t1)
    ld      t3, 24(s2)
    beq     t2, t3, 2f
    li      t3, -1                          # another file of the kind: it closes
    beq     t2, t3, 1f
    mv      a0, s5
    CALL_GLOBAL lantern_shell_close
    slli    t0, s3, 3
    add     t1, s10, t0
    li      t2, -1
    sd      t2, AppDb_segment(t1)
1:  mv      a0, s3                          # the segment's file, to append to, cut to the offset
    ld      a1, 24(s2)
    call    app_db_path
    li      t0, 1
    sd      t0, (L + 24)(sp)
    ADDQ    a0, s1, APP_PATH
    addi    a1, sp, L + 24
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_open
    ld      t0, AppDb_op(s10)
    bnez    t0, 90f
    ld      t0, (AppDb_op + 8)(s10)
    sd      t0, 0(s5)
    mv      a0, s5
    addi    a1, s2, 40
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_truncate
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
    ld      t2, 24(s2)
    slli    t0, s3, 3
    add     t1, s10, t0
    sd      t2, AppDb_segment(t1)
2:  addi    t0, s2, 48                      # the DbRecord: a ByteList of the action's 64 bytes
    addi    t1, sp, L
    sub     t0, t0, t1
    li      t2, 24
    sd      t2, L(sp)
    sd      t0, (L + 8)(sp)
    li      t2, DbRecord__mem
    sd      t2, (L + 16)(sp)
    mv      a0, s5
    addi    a1, sp, L
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_append
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
    mv      a0, s5                          # the bytes
    ld      a1, 8(s4)
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_append
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
    ld      t0, 8(s4)                       # zero bytes to a multiple of 8
    ld      t0, 16(t0)
    neg     t0, t0
    andi    t0, t0, 7
    beqz    t0, 99f
    sd      zero, (L + 32)(sp)
    li      t1, 24
    sd      t1, L(sp)
    li      t1, 32
    sd      t1, (L + 8)(sp)
    sd      t0, (L + 16)(sp)
    mv      a0, s5
    addi    a1, sp, L
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_append
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
99: LEAVE 48
89: mv      a0, s5                          # the file closes
    CALL_GLOBAL lantern_shell_close
    slli    t0, s3, 3
    add     t1, s10, t0
    li      t2, -1
    sd      t2, AppDb_segment(t1)
90: ld      t0, AppDb_op(s10)               # cannot write <path>: error <n>
    sd      t0, (L + 24)(sp)
    mv      a0, s3
    ld      a1, 24(s2)
    call    app_db_path
    call    app_line_start
    ADDRESS a0, app_m_write
    li      a1, app_m_write_len
    call    app_line_text
    call    app_line_path
    ADDRESS a0, app_m_error
    li      a1, app_m_error_len
    call    app_line_text
    ld      a0, (L + 24)(sp)
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
    LEAVE 48
END_FUNCTION app_db_append

/*
 * L1: NODE_ACT_DB_DROP a0: the segment's file goes: the open file of its kind, when it is that
 * segment, closes; a map of it goes; then the file is deleted. s2 the action, s3 the kind (0
 * blocks, 1 sidecars), s4 the segment, s5 the map key, s6 a map's index, s7 a map, s10 the AppDb.
 */
LOCAL_FUNCTION app_db_drop
    ENTER 0
    mv      s2, a0
    ADDQ    s10, s1, APP_DB
    ld      s3, 24(s2)
    andi    s3, s3, 1
    ld      s4, 16(s2)
    slli    t0, s3, 3                       # the open file of its kind
    add     t0, s10, t0
    ld      t1, AppDb_segment(t0)
    bne     t1, s4, 1f
    addi    a0, t0, AppDb_file
    CALL_GLOBAL lantern_shell_close
    slli    t0, s3, 3
    add     t0, s10, t0
    li      t1, -1
    sd      t1, AppDb_segment(t0)
1:  slli    s5, s3, 63                      # its map
    or      s5, s5, s4
    li      s6, 0
2:  li      t0, APP_DB_MAP_COUNT
    bgeu    s6, t0, 4f
    slli    t0, s6, 5
    add     s7, s10, t0
    addi    s7, s7, AppDb_maps
    ld      t0, 0(s7)
    bne     t0, s5, 3f
    ld      t0, 8(s7)
    beqz    t0, 21f
    addi    a0, s7, 8
    addi    a1, s7, 24
    CALL_GLOBAL lantern_shell_unmap_file
21: li      t0, -1
    sd      t0, 0(s7)
    sd      zero, 8(s7)
3:  addi    s6, s6, 1
    j       2b
4:  mv      a0, s3                          # the file
    mv      a1, s4
    call    app_db_path
    ADDQ    a0, s1, APP_PATH
    addi    a1, s10, AppDb_op
    CALL_GLOBAL lantern_shell_remove
    LEAVE 0
END_FUNCTION app_db_drop

/*
 * L0: a0 = the AppDb's view entry of the record at offset a0 of the mapped segment a1: its
 * ByteList in place, at byte DbRecord_bytes of the record; 0 when the record is not all inside
 * the map, or its ByteList header is not of its bytes. Uses t0-t5, a7.
 */
LOCAL_FUNCTION app_db_record
    UNWIND_END_PROLOGUE
    ld      t0, 8(a1)
    beqz    t0, 8f
    ld      t1, 16(a1)
    addi    t2, a0, DbRecord__mem
    bltu    t2, a0, 8f
    bgtu    t2, t1, 8f
    add     t0, t0, a0                      # the record, its bytes inside
    ld      t3, DbRecord_length(t0)
    sub     t1, t1, t2
    bgtu    t3, t1, 8f
    addi    t3, t3, 24                      # its ByteList: size 24 + length, offset 24
    ld      t4, DbRecord_bytes(t0)
    bne     t3, t4, 8f
    ld      t4, (DbRecord_bytes + 8)(t0)
    li      t5, 24
    bne     t4, t5, 8f
    ADDQ    t4, s1, APP_DB + AppDb_view
    addi    t0, t0, DbRecord_bytes
    sd      t0, 8(t4)
    mv      a0, t4
    ret
8:  li      a0, 0
    ret
END_FUNCTION app_db_record

/*
 * L1: a0 = the table entry of a work's data BufferId a0 as app_work_entry gives; for a
 * NODE_DB_REF, the AppDb's view entry of its record in the segment, mapped again when the file
 * grew past the map, or 2^64 - 1 when the record is not there. s2 the kind, s3 the segment, s4
 * the offset, s5 the map's key, s6 a map, s10 the AppDb.
 */
LOCAL_FUNCTION app_work_data
    ENTER 0
    bltz    a0, 1f
    call    app_work_entry
    LEAVE 0
1:  ADDQ    s10, s1, APP_DB
    srli    s2, a0, 62
    andi    s2, s2, 1
    srli    s3, a0, 48
    li      t0, 0x3fff
    and     s3, s3, t0
    slli    s4, a0, 16
    srli    s4, s4, 16
    slli    s5, s2, 63
    or      s5, s5, s3
    li      t1, 0                           # the map of the segment
2:  li      t0, APP_DB_MAP_COUNT
    bgeu    t1, t0, 5f
    slli    t2, t1, 5
    add     s6, s10, t2
    addi    s6, s6, AppDb_maps
    ld      t0, 0(s6)
    beq     t0, s5, 3f
    addi    t1, t1, 1
    j       2b
3:  mv      a0, s4
    mv      a1, s6
    call    app_db_record
    bnez    a0, 9f
    j       6f
5:  ld      t1, AppDb_next_map(s10)         # else the next entry in turn
    addi    t0, t1, 1
    andi    t0, t0, APP_DB_MAP_COUNT - 1
    sd      t0, AppDb_next_map(s10)
    slli    t2, t1, 5
    add     s6, s10, t2
    addi    s6, s6, AppDb_maps
6:  ld      t0, 8(s6)                       # its old map goes
    beqz    t0, 7f
    addi    a0, s6, 8
    addi    a1, s6, 24
    CALL_GLOBAL lantern_shell_unmap_file
7:  li      t0, -1
    sd      t0, 0(s6)
    sd      zero, 8(s6)
    mv      a0, s2
    mv      a1, s3
    call    app_db_path
    ADDQ    a0, s1, APP_PATH
    addi    a1, s10, AppDb_op
    CALL_GLOBAL lantern_shell_map_file
    ld      t0, AppDb_op(s10)
    bnez    t0, 8f
    ld      t0, (AppDb_op + 8)(s10)
    beqz    t0, 8f
    sd      t0, 8(s6)
    sd      s5, 0(s6)
    ld      t0, (AppDb_op + 16)(s10)
    sd      t0, 16(s6)
    ld      t0, (AppDb_op + 24)(s10)
    sd      t0, 24(s6)
    mv      a0, s4
    mv      a1, s6
    call    app_db_record
    bnez    a0, 9f
8:  li      a0, -1
9:  LEAVE 0
END_FUNCTION app_work_data

/* L1: <dir>/<the a1 bytes of the name at a0> of the data directory, as a ByteList at a2 of APP_PATH_MAX bytes of room. s2 the name, s3 its length, s4 the ByteList. */
LOCAL_FUNCTION app_db_file
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    mv      s4, a2
    li      t0, 24 + APP_PATH_MAX
    sd      t0, 0(s4)
    li      t0, 24
    sd      t0, 8(s4)
    LDQ     a2, s1, (APP_OPTIONS + AppOptions_data_dir + 8)
    add     t0, a2, s3
    addi    t0, t0, 1
    li      t1, APP_PATH_MAX
    bgtu    t0, t1, 8f
    sd      t0, 16(s4)
    LDQ     t0, s1, APP_ARGS
    LDQ     t1, s1, (APP_OPTIONS + AppOptions_data_dir)
    add     a1, t0, t1
    addi    a0, s4, 24
    call    lantern_copy
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_data_dir + 8)
    addi    a0, s4, 24
    add     a0, a0, t0
    li      t0, 0x2f                        # /
    sb      t0, 0(a0)
    addi    a0, a0, 1
    mv      a1, s2
    mv      a2, s3
    call    lantern_copy
    LEAVE 0
8:  li      t0, APP_PATH_MAX + 1            # a count past the room: the shell gives its error
    sd      t0, 16(s4)
    LEAVE 0
END_FUNCTION app_db_file

/* L1: a0 = 1 when the block segment a0's file is there (it opens to read), else 0. s10 the AppDb. Locals: L the mode. */
LOCAL_FUNCTION app_db_exists
    ENTER 16
    ADDQ    s10, s1, APP_DB
    mv      a1, a0
    li      a0, 0
    call    app_db_path
    sd      zero, L(sp)
    ADDQ    a0, s1, APP_PATH
    addi    a1, sp, L
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_open
    ld      t0, AppDb_op(s10)
    bnez    t0, 8f
    addi    a0, s10, AppDb_op + 8
    CALL_GLOBAL lantern_shell_close
    li      a0, 1
    LEAVE 16
8:  li      a0, 0
    LEAVE 16
END_FUNCTION app_db_exists

/*
 * L1: for a start from anchor.ssz: the first block segment file there, from 0 to the anchor's
 * segment, gives the anchor's history_slot; the Db has room for the slots from it to the last
 * block segment file there, from the anchor's on, and a segment more, and a power of two of roots
 * above twice them. s2 a segment, s3 the anchor's segment, s4 the first, s5 the last.
 */
LOCAL_FUNCTION app_db_history
    ENTER 0
    LDQ     s3, s1, (APP_ANCHOR + 32)
    srli    s3, s3, DB_SEGMENT_SHIFT
    mv      s4, s3
    li      s2, 0
1:  bgtu    s2, s3, 2f
    mv      a0, s2
    call    app_db_exists
    bnez    a0, 11f
    addi    s2, s2, 1
    j       1b
11: mv      s4, s2
2:  mv      s5, s3
    addi    s2, s3, 1
3:  mv      a0, s2
    call    app_db_exists
    beqz    a0, 4f
    mv      s5, s2
    addi    s2, s2, 1
    j       3b
4:  slli    t0, s4, DB_SEGMENT_SHIFT
    STQ     t0, s1, (APP_ANCHOR + NodeAnchor_history_slot)
    sub     t0, s5, s4
    addi    t0, t0, 2
    slli    t0, t0, DB_SEGMENT_SHIFT
    STQ     t0, s1, (APP_NODE_ROOM + NodeRoom_db_slots)
    slli    t0, t0, 1                       # a power of two above twice the slots
    li      t1, 1
5:  bgtu    t1, t0, 6f
    slli    t1, t1, 1
    j       5b
6:  STQ     t1, s1, (APP_NODE_ROOM + NodeRoom_db_roots)
    LEAVE 0
END_FUNCTION app_db_history

/*
 * L1: for a start from anchor.ssz: each segment file there, the blocks' then the sidecars', from
 * the segment of history_slot to the end of the Db's room, goes to lantern_node_db_scan; a file
 * with bytes after its last whole record is cut there: a0 = 0, or 2 after a line on the standard
 * error. s2 the kind, s3 the segment, s4 the end, s5 a status, s10 the AppDb. Locals: L a
 * ByteList header, L+24 valid, L+32 the segment, L+40 the kind, L+48 the file's size or a mode,
 * L+56 a file.
 */
LOCAL_FUNCTION app_db_scan_all
    ENTER 64
    ADDQ    s10, s1, APP_DB
    LDQ     t0, s1, (APP_ANCHOR + NodeAnchor_history_slot)
    srli    t0, t0, DB_SEGMENT_SHIFT
    LDQ     s4, s1, (APP_NODE_ROOM + NodeRoom_db_slots)
    srli    s4, s4, DB_SEGMENT_SHIFT
    add     s4, s4, t0
    li      s2, 0
1:  LDQ     s3, s1, (APP_ANCHOR + NodeAnchor_history_slot)
    srli    s3, s3, DB_SEGMENT_SHIFT
2:  bgeu    s3, s4, 7f
    mv      a0, s2
    mv      a1, s3
    call    app_db_path
    ADDQ    a0, s1, APP_PATH
    addi    a1, s10, AppDb_op
    CALL_GLOBAL lantern_shell_map_file
    ld      t0, AppDb_op(s10)
    bnez    t0, 6f                          # not there
    ld      t0, (AppDb_op + 8)(s10)
    beqz    t0, 6f                          # empty
    addi    t1, sp, L                       # its bytes: a ByteList of the map
    sub     t0, t0, t1
    li      t2, 24
    sd      t2, L(sp)
    sd      t0, (L + 8)(sp)
    ld      t0, (AppDb_op + 16)(s10)
    sd      t0, (L + 16)(sp)
    sd      t0, (L + 48)(sp)
    sd      s3, (L + 32)(sp)
    sd      s2, (L + 40)(sp)
    LDQ     a0, s1, APP_NODE
    addi    a1, sp, L + 32
    addi    a2, sp, L + 40
    addi    a3, sp, L
    addi    a4, sp, L + 24
    CALL_GLOBAL lantern_node_db_scan
    mv      s5, a0
    addi    a0, s10, AppDb_op + 8
    addi    a1, s10, AppDb_op + 24
    CALL_GLOBAL lantern_shell_unmap_file
    bnez    s5, 8f
    ld      t0, (L + 24)(sp)                # bytes after the last whole record: the file is cut there
    ld      t1, (L + 48)(sp)
    bgeu    t0, t1, 6f
    li      t0, 1
    sd      t0, (L + 48)(sp)
    ADDQ    a0, s1, APP_PATH
    addi    a1, sp, L + 48
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_open
    ld      t0, AppDb_op(s10)
    bnez    t0, 6f
    ld      t0, (AppDb_op + 8)(s10)
    sd      t0, (L + 56)(sp)
    addi    a0, sp, L + 56
    addi    a1, sp, L + 24
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_truncate
    addi    a0, sp, L + 56
    CALL_GLOBAL lantern_shell_close
6:  addi    s3, s3, 1
    j       2b
7:  addi    s2, s2, 1
    li      t0, 2
    bltu    s2, t0, 1b
    li      a0, 0
    LEAVE 64
8:  ADDQ    t0, s1, APP_PATH                # <path>: status <n>
    addi    a0, t0, 24
    ld      a1, 16(t0)
    mv      a2, s5
    call    app_fail_status
    LEAVE 64
END_FUNCTION app_db_scan_all

/*
 * L1: NODE_ACT_DB_STATE a0, with no anchor written in this run or one DB_SEGMENT_SLOTS slots
 * back: the open segment files are synced; <dir>/anchor.tmp gets two ByteLists, the second at the
 * first multiple of 8 after the first: the state's SSZ bytes, then those of its block's message;
 * it is synced and renamed over <dir>/anchor.ssz, and the directory is synced. A failure gives a
 * line on the standard error. s2 the action, s3 the state's entry, s4 the block's entry, s5 the
 * state's ByteList, s6 its size, s10 the AppDb. Locals: L a ByteList header, L+24 a u64, L+32
 * zero bytes, L+40 a size, L+48 the fork, L+56 the file, L+64 the message's ByteList header.
 */
LOCAL_FUNCTION app_db_state
    ENTER 96
    mv      s2, a0
    ADDQ    s10, s1, APP_DB
    li      s5, 0
    ld      t0, AppDb_anchor_slot(s10)
    li      t1, -1
    beq     t0, t1, 1f
    li      t1, DB_SEGMENT_SLOTS
    add     t0, t0, t1
    ld      t1, 32(s2)
    bltu    t1, t0, 99f
1:  ld      a0, 16(s2)
    call    app_buf_find
    beqz    a0, 99f
    mv      s3, a0
    ld      a0, 24(s2)
    call    app_buf_find
    beqz    a0, 99f
    mv      s4, a0
    ld      t0, AppDb_segment(s10)          # the open segment files are synced
    li      t1, -1
    beq     t0, t1, 2f
    addi    a0, s10, AppDb_file
    addi    a1, s10, AppDb_op
    CALL_GLOBAL lantern_shell_sync
2:  ld      t0, (AppDb_segment + 8)(s10)
    li      t1, -1
    beq     t0, t1, 3f
    addi    a0, s10, AppDb_file + 8
    addi    a1, s10, AppDb_op
    CALL_GLOBAL lantern_shell_sync
3:  ld      a0, 32(s2)                      # the state's SSZ bytes: their size, then the bytes
    ADDQ    a1, s1, APP_CONFIG
    call    app_fork
    sd      a0, (L + 48)(sp)
    li      t0, 24
    sd      t0, L(sp)
    sd      zero, (L + 40)(sp)
    mv      t6, a0
    ld      a0, 8(s3)
    SCRATCH a1
    addi    a2, sp, L
    addi    a3, sp, L + 40
    FORK_CALL node_state_bytes
    ld      s6, (L + 40)(sp)
    li      t0, 24
    bleu    s6, t0, 99f
    mv      a0, s6
    call    app_map
    beqz    a0, 99f
    mv      s5, a0
    sd      s6, 0(s5)
    ld      t6, (L + 48)(sp)
    ld      a0, 8(s3)
    SCRATCH a1
    mv      a2, s5
    addi    a3, sp, L + 40
    FORK_CALL node_state_bytes
    bnez    a0, 98f
    ADDRESS a0, app_anchor_tmp_name         # anchor.tmp, cut to 0
    li      a1, app_anchor_tmp_name_len
    ADDQ    a2, s1, APP_PATH
    call    app_db_file
    li      t0, 1
    sd      t0, (L + 24)(sp)
    ADDQ    a0, s1, APP_PATH
    addi    a1, sp, L + 24
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_open
    ld      t0, AppDb_op(s10)
    bnez    t0, 90f
    ld      t0, (AppDb_op + 8)(s10)
    sd      t0, (L + 56)(sp)
    sd      zero, (L + 24)(sp)
    addi    a0, sp, L + 56
    addi    a1, sp, L + 24
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_truncate
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
    addi    t1, sp, L                       # the state's ByteList, its header and bytes
    sub     t0, s5, t1
    li      t2, 24
    sd      t2, L(sp)
    sd      t0, (L + 8)(sp)
    sd      s6, (L + 16)(sp)
    addi    a0, sp, L + 56
    addi    a1, sp, L
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_append
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
    neg     t0, s6                          # zero bytes to a multiple of 8
    andi    t0, t0, 7
    beqz    t0, 4f
    sd      zero, (L + 32)(sp)
    li      t1, 24
    sd      t1, L(sp)
    li      t1, 32
    sd      t1, (L + 8)(sp)
    sd      t0, (L + 16)(sp)
    addi    a0, sp, L + 56
    addi    a1, sp, L
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_append
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
4:  ld      t2, 8(s4)                       # the message's ByteList: its header, then its bytes, from 100 of the SignedBeaconBlock
    ld      t0, 16(t2)
    addi    t0, t0, -100
    sd      t0, (L + 80)(sp)
    addi    t0, t0, 24
    sd      t0, (L + 64)(sp)
    li      t1, 24
    sd      t1, (L + 72)(sp)
    sd      t1, L(sp)
    li      t0, 64
    sd      t0, (L + 8)(sp)
    sd      t1, (L + 16)(sp)
    addi    a0, sp, L + 56
    addi    a1, sp, L
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_append
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
    ld      t2, 8(s4)
    ld      t0, 8(t2)
    add     t0, t2, t0
    addi    t0, t0, 100
    addi    t1, sp, L
    sub     t0, t0, t1
    li      t1, 24
    sd      t1, L(sp)
    sd      t0, (L + 8)(sp)
    ld      t0, 16(t2)
    addi    t0, t0, -100
    sd      t0, (L + 16)(sp)
    addi    a0, sp, L + 56
    addi    a1, sp, L
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_append
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
    addi    a0, sp, L + 56
    addi    a1, s10, AppDb_op
    CALL_GLOBAL lantern_shell_sync
    ld      t0, AppDb_op(s10)
    bnez    t0, 89f
    addi    a0, sp, L + 56
    CALL_GLOBAL lantern_shell_close
    ADDRESS a0, app_anchor_name             # over anchor.ssz, and the directory synced
    li      a1, app_anchor_name_len
    ADDQ    a2, s1, APP_PATH2
    call    app_db_file
    ADDQ    a0, s1, APP_PATH
    ADDQ    a1, s1, APP_PATH2
    addi    a2, s10, AppDb_op
    CALL_GLOBAL lantern_shell_rename
    ld      t0, AppDb_op(s10)
    bnez    t0, 90f
    ADDRESS a0, app_anchor_name
    li      a1, 0
    ADDQ    a2, s1, APP_PATH
    call    app_db_file
    ADDQ    a0, s1, APP_PATH
    addi    a1, s10, AppDb_op
    CALL_GLOBAL lantern_shell_sync_dir
    ld      t0, 32(s2)
    sd      t0, AppDb_anchor_slot(s10)
    j       98f
89: addi    a0, sp, L + 56                  # the file closes
    CALL_GLOBAL lantern_shell_close
90: ld      t0, AppDb_op(s10)               # cannot write <path>: error <n>
    sd      t0, (L + 24)(sp)
    call    app_line_start
    ADDRESS a0, app_m_write
    li      a1, app_m_write_len
    call    app_line_text
    call    app_line_path
    ADDRESS a0, app_m_error
    li      a1, app_m_error_len
    call    app_line_text
    ld      a0, (L + 24)(sp)
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
98: beqz    s5, 99f                         # the bytes' memory goes back
    sd      s5, (L + 24)(sp)
    sd      s6, (L + 40)(sp)
    addi    a0, sp, L + 24
    addi    a1, sp, L + 40
    CALL_GLOBAL lantern_shell_unmap
99: LEAVE 96
END_FUNCTION app_db_state

/* L1: a0 = the table entry of the BufferId a0, 0 for id 0, or 2^64 - 1 when no entry has it. */
LOCAL_FUNCTION app_work_entry
    FRAME 0
    beqz    a0, 9f
    call    app_buf_find
    bnez    a0, 9f
    li      a0, -1
9:  UNFRAME 0
END_FUNCTION app_work_entry

/*
 * L2: the actions of the step, in order: BYTES_PUT, STATE_COPY, STATE_FREE and BYTES_FREE on the
 * BufferId table, WORK by app_work. s2 the next action, s3 the end, s4 its size, s5 an entry.
 */
LOCAL_FUNCTION app_actions
    ENTER 0
    LDQ     s2, s1, APP_ACTIONS
    ld      s3, 16(s2)
    addi    s2, s2, 24
    add     s3, s2, s3
1:  bgeu    s2, s3, 9f
    ld      s4, 0(s2)
    ld      t0, 8(s2)
    li      t1, NODE_ACT_DB_APPEND
    bne     t0, t1, 11f
    mv      a0, s2                          # DB_APPEND: the record in its segment file
    call    app_db_append
    j       8f
11: li      t1, NODE_ACT_DB_DROP
    bne     t0, t1, 12f
    mv      a0, s2                          # DB_DROP: the segment's file goes
    call    app_db_drop
    j       8f
12: li      t1, NODE_ACT_DB_STATE
    bne     t0, t1, 10f
    mv      a0, s2                          # DB_STATE: anchor.ssz
    call    app_db_state
    j       8f
10: li      t1, NODE_ACT_STATE_BYTES
    bne     t0, t1, 13f
    mv      a0, s2                          # STATE_BYTES: the state's SSZ bytes
    call    app_state_bytes
    j       8f
13: li      t1, NODE_ACT_BYTES_PUT
    bne     t0, t1, 131f
    addi    a0, s2, 24                      # BYTES_PUT: a copy of the ByteList
    ld      a1, 24(s2)
    call    app_dup
    beqz    a0, 8f
    mv      a1, a0
    ld      a0, 16(s2)
    ld      a2, 24(s2)
    call    app_buf_add
    j       8f
131: li     t1, NODE_ACT_BYTES_NEW
    bne     t0, t1, 2f
    ld      a0, 24(s2)                      # BYTES_NEW: a ByteList of the size, its bytes zero
    call    app_map
    beqz    a0, 8f
    ld      t1, 24(s2)
    sd      t1, 0(a0)
    li      t2, 24
    sd      t2, 8(a0)
    addi    t1, t1, -24
    sd      t1, 16(a0)
    mv      a1, a0
    ld      a0, 16(s2)
    ld      a2, 24(s2)
    call    app_buf_add
    j       8f
2:  li      t1, NODE_ACT_STATE_COPY
    bne     t0, t1, 3f
    ld      a0, 16(s2)                      # STATE_COPY: a copy of the source buffer
    call    app_buf_find
    beqz    a0, 8f
    mv      s5, a0
    ld      a0, 8(s5)
    ld      a1, 16(s5)
    call    app_dup
    beqz    a0, 8f
    mv      a1, a0
    ld      a0, 24(s2)
    ld      a2, 16(s5)
    call    app_buf_add
    j       8f
3:  li      t1, NODE_ACT_STATE_FREE
    beq     t0, t1, 31f
    li      t1, NODE_ACT_BYTES_FREE
    bne     t0, t1, 4f
31: ld      a0, 16(s2)                      # STATE_FREE, BYTES_FREE
    call    app_buf_drop
    j       8f
4:  li      t1, NODE_ACT_WORK
    bne     t0, t1, 5f
    mv      a0, s2
    call    app_work
    j       8f
5:  li      t1, NODE_ACT_ENGINE
    bne     t0, t1, 51f
    mv      a0, s2
    call    app_engine_request
    j       8f
51: li      t1, NODE_ACT_BUILDER
    bne     t0, t1, 6f
    mv      a0, s2
    call    app_builder_request
    j       8f
6:  li      t1, NODE_ACT_DISCV5
    bne     t0, t1, 7f
    ld      t2, (24 + 8)(s2)                # DISCV5: its events join discv5's
    addi    a0, s2, 24
    add     a0, a0, t2
    ld      a1, (24 + 16)(s2)
    call    app_dv_put
    j       8f
7:  li      t1, NODE_ACT_P2P_LIST
    bne     t0, t1, 71f
    LDQ     a0, s1, APP_SHELL               # P2P_LIST: the shell requests of libp2p
    addi    a1, s2, 16
    LDQ     a2, s1, APP_SHELL_EVENTS
    CALL_GLOBAL libp2p_shell_perform
    j       8f
71: li      t1, NODE_ACT_API_SEND
    beq     t0, t1, 72f
    li      t1, NODE_ACT_API_CLOSE
    bne     t0, t1, 8f
72: mv      a0, s2                          # API_SEND, API_CLOSE: to the Beacon API's connection
    call    app_api_action
8:  add     s2, s2, s4
    j       1b
9:  call    app_api_flush                   # the answers go out now
    LEAVE 0
END_FUNCTION app_actions

/*
 * L2: lantern_node_step with the events of the App and the libp2p state a0 and Tick a1 (both 0 with
 * no network), again with a larger node and actions while it asks for them; then the accepted
 * events leave the queue and the actions run. s2 p2p, s3 tick, s4 the tries, s5 a size.
 */
LOCAL_FUNCTION app_step
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    li      s4, 0
1:  LDQ     t0, s1, APP_ACTIONS
    li      t1, 24
    sd      t1, 8(t0)
    sd      zero, 16(t0)
    LDQ     a0, s1, APP_NODE
    LDQ     a1, s1, APP_STORE
    mv      a2, s2
    mv      a3, s3
    LDQ     a4, s1, APP_EVENTS
    SCRATCH a5
    LDQ     a6, s1, APP_ACTIONS
    ADDQ    a7, s1, APP_RESULT
    CALL_GLOBAL lantern_node_step
    beqz    a0, 3f
    li      t0, LANTERN_BUFFER_TOO_SMALL
    bne     a0, t0, 2f
    addi    s4, s4, 1
    li      t0, APP_STEP_TRIES
    bgeu    s4, t0, 21f
    LDQ     t0, s1, (APP_RESULT + NodeStepResult_short)  # the buffer short of room grows
    li      t1, NODE_SHORT_NODE
    bne     t0, t1, 11f
    li      a0, 0                           # the node: the field that is short
    LDQ     a1, s1, (APP_RESULT + NodeStepResult_room)
    call    app_grow
    bnez    a0, 21f
    j       1b
11: li      s5, APP_ACTIONS                 # actions, or scratch: twice the room
    li      t1, NODE_SHORT_SCRATCH
    bne     t0, t1, 12f
    li      s5, APP_SCRATCH
12: add     t0, s1, s5
    ld      s6, 8(t0)
    slli    s6, s6, 1
    mv      a0, s5
    call    app_unmap
    mv      a0, s5
    mv      a1, s6
    call    app_alloc
    beqz    a0, 21f
    j       1b
21: call    app_line_start                  # a node step: no room in buffer <short>
    ADDRESS a0, app_m_step
    li      a1, app_m_step_len
    call    app_line_text
    ADDRESS a0, app_m_room
    li      a1, app_m_room_len
    call    app_line_text
    LDQ     a0, s1, (APP_RESULT + NodeStepResult_short)
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
    LEAVE 0
2:  mv      a2, a0                          # a node step: status <n>
    ADDRESS a0, app_m_step
    li      a1, app_m_step_len
    call    app_fail_status
    LEAVE 0
3:  LDQ     t0, s1, APP_EVENTS              # the accepted events leave the queue
    ld      t1, 16(t0)
    addi    t2, t0, 24
    li      t3, 0
    LDQ     t4, s1, APP_RESULT
4:  beqz    t4, 5f
    bgeu    t3, t1, 5f
    add     a3, t2, t3
    ld      a3, 0(a3)
    add     t3, t3, a3
    addi    t4, t4, -1
    j       4b
5:  sub     a2, t1, t3
    sd      a2, 16(t0)
    mv      a0, t2
    add     a1, t2, t3
    call    lantern_copy
    call    app_actions
    LEAVE 0
END_FUNCTION app_step


/*
 * L0: a0 = the bytes of the base64url text at a0 of a1 bytes (RFC 4648 section 5, with or without
 * padding), written at a2, at most a3; or 2^64 - 1 for a byte of no digit or too many bytes. Uses t0-t5.
 */
LOCAL_FUNCTION app_base64url
    UNWIND_END_PROLOGUE
    li      t0, 0                           # the bits
    li      t1, 0                           # their count
    li      t2, 0                           # the bytes out
1:  beqz    a1, 8f
    lbu     t3, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, -1
    li      t4, 0x3d                        # = ends the digits
    beq     t3, t4, 8f
    addi    t4, t3, -0x41                   # A to Z: 0 to 25
    li      t5, 26
    bltu    t4, t5, 2f
    addi    t4, t3, -0x61                   # a to z: 26 to 51
    bgeu    t4, t5, 11f
    addi    t4, t4, 26
    j       2f
11: addi    t4, t3, -0x30                   # 0 to 9: 52 to 61
    li      t5, 10
    bgeu    t4, t5, 12f
    addi    t4, t4, 52
    j       2f
12: li      t4, 62
    li      t5, 0x2d                        # -
    beq     t3, t5, 2f
    li      t4, 63
    li      t5, 0x5f                        # _
    bne     t3, t5, 9f
2:  slli    t0, t0, 6
    or      t0, t0, t4
    addi    t1, t1, 6
    li      t5, 8
    bltu    t1, t5, 1b
    addi    t1, t1, -8
    bgeu    t2, a3, 9f
    srl     t4, t0, t1
    add     t5, a2, t2
    sb      t4, 0(t5)
    addi    t2, t2, 1
    li      t5, 1                           # only the bits not yet out stay
    sll     t5, t5, t1
    addi    t5, t5, -1
    and     t0, t0, t5
    j       1b
8:  mv      a0, t2
    ret
9:  li      a0, -1
    ret
END_FUNCTION app_base64url

/*
 * L2: a NODE_EV_ENR event of each record of --boot-nodes, with commas between them; a line on
 * the standard error for one that is not "enr:" and base64url. s2 the next byte, s3 the end, s4
 * the record's start, s5 the record's number, s6 the event at APP_RECORD. Locals: L the record's length.
 */
LOCAL_FUNCTION app_boot_nodes
    ENTER 16
    ADDQ    s6, s1, APP_RECORD
    ld      t0, APP_ARGS(s1)
    LDQ     t1, s1, (APP_OPTIONS + AppOptions_boot_nodes)
    LDQ     t2, s1, (APP_OPTIONS + AppOptions_boot_nodes + 8)
    add     s2, t0, t1
    add     s3, s2, t2
    li      s5, 0
1:  bgeu    s2, s3, 9f
    mv      s4, s2                          # a record: to a comma or the end
2:  bgeu    s2, s3, 3f
    lbu     t0, 0(s2)
    li      t1, 0x2c
    beq     t0, t1, 3f
    addi    s2, s2, 1
    j       2b
3:  sub     a1, s2, s4
    addi    s2, s2, 1                       # past the comma
    addi    s5, s5, 1
    li      t0, 4
    bltu    a1, t0, 7f
    mv      a0, s4
    sd      a1, L(sp)
    li      a1, 4
    ADDRESS a2, app_enr_prefix
    li      a3, 4
    call    app_name_is
    beqz    a0, 7f
    addi    a0, s4, 4                       # its bytes, after the event and ByteList headers
    ld      a1, L(sp)
    addi    a1, a1, -4
    addi    a2, s6, 48
    li      a3, APP_RECORD_MAX
    call    app_base64url
    li      t0, -1
    beq     a0, t0, 7f
    addi    t0, a0, (48 + 7)                # the event: size, NODE_EV_ENR, 0, then the ByteList
    andi    t0, t0, -8
    sd      t0, 0(s6)
    li      t1, NODE_EV_ENR
    sd      t1, 8(s6)
    sd      zero, 16(s6)
    addi    t1, t0, -24
    sd      t1, 24(s6)
    li      t1, 24
    sd      t1, 32(s6)
    sd      a0, 40(s6)
    mv      a0, s6
    mv      a1, t0
    call    app_event_put
    ld      t0, 40(s6)                      # and an ADD_NODE of discv5: size, kind, len, the record
    addi    t1, t0, (DISCV5_EV_ADD_DATA + 7)
    andi    t1, t1, -8
    sd      t1, 24(s6)
    li      t2, DISCV5_EVENT_ADD_NODE
    sd      t2, 32(s6)
    sd      t0, (24 + DISCV5_EV_ADD_LEN)(s6)
    addi    a0, s6, 24
    mv      a1, t1
    call    app_dv_put
    j       1b
7:  call    app_line_start                  # boot node <n>: not an enr: record
    ADDRESS a0, app_m_boot
    li      a1, app_m_boot_len
    call    app_line_text
    mv      a0, s5
    call    app_line_u64
    ADDRESS a0, app_m_not_enr
    li      a1, app_m_not_enr_len
    call    app_line_text
    li      a0, APP_LOG_ERROR
    call    app_line_end
    j       1b
9:  LEAVE 16
END_FUNCTION app_boot_nodes

/*
 * L2: the network: a secp256k1 key, the libp2p state, the shell context with a TCP listener on
 * --port, and the boot nodes: a0 = 0, or 2 after a line on the standard error. s2 the config,
 * s3 the tries. Locals: L a size or a status, L+8 ShellParams, L+32 an Address, L+64 a ListenResult.
 */
/*
 * A new secp256k1 key at APP_KEY from fresh random bytes, below 2^255 and so below the order of
 * the curve (a zero key tries again, up to 4 times), and the anchor's node_id: keccak256 of its
 * point, x then y, in reverse byte order: a0 = 0, or a status. s3 the tries, s4 APP_KEY.
 * Locals: L the public key (40), L+48 the point (64), L+112 a ByteList of the point (88), L+200
 * the digest (32).
 */
LOCAL_FUNCTION app_key
    ENTER 240
    li      s3, 0
    ADDQ    s4, s1, APP_KEY
1:  ADDQ    a0, s1, APP_TICK
    CALL_GLOBAL libp2p_shell_clock
    mv      a0, s4
    ADDQ    a1, s1, (APP_TICK + LIBP2P_TICK_ENTROPY)
    li      a2, 32
    call    lantern_copy
    lbu     t0, 0(s4)
    andi    t0, t0, 0x7f
    sb      t0, 0(s4)
    mv      a0, s4
    addi    a1, sp, L
    CALL_GLOBAL crypto_secp256k1_public_key
    beqz    a0, 2f
    addi    s3, s3, 1
    li      t0, 4
    bltu    s3, t0, 1b
    LEAVE 240
2:  addi    a0, sp, L
    addi    a1, sp, L + 48
    CALL_GLOBAL crypto_secp256k1_decompress
    bnez    a0, 9f
    li      t0, 24 + 64                     # keccak256(x || y)
    sd      t0, (L + 112)(sp)
    li      t0, 24
    sd      t0, (L + 120)(sp)
    li      t0, 64
    sd      t0, (L + 128)(sp)
    addi    a0, sp, L + 136
    addi    a1, sp, L + 48
    li      a2, 64
    call    lantern_copy
    addi    a0, sp, L + 112
    addi    a1, sp, L + 200
    CALL_GLOBAL crypto_keccak256
    bnez    a0, 9f
    addi    t0, sp, L + 200                 # the NodeID: the digest's bytes in reverse order
    ADDQ    t1, s1, APP_ANCHOR + NodeAnchor_node_id + 31
    li      t2, 32
3:  lbu     t3, 0(t0)
    sb      t3, 0(t1)
    addi    t0, t0, 1
    addi    t1, t1, -1
    addi    t2, t2, -1
    bnez    t2, 3b
    li      a0, 0
9:  LEAVE 240
END_FUNCTION app_key

LOCAL_FUNCTION app_net
    ENTER 112
    li      a0, APP_P2P_CONFIG              # the config: the template, then the protocols
    li      a1, (LIBP2P_CFG_FIXED + 24 + APP_PROTOCOLS_MAX * LIBP2P_PROTO_SIZE)
    call    app_alloc
    beqz    a0, 97f
    mv      s2, a0
    ADDRESS a1, app_p2p_config
    li      a2, LIBP2P_CFG_FIXED
    call    lantern_copy
    ADDQ    a0, s2, LIBP2P_CFG_FIXED
    li      t0, (24 + APP_PROTOCOLS_MAX * LIBP2P_PROTO_SIZE)
    sd      t0, 0(a0)
    li      t0, 24
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    addi    a1, sp, L
    CALL_GLOBAL lantern_node_protocols
    bnez    a0, 96f
    ld      t0, L(sp)
    li      t1, (LIBP2P_CFG_FIXED + 24)
    sd      t1, 208(s2)                     # protocols, protocols_count
    sd      t0, 216(s2)
    li      t2, LIBP2P_PROTO_SIZE
    mul     t0, t0, t2
    add     t0, t0, t1
    sd      t0, 0(s2)
    addi    a0, s2, 16                      # the key of app_key
    ADDQ    a1, s1, APP_KEY
    li      a2, 32
    call    lantern_copy
    ADDQ    a0, s1, APP_TICK                # the DRBG's entropy, and the time
    CALL_GLOBAL libp2p_shell_clock
    addi    a0, s2, 48
    ADDQ    a1, s1, (APP_TICK + LIBP2P_TICK_ENTROPY)
    li      a2, 32
    call    lantern_copy
    LDQ     t0, s1, (APP_TICK + LIBP2P_TICK_NOW)
    sd      t0, 80(s2)
    mv      a0, s2                          # the libp2p state
    addi    a1, sp, L
    CALL_GLOBAL libp2p_state_size
    bnez    a0, 96f
    li      a0, APP_P2P
    ld      a1, L(sp)
    call    app_alloc
    beqz    a0, 97f
    mv      a1, a0
    mv      a0, s2
    CALL_GLOBAL libp2p_init
    bnez    a0, 96f
    ld      t0, 88(s2)                      # the shell: a slot for each connection, one for the execution engine, and the builder's
    addi    t0, t0, 1 + APP_BUILDER_SLOTS
    sd      t0, (L + 8)(sp)
    ld      t0, 160(s2)
    sd      t0, (L + 16)(sp)
    addi    a0, sp, (L + 8)
    addi    a1, sp, L
    CALL_GLOBAL libp2p_shell_size
    bnez    a0, 96f
    li      a0, APP_SHELL
    ld      a1, L(sp)
    call    app_alloc
    beqz    a0, 97f
    mv      a1, a0
    addi    a0, sp, (L + 8)
    CALL_GLOBAL libp2p_shell_init
    bnez    a0, 96f
    li      a0, APP_SHELL_EVENTS
    li      a1, APP_SHELL_EVENT_BYTES
    call    app_alloc
    beqz    a0, 97f
    li      t0, 24
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    ld      a1, 160(s2)                     # the engine's action: a SEND of up to send_window bytes
    addi    a1, a1, (24 + LIBP2P_ACT_SEND_DATA + 8)
    li      a0, APP_ENGINE_ACT
    call    app_alloc
    beqz    a0, 97f
    li      t0, 24
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    li      t0, 4                           # listen: TCP --port on every IPv4 address
    sd      t0, (L + 32)(sp)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_port)
    sd      t0, (L + 40)(sp)
    sd      zero, (L + 48)(sp)
    sd      zero, (L + 56)(sp)
    LDQ     a0, s1, APP_SHELL
    addi    a1, sp, (L + 32)
    addi    a2, sp, (L + 64)
    CALL_GLOBAL libp2p_shell_listen
    ld      t0, (L + 64)(sp)
    beqz    t0, 3f
    call    app_line_start                  # listen on TCP port <p>: error <n>
    ADDRESS a0, app_m_listen
    li      a1, app_m_listen_len
    call    app_line_text
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_port)
    call    app_line_u64
    ADDRESS a0, app_m_error
    li      a1, app_m_error_len
    call    app_line_text
    ld      a0, (L + 64)(sp)
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
    li      a0, 2
    LEAVE 112
3:  call    app_api_start
    bnez    a0, 99f
    call    app_dv_start
    bnez    a0, 99f
    call    app_boot_nodes
    call    app_line_start                  # listening on TCP port <p>
    ADDRESS a0, app_m_listening
    li      a1, app_m_listening_len
    call    app_line_text
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_port)
    call    app_line_u64
    li      a0, APP_LOG_INFO
    call    app_line_end
    li      a0, 0
99: LEAVE 112
96: mv      a2, a0                          # libp2p: status <n>
    ADDRESS a0, app_m_p2p
    li      a1, app_m_p2p_len
    call    app_fail_status
    LEAVE 112
97: call    app_no_memory
    LEAVE 112
END_FUNCTION app_net

/* L0: a0 = 0 and a1 = the u64 of the decimal digits a0 to a1, one or more; else a0 = 1. Uses t0-t3. */
LOCAL_FUNCTION app_number
    UNWIND_END_PROLOGUE
    bgeu    a0, a1, 9f
    li      t0, 0
    li      t3, 10
1:  bgeu    a0, a1, 8f
    lbu     t1, 0(a0)
    addi    a0, a0, 1
    addi    t1, t1, -0x30
    li      t2, 9
    bgtu    t1, t2, 9f
    mulhu   t2, t0, t3
    bnez    t2, 9f
    mul     t0, t0, t3
    add     t2, t0, t1
    bltu    t2, t0, 9f
    mv      t0, t2
    j       1b
8:  mv      a1, t0
    li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION app_number

/* L0: a0 = 0 and a1 = the IPv4 address of the bytes a0 to a1, its 4 bytes in order in the low bytes; else a0 = 1. Uses t0-t6. */
LOCAL_FUNCTION app_dotted
    UNWIND_END_PROLOGUE
    li      t0, 0                           # the address
    li      t1, 0                           # the numbers
    li      t2, 0                           # the shift of the next one
1:  li      t3, 0                           # a number
    li      t4, 0                           # its digits
2:  bgeu    a0, a1, 3f
    lbu     t5, 0(a0)
    li      t6, 0x2e                        # .
    beq     t5, t6, 3f
    addi    t5, t5, -0x30
    li      t6, 9
    bgtu    t5, t6, 9f
    addi    t4, t4, 1
    li      t6, 3
    bgtu    t4, t6, 9f
    slli    t6, t3, 2
    add     t3, t3, t6
    slli    t3, t3, 1
    add     t3, t3, t5
    addi    a0, a0, 1
    j       2b
3:  beqz    t4, 9f
    li      t6, 255
    bgtu    t3, t6, 9f
    sll     t3, t3, t2
    or      t0, t0, t3
    addi    t2, t2, 8
    addi    t1, t1, 1
    bgeu    a0, a1, 4f
    addi    a0, a0, 1                       # past the dot, to the next number
    li      t6, 4
    bgeu    t1, t6, 9f
    j       1b
4:  li      t6, 4
    bne     t1, t6, 9f
    mv      a1, t0
    li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION app_dotted

/*
 * L2: with --execution-endpoint, the engine: its Address, the anchor's engine_host and the
 * jwt_secret of --jwt-secret, and NODE_FLAG_ENGINE: a0 = 0, or 2 after a line on the standard
 * error. s2 the endpoint's bytes, s3 their count (then a digit), s4 the colon, s5 the secret's
 * next byte, s6 its end.
 */
LOCAL_FUNCTION app_engine_conf
    ENTER 0
    LDQ     s3, s1, (APP_OPTIONS + AppOptions_execution + 8)
    beqz    s3, 8f
    LDQ     s2, s1, (APP_OPTIONS + AppOptions_execution)
    ld      t0, APP_ARGS(s1)
    add     s2, t0, s2
    li      t0, NODE_ENGINE_HOST_MAX        # the Host of each request
    bgtu    s3, t0, 90f
    STQ     s3, s1, (APP_ANCHOR + NodeAnchor_engine_host_len)
    ADDQ    a0, s1, (APP_ANCHOR + NodeAnchor_engine_host)
    mv      a1, s2
    mv      a2, s3
    call    lantern_copy
    mv      s4, s3                          # the last colon
1:  beqz    s4, 90f
    addi    s4, s4, -1
    add     t0, s2, s4
    lbu     t0, 0(t0)
    li      t1, 0x3a
    bne     t0, t1, 1b
    add     a0, s2, s4                      # the port
    addi    a0, a0, 1
    add     a1, s2, s3
    call    app_number
    bnez    a0, 90f
    beqz    a1, 90f
    li      t0, 65535
    bgtu    a1, t0, 90f
    li      t0, 4
    STQ     t0, s1, APP_ENGINE_ADDR
    STQ     a1, s1, (APP_ENGINE_ADDR + 8)
    STQ     zero, s1, (APP_ENGINE_ADDR + 16)
    STQ     zero, s1, (APP_ENGINE_ADDR + 24)
    mv      a0, s2                          # the host: localhost, or an IPv4 address
    mv      a1, s4
    ADDRESS a2, app_localhost
    li      a3, 9
    call    app_name_is
    li      a1, 0x0100007f                  # 127.0.0.1
    bnez    a0, 2f
    mv      a0, s2
    add     a1, s2, s4
    call    app_dotted
    bnez    a0, 90f
2:  ADDQ    t0, s1, (APP_ENGINE_ADDR + 16)
    sw      a1, 0(t0)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_jwt_secret)  # the secret's path
    LDQ     t1, s1, (APP_OPTIONS + AppOptions_jwt_secret + 8)
    beqz    t1, 91f
    li      t2, APP_PATH_MAX
    bgtu    t1, t2, 91f
    ADDQ    t2, s1, APP_PATH
    sd      t1, 16(t2)
    addi    a0, t2, 24
    ld      t3, APP_ARGS(s1)
    add     a1, t3, t0
    mv      a2, t1
    call    lantern_copy
    call    app_read
    bnez    a0, 99f
    LDQ     t0, s1, (APP_FILE + 8)          # 64 hex digits, after 0x or not, with white space around them
    ld      t1, 16(t0)
    addi    s5, t0, 24
    add     s6, s5, t1
    call    app_space
    sub     t0, s6, s5
    li      t1, 2
    bltu    t0, t1, 3f
    lbu     t0, 0(s5)
    lbu     t1, 1(s5)
    li      t2, 0x30
    bne     t0, t2, 3f
    li      t2, 0x78
    bne     t1, t2, 3f
    addi    s5, s5, 2
3:  li      s4, 0
4:  li      t0, 32
    bgeu    s4, t0, 5f
    sub     t0, s6, s5
    li      t1, 2
    bltu    t0, t1, 92f
    lbu     a0, 0(s5)
    call    app_hex_digit
    mv      s3, a0
    lbu     a0, 1(s5)
    call    app_hex_digit
    or      t0, a0, s3
    li      t1, 15
    bgtu    t0, t1, 92f
    slli    t0, s3, 4
    or      t0, t0, a0
    ADDQ    t1, s1, (APP_ANCHOR + NodeAnchor_jwt_secret)
    add     t1, t1, s4
    sb      t0, 0(t1)
    addi    s5, s5, 2
    addi    s4, s4, 1
    j       4b
5:  call    app_space
    bne     s5, s6, 92f
    call    app_file_free
    LDQ     t0, s1, APP_FLAGS
    ori     t0, t0, NODE_FLAG_ENGINE
    STQ     t0, s1, APP_FLAGS
8:  li      a0, 0
    LEAVE 0
90: call    app_line_start                  # the endpoint's form
    ADDRESS a0, app_m_endpoint
    li      a1, app_m_endpoint_len
    call    app_line_text
    j       98f
91: call    app_line_start                  # no secret
    ADDRESS a0, app_m_jwt
    li      a1, app_m_jwt_len
    call    app_line_text
    j       98f
92: call    app_file_free                   # <path>: not 32 bytes in hex
    call    app_line_start
    call    app_line_path
    ADDRESS a0, app_m_hex
    li      a1, app_m_hex_len
    call    app_line_text
98: li      a0, APP_LOG_ERROR
    call    app_line_end
99: li      a0, 2
    LEAVE 0
END_FUNCTION app_engine_conf

/* L0: s5 moves past spaces, tabs, CR and LF, to at most s6. Uses t0, t1. */
LOCAL_FUNCTION app_space
    UNWIND_END_PROLOGUE
1:  bgeu    s5, s6, 2f
    lbu     t0, 0(s5)
    li      t1, 0x20
    beq     t0, t1, 3f
    li      t1, 9
    bltu    t0, t1, 2f
    li      t1, 13
    bgtu    t0, t1, 2f
3:  addi    s5, s5, 1
    j       1b
2:  ret
END_FUNCTION app_space

/* L0: a0 = the value of the hex digit a0, or 16 when it is not one. Uses t0, t1. */
LOCAL_FUNCTION app_hex_digit
    UNWIND_END_PROLOGUE
    addi    t0, a0, -0x30
    li      t1, 10
    bltu    t0, t1, 1f
    ori     t0, a0, 0x20
    addi    t0, t0, -0x61
    li      t1, 6
    bltu    t0, t1, 2f
    li      a0, 16
    ret
1:  mv      a0, t0
    ret
2:  addi    a0, t0, 10
    ret
END_FUNCTION app_hex_digit

/* L0: a0 = the Handle of the engine's connection: the slot after libp2p's, at its generation. Uses t0, a7. */
LOCAL_FUNCTION app_engine_handle
    UNWIND_END_PROLOGUE
    LDQ     t0, s1, APP_P2P_CONFIG
    ld      a0, 88(t0)                      # max_connections
    LDQ     t0, s1, APP_ENGINE_GEN
    slli    t0, t0, 32
    or      a0, a0, t0
    ret
END_FUNCTION app_engine_handle

/*
 * L1: one shell action, the a1 bytes in the ByteList at APP_ENGINE_ACT, through
 * libp2p_shell_perform; its results join the shell's events.
 */
LOCAL_FUNCTION app_engine_perform
    FRAME 0
    LDQ     t0, s1, APP_ENGINE_ACT
    sd      a1, 16(t0)
    LDQ     a0, s1, APP_SHELL
    mv      a1, t0
    LDQ     a2, s1, APP_SHELL_EVENTS
    CALL_GLOBAL libp2p_shell_perform
    UNFRAME 0
END_FUNCTION app_engine_perform

/*
 * L2: the next bytes of the request on the open connection, as far as the shell's send buffer has
 * room. s2 the action, s3 the bytes.
 */
LOCAL_FUNCTION app_engine_send
    ENTER 0
    LDQ     t0, s1, APP_ENGINE
    li      t1, 2
    bne     t0, t1, 9f
    LDQ     t0, s1, APP_ENGINE_LEN
    LDQ     t1, s1, APP_ENGINE_SENT
    sub     s3, t0, t1
    beqz    s3, 9f
    LDQ     t0, s1, APP_P2P_CONFIG
    ld      t0, 160(t0)                     # send_window
    LDQ     t1, s1, APP_ENGINE_FLIGHT
    bleu    t0, t1, 9f
    sub     t0, t0, t1
    bleu    s3, t0, 1f
    mv      s3, t0
1:  LDQ     s2, s1, APP_ENGINE_ACT          # SEND: connection, count, the bytes
    addi    s2, s2, 24
    addi    t0, s3, (LIBP2P_ACT_SEND_DATA + 7)
    andi    t0, t0, -8
    sd      t0, 0(s2)
    li      t0, LIBP2P_ACTION_SEND
    sd      t0, 8(s2)
    call    app_engine_handle
    sd      a0, LIBP2P_ACT_CONN(s2)
    sd      s3, (LIBP2P_ACT_CONN + 8)(s2)
    addi    a0, s2, LIBP2P_ACT_SEND_DATA
    LDQ     a1, s1, APP_ENGINE_OUT
    LDQ     t0, s1, APP_ENGINE_SENT
    add     a1, a1, t0
    mv      a2, s3
    call    lantern_copy
    LDQ     t0, s1, APP_ENGINE_SENT
    add     t0, t0, s3
    STQ     t0, s1, APP_ENGINE_SENT
    LDQ     t0, s1, APP_ENGINE_FLIGHT
    add     t0, t0, s3
    STQ     t0, s1, APP_ENGINE_FLIGHT
    mv      a0, s2
    ld      a1, 0(s2)
    call    app_engine_perform
9:  LEAVE 0
END_FUNCTION app_engine_send

/*
 * L2: the NODE_ACT_ENGINE a0: its request bytes wait in APP_ENGINE_OUT; they go on the open
 * connection, or after a DIAL of the engine's Address. s2 the ByteList, s3 the count.
 */
LOCAL_FUNCTION app_engine_request
    ENTER 0
    addi    s2, a0, 24
    ld      s3, 16(s2)
    LDQ     t0, s1, (APP_ENGINE_OUT + 8)    # room for the request
    bleu    s3, t0, 1f
    li      a0, APP_ENGINE_OUT
    call    app_unmap
    li      a0, APP_ENGINE_OUT
    mv      a1, s3
    call    app_alloc
    beqz    a0, 9f
1:  LDQ     a0, s1, APP_ENGINE_OUT
    ld      t0, 8(s2)
    add     a1, s2, t0
    mv      a2, s3
    call    lantern_copy
    STQ     s3, s1, APP_ENGINE_LEN
    STQ     zero, s1, APP_ENGINE_SENT
    LDQ     t0, s1, APP_ENGINE
    li      t1, 2
    bne     t0, t1, 2f
    call    app_engine_send
    LEAVE 0
2:  bnez    t0, 9f                          # no connection: a DIAL
    LDQ     t0, s1, APP_ENGINE_GEN
    addi    t0, t0, 1
    STQ     t0, s1, APP_ENGINE_GEN
    li      t0, 1
    STQ     t0, s1, APP_ENGINE
    STQ     zero, s1, APP_ENGINE_FLIGHT
    LDQ     s2, s1, APP_ENGINE_ACT
    addi    s2, s2, 24
    li      t0, LIBP2P_ACT_DIAL_SIZE
    sd      t0, 0(s2)
    li      t0, LIBP2P_ACTION_DIAL
    sd      t0, 8(s2)
    call    app_engine_handle
    sd      a0, LIBP2P_ACT_CONN(s2)
    addi    a0, s2, LIBP2P_ACT_DIAL_ADDR
    ADDQ    a1, s1, APP_ENGINE_ADDR
    li      a2, 32
    call    lantern_copy
    mv      a0, s2
    li      a1, LIBP2P_ACT_DIAL_SIZE
    call    app_engine_perform
9:  LEAVE 0
END_FUNCTION app_engine_request

/*
 * L2: a0 = 1 when the shell event a0 is of the engine's connection, which it then takes: CONNECTED
 * opens it, SENT frees its buffer, RECEIVED gives a NODE_EV_ENGINE of the bytes, DIAL_FAILED and
 * CLOSED end it with a NODE_EV_ENGINE of failure while the node waits for an answer; else 0.
 * s2 the event, s3 its kind. Locals: L the header of an event.
 */
LOCAL_FUNCTION app_engine_event
    ENTER 48
    mv      s2, a0
    ld      s3, 8(s2)
    li      t0, LIBP2P_EVENT_CONNECTED
    bltu    s3, t0, 8f
    li      t0, LIBP2P_EVENT_CLOSED
    bgtu    s3, t0, 8f
    LDQ     t0, s1, APP_ENGINE
    beqz    t0, 8f
    call    app_engine_handle
    ld      t0, LIBP2P_EV_CONN(s2)
    bne     t0, a0, 8f
    li      t0, LIBP2P_EVENT_CONNECTED
    bne     s3, t0, 1f
    li      t0, 2
    STQ     t0, s1, APP_ENGINE
    STQ     zero, s1, APP_ENGINE_FLIGHT
    li      t0, 1
    STQ     t0, s1, APP_ENGINE_DUE
    j       9f
1:  li      t0, LIBP2P_EVENT_SENT
    bne     s3, t0, 2f
    LDQ     t0, s1, APP_ENGINE_FLIGHT
    ld      t1, LIBP2P_EV_COUNT(s2)
    sub     t2, t0, t1
    bgeu    t0, t1, 11f
    li      t2, 0
11: STQ     t2, s1, APP_ENGINE_FLIGHT
    li      t0, 1
    STQ     t0, s1, APP_ENGINE_DUE
    j       9f
2:  li      t0, LIBP2P_EVENT_RECEIVED
    bne     s3, t0, 3f
    ld      t0, LIBP2P_EV_COUNT(s2)         # NODE_EV_ENGINE 0: size, kind, 0, a ByteList, the bytes
    addi    t1, t0, (48 + 7)
    andi    t1, t1, -8
    sd      t1, L(sp)
    li      t2, NODE_EV_ENGINE
    sd      t2, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    addi    t2, t1, -24
    sd      t2, (L + 24)(sp)
    li      t2, 24
    sd      t2, (L + 32)(sp)
    sd      t0, (L + 40)(sp)
    addi    a0, sp, L
    li      a1, 48
    call    app_event_put
    addi    a0, s2, LIBP2P_EV_DATA
    ld      a1, LIBP2P_EV_COUNT(s2)
    addi    a1, a1, 7
    andi    a1, a1, -8
    call    app_event_put
    j       9f
3:  STQ     zero, s1, APP_ENGINE            # DIAL_FAILED, CLOSED
    STQ     zero, s1, APP_ENGINE_LEN
    STQ     zero, s1, APP_ENGINE_SENT
    LDQ     t0, s1, APP_NODE
    LDQ     t0, t0, Node_engine_method
    beqz    t0, 9f
    li      t0, 24                          # NODE_EV_ENGINE 1
    sd      t0, L(sp)
    li      t0, NODE_EV_ENGINE
    sd      t0, (L + 8)(sp)
    li      t0, 1
    sd      t0, (L + 16)(sp)
    addi    a0, sp, L
    li      a1, 24
    call    app_event_put
9:  li      a0, 1
    LEAVE 48
8:  li      a0, 0
    LEAVE 48
END_FUNCTION app_engine_event

# L2: with --builder, the builder: its Address, the anchor's builder_host, and NODE_FLAG_BUILDER
# (app.md): a0 = 0, or 2 after a line on the standard error. s2 the endpoint's bytes, s3 their
# count, s4 the colon.
LOCAL_FUNCTION app_builder_conf
    ENTER 0
    LDQ     s3, s1, (APP_OPTIONS + AppOptions_builder + 8)
    beqz    s3, 8f
    LDQ     s2, s1, (APP_OPTIONS + AppOptions_builder)
    ld      t0, APP_ARGS(s1)
    add     s2, t0, s2
    li      t0, NODE_ENGINE_HOST_MAX        # the Host of each request
    bgtu    s3, t0, 90f
    STQ     s3, s1, (APP_ANCHOR + NodeAnchor_builder_host_len)
    ADDQ    a0, s1, (APP_ANCHOR + NodeAnchor_builder_host)
    mv      a1, s2
    mv      a2, s3
    call    lantern_copy
    mv      s4, s3                          # the last colon
1:  beqz    s4, 90f
    addi    s4, s4, -1
    add     t0, s2, s4
    lbu     t0, 0(t0)
    li      t1, 0x3a
    bne     t0, t1, 1b
    add     a0, s2, s4                      # the port
    addi    a0, a0, 1
    add     a1, s2, s3
    call    app_number
    bnez    a0, 90f
    beqz    a1, 90f
    li      t0, 65535
    bgtu    a1, t0, 90f
    ADDQ    t1, s1, APP_BUILDER
    li      t0, 4
    sd      t0, 0(t1)
    sd      a1, 8(t1)
    sd      zero, 16(t1)
    sd      zero, 24(t1)
    mv      a0, s2                          # the host: localhost, or an IPv4 address
    mv      a1, s4
    ADDRESS a2, app_localhost
    li      a3, 9
    call    app_name_is
    li      a1, 0x0100007f                  # 127.0.0.1
    bnez    a0, 2f
    mv      a0, s2
    add     a1, s2, s4
    call    app_dotted
    bnez    a0, 90f
2:  ADDQ    t0, s1, APP_BUILDER
    sw      a1, 16(t0)
    LDQ     t0, s1, APP_FLAGS
    li      t1, NODE_FLAG_BUILDER
    or      t0, t0, t1
    STQ     t0, s1, APP_FLAGS
8:  li      a0, 0
    LEAVE 0
90: call    app_line_start                  # the endpoint's form
    ADDRESS a0, app_m_builder
    li      a1, app_m_builder_len
    call    app_line_text
    li      a0, APP_LOG_ERROR
    call    app_line_end
    li      a0, 2
    LEAVE 0
END_FUNCTION app_builder_conf

# L0: a0 = the Handle of the connection of the builder slot a0 (a1 its fields): the slots after the engine's, at its generation. Uses t0, a7.
LOCAL_FUNCTION app_builder_handle
    UNWIND_END_PROLOGUE
    LDQ     t0, s1, APP_P2P_CONFIG
    ld      t0, 88(t0)                      # max_connections, then the engine's
    add     a0, a0, t0
    addi    a0, a0, 1
    ld      t0, AppBuilder_gen(a1)
    slli    t0, t0, 32
    or      a0, a0, t0
    ret
END_FUNCTION app_builder_handle

# L1: the NODE_EV_BUILDER of the failure of the call a0 joins the next step's events. Locals: the event.
LOCAL_FUNCTION app_builder_fail
    FRAME 32
    li      t0, 24
    sd      t0, 0(sp)
    li      t0, NODE_EV_BUILDER
    sd      t0, 8(sp)
    ori     a0, a0, 256
    sd      a0, 16(sp)
    mv      a0, sp
    li      a1, 24
    call    app_event_put
    UNFRAME 32
END_FUNCTION app_builder_fail

# L1: the NODE_EV_BUILDER of the slot fields a1 joins the next step's events: the call, with the
# bytes the builder sent, or with the failure bit when it sent none; the slot is free. Locals: the
# event's head, the fields.
LOCAL_FUNCTION app_builder_answer
    FRAME 64
    sd      a1, 48(sp)
    ld      t0, AppBuilder_got(a1)
    ld      a0, AppBuilder_call(a1)
    bnez    t0, 1f
    call    app_builder_fail                # none: the failure bit
    j       9f
1:  addi    t1, t0, 48 + 7                  # size, kind, the call, a ByteList, the bytes
    andi    t1, t1, -8
    sd      t1, 0(sp)
    li      t2, NODE_EV_BUILDER
    sd      t2, 8(sp)
    sd      a0, 16(sp)
    addi    t1, t1, -24
    sd      t1, 24(sp)
    li      t2, 24
    sd      t2, 32(sp)
    sd      t0, 40(sp)
    mv      a0, sp
    li      a1, 48
    call    app_event_put
    ld      a1, 48(sp)
    ld      a0, AppBuilder_buf(a1)
    ld      t0, AppBuilder_len(a1)
    add     a0, a0, t0
    ld      a1, AppBuilder_got(a1)
    addi    a1, a1, 7
    andi    a1, a1, -8
    call    app_event_put
9:  ld      a1, 48(sp)
    sd      zero, AppBuilder_state(a1)
    UNFRAME 64
END_FUNCTION app_builder_answer

# L2: the NODE_ACT_BUILDER a0 (app.md): a free slot takes its request and dials the builder; with
# none, or no memory, its NODE_EV_BUILDER of failure. s2 the action, s3 the slot, s4 its fields, s5
# the request's bytes, s6 their count.
LOCAL_FUNCTION app_builder_request
    ENTER 0
    mv      s2, a0
    ld      t0, (24 + 8)(s2)
    addi    s5, s2, 24
    add     s5, s5, t0
    ld      s6, (24 + 16)(s2)
    li      s3, 0
    ADDQ    s4, s1, APP_BUILDER_SLOT0
1:  li      t0, APP_BUILDER_SLOTS
    bgeu    s3, t0, 7f
    ld      t0, AppBuilder_state(s4)
    beqz    t0, 2f
    addi    s4, s4, APP_BUILDER_SLOT
    addi    s3, s3, 1
    j       1b
2:  ld      t0, 16(s2)                      # the call
    sd      t0, AppBuilder_call(s4)
    sd      zero, AppBuilder_sent(s4)
    sd      zero, AppBuilder_flight(s4)
    sd      zero, AppBuilder_got(s4)
    li      t0, APP_BUILDER_BUFFER + 8      # room for the request and the answer
    add     t0, t0, s6
    ld      t1, (AppBuilder_buf + 8)(s4)
    bgeu    t1, t0, 3f
    addi    a0, s4, AppBuilder_buf
    sub     a0, a0, s1
    call    app_unmap
    addi    a0, s4, AppBuilder_buf
    sub     a0, a0, s1
    li      a1, APP_BUILDER_BUFFER + 8
    add     a1, a1, s6
    call    app_alloc
    beqz    a0, 8f
3:  ld      a0, AppBuilder_buf(s4)
    mv      a1, s5
    mv      a2, s6
    call    lantern_copy
    sd      s6, AppBuilder_len(s4)
    ld      t0, AppBuilder_gen(s4)
    addi    t0, t0, 1
    sd      t0, AppBuilder_gen(s4)
    li      t0, 1
    sd      t0, AppBuilder_state(s4)
    LDQ     t0, s1, (APP_TICK + LIBP2P_TICK_NOW)
    sd      t0, AppBuilder_start(s4)
    LDQ     s2, s1, APP_ENGINE_ACT          # the DIAL
    addi    s2, s2, 24
    li      t0, LIBP2P_ACT_DIAL_SIZE
    sd      t0, 0(s2)
    li      t0, LIBP2P_ACTION_DIAL
    sd      t0, 8(s2)
    mv      a0, s3
    mv      a1, s4
    call    app_builder_handle
    sd      a0, LIBP2P_ACT_CONN(s2)
    addi    a0, s2, LIBP2P_ACT_DIAL_ADDR
    ADDQ    a1, s1, APP_BUILDER
    li      a2, 32
    call    lantern_copy
    mv      a0, s2
    li      a1, LIBP2P_ACT_DIAL_SIZE
    call    app_engine_perform
    LEAVE 0
7:  ld      a0, 16(s2)                      # no free slot: a failure
    call    app_builder_fail
    LEAVE 0
8:  sd      zero, AppBuilder_got(s4)        # no memory: a failure
    mv      a1, s4
    call    app_builder_answer
    LEAVE 0
END_FUNCTION app_builder_request

# L2: a0 = 1 when the shell event a0 is of a builder slot's connection, which it then takes:
# CONNECTED opens it, SENT frees its buffer, RECEIVED keeps the bytes (a full buffer closes it),
# DIAL_FAILED and CLOSED give the call's NODE_EV_BUILDER; else 0. An event of an older connection
# of a slot is dropped. s2 the event, s3 its kind, s4 the slot, s5 its fields.
LOCAL_FUNCTION app_builder_event
    ENTER 0
    mv      s2, a0
    ld      s3, 8(s2)
    li      t0, LIBP2P_EVENT_CONNECTED
    bltu    s3, t0, 8f
    li      t0, LIBP2P_EVENT_CLOSED
    bgtu    s3, t0, 8f
    ld      t1, LIBP2P_EV_CONN(s2)
    slli    s4, t1, 32                      # its index, past libp2p's and the engine's
    srli    s4, s4, 32
    LDQ     t0, s1, APP_P2P_CONFIG
    ld      t0, 88(t0)
    addi    t0, t0, 1
    bltu    s4, t0, 8f
    sub     s4, s4, t0
    li      t0, APP_BUILDER_SLOTS
    bgeu    s4, t0, 8f
    li      t0, APP_BUILDER_SLOT
    mul     t0, s4, t0
    ADDQ    s5, s1, APP_BUILDER_SLOT0
    add     s5, s5, t0
    ld      t0, AppBuilder_state(s5)
    beqz    t0, 9f
    srli    t1, t1, 32
    ld      t0, AppBuilder_gen(s5)
    bne     t0, t1, 9f
    li      t0, LIBP2P_EVENT_CONNECTED
    bne     s3, t0, 1f
    li      t0, 2
    sd      t0, AppBuilder_state(s5)
    j       9f
1:  li      t0, LIBP2P_EVENT_SENT
    bne     s3, t0, 2f
    ld      t0, AppBuilder_flight(s5)
    ld      t1, LIBP2P_EV_COUNT(s2)
    sub     t2, t0, t1
    bgeu    t0, t1, 11f
    li      t2, 0
11: sd      t2, AppBuilder_flight(s5)
    j       9f
2:  li      t0, LIBP2P_EVENT_RECEIVED
    bne     s3, t0, 3f
    ld      t0, (AppBuilder_buf + 8)(s5)    # the room after the request and the bytes so far
    ld      t1, AppBuilder_len(s5)
    sub     t0, t0, t1
    ld      t1, AppBuilder_got(s5)
    sub     t0, t0, t1
    addi    t0, t0, -8
    ld      a2, LIBP2P_EV_COUNT(s2)
    bleu    a2, t0, 21f
    mv      a2, t0                          # full: the rest goes, and the connection closes
    li      t0, 3
    sd      t0, AppBuilder_state(s5)
21: ld      a0, AppBuilder_buf(s5)
    ld      t0, AppBuilder_len(s5)
    add     a0, a0, t0
    ld      t0, AppBuilder_got(s5)
    add     a0, a0, t0
    add     t0, t0, a2
    sd      t0, AppBuilder_got(s5)
    addi    a1, s2, LIBP2P_EV_DATA
    call    lantern_copy
    j       9f
3:  mv      a1, s5                          # DIAL_FAILED, CLOSED: the answer
    call    app_builder_answer
9:  li      a0, 1
    LEAVE 0
8:  li      a0, 0
    LEAVE 0
END_FUNCTION app_builder_event

# L2: after the shell's events (app.md): for each slot, a call past APP_BUILDER_MS closes; an open
# one sends its request's next bytes as the shell's send buffer has room; one to close (state 3)
# gets its CLOSE, then waits for CLOSED (state 4). s2 the action, s3 the slot, s4 its fields, s5
# the bytes.
LOCAL_FUNCTION app_builder_due
    ENTER 0
    li      s3, 0
    ADDQ    s4, s1, APP_BUILDER_SLOT0
1:  li      t0, APP_BUILDER_SLOTS
    bgeu    s3, t0, 9f
    ld      t1, AppBuilder_state(s4)
    beqz    t1, 7f
    li      t0, 2
    bgtu    t1, t0, 3f
    LDQ     t2, s1, (APP_TICK + LIBP2P_TICK_NOW)    # the time limit
    ld      t3, AppBuilder_start(s4)
    sub     t2, t2, t3
    li      t3, APP_BUILDER_MS
    bltu    t2, t3, 2f
    li      t0, 3
    sd      t0, AppBuilder_state(s4)
    j       3f
2:  li      t0, 2
    bne     t1, t0, 7f
    ld      t0, AppBuilder_len(s4)          # open: the next bytes, as the send buffer has room
    ld      t1, AppBuilder_sent(s4)
    sub     s5, t0, t1
    beqz    s5, 7f
    LDQ     t0, s1, APP_P2P_CONFIG
    ld      t0, 160(t0)                     # send_window
    ld      t1, AppBuilder_flight(s4)
    bleu    t0, t1, 7f
    sub     t0, t0, t1
    bleu    s5, t0, 21f
    mv      s5, t0
21: LDQ     s2, s1, APP_ENGINE_ACT          # SEND: connection, count, the bytes
    addi    s2, s2, 24
    addi    t0, s5, LIBP2P_ACT_SEND_DATA + 7
    andi    t0, t0, -8
    sd      t0, 0(s2)
    li      t0, LIBP2P_ACTION_SEND
    sd      t0, 8(s2)
    mv      a0, s3
    mv      a1, s4
    call    app_builder_handle
    sd      a0, LIBP2P_ACT_CONN(s2)
    sd      s5, (LIBP2P_ACT_CONN + 8)(s2)
    addi    a0, s2, LIBP2P_ACT_SEND_DATA
    ld      a1, AppBuilder_buf(s4)
    ld      t0, AppBuilder_sent(s4)
    add     a1, a1, t0
    mv      a2, s5
    call    lantern_copy
    ld      t0, AppBuilder_sent(s4)
    add     t0, t0, s5
    sd      t0, AppBuilder_sent(s4)
    ld      t0, AppBuilder_flight(s4)
    add     t0, t0, s5
    sd      t0, AppBuilder_flight(s4)
    mv      a0, s2
    ld      a1, 0(s2)
    call    app_engine_perform
    j       7f
3:  ld      t1, AppBuilder_state(s4)        # to close: the CLOSE
    li      t0, 3
    bne     t1, t0, 7f
    li      t0, 4
    sd      t0, AppBuilder_state(s4)
    LDQ     s2, s1, APP_ENGINE_ACT
    addi    s2, s2, 24
    li      t0, LIBP2P_ACT_CLOSE_SIZE
    sd      t0, 0(s2)
    li      t0, LIBP2P_ACTION_CLOSE
    sd      t0, 8(s2)
    mv      a0, s3
    mv      a1, s4
    call    app_builder_handle
    sd      a0, LIBP2P_ACT_CONN(s2)
    mv      a0, s2
    li      a1, LIBP2P_ACT_CLOSE_SIZE
    call    app_engine_perform
7:  addi    s4, s4, APP_BUILDER_SLOT
    addi    s3, s3, 1
    j       1b
9:  LEAVE 0
END_FUNCTION app_builder_due

/* L1: the base64url text (RFC 4648 section 5, no padding) of the a1 bytes at a0 joins the log line. Locals: a0, a1, then 4 digits. */
LOCAL_FUNCTION app_line_base64url
    FRAME 48
    sd      a0, 0(sp)
    sd      a1, 8(sp)
1:  ld      a0, 0(sp)
    ld      a1, 8(sp)
    beqz    a1, 9f
    li      t0, 0                           # up to 3 bytes: 24 bits, from the top
    li      t1, 0
2:  li      t2, 3
    bgeu    t1, t2, 3f
    beqz    a1, 3f
    lbu     t2, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, -1
    slli    t3, t1, 3
    li      t4, 16
    sub     t3, t4, t3
    sll     t2, t2, t3
    or      t0, t0, t2
    addi    t1, t1, 1
    j       2b
3:  sd      a0, 0(sp)
    sd      a1, 8(sp)
    ADDRESS t4, app_base64url_digits        # 1 byte: 2 digits; 2: 3; 3: 4
    li      t2, 0
4:  li      t3, 4
    bgeu    t2, t3, 5f
    li      t3, 6
    mul     t3, t2, t3
    li      a2, 18
    sub     t3, a2, t3
    srl     t3, t0, t3
    andi    t3, t3, 63
    add     t3, t4, t3
    lbu     t3, 0(t3)
    addi    a2, sp, 24
    add     a2, a2, t2
    sb      t3, 0(a2)
    addi    t2, t2, 1
    j       4b
5:  addi    a0, sp, 24
    addi    a1, t1, 1
    call    app_line_text
    j       1b
9:  UNFRAME 48
END_FUNCTION app_line_base64url

/* L1: the a1 bytes of the event at a0 join the next discv5 step's events, while they have room. Locals: the new count. */
LOCAL_FUNCTION app_dv_put
    FRAME 16
    LDQ     t0, s1, APP_DV_EVENTS
    ld      t1, 16(t0)
    add     t2, t1, a1
    addi    t2, t2, 24
    ld      t3, 0(t0)
    bgtu    t2, t3, 9f
    sd      t2, 0(sp)
    mv      a2, a1
    mv      a1, a0
    addi    a0, t0, 24
    add     a0, a0, t1
    call    lantern_copy
    ld      t2, 0(sp)
    addi    t2, t2, -24
    LDQ     t0, s1, APP_DV_EVENTS
    sd      t2, 16(t0)
9:  UNFRAME 16
END_FUNCTION app_dv_put

/*
 * L2: discv5 with the key of libp2p: its state, with --enr-address and --port in the record, its UDP
 * socket on --port, and the record entry tcp: a0 = 0, or 2 after a line on the standard error.
 * Locals: L the Config (152), then an Address and a BindResult, and the tcp event.
 */
LOCAL_FUNCTION app_dv_start
    ENTER 256
    li      a0, APP_DV
    li      a1, DISCV5_STATE_SIZE
    call    app_alloc
    beqz    a0, 97f
    li      a0, APP_DV_SCRATCH
    li      a1, DISCV5_SCRATCH_SIZE
    call    app_alloc
    beqz    a0, 97f
    li      a0, APP_DV_EVENTS
    li      a1, APP_DV_EVENT_BYTES
    call    app_alloc
    beqz    a0, 97f
    li      t0, 24
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    li      a0, APP_DV_ACTIONS
    li      a1, (DISCV5_ACTIONS_BASE + 64 * DISCV5_ACTIONS_PER_EVENT)
    call    app_alloc
    beqz    a0, 97f
    li      a0, APP_DV_OUT
    li      a1, APP_DV_OUT_BYTES
    call    app_alloc
    beqz    a0, 97f
    li      t0, 24
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    addi    a0, sp, L                       # the config: key, seq, entropy, now, endpoint, limits
    li      a1, DISCV5_CFG_SIZE
    call    lantern_zero
    addi    a0, sp, (L + DISCV5_CFG_KEY)
    ADDQ    a1, s1, APP_KEY
    li      a2, 32
    call    lantern_copy
    addi    a0, sp, (L + DISCV5_CFG_SEQ)    # seq: the Unix time in ms, so a restart gives a later record
    CALL_GLOBAL lantern_shell_time_ms
    ADDQ    a0, s1, APP_TICK
    CALL_GLOBAL libp2p_shell_clock
    addi    a0, sp, (L + DISCV5_CFG_ENTROPY)
    ADDQ    a1, s1, (APP_TICK + LIBP2P_TICK_ENTROPY)
    li      a2, 32
    call    lantern_copy
    LDQ     t0, s1, (APP_TICK + LIBP2P_TICK_NOW)
    sd      t0, (L + DISCV5_CFG_NOW)(sp)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_port)
    sd      t0, (L + DISCV5_CFG_PORT)(sp)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_enr_address)
    beqz    t0, 1f
    li      t1, 4
    sd      t1, (L + DISCV5_CFG_FAMILY)(sp)
    sw      t0, (L + DISCV5_CFG_ADDRESS)(sp)
1:  li      t0, 2
    sd      t0, (L + DISCV5_CFG_BUCKET_IP_LIMIT)(sp)
    li      t0, 10
    sd      t0, (L + DISCV5_CFG_TABLE_IP_LIMIT)(sp)
    li      t0, 24
    sd      t0, (L + DISCV5_CFG_SUBNET4)(sp)
    li      t0, 64
    sd      t0, (L + DISCV5_CFG_SUBNET6)(sp)
    addi    a0, sp, L
    LDQ     a1, s1, APP_DV
    CALL_GLOBAL discv5_init
    bnez    a0, 96f
    li      t0, 4                           # its UDP socket
    sd      t0, (L + 152)(sp)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_port)
    sd      t0, (L + 160)(sp)
    sd      zero, (L + 168)(sp)
    sd      zero, (L + 176)(sp)
    LDQ     a0, s1, APP_SHELL
    addi    a1, sp, (L + 152)
    addi    a2, sp, (L + 184)
    CALL_GLOBAL libp2p_shell_bind
    ld      t0, (L + 184 + LIBP2P_BR_ERROR)(sp)
    bnez    t0, 95f
    ld      t0, (L + 184 + LIBP2P_BR_SOCKET)(sp)
    STQ     t0, s1, APP_DV_SOCKET
    STQ     zero, s1, APP_DV_WAKE
    addi    a0, sp, L                       # the entry tcp: --port, big endian
    li      a1, 56
    call    lantern_zero
    li      t0, 56
    sd      t0, L(sp)
    li      t0, DISCV5_EVENT_SET_ENTRY
    sd      t0, (L + 8)(sp)
    li      t0, 3
    sd      t0, (L + 16)(sp)
    li      t0, 0x706374                    # tcp
    sd      t0, (L + 24)(sp)
    li      t0, 2
    sd      t0, (L + 40)(sp)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_port)
    srli    t1, t0, 8
    sb      t1, (L + 48)(sp)
    sb      t0, (L + 49)(sp)
    addi    a0, sp, L
    li      a1, 56
    call    app_dv_put
    li      a0, 0
    LEAVE 256
95: call    app_line_start                  # bind UDP port <p>: error <n>
    ADDRESS a0, app_m_bind
    li      a1, app_m_bind_len
    call    app_line_text
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_port)
    call    app_line_u64
    ADDRESS a0, app_m_error
    li      a1, app_m_error_len
    call    app_line_text
    ld      a0, (L + 184 + LIBP2P_BR_ERROR)(sp)
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
    li      a0, 2
    LEAVE 256
96: mv      a2, a0                          # discv5: status <n>
    ADDRESS a0, app_m_discv5
    li      a1, app_m_discv5_len
    call    app_fail_status
    LEAVE 256
97: call    app_no_memory
    LEAVE 256
END_FUNCTION app_dv_start

/*
 * L2: a0 = 1 when the shell event a0 is a DATAGRAM of discv5's socket, which then joins the next
 * discv5 step as a DATAGRAM event (the sender as an Endpoint); else 0. s2 the event. Locals: L the header.
 */
LOCAL_FUNCTION app_dv_datagram
    ENTER 64
    mv      s2, a0
    ld      t0, 8(s2)
    li      t1, LIBP2P_EVENT_DATAGRAM
    bne     t0, t1, 8f
    ld      t0, LIBP2P_EV_DG_SOCKET(s2)
    LDQ     t1, s1, APP_DV_SOCKET
    bne     t0, t1, 8f
    ld      t2, LIBP2P_EV_DG_COUNT(s2)
    li      t0, APP_DV_DATAGRAM_MAX
    bgtu    t2, t0, 9f
    addi    t0, t2, (DISCV5_EV_DG_DATA + 7) # size, DATAGRAM, the Endpoint (port, family, address), len
    andi    t0, t0, -8
    sd      t0, L(sp)
    li      t0, DISCV5_EVENT_DATAGRAM
    sd      t0, (L + 8)(sp)
    addi    t3, s2, LIBP2P_EV_DG_ADDR
    ld      t0, LIBP2P_ADDR_PORT(t3)
    sd      t0, (L + 16)(sp)
    ld      t0, LIBP2P_ADDR_FAMILY(t3)
    sd      t0, (L + 24)(sp)
    ld      t0, LIBP2P_ADDR_IP(t3)
    sd      t0, (L + 32)(sp)
    ld      t0, (LIBP2P_ADDR_IP + 8)(t3)
    sd      t0, (L + 40)(sp)
    sd      t2, (L + 48)(sp)
    LDQ     t0, s1, APP_DV_EVENTS           # the header, then the bytes, if they fit
    ld      t1, 16(t0)
    ld      t3, L(sp)
    add     t3, t3, t1
    addi    t3, t3, 24
    ld      t4, 0(t0)
    bgtu    t3, t4, 9f
    addi    a0, sp, L
    li      a1, DISCV5_EV_DG_DATA
    call    app_dv_put
    ld      t0, L(sp)
    addi    a1, t0, -DISCV5_EV_DG_DATA
    addi    a0, s2, LIBP2P_EV_DG_DATA
    call    app_dv_put
9:  li      a0, 1
    LEAVE 64
8:  li      a0, 0
    LEAVE 64
END_FUNCTION app_dv_datagram

/*
 * L2: a discv5 step when it has events or its WAKEUP is due; then its actions: SEND as the shell's
 * SEND_DATAGRAM, NODE_FOUND as a NODE_EV_ENR of the next node step, RECORD as a log line, WAKEUP
 * as the next time. s2 the next action, s3 the end, s4 the datagrams, s5 an event count.
 * Locals: L the header of an event.
 */
LOCAL_FUNCTION app_discv5
    ENTER 64
    LDQ     t0, s1, APP_DV_EVENTS
    ld      t1, 16(t0)
    bnez    t1, 1f
    LDQ     t2, s1, (APP_TICK + LIBP2P_TICK_NOW)
    LDQ     t3, s1, APP_DV_WAKE
    bltu    t2, t3, 99f
1:  li      s5, 0                           # the action room for the events
    addi    t2, t0, 24
    add     t3, t2, t1
2:  bgeu    t2, t3, 3f
    ld      t4, 0(t2)
    add     t2, t2, t4
    addi    s5, s5, 1
    j       2b
3:  li      t0, DISCV5_ACTIONS_PER_EVENT
    mul     s5, s5, t0
    li      t0, DISCV5_ACTIONS_BASE
    add     s5, s5, t0
    LDQ     t0, s1, (APP_DV_ACTIONS + 8)
    bleu    s5, t0, 4f
    li      a0, APP_DV_ACTIONS
    call    app_unmap
    li      a0, APP_DV_ACTIONS
    mv      a1, s5
    call    app_alloc
    beqz    a0, 98f
4:  LDQ     t0, s1, (APP_TICK + LIBP2P_TICK_NOW)    # the Tick: now and fresh bytes
    STQ     t0, s1, APP_DV_TICK
    ADDQ    a0, s1, (APP_DV_TICK + 8)
    ADDQ    a1, s1, (APP_TICK + LIBP2P_TICK_ENTROPY)
    li      a2, 32
    call    lantern_copy
    LDQ     t0, s1, APP_DV_ACTIONS
    LDQ     t1, s1, (APP_DV_ACTIONS + 8)
    sd      t1, 0(t0)
    LDQ     t0, s1, APP_DV_SCRATCH
    LDQ     t1, s1, (APP_DV_SCRATCH + 8)
    sd      t1, 0(t0)
    LDQ     a0, s1, APP_DV
    ADDQ    a1, s1, APP_DV_TICK
    LDQ     a2, s1, APP_DV_EVENTS
    LDQ     a3, s1, APP_DV_SCRATCH
    LDQ     a4, s1, APP_DV_ACTIONS
    CALL_GLOBAL discv5_step
    LDQ     t0, s1, APP_DV_EVENTS
    sd      zero, 16(t0)
    beqz    a0, 5f
    mv      a2, a0                          # discv5: status <n>; its events are dropped
    ADDRESS a0, app_m_discv5
    li      a1, app_m_discv5_len
    call    app_fail_status
    LDQ     t0, s1, (APP_TICK + LIBP2P_TICK_NOW)
    addi    t0, t0, 1000
    STQ     t0, s1, APP_DV_WAKE
    j       99f
5:  LDQ     t0, s1, APP_DV_ACTIONS
    ld      t1, 8(t0)
    ld      t2, 16(t0)
    add     s2, t0, t1
    add     s3, s2, t2
    LDQ     s4, s1, APP_DV_OUT
6:  bgeu    s2, s3, 90f
    ld      t0, 8(s2)
    li      t1, DISCV5_ACTION_SEND
    bne     t0, t1, 7f
    LDQ     t2, s2, DISCV5_ACT_SEND_LEN     # SEND: a SEND_DATAGRAM of the socket
    addi    t3, t2, (LIBP2P_ACT_DG_DATA + 7)
    andi    t3, t3, -8
    ld      t4, 16(s4)
    add     t5, t4, t3
    addi    t5, t5, 24
    ld      t6, 0(s4)
    bgtu    t5, t6, 80f
    addi    a0, s4, 24
    add     a0, a0, t4
    addi    t5, t5, -24
    sd      t5, 16(s4)
    sd      t3, 0(a0)
    li      t4, LIBP2P_ACTION_SEND_DATAGRAM
    sd      t4, 8(a0)
    LDQ     t4, s1, APP_DV_SOCKET
    sd      t4, LIBP2P_ACT_DG_SOCKET(a0)
    LDQ     t4, s2, DISCV5_ACT_SEND_TO      # port, family
    LDQ     t5, s2, (DISCV5_ACT_SEND_TO + 8)
    addi    t6, a0, LIBP2P_ACT_DG_ADDR
    sd      t5, 0(t6)
    sd      t4, 8(t6)
    LDQ     t4, s2, (DISCV5_ACT_SEND_TO + 16)
    LDQ     t5, s2, (DISCV5_ACT_SEND_TO + 24)
    sd      t4, 16(t6)
    sd      t5, 24(t6)
    sd      t2, LIBP2P_ACT_DG_COUNT(a0)
    addi    a0, a0, LIBP2P_ACT_DG_DATA
    ADDQ    a1, s2, DISCV5_ACT_SEND_DATA
    mv      a2, t2
    call    lantern_copy
    j       80f
7:  li      t1, DISCV5_ACTION_NODE_FOUND
    bne     t0, t1, 71f
    LDQ     t2, s2, DISCV5_ACT_FOUND_LEN    # NODE_FOUND: NODE_EV_ENR with the record
    addi    t3, t2, (48 + 7)
    andi    t3, t3, -8
    sd      t3, L(sp)
    li      t4, NODE_EV_ENR
    sd      t4, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    addi    t4, t3, -24
    sd      t4, (L + 24)(sp)
    li      t4, 24
    sd      t4, (L + 32)(sp)
    sd      t2, (L + 40)(sp)
    addi    a0, sp, L
    li      a1, 48
    call    app_event_put
    ADDQ    a0, s2, DISCV5_ACT_FOUND_DATA
    ld      t0, L(sp)
    addi    a1, t0, -48
    call    app_event_put
    j       80f
71: li      t1, DISCV5_ACTION_RECORD
    bne     t0, t1, 72f
    call    app_line_clear                  # the view's enr: enr:<base64url>
    ADDRESS a0, app_t_enr
    li      a1, 4
    call    app_line_text
    ADDQ    a0, s2, DISCV5_ACT_RECORD_DATA
    LDQ     a1, s2, DISCV5_ACT_RECORD_LEN
    call    app_line_base64url
    LDQ     a0, s1, APP_IDENTITY
    addi    a0, a0, (48 + ApiIdentity_enr)
    li      a1, 512
    call    app_line_to
    call    app_identity_put                # the node's identity: the new record
    call    app_line_start                  # record enr:<base64url>
    ADDRESS a0, app_m_record
    li      a1, app_m_record_len
    call    app_line_text
    ADDQ    a0, s2, DISCV5_ACT_RECORD_DATA
    LDQ     a1, s2, DISCV5_ACT_RECORD_LEN
    call    app_line_base64url
    li      a0, APP_LOG_INFO
    call    app_line_end
    j       80f
72: li      t1, DISCV5_ACTION_WAKEUP
    bne     t0, t1, 80f
    LDQ     t0, s2, DISCV5_ACT_WAKEUP_AT
    STQ     t0, s1, APP_DV_WAKE
80: ld      t0, 0(s2)
    add     s2, s2, t0
    j       6b
90: LDQ     s4, s1, APP_DV_OUT              # the datagrams go out
    ld      t0, 16(s4)
    beqz    t0, 99f
    LDQ     a0, s1, APP_SHELL
    mv      a1, s4
    LDQ     a2, s1, APP_SHELL_EVENTS
    CALL_GLOBAL libp2p_shell_perform
    LDQ     s4, s1, APP_DV_OUT
    sd      zero, 16(s4)
    j       99f
98: LDQ     t0, s1, APP_DV_EVENTS
    sd      zero, 16(t0)
99: LEAVE 64
END_FUNCTION app_discv5

/*
 * L2: a0 = the base58btc text of the a1 bytes at a0 (at most 48), written at a2: a 1 for each
 * leading zero byte, then the digits. a3: a work area of 72 bytes. s2 the bytes, s3 their count,
 * s4 the text, s5 the work area, s6 the leading zero bytes.
 */
LOCAL_FUNCTION app_base58
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    mv      s4, a2
    mv      s5, a3
    li      s6, 0                           # the leading zero bytes
1:  bgeu    s6, s3, 2f
    add     t0, s2, s6
    lbu     t0, 0(t0)
    bnez    t0, 2f
    addi    s6, s6, 1
    j       1b
2:  li      t1, 0                           # the digits so far, least significant at s5 + 71
    mv      t2, s6
    li      a4, 58
3:  bgeu    t2, s3, 6f                      # each byte: digits * 256 + byte
    add     t3, s2, t2
    lbu     t3, 0(t3)
    li      t4, 0
4:  bgeu    t4, t1, 5f
    li      t0, 71
    sub     t0, t0, t4
    add     t0, s5, t0
    lbu     t5, 0(t0)
    slli    t5, t5, 8
    add     t3, t3, t5
    remu    t5, t3, a4
    divu    t3, t3, a4
    sb      t5, 0(t0)
    addi    t4, t4, 1
    j       4b
5:  beqz    t3, 51f
    remu    t5, t3, a4
    divu    t3, t3, a4
    li      t0, 71
    sub     t0, t0, t1
    add     t0, s5, t0
    sb      t5, 0(t0)
    addi    t1, t1, 1
    j       5b
51: addi    t2, t2, 1
    j       3b
6:  li      a0, 0                           # the text: the ones, then the digits
    ADDRESS t3, app_base58_digits
7:  beqz    s6, 8f
    lbu     t0, 0(t3)
    add     t4, s4, a0
    sb      t0, 0(t4)
    addi    a0, a0, 1
    addi    s6, s6, -1
    j       7b
8:  beqz    t1, 9f
    li      t0, 72
    sub     t0, t0, t1
    add     t0, s5, t0
    lbu     t0, 0(t0)
    add     t0, t3, t0
    lbu     t0, 0(t0)
    add     t4, s4, a0
    sb      t0, 0(t4)
    addi    a0, a0, 1
    addi    t1, t1, -1
    j       8b
9:  LEAVE 0
END_FUNCTION app_base58

/* L0: the log line becomes empty: the text helpers then build a text in it. Uses a7. */
LOCAL_FUNCTION app_line_clear
    UNWIND_END_PROLOGUE
    STQ     zero, s1, (APP_LINE + 16)
    ret
END_FUNCTION app_line_clear

/* L1: the bytes of the log line go to the text field at a0 of the view (its length, then its bytes, at most a1). */
LOCAL_FUNCTION app_line_to
    FRAME 0
    LDQ     a2, s1, (APP_LINE + 16)
    bleu    a2, a1, 1f
    mv      a2, a1
1:  sd      a2, 0(a0)
    addi    a0, a0, 8
    ADDQ    a1, s1, (APP_LINE + 24)
    call    lantern_copy
    UNFRAME 0
END_FUNCTION app_line_to

/* L1: the IPv4 address a0 (its bytes in order in the low bytes) joins the line in dotted decimal. Locals: the address, the count. */
LOCAL_FUNCTION app_line_ip4
    FRAME 16
    sd      a0, 0(sp)
    sd      zero, 8(sp)
1:  ld      a0, 0(sp)
    andi    a0, a0, 0xff
    call    app_line_u64
    ld      a0, 0(sp)
    ld      t0, 8(sp)
    addi    t0, t0, 1
    srli    a0, a0, 8
    sd      a0, 0(sp)
    sd      t0, 8(sp)
    li      t1, 4
    bgeu    t0, t1, 2f
    ADDRESS a0, app_t_dot
    li      a1, 1
    call    app_line_text
    j       1b
2:  UNFRAME 16
END_FUNCTION app_line_ip4

/* L1: a multiaddr /ip4/<--enr-address>/<a0: tcp or udp text>/<--port>/p2p/<peer id> to the view's field at a1, or length 0 with no --enr-address. Locals: a0, a1. */
LOCAL_FUNCTION app_multiaddr
    FRAME 16
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_enr_address)
    bnez    t0, 1f
    sd      zero, 0(a1)
    j       9f
1:  call    app_line_clear
    ADDRESS a0, app_t_ip4
    li      a1, 5
    call    app_line_text
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_enr_address)
    call    app_line_ip4
    ld      a0, 0(sp)
    li      a1, 5
    call    app_line_text
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_port)
    call    app_line_u64
    ADDRESS a0, app_t_p2p
    li      a1, 5
    call    app_line_text
    LDQ     t0, s1, APP_IDENTITY
    addi    a0, t0, (48 + ApiIdentity_peer_id + 8)
    ld      a1, (48 + ApiIdentity_peer_id)(t0)
    call    app_line_text
    ld      a0, 8(sp)
    li      a1, 128
    call    app_line_to
9:  UNFRAME 16
END_FUNCTION app_multiaddr

/*
 * L2: the Beacon API: a shell context with --http-max-connections slots that listens on
 * --http-address and --http-port, the slots' buffers, and the identity's texts: the peer id, the
 * addresses and the version, in a NODE_EV_API_IDENTITY: a0 = 0, or 2 after a line on the standard
 * error. Locals: L ShellParams or an Address, L+32 a ListenResult or the public key, L+80 the peer
 * id's multihash, L+128 base58's work area.
 */
LOCAL_FUNCTION app_api_start
    ENTER 208
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_http_max_connections)
    sd      t0, L(sp)
    li      t0, APP_API_SEND_WINDOW
    sd      t0, (L + 8)(sp)
    addi    a0, sp, L
    addi    a1, sp, (L + 32)
    CALL_GLOBAL libp2p_shell_size
    bnez    a0, 97f
    li      a0, APP_API_SHELL
    ld      a1, (L + 32)(sp)
    call    app_alloc
    beqz    a0, 97f
    mv      a1, a0
    addi    a0, sp, L
    CALL_GLOBAL libp2p_shell_init
    bnez    a0, 97f
    li      a0, APP_API_EVENTS
    li      a1, APP_API_EVENT_BYTES
    call    app_alloc
    beqz    a0, 97f
    li      t0, 24
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    li      a0, APP_API_ACT
    li      a1, APP_API_ACT_BYTES
    call    app_alloc
    beqz    a0, 97f
    li      t0, 24
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    li      a0, APP_API_EVENT
    li      a1, (48 + HTTP_REQUEST_FIXED + APP_API_BUFFER + 64)
    call    app_alloc
    beqz    a0, 97f
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_http_max_connections)
    li      t1, APP_API_SLOT_BYTES
    mul     a1, t0, t1
    li      a0, APP_API_BUF
    call    app_alloc
    beqz    a0, 97f
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_http_max_connections)
    li      a1, APP_API_SLOT                # APP_API_SLOT bytes each
    mul     a1, t0, a1
    li      a0, APP_API_SLOTS
    call    app_alloc
    beqz    a0, 97f
    sd      zero, 0(a0)
    li      a0, APP_IDENTITY
    li      a1, (48 + API_IDENTITY_SIZE)
    call    app_alloc
    beqz    a0, 97f
    li      t0, 4                           # listen: TCP --http-address, --http-port
    sd      t0, L(sp)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_http_port)
    sd      t0, (L + 8)(sp)
    LDQ     t0, s1, (APP_OPTIONS + AppOptions_http_address)
    sd      t0, (L + 16)(sp)
    sd      zero, (L + 24)(sp)
    LDQ     a0, s1, APP_API_SHELL
    addi    a1, sp, L
    addi    a2, sp, (L + 32)
    CALL_GLOBAL libp2p_shell_listen
    ld      t0, (L + 32)(sp)
    bnez    t0, 96f
    ADDQ    a0, s1, APP_KEY                 # the peer id: base58btc of the identity multihash of the key
    addi    a1, sp, (L + 32)
    CALL_GLOBAL crypto_secp256k1_public_key
    bnez    a0, 97f
    li      t0, 0x0000211202082500
    sd      t0, (L + 80)(sp)
    addi    a0, sp, (L + 86)
    addi    a1, sp, (L + 32)
    li      a2, 33
    call    lantern_copy
    addi    a0, sp, (L + 80)
    li      a1, 39
    LDQ     a2, s1, APP_IDENTITY
    addi    a2, a2, (48 + ApiIdentity_peer_id + 8)
    addi    a3, sp, (L + 128)
    call    app_base58
    LDQ     t0, s1, APP_IDENTITY
    sd      a0, (48 + ApiIdentity_peer_id)(t0)
    LDQ     a0, s1, APP_IDENTITY            # the version
    addi    a0, a0, (48 + ApiIdentity_version)
    li      t0, app_version_text_len
    sd      t0, 0(a0)
    addi    a0, a0, 8
    ADDRESS a1, app_version_text
    li      a2, app_version_text_len
    call    lantern_copy
    ADDRESS a0, app_t_tcp                   # the addresses
    LDQ     a1, s1, APP_IDENTITY
    addi    a1, a1, (48 + ApiIdentity_p2p_address)
    call    app_multiaddr
    ADDRESS a0, app_t_udp
    LDQ     a1, s1, APP_IDENTITY
    addi    a1, a1, (48 + ApiIdentity_discovery_address)
    call    app_multiaddr
    call    app_identity_put
    call    app_line_start                  # Beacon API on TCP <address>:<port>, peer id <id>
    ADDRESS a0, app_m_api
    li      a1, app_m_api_len
    call    app_line_text
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_http_address)
    call    app_line_ip4
    ADDRESS a0, app_t_colon
    li      a1, 1
    call    app_line_text
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_http_port)
    call    app_line_u64
    ADDRESS a0, app_m_peer_id
    li      a1, app_m_peer_id_len
    call    app_line_text
    LDQ     t0, s1, APP_IDENTITY
    addi    a0, t0, (48 + ApiIdentity_peer_id + 8)
    ld      a1, (48 + ApiIdentity_peer_id)(t0)
    call    app_line_text
    li      a0, APP_LOG_INFO
    call    app_line_end
    li      a0, 0
    LEAVE 208
96: call    app_line_start                  # listen on TCP port <p>: error <n>
    ADDRESS a0, app_m_listen
    li      a1, app_m_listen_len
    call    app_line_text
    LDQ     a0, s1, (APP_OPTIONS + AppOptions_http_port)
    call    app_line_u64
    ADDRESS a0, app_m_error
    li      a1, app_m_error_len
    call    app_line_text
    ld      a0, (L + 32)(sp)
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
    li      a0, 2
    LEAVE 208
97: call    app_no_memory
    LEAVE 208
END_FUNCTION app_api_start

/* L1: the identity's texts go to the next step in a NODE_EV_API_IDENTITY. */
LOCAL_FUNCTION app_identity_put
    FRAME 0
    LDQ     a0, s1, APP_IDENTITY
    li      t0, (48 + API_IDENTITY_SIZE)
    sd      t0, 0(a0)
    li      t0, NODE_EV_API_IDENTITY
    sd      t0, 8(a0)
    sd      zero, 16(a0)
    li      t0, (24 + API_IDENTITY_SIZE)
    sd      t0, 24(a0)
    li      t0, 24
    sd      t0, 32(a0)
    li      t0, API_IDENTITY_SIZE
    sd      t0, 40(a0)
    li      a1, (48 + API_IDENTITY_SIZE)
    call    app_event_put
    UNFRAME 0
END_FUNCTION app_identity_put

/* L0: a0 = the slot of the connection a0, while it is open at that generation, else 0. Uses t0-t2, a7. */
LOCAL_FUNCTION app_api_slot
    UNWIND_END_PROLOGUE
    slli    t0, a0, 32
    srli    t0, t0, 32
    LDQ     t1, s1, (APP_OPTIONS + AppOptions_http_max_connections)
    bgeu    t0, t1, 9f
    LDQ     t1, s1, APP_API_SLOTS
    li      t2, APP_API_SLOT
    mul     t0, t0, t2
    add     t1, t1, t0
    ld      t2, 8(t1)
    beqz    t2, 9f
    ld      t2, 0(t1)
    srli    t0, a0, 32
    bne     t2, t0, 9f
    mv      a0, t1
    ret
9:  li      a0, 0
    ret
END_FUNCTION app_api_slot

/* L1: the Beacon API's shell actions go out; their results come at the next poll. */
LOCAL_FUNCTION app_api_flush
    FRAME 0
    LDQ     a1, s1, APP_API_ACT
    beqz    a1, 9f
    ld      t0, 16(a1)
    beqz    t0, 9f
    LDQ     a0, s1, APP_API_SHELL
    LDQ     a2, s1, APP_API_EVENTS
    CALL_GLOBAL libp2p_shell_perform
    LDQ     t0, s1, APP_API_ACT
    sd      zero, 16(t0)
9:  UNFRAME 0
END_FUNCTION app_api_flush

/* L1: a0 = room for a shell action of a0 bytes at the end of the Beacon API's actions, its bytes counted, after a flush when they are full; 0 when it never fits. Locals: a0. */
LOCAL_FUNCTION app_api_room
    FRAME 16
    sd      a0, 0(sp)
    LDQ     t0, s1, APP_API_ACT
    ld      t1, 0(t0)
    addi    t1, t1, -24
    bgtu    a0, t1, 8f
    ld      t2, 16(t0)
    add     t2, t2, a0
    bleu    t2, t1, 1f
    call    app_api_flush
1:  LDQ     t0, s1, APP_API_ACT
    ld      t1, 16(t0)
    ld      t2, 0(sp)
    add     t2, t1, t2
    sd      t2, 16(t0)
    addi    a0, t0, 24
    add     a0, a0, t1
    UNFRAME 16
8:  li      a0, 0
    UNFRAME 16
END_FUNCTION app_api_room

/* L1: a CLOSE of the connection a0, while it is open; its slot waits for the shell's CLOSED. Locals: a0. */
LOCAL_FUNCTION app_api_close
    FRAME 16
    sd      a0, 0(sp)
    call    app_api_slot
    beqz    a0, 9f
    li      t0, APP_API_CLOSING
    sd      t0, 8(a0)
    li      a0, LIBP2P_ACT_CLOSE_SIZE
    call    app_api_room
    beqz    a0, 9f
    li      t0, LIBP2P_ACT_CLOSE_SIZE
    sd      t0, 0(a0)
    li      t0, LIBP2P_ACTION_CLOSE
    sd      t0, 8(a0)
    ld      t0, 0(sp)
    sd      t0, LIBP2P_ACT_CONN(a0)
9:  UNFRAME 16
END_FUNCTION app_api_close

/*
 * L2: the slot a0, when it waits for no answer: lantern_http_request of its bytes, then a
 * NODE_EV_API of the request, or of a fault's status (413 for a full buffer with no whole
 * request); the request's bytes leave the buffer, and the slot waits for the answer. s4 the slot,
 * s5 its ByteList, s6 its bytes, s7 its index, s8 the event, s9 the HttpRequest's room. Locals:
 * L HttpLimits.
 */
LOCAL_FUNCTION app_api_read
    ENTER 16
    mv      s7, a0
    LDQ     s4, s1, APP_API_SLOTS
    li      t0, APP_API_SLOT
    mul     t0, s7, t0
    add     s4, s4, t0
    ld      t0, 8(s4)
    li      t1, APP_API_READING
    bne     t0, t1, 99f
    LDQ     s5, s1, APP_API_BUF
    li      t0, APP_API_SLOT_BYTES
    mul     t1, s7, t0
    add     s5, s5, t1
    ld      s6, 16(s4)
    beqz    s6, 99f
    sd      t0, 0(s5)
    li      t1, 24
    sd      t1, 8(s5)
    sd      s6, 16(s5)
    li      t0, APP_API_HEAD_MAX
    sd      t0, L(sp)
    li      t0, APP_API_BODY_MAX
    sd      t0, (L + 8)(sp)
    LDQ     s8, s1, APP_API_EVENT
    addi    s9, s6, (HTTP_REQUEST_FIXED + 48 + 7)
    andi    s9, s9, -8
    sd      s9, 48(s8)
    mv      a0, s5
    addi    a1, sp, L
    addi    a2, s8, 48
    CALL_GLOBAL lantern_http_request
    beqz    a0, 4f
    li      t0, LANTERN_INVALID_HTTP
    beq     a0, t0, 3f
    li      t1, 400                         # no room: a request too large to read
    li      t0, LANTERN_HTTP_MORE
    bne     a0, t0, 2f
    li      t0, APP_API_BUFFER              # more to come, unless the buffer is full
    bltu    s6, t0, 99f
    li      t1, 413
2:  sd      t1, (48 + HttpRequest_status)(s8)
3:  li      s9, HTTP_REQUEST_FIXED          # a fault: the fixed part, with its status; the bytes go
    sd      s9, 48(s8)
    sd      zero, 16(s4)
    j       5f
4:  ld      t0, (48 + HttpRequest_used)(s8) # the request's bytes leave the buffer
    sub     a2, s6, t0
    sd      a2, 16(s4)
    addi    a0, s5, 24
    add     a1, a0, t0
    call    lantern_copy
5:  addi    t0, s9, 48                      # the event: size, kind, connection, a ByteList of the HttpRequest
    sd      t0, 0(s8)
    li      t0, NODE_EV_API
    sd      t0, 8(s8)
    ld      t0, 0(s4)
    slli    t0, t0, 32
    or      t0, t0, s7
    sd      t0, 16(s8)
    addi    t0, s9, 24
    sd      t0, 24(s8)
    li      t0, 24
    sd      t0, 32(s8)
    sd      s9, 40(s8)
    mv      a0, s8
    addi    a1, s9, 48
    call    app_event_put
    li      t0, APP_API_ANSWERING
    sd      t0, 8(s4)
99: LEAVE 16
END_FUNCTION app_api_read

/*
 * L2: the NODE_ACT_API_SEND or NODE_ACT_API_CLOSE a0 of the node: a SEND of its bytes, or the
 * close, on its connection; after the bytes with last 1, the slot's next request. An action of a
 * connection no longer open goes. s2 the action, s4 the slot, s5 the shell action.
 */
LOCAL_FUNCTION app_api_action
    ENTER 0
    mv      s2, a0
    ld      a0, 16(s2)
    call    app_api_slot
    beqz    a0, 99f
    mv      s4, a0
    ld      t0, 8(s4)
    li      t1, APP_API_CLOSING             # closing or draining: no more actions
    bgeu    t0, t1, 99f
    ld      t0, 8(s2)
    li      t1, NODE_ACT_API_CLOSE
    bne     t0, t1, 1f
    ld      t0, 32(s4)                      # CLOSE: at once with no bytes in flight, else after them
    bnez    t0, 2f
    ld      a0, 16(s2)
    call    app_api_close
    j       99f
2:  li      t0, APP_API_DRAINING
    sd      t0, 8(s4)
    LDQ     t0, s1, (APP_TICK + LIBP2P_TICK_NOW)
    sd      t0, 24(s4)
    j       99f
1:  ld      t0, 48(s2)                      # SEND: size, kind, connection, count, the bytes
    addi    a0, t0, (LIBP2P_ACT_SEND_DATA + 7)
    andi    a0, a0, -8
    call    app_api_room
    beqz    a0, 98f
    mv      s5, a0
    ld      t0, 48(s2)
    addi    t1, t0, (LIBP2P_ACT_SEND_DATA + 7)
    andi    t1, t1, -8
    sd      t1, 0(s5)
    li      t1, LIBP2P_ACTION_SEND
    sd      t1, 8(s5)
    ld      t1, 16(s2)
    sd      t1, LIBP2P_ACT_CONN(s5)
    sd      t0, (LIBP2P_ACT_CONN + 8)(s5)
    addi    a0, s5, LIBP2P_ACT_SEND_DATA
    addi    a1, s2, 56
    mv      a2, t0
    call    lantern_copy
    ld      t0, 32(s4)                      # its bytes are in flight
    ld      t1, 48(s2)
    add     t0, t0, t1
    sd      t0, 32(s4)
    ld      t0, 24(s2)                      # last: the slot reads its next request
    bnez    t0, 97f
    li      t0, 1                           # else an API_SENT is owed
    sd      t0, 40(s4)
    mv      a0, s4
    ld      a1, 16(s2)
    call    app_api_due
    j       99f
97:
    li      t0, APP_API_READING
    sd      t0, 8(s4)
    LDQ     t0, s1, (APP_TICK + LIBP2P_TICK_NOW)
    sd      t0, 24(s4)
    ld      a0, 16(s2)
    slli    a0, a0, 32
    srli    a0, a0, 32
    call    app_api_read
    j       99f
98: ld      a0, 16(s2)                      # bytes that never fit: the connection closes
    call    app_api_close
99: LEAVE 0
END_FUNCTION app_api_action

/* L1: a NODE_EV_API_SENT or NODE_EV_API_CLOSED (a0) of the connection a1 for the next step. Locals: the event. */
LOCAL_FUNCTION app_api_note
    FRAME 32
    li      t0, 24
    sd      t0, 0(sp)
    sd      a0, 8(sp)
    sd      a1, 16(sp)
    mv      a0, sp
    li      a1, 24
    call    app_event_put
    UNFRAME 32
END_FUNCTION app_api_note

/* L1: the slot a0 of the connection a1, owing an API_SENT: it goes once the slot's bytes in flight are at most APP_API_SEND_WINDOW - NODE_API_CHUNK. */
LOCAL_FUNCTION app_api_due
    FRAME 0
    ld      t0, 40(a0)
    beqz    t0, 9f
    ld      t0, 32(a0)
    li      t1, APP_API_SEND_WINDOW - NODE_API_CHUNK
    bgtu    t0, t1, 9f
    sd      zero, 40(a0)
    li      a0, NODE_EV_API_SENT
    call    app_api_note
9:  UNFRAME 0
END_FUNCTION app_api_due

/*
 * L2: the NODE_ACT_STATE_BYTES a0: lantern_node_state_bytes of the fork of the state's slot in new
 * memory, kept as the bytes of the new id; with no memory, a ByteList of no bytes. s2 the action,
 * s3 the state's entry, s4 the bytes' size, s5 the memory. Locals: L a ByteList, L+24 the size,
 * L+32 the fork.
 */
LOCAL_FUNCTION app_state_bytes
    ENTER 48
    mv      s2, a0
    ld      a0, 16(s2)
    call    app_buf_find
    beqz    a0, 9f
    mv      s3, a0
    ld      t0, 8(s3)
    ld      a0, NODE_STATE_SLOT(t0)
    ADDQ    a1, s1, APP_CONFIG
    call    app_fork
    sd      a0, (L + 32)(sp)
    li      t0, 24                          # the size first
    sd      t0, L(sp)
    sd      zero, (L + 24)(sp)
    mv      t6, a0
    ld      a0, 8(s3)
    SCRATCH a1
    addi    a2, sp, L
    addi    a3, sp, L + 24
    FORK_CALL node_state_bytes
    ld      s4, (L + 24)(sp)
    li      t0, 24
    bleu    s4, t0, 8f
    mv      a0, s4
    call    app_map
    beqz    a0, 8f
    mv      s5, a0
    sd      s4, 0(s5)
    ld      t6, (L + 32)(sp)
    ld      a0, 8(s3)
    SCRATCH a1
    mv      a2, s5
    addi    a3, sp, L + 24
    FORK_CALL node_state_bytes
    beqz    a0, 7f
    li      t0, 24                          # no bytes
    sd      t0, 8(s5)
    sd      zero, 16(s5)
7:  ld      a0, 24(s2)
    mv      a1, s5
    mv      a2, s4
    call    app_buf_add
    LEAVE 48
8:  li      t0, 24                          # no memory: a ByteList of no bytes
    sd      t0, L(sp)
    sd      t0, (L + 8)(sp)
    sd      zero, (L + 16)(sp)
    addi    a0, sp, L
    li      a1, 24
    call    app_dup
    beqz    a0, 9f
    mv      a1, a0
    ld      a0, 24(s2)
    li      a2, 24
    call    app_buf_add
9:  LEAVE 48
END_FUNCTION app_state_bytes

/*
 * L2: the Beacon API's sockets, without waiting: ACCEPTED takes a free slot (ADOPT) or a REFUSE,
 * RECEIVED joins its slot's buffer and the slot reads it, SENT ends a slot's draining once its bytes
 * are out, CLOSED frees the slot; a slot that waits for no answer with no bytes for
 * APP_API_IDLE_MS closes, as does a draining one; then the shell actions go out. s2 the
 * next event, s3 the end, s4 a slot, s5 an index, s6 the connection. Locals: L the wait.
 */
LOCAL_FUNCTION app_api_poll
    ENTER 16
    sd      zero, L(sp)
    LDQ     a0, s1, APP_API_SHELL
    addi    a1, sp, L
    LDQ     a2, s1, APP_API_EVENTS
    CALL_GLOBAL libp2p_shell_wait
    LDQ     t0, s1, APP_API_EVENTS
    ld      t1, 8(t0)
    ld      t2, 16(t0)
    add     s2, t0, t1
    add     s3, s2, t2
1:  bgeu    s2, s3, 80f
    ld      t0, 8(s2)
    li      t1, LIBP2P_EVENT_ACCEPTED
    bne     t0, t1, 3f
    LDQ     s4, s1, APP_API_SLOTS           # ACCEPTED: a free slot, or REFUSE
    li      s5, 0
2:  LDQ     t0, s1, (APP_OPTIONS + AppOptions_http_max_connections)
    bgeu    s5, t0, 21f
    ld      t0, 8(s4)
    beqz    t0, 22f
    addi    s4, s4, APP_API_SLOT
    addi    s5, s5, 1
    j       2b
21: li      a0, LIBP2P_ACT_REFUSE_SIZE
    call    app_api_room
    beqz    a0, 79f
    li      t0, LIBP2P_ACT_REFUSE_SIZE
    sd      t0, 0(a0)
    li      t0, LIBP2P_ACTION_REFUSE
    sd      t0, 8(a0)
    ld      t0, LIBP2P_EV_TOKEN(s2)
    sd      t0, LIBP2P_ACT_TOKEN(a0)
    j       79f
22: ld      t0, 0(s4)                       # a new generation, reading, no bytes, the time now
    addi    t0, t0, 1
    sd      t0, 0(s4)
    li      t1, APP_API_READING
    sd      t1, 8(s4)
    sd      zero, 16(s4)
    LDQ     t1, s1, (APP_TICK + LIBP2P_TICK_NOW)
    sd      t1, 24(s4)
    sd      zero, 32(s4)                    # no bytes in flight, no API_SENT owed
    sd      zero, 40(s4)
    slli    s6, t0, 32
    or      s6, s6, s5
    li      a0, LIBP2P_ACT_ADOPT_SIZE
    call    app_api_room
    beqz    a0, 79f
    li      t0, LIBP2P_ACT_ADOPT_SIZE
    sd      t0, 0(a0)
    li      t0, LIBP2P_ACTION_ADOPT
    sd      t0, 8(a0)
    ld      t0, LIBP2P_EV_TOKEN(s2)
    sd      t0, LIBP2P_ACT_TOKEN(a0)
    sd      s6, (LIBP2P_ACT_TOKEN + 8)(a0)
    j       79f
3:  li      t1, LIBP2P_EVENT_SENT           # SENT: fewer bytes in flight, and an API_SENT once owed
    bne     t0, t1, 30f
    ld      s6, LIBP2P_EV_CONN(s2)
    mv      a0, s6
    call    app_api_slot
    beqz    a0, 79f
    ld      t0, 32(a0)
    ld      t1, LIBP2P_EV_COUNT(s2)
    sub     t2, t0, t1
    bgeu    t0, t1, 301f
    li      t2, 0
301: sd     t2, 32(a0)
    ld      t0, 8(a0)
    li      t1, APP_API_DRAINING
    bne     t0, t1, 302f
    LDQ     t1, s1, (APP_TICK + LIBP2P_TICK_NOW)    # draining: bytes went out; with none left, the close
    sd      t1, 24(a0)
    bnez    t2, 79f
    mv      a0, s6
    call    app_api_close
    j       79f
302: mv     a1, s6
    call    app_api_due
    j       79f
30: li      t1, LIBP2P_EVENT_RECEIVED
    beq     t0, t1, 31f
    li      t1, LIBP2P_EVENT_CLOSED
    bne     t0, t1, 79f
31: ld      s6, LIBP2P_EV_CONN(s2)          # the slot of the connection, at its generation
    mv      a0, s6
    call    app_api_slot
    beqz    a0, 79f
    mv      s4, a0
    ld      t0, 8(s2)
    li      t1, LIBP2P_EVENT_CLOSED
    bne     t0, t1, 4f
    li      a0, NODE_EV_API_CLOSED          # CLOSED: the node's stream ends, and the slot is free
    mv      a1, s6
    call    app_api_note
    sd      zero, 8(s4)
    sd      zero, 16(s4)
    j       79f
4:  ld      t0, 8(s4)                       # RECEIVED, unless closing or draining: the bytes join the buffer
    li      t1, APP_API_CLOSING
    bgeu    t0, t1, 79f
    LDQ     t1, s1, (APP_TICK + LIBP2P_TICK_NOW)
    sd      t1, 24(s4)
    slli    s5, s6, 32
    srli    s5, s5, 32
    ld      t2, 16(s4)
    ld      a2, LIBP2P_EV_COUNT(s2)
    add     t3, t2, a2
    li      t4, APP_API_BUFFER
    bleu    t3, t4, 5f
    li      t1, APP_API_READING             # no room: while reading, what fits (then 413); else the connection closes
    bne     t0, t1, 6f
    sub     a2, t4, t2
    mv      t3, t4
5:  sd      t3, 16(s4)
    LDQ     a0, s1, APP_API_BUF
    li      t0, APP_API_SLOT_BYTES
    mul     t0, s5, t0
    add     a0, a0, t0
    addi    a0, a0, 24
    add     a0, a0, t2
    addi    a1, s2, LIBP2P_EV_DATA
    call    lantern_copy
    mv      a0, s5
    call    app_api_read
    j       79f
6:  mv      a0, s6
    call    app_api_close
79: ld      t0, 0(s2)
    add     s2, s2, t0
    j       1b
80: LDQ     t0, s1, APP_API_EVENTS          # the idle connections close
    sd      zero, 16(t0)
    LDQ     s4, s1, APP_API_SLOTS
    li      s5, 0
81: LDQ     t0, s1, (APP_OPTIONS + AppOptions_http_max_connections)
    bgeu    s5, t0, 85f
    ld      t0, 8(s4)                       # reading, or draining, with no bytes for APP_API_IDLE_MS
    li      t1, APP_API_READING
    beq     t0, t1, 82f
    li      t1, APP_API_DRAINING
    bne     t0, t1, 84f
82: ld      t0, 24(s4)
    li      t1, APP_API_IDLE_MS
    add     t0, t0, t1
    LDQ     t1, s1, (APP_TICK + LIBP2P_TICK_NOW)
    bltu    t1, t0, 84f
    ld      a0, 0(s4)
    slli    a0, a0, 32
    or      a0, a0, s5
    call    app_api_close
84: addi    s4, s4, APP_API_SLOT
    addi    s5, s5, 1
    j       81b
85: call    app_api_flush
    LEAVE 16
END_FUNCTION app_api_poll

/* L2: each event of the shell becomes a NODE_EV_P2P event of the next step, but those of the engine's connection. s2 the next event, s3 the end. Locals: L the header. */
LOCAL_FUNCTION app_p2p_events
    ENTER 16
    LDQ     t0, s1, APP_SHELL_EVENTS
    ld      t1, 8(t0)
    ld      t2, 16(t0)
    add     s2, t0, t1
    add     s3, s2, t2
1:  bgeu    s2, s3, 9f
    mv      a0, s2                          # a datagram of discv5
    call    app_dv_datagram
    bnez    a0, 2f
    mv      a0, s2                          # the engine's connection
    call    app_engine_event
    bnez    a0, 2f
    mv      a0, s2                          # a builder call's connection
    call    app_builder_event
    bnez    a0, 2f
    ld      t0, 0(s2)
    addi    t0, t0, 16
    sd      t0, L(sp)
    li      t0, NODE_EV_P2P
    sd      t0, (L + 8)(sp)
    addi    a0, sp, L
    li      a1, 16
    call    app_event_put
    mv      a0, s2
    ld      a1, 0(s2)
    call    app_event_put
2:  ld      t0, 0(s2)
    add     s2, s2, t0
    j       1b
9:  LDQ     t0, s1, APP_SHELL_EVENTS
    sd      zero, 16(t0)
    call    app_builder_due                 # the builder calls: their bytes, ends and time limits
    LDQ     t0, s1, APP_ENGINE_DUE          # then more bytes of the request
    beqz    t0, 10f
    STQ     zero, s1, APP_ENGINE_DUE
    call    app_engine_send
10: LEAVE 16
END_FUNCTION app_p2p_events

/*
 * L2: the loop: the clock, a NODE_EV_TICK of the time and the shell's events, lantern_node_step
 * with libp2p, a line at each new slot, then a wait for the sockets until the node's wakeup, at
 * most APP_WAIT_MS. Locals: L the time, L+8 the wait, L+16 the NODE_EV_TICK.
 */
LOCAL_FUNCTION app_loop
    ENTER 48
1:  ADDQ    a0, s1, APP_TICK                # the clocks
    CALL_GLOBAL libp2p_shell_clock
    addi    a0, sp, L
    CALL_GLOBAL lantern_shell_time_ms
    li      t0, 24                          # NODE_EV_TICK of the Unix time
    sd      t0, (L + 16)(sp)
    li      t0, NODE_EV_TICK
    sd      t0, (L + 24)(sp)
    ld      t0, L(sp)
    sd      t0, (L + 32)(sp)
    addi    a0, sp, (L + 16)
    li      a1, 24
    call    app_event_put
    call    app_p2p_events
    LDQ     a0, s1, APP_P2P
    ADDQ    a1, s1, APP_TICK
    call    app_step
    call    app_discv5
    LDQ     a0, s1, APP_STORE               # a line at each new slot
    call    app_store_slot
    LDQ     t0, s1, APP_LAST_SLOT
    beq     a0, t0, 3f
    STQ     a0, s1, APP_LAST_SLOT
    sd      a0, (L + 8)(sp)
    call    app_line_start                  # slot <s>, head 0x<root>, finalized epoch <e>
    ADDRESS a0, app_m_slot
    li      a1, app_m_slot_len
    call    app_line_text
    ld      a0, (L + 8)(sp)
    call    app_line_u64
    ADDRESS a0, app_m_head
    li      a1, app_m_head_len
    call    app_line_text
    LDQ     a0, s1, APP_NODE
    ADDQ    a0, a0, Node_head_root
    li      a1, 8
    call    app_line_hex
    ADDRESS a0, app_m_finalized
    li      a1, app_m_finalized_len
    call    app_line_text
    LDQ     a0, s1, APP_STORE
    LDQ     a0, a0, Store_finalized_checkpoint
    call    app_line_u64
    ADDRESS a0, app_m_earliest              # the first slot the node serves blocks and sidecars from: the backfill's
    li      a1, app_m_earliest_len
    call    app_line_text
    LDQ     a0, s1, APP_NODE
    LDQ     a0, a0, Node_earliest_slot
    call    app_line_u64
    li      a0, APP_LOG_INFO
    call    app_line_end
3:  LDQ     t0, s1, APP_NODE                # a line when the count of connected peers changes
    LDQ     t0, t0, (Node_peers + 8)
    LDQ     t1, s1, APP_PEERS
    beq     t0, t1, 4f
    STQ     t0, s1, APP_PEERS
    call    app_line_start                  # peers <n>
    ADDRESS a0, app_m_peers
    li      a1, app_m_peers_len
    call    app_line_text
    LDQ     a0, s1, APP_PEERS
    call    app_line_u64
    li      a0, APP_LOG_INFO
    call    app_line_end
4:  LDQ     t0, s1, (APP_RESULT + 8)        # the wait: to the node's or discv5's wakeup, at most APP_WAIT_MS
    LDQ     t1, s1, APP_DV_WAKE
    bgeu    t1, t0, 31f
    mv      t0, t1
31: LDQ     t1, s1, (APP_TICK + LIBP2P_TICK_NOW)
    sub     t2, t0, t1
    bgtu    t0, t1, 32f
    li      t2, 0
32: li      t3, APP_WAIT_MS
    bltu    t2, t3, 33f
    mv      t2, t3
33: LDQ     t0, s1, APP_EVENTS              # no wait while events wait for the next step
    ld      t0, 16(t0)
    beqz    t0, 34f
    li      t2, 0
34: sd      t2, (L + 8)(sp)
    LDQ     a0, s1, APP_SHELL
    addi    a1, sp, (L + 8)
    LDQ     a2, s1, APP_SHELL_EVENTS
    CALL_GLOBAL libp2p_shell_wait
    call    app_api_poll
    j       1b
END_FUNCTION app_loop

/* (args): docs/reference/app.md. s1 the App, s2 args. Locals: L the fault. */
FUNCTION lantern_app_main
    ENTER 16
    mv      s2, a0
    li      a0, APP_SIZE
    call    app_map
    beqz    a0, 9f
    mv      s1, a0
    sd      s2, APP_ARGS(s1)
    li      t0, (24 + APP_LINE_MAX)
    li      t1, 24
    ADDQ    t2, s1, APP_LINE
    sd      t0, 0(t2)
    sd      t1, 8(t2)
    li      t0, (24 + APP_PATH_MAX)
    ADDQ    t2, s1, APP_PATH
    sd      t0, 0(t2)
    sd      t1, 8(t2)
    mv      a0, s2
    ADDQ    a1, s1, APP_OPTIONS
    addi    a2, sp, L
    CALL_GLOBAL lantern_app_options
    beqz    a0, 1f
    call    app_line_start                  # faulty option at argument <n>
    ADDRESS a0, app_m_option
    li      a1, app_m_option_len
    call    app_line_text
    ld      a0, L(sp)
    call    app_line_u64
    li      a0, APP_LOG_ERROR
    call    app_line_end
    li      a0, 1
    LEAVE 16
1:  call    app_start
    bnez    a0, 8f
    call    app_net
    bnez    a0, 8f
    call    app_loop
8:  LEAVE 16
9:  li      a0, 2
    LEAVE 16
END_FUNCTION lantern_app_main
