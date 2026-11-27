/*
 * Sizing, making, growing and pruning Seen, x86-64: it reads no fork's layouts.
 * Requirements: docs/reference/networking.md.
 */

.if SeenKey__mem != 32 || SeenBits__mem != 320 || SeenBlock__mem != 40 || SEEN_BITS_BYTES * 8 < MAX_VALIDATORS_PER_COMMITTEE || SEEN_BITS_BYTES * 8 < SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.error "the gossip code assumes the Seen layouts of include/lantern.inc"
.endif

/* Copy the entries of stride bytes of part ref of seen rbx into out r12, and set the part's count. Uses r13. */
.macro SEEN_PART_COPY ref, stride
    PART    %rsi, %r13, %rbx, \ref
    mov     \ref(%r12), %rdi
    add     %r12, %rdi
    imul    $(\stride), %r13, %rdx
    call    lantern_copy
    mov     %r13, ((\ref) + 8)(%r12)
.endm

LEAF lantern_seen_size
    mov     %rsi, %r9
    MOVQ    %r8, SEEN_FIXED
    mov     SeenRoom_keys(%rdi), %rax       # keys * 32 fits
    mov     %rax, %rcx
    shr     $59, %rcx
    jnz     9f
    shl     $5, %rax
    add     %rax, %r8
    jc      9f
    mov     SeenRoom_bits(%rdi), %rax
    mov     $SeenBits__mem, %ecx
    mul     %rcx
    jc      9f
    add     %rax, %r8
    jc      9f
    mov     SeenRoom_blocks(%rdi), %rax
    mov     $SeenBlock__mem, %ecx
    mul     %rcx
    jc      9f
    add     %rax, %r8
    jc      9f
    add     SeenRoom_header_bytes(%rdi), %r8
    jc      9f
    mov     %r8, (%r9)
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_seen_size

/* Locals: rsp+0 room, rsp+8 seen, rsp+16 size. */
FUNCTION lantern_seen_init
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    lea     16(%rsp), %rsi
    call    lantern_seen_size
    test    %rax, %rax
    jnz     9f
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rsi
    mov     16(%rsp), %rax
    cmp     %rax, (%rsi)
    jb      9f
    MOVQ    %rax, SEEN_FIXED                # each part empty, at the offsets of room's capacities
    mov     %rax, Seen_keys(%rsi)
    movq    $0, (Seen_keys + 8)(%rsi)
    mov     SeenRoom_keys(%rdi), %rcx
    shl     $5, %rcx
    add     %rcx, %rax
    mov     %rax, Seen_bits(%rsi)
    movq    $0, (Seen_bits + 8)(%rsi)
    imul    $SeenBits__mem, SeenRoom_bits(%rdi), %rcx
    add     %rcx, %rax
    mov     %rax, Seen_blocks(%rsi)
    movq    $0, (Seen_blocks + 8)(%rsi)
    imul    $SeenBlock__mem, SeenRoom_blocks(%rdi), %rcx
    add     %rcx, %rax
    mov     %rax, Seen_headers(%rsi)
    movq    $0, (Seen_headers + 8)(%rsi)
    movq    $0, Seen_header_bytes(%rsi)
    xor     %eax, %eax
    UNFRAME 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 32
END_FUNCTION lantern_seen_init

/* rbx seen, rbp room, r12 out, r13 count. */
FUNCTION lantern_seen_copy
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     SeenRoom_keys(%rbp), %rax       # each capacity holds what seen holds
    cmp     (Seen_keys + 8)(%rbx), %rax
    jb      9f
    mov     SeenRoom_bits(%rbp), %rax
    cmp     (Seen_bits + 8)(%rbx), %rax
    jb      9f
    mov     SeenRoom_blocks(%rbp), %rax
    cmp     (Seen_blocks + 8)(%rbx), %rax
    jb      9f
    mov     SeenRoom_header_bytes(%rbp), %rax
    cmp     Seen_header_bytes(%rbx), %rax
    jb      9f
    mov     %rbp, %rdi
    mov     %r12, %rsi
    call    lantern_seen_init
    test    %rax, %rax
    jnz     7f
    SEEN_PART_COPY Seen_keys, SeenKey__mem
    SEEN_PART_COPY Seen_bits, SeenBits__mem
    SEEN_PART_COPY Seen_blocks, SeenBlock__mem
    SEEN_PART_COPY Seen_headers, 0
    mov     Seen_headers(%rbx), %rsi        # the headers: their bytes in use
    add     %rbx, %rsi
    mov     Seen_headers(%r12), %rdi
    add     %r12, %rdi
    mov     Seen_header_bytes(%rbx), %rdx
    mov     %rdx, Seen_header_bytes(%r12)
    call    lantern_copy
    xor     %eax, %eax
7:  LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION lantern_seen_copy

/* Locals: rsp+0 seen, rsp+8 root, rsp+16 payload_status. */
FUNCTION lantern_seen_add_block
    FRAME 32
    mov     (%rdx), %rdx
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    call    lantern_seen_find_block
    test    %rax, %rax
    jnz     2f
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rsi
    mov     Seen_headers(%rdi), %rax        # room for one more
    sub     Seen_blocks(%rdi), %rax
    xor     %edx, %edx
    mov     $SeenBlock__mem, %ecx
    div     %rcx
    mov     (Seen_blocks + 8)(%rdi), %r8
    cmp     %rax, %r8
    jae     9f
    imul    $SeenBlock__mem, %r8, %rax
    add     Seen_blocks(%rdi), %rax
    add     %rdi, %rax
    inc     %r8
    mov     %r8, (Seen_blocks + 8)(%rdi)
    COPY32  %rax, %rsi
2:  mov     16(%rsp), %rdx
    mov     %rdx, SeenBlock_payload_status(%rax)
    xor     %eax, %eax
    UNFRAME 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 32
END_FUNCTION lantern_seen_add_block

/*
 * Drop the entries of past epochs and slots from seen rdi, with the time and the finalized epoch of
 * store rsi (networking.md). A leaf; uses rax, rcx, rdx, rsi, r8-r11, xmm0, xmm1. r8 the first epoch
 * kept, r9 the first sync slot kept, r11 the finalized slot; rsi the entry read, rdx the entry
 * written, rcx the entries left.
 */
LEAF lantern_seen_prune
    mov     Store_time_ms(%rsi), %rax       # s: the current slot, 0 before genesis
    sub     Store_genesis_time_ms(%rsi), %rax
    jae     1f
    xor     %eax, %eax
1:  mov     (Store_config + CONFIG_SLOT_DURATION_MS)(%rsi), %rcx
    test    %rcx, %rcx
    jz      2f
    xor     %edx, %edx
    div     %rcx
    jmp     3f
2:  xor     %eax, %eax
3:  mov     %rax, %r9                       # the first sync slot kept: s - 1
    sub     $1, %r9
    jae     4f
    xor     %r9d, %r9d
4:  sub     (Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE)(%rsi), %rax
    jb      5f
    sub     $1, %rax
    jb      5f
    xor     %edx, %edx                      # e: the epoch of s - range - 1
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    sub     $1, %rax                        # the first epoch kept: e - 1
    jae     6f
5:  xor     %eax, %eax
6:  mov     %rax, %r8
    mov     Store_finalized_checkpoint(%rsi), %rax  # f: the first slot of the finalized epoch
    mov     $SLOTS_PER_EPOCH, %ecx
    mul     %rcx
    jno     7f
    mov     $-1, %rax
7:  mov     %rax, %r11
    PART    %rsi, %rcx, %rdi, Seen_keys     # the keys
    mov     %rsi, %rdx
10: test    %rcx, %rcx
    jz      19f
    mov     SeenKey_kind(%rsi), %rax
    mov     SeenKey_a(%rsi), %r10
    cmp     $SEEN_ATTESTATION, %rax
    je      11f
    cmp     $SEEN_AGGREGATOR_EPOCH, %rax
    je      11f
    cmp     $SEEN_PROPOSER_SLOT, %rax
    je      12f
    cmp     $SEEN_DATA_COLUMN, %rax
    je      12f
    cmp     $SEEN_BLOB_SIDECAR, %rax
    je      12f
    cmp     $SEEN_SYNC_CONTRIBUTION, %rax
    je      13f
    cmp     $SEEN_SYNC_MESSAGE, %rax
    jne     15f
13: cmp     %r9, %r10                       # a sync slot: kept from s - 1
    jb      16f
    jmp     15f
11: cmp     %r8, %r10                       # an epoch: kept from the first epoch kept
    jb      16f
    jmp     15f
12: cmp     %r11, %r10                      # a block's slot: kept above f
    jbe     16f
15: cmp     %rsi, %rdx                      # kept: moved down over the dropped ones
    je      14f
    movdqu  0(%rsi), %xmm0
    movdqu  16(%rsi), %xmm1
    movdqu  %xmm0, 0(%rdx)
    movdqu  %xmm1, 16(%rdx)
14: add     $SeenKey__mem, %rdx
16: add     $SeenKey__mem, %rsi
    dec     %rcx
    jmp     10b
19: mov     Seen_keys(%rdi), %rax           # the count: the entries written
    add     %rdi, %rax
    sub     %rax, %rdx
    shr     $5, %rdx
    mov     %rdx, (Seen_keys + 8)(%rdi)
    PART    %rsi, %rcx, %rdi, Seen_bits     # the bits
    mov     %rsi, %rdx
20: test    %rcx, %rcx
    jz      29f
    mov     SeenBits_kind(%rsi), %rax
    cmp     $SEEN_AGGREGATE, %rax
    jne     21f
    cmp     %r8, SeenBits_b(%rsi)           # an aggregate: its target epoch kept from the first epoch kept
    jb      26f
    jmp     25f
21: cmp     $SEEN_CONTRIBUTION, %rax
    jne     25f
    cmp     %r9, SeenBits_a(%rsi)           # a contribution: its slot kept from s - 1
    jb      26f
25: cmp     %rsi, %rdx
    je      23f
    xor     %r11d, %r11d
24: movdqu  (%rsi,%r11), %xmm0
    movdqu  %xmm0, (%rdx,%r11)
    add     $16, %r11
    cmp     $SeenBits__mem, %r11
    jb      24b
23: add     $SeenBits__mem, %rdx
26: add     $SeenBits__mem, %rsi
    dec     %rcx
    jmp     20b
29: mov     Seen_bits(%rdi), %rax
    add     %rdi, %rax
    sub     %rax, %rdx
    mov     %rdx, %rax
    xor     %edx, %edx
    mov     $SeenBits__mem, %ecx
    div     %rcx
    mov     %rax, (Seen_bits + 8)(%rdi)
    xor     %eax, %eax
    ret
END_FUNCTION lantern_seen_prune
