/*
 * The binary's startup and loop, x86-64: its own object, which only the binary links (entry.s calls
 * lantern_app_main). Requirements: docs/reference/app.md. The same steps as asm/core/arm64/app.s:
 * rbx holds the App (x19 there); rbp, r12, r13, r14 and r15 hold x20 to x24; the slots S7 and S8
 * hold x25 and x26; rdi, rsi, rdx, rcx, r8 and r9 hold the arguments x0 to x5.
 */
.set ISA_X86_64, 1
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

/* The App, at rbx; the constants and the RODATA. */
.include "app.inc"

/* reg = the scratch buffer, its size written back into its first 8 bytes: a callee may leave it
 * invalid (ARCHITECTURE.md section 6). Uses r11. */
.macro SCRATCH reg
    mov     APP_SCRATCH(%rbx), \reg
    mov     (APP_SCRATCH + 8)(%rbx), %r11
    mov     %r11, (\reg)
.endm

/* L0: rax = the fork of the slot rdi with the config rsi: the last fork whose epoch is at most the slot's. Uses rcx, rdx. */
LOCAL_FUNCTION app_fork
    UNWIND_END_PROLOGUE
    mov     %rdi, %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx                            # the epoch
    mov     $(16 * FORK_FULU), %ecx
1:  test    %rcx, %rcx
    jz      2f
    cmp     (%rsi,%rcx), %rax
    jae     2f
    sub     $16, %rcx
    jmp     1b
2:  mov     %rcx, %rax
    shr     $4, %rax
    ret
END_FUNCTION app_fork

/* L0: rax = the current slot of the store rdi: (time_ms - genesis_time_ms) // SLOT_DURATION_MS, 0 before genesis. Uses rcx, rdx. */
LOCAL_FUNCTION app_store_slot
    UNWIND_END_PROLOGUE
    mov     Store_time_ms(%rdi), %rax
    sub     Store_genesis_time_ms(%rdi), %rax
    jae     1f
    xor     %eax, %eax
1:  mov     (Store_config + CONFIG_SLOT_DURATION_MS)(%rdi), %rcx
    test    %rcx, %rcx
    jz      2f
    xor     %edx, %edx
    div     %rcx
    ret
2:  xor     %eax, %eax
    ret
END_FUNCTION app_store_slot

/* L0: rax = 1 when the rsi bytes at rdi are the rcx bytes at rdx, else 0. Uses rdi, rsi, rdx, r8. */
LOCAL_FUNCTION app_name_is
    UNWIND_END_PROLOGUE
    cmp     %rcx, %rsi
    jne     2f
1:  test    %rsi, %rsi
    jz      3f
    movzbl  (%rdi), %r8d
    cmp     (%rdx), %r8b
    jne     2f
    inc     %rdi
    inc     %rdx
    dec     %rsi
    jmp     1b
2:  xor     %eax, %eax
    ret
3:  mov     $1, %eax
    ret
END_FUNCTION app_name_is

/* L1: rax = memory of rdi bytes from lantern_shell_map, zeroed, or 0. Locals: the size, the address. */
LOCAL_FUNCTION app_map
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsp, %rdi
    lea     8(%rsp), %rsi
    CALL_GLOBAL lantern_shell_map
    mov     8(%rsp), %rax
    UNFRAME 16
END_FUNCTION app_map

/* L1: the pair at rbx + rdi goes back to lantern_shell_unmap and becomes 0, 0. */
LOCAL_FUNCTION app_unmap
    FRAME 16
    lea     (%rbx,%rdi), %rax
    mov     %rax, (%rsp)
    cmpq    $0, (%rax)
    je      1f
    mov     %rax, %rdi
    lea     8(%rax), %rsi
    CALL_GLOBAL lantern_shell_unmap
    mov     (%rsp), %rax
    movq    $0, (%rax)
    movq    $0, 8(%rax)
1:  UNFRAME 16
END_FUNCTION app_unmap

/* L1: the pair at rbx + rdi becomes new memory of rsi bytes, its first u64 the size: rax = the memory, or 0. */
LOCAL_FUNCTION app_alloc
    ENTER 0
    lea     (%rbx,%rdi), %rbp
    mov     %rsi, %r12
    mov     %rsi, %rdi
    call    app_map
    test    %rax, %rax
    jz      1f
    mov     %r12, (%rax)
    mov     %rax, (%rbp)
    mov     %r12, 8(%rbp)
1:  LEAVE 0
END_FUNCTION app_alloc

/* L0: the log line starts with "lantern: ". Uses rax, rcx, rdx, rsi, rdi. */
LOCAL_FUNCTION app_line_start
    UNWIND_END_PROLOGUE
    movq    $0, (APP_LINE + 16)(%rbx)
    ADDRESS %rdi, app_m_prefix
    mov     $app_m_prefix_len, %esi
    jmp     app_line_text
END_FUNCTION app_line_start

/* L0: the rsi bytes at rdi join the log line, as far as it has room. Uses rax, rcx, rdx, rsi, rdi. */
LOCAL_FUNCTION app_line_text
    UNWIND_END_PROLOGUE
    lea     APP_LINE(%rbx), %rax
    mov     16(%rax), %rcx
    mov     $APP_LINE_MAX, %edx
    sub     %rcx, %rdx
    cmp     %rdx, %rsi
    jbe     1f
    mov     %rdx, %rsi
1:  lea     (%rcx,%rsi), %rdx
    mov     %rdx, 16(%rax)
    lea     24(%rax,%rcx), %rax
2:  test    %rsi, %rsi
    jz      3f
    movzbl  (%rdi), %edx
    mov     %dl, (%rax)
    inc     %rdi
    inc     %rax
    dec     %rsi
    jmp     2b
3:  ret
END_FUNCTION app_line_text

/* L1: the decimal digits of rdi join the log line. Locals: 32 digit bytes. */
LOCAL_FUNCTION app_line_u64
    FRAME 32
    lea     32(%rsp), %rcx                  # the digits, from the end
    mov     %rdi, %rax
    mov     $10, %r8d
1:  xor     %edx, %edx
    div     %r8
    add     $0x30, %edx
    dec     %rcx
    mov     %dl, (%rcx)
    test    %rax, %rax
    jnz     1b
    mov     %rcx, %rdi
    lea     32(%rsp), %rsi
    sub     %rcx, %rsi
    call    app_line_text
    UNFRAME 32
END_FUNCTION app_line_u64

/* L1: the hex digits of the rsi bytes at rdi join the log line. Locals: rdi, rsi, then 2 digits. */
LOCAL_FUNCTION app_line_hex
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
1:  mov     8(%rsp), %rsi
    test    %rsi, %rsi
    jz      2f
    mov     (%rsp), %rdi
    movzbl  (%rdi), %eax
    inc     %rdi
    dec     %rsi
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    ADDRESS %rcx, app_hex_digits
    mov     %eax, %edx
    shr     $4, %edx
    movzbl  (%rcx,%rdx), %edx
    mov     %dl, 16(%rsp)
    and     $15, %eax
    movzbl  (%rcx,%rax), %eax
    mov     %al, 17(%rsp)
    lea     16(%rsp), %rdi
    mov     $2, %esi
    call    app_line_text
    jmp     1b
2:  UNFRAME 32
END_FUNCTION app_line_hex

/* L1: the log line and an LF go to stream rdi: 1 the standard output, 2 the standard error. */
LOCAL_FUNCTION app_line_end
    FRAME 16
    mov     %rdi, APP_STREAM(%rbx)
    movb    $10, (%rsp)
    mov     %rsp, %rdi
    mov     $1, %esi
    call    app_line_text
    lea     APP_STREAM(%rbx), %rdi
    lea     APP_LINE(%rbx), %rsi
    CALL_GLOBAL lantern_shell_write
    UNFRAME 16
END_FUNCTION app_line_end

/* L1: the path of the rsi bytes of the name at rdi in the network directory: a ByteList at APP_PATH. */
LOCAL_FUNCTION app_path
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %r12
    mov     (APP_OPTIONS + AppOptions_network_dir)(%rbx), %r13
    mov     (APP_OPTIONS + AppOptions_network_dir + 8)(%rbx), %r14
    lea     1(%r14,%r12), %rax              # the directory, /, the name: too long reads as too long
    lea     APP_PATH(%rbx), %r15
    cmp     $APP_PATH_MAX, %rax
    ja      1f
    mov     %rax, 16(%r15)
    mov     APP_ARGS(%rbx), %rsi
    add     %r13, %rsi
    lea     24(%r15), %rdi
    mov     %r14, %rdx
    call    lantern_copy
    lea     24(%r15,%r14), %rdi
    movb    $0x2f, (%rdi)                   # /
    inc     %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_copy
    LEAVE 0
1:  movq    $(APP_PATH_MAX + 1), 16(%r15)   # a count past the room: the shell gives its error
    LEAVE 0
END_FUNCTION app_path

/* L1: the path of the log line: the bytes of APP_PATH, as far as they fit. */
LOCAL_FUNCTION app_line_path
    FRAME 0
    lea     APP_PATH(%rbx), %rax
    lea     24(%rax), %rdi
    mov     16(%rax), %rsi
    cmp     $APP_PATH_MAX, %rsi
    jbe     1f
    mov     $APP_PATH_MAX, %esi
1:  call    app_line_text
    UNFRAME 0
END_FUNCTION app_line_path

/* L1: the file at APP_PATH, read into APP_FILE: rax = 0, or 2 after a line on the standard error. */
LOCAL_FUNCTION app_read
    FRAME 0
    lea     APP_PATH(%rbx), %rdi
    lea     APP_FILE(%rbx), %rsi
    CALL_GLOBAL lantern_shell_read_file
    cmpq    $0, APP_FILE(%rbx)
    je      1f
    call    app_line_start                  # cannot read <path>: error <n>
    ADDRESS %rdi, app_m_read
    mov     $app_m_read_len, %esi
    call    app_line_text
    call    app_line_path
    ADDRESS %rdi, app_m_error
    mov     $app_m_error_len, %esi
    call    app_line_text
    mov     APP_FILE(%rbx), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
    mov     $2, %eax
    UNFRAME 0
1:  xor     %eax, %eax
    UNFRAME 0
END_FUNCTION app_read

/*
 * L1: APP_PATH holds the path of the Arg at rdi, or a count past its room when the path does not
 * fit, so the shell gives its error.
 */
LOCAL_FUNCTION app_arg_path
    FRAME 0
    mov     (%rdi), %rsi
    mov     8(%rdi), %rdx
    cmp     $APP_PATH_MAX, %rdx
    ja      1f
    mov     %rdx, (APP_PATH + 16)(%rbx)
    lea     (APP_PATH + 24)(%rbx), %rdi
    add     APP_ARGS(%rbx), %rsi
    call    lantern_copy
    UNFRAME 0
1:  movq    $(APP_PATH_MAX + 1), (APP_PATH + 16)(%rbx)
    UNFRAME 0
END_FUNCTION app_arg_path

/*
 * L2: the anchor of --checkpoint-state and --checkpoint-block in APP_FILE, in the form of
 * anchor.ssz: one ByteList of two, the state's bytes, then the block's message from byte 100 of
 * its SignedBeaconBlock: rax = 0, or 2 after a line on the standard error. rbp the block file's
 * ByteList, r13 its bytes, r14 the state file's ByteList, r15 its bytes, S7 the buffer's size, S8
 * the buffer. Locals: L the block file's address and mapped size.
 */
LOCAL_FUNCTION app_checkpoint
    ENTER 16
    lea     (APP_OPTIONS + AppOptions_checkpoint_block)(%rbx), %rdi
    call    app_arg_path
    call    app_read
    test    %rax, %rax
    jnz     99f
    mov     (APP_FILE + 8)(%rbx), %rbp
    mov     (APP_FILE + 16)(%rbx), %r13
    cmp     $(100 + 84), %r13               # the offset and signature, then the message's fixed part
    jb      90f
    mov     %rbp, L(%rsp)
    mov     (APP_FILE + 24)(%rbx), %rax
    mov     %rax, (L + 8)(%rsp)
    movq    $0, (APP_FILE + 8)(%rbx)
    lea     (APP_OPTIONS + AppOptions_checkpoint_state)(%rbx), %rdi
    call    app_arg_path
    call    app_read
    test    %rax, %rax
    jnz     98f
    mov     (APP_FILE + 8)(%rbx), %r14
    mov     (APP_FILE + 16)(%rbx), %r15
    lea     7(%r15), %rax                   # three ByteList headers, the state to a multiple of 8, the message
    and     $-8, %rax
    lea     72(%rax,%r13), %rax
    sub     $100, %rax
    mov     %rax, S7(%rsp)
    mov     %rax, %rdi
    call    app_map
    test    %rax, %rax
    jz      97f
    mov     %rax, S8(%rsp)
    mov     S7(%rsp), %rcx                  # the ByteList of both
    mov     %rcx, (%rax)
    movq    $24, 8(%rax)
    sub     $24, %rcx
    mov     %rcx, 16(%rax)
    lea     24(%r15), %rcx                  # the state's
    mov     %rcx, 24(%rax)
    movq    $24, 32(%rax)
    mov     %r15, 40(%rax)
    lea     48(%rax), %rdi
    lea     24(%r14), %rsi
    mov     %r15, %rdx
    call    lantern_copy
    lea     7(%r15), %rax                   # the message's, at the first multiple of 8 after the state
    and     $-8, %rax
    add     $48, %rax
    add     S8(%rsp), %rax
    lea     -100(%r13), %rcx
    lea     24(%rcx), %rdx
    mov     %rdx, (%rax)
    movq    $24, 8(%rax)
    mov     %rcx, 16(%rax)
    lea     24(%rax), %rdi
    lea     (24 + 100)(%rbp), %rsi
    mov     %rcx, %rdx
    call    lantern_copy
    call    app_file_free                   # the files go; the buffer takes their place
    lea     L(%rsp), %rdi
    lea     (L + 8)(%rsp), %rsi
    CALL_GLOBAL lantern_shell_unmap
    movq    $0, APP_FILE(%rbx)
    mov     S8(%rsp), %rax
    mov     %rax, (APP_FILE + 8)(%rbx)
    mov     S7(%rsp), %rax
    mov     %rax, (APP_FILE + 24)(%rbx)
    sub     $24, %rax
    mov     %rax, (APP_FILE + 16)(%rbx)
    xor     %eax, %eax
    LEAVE 16
90: call    app_file_free                   # <path>: too short
    call    app_line_start
    call    app_line_path
    ADDRESS %rdi, app_m_short
    mov     $app_m_short_len, %esi
    call    app_line_text
    mov     $2, %edi
    call    app_line_end
    jmp     99f
97: call    app_file_free                   # no memory
    call    app_line_start
    ADDRESS %rdi, app_m_memory
    mov     $app_m_memory_len, %esi
    call    app_line_text
    mov     $2, %edi
    call    app_line_end
98: lea     L(%rsp), %rdi                   # the block file goes
    lea     (L + 8)(%rsp), %rsi
    CALL_GLOBAL lantern_shell_unmap
99: mov     $2, %eax
    LEAVE 16
END_FUNCTION app_checkpoint

/* L1: the memory of APP_FILE goes back. */
LOCAL_FUNCTION app_file_free
    FRAME 16
    cmpq    $0, (APP_FILE + 8)(%rbx)
    je      1f
    lea     (APP_FILE + 8)(%rbx), %rdi
    lea     (APP_FILE + 24)(%rbx), %rsi
    CALL_GLOBAL lantern_shell_unmap
    movq    $0, (APP_FILE + 8)(%rbx)
1:  UNFRAME 16
END_FUNCTION app_file_free

/* L1: a line "<rsi bytes at rdi>: status <rdx>" on the standard error, then rax = 2. Locals: rdi, rsi, rdx. */
LOCAL_FUNCTION app_fail_status
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    call    app_line_start
    mov     (%rsp), %rdi
    mov     8(%rsp), %rsi
    call    app_line_text
    ADDRESS %rdi, app_m_status
    mov     $app_m_status_len, %esi
    call    app_line_text
    mov     16(%rsp), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
    mov     $2, %eax
    UNFRAME 32
END_FUNCTION app_fail_status

/* L1: rax = 2 after a line "lantern: no memory" on the standard error. */
LOCAL_FUNCTION app_no_memory
    FRAME 0
    call    app_line_start
    ADDRESS %rdi, app_m_memory
    mov     $app_m_memory_len, %esi
    call    app_line_text
    mov     $2, %edi
    call    app_line_end
    mov     $2, %eax
    UNFRAME 0
END_FUNCTION app_no_memory

/*
 * L2: the start of docs/reference/app.md: the config, the anchor of genesis.ssz, the store, the
 * node and the Seen: rax = 0, or 2 after a line on the standard error. rbp a ByteList, r12 the
 * file's size, r13 a size, r14 a size, r15 the tries. Locals: L a line number or a size.
 */
LOCAL_FUNCTION app_start
    ENTER 16
    ADDRESS %rdi, app_builtin_config        # the config: the pinned config of the preset, then the network's
    lea     APP_CONFIG(%rbx), %rsi
    lea     L(%rsp), %rdx
    CALL_GLOBAL lantern_config_parse
    ADDRESS %rdi, app_config_name
    mov     $app_config_name_len, %esi
    call    app_path
    call    app_read
    test    %rax, %rax
    jnz     99f
    mov     (APP_FILE + 8)(%rbx), %rdi
    lea     APP_CONFIG(%rbx), %rsi
    lea     L(%rsp), %rdx
    CALL_GLOBAL lantern_config_parse
    mov     %rax, %rbp
    call    app_file_free
    test    %rbp, %rbp
    jz      1f
    call    app_line_start                  # <path>: faulty line <n>
    call    app_line_path
    ADDRESS %rdi, app_m_line
    mov     $app_m_line_len, %esi
    call    app_line_text
    mov     L(%rsp), %rdi
    call    app_line_u64
    jmp     98f
1:  movq    $0, S7(%rsp)                    # with a data directory: its anchor.ssz, when there is one
    cmpq    $0, (APP_OPTIONS + AppOptions_data_dir + 8)(%rbx)
    je      11f
    ADDRESS %rdi, app_anchor_name
    mov     $app_anchor_name_len, %esi
    lea     APP_PATH(%rbx), %rdx
    call    app_db_file
    lea     APP_PATH(%rbx), %rdi
    lea     APP_FILE(%rbx), %rsi
    CALL_GLOBAL lantern_shell_read_file
    cmpq    $0, APP_FILE(%rbx)
    jne     11f
    movq    $1, S7(%rsp)
    jmp     12f
11: cmpq    $0, (APP_OPTIONS + AppOptions_checkpoint_state + 8)(%rbx)  # else the checkpoint files
    je      111f
    call    app_checkpoint
    test    %rax, %rax
    jnz     99f
    movq    $2, S7(%rsp)
    jmp     12f
111: ADDRESS %rdi, app_genesis_name         # else genesis.ssz: the fork of its slot
    mov     $app_genesis_name_len, %esi
    call    app_path
    call    app_read
    test    %rax, %rax
    jnz     99f
12:
    mov     (APP_FILE + 8)(%rbx), %rbp
    mov     (APP_FILE + 16)(%rbx), %r12
    cmp     $(40 + 8), %r12
    jae     2f
    call    app_line_start
    call    app_line_path
    ADDRESS %rdi, app_m_short
    mov     $app_m_short_len, %esi
    call    app_line_text
    jmp     98f
2:  xor     %eax, %eax                      # BeaconState.slot, after the ByteList header of anchor.ssz's state
    mov     $24, %ecx
    cmpq    $0, S7(%rsp)
    cmovne  %rcx, %rax
    mov     (24 + 40)(%rbp,%rax), %rdi
    lea     APP_CONFIG(%rbx), %rsi
    call    app_fork
    mov     %rax, APP_FORK(%rbx)
    lea     APP_STATE_ROOM(%rbx), %rdi
    ADDRESS %rsi, app_state_room
    mov     $64, %edx
    call    lantern_copy
    lea     (%r12,%r12,2), %r13             # the state: 3 times the file and 16 MiB; scratch: 2 times and 64 MiB
    add     $(1 << 24), %r13
    lea     (%r12,%r12), %r14
    add     $(1 << 26), %r14
    xor     %r15d, %r15d
    movq    $APP_BLOCK_BYTES, S8(%rsp)      # the block: of genesis, or of anchor.ssz
    cmpq    $0, S7(%rsp)
    je      3f
    lea     (1 << 20)(%r12), %rax
    mov     %rax, S8(%rsp)
3:  mov     $APP_STATE, %edi
    mov     %r13, %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     $APP_SCRATCH, %edi
    mov     %r14, %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     $APP_BLOCK, %edi
    mov     S8(%rsp), %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     %rbp, %rdi
    lea     APP_STATE_ROOM(%rbx), %rsi
    SCRATCH %rdx
    mov     APP_STATE(%rbx), %rcx
    mov     APP_BLOCK(%rbx), %r8
    mov     APP_FORK(%rbx), %r10
    cmpq    $0, S7(%rsp)
    jne     31f
    FORK_CALL node_anchor
    jmp     32f
31: FORK_CALL node_anchor_block
32: test    %rax, %rax
    jz      4f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    jne     96f
    mov     $APP_STATE, %edi                # more room, a few times
    call    app_unmap
    mov     $APP_SCRATCH, %edi
    call    app_unmap
    mov     $APP_BLOCK, %edi
    call    app_unmap
    shl     $1, %r13
    shl     $1, %r14
    shlq    $1, S8(%rsp)
    inc     %r15
    cmp     $APP_TRIES, %r15
    jb      3b
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
96: mov     %rax, %rdx                      # genesis.ssz or anchor.ssz: status <n>
    ADDRESS %rdi, app_genesis_name
    mov     $app_genesis_name_len, %esi
    cmpq    $0, S7(%rsp)
    je      961f
    ADDRESS %rdi, app_anchor_name
    mov     $app_anchor_name_len, %esi
    cmpq    $1, S7(%rsp)
    je      961f
    mov     (APP_OPTIONS + AppOptions_checkpoint_state)(%rbx), %rdi
    add     APP_ARGS(%rbx), %rdi
    mov     (APP_OPTIONS + AppOptions_checkpoint_state + 8)(%rbx), %rsi
961:
    call    app_fail_status
    jmp     99f
4:  call    app_file_free
    mov     %r12, %rax                      # the store: nodes, and validators below the file's bytes / 121
    xor     %edx, %edx
    mov     $121, %ecx
    div     %rcx
    add     $4096, %rax
    movq    $4096, APP_STORE_ROOM(%rbx)
    mov     %rax, (APP_STORE_ROOM + 8)(%rbx)
    xor     %r15d, %r15d
5:  lea     APP_STORE_ROOM(%rbx), %rdi
    lea     L(%rsp), %rsi
    CALL_GLOBAL lantern_store_size
    mov     $APP_STORE, %edi
    mov     L(%rsp), %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     APP_STATE(%rbx), %rdi
    mov     APP_BLOCK(%rbx), %rsi
    lea     APP_CONFIG(%rbx), %rdx
    lea     APP_STORE_ROOM(%rbx), %rcx
    SCRATCH %r8
    mov     APP_STORE(%rbx), %r9
    mov     APP_FORK(%rbx), %r10
    FORK_CALL get_forkchoice_store
    test    %rax, %rax
    jz      6f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    jne     95f
    mov     $APP_STORE, %edi
    call    app_unmap
    shlq    $1, APP_STORE_ROOM(%rbx)
    shlq    $1, (APP_STORE_ROOM + 8)(%rbx)
    inc     %r15
    cmp     $APP_TRIES, %r15
    jb      5b
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
95: mov     %rax, %rdx                      # the store: status <n>
    ADDRESS %rdi, app_m_store
    mov     $app_m_store_len, %esi
    call    app_fail_status
    jmp     99f
6:  mov     APP_STORE(%rbx), %rax           # the node's anchor: the store's node 0, the state's root
    mov     Store_blocks(%rax), %rsi
    add     %rax, %rsi
    lea     APP_ANCHOR(%rbx), %rdi
    mov     $32, %edx
    call    lantern_copy
    mov     APP_STORE(%rbx), %rax
    mov     Store_blocks(%rax), %rcx
    add     %rax, %rcx
    mov     BlockNode_slot(%rcx), %rcx
    mov     %rcx, (APP_ANCHOR + 32)(%rbx)
    mov     %rcx, (APP_ANCHOR + NodeAnchor_history_slot)(%rbx)  # anchor.ssz's history lowers it
    lea     (APP_ANCHOR + 40)(%rbx), %rdi
    mov     APP_STATE(%rbx), %rsi
    add     $NODE_STATE_GVR, %rsi
    mov     $32, %edx
    call    lantern_copy
    orq     $NODE_FLAG_DISCV5, APP_FLAGS(%rbx)  # the shell runs discv5 for the node
    call    app_engine_conf                 # the execution engine
    test    %rax, %rax
    jnz     99f
    call    app_key                         # the key, and the anchor's node ID
    test    %rax, %rax
    jnz     94f
    lea     APP_NODE_ROOM(%rbx), %rdi       # the node
    ADDRESS %rsi, app_node_room
    mov     $(8 * NODE_ROOM_FIELDS), %edx
    call    lantern_copy
    mov     (APP_OPTIONS + AppOptions_target_peers)(%rbx), %rax
    mov     %rax, (APP_NODE_ROOM + NodeRoom_peers)(%rbx)
    call    app_db_start                    # the history's files
    cmpq    $1, S7(%rsp)
    jne     13f
    call    app_db_history                  # from anchor.ssz: the segments there
13:
    lea     APP_NODE_ROOM(%rbx), %rdi
    lea     L(%rsp), %rsi
    CALL_GLOBAL lantern_node_size
    test    %rax, %rax
    jnz     94f
    mov     $APP_NODE, %edi
    mov     L(%rsp), %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    lea     APP_NODE_ROOM(%rbx), %rdi
    lea     APP_CONFIG(%rbx), %rsi
    lea     APP_ANCHOR(%rbx), %rdx
    lea     APP_FLAGS(%rbx), %rcx
    mov     APP_NODE(%rbx), %r8
    CALL_GLOBAL lantern_node_init
    test    %rax, %rax
    jnz     94f
    cmpq    $0, S7(%rsp)
    je      14f
    cmpq    $1, S7(%rsp)
    je      141f
    call    app_line_start                  # checkpoint at slot <n>
    ADDRESS %rdi, app_m_checkpoint
    mov     $app_m_checkpoint_len, %esi
    call    app_line_text
    mov     (APP_ANCHOR + 32)(%rbx), %rdi
    call    app_line_u64
    mov     $1, %edi
    call    app_line_end
    jmp     14f
141: call   app_db_scan_all                 # from anchor.ssz: the history's segments to the node
    test    %rax, %rax
    jnz     99f
    call    app_line_start                  # restart at slot <n>
    ADDRESS %rdi, app_m_restart
    mov     $app_m_restart_len, %esi
    call    app_line_text
    mov     (APP_ANCHOR + 32)(%rbx), %rdi
    call    app_line_u64
    mov     $1, %edi
    call    app_line_end
14:
    lea     APP_SEEN_ROOM(%rbx), %rdi       # the Seen
    ADDRESS %rsi, app_seen_room
    mov     $32, %edx
    call    lantern_copy
    lea     APP_SEEN_ROOM(%rbx), %rdi
    lea     L(%rsp), %rsi
    CALL_GLOBAL lantern_seen_size
    mov     $APP_SEEN, %edi
    mov     L(%rsp), %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    lea     APP_SEEN_ROOM(%rbx), %rdi
    mov     APP_SEEN(%rbx), %rsi
    CALL_GLOBAL lantern_seen_init
    test    %rax, %rax
    jnz     94f
    mov     $APP_KZG, %edi                  # the KZG trusted setup
    mov     $CRYPTO_KZG_SETTINGS_SIZE, %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    ADDRESS %rdi, app_kzg_g1_lagrange
    ADDRESS %rsi, app_kzg_g1_monomial
    ADDRESS %rdx, app_kzg_g2_monomial
    mov     APP_KZG(%rbx), %rcx
    CALL_GLOBAL crypto_kzg_trusted_setup_of_bytes
    test    %rax, %rax
    jnz     93f
    mov     $(APP_BUF_ENTRY * APP_BUFS_CAP), %edi  # BufferId 1: the anchor state
    call    app_map
    test    %rax, %rax
    jz      97f
    mov     %rax, APP_BUFS(%rbx)
    movq    $1, (%rax)
    mov     APP_STATE(%rbx), %rcx
    mov     %rcx, 8(%rax)
    mov     (APP_STATE + 8)(%rbx), %rcx
    mov     %rcx, 16(%rax)
    movq    $1, (APP_BUFS + 8)(%rbx)
    movq    $APP_BUFS_CAP, (APP_BUFS + 16)(%rbx)
    mov     $APP_ACTIONS, %edi              # the queues of a step
    mov     $APP_QUEUE_BYTES, %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     $APP_EVENTS, %edi
    mov     $APP_QUEUE_BYTES, %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    mov     $APP_WORK_EVENT, %edi
    mov     $APP_QUEUE_BYTES, %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    call    app_line_start                  # started at slot <s>, fork <f>, head 0x<root>
    ADDRESS %rdi, app_m_started
    mov     $app_m_started_len, %esi
    call    app_line_text
    mov     (APP_ANCHOR + 32)(%rbx), %rdi
    call    app_line_u64
    ADDRESS %rdi, app_m_fork
    mov     $app_m_fork_len, %esi
    call    app_line_text
    mov     APP_FORK(%rbx), %rdi
    call    app_line_u64
    ADDRESS %rdi, app_m_head
    mov     $app_m_head_len, %esi
    call    app_line_text
    lea     APP_ANCHOR(%rbx), %rdi
    mov     $32, %esi
    call    app_line_hex
    mov     $1, %edi
    call    app_line_end
    xor     %eax, %eax
    LEAVE 16
93: mov     %rax, %rdx                      # the KZG trusted setup: status <n>
    ADDRESS %rdi, app_m_kzg
    mov     $app_m_kzg_len, %esi
    call    app_fail_status
    jmp     99f
94: mov     %rax, %rdx                      # the node: status <n>
    ADDRESS %rdi, app_m_node
    mov     $app_m_node_len, %esi
    call    app_fail_status
    jmp     99f
97: call    app_no_memory
    jmp     99f
98: mov     $2, %edi
    call    app_line_end
99: mov     $2, %eax
    LEAVE 16
END_FUNCTION app_start

/* L0: rax = the BufferId table entry of the id rdi, or 0. Uses rcx. */
LOCAL_FUNCTION app_buf_find
    UNWIND_END_PROLOGUE
    mov     APP_BUFS(%rbx), %rax
    mov     (APP_BUFS + 8)(%rbx), %rcx
1:  test    %rcx, %rcx
    jz      2f
    cmp     %rdi, (%rax)
    je      3f
    add     $APP_BUF_ENTRY, %rax
    dec     %rcx
    jmp     1b
2:  xor     %eax, %eax
3:  ret
END_FUNCTION app_buf_find

/* L1: a table entry of the id rdi for the memory rsi of rdx bytes: rax = 0, or 1 for id 0, an id in use or a full table. */
LOCAL_FUNCTION app_buf_add
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    test    %rdi, %rdi
    jz      9f
    call    app_buf_find
    test    %rax, %rax
    jnz     9f
    mov     (APP_BUFS + 8)(%rbx), %rcx
    cmp     (APP_BUFS + 16)(%rbx), %rcx
    jae     9f
    imul    $APP_BUF_ENTRY, %rcx, %rax
    add     APP_BUFS(%rbx), %rax
    mov     (%rsp), %rdx
    mov     %rdx, (%rax)
    mov     8(%rsp), %rdx
    mov     %rdx, 8(%rax)
    mov     16(%rsp), %rdx
    mov     %rdx, 16(%rax)
    inc     %rcx
    mov     %rcx, (APP_BUFS + 8)(%rbx)
    xor     %eax, %eax
    UNFRAME 32
9:  mov     $1, %eax
    UNFRAME 32
END_FUNCTION app_buf_add

/* L1: the buffer of the id rdi goes back to the OS, and the last entry takes its place. */
LOCAL_FUNCTION app_buf_drop
    FRAME 16
    call    app_buf_find
    test    %rax, %rax
    jz      9f
    mov     %rax, (%rsp)
    lea     8(%rax), %rdi
    lea     16(%rax), %rsi
    CALL_GLOBAL lantern_shell_unmap
    mov     (%rsp), %rdi                    # the entry
    mov     (APP_BUFS + 8)(%rbx), %rcx
    dec     %rcx
    mov     %rcx, (APP_BUFS + 8)(%rbx)
    imul    $APP_BUF_ENTRY, %rcx, %rax
    add     APP_BUFS(%rbx), %rax            # the last entry
    mov     (%rax), %rdx
    mov     %rdx, (%rdi)
    mov     8(%rax), %rdx
    mov     %rdx, 8(%rdi)
    mov     16(%rax), %rdx
    mov     %rdx, 16(%rdi)
9:  UNFRAME 16
END_FUNCTION app_buf_drop

/*
 * L1: rax = new memory with a copy of the rsi bytes at rdi, or 0. With a source and size of
 * multiples of 8, a page of the source that is all zero bytes is not written: the new memory is
 * zero already, and the OS keeps no memory for a page nobody writes. rbp the source, r12 the
 * size, r13 the copy, r14 the page's offset, r15 its bytes.
 */
LOCAL_FUNCTION app_dup
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %r12
    mov     %rsi, %rdi
    call    app_map
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    mov     %rbp, %rcx
    or      %r12, %rcx
    test    $7, %cl
    jz      1f
    mov     %rax, %rdi                      # not multiples of 8: all of it
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_copy
    jmp     8f
1:  xor     %r14d, %r14d
2:  mov     %r12, %r15                      # the next page: all zero, or a copy
    sub     %r14, %r15
    jbe     8f
    mov     $4096, %eax
    cmp     %rax, %r15
    cmova   %rax, %r15
    lea     (%rbp,%r14), %rsi
    xor     %ecx, %ecx
3:  cmpq    $0, (%rsi,%rcx)
    jne     4f
    add     $8, %rcx
    cmp     %r15, %rcx
    jb      3b
    jmp     5f
4:  lea     (%r13,%r14), %rdi
    mov     %r15, %rdx
    call    lantern_copy
5:  add     %r15, %r14
    jmp     2b
8:  mov     %r13, %rax
9:  LEAVE 0
END_FUNCTION app_dup

/*
 * L1: the rsi bytes of the event at rdi join the events of the next step, which grow when full:
 * rax = 0, or 1 with no memory. rbp the event, r12 its size, r13 the events, r14 a new size, r15 new memory.
 */
LOCAL_FUNCTION app_event_put
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %r12
1:  mov     APP_EVENTS(%rbx), %r13
    mov     (%r13), %rax
    mov     16(%r13), %rcx
    lea     24(%rcx,%r12), %rdx
    cmp     %rax, %rdx
    jbe     2f
    lea     (%rax,%rax), %r14               # twice the room, and the event
    add     %r12, %r14
    mov     %r14, %rdi
    call    app_map
    test    %rax, %rax
    jz      9f
    mov     %rax, %r15
    mov     %rax, %rdi
    mov     %r13, %rsi
    mov     16(%r13), %rdx
    add     $24, %rdx
    call    lantern_copy
    mov     %r14, (%r15)
    mov     $APP_EVENTS, %edi
    call    app_unmap
    mov     %r15, APP_EVENTS(%rbx)
    mov     %r14, (APP_EVENTS + 8)(%rbx)
    jmp     1b
2:  lea     24(%r13,%rcx), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_copy
    mov     APP_EVENTS(%rbx), %r13
    add     %r12, 16(%r13)
    xor     %eax, %eax
    LEAVE 0
9:  mov     $1, %eax
    LEAVE 0
END_FUNCTION app_event_put

/*
 * L1: the node (rdi = 0), the store (1) or the Seen (2) moves to new memory, with the field of its
 * room at byte offset rsi doubled, or each field for rsi = 2^64 - 1: rax = 0, or 1. rbp the kind, r12 the pair, r13 the room, r14 the room's fields,
 * r15 the new memory. Locals: L a size, L+8 an address.
 */
LOCAL_FUNCTION app_grow
    ENTER 16
    mov     %rdi, %rbp
    mov     $APP_NODE, %eax
    mov     $APP_NODE_ROOM, %ecx
    mov     $NODE_ROOM_FIELDS, %r14d
    cmp     $1, %rbp
    jne     1f
    mov     $APP_STORE, %eax
    mov     $APP_STORE_ROOM, %ecx
    mov     $2, %r14d
1:  cmp     $2, %rbp
    jne     2f
    mov     $APP_SEEN, %eax
    mov     $APP_SEEN_ROOM, %ecx
    mov     $4, %r14d
2:  lea     (%rbx,%rax), %r12
    lea     (%rbx,%rcx), %r13
    cmp     $-1, %rsi                       # one field: its offset, below the fields and a multiple of 8
    je      31f
    lea     (,%r14,8), %rcx
    cmp     %rcx, %rsi
    jae     9f
    test    $7, %esi
    jnz     9f
    shlq    $1, (%r13,%rsi)
    jmp     4f
31: xor     %ecx, %ecx
3:  cmp     %r14, %rcx
    jae     4f
    shlq    $1, (%r13,%rcx,8)
    inc     %rcx
    jmp     3b
4:  mov     %r13, %rdi                      # its size
    lea     L(%rsp), %rsi
    test    %rbp, %rbp
    jnz     41f
    CALL_GLOBAL lantern_node_size
    jmp     43f
41: cmp     $1, %rbp
    jne     42f
    CALL_GLOBAL lantern_store_size
    jmp     43f
42: CALL_GLOBAL lantern_seen_size
43: test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rdi
    call    app_map
    test    %rax, %rax
    jz      9f
    mov     %rax, %r15
    mov     L(%rsp), %rcx
    mov     %rcx, (%r15)
    mov     (%r12), %rdi                    # the copy
    mov     %r13, %rsi
    mov     %r15, %rdx
    test    %rbp, %rbp
    jnz     51f
    CALL_GLOBAL lantern_node_copy
    jmp     53f
51: cmp     $1, %rbp
    jne     52f
    CALL_GLOBAL lantern_store_copy
    jmp     53f
52: CALL_GLOBAL lantern_seen_copy
53: test    %rax, %rax
    jnz     8f
    mov     %r12, %rdi
    sub     %rbx, %rdi
    call    app_unmap
    mov     L(%rsp), %rcx
    mov     %r15, (%r12)
    mov     %rcx, 8(%r12)
    xor     %eax, %eax
    LEAVE 16
8:  mov     %r15, (L + 8)(%rsp)             # the copy failed: its memory goes back
    lea     (L + 8)(%rsp), %rdi
    lea     L(%rsp), %rsi
    CALL_GLOBAL lantern_shell_unmap
9:  mov     $1, %eax
    LEAVE 16
END_FUNCTION app_grow

/*
 * L1: the state of the BufferId table entry rdi moves to new memory with twice the StateRoom of the
 * App: rax = 0, or 1. rbp the entry, r12 the fork, r13 the new memory. Locals: L a size.
 */
LOCAL_FUNCTION app_regrow
    ENTER 16
    mov     %rdi, %rbp
    xor     %ecx, %ecx
1:  shlq    $1, APP_STATE_ROOM(%rbx,%rcx,8)
    inc     %rcx
    cmp     $8, %rcx
    jb      1b
    mov     8(%rbp), %rax                   # the fork of the state's slot
    mov     NODE_STATE_SLOT(%rax), %rdi
    lea     APP_CONFIG(%rbx), %rsi
    call    app_fork
    mov     %rax, %r12
    mov     8(%rbp), %rdi
    lea     APP_STATE_ROOM(%rbx), %rsi
    lea     L(%rsp), %rdx
    mov     %r12, %r10
    FORK_CALL beacon_state_copy_size
    mov     L(%rsp), %rdi
    call    app_map
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    mov     L(%rsp), %rcx
    mov     %rcx, (%r13)
    mov     8(%rbp), %rdi
    lea     APP_STATE_ROOM(%rbx), %rsi
    mov     %r13, %rdx
    mov     %r12, %r10
    FORK_CALL beacon_state_copy
    test    %rax, %rax
    jnz     9f
    lea     8(%rbp), %rdi
    lea     16(%rbp), %rsi
    CALL_GLOBAL lantern_shell_unmap
    mov     L(%rsp), %rcx
    mov     %r13, 8(%rbp)
    mov     %rcx, 16(%rbp)
    xor     %eax, %eax
    LEAVE 16
9:  mov     $1, %eax
    LEAVE 16
END_FUNCTION app_regrow

/*
 * L2: the WORK action rdi, by lantern_node_run with its buffers, again with more room while it asks
 * for it; then its WORK_DONE event joins the next step's. rbp the action, r12-r15 the entries of
 * state_a, state_b, state_c and data (or 0), S7 the tries, S8 the kind, S9 a size.
 */
LOCAL_FUNCTION app_work
    ENTER 0
    mov     %rdi, %rbp
    mov     NodeAction_work_kind(%rbp), %rax
    mov     %rax, S8(%rsp)
    movq    $0, S7(%rsp)
    mov     NodeAction_state_a(%rbp), %rdi
    call    app_work_entry
    mov     %rax, %r12
    mov     NodeAction_state_b(%rbp), %rdi
    call    app_work_entry
    mov     %rax, %r13
    mov     NodeAction_state_c(%rbp), %rdi
    call    app_work_entry
    mov     %rax, %r14
    mov     NodeAction_data(%rbp), %rdi
    call    app_work_data
    mov     %rax, %r15
    cmp     $-1, %r12                       # an id with no buffer
    je      90f
    cmp     $-1, %r13
    je      90f
    cmp     $-1, %r14
    je      90f
    cmp     $-1, %r15
    je      90f
1:  mov     APP_WORK_EVENT(%rbx), %rax      # the event's room
    mov     (APP_WORK_EVENT + 8)(%rbx), %rcx
    mov     %rcx, (%rax)
    sub     $48, %rsp                       # the seventh to eleventh arguments: state_c, data, settings, scratch, event
    xor     %eax, %eax
    test    %r14, %r14
    jz      11f
    mov     8(%r14), %rax
11: mov     %rax, (%rsp)
    xor     %eax, %eax
    test    %r15, %r15
    jz      12f
    mov     8(%r15), %rax
12: mov     %rax, 8(%rsp)
    mov     APP_KZG(%rbx), %rax
    mov     %rax, 16(%rsp)
    SCRATCH %rax
    mov     %rax, 24(%rsp)
    mov     APP_WORK_EVENT(%rbx), %rax
    mov     %rax, 32(%rsp)
    mov     APP_NODE(%rbx), %rdi
    mov     APP_STORE(%rbx), %rsi
    mov     APP_SEEN(%rbx), %rdx
    mov     %rbp, %rcx
    xor     %r8d, %r8d
    test    %r12, %r12
    jz      13f
    mov     8(%r12), %r8
13: xor     %r9d, %r9d
    test    %r13, %r13
    jz      14f
    mov     8(%r13), %r9
14: CALL_GLOBAL lantern_node_run
    add     $48, %rsp
    test    %rax, %rax
    jz      8f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    jne     91f
    incq    S7(%rsp)                        # more room: as the runner's shell
    cmpq    $APP_WORK_TRIES, S7(%rsp)
    jae     91f
    mov     S8(%rsp), %rcx
    cmp     $NODE_WORK_SERVE, %rcx          # SERVE, NEW_PAYLOAD, FORKCHOICE: a larger event
    je      2f
    cmp     $NODE_WORK_NEW_PAYLOAD, %rcx
    je      2f
    cmp     $NODE_WORK_FORKCHOICE, %rcx
    je      2f
    cmp     $NODE_WORK_GOSSIP, %rcx         # GOSSIP: the Seen, and the proposer state
    je      3f
    cmp     $NODE_WORK_TARGET_STATE, %rcx   # TARGET_STATE, SLOTS, and IMPORT_BLOCK with store room: state_a
    je      4f
    cmp     $NODE_WORK_SLOTS, %rcx
    je      4f
    cmp     $NODE_WORK_REPLAY, %rcx
    je      4f
    cmp     $NODE_WORK_UPGRADE, %rcx        # UPGRADE: state_b, the upgrade's buffer
    je      6f
    cmp     $NODE_WORK_IMPORT_BLOCK, %rcx
    jne     5f
    mov     APP_STORE(%rbx), %rcx
    mov     (Store_blocks + 8)(%rcx), %rcx
    cmp     (APP_STORE_ROOM + StoreRoom_nodes)(%rbx), %rcx
    jb      4f
5:  mov     $1, %edi                        # else the store
    mov     $-1, %rsi
    call    app_grow
    test    %rax, %rax
    jnz     91f
    jmp     1b
2:  mov     (APP_WORK_EVENT + 8)(%rbx), %rax
    shl     $2, %rax
    mov     %rax, S9(%rsp)
    mov     $APP_WORK_EVENT, %edi
    call    app_unmap
    mov     $APP_WORK_EVENT, %edi
    mov     S9(%rsp), %rsi
    call    app_alloc
    test    %rax, %rax
    jz      91f
    jmp     1b
3:  mov     $2, %edi                        # the Seen
    mov     $-1, %rsi
    call    app_grow
    test    %rax, %rax
    jnz     91f
    test    %r13, %r13
    jz      1b
    mov     %r13, %rdi
    call    app_regrow
    test    %rax, %rax
    jnz     91f
    jmp     1b
4:  test    %r12, %r12
    jz      91f
    mov     %r12, %rdi
    call    app_regrow
    test    %rax, %rax
    jnz     91f
    jmp     1b
6:  test    %r13, %r13
    jz      91f
    mov     %r13, %rdi
    call    app_regrow
    test    %rax, %rax
    jnz     91f
    jmp     1b
8:  mov     APP_WORK_EVENT(%rbx), %rdi      # the WORK_DONE event
    mov     (%rdi), %rsi
    call    app_event_put
    LEAVE 0
90: ADDRESS %rdi, app_m_buffer              # an action's BufferId: status 0
    mov     $app_m_buffer_len, %esi
    xor     %edx, %edx
    call    app_fail_status
    LEAVE 0
91: mov     %rax, %rdx                      # a work: status <n>
    ADDRESS %rdi, app_m_work
    mov     $app_m_work_len, %esi
    call    app_fail_status
    LEAVE 0
END_FUNCTION app_work

/*
 * L1: the history's files: no file open, no segment mapped; with a data directory, the node gets
 * NODE_FLAG_DB and room for a segment of slots, and the directory is made (one already there
 * will do; a failure shows at its first file). r15 the AppDb.
 */
LOCAL_FUNCTION app_db_start
    ENTER 0
    lea     APP_DB(%rbx), %r15
    movq    $-1, AppDb_segment(%r15)
    movq    $-1, (AppDb_segment + 8)(%r15)
    xor     %ecx, %ecx
1:  mov     %rcx, %rax
    shl     $5, %rax
    movq    $-1, AppDb_maps(%r15,%rax)
    movq    $0, (AppDb_maps + 8)(%r15,%rax)
    inc     %rcx
    cmp     $APP_DB_MAP_COUNT, %rcx
    jb      1b
    movq    $0, AppDb_next_map(%r15)
    movq    $-1, AppDb_anchor_slot(%r15)
    mov     (APP_ANCHOR + 32)(%rbx), %rax   # the Db from the anchor's slot
    mov     %rax, (APP_ANCHOR + NodeAnchor_history_slot)(%rbx)
    mov     (APP_OPTIONS + AppOptions_data_dir + 8)(%rbx), %r12
    test    %r12, %r12
    jz      9f
    orq     $NODE_FLAG_DB, APP_FLAGS(%rbx)
    movq    $DB_SEGMENT_SLOTS, (APP_NODE_ROOM + NodeRoom_db_slots)(%rbx)
    movq    $APP_DB_ROOTS, (APP_NODE_ROOM + NodeRoom_db_roots)(%rbx)
    cmp     $APP_PATH_MAX, %r12
    ja      9f
    lea     APP_PATH(%rbx), %r13            # the directory's path
    mov     %r12, 16(%r13)
    mov     APP_ARGS(%rbx), %rsi
    add     (APP_OPTIONS + AppOptions_data_dir)(%rbx), %rsi
    lea     24(%r13), %rdi
    mov     %r12, %rdx
    call    lantern_copy
    mov     %r13, %rdi
    lea     AppDb_op(%r15), %rsi
    CALL_GLOBAL lantern_shell_mkdir
9:  LEAVE 0
END_FUNCTION app_db_start

/* L1: the path of segment rsi of blocks (rdi 0) or sidecars (1) in the data directory, <dir>/b<n>.seg or <dir>/s<n>.seg: a ByteList at APP_PATH. rbp the kind, r12 the segment, r13 the next byte. Locals: L 24 digits. */
LOCAL_FUNCTION app_db_path
    ENTER 32
    mov     %rdi, %rbp
    mov     %rsi, %r12
    lea     APP_PATH(%rbx), %r13
    mov     (APP_OPTIONS + AppOptions_data_dir + 8)(%rbx), %rdx
    cmp     $(APP_PATH_MAX - 32), %rdx
    ja      8f
    mov     APP_ARGS(%rbx), %rsi
    add     (APP_OPTIONS + AppOptions_data_dir)(%rbx), %rsi
    lea     24(%r13), %rdi
    lea     24(%r13,%rdx), %r13
    call    lantern_copy
    movb    $0x2f, (%r13)                   # /
    movb    $0x62, %al                      # b
    test    %rbp, %rbp
    jz      1f
    movb    $0x73, %al                      # s
1:  movb    %al, 1(%r13)
    add     $2, %r13
    lea     (L + 24)(%rsp), %rcx            # the number's digits, from the last
    mov     %r12, %rax
    mov     $10, %r8d
2:  xor     %edx, %edx
    div     %r8
    add     $0x30, %dl
    dec     %rcx
    mov     %dl, (%rcx)
    test    %rax, %rax
    jnz     2b
    lea     (L + 24)(%rsp), %rdx
3:  cmp     %rdx, %rcx
    jae     4f
    mov     (%rcx), %al
    mov     %al, (%r13)
    inc     %rcx
    inc     %r13
    jmp     3b
4:  movl    $0x6765732e, (%r13)            # .seg
    add     $4, %r13
    lea     APP_PATH(%rbx), %rax
    lea     24(%rax), %rcx
    sub     %rcx, %r13
    mov     %r13, 16(%rax)
    LEAVE 32
8:  lea     APP_PATH(%rbx), %rax            # a count past the room: the shell gives its error
    movq    $(APP_PATH_MAX + 1), 16(%rax)
    LEAVE 32
END_FUNCTION app_db_path

/*
 * L1: NODE_ACT_DB_APPEND rdi: the record at the end of its segment file, its DbRecord, its bytes
 * and zero bytes to a multiple of 8. A file that is not the open one of its kind opens, and is cut
 * to the record's offset first. A failure gives a line on the standard error, and the file closes,
 * so the next record opens it again. rbp the action, r12 the kind (0 blocks, 1 sidecars), r13 the
 * bytes' table entry, r14 the file, r15 the AppDb. Locals: L a ByteList header, L+24 a u64, L+32 zero bytes.
 */
LOCAL_FUNCTION app_db_append
    ENTER 48
    mov     %rdi, %rbp
    lea     APP_DB(%rbx), %r15
    mov     32(%rbp), %r12
    and     $1, %r12d
    mov     16(%rbp), %rdi
    call    app_buf_find
    test    %rax, %rax
    jz      99f
    mov     %rax, %r13
    lea     AppDb_file(%r15,%r12,8), %r14
    mov     AppDb_segment(%r15,%r12,8), %rax
    cmp     24(%rbp), %rax
    je      2f
    cmp     $-1, %rax                       # another file of the kind: it closes
    je      1f
    mov     %r14, %rdi
    CALL_GLOBAL lantern_shell_close
    movq    $-1, AppDb_segment(%r15,%r12,8)
1:  mov     %r12, %rdi                      # the segment's file, to append to, cut to the offset
    mov     24(%rbp), %rsi
    call    app_db_path
    movq    $1, (L + 24)(%rsp)
    lea     APP_PATH(%rbx), %rdi
    lea     (L + 24)(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_open
    cmpq    $0, AppDb_op(%r15)
    jne     90f
    mov     (AppDb_op + 8)(%r15), %rax
    mov     %rax, (%r14)
    mov     %r14, %rdi
    lea     40(%rbp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_truncate
    cmpq    $0, AppDb_op(%r15)
    jne     89f
    mov     24(%rbp), %rax
    mov     %rax, AppDb_segment(%r15,%r12,8)
2:  lea     48(%rbp), %rax                  # the DbRecord: a ByteList of the action's 64 bytes
    lea     L(%rsp), %rcx
    sub     %rcx, %rax
    movq    $24, L(%rsp)
    mov     %rax, (L + 8)(%rsp)
    movq    $DbRecord__mem, (L + 16)(%rsp)
    mov     %r14, %rdi
    lea     L(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_append
    cmpq    $0, AppDb_op(%r15)
    jne     89f
    mov     %r14, %rdi                      # the bytes
    mov     8(%r13), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_append
    cmpq    $0, AppDb_op(%r15)
    jne     89f
    mov     8(%r13), %rax                   # zero bytes to a multiple of 8
    mov     16(%rax), %rax
    neg     %rax
    and     $7, %eax
    jz      99f
    movq    $0, (L + 32)(%rsp)
    movq    $24, L(%rsp)
    movq    $32, (L + 8)(%rsp)
    mov     %rax, (L + 16)(%rsp)
    mov     %r14, %rdi
    lea     L(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_append
    cmpq    $0, AppDb_op(%r15)
    jne     89f
99: LEAVE 48
89: mov     %r14, %rdi                      # the file closes
    CALL_GLOBAL lantern_shell_close
    movq    $-1, AppDb_segment(%r15,%r12,8)
90: mov     AppDb_op(%r15), %rax            # cannot write <path>: error <n>
    mov     %rax, (L + 24)(%rsp)
    mov     %r12, %rdi
    mov     24(%rbp), %rsi
    call    app_db_path
    call    app_line_start
    ADDRESS %rdi, app_m_write
    mov     $app_m_write_len, %esi
    call    app_line_text
    call    app_line_path
    ADDRESS %rdi, app_m_error
    mov     $app_m_error_len, %esi
    call    app_line_text
    mov     (L + 24)(%rsp), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
    LEAVE 48
END_FUNCTION app_db_append

/*
 * L1: NODE_ACT_DB_DROP rdi: the segment's file goes: the open file of its kind, when it is that
 * segment, closes; a map of it goes; then the file is deleted. r12 the action, r13 the kind (0
 * blocks, 1 sidecars), r14 the segment, r15 the AppDb, rbp a map, S7 the map key, S8 a map's index.
 */
LOCAL_FUNCTION app_db_drop
    ENTER 0
    mov     %rdi, %r12
    lea     APP_DB(%rbx), %r15
    mov     24(%r12), %r13
    and     $1, %r13d
    mov     16(%r12), %r14
    cmp     AppDb_segment(%r15,%r13,8), %r14    # the open file of its kind
    jne     1f
    lea     AppDb_file(%r15,%r13,8), %rdi
    CALL_GLOBAL lantern_shell_close
    movq    $-1, AppDb_segment(%r15,%r13,8)
1:  mov     %r13, %rax                      # its map
    shl     $63, %rax
    or      %r14, %rax
    mov     %rax, S7(%rsp)
    movq    $0, S8(%rsp)
2:  mov     S8(%rsp), %rax
    cmp     $APP_DB_MAP_COUNT, %rax
    jae     4f
    shl     $5, %rax
    lea     AppDb_maps(%r15,%rax), %rbp
    mov     (%rbp), %rax
    cmp     S7(%rsp), %rax
    jne     3f
    cmpq    $0, 8(%rbp)
    je      21f
    lea     8(%rbp), %rdi
    lea     24(%rbp), %rsi
    CALL_GLOBAL lantern_shell_unmap_file
21: movq    $-1, (%rbp)
    movq    $0, 8(%rbp)
3:  incq    S8(%rsp)
    jmp     2b
4:  mov     %r13, %rdi                      # the file
    mov     %r14, %rsi
    call    app_db_path
    lea     APP_PATH(%rbx), %rdi
    lea     AppDb_op(%r15), %rsi
    CALL_GLOBAL lantern_shell_remove
    LEAVE 0
END_FUNCTION app_db_drop

/*
 * L0: rax = the AppDb's view entry of the record at offset rdi of the mapped segment rsi: its
 * ByteList in place, at byte DbRecord_bytes of the record; 0 when the record is not all inside
 * the map, or its ByteList header is not of its bytes. Uses rcx, rdx, r8, r9.
 */
LOCAL_FUNCTION app_db_record
    UNWIND_END_PROLOGUE
    mov     8(%rsi), %r8
    test    %r8, %r8
    jz      8f
    mov     16(%rsi), %rdx
    lea     DbRecord__mem(%rdi), %rcx
    cmp     %rdi, %rcx
    jb      8f
    cmp     %rdx, %rcx
    ja      8f
    add     %rdi, %r8                       # the record, its bytes inside
    mov     DbRecord_length(%r8), %r9
    sub     %rcx, %rdx
    cmp     %rdx, %r9
    ja      8f
    lea     24(%r9), %rcx                   # its ByteList: size 24 + length, offset 24
    cmp     %rcx, DbRecord_bytes(%r8)
    jne     8f
    cmpq    $24, (DbRecord_bytes + 8)(%r8)
    jne     8f
    lea     (APP_DB + AppDb_view)(%rbx), %rax
    lea     DbRecord_bytes(%r8), %rcx
    mov     %rcx, 8(%rax)
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION app_db_record

/*
 * L1: rax = the table entry of a work's data BufferId rdi as app_work_entry gives; for a
 * NODE_DB_REF, the AppDb's view entry of its record in the segment, mapped again when the file
 * grew past the map, or 2^64 - 1 when the record is not there. rbp the kind, r12 the segment, r13
 * the offset, r14 a map, r15 the AppDb, S7 the map's key.
 */
LOCAL_FUNCTION app_work_data
    ENTER 0
    bt      $63, %rdi
    jc      1f
    call    app_work_entry
    LEAVE 0
1:  lea     APP_DB(%rbx), %r15
    mov     %rdi, %rbp
    shr     $62, %rbp
    and     $1, %ebp
    mov     %rdi, %r12
    shr     $48, %r12
    and     $0x3fff, %r12d
    mov     %rdi, %r13
    shl     $16, %r13
    shr     $16, %r13
    mov     %rbp, %rax
    shl     $63, %rax
    or      %r12, %rax
    mov     %rax, S7(%rsp)
    xor     %ecx, %ecx                      # the map of the segment
2:  cmp     $APP_DB_MAP_COUNT, %rcx
    jae     5f
    mov     %rcx, %rdx
    shl     $5, %rdx
    lea     AppDb_maps(%r15,%rdx), %r14
    cmp     (%r14), %rax
    je      3f
    inc     %rcx
    jmp     2b
3:  mov     %r13, %rdi
    mov     %r14, %rsi
    call    app_db_record
    test    %rax, %rax
    jnz     9f
    jmp     6f
5:  mov     AppDb_next_map(%r15), %rcx      # else the next entry in turn
    lea     1(%rcx), %rax
    and     $(APP_DB_MAP_COUNT - 1), %eax
    mov     %rax, AppDb_next_map(%r15)
    shl     $5, %rcx
    lea     AppDb_maps(%r15,%rcx), %r14
6:  cmpq    $0, 8(%r14)                     # its old map goes
    je      7f
    lea     8(%r14), %rdi
    lea     24(%r14), %rsi
    CALL_GLOBAL lantern_shell_unmap_file
7:  movq    $-1, (%r14)
    movq    $0, 8(%r14)
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    app_db_path
    lea     APP_PATH(%rbx), %rdi
    lea     AppDb_op(%r15), %rsi
    CALL_GLOBAL lantern_shell_map_file
    cmpq    $0, AppDb_op(%r15)
    jne     8f
    mov     (AppDb_op + 8)(%r15), %rax
    test    %rax, %rax
    jz      8f
    mov     %rax, 8(%r14)
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    mov     (AppDb_op + 16)(%r15), %rax
    mov     %rax, 16(%r14)
    mov     (AppDb_op + 24)(%r15), %rax
    mov     %rax, 24(%r14)
    mov     %r13, %rdi
    mov     %r14, %rsi
    call    app_db_record
    test    %rax, %rax
    jnz     9f
8:  mov     $-1, %rax
9:  LEAVE 0
END_FUNCTION app_work_data

/* L1: <dir>/<the rsi bytes of the name at rdi> of the data directory, as a ByteList at rdx of APP_PATH_MAX bytes of room. rbp the name, r12 its length, r13 the ByteList. */
LOCAL_FUNCTION app_db_file
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %r12
    mov     %rdx, %r13
    movq    $(24 + APP_PATH_MAX), (%r13)
    movq    $24, 8(%r13)
    mov     (APP_OPTIONS + AppOptions_data_dir + 8)(%rbx), %rdx
    lea     1(%rdx,%r12), %rax
    cmp     $APP_PATH_MAX, %rax
    ja      8f
    mov     %rax, 16(%r13)
    mov     APP_ARGS(%rbx), %rsi
    add     (APP_OPTIONS + AppOptions_data_dir)(%rbx), %rsi
    lea     24(%r13), %rdi
    call    lantern_copy
    mov     (APP_OPTIONS + AppOptions_data_dir + 8)(%rbx), %rax
    lea     24(%r13,%rax), %rdi
    movb    $0x2f, (%rdi)                   # /
    inc     %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_copy
    LEAVE 0
8:  movq    $(APP_PATH_MAX + 1), 16(%r13)   # a count past the room: the shell gives its error
    LEAVE 0
END_FUNCTION app_db_file

/* L1: rax = 1 when the block segment rdi's file is there (it opens to read), else 0. r15 the AppDb. Locals: L the mode. */
LOCAL_FUNCTION app_db_exists
    ENTER 16
    lea     APP_DB(%rbx), %r15
    mov     %rdi, %rsi
    xor     %edi, %edi
    call    app_db_path
    movq    $0, L(%rsp)
    lea     APP_PATH(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_open
    cmpq    $0, AppDb_op(%r15)
    jne     8f
    lea     (AppDb_op + 8)(%r15), %rdi
    CALL_GLOBAL lantern_shell_close
    mov     $1, %eax
    LEAVE 16
8:  xor     %eax, %eax
    LEAVE 16
END_FUNCTION app_db_exists

/*
 * L1: for a start from anchor.ssz: the first block segment file there, from 0 to the anchor's
 * segment, gives the anchor's history_slot; the Db has room for the slots from it to the last
 * block segment file there, from the anchor's on, and a segment more, and a power of two of roots
 * above twice them. rbp a segment, r12 the anchor's segment, r13 the first, r14 the last.
 */
LOCAL_FUNCTION app_db_history
    ENTER 0
    mov     (APP_ANCHOR + 32)(%rbx), %r12
    shr     $DB_SEGMENT_SHIFT, %r12
    mov     %r12, %r13
    xor     %ebp, %ebp
1:  cmp     %r12, %rbp
    ja      2f
    mov     %rbp, %rdi
    call    app_db_exists
    test    %rax, %rax
    jnz     11f
    inc     %rbp
    jmp     1b
11: mov     %rbp, %r13
2:  mov     %r12, %r14
    lea     1(%r12), %rbp
3:  mov     %rbp, %rdi
    call    app_db_exists
    test    %rax, %rax
    jz      4f
    mov     %rbp, %r14
    inc     %rbp
    jmp     3b
4:  mov     %r13, %rax
    shl     $DB_SEGMENT_SHIFT, %rax
    mov     %rax, (APP_ANCHOR + NodeAnchor_history_slot)(%rbx)
    mov     %r14, %rax
    sub     %r13, %rax
    add     $2, %rax
    shl     $DB_SEGMENT_SHIFT, %rax
    mov     %rax, (APP_NODE_ROOM + NodeRoom_db_slots)(%rbx)
    add     %rax, %rax
    bsr     %rax, %rcx
    inc     %ecx
    mov     $1, %eax
    shl     %cl, %rax
    mov     %rax, (APP_NODE_ROOM + NodeRoom_db_roots)(%rbx)
    LEAVE 0
END_FUNCTION app_db_history

/*
 * L1: for a start from anchor.ssz: each segment file there, the blocks' then the sidecars', from
 * the segment of history_slot to the end of the Db's room, goes to lantern_node_db_scan; a file
 * with bytes after its last whole record is cut there: rax = 0, or 2 after a line on the standard
 * error. rbp the kind, r12 the segment, r13 the end, r14 a status, r15 the AppDb. Locals: L a
 * ByteList header, L+24 valid, L+32 the segment, L+40 the kind, L+48 the file's size or a mode,
 * L+56 a file.
 */
LOCAL_FUNCTION app_db_scan_all
    ENTER 64
    lea     APP_DB(%rbx), %r15
    mov     (APP_ANCHOR + NodeAnchor_history_slot)(%rbx), %rax
    shr     $DB_SEGMENT_SHIFT, %rax
    mov     (APP_NODE_ROOM + NodeRoom_db_slots)(%rbx), %r13
    shr     $DB_SEGMENT_SHIFT, %r13
    add     %rax, %r13
    xor     %ebp, %ebp
1:  mov     (APP_ANCHOR + NodeAnchor_history_slot)(%rbx), %r12
    shr     $DB_SEGMENT_SHIFT, %r12
2:  cmp     %r13, %r12
    jae     7f
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    app_db_path
    lea     APP_PATH(%rbx), %rdi
    lea     AppDb_op(%r15), %rsi
    CALL_GLOBAL lantern_shell_map_file
    cmpq    $0, AppDb_op(%r15)
    jne     6f                              # not there
    mov     (AppDb_op + 8)(%r15), %rax
    test    %rax, %rax
    jz      6f                              # empty
    lea     L(%rsp), %rcx                   # its bytes: a ByteList of the map
    sub     %rcx, %rax
    movq    $24, L(%rsp)
    mov     %rax, (L + 8)(%rsp)
    mov     (AppDb_op + 16)(%r15), %rax
    mov     %rax, (L + 16)(%rsp)
    mov     %rax, (L + 48)(%rsp)
    mov     %r12, (L + 32)(%rsp)
    mov     %rbp, (L + 40)(%rsp)
    mov     APP_NODE(%rbx), %rdi
    lea     (L + 32)(%rsp), %rsi
    lea     (L + 40)(%rsp), %rdx
    lea     L(%rsp), %rcx
    lea     (L + 24)(%rsp), %r8
    CALL_GLOBAL lantern_node_db_scan
    mov     %rax, %r14
    lea     (AppDb_op + 8)(%r15), %rdi
    lea     (AppDb_op + 24)(%r15), %rsi
    CALL_GLOBAL lantern_shell_unmap_file
    test    %r14, %r14
    jnz     8f
    mov     (L + 24)(%rsp), %rax            # bytes after the last whole record: the file is cut there
    cmp     (L + 48)(%rsp), %rax
    jae     6f
    movq    $1, (L + 48)(%rsp)
    lea     APP_PATH(%rbx), %rdi
    lea     (L + 48)(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_open
    cmpq    $0, AppDb_op(%r15)
    jne     6f
    mov     (AppDb_op + 8)(%r15), %rax
    mov     %rax, (L + 56)(%rsp)
    lea     (L + 56)(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_truncate
    lea     (L + 56)(%rsp), %rdi
    CALL_GLOBAL lantern_shell_close
6:  inc     %r12
    jmp     2b
7:  inc     %rbp
    cmp     $2, %rbp
    jb      1b
    xor     %eax, %eax
    LEAVE 64
8:  lea     APP_PATH(%rbx), %rax            # <path>: status <n>
    lea     24(%rax), %rdi
    mov     16(%rax), %rsi
    mov     %r14, %rdx
    call    app_fail_status
    LEAVE 64
END_FUNCTION app_db_scan_all

/*
 * L1: NODE_ACT_DB_STATE rdi, with no anchor written in this run or one DB_SEGMENT_SLOTS slots
 * back: the open segment files are synced; <dir>/anchor.tmp gets two ByteLists, the second at the
 * first multiple of 8 after the first: the state's SSZ bytes, then those of its block's message;
 * it is synced and renamed over <dir>/anchor.ssz, and the directory is synced. A failure gives a
 * line on the standard error. rbp the action, r12 the state's entry, r13 the block's entry, r14
 * the state's ByteList, r15 the AppDb, S7 its size. Locals: L a ByteList header, L+24 a u64, L+32
 * zero bytes, L+40 a size, L+48 the fork, L+56 the file, L+64 the message's ByteList header.
 */
LOCAL_FUNCTION app_db_state
    ENTER 96
    mov     %rdi, %rbp
    lea     APP_DB(%rbx), %r15
    xor     %r14d, %r14d
    mov     AppDb_anchor_slot(%r15), %rax
    cmp     $-1, %rax
    je      1f
    add     $DB_SEGMENT_SLOTS, %rax
    cmp     %rax, 32(%rbp)
    jb      99f
1:  mov     16(%rbp), %rdi
    call    app_buf_find
    test    %rax, %rax
    jz      99f
    mov     %rax, %r12
    mov     24(%rbp), %rdi
    call    app_buf_find
    test    %rax, %rax
    jz      99f
    mov     %rax, %r13
    cmpq    $-1, AppDb_segment(%r15)        # the open segment files are synced
    je      2f
    lea     AppDb_file(%r15), %rdi
    lea     AppDb_op(%r15), %rsi
    CALL_GLOBAL lantern_shell_sync
2:  cmpq    $-1, (AppDb_segment + 8)(%r15)
    je      3f
    lea     (AppDb_file + 8)(%r15), %rdi
    lea     AppDb_op(%r15), %rsi
    CALL_GLOBAL lantern_shell_sync
3:  mov     32(%rbp), %rdi                  # the state's SSZ bytes: their size, then the bytes
    lea     APP_CONFIG(%rbx), %rsi
    call    app_fork
    mov     %rax, (L + 48)(%rsp)
    movq    $24, L(%rsp)
    movq    $0, (L + 40)(%rsp)
    mov     %rax, %r10
    mov     8(%r12), %rdi
    SCRATCH %rsi
    lea     L(%rsp), %rdx
    lea     (L + 40)(%rsp), %rcx
    FORK_CALL node_state_bytes
    mov     (L + 40)(%rsp), %rax
    cmp     $24, %rax
    jbe     99f
    mov     %rax, S7(%rsp)
    mov     %rax, %rdi
    call    app_map
    test    %rax, %rax
    jz      99f
    mov     %rax, %r14
    mov     S7(%rsp), %rax
    mov     %rax, (%r14)
    mov     (L + 48)(%rsp), %r10
    mov     8(%r12), %rdi
    SCRATCH %rsi
    mov     %r14, %rdx
    lea     (L + 40)(%rsp), %rcx
    FORK_CALL node_state_bytes
    test    %rax, %rax
    jnz     98f
    ADDRESS %rdi, app_anchor_tmp_name       # anchor.tmp, cut to 0
    mov     $app_anchor_tmp_name_len, %esi
    lea     APP_PATH(%rbx), %rdx
    call    app_db_file
    movq    $1, (L + 24)(%rsp)
    lea     APP_PATH(%rbx), %rdi
    lea     (L + 24)(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_open
    cmpq    $0, AppDb_op(%r15)
    jne     90f
    mov     (AppDb_op + 8)(%r15), %rax
    mov     %rax, (L + 56)(%rsp)
    movq    $0, (L + 24)(%rsp)
    lea     (L + 56)(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_truncate
    cmpq    $0, AppDb_op(%r15)
    jne     89f
    lea     L(%rsp), %rcx                   # the state's ByteList, its header and bytes
    mov     %r14, %rax
    sub     %rcx, %rax
    movq    $24, L(%rsp)
    mov     %rax, (L + 8)(%rsp)
    mov     S7(%rsp), %rax
    mov     %rax, (L + 16)(%rsp)
    lea     (L + 56)(%rsp), %rdi
    lea     L(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_append
    cmpq    $0, AppDb_op(%r15)
    jne     89f
    mov     S7(%rsp), %rax                  # zero bytes to a multiple of 8
    neg     %rax
    and     $7, %eax
    jz      4f
    movq    $0, (L + 32)(%rsp)
    movq    $24, L(%rsp)
    movq    $32, (L + 8)(%rsp)
    mov     %rax, (L + 16)(%rsp)
    lea     (L + 56)(%rsp), %rdi
    lea     L(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_append
    cmpq    $0, AppDb_op(%r15)
    jne     89f
4:  mov     8(%r13), %r8                    # the message's ByteList: its header, then its bytes, from 100 of the SignedBeaconBlock
    mov     16(%r8), %rax
    sub     $100, %rax
    mov     %rax, (L + 80)(%rsp)
    add     $24, %rax
    mov     %rax, (L + 64)(%rsp)
    movq    $24, (L + 72)(%rsp)
    movq    $24, L(%rsp)
    movq    $64, (L + 8)(%rsp)
    movq    $24, (L + 16)(%rsp)
    lea     (L + 56)(%rsp), %rdi
    lea     L(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_append
    cmpq    $0, AppDb_op(%r15)
    jne     89f
    mov     8(%r13), %r8
    mov     8(%r8), %rax
    lea     100(%r8,%rax), %rax
    lea     L(%rsp), %rcx
    sub     %rcx, %rax
    movq    $24, L(%rsp)
    mov     %rax, (L + 8)(%rsp)
    mov     16(%r8), %rax
    sub     $100, %rax
    mov     %rax, (L + 16)(%rsp)
    lea     (L + 56)(%rsp), %rdi
    lea     L(%rsp), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_append
    cmpq    $0, AppDb_op(%r15)
    jne     89f
    lea     (L + 56)(%rsp), %rdi
    lea     AppDb_op(%r15), %rsi
    CALL_GLOBAL lantern_shell_sync
    cmpq    $0, AppDb_op(%r15)
    jne     89f
    lea     (L + 56)(%rsp), %rdi
    CALL_GLOBAL lantern_shell_close
    ADDRESS %rdi, app_anchor_name           # over anchor.ssz, and the directory synced
    mov     $app_anchor_name_len, %esi
    lea     APP_PATH2(%rbx), %rdx
    call    app_db_file
    lea     APP_PATH(%rbx), %rdi
    lea     APP_PATH2(%rbx), %rsi
    lea     AppDb_op(%r15), %rdx
    CALL_GLOBAL lantern_shell_rename
    cmpq    $0, AppDb_op(%r15)
    jne     90f
    ADDRESS %rdi, app_anchor_name
    xor     %esi, %esi
    lea     APP_PATH(%rbx), %rdx
    call    app_db_file
    lea     APP_PATH(%rbx), %rdi
    lea     AppDb_op(%r15), %rsi
    CALL_GLOBAL lantern_shell_sync_dir
    mov     32(%rbp), %rax
    mov     %rax, AppDb_anchor_slot(%r15)
    jmp     98f
89: lea     (L + 56)(%rsp), %rdi            # the file closes
    CALL_GLOBAL lantern_shell_close
90: mov     AppDb_op(%r15), %rax            # cannot write <path>: error <n>
    mov     %rax, (L + 24)(%rsp)
    call    app_line_start
    ADDRESS %rdi, app_m_write
    mov     $app_m_write_len, %esi
    call    app_line_text
    call    app_line_path
    ADDRESS %rdi, app_m_error
    mov     $app_m_error_len, %esi
    call    app_line_text
    mov     (L + 24)(%rsp), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
98: test    %r14, %r14                      # the bytes' memory goes back
    jz      99f
    mov     %r14, (L + 24)(%rsp)
    mov     S7(%rsp), %rax
    mov     %rax, (L + 40)(%rsp)
    lea     (L + 24)(%rsp), %rdi
    lea     (L + 40)(%rsp), %rsi
    CALL_GLOBAL lantern_shell_unmap
99: LEAVE 96
END_FUNCTION app_db_state

/* L1: rax = the table entry of the BufferId rdi, 0 for id 0, or 2^64 - 1 when no entry has it. */
LOCAL_FUNCTION app_work_entry
    FRAME 0
    xor     %eax, %eax
    test    %rdi, %rdi
    jz      9f
    call    app_buf_find
    test    %rax, %rax
    jnz     9f
    mov     $-1, %rax
9:  UNFRAME 0
END_FUNCTION app_work_entry

/*
 * L2: the actions of the step, in order: BYTES_PUT, STATE_COPY, STATE_FREE and BYTES_FREE on the
 * BufferId table, WORK by app_work. rbp the next action, r12 the end, r13 its size, r14 an entry.
 */
LOCAL_FUNCTION app_actions
    ENTER 0
    mov     APP_ACTIONS(%rbx), %rbp
    mov     16(%rbp), %r12
    add     $24, %rbp
    add     %rbp, %r12
1:  cmp     %r12, %rbp
    jae     9f
    mov     (%rbp), %r13
    mov     8(%rbp), %rax
    cmp     $NODE_ACT_DB_APPEND, %rax
    jne     11f
    mov     %rbp, %rdi                      # DB_APPEND: the record in its segment file
    call    app_db_append
    jmp     8f
11: cmp     $NODE_ACT_DB_DROP, %rax
    jne     12f
    mov     %rbp, %rdi                      # DB_DROP: the segment's file goes
    call    app_db_drop
    jmp     8f
12: cmp     $NODE_ACT_DB_STATE, %rax
    jne     10f
    mov     %rbp, %rdi                      # DB_STATE: anchor.ssz
    call    app_db_state
    jmp     8f
10: cmp     $NODE_ACT_BYTES_PUT, %rax
    jne     2f
    lea     24(%rbp), %rdi                  # BYTES_PUT: a copy of the ByteList
    mov     24(%rbp), %rsi
    call    app_dup
    test    %rax, %rax
    jz      8f
    mov     %rax, %rsi
    mov     16(%rbp), %rdi
    mov     24(%rbp), %rdx
    call    app_buf_add
    jmp     8f
2:  cmp     $NODE_ACT_STATE_COPY, %rax
    jne     3f
    mov     16(%rbp), %rdi                  # STATE_COPY: a copy of the source buffer
    call    app_buf_find
    test    %rax, %rax
    jz      8f
    mov     %rax, %r14
    mov     8(%r14), %rdi
    mov     16(%r14), %rsi
    call    app_dup
    test    %rax, %rax
    jz      8f
    mov     %rax, %rsi
    mov     24(%rbp), %rdi
    mov     16(%r14), %rdx
    call    app_buf_add
    jmp     8f
3:  cmp     $NODE_ACT_STATE_FREE, %rax
    je      31f
    cmp     $NODE_ACT_BYTES_FREE, %rax
    jne     4f
31: mov     16(%rbp), %rdi                  # STATE_FREE, BYTES_FREE
    call    app_buf_drop
    jmp     8f
4:  cmp     $NODE_ACT_WORK, %rax
    jne     5f
    mov     %rbp, %rdi
    call    app_work
    jmp     8f
5:  cmp     $NODE_ACT_ENGINE, %rax
    jne     6f
    mov     %rbp, %rdi
    call    app_engine_request
    jmp     8f
6:  cmp     $NODE_ACT_DISCV5, %rax
    jne     7f
    mov     (24 + 8)(%rbp), %rax            # DISCV5: its events join discv5's
    lea     24(%rbp,%rax), %rdi
    mov     (24 + 16)(%rbp), %rsi
    call    app_dv_put
    jmp     8f
7:  cmp     $NODE_ACT_P2P_LIST, %rax
    jne     8f
    mov     APP_SHELL(%rbx), %rdi           # P2P_LIST: the shell requests of libp2p
    lea     16(%rbp), %rsi
    mov     APP_SHELL_EVENTS(%rbx), %rdx
    CALL_GLOBAL libp2p_shell_perform
8:  add     %r13, %rbp
    jmp     1b
9:  LEAVE 0
END_FUNCTION app_actions

/*
 * L2: lantern_node_step with the events of the App and the libp2p state rdi and Tick rsi (both 0 with
 * no network), again with a larger node and actions while it asks for them; then the accepted
 * events leave the queue and the actions run. rbp p2p, r12 tick, r13 the tries, r14 a size.
 */
LOCAL_FUNCTION app_step
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %r12
    xor     %r13d, %r13d
1:  mov     APP_ACTIONS(%rbx), %rax
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    sub     $16, %rsp                       # the seventh and eighth arguments: actions, result
    mov     %rax, (%rsp)
    lea     APP_RESULT(%rbx), %rax
    mov     %rax, 8(%rsp)
    mov     APP_NODE(%rbx), %rdi
    mov     APP_STORE(%rbx), %rsi
    mov     %rbp, %rdx
    mov     %r12, %rcx
    mov     APP_EVENTS(%rbx), %r8
    SCRATCH %r9
    CALL_GLOBAL lantern_node_step
    add     $16, %rsp
    test    %rax, %rax
    jz      3f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    jne     2f
    inc     %r13
    cmp     $APP_STEP_TRIES, %r13
    jae     21f
    mov     (APP_RESULT + NodeStepResult_short)(%rbx), %rax  # the buffer short of room grows
    cmp     $NODE_SHORT_NODE, %rax
    jne     11f
    xor     %edi, %edi                      # the node: the field that is short
    mov     (APP_RESULT + NodeStepResult_room)(%rbx), %rsi
    call    app_grow
    test    %rax, %rax
    jnz     21f
    jmp     1b
11: mov     $APP_ACTIONS, %r14d             # actions, or scratch: twice the room
    cmp     $NODE_SHORT_SCRATCH, %rax
    jne     12f
    mov     $APP_SCRATCH, %r14d
12: mov     8(%rbx,%r14), %r15
    shl     $1, %r15
    mov     %r14, %rdi
    call    app_unmap
    mov     %r14, %rdi
    mov     %r15, %rsi
    call    app_alloc
    test    %rax, %rax
    jz      21f
    jmp     1b
21: call    app_line_start                  # a node step: no room in buffer <short>
    ADDRESS %rdi, app_m_step
    mov     $app_m_step_len, %esi
    call    app_line_text
    ADDRESS %rdi, app_m_room
    mov     $app_m_room_len, %esi
    call    app_line_text
    mov     (APP_RESULT + NodeStepResult_short)(%rbx), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
    LEAVE 0
2:  mov     %rax, %rdx                      # a node step: status <n>
    ADDRESS %rdi, app_m_step
    mov     $app_m_step_len, %esi
    call    app_fail_status
    LEAVE 0
3:  mov     APP_EVENTS(%rbx), %rax          # the accepted events leave the queue
    mov     16(%rax), %rcx
    lea     24(%rax), %rsi
    xor     %edx, %edx
    mov     APP_RESULT(%rbx), %r8
4:  test    %r8, %r8
    jz      5f
    cmp     %rcx, %rdx
    jae     5f
    add     (%rsi,%rdx), %rdx
    dec     %r8
    jmp     4b
5:  sub     %rdx, %rcx
    mov     %rcx, 16(%rax)
    mov     %rsi, %rdi
    add     %rdx, %rsi
    mov     %rcx, %rdx
    call    lantern_copy
    call    app_actions
    LEAVE 0
END_FUNCTION app_step


/*
 * L0: rax = the bytes of the base64url text at rdi of rsi bytes (RFC 4648 section 5, with or without
 * padding), written at rdx, at most rcx; or 2^64 - 1 for a byte of no digit or too many bytes.
 * Uses rcx, rsi, rdi, r8-r11.
 */
LOCAL_FUNCTION app_base64url
    UNWIND_END_PROLOGUE
    mov     %rcx, %r11                      # the room
    xor     %r8d, %r8d                      # the bits
    xor     %ecx, %ecx                      # their count
    xor     %r9d, %r9d                      # the bytes out
1:  test    %rsi, %rsi
    jz      8f
    movzbl  (%rdi), %eax
    inc     %rdi
    dec     %rsi
    cmp     $0x3d, %eax                     # = ends the digits
    je      8f
    lea     -0x41(%rax), %r10d              # A to Z: 0 to 25
    cmp     $26, %r10d
    jb      2f
    lea     -0x61(%rax), %r10d              # a to z: 26 to 51
    cmp     $26, %r10d
    lea     26(%r10), %r10d
    jb      2f
    lea     -0x30(%rax), %r10d              # 0 to 9: 52 to 61
    cmp     $10, %r10d
    lea     52(%r10), %r10d
    jb      2f
    mov     $62, %r10d
    cmp     $0x2d, %eax                     # -
    je      2f
    mov     $63, %r10d
    cmp     $0x5f, %eax                     # _
    jne     9f
2:  shl     $6, %r8
    or      %r10, %r8
    add     $6, %ecx
    cmp     $8, %ecx
    jb      1b
    sub     $8, %ecx
    cmp     %r11, %r9
    jae     9f
    mov     %r8, %rax
    shr     %cl, %rax
    mov     %al, (%rdx,%r9)
    inc     %r9
    mov     $1, %eax                        # only the bits not yet out stay
    shl     %cl, %rax
    dec     %rax
    and     %rax, %r8
    jmp     1b
8:  mov     %r9, %rax
    ret
9:  mov     $-1, %rax
    ret
END_FUNCTION app_base64url

/*
 * L2: a NODE_EV_ENR event of each record of --boot-nodes, with commas between them; a line on
 * the standard error for one that is not "enr:" and base64url. rbp the next byte, r12 the end, r13
 * the record's start, r14 the record's number, r15 the event at APP_RECORD. Locals: L the record's length.
 */
LOCAL_FUNCTION app_boot_nodes
    ENTER 16
    lea     APP_RECORD(%rbx), %r15
    mov     (APP_OPTIONS + AppOptions_boot_nodes)(%rbx), %rbp
    add     APP_ARGS(%rbx), %rbp
    mov     (APP_OPTIONS + AppOptions_boot_nodes + 8)(%rbx), %r12
    add     %rbp, %r12
    xor     %r14d, %r14d
1:  cmp     %r12, %rbp
    jae     9f
    mov     %rbp, %r13                      # a record: to a comma or the end
2:  cmp     %r12, %rbp
    jae     3f
    cmpb    $0x2c, (%rbp)
    je      3f
    inc     %rbp
    jmp     2b
3:  mov     %rbp, %rsi
    sub     %r13, %rsi
    inc     %rbp                            # past the comma
    inc     %r14
    cmp     $4, %rsi
    jb      7f
    mov     %rsi, L(%rsp)
    mov     %r13, %rdi
    mov     $4, %esi
    ADDRESS %rdx, app_enr_prefix
    mov     $4, %ecx
    call    app_name_is
    test    %rax, %rax
    jz      7f
    lea     4(%r13), %rdi                   # its bytes, after the event and ByteList headers
    mov     L(%rsp), %rsi
    sub     $4, %rsi
    lea     48(%r15), %rdx
    mov     $APP_RECORD_MAX, %ecx
    call    app_base64url
    cmp     $-1, %rax
    je      7f
    lea     (48 + 7)(%rax), %rcx            # the event: size, NODE_EV_ENR, 0, then the ByteList
    and     $-8, %rcx
    mov     %rcx, (%r15)
    movq    $NODE_EV_ENR, 8(%r15)
    movq    $0, 16(%r15)
    lea     -24(%rcx), %rdx
    mov     %rdx, 24(%r15)
    movq    $24, 32(%r15)
    mov     %rax, 40(%r15)
    mov     %r15, %rdi
    mov     %rcx, %rsi
    call    app_event_put
    mov     40(%r15), %rax                  # and an ADD_NODE of discv5: size, kind, len, the record
    lea     (DISCV5_EV_ADD_DATA + 7)(%rax), %rcx
    and     $-8, %rcx
    mov     %rcx, 24(%r15)
    movq    $DISCV5_EVENT_ADD_NODE, 32(%r15)
    mov     %rax, (24 + DISCV5_EV_ADD_LEN)(%r15)
    lea     24(%r15), %rdi
    mov     %rcx, %rsi
    call    app_dv_put
    jmp     1b
7:  call    app_line_start                  # boot node <n>: not an enr: record
    ADDRESS %rdi, app_m_boot
    mov     $app_m_boot_len, %esi
    call    app_line_text
    mov     %r14, %rdi
    call    app_line_u64
    ADDRESS %rdi, app_m_not_enr
    mov     $app_m_not_enr_len, %esi
    call    app_line_text
    mov     $2, %edi
    call    app_line_end
    jmp     1b
9:  LEAVE 16
END_FUNCTION app_boot_nodes

/*
 * L2: the network: a secp256k1 key, the libp2p state, the shell context with a TCP listener on
 * --port, and the boot nodes: rax = 0, or 2 after a line on the standard error. rbp the config,
 * r12 the tries. Locals: L a size or a status, L+8 ShellParams, L+32 an Address, L+64 a ListenResult.
 */
/*
 * A new secp256k1 key at APP_KEY from fresh random bytes, below 2^255 and so below the order of
 * the curve (a zero key tries again, up to 4 times), and the anchor's node_id: keccak256 of its
 * point, x then y, in reverse byte order: rax = 0, or a status. r12 the tries. Locals: L the
 * public key (40), L+48 the point (64), L+112 a ByteList of the point (88), L+200 the digest (32).
 */
LOCAL_FUNCTION app_key
    ENTER 240
    xor     %r12d, %r12d
1:  lea     APP_TICK(%rbx), %rdi
    CALL_GLOBAL libp2p_shell_clock
    lea     APP_KEY(%rbx), %rdi
    lea     (APP_TICK + LIBP2P_TICK_ENTROPY)(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    andb    $0x7f, APP_KEY(%rbx)
    lea     APP_KEY(%rbx), %rdi
    lea     L(%rsp), %rsi
    CALL_GLOBAL crypto_secp256k1_public_key
    test    %rax, %rax
    jz      2f
    inc     %r12
    cmp     $4, %r12
    jb      1b
    LEAVE 240
2:  lea     L(%rsp), %rdi
    lea     (L + 48)(%rsp), %rsi
    CALL_GLOBAL crypto_secp256k1_decompress
    test    %rax, %rax
    jnz     9f
    movq    $(24 + 64), (L + 112)(%rsp)     # keccak256(x || y)
    movq    $24, (L + 120)(%rsp)
    movq    $64, (L + 128)(%rsp)
    lea     (L + 136)(%rsp), %rdi
    lea     (L + 48)(%rsp), %rsi
    mov     $64, %edx
    call    lantern_copy
    lea     (L + 112)(%rsp), %rdi
    lea     (L + 200)(%rsp), %rsi
    CALL_GLOBAL crypto_keccak256
    test    %rax, %rax
    jnz     9f
    mov     (L + 200)(%rsp), %rax           # the NodeID: the digest's bytes in reverse order
    mov     (L + 208)(%rsp), %rcx
    mov     (L + 216)(%rsp), %rdx
    mov     (L + 224)(%rsp), %rsi
    bswap   %rax
    bswap   %rcx
    bswap   %rdx
    bswap   %rsi
    mov     %rsi, (APP_ANCHOR + NodeAnchor_node_id)(%rbx)
    mov     %rdx, (APP_ANCHOR + NodeAnchor_node_id + 8)(%rbx)
    mov     %rcx, (APP_ANCHOR + NodeAnchor_node_id + 16)(%rbx)
    mov     %rax, (APP_ANCHOR + NodeAnchor_node_id + 24)(%rbx)
    xor     %eax, %eax
9:  LEAVE 240
END_FUNCTION app_key

LOCAL_FUNCTION app_net
    ENTER 112
    mov     $APP_P2P_CONFIG, %edi           # the config: the template, then the protocols
    mov     $(LIBP2P_CFG_FIXED + 24 + APP_PROTOCOLS_MAX * LIBP2P_PROTO_SIZE), %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     %rax, %rbp
    mov     %rax, %rdi
    ADDRESS %rsi, app_p2p_config
    mov     $LIBP2P_CFG_FIXED, %edx
    call    lantern_copy
    lea     LIBP2P_CFG_FIXED(%rbp), %rdi
    movq    $(24 + APP_PROTOCOLS_MAX * LIBP2P_PROTO_SIZE), (%rdi)
    movq    $24, 8(%rdi)
    movq    $0, 16(%rdi)
    lea     L(%rsp), %rsi
    CALL_GLOBAL lantern_node_protocols
    test    %rax, %rax
    jnz     96f
    mov     L(%rsp), %rax
    mov     $(LIBP2P_CFG_FIXED + 24), %ecx
    mov     %rcx, 208(%rbp)                 # protocols, protocols_count
    mov     %rax, 216(%rbp)
    imul    $LIBP2P_PROTO_SIZE, %rax, %rax
    add     %rcx, %rax
    mov     %rax, (%rbp)
    lea     16(%rbp), %rdi                  # the key of app_key
    lea     APP_KEY(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     APP_TICK(%rbx), %rdi            # the DRBG's entropy, and the time
    CALL_GLOBAL libp2p_shell_clock
    lea     48(%rbp), %rdi
    lea     (APP_TICK + LIBP2P_TICK_ENTROPY)(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     (APP_TICK + LIBP2P_TICK_NOW)(%rbx), %rax
    mov     %rax, 80(%rbp)
    mov     %rbp, %rdi                      # the libp2p state
    lea     L(%rsp), %rsi
    CALL_GLOBAL libp2p_state_size
    test    %rax, %rax
    jnz     96f
    mov     $APP_P2P, %edi
    mov     L(%rsp), %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     %rax, %rsi
    mov     %rbp, %rdi
    CALL_GLOBAL libp2p_init
    test    %rax, %rax
    jnz     96f
    mov     88(%rbp), %rax                  # the shell: a slot for each connection, and one for the execution engine
    inc     %rax
    mov     %rax, (L + 8)(%rsp)
    mov     160(%rbp), %rax
    mov     %rax, (L + 16)(%rsp)
    lea     (L + 8)(%rsp), %rdi
    lea     L(%rsp), %rsi
    CALL_GLOBAL libp2p_shell_size
    test    %rax, %rax
    jnz     96f
    mov     $APP_SHELL, %edi
    mov     L(%rsp), %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     %rax, %rsi
    lea     (L + 8)(%rsp), %rdi
    CALL_GLOBAL libp2p_shell_init
    test    %rax, %rax
    jnz     96f
    mov     $APP_SHELL_EVENTS, %edi
    mov     $APP_SHELL_EVENT_BYTES, %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    mov     160(%rbp), %rsi                 # the engine's action: a SEND of up to send_window bytes
    add     $(24 + LIBP2P_ACT_SEND_DATA + 8), %rsi
    mov     $APP_ENGINE_ACT, %edi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    movq    $4, (L + 32)(%rsp)              # listen: TCP --port on every IPv4 address
    mov     (APP_OPTIONS + AppOptions_port)(%rbx), %rax
    mov     %rax, (L + 40)(%rsp)
    movq    $0, (L + 48)(%rsp)
    movq    $0, (L + 56)(%rsp)
    mov     APP_SHELL(%rbx), %rdi
    lea     (L + 32)(%rsp), %rsi
    lea     (L + 64)(%rsp), %rdx
    CALL_GLOBAL libp2p_shell_listen
    cmpq    $0, (L + 64)(%rsp)
    je      3f
    call    app_line_start                  # listen on TCP port <p>: error <n>
    ADDRESS %rdi, app_m_listen
    mov     $app_m_listen_len, %esi
    call    app_line_text
    mov     (APP_OPTIONS + AppOptions_port)(%rbx), %rdi
    call    app_line_u64
    ADDRESS %rdi, app_m_error
    mov     $app_m_error_len, %esi
    call    app_line_text
    mov     (L + 64)(%rsp), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
    mov     $2, %eax
    LEAVE 112
3:  call    app_api_start
    test    %rax, %rax
    jnz     99f
    call    app_dv_start
    test    %rax, %rax
    jnz     99f
    call    app_boot_nodes
    call    app_line_start                  # listening on TCP port <p>
    ADDRESS %rdi, app_m_listening
    mov     $app_m_listening_len, %esi
    call    app_line_text
    mov     (APP_OPTIONS + AppOptions_port)(%rbx), %rdi
    call    app_line_u64
    mov     $1, %edi
    call    app_line_end
    xor     %eax, %eax
99: LEAVE 112
96: mov     %rax, %rdx                      # libp2p: status <n>
    ADDRESS %rdi, app_m_p2p
    mov     $app_m_p2p_len, %esi
    call    app_fail_status
    LEAVE 112
97: call    app_no_memory
    LEAVE 112
END_FUNCTION app_net

/* L0: rax = 0 and rdx = the u64 of the decimal digits rdi to rsi, one or more; else rax = 1. Uses rcx, rdi, r8. */
LOCAL_FUNCTION app_number
    UNWIND_END_PROLOGUE
    cmp     %rsi, %rdi
    jae     9f
    xor     %r8d, %r8d
1:  cmp     %rsi, %rdi
    jae     8f
    movzbl  (%rdi), %ecx
    inc     %rdi
    sub     $0x30, %ecx
    cmp     $9, %ecx
    ja      9f
    mov     %r8, %rax
    mov     $10, %edx
    mul     %rdx
    jc      9f
    add     %rcx, %rax
    jc      9f
    mov     %rax, %r8
    jmp     1b
8:  mov     %r8, %rdx
    xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION app_number

/* L0: rax = 0 and rdx = the IPv4 address of the bytes rdi to rsi, its 4 bytes in order in the low bytes; else rax = 1. Uses rcx, rdi, r8-r11. */
LOCAL_FUNCTION app_dotted
    UNWIND_END_PROLOGUE
    xor     %r8d, %r8d                      # the address
    xor     %r9d, %r9d                      # the numbers
    xor     %ecx, %ecx                      # the shift of the next one
1:  xor     %r10d, %r10d                    # a number
    xor     %r11d, %r11d                    # its digits
2:  cmp     %rsi, %rdi
    jae     3f
    movzbl  (%rdi), %eax
    cmp     $0x2e, %eax                     # .
    je      3f
    sub     $0x30, %eax
    cmp     $9, %eax
    ja      9f
    inc     %r11
    cmp     $3, %r11
    ja      9f
    lea     (%r10,%r10,4), %r10
    add     %r10, %r10
    add     %rax, %r10
    inc     %rdi
    jmp     2b
3:  test    %r11, %r11
    jz      9f
    cmp     $255, %r10
    ja      9f
    shl     %cl, %r10
    or      %r10, %r8
    add     $8, %ecx
    inc     %r9
    cmp     %rsi, %rdi
    jae     4f
    inc     %rdi                            # past the dot, to the next number
    cmp     $4, %r9
    jae     9f
    jmp     1b
4:  cmp     $4, %r9
    jne     9f
    mov     %r8, %rdx
    xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION app_dotted

/*
 * L2: with --execution-endpoint, the engine: its Address, the anchor's engine_host and the
 * jwt_secret of --jwt-secret, and NODE_FLAG_ENGINE: rax = 0, or 2 after a line on the standard
 * error. rbp the endpoint's bytes, r12 their count, r13 the colon, r14 the secret's next byte, r15
 * its end.
 */
LOCAL_FUNCTION app_engine_conf
    ENTER 0
    mov     (APP_OPTIONS + AppOptions_execution + 8)(%rbx), %r12
    test    %r12, %r12
    jz      8f
    mov     (APP_OPTIONS + AppOptions_execution)(%rbx), %rbp
    add     APP_ARGS(%rbx), %rbp
    cmp     $NODE_ENGINE_HOST_MAX, %r12     # the Host of each request
    ja      90f
    mov     %r12, (APP_ANCHOR + NodeAnchor_engine_host_len)(%rbx)
    lea     (APP_ANCHOR + NodeAnchor_engine_host)(%rbx), %rdi
    mov     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_copy
    mov     %r12, %r13                      # the last colon
1:  test    %r13, %r13
    jz      90f
    dec     %r13
    cmpb    $0x3a, (%rbp,%r13)
    jne     1b
    lea     1(%rbp,%r13), %rdi              # the port
    lea     (%rbp,%r12), %rsi
    call    app_number
    test    %rax, %rax
    jnz     90f
    test    %rdx, %rdx
    jz      90f
    cmp     $65535, %rdx
    ja      90f
    movq    $4, APP_ENGINE_ADDR(%rbx)
    mov     %rdx, (APP_ENGINE_ADDR + 8)(%rbx)
    movq    $0, (APP_ENGINE_ADDR + 16)(%rbx)
    movq    $0, (APP_ENGINE_ADDR + 24)(%rbx)
    mov     %rbp, %rdi                      # the host: localhost, or an IPv4 address
    mov     %r13, %rsi
    ADDRESS %rdx, app_localhost
    mov     $9, %ecx
    call    app_name_is
    mov     $0x0100007f, %edx               # 127.0.0.1
    test    %rax, %rax
    jnz     2f
    mov     %rbp, %rdi
    lea     (%rbp,%r13), %rsi
    call    app_dotted
    test    %rax, %rax
    jnz     90f
2:  mov     %edx, (APP_ENGINE_ADDR + 16)(%rbx)
    mov     (APP_OPTIONS + AppOptions_jwt_secret + 8)(%rbx), %rdx  # the secret's path
    test    %rdx, %rdx
    jz      91f
    cmp     $APP_PATH_MAX, %rdx
    ja      91f
    mov     %rdx, (APP_PATH + 16)(%rbx)
    lea     (APP_PATH + 24)(%rbx), %rdi
    mov     (APP_OPTIONS + AppOptions_jwt_secret)(%rbx), %rsi
    add     APP_ARGS(%rbx), %rsi
    call    lantern_copy
    call    app_read
    test    %rax, %rax
    jnz     99f
    mov     (APP_FILE + 8)(%rbx), %rax      # 64 hex digits, after 0x or not, with white space around them
    mov     16(%rax), %rcx
    lea     24(%rax), %r14
    lea     (%r14,%rcx), %r15
    call    app_space
    mov     %r15, %rax
    sub     %r14, %rax
    cmp     $2, %rax
    jb      3f
    cmpb    $0x30, (%r14)
    jne     3f
    cmpb    $0x78, 1(%r14)
    jne     3f
    add     $2, %r14
3:  xor     %r13d, %r13d
4:  cmp     $32, %r13
    jae     5f
    mov     %r15, %rax
    sub     %r14, %rax
    cmp     $2, %rax
    jb      92f
    movzbl  (%r14), %edi
    call    app_hex_digit
    mov     %rax, %rsi
    movzbl  1(%r14), %edi
    call    app_hex_digit
    mov     %rax, %rcx
    or      %rsi, %rcx
    cmp     $15, %rcx
    ja      92f
    shl     $4, %rsi
    or      %rax, %rsi
    mov     %sil, (APP_ANCHOR + NodeAnchor_jwt_secret)(%rbx,%r13)
    add     $2, %r14
    inc     %r13
    jmp     4b
5:  call    app_space
    cmp     %r15, %r14
    jne     92f
    call    app_file_free
    orq     $NODE_FLAG_ENGINE, APP_FLAGS(%rbx)
8:  xor     %eax, %eax
    LEAVE 0
90: call    app_line_start                  # the endpoint's form
    ADDRESS %rdi, app_m_endpoint
    mov     $app_m_endpoint_len, %esi
    call    app_line_text
    jmp     98f
91: call    app_line_start                  # no secret
    ADDRESS %rdi, app_m_jwt
    mov     $app_m_jwt_len, %esi
    call    app_line_text
    jmp     98f
92: call    app_file_free                   # <path>: not 32 bytes in hex
    call    app_line_start
    call    app_line_path
    ADDRESS %rdi, app_m_hex
    mov     $app_m_hex_len, %esi
    call    app_line_text
98: mov     $2, %edi
    call    app_line_end
99: mov     $2, %eax
    LEAVE 0
END_FUNCTION app_engine_conf

/* L0: r14 moves past spaces, tabs, CR and LF, to at most r15. Uses rax. */
LOCAL_FUNCTION app_space
    UNWIND_END_PROLOGUE
1:  cmp     %r15, %r14
    jae     2f
    movzbl  (%r14), %eax
    cmp     $0x20, %eax
    je      3f
    cmp     $9, %eax
    jb      2f
    cmp     $13, %eax
    ja      2f
3:  inc     %r14
    jmp     1b
2:  ret
END_FUNCTION app_space

/* L0: rax = the value of the hex digit edi, or 16 when it is not one. Uses rdi. */
LOCAL_FUNCTION app_hex_digit
    UNWIND_END_PROLOGUE
    lea     -0x30(%rdi), %eax
    cmp     $10, %eax
    jb      1f
    or      $0x20, %edi
    lea     -0x61(%rdi), %eax
    cmp     $6, %eax
    jb      2f
    mov     $16, %eax
1:  ret
2:  add     $10, %eax
    ret
END_FUNCTION app_hex_digit

/* L0: rax = the Handle of the engine's connection: the slot after libp2p's, at its generation. Uses rcx. */
LOCAL_FUNCTION app_engine_handle
    UNWIND_END_PROLOGUE
    mov     APP_P2P_CONFIG(%rbx), %rax
    mov     88(%rax), %rax                  # max_connections
    mov     APP_ENGINE_GEN(%rbx), %rcx
    shl     $32, %rcx
    or      %rcx, %rax
    ret
END_FUNCTION app_engine_handle

/*
 * L1: one shell action, the rsi bytes in the ByteList at APP_ENGINE_ACT, through
 * libp2p_shell_perform; its results join the shell's events.
 */
LOCAL_FUNCTION app_engine_perform
    FRAME 0
    mov     APP_ENGINE_ACT(%rbx), %rax
    mov     %rsi, 16(%rax)
    mov     APP_SHELL(%rbx), %rdi
    mov     %rax, %rsi
    mov     APP_SHELL_EVENTS(%rbx), %rdx
    CALL_GLOBAL libp2p_shell_perform
    UNFRAME 0
END_FUNCTION app_engine_perform

/*
 * L2: the next bytes of the request on the open connection, as far as the shell's send buffer has
 * room. rbp the action, r12 the bytes.
 */
LOCAL_FUNCTION app_engine_send
    ENTER 0
    cmpq    $2, APP_ENGINE(%rbx)
    jne     9f
    mov     APP_ENGINE_LEN(%rbx), %r12
    sub     APP_ENGINE_SENT(%rbx), %r12
    jz      9f
    mov     APP_P2P_CONFIG(%rbx), %rax
    mov     160(%rax), %rax                 # send_window
    sub     APP_ENGINE_FLIGHT(%rbx), %rax
    jbe     9f
    cmp     %rax, %r12
    jbe     1f
    mov     %rax, %r12
1:  mov     APP_ENGINE_ACT(%rbx), %rbp      # SEND: connection, count, the bytes
    add     $24, %rbp
    lea     (LIBP2P_ACT_SEND_DATA + 7)(%r12), %rax
    and     $-8, %rax
    mov     %rax, (%rbp)
    movq    $LIBP2P_ACTION_SEND, 8(%rbp)
    call    app_engine_handle
    mov     %rax, LIBP2P_ACT_CONN(%rbp)
    mov     %r12, (LIBP2P_ACT_CONN + 8)(%rbp)
    lea     LIBP2P_ACT_SEND_DATA(%rbp), %rdi
    mov     APP_ENGINE_OUT(%rbx), %rsi
    add     APP_ENGINE_SENT(%rbx), %rsi
    mov     %r12, %rdx
    call    lantern_copy
    add     %r12, APP_ENGINE_SENT(%rbx)
    add     %r12, APP_ENGINE_FLIGHT(%rbx)
    mov     %rbp, %rdi
    mov     (%rbp), %rsi
    call    app_engine_perform
9:  LEAVE 0
END_FUNCTION app_engine_send

/*
 * L2: the NODE_ACT_ENGINE rdi: its request bytes wait in APP_ENGINE_OUT; they go on the open
 * connection, or after a DIAL of the engine's Address. rbp the ByteList, r12 the count.
 */
LOCAL_FUNCTION app_engine_request
    ENTER 0
    lea     24(%rdi), %rbp
    mov     16(%rbp), %r12
    cmp     (APP_ENGINE_OUT + 8)(%rbx), %r12    # room for the request
    jbe     1f
    mov     $APP_ENGINE_OUT, %edi
    call    app_unmap
    mov     $APP_ENGINE_OUT, %edi
    mov     %r12, %rsi
    call    app_alloc
    test    %rax, %rax
    jz      9f
1:  mov     APP_ENGINE_OUT(%rbx), %rdi
    mov     8(%rbp), %rsi
    add     %rbp, %rsi
    mov     %r12, %rdx
    call    lantern_copy
    mov     %r12, APP_ENGINE_LEN(%rbx)
    movq    $0, APP_ENGINE_SENT(%rbx)
    mov     APP_ENGINE(%rbx), %rax
    cmp     $2, %rax
    jne     2f
    call    app_engine_send
    LEAVE 0
2:  test    %rax, %rax                      # no connection: a DIAL
    jnz     9f
    incq    APP_ENGINE_GEN(%rbx)
    movq    $1, APP_ENGINE(%rbx)
    movq    $0, APP_ENGINE_FLIGHT(%rbx)
    mov     APP_ENGINE_ACT(%rbx), %rbp
    add     $24, %rbp
    movq    $LIBP2P_ACT_DIAL_SIZE, (%rbp)
    movq    $LIBP2P_ACTION_DIAL, 8(%rbp)
    call    app_engine_handle
    mov     %rax, LIBP2P_ACT_CONN(%rbp)
    lea     LIBP2P_ACT_DIAL_ADDR(%rbp), %rdi
    lea     APP_ENGINE_ADDR(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     %rbp, %rdi
    mov     $LIBP2P_ACT_DIAL_SIZE, %esi
    call    app_engine_perform
9:  LEAVE 0
END_FUNCTION app_engine_request

/*
 * L2: rax = 1 when the shell event rdi is of the engine's connection, which it then takes: CONNECTED
 * opens it, SENT frees its buffer, RECEIVED gives a NODE_EV_ENGINE of the bytes, DIAL_FAILED and
 * CLOSED end it with a NODE_EV_ENGINE of failure while the node waits for an answer; else 0.
 * rbp the event, r12 its kind. Locals: L the header of an event.
 */
LOCAL_FUNCTION app_engine_event
    ENTER 48
    mov     %rdi, %rbp
    mov     8(%rbp), %r12
    cmp     $LIBP2P_EVENT_CONNECTED, %r12
    jb      8f
    cmp     $LIBP2P_EVENT_CLOSED, %r12
    ja      8f
    cmpq    $0, APP_ENGINE(%rbx)
    je      8f
    call    app_engine_handle
    cmp     LIBP2P_EV_CONN(%rbp), %rax
    jne     8f
    cmp     $LIBP2P_EVENT_CONNECTED, %r12
    jne     1f
    movq    $2, APP_ENGINE(%rbx)
    movq    $0, APP_ENGINE_FLIGHT(%rbx)
    movq    $1, APP_ENGINE_DUE(%rbx)
    jmp     9f
1:  cmp     $LIBP2P_EVENT_SENT, %r12
    jne     2f
    mov     APP_ENGINE_FLIGHT(%rbx), %rax
    sub     LIBP2P_EV_COUNT(%rbp), %rax
    jae     11f
    xor     %eax, %eax
11: mov     %rax, APP_ENGINE_FLIGHT(%rbx)
    movq    $1, APP_ENGINE_DUE(%rbx)
    jmp     9f
2:  cmp     $LIBP2P_EVENT_RECEIVED, %r12
    jne     3f
    mov     LIBP2P_EV_COUNT(%rbp), %rax     # NODE_EV_ENGINE 0: size, kind, 0, a ByteList, the bytes
    lea     (48 + 7)(%rax), %rcx
    and     $-8, %rcx
    mov     %rcx, L(%rsp)
    movq    $NODE_EV_ENGINE, (L + 8)(%rsp)
    movq    $0, (L + 16)(%rsp)
    sub     $24, %rcx
    mov     %rcx, (L + 24)(%rsp)
    movq    $24, (L + 32)(%rsp)
    mov     %rax, (L + 40)(%rsp)
    lea     L(%rsp), %rdi
    mov     $48, %esi
    call    app_event_put
    lea     LIBP2P_EV_DATA(%rbp), %rdi
    mov     LIBP2P_EV_COUNT(%rbp), %rsi
    add     $7, %rsi
    and     $-8, %rsi
    call    app_event_put
    jmp     9f
3:  movq    $0, APP_ENGINE(%rbx)            # DIAL_FAILED, CLOSED
    movq    $0, APP_ENGINE_LEN(%rbx)
    movq    $0, APP_ENGINE_SENT(%rbx)
    mov     APP_NODE(%rbx), %rax
    cmpq    $0, Node_engine_method(%rax)
    je      9f
    movq    $24, L(%rsp)                    # NODE_EV_ENGINE 1
    movq    $NODE_EV_ENGINE, (L + 8)(%rsp)
    movq    $1, (L + 16)(%rsp)
    lea     L(%rsp), %rdi
    mov     $24, %esi
    call    app_event_put
9:  mov     $1, %eax
    LEAVE 48
8:  xor     %eax, %eax
    LEAVE 48
END_FUNCTION app_engine_event

/* L1: the base64url text (RFC 4648 section 5, no padding) of the rsi bytes at rdi joins the log line. Locals: rdi, rsi, then 4 digits. */
LOCAL_FUNCTION app_line_base64url
    FRAME 48
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
1:  mov     (%rsp), %rdi
    mov     8(%rsp), %rsi
    test    %rsi, %rsi
    jz      9f
    xor     %r8d, %r8d                      # up to 3 bytes: 24 bits, from the top
    xor     %r9d, %r9d
2:  cmp     $3, %r9
    jae     3f
    test    %rsi, %rsi
    jz      3f
    movzbl  (%rdi), %eax
    inc     %rdi
    dec     %rsi
    lea     (,%r9,8), %rcx
    neg     %rcx
    add     $16, %rcx
    shl     %cl, %rax
    or      %rax, %r8
    inc     %r9
    jmp     2b
3:  mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    ADDRESS %rdx, app_base64url_digits      # 1 byte: 2 digits; 2: 3; 3: 4
    xor     %r10d, %r10d
4:  cmp     $4, %r10
    jae     5f
    imul    $6, %r10, %rcx
    neg     %rcx
    add     $18, %rcx
    mov     %r8, %rax
    shr     %cl, %rax
    and     $63, %eax
    movzbl  (%rdx,%rax), %eax
    mov     %al, 24(%rsp,%r10)
    inc     %r10
    jmp     4b
5:  lea     24(%rsp), %rdi
    lea     1(%r9), %rsi
    call    app_line_text
    jmp     1b
9:  UNFRAME 48
END_FUNCTION app_line_base64url

/* L1: the rsi bytes of the event at rdi join the next discv5 step's events, while they have room. Locals: the new count. */
LOCAL_FUNCTION app_dv_put
    FRAME 16
    mov     APP_DV_EVENTS(%rbx), %rax
    mov     16(%rax), %rcx
    lea     24(%rcx,%rsi), %rdx
    cmp     (%rax), %rdx
    ja      9f
    mov     %rdx, (%rsp)
    lea     24(%rax,%rcx), %rax
    mov     %rsi, %rdx
    mov     %rdi, %rsi
    mov     %rax, %rdi
    call    lantern_copy
    mov     (%rsp), %rdx
    sub     $24, %rdx
    mov     APP_DV_EVENTS(%rbx), %rax
    mov     %rdx, 16(%rax)
9:  UNFRAME 16
END_FUNCTION app_dv_put

/*
 * L2: discv5 with the key of libp2p: its state, with --enr-address and --port in the record, its UDP
 * socket on --port, and the record entry tcp: rax = 0, or 2 after a line on the standard error.
 * Locals: L the Config (152), then an Address and a BindResult, and the tcp event.
 */
LOCAL_FUNCTION app_dv_start
    ENTER 256
    mov     $APP_DV, %edi
    MOVQ    %rsi, DISCV5_STATE_SIZE
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     $APP_DV_SCRATCH, %edi
    MOVQ    %rsi, DISCV5_SCRATCH_SIZE
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     $APP_DV_EVENTS, %edi
    MOVQ    %rsi, APP_DV_EVENT_BYTES
    call    app_alloc
    test    %rax, %rax
    jz      97f
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    mov     $APP_DV_ACTIONS, %edi
    MOVQ    %rsi, DISCV5_ACTIONS_BASE + 64 * DISCV5_ACTIONS_PER_EVENT
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     $APP_DV_OUT, %edi
    MOVQ    %rsi, APP_DV_OUT_BYTES
    call    app_alloc
    test    %rax, %rax
    jz      97f
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    lea     L(%rsp), %rdi                   # the config: key, seq, entropy, now, endpoint, limits
    mov     $DISCV5_CFG_SIZE, %esi
    call    lantern_zero
    lea     (L + DISCV5_CFG_KEY)(%rsp), %rdi
    lea     APP_KEY(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     (L + DISCV5_CFG_SEQ)(%rsp), %rdi  # seq: the Unix time in ms, so a restart gives a later record
    CALL_GLOBAL lantern_shell_time_ms
    lea     APP_TICK(%rbx), %rdi
    CALL_GLOBAL libp2p_shell_clock
    lea     (L + DISCV5_CFG_ENTROPY)(%rsp), %rdi
    lea     (APP_TICK + LIBP2P_TICK_ENTROPY)(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     (APP_TICK + LIBP2P_TICK_NOW)(%rbx), %rax
    mov     %rax, (L + DISCV5_CFG_NOW)(%rsp)
    mov     (APP_OPTIONS + AppOptions_port)(%rbx), %rax
    mov     %rax, (L + DISCV5_CFG_PORT)(%rsp)
    mov     (APP_OPTIONS + AppOptions_enr_address)(%rbx), %rax
    test    %rax, %rax
    jz      1f
    movq    $4, (L + DISCV5_CFG_FAMILY)(%rsp)
    mov     %eax, (L + DISCV5_CFG_ADDRESS)(%rsp)
1:  movq    $2, (L + DISCV5_CFG_BUCKET_IP_LIMIT)(%rsp)
    movq    $10, (L + DISCV5_CFG_TABLE_IP_LIMIT)(%rsp)
    movq    $24, (L + DISCV5_CFG_SUBNET4)(%rsp)
    movq    $64, (L + DISCV5_CFG_SUBNET6)(%rsp)
    lea     L(%rsp), %rdi
    mov     APP_DV(%rbx), %rsi
    CALL_GLOBAL discv5_init
    test    %rax, %rax
    jnz     96f
    movq    $4, (L + 152)(%rsp)             # its UDP socket
    mov     (APP_OPTIONS + AppOptions_port)(%rbx), %rax
    mov     %rax, (L + 160)(%rsp)
    movq    $0, (L + 168)(%rsp)
    movq    $0, (L + 176)(%rsp)
    mov     APP_SHELL(%rbx), %rdi
    lea     (L + 152)(%rsp), %rsi
    lea     (L + 184)(%rsp), %rdx
    CALL_GLOBAL libp2p_shell_bind
    cmpq    $0, (L + 184 + LIBP2P_BR_ERROR)(%rsp)
    jne     95f
    mov     (L + 184 + LIBP2P_BR_SOCKET)(%rsp), %rax
    mov     %rax, APP_DV_SOCKET(%rbx)
    movq    $0, APP_DV_WAKE(%rbx)
    lea     L(%rsp), %rdi                   # the entry tcp: --port, big endian
    mov     $56, %esi
    call    lantern_zero
    movq    $56, L(%rsp)
    movq    $DISCV5_EVENT_SET_ENTRY, (L + 8)(%rsp)
    movq    $3, (L + 16)(%rsp)
    movq    $0x706374, (L + 24)(%rsp)       # tcp
    movq    $2, (L + 40)(%rsp)
    mov     (APP_OPTIONS + AppOptions_port)(%rbx), %eax
    rol     $8, %ax
    mov     %ax, (L + 48)(%rsp)
    lea     L(%rsp), %rdi
    mov     $56, %esi
    call    app_dv_put
    xor     %eax, %eax
    LEAVE 256
95: call    app_line_start                  # bind UDP port <p>: error <n>
    ADDRESS %rdi, app_m_bind
    mov     $app_m_bind_len, %esi
    call    app_line_text
    mov     (APP_OPTIONS + AppOptions_port)(%rbx), %rdi
    call    app_line_u64
    ADDRESS %rdi, app_m_error
    mov     $app_m_error_len, %esi
    call    app_line_text
    mov     (L + 184 + LIBP2P_BR_ERROR)(%rsp), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
    mov     $2, %eax
    LEAVE 256
96: mov     %rax, %rdx                      # discv5: status <n>
    ADDRESS %rdi, app_m_discv5
    mov     $app_m_discv5_len, %esi
    call    app_fail_status
    LEAVE 256
97: call    app_no_memory
    LEAVE 256
END_FUNCTION app_dv_start

/*
 * L2: rax = 1 when the shell event rdi is a DATAGRAM of discv5's socket, which then joins the next
 * discv5 step as a DATAGRAM event (the sender as an Endpoint); else 0. rbp the event. Locals: L the header.
 */
LOCAL_FUNCTION app_dv_datagram
    ENTER 64
    mov     %rdi, %rbp
    cmpq    $LIBP2P_EVENT_DATAGRAM, 8(%rbp)
    jne     8f
    mov     LIBP2P_EV_DG_SOCKET(%rbp), %rax
    cmp     APP_DV_SOCKET(%rbx), %rax
    jne     8f
    mov     LIBP2P_EV_DG_COUNT(%rbp), %rcx
    cmp     $APP_DV_DATAGRAM_MAX, %rcx
    ja      9f
    lea     (DISCV5_EV_DG_DATA + 7)(%rcx), %rax # size, DATAGRAM, the Endpoint (port, family, address), len
    and     $-8, %rax
    mov     %rax, L(%rsp)
    movq    $DISCV5_EVENT_DATAGRAM, (L + 8)(%rsp)
    lea     LIBP2P_EV_DG_ADDR(%rbp), %rdx
    mov     LIBP2P_ADDR_PORT(%rdx), %rax
    mov     %rax, (L + 16)(%rsp)
    mov     LIBP2P_ADDR_FAMILY(%rdx), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     LIBP2P_ADDR_IP(%rdx), %rax
    mov     %rax, (L + 32)(%rsp)
    mov     (LIBP2P_ADDR_IP + 8)(%rdx), %rax
    mov     %rax, (L + 40)(%rsp)
    mov     %rcx, (L + 48)(%rsp)
    mov     APP_DV_EVENTS(%rbx), %rax       # the header, then the bytes, if they fit
    mov     16(%rax), %rcx
    add     L(%rsp), %rcx
    add     $24, %rcx
    cmp     (%rax), %rcx
    ja      9f
    lea     L(%rsp), %rdi
    mov     $DISCV5_EV_DG_DATA, %esi
    call    app_dv_put
    mov     L(%rsp), %rsi
    sub     $DISCV5_EV_DG_DATA, %rsi
    lea     LIBP2P_EV_DG_DATA(%rbp), %rdi
    call    app_dv_put
9:  mov     $1, %eax
    LEAVE 64
8:  xor     %eax, %eax
    LEAVE 64
END_FUNCTION app_dv_datagram

/*
 * L2: a discv5 step when it has events or its WAKEUP is due; then its actions: SEND as the shell's
 * SEND_DATAGRAM, NODE_FOUND as a NODE_EV_ENR of the next node step, RECORD as a log line, WAKEUP
 * as the next time. rbp the next action, r12 the end, r13 the datagrams, r14 an event count.
 * Locals: L the header of an event.
 */
LOCAL_FUNCTION app_discv5
    ENTER 64
    mov     APP_DV_EVENTS(%rbx), %rax
    mov     16(%rax), %rcx
    test    %rcx, %rcx
    jnz     1f
    mov     (APP_TICK + LIBP2P_TICK_NOW)(%rbx), %rdx
    cmp     APP_DV_WAKE(%rbx), %rdx
    jb      99f
1:  xor     %r14d, %r14d                    # the action room for the events
    lea     24(%rax), %rdx
    lea     (%rdx,%rcx), %rsi
2:  cmp     %rsi, %rdx
    jae     3f
    add     (%rdx), %rdx
    inc     %r14
    jmp     2b
3:  MOVQ    %rax, DISCV5_ACTIONS_PER_EVENT
    imul    %rax, %r14
    MOVQ    %rax, DISCV5_ACTIONS_BASE
    add     %rax, %r14
    cmp     (APP_DV_ACTIONS + 8)(%rbx), %r14
    jbe     4f
    mov     $APP_DV_ACTIONS, %edi
    call    app_unmap
    mov     $APP_DV_ACTIONS, %edi
    mov     %r14, %rsi
    call    app_alloc
    test    %rax, %rax
    jz      98f
4:  mov     (APP_TICK + LIBP2P_TICK_NOW)(%rbx), %rax    # the Tick: now and fresh bytes
    mov     %rax, APP_DV_TICK(%rbx)
    lea     (APP_DV_TICK + 8)(%rbx), %rdi
    lea     (APP_TICK + LIBP2P_TICK_ENTROPY)(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     APP_DV_ACTIONS(%rbx), %rax
    mov     (APP_DV_ACTIONS + 8)(%rbx), %rcx
    mov     %rcx, (%rax)
    mov     APP_DV_SCRATCH(%rbx), %rax
    mov     (APP_DV_SCRATCH + 8)(%rbx), %rcx
    mov     %rcx, (%rax)
    mov     APP_DV(%rbx), %rdi
    lea     APP_DV_TICK(%rbx), %rsi
    mov     APP_DV_EVENTS(%rbx), %rdx
    mov     APP_DV_SCRATCH(%rbx), %rcx
    mov     APP_DV_ACTIONS(%rbx), %r8
    CALL_GLOBAL discv5_step
    mov     APP_DV_EVENTS(%rbx), %rcx
    movq    $0, 16(%rcx)
    test    %rax, %rax
    jz      5f
    mov     %rax, %rdx                      # discv5: status <n>; its events are dropped
    ADDRESS %rdi, app_m_discv5
    mov     $app_m_discv5_len, %esi
    call    app_fail_status
    mov     (APP_TICK + LIBP2P_TICK_NOW)(%rbx), %rax
    add     $1000, %rax
    mov     %rax, APP_DV_WAKE(%rbx)
    jmp     99f
5:  mov     APP_DV_ACTIONS(%rbx), %rax
    mov     8(%rax), %rbp
    add     %rax, %rbp
    mov     16(%rax), %r12
    add     %rbp, %r12
    mov     APP_DV_OUT(%rbx), %r13
6:  cmp     %r12, %rbp
    jae     90f
    mov     8(%rbp), %rax
    cmp     $DISCV5_ACTION_SEND, %rax
    jne     7f
    mov     DISCV5_ACT_SEND_LEN(%rbp), %r8  # SEND: a SEND_DATAGRAM of the socket
    lea     (LIBP2P_ACT_DG_DATA + 7)(%r8), %r9
    and     $-8, %r9
    mov     16(%r13), %rcx
    lea     24(%rcx,%r9), %rdx
    cmp     (%r13), %rdx
    ja      80f
    lea     24(%r13,%rcx), %rdi
    sub     $24, %rdx
    mov     %rdx, 16(%r13)
    mov     %r9, (%rdi)
    movq    $LIBP2P_ACTION_SEND_DATAGRAM, 8(%rdi)
    mov     APP_DV_SOCKET(%rbx), %rax
    mov     %rax, LIBP2P_ACT_DG_SOCKET(%rdi)
    mov     DISCV5_ACT_SEND_TO(%rbp), %rax  # port, family
    mov     (DISCV5_ACT_SEND_TO + 8)(%rbp), %rcx
    mov     %rcx, LIBP2P_ACT_DG_ADDR(%rdi)
    mov     %rax, (LIBP2P_ACT_DG_ADDR + 8)(%rdi)
    mov     (DISCV5_ACT_SEND_TO + 16)(%rbp), %rax
    mov     %rax, (LIBP2P_ACT_DG_ADDR + 16)(%rdi)
    mov     (DISCV5_ACT_SEND_TO + 24)(%rbp), %rax
    mov     %rax, (LIBP2P_ACT_DG_ADDR + 24)(%rdi)
    mov     %r8, LIBP2P_ACT_DG_COUNT(%rdi)
    add     $LIBP2P_ACT_DG_DATA, %rdi
    lea     DISCV5_ACT_SEND_DATA(%rbp), %rsi
    mov     %r8, %rdx
    call    lantern_copy
    jmp     80f
7:  cmp     $DISCV5_ACTION_NODE_FOUND, %rax
    jne     71f
    mov     DISCV5_ACT_FOUND_LEN(%rbp), %rax    # NODE_FOUND: NODE_EV_ENR with the record
    lea     (48 + 7)(%rax), %rcx
    and     $-8, %rcx
    mov     %rcx, L(%rsp)
    movq    $NODE_EV_ENR, (L + 8)(%rsp)
    movq    $0, (L + 16)(%rsp)
    lea     -24(%rcx), %rdx
    mov     %rdx, (L + 24)(%rsp)
    movq    $24, (L + 32)(%rsp)
    mov     %rax, (L + 40)(%rsp)
    lea     L(%rsp), %rdi
    mov     $48, %esi
    call    app_event_put
    lea     DISCV5_ACT_FOUND_DATA(%rbp), %rdi
    mov     L(%rsp), %rsi
    sub     $48, %rsi
    call    app_event_put
    jmp     80f
71: cmp     $DISCV5_ACTION_RECORD, %rax
    jne     72f
    call    app_line_clear                  # the view's enr: enr:<base64url>
    ADDRESS %rdi, app_t_enr
    mov     $4, %esi
    call    app_line_text
    lea     DISCV5_ACT_RECORD_DATA(%rbp), %rdi
    mov     DISCV5_ACT_RECORD_LEN(%rbp), %rsi
    call    app_line_base64url
    mov     APP_VIEW(%rbx), %rdi
    add     $ApiView_enr, %rdi
    mov     $512, %esi
    call    app_line_to
    call    app_line_start                  # record enr:<base64url>
    ADDRESS %rdi, app_m_record
    mov     $app_m_record_len, %esi
    call    app_line_text
    lea     DISCV5_ACT_RECORD_DATA(%rbp), %rdi
    mov     DISCV5_ACT_RECORD_LEN(%rbp), %rsi
    call    app_line_base64url
    mov     $1, %edi
    call    app_line_end
    jmp     80f
72: cmp     $DISCV5_ACTION_WAKEUP, %rax
    jne     80f
    mov     DISCV5_ACT_WAKEUP_AT(%rbp), %rax
    mov     %rax, APP_DV_WAKE(%rbx)
80: add     (%rbp), %rbp
    jmp     6b
90: mov     APP_DV_OUT(%rbx), %r13          # the datagrams go out
    cmpq    $0, 16(%r13)
    je      99f
    mov     APP_SHELL(%rbx), %rdi
    mov     %r13, %rsi
    mov     APP_SHELL_EVENTS(%rbx), %rdx
    CALL_GLOBAL libp2p_shell_perform
    mov     APP_DV_OUT(%rbx), %r13
    movq    $0, 16(%r13)
    jmp     99f
98: mov     APP_DV_EVENTS(%rbx), %rax
    movq    $0, 16(%rax)
99: LEAVE 64
END_FUNCTION app_discv5

/*
 * L2: rax = the base58btc text of the rsi bytes at rdi (at most 48), written at rdx: a 1 for each
 * leading zero byte, then the digits. rcx: a work area of 72 bytes. r12 the bytes, r13 their count,
 * r14 the text, r15 the work area, rbp the leading zero bytes.
 */
LOCAL_FUNCTION app_base58
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, %r14
    mov     %rcx, %r15
    mov     $58, %r11d
    xor     %ebp, %ebp                      # the leading zero bytes
1:  cmp     %r13, %rbp
    jae     2f
    cmpb    $0, (%r12,%rbp)
    jne     2f
    inc     %rbp
    jmp     1b
2:  xor     %r8d, %r8d                      # the digits so far, least significant at r15 + 71
    mov     %rbp, %r9
3:  cmp     %r13, %r9                       # each byte: digits * 256 + byte
    jae     6f
    movzbl  (%r12,%r9), %eax
    xor     %r10d, %r10d
4:  cmp     %r8, %r10
    jae     5f
    mov     $71, %ecx
    sub     %r10, %rcx
    movzbl  (%r15,%rcx), %esi
    shl     $8, %esi
    add     %rsi, %rax
    xor     %edx, %edx
    div     %r11
    mov     %dl, (%r15,%rcx)
    inc     %r10
    jmp     4b
5:  test    %rax, %rax
    jz      51f
    xor     %edx, %edx
    div     %r11
    mov     $71, %ecx
    sub     %r8, %rcx
    mov     %dl, (%r15,%rcx)
    inc     %r8
    jmp     5b
51: inc     %r9
    jmp     3b
6:  xor     %eax, %eax                      # the text: the ones, then the digits
    ADDRESS %rsi, app_base58_digits
7:  test    %rbp, %rbp
    jz      8f
    movzbl  (%rsi), %ecx
    mov     %cl, (%r14,%rax)
    inc     %rax
    dec     %rbp
    jmp     7b
8:  test    %r8, %r8
    jz      9f
    mov     $72, %ecx
    sub     %r8, %rcx
    movzbl  (%r15,%rcx), %ecx
    movzbl  (%rsi,%rcx), %ecx
    mov     %cl, (%r14,%rax)
    inc     %rax
    dec     %r8
    jmp     8b
9:  LEAVE 0
END_FUNCTION app_base58

/* L0: the log line becomes empty: the text helpers then build a text in it. */
LOCAL_FUNCTION app_line_clear
    UNWIND_END_PROLOGUE
    movq    $0, (APP_LINE + 16)(%rbx)
    ret
END_FUNCTION app_line_clear

/* L1: the bytes of the log line go to the text field at rdi of the view (its length, then its bytes, at most rsi). */
LOCAL_FUNCTION app_line_to
    FRAME 0
    mov     (APP_LINE + 16)(%rbx), %rdx
    cmp     %rsi, %rdx
    jbe     1f
    mov     %rsi, %rdx
1:  mov     %rdx, (%rdi)
    add     $8, %rdi
    lea     (APP_LINE + 24)(%rbx), %rsi
    call    lantern_copy
    UNFRAME 0
END_FUNCTION app_line_to

/* L1: the IPv4 address rdi (its bytes in order in the low bytes) joins the line in dotted decimal. Locals: the address, the count. */
LOCAL_FUNCTION app_line_ip4
    FRAME 16
    mov     %rdi, (%rsp)
    movq    $0, 8(%rsp)
1:  movzbl  (%rsp), %edi
    call    app_line_u64
    incq    8(%rsp)
    shrq    $8, (%rsp)
    cmpq    $4, 8(%rsp)
    jae     2f
    ADDRESS %rdi, app_t_dot
    mov     $1, %esi
    call    app_line_text
    jmp     1b
2:  UNFRAME 16
END_FUNCTION app_line_ip4

/* L1: a multiaddr /ip4/<--enr-address>/<rdi: tcp or udp text>/<--port>/p2p/<peer id> to the view's field at rsi, or length 0 with no --enr-address. Locals: rdi, rsi. */
LOCAL_FUNCTION app_multiaddr
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    cmpq    $0, (APP_OPTIONS + AppOptions_enr_address)(%rbx)
    jne     1f
    movq    $0, (%rsi)
    jmp     9f
1:  call    app_line_clear
    ADDRESS %rdi, app_t_ip4
    mov     $5, %esi
    call    app_line_text
    mov     (APP_OPTIONS + AppOptions_enr_address)(%rbx), %rdi
    call    app_line_ip4
    mov     (%rsp), %rdi
    mov     $5, %esi
    call    app_line_text
    mov     (APP_OPTIONS + AppOptions_port)(%rbx), %rdi
    call    app_line_u64
    ADDRESS %rdi, app_t_p2p
    mov     $5, %esi
    call    app_line_text
    mov     APP_VIEW(%rbx), %rax
    lea     (ApiView_peer_id + 8)(%rax), %rdi
    mov     ApiView_peer_id(%rax), %rsi
    call    app_line_text
    mov     8(%rsp), %rdi
    mov     $128, %esi
    call    app_line_to
9:  UNFRAME 16
END_FUNCTION app_multiaddr

/*
 * L2: the Beacon API: a shell context that listens on --http-port, its buffers, and the view's
 * fixed values: the peer id, the addresses, the version, and the anchor's header: rax = 0, or 2
 * after a line on the standard error. Locals: L ShellParams or an Address, L+32 a ListenResult
 * or the public key, L+80 the peer id's multihash, L+128 base58's work area.
 */
LOCAL_FUNCTION app_api_start
    ENTER 208
    movq    $APP_API_SLOTS_MAX, L(%rsp)
    movq    $APP_API_SEND_WINDOW, (L + 8)(%rsp)
    lea     L(%rsp), %rdi
    lea     (L + 32)(%rsp), %rsi
    CALL_GLOBAL libp2p_shell_size
    test    %rax, %rax
    jnz     97f
    mov     $APP_API_SHELL, %edi
    mov     (L + 32)(%rsp), %rsi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     %rax, %rsi
    lea     L(%rsp), %rdi
    CALL_GLOBAL libp2p_shell_init
    test    %rax, %rax
    jnz     97f
    mov     $APP_API_EVENTS, %edi
    mov     $APP_API_EVENT_BYTES, %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    mov     $APP_API_ACT, %edi
    MOVQ    %rsi, 24 + APP_API_SLOTS_MAX * (64 + APP_API_OUT_BYTES)
    call    app_alloc
    test    %rax, %rax
    jz      97f
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    mov     $APP_API_OUT, %edi
    mov     $(24 + APP_API_OUT_BYTES), %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     $APP_API_REQ, %edi
    MOVQ    %rsi, APP_API_SLOTS_MAX * (24 + APP_API_REQ_BYTES)
    call    app_alloc
    test    %rax, %rax
    jz      97f
    mov     $APP_VIEW, %edi
    mov     $4096, %esi
    call    app_alloc
    test    %rax, %rax
    jz      97f
    movq    $4, L(%rsp)                     # listen: TCP --http-port on every IPv4 address
    mov     (APP_OPTIONS + AppOptions_http_port)(%rbx), %rax
    mov     %rax, (L + 8)(%rsp)
    movq    $0, (L + 16)(%rsp)
    movq    $0, (L + 24)(%rsp)
    mov     APP_API_SHELL(%rbx), %rdi
    lea     L(%rsp), %rsi
    lea     (L + 32)(%rsp), %rdx
    CALL_GLOBAL libp2p_shell_listen
    cmpq    $0, (L + 32)(%rsp)
    jne     96f
    lea     APP_KEY(%rbx), %rdi             # the peer id: base58btc of the identity multihash of the key
    lea     (L + 32)(%rsp), %rsi
    CALL_GLOBAL crypto_secp256k1_public_key
    test    %rax, %rax
    jnz     97f
    MOVQ    %rax, 0x0000211202082500
    mov     %rax, (L + 80)(%rsp)
    lea     (L + 86)(%rsp), %rdi
    lea     (L + 32)(%rsp), %rsi
    mov     $33, %edx
    call    lantern_copy
    lea     (L + 80)(%rsp), %rdi
    mov     $39, %esi
    mov     APP_VIEW(%rbx), %rdx
    add     $(ApiView_peer_id + 8), %rdx
    lea     (L + 128)(%rsp), %rcx
    call    app_base58
    mov     APP_VIEW(%rbx), %rcx
    mov     %rax, ApiView_peer_id(%rcx)
    mov     APP_VIEW(%rbx), %rdi            # the version
    add     $ApiView_version, %rdi
    movq    $app_version_text_len, (%rdi)
    add     $8, %rdi
    ADDRESS %rsi, app_version_text
    mov     $app_version_text_len, %edx
    call    lantern_copy
    ADDRESS %rdi, app_t_tcp                 # the addresses
    mov     APP_VIEW(%rbx), %rsi
    add     $ApiView_p2p_address, %rsi
    call    app_multiaddr
    ADDRESS %rdi, app_t_udp
    mov     APP_VIEW(%rbx), %rsi
    add     $ApiView_discovery_address, %rsi
    call    app_multiaddr
    mov     APP_STATE(%rbx), %rsi           # the anchor's header: its state's latest_block_header, the block's state_root
    add     $NODE_STATE_HEADER, %rsi
    lea     APP_ANCHOR_HEADER(%rbx), %rdi
    mov     $112, %edx
    call    lantern_copy
    lea     (APP_ANCHOR_HEADER + 48)(%rbx), %rdi
    mov     APP_BLOCK(%rbx), %rsi
    add     $NODE_BLOCK_STATE_ROOT, %rsi
    mov     $32, %edx
    call    lantern_copy
    call    app_line_start                  # Beacon API on TCP port <p>, peer id <id>
    ADDRESS %rdi, app_m_api
    mov     $app_m_api_len, %esi
    call    app_line_text
    mov     (APP_OPTIONS + AppOptions_http_port)(%rbx), %rdi
    call    app_line_u64
    ADDRESS %rdi, app_m_peer_id
    mov     $app_m_peer_id_len, %esi
    call    app_line_text
    mov     APP_VIEW(%rbx), %rax
    lea     (ApiView_peer_id + 8)(%rax), %rdi
    mov     ApiView_peer_id(%rax), %rsi
    call    app_line_text
    mov     $1, %edi
    call    app_line_end
    xor     %eax, %eax
    LEAVE 208
96: call    app_line_start                  # listen on TCP port <p>: error <n>
    ADDRESS %rdi, app_m_listen
    mov     $app_m_listen_len, %esi
    call    app_line_text
    mov     (APP_OPTIONS + AppOptions_http_port)(%rbx), %rdi
    call    app_line_u64
    ADDRESS %rdi, app_m_error
    mov     $app_m_error_len, %esi
    call    app_line_text
    mov     (L + 32)(%rsp), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
    mov     $2, %eax
    LEAVE 208
97: call    app_no_memory
    LEAVE 208
END_FUNCTION app_api_start

/*
 * L2: the view's values of the node now: genesis, the head and its header, the head state's
 * checkpoints, the clock's slot, sync, peers and MetaData. rbp the view, r12 the head's NodeBlock,
 * r13 a count or a buffer, r14 the header.
 */
LOCAL_FUNCTION app_view_fill
    ENTER 0
    mov     APP_VIEW(%rbx), %rbp
    mov     APP_STORE(%rbx), %rax           # genesis
    mov     Store_genesis_time_ms(%rax), %rax
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    mov     %rax, ApiView_genesis_time(%rbp)
    lea     ApiView_genesis_validators_root(%rbp), %rdi
    lea     (APP_ANCHOR + NodeAnchor_genesis_validators_root)(%rbx), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     (APP_CONFIG + CONFIG_GENESIS_FORK_VERSION)(%rbx), %rax
    mov     %rax, ApiView_genesis_fork_version(%rbp)
    mov     APP_NODE(%rbx), %rax            # the head's NodeBlock
    mov     Node_blocks(%rax), %r12
    add     %rax, %r12
    mov     (Node_blocks + 8)(%rax), %r13
1:  test    %r13, %r13
    jz      90f
    mov     %r12, %rdi
    mov     APP_NODE(%rbx), %rsi
    add     $Node_head_root, %rsi
    call    app_same32
    test    %rax, %rax
    jnz     2f
    add     $NodeBlock__mem, %r12
    dec     %r13
    jmp     1b
2:  mov     NodeBlock_slot(%r12), %rax
    mov     %rax, ApiView_head_slot(%rbp)
    lea     ApiView_head_root(%rbp), %rdi
    mov     %r12, %rsi
    mov     $32, %edx
    call    lantern_copy
    lea     APP_ANCHOR_HEADER(%rbx), %r14   # the header: the anchor's, or the block's
    mov     NodeBlock_data_id(%r12), %rdi
    test    %rdi, %rdi
    jz      31f
    call    app_buf_find
    test    %rax, %rax
    jz      3f
    jmp     32f
31: mov     APP_NODE(%rbx), %rdi            # no bytes: the block's record in the Db, when it holds one
    testq   $NODE_FLAG_DB, Node_flags(%rdi)
    jz      3f
    add     Node_db(%rdi), %rdi
    mov     %r12, %rsi
    lea     APP_HEADER(%rbx), %rdx
    CALL_GLOBAL lantern_db_find_root
    mov     APP_HEADER(%rbx), %rdx
    mov     APP_NODE(%rbx), %rax
    add     Node_db(%rax), %rax
    cmp     Db_end_slot(%rax), %rdx
    jae     3f
    mov     %rdx, %rcx
    sub     Db_first_slot(%rax), %rcx
    jb      3f
    imul    $DbSlot__mem, %rcx, %rcx
    add     Db_slots(%rax), %rcx
    mov     DbSlot_block(%rax,%rcx), %rdi
    test    %rdi, %rdi
    jz      3f
    dec     %rdi
    shr     $DB_SEGMENT_SHIFT, %rdx
    shl     $48, %rdx
    or      %rdx, %rdi
    bts     $63, %rdi
    call    app_work_data
    cmp     $-1, %rax
    je      3f
32: mov     8(%rax), %r13
    mov     NodeBlock_slot(%r12), %rdi
    lea     APP_CONFIG(%rbx), %rsi
    call    app_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    SCRATCH %rsi
    lea     APP_HEADER(%rbx), %rdx
    FORK_CALL node_block_header
    test    %rax, %rax
    jnz     3f
    lea     APP_HEADER(%rbx), %r14
3:  mov     8(%r14), %rax
    mov     %rax, ApiView_proposer_index(%rbp)
    lea     ApiView_parent_root(%rbp), %rdi
    lea     16(%r14), %rsi
    mov     $(32 * 3), %edx
    call    lantern_copy
    lea     ApiView_signature(%rbp), %rdi
    lea     112(%r14), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     NodeBlock_state_id(%r12), %rdi  # the head state's checkpoints
    call    app_buf_find
    test    %rax, %rax
    jz      4f
    mov     8(%rax), %r13
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     APP_CONFIG(%rbx), %rsi
    call    app_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    lea     ApiView_previous_justified(%rbp), %rsi
    FORK_CALL node_state_checkpoints
4:  xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%r12)
    sete    %al
    mov     %rax, ApiView_is_optimistic(%rbp)
90: mov     APP_STORE(%rbx), %rdi           # the clock, sync, peers, MetaData
    call    app_store_slot
    mov     %rax, ApiView_current_slot(%rbp)
    mov     %rax, %rdi
    lea     APP_CONFIG(%rbx), %rsi
    call    app_fork
    mov     %rax, ApiView_fork(%rbp)
    mov     APP_NODE(%rbx), %rcx
    mov     Node_flags(%rcx), %rax
    shr     $3, %rax                        # NODE_FLAG_SYNCING
    and     $1, %eax
    mov     %rax, ApiView_is_syncing(%rbp)
    movq    $0, ApiView_el_offline(%rbp)
    mov     (Node_peers + 8)(%rcx), %rax
    mov     %rax, ApiView_peers(%rbp)
    mov     Node_metadata_seq(%rcx), %rax
    mov     %rax, ApiView_seq_number(%rbp)
    movq    $0, ApiView_attnets(%rbp)
    movq    $0, ApiView_syncnets(%rbp)
    mov     (APP_CONFIG + CONFIG_CUSTODY_REQUIREMENT)(%rbx), %rax
    mov     %rax, ApiView_custody_group_count(%rbp)
    LEAVE 0
END_FUNCTION app_view_fill

/* L0: rax = 1 when the 32 bytes at rdi are those at rsi, else 0. */
LOCAL_FUNCTION app_same32
    UNWIND_END_PROLOGUE
    mov     (%rdi), %rax
    cmp     (%rsi), %rax
    jne     1f
    mov     8(%rdi), %rax
    cmp     8(%rsi), %rax
    jne     1f
    mov     16(%rdi), %rax
    cmp     16(%rsi), %rax
    jne     1f
    mov     24(%rdi), %rax
    cmp     24(%rsi), %rax
    jne     1f
    mov     $1, %eax
    ret
1:  xor     %eax, %eax
    ret
END_FUNCTION app_same32

/* L1: an action of rsi bytes, the rsi bytes at rdi, joins the Beacon API's shell actions, when it fits. */
LOCAL_FUNCTION app_api_act
    FRAME 0
    mov     APP_API_ACT(%rbx), %rax
    mov     16(%rax), %rcx
    lea     24(%rcx,%rsi), %rdx
    cmp     (%rax), %rdx
    ja      9f
    sub     $24, %rdx
    mov     %rdx, 16(%rax)
    lea     24(%rax,%rcx), %rax
    mov     %rsi, %rdx
    mov     %rdi, %rsi
    mov     %rax, %rdi
    call    lantern_copy
9:  UNFRAME 0
END_FUNCTION app_api_act

/* L1: a CLOSE of the connection rdi joins the shell actions. Locals: the action. */
LOCAL_FUNCTION app_api_close
    FRAME 32
    movq    $LIBP2P_ACT_CLOSE_SIZE, (%rsp)
    movq    $LIBP2P_ACTION_CLOSE, 8(%rsp)
    mov     %rdi, LIBP2P_ACT_CONN(%rsp)
    mov     %rsp, %rdi
    mov     $LIBP2P_ACT_CLOSE_SIZE, %esi
    call    app_api_act
    UNFRAME 32
END_FUNCTION app_api_close

/*
 * L2: the Beacon API's sockets, without waiting: ACCEPTED takes a free slot (ADOPT) or a REFUSE,
 * RECEIVED joins its slot's request, then a complete request gets its answer (SEND, CLOSE),
 * CLOSED frees the slot; then the shell actions go out. rbp the next event, r12 the end, r13 a
 * slot's entry, r14 its request ByteList, r15 the connection. Locals: L the wait, L+8 an action.
 */
LOCAL_FUNCTION app_api_poll
    ENTER 64
    movq    $0, L(%rsp)
    mov     APP_API_SHELL(%rbx), %rdi
    lea     L(%rsp), %rsi
    mov     APP_API_EVENTS(%rbx), %rdx
    CALL_GLOBAL libp2p_shell_wait
    mov     APP_API_EVENTS(%rbx), %rax
    mov     8(%rax), %rbp
    add     %rax, %rbp
    mov     16(%rax), %r12
    add     %rbp, %r12
1:  cmp     %r12, %rbp
    jae     80f
    mov     8(%rbp), %rax
    cmp     $LIBP2P_EVENT_ACCEPTED, %rax
    jne     3f
    lea     APP_API_SLOTS(%rbx), %r13       # ACCEPTED: a free slot, or REFUSE
    xor     %ecx, %ecx
2:  cmp     $APP_API_SLOTS_MAX, %rcx
    jae     21f
    cmpq    $0, 8(%r13)
    je      22f
    add     $16, %r13
    inc     %rcx
    jmp     2b
21: movq    $LIBP2P_ACT_REFUSE_SIZE, (L + 8)(%rsp)
    movq    $LIBP2P_ACTION_REFUSE, (L + 16)(%rsp)
    mov     LIBP2P_EV_TOKEN(%rbp), %rax
    mov     %rax, (L + 8 + LIBP2P_ACT_TOKEN)(%rsp)
    lea     (L + 8)(%rsp), %rdi
    mov     $LIBP2P_ACT_REFUSE_SIZE, %esi
    call    app_api_act
    jmp     79f
22: mov     (%r13), %rax                    # a new generation, its request empty
    inc     %rax
    mov     %rax, (%r13)
    movq    $1, 8(%r13)
    mov     %rax, %r15
    shl     $32, %r15
    or      %rcx, %r15
    imul    $(24 + APP_API_REQ_BYTES), %rcx, %r14
    add     APP_API_REQ(%rbx), %r14
    movq    $(24 + APP_API_REQ_BYTES), (%r14)
    movq    $24, 8(%r14)
    movq    $0, 16(%r14)
    movq    $LIBP2P_ACT_ADOPT_SIZE, (L + 8)(%rsp)
    movq    $LIBP2P_ACTION_ADOPT, (L + 16)(%rsp)
    mov     LIBP2P_EV_TOKEN(%rbp), %rax
    mov     %rax, (L + 8 + LIBP2P_ACT_TOKEN)(%rsp)
    mov     %r15, (L + 8 + LIBP2P_ACT_TOKEN + 8)(%rsp)
    lea     (L + 8)(%rsp), %rdi
    mov     $LIBP2P_ACT_ADOPT_SIZE, %esi
    call    app_api_act
    jmp     79f
3:  cmp     $LIBP2P_EVENT_RECEIVED, %rax
    je      31f
    cmp     $LIBP2P_EVENT_CLOSED, %rax
    jne     79f
31: mov     LIBP2P_EV_CONN(%rbp), %r15      # the slot of the connection, at its generation
    mov     %r15d, %ecx
    cmp     $APP_API_SLOTS_MAX, %rcx
    jae     79f
    mov     %rcx, %r13
    shl     $4, %r13
    lea     APP_API_SLOTS(%rbx,%r13), %r13
    mov     %r15, %rdx
    shr     $32, %rdx
    cmp     (%r13), %rdx
    jne     79f
    cmp     $LIBP2P_EVENT_CLOSED, %rax
    jne     4f
    movq    $0, 8(%r13)                     # CLOSED: the slot is free
    jmp     79f
4:  cmpq    $1, 8(%r13)                     # RECEIVED, while reading: the bytes join the request
    jne     79f
    imul    $(24 + APP_API_REQ_BYTES), %rcx, %r14
    add     APP_API_REQ(%rbx), %r14
    mov     16(%r14), %rcx
    mov     LIBP2P_EV_COUNT(%rbp), %rdx
    lea     (%rcx,%rdx), %rax
    cmp     $APP_API_REQ_BYTES, %rax
    ja      6f
    mov     %rax, 16(%r14)
    lea     24(%r14,%rcx), %rdi
    lea     LIBP2P_EV_DATA(%rbp), %rsi
    call    lantern_copy
    call    app_view_fill                   # the answer, once the request's head is complete
    mov     APP_API_OUT(%rbx), %rax
    movq    $(24 + APP_API_OUT_BYTES), (%rax)
    mov     %r14, %rdi
    mov     APP_VIEW(%rbx), %rsi
    mov     APP_API_OUT(%rbx), %rdx
    CALL_GLOBAL lantern_api_answer
    cmp     $LANTERN_HTTP_MORE, %rax
    je      79f
    test    %rax, %rax
    jnz     6f
    mov     APP_API_OUT(%rbx), %rsi         # SEND the response: size, kind, connection, count, the bytes
    mov     16(%rsi), %rcx
    lea     (LIBP2P_ACT_SEND_DATA + 7)(%rcx), %r8
    and     $-8, %r8
    mov     APP_API_ACT(%rbx), %r9
    mov     16(%r9), %rdx
    lea     24(%rdx,%r8), %rax
    cmp     (%r9), %rax
    ja      6f
    sub     $24, %rax
    mov     %rax, 16(%r9)
    lea     24(%r9,%rdx), %rdi
    mov     %r8, (%rdi)
    movq    $LIBP2P_ACTION_SEND, 8(%rdi)
    mov     %r15, LIBP2P_ACT_CONN(%rdi)
    mov     %rcx, (LIBP2P_ACT_CONN + 8)(%rdi)
    add     $LIBP2P_ACT_SEND_DATA, %rdi
    add     $24, %rsi
    mov     %rcx, %rdx
    call    lantern_copy
6:  movq    $2, 8(%r13)                     # then CLOSE
    mov     %r15, %rdi
    call    app_api_close
79: add     (%rbp), %rbp
    jmp     1b
80: mov     APP_API_EVENTS(%rbx), %rax      # the actions go out; their results come at the next poll
    movq    $0, 16(%rax)
    mov     APP_API_ACT(%rbx), %rsi
    cmpq    $0, 16(%rsi)
    je      9f
    mov     APP_API_SHELL(%rbx), %rdi
    mov     APP_API_EVENTS(%rbx), %rdx
    CALL_GLOBAL libp2p_shell_perform
    mov     APP_API_ACT(%rbx), %rax
    movq    $0, 16(%rax)
9:  LEAVE 64
END_FUNCTION app_api_poll

/* L2: each event of the shell becomes a NODE_EV_P2P event of the next step, but those of the engine's connection. rbp the next event, r12 the end. Locals: L the header. */
LOCAL_FUNCTION app_p2p_events
    ENTER 16
    mov     APP_SHELL_EVENTS(%rbx), %rax
    mov     8(%rax), %rbp
    add     %rax, %rbp
    mov     16(%rax), %r12
    add     %rbp, %r12
1:  cmp     %r12, %rbp
    jae     9f
    mov     %rbp, %rdi                      # a datagram of discv5
    call    app_dv_datagram
    test    %rax, %rax
    jnz     2f
    mov     %rbp, %rdi                      # the engine's connection
    call    app_engine_event
    test    %rax, %rax
    jnz     2f
    mov     (%rbp), %rax
    add     $16, %rax
    mov     %rax, L(%rsp)
    movq    $NODE_EV_P2P, (L + 8)(%rsp)
    lea     L(%rsp), %rdi
    mov     $16, %esi
    call    app_event_put
    mov     %rbp, %rdi
    mov     (%rbp), %rsi
    call    app_event_put
2:  add     (%rbp), %rbp
    jmp     1b
9:  mov     APP_SHELL_EVENTS(%rbx), %rax
    movq    $0, 16(%rax)
    cmpq    $0, APP_ENGINE_DUE(%rbx)        # then more bytes of the request
    je      10f
    movq    $0, APP_ENGINE_DUE(%rbx)
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
1:  lea     APP_TICK(%rbx), %rdi            # the clocks
    CALL_GLOBAL libp2p_shell_clock
    lea     L(%rsp), %rdi
    CALL_GLOBAL lantern_shell_time_ms
    movq    $24, (L + 16)(%rsp)             # NODE_EV_TICK of the Unix time
    movq    $NODE_EV_TICK, (L + 24)(%rsp)
    mov     L(%rsp), %rax
    mov     %rax, (L + 32)(%rsp)
    lea     (L + 16)(%rsp), %rdi
    mov     $24, %esi
    call    app_event_put
    call    app_p2p_events
    mov     APP_P2P(%rbx), %rdi
    lea     APP_TICK(%rbx), %rsi
    call    app_step
    call    app_discv5
    mov     APP_STORE(%rbx), %rdi           # a line at each new slot
    call    app_store_slot
    cmp     APP_LAST_SLOT(%rbx), %rax
    je      3f
    mov     %rax, APP_LAST_SLOT(%rbx)
    mov     %rax, (L + 8)(%rsp)
    call    app_line_start                  # slot <s>, head 0x<root>, finalized epoch <e>
    ADDRESS %rdi, app_m_slot
    mov     $app_m_slot_len, %esi
    call    app_line_text
    mov     (L + 8)(%rsp), %rdi
    call    app_line_u64
    ADDRESS %rdi, app_m_head
    mov     $app_m_head_len, %esi
    call    app_line_text
    mov     APP_NODE(%rbx), %rdi
    add     $Node_head_root, %rdi
    mov     $8, %esi
    call    app_line_hex
    ADDRESS %rdi, app_m_finalized
    mov     $app_m_finalized_len, %esi
    call    app_line_text
    mov     APP_STORE(%rbx), %rax
    mov     Store_finalized_checkpoint(%rax), %rdi
    call    app_line_u64
    mov     $1, %edi
    call    app_line_end
3:  mov     APP_NODE(%rbx), %rax            # a line when the count of connected peers changes
    mov     (Node_peers + 8)(%rax), %rax
    cmp     APP_PEERS(%rbx), %rax
    je      4f
    mov     %rax, APP_PEERS(%rbx)
    call    app_line_start                  # peers <n>
    ADDRESS %rdi, app_m_peers
    mov     $app_m_peers_len, %esi
    call    app_line_text
    mov     APP_PEERS(%rbx), %rdi
    call    app_line_u64
    mov     $1, %edi
    call    app_line_end
4:  mov     (APP_RESULT + 8)(%rbx), %rax    # the wait: to the node's or discv5's wakeup, at most APP_WAIT_MS
    mov     APP_DV_WAKE(%rbx), %rcx
    cmp     %rax, %rcx
    jae     31f
    mov     %rcx, %rax
31: sub     (APP_TICK + LIBP2P_TICK_NOW)(%rbx), %rax
    ja      32f
    xor     %eax, %eax
32: cmp     $APP_WAIT_MS, %rax
    jb      33f
    mov     $APP_WAIT_MS, %eax
33: mov     %rax, (L + 8)(%rsp)
    mov     APP_SHELL(%rbx), %rdi
    lea     (L + 8)(%rsp), %rsi
    mov     APP_SHELL_EVENTS(%rbx), %rdx
    CALL_GLOBAL libp2p_shell_wait
    call    app_api_poll
    jmp     1b
END_FUNCTION app_loop

/* (args): docs/reference/app.md. rbx the App, rbp args. Locals: L the fault. */
FUNCTION lantern_app_main
    ENTER 16
    mov     %rdi, %rbp
    mov     $APP_SIZE, %edi
    call    app_map
    test    %rax, %rax
    jz      9f
    mov     %rax, %rbx
    mov     %rbp, APP_ARGS(%rbx)
    movq    $(24 + APP_LINE_MAX), APP_LINE(%rbx)
    movq    $24, (APP_LINE + 8)(%rbx)
    movq    $(24 + APP_PATH_MAX), APP_PATH(%rbx)
    movq    $24, (APP_PATH + 8)(%rbx)
    mov     %rbp, %rdi
    lea     APP_OPTIONS(%rbx), %rsi
    lea     L(%rsp), %rdx
    CALL_GLOBAL lantern_app_options
    test    %rax, %rax
    jz      1f
    call    app_line_start                  # faulty option at argument <n>
    ADDRESS %rdi, app_m_option
    mov     $app_m_option_len, %esi
    call    app_line_text
    mov     L(%rsp), %rdi
    call    app_line_u64
    mov     $2, %edi
    call    app_line_end
    mov     $1, %eax
    LEAVE 16
1:  call    app_start
    test    %rax, %rax
    jnz     8f
    call    app_net
    test    %rax, %rax
    jnz     8f
    call    app_loop
8:  LEAVE 16
9:  mov     $2, %eax
    LEAVE 16
END_FUNCTION lantern_app_main
