/*
 * The metrics' values of a head state, x86-64: in the object of each fork. Requirements:
 * docs/reference/metrics.md, lantern_metrics_state.
 */

/* rax = the status of the validator r10 at the epoch e: 0 pending, 1 active, 2 exited, 3 withdrawable. */
.macro MS_STATUS e
    xor     %eax, %eax
    cmp     \e, Validator_activation_epoch(%r10)
    ja      91f
    mov     $1, %eax
    cmp     Validator_exit_epoch(%r10), \e
    jb      91f
    mov     $2, %eax
    cmp     Validator_withdrawable_epoch(%r10), \e
    jb      91f
    mov     $3, %eax
91:
.endm

/*
 * (state, block, out): rdi state, rsi block, then the current participation, rdx out, r8 the
 * current epoch, r9 the previous epoch, r10 a validator, r11 the validators left, rcx the previous
 * participation. A leaf.
 */
SPEC_LEAF metrics_state
    xor     %eax, %eax                      # out: zero
    mov     $(MetricsState__mem / 8), %ecx
1:  mov     %rax, -8(%rdx,%rcx,8)
    dec     %rcx
    jnz     1b
    movq    $1, MetricsState_present(%rdx)
    cmpq    $180, 16(%rsi)                  # the block's state_root: bytes 148 to 180, as a number
    jb      2f
    mov     8(%rsi), %rax
    mov     172(%rsi,%rax), %rax
    mov     %rax, MetricsState_state_root(%rdx)
    movq    $1, MetricsState_state_root_present(%rdx)
2:  mov     BeaconState_slot(%rdi), %r8
    mov     %r8, MetricsState_slot(%rdx)
    shr     $LOG2_SLOTS_PER_EPOCH, %r8      # the current epoch, and the previous: one less, not below 0
    mov     %r8, %r9
    test    %r9, %r9
    jz      3f
    dec     %r9
3:  mov     (BeaconState_finalized_checkpoint + Checkpoint_epoch)(%rdi), %rax
    mov     %rax, MetricsState_finalized_epoch(%rdx)
    mov     (BeaconState_current_justified_checkpoint + Checkpoint_epoch)(%rdi), %rax
    mov     %rax, MetricsState_current_justified_epoch(%rdx)
    mov     (BeaconState_previous_justified_checkpoint + Checkpoint_epoch)(%rdi), %rax
    mov     %rax, MetricsState_previous_justified_epoch(%rdx)
    mov     (BeaconState_finalized_checkpoint + Checkpoint_root + 24)(%rdi), %rax
    mov     %rax, MetricsState_finalized_root(%rdx)
    mov     (BeaconState_previous_justified_checkpoint + Checkpoint_root + 24)(%rdi), %rax
    mov     %rax, MetricsState_previous_justified_root(%rdx)
    mov     (BeaconState_eth1_data + Eth1Data_deposit_count)(%rdi), %rax
    mov     %rax, MetricsState_deposit_count(%rdx)
.if FORK >= FORK_ALTAIR
    movq    $1, MetricsState_altair(%rdx)
.endif
.if FORK >= FORK_ELECTRA
    movq    $1, MetricsState_electra(%rdx)
    mov     (BeaconState_pending_deposits + 8)(%rdi), %rax
    mov     %rax, MetricsState_pending_deposits(%rdx)
    mov     (BeaconState_pending_partial_withdrawals + 8)(%rdi), %rax
    mov     %rax, MetricsState_pending_partial_withdrawals(%rdx)
    mov     (BeaconState_pending_consolidations + 8)(%rdi), %rax
    mov     %rax, MetricsState_pending_consolidations(%rdx)
.endif
    PART    %r10, %r11, %rdi, BeaconState_validators
.if FORK >= FORK_ALTAIR
    PART    %rsi, %rax, %rdi, BeaconState_current_epoch_participation
    PART    %rcx, %rax, %rdi, BeaconState_previous_epoch_participation
.endif
4:  test    %r11, %r11                      # each validator: its status at each epoch, and live
    jz      8f
    MS_STATUS %r8
    incq    MetricsState_current_validators(%rdx,%rax,8)
.if FORK >= FORK_ALTAIR
    cmp     $1, %eax                        # active with a flag
    jne     5f
    cmpb    $0, (%rsi)
    je      5f
    incq    MetricsState_current_live(%rdx)
5:  inc     %rsi
.endif
    MS_STATUS %r9
    incq    MetricsState_previous_validators(%rdx,%rax,8)
.if FORK >= FORK_ALTAIR
    cmp     $1, %eax
    jne     6f
    cmpb    $0, (%rcx)
    je      6f
    incq    MetricsState_previous_live(%rdx)
6:  inc     %rcx
.endif
    add     $Validator__mem, %r10
    dec     %r11
    jmp     4b
8:  mov     (MetricsState_current_validators + 8)(%rdx), %rax
    mov     %rax, MetricsState_active_validators(%rdx)
    xor     %eax, %eax
    ret
SPEC_END metrics_state
