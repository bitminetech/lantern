/*
 * Beacon state buffers, x86-64. Requirements: docs/reference/state.md.
 */

/* Room of an ExecutionPayloadHeader value with the longest extra_data. */
.set HEADER_ROOM, (ExecutionPayloadHeader__fixed + MAX_EXTRA_DATA_BYTES + 7) / 8 * 8

/* The parts of a BeaconState, in field order: PartRef offset, entry stride, StateRoom offset or -1. */
.macro STATE_PARTS m
    \m BeaconState_historical_roots, Bytes32__mem, -1
    \m BeaconState_eth1_data_votes, Eth1Data__mem, 8
    \m BeaconState_validators, Validator__mem, 0
    \m BeaconState_balances, 8, 0
    \m BeaconState_previous_epoch_participation, 1, 0
    \m BeaconState_current_epoch_participation, 1, 0
    \m BeaconState_inactivity_scores, 8, 0
    \m BeaconState_latest_execution_payload_header, 0, -1
    \m BeaconState_historical_summaries, HistoricalSummary__mem, 16
    \m BeaconState_pending_deposits, PendingDeposit__mem, 24
    \m BeaconState_pending_partial_withdrawals, PendingPartialWithdrawal__mem, 32
    \m BeaconState_pending_consolidations, PendingConsolidation__mem, 40
.endm

/*
 * rax = the capacity a copy gives one part of state st with room rm: its entry
 * bytes plus room, rounded up to 8. Also rcx = its entry bytes, rdx = its count,
 * r8 = where its entries are.
 */
.macro PART_CAPACITY st, rm, ref, stride, room
    PART    %r8, %rdx, \st, \ref
    .if \stride
    imul    $(\stride), %rdx, %rcx
    .if (\room) >= 0
    imul    $(\stride), (\room)(\rm), %rax
    add     %rcx, %rax
    .else
    mov     %rcx, %rax
    .endif
    .else
    xor     %ecx, %ecx                      # a nested value: its size, when present
    test    %rdx, %rdx
    jz      91f
    mov     (%r8), %rcx
91: mov     $HEADER_ROOM, %eax
    cmp     %rax, %rcx
    jbe     92f
    mov     %rcx, %rax
92:
    .endif
    add     $7, %rax
    and     $-8, %rax
.endm

/* r9 += the capacity of one part of state rdi with room rsi. */
.macro SIZE_PART ref, stride, room
    PART_CAPACITY %rdi, %rsi, \ref, \stride, \room
    add     %rax, %r9
.endm

SPEC_LEAF beacon_state_copy_size
    mov     %rdx, %r10
    mov     $BeaconState__fixed, %r9d
    STATE_PARTS SIZE_PART
    mov     %r9, (%r10)
    RETURN_OK
SPEC_END beacon_state_copy_size

/* rbx state, rbp room, r12 out, r13 cursor. */
.macro COPY_PART ref, stride, room
    PART_CAPACITY %rbx, %rbp, \ref, \stride, \room
    mov     %r13, (\ref)(%r12)              # out's PartRef: offset and count
    mov     %rdx, ((\ref) + 8)(%r12)
    lea     (%r12,%r13), %rdi
    mov     %r8, %rsi
    add     %rax, %r13
    mov     %rcx, %rdx
    call    lantern_copy
.endm

SPEC_FUNCTION beacon_state_copy
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    lea     L(%rsp), %rdx
    call    lantern_beacon_state_copy_size
    mov     L(%rsp), %rax
    cmp     %rax, (%r12)
    jb      9f
    lea     8(%r12), %rdi                   # the fixed part, after out's own size
    lea     8(%rbx), %rsi
    mov     $(BeaconState__fixed - 8), %edx
    call    lantern_copy
    mov     $BeaconState__fixed, %r13d
    STATE_PARTS COPY_PART
    xor     %eax, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
SPEC_END beacon_state_copy
