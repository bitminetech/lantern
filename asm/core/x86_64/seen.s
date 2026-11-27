/*
 * Sizing, making, growing and archiving Seen, x86-64: it reads no fork's layouts.
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
    mov     (%rsi), %rcx                    # every byte of the parts zero
    sub     $SEEN_FIXED, %rcx
    lea     SEEN_FIXED(%rsi), %rdi
    xor     %eax, %eax
    rep stosb
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
 * The floors of store rsi (networking.md, lantern_seen_archive): r8 the first epoch kept, r9 the first
 * sync slot kept, r11 the finalized slot. A leaf; uses rax, rcx, rdx.
 */
LOCAL_FUNCTION lantern_seen_floors
    UNWIND_END_PROLOGUE
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
    ret
END_FUNCTION lantern_seen_floors

/* dst = the bytes of an entry of HIST kind k: 16, 24, or HistBits__mem. */
.macro HIST_ELEM dst, k
    mov     $16, \dst
    cmp     $HIST_COLUMN, \k
    jb      104f
    mov     $24, \dst
    cmp     $HIST_AGGREGATE, \k
    jb      104f
    mov     $HistBits__mem, \dst
104:
.endm

/* Jump to less when the first r13 words of the record at rsi are below those at rdi, else to notless. Uses rax, r11. */
.macro SORT_LESS less, notless
    xor     %r11d, %r11d
101: cmp    %r13, %r11
    jae     \notless
    mov     (%rsi,%r11,8), %rax
    cmp     (%rdi,%r11,8), %rax
    jb      \less
    ja      \notless
    inc     %r11
    jmp     101b
.endm

/* Swap the r12 words of the records at rsi and rdi. Uses rax, rdx, r11. */
.macro SORT_SWAP
    xor     %r11d, %r11d
102: cmp    %r12, %r11
    jae     103f
    mov     (%rsi,%r11,8), %rax
    mov     (%rdi,%r11,8), %rdx
    mov     %rdx, (%rsi,%r11,8)
    mov     %rax, (%rdi,%r11,8)
    inc     %r11
    jmp     102b
103:
.endm

/*
 * Sort the rsi records of rdx words at rdi by their first rcx words, unsigned and in word order: a
 * heapsort. rbx the records, rbp their count, r12 words, r13 key words, r14 record bytes, r15 the
 * inner node or the end of the heap, r8 the root, r9 the end, r10 a child. Locals: L 0 while the heap is built.
 */
LOCAL_FUNCTION lantern_seen_sort
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    cmp     $2, %rbp
    jb      9f
    lea     (,%r12,8), %r14
    mov     %rbp, %r15
    shr     $1, %r15
    movq    $0, L(%rsp)
1:  test    %r15, %r15                      # the heap: each inner node from the last
    jz      2f
    dec     %r15
    mov     %r15, %r8
    mov     %rbp, %r9
    jmp     5f
2:  movq    $1, L(%rsp)                     # then the largest to the end, one at a time
    lea     -1(%rbp), %r15
3:  test    %r15, %r15
    jz      9f
    mov     %rbx, %rsi
    mov     %r15, %rdi
    imul    %r14, %rdi
    add     %rbx, %rdi
    SORT_SWAP
    xor     %r8d, %r8d
    mov     %r15, %r9
    dec     %r15
    jmp     5f
4:  cmpq    $0, L(%rsp)
    je      1b
    jmp     3b
5:  lea     1(%r8,%r8), %r10                # sift down from r8, below r9
    cmp     %r9, %r10
    jae     4b
    lea     1(%r10), %rax
    cmp     %r9, %rax
    jae     6f
    mov     %r10, %rsi
    imul    %r14, %rsi
    add     %rbx, %rsi
    lea     (%rsi,%r14), %rdi
    SORT_LESS 7f, 6f
7:  inc     %r10
6:  mov     %r8, %rsi
    imul    %r14, %rsi
    add     %rbx, %rsi
    mov     %r10, %rdi
    imul    %r14, %rdi
    add     %rbx, %rdi
    SORT_LESS 8f, 4b
8:  SORT_SWAP
    mov     %r10, %r8
    jmp     5b
9:  LEAVE 16
END_FUNCTION lantern_seen_sort

/* The chunk at c takes epoch e into its range. */
.macro CHUNK_EPOCH c, e
    cmp     SeenChunk_epoch_lo(\c), \e
    jae     105f
    mov     \e, SeenChunk_epoch_lo(\c)
105: cmp    SeenChunk_epoch_hi(\c), \e
    jbe     106f
    mov     \e, SeenChunk_epoch_hi(\c)
106:
.endm

/*
 * (seen, store, out): networking.md. rbx seen, rbp store, r12 out, r13 the first epoch kept, r14 the first
 * sync slot kept, r15 the finalized slot. Locals: L the entries of each of the five kinds, L+40 the bytes
 * of the bits, L+48 the write cursor, L+56 the HIST kind, L+64 the chunk, L+72 its entries, L+80 an entry's bytes.
 */
FUNCTION lantern_seen_archive
    ENTER 96
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    call    lantern_seen_floors
    mov     %r8, %r13
    mov     %r9, %r14
    mov     %r11, %r15
    xor     %eax, %eax
    mov     %rax, L(%rsp)
    mov     %rax, (L + 8)(%rsp)
    mov     %rax, (L + 16)(%rsp)
    mov     %rax, (L + 24)(%rsp)
    mov     %rax, (L + 32)(%rsp)
    mov     %rax, (L + 40)(%rsp)
    PART    %rsi, %rcx, %rbx, Seen_keys     # the entries that go: counts
1:  test    %rcx, %rcx
    jz      2f
    mov     (%rsi), %rax
    mov     8(%rsi), %rdx
    mov     $HIST_ATTESTATION, %edi
    cmp     $SEEN_ATTESTATION, %rax
    je      11f
    mov     $HIST_AGGREGATOR, %edi
    cmp     $SEEN_AGGREGATOR_EPOCH, %rax
    je      11f
    mov     $HIST_COLUMN, %edi
    cmp     $SEEN_DATA_COLUMN, %rax
    je      12f
    mov     $HIST_BLOB, %edi
    cmp     $SEEN_BLOB_SIDECAR, %rax
    je      12f
    jmp     13f
11: cmp     %r13, %rdx                      # an epoch before the first kept
    jae     13f
    jmp     14f
12: cmp     %r15, %rdx                      # a slot before the finalized slot
    jae     13f
14: incq    L(%rsp,%rdi,8)
13: add     $SeenKey__mem, %rsi
    dec     %rcx
    jmp     1b
2:  PART    %rsi, %rcx, %rbx, Seen_bits
21: test    %rcx, %rcx
    jz      3f
    cmpq    $SEEN_AGGREGATE, SeenBits_kind(%rsi)
    jne     23f
    cmp     %r13, SeenBits_b(%rsi)
    jae     23f
    incq    (L + 32)(%rsp)
    mov     SeenBits_length(%rsi), %rax     # its bits: whole words
    add     $63, %rax
    shr     $6, %rax
    shl     $3, %rax
    add     %rax, (L + 40)(%rsp)
23: add     $SeenBits__mem, %rsi
    dec     %rcx
    jmp     21b
3:  xor     %r8d, %r8d                      # the bytes the chunks need
    xor     %edi, %edi
31: mov     L(%rsp,%rdi,8), %rax
    test    %rax, %rax
    jz      32f
    HIST_ELEM %rcx, %rdi
    imul    %rcx, %rax
    add     %rax, %r8
    add     $SEEN_CHUNK_FIXED, %r8
32: inc     %rdi
    cmp     $HIST_KINDS, %rdi
    jb      31b
    add     (L + 40)(%rsp), %r8
    mov     (%r12), %rax                    # out has room for them
    sub     8(%r12), %rax
    jb      98f
    sub     16(%r12), %rax
    jb      98f
    cmp     %r8, %rax
    jb      98f
    mov     8(%r12), %rax
    add     16(%r12), %rax
    add     %r12, %rax
    mov     %rax, (L + 48)(%rsp)
    movq    $0, (L + 56)(%rsp)              # each kind's chunk
4:  mov     (L + 56)(%rsp), %rdi
    mov     L(%rsp,%rdi,8), %rax
    test    %rax, %rax
    jz      49f
    mov     %rax, (L + 72)(%rsp)
    mov     (L + 48)(%rsp), %r9
    mov     %r9, (L + 64)(%rsp)
    mov     %rdi, SeenChunk_kind(%r9)
    movq    $-1, SeenChunk_epoch_lo(%r9)
    movq    $0, SeenChunk_epoch_hi(%r9)
    mov     %rax, SeenChunk_count(%r9)
    lea     SEEN_CHUNK_FIXED(%r9), %r10
    HIST_ELEM %rcx, %rdi
    mov     %rcx, (L + 80)(%rsp)
    cmp     $HIST_AGGREGATE, %rdi
    je      45f
    mov     $SEEN_ATTESTATION, %r11d
    cmp     $HIST_AGGREGATOR, %rdi
    jb      40f
    mov     $SEEN_AGGREGATOR_EPOCH, %r11d
    je      40f
    mov     $SEEN_DATA_COLUMN, %r11d
    cmp     $HIST_COLUMN, %rdi
    je      40f
    mov     $SEEN_BLOB_SIDECAR, %r11d
40: PART    %rsi, %rcx, %rbx, Seen_keys
41: test    %rcx, %rcx
    jz      47f
    cmp     %r11, (%rsi)
    jne     44f
    mov     8(%rsi), %rdx
    cmp     $HIST_COLUMN, %rdi
    jae     42f
    cmp     %r13, %rdx                      # (epoch, index)
    jae     44f
    mov     %rdx, %rax
    mov     %rdx, (%r10)
    mov     16(%rsi), %r8
    mov     %r8, 8(%r10)
    add     $16, %r10
    jmp     43f
42: cmp     %r15, %rdx                      # (slot, proposer index, index)
    jae     44f
    mov     %rdx, (%r10)
    mov     16(%rsi), %r8
    mov     %r8, 8(%r10)
    mov     24(%rsi), %r8
    mov     %r8, 16(%r10)
    add     $24, %r10
    mov     %rdx, %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %r8d
    div     %r8
43: CHUNK_EPOCH %r9, %rax
44: add     $SeenKey__mem, %rsi
    dec     %rcx
    jmp     41b
45: mov     (L + 72)(%rsp), %rax            # the bits follow the HistBits
    imul    $HistBits__mem, %rax
    lea     (%r10,%rax), %r8
    PART    %rsi, %rcx, %rbx, Seen_bits
451: test   %rcx, %rcx
    jz      46f
    cmpq    $SEEN_AGGREGATE, SeenBits_kind(%rsi)
    jne     454f
    mov     SeenBits_b(%rsi), %rax
    cmp     %r13, %rax
    jae     454f
    lea     SeenBits_root(%rsi), %rdx
    COPY32  %r10, %rdx
    mov     SeenBits_a(%rsi), %rdx
    mov     %rdx, HistBits_a(%r10)
    mov     %rax, HistBits_epoch(%r10)
    mov     SeenBits_length(%rsi), %rdx
    mov     %rdx, HistBits_length(%r10)
    mov     %r8, %r11
    sub     %r9, %r11
    mov     %r11, HistBits_bits(%r10)
    add     $HistBits__mem, %r10
    add     $63, %rdx
    shr     $6, %rdx
    xor     %r11d, %r11d
452: cmp    %rdx, %r11
    jae     453f
    mov     SeenBits_bits(%rsi,%r11,8), %rdi
    mov     %rdi, (%r8)
    add     $8, %r8
    inc     %r11
    jmp     452b
453: CHUNK_EPOCH %r9, %rax
454: add    $SeenBits__mem, %rsi
    dec     %rcx
    jmp     451b
46: mov     %r8, (L + 48)(%rsp)             # the chunk's end: after the bits
    jmp     48f
47: mov     %r10, (L + 48)(%rsp)            # or after the entries
48: mov     (L + 64)(%rsp), %r9
    mov     (L + 48)(%rsp), %rax
    sub     %r9, %rax
    mov     %rax, SeenChunk_bytes(%r9)
    lea     SEEN_CHUNK_FIXED(%r9), %rdi     # the entries sorted
    mov     (L + 72)(%rsp), %rsi
    mov     (L + 80)(%rsp), %rdx
    shr     $3, %rdx
    mov     %rdx, %rcx
    cmpq    $HIST_AGGREGATE, (L + 56)(%rsp)
    jne     481f
    mov     $6, %ecx                        # the root, a and the epoch
481: call   lantern_seen_sort
49: incq    (L + 56)(%rsp)
    cmpq    $HIST_KINDS, (L + 56)(%rsp)
    jb      4b
    mov     (L + 48)(%rsp), %rax            # out's length
    sub     %r12, %rax
    sub     8(%r12), %rax
    mov     %rax, 16(%r12)
    PART    %rsi, %rcx, %rbx, Seen_keys     # the keys that stay, moved down; zero after them
    mov     %rsi, %rdx
5:  test    %rcx, %rcx
    jz      59f
    mov     (%rsi), %rax
    mov     8(%rsi), %r10
    cmp     $SEEN_ATTESTATION, %rax
    je      51f
    cmp     $SEEN_AGGREGATOR_EPOCH, %rax
    je      51f
    cmp     $SEEN_DATA_COLUMN, %rax
    je      52f
    cmp     $SEEN_BLOB_SIDECAR, %rax
    je      52f
    cmp     $SEEN_PROPOSER_SLOT, %rax
    je      53f
    cmp     $SEEN_SYNC_CONTRIBUTION, %rax
    je      54f
    cmp     $SEEN_SYNC_MESSAGE, %rax
    jne     55f
54: cmp     %r14, %r10                      # a sync slot: kept from s - 1
    jb      56f
    jmp     55f
51: cmp     %r13, %r10                      # archived: an epoch before the first kept
    jb      56f
    jmp     55f
52: cmp     %r15, %r10                      # archived: a slot before the finalized slot
    jb      56f
    jmp     55f
53: cmp     %r15, %r10                      # a proposer slot at or below f: dropped
    jbe     56f
55: cmp     %rsi, %rdx
    je      57f
    movdqu  0(%rsi), %xmm0
    movdqu  16(%rsi), %xmm1
    movdqu  %xmm0, 0(%rdx)
    movdqu  %xmm1, 16(%rdx)
57: add     $SeenKey__mem, %rdx
56: add     $SeenKey__mem, %rsi
    dec     %rcx
    jmp     5b
59: mov     Seen_keys(%rbx), %rax
    add     %rbx, %rax
    mov     %rdx, %rdi
    sub     %rax, %rdx
    shr     $5, %rdx
    mov     (Seen_keys + 8)(%rbx), %rsi
    mov     %rdx, (Seen_keys + 8)(%rbx)
    sub     %rdx, %rsi
    shl     $5, %rsi
    call    lantern_zero
    PART    %rsi, %rcx, %rbx, Seen_bits     # the bits that stay, moved down; zero after them
    mov     %rsi, %rdx
6:  test    %rcx, %rcx
    jz      69f
    mov     SeenBits_kind(%rsi), %rax
    cmp     $SEEN_AGGREGATE, %rax
    jne     61f
    cmp     %r13, SeenBits_b(%rsi)          # archived: a target epoch before the first kept
    jb      66f
    jmp     65f
61: cmp     $SEEN_CONTRIBUTION, %rax
    jne     65f
    cmp     %r14, SeenBits_a(%rsi)          # a contribution: its slot kept from s - 1
    jb      66f
65: cmp     %rsi, %rdx
    je      67f
    xor     %r11d, %r11d
64: movdqu  (%rsi,%r11), %xmm0
    movdqu  %xmm0, (%rdx,%r11)
    add     $16, %r11
    cmp     $SeenBits__mem, %r11
    jb      64b
67: add     $SeenBits__mem, %rdx
66: add     $SeenBits__mem, %rsi
    dec     %rcx
    jmp     6b
69: mov     Seen_bits(%rbx), %rax
    add     %rbx, %rax
    mov     %rdx, %rdi
    sub     %rax, %rdx
    mov     %rdx, %rax
    xor     %edx, %edx
    mov     $SeenBits__mem, %ecx
    div     %rcx
    mov     (Seen_bits + 8)(%rbx), %rsi
    mov     %rax, (Seen_bits + 8)(%rbx)
    sub     %rax, %rsi
    imul    $SeenBits__mem, %rsi
    call    lantern_zero
    xor     %eax, %eax
    LEAVE 96
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 96
END_FUNCTION lantern_seen_archive

/*
 * rax = the first entry of HIST kind rsi whose first rcx words equal the rcx words at rdx, in the chunk of
 * epoch r8 of history rdi, and rdx its chunk; or rax = 0. rbx history, rbp the key, r12 key words, r13 an
 * entry's bytes, r14 the entries, r15 the first entry; r8 the low bound, r9 the high bound, r10 the middle.
 */
LOCAL_FUNCTION lantern_seen_history_find
    ENTER 0
    mov     %rdi, %rbx
    mov     %rdx, %rbp
    mov     %rcx, %r12
    test    %rbx, %rbx
    jz      9f
    mov     %r8, %rax
    sub     SeenHistory_first_epoch(%rbx), %rax
    jb      9f
    cmp     SeenHistory_capacity(%rbx), %rax
    jae     9f
    imul    $SEEN_HISTORY_ENTRY, %rax       # the epoch's entry, inside the file's bytes
    add     $SEEN_HISTORY_FIXED, %rax
    lea     (%rax,%rsi,8), %rax
    lea     8(%rax), %rcx
    cmp     SeenHistory_size(%rbx), %rcx
    ja      9f
    mov     (%rbx,%rax), %rdx
    test    %rdx, %rdx
    jz      9f
    mov     SeenHistory_size(%rbx), %rcx    # the chunk, inside the file's bytes
    cmp     %rcx, %rdx
    jae     9f
    sub     %rdx, %rcx
    cmp     $SEEN_CHUNK_FIXED, %rcx
    jb      9f
    add     %rbx, %rdx
    cmp     %rcx, SeenChunk_bytes(%rdx)
    ja      9f
    cmp     %rsi, SeenChunk_kind(%rdx)
    jne     9f
    HIST_ELEM %r13, %rsi
    mov     SeenChunk_count(%rdx), %r14     # its entries, inside the chunk
    mov     %rdx, %r15
    mov     %r14, %rax
    mul     %r13
    jc      9f
    add     $SEEN_CHUNK_FIXED, %rax
    cmp     SeenChunk_bytes(%r15), %rax
    ja      9f
    mov     %r15, %rdx
    add     $SEEN_CHUNK_FIXED, %r15
    xor     %r8d, %r8d                      # the first entry not below the key
    mov     %r14, %r9
1:  cmp     %r9, %r8
    jae     3f
    lea     (%r8,%r9), %r10
    shr     $1, %r10
    mov     %r10, %rsi
    imul    %r13, %rsi
    add     %r15, %rsi
    xor     %ecx, %ecx
2:  cmp     %r12, %rcx
    jae     21f
    mov     (%rsi,%rcx,8), %rax
    cmp     (%rbp,%rcx,8), %rax
    jb      22f
    ja      21f
    inc     %rcx
    jmp     2b
22: lea     1(%r10), %r8
    jmp     1b
21: mov     %r10, %r9
    jmp     1b
3:  cmp     %r14, %r8
    jae     9f
    mov     %r8, %rsi
    imul    %r13, %rsi
    add     %r15, %rsi
    xor     %ecx, %ecx
4:  cmp     %r12, %rcx
    jae     5f
    mov     (%rsi,%rcx,8), %rax
    cmp     (%rbp,%rcx,8), %rax
    jne     9f
    inc     %rcx
    jmp     4b
5:  mov     %rsi, %rax
    LEAVE 0
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_seen_history_find

/*
 * (seen, history, recall, mark): networking.md. rbx seen, rbp history, r12 recall, r13 mark, r14 the items
 * left, r15 the item. Locals: L a key of 6 words, L+48 the keys to add, L+56 the bits, L+64 0 while counting,
 * 1 while adding, L+72 the entry, L+80 the chunk, L+88 the end of the chunk's entries.
 */
FUNCTION lantern_seen_recall
    ENTER 96
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     (Seen_keys + 8)(%rbx), %rax
    mov     %rax, SeenMark_keys(%r13)
    movq    $0, SeenMark_added_keys(%r13)
    mov     (Seen_bits + 8)(%rbx), %rax
    mov     %rax, SeenMark_bits(%r13)
    movq    $0, SeenMark_added_bits(%r13)
    movq    $0, (L + 48)(%rsp)
    movq    $0, (L + 56)(%rsp)
    movq    $0, (L + 64)(%rsp)
0:  mov     SeenRecall_count(%r12), %r14
    cmp     $SEEN_RECALL_MAX, %r14
    ja      99f
    lea     SeenRecall_items(%r12), %r15
1:  test    %r14, %r14
    jz      80f
    mov     SeenRecallItem_kind(%r15), %rax
    cmp     $SEEN_RECALL_BITS, %rax
    je      20f
    mov     SeenRecallItem_a(%r15), %rcx
    mov     %rcx, L(%rsp)
    mov     SeenRecallItem_b(%r15), %rdx
    mov     %rdx, (L + 8)(%rsp)
    mov     SeenRecallItem_c(%r15), %rdx
    mov     %rdx, (L + 16)(%rsp)
    mov     %rcx, %r8                       # the epoch of a
    mov     $HIST_ATTESTATION, %esi
    mov     $2, %r9d
    cmp     $SEEN_ATTESTATION, %rax
    je      10f
    mov     $HIST_AGGREGATOR, %esi
    cmp     $SEEN_AGGREGATOR_EPOCH, %rax
    je      10f
    mov     %rax, %r10                      # or of the slot a
    mov     %rcx, %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %r8
    mov     %r10, %rax
    mov     $HIST_COLUMN, %esi
    mov     $3, %r9d
    cmp     $SEEN_DATA_COLUMN, %rax
    je      10f
    mov     $HIST_BLOB, %esi
    cmp     $SEEN_BLOB_SIDECAR, %rax
    jne     70f
10: PART    %rdi, %rcx, %rbx, Seen_keys     # seen holds it already: nothing to add
11: test    %rcx, %rcx
    jz      12f
    cmp     %rax, (%rdi)
    jne     13f
    mov     L(%rsp), %rdx
    cmp     %rdx, 8(%rdi)
    jne     13f
    mov     (L + 8)(%rsp), %rdx
    cmp     %rdx, 16(%rdi)
    jne     13f
    mov     (L + 16)(%rsp), %rdx
    cmp     %rdx, 24(%rdi)
    je      70f
13: add     $SeenKey__mem, %rdi
    dec     %rcx
    jmp     11b
12: mov     %rbp, %rdi
    lea     L(%rsp), %rdx
    mov     %r9, %rcx
    call    lantern_seen_history_find
    test    %rax, %rax
    jz      70f
    cmpq    $0, (L + 64)(%rsp)
    jne     14f
    incq    (L + 48)(%rsp)
    jmp     70f
14: PART    %rdi, %rcx, %rbx, Seen_keys     # the key, after the others
    mov     %rcx, %rax
    shl     $5, %rax
    add     %rax, %rdi
    mov     SeenRecallItem_kind(%r15), %rax
    mov     %rax, 0(%rdi)
    mov     SeenRecallItem_a(%r15), %rax
    mov     %rax, 8(%rdi)
    mov     SeenRecallItem_b(%r15), %rax
    mov     %rax, 16(%rdi)
    mov     SeenRecallItem_c(%r15), %rax
    mov     %rax, 24(%rdi)
    incq    (Seen_keys + 8)(%rbx)
    incq    SeenMark_added_keys(%r13)
    jmp     70f
20: lea     SeenRecallItem_root(%r15), %rax # bits: none of (root, a, epoch) in seen
    lea     L(%rsp), %rdx
    COPY32  %rdx, %rax
    mov     SeenRecallItem_a(%r15), %rax
    mov     %rax, (L + 32)(%rsp)
    mov     SeenRecallItem_b(%r15), %rax
    mov     %rax, (L + 40)(%rsp)
    PART    %rdi, %rcx, %rbx, Seen_bits
21: test    %rcx, %rcx
    jz      22f
    cmpq    $SEEN_AGGREGATE, SeenBits_kind(%rdi)
    jne     23f
    mov     (L + 32)(%rsp), %rax
    cmp     %rax, SeenBits_a(%rdi)
    jne     23f
    mov     (L + 40)(%rsp), %rax
    cmp     %rax, SeenBits_b(%rdi)
    jne     23f
    lea     SeenBits_root(%rdi), %rax
    lea     L(%rsp), %rdx
    NE32    %rax, %rdx, 23f
    jmp     70f
23: add     $SeenBits__mem, %rdi
    dec     %rcx
    jmp     21b
22: mov     %rbp, %rdi
    mov     $HIST_AGGREGATE, %esi
    lea     L(%rsp), %rdx
    mov     $6, %ecx
    mov     (L + 40)(%rsp), %r8
    call    lantern_seen_history_find
    test    %rax, %rax
    jz      70f
    mov     %rax, (L + 72)(%rsp)
    mov     %rdx, (L + 80)(%rsp)
    mov     SeenChunk_count(%rdx), %rax
    imul    $HistBits__mem, %rax
    lea     SEEN_CHUNK_FIXED(%rdx,%rax), %rax
    mov     %rax, (L + 88)(%rsp)
24: mov     (L + 72)(%rsp), %rsi            # each entry of the key
    cmp     (L + 88)(%rsp), %rsi
    jae     70f
    xor     %ecx, %ecx
25: cmp     $6, %rcx
    jae     26f
    mov     (%rsi,%rcx,8), %rax
    cmp     L(%rsp,%rcx,8), %rax
    jne     70f
    inc     %rcx
    jmp     25b
26: mov     HistBits_length(%rsi), %r8      # its bits inside the chunk, at most SEEN_BITS_BYTES
    cmp     $(SEEN_BITS_BYTES * 8), %r8
    ja      29f
    mov     HistBits_bits(%rsi), %r9
    lea     63(%r8), %r10
    shr     $6, %r10
    shl     $3, %r10
    mov     (L + 80)(%rsp), %rdx
    mov     SeenChunk_bytes(%rdx), %rax
    cmp     %rax, %r9
    jae     29f
    sub     %r9, %rax
    cmp     %rax, %r10
    ja      29f
    cmpq    $0, (L + 64)(%rsp)
    jne     27f
    incq    (L + 56)(%rsp)
    jmp     29f
27: PART    %rdi, %rcx, %rbx, Seen_bits     # the SeenBits, after the others
    imul    $SeenBits__mem, %rcx
    add     %rcx, %rdi
    movq    $SEEN_AGGREGATE, SeenBits_kind(%rdi)
    lea     SeenBits_root(%rdi), %rax
    COPY32  %rax, %rsi
    mov     HistBits_a(%rsi), %rax
    mov     %rax, SeenBits_a(%rdi)
    mov     HistBits_epoch(%rsi), %rax
    mov     %rax, SeenBits_b(%rdi)
    mov     %r8, SeenBits_length(%rdi)
    add     %rdx, %r9
    xor     %ecx, %ecx
28: cmp     %r10, %rcx
    jae     281f
    mov     (%r9,%rcx), %rax
    mov     %rax, SeenBits_bits(%rdi,%rcx)
    add     $8, %rcx
    jmp     28b
281: incq   (Seen_bits + 8)(%rbx)
    incq    SeenMark_added_bits(%r13)
29: addq    $HistBits__mem, (L + 72)(%rsp)
    jmp     24b
70: add     $SeenRecallItem__mem, %r15
    dec     %r14
    jmp     1b
80: cmpq    $0, (L + 64)(%rsp)              # counted: room for them, then add them
    jne     90f
    mov     Seen_bits(%rbx), %rax
    sub     Seen_keys(%rbx), %rax
    shr     $5, %rax
    sub     (Seen_keys + 8)(%rbx), %rax
    cmp     (L + 48)(%rsp), %rax
    jb      98f
    mov     Seen_blocks(%rbx), %rax
    sub     Seen_bits(%rbx), %rax
    xor     %edx, %edx
    mov     $SeenBits__mem, %ecx
    div     %rcx
    sub     (Seen_bits + 8)(%rbx), %rax
    cmp     (L + 56)(%rsp), %rax
    jb      98f
    movq    $1, (L + 64)(%rsp)
    jmp     0b
90: xor     %eax, %eax
    LEAVE 96
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 96
99: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 96
END_FUNCTION lantern_seen_recall

/* (seen, mark): networking.md. A leaf; uses rax, rcx, rdx, rsi, r8-r11. */
LEAF lantern_seen_forget
    mov     SeenMark_keys(%rsi), %r8        # the keys it added: those after them move down, zero after
    mov     SeenMark_added_keys(%rsi), %r9
    test    %r9, %r9
    jz      2f
    PART    %r10, %r11, %rdi, Seen_keys
    shl     $5, %r8
    add     %r8, %r10                       # the first added
    mov     %r9, %rax
    shl     $5, %rax
    lea     (%r10,%rax), %rcx               # the first after them
    mov     (Seen_keys + 8)(%rdi), %rdx
    sub     SeenMark_keys(%rsi), %rdx
    sub     %r9, %rdx
    shl     $5, %rdx
1:  test    %rdx, %rdx
    jz      11f
    mov     (%rcx), %rax
    mov     %rax, (%r10)
    add     $8, %rcx
    add     $8, %r10
    sub     $8, %rdx
    jmp     1b
11: sub     %r9, (Seen_keys + 8)(%rdi)
    shl     $5, %r9
12: movq    $0, (%r10)
    add     $8, %r10
    sub     $8, %r9
    jnz     12b
2:  mov     SeenMark_bits(%rsi), %r8        # the same for the bits
    mov     SeenMark_added_bits(%rsi), %r9
    test    %r9, %r9
    jz      9f
    PART    %r10, %r11, %rdi, Seen_bits
    imul    $SeenBits__mem, %r8
    add     %r8, %r10
    imul    $SeenBits__mem, %r9, %rax
    lea     (%r10,%rax), %rcx
    mov     (Seen_bits + 8)(%rdi), %rdx
    sub     SeenMark_bits(%rsi), %rdx
    sub     %r9, %rdx
    imul    $SeenBits__mem, %rdx
3:  test    %rdx, %rdx
    jz      31f
    mov     (%rcx), %rax
    mov     %rax, (%r10)
    add     $8, %rcx
    add     $8, %r10
    sub     $8, %rdx
    jmp     3b
31: sub     %r9, (Seen_bits + 8)(%rdi)
    imul    $SeenBits__mem, %r9
32: movq    $0, (%r10)
    add     $8, %r10
    sub     $8, %r9
    jnz     32b
9:  xor     %eax, %eax
    ret
END_FUNCTION lantern_seen_forget

/* Part ref of seen rbx takes the count at rbp + at; zero the bytes of the entries past it, of size bytes each. */
.macro SEEN_RESTORE ref, at, size
    mov     \at(%rbp), %rax
    mov     ((\ref) + 8)(%rbx), %rcx
    mov     %rax, ((\ref) + 8)(%rbx)
    sub     %rax, %rcx
    jbe     107f
    imul    $(\size), %rcx, %rsi
    imul    $(\size), %rax, %rdi
    add     (\ref)(%rbx), %rdi
    add     %rbx, %rdi
    call    lantern_zero
107:
.endm

/* (seen, counts): networking.md. rbx seen, rbp counts. */
FUNCTION lantern_seen_restore
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    SEEN_RESTORE Seen_keys, 0, SeenKey__mem
    SEEN_RESTORE Seen_bits, 8, SeenBits__mem
    SEEN_RESTORE Seen_blocks, 16, SeenBlock__mem
    mov     24(%rbp), %rax                  # the headers: their count, and zero after their bytes
    mov     %rax, (Seen_headers + 8)(%rbx)
    mov     32(%rbp), %rax
    mov     Seen_header_bytes(%rbx), %rcx
    mov     %rax, Seen_header_bytes(%rbx)
    sub     %rax, %rcx
    jbe     9f
    mov     %rcx, %rsi
    mov     Seen_headers(%rbx), %rdi
    add     %rbx, %rdi
    add     %rax, %rdi
    call    lantern_zero
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_seen_restore

/*
 * (a, b, out): networking.md. rbx a, rbp b, r12 the merged chunk, r13 the words compared, r14 the entry
 * bytes, r15 the kind, r8 a's next entry, r9 a's entries left, r10 b's next entry, rdx the next entry
 * written. Locals: L the next word of bits, L+8 the chunk of the entry taken, L+16 b's entries left.
 */
FUNCTION lantern_seen_chunk_merge
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     SeenChunk_bytes(%rbx), %rax     # the merged chunk's bytes
    add     SeenChunk_bytes(%rbp), %rax
    sub     $SEEN_CHUNK_FIXED, %rax
    mov     (%rdx), %rcx                    # out has room for them
    sub     8(%rdx), %rcx
    jb      98f
    sub     16(%rdx), %rcx
    jb      98f
    cmp     %rax, %rcx
    jb      98f
    mov     8(%rdx), %r12
    add     16(%rdx), %r12
    add     %rdx, %r12
    add     %rax, 16(%rdx)
    mov     %rax, SeenChunk_bytes(%r12)
    mov     SeenChunk_kind(%rbx), %r15
    mov     %r15, SeenChunk_kind(%r12)
    HIST_ELEM %r14, %r15
    mov     %r14, %r13
    shr     $3, %r13
    cmp     $HIST_AGGREGATE, %r15
    jne     1f
    mov     $6, %r13d                       # the root, a and the epoch
1:  mov     SeenChunk_epoch_lo(%rbx), %rax
    mov     SeenChunk_epoch_lo(%rbp), %rcx
    cmp     %rcx, %rax
    cmova   %rcx, %rax
    mov     %rax, SeenChunk_epoch_lo(%r12)
    mov     SeenChunk_epoch_hi(%rbx), %rax
    mov     SeenChunk_epoch_hi(%rbp), %rcx
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    mov     %rax, SeenChunk_epoch_hi(%r12)
    mov     SeenChunk_count(%rbx), %r9
    mov     SeenChunk_count(%rbp), %rax
    mov     %rax, (L + 16)(%rsp)
    add     %r9, %rax
    mov     %rax, SeenChunk_count(%r12)
    lea     SEEN_CHUNK_FIXED(%rbx), %r8
    lea     SEEN_CHUNK_FIXED(%rbp), %r10
    lea     SEEN_CHUNK_FIXED(%r12), %rdx
    imul    %r14, %rax                      # the bits follow the entries
    add     %rdx, %rax
    mov     %rax, L(%rsp)
2:  test    %r9, %r9                        # the lower entry next; a's first when equal
    jnz     21f
    cmpq    $0, (L + 16)(%rsp)
    je      8f
    jmp     31f
21: cmpq    $0, (L + 16)(%rsp)
    je      30f
    mov     %r10, %rsi
    mov     %r8, %rdi
    SORT_LESS 31f, 30f
30: mov     %r8, %rsi
    mov     %rbx, (L + 8)(%rsp)
    add     %r14, %r8
    dec     %r9
    jmp     3f
31: mov     %r10, %rsi
    mov     %rbp, (L + 8)(%rsp)
    add     %r14, %r10
    decq    (L + 16)(%rsp)
3:  mov     %rdx, %rdi                      # the entry
    mov     %r14, %rcx
    shr     $3, %rcx
    rep movsq
    cmp     $HIST_AGGREGATE, %r15
    jne     35f
    mov     %rsi, %rax                      # and its bits, at their new offset
    sub     %r14, %rax
    mov     HistBits_length(%rax), %rcx
    add     $63, %rcx
    shr     $6, %rcx
    mov     HistBits_bits(%rax), %rsi
    add     (L + 8)(%rsp), %rsi
    mov     L(%rsp), %rax
    mov     %rax, %r11
    sub     %r12, %r11
    mov     %r11, HistBits_bits(%rdx)
    mov     %rdi, %r11
    mov     %rax, %rdi
    rep movsq
    mov     %rdi, L(%rsp)
    mov     %r11, %rdi
35: mov     %rdi, %rdx
    jmp     2b
8:  xor     %eax, %eax
    LEAVE 32
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
END_FUNCTION lantern_seen_chunk_merge
