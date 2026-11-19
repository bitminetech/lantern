/*
 * Networking rules, x86-64. Requirements: docs/reference/networking.md.
 */

.if FORK >= FORK_FULU
/*
 * rbx out entries, rbp NUMBER_OF_CUSTODY_GROUPS, r12 custody_group_count, r13 groups found, r14 out.
 * Locals: L current_id (32), L+32 the digest (32).
 */
SPEC_FUNCTION get_custody_groups
    ENTER 64
    mov     CONFIG_NUMBER_OF_CUSTODY_GROUPS(%rdx), %rbp
    mov     (%rsi), %r12
    mov     %rcx, %r14
    cmp     %rbp, %r12                      # assert custody_group_count <= NUMBER_OF_CUSTODY_GROUPS
    ja      8f
    mov     (%r14), %rax                    # room for custody_group_count entries
    sub     $LIST_FIXED, %rax
    jb      9f
    shr     $3, %rax
    cmp     %rax, %r12
    ja      9f
    lea     L(%rsp), %rax                   # current_id = node_id
    COPY32  %rax, %rdi
    lea     LIST_FIXED(%r14), %rbx
    cmp     %rbp, %r12
    jne     2f
    xor     %eax, %eax                      # every group: 0 to NUMBER_OF_CUSTODY_GROUPS - 1
    test    %r12, %r12
    jz      6f
1:  mov     %rax, (%rbx,%rax,8)
    inc     %rax
    cmp     %r12, %rax
    jb      1b
    jmp     6f
2:  xor     %r13d, %r13d
3:  cmp     %r12, %r13                      # while len(custody_groups) < custody_group_count
    jae     6f
    lea     L(%rsp), %rdi                   # sha256(uint_to_bytes(current_id))
    mov     $32, %esi
    lea     (L + 32)(%rsp), %rdx
    call    sha256_short
    mov     (L + 32)(%rsp), %rax            # bytes_to_uint64(digest[0:8]) % NUMBER_OF_CUSTODY_GROUPS
    xor     %edx, %edx
    div     %rbp
    xor     %ecx, %ecx                      # the first entry not below the group
4:  cmp     %r13, %rcx
    jae     5f
    mov     (%rbx,%rcx,8), %rax
    cmp     %rdx, %rax
    je      55f                             # already in custody_groups
    ja      5f
    inc     %rcx
    jmp     4b
5:  mov     %r13, %rsi                      # move the entries from rcx up by one
51: cmp     %rcx, %rsi
    jbe     52f
    mov     -8(%rbx,%rsi,8), %rax
    mov     %rax, (%rbx,%rsi,8)
    dec     %rsi
    jmp     51b
52: mov     %rdx, (%rbx,%rcx,8)
    inc     %r13
55: addq    $1, L(%rsp)                     # current_id += 1, wrapping from UINT256_MAX to 0
    adcq    $0, (L + 8)(%rsp)
    adcq    $0, (L + 16)(%rsp)
    adcq    $0, (L + 24)(%rsp)
    jmp     3b
6:  movq    $LIST_FIXED, 8(%r14)            # offset 24, count
    mov     %r12, 16(%r14)
    xor     %eax, %eax
    LEAVE 64
8:  mov     $LANTERN_INVALID_CUSTODY_GROUP, %eax
    LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
SPEC_END get_custody_groups

SPEC_LEAF compute_columns_for_custody_group
    mov     CONFIG_NUMBER_OF_CUSTODY_GROUPS(%rsi), %rcx
    mov     (%rdi), %r8
    cmp     %rcx, %r8                       # assert custody_group < NUMBER_OF_CUSTODY_GROUPS
    jae     8f
    mov     %rdx, %r9
    mov     $NUMBER_OF_COLUMNS, %eax        # columns_per_group
    xor     %edx, %edx
    div     %rcx
    mov     (%r9), %rdx
    sub     $LIST_FIXED, %rdx
    jb      9f
    shr     $3, %rdx
    cmp     %rdx, %rax
    ja      9f
    movq    $LIST_FIXED, 8(%r9)
    mov     %rax, 16(%r9)
    lea     LIST_FIXED(%r9), %rdx
    test    %rax, %rax
    jz      2f
1:  mov     %r8, (%rdx)                     # NUMBER_OF_CUSTODY_GROUPS * index + custody_group
    add     $8, %rdx
    add     %rcx, %r8
    dec     %rax
    jnz     1b
2:  xor     %eax, %eax
    ret
8:  mov     $LANTERN_INVALID_CUSTODY_GROUP, %eax
    ret
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    ret
SPEC_END compute_columns_for_custody_group
.endif

/* ---------------------------------------------------------------- Seen */

.if SeenKey__mem != 32 || SeenBits__mem != 320 || SeenBlock__mem != 40 || SEEN_BITS_BYTES * 8 < MAX_VALIDATORS_PER_COMMITTEE || SEEN_BITS_BYTES * 8 < SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.error "the gossip code assumes the Seen layouts of include/lantern.inc"
.endif

/* L0: rax = 1 when seen rdi holds the SeenKey (rsi kind, rdx a, rcx b, r8 c), else 0. A leaf; uses r9-r11. */
LOCAL_FUNCTION seen_find_key
    UNWIND_END_PROLOGUE
    PART    %r9, %r10, %rdi, Seen_keys
1:  test    %r10, %r10
    jz      3f
    cmp     %rsi, 0(%r9)
    jne     2f
    cmp     %rdx, 8(%r9)
    jne     2f
    cmp     %rcx, 16(%r9)
    jne     2f
    cmp     %r8, 24(%r9)
    je      4f
2:  add     $SeenKey__mem, %r9
    dec     %r10
    jmp     1b
3:  xor     %eax, %eax
    ret
4:  mov     $1, %eax
    ret
END_FUNCTION seen_find_key

/* L0: rax = the free SeenKey entries of seen rdi. A leaf. */
LOCAL_FUNCTION seen_key_room
    UNWIND_END_PROLOGUE
    mov     Seen_bits(%rdi), %rax
    sub     Seen_keys(%rdi), %rax
    shr     $5, %rax
    sub     (Seen_keys + 8)(%rdi), %rax
    ret
END_FUNCTION seen_key_room

/* L0: append the SeenKey (rsi kind, rdx a, rcx b, r8 c) to seen rdi, which has room. A leaf; uses r9, r10. */
LOCAL_FUNCTION seen_add_key
    UNWIND_END_PROLOGUE
    PART    %r9, %r10, %rdi, Seen_keys
    shl     $5, %r10
    add     %r10, %r9
    mov     %rsi, 0(%r9)
    mov     %rdx, 8(%r9)
    mov     %rcx, 16(%r9)
    mov     %r8, 24(%r9)
    incq    (Seen_keys + 8)(%rdi)
    ret
END_FUNCTION seen_add_key

/* L0: rax = the free SeenBits entries of seen rdi. A leaf; uses rcx, rdx. */
LOCAL_FUNCTION seen_bits_room
    UNWIND_END_PROLOGUE
    mov     Seen_blocks(%rdi), %rax
    sub     Seen_bits(%rdi), %rax
    xor     %edx, %edx
    mov     $SeenBits__mem, %ecx
    div     %rcx
    sub     (Seen_bits + 8)(%rdi), %rax
    ret
END_FUNCTION seen_bits_room

/*
 * L0: is_non_strict_superset of the SeenBits of key (rsi kind, root at rdx, rcx a, r8 b) in seen rdi,
 * for the rax bits at r9: rax = 1 when one of them has every bit of r9 set. Uses rdi, r10, r11, xmm0-xmm2.
 * Locals: rsp+0 the length, rsp+8 its bytes, rsp+16 the entries left.
 */
LOCAL_FUNCTION seen_superset
    FRAME 32
    mov     %rax, 0(%rsp)
    add     $7, %rax
    shr     $3, %rax
    mov     %rax, 8(%rsp)                   # bytes of the bits
    PART    %r10, %r11, %rdi, Seen_bits
    mov     %r10, %rdi
    mov     %r11, 16(%rsp)
1:  cmpq    $0, 16(%rsp)
    je      8f
    cmp     %rsi, SeenBits_kind(%rdi)
    jne     5f
    cmp     %rcx, SeenBits_a(%rdi)
    jne     5f
    cmp     %r8, SeenBits_b(%rdi)
    jne     5f
    mov     0(%rsp), %rax                   # a bitfield of another length: skipped
    cmp     %rax, SeenBits_length(%rdi)
    jne     5f
    lea     SeenBits_root(%rdi), %rax
    NE32    %rax, %rdx, 5f
    xor     %eax, %eax
2:  cmp     8(%rsp), %rax
    jae     9f
    movzbl  SeenBits_bits(%rdi,%rax), %r10d
    movzbl  (%r9,%rax), %r11d
    not     %r10d                           # a bit of the new bits outside the prior
    and     %r11d, %r10d
    jnz     5f
    inc     %rax
    jmp     2b
5:  add     $SeenBits__mem, %rdi
    decq    16(%rsp)
    jmp     1b
8:  xor     %eax, %eax
    UNFRAME 32
9:  mov     $1, %eax
    UNFRAME 32
END_FUNCTION seen_superset

/*
 * L0: append the SeenBits of key (rsi kind, root at rdx, rcx a, r8 b) and the rax bits at r9 to seen rdi,
 * which has room. Locals: rsp+0 entry, rsp+8 bits, rsp+16 length.
 */
LOCAL_FUNCTION seen_add_bits
    FRAME 32
    mov     %rax, 16(%rsp)
    mov     %r9, 8(%rsp)
    PART    %r10, %r11, %rdi, Seen_bits
    imul    $SeenBits__mem, %r11, %r9
    add     %r9, %r10
    incq    (Seen_bits + 8)(%rdi)
    mov     %rsi, SeenBits_kind(%r10)
    lea     SeenBits_root(%r10), %r9
    COPY32  %r9, %rdx
    mov     %rcx, SeenBits_a(%r10)
    mov     %r8, SeenBits_b(%r10)
    mov     %rax, SeenBits_length(%r10)
    mov     %r10, 0(%rsp)
    lea     SeenBits_bits(%r10), %rdi
    mov     $SEEN_BITS_BYTES, %esi
    call    lantern_zero
    mov     0(%rsp), %rdi
    add     $SeenBits_bits, %rdi
    mov     8(%rsp), %rsi
    mov     16(%rsp), %rdx
    add     $7, %rdx
    shr     $3, %rdx
    call    lantern_copy
    UNFRAME 32
END_FUNCTION seen_add_bits

/* L0: rax = the SeenHeader of block root rsi in seen rdi, or 0. A leaf; uses rcx, rdx, r11, xmm0-xmm2. */
LOCAL_FUNCTION seen_find_header
    UNWIND_END_PROLOGUE
    PART    %rax, %rcx, %rdi, Seen_headers
1:  test    %rcx, %rcx
    jz      3f
    NE32    %rax, %rsi, 2f
    ret
2:  mov     SeenHeader_header(%rax), %rdx   # the next entry: 64 + the header value's size
    lea     SeenHeader_header(%rax,%rdx), %rax
    dec     %rcx
    jmp     1b
3:  xor     %eax, %eax
    ret
END_FUNCTION seen_find_header

/* ---------------------------------------------------------------- Gossip helpers */

/* dst = compute_time_at_slot_ms(genesis_time_ms of store st, slot), UINT64_MAX when it does not fit. Uses rax, rdx. */
.macro SLOT_TIME dst, st, slot
    mov     \slot, %rax
    mulq    (Store_config + CONFIG_SLOT_DURATION_MS)(\st)
    jc      98f
    add     Store_genesis_time_ms(\st), %rax
    jnc     99f
98: mov     $-1, %rax
99: mov     %rax, \dst
.endm

/* dst = t + MAXIMUM_GOSSIP_CLOCK_DISPARITY of store st, UINT64_MAX when it does not fit. dst is not t. */
.macro WITH_DISPARITY dst, st, t
    mov     \t, \dst
    add     (Store_config + CONFIG_MAXIMUM_GOSSIP_CLOCK_DISPARITY)(\st), \dst
    jnc     99f
    mov     $-1, \dst
99:
.endm

/* L0: rax = is_future_slot(store rdi, slot rsi, current_time_ms rdx). A leaf; uses rcx, r8. */
LOCAL_FUNCTION is_future_slot
    UNWIND_END_PROLOGUE
    mov     %rdx, %r8
    SLOT_TIME %rcx, %rdi, %rsi
    WITH_DISPARITY %rdx, %rdi, %r8
    xor     %eax, %eax
    cmp     %rcx, %rdx
    setb    %al
    ret
END_FUNCTION is_future_slot

/* L0: rax = is_within_slot_range(store rdi, slot rsi, slot_range rdx, current_time_ms rcx). A leaf; uses r8, r9. */
LOCAL_FUNCTION is_within_slot_range
    UNWIND_END_PROLOGUE
    mov     %rdx, %r9
    SLOT_TIME %r8, %rdi, %rsi               # current_time_ms + MAXIMUM_GOSSIP_CLOCK_DISPARITY < start_time_ms
    WITH_DISPARITY %rdx, %rdi, %rcx
    cmp     %r8, %rdx
    jb      8f
    add     %r9, %rsi                       # end_time_ms = time of slot + slot_range + 1
    jc      9f
    add     $1, %rsi
    jc      9f
    SLOT_TIME %r8, %rdi, %rsi
    WITH_DISPARITY %rdx, %rdi, %r8          # end_time_ms + MAXIMUM_GOSSIP_CLOCK_DISPARITY < current_time_ms
    cmp     %rcx, %rdx
    jb      8f
9:  mov     $1, %eax
    ret
8:  xor     %eax, %eax
    ret
END_FUNCTION is_within_slot_range

/* L0: rax = is_current_or_previous_epoch(store rdi, epoch rsi, current_time_ms rdx). rbx store, rbp epoch, r12 time. */
LOCAL_FUNCTION is_current_or_previous_epoch
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rbp, %rax                      # is_within_epoch(epoch): the start slot fits
    shr     $(64 - LOG2_SLOTS_PER_EPOCH), %rax
    jnz     1f
    mov     %rbp, %rsi
    shl     $LOG2_SLOTS_PER_EPOCH, %rsi
    mov     $(SLOTS_PER_EPOCH - 1), %edx
    mov     %r12, %rcx
    call    is_within_slot_range
    test    %rax, %rax
    jnz     7f
1:  lea     1(%rbp), %rsi                   # is_within_epoch(epoch + 1)
    test    %rsi, %rsi
    jz      6f
    mov     %rsi, %rax
    shr     $(64 - LOG2_SLOTS_PER_EPOCH), %rax
    jnz     6f
    mov     %rbx, %rdi
    shl     $LOG2_SLOTS_PER_EPOCH, %rsi
    mov     $(SLOTS_PER_EPOCH - 1), %edx
    mov     %r12, %rcx
    call    is_within_slot_range
    jmp     7f
6:  xor     %eax, %eax
7:  LEAVE 0
END_FUNCTION is_current_or_previous_epoch

/*
 * L0: rax = is_future_epoch(store rdi, epoch rsi, current_time_ms rdx); true when the time with
 * disparity is before genesis, where the spec's subtraction raises. A leaf; uses rcx, rdx.
 */
LOCAL_FUNCTION is_future_epoch
    UNWIND_END_PROLOGUE
    WITH_DISPARITY %rax, %rdi, %rdx
    sub     Store_genesis_time_ms(%rdi), %rax
    jb      9f
    xor     %edx, %edx
    divq    (Store_config + CONFIG_SLOT_DURATION_MS)(%rdi)  # current_slot
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    cmp     %rsi, %rax
    setb    %al
    movzbl  %al, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION is_future_epoch

/* L0: rax = compute_start_slot_at_epoch(finalized epoch of store rdi), UINT64_MAX when it does not fit. A leaf; uses rcx. */
LOCAL_FUNCTION finalized_slot
    UNWIND_END_PROLOGUE
    mov     (Store_finalized_checkpoint + Checkpoint_epoch)(%rdi), %rax
    mov     %rax, %rcx
    shr     $(64 - LOG2_SLOTS_PER_EPOCH), %rcx
    jnz     9f
    shl     $LOG2_SLOTS_PER_EPOCH, %rax
    ret
9:  mov     $-1, %rax
    ret
END_FUNCTION finalized_slot

/*
 * L0: rax = status, rdx = 1 when get_checkpoint_block(store rdi, node rsi, epoch rdx) is the root at rcx, else 0.
 * Locals: rsp+0 store, rsp+8 root.
 */
LOCAL_FUNCTION checkpoint_is
    FRAME 16
    mov     %rdi, 0(%rsp)
    mov     %rcx, 8(%rsp)
    call    checkpoint_block
    test    %rax, %rax
    jnz     7f
    mov     0(%rsp), %rdi
    mov     8(%rsp), %rcx
    NODE    %rsi, %rdi, %rdx
    xor     %edx, %edx
    NE32    %rsi, %rcx, 7f
    mov     $1, %edx
7:  UNFRAME 16
END_FUNCTION checkpoint_is

/* L0: checkpoint_is of the store's finalized checkpoint for node rsi of store rdi. */
LOCAL_FUNCTION finalized_is_ancestor
    UNWIND_END_PROLOGUE
    mov     (Store_finalized_checkpoint + Checkpoint_epoch)(%rdi), %rdx
    lea     (Store_finalized_checkpoint + Checkpoint_root)(%rdi), %rcx
    jmp     checkpoint_is
END_FUNCTION finalized_is_ancestor

/*
 * L0: rax = status, rdx = bls.Verify(public key rcx, compute_signing_root(object rdx of type rsi, domain rdi),
 * signature r8), with scratch r9. Locals: rsp+0 the root buffer (56: a ByteList header, then the root),
 * rsp+56 key, rsp+64 signature, rsp+72 scratch.
 */
LOCAL_FUNCTION verify_with_domain
    FRAME 80
    mov     %rcx, 56(%rsp)
    mov     %r8, 64(%rsp)
    mov     %r9, 72(%rsp)
    mov     %rdi, %rax
    mov     %rsi, %rdi
    mov     %rdx, %rsi
    mov     %rax, %rdx
    mov     %r9, %rcx
    lea     24(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    mov     56(%rsp), %rdi
    mov     64(%rsp), %rsi
    mov     %rsp, %rdx
    mov     72(%rsp), %rcx
    call    verify_root_signature
7:  UNFRAME 80
END_FUNCTION verify_with_domain

/*
 * L0: verify_with_domain with get_domain(state rdi, domain type esi, epoch rdx): object r8 of type rcx,
 * public key r9; the signature and scratch are the two stack arguments (the caller's S7 and S8).
 * Locals: rsp+0 domain type, rsp+8 epoch, rsp+16 domain (32), rsp+48 type, object, key.
 */
LOCAL_FUNCTION verify_signed
    FRAME 80
    mov     %esi, 0(%rsp)
    mov     %rdx, 8(%rsp)
    mov     %rcx, 48(%rsp)
    mov     %r8, 56(%rsp)
    mov     %r9, 64(%rsp)
    mov     %rsp, %rsi
    lea     8(%rsp), %rdx
    mov     (80 + 16 + 8)(%rsp), %rcx       # the scratch
    lea     16(%rsp), %r8
    call    lantern_get_domain
    test    %rax, %rax
    jnz     7f
    lea     16(%rsp), %rdi
    mov     48(%rsp), %rsi
    mov     56(%rsp), %rdx
    mov     64(%rsp), %rcx
    mov     (80 + 16)(%rsp), %r8            # the signature
    mov     (80 + 16 + 8)(%rsp), %r9
    call    verify_with_domain
7:  UNFRAME 80
END_FUNCTION verify_signed

/* dst = &state.validators[idx] of state st; branch to fail when idx is not below the count. Uses r11. */
.macro VALIDATOR_AT dst, st, idx, fail
    cmp     (BeaconState_validators + 8)(\st), \idx
    jae     \fail
    VALIDATOR \dst, \st, \idx
.endm

/*
 * L0: the block of the root at rdx, from store rdi and seen rsi: rax = its node or NODE_NONE, rdx = 2 for a node
 * of the store, 1 for a block of seen, 0 when unknown, rcx = its payload status. Locals: store, seen, root.
 */
LOCAL_FUNCTION block_lookup
    FRAME 32
    mov     %rdi, 0(%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rdx, %rsi
    call    find_node
    cmp     $-1, %rax
    je      1f
    mov     0(%rsp), %rdi
    NODE    %rsi, %rdi, %rax
    mov     BlockNode_payload_status(%rsi), %rcx
    mov     $2, %edx
    UNFRAME 32
1:  mov     8(%rsp), %rdi
    mov     16(%rsp), %rsi
    call    seen_find_block
    test    %rax, %rax
    jz      2f
    mov     SeenBlock_payload_status(%rax), %rcx
    mov     $-1, %rax
    mov     $1, %edx
    UNFRAME 32
2:  mov     $-1, %rax
    xor     %edx, %edx
    mov     $PAYLOAD_STATUS_NOT_VALIDATED, %ecx
    UNFRAME 32
END_FUNCTION block_lookup

/* The gossip results: rax into the Result whose pointer is in local slot off. Uses rcx. */
.macro CHECK_RESULT off, fail, done
    mov     \off(%rsp), %rcx
    CHECK_STATUS %rcx, \fail, \done
.endm

/* The tail of a gossip function whose Result pointer is at local off: labels 4 ignore, 5 reject, 6 store rax, 8 ok, 7 return, 9 too small. */
.macro GOSSIP_TAIL off, locals
4:  mov     $LANTERN_GOSSIP_IGNORE, %eax
    jmp     6f
5:  mov     $LANTERN_GOSSIP_REJECT, %eax
6:  mov     \off(%rsp), %rcx
    mov     %rax, (%rcx)
8:  xor     %eax, %eax
7:  LEAVE \locals
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE \locals
.endm

/* ---------------------------------------------------------------- Gossip: operations */

/*
 * rbx seen, rbp store, r12 signed exit, r13 current_time_ms, r14 head state, r15 scratch; S9 validator,
 * S10 validator index. Locals: L result, L+8 current epoch, L+16 predicate, L+24 domain type, L+32 domain (32).
 */
SPEC_FUNCTION validate_voluntary_exit_gossip
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     (64 + 96)(%rsp), %rax           # the seventh argument
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH %r15, %r14, 0, 9f
    mov     (SignedVoluntaryExit_message + VoluntaryExit_validator_index)(%r12), %rax
    mov     %rax, S10(%rsp)
    mov     %rbx, %rdi                      # [IGNORE] the first valid exit for the validator
    mov     $SEEN_VOLUNTARY_EXIT, %esi
    mov     %rax, %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] the exit epoch is not in the future
    mov     (SignedVoluntaryExit_message + VoluntaryExit_epoch)(%r12), %rsi
    mov     %r13, %rdx
    call    is_future_epoch
    test    %rax, %rax
    jnz     4f
    mov     S10(%rsp), %rax                 # [REJECT] the validator index is valid
    VALIDATOR_AT %rcx, %r14, %rax, 5f
    mov     %rcx, S9(%rsp)
    mov     %r14, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     S9(%rsp), %rcx                  # [IGNORE] the validator has not initiated exit
    cmpq    $-1, Validator_exit_epoch(%rcx)
    jne     4f
    mov     %rcx, %rdi                      # [REJECT] the validator is active
    lea     (L + 8)(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_is_active_validator
    cmpq    $0, (L + 16)(%rsp)
    je      5f
    mov     S9(%rsp), %rcx                  # [REJECT] active for SHARD_COMMITTEE_PERIOD
    mov     Validator_activation_epoch(%rcx), %rax
    add     (Store_config + CONFIG_SHARD_COMMITTEE_PERIOD)(%rbp), %rax
    jc      3f
    cmp     %rax, (L + 8)(%rsp)
    jb      5f
.if FORK >= FORK_DENEB
    movl    $DOMAIN_VOLUNTARY_EXIT, (L + 24)(%rsp)  # [REJECT] the signature: compute_domain(DOMAIN_VOLUNTARY_EXIT, CAPELLA_FORK_VERSION, gvr)
    lea     (L + 24)(%rsp), %rdi
    lea     (Store_config + CONFIG_CAPELLA_FORK_VERSION)(%rbp), %rsi
    lea     BeaconState_genesis_validators_root(%r14), %rdx
    mov     %r15, %rcx
    lea     (L + 32)(%rsp), %r8
    call    lantern_compute_domain
    test    %rax, %rax
    jnz     7f
    lea     (L + 32)(%rsp), %rdi
    ADDRESS %rsi, lantern_type_VoluntaryExit
    lea     SignedVoluntaryExit_message(%r12), %rdx
    mov     S9(%rsp), %rcx
    add     $Validator_pubkey, %rcx
    lea     SignedVoluntaryExit_signature(%r12), %r8
    mov     %r15, %r9
    call    verify_with_domain
.else
    lea     SignedVoluntaryExit_signature(%r12), %rax   # [REJECT] the signature: get_domain(state, DOMAIN_VOLUNTARY_EXIT, voluntary_exit.epoch)
    mov     %rax, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_VOLUNTARY_EXIT, %esi
    mov     (SignedVoluntaryExit_message + VoluntaryExit_epoch)(%r12), %rdx
    ADDRESS %rcx, lantern_type_VoluntaryExit
    lea     SignedVoluntaryExit_message(%r12), %r8
    mov     S9(%rsp), %r9
    add     $Validator_pubkey, %r9
    call    verify_signed
.endif
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     %rbx, %rdi                      # seen.voluntary_exit_indices.add(validator_index)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_VOLUNTARY_EXIT, %esi
    mov     S10(%rsp), %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_add_key
    jmp     8f
3:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    jmp     6f
    GOSSIP_TAIL L, 64
SPEC_END validate_voluntary_exit_gossip

/*
 * rbx seen, rbp store, r12 proposer slashing, r13 signed header, r14 head state, r15 scratch; S9 validator,
 * S10 proposer index. Locals: L result, L+8 current epoch, L+16 predicate.
 */
SPEC_FUNCTION validate_proposer_slashing_gossip
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r14
    mov     %r8, %r15
    mov     %r9, L(%rsp)
    movq    $0, (%r9)
    NEED_SCRATCH %r15, %r14, 0, 9f
    mov     (ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)(%r12), %rax
    mov     %rax, S10(%rsp)
    mov     %rbx, %rdi                      # [IGNORE] the first valid slashing for this proposer
    mov     $SEEN_PROPOSER_SLASHING, %esi
    mov     %rax, %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    lea     (ProposerSlashing_signed_header_1 + SignedBeaconBlockHeader_message)(%r12), %rsi
    lea     (ProposerSlashing_signed_header_2 + SignedBeaconBlockHeader_message)(%r12), %rdi
    mov     BeaconBlockHeader_slot(%rsi), %rax  # [REJECT] the header slots match
    cmp     BeaconBlockHeader_slot(%rdi), %rax
    jne     5f
    mov     BeaconBlockHeader_proposer_index(%rsi), %rax    # [REJECT] the proposer indices match
    cmp     BeaconBlockHeader_proposer_index(%rdi), %rax
    jne     5f
    xor     %ecx, %ecx                      # [REJECT] the headers are different
1:  cmp     $BeaconBlockHeader__mem, %rcx
    jae     5f
    mov     (%rsi,%rcx), %rax
    cmp     (%rdi,%rcx), %rax
    jne     2f
    add     $8, %rcx
    jmp     1b
2:  mov     S10(%rsp), %rax                 # [REJECT] the proposer index is valid
    VALIDATOR_AT %rcx, %r14, %rax, 5f
    mov     %rcx, S9(%rsp)
    mov     %r14, %rdi
    lea     (L + 8)(%rsp), %rsi
    call    lantern_get_current_epoch
    mov     S9(%rsp), %rdi                  # [REJECT] the proposer is slashable
    lea     (L + 8)(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_is_slashable_validator
    cmpq    $0, (L + 16)(%rsp)
    je      5f
    lea     ProposerSlashing_signed_header_1(%r12), %r13    # [REJECT] the two signatures are valid
21: lea     SignedBeaconBlockHeader_signature(%r13), %rax
    mov     %rax, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_BEACON_PROPOSER, %esi
    mov     (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%r13), %rdx
    shr     $LOG2_SLOTS_PER_EPOCH, %rdx
    ADDRESS %rcx, lantern_type_BeaconBlockHeader
    lea     SignedBeaconBlockHeader_message(%r13), %r8
    mov     S9(%rsp), %r9
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    lea     ProposerSlashing_signed_header_2(%r12), %rax
    cmp     %rax, %r13
    je      22f
    mov     %rax, %r13
    jmp     21b
22: mov     %rbx, %rdi                      # seen.proposer_slashing_indices.add(proposer_index)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_PROPOSER_SLASHING, %esi
    mov     S10(%rsp), %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_add_key
    jmp     8f
    GOSSIP_TAIL L, 32
SPEC_END validate_proposer_slashing_gossip

.if FORK >= FORK_CAPELLA
/*
 * rbx seen, rbp store, r12 signed change, r13 current_time_ms, r14 head state, r15 scratch; S9 validator,
 * S10 validator index. Locals: L result, L+8 digest (32), L+40 domain type, L+48 domain (32).
 */
SPEC_FUNCTION validate_bls_to_execution_change_gossip
    ENTER 80
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     (80 + 96)(%rsp), %rax           # the seventh argument
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH %r15, %r14, 0, 9f
    mov     (SignedBLSToExecutionChange_message + BLSToExecutionChange_validator_index)(%r12), %rax
    mov     %rax, S10(%rsp)
    mov     %rbx, %rdi                      # [IGNORE] the first valid change for the validator
    mov     $SEEN_BLS_CHANGE, %esi
    mov     %rax, %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] the current epoch is at or after CAPELLA_FORK_EPOCH
    mov     (Store_config + CONFIG_CAPELLA_FORK_EPOCH)(%rbp), %rsi
    mov     %r13, %rdx
    call    is_future_epoch
    test    %rax, %rax
    jnz     4f
    mov     S10(%rsp), %rax                 # [REJECT] the validator index is valid
    VALIDATOR_AT %rcx, %r14, %rax, 5f
    mov     %rcx, S9(%rsp)
    cmpb    $BLS_WITHDRAWAL_PREFIX, Validator_withdrawal_credentials(%rcx)  # [REJECT] BLS withdrawal credentials
    jne     5f
    lea     (SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)(%r12), %rdi
    mov     $48, %esi
    lea     (L + 8)(%rsp), %rdx
    call    sha256_short                    # [REJECT] withdrawal_credentials[1:] == sha256(pubkey)[1:]
    movb    $BLS_WITHDRAWAL_PREFIX, (L + 8)(%rsp)
    mov     S9(%rsp), %rax
    add     $Validator_withdrawal_credentials, %rax
    lea     (L + 8)(%rsp), %rcx
    NE32    %rax, %rcx, 5f
    movl    $DOMAIN_BLS_TO_EXECUTION_CHANGE, (L + 40)(%rsp)    # [REJECT] the signature: compute_domain(type, GENESIS_FORK_VERSION, gvr)
    lea     (L + 40)(%rsp), %rdi
    lea     (Store_config + CONFIG_GENESIS_FORK_VERSION)(%rbp), %rsi
    lea     BeaconState_genesis_validators_root(%r14), %rdx
    mov     %r15, %rcx
    lea     (L + 48)(%rsp), %r8
    call    lantern_compute_domain
    test    %rax, %rax
    jnz     7f
    lea     (L + 48)(%rsp), %rdi
    ADDRESS %rsi, lantern_type_BLSToExecutionChange
    lea     SignedBLSToExecutionChange_message(%r12), %rdx
    lea     (SignedBLSToExecutionChange_message + BLSToExecutionChange_from_bls_pubkey)(%r12), %rcx
    lea     SignedBLSToExecutionChange_signature(%r12), %r8
    mov     %r15, %r9
    call    verify_with_domain
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     %rbx, %rdi                      # seen.bls_to_execution_change_indices.add(validator_index)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_BLS_CHANGE, %esi
    mov     S10(%rsp), %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_add_key
    jmp     8f
    GOSSIP_TAIL L, 80
SPEC_END validate_bls_to_execution_change_gossip
.endif

/* ---------------------------------------------------------------- Gossip: attestations */

.if FORK >= FORK_ELECTRA
/*
 * rbx seen, rbp store, r12 single attestation, r13 current_time_ms, r14 head state, r15 scratch;
 * S9 scratch size, S10 validator count. Locals: L result, L+8 subnet_id, L+16 committees_per_slot,
 * L+24 committee list, L+32 block node.
 */
SPEC_FUNCTION validate_beacon_attestation_gossip
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     (%r8), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     %r9, %r14
    mov     (48 + 96)(%rsp), %r15           # the seventh and eighth arguments
    mov     (48 + 96 + 8)(%rsp), %rax
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH %r15, %r14, 3, 9f
    mov     (%r15), %rax
    mov     %rax, S9(%rsp)
    mov     (BeaconState_validators + 8)(%r14), %rax
    mov     %rax, S10(%rsp)
    mov     %rbx, %rdi                      # [IGNORE] no attestation seen for (target epoch, attester)
    mov     $SEEN_ATTESTATION, %esi
    mov     (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rdx
    mov     SingleAttestation_attester_index(%r12), %rcx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    cmpq    $0, (SingleAttestation_data + AttestationData_index)(%r12)    # [REJECT] data.index is zero
    jne     5f
    mov     %rbp, %rdi                      # [IGNORE] the block voted for has been seen; [REJECT] it passed validation
    mov     %rbx, %rsi
    lea     (SingleAttestation_data + AttestationData_beacon_block_root)(%r12), %rdx
    call    block_lookup
    test    %rdx, %rdx
    jz      4f
    cmp     $2, %rdx
    jne     5f
    mov     %rax, (L + 32)(%rsp)
    mov     S9(%rsp), %rax                  # [REJECT] the committee index is in range
    mov     %rax, (%r15)
    mov     %r14, %rdi
    lea     (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rsi
    mov     %r15, %rcx
    lea     (L + 16)(%rsp), %r8
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbp), %rdx
    call    lantern_get_committee_count_per_slot
    CHECK_RESULT L, 7f, 8f
    mov     (L + 16)(%rsp), %rcx
    mov     SingleAttestation_committee_index(%r12), %rdx
    cmp     %rcx, %rdx
    jae     5f
    mov     (SingleAttestation_data + AttestationData_slot)(%r12), %rax    # [REJECT] the subnet: compute_subnet_for_attestation
    and     $(SLOTS_PER_EPOCH - 1), %rax
    imul    %rcx, %rax
    add     %rdx, %rax
    and     $(ATTESTATION_SUBNET_COUNT - 1), %rax
    cmp     (L + 8)(%rsp), %rax
    jne     5f
    mov     %rbp, %rdi                      # [IGNORE] not from a future slot
    mov     (SingleAttestation_data + AttestationData_slot)(%r12), %rsi
    mov     %r13, %rdx
    call    is_future_slot
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] the current or previous epoch
    mov     (SingleAttestation_data + AttestationData_slot)(%r12), %rsi
    shr     $LOG2_SLOTS_PER_EPOCH, %rsi
    mov     %r13, %rdx
    call    is_current_or_previous_epoch
    test    %rax, %rax
    jz      4f
    mov     (SingleAttestation_data + AttestationData_slot)(%r12), %rax    # [REJECT] the epoch matches the target
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    cmp     (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rax
    jne     5f
    mov     S10(%rsp), %rcx                 # committee = get_beacon_committee(state, data.slot, committee_index)
    mov     S9(%rsp), %rdx
    SCRATCH_LIST %rax, %r15, %rdx, 0, %rcx
    mov     %rax, (L + 24)(%rsp)
    SCRATCH_GIVE %r15, %rdx, 1, %rcx
    mov     %r14, %rdi
    lea     (SingleAttestation_data + AttestationData_slot)(%r12), %rsi
    lea     SingleAttestation_committee_index(%r12), %rdx
    mov     %r15, %r8
    mov     (L + 24)(%rsp), %r9
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbp), %rcx
    call    lantern_get_beacon_committee
    CHECK_RESULT L, 7f, 8f
    mov     (L + 24)(%rsp), %rsi            # [REJECT] the attester is in the committee
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    mov     SingleAttestation_attester_index(%r12), %rdx
1:  test    %rcx, %rcx
    jz      5f
    cmp     %rdx, (%rsi)
    je      2f
    add     $8, %rsi
    dec     %rcx
    jmp     1b
2:  VALIDATOR_AT %r9, %r14, %rdx, 5f        # [REJECT] the signature
    mov     S10(%rsp), %rcx
    mov     S9(%rsp), %rdx
    SCRATCH_GIVE %r15, %rdx, 1, %rcx
    lea     SingleAttestation_signature(%r12), %rax
    mov     %rax, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_BEACON_ATTESTER, %esi
    mov     (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rdx
    ADDRESS %rcx, lantern_type_AttestationData
    lea     SingleAttestation_data(%r12), %r8
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     %rbp, %rdi                      # [REJECT] the target block is an ancestor of the LMD vote block
    mov     (L + 32)(%rsp), %rsi
    mov     (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rdx
    lea     (SingleAttestation_data + AttestationData_target + Checkpoint_root)(%r12), %rcx
    call    checkpoint_is
    CHECK_RESULT L, 7f, 8f
    test    %rdx, %rdx
    jz      5f
    mov     %rbp, %rdi                      # [IGNORE] the finalized checkpoint is an ancestor of the block
    mov     (L + 32)(%rsp), %rsi
    call    finalized_is_ancestor
    CHECK_RESULT L, 7f, 8f
    test    %rdx, %rdx
    jz      4f
    mov     %rbx, %rdi                      # seen.attestation_validator_epochs.add(...)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_ATTESTATION, %esi
    mov     (SingleAttestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rdx
    mov     SingleAttestation_attester_index(%r12), %rcx
    xor     %r8d, %r8d
    call    seen_add_key
    jmp     8f
    GOSSIP_TAIL L, 48
SPEC_END validate_beacon_attestation_gossip
.else
/*
 * rbx seen, rbp store, r12 attestation, r13 current_time_ms, r14 head state, r15 scratch;
 * S9 scratch size, S10 validator count. Locals: L result, L+8 subnet_id, L+16 committees_per_slot,
 * L+24 committee list, L+32 block node, L+40 participant index, L+48 bit length, L+56 bit count.
 */
SPEC_FUNCTION validate_beacon_attestation_gossip
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     (%r8), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     %r9, %r14
    mov     (64 + 96)(%rsp), %r15           # the seventh and eighth arguments
    mov     (64 + 96 + 8)(%rsp), %rax
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH %r15, %r14, 3, 9f
    mov     (%r15), %rax
    mov     %rax, S9(%rsp)
    mov     (BeaconState_validators + 8)(%r14), %rax
    mov     %rax, S10(%rsp)
    mov     %rbp, %rdi                      # [IGNORE] the block voted for has been seen; [REJECT] it passed validation
    mov     %rbx, %rsi
    lea     (Attestation_data + AttestationData_beacon_block_root)(%r12), %rdx
    call    block_lookup
    test    %rdx, %rdx
    jz      4f
    cmp     $2, %rdx
    jne     5f
    mov     %rax, (L + 32)(%rsp)
    mov     S9(%rsp), %rax                  # [REJECT] the committee index is in range
    mov     %rax, (%r15)
    mov     %r14, %rdi
    lea     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rsi
    mov     %r15, %rcx
    lea     (L + 16)(%rsp), %r8
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbp), %rdx
    call    lantern_get_committee_count_per_slot
    CHECK_RESULT L, 7f, 8f
    mov     (L + 16)(%rsp), %rcx
    mov     (Attestation_data + AttestationData_index)(%r12), %rdx
    cmp     %rcx, %rdx
    jae     5f
    mov     (Attestation_data + AttestationData_slot)(%r12), %rax    # [REJECT] the subnet: compute_subnet_for_attestation
    and     $(SLOTS_PER_EPOCH - 1), %rax
    imul    %rcx, %rax
    add     %rdx, %rax
    and     $(ATTESTATION_SUBNET_COUNT - 1), %rax
    cmp     (L + 8)(%rsp), %rax
    jne     5f
.if FORK >= FORK_DENEB
    mov     %rbp, %rdi                      # [IGNORE] not from a future slot
    mov     (Attestation_data + AttestationData_slot)(%r12), %rsi
    mov     %r13, %rdx
    call    is_future_slot
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] the current or previous epoch
    mov     (Attestation_data + AttestationData_slot)(%r12), %rsi
    shr     $LOG2_SLOTS_PER_EPOCH, %rsi
    mov     %r13, %rdx
    call    is_current_or_previous_epoch
    test    %rax, %rax
    jz      4f
.else
    mov     %rbp, %rdi                      # [IGNORE] the slot is within ATTESTATION_PROPAGATION_SLOT_RANGE
    mov     (Attestation_data + AttestationData_slot)(%r12), %rsi
    mov     (Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE)(%rbp), %rdx
    mov     %r13, %rcx
    call    is_within_slot_range
    test    %rax, %rax
    jz      4f
.endif
    mov     (Attestation_data + AttestationData_slot)(%r12), %rax    # [REJECT] the epoch matches the target
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    cmp     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rax
    jne     5f
    PART    %rdi, %rax, %r12, Attestation_aggregation_bits  # [REJECT] unaggregated: exactly one bit set
    mov     %rax, (L + 48)(%rsp)
    lea     (L + 48)(%rsp), %rsi
    lea     (L + 56)(%rsp), %rdx
    call    lantern_get_set_bit_count
    cmpq    $1, (L + 56)(%rsp)
    jne     5f
    mov     S10(%rsp), %rcx                 # committee = get_beacon_committee(state, data.slot, committee_index)
    mov     S9(%rsp), %rdx
    SCRATCH_LIST %rax, %r15, %rdx, 0, %rcx
    mov     %rax, (L + 24)(%rsp)
    SCRATCH_GIVE %r15, %rdx, 1, %rcx
    mov     %r14, %rdi
    lea     (Attestation_data + AttestationData_slot)(%r12), %rsi
    lea     (Attestation_data + AttestationData_index)(%r12), %rdx
    mov     %r15, %r8
    mov     (L + 24)(%rsp), %r9
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbp), %rcx
    call    lantern_get_beacon_committee
    CHECK_RESULT L, 7f, 8f
    mov     (L + 24)(%rsp), %rsi            # [REJECT] len(aggregation_bits) == len(committee)
    mov     LIST_COUNT(%rsi), %rax
    cmp     (L + 48)(%rsp), %rax
    jne     5f
    PART    %rdi, %rax, %r12, Attestation_aggregation_bits  # participant_index: the committee member of the set bit
    xor     %ecx, %ecx
1:  bt      %rcx, (%rdi)
    jc      2f
    inc     %rcx
    jmp     1b
2:  mov     (L + 24)(%rsp), %rsi
    mov     LIST_FIXED(%rsi,%rcx,8), %rcx
    mov     %rcx, (L + 40)(%rsp)
    mov     %rbx, %rdi                      # [IGNORE] no attestation seen for (target epoch, participant)
    mov     $SEEN_ATTESTATION, %esi
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rdx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     (L + 40)(%rsp), %rdx            # [REJECT] the signature: is_valid_indexed_attestation of the one attester
    VALIDATOR_AT %r9, %r14, %rdx, 5f
    mov     S10(%rsp), %rcx
    mov     S9(%rsp), %rdx
    SCRATCH_GIVE %r15, %rdx, 1, %rcx
    lea     Attestation_signature(%r12), %rax
    mov     %rax, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_BEACON_ATTESTER, %esi
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rdx
    ADDRESS %rcx, lantern_type_AttestationData
    lea     Attestation_data(%r12), %r8
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     %rbp, %rdi                      # [REJECT] the target block is an ancestor of the LMD vote block
    mov     (L + 32)(%rsp), %rsi
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rdx
    lea     (Attestation_data + AttestationData_target + Checkpoint_root)(%r12), %rcx
    call    checkpoint_is
    CHECK_RESULT L, 7f, 8f
    test    %rdx, %rdx
    jz      5f
    mov     %rbp, %rdi                      # [IGNORE] the finalized checkpoint is an ancestor of the block
    mov     (L + 32)(%rsp), %rsi
    call    finalized_is_ancestor
    CHECK_RESULT L, 7f, 8f
    test    %rdx, %rdx
    jz      4f
    mov     %rbx, %rdi                      # seen.attestation_validator_epochs.add(...)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_ATTESTATION, %esi
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%r12), %rdx
    mov     (L + 40)(%rsp), %rcx
    xor     %r8d, %r8d
    call    seen_add_key
    jmp     8f
    GOSSIP_TAIL L, 64
SPEC_END validate_beacon_attestation_gossip
.endif

/*
 * rbx seen, rbp store, r12 signed aggregate and proof, r13 current_time_ms, r14 head state, r15 scratch;
 * S9 the aggregate, S10 the aggregate and proof. Locals: L result, L+8 committee index, L+16 committee count,
 * L+24 data root (32), L+56 block node, L+64 committee list, L+72 attesting list, L+80 indexed attestation,
 * L+88 front size, L+96 valid, L+104 digest (32), L+136 target epoch, L+144 aggregator.
 */
SPEC_FUNCTION validate_beacon_aggregate_and_proof_gossip
    ENTER 160
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     (160 + 96)(%rsp), %rax          # the seventh argument
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH_B %r15, %r14, 10, IndexedAttestation__fixed + 8, 9f
    mov     (BeaconState_validators + 8)(%r14), %rcx  # own scratch at the end: committee, attesting indices, indexed attestation
    lea     LIST_FIXED(,%rcx,8), %rcx       # L(n)
    mov     (%r15), %rdx
    sub     %rcx, %rdx
    lea     (%r15,%rdx), %rax
    mov     %rcx, (%rax)
    mov     %rax, (L + 64)(%rsp)
    sub     %rcx, %rdx
    lea     (%r15,%rdx), %rax
    mov     %rcx, (%rax)
    mov     %rax, (L + 72)(%rsp)
    lea     (IndexedAttestation__fixed + 8)(%rcx), %rcx
    sub     %rcx, %rdx
    lea     (%r15,%rdx), %rax
    mov     %rcx, (%rax)
    mov     %rax, (L + 80)(%rsp)
    mov     %rdx, (L + 88)(%rsp)
    mov     %rdx, (%r15)
    PART    %rax, %rcx, %r12, SignedAggregateAndProof_message
    mov     %rax, S10(%rsp)
    PART    %rdx, %rcx, %rax, AggregateAndProof_aggregate
    mov     %rdx, S9(%rsp)
    mov     AggregateAndProof_aggregator_index(%rax), %rcx
    mov     %rcx, (L + 144)(%rsp)
    mov     (Attestation_data + AttestationData_target + Checkpoint_epoch)(%rdx), %rcx
    mov     %rcx, (L + 136)(%rsp)
.if FORK >= FORK_ELECTRA
    cmpq    $0, (Attestation_data + AttestationData_index)(%rdx)  # [REJECT] data.index is zero
    jne     5f
    xor     %ecx, %ecx                      # [REJECT] exactly one committee in committee_bits
    xor     %esi, %esi
1:  cmp     $MAX_COMMITTEES_PER_SLOT, %rcx
    jae     2f
    bt      %rcx, Attestation_committee_bits(%rdx)
    jnc     11f
    mov     %rcx, (L + 8)(%rsp)
    inc     %rsi
11: inc     %rcx
    jmp     1b
2:  cmp     $1, %rsi
    jne     5f
.else
    mov     (Attestation_data + AttestationData_index)(%rdx), %rcx    # index = aggregate.data.index
    mov     %rcx, (L + 8)(%rsp)
.endif
    ADDRESS %rdi, lantern_type_AttestationData  # [IGNORE] no seen aggregate with a superset of the bits
    lea     Attestation_data(%rdx), %rsi
    mov     %r15, %rdx
    lea     (L + 24)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     (L + 88)(%rsp), %rax
    mov     %rax, (%r15)
    mov     S9(%rsp), %rax
    PART    %r9, %r10, %rax, Attestation_aggregation_bits
    mov     %r10, %rax
    mov     %rbx, %rdi
    mov     $SEEN_AGGREGATE, %esi
    lea     (L + 24)(%rsp), %rdx
.if FORK >= FORK_ELECTRA
    mov     (L + 8)(%rsp), %rcx             # the key: (data root, committee index)
.else
    xor     %ecx, %ecx                      # the key: the data root
.endif
    xor     %r8d, %r8d
    call    seen_superset
    test    %rax, %rax
    jnz     4f
    mov     %rbx, %rdi                      # [IGNORE] the first valid aggregate for (target epoch, aggregator)
    mov     $SEEN_AGGREGATOR_EPOCH, %esi
    mov     (L + 136)(%rsp), %rdx
    mov     (L + 144)(%rsp), %rcx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] the block voted for has been seen; [REJECT] it passed validation
    mov     %rbx, %rsi
    mov     S9(%rsp), %rdx
    add     $(Attestation_data + AttestationData_beacon_block_root), %rdx
    call    block_lookup
    test    %rdx, %rdx
    jz      4f
    cmp     $2, %rdx
    jne     5f
    mov     %rax, (L + 56)(%rsp)
    mov     %r14, %rdi                      # [REJECT] the committee index is in range
    lea     (L + 136)(%rsp), %rsi
    mov     %r15, %rcx
    lea     (L + 16)(%rsp), %r8
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbp), %rdx
    call    lantern_get_committee_count_per_slot
    CHECK_RESULT L, 7f, 8f
    mov     (L + 8)(%rsp), %rax
    cmp     (L + 16)(%rsp), %rax
    jae     5f
.if FORK >= FORK_DENEB
    mov     %rbp, %rdi                      # [IGNORE] not from a future slot
    mov     S9(%rsp), %rsi
    mov     (Attestation_data + AttestationData_slot)(%rsi), %rsi
    mov     %r13, %rdx
    call    is_future_slot
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] the current or previous epoch
    mov     S9(%rsp), %rsi
    mov     (Attestation_data + AttestationData_slot)(%rsi), %rsi
    shr     $LOG2_SLOTS_PER_EPOCH, %rsi
    mov     %r13, %rdx
    call    is_current_or_previous_epoch
    test    %rax, %rax
    jz      4f
.else
    mov     %rbp, %rdi                      # [IGNORE] the slot is within ATTESTATION_PROPAGATION_SLOT_RANGE
    mov     S9(%rsp), %rsi
    mov     (Attestation_data + AttestationData_slot)(%rsi), %rsi
    mov     (Store_config + CONFIG_ATTESTATION_PROPAGATION_SLOT_RANGE)(%rbp), %rdx
    mov     %r13, %rcx
    call    is_within_slot_range
    test    %rax, %rax
    jz      4f
.endif
    mov     S9(%rsp), %rax                  # [REJECT] the epoch matches the target
    mov     (Attestation_data + AttestationData_slot)(%rax), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    cmp     (L + 136)(%rsp), %rax
    jne     5f
    mov     (L + 88)(%rsp), %rax            # committee = get_beacon_committee(state, data.slot, index)
    mov     %rax, (%r15)
    mov     %r14, %rdi
    mov     S9(%rsp), %rsi
    add     $(Attestation_data + AttestationData_slot), %rsi
    lea     (L + 8)(%rsp), %rdx
    mov     %r15, %r8
    mov     (L + 64)(%rsp), %r9
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbp), %rcx
    call    lantern_get_beacon_committee
    CHECK_RESULT L, 7f, 8f
    mov     (L + 64)(%rsp), %rax            # [REJECT] len(aggregation_bits) == len(committee)
    mov     LIST_COUNT(%rax), %rax
    mov     S9(%rsp), %rcx
    cmp     (Attestation_aggregation_bits + 8)(%rcx), %rax
    jne     5f
    mov     (L + 88)(%rsp), %rax            # [REJECT] the aggregate has participants: get_attesting_indices
    mov     %rax, (%r15)
    mov     %r14, %rdi
    mov     S9(%rsp), %rsi
    mov     %r15, %rcx
    mov     (L + 72)(%rsp), %r8
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbp), %rdx
    call    lantern_get_attesting_indices
    CHECK_RESULT L, 7f, 8f
    mov     (L + 72)(%rsp), %rax
    cmpq    $0, LIST_COUNT(%rax)
    je      5f
    mov     S10(%rsp), %rdi                 # [REJECT] is_aggregator(state, slot, index, selection_proof)
    add     $AggregateAndProof_selection_proof, %rdi
    mov     $96, %esi
    lea     (L + 104)(%rsp), %rdx
    call    sha256_short
    mov     (L + 64)(%rsp), %rcx
    mov     LIST_COUNT(%rcx), %rcx
    shr     $4, %rcx                        # len(committee) // TARGET_AGGREGATORS_PER_COMMITTEE, at least 1
    mov     $1, %eax
    test    %rcx, %rcx
    cmovz   %rax, %rcx
    mov     (L + 104)(%rsp), %rax
    xor     %edx, %edx
    div     %rcx
    test    %rdx, %rdx
    jnz     5f
    mov     (L + 64)(%rsp), %rsi            # [REJECT] the aggregator is in the committee
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    mov     (L + 144)(%rsp), %rdx
21: test    %rcx, %rcx
    jz      5f
    cmp     %rdx, (%rsi)
    je      22f
    add     $8, %rsi
    dec     %rcx
    jmp     21b
22: mov     (L + 88)(%rsp), %rax            # [REJECT] the selection proof signature
    mov     %rax, (%r15)
    VALIDATOR_AT %r9, %r14, %rdx, 5f
    mov     %r9, (L + 96)(%rsp)
    mov     S10(%rsp), %rax
    add     $AggregateAndProof_selection_proof, %rax
    mov     %rax, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_SELECTION_PROOF, %esi
    mov     (L + 136)(%rsp), %rdx
    ADDRESS %rcx, lantern_type_Uint64
    mov     S9(%rsp), %r8
    add     $(Attestation_data + AttestationData_slot), %r8
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     (L + 88)(%rsp), %rax            # [REJECT] the aggregator signature
    mov     %rax, (%r15)
    lea     SignedAggregateAndProof_signature(%r12), %rax
    mov     %rax, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_AGGREGATE_AND_PROOF, %esi
    mov     (L + 136)(%rsp), %rdx
    ADDRESS %rcx, lantern_type_AggregateAndProof
    mov     S10(%rsp), %r8
    mov     (L + 96)(%rsp), %r9
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     (L + 88)(%rsp), %rax            # [REJECT] the aggregate signature: is_valid_indexed_attestation(get_indexed_attestation)
    mov     %rax, (%r15)
    mov     %r14, %rdi
    mov     S9(%rsp), %rsi
    mov     %r15, %rcx
    mov     (L + 80)(%rsp), %r8
    mov     (Store_config + CONFIG_COMMITTEE_CACHE)(%rbp), %rdx
    call    lantern_get_indexed_attestation
    CHECK_RESULT L, 7f, 8f
    mov     (L + 88)(%rsp), %rax
    mov     %rax, (%r15)
    mov     %r14, %rdi
    mov     (L + 80)(%rsp), %rsi
    mov     %r15, %rdx
    lea     (L + 96)(%rsp), %rcx
    call    lantern_is_valid_indexed_attestation
    CHECK_RESULT L, 7f, 8f
    cmpq    $0, (L + 96)(%rsp)
    je      5f
    mov     %rbp, %rdi                      # [REJECT] the target block is an ancestor of the LMD vote block
    mov     (L + 56)(%rsp), %rsi
    mov     (L + 136)(%rsp), %rdx
    mov     S9(%rsp), %rcx
    add     $(Attestation_data + AttestationData_target + Checkpoint_root), %rcx
    call    checkpoint_is
    CHECK_RESULT L, 7f, 8f
    test    %rdx, %rdx
    jz      5f
    mov     %rbp, %rdi                      # [IGNORE] the finalized checkpoint is an ancestor of the block
    mov     (L + 56)(%rsp), %rsi
    call    finalized_is_ancestor
    CHECK_RESULT L, 7f, 8f
    test    %rdx, %rdx
    jz      4f
    mov     %rbx, %rdi                      # seen: the aggregator epoch and the bits of the data root
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    call    seen_bits_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_AGGREGATOR_EPOCH, %esi
    mov     (L + 136)(%rsp), %rdx
    mov     (L + 144)(%rsp), %rcx
    xor     %r8d, %r8d
    call    seen_add_key
    mov     S9(%rsp), %rax
    PART    %r9, %r10, %rax, Attestation_aggregation_bits
    mov     %r10, %rax
    mov     %rbx, %rdi
    mov     $SEEN_AGGREGATE, %esi
    lea     (L + 24)(%rsp), %rdx
.if FORK >= FORK_ELECTRA
    mov     (L + 8)(%rsp), %rcx             # the key: (data root, committee index)
.else
    xor     %ecx, %ecx                      # the key: the data root
.endif
    xor     %r8d, %r8d
    call    seen_add_bits
    jmp     8f
    GOSSIP_TAIL L, 160
SPEC_END validate_beacon_aggregate_and_proof_gossip

/* ---------------------------------------------------------------- Gossip: sync committee */

.if FORK >= FORK_ALTAIR
.set SYNC_SUBCOMMITTEE_SIZE, SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT
.set SYNC_SUB_KEYS, 24 + 48 * SYNC_SUBCOMMITTEE_SIZE    /* a BlsPublicKeyList of one subcommittee */
.if (SYNC_SUBCOMMITTEE_SIZE / TARGET_AGGREGATORS_PER_SYNC_SUBCOMMITTEE) > 1
.set SYNC_AGGREGATOR_MODULO, SYNC_SUBCOMMITTEE_SIZE / TARGET_AGGREGATORS_PER_SYNC_SUBCOMMITTEE
.else
.set SYNC_AGGREGATOR_MODULO, 1
.endif

/*
 * dst = the sync committee of state st for its next slot: current_sync_committee when the period of the
 * current epoch is that of the next slot's epoch, else next_sync_committee. Uses rax, rcx, rdx, r10.
 */
.macro SYNC_COMMITTEE_OF dst, st
    mov     BeaconState_slot(\st), %rax
    lea     1(%rax), %r10
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %r10
    xor     %edx, %edx
    mov     $EPOCHS_PER_SYNC_COMMITTEE_PERIOD, %ecx
    div     %rcx
    mov     %rax, %rcx
    mov     %r10, %rax
    mov     %rcx, %r10
    xor     %edx, %edx
    mov     $EPOCHS_PER_SYNC_COMMITTEE_PERIOD, %ecx
    div     %rcx
    MOVQ    \dst, BeaconState_current_sync_committee
    cmp     %rax, %r10
    je      98f
    MOVQ    \dst, BeaconState_next_sync_committee
98: add     \st, \dst
.endm

/*
 * rbx seen, rbp store, r12 message, r13 current_time_ms, r14 head state, r15 scratch; S9 validator, S10 i.
 * Locals: L result, L+8 subnet_id, L+16 the sync committee's keys.
 */
SPEC_FUNCTION validate_sync_committee_message_gossip
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     (%r8), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     %r9, %r14
    mov     (32 + 96)(%rsp), %r15           # the seventh and eighth arguments
    mov     (32 + 96 + 8)(%rsp), %rax
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH %r15, %r14, 0, 9f
    mov     %rbx, %rdi                      # [IGNORE] the first valid message for (slot, validator, subnet)
    mov     $SEEN_SYNC_MESSAGE, %esi
    mov     SyncCommitteeMessage_slot(%r12), %rdx
    mov     SyncCommitteeMessage_validator_index(%r12), %rcx
    mov     (L + 8)(%rsp), %r8
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] is_current_slot
    mov     SyncCommitteeMessage_slot(%r12), %rsi
    xor     %edx, %edx
    mov     %r13, %rcx
    call    is_within_slot_range
    test    %rax, %rax
    jz      4f
    mov     SyncCommitteeMessage_validator_index(%r12), %rax   # [REJECT] the validator index is valid
    VALIDATOR_AT %rcx, %r14, %rax, 5f
    mov     %rcx, S9(%rsp)
    SYNC_COMMITTEE_OF %rsi, %r14            # [REJECT] subnet_id in compute_subnets_for_sync_committee
    add     $SyncCommittee_pubkeys, %rsi
    mov     %rsi, (L + 16)(%rsp)
    movq    $0, S10(%rsp)
1:  mov     S10(%rsp), %rax
    cmp     $SYNC_COMMITTEE_SIZE, %rax
    jae     5f
    imul    $48, %rax, %rax
    add     (L + 16)(%rsp), %rax
    mov     S9(%rsp), %rcx
    add     $Validator_pubkey, %rcx
    NE48    %rax, %rcx, 3f
    mov     S10(%rsp), %rax
    xor     %edx, %edx
    mov     $SYNC_SUBCOMMITTEE_SIZE, %ecx
    div     %rcx
    cmp     (L + 8)(%rsp), %rax
    je      31f
3:  incq    S10(%rsp)
    jmp     1b
31: lea     SyncCommitteeMessage_signature(%r12), %rax  # [REJECT] the signature
    mov     %rax, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_SYNC_COMMITTEE, %esi
    mov     SyncCommitteeMessage_slot(%r12), %rdx
    shr     $LOG2_SLOTS_PER_EPOCH, %rdx
    ADDRESS %rcx, lantern_type_Bytes32
    lea     SyncCommitteeMessage_beacon_block_root(%r12), %r8
    mov     S9(%rsp), %r9
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     %rbx, %rdi                      # seen.sync_message_validator_slots.add(...)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_SYNC_MESSAGE, %esi
    mov     SyncCommitteeMessage_slot(%r12), %rdx
    mov     SyncCommitteeMessage_validator_index(%r12), %rcx
    mov     (L + 8)(%rsp), %r8
    call    seen_add_key
    jmp     8f
    GOSSIP_TAIL L, 32
SPEC_END validate_sync_committee_message_gossip

/*
 * rbx seen, rbp store, r12 signed contribution and proof, r13 contribution, r14 head state, r15 scratch;
 * S9 aggregator validator, S10 subcommittee pubkeys.
 * Locals: L result, L+8 current_time_ms, L+16 selection data (16), L+32 digest (32), L+64 key list,
 * L+72 front size, L+80 domain type, L+88 epoch, L+96 domain (32), L+128 the signing root buffer (56),
 * L+184 valid, L+192 i.
 */
SPEC_FUNCTION validate_sync_committee_contribution_and_proof_gossip
    ENTER 208
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     %r8, %r14
    mov     %r9, %r15
    mov     (208 + 96)(%rsp), %rax          # the seventh argument
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH_B %r15, %r14, 1, SYNC_SUB_KEYS, 9f
    mov     (%r15), %rax                    # own scratch at the end: the participant keys
    MOVQ    %rcx, SYNC_SUB_KEYS
    sub     %rcx, %rax
    lea     (%r15,%rax), %rdx
    mov     %rcx, (%rdx)
    movq    $24, 8(%rdx)
    movq    $0, 16(%rdx)
    mov     %rdx, (L + 64)(%rsp)
    mov     %rax, (L + 72)(%rsp)
    mov     %rax, (%r15)
    lea     (SignedContributionAndProof_message + ContributionAndProof_contribution)(%r12), %r13
    mov     %rbx, %rdi                      # [IGNORE] no seen contribution with a superset of the bits
    mov     $SEEN_CONTRIBUTION, %esi
    lea     SyncCommitteeContribution_beacon_block_root(%r13), %rdx
    mov     SyncCommitteeContribution_slot(%r13), %rcx
    mov     SyncCommitteeContribution_subcommittee_index(%r13), %r8
    lea     SyncCommitteeContribution_aggregation_bits(%r13), %r9
    mov     $SYNC_SUBCOMMITTEE_SIZE, %eax
    call    seen_superset
    test    %rax, %rax
    jnz     4f
    mov     %rbx, %rdi                      # [IGNORE] the first valid contribution of (slot, aggregator, subcommittee)
    mov     $SEEN_SYNC_CONTRIBUTION, %esi
    mov     SyncCommitteeContribution_slot(%r13), %rdx
    mov     (SignedContributionAndProof_message + ContributionAndProof_aggregator_index)(%r12), %rcx
    mov     SyncCommitteeContribution_subcommittee_index(%r13), %r8
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] is_current_slot
    mov     SyncCommitteeContribution_slot(%r13), %rsi
    xor     %edx, %edx
    mov     (L + 8)(%rsp), %rcx
    call    is_within_slot_range
    test    %rax, %rax
    jz      4f
    cmpq    $SYNC_COMMITTEE_SUBNET_COUNT, SyncCommitteeContribution_subcommittee_index(%r13)  # [REJECT] the subcommittee index is in range
    jae     5f
    xor     %ecx, %ecx                      # [REJECT] the contribution has participants
    xor     %eax, %eax
1:  cmp     $(SYNC_SUBCOMMITTEE_SIZE / 8), %rcx
    jae     2f
    movzbl  SyncCommitteeContribution_aggregation_bits(%r13,%rcx), %edx
    or      %edx, %eax
    inc     %rcx
    jmp     1b
2:  test    %eax, %eax
    jz      5f
    lea     (SignedContributionAndProof_message + ContributionAndProof_selection_proof)(%r12), %rdi
    mov     $96, %esi                       # [REJECT] is_sync_committee_aggregator(selection_proof)
    lea     (L + 32)(%rsp), %rdx
    call    sha256_short
    mov     (L + 32)(%rsp), %rax
    xor     %edx, %edx
    mov     $SYNC_AGGREGATOR_MODULO, %ecx
    div     %rcx
    test    %rdx, %rdx
    jnz     5f
    mov     (SignedContributionAndProof_message + ContributionAndProof_aggregator_index)(%r12), %rax
    VALIDATOR_AT %rcx, %r14, %rax, 5f       # [REJECT] the aggregator index is valid
    mov     %rcx, S9(%rsp)
    SYNC_COMMITTEE_OF %rsi, %r14            # [REJECT] the aggregator is in get_sync_subcommittee_pubkeys
    imul    $(48 * SYNC_SUBCOMMITTEE_SIZE), SyncCommitteeContribution_subcommittee_index(%r13), %rax
    lea     SyncCommittee_pubkeys(%rsi,%rax), %rsi
    mov     %rsi, S10(%rsp)
    xor     %edx, %edx
3:  cmp     $SYNC_SUBCOMMITTEE_SIZE, %rdx
    jae     5f
    imul    $48, %rdx, %rax
    add     S10(%rsp), %rax
    mov     S9(%rsp), %rcx
    add     $Validator_pubkey, %rcx
    NE48    %rax, %rcx, 32f
    jmp     31f
32: inc     %rdx
    jmp     3b
31: mov     SyncCommitteeContribution_slot(%r13), %rax  # [REJECT] the selection proof signs SyncAggregatorSelectionData
    mov     %rax, (L + 16)(%rsp)
    mov     SyncCommitteeContribution_subcommittee_index(%r13), %rcx
    mov     %rcx, (L + 24)(%rsp)
    lea     (SignedContributionAndProof_message + ContributionAndProof_selection_proof)(%r12), %rcx
    mov     %rcx, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_SYNC_COMMITTEE_SELECTION_PROOF, %esi
    mov     %rax, %rdx
    shr     $LOG2_SLOTS_PER_EPOCH, %rdx
    ADDRESS %rcx, lantern_type_SyncAggregatorSelectionData
    lea     (L + 16)(%rsp), %r8
    mov     S9(%rsp), %r9
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     (L + 72)(%rsp), %rax            # [REJECT] the aggregator signature
    mov     %rax, (%r15)
    lea     SignedContributionAndProof_signature(%r12), %rax
    mov     %rax, S7(%rsp)
    mov     %r15, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_CONTRIBUTION_AND_PROOF, %esi
    mov     SyncCommitteeContribution_slot(%r13), %rdx
    shr     $LOG2_SLOTS_PER_EPOCH, %rdx
    ADDRESS %rcx, lantern_type_ContributionAndProof
    lea     SignedContributionAndProof_message(%r12), %r8
    mov     S9(%rsp), %r9
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    movq    $0, (L + 192)(%rsp)             # participant_pubkeys: the keys of the set bits
45: mov     (L + 192)(%rsp), %rcx
    cmp     $SYNC_SUBCOMMITTEE_SIZE, %rcx
    jae     42f
    bt      %rcx, SyncCommitteeContribution_aggregation_bits(%r13)
    jnc     41f
    imul    $48, %rcx, %rax
    add     S10(%rsp), %rax
    mov     (L + 64)(%rsp), %rdx
    KEYS_APPEND %rdx, %rax
41: incq    (L + 192)(%rsp)
    jmp     45b
42: movl    $DOMAIN_SYNC_COMMITTEE, (L + 80)(%rsp)  # [REJECT] eth_fast_aggregate_verify over the beacon_block_root
    mov     SyncCommitteeContribution_slot(%r13), %rax
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (L + 88)(%rsp)
    mov     (L + 72)(%rsp), %rax
    mov     %rax, (%r15)
    mov     %r14, %rdi
    lea     (L + 80)(%rsp), %rsi
    lea     (L + 88)(%rsp), %rdx
    mov     %r15, %rcx
    lea     (L + 96)(%rsp), %r8
    call    lantern_get_domain
    test    %rax, %rax
    jnz     7f
    mov     (L + 72)(%rsp), %rax
    mov     %rax, (%r15)
    ADDRESS %rdi, lantern_type_Bytes32
    lea     SyncCommitteeContribution_beacon_block_root(%r13), %rsi
    lea     (L + 96)(%rsp), %rdx
    mov     %r15, %rcx
    lea     (L + 128 + 24)(%rsp), %r8
    call    lantern_compute_signing_root
    test    %rax, %rax
    jnz     7f
    movq    $56, (L + 128)(%rsp)
    movq    $24, (L + 136)(%rsp)
    movq    $32, (L + 144)(%rsp)
    mov     (L + 72)(%rsp), %rax
    mov     %rax, (%r15)
    mov     (L + 64)(%rsp), %rdi
    lea     (L + 128)(%rsp), %rsi
    lea     SyncCommitteeContribution_signature(%r13), %rdx
    mov     %r15, %rcx
    lea     (L + 184)(%rsp), %r8
    CALL_GLOBAL crypto_bls_eth_fast_aggregate_verify
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (L + 184)(%rsp)
    je      5f
    mov     %rbx, %rdi                      # seen: the aggregator slot and the bits of the contribution
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    call    seen_bits_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_SYNC_CONTRIBUTION, %esi
    mov     SyncCommitteeContribution_slot(%r13), %rdx
    mov     (SignedContributionAndProof_message + ContributionAndProof_aggregator_index)(%r12), %rcx
    mov     SyncCommitteeContribution_subcommittee_index(%r13), %r8
    call    seen_add_key
    mov     %rbx, %rdi
    mov     $SEEN_CONTRIBUTION, %esi
    lea     SyncCommitteeContribution_beacon_block_root(%r13), %rdx
    mov     SyncCommitteeContribution_slot(%r13), %rcx
    mov     SyncCommitteeContribution_subcommittee_index(%r13), %r8
    lea     SyncCommitteeContribution_aggregation_bits(%r13), %r9
    mov     $SYNC_SUBCOMMITTEE_SIZE, %eax
    call    seen_add_bits
    jmp     8f
    GOSSIP_TAIL L, 208
SPEC_END validate_sync_committee_contribution_and_proof_gossip
.endif

/* ---------------------------------------------------------------- Gossip: attester slashings */

/*
 * rbx seen, rbp store, r12 attester slashing, r13 i, r14 head state, r15 scratch; S9 attestation 1,
 * S10 attestation 2. Locals: L result, L+8 front size, L+16 list 1, L+24 list 2, L+32 intersection,
 * L+40 new indices, L+48 current epoch, L+56 predicate.
 */
SPEC_FUNCTION validate_attester_slashing_gossip
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r14
    mov     %r8, %r15
    mov     %r9, L(%rsp)
    movq    $0, (%r9)
    PART    %rax, %rcx, %r12, AttesterSlashing_attestation_1
    mov     %rax, S9(%rsp)
    PART    %rax, %rcx, %r12, AttesterSlashing_attestation_2
    mov     %rax, S10(%rsp)
    mov     S9(%rsp), %rax                  # own scratch at the end: two sorted copies, the intersection
    mov     (IndexedAttestation_attesting_indices + 8)(%rax), %rsi
    mov     S10(%rsp), %rax
    mov     (IndexedAttestation_attesting_indices + 8)(%rax), %rdi
    mov     %rsi, %r8
    cmp     %rdi, %rsi
    cmova   %rdi, %r8                       # the smaller count
    lea     (%rsi,%rdi), %r9
    add     %r8, %r9
    lea     (3 * LIST_FIXED)(,%r9,8), %r9   # their bytes
    mov     (BeaconState_validators + 8)(%r14), %rax
    lea     LIST_FIXED(,%rax,8), %rax
    imul    $7, %rax, %rax
    add     $LANTERN_SCRATCH_FIXED, %rax    # S(7) for is_valid_indexed_attestation
    add     %r9, %rax
    cmp     %rax, (%r15)
    jb      9f
    mov     (%r15), %rax
    sub     %r9, %rax
    mov     %rax, (L + 8)(%rsp)
    lea     (%r15,%rax), %rax               # list 1
    lea     LIST_FIXED(,%rsi,8), %rcx
    mov     %rcx, (%rax)
    mov     %rax, (L + 16)(%rsp)
    add     %rcx, %rax                      # list 2
    lea     LIST_FIXED(,%rdi,8), %rcx
    mov     %rcx, (%rax)
    mov     %rax, (L + 24)(%rsp)
    add     %rcx, %rax                      # the intersection
    lea     LIST_FIXED(,%r8,8), %rcx
    mov     %rcx, (%rax)
    mov     %rax, (L + 32)(%rsp)
    mov     (L + 16)(%rsp), %rdi            # sorted copies of both attesting index lists
    mov     S9(%rsp), %rax
    PART    %rsi, %rdx, %rax, IndexedAttestation_attesting_indices
    mov     %rdx, LIST_COUNT(%rdi)
    add     $LIST_FIXED, %rdi
    shl     $3, %rdx
    call    lantern_copy
    mov     (L + 24)(%rsp), %rdi
    mov     S10(%rsp), %rax
    PART    %rsi, %rdx, %rax, IndexedAttestation_attesting_indices
    mov     %rdx, LIST_COUNT(%rdi)
    add     $LIST_FIXED, %rdi
    shl     $3, %rdx
    call    lantern_copy
    mov     (L + 16)(%rsp), %rdi
    mov     LIST_COUNT(%rdi), %rsi
    add     $LIST_FIXED, %rdi
    call    sort_u64
    mov     (L + 24)(%rsp), %rdi
    mov     LIST_COUNT(%rdi), %rsi
    add     $LIST_FIXED, %rdi
    call    sort_u64
    mov     (L + 16)(%rsp), %rsi            # slashable_indices = their intersection, each index once
    mov     LIST_COUNT(%rsi), %rcx
    add     $LIST_FIXED, %rsi
    mov     (L + 24)(%rsp), %rdi
    mov     LIST_COUNT(%rdi), %rdx
    add     $LIST_FIXED, %rdi
    mov     (L + 32)(%rsp), %r8
    add     $LIST_FIXED, %r8
    xor     %r9d, %r9d                      # its count
1:  test    %rcx, %rcx
    jz      3f
    test    %rdx, %rdx
    jz      3f
    mov     (%rsi), %rax
    cmp     (%rdi), %rax
    jb      12f
    ja      13f
    test    %r9, %r9
    jz      14f
    cmp     -8(%r8,%r9,8), %rax
    je      15f
14: mov     %rax, (%r8,%r9,8)
    inc     %r9
15: add     $8, %rsi
    dec     %rcx
13: add     $8, %rdi
    dec     %rdx
    jmp     1b
12: add     $8, %rsi
    dec     %rcx
    jmp     1b
3:  mov     (L + 32)(%rsp), %rax
    mov     %r9, LIST_COUNT(%rax)
    xor     %r13d, %r13d                    # [IGNORE] an index of the intersection not yet seen
    movq    $0, (L + 40)(%rsp)
2:  mov     (L + 32)(%rsp), %rax
    cmp     LIST_COUNT(%rax), %r13
    jae     21f
    mov     %rbx, %rdi
    mov     $SEEN_ATTESTER_SLASHING, %esi
    mov     LIST_FIXED(%rax,%r13,8), %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     211f
    incq    (L + 40)(%rsp)
211: inc     %r13
    jmp     2b
21: cmpq    $0, (L + 40)(%rsp)
    je      4f
    mov     S9(%rsp), %rdi                  # [REJECT] the data is slashable
    add     $IndexedAttestation_data, %rdi
    mov     S10(%rsp), %rsi
    add     $IndexedAttestation_data, %rsi
    lea     (L + 56)(%rsp), %rdx
    call    lantern_is_slashable_attestation_data
    cmpq    $0, (L + 56)(%rsp)
    je      5f
    mov     S9(%rsp), %r13                  # [REJECT] each attestation: valid indices, is_valid_indexed_attestation
22: PART    %rsi, %rcx, %r13, IndexedAttestation_attesting_indices
    mov     (BeaconState_validators + 8)(%r14), %rdx
23: test    %rcx, %rcx
    jz      24f
    cmp     %rdx, (%rsi)
    jae     5f
    add     $8, %rsi
    dec     %rcx
    jmp     23b
24: mov     (L + 8)(%rsp), %rax
    mov     %rax, (%r15)
    mov     %r14, %rdi
    mov     %r13, %rsi
    mov     %r15, %rdx
    lea     (L + 56)(%rsp), %rcx
    call    lantern_is_valid_indexed_attestation
    CHECK_RESULT L, 7f, 8f
    cmpq    $0, (L + 56)(%rsp)
    je      5f
    cmp     S10(%rsp), %r13
    je      25f
    mov     S10(%rsp), %r13
    jmp     22b
25: mov     %r14, %rdi                      # [REJECT] a validator of the intersection is slashable
    lea     (L + 48)(%rsp), %rsi
    call    lantern_get_current_epoch
    xor     %r13d, %r13d
26: mov     (L + 32)(%rsp), %rax
    cmp     LIST_COUNT(%rax), %r13
    jae     5f
    mov     LIST_FIXED(%rax,%r13,8), %rax
    VALIDATOR_AT %rdi, %r14, %rax, 5f
    lea     (L + 48)(%rsp), %rsi
    lea     (L + 56)(%rsp), %rdx
    call    lantern_is_slashable_validator
    inc     %r13
    cmpq    $0, (L + 56)(%rsp)
    je      26b
    mov     %rbx, %rdi                      # seen.attester_slashing_indices.update(slashable_indices)
    call    seen_key_room
    cmp     (L + 40)(%rsp), %rax
    jb      9f
    xor     %r13d, %r13d
27: mov     (L + 32)(%rsp), %rax
    cmp     LIST_COUNT(%rax), %r13
    jae     8f
    mov     %rbx, %rdi
    mov     $SEEN_ATTESTER_SLASHING, %esi
    mov     LIST_FIXED(%rax,%r13,8), %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     28f
    mov     (L + 32)(%rsp), %rax
    mov     %rbx, %rdi
    mov     $SEEN_ATTESTER_SLASHING, %esi
    mov     LIST_FIXED(%rax,%r13,8), %rdx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    seen_add_key
28: inc     %r13
    jmp     27b
    GOSSIP_TAIL L, 64
SPEC_END validate_attester_slashing_gossip

/* ---------------------------------------------------------------- Gossip: blocks and columns */

/*
 * rbx seen, rbp store, r12 signed block, r13 current_time_ms, r14 head state, r15 block; S9 proposer state,
 * S10 parent node. Locals: L result, L+8 scratch, L+16 blob parameters (16), L+32 expected proposer,
 * L+40 epoch, L+48 time, L+56 parent payload status, L+64 a predicate, L+72 bellatrix: the justified state.
 */
SPEC_FUNCTION validate_beacon_block_gossip
    ENTER 80
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     %r8, %r14
    mov     %r9, S9(%rsp)
.if FORK == FORK_BELLATRIX
    mov     (80 + 96)(%rsp), %rax           # bellatrix: the seventh to ninth arguments, the justified state first
    mov     %rax, (L + 72)(%rsp)
    mov     (80 + 96 + 8)(%rsp), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     (80 + 96 + 16)(%rsp), %rax
.else
    mov     (80 + 96)(%rsp), %rax           # the seventh and eighth arguments
    mov     %rax, (L + 8)(%rsp)
    mov     (80 + 96 + 8)(%rsp), %rax
.endif
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    mov     (L + 8)(%rsp), %rax
.if FORK >= FORK_FULU
    NEED_SCRATCH %rax, %r14, 0, 9f
.else
    mov     S9(%rsp), %rcx
    NEED_SCRATCH %rax, %rcx, 2, 9f          # get_beacon_proposer_index of the proposer state takes S(2)
.endif
    PART    %r15, %rax, %r12, SignedBeaconBlock_message
    mov     %rbx, %rdi                      # [IGNORE] the first block for (slot, proposer)
    mov     $SEEN_PROPOSER_SLOT, %esi
    mov     BeaconBlock_slot(%r15), %rdx
    mov     BeaconBlock_proposer_index(%r15), %rcx
    xor     %r8d, %r8d
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] not from a future slot
    mov     BeaconBlock_slot(%r15), %rsi
    mov     %r13, %rdx
    call    is_future_slot
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] after the finalized slot
    call    finalized_slot
    cmp     %rax, BeaconBlock_slot(%r15)
    jbe     4f
    mov     %rbp, %rdi                      # [IGNORE] the parent has been seen
    mov     %rbx, %rsi
    lea     BeaconBlock_parent_root(%r15), %rdx
    call    block_lookup
    test    %rdx, %rdx
    jz      4f
    mov     %rax, S10(%rsp)
    cmp     $2, %rdx
    je      1f
.if FORK >= FORK_CAPELLA
    cmp     $PAYLOAD_STATUS_NOT_VALIDATED, %rcx     # no post-state: [REJECT] with an optimistic payload, else [IGNORE]
    je      5f
    jmp     4f
.elseif FORK == FORK_BELLATRIX
    mov     %rcx, (L + 56)(%rsp)
    mov     (L + 72)(%rsp), %rdi            # no post-state: is_execution_enabled(justified checkpoint state, block.body)
    PART    %rsi, %rax, %r15, BeaconBlock_body
    lea     (L + 64)(%rsp), %rdx
    call    lantern_is_execution_enabled
    cmpq    $0, (L + 64)(%rsp)
    je      5f                              # [REJECT] the parent failed validation, execution not enabled
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, (L + 56)(%rsp)   # [REJECT] with an optimistic payload, else [IGNORE]
    je      5f
    jmp     4f
.else
    jmp     5f                              # [REJECT] the parent failed validation
.endif
1:
.if FORK >= FORK_CAPELLA
    cmp     $PAYLOAD_STATUS_INVALIDATED, %rcx       # [IGNORE] the parent's payload is invalid
    je      4f
.elseif FORK == FORK_BELLATRIX
    mov     %rcx, (L + 56)(%rsp)            # parent_payload_status, for the payload checks
.endif
    mov     BeaconBlock_proposer_index(%r15), %rax  # [REJECT] the proposer index is valid
    VALIDATOR_AT %r9, %r14, %rax, 5f
    lea     SignedBeaconBlock_signature(%r12), %rax # [REJECT] the proposer signature
    mov     %rax, S7(%rsp)
    mov     (L + 8)(%rsp), %rax
    mov     %rax, S8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_BEACON_PROPOSER, %esi
    mov     BeaconBlock_slot(%r15), %rdx
    shr     $LOG2_SLOTS_PER_EPOCH, %rdx
    ADDRESS %rcx, lantern_type_BeaconBlock
    mov     %r15, %r8
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
.if FORK == FORK_BELLATRIX
    mov     %r14, %rdi                      # if is_execution_enabled(state, block.body):
    PART    %rsi, %rax, %r15, BeaconBlock_body
    lea     (L + 64)(%rsp), %rdx
    call    lantern_is_execution_enabled
    cmpq    $0, (L + 64)(%rsp)
    je      2f
.endif
.if FORK >= FORK_BELLATRIX
    lea     BeaconState_genesis_time(%r14), %rdi    # [REJECT] the payload timestamp is compute_time_at_slot
    lea     BeaconBlock_slot(%r15), %rsi
    lea     Store_config(%rbp), %rdx
    lea     (L + 48)(%rsp), %rcx
    call    lantern_compute_time_at_slot
    CHECK_RESULT L, 7f, 8f
    PART    %rax, %rcx, %r15, BeaconBlock_body
    PART    %rdx, %rcx, %rax, BeaconBlockBody_execution_payload
    mov     ExecutionPayload_timestamp(%rdx), %rax
    cmp     (L + 48)(%rsp), %rax
    jne     5f
.endif
.if FORK == FORK_BELLATRIX
    cmpq    $PAYLOAD_STATUS_INVALIDATED, (L + 56)(%rsp)    # [IGNORE] the parent passed validation but its payload is invalid
    je      4f
2:
.endif
    mov     S10(%rsp), %rax                 # [REJECT] a higher slot than the parent
    NODE    %rcx, %rbp, %rax
    mov     BlockNode_slot(%rcx), %rax
    cmp     %rax, BeaconBlock_slot(%r15)
    jbe     5f
    mov     %rbp, %rdi                      # [REJECT] the finalized checkpoint is an ancestor
    mov     S10(%rsp), %rsi
    call    finalized_is_ancestor
    CHECK_RESULT L, 7f, 8f
    test    %rdx, %rdx
    jz      5f
.if FORK >= FORK_FULU
    mov     BeaconBlock_slot(%r15), %rax    # [REJECT] at most max_blobs_per_block commitments
    shr     $LOG2_SLOTS_PER_EPOCH, %rax
    mov     %rax, (L + 40)(%rsp)
    lea     (L + 40)(%rsp), %rdi
    lea     Store_config(%rbp), %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_get_blob_parameters
.elseif FORK == FORK_ELECTRA
    mov     (Store_config + CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA)(%rbp), %rax     # [REJECT] at most MAX_BLOBS_PER_BLOCK_ELECTRA commitments
    mov     %rax, (L + 24)(%rsp)
.elseif FORK == FORK_DENEB
    mov     (Store_config + CONFIG_MAX_BLOBS_PER_BLOCK)(%rbp), %rax             # [REJECT] at most MAX_BLOBS_PER_BLOCK commitments
    mov     %rax, (L + 24)(%rsp)
.endif
.if FORK >= FORK_DENEB
    PART    %rax, %rcx, %r15, BeaconBlock_body
    mov     (BeaconBlockBody_blob_kzg_commitments + 8)(%rax), %rax
    cmp     (L + 24)(%rsp), %rax
    ja      5f
.endif
    mov     S9(%rsp), %rdi                  # [REJECT] the expected proposer of the parent state at the slot
.if FORK >= FORK_FULU
    lea     (L + 32)(%rsp), %rsi
.else
    mov     (L + 8)(%rsp), %rsi
    lea     (L + 32)(%rsp), %rdx
.endif
    call    lantern_get_beacon_proposer_index
    CHECK_RESULT L, 7f, 8f
    mov     (L + 32)(%rsp), %rax
    cmp     BeaconBlock_proposer_index(%r15), %rax
    jne     5f
    mov     %rbx, %rdi                      # seen.proposer_slots.add(...)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     %rbx, %rdi
    mov     $SEEN_PROPOSER_SLOT, %esi
    mov     BeaconBlock_slot(%r15), %rdx
    mov     BeaconBlock_proposer_index(%r15), %rcx
    xor     %r8d, %r8d
    call    seen_add_key
    jmp     8f
    GOSSIP_TAIL L, 80
SPEC_END validate_beacon_block_gossip

/* ---------------------------------------------------------------- Columns */

.if FORK >= FORK_FULU
/*
 * get_subtree_index(get_generalized_index(BeaconBlockBody, "blob_kzg_commitments")): field 11 of the 13 fields
 * of BeaconBlockBody, whose tree has 16 leaves, so the generalized index is 16 + 11 = 27 and the subtree index 11.
 */
.set BLOB_KZG_COMMITMENTS_SUBTREE_INDEX, 11
.if KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH != 4
.error "the subtree index of blob_kzg_commitments assumes a body of 13 fields"
.endif

SPEC_LEAF compute_subnet_for_data_column_sidecar
    mov     CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT(%rsi), %rcx
    test    %rcx, %rcx
    jz      9f
    mov     %rdx, %r8
    mov     (%rdi), %rax
    xor     %edx, %edx
    div     %rcx
    mov     %rdx, (%r8)
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_subnet_for_data_column_sidecar

/*
 * L0: rax = status, rdx = is_valid_merkle_branch(hash_tree_root of the rdx commitments at rsi, the branch at rcx,
 * KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH, BLOB_KZG_COMMITMENTS_SUBTREE_INDEX, the root at r8), with scratch rdi.
 * The list is hashed from a standalone copy at the end of scratch.
 * rbx scratch, rbp branch, r12 root, r13 i. Locals: L value (32), L+32 the two halves (64).
 */
LOCAL_FUNCTION commitments_in_body
    ENTER 96
    mov     %rdi, %rbx
    mov     %rcx, %rbp
    mov     %r8, %r12
    imul    $48, %rdx, %rax                 # the list: size, offset 24, count, the commitments
    add     $(LIST_FIXED + 7), %rax
    and     $-8, %rax
    MOVQ    %rcx, LANTERN_SCRATCH_FIXED
    add     %rax, %rcx
    cmp     %rcx, (%rbx)
    jb      9f
    mov     (%rbx), %rcx
    sub     %rax, %rcx
    lea     (%rbx,%rcx), %rdi
    mov     %rcx, (%rbx)                    # asm-ssz's scratch: the front
    mov     %rax, (%rdi)
    movq    $LIST_FIXED, 8(%rdi)
    mov     %rdx, 16(%rdi)
    mov     %rdi, (L + 32)(%rsp)
    add     $LIST_FIXED, %rdi
    imul    $48, %rdx, %rdx
    call    lantern_copy
    ADDRESS %rdi, lantern_type_BlobKZGCommitments   # value = hash_tree_root(kzg_commitments)
    mov     (L + 32)(%rsp), %rsi
    mov     %rbx, %rdx
    lea     L(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    xor     %r13d, %r13d
1:  cmp     $KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH, %r13
    jae     3f
    mov     %r13, %rax                      # branch[i]
    shl     $5, %rax
    add     %rbp, %rax
    lea     (L + 32)(%rsp), %rdi
    lea     L(%rsp), %rsi
    mov     $BLOB_KZG_COMMITMENTS_SUBTREE_INDEX, %ecx
    bt      %r13, %rcx
    jnc     2f
    COPY32  %rdi, %rax                      # index bit set: hash(branch[i] + value)
    add     $32, %rdi
    COPY32  %rdi, %rsi
    jmp     21f
2:  COPY32  %rdi, %rsi                      # else hash(value + branch[i])
    add     $32, %rdi
    COPY32  %rdi, %rax
21: lea     (L + 32)(%rsp), %rdi
    mov     $64, %esi
    lea     L(%rsp), %rdx
    call    sha256_short
    inc     %r13
    jmp     1b
3:  lea     L(%rsp), %rax                   # value == root
    xor     %edx, %edx
    NE32    %rax, %r12, 6f
    mov     $1, %edx
6:  xor     %eax, %eax
7:  LEAVE 96
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 96
END_FUNCTION commitments_in_body

/* Locals: rsp+0 out. */
SPEC_FUNCTION verify_data_column_sidecar_inclusion_proof
    FRAME 16
    mov     %rdx, 0(%rsp)
    movq    $0, (%rdx)
    mov     %rdi, %rax
    mov     %rsi, %rdi
    PART    %rsi, %rdx, %rax, DataColumnSidecar_kzg_commitments
    lea     DataColumnSidecar_kzg_commitments_inclusion_proof(%rax), %rcx
    lea     (DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root)(%rax), %r8
    call    commitments_in_body
    test    %rax, %rax
    jnz     7f
    mov     0(%rsp), %rcx
    mov     %rdx, (%rcx)
7:  UNFRAME 16
SPEC_END verify_data_column_sidecar_inclusion_proof

/* Locals: rsp+0 out. */
SPEC_FUNCTION verify_partial_data_column_header_inclusion_proof
    FRAME 16
    mov     %rdx, 0(%rsp)
    movq    $0, (%rdx)
    mov     %rdi, %rax
    mov     %rsi, %rdi
    PART    %rsi, %rdx, %rax, PartialDataColumnHeader_kzg_commitments
    lea     PartialDataColumnHeader_kzg_commitments_inclusion_proof(%rax), %rcx
    lea     (PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root)(%rax), %r8
    call    commitments_in_body
    test    %rax, %rax
    jnz     7f
    mov     0(%rsp), %rcx
    mov     %rdx, (%rcx)
7:  UNFRAME 16
SPEC_END verify_partial_data_column_header_inclusion_proof

/* dst = the set bits of the BitList at PartRef ref of value v. Uses rax, rcx, rdx, r10. dst and v are not those. */
.macro BIT_COUNT dst, v, ref
    PART    %r10, %rcx, \v, \ref
    xor     \dst, \dst
    xor     %eax, %eax
96: cmp     %rcx, %rax
    jae     97f
    xor     %edx, %edx
    bt      %rax, (%r10)
    adc     $0, \dst
    inc     %rax
    jmp     96b
97:
.endm

/*
 * rbx sidecar, rbp settings, r12 scratch, r13 out, r14 n, r15 scratch size left;
 * S7 the seventh argument of the KZG call, S8 commitments, S9 cell indices, S10 cells,
 * L proofs, L+8 valid, L+16 header, L+24 column index.
 */
SPEC_FUNCTION verify_partial_data_column_sidecar_kzg_proofs
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, (L + 16)(%rsp)
    mov     (%rdx), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     %rcx, %rbp
    mov     %r8, %r12
    mov     %r9, %r13
    movq    $0, (%r13)
    BIT_COUNT %r14, %rbx, PartialDataColumnSidecar_cells_present_bitmap    # blob_indices: the set bits
    cmp     %r14, (PartialDataColumnSidecar_partial_column + 8)(%rbx)  # one cell and one proof per index, as the batch asserts
    jne     8f
    cmp     %r14, (PartialDataColumnSidecar_kzg_proofs + 8)(%rbx)
    jne     8f
    mov     %r14, %rax
    MOVQ    %rcx, DA_SCRATCH_PER_BLOB
    mul     %rcx
    jc      9f
    MOVQ    %rcx, DA_SCRATCH_FIXED
    add     %rcx, %rax
    jc      9f
    mov     (%r12), %r15
    cmp     %rax, %r15
    jb      9f
    DA_LIST S8, 48                          # commitments_bytes = [all_commitments[index] for index in blob_indices]
    DA_LIST S9, 8                           # cell_indices = [column_index] * len(blob_indices)
    DA_LIST S10, CRYPTO_KZG_CELL_SIZE       # cells = sidecar.partial_column
    DA_LIST L, 48                           # proofs_bytes = sidecar.kzg_proofs
    mov     (L + 16)(%rsp), %rax
    PART    %rsi, %r8, %rax, PartialDataColumnHeader_kzg_commitments
    PART    %r10, %r9, %rbx, PartialDataColumnSidecar_cells_present_bitmap
    mov     S8(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    xor     %ecx, %ecx
1:  cmp     %r9, %rcx
    jae     2f
    bt      %rcx, (%r10)
    jnc     11f
    cmp     %r8, %rcx                       # an index past the commitments: the spec's indexing raises
    jae     8f
    imul    $48, %rcx, %rax
    movdqu  (%rsi,%rax), %xmm0
    movdqu  16(%rsi,%rax), %xmm1
    movdqu  32(%rsi,%rax), %xmm2
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm1, 16(%rdi)
    movdqu  %xmm2, 32(%rdi)
    add     $48, %rdi
11: inc     %rcx
    jmp     1b
2:  mov     (L + 24)(%rsp), %rax
    mov     S9(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    mov     %r14, %rcx
    rep stosq
    mov     S10(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    PART    %rsi, %rdx, %rbx, PartialDataColumnSidecar_partial_column
    shl     $11, %rdx
    call    lantern_copy
    mov     L(%rsp), %rdi
    add     $LIST_FIXED, %rdi
    PART    %rsi, %rdx, %rbx, PartialDataColumnSidecar_kzg_proofs
    imul    $48, %rdx, %rdx
    call    lantern_copy
    mov     %r15, (%r12)                    # asm-crypto's scratch: the front
    mov     %rbp, %rdi
    mov     S8(%rsp), %rsi
    mov     S9(%rsp), %rdx
    mov     S10(%rsp), %rcx
    mov     L(%rsp), %r8
    mov     %r12, %r9
    lea     (L + 8)(%rsp), %rax             # valid, the seventh argument, on the stack
    mov     %rax, S7(%rsp)
    CALL_GLOBAL crypto_kzg_verify_cell_kzg_proof_batch
    cmp     $CRYPTO_BUFFER_TOO_SMALL, %rax
    je      9f
    test    %rax, %rax
    jnz     8f                              # an input that does not decode: the spec raises
    mov     (L + 8)(%rsp), %rax
    mov     %rax, (%r13)
8:  xor     %eax, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
SPEC_END verify_partial_data_column_sidecar_kzg_proofs

.endif

.if FORK >= FORK_DENEB
/*
 * L0: the checks of a block header shared by the sidecar topics, from is_future_slot to the finalized ancestor:
 * rax = status, rdx = LANTERN_VALID, LANTERN_GOSSIP_IGNORE or LANTERN_GOSSIP_REJECT, rcx = the parent node.
 * Takes rbx seen, rbp store, r13 current_time_ms, r14 head state, r15 scratch, and rdi the SignedBeaconBlockHeader.
 * rbx-r15 are the caller's and stay unchanged. Locals: rsp+0 and rsp+8 the stack arguments of verify_signed,
 * rsp+16 header, rsp+24 parent node.
 */
LOCAL_FUNCTION header_checks
    FRAME 32
    mov     %rdi, 16(%rsp)
    mov     %rbp, %rdi                      # [IGNORE] not from a future slot
    mov     16(%rsp), %rax
    mov     (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rax), %rsi
    mov     %r13, %rdx
    call    is_future_slot
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] after the finalized slot
    call    finalized_slot
    mov     16(%rsp), %rcx
    cmp     %rax, (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rcx)
    jbe     4f
    mov     %rbp, %rdi                      # [IGNORE] the parent has been seen; [REJECT] it passed validation
    mov     %rbx, %rsi
    mov     16(%rsp), %rdx
    add     $(SignedBeaconBlockHeader_message + BeaconBlockHeader_parent_root), %rdx
    call    block_lookup
    test    %rdx, %rdx
    jz      4f
    cmp     $2, %rdx
    jne     5f
    mov     %rax, 24(%rsp)
    mov     16(%rsp), %rax                  # [REJECT] the proposer index is valid
    mov     (SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)(%rax), %rax
    VALIDATOR_AT %r9, %r14, %rax, 5f
    mov     16(%rsp), %r8                   # [REJECT] the proposer signature of the header
    lea     SignedBeaconBlockHeader_signature(%r8), %rax
    mov     %rax, 0(%rsp)
    mov     %r15, 8(%rsp)
    mov     %r14, %rdi
    mov     $DOMAIN_BEACON_PROPOSER, %esi
    mov     (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%r8), %rdx
    shr     $LOG2_SLOTS_PER_EPOCH, %rdx
    ADDRESS %rcx, lantern_type_BeaconBlockHeader
    add     $SignedBeaconBlockHeader_message, %r8
    add     $Validator_pubkey, %r9
    call    verify_signed
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      5f
    mov     24(%rsp), %rax                  # [REJECT] a higher slot than the parent
    NODE    %rcx, %rbp, %rax
    mov     BlockNode_slot(%rcx), %rax
    mov     16(%rsp), %rcx
    cmp     %rax, (SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rcx)
    jbe     5f
    mov     %rbp, %rdi                      # [REJECT] the finalized checkpoint is an ancestor
    mov     24(%rsp), %rsi
    call    finalized_is_ancestor
    test    %rax, %rax
    jnz     6f
    test    %rdx, %rdx
    jz      5f
    mov     $LANTERN_VALID, %edx
    jmp     8f
4:  mov     $LANTERN_GOSSIP_IGNORE, %edx
    jmp     8f
5:  mov     $LANTERN_GOSSIP_REJECT, %edx
8:  mov     24(%rsp), %rcx
    xor     %eax, %eax
7:  UNFRAME 32
6:  cmp     $LANTERN_BUFFER_TOO_SMALL, %rax # a spec failure: its code as the outcome
    je      7b
    mov     %rax, %rdx
    jmp     8b
END_FUNCTION header_checks
.endif

/* ---------------------------------------------------------------- Blob sidecars */

.if FORK == FORK_DENEB || FORK == FORK_ELECTRA
.if FORK == FORK_ELECTRA
.set BLOB_SUBNETS, CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA
.set BLOB_LIMIT, CONFIG_MAX_BLOBS_PER_BLOCK_ELECTRA
.else
.set BLOB_SUBNETS, CONFIG_BLOB_SIDECAR_SUBNET_COUNT
.set BLOB_LIMIT, CONFIG_MAX_BLOBS_PER_BLOCK
.endif

/* (blob_index, config, out): blob_index % BLOB_SIDECAR_SUBNET_COUNT, _ELECTRA from electra on. */
SPEC_LEAF compute_subnet_for_blob_sidecar
    mov     BLOB_SUBNETS(%rsi), %rcx
    test    %rcx, %rcx
    jz      9f
    mov     (%rdi), %rax
    mov     %rdx, %r8
    xor     %edx, %edx
    div     %rcx
    mov     %rdx, (%r8)
    RETURN_OK
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
SPEC_END compute_subnet_for_blob_sidecar

/*
 * (sidecar, out): is_valid_merkle_branch of hash_tree_root(kzg_commitment) at the subtree index of
 * blob_kzg_commitments[index] against the header's body_root. rbx sidecar, rbp out.
 * Locals: L the commitment as two chunks (64), L+64 its root (32), L+96 depth, L+104 index.
 */
SPEC_FUNCTION verify_blob_sidecar_inclusion_proof
    ENTER 112
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    lea     L(%rsp), %rdi
    mov     $64, %esi
    call    lantern_zero
    lea     L(%rsp), %rdi
    lea     BlobSidecar_kzg_commitment(%rbx), %rsi
    mov     $48, %edx
    call    lantern_copy
    lea     L(%rsp), %rdi                   # hash_tree_root(Bytes48): its two chunks
    mov     $64, %esi
    lea     (L + 64)(%rsp), %rdx
    call    sha256_short
    movq    $KZG_COMMITMENT_INCLUSION_PROOF_DEPTH, (L + 96)(%rsp)
    mov     BlobSidecar_index(%rbx), %rax   # field 11 of the body, the list's data root, then the index
    add     $(11 << (KZG_COMMITMENT_INCLUSION_PROOF_DEPTH - 4)), %rax
    mov     %rax, (L + 104)(%rsp)
    lea     (L + 64)(%rsp), %rdi
    lea     BlobSidecar_kzg_commitment_inclusion_proof(%rbx), %rsi
    lea     (L + 96)(%rsp), %rdx
    lea     (L + 104)(%rsp), %rcx
    lea     (BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_body_root)(%rbx), %r8
    mov     %rbp, %r9
    call    lantern_is_valid_merkle_branch
    LEAVE 112
SPEC_END verify_blob_sidecar_inclusion_proof
.if (1 << (KZG_COMMITMENT_INCLUSION_PROOF_DEPTH - 5)) != MAX_BLOB_COMMITMENTS_PER_BLOCK
.error "verify_blob_sidecar_inclusion_proof assumes a body of 16 leaves and a list of MAX_BLOB_COMMITMENTS_PER_BLOCK"
.endif

/*
 * rbx seen, rbp store, r12 sidecar, r13 current_time_ms, r14 head state, r15 scratch; S9 the block header,
 * S10 scratch size. Locals: L result, L+8 subnet_id, L+16 proposer state, L+24 settings, L+32 out,
 * L+40 expected proposer.
 */
SPEC_FUNCTION validate_blob_sidecar_gossip
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     (%r8), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     %r9, %r14
    mov     (48 + 96)(%rsp), %rax           # the seventh to tenth arguments
    mov     %rax, (L + 16)(%rsp)
    mov     (48 + 96 + 8)(%rsp), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     (48 + 96 + 16)(%rsp), %r15
    mov     (48 + 96 + 24)(%rsp), %rax
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    mov     (L + 16)(%rsp), %rcx
    NEED_SCRATCH %r15, %rcx, 2, 9f          # get_beacon_proposer_index of the proposer state takes S(2)
    mov     (%r15), %rax
    mov     %rax, S10(%rsp)
    lea     (BlobSidecar_signed_block_header + SignedBeaconBlockHeader_message)(%r12), %rax
    mov     %rax, S9(%rsp)
    mov     %rbx, %rdi                      # [IGNORE] the first sidecar for (slot, proposer, index)
    mov     $SEEN_BLOB_SIDECAR, %esi
    mov     BeaconBlockHeader_slot(%rax), %rdx
    mov     BeaconBlockHeader_proposer_index(%rax), %rcx
    mov     BlobSidecar_index(%r12), %r8
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     BlobSidecar_index(%r12), %rax   # [REJECT] the index is below the blob limit
    cmp     (Store_config + BLOB_LIMIT)(%rbp), %rax
    jae     5f
    lea     BlobSidecar_index(%r12), %rdi   # [REJECT] the subnet: compute_subnet_for_blob_sidecar
    lea     Store_config(%rbp), %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_compute_subnet_for_blob_sidecar
    CHECK_RESULT L, 7f, 8f
    mov     (L + 8)(%rsp), %rax
    cmp     (L + 32)(%rsp), %rax
    jne     5f
    lea     BlobSidecar_signed_block_header(%r12), %rdi     # the header checks, through the finalized ancestor
    call    header_checks
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      1f
    mov     %rdx, %rax
    jmp     6f
1:  mov     %r12, %rdi                      # [REJECT] verify_blob_sidecar_inclusion_proof
    lea     (L + 32)(%rsp), %rsi
    call    lantern_verify_blob_sidecar_inclusion_proof
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (L + 32)(%rsp)
    je      5f
    mov     S10(%rsp), %rax                 # [REJECT] verify_blob_kzg_proof(blob, kzg_commitment, kzg_proof)
    mov     %rax, (%r15)
    mov     (L + 24)(%rsp), %rdi
    lea     BlobSidecar_blob(%r12), %rsi
    lea     BlobSidecar_kzg_commitment(%r12), %rdx
    lea     BlobSidecar_kzg_proof(%r12), %rcx
    mov     %r15, %r8
    lea     (L + 32)(%rsp), %r9
    CALL_GLOBAL crypto_kzg_verify_blob_kzg_proof
    cmp     $CRYPTO_BUFFER_TOO_SMALL, %rax
    je      9f
    test    %rax, %rax                      # an input that does not decode: the spec's exception
    jnz     5f
    cmpq    $0, (L + 32)(%rsp)
    je      5f
    mov     S10(%rsp), %rax                 # [REJECT] the expected proposer of the parent state at the slot
    mov     %rax, (%r15)
    mov     (L + 16)(%rsp), %rdi
    mov     %r15, %rsi
    lea     (L + 40)(%rsp), %rdx
    call    lantern_get_beacon_proposer_index
    CHECK_RESULT L, 7f, 8f
    mov     S9(%rsp), %rcx
    mov     (L + 40)(%rsp), %rax
    cmp     BeaconBlockHeader_proposer_index(%rcx), %rax
    jne     5f
    mov     %rbx, %rdi                      # seen.blob_sidecar_tuples.add(...)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     S9(%rsp), %rax
    mov     %rbx, %rdi
    mov     $SEEN_BLOB_SIDECAR, %esi
    mov     BeaconBlockHeader_slot(%rax), %rdx
    mov     BeaconBlockHeader_proposer_index(%rax), %rcx
    mov     BlobSidecar_index(%r12), %r8
    call    seen_add_key
    jmp     8f
    GOSSIP_TAIL L, 48
SPEC_END validate_blob_sidecar_gossip
.endif

.if FORK >= FORK_FULU

/*
 * rbx seen, rbp store, r12 sidecar, r13 current_time_ms, r14 head state, r15 scratch; S9 the block header,
 * S10 parent node. Locals: L result, L+8 subnet_id, L+16 proposer state, L+24 settings, L+32 out,
 * L+40 expected proposer.
 */
SPEC_FUNCTION validate_data_column_sidecar_gossip
    ENTER 48
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     (%r8), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     %r9, %r14
    mov     (48 + 96)(%rsp), %rax           # the seventh to tenth arguments
    mov     %rax, (L + 16)(%rsp)
    mov     (48 + 96 + 8)(%rsp), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     (48 + 96 + 16)(%rsp), %r15
    mov     (48 + 96 + 24)(%rsp), %rax
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH %r15, %r14, 0, 9f
    lea     (DataColumnSidecar_signed_block_header + SignedBeaconBlockHeader_message)(%r12), %rax
    mov     %rax, S9(%rsp)
    mov     %rbx, %rdi                      # [IGNORE] the first sidecar for (slot, proposer, index)
    mov     $SEEN_DATA_COLUMN, %esi
    mov     BeaconBlockHeader_slot(%rax), %rdx
    mov     BeaconBlockHeader_proposer_index(%rax), %rcx
    mov     DataColumnSidecar_index(%r12), %r8
    call    seen_find_key
    test    %rax, %rax
    jnz     4f
    mov     %r12, %rdi                      # [REJECT] verify_data_column_sidecar
    lea     Store_config(%rbp), %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_verify_data_column_sidecar
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (L + 32)(%rsp)
    je      5f
    lea     DataColumnSidecar_index(%r12), %rdi     # [REJECT] the subnet: compute_subnet_for_data_column_sidecar
    lea     Store_config(%rbp), %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_compute_subnet_for_data_column_sidecar
    CHECK_RESULT L, 7f, 8f
    mov     (L + 8)(%rsp), %rax
    cmp     (L + 32)(%rsp), %rax
    jne     5f
    lea     DataColumnSidecar_signed_block_header(%r12), %rdi   # the header checks, through the finalized ancestor
    call    header_checks
    test    %rax, %rax
    jnz     7f
    mov     %rcx, S10(%rsp)
    test    %rdx, %rdx
    jz      1f
    mov     %rdx, %rax
    jmp     6f
1:  mov     %r12, %rdi                      # [REJECT] verify_data_column_sidecar_inclusion_proof
    mov     %r15, %rsi
    lea     (L + 32)(%rsp), %rdx
    call    lantern_verify_data_column_sidecar_inclusion_proof
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (L + 32)(%rsp)
    je      5f
    mov     %r12, %rdi                      # [REJECT] verify_data_column_sidecar_kzg_proofs
    mov     (L + 24)(%rsp), %rsi
    mov     %r15, %rdx
    lea     (L + 32)(%rsp), %rcx
    call    lantern_verify_data_column_sidecar_kzg_proofs
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (L + 32)(%rsp)
    je      5f
    mov     (L + 16)(%rsp), %rdi            # [REJECT] the expected proposer of the parent state at the slot
    lea     (L + 40)(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
    CHECK_RESULT L, 7f, 8f
    mov     S9(%rsp), %rcx
    mov     (L + 40)(%rsp), %rax
    cmp     BeaconBlockHeader_proposer_index(%rcx), %rax
    jne     5f
    mov     %rbx, %rdi                      # seen.data_column_sidecar_tuples.add(...)
    call    seen_key_room
    test    %rax, %rax
    jz      9f
    mov     S9(%rsp), %rax
    mov     %rbx, %rdi
    mov     $SEEN_DATA_COLUMN, %esi
    mov     BeaconBlockHeader_slot(%rax), %rdx
    mov     BeaconBlockHeader_proposer_index(%rax), %rcx
    mov     DataColumnSidecar_index(%r12), %r8
    call    seen_add_key
    jmp     8f
    GOSSIP_TAIL L, 48
SPEC_END validate_data_column_sidecar_gossip

/*
 * rbx seen, rbp store, r12 sidecar, r13 current_time_ms, r14 head state, r15 scratch; S9 the header value, or 0,
 * S10 the cells present. Locals: L result, L+8 group_id, L+16 column_index, L+24 proposer state, L+32 settings,
 * L+40 out, L+48 header root (32), L+80 expected proposer, L+88 the block header root (32).
 */
SPEC_FUNCTION validate_partial_data_column_sidecar_gossip
    ENTER 128
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     (%rcx), %r13
    mov     %r8, (L + 8)(%rsp)
    mov     (%r9), %rax
    mov     %rax, (L + 16)(%rsp)
    mov     (128 + 96)(%rsp), %r14          # the seventh to eleventh arguments
    mov     (128 + 96 + 8)(%rsp), %rax
    mov     %rax, (L + 24)(%rsp)
    mov     (128 + 96 + 16)(%rsp), %rax
    mov     %rax, (L + 32)(%rsp)
    mov     (128 + 96 + 24)(%rsp), %r15
    mov     (128 + 96 + 32)(%rsp), %rax
    mov     %rax, L(%rsp)
    movq    $0, (%rax)
    NEED_SCRATCH %r15, %r14, 0, 9f
    movq    $0, S9(%rsp)                    # has_header: the optional header holds one
    cmpq    $0, (PartialDataColumnSidecar_header + 8)(%r12)
    je      1f
    mov     PartialDataColumnSidecar_header(%r12), %rax
    add     %r12, %rax
    mov     %rax, S9(%rsp)
1:  BIT_COUNT %rsi, %r12, PartialDataColumnSidecar_cells_present_bitmap
    mov     %rsi, S10(%rsp)
    or      S9(%rsp), %rsi                  # [REJECT] a header and/or cells are present
    jz      5f
    mov     S10(%rsp), %rax
    cmp     %rax, (PartialDataColumnSidecar_partial_column + 8)(%r12)  # [REJECT] one cell per set bit
    jne     5f
    cmp     %rax, (PartialDataColumnSidecar_kzg_proofs + 8)(%r12)  # [REJECT] one proof per set bit
    jne     5f
    cmpq    $0, S9(%rsp)
    je      3f
    ADDRESS %rdi, lantern_type_PartialDataColumnHeader  # [REJECT] the header equals a prior validated header
    mov     S9(%rsp), %rsi
    mov     %r15, %rdx
    lea     (L + 48)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    mov     %rbx, %rdi
    mov     (L + 8)(%rsp), %rsi
    call    seen_find_header
    test    %rax, %rax
    jz      2f
    add     $SeenHeader_header_root, %rax
    lea     (L + 48)(%rsp), %rcx
    NE32    %rax, %rcx, 5f
2:  ADDRESS %rdi, lantern_type_BeaconBlockHeader        # [REJECT] the block header's root is the group id
    mov     S9(%rsp), %rsi
    add     $(PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message), %rsi
    mov     %r15, %rdx
    lea     (L + 88)(%rsp), %rcx
    CALL_GLOBAL ssz_hash_tree_root
    test    %rax, %rax
    jnz     7f
    lea     (L + 88)(%rsp), %rax
    mov     (L + 8)(%rsp), %rcx
    NE32    %rax, %rcx, 5f
    mov     S9(%rsp), %rax
    cmpq    $0, (PartialDataColumnHeader_kzg_commitments + 8)(%rax)    # [REJECT] the header has commitments
    je      5f
    lea     PartialDataColumnHeader_signed_block_header(%rax), %rdi    # the header checks, through the finalized ancestor
    call    header_checks
    test    %rax, %rax
    jnz     7f
    test    %rdx, %rdx
    jz      21f
    mov     %rdx, %rax
    jmp     6f
21: mov     S9(%rsp), %rdi                  # [REJECT] verify_partial_data_column_header_inclusion_proof
    mov     %r15, %rsi
    lea     (L + 40)(%rsp), %rdx
    call    lantern_verify_partial_data_column_header_inclusion_proof
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (L + 40)(%rsp)
    je      5f
    mov     (L + 24)(%rsp), %rdi            # [REJECT] the expected proposer of the parent state at the slot
    lea     (L + 80)(%rsp), %rsi
    call    lantern_get_beacon_proposer_index
    CHECK_RESULT L, 7f, 8f
    mov     S9(%rsp), %rcx
    mov     (L + 80)(%rsp), %rax
    cmp     (PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_proposer_index)(%rcx), %rax
    jne     5f
    mov     %rbx, %rdi                      # seen.partial_data_column_headers[group_id.beacon_block_root] = header
    mov     (L + 8)(%rsp), %rsi
    call    seen_find_header
    test    %rax, %rax
    jnz     3f
    mov     S9(%rsp), %rsi                  # room for 64 + the header value
    mov     (%rsi), %rdx
    add     $SeenHeader_header, %rdx
    mov     (%rbx), %rax
    sub     Seen_headers(%rbx), %rax
    sub     Seen_header_bytes(%rbx), %rax
    cmp     %rdx, %rax
    jb      9f
    mov     Seen_headers(%rbx), %rdi
    add     Seen_header_bytes(%rbx), %rdi
    add     %rbx, %rdi
    add     %rdx, Seen_header_bytes(%rbx)
    incq    (Seen_headers + 8)(%rbx)
    mov     (L + 8)(%rsp), %rax
    COPY32  %rdi, %rax
    lea     SeenHeader_header_root(%rdi), %rax
    lea     (L + 48)(%rsp), %rcx
    COPY32  %rax, %rcx
    add     $SeenHeader_header, %rdi
    mov     (%rsi), %rdx
    call    lantern_copy
3:  cmpq    $0, S10(%rsp)                   # has_cells
    je      8f
    mov     %rbx, %rdi                      # [IGNORE] a valid header for the group has been seen
    mov     (L + 8)(%rsp), %rsi
    call    seen_find_header
    test    %rax, %rax
    jz      4f
    add     $SeenHeader_header, %rax
    mov     %rax, S9(%rsp)
    mov     %rbp, %rdi                      # [IGNORE] its slot is not in the future
    mov     (PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rax), %rsi
    mov     %r13, %rdx
    call    is_future_slot
    test    %rax, %rax
    jnz     4f
    mov     %rbp, %rdi                      # [IGNORE] its slot is after the finalized slot
    call    finalized_slot
    mov     S9(%rsp), %rcx
    cmp     %rax, (PartialDataColumnHeader_signed_block_header + SignedBeaconBlockHeader_message + BeaconBlockHeader_slot)(%rcx)
    jbe     4f
    mov     (PartialDataColumnSidecar_cells_present_bitmap + 8)(%r12), %rax    # [REJECT] one bit per commitment
    cmp     (PartialDataColumnHeader_kzg_commitments + 8)(%rcx), %rax
    jne     5f
    mov     %r12, %rdi                      # [REJECT] verify_partial_data_column_sidecar_kzg_proofs
    mov     S9(%rsp), %rsi
    lea     (L + 16)(%rsp), %rdx
    mov     (L + 32)(%rsp), %rcx
    mov     %r15, %r8
    lea     (L + 40)(%rsp), %r9
    call    lantern_verify_partial_data_column_sidecar_kzg_proofs
    test    %rax, %rax
    jnz     7f
    cmpq    $0, (L + 40)(%rsp)
    je      5f
    jmp     8f
    GOSSIP_TAIL L, 128
SPEC_END validate_partial_data_column_sidecar_gossip
.endif
