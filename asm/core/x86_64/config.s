/*
 * The network config file, x86-64: in the common object. Requirements: docs/reference/config.md.
 */

/* A record of CONFIG_KEYS: the name's length, its CONFIG_* offset, its kind, then the name in CONFIG_KEY_NAME_MAX bytes. */
.set CONFIG_KEY_BYTES, 24 + CONFIG_KEY_NAME_MAX
.macro CONFIG_KEY_RECORD name, offset, kind
    .quad 72f - 71f, \offset, \kind
71: .ascii "\name"
72: .space CONFIG_KEY_NAME_MAX - (72b - 71b)
.endm

    RODATA
    .p2align 3
config_keys:
    CONFIG_KEYS CONFIG_KEY_RECORD
config_keys_end:
config_schedule_name:
    .ascii "BLOB_SCHEDULE"
config_epoch_name:
    .ascii "EPOCH"
config_max_name:
    .ascii "MAX_BLOBS_PER_BLOCK"

/* \out = the value of the hex digit in \in (32-bit registers), or 16 when it is not one. */
.macro CONFIG_HEX out, in
    mov     \in, \out
    sub     $(0x30), \out
    cmp     $(10), \out
    jb      91f
    mov     \in, \out
    or      $(0x20), \out                   # a to f, either case
    sub     $(0x61), \out
    cmp     $(6), \out
    jb      92f
    mov     $(16), \out
    jmp     91f
92: add     $(10), \out
91:
.endm

/* rax = 1 when the rsi bytes at rdi are the rcx bytes at rdx, else 0. Uses rdi, rsi, rdx. */
LOCAL_FUNCTION config_name_is
    UNWIND_END_PROLOGUE
    cmp     %rcx, %rsi
    jne     2f
1:  test    %rsi, %rsi
    jz      3f
    movzbl  (%rdi), %eax
    cmpb    %al, (%rdx)
    jne     2f
    inc     %rdi
    inc     %rdx
    dec     %rsi
    jmp     1b
2:  xor     %eax, %eax
    ret
3:  mov     $1, %eax
    ret
END_FUNCTION config_name_is

/* The value bytes rdi to rsi without a pair of quotes: rax = 0, rdi their start, rsi their end; rax = 1 for a quote with no end. Uses rcx. */
LOCAL_FUNCTION config_unquote
    UNWIND_END_PROLOGUE
    cmp     %rsi, %rdi
    jae     8f
    movzbl  (%rdi), %eax
    cmp     $0x27, %eax                     # '
    je      1f
    cmp     $0x22, %eax                     # "
    jne     8f
1:  mov     %rsi, %rcx
    sub     %rdi, %rcx
    cmp     $2, %rcx
    jb      9f
    cmpb    %al, -1(%rsi)
    jne     9f
    inc     %rdi
    dec     %rsi
8:  xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION config_unquote

/* rax = 0 and rdx = the u64 of the bytes rdi to rsi: decimal, or 0x and 1 to 16 hex digits; else rax = 1. Uses rcx, rdi, r8-r10. */
LOCAL_FUNCTION config_u64
    UNWIND_END_PROLOGUE
    mov     %rsi, %rcx
    sub     %rdi, %rcx
    jz      9f
    xor     %r10d, %r10d                    # the value
    cmp     $3, %rcx
    jb      3f
    cmpb    $0x30, (%rdi)                   # 0x
    jne     3f
    cmpb    $0x78, 1(%rdi)
    jne     3f
    sub     $2, %rcx
    cmp     $16, %rcx
    ja      9f
    add     $2, %rdi
2:  cmp     %rsi, %rdi
    jae     8f
    movzbl  (%rdi), %eax
    inc     %rdi
    CONFIG_HEX %r8d, %eax
    cmp     $16, %r8d
    jae     9f
    shl     $4, %r10
    or      %r8, %r10
    jmp     2b
3:  cmp     %rsi, %rdi                      # decimal
    jae     8f
    movzbl  (%rdi), %r9d
    inc     %rdi
    sub     $0x30, %r9d
    cmp     $9, %r9d
    ja      9f
    mov     %r10, %rax
    mov     $10, %ecx
    mul     %rcx
    jc      9f
    add     %r9, %rax
    jc      9f
    mov     %rax, %r10
    jmp     3b
8:  mov     %r10, %rdx
    xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION config_u64

/* rax = 0 when the bytes rdi to rsi are 0x and 2 * rcx hex digits, whose rcx bytes go to rdx in order; else 1. Uses rcx, rdx, rdi, r8, r9. */
LOCAL_FUNCTION config_hex_bytes
    UNWIND_END_PROLOGUE
    mov     %rsi, %rax
    sub     %rdi, %rax
    lea     2(%rcx,%rcx), %r8
    cmp     %r8, %rax
    jne     9f
    cmpb    $0x30, (%rdi)                   # 0x
    jne     9f
    cmpb    $0x78, 1(%rdi)
    jne     9f
    add     $2, %rdi
1:  test    %rcx, %rcx
    jz      8f
    movzbl  (%rdi), %eax
    CONFIG_HEX %r8d, %eax
    cmp     $16, %r8d
    jae     9f
    movzbl  1(%rdi), %eax
    CONFIG_HEX %r9d, %eax
    cmp     $16, %r9d
    jae     9f
    shl     $4, %r8d
    or      %r9d, %r8d
    mov     %r8b, (%rdx)
    inc     %rdx
    add     $2, %rdi
    dec     %rcx
    jmp     1b
8:  xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION config_hex_bytes

/* rax = 0 when the bytes rdi to rsi are the decimal digits of a number below 2^256, then little endian at rdx (32 bytes); else 1. Uses rcx, rdx, rdi, r8-r10. */
LOCAL_FUNCTION config_uint256
    UNWIND_END_PROLOGUE
    mov     %rdx, %r8
    movq    $0, (%r8)
    movq    $0, 8(%r8)
    movq    $0, 16(%r8)
    movq    $0, 24(%r8)
    cmp     %rsi, %rdi
    jae     9f
1:  cmp     %rsi, %rdi
    jae     8f
    movzbl  (%rdi), %r9d                    # the carry: the digit
    inc     %rdi
    sub     $0x30, %r9d
    cmp     $9, %r9d
    ja      9f
    xor     %r10d, %r10d                    # each limb: limb * 10 + carry
2:  mov     (%r8,%r10), %rax
    mov     $10, %ecx
    mul     %rcx
    add     %r9, %rax
    adc     $0, %rdx
    mov     %rax, (%r8,%r10)
    mov     %rdx, %r9
    add     $8, %r10
    cmp     $32, %r10
    jb      2b
    test    %r9, %r9                        # 2^256 or more
    jnz     9f
    jmp     1b
8:  xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION config_uint256

/*
 * rax = 0 when the value bytes rsi to rdx, without a pair of quotes, are a value of the kind
 * rdi, then at rcx: 8 bytes (u64; Version: 4 bytes and 4 zero bytes) or 32 (Uint256, Hash32);
 * else 1. r12 the kind, r13 out.
 */
LOCAL_FUNCTION config_value
    ENTER 0
    mov     %rdi, %r12
    mov     %rcx, %r13
    mov     %rsi, %rdi
    mov     %rdx, %rsi
    call    config_unquote
    test    %rax, %rax
    jnz     9f
    cmp     $CONFIG_KIND_U64, %r12
    jne     1f
    call    config_u64
    test    %rax, %rax
    jnz     9f
    mov     %rdx, (%r13)
    jmp     9f
1:  cmp     $CONFIG_KIND_VERSION, %r12
    jne     2f
    movq    $0, (%r13)
    mov     %r13, %rdx
    mov     $4, %ecx
    call    config_hex_bytes
    jmp     9f
2:  cmp     $CONFIG_KIND_UINT256, %r12
    jne     3f
    mov     %r13, %rdx
    call    config_uint256
    jmp     9f
3:  mov     %r13, %rdx                      # Hash32
    mov     $32, %ecx
    call    config_hex_bytes
9:  LEAVE 0
END_FUNCTION config_value

/*
 * In config_scan: close the open entry of the schedule: to 80f (a fault at its line) without
 * both fields; else with write, its EPOCH and MAX_BLOBS_PER_BLOCK as schedule entry S8 - 1. Uses rax, rcx.
 */
.macro CONFIG_ENTRY_END
    testq   $(4), S9(%rsp)
    jz      99f
    mov     S9(%rsp), %rax
    and     $(3), %eax
    cmp     $(3), %eax
    jne     80f
    cmpq    $(0), S10(%rsp)
    je      98f
    mov     S8(%rsp), %rax
    dec     %rax
    shl     $(4), %rax
    lea     CONFIG_BLOB_SCHEDULE(%rbx,%rax), %rax
    mov     (L + 16)(%rsp), %rcx
    mov     %rcx, (%rax)
    mov     (L + 24)(%rsp), %rcx
    mov     %rcx, 8(%rax)
98: movq    $(0), S9(%rsp)
99:
.endm

.set CONFIG_MODE_NONE, 0                    # no key yet
.set CONFIG_MODE_SCALAR, 1                  # a key lantern reads, or BLOB_SCHEDULE: []
.set CONFIG_MODE_SKIP, 2                    # a key lantern does not read
.set CONFIG_MODE_SCHEDULE, 3                # the entries of BLOB_SCHEDULE

/*
 * rax = 0, or the number of the first faulty line, of the config text rdi (a ByteList); with
 * rdx = 1, writes its values into the config rsi. rbx config, rbp the next line, r12 the text
 * end, r13 the line number, r14 the line start, r15 the line end, S7 the mode or a key record,
 * S8 the schedule's entries, S9 the open entry: bit 0 EPOCH, bit 1 MAX_BLOBS_PER_BLOCK, bit 2
 * open, S10 write. Locals: L the entry's line, L+8 its dash column, L+16 its EPOCH, L+24 its
 * MAX_BLOBS_PER_BLOCK, L+32 1 when the text gives BLOB_SCHEDULE, L+40 a value (32 bytes) or a
 * field, L+72 the value's start or a column, L+80 the key's length or a position.
 */
LOCAL_FUNCTION config_scan
    ENTER 96
    mov     %rsi, %rbx
    mov     %rdx, S10(%rsp)
    mov     8(%rdi), %rbp
    add     %rdi, %rbp
    mov     16(%rdi), %r12
    add     %rbp, %r12
    xor     %r13d, %r13d
    movq    $CONFIG_MODE_NONE, S7(%rsp)
    movq    $0, S8(%rsp)
    movq    $0, S9(%rsp)
    movq    $0, (L + 32)(%rsp)
10: cmp     %r12, %rbp                      # the next line
    jae     90f
    inc     %r13
    mov     %rbp, %r14
11: cmp     %r12, %rbp                      # its end: an LF or the text end
    jae     12f
    cmpb    $10, (%rbp)
    je      12f
    inc     %rbp
    jmp     11b
12: mov     %rbp, %r15
    cmp     %r12, %rbp
    jae     13f
    inc     %rbp                            # past the LF, and a CR before it
    cmp     %r14, %r15
    jbe     13f
    cmpb    $13, -1(%r15)
    jne     13f
    dec     %r15
13: mov     %r14, %rdi                      # a comment: # at the start or after a space or tab, outside quotes
    xor     %ecx, %ecx                      # the open quote
14: cmp     %r15, %rdi
    jae     17f
    movzbl  (%rdi), %eax
    test    %ecx, %ecx
    jz      15f
    cmp     %ecx, %eax
    jne     16f
    xor     %ecx, %ecx
    jmp     16f
15: cmp     $0x27, %eax
    je      151f
    cmp     $0x22, %eax
    jne     152f
151: mov    %eax, %ecx
    jmp     16f
152: cmp    $0x23, %eax                     # #
    jne     16f
    cmp     %r14, %rdi
    je      153f
    movzbl  -1(%rdi), %edx
    cmp     $0x20, %edx
    je      153f
    cmp     $9, %edx
    jne     16f
153: mov    %rdi, %r15
    jmp     17f
16: inc     %rdi
    jmp     14b
17: cmp     %r14, %r15                      # the spaces and tabs at the end
    jbe     10b                             # an empty line
    movzbl  -1(%r15), %eax
    cmp     $0x20, %eax
    je      171f
    cmp     $9, %eax
    jne     18f
171: dec    %r15
    jmp     17b
18: mov     %r15, %rax                      # ---
    sub     %r14, %rax
    cmp     $3, %rax
    jne     19f
    cmpb    $0x2d, (%r14)
    jne     19f
    cmpb    $0x2d, 1(%r14)
    jne     19f
    cmpb    $0x2d, 2(%r14)
    je      10b
19: cmpb    $0x20, (%r14)
    je      50f
    CONFIG_ENTRY_END                        # KEY: and nothing, or spaces and a value
    mov     %r14, %rdi
21: cmp     %r15, %rdi
    jae     89f
    movzbl  (%rdi), %eax
    cmp     $0x3a, %eax                     # :
    je      23f
    lea     -0x30(%rax), %ecx               # 0 to 9, _, A to Z, a to z
    cmp     $10, %ecx
    jb      22f
    cmp     $0x5f, %eax
    je      22f
    or      $0x20, %eax
    sub     $0x61, %eax
    cmp     $26, %eax
    jae     89f
22: inc     %rdi
    jmp     21b
23: mov     %rdi, %rax
    sub     %r14, %rax
    jz      89f
    mov     %rax, (L + 80)(%rsp)
    inc     %rdi
    cmp     %r15, %rdi
    jae     25f
    cmpb    $0x20, (%rdi)
    jne     89f
24: cmpb    $0x20, (%rdi)                   # the spaces before the value
    jne     25f
    inc     %rdi
    jmp     24b
25: mov     %rdi, (L + 72)(%rsp)
    mov     %r14, %rdi
    mov     (L + 80)(%rsp), %rsi
    lea     config_schedule_name(%rip), %rdx
    mov     $13, %ecx
    call    config_name_is
    test    %rax, %rax
    jnz     30f
    lea     config_keys(%rip), %rax
    mov     %rax, S7(%rsp)
26: mov     S7(%rsp), %rdx
    lea     config_keys_end(%rip), %rax
    cmp     %rax, %rdx
    jae     27f
    mov     %r14, %rdi
    mov     (L + 80)(%rsp), %rsi
    mov     (%rdx), %rcx
    add     $24, %rdx
    call    config_name_is
    test    %rax, %rax
    jnz     28f
    addq    $CONFIG_KEY_BYTES, S7(%rsp)
    jmp     26b
27: movq    $CONFIG_MODE_SKIP, S7(%rsp)     # a key lantern does not read
    jmp     10b
28: mov     S7(%rsp), %rax                  # a key lantern reads
    mov     16(%rax), %rdi
    mov     (L + 72)(%rsp), %rsi
    mov     %r15, %rdx
    lea     (L + 40)(%rsp), %rcx
    call    config_value
    test    %rax, %rax
    jnz     89f
    cmpq    $0, S10(%rsp)
    je      29f
    mov     S7(%rsp), %rax                  # 8 bytes, or 32 for a Uint256 or a Hash32
    mov     8(%rax), %rdi
    add     %rbx, %rdi
    mov     (L + 40)(%rsp), %rcx
    mov     %rcx, (%rdi)
    cmpq    $CONFIG_KIND_VERSION, 16(%rax)
    jbe     29f
    mov     (L + 48)(%rsp), %rcx
    mov     %rcx, 8(%rdi)
    mov     (L + 56)(%rsp), %rcx
    mov     %rcx, 16(%rdi)
    mov     (L + 64)(%rsp), %rcx
    mov     %rcx, 24(%rdi)
29: movq    $CONFIG_MODE_SCALAR, S7(%rsp)
    jmp     10b
30: movq    $0, S8(%rsp)                    # BLOB_SCHEDULE: nothing, then its entries; or []
    movq    $1, (L + 32)(%rsp)
    movq    $CONFIG_MODE_SCHEDULE, S7(%rsp)
    mov     (L + 72)(%rsp), %rdi
    cmp     %r15, %rdi
    jae     10b
    mov     %r15, %rax
    sub     %rdi, %rax
    cmp     $2, %rax
    jne     89f
    cmpb    $0x5b, (%rdi)
    jne     89f
    cmpb    $0x5d, 1(%rdi)
    jne     89f
    movq    $CONFIG_MODE_SCALAR, S7(%rsp)
    jmp     10b
50: cmpq    $CONFIG_MODE_SKIP, S7(%rsp)     # an indented line
    je      10b
    cmpq    $CONFIG_MODE_SCHEDULE, S7(%rsp)
    jne     89f
    mov     %r14, %rdi
51: cmpb    $0x20, (%rdi)
    jne     52f
    inc     %rdi
    jmp     51b
52: mov     %rdi, %rsi                      # its column
    sub     %r14, %rsi
    cmpb    $0x2d, (%rdi)
    jne     55f
    lea     1(%rdi), %rdx                   # - and a space: a new entry
    cmp     %r15, %rdx
    jae     89f
    cmpb    $0x20, (%rdx)
    jne     89f
    mov     %rsi, (L + 72)(%rsp)
    mov     %rdx, (L + 80)(%rsp)
    CONFIG_ENTRY_END
    cmpq    $CONFIG_BLOB_SCHEDULE_MAX, S8(%rsp)
    jae     89f
    incq    S8(%rsp)
    movq    $4, S9(%rsp)
    mov     %r13, L(%rsp)
    mov     (L + 72)(%rsp), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     (L + 80)(%rsp), %rdi
53: cmpb    $0x20, (%rdi)
    jne     56f
    inc     %rdi
    jmp     53b
55: testq   $4, S9(%rsp)                    # a field of the open entry, past its dash
    jz      89f
    cmp     (L + 8)(%rsp), %rsi
    jbe     89f
56: mov     %rdi, %rdx                      # FIELD: and spaces and a value
57: cmp     %r15, %rdx
    jae     89f
    cmpb    $0x3a, (%rdx)
    je      58f
    inc     %rdx
    jmp     57b
58: mov     %rdx, %rsi                      # the field's length
    sub     %rdi, %rsi
    inc     %rdx
    cmp     %r15, %rdx
    jae     89f
    cmpb    $0x20, (%rdx)
    jne     89f
581: cmpb   $0x20, (%rdx)
    jne     582f
    inc     %rdx
    jmp     581b
582: mov    %rdi, (L + 40)(%rsp)
    mov     %rsi, (L + 48)(%rsp)
    mov     %rdx, (L + 56)(%rsp)
    lea     config_epoch_name(%rip), %rdx
    mov     $5, %ecx
    call    config_name_is
    mov     $1, %r8d                        # EPOCH: bit 0
    test    %rax, %rax
    jnz     59f
    mov     (L + 40)(%rsp), %rdi
    mov     (L + 48)(%rsp), %rsi
    lea     config_max_name(%rip), %rdx
    mov     $19, %ecx
    call    config_name_is
    test    %rax, %rax
    jz      89f
    mov     $2, %r8d                        # MAX_BLOBS_PER_BLOCK: bit 1
59: test    %r8, S9(%rsp)
    jnz     89f                             # given twice
    or      %r8, S9(%rsp)
    mov     %r8, (L + 64)(%rsp)
    mov     (L + 56)(%rsp), %rdi
    mov     %r15, %rsi
    call    config_unquote
    test    %rax, %rax
    jnz     89f
    call    config_u64
    test    %rax, %rax
    jnz     89f
    mov     (L + 64)(%rsp), %rax
    mov     %rdx, (L + 8)(%rsp,%rax,8)      # L+16 or L+24
    jmp     10b
90: CONFIG_ENTRY_END                        # the end of the text
    cmpq    $0, S10(%rsp)
    je      95f
    cmpq    $0, (L + 32)(%rsp)              # the schedule's count, then its entries sorted by EPOCH
    je      95f
    mov     S8(%rsp), %r8
    mov     %r8, CONFIG_BLOB_SCHEDULE_COUNT(%rbx)
    lea     CONFIG_BLOB_SCHEDULE(%rbx), %r9
    mov     $1, %r10d
91: cmp     %r8, %r10
    jae     95f
    mov     %r10, %rdx                      # the place of entry r10
    shl     $4, %rdx
    add     %r9, %rdx
    mov     (%rdx), %rax
    mov     8(%rdx), %rcx
92: cmp     %r9, %rdx
    jbe     93f
    mov     -16(%rdx), %rsi
    cmp     %rax, %rsi
    jbe     93f                             # an equal EPOCH stays before
    mov     %rsi, (%rdx)
    mov     -8(%rdx), %rsi
    mov     %rsi, 8(%rdx)
    sub     $16, %rdx
    jmp     92b
93: mov     %rax, (%rdx)
    mov     %rcx, 8(%rdx)
    inc     %r10
    jmp     91b
95: xor     %eax, %eax
    LEAVE 96
80: mov     L(%rsp), %r13                   # the line of the open entry
89: mov     %r13, %rax
    LEAVE 96
END_FUNCTION config_scan

/* (text, config, line): docs/reference/config.md. r12 text, r13 config, r14 line. */
FUNCTION lantern_config_parse
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, %r14
    xor     %edx, %edx                      # check every line first
    call    config_scan
    test    %rax, %rax
    jnz     1f
    mov     %r12, %rdi
    mov     %r13, %rsi
    mov     $1, %edx
    call    config_scan
    movq    $0, (%r14)
    xor     %eax, %eax
    LEAVE 0
1:  mov     %rax, (%r14)
    mov     $LANTERN_INVALID_CONFIG, %eax
    LEAVE 0
END_FUNCTION lantern_config_parse
