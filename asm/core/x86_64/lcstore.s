# The light client store, x86-64: in the common object. Requirements: docs/reference/light-client.md.

.set LC_SPP, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD   # the slots of a sync committee period

# rax += the room field k of the store rdi times mem, for part rsi above k; else to 9f. Uses rcx.
.macro LC_PART_STEP k, mem
    cmp     $\k, %rsi
    jbe     9f
    mov     (LcStore_room + 8 * \k)(%rdi), %rcx
    imul    $(\mem), %rcx
    add     %rcx, %rax
.endm

# L0: rax = the first entry or record of part rsi of the store rdi. Uses rcx.
LOCAL_FUNCTION lc_part
    UNWIND_END_PROLOGUE
    mov     $LC_STORE_FIXED, %eax
    LC_PART_STEP 0, LcBlock__mem
    LC_PART_STEP 1, LcFinalized__mem
    LC_PART_STEP 2, LcPeriod__mem
    LC_PART_STEP 3, LcBootstrap__mem
    LC_PART_STEP 4, LcHeader__mem
    LC_PART_STEP 5, LcCommittee__mem
9:  add     %rdi, %rax
    ret
END_FUNCTION lc_part

# L0: rcx = the bytes of an entry or record of part rsi.
LOCAL_FUNCTION lc_mem
    UNWIND_END_PROLOGUE
    mov     $LcBlock__mem, %ecx
    cmp     $LC_PART_BLOCKS, %rsi
    je      1f
    mov     $LcFinalized__mem, %ecx
    cmp     $LC_PART_FINALIZED, %rsi
    je      1f
    mov     $LcPeriod__mem, %ecx
    cmp     $LC_PART_PERIODS, %rsi
    je      1f
    mov     $LcBootstrap__mem, %ecx
    cmp     $LC_PART_BOOTSTRAPS, %rsi
    je      1f
    mov     $LcHeader__mem, %ecx
    cmp     $LC_PART_HEADERS, %rsi
    je      1f
    mov     $LcCommittee__mem, %ecx
    cmp     $LC_PART_COMMITTEES, %rsi
    je      1f
    mov     $LcUpdate__mem, %ecx
1:  ret
END_FUNCTION lc_mem

# L1: rax = entry or record rdx (an index) of part rsi of the store rdi; rdi, rsi, rdx, r9 kept. Uses rcx, r8.
LOCAL_FUNCTION lc_at
    FRAME 0
    call    lc_part
    call    lc_mem
    mov     %rcx, %r8
    imul    %rdx, %r8
    add     %r8, %rax
    UNFRAME 0
END_FUNCTION lc_at

# L1: rax = record rdx (a reference, not 0) of part rsi of the store rdi; rdi, rsi, rdx, r9 kept. Uses rcx, r8.
LOCAL_FUNCTION lc_ref
    FRAME 0
    dec     %rdx
    call    lc_at
    inc     %rdx
    UNFRAME 0
END_FUNCTION lc_ref

# L1: rax = the reference of a free record of part rsi of the store rdi, now LC_USED; 0 with none. Uses rcx, rdx, r8.
LOCAL_FUNCTION lc_alloc
    FRAME 0
    call    lc_part
    call    lc_mem
    mov     LcStore_room(%rdi,%rsi,8), %r8
    xor     %edx, %edx
1:  cmp     %r8, %rdx
    jae     8f
    cmpq    $LC_FREE, (%rax)
    je      2f
    add     %rcx, %rax
    inc     %rdx
    jmp     1b
2:  movq    $LC_USED, (%rax)
    lea     1(%rdx), %rax
    UNFRAME 0
8:  xor     %eax, %eax
    UNFRAME 0
END_FUNCTION lc_alloc

# L1: rax = the free records of part rsi of the store rdi. Uses rcx, rdx, r8, r9.
LOCAL_FUNCTION lc_free_count
    FRAME 0
    call    lc_part
    call    lc_mem
    mov     LcStore_room(%rdi,%rsi,8), %r8
    xor     %edx, %edx
1:  test    %r8, %r8
    jz      2f
    xor     %r9d, %r9d
    cmpq    $LC_FREE, (%rax)
    sete    %r9b
    add     %r9, %rdx
    add     %rcx, %rax
    dec     %r8
    jmp     1b
2:  mov     %rdx, %rax
    UNFRAME 0
END_FUNCTION lc_free_count

# L1: record rdx (a reference, or 0 for none) of part rsi of the store rdi becomes LC_MARKED. Uses rax, rcx, r8.
LOCAL_FUNCTION lc_mark
    FRAME 0
    test    %rdx, %rdx
    jz      1f
    call    lc_ref
    movq    $LC_MARKED, (%rax)
1:  UNFRAME 0
END_FUNCTION lc_mark

# L1: rbx's marks of field off of the entry rbp: lc_mark of part, with the store rbx.
.macro LC_MARK_FIELD part, off
    mov     %rbx, %rdi
    mov     $\part, %esi
    mov     \off(%rbp), %rdx
    call    lc_mark
.endm

# L1: the records of the store rdi that nothing refers to become LC_FREE (LcStore, Rules). rbx the
# store, rbp an entry or record, r12 the ones left, r13 the part, r14 its bytes.
LOCAL_FUNCTION lc_collect
    ENTER 0
    mov     %rdi, %rbx
    mov     $LC_PART_BLOCKS, %esi           # the blocks' header, committees and best update
    call    lc_part
    mov     %rax, %rbp
    mov     LcStore_blocks(%rbx), %r12
1:  test    %r12, %r12
    jz      2f
    LC_MARK_FIELD LC_PART_HEADERS, LcBlock_header
    LC_MARK_FIELD LC_PART_COMMITTEES, LcBlock_current_sync_committee
    LC_MARK_FIELD LC_PART_COMMITTEES, LcBlock_next_sync_committee
    LC_MARK_FIELD LC_PART_UPDATES, LcBlock_best
    add     $LcBlock__mem, %rbp
    dec     %r12
    jmp     1b
2:  mov     %rbx, %rdi                      # the bootstraps' header and committee
    mov     $LC_PART_BOOTSTRAPS, %esi
    call    lc_part
    mov     %rax, %rbp
    mov     LcStore_bootstraps(%rbx), %r12
3:  test    %r12, %r12
    jz      4f
    LC_MARK_FIELD LC_PART_HEADERS, LcBootstrap_header
    LC_MARK_FIELD LC_PART_COMMITTEES, LcBootstrap_sync_committee
    add     $LcBootstrap__mem, %rbp
    dec     %r12
    jmp     3b
4:  mov     %rbx, %rdi                      # the periods' updates, and latest
    mov     $LC_PART_PERIODS, %esi
    call    lc_part
    mov     %rax, %rbp
    mov     LcStore_periods(%rbx), %r12
5:  test    %r12, %r12
    jz      6f
    LC_MARK_FIELD LC_PART_UPDATES, LcPeriod_update
    add     $LcPeriod__mem, %rbp
    dec     %r12
    jmp     5b
6:  mov     %rbx, %rbp
    LC_MARK_FIELD LC_PART_UPDATES, LcStore_latest
    mov     %rbx, %rdi                      # each marked update's headers and committee
    mov     $LC_PART_UPDATES, %esi
    call    lc_part
    mov     %rax, %rbp
    mov     (LcStore_room + LcRoom_updates)(%rbx), %r12
7:  test    %r12, %r12
    jz      10f
    cmpq    $LC_MARKED, LcUpdate_state(%rbp)
    jne     8f
    LC_MARK_FIELD LC_PART_HEADERS, LcUpdate_attested_header
    LC_MARK_FIELD LC_PART_HEADERS, LcUpdate_finalized_header
    LC_MARK_FIELD LC_PART_COMMITTEES, LcUpdate_next_sync_committee
8:  add     $LcUpdate__mem, %rbp
    dec     %r12
    jmp     7b
10: mov     $LC_PART_HEADERS, %r13d         # the sweep: LC_USED goes, LC_MARKED stays
11: mov     %rbx, %rdi
    mov     %r13, %rsi
    call    lc_part
    call    lc_mem
    mov     %rax, %rbp
    mov     %rcx, %r14
    mov     LcStore_room(%rbx,%r13,8), %r12
12: test    %r12, %r12
    jz      14f
    xor     %eax, %eax
    cmpq    $LC_MARKED, (%rbp)
    sete    %al                             # LC_MARKED: LC_USED; else LC_FREE
    mov     %rax, (%rbp)
    add     %r14, %rbp
    dec     %r12
    jmp     12b
14: inc     %r13
    cmp     $LC_PART_UPDATES, %r13
    jbe     11b
    LEAVE 0
END_FUNCTION lc_collect

# L1: rax = LANTERN_OK when the store rdi has rsi free headers, rdx committees and rcx updates, once
# the records nothing refers to are freed; else LANTERN_BUFFER_TOO_SMALL. rbx the store, rbp, r12
# and r13 the needs, r14 1 once collected, r15 the part.
LOCAL_FUNCTION lc_reserve
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    xor     %r14d, %r14d
1:  mov     $LC_PART_HEADERS, %r15d
2:  mov     %rbx, %rdi
    mov     %r15, %rsi
    call    lc_free_count
    mov     %rbp, %rcx
    cmp     $LC_PART_COMMITTEES, %r15
    cmove   %r12, %rcx
    cmova   %r13, %rcx
    cmp     %rcx, %rax
    jae     3f
    test    %r14, %r14
    jnz     9f
    mov     %rbx, %rdi
    call    lc_collect
    mov     $1, %r14d
    jmp     1b
3:  inc     %r15
    cmp     $LC_PART_UPDATES, %r15
    jbe     2b
    xor     %eax, %eax
    LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION lc_reserve

# L1: rax = the index plus 1 of the LcBlock of the root at rsi in the store rdi, or 0. Uses rcx, rdx, rsi, r8, r9, r11, xmm0-xmm2.
LOCAL_FUNCTION lc_find_block
    FRAME 0
    mov     LcStore_blocks(%rdi), %r9
    mov     %rsi, %r8
    mov     $LC_PART_BLOCKS, %esi
    call    lc_part
    xor     %edx, %edx
1:  cmp     %r9, %rdx
    jae     3f
    NE32    %rax, %r8, 2f
    lea     1(%rdx), %rax
    UNFRAME 0
2:  add     $LcBlock__mem, %rax
    inc     %rdx
    jmp     1b
3:  xor     %eax, %eax
    UNFRAME 0
END_FUNCTION lc_find_block

# L1: rax = the entry (index plus 1) of the highest slot at most rdx along the parents from entry rsi
# of the store rdi, or 0. Uses rcx, rdx, rsi, r8, r9.
LOCAL_FUNCTION lc_ancestor
    FRAME 0
    mov     %rdx, %r9
    mov     %rsi, %rdx
    mov     $LC_PART_BLOCKS, %esi
1:  test    %rdx, %rdx
    jz      3f
    call    lc_ref
    cmp     %r9, LcBlock_slot(%rax)
    jbe     2f
    mov     LcBlock_parent(%rax), %rdx
    jmp     1b
2:  mov     %rdx, %rax
    UNFRAME 0
3:  xor     %eax, %eax
    UNFRAME 0
END_FUNCTION lc_ancestor

# L1: rax = the LcFinalized of the highest slot at most rsi and at least historical_tail_slot in the store rdi, or 0. Uses rcx, rdx, rsi, r8, r9.
LOCAL_FUNCTION lc_finalized_at
    FRAME 0
    mov     LcStore_finalized(%rdi), %rdx
    mov     LcStore_historical_tail_slot(%rdi), %r9
    mov     %rsi, %r8
    mov     $LC_PART_FINALIZED, %esi
    call    lc_part
    imul    $LcFinalized__mem, %rdx, %rcx
    add     %rcx, %rax
1:  test    %rdx, %rdx
    jz      3f
    sub     $LcFinalized__mem, %rax
    dec     %rdx
    mov     LcFinalized_slot(%rax), %rcx
    cmp     %r8, %rcx
    ja      1b
    cmp     %r9, %rcx
    jb      3f
    UNFRAME 0
3:  xor     %eax, %eax
    UNFRAME 0
END_FUNCTION lc_finalized_at

# L0: rax = the set bits of the sync_committee_bits at rdi. Uses rcx, rdx, rsi.
LOCAL_FUNCTION lc_participants
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    xor     %esi, %esi
1:  cmp     $(SYNC_COMMITTEE_SIZE / 8), %rsi
    jae     3f
    movzbl  (%rdi,%rsi), %ecx
2:  test    %ecx, %ecx
    jz      21f
    lea     -1(%rcx), %edx
    and     %edx, %ecx
    inc     %rax
    jmp     2b
21: inc     %rsi
    jmp     1b
3:  ret
END_FUNCTION lc_participants

# rcx = the roots of a sync committee branch, rdx of a finality branch, of the fork rcx.
.macro LC_COUNTS
    xor     %edx, %edx
    cmp     $FORK_ELECTRA, %rcx
    setae   %dl
    lea     5(%rdx), %ecx
    add     $(6), %edx
.endm

# L0: rax = 1 when the rdx bytes at rdi and rsi are equal, rdx a multiple of 8; else 0. Uses rcx.
LOCAL_FUNCTION lc_equal
    UNWIND_END_PROLOGUE
1:  test    %rdx, %rdx
    jz      2f
    mov     (%rdi), %rcx
    add     $8, %rdi
    sub     $8, %rdx
    cmp     (%rsi), %rcx
    lea     8(%rsi), %rsi
    je      1b
    xor     %eax, %eax
    ret
2:  mov     $1, %eax
    ret
END_FUNCTION lc_equal

# L1: rax = an LcCommittee reference of the sync committee bytes rsi in the store rdi: rdx or rcx
# (each a reference or 0) when its bytes are equal, else a new record. rbx the store, rbp the
# bytes, r12 and r13 the candidates, r14 the reference.
LOCAL_FUNCTION lc_committee
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r12, %r14
1:  test    %r14, %r14
    jz      2f
    mov     %rbx, %rdi
    mov     $LC_PART_COMMITTEES, %esi
    mov     %r14, %rdx
    call    lc_ref
    lea     LcCommittee_committee(%rax), %rdi
    mov     %rbp, %rsi
    mov     $LC_COMMITTEE, %edx
    call    lc_equal
    test    %rax, %rax
    jnz     4f
2:  cmp     %r13, %r14
    je      3f
    mov     %r13, %r14
    jmp     1b
3:  mov     %rbx, %rdi
    mov     $LC_PART_COMMITTEES, %esi
    call    lc_alloc
    mov     %rax, %r14
    mov     %rbx, %rdi
    mov     $LC_PART_COMMITTEES, %esi
    mov     %r14, %rdx
    call    lc_ref
    lea     LcCommittee_committee(%rax), %rdi
    mov     %rbp, %rsi
    mov     $LC_COMMITTEE, %edx
    call    lantern_copy
4:  mov     %r14, %rax
    LEAVE 0
END_FUNCTION lc_committee

# L1: hash_tree_root of the BeaconBlockHeader at rdi (its 112 SSZ bytes) at rsi. rbx the header,
# rbp out, r12 the 8 chunks, r13 the pairs of the level, r14 the pair. Locals: L a ByteList, L + 32
# a digest, L + 64 the chunks.
LOCAL_FUNCTION lc_beacon_root
    ENTER 320
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     (L + 64)(%rsp), %r12
    mov     %r12, %rdi
    mov     $256, %esi
    call    lantern_zero
    mov     (%rbx), %rax                    # slot, proposer_index, then the three roots
    mov     %rax, (%r12)
    mov     8(%rbx), %rax
    mov     %rax, 32(%r12)
    lea     64(%r12), %rdi
    lea     16(%rbx), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     $4, %r13d
1:  xor     %r14d, %r14d
2:  mov     %r14, %rax
    shl     $6, %rax
    add     $64, %rax                       # the pair's offset from the ByteList at L
    lea     64(%rax), %rcx
    mov     %rcx, L(%rsp)
    mov     %rax, (L + 8)(%rsp)
    movq    $64, (L + 16)(%rsp)
    lea     L(%rsp), %rdi
    lea     (L + 32)(%rsp), %rsi
    CALL_GLOBAL crypto_sha256
    mov     %r14, %rax
    shl     $5, %rax
    add     %r12, %rax
    lea     (L + 32)(%rsp), %rcx
    COPY32  %rax, %rcx
    inc     %r14
    cmp     %r13, %r14
    jb      2b
    shr     $1, %r13
    jnz     1b
    COPY32  %rbp, %r12
    LEAVE 320
END_FUNCTION lc_beacon_root

# L1: rax = a new LcHeader of the fork rsi in the store rdi (reserved before), the empty header of
# the fork: lantern_upgrade_lc_header of 112 zero bytes from altair. rbx the store, rbp the fork,
# r12 the reference. Locals: L the ByteList of the zero bytes.
LOCAL_FUNCTION lc_empty_header
    ENTER 144
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     L(%rsp), %rdi
    mov     $144, %esi
    call    lantern_zero
    movq    $136, L(%rsp)
    movq    $24, (L + 8)(%rsp)
    movq    $112, (L + 16)(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    call    lc_alloc
    mov     %rax, %r12
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     %r12, %rdx
    call    lc_ref
    mov     %rbp, LcHeader_fork(%rax)
    movq    $(24 + LC_HEADER_ROOM), LcHeader_header(%rax)
    lea     LcHeader_header(%rax), %rdx
    lea     L(%rsp), %rdi
    mov     $FORK_ALTAIR, %esi
    mov     %rbp, %r10
    FORK_CALL upgrade_lc_header
    mov     %r12, %rax
    LEAVE 144
END_FUNCTION lc_empty_header

# L1: rax = a new LcUpdate (reserved before, with one LcHeader) in the store rdi: the update of
# entry rsi (light-client.md, The update of an entry) with the signature slot rdx, the sync
# aggregate at rcx and the LcCommittee r8 (0: a finality update). rbx the store, rbp the entry, r12
# the update's reference, r13 the update, r14 its fork, r15 a finalized entry or header; S7 the
# entry's reference, S8 the signature slot, S9 the aggregate, S10 the committee.
LOCAL_FUNCTION lc_make_update
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, S7(%rsp)
    mov     %rdx, S8(%rsp)
    mov     %rcx, S9(%rsp)
    mov     %r8, S10(%rsp)
    mov     $LC_PART_UPDATES, %esi
    call    lc_alloc
    mov     %rax, %r12
    mov     %rbx, %rdi
    mov     $LC_PART_UPDATES, %esi
    mov     %r12, %rdx
    call    lc_ref
    mov     %rax, %r13
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     S7(%rsp), %rdx
    call    lc_ref
    mov     %rax, %rbp
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     LcBlock_header(%rbp), %rdx
    call    lc_ref
    mov     LcHeader_fork(%rax), %r14
    mov     %r14, LcUpdate_fork(%r13)
    mov     LcBlock_header(%rbp), %rax
    mov     %rax, LcUpdate_attested_header(%r13)
    mov     S10(%rsp), %rax
    mov     %rax, LcUpdate_next_sync_committee(%r13)
    mov     S8(%rsp), %rax
    mov     %rax, LcUpdate_signature_slot(%r13)
    lea     LcUpdate_next_branch(%r13), %rdi
    lea     LcBlock_next_branch(%rbp), %rsi
    mov     $192, %edx
    call    lantern_copy
    lea     LcUpdate_sync_aggregate(%r13), %rdi
    mov     S9(%rsp), %rsi
    mov     $LC_AGGREGATE, %edx
    call    lantern_copy
    mov     %rbx, %rdi                      # the finalized block: the LcFinalized at the entry's finalized_slot
    mov     LcBlock_finalized_slot(%rbp), %rsi
    call    lc_finalized_at
    test    %rax, %rax
    jz      5f
    mov     %rax, %r15
    mov     LcFinalized_slot(%r15), %rax
    mov     %rax, LcBlock_finalized_slot(%rbp)
    test    %rax, %rax
    jz      4f                              # GENESIS_SLOT: the empty header, the branch
    mov     %rbx, %rdi
    lea     LcFinalized_root(%r15), %rsi
    call    lc_find_block
    test    %rax, %rax
    jz      5f
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     LcBlock_header(%rax), %rdx
    mov     %rdx, LcUpdate_finalized_header(%r13)
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    call    lc_ref
    mov     %rax, %r15
    cmp     %r14, LcHeader_fork(%r15)
    je      3f
    mov     %rbx, %rdi                      # of an earlier fork: upgraded, in a new record
    mov     $LC_PART_HEADERS, %esi
    call    lc_alloc
    mov     %rax, LcUpdate_finalized_header(%r13)
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     %r14, LcHeader_fork(%rax)
    movq    $(24 + LC_HEADER_ROOM), LcHeader_header(%rax)
    lea     LcHeader_header(%rax), %rdx
    lea     LcHeader_header(%r15), %rdi
    mov     LcHeader_fork(%r15), %rsi
    mov     %r14, %r10
    FORK_CALL upgrade_lc_header
3:  lea     LcUpdate_finality_branch(%r13), %rdi
    lea     LcBlock_finality_branch(%rbp), %rsi
    mov     $224, %edx
    call    lantern_copy
    jmp     7f
4:  lea     LcUpdate_finality_branch(%r13), %rdi
    lea     LcBlock_finality_branch(%rbp), %rsi
    mov     $224, %edx
    call    lantern_copy
    jmp     6f
5:  lea     LcUpdate_finality_branch(%r13), %rdi  # no finalized block: the empty header, a zero branch
    mov     $224, %esi
    call    lantern_zero
6:  mov     %rbx, %rdi
    mov     %r14, %rsi
    call    lc_empty_header
    mov     %rax, LcUpdate_finalized_header(%r13)
7:  mov     %r12, %rax
    LEAVE 0
END_FUNCTION lc_make_update

# L1, lc_better's: the LcParts rdx of the LcUpdate rsi of the fork rcx in the store rdi, the
# branches at their counts. rbx the store, rbp the update, r12 the parts, r13 the fork.
LOCAL_FUNCTION lc_better_parts
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     $LC_PART_HEADERS, %esi
    mov     LcUpdate_attested_header(%rbp), %rdx
    call    lc_ref
    add     $LcHeader_header, %rax
    mov     %rax, LcParts_header(%r12)
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     LcUpdate_finalized_header(%rbp), %rdx
    call    lc_ref
    add     $LcHeader_header, %rax
    mov     %rax, LcParts_finalized_header(%r12)
    mov     %rbx, %rdi
    mov     $LC_PART_COMMITTEES, %esi
    mov     LcUpdate_next_sync_committee(%rbp), %rdx
    call    lc_ref
    add     $LcCommittee_committee, %rax
    mov     %rax, LcParts_sync_committee(%r12)
    lea     LcUpdate_next_branch(%rbp), %rax
    mov     %rax, LcParts_branch(%r12)
    lea     LcUpdate_finality_branch(%rbp), %rax
    mov     %rax, LcParts_finality_branch(%r12)
    lea     LcUpdate_sync_aggregate(%rbp), %rax
    mov     %rax, LcParts_sync_aggregate(%r12)
    mov     LcUpdate_signature_slot(%rbp), %rax
    mov     %rax, LcParts_signature_slot(%r12)
    mov     %r13, %rcx
    LC_COUNTS
    mov     %rcx, LcParts_branch_count(%r12)
    mov     %rdx, LcParts_finality_count(%r12)
    LEAVE 0
END_FUNCTION lc_better_parts

# L1: rax = 1 when lantern_is_better_update of the LcUpdate rsi's fork gives 1 for it and the
# LcUpdate rdx upgraded to that fork, in the store rdi with the scratch rcx (LC_COMPARE_SCRATCH
# bytes, checked before); else 0. rbx the store, rbp the new update, r12 the old one's reference,
# r13 the scratch's buffers, r14 the new update's fork, r15 the old one's fork; S7 the old update.
# Locals: L the parts, L + 72 the answer.
LOCAL_FUNCTION lc_better
    ENTER 80
    mov     %rdi, %rbx
    mov     %rdx, %r12
    lea     8(%rcx), %r13
    mov     %rsi, %rdx
    mov     $LC_PART_UPDATES, %esi
    call    lc_ref
    mov     %rax, %rbp
    mov     LcUpdate_fork(%rbp), %r14
    mov     %rbx, %rdi                      # the new update: buffer 1
    mov     %rbp, %rsi
    lea     L(%rsp), %rdx
    mov     %r14, %rcx
    call    lc_better_parts
    movq    $(24 + LC_UPDATE_ROOM), (%r13)
    mov     $LC_OBJECT_UPDATE, %edi
    lea     L(%rsp), %rsi
    mov     %r13, %rdx
    mov     %r14, %r10
    FORK_CALL lc_object
    test    %rax, %rax
    jnz     9f
    mov     %rbx, %rdi                      # the old one, its headers upgraded: buffer 2
    mov     $LC_PART_UPDATES, %esi
    mov     %r12, %rdx
    call    lc_ref
    mov     %rax, S7(%rsp)
    mov     LcUpdate_fork(%rax), %r15
    mov     %rbx, %rdi
    mov     %rax, %rsi
    lea     L(%rsp), %rdx
    mov     %r15, %rcx
    call    lc_better_parts
    cmp     %r14, %r15
    je      1f
    lea     (2 * (24 + LC_UPDATE_ROOM))(%r13), %rdx   # the headers' buffers, after the two updates'
    movq    $(24 + LC_HEADER_ROOM), (%rdx)
    mov     (L + LcParts_header)(%rsp), %rdi
    mov     %rdx, (L + LcParts_header)(%rsp)
    mov     %r15, %rsi
    mov     %r14, %r10
    FORK_CALL upgrade_lc_header
    test    %rax, %rax
    jnz     9f
    lea     (2 * (24 + LC_UPDATE_ROOM) + 24 + LC_HEADER_ROOM)(%r13), %rdx
    movq    $(24 + LC_HEADER_ROOM), (%rdx)
    mov     (L + LcParts_finalized_header)(%rsp), %rdi
    mov     %rdx, (L + LcParts_finalized_header)(%rsp)
    mov     %r15, %rsi
    mov     %r14, %r10
    FORK_CALL upgrade_lc_header
    test    %rax, %rax
    jnz     9f
1:  lea     (24 + LC_UPDATE_ROOM)(%r13), %rdx
    movq    $(24 + LC_UPDATE_ROOM), (%rdx)
    mov     $LC_OBJECT_UPDATE, %edi
    lea     L(%rsp), %rsi
    mov     %r14, %r10
    FORK_CALL lc_object
    test    %rax, %rax
    jnz     9f
    mov     %r13, %rdi
    lea     (24 + LC_UPDATE_ROOM)(%r13), %rsi
    lea     (L + 72)(%rsp), %rdx
    mov     %r14, %r10
    FORK_CALL is_better_update
    test    %rax, %rax
    jnz     9f
    mov     (L + 72)(%rsp), %rax
    LEAVE 80
9:  xor     %eax, %eax
    LEAVE 80
END_FUNCTION lc_better

# L1: rax = status: the LcBlock of the block rcx (ByteList) with its post-state rdx in the store
# rdi, the config rsi, the StateCache r8 (or 0), the scratch r9; with rax 1 the anchor of
# lantern_lc_store_init, else lantern_lc_on_block. rbx the store, rbp config, r12 state, r13 block,
# r14 cache, r15 scratch; S7 the new entry, S8 the block's fork, S9 the header's reference, S10 the
# parent entry. Locals: L the anchor flag, L + 8 the slot, L + 16 the header's bytes, L + 24 the
# root, L + 56 the parent's reference, L + 64 the update, L + 72 the header.
LOCAL_FUNCTION lc_add_block
    ENTER 80
    mov     %rax, L(%rsp)
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     %rbx, %rdi                      # the room first
    mov     $2, %esi
    mov     $2, %edx
    mov     $1, %ecx
    call    lc_reserve
    test    %rax, %rax
    jnz     98f
    mov     LcStore_blocks(%rbx), %rax
    cmp     (LcStore_room + LcRoom_blocks)(%rbx), %rax
    jae     98f
    cmpq    $LC_COMPARE_SCRATCH, (%r15)
    jb      98f
    mov     NODE_STATE_SLOT(%r12), %rdi     # the anchor: the fork of the state's slot
    cmpq    $0, L(%rsp)
    jne     5f
    mov     8(%r13), %rax                   # else the block's slot, for its fork
    add     %r13, %rax
    mov     16(%r13), %rcx
    cmp     $4, %rcx
    jb      96f
    mov     (%rax), %edx
    lea     8(%rdx), %rsi
    cmp     %rcx, %rsi
    ja      96f
    mov     (%rax,%rdx), %rdi
5:  mov     %rbp, %rsi
    call    node_fork
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi                      # the header
    mov     $LC_PART_HEADERS, %esi
    call    lc_alloc
    mov     %rax, S9(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     %rax, (L + 72)(%rsp)
    mov     S8(%rsp), %rcx
    mov     $FORK_ALTAIR, %edx
    cmp     %rdx, %rcx
    cmovb   %rdx, %rcx
    mov     %rcx, LcHeader_fork(%rax)
    movq    $(24 + LC_HEADER_ROOM), LcHeader_header(%rax)
    lea     LcHeader_header(%rax), %rdx
    mov     %r13, %rdi
    mov     %r15, %rsi
    mov     S8(%rsp), %r10
    cmpq    $0, L(%rsp)
    jne     6f
    FORK_CALL block_to_light_client_header
    jmp     7f
6:  FORK_CALL lc_anchor_header              # the anchor: of its block's value
7:  test    %rax, %rax
    jnz     90f
    mov     (L + 72)(%rsp), %rax            # the root: of the header's beacon; the slot its slot
    add     $LcHeader_header, %rax
    mov     8(%rax), %rcx
    lea     (%rax,%rcx), %rdi
    mov     %rdi, (L + 16)(%rsp)
    mov     (%rdi), %rcx
    mov     %rcx, (L + 8)(%rsp)
    lea     (L + 24)(%rsp), %rsi
    call    lc_beacon_root
    mov     %rbx, %rdi
    lea     (L + 24)(%rsp), %rsi
    call    lc_find_block
    test    %rax, %rax
    jnz     95f
    mov     %rbx, %rdi                      # the entry, at the end of blocks
    mov     $LC_PART_BLOCKS, %esi
    mov     LcStore_blocks(%rbx), %rdx
    call    lc_at
    mov     %rax, S7(%rsp)
    mov     %rax, %rdi
    mov     $LcBlock__mem, %esi
    call    lantern_zero
    mov     S7(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    COPY32  %rdi, %rsi
    mov     (L + 16)(%rsp), %rsi
    add     $16, %rsi
    lea     LcBlock_parent_root(%rdi), %rax
    COPY32  %rax, %rsi
    mov     (L + 8)(%rsp), %rax
    mov     %rax, LcBlock_slot(%rdi)
    mov     S9(%rsp), %rax
    mov     %rax, LcBlock_header(%rdi)
    lea     LcBlock_parent_root(%rdi), %rsi
    mov     %rbx, %rdi
    call    lc_find_block
    mov     S7(%rsp), %rdi
    mov     %rax, LcBlock_parent(%rdi)
    mov     %rax, (L + 56)(%rsp)
    cmpq    $0, L(%rsp)                     # from altair, but the anchor: the body's sync_aggregate
    jne     10f
    cmpq    $FORK_ALTAIR, S8(%rsp)
    jb      10f
    mov     8(%r13), %rax
    add     %r13, %rax
    mov     (%rax), %ecx
    add     %rcx, %rax
    mov     80(%rax), %ecx
    lea     220(%rax,%rcx), %rsi
    lea     LcBlock_sync_aggregate(%rdi), %rdi
    mov     $LC_AGGREGATE, %edx
    call    lantern_copy
10: cmpq    $0, L(%rsp)
    je      11f
    cmpq    $FORK_ALTAIR, S8(%rsp)          # the anchor: data from altair
    jb      50f
    jmp     20f
11: mov     (L + 8)(%rsp), %rax
    cmp     LcStore_tail_slot(%rbx), %rax
    jb      50f
    cmpq    $0, (L + 56)(%rsp)
    je      94f
20: mov     S7(%rsp), %rax                  # the data: branches, finalized_slot, committees
    movq    $1, LcBlock_data(%rax)
    xor     %ecx, %ecx
21: mov     %rcx, S10(%rsp)
    mov     %r12, %rdi
    mov     %rcx, %rsi
    mov     %r14, %rdx
    imul    $192, %rcx, %r8
    mov     S7(%rsp), %rax
    lea     LcBlock_current_branch(%rax,%r8), %r8
    mov     %r15, %rcx
    mov     S8(%rsp), %r10
    FORK_CALL state_branch
    test    %rax, %rax
    jnz     90f
    mov     S10(%rsp), %rcx
    inc     %rcx
    cmp     $LC_BRANCH_FINALIZED_ROOT, %rcx
    jbe     21b
    mov     NODE_STATE_FINALIZED(%r12), %rax
    imul    $SLOTS_PER_EPOCH, %rax
    mov     S7(%rsp), %rcx
    mov     %rax, LcBlock_finalized_slot(%rcx)
    xor     %edx, %edx                      # the parent's committees, as candidates
    xor     %ecx, %ecx
    movq    $0, S10(%rsp)
    mov     (L + 56)(%rsp), %rax
    test    %rax, %rax
    jz      22f
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     %rax, S10(%rsp)
    mov     LcBlock_current_sync_committee(%rax), %rdx
    mov     LcBlock_next_sync_committee(%rax), %rcx
22: mov     %rbx, %rdi
    lea     NODE_STATE_CURRENT_SYNC_COMMITTEE(%r12), %rsi
    call    lc_committee
    mov     S7(%rsp), %rcx
    mov     %rax, LcBlock_current_sync_committee(%rcx)
    xor     %edx, %edx
    mov     S10(%rsp), %rax
    test    %rax, %rax
    jz      23f
    mov     LcBlock_next_sync_committee(%rax), %rdx
23: mov     LcBlock_current_sync_committee(%rcx), %rcx
    mov     %rbx, %rdi
    lea     NODE_STATE_NEXT_SYNC_COMMITTEE(%r12), %rsi
    call    lc_committee
    mov     S7(%rsp), %rcx
    mov     %rax, LcBlock_next_sync_committee(%rcx)
    cmpq    $0, L(%rsp)
    jne     50f                             # the anchor: no best update, latest_signature_slot GENESIS_SLOT
    mov     S10(%rsp), %rsi                 # the attested block: the parent
    mov     LcBlock_slot(%rsi), %rax
    cmp     LcStore_tail_slot(%rbx), %rax
    jb      50f
    xor     %edx, %edx
    mov     $LC_SPP, %r8d
    div     %r8
    mov     %rax, %r9                       # r9 its period, rax the block's
    mov     (L + 8)(%rsp), %rax
    xor     %edx, %edx
    div     %r8
    xor     %edx, %edx
    cmp     %rax, %r9
    jne     24f
    mov     LcBlock_best(%rsi), %rdx
24: mov     %rdx, LcBlock_best(%rcx)
    xor     %edx, %edx
    cmp     %rax, %r9
    setne   %dl
    mov     %rdx, (L + 64)(%rsp)            # 1 when the periods differ
    lea     LcBlock_sync_aggregate(%rcx), %rdi
    call    lc_participants
    mov     S7(%rsp), %rcx
    mov     S10(%rsp), %rsi
    mov     (L + 8)(%rsp), %rdx
    cmp     $MIN_SYNC_COMMITTEE_PARTICIPANTS, %rax
    jae     25f
    mov     LcBlock_latest_signature_slot(%rsi), %rdx
25: mov     %rdx, LcBlock_latest_signature_slot(%rcx)
    jb      50f
    cmpq    $0, (L + 64)(%rsp)
    jne     50f
    mov     %rbx, %rdi                      # the update; it becomes best when better
    mov     (L + 56)(%rsp), %rsi
    mov     (L + 8)(%rsp), %rdx
    lea     LcBlock_sync_aggregate(%rcx), %rax
    mov     LcBlock_next_sync_committee(%rcx), %r8
    mov     %rax, %rcx
    call    lc_make_update
    mov     %rax, (L + 64)(%rsp)
    mov     S7(%rsp), %rcx
    mov     LcBlock_best(%rcx), %rdx
    test    %rdx, %rdx
    jz      40f
    mov     %rbx, %rdi
    mov     %rax, %rsi
    mov     %r15, %rcx
    call    lc_better
    test    %rax, %rax
    jz      50f
40: mov     S7(%rsp), %rcx
    mov     (L + 64)(%rsp), %rax
    mov     %rax, LcBlock_best(%rcx)
50: incq    LcStore_blocks(%rbx)
    xor     %eax, %eax
    LEAVE 80
90: mov     (L + 72)(%rsp), %rcx            # a status: the header's record is free again
    movq    $LC_FREE, (%rcx)
    LEAVE 80
94: mov     (L + 72)(%rsp), %rcx
    movq    $LC_FREE, (%rcx)
    mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    LEAVE 80
95: mov     (L + 72)(%rsp), %rcx
    movq    $LC_FREE, (%rcx)
    mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 80
96: mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 80
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
END_FUNCTION lc_add_block

# L1: an LcBootstrap of the LcFinalized rsi in the store rdi (room checked before), when the store
# holds none of its root and holds its LcBlock with data. rbx the store, rbp the LcFinalized, r12
# the bootstraps, r13 their count, r14 the index, r15 the entry.
LOCAL_FUNCTION lc_add_bootstrap
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     $LC_PART_BOOTSTRAPS, %esi
    call    lc_part
    mov     %rax, %r12
    mov     LcStore_bootstraps(%rbx), %r13
    xor     %r14d, %r14d
    lea     LcFinalized_root(%rbp), %rcx
1:  cmp     %r13, %r14
    jae     2f
    imul    $LcBootstrap__mem, %r14, %rax
    add     %r12, %rax
    NE32    %rax, %rcx, 3f
    LEAVE 0
3:  inc     %r14
    jmp     1b
2:  mov     %rbx, %rdi
    lea     LcFinalized_root(%rbp), %rsi
    call    lc_find_block
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     %rax, %r15
    cmpq    $0, LcBlock_data(%r15)
    je      9f
    imul    $LcBootstrap__mem, %r13, %rdi
    add     %r12, %rdi
    lea     LcFinalized_root(%rbp), %rsi
    COPY32  %rdi, %rsi
    mov     LcFinalized_slot(%rbp), %rax
    mov     %rax, LcBootstrap_slot(%rdi)
    mov     LcBlock_header(%r15), %rax
    mov     %rax, LcBootstrap_header(%rdi)
    mov     LcBlock_current_sync_committee(%r15), %rax
    mov     %rax, LcBootstrap_sync_committee(%rdi)
    add     $LcBootstrap_branch, %rdi
    lea     LcBlock_current_branch(%r15), %rsi
    mov     $192, %edx
    call    lantern_copy
    incq    LcStore_bootstraps(%rbx)
9:  LEAVE 0
END_FUNCTION lc_add_bootstrap

# L1: the LcPeriod of period rsi in the store rdi refers to update rdx (room checked before); with
# rdx 0, the period has none. rbx the store, rbp the period, r12 the update, r13 the periods, r14
# their count, r15 the index.
LOCAL_FUNCTION lc_set_period
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     $LC_PART_PERIODS, %esi
    call    lc_part
    mov     %rax, %r13
    mov     LcStore_periods(%rbx), %r14
    xor     %r15d, %r15d
1:  cmp     %r14, %r15                      # the first entry of a period at least rbp
    jae     2f
    mov     %r15, %rax
    shl     $4, %rax
    cmp     %rbp, (%r13,%rax)
    jae     2f
    inc     %r15
    jmp     1b
2:  mov     %r15, %rdi
    shl     $4, %rdi
    add     %r13, %rdi
    cmp     %r14, %r15
    jae     4f
    cmp     %rbp, LcPeriod_period(%rdi)
    jne     4f
    test    %r12, %r12
    jz      3f
    mov     %r12, LcPeriod_update(%rdi)     # the period's entry: the new update
    LEAVE 0
3:  dec     %r14                            # none: its entry goes
    mov     %r14, LcStore_periods(%rbx)
    lea     LcPeriod__mem(%rdi), %rsi
    mov     %r14, %rdx
    sub     %r15, %rdx
    shl     $4, %rdx
    call    lantern_copy
    LEAVE 0
4:  test    %r12, %r12                      # a new entry at r15: the later ones up by one
    jz      9f
    mov     %r14, %rcx
5:  cmp     %r15, %rcx
    jbe     6f
    mov     %rcx, %rax
    shl     $4, %rax
    add     %r13, %rax
    movdqu  -16(%rax), %xmm0
    movdqu  %xmm0, (%rax)
    dec     %rcx
    jmp     5b
6:  mov     %rbp, LcPeriod_period(%rdi)
    mov     %r12, LcPeriod_update(%rdi)
    inc     %r14
    mov     %r14, LcStore_periods(%rbx)
9:  LEAVE 0
END_FUNCTION lc_set_period

# L1: the LcBlock entries of slots below rsi in the store rdi go, with the scratch rdx (8 bytes for
# each entry, checked before) for their new indices. rbx the store, rbp the slot, r12 the indices,
# r13 the entries, r14 their count, r15 the index; S7 the kept ones.
LOCAL_FUNCTION lc_prune
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     8(%rdx), %r12
    mov     $LC_PART_BLOCKS, %esi
    call    lc_part
    mov     %rax, %r13
    mov     LcStore_blocks(%rbx), %r14
    xor     %r15d, %r15d
    movq    $0, S7(%rsp)
1:  cmp     %r14, %r15                      # each entry's new index plus 1, or 0; its parent's
    jae     3f
    imul    $LcBlock__mem, %r15, %rax
    add     %r13, %rax
    xor     %ecx, %ecx
    cmp     %rbp, LcBlock_slot(%rax)
    jb      2f
    incq    S7(%rsp)
    mov     S7(%rsp), %rcx
    mov     LcBlock_parent(%rax), %rdx
    test    %rdx, %rdx
    jz      2f
    mov     -8(%r12,%rdx,8), %rdx
    mov     %rdx, LcBlock_parent(%rax)
2:  mov     %rcx, (%r12,%r15,8)
    inc     %r15
    jmp     1b
3:  xor     %r15d, %r15d                    # the kept ones down to their new places
4:  cmp     %r14, %r15
    jae     6f
    mov     (%r12,%r15,8), %rax
    dec     %rax
    cmp     %r15, %rax
    jae     5f                              # gone (0 - 1), or in place
    imul    $LcBlock__mem, %rax, %rdi
    add     %r13, %rdi
    imul    $LcBlock__mem, %r15, %rsi
    add     %r13, %rsi
    mov     $LcBlock__mem, %edx
    call    lantern_copy
5:  inc     %r15
    jmp     4b
6:  mov     S7(%rsp), %rax
    mov     %rax, LcStore_blocks(%rbx)
    LEAVE 0
END_FUNCTION lc_prune

# (room, size) -> status: LC_STORE_FIXED plus each capacity times its bytes (light-client.md).
FUNCTION lantern_lc_store_size
    FRAME 0
    mov     %rdi, %r8
    mov     %rsi, %r9
    mov     $LC_STORE_FIXED, %edi
    xor     %esi, %esi
1:  call    lc_mem
    mov     (%r8,%rsi,8), %rax
    mul     %rcx
    jc      9f
    add     %rax, %rdi
    jc      9f
    inc     %rsi
    cmp     $LC_PART_UPDATES, %rsi
    jbe     1b
    mov     %rdi, (%r9)
    xor     %eax, %eax
    UNFRAME 0
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    UNFRAME 0
END_FUNCTION lantern_lc_store_size

# rax = rax times SLOTS_PER_EPOCH, 2^64 - 1 when it overflows. Uses rcx, rdx.
.macro LC_EPOCH_SLOT
    mov     $SLOTS_PER_EPOCH, %ecx
    mul     %rcx
    mov     $-1, %rcx
    cmovc   %rcx, %rax
.endm

# (room, config, state, block, scratch, lc) -> status: an LcStore at an anchor (light-client.md).
# rbx room, rbp config, r12 state, r13 block, r14 scratch, r15 lc. Locals: L the size.
FUNCTION lantern_lc_store_init
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r9, %r15
    lea     L(%rsp), %rsi
    call    lantern_lc_store_size
    test    %rax, %rax
    jnz     99f
    mov     L(%rsp), %rax
    cmp     %rax, (%r15)
    jb      98f
    xor     %ecx, %ecx                      # 2 of each at least
1:  cmpq    $2, (%rbx,%rcx,8)
    jb      98f
    inc     %rcx
    cmp     $LC_PART_UPDATES, %rcx
    jbe     1b
    lea     8(%r15), %rdi                   # every field 0, every record LC_FREE
    mov     L(%rsp), %rsi
    sub     $8, %rsi
    call    lantern_zero
    lea     LcStore_room(%r15), %rdi
    mov     %rbx, %rsi
    mov     $LcRoom__mem, %edx
    call    lantern_copy
    mov     NODE_STATE_SLOT(%r12), %rax
    mov     %rax, LcStore_historical_tail_slot(%r15)
    mov     CONFIG_ALTAIR_FORK_EPOCH(%rbp), %rax
    LC_EPOCH_SLOT
    mov     NODE_STATE_SLOT(%r12), %rcx
    cmp     %rax, %rcx
    cmovae  %rcx, %rax
    mov     %rax, LcStore_tail_slot(%r15)
    mov     NODE_STATE_FINALIZED(%r12), %rax
    mov     %rax, LcStore_latest_finalized_epoch(%r15)
    LC_EPOCH_SLOT
    mov     %rax, LcStore_latest_finalized_slot(%r15)
    lea     LcStore_latest_finalized_root(%r15), %rdi
    lea     (NODE_STATE_FINALIZED + 8)(%r12), %rsi
    COPY32  %rdi, %rsi
    mov     %r15, %rdi                      # the anchor's entry, its LcFinalized and bootstrap
    mov     %rbp, %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    xor     %r8d, %r8d
    mov     %r14, %r9
    mov     $1, %eax
    call    lc_add_block
    test    %rax, %rax
    jnz     99f
    mov     %r15, %rdi
    mov     $LC_PART_BLOCKS, %esi
    xor     %edx, %edx
    call    lc_at
    mov     %rax, %rbx
    mov     %r15, %rdi
    mov     $LC_PART_FINALIZED, %esi
    call    lc_part
    mov     %rax, %rbp
    mov     LcBlock_slot(%rbx), %rax
    mov     %rax, LcFinalized_slot(%rbp)
    lea     LcFinalized_root(%rbp), %rdi
    COPY32  %rdi, %rbx
    movq    $1, LcStore_finalized(%r15)
    mov     %r15, %rdi
    mov     %rbp, %rsi
    call    lc_add_bootstrap
    xor     %eax, %eax
    LEAVE 16
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
99: LEAVE 16
END_FUNCTION lantern_lc_store_init

# (lc, room, out) -> status: the store in a new buffer (light-client.md). rbx lc, rbp room, r12
# out, r13 the part, r14 its source, r15 its target; S7 an entry's bytes, S8 the old records'
# bytes. Locals: L the size.
FUNCTION lantern_lc_store_copy
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rbp, %rdi
    lea     L(%rsp), %rsi
    call    lantern_lc_store_size
    test    %rax, %rax
    jnz     99f
    mov     L(%rsp), %rax
    cmp     %rax, (%r12)
    jb      98f
    xor     %ecx, %ecx
1:  mov     (%rbp,%rcx,8), %rax
    cmp     LcStore_room(%rbx,%rcx,8), %rax
    jb      98f
    inc     %rcx
    cmp     $LC_PART_UPDATES, %rcx
    jbe     1b
    lea     8(%r12), %rdi                   # the fixed fields, then the new room
    lea     8(%rbx), %rsi
    mov     $(LC_STORE_FIXED - 8), %edx
    call    lantern_copy
    lea     LcStore_room(%r12), %rdi
    mov     %rbp, %rsi
    mov     $LcRoom__mem, %edx
    call    lantern_copy
    xor     %r13d, %r13d
2:  mov     %rbx, %rdi
    mov     %r13, %rsi
    call    lc_part
    mov     %rax, %r14
    mov     %r12, %rdi
    call    lc_part
    mov     %rax, %r15
    call    lc_mem
    mov     %rcx, S7(%rsp)
    cmp     $LC_PART_BOOTSTRAPS, %r13
    ja      3f
    mov     LcStore_blocks(%rbx,%r13,8), %rdx   # an entry part: its entries
    imul    %rcx, %rdx
    mov     %r15, %rdi
    mov     %r14, %rsi
    call    lantern_copy
    jmp     4f
3:  mov     LcStore_room(%rbx,%r13,8), %rdx # a record part: its records, the new ones LC_FREE
    imul    %rcx, %rdx
    mov     %rdx, S8(%rsp)
    mov     %r15, %rdi
    mov     %r14, %rsi
    call    lantern_copy
    mov     (%rbp,%r13,8), %rsi
    imul    S7(%rsp), %rsi
    sub     S8(%rsp), %rsi
    mov     %r15, %rdi
    add     S8(%rsp), %rdi
    call    lantern_zero
4:  inc     %r13
    cmp     $LC_PART_UPDATES, %r13
    jbe     2b
    xor     %eax, %eax
    LEAVE 16
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
99: LEAVE 16
END_FUNCTION lantern_lc_store_copy

# (lc, config, state, block, cache, scratch) -> status: lantern_lc_on_block (light-client.md).
FUNCTION lantern_lc_on_block
    FRAME 0
    xor     %eax, %eax
    call    lc_add_block
    UNFRAME 0
END_FUNCTION lantern_lc_on_block

# (lc, config, head, checkpoint, scratch) -> status: lantern_lc_on_head (light-client.md). rbx lc,
# rbp config, r12 head, r13 checkpoint, r14 scratch, r15 the head's entry (a reference); S7 the
# checkpoint's entry when it is new, else 0; S8 an entry; S9 and S10 a period, an entry or an
# index. Locals: L low_slot, L + 8 the new LcFinalized, L + 16 the boundary slot, L + 24 the low
# slot of the bootstraps, L + 32 the slot the new LcFinalized are above, L + 40 an entry, L + 48
# an update or a slot.
FUNCTION lantern_lc_on_head
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    mov     %r12, %rsi
    call    lc_find_block
    test    %rax, %rax
    jz      94f
    mov     %rax, %r15
    movq    $0, S7(%rsp)
    cmpq    $0, (%r13)
    je      1f
    mov     %rbx, %rdi
    lea     8(%r13), %rsi
    call    lc_find_block
    test    %rax, %rax
    jz      94f
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     LcBlock_slot(%rax), %rax
    cmp     LcStore_latest_finalized_slot(%rbx), %rax
    jbe     1f
    mov     %rdx, S7(%rsp)
1:  mov     %rbx, %rdi                      # the room: records, scratch, periods, finalized, bootstraps
    mov     $1, %esi
    xor     %edx, %edx
    mov     $1, %ecx
    call    lc_reserve
    test    %rax, %rax
    jnz     98f
    mov     LcStore_blocks(%rbx), %rax
    lea     8(,%rax,8), %rax
    cmp     %rax, (%r14)
    jb      98f
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     %r15, %rdx
    call    lc_ref
    mov     %rax, S8(%rsp)
    mov     LcStore_tail_slot(%rbx), %rax
    mov     LcStore_latest_finalized_slot(%rbx), %rcx
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    mov     %rax, L(%rsp)
    xor     %r8d, %r8d
    mov     S8(%rsp), %rcx
    mov     LcBlock_slot(%rcx), %rcx
    cmp     LcStore_tail_slot(%rbx), %rcx
    jb      2f
    mov     $LC_SPP, %r9d
    xor     %edx, %edx
    div     %r9                             # rax the period of low_slot
    mov     %rax, %rsi
    mov     %rcx, %rax
    xor     %edx, %edx
    div     %r9                             # rax the head's period
    cmp     %rsi, %rax
    jb      2f
    sub     %rsi, %rax
    lea     1(%rax), %r8
2:  add     LcStore_periods(%rbx), %r8
    cmp     (LcStore_room + LcRoom_periods)(%rbx), %r8
    ja      98f
    movq    $0, (L + 8)(%rsp)
    cmpq    $0, S7(%rsp)
    je      4f
    mov     LcStore_latest_finalized_slot(%rbx), %rax   # above it and the last LcFinalized
    mov     %rax, (L + 32)(%rsp)
    mov     LcStore_finalized(%rbx), %rdx
    test    %rdx, %rdx
    jz      21f
    dec     %rdx
    mov     %rbx, %rdi
    mov     $LC_PART_FINALIZED, %esi
    call    lc_at
    mov     LcFinalized_slot(%rax), %rax
    cmp     (L + 32)(%rsp), %rax
    jbe     21f
    mov     %rax, (L + 32)(%rsp)
21: mov     S7(%rsp), %rdx
3:  test    %rdx, %rdx
    jz      31f
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    call    lc_ref
    mov     LcBlock_slot(%rax), %rcx
    cmp     (L + 32)(%rsp), %rcx
    jbe     31f
    incq    (L + 8)(%rsp)
    mov     LcBlock_parent(%rax), %rdx
    jmp     3b
31: mov     (L + 8)(%rsp), %rcx
    mov     LcStore_finalized(%rbx), %rax
    add     %rcx, %rax
    cmp     (LcStore_room + LcRoom_finalized)(%rbx), %rax
    ja      98f
    mov     LcStore_bootstraps(%rbx), %rax
    add     %rcx, %rax
    cmp     (LcStore_room + LcRoom_bootstraps)(%rbx), %rax
    ja      98f
4:  mov     S8(%rsp), %rax                  # the head
    mov     LcBlock_slot(%rax), %rax
    cmp     LcStore_tail_slot(%rbx), %rax
    jb      30f
    mov     $LC_SPP, %ecx
    xor     %edx, %edx
    div     %rcx
    mov     %rax, S9(%rsp)                  # S9 the period, S10 that of low_slot
    mov     L(%rsp), %rax
    xor     %edx, %edx
    div     %rcx
    mov     %rax, S10(%rsp)
    cmp     %rax, S9(%rsp)
    jb      10f
    mov     %r15, (L + 40)(%rsp)
5:  mov     S9(%rsp), %rax                  # period S9: the entry at its last slot
    inc     %rax
    imul    $LC_SPP, %rax, %rdx
    dec     %rdx
    mov     %rbx, %rdi
    mov     (L + 40)(%rsp), %rsi
    call    lc_ancestor
    test    %rax, %rax
    jz      10f
    mov     %rax, (L + 40)(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     LcBlock_slot(%rax), %rcx
    cmp     L(%rsp), %rcx
    jb      10f
    mov     LcBlock_best(%rax), %rdx
    test    %rdx, %rdx
    jz      7f
    mov     %rdx, (L + 48)(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_UPDATES, %esi
    call    lc_ref
    lea     LcUpdate_sync_aggregate(%rax), %rdi
    call    lc_participants
    mov     (L + 48)(%rsp), %rdx
    cmp     $MIN_SYNC_COMMITTEE_PARTICIPANTS, %rax
    jae     7f
    xor     %edx, %edx
7:  mov     %rbx, %rdi
    mov     S9(%rsp), %rsi
    call    lc_set_period
    mov     S9(%rsp), %rax
    cmp     S10(%rsp), %rax
    je      10f
    decq    S9(%rsp)
    jmp     5b
10: mov     S8(%rsp), %rax                  # latest: S at it, A before S
    mov     LcBlock_latest_signature_slot(%rax), %rdx
    mov     %rdx, (L + 48)(%rsp)
    cmp     L(%rsp), %rdx
    jbe     12f
    mov     %rbx, %rdi
    mov     %r15, %rsi
    call    lc_ancestor
    test    %rax, %rax
    jz      12f
    mov     %rax, (L + 40)(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     %rax, S9(%rsp)
    mov     LcBlock_slot(%rax), %rdx
    cmp     L(%rsp), %rdx
    jbe     12f
    dec     %rdx
    mov     %rbx, %rdi
    mov     (L + 40)(%rsp), %rsi
    call    lc_ancestor
    test    %rax, %rax
    jz      12f
    mov     %rax, S10(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     %rax, %rdx
    call    lc_ref
    mov     LcBlock_slot(%rax), %rax
    cmp     L(%rsp), %rax
    jb      12f
    mov     %rbx, %rdi
    mov     S10(%rsp), %rsi
    mov     (L + 48)(%rsp), %rdx
    mov     S9(%rsp), %rcx
    add     $LcBlock_sync_aggregate, %rcx
    xor     %r8d, %r8d
    call    lc_make_update
    mov     %rax, LcStore_latest(%rbx)
    jmp     30f
12: movq    $0, LcStore_latest(%rbx)
30: cmpq    $0, S7(%rsp)                    # the checkpoint: its LcFinalized from the top down
    je      60f
    mov     LcStore_finalized(%rbx), %rax
    add     (L + 8)(%rsp), %rax
    mov     %rax, LcStore_finalized(%rbx)
    dec     %rax
    mov     %rax, S10(%rsp)
    mov     S7(%rsp), %rax
    mov     %rax, S8(%rsp)
32: cmpq    $0, (L + 8)(%rsp)
    je      33f
    decq    (L + 8)(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     S8(%rsp), %rdx
    call    lc_ref
    mov     %rax, S9(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_FINALIZED, %esi
    mov     S10(%rsp), %rdx
    call    lc_at
    mov     S9(%rsp), %rcx
    mov     LcBlock_slot(%rcx), %rdx
    mov     %rdx, LcFinalized_slot(%rax)
    lea     LcFinalized_root(%rax), %rax
    COPY32  %rax, %rcx
    decq    S10(%rsp)
    mov     LcBlock_parent(%rcx), %rax
    mov     %rax, S8(%rsp)
    jmp     32b
33: mov     %rbx, %rdi
    mov     $LC_PART_BLOCKS, %esi
    mov     S7(%rsp), %rdx
    call    lc_ref
    mov     %rax, S8(%rsp)
    mov     (%r13), %rcx
    mov     %rcx, LcStore_latest_finalized_epoch(%rbx)
    mov     LcStore_latest_finalized_slot(%rbx), %rcx
    mov     %rcx, S9(%rsp)                  # the old latest_finalized_slot
    mov     LcBlock_slot(%rax), %rdx
    mov     %rdx, LcStore_latest_finalized_slot(%rbx)
    lea     LcStore_latest_finalized_root(%rbx), %rcx
    COPY32  %rcx, %rax
    mov     LcStore_tail_slot(%rbx), %rcx   # the bootstraps of the new epoch boundary blocks
    cmp     %rcx, %rdx
    jb      50f
    mov     S9(%rsp), %rax
    inc     %rax
    cmp     %rcx, %rax
    cmovb   %rcx, %rax
    mov     %rax, (L + 24)(%rsp)
    mov     %rdx, (L + 16)(%rsp)
40: mov     (L + 16)(%rsp), %rsi
    cmp     (L + 24)(%rsp), %rsi
    jb      50f
    mov     %rbx, %rdi
    call    lc_finalized_at
    test    %rax, %rax
    jz      50f
    mov     %rax, S10(%rsp)
    mov     LcFinalized_slot(%rax), %rcx
    cmp     (L + 24)(%rsp), %rcx
    jb      41f
    mov     %rbx, %rdi
    mov     %rax, %rsi
    call    lc_add_bootstrap
41: mov     S10(%rsp), %rax
    mov     LcFinalized_slot(%rax), %rax
    add     $(SLOTS_PER_EPOCH - 1), %rax
    mov     $SLOTS_PER_EPOCH, %ecx
    xor     %edx, %edx
    div     %rcx
    imul    %rcx, %rax
    cmp     %rcx, %rax
    jb      50f
    sub     %rcx, %rax
    mov     %rax, (L + 16)(%rsp)
    jmp     40b
50: mov     %rbx, %rdi                      # the entries below the checkpoint's go
    mov     S8(%rsp), %rax
    mov     LcBlock_slot(%rax), %rsi
    mov     %r14, %rdx
    call    lc_prune
60: xor     %eax, %eax
    LEAVE 64
94: mov     $LANTERN_INVALID_UNKNOWN_BLOCK, %eax
    LEAVE 64
98: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
END_FUNCTION lantern_lc_on_head

# (lc, kind, key, out, fork) -> status: lantern_lc_read (light-client.md). rbx lc, rbp kind, r12
# key, r13 out, r14 fork, r15 the bootstrap or update; S7 a count, S8 its fork. Locals: L the parts.
FUNCTION lantern_lc_read
    ENTER 80
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, %r14
    cmp     $LC_OBJECT_OPTIMISTIC_UPDATE, %rbp
    ja      97f
    test    %rbp, %rbp
    jnz     10f
    mov     $LC_PART_BOOTSTRAPS, %esi       # the bootstrap of the root
    call    lc_part
    mov     %rax, %r15
    mov     LcStore_bootstraps(%rbx), %rcx
    mov     %rcx, S7(%rsp)
1:  cmpq    $0, S7(%rsp)
    je      93f
    NE32    %r15, %r12, 2f
    jmp     3f
2:  add     $LcBootstrap__mem, %r15
    decq    S7(%rsp)
    jmp     1b
3:  mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     LcBootstrap_header(%r15), %rdx
    call    lc_ref
    mov     LcHeader_fork(%rax), %rcx
    mov     %rcx, S8(%rsp)
    add     $LcHeader_header, %rax
    mov     %rax, (L + LcParts_header)(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_COMMITTEES, %esi
    mov     LcBootstrap_sync_committee(%r15), %rdx
    call    lc_ref
    add     $LcCommittee_committee, %rax
    mov     %rax, (L + LcParts_sync_committee)(%rsp)
    lea     LcBootstrap_branch(%r15), %rax
    mov     %rax, (L + LcParts_branch)(%rsp)
    mov     S8(%rsp), %rcx
    LC_COUNTS
    mov     %rcx, (L + LcParts_branch_count)(%rsp)
    jmp     30f
10: cmp     $LC_OBJECT_UPDATE, %rbp
    jne     20f
    mov     $LC_PART_PERIODS, %esi          # the period's update
    call    lc_part
    mov     LcStore_periods(%rbx), %rcx
11: test    %rcx, %rcx
    jz      93f
    cmp     %r12, LcPeriod_period(%rax)
    je      12f
    add     $LcPeriod__mem, %rax
    dec     %rcx
    jmp     11b
12: mov     LcPeriod_update(%rax), %rdx
    jmp     21f
20: mov     LcStore_latest(%rbx), %rdx      # the latest finality update
    test    %rdx, %rdx
    jz      93f
21: mov     %rbx, %rdi
    mov     $LC_PART_UPDATES, %esi
    call    lc_ref
    mov     %rax, %r15
    mov     LcUpdate_fork(%r15), %rax
    mov     %rax, S8(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     LcUpdate_attested_header(%r15), %rdx
    call    lc_ref
    add     $LcHeader_header, %rax
    mov     %rax, (L + LcParts_header)(%rsp)
    mov     %rbx, %rdi
    mov     $LC_PART_HEADERS, %esi
    mov     LcUpdate_finalized_header(%r15), %rdx
    call    lc_ref
    add     $LcHeader_header, %rax
    mov     %rax, (L + LcParts_finalized_header)(%rsp)
    movq    $0, (L + LcParts_sync_committee)(%rsp)
    mov     LcUpdate_next_sync_committee(%r15), %rdx
    test    %rdx, %rdx
    jz      22f
    mov     %rbx, %rdi
    mov     $LC_PART_COMMITTEES, %esi
    call    lc_ref
    add     $LcCommittee_committee, %rax
    mov     %rax, (L + LcParts_sync_committee)(%rsp)
22: lea     LcUpdate_next_branch(%r15), %rax
    mov     %rax, (L + LcParts_branch)(%rsp)
    lea     LcUpdate_finality_branch(%r15), %rax
    mov     %rax, (L + LcParts_finality_branch)(%rsp)
    lea     LcUpdate_sync_aggregate(%r15), %rax
    mov     %rax, (L + LcParts_sync_aggregate)(%rsp)
    mov     LcUpdate_signature_slot(%r15), %rax
    mov     %rax, (L + LcParts_signature_slot)(%rsp)
    mov     S8(%rsp), %rcx
    LC_COUNTS
    mov     %rcx, (L + LcParts_branch_count)(%rsp)
    mov     %rdx, (L + LcParts_finality_count)(%rsp)
30: mov     %rbp, %rdi
    lea     L(%rsp), %rsi
    mov     %r13, %rdx
    mov     S8(%rsp), %r10
    FORK_CALL lc_object
    test    %rax, %rax
    jnz     99f
    mov     S8(%rsp), %rcx
    mov     %rcx, (%r14)
    LEAVE 80
93: mov     $LANTERN_NO_STATE_ANSWER, %eax
    LEAVE 80
97: mov     $LANTERN_INVALID_EVENT, %eax
99: LEAVE 80
END_FUNCTION lantern_lc_read
