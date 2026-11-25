/*
 * The Beacon API answers of the node, x86-64: in the common object. Requirements:
 * docs/reference/beacon-api.md (Common rules) and docs/reference/node.md (NODE_EV_API).
 *
 * The writer: r12 the cursor, r13 the pass (0 counts the bytes, 1 writes them), r14 the end of
 * the room, r15 1 when the room ran out, rbp the ApiView. The writer's functions keep r12-r15
 * and rbp for it; only lantern_api_respond calls them.
 */

    RODATA
.include "api_text.inc"
.include "api_spec.inc"

/* A record of API_SPEC_KEYS: the name's length, its kind, its value, then the name in CONFIG_KEY_NAME_MAX bytes. */
.set API_SPEC_BYTES, 24 + CONFIG_KEY_NAME_MAX
.macro API_SPEC_RECORD name, kind, value
    .quad 72f - 71f, \kind, \value
71: .ascii "\name"
72: .space CONFIG_KEY_NAME_MAX - (72b - 71b)
.endm
    .p2align 3
api_spec_keys:
    API_SPEC_KEYS API_SPEC_RECORD
api_spec_keys_end:

/* The text at label joins the response. */
.macro API_LIT label
    lea     \label(%rip), %rdi
    mov     $\label\()_len, %esi
    call    lantern_api_put
.endm

/* The rsi bytes at rdi join the response; the first pass only counts them. Uses rax, rcx, rsi, rdi. */
LOCAL_FUNCTION lantern_api_put
    UNWIND_END_PROLOGUE
    test    %r13, %r13
    jz      2f
    lea     (%r12,%rsi), %rax
    cmp     %r14, %rax
    ja      3f
    mov     %rsi, %rcx
    mov     %rdi, %rsi
    mov     %r12, %rdi
    rep movsb
    mov     %rdi, %r12
    ret
2:  add     %rsi, %r12
    ret
3:  mov     $1, %r15d
    ret
END_FUNCTION lantern_api_put

/* The decimal digits of rdi join the response. Locals: the digits, from the end. */
LOCAL_FUNCTION lantern_api_dec
    FRAME 32
    lea     32(%rsp), %r8
    mov     %rdi, %rax
    mov     $10, %ecx
1:  xor     %edx, %edx
    div     %rcx
    add     $0x30, %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %rax, %rax
    jnz     1b
    mov     %r8, %rdi
    lea     32(%rsp), %rsi
    sub     %r8, %rsi
    call    lantern_api_put
    UNFRAME 32
END_FUNCTION lantern_api_dec

/* The decimal digits of the 256-bit little-endian number at rdi join the response. Locals: its four words, then the digits from the end. */
LOCAL_FUNCTION lantern_api_dec256
    FRAME 128
    mov     (%rdi), %rax
    mov     %rax, (%rsp)
    mov     8(%rdi), %rax
    mov     %rax, 8(%rsp)
    mov     16(%rdi), %rax
    mov     %rax, 16(%rsp)
    mov     24(%rdi), %rax
    mov     %rax, 24(%rsp)
    lea     128(%rsp), %r8
    mov     $10, %ecx
1:  xor     %edx, %edx                      # divide by 10, from the top word down
    xor     %r9d, %r9d
    mov     $3, %r10d
2:  mov     (%rsp,%r10,8), %rax
    div     %rcx
    mov     %rax, (%rsp,%r10,8)
    or      %rax, %r9
    dec     %r10
    jns     2b
    add     $0x30, %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %r9, %r9
    jnz     1b
    mov     %r8, %rdi
    lea     128(%rsp), %rsi
    sub     %r8, %rsi
    call    lantern_api_put
    UNFRAME 128
END_FUNCTION lantern_api_dec256

/* The Gwei rdi in Wei, decimal digits, join the response. Locals: rdi. */
LOCAL_FUNCTION lantern_api_wei
    FRAME 16
    mov     %rdi, (%rsp)
    call    lantern_api_dec
    cmpq    $0, (%rsp)
    je      1f
    API_LIT api_nines
1:  UNFRAME 16
END_FUNCTION lantern_api_wei

/* The decimal digits of rdi, in quotes. Locals: rdi. */
LOCAL_FUNCTION lantern_api_qdec
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_quote
    mov     (%rsp), %rdi
    call    lantern_api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION lantern_api_qdec

/* "0x" and the lower case hex of the rsi bytes at rdi, in quotes. Locals: rdi, rsi, then 2 digits. */
LOCAL_FUNCTION lantern_api_qhex
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    API_LIT api_quote
    API_LIT api_0x
1:  mov     8(%rsp), %rsi
    test    %rsi, %rsi
    jz      2f
    mov     (%rsp), %rdi
    movzbl  (%rdi), %eax
    inc     %rdi
    dec     %rsi
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    lea     api_hex(%rip), %rcx
    mov     %eax, %edx
    shr     $4, %edx
    movzbl  (%rcx,%rdx), %edx
    mov     %dl, 16(%rsp)
    and     $15, %eax
    movzbl  (%rcx,%rax), %eax
    mov     %al, 17(%rsp)
    lea     16(%rsp), %rdi
    mov     $2, %esi
    call    lantern_api_put
    jmp     1b
2:  API_LIT api_quote
    UNFRAME 32
END_FUNCTION lantern_api_qhex

/* The text at rdi (its length, then its bytes), in quotes. Locals: rdi. */
LOCAL_FUNCTION lantern_api_text
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_quote
    mov     (%rsp), %rax
    mov     (%rax), %rsi
    lea     8(%rax), %rdi
    call    lantern_api_put
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION lantern_api_text

/* true when rdi is not 0, else false. */
LOCAL_FUNCTION lantern_api_bool
    FRAME 0
    test    %rdi, %rdi
    jz      1f
    API_LIT api_true
    UNFRAME 0
1:  API_LIT api_false
    UNFRAME 0
END_FUNCTION lantern_api_bool

/* A Checkpoint of the view at rdi: {"epoch":…,"root":…}. Locals: rdi. */
LOCAL_FUNCTION lantern_api_checkpoint
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_f_epoch
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_f_root
    mov     (%rsp), %rdi
    add     $8, %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION lantern_api_checkpoint

/* rax = the api_codes entry of the status rdi, or 0. Uses rcx. */
LOCAL_FUNCTION lantern_api_code
    UNWIND_END_PROLOGUE
    lea     api_codes(%rip), %rax
    lea     api_codes_end(%rip), %rcx
1:  cmp     %rcx, %rax
    jae     2f
    cmp     (%rax), %rdi
    je      3f
    add     $API_CODE_ENTRY, %rax
    jmp     1b
2:  xor     %eax, %eax
3:  ret
END_FUNCTION lantern_api_code

/* The text of the api_codes entry rdi at its byte rsi (8 the reason, 24 the message), or none for no entry. */
LOCAL_FUNCTION lantern_api_code_text
    FRAME 0
    test    %rdi, %rdi
    jz      9f
    mov     (%rdi,%rsi), %rax
    mov     8(%rdi,%rsi), %rsi
    lea     api_texts(%rip), %rdi
    add     %rax, %rdi
    call    lantern_api_put
9:  UNFRAME 0
END_FUNCTION lantern_api_code_text

/*
 * The body of the kind rsi for the view rbp: an error body of the status at (rdi), or the JSON of
 * an operation (beacon-api.md, Common rules). Locals: rdi, rsi.
 */
/* The decimal digits of the Uint256 at rdi, little endian, in quotes. Locals: its eight 32-bit words, then the text from its end. */
LOCAL_FUNCTION lantern_api_qdec256
    FRAME 128
    mov     (%rdi), %rax
    mov     %rax, (%rsp)
    mov     8(%rdi), %rax
    mov     %rax, 8(%rsp)
    mov     16(%rdi), %rax
    mov     %rax, 16(%rsp)
    mov     24(%rdi), %rax
    mov     %rax, 24(%rsp)
    lea     128(%rsp), %r8                  # the closing quote, then the digits backwards
    dec     %r8
    movb    $0x22, (%r8)
    mov     $10, %ecx
1:  xor     %edx, %edx                      # divide by 10, from the top word down
    mov     $7, %r9
    xor     %r10d, %r10d                    # any word not zero
2:  mov     (%rsp,%r9,4), %eax
    div     %ecx
    mov     %eax, (%rsp,%r9,4)
    or      %eax, %r10d
    dec     %r9
    jns     2b
    add     $0x30, %dl
    dec     %r8
    mov     %dl, (%r8)
    test    %r10d, %r10d
    jnz     1b
    dec     %r8
    movb    $0x22, (%r8)
    mov     %r8, %rdi
    lea     128(%rsp), %rsi
    sub     %r8, %rsi
    call    lantern_api_put
    UNFRAME 128
END_FUNCTION lantern_api_qdec256

/*
 * The body of getSpec (beacon-api.md, Common rules): each key of API_SPEC_KEYS, with the config
 * of the view rbp. Locals: the record, an index, 32 bytes of a value, a count.
 */
LOCAL_FUNCTION lantern_api_spec
    FRAME 64
    lea     api_spec_keys(%rip), %rax
    mov     %rax, (%rsp)
    API_LIT api_p_open
    jmp     2f
1:  mov     (%rsp), %rax                    # the next record
    add     $API_SPEC_BYTES, %rax
    mov     %rax, (%rsp)
    lea     api_spec_keys_end(%rip), %rcx
    cmp     %rcx, %rax
    jae     9f
    API_LIT api_p_next
2:  mov     (%rsp), %rax                    # "<name>":
    mov     (%rax), %rsi
    lea     24(%rax), %rdi
    call    lantern_api_put
    API_LIT api_p_key
    mov     (%rsp), %rax
    mov     8(%rax), %rcx                   # the kind, the value
    mov     16(%rax), %rdi
    mov     %rcx, %rdx                      # the kind's arg
    shr     $8, %rdx
    and     $255, %ecx
    mov     %rdi, 16(%rsp)                  # the value's bytes, then zero bytes
    movq    $0, 24(%rsp)
    movq    $0, 32(%rsp)
    movq    $0, 40(%rsp)
    mov     %rdx, 48(%rsp)
    cmp     $SPEC_NUMBER, %ecx
    jne     3f
    call    lantern_api_qdec
    jmp     1b
3:  cmp     $SPEC_HEX, %ecx
    jne     4f
    lea     16(%rsp), %rdi
    mov     %rdx, %rsi
    call    lantern_api_qhex
    jmp     1b
4:  cmp     $SPEC_TEXT, %ecx
    jne     5f
    API_LIT api_quote
    lea     16(%rsp), %rdi
    mov     48(%rsp), %rsi
    call    lantern_api_put
    API_LIT api_quote
    jmp     1b
5:  cmp     $SPEC_LIST, %ecx
    jne     6f
    API_LIT api_p_lbracket
    movq    $0, 8(%rsp)
51: mov     8(%rsp), %rax
    cmp     48(%rsp), %rax
    jae     52f
    test    %rax, %rax
    jz      53f
    API_LIT api_p_comma
53: mov     8(%rsp), %rax
    movzbl  16(%rsp,%rax), %edi
    inc     %rax
    mov     %rax, 8(%rsp)
    call    lantern_api_qdec
    jmp     51b
52: API_LIT api_p_rbracket
    jmp     1b
6:  add     ApiView_config(%rbp), %rdi      # the config's field
    cmp     $SPEC_SECONDS, %ecx
    jne     7f
    mov     (%rdi), %rax
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    mov     %rax, %rdi
    call    lantern_api_qdec
    jmp     1b
7:  cmp     $SPEC_CONFIG, %ecx
    jne     8f
    cmp     $CONFIG_KIND_U64, %rdx
    jne     71f
    mov     (%rdi), %rdi
    call    lantern_api_qdec
    jmp     1b
71: cmp     $CONFIG_KIND_UINT256, %rdx
    jne     72f
    call    lantern_api_qdec256
    jmp     1b
72: cmp     $CONFIG_KIND_TEXT, %rdx
    jne     73f
    call    lantern_api_text                        # in quotes
    jmp     1b
73: mov     $4, %esi                        # Version: 4 bytes; Hash32: 32; Address: 20
    mov     $32, %eax
    cmp     $CONFIG_KIND_HASH32, %rdx
    cmove   %eax, %esi
    mov     $20, %eax
    cmp     $CONFIG_KIND_ADDRESS, %rdx
    cmove   %eax, %esi
    call    lantern_api_qhex
    jmp     1b
    # SPEC_SCHEDULE: [{"EPOCH":…,"MAX_BLOBS_PER_BLOCK":…},…]
8:  API_LIT api_p_lbracket
    movq    $0, 8(%rsp)
81: mov     8(%rsp), %rax
    mov     ApiView_config(%rbp), %rcx
    cmp     CONFIG_BLOB_SCHEDULE_COUNT(%rcx), %rax
    jae     82f
    test    %rax, %rax
    jz      83f
    API_LIT api_p_comma
83: API_LIT api_p_epoch
    mov     8(%rsp), %rax
    shl     $4, %rax
    add     ApiView_config(%rbp), %rax
    mov     CONFIG_BLOB_SCHEDULE(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_p_max
    mov     8(%rsp), %rax
    shl     $4, %rax
    add     ApiView_config(%rbp), %rax
    mov     (CONFIG_BLOB_SCHEDULE + 8)(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_end1
    incq    8(%rsp)
    jmp     81b
82: API_LIT api_p_rbracket
    jmp     1b
9:  API_LIT api_end2
    UNFRAME 64
END_FUNCTION lantern_api_spec

/*
 * The body of getForkSchedule (beacon-api.md, Common rules), with the config of the view rbp:
 * phase0, then each fork to fulu whose epoch is below 2^64 - 1. Locals: the fork, the previous
 * version, the version, the epoch.
 */
LOCAL_FUNCTION lantern_api_fork_schedule
    FRAME 32
    API_LIT api_o_open
    mov     ApiView_config(%rbp), %rax
    mov     CONFIG_GENESIS_FORK_VERSION(%rax), %rax
    movq    $0, (%rsp)
    mov     %rax, 8(%rsp)
    mov     %rax, 16(%rsp)
    movq    $0, 24(%rsp)
    jmp     2f
1:  mov     (%rsp), %rax                    # the next fork: its version at 16 * fork - 8, its epoch at 16 * fork
    inc     %rax
    mov     %rax, (%rsp)
    cmp     $FORK_FULU, %rax
    ja      9f
    shl     $4, %rax
    add     ApiView_config(%rbp), %rax
    mov     -8(%rax), %rcx
    mov     (%rax), %rdx
    cmp     $-1, %rdx
    je      1b
    mov     %rcx, 16(%rsp)
    mov     %rdx, 24(%rsp)
    API_LIT api_p_comma
    # {"previous_version":…,"current_version":…,"epoch":…}
2:  API_LIT api_o_entry
    lea     8(%rsp), %rdi
    mov     $4, %esi
    call    lantern_api_qhex
    API_LIT api_k_current
    lea     16(%rsp), %rdi
    mov     $4, %esi
    call    lantern_api_qhex
    API_LIT api_k_epoch
    mov     24(%rsp), %rdi
    call    lantern_api_qdec
    API_LIT api_end1
    mov     16(%rsp), %rax                  # the next fork's previous version
    mov     %rax, 8(%rsp)
    jmp     1b
9:  API_LIT api_o_end
    UNFRAME 32
END_FUNCTION lantern_api_fork_schedule

# ---------------------------------------------------------------- Validators (beacon-api.md, Common rules)

.set API_ITEM_MAX, 576                      # the most bytes of an item and its comma

# rax = the API_STATUS_* of the validator at rdi at the epoch rsi. A leaf. Uses rax, rcx, rdx.
LOCAL_FUNCTION lantern_api_validator_status
    UNWIND_END_PROLOGUE
    cmp     %rsi, NODE_VALIDATOR_WITHDRAWABLE(%rdi)
    ja      1f
    mov     $API_STATUS_WITHDRAWAL_POSSIBLE, %eax
    mov     $API_STATUS_WITHDRAWAL_DONE, %ecx
    cmpq    $0, NODE_VALIDATOR_EFFECTIVE_BALANCE(%rdi)
    cmove   %ecx, %eax
    ret
1:  movzbl  NODE_VALIDATOR_SLASHED(%rdi), %edx
    mov     NODE_VALIDATOR_EXIT(%rdi), %rcx
    cmp     %rsi, %rcx
    ja      2f
    mov     $API_STATUS_EXITED_UNSLASHED, %eax
    test    %edx, %edx
    jz      9f
    mov     $API_STATUS_EXITED_SLASHED, %eax
    ret
2:  cmp     %rsi, NODE_VALIDATOR_ACTIVATION(%rdi)
    ja      4f
    mov     $API_STATUS_ACTIVE_ONGOING, %eax
    cmp     $-1, %rcx                       # active: exiting with an exit epoch below FAR_FUTURE_EPOCH
    je      9f
    mov     $API_STATUS_ACTIVE_EXITING, %eax
    test    %edx, %edx
    jz      9f
    mov     $API_STATUS_ACTIVE_SLASHED, %eax
    ret
4:  mov     $API_STATUS_PENDING_QUEUED, %eax
    cmpq    $-1, NODE_VALIDATOR_ELIGIBILITY(%rdi)
    jne     9f
    mov     $API_STATUS_PENDING_INITIALIZED, %eax
9:  ret
END_FUNCTION lantern_api_validator_status

# The item of the validator rsi of the state rdi: rdx 0 for getStateValidators, 1 for the balances,
# 2 for the identities, 3 for their SSZ (64 bytes). Locals: the validator, the index, the kind, the
# balance, the epoch, then an SSZ item at 48.
LOCAL_FUNCTION lantern_api_validator_item
    FRAME 112
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    PART    %rax, %rcx, %rdi, NODE_STATE_BALANCES
    mov     (%rax,%rsi,8), %rax
    mov     %rax, 24(%rsp)
    mov     NODE_STATE_SLOT(%rdi), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, 32(%rsp)
    PART    %rax, %rcx, %rdi, NODE_STATE_VALIDATORS
    mov     8(%rsp), %rcx
    shl     $7, %rcx                        # NODE_VALIDATOR_MEM
    add     %rcx, %rax
    mov     %rax, (%rsp)
    cmpq    $3, 16(%rsp)
    jne     1f
    mov     8(%rsp), %rcx                   # SSZ: index, pubkey, activation_epoch
    mov     %rcx, 48(%rsp)
    lea     56(%rsp), %rdi
    mov     %rax, %rsi
    mov     $48, %edx
    call    lantern_copy
    mov     (%rsp), %rax
    mov     NODE_VALIDATOR_ACTIVATION(%rax), %rax
    mov     %rax, 104(%rsp)
    lea     48(%rsp), %rdi
    mov     $64, %esi
    call    lantern_api_put
    UNFRAME 112
1:  API_LIT api_v_index
    mov     8(%rsp), %rdi
    call    lantern_api_qdec
    cmpq    $2, 16(%rsp)
    je      2f
    API_LIT api_v_balance
    mov     24(%rsp), %rdi
    call    lantern_api_qdec
    cmpq    $0, 16(%rsp)
    jne     9f
    API_LIT api_v_status
    mov     (%rsp), %rdi
    mov     32(%rsp), %rsi
    call    lantern_api_validator_status
    lea     api_v_statuses(%rip), %rdi
    imul    $24, %rax, %rax
    add     %rax, %rdi
    movzbl  (%rdi), %esi
    inc     %rdi
    call    lantern_api_put
    API_LIT api_v_validator
    mov     (%rsp), %rdi
    mov     $48, %esi
    call    lantern_api_qhex
    API_LIT api_v_credentials
    mov     (%rsp), %rdi
    add     $NODE_VALIDATOR_CREDENTIALS, %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_v_effective
    mov     (%rsp), %rax
    mov     NODE_VALIDATOR_EFFECTIVE_BALANCE(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_v_slashed
    mov     (%rsp), %rax
    movzbl  NODE_VALIDATOR_SLASHED(%rax), %edi
    call    lantern_api_bool
    API_LIT api_v_eligibility
    mov     (%rsp), %rax
    mov     NODE_VALIDATOR_ELIGIBILITY(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_v_activation
    mov     (%rsp), %rax
    mov     NODE_VALIDATOR_ACTIVATION(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_v_exit
    mov     (%rsp), %rax
    mov     NODE_VALIDATOR_EXIT(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_v_withdrawable
    mov     (%rsp), %rax
    mov     NODE_VALIDATOR_WITHDRAWABLE(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_end2
    UNFRAME 112
    # identities
2:  API_LIT api_v_pubkey
    mov     (%rsp), %rdi
    mov     $48, %esi
    call    lantern_api_qhex
    API_LIT api_v_activation
    mov     (%rsp), %rax
    mov     NODE_VALIDATOR_ACTIVATION(%rax), %rdi
    call    lantern_api_qdec
9:  API_LIT api_end1
    UNFRAME 112
END_FUNCTION lantern_api_validator_item

# rax = the index of the validator of the ValidatorRef in the ByteList rsi in the state rdi, or 2^64 - 1. A leaf. Uses rax, rcx, rdx, rsi, r8, r9.
LOCAL_FUNCTION lantern_node_api_find_validator
    UNWIND_END_PROLOGUE
    cmpq    $64, 16(%rsi)
    jne     8f
    add     8(%rsi), %rsi
    PART    %r8, %r9, %rdi, NODE_STATE_VALIDATORS
    cmpq    $API_VALIDATOR_INDEX, (%rsi)
    jne     2f
    mov     8(%rsi), %rax
    cmp     %r9, %rax
    jae     8f
    ret
2:  xor     %eax, %eax
3:  cmp     %r9, %rax
    jae     8f
    xor     %edx, %edx
31: mov     (%r8,%rdx), %rcx
    cmp     ValidatorRef_pubkey(%rsi,%rdx), %rcx
    jne     4f
    add     $8, %rdx
    cmp     $48, %rdx
    jb      31b
    ret
4:  add     $NODE_VALIDATOR_MEM, %r8
    inc     %rax
    jmp     3b
8:  mov     $-1, %rax
    ret
END_FUNCTION lantern_node_api_find_validator

# The selection of a chunk of a validator stream (node.md, NODE_WORK_API_CHUNK), at the cursor at
# NodeEvent_api + 16 of the event rbp: +16 a bitmap, in the scratch rdi, of the validators of the
# state rsi that the ValidatorRef items of data rdx name (0 with no data); +24 the epoch of the
# state's slot; +40 the count of the validators selected. rax = 0, or LANTERN_BUFFER_TOO_SMALL.
# Locals: the scratch's next byte, its end, the validators, their count, the items, their count, the
# table of the public keys, its mask.
LOCAL_FUNCTION lantern_node_api_validators_prep
    FRAME 64
    mov     (%rdi), %rax
    add     %rdi, %rax
    lea     16(%rdi), %rcx
    mov     %rcx, (%rsp)
    mov     %rax, 8(%rsp)
    mov     %rdx, %r8
    mov     NODE_STATE_SLOT(%rsi), %rax     # the epoch
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, (NodeEvent_api + 16 + 24)(%rbp)
    PART    %rax, %rcx, %rsi, NODE_STATE_VALIDATORS
    mov     %rax, 16(%rsp)
    mov     %rcx, 24(%rsp)
    mov     %rcx, (NodeEvent_api + 16 + 40)(%rbp)   # no items: every validator
    movq    $0, (NodeEvent_api + 16 + 16)(%rbp)
    test    %r8, %r8
    jz      90f
    mov     8(%r8), %rax                    # the items
    add     %r8, %rax
    mov     %rax, 32(%rsp)
    mov     16(%r8), %rax
    shr     $6, %rax
    mov     %rax, 40(%rsp)
    mov     24(%rsp), %rsi                  # the bitmap: a bit for each validator
    add     $63, %rsi
    shr     $6, %rsi
    shl     $3, %rsi
    mov     (%rsp), %rdi
    lea     (%rdi,%rsi), %rax
    cmp     8(%rsp), %rax
    ja      97f
    mov     %rax, (%rsp)
    mov     %rdi, (NodeEvent_api + 16 + 16)(%rbp)
    call    lantern_zero
    mov     (NodeEvent_api + 16 + 16)(%rbp), %r11   # index items: their bits; then count the public keys
    mov     32(%rsp), %r8
    mov     40(%rsp), %r9
    mov     24(%rsp), %r10
    xor     %ecx, %ecx
1:  test    %r9, %r9
    jz      3f
    cmpq    $API_VALIDATOR_INDEX, (%r8)
    jne     2f
    mov     8(%r8), %rax
    cmp     %r10, %rax
    jae     21f
    bts     %rax, (%r11)
    jmp     21f
2:  inc     %rcx
21: add     $64, %r8
    dec     %r9
    jmp     1b
3:  test    %rcx, %rcx
    jz      80f
    shl     $1, %rcx                        # the table: the least power of two at least twice the keys
    mov     $1, %eax
31: cmp     %rcx, %rax
    jae     32f
    shl     $1, %rax
    jmp     31b
32: lea     -1(%rax), %rcx
    mov     %rcx, 56(%rsp)
    mov     (%rsp), %rdi
    lea     0(,%rax,8), %rsi
    lea     (%rdi,%rsi), %rax
    cmp     8(%rsp), %rax
    ja      97f
    mov     %rdi, 48(%rsp)
    call    lantern_zero
    mov     32(%rsp), %r8                   # each public key item: its number + 1, at bytes 8 to 16 of the key
    mov     40(%rsp), %r9
    mov     48(%rsp), %r10
    mov     56(%rsp), %r11
    xor     %ecx, %ecx
4:  cmp     %r9, %rcx
    jae     5f
    cmpq    $API_VALIDATOR_PUBKEY, (%r8)
    jne     42f
    mov     (ValidatorRef_pubkey + 8)(%r8), %rax
41: and     %r11, %rax
    cmpq    $0, (%r10,%rax,8)
    je      43f
    inc     %rax
    jmp     41b
43: lea     1(%rcx), %rdx
    mov     %rdx, (%r10,%rax,8)
42: add     $64, %r8
    inc     %rcx
    jmp     4b
5:  mov     16(%rsp), %r8                   # each validator whose key the table holds: its bit
    xor     %ecx, %ecx
    mov     (NodeEvent_api + 16 + 16)(%rbp), %rsi
51: cmp     24(%rsp), %rcx
    jae     80f
    mov     8(%r8), %rax
52: and     %r11, %rax
    mov     (%r10,%rax,8), %rdx
    test    %rdx, %rdx
    jz      59f
    dec     %rdx
    shl     $6, %rdx
    add     32(%rsp), %rdx
    xor     %edi, %edi
53: mov     (%r8,%rdi), %r9
    cmp     ValidatorRef_pubkey(%rdx,%rdi), %r9
    jne     58f
    add     $8, %rdi
    cmp     $48, %rdi
    jb      53b
    bts     %rcx, (%rsi)
    jmp     59f
58: inc     %rax
    jmp     52b
59: add     $NODE_VALIDATOR_MEM, %r8
    inc     %rcx
    jmp     51b
80: mov     24(%rsp), %rcx                  # the count: the bits set
    add     $63, %rcx
    shr     $6, %rcx
    mov     (NodeEvent_api + 16 + 16)(%rbp), %rsi
    xor     %edx, %edx
81: test    %rcx, %rcx
    jz      83f
    mov     (%rsi), %rax
    add     $8, %rsi
82: test    %rax, %rax
    jz      84f
    lea     -1(%rax), %rdi
    and     %rdi, %rax
    inc     %rdx
    jmp     82b
84: dec     %rcx
    jmp     81b
83: mov     %rdx, (NodeEvent_api + 16 + 40)(%rbp)
90: xor     %eax, %eax
    UNFRAME 64
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 64
END_FUNCTION lantern_node_api_validators_prep

# The items of the pending stream of the entry rbx, of the state rdi (node.md, NODE_WORK_API_CHUNK),
# from the index at NodeEvent_api + 16 of the event rbp, at the writer's cursor r12 up to r14, with
# , between; then ]} once they are all written. rax = 1 when whole, 0 when more is to come, 2 when
# the state has no such list. Locals: lantern_node_pending's out, the kind.
LOCAL_FUNCTION lantern_api_pending_json
    FRAME 32
    mov     NodeApi_op(%rbx), %rax          # the kind: 0 deposits, 1 partial withdrawals, 2 consolidations
    lea     -API_OP_GET_PENDING_DEPOSITS(%rax), %rsi
    mov     $2, %ecx
    cmp     $API_OP_GET_PENDING_CONSOLIDATIONS, %rax
    cmove   %rcx, %rsi
    mov     %rsi, 24(%rsp)
    mov     %rsp, %rdx
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_pending
    test    %rax, %rax
    jnz     7f
1:  mov     (NodeEvent_api + 16)(%rbp), %rax
    cmp     8(%rsp), %rax
    jae     8f
    mov     %r14, %rcx                      # room for one more item
    sub     %r12, %rcx
    cmp     $API_ITEM_MAX, %rcx
    jb      9f
    test    %rax, %rax
    jz      2f
    API_LIT api_p_comma
2:  mov     (NodeEvent_api + 16)(%rbp), %rdi
    imul    16(%rsp), %rdi
    add     (%rsp), %rdi
    mov     24(%rsp), %rsi
    call    lantern_api_pending_item
    incq    (NodeEvent_api + 16)(%rbp)
    jmp     1b
8:  API_LIT api_v_end
    mov     $1, %eax
    UNFRAME 32
9:  xor     %eax, %eax
    UNFRAME 32
7:  mov     $2, %eax
    UNFRAME 32
END_FUNCTION lantern_api_pending_json

# The JSON of the pending item at rdi of the kind rsi (lantern_node_pending): a PendingDeposit, a
# PendingPartialWithdrawal or a PendingConsolidation, from its SSZ fields. Locals: the item.
LOCAL_FUNCTION lantern_api_pending_item
    FRAME 16
    mov     %rdi, (%rsp)
    cmp     $1, %rsi
    je      20f
    ja      30f
    # {"pubkey":…,"withdrawal_credentials":…,"amount":…,"signature":…,"slot":…}
    API_LIT api_q_pubkey
    mov     (%rsp), %rdi
    mov     $48, %esi
    call    lantern_api_qhex
    API_LIT api_q_credentials
    mov     (%rsp), %rdi
    add     $48, %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_q_amount
    mov     (%rsp), %rax
    mov     80(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_q_signature
    mov     (%rsp), %rdi
    add     $88, %rdi
    mov     $96, %esi
    call    lantern_api_qhex
    API_LIT api_q_slot
    mov     (%rsp), %rax
    mov     184(%rax), %rdi
    call    lantern_api_qdec
    jmp     9f
    # {"validator_index":…,"amount":…,"withdrawable_epoch":…}
20: API_LIT api_q_validator
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_q_amount
    mov     (%rsp), %rax
    mov     8(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_q_withdrawable
    mov     (%rsp), %rax
    mov     16(%rax), %rdi
    call    lantern_api_qdec
    jmp     9f
    # {"source_index":…,"target_index":…}
30: API_LIT api_q_source
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_q_target
    mov     (%rsp), %rax
    mov     8(%rax), %rdi
    call    lantern_api_qdec
9:  API_LIT api_end1
    UNFRAME 16
END_FUNCTION lantern_api_pending_item

# The items of the validator stream of the entry rbx, of the state rdi, from the cursor at
# NodeEvent_api + 16 of the event rbp (+0 the next index, +8 the status bits, +16 the bitmap, +24
# the epoch, +32 the items written), at the writer's cursor r12 up to r14; then ]} for JSON once they
# are all written. rax = 1 when whole, else 0. Locals: the state, the kind, the validators' count.
LOCAL_FUNCTION lantern_api_validators_json
    FRAME 32
    mov     %rdi, (%rsp)
    xor     %eax, %eax                      # the kind: 0, 1 the balances, 2 the identities, 3 their SSZ
    mov     NodeApi_op(%rbx), %rcx
    cmp     $API_OP_GET_STATE_VALIDATOR_BALANCES, %rcx
    je      11f
    cmp     $API_OP_POST_STATE_VALIDATOR_BALANCES, %rcx
    jne     12f
11: mov     $1, %eax
12: cmp     $API_OP_POST_STATE_VALIDATOR_IDENTITIES, %rcx
    jne     13f
    mov     $2, %eax
    testq   $API_STREAM_SSZ, NodeApi_flags(%rbx)
    jz      13f
    mov     $3, %eax
13: mov     %rax, 8(%rsp)
    mov     (NODE_STATE_VALIDATORS + 8)(%rdi), %rax
    mov     %rax, 16(%rsp)
2:  mov     (NodeEvent_api + 16)(%rbp), %rcx
    cmp     16(%rsp), %rcx
    jae     8f
    mov     (NodeEvent_api + 16 + 16)(%rbp), %rdx   # with a bitmap: the next validator it names
    test    %rdx, %rdx
    jz      3f
    mov     %rcx, %rax
    shr     $6, %rax
    mov     (%rdx,%rax,8), %rax
    shr     %cl, %rax
    test    %rax, %rax
    jnz     21f
    add     $64, %rcx
    and     $~63, %rcx
    mov     %rcx, (NodeEvent_api + 16)(%rbp)
    jmp     2b
21: bsf     %rax, %rax
    add     %rax, %rcx
    mov     %rcx, (NodeEvent_api + 16)(%rbp)
3:  cmpq    $0, (NodeEvent_api + 16 + 8)(%rbp)       # with status bits: its status has its bit
    je      4f
    mov     (%rsp), %rdi
    PART    %rax, %rdx, %rdi, NODE_STATE_VALIDATORS
    shl     $7, %rcx
    lea     (%rax,%rcx), %rdi
    mov     (NodeEvent_api + 16 + 24)(%rbp), %rsi
    call    lantern_api_validator_status
    mov     (NodeEvent_api + 16 + 8)(%rbp), %rdx
    bt      %rax, %rdx
    jc      4f
    incq    (NodeEvent_api + 16)(%rbp)
    jmp     2b
4:  mov     %r14, %rax                      # room for one more item
    sub     %r12, %rax
    cmp     $API_ITEM_MAX, %rax
    jb      9f
    cmpq    $3, 8(%rsp)
    je      5f
    cmpq    $0, (NodeEvent_api + 16 + 32)(%rbp)
    je      5f
    API_LIT api_p_comma
5:  incq    (NodeEvent_api + 16 + 32)(%rbp)
    mov     (%rsp), %rdi
    mov     (NodeEvent_api + 16)(%rbp), %rsi
    mov     8(%rsp), %rdx
    call    lantern_api_validator_item
    incq    (NodeEvent_api + 16)(%rbp)
    jmp     2b
8:  cmpq    $3, 8(%rsp)                     # all: ]} for JSON
    je      81f
    mov     %r14, %rax
    sub     %r12, %rax
    cmp     $2, %rax
    jb      9f
    API_LIT api_v_end
81: mov     $1, %eax
    UNFRAME 32
9:  xor     %eax, %eax
    UNFRAME 32
END_FUNCTION lantern_api_validators_json

# The fields ,"head":…,"target":…,"source":…,"inactivity":…} of the 48-byte item rdi of
# lantern_node_attestation_rewards, with ,"inclusion_delay":… before inactivity when the fork of the
# entry rbx is phase0. Locals: the item.
LOCAL_FUNCTION lantern_api_reward_fields
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_ar_head
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_qint
    API_LIT api_ar_target
    mov     (%rsp), %rax
    mov     8(%rax), %rdi
    call    lantern_api_qint
    API_LIT api_ar_source
    mov     (%rsp), %rax
    mov     16(%rax), %rdi
    call    lantern_api_qint
    cmpq    $0, NodeApi_fork(%rbx)
    jne     1f
    API_LIT api_ar_inclusion
    mov     (%rsp), %rax
    mov     24(%rax), %rdi
    call    lantern_api_qdec
1:  API_LIT api_ar_inactivity
    mov     (%rsp), %rax
    mov     32(%rax), %rdi
    call    lantern_api_qint
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION lantern_api_reward_fields

.set API_REWARD_WINDOW, 256                 # the validators of one call of lantern_node_attestation_rewards
.set API_REWARD_ITEM_MAX, 256               # the room an item may take

# The items of getAttestationsRewards (beacon-api.md) of the entry rbx, of the state rdi, from the
# cursor at NodeEvent_api + 16 of the event rbp (+0 the next step or validator, +16 the bitmap of
# the ids, +32 the items written, +48 the part: 0 no totals yet, 1 the ideal items, 2 the
# validators' items; +56 the totals; +584 the node's config; +592 the chunk's scratch), at the
# writer's cursor r12 up to r14; then ]}} once all are written. rax = 1 when whole, 0 when more is
# to come, 2 for a state the functions refuse, 3 for a scratch too small. Locals: the state, the
# cursor, the window's items, its first validator, its count, a value, an ideal item (48).
LOCAL_FUNCTION lantern_api_rewards_json
    FRAME 96
    mov     %rdi, (%rsp)
    lea     (NodeEvent_api + 16)(%rbp), %rax
    mov     %rax, 8(%rsp)
    mov     48(%rax), %rcx
    cmp     $2, %rcx
    je      5f
    cmp     $1, %rcx
    je      3f
    mov     (%rsp), %rdi                    # the first chunk: the totals, as process_epoch has them
    mov     584(%rax), %rsi
    mov     $1, %edx
    mov     592(%rax), %rcx
    lea     56(%rax), %r8
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_reward_totals
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      93f
    test    %rax, %rax
    jnz     92f
    mov     8(%rsp), %rax
    movq    $1, 48(%rax)
    movq    $1, (%rax)
    movq    $0, 32(%rax)
3:  mov     8(%rsp), %rax                   # the ideal items: each effective balance step
    mov     (%rax), %rcx
    MOVQ    %rdx, EFFECTIVE_BALANCE_INCREMENT
    imul    %rdx, %rcx
    cmp     (56 + 72)(%rax), %rcx
    ja      4f
    mov     %r14, %rdx
    sub     %r12, %rdx
    cmp     $API_REWARD_ITEM_MAX, %rdx
    jb      90f
    mov     %rcx, 40(%rsp)
    lea     56(%rax), %rdi
    mov     %rcx, %rsi
    lea     48(%rsp), %rdx
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_ideal_reward
    mov     8(%rsp), %rax
    cmpq    $1, (%rax)
    je      31f
    API_LIT api_p_comma
31: API_LIT api_ar_eb
    mov     40(%rsp), %rdi
    call    lantern_api_qdec
    lea     48(%rsp), %rdi
    call    lantern_api_reward_fields
    mov     8(%rsp), %rax
    incq    (%rax)
    jmp     3b
4:  mov     %r14, %rax                      # then the validators
    sub     %r12, %rax
    cmp     $32, %rax
    jb      90f
    API_LIT api_ar_total
    mov     8(%rsp), %rax
    movq    $2, 48(%rax)
    movq    $0, (%rax)
    movq    $0, 32(%rax)
5:  mov     8(%rsp), %rax                   # a window of validators from the next
    mov     (%rax), %rcx
    mov     (%rsp), %rdx
    mov     (NODE_STATE_VALIDATORS + 8)(%rdx), %rdx
    cmp     %rdx, %rcx
    jae     8f
    sub     %rcx, %rdx
    cmp     $API_REWARD_WINDOW, %rdx
    jbe     51f
    mov     $API_REWARD_WINDOW, %edx
51: mov     %rcx, 24(%rsp)
    mov     %rdx, 32(%rsp)
    mov     592(%rax), %rsi                 # its items at the end of the chunk's scratch
    imul    $48, %rdx, %rdx
    mov     (%rsi), %rcx
    sub     %rdx, %rcx
    jb      93f
    mov     %rcx, (%rsi)
    add     %rsi, %rcx
    mov     %rcx, 16(%rsp)
    mov     (%rsp), %rdi
    mov     584(%rax), %rsi
    lea     56(%rax), %rdx
    mov     24(%rsp), %rcx
    mov     32(%rsp), %r8
    mov     592(%rax), %r9
    mov     16(%rsp), %rax
    sub     $16, %rsp                       # the seventh argument: out
    mov     %rax, (%rsp)
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_attestation_rewards
    add     $16, %rsp
    mov     8(%rsp), %rcx                   # the scratch's size again
    mov     592(%rcx), %rsi
    mov     32(%rsp), %rdx
    imul    $48, %rdx, %rdx
    add     %rdx, (%rsi)
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      93f
    test    %rax, %rax
    jnz     92f
    movq    $0, 40(%rsp)
6:  mov     40(%rsp), %rcx                  # each validator of the window: named by the ids, or with none eligible
    cmp     32(%rsp), %rcx
    jae     7f
    mov     24(%rsp), %rsi
    add     %rcx, %rsi
    imul    $48, %rcx, %rdi
    add     16(%rsp), %rdi
    mov     8(%rsp), %rax
    mov     16(%rax), %rdx
    test    %rdx, %rdx
    jz      61f
    mov     %rsi, %rax
    shr     $6, %rax
    mov     (%rdx,%rax,8), %rax
    bt      %rsi, %rax
    jnc     69f
    jmp     62f
61: cmpq    $0, 40(%rdi)
    je      69f
62: mov     %r14, %rax
    sub     %r12, %rax
    cmp     $API_REWARD_ITEM_MAX, %rax
    jb      68f
    mov     8(%rsp), %rax
    mov     32(%rax), %rcx
    incq    32(%rax)
    test    %rcx, %rcx
    jz      63f
    API_LIT api_p_comma
63: API_LIT api_q_validator
    mov     24(%rsp), %rdi
    add     40(%rsp), %rdi
    call    lantern_api_qdec
    mov     40(%rsp), %rdi
    imul    $48, %rdi, %rdi
    add     16(%rsp), %rdi
    call    lantern_api_reward_fields
69: incq    40(%rsp)
    jmp     6b
68: mov     24(%rsp), %rcx                  # no room: the next chunk goes on from this validator
    add     40(%rsp), %rcx
    mov     8(%rsp), %rax
    mov     %rcx, (%rax)
    jmp     90f
7:  mov     24(%rsp), %rcx
    add     32(%rsp), %rcx
    mov     8(%rsp), %rax
    mov     %rcx, (%rax)
    jmp     5b
8:  mov     %r14, %rax                      # all: ]}}
    sub     %r12, %rax
    cmp     $4, %rax
    jb      90f
    API_LIT api_ar_end
    mov     $1, %eax
    UNFRAME 96
90: xor     %eax, %eax
    UNFRAME 96
92: mov     $2, %eax
    UNFRAME 96
93: mov     $3, %eax
    UNFRAME 96
END_FUNCTION lantern_api_rewards_json

/*
 * The answer of a state operation (beacon-api.md) for the connection rdi, the route rsi, the answer
 * flags rdx and the view rcx whose state lantern_node_api_state found: the state at head_slot, then a
 * stream or a work. A validator operation's ids: look_data when it is not 0, else the route's.
 * rax = 0, or the status of an error. r12 the flags, r13 the route, S7 the view, S8 the connection.
 */
LOCAL_FUNCTION lantern_node_api_state_answer
    ENTER 0
    mov     %rdi, S8(%rsp)
    mov     %rsi, %r13
    mov     %rdx, %r12
    mov     %rcx, S7(%rsp)
    mov     %rcx, %rdi
    call    lantern_node_api_advance
    mov     ApiRoute_op(%r13), %rcx
    cmp     $API_OP_GET_STATE_V2, %rcx
    je      64f
    lea     -API_OP_GET_PENDING_CONSOLIDATIONS(%rcx), %rdx  # the pending lists: a stream of the state, no data
    cmp     $2, %rdx
    ja      5f
    mov     S7(%rsp), %rdx
    movq    $0, ApiView_look_data(%rdx)
    jmp     64f
5:  cmp     $API_OP_GET_STATE_RANDAO, %rcx  # getStateRandao, getEpochSyncCommittees: the epoch in the work's data
    je      2f
    cmp     $API_OP_GET_EPOCH_SYNC_COMMITTEES, %rcx
    je      2f
    cmp     $API_OP_GET_PROPOSER_LOOKAHEAD, %rcx    # getProposerLookahead: SSZ, an answer flag
    jne     3f
    cmpq    $API_TYPE_SSZ, ApiRoute_response(%r13)
    jne     67f
    or      $API_ANSWER_SSZ, %r12
    jmp     67f
2:  testq   $(1 << API_PARAM_EPOCH), ApiRoute_present(%r13)
    jnz     4f
    movq    $-1, ApiRoute_epoch(%r13)
4:  lea     ApiRoute_epoch(%r13), %rdi
    call    lantern_node_api_put8
    mov     S7(%rsp), %rcx
    mov     %rax, ApiView_look_data(%rcx)
    jmp     67f
3:  sub     $API_OP_GET_STATE_VALIDATORS, %rcx
    cmp     $(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS), %rcx
    ja      67f
    mov     S7(%rsp), %rcx                  # the validator operations: their ids; getStateValidator a work, the others a stream
    cmpq    $0, ApiView_look_data(%rcx)
    jne     6f
    mov     %r13, %rdi
    call    lantern_node_api_ids
    mov     S7(%rsp), %rcx
    mov     %rax, ApiView_look_data(%rcx)
6:  cmpq    $API_OP_GET_STATE_VALIDATOR, ApiRoute_op(%r13)
    jne     64f
67: mov     ApiRoute_op(%r13), %rdi         # a work
    mov     S8(%rsp), %rsi
    mov     %r12, %rdx
    mov     S7(%rsp), %rcx
    call    lantern_node_api_encode
    LEAVE 0
64: mov     S8(%rsp), %rdi                  # a stream of the answer
    mov     %r13, %rsi
    mov     %r12, %rdx
    mov     S7(%rsp), %rcx
    call    lantern_node_api_stream
    LEAVE 0
END_FUNCTION lantern_node_api_state_answer

# rax = the epoch of getEpochCommittees of the route rdi and the state of the view rsi (beacon-api.md,
# Common rules), or 2^64 - 1 for 400: an epoch above the state's + 1, one whose seed's RANDAO mix the
# state no longer holds, or a slot of another epoch. A leaf. Uses rax, rcx, rdx, r8, r9.
LOCAL_FUNCTION lantern_node_api_committees_check
    UNWIND_END_PROLOGUE
    mov     ApiView_head_slot(%rsi), %rax   # the state's epoch at r8, the epoch at r9
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %r8
    mov     %rax, %r9
    testq   $(1 << API_PARAM_EPOCH), ApiRoute_present(%rdi)
    jz      1f
    mov     ApiRoute_epoch(%rdi), %r9
1:  lea     1(%r8), %rax                    # at most the state's epoch + 1
    cmp     %rax, %r9
    ja      8f
    sub     $EPOCHS_PER_HISTORICAL_VECTOR, %rax   # epoch - MIN_SEED_LOOKAHEAD - 1 at least epoch + 1 - EPOCHS_PER_HISTORICAL_VECTOR, each 0 when below
    jae     11f
    xor     %eax, %eax
11: mov     %r9, %rcx
    sub     $(MIN_SEED_LOOKAHEAD + 1), %rcx
    jae     12f
    xor     %ecx, %ecx
12: cmp     %rax, %rcx
    jb      8f
    testq   $(1 << API_PARAM_SLOT), ApiRoute_present(%rdi)    # a slot of the epoch
    jz      2f
    mov     ApiRoute_slot(%rdi), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    cmp     %r9, %rax
    jne     8f
2:  mov     %r9, %rax
    ret
8:  mov     $-1, %rax
    ret
END_FUNCTION lantern_node_api_committees_check

# The cursor of the getEpochCommittees stream of the entry rdi, for the route rsi and the epoch rdx
# (node.md, NODE_EV_API): the first slot at 0, the first index at 8, the epoch at 24, the slot and the
# index asked at 40 and 48 (2^64 - 1 for none). A leaf. Uses rax, rcx.
LOCAL_FUNCTION lantern_node_api_committees_cursor
    UNWIND_END_PROLOGUE
    mov     %rdx, (NodeApi_cursor + 24)(%rdi)
    imul    $SLOTS_PER_EPOCH, %rdx, %rax
    mov     $-1, %rcx
    testq   $(1 << API_PARAM_SLOT), ApiRoute_present(%rsi)
    jz      1f
    mov     ApiRoute_slot(%rsi), %rax
    mov     %rax, %rcx
1:  mov     %rax, NodeApi_cursor(%rdi)
    mov     %rcx, (NodeApi_cursor + 40)(%rdi)
    xor     %eax, %eax
    mov     $-1, %rcx
    testq   $(1 << API_PARAM_INDEX), ApiRoute_present(%rsi)
    jz      2f
    mov     ApiRoute_index(%rsi), %rax
    mov     %rax, %rcx
2:  mov     %rax, (NodeApi_cursor + 8)(%rdi)
    mov     %rcx, (NodeApi_cursor + 48)(%rdi)
    ret
END_FUNCTION lantern_node_api_committees_cursor

# A chunk's start of a getEpochCommittees stream (node.md, NODE_WORK_API_CHUNK), at the cursor at
# NodeEvent_api + 16 of the event rbp: +56 get_committee_count_per_slot of the state rsi at the epoch
# at +24; +72 the scratch rdi and +80 the CommitteeCache of the node rdx, for lantern_api_committees_json.
# rax = 0; 400 for an index asked at or past the count, in the first chunk; LANTERN_BUFFER_TOO_SMALL
# for a scratch with no room for a committee and lantern_get_beacon_committee; else the status of the
# count. Locals: the epoch, the count, the state.
LOCAL_FUNCTION lantern_node_api_committees_prep
    FRAME 32
    mov     %rdi, (NodeEvent_api + 16 + 72)(%rbp)
    mov     %rsi, 16(%rsp)
    mov     (NodeEvent_api + 16 + 24)(%rbp), %rax
    mov     %rax, (%rsp)
    mov     %rdi, %rcx
    mov     %rsi, %rdi
    mov     %rsp, %rsi
    mov     (Node_config + CONFIG_COMMITTEE_CACHE)(%rdx), %rdx
    mov     %rdx, (NodeEvent_api + 16 + 80)(%rbp)
    lea     8(%rsp), %r8
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL get_committee_count_per_slot
    test    %rax, %rax
    jnz     9f
    mov     8(%rsp), %rcx                   # the count
    mov     %rcx, (NodeEvent_api + 16 + 56)(%rbp)
    mov     16(%rsp), %rax                  # the scratch: 16, a committee's list, then S(2)
    mov     (NODE_STATE_VALIDATORS + 8)(%rax), %r8
    imul    $SLOTS_PER_EPOCH, %rcx, %rcx
    mov     %r8, %rax
    xor     %edx, %edx
    div     %rcx
    lea     (16 + LIST_FIXED + 8)(,%rax,8), %r9
    lea     LIST_FIXED(,%r8,8), %rax
    lea     (%r9,%rax,2), %r9
    add     $LANTERN_SCRATCH_FIXED, %r9
    mov     (NodeEvent_api + 16 + 72)(%rbp), %rax
    cmp     (%rax), %r9
    ja      97f
    testq   $API_STREAM_STARTED, (NodeEvent_api + 8)(%rbp)   # the first chunk: an index at or past the count, 400
    jnz     8f
    mov     (NodeEvent_api + 16 + 48)(%rbp), %rax
    cmp     $-1, %rax
    je      8f
    cmp     (NodeEvent_api + 16 + 56)(%rbp), %rax
    jb      8f
    mov     $400, %eax
    UNFRAME 32
8:  xor     %eax, %eax
9:  UNFRAME 32
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    UNFRAME 32
END_FUNCTION lantern_node_api_committees_prep

# The items of the getEpochCommittees stream of the entry rbx, of the state rdi, from the cursor at
# NodeEvent_api + 16 of the event rbp (+0 the slot, +8 the index, +16 the member, +24 the epoch, +32
# the items written, +40 and +48 the slot and the index asked or 2^64 - 1, +56 the committees per
# slot, +64 1 within an item, +72 the scratch, +80 the CommitteeCache), at the writer's cursor r12 up
# to r14; then ]} once they are all written. rax = 1 when whole, 0 when more is to come, 2 when a
# committee fails. Locals: the slot, the index, the committee's list, the state.
LOCAL_FUNCTION lantern_api_committees_json
    FRAME 48
    mov     %rdi, 32(%rsp)
1:  mov     (NodeEvent_api + 16)(%rbp), %rax        # the slot and the index
    mov     (NodeEvent_api + 16 + 8)(%rbp), %rcx
    mov     (NodeEvent_api + 16 + 40)(%rbp), %rdx   # the last slot: the one asked, else the epoch's last
    cmp     $-1, %rdx
    jne     2f
    mov     (NodeEvent_api + 16 + 24)(%rbp), %rdx
    inc     %rdx
    imul    $SLOTS_PER_EPOCH, %rdx, %rdx
    dec     %rdx
2:  cmp     %rdx, %rax
    ja      8f
    mov     (NodeEvent_api + 16 + 48)(%rbp), %rdx   # the end of the indices: past the one asked, else the count
    mov     (NodeEvent_api + 16 + 56)(%rbp), %rsi
    cmp     $-1, %rdx
    je      21f
    lea     1(%rdx), %rsi
21: cmp     %rsi, %rcx
    jb      3f
    inc     %rax                            # the slot's committees are written: the next slot
    xor     %ecx, %ecx
    cmp     $-1, %rdx
    cmovne  %rdx, %rcx
    mov     %rax, (NodeEvent_api + 16)(%rbp)
    mov     %rcx, (NodeEvent_api + 16 + 8)(%rbp)
    jmp     1b
3:  cmpq    $0, (NodeEvent_api + 16 + 64)(%rbp)
    jne     4f
    mov     %r14, %rax                      # the item's head: {"index":…,"slot":…,"validators":[
    sub     %r12, %rax
    cmp     $80, %rax
    jb      9f
    cmpq    $0, (NodeEvent_api + 16 + 32)(%rbp)
    je      31f
    API_LIT api_p_comma
31: incq    (NodeEvent_api + 16 + 32)(%rbp)
    movq    $1, (NodeEvent_api + 16 + 64)(%rbp)
    movq    $0, (NodeEvent_api + 16 + 16)(%rbp)
    API_LIT api_v_index
    mov     (NodeEvent_api + 16 + 8)(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_c_slot
    mov     (NodeEvent_api + 16)(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_c_validators
4:  mov     (NodeEvent_api + 16)(%rbp), %rax        # the committee, in a list after 16 bytes of the scratch
    mov     %rax, (%rsp)
    mov     (NodeEvent_api + 16 + 8)(%rbp), %rax
    mov     %rax, 8(%rsp)
    mov     32(%rsp), %rax
    mov     (NODE_STATE_VALIDATORS + 8)(%rax), %rax
    mov     (NodeEvent_api + 16 + 56)(%rbp), %rcx
    imul    $SLOTS_PER_EPOCH, %rcx, %rcx
    xor     %edx, %edx
    div     %rcx
    lea     (LIST_FIXED + 8)(,%rax,8), %rax
    mov     (NodeEvent_api + 16 + 72)(%rbp), %rsi
    lea     16(%rsi), %r9
    mov     %rax, (%r9)
    movq    $LIST_FIXED, LIST_OFFSET(%r9)
    movq    $0, LIST_COUNT(%r9)
    mov     %r9, 16(%rsp)
    lea     16(%rax), %rcx
    lea     (%rsi,%rcx), %r8
    mov     (%rsi), %rdx
    sub     %rcx, %rdx
    mov     %rdx, (%r8)
    mov     32(%rsp), %rdi
    mov     %rsp, %rsi
    lea     8(%rsp), %rdx
    mov     (NodeEvent_api + 16 + 80)(%rbp), %rcx
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL get_beacon_committee
    test    %rax, %rax
    jnz     7f
41: mov     (NodeEvent_api + 16 + 16)(%rbp), %rcx   # its members from the one at +16
    mov     16(%rsp), %rax
    cmp     LIST_COUNT(%rax), %rcx
    jae     5f
    mov     %r14, %rax
    sub     %r12, %rax
    cmp     $24, %rax
    jb      9f
    test    %rcx, %rcx
    jz      42f
    API_LIT api_p_comma
42: mov     (NodeEvent_api + 16 + 16)(%rbp), %rcx
    mov     16(%rsp), %rax
    mov     LIST_FIXED(%rax,%rcx,8), %rdi
    incq    (NodeEvent_api + 16 + 16)(%rbp)
    call    lantern_api_qdec
    jmp     41b
5:  mov     %r14, %rax                      # the item's end: ]}
    sub     %r12, %rax
    cmp     $2, %rax
    jb      9f
    API_LIT api_v_end
    movq    $0, (NodeEvent_api + 16 + 64)(%rbp)
    incq    (NodeEvent_api + 16 + 8)(%rbp)
    jmp     1b
7:  mov     $2, %eax
    UNFRAME 48
8:  mov     %r14, %rax                      # all: ]}
    sub     %r12, %rax
    cmp     $2, %rax
    jb      9f
    API_LIT api_v_end
    mov     $1, %eax
    UNFRAME 48
9:  xor     %eax, %eax
    UNFRAME 48
END_FUNCTION lantern_api_committees_json

# rax = the new id of a NODE_ACT_BYTES_PUT of the ValidatorRef items of the validator operation of
# the route rdi (getStateValidator: its validator_id), or 0 with none (node.md, NODE_EV_API).
# Locals: a ByteList head whose offset reaches the items.
LOCAL_FUNCTION lantern_node_api_ids
    FRAME 32
    cmpq    $API_OP_GET_STATE_VALIDATOR, ApiRoute_op(%rdi)
    jne     1f
    lea     ApiRoute_validator(%rdi), %rax
    mov     $64, %ecx
    jmp     2f
1:  mov     ApiRoute_list(%rdi), %rax
    add     %rdi, %rax
    mov     (ApiRoute_list + 8)(%rdi), %rcx
    shl     $6, %rcx
    jnz     2f
    xor     %eax, %eax
    UNFRAME 32
2:  mov     %rsp, %rdi
    sub     %rdi, %rax
    mov     %rcx, (%rdi)
    mov     %rax, 8(%rdi)
    mov     %rcx, 16(%rdi)
    call    lantern_node_put
    UNFRAME 32
END_FUNCTION lantern_node_api_ids

LOCAL_FUNCTION lantern_api_body
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    cmp     $API_BODY_ERROR, %rsi
    jne     1f
    # {"code":<n>,"message":"<m>"}
    API_LIT api_e_code
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_dec
    API_LIT api_e_message
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_code
    mov     %rax, %rdi
    mov     $24, %esi
    call    lantern_api_code_text
    API_LIT api_e_end
    UNFRAME 16
1:  cmp     $API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE, %rsi
    jne     102f
    call    lantern_api_lc_updates_body
    UNFRAME 16
102: lea    -API_OP_GET_LIGHT_CLIENT_BOOTSTRAP(%rsi), %rax   # the light client reads: SSZ, or {"version":…,"data":…}
    cmp     $(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP), %rax
    ja      10f
    cmpq    $0, ApiView_lc_json(%rbp)
    jne     101f
    mov     ApiView_lc_bytes(%rbp), %rax
    mov     8(%rax), %rdi
    add     %rax, %rdi
    mov     16(%rax), %rsi
    call    lantern_api_put
    UNFRAME 16
101: API_LIT api_j_version
    mov     ApiView_fork(%rbp), %rdi
    call    lantern_api_fork_name
    API_LIT api_g_data
    mov     ApiView_lc_json(%rbp), %rax
    mov     8(%rax), %rdi
    add     %rax, %rdi
    mov     16(%rax), %rsi
    call    lantern_api_put
    API_LIT api_end1
    UNFRAME 16
10: mov     8(%rsp), %rsi
    cmp     $API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE, %rsi
    jne     11f
    # {"code":400,"message":"BAD_REQUEST","failures":[…]}: rbp the event of the work
    API_LIT api_e_code
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_dec
    API_LIT api_e_message
    mov     (%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_code
    mov     %rax, %rdi
    mov     $24, %esi
    call    lantern_api_code_text
    API_LIT api_f_list
    call    lantern_api_failures
    UNFRAME 16
11: mov     8(%rsp), %rsi
    cmp     $API_OP_GET_PEERS, %rsi
    jne     116f
    call    lantern_api_peers_body
    UNFRAME 16
116: cmp    $API_OP_GET_PEER, %rsi
    jne     117f
    API_LIT api_pe_data
    mov     ApiView_peer(%rbp), %rdi
    call    lantern_api_peer_item
    API_LIT api_end1
    UNFRAME 16
117: mov    8(%rsp), %rsi
    cmp     $API_OP_GET_DEBUG_CHAIN_HEADS_V2, %rsi
    jne     110f
    call    lantern_api_heads_body
    UNFRAME 16
110: cmp    $API_OP_GET_DEBUG_FORK_CHOICE, %rsi
    jne     115f
    call    lantern_api_fork_choice_body
    UNFRAME 16
115: cmp    $API_OP_GET_STATE_RANDAO, %rsi
    je      113f
    cmp     $API_OP_GET_EPOCH_SYNC_COMMITTEES, %rsi
    je      113f
    cmp     $API_OP_GET_PROPOSER_LOOKAHEAD, %rsi
    jne     114f
113: mov    (%rsp), %rdi                    # the state reads
    call    lantern_api_state_read_body
    UNFRAME 16
114: cmp    $API_OP_PRODUCE_ATTESTATION_DATA, %rsi
    jne     12f
    mov     (%rsp), %rax                    # SSZ: its 128 bytes
    testq   $API_R_SSZ, 8(%rax)
    jz      13f
    lea     ApiView_att(%rbp), %rdi
    mov     $128, %esi
    call    lantern_api_put
    UNFRAME 16
    # {"data":{"slot":…,"index":…,"beacon_block_root":…,"source":…,"target":…}}
13: API_LIT api_a_slot
    mov     ApiView_att(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_a_index
    mov     (ApiView_att + 8)(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_a_root
    lea     (ApiView_att + 16)(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_a_source
    lea     (ApiView_att + 48)(%rbp), %rdi
    call    lantern_api_checkpoint
    API_LIT api_a_target
    lea     (ApiView_att + 88)(%rbp), %rdi
    call    lantern_api_checkpoint
    API_LIT api_end2
    UNFRAME 16
12: cmp     $API_OP_GET_NETWORK_IDENTITY, %rsi
    jne     2f
    API_LIT api_i_peer_id
    lea     ApiView_peer_id(%rbp), %rdi
    call    lantern_api_text
    API_LIT api_i_enr
    lea     ApiView_enr(%rbp), %rdi
    call    lantern_api_text
    API_LIT api_i_p2p
    cmpq    $0, ApiView_p2p_address(%rbp)
    je      14f
    lea     ApiView_p2p_address(%rbp), %rdi
    call    lantern_api_text
14: API_LIT api_i_discovery
    cmpq    $0, ApiView_discovery_address(%rbp)
    je      15f
    lea     ApiView_discovery_address(%rbp), %rdi
    call    lantern_api_text
15: API_LIT api_i_seq
    mov     ApiView_seq_number(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_i_attnets
    lea     ApiView_attnets(%rbp), %rdi
    mov     $8, %esi
    call    lantern_api_qhex
    cmpq    $FORK_ALTAIR, ApiView_fork(%rbp)
    jb      16f
    API_LIT api_i_syncnets
    lea     ApiView_syncnets(%rbp), %rdi
    mov     $1, %esi
    call    lantern_api_qhex
    cmpq    $FORK_FULU, ApiView_fork(%rbp)
    jb      16f
    API_LIT api_i_cgc
    mov     ApiView_custody_group_count(%rbp), %rdi
    call    lantern_api_qdec
16: API_LIT api_end3
    UNFRAME 16
2:  cmp     $API_OP_GET_NODE_VERSION, %rsi
    jne     3f
    API_LIT api_v_version
    lea     ApiView_version(%rbp), %rdi
    call    lantern_api_text
    API_LIT api_end2
    UNFRAME 16
3:  cmp     $API_OP_GET_SYNCING_STATUS, %rsi
    jne     4f
    API_LIT api_s_head
    mov     ApiView_head_slot(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_s_distance
    mov     ApiView_current_slot(%rbp), %rdi
    sub     ApiView_head_slot(%rbp), %rdi
    jae     31f
    xor     %edi, %edi
31: call    lantern_api_qdec
    API_LIT api_s_syncing
    mov     ApiView_is_syncing(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_s_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_s_offline
    mov     ApiView_el_offline(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_end2
    UNFRAME 16
4:  cmp     $API_OP_GET_PEER_COUNT, %rsi
    jne     5f
    API_LIT api_c_connected
    mov     ApiView_peers(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  cmp     $API_OP_GET_GENESIS, %rsi
    jne     6f
    API_LIT api_g_time
    mov     ApiView_genesis_time(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_g_root
    lea     ApiView_genesis_validators_root(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_g_version
    lea     ApiView_genesis_fork_version(%rbp), %rdi
    mov     $4, %esi
    call    lantern_api_qhex
    API_LIT api_end2
    UNFRAME 16
6:  cmp     $API_OP_GET_BLOCK_HEADER, %rsi
    jne     7f
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     ApiView_head_finalized(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_data
    API_LIT api_h_root
    lea     ApiView_head_root(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    mov     ApiView_head_slot(%rbp), %rdi
    lea     ApiView_proposer_index(%rbp), %rsi
    mov     ApiView_canonical(%rbp), %rdx
    call    lantern_api_header_json
    API_LIT api_end3
    UNFRAME 16
7:  cmp     $API_OP_GET_STATE_FINALITY_CHECKPOINTS, %rsi
    jne     9f
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     ApiView_head_finalized(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_data
    API_LIT api_f_previous
    lea     ApiView_previous_justified(%rbp), %rdi
    call    lantern_api_checkpoint
    API_LIT api_f_current
    lea     ApiView_current_justified(%rbp), %rdi
    call    lantern_api_checkpoint
    API_LIT api_f_finalized
    lea     ApiView_finalized(%rbp), %rdi
    call    lantern_api_checkpoint
    API_LIT api_end2
    UNFRAME 16
9:  cmp     $API_OP_GET_BLOCK_ROOT, %rsi    # getBlockRoot, getStateRoot: {"execution_optimistic":…,"finalized":…,"data":{"root":…}}
    je      10f
    cmp     $API_OP_GET_STATE_ROOT, %rsi
    je      10f
    cmp     $API_OP_GET_STATE_FORK, %rsi
    jne     12f
10: mov     %rsi, 8(%rsp)
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     ApiView_head_finalized(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_data
    cmpq    $API_OP_GET_STATE_FORK, 8(%rsp)
    je      11f
    API_LIT api_h_root
    lea     ApiView_head_root(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_end2
    UNFRAME 16
    # getStateFork: {"previous_version":…,"current_version":…,"epoch":…}
11: API_LIT api_k_previous
    lea     ApiView_state_fork(%rbp), %rdi
    mov     $4, %esi
    call    lantern_api_qhex
    API_LIT api_k_current
    lea     (ApiView_state_fork + 4)(%rbp), %rdi
    mov     $4, %esi
    call    lantern_api_qhex
    API_LIT api_k_epoch
    mov     (ApiView_state_fork + 8)(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_end2
    UNFRAME 16
12: cmp     $API_OP_GET_SPEC, %rsi
    jne     13f
    call    lantern_api_spec
    UNFRAME 16
13: cmp     $API_OP_GET_FORK_SCHEDULE, %rsi
    jne     17f
    call    lantern_api_fork_schedule
    UNFRAME 16
17: cmp     $API_OP_GET_DEPOSIT_CONTRACT, %rsi  # {"data":{"chain_id":…,"address":…}}
    jne     18f
    API_LIT api_d_chain
    mov     ApiView_config(%rbp), %rax
    mov     CONFIG_DEPOSIT_CHAIN_ID(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_d_address
    mov     ApiView_config(%rbp), %rdi
    add     $CONFIG_DEPOSIT_CONTRACT_ADDRESS, %rdi
    mov     $20, %esi
    call    lantern_api_qhex
    API_LIT api_end2
    UNFRAME 16
18: cmp     $API_OP_GET_STATE_VALIDATOR, %rsi   # {"execution_optimistic":…,"finalized":…,"data":<item>}
    jne     19f
    API_LIT api_v_open
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     ApiView_head_finalized(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_v_data
    mov     ApiView_val_state(%rbp), %rdi
    mov     ApiView_val_index(%rbp), %rsi
    xor     %edx, %edx
    call    lantern_api_validator_item
    API_LIT api_end1
    UNFRAME 16
    # getProposerDuties and getProposerDutiesV2: {"dependent_root":…,"execution_optimistic":…,"data":[{"pubkey":…,"validator_index":…,"slot":…},…]}
19: cmp     $API_OP_GET_PROPOSER_DUTIES, %rsi
    je      190f
    cmp     $API_OP_GET_PROPOSER_DUTIES_V2, %rsi
    jne     18f
190: API_LIT api_u_root
    lea     ApiView_duties(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_u_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_v_list
    movq    $0, 8(%rsp)                     # the slot's place in the epoch
20: mov     8(%rsp), %rax
    cmp     $SLOTS_PER_EPOCH, %rax
    jae     21f
    mov     ApiView_val_state(%rbp), %rcx
    add     NODE_STATE_SLOT(%rcx), %rax     # the slot; slot 0 has no item: its block is the genesis block
    jz      23f
    cmp     $1, %rax                        # a comma before each item past the first: past the epoch's first slot and past slot 1
    jbe     22f
    cmpq    $0, 8(%rsp)
    je      22f
    API_LIT api_p_comma
22: API_LIT api_u_pubkey
    mov     ApiView_val_state(%rbp), %rdi
    PART    %rax, %rcx, %rdi, NODE_STATE_VALIDATORS
    mov     8(%rsp), %rcx
    mov     (ApiView_duties + 32)(%rbp,%rcx,8), %rsi
    shl     $7, %rsi                        # NODE_VALIDATOR_MEM: the pubkey first
    lea     (%rax,%rsi), %rdi
    mov     $48, %esi
    call    lantern_api_qhex
    API_LIT api_u_index
    mov     8(%rsp), %rcx
    mov     (ApiView_duties + 32)(%rbp,%rcx,8), %rdi
    call    lantern_api_qdec
    API_LIT api_c_slot
    mov     ApiView_val_state(%rbp), %rax
    mov     NODE_STATE_SLOT(%rax), %rdi
    add     8(%rsp), %rdi
    call    lantern_api_qdec
    API_LIT api_end1
23: incq    8(%rsp)
    jmp     20b
21: API_LIT api_v_end
    UNFRAME 16
18: cmp     $API_OP_GET_SYNC_COMMITTEE_DUTIES, %rsi
    jne     181f
    call    lantern_api_sync_duties_body
    UNFRAME 16
181: cmp    $API_OP_GET_ATTESTER_DUTIES, %rsi
    jne     182f
    call    lantern_api_duties_json
    UNFRAME 16
182: cmp    $API_OP_GET_LIVENESS, %rsi      # getLiveness: {"data":[{"index":…,"is_live":…},…]}
    jne     183f
    call    lantern_api_liveness_body
    UNFRAME 16
183: cmp    $API_OP_GET_BLOCK_REWARDS, %rsi # getBlockRewards and getSyncCommitteeRewards
    jne     184f
    call    lantern_api_rewards_body
    UNFRAME 16
184: cmp    $API_OP_GET_SYNC_COMMITTEE_REWARDS, %rsi
    jne     99f
    call    lantern_api_sync_rewards_body
99: UNFRAME 16
END_FUNCTION lantern_api_body

# rax = 1 when the ValidatorRef items of the ByteList rdx name the validator rdi of the state rsi, by its index or its pubkey, else 0. A leaf. Uses rax, rcx, r8-r11.
LOCAL_FUNCTION lantern_api_names
    UNWIND_END_PROLOGUE
    PART    %r8, %r9, %rsi, NODE_STATE_VALIDATORS
    imul    $NODE_VALIDATOR_MEM, %rdi, %rax
    add     %rax, %r8                       # the validator's pubkey
    mov     8(%rdx), %r10
    add     %rdx, %r10
    mov     16(%rdx), %r11
    shr     $6, %r11
1:  test    %r11, %r11
    jz      8f
    cmpq    $API_VALIDATOR_INDEX, (%r10)
    jne     2f
    cmp     8(%r10), %rdi
    je      9f
    jmp     3f
2:  xor     %ecx, %ecx
21: mov     (%r8,%rcx), %rax
    cmp     ValidatorRef_pubkey(%r10,%rcx), %rax
    jne     3f
    add     $8, %rcx
    cmp     $48, %rcx
    jb      21b
    jmp     9f
3:  add     $64, %r10
    dec     %r11
    jmp     1b
8:  xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION lantern_api_names

# The signed (two's complement) rdi in decimal, in quotes, with - before a value below 0. Locals: rdi.
LOCAL_FUNCTION lantern_api_qint
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_quote
    mov     (%rsp), %rdi
    test    %rdi, %rdi
    jns     1f
    API_LIT api_rw_minus
    mov     (%rsp), %rdi
    neg     %rdi
1:  call    lantern_api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION lantern_api_qint

.macro REWARD_FIELD text, off
    API_LIT \text
    mov     ApiView_live_out(%rbp), %rax
    mov     \off(%rax), %rdi
    call    lantern_api_qdec
.endm

# The body of getBlockRewards (beacon-api.md) from the view rbp: {"execution_optimistic":…,"finalized":…,"data":{"proposer_index":…,
# "total":…,"attestations":…,"sync_aggregate":…,"proposer_slashings":…,"attester_slashings":…}} of the 48 bytes of
# lantern_node_block_rewards at ApiView_live_out.
LOCAL_FUNCTION lantern_api_rewards_body
    FRAME 0
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     ApiView_head_finalized(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_data
    REWARD_FIELD api_rw_proposer, 0
    REWARD_FIELD api_rw_total, 8
    REWARD_FIELD api_rw_attestations, 16
    REWARD_FIELD api_rw_sync, 24
    REWARD_FIELD api_rw_proposer_slashings, 32
    REWARD_FIELD api_rw_attester_slashings, 40
    API_LIT api_end2
    UNFRAME 0
END_FUNCTION lantern_api_rewards_body

# The body of getSyncCommitteeRewards (beacon-api.md) from the view rbp: {"execution_optimistic":…,"finalized":…,"data":[
# {"validator_index":…,"reward":…},…]} of the items of lantern_node_sync_rewards at ApiView_live_out; with ValidatorRef
# items at ApiView_sd_ids, those of the validators of ApiView_val_state that one names. Locals: the item, the items written.
LOCAL_FUNCTION lantern_api_sync_rewards_body
    FRAME 16
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     ApiView_head_finalized(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_v_list
    movq    $0, (%rsp)
    movq    $0, 8(%rsp)
1:  mov     ApiView_live_out(%rbp), %rax
    mov     16(%rax), %rcx
    shr     $4, %rcx
    mov     (%rsp), %rdx
    cmp     %rcx, %rdx
    jae     9f
    mov     8(%rax), %rcx
    add     %rax, %rcx
    shl     $4, %rdx
    mov     (%rcx,%rdx), %rdi
    mov     ApiView_sd_ids(%rbp), %rdx
    test    %rdx, %rdx
    jz      2f
    mov     ApiView_val_state(%rbp), %rsi
    call    lantern_api_names
    test    %rax, %rax
    jz      5f
2:  cmpq    $0, 8(%rsp)
    je      3f
    API_LIT api_p_comma
3:  API_LIT api_q_validator
    mov     ApiView_live_out(%rbp), %rax
    mov     8(%rax), %rcx
    add     %rax, %rcx
    mov     (%rsp), %rdx
    shl     $4, %rdx
    mov     (%rcx,%rdx), %rdi
    call    lantern_api_qdec
    API_LIT api_rw_reward
    mov     ApiView_live_out(%rbp), %rax
    mov     8(%rax), %rcx
    add     %rax, %rcx
    mov     (%rsp), %rdx
    shl     $4, %rdx
    mov     8(%rcx,%rdx), %rdi
    call    lantern_api_qint
    API_LIT api_end1
    incq    8(%rsp)
5:  incq    (%rsp)
    jmp     1b
9:  API_LIT api_v_end
    UNFRAME 16
END_FUNCTION lantern_api_sync_rewards_body

/*
 * The body of getLiveness (beacon-api.md) from the view rbp: {"data":[{"index":…,"is_live":…},…]}
 * of the ValidatorRef items at ApiView_sd_ids, each by its byte at ApiView_live_out. Locals: the
 * item's index.
 */
LOCAL_FUNCTION lantern_api_liveness_body
    FRAME 16
    API_LIT api_p_data
    movq    $0, (%rsp)
1:  mov     ApiView_sd_ids(%rbp), %rax
    mov     16(%rax), %rcx
    shr     $6, %rcx
    mov     (%rsp), %rdx
    cmp     %rcx, %rdx
    jae     9f
    test    %rdx, %rdx
    jz      2f
    API_LIT api_p_comma
2:  API_LIT api_l_index
    mov     ApiView_sd_ids(%rbp), %rax
    mov     8(%rax), %rcx
    add     %rax, %rcx
    mov     (%rsp), %rdx
    shl     $6, %rdx
    mov     8(%rcx,%rdx), %rdi
    call    lantern_api_qdec
    API_LIT api_l_live
    mov     ApiView_live_out(%rbp), %rax
    mov     (%rsp), %rdx
    movzbl  (%rax,%rdx), %edi
    call    lantern_api_bool
    API_LIT api_end1
    incq    (%rsp)
    jmp     1b
9:  API_LIT api_v_end
    UNFRAME 16
END_FUNCTION lantern_api_liveness_body

/*
 * The JSON of getAttesterDuties from the view rbp: {"dependent_root":…,"execution_optimistic":…,
 * "data":[{"pubkey":…,…,"slot":…},…]}, an item for each record with an assignment. Locals: a
 * record's place, the items written, the record.
 */
LOCAL_FUNCTION lantern_api_duties_json
    FRAME 32
    API_LIT api_u_root
    mov     ApiView_ad_out(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_u_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_v_list
    movq    $0, (%rsp)
    movq    $0, 8(%rsp)
1:  mov     (%rsp), %rax
    cmp     ApiView_ad_count(%rbp), %rax
    jae     9f
    imul    $48, %rax, %rax
    add     ApiView_ad_out(%rbp), %rax
    add     $40, %rax
    mov     %rax, 16(%rsp)
    cmpq    $0, (%rax)
    je      8f
    cmpq    $0, 8(%rsp)
    je      2f
    API_LIT api_p_comma
2:  incq    8(%rsp)
    API_LIT api_u_pubkey
    mov     ApiView_val_state(%rbp), %rdi
    PART    %rax, %rcx, %rdi, NODE_STATE_VALIDATORS
    mov     16(%rsp), %rcx
    mov     40(%rcx), %rsi
    shl     $7, %rsi                        # NODE_VALIDATOR_MEM: the pubkey first
    lea     (%rax,%rsi), %rdi
    mov     $48, %esi
    call    lantern_api_qhex
    API_LIT api_u_index
    mov     16(%rsp), %rax
    mov     40(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_t_committee_index
    mov     16(%rsp), %rax
    mov     16(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_t_committee_length
    mov     16(%rsp), %rax
    mov     24(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_t_committees_at_slot
    mov     ApiView_ad_out(%rbp), %rax
    mov     32(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_t_validator_committee_index
    mov     16(%rsp), %rax
    mov     32(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_c_slot
    mov     16(%rsp), %rax
    mov     8(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_end1
8:  incq    (%rsp)
    jmp     1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION lantern_api_duties_json

/*
 * L1: the body of getDebugChainHeadsV2 (beacon-api.md): {"data":[{"root":…,"slot":…,"execution_optimistic":…},…]}
 * of the store nodes at ApiView_val_state of the view rbp whose byte at ApiView_heads is 0. Locals: the
 * index, 1 once an item is written, the node.
 */
LOCAL_FUNCTION lantern_api_heads_body
    FRAME 32
    API_LIT api_p_data
    movq    $0, (%rsp)
    movq    $0, 8(%rsp)
1:  mov     ApiView_val_state(%rbp), %rax
    mov     (%rsp), %rcx
    cmp     (Store_blocks + 8)(%rax), %rcx
    jae     9f
    mov     ApiView_heads(%rbp), %rdx
    cmpb    $0, (%rdx,%rcx)
    jne     8f
    cmpq    $0, 8(%rsp)
    je      2f
    API_LIT api_p_comma
2:  movq    $1, 8(%rsp)
    API_LIT api_ch_root
    mov     ApiView_val_state(%rbp), %rax
    mov     Store_blocks(%rax), %rdi
    add     %rax, %rdi
    imul    $BlockNode__mem, (%rsp), %rcx
    add     %rcx, %rdi
    mov     %rdi, 16(%rsp)
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_q_slot
    mov     16(%rsp), %rax
    mov     BlockNode_slot(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_ch_optimistic
    mov     16(%rsp), %rax
    xor     %edi, %edi
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, BlockNode_payload_status(%rax)
    sete    %dil
    call    lantern_api_bool
    API_LIT api_end1
8:  incq    (%rsp)
    jmp     1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION lantern_api_heads_body

/*
 * L1: the body of getDebugForkChoice (beacon-api.md): {"justified_checkpoint":…,"finalized_checkpoint":…,
 * "fork_choice_nodes":[…]} of the store at ApiView_val_state of the view rbp, each node's weight at
 * ApiView_weights. Locals: the index, the node.
 */
LOCAL_FUNCTION lantern_api_fork_choice_body
    FRAME 16
    API_LIT api_fc_justified
    mov     ApiView_val_state(%rbp), %rdi
    add     $Store_justified_checkpoint, %rdi
    call    lantern_api_checkpoint
    API_LIT api_fc_finalized
    mov     ApiView_val_state(%rbp), %rdi
    add     $Store_finalized_checkpoint, %rdi
    call    lantern_api_checkpoint
    API_LIT api_fc_nodes
    movq    $0, (%rsp)
1:  mov     ApiView_val_state(%rbp), %rax
    mov     (%rsp), %rcx
    cmp     (Store_blocks + 8)(%rax), %rcx
    jae     9f
    test    %rcx, %rcx
    jz      2f
    API_LIT api_p_comma
2:  mov     ApiView_val_state(%rbp), %rax
    mov     Store_blocks(%rax), %rdi
    add     %rax, %rdi
    imul    $BlockNode__mem, (%rsp), %rcx
    add     %rcx, %rdi
    mov     %rdi, 8(%rsp)
    API_LIT api_fc_slot
    mov     8(%rsp), %rax
    mov     BlockNode_slot(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_fc_block_root
    mov     8(%rsp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_h_parent
    mov     8(%rsp), %rdi
    add     $BlockNode_parent_root, %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_fc_justified_epoch
    mov     8(%rsp), %rax
    mov     BlockNode_justified_checkpoint(%rax), %rdi   # its epoch, the Checkpoint's first field
    call    lantern_api_qdec
    API_LIT api_fc_finalized_epoch
    mov     8(%rsp), %rax
    mov     BlockNode_finalized_epoch(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_fc_weight
    mov     ApiView_weights(%rbp), %rax
    mov     (%rsp), %rcx
    mov     (%rax,%rcx,8), %rdi
    call    lantern_api_qdec
    API_LIT api_fc_validity
    mov     8(%rsp), %rax
    mov     BlockNode_payload_status(%rax), %rax
    cmp     $PAYLOAD_STATUS_NOT_VALIDATED, %rax
    je      3f
    cmp     $PAYLOAD_STATUS_INVALIDATED, %rax
    je      4f
    API_LIT api_fc_valid
    jmp     5f
3:  API_LIT api_fc_optimistic
    jmp     5f
4:  API_LIT api_fc_invalid
5:  API_LIT api_fc_hash
    mov     8(%rsp), %rdi
    add     $BlockNode_block_hash, %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_end1
    incq    (%rsp)
    jmp     1b
9:  API_LIT api_v_end
    UNFRAME 16
END_FUNCTION lantern_api_fork_choice_body

# ,"canonical":…,"header":{"message":{"slot":…,"proposer_index":…,"parent_root":…,"state_root":…,"body_root":…},"signature":…
# of the slot rdi, canonical rdx, and at rsi the header's proposer_index, parent_root, state_root,
# body_root and signature, in that order. Locals: rdi, rsi, rdx.
LOCAL_FUNCTION lantern_api_header_json
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    API_LIT api_h_canonical
    mov     16(%rsp), %rdi
    call    lantern_api_bool
    API_LIT api_h_slot
    mov     (%rsp), %rdi
    call    lantern_api_qdec
    API_LIT api_h_proposer
    mov     8(%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_h_parent
    mov     8(%rsp), %rdi
    add     $(ApiView_parent_root - ApiView_proposer_index), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_h_state
    mov     8(%rsp), %rdi
    add     $(ApiView_state_root - ApiView_proposer_index), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_h_body
    mov     8(%rsp), %rdi
    add     $(ApiView_body_root - ApiView_proposer_index), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_h_signature
    mov     8(%rsp), %rdi
    add     $(ApiView_signature - ApiView_proposer_index), %rdi
    mov     $96, %esi
    call    lantern_api_qhex
    UNFRAME 32
END_FUNCTION lantern_api_header_json
.if ApiView_parent_root - ApiView_proposer_index != 8 || ApiView_state_root - ApiView_proposer_index != 40 || ApiView_body_root - ApiView_proposer_index != 72 || ApiView_signature - ApiView_proposer_index != 104
.error "api_header_json reads the fields of a SignedBeaconBlockHeader after its slot"
.endif

# getBlockHeaders' JSON, as lantern_api_stream_json: with rdi, the address of an item's header (its slot,
# then the fields lantern_api_header_json reads), the item {"root":…,"canonical":…,"header":…}, its root at
# byte 0 of the entry rbx's cursor and canonical bit 0 of its member, after , when API_STREAM_ITEMS
# is set; then API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event rbp. With rdi = 0: ]}. rax = 1
# when the answer is whole, else 0. Locals: rdi.
LOCAL_FUNCTION lantern_api_headers_json
    FRAME 16
    mov     %rdi, (%rsp)
    test    %rdi, %rdi
    jnz     1f
    API_LIT api_v_end
    mov     $1, %eax
    UNFRAME 16
1:  testq   $API_STREAM_ITEMS, (NodeEvent_api + 8)(%rbp)
    jz      2f
    API_LIT api_p_comma
2:  API_LIT api_ch_root
    lea     NodeApi_cursor(%rbx), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    mov     (%rsp), %rsi
    mov     (%rsi), %rdi
    add     $8, %rsi
    mov     NodeApi_member(%rbx), %rdx
    and     $1, %edx
    call    lantern_api_header_json
    API_LIT api_end2
    orq     $(API_STREAM_ITEMS | API_STREAM_ITEM_DONE), (NodeEvent_api + 8)(%rbp)
    xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_api_headers_json

/*
 * L2: rax = the base58btc text of the rsi bytes at rdi (at most 48), written at rdx: a 1 for each
 * leading zero byte, then the digits. rcx: a work area of 72 bytes. r12 the bytes, r13 their count,
 * r14 the text, r15 the work area, rbp the leading zero bytes.
 */
LOCAL_FUNCTION lantern_api_base58
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
    ADDRESS %rsi, api_base58_digits
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
END_FUNCTION lantern_api_base58

# A peer of getPeers and getPeer (beacon-api.md): {"peer_id":…,"enr":null,"last_seen_p2p_address":…,
# "state":"connected","direction":…} of the NodePeer rdi. Locals: the peer, the text's length, an
# index, the text (72 bytes), base58's work area (72 bytes).
LOCAL_FUNCTION lantern_api_peer_item
    FRAME 176
    mov     %rdi, (%rsp)
    lea     NodePeer_id(%rdi), %rdi
    mov     (%rsp), %rax
    mov     NodePeer_id_len(%rax), %rsi
    lea     24(%rsp), %rdx
    lea     96(%rsp), %rcx
    call    lantern_api_base58
    mov     %rax, 8(%rsp)
    API_LIT api_pe_open
    lea     24(%rsp), %rdi
    mov     8(%rsp), %rsi
    call    lantern_api_put
    API_LIT api_pe_enr
    mov     (%rsp), %rax
    cmpq    $6, NodePeer_address(%rax)      # the family
    je      3f
    # IPv4: 4 bytes in decimal, . between
    API_LIT api_pe_ip4
    movq    $0, 16(%rsp)
1:  mov     (%rsp), %rax
    mov     16(%rsp), %rcx
    movzbl  (NodePeer_address + 16)(%rax,%rcx), %edi
    call    lantern_api_dec
    incq    16(%rsp)
    cmpq    $4, 16(%rsp)
    jae     5f
    API_LIT api_pe_dot
    jmp     1b
    # IPv6: 8 groups of 16 bits, lower case hex with no leading zeros, : between
3:  API_LIT api_pe_ip6
    movq    $0, 16(%rsp)
4:  mov     (%rsp), %rax
    mov     16(%rsp), %rcx
    movzbl  (NodePeer_address + 16)(%rax,%rcx,2), %edi
    shl     $8, %edi
    movzbl  (NodePeer_address + 17)(%rax,%rcx,2), %edx
    or      %edx, %edi
    call    lantern_api_hex16
    incq    16(%rsp)
    cmpq    $8, 16(%rsp)
    jae     5f
    API_LIT api_pe_colon
    jmp     4b
5:  mov     (%rsp), %rax                    # the transport and its port
    cmpq    $LIBP2P_QUIC, NodePeer_transport(%rax)
    je      6f
    API_LIT api_pe_tcp
    mov     (%rsp), %rax
    mov     (NodePeer_address + 8)(%rax), %rdi
    call    lantern_api_dec
    jmp     7f
6:  API_LIT api_pe_udp
    mov     (%rsp), %rax
    mov     (NodePeer_address + 8)(%rax), %rdi
    call    lantern_api_dec
    API_LIT api_pe_quic
7:  API_LIT api_pe_p2p
    lea     24(%rsp), %rdi
    mov     8(%rsp), %rsi
    call    lantern_api_put
    API_LIT api_pe_state
    mov     (%rsp), %rax
    cmpq    $LIBP2P_OUTBOUND, NodePeer_direction(%rax)
    je      8f
    API_LIT api_pe_inbound
    UNFRAME 176
8:  API_LIT api_pe_outbound
    UNFRAME 176
END_FUNCTION lantern_api_peer_item

# The lower case hex digits of the 16 bits rdi, with no leading zeros, join the response. Locals: rdi, a shift.
LOCAL_FUNCTION lantern_api_hex16
    FRAME 16
    mov     %rdi, (%rsp)
    mov     $12, %ecx
1:  test    %ecx, %ecx                      # the leading zero digits but the last
    jz      2f
    mov     %rdi, %rax
    shr     %cl, %rax
    test    %rax, %rax
    jnz     2f
    sub     $4, %ecx
    jmp     1b
2:  mov     %rcx, 8(%rsp)
3:  mov     (%rsp), %rax
    mov     8(%rsp), %rcx
    shr     %cl, %rax
    and     $15, %eax
    ADDRESS %rdi, api_hex
    add     %rax, %rdi
    mov     $1, %esi
    call    lantern_api_put
    mov     8(%rsp), %rcx
    test    %rcx, %rcx
    jz      9f
    sub     $4, %rcx
    mov     %rcx, 8(%rsp)
    jmp     3b
9:  UNFRAME 16
END_FUNCTION lantern_api_hex16

# getPeers' body (beacon-api.md): {"data":[<peer>,…],"meta":{"count":…}} of the NodePeers of the
# Node at ApiView_node of the view rbp whose state and direction are in the sets at
# ApiView_peer_states and ApiView_peer_directions. Locals: the index, the count, the peer.
LOCAL_FUNCTION lantern_api_peers_body
    FRAME 32
    API_LIT api_p_data
    movq    $0, (%rsp)
    movq    $0, 8(%rsp)
1:  mov     ApiView_node(%rbp), %rax
    PART    %rcx, %rdx, %rax, Node_peers
    mov     (%rsp), %rax
    cmp     %rdx, %rax
    jae     9f
    imul    $NodePeer__mem, %rax, %rax
    add     %rcx, %rax
    incq    (%rsp)
    testq   $(1 << API_PEER_CONNECTED), ApiView_peer_states(%rbp)  # connected
    jz      1b
    mov     NodePeer_direction(%rax), %rcx
    mov     ApiView_peer_directions(%rbp), %rdx
    shr     %cl, %rdx
    test    $1, %edx
    jz      1b
    mov     %rax, 16(%rsp)
    cmpq    $0, 8(%rsp)
    je      2f
    API_LIT api_p_comma
2:  incq    8(%rsp)
    mov     16(%rsp), %rdi
    call    lantern_api_peer_item
    jmp     1b
9:  API_LIT api_pe_meta
    mov     8(%rsp), %rdi
    call    lantern_api_dec
    API_LIT api_end2
    UNFRAME 32
END_FUNCTION lantern_api_peers_body
.if API_DIRECTION_INBOUND != LIBP2P_INBOUND || API_DIRECTION_OUTBOUND != LIBP2P_OUTBOUND
.error "api_peers_body: the direction bits are the libp2p directions"
.endif

# (route rdi) -> rax: the NodePeer whose peer ID's base58btc text is the route's peer_id, or 0. rbx
# the node. Locals: the route, the index, the text (72 bytes), base58's work area (72 bytes).
LOCAL_FUNCTION lantern_node_api_find_peer
    FRAME 176
    mov     %rdi, (%rsp)
    movq    $0, 8(%rsp)
1:  PART    %rcx, %rdx, %rbx, Node_peers
    mov     8(%rsp), %rax
    cmp     %rdx, %rax
    jae     8f
    imul    $NodePeer__mem, %rax, %rax
    add     %rcx, %rax
    incq    8(%rsp)
    lea     NodePeer_id(%rax), %rdi
    mov     NodePeer_id_len(%rax), %rsi
    lea     24(%rsp), %rdx
    lea     96(%rsp), %rcx
    call    lantern_api_base58
    mov     (%rsp), %rdi
    PART    %rsi, %rdx, %rdi, ApiRoute_peer_id
    cmp     %rdx, %rax
    jne     1b
    xor     %ecx, %ecx
2:  cmp     %rdx, %rcx
    jae     3f
    movzbl  24(%rsp,%rcx), %eax
    cmpb    %al, (%rsi,%rcx)
    jne     1b
    inc     %rcx
    jmp     2b
3:  PART    %rcx, %rdx, %rbx, Node_peers    # that peer
    mov     8(%rsp), %rax
    dec     %rax
    imul    $NodePeer__mem, %rax, %rax
    add     %rcx, %rax
    UNFRAME 176
8:  xor     %eax, %eax
    UNFRAME 176
END_FUNCTION lantern_node_api_find_peer

/*
 * The body of getSyncCommitteeDuties (beacon-api.md): {"execution_optimistic":…,"data":[{"pubkey":…,
 * "validator_index":…,"validator_sync_committee_indices":[…]},…]} of the ValidatorRef items at
 * ApiView_sd_ids of the view rbp, each by its places in the committee at ApiView_sync_out, the pubkeys
 * those of the state at ApiView_val_state. Locals: the item's index, the items written, the
 * validator, the place, its places written.
 */
LOCAL_FUNCTION lantern_api_sync_duties_body
    FRAME 48
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_v_list
    movq    $0, (%rsp)
    movq    $0, 8(%rsp)
1:  mov     ApiView_sd_ids(%rbp), %rax      # each item: a validator index the state has
    mov     16(%rax), %rcx
    shr     $6, %rcx
    mov     (%rsp), %rdx
    cmp     %rcx, %rdx
    jae     9f
    incq    (%rsp)
    mov     8(%rax), %rcx
    add     %rax, %rcx
    shl     $6, %rdx
    mov     8(%rcx,%rdx), %rdx
    mov     %rdx, 16(%rsp)
    mov     ApiView_val_state(%rbp), %rax
    PART    %rsi, %rcx, %rax, NODE_STATE_VALIDATORS
    cmp     %rcx, %rdx
    jae     1b
    movq    $0, 24(%rsp)                    # its places in the committee
    movq    $0, 32(%rsp)
2:  mov     24(%rsp), %rcx
    cmp     $SYNC_COMMITTEE_SIZE, %rcx
    jae     7f
    incq    24(%rsp)
    mov     ApiView_sync_out(%rbp), %rax
    mov     (%rax,%rcx,8), %rax
    cmp     16(%rsp), %rax
    jne     2b
    cmpq    $0, 32(%rsp)
    jne     5f
    cmpq    $0, 8(%rsp)                     # the first place: the item's head
    je      3f
    API_LIT api_p_comma
3:  incq    8(%rsp)
    API_LIT api_u_pubkey
    mov     ApiView_val_state(%rbp), %rax
    PART    %rdi, %rcx, %rax, NODE_STATE_VALIDATORS
    mov     16(%rsp), %rcx
    shl     $7, %rcx                        # NODE_VALIDATOR_MEM: the pubkey first
    add     %rcx, %rdi
    mov     $48, %esi
    call    lantern_api_qhex
    API_LIT api_u_index
    mov     16(%rsp), %rdi
    call    lantern_api_qdec
    API_LIT api_sd_indices
    jmp     6f
5:  API_LIT api_p_comma
6:  incq    32(%rsp)
    mov     24(%rsp), %rdi
    dec     %rdi
    call    lantern_api_qdec
    jmp     2b
7:  cmpq    $0, 32(%rsp)                    # places written: the item's end
    je      1b
    API_LIT api_v_end
    jmp     1b
9:  API_LIT api_v_end
    UNFRAME 48
END_FUNCTION lantern_api_sync_duties_body
.if NODE_VALIDATOR_MEM != 128
.error "api_sync_duties_body reads a pubkey at index * 128"
.endif

/*
 * The bodies of getStateRandao, getEpochSyncCommittees and getProposerLookahead (beacon-api.md), as
 * lantern_api_body: rdi its locals (flags at 8), rsi the kind, rbp the view. Locals: those, an index, the kind.
 */
LOCAL_FUNCTION lantern_api_state_read_body
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %rsi, 16(%rsp)
    cmp     $API_OP_GET_PROPOSER_LOOKAHEAD, %rsi
    je      30f
    # {"execution_optimistic":…,"finalized":…,"data":{
    API_LIT api_x_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     ApiView_head_finalized(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_data
    cmpq    $API_OP_GET_STATE_RANDAO, 16(%rsp)
    jne     10f
    # "randao":…}}
    API_LIT api_r_randao
    lea     ApiView_randao(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_end2
    UNFRAME 32
    # "validators":[…],"validator_aggregates":[[…],…]}}
10: API_LIT api_s_validators
    movq    $0, 8(%rsp)
11: mov     8(%rsp), %rax
    cmp     $SYNC_COMMITTEE_SIZE, %rax
    jae     13f
    test    %rax, %rax
    jz      12f
    API_LIT api_p_comma
12: mov     8(%rsp), %rax
    mov     ApiView_sync_out(%rbp), %rcx
    mov     (%rcx,%rax,8), %rdi
    call    lantern_api_qdec
    incq    8(%rsp)
    jmp     11b
13: API_LIT api_s_aggregates
    movq    $0, 8(%rsp)
14: mov     8(%rsp), %rax
    cmp     $SYNC_COMMITTEE_SIZE, %rax
    jae     18f
    test    $(SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT - 1), %eax
    jnz     16f
    test    %rax, %rax
    jz      15f
    API_LIT api_p_rbracket
    API_LIT api_p_comma
15: API_LIT api_p_lbracket
    jmp     17f
16: API_LIT api_p_comma
17: mov     8(%rsp), %rax
    mov     ApiView_sync_out(%rbp), %rcx
    mov     (%rcx,%rax,8), %rdi
    call    lantern_api_qdec
    incq    8(%rsp)
    jmp     14b
18: API_LIT api_p_rbracket
    API_LIT api_s_end
    UNFRAME 32
30: mov     (%rsp), %rax                    # getProposerLookahead: SSZ, its bytes
    testq   $API_R_SSZ, 8(%rax)
    jz      31f
    lea     ApiView_lookahead(%rbp), %rdi
    mov     $(8 * API_LOOKAHEAD_SLOTS), %esi
    call    lantern_api_put
    UNFRAME 32
    # {"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[…]}
31: API_LIT api_j_version
    mov     ApiView_fork(%rbp), %rdi
    call    lantern_api_fork_name
    API_LIT api_j_optimistic
    mov     ApiView_is_optimistic(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     ApiView_head_finalized(%rbp), %rdi
    call    lantern_api_bool
    API_LIT api_v_list
    movq    $0, 8(%rsp)
32: mov     8(%rsp), %rax
    cmp     $API_LOOKAHEAD_SLOTS, %rax
    jae     34f
    test    %rax, %rax
    jz      33f
    API_LIT api_p_comma
33: mov     8(%rsp), %rax
    mov     ApiView_lookahead(%rbp,%rax,8), %rdi
    call    lantern_api_qdec
    incq    8(%rsp)
    jmp     32b
34: API_LIT api_v_end
    UNFRAME 32
END_FUNCTION lantern_api_state_read_body

/*
 * (view rdi, out rsi, status rdx, body rcx, flags r8) -> rax: the HTTP response of beacon-api.md,
 * Common rules, into the ByteList out, its count set: the status line, its fields, then the body
 * of the kind body (0 none, API_BODY_ERROR, or an API_OP_*) from the ApiView view. flags:
 * API_R_CLOSE, API_R_KEEP, API_R_NO_REASON, and the allow bits from bit 8. rax = LANTERN_OK, or
 * LANTERN_BUFFER_TOO_SMALL when out has too little room. rbx out. Locals: L status, L+8 flags,
 * L+16 the body's bytes, L+24 the body's kind.
 */
LOCAL_FUNCTION lantern_api_respond
    ENTER 32
    mov     %rdi, %rbp
    mov     %rsi, %rbx
    mov     %rdx, L(%rsp)
    mov     %r8, (L + 8)(%rsp)
    mov     %rcx, (L + 24)(%rsp)
    xor     %r13d, %r13d                    # the body's bytes
    xor     %r12d, %r12d
    xor     %r15d, %r15d
    test    %rcx, %rcx
    jz      1f
    lea     L(%rsp), %rdi
    mov     %rcx, %rsi
    call    lantern_api_body
1:  mov     %r12, (L + 16)(%rsp)
    mov     $1, %r13d                       # the response
    lea     24(%rbx), %r12
    mov     (%rbx), %r14
    add     %rbx, %r14
    # HTTP/1.1 <code> <reason> CRLF
    API_LIT api_http
    mov     L(%rsp), %rdi
    call    lantern_api_dec
    API_LIT api_sp
    testq   $API_R_NO_REASON, (L + 8)(%rsp)
    jnz     2f
    mov     L(%rsp), %rdi
    call    lantern_api_code
    mov     %rax, %rdi
    mov     $8, %esi
    call    lantern_api_code_text
2:  API_LIT api_crlf
    cmpq    $0, (L + 16)(%rsp)
    je      3f
    testq   $API_R_SSZ, (L + 8)(%rsp)
    jnz     21f
    API_LIT api_type
    jmp     22f
21: API_LIT api_octet
22: testq   $API_R_VERSION, (L + 8)(%rsp)   # Eth-Consensus-Version of the view's fork
    jz      3f
    API_LIT api_version
    mov     ApiView_fork(%rbp), %rdi
    call    lantern_api_fork_name
    API_LIT api_crlf
3:  API_LIT api_length
    mov     (L + 16)(%rsp), %rdi
    call    lantern_api_dec
    API_LIT api_crlf
    cmpq    $405, L(%rsp)
    jne     5f
    # Allow: GET, POST or GET, POST
    API_LIT api_allow
    testq   $0x100, (L + 8)(%rsp)
    jz      4f
    API_LIT api_get
    testq   $0x200, (L + 8)(%rsp)
    jz      41f
    API_LIT api_comma
4:  testq   $0x200, (L + 8)(%rsp)
    jz      41f
    API_LIT api_post
41: API_LIT api_crlf
5:  testq   $API_R_CLOSE, (L + 8)(%rsp)
    jz      6f
    API_LIT api_close
    jmp     7f
6:  testq   $API_R_KEEP, (L + 8)(%rsp)
    jz      7f
    API_LIT api_keep
7:  API_LIT api_crlf
    cmpq    $0, (L + 24)(%rsp)
    je      8f
    lea     L(%rsp), %rdi
    mov     (L + 24)(%rsp), %rsi
    call    lantern_api_body
8:  test    %r15, %r15
    jnz     9f
    lea     24(%rbx), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    xor     %eax, %eax
    LEAVE 32
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
END_FUNCTION lantern_api_respond

/*
 * The values of the ApiView rdi that the node, rbx, and the store, rbp, give (beacon-api.md,
 * Common rules); the header and the checkpoints zero. Locals: the view.
 */
LOCAL_FUNCTION lantern_node_api_view
    FRAME 16
    mov     %rdi, (%rsp)
    mov     $ApiView__size, %esi
    call    lantern_zero
    mov     (%rsp), %rdi
    mov     Store_genesis_time_ms(%rbp), %rax
    xor     %edx, %edx
    mov     $1000, %ecx
    div     %rcx
    mov     %rax, ApiView_genesis_time(%rdi)
    lea     ApiView_genesis_validators_root(%rdi), %rax
    lea     Node_genesis_validators_root(%rbx), %rcx
    COPY32  %rax, %rcx
    mov     (Node_config + CONFIG_GENESIS_FORK_VERSION)(%rbx), %rax
    mov     %rax, ApiView_genesis_fork_version(%rdi)
    lea     Node_config(%rbx), %rax
    mov     %rax, ApiView_config(%rdi)
    lea     Node_head_root(%rbx), %rdi      # the head
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      1f
    mov     (%rsp), %rdi
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, ApiView_head_slot(%rdi)
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rdx)
    sete    %al
    mov     %rax, ApiView_is_optimistic(%rdi)
    lea     ApiView_head_root(%rdi), %rax
    COPY32  %rax, %rdx
1:  mov     %rbp, %rdi                      # the clock, sync, peers, MetaData
    call    lantern_node_store_slot
    mov     (%rsp), %rdi
    mov     %rax, ApiView_current_slot(%rdi)
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     (%rsp), %rdi
    mov     %rax, ApiView_fork(%rdi)
    mov     Node_flags(%rbx), %rax
    mov     %rax, %rcx
    shr     $3, %rcx                        # NODE_FLAG_SYNCING
    and     $1, %ecx
    mov     %rcx, ApiView_is_syncing(%rdi)
    shr     $9, %rax                        # NODE_FLAG_EL_OFFLINE
    and     $1, %eax
    mov     %rax, ApiView_el_offline(%rdi)
    mov     (Node_peers + 8)(%rbx), %rax
    mov     %rax, ApiView_peers(%rdi)
    mov     Node_metadata_seq(%rbx), %rax
    mov     %rax, ApiView_seq_number(%rdi)
    mov     Node_attnets(%rbx), %rax
    mov     %rax, ApiView_attnets(%rdi)
    mov     Node_custody_count(%rbx), %rax  # the custody group count
    mov     %rax, ApiView_custody_group_count(%rdi)
    add     $ApiView_peer_id, %rdi          # the identity's texts
    lea     Node_api_identity(%rbx), %rsi
    mov     $API_IDENTITY_SIZE, %edx
    call    lantern_copy
    mov     (%rsp), %rdi
    call    lantern_api_view_finalized
    UNFRAME 16
END_FUNCTION lantern_node_api_view

/* ApiView_head_finalized of the view rdi: 1 when its head_root is the root of the store rbp's finalized checkpoint. Uses rax, rsi, xmm0-xmm2. */
LOCAL_FUNCTION lantern_api_view_finalized
    UNWIND_END_PROLOGUE
    lea     ApiView_head_root(%rdi), %rax
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rsi
    movq    $0, ApiView_head_finalized(%rdi)
    NE32    %rax, %rsi, 1f
    movq    $1, ApiView_head_finalized(%rdi)
1:  ret
END_FUNCTION lantern_api_view_finalized

/*
 * One NODE_ACT_API_SEND of the connection rdi, with last 1, at the end of the actions r15: the
 * response of lantern_api_respond with the view rsi, the status rdx, the body rcx and the flags r8; when it
 * does not fit, the error 500. With API_R_CLOSE, then a NODE_ACT_API_CLOSE. Locals: the
 * connection, the flags, the action, its size.
 */
LOCAL_FUNCTION lantern_node_api_send
    FRAME 32
    mov     %rdi, (%rsp)
    mov     %r8, 8(%rsp)
    mov     8(%r15), %rax                   # the action, and the room after it
    add     %r15, %rax
    add     16(%r15), %rax
    mov     %rax, 16(%rsp)
    mov     (%r15), %r9
    sub     8(%r15), %r9
    sub     16(%r15), %r9
    sub     $32, %r9
    and     $~7, %r9
    mov     %r9, 32(%rax)                   # its ByteList at 32
    mov     %rsi, %rdi
    lea     32(%rax), %rsi
    call    lantern_api_respond
    test    %eax, %eax
    jz      1f
    xor     %edi, %edi                      # no room: the error 500
    mov     16(%rsp), %rsi
    add     $32, %rsi
    mov     $500, %edx
    mov     $API_BODY_ERROR, %ecx
    mov     8(%rsp), %r8
    and     $(API_R_CLOSE | API_R_KEEP), %r8
    call    lantern_api_respond
1:  mov     16(%rsp), %rax
    mov     48(%rax), %rcx                  # the count; the size to a multiple of 8, zero bytes after
    lea     (56 + 7)(%rcx), %rdx
    and     $~7, %rdx
    mov     %rdx, 24(%rsp)
    lea     56(%rax,%rcx), %rdi
    mov     %rdx, %rsi
    sub     $56, %rsi
    sub     %rcx, %rsi
    call    lantern_zero
    mov     16(%rsp), %rax
    mov     24(%rsp), %rdx
    mov     %rdx, (%rax)
    movq    $NODE_ACT_API_SEND, 8(%rax)
    mov     (%rsp), %rcx
    mov     %rcx, 16(%rax)
    movq    $1, 24(%rax)
    lea     -32(%rdx), %rcx
    mov     %rcx, 32(%rax)
    add     %rdx, 16(%r15)
    testq   $API_R_CLOSE, 8(%rsp)
    jz      9f
    mov     $NODE_ACT_API_CLOSE, %edi
    mov     $NODE_ACT_API_CLOSE_SIZE, %esi
    call    lantern_node_act
    mov     (%rsp), %rcx
    mov     %rcx, 16(%rax)
9:  UNFRAME 32
END_FUNCTION lantern_node_api_send

/*
 * The NODE_EV_API or NODE_EV_API_IDENTITY rdi, whose ByteList at 24 is inside it (node.md,
 * NodeEvent): rax = 0 when it keeps its rules, else 1; rdx = the scratch it needs. Uses rcx,
 * rsi, r8-r11.
 */
LOCAL_FUNCTION lantern_node_api_check
    UNWIND_END_PROLOGUE
    mov     (NodeEvent_bytes + 16)(%rdi), %r8   # the count
    lea     (NodeEvent_bytes + 24)(%rdi), %rsi  # the bytes
    cmpq    $NODE_EV_API_IDENTITY, 8(%rdi)
    jne     5f
    cmp     $API_IDENTITY_SIZE, %r8         # IDENTITY: each text in its room, its bytes 0x21 to 0x7e but " and \
    jne     8f
    lea     node_api_rooms(%rip), %r9
1:  mov     (%r9), %r10
    add     $8, %r9
    test    %r10, %r10
    jz      4f
    mov     (%rsi), %r11
    add     $8, %rsi
    cmp     %r10, %r11
    ja      8f
    xor     %ecx, %ecx
2:  cmp     %r11, %rcx
    jae     3f
    movzbl  (%rsi,%rcx), %eax
    lea     -0x21(%rax), %edx
    cmp     $(0x7e - 0x21), %edx
    ja      8f
    cmp     $0x22, %eax
    je      8f
    cmp     $0x5c, %eax
    je      8f
    inc     %rcx
    jmp     2b
3:  add     %r10, %rsi
    jmp     1b
4:  xor     %eax, %eax
    xor     %edx, %edx
    ret
5:  cmpq    $0, 16(%rdi)                    # API: a connection, not 0
    je      8f
    cmp     $HTTP_REQUEST_FIXED, %r8        # an HttpRequest of the count's size
    jb      8f
    test    $7, %r8b
    jnz     8f
    cmp     HttpRequest_size(%rsi), %r8
    jne     8f
    cmpq    $0, HttpRequest_status(%rsi)
    jne     7f
    mov     $HttpRequest_path, %ecx         # with status 0, each part inside
6:  cmp     $HTTP_REQUEST_FIXED, %rcx
    jae     7f
    mov     (%rsi,%rcx), %r9
    cmp     %r8, %r9
    ja      8f
    mov     %r8, %r10
    sub     %r9, %r10
    cmp     %r10, 8(%rsi,%rcx)
    ja      8f
    add     $16, %rcx
    jmp     6b
7:  mov     $NODE_API_SCRATCH, %edx
    cmpq    $0, HttpRequest_status(%rsi)
    jne     71f
    mov     (HttpRequest_query + 8)(%rsi), %rax
    lea     (%rdx,%rax,4), %rdx
    mov     (HttpRequest_body + 8)(%rsi), %rax   # 16 bytes per byte of the body: its ids
    shl     $4, %rax
    add     %rax, %rdx
71: xor     %eax, %eax
    ret
8:  mov     $1, %eax
    xor     %edx, %edx
    ret
END_FUNCTION lantern_node_api_check

/* rax = the NODE_DB_REF of the Db's record of the block at rdi, or 0. Locals: the slot. */
LOCAL_FUNCTION lantern_node_api_db_ref
    FRAME 16
    testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      9f
    mov     %rdi, %rsi
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    mov     %rsp, %rdx
    call    lantern_db_find_root
    mov     (%rsp), %rdi
    cmp     $-1, %rdi
    je      9f
    call    lantern_node_db_block
    UNFRAME 16
9:  xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_node_api_db_ref

/*
 * The answer to the NODE_EV_API rdi (node.md, lantern_node_step): rbx the node, rbp the store,
 * r14 the scratch, r15 the actions. r12 the event, r13 its HttpRequest, S7 the ApiRoute, S8 the
 * ApiView, S9 the connection, S10 the flags of lantern_api_respond. Locals: L the scratch's size.
 */
LOCAL_FUNCTION lantern_node_api_event
    ENTER 16
    mov     %rdi, %r12
    mov     16(%r12), %rax
    mov     %rax, S9(%rsp)
    mov     (NodeEvent_bytes + 8)(%r12), %r13
    lea     NodeEvent_bytes(%r12,%r13), %r13
    movq    $0, S10(%rsp)                   # close after a fault or with close; HTTP/1.0 kept open says so
    mov     HttpRequest_status(%r13), %rax
    or      HttpRequest_close(%r13), %rax
    jz      1f
    movq    $API_R_CLOSE, S10(%rsp)
    jmp     2f
1:  cmpq    $10, HttpRequest_version(%r13)
    jne     2f
    movq    $API_R_KEEP, S10(%rsp)
2:  mov     (%r14), %rax                    # the ApiView, then the ApiRoute, at the end of scratch
    mov     %rax, L(%rsp)
    mov     %r12, %rdi
    call    lantern_node_api_check
    mov     L(%rsp), %rax
    sub     %rdx, %rax
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, S8(%rsp)
    lea     ApiView__size(%rax), %rcx
    mov     %rcx, S7(%rsp)
    sub     $ApiView__size, %rdx
    mov     %rdx, (%rcx)
    mov     %rax, %rdi
    call    lantern_node_api_view
    mov     HttpRequest_status(%r13), %rdx  # a fault of the request: its status
    test    %rdx, %rdx
    jnz     80f
    mov     %r13, %rdi
    mov     S7(%rsp), %rsi
    call    lantern_api_route
    cmp     $LANTERN_INVALID_ROUTE, %rax
    jne     3f
    mov     S7(%rsp), %rcx
    mov     ApiRoute_status(%rcx), %rdx
    mov     ApiRoute_allow(%rcx), %rax
    shl     $8, %rax
    or      %rax, S10(%rsp)
    jmp     80f
3:  mov     $500, %edx
    test    %rax, %rax
    jnz     80f
    mov     S7(%rsp), %rax
    mov     ApiRoute_op(%rax), %rcx
    mov     $200, %edx
    cmp     $API_OP_GET_HEALTH, %rcx
    jne     4f
    mov     S8(%rsp), %rax                  # health: 200, else 206 or syncing_status
    mov     ApiView_is_syncing(%rax), %rsi
    or      ApiView_is_optimistic(%rax), %rsi
    or      ApiView_el_offline(%rax), %rsi
    xor     %ecx, %ecx
    test    %rsi, %rsi
    jz      81f
    mov     $206, %edx
    mov     S7(%rsp), %rax
    btq     $API_PARAM_SYNCING_STATUS, ApiRoute_present(%rax)
    jnc     81f
    mov     ApiRoute_syncing_status(%rax), %rdx
    orq     $API_R_NO_REASON, S10(%rsp)
    jmp     81f
4:  cmp     $API_OP_GET_NETWORK_IDENTITY, %rcx
    je      81f
    cmp     $API_OP_GET_NODE_VERSION, %rcx
    je      81f
    cmp     $API_OP_GET_SYNCING_STATUS, %rcx
    je      81f
    cmp     $API_OP_GET_PEER_COUNT, %rcx
    je      81f
    cmp     $API_OP_GET_PEERS, %rcx
    je      56f
    cmp     $API_OP_GET_PEER, %rcx
    je      55f
    cmp     $API_OP_GET_GENESIS, %rcx
    je      81f
    cmp     $API_OP_GET_FORK_SCHEDULE, %rcx
    je      81f
    cmp     $API_OP_GET_DEPOSIT_CONTRACT, %rcx
    je      81f
    mov     $404, %edx
    xor     %r12d, %r12d                    # r12: the answer flags of a work or a stream
    testq   $API_R_CLOSE, S10(%rsp)
    setnz   %r12b
    xor     %eax, %eax
    cmpq    $10, HttpRequest_version(%r13)
    sete    %al
    lea     (%r12,%rax,2), %r12
    lea     -API_OP_GET_LIGHT_CLIENT_BOOTSTRAP(%rcx), %rax  # the light client reads: of the light client store
    cmp     $(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP), %rax
    jbe     549f
    cmp     $API_OP_GET_BLOCK_ROOT, %rcx
    je      65f
    cmp     $API_OP_GET_BLOCK_HEADER, %rcx
    je      65f
    cmp     $API_OP_GET_BLOCK_V2, %rcx
    je      65f
    cmp     $API_OP_GET_BLOCK_ATTESTATIONS_V2, %rcx
    je      65f
    cmp     $API_OP_GET_BLINDED_BLOCK, %rcx
    je      65f
    cmp     $API_OP_GET_BLOB_SIDECARS, %rcx
    je      65f
    cmp     $API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS, %rcx
    je      65f
    cmp     $API_OP_GET_BLOBS, %rcx
    je      65f
    cmp     $API_OP_GET_BLOCK_REWARDS, %rcx
    je      547f
    cmp     $API_OP_GET_SYNC_COMMITTEE_REWARDS, %rcx
    je      547f
    cmp     $API_OP_GET_ATTESTATIONS_REWARDS, %rcx
    je      548f
    cmp     $API_OP_GET_STATE_ROOT, %rcx
    je      66f
    cmp     $API_OP_GET_STATE_FORK, %rcx
    je      66f
    cmp     $API_OP_GET_STATE_FINALITY_CHECKPOINTS, %rcx
    je      66f
    cmp     $API_OP_GET_STATE_RANDAO, %rcx
    je      66f
    cmp     $API_OP_GET_EPOCH_SYNC_COMMITTEES, %rcx
    je      66f
    cmp     $API_OP_GET_PROPOSER_LOOKAHEAD, %rcx
    je      66f
    lea     -API_OP_GET_PENDING_CONSOLIDATIONS(%rcx), %rax
    cmp     $2, %rax
    jbe     66f
    cmp     $API_OP_GET_SPEC, %rcx
    je      67f
    cmp     $API_OP_GET_DEBUG_CHAIN_HEADS_V2, %rcx
    je      67f
    cmp     $API_OP_GET_DEBUG_FORK_CHOICE, %rcx
    je      67f
    cmp     $API_OP_GET_BLOCK_HEADERS, %rcx
    je      57f
    cmp     $API_OP_GET_PROPOSER_DUTIES, %rcx
    je      63f
    cmp     $API_OP_GET_PROPOSER_DUTIES_V2, %rcx
    je      63f
    cmp     $API_OP_PRODUCE_ATTESTATION_DATA, %rcx
    je      59f
    cmp     $API_OP_PRODUCE_BLOCK_V3, %rcx
    je      540f
    cmp     $API_OP_GET_ATTESTER_DUTIES, %rcx
    je      58f
    cmp     $API_OP_GET_SYNC_COMMITTEE_DUTIES, %rcx
    je      53f
    cmp     $API_OP_GET_LIVENESS, %rcx
    je      52f
    cmp     $API_OP_EVENTSTREAM, %rcx
    je      61f
    cmp     $API_OP_GET_POOL_VOLUNTARY_EXITS, %rcx
    je      68f
    cmp     $API_OP_GET_POOL_PROPOSER_SLASHINGS, %rcx
    je      68f
    cmp     $API_OP_GET_POOL_ATTESTER_SLASHINGS_V2, %rcx
    je      68f
    cmp     $API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES, %rcx
    je      68f
    cmp     $API_OP_GET_POOL_ATTESTATIONS_V2, %rcx
    je      68f
    cmp     $API_OP_GET_AGGREGATED_ATTESTATION_V2, %rcx
    je      68f
    cmp     $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, %rcx
    je      68f
    cmp     $API_OP_PREPARE_BEACON_COMMITTEE_SUBNET, %rcx  # the subscriptions: as a pool POST
    je      60f
    cmp     $API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS, %rcx
    je      60f
    cmp     $API_OP_PREPARE_BEACON_PROPOSER, %rcx
    je      60f
    cmp     $API_OP_REGISTER_VALIDATOR, %rcx
    je      60f
    cmp     $API_OP_PUBLISH_BLOCK_V2, %rcx
    je      545f
    cmp     $API_OP_PUBLISH_BLINDED_BLOCK_V2, %rcx
    je      545f
    mov     %rcx, %rdi
    call    lantern_node_submit_topic
    test    %rax, %rax
    jnz     60f
    mov     S7(%rsp), %rax
    mov     ApiRoute_op(%rax), %rcx
    lea     -API_OP_GET_STATE_VALIDATORS(%rcx), %rax    # the six validator operations and getEpochCommittees: a state
    cmp     $(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS), %rax
    jbe     66f
    cmp     $API_OP_GET_STATE_V2, %rcx
    jne     7f
66: mov     S7(%rsp), %rax                  # a state root: a work finds its slot first
    cmpq    $API_ID_ROOT, ApiRoute_id_kind(%rax)
    jne     69f
    mov     S9(%rsp), %rdi
    mov     %rax, %rsi
    mov     %r12, %rdx
    xor     %ecx, %ecx
    call    lantern_node_api_lookup
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
69: mov     S8(%rsp), %rsi                  # a state: its lookup, then the state at its slot; the replay may come
    movq    $1, ApiView_look_replay(%rsi)
    mov     S7(%rsp), %rdi
    call    lantern_node_api_state
    mov     %rax, %rdx
    cmp     $1, %rax
    je      698f
    test    %rax, %rax
    jnz     80f
    mov     S8(%rsp), %rcx
    movq    $0, ApiView_look_data(%rcx)
    mov     S9(%rsp), %rdi
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    call    lantern_node_api_state_answer
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
698: mov    S9(%rsp), %rdi                  # the replay: the request waits in a lookup entry
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     $1, %ecx
    call    lantern_node_api_lookup
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
53: mov     $503, %edx                      # getSyncCommitteeDuties: 503 while syncing; 400 past the next period, with no index or a key
    mov     S8(%rsp), %rax
    cmpq    $0, ApiView_is_syncing(%rax)
    jne     80f
    mov     $400, %edx
    mov     S7(%rsp), %rdi
    mov     ApiRoute_list(%rdi), %rax
    mov     (ApiRoute_list + 8)(%rdi), %rcx
    test    %rcx, %rcx
    jz      80f
    add     %rdi, %rax
531: cmpq   $API_VALIDATOR_INDEX, (%rax)
    jne     80f
    add     $64, %rax
    dec     %rcx
    jnz     531b
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    xor     %edx, %edx
    mov     $(SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD), %ecx
    div     %rcx
    inc     %rax
    mov     %rax, (L + 8)(%rsp)             # the store's period + 1
    mov     S7(%rsp), %rdi
    mov     ApiRoute_epoch(%rdi), %rax
    xor     %edx, %edx
    mov     $EPOCHS_PER_SYNC_COMMITTEE_PERIOD, %ecx
    div     %rcx
    mov     $400, %edx
    cmp     (L + 8)(%rsp), %rax
    ja      80f
    mov     %rax, (L + 8)(%rsp)             # the epoch's period
    lea     Node_head_root(%rbx), %rdi      # the head's post-state, of altair on, at the epoch's period or the one before
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      532f
    mov     NodeBlock_slot(%rdx), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    cmp     $FORK_ALTAIR, %rax
    jb      532f
    lea     Node_head_root(%rbx), %rdi
    call    lantern_node_find_block
    mov     NodeBlock_slot(%rdx), %rax
    xor     %edx, %edx
    mov     $(SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD), %ecx
    div     %rcx
    mov     (L + 8)(%rsp), %rcx
    sub     %rax, %rcx
    jb      532f
    cmp     $1, %rcx
    ja      532f
    mov     %rcx, (L + 8)(%rsp)             # 1: the next period
    mov     S7(%rsp), %rdi
    movq    $API_ID_HEAD, ApiRoute_id_kind(%rdi)
    mov     S8(%rsp), %rsi
    call    lantern_node_api_state
    mov     $400, %edx
    test    %rax, %rax
    jnz     80f
    mov     S8(%rsp), %rdi
    mov     (L + 8)(%rsp), %rax
    mov     %rax, ApiView_next_period(%rdi)
    mov     S7(%rsp), %rdi                  # its ids in the work's data
    call    lantern_node_api_ids
    mov     S8(%rsp), %rcx
    mov     %rax, ApiView_look_data(%rcx)
    jmp     67f
532: mov    %rbp, %rdi                      # else the state of the epoch's first slot, as getAttesterDuties
    call    lantern_node_store_slot
    mov     %rax, %rsi
    mov     S7(%rsp), %rdi
    mov     ApiRoute_epoch(%rdi), %rcx
    jmp     583f
52: mov     $503, %edx                      # getLiveness: 503 while syncing; 400 outside the previous to the next epoch, with no index or a key
    mov     S8(%rsp), %rax
    cmpq    $0, ApiView_is_syncing(%rax)
    jne     80f
    mov     $400, %edx
    mov     S7(%rsp), %rdi
    mov     ApiRoute_list(%rdi), %rax
    mov     (ApiRoute_list + 8)(%rdi), %rcx
    test    %rcx, %rcx
    jz      80f
    add     %rdi, %rax
521: cmpq   $API_VALIDATOR_INDEX, (%rax)
    jne     80f
    add     $64, %rax
    dec     %rcx
    jnz     521b
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx                            # the store's epoch
    mov     S7(%rsp), %rdi
    mov     ApiRoute_epoch(%rdi), %rcx
    mov     $400, %edx
    lea     1(%rax), %rsi
    cmp     %rsi, %rcx
    ja      80f
    test    %rax, %rax
    jz      522f
    dec     %rax
    cmp     %rax, %rcx
    jb      80f
522: movq   $API_ID_HEAD, ApiRoute_id_kind(%rdi)  # the head's post-state at its slot; none: 500
    mov     S8(%rsp), %rsi
    call    lantern_node_api_state
    mov     $500, %edx
    test    %rax, %rax
    jnz     80f
    mov     S7(%rsp), %rdi                  # the epoch in the work's arg, in place of the slot
    mov     ApiRoute_epoch(%rdi), %rax
    mov     S8(%rsp), %rcx
    mov     %rax, ApiView_head_slot(%rcx)
    call    lantern_node_api_ids                    # its ids in the work's data
    mov     S8(%rsp), %rcx
    mov     %rax, ApiView_look_data(%rcx)
    jmp     67f
58: mov     $503, %edx                      # getAttesterDuties: 503 while syncing; 400 past the next epoch, with no index or a key
    mov     S8(%rsp), %rax
    cmpq    $0, ApiView_is_syncing(%rax)
    jne     80f
    mov     $400, %edx
    mov     S7(%rsp), %rdi
    mov     ApiRoute_list(%rdi), %rax
    mov     (ApiRoute_list + 8)(%rdi), %rcx
    test    %rcx, %rcx
    jz      80f
    add     %rdi, %rax
581: cmpq   $API_VALIDATOR_INDEX, (%rax)
    jne     80f
    add     $64, %rax
    dec     %rcx
    jnz     581b
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    mov     %rax, %rsi
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    inc     %rax
    mov     S7(%rsp), %rdi
    mov     ApiRoute_epoch(%rdi), %rcx
    mov     $400, %edx
    cmp     %rax, %rcx
    ja      80f
583: imul   $SLOTS_PER_EPOCH, %rcx, %rcx    # the state of the first slot, as getProposerDuties; none: 400
    mov     %rcx, ApiRoute_id_slot(%rdi)
    movq    $API_ID_SLOT, ApiRoute_id_kind(%rdi)
    cmp     %rsi, %rcx
    jbe     582f
    movq    $API_ID_HEAD, ApiRoute_id_kind(%rdi)
582: mov    S8(%rsp), %rsi
    cmpq    $API_OP_GET_ATTESTER_DUTIES, ApiRoute_op(%rdi)  # getAttesterDuties of a slot: the replay may come
    jne     584f
    cmpq    $API_ID_SLOT, ApiRoute_id_kind(%rdi)
    jne     584f
    movq    $1, ApiView_look_replay(%rsi)
584: call   lantern_node_api_state
    mov     %rax, %rdx
    cmp     $1, %rax
    je      698b
    mov     $400, %edx
    test    %rax, %rax
    jnz     80f
    mov     S7(%rsp), %rax
    mov     ApiRoute_id_slot(%rax), %rax
    mov     S8(%rsp), %rdi
    mov     %rax, ApiView_head_slot(%rdi)
    call    lantern_node_api_advance
    mov     S7(%rsp), %rdi                  # its ids in the work's data
    call    lantern_node_api_ids
    mov     S8(%rsp), %rcx
    mov     %rax, ApiView_look_data(%rcx)
    jmp     67f
540: mov    $503, %edx                      # produceBlockV3: 503 while syncing; 400 at or below the head's slot, or past the store's slot + 1
    mov     S8(%rsp), %rax
    cmpq    $0, ApiView_is_syncing(%rax)
    jne     80f
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    mov     S7(%rsp), %rdi
    mov     ApiRoute_slot(%rdi), %rcx
    mov     $400, %edx
    inc     %rax
    cmp     %rax, %rcx
    ja      80f
    mov     S8(%rsp), %rax
    cmp     ApiView_head_slot(%rax), %rcx
    jbe     80f
    movq    $API_ID_HEAD, ApiRoute_id_kind(%rdi)    # the head's post-state brought to the slot, which may be past the store's
    mov     S8(%rsp), %rsi
    call    lantern_node_api_state
    mov     $500, %edx
    test    %rax, %rax
    jnz     80f
    mov     S7(%rsp), %rax
    mov     ApiRoute_slot(%rax), %rax
    mov     S8(%rsp), %rdi
    mov     %rax, ApiView_head_slot(%rdi)
    call    lantern_node_api_advance
    mov     S9(%rsp), %rdi
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    call    lantern_node_api_produce
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
59: mov     $503, %edx                      # produceAttestationData: 503 while syncing; 400 past the store's slot
    mov     S8(%rsp), %rax
    cmpq    $0, ApiView_is_syncing(%rax)
    jne     80f
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    mov     S7(%rsp), %rdi
    mov     ApiRoute_slot(%rdi), %rcx
    mov     $400, %edx
    cmp     %rax, %rcx
    ja      80f
    movq    $API_ID_SLOT, ApiRoute_id_kind(%rdi)    # the state of the slot, as a state_id of it; none: 400
    mov     %rcx, ApiRoute_id_slot(%rdi)
    mov     S8(%rsp), %rsi
    call    lantern_node_api_state
    mov     $400, %edx
    test    %rax, %rax
    jnz     80f
    mov     $503, %edx                      # an optimistic block: 503
    mov     S8(%rsp), %rdi
    cmpq    $0, ApiView_is_optimistic(%rdi)
    jne     80f
    call    lantern_node_api_advance
    mov     S7(%rsp), %rdi                  # its committee index in the work's data
    add     $ApiRoute_committee_index, %rdi
    call    lantern_node_api_put8
    mov     S8(%rsp), %rcx
    mov     %rax, ApiView_look_data(%rcx)
    mov     S7(%rsp), %rax                  # SSZ: an answer flag
    cmpq    $API_TYPE_SSZ, ApiRoute_response(%rax)
    jne     67f
    or      $API_ANSWER_SSZ, %r12
    jmp     67f
56: mov     S7(%rsp), %rax                  # getPeers: its state and direction sets, all bits with none
    mov     S8(%rsp), %rsi
    mov     $-1, %rcx
    testq   $(1 << API_PARAM_STATE), ApiRoute_present(%rax)
    jz      561f
    mov     ApiRoute_peer_states(%rax), %rcx
561: mov    %rcx, ApiView_peer_states(%rsi)
    mov     $-1, %rcx
    testq   $(1 << API_PARAM_DIRECTION), ApiRoute_present(%rax)
    jz      562f
    mov     ApiRoute_peer_directions(%rax), %rcx
562: mov    %rcx, ApiView_peer_directions(%rsi)
    mov     %rbx, ApiView_node(%rsi)
    mov     $200, %edx
    mov     $API_OP_GET_PEERS, %ecx
    jmp     81f
55: mov     S7(%rsp), %rdi                  # getPeer: the peer of its peer_id, else 404
    call    lantern_node_api_find_peer
    mov     $404, %edx
    test    %rax, %rax
    jz      80f
    mov     S8(%rsp), %rsi
    mov     %rax, ApiView_peer(%rsi)
    mov     $200, %edx
    mov     $API_OP_GET_PEER, %ecx
    jmp     81f
57: mov     S9(%rsp), %rdi                  # getBlockHeaders: a stream of the blocks of its query
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    call    lantern_node_api_headers_stream
    jmp     90f
68: mov     S9(%rsp), %rdi                  # a pool GET: a stream of the pool; getAggregatedAttestationV2 with none 404
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    call    lantern_node_api_pool_stream
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
548: mov    S7(%rsp), %rax                  # getAttestationsRewards: the state of the last slot of epoch + 1, a stream of it
    mov     $404, %edx
    mov     ApiRoute_epoch(%rax), %rcx
    add     $2, %rcx
    jc      80f
    mov     %rcx, (L + 8)(%rsp)
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    inc     %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     $404, %edx
    mov     (L + 8)(%rsp), %rcx
    cmp     %rax, %rcx
    ja      80f
    imul    $SLOTS_PER_EPOCH, %rcx, %rcx
    dec     %rcx
    mov     S7(%rsp), %rdi
    movq    $API_ID_SLOT, ApiRoute_id_kind(%rdi)
    mov     %rcx, ApiRoute_id_slot(%rdi)
    mov     S8(%rsp), %rsi
    call    lantern_node_api_state
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    mov     S8(%rsp), %rdi
    call    lantern_node_api_advance
    mov     S7(%rsp), %rdi                  # its ids, as a validator stream's
    call    lantern_node_api_ids
    mov     S8(%rsp), %rcx
    mov     %rax, ApiView_look_data(%rcx)
    jmp     64f
547: mov    S9(%rsp), %rdi                  # getBlockRewards, getSyncCommitteeRewards: a work of the block on its pre-state
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    call    lantern_node_api_rewards
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
545: mov    $503, %edx                      # publishBlockV2 and publishBlindedBlockV2: 503 while syncing; a work decodes its body
    mov     S8(%rsp), %rax
    cmpq    $0, ApiView_is_syncing(%rax)
    jne     80f
    mov     S9(%rsp), %rdi
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    call    lantern_node_api_publish
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
60: mov     S9(%rsp), %rdi                  # a pool POST: a work checks its operations
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     %r13, %rcx
    mov     S8(%rsp), %r8
    call    lantern_node_api_submit
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
61: mov     S9(%rsp), %rdi                  # eventstream: an entry, and the head
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    call    lantern_node_api_subscribe
    jmp     90f
63: mov     $503, %edx                      # getProposerDuties and V2: 503 while syncing; 400 past the next epoch
    mov     S8(%rsp), %rax
    cmpq    $0, ApiView_is_syncing(%rax)
    jne     80f
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    mov     %rax, %rsi
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    inc     %rax
    mov     S7(%rsp), %rdi
    mov     ApiRoute_epoch(%rdi), %rcx
    mov     $400, %edx
    cmp     %rax, %rcx
    ja      80f
    imul    $SLOTS_PER_EPOCH, %rcx, %rcx    # the first slot: as a state_id of it; past the store's slot, the head's post-state
    mov     %rcx, ApiRoute_id_slot(%rdi)
    movq    $API_ID_SLOT, ApiRoute_id_kind(%rdi)
    cmp     %rsi, %rcx
    jbe     62f
    movq    $API_ID_HEAD, ApiRoute_id_kind(%rdi)
62: mov     S8(%rsp), %rsi
    cmpq    $API_ID_SLOT, ApiRoute_id_kind(%rdi)    # a slot: the replay may come
    jne     621f
    movq    $1, ApiView_look_replay(%rsi)
621: call   lantern_node_api_state
    mov     %rax, %rdx
    cmp     $1, %rax
    je      698b
    test    %rax, %rax
    jnz     80f
    mov     S7(%rsp), %rax                  # brought to the first slot
    mov     ApiRoute_id_slot(%rax), %rax
    mov     S8(%rsp), %rdi
    mov     %rax, ApiView_head_slot(%rdi)
    call    lantern_node_api_advance
    jmp     67f
65: mov     S7(%rsp), %rdi                  # a block: its lookup
    mov     S8(%rsp), %rsi
    call    lantern_node_api_block
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    mov     S7(%rsp), %rax
    mov     ApiRoute_op(%rax), %rcx
    mov     $200, %edx
    cmp     $API_OP_GET_BLOCK_ROOT, %rcx    # getBlockRoot: the answer at once
    je      81f
    cmp     $API_OP_GET_BLOCK_V2, %rcx
    je      64f
    cmp     $API_OP_GET_BLOCK_ATTESTATIONS_V2, %rcx
    je      64f
    cmp     $API_OP_GET_BLINDED_BLOCK, %rcx
    je      64f
    cmp     $API_OP_GET_BLOB_SIDECARS, %rcx
    je      54f
    cmp     $API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS, %rcx
    je      54f
    cmp     $API_OP_GET_BLOBS, %rcx
    je      55f
67: mov     S7(%rsp), %rax                  # a work
    mov     ApiRoute_op(%rax), %rdi
    mov     S9(%rsp), %rsi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    call    lantern_node_api_encode
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
549: mov    S7(%rsp), %rdi                  # the light client reads: a work
    mov     S9(%rsp), %rsi
    mov     %r12, %rdx
    call    lantern_node_api_lc
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     80f
    jmp     90f
54: mov     S9(%rsp), %rdi                  # a sidecar stream of the block
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    call    lantern_node_api_sidecar_stream
    test    %rax, %rax
    jz      90f
    mov     %rax, %rdx
    jmp     80f
55: mov     S9(%rsp), %rdi                  # getBlobs: the blob stream of the block
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    call    lantern_node_api_blob_stream
    test    %rax, %rax
    jz      90f
    mov     %rax, %rdx
    jmp     80f
64: mov     S9(%rsp), %rdi                  # a stream of the answer
    mov     S7(%rsp), %rsi
    mov     %r12, %rdx
    mov     S8(%rsp), %rcx
    call    lantern_node_api_stream
    test    %rax, %rax
    jz      90f
    mov     %rax, %rdx
    jmp     80f
7:  mov     $501, %edx                      # another operation
80: mov     $API_BODY_ERROR, %ecx
81: mov     S9(%rsp), %rdi
    mov     S8(%rsp), %rsi
    mov     S10(%rsp), %r8
    call    lantern_node_api_send
90: mov     L(%rsp), %rax
    mov     %rax, (%r14)
    LEAVE 16
END_FUNCTION lantern_node_api_event

/*
 * The state of the chain at the slot rdi, as for a state_id of it, and past the store's slot the
 * head's post-state brought to it (beacon-api.md, getBlockRewards), with the route r12 and the view
 * r13: rax = 0 or 404, rdx its id, rcx 1 when it is a copy. Locals: L the slot.
 */
LOCAL_FUNCTION lantern_node_api_rewards_state
    ENTER 16
    mov     %rdi, L(%rsp)
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    mov     L(%rsp), %rcx
    movq    $API_ID_SLOT, ApiRoute_id_kind(%r12)
    cmp     %rax, %rcx
    jbe     1f
    movq    $API_ID_HEAD, ApiRoute_id_kind(%r12)
1:  mov     %rcx, ApiRoute_id_slot(%r12)
    movq    $0, ApiView_look_copy(%r13)
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    lantern_node_api_state
    test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax
    mov     %rax, ApiView_head_slot(%r13)
    mov     %r13, %rdi
    call    lantern_node_api_advance
    mov     ApiView_look_state(%r13), %rdx
    mov     ApiView_look_copy(%r13), %rcx
    xor     %eax, %eax
9:  LEAVE 16
END_FUNCTION lantern_node_api_rewards_state

/*
 * getBlockRewards and getSyncCommitteeRewards (node.md, NODE_EV_API): the block, a NodeBlock with
 * bytes; P, its parent's post-state brought to its slot; getSyncCommitteeRewards its ids as state_b,
 * getBlockRewards of a phase0 block the E states as state_b and state_c; a NODE_WORK_API_ENCODE, then
 * a STATE_FREE of each copy. (connection rdi, route rsi, answer flags rdx, view rcx) -> rax = 0, or
 * the error status. r12 the route, r13 the view. Locals: L the connection, L+8 the flags, L+16 P,
 * L+24 state_b, L+32 state_c, L+40 1 when state_b is a copy, L+48 1 when state_c is, L+56 the block's
 * slot, L+64 its values, L+72 its bytes, L+80 its fork, L+88 a slot, L+96 the status, L+104 the parent.
 */
LOCAL_FUNCTION lantern_node_api_rewards
    ENTER 112
    mov     %rdi, L(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    mov     %rsi, %r12
    mov     %rcx, %r13
    mov     %r12, %rdi
    mov     %r13, %rsi
    call    lantern_node_api_block
    test    %rax, %rax
    jnz     9f
    mov     $404, %eax
    cmpq    $-1, ApiView_look_index(%r13)   # a NodeBlock with bytes
    je      9f
    mov     ApiView_look_data(%r13), %rcx
    test    %rcx, %rcx
    jz      9f
    mov     %rcx, (L + 72)(%rsp)
    mov     ApiView_head_slot(%r13), %rdi
    mov     %rdi, (L + 56)(%rsp)
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, (L + 80)(%rsp)
    cmpq    $API_OP_GET_SYNC_COMMITTEE_REWARDS, ApiRoute_op(%r12)  # getSyncCommitteeRewards of a phase0 block: 400
    jne     1f
    mov     %rax, %rcx
    mov     $400, %eax
    test    %rcx, %rcx
    jz      9f
1:  mov     ApiView_canonical(%r13), %rax   # the values of the block
    mov     ApiView_head_finalized(%r13), %rcx
    shl     $1, %rcx
    or      %rcx, %rax
    mov     ApiView_is_optimistic(%r13), %rcx
    shl     $2, %rcx
    or      %rcx, %rax
    mov     %rax, (L + 64)(%rsp)
    lea     ApiView_head_root(%r13), %rdi   # the parent, imported, with a post-state
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      8f
    lea     NodeBlock_parent_root(%rdx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      8f
    mov     %rdx, (L + 104)(%rsp)
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     8f
    mov     NodeBlock_state_id(%rdx), %rax
    test    %rax, %rax
    jnz     2f
    call    lantern_node_f_slot
    mov     (L + 104)(%rsp), %rdi
    cmp     $-1, %rax
    je      8f
    cmp     %rax, NodeBlock_slot(%rdi)
    jbe     8f
    call    lantern_node_rebuild
    test    %rax, %rax
    jz      8f
2:  mov     %rax, ApiView_look_state(%r13)  # P: a copy brought to the block's slot
    mov     (L + 104)(%rsp), %rdi
    mov     NodeBlock_slot(%rdi), %rax
    mov     %rax, ApiView_look_state_slot(%r13)
    mov     (L + 56)(%rsp), %rax
    mov     %rax, ApiView_head_slot(%r13)
    mov     %r13, %rdi
    call    lantern_node_api_advance
    mov     ApiView_look_state(%r13), %rax
    mov     %rax, (L + 16)(%rsp)
    xor     %eax, %eax
    mov     %rax, (L + 24)(%rsp)
    mov     %rax, (L + 32)(%rsp)
    mov     %rax, (L + 40)(%rsp)
    mov     %rax, (L + 48)(%rsp)
    mov     %rax, (L + 96)(%rsp)
    cmpq    $API_OP_GET_SYNC_COMMITTEE_REWARDS, ApiRoute_op(%r12)
    jne     3f
    mov     %r12, %rdi                      # getSyncCommitteeRewards: its ids as state_b
    call    lantern_node_api_ids
    mov     %rax, (L + 24)(%rsp)
    jmp     6f
3:  cmpq    $0, (L + 80)(%rsp)              # getBlockRewards of a phase0 block of epoch b: the E states
    jne     6f
    mov     (L + 56)(%rsp), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    test    %rax, %rax
    jz      4f
    inc     %rax                            # early: the state at the last slot of b
    imul    $SLOTS_PER_EPOCH, %rax, %rdi
    dec     %rdi
    call    lantern_node_api_rewards_state
    mov     %rax, (L + 96)(%rsp)
    test    %rax, %rax
    jnz     7f
    mov     %rdx, (L + 24)(%rsp)
    mov     %rcx, (L + 40)(%rsp)
4:  mov     (L + 56)(%rsp), %rax            # late: at the last slot of b + 1, when that epoch is phase0's
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    add     $2, %rax
    imul    $SLOTS_PER_EPOCH, %rax, %rdi
    dec     %rdi
    mov     %rdi, (L + 88)(%rsp)
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    test    %rax, %rax
    jnz     6f
    mov     (L + 88)(%rsp), %rdi
    call    lantern_node_api_rewards_state
    mov     %rax, (L + 96)(%rsp)
    test    %rax, %rax
    jnz     7f
    mov     %rdx, (L + 32)(%rsp)
    mov     %rcx, (L + 48)(%rsp)
6:  mov     ApiRoute_op(%r12), %r9          # the work: arg as lantern_node_api_encode packs it
    mov     (L + 8)(%rsp), %rax
    shl     $8, %rax
    or      %rax, %r9
    mov     (L + 64)(%rsp), %rax
    shl     $16, %rax
    or      %rax, %r9
    mov     (L + 56)(%rsp), %rax
    shl     $24, %rax
    or      %rax, %r9
    mov     $NODE_WORK_API_ENCODE, %edi
    mov     (L + 16)(%rsp), %rsi
    mov     (L + 24)(%rsp), %rdx
    mov     (L + 72)(%rsp), %rcx
    mov     L(%rsp), %r8
    call    lantern_node_work
    mov     (L + 32)(%rsp), %rcx
    mov     %rcx, NodeAction_state_c(%rax)
7:  mov     $NODE_ACT_STATE_FREE, %edi      # the copies go after the work
    mov     (L + 16)(%rsp), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
    cmpq    $0, (L + 40)(%rsp)
    je      71f
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     (L + 24)(%rsp), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
71: cmpq    $0, (L + 48)(%rsp)
    je      72f
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     (L + 32)(%rsp), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
72: mov     (L + 96)(%rsp), %rax
9:  LEAVE 112
8:  mov     $404, %eax
    LEAVE 112
END_FUNCTION lantern_node_api_rewards

/*
 * The NODE_EV_WORK_DONE rdi of a NODE_WORK_API_ENCODE (node.md, lantern_node_step): its response
 * to the connection, or the error 500. rbx the node, r15 the actions. r12 the event, r13 the
 * action, S7 the flags.
 */
LOCAL_FUNCTION lantern_node_api_done
    ENTER 0
    mov     %rdi, %r12
    movzbl  NodeAction_arg(%r12), %eax      # getSyncCommitteeRewards: its ids in state_b go
    cmp     $API_OP_GET_SYNC_COMMITTEE_REWARDS, %eax
    jne     4f
    mov     NodeAction_state_b(%r12), %rsi
    test    %rsi, %rsi
    jz      4f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
4:  movzbl  NodeAction_arg(%r12), %eax      # getStateValidator: its ids go; produceAttestationData its index
    cmp     $API_OP_GET_STATE_VALIDATOR, %eax
    je      3f
    cmp     $API_OP_PRODUCE_ATTESTATION_DATA, %eax
    je      3f
    cmp     $API_OP_GET_STATE_RANDAO, %eax
    je      3f
    cmp     $API_OP_GET_EPOCH_SYNC_COMMITTEES, %eax
    je      3f
    cmp     $API_OP_GET_SYNC_COMMITTEE_DUTIES, %eax
    je      3f
    cmp     $API_OP_GET_LIVENESS, %eax
    je      3f
    cmp     $API_OP_GET_LIGHT_CLIENT_BOOTSTRAP, %eax
    je      3f
    cmp     $API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE, %eax
    je      3f
    cmp     $API_OP_GET_ATTESTER_DUTIES, %eax
    jne     2f
3:  mov     NodeAction_data(%r12), %rsi
    test    %rsi, %rsi
    jz      2f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
2:  mov     NodeAction_arg(%r12), %rax
    shr     $8, %rax
    movzbl  %al, %eax
    mov     %rax, %rcx
    and     $API_ANSWER_CLOSE, %ecx         # API_R_CLOSE, or API_R_KEEP for HTTP/1.0 kept open
    jnz     1f
    test    $API_ANSWER_HTTP10, %al
    jz      1f
    mov     $API_R_KEEP, %ecx
1:  mov     %rcx, S7(%rsp)
    cmpq    $0, NodeEvent_result(%r12)
    jne     5f
    mov     (NodeEvent_chunk + 16)(%r12), %rsi  # the chunk's bytes in a SEND
    add     $(56 + 7), %rsi
    and     $~7, %rsi
    mov     $NODE_ACT_API_SEND, %edi
    call    lantern_node_act
    mov     %rax, %r13
    mov     NodeAction_target(%r12), %rax
    mov     %rax, 16(%r13)
    movq    $1, 24(%r13)
    mov     (%r13), %rax
    sub     $32, %rax
    mov     %rax, 32(%r13)
    movq    $24, 40(%r13)
    mov     (NodeEvent_chunk + 16)(%r12), %rdx
    mov     %rdx, 48(%r13)
    lea     56(%r13), %rdi
    mov     (NodeEvent_chunk + 8)(%r12), %rsi
    lea     NodeEvent_chunk(%r12,%rsi), %rsi
    call    lantern_copy
    mov     48(%r13), %rcx                  # zero bytes to the size
    lea     56(%r13,%rcx), %rdi
    mov     (%r13), %rsi
    sub     $56, %rsi
    sub     %rcx, %rsi
    call    lantern_zero
    testq   $API_R_CLOSE, S7(%rsp)
    jz      9f
    mov     $NODE_ACT_API_CLOSE, %edi
    mov     $NODE_ACT_API_CLOSE_SIZE, %esi
    call    lantern_node_act
    mov     NodeAction_target(%r12), %rcx
    mov     %rcx, 16(%rax)
    LEAVE 0
5:  mov     NodeAction_target(%r12), %rdi   # not valid: the error 500
    xor     %esi, %esi
    mov     $500, %edx
    mov     $API_BODY_ERROR, %ecx
    mov     S7(%rsp), %r8
    call    lantern_node_api_send
9:  LEAVE 0
END_FUNCTION lantern_node_api_done

/*
 * (node rdi, store rsi, work rdx, state_a rcx, data r8, scratch r9, event r10, room r11, seen rax)
 * -> rax: a NODE_WORK_API_ENCODE of lantern_node_run (node.md): the response at NodeEvent_chunk of
 * the event, whose buffer has room bytes. rbx the node, rbp the store, r12 the work, r13 state_a,
 * r14 the scratch, r15 the event, S7 data, S8 the ApiView at the end of scratch, S9 the operation,
 * S10 the room. Locals: L the scratch's size, L+8 the fork, L+16 a Result, L+24 a blob count, L+32
 * the seen.
 */
LOCAL_FUNCTION lantern_node_api_run
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     %r8, S7(%rsp)
    mov     %r9, %r14
    mov     %r10, %r15
    mov     %r11, S10(%rsp)
    mov     (%rax), %rcx                    # rax: the seen, state_b and state_c
    mov     %rcx, (L + 32)(%rsp)
    mov     8(%rax), %rcx
    mov     %rcx, (L + 40)(%rsp)
    mov     16(%rax), %rcx
    mov     %rcx, (L + 48)(%rsp)
    movzbl  NodeAction_arg(%r12), %eax      # the operation; a block index past the blocks part
    mov     %rax, S9(%rsp)
    mov     NodeAction_arg(%r12), %rcx
    shr     $24, %rcx
    cmp     $API_OP_GET_BLOCK_HEADER, %eax
    jne     1f
    cmp     (Node_blocks + 8)(%rbx), %rcx
    ja      8f
    cmpq    $0, S7(%rsp)                    # a header: bytes, or a block of the node with a post-state
    jne     2f
    test    %rcx, %rcx
    jz      8f
    test    %r13, %r13
    jz      8f
    jmp     2f
1:  cmp     $API_OP_GET_SPEC, %eax          # getSpec, getDebugChainHeadsV2, getDebugForkChoice: no state
    je      2f
    lea     -API_OP_GET_LIGHT_CLIENT_BOOTSTRAP(%rax), %rdx  # the light client reads: the light client store
    cmp     $(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP), %rdx
    jbe     2f
    cmp     $API_OP_GET_DEBUG_CHAIN_HEADS_V2, %eax
    je      2f
    cmp     $API_OP_GET_DEBUG_FORK_CHOICE, %eax
    je      2f
    test    %r13, %r13                      # a state's answer: a state
    jz      8f
    cmp     $API_OP_GET_STATE_FINALITY_CHECKPOINTS, %eax
    je      2f
    cmp     $API_OP_GET_STATE_VALIDATOR, %eax
    je      2f
    cmp     $API_OP_GET_STATE_ROOT, %eax
    je      2f
    cmp     $API_OP_GET_PROPOSER_DUTIES, %eax
    je      2f
    cmp     $API_OP_GET_PROPOSER_DUTIES_V2, %eax
    je      2f
    cmp     $API_OP_PRODUCE_ATTESTATION_DATA, %eax
    je      2f
    cmp     $API_OP_GET_ATTESTER_DUTIES, %eax
    je      2f
    cmp     $API_OP_GET_SYNC_COMMITTEE_DUTIES, %eax
    je      2f
    cmp     $API_OP_GET_STATE_RANDAO, %eax
    je      2f
    cmp     $API_OP_GET_EPOCH_SYNC_COMMITTEES, %eax
    je      2f
    cmp     $API_OP_GET_PROPOSER_LOOKAHEAD, %eax
    je      2f
    cmp     $API_OP_GET_LIVENESS, %eax
    je      2f
    cmp     $API_OP_GET_BLOCK_REWARDS, %eax
    je      2f
    cmp     $API_OP_GET_SYNC_COMMITTEE_REWARDS, %eax
    je      2f
    cmp     $API_OP_GET_STATE_FORK, %eax
    jne     8f
2:  mov     (%r14), %rax                    # the ApiView at the end of scratch, with the work's values
    mov     %rax, L(%rsp)
    sub     $ApiView__size, %rax
    jb      7f
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, S8(%rsp)
    mov     %rax, %rdi
    call    lantern_node_api_view
    mov     S8(%rsp), %rdi
    mov     NodeAction_arg(%r12), %rax
    mov     %rax, %rcx
    shr     $16, %rcx
    and     $1, %ecx
    mov     %rcx, ApiView_canonical(%rdi)
    mov     %rax, %rcx
    shr     $17, %rcx
    and     $1, %ecx
    mov     %rcx, ApiView_head_finalized(%rdi)
    mov     %rax, %rcx
    shr     $18, %rcx
    and     $1, %ecx
    mov     %rcx, ApiView_is_optimistic(%rdi)
    movq    $0, ApiView_status(%rdi)
    cmpq    $API_OP_GET_BLOCK_HEADER, S9(%rsp)
    je      3f
    mov     S9(%rsp), %rcx                  # rax: the work's arg, below
    sub     $API_OP_GET_LIGHT_CLIENT_BOOTSTRAP, %rcx
    cmp     $(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP), %rcx
    ja      30f
    mov     (L + 48)(%rsp), %rdi            # the light client reads: the object, and its JSON
    mov     %r12, %rsi
    mov     S7(%rsp), %rdx
    mov     %r14, %rcx
    mov     S8(%rsp), %r8
    call    lantern_node_api_lc_read
    test    %rax, %rax
    jz      5f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    mov     L(%rsp), %rcx
    mov     %rcx, (%r14)
    LEAVE 64
30: cmpq    $API_OP_GET_SPEC, S9(%rsp)
    je      5f
    cmpq    $API_OP_GET_DEBUG_CHAIN_HEADS_V2, S9(%rsp)
    je      29f
    cmpq    $API_OP_GET_DEBUG_FORK_CHOICE, S9(%rsp)
    je      28f
    shr     $24, %rax                       # a state at the work's slot, else the work that brought it there failed
    mov     NODE_STATE_SLOT(%r13), %rdi
    cmpq    $API_OP_GET_LIVENESS, S9(%rsp)  # getLiveness: the state at its own slot, the epoch in arg
    je      43f
    cmp     %rax, %rdi
    jne     42f
43: lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    cmpq    $API_OP_GET_BLOCK_REWARDS, S9(%rsp)
    je      277f
    cmpq    $API_OP_GET_SYNC_COMMITTEE_REWARDS, S9(%rsp)
    je      278f
    cmpq    $API_OP_GET_STATE_VALIDATOR, S9(%rsp)
    jne     271f
    mov     %r13, %rdi                      # getStateValidator: the validator of its ids
    mov     S7(%rsp), %rsi
    test    %rsi, %rsi
    jz      8f
    call    lantern_node_api_find_validator
    mov     S8(%rsp), %rdi
    mov     %r13, ApiView_val_state(%rdi)
    mov     %rax, ApiView_val_index(%rdi)
    jmp     5f
271: cmpq   $API_OP_GET_STATE_RANDAO, S9(%rsp)   # getStateRandao: lantern_node_randao of the epoch in data
    jne     272f
    mov     S7(%rsp), %rax
    test    %rax, %rax
    jz      41f
    cmpq    $8, 16(%rax)
    jb      41f
    mov     8(%rax), %rsi
    mov     (%rax,%rsi), %rsi
    mov     %r13, %rdi
    mov     S8(%rsp), %rdx
    add     $ApiView_randao, %rdx
    FORK_CALL node_randao
    jmp     275f
272: cmpq   $API_OP_GET_EPOCH_SYNC_COMMITTEES, S9(%rsp)  # lantern_node_sync_committee of the epoch in data, its out at the end of scratch
    jne     274f
    mov     S7(%rsp), %rax
    test    %rax, %rax
    jz      41f
    cmpq    $8, 16(%rax)
    jb      41f
    mov     8(%rax), %rsi
    mov     (%rax,%rsi), %rsi
    mov     (%r14), %rcx
    sub     $(8 * SYNC_COMMITTEE_SIZE), %rcx
    jb      71f
    mov     %rcx, (%r14)
    add     %r14, %rcx
    mov     S8(%rsp), %rax
    mov     %rcx, ApiView_sync_out(%rax)
    mov     %r13, %rdi
    mov     %r14, %rdx
    FORK_CALL node_sync_committee
    jmp     275f
274: cmpq   $API_OP_GET_SYNC_COMMITTEE_DUTIES, S9(%rsp)  # lantern_node_sync_committee of the state's epoch, or of the next period's
    jne     273f
    mov     S7(%rsp), %rax
    test    %rax, %rax
    jz      41f
    mov     S8(%rsp), %rcx
    mov     %rax, ApiView_sd_ids(%rcx)
    mov     %r13, ApiView_val_state(%rcx)
    mov     NODE_STATE_SLOT(%r13), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %rsi
    testq   $(API_VALUE_NEXT_PERIOD << 16), NodeAction_arg(%r12)
    jz      2741f
    add     $EPOCHS_PER_SYNC_COMMITTEE_PERIOD, %rsi
2741: mov   (%r14), %rcx
    sub     $(8 * SYNC_COMMITTEE_SIZE), %rcx
    jb      71f
    mov     %rcx, (%r14)
    add     %r14, %rcx
    mov     S8(%rsp), %rax
    mov     %rcx, ApiView_sync_out(%rax)
    mov     %r13, %rdi
    mov     %r14, %rdx
    FORK_CALL node_sync_committee
    jmp     275f
273: cmpq   $API_OP_GET_PROPOSER_LOOKAHEAD, S9(%rsp)     # lantern_node_proposer_lookahead; the version the state's fork
    jne     20f
    mov     S8(%rsp), %rsi
    mov     %r10, ApiView_fork(%rsi)
    add     $ApiView_lookahead, %rsi
    mov     %r13, %rdi
    FORK_CALL node_proposer_lookahead
275: cmp    $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    cmp     $LANTERN_NO_STATE_ANSWER, %rax  # no answer in the state: 400
    jne     276f
    mov     S8(%rsp), %rdi
    movq    $400, ApiView_status(%rdi)
    jmp     5f
276: test   %rax, %rax
    jz      5f
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
277: mov    S7(%rsp), %rax                  # getBlockRewards: lantern_node_block_rewards of the block in data, its out at the end of scratch
    test    %rax, %rax
    jz      41f
    mov     (%r14), %rcx
    sub     $48, %rcx
    jb      71f
    mov     %rcx, (%r14)
    lea     (%r14,%rcx), %rax
    mov     S8(%rsp), %rdi
    mov     %rax, ApiView_live_out(%rdi)
    mov     %r13, %rdi
    mov     S7(%rsp), %rsi
    mov     (L + 40)(%rsp), %rdx
    mov     (L + 48)(%rsp), %rcx
    lea     Node_config(%rbx), %r8
    mov     %r14, %r9
    sub     $16, %rsp                       # the seventh argument: out
    mov     %rax, (%rsp)
    FORK_CALL node_block_rewards
    add     $16, %rsp
    jmp     279f
278: mov    S7(%rsp), %rax                  # getSyncCommitteeRewards: lantern_node_sync_rewards, its out at the end of scratch; its ids in state_b
    test    %rax, %rax
    jz      41f
    mov     S8(%rsp), %rdi
    mov     (L + 40)(%rsp), %rax
    mov     %rax, ApiView_sd_ids(%rdi)
    mov     %r13, ApiView_val_state(%rdi)
    mov     (%r14), %rcx
    MOVQ    %rax, 24 + 16 * SYNC_COMMITTEE_SIZE
    sub     %rax, %rcx
    jb      71f
    mov     %rcx, (%r14)
    lea     (%r14,%rcx), %rcx
    mov     %rax, (%rcx)
    mov     %rcx, ApiView_live_out(%rdi)
    mov     %r13, %rdi
    mov     S7(%rsp), %rsi
    mov     %r14, %rdx
    FORK_CALL node_sync_rewards
279: cmp    $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    cmp     $LANTERN_NO_STATE_ANSWER, %rax  # no answer in the state: 400
    jne     276b
    mov     S8(%rsp), %rdi
    movq    $400, ApiView_status(%rdi)
    jmp     5f
20: cmpq    $API_OP_PRODUCE_ATTESTATION_DATA, S9(%rsp)
    jne     25f
    mov     S7(%rsp), %rax                  # produceAttestationData: lantern_node_attestation_data, its index in data
    test    %rax, %rax
    jz      41f
    cmpq    $8, 16(%rax)
    jb      41f
    mov     8(%rax), %rdx
    mov     (%rax,%rdx), %rdx
    mov     %r13, %rdi
    lea     Node_config(%rbx), %rsi
    mov     %r14, %rcx
    mov     S8(%rsp), %r8
    add     $ApiView_att, %r8
    FORK_CALL node_attestation_data
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      5f
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
25: cmpq    $API_OP_GET_ATTESTER_DUTIES, S9(%rsp)
    jne     251f
    mov     S7(%rsp), %rax                  # getAttesterDuties: lantern_node_attester_duties of its ids, its out at the end of scratch
    test    %rax, %rax
    jz      41f
    mov     16(%rax), %rax
    shr     $6, %rax
    mov     S8(%rsp), %rdi
    mov     %rax, ApiView_ad_count(%rdi)
    imul    $48, %rax, %rax
    add     $40, %rax
    mov     (%r14), %rcx
    sub     %rax, %rcx
    jb      71f
    mov     %rcx, (%r14)
    lea     (%r14,%rcx), %r8
    mov     %r8, ApiView_ad_out(%rdi)
    mov     %r13, %rdi
    lea     Node_config(%rbx), %rsi
    mov     S7(%rsp), %rdx
    mov     %r14, %rcx
    FORK_CALL node_attester_duties
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      24f
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
251: cmpq   $API_OP_GET_LIVENESS, S9(%rsp)
    jne     26f
    mov     S7(%rsp), %rax                  # getLiveness: lantern_node_liveness of its ids and the epoch, its out at the end of scratch
    test    %rax, %rax
    jz      41f
    mov     S8(%rsp), %rdi
    mov     %rax, ApiView_sd_ids(%rdi)
    mov     16(%rax), %rax
    shr     $6, %rax
    add     $7, %rax
    and     $-8, %rax
    mov     (%r14), %rcx
    sub     %rax, %rcx
    jb      71f
    mov     %rcx, (%r14)
    lea     (%r14,%rcx), %rax
    mov     %rax, ApiView_live_out(%rdi)
    mov     %r13, %rdi
    lea     Node_config(%rbx), %rsi
    mov     (L + 32)(%rsp), %rdx
    mov     S7(%rsp), %rcx
    mov     NodeAction_arg(%r12), %r8
    shr     $24, %r8
    mov     %r14, %r9
    sub     $16, %rsp                       # the seventh argument: out
    mov     %rax, (%rsp)
    FORK_CALL node_liveness
    add     $16, %rsp
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      24f
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
26: cmpq    $API_OP_GET_PROPOSER_DUTIES, S9(%rsp)
    je      261f
    cmpq    $API_OP_GET_PROPOSER_DUTIES_V2, S9(%rsp)
    jne     23f
261: mov    %r13, %rdi                      # getProposerDuties and V2: lantern_node_proposers
    lea     Node_config(%rbx), %rsi
    mov     %r14, %rdx
    mov     S8(%rsp), %rcx
    add     $ApiView_duties, %rcx
    FORK_CALL node_proposers
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      262f
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
262: cmpq   $API_OP_GET_PROPOSER_DUTIES_V2, S9(%rsp)
    jne     24f
    mov     NODE_STATE_SLOT(%r13), %rax     # V2 from epoch 1: get_block_root_at_slot of max(the first slot - SLOTS_PER_EPOCH - 1, 0)
    test    %rax, %rax
    jz      24f
    sub     $(SLOTS_PER_EPOCH + 1), %rax
    jae     263f
    xor     %eax, %eax
263: mov    %rax, (L + 56)(%rsp)
    mov     NODE_STATE_SLOT(%r13), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    lea     (L + 56)(%rsp), %rsi
    mov     S8(%rsp), %rdx
    add     $ApiView_duties, %rdx
    FORK_CALL get_block_root_at_slot
    test    %rax, %rax
    jz      24f
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
24: mov     S8(%rsp), %rdi
    mov     %r13, ApiView_val_state(%rdi)
    jmp     5f
23: cmpq    $API_OP_GET_STATE_FINALITY_CHECKPOINTS, S9(%rsp)
    jne     21f
    mov     %r13, %rdi                      # finality_checkpoints
    mov     S8(%rsp), %rsi
    add     $ApiView_previous_justified, %rsi
    FORK_CALL node_state_checkpoints
    jmp     5f
21: cmpq    $API_OP_GET_STATE_FORK, S9(%rsp)
    jne     22f
    mov     S8(%rsp), %rdi                  # fork
    add     $ApiView_state_fork, %rdi
    lea     NODE_STATE_FORK(%r13), %rsi
    mov     $16, %edx
    call    lantern_copy
    jmp     5f
22: mov     %r13, %rdi                      # root
    mov     (Node_config + CONFIG_STATE_CACHE)(%rbx), %rsi
    mov     %r14, %rdx
    mov     S8(%rsp), %rcx
    add     $ApiView_head_root, %rcx
    FORK_CALL state_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jnz     41f
    jmp     5f
3:  mov     S7(%rsp), %rdi
    test    %rdi, %rdi
    jz      33f
    cmpq    $(100 + 84), 16(%rdi)           # header: of the bytes, at the fork of their slot
    jb      41f
    mov     8(%rdi), %rax
    add     %rdi, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     %rax, (L + 8)(%rsp)
    mov     S7(%rsp), %rdi
    mov     %r14, %rsi
    mov     S8(%rsp), %rdx                  # the header's slot lands on the root's last 8 bytes
    add     $(ApiView_proposer_index - 8), %rdx
    FORK_CALL node_block_header
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jnz     41f
    mov     S8(%rsp), %rdx
    mov     (ApiView_proposer_index - 8)(%rdx), %rax
    mov     %rax, ApiView_head_slot(%rdx)
    mov     NodeAction_arg(%r12), %rax      # the root: the node's block's, else of the bytes
    shr     $24, %rax
    jnz     34f
    mov     (L + 8)(%rsp), %r10
    mov     S7(%rsp), %rdi
    mov     %r14, %rsi
    add     $ApiView_head_root, %rdx
    lea     (L + 16)(%rsp), %rcx
    lea     (L + 24)(%rsp), %r8
    FORK_CALL node_block_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jnz     41f
    cmpq    $0, (L + 16)(%rsp)
    jne     41f
    jmp     5f
33: mov     S8(%rsp), %rdi                  # no bytes: the state's latest_block_header, a zero signature
    add     $ApiView_proposer_index, %rdi
    lea     (NODE_STATE_HEADER + 8)(%r13), %rsi
    mov     $(112 - 8), %edx
    call    lantern_copy
    mov     S8(%rsp), %rdi
    mov     NODE_STATE_HEADER(%r13), %rax
    mov     %rax, ApiView_head_slot(%rdi)
    mov     ApiView_state_root(%rdi), %rax
    or      (ApiView_state_root + 8)(%rdi), %rax
    or      (ApiView_state_root + 16)(%rdi), %rax
    or      (ApiView_state_root + 24)(%rdi), %rax
    jnz     34f
    mov     NODE_STATE_SLOT(%r13), %rdi     # a zero state_root: the state's root
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    mov     (Node_config + CONFIG_STATE_CACHE)(%rbx), %rsi
    mov     %r14, %rdx
    mov     S8(%rsp), %rcx
    add     $ApiView_state_root, %rcx
    FORK_CALL state_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jnz     41f
34: mov     NodeAction_arg(%r12), %rax      # the root of the node's block, index - 1
    shr     $24, %rax
    jz      5f
    dec     %rax
    imul    $NodeBlock__mem, %rax, %rax
    add     Node_blocks(%rbx), %rax
    add     %rbx, %rax
    mov     S8(%rsp), %rdi
    add     $ApiView_head_root, %rdi
    COPY32  %rdi, %rax
5:  mov     NodeAction_arg(%r12), %rax      # the response, in the event
    shr     $8, %rax
    movzbl  %al, %eax
    mov     %rax, %r8
    and     $API_ANSWER_CLOSE, %r8d
    jnz     51f
    test    $API_ANSWER_HTTP10, %al
    jz      51f
    mov     $API_R_KEEP, %r8d
51: mov     %r8, %rcx                       # SSZ: API_R_SSZ
    or      $API_R_SSZ, %rcx
    test    $API_ANSWER_SSZ, %al
    cmovnz  %rcx, %r8
    mov     S10(%rsp), %rax
    sub     $NodeEvent_chunk, %rax
    and     $~7, %rax
    cmp     $24, %rax
    jb      71f
    mov     %rax, NodeEvent_chunk(%r15)
    mov     S8(%rsp), %rdi
    lea     NodeEvent_chunk(%r15), %rsi
    mov     $200, %edx
    mov     S9(%rsp), %rcx
    cmp     $API_OP_GET_STATE_VALIDATOR, %rcx   # no such validator: 404
    jne     52f
    cmpq    $-1, ApiView_val_index(%rdi)
    jne     52f
    mov     $404, %edx
    mov     $API_BODY_ERROR, %ecx
52: cmpq    $0, ApiView_status(%rdi)        # an error status of the work
    je      53f
    mov     ApiView_status(%rdi), %rdx
    mov     $API_BODY_ERROR, %ecx
    and     $~API_R_SSZ, %r8
    jmp     54f
53: cmpq    $API_OP_GET_PROPOSER_LOOKAHEAD, S9(%rsp)    # Eth-Consensus-Version of getProposerLookahead and the light client reads
    je      531f
    mov     S9(%rsp), %rax
    sub     $API_OP_GET_LIGHT_CLIENT_BOOTSTRAP, %rax
    cmp     $(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP), %rax
    ja      54f
    cmpq    $API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE, S9(%rsp)  # no version: of each item
    je      54f
531: or     $API_R_VERSION, %r8
54: call    lantern_api_respond
    test    %rax, %rax
    jnz     71f
    mov     (NodeEvent_chunk + 16)(%r15), %rax  # the event's size covers the chunk
    add     $(NodeEvent_chunk + 24 + 7), %rax
    and     $~7, %rax
    mov     %rax, (%r15)
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%r15)
    jmp     9f
    # getDebugChainHeadsV2: a byte for each store node at the end of scratch, 1 when it is out of the tree, 2 when a node not out has it as parent
29: mov     Store_blocks(%rbp), %rsi
    add     %rbp, %rsi
    mov     (Store_blocks + 8)(%rbp), %rcx
    lea     7(%rcx), %rdx
    and     $~7, %rdx
    mov     (%r14), %rax
    sub     %rdx, %rax
    jb      71f
    mov     %rax, (%r14)
    lea     (%r14,%rax), %rdi
    mov     S8(%rsp), %rax
    mov     %rdi, ApiView_heads(%rax)
    mov     %rbp, ApiView_val_state(%rax)
    xor     %edx, %edx
291: cmp    %rcx, %rdx
    jae     5b
    imul    $BlockNode__mem, %rdx, %r8
    add     %rsi, %r8
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_INVALIDATED, BlockNode_payload_status(%r8)
    sete    %al
    mov     BlockNode_parent(%r8), %r9
    cmp     %rcx, %r9
    jae     293f
    movzbl  (%rdi,%r9), %r10d
    and     $1, %r10d
    or      %r10d, %eax
    jnz     293f
    orb     $2, (%rdi,%r9)
293: mov    %al, (%rdi,%rdx)
    inc     %rdx
    jmp     291b
    # getDebugForkChoice: lantern_node_weights of the fork of the head's slot into the end of scratch; a failure, the error 500
28: mov     (Store_blocks + 8)(%rbp), %rcx
    shl     $3, %rcx
    mov     (%r14), %rax
    sub     %rcx, %rax
    jb      71f
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     S8(%rsp), %rdi
    mov     %rax, ApiView_weights(%rdi)
    mov     %rbp, ApiView_val_state(%rdi)
    mov     ApiView_head_slot(%rdi), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     %rbp, %rdi
    mov     %r14, %rsi
    mov     S8(%rsp), %rdx
    mov     ApiView_weights(%rdx), %rdx
    FORK_CALL node_weights
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      5b
    mov     S8(%rsp), %rdi
    movq    $500, ApiView_status(%rdi)
    jmp     5b
42: movq    $LANTERN_INVALID_SLOT, NodeEvent_result(%r15)
    jmp     9f
41: movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%r15)
9:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 64
8:  mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 64
71: mov     L(%rsp), %rax
    mov     %rax, (%r14)
7:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
END_FUNCTION lantern_node_api_run

/* ---------------------------------------------------------------- Lookup (beacon-api.md, Common rules) */

/* rax = the NodeBlock index of the imported parent of the entry rdi, or 2^64 - 1; rdx = its entry. Uses rcx, r11, xmm0-xmm2. */
LOCAL_FUNCTION lantern_node_api_parent
    FRAME 0
    add     $NodeBlock_parent_root, %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      9f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    je      9f
    mov     $-1, %rax
9:  UNFRAME 0
END_FUNCTION lantern_node_api_parent

/*
 * The block of the chain at or below the slot rdi: rax = its NodeBlock index, rdx = its entry; or
 * rax = 2^64 - 1 when the lowest block of the chain the node keeps, rdx (0 with no head), is above
 * the slot. Locals: the slot, an entry.
 */
LOCAL_FUNCTION lantern_node_api_below
    FRAME 16
    mov     %rdi, (%rsp)
    lea     Node_head_root(%rbx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    jne     1f
    xor     %edx, %edx
    UNFRAME 16
1:  mov     (%rsp), %rcx
    cmp     %rcx, NodeBlock_slot(%rdx)
    jbe     9f
    mov     %rdx, 8(%rsp)
    mov     %rdx, %rdi
    call    lantern_node_api_parent
    cmp     $-1, %rax
    jne     1b
    mov     8(%rsp), %rdx
9:  UNFRAME 16
END_FUNCTION lantern_node_api_below

/* rax = 1 when the block entry rdi is on the chain, else 0. Locals: the entry. */
LOCAL_FUNCTION lantern_node_api_on_chain
    FRAME 16
    mov     %rdi, (%rsp)
    mov     NodeBlock_slot(%rdi), %rdi
    call    lantern_node_api_below
    cmp     $-1, %rax
    je      8f
    xor     %eax, %eax
    cmp     (%rsp), %rdx
    sete    %al
    UNFRAME 16
8:  xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_node_api_on_chain

/* rax = 1 when the slot rdi is at most that of the block of the store's finalized root, else 0. Locals: rdi. */
LOCAL_FUNCTION lantern_node_api_final_block
    FRAME 16
    mov     %rdi, (%rsp)
    call    lantern_node_f_slot
    cmp     $-1, %rax
    je      8f
    mov     (%rsp), %rcx
    cmp     %rax, %rcx
    setbe   %al
    movzbl  %al, %eax
    UNFRAME 16
8:  xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_node_api_final_block

/*
 * The block of the block_id of the ApiRoute rdi into the ApiView rsi (beacon-api.md, Common rules):
 * head_root, head_slot, canonical, head_finalized, is_optimistic, look_index, look_data, and for a
 * block the node keeps look_state and look_state_slot. rax = 0, or 404 for none. rbx the node, rbp
 * the store. r12 the route, r13 the view, S7 the entry, S8 the slot. Locals: L the Db's slot.
 */
LOCAL_FUNCTION lantern_node_api_block
    ENTER 16
    mov     %rdi, %r12
    mov     %rsi, %r13
    movq    $-1, ApiView_look_index(%r13)
    movq    $0, ApiView_look_data(%r13)
    movq    $0, ApiView_look_state(%r13)
    movq    $0, ApiView_look_copy(%r13)
    mov     ApiRoute_id_kind(%r12), %rax
    lea     Node_head_root(%rbx), %rdi      # head
    cmp     $API_ID_HEAD, %rax
    je      4f
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rdi    # finalized
    cmp     $API_ID_FINALIZED, %rax
    je      4f
    cmp     $API_ID_ROOT, %rax
    jne     3f
    lea     ApiRoute_id_root(%r12), %rdi    # a root: the node's imported block, else the Db's
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      1f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    je      5f
1:  testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      80f
    mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    lea     ApiRoute_id_root(%r12), %rsi
    lea     L(%rsp), %rdx
    call    lantern_db_find_root
    mov     L(%rsp), %rax
    cmp     $-1, %rax
    je      80f
    mov     %rax, S8(%rsp)
    lea     ApiRoute_id_root(%r12), %rax
    jmp     6f
3:  xor     %ecx, %ecx                      # genesis: the slot 0; a slot
    cmp     $API_ID_SLOT, %rax
    jne     31f
    mov     ApiRoute_id_slot(%r12), %rcx
31: mov     %rcx, S8(%rsp)
    mov     %rcx, %rdi
    call    lantern_node_api_below
    cmp     $-1, %rax
    je      32f
    mov     S8(%rsp), %rcx
    cmp     %rcx, NodeBlock_slot(%rdx)
    jne     80f                             # an empty slot, or past the head
    jmp     5f
32: testq   $NODE_FLAG_DB, Node_flags(%rbx) # below the chain's blocks the node keeps: the Db's
    jz      80f
    mov     S8(%rsp), %rdi
    call    lantern_node_db_slot
    test    %rax, %rax
    jz      80f
    jmp     6f                              # DbSlot_root is at 0
4:  call    lantern_node_find_block                 # head, finalized: the block of that root
    cmp     $-1, %rax
    je      80f
5:  mov     %rdx, S7(%rsp)                  # a block the node keeps
    mov     %rax, ApiView_look_index(%r13)
    lea     ApiView_head_root(%r13), %rax
    COPY32  %rax, %rdx
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, S8(%rsp)
    mov     %rax, ApiView_head_slot(%r13)
    mov     %rax, ApiView_look_state_slot(%r13)
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rdx)
    sete    %al
    mov     %rax, ApiView_is_optimistic(%r13)
    mov     NodeBlock_state_id(%rdx), %rax
    mov     %rax, ApiView_look_state(%r13)
    mov     NodeBlock_data_id(%rdx), %rax
    test    %rax, %rax
    jnz     51f
    mov     %rdx, %rdi
    call    lantern_node_api_db_ref
51: mov     %rax, ApiView_look_data(%r13)
    mov     S7(%rsp), %rdi
    call    lantern_node_api_on_chain
    mov     %rax, ApiView_canonical(%r13)
    test    %rax, %rax
    jz      52f
    mov     S8(%rsp), %rdi
    call    lantern_node_api_final_block
52: mov     %rax, ApiView_head_finalized(%r13)
    xor     %eax, %eax
    LEAVE 16
6:  lea     ApiView_head_root(%r13), %rcx   # a block of the Db: its root at rax, its slot S8
    COPY32  %rcx, %rax
    mov     S8(%rsp), %rdi
    mov     %rdi, ApiView_head_slot(%r13)
    movq    $0, ApiView_is_optimistic(%r13)
    movq    $1, ApiView_canonical(%r13)
    call    lantern_node_db_block
    mov     %rax, ApiView_look_data(%r13)
    mov     S8(%rsp), %rdi
    call    lantern_node_api_final_block
    mov     %rax, ApiView_head_finalized(%r13)
    xor     %eax, %eax
    LEAVE 16
80: mov     $404, %eax
    LEAVE 16
END_FUNCTION lantern_node_api_block

/*
 * The state of the state_id of the ApiRoute rdi into the ApiView rsi (beacon-api.md, Common
 * rules): look_state, a state the node keeps, at look_state_slot; head_slot the slot it goes to;
 * head_finalized and is_optimistic. rax = 0, or 404 for none; with look_replay 1 (which goes to 0)
 * a block at or below F's slot with no post-state comes from the replay (node.md): rax = 1 while
 * the request waits for it. rbx the node, rbp the store, r14 the scratch, r15 the actions. r12 the
 * route, r13 the view, S7 the block's entry, then the slot scanned, S8 the slot, S9 the checkpoint.
 * Locals: L look_replay.
 */
LOCAL_FUNCTION lantern_node_api_state
    ENTER 16
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     ApiView_look_replay(%r13), %rax
    mov     %rax, L(%rsp)
    movq    $0, ApiView_look_replay(%r13)
    movq    $0, ApiView_look_state(%r13)
    movq    $0, ApiView_look_copy(%r13)
    movq    $-1, ApiView_look_index(%r13)
    mov     ApiRoute_id_kind(%r12), %rax
    cmp     $API_ID_HEAD, %rax
    jne     1f
    lea     Node_head_root(%rbx), %rdi      # head: its post-state at its slot
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      80f
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, S8(%rsp)
    jmp     5f
1:  lea     Store_finalized_checkpoint(%rbp), %rcx
    cmp     $API_ID_FINALIZED, %rax
    je      2f
    lea     Store_justified_checkpoint(%rbp), %rcx
    cmp     $API_ID_JUSTIFIED, %rax
    jne     3f
2:  mov     %rcx, S9(%rsp)                  # a checkpoint: at the first slot of its epoch
    mov     (%rcx), %rax
    imul    $SLOTS_PER_EPOCH, %rax, %rax
    mov     %rax, S8(%rsp)
    lea     8(%rcx), %rdi                   # the optimistic status of its block
    call    lantern_node_find_block
    xor     %ecx, %ecx
    cmp     $-1, %rax
    je      21f
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rdx)
    sete    %cl
21: mov     %rcx, ApiView_is_optimistic(%r13)
    mov     S9(%rsp), %rsi                  # its NodeCheckpoint's state, else its block's post-state
    mov     (%rsi), %rdi
    add     $8, %rsi
    call    lantern_node_find_checkpoint
    cmp     $-1, %rax
    je      22f
    mov     NodeCheckpoint_state_id(%rdx), %rax
    test    %rax, %rax
    jz      22f
    mov     %rax, ApiView_look_state(%r13)
    mov     S8(%rsp), %rax
    mov     %rax, ApiView_look_state_slot(%r13)
    jmp     7f
22: mov     S9(%rsp), %rdi
    add     $8, %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      80f
    jmp     5f
3:  cmp     $API_ID_ROOT, %rax              # a state root: none in this version
    je      80f
    xor     %ecx, %ecx                      # genesis: the slot 0; a slot, at most the store's
    cmp     $API_ID_SLOT, %rax
    jne     31f
    mov     ApiRoute_id_slot(%r12), %rcx
31: mov     %rcx, S8(%rsp)
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    cmp     %rax, S8(%rsp)
    ja      80f
    mov     S8(%rsp), %rdi
    call    lantern_node_api_below
    cmp     $-1, %rax
    je      75f
5:  mov     %rdx, S7(%rsp)                  # the block's post-state, again when the node let it go
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rdx)
    sete    %al
    mov     %rax, ApiView_is_optimistic(%r13)
    mov     NodeBlock_state_id(%rdx), %rax
    test    %rax, %rax
    jnz     6f
    call    lantern_node_f_slot
    cmp     $-1, %rax
    je      80f
    mov     S7(%rsp), %rdi
    cmp     %rax, NodeBlock_slot(%rdi)
    jbe     70f
    call    lantern_node_rebuild
    test    %rax, %rax
    jz      80f
6:  mov     %rax, ApiView_look_state(%r13)
    mov     S7(%rsp), %rdx
    mov     NodeBlock_slot(%rdx), %rax
    mov     %rax, ApiView_look_state_slot(%r13)
7:  mov     S8(%rsp), %rax                  # finalized: at most the first slot of the finalized epoch
    mov     %rax, ApiView_head_slot(%r13)
    mov     Store_finalized_checkpoint(%rbp), %rcx
    imul    $SLOTS_PER_EPOCH, %rcx, %rcx
    xor     %edx, %edx
    cmp     %rcx, %rax
    setbe   %dl
    mov     %rdx, ApiView_head_finalized(%r13)
    xor     %eax, %eax
    LEAVE 16
70: mov     S7(%rsp), %rdx                  # at or below F's slot: the replay
    lea     NodeBlock_root(%rdx), %rdi
    mov     NodeBlock_slot(%rdx), %rsi
    jmp     71f
75: testq   $NODE_FLAG_DB, Node_flags(%rbx) # below the chain's lowest block: the Db's block at or below the slot
    jz      80f
    mov     S8(%rsp), %rax
    mov     %rax, S7(%rsp)
    cmp     Node_base_slot(%rbx), %rax
    jae     76f
    cmp     Node_archive_first(%rbx), %rax  # below the base's slot: from the lowest state record on
    jb      80f
78: mov     S7(%rsp), %rdi
    call    lantern_node_db_slot
    mov     %rax, %rdi
    mov     S7(%rsp), %rsi
    test    %rax, %rax
    jnz     71f
    cmpq    $0, S7(%rsp)
    je      80f
    decq    S7(%rsp)
    jmp     78b
76: mov     S7(%rsp), %rdi
    cmp     Node_base_slot(%rbx), %rdi
    jbe     77f
    call    lantern_node_db_slot
    mov     %rax, %rdi                      # its DbSlot: the root at 0
    mov     S7(%rsp), %rsi
    test    %rax, %rax
    jnz     71f
    decq    S7(%rsp)
    jmp     76b
77: xor     %edi, %edi                      # none above the base's slot: the base state
    mov     Node_base_slot(%rbx), %rsi
71: cmpq    $0, L(%rsp)
    je      80f
    call    lantern_node_replay_get
    test    %rax, %rax
    jz      80f
    cmp     $1, %rax
    je      79f
    mov     %rax, ApiView_look_state(%r13)
    mov     %rdx, ApiView_look_state_slot(%r13)
    movq    $1, ApiView_look_copy(%r13)
    movq    $0, ApiView_is_optimistic(%r13)
    jmp     7b
79: LEAVE 16
80: mov     $404, %eax
    LEAVE 16
END_FUNCTION lantern_node_api_state

/*
 * (root rdi, or 0 for the base, slot rsi): the post-state of the block of root rdi at slot rsi, at
 * or below F's slot and at or above base_slot, by the replay (node.md): rax = a copy of it and rdx
 * its slot; 1 when the request waits for the replay; 0 for none. r12 the root, S7 the slot, S8 the
 * state, S9 the copy.
 */
LOCAL_FUNCTION lantern_node_replay_get
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, S7(%rsp)
    cmp     Node_base_slot(%rbx), %rsi
    ja      1f
    jb      6f
    mov     Node_anchor_state_id(%rbx), %rax    # the base's slot: the base state
    jmp     5f
6:  cmp     Node_archive_first(%rbx), %rsi  # below it: from the lowest state record on
    jb      8f
1:  test    %r12, %r12
    jz      8f
    mov     Node_replay_state(%rbx), %rax   # the last replay's state, of that root
    test    %rax, %rax
    jz      2f
    lea     Node_replay_root(%rbx), %rdi
    NE32    %rdi, %r12, 2f
    mov     Node_replay_state(%rbx), %rax
5:  mov     %rax, S8(%rsp)                  # a copy for the answer
    call    lantern_node_new_id
    mov     %rax, S9(%rsp)
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     S8(%rsp), %rsi
    mov     %rax, %rdx
    call    lantern_node_ids
    mov     S9(%rsp), %rax
    mov     S7(%rsp), %rdx
    LEAVE 0
2:  cmpq    $0, Node_replay_copy(%rbx)      # a replay in flight: the request waits
    jne     7f
    mov     Node_replay_state(%rbx), %rsi   # else one starts, for this block
    test    %rsi, %rsi
    jz      3f
    mov     $NODE_ACT_STATE_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
    movq    $0, Node_replay_state(%rbx)
3:  lea     Node_replay_root(%rbx), %rdi
    COPY32  %rdi, %r12
    mov     S7(%rsp), %rax
    mov     %rax, Node_replay_slot(%rbx)
    call    lantern_node_new_id
    mov     %rax, Node_replay_copy(%rbx)
    mov     %rax, %rdx
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     Node_anchor_state_id(%rbx), %rsi
    call    lantern_node_ids
    mov     Node_base_slot(%rbx), %rax
    mov     %rax, Node_replay_copy_slot(%rbx)
    inc     %rax
    mov     %rax, Node_replay_next(%rbx)
    mov     S7(%rsp), %rdi                  # a nearer base among the state records: the copy loads it
    call    lantern_node_archive_base
    cmp     $-1, %rax
    je      7f
    mov     %rax, Node_replay_copy_slot(%rbx)
    lea     1(%rax), %rcx
    mov     %rcx, Node_replay_next(%rbx)
    movq    $1, Node_replay_loading(%rbx)
    shr     $DB_SEGMENT_SHIFT, %rax         # the record's NODE_DB_REF, and with a diff the full state's at 0
    shl     $NODE_DB_SEGMENT_SHIFT, %rax
    bts     $63, %rax
    bts     $61, %rax
    lea     -1(%rdx), %rcx
    or      %rax, %rcx
    xor     %r8d, %r8d
    cmp     $1, %rdx
    cmovne  %rax, %r8
    mov     %r8, %rdx
    mov     $NODE_WORK_ARCHIVE_LOAD, %edi
    mov     Node_replay_copy(%rbx), %rsi
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    lantern_node_work
7:  mov     $1, %eax
    LEAVE 0
8:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_node_replay_get

/*
 * The state of the ApiView rdi at its slot (node.md, NODE_EV_API): when head_slot is past
 * look_state_slot, a STATE_COPY of look_state, the copy across the fork boundaries to head_slot,
 * and a SLOTS work of it to head_slot when it is below it; look_state is the copy, look_copy 1.
 * r12 the view, r13 the copy, S7 the copy's slot, S8 the fork of look_state_slot.
 */
LOCAL_FUNCTION lantern_node_api_advance
    ENTER 0
    mov     %rdi, %r12
    mov     ApiView_head_slot(%r12), %rax
    cmp     ApiView_look_state_slot(%r12), %rax
    jbe     9f
    call    lantern_node_new_id
    mov     %rax, %r13
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     ApiView_look_state(%r12), %rsi
    mov     %r13, %rdx
    call    lantern_node_ids
    mov     %r13, %rdi
    mov     ApiView_look_state(%r12), %rsi
    mov     ApiView_look_state_slot(%r12), %rdx
    mov     ApiView_head_slot(%r12), %rcx
    call    lantern_node_cross
    mov     %rax, %r13
    mov     ApiView_look_state_slot(%r12), %rdi     # the copy's slot: the first of the target's fork, when it crossed one
    mov     %rdi, S7(%rsp)
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, S8(%rsp)
    mov     ApiView_head_slot(%r12), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    cmp     S8(%rsp), %rax
    jbe     1f
    shl     $4, %rax
    mov     Node_config(%rbx,%rax), %rax
    imul    $SLOTS_PER_EPOCH, %rax, %rax
    cmp     S7(%rsp), %rax
    jbe     1f
    mov     %rax, S7(%rsp)
1:  mov     ApiView_head_slot(%r12), %r9
    cmp     S7(%rsp), %r9
    jbe     2f
    mov     $NODE_WORK_SLOTS, %edi
    mov     %r13, %rsi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    lantern_node_work
2:  mov     %r13, ApiView_look_state(%r12)
    movq    $1, ApiView_look_copy(%r12)
9:  LEAVE 0
END_FUNCTION lantern_node_api_advance

/*
 * A NODE_WORK_API_ENCODE of the operation rdi for the connection rsi with the answer flags rdx,
 * from the lookup in the ApiView rcx (node.md, NODE_EV_API); then a STATE_FREE of the state when it
 * is a copy. rax = 0, or 404 for a header with neither bytes nor a post-state. Locals: the view.
 */
LOCAL_FUNCTION lantern_node_api_encode
    FRAME 16
    mov     %rcx, (%rsp)
    mov     %rsi, %r8
    cmp     $API_OP_GET_SPEC, %rdi          # getSpec, getDebugChainHeadsV2: no state, no bytes, no values
    je      4f
    cmp     $API_OP_GET_DEBUG_CHAIN_HEADS_V2, %rdi
    je      4f
    cmp     $API_OP_GET_DEBUG_FORK_CHOICE, %rdi
    jne     1f
4:
    shl     $8, %rdx
    lea     (%rdi,%rdx), %r9
    xor     %esi, %esi
    xor     %ecx, %ecx
    jmp     3f
1:  mov     ApiView_canonical(%rcx), %r9
    mov     ApiView_head_finalized(%rcx), %rax
    lea     (%r9,%rax,2), %r9
    mov     ApiView_is_optimistic(%rcx), %rax
    lea     (%r9,%rax,4), %r9
    mov     ApiView_next_period(%rcx), %rax # API_VALUE_NEXT_PERIOD
    lea     (%r9,%rax,8), %r9
    shl     $16, %r9
    shl     $8, %rdx
    or      %rdx, %r9
    or      %rdi, %r9
    cmp     $API_OP_GET_BLOCK_HEADER, %rdi
    jne     2f
    mov     ApiView_look_index(%rcx), %rax  # getBlockHeader: the block's index + 1, its bytes or post-state
    inc     %rax
    shl     $24, %rax
    or      %rax, %r9
    xor     %esi, %esi
    mov     ApiView_look_data(%rcx), %rcx
    test    %rcx, %rcx
    jnz     3f
    mov     (%rsp), %rax
    mov     ApiView_look_state(%rax), %rsi
    test    %rsi, %rsi
    jnz     3f
    mov     $404, %eax
    UNFRAME 16
2:  mov     ApiView_head_slot(%rcx), %rax   # the others: the state at its slot; getStateValidator its ids
    shl     $24, %rax
    or      %rax, %r9
    mov     ApiView_look_state(%rcx), %rsi
    mov     ApiView_look_data(%rcx), %rax
    xor     %ecx, %ecx
    cmp     $API_OP_GET_STATE_VALIDATOR, %rdi
    cmove   %rax, %rcx
    cmp     $API_OP_PRODUCE_ATTESTATION_DATA, %rdi
    cmove   %rax, %rcx
    cmp     $API_OP_GET_ATTESTER_DUTIES, %rdi
    cmove   %rax, %rcx
    cmp     $API_OP_GET_SYNC_COMMITTEE_DUTIES, %rdi
    cmove   %rax, %rcx
    cmp     $API_OP_GET_STATE_RANDAO, %rdi
    cmove   %rax, %rcx
    cmp     $API_OP_GET_EPOCH_SYNC_COMMITTEES, %rdi
    cmove   %rax, %rcx
    cmp     $API_OP_GET_LIVENESS, %rdi
    cmove   %rax, %rcx
3:  mov     $NODE_WORK_API_ENCODE, %edi
    xor     %edx, %edx
    call    lantern_node_work
    mov     (%rsp), %rax                    # a copy goes after the work
    cmpq    $0, ApiView_look_copy(%rax)
    je      9f
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     ApiView_look_state(%rax), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
9:  xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_node_api_encode

/*
 * (connection rdi, route rsi, answer flags rdx, wait rcx) -> rax: a state_id of a root (node.md,
 * NODE_EV_API): a NodeApi entry with API_STREAM_LOOKUP and a NODE_WORK_API_LOOKUP with the head's
 * post-state; with wait 1, a state_id of a slot whose state waits for the replay: the entry with
 * API_STREAM_REPLAY and the slot at API_REPLAY_SLOT of its cursor, and no work. 0, or 404 with no
 * head post-state. rbx the node, r15 the actions. r12 the route, S7 the flags, S9 the connection,
 * S8 the head's post-state, S10 wait. Locals: L the entry's index.
 */
LOCAL_FUNCTION lantern_node_api_lookup
    ENTER 16
    mov     %rdi, S9(%rsp)
    mov     %rsi, %r12
    mov     %rcx, S10(%rsp)
    or      $(API_STREAM_LOOKUP | API_STREAM_BUSY), %rdx
    test    %rcx, %rcx
    jz      3f
    or      $API_STREAM_REPLAY, %rdx
3:  cmpq    $API_TYPE_SSZ, ApiRoute_response(%r12)
    jne     1f
    or      $API_STREAM_SSZ, %rdx
1:  mov     %rdx, S7(%rsp)
    lea     Node_head_root(%rbx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      80f
    mov     NodeBlock_state_id(%rdx), %rax
    test    %rax, %rax
    jz      80f
    mov     %rax, S8(%rsp)
    call    lantern_node_api_new
    mov     %rax, L(%rsp)
    mov     %rdx, %r13
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     S9(%rsp), %rax
    mov     %rax, NodeApi_connection(%r13)
    mov     ApiRoute_op(%r12), %rax
    mov     %rax, NodeApi_op(%r13)
    mov     S7(%rsp), %rax
    mov     %rax, NodeApi_flags(%r13)
    lea     NodeApi_cursor(%r13), %rax
    lea     ApiRoute_id_root(%r12), %rcx
    COPY32  %rax, %rcx
    mov     ApiRoute_statuses(%r12), %rax   # statuses, validator_id, epoch, slot, index and present; the validator operations' ids

    mov     %rax, (NodeApi_cursor + 32)(%r13)
    mov     ApiRoute_epoch(%r12), %rax
    mov     %rax, (NodeApi_cursor + 104)(%r13)
    mov     ApiRoute_slot(%r12), %rax
    mov     %rax, (NodeApi_cursor + 112)(%r13)
    mov     ApiRoute_index(%r12), %rax
    mov     %rax, (NodeApi_cursor + 120)(%r13)
    mov     ApiRoute_present(%r12), %rax
    mov     %rax, (NodeApi_cursor + 128)(%r13)
    lea     (NodeApi_cursor + 40)(%r13), %rdi
    lea     ApiRoute_validator(%r12), %rsi
    mov     $64, %edx
    call    lantern_copy
    mov     ApiRoute_op(%r12), %rax
    cmp     $API_OP_GET_ATTESTER_DUTIES, %rax   # and getAttesterDuties'
    je      21f
    sub     $API_OP_GET_STATE_VALIDATORS, %rax
    cmp     $(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS), %rax
    ja      2f
21: mov     %r12, %rdi
    call    lantern_node_api_ids
    mov     %rax, NodeApi_data(%r13)
    test    %rax, %rax
    jz      2f
    orq     $API_STREAM_OWN, NodeApi_flags(%r13)
2:  cmpq    $0, S10(%rsp)                   # the replay's wait: the slot of the state_id, no work
    je      4f
    xor     %eax, %eax
    cmpq    $API_ID_SLOT, ApiRoute_id_kind(%r12)
    jne     5f
    mov     ApiRoute_id_slot(%r12), %rax
5:  mov     %rax, (NodeApi_cursor + API_REPLAY_SLOT)(%r13)
    xor     %eax, %eax
    LEAVE 16
4:  mov     $NODE_WORK_API_LOOKUP, %edi
    mov     S8(%rsp), %rsi
    xor     %edx, %edx
    xor     %ecx, %ecx
    mov     S9(%rsp), %r8
    mov     L(%rsp), %r9
    call    lantern_node_work
    xor     %eax, %eax
    LEAVE 16
80: mov     $404, %eax
    LEAVE 16
END_FUNCTION lantern_node_api_lookup

/*
 * The NODE_EV_WORK_DONE rdi of a NODE_WORK_API_LOOKUP (node.md, lantern_node_step): its entry goes
 * on with the slot found (lantern_node_api_rerun), the replay allowed. r12 the event.
 */
LOCAL_FUNCTION lantern_node_api_lookup_done
    ENTER 0
    mov     %rdi, %r12
    mov     NodeAction_arg(%r12), %rax
    PART    %rdi, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     99f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %rdi
    mov     NodeApi_connection(%rdi), %rax
    test    %rax, %rax
    jz      99f
    cmp     NodeAction_target(%r12), %rax
    jne     99f
    testq   $API_STREAM_LOOKUP, NodeApi_flags(%rdi)
    jz      99f
    mov     NodeEvent_index(%r12), %rsi
    mov     $1, %edx
    call    lantern_node_api_rerun
99: LEAVE 0
END_FUNCTION lantern_node_api_lookup_done

/*
 * (entry rdi, slot rsi, replay rdx): a lookup entry goes on with the slot of its state_id (node.md,
 * NODE_WORK_API_LOOKUP done, and the replay): it ends, then the answer of its operation for the
 * state_id of that slot, or 404 for 2^64 - 1; with replay 1 a state that needs the replay keeps the
 * entry waiting (API_STREAM_REPLAY, the slot at API_REPLAY_SLOT of its cursor). With
 * API_STREAM_GONE it ends. rbx the node, rbp the store, r14 the scratch, r15 the actions. r12 the
 * entry, r13 the route, S7 the flags, S8 the view, S9 the connection, S10 the operation. Locals: L
 * the scratch's size, L+16 the ids, L+24 statuses, L+32 validator (64), L+96 epoch, slot, index and
 * present, L+128 the slot, L+136 replay, then the status.
 */
LOCAL_FUNCTION lantern_node_api_rerun
    ENTER 144
    mov     %rdi, %r12
    mov     %rsi, (L + 128)(%rsp)
    mov     %rdx, (L + 136)(%rsp)
    mov     NodeApi_connection(%r12), %rax
    mov     %rax, S9(%rsp)
    mov     NodeApi_flags(%r12), %rax
    mov     %rax, S7(%rsp)
    mov     NodeApi_op(%r12), %rcx
    mov     %rcx, S10(%rsp)
    test    $API_STREAM_GONE, %eax
    jz      1f
    mov     %r12, %rdi
    call    lantern_node_api_end                    # API_STREAM_GONE: the entry ends, its ids with it
    jmp     99f
1:  mov     NodeApi_data(%r12), %rcx        # its ids, statuses and validator_id go to the answer
    mov     %rcx, (L + 16)(%rsp)
    mov     (NodeApi_cursor + 32)(%r12), %rcx
    mov     %rcx, (L + 24)(%rsp)
    lea     (L + 32)(%rsp), %rdi
    lea     (NodeApi_cursor + 40)(%r12), %rsi
    mov     $64, %edx
    call    lantern_copy
    lea     (L + 96)(%rsp), %rdi
    lea     (NodeApi_cursor + 104)(%r12), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     (%r14), %rax                    # the ApiView, then an ApiRoute, at the end of scratch
    mov     %rax, L(%rsp)
    sub     $(ApiView__size + API_ROUTE_FIXED), %rax
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, S8(%rsp)
    mov     %rax, %rdi
    call    lantern_node_api_view
    mov     S8(%rsp), %r13
    add     $ApiView__size, %r13
    mov     %r13, %rdi
    mov     $API_ROUTE_FIXED, %esi
    call    lantern_zero
    movq    $API_ROUTE_FIXED, (%r13)
    mov     S10(%rsp), %rax
    mov     %rax, ApiRoute_op(%r13)
    mov     $API_TYPE_JSON, %eax
    testq   $API_STREAM_SSZ, S7(%rsp)
    jz      2f
    mov     $API_TYPE_SSZ, %eax
2:  mov     %rax, ApiRoute_response(%r13)
    mov     (L + 24)(%rsp), %rax
    mov     %rax, ApiRoute_statuses(%r13)
    lea     ApiRoute_validator(%r13), %rdi
    lea     (L + 32)(%rsp), %rsi
    mov     $64, %edx
    call    lantern_copy
    mov     (L + 96)(%rsp), %rax
    mov     %rax, ApiRoute_epoch(%r13)
    mov     (L + 104)(%rsp), %rax
    mov     %rax, ApiRoute_slot(%r13)
    mov     (L + 112)(%rsp), %rax
    mov     %rax, ApiRoute_index(%r13)
    mov     (L + 120)(%rsp), %rax
    mov     %rax, ApiRoute_present(%r13)
    movq    $API_ID_SLOT, ApiRoute_id_kind(%r13)
    mov     (L + 128)(%rsp), %rax
    mov     %rax, ApiRoute_id_slot(%r13)
    mov     $404, %edx
    cmp     $-1, %rax
    je      70f
    mov     S8(%rsp), %rsi
    mov     (L + 136)(%rsp), %rax
    mov     %rax, ApiView_look_replay(%rsi)
    mov     %r13, %rdi
    call    lantern_node_api_state
    mov     %rax, %rdx
    cmp     $1, %rax
    jne     70f
    orq     $API_STREAM_REPLAY, NodeApi_flags(%r12) # the replay: the entry waits
    mov     (L + 128)(%rsp), %rax
    mov     %rax, (NodeApi_cursor + API_REPLAY_SLOT)(%r12)
    jmp     90f
70: cmpq    $API_OP_GET_ATTESTER_DUTIES, S10(%rsp)  # getAttesterDuties with no state: 400
    jne     707f
    mov     $400, %eax
    cmp     $404, %rdx
    cmove   %rax, %rdx
707: mov    %rdx, (L + 136)(%rsp)
    mov     S7(%rsp), %rax
    and     $~API_STREAM_OWN, %rax          # the entry ends; it owns no bytes
    mov     %rax, NodeApi_flags(%r12)
    mov     %r12, %rdi
    call    lantern_node_api_end
    mov     (L + 136)(%rsp), %rdx
    test    %rdx, %rdx
    jnz     80f
    mov     S8(%rsp), %rax                  # the ids go to the answer
    mov     (L + 16)(%rsp), %rcx
    mov     %rcx, ApiView_look_data(%rax)
    movq    $0, (L + 16)(%rsp)
    mov     S9(%rsp), %rdi
    mov     %r13, %rsi
    mov     S7(%rsp), %rdx
    and     $(API_STREAM_CLOSE | API_STREAM_HTTP10), %edx
    mov     S8(%rsp), %rcx
    call    lantern_node_api_state_answer
    mov     %rax, %rdx
    test    %rax, %rax
    jz      90f
80: mov     (L + 16)(%rsp), %rsi            # ids no answer took: they go
    test    %rsi, %rsi
    jz      82f
    mov     %rdx, (L + 24)(%rsp)
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
    mov     (L + 24)(%rsp), %rdx
82: mov     S9(%rsp), %rdi                  # an error: with close, or keep-alive for HTTP/1.0
    xor     %esi, %esi
    mov     $API_BODY_ERROR, %ecx
    mov     S7(%rsp), %r8
    and     $API_R_CLOSE, %r8d
    jnz     81f
    testq   $API_STREAM_HTTP10, S7(%rsp)
    jz      81f
    mov     $API_R_KEEP, %r8d
81: call    lantern_node_api_send
90: mov     L(%rsp), %rax
    mov     %rax, (%r14)
99: LEAVE 144
END_FUNCTION lantern_node_api_rerun

/*
 * (data rdi, slot rsi): the copy of the replay in flight crosses the fork boundaries to the slot
 * rsi, then a NODE_WORK_REPLAY of it with the block's bytes rdi (node.md, the replay). S7 the data,
 * S8 the slot.
 */
LOCAL_FUNCTION lantern_node_replay_block
    ENTER 0
    mov     %rdi, S7(%rsp)
    mov     %rsi, S8(%rsp)
    mov     Node_replay_copy(%rbx), %rdi
    mov     Node_anchor_state_id(%rbx), %rsi
    mov     Node_replay_copy_slot(%rbx), %rdx
    mov     S8(%rsp), %rcx
    call    lantern_node_cross
    mov     %rax, Node_replay_copy(%rbx)
    mov     S8(%rsp), %rcx
    mov     %rcx, Node_replay_copy_slot(%rbx)
    mov     $NODE_WORK_REPLAY, %edi
    mov     %rax, %rsi
    xor     %edx, %edx
    mov     S7(%rsp), %rcx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    lantern_node_work
    LEAVE 0
END_FUNCTION lantern_node_replay_block

/*
 * The replay in flight queues its next blocks (node.md, the replay): at most NODE_REPLAY_CHUNK, the
 * first always and the others while the actions have room for 1024 bytes more; the Db's blocks
 * below db_next_slot, then the NodeBlock path from replay_root, a list at the end of scratch. Once
 * it is queued whole, replay_state takes the copy and the entries that wait run again; a block it
 * cannot find ends it, and they run again with no replay. r12 the next slot, r13 the blocks queued,
 * S7 a block's data, then the path's count, S8 the path list, S9 an entry, S10 the entries left.
 * Locals: L the scratch's size, L+16 replay.
 */
LOCAL_FUNCTION lantern_node_replay_due
    ENTER 32
    cmpq    $0, Node_replay_copy(%rbx)
    je      99f
    mov     Node_replay_next(%rbx), %r12
    xor     %r13d, %r13d
    mov     (%r14), %rax
    mov     %rax, L(%rsp)
    mov     Node_replay_loading(%rbx), %rax # a load out: later; a failed one: no replay
    test    %rax, %rax
    jz      1f
    cmp     $2, %rax
    jne     99f
    movq    $0, Node_replay_loading(%rbx)
    jmp     60f
1:  cmp     Node_replay_slot(%rbx), %r12
    ja      50f
    testq   $NODE_FLAG_DB, Node_flags(%rbx) # the Db's blocks, below db_next_slot
    jz      10f
    cmp     Node_db_next_slot(%rbx), %r12
    jae     10f
    mov     %r12, %rdi
    call    lantern_node_db_block
    test    %rax, %rax
    jz      3f
    mov     %rax, S7(%rsp)
    cmp     $NODE_REPLAY_CHUNK, %r13
    jae     40f
    test    %r13, %r13
    jz      2f
    mov     $1024, %edi
    call    lantern_node_room
    test    %rax, %rax
    jz      40f
2:  mov     S7(%rsp), %rdi
    mov     %r12, %rsi
    call    lantern_node_replay_block
    inc     %r13
3:  inc     %r12
    jmp     1b
10: lea     Node_replay_root(%rbx), %rdi    # the NodeBlock path from the replay's block, down to the next slot
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      60f
    mov     (%r14), %rax
    mov     (Node_blocks + 8)(%rbx), %rcx
    shl     $3, %rcx
    sub     %rcx, %rax
    jb      40f
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, S8(%rsp)
    movq    $0, S7(%rsp)
11: cmp     %r12, NodeBlock_slot(%rdx)
    jb      14f
    cmpq    $0, NodeBlock_data_id(%rdx)     # a block of the path with no bytes: none
    je      60f
    mov     S7(%rsp), %rcx
    cmp     (Node_blocks + 8)(%rbx), %rcx
    jae     60f
    mov     S8(%rsp), %rax
    mov     %rdx, (%rax,%rcx,8)
    incq    S7(%rsp)
    lea     NodeBlock_parent_root(%rdx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    jne     11b
14: cmpq    $0, S7(%rsp)                    # from the lowest
    je      15f
    cmp     $NODE_REPLAY_CHUNK, %r13
    jae     40f
    test    %r13, %r13
    jz      16f
    mov     $1024, %edi
    call    lantern_node_room
    test    %rax, %rax
    jz      40f
16: decq    S7(%rsp)
    mov     S7(%rsp), %rcx
    mov     S8(%rsp), %rax
    mov     (%rax,%rcx,8), %rax
    mov     NodeBlock_data_id(%rax), %rdi
    mov     NodeBlock_slot(%rax), %rsi
    lea     1(%rsi), %r12
    call    lantern_node_replay_block
    inc     %r13
    jmp     14b
15: mov     Node_replay_slot(%rbx), %r12    # the path's last: the replay's block
    inc     %r12
50: mov     Node_replay_copy(%rbx), %rax    # queued whole: its state
    mov     %rax, Node_replay_state(%rbx)
    movq    $0, Node_replay_copy(%rbx)
    mov     %r12, Node_replay_next(%rbx)
    movq    $1, (L + 16)(%rsp)
    jmp     70f
40: mov     %r12, Node_replay_next(%rbx)    # the rest in a later step
    jmp     90f
60: mov     $NODE_ACT_STATE_FREE, %edi      # a block it cannot find: no replay
    mov     Node_replay_copy(%rbx), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
    movq    $0, Node_replay_copy(%rbx)
    lea     Node_replay_root(%rbx), %rdi
    mov     $32, %esi
    call    lantern_zero
    movq    $0, (L + 16)(%rsp)
70: mov     L(%rsp), %rax                   # the entries that wait run again
    mov     %rax, (%r14)
    PART    %rax, %rcx, %rbx, Node_api
    mov     %rax, S9(%rsp)
    mov     %rcx, S10(%rsp)
71: cmpq    $0, S10(%rsp)
    je      99f
    mov     S9(%rsp), %rdi
    cmpq    $0, NodeApi_connection(%rdi)
    je      72f
    mov     NodeApi_flags(%rdi), %rax
    test    $API_STREAM_REPLAY, %eax
    jz      72f
    and     $~API_STREAM_REPLAY, %rax
    mov     %rax, NodeApi_flags(%rdi)
    mov     (NodeApi_cursor + API_REPLAY_SLOT)(%rdi), %rsi
    mov     (L + 16)(%rsp), %rdx
    call    lantern_node_api_rerun
72: addq    $NodeApi__mem, S9(%rsp)
    decq    S10(%rsp)
    jmp     71b
90: mov     L(%rsp), %rax
    mov     %rax, (%r14)
99: LEAVE 32
END_FUNCTION lantern_node_replay_due

/*
 * (node rdi, work rsi, state_a rdx, scratch rcx, event r8) -> rax: a NODE_WORK_API_LOOKUP of
 * lantern_node_run (node.md): at NodeEvent_index of the event, the slot whose state on the chain of
 * state_a has the root of the NodeApi entry at the work's arg, or 2^64 - 1. rbx the node, r12 the
 * state, r13 the event, r14 the root, r15 the slot, S7 the lowest slot.
 */
LOCAL_FUNCTION lantern_node_api_lookup_run
    ENTER 0
    mov     %rdi, %rbx
    mov     %rdx, %r12
    mov     %r8, %r13
    movq    $-1, NodeEvent_index(%r13)
    test    %r12, %r12
    jz      98f
    mov     NodeAction_arg(%rsi), %rax
    PART    %rdi, %rdx, %rbx, Node_api
    cmp     %rdx, %rax
    jae     90f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %rdi
    testq   $API_STREAM_LOOKUP, NodeApi_flags(%rdi)
    jz      90f
    lea     NodeApi_cursor(%rdi), %r14
    mov     %rcx, S8(%rsp)
    mov     NODE_STATE_SLOT(%r12), %rdi     # the state's own root
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     %r12, %rdi
    mov     (Node_config + CONFIG_STATE_CACHE)(%rbx), %rsi
    mov     S8(%rsp), %rdx
    lea     NodeEvent_root(%r13), %rcx
    FORK_CALL state_root
    test    %rax, %rax
    jnz     97f
    mov     NODE_STATE_SLOT(%r12), %r15
    lea     NodeEvent_root(%r13), %rax
    NE32    %rax, %r14, 1f
    jmp     80f
1:  mov     %r15, %rax                      # then its state_roots, from the slot below it down
    sub     $SLOTS_PER_HISTORICAL_ROOT, %rax
    jae     2f
    xor     %eax, %eax
2:  mov     %rax, S7(%rsp)
3:  cmp     S7(%rsp), %r15
    jbe     90f
    dec     %r15
    mov     %r15, %rax
    and     $(SLOTS_PER_HISTORICAL_ROOT - 1), %eax
    shl     $5, %rax
    lea     NODE_STATE_STATE_ROOTS(%r12,%rax), %rax
    NE32    %rax, %r14, 3b
80: mov     %r15, NodeEvent_index(%r13)
90: xor     %eax, %eax
    LEAVE 0
97: cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      96f
    movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%r13)   # a state lantern_state_root does not take
    jmp     90f
96: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
98: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 0
END_FUNCTION lantern_node_api_lookup_run

/* ---------------------------------------------------------------- Streams (node.md, NodeApi) */

/* rax = the free NodeApi entries of the node rbx: the capacity past the count, and the free ones below it. Uses rcx, rdx, rsi, r10. */
LOCAL_FUNCTION lantern_node_api_free
    UNWIND_END_PROLOGUE
    PART    %rsi, %r10, %rbx, Node_api
    mov     Node_pool(%rbx), %rax
    sub     Node_api(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    sub     %r10, %rax
1:  test    %r10, %r10
    jz      9f
    cmpq    $0, NodeApi_connection(%rsi)
    jne     2f
    inc     %rax
2:  add     $NodeApi__mem, %rsi
    dec     %r10
    jmp     1b
9:  ret
END_FUNCTION lantern_node_api_free

/* rax = the index of the NodeApi entry of the connection rdi, or 2^64 - 1; rdx = the entry. Uses rcx, r10. */
LOCAL_FUNCTION lantern_node_api_find
    UNWIND_END_PROLOGUE
    PART    %rdx, %r10, %rbx, Node_api
    xor     %eax, %eax
    test    %rdi, %rdi
    jz      3f
1:  cmp     %r10, %rax
    jae     3f
    cmp     %rdi, NodeApi_connection(%rdx)
    je      4f
    add     $NodeApi__mem, %rdx
    inc     %rax
    jmp     1b
3:  mov     $-1, %rax
4:  ret
END_FUNCTION lantern_node_api_find

/*
 * (connection rdi, route rsi, flags rdx, view rcx) -> rax: produceBlockV3 (node.md, Block
 * production): a NodeApi entry in NODE_PRODUCE_STATE that owns the state of the view, a copy at
 * the slot, with the request in its cursor, and a PRODUCE_CHECK work of it; 0 once it started,
 * else the status of the error to answer. r12 the entry, r13 its index; S7 the route, S8 the view,
 * S9 the connection, S10 the flags.
 */
LOCAL_FUNCTION lantern_node_api_produce
    ENTER 0
    mov     %rdi, S9(%rsp)
    mov     %rsi, S7(%rsp)
    mov     %rcx, S8(%rsp)
    cmpq    $API_TYPE_SSZ, ApiRoute_response(%rsi)  # SSZ, else JSON
    jne     1f
    or      $API_STREAM_SSZ, %rdx
1:  mov     %rdx, S10(%rsp)
    cmpq    $0, ApiView_look_copy(%rcx)     # the state: a copy at the slot; busy with its check
    je      8f
    orq     $(API_STREAM_OWN_STATE | API_STREAM_BUSY), S10(%rsp)
    call    lantern_node_api_new
    mov     %rax, %r13
    mov     %rdx, %r12
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     S9(%rsp), %rax
    mov     %rax, NodeApi_connection(%r12)
    movq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%r12)
    mov     S10(%rsp), %rax
    mov     %rax, NodeApi_flags(%r12)
    mov     S8(%rsp), %rax
    mov     ApiView_look_state(%rax), %rax
    mov     %rax, NodeApi_state(%r12)
    mov     S7(%rsp), %rax
    mov     ApiRoute_slot(%rax), %rdi
    mov     %rdi, NodeApi_slot(%r12)
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, NodeApi_fork(%r12)
    movq    $NODE_PRODUCE_STATE, NodeApi_member(%r12)
    lea     NodeApi_cursor(%r12), %rdi      # the request: randao_reveal, graffiti, the skip flag
    mov     S7(%rsp), %rsi
    add     $ApiRoute_randao_reveal, %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     S7(%rsp), %rsi
    testq   $(1 << API_PARAM_GRAFFITI), ApiRoute_present(%rsi)
    jz      2f
    add     $ApiRoute_graffiti, %rsi
    lea     (NodeApi_cursor + 96)(%r12), %rdi
    COPY32  %rdi, %rsi
2:  mov     S7(%rsp), %rsi
    mov     ApiRoute_present(%rsi), %rax
    shr     $API_PARAM_SKIP_RANDAO_VERIFICATION, %rax
    and     $1, %eax
    mov     %rax, (NodeApi_cursor + 128)(%r12)
    mov     $100, %eax                      # builder_boost_factor: 100 without it
    testq   $(1 << API_PARAM_BUILDER_BOOST_FACTOR), ApiRoute_present(%rsi)
    jz      3f
    mov     ApiRoute_builder_boost_factor(%rsi), %rax
3:  mov     %rax, (NodeApi_cursor + PRODUCE_BOOST)(%r12)
    mov     $NODE_WORK_PRODUCE_CHECK, %edi
    mov     NodeApi_state(%r12), %rsi
    xor     %edx, %edx
    xor     %ecx, %ecx
    mov     %r13, %r8
    xor     %r9d, %r9d
    call    lantern_node_work
    xor     %eax, %eax
    LEAVE 0
8:  mov     $500, %eax
    LEAVE 0
END_FUNCTION lantern_node_api_produce

/*
 * The NODE_EV_WORK_DONE rdi of a work of block production (node.md, Block production): the
 * produceBlockV3 entry at its target goes on, or answers its error. r12 the event, r13 the entry;
 * S7 the result.
 */
LOCAL_FUNCTION lantern_node_produce_done
    ENTER 0
    mov     %rdi, %r12
    mov     NodeAction_target(%r12), %rax
    PART    %r13, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     9f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %r13
    cmpq    $0, NodeApi_connection(%r13)    # an entry still there
    je      9f
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%r13)
    jne     9f
    mov     NodeEvent_result(%r12), %rax
    mov     %rax, S7(%rsp)
    andq    $~API_STREAM_BUSY, NodeApi_flags(%r13)  # its work is done
    cmpq    $NODE_WORK_PRODUCE_FOLD, NodeAction_work_kind(%r12)  # a fold: the pool entry's bytes, when they left the pool meanwhile
    jne     2f
    testq   $API_STREAM_PRODUCE_OWN, NodeApi_flags(%r13)
    jz      1f
    andq    $~API_STREAM_PRODUCE_OWN, NodeApi_flags(%r13)
    mov     NodeApi_root(%r13), %rsi
    movq    $0, NodeApi_root(%r13)
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
1:  movq    $0, NodeApi_root(%r13)
2:  testq   $API_STREAM_GONE, NodeApi_flags(%r13)  # the connection closed meanwhile: the entry ends
    jz      3f
    mov     %r13, %rdi
    call    lantern_node_produce_release
    mov     %r13, %rdi
    call    lantern_node_api_end
    LEAVE 0
3:  mov     S7(%rsp), %rax
    mov     NodeAction_work_kind(%r12), %rcx
    cmp     $NODE_WORK_PRODUCE_CHECK, %rcx
    jne     20f
    mov     $400, %esi                      # the check: 400 for the reveal, 500 for another
    cmp     $LANTERN_INVALID_RANDAO_REVEAL, %rax
    je      8f
    mov     $500, %esi
    test    %rax, %rax
    jnz     8f
    mov     NodeApi_slot(%r13), %rdi        # from bellatrix with a head of a payload: the engine's payload first
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    cmp     $FORK_BELLATRIX, %rax
    jb      10f
    lea     Node_head_root(%rbx), %rdi
    call    lantern_node_store_find
    cmp     $-1, %rax
    je      10f
    mov     BlockNode_block_hash(%rdx), %rax
    or      (BlockNode_block_hash + 8)(%rdx), %rax
    or      (BlockNode_block_hash + 16)(%rdx), %rax
    or      (BlockNode_block_hash + 24)(%rdx), %rax
    jz      10f
    movq    $NODE_PRODUCE_PAYLOAD, NodeApi_member(%r13)
    mov     %r13, %rdi                      # with a builder: its getHeader
    mov     %r12, %rsi
    lea     BlockNode_block_hash(%rdx), %rdx
    call    lantern_node_produce_header
    LEAVE 0
10: movq    $NODE_PRODUCE_FOLD, NodeApi_member(%r13)
    movq    $0, NodeApi_filter_slot(%r13)
    mov     %r13, %rdi
    call    lantern_node_produce_next
    LEAVE 0
20: cmp     $NODE_WORK_PRODUCE_FOLD, %rcx   # the draft holds the entry, or the rules left it out: the next
    jne     25f
    mov     %r13, %rdi
    call    lantern_node_produce_next
    LEAVE 0
25: cmp     $NODE_WORK_PRODUCE_ETH1, %rcx   # PRODUCE_ETH1: the snapshot goes; then the header call's wait, at the quiet point
    jne     30f
    mov     (NodeApi_cursor + PRODUCE_ETH1_SNAP)(%r13), %rsi
    movq    $0, (NodeApi_cursor + PRODUCE_ETH1_SNAP)(%r13)
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
    mov     $500, %esi
    cmpq    $0, S7(%rsp)
    jne     8f
    movq    $NODE_PRODUCE_BID, NodeApi_member(%r13)
    LEAVE 0
30: cmp     $NODE_WORK_PRODUCE_BID, %rcx    # PRODUCE_BID: the answer goes, a valid bid stays; then the build
    jne     31f
    mov     (NodeApi_cursor + PRODUCE_BID)(%r13), %rsi
    movq    $0, (NodeApi_cursor + PRODUCE_BID)(%r13)
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
    cmpq    $0, S7(%rsp)
    jne     32f
    lea     NodeEvent_chunk(%r12), %rdi
    call    lantern_node_put
    mov     %rax, (NodeApi_cursor + PRODUCE_BID)(%r13)
32: mov     %r13, %rdi
    call    lantern_node_produce_build
    LEAVE 0
31: mov     $500, %esi                      # PRODUCE_BLOCK: the block's bytes, answered as a block's
    cmpq    $0, S7(%rsp)
    jne     8f
    mov     %r13, %rdi
    call    lantern_node_produce_release
    lea     NodeEvent_chunk(%r12), %rdi
    call    lantern_node_put
    mov     %rax, NodeApi_data(%r13)
    orq     $API_STREAM_OWN, NodeApi_flags(%r13)
    cmpq    $0, NodeEvent_checkpoint(%r12)  # a blinded block
    je      33f
    orq     $API_STREAM_PRODUCE_BLINDED, NodeApi_flags(%r13)
33: lea     NodeApi_root(%r13), %rdi        # the values: execution_payload_value at root, consensus_block_value at filter_slot
    lea     NodeEvent_root(%r12), %rsi
    COPY32  %rdi, %rsi
    mov     NodeEvent_index(%r12), %rax
    mov     %rax, NodeApi_filter_slot(%r13)
    lea     NodeApi_cursor(%r13), %rdi      # the request goes: the cursor is the answer's JsonCursor
    mov     $(NodeApi_slot - NodeApi_cursor), %esi
    call    lantern_zero
    mov     %r13, %rdi
    call    lantern_node_produce_answer
    LEAVE 0
8:  mov     %r13, %rdi
    call    lantern_node_produce_fail
9:  LEAVE 0
END_FUNCTION lantern_node_produce_done

/* The answer of the produceBlockV3 entry rdi, whose block's bytes are its data: its first chunk. Uses rax, rcx, rdx, r10. */
LOCAL_FUNCTION lantern_node_produce_answer
    FRAME 0
    PART    %rcx, %r10, %rbx, Node_api
    mov     %rdi, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    mov     %rdi, %rdx
    call    lantern_node_api_chunk_work
    UNFRAME 0
END_FUNCTION lantern_node_produce_answer

/*
 * (connection rdi, route rsi, flags rdx, request rcx) -> rax: publishBlockV2 (node.md, Block
 * publishing): a NodeApi entry in NODE_PUBLISH_DECODE, the body's bytes as its data, and a
 * PUBLISH_DECODE work of them; 0 once it started, else the status of the error to answer. r12 the
 * entry, r13 its index; S7 the route, S8 the request, S9 the connection, S10 the flags. Locals: L a
 * ByteList view of the body.
 */
LOCAL_FUNCTION lantern_node_api_publish
    ENTER 32
    mov     %rdi, S9(%rsp)
    mov     %rsi, S7(%rsp)
    mov     %rdx, S10(%rsp)
    mov     %rcx, S8(%rsp)
    mov     HttpRequest_body(%rcx), %rax    # a body of no bytes: 400
    mov     (HttpRequest_body + 8)(%rcx), %rdx
    test    %rdx, %rdx
    jz      8f
    add     %rcx, %rax
    lea     L(%rsp), %rsi
    sub     %rsi, %rax
    mov     %rdx, L(%rsp)
    mov     %rax, (L + 8)(%rsp)
    mov     %rdx, (L + 16)(%rsp)
    call    lantern_node_api_new
    mov     %rax, %r13
    mov     %rdx, %r12
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     S9(%rsp), %rax
    mov     %rax, NodeApi_connection(%r12)
    movq    $API_OP_PUBLISH_BLOCK_V2, NodeApi_op(%r12)
    mov     S10(%rsp), %rax
    or      $API_STREAM_BUSY, %rax          # busy with its decode
    mov     %rax, NodeApi_flags(%r12)
    mov     S7(%rsp), %rsi
    mov     ApiRoute_consensus_version(%rsi), %rax
    mov     %rax, NodeApi_fork(%r12)
    movq    $NODE_PUBLISH_DECODE, NodeApi_member(%r12)
    mov     ApiRoute_broadcast_validation(%rsi), %rax   # the level, and 1 for a JSON body
    mov     %rax, NodeApi_cursor(%r12)
    xor     %eax, %eax
    cmpq    $API_TYPE_SSZ, ApiRoute_body(%rsi)
    setne   %al
    mov     %rax, (NodeApi_cursor + 24)(%r12)
    xor     %eax, %eax                      # publishBlindedBlockV2 from bellatrix: a blinded block
    cmpq    $API_OP_PUBLISH_BLINDED_BLOCK_V2, ApiRoute_op(%rsi)
    jne     1f
    cmpq    $FORK_BELLATRIX, ApiRoute_consensus_version(%rsi)
    setae   %al
1:  mov     %rax, (NodeApi_cursor + PUBLISH_BLINDED)(%r12)
    lea     L(%rsp), %rdi
    call    lantern_node_put
    mov     %rax, NodeApi_data(%r12)
    mov     $NODE_WORK_PUBLISH_DECODE, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     %rax, %rcx
    mov     %r13, %r8
    mov     (NodeApi_cursor + 24)(%r12), %r9
    xor     $1, %r9
    shl     $8, %r9
    or      NodeApi_fork(%r12), %r9
    mov     (NodeApi_cursor + PUBLISH_BLINDED)(%r12), %rax
    shl     $9, %rax
    or      %rax, %r9
    call    lantern_node_work
    xor     %eax, %eax
    LEAVE 32
8:  mov     $400, %eax
    LEAVE 32
END_FUNCTION lantern_node_api_publish

/*
 * The NODE_EV_WORK_DONE rdi of a work of block publishing (node.md, Block publishing): the
 * publishBlockV2 entry at its target goes on, or answers. r12 the event, r13 the entry; S7 the
 * block's index.
 */
LOCAL_FUNCTION lantern_node_publish_done
    ENTER 0
    mov     %rdi, %r12
    mov     NodeAction_target(%r12), %rax
    cmp     $-1, %rax                       # a sidecar of the reconstruction
    jne     100f
    call    lantern_node_recon_sidecar_done
    LEAVE 0
100: PART   %r13, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     99f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %r13
    cmpq    $0, NodeApi_connection(%r13)    # an entry still there
    je      99f
    cmpq    $API_OP_PUBLISH_BLOCK_V2, NodeApi_op(%r13)
    jne     99f
    andq    $~API_STREAM_BUSY, NodeApi_flags(%r13)  # its work is done; the connection closed meanwhile: the entry ends,
    testq   $API_STREAM_GONE, NodeApi_flags(%r13)   # but after a check that passed, or a sidecar, the publish goes on unanswered
    jz      1f
    mov     NodeAction_work_kind(%r12), %rax
    cmp     $NODE_WORK_PUBLISH_CHECK, %rax
    jb      2f
    ja      1f
    cmpq    $0, NodeEvent_result(%r12)
    je      1f
2:  mov     %r13, %rdi
    call    lantern_node_publish_end
    LEAVE 0
1:  cmpq    $NODE_WORK_PUBLISH_SIDECAR, NodeAction_work_kind(%r12)  # a sidecar past the last: the sidecars end
    jne     12f
    cmpq    $0, NodeEvent_result(%r12)
    je      12f
    movq    $0, (NodeApi_cursor + 40)(%r13)
    mov     %r13, %rdi
    call    lantern_node_publish_drop
    LEAVE 0
12: mov     $400, %esi                      # a check that fails: 400
    cmpq    $0, NodeEvent_result(%r12)
    jne     90f
    mov     NodeAction_work_kind(%r12), %rax
    cmp     $NODE_WORK_PUBLISH_DECODE, %rax
    jne     20f
    lea     NodeEvent_chunk(%r12), %rdi     # DECODE: the block's bytes, root, slot, blob count, parent
    call    lantern_node_put
    mov     %rax, NodeApi_filter_slot(%r13)
    lea     NodeApi_root(%r13), %rdi
    lea     NodeEvent_root(%r12), %rsi
    COPY32  %rdi, %rsi
    mov     NodeEvent_index(%r12), %rax
    mov     %rax, NodeApi_slot(%r13)
    mov     NodeEvent_checkpoint(%r12), %rax
    mov     %rax, (NodeApi_cursor + 16)(%r13)
    mov     (NodeEvent_chunk + 8)(%r12), %rsi
    lea     (NodeEvent_chunk + 116)(%r12,%rsi), %rsi
    lea     (NodeApi_cursor + 32)(%r13), %rdi
    COPY32  %rdi, %rsi
    mov     NodeApi_slot(%r13), %rdi        # a slot of another fork than consensus_version's: 400
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     $400, %esi
    cmp     NodeApi_fork(%r13), %rax
    jne     90f
    lea     NodeApi_root(%r13), %rdi        # a block the node holds: 200
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      11f
    mov     $200, %esi
    cmpq    $NODE_BLOCK_INVALID, NodeBlock_status(%rdx)
    jne     90f
11: cmpq    $0, (NodeApi_cursor + PUBLISH_BLINDED)(%r13)    # a blinded block: no sidecars
    jne     30f
    cmpq    $0, (NodeApi_cursor + 16)(%r13)    # with blobs: the sidecars, else the check
    je      30f
    mov     %r13, %rdi
    call    lantern_node_publish_sidecars_work
    LEAVE 0
20: cmp     $NODE_WORK_PUBLISH_SIDECARS, %rax  # SIDECARS: the check
    je      30f
    cmp     $NODE_WORK_PUBLISH_SIDECAR, %rax
    jne     22f
    mov     %r13, %rdi                      # SIDECAR: it goes out and stays, then the next
    mov     %r12, %rsi
    call    lantern_node_publish_sidecar_done
    LEAVE 0
22: cmp     $NODE_WORK_PUBLISH_CHECK, %rax
    jne     99f
    cmpq    $0, (NodeApi_cursor + PUBLISH_BLINDED)(%r13)    # a blinded block: to the builder
    je      25f
    mov     %r13, %rdi
    lea     NodeEvent_chunk(%r12), %rsi
    call    lantern_node_publish_submit
    test    %rax, %rax
    jz      99f
    mov     %rax, %rsi
    jmp     90f
25: call    lantern_node_new_block                  # CHECK: the block's NodeBlock, before the publish
    mov     %rax, S7(%rsp)
    mov     %rdi, %rdx
    lea     NodeBlock_root(%rdx), %rdi
    lea     NodeApi_root(%r13), %rsi
    COPY32  %rdi, %rsi
    lea     NodeBlock_parent_root(%rdx), %rdi
    lea     (NodeApi_cursor + 32)(%r13), %rsi
    COPY32  %rdi, %rsi
    mov     NodeApi_slot(%r13), %rax
    mov     %rax, NodeBlock_slot(%rdx)
    mov     NodeApi_filter_slot(%r13), %rax
    mov     %rax, NodeBlock_data_id(%rdx)
    movq    $0, NodeApi_filter_slot(%r13)
    movq    $NODE_BLOCK_WAITING, NodeBlock_status(%rdx)
    movq    $1, NodeBlock_data_available(%rdx)
    mov     (NodeApi_cursor + 16)(%r13), %rax
    mov     %rax, NodeBlock_blobs(%rdx)
    mov     (NodeEvent_chunk + 16)(%r12), %rax
    mov     %rax, NodeBlock_length(%rdx)
    mov     $API_TOPIC_BLOCK_GOSSIP, %edi   # its block_gossip event: its checks passed
    lea     NodeApi_root(%r13), %rsi
    mov     NodeApi_slot(%r13), %rdx
    xor     %ecx, %ecx
    call    lantern_node_api_root_event
    testq   $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx)  # subscribed: the block out on beacon_block
    jz      21f
    mov     $GOSSIP_BEACON_BLOCK, %edi
    lea     NodeEvent_chunk(%r12), %rsi
    xor     %edx, %edx
    call    lantern_node_publish
21: movq    $NODE_PUBLISH_IMPORT, NodeApi_member(%r13)  # the import, the sidecars one at a time, then the answer
    cmpq    $0, NodeApi_filter_index(%r13)
    je      23f
    movq    $0, (NodeApi_cursor + 40)(%r13)
    mov     %r13, %rdi
    call    lantern_node_publish_sidecar_work
    jmp     24f
23: mov     %r13, %rdi
    call    lantern_node_publish_drop
24: mov     S7(%rsp), %rdi
    call    lantern_node_try_import
    LEAVE 0
30: mov     %r13, %rdi                      # the check
    call    lantern_node_publish_check_work
    test    %rax, %rax
    jz      99f
    mov     %rax, %rsi
90: mov     %r13, %rdi
    call    lantern_node_publish_answer
99: LEAVE 0
END_FUNCTION lantern_node_publish_done

/*
 * The PUBLISH_SIDECARS of the publishBlockV2 entry rdi (node.md, NODE_PUBLISH_SIDECARS): a
 * BYTES_NEW of the sidecars' room, its id the entry's filter_index, then the work. Locals: the
 * entry, the room, the action.
 */
LOCAL_FUNCTION lantern_node_publish_sidecars_work
    FRAME 32
    mov     %rdi, (%rsp)
    mov     (NodeApi_cursor + 16)(%rdi), %rax   # the blob count
    cmpq    $FORK_FULU, NodeApi_fork(%rdi)
    jae     1f
    imul    $(PUB_BLOB_SIDECAR + 24), %rax, %rax    # deneb and electra: a BlobSidecar for each blob
    jmp     2f
1:  imul    $(PUB_CELL_BYTES + 96), %rax, %rax      # fulu: NUMBER_OF_COLUMNS column sidecars of the count
    add     $(PUB_COLUMN_FIXED + 24 + 7), %rax
    and     $-8, %rax
    imul    $NUMBER_OF_COLUMNS, %rax, %rax
2:  add     $24, %rax
    mov     %rax, 8(%rsp)
    mov     $NODE_ACT_BYTES_NEW, %edi
    mov     $NODE_ACT_BYTES_NEW_SIZE, %esi
    call    lantern_node_act
    mov     %rax, 16(%rsp)
    call    lantern_node_new_id
    mov     16(%rsp), %rcx
    mov     %rax, 16(%rcx)
    mov     8(%rsp), %rdx
    mov     %rdx, 24(%rcx)
    mov     (%rsp), %rcx
    mov     %rax, NodeApi_filter_index(%rcx)
    movq    $NODE_PUBLISH_SIDECARS, NodeApi_member(%rcx)
    orq     $API_STREAM_BUSY, NodeApi_flags(%rcx)
    mov     %rax, %rdx                      # the work: the sidecars as state_b, the body as data
    mov     NodeApi_data(%rcx), %rax
    mov     %rax, 24(%rsp)
    PART    %rsi, %rdi, %rbx, Node_api
    mov     %rcx, %rax
    sub     %rsi, %rax
    mov     %rdx, %rsi
    xor     %edx, %edx
    mov     $NodeApi__mem, %edi
    div     %rdi
    mov     %rax, %r8
    mov     (%rsp), %rcx
    mov     (NodeApi_cursor + 24)(%rcx), %r9    # 2^8 for SSZ
    xor     $1, %r9
    shl     $8, %r9
    or      NodeApi_fork(%rcx), %r9
    mov     %rsi, %rdx
    mov     24(%rsp), %rcx
    mov     $NODE_WORK_PUBLISH_SIDECARS, %edi
    xor     %esi, %esi
    call    lantern_node_work
    UNFRAME 32
END_FUNCTION lantern_node_publish_sidecars_work

/* The PUBLISH_SIDECAR of the next sidecar (cursor + 40) of the publishBlockV2 entry rdi in NODE_PUBLISH_IMPORT. */
LOCAL_FUNCTION lantern_node_publish_sidecar_work
    FRAME 0
    orq     $API_STREAM_BUSY, NodeApi_flags(%rdi)
    mov     NodeApi_filter_index(%rdi), %rdx
    mov     (NodeApi_cursor + 40)(%rdi), %r9
    PART    %rsi, %rcx, %rbx, Node_api
    mov     %rdi, %rax
    sub     %rsi, %rax
    mov     %rdx, %rsi
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    mov     %rax, %r8
    mov     %rsi, %rdx
    mov     $NODE_WORK_PUBLISH_SIDECAR, %edi
    xor     %esi, %esi
    xor     %ecx, %ecx
    call    lantern_node_work
    UNFRAME 0
END_FUNCTION lantern_node_publish_sidecar_work

/*
 * The WORK_DONE rdi of a PUBLISH_SIDECAR of the reconstruction (node.md): recon_state 2; a valid
 * one stays as a NodeBlob when the node lacks it, and goes out on its subnet's topic with
 * NODE_FLAG_SUBSCRIBED, a column of columns and recon_slot above F's slot. r13 the event, S7 the
 * sidecar's id.
 */
LOCAL_FUNCTION lantern_node_recon_sidecar_done
    ENTER 0
    mov     %rdi, %r13
    movq    $2, Node_recon_state(%rbx)
    cmpq    $0, NodeEvent_result(%r13)
    jne     9f
    lea     NodeEvent_root(%r13), %rdi
    mov     NodeEvent_index(%r13), %rsi
    call    lantern_node_blob_held
    test    %rax, %rax
    jnz     3f
    lea     NodeEvent_chunk(%r13), %rdi
    call    lantern_node_put
    mov     %rax, S7(%rsp)
    call    lantern_node_new_blob
    mov     %rdi, %rdx
    lea     NodeBlob_block_root(%rdx), %rdi
    lea     NodeEvent_root(%r13), %rsi
    COPY32  %rdi, %rsi
    mov     NodeEvent_index(%r13), %rax
    mov     %rax, NodeBlob_index(%rdx)
    mov     NodeEvent_checkpoint(%r13), %rax
    mov     %rax, NodeBlob_slot(%rdx)
    mov     S7(%rsp), %rax
    mov     %rax, NodeBlob_data_id(%rdx)
    movq    $NODE_BLOB_VALID, NodeBlob_status(%rdx)
    mov     (NodeEvent_chunk + 16)(%r13), %rax
    mov     %rax, NodeBlob_length(%rdx)
    lea     NodeEvent_root(%r13), %rdi
    call    lantern_node_blob_added
3:  testq   $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx)  # subscribed: out on its subnet's topic
    jz      9f
    mov     NodeEvent_index(%r13), %rdi
    call    lantern_node_sampled
    test    %rax, %rax
    jz      9f
    mov     Store_finalized_checkpoint(%rbp), %rax
    imul    $SLOTS_PER_EPOCH, %rax, %rax
    cmp     Node_recon_slot(%rbx), %rax
    jae     9f
    mov     (Node_config + CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT)(%rbx), %rcx
    test    %rcx, %rcx
    jz      9f
    mov     NodeEvent_index(%r13), %rax
    xor     %edx, %edx
    div     %rcx
    mov     $GOSSIP_DATA_COLUMN_SIDECAR, %edi
    lea     NodeEvent_chunk(%r13), %rsi
    call    lantern_node_publish
9:  LEAVE 0
END_FUNCTION lantern_node_recon_sidecar_done

/*
 * The WORK_DONE rsi of a valid PUBLISH_SIDECAR of the publishBlockV2 entry rdi: the sidecar stays
 * as a NodeBlob when the node keeps it (each blob sidecar; the column sidecars it samples), goes
 * out on its subnet's topic with NODE_FLAG_SUBSCRIBED, then the next. r12 the entry, r13 the
 * event; S7 the sidecar's id. Step code keeps r14 and r15.
 */
LOCAL_FUNCTION lantern_node_publish_sidecar_done
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
    movq    $0, S7(%rsp)
    cmpq    $FORK_FULU, NodeApi_fork(%r12)
    jb      1f
    mov     NodeEvent_index(%r13), %rdi     # a column the node samples
    call    lantern_node_sampled
    test    %rax, %rax
    jz      3f
1:  lea     NodeEvent_root(%r13), %rdi      # one the node does not hold yet
    mov     NodeEvent_index(%r13), %rsi
    call    lantern_node_blob_held
    test    %rax, %rax
    jnz     3f
    lea     NodeEvent_chunk(%r13), %rdi
    call    lantern_node_put
    mov     %rax, S7(%rsp)
    call    lantern_node_new_blob
    mov     %rdi, %rdx
    lea     NodeBlob_block_root(%rdx), %rdi
    lea     NodeEvent_root(%r13), %rsi
    COPY32  %rdi, %rsi
    mov     NodeEvent_index(%r13), %rax
    mov     %rax, NodeBlob_index(%rdx)
    mov     NodeEvent_checkpoint(%r13), %rax
    mov     %rax, NodeBlob_slot(%rdx)
    mov     S7(%rsp), %rax
    mov     %rax, NodeBlob_data_id(%rdx)
    movq    $NODE_BLOB_VALID, NodeBlob_status(%rdx)
    mov     (NodeEvent_chunk + 16)(%r13), %rax
    mov     %rax, NodeBlob_length(%rdx)
    lea     NodeEvent_root(%r13), %rdi
    call    lantern_node_blob_added
3:  mov     $API_TOPIC_BLOB_SIDECAR, %eax   # its event: of its NodeBlob's bytes, else of a copy for the work
    mov     $API_TOPIC_DATA_COLUMN_SIDECAR, %ecx
    cmpq    $FORK_FULU, NodeApi_fork(%r12)
    cmovae  %rcx, %rax
    mov     %rax, S8(%rsp)
    mov     %rax, %rdi
    call    lantern_node_api_subscribed
    test    %rax, %rax
    jz      39f
    mov     S7(%rsp), %rax
    mov     %rax, S9(%rsp)
    test    %rax, %rax
    jnz     38f
    lea     NodeEvent_chunk(%r13), %rdi
    call    lantern_node_put
    mov     %rax, S9(%rsp)
38: mov     $NODE_WORK_API_EVENT, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     S9(%rsp), %rcx
    xor     %r8d, %r8d
    mov     NodeApi_fork(%r12), %r9
    shl     $16, %r9
    or      S8(%rsp), %r9
    call    lantern_node_work
    mov     S9(%rsp), %rax
    cmp     S7(%rsp), %rax
    je      39f
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     S9(%rsp), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
39: testq   $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx)  # subscribed: out on its subnet's topic
    jz      4f
    mov     NodeEvent_index(%r13), %rax
    mov     NodeApi_fork(%r12), %rcx
    cmp     $FORK_FULU, %rcx
    jb      31f
    mov     $GOSSIP_DATA_COLUMN_SIDECAR, %edi
    mov     (Node_config + CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT)(%rbx), %rcx
    jmp     33f
31: mov     $GOSSIP_BLOB_SIDECAR, %edi
    cmp     $FORK_ELECTRA, %rcx
    jb      32f
    mov     (Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA)(%rbx), %rcx
    jmp     33f
32: mov     (Node_config + CONFIG_BLOB_SIDECAR_SUBNET_COUNT)(%rbx), %rcx
33: test    %rcx, %rcx
    jz      4f
    xor     %edx, %edx
    div     %rcx
    lea     NodeEvent_chunk(%r13), %rsi
    call    lantern_node_publish
4:  mov     (NodeApi_cursor + 40)(%r12), %rax   # the next sidecar; after the last, the body and the sidecars go
    inc     %rax
    mov     %rax, (NodeApi_cursor + 40)(%r12)
    mov     (NodeApi_cursor + 16)(%r12), %rcx
    mov     $NUMBER_OF_COLUMNS, %edx
    cmpq    $FORK_FULU, NodeApi_fork(%r12)
    cmovae  %rdx, %rcx
    mov     %r12, %rdi
    cmp     %rcx, %rax
    jae     5f
    call    lantern_node_publish_sidecar_work
    LEAVE 0
5:  call    lantern_node_publish_drop
    LEAVE 0
END_FUNCTION lantern_node_publish_sidecar_done

/*
 * The PUBLISH_CHECK of the publishBlockV2 entry rdi (node.md, NODE_PUBLISH_CHECK): rax = 0 once
 * it went, else 400 with no post-state of the parent, or 500 with no head post-state. r12 the
 * entry, r13 the parent's entry; S7 the copy, S8 the head's state id, S9 the parent's fork, S10
 * the copy's slot.
 */
LOCAL_FUNCTION lantern_node_publish_check_work
    ENTER 0
    mov     %rdi, %r12
    lea     Node_head_root(%rbx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      9f
    mov     NodeBlock_state_id(%rdx), %rax
    test    %rax, %rax
    jz      9f
    mov     %rax, S8(%rsp)
    lea     (NodeApi_cursor + 32)(%r12), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      8f
    mov     %rdx, %r13
    cmpq    $0, NodeBlock_state_id(%r13)
    je      8f
    movq    $NODE_PUBLISH_CHECK, NodeApi_member(%r12)
    orq     $API_STREAM_BUSY, NodeApi_flags(%r12)
    call    lantern_node_new_id                     # the copy, across the fork boundaries to the slot
    mov     %rax, S7(%rsp)
    mov     $NODE_ACT_STATE_COPY, %edi
    mov     NodeBlock_state_id(%r13), %rsi
    mov     %rax, %rdx
    call    lantern_node_ids
    mov     S7(%rsp), %rdi
    mov     NodeBlock_state_id(%r13), %rsi
    mov     NodeBlock_slot(%r13), %rdx
    mov     NodeApi_slot(%r12), %rcx
    call    lantern_node_cross
    mov     %rax, S7(%rsp)
    mov     NodeBlock_slot(%r13), %rdi      # the copy's slot: the parent's, or the first of the block's fork after an upgrade
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, S9(%rsp)
    mov     NodeApi_slot(%r12), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     NodeBlock_slot(%r13), %rcx
    mov     %rcx, S10(%rsp)
    cmp     S9(%rsp), %rax
    jbe     1f
    shl     $4, %rax
    mov     Node_config(%rbx,%rax), %rax
    imul    $SLOTS_PER_EPOCH, %rax, %rax
    cmp     S10(%rsp), %rax
    jbe     1f
    mov     %rax, S10(%rsp)
1:  mov     NodeApi_slot(%r12), %r9         # then process_slots to the block's slot, as a lookup's
    cmp     S10(%rsp), %r9
    jbe     2f
    mov     $NODE_WORK_SLOTS, %edi
    mov     S7(%rsp), %rsi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    call    lantern_node_work
2:  PART    %rcx, %rdx, %rbx, Node_api      # the entry's index
    mov     %r12, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    mov     %rax, %r8
    mov     $NODE_WORK_PUBLISH_CHECK, %edi
    mov     S7(%rsp), %rsi
    mov     NodeApi_filter_index(%r12), %rdx
    mov     NodeApi_filter_slot(%r12), %rcx
    mov     NodeApi_cursor(%r12), %r9
    mov     (NodeApi_cursor + PUBLISH_BLINDED)(%r12), %rax  # a blinded block's check
    shl     $8, %rax
    or      %rax, %r9
    call    lantern_node_work
    mov     S8(%rsp), %rcx
    mov     %rcx, NodeAction_state_c(%rax)
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     S7(%rsp), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
    xor     %eax, %eax
    LEAVE 0
8:  mov     $400, %eax
    LEAVE 0
9:  mov     $500, %eax
    LEAVE 0
END_FUNCTION lantern_node_publish_check_work

/* The ids of the publishBlockV2 entry rdi but the block's bytes go: its body and sidecars. Locals: the entry. */
LOCAL_FUNCTION lantern_node_publish_drop
    FRAME 16
    mov     %rdi, (%rsp)
    mov     NodeApi_data(%rdi), %rsi        # each field cleared first: lantern_node_ids leaves an entry's own bytes to it
    movq    $0, NodeApi_data(%rdi)
    test    %rsi, %rsi
    jz      1f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
1:  mov     (%rsp), %rdi
    mov     NodeApi_filter_index(%rdi), %rsi
    movq    $0, NodeApi_filter_index(%rdi)
    test    %rsi, %rsi
    jz      2f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
2:  UNFRAME 16
END_FUNCTION lantern_node_publish_drop

/* The end of the publishBlockV2 entry rdi, its ids with it. Locals: the entry. */
LOCAL_FUNCTION lantern_node_publish_end
    FRAME 16
    mov     %rdi, (%rsp)
    mov     (NodeApi_cursor + PUBLISH_CALL)(%rdi), %rax     # its builder call in flight answers no entry
    movq    $0, (NodeApi_cursor + PUBLISH_CALL)(%rdi)
    test    %rax, %rax
    jz      2f
    dec     %rax
    imul    $NODE_BUILDER_CALL_SIZE, %rax, %rax
    movq    $-1, (Node_builder_calls + 8)(%rbx,%rax)
2:  mov     (%rsp), %rdi
    call    lantern_node_publish_drop
    mov     (%rsp), %rdi
    mov     NodeApi_filter_slot(%rdi), %rsi
    movq    $0, NodeApi_filter_slot(%rdi)
    test    %rsi, %rsi
    jz      1f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
1:  mov     (%rsp), %rdi
    call    lantern_node_api_end
    UNFRAME 16
END_FUNCTION lantern_node_publish_end

/*
 * The answer rsi (200, 202, or an error) of the publishBlockV2 entry rdi, then its end; with
 * API_STREAM_GONE no answer. Locals: the entry.
 */
LOCAL_FUNCTION lantern_node_publish_answer
    FRAME 16
    mov     %rdi, (%rsp)
    mov     NodeApi_flags(%rdi), %rax
    test    $API_STREAM_GONE, %rax          # the connection closed: no answer
    jnz     2f
    mov     %rsi, %rdx
    mov     NodeApi_connection(%rdi), %rdi
    xor     %esi, %esi
    xor     %ecx, %ecx                      # 200 and 202: no body
    mov     $API_BODY_ERROR, %r8d
    cmp     $400, %rdx
    cmovae  %r8, %rcx
    mov     %rax, %r8
    and     $API_R_CLOSE, %r8d              # API_STREAM_CLOSE is API_R_CLOSE; HTTP/1.0 kept open says so
    jnz     1f
    test    $API_STREAM_HTTP10, %rax
    jz      1f
    mov     $API_R_KEEP, %r8d
1:  call    lantern_node_api_send
2:  mov     (%rsp), %rdi
    call    lantern_node_publish_end
    UNFRAME 16
END_FUNCTION lantern_node_publish_answer

/*
 * After the head (node.md, NODE_PUBLISH_IMPORT): each publishBlockV2 entry whose block's import
 * ended answers, 200 for a block the node imported, 202 for another. r12 an entry, r13 the count.
 */
LOCAL_FUNCTION lantern_node_publish_poll
    ENTER 0
    PART    %r12, %r13, %rbx, Node_api
1:  test    %r13, %r13
    jz      9f
    cmpq    $0, NodeApi_connection(%r12)
    je      2f
    cmpq    $API_OP_PUBLISH_BLOCK_V2, NodeApi_op(%r12)
    jne     2f
    cmpq    $NODE_PUBLISH_IMPORT, NodeApi_member(%r12)
    jne     2f
    testq   $API_STREAM_BUSY, NodeApi_flags(%r12)   # a work of it in flight
    jnz     2f
    lea     NodeApi_root(%r12), %rdi
    call    lantern_node_find_block
    mov     $202, %esi
    cmp     $-1, %rax
    je      3f
    mov     NodeBlock_status(%rdx), %rax
    cmp     $NODE_BLOCK_INVALID, %rax
    je      3f
    cmp     $NODE_BLOCK_IMPORTED, %rax
    jne     2f
    mov     $200, %esi
3:  mov     %r12, %rdi
    call    lantern_node_publish_answer
2:  add     $NodeApi__mem, %r12
    dec     %r13
    jmp     1b
9:  LEAVE 0
END_FUNCTION lantern_node_publish_poll

/* rax = the count of the publishBlockV2 entries. Uses rcx, rdx, rsi. */
LOCAL_FUNCTION lantern_node_api_publish_count
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    PART    %rcx, %rdx, %rbx, Node_api
1:  test    %rdx, %rdx
    jz      9f
    cmpq    $0, NodeApi_connection(%rcx)
    je      2f
    cmpq    $API_OP_PUBLISH_BLOCK_V2, NodeApi_op(%rcx)
    jne     2f
    inc     %rax
2:  add     $NodeApi__mem, %rcx
    dec     %rdx
    jmp     1b
9:  ret
END_FUNCTION lantern_node_api_publish_count

/*
 * The next work of the produceBlockV3 entry rdi in NODE_PRODUCE_FOLD: a PRODUCE_FOLD of the next
 * kept pool entry of the kind at cursor + 144 from index filter_slot, the kinds in the order of
 * api_produce_kinds; after the last, NODE_PRODUCE_BUILD and its PRODUCE_BLOCK. r12 the entry, r13
 * its index; S7 the draft's action, S8 the pool index, S9 the kind's index, S10 its topic.
 */
LOCAL_FUNCTION lantern_node_produce_next
    ENTER 0
    mov     %rdi, %r12
    PART    %rcx, %r10, %rbx, Node_api
    mov     %r12, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    mov     %rax, %r13
    orq     $API_STREAM_BUSY, NodeApi_flags(%r12)  # busy with its next work
    cmpq    $0, NodeApi_data(%r12)          # the draft, before the first fold: a zeroed buffer
    jne     11f
    mov     $NODE_ACT_BYTES_NEW, %edi
    mov     $NODE_ACT_BYTES_NEW_SIZE, %esi
    call    lantern_node_act
    mov     %rax, S7(%rsp)
    call    lantern_node_new_id
    mov     S7(%rsp), %rcx
    mov     %rax, 16(%rcx)
    mov     %rax, NodeApi_data(%r12)
    MOVQ    %rax, ProduceDraft__size + 24
    mov     %rax, 24(%rcx)
11: mov     NodeApi_filter_slot(%r12), %rax
    mov     %rax, S8(%rsp)
    mov     (NodeApi_cursor + 144)(%r12), %rax  # the kind: its index in api_produce_kinds
    mov     %rax, S9(%rsp)
1:  mov     S9(%rsp), %rax
    cmp     $API_PRODUCE_KINDS, %rax
    jae     5f
    lea     api_produce_kinds(%rip), %rcx
    movzbl  (%rcx,%rax), %eax
    mov     %rax, S10(%rsp)
2:  PART    %rcx, %rdx, %rbx, Node_pool
    mov     S8(%rsp), %rax
    cmp     %rdx, %rax
    jae     3f
    imul    $NodePool__mem, %rax, %rsi
    add     %rcx, %rsi
    inc     %rax
    mov     %rax, S8(%rsp)
    mov     NodePool_topic(%rsi), %rax
    cmp     S10(%rsp), %rax
    jne     2b
    cmpq    $NODE_POOL_KEPT, NodePool_state(%rsi)
    jne     2b
    mov     S8(%rsp), %rax
    mov     %rax, NodeApi_filter_slot(%r12)
    mov     S9(%rsp), %rax
    mov     %rax, (NodeApi_cursor + 144)(%r12)
    mov     NodePool_data_id(%rsi), %rax
    mov     %rax, NodeApi_root(%r12)
    mov     NodePool_topic(%rsi), %r9       # arg: the topic, the fork << 8, the member << 16
    mov     NodePool_fork(%rsi), %rax
    shl     $8, %rax
    or      %rax, %r9
    mov     NodePool_member(%rsi), %rax
    shl     $16, %rax
    or      %rax, %r9
    mov     $NODE_WORK_PRODUCE_FOLD, %edi
    mov     NodePool_data_id(%rsi), %rdx
    mov     NodeApi_data(%r12), %rcx
    mov     %r13, %r8
    mov     NodeApi_state(%r12), %rsi
    call    lantern_node_work
    LEAVE 0
3:  incq    S9(%rsp)                        # the next kind, from the pool's first entry
    movq    $0, S8(%rsp)
    jmp     1b
5:  movq    $NODE_PRODUCE_ETH1, NodeApi_member(%r12)  # after the last fold: the eth1 vote and deposits from the follower's snapshot
    call    lantern_node_eth1_snapshot
    mov     %rax, (NodeApi_cursor + PRODUCE_ETH1_SNAP)(%r12)
    mov     $NODE_WORK_PRODUCE_ETH1, %edi
    mov     NodeApi_state(%r12), %rsi
    mov     %rax, %rdx
    mov     NodeApi_data(%r12), %rcx
    mov     %r13, %r8
    xor     %r9d, %r9d
    call    lantern_node_work
    LEAVE 0
END_FUNCTION lantern_node_produce_next

/*
 * The produceBlockV3 entry rdi in NODE_PRODUCE_BID with no call in flight goes on (node.md, Block
 * production): with the builder's answer at PRODUCE_BID a PRODUCE_BID work of it, else the build.
 * r12 the entry, r13 its index.
 */
LOCAL_FUNCTION lantern_node_produce_bid_go
    ENTER 0
    mov     %rdi, %r12
    PART    %rcx, %r10, %rbx, Node_api
    mov     %r12, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    mov     %rax, %r13
    mov     (NodeApi_cursor + PRODUCE_BID)(%r12), %rcx
    test    %rcx, %rcx
    jz      5f
    orq     $API_STREAM_BUSY, NodeApi_flags(%r12)
    mov     $NODE_WORK_PRODUCE_BID, %edi
    mov     NodeApi_state(%r12), %rsi
    xor     %edx, %edx
    mov     %r13, %r8
    xor     %r9d, %r9d
    call    lantern_node_work
    LEAVE 0
5:  mov     %r12, %rdi
    call    lantern_node_produce_build
    LEAVE 0
END_FUNCTION lantern_node_produce_bid_go

/*
 * The build of the produceBlockV3 entry rdi (node.md, Block production): NODE_PRODUCE_BUILD and
 * its PRODUCE_BLOCK of the copy, the engine's result, the draft and the bid at PRODUCE_BID as
 * state_c. r12 the entry, r13 its index.
 */
LOCAL_FUNCTION lantern_node_produce_build
    ENTER 0
    mov     %rdi, %r12
    PART    %rcx, %r10, %rbx, Node_api
    mov     %r12, %rax
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $NodeApi__mem, %ecx
    div     %rcx
    mov     %rax, %r13
    orq     $API_STREAM_BUSY, NodeApi_flags(%r12)
    movq    $NODE_PRODUCE_BUILD, NodeApi_member(%r12)
    mov     $NODE_WORK_PRODUCE_BLOCK, %edi
    mov     NodeApi_state(%r12), %rsi
    mov     NodeApi_filter_index(%r12), %rdx
    mov     NodeApi_data(%r12), %rcx
    mov     %r13, %r8
    xor     %r9d, %r9d
    call    lantern_node_work
    mov     (NodeApi_cursor + PRODUCE_BID)(%r12), %rcx
    mov     %rcx, NodeAction_state_c(%rax)
    LEAVE 0
END_FUNCTION lantern_node_produce_build

/*
 * At a quiet point (node.md, Block production, NODE_PRODUCE_BID): each produceBlockV3 entry
 * waiting for its bid, with no work in flight: a header call in flight past
 * BUILDER_PROPOSAL_DELAY_TOLERANCE_MS answers no entry; with no call in flight, the entry goes on
 * while the actions have room for two works. rbx the node, r15 the actions; r12 an entry, r13
 * the entries left.
 */
LOCAL_FUNCTION lantern_node_produce_due
    ENTER 0
    PART    %r12, %r13, %rbx, Node_api
1:  test    %r13, %r13
    jz      9f
    cmpq    $0, NodeApi_connection(%r12)
    je      2f
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%r12)
    jne     2f
    cmpq    $NODE_PRODUCE_BID, NodeApi_member(%r12)
    jne     2f
    testq   $API_STREAM_BUSY, NodeApi_flags(%r12)   # its bid's check
    jnz     2f
    mov     (NodeApi_cursor + PRODUCE_CALL)(%r12), %rax
    test    %rax, %rax
    jz      3f
    dec     %rax                            # the call in flight: late at its time + the tolerance
    imul    $NODE_BUILDER_CALL_SIZE, %rax, %rax
    lea     Node_builder_calls(%rbx,%rax), %rcx
    mov     16(%rcx), %rax
    add     $BUILDER_PROPOSAL_DELAY_TOLERANCE_MS, %rax
    cmp     %rax, Node_time_ms(%rbx)
    jb      2f
    movq    $-1, 8(%rcx)
    movq    $0, (NodeApi_cursor + PRODUCE_CALL)(%r12)
3:  mov     $(2 * NODE_ACT_WORK_SIZE), %edi
    call    lantern_node_room
    test    %rax, %rax
    jz      9f
    mov     %r12, %rdi
    call    lantern_node_produce_bid_go
2:  add     $NodeApi__mem, %r12
    dec     %r13
    jmp     1b
9:  LEAVE 0
END_FUNCTION lantern_node_produce_due

/* The draft and the engine's result of the produceBlockV3 entry rdi go. Locals: the entry. */
LOCAL_FUNCTION lantern_node_produce_release
    FRAME 16
    mov     %rdi, (%rsp)
    mov     NodeApi_data(%rdi), %rsi        # each field cleared first: lantern_node_ids leaves an entry's own bytes to it
    movq    $0, NodeApi_data(%rdi)
    test    %rsi, %rsi
    jz      1f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
1:  mov     (%rsp), %rdi
    mov     NodeApi_filter_index(%rdi), %rsi
    movq    $0, NodeApi_filter_index(%rdi)
    test    %rsi, %rsi
    jz      2f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
2:  mov     (%rsp), %rdi                    # the eth1 snapshot of a work in flight
    mov     (NodeApi_cursor + PRODUCE_ETH1_SNAP)(%rdi), %rsi
    movq    $0, (NodeApi_cursor + PRODUCE_ETH1_SNAP)(%rdi)
    test    %rsi, %rsi
    jz      21f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
21: mov     (%rsp), %rdi                    # the builder's answer or bid
    mov     (NodeApi_cursor + PRODUCE_BID)(%rdi), %rsi
    movq    $0, (NodeApi_cursor + PRODUCE_BID)(%rdi)
    test    %rsi, %rsi
    jz      3f
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
3:  mov     (%rsp), %rdi                    # its header call in flight answers no entry
    mov     (NodeApi_cursor + PRODUCE_CALL)(%rdi), %rax
    movq    $0, (NodeApi_cursor + PRODUCE_CALL)(%rdi)
    test    %rax, %rax
    jz      4f
    dec     %rax
    imul    $NODE_BUILDER_CALL_SIZE, %rax, %rax
    movq    $-1, (Node_builder_calls + 8)(%rbx,%rax)
4:  UNFRAME 16
END_FUNCTION lantern_node_produce_release

/*
 * The error rsi to the produceBlockV3 entry rdi, then its end: its draft and engine result go,
 * and its state with API_STREAM_OWN_STATE. Locals: the entry.
 */
LOCAL_FUNCTION lantern_node_produce_fail
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rsi, %rdx
    mov     NodeApi_flags(%rdi), %rax
    test    $API_STREAM_GONE, %rax          # the connection closed: no answer
    jnz     2f
    mov     NodeApi_connection(%rdi), %rdi
    xor     %esi, %esi
    mov     $API_BODY_ERROR, %ecx
    mov     %rax, %r8
    and     $API_R_CLOSE, %r8d              # API_STREAM_CLOSE is API_R_CLOSE; HTTP/1.0 kept open says so
    jnz     1f
    test    $API_STREAM_HTTP10, %rax
    jz      1f
    mov     $API_R_KEEP, %r8d
1:  call    lantern_node_api_send
2:  mov     (%rsp), %rdi
    call    lantern_node_produce_release
    mov     (%rsp), %rdi
    call    lantern_node_api_end
    UNFRAME 16
END_FUNCTION lantern_node_produce_fail

/* rax = the index of a free NodeApi entry (the first free, else the next; the step checked one is free), rdx = the entry. Uses r10. */
LOCAL_FUNCTION lantern_node_api_new
    UNWIND_END_PROLOGUE
    PART    %rdx, %r10, %rbx, Node_api
    xor     %eax, %eax
1:  cmp     %r10, %rax
    jae     2f
    cmpq    $0, NodeApi_connection(%rdx)
    je      3f
    add     $NodeApi__mem, %rdx
    inc     %rax
    jmp     1b
2:  incq    (Node_api + 8)(%rbx)
3:  ret
END_FUNCTION lantern_node_api_new

/*
 * The end of the stream of the NodeApi entry rdi: the entry is free, the api part's count drops
 * past the free entries at its end; with API_STREAM_OWN, a BYTES_FREE of its data, which lantern_node_ids
 * gives to another entry that sends the same bytes.
 */
LOCAL_FUNCTION lantern_node_api_end
    FRAME 16
    movq    $0, NodeApi_connection(%rdi)
    mov     %rdi, (%rsp)
    PART    %rcx, %r10, %rbx, Node_api
1:  test    %r10, %r10
    jz      2f
    imul    $NodeApi__mem, %r10, %rax
    cmpq    $0, (NodeApi_connection - NodeApi__mem)(%rcx,%rax)
    jne     2f
    dec     %r10
    jmp     1b
2:  mov     %r10, (Node_api + 8)(%rbx)
    testq   $API_STREAM_OWN, NodeApi_flags(%rdi)
    jz      8f
    mov     NodeApi_data(%rdi), %rsi
    mov     $NODE_ACT_BYTES_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
8:  mov     (%rsp), %rdi
    testq   $API_STREAM_OWN_STATE, NodeApi_flags(%rdi)
    jz      9f
    mov     NodeApi_state(%rdi), %rsi
    mov     $NODE_ACT_STATE_FREE, %edi
    xor     %edx, %edx
    call    lantern_node_ids
9:  UNFRAME 16
END_FUNCTION lantern_node_api_end

/* A NODE_WORK_API_CHUNK of the NodeApi entry rdx at index rax, which takes API_STREAM_BUSY. */
LOCAL_FUNCTION lantern_node_api_chunk_work
    UNWIND_END_PROLOGUE
    orq     $API_STREAM_BUSY, NodeApi_flags(%rdx)
    mov     %rax, %r9
    mov     NodeApi_data(%rdx), %rcx
    mov     NodeApi_connection(%rdx), %r8
    mov     NodeApi_state(%rdx), %rsi       # a validator stream's state
    mov     $NODE_WORK_API_CHUNK, %edi
    xor     %edx, %edx
    jmp     lantern_node_work
END_FUNCTION lantern_node_api_chunk_work

/* NODE_EV_API_SENT of the connection rdi: the next chunk of its stream, unless one is queued. */
LOCAL_FUNCTION lantern_node_api_sent
    FRAME 0
    call    lantern_node_api_find
    cmp     $-1, %rax
    je      9f
    cmpq    $API_OP_EVENTSTREAM, NodeApi_op(%rdx)  # an event stream: its sent is 0
    jne     1f
    movq    $0, NodeApi_sent(%rdx)
    jmp     9f
1:  testq   $API_STREAM_BUSY, NodeApi_flags(%rdx)
    jnz     9f
    call    lantern_node_api_chunk_work
9:  UNFRAME 0
END_FUNCTION lantern_node_api_sent

# ---------------------------------------------------------------- Events (beacon-api.md, eventstream)

/*
 * (node rdi, work rsi, state_a rdx, data rcx, scratch r8, event r9, room r10) -> rax: a
 * NODE_WORK_API_EVENT of lantern_node_run (node.md): the event's text at NodeEvent_chunk of the
 * event. rbx the node, r12 the work, r13 state_a, r14 the scratch, r15 the event, S7 data, S8 the
 * ApiView at the end of scratch, S9 the topic, S10 the room. Locals: L the scratch's size, L+8 a
 * Result, L+16 a blob count.
 */
LOCAL_FUNCTION lantern_node_api_event_run
    ENTER 32
    mov     %r11, (L + 24)(%rsp)            # state_c: the light client store
    mov     %rdi, %rbx
    mov     %rsi, %r12
    mov     %rdx, %r13
    mov     %rcx, S7(%rsp)
    mov     %r8, %r14
    mov     %r9, %r15
    mov     %r10, S10(%rsp)
    movzbl  NodeAction_arg(%r12), %eax
    mov     %rax, S9(%rsp)
    mov     (%r14), %rax                    # the ApiView at the end of scratch, with the work's values
    mov     %rax, L(%rsp)
    sub     $ApiView__size, %rax
    jb      7f
    mov     %rax, (%r14)
    add     %r14, %rax
    mov     %rax, S8(%rsp)
    mov     NodeAction_arg(%r12), %rcx
    movzbl  %ch, %edx
    mov     %rdx, ApiView_event_flags(%rax)
    shr     $16, %rcx
    mov     %rcx, ApiView_event_epoch(%rax)
    cmpq    $API_TOPIC_HEAD, S9(%rsp)
    je      1f
    cmpq    $API_TOPIC_HEAD_V2, S9(%rsp)
    je      1f
    cmpq    $API_TOPIC_CHAIN_REORG, S9(%rsp)
    je      20f
    cmpq    $API_TOPIC_FINALIZED_CHECKPOINT, S9(%rsp)
    jne     10f
    cmpq    $0, S7(%rsp)
    jne     3f
1:  test    %r13, %r13                      # of a post-state: lantern_node_event_roots
    jz      8f
    mov     NODE_STATE_SLOT(%r13), %rdi
    mov     S8(%rsp), %rax
    mov     %rdi, ApiView_event_slot(%rax)
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     S8(%rsp), %rcx                  # head_v2's version
    mov     %rax, ApiView_fork(%rcx)
    mov     %r13, %rdi
    lea     Node_config(%rbx), %rsi
    mov     %r14, %rdx
    mov     S8(%rsp), %rcx
    add     $ApiView_event_block, %rcx
    FORK_CALL node_event_roots
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      5f
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
3:  mov     S7(%rsp), %rcx                  # of a block's bytes: its root and its state_root
    cmpq    $(100 + 84), 16(%rcx)
    jb      41f
    mov     8(%rcx), %rax
    add     %rcx, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     S7(%rsp), %rcx
    mov     8(%rcx), %rax
    add     %rcx, %rax
    lea     (100 + 48)(%rax), %rsi
    mov     S8(%rsp), %rdi
    add     $ApiView_event_state, %rdi
    COPY32  %rdi, %rsi
    mov     S7(%rsp), %rdi
    mov     %r14, %rsi
    mov     S8(%rsp), %rdx
    add     $ApiView_event_block, %rdx
    lea     (L + 8)(%rsp), %rcx
    lea     (L + 16)(%rsp), %r8
    FORK_CALL node_block_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jnz     41f
    cmpq    $0, (L + 8)(%rsp)
    jne     41f
5:  mov     S10(%rsp), %rax                 # the text, in the event
    sub     $NodeEvent_chunk, %rax
    and     $-8, %rax
    cmp     $24, %rax
    jb      71f
    mov     %rax, NodeEvent_chunk(%r15)
    mov     S8(%rsp), %rdi
    lea     NodeEvent_chunk(%r15), %rsi
    mov     S9(%rsp), %rdx
    call    lantern_api_event_text
    test    %rax, %rax
    jnz     71f
55: mov     (NodeEvent_chunk + 16)(%r15), %rax  # the event's size covers the text
    add     $(NodeEvent_chunk + 24 + 7), %rax
    and     $-8, %rax
    mov     %rax, (%r15)
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%r15)
    jmp     9f
20: test    %r13, %r13                      # chain_reorg: the new head from its post-state, the old from its block's bytes
    jz      8f
    cmpq    $0, S7(%rsp)
    je      8f
    mov     NODE_STATE_SLOT(%r13), %rdi
    mov     S8(%rsp), %rax
    mov     %rdi, ApiView_event_slot(%rax)
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     %r13, %rdi
    lea     Node_config(%rbx), %rsi
    mov     %r14, %rdx
    mov     S8(%rsp), %rcx
    add     $ApiView_event_block, %rcx
    FORK_CALL node_event_roots
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      21f
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
21: mov     S7(%rsp), %rcx                  # the old head block's bytes: its root and its state_root
    cmpq    $(100 + 84), 16(%rcx)
    jb      41f
    mov     8(%rcx), %rax
    add     %rcx, %rax
    mov     100(%rax), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     S7(%rsp), %rcx
    mov     8(%rcx), %rax
    add     %rcx, %rax
    lea     (100 + 48)(%rax), %rsi
    mov     S8(%rsp), %rdi
    add     $ApiView_event_old_state, %rdi
    COPY32  %rdi, %rsi
    mov     S7(%rsp), %rdi
    mov     %r14, %rsi
    mov     S8(%rsp), %rdx
    add     $ApiView_event_old_block, %rdx
    lea     (L + 8)(%rsp), %rcx
    lea     (L + 16)(%rsp), %r8
    FORK_CALL node_block_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jnz     41f
    cmpq    $0, (L + 8)(%rsp)
    jne     41f
    jmp     5b
10: mov     S9(%rsp), %rax                  # the light client topics: of the store's latest update
    cmp     $API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE, %rax
    je      100f
    cmp     $API_TOPIC_LIGHT_CLIENT_OPTIMISTIC_UPDATE, %rax
    jne     101f
100: mov    (L + 24)(%rsp), %rdx
    test    %rdx, %rdx
    jz      8f
    mov     S10(%rsp), %rax                 # the text, in the event
    sub     $NodeEvent_chunk, %rax
    and     $-8, %rax
    cmp     $64, %rax
    jb      71f
    mov     %rax, NodeEvent_chunk(%r15)
    lea     NodeEvent_chunk(%r15), %rdi
    mov     S9(%rsp), %rsi
    mov     %r14, %rcx
    call    lantern_api_lc_event_text
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      55b
    mov     %rax, NodeEvent_result(%r15)
    jmp     9f
101: mov    S9(%rsp), %rax                  # an operation topic: the JSON of its bytes, lantern_node_json of the fork in arg
    mov     $NODE_JSON_EXIT, %edx
    cmp     $API_TOPIC_VOLUNTARY_EXIT, %rax
    je      11f
    mov     $NODE_JSON_BLS_CHANGE, %edx
    cmp     $API_TOPIC_BLS_TO_EXECUTION_CHANGE, %rax
    je      11f
    mov     $NODE_JSON_PROPOSER_SLASHING, %edx
    cmp     $API_TOPIC_PROPOSER_SLASHING, %rax
    je      11f
    mov     $NODE_JSON_ATTESTER_SLASHING, %edx
    cmp     $API_TOPIC_ATTESTER_SLASHING, %rax
    je      11f
    mov     $NODE_JSON_ATTESTATION, %edx
    cmp     $API_TOPIC_ATTESTATION, %rax
    je      11f
    mov     $NODE_JSON_SINGLE_ATTESTATION, %edx
    cmp     $API_TOPIC_SINGLE_ATTESTATION, %rax
    je      11f
    mov     $NODE_JSON_CONTRIBUTION_AND_PROOF, %edx
    cmp     $API_TOPIC_CONTRIBUTION_AND_PROOF, %rax
    jne     12f
11: mov     S7(%rsp), %rcx
    test    %rcx, %rcx
    jz      41f
    mov     (%r14), %rax                    # a JsonCursor at the end of scratch
    sub     $JSON_CURSOR_SIZE, %rax
    jb      71f
    mov     %rax, (%r14)
    lea     (%r14,%rax), %r8
    movzbl  (NodeAction_arg + 2)(%r12), %r10d
    mov     S10(%rsp), %rax                 # the text, in the event
    sub     $NodeEvent_chunk, %rax
    and     $-8, %rax
    cmp     $64, %rax
    jb      71f
    mov     %rax, NodeEvent_chunk(%r15)
    lea     NodeEvent_chunk(%r15), %rdi
    mov     S9(%rsp), %rsi
    call    lantern_api_op_event_text
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      55b
    jmp     41f
12: cmp     $API_TOPIC_BLOB_SIDECAR, %rax   # a sidecar topic: its fields from its bytes
    je      13f
    cmp     $API_TOPIC_DATA_COLUMN_SIDECAR, %rax
    jne     8f
13: cmpq    $0, S7(%rsp)
    je      41f
    movzbl  (NodeAction_arg + 2)(%r12), %r10d
    mov     S10(%rsp), %rax                 # the text, in the event
    sub     $NodeEvent_chunk, %rax
    and     $-8, %rax
    cmp     $64, %rax
    jb      71f
    mov     %rax, NodeEvent_chunk(%r15)
    lea     NodeEvent_chunk(%r15), %rdi
    mov     S9(%rsp), %rsi
    mov     S7(%rsp), %rdx
    mov     %r14, %rcx
    call    lantern_api_sidecar_event_text
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      71f
    test    %rax, %rax
    jz      55b
41: movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%r15)
9:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
    xor     %eax, %eax
    LEAVE 32
8:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
    mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 32
71: mov     L(%rsp), %rax
    mov     %rax, (%r14)
7:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 32
END_FUNCTION lantern_node_api_event_run

/*
 * (out rdi, answer flags rsi) -> rax: the head of an eventstream answer into the ByteList out, its
 * count set; LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL. The writer's registers; rbx out, S7 the flags.
 */
LOCAL_FUNCTION lantern_api_sse_head
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, S7(%rsp)
    mov     $1, %r13d
    xor     %r15d, %r15d
    lea     24(%rbx), %r12
    mov     (%rbx), %r14
    add     %rbx, %r14
    API_LIT api_ev_head
    testq   $API_ANSWER_HTTP10, S7(%rsp)
    jnz     1f
    API_LIT api_ev_chunked
    testq   $API_ANSWER_CLOSE, S7(%rsp)
    jz      2f
1:  API_LIT api_ev_close
2:  API_LIT api_crlf
    test    %r15, %r15
    jnz     9f
    lea     24(%rbx), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    xor     %eax, %eax
    LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION lantern_api_sse_head

/*
 * (view rdi, out rsi, topic rdx) -> rax: the text of the event of the topic, from the view's event
 * fields, into the ByteList out, its count set; LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL. The
 * writer's registers; rbx out, S7 the topic.
 */
LOCAL_FUNCTION lantern_api_event_text
    ENTER 0
    mov     %rdi, %rbp
    mov     %rsi, %rbx
    mov     %rdx, S7(%rsp)
    mov     $1, %r13d
    xor     %r15d, %r15d
    lea     24(%rbx), %r12
    mov     (%rbx), %r14
    add     %rbx, %r14
    API_LIT api_ev_event
    cmpq    $API_TOPIC_HEAD, S7(%rsp)
    jne     13f
    API_LIT api_ev_t_head
    jmp     3f
13: cmpq    $API_TOPIC_HEAD_V2, S7(%rsp)
    jne     1f
    # head_v2: {"version":…,"data":{"slot":…,"block":…,"state":…,"payload_status":"full","epoch_transition":…,"current_epoch_dependent_root":…,"next_epoch_dependent_root":…,"execution_optimistic":…}}
    API_LIT api_ev_t_head_v2
    API_LIT api_ev_data
    API_LIT api_pa_version
    mov     ApiView_fork(%rbp), %rdi
    call    lantern_api_fork_name
    API_LIT api_ev_v2_slot
    mov     ApiView_event_slot(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_ev_block
    lea     ApiView_event_block(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_ev_state
    lea     ApiView_event_state(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_ev_full
    API_LIT api_ev_transition
    mov     ApiView_event_flags(%rbp), %rdi
    and     $1, %edi
    call    lantern_api_bool
    API_LIT api_ev_current_epoch
    lea     ApiView_event_previous(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_ev_next_epoch
    lea     ApiView_event_current(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_u_optimistic
    mov     ApiView_event_flags(%rbp), %rdi
    shr     $1, %rdi
    and     $1, %edi
    call    lantern_api_bool
    API_LIT api_end1
    jmp     61f
1:  cmpq    $API_TOPIC_BLOCK, S7(%rsp)
    jne     11f
    API_LIT api_ev_t_block
    jmp     3f
11: cmpq    $API_TOPIC_BLOCK_GOSSIP, S7(%rsp)
    jne     12f
    API_LIT api_ev_t_block_gossip
    jmp     3f
12: cmpq    $API_TOPIC_CHAIN_REORG, S7(%rsp)
    jne     2f
    API_LIT api_ev_t_reorg
    jmp     3f
2:  API_LIT api_ev_t_finalized
3:  API_LIT api_ev_data
    cmpq    $API_TOPIC_FINALIZED_CHECKPOINT, S7(%rsp)
    je      5f
    cmpq    $API_TOPIC_CHAIN_REORG, S7(%rsp)
    je      7f
    # block, block_gossip and head: {"slot":…,"block":…
    API_LIT api_ev_slot
    mov     ApiView_event_slot(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_ev_block
    lea     ApiView_event_block(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    cmpq    $API_TOPIC_BLOCK_GOSSIP, S7(%rsp)
    je      61f
    cmpq    $API_TOPIC_HEAD, S7(%rsp)
    jne     6f
    # head: state, epoch_transition and the dependent roots
    API_LIT api_ev_state
    lea     ApiView_event_state(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_ev_transition
    mov     ApiView_event_flags(%rbp), %rdi
    and     $1, %edi
    call    lantern_api_bool
    API_LIT api_ev_previous
    lea     ApiView_event_previous(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_ev_current
    lea     ApiView_event_current(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    jmp     6f
    # finalized_checkpoint: {"block":…,"state":…,"epoch":…
5:  API_LIT api_ev_block1
    lea     ApiView_event_block(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_ev_state
    lea     ApiView_event_state(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_k_epoch
    mov     ApiView_event_epoch(%rbp), %rdi
    call    lantern_api_qdec
    jmp     6f
    # chain_reorg: {"slot":…,"depth":…,"old_head_block":…,"new_head_block":…,"old_head_state":…,"new_head_state":…,"epoch":…
7:  API_LIT api_ev_slot
    mov     ApiView_event_slot(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_cr_depth
    mov     ApiView_event_epoch(%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_cr_old_block
    lea     ApiView_event_old_block(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_cr_new_block
    lea     ApiView_event_block(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_cr_old_state
    lea     ApiView_event_old_state(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_cr_new_state
    lea     ApiView_event_state(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_k_epoch
    mov     ApiView_event_slot(%rbp), %rax
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %rdi
    call    lantern_api_qdec
6:  API_LIT api_u_optimistic
    mov     ApiView_event_flags(%rbp), %rdi
    shr     $1, %rdi
    and     $1, %edi
    call    lantern_api_bool
61: API_LIT api_ev_end
    test    %r15, %r15
    jnz     9f
    lea     24(%rbx), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    xor     %eax, %eax
    LEAVE 0
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION lantern_api_event_text

/*
 * (out rdi, topic rsi, kind rdx, ssz rcx, cursor r8; the fork in r10) -> rax: the text of the event
 * of an operation topic (beacon-api.md, eventstream): event: <topic> LF data: <lantern_node_json of
 * the kind and the ssz> LF LF, into the ByteList out, its count set; LANTERN_OK,
 * LANTERN_BUFFER_TOO_SMALL, or LANTERN_INVALID_ENCODING. The writer's registers; rbx out, S7 the
 * topic, S8 the kind, S9 the ssz, S10 the cursor. Locals: L the fork.
 */
LOCAL_FUNCTION lantern_api_op_event_text
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, S7(%rsp)
    mov     %rdx, S8(%rsp)
    mov     %rcx, S9(%rsp)
    mov     %r8, S10(%rsp)
    mov     %r10, L(%rsp)
    mov     $1, %r13d
    xor     %r15d, %r15d
    lea     24(%rbx), %r12
    mov     (%rbx), %r14
    add     %rbx, %r14
    API_LIT api_ev_event
    cmpq    $API_TOPIC_ATTESTATION, S7(%rsp)
    jne     1f
    API_LIT api_ev_t_attestation
    jmp     7f
1:  cmpq    $API_TOPIC_SINGLE_ATTESTATION, S7(%rsp)
    jne     2f
    API_LIT api_ev_t_single
    jmp     7f
2:  cmpq    $API_TOPIC_VOLUNTARY_EXIT, S7(%rsp)
    jne     3f
    API_LIT api_ev_t_exit
    jmp     7f
3:  cmpq    $API_TOPIC_BLS_TO_EXECUTION_CHANGE, S7(%rsp)
    jne     4f
    API_LIT api_ev_t_bls
    jmp     7f
4:  cmpq    $API_TOPIC_PROPOSER_SLASHING, S7(%rsp)
    jne     5f
    API_LIT api_ev_t_proposer
    jmp     7f
5:  cmpq    $API_TOPIC_ATTESTER_SLASHING, S7(%rsp)
    jne     6f
    API_LIT api_ev_t_attester
    jmp     7f
6:  API_LIT api_ev_t_contribution
7:  API_LIT api_ev_data
    test    %r15, %r15
    jnz     9f
    lea     24(%rbx), %rax                  # the JSON after the bytes so far
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    mov     S10(%rsp), %rdi
    mov     $JSON_CURSOR_SIZE, %esi
    call    lantern_zero
    mov     L(%rsp), %r10
    mov     S8(%rsp), %rdi
    mov     S9(%rsp), %rsi
    mov     S10(%rsp), %rdx
    mov     %rbx, %rcx
    FORK_CALL node_json
    cmp     $LANTERN_JSON_MORE, %rax        # the text passes the event's room
    je      9f
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      9f
    test    %rax, %rax
    jnz     8f
    mov     16(%rbx), %rax
    lea     24(%rbx,%rax), %r12
    API_LIT api_ev_lf2
    test    %r15, %r15
    jnz     9f
    lea     24(%rbx), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    xor     %eax, %eax
    LEAVE 16
8:  mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 16
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_api_op_event_text

/*
 * (out rdi, state rsi, attributes rdx, proposer rcx, head root r8; the fork in r10) -> rax: the
 * text of the payload_attributes event (beacon-api.md, eventstream) of a preparation: event:
 * payload_attributes LF data: {"version":…,"data":{…}} LF LF, into the ByteList out, its count
 * set; LANTERN_OK or LANTERN_BUFFER_TOO_SMALL. The writer's registers; rbx out, rbp the attributes,
 * S7 the state, S8 the proposer, S9 the head root, S10 the fork. Locals: L the parent's block
 * number and hash (40), L+40 a withdrawal's index, L+48 the withdrawal.
 */
LOCAL_FUNCTION lantern_api_payload_event_text
    ENTER 64
    mov     %rdi, %rbx
    mov     %rsi, S7(%rsp)
    mov     %rdx, %rbp
    mov     %rcx, S8(%rsp)
    mov     %r8, S9(%rsp)
    mov     %r10, S10(%rsp)
    mov     %rsi, %rdi                      # the parent's block number and hash
    lea     L(%rsp), %rsi
    FORK_CALL node_payload_parent
    test    %rax, %rax
    jnz     9f
    mov     $1, %r13d
    xor     %r15d, %r15d
    lea     24(%rbx), %r12
    mov     (%rbx), %r14
    add     %rbx, %r14
    API_LIT api_ev_event
    API_LIT api_ev_t_payload
    API_LIT api_ev_data
    API_LIT api_pa_version
    mov     S10(%rsp), %rdi
    call    lantern_api_fork_name
    API_LIT api_pa_proposer
    mov     S8(%rsp), %rdi
    call    lantern_api_qdec
    API_LIT api_pa_slot
    mov     S7(%rsp), %rax
    mov     NODE_STATE_SLOT(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_pa_number
    mov     L(%rsp), %rdi
    call    lantern_api_qdec
    API_LIT api_pa_root
    mov     S9(%rsp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_pa_hash
    lea     (L + 8)(%rsp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    # the PayloadAttributes (engine-api.md)
    API_LIT api_pa_time
    mov     (%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_pa_randao
    lea     8(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_pa_fee
    lea     40(%rbp), %rdi
    mov     $20, %esi
    call    lantern_api_qhex
    cmpq    $FORK_CAPELLA, S10(%rsp)        # from capella, the withdrawals: each 44 SSZ bytes
    jb      3f
    API_LIT api_pa_withdrawals
    movq    $0, (L + 40)(%rsp)
1:  mov     (L + 40)(%rsp), %rax
    cmp     96(%rbp), %rax
    jae     2f
    test    %rax, %rax
    jz      11f
    API_LIT api_p_comma
11: mov     (L + 40)(%rsp), %rax
    imul    $44, %rax, %rax
    lea     104(%rbp,%rax), %rax
    mov     %rax, (L + 48)(%rsp)
    API_LIT api_pa_index
    mov     (L + 48)(%rsp), %rax
    mov     (%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_u_index
    mov     (L + 48)(%rsp), %rax
    mov     8(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_pa_address
    mov     (L + 48)(%rsp), %rdi
    add     $16, %rdi
    mov     $20, %esi
    call    lantern_api_qhex
    API_LIT api_pa_amount
    mov     (L + 48)(%rsp), %rax
    mov     36(%rax), %rdi
    call    lantern_api_qdec
    API_LIT api_end1
    incq    (L + 40)(%rsp)
    jmp     1b
2:  API_LIT api_p_rbracket
3:  cmpq    $FORK_DENEB, S10(%rsp)          # from deneb, the parent beacon block root
    jb      4f
    API_LIT api_pa_parent
    lea     64(%rbp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
4:  API_LIT api_pa_end
    test    %r15, %r15
    jnz     9f
    lea     24(%rbx), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    xor     %eax, %eax
    LEAVE 64
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 64
END_FUNCTION lantern_api_payload_event_text

/*
 * (out rdi, topic rsi, ssz rdx, scratch rcx; the fork in r10) -> rax: the text of the event of a
 * sidecar topic (beacon-api.md, eventstream): event: <topic> LF data: {"block_root":…,"index":…,
 * "slot":…,…} LF LF, from the sidecar's bytes, into the ByteList out, its count set; LANTERN_OK,
 * LANTERN_BUFFER_TOO_SMALL, or LANTERN_INVALID_ENCODING. The writer's registers; rbx out, rbp the
 * bytes, S7 the topic, S8 their count, S9 a commitment's index. Locals: L the block root, L+32 a
 * versioned hash, L+64 a ByteList of a commitment (24 + 48).
 */
LOCAL_FUNCTION lantern_api_sidecar_event_text
    ENTER 144
    mov     %rdi, %rbx
    mov     %rsi, S7(%rsp)
    mov     8(%rdx), %rbp
    add     %rdx, %rbp
    mov     16(%rdx), %rax
    mov     %rax, S8(%rsp)
    mov     %rdx, %rdi                      # block_root: lantern_node_sidecar_root
    mov     %rcx, %rsi
    lea     L(%rsp), %rdx
    FORK_CALL node_sidecar_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      9f
    test    %rax, %rax
    jnz     8f
    mov     $1, %r13d
    xor     %r15d, %r15d
    lea     24(%rbx), %r12
    mov     (%rbx), %r14
    add     %rbx, %r14
    API_LIT api_ev_event
    cmpq    $API_TOPIC_BLOB_SIDECAR, S7(%rsp)
    jne     1f
    API_LIT api_ev_t_blob
    jmp     2f
1:  API_LIT api_ev_t_column
2:  API_LIT api_ev_data
    API_LIT api_sc_root
    lea     L(%rsp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_sc_index
    mov     (%rbp), %rdi
    call    lantern_api_qdec
    API_LIT api_c_slot
    cmpq    $API_TOPIC_BLOB_SIDECAR, S7(%rsp)
    jne     4f
    mov     (8 + PUB_BLOB_BYTES + 96)(%rbp), %rdi   # a BlobSidecar: the header's slot, the commitment, its versioned hash
    call    lantern_api_qdec
    API_LIT api_sc_commitment
    lea     (8 + PUB_BLOB_BYTES)(%rbp), %rdi
    mov     $48, %esi
    call    lantern_api_qhex
    API_LIT api_sc_hash
    lea     (L + 88)(%rsp), %rdi
    lea     (8 + PUB_BLOB_BYTES)(%rbp), %rsi
    mov     $48, %edx
    call    lantern_copy
    movq    $72, (L + 64)(%rsp)
    movq    $24, (L + 72)(%rsp)
    movq    $48, (L + 80)(%rsp)
    lea     (L + 64)(%rsp), %rdi
    lea     (L + 32)(%rsp), %rsi
    CALL_GLOBAL crypto_sha256
    test    %rax, %rax
    jnz     8f
    movb    $VERSIONED_HASH_VERSION_KZG, (L + 32)(%rsp)
    lea     (L + 32)(%rsp), %rdi
    mov     $32, %esi
    call    lantern_api_qhex
    API_LIT api_end1
    jmp     7f
4:  mov     20(%rbp), %rdi                  # a DataColumnSidecar: the header's slot, then the commitments
    call    lantern_api_qdec
    API_LIT api_sc_commitments
    mov     12(%rbp), %eax
    mov     16(%rbp), %ecx
    cmp     %rcx, %rax
    ja      8f
    cmp     S8(%rsp), %rcx
    ja      8f
    sub     %rax, %rcx
    mov     %rcx, %rax
    xor     %edx, %edx
    mov     $48, %ecx
    div     %rcx
    test    %rdx, %rdx
    jnz     8f
    movq    $0, S9(%rsp)
5:  mov     12(%rbp), %eax
    mov     16(%rbp), %ecx
    sub     %rax, %rcx
    mov     %rcx, %rax
    xor     %edx, %edx
    mov     $48, %ecx
    div     %rcx                            # the count: the bytes over 48
    cmp     %rax, S9(%rsp)
    jae     6f
    cmpq    $0, S9(%rsp)
    je      51f
    API_LIT api_p_comma
51: mov     12(%rbp), %eax
    imul    $48, S9(%rsp), %rdi
    add     %rax, %rdi
    add     %rbp, %rdi
    mov     $48, %esi
    call    lantern_api_qhex
    incq    S9(%rsp)
    jmp     5b
6:  API_LIT api_v_end
7:  API_LIT api_ev_lf2
    test    %r15, %r15
    jnz     9f
    lea     24(%rbx), %rax
    mov     %r12, %rcx
    sub     %rax, %rcx
    movq    $24, 8(%rbx)
    mov     %rcx, 16(%rbx)
    xor     %eax, %eax
    LEAVE 144
8:  mov     $LANTERN_INVALID_ENCODING, %eax
    LEAVE 144
9:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 144
END_FUNCTION lantern_api_sidecar_event_text

/*
 * The event of a valid operation of the gossip topic rdi, its bytes rsi, of the fork rdx (node.md,
 * The events): a NODE_WORK_API_EVENT of its event topic when an entry has the topic. Locals: the
 * bytes, the work's arg.
 */
LOCAL_FUNCTION lantern_node_op_event
    FRAME 16
    mov     %rsi, (%rsp)
    mov     $API_TOPIC_VOLUNTARY_EXIT, %eax
    cmp     $GOSSIP_VOLUNTARY_EXIT, %rdi
    je      1f
    mov     $API_TOPIC_BLS_TO_EXECUTION_CHANGE, %eax
    cmp     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %rdi
    je      1f
    mov     $API_TOPIC_PROPOSER_SLASHING, %eax
    cmp     $GOSSIP_PROPOSER_SLASHING, %rdi
    je      1f
    mov     $API_TOPIC_ATTESTER_SLASHING, %eax
    cmp     $GOSSIP_ATTESTER_SLASHING, %rdi
    je      1f
    mov     $API_TOPIC_CONTRIBUTION_AND_PROOF, %eax
    cmp     $GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF, %rdi
    je      1f
    mov     $API_TOPIC_BLOB_SIDECAR, %eax
    cmp     $GOSSIP_BLOB_SIDECAR, %rdi
    je      1f
    mov     $API_TOPIC_DATA_COLUMN_SIDECAR, %eax
    cmp     $GOSSIP_DATA_COLUMN_SIDECAR, %rdi
    je      1f
    cmp     $GOSSIP_BEACON_ATTESTATION, %rdi
    jne     9f
    mov     $API_TOPIC_ATTESTATION, %eax    # beacon_attestation: SingleAttestation from electra
    mov     $API_TOPIC_SINGLE_ATTESTATION, %ecx
    cmp     $FORK_ELECTRA, %rdx
    cmovae  %rcx, %rax
1:  shl     $16, %rdx
    or      %rdx, %rax
    mov     %rax, 8(%rsp)
    movzbl  %al, %edi
    call    lantern_node_api_subscribed
    test    %rax, %rax
    jz      9f
    mov     $NODE_WORK_API_EVENT, %edi
    xor     %esi, %esi
    xor     %edx, %edx
    mov     (%rsp), %rcx
    xor     %r8d, %r8d
    mov     8(%rsp), %r9
    call    lantern_node_work
9:  UNFRAME 16
END_FUNCTION lantern_node_op_event

/* rax = 1 when a NodeApi entry of eventstream has the topic rdi, else 0. Uses rcx, rdx, r10. */
LOCAL_FUNCTION lantern_node_api_subscribed
    UNWIND_END_PROLOGUE
    PART    %rdx, %r10, %rbx, Node_api
    mov     %rdi, %rcx
1:  test    %r10, %r10
    jz      8f
    cmpq    $0, NodeApi_connection(%rdx)
    je      2f
    cmpq    $API_OP_EVENTSTREAM, NodeApi_op(%rdx)
    jne     2f
    mov     NodeApi_cursor(%rdx), %rax
    bt      %rcx, %rax
    jc      9f
2:  add     $NodeApi__mem, %rdx
    dec     %r10
    jmp     1b
8:  xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION lantern_node_api_subscribed

/* rax = the NodeApi entries of eventstream. Uses rcx, rdx. */
LOCAL_FUNCTION lantern_node_api_event_count
    UNWIND_END_PROLOGUE
    xor     %eax, %eax
    PART    %rdx, %rcx, %rbx, Node_api
1:  test    %rcx, %rcx
    jz      9f
    cmpq    $0, NodeApi_connection(%rdx)
    je      2f
    cmpq    $API_OP_EVENTSTREAM, NodeApi_op(%rdx)
    jne     2f
    inc     %rax
2:  add     $NodeApi__mem, %rdx
    dec     %rcx
    jmp     1b
9:  ret
END_FUNCTION lantern_node_api_event_count

/*
 * eventstream of the connection rdi with the route rsi and the answer flags rdx (node.md,
 * NODE_EV_API): a NodeApi entry of the route's topics, and a SEND of the head with last 0, its bytes
 * the entry's sent. r12 the connection, r13 the route, then the action. Locals: L the flags, L+8 the entry.
 */
LOCAL_FUNCTION lantern_node_api_subscribe
    ENTER 16
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     %rdx, L(%rsp)
    call    lantern_node_api_new
    mov     %rdx, (L + 8)(%rsp)
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     (L + 8)(%rsp), %rdx
    mov     %r12, NodeApi_connection(%rdx)
    movq    $API_OP_EVENTSTREAM, NodeApi_op(%rdx)
    mov     $API_STREAM_STARTED, %eax
    testq   $API_ANSWER_HTTP10, L(%rsp)
    jnz     1f
    or      $API_STREAM_CHUNKED, %eax
    testq   $API_ANSWER_CLOSE, L(%rsp)
    jz      2f
    or      $API_STREAM_CLOSE, %eax
    jmp     2f
1:  or      $(API_STREAM_CLOSE | API_STREAM_HTTP10), %eax
2:  mov     %rax, NodeApi_flags(%rdx)
    mov     ApiRoute_topics(%r13), %rax
    mov     %rax, NodeApi_cursor(%rdx)
    mov     $NODE_ACT_API_SEND, %edi        # the head: 56 + 128 bytes of room
    mov     $(56 + 128), %esi
    call    lantern_node_act
    mov     %rax, %r13
    lea     16(%rax), %rdi
    mov     $(56 + 128 - 16), %esi
    call    lantern_zero
    mov     %r12, 16(%r13)
    movq    $(128 + 24), 32(%r13)
    lea     32(%r13), %rdi
    mov     L(%rsp), %rsi
    call    lantern_api_sse_head
    mov     48(%r13), %rax
    mov     (L + 8)(%rsp), %rdx
    mov     %rax, NodeApi_sent(%rdx)
    LEAVE 16
END_FUNCTION lantern_node_api_subscribe

/*
 * The event text of the ByteList rdi, of the topic rsi, to each NodeApi entry of eventstream of the
 * topic (node.md, The events): a SEND of it, in one chunk with API_STREAM_CHUNKED, its bytes added
 * to the entry's sent; an entry whose sent would pass NODE_API_CHUNK gets a CLOSE and ends. r12 the
 * text, r13 the topic. Locals: L the index, L+8 the entry, L+16 the bytes sent, L+24 the action.
 */
LOCAL_FUNCTION lantern_node_api_events
    ENTER 32
    mov     %rdi, %r12
    mov     %rsi, %r13
    movq    $0, L(%rsp)
1:  PART    %rdx, %r10, %rbx, Node_api
    mov     L(%rsp), %rax
    cmp     %r10, %rax
    jae     9f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %rdx
    mov     %rdx, (L + 8)(%rsp)
    cmpq    $0, NodeApi_connection(%rdx)
    je      8f
    cmpq    $API_OP_EVENTSTREAM, NodeApi_op(%rdx)
    jne     8f
    mov     NodeApi_cursor(%rdx), %rax
    bt      %r13, %rax
    jnc     8f
    mov     16(%r12), %rax
    testq   $API_STREAM_CHUNKED, NodeApi_flags(%rdx)
    jz      2f
    add     $8, %rax                        # a chunk: 4 hex digits, CRLF, the text, CRLF
2:  mov     %rax, (L + 16)(%rsp)
    add     NodeApi_sent(%rdx), %rax
    cmp     $NODE_API_CHUNK, %rax
    ja      5f
    mov     %rax, NodeApi_sent(%rdx)
    mov     (L + 16)(%rsp), %rsi
    add     $(56 + 7), %rsi
    and     $-8, %rsi
    mov     $NODE_ACT_API_SEND, %edi
    call    lantern_node_act
    mov     %rax, (L + 24)(%rsp)
    lea     16(%rax), %rdi
    mov     (%rax), %rsi
    sub     $16, %rsi
    call    lantern_zero
    mov     (L + 24)(%rsp), %rax
    mov     (L + 8)(%rsp), %rdx
    mov     NodeApi_connection(%rdx), %rcx
    mov     %rcx, 16(%rax)
    mov     (%rax), %rcx
    sub     $32, %rcx
    mov     %rcx, 32(%rax)
    movq    $24, 40(%rax)
    mov     (L + 16)(%rsp), %rcx
    mov     %rcx, 48(%rax)
    lea     56(%rax), %rdi
    testq   $API_STREAM_CHUNKED, NodeApi_flags(%rdx)
    jz      3f
    mov     16(%r12), %r8                   # the size in 4 lower case hex digits, CRLF
    mov     $12, %ecx
4:  mov     %r8, %r9
    shr     %cl, %r9
    and     $15, %r9d
    cmp     $10, %r9d
    jb      41f
    add     $(0x61 - 10 - 0x30), %r9d
41: add     $0x30, %r9d
    mov     %r9b, (%rdi)
    inc     %rdi
    sub     $4, %ecx
    jns     4b
    movw    $0x0a0d, (%rdi)
    add     $2, %rdi
3:  lea     24(%r12), %rsi
    mov     16(%r12), %rdx
    call    lantern_copy
    mov     (L + 8)(%rsp), %rdx
    testq   $API_STREAM_CHUNKED, NodeApi_flags(%rdx)
    jz      8f
    mov     (L + 24)(%rsp), %rax            # and CRLF after the text
    add     16(%r12), %rax
    movw    $0x0a0d, (56 + 6)(%rax)
    jmp     8f
5:  mov     $NODE_ACT_API_CLOSE, %edi       # the stream falls behind: a CLOSE, and it ends
    mov     $NODE_ACT_API_CLOSE_SIZE, %esi
    call    lantern_node_act
    mov     (L + 8)(%rsp), %rdi
    mov     NodeApi_connection(%rdi), %rcx
    mov     %rcx, 16(%rax)
    call    lantern_node_api_end
8:  incq    L(%rsp)
    jmp     1b
9:  LEAVE 32
END_FUNCTION lantern_node_api_events

/* The block event of the NodeBlock entry rdi (node.md, The events): its slot and root, execution_optimistic from its payload status. */
LOCAL_FUNCTION lantern_node_api_block_event
    FRAME 0
    xor     %ecx, %ecx
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rdi)
    sete    %cl
    shl     $1, %ecx
    mov     NodeBlock_slot(%rdi), %rdx
    lea     NodeBlock_root(%rdi), %rsi
    mov     $API_TOPIC_BLOCK, %edi
    call    lantern_node_api_root_event
    UNFRAME 0
END_FUNCTION lantern_node_api_block_event

/*
 * The event of the topic rdi (block or block_gossip) of the block root rsi and slot rdx, with the
 * values rcx (node.md, The events), with an entry of the topic: its text in a ByteList at the end
 * of scratch, after the ApiView of its values. r12 the root, r13 the view. Locals: L the scratch's
 * size, L+8 the ByteList, L+16 the topic, L+24 the slot, L+32 the values.
 */
LOCAL_FUNCTION lantern_node_api_root_event
    ENTER 48
    mov     %rsi, %r12
    mov     %rdi, (L + 16)(%rsp)
    mov     %rdx, (L + 24)(%rsp)
    mov     %rcx, (L + 32)(%rsp)
    call    lantern_node_api_subscribed
    test    %rax, %rax
    jz      9f
    mov     (%r14), %rax
    mov     %rax, L(%rsp)
    sub     $(ApiView__size + 1024), %rax
    jb      9f
    mov     %rax, (%r14)
    lea     (%r14,%rax), %r13
    lea     ApiView__size(%r13), %rax
    mov     %rax, (L + 8)(%rsp)
    movq    $1024, (%rax)
    movq    $24, 8(%rax)
    movq    $0, 16(%rax)
    mov     (L + 24)(%rsp), %rax
    mov     %rax, ApiView_event_slot(%r13)
    lea     ApiView_event_block(%r13), %rax
    COPY32  %rax, %r12
    mov     (L + 32)(%rsp), %rax
    mov     %rax, ApiView_event_flags(%r13)
    mov     %r13, %rdi
    mov     (L + 8)(%rsp), %rsi
    mov     (L + 16)(%rsp), %rdx
    call    lantern_api_event_text
    test    %rax, %rax
    jnz     8f
    mov     (L + 8)(%rsp), %rdi
    mov     (L + 16)(%rsp), %rsi
    call    lantern_node_api_events
8:  mov     L(%rsp), %rax
    mov     %rax, (%r14)
9:  LEAVE 48
END_FUNCTION lantern_node_api_root_event

/*
 * (old head root rdi, new head entry rsi) -> rax: the depth of the reorg from the old head to the
 * new (node.md, The events: chain_reorg), or 2^64 - 1 with none: the new head's chain has the old
 * head below the new head's slot, or a walk meets no common block; rdx the old head's entry. The
 * walk by parent_root from both, the one at the higher slot first. r12 the old head's entry, r13
 * the new head's, r14 the old chain's block, S7 the new chain's, S8 and S9 the blocks each walk
 * left last.
 */
LOCAL_FUNCTION lantern_node_api_reorg
    ENTER 0
    mov     %rsi, %r13
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      8f
    mov     %rdx, %r12
    mov     %rdx, %r14
    mov     %r13, S7(%rsp)
    movq    $0, S8(%rsp)
    movq    $0, S9(%rsp)
1:  mov     S7(%rsp), %rcx                  # the same block: the common one
    movdqu  (%r14), %xmm0
    movdqu  (%rcx), %xmm1
    pcmpeqb %xmm1, %xmm0
    pmovmskb %xmm0, %eax
    cmp     $0xffff, %eax
    jne     2f
    movdqu  16(%r14), %xmm0
    movdqu  16(%rcx), %xmm1
    pcmpeqb %xmm1, %xmm0
    pmovmskb %xmm0, %eax
    cmp     $0xffff, %eax
    je      4f
2:  mov     S7(%rsp), %rcx
    mov     NodeBlock_slot(%rcx), %rax
    cmp     %rax, NodeBlock_slot(%r14)
    jb      3f
    mov     %r14, S8(%rsp)                  # the old chain's block, a step down
    lea     NodeBlock_parent_root(%r14), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      8f
    mov     %rdx, %r14
    jmp     1b
3:  mov     %rcx, S9(%rsp)                  # the new chain's block, a step down
    lea     NodeBlock_parent_root(%rcx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      8f
    mov     %rdx, S7(%rsp)
    jmp     1b
4:  mov     NodeBlock_slot(%r12), %rax      # the old head common, below the new head's slot: no reorg
    mov     NodeBlock_slot(%r13), %rcx
    cmp     %r12, %r14
    jne     41f
    cmp     %rcx, %rax
    jb      8f
41: cmp     %rcx, %rax                      # the lowest of the two heads' slots and the slot before each chain's first block after it
    mov     %rcx, %rdx
    cmovb   %rax, %rdx
    mov     S8(%rsp), %rsi
    test    %rsi, %rsi
    jz      5f
    mov     NodeBlock_slot(%rsi), %rsi
    dec     %rsi
    cmp     %rdx, %rsi
    cmovb   %rsi, %rdx
5:  mov     S9(%rsp), %rsi
    test    %rsi, %rsi
    jz      6f
    mov     NodeBlock_slot(%rsi), %rsi
    dec     %rsi
    cmp     %rdx, %rsi
    cmovb   %rsi, %rdx
6:  sub     %rdx, %rax
    mov     %r12, %rdx
    LEAVE 0
8:  mov     $-1, %rax
    LEAVE 0
END_FUNCTION lantern_node_api_reorg

/*
 * The head and finalized_checkpoint events at a quiet point (node.md, The events): with no block
 * vote queued, a head other than event_head, then a finalized epoch above event_epoch; each a
 * NODE_WORK_API_EVENT when an entry has its topic. r12 the block, r13 the values.
 */
.if API_TOPIC_HEAD
.error "node_api_head_events: the arg of a head event takes API_TOPIC_HEAD as 0"
.endif
LOCAL_FUNCTION lantern_node_api_head_events
    ENTER 0
    cmpq    $0, Node_event_votes(%rbx)
    jne     9f
    lea     Node_head_root(%rbx), %rdi
    movdqu  (%rdi), %xmm0
    movdqu  Node_event_head(%rbx), %xmm1
    pcmpeqb %xmm1, %xmm0
    pmovmskb %xmm0, %eax
    cmp     $0xffff, %eax
    jne     1f
    movdqu  16(%rdi), %xmm0
    movdqu  (Node_event_head + 16)(%rbx), %xmm1
    pcmpeqb %xmm1, %xmm0
    pmovmskb %xmm0, %eax
    cmp     $0xffff, %eax
    je      5f
1:  call    lantern_node_find_block
    cmp     $-1, %rax
    je      5f
    mov     %rdx, %r12
    mov     $NODE_WORK_LC_HEAD, %edi        # the light client data first
    xor     %esi, %esi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    lantern_node_work
    movq    $NODE_LC_ID, NodeAction_state_c(%rax)
    mov     NodeBlock_slot(%r12), %rax      # epoch_transition, execution_optimistic
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, %r13
    mov     Node_event_slot(%rbx), %rax
    xor     %edx, %edx
    div     %rcx
    xor     %r8d, %r8d
    cmp     %rax, %r13
    seta    %r8b
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%r12)
    sete    %al
    lea     (%r8,%rax,2), %r13
    mov     $API_TOPIC_CHAIN_REORG, %edi    # chain_reorg, before the head event: the new head's chain lacks the old head
    call    lantern_node_api_subscribed
    test    %rax, %rax
    jz      12f
    cmpq    $0, NodeBlock_state_id(%r12)
    je      12f
    lea     Node_event_head(%rbx), %rdi
    mov     %r12, %rsi
    call    lantern_node_api_reorg
    cmp     $-1, %rax
    je      12f
    mov     NodeBlock_data_id(%rdx), %rcx
    test    %rcx, %rcx
    jz      12f
    mov     %rax, %r9
    shl     $16, %r9
    mov     %r13, %rax
    and     $2, %eax
    shl     $8, %rax
    or      %rax, %r9
    add     $API_TOPIC_CHAIN_REORG, %r9
    mov     $NODE_WORK_API_EVENT, %edi
    mov     NodeBlock_state_id(%r12), %rsi
    xor     %edx, %edx
    xor     %r8d, %r8d
    call    lantern_node_work
12: mov     NodeBlock_slot(%r12), %rax
    mov     %rax, Node_event_slot(%rbx)
    lea     Node_event_head(%rbx), %rax
    COPY32  %rax, %r12
    mov     NodeBlock_state_id(%r12), %rdi  # the pool's checks at the new head
    call    lantern_node_pool_checks
    mov     $API_TOPIC_HEAD, %edi
    call    lantern_node_api_subscribed
    test    %rax, %rax
    jz      13f
    mov     NodeBlock_state_id(%r12), %rsi
    test    %rsi, %rsi
    jz      5f
    mov     $NODE_WORK_API_EVENT, %edi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    mov     %r13, %r9
    shl     $8, %r9                         # API_TOPIC_HEAD is 0
    call    lantern_node_work
13: mov     $API_TOPIC_HEAD_V2, %edi        # head_v2: the same values, its own text
    call    lantern_node_api_subscribed
    test    %rax, %rax
    jz      5f
    mov     NodeBlock_state_id(%r12), %rsi
    test    %rsi, %rsi
    jz      5f
    mov     $NODE_WORK_API_EVENT, %edi
    xor     %edx, %edx
    xor     %ecx, %ecx
    xor     %r8d, %r8d
    mov     %r13, %r9
    shl     $8, %r9
    add     $API_TOPIC_HEAD_V2, %r9
    call    lantern_node_work
5:  mov     Store_finalized_checkpoint(%rbp), %rax
    cmp     Node_event_epoch(%rbx), %rax
    jbe     9f
    mov     %rax, Node_event_epoch(%rbx)
    mov     $API_TOPIC_FINALIZED_CHECKPOINT, %edi
    call    lantern_node_api_subscribed
    test    %rax, %rax
    jz      9f
    lea     (Store_finalized_checkpoint + 8)(%rbp), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      9f
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rdx)
    sete    %al
    shl     $9, %rax
    mov     Store_finalized_checkpoint(%rbp), %r9
    shl     $16, %r9
    or      %rax, %r9
    add     $API_TOPIC_FINALIZED_CHECKPOINT, %r9
    mov     NodeBlock_data_id(%rdx), %rcx   # the block's bytes, else its post-state
    mov     NodeBlock_state_id(%rdx), %rsi
    test    %rcx, %rcx
    jz      6f
    xor     %esi, %esi
6:  mov     %rcx, %rax
    or      %rsi, %rax
    jz      9f
    mov     $NODE_WORK_API_EVENT, %edi
    xor     %edx, %edx
    xor     %r8d, %r8d
    call    lantern_node_work
9:  LEAVE 0
END_FUNCTION lantern_node_api_head_events

/* NODE_EV_WORK_DONE rdi of a NODE_WORK_API_EVENT: LANTERN_VALID, its text to the entries of its topic. */
LOCAL_FUNCTION lantern_node_api_event_done
    FRAME 0
    cmpq    $0, NodeEvent_result(%rdi)
    jne     9f
    movzbl  NodeAction_arg(%rdi), %esi
    add     $NodeEvent_chunk, %rdi
    call    lantern_node_api_events
9:  UNFRAME 0
END_FUNCTION lantern_node_api_event_done

/* NODE_EV_API_CLOSED of the connection rdi: its stream ends, or with a chunk or work queued takes API_STREAM_GONE. Locals: the entry. */
LOCAL_FUNCTION lantern_node_api_closed
    FRAME 16
    call    lantern_node_api_find
    cmp     $-1, %rax
    je      9f
    testq   $API_STREAM_BUSY, NodeApi_flags(%rdx)
    jz      1f
    orq     $API_STREAM_GONE, NodeApi_flags(%rdx)
    jmp     9f
1:  mov     %rdx, (%rsp)
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rdx)  # a produceBlockV3: its draft and engine result go too
    jne     3f
    mov     %rdx, %rdi
    call    lantern_node_produce_release
2:  mov     (%rsp), %rdi
    call    lantern_node_api_end
9:  UNFRAME 16
3:  cmpq    $API_OP_PUBLISH_BLOCK_V2, NodeApi_op(%rdx)  # a publishBlockV2: its ids; in NODE_PUBLISH_IMPORT it goes on unanswered
    jne     2b
    cmpq    $NODE_PUBLISH_IMPORT, NodeApi_member(%rdx)
    jne     4f
    orq     $API_STREAM_GONE, NodeApi_flags(%rdx)
    UNFRAME 16
4:  mov     %rdx, %rdi
    call    lantern_node_publish_end
    UNFRAME 16
END_FUNCTION lantern_node_api_closed

/*
 * (connection rdi, route rsi, flags rdx, view rcx) -> rax: a stream of getBlockV2, getStateV2 or a validator operation of
 * the lookup in the view (node.md, NODE_EV_API): 0 once it started, else the status of the error to
 * answer. flags: API_STREAM_CLOSE and API_STREAM_HTTP10. rbx the node, r15 the actions. r12 the
 * data, S7 the route, S8 the view, S9 the connection, S10 the flags. Locals: L the entry's index,
 * L+8 the entry.
 */
LOCAL_FUNCTION lantern_node_api_stream
    ENTER 32
    movq    $0, (L + 16)(%rsp)
    mov     %rdi, S9(%rsp)
    mov     %rsi, S7(%rsp)
    mov     %rdx, S10(%rsp)
    mov     %rcx, S8(%rsp)
    cmpq    $API_TYPE_SSZ, ApiRoute_response(%rsi)  # SSZ, else JSON; the values of the JSON
    jne     1f
    orq     $API_STREAM_SSZ, S10(%rsp)
1:  cmpq    $0, ApiView_is_optimistic(%rcx)
    je      2f
    orq     $API_STREAM_OPTIMISTIC, S10(%rsp)
2:  cmpq    $0, ApiView_head_finalized(%rcx)
    je      3f
    orq     $API_STREAM_FINALIZED, S10(%rsp)
3:  cmpq    $API_OP_GET_STATE_V2, ApiRoute_op(%rsi)
    je      5f
    cmpq    $API_OP_GET_BLOCK_V2, ApiRoute_op(%rsi)
    je      4f
    cmpq    $API_OP_GET_BLOCK_ATTESTATIONS_V2, ApiRoute_op(%rsi)
    je      4f
    cmpq    $API_OP_GET_BLINDED_BLOCK, ApiRoute_op(%rsi)
    je      4f
    mov     ApiView_look_data(%rcx), %r12   # a validator stream: its ids, and its state
    test    %r12, %r12
    jz      31f
    orq     $API_STREAM_OWN, S10(%rsp)
31: cmpq    $0, ApiView_look_copy(%rcx)
    je      32f
    orq     $API_STREAM_OWN_STATE, S10(%rsp)
32: mov     ApiView_look_state(%rcx), %rax
    mov     %rax, (L + 16)(%rsp)
    cmpq    $API_OP_GET_EPOCH_COMMITTEES, ApiRoute_op(%rsi)   # getEpochCommittees: its epoch, else 400 and no stream
    jne     34f
    mov     %rsi, %rdi
    mov     %rcx, %rsi
    call    lantern_node_api_committees_check
    mov     %rax, (L + 24)(%rsp)
    cmp     $-1, %rax
    jne     6f
    jmp     331f
34: mov     ApiRoute_op(%rsi), %rax         # the pending lists: 400 for a state before electra, and no stream
    sub     $API_OP_GET_PENDING_CONSOLIDATIONS, %rax
    cmp     $2, %rax
    ja      6f
    mov     ApiView_head_slot(%rcx), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     S7(%rsp), %rsi
    mov     S8(%rsp), %rcx
    cmp     $FORK_ELECTRA, %rax
    jae     6f
331: mov    S8(%rsp), %rcx
    cmpq    $0, ApiView_look_copy(%rcx)
    je      33f
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     ApiView_look_state(%rcx), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
33: mov     $400, %eax
    LEAVE 32
4:  mov     ApiView_look_data(%rcx), %r12   # getBlockV2: the block's bytes
    test    %r12, %r12
    jz      80f
    jmp     6f
5:  call    lantern_node_new_id                     # getStateV2: the state's SSZ bytes, as a new id the stream owns
    mov     %rax, %r12
    mov     $NODE_ACT_STATE_BYTES, %edi
    mov     $NODE_ACT_STATE_BYTES_SIZE, %esi
    call    lantern_node_act
    mov     S8(%rsp), %rcx
    mov     ApiView_look_state(%rcx), %rdx
    mov     %rdx, 16(%rax)
    mov     %r12, 24(%rax)
    orq     $API_STREAM_OWN, S10(%rsp)
    cmpq    $0, ApiView_look_copy(%rcx)     # a copy goes after its bytes
    je      6f
    mov     $NODE_ACT_STATE_FREE, %edi
    mov     ApiView_look_state(%rcx), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
6:  call    lantern_node_api_new                    # the entry
    mov     %rax, L(%rsp)
    mov     %rdx, (L + 8)(%rsp)
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     S8(%rsp), %rax
    mov     ApiView_head_slot(%rax), %rdi
    mov     (L + 8)(%rsp), %rdx
    mov     %rdi, NodeApi_slot(%rdx)
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     (L + 8)(%rsp), %rdx
    mov     %rax, NodeApi_fork(%rdx)
    mov     S9(%rsp), %rax
    mov     %rax, NodeApi_connection(%rdx)
    mov     S7(%rsp), %rax
    mov     ApiRoute_op(%rax), %rax
    mov     %rax, NodeApi_op(%rdx)
    mov     S10(%rsp), %rax
    mov     %rax, NodeApi_flags(%rdx)
    mov     %r12, NodeApi_data(%rdx)
    mov     (L + 16)(%rsp), %rax            # a validator stream: its state and status bits
    mov     %rax, NodeApi_state(%rdx)
    mov     S7(%rsp), %rax
    mov     ApiRoute_statuses(%rax), %rax
    mov     %rax, NodeApi_statuses(%rdx)
    mov     S7(%rsp), %rsi                  # getEpochCommittees: its cursor
    cmpq    $API_OP_GET_EPOCH_COMMITTEES, ApiRoute_op(%rsi)
    jne     7f
    mov     %rdx, %rdi
    mov     (L + 24)(%rsp), %rdx
    call    lantern_node_api_committees_cursor
    mov     (L + 8)(%rsp), %rdx
7:  mov     L(%rsp), %rax
    call    lantern_node_api_chunk_work
    xor     %eax, %eax
    LEAVE 32
80: mov     $404, %eax
    LEAVE 32
END_FUNCTION lantern_node_api_stream

/*
 * The NODE_EV_WORK_DONE rdi of a NODE_WORK_API_CHUNK (node.md, lantern_node_step). rbx the node,
 * r15 the actions. r12 the event, r13 the entry, r14 the action, S7 the flags.
 */
LOCAL_FUNCTION lantern_node_api_chunk_done
    ENTER 0
    mov     %rdi, %r12
    mov     NodeAction_arg(%r12), %rax
    PART    %r13, %rcx, %rbx, Node_api
    cmp     %rcx, %rax
    jae     99f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %r13
    mov     NodeApi_connection(%r13), %rax
    test    %rax, %rax
    jz      99f
    cmp     NodeAction_target(%r12), %rax
    jne     99f
    andq    $~API_STREAM_BUSY, NodeApi_flags(%r13)
    mov     NodeApi_flags(%r13), %rax
    mov     %rax, S7(%rsp)
    test    $API_STREAM_GONE, %eax
    jnz     90f                             # API_STREAM_GONE: the stream ends
    cmpq    $0, NodeEvent_result(%r12)
    jne     50f
    mov     NodeEvent_api(%r12), %rax       # valid: the entry takes sent, flags and cursor
    mov     %rax, NodeApi_sent(%r13)
    mov     (NodeEvent_api + 8)(%r12), %rax
    and     $~(API_STREAM_BUSY | API_STREAM_OWN), %rax
    mov     S7(%rsp), %rcx
    and     $API_STREAM_OWN, %ecx
    or      %rcx, %rax
    mov     %rax, S7(%rsp)
    mov     %rax, NodeApi_flags(%r13)
    lea     NodeApi_cursor(%r13), %rdi
    lea     (NodeEvent_api + 16)(%r12), %rsi
    mov     $JSON_CURSOR_SIZE, %edx
    call    lantern_copy
    testq   $API_STREAM_ITEM_DONE, S7(%rsp) # API_STREAM_ITEM_DONE: the pool stream's next entry, getBlockHeaders' next item
    jz      1f
    andq    $~API_STREAM_ITEM_DONE, NodeApi_flags(%r13)
    mov     %r13, %rdi
    cmpq    $API_OP_GET_BLOCK_HEADERS, NodeApi_op(%r13)
    jne     2f
    mov     NodeApi_slot(%r13), %rsi
    inc     %rsi
    call    lantern_node_headers_next
    jmp     3f
2:  cmpq    $API_OP_GET_BLOBS, NodeApi_op(%r13)   # the blob stream: its next sidecar or cell
    jne     21f
    call    lantern_node_blob_advance
    jmp     3f
21: cmpq    $API_OP_GET_BLOB_SIDECARS, NodeApi_op(%r13)    # a sidecar stream: its sidecar from member + 1 on
    je      4f
    cmpq    $API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS, NodeApi_op(%r13)
    jne     5f
4:  mov     NodeApi_member(%r13), %rsi
    inc     %rsi
    call    lantern_node_sidecar_next
    jmp     3f
5:  call    lantern_node_api_pool_advance
3:  mov     NodeApi_flags(%r13), %rax
    mov     %rax, S7(%rsp)
1:  testq   $API_STREAM_FOLD, S7(%rsp)      # API_STREAM_FOLD: no send, and the next chunk at once
    jz      11f
    testq   $API_STREAM_DONE, S7(%rsp)      # the error that ends it goes
    jnz     11f
    cmpq    $0, NodeApi_data(%r13)
    jne     12f                             # a fold
    cmpq    $0, (NodeEvent_api_bytes + 16)(%r12)
    jne     14f                             # the Attestation's bytes
    cmpq    $0, (NodeApi_cursor + 32)(%r13) # the fold's end: optimistic for a NOT_VALIDATED block
    je      12f
    lea     (NodeApi_cursor + 48 + 16)(%r13), %rdi  # the aggregate's data.beacon_block_root, a contribution's at byte 0
    cmpq    $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, NodeApi_op(%r13)
    jne     15f
    lea     NodeApi_cursor(%r13), %rdi
15: call    lantern_node_store_find
    cmp     $-1, %rax
    je      12f
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, BlockNode_payload_status(%rdx)
    jne     12f
    orq     $API_STREAM_OPTIMISTIC, NodeApi_flags(%r13)
    jmp     12f
14: lea     NodeEvent_api_bytes(%r12), %rdi # they become the stream's own data; the answer from sent 0
    call    lantern_node_put
    mov     %rax, NodeApi_data(%r13)
    mov     NodeApi_flags(%r13), %rax
    and     $~API_STREAM_FOLD, %rax
    or      $API_STREAM_OWN, %rax
    mov     %rax, NodeApi_flags(%r13)
    movq    $0, NodeApi_sent(%r13)
    lea     NodeApi_cursor(%r13), %rdi
    mov     $JSON_CURSOR_SIZE, %esi
    call    lantern_zero
12: mov     NodeAction_arg(%r12), %rax
    mov     %r13, %rdx
    call    lantern_node_api_chunk_work
    jmp     99f
11: mov     (NodeEvent_api_bytes + 16)(%r12), %rsi  # the chunk in a SEND
    add     $(56 + 7), %rsi
    and     $~7, %rsi
    mov     $NODE_ACT_API_SEND, %edi
    call    lantern_node_act
    mov     %rax, %r14
    mov     NodeApi_connection(%r13), %rax
    mov     %rax, 16(%r14)
    mov     S7(%rsp), %rax                  # last: API_STREAM_DONE
    shr     $10, %rax
    and     $1, %eax
    mov     %rax, 24(%r14)
    mov     (%r14), %rax
    sub     $32, %rax
    mov     %rax, 32(%r14)
    movq    $24, 40(%r14)
    mov     (NodeEvent_api_bytes + 16)(%r12), %rdx
    mov     %rdx, 48(%r14)
    lea     56(%r14), %rdi
    mov     (NodeEvent_api_bytes + 8)(%r12), %rsi
    lea     NodeEvent_api_bytes(%r12,%rsi), %rsi
    call    lantern_copy
    mov     48(%r14), %rcx                  # zero bytes to the size
    lea     56(%r14,%rcx), %rdi
    mov     (%r14), %rsi
    sub     $56, %rsi
    sub     %rcx, %rsi
    call    lantern_zero
    testq   $API_STREAM_DONE, S7(%rsp)
    jz      99f                             # not the last: the next chunk at the next API_SENT
    testq   $API_STREAM_CLOSE, S7(%rsp)
    jz      90f
    jmp     60f
50: testq   $API_STREAM_STARTED, S7(%rsp)   # another result: before API_STREAM_STARTED the error 500, after it a CLOSE
    jnz     60f
    mov     NodeApi_connection(%r13), %rdi
    xor     %esi, %esi
    mov     $500, %edx
    mov     $API_BODY_ERROR, %ecx
    mov     S7(%rsp), %r8
    and     $API_R_CLOSE, %r8d              # API_STREAM_CLOSE is API_R_CLOSE; HTTP/1.0 kept open says so
    jnz     51f
    testq   $API_STREAM_HTTP10, S7(%rsp)
    jz      51f
    mov     $API_R_KEEP, %r8d
51: call    lantern_node_api_send
    jmp     90f
60: mov     $NODE_ACT_API_CLOSE, %edi
    mov     $NODE_ACT_API_CLOSE_SIZE, %esi
    call    lantern_node_act
    mov     NodeApi_connection(%r13), %rcx
    mov     %rcx, 16(%rax)
90: mov     %r13, %rdi
    call    lantern_node_api_end
99: LEAVE 0
END_FUNCTION lantern_node_api_chunk_done

/* The name of the fork rdi joins the response. */
LOCAL_FUNCTION lantern_api_fork_name
    UNWIND_END_PROLOGUE
    lea     api_forks(%rip), %rax
    shl     $4, %rdi
    add     %rax, %rdi
    movzbl  (%rdi), %esi
    inc     %rdi
    jmp     lantern_api_put
END_FUNCTION lantern_api_fork_name

/*
 * The head of a streamed answer (beacon-api.md, Common rules) for the flags at NodeEvent_api + 8
 * of the event rbp and the fork of the entry rbx: with Content-Length rdi, or for rdi = 2^64 - 1
 * Transfer-Encoding: chunked when API_STREAM_CHUNKED is set, else neither. Locals: rdi.
 */
LOCAL_FUNCTION lantern_api_stream_head
    FRAME 16
    mov     %rdi, (%rsp)
    API_LIT api_ok
    testq   $API_STREAM_SSZ, (NodeEvent_api + 8)(%rbp)
    jz      1f
    API_LIT api_octet
    jmp     2f
1:  API_LIT api_type
2:  cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rbx)
    je      23f
    cmpq    $API_OP_GET_BLOCK_V2, NodeApi_op(%rbx)  # Eth-Consensus-Version: of getBlockV2 and getStateV2
    je      21f
    cmpq    $API_OP_GET_BLOCK_ATTESTATIONS_V2, NodeApi_op(%rbx)
    je      21f
    cmpq    $API_OP_GET_BLINDED_BLOCK, NodeApi_op(%rbx)
    je      21f
    cmpq    $API_OP_GET_STATE_V2, NodeApi_op(%rbx)
    je      21f
    cmpq    $API_OP_GET_POOL_ATTESTER_SLASHINGS_V2, NodeApi_op(%rbx)
    je      21f
    cmpq    $API_OP_GET_POOL_ATTESTATIONS_V2, NodeApi_op(%rbx)
    je      21f
    cmpq    $API_OP_GET_AGGREGATED_ATTESTATION_V2, NodeApi_op(%rbx)
    je      21f
    cmpq    $API_OP_GET_BLOB_SIDECARS, NodeApi_op(%rbx)
    je      21f
    cmpq    $API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS, NodeApi_op(%rbx)
    je      21f
    mov     NodeApi_op(%rbx), %rax          # and of the pending lists
    sub     $API_OP_GET_PENDING_CONSOLIDATIONS, %rax
    cmp     $2, %rax
    ja      22f
21: API_LIT api_version
    mov     NodeApi_fork(%rbx), %rdi
    call    lantern_api_fork_name
    API_LIT api_crlf
    jmp     22f
    /* produceBlockV3: and its three headers */
23: API_LIT api_version
    mov     NodeApi_fork(%rbx), %rdi
    call    lantern_api_fork_name
    API_LIT api_crlf
    testq   $API_STREAM_PRODUCE_BLINDED, NodeApi_flags(%rbx)  # blinded with API_STREAM_PRODUCE_BLINDED
    jnz     231f
    API_LIT api_h_blinded
    jmp     232f
231: API_LIT api_h_blinded_true
232: lea    NodeApi_root(%rbx), %rdi
    call    lantern_api_dec256
    API_LIT api_h_block_value
    mov     NodeApi_filter_slot(%rbx), %rdi
    call    lantern_api_wei
    API_LIT api_crlf
22: mov     (%rsp), %rdi
    cmp     $-1, %rdi
    je      3f
    API_LIT api_length
    mov     (%rsp), %rdi
    call    lantern_api_dec
    API_LIT api_crlf
    jmp     4f
3:  testq   $API_STREAM_CHUNKED, (NodeEvent_api + 8)(%rbp)
    jz      4f
    API_LIT api_chunked
4:  testq   $API_STREAM_CLOSE, (NodeEvent_api + 8)(%rbp)
    jz      5f
    API_LIT api_close
    jmp     6f
5:  testq   $API_STREAM_HTTP10, (NodeEvent_api + 8)(%rbp)
    jz      6f
    API_LIT api_keep
6:  API_LIT api_crlf
    UNFRAME 16
END_FUNCTION lantern_api_stream_head

/* The 4 lower case hex digits of rdi at rsi. Uses rax, rcx, rdx, rdi. */
LOCAL_FUNCTION lantern_api_hex4
    UNWIND_END_PROLOGUE
    lea     api_hex(%rip), %rax
    mov     $3, %ecx
1:  mov     %edi, %edx
    and     $15, %edx
    movzbl  (%rax,%rdx), %edx
    mov     %dl, (%rsi,%rcx)
    shr     $4, %edi
    dec     %ecx
    jns     1b
    ret
END_FUNCTION lantern_api_hex4

/*
 * The JSON of the entry rbx's SSZ bytes rdi from the cursor at NodeEvent_api + 16 of the event
 * rbp, at the writer's cursor r12 up to r14 less a byte, through the event's ByteList at
 * NodeEvent_api_bytes; then } once it is whole. rax = 1 when whole, 0 when more is to come, 2
 * for bytes that are no encoding.
 */
LOCAL_FUNCTION lantern_api_stream_json
    FRAME 0
    mov     NodeApi_op(%rbx), %rax          # a pool stream: its entries
    cmp     $API_OP_GET_POOL_VOLUNTARY_EXITS, %rax
    je      4f
    cmp     $API_OP_GET_POOL_PROPOSER_SLASHINGS, %rax
    je      4f
    cmp     $API_OP_GET_POOL_ATTESTER_SLASHINGS_V2, %rax
    je      4f
    cmp     $API_OP_GET_POOL_ATTESTATIONS_V2, %rax
    je      4f
    cmp     $API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES, %rax
    jne     3f
4:  call    lantern_api_pool_json
    UNFRAME 0
3:  cmpq    $API_OP_GET_BLOCK_HEADERS, NodeApi_op(%rbx)
    jne     32f
    call    lantern_api_headers_json
    UNFRAME 0
32: cmpq    $API_OP_GET_BLOBS, NodeApi_op(%rbx)   # the blob stream: the sidecar rdi, the versioned hashes rsi
    jne     35f
    call    lantern_api_blob_body
    UNFRAME 0
35: cmpq    $API_OP_GET_BLOB_SIDECARS, NodeApi_op(%rbx)
    je      33f
    cmpq    $API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS, NodeApi_op(%rbx)
    jne     34f
33: call    lantern_api_sidecar_body
    UNFRAME 0
34: mov     NodeApi_op(%rbx), %rax          # the pending streams: their items, of the state rdi
    sub     $API_OP_GET_PENDING_CONSOLIDATIONS, %rax
    cmp     $2, %rax
    ja      31f
    call    lantern_api_pending_json
    UNFRAME 0
31: cmpq    $API_OP_GET_BLOCK_V2, NodeApi_op(%rbx)  # the validator streams: their items, of the state rdi
    je      1f
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rbx)
    je      1f
    cmpq    $API_OP_GET_AGGREGATED_ATTESTATION_V2, NodeApi_op(%rbx)
    je      1f
    cmpq    $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, NodeApi_op(%rbx)
    je      1f
    cmpq    $API_OP_GET_BLOCK_ATTESTATIONS_V2, NodeApi_op(%rbx)
    je      1f
    cmpq    $API_OP_GET_BLINDED_BLOCK, NodeApi_op(%rbx)
    je      1f
    cmpq    $API_OP_GET_STATE_V2, NodeApi_op(%rbx)
    je      1f
    cmpq    $API_OP_GET_ATTESTATIONS_REWARDS, NodeApi_op(%rbx)
    je      35f
    cmpq    $API_OP_GET_EPOCH_COMMITTEES, NodeApi_op(%rbx)
    je      2f
    call    lantern_api_validators_json
    UNFRAME 0
35: call    lantern_api_rewards_json
    UNFRAME 0
2:  call    lantern_api_committees_json
    UNFRAME 0
1:  lea     NodeEvent_api_bytes(%rbp), %rsi # the ByteList: its room to r14 - 1, its bytes to r12
    lea     -1(%r14), %rax
    sub     %rsi, %rax
    mov     %rax, (%rsi)
    movq    $24, 8(%rsi)
    mov     %r12, %rax
    sub     %rsi, %rax
    sub     $24, %rax
    mov     %rax, 16(%rsi)
    mov     %rdi, %rsi
    xor     %edi, %edi                      # NODE_JSON_STATE, else NODE_JSON_BLOCK; NODE_JSON_ATTESTATIONS of a block's
    cmpq    $API_OP_GET_STATE_V2, NodeApi_op(%rbx)
    sete    %dil
    cmpq    $API_OP_GET_BLOCK_ATTESTATIONS_V2, NodeApi_op(%rbx)
    jne     121f
    mov     $NODE_JSON_ATTESTATIONS, %edi
121: cmpq   $API_OP_GET_BLINDED_BLOCK, NodeApi_op(%rbx)
    jne     122f
    mov     $NODE_JSON_BLINDED_BLOCK, %edi
122: cmpq   $API_OP_GET_AGGREGATED_ATTESTATION_V2, NodeApi_op(%rbx)
    jne     123f
    mov     $NODE_JSON_ATTESTATION, %edi
123: cmpq   $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, NodeApi_op(%rbx)
    jne     124f
    mov     $NODE_JSON_SYNC_CONTRIBUTION, %edi
124: cmpq   $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rbx)  # produceBlockV3: the block, from deneb its BlockContents
    jne     125f
    mov     $NODE_JSON_BEACON_BLOCK, %edi
    cmpq    $FORK_DENEB, NodeApi_fork(%rbx)
    jb      1241f
    mov     $NODE_JSON_BLOCK_CONTENTS, %edi
1241: testq $API_STREAM_PRODUCE_BLINDED, NodeApi_flags(%rbx)  # a blinded block: its BlindedBeaconBlock
    jz      125f
    mov     $NODE_JSON_BLINDED_BEACON_BLOCK, %edi
125:
    lea     (NodeEvent_api + 16)(%rbp), %rdx
    lea     NodeEvent_api_bytes(%rbp), %rcx
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_json
    mov     (NodeEvent_api_bytes + 16)(%rbp), %r12
    lea     (NodeEvent_api_bytes + 24)(%rbp,%r12), %r12
    cmp     $LANTERN_JSON_MORE, %rax
    je      8f
    test    %rax, %rax
    jnz     7f
    API_LIT api_end1
    mov     $1, %eax
    UNFRAME 0
7:  mov     $2, %eax
    UNFRAME 0
8:  xor     %eax, %eax
    UNFRAME 0
END_FUNCTION lantern_api_stream_json

/*
 * (node rdi, work rsi, data rdx, scratch rcx, event r8, room r9, state_a r10) -> rax: a
 * NODE_WORK_API_CHUNK of lantern_node_run (node.md): the next chunk of the NodeApi entry at the
 * work's arg, from the SSZ bytes in data, or for a validator stream from state_a and the ids in
 * data, at NodeEvent_api of the event, whose buffer has room bytes. rbx the entry, rbp the event;
 * the writer's r12-r15 (lantern_api_put). Locals: L the end of the chunk's room, L+8 the SSZ bytes, L+16
 * their count, L+24 the body's start, L+32 the head's bytes, L+40 data (a validator stream's state
 * once its selection is made), L+48 state_a, L+56 1 for a validator stream, L+64 the scratch.
 */
LOCAL_FUNCTION lantern_node_api_chunk_run
    ENTER 80
    mov     %rdx, (L + 40)(%rsp)
    mov     %r10, (L + 48)(%rsp)
    mov     %rcx, (L + 64)(%rsp)
    mov     %rdi, (L + 72)(%rsp)
    mov     %r8, %rbp
    mov     NodeAction_arg(%rsi), %rax      # the entry
    PART    %rbx, %rcx, %rdi, Node_api
    cmp     %rcx, %rax
    jae     98f
    imul    $NodeApi__mem, %rax, %rax
    add     %rax, %rbx
    cmpq    $0, NodeApi_connection(%rbx)
    je      98f
    mov     NodeApi_op(%rbx), %rax
    cmp     $API_OP_GET_BLOCK_V2, %rax
    je      1f
    cmp     $API_OP_GET_BLOCK_ATTESTATIONS_V2, %rax
    je      1f
    cmp     $API_OP_GET_BLINDED_BLOCK, %rax
    je      1f
    cmp     $API_OP_PRODUCE_BLOCK_V3, %rax
    je      1f
    cmp     $API_OP_GET_STATE_V2, %rax
    je      1f
    mov     $3, %ecx                        # a pool stream (3): data 0 at its end
    cmp     $API_OP_GET_POOL_VOLUNTARY_EXITS, %rax
    je      103f
    cmp     $API_OP_GET_POOL_PROPOSER_SLASHINGS, %rax
    je      103f
    cmp     $API_OP_GET_POOL_ATTESTER_SLASHINGS_V2, %rax
    je      103f
    cmp     $API_OP_GET_POOL_ATTESTATIONS_V2, %rax
    je      103f
    cmp     $API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES, %rax
    je      103f
    mov     $7, %ecx                        # getAggregatedAttestationV2 and produceSyncCommitteeContribution (7): their fold, then their answer
    cmp     $API_OP_GET_AGGREGATED_ATTESTATION_V2, %rax
    je      103f
    cmp     $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, %rax
    je      103f
    mov     $6, %ecx                        # a sidecar stream (6), and the blob stream: data 0 at its end
    cmp     $API_OP_GET_BLOB_SIDECARS, %rax
    je      103f
    cmp     $API_OP_GET_BLOBS, %rax
    je      103f
    cmp     $API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS, %rax
    je      103f
    mov     $5, %ecx                        # getBlockHeaders (5): an item of data or state, none at its end
    cmp     $API_OP_GET_BLOCK_HEADERS, %rax
    je      103f
    mov     $4, %ecx                        # a pending stream (4): a state
    mov     %rax, %r8
    sub     $API_OP_GET_PENDING_CONSOLIDATIONS, %r8
    cmp     $2, %r8
    ja      104f
    cmpq    $0, (L + 48)(%rsp)
    je      98f
    jmp     103f
104: cmp    $API_OP_GET_ATTESTATIONS_REWARDS, %rax  # getAttestationsRewards: as a validator stream (1), of a state
    jne     106f
    cmpq    $0, (L + 48)(%rsp)
    je      98f
    mov     $1, %ecx
    jmp     103f
106: cmp    $API_OP_GET_STATE_VALIDATOR, %rax       # a validator stream: a state
    je      98f
    sub     $API_OP_GET_STATE_VALIDATORS, %rax
    cmp     $(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS), %rax
    ja      98f
    cmpq    $0, (L + 48)(%rsp)
    je      98f
    mov     $1, %ecx                        # a validator stream (1) or getEpochCommittees (2)
    cmp     $(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS), %rax
    jne     103f
    mov     $2, %ecx
103: mov    %rcx, (L + 56)(%rsp)
    jmp     101f
1:  test    %rdx, %rdx
    jz      98f
    movq    $0, (L + 56)(%rsp)
101: mov    %r9, %rax                       # the chunk's room: at most NODE_API_CHUNK
    sub     $(NodeEvent_api_bytes + 24), %rax
    jb      97f
    and     $~7, %rax
    cmp     $NODE_API_CHUNK, %rax
    jbe     2f
    mov     $NODE_API_CHUNK, %eax
2:  mov     $NODE_API_FIRST_ROOM, %ecx
    testq   $API_STREAM_STARTED, NodeApi_flags(%rbx)
    jz      3f
    mov     (L + 56)(%rsp), %r8             # a validator stream: an item in every chunk
    test    %r8, %r8
    jz      105f
    cmp     $3, %r8
    je      105f
    cmp     $7, %r8
    jne     3f
105: mov    $64, %ecx
3:  cmp     %rcx, %rax
    jb      97f
    lea     (NodeEvent_api_bytes + 24)(%rbp,%rax), %rax
    mov     %rax, L(%rsp)
    cmpq    $0, (L + 56)(%rsp)
    je      102f
    cmpq    $3, (L + 56)(%rsp)
    je      5f
    cmpq    $5, (L + 56)(%rsp)
    je      5f
    cmpq    $6, (L + 56)(%rsp)
    je      5f
    cmpq    $7, (L + 56)(%rsp)
    je      5f
    mov     (L + 48)(%rsp), %rax            # the state at the entry's slot
    mov     NODE_STATE_SLOT(%rax), %rax
    cmp     NodeApi_slot(%rbx), %rax
    jne     95f
    jmp     5f
102: mov    8(%rdx), %rax                   # the SSZ bytes
    add     %rdx, %rax
    mov     %rax, (L + 8)(%rsp)
    mov     16(%rdx), %rax
    mov     %rax, (L + 16)(%rsp)
    mov     $40, %ecx                       # their slot: a state's at byte 40, a signed block's at 100
    cmpq    $API_OP_GET_STATE_V2, NodeApi_op(%rbx)
    je      4f
    mov     $100, %ecx
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rbx)  # produceBlockV3: a block's at 0, from deneb at the BlockContents' offset of its block
    jne     4f
    xor     %ecx, %ecx
    testq   $API_STREAM_PRODUCE_BLINDED, NodeApi_flags(%rbx)  # a blinded block's at 0
    jnz     4f
    cmpq    $FORK_DENEB, NodeApi_fork(%rbx)
    jb      4f
    cmp     $4, %rax
    jb      96f
    mov     (L + 8)(%rsp), %rsi
    mov     (%rsi), %ecx
4:  lea     8(%rcx), %rsi
    cmp     %rsi, %rax
    jb      96f
    mov     (L + 8)(%rsp), %rsi
    mov     (%rsi,%rcx), %rsi
    cmp     NodeApi_slot(%rbx), %rsi
    jne     96f
    cmpq    $API_OP_GET_BLINDED_BLOCK, NodeApi_op(%rbx)
    je      52f
    cmpq    $API_OP_GET_BLOCK_ATTESTATIONS_V2, NodeApi_op(%rbx)  # getBlockAttestationsV2: the body's attestations, a ByteList at the end of scratch
    jne     5f
    mov     (L + 8)(%rsp), %rsi
    mov     (L + 16)(%rsp), %rdi
    mov     (%rsi), %eax                    # the message
    lea     84(%rax), %rcx
    cmp     %rdi, %rcx
    ja      96f
    mov     80(%rsi,%rax), %ecx             # its body
    add     %rcx, %rax
    lea     216(%rax), %rcx
    cmp     %rdi, %rcx
    ja      96f
    mov     208(%rsi,%rax), %ecx            # the list: from attestations to deposits
    mov     212(%rsi,%rax), %edx
    cmp     %rdx, %rcx
    ja      96f
    add     %rax, %rdx
    cmp     %rdi, %rdx
    ja      96f
    add     %rax, %rcx
    sub     %rcx, %rdx
    mov     (L + 64)(%rsp), %rax            # its bytes copied into a ByteList at the end of scratch
    mov     (%rax), %rdi
    lea     (24 + 7)(%rdx), %r8
    and     $~7, %r8
    cmp     %r8, %rdi
    jb      97f
    sub     %r8, %rdi
    add     %rdi, %rax
    mov     %r8, (%rax)
    movq    $24, 8(%rax)
    mov     %rdx, 16(%rax)
    mov     %rax, (L + 40)(%rsp)
    lea     24(%rax), %rdi
    add     %rcx, %rsi
    call    lantern_copy
    jmp     5f
52: mov     (L + 64)(%rsp), %rsi            # getBlindedBlock: lantern_node_blinded_block into a ByteList at the end of scratch, then its bytes
    mov     (%rsi), %rcx
    mov     (L + 16)(%rsp), %rax
    lea     (24 + 1024 + 7)(%rax), %rax
    and     $~7, %rax
    lea     64(%rax), %rdx
    cmp     %rdx, %rcx
    jb      97f
    sub     %rax, %rcx
    mov     %rcx, (%rsi)
    lea     (%rsi,%rcx), %rdx
    mov     %rax, (%rdx)
    mov     (L + 40)(%rsp), %rdi
    mov     %rdx, (L + 40)(%rsp)
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_blinded_block
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      97f
    test    %rax, %rax
    jnz     96f
    mov     (L + 40)(%rsp), %rax
    mov     8(%rax), %rcx
    add     %rax, %rcx
    mov     %rcx, (L + 8)(%rsp)
    mov     16(%rax), %rcx
    mov     %rcx, (L + 16)(%rsp)
5:  mov     NodeApi_sent(%rbx), %rax        # the entry's sent, flags and cursor go on in the event
    mov     %rax, NodeEvent_api(%rbp)
    mov     NodeApi_flags(%rbx), %rax
    mov     %rax, (NodeEvent_api + 8)(%rbp)
    lea     (NodeEvent_api + 16)(%rbp), %rdi
    lea     NodeApi_cursor(%rbx), %rsi
    mov     $JSON_CURSOR_SIZE, %edx
    call    lantern_copy
    lea     (NodeEvent_api_bytes + 24)(%rbp), %r12  # the writer
    mov     $1, %r13d
    mov     L(%rsp), %r14
    xor     %r15d, %r15d
    cmpq    $0, (L + 56)(%rsp)              # a validator stream: its selection; getEpochCommittees its count; then the state is what lantern_api_stream_json reads
    je      6f
    cmpq    $3, (L + 56)(%rsp)
    je      67f
    cmpq    $4, (L + 56)(%rsp)
    je      68f
    cmpq    $5, (L + 56)(%rsp)
    je      69f
    cmpq    $6, (L + 56)(%rsp)
    je      6f
    cmpq    $7, (L + 56)(%rsp)
    je      70f
    mov     (L + 64)(%rsp), %rdi
    mov     (L + 48)(%rsp), %rsi
    cmpq    $2, (L + 56)(%rsp)
    je      63f
    mov     (L + 40)(%rsp), %rdx
    call    lantern_node_api_validators_prep
    test    %rax, %rax
    jnz     97f
    cmpq    $API_OP_GET_ATTESTATIONS_REWARDS, NodeApi_op(%rbx)  # getAttestationsRewards: the scratch after the bitmap at +592 of the cursor, the node's config at +584
    jne     66f
    mov     (L + 64)(%rsp), %rdi
    mov     (L + 48)(%rsp), %rax
    mov     (NODE_STATE_VALIDATORS + 8)(%rax), %rcx
    add     $63, %rcx
    shr     $6, %rcx
    lea     16(,%rcx,8), %rcx
    mov     (%rdi), %rax
    sub     %rcx, %rax
    jb      97f
    add     %rdi, %rcx
    mov     %rax, (%rcx)
    mov     %rcx, (NodeEvent_api + 16 + 592)(%rbp)
    mov     (L + 72)(%rsp), %rax
    add     $Node_config, %rax
    mov     %rax, (NodeEvent_api + 16 + 584)(%rbp)
    jmp     66f
68: mov     NodeApi_op(%rbx), %rax          # a pending stream: its items; for SSZ their bytes and their count
    lea     -API_OP_GET_PENDING_DEPOSITS(%rax), %rsi
    mov     $2, %ecx
    cmp     $API_OP_GET_PENDING_CONSOLIDATIONS, %rax
    cmove   %rcx, %rsi
    mov     (L + 48)(%rsp), %rdi
    lea     (L + 8)(%rsp), %rdx
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_pending
    test    %rax, %rax
    jnz     96f
    mov     (L + 16)(%rsp), %rax
    imul    (L + 24)(%rsp), %rax
    mov     %rax, (L + 16)(%rsp)
    mov     (L + 48)(%rsp), %rax            # the state is what lantern_api_stream_json reads
    mov     %rax, (L + 40)(%rsp)
    jmp     6f
69: mov     (L + 40)(%rsp), %rax            # getBlockHeaders: an item's header at the end of scratch, at L+40
    or      (L + 48)(%rsp), %rax
    jz      6f
    mov     (L + 64)(%rsp), %rsi
    mov     (%rsi), %rax
    cmp     $(208 + 64), %rax
    jb      97f
    sub     $208, %rax
    mov     %rax, (%rsi)
    add     %rsi, %rax
    mov     %rax, (L + 32)(%rsp)
    mov     (L + 40)(%rsp), %rdx
    test    %rdx, %rdx
    jz      691f
    cmpq    $108, 16(%rdx)                  # of the bytes: lantern_node_block_header of the fork of their slot
    jb      96f
    mov     8(%rdx), %rax
    add     %rdx, %rax
    mov     100(%rax), %rdi
    mov     (L + 72)(%rsp), %rsi
    add     $Node_config, %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     (L + 40)(%rsp), %rdi
    mov     (L + 64)(%rsp), %rsi
    mov     (L + 32)(%rsp), %rdx
    FORK_CALL node_block_header
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      97f
    test    %rax, %rax
    jnz     96f
    jmp     693f
691: mov    (L + 48)(%rsp), %rsi            # of the post-state: its latest_block_header, a zero signature
    mov     (L + 32)(%rsp), %rdi
    mov     NODE_STATE_HEADER(%rsi), %rax
    mov     %rax, (%rdi)
    add     $8, %rdi
    add     $(NODE_STATE_HEADER + 8), %rsi
    mov     $(112 - 8), %edx
    call    lantern_copy
    mov     (L + 32)(%rsp), %rdi
    add     $112, %rdi
    mov     $96, %esi
    call    lantern_zero
    mov     (L + 32)(%rsp), %rax
    mov     48(%rax), %rcx
    or      56(%rax), %rcx
    or      64(%rax), %rcx
    or      72(%rax), %rcx
    jnz     693f
    mov     (L + 48)(%rsp), %rax            # a zero state_root: the state's root
    mov     NODE_STATE_SLOT(%rax), %rdi
    mov     (L + 72)(%rsp), %rsi
    add     $Node_config, %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    mov     (L + 48)(%rsp), %rdi
    mov     (L + 72)(%rsp), %rsi
    mov     (Node_config + CONFIG_STATE_CACHE)(%rsi), %rsi
    mov     (L + 64)(%rsp), %rdx
    mov     (L + 32)(%rsp), %rcx
    add     $48, %rcx
    FORK_CALL state_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      97f
    test    %rax, %rax
    jnz     96f
693: mov    (L + 32)(%rsp), %rax
    mov     %rax, (L + 40)(%rsp)
    jmp     6f
63: mov     (L + 72)(%rsp), %rdx
    call    lantern_node_api_committees_prep
    cmp     $400, %rax
    je      64f
    test    %rax, %rax
    jnz     97f
66: mov     (L + 48)(%rsp), %rax
    mov     %rax, (L + 40)(%rsp)
    jmp     6f
67: mov     (L + 40)(%rsp), %rsi            # getPoolAttestationsV2 from electra: the Attestation of a SingleAttestation
    test    %rsi, %rsi
    jz      6f
    cmpq    $API_OP_GET_POOL_ATTESTATIONS_V2, NodeApi_op(%rbx)
    jne     6f
    cmpq    $FORK_ELECTRA, NodeApi_sent(%rbx)
    jb      6f
    mov     (L + 64)(%rsp), %rdi
    mov     NodeApi_member(%rbx), %rdx
    call    lantern_node_pool_attestation
    cmp     $1, %rax
    je      96f
    ja      97f
    mov     %rdx, (L + 40)(%rsp)
    jmp     6f
70: testq   $API_STREAM_FOLD, (NodeEvent_api + 8)(%rbp)  # getAggregatedAttestationV2
    jz      73f
    mov     (L + 40)(%rsp), %rsi
    test    %rsi, %rsi
    jz      71f
    mov     (L + 64)(%rsp), %rdi            # a fold of the entry: no bytes
    cmpq    $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, NodeApi_op(%rbx)
    je      74f
    call    lantern_node_api_fold
    jmp     75f
74: mov     (L + 48)(%rsp), %rdx
    call    lantern_node_api_sync_fold
75: cmp     $1, %rax
    je      96f
    ja      97f
    orq     $API_STREAM_ITEM_DONE, (NodeEvent_api + 8)(%rbp)
    jmp     80f
71: mov     $404, %eax                      # the fold's end: none 404, optimistic 503, else the Attestation's bytes
    cmpq    $0, (NodeEvent_api + 16 + 32)(%rbp)
    je      72f
    mov     $503, %eax
    testq   $API_STREAM_OPTIMISTIC, (NodeEvent_api + 8)(%rbp)
    jnz     72f
    mov     %r12, %rdi
    cmpq    $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, NodeApi_op(%rbx)
    je      76f
    call    lantern_node_api_aggregate
    jmp     77f
76: call    lantern_node_api_contribution
77: test    %rax, %rax
    jnz     96f
    add     %rdx, %r12
    jmp     80f
72: mov     %rax, (L + 32)(%rsp)
    jmp     641f
73: mov     (L + 40)(%rsp), %rax            # the answer: from the Attestation's bytes
    test    %rax, %rax
    jz      96f
    mov     8(%rax), %rcx
    add     %rax, %rcx
    mov     %rcx, (L + 8)(%rsp)
    mov     16(%rax), %rcx
    mov     %rcx, (L + 16)(%rsp)
    jmp     6f
64: movq    $400, (L + 32)(%rsp)            # an index past the count: the error 400 is the answer
641: lea    NodeEvent_api_bytes(%rbp), %rsi # the error of L + 32 is the answer
    mov     L(%rsp), %rax
    sub     %rsi, %rax
    mov     %rax, (%rsi)
    mov     (NodeEvent_api + 8)(%rbp), %rax
    mov     %rax, %r8
    and     $API_R_CLOSE, %r8d
    jnz     65f
    test    $API_STREAM_HTTP10, %eax
    jz      65f
    mov     $API_R_KEEP, %r8d
65: xor     %edi, %edi
    mov     (L + 32)(%rsp), %rdx
    mov     $API_BODY_ERROR, %ecx
    call    lantern_api_respond
    test    %rax, %rax
    jnz     97f
    mov     (NodeEvent_api_bytes + 16)(%rbp), %rax
    lea     (NodeEvent_api_bytes + 24)(%rbp,%rax), %r12
    orq     $(API_STREAM_STARTED | API_STREAM_DONE), (NodeEvent_api + 8)(%rbp)
    jmp     80f
6:  mov     (NodeEvent_api + 8)(%rbp), %rax
    test    $API_STREAM_SSZ, %eax
    jz      30f
    cmpq    $6, (L + 56)(%rsp)              # a sidecar stream: SSZ as a JSON answer
    je      30f
    cmpq    $4, (L + 56)(%rsp)              # a pending stream: its SSZ bytes as getStateV2's
    je      601f
    cmpq    $7, (L + 56)(%rsp)              # getAggregatedAttestationV2: the Attestation's SSZ bytes
    je      601f
    cmpq    $0, (L + 56)(%rsp)
    jne     60f
601: test   $API_STREAM_STARTED, %eax
    jnz     11f
    mov     (L + 16)(%rsp), %rdi            # SSZ: the head first, with Content-Length
    call    lantern_api_stream_head
11: mov     (L + 16)(%rsp), %rdx            # then the bytes from sent, as many as fit
    mov     NodeEvent_api(%rbp), %rax
    sub     %rax, %rdx
    mov     %r14, %rcx
    sub     %r12, %rcx
    cmp     %rcx, %rdx
    jbe     12f
    mov     %rcx, %rdx
12: mov     (L + 8)(%rsp), %rsi
    add     %rax, %rsi
    add     %rdx, NodeEvent_api(%rbp)
    mov     %r12, %rdi
    add     %rdx, %r12
    call    lantern_copy
    orq     $API_STREAM_STARTED, (NodeEvent_api + 8)(%rbp)
    mov     NodeEvent_api(%rbp), %rax
    cmp     (L + 16)(%rsp), %rax
    jne     80f
    orq     $API_STREAM_DONE, (NodeEvent_api + 8)(%rbp)
    jmp     80f
60: test    $API_STREAM_STARTED, %eax       # the identities as SSZ: Content-Length of 64 bytes each
    jnz     61f
    mov     (NodeEvent_api + 16 + 40)(%rbp), %rdi
    shl     $6, %rdi
    call    lantern_api_stream_head
61: mov     (L + 40)(%rsp), %rdi
    call    lantern_api_validators_json
    orq     $API_STREAM_STARTED, (NodeEvent_api + 8)(%rbp)
    test    %rax, %rax
    jz      80f
    orq     $API_STREAM_DONE, (NodeEvent_api + 8)(%rbp)
    jmp     80f
30: test    $API_STREAM_STARTED, %eax       # JSON, the first chunk: the body after room for the head
    jnz     40f
    lea     (NodeEvent_api_bytes + 24 + API_HEAD_ROOM)(%rbp), %r12
    cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rbx)
    jne     301f
    add     $API_PRODUCE_HEAD_ROOM, %r12
301: mov    %r12, (L + 24)(%rsp)
    mov     L(%rsp), %r14
    sub     $7, %r14                        # room for CRLF and the last chunk
    cmpq    $0, (L + 56)(%rsp)
    je      35f
    cmpq    $6, (L + 56)(%rsp)              # a sidecar stream: as JSON the pending streams' head; as SSZ none
    jne     393f
    testq   $API_STREAM_SSZ, (NodeEvent_api + 8)(%rbp)
    jnz     36f
    cmpq    $API_OP_GET_BLOBS, NodeApi_op(%rbx)   # getBlobs: as the validator streams
    je      38f
    jmp     392f
393: cmpq   $4, (L + 56)(%rsp)
    je      392f
    cmpq    $7, (L + 56)(%rsp)              # getAggregatedAttestationV2: {"version":"<fork>","data":
    jne     394f
    cmpq    $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, NodeApi_op(%rbx)
    jne     395f
    # produceSyncCommitteeContribution: {"data":
    API_LIT api_pe_data
    jmp     36f
395: API_LIT api_j_version
    mov     NodeApi_fork(%rbx), %rdi
    call    lantern_api_fork_name
    API_LIT api_g_data
    jmp     36f
394: cmpq   $3, (L + 56)(%rsp)
    jne     38f
    cmpq    $API_OP_GET_POOL_ATTESTER_SLASHINGS_V2, NodeApi_op(%rbx)   # a pool stream: {"data":[, the V2 GETs {"version":"<fork>","data":[
    je      391f
    cmpq    $API_OP_GET_POOL_ATTESTATIONS_V2, NodeApi_op(%rbx)
    jne     39f
391: API_LIT api_j_version
    mov     NodeApi_fork(%rbx), %rdi
    call    lantern_api_fork_name
    API_LIT api_p_version
    jmp     36f
39: API_LIT api_p_data
    jmp     36f
    /* the validator streams: {"execution_optimistic":…,"finalized":…,"data":[ */
38: API_LIT api_v_open
    mov     (NodeEvent_api + 8)(%rbp), %rdi
    shr     $8, %rdi
    and     $1, %edi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     (NodeEvent_api + 8)(%rbp), %rdi
    shr     $9, %rdi
    and     $1, %edi
    call    lantern_api_bool
    cmpq    $API_OP_GET_ATTESTATIONS_REWARDS, NodeApi_op(%rbx)  # getAttestationsRewards: ,"data":{"ideal_rewards":[
    jne     381f
    API_LIT api_ar_open
    jmp     36f
381: API_LIT api_v_list
    jmp     36f
    /* the pending streams: {"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[ */
392: API_LIT api_j_version
    mov     NodeApi_fork(%rbx), %rdi
    call    lantern_api_fork_name
    API_LIT api_j_optimistic
    mov     (NodeEvent_api + 8)(%rbp), %rdi
    shr     $8, %rdi
    and     $1, %edi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     (NodeEvent_api + 8)(%rbp), %rdi
    shr     $9, %rdi
    and     $1, %edi
    call    lantern_api_bool
    API_LIT api_v_list
    jmp     36f
    /* {"version":"<fork>","execution_optimistic":…,"finalized":…,"data": */
35: cmpq    $API_OP_PRODUCE_BLOCK_V3, NodeApi_op(%rbx)  # produceBlockV3: {"version":…,"execution_payload_blinded":false,…,"data":
    jne     351f
    API_LIT api_j_version
    mov     NodeApi_fork(%rbx), %rdi
    call    lantern_api_fork_name
    testq   $API_STREAM_PRODUCE_BLINDED, NodeApi_flags(%rbx)  # blinded with API_STREAM_PRODUCE_BLINDED
    jnz     3521f
    API_LIT api_pb_head
    jmp     3522f
3521: API_LIT api_pb_head_true
3522: lea   NodeApi_root(%rbx), %rdi
    call    lantern_api_dec256
    API_LIT api_pb_block_value
    mov     NodeApi_filter_slot(%rbx), %rdi
    call    lantern_api_wei
    API_LIT api_g_data
    jmp     36f
351: API_LIT api_j_version
    mov     NodeApi_fork(%rbx), %rdi
    call    lantern_api_fork_name
    API_LIT api_j_optimistic
    mov     (NodeEvent_api + 8)(%rbp), %rdi
    shr     $8, %rdi
    and     $1, %edi
    call    lantern_api_bool
    API_LIT api_x_finalized
    mov     (NodeEvent_api + 8)(%rbp), %rdi
    shr     $9, %rdi
    and     $1, %edi
    call    lantern_api_bool
    API_LIT api_j_data
36: mov     (L + 40)(%rsp), %rdi
    mov     (L + 48)(%rsp), %rsi            # state_a: the blob stream's versioned hashes
    call    lantern_api_stream_json
    cmp     $3, %rax
    je      97f
    cmp     $2, %rax
    je      96f
    mov     (NodeEvent_api + 8)(%rbp), %rcx
    or      $API_STREAM_STARTED, %rcx
    mov     $-1, %rdx                       # not whole: chunked, or for HTTP/1.0 no length and a close
    test    %rax, %rax
    jz      31f
    or      $API_STREAM_DONE, %rcx          # whole: Content-Length
    mov     %r12, %rdx
    sub     (L + 24)(%rsp), %rdx
    jmp     33f
31: test    $API_STREAM_HTTP10, %ecx
    jz      32f
    or      $API_STREAM_CLOSE, %rcx
    jmp     33f
32: or      $API_STREAM_CHUNKED, %rcx
33: mov     %rcx, (NodeEvent_api + 8)(%rbp)
    mov     %rdx, (L + 32)(%rsp)
    mov     %r12, %rax                      # the body's bytes
    sub     (L + 24)(%rsp), %rax
    mov     %rax, (L + 16)(%rsp)
    xor     %r13d, %r13d                    # the head's bytes: a pass that counts
    xor     %r12d, %r12d
    mov     (L + 32)(%rsp), %rdi
    call    lantern_api_stream_head
    lea     (NodeEvent_api_bytes + 24)(%rbp,%r12), %rdi # the body after the head, and a size line when chunked
    testq   $API_STREAM_CHUNKED, (NodeEvent_api + 8)(%rbp)
    jz      34f
    add     $6, %rdi
34: mov     (L + 24)(%rsp), %rsi
    mov     (L + 16)(%rsp), %rdx
    lea     (%rdi,%rdx), %rax
    mov     %rax, (L + 24)(%rsp)            # now the body's end
    call    lantern_copy
    mov     $1, %r13d                       # the head
    lea     (NodeEvent_api_bytes + 24)(%rbp), %r12
    mov     L(%rsp), %r14
    mov     (L + 32)(%rsp), %rdi
    call    lantern_api_stream_head
    testq   $API_STREAM_CHUNKED, (NodeEvent_api + 8)(%rbp)
    jz      37f
    mov     (L + 16)(%rsp), %rdi            # chunked: the size line, then CRLF after the bytes
    mov     %r12, %rsi
    call    lantern_api_hex4
    movw    $0x0a0d, 4(%r12)
    mov     (L + 24)(%rsp), %r12
    API_LIT api_crlf
    jmp     80f
37: mov     (L + 24)(%rsp), %r12
    jmp     80f
40: test    $API_STREAM_CHUNKED, %eax       # JSON, a later chunk; chunked: a size line, the bytes, CRLF
    jz      45f
    lea     (NodeEvent_api_bytes + 24 + 6)(%rbp), %r12
    mov     L(%rsp), %r14
    sub     $7, %r14
    mov     (L + 40)(%rsp), %rdi
    mov     (L + 48)(%rsp), %rsi
    call    lantern_api_stream_json
    cmp     $3, %rax
    je      97f
    cmp     $2, %rax
    je      96f
    mov     %rax, (L + 32)(%rsp)
    lea     (NodeEvent_api_bytes + 24 + 6)(%rbp), %rcx  # no bytes: no chunk of them, the last chunk alone
    cmp     %rcx, %r12
    jne     41f
    lea     (NodeEvent_api_bytes + 24)(%rbp), %r12
    mov     L(%rsp), %r14
    test    %rax, %rax
    jz      80f
    API_LIT api_last_chunk
    jmp     44f
41: lea     (NodeEvent_api_bytes + 24)(%rbp), %rsi
    mov     %r12, %rdi
    sub     %rsi, %rdi
    sub     $6, %rdi
    call    lantern_api_hex4
    movw    $0x0a0d, (NodeEvent_api_bytes + 24 + 4)(%rbp)
    mov     L(%rsp), %r14
    API_LIT api_crlf
    cmpq    $0, (L + 32)(%rsp)
    je      80f
    API_LIT api_last_chunk
    jmp     44f
45: mov     (L + 40)(%rsp), %rdi            # HTTP/1.0: the bytes alone
    mov     (L + 48)(%rsp), %rsi
    call    lantern_api_stream_json
    cmp     $3, %rax
    je      97f
    cmp     $2, %rax
    je      96f
    test    %rax, %rax
    jz      80f
44: orq     $API_STREAM_DONE, (NodeEvent_api + 8)(%rbp)
80: lea     (NodeEvent_api_bytes + 24)(%rbp), %rax  # the chunk's ByteList; the event's size covers it
    mov     %r12, %rcx
    sub     %rax, %rcx
    lea     (24 + 7)(%rcx), %rdx
    and     $~7, %rdx
    mov     %rdx, NodeEvent_api_bytes(%rbp)
    movq    $24, (NodeEvent_api_bytes + 8)(%rbp)
    mov     %rcx, (NodeEvent_api_bytes + 16)(%rbp)
    lea     NodeEvent_api_bytes(%rdx), %rax
    mov     %rax, (%rbp)
    mov     %r12, %rdi
    mov     %rdx, %rsi
    sub     $24, %rsi
    sub     %rcx, %rsi
    call    lantern_zero
    xor     %eax, %eax
    LEAVE 80
95: movq    $LANTERN_INVALID_SLOT, NodeEvent_result(%rbp)       # a state at another slot
    jmp     94f
96: movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%rbp)   # bytes that are no encoding of the type
94: movq    $NODE_EV_WORK_DONE_SIZE, (%rbp)
    xor     %eax, %eax
    LEAVE 80
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
98: mov     $LANTERN_INVALID_EVENT, %eax
    LEAVE 80
END_FUNCTION lantern_node_api_chunk_run

/* ------------------------------------------------------------ The pools (beacon-api.md, node.md) */

/*
 * (scratch rdi, the ByteList rsi of a SingleAttestation, member rdx) -> rax: the electra Attestation
 * of it as a ByteList at the end of scratch, at rdx (node.md, NODE_WORK_API_CHUNK, the pool
 * streams): aggregation_bits of the length member / 2^16 with the bit of the place member % 2^16,
 * data, signature, committee_bits with the bit of committee_index. rax = 0; 1 for bytes of another
 * size, a place not below the length, a length above MAX_VALIDATORS_PER_COMMITTEE or a
 * committee_index not below MAX_COMMITTEES_PER_SLOT; 2 for a scratch without
 * NODE_POOL_ATTESTATION_ROOM bytes. Locals: the ByteList, the SingleAttestation, the committee
 * index, the place, the length.
 */
LOCAL_FUNCTION lantern_node_pool_attestation
    FRAME 48
    cmpq    $240, 16(%rsi)
    jne     81f
    mov     8(%rsi), %rax
    add     %rsi, %rax
    mov     (%rax), %rcx
    cmp     $MAX_COMMITTEES_PER_SLOT, %rcx
    jae     81f
    movzwl  %dx, %r8d
    shr     $16, %rdx
    cmp     $MAX_VALIDATORS_PER_COMMITTEE, %rdx
    ja      81f
    cmp     %rdx, %r8
    jae     81f
    mov     (%rdi), %r9
    cmp     $NODE_POOL_ATTESTATION_ROOM, %r9
    jb      82f
    lea     -NODE_POOL_ATTESTATION_ROOM(%rdi,%r9), %r9
    mov     %r9, (%rsp)
    mov     %rax, 8(%rsp)
    mov     %rcx, 16(%rsp)
    mov     %r8, 24(%rsp)
    mov     %rdx, 32(%rsp)
    lea     24(%r9), %rdi
    mov     $(NODE_POOL_ATTESTATION_ROOM - 24), %esi
    call    lantern_zero
    mov     (%rsp), %r9                     # its head: size, offset 24, count
    movq    $NODE_POOL_ATTESTATION_ROOM, (%r9)
    movq    $24, 8(%r9)
    mov     32(%rsp), %rax
    shr     $3, %rax
    add     $(NODE_POOL_ATTESTATION_FIXED + 1), %rax
    mov     %rax, 16(%r9)
    movl    $NODE_POOL_ATTESTATION_FIXED, 24(%r9)   # the offset of aggregation_bits, data and signature
    lea     28(%r9), %rdi
    mov     8(%rsp), %rsi
    add     $16, %rsi
    mov     $(128 + 96), %edx
    call    lantern_copy
    mov     (%rsp), %r9
    mov     16(%rsp), %rcx                  # committee_bits
    mov     %rcx, %rax
    shr     $3, %rax
    and     $7, %ecx
    mov     $1, %edx
    shl     %cl, %edx
    or      %dl, (24 + 4 + 128 + 96)(%r9,%rax)
    add     $(24 + NODE_POOL_ATTESTATION_FIXED), %r9    # aggregation_bits: the place, then the length's bit
    mov     24(%rsp), %rcx
    mov     %rcx, %rax
    shr     $3, %rax
    and     $7, %ecx
    mov     $1, %edx
    shl     %cl, %edx
    or      %dl, (%r9,%rax)
    mov     32(%rsp), %rcx
    mov     %rcx, %rax
    shr     $3, %rax
    and     $7, %ecx
    mov     $1, %edx
    shl     %cl, %edx
    or      %dl, (%r9,%rax)
    mov     (%rsp), %rdx
    xor     %eax, %eax
    UNFRAME 48
81: mov     $1, %eax
    UNFRAME 48
82: mov     $2, %eax
    UNFRAME 48
END_FUNCTION lantern_node_pool_attestation

/* rax = the new id of a NODE_ACT_BYTES_PUT of the 8 bytes at rdi. Locals: a ByteList head whose offset reaches them. */
LOCAL_FUNCTION lantern_node_api_put8
    FRAME 32
    mov     %rdi, %rax
    sub     %rsp, %rax
    movq    $8, (%rsp)
    mov     %rax, 8(%rsp)
    movq    $8, 16(%rsp)
    mov     %rsp, %rdi
    call    lantern_node_put
    UNFRAME 32
END_FUNCTION lantern_node_api_put8

/* rax = the gossip topic of the pool POST rdi, or 0. */
LOCAL_FUNCTION lantern_node_submit_topic
    UNWIND_END_PROLOGUE
    mov     $GOSSIP_VOLUNTARY_EXIT, %eax
    cmp     $API_OP_SUBMIT_POOL_VOLUNTARY_EXIT, %rdi
    je      9f
    mov     $GOSSIP_PROPOSER_SLASHING, %eax
    cmp     $API_OP_SUBMIT_POOL_PROPOSER_SLASHINGS, %rdi
    je      9f
    mov     $GOSSIP_ATTESTER_SLASHING, %eax
    cmp     $API_OP_SUBMIT_POOL_ATTESTER_SLASHINGS_V2, %rdi
    je      9f
    mov     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %eax
    cmp     $API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE, %rdi
    je      9f
    mov     $GOSSIP_BEACON_ATTESTATION, %eax
    cmp     $API_OP_SUBMIT_POOL_ATTESTATIONS_V2, %rdi
    je      9f
    mov     $GOSSIP_BEACON_AGGREGATE_AND_PROOF, %eax
    cmp     $API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2, %rdi
    je      9f
    mov     $GOSSIP_SYNC_COMMITTEE, %eax
    cmp     $API_OP_SUBMIT_POOL_SYNC_COMMITTEE_SIGNATURES, %rdi
    je      9f
    mov     $GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF, %eax
    cmp     $API_OP_PUBLISH_CONTRIBUTION_AND_PROOFS, %rdi
    je      9f
    xor     %eax, %eax
9:  ret
END_FUNCTION lantern_node_submit_topic

/* rax = the lantern_node_json kind of the pool operation of the gossip topic rdi. */
LOCAL_FUNCTION lantern_node_pool_kind
    UNWIND_END_PROLOGUE
    lea     -(GOSSIP_VOLUNTARY_EXIT - NODE_JSON_EXIT)(%rdi), %rax
    cmp     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %rdi
    jne     9f
    mov     $NODE_JSON_BLS_CHANGE, %eax
9:  ret
END_FUNCTION lantern_node_pool_kind
.if GOSSIP_PROPOSER_SLASHING - GOSSIP_VOLUNTARY_EXIT != NODE_JSON_PROPOSER_SLASHING - NODE_JSON_EXIT || GOSSIP_ATTESTER_SLASHING - GOSSIP_VOLUNTARY_EXIT != NODE_JSON_ATTESTER_SLASHING - NODE_JSON_EXIT
.error "node_pool_kind: the kinds follow the topics"
.endif

/*
 * rax = the index of the first pool entry from the index rdi that the pool stream rsi answers
 * (node.md, NODE_EV_API): of its topic; for getPoolAttesterSlashingsV2 and getPoolAttestationsV2
 * of the type of its fork, and for getPoolAttestationsV2 of its filters; else 2^64 - 1. rdx = the
 * entry. rbx the node. Uses rcx, r8, r9, r10, r11.
 */
LOCAL_FUNCTION lantern_node_pool_next
    UNWIND_END_PROLOGUE
    mov     NodeApi_op(%rsi), %rax
    mov     $GOSSIP_VOLUNTARY_EXIT, %ecx
    cmp     $API_OP_GET_POOL_VOLUNTARY_EXITS, %rax
    je      1f
    mov     $GOSSIP_PROPOSER_SLASHING, %ecx
    cmp     $API_OP_GET_POOL_PROPOSER_SLASHINGS, %rax
    je      1f
    mov     $GOSSIP_ATTESTER_SLASHING, %ecx
    cmp     $API_OP_GET_POOL_ATTESTER_SLASHINGS_V2, %rax
    je      1f
    mov     $GOSSIP_BEACON_ATTESTATION, %ecx
    cmp     $API_OP_GET_POOL_ATTESTATIONS_V2, %rax
    je      1f
    cmp     $API_OP_GET_AGGREGATED_ATTESTATION_V2, %rax
    je      1f
    mov     $GOSSIP_SYNC_COMMITTEE, %ecx
    cmp     $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, %rax
    je      1f
    mov     $GOSSIP_BLS_TO_EXECUTION_CHANGE, %ecx
1:  xor     %r11d, %r11d
    cmpq    $FORK_ELECTRA, NodeApi_fork(%rsi)
    setae   %r11b
    mov     NodeApi_filter_slot(%rsi), %r9
    mov     %rdi, %rax
    PART    %rdx, %r10, %rbx, Node_pool
    imul    $NodePool__mem, %rax, %r8
    add     %r8, %rdx
2:  cmp     %r10, %rax
    jae     8f
    cmp     %rcx, NodePool_topic(%rdx)
    jne     3f
    cmp     $GOSSIP_ATTESTER_SLASHING, %rcx
    je      21f
    cmp     $GOSSIP_SYNC_COMMITTEE, %rcx
    je      22f
    cmp     $GOSSIP_BEACON_ATTESTATION, %rcx
    jne     4f
    cmp     $-1, %r9                        # an attestation: of the filters
    je      20f
    cmp     %r9, NodePool_slot(%rdx)
    jne     3f
20: mov     NodeApi_filter_index(%rsi), %r8
    cmp     $-1, %r8
    je      21f
    cmp     %r8, NodePool_index(%rdx)
    jne     3f
21: xor     %r8d, %r8d
    cmpq    $FORK_ELECTRA, NodePool_fork(%rdx)
    setae   %r8b
    cmp     %r11, %r8
    je      4f
3:  add     $NodePool__mem, %rdx
    inc     %rax
    jmp     2b
22: cmp     %r9, NodePool_slot(%rdx)       # a sync message: of the slot, valid on the subnet
    jne     3b
    mov     NodeApi_filter_index(%rsi), %r8
    bt      %r8, NodePool_index(%rdx)
    jnc     3b
4:  ret
8:  mov     $-1, %rax
    ret
END_FUNCTION lantern_node_pool_next

/*
 * (connection rdi, route rsi, flags rdx, view rcx): a stream of a pool GET (node.md, NODE_EV_API):
 * fork the store's, the filters of getPoolAttestationsV2; slot the first entry it answers, data
 * its bytes, sent its fork, member its member; data 0 with none. flags: API_STREAM_CLOSE and API_STREAM_HTTP10. Locals: the connection, the route, the
 * flags, the fork, the entry's index and address.
 */
LOCAL_FUNCTION lantern_node_api_pool_stream
    FRAME 48
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     ApiView_fork(%rcx), %rax
    mov     %rax, 24(%rsp)
    call    lantern_node_api_new
    mov     %rax, 32(%rsp)
    mov     %rdx, 40(%rsp)
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     40(%rsp), %rdx
    mov     (%rsp), %rax
    mov     %rax, NodeApi_connection(%rdx)
    mov     8(%rsp), %rax
    mov     ApiRoute_op(%rax), %rsi
    mov     %rsi, NodeApi_op(%rdx)
    mov     16(%rsp), %rax
    mov     %rax, NodeApi_flags(%rdx)
    mov     24(%rsp), %rax
    mov     %rax, NodeApi_fork(%rdx)
    movq    $-1, NodeApi_filter_slot(%rdx)  # the filters: getPoolAttestationsV2's slot and committee_index
    movq    $-1, NodeApi_filter_index(%rdx)
    cmp     $API_OP_GET_POOL_ATTESTATIONS_V2, %rsi
    je      4f
    cmp     $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, %rsi
    je      23f
    cmp     $API_OP_GET_AGGREGATED_ATTESTATION_V2, %rsi
    jne     2f
    mov     8(%rsp), %rax                   # getAggregatedAttestationV2: a fold, SSZ, attestation_data_root in cursor
    mov     NodeApi_flags(%rdx), %rcx
    or      $API_STREAM_FOLD, %rcx
    cmpq    $API_TYPE_SSZ, ApiRoute_response(%rax)
    jne     5f
    or      $API_STREAM_SSZ, %rcx
5:  mov     %rcx, NodeApi_flags(%rdx)
    movdqu  ApiRoute_root(%rax), %xmm0
    movdqu  (ApiRoute_root + 16)(%rax), %xmm1
    movdqu  %xmm0, NodeApi_cursor(%rdx)
    movdqu  %xmm1, (NodeApi_cursor + 16)(%rdx)
4:  mov     8(%rsp), %rax
    testq   $(1 << API_PARAM_SLOT), ApiRoute_present(%rax)
    jz      3f
    mov     ApiRoute_slot(%rax), %rcx
    mov     %rcx, NodeApi_filter_slot(%rdx)
3:  testq   $(1 << API_PARAM_COMMITTEE_INDEX), ApiRoute_present(%rax)
    jz      2f
    mov     ApiRoute_committee_index(%rax), %rcx
    mov     %rcx, NodeApi_filter_index(%rdx)
2:  xor     %edi, %edi
    mov     %rdx, %rsi
    call    lantern_node_pool_next
    mov     40(%rsp), %rcx
    cmp     $-1, %rax
    je      1f
    mov     %rax, NodeApi_slot(%rcx)
    mov     NodePool_data_id(%rdx), %rax
    mov     %rax, NodeApi_data(%rcx)
    mov     NodePool_fork(%rdx), %rax
    mov     %rax, NodeApi_sent(%rcx)
    mov     NodePool_member(%rdx), %rax
    mov     %rax, NodeApi_member(%rcx)
6:  mov     32(%rsp), %rax
    mov     40(%rsp), %rdx
    call    lantern_node_api_chunk_work
    xor     %eax, %eax
    UNFRAME 48
1:  cmpq    $API_OP_GET_AGGREGATED_ATTESTATION_V2, NodeApi_op(%rcx)  # none: the folds 404, and no stream
    je      7f
    cmpq    $API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION, NodeApi_op(%rcx)
    jne     6b
7:  mov     %rcx, %rdi
    call    lantern_node_api_end
    mov     $404, %eax
    UNFRAME 48
23: mov     8(%rsp), %rax                   # produceSyncCommitteeContribution: a fold of slot and subcommittee_index,
    mov     ApiRoute_subcommittee_index(%rax), %rcx     # beacon_block_root in cursor, the head's post-state; 400, 500
    cmp     $SYNC_COMMITTEE_SUBNET_COUNT, %rcx
    jae     25f
    mov     %rcx, NodeApi_filter_index(%rdx)
    mov     ApiRoute_slot(%rax), %rcx
    mov     %rcx, NodeApi_filter_slot(%rdx)
    orq     $API_STREAM_FOLD, NodeApi_flags(%rdx)
    movdqu  ApiRoute_root(%rax), %xmm0
    movdqu  (ApiRoute_root + 16)(%rax), %xmm1
    movdqu  %xmm0, NodeApi_cursor(%rdx)
    movdqu  %xmm1, (NodeApi_cursor + 16)(%rdx)
    lea     Node_head_root(%rbx), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      26f
    mov     NodeBlock_state_id(%rdx), %rax
    test    %rax, %rax
    jz      26f
    mov     40(%rsp), %rdx
    mov     %rax, NodeApi_state(%rdx)
    jmp     2b
25: mov     40(%rsp), %rdi
    call    lantern_node_api_end
    mov     $400, %eax
    UNFRAME 48
26: mov     40(%rsp), %rdi
    call    lantern_node_api_end
    mov     $500, %eax
    UNFRAME 48
END_FUNCTION lantern_node_api_pool_stream

/*
 * The item of the getBlockHeaders stream rdi at or after the position rsi (node.md, NODE_EV_API, an
 * item of getBlockHeaders): position 0 the Db's block of the query, i + 1 the NodeBlock at index i.
 * Its slot (the position), data, state, member (1 on the chain, + 2 optimistic, + 4 finalized) and
 * its root at byte 0 of cursor; rax = 1, or 0 with data and state 0 for none. rbx the node, rbp the
 * store. r12 the entry, r13 the position, r14 the slot of the query or 2^64 - 1, r15 the address of
 * its parent_root or 0. Locals: L, L+8 the member, L+16 a slot or a NodeBlock entry.
 */
LOCAL_FUNCTION lantern_node_headers_next
    ENTER 32
    mov     %rdi, %r12
    mov     %rsi, %r13
    mov     NodeApi_filter_slot(%r12), %r14
    xor     %r15d, %r15d
    cmpq    $0, (NodeApi_cursor + 64)(%r12)
    je      1f
    lea     (NodeApi_cursor + 32)(%r12), %r15
1:  test    %r13, %r13
    jnz     20f
    testq   $NODE_FLAG_DB, Node_flags(%rbx)  # position 0: with NODE_FLAG_DB, the Db's block of the query
    jz      19f
    test    %r15, %r15
    jz      15f
    mov     %r15, %rdi                      # with parent_root: its slot r, of the node's imported block on the chain, else of the Db
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      11f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     11f
    mov     %rdx, (L + 16)(%rsp)
    mov     %rdx, %rdi
    call    lantern_node_api_on_chain
    test    %rax, %rax
    jz      19f
    mov     (L + 16)(%rsp), %rax
    mov     NodeBlock_slot(%rax), %rax
    mov     %rax, (L + 16)(%rsp)
    jmp     12f
11: mov     Node_db(%rbx), %rdi
    add     %rbx, %rdi
    mov     %r15, %rsi
    lea     (L + 16)(%rsp), %rdx
    call    lantern_db_find_root
    cmpq    $-1, (L + 16)(%rsp)
    je      19f
12: incq    (L + 16)(%rsp)                  # the first slot above r whose block is in the Db, below the chain the node keeps
    cmp     %r14, (L + 16)(%rsp)
    ja      19f                             # with slot: at most slot
    mov     (L + 16)(%rsp), %rdi
    call    lantern_node_api_below
    cmp     $-1, %rax
    jne     19f
    mov     (L + 16)(%rsp), %rdi
    call    lantern_node_db_slot
    test    %rax, %rax
    jz      12b
    cmp     $-1, %r14
    je      16f
    cmp     %r14, (L + 16)(%rsp)
    jne     19f
    jmp     16f
15: mov     %r14, (L + 16)(%rsp)            # slot alone: the Db's block of slot, below the chain the node keeps
    mov     %r14, %rdi
    call    lantern_node_api_below
    cmp     $-1, %rax
    jne     19f
    mov     %r14, %rdi
    call    lantern_node_db_slot
    test    %rax, %rax
    jz      19f
16: lea     NodeApi_cursor(%r12), %rdi      # the Db's block of the slot at L + 16: its DbSlot rax, the root at 0
    COPY32  %rdi, %rax
    mov     (L + 16)(%rsp), %rdi
    call    lantern_node_db_block
    mov     %rax, NodeApi_data(%r12)
    movq    $0, NodeApi_state(%r12)
    movq    $0, NodeApi_slot(%r12)
    mov     (L + 16)(%rsp), %rdi
    call    lantern_node_api_final_block
    shl     $2, %rax
    or      $1, %rax                        # on the chain, not optimistic
    mov     %rax, NodeApi_member(%r12)
    mov     $1, %eax
    LEAVE 32
19: mov     $1, %r13d
20: PART    %rcx, %rdx, %rbx, Node_blocks   # the node's imported blocks from the index r13 - 1
    lea     -1(%r13), %rax
    cmp     %rdx, %rax
    jae     29f
    imul    $NodeBlock__mem, %rax, %rax
    lea     (%rcx,%rax), %rsi
    mov     %rsi, (L + 16)(%rsp)
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rsi)
    jne     28f
    cmp     $-1, %r14
    je      22f
    cmp     %r14, NodeBlock_slot(%rsi)
    jne     28f
22: test    %r15, %r15
    jz      23f
    lea     NodeBlock_parent_root(%rsi), %rax
    NE32    %rax, %r15, 28f
23: mov     NodeBlock_data_id(%rsi), %rax   # its bytes, else its Db record, else its post-state
    test    %rax, %rax
    jnz     24f
    mov     %rsi, %rdi
    call    lantern_node_api_db_ref
24: mov     (L + 16)(%rsp), %rsi
    mov     %rax, NodeApi_data(%r12)
    xor     %ecx, %ecx
    test    %rax, %rax
    jnz     25f
    mov     NodeBlock_state_id(%rsi), %rcx
    test    %rcx, %rcx
    jz      28f                             # neither: left out
25: mov     %rcx, NodeApi_state(%r12)
    mov     %r13, NodeApi_slot(%r12)
    lea     NodeApi_cursor(%r12), %rdi
    COPY32  %rdi, %rsi
    xor     %eax, %eax
    cmpq    $PAYLOAD_STATUS_NOT_VALIDATED, NodeBlock_payload_status(%rsi)
    sete    %al
    shl     $1, %eax
    mov     %rax, (L + 8)(%rsp)
    mov     %rsi, %rdi
    call    lantern_node_api_on_chain
    or      %rax, (L + 8)(%rsp)
    test    %rax, %rax
    jz      26f
    mov     (L + 16)(%rsp), %rsi
    mov     NodeBlock_slot(%rsi), %rdi
    call    lantern_node_api_final_block
    shl     $2, %rax
    or      %rax, (L + 8)(%rsp)
26: mov     (L + 8)(%rsp), %rax
    mov     %rax, NodeApi_member(%r12)
    mov     $1, %eax
    LEAVE 32
28: inc     %r13
    jmp     20b
29: movq    $0, NodeApi_data(%r12)
    movq    $0, NodeApi_state(%r12)
    xor     %eax, %eax
    LEAVE 32
END_FUNCTION lantern_node_headers_next

/*
 * (connection rdi, route rsi, flags rdx): the getBlockHeaders stream of the route's query (node.md,
 * NODE_EV_API): filter_slot its slot, the head's slot with neither slot nor parent_root, else
 * 2^64 - 1; its parent_root at byte 32 of cursor and 1 at byte 64; API_STREAM_OPTIMISTIC and
 * API_STREAM_FINALIZED of all its items; then its first item and a NODE_WORK_API_CHUNK. rbx the
 * node. Locals: the connection, the route then the items, the flags, the entry's index and address,
 * the position.
 */
LOCAL_FUNCTION lantern_node_api_headers_stream
    FRAME 48
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    call    lantern_node_api_new
    mov     %rax, 24(%rsp)
    mov     %rdx, 32(%rsp)
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     32(%rsp), %rdx
    mov     (%rsp), %rax
    mov     %rax, NodeApi_connection(%rdx)
    movq    $API_OP_GET_BLOCK_HEADERS, NodeApi_op(%rdx)
    mov     8(%rsp), %rax
    testq   $(1 << API_PARAM_PARENT_ROOT), ApiRoute_present(%rax)
    jz      1f
    lea     (NodeApi_cursor + 32)(%rdx), %rdi
    lea     ApiRoute_root(%rax), %rsi
    COPY32  %rdi, %rsi
    mov     32(%rsp), %rdx
    movq    $1, (NodeApi_cursor + 64)(%rdx)
    movq    $-1, NodeApi_filter_slot(%rdx)
    jmp     2f
1:  lea     Node_head_root(%rbx), %rdi      # neither: the head's slot
    call    lantern_node_find_block
    mov     $-1, %rcx
    cmp     $-1, %rax
    je      11f
    mov     NodeBlock_slot(%rdx), %rcx
11: mov     32(%rsp), %rdx
    mov     %rcx, NodeApi_filter_slot(%rdx)
2:  mov     8(%rsp), %rax
    testq   $(1 << API_PARAM_SLOT), ApiRoute_present(%rax)
    jz      3f
    mov     ApiRoute_slot(%rax), %rcx
    mov     %rcx, NodeApi_filter_slot(%rdx)
3:  mov     16(%rsp), %rax                  # the flags of all items: optimistic of any, finalized of each, and of some
    or      $API_STREAM_FINALIZED, %rax
    mov     %rax, NodeApi_flags(%rdx)
    movq    $0, 8(%rsp)
    movq    $0, 40(%rsp)
4:  mov     32(%rsp), %rdi
    mov     40(%rsp), %rsi
    call    lantern_node_headers_next
    mov     32(%rsp), %rdx
    test    %rax, %rax
    jz      5f
    incq    8(%rsp)
    mov     NodeApi_member(%rdx), %rcx
    test    $2, %ecx
    jz      41f
    orq     $API_STREAM_OPTIMISTIC, NodeApi_flags(%rdx)
41: test    $4, %ecx
    jnz     42f
    andq    $~API_STREAM_FINALIZED, NodeApi_flags(%rdx)
42: mov     NodeApi_slot(%rdx), %rax
    inc     %rax
    mov     %rax, 40(%rsp)
    jmp     4b
5:  cmpq    $0, 8(%rsp)
    jne     6f
    andq    $~API_STREAM_FINALIZED, NodeApi_flags(%rdx)
6:  mov     32(%rsp), %rdi                  # the first item
    xor     %esi, %esi
    call    lantern_node_headers_next
    mov     24(%rsp), %rax
    mov     32(%rsp), %rdx
    call    lantern_node_api_chunk_work
    UNFRAME 48
END_FUNCTION lantern_node_api_headers_stream

# rax = the data of the sidecar of index rdx of the block of the root at rdi and the slot rsi, as a
# sidecar stream finds it (node.md): the NODE_BLOB_VALID entry's bytes, else with NODE_FLAG_DB the
# NODE_DB_REF of the Db's record; 0 with none. rbx the node. Locals: the slot, the index.
LOCAL_FUNCTION lantern_node_sidecar_of
    FRAME 16
    mov     %rsi, (%rsp)
    mov     %rdx, 8(%rsp)
    mov     %rdx, %rsi
    call    lantern_node_blob_held
    test    %rax, %rax
    jz      1f
    mov     NodeBlob_data_id(%rax), %rax
    UNFRAME 16
1:  testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      9f
    mov     (%rsp), %rdi
    mov     8(%rsp), %rsi
    call    lantern_node_db_sidecar
    UNFRAME 16
9:  xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_node_sidecar_of

# (connection rdi, route rsi, flags rdx, view rcx) -> rax: the blob stream of the block of the view
# (node.md, NODE_EV_API, the blob stream): 0, or 404 for a fulu block of which the node holds a
# column sidecar but not one of each of the first NUMBER_OF_COLUMNS / 2 columns. rbx the node.
# Locals: the connection, the route, the flags, the view, the fork, the entry's index and address, a
# column, the count of the first half's columns held, 1 with any held, a ByteList head (24).
LOCAL_FUNCTION lantern_node_api_blob_stream
    FRAME 112
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rcx, 24(%rsp)
    mov     ApiView_head_slot(%rcx), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, 32(%rsp)
    movq    $0, 64(%rsp)
    movq    $0, 72(%rsp)
    cmp     $FORK_FULU, %rax
    jb      2f
    movq    $0, 56(%rsp)
1:  mov     56(%rsp), %rdx                  # fulu: the columns the node holds
    cmp     $NUMBER_OF_COLUMNS, %rdx
    jae     11f
    mov     24(%rsp), %rcx
    lea     ApiView_head_root(%rcx), %rdi
    mov     ApiView_head_slot(%rcx), %rsi
    call    lantern_node_sidecar_of
    mov     56(%rsp), %rdx
    incq    56(%rsp)
    test    %rax, %rax
    jz      1b
    movq    $1, 72(%rsp)
    cmp     $(NUMBER_OF_COLUMNS / 2), %rdx
    jae     1b
    incq    64(%rsp)
    jmp     1b
11: cmpq    $(NUMBER_OF_COLUMNS / 2), 64(%rsp)
    je      2f
    cmpq    $0, 72(%rsp)
    jne     8f                              # some, but not each of the first half: 404
2:  call    lantern_node_api_new
    mov     %rax, 40(%rsp)
    mov     %rdx, 48(%rsp)
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     48(%rsp), %rdx
    mov     (%rsp), %rax
    mov     %rax, NodeApi_connection(%rdx)
    mov     8(%rsp), %rsi
    mov     ApiRoute_op(%rsi), %rax
    mov     %rax, NodeApi_op(%rdx)
    mov     16(%rsp), %rax                  # the answer flags, SSZ, and the block's values
    cmpq    $API_TYPE_SSZ, ApiRoute_response(%rsi)
    jne     3f
    or      $API_STREAM_SSZ, %rax
3:  mov     24(%rsp), %rcx
    cmpq    $0, ApiView_is_optimistic(%rcx)
    je      31f
    or      $API_STREAM_OPTIMISTIC, %rax
31: cmpq    $0, ApiView_head_finalized(%rcx)
    je      32f
    or      $API_STREAM_FINALIZED, %rax
32: mov     %rax, NodeApi_flags(%rdx)
    mov     32(%rsp), %rax
    mov     %rax, NodeApi_fork(%rdx)
    mov     ApiView_head_slot(%rcx), %rax
    mov     %rax, NodeApi_slot(%rdx)
    lea     NodeApi_root(%rdx), %rdi
    lea     ApiView_head_root(%rcx), %rsi
    COPY32  %rdi, %rsi
    mov     8(%rsp), %rsi                   # the versioned hashes: a BYTES_PUT of them, as the entry's state
    testq   $(1 << API_PARAM_VERSIONED_HASHES), ApiRoute_present(%rsi)
    jz      5f
    PART    %rax, %rcx, %rsi, ApiRoute_list
    shl     $5, %rcx
    lea     80(%rsp), %rdi                  # a ByteList head whose offset reaches the items
    sub     %rdi, %rax
    mov     %rcx, (%rdi)
    mov     %rax, 8(%rdi)
    mov     %rcx, 16(%rdi)
    call    lantern_node_put
    mov     48(%rsp), %rdx
    mov     %rax, NodeApi_state(%rdx)
    orq     $API_STREAM_OWN_STATE, NodeApi_flags(%rdx)
5:  mov     48(%rsp), %rdx                  # the first item
    mov     32(%rsp), %rax
    cmp     $FORK_DENEB, %rax
    jb      7f
    cmp     $FORK_FULU, %rax
    jae     6f
    movq    $-1, NodeApi_filter_slot(%rdx)  # deneb and electra: every sidecar
    movq    $-1, NodeApi_filter_index(%rdx)
    mov     %rdx, %rdi
    xor     %esi, %esi
    call    lantern_node_sidecar_next
    jmp     7f
6:  cmpq    $(NUMBER_OF_COLUMNS / 2), 64(%rsp)  # fulu: blob 0 and column 0 with the first half; else none
    jne     7f
    lea     NodeApi_root(%rdx), %rdi
    mov     NodeApi_slot(%rdx), %rsi
    xor     %edx, %edx
    call    lantern_node_sidecar_of
    mov     48(%rsp), %rdx
    mov     %rax, NodeApi_data(%rdx)
7:  mov     40(%rsp), %rax
    mov     48(%rsp), %rdx
    call    lantern_node_api_chunk_work
    xor     %eax, %eax
    UNFRAME 112
8:  mov     $404, %eax
    UNFRAME 112
END_FUNCTION lantern_node_api_blob_stream

# The blob stream rdi after a chunk that ended its item (node.md, NODE_EV_API, the blob stream):
# deneb and electra the sidecar from member + 1 on; fulu the next cell, of blob filter_slot + 1 and
# column 0 after API_STREAM_BLOB_SKIP or the first half's last column, else of column member + 1,
# with sent 0. API_STREAM_BLOB_SKIP clears. rbx the node. r12 the entry, r13 its flags.
LOCAL_FUNCTION lantern_node_blob_advance
    ENTER 0
    mov     %rdi, %r12
    mov     NodeApi_flags(%r12), %r13
    andq    $~API_STREAM_BLOB_SKIP, NodeApi_flags(%r12)
    cmpq    $FORK_FULU, NodeApi_fork(%r12)
    jae     1f
    mov     %r12, %rdi
    mov     NodeApi_member(%r12), %rsi
    inc     %rsi
    call    lantern_node_sidecar_next
    LEAVE 0
1:  mov     NodeApi_member(%r12), %rax
    mov     NodeApi_filter_slot(%r12), %rcx
    inc     %rax
    test    $API_STREAM_BLOB_SKIP, %r13
    jnz     2f
    cmp     $(NUMBER_OF_COLUMNS / 2), %rax
    jb      3f
2:  inc     %rcx
    xor     %eax, %eax
3:  mov     %rax, NodeApi_member(%r12)
    mov     %rcx, NodeApi_filter_slot(%r12)
    movq    $0, NodeApi_sent(%r12)
    lea     NodeApi_root(%r12), %rdi
    mov     NodeApi_slot(%r12), %rsi
    mov     %rax, %rdx
    call    lantern_node_sidecar_of
    mov     %rax, NodeApi_data(%r12)
    LEAVE 0
END_FUNCTION lantern_node_blob_advance

# rax = 1 when kzg_commitment_to_versioned_hash of the 48-byte commitment at rdi (deneb
# beacon-chain.md: VERSIONED_HASH_VERSION_KZG, then the last 31 bytes of its sha256) is one of the
# Root items of the ByteList rsi, else 0. Locals: the ByteList rsi, a ByteList of the commitment
# (72), the hash (32).
LOCAL_FUNCTION lantern_api_blob_wanted
    FRAME 112
    mov     %rsi, (%rsp)
    movq    $72, 8(%rsp)
    movq    $24, 16(%rsp)
    movq    $48, 24(%rsp)
    mov     %rdi, %rsi
    lea     32(%rsp), %rdi
    mov     $48, %edx
    call    lantern_copy
    lea     8(%rsp), %rdi
    lea     80(%rsp), %rsi
    CALL_GLOBAL crypto_sha256
    movb    $VERSIONED_HASH_VERSION_KZG, 80(%rsp)
    mov     (%rsp), %rsi                    # the items
    mov     8(%rsi), %rax
    add     %rsi, %rax
    mov     16(%rsi), %rcx
    shr     $5, %rcx
    lea     80(%rsp), %rdx
1:  test    %rcx, %rcx
    jz      8f
    NE32    %rax, %rdx, 2f
    mov     $1, %eax
    UNFRAME 112
2:  add     $32, %rax
    dec     %rcx
    jmp     1b
8:  xor     %eax, %eax
    UNFRAME 112
END_FUNCTION lantern_api_blob_wanted

# The blob stream's body, as lantern_api_stream_json (node.md, NODE_WORK_API_CHUNK, the blob stream): with
# the sidecar rdi and the versioned hashes rsi (or 0), the bytes of its blob, or of its cell, from
# sent (NodeEvent_api), as many as fit, as JSON in lower case hex; with rdi = 0, or a blob past the
# last, ]} as JSON. rax = 1 when the answer is whole, 0 when more is to come, 2 for bytes that are
# no encoding. Locals: the sidecar, the hashes, the piece's bytes, their count, 1 at a blob's first
# piece, 1 at its last, the offsets of column and kzg_commitments.
LOCAL_FUNCTION lantern_api_blob_body
    FRAME 64
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    test    %rdi, %rdi
    jz      90f
    mov     8(%rdi), %r8                    # the sidecar's SSZ bytes, r9 of them
    add     %rdi, %r8
    mov     16(%rdi), %r9
    cmpq    $FORK_FULU, NodeApi_fork(%rbx)
    jae     20f
    cmp     $(8 + PUB_BLOB_BYTES + 48), %r9 # deneb and electra: index, blob, kzg_commitment, ...
    jb      92f
    lea     8(%r8), %rax
    mov     %rax, 16(%rsp)
    movq    $PUB_BLOB_BYTES, 24(%rsp)
    movq    $1, 32(%rsp)
    movq    $1, 40(%rsp)
    cmpq    $0, NodeEvent_api(%rbp)         # at the blob's start, with hashes: its versioned hash
    jne     30f
    cmpq    $0, 8(%rsp)
    je      30f
    lea     (8 + PUB_BLOB_BYTES)(%r8), %rdi
    mov     8(%rsp), %rsi
    call    lantern_api_blob_wanted
    test    %rax, %rax
    jnz     30f
    jmp     88f
20: cmp     $PUB_COLUMN_FIXED, %r9          # fulu: a DataColumnSidecar; the offsets of column, kzg_commitments, kzg_proofs
    jb      92f
    mov     8(%r8), %eax
    mov     12(%r8), %ecx
    mov     16(%r8), %edx
    cmp     %rcx, %rax
    ja      92f
    cmp     %rdx, %rcx
    ja      92f
    cmp     %r9, %rdx
    ja      92f
    mov     %rax, 48(%rsp)
    mov     %rcx, 56(%rsp)
    mov     NodeApi_member(%rbx), %rax
    or      NodeEvent_api(%rbp), %rax
    jnz     22f
    mov     %rdx, %rax                      # at the blob's start: past the last commitment, the end
    sub     %rcx, %rax
    xor     %edx, %edx
    mov     $48, %ecx
    div     %rcx
    cmp     %rax, NodeApi_filter_slot(%rbx)
    jae     90f
    cmpq    $0, 8(%rsp)
    je      22f
    imul    $48, NodeApi_filter_slot(%rbx), %rdi    # with hashes: the versioned hash of commitment b
    add     56(%rsp), %rdi
    add     %r8, %rdi
    mov     8(%rsp), %rsi
    call    lantern_api_blob_wanted
    test    %rax, %rax
    jz      87f
    mov     (%rsp), %rdi
    mov     8(%rdi), %r8
    add     %rdi, %r8
22: mov     56(%rsp), %rax                  # cell b of the column
    sub     48(%rsp), %rax
    xor     %edx, %edx
    mov     $PUB_CELL_BYTES, %ecx
    div     %rcx
    mov     NodeApi_filter_slot(%rbx), %r10
    cmp     %rax, %r10
    jae     92f
    imul    $PUB_CELL_BYTES, %r10, %rax
    add     48(%rsp), %rax
    add     %r8, %rax
    mov     %rax, 16(%rsp)
    movq    $PUB_CELL_BYTES, 24(%rsp)
    xor     %eax, %eax
    cmpq    $0, NodeApi_member(%rbx)
    sete    %al
    mov     %rax, 32(%rsp)
    xor     %eax, %eax
    cmpq    $(NUMBER_OF_COLUMNS / 2 - 1), NodeApi_member(%rbx)
    sete    %al
    mov     %rax, 40(%rsp)
30: testq   $API_STREAM_SSZ, (NodeEvent_api + 8)(%rbp)  # the piece from sent
    jnz     40f
    cmpq    $0, NodeEvent_api(%rbp)         # JSON: at a blob's start , and "0x
    jne     32f
    cmpq    $0, 32(%rsp)
    je      32f
    mov     %r14, %rax
    sub     %r12, %rax
    cmp     $8, %rax
    jb      89f
    testq   $API_STREAM_ITEMS, (NodeEvent_api + 8)(%rbp)
    jz      31f
    API_LIT api_p_comma
31: API_LIT api_blob_open
32: mov     24(%rsp), %rcx                  # the hex of the bytes from sent, as many as fit before a "
    mov     NodeEvent_api(%rbp), %rax
    sub     %rax, %rcx
    mov     %r14, %rdx
    sub     %r12, %rdx
    sub     $1, %rdx
    jbe     89f
    shr     $1, %rdx
    cmp     %rdx, %rcx
    jbe     321f
    mov     %rdx, %rcx
321: mov    16(%rsp), %rsi
    add     %rax, %rsi
    add     %rcx, %rax
    mov     %rax, NodeEvent_api(%rbp)
33: test    %rcx, %rcx
    jz      34f
    movzbl  (%rsi), %eax
    inc     %rsi
    mov     %eax, %edx
    shr     $4, %edx
    and     $15, %eax
    add     $0x30, %edx
    cmp     $0x39, %edx
    jbe     331f
    add     $39, %edx
331: add    $0x30, %eax
    cmp     $0x39, %eax
    jbe     332f
    add     $39, %eax
332: mov    %dl, (%r12)
    mov     %al, 1(%r12)
    add     $2, %r12
    dec     %rcx
    jmp     33b
34: mov     NodeEvent_api(%rbp), %rax       # the piece's end: " after a blob's last byte
    cmp     24(%rsp), %rax
    jne     89f
    cmpq    $0, 40(%rsp)
    je      88f
    API_LIT api_quote
    jmp     86f
40: mov     24(%rsp), %rdx                  # SSZ: the bytes from sent, as many as fit
    mov     NodeEvent_api(%rbp), %rax
    sub     %rax, %rdx
    mov     %r14, %rcx
    sub     %r12, %rcx
    cmp     %rcx, %rdx
    jbe     41f
    mov     %rcx, %rdx
41: mov     16(%rsp), %rsi
    add     %rax, %rsi
    add     %rdx, %rax
    mov     %rax, NodeEvent_api(%rbp)
    mov     %r12, %rdi
    add     %rdx, %r12
    call    lantern_copy
    mov     NodeEvent_api(%rbp), %rax
    cmp     24(%rsp), %rax
    jne     89f
    cmpq    $0, 40(%rsp)
    je      88f
86: orq     $API_STREAM_ITEMS, (NodeEvent_api + 8)(%rbp)   # a blob's end
88: orq     $API_STREAM_ITEM_DONE, (NodeEvent_api + 8)(%rbp)   # the piece is done
89: xor     %eax, %eax
    UNFRAME 64
87: orq     $(API_STREAM_ITEM_DONE | API_STREAM_BLOB_SKIP), (NodeEvent_api + 8)(%rbp)  # a blob not wanted: skip it
    jmp     89b
90: testq   $API_STREAM_SSZ, (NodeEvent_api + 8)(%rbp)  # the end: ]} as JSON
    jnz     91f
    mov     %r14, %rax
    sub     %r12, %rax
    cmp     $2, %rax
    jb      89b
    API_LIT api_v_end
91: mov     $1, %eax
    UNFRAME 64
92: mov     $2, %eax
    UNFRAME 64
END_FUNCTION lantern_api_blob_body

/*
 * The sidecar of the sidecar stream rdi from the index rsi on (node.md, NODE_EV_API, a sidecar of a
 * sidecar stream): member, data, sent 0 and cursor zero; rax = 1, or 0 with data 0 for none. rbx
 * the node. r12 the entry, r13 the index.
 */
LOCAL_FUNCTION lantern_node_sidecar_next
    ENTER 0
    mov     %rdi, %r12
    mov     %rsi, %r13
1:  cmp     $128, %r13
    jae     8f
    mov     NodeApi_filter_slot(%r12), %rax
    mov     %r13, %rcx
    cmp     $64, %r13
    jb      2f
    mov     NodeApi_filter_index(%r12), %rax
    lea     -64(%r13), %rcx
2:  shr     %cl, %rax
    test    $1, %eax
    jz      7f
    lea     NodeApi_root(%r12), %rdi        # the node's NODE_BLOB_VALID entry, else the Db's record
    mov     %r13, %rsi
    call    lantern_node_blob_held
    test    %rax, %rax
    jz      3f
    mov     NodeBlob_data_id(%rax), %rax
    jmp     5f
3:  testq   $NODE_FLAG_DB, Node_flags(%rbx)
    jz      7f
    mov     NodeApi_slot(%r12), %rdi
    mov     %r13, %rsi
    call    lantern_node_db_sidecar
    test    %rax, %rax
    jz      7f
5:  mov     %rax, NodeApi_data(%r12)
    mov     %r13, NodeApi_member(%r12)
    movq    $0, NodeApi_sent(%r12)
    lea     NodeApi_cursor(%r12), %rdi
    mov     $JSON_CURSOR_SIZE, %esi
    call    lantern_zero
    mov     $1, %eax
    LEAVE 0
7:  inc     %r13
    jmp     1b
8:  movq    $0, NodeApi_data(%r12)
    xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_node_sidecar_next

/*
 * (connection rdi, route rsi, flags rdx, view rcx) -> rax: the sidecar stream of the block of the
 * view (node.md, NODE_EV_API): 0, or 400 for a block whose slot's fork is not the operation's. rbx
 * the node. Locals: the connection, the route, the flags, the view, the fork, the entry's index and
 * address.
 */
LOCAL_FUNCTION lantern_node_api_sidecar_stream
    FRAME 64
    mov     %rdi, (%rsp)
    mov     %rsi, 8(%rsp)
    mov     %rdx, 16(%rsp)
    mov     %rcx, 24(%rsp)
    mov     ApiView_head_slot(%rcx), %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, 32(%rsp)
    mov     8(%rsp), %rcx
    cmpq    $API_OP_GET_BLOB_SIDECARS, ApiRoute_op(%rcx)
    jne     1f
    cmp     $FORK_DENEB, %rax               # getBlobSidecars: deneb and electra
    jb      8f
    cmp     $FORK_FULU, %rax
    jae     8f
    jmp     2f
1:  cmp     $FORK_FULU, %rax                # getDebugDataColumnSidecars: fulu and later
    jb      8f
2:  call    lantern_node_api_new
    mov     %rax, 40(%rsp)
    mov     %rdx, 48(%rsp)
    mov     %rdx, %rdi
    mov     $NodeApi__mem, %esi
    call    lantern_zero
    mov     48(%rsp), %rdx
    mov     (%rsp), %rax
    mov     %rax, NodeApi_connection(%rdx)
    mov     8(%rsp), %rsi
    mov     ApiRoute_op(%rsi), %rax
    mov     %rax, NodeApi_op(%rdx)
    mov     16(%rsp), %rax                  # the answer flags, SSZ, and the block's values
    cmpq    $API_TYPE_SSZ, ApiRoute_response(%rsi)
    jne     3f
    or      $API_STREAM_SSZ, %rax
3:  mov     24(%rsp), %rcx
    cmpq    $0, ApiView_is_optimistic(%rcx)
    je      31f
    or      $API_STREAM_OPTIMISTIC, %rax
31: cmpq    $0, ApiView_head_finalized(%rcx)
    je      32f
    or      $API_STREAM_FINALIZED, %rax
32: mov     %rax, NodeApi_flags(%rdx)
    mov     32(%rsp), %rax
    mov     %rax, NodeApi_fork(%rdx)
    mov     ApiView_head_slot(%rcx), %rax
    mov     %rax, NodeApi_slot(%rdx)
    lea     NodeApi_root(%rdx), %rdi
    lea     ApiView_head_root(%rcx), %rsi
    COPY32  %rdi, %rsi
    mov     8(%rsp), %rsi                   # the indices: their bits, all with none
    mov     $-1, %r8
    mov     $-1, %r9
    testq   $(1 << API_PARAM_INDICES), ApiRoute_present(%rsi)
    jz      6f
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    PART    %r10, %r11, %rsi, ApiRoute_list
5:  test    %r11, %r11
    jz      6f
    mov     (%r10), %rcx
    add     $8, %r10
    dec     %r11
    cmp     $128, %rcx
    jae     5b
    mov     $1, %eax
    cmp     $64, %rcx
    jae     51f
    shl     %cl, %rax
    or      %rax, %r8
    jmp     5b
51: sub     $64, %rcx
    shl     %cl, %rax
    or      %rax, %r9
    jmp     5b
6:  mov     %r8, NodeApi_filter_slot(%rdx)
    mov     %r9, NodeApi_filter_index(%rdx)
    mov     %rdx, %rdi
    xor     %esi, %esi
    call    lantern_node_sidecar_next
    mov     40(%rsp), %rax
    mov     48(%rsp), %rdx
    call    lantern_node_api_chunk_work
    xor     %eax, %eax
    UNFRAME 64
8:  mov     $400, %eax
    UNFRAME 64
END_FUNCTION lantern_node_api_sidecar_stream

/*
 * A sidecar stream's body, as lantern_api_stream_json (node.md, NODE_WORK_API_CHUNK, the sidecar streams):
 * with the bytes rdi, as JSON the JSON of the sidecar from the cursor at NodeEvent_api + 16 by
 * lantern_node_json of the entry's fork and the kind of the operation, after , when API_STREAM_ITEMS
 * is set and the cursor is at its start; as SSZ its bytes from sent (NodeEvent_api), as many as fit;
 * at the sidecar's end API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With rdi = 0: ]} as
 * JSON, nothing as SSZ. rax = 1 when the answer is whole, 0 when more is to come, 2 for bytes that
 * are no encoding. Locals: the bytes.
 */
LOCAL_FUNCTION lantern_api_sidecar_body
    FRAME 16
    mov     %rdi, (%rsp)
    test    %rdi, %rdi
    jnz     1f
    testq   $API_STREAM_SSZ, (NodeEvent_api + 8)(%rbp)
    jnz     9f
    API_LIT api_v_end
9:  mov     $1, %eax
    UNFRAME 16
1:  testq   $API_STREAM_SSZ, (NodeEvent_api + 8)(%rbp)
    jz      3f
    mov     8(%rdi), %rsi                   # SSZ: the bytes from sent, as many as fit
    add     %rdi, %rsi
    mov     16(%rdi), %rdx
    mov     NodeEvent_api(%rbp), %rax
    sub     %rax, %rdx
    mov     %r14, %rcx
    sub     %r12, %rcx
    cmp     %rcx, %rdx
    jbe     11f
    mov     %rcx, %rdx
11: add     %rax, %rsi
    add     %rdx, %rax
    mov     %rax, NodeEvent_api(%rbp)
    mov     %r12, %rdi
    add     %rdx, %r12
    call    lantern_copy
    mov     (%rsp), %rdi
    mov     NodeEvent_api(%rbp), %rax
    cmp     16(%rdi), %rax
    jne     2f
    orq     $(API_STREAM_ITEMS | API_STREAM_ITEM_DONE), (NodeEvent_api + 8)(%rbp)
2:  xor     %eax, %eax
    UNFRAME 16
3:  cmpq    $0, (NodeEvent_api + 16)(%rbp)  # JSON: the cursor's depth, 0 before the first byte
    jne     4f
    testq   $API_STREAM_ITEMS, (NodeEvent_api + 8)(%rbp)
    jz      4f
    API_LIT api_p_comma
4:  mov     $NODE_JSON_BLOB_SIDECAR, %edi
    cmpq    $API_OP_GET_BLOB_SIDECARS, NodeApi_op(%rbx)
    je      5f
    mov     $NODE_JSON_DATA_COLUMN_SIDECAR, %edi
5:  lea     NodeEvent_api_bytes(%rbp), %rsi # the ByteList: its room to r14 - 1, its bytes to r12
    lea     -1(%r14), %rax
    sub     %rsi, %rax
    mov     %rax, (%rsi)
    movq    $24, 8(%rsi)
    mov     %r12, %rax
    sub     %rsi, %rax
    sub     $24, %rax
    mov     %rax, 16(%rsi)
    mov     (%rsp), %rsi
    lea     (NodeEvent_api + 16)(%rbp), %rdx
    lea     NodeEvent_api_bytes(%rbp), %rcx
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_json
    mov     (NodeEvent_api_bytes + 16)(%rbp), %r12
    lea     (NodeEvent_api_bytes + 24)(%rbp,%r12), %r12
    cmp     $LANTERN_JSON_MORE, %rax
    je      8f
    test    %rax, %rax
    jnz     7f
    orq     $(API_STREAM_ITEMS | API_STREAM_ITEM_DONE), (NodeEvent_api + 8)(%rbp)
8:  xor     %eax, %eax
    UNFRAME 16
7:  mov     $2, %eax
    UNFRAME 16
END_FUNCTION lantern_api_sidecar_body

/*
 * The pool stream of the NodeApi entry rdi goes to its next entry after slot (node.md,
 * NODE_WORK_API_CHUNK): its slot, data, sent and member, a zero cursor; data 0 with none. Bytes it owned
 * get a NODE_ACT_BYTES_FREE, and API_STREAM_OWN clears. Locals: the entry, the old data, the flags.
 */
LOCAL_FUNCTION lantern_node_api_pool_advance
    FRAME 32
    mov     %rdi, (%rsp)
    mov     NodeApi_data(%rdi), %rax
    mov     %rax, 8(%rsp)
    mov     NodeApi_flags(%rdi), %rax
    mov     %rax, 16(%rsp)
    mov     %rdi, %rsi
    mov     NodeApi_slot(%rdi), %rdi
    inc     %rdi
    call    lantern_node_pool_next
    mov     (%rsp), %rcx
    xor     %r8d, %r8d
    cmp     $-1, %rax
    je      1f
    mov     %rax, NodeApi_slot(%rcx)
    mov     NodePool_fork(%rdx), %rax
    mov     %rax, NodeApi_sent(%rcx)
    mov     NodePool_member(%rdx), %rax
    mov     %rax, NodeApi_member(%rcx)
    mov     NodePool_data_id(%rdx), %r8
1:  mov     %r8, NodeApi_data(%rcx)
    andq    $~API_STREAM_OWN, NodeApi_flags(%rcx)
    testq   $API_STREAM_FOLD, NodeApi_flags(%rcx)   # API_STREAM_FOLD: the cursor holds the aggregate
    jnz     2f
    lea     NodeApi_cursor(%rcx), %rdi
    mov     $JSON_CURSOR_SIZE, %esi
    call    lantern_zero
2:  testq   $API_STREAM_OWN, 16(%rsp)       # API_STREAM_OWN: the old bytes go
    jz      9f
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     8(%rsp), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
9:  UNFRAME 32
END_FUNCTION lantern_node_api_pool_advance

/*
 * (scratch rdi, data rsi) -> rax: the pool entry's bytes data folded into the aggregate in the
 * cursor at NodeEvent_api + 16 of the event rbp (node.md, getAggregatedAttestationV2), rbx the
 * entry: of the fork in sent a SingleAttestation (place and length from member) or an Attestation
 * (place its bit, length that of its bits); with data of the root at byte 0, a place not taken,
 * and the length of the aggregate, its bit at byte 272 and its signature added at byte 176 by
 * crypto_bls_aggregate; the first gives the length (40), data (48) and signature; byte 32 counts
 * them. rax = 0; 1 for bytes that are no attestation or a signature crypto_bls_aggregate rejects;
 * 2 for a short scratch. Locals: scratch, data, signature, length, place, the root (then the list).
 */
LOCAL_FUNCTION lantern_node_api_fold
    FRAME 80
    mov     %rdi, (%rsp)
    mov     8(%rsi), %rax
    add     %rsi, %rax                      # the bytes and their count
    mov     16(%rsi), %rcx
    cmpq    $FORK_ELECTRA, NodeApi_sent(%rbx)
    jb      1f
    cmp     $240, %rcx                      # a SingleAttestation: data at 16, signature at 144
    jne     71f
    lea     16(%rax), %rdx
    lea     144(%rax), %rsi
    mov     NodeApi_member(%rbx), %r8
    movzwl  %r8w, %r9d
    shr     $16, %r8
    jmp     3f
1:  cmp     $(228 + 1), %rcx                # an Attestation: offset 228, data at 4, signature at 132, its bits
    jb      71f
    cmp     $(228 + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1), %rcx
    ja      71f
    cmpl    $228, (%rax)
    jne     71f
    lea     4(%rax), %rdx
    lea     132(%rax), %rsi
    lea     228(%rax), %rdi
    lea     -229(%rcx), %r10                # the last byte: its highest bit is the length's
    movzbl  (%rdi,%r10), %r11d
    test    %r11d, %r11d
    jz      71f
    bsr     %r11d, %r11d
    lea     (%r11,%r10,8), %r8
    xor     %r9d, %r9d                      # the place: the first bit set
2:  cmp     %r8, %r9
    jae     71f
    mov     %r9, %rcx
    shr     $3, %rcx
    movzbl  (%rdi,%rcx), %eax
    mov     %r9d, %ecx
    and     $7, %ecx
    bt      %ecx, %eax
    jc      3f
    inc     %r9
    jmp     2b
3:  cmp     $MAX_VALIDATORS_PER_COMMITTEE, %r8
    ja      71f
    cmp     %r8, %r9
    jae     71f
    mov     %rdx, 8(%rsp)
    mov     %rsi, 16(%rsp)
    mov     %r8, 24(%rsp)
    mov     %r9, 32(%rsp)
    mov     %rdx, %rdi                      # the root of its data: that of the cursor, else not in the aggregate
    mov     (%rsp), %rsi
    lea     40(%rsp), %rdx
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_data_root
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      72f
    test    %rax, %rax
    jnz     71f
    lea     40(%rsp), %rdi
    lea     (NodeEvent_api + 16)(%rbp), %rsi
    NE32    %rdi, %rsi, 70f
    mov     24(%rsp), %r8
    cmpq    $0, (NodeEvent_api + 16 + 32)(%rbp)
    jne     4f
    mov     %r8, (NodeEvent_api + 16 + 40)(%rbp)    # the first: its length, data and signature
    lea     (NodeEvent_api + 16 + 48)(%rbp), %rdi
    mov     8(%rsp), %rsi
    mov     $128, %edx
    call    lantern_copy
    lea     (NodeEvent_api + 16 + 176)(%rbp), %rdi
    mov     16(%rsp), %rsi
    mov     $96, %edx
    call    lantern_copy
    jmp     6f
4:  cmp     (NodeEvent_api + 16 + 40)(%rbp), %r8    # a later one: the same length, a place not taken
    jne     70f
    mov     32(%rsp), %r9
    mov     %r9, %rcx
    shr     $3, %rcx
    movzbl  (NodeEvent_api + 16 + 272)(%rbp,%rcx), %eax
    mov     %r9d, %ecx
    and     $7, %ecx
    bt      %ecx, %eax
    jc      70f
    mov     (%rsp), %rdi                    # the two signatures: a BlsSignatureList at the end of scratch
    mov     (%rdi), %rax
    cmp     $(24 + 2 * 96 + 8), %rax
    jb      72f
    sub     $(24 + 2 * 96), %rax
    and     $~7, %rax
    add     %rdi, %rax
    mov     %rax, 40(%rsp)
    movq    $(24 + 2 * 96), (%rax)
    movq    $24, 8(%rax)
    movq    $2, 16(%rax)
    lea     24(%rax), %rdi
    lea     (NodeEvent_api + 16 + 176)(%rbp), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     40(%rsp), %rdi
    add     $(24 + 96), %rdi
    mov     16(%rsp), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     40(%rsp), %rdi
    lea     (NodeEvent_api + 16 + 176)(%rbp), %rsi
    CALL_GLOBAL crypto_bls_aggregate
    test    %rax, %rax
    jnz     71f
6:  mov     32(%rsp), %r9                   # its place's bit; one more
    mov     %r9, %rdx
    shr     $3, %rdx
    lea     (NodeEvent_api + 16 + 272)(%rbp,%rdx), %rdx
    mov     %r9d, %ecx
    and     $7, %ecx
    mov     $1, %eax
    shl     %cl, %eax
    or      %al, (%rdx)
    incq    (NodeEvent_api + 16 + 32)(%rbp)
70: xor     %eax, %eax
    UNFRAME 80
71: mov     $1, %eax
    UNFRAME 80
72: mov     $2, %eax
    UNFRAME 80
END_FUNCTION lantern_node_api_fold
.if MAX_VALIDATORS_PER_COMMITTEE > 2048 || 48 + 128 + 96 + 2048 / 8 > JSON_CURSOR_SIZE
.error "node_api_fold: the aggregate's bits fit the cursor from byte 272"
.endif

.set API_SYNC_SUBCOMMITTEE_SIZE, SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT

/*
 * (scratch rdi, data rsi, state rdx) -> rax: the pool entry's bytes data, a SyncCommitteeMessage,
 * folded into the contribution in the cursor at NodeEvent_api + 16 of the event rbp (node.md,
 * produceSyncCommitteeContribution), rbx the entry, state the head's post-state: with the
 * beacon_block_root at byte 0, and none of its places in the subcommittee filter_index
 * (lantern_node_sync_positions of the fork `fork`) set in the bits at byte 144, each of them is
 * set and its signature added at byte 48 once for each (crypto_bls_aggregate); byte 32 counts
 * them. rax = 0; 1 for bytes of another size, no state, or a signature crypto_bls_aggregate
 * rejects; 2 for a short scratch. Locals: scratch, the state, the bytes, the places
 * (SYNC_COMMITTEE_SIZE / 8 bytes), the subcommittee's places, the place, the list.
 */
LOCAL_FUNCTION lantern_node_api_sync_fold
    FRAME 128
    mov     %rdi, (%rsp)
    cmpq    $144, 16(%rsi)
    jne     71f
    test    %rdx, %rdx
    jz      71f
    mov     %rdx, 8(%rsp)
    mov     8(%rsi), %rax
    add     %rsi, %rax
    mov     %rax, 16(%rsp)
    lea     8(%rax), %rdi                   # its beacon_block_root: the contribution's, else not in it
    lea     (NodeEvent_api + 16)(%rbp), %rsi
    NE32    %rdi, %rsi, 70f
    mov     8(%rsp), %rdi                   # its places
    mov     16(%rsp), %rax
    mov     40(%rax), %rsi
    lea     32(%rsp), %rdx
    mov     NodeApi_fork(%rbx), %r10
    FORK_CALL node_sync_positions
    test    %rax, %rax
    jnz     71f
    mov     NodeApi_filter_index(%rbx), %rax    # those of the subcommittee: none taken, one at least
    imul    $(API_SYNC_SUBCOMMITTEE_SIZE / 8), %rax, %rax
    lea     32(%rsp,%rax), %rax
    mov     %rax, 96(%rsp)
    xor     %ecx, %ecx
    xor     %edx, %edx
1:  cmp     $(API_SYNC_SUBCOMMITTEE_SIZE / 8), %rcx
    jae     2f
    movzbl  (%rax,%rcx), %r8d
    movzbl  (NodeEvent_api + 16 + 144)(%rbp,%rcx), %r9d
    test    %r8d, %r9d
    jnz     70f
    or      %r8d, %edx
    inc     %rcx
    jmp     1b
2:  test    %edx, %edx
    jz      70f
    movq    $0, 104(%rsp)
3:  mov     104(%rsp), %rcx                 # each place: its bit, its signature once more
    cmp     $API_SYNC_SUBCOMMITTEE_SIZE, %rcx
    jae     70f
    mov     96(%rsp), %rax
    mov     %rcx, %rdx
    shr     $3, %rdx
    movzbl  (%rax,%rdx), %eax
    and     $7, %ecx
    shr     %cl, %eax
    test    $1, %al
    jz      6f
    mov     104(%rsp), %rcx
    mov     %rcx, %rdx
    shr     $3, %rdx
    and     $7, %ecx
    mov     $1, %eax
    shl     %cl, %eax
    or      %al, (NodeEvent_api + 16 + 144)(%rbp,%rdx)
    cmpq    $0, (NodeEvent_api + 16 + 32)(%rbp)
    jne     4f
    lea     (NodeEvent_api + 16 + 48)(%rbp), %rdi   # the first: its signature
    mov     16(%rsp), %rsi
    add     $48, %rsi
    mov     $96, %edx
    call    lantern_copy
    jmp     5f
4:  mov     (%rsp), %rdi                    # else the two signatures: a BlsSignatureList at the end of scratch
    mov     (%rdi), %rax
    cmp     $(24 + 2 * 96 + 8), %rax
    jb      72f
    sub     $(24 + 2 * 96), %rax
    and     $~7, %rax
    add     %rdi, %rax
    mov     %rax, 112(%rsp)
    movq    $(24 + 2 * 96), (%rax)
    movq    $24, 8(%rax)
    movq    $2, 16(%rax)
    lea     24(%rax), %rdi
    lea     (NodeEvent_api + 16 + 48)(%rbp), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     112(%rsp), %rdi
    add     $(24 + 96), %rdi
    mov     16(%rsp), %rsi
    add     $48, %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     112(%rsp), %rdi
    lea     (NodeEvent_api + 16 + 48)(%rbp), %rsi
    CALL_GLOBAL crypto_bls_aggregate
    test    %rax, %rax
    jnz     71f
5:  incq    (NodeEvent_api + 16 + 32)(%rbp)
6:  incq    104(%rsp)
    jmp     3b
70: xor     %eax, %eax
    UNFRAME 128
71: mov     $1, %eax
    UNFRAME 128
72: mov     $2, %eax
    UNFRAME 128
END_FUNCTION lantern_node_api_sync_fold
.if SYNC_COMMITTEE_SIZE / 8 > 64 || API_SYNC_SUBCOMMITTEE_SIZE % 8 || 144 + API_SYNC_SUBCOMMITTEE_SIZE / 8 > JSON_CURSOR_SIZE
.error "node_api_sync_fold: the places fit its locals, a subcommittee's places are whole bytes"
.endif

/*
 * (out rdi) -> rax: the contribution in the cursor at NodeEvent_api + 16 of the event rbp as the
 * SSZ bytes of a SyncCommitteeContribution at out, rdx their count (node.md,
 * produceSyncCommitteeContribution): slot filter_slot, the beacon_block_root, subcommittee_index
 * filter_index of the entry rbx, the bits, the signature. rax = 0. Locals: out.
 */
LOCAL_FUNCTION lantern_node_api_contribution
    FRAME 16
    mov     %rdi, (%rsp)
    mov     NodeApi_filter_slot(%rbx), %rax
    mov     %rax, (%rdi)
    add     $8, %rdi
    lea     (NodeEvent_api + 16)(%rbp), %rsi
    mov     $32, %edx
    call    lantern_copy
    mov     (%rsp), %rdi
    mov     NodeApi_filter_index(%rbx), %rax
    mov     %rax, 40(%rdi)
    add     $48, %rdi
    lea     (NodeEvent_api + 16 + 144)(%rbp), %rsi
    mov     $(API_SYNC_SUBCOMMITTEE_SIZE / 8), %edx
    call    lantern_copy
    mov     (%rsp), %rdi
    add     $(48 + API_SYNC_SUBCOMMITTEE_SIZE / 8), %rdi
    lea     (NodeEvent_api + 16 + 48)(%rbp), %rsi
    mov     $96, %edx
    call    lantern_copy
    mov     $(48 + API_SYNC_SUBCOMMITTEE_SIZE / 8 + 96), %edx
    xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_node_api_contribution

/*
 * (out rdi) -> rax: the aggregate in the cursor at NodeEvent_api + 16 of the event rbp as the SSZ
 * bytes of the Attestation of the fork of the entry rbx at out, rdx their count (node.md,
 * getAggregatedAttestationV2): aggregation_bits of the cursor's length with its bits, data,
 * signature; from electra committee_bits with the bit of filter_index. rax = 0; 1 for a committee
 * index not below MAX_COMMITTEES_PER_SLOT. Locals: out, the fixed part's size, the count.
 */
LOCAL_FUNCTION lantern_node_api_aggregate
    FRAME 32
    mov     %rdi, (%rsp)
    mov     $228, %ecx                      # the fixed part: 228 bytes, from electra with committee_bits
    cmpq    $FORK_ELECTRA, NodeApi_fork(%rbx)
    jb      1f
    mov     $NODE_POOL_ATTESTATION_FIXED, %ecx
1:  mov     %rcx, 8(%rsp)
    mov     (NodeEvent_api + 16 + 40)(%rbp), %rax   # the bits' bytes, with the length's bit
    shr     $3, %rax
    lea     1(%rcx,%rax), %rsi
    mov     %rsi, 16(%rsp)
    call    lantern_zero
    mov     (%rsp), %rdi
    mov     8(%rsp), %rax
    mov     %eax, (%rdi)                    # the offset of aggregation_bits, data and signature
    add     $4, %rdi
    lea     (NodeEvent_api + 16 + 48)(%rbp), %rsi
    mov     $(128 + 96), %edx
    call    lantern_copy
    cmpq    $228, 8(%rsp)
    je      2f
    mov     NodeApi_filter_index(%rbx), %rax    # committee_bits
    cmp     $MAX_COMMITTEES_PER_SLOT, %rax
    jae     71f
    mov     (%rsp), %rdx
    mov     %rax, %rcx
    shr     $3, %rcx
    lea     228(%rdx,%rcx), %rdx
    mov     %eax, %ecx
    and     $7, %ecx
    mov     $1, %eax
    shl     %cl, %eax
    or      %al, (%rdx)
2:  mov     (%rsp), %rdi                    # the bits, then the length's bit
    add     8(%rsp), %rdi
    lea     (NodeEvent_api + 16 + 272)(%rbp), %rsi
    mov     (NodeEvent_api + 16 + 40)(%rbp), %rdx
    add     $7, %rdx
    shr     $3, %rdx
    call    lantern_copy
    mov     (%rsp), %rdx
    add     8(%rsp), %rdx
    mov     (NodeEvent_api + 16 + 40)(%rbp), %rax
    mov     %rax, %rcx
    shr     $3, %rcx
    add     %rcx, %rdx
    mov     %eax, %ecx
    and     $7, %ecx
    mov     $1, %eax
    shl     %cl, %eax
    or      %al, (%rdx)
    mov     16(%rsp), %rdx
    xor     %eax, %eax
    UNFRAME 32
71: mov     $1, %eax
    UNFRAME 32
END_FUNCTION lantern_node_api_aggregate
.if NODE_API_FIRST_ROOM < API_HEAD_ROOM + NODE_POOL_ATTESTATION_FIXED + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1
.error "node_api_aggregate: an Attestation of one committee fits the first chunk"
.endif

/*
 * A pool stream's JSON, as lantern_api_stream_json: with the bytes rdi, the JSON of the pool entry from
 * the cursor at NodeEvent_api + 16, by lantern_node_json of the fork in sent (NodeEvent_api) and
 * the kind of the GET, after , when API_STREAM_ITEMS is set and the cursor is at its start; once
 * whole, API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With rdi = 0: ]}. rax = 1 when
 * the answer is whole, 0 when more is to come, 2 for bytes that are no encoding. Locals: the bytes.
 */
LOCAL_FUNCTION lantern_api_pool_json
    FRAME 16
    mov     %rdi, (%rsp)
    test    %rdi, %rdi
    jnz     1f
    API_LIT api_v_end
    mov     $1, %eax
    UNFRAME 16
1:  cmpq    $0, (NodeEvent_api + 16)(%rbp)  # the cursor's depth: 0 before the first byte
    jne     2f
    testq   $API_STREAM_ITEMS, (NodeEvent_api + 8)(%rbp)
    jz      2f
    API_LIT api_p_comma
2:  mov     NodeApi_op(%rbx), %rax          # the kind of the GET's operation
    mov     $NODE_JSON_EXIT, %edi
    cmp     $API_OP_GET_POOL_VOLUNTARY_EXITS, %rax
    je      3f
    mov     $NODE_JSON_PROPOSER_SLASHING, %edi
    cmp     $API_OP_GET_POOL_PROPOSER_SLASHINGS, %rax
    je      3f
    mov     $NODE_JSON_ATTESTER_SLASHING, %edi
    cmp     $API_OP_GET_POOL_ATTESTER_SLASHINGS_V2, %rax
    je      3f
    mov     $NODE_JSON_ATTESTATION, %edi
    cmp     $API_OP_GET_POOL_ATTESTATIONS_V2, %rax
    je      3f
    mov     $NODE_JSON_BLS_CHANGE, %edi
3:  lea     NodeEvent_api_bytes(%rbp), %rsi # the ByteList: its room to r14 - 1, its bytes to r12
    lea     -1(%r14), %rax
    sub     %rsi, %rax
    mov     %rax, (%rsi)
    movq    $24, 8(%rsi)
    mov     %r12, %rax
    sub     %rsi, %rax
    sub     $24, %rax
    mov     %rax, 16(%rsi)
    mov     (%rsp), %rsi
    lea     (NodeEvent_api + 16)(%rbp), %rdx
    lea     NodeEvent_api_bytes(%rbp), %rcx
    mov     NodeEvent_api(%rbp), %r10
    FORK_CALL node_json
    mov     (NodeEvent_api_bytes + 16)(%rbp), %r12
    lea     (NodeEvent_api_bytes + 24)(%rbp,%r12), %r12
    cmp     $LANTERN_JSON_MORE, %rax
    je      8f
    test    %rax, %rax
    jnz     7f
    orq     $(API_STREAM_ITEMS | API_STREAM_ITEM_DONE), (NodeEvent_api + 8)(%rbp)   # whole: the entry is done
8:  xor     %eax, %eax
    UNFRAME 16
7:  mov     $2, %eax
    UNFRAME 16
END_FUNCTION lantern_api_pool_json

/*
 * The failures of the event rbp of a NODE_WORK_API_SUBMIT: {"index":<i>,"message":"REJECT"} for
 * each record of LANTERN_GOSSIP_REJECT, with , between, then ]}. Locals: the record, its index,
 * the failures written.
 */
LOCAL_FUNCTION lantern_api_failures
    FRAME 32
    mov     (NodeEvent_chunk + 8)(%rbp), %rax
    lea     NodeEvent_chunk(%rbp,%rax), %rax
    mov     %rax, (%rsp)
    movq    $0, 8(%rsp)
    movq    $0, 16(%rsp)
1:  mov     8(%rsp), %rax
    cmp     NodeEvent_index(%rbp), %rax
    jae     9f
    mov     (%rsp), %rax
    cmpq    $LANTERN_GOSSIP_REJECT, (%rax)
    jne     3f
    cmpq    $0, 16(%rsp)
    je      2f
    API_LIT api_p_comma
2:  API_LIT api_f_index
    mov     8(%rsp), %rdi
    call    lantern_api_dec
    API_LIT api_f_reject
    incq    16(%rsp)
3:  mov     (%rsp), %rax                    # the next record: its code, its subnet, then its ByteList
    mov     16(%rax), %rcx
    lea     16(%rax,%rcx), %rax
    mov     %rax, (%rsp)
    incq    8(%rsp)
    jmp     1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION lantern_api_failures

/*
 * (connection rdi, route rsi, flags rdx, request rcx, view r8) -> rax: a pool POST (node.md,
 * NODE_EV_API): a NODE_ACT_BYTES_PUT of the body and a NODE_WORK_API_SUBMIT; 0 once queued, else
 * the status of the error to answer. Locals: the connection, the flags, the route, the view, the
 * head's post-state, a ByteList head whose offset reaches the body.
 */
LOCAL_FUNCTION lantern_node_api_submit
    FRAME 64
    mov     %rdi, (%rsp)
    mov     %rdx, 8(%rsp)
    mov     %rsi, 16(%rsp)
    mov     %r8, 24(%rsp)
    cmpq    $API_TYPE_SSZ, ApiRoute_body(%rsi)  # an SSZ body: an answer flag
    jne     11f
    orq     $API_ANSWER_SSZ, 8(%rsp)
11: cmpq    $API_OP_SUBMIT_POOL_ATTESTATIONS_V2, ApiRoute_op(%rsi)  # the AttesterSlashing, attestation or aggregate type of the store's fork
    je      12f
    cmpq    $API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2, ApiRoute_op(%rsi)
    je      12f
    cmpq    $API_OP_SUBMIT_POOL_ATTESTER_SLASHINGS_V2, ApiRoute_op(%rsi)
    jne     1f
12:
    xor     %eax, %eax
    cmpq    $FORK_ELECTRA, ApiRoute_consensus_version(%rsi)
    setae   %al
    xor     %edx, %edx
    cmpq    $FORK_ELECTRA, ApiView_fork(%r8)
    setae   %dl
    cmp     %rax, %rdx
    jne     80f
1:  mov     (HttpRequest_body + 8)(%rcx), %rax  # a body of no bytes: 400
    test    %rax, %rax
    jz      80f
    mov     HttpRequest_body(%rcx), %rdx
    add     %rcx, %rdx
    lea     40(%rsp), %rdi
    sub     %rdi, %rdx
    mov     %rax, 40(%rsp)
    mov     %rdx, 48(%rsp)
    mov     %rax, 56(%rsp)
    lea     Node_head_root(%rbx), %rdi      # the head's post-state, else 500
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      81f
    mov     NodeBlock_state_id(%rdx), %rax
    test    %rax, %rax
    jz      81f
    mov     %rax, 32(%rsp)
    lea     40(%rsp), %rdi
    call    lantern_node_put
    mov     %rax, %rcx
    mov     $NODE_WORK_API_SUBMIT, %edi
    mov     32(%rsp), %rsi
    xor     %edx, %edx
    mov     (%rsp), %r8
    mov     16(%rsp), %rax
    mov     ApiRoute_op(%rax), %r9
    mov     8(%rsp), %rax
    shl     $8, %rax
    or      %rax, %r9
    mov     24(%rsp), %rax
    mov     ApiView_fork(%rax), %rax
    shl     $16, %rax
    or      %rax, %r9
    call    lantern_node_work
    xor     %eax, %eax
    UNFRAME 64
80: mov     $400, %eax
    UNFRAME 64
81: mov     $500, %eax
    UNFRAME 64
END_FUNCTION lantern_node_api_submit

/*
 * rax = 0 when the NODE_EV_WORK_DONE rdi of rcx bytes of a valid NODE_WORK_API_SUBMIT holds its
 * records inside it (node.md): a ByteList at NodeEvent_chunk of offset 24, and NodeEvent_index
 * records in its bytes, each a code and a ByteList of offset 24 whose size is a multiple of 8;
 * else 1. Uses rdx, rsi.
 */
LOCAL_FUNCTION lantern_node_submit_check
    UNWIND_END_PROLOGUE
    cmp     $(NodeEvent_chunk + 24), %rcx
    jb      8f
    cmpq    $24, (NodeEvent_chunk + 8)(%rdi)
    jne     8f
    lea     -(NodeEvent_chunk + 24)(%rcx), %rax
    cmp     %rax, (NodeEvent_chunk + 16)(%rdi)
    ja      8f
    lea     (NodeEvent_chunk + 24)(%rdi), %rsi  # the first record
    mov     NodeEvent_index(%rdi), %rdx
1:  test    %rdx, %rdx
    jz      7f
    mov     (NodeEvent_chunk + 16)(%rdi), %rax  # the bytes left
    lea     (NodeEvent_chunk + 24)(%rdi,%rax), %rax
    sub     %rsi, %rax
    cmp     $40, %rax
    jb      8f
    sub     $16, %rax                       # its ByteList, after the code and the subnet
    cmp     %rax, 16(%rsi)
    ja      8f
    cmpq    $24, 24(%rsi)
    jne     8f
    mov     16(%rsi), %rax
    cmp     $24, %rax
    jb      8f
    test    $7, %al
    jnz     8f
    sub     $24, %rax
    cmp     %rax, 32(%rsi)
    ja      8f
    mov     16(%rsi), %rax
    lea     16(%rsi,%rax), %rsi
    dec     %rdx
    jmp     1b
7:  xor     %eax, %eax
    ret
8:  mov     $1, %eax
    ret
END_FUNCTION lantern_node_submit_check

/*
 * The ProposerPreparation at rdi (beacon-api.md, prepareBeaconProposer): the NodeProposer of its
 * validator_index takes its fee_recipient and the store rbp's epoch + 3 as until_epoch; with none,
 * the first entry whose until_epoch is at most that epoch, else a new one when the part has room;
 * else none. Locals: the item, the epoch.
 */
LOCAL_FUNCTION lantern_node_proposer_put
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rbp, %rdi
    call    lantern_node_store_slot
    xor     %edx, %edx
    mov     $SLOTS_PER_EPOCH, %ecx
    div     %rcx
    mov     %rax, 8(%rsp)
    mov     (%rsp), %rsi
    mov     (%rsi), %r8                     # validator_index
    PART    %r9, %r10, %rbx, Node_proposers
    xor     %r11d, %r11d
    xor     %edx, %edx                      # the first free entry, or 0
1:  cmp     %r10, %r11
    jae     3f
    cmp     %r8, NodeProposer_validator_index(%r9)
    je      5f
    test    %rdx, %rdx
    jnz     2f
    cmp     %rax, NodeProposer_until_epoch(%r9)
    ja      2f
    cmpq    $0, NodeProposer_registered(%r9)
    jne     2f
    mov     %r9, %rdx
2:  add     $NodeProposer__mem, %r9
    inc     %r11
    jmp     1b
3:  mov     %rdx, %r9                       # none of its index: a free entry, else a new one
    test    %r9, %r9
    jnz     5f
    mov     Node_p2p_out(%rbx), %rax        # the capacity: up to the next part
    sub     Node_proposers(%rbx), %rax
    xor     %edx, %edx
    mov     $NodeProposer__mem, %ecx
    div     %rcx
    cmp     %rax, %r10
    jae     9f
    PART    %r9, %rcx, %rbx, Node_proposers
    imul    $NodeProposer__mem, %r10, %rax
    add     %rax, %r9
    inc     %r10
    mov     %r10, (Node_proposers + 8)(%rbx)
    movq    $0, NodeProposer_registered(%r9)    # a new entry: no registration
5:  mov     %r8, NodeProposer_validator_index(%r9)
    mov     8(%rsp), %rax
    add     $3, %rax
    mov     %rax, NodeProposer_until_epoch(%r9)
    lea     NodeProposer_fee_recipient(%r9), %rdi
    mov     (%rsp), %rsi
    add     $8, %rsi
    mov     $20, %edx
    call    lantern_copy
9:  UNFRAME 16
END_FUNCTION lantern_node_proposer_put

/*
 * The NODE_EV_WORK_DONE rdi of a NODE_WORK_API_SUBMIT (node.md, lantern_node_step): the body's
 * bytes go; each valid operation joins the pool, goes out on its topic with NODE_FLAG_SUBSCRIBED,
 * and an attester slashing to fork choice; then the answer to the connection. rbx the node, rbp
 * the store, r15 the actions. r12 the event, r13 the record, S7 the records left, S8 the failures,
 * S9 the topic, S10 the new id. Locals: L 1 when the pool keeps it, L+8 the answer's flags,
 * L+16 an attestation's slot, committee index and member.
 */
LOCAL_FUNCTION lantern_node_api_submit_done
    ENTER 48
    mov     %rdi, %r12
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     NodeAction_data(%r12), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
    mov     NodeAction_arg(%r12), %rax      # the answer's flags: API_STREAM_CLOSE (1), API_STREAM_HTTP10 (2)
    shr     $8, %rax
    mov     $API_R_CLOSE, %ecx
    test    $API_STREAM_CLOSE, %al
    jnz     1f
    xor     %ecx, %ecx
    test    $API_STREAM_HTTP10, %al
    jz      1f
    mov     $API_R_KEEP, %ecx
1:  mov     %rcx, (L + 8)(%rsp)
    movzbl  NodeAction_arg(%r12), %edi
    call    lantern_node_submit_topic
    mov     %rax, S9(%rsp)
    cmpq    $0, NodeEvent_result(%r12)
    jne     80f
    movq    $0, S8(%rsp)
    mov     NodeEvent_index(%r12), %rax
    mov     %rax, S7(%rsp)
    mov     (NodeEvent_chunk + 8)(%r12), %r13
    lea     NodeEvent_chunk(%r12,%r13), %r13
2:  cmpq    $0, S7(%rsp)
    je      70f
    mov     (%r13), %rax                    # its code
    cmp     $LANTERN_GOSSIP_REJECT, %rax
    jne     21f
    incq    S8(%rsp)
21: test    %rax, %rax
    jnz     6f
    cmpq    $0, S9(%rsp)                    # no topic: a subscription
    je      40f
    lea     16(%r13), %rdi                  # valid: its bytes to a new id, kept by the pool when it has room
    call    lantern_node_put
    mov     %rax, S10(%rsp)
    mov     S9(%rsp), %rdi                  # its event (node.md, The events), before its bytes go
    mov     %rax, %rsi
    mov     NodeAction_arg(%r12), %rdx
    shr     $16, %rdx
    call    lantern_node_op_event
    xor     %eax, %eax                      # the metrics (metrics.md): an attestation that goes out
    cmpq    $GOSSIP_BEACON_ATTESTATION, S9(%rsp)
    sete    %al
    add     %rax, (Node_metrics + NodeMetrics_attestations_published)(%rbx)
    mov     8(%r13), %rax                   # an attestation: its slot and committee index, its member
    shr     $32, %rax
    mov     %rax, (L + 32)(%rsp)
    movq    $0, (L + 16)(%rsp)
    movq    $0, (L + 24)(%rsp)
    cmpq    $GOSSIP_SYNC_COMMITTEE, S9(%rsp)    # a sync message: its slot, its subnets
    jne     24f
    mov     24(%r13), %rax
    lea     16(%r13,%rax), %rax
    mov     (%rax), %rcx
    mov     %rcx, (L + 16)(%rsp)
    mov     8(%r13), %ecx
    mov     %rcx, (L + 24)(%rsp)
    movq    $0, (L + 32)(%rsp)
    jmp     22f
24: cmpq    $GOSSIP_BEACON_ATTESTATION, S9(%rsp)
    jne     22f
    mov     24(%r13), %rax
    lea     16(%r13,%rax), %rax
    mov     NodeAction_arg(%r12), %rcx
    shr     $16, %rcx
    cmp     $FORK_ELECTRA, %rcx
    jae     23f
    mov     4(%rax), %rcx                   # Attestation: data.slot at 4, data.index at 12
    mov     %rcx, (L + 16)(%rsp)
    mov     12(%rax), %rcx
    mov     %rcx, (L + 24)(%rsp)
    jmp     22f
23: mov     16(%rax), %rcx                  # SingleAttestation: committee_index at 0, data.slot at 16
    mov     %rcx, (L + 16)(%rsp)
    mov     (%rax), %rcx
    mov     %rcx, (L + 24)(%rsp)
22: mov     S9(%rsp), %rdi
    mov     S10(%rsp), %rsi
    mov     32(%r13), %rdx
    mov     NodeAction_arg(%r12), %rcx
    shr     $16, %rcx
    lea     (L + 16)(%rsp), %r8
    call    lantern_node_pool_add
    mov     %rax, L(%rsp)
    testq   $NODE_FLAG_SUBSCRIBED, Node_flags(%rbx) # NODE_FLAG_SUBSCRIBED: out on its topic, an attestation on its subnet
    jz      3f
    cmpq    $GOSSIP_SYNC_COMMITTEE, S9(%rsp)
    je      25f
    mov     S9(%rsp), %rdi
    lea     16(%r13), %rsi
    mov     8(%r13), %edx
    call    lantern_node_publish
    jmp     3f
25: movq    $0, (L + 40)(%rsp)              # a sync message: on each of its subnets
26: mov     (L + 40)(%rsp), %rdx
    cmp     $SYNC_COMMITTEE_SUBNET_COUNT, %rdx
    jae     3f
    mov     8(%r13), %eax
    bt      %edx, %eax
    jnc     27f
    mov     S9(%rsp), %rdi
    lea     16(%r13), %rsi
    call    lantern_node_publish
27: incq    (L + 40)(%rsp)
    jmp     26b
3:  cmpq    $GOSSIP_ATTESTER_SLASHING, S9(%rsp) # an attester slashing: on_attester_slashing with the justified root's state
    jne     4f
    lea     (Store_justified_checkpoint + 8)(%rbp), %rdi
    call    lantern_node_find_block
    cmp     $-1, %rax
    je      4f
    cmpq    $NODE_BLOCK_IMPORTED, NodeBlock_status(%rdx)
    jne     4f
    mov     NodeBlock_state_id(%rdx), %rsi
    test    %rsi, %rsi
    jz      4f
    mov     $NODE_WORK_ATTESTER_SLASHING, %edi
    xor     %edx, %edx
    mov     S10(%rsp), %rcx
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    call    lantern_node_work
    jmp     6f
4:  cmpq    $0, L(%rsp)                     # bytes no entry keeps and no work reads go
    jne     6f
    mov     $NODE_ACT_BYTES_FREE, %edi
    mov     S10(%rsp), %rsi
    xor     %edx, %edx
    call    lantern_node_ids
6:  mov     16(%r13), %rax
    lea     16(%r13,%rax), %r13
    decq    S7(%rsp)
    jmp     2b
40: mov     24(%r13), %rax                  # a subscription: an aggregator's subnet kept to its slot, sync subnets to an epoch
    lea     16(%r13,%rax), %rax
    movzbl  NodeAction_arg(%r12), %ecx
    cmp     $API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS, %ecx
    je      42f
    cmp     $API_OP_PREPARE_BEACON_PROPOSER, %ecx
    je      45f
    cmp     $API_OP_REGISTER_VALIDATOR, %ecx
    je      46f
    cmpb    $0, 32(%rax)                    # is_aggregator: subnet_until of compute_subnet_for_attestation, the slot + 1 at least
    je      6b
    mov     24(%rax), %rsi
    mov     %rsi, %rcx
    and     $(SLOTS_PER_EPOCH - 1), %ecx
    imul    16(%rax), %rcx
    add     8(%rax), %rcx
    and     $(ATTESTATION_SUBNET_COUNT - 1), %ecx
    inc     %rsi
    cmp     Node_subnet_until(%rbx,%rcx,8), %rsi
    jbe     6b
    mov     %rsi, Node_subnet_until(%rbx,%rcx,8)
    jmp     6b
42: mov     12(%rax), %rsi                  # until_epoch: sync_until of the subnet of each index, that epoch at least
    mov     32(%r13), %rdi
    sub     $20, %rdi
    lea     20(%rax), %r8
43: test    %rdi, %rdi
    jz      6b
    mov     (%r8), %rax
    xor     %edx, %edx
    mov     $(SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT), %ecx
    div     %rcx
    cmp     Node_sync_until(%rbx,%rax,8), %rsi
    jbe     44f
    mov     %rsi, Node_sync_until(%rbx,%rax,8)
44: add     $8, %r8
    sub     $8, %rdi
    jmp     43b
45: mov     %rax, %rdi                      # a fee recipient: through the store's epoch + 2
    call    lantern_node_proposer_put
    jmp     6b
46: lea     16(%r13), %rdi                  # a registration: its validator's NodeProposer entry
    mov     8(%r13), %rsi
    call    lantern_node_registration_put
    jmp     6b
70: cmpb    $API_OP_REGISTER_VALIDATOR, NodeAction_arg(%r12)   # registerValidator: the builder's call, then the answer
    jne     701f
    call    lantern_node_builder_register
701: mov    NodeAction_target(%r12), %rdi   # the answer: 200, or 400 with the failures
    cmpq    $0, S8(%rsp)
    je      71f
    movzbl  NodeAction_arg(%r12), %eax      # a list: the failures
    cmp     $API_OP_SUBMIT_POOL_ATTESTATIONS_V2, %eax
    je      72f
    cmp     $API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2, %eax
    je      72f
    cmp     $API_OP_SUBMIT_POOL_SYNC_COMMITTEE_SIGNATURES, %eax
    je      72f
    cmp     $API_OP_PUBLISH_CONTRIBUTION_AND_PROOFS, %eax
    je      72f
    cmp     $API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE, %eax
    jne     80f
72: mov     %r12, %rsi
    mov     $400, %edx
    mov     $API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE, %ecx
    mov     (L + 8)(%rsp), %r8
    call    lantern_node_api_send
    LEAVE 48
71: xor     %esi, %esi
    mov     $200, %edx
    xor     %ecx, %ecx
    mov     (L + 8)(%rsp), %r8
    call    lantern_node_api_send
    LEAVE 48
80: mov     NodeAction_target(%r12), %rdi
    xor     %esi, %esi
    mov     $400, %edx
    mov     $API_BODY_ERROR, %ecx
    mov     (L + 8)(%rsp), %r8
    call    lantern_node_api_send
    LEAVE 48
END_FUNCTION lantern_node_api_submit_done

/*
 * The publish of the SSZ bytes of the ByteList rsi on the gossip topic rdi of the subnet rdx (node.md, the
 * publish): a LIBP2P_EVENT_PUBLISH at the end of p2p_out; none when it does not fit. Its data
 * compresses in place, its ByteList head in the 24 bytes before the data. rbx the node, rbp the
 * store, r14 the scratch. r12 the bytes, then the data's length; r13 the event. Locals: L a
 * GossipTopic, L+24 the topic's ByteList (24 + 128), L+176 a size, L+184 the message-id (24),
 * L+208 the topic's length, L+216 the data's offset in the event, L+224 the event's room.
 */
LOCAL_FUNCTION lantern_node_publish
    ENTER 240
    mov     %rsi, %r12
    mov     Node_fork_digest(%rbx), %eax
    mov     %rax, (L + GossipTopic_fork_digest)(%rsp)
    mov     %rdi, (L + GossipTopic_name)(%rsp)
    mov     %rdx, (L + GossipTopic_subnet_id)(%rsp)
    movq    $(24 + 128), (L + 24)(%rsp)
    movq    $24, (L + 32)(%rsp)
    movq    $0, (L + 40)(%rsp)
    lea     L(%rsp), %rdi
    lea     (L + 24)(%rsp), %rsi
    call    lantern_gossip_topic
    test    %rax, %rax
    jnz     9f
    mov     (L + 40)(%rsp), %rax
    mov     %rax, (L + 208)(%rsp)
    add     $(LIBP2P_EV_PUB_TOPIC + 7), %rax
    and     $-8, %rax
    mov     %rax, (L + 216)(%rsp)
    mov     %r12, %rdi
    lea     (L + 176)(%rsp), %rsi
    CALL_GLOBAL snappy_compress_size
    test    %rax, %rax
    jnz     9f
    mov     (L + 176)(%rsp), %rax           # the room: the data's offset, then at most size - 24 bytes
    sub     $24, %rax
    add     (L + 216)(%rsp), %rax
    add     $7, %rax
    and     $-8, %rax
    mov     %rax, (L + 224)(%rsp)
    mov     %rax, %rdi
    call    lantern_node_out
    test    %rax, %rax
    jz      9f
    mov     %rax, %r13
    mov     (L + 216)(%rsp), %rdx           # the data's ByteList head before it: its room to the event's end
    lea     -24(%r13,%rdx), %rdx
    mov     (L + 224)(%rsp), %rax
    sub     (L + 216)(%rsp), %rax
    add     $24, %rax
    mov     %rax, (%rdx)
    mov     %r12, %rdi
    mov     %r14, %rsi
    CALL_GLOBAL snappy_compress
    test    %rax, %rax
    jnz     8f
    mov     %rbp, %rdi                      # the message-id: of the fork of the store's slot
    call    lantern_node_store_slot
    mov     %rax, %rdi
    lea     Node_config(%rbx), %rsi
    call    lantern_node_fork
    mov     %rax, %r10
    lea     (L + 24)(%rsp), %rdi
    mov     (L + 216)(%rsp), %rsi
    lea     -24(%r13,%rsi), %rsi
    lea     Node_config(%rbx), %rdx
    mov     %r14, %rcx
    lea     (L + 184)(%rsp), %r8
    FORK_CALL compute_message_id
    test    %rax, %rax
    jnz     8f
    mov     (L + 216)(%rsp), %rax           # the data's length; the event to its bytes
    mov     -8(%r13,%rax), %r12
    lea     7(%rax,%r12), %rcx
    and     $-8, %rcx
    mov     Node_p2p_out(%rbx), %rdx
    add     %rbx, %rdx
    mov     16(%rdx), %rax
    sub     (L + 224)(%rsp), %rax
    add     %rcx, %rax
    mov     %rax, 16(%rdx)
    mov     %rcx, (L + 224)(%rsp)
    mov     %rcx, (%r13)
    movq    $LIBP2P_EVENT_PUBLISH, 8(%r13)
    movq    $20, LIBP2P_EV_PUB_ID_LEN(%r13)
    movq    $0, (LIBP2P_EV_PUB_ID + 16)(%r13)
    movq    $0, (LIBP2P_EV_PUB_ID + 24)(%r13)
    lea     LIBP2P_EV_PUB_ID(%r13), %rdi
    lea     (L + 184)(%rsp), %rsi
    mov     $20, %edx
    call    lantern_copy
    mov     (L + 208)(%rsp), %rax
    mov     %rax, LIBP2P_EV_PUB_TOPIC_LEN(%r13)
    mov     %r12, LIBP2P_EV_PUB_DATA_LEN(%r13)
    lea     LIBP2P_EV_PUB_TOPIC(%r13), %rdi
    lea     (L + 48)(%rsp), %rsi
    mov     (L + 208)(%rsp), %rdx
    call    lantern_copy
    mov     (L + 208)(%rsp), %rax           # zero bytes after the topic and after the data
    lea     LIBP2P_EV_PUB_TOPIC(%r13,%rax), %rdi
    mov     (L + 216)(%rsp), %rsi
    sub     $LIBP2P_EV_PUB_TOPIC, %rsi
    sub     %rax, %rsi
    call    lantern_zero
    mov     (L + 216)(%rsp), %rax
    add     %r12, %rax
    lea     (%r13,%rax), %rdi
    mov     (L + 224)(%rsp), %rsi
    sub     %rax, %rsi
    call    lantern_zero
9:  LEAVE 240
8:  mov     Node_p2p_out(%rbx), %rdx        # no publish: the room goes back
    add     %rbx, %rdx
    mov     16(%rdx), %rax
    sub     (L + 224)(%rsp), %rax
    mov     %rax, 16(%rdx)
    LEAVE 240
END_FUNCTION lantern_node_publish

/*
 * (text rdi to rsi, kind rdx, fork rcx, fault r8, record r9, the event's end r10) -> rax: the
 * JSON text decoded by lantern_node_json_decode into the record r9 (r15 the scratch of
 * lantern_node_api_submit_run): code and subnet 0, then a ByteList of the SSZ bytes, its size to a multiple of 8;
 * rdx the next record. rax = 0, 1 for a text that is no such value, 2 for too little room.
 * Locals: a ByteList head of the text, the record.
 */
LOCAL_FUNCTION lantern_node_submit_decode
    FRAME 32
    mov     %r9, 24(%rsp)
    sub     %rdi, %rsi
    mov     %rsi, (%rsp)
    mov     %rdi, %rax
    sub     %rsp, %rax
    mov     %rax, 8(%rsp)
    mov     %rsi, 16(%rsp)
    lea     40(%r9), %rax
    cmp     %r10, %rax
    ja      8f
    mov     %r10, %rax
    sub     %r9, %rax
    sub     $16, %rax
    mov     %rax, 16(%r9)
    mov     %rcx, %r10
    mov     %rdx, %rdi
    mov     %rsp, %rsi
    mov     %r15, %rdx
    lea     16(%r9), %rcx
    FORK_CALL node_json_decode
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     7f
    mov     24(%rsp), %r9                   # its size: the bytes to a multiple of 8, zero after them
    mov     32(%r9), %rdx
    lea     (24 + 7)(%rdx), %rax
    and     $-8, %rax
    mov     %rax, 16(%r9)
    movq    $0, (%r9)
    movq    $0, 8(%r9)
    lea     40(%r9,%rdx), %rdi
    lea     -24(%rax), %rsi
    sub     %rdx, %rsi
    call    lantern_zero
    mov     24(%rsp), %r9
    mov     16(%r9), %rdx
    lea     16(%r9,%rdx), %rdx
    xor     %eax, %eax
    UNFRAME 32
7:  mov     $1, %eax
    UNFRAME 32
8:  mov     $2, %eax
    UNFRAME 32
END_FUNCTION lantern_node_submit_decode

/*
 * (bytes rdi, length rsi, record r9, the event's end r10) -> rax: the bytes as the record r9 of
 * lantern_node_api_submit_run: code and subnet 0, then a ByteList of them, its size to a multiple of 8;
 * rdx the next record. rax = 0, or 2 for too little room. Locals: the record, its size, the length.
 */
LOCAL_FUNCTION lantern_node_submit_copy
    FRAME 32
    lea     (16 + 24 + 7)(%rsi), %rax
    and     $-8, %rax
    lea     (%r9,%rax), %rcx
    cmp     %r10, %rcx
    ja      8f
    mov     %r9, (%rsp)
    mov     %rax, 8(%rsp)
    mov     %rsi, 16(%rsp)
    movq    $0, (%r9)
    movq    $0, 8(%r9)
    lea     -16(%rax), %rcx
    mov     %rcx, 16(%r9)
    movq    $24, 24(%r9)
    mov     %rsi, 32(%r9)
    mov     %rsi, %rdx
    mov     %rdi, %rsi
    lea     40(%r9), %rdi
    call    lantern_copy
    mov     (%rsp), %r9
    mov     16(%rsp), %rdx
    lea     40(%r9,%rdx), %rdi
    mov     8(%rsp), %rsi
    sub     $40, %rsi
    sub     %rdx, %rsi
    call    lantern_zero
    mov     (%rsp), %rdx
    add     8(%rsp), %rdx
    xor     %eax, %eax
    UNFRAME 32
8:  mov     $2, %eax
    UNFRAME 32
END_FUNCTION lantern_node_submit_copy

/*
 * (node rdi, store rsi, seen rdx, work rcx, state_a r8, data r9, scratch r10, event r11, room rax)
 * -> rax: a NODE_WORK_API_SUBMIT of lantern_node_run (node.md): the operations of the body decoded
 * as records at NodeEvent_chunk of the event, then each checked by lantern_node_gossip of the fork
 * arg / 2^16 with seen. rbx node, rbp store, r12 work, r13 state_a, r14 data, r15 scratch, S7 the
 * event, S8 its end, S9 the next record, S10 the text's end. Locals: L seen, L+8 the kind, L+16
 * the topic, L+24 the fork, L+32 the operations, L+40 1 for a list, L+48 where the text goes on,
 * L+56 an item's start, L+64 a NodeGossip, L+144 a JsonFault, L+272 a root, L+304 an index.
 */
LOCAL_FUNCTION lantern_node_api_submit_run
    ENTER 320
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, L(%rsp)
    mov     %rcx, %r12
    mov     %r8, %r13
    mov     %r9, %r14
    mov     %r10, %r15
    mov     %r11, S7(%rsp)
    add     %r11, %rax
    mov     %rax, S8(%rsp)
    mov     NodeAction_arg(%r12), %rax      # the operation's kind and topic; the fork
    mov     %rax, %rcx
    shr     $16, %rcx
    cmp     $FORK_FULU, %rcx
    ja      98f
    mov     %rcx, (L + 24)(%rsp)
    movzbl  %al, %edi
    xor     %eax, %eax
    cmp     $API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE, %edi
    sete    %al
    cmp     $API_OP_SUBMIT_POOL_ATTESTATIONS_V2, %edi
    sete    %cl
    or      %cl, %al
    cmp     $API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2, %edi
    sete    %cl
    or      %cl, %al
    cmp     $API_OP_SUBMIT_POOL_SYNC_COMMITTEE_SIGNATURES, %edi
    sete    %cl
    or      %cl, %al
    cmp     $API_OP_PUBLISH_CONTRIBUTION_AND_PROOFS, %edi
    sete    %cl
    or      %cl, %al
    cmp     $API_OP_PREPARE_BEACON_COMMITTEE_SUBNET, %edi
    sete    %cl
    or      %cl, %al
    cmp     $API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS, %edi
    sete    %cl
    or      %cl, %al
    cmp     $API_OP_PREPARE_BEACON_PROPOSER, %edi
    sete    %cl
    or      %cl, %al
    cmp     $API_OP_REGISTER_VALIDATOR, %edi
    sete    %cl
    or      %cl, %al
    mov     %rax, (L + 40)(%rsp)
    mov     %rdi, (L + 48)(%rsp)
    call    lantern_node_submit_topic
    mov     %rax, (L + 16)(%rsp)
    test    %rax, %rax
    jnz     17f
    mov     (L + 48)(%rsp), %rdi            # no topic: a subscription's type, else no such work
    mov     $NODE_JSON_COMMITTEE_SUBSCRIPTION, %eax
    cmp     $API_OP_PREPARE_BEACON_COMMITTEE_SUBNET, %edi
    je      13f
    mov     $NODE_JSON_SYNC_SUBSCRIPTION, %eax
    cmp     $API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS, %edi
    je      13f
    mov     $NODE_JSON_PROPOSER_PREPARATION, %eax
    cmp     $API_OP_PREPARE_BEACON_PROPOSER, %edi
    je      13f
    mov     $NODE_JSON_VALIDATOR_REGISTRATION, %eax
    cmp     $API_OP_REGISTER_VALIDATOR, %edi
    je      13f
    jmp     98f
17: mov     (L + 16)(%rsp), %rax
    cmp     $GOSSIP_BEACON_AGGREGATE_AND_PROOF, %rax    # an aggregate: SignedAggregateAndProof
    jne     14f
    mov     $NODE_JSON_AGGREGATE_AND_PROOF, %eax
    jmp     13f
14: cmp     $GOSSIP_SYNC_COMMITTEE, %rax    # a sync message: SyncCommitteeMessage
    jne     16f
    mov     $NODE_JSON_SYNC_COMMITTEE_MESSAGE, %eax
    jmp     13f
16: cmp     $GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF, %rax  # a contribution: SignedContributionAndProof
    jne     15f
    mov     $NODE_JSON_CONTRIBUTION_AND_PROOF, %eax
    jmp     13f
15: cmp     $GOSSIP_BEACON_ATTESTATION, %rax    # an attestation: of the fork's type
    jne     12f
    mov     $NODE_JSON_ATTESTATION, %eax
    mov     $NODE_JSON_SINGLE_ATTESTATION, %ecx
    cmpq    $FORK_ELECTRA, (L + 24)(%rsp)
    cmovae  %rcx, %rax
    jmp     13f
12: mov     %rax, %rdi
    call    lantern_node_pool_kind
13: mov     %rax, (L + 8)(%rsp)
    test    %r13, %r13
    jz      98f
    test    %r14, %r14
    jz      98f
    mov     S7(%rsp), %rdi                  # the records' ByteList
    lea     (NodeEvent_chunk + 24)(%rdi), %rax
    cmp     S8(%rsp), %rax
    ja      97f
    mov     S8(%rsp), %rcx
    sub     %rdi, %rcx
    sub     $NodeEvent_chunk, %rcx
    mov     %rcx, NodeEvent_chunk(%rdi)
    movq    $24, (NodeEvent_chunk + 8)(%rdi)
    movq    $0, (NodeEvent_chunk + 16)(%rdi)
    mov     %rax, S9(%rsp)
    movq    $0, (L + 32)(%rsp)
    mov     8(%r14), %rdi                   # the text
    add     %r14, %rdi
    mov     16(%r14), %rax
    add     %rdi, %rax
    mov     %rax, S10(%rsp)
    testb   $API_ANSWER_SSZ, (NodeAction_arg + 1)(%r12) # an SSZ body: the list's items
    jnz     40f
    cmpq    $0, (L + 40)(%rsp)
    jne     20f
    mov     S10(%rsp), %rsi                 # one operation: the whole text
    mov     (L + 8)(%rsp), %rdx
    mov     (L + 24)(%rsp), %rcx
    lea     (L + 144)(%rsp), %r8
    mov     S9(%rsp), %r9
    mov     S8(%rsp), %r10
    call    lantern_node_submit_decode
    cmp     $1, %rax
    je      90f
    ja      97f
    mov     %rdx, S9(%rsp)
    movq    $1, (L + 32)(%rsp)
    jmp     30f
20: cmpq    $GOSSIP_BLS_TO_EXECUTION_CHANGE, (L + 16)(%rsp)   # a JSON array; of BLS changes from capella
    jne     201f
    cmpq    $FORK_CAPELLA, (L + 24)(%rsp)
    jb      90f
201:
    mov     S10(%rsp), %rsi
    call    lantern_submit_ws
    cmp     %rsi, %rdi
    jae     90f
    cmpb    $'[', (%rdi)
    jne     90f
    inc     %rdi
    call    lantern_submit_ws
    cmp     %rsi, %rdi
    jae     90f
    cmpb    $']', (%rdi)
    jne     23f
    inc     %rdi
    jmp     28f
23: mov     %rdi, (L + 56)(%rsp)            # an item: to a , or ] outside strings, arrays and objects
    xor     %ecx, %ecx
24: cmp     %rsi, %rdi
    jae     90f
    movzbl  (%rdi), %eax
    cmp     $'"', %eax
    jne     25f
253: inc    %rdi
    cmp     %rsi, %rdi
    jae     90f
    movzbl  (%rdi), %eax
    cmp     $'\\', %eax
    jne     252f
    inc     %rdi
    jmp     253b
252: cmp    $'"', %eax
    jne     253b
    inc     %rdi
    jmp     24b
25: cmp     $'{', %eax
    je      251f
    cmp     $'[', %eax
    jne     26f
251: inc    %rcx
    inc     %rdi
    jmp     24b
26: cmp     $'}', %eax
    je      261f
    cmp     $']', %eax
    jne     27f
261: test   %rcx, %rcx
    jz      271f
    dec     %rcx
    inc     %rdi
    jmp     24b
27: cmp     $',', %eax
    jne     272f
    test    %rcx, %rcx
    jz      271f
272: inc    %rdi
    jmp     24b
271: mov    %rdi, (L + 48)(%rsp)
    mov     %rdi, %rsi
    mov     (L + 56)(%rsp), %rdi
    mov     (L + 8)(%rsp), %rdx
    mov     (L + 24)(%rsp), %rcx
    lea     (L + 144)(%rsp), %r8
    mov     S9(%rsp), %r9
    mov     S8(%rsp), %r10
    call    lantern_node_submit_decode
    cmp     $1, %rax
    je      90f
    ja      97f
    mov     %rdx, S9(%rsp)
    incq    (L + 32)(%rsp)
    mov     (L + 48)(%rsp), %rdi
    mov     S10(%rsp), %rsi
    movzbl  (%rdi), %eax
    inc     %rdi
    cmp     $',', %eax
    je      23b
    cmp     $']', %eax
    jne     90f
28: mov     S10(%rsp), %rsi                 # then only white space
    call    lantern_submit_ws
    cmp     %rsi, %rdi
    jne     90f
    jmp     30f
40: mov     %rdi, (L + 48)(%rsp)            # SSZ: attestations from electra items of 240 bytes
    mov     S10(%rsp), %rax
    sub     %rdi, %rax
    cmpb    $API_OP_REGISTER_VALIDATOR, NodeAction_arg(%r12)   # registrations: items of 180 bytes
    je      46f
    cmpq    $GOSSIP_BEACON_AGGREGATE_AND_PROOF, (L + 16)(%rsp)
    je      42f
    cmpq    $FORK_ELECTRA, (L + 24)(%rsp)
    jb      42f
    xor     %edx, %edx
    mov     $240, %ecx
    div     %rcx
    test    %rdx, %rdx
    jnz     90f
    mov     %rax, (L + 56)(%rsp)
41: cmpq    $0, (L + 56)(%rsp)
    je      30f
    mov     (L + 48)(%rsp), %rdi
    mov     $240, %esi
    mov     S9(%rsp), %r9
    mov     S8(%rsp), %r10
    call    lantern_node_submit_copy
    test    %rax, %rax
    jnz     97f
    mov     %rdx, S9(%rsp)
    addq    $240, (L + 48)(%rsp)
    decq    (L + 56)(%rsp)
    incq    (L + 32)(%rsp)
    jmp     41b
46: xor     %edx, %edx                      # registrations: SignedValidatorRegistrationV1 items
    mov     $180, %ecx
    div     %rcx
    test    %rdx, %rdx
    jnz     90f
    mov     %rax, (L + 56)(%rsp)
47: cmpq    $0, (L + 56)(%rsp)
    je      30f
    mov     (L + 48)(%rsp), %rdi
    mov     $180, %esi
    mov     S9(%rsp), %r9
    mov     S8(%rsp), %r10
    call    lantern_node_submit_copy
    test    %rax, %rax
    jnz     97f
    mov     %rdx, S9(%rsp)
    addq    $180, (L + 48)(%rsp)
    decq    (L + 56)(%rsp)
    incq    (L + 32)(%rsp)
    jmp     47b
42: test    %rax, %rax                      # before electra: the items of the 4-byte offsets
    jz      30f
    cmp     $4, %rax
    jb      90f
    mov     (%rdi), %ecx
    test    %rcx, %rcx
    jz      90f
    test    $3, %cl
    jnz     90f
    cmp     %rax, %rcx
    ja      90f
    shr     $2, %rcx
    mov     %rcx, (L + 304)(%rsp)
    movq    $0, (L + 56)(%rsp)
43: mov     (L + 56)(%rsp), %rcx
    cmp     (L + 304)(%rsp), %rcx
    jae     30f
    mov     (L + 48)(%rsp), %rdi
    mov     (%rdi,%rcx,4), %r8d
    mov     S10(%rsp), %rax
    sub     %rdi, %rax
    lea     1(%rcx), %rdx
    cmp     (L + 304)(%rsp), %rdx
    jae     44f
    mov     (%rdi,%rdx,4), %eax
44: cmp     %rax, %r8
    ja      90f
    mov     S10(%rsp), %rdx
    sub     %rdi, %rdx
    cmp     %rdx, %rax
    ja      90f
    lea     (%rdi,%r8), %rdi
    mov     %rax, %rsi
    sub     %r8, %rsi
    mov     S9(%rsp), %r9
    mov     S8(%rsp), %r10
    call    lantern_node_submit_copy
    test    %rax, %rax
    jnz     97f
    mov     %rdx, S9(%rsp)
    incq    (L + 56)(%rsp)
    incq    (L + 32)(%rsp)
    jmp     43b
30: mov     S7(%rsp), %rdi                  # the records: their bytes, their count
    mov     S9(%rsp), %rax
    sub     %rdi, %rax
    mov     %rax, (%rdi)
    sub     $NodeEvent_chunk, %rax
    mov     %rax, NodeEvent_chunk(%rdi)
    sub     $24, %rax
    mov     %rax, (NodeEvent_chunk + 16)(%rdi)
    mov     (L + 32)(%rsp), %rax
    mov     %rax, NodeEvent_index(%rdi)
    cmpq    $0, (L + 16)(%rsp)              # the subscriptions: their checks, no gossip validation
    je      50f
    mov     L(%rsp), %rdi                   # seen has a key free for each operation, for a sync message one a subnet
    mov     Seen_bits(%rdi), %rax
    sub     Seen_keys(%rdi), %rax
    shr     $5, %rax
    sub     (Seen_keys + 8)(%rdi), %rax
    mov     (L + 32)(%rsp), %rcx
    cmpq    $GOSSIP_SYNC_COMMITTEE, (L + 16)(%rsp)
    jne     301f
    imul    $SYNC_COMMITTEE_SUBNET_COUNT, %rcx, %rcx
301: cmp    %rcx, %rax
    jb      97f
    mov     L(%rsp), %rax                   # the NodeGossip of the operations
    mov     %rax, (L + 64 + NodeGossip_seen)(%rsp)
    mov     %rbp, (L + 64 + NodeGossip_store)(%rsp)
    mov     Node_time_ms(%rbx), %rax
    mov     %rax, (L + 64 + NodeGossip_time_ms)(%rsp)
    mov     (L + 16)(%rsp), %rax
    mov     %rax, (L + 64 + NodeGossip_topic)(%rsp)
    movq    $0, (L + 64 + NodeGossip_subnet)(%rsp)
    mov     %r13, (L + 64 + NodeGossip_head)(%rsp)
    movq    $0, (L + 64 + NodeGossip_proposer)(%rsp)
    movq    $0, (L + 64 + NodeGossip_justified)(%rsp)
    movq    $0, (L + 64 + NodeGossip_settings)(%rsp)
    lea     Node_config(%rbx), %rax
    mov     %rax, (L + 64 + NodeGossip_config)(%rsp)
    mov     S7(%rsp), %rax
    add     $(NodeEvent_chunk + 24), %rax
    mov     %rax, S9(%rsp)
31: cmpq    $0, (L + 32)(%rsp)
    je      39f
    mov     S9(%rsp), %rcx                  # the subnet: 0, but an attestation's
    movq    $0, 8(%rcx)
    cmpq    $GOSSIP_SYNC_COMMITTEE, (L + 16)(%rsp)
    je      36f
    cmpq    $GOSSIP_BEACON_ATTESTATION, (L + 16)(%rsp)
    jne     33f
    mov     32(%rcx), %rax
    lea     40(%rcx), %rdx
    cmpq    $FORK_ELECTRA, (L + 24)(%rsp)
    jb      32f
    cmp     $240, %rax                      # a SingleAttestation: committee_index 0, data.slot 16, data.target.epoch 104
    jb      33f
    mov     (%rdx), %rax
    mov     %rax, (L + 48)(%rsp)
    mov     16(%rdx), %rax
    mov     %rax, (L + 56)(%rsp)
    mov     104(%rdx), %rax
    jmp     34f
32: cmp     $228, %rax                      # an Attestation: data.slot 4, data.index 12, data.target.epoch 92
    jb      33f
    mov     12(%rdx), %rax
    mov     %rax, (L + 48)(%rsp)
    mov     4(%rdx), %rax
    mov     %rax, (L + 56)(%rsp)
    mov     92(%rdx), %rax
34: mov     %rax, (L + 272)(%rsp)
    mov     %r13, %rdi
    lea     (L + 272)(%rsp), %rsi
    mov     (Node_config + CONFIG_COMMITTEE_CACHE)(%rbx), %rdx
    mov     %r15, %rcx
    lea     (L + 304)(%rsp), %r8
    mov     (L + 24)(%rsp), %r10
    FORK_CALL get_committee_count_per_slot
    test    %rax, %rax
    jnz     33f
    mov     (L + 56)(%rsp), %rax            # compute_subnet_for_attestation
    and     $(SLOTS_PER_EPOCH - 1), %eax
    imul    (L + 304)(%rsp), %rax
    add     (L + 48)(%rsp), %rax
    mov     (Node_config + CONFIG_ATTESTATION_SUBNET_COUNT)(%rbx), %rcx
    test    %rcx, %rcx
    jz      33f
    xor     %edx, %edx
    div     %rcx
    mov     S9(%rsp), %rcx
    mov     %rdx, 8(%rcx)
33: mov     S9(%rsp), %rcx
    mov     8(%rcx), %rax
    mov     %rax, (L + 64 + NodeGossip_subnet)(%rsp)
    mov     (L + 24)(%rsp), %r10
    lea     (L + 64)(%rsp), %rdi
    lea     16(%rcx), %rsi
    mov     %r15, %rdx
    lea     (L + 304)(%rsp), %r9
    lea     (L + 272)(%rsp), %r8
    FORK_CALL node_gossip
    test    %rax, %rax
    jnz     99f
    mov     S9(%rsp), %rcx
    cmpq    $GOSSIP_BEACON_ATTESTATION, (L + 16)(%rsp)  # a valid attestation: its member, 2^32 times, with the subnet
    jne     35f
    cmpq    $0, (%rcx)
    jne     35f
    mov     (L + 272 + 16)(%rsp), %rax
    shl     $32, %rax
    or      %rax, 8(%rcx)
35: mov     16(%rcx), %rax
    lea     16(%rcx,%rax), %rcx
    mov     %rcx, S9(%rsp)
    decq    (L + 32)(%rsp)
    jmp     31b
36: mov     $-1, %rsi                       # a sync message: its check on each subnet of compute_subnets_for_sync_committee
    cmpq    $144, 32(%rcx)
    jne     361f
    mov     (40 + 40)(%rcx), %rsi           # validator_index
361: mov    %r13, %rdi
    lea     (L + 48)(%rsp), %rdx
    mov     (L + 24)(%rsp), %r10
    FORK_CALL node_sync_subnets
    test    %rax, %rax
    jnz     99f
    movq    $0, (L + 144)(%rsp)             # the valid subnets, a reject, the subnet
    movq    $0, (L + 152)(%rsp)
    movq    $0, (L + 160)(%rsp)
    cmpq    $0, (L + 48)(%rsp)
    jne     37f
    movq    $1, (L + 48)(%rsp)              # none: the check on subnet 0, which it fails
37: mov     (L + 160)(%rsp), %rax
    cmp     $SYNC_COMMITTEE_SUBNET_COUNT, %rax
    jae     38f
    mov     (L + 48)(%rsp), %rdx
    bt      %rax, %rdx
    jnc     371f
    mov     %rax, (L + 64 + NodeGossip_subnet)(%rsp)
    mov     (L + 24)(%rsp), %r10
    lea     (L + 64)(%rsp), %rdi
    mov     S9(%rsp), %rcx
    lea     16(%rcx), %rsi
    mov     %r15, %rdx
    lea     (L + 304)(%rsp), %r9
    lea     (L + 272)(%rsp), %r8
    FORK_CALL node_gossip
    test    %rax, %rax
    jnz     99f
    mov     S9(%rsp), %rcx
    mov     (%rcx), %rax
    test    %rax, %rax
    jnz     372f
    mov     (L + 160)(%rsp), %rdx           # valid: its bit
    mov     (L + 144)(%rsp), %rax
    bts     %rdx, %rax
    mov     %rax, (L + 144)(%rsp)
    jmp     371f
372: cmp    $LANTERN_GOSSIP_REJECT, %rax
    jne     371f
    mov     %rax, (L + 152)(%rsp)
371: incq   (L + 160)(%rsp)
    jmp     37b
38: mov     S9(%rsp), %rcx                  # valid on a subnet; else a reject; else the last code
    mov     (L + 144)(%rsp), %rax
    mov     %rax, 8(%rcx)
    test    %rax, %rax
    jz      381f
    movq    $0, (%rcx)
    jmp     35b
381: mov    (L + 152)(%rsp), %rax
    test    %rax, %rax
    jz      35b
    mov     %rax, (%rcx)
    jmp     35b
39: xor     %eax, %eax
    LEAVE 320
50: mov     S7(%rsp), %rcx                  # each subscription valid, else the result LANTERN_INVALID_ENCODING
    add     $(NodeEvent_chunk + 24), %rcx
    cmpb    $API_OP_REGISTER_VALIDATOR, NodeAction_arg(%r12)   # registrations: 180 bytes each, IGNORE until found eligible
    je      60f
51: cmpq    $0, (L + 32)(%rsp)
    je      39b
    movq    $0, (%rcx)
    movq    $0, 8(%rcx)
    mov     32(%rcx), %rax
    lea     40(%rcx), %rdx
    movzbl  NodeAction_arg(%r12), %esi
    cmp     $API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS, %esi
    je      53f
    cmp     $API_OP_PREPARE_BEACON_PROPOSER, %esi
    jne     55f
    cmp     $28, %rax                       # ProposerPreparation: its 28 bytes
    jne     90f
    jmp     54f
55: cmp     $33, %rax                       # BeaconCommitteeSubscription: committees_at_slot 1 to MAX_COMMITTEES_PER_SLOT, committee_index below it
    jne     90f
    mov     16(%rdx), %rsi
    test    %rsi, %rsi
    jz      90f
    cmp     $MAX_COMMITTEES_PER_SLOT, %rsi
    ja      90f
    cmp     %rsi, 8(%rdx)
    jae     90f
    jmp     54f
53: cmp     $20, %rax                       # SyncCommitteeSubscription: offset 20, indices below SYNC_COMMITTEE_SIZE
    jb      90f
    cmpl    $20, 8(%rdx)
    jne     90f
    sub     $20, %rax
    test    $7, %al
    jnz     90f
    add     $20, %rdx
52: test    %rax, %rax
    jz      54f
    cmpq    $SYNC_COMMITTEE_SIZE, (%rdx)
    jae     90f
    add     $8, %rdx
    sub     $8, %rax
    jmp     52b
54: mov     16(%rcx), %rax
    lea     16(%rcx,%rax), %rcx
    decq    (L + 32)(%rsp)
    jmp     51b
60: mov     (L + 32)(%rsp), %rdx
    mov     %rcx, %rsi
61: test    %rdx, %rdx
    jz      62f
    cmpq    $180, 32(%rsi)
    jne     90f
    movq    $LANTERN_GOSSIP_IGNORE, (%rsi)
    movq    $0, 8(%rsi)
    mov     16(%rsi), %rax
    lea     16(%rsi,%rax), %rsi
    dec     %rdx
    jmp     61b
62: mov     (L + 32)(%rsp), %rdx
    test    %rdx, %rdx
    jz      39b
    mov     %r13, %rdi                      # one scan of the state's validators
    mov     %rcx, %rsi
    mov     %r15, %rcx
    call    lantern_node_registrations_find
    test    %rax, %rax
    jnz     97f
    jmp     39b
90: mov     S7(%rsp), %rcx                  # a body that is no such text
    movq    $LANTERN_INVALID_ENCODING, NodeEvent_result(%rcx)
    movq    $NODE_EV_WORK_DONE_SIZE, (%rcx)
    xor     %eax, %eax
    LEAVE 320
97: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 320
98: mov     $LANTERN_INVALID_EVENT, %eax
99: LEAVE 320
END_FUNCTION lantern_node_api_submit_run

/* rdi = rdi past the JSON white space (space, tab, LF, CR) before rsi. Uses rax. */
LOCAL_FUNCTION lantern_submit_ws
    UNWIND_END_PROLOGUE
1:  cmp     %rsi, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    cmp     $' ', %eax
    je      2f
    cmp     $9, %eax
    je      2f
    cmp     $10, %eax
    je      2f
    cmp     $13, %eax
    jne     9f
2:  inc     %rdi
    jmp     1b
9:  ret
END_FUNCTION lantern_submit_ws

    RODATA
    .p2align 3
node_api_rooms:                             # the room of each text of an ApiIdentity, then 0
    .quad 64, 512, 128, 128, 64, 0
