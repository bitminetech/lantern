/*
 * The Beacon API answers of the node, ARM64: in the common object. Requirements:
 * docs/reference/beacon-api.md (Common rules) and docs/reference/node.md (NODE_EV_API).
 *
 * The writer: x24 the cursor, x25 the pass (0 counts the bytes, 1 writes them), x26 the end of
 * the room, x27 1 when the room ran out, x22 the ApiView, x28 the body kind. The writer's
 * functions keep x22 and x24-x28 for it; only lantern_api_respond calls them.
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
    ADDRESS x0, \label
    mov     x1, #\label\()_len
    bl      lantern_api_put
.endm

/* L0: the x1 bytes at x0 join the response; the first pass only counts them. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION lantern_api_put
    UNWIND_END_PROLOGUE
    cbz     x25, 2f
    add     x9, x24, x1
    cmp     x9, x26
    b.hi    3f
1:  cbz     x1, 9f
    ldrb    w10, [x0], #1
    strb    w10, [x24], #1
    sub     x1, x1, #1
    b       1b
2:  add     x24, x24, x1
9:  ret
3:  mov     x27, #1
    ret
END_FUNCTION lantern_api_put

/* L1: the decimal digits of x0 join the response. Locals: the digits, from the end. */
LOCAL_FUNCTION lantern_api_dec
    FRAME 32
    add     x9, sp, #48
    mov     x10, #10
1:  udiv    x11, x0, x10
    msub    x12, x11, x10, x0
    add     x12, x12, #0x30
    strb    w12, [x9, #-1]!
    mov     x0, x11
    cbnz    x0, 1b
    mov     x0, x9
    add     x1, sp, #48
    sub     x1, x1, x9
    bl      lantern_api_put
    UNFRAME 32
END_FUNCTION lantern_api_dec

/*
 * L1: the decimal digits of the 256-bit little-endian number at x0 join the response. Locals: its
 * eight 32-bit words, then the digits from the end.
 */
LOCAL_FUNCTION lantern_api_dec256
    FRAME 128
    ldp     x10, x11, [x0]
    stp     x10, x11, [sp, #16]
    ldp     x10, x11, [x0, #16]
    stp     x10, x11, [sp, #32]
    add     x9, sp, #(16 + 112)
    mov     x13, x9
1:  mov     x4, #0                          /* divide by 10, from the top word down */
    mov     x5, #7
    mov     x6, #0
    mov     x10, #10
2:  add     x7, sp, #16
    ldr     w11, [x7, x5, lsl #2]
    orr     x11, x11, x4, lsl #32
    udiv    x12, x11, x10
    msub    x4, x12, x10, x11
    str     w12, [x7, x5, lsl #2]
    orr     x6, x6, x12
    subs    x5, x5, #1
    b.hs    2b
    add     x4, x4, #0x30
    strb    w4, [x9, #-1]!
    cbnz    x6, 1b
    mov     x0, x9
    sub     x1, x13, x9
    bl      lantern_api_put
    UNFRAME 128
END_FUNCTION lantern_api_dec256

/* L1: the Gwei x0 in Wei, decimal digits, join the response. Locals: x0. */
LOCAL_FUNCTION lantern_api_wei
    FRAME 16
    str     x0, [sp, #16]
    bl      lantern_api_dec
    ldr     x0, [sp, #16]
    cbz     x0, 1f
    API_LIT api_nines
1:  UNFRAME 16
END_FUNCTION lantern_api_wei

/* L1: the decimal digits of x0, in quotes. Locals: x0. */
LOCAL_FUNCTION lantern_api_qdec
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_quote
    ldr     x0, [sp, #16]
    bl      lantern_api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION lantern_api_qdec

/* L1: "0x" and the lower case hex of the x1 bytes at x0, in quotes. Locals: x0, x1, then 2 digits. */
LOCAL_FUNCTION lantern_api_qhex
    FRAME 32
    stp     x0, x1, [sp, #16]
    API_LIT api_quote
    API_LIT api_0x
1:  ldp     x0, x1, [sp, #16]
    cbz     x1, 2f
    ldrb    w9, [x0], #1
    sub     x1, x1, #1
    stp     x0, x1, [sp, #16]
    ADDRESS x10, api_hex
    lsr     w11, w9, #4
    ldrb    w11, [x10, x11]
    strb    w11, [sp, #32]
    and     w11, w9, #15
    ldrb    w11, [x10, x11]
    strb    w11, [sp, #33]
    add     x0, sp, #32
    mov     x1, #2
    bl      lantern_api_put
    b       1b
2:  API_LIT api_quote
    UNFRAME 32
END_FUNCTION lantern_api_qhex

/* L1: the text at x0 (its length, then its bytes), in quotes. Locals: x0. */
LOCAL_FUNCTION lantern_api_text
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_quote
    ldr     x9, [sp, #16]
    ldr     x1, [x9]
    add     x0, x9, #8
    bl      lantern_api_put
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION lantern_api_text

/* L1: true when x0 is not 0, else false. */
LOCAL_FUNCTION lantern_api_bool
    FRAME 0
    cbz     x0, 1f
    API_LIT api_true
    UNFRAME 0
1:  API_LIT api_false
    UNFRAME 0
END_FUNCTION lantern_api_bool

/* L1: a Checkpoint of the view at x0: {"epoch":…,"root":…}. Locals: x0. */
LOCAL_FUNCTION lantern_api_checkpoint
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_f_epoch
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_qdec
    API_LIT api_f_root
    ldr     x0, [sp, #16]
    add     x0, x0, #8
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION lantern_api_checkpoint

/* L0: x0 = the api_codes entry of the status x0, or 0. Uses x9-x11. */
LOCAL_FUNCTION lantern_api_code
    UNWIND_END_PROLOGUE
    ADDRESS x9, api_codes
    ADDRESS x10, api_codes_end
1:  cmp     x9, x10
    b.hs    2f
    ldr     x11, [x9]
    cmp     x11, x0
    b.eq    3f
    add     x9, x9, #API_CODE_ENTRY
    b       1b
2:  mov     x0, #0
    ret
3:  mov     x0, x9
    ret
END_FUNCTION lantern_api_code

/* L1: the text of the api_codes entry x0 at its byte x1 (8 the reason, 24 the message), or none for no entry. */
LOCAL_FUNCTION lantern_api_code_text
    FRAME 0
    cbz     x0, 9f
    add     x9, x0, x1
    ldp     x10, x1, [x9]
    ADDRESS x0, api_texts
    add     x0, x0, x10
    bl      lantern_api_put
9:  UNFRAME 0
END_FUNCTION lantern_api_code_text

/* L1: the decimal digits of the Uint256 at x0, little endian, in quotes. Locals: its eight 32-bit words, then the text from its end. */
LOCAL_FUNCTION lantern_api_qdec256
    FRAME 128
    ldp     x10, x11, [x0]
    stp     x10, x11, [sp, #16]
    ldp     x10, x11, [x0, #16]
    stp     x10, x11, [sp, #32]
    add     x9, sp, #(16 + 128)             /* the closing quote, then the digits backwards */
    mov     w10, #0x22
    strb    w10, [x9, #-1]!
    add     x7, sp, #16
    mov     x10, #10
1:  mov     x4, #0                          /* divide by 10, from the top word down */
    mov     x5, #7
    mov     x6, #0                          /* any word not zero */
2:  ldr     w11, [x7, x5, lsl #2]
    orr     x11, x11, x4, lsl #32
    udiv    x12, x11, x10
    msub    x4, x12, x10, x11
    str     w12, [x7, x5, lsl #2]
    orr     x6, x6, x12
    subs    x5, x5, #1
    b.hs    2b
    add     x4, x4, #0x30
    strb    w4, [x9, #-1]!
    cbnz    x6, 1b
    mov     w10, #0x22
    strb    w10, [x9, #-1]!
    mov     x0, x9
    add     x1, sp, #(16 + 128)
    sub     x1, x1, x9
    bl      lantern_api_put
    UNFRAME 128
END_FUNCTION lantern_api_qdec256

/*
 * L2: the body of getSpec (beacon-api.md, Common rules): each key of API_SPEC_KEYS, with the
 * config of the view x22. Locals: L the record, L+8 an index, L+16 32 bytes of a value, L+48 a count.
 */
LOCAL_FUNCTION lantern_api_spec
    FRAME 64
    ADDRESS x9, api_spec_keys
    str     x9, [sp, #16]
    API_LIT api_p_open
    b       2f
1:  ldr     x9, [sp, #16]                   /* the next record */
    add     x9, x9, #API_SPEC_BYTES
    str     x9, [sp, #16]
    ADDRESS x10, api_spec_keys_end
    cmp     x9, x10
    b.hs    9f
    API_LIT api_p_next
2:  ldr     x9, [sp, #16]                   /* "<name>": */
    ldr     x1, [x9]
    add     x0, x9, #24
    bl      lantern_api_put
    API_LIT api_p_key
    ldr     x9, [sp, #16]
    ldp     x10, x0, [x9, #8]               /* the kind, the value */
    lsr     x12, x10, #8                    /* the kind's arg */
    and     x10, x10, #255
    stp     x0, xzr, [sp, #32]              /* the value's bytes, then zero bytes */
    stp     xzr, xzr, [sp, #48]
    str     x12, [sp, #64]
    cmp     x10, #SPEC_NUMBER
    b.ne    3f
    bl      lantern_api_qdec
    b       1b
3:  cmp     x10, #SPEC_HEX
    b.ne    4f
    add     x0, sp, #32
    mov     x1, x12
    bl      lantern_api_qhex
    b       1b
4:  cmp     x10, #SPEC_TEXT
    b.ne    5f
    API_LIT api_quote
    add     x0, sp, #32
    ldr     x1, [sp, #64]
    bl      lantern_api_put
    API_LIT api_quote
    b       1b
5:  cmp     x10, #SPEC_LIST
    b.ne    6f
    API_LIT api_p_lbracket
    str     xzr, [sp, #24]
51: ldr     x9, [sp, #24]
    ldr     x10, [sp, #64]
    cmp     x9, x10
    b.hs    52f
    cbz     x9, 53f
    API_LIT api_p_comma
53: ldr     x9, [sp, #24]
    add     x10, sp, #32
    ldrb    w0, [x10, x9]
    add     x9, x9, #1
    str     x9, [sp, #24]
    bl      lantern_api_qdec
    b       51b
52: API_LIT api_p_rbracket
    b       1b
6:  ldr     x9, [x22, #ApiView_config]
    add     x0, x9, x0                      /* the config's field */
    cmp     x10, #SPEC_SECONDS
    b.ne    7f
    ldr     x0, [x0]
    mov     x9, #1000
    udiv    x0, x0, x9
    bl      lantern_api_qdec
    b       1b
7:  cmp     x10, #SPEC_CONFIG
    b.ne    8f
    cmp     x12, #CONFIG_KIND_U64
    b.ne    71f
    ldr     x0, [x0]
    bl      lantern_api_qdec
    b       1b
71: cmp     x12, #CONFIG_KIND_UINT256
    b.ne    72f
    bl      lantern_api_qdec256
    b       1b
72: cmp     x12, #CONFIG_KIND_TEXT
    b.ne    73f
    bl      lantern_api_text                        /* in quotes */
    b       1b
73: mov     x1, #4                          /* Version: 4 bytes; Hash32: 32; Address: 20 */
    cmp     x12, #CONFIG_KIND_HASH32
    mov     x9, #32
    csel    x1, x9, x1, eq
    cmp     x12, #CONFIG_KIND_ADDRESS
    mov     x9, #20
    csel    x1, x9, x1, eq
    bl      lantern_api_qhex
    b       1b
    /* SPEC_SCHEDULE: [{"EPOCH":…,"MAX_BLOBS_PER_BLOCK":…},…] */
8:  API_LIT api_p_lbracket
    str     xzr, [sp, #24]
81: ldr     x9, [sp, #24]
    ldr     x11, [x22, #ApiView_config]
    LDQ     x10, x11, CONFIG_BLOB_SCHEDULE_COUNT
    cmp     x9, x10
    b.hs    82f
    cbz     x9, 83f
    API_LIT api_p_comma
83: API_LIT api_p_epoch
    ldr     x9, [sp, #24]
    ldr     x11, [x22, #ApiView_config]
    add     x11, x11, #CONFIG_BLOB_SCHEDULE
    add     x11, x11, x9, lsl #4
    ldr     x0, [x11]
    bl      lantern_api_qdec
    API_LIT api_p_max
    ldr     x9, [sp, #24]
    ldr     x11, [x22, #ApiView_config]
    add     x11, x11, #(CONFIG_BLOB_SCHEDULE + 8)
    add     x11, x11, x9, lsl #4
    ldr     x0, [x11]
    bl      lantern_api_qdec
    API_LIT api_end1
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       81b
82: API_LIT api_p_rbracket
    b       1b
9:  API_LIT api_end2
    UNFRAME 64
END_FUNCTION lantern_api_spec

/*
 * L2: the body of getForkSchedule (beacon-api.md, Common rules), with the config of the view x22:
 * phase0, then each fork to fulu whose epoch is below 2^64 - 1. Locals: L the fork, L+8 the
 * previous version, L+16 the version, L+24 the epoch.
 */
LOCAL_FUNCTION lantern_api_fork_schedule
    FRAME 32
    API_LIT api_o_open
    ldr     x9, [x22, #ApiView_config]
    ldr     x10, [x9, #CONFIG_GENESIS_FORK_VERSION]
    stp     xzr, x10, [sp, #16]
    stp     x10, xzr, [sp, #32]
    b       2f
1:  ldr     x9, [sp, #16]                   /* the next fork: its version at 16 * fork - 8, its epoch at 16 * fork */
    add     x9, x9, #1
    str     x9, [sp, #16]
    cmp     x9, #FORK_FULU
    b.hi    9f
    ldr     x10, [x22, #ApiView_config]
    add     x10, x10, x9, lsl #4
    ldur    x11, [x10, #-8]
    ldr     x12, [x10]
    cmn     x12, #1
    b.eq    1b
    stp     x11, x12, [sp, #32]
    API_LIT api_p_comma
    /* {"previous_version":…,"current_version":…,"epoch":…} */
2:  API_LIT api_o_entry
    add     x0, sp, #24
    mov     x1, #4
    bl      lantern_api_qhex
    API_LIT api_k_current
    add     x0, sp, #32
    mov     x1, #4
    bl      lantern_api_qhex
    API_LIT api_k_epoch
    ldr     x0, [sp, #40]
    bl      lantern_api_qdec
    API_LIT api_end1
    ldr     x9, [sp, #32]                   /* the next fork's previous version */
    str     x9, [sp, #24]
    b       1b
9:  API_LIT api_o_end
    UNFRAME 32
END_FUNCTION lantern_api_fork_schedule

/* ---------------------------------------------------------------- Validators (beacon-api.md, Common rules) */

.set API_ITEM_MAX, 576                      /* the most bytes of an item and its comma */

/* L0: x0 = the API_STATUS_* of the validator at x0 at the epoch x1. A leaf. Uses x9-x12. */
LOCAL_FUNCTION lantern_api_validator_status
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #NODE_VALIDATOR_WITHDRAWABLE]
    cmp     x9, x1
    b.hi    1f
    ldr     x9, [x0, #NODE_VALIDATOR_EFFECTIVE_BALANCE]
    cmp     x9, #0
    mov     x10, #API_STATUS_WITHDRAWAL_DONE
    mov     x11, #API_STATUS_WITHDRAWAL_POSSIBLE
    csel    x0, x10, x11, eq
    ret
1:  ldrb    w12, [x0, #NODE_VALIDATOR_SLASHED]
    ldr     x9, [x0, #NODE_VALIDATOR_EXIT]
    cmp     x9, x1
    b.hi    2f
    cmp     w12, #0
    mov     x10, #API_STATUS_EXITED_SLASHED
    mov     x11, #API_STATUS_EXITED_UNSLASHED
    csel    x0, x10, x11, ne
    ret
2:  ldr     x10, [x0, #NODE_VALIDATOR_ACTIVATION]
    cmp     x10, x1
    b.hi    4f
    cmn     x9, #1                          /* active: exiting with an exit epoch below FAR_FUTURE_EPOCH */
    b.eq    3f
    cmp     w12, #0
    mov     x10, #API_STATUS_ACTIVE_SLASHED
    mov     x11, #API_STATUS_ACTIVE_EXITING
    csel    x0, x10, x11, ne
    ret
3:  mov     x0, #API_STATUS_ACTIVE_ONGOING
    ret
4:  ldr     x9, [x0, #NODE_VALIDATOR_ELIGIBILITY]
    cmn     x9, #1
    mov     x10, #API_STATUS_PENDING_INITIALIZED
    mov     x11, #API_STATUS_PENDING_QUEUED
    csel    x0, x10, x11, eq
    ret
END_FUNCTION lantern_api_validator_status

/*
 * L1: the item of the validator x1 of the state x0: x2 0 for getStateValidators, 1 for the
 * balances, 2 for the identities, 3 for their SSZ (64 bytes). Locals: L the validator, L+8 the
 * index, L+16 the kind, L+24 the balance, L+32 the epoch, L+48 an SSZ item.
 */
LOCAL_FUNCTION lantern_api_validator_item
    FRAME 112
    stp     x1, x2, [sp, #24]
    PART    x9, x10, x0, NODE_STATE_BALANCES
    ldr     x10, [x9, x1, lsl #3]
    str     x10, [sp, #40]
    ldr     x11, [x0, #NODE_STATE_SLOT]
    mov     x12, #SLOTS_PER_EPOCH
    udiv    x11, x11, x12
    str     x11, [sp, #48]
    PART    x9, x10, x0, NODE_STATE_VALIDATORS
    add     x9, x9, x1, lsl #7              /* NODE_VALIDATOR_MEM */
    str     x9, [sp, #16]
    cmp     x2, #3
    b.ne    1f
    str     x1, [sp, #64]                   /* SSZ: index, pubkey, activation_epoch */
    add     x0, sp, #72
    mov     x1, x9
    mov     x2, #48
    bl      lantern_copy
    ldr     x9, [sp, #16]
    ldr     x10, [x9, #NODE_VALIDATOR_ACTIVATION]
    str     x10, [sp, #120]
    add     x0, sp, #64
    mov     x1, #64
    bl      lantern_api_put
    UNFRAME 112
1:  API_LIT api_v_index
    ldr     x0, [sp, #24]
    bl      lantern_api_qdec
    ldr     x9, [sp, #32]
    cmp     x9, #2
    b.eq    2f
    API_LIT api_v_balance
    ldr     x0, [sp, #40]
    bl      lantern_api_qdec
    ldr     x9, [sp, #32]
    cbnz    x9, 9f
    API_LIT api_v_status
    ldr     x0, [sp, #16]
    ldr     x1, [sp, #48]
    bl      lantern_api_validator_status
    ADDRESS x9, api_v_statuses
    mov     x10, #24
    madd    x9, x0, x10, x9
    ldrb    w1, [x9], #1
    mov     x0, x9
    bl      lantern_api_put
    API_LIT api_v_validator
    ldr     x0, [sp, #16]
    mov     x1, #48
    bl      lantern_api_qhex
    API_LIT api_v_credentials
    ldr     x0, [sp, #16]
    add     x0, x0, #NODE_VALIDATOR_CREDENTIALS
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_v_effective
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_EFFECTIVE_BALANCE]
    bl      lantern_api_qdec
    API_LIT api_v_slashed
    ldr     x9, [sp, #16]
    ldrb    w0, [x9, #NODE_VALIDATOR_SLASHED]
    bl      lantern_api_bool
    API_LIT api_v_eligibility
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_ELIGIBILITY]
    bl      lantern_api_qdec
    API_LIT api_v_activation
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_ACTIVATION]
    bl      lantern_api_qdec
    API_LIT api_v_exit
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_EXIT]
    bl      lantern_api_qdec
    API_LIT api_v_withdrawable
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_WITHDRAWABLE]
    bl      lantern_api_qdec
    API_LIT api_end2
    UNFRAME 112
    /* identities */
2:  API_LIT api_v_pubkey
    ldr     x0, [sp, #16]
    mov     x1, #48
    bl      lantern_api_qhex
    API_LIT api_v_activation
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_ACTIVATION]
    bl      lantern_api_qdec
9:  API_LIT api_end1
    UNFRAME 112
END_FUNCTION lantern_api_validator_item

/* L0: x0 = the index of the validator of the ValidatorRef in the ByteList x1 in the state x0, or 2^64 - 1. A leaf. Uses x0-x5, x9-x16. */
LOCAL_FUNCTION lantern_node_api_find_validator
    UNWIND_END_PROLOGUE
    ldr     x9, [x1, #16]
    cmp     x9, #64
    b.ne    8f
    ldr     x9, [x1, #8]
    add     x1, x1, x9
    PART    x10, x11, x0, NODE_STATE_VALIDATORS
    ldr     x9, [x1]
    cmp     x9, #API_VALIDATOR_INDEX
    b.ne    2f
    ldr     x0, [x1, #8]
    cmp     x0, x11
    b.hs    8f
    ret
2:  ldp     x12, x13, [x1, #ValidatorRef_pubkey]
    ldp     x14, x15, [x1, #(ValidatorRef_pubkey + 16)]
    ldp     x2, x3, [x1, #(ValidatorRef_pubkey + 32)]
    mov     x0, #0
3:  cmp     x0, x11
    b.hs    8f
    ldp     x4, x5, [x10]
    cmp     x4, x12
    ccmp    x5, x13, #0, eq
    b.ne    4f
    ldp     x4, x5, [x10, #16]
    cmp     x4, x14
    ccmp    x5, x15, #0, eq
    b.ne    4f
    ldp     x4, x5, [x10, #32]
    cmp     x4, x2
    ccmp    x5, x3, #0, eq
    b.eq    9f
4:  add     x10, x10, #NODE_VALIDATOR_MEM
    add     x0, x0, #1
    b       3b
8:  mov     x0, #-1
9:  ret
END_FUNCTION lantern_node_api_find_validator

/*
 * L1: the selection of a chunk of a validator stream (node.md, NODE_WORK_API_CHUNK), at the cursor
 * at NodeEvent_api + 16 of the event x23: +16 a bitmap, in the scratch x0, of the validators of the
 * state x20 that the ValidatorRef items of data x21 name (0 with no data); +24 the epoch of the
 * state's slot; +40 the count of the validators selected. x0 = 0, or LANTERN_BUFFER_TOO_SMALL.
 * Locals: L the scratch's next byte, L+8 its end, L+16 the validators, L+24 their count, L+32 the
 * items, L+40 their count, L+48 the table of the public keys, L+56 its mask.
 */
LOCAL_FUNCTION lantern_node_api_validators_prep
    FRAME 64
    ldr     x9, [x0]
    add     x10, x0, x9
    add     x9, x0, #16
    stp     x9, x10, [sp, #16]
    add     x11, x23, #(NodeEvent_api + 16)
    ldr     x9, [x20, #NODE_STATE_SLOT]
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x9, x9, x10
    str     x9, [x11, #24]
    PART    x9, x10, x20, NODE_STATE_VALIDATORS
    stp     x9, x10, [sp, #32]
    str     x10, [x11, #40]                 /* no items: every validator */
    str     xzr, [x11, #16]
    cbz     x21, 90f
    ldr     x9, [x21, #8]
    add     x9, x21, x9
    ldr     x10, [x21, #16]
    lsr     x10, x10, #6
    stp     x9, x10, [sp, #48]
    ldr     x12, [sp, #40]                  /* the bitmap: a bit for each validator */
    add     x12, x12, #63
    lsr     x12, x12, #6
    lsl     x1, x12, #3
    ldp     x0, x13, [sp, #16]
    add     x14, x0, x1
    cmp     x14, x13
    b.hi    97f
    str     x14, [sp, #16]
    add     x11, x23, #(NodeEvent_api + 16)
    str     x0, [x11, #16]
    bl      lantern_zero
    add     x11, x23, #(NodeEvent_api + 16)  /* index items: their bits; then count the public keys */
    ldr     x11, [x11, #16]
    ldp     x9, x10, [sp, #48]
    ldr     x12, [sp, #40]
    mov     x13, #0
1:  cbz     x10, 3f
    ldr     x14, [x9]
    cmp     x14, #API_VALIDATOR_INDEX
    b.ne    2f
    ldr     x14, [x9, #8]
    cmp     x14, x12
    b.hs    21f
    lsr     x15, x14, #6
    ldr     x16, [x11, x15, lsl #3]
    mov     x17, #1
    lsl     x17, x17, x14
    orr     x16, x16, x17
    str     x16, [x11, x15, lsl #3]
    b       21f
2:  add     x13, x13, #1
21: add     x9, x9, #64
    sub     x10, x10, #1
    b       1b
3:  cbz     x13, 80f
    lsl     x13, x13, #1                    /* the table: the least power of two at least twice the keys */
    mov     x14, #1
31: cmp     x14, x13
    b.hs    32f
    lsl     x14, x14, #1
    b       31b
32: sub     x15, x14, #1
    str     x15, [sp, #72]
    ldp     x0, x13, [sp, #16]
    lsl     x1, x14, #3
    add     x14, x0, x1
    cmp     x14, x13
    b.hi    97f
    str     x0, [sp, #64]
    bl      lantern_zero
    ldp     x9, x10, [sp, #48]              /* each public key item: its number + 1, at bytes 8 to 16 of the key */
    ldp     x11, x12, [sp, #64]
    mov     x13, #0
4:  cmp     x13, x10
    b.hs    5f
    ldr     x14, [x9]
    cmp     x14, #API_VALIDATOR_PUBKEY
    b.ne    42f
    ldr     x14, [x9, #(ValidatorRef_pubkey + 8)]
41: and     x14, x14, x12
    ldr     x15, [x11, x14, lsl #3]
    cbz     x15, 43f
    add     x14, x14, #1
    b       41b
43: add     x15, x13, #1
    str     x15, [x11, x14, lsl #3]
42: add     x9, x9, #64
    add     x13, x13, #1
    b       4b
5:  ldp     x9, x10, [sp, #32]              /* each validator whose key the table holds: its bit */
    mov     x13, #0
    add     x16, x23, #(NodeEvent_api + 16)
    ldr     x16, [x16, #16]
51: cmp     x13, x10
    b.hs    80f
    ldr     x14, [x9, #8]
    ldp     x11, x12, [sp, #64]
52: and     x14, x14, x12
    ldr     x15, [x11, x14, lsl #3]
    cbz     x15, 59f
    sub     x15, x15, #1
    ldr     x17, [sp, #48]
    add     x17, x17, x15, lsl #6
    add     x17, x17, #ValidatorRef_pubkey
    ldp     x0, x1, [x9]
    ldp     x2, x3, [x17]
    cmp     x0, x2
    ccmp    x1, x3, #0, eq
    b.ne    58f
    ldp     x0, x1, [x9, #16]
    ldp     x2, x3, [x17, #16]
    cmp     x0, x2
    ccmp    x1, x3, #0, eq
    b.ne    58f
    ldp     x0, x1, [x9, #32]
    ldp     x2, x3, [x17, #32]
    cmp     x0, x2
    ccmp    x1, x3, #0, eq
    b.ne    58f
    lsr     x15, x13, #6
    ldr     x0, [x16, x15, lsl #3]
    mov     x1, #1
    lsl     x1, x1, x13
    orr     x0, x0, x1
    str     x0, [x16, x15, lsl #3]
    b       59f
58: add     x14, x14, #1
    b       52b
59: add     x9, x9, #NODE_VALIDATOR_MEM
    add     x13, x13, #1
    b       51b
80: ldr     x9, [sp, #40]                   /* the count: the bits set */
    add     x9, x9, #63
    lsr     x9, x9, #6
    add     x16, x23, #(NodeEvent_api + 16)
    ldr     x10, [x16, #16]
    mov     x11, #0
81: cbz     x9, 83f
    ldr     x12, [x10], #8
82: cbz     x12, 84f
    sub     x13, x12, #1
    and     x12, x12, x13
    add     x11, x11, #1
    b       82b
84: sub     x9, x9, #1
    b       81b
83: str     x11, [x16, #40]
90: mov     x0, #0
    UNFRAME 64
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 64
END_FUNCTION lantern_node_api_validators_prep

/*
 * L1: the items of the pending stream of the entry x22, of the state x20 (node.md,
 * NODE_WORK_API_CHUNK), from the index at NodeEvent_api + 16 of the event x23, at the writer's
 * cursor x24 up to x26, with , between; then ]} once they are all written. x0 = 1 when whole, 0
 * when more is to come, 2 when the state has no such list. Locals: L the cursor, L+8
 * lantern_node_pending's out, L+32 the kind.
 */
LOCAL_FUNCTION lantern_api_pending_json
    FRAME 48
    add     x9, x23, #(NodeEvent_api + 16)
    str     x9, [sp, #16]
    ldr     x9, [x22, #NodeApi_op]          /* the kind: 0 deposits, 1 partial withdrawals, 2 consolidations */
    sub     x1, x9, #API_OP_GET_PENDING_DEPOSITS
    cmp     x9, #API_OP_GET_PENDING_CONSOLIDATIONS
    mov     x10, #2
    csel    x1, x10, x1, eq
    str     x1, [sp, #48]
    mov     x0, x20
    add     x2, sp, #24
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_pending
    cbnz    x0, 7f
1:  ldr     x9, [sp, #16]
    ldr     x10, [x9]
    ldr     x11, [sp, #32]
    cmp     x10, x11
    b.hs    8f
    sub     x12, x26, x24                   /* room for one more item */
    cmp     x12, #API_ITEM_MAX
    b.lo    9f
    cbz     x10, 2f
    API_LIT api_p_comma
2:  ldr     x9, [sp, #16]
    ldr     x10, [x9]
    ldr     x11, [sp, #24]
    ldr     x12, [sp, #40]
    madd    x0, x10, x12, x11
    ldr     x1, [sp, #48]
    bl      lantern_api_pending_item
    ldr     x9, [sp, #16]
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    b       1b
8:  API_LIT api_v_end
    mov     x0, #1
    UNFRAME 48
9:  mov     x0, #0
    UNFRAME 48
7:  mov     x0, #2
    UNFRAME 48
END_FUNCTION lantern_api_pending_json

/*
 * L1: the JSON of the pending item at x0 of the kind x1 (lantern_node_pending): a PendingDeposit,
 * a PendingPartialWithdrawal or a PendingConsolidation, from its SSZ fields. Locals: the item.
 */
LOCAL_FUNCTION lantern_api_pending_item
    FRAME 16
    str     x0, [sp, #16]
    cmp     x1, #1
    b.eq    20f
    b.hi    30f
    /* {"pubkey":…,"withdrawal_credentials":…,"amount":…,"signature":…,"slot":…} */
    API_LIT api_q_pubkey
    ldr     x0, [sp, #16]
    mov     x1, #48
    bl      lantern_api_qhex
    API_LIT api_q_credentials
    ldr     x0, [sp, #16]
    add     x0, x0, #48
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_q_amount
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #80]
    bl      lantern_api_qdec
    API_LIT api_q_signature
    ldr     x0, [sp, #16]
    add     x0, x0, #88
    mov     x1, #96
    bl      lantern_api_qhex
    API_LIT api_q_slot
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #184]
    bl      lantern_api_qdec
    b       9f
    /* {"validator_index":…,"amount":…,"withdrawable_epoch":…} */
20: API_LIT api_q_validator
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_qdec
    API_LIT api_q_amount
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #8]
    bl      lantern_api_qdec
    API_LIT api_q_withdrawable
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #16]
    bl      lantern_api_qdec
    b       9f
    /* {"source_index":…,"target_index":…} */
30: API_LIT api_q_source
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_qdec
    API_LIT api_q_target
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #8]
    bl      lantern_api_qdec
9:  API_LIT api_end1
    UNFRAME 16
END_FUNCTION lantern_api_pending_item

/*
 * L1: the items of the validator stream of the entry x22, of the state x20, from the cursor at
 * NodeEvent_api + 16 of the event x23 (+0 the next index, +8 the status bits, +16 the bitmap,
 * +24 the epoch, +32 the items written), at the writer's cursor x24 up to x26; then ]} for JSON
 * once they are all written. x0 = 1 when whole, else 0. Locals: L the cursor, L+8 the kind of
 * the items, L+16 the validators' count.
 */
LOCAL_FUNCTION lantern_api_validators_json
    FRAME 32
    add     x9, x23, #(NodeEvent_api + 16)
    str     x9, [sp, #16]
    ldr     x10, [x22, #NodeApi_op]         /* the kind: 0, 1 the balances, 2 the identities, 3 their SSZ */
    mov     x11, #0
    mov     x12, #1
    cmp     x10, #API_OP_GET_STATE_VALIDATOR_BALANCES
    csel    x11, x12, x11, eq
    cmp     x10, #API_OP_POST_STATE_VALIDATOR_BALANCES
    csel    x11, x12, x11, eq
    cmp     x10, #API_OP_POST_STATE_VALIDATOR_IDENTITIES
    b.ne    1f
    ldr     x9, [x22, #NodeApi_flags]
    tst     x9, #API_STREAM_SSZ
    mov     x11, #2
    mov     x12, #3
    csel    x11, x12, x11, ne
1:  str     x11, [sp, #24]
    LDQ     x9, x20, NODE_STATE_VALIDATORS + 8
    str     x9, [sp, #32]
2:  ldr     x9, [sp, #16]
    ldr     x10, [x9]
    ldr     x11, [sp, #32]
    cmp     x10, x11
    b.hs    8f
    ldr     x12, [x9, #16]                  /* with a bitmap: the next validator it names */
    cbz     x12, 3f
    lsr     x13, x10, #6
    ldr     x14, [x12, x13, lsl #3]
    lsr     x14, x14, x10
    cbnz    x14, 21f
    add     x10, x10, #64
    and     x10, x10, #~63
    str     x10, [x9]
    b       2b
21: rbit    x14, x14
    clz     x14, x14
    add     x10, x10, x14
    str     x10, [x9]
3:  ldr     x12, [x9, #8]                   /* with status bits: the validator's status has its bit */
    cbz     x12, 4f
    PART    x13, x14, x20, NODE_STATE_VALIDATORS
    add     x0, x13, x10, lsl #7
    ldr     x1, [x9, #24]
    bl      lantern_api_validator_status
    ldr     x9, [sp, #16]
    ldr     x12, [x9, #8]
    lsr     x12, x12, x0
    tbnz    x12, #0, 4f
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    b       2b
4:  sub     x9, x26, x24                    /* room for one more item */
    cmp     x9, #API_ITEM_MAX
    b.lo    9f
    ldr     x9, [sp, #16]
    ldr     x10, [x9, #32]
    ldr     x11, [sp, #24]
    cmp     x11, #3
    b.eq    5f
    cbz     x10, 5f
    API_LIT api_p_comma
5:  ldr     x9, [sp, #16]
    ldr     x10, [x9, #32]
    add     x10, x10, #1
    str     x10, [x9, #32]
    mov     x0, x20
    ldr     x1, [x9]
    ldr     x2, [sp, #24]
    bl      lantern_api_validator_item
    ldr     x9, [sp, #16]
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    b       2b
8:  ldr     x11, [sp, #24]                  /* all: ]} for JSON */
    cmp     x11, #3
    b.eq    81f
    sub     x9, x26, x24
    cmp     x9, #2
    b.lo    9f
    API_LIT api_v_end
81: mov     x0, #1
    UNFRAME 32
9:  mov     x0, #0
    UNFRAME 32
END_FUNCTION lantern_api_validators_json

/*
 * L1: ,"head":…,"target":…,"source":…,"inactivity":…} of the 48-byte item x0 of lantern_node_attestation_rewards,
 * with ,"inclusion_delay":… before inactivity when the fork of the entry x22 is phase0. Locals: the item.
 */
LOCAL_FUNCTION lantern_api_reward_fields
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_ar_head
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_qint
    API_LIT api_ar_target
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #8]
    bl      lantern_api_qint
    API_LIT api_ar_source
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #16]
    bl      lantern_api_qint
    ldr     x9, [x22, #NodeApi_fork]
    cbnz    x9, 1f
    API_LIT api_ar_inclusion
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #24]
    bl      lantern_api_qdec
1:  API_LIT api_ar_inactivity
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #32]
    bl      lantern_api_qint
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION lantern_api_reward_fields

.set API_REWARD_WINDOW, 256                 /* the validators of one call of lantern_node_attestation_rewards */
.set API_REWARD_ITEM_MAX, 256               /* the room an item may take */

/*
 * L1: the items of getAttestationsRewards (beacon-api.md) of the entry x22, of the state x20, from the
 * cursor at NodeEvent_api + 16 of the event x23 (+0 the next step or validator, +16 the bitmap of the
 * ids, +32 the items written, +48 the part: 0 no totals yet, 1 the ideal items, 2 the validators'
 * items; +56 the totals; +592 the chunk's scratch), at the writer's cursor x24 up to x26; then ]}}
 * once all are written. x0 = 1 when whole, 0 when more is to come, 2 for a state the functions
 * refuse, 3 for a scratch too small. Locals: sp+16 the cursor, sp+24 the window's items, sp+32 its
 * first validator, sp+40 its count, sp+48 a value, sp+56 an ideal item (48).
 */
LOCAL_FUNCTION lantern_api_rewards_json
    FRAME 96
    add     x9, x23, #(NodeEvent_api + 16)
    str     x9, [sp, #16]
    ldr     x10, [x9, #48]
    cmp     x10, #2
    b.eq    5f
    cmp     x10, #1
    b.eq    3f
    mov     x0, x20                         /* the first chunk: the totals, as process_epoch has them */
    add     x1, x19, #Node_config
    mov     x2, #1
    ldr     x3, [x9, #592]
    add     x4, x9, #56
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_reward_totals
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    93f
    cbnz    x0, 92f
    ldr     x9, [sp, #16]
    mov     x10, #1
    str     x10, [x9, #48]
    str     x10, [x9]
    str     xzr, [x9, #32]
3:  ldr     x9, [sp, #16]                   /* the ideal items: each effective balance step */
    ldr     x10, [x9]
    MOVQ    x11, EFFECTIVE_BALANCE_INCREMENT
    mul     x10, x10, x11
    ldr     x11, [x9, #(56 + 72)]
    cmp     x10, x11
    b.hi    4f
    sub     x12, x26, x24
    cmp     x12, #API_REWARD_ITEM_MAX
    b.lo    90f
    str     x10, [sp, #48]
    add     x0, x9, #56
    mov     x1, x10
    add     x2, sp, #56
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_ideal_reward
    ldr     x9, [sp, #16]
    ldr     x10, [x9]
    cmp     x10, #1
    b.eq    31f
    API_LIT api_p_comma
31: API_LIT api_ar_eb
    ldr     x0, [sp, #48]
    bl      lantern_api_qdec
    add     x0, sp, #56
    bl      lantern_api_reward_fields
    ldr     x9, [sp, #16]
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    b       3b
4:  sub     x12, x26, x24                   /* then the validators */
    cmp     x12, #32
    b.lo    90f
    API_LIT api_ar_total
    ldr     x9, [sp, #16]
    mov     x10, #2
    str     x10, [x9, #48]
    str     xzr, [x9]
    str     xzr, [x9, #32]
5:  ldr     x9, [sp, #16]                   /* a window of validators from the next */
    ldr     x10, [x9]
    LDQ     x11, x20, NODE_STATE_VALIDATORS + 8
    cmp     x10, x11
    b.hs    8f
    sub     x12, x11, x10
    mov     x13, #API_REWARD_WINDOW
    cmp     x12, x13
    csel    x12, x12, x13, lo
    stp     x10, x12, [sp, #32]
    ldr     x3, [x9, #592]                  /* its items at the end of the chunk's scratch */
    ldr     x13, [x3]
    mov     x14, #48
    mul     x14, x12, x14
    subs    x13, x13, x14
    b.lo    93f
    str     x13, [x3]
    add     x14, x3, x13
    str     x14, [sp, #24]
    mov     x0, x20
    add     x1, x19, #Node_config
    add     x2, x9, #56
    ldp     x3, x4, [sp, #32]
    ldr     x5, [x9, #592]
    ldr     x6, [sp, #24]
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_attestation_rewards
    ldr     x9, [sp, #16]                   /* the scratch's size again */
    ldr     x3, [x9, #592]
    ldr     x13, [x3]
    ldr     x12, [sp, #40]
    mov     x14, #48
    madd    x13, x12, x14, x13
    str     x13, [x3]
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    93f
    cbnz    x0, 92f
    str     xzr, [sp, #48]
6:  ldr     x10, [sp, #48]                  /* each validator of the window: named by the ids, or with none eligible */
    ldp     x11, x12, [sp, #32]
    cmp     x10, x12
    b.hs    7f
    add     x13, x11, x10
    ldr     x14, [sp, #24]
    mov     x15, #48
    madd    x14, x10, x15, x14
    ldr     x9, [sp, #16]
    ldr     x15, [x9, #16]
    cbz     x15, 61f
    lsr     x0, x13, #6
    ldr     x0, [x15, x0, lsl #3]
    lsr     x0, x0, x13
    tbz     x0, #0, 69f
    b       62f
61: ldr     x0, [x14, #40]
    cbz     x0, 69f
62: sub     x0, x26, x24
    cmp     x0, #API_REWARD_ITEM_MAX
    b.lo    68f
    ldr     x0, [x9, #32]
    add     x1, x0, #1
    str     x1, [x9, #32]
    cbz     x0, 63f
    API_LIT api_p_comma
63: API_LIT api_q_validator
    ldp     x11, x12, [sp, #32]
    ldr     x10, [sp, #48]
    add     x0, x11, x10
    bl      lantern_api_qdec
    ldr     x10, [sp, #48]
    ldr     x14, [sp, #24]
    mov     x15, #48
    madd    x0, x10, x15, x14
    bl      lantern_api_reward_fields
69: ldr     x10, [sp, #48]
    add     x10, x10, #1
    str     x10, [sp, #48]
    b       6b
68: ldr     x9, [sp, #16]                   /* no room: the next chunk goes on from this validator */
    ldr     x11, [sp, #32]
    ldr     x10, [sp, #48]
    add     x11, x11, x10
    str     x11, [x9]
    b       90f
7:  ldr     x9, [sp, #16]
    ldp     x11, x12, [sp, #32]
    add     x11, x11, x12
    str     x11, [x9]
    b       5b
8:  sub     x12, x26, x24                   /* all: ]}} */
    cmp     x12, #4
    b.lo    90f
    API_LIT api_ar_end
    mov     x0, #1
    UNFRAME 96
90: mov     x0, #0
    UNFRAME 96
92: mov     x0, #2
    UNFRAME 96
93: mov     x0, #3
    UNFRAME 96
END_FUNCTION lantern_api_rewards_json

/*
 * L0: x0 = the epoch of getEpochCommittees of the route x0 and the state of the view x1 (beacon-api.md,
 * Common rules), or 2^64 - 1 for 400: an epoch above the state's + 1, one whose seed's RANDAO mix the
 * state no longer holds, or a slot of another epoch. A leaf. Uses x9-x13.
 */
LOCAL_FUNCTION lantern_node_api_committees_check
    UNWIND_END_PROLOGUE
    ldr     x9, [x1, #ApiView_head_slot]    /* the state's epoch */
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x9, x9, x10
    ldr     x11, [x0, #ApiRoute_present]
    mov     x12, x9
    tbz     x11, #API_PARAM_EPOCH, 1f
    ldr     x12, [x0, #ApiRoute_epoch]
1:  add     x13, x9, #1                     /* at most the state's epoch + 1 */
    cmp     x12, x13
    b.hi    8f
    MOVQ    x10, EPOCHS_PER_HISTORICAL_VECTOR   /* epoch - MIN_SEED_LOOKAHEAD - 1 at least epoch + 1 - EPOCHS_PER_HISTORICAL_VECTOR, each 0 when below */
    subs    x13, x13, x10
    csel    x13, xzr, x13, lo
    subs    x10, x12, #(MIN_SEED_LOOKAHEAD + 1)
    csel    x10, xzr, x10, lo
    cmp     x10, x13
    b.lo    8f
    tbz     x11, #API_PARAM_SLOT, 2f        /* a slot of the epoch */
    ldr     x10, [x0, #ApiRoute_slot]
    mov     x13, #SLOTS_PER_EPOCH
    udiv    x10, x10, x13
    cmp     x10, x12
    b.ne    8f
2:  mov     x0, x12
    ret
8:  mov     x0, #-1
    ret
END_FUNCTION lantern_node_api_committees_check

/*
 * L0: the cursor of the getEpochCommittees stream of the entry x0, for the route x1 and the epoch x2
 * (node.md, NODE_EV_API): the first slot at 0, the first index at 8, the epoch at 24, the slot and
 * the index asked at 40 and 48 (2^64 - 1 for none). A leaf. Uses x9-x12.
 */
LOCAL_FUNCTION lantern_node_api_committees_cursor
    UNWIND_END_PROLOGUE
    add     x9, x0, #NodeApi_cursor
    str     x2, [x9, #24]
    ldr     x10, [x1, #ApiRoute_present]
    mov     x11, #SLOTS_PER_EPOCH
    mul     x11, x2, x11
    mov     x12, #-1
    tbz     x10, #API_PARAM_SLOT, 1f
    ldr     x11, [x1, #ApiRoute_slot]
    mov     x12, x11
1:  str     x11, [x9]
    str     x12, [x9, #40]
    mov     x11, #0
    mov     x12, #-1
    tbz     x10, #API_PARAM_INDEX, 2f
    ldr     x11, [x1, #ApiRoute_index]
    mov     x12, x11
2:  str     x11, [x9, #8]
    str     x12, [x9, #48]
    ret
END_FUNCTION lantern_node_api_committees_cursor

/*
 * L1: a chunk's start of a getEpochCommittees stream (node.md, NODE_WORK_API_CHUNK), at the cursor at
 * NodeEvent_api + 16 of the event x23: +56 get_committee_count_per_slot of the state x20 at the epoch
 * at +24; +72 the scratch x0, for lantern_api_committees_json. x0 = 0; 400 for an index asked at or past the
 * count, in the first chunk; LANTERN_BUFFER_TOO_SMALL for a scratch with no room for a committee and
 * lantern_get_beacon_committee; else the status of the count. Locals: L the epoch, L+8 the count.
 */
LOCAL_FUNCTION lantern_node_api_committees_prep
    FRAME 16
    add     x9, x23, #(NodeEvent_api + 16)
    str     x0, [x9, #72]
    mov     x3, x0
    ldr     x10, [x9, #24]
    str     x10, [sp, #16]
    mov     x0, x20
    add     x1, sp, #16
    LDQ     x2, x19, Node_config + CONFIG_COMMITTEE_CACHE
    add     x4, sp, #24
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL get_committee_count_per_slot
    cbnz    x0, 9f
    add     x9, x23, #(NodeEvent_api + 16)
    ldr     x10, [sp, #24]
    str     x10, [x9, #56]
    LDQ     x11, x20, NODE_STATE_VALIDATORS + 8     /* the scratch: 16, a committee's list, then S(2) */
    mov     x12, #SLOTS_PER_EPOCH
    mul     x12, x10, x12
    udiv    x12, x11, x12
    add     x12, x12, #1
    lsl     x12, x12, #3
    add     x12, x12, #(16 + LIST_FIXED)
    lsl     x11, x11, #3
    add     x11, x11, #LIST_FIXED
    add     x12, x12, x11, lsl #1
    MOVQ    x11, LANTERN_SCRATCH_FIXED
    add     x12, x12, x11
    ldr     x11, [x9, #72]
    ldr     x11, [x11]
    cmp     x11, x12
    b.lo    97f
    ldr     x11, [x23, #(NodeEvent_api + 8)]   /* the first chunk: an index at or past the count, 400 */
    tst     x11, #API_STREAM_STARTED
    b.ne    9f
    ldr     x11, [x9, #48]
    cmn     x11, #1
    b.eq    9f
    cmp     x11, x10
    b.lo    9f
    mov     x0, #400
9:  UNFRAME 16
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    UNFRAME 16
END_FUNCTION lantern_node_api_committees_prep

/*
 * L1: the items of the getEpochCommittees stream of the entry x22, of the state x20, from the cursor
 * at NodeEvent_api + 16 of the event x23 (+0 the slot, +8 the index, +16 the member, +24 the epoch,
 * +32 the items written, +40 and +48 the slot and the index asked or 2^64 - 1, +56 the committees per
 * slot, +64 1 within an item, +72 the scratch), at the writer's cursor x24 up to x26; then ]} once
 * they are all written. x0 = 1 when whole, 0 when more is to come, 2 when a committee fails.
 * Locals: L the cursor, L+8 the slot, L+16 the index, L+24 the committee's list.
 */
LOCAL_FUNCTION lantern_api_committees_json
    FRAME 48
    add     x9, x23, #(NodeEvent_api + 16)
    str     x9, [sp, #16]
1:  ldr     x9, [sp, #16]
    ldp     x10, x11, [x9]                  /* the slot and the index */
    ldr     x12, [x9, #40]                  /* the last slot: the one asked, else the epoch's last */
    cmn     x12, #1
    b.ne    2f
    ldr     x12, [x9, #24]
    add     x12, x12, #1
    mov     x13, #SLOTS_PER_EPOCH
    mul     x12, x12, x13
    sub     x12, x12, #1
2:  cmp     x10, x12
    b.hi    8f
    ldr     x12, [x9, #48]                  /* the end of the indices: past the one asked, else the count */
    ldr     x13, [x9, #56]
    cmn     x12, #1
    b.eq    21f
    add     x13, x12, #1
21: cmp     x11, x13
    b.lo    3f
    add     x10, x10, #1                    /* the slot's committees are written: the next slot */
    cmn     x12, #1
    csel    x11, xzr, x12, eq
    stp     x10, x11, [x9]
    b       1b
3:  ldr     x12, [x9, #64]
    cbnz    x12, 4f
    sub     x13, x26, x24                   /* the item's head: {"index":…,"slot":…,"validators":[ */
    cmp     x13, #80
    b.lo    9f
    ldr     x13, [x9, #32]
    cbz     x13, 31f
    API_LIT api_p_comma
31: ldr     x9, [sp, #16]
    ldr     x13, [x9, #32]
    add     x13, x13, #1
    str     x13, [x9, #32]
    mov     x13, #1
    str     x13, [x9, #64]
    str     xzr, [x9, #16]
    API_LIT api_v_index
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #8]
    bl      lantern_api_qdec
    API_LIT api_c_slot
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_qdec
    API_LIT api_c_validators
4:  ldr     x9, [sp, #16]                   /* the committee, in a list after 16 bytes of the scratch */
    ldp     x10, x11, [x9]
    stp     x10, x11, [sp, #24]
    ldr     x12, [x9, #72]
    LDQ     x13, x20, NODE_STATE_VALIDATORS + 8
    ldr     x14, [x9, #56]
    mov     x15, #SLOTS_PER_EPOCH
    mul     x14, x14, x15
    udiv    x13, x13, x14
    add     x13, x13, #1
    lsl     x13, x13, #3
    add     x13, x13, #LIST_FIXED
    add     x14, x12, #16
    str     x13, [x14]
    mov     x15, #LIST_FIXED
    stp     x15, xzr, [x14, #LIST_OFFSET]
    str     x14, [sp, #40]
    add     x13, x13, #16
    SCRATCH_REST x4, x12, x13
    mov     x0, x20
    add     x1, sp, #24
    add     x2, sp, #32
    LDQ     x3, x19, Node_config + CONFIG_COMMITTEE_CACHE
    ldr     x5, [sp, #40]
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL get_beacon_committee
    cbnz    x0, 7f
41: ldr     x9, [sp, #16]                   /* its members from the one at +16 */
    ldr     x10, [x9, #16]
    ldr     x11, [sp, #40]
    ldr     x12, [x11, #LIST_COUNT]
    cmp     x10, x12
    b.hs    5f
    sub     x13, x26, x24
    cmp     x13, #24
    b.lo    9f
    cbz     x10, 42f
    API_LIT api_p_comma
42: ldr     x9, [sp, #16]
    ldr     x10, [x9, #16]
    ldr     x11, [sp, #40]
    add     x11, x11, #LIST_FIXED
    ldr     x0, [x11, x10, lsl #3]
    add     x10, x10, #1
    str     x10, [x9, #16]
    bl      lantern_api_qdec
    b       41b
5:  sub     x13, x26, x24                   /* the item's end: ]} */
    cmp     x13, #2
    b.lo    9f
    API_LIT api_v_end
    ldr     x9, [sp, #16]
    str     xzr, [x9, #64]
    ldr     x11, [x9, #8]
    add     x11, x11, #1
    str     x11, [x9, #8]
    b       1b
7:  mov     x0, #2
    UNFRAME 48
8:  sub     x13, x26, x24                   /* all: ]} */
    cmp     x13, #2
    b.lo    9f
    API_LIT api_v_end
    mov     x0, #1
    UNFRAME 48
9:  mov     x0, #0
    UNFRAME 48
END_FUNCTION lantern_api_committees_json

/*
 * L1: the ids of the validator operation of the route x0 (node.md, NODE_EV_API): x0 = the new id
 * of a NODE_ACT_BYTES_PUT of its ValidatorRef items (getStateValidator: its validator_id), or 0
 * with none. Locals: a ByteList head whose offset reaches the items.
 */
LOCAL_FUNCTION lantern_node_api_ids
    FRAME 32
    ldr     x9, [x0, #ApiRoute_op]
    cmp     x9, #API_OP_GET_STATE_VALIDATOR
    b.ne    1f
    add     x10, x0, #ApiRoute_validator
    mov     x11, #64
    b       2f
1:  ldp     x10, x11, [x0, #ApiRoute_list]
    add     x10, x0, x10
    mov     x0, #0
    cbz     x11, 9f
    lsl     x11, x11, #6
2:  add     x12, sp, #16
    sub     x13, x10, x12
    stp     x11, x13, [x12]
    str     x11, [x12, #16]
    mov     x0, x12
    bl      lantern_node_put
9:  UNFRAME 32
END_FUNCTION lantern_node_api_ids

/*
 * L1: the body of the kind x28 for the view x22: an error body of the status at [x0], or the
 * JSON of an operation (beacon-api.md, Common rules). Locals: x0.
 */
LOCAL_FUNCTION lantern_api_body
    FRAME 16
    str     x0, [sp, #16]
    cmp     x28, #API_BODY_ERROR
    b.ne    1f
    /* {"code":<n>,"message":"<m>"} */
    API_LIT api_e_code
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_dec
    API_LIT api_e_message
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_code
    mov     x1, #24
    bl      lantern_api_code_text
    API_LIT api_e_end
    UNFRAME 16
1:  cmp     x28, #API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE
    b.ne    102f
    bl      lantern_api_lc_updates_body
    UNFRAME 16
102: sub    x9, x28, #API_OP_GET_LIGHT_CLIENT_BOOTSTRAP   /* the light client reads: SSZ, or {"version":…,"data":…} */
    cmp     x9, #(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP)
    b.hi    10f
    LDQ     x9, x22, ApiView_lc_json
    cbnz    x9, 101f
    LDQ     x9, x22, ApiView_lc_bytes
    ldr     x10, [x9, #8]
    add     x0, x9, x10
    ldr     x1, [x9, #16]
    bl      lantern_api_put
    UNFRAME 16
101: API_LIT api_j_version
    ldr     x0, [x22, #ApiView_fork]
    bl      lantern_api_fork_name
    API_LIT api_g_data
    LDQ     x9, x22, ApiView_lc_json
    ldr     x10, [x9, #8]
    add     x0, x9, x10
    ldr     x1, [x9, #16]
    bl      lantern_api_put
    API_LIT api_end1
    UNFRAME 16
10: cmp     x28, #API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    b.ne    11f
    /* {"code":400,"message":"BAD_REQUEST","failures":[…]}: x22 the event of the work */
    API_LIT api_e_code
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_dec
    API_LIT api_e_message
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      lantern_api_code
    mov     x1, #24
    bl      lantern_api_code_text
    API_LIT api_f_list
    bl      lantern_api_failures
    UNFRAME 16
11: cmp     x28, #API_OP_GET_PEERS
    b.ne    116f
    bl      lantern_api_peers_body
    UNFRAME 16
116: cmp    x28, #API_OP_GET_PEER
    b.ne    117f
    API_LIT api_pe_data
    ldr     x0, [x22, #ApiView_peer]
    bl      lantern_api_peer_item
    API_LIT api_end1
    UNFRAME 16
117: cmp    x28, #API_OP_GET_DEBUG_CHAIN_HEADS_V2
    b.ne    110f
    bl      lantern_api_heads_body
    UNFRAME 16
110: cmp    x28, #API_OP_GET_DEBUG_FORK_CHOICE
    b.ne    115f
    bl      lantern_api_fork_choice_body
    UNFRAME 16
115: cmp    x28, #API_OP_GET_STATE_RANDAO
    b.eq    111f
    cmp     x28, #API_OP_GET_EPOCH_SYNC_COMMITTEES
    b.eq    112f
    cmp     x28, #API_OP_GET_PROPOSER_LOOKAHEAD
    b.eq    113f
    cmp     x28, #API_OP_PRODUCE_ATTESTATION_DATA
    b.ne    12f
    b       114f
111:
112:
113: ldr    x0, [sp, #16]                   /* the state reads */
    bl      lantern_api_state_read_body
    UNFRAME 16
114: ldr    x9, [sp, #16]                   /* SSZ: its 128 bytes */
    ldr     x9, [x9, #8]
    tbz     x9, #3, 13f
    ADDQ    x0, x22, ApiView_att
    mov     x1, #128
    bl      lantern_api_put
    UNFRAME 16
    /* {"data":{"slot":…,"index":…,"beacon_block_root":…,"source":…,"target":…}} */
13: API_LIT api_a_slot
    LDQ     x0, x22, ApiView_att
    bl      lantern_api_qdec
    API_LIT api_a_index
    LDQ     x0, x22, ApiView_att + 8
    bl      lantern_api_qdec
    API_LIT api_a_root
    ADDQ    x0, x22, ApiView_att + 16
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_a_source
    ADDQ    x0, x22, ApiView_att + 48
    bl      lantern_api_checkpoint
    API_LIT api_a_target
    ADDQ    x0, x22, ApiView_att + 88
    bl      lantern_api_checkpoint
    API_LIT api_end2
    UNFRAME 16
12: cmp     x28, #API_OP_GET_NETWORK_IDENTITY
    b.ne    2f
    API_LIT api_i_peer_id
    add     x0, x22, #ApiView_peer_id
    bl      lantern_api_text
    API_LIT api_i_enr
    add     x0, x22, #ApiView_enr
    bl      lantern_api_text
    API_LIT api_i_p2p
    ldr     x9, [x22, #ApiView_p2p_address]
    cbz     x9, 14f
    add     x0, x22, #ApiView_p2p_address
    bl      lantern_api_text
14: API_LIT api_i_discovery
    ldr     x9, [x22, #ApiView_discovery_address]
    cbz     x9, 15f
    add     x0, x22, #ApiView_discovery_address
    bl      lantern_api_text
15: API_LIT api_i_seq
    ldr     x0, [x22, #ApiView_seq_number]
    bl      lantern_api_qdec
    API_LIT api_i_attnets
    add     x0, x22, #ApiView_attnets
    mov     x1, #8
    bl      lantern_api_qhex
    ldr     x9, [x22, #ApiView_fork]
    cmp     x9, #FORK_ALTAIR
    b.lo    16f
    API_LIT api_i_syncnets
    add     x0, x22, #ApiView_syncnets
    mov     x1, #1
    bl      lantern_api_qhex
    ldr     x9, [x22, #ApiView_fork]
    cmp     x9, #FORK_FULU
    b.lo    16f
    API_LIT api_i_cgc
    ldr     x0, [x22, #ApiView_custody_group_count]
    bl      lantern_api_qdec
16: API_LIT api_end3
    UNFRAME 16
2:  cmp     x28, #API_OP_GET_NODE_VERSION
    b.ne    3f
    API_LIT api_v_version
    add     x0, x22, #ApiView_version
    bl      lantern_api_text
    API_LIT api_end2
    UNFRAME 16
3:  cmp     x28, #API_OP_GET_SYNCING_STATUS
    b.ne    4f
    API_LIT api_s_head
    ldr     x0, [x22, #ApiView_head_slot]
    bl      lantern_api_qdec
    API_LIT api_s_distance
    ldr     x9, [x22, #ApiView_current_slot]
    ldr     x10, [x22, #ApiView_head_slot]
    subs    x0, x9, x10
    csel    x0, xzr, x0, lo
    bl      lantern_api_qdec
    API_LIT api_s_syncing
    ldr     x0, [x22, #ApiView_is_syncing]
    bl      lantern_api_bool
    API_LIT api_s_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_s_offline
    ldr     x0, [x22, #ApiView_el_offline]
    bl      lantern_api_bool
    API_LIT api_end2
    UNFRAME 16
4:  cmp     x28, #API_OP_GET_PEER_COUNT
    b.ne    5f
    API_LIT api_c_connected
    ldr     x0, [x22, #ApiView_peers]
    bl      lantern_api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  cmp     x28, #API_OP_GET_GENESIS
    b.ne    6f
    API_LIT api_g_time
    ldr     x0, [x22, #ApiView_genesis_time]
    bl      lantern_api_qdec
    API_LIT api_g_root
    add     x0, x22, #ApiView_genesis_validators_root
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_g_version
    add     x0, x22, #ApiView_genesis_fork_version
    mov     x1, #4
    bl      lantern_api_qhex
    API_LIT api_end2
    UNFRAME 16
6:  cmp     x28, #API_OP_GET_BLOCK_HEADER
    b.ne    7f
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      lantern_api_bool
    API_LIT api_x_data
    API_LIT api_h_root
    add     x0, x22, #ApiView_head_root
    mov     x1, #32
    bl      lantern_api_qhex
    ldr     x0, [x22, #ApiView_head_slot]
    add     x1, x22, #ApiView_proposer_index
    ldr     x2, [x22, #ApiView_canonical]
    bl      lantern_api_header_json
    API_LIT api_end3
    UNFRAME 16
7:  cmp     x28, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.ne    9f
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      lantern_api_bool
    API_LIT api_x_data
    API_LIT api_f_previous
    add     x0, x22, #ApiView_previous_justified
    bl      lantern_api_checkpoint
    API_LIT api_f_current
    add     x0, x22, #ApiView_current_justified
    bl      lantern_api_checkpoint
    API_LIT api_f_finalized
    add     x0, x22, #ApiView_finalized
    bl      lantern_api_checkpoint
    API_LIT api_end2
    UNFRAME 16
9:  cmp     x28, #API_OP_GET_BLOCK_ROOT     /* getBlockRoot, getStateRoot: {"execution_optimistic":…,"finalized":…,"data":{"root":…}} */
    b.eq    10f
    cmp     x28, #API_OP_GET_STATE_ROOT
    b.eq    10f
    cmp     x28, #API_OP_GET_STATE_FORK
    b.ne    12f
10: API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      lantern_api_bool
    API_LIT api_x_data
    cmp     x28, #API_OP_GET_STATE_FORK
    b.eq    11f
    API_LIT api_h_root
    add     x0, x22, #ApiView_head_root
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_end2
    UNFRAME 16
    /* getStateFork: {"previous_version":…,"current_version":…,"epoch":…} */
11: API_LIT api_k_previous
    ADDQ    x0, x22, ApiView_state_fork
    mov     x1, #4
    bl      lantern_api_qhex
    API_LIT api_k_current
    ADDQ    x0, x22, ApiView_state_fork + 4
    mov     x1, #4
    bl      lantern_api_qhex
    API_LIT api_k_epoch
    LDQ     x0, x22, ApiView_state_fork + 8
    bl      lantern_api_qdec
    API_LIT api_end2
    UNFRAME 16
12: cmp     x28, #API_OP_GET_SPEC
    b.ne    13f
    bl      lantern_api_spec
    UNFRAME 16
13: cmp     x28, #API_OP_GET_FORK_SCHEDULE
    b.ne    17f
    bl      lantern_api_fork_schedule
    UNFRAME 16
17: cmp     x28, #API_OP_GET_DEPOSIT_CONTRACT   /* {"data":{"chain_id":…,"address":…}} */
    b.ne    18f
    API_LIT api_d_chain
    ldr     x9, [x22, #ApiView_config]
    LDQ     x0, x9, CONFIG_DEPOSIT_CHAIN_ID
    bl      lantern_api_qdec
    API_LIT api_d_address
    ldr     x9, [x22, #ApiView_config]
    ADDQ    x0, x9, CONFIG_DEPOSIT_CONTRACT_ADDRESS
    mov     x1, #20
    bl      lantern_api_qhex
    API_LIT api_end2
    UNFRAME 16
18: cmp     x28, #API_OP_GET_STATE_VALIDATOR    /* {"execution_optimistic":…,"finalized":…,"data":<item>} */
    b.ne    19f
    API_LIT api_v_open
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      lantern_api_bool
    API_LIT api_v_data
    ldr     x0, [x22, #ApiView_val_state]
    ldr     x1, [x22, #ApiView_val_index]
    mov     x2, #0
    bl      lantern_api_validator_item
    API_LIT api_end1
    UNFRAME 16
    /* getProposerDuties and getProposerDutiesV2: {"dependent_root":…,"execution_optimistic":…,"data":[{"pubkey":…,"validator_index":…,"slot":…},…]} */
19: cmp     x28, #API_OP_GET_PROPOSER_DUTIES
    b.eq    190f
    cmp     x28, #API_OP_GET_PROPOSER_DUTIES_V2
    b.ne    18f
190: API_LIT api_u_root
    add     x0, x22, #ApiView_duties
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_u_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_v_list
    str     xzr, [sp, #24]
20: ldr     x9, [sp, #24]
    cmp     x9, #SLOTS_PER_EPOCH
    b.hs    21f
    ldr     x10, [x22, #ApiView_val_state]
    ldr     x10, [x10, #NODE_STATE_SLOT]
    adds    x10, x10, x9                    /* the slot; slot 0 has no item: its block is the genesis block */
    b.eq    23f
    cmp     x10, #1                         /* a comma before each item past the first: past the epoch's first slot and past slot 1 */
    b.ls    22f
    cbz     x9, 22f
    API_LIT api_p_comma
22: API_LIT api_u_pubkey
    ldr     x9, [sp, #24]
    add     x10, x22, #(ApiView_duties + 32)
    ldr     x1, [x10, x9, lsl #3]
    ldr     x0, [x22, #ApiView_val_state]
    PART    x9, x10, x0, NODE_STATE_VALIDATORS
    add     x0, x9, x1, lsl #7              /* NODE_VALIDATOR_MEM: the pubkey first */
    mov     x1, #48
    bl      lantern_api_qhex
    API_LIT api_u_index
    ldr     x9, [sp, #24]
    add     x10, x22, #(ApiView_duties + 32)
    ldr     x0, [x10, x9, lsl #3]
    bl      lantern_api_qdec
    API_LIT api_c_slot
    ldr     x9, [x22, #ApiView_val_state]
    ldr     x0, [x9, #NODE_STATE_SLOT]
    ldr     x9, [sp, #24]
    add     x0, x0, x9
    bl      lantern_api_qdec
    API_LIT api_end1
23: ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       20b
21: API_LIT api_v_end
    UNFRAME 16
    /* {"dependent_root":…,"execution_optimistic":…,"data":[{"pubkey":…,…,"slot":…},…]}, x21 the items written */
18: cmp     x28, #API_OP_GET_SYNC_COMMITTEE_DUTIES
    b.ne    181f
    bl      lantern_api_sync_duties_body
    UNFRAME 16
181: cmp    x28, #API_OP_GET_ATTESTER_DUTIES
    b.ne    182f
    API_LIT api_u_root
    LDQ     x0, x22, ApiView_ad_out
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_u_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_v_list
    mov     x21, #0
    str     xzr, [sp, #24]
17: ldr     x9, [sp, #24]
    LDQ     x10, x22, ApiView_ad_count
    cmp     x9, x10
    b.hs    16f
    LDQ     x10, x22, ApiView_ad_out
    mov     x11, #48
    madd    x10, x9, x11, x10
    add     x10, x10, #40
    str     x10, [sp, #16]
    ldr     x11, [x10]
    cbz     x11, 15f
    cbz     x21, 14f
    API_LIT api_p_comma
14: add     x21, x21, #1
    API_LIT api_u_pubkey
    ldr     x12, [x22, #ApiView_val_state]
    PART    x9, x10, x12, NODE_STATE_VALIDATORS
    ldr     x11, [sp, #16]
    ldr     x11, [x11, #40]
    add     x0, x9, x11, lsl #7             /* NODE_VALIDATOR_MEM: the pubkey first */
    mov     x1, #48
    bl      lantern_api_qhex
    API_LIT api_u_index
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #40]
    bl      lantern_api_qdec
    API_LIT api_t_committee_index
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #16]
    bl      lantern_api_qdec
    API_LIT api_t_committee_length
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #24]
    bl      lantern_api_qdec
    API_LIT api_t_committees_at_slot
    LDQ     x9, x22, ApiView_ad_out
    ldr     x0, [x9, #32]
    bl      lantern_api_qdec
    API_LIT api_t_validator_committee_index
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #32]
    bl      lantern_api_qdec
    API_LIT api_c_slot
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #8]
    bl      lantern_api_qdec
    API_LIT api_end1
15: ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       17b
16: API_LIT api_v_end
    UNFRAME 16
    /* getLiveness: {"data":[{"index":…,"is_live":…},…]} */
182: cmp    x28, #API_OP_GET_LIVENESS
    b.ne    183f
    bl      lantern_api_liveness_body
    b       99f
    /* getBlockRewards and getSyncCommitteeRewards */
183: cmp    x28, #API_OP_GET_BLOCK_REWARDS
    b.ne    184f
    bl      lantern_api_rewards_body
    b       99f
184: cmp    x28, #API_OP_GET_SYNC_COMMITTEE_REWARDS
    b.ne    99f
    bl      lantern_api_sync_rewards_body
99: UNFRAME 16
END_FUNCTION lantern_api_body

/* L0: the 48 bytes of the pubkey of validator x0 of the state x1 among the ValidatorRef items of the ByteList x2, or its index: x0 = 1, else 0. Uses x3-x13. */
LOCAL_FUNCTION lantern_api_names
    UNWIND_END_PROLOGUE
    PART    x3, x4, x1, NODE_STATE_VALIDATORS
    mov     x5, #NODE_VALIDATOR_MEM
    madd    x3, x0, x5, x3                  /* the validator's pubkey */
    ldr     x5, [x2, #8]
    add     x5, x2, x5
    ldr     x6, [x2, #16]
    lsr     x6, x6, #6
1:  cbz     x6, 8f
    ldr     x7, [x5]
    cmp     x7, #API_VALIDATOR_INDEX
    b.ne    2f
    ldr     x7, [x5, #8]
    cmp     x7, x0
    b.eq    9f
    b       3f
2:  ldp     x7, x8, [x5, #ValidatorRef_pubkey]
    ldp     x9, x10, [x3]
    cmp     x7, x9
    ccmp    x8, x10, #0, eq
    b.ne    3f
    ldp     x7, x8, [x5, #(ValidatorRef_pubkey + 16)]
    ldp     x9, x10, [x3, #16]
    cmp     x7, x9
    ccmp    x8, x10, #0, eq
    b.ne    3f
    ldp     x7, x8, [x5, #(ValidatorRef_pubkey + 32)]
    ldp     x9, x10, [x3, #32]
    cmp     x7, x9
    ccmp    x8, x10, #0, eq
    b.eq    9f
3:  add     x5, x5, #64
    sub     x6, x6, #1
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lantern_api_names

/* L1: the signed (two's complement) x0 in decimal, in quotes, with - before a value below 0. Locals: x0. */
LOCAL_FUNCTION lantern_api_qint
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_quote
    ldr     x0, [sp, #16]
    tbz     x0, #63, 1f
    API_LIT api_rw_minus
    ldr     x0, [sp, #16]
    neg     x0, x0
1:  bl      lantern_api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION lantern_api_qint

/*
 * L1: the body of getBlockRewards (beacon-api.md): {"execution_optimistic":…,"finalized":…,"data":{"proposer_index":…,
 * "total":…,"attestations":…,"sync_aggregate":…,"proposer_slashings":…,"attester_slashings":…}} of the 48 bytes of
 * lantern_node_block_rewards at ApiView_live_out of the view x22.
 */
.macro REWARD_FIELD text, off
    API_LIT \text
    LDQ     x9, x22, ApiView_live_out
    ldr     x0, [x9, #\off]
    bl      lantern_api_qdec
.endm
LOCAL_FUNCTION lantern_api_rewards_body
    FRAME 0
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      lantern_api_bool
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

/*
 * L1: the body of getSyncCommitteeRewards (beacon-api.md): {"execution_optimistic":…,"finalized":…,"data":[{"validator_index":…,
 * "reward":…},…]} of the items of lantern_node_sync_rewards at ApiView_live_out of the view x22; with ValidatorRef items at
 * ApiView_sd_ids, those of the validators of ApiView_val_state that one names. Locals: the item, the items written.
 */
LOCAL_FUNCTION lantern_api_sync_rewards_body
    FRAME 16
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      lantern_api_bool
    API_LIT api_v_list
    stp     xzr, xzr, [sp, #16]
1:  LDQ     x9, x22, ApiView_live_out
    ldr     x10, [x9, #16]
    lsr     x10, x10, #4
    ldr     x11, [sp, #16]
    cmp     x11, x10
    b.hs    9f
    ldr     x12, [x9, #8]
    add     x12, x9, x12
    add     x12, x12, x11, lsl #4
    ldr     x0, [x12]
    LDQ     x2, x22, ApiView_sd_ids
    cbz     x2, 2f
    ldr     x1, [x22, #ApiView_val_state]
    bl      lantern_api_names
    cbz     x0, 5f
2:  ldr     x11, [sp, #24]
    cbz     x11, 3f
    API_LIT api_p_comma
3:  API_LIT api_q_validator
    LDQ     x9, x22, ApiView_live_out
    ldr     x12, [x9, #8]
    add     x12, x9, x12
    ldr     x11, [sp, #16]
    add     x12, x12, x11, lsl #4
    ldr     x0, [x12]
    bl      lantern_api_qdec
    API_LIT api_rw_reward
    LDQ     x9, x22, ApiView_live_out
    ldr     x12, [x9, #8]
    add     x12, x9, x12
    ldr     x11, [sp, #16]
    add     x12, x12, x11, lsl #4
    ldr     x0, [x12, #8]
    bl      lantern_api_qint
    API_LIT api_end1
    ldr     x11, [sp, #24]
    add     x11, x11, #1
    str     x11, [sp, #24]
5:  ldr     x11, [sp, #16]
    add     x11, x11, #1
    str     x11, [sp, #16]
    b       1b
9:  API_LIT api_v_end
    UNFRAME 16
END_FUNCTION lantern_api_sync_rewards_body

/*
 * L1: the body of getLiveness (beacon-api.md): {"data":[{"index":…,"is_live":…},…]} of the
 * ValidatorRef items at ApiView_sd_ids of the view x22, each by its byte at ApiView_live_out.
 * Locals: the item's index.
 */
LOCAL_FUNCTION lantern_api_liveness_body
    FRAME 16
    API_LIT api_p_data
    str     xzr, [sp, #16]
1:  LDQ     x9, x22, ApiView_sd_ids
    ldr     x10, [x9, #16]
    lsr     x10, x10, #6
    ldr     x11, [sp, #16]
    cmp     x11, x10
    b.hs    9f
    cbz     x11, 2f
    API_LIT api_p_comma
2:  API_LIT api_l_index
    LDQ     x9, x22, ApiView_sd_ids
    ldr     x10, [x9, #8]
    add     x10, x9, x10
    ldr     x11, [sp, #16]
    add     x10, x10, x11, lsl #6
    ldr     x0, [x10, #8]
    bl      lantern_api_qdec
    API_LIT api_l_live
    LDQ     x9, x22, ApiView_live_out
    ldr     x11, [sp, #16]
    ldrb    w0, [x9, x11]
    bl      lantern_api_bool
    API_LIT api_end1
    ldr     x9, [sp, #16]
    add     x9, x9, #1
    str     x9, [sp, #16]
    b       1b
9:  API_LIT api_v_end
    UNFRAME 16
END_FUNCTION lantern_api_liveness_body

/*
 * L1: the body of getSyncCommitteeDuties (beacon-api.md): {"execution_optimistic":…,"data":[{"pubkey":…,
 * "validator_index":…,"validator_sync_committee_indices":[…]},…]} of the ValidatorRef items at
 * ApiView_sd_ids of the view x22, each by its places in the committee at ApiView_sync_out, the
 * pubkeys those of the state at ApiView_val_state. Locals: the item's index, the items written,
 * the validator, the place, its places written.
 */
LOCAL_FUNCTION lantern_api_sync_duties_body
    FRAME 48
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_v_list
    stp     xzr, xzr, [sp, #16]
1:  LDQ     x9, x22, ApiView_sd_ids         /* each item: a validator index the state has */
    ldr     x10, [x9, #16]
    lsr     x10, x10, #6
    ldr     x11, [sp, #16]
    cmp     x11, x10
    b.hs    9f
    add     x12, x11, #1
    str     x12, [sp, #16]
    ldr     x10, [x9, #8]
    add     x10, x9, x10
    add     x10, x10, x11, lsl #6
    ldr     x12, [x10, #8]
    str     x12, [sp, #32]
    ldr     x13, [x22, #ApiView_val_state]
    PART    x9, x10, x13, NODE_STATE_VALIDATORS
    cmp     x12, x10
    b.hs    1b
    stp     xzr, xzr, [sp, #40]             /* its places in the committee */
2:  ldr     x11, [sp, #40]
    cmp     x11, #SYNC_COMMITTEE_SIZE
    b.hs    7f
    add     x12, x11, #1
    str     x12, [sp, #40]
    ldr     x9, [x22, #ApiView_sync_out]
    ldr     x9, [x9, x11, lsl #3]
    ldr     x10, [sp, #32]
    cmp     x9, x10
    b.ne    2b
    ldr     x9, [sp, #48]
    cbnz    x9, 5f
    ldr     x9, [sp, #24]                   /* the first place: the item's head */
    cbz     x9, 3f
    API_LIT api_p_comma
3:  ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    API_LIT api_u_pubkey
    ldr     x13, [x22, #ApiView_val_state]
    PART    x9, x10, x13, NODE_STATE_VALIDATORS
    ldr     x11, [sp, #32]
    add     x0, x9, x11, lsl #7             /* NODE_VALIDATOR_MEM: the pubkey first */
    mov     x1, #48
    bl      lantern_api_qhex
    API_LIT api_u_index
    ldr     x0, [sp, #32]
    bl      lantern_api_qdec
    API_LIT api_sd_indices
    b       6f
5:  API_LIT api_p_comma
6:  ldr     x9, [sp, #48]
    add     x9, x9, #1
    str     x9, [sp, #48]
    ldr     x0, [sp, #40]
    sub     x0, x0, #1
    bl      lantern_api_qdec
    b       2b
7:  ldr     x9, [sp, #48]                   /* places written: the item's end */
    cbz     x9, 1b
    API_LIT api_v_end
    b       1b
9:  API_LIT api_v_end
    UNFRAME 48
END_FUNCTION lantern_api_sync_duties_body
.if NODE_VALIDATOR_MEM != 128
.error "api_sync_duties_body reads a pubkey at index * 128"
.endif

/*
 * L1: the body of getDebugChainHeadsV2 (beacon-api.md): {"data":[{"root":…,"slot":…,"execution_optimistic":…},…]}
 * of the store nodes at ApiView_val_state of the view x22 whose byte at ApiView_heads is 0. Locals: the
 * index, 1 once an item is written, the node.
 */
LOCAL_FUNCTION lantern_api_heads_body
    FRAME 32
    API_LIT api_p_data
    stp     xzr, xzr, [sp, #16]
1:  ldr     x9, [x22, #ApiView_val_state]
    ldr     x10, [x9, #(Store_blocks + 8)]
    ldr     x11, [sp, #16]
    cmp     x11, x10
    b.hs    9f
    ldr     x12, [x22, #ApiView_heads]
    ldrb    w12, [x12, x11]
    cbnz    w12, 8f
    ldr     x12, [sp, #24]
    cbz     x12, 2f
    API_LIT api_p_comma
2:  mov     x12, #1
    str     x12, [sp, #24]
    API_LIT api_ch_root
    ldr     x9, [x22, #ApiView_val_state]
    ldr     x10, [x9, #Store_blocks]
    add     x10, x9, x10
    ldr     x11, [sp, #16]
    mov     x12, #BlockNode__mem
    madd    x0, x11, x12, x10
    str     x0, [sp, #32]
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_q_slot
    ldr     x0, [sp, #32]
    ldr     x0, [x0, #BlockNode_slot]
    bl      lantern_api_qdec
    API_LIT api_ch_optimistic
    ldr     x0, [sp, #32]
    ldr     x0, [x0, #BlockNode_payload_status]
    cmp     x0, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x0, eq
    bl      lantern_api_bool
    API_LIT api_end1
8:  ldr     x11, [sp, #16]
    add     x11, x11, #1
    str     x11, [sp, #16]
    b       1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION lantern_api_heads_body

/*
 * L1: the body of getDebugForkChoice (beacon-api.md): {"justified_checkpoint":…,"finalized_checkpoint":…,
 * "fork_choice_nodes":[…]} of the store at ApiView_val_state of the view x22, each node's weight at
 * ApiView_weights. Locals: the index, the node.
 */
LOCAL_FUNCTION lantern_api_fork_choice_body
    FRAME 16
    API_LIT api_fc_justified
    ldr     x0, [x22, #ApiView_val_state]
    add     x0, x0, #Store_justified_checkpoint
    bl      lantern_api_checkpoint
    API_LIT api_fc_finalized
    ldr     x0, [x22, #ApiView_val_state]
    add     x0, x0, #Store_finalized_checkpoint
    bl      lantern_api_checkpoint
    API_LIT api_fc_nodes
    str     xzr, [sp, #16]
1:  ldr     x9, [x22, #ApiView_val_state]
    ldr     x10, [x9, #(Store_blocks + 8)]
    ldr     x11, [sp, #16]
    cmp     x11, x10
    b.hs    9f
    cbz     x11, 2f
    API_LIT api_p_comma
2:  ldr     x9, [x22, #ApiView_val_state]
    ldr     x10, [x9, #Store_blocks]
    add     x10, x9, x10
    ldr     x11, [sp, #16]
    mov     x12, #BlockNode__mem
    madd    x0, x11, x12, x10
    str     x0, [sp, #24]
    API_LIT api_fc_slot
    ldr     x0, [sp, #24]
    ldr     x0, [x0, #BlockNode_slot]
    bl      lantern_api_qdec
    API_LIT api_fc_block_root
    ldr     x0, [sp, #24]
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_h_parent
    ldr     x0, [sp, #24]
    add     x0, x0, #BlockNode_parent_root
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_fc_justified_epoch
    ldr     x0, [sp, #24]
    ldr     x0, [x0, #BlockNode_justified_checkpoint]   /* its epoch, the Checkpoint's first field */
    bl      lantern_api_qdec
    API_LIT api_fc_finalized_epoch
    ldr     x0, [sp, #24]
    ldr     x0, [x0, #BlockNode_finalized_epoch]
    bl      lantern_api_qdec
    API_LIT api_fc_weight
    LDQ     x9, x22, ApiView_weights
    ldr     x11, [sp, #16]
    ldr     x0, [x9, x11, lsl #3]
    bl      lantern_api_qdec
    API_LIT api_fc_validity
    ldr     x0, [sp, #24]
    ldr     x0, [x0, #BlockNode_payload_status]
    cmp     x0, #PAYLOAD_STATUS_NOT_VALIDATED
    b.eq    3f
    cmp     x0, #PAYLOAD_STATUS_INVALIDATED
    b.eq    4f
    API_LIT api_fc_valid
    b       5f
3:  API_LIT api_fc_optimistic
    b       5f
4:  API_LIT api_fc_invalid
5:  API_LIT api_fc_hash
    ldr     x0, [sp, #24]
    add     x0, x0, #BlockNode_block_hash
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_end1
    ldr     x11, [sp, #16]
    add     x11, x11, #1
    str     x11, [sp, #16]
    b       1b
9:  API_LIT api_v_end
    UNFRAME 16
END_FUNCTION lantern_api_fork_choice_body

/*
 * L1: ,"canonical":…,"header":{"message":{"slot":…,"proposer_index":…,"parent_root":…,"state_root":…,"body_root":…},"signature":…
 * of the slot x0, canonical x2, and at x1 the header's proposer_index, parent_root, state_root,
 * body_root and signature, in that order. Locals: x0, x1, x2.
 */
LOCAL_FUNCTION lantern_api_header_json
    FRAME 32
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    API_LIT api_h_canonical
    ldr     x0, [sp, #32]
    bl      lantern_api_bool
    API_LIT api_h_slot
    ldr     x0, [sp, #16]
    bl      lantern_api_qdec
    API_LIT api_h_proposer
    ldr     x9, [sp, #24]
    ldr     x0, [x9]
    bl      lantern_api_qdec
    API_LIT api_h_parent
    ldr     x0, [sp, #24]
    add     x0, x0, #(ApiView_parent_root - ApiView_proposer_index)
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_h_state
    ldr     x0, [sp, #24]
    add     x0, x0, #(ApiView_state_root - ApiView_proposer_index)
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_h_body
    ldr     x0, [sp, #24]
    add     x0, x0, #(ApiView_body_root - ApiView_proposer_index)
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_h_signature
    ldr     x0, [sp, #24]
    add     x0, x0, #(ApiView_signature - ApiView_proposer_index)
    mov     x1, #96
    bl      lantern_api_qhex
    UNFRAME 32
END_FUNCTION lantern_api_header_json
.if ApiView_parent_root - ApiView_proposer_index != 8 || ApiView_state_root - ApiView_proposer_index != 40 || ApiView_body_root - ApiView_proposer_index != 72 || ApiView_signature - ApiView_proposer_index != 104
.error "api_header_json reads the fields of a SignedBeaconBlockHeader after its slot"
.endif

/*
 * L1: getBlockHeaders' JSON, as lantern_api_stream_json: with x21, the address of an item's header (its
 * slot, then the fields lantern_api_header_json reads), the item {"root":…,"canonical":…,"header":…}, its
 * root at byte 0 of the entry x22's cursor and canonical bit 0 of its member, after , when
 * API_STREAM_ITEMS is set; then API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With x21 = 0:
 * ]}. x0 = 1 when the answer is whole, else 0.
 */
LOCAL_FUNCTION lantern_api_headers_json
    FRAME 0
    cbnz    x21, 1f
    API_LIT api_v_end
    mov     x0, #1
    UNFRAME 0
1:  ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #13, 2f                     /* API_STREAM_ITEMS */
    API_LIT api_p_comma
2:  API_LIT api_ch_root
    add     x0, x22, #NodeApi_cursor
    mov     x1, #32
    bl      lantern_api_qhex
    ldr     x0, [x21]
    add     x1, x21, #8
    ldr     x2, [x22, #NodeApi_member]
    and     x2, x2, #1
    bl      lantern_api_header_json
    API_LIT api_end2
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #(API_STREAM_ITEMS | API_STREAM_ITEM_DONE)
    str     x9, [x23, #(NodeEvent_api + 8)]
    mov     x0, #0
    UNFRAME 0
END_FUNCTION lantern_api_headers_json

/*
 * L0: x0 = the base58btc text of the x1 bytes at x0 (at most 48), written at x2: a 1 for each
 * leading zero byte, then the digits. x3: a work area of 72 bytes. Uses x4, x9-x15.
 */
LOCAL_FUNCTION lantern_api_base58
    UNWIND_END_PROLOGUE
    mov     x9, #0                          /* the leading zero bytes */
1:  cmp     x9, x1
    b.hs    2f
    ldrb    w10, [x0, x9]
    cbnz    w10, 2f
    add     x9, x9, #1
    b       1b
2:  mov     x15, x9
    mov     x11, #0                         /* the digits so far, least significant at x3 + 71 */
    mov     x12, x9
3:  cmp     x12, x1                         /* each byte: digits * 256 + byte */
    b.hs    6f
    ldrb    w13, [x0, x12]
    mov     x14, #0
4:  cmp     x14, x11
    b.hs    5f
    mov     x10, #71
    sub     x10, x10, x14
    ldrb    w9, [x3, x10]
    add     x13, x13, x9, lsl #8
    mov     x9, #58
    udiv    x4, x13, x9
    msub    x9, x4, x9, x13
    strb    w9, [x3, x10]
    mov     x13, x4
    add     x14, x14, #1
    b       4b
5:  cbz     x13, 51f
    mov     x9, #58
    udiv    x4, x13, x9
    msub    x9, x4, x9, x13
    mov     x10, #71
    sub     x10, x10, x11
    strb    w9, [x3, x10]
    add     x11, x11, #1
    mov     x13, x4
    b       5b
51: add     x12, x12, #1
    b       3b
6:  mov     x0, #0                          /* the text: the ones, then the digits */
    ADDRESS x13, api_base58_digits
7:  cbz     x15, 8f
    ldrb    w9, [x13]
    strb    w9, [x2, x0]
    add     x0, x0, #1
    sub     x15, x15, #1
    b       7b
8:  cbz     x11, 9f
    mov     x10, #72
    sub     x10, x10, x11
    ldrb    w9, [x3, x10]
    ldrb    w9, [x13, x9]
    strb    w9, [x2, x0]
    add     x0, x0, #1
    sub     x11, x11, #1
    b       8b
9:  ret
END_FUNCTION lantern_api_base58

/*
 * L1: a peer of getPeers and getPeer (beacon-api.md): {"peer_id":…,"enr":null,"last_seen_p2p_address":…,
 * "state":"connected","direction":…} of the NodePeer x0. Locals: the peer, the text's length, an
 * index, the text (72 bytes), base58's work area (72 bytes).
 */
LOCAL_FUNCTION lantern_api_peer_item
    FRAME 176
    str     x0, [sp, #16]
    add     x0, x0, #NodePeer_id
    ldr     x9, [sp, #16]
    ldr     x1, [x9, #NodePeer_id_len]
    add     x2, sp, #40
    add     x3, sp, #112
    bl      lantern_api_base58
    str     x0, [sp, #24]
    API_LIT api_pe_open
    add     x0, sp, #40
    ldr     x1, [sp, #24]
    bl      lantern_api_put
    API_LIT api_pe_enr
    ldr     x9, [sp, #16]
    ldr     x10, [x9, #NodePeer_address]    /* the family */
    cmp     x10, #6
    b.eq    3f
    /* IPv4: 4 bytes in decimal, . between */
    API_LIT api_pe_ip4
    str     xzr, [sp, #32]
1:  ldr     x9, [sp, #16]
    ldr     x10, [sp, #32]
    add     x9, x9, x10
    ldrb    w0, [x9, #(NodePeer_address + 16)]
    bl      lantern_api_dec
    ldr     x10, [sp, #32]
    add     x10, x10, #1
    str     x10, [sp, #32]
    cmp     x10, #4
    b.hs    5f
    API_LIT api_pe_dot
    b       1b
    /* IPv6: 8 groups of 16 bits, lower case hex with no leading zeros, : between */
3:  API_LIT api_pe_ip6
    str     xzr, [sp, #32]
4:  ldr     x9, [sp, #16]
    ldr     x10, [sp, #32]
    add     x9, x9, x10, lsl #1
    ldrb    w11, [x9, #(NodePeer_address + 16)]
    ldrb    w12, [x9, #(NodePeer_address + 17)]
    orr     x0, x12, x11, lsl #8
    bl      lantern_api_hex16
    ldr     x10, [sp, #32]
    add     x10, x10, #1
    str     x10, [sp, #32]
    cmp     x10, #8
    b.hs    5f
    API_LIT api_pe_colon
    b       4b
5:  ldr     x9, [sp, #16]                   /* the transport and its port */
    ldr     x10, [x9, #NodePeer_transport]
    cmp     x10, #LIBP2P_QUIC
    b.eq    6f
    API_LIT api_pe_tcp
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #(NodePeer_address + 8)]
    bl      lantern_api_dec
    b       7f
6:  API_LIT api_pe_udp
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #(NodePeer_address + 8)]
    bl      lantern_api_dec
    API_LIT api_pe_quic
7:  API_LIT api_pe_p2p
    add     x0, sp, #40
    ldr     x1, [sp, #24]
    bl      lantern_api_put
    API_LIT api_pe_state
    ldr     x9, [sp, #16]
    ldr     x10, [x9, #NodePeer_direction]
    cmp     x10, #LIBP2P_OUTBOUND
    b.eq    8f
    API_LIT api_pe_inbound
    UNFRAME 176
8:  API_LIT api_pe_outbound
    UNFRAME 176
END_FUNCTION lantern_api_peer_item

/* L1: the lower case hex digits of the 16 bits x0, with no leading zeros, join the response. Locals: x0, a shift. */
LOCAL_FUNCTION lantern_api_hex16
    FRAME 16
    str     x0, [sp, #16]
    mov     x9, #12
1:  cbz     x9, 2f                          /* the leading zero digits but the last */
    lsr     x10, x0, x9
    cbnz    x10, 2f
    sub     x9, x9, #4
    b       1b
2:  str     x9, [sp, #24]
3:  ldr     x10, [sp, #16]
    lsr     x10, x10, x9
    and     x10, x10, #15
    ADDRESS x0, api_hex
    add     x0, x0, x10
    mov     x1, #1
    bl      lantern_api_put
    ldr     x9, [sp, #24]
    cbz     x9, 9f
    sub     x9, x9, #4
    str     x9, [sp, #24]
    b       3b
9:  UNFRAME 16
END_FUNCTION lantern_api_hex16

/*
 * L1: getPeers' body (beacon-api.md): {"data":[<peer>,…],"meta":{"count":…}} of the NodePeers of the
 * Node at ApiView_node of the view x22 whose state and direction are in the sets at
 * ApiView_peer_states and ApiView_peer_directions. Locals: the index, the count, the peer.
 */
LOCAL_FUNCTION lantern_api_peers_body
    FRAME 32
    API_LIT api_p_data
    stp     xzr, xzr, [sp, #16]
1:  ldr     x13, [x22, #ApiView_node]
    PART    x10, x11, x13, Node_peers
    ldr     x9, [sp, #16]
    cmp     x9, x11
    b.hs    9f
    mov     x12, #NodePeer__mem
    madd    x0, x9, x12, x10
    add     x9, x9, #1
    str     x9, [sp, #16]
    ldr     x9, [x22, #ApiView_peer_states] /* connected */
    tbz     x9, #API_PEER_CONNECTED, 1b
    ldr     x10, [x0, #NodePeer_direction]
    ldr     x9, [x22, #ApiView_peer_directions]
    lsr     x9, x9, x10
    tbz     x9, #0, 1b
    str     x0, [sp, #32]
    ldr     x9, [sp, #24]
    cbz     x9, 2f
    API_LIT api_p_comma
2:  ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    ldr     x0, [sp, #32]
    bl      lantern_api_peer_item
    b       1b
9:  API_LIT api_pe_meta
    ldr     x0, [sp, #24]
    bl      lantern_api_dec
    API_LIT api_end2
    UNFRAME 32
END_FUNCTION lantern_api_peers_body
.if API_DIRECTION_INBOUND != LIBP2P_INBOUND || API_DIRECTION_OUTBOUND != LIBP2P_OUTBOUND
.error "api_peers_body: the direction bits are the libp2p directions"
.endif

/*
 * L1: (route x0) -> x0: the NodePeer whose peer ID's base58btc text is the route's peer_id, or 0.
 * Locals: the route, the index, the text (72 bytes), base58's work area (72 bytes).
 */
LOCAL_FUNCTION lantern_node_api_find_peer
    FRAME 176
    stp     x0, xzr, [sp, #16]
1:  PART    x10, x11, x19, Node_peers
    ldr     x9, [sp, #24]
    cmp     x9, x11
    b.hs    8f
    mov     x12, #NodePeer__mem
    madd    x13, x9, x12, x10
    add     x9, x9, #1
    str     x9, [sp, #24]
    add     x0, x13, #NodePeer_id
    ldr     x1, [x13, #NodePeer_id_len]
    add     x2, sp, #40
    add     x3, sp, #112
    bl      lantern_api_base58
    ldr     x9, [sp, #16]
    PART    x10, x11, x9, ApiRoute_peer_id
    cmp     x0, x11
    b.ne    1b
    mov     x12, #0
2:  cmp     x12, x11
    b.hs    3f
    add     x13, sp, #40
    ldrb    w14, [x13, x12]
    ldrb    w15, [x10, x12]
    cmp     w14, w15
    b.ne    1b
    add     x12, x12, #1
    b       2b
3:  PART    x10, x11, x19, Node_peers       /* that peer */
    ldr     x9, [sp, #24]
    sub     x9, x9, #1
    mov     x12, #NodePeer__mem
    madd    x0, x9, x12, x10
    UNFRAME 176
8:  mov     x0, #0
    UNFRAME 176
END_FUNCTION lantern_node_api_find_peer

/*
 * L1: the bodies of getStateRandao, getEpochSyncCommittees and getProposerLookahead (beacon-api.md),
 * as lantern_api_body: x22 the view, the local at x0 + 8 the flags. Locals: an index.
 */
LOCAL_FUNCTION lantern_api_state_read_body
    FRAME 16
    str     x0, [sp, #16]
    cmp     x28, #API_OP_GET_PROPOSER_LOOKAHEAD
    b.eq    30f
    /* {"execution_optimistic":…,"finalized":…,"data":{ */
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      lantern_api_bool
    API_LIT api_x_data
    cmp     x28, #API_OP_GET_STATE_RANDAO
    b.ne    10f
    /* "randao":…}} */
    API_LIT api_r_randao
    ADDQ    x0, x22, ApiView_randao
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_end2
    UNFRAME 16
    /* "validators":[…],"validator_aggregates":[[…],…]}} */
10: API_LIT api_s_validators
    str     xzr, [sp, #24]
11: ldr     x9, [sp, #24]
    cmp     x9, #SYNC_COMMITTEE_SIZE
    b.hs    13f
    cbz     x9, 12f
    API_LIT api_p_comma
12: ldr     x9, [sp, #24]
    ldr     x10, [x22, #ApiView_sync_out]
    ldr     x0, [x10, x9, lsl #3]
    bl      lantern_api_qdec
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       11b
13: API_LIT api_s_aggregates
    str     xzr, [sp, #24]
14: ldr     x9, [sp, #24]
    cmp     x9, #SYNC_COMMITTEE_SIZE
    b.hs    18f
    and     x10, x9, #(SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT - 1)
    cbnz    x10, 16f
    cbz     x9, 15f
    API_LIT api_p_rbracket
    API_LIT api_p_comma
15: API_LIT api_p_lbracket
    b       17f
16: API_LIT api_p_comma
17: ldr     x9, [sp, #24]
    ldr     x10, [x22, #ApiView_sync_out]
    ldr     x0, [x10, x9, lsl #3]
    bl      lantern_api_qdec
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       14b
18: API_LIT api_p_rbracket
    API_LIT api_s_end
    UNFRAME 16
30: ldr     x9, [sp, #16]                   /* getProposerLookahead: SSZ, its bytes */
    ldr     x9, [x9, #8]
    tbz     x9, #3, 31f
    ADDQ    x0, x22, ApiView_lookahead
    mov     x1, #(8 * API_LOOKAHEAD_SLOTS)
    bl      lantern_api_put
    UNFRAME 16
    /* {"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[…]} */
31: API_LIT api_j_version
    ldr     x0, [x22, #ApiView_fork]
    bl      lantern_api_fork_name
    API_LIT api_j_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      lantern_api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      lantern_api_bool
    API_LIT api_v_list
    str     xzr, [sp, #24]
32: ldr     x9, [sp, #24]
    cmp     x9, #API_LOOKAHEAD_SLOTS
    b.hs    34f
    cbz     x9, 33f
    API_LIT api_p_comma
33: ADDQ    x10, x22, ApiView_lookahead
    ldr     x9, [sp, #24]
    ldr     x0, [x10, x9, lsl #3]
    bl      lantern_api_qdec
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       32b
34: API_LIT api_v_end
    UNFRAME 16
END_FUNCTION lantern_api_state_read_body
.if SYNC_COMMITTEE_SIZE % SYNC_COMMITTEE_SUBNET_COUNT || (SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT) & (SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT - 1)
.error "api_state_read_body takes a sync subcommittee's size as a power of two"
.endif

/*
 * L1: (view, out, status, body, flags) -> status: the HTTP response of beacon-api.md, Common
 * rules, into the ByteList out, its count set: the status line of status, then its fields, then the
 * body of the kind body (0 none, API_BODY_ERROR, or an API_OP_*) from the ApiView view. flags:
 * API_R_CLOSE, API_R_KEEP, API_R_NO_REASON, and the allow bits from bit 8. x0 = LANTERN_OK, or
 * LANTERN_BUFFER_TOO_SMALL when out has too little room. Locals: L status, L+8 flags, L+16 the
 * body's bytes.
 */
LOCAL_FUNCTION lantern_api_respond
    ENTER 32
    mov     x22, x0
    mov     x23, x1
    stp     x2, x4, [sp, #L]
    mov     x28, x3
    mov     x25, #0                         /* the body's bytes */
    mov     x24, #0
    mov     x27, #0
    cbz     x28, 1f
    add     x0, sp, #L
    bl      lantern_api_body
1:  str     x24, [sp, #(L + 16)]
    mov     x25, #1                         /* the response */
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    /* HTTP/1.1 <code> <reason> CRLF */
    API_LIT api_http
    ldr     x0, [sp, #L]
    bl      lantern_api_dec
    API_LIT api_sp
    ldr     x9, [sp, #(L + 8)]
    tbnz    x9, #2, 2f
    ldr     x0, [sp, #L]
    bl      lantern_api_code
    mov     x1, #8
    bl      lantern_api_code_text
2:  API_LIT api_crlf
    ldr     x9, [sp, #(L + 16)]
    cbz     x9, 3f
    ldr     x9, [sp, #(L + 8)]
    tbnz    x9, #3, 21f                     /* API_R_SSZ */
    API_LIT api_type
    b       22f
21: API_LIT api_octet
22: ldr     x9, [sp, #(L + 8)]              /* API_R_VERSION: Eth-Consensus-Version of the view's fork */
    tbz     x9, #4, 3f
    API_LIT api_version
    ldr     x0, [x22, #ApiView_fork]
    bl      lantern_api_fork_name
    API_LIT api_crlf
3:  API_LIT api_length
    ldr     x0, [sp, #(L + 16)]
    bl      lantern_api_dec
    API_LIT api_crlf
    ldr     x9, [sp, #L]
    cmp     x9, #405
    b.ne    5f
    /* Allow: GET, POST or GET, POST */
    API_LIT api_allow
    ldr     x9, [sp, #(L + 8)]
    tbz     x9, #8, 4f
    API_LIT api_get
    ldr     x9, [sp, #(L + 8)]
    tbz     x9, #9, 41f
    API_LIT api_comma
4:  ldr     x9, [sp, #(L + 8)]
    tbz     x9, #9, 41f
    API_LIT api_post
41: API_LIT api_crlf
5:  ldr     x9, [sp, #(L + 8)]
    tbz     x9, #0, 6f
    API_LIT api_close
    b       7f
6:  tbz     x9, #1, 7f
    API_LIT api_keep
7:  API_LIT api_crlf
    cbz     x28, 8f
    add     x0, sp, #L
    bl      lantern_api_body
8:  cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_api_respond

/*
 * L1: the values of the ApiView x0 that the node, x19, and the store, x20, give (beacon-api.md,
 * Common rules); the header and the checkpoints zero. Locals: L the view.
 */
LOCAL_FUNCTION lantern_node_api_view
    FRAME 16
    str     x0, [sp, #16]
    MOVQ    x1, ApiView__size
    bl      lantern_zero
    ldr     x0, [sp, #16]
    ldr     x9, [x20, #Store_genesis_time_ms]
    mov     x10, #1000
    udiv    x9, x9, x10
    str     x9, [x0, #ApiView_genesis_time]
    add     x0, x0, #ApiView_genesis_validators_root
    add     x1, x19, #Node_genesis_validators_root
    mov     x2, #32
    bl      lantern_copy
    ldr     x0, [sp, #16]
    LDQ     x9, x19, Node_config + CONFIG_GENESIS_FORK_VERSION
    str     x9, [x0, #ApiView_genesis_fork_version]
    add     x9, x19, #Node_config
    STQ     x9, x0, ApiView_config
    add     x0, x19, #Node_head_root        /* the head */
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    1f
    ldr     x0, [sp, #16]
    ldr     x9, [x1, #NodeBlock_slot]
    str     x9, [x0, #ApiView_head_slot]
    ldr     x9, [x1, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x0, #ApiView_is_optimistic]
    add     x0, x0, #ApiView_head_root
    bl      lantern_copy_root
1:  mov     x0, x20                         /* the clock, sync, peers, MetaData */
    bl      lantern_node_store_slot
    ldr     x9, [sp, #16]
    str     x0, [x9, #ApiView_current_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    ldr     x9, [sp, #16]
    str     x0, [x9, #ApiView_fork]
    ldr     x10, [x19, #Node_flags]
    ubfx    x11, x10, #3, #1                /* NODE_FLAG_SYNCING */
    str     x11, [x9, #ApiView_is_syncing]
    ubfx    x11, x10, #9, #1                /* NODE_FLAG_EL_OFFLINE */
    str     x11, [x9, #ApiView_el_offline]
    ldr     x10, [x19, #(Node_peers + 8)]
    str     x10, [x9, #ApiView_peers]
    ldr     x10, [x19, #Node_metadata_seq]
    str     x10, [x9, #ApiView_seq_number]
    ldr     x10, [x19, #Node_attnets]
    str     x10, [x9, #ApiView_attnets]
    LDQ     x10, x19, Node_custody_count    /* the custody group count */
    str     x10, [x9, #ApiView_custody_group_count]
    add     x0, x9, #ApiView_peer_id        /* the identity's texts */
    ADDQ    x1, x19, Node_api_identity
    mov     x2, #API_IDENTITY_SIZE
    bl      lantern_copy
    ldr     x0, [sp, #16]
    bl      lantern_api_view_finalized
    UNFRAME 16
END_FUNCTION lantern_node_api_view

/* L0: ApiView_head_finalized of the view x0: 1 when its head_root is the root of the store x20's finalized checkpoint. Uses x9-x16. */
LOCAL_FUNCTION lantern_api_view_finalized
    UNWIND_END_PROLOGUE
    add     x9, x0, #ApiView_head_root
    add     x10, x20, #(Store_finalized_checkpoint + 8)
    mov     x13, #0
    ldp     x11, x12, [x9]
    ldp     x14, x15, [x10]
    cmp     x11, x14
    ccmp    x12, x15, #0, eq
    b.ne    1f
    ldp     x11, x12, [x9, #16]
    ldp     x14, x15, [x10, #16]
    cmp     x11, x14
    ccmp    x12, x15, #0, eq
    cset    x13, eq
1:  STQ     x13, x0, ApiView_head_finalized
    ret
END_FUNCTION lantern_api_view_finalized

/* L0: the 32 bytes at x1 to x0. Uses x16, x17. */
LOCAL_FUNCTION lantern_copy_root
    UNWIND_END_PROLOGUE
    COPY32  x0, x1
    ret
END_FUNCTION lantern_copy_root

/*
 * L1: one NODE_ACT_API_SEND of the connection x0, with last 1, at the end of the actions x24: the
 * response of lantern_api_respond with the view x1, the status x2, the body x3 and the flags x4; when it
 * does not fit, the error 500. With API_R_CLOSE, then a NODE_ACT_API_CLOSE. Locals: L the
 * connection, L+8 the flags, L+16 the action.
 */
LOCAL_FUNCTION lantern_node_api_send
    FRAME 48
    stp     x0, x4, [sp, #16]
    ldp     x9, x10, [x24, #8]              /* the action, and the room after it */
    add     x11, x24, x9
    add     x11, x11, x10
    str     x11, [sp, #32]
    ldr     x12, [x24]
    sub     x12, x12, x9
    sub     x12, x12, x10
    sub     x12, x12, #32
    and     x12, x12, #~7
    str     x12, [x11, #32]                 /* its ByteList at 32 */
    mov     x0, x1
    add     x1, x11, #32
    bl      lantern_api_respond
    cbz     x0, 1f
    mov     x0, #0                          /* no room: the error 500 */
    ldr     x1, [sp, #32]
    add     x1, x1, #32
    mov     x2, #500
    mov     x3, #API_BODY_ERROR
    ldr     x4, [sp, #24]
    and     x4, x4, #(API_R_CLOSE | API_R_KEEP)
    bl      lantern_api_respond
1:  ldr     x11, [sp, #32]
    ldr     x9, [x11, #48]                  /* the count; the size to a multiple of 8, zero bytes after */
    add     x0, x11, #56
    add     x0, x0, x9
    add     x10, x9, #(56 + 7)
    and     x10, x10, #~7
    sub     x1, x10, #56
    sub     x1, x1, x9
    str     x10, [sp, #40]
    bl      lantern_zero
    ldr     x11, [sp, #32]
    ldr     x10, [sp, #40]
    mov     x9, #NODE_ACT_API_SEND
    stp     x10, x9, [x11]
    ldr     x9, [sp, #16]
    mov     x12, #1
    stp     x9, x12, [x11, #16]
    sub     x9, x10, #32
    str     x9, [x11, #32]
    ldr     x9, [x24, #16]
    add     x9, x9, x10
    str     x9, [x24, #16]
    ldr     x9, [sp, #24]
    tbz     x9, #0, 9f
    mov     x0, #NODE_ACT_API_CLOSE
    mov     x1, #NODE_ACT_API_CLOSE_SIZE
    bl      lantern_node_act
    ldr     x9, [sp, #16]
    str     x9, [x0, #16]
9:  UNFRAME 48
END_FUNCTION lantern_node_api_send

/*
 * L0: the NODE_EV_API or NODE_EV_API_IDENTITY x0 of size x1, whose ByteList at 24 is inside it
 * (node.md, NodeEvent): x0 = 0 when it keeps its rules, else 1; x1 = the scratch it needs. Uses
 * x9-x15.
 */
LOCAL_FUNCTION lantern_node_api_check
    UNWIND_END_PROLOGUE
    ldr     x9, [x0, #8]
    ldr     x10, [x0, #(NodeEvent_bytes + 16)]  /* the count */
    add     x11, x0, #(NodeEvent_bytes + 24)    /* the bytes */
    cmp     x9, #NODE_EV_API_IDENTITY
    b.ne    5f
    cmp     x10, #API_IDENTITY_SIZE         /* IDENTITY: each text in its room, its bytes 0x21 to 0x7e but " and \ */
    b.ne    8f
    ADDRESS x12, node_api_rooms
1:  ldr     x13, [x12], #8
    cbz     x13, 4f
    ldr     x14, [x11], #8
    cmp     x14, x13
    b.hi    8f
    mov     x15, #0
2:  cmp     x15, x14
    b.hs    3f
    ldrb    w9, [x11, x15]
    sub     w10, w9, #0x21
    cmp     w10, #(0x7e - 0x21)
    b.hi    8f
    cmp     w9, #0x22
    b.eq    8f
    cmp     w9, #0x5c
    b.eq    8f
    add     x15, x15, #1
    b       2b
3:  add     x11, x11, x13
    b       1b
4:  mov     x0, #0
    mov     x1, #0
    ret
5:  ldr     x12, [x0, #16]                  /* API: a connection, not 0 */
    cbz     x12, 8f
    cmp     x10, #HTTP_REQUEST_FIXED        /* an HttpRequest of the count's size */
    b.lo    8f
    tst     x10, #7
    b.ne    8f
    ldr     x12, [x11, #HttpRequest_size]
    cmp     x12, x10
    b.ne    8f
    ldr     x12, [x11, #HttpRequest_status]
    cbnz    x12, 7f
    mov     x13, #HttpRequest_path          /* with status 0, each part inside */
6:  cmp     x13, #HTTP_REQUEST_FIXED
    b.hs    7f
    add     x14, x11, x13
    ldp     x14, x15, [x14]
    cmp     x14, x10
    b.hi    8f
    sub     x14, x10, x14
    cmp     x15, x14
    b.hi    8f
    add     x13, x13, #16
    b       6b
7:  MOVQ    x1, NODE_API_SCRATCH
    ldr     x12, [x11, #HttpRequest_status]
    cbnz    x12, 71f
    ldr     x12, [x11, #(HttpRequest_query + 8)]
    add     x1, x1, x12, lsl #2
    ldr     x12, [x11, #(HttpRequest_body + 8)]   /* 16 bytes per byte of the body: its ids */
    add     x1, x1, x12, lsl #4
71: mov     x0, #0
    ret
8:  mov     x0, #1
    mov     x1, #0
    ret
END_FUNCTION lantern_node_api_check

/* L0: x0 = the NODE_DB_REF of the Db's record of the block at x0, or 0. Uses x9-x13, and the stack. */
LOCAL_FUNCTION lantern_node_api_db_ref
    FRAME 16
    ldr     x9, [x19, #Node_flags]
    tst     x9, #NODE_FLAG_DB
    b.eq    9f
    mov     x1, x0
    ldr     x0, [x19, #Node_db]
    add     x0, x19, x0
    add     x2, sp, #16
    bl      lantern_db_find_root
    ldr     x0, [sp, #16]
    cmn     x0, #1
    b.eq    9f
    bl      lantern_node_db_block
    UNFRAME 16
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION lantern_node_api_db_ref

/*
 * L2: the answer to the NODE_EV_API x0 (node.md, lantern_node_step): x19 the node, x20 the store,
 * x23 the scratch, x24 the actions. x21 the event, x22 its HttpRequest, x25 the ApiRoute, x26 the
 * ApiView, x27 the connection, x28 the flags of lantern_api_respond. Locals: L the scratch's size.
 */
LOCAL_FUNCTION lantern_node_api_event
    ENTER 16
    mov     x21, x0
    ldr     x27, [x21, #16]
    ldr     x9, [x21, #(NodeEvent_bytes + 8)]
    add     x22, x21, #NodeEvent_bytes
    add     x22, x22, x9
    mov     x28, #0                         /* close after a fault or with close; HTTP/1.0 kept open says so */
    ldr     x9, [x22, #HttpRequest_status]
    ldr     x10, [x22, #HttpRequest_close]
    orr     x9, x9, x10
    cbz     x9, 1f
    mov     x28, #API_R_CLOSE
    b       2f
1:  ldr     x9, [x22, #HttpRequest_version]
    cmp     x9, #10
    b.ne    2f
    mov     x28, #API_R_KEEP
2:  ldr     x9, [x23]                       /* the ApiView, then the ApiRoute, at the end of scratch */
    str     x9, [sp, #L]
    mov     x0, x21
    bl      lantern_node_api_check
    ldr     x9, [sp, #L]
    sub     x9, x9, x1
    str     x9, [x23]
    add     x26, x23, x9
    add     x25, x26, #ApiView__size
    MOVQ    x9, ApiView__size
    sub     x9, x1, x9
    str     x9, [x25]
    mov     x0, x26
    bl      lantern_node_api_view
    ldr     x2, [x22, #HttpRequest_status]  /* a fault of the request: its status */
    cbnz    x2, 80f
    mov     x0, x22
    mov     x1, x25
    bl      lantern_api_route
    cmp     x0, #LANTERN_INVALID_ROUTE
    b.ne    3f
    ldr     x2, [x25, #ApiRoute_status]
    ldr     x9, [x25, #ApiRoute_allow]
    orr     x28, x28, x9, lsl #8
    b       80f
3:  mov     x2, #500
    cbnz    x0, 80f
    ldr     x3, [x25, #ApiRoute_op]
    mov     x2, #200
    cmp     x3, #API_OP_GET_HEALTH
    b.ne    4f
    ldr     x9, [x26, #ApiView_is_syncing]  /* health: 200, else 206 or syncing_status */
    ldr     x10, [x26, #ApiView_is_optimistic]
    orr     x9, x9, x10
    ldr     x10, [x26, #ApiView_el_offline]
    orr     x9, x9, x10
    mov     x3, #0
    cbz     x9, 81f
    mov     x2, #206
    ldr     x9, [x25, #ApiRoute_present]
    tbz     x9, #API_PARAM_SYNCING_STATUS, 81f
    ldr     x2, [x25, #ApiRoute_syncing_status]
    orr     x28, x28, #API_R_NO_REASON
    b       81f
4:  cmp     x3, #API_OP_GET_NETWORK_IDENTITY
    b.eq    81f
    cmp     x3, #API_OP_GET_NODE_VERSION
    b.eq    81f
    cmp     x3, #API_OP_GET_SYNCING_STATUS
    b.eq    81f
    cmp     x3, #API_OP_GET_PEER_COUNT
    b.eq    81f
    cmp     x3, #API_OP_GET_PEERS
    b.eq    56f
    cmp     x3, #API_OP_GET_PEER
    b.eq    55f
    cmp     x3, #API_OP_GET_GENESIS
    b.eq    81f
    cmp     x3, #API_OP_GET_FORK_SCHEDULE
    b.eq    81f
    cmp     x3, #API_OP_GET_DEPOSIT_CONTRACT
    b.eq    81f
    mov     x2, #404
    ldr     x9, [x22, #HttpRequest_version] /* x21: the answer flags of a work or a stream */
    cmp     x9, #10
    cset    x9, eq
    tst     x28, #API_R_CLOSE
    cset    x21, ne
    orr     x21, x21, x9, lsl #1
    sub     x9, x3, #API_OP_GET_LIGHT_CLIENT_BOOTSTRAP  /* the light client reads: of the light client store */
    cmp     x9, #(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP)
    b.ls    549f
    cmp     x3, #API_OP_GET_BLOCK_ROOT
    b.eq    65f
    cmp     x3, #API_OP_GET_BLOCK_HEADER
    b.eq    65f
    cmp     x3, #API_OP_GET_BLOCK_V2
    b.eq    65f
    cmp     x3, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    b.eq    65f
    cmp     x3, #API_OP_GET_BLINDED_BLOCK
    b.eq    65f
    cmp     x3, #API_OP_GET_BLOB_SIDECARS
    b.eq    65f
    cmp     x3, #API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    b.eq    65f
    cmp     x3, #API_OP_GET_BLOBS
    b.eq    65f
    cmp     x3, #API_OP_GET_BLOCK_REWARDS
    b.eq    547f
    cmp     x3, #API_OP_GET_SYNC_COMMITTEE_REWARDS
    b.eq    547f
    cmp     x3, #API_OP_GET_ATTESTATIONS_REWARDS
    b.eq    548f
    cmp     x3, #API_OP_GET_STATE_ROOT
    b.eq    66f
    cmp     x3, #API_OP_GET_STATE_FORK
    b.eq    66f
    cmp     x3, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.eq    66f
    cmp     x3, #API_OP_GET_STATE_RANDAO
    b.eq    66f
    cmp     x3, #API_OP_GET_EPOCH_SYNC_COMMITTEES
    b.eq    66f
    cmp     x3, #API_OP_GET_PROPOSER_LOOKAHEAD
    b.eq    66f
    sub     x9, x3, #API_OP_GET_PENDING_CONSOLIDATIONS
    cmp     x9, #2
    b.ls    66f
    cmp     x3, #API_OP_GET_SPEC
    b.eq    67f
    cmp     x3, #API_OP_GET_DEBUG_CHAIN_HEADS_V2
    b.eq    67f
    cmp     x3, #API_OP_GET_DEBUG_FORK_CHOICE
    b.eq    67f
    cmp     x3, #API_OP_GET_BLOCK_HEADERS
    b.eq    57f
    cmp     x3, #API_OP_GET_PROPOSER_DUTIES
    b.eq    63f
    cmp     x3, #API_OP_GET_PROPOSER_DUTIES_V2
    b.eq    63f
    cmp     x3, #API_OP_PRODUCE_ATTESTATION_DATA
    b.eq    59f
    cmp     x3, #API_OP_PRODUCE_BLOCK_V3
    b.eq    540f
    cmp     x3, #API_OP_GET_ATTESTER_DUTIES
    b.eq    58f
    cmp     x3, #API_OP_GET_SYNC_COMMITTEE_DUTIES
    b.eq    53f
    cmp     x3, #API_OP_GET_LIVENESS
    b.eq    52f
    cmp     x3, #API_OP_EVENTSTREAM
    b.eq    61f
    cmp     x3, #API_OP_GET_POOL_VOLUNTARY_EXITS
    b.eq    68f
    cmp     x3, #API_OP_GET_POOL_PROPOSER_SLASHINGS
    b.eq    68f
    cmp     x3, #API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    b.eq    68f
    cmp     x3, #API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES
    b.eq    68f
    cmp     x3, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.eq    68f
    cmp     x3, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.eq    68f
    cmp     x3, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    b.eq    68f
    cmp     x3, #API_OP_PREPARE_BEACON_COMMITTEE_SUBNET    /* the subscriptions: as a pool POST */
    b.eq    60f
    cmp     x3, #API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS
    b.eq    60f
    cmp     x3, #API_OP_PREPARE_BEACON_PROPOSER
    b.eq    60f
    cmp     x3, #API_OP_REGISTER_VALIDATOR
    b.eq    60f
    cmp     x3, #API_OP_PUBLISH_BLOCK_V2
    b.eq    545f
    cmp     x3, #API_OP_PUBLISH_BLINDED_BLOCK_V2
    b.eq    545f
    mov     x0, x3
    bl      lantern_node_submit_topic
    cbnz    x0, 60f
    ldr     x3, [x25, #ApiRoute_op]
    sub     x9, x3, #API_OP_GET_STATE_VALIDATORS   /* the six validator operations and getEpochCommittees: a state */
    cmp     x9, #(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS)
    b.ls    66f
    cmp     x3, #API_OP_GET_STATE_V2
    b.ne    7f
66: ldr     x9, [x25, #ApiRoute_id_kind]    /* a state root: a work finds its slot first */
    cmp     x9, #API_ID_ROOT
    b.ne    69f
    mov     x0, x27
    mov     x1, x25
    mov     x2, x21
    mov     x3, #0
    bl      lantern_node_api_lookup
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
69: mov     x9, #1                          /* a state: its lookup, then the state at its slot; the replay may come */
    STQ     x9, x26, ApiView_look_replay
    mov     x0, x25
    mov     x1, x26
    bl      lantern_node_api_state
    mov     x2, x0
    cmp     x0, #1
    b.eq    698f
    cbnz    x0, 80f
    str     xzr, [x26, #ApiView_look_data]
    mov     x0, x27
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_state_answer
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
698: mov    x0, x27                         /* the replay: the request waits in a lookup entry */
    mov     x1, x25
    mov     x2, x21
    mov     x3, #1
    bl      lantern_node_api_lookup
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
53: mov     x2, #503                        /* getSyncCommitteeDuties: 503 while syncing; 400 past the next period, with no index or a key */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x2, #400
    ldp     x10, x11, [x25, #ApiRoute_list]
    cbz     x11, 80f
    add     x10, x25, x10
531: ldr    x12, [x10], #64
    cmp     x12, #API_VALIDATOR_INDEX
    b.ne    80f
    subs    x11, x11, #1
    b.ne    531b
    mov     x0, x20
    bl      lantern_node_store_slot
    MOVQ    x11, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    udiv    x9, x0, x11
    add     x9, x9, #1
    ldr     x10, [x25, #ApiRoute_epoch]
    mov     x12, #EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    udiv    x12, x10, x12
    mov     x2, #400
    cmp     x12, x9
    b.hi    80f
    add     x0, x19, #Node_head_root        /* the head's post-state, of altair on, at the epoch's period or the one before */
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    532f
    ldr     x0, [x1, #NodeBlock_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    cmp     x0, #FORK_ALTAIR
    b.lo    532f
    add     x0, x19, #Node_head_root
    bl      lantern_node_find_block
    ldr     x9, [x1, #NodeBlock_slot]
    MOVQ    x11, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    udiv    x9, x9, x11                     /* the head's period */
    ldr     x10, [x25, #ApiRoute_epoch]
    mov     x12, #EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    udiv    x12, x10, x12
    subs    x12, x12, x9
    b.lo    532f
    cmp     x12, #1
    b.hi    532f
    str     x12, [sp, #(L + 8)]             /* 1: the next period */
    mov     x9, #API_ID_HEAD
    str     x9, [x25, #ApiRoute_id_kind]
    mov     x0, x25
    mov     x1, x26
    bl      lantern_node_api_state
    mov     x2, #400
    cbnz    x0, 80f
    ldr     x9, [sp, #(L + 8)]
    STQ     x9, x26, ApiView_next_period
    mov     x0, x25                         /* its ids in the work's data */
    bl      lantern_node_api_ids
    str     x0, [x26, #ApiView_look_data]
    b       67f
532: mov    x0, x20                         /* else the state of the epoch's first slot, as getAttesterDuties */
    bl      lantern_node_store_slot
    ldr     x10, [x25, #ApiRoute_epoch]
    mov     x11, #SLOTS_PER_EPOCH
    b       583f
52: mov     x2, #503                        /* getLiveness: 503 while syncing; 400 outside the previous to the next epoch, with no index or a key */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x2, #400
    ldp     x10, x11, [x25, #ApiRoute_list]
    cbz     x11, 80f
    add     x10, x25, x10
521: ldr    x12, [x10], #64
    cmp     x12, #API_VALIDATOR_INDEX
    b.ne    80f
    subs    x11, x11, #1
    b.ne    521b
    mov     x0, x20
    bl      lantern_node_store_slot
    mov     x11, #SLOTS_PER_EPOCH
    udiv    x9, x0, x11                     /* the store's epoch */
    ldr     x10, [x25, #ApiRoute_epoch]
    mov     x2, #400
    add     x11, x9, #1
    cmp     x10, x11
    b.hi    80f
    cbz     x9, 522f
    sub     x9, x9, #1
    cmp     x10, x9
    b.lo    80f
522: mov    x9, #API_ID_HEAD                /* the head's post-state at its slot; none: 500 */
    str     x9, [x25, #ApiRoute_id_kind]
    mov     x0, x25
    mov     x1, x26
    bl      lantern_node_api_state
    mov     x2, #500
    cbnz    x0, 80f
    ldr     x9, [x25, #ApiRoute_epoch]      /* the epoch in the work's arg, in place of the slot */
    str     x9, [x26, #ApiView_head_slot]
    mov     x0, x25                         /* its ids in the work's data */
    bl      lantern_node_api_ids
    str     x0, [x26, #ApiView_look_data]
    b       67f
58: mov     x2, #503                        /* getAttesterDuties: 503 while syncing; 400 past the next epoch, with no index or a key */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x2, #400
    ldp     x10, x11, [x25, #ApiRoute_list]
    cbz     x11, 80f
    add     x10, x25, x10
581: ldr    x12, [x10], #64
    cmp     x12, #API_VALIDATOR_INDEX
    b.ne    80f
    subs    x11, x11, #1
    b.ne    581b
    mov     x0, x20
    bl      lantern_node_store_slot
    mov     x11, #SLOTS_PER_EPOCH
    udiv    x9, x0, x11
    add     x9, x9, #1
    ldr     x10, [x25, #ApiRoute_epoch]
    mov     x2, #400
    cmp     x10, x9
    b.hi    80f
583: mul    x10, x10, x11                   /* the state of the first slot, as getProposerDuties; none: 400 */
    mov     x9, #API_ID_SLOT
    cmp     x10, x0
    b.ls    582f
    mov     x9, #API_ID_HEAD
582: stp    x9, x10, [x25, #ApiRoute_id_kind]
    ldr     x12, [x25, #ApiRoute_op]        /* getAttesterDuties of a slot: the replay may come */
    cmp     x12, #API_OP_GET_ATTESTER_DUTIES
    ccmp    x9, #API_ID_SLOT, #0, eq
    b.ne    584f
    mov     x12, #1
    STQ     x12, x26, ApiView_look_replay
584: mov    x0, x25
    mov     x1, x26
    bl      lantern_node_api_state
    cmp     x0, #1
    b.eq    698b
    mov     x2, #400
    cbnz    x0, 80f
    ldr     x9, [x25, #ApiRoute_id_slot]
    str     x9, [x26, #ApiView_head_slot]
    mov     x0, x26
    bl      lantern_node_api_advance
    mov     x0, x25                         /* its ids in the work's data */
    bl      lantern_node_api_ids
    str     x0, [x26, #ApiView_look_data]
    b       67f
540: mov    x2, #503                        /* produceBlockV3: 503 while syncing; 400 at or below the head's slot, or past the store's slot + 1 */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x0, x20
    bl      lantern_node_store_slot
    ldr     x10, [x25, #ApiRoute_slot]
    mov     x2, #400
    add     x0, x0, #1
    cmp     x10, x0
    b.hi    80f
    ldr     x9, [x26, #ApiView_head_slot]
    cmp     x10, x9
    b.ls    80f
    mov     x9, #API_ID_HEAD                /* the head's post-state brought to the slot, which may be past the store's */
    str     x9, [x25, #ApiRoute_id_kind]
    mov     x0, x25
    mov     x1, x26
    bl      lantern_node_api_state
    mov     x2, #500
    cbnz    x0, 80f
    ldr     x9, [x25, #ApiRoute_slot]
    str     x9, [x26, #ApiView_head_slot]
    mov     x0, x26
    bl      lantern_node_api_advance
    mov     x0, x27
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_produce
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
59: mov     x2, #503                        /* produceAttestationData: 503 while syncing; 400 past the store's slot */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x0, x20
    bl      lantern_node_store_slot
    ldr     x10, [x25, #ApiRoute_slot]
    mov     x2, #400
    cmp     x10, x0
    b.hi    80f
    mov     x9, #API_ID_SLOT                /* the state of the slot, as a state_id of it; none: 400 */
    stp     x9, x10, [x25, #ApiRoute_id_kind]
    mov     x0, x25
    mov     x1, x26
    bl      lantern_node_api_state
    mov     x2, #400
    cbnz    x0, 80f
    mov     x2, #503                        /* an optimistic block: 503 */
    ldr     x9, [x26, #ApiView_is_optimistic]
    cbnz    x9, 80f
    mov     x0, x26
    bl      lantern_node_api_advance
    add     x0, x25, #ApiRoute_committee_index  /* its committee index in the work's data */
    bl      lantern_node_api_put8
    str     x0, [x26, #ApiView_look_data]
    ldr     x9, [x25, #ApiRoute_response]   /* SSZ: an answer flag */
    cmp     x9, #API_TYPE_SSZ
    b.ne    67f
    orr     x21, x21, #API_ANSWER_SSZ
    b       67f
56: ldr     x9, [x25, #ApiRoute_present]    /* getPeers: its state and direction sets, all bits with none */
    mov     x10, #-1
    ldr     x11, [x25, #ApiRoute_peer_states]
    tst     x9, #(1 << API_PARAM_STATE)
    csel    x10, x11, x10, ne
    str     x10, [x26, #ApiView_peer_states]
    mov     x10, #-1
    ldr     x11, [x25, #ApiRoute_peer_directions]
    tst     x9, #(1 << API_PARAM_DIRECTION)
    csel    x10, x11, x10, ne
    str     x10, [x26, #ApiView_peer_directions]
    str     x19, [x26, #ApiView_node]
    mov     x2, #200
    mov     x3, #API_OP_GET_PEERS
    b       81f
55: mov     x0, x25                         /* getPeer: the peer of its peer_id, else 404 */
    bl      lantern_node_api_find_peer
    mov     x2, #404
    cbz     x0, 80f
    str     x0, [x26, #ApiView_peer]
    mov     x2, #200
    mov     x3, #API_OP_GET_PEER
    b       81f
57: mov     x0, x27                         /* getBlockHeaders: a stream of the blocks of its query */
    mov     x1, x25
    mov     x2, x21
    bl      lantern_node_api_headers_stream
    b       90f
68: mov     x0, x27                         /* a pool GET: a stream of the pool; getAggregatedAttestationV2 with none 404 */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_pool_stream
    cbz     x0, 90f
    mov     x2, x0
    b       80f
548: ldr    x10, [x25, #ApiRoute_epoch]     /* getAttestationsRewards: the state of the last slot of epoch + 1, a stream of it */
    mov     x2, #404
    adds    x10, x10, #2
    b.cs    80f
    mov     x0, x20
    bl      lantern_node_store_slot
    add     x11, x0, #1
    mov     x12, #SLOTS_PER_EPOCH
    udiv    x11, x11, x12
    ldr     x10, [x25, #ApiRoute_epoch]
    add     x10, x10, #2
    mov     x2, #404
    cmp     x10, x11
    b.hi    80f
    mul     x10, x10, x12
    sub     x10, x10, #1
    mov     x9, #API_ID_SLOT
    stp     x9, x10, [x25, #ApiRoute_id_kind]
    mov     x0, x25
    mov     x1, x26
    bl      lantern_node_api_state
    mov     x2, x0
    cbnz    x0, 80f
    mov     x0, x26
    bl      lantern_node_api_advance
    mov     x0, x25                         /* its ids, as a validator stream's */
    bl      lantern_node_api_ids
    str     x0, [x26, #ApiView_look_data]
    b       64f
547: mov    x0, x27                         /* getBlockRewards, getSyncCommitteeRewards: a work of the block on its pre-state */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_rewards
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
545: mov    x2, #503                        /* publishBlockV2 and publishBlindedBlockV2: 503 while syncing; a work decodes its body */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x0, x27
    mov     x1, x25
    mov     x2, x21
    mov     x3, x22
    bl      lantern_node_api_publish
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
60: mov     x0, x27                         /* a pool POST: a work checks its operations */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x22
    mov     x4, x26
    bl      lantern_node_api_submit
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
61: mov     x0, x27                         /* eventstream: an entry, and the head */
    mov     x1, x25
    mov     x2, x21
    bl      lantern_node_api_subscribe
    b       90f
63: mov     x2, #503                        /* getProposerDuties: 503 while syncing; 400 past the next epoch */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x0, x20
    bl      lantern_node_store_slot
    mov     x11, #SLOTS_PER_EPOCH
    udiv    x9, x0, x11
    add     x9, x9, #1
    ldr     x10, [x25, #ApiRoute_epoch]
    mov     x2, #400
    cmp     x10, x9
    b.hi    80f
    mul     x10, x10, x11                   /* the first slot: as a state_id of it; past the store's slot, the head's post-state */
    mov     x9, #API_ID_SLOT
    cmp     x10, x0
    b.ls    62f
    mov     x9, #API_ID_HEAD
62: stp     x9, x10, [x25, #ApiRoute_id_kind]
    cmp     x9, #API_ID_SLOT                /* a slot: the replay may come */
    b.ne    621f
    mov     x9, #1
    STQ     x9, x26, ApiView_look_replay
621: mov    x0, x25
    mov     x1, x26
    bl      lantern_node_api_state
    mov     x2, x0
    cmp     x0, #1
    b.eq    698b
    cbnz    x0, 80f
    ldr     x9, [x25, #ApiRoute_id_slot]    /* brought to the first slot */
    str     x9, [x26, #ApiView_head_slot]
    mov     x0, x26
    bl      lantern_node_api_advance
    b       67f
65: mov     x0, x25                         /* a block: its lookup */
    mov     x1, x26
    bl      lantern_node_api_block
    mov     x2, x0
    cbnz    x0, 80f
    ldr     x3, [x25, #ApiRoute_op]
    mov     x2, #200
    cmp     x3, #API_OP_GET_BLOCK_ROOT      /* getBlockRoot: the answer at once */
    b.eq    81f
    cmp     x3, #API_OP_GET_BLOCK_V2
    b.eq    64f
    cmp     x3, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    b.eq    64f
    cmp     x3, #API_OP_GET_BLINDED_BLOCK
    b.eq    64f
    cmp     x3, #API_OP_GET_BLOB_SIDECARS
    b.eq    54f
    cmp     x3, #API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    b.eq    54f
    cmp     x3, #API_OP_GET_BLOBS
    b.eq    55f
67: ldr     x0, [x25, #ApiRoute_op]         /* a work */
    mov     x1, x27
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_encode
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
549: mov    x0, x25                         /* the light client reads: a work */
    mov     x1, x27
    mov     x2, x21
    bl      lantern_node_api_lc
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
54: mov     x0, x27                         /* a sidecar stream of the block */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_sidecar_stream
    cbz     x0, 90f
    mov     x2, x0
    b       80f
55: mov     x0, x27                         /* getBlobs: the blob stream of the block */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_blob_stream
    cbz     x0, 90f
    mov     x2, x0
    b       80f
64: mov     x0, x27                         /* a stream of the answer */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_stream
    cbz     x0, 90f
    mov     x2, x0
    b       80f
7:  mov     x2, #501                        /* another operation */
80: mov     x3, #API_BODY_ERROR
81: mov     x0, x27
    mov     x1, x26
    mov     x4, x28
    bl      lantern_node_api_send
90: ldr     x9, [sp, #L]
    str     x9, [x23]
    LEAVE 16
END_FUNCTION lantern_node_api_event

/*
 * L2: the answer of a state operation (beacon-api.md) for the connection x0, the route x1, the
 * answer flags x2 and the view x3 whose state lantern_node_api_state found: the state at head_slot, then a
 * stream or a work. A validator operation's ids: look_data when it is not 0, else the route's.
 * x0 = 0, or the status of an error. x21 the flags, x25 the route, x26 the view, x27 the connection.
 */
LOCAL_FUNCTION lantern_node_api_state_answer
    ENTER 0
    mov     x27, x0
    mov     x25, x1
    mov     x21, x2
    mov     x26, x3
    mov     x0, x26
    bl      lantern_node_api_advance
    ldr     x0, [x25, #ApiRoute_op]
    cmp     x0, #API_OP_GET_STATE_V2
    b.eq    64f
    sub     x9, x0, #API_OP_GET_PENDING_CONSOLIDATIONS  /* the pending lists: a stream of the state, no data */
    cmp     x9, #2
    b.hi    5f
    str     xzr, [x26, #ApiView_look_data]
    b       64f
5:  cmp     x0, #API_OP_GET_STATE_RANDAO    /* getStateRandao, getEpochSyncCommittees: the epoch in the work's data */
    ccmp    x0, #API_OP_GET_EPOCH_SYNC_COMMITTEES, #4, ne
    b.ne    1f
    ldr     x9, [x25, #ApiRoute_present]
    tbnz    x9, #API_PARAM_EPOCH, 2f
    mov     x10, #-1
    str     x10, [x25, #ApiRoute_epoch]
2:  add     x0, x25, #ApiRoute_epoch
    bl      lantern_node_api_put8
    str     x0, [x26, #ApiView_look_data]
    b       67f
1:  cmp     x0, #API_OP_GET_PROPOSER_LOOKAHEAD  /* getProposerLookahead: SSZ, an answer flag */
    b.ne    3f
    ldr     x9, [x25, #ApiRoute_response]
    cmp     x9, #API_TYPE_SSZ
    b.ne    67f
    orr     x21, x21, #API_ANSWER_SSZ
    b       67f
3:  sub     x9, x0, #API_OP_GET_STATE_VALIDATORS
    cmp     x9, #(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS)
    b.hi    67f
    ldr     x9, [x26, #ApiView_look_data]   /* the validator operations: their ids; getStateValidator a work, the others a stream */
    cbnz    x9, 4f
    mov     x0, x25
    bl      lantern_node_api_ids
    str     x0, [x26, #ApiView_look_data]
4:  ldr     x0, [x25, #ApiRoute_op]
    cmp     x0, #API_OP_GET_STATE_VALIDATOR
    b.ne    64f
67: ldr     x0, [x25, #ApiRoute_op]         /* a work */
    mov     x1, x27
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_encode
    LEAVE 0
64: mov     x0, x27                         /* a stream of the answer */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      lantern_node_api_stream
    LEAVE 0
END_FUNCTION lantern_node_api_state_answer

/*
 * L3: the state of the chain at the slot x0, as for a state_id of it, and past the store's slot the
 * head's post-state brought to it (beacon-api.md, getBlockRewards), with the route x21 and the view
 * x22: x0 = 0 or 404, x1 its id, x2 1 when it is a copy. Locals: L the slot.
 */
LOCAL_FUNCTION lantern_node_api_rewards_state
    ENTER 16
    str     x0, [sp, #L]
    mov     x0, x20
    bl      lantern_node_store_slot
    ldr     x10, [sp, #L]
    mov     x9, #API_ID_SLOT
    cmp     x10, x0
    b.ls    1f
    mov     x9, #API_ID_HEAD
1:  stp     x9, x10, [x21, #ApiRoute_id_kind]
    str     xzr, [x22, #ApiView_look_copy]
    mov     x0, x21
    mov     x1, x22
    bl      lantern_node_api_state
    cbnz    x0, 9f
    ldr     x9, [sp, #L]
    str     x9, [x22, #ApiView_head_slot]
    mov     x0, x22
    bl      lantern_node_api_advance
    ldr     x1, [x22, #ApiView_look_state]
    ldr     x2, [x22, #ApiView_look_copy]
    mov     x0, #0
9:  LEAVE 16
END_FUNCTION lantern_node_api_rewards_state

/*
 * L2: getBlockRewards and getSyncCommitteeRewards (node.md, NODE_EV_API): the block, a NodeBlock with
 * bytes; P, its parent's post-state brought to its slot; getSyncCommitteeRewards its ids as state_b,
 * getBlockRewards of a phase0 block the E states as state_b and state_c; a NODE_WORK_API_ENCODE, then a
 * STATE_FREE of each copy. (connection x0, route x1, answer flags x2, view x3) -> x0 = 0, or the error
 * status. x21 the route, x22 the view, x25 the parent. Locals: L the connection, L+8 the flags, L+16 P,
 * L+24 state_b, L+32 state_c, L+40 1 when state_b is a copy, L+48 1 when state_c is, L+56 the block's
 * slot, L+64 its values, L+72 its bytes, L+80 its fork, L+88 a slot, L+96 the status.
 */
LOCAL_FUNCTION lantern_node_api_rewards
    ENTER 112
    stp     x0, x2, [sp, #L]
    mov     x21, x1
    mov     x22, x3
    mov     x0, x21
    mov     x1, x22
    bl      lantern_node_api_block
    cbnz    x0, 9f
    mov     x0, #404
    ldr     x9, [x22, #ApiView_look_index]  /* a NodeBlock with bytes */
    cmn     x9, #1
    b.eq    9f
    ldr     x9, [x22, #ApiView_look_data]
    cbz     x9, 9f
    str     x9, [sp, #(L + 72)]
    ldr     x0, [x22, #ApiView_head_slot]
    str     x0, [sp, #(L + 56)]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    str     x0, [sp, #(L + 80)]
    ldr     x9, [x21, #ApiRoute_op]         /* getSyncCommitteeRewards of a phase0 block: 400 */
    cmp     x9, #API_OP_GET_SYNC_COMMITTEE_REWARDS
    b.ne    1f
    mov     x9, x0
    mov     x0, #400
    cbz     x9, 9f
1:  ldr     x9, [x22, #ApiView_canonical]   /* the values of the block */
    LDQ     x10, x22, ApiView_head_finalized
    ldr     x11, [x22, #ApiView_is_optimistic]
    orr     x9, x9, x10, lsl #1
    orr     x9, x9, x11, lsl #2
    str     x9, [sp, #(L + 64)]
    add     x0, x22, #ApiView_head_root     /* the parent, imported, with a post-state */
    bl      lantern_node_find_block
    mov     x9, x0
    mov     x0, #404
    cmn     x9, #1
    b.eq    9f
    add     x0, x1, #NodeBlock_parent_root
    bl      lantern_node_find_block
    mov     x9, x0
    mov     x0, #404
    cmn     x9, #1
    b.eq    9f
    mov     x25, x1
    ldr     x9, [x25, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    9f
    ldr     x0, [x25, #NodeBlock_state_id]
    cbnz    x0, 2f
    bl      lantern_node_f_slot
    ldr     x9, [x25, #NodeBlock_slot]
    cmn     x0, #1
    b.eq    8f
    cmp     x9, x0
    b.ls    8f
    mov     x0, x25
    bl      lantern_node_rebuild
    cbz     x0, 8f
2:  str     x0, [x22, #ApiView_look_state]  /* P: a copy brought to the block's slot */
    ldr     x9, [x25, #NodeBlock_slot]
    str     x9, [x22, #ApiView_look_state_slot]
    ldr     x9, [sp, #(L + 56)]
    str     x9, [x22, #ApiView_head_slot]
    mov     x0, x22
    bl      lantern_node_api_advance
    ldr     x9, [x22, #ApiView_look_state]
    str     x9, [sp, #(L + 16)]
    stp     xzr, xzr, [sp, #(L + 24)]
    stp     xzr, xzr, [sp, #(L + 40)]
    str     xzr, [sp, #(L + 96)]
    ldr     x9, [x21, #ApiRoute_op]
    cmp     x9, #API_OP_GET_SYNC_COMMITTEE_REWARDS
    b.ne    3f
    mov     x0, x21                         /* getSyncCommitteeRewards: its ids as state_b */
    bl      lantern_node_api_ids
    str     x0, [sp, #(L + 24)]
    b       6f
3:  ldr     x9, [sp, #(L + 80)]             /* getBlockRewards of a phase0 block of epoch b: the E states */
    cbnz    x9, 6f
    ldr     x9, [sp, #(L + 56)]
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x9, x9, x10
    cbz     x9, 4f
    add     x0, x9, #1                      /* early: the state at the last slot of b */
    mul     x0, x0, x10
    sub     x0, x0, #1
    bl      lantern_node_api_rewards_state
    str     x0, [sp, #(L + 96)]
    cbnz    x0, 7f
    str     x1, [sp, #(L + 24)]
    str     x2, [sp, #(L + 40)]
4:  ldr     x9, [sp, #(L + 56)]             /* late: at the last slot of b + 1, when that epoch is phase0's */
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x9, x9, x10
    add     x0, x9, #2
    mul     x0, x0, x10
    sub     x0, x0, #1
    str     x0, [sp, #(L + 88)]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    cbnz    x0, 6f
    ldr     x0, [sp, #(L + 88)]
    bl      lantern_node_api_rewards_state
    str     x0, [sp, #(L + 96)]
    cbnz    x0, 7f
    str     x1, [sp, #(L + 32)]
    str     x2, [sp, #(L + 48)]
6:  ldp     x4, x10, [sp, #L]               /* the work: arg as lantern_node_api_encode packs it */
    ldr     x11, [x21, #ApiRoute_op]
    orr     x5, x11, x10, lsl #8
    ldr     x12, [sp, #(L + 64)]
    orr     x5, x5, x12, lsl #16
    ldr     x12, [sp, #(L + 56)]
    orr     x5, x5, x12, lsl #24
    mov     x0, #NODE_WORK_API_ENCODE
    ldr     x1, [sp, #(L + 16)]
    ldr     x2, [sp, #(L + 24)]
    ldr     x3, [sp, #(L + 72)]
    bl      lantern_node_work
    ldr     x9, [sp, #(L + 32)]
    str     x9, [x0, #NodeAction_state_c]
7:  mov     x0, #NODE_ACT_STATE_FREE        /* the copies go after the work */
    ldr     x1, [sp, #(L + 16)]
    mov     x2, #0
    bl      lantern_node_ids
    ldr     x9, [sp, #(L + 40)]
    cbz     x9, 71f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [sp, #(L + 24)]
    mov     x2, #0
    bl      lantern_node_ids
71: ldr     x9, [sp, #(L + 48)]
    cbz     x9, 72f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [sp, #(L + 32)]
    mov     x2, #0
    bl      lantern_node_ids
72: ldr     x0, [sp, #(L + 96)]
9:  LEAVE 112
8:  mov     x0, #404
    LEAVE 112
END_FUNCTION lantern_node_api_rewards

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_ENCODE (node.md, lantern_node_step): its
 * response to the connection, or the error 500. x19 the node, x24 the actions. x21 the event,
 * x22 the action, x23 the response's bytes, x25 the flags.
 */
LOCAL_FUNCTION lantern_node_api_done
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_arg]
    and     x10, x9, #255                   /* getSyncCommitteeRewards: its ids in state_b go */
    cmp     x10, #API_OP_GET_SYNC_COMMITTEE_REWARDS
    b.ne    3f
    ldr     x1, [x21, #NodeAction_state_b]
    cbz     x1, 3f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
    ldr     x9, [x21, #NodeAction_arg]
3:
    and     x10, x9, #255                   /* getStateValidator: its ids go; produceAttestationData its index; the epoch reads their epoch */
    mov     x11, #API_OP_PRODUCE_ATTESTATION_DATA
    mov     x12, #API_OP_GET_ATTESTER_DUTIES
    mov     x13, #API_OP_GET_SYNC_COMMITTEE_DUTIES
    cmp     x10, #API_OP_GET_STATE_VALIDATOR
    ccmp    x10, x11, #4, ne
    ccmp    x10, x12, #4, ne
    ccmp    x10, x13, #4, ne
    ccmp    x10, #API_OP_GET_STATE_RANDAO, #4, ne
    ccmp    x10, #API_OP_GET_EPOCH_SYNC_COMMITTEES, #4, ne
    mov     x14, #API_OP_GET_LIVENESS
    ccmp    x10, x14, #4, ne
    mov     x14, #API_OP_GET_LIGHT_CLIENT_BOOTSTRAP
    ccmp    x10, x14, #4, ne
    mov     x14, #API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE
    ccmp    x10, x14, #4, ne
    b.ne    2f
    ldr     x1, [x21, #NodeAction_data]
    cbz     x1, 2f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
    ldr     x9, [x21, #NodeAction_arg]
2:  ubfx    x10, x9, #8, #8
    and     x25, x10, #API_ANSWER_CLOSE     /* API_R_CLOSE, or API_R_KEEP for HTTP/1.0 kept open */
    cbnz    x25, 1f
    tst     x10, #API_ANSWER_HTTP10
    mov     x11, #API_R_KEEP
    csel    x25, x11, xzr, ne
1:  ldr     x9, [x21, #NodeEvent_result]
    cbnz    x9, 5f
    ldr     x9, [x21, #(NodeEvent_chunk + 16)]  /* the chunk's bytes in a SEND */
    add     x1, x9, #(56 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_API_SEND
    bl      lantern_node_act
    mov     x22, x0
    ldr     x9, [x21, #NodeAction_target]
    mov     x10, #1
    stp     x9, x10, [x22, #16]
    ldr     x9, [x22]
    sub     x9, x9, #32
    mov     x10, #24
    stp     x9, x10, [x22, #32]
    ldr     x2, [x21, #(NodeEvent_chunk + 16)]
    str     x2, [x22, #48]
    add     x0, x22, #56
    ldr     x9, [x21, #(NodeEvent_chunk + 8)]
    add     x1, x21, #NodeEvent_chunk
    add     x1, x1, x9
    bl      lantern_copy
    ldr     x9, [x22, #48]                  /* zero bytes to the size */
    add     x0, x22, #56
    add     x0, x0, x9
    ldr     x10, [x22]
    sub     x1, x10, #56
    sub     x1, x1, x9
    bl      lantern_zero
    tbz     x25, #0, 9f
    mov     x0, #NODE_ACT_API_CLOSE
    mov     x1, #NODE_ACT_API_CLOSE_SIZE
    bl      lantern_node_act
    ldr     x9, [x21, #NodeAction_target]
    str     x9, [x0, #16]
    LEAVE 0
5:  ldr     x0, [x21, #NodeAction_target]   /* not valid: the error 500 */
    mov     x1, #0
    mov     x2, #500
    mov     x3, #API_BODY_ERROR
    mov     x4, x25
    bl      lantern_node_api_send
9:  LEAVE 0
END_FUNCTION lantern_node_api_done

/*
 * (node, store, work, state_a, data, scratch, event, room; the seen in x8) -> status: a
 * NODE_WORK_API_ENCODE of lantern_node_run (node.md): the response at NodeEvent_chunk of the event,
 * whose buffer has room bytes. x19 the node, x20 the store, x21 the work, x22 state_a, x23 data, x24
 * the scratch, x25 the event, x26 the ApiView at the end of scratch, x27 the operation, x28 the room.
 * Locals: L the scratch's size, L+8 a kept word, L+16 a Result, L+24 a blob count, L+32 the seen.
 */
LOCAL_FUNCTION lantern_node_api_run
    ENTER 64
    ldr     x9, [x8]                        /* x8: the seen, state_b and state_c */
    str     x9, [sp, #(L + 32)]
    ldp     x9, x10, [x8, #8]
    stp     x9, x10, [sp, #(L + 40)]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    mov     x23, x4
    mov     x24, x5
    mov     x25, x6
    mov     x28, x7
    ldr     x9, [x21, #NodeAction_arg]      /* the operation; a block index past the blocks part */
    and     x27, x9, #255
    lsr     x10, x9, #24
    cmp     x27, #API_OP_GET_BLOCK_HEADER
    b.ne    1f
    ldr     x11, [x19, #(Node_blocks + 8)]
    cmp     x10, x11
    b.hi    8f
    orr     x11, x23, x10                   /* a header: bytes, or a block of the node with a post-state */
    cbz     x11, 8f
    cbnz    x23, 2f
    cbz     x10, 8f
    cbz     x22, 8f
    b       2f
1:  cmp     x27, #API_OP_GET_SPEC           /* getSpec, getDebugChainHeadsV2, getDebugForkChoice: no state */
    b.eq    2f
    sub     x9, x27, #API_OP_GET_LIGHT_CLIENT_BOOTSTRAP  /* the light client reads: the light client store */
    cmp     x9, #(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP)
    b.ls    2f
    cmp     x27, #API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE
    b.eq    2f
    cmp     x27, #API_OP_GET_DEBUG_CHAIN_HEADS_V2
    b.eq    2f
    cmp     x27, #API_OP_GET_DEBUG_FORK_CHOICE
    b.eq    2f
    cbz     x22, 8f                         /* a state's answer: a state */
    cmp     x27, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.eq    2f
    cmp     x27, #API_OP_GET_STATE_VALIDATOR
    b.eq    2f
    cmp     x27, #API_OP_GET_STATE_ROOT
    b.eq    2f
    cmp     x27, #API_OP_GET_PROPOSER_DUTIES
    b.eq    2f
    cmp     x27, #API_OP_GET_PROPOSER_DUTIES_V2
    b.eq    2f
    cmp     x27, #API_OP_PRODUCE_ATTESTATION_DATA
    b.eq    2f
    cmp     x27, #API_OP_GET_ATTESTER_DUTIES
    b.eq    2f
    cmp     x27, #API_OP_GET_SYNC_COMMITTEE_DUTIES
    b.eq    2f
    cmp     x27, #API_OP_GET_STATE_RANDAO
    b.eq    2f
    cmp     x27, #API_OP_GET_EPOCH_SYNC_COMMITTEES
    b.eq    2f
    cmp     x27, #API_OP_GET_PROPOSER_LOOKAHEAD
    b.eq    2f
    cmp     x27, #API_OP_GET_LIVENESS
    b.eq    2f
    cmp     x27, #API_OP_GET_BLOCK_REWARDS
    b.eq    2f
    cmp     x27, #API_OP_GET_SYNC_COMMITTEE_REWARDS
    b.eq    2f
    cmp     x27, #API_OP_GET_STATE_FORK
    b.ne    8f
2:  ldr     x9, [x24]                       /* the ApiView at the end of scratch, with the work's values */
    str     x9, [sp, #L]
    MOVQ    x10, ApiView__size
    subs    x9, x9, x10
    b.lo    7f
    str     x9, [x24]
    add     x26, x24, x9
    mov     x0, x26
    bl      lantern_node_api_view
    ldr     x9, [x21, #NodeAction_arg]
    ubfx    x10, x9, #16, #1
    str     x10, [x26, #ApiView_canonical]
    ubfx    x10, x9, #17, #1
    STQ     x10, x26, ApiView_head_finalized
    ubfx    x10, x9, #18, #1
    str     x10, [x26, #ApiView_is_optimistic]
    str     xzr, [x26, #ApiView_status]
    cmp     x27, #API_OP_GET_BLOCK_HEADER
    b.eq    3f
    sub     x10, x27, #API_OP_GET_LIGHT_CLIENT_BOOTSTRAP   /* x9: the work's arg, below */
    cmp     x10, #(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP)
    b.hi    30f
    ldr     x0, [sp, #(L + 48)]             /* the light client reads: the object, and its JSON */
    mov     x1, x21
    mov     x2, x23
    mov     x3, x24
    mov     x4, x26
    bl      lantern_node_api_lc_read
    cbz     x0, 5f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    ldr     x9, [sp, #L]
    str     x9, [x24]
    LEAVE 64
30: cmp     x27, #API_OP_GET_SPEC
    b.eq    5f
    cmp     x27, #API_OP_GET_DEBUG_CHAIN_HEADS_V2
    b.eq    29f
    cmp     x27, #API_OP_GET_DEBUG_FORK_CHOICE
    b.eq    28f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* a state at the work's slot, else the work that brought it there failed */
    lsr     x9, x9, #24
    cmp     x27, #API_OP_GET_LIVENESS       /* getLiveness: the state at its own slot, the epoch in arg */
    b.eq    43f
    cmp     x0, x9
    b.ne    42f
43: add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    cmp     x27, #API_OP_GET_BLOCK_REWARDS
    b.eq    277f
    cmp     x27, #API_OP_GET_SYNC_COMMITTEE_REWARDS
    b.eq    278f
    cmp     x27, #API_OP_GET_STATE_VALIDATOR
    b.ne    271f
    mov     x0, x22                         /* getStateValidator: the validator of its ids */
    mov     x1, x23
    cbz     x1, 8f
    bl      lantern_node_api_find_validator
    str     x22, [x26, #ApiView_val_state]
    str     x0, [x26, #ApiView_val_index]
    b       5f
271: cmp    x27, #API_OP_GET_STATE_RANDAO   /* getStateRandao: lantern_node_randao of the epoch in data */
    b.ne    272f
    cbz     x23, 41f
    ldr     x9, [x23, #16]
    cmp     x9, #8
    b.lo    41f
    ldr     x9, [x23, #8]
    ldr     x1, [x23, x9]
    mov     x0, x22
    ADDQ    x2, x26, ApiView_randao
    FORK_CALL node_randao
    b       275f
272: cmp    x27, #API_OP_GET_EPOCH_SYNC_COMMITTEES  /* lantern_node_sync_committee of the epoch in data, its out at the end of scratch */
    b.ne    274f
    cbz     x23, 41f
    ldr     x9, [x23, #16]
    cmp     x9, #8
    b.lo    41f
    ldr     x9, [x23, #8]
    ldr     x1, [x23, x9]
    ldr     x10, [x24]
    MOVQ    x11, 8 * SYNC_COMMITTEE_SIZE
    subs    x10, x10, x11
    b.lo    71f
    str     x10, [x24]
    add     x3, x24, x10
    str     x3, [x26, #ApiView_sync_out]
    mov     x0, x22
    mov     x2, x24
    FORK_CALL node_sync_committee
    b       275f
274: cmp    x27, #API_OP_GET_SYNC_COMMITTEE_DUTIES  /* lantern_node_sync_committee of the state's epoch, or of the next period's */
    b.ne    273f
    cbz     x23, 41f
    STQ     x23, x26, ApiView_sd_ids
    str     x22, [x26, #ApiView_val_state]
    ldr     x1, [x22, #NODE_STATE_SLOT]
    mov     x10, #SLOTS_PER_EPOCH
    udiv    x1, x1, x10
    ldr     x9, [x21, #NodeAction_arg]
    tst     x9, #(API_VALUE_NEXT_PERIOD << 16)
    b.eq    2741f
    add     x1, x1, #EPOCHS_PER_SYNC_COMMITTEE_PERIOD
2741: ldr   x10, [x24]
    MOVQ    x11, 8 * SYNC_COMMITTEE_SIZE
    subs    x10, x10, x11
    b.lo    71f
    str     x10, [x24]
    add     x3, x24, x10
    str     x3, [x26, #ApiView_sync_out]
    mov     x0, x22
    mov     x2, x24
    FORK_CALL node_sync_committee
    b       275f
273: cmp    x27, #API_OP_GET_PROPOSER_LOOKAHEAD     /* lantern_node_proposer_lookahead; the version the state's fork */
    b.ne    20f
    str     x15, [x26, #ApiView_fork]
    mov     x0, x22
    ADDQ    x1, x26, ApiView_lookahead
    FORK_CALL node_proposer_lookahead
275: cmp    x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cmp     x0, #LANTERN_NO_STATE_ANSWER   /* no answer in the state: 400 */
    b.ne    276f
    mov     x9, #400
    str     x9, [x26, #ApiView_status]
    b       5f
276: cbz    x0, 5f
    str     x0, [x25, #NodeEvent_result]
    b       9f
277: cbz    x23, 41f                        /* getBlockRewards: lantern_node_block_rewards of the block in data, its out at the end of scratch */
    ldr     x10, [x24]
    subs    x10, x10, #48
    b.lo    71f
    str     x10, [x24]
    add     x6, x24, x10
    STQ     x6, x26, ApiView_live_out
    mov     x0, x22
    mov     x1, x23
    ldp     x2, x3, [sp, #(L + 40)]
    add     x4, x19, #Node_config
    mov     x5, x24
    FORK_CALL node_block_rewards
    b       279f
278: cbz    x23, 41f                        /* getSyncCommitteeRewards: lantern_node_sync_rewards, its out at the end of scratch; its ids in state_b */
    ldr     x9, [sp, #(L + 40)]
    STQ     x9, x26, ApiView_sd_ids
    str     x22, [x26, #ApiView_val_state]
    ldr     x10, [x24]
    MOVQ    x11, 24 + 16 * SYNC_COMMITTEE_SIZE
    subs    x10, x10, x11
    b.lo    71f
    str     x10, [x24]
    add     x3, x24, x10
    str     x11, [x3]
    STQ     x3, x26, ApiView_live_out
    mov     x0, x22
    mov     x1, x23
    mov     x2, x24
    FORK_CALL node_sync_rewards
279: cmp    x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cmp     x0, #LANTERN_NO_STATE_ANSWER    /* no answer in the state: 400 */
    b.ne    276b
    mov     x9, #400
    str     x9, [x26, #ApiView_status]
    b       5f
20: cmp     x27, #API_OP_PRODUCE_ATTESTATION_DATA
    b.ne    25f
    cbz     x23, 41f                        /* produceAttestationData: lantern_node_attestation_data, its index in data */
    ldr     x9, [x23, #16]
    cmp     x9, #8
    b.lo    41f
    ldr     x9, [x23, #8]
    ldr     x2, [x23, x9]
    mov     x0, x22
    add     x1, x19, #Node_config
    mov     x3, x24
    ADDQ    x4, x26, ApiView_att
    FORK_CALL node_attestation_data
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 5f
    str     x0, [x25, #NodeEvent_result]
    b       9f
25: cmp     x27, #API_OP_GET_ATTESTER_DUTIES
    b.ne    251f
    cbz     x23, 41f                        /* getAttesterDuties: lantern_node_attester_duties of its ids, its out at the end of scratch */
    ldr     x9, [x23, #16]
    lsr     x9, x9, #6
    STQ     x9, x26, ApiView_ad_count
    mov     x10, #48
    mul     x9, x9, x10
    add     x9, x9, #40
    ldr     x10, [x24]
    subs    x10, x10, x9
    b.lo    71f
    str     x10, [x24]
    add     x4, x24, x10
    STQ     x4, x26, ApiView_ad_out
    mov     x0, x22
    add     x1, x19, #Node_config
    mov     x2, x23
    mov     x3, x24
    FORK_CALL node_attester_duties
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 24f
    str     x0, [x25, #NodeEvent_result]
    b       9f
251: cmp    x27, #API_OP_GET_LIVENESS
    b.ne    26f
    cbz     x23, 41f                        /* getLiveness: lantern_node_liveness of its ids and the epoch, its out at the end of scratch */
    STQ     x23, x26, ApiView_sd_ids
    ldr     x9, [x23, #16]
    lsr     x9, x9, #6
    add     x9, x9, #7
    and     x9, x9, #~7
    ldr     x10, [x24]
    subs    x10, x10, x9
    b.lo    71f
    str     x10, [x24]
    add     x6, x24, x10
    STQ     x6, x26, ApiView_live_out
    mov     x0, x22
    add     x1, x19, #Node_config
    ldr     x2, [sp, #(L + 32)]
    mov     x3, x23
    ldr     x4, [x21, #NodeAction_arg]
    lsr     x4, x4, #24
    mov     x5, x24
    FORK_CALL node_liveness
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 24f
    str     x0, [x25, #NodeEvent_result]
    b       9f
26: cmp     x27, #API_OP_GET_PROPOSER_DUTIES
    b.eq    261f
    cmp     x27, #API_OP_GET_PROPOSER_DUTIES_V2
    b.ne    23f
261: mov    x0, x22                         /* getProposerDuties and V2: lantern_node_proposers */
    add     x1, x19, #Node_config
    mov     x2, x24
    add     x3, x26, #ApiView_duties
    FORK_CALL node_proposers
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 262f
    str     x0, [x25, #NodeEvent_result]
    b       9f
262: cmp    x27, #API_OP_GET_PROPOSER_DUTIES_V2
    b.ne    24f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* V2 from epoch 1: get_block_root_at_slot of max(the first slot - SLOTS_PER_EPOCH - 1, 0) */
    cbz     x0, 24f
    subs    x9, x0, #(SLOTS_PER_EPOCH + 1)
    csel    x9, x9, xzr, hs
    str     x9, [sp, #(L + 56)]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    mov     x0, x22
    add     x1, sp, #(L + 56)
    add     x2, x26, #ApiView_duties
    FORK_CALL get_block_root_at_slot
    cbz     x0, 24f
    str     x0, [x25, #NodeEvent_result]
    b       9f
24: str     x22, [x26, #ApiView_val_state]
    b       5f
23: cmp     x27, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.ne    21f
    mov     x0, x22                         /* finality_checkpoints */
    add     x1, x26, #ApiView_previous_justified
    FORK_CALL node_state_checkpoints
    b       5f
21: cmp     x27, #API_OP_GET_STATE_FORK
    b.ne    22f
    ADDQ    x0, x26, ApiView_state_fork     /* fork */
    add     x1, x22, #NODE_STATE_FORK
    mov     x2, #16
    bl      lantern_copy
    b       5f
22: mov     x0, x22                         /* root */
    LDQ     x1, x19, Node_config + CONFIG_STATE_CACHE
    mov     x2, x24
    add     x3, x26, #ApiView_head_root
    FORK_CALL state_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    b       5f
3:  cbz     x23, 33f
    ldr     x9, [x23, #16]                  /* header: of the bytes, at the fork of their slot */
    cmp     x9, #(100 + 84)
    b.lo    41f
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    str     x15, [sp, #(L + 24)]
    mov     x0, x23
    mov     x1, x24
    add     x2, x26, #(ApiView_proposer_index - 8)  /* the header's slot lands on the root's last 8 bytes */
    FORK_CALL node_block_header
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    ldr     x9, [x26, #(ApiView_proposer_index - 8)]
    str     x9, [x26, #ApiView_head_slot]
    ldr     x9, [x21, #NodeAction_arg]      /* the root: the node's block's, else of the bytes */
    lsr     x9, x9, #24
    cbnz    x9, 34f
    ldr     x15, [sp, #(L + 24)]
    mov     x0, x23
    mov     x1, x24
    add     x2, x26, #ApiView_head_root
    add     x3, sp, #(L + 16)
    add     x4, sp, #(L + 24)
    FORK_CALL node_block_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    ldr     x9, [sp, #(L + 16)]
    cbnz    x9, 41f
    b       5f
33: add     x0, x26, #ApiView_proposer_index    /* no bytes: the state's latest_block_header, a zero signature */
    add     x1, x22, #(NODE_STATE_HEADER + 8)
    mov     x2, #(112 - 8)
    bl      lantern_copy
    ldr     x9, [x22, #NODE_STATE_HEADER]
    str     x9, [x26, #ApiView_head_slot]
    ldp     x9, x10, [x26, #ApiView_state_root]
    ldp     x11, x12, [x26, #(ApiView_state_root + 16)]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbnz    x9, 34f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* a zero state_root: the state's root */
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    mov     x0, x22
    LDQ     x1, x19, Node_config + CONFIG_STATE_CACHE
    mov     x2, x24
    add     x3, x26, #ApiView_state_root
    FORK_CALL state_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
34: ldr     x9, [x21, #NodeAction_arg]      /* the root of the node's block, index - 1 */
    lsr     x9, x9, #24
    cbz     x9, 5f
    sub     x9, x9, #1
    PART    x10, x11, x19, Node_blocks
    mov     x11, #NodeBlock__mem
    madd    x1, x9, x11, x10
    add     x0, x26, #ApiView_head_root
    bl      lantern_copy_root
5:  ldr     x9, [x21, #NodeAction_arg]      /* the response, in the event */
    ubfx    x10, x9, #8, #8
    and     x4, x10, #API_ANSWER_CLOSE
    cbnz    x4, 51f
    tst     x10, #API_ANSWER_HTTP10
    mov     x11, #API_R_KEEP
    csel    x4, x11, xzr, ne
51: tst     x10, #API_ANSWER_SSZ            /* SSZ: API_R_SSZ */
    orr     x11, x4, #API_R_SSZ
    csel    x4, x11, x4, ne
    sub     x9, x28, #NodeEvent_chunk
    and     x9, x9, #~7
    cmp     x9, #24
    b.lo    71f
    str     x9, [x25, #NodeEvent_chunk]
    mov     x0, x26
    add     x1, x25, #NodeEvent_chunk
    mov     x2, #200
    mov     x3, x27
    cmp     x27, #API_OP_GET_STATE_VALIDATOR    /* no such validator: 404 */
    b.ne    52f
    ldr     x9, [x26, #ApiView_val_index]
    cmn     x9, #1
    b.ne    52f
    mov     x2, #404
    mov     x3, #API_BODY_ERROR
52: ldr     x9, [x26, #ApiView_status]      /* an error status of the work */
    cbz     x9, 53f
    mov     x2, x9
    mov     x3, #API_BODY_ERROR
    and     x4, x4, #~API_R_SSZ
    b       54f
53: cmp     x27, #API_OP_GET_PROPOSER_LOOKAHEAD /* Eth-Consensus-Version of getProposerLookahead and the light client reads */
    b.eq    531f
    sub     x9, x27, #API_OP_GET_LIGHT_CLIENT_BOOTSTRAP
    cmp     x9, #(API_OP_GET_LIGHT_CLIENT_OPTIMISTIC_UPDATE - API_OP_GET_LIGHT_CLIENT_BOOTSTRAP)
    b.hi    54f
    cmp     x27, #API_OP_GET_LIGHT_CLIENT_UPDATES_BY_RANGE  /* no version: of each item */
    b.eq    54f
531: orr    x4, x4, #API_R_VERSION
54: bl      lantern_api_respond
    cbnz    x0, 71f
    ldr     x9, [x25, #(NodeEvent_chunk + 16)]  /* the event's size covers the chunk */
    add     x9, x9, #(NodeEvent_chunk + 24 + 7)
    and     x9, x9, #~7
    str     x9, [x25]
    sub     x9, x9, #NodeEvent_chunk
    str     x9, [x25, #NodeEvent_chunk]
    b       9f
    /* getDebugChainHeadsV2: a byte for each store node at the end of scratch, 1 when it is out of the tree, 2 when a node not out has it as parent */
29: ldr     x9, [x20, #Store_blocks]
    add     x9, x20, x9
    ldr     x10, [x20, #(Store_blocks + 8)]
    ldr     x11, [x24]
    add     x12, x10, #7
    and     x12, x12, #~7
    cmp     x11, x12
    b.lo    71f
    sub     x11, x11, x12
    str     x11, [x24]
    add     x13, x24, x11
    str     x13, [x26, #ApiView_heads]
    str     x20, [x26, #ApiView_val_state]
    mov     x14, #0
291: cmp    x14, x10
    b.hs    5b
    mov     x15, #BlockNode__mem
    madd    x15, x14, x15, x9
    ldr     x12, [x15, #BlockNode_payload_status]
    cmp     x12, #PAYLOAD_STATUS_INVALIDATED
    cset    w12, eq
    ldr     x11, [x15, #BlockNode_parent]
    cmp     x11, x10
    b.hs    293f
    ldrb    w16, [x13, x11]
    and     w16, w16, #1
    orr     w12, w12, w16
    cbnz    w12, 293f
    ldrb    w16, [x13, x11]
    orr     w16, w16, #2
    strb    w16, [x13, x11]
293: strb   w12, [x13, x14]
    add     x14, x14, #1
    b       291b
    /* getDebugForkChoice: lantern_node_weights of the fork of the head's slot into the end of scratch; a failure, the error 500 */
28: LDQ     x10, x20, Store_blocks + 8
    ldr     x11, [x24]
    lsl     x12, x10, #3
    cmp     x11, x12
    b.lo    71f
    sub     x11, x11, x12
    str     x11, [x24]
    add     x9, x24, x11
    STQ     x9, x26, ApiView_weights
    str     x20, [x26, #ApiView_val_state]
    ldr     x0, [x26, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    mov     x0, x20
    mov     x1, x24
    LDQ     x2, x26, ApiView_weights
    FORK_CALL node_weights
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 5b
    mov     x9, #500
    str     x9, [x26, #ApiView_status]
    b       5b
42: mov     x9, #LANTERN_INVALID_SLOT
    str     x9, [x25, #NodeEvent_result]
    b       9f
41: mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x25, #NodeEvent_result]
9:  ldr     x9, [sp, #L]
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 64
8:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 64
71: ldr     x9, [sp, #L]
    str     x9, [x24]
7:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
END_FUNCTION lantern_node_api_run

/*
 * (node, work, state_a, data, scratch, event, room) -> status: a NODE_WORK_API_EVENT of
 * lantern_node_run (node.md): the event's text at NodeEvent_chunk of the event, whose buffer has
 * room bytes. x19 the node, x21 the work, x22 state_a, x23 data, x24 the scratch, x25 the event,
 * x26 the ApiView at the end of scratch, x27 the topic, x28 the room. Locals: L the scratch's
 * size, L+8 a Result, L+16 a blob count.
 */
LOCAL_FUNCTION lantern_node_api_event_run
    ENTER 32
    mov     x19, x0
    mov     x21, x1
    mov     x22, x2
    mov     x23, x3
    mov     x24, x4
    mov     x25, x5
    mov     x28, x6
    str     x7, [sp, #(L + 24)]             /* state_c: the light client store */
    ldr     x9, [x21, #NodeAction_arg]
    and     x27, x9, #255
    ldr     x9, [x24]                       /* the ApiView at the end of scratch, with the work's values */
    str     x9, [sp, #L]
    MOVQ    x10, ApiView__size
    subs    x9, x9, x10
    b.lo    7f
    str     x9, [x24]
    add     x26, x24, x9
    ldr     x9, [x21, #NodeAction_arg]
    ubfx    x10, x9, #8, #8
    str     x10, [x26, #ApiView_event_flags]
    lsr     x10, x9, #16
    str     x10, [x26, #ApiView_event_epoch]
    cmp     x27, #API_TOPIC_HEAD
    b.eq    1f
    cmp     x27, #API_TOPIC_HEAD_V2
    b.eq    1f
    cmp     x27, #API_TOPIC_CHAIN_REORG
    b.eq    20f
    cmp     x27, #API_TOPIC_FINALIZED_CHECKPOINT
    b.ne    10f
    cbnz    x23, 3f
1:  cbz     x22, 8f                         /* of a post-state: lantern_node_event_roots */
    ldr     x0, [x22, #NODE_STATE_SLOT]
    str     x0, [x26, #ApiView_event_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    str     x0, [x26, #ApiView_fork]        /* head_v2's version */
    mov     x0, x22
    add     x1, x19, #Node_config
    mov     x2, x24
    add     x3, x26, #ApiView_event_block
    FORK_CALL node_event_roots
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 5f
    str     x0, [x25, #NodeEvent_result]
    b       9f
3:  ldr     x9, [x23, #16]                  /* of a block's bytes: its root and its state_root */
    cmp     x9, #(100 + 84)
    b.lo    41f
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    add     x1, x9, #(100 + 48)
    add     x0, x26, #ApiView_event_state
    bl      lantern_copy_root
    mov     x0, x23
    mov     x1, x24
    add     x2, x26, #ApiView_event_block
    add     x3, sp, #(L + 8)
    add     x4, sp, #(L + 16)
    FORK_CALL node_block_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    ldr     x9, [sp, #(L + 8)]
    cbnz    x9, 41f
5:  sub     x9, x28, #NodeEvent_chunk       /* the text, in the event */
    and     x9, x9, #~7
    cmp     x9, #24
    b.lo    71f
    str     x9, [x25, #NodeEvent_chunk]
    mov     x0, x26
    add     x1, x25, #NodeEvent_chunk
    mov     x2, x27
    bl      lantern_api_event_text
    cbnz    x0, 71f
55: ldr     x9, [x25, #(NodeEvent_chunk + 16)]  /* the event's size covers the text */
    add     x9, x9, #(NodeEvent_chunk + 24 + 7)
    and     x9, x9, #~7
    str     x9, [x25]
    sub     x9, x9, #NodeEvent_chunk
    str     x9, [x25, #NodeEvent_chunk]
    b       9f
20: cbz     x22, 8f                         /* chain_reorg: the new head from its post-state, the old from its block's bytes */
    cbz     x23, 8f
    ldr     x0, [x22, #NODE_STATE_SLOT]
    str     x0, [x26, #ApiView_event_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    mov     x0, x22
    add     x1, x19, #Node_config
    mov     x2, x24
    add     x3, x26, #ApiView_event_block
    FORK_CALL node_event_roots
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 21f
    str     x0, [x25, #NodeEvent_result]
    b       9f
21: ldr     x9, [x23, #16]                  /* the old head block's bytes: its root and its state_root */
    cmp     x9, #(100 + 84)
    b.lo    41f
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    ldr     x9, [x23, #8]
    add     x9, x23, x9
    add     x1, x9, #(100 + 48)
    add     x0, x26, #ApiView_event_old_state
    bl      lantern_copy_root
    mov     x0, x23
    mov     x1, x24
    add     x2, x26, #ApiView_event_old_block
    add     x3, sp, #(L + 8)
    add     x4, sp, #(L + 16)
    FORK_CALL node_block_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbnz    x0, 41f
    ldr     x9, [sp, #(L + 8)]
    cbnz    x9, 41f
    b       5b
10: cmp     x27, #API_TOPIC_LIGHT_CLIENT_FINALITY_UPDATE  /* the light client topics: of the store's latest update */
    ccmp    x27, #API_TOPIC_LIGHT_CLIENT_OPTIMISTIC_UPDATE, #4, ne
    b.ne    101f
    ldr     x2, [sp, #(L + 24)]
    cbz     x2, 8f
    sub     x10, x28, #NodeEvent_chunk      /* the text, in the event */
    and     x10, x10, #~7
    cmp     x10, #64
    b.lo    71f
    str     x10, [x25, #NodeEvent_chunk]
    add     x0, x25, #NodeEvent_chunk
    mov     x1, x27
    mov     x3, x24
    bl      lantern_api_lc_event_text
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 55b
    str     x0, [x25, #NodeEvent_result]
    b       9f
101: mov    x14, #NODE_JSON_EXIT            /* an operation topic: the JSON of its bytes, lantern_node_json of the fork in arg */
    cmp     x27, #API_TOPIC_VOLUNTARY_EXIT
    b.eq    11f
    mov     x14, #NODE_JSON_BLS_CHANGE
    cmp     x27, #API_TOPIC_BLS_TO_EXECUTION_CHANGE
    b.eq    11f
    mov     x14, #NODE_JSON_PROPOSER_SLASHING
    cmp     x27, #API_TOPIC_PROPOSER_SLASHING
    b.eq    11f
    mov     x14, #NODE_JSON_ATTESTER_SLASHING
    cmp     x27, #API_TOPIC_ATTESTER_SLASHING
    b.eq    11f
    mov     x14, #NODE_JSON_ATTESTATION
    cmp     x27, #API_TOPIC_ATTESTATION
    b.eq    11f
    mov     x14, #NODE_JSON_SINGLE_ATTESTATION
    cmp     x27, #API_TOPIC_SINGLE_ATTESTATION
    b.eq    11f
    mov     x14, #NODE_JSON_CONTRIBUTION_AND_PROOF
    cmp     x27, #API_TOPIC_CONTRIBUTION_AND_PROOF
    b.ne    12f
11: cbz     x23, 41f
    ldr     x10, [x24]                      /* a JsonCursor at the end of scratch */
    subs    x10, x10, #JSON_CURSOR_SIZE
    b.lo    71f
    str     x10, [x24]
    add     x4, x24, x10
    ldr     x10, [x21, #NodeAction_arg]
    ubfx    x15, x10, #16, #8
    sub     x10, x28, #NodeEvent_chunk      /* the text, in the event */
    and     x10, x10, #~7
    cmp     x10, #64
    b.lo    71f
    str     x10, [x25, #NodeEvent_chunk]
    add     x0, x25, #NodeEvent_chunk
    mov     x1, x27
    mov     x2, x14
    mov     x3, x23
    bl      lantern_api_op_event_text
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 55b
    b       41f
12: cmp     x27, #API_TOPIC_BLOB_SIDECAR    /* a sidecar topic: its fields from its bytes */
    ccmp    x27, #API_TOPIC_DATA_COLUMN_SIDECAR, #4, ne
    b.ne    8f
    cbz     x23, 41f
    ldr     x10, [x21, #NodeAction_arg]
    ubfx    x15, x10, #16, #8
    sub     x10, x28, #NodeEvent_chunk      /* the text, in the event */
    and     x10, x10, #~7
    cmp     x10, #64
    b.lo    71f
    str     x10, [x25, #NodeEvent_chunk]
    add     x0, x25, #NodeEvent_chunk
    mov     x1, x27
    mov     x2, x23
    mov     x3, x24
    bl      lantern_api_sidecar_event_text
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
    cbz     x0, 55b
41: mov     x9, #LANTERN_INVALID_ENCODING
    str     x9, [x25, #NodeEvent_result]
9:  ldr     x9, [sp, #L]
    str     x9, [x24]
    mov     x0, #LANTERN_OK
    LEAVE 32
8:  ldr     x9, [sp, #L]
    str     x9, [x24]
    mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 32
71: ldr     x9, [sp, #L]
    str     x9, [x24]
7:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION lantern_node_api_event_run

/* ---------------------------------------------------------------- Lookup (beacon-api.md, Common rules) */

/* L1: x0 = the NodeBlock index of the imported parent of the entry x0, or 2^64 - 1; x1 = its entry. Uses x9-x15. */
LOCAL_FUNCTION lantern_node_api_parent
    FRAME 0
    add     x0, x0, #NodeBlock_parent_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.eq    9f
    mov     x0, #-1
9:  UNFRAME 0
END_FUNCTION lantern_node_api_parent

/*
 * L1: the block of the chain at or below the slot x0: x0 = its NodeBlock index, x1 = its entry; or
 * x0 = 2^64 - 1 when the lowest block of the chain the node keeps, x1 (0 with no head), is above
 * the slot. Locals: L the slot, L+8 an entry.
 */
LOCAL_FUNCTION lantern_node_api_below
    FRAME 32
    str     x0, [sp, #16]
    add     x0, x19, #Node_head_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.ne    1f
    mov     x1, #0
    UNFRAME 32
1:  ldr     x9, [x1, #NodeBlock_slot]
    ldr     x10, [sp, #16]
    cmp     x9, x10
    b.ls    9f
    str     x1, [sp, #24]
    mov     x0, x1
    bl      lantern_node_api_parent
    cmn     x0, #1
    b.ne    1b
    ldr     x1, [sp, #24]
9:  UNFRAME 32
END_FUNCTION lantern_node_api_below

/* L1: x0 = 1 when the block entry x0 is on the chain, else 0. Locals: L the entry. */
LOCAL_FUNCTION lantern_node_api_on_chain
    FRAME 16
    str     x0, [sp, #16]
    ldr     x0, [x0, #NodeBlock_slot]
    bl      lantern_node_api_below
    cmn     x0, #1
    b.eq    8f
    ldr     x9, [sp, #16]
    cmp     x1, x9
    cset    x0, eq
    UNFRAME 16
8:  mov     x0, #0
    UNFRAME 16
END_FUNCTION lantern_node_api_on_chain

/* L1: x0 = 1 when the slot x0 is at most that of the block of the store's finalized root, else 0. Locals: x0. */
LOCAL_FUNCTION lantern_node_api_final_block
    FRAME 16
    str     x0, [sp, #16]
    bl      lantern_node_f_slot
    ldr     x9, [sp, #16]
    cmn     x0, #1
    b.eq    8f
    cmp     x9, x0
    cset    x0, ls
    UNFRAME 16
8:  mov     x0, #0
    UNFRAME 16
END_FUNCTION lantern_node_api_final_block

/*
 * L2: the block of the block_id of the ApiRoute x0 into the ApiView x1 (beacon-api.md, Common
 * rules): head_root, head_slot, canonical, head_finalized, is_optimistic, look_index, look_data,
 * and for a block the node keeps look_state and look_state_slot. x0 = 0, or 404 for none. x21 the
 * route, x22 the view, x25 the entry, x26 the slot. Locals: L the Db's slot.
 */
LOCAL_FUNCTION lantern_node_api_block
    ENTER 16
    mov     x21, x0
    mov     x22, x1
    mov     x9, #-1
    str     x9, [x22, #ApiView_look_index]
    str     xzr, [x22, #ApiView_look_data]
    str     xzr, [x22, #ApiView_look_state]
    str     xzr, [x22, #ApiView_look_copy]
    ldr     x9, [x21, #ApiRoute_id_kind]
    add     x0, x19, #Node_head_root        /* head */
    cmp     x9, #API_ID_HEAD
    b.eq    4f
    add     x0, x20, #(Store_finalized_checkpoint + 8)  /* finalized */
    cmp     x9, #API_ID_FINALIZED
    b.eq    4f
    cmp     x9, #API_ID_ROOT
    b.ne    3f
    add     x0, x21, #ApiRoute_id_root      /* a root: the node's imported block, else the Db's */
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    1f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.eq    5f
1:  ldr     x9, [x19, #Node_flags]
    tst     x9, #NODE_FLAG_DB
    b.eq    80f
    ldr     x0, [x19, #Node_db]
    add     x0, x19, x0
    add     x1, x21, #ApiRoute_id_root
    add     x2, sp, #L
    bl      lantern_db_find_root
    ldr     x26, [sp, #L]
    cmn     x26, #1
    b.eq    80f
    add     x0, x21, #ApiRoute_id_root
    b       6f
3:  mov     x26, #0                         /* genesis: the slot 0; a slot */
    cmp     x9, #API_ID_SLOT
    b.ne    31f
    ldr     x26, [x21, #ApiRoute_id_slot]
31: mov     x0, x26
    bl      lantern_node_api_below
    cmn     x0, #1
    b.eq    32f
    ldr     x9, [x1, #NodeBlock_slot]
    cmp     x9, x26
    b.ne    80f                             /* an empty slot, or past the head */
    b       5f
32: ldr     x9, [x19, #Node_flags]          /* below the chain's blocks the node keeps: the Db's */
    tst     x9, #NODE_FLAG_DB
    b.eq    80f
    mov     x0, x26
    bl      lantern_node_db_slot
    cbz     x0, 80f
    b       6f                              /* DbSlot_root is at 0 */
4:  bl      lantern_node_find_block                 /* head, finalized: the block of that root */
    cmn     x0, #1
    b.eq    80f
5:  mov     x25, x1                         /* a block the node keeps */
    str     x0, [x22, #ApiView_look_index]
    add     x0, x22, #ApiView_head_root
    bl      lantern_copy_root
    ldr     x26, [x25, #NodeBlock_slot]
    str     x26, [x22, #ApiView_head_slot]
    ldr     x9, [x25, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x22, #ApiView_is_optimistic]
    ldr     x9, [x25, #NodeBlock_state_id]
    str     x9, [x22, #ApiView_look_state]
    str     x26, [x22, #ApiView_look_state_slot]
    ldr     x0, [x25, #NodeBlock_data_id]
    cbnz    x0, 51f
    mov     x0, x25
    bl      lantern_node_api_db_ref
51: str     x0, [x22, #ApiView_look_data]
    mov     x0, x25
    bl      lantern_node_api_on_chain
    str     x0, [x22, #ApiView_canonical]
    cbz     x0, 52f
    mov     x0, x26
    bl      lantern_node_api_final_block
52: STQ     x0, x22, ApiView_head_finalized
    mov     x0, #0
    LEAVE 16
6:  mov     x1, x0                          /* a block of the Db: its root at x0, its slot x26 */
    add     x0, x22, #ApiView_head_root
    bl      lantern_copy_root
    str     x26, [x22, #ApiView_head_slot]
    str     xzr, [x22, #ApiView_is_optimistic]
    mov     x9, #1
    str     x9, [x22, #ApiView_canonical]
    mov     x0, x26
    bl      lantern_node_db_block
    str     x0, [x22, #ApiView_look_data]
    mov     x0, x26
    bl      lantern_node_api_final_block
    STQ     x0, x22, ApiView_head_finalized
    mov     x0, #0
    LEAVE 16
80: mov     x0, #404
    LEAVE 16
END_FUNCTION lantern_node_api_block

/*
 * L2: the state of the state_id of the ApiRoute x0 into the ApiView x1 (beacon-api.md, Common
 * rules): look_state, a state the node keeps, at look_state_slot; head_slot the slot it goes to;
 * head_finalized and is_optimistic. x0 = 0, or 404 for none; with look_replay 1 (which goes to 0)
 * a block at or below F's slot with no post-state comes from the replay (node.md): x0 = 1 while the
 * request waits for it. x21 the route, x22 the view, x25 the block's entry, x26 the slot, x27 the
 * checkpoint, then the base's slot. Locals: L look_replay.
 */
LOCAL_FUNCTION lantern_node_api_state
    ENTER 16
    mov     x21, x0
    mov     x22, x1
    LDQ     x9, x22, ApiView_look_replay
    str     x9, [sp, #L]
    STQ     xzr, x22, ApiView_look_replay
    str     xzr, [x22, #ApiView_look_state]
    str     xzr, [x22, #ApiView_look_copy]
    mov     x9, #-1
    str     x9, [x22, #ApiView_look_index]
    ldr     x9, [x21, #ApiRoute_id_kind]
    cmp     x9, #API_ID_HEAD
    b.ne    1f
    add     x0, x19, #Node_head_root        /* head: its post-state at its slot */
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    80f
    ldr     x26, [x1, #NodeBlock_slot]
    b       5f
1:  add     x27, x20, #Store_finalized_checkpoint
    cmp     x9, #API_ID_FINALIZED
    b.eq    2f
    add     x27, x20, #Store_justified_checkpoint
    cmp     x9, #API_ID_JUSTIFIED
    b.ne    3f
2:  ldr     x26, [x27]                      /* a checkpoint: at the first slot of its epoch */
    mov     x9, #SLOTS_PER_EPOCH
    mul     x26, x26, x9
    add     x0, x27, #8
    bl      lantern_node_find_block                 /* the optimistic status of its block */
    mov     x9, #0
    cmn     x0, #1
    b.eq    21f
    mov     x25, x1
    ldr     x9, [x25, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
21: str     x9, [x22, #ApiView_is_optimistic]
    ldr     x0, [x27]                       /* its NodeCheckpoint's state, else its block's post-state */
    add     x1, x27, #8
    bl      lantern_node_find_checkpoint
    cmn     x0, #1
    b.eq    22f
    ldr     x9, [x1, #NodeCheckpoint_state_id]
    cbz     x9, 22f
    str     x9, [x22, #ApiView_look_state]
    str     x26, [x22, #ApiView_look_state_slot]
    b       7f
22: add     x0, x27, #8
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    80f
    b       5f
3:  cmp     x9, #API_ID_ROOT                /* a state root: none in this version */
    b.eq    80f
    mov     x26, #0                         /* genesis: the slot 0; a slot, at most the store's */
    cmp     x9, #API_ID_SLOT
    b.ne    31f
    ldr     x26, [x21, #ApiRoute_id_slot]
31: mov     x0, x20
    bl      lantern_node_store_slot
    cmp     x26, x0
    b.hi    80f
    mov     x0, x26
    bl      lantern_node_api_below
    cmn     x0, #1
    b.eq    75f
5:  mov     x25, x1                         /* the block's post-state, again when the node let it go */
    ldr     x9, [x25, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x22, #ApiView_is_optimistic]
    ldr     x0, [x25, #NodeBlock_state_id]
    cbnz    x0, 6f
    bl      lantern_node_f_slot
    ldr     x9, [x25, #NodeBlock_slot]
    cmn     x0, #1
    b.eq    80f
    cmp     x9, x0
    b.ls    70f
    mov     x0, x25
    bl      lantern_node_rebuild
    cbz     x0, 80f
6:  str     x0, [x22, #ApiView_look_state]
    ldr     x9, [x25, #NodeBlock_slot]
    str     x9, [x22, #ApiView_look_state_slot]
7:  str     x26, [x22, #ApiView_head_slot]  /* finalized: at most the first slot of the finalized epoch */
    ldr     x9, [x20, #Store_finalized_checkpoint]
    mov     x10, #SLOTS_PER_EPOCH
    mul     x9, x9, x10
    cmp     x26, x9
    cset    x9, ls
    STQ     x9, x22, ApiView_head_finalized
    mov     x0, #0
    LEAVE 16
70: add     x0, x25, #NodeBlock_root        /* at or below F's slot: the replay */
    ldr     x1, [x25, #NodeBlock_slot]
    b       71f
75: ldr     x9, [x19, #Node_flags]          /* below the chain's lowest block: the Db's block at or below the slot */
    tst     x9, #NODE_FLAG_DB
    b.eq    80f
    LDQ     x27, x19, Node_base_slot
    mov     x25, x26
    cmp     x25, x27
    b.hs    76f
    LDQ     x9, x19, Node_archive_first     /* below the base's slot: from the lowest state record on */
    cmp     x25, x9
    b.lo    80f
78: mov     x0, x25
    bl      lantern_node_db_slot
    mov     x1, x25
    cbnz    x0, 71f
    cbz     x25, 80f
    sub     x25, x25, #1
    b       78b
76: cmp     x25, x27
    b.ls    77f
    mov     x0, x25
    bl      lantern_node_db_slot
    mov     x1, x25
    cbnz    x0, 71f                         /* its DbSlot: the root at 0 */
    sub     x25, x25, #1
    b       76b
77: mov     x0, #0                          /* none above the base's slot: the base state */
    mov     x1, x27
71: ldr     x9, [sp, #L]
    cbz     x9, 80f
    bl      lantern_node_replay_get
    cbz     x0, 80f
    cmp     x0, #1
    b.eq    79f
    str     x0, [x22, #ApiView_look_state]
    str     x1, [x22, #ApiView_look_state_slot]
    mov     x9, #1
    str     x9, [x22, #ApiView_look_copy]
    str     xzr, [x22, #ApiView_is_optimistic]
    b       7b
79: LEAVE 16
80: mov     x0, #404
    LEAVE 16
END_FUNCTION lantern_node_api_state

/*
 * L2: (root x0, or 0 for the base, slot x1) with the view x22: the post-state of the block of root
 * x0 at slot x1, at or below F's slot and at or above base_slot, by the replay (node.md): x0 = a
 * copy of it and x1 its slot; 1 when the request waits for the replay; 0 for none. x21 the root,
 * x25 the slot, x26 the state, x27 the copy.
 */
LOCAL_FUNCTION lantern_node_replay_get
    ENTER 0
    mov     x21, x0
    mov     x25, x1
    LDQ     x9, x19, Node_base_slot
    cmp     x25, x9
    b.hi    1f
    b.lo    6f
    ldr     x26, [x19, #Node_anchor_state_id]   /* the base's slot: the base state */
    b       5f
6:  LDQ     x9, x19, Node_archive_first     /* below it: from the lowest state record on */
    cmp     x25, x9
    b.lo    8f
1:  cbz     x21, 8f
    LDQ     x26, x19, Node_replay_state     /* the last replay's state, of that root */
    cbz     x26, 2f
    ADDQ    x9, x19, Node_replay_root
    NE32    x9, x21, 2f
5:  bl      lantern_node_new_id                     /* a copy for the answer */
    mov     x27, x0
    mov     x0, #NODE_ACT_STATE_COPY
    mov     x1, x26
    mov     x2, x27
    bl      lantern_node_ids
    mov     x0, x27
    mov     x1, x25
    LEAVE 0
2:  LDQ     x9, x19, Node_replay_copy       /* a replay in flight: the request waits */
    cbnz    x9, 7f
    LDQ     x1, x19, Node_replay_state      /* else one starts, for this block */
    cbz     x1, 3f
    mov     x0, #NODE_ACT_STATE_FREE
    mov     x2, #0
    bl      lantern_node_ids
    STQ     xzr, x19, Node_replay_state
3:  ADDQ    x0, x19, Node_replay_root
    COPY32  x0, x21
    STQ     x25, x19, Node_replay_slot
    bl      lantern_node_new_id
    STQ     x0, x19, Node_replay_copy
    mov     x2, x0
    mov     x0, #NODE_ACT_STATE_COPY
    ldr     x1, [x19, #Node_anchor_state_id]
    bl      lantern_node_ids
    LDQ     x9, x19, Node_base_slot
    STQ     x9, x19, Node_replay_copy_slot
    add     x9, x9, #1
    STQ     x9, x19, Node_replay_next
    mov     x0, x25                         /* a nearer base among the state records: the copy loads it */
    bl      lantern_node_archive_base
    cmn     x0, #1
    b.eq    7f
    STQ     x0, x19, Node_replay_copy_slot
    add     x9, x0, #1
    STQ     x9, x19, Node_replay_next
    mov     x9, #1
    STQ     x9, x19, Node_replay_loading
    lsr     x9, x0, #DB_SEGMENT_SHIFT       /* the record's NODE_DB_REF, and with a diff the full state's at 0 */
    lsl     x9, x9, #NODE_DB_SEGMENT_SHIFT
    orr     x9, x9, #NODE_DB_REF
    orr     x9, x9, #NODE_DB_STATES
    sub     x3, x1, #1
    orr     x3, x3, x9
    mov     x2, #0
    cmp     x1, #1
    csel    x2, x2, x9, eq
    mov     x0, #NODE_WORK_ARCHIVE_LOAD
    LDQ     x1, x19, Node_replay_copy
    mov     x4, #0
    mov     x5, #0
    bl      lantern_node_work
7:  mov     x0, #1
    LEAVE 0
8:  mov     x0, #0
    LEAVE 0
END_FUNCTION lantern_node_replay_get

/*
 * L2: the state of the ApiView x0 at its slot (node.md, NODE_EV_API): when head_slot is past
 * look_state_slot, a STATE_COPY of look_state, the copy across the fork boundaries to head_slot,
 * and a SLOTS work of it to head_slot when it is below it; look_state is the copy, look_copy 1.
 * x21 the view, x22 the copy, x25 the copy's slot.
 */
LOCAL_FUNCTION lantern_node_api_advance
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #ApiView_look_state_slot]
    ldr     x10, [x21, #ApiView_head_slot]
    cmp     x10, x9
    b.ls    9f
    bl      lantern_node_new_id
    mov     x22, x0
    mov     x2, x0
    mov     x0, #NODE_ACT_STATE_COPY
    ldr     x1, [x21, #ApiView_look_state]
    bl      lantern_node_ids
    mov     x0, x22
    ldr     x1, [x21, #ApiView_look_state]
    ldr     x2, [x21, #ApiView_look_state_slot]
    ldr     x3, [x21, #ApiView_head_slot]
    bl      lantern_node_cross
    mov     x22, x0
    ldr     x25, [x21, #ApiView_look_state_slot]    /* the copy's slot: the first of the target's fork, when it crossed one */
    mov     x0, x25
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x26, x0
    ldr     x0, [x21, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    cmp     x0, x26
    b.ls    1f
    add     x9, x19, #Node_config
    add     x9, x9, x0, lsl #4
    ldr     x9, [x9]
    mov     x10, #SLOTS_PER_EPOCH
    mul     x9, x9, x10
    cmp     x9, x25
    csel    x25, x9, x25, hi
1:  ldr     x5, [x21, #ApiView_head_slot]
    cmp     x5, x25
    b.ls    2f
    mov     x0, #NODE_WORK_SLOTS
    mov     x1, x22
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    bl      lantern_node_work
2:  str     x22, [x21, #ApiView_look_state]
    mov     x9, #1
    str     x9, [x21, #ApiView_look_copy]
9:  LEAVE 0
END_FUNCTION lantern_node_api_advance

/*
 * L1: a NODE_WORK_API_ENCODE of the operation x0 for the connection x1 with the answer flags x2,
 * from the lookup in the ApiView x3 (node.md, NODE_EV_API); then a STATE_FREE of the state when it
 * is a copy. x0 = 0, or 404 for a header with neither bytes nor a post-state. Locals: L the view.
 */
LOCAL_FUNCTION lantern_node_api_encode
    FRAME 16
    str     x3, [sp, #16]
    ldr     x9, [x3, #ApiView_canonical]
    LDQ     x10, x3, ApiView_head_finalized
    ldr     x11, [x3, #ApiView_is_optimistic]
    orr     x9, x9, x10, lsl #1
    orr     x9, x9, x11, lsl #2
    LDQ     x10, x3, ApiView_next_period
    orr     x9, x9, x10, lsl #3             /* API_VALUE_NEXT_PERIOD */
    orr     x5, x0, x2, lsl #8
    mov     x4, x1
    cmp     x0, #API_OP_GET_SPEC            /* getSpec, getDebugChainHeadsV2: no state, no bytes, no values */
    mov     x12, #API_OP_GET_DEBUG_CHAIN_HEADS_V2
    ccmp    x0, x12, #4, ne
    mov     x12, #API_OP_GET_DEBUG_FORK_CHOICE
    ccmp    x0, x12, #4, ne
    b.ne    1f
    mov     x1, #0
    mov     x3, #0
    b       3f
1:  orr     x5, x5, x9, lsl #16
    cmp     x0, #API_OP_GET_BLOCK_HEADER
    b.ne    2f
    ldr     x9, [x3, #ApiView_look_index]   /* getBlockHeader: the block's index + 1, its bytes or post-state */
    add     x9, x9, #1
    orr     x5, x5, x9, lsl #24
    mov     x1, #0
    ldr     x3, [x3, #ApiView_look_data]
    cbnz    x3, 3f
    ldr     x9, [sp, #16]
    ldr     x1, [x9, #ApiView_look_state]
    cbnz    x1, 3f
    mov     x0, #404
    UNFRAME 16
2:  ldr     x9, [x3, #ApiView_head_slot]    /* the others: the state at its slot; getStateValidator its ids */
    orr     x5, x5, x9, lsl #24
    ldr     x1, [x3, #ApiView_look_state]
    mov     x10, #API_OP_PRODUCE_ATTESTATION_DATA
    mov     x11, #API_OP_GET_ATTESTER_DUTIES
    mov     x12, #API_OP_GET_SYNC_COMMITTEE_DUTIES
    cmp     x0, #API_OP_GET_STATE_VALIDATOR
    ccmp    x0, x10, #4, ne
    ccmp    x0, x11, #4, ne
    ccmp    x0, x12, #4, ne
    ccmp    x0, #API_OP_GET_STATE_RANDAO, #4, ne
    ccmp    x0, #API_OP_GET_EPOCH_SYNC_COMMITTEES, #4, ne
    mov     x13, #API_OP_GET_LIVENESS
    ccmp    x0, x13, #4, ne
    ldr     x9, [x3, #ApiView_look_data]
    csel    x3, x9, xzr, eq
3:  mov     x0, #NODE_WORK_API_ENCODE
    mov     x2, #0
    bl      lantern_node_work
    ldr     x9, [sp, #16]                   /* a copy goes after the work */
    ldr     x10, [x9, #ApiView_look_copy]
    cbz     x10, 9f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x9, #ApiView_look_state]
    mov     x2, #0
    bl      lantern_node_ids
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION lantern_node_api_encode

/*
 * L2: (connection x0, route x1, answer flags x2, wait x3) -> x0: a state_id of a root (node.md,
 * NODE_EV_API): a NodeApi entry with API_STREAM_LOOKUP and a NODE_WORK_API_LOOKUP with the head's
 * post-state; with wait 1, a state_id of a slot whose state waits for the replay: the entry with
 * API_STREAM_REPLAY and the slot at API_REPLAY_SLOT of its cursor, and no work. 0, or 404 with no
 * head post-state. x21 the route, x25 the flags, x26 wait, x27 the connection. Locals: L the
 * entry's index, L+8 the entry.
 */
LOCAL_FUNCTION lantern_node_api_lookup
    ENTER 16
    mov     x27, x0
    mov     x21, x1
    mov     x26, x3
    orr     x25, x2, #API_STREAM_LOOKUP
    orr     x25, x25, #API_STREAM_BUSY
    cbz     x26, 3f
    orr     x25, x25, #API_STREAM_REPLAY
3:  ldr     x9, [x21, #ApiRoute_response]
    cmp     x9, #API_TYPE_SSZ
    b.ne    1f
    orr     x25, x25, #API_STREAM_SSZ
1:  add     x0, x19, #Node_head_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    80f
    ldr     x9, [x1, #NodeBlock_state_id]
    cbz     x9, 80f
    bl      lantern_node_api_new
    stp     x0, x1, [sp, #L]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x1, [sp, #(L + 8)]
    str     x27, [x1, #NodeApi_connection]
    ldr     x9, [x21, #ApiRoute_op]
    str     x9, [x1, #NodeApi_op]
    str     x25, [x1, #NodeApi_flags]
    add     x0, x1, #NodeApi_cursor
    add     x1, x21, #ApiRoute_id_root
    bl      lantern_copy_root
    ldr     x1, [sp, #(L + 8)]              /* statuses, validator_id, epoch, slot, index and present; the validator operations' ids */
    ldr     x9, [x21, #ApiRoute_statuses]
    str     x9, [x1, #(NodeApi_cursor + 32)]
    add     x11, x1, #(NodeApi_cursor + 104)
    ldr     x9, [x21, #ApiRoute_epoch]
    ldr     x10, [x21, #ApiRoute_slot]
    stp     x9, x10, [x11]
    ldr     x9, [x21, #ApiRoute_index]
    ldr     x10, [x21, #ApiRoute_present]
    stp     x9, x10, [x11, #16]
    add     x0, x1, #(NodeApi_cursor + 40)
    add     x1, x21, #ApiRoute_validator
    mov     x2, #64
    bl      lantern_copy
    ldr     x9, [x21, #ApiRoute_op]
    cmp     x9, #API_OP_GET_ATTESTER_DUTIES /* and getAttesterDuties' */
    b.eq    5f
    sub     x9, x9, #API_OP_GET_STATE_VALIDATORS
    cmp     x9, #(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS)
    b.hi    2f
5:  mov     x0, x21
    bl      lantern_node_api_ids
    ldr     x1, [sp, #(L + 8)]
    str     x0, [x1, #NodeApi_data]
    cbz     x0, 2f
    ldr     x9, [x1, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_OWN
    str     x9, [x1, #NodeApi_flags]
2:  cbz     x26, 4f                         /* the replay's wait: the slot of the state_id, no work */
    ldr     x1, [sp, #(L + 8)]
    ldr     x9, [x21, #ApiRoute_id_kind]
    ldr     x10, [x21, #ApiRoute_id_slot]
    cmp     x9, #API_ID_SLOT
    csel    x10, x10, xzr, eq
    str     x10, [x1, #(NodeApi_cursor + API_REPLAY_SLOT)]
    mov     x0, #0
    LEAVE 16
4:  add     x0, x19, #Node_head_root
    bl      lantern_node_find_block
    ldr     x1, [x1, #NodeBlock_state_id]
    mov     x0, #NODE_WORK_API_LOOKUP
    mov     x2, #0
    mov     x3, #0
    mov     x4, x27
    ldr     x5, [sp, #L]
    bl      lantern_node_work
    mov     x0, #0
    LEAVE 16
80: mov     x0, #404
    LEAVE 16
END_FUNCTION lantern_node_api_lookup

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_LOOKUP (node.md, lantern_node_step): its entry
 * goes on with the slot found (lantern_node_api_rerun), the replay allowed. x21 the event, x22 the entry.
 */
LOCAL_FUNCTION lantern_node_api_lookup_done
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_arg]
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    99f
    mov     x12, #NodeApi__mem
    madd    x22, x9, x12, x10
    ldr     x9, [x22, #NodeApi_connection]
    cbz     x9, 99f
    ldr     x10, [x21, #NodeAction_target]
    cmp     x9, x10
    b.ne    99f
    ldr     x9, [x22, #NodeApi_flags]
    tst     x9, #API_STREAM_LOOKUP
    b.eq    99f
    mov     x0, x22
    ldr     x1, [x21, #NodeEvent_index]
    mov     x2, #1
    bl      lantern_node_api_rerun
99: LEAVE 0
END_FUNCTION lantern_node_api_lookup_done

/*
 * L2: (entry x0, slot x1, replay x2): a lookup entry goes on with the slot of its state_id (node.md,
 * NODE_WORK_API_LOOKUP done, and the replay): it ends, then the answer of its operation for the
 * state_id of that slot, or 404 for 2^64 - 1; with replay 1 a state that needs the replay keeps the
 * entry waiting (API_STREAM_REPLAY, the slot at API_REPLAY_SLOT of its cursor). With
 * API_STREAM_GONE it ends. x19 the node, x20 the store, x23 the scratch, x24 the actions. x22 the
 * entry, x25 its flags, x26 the view, x27 the connection, x28 the operation. Locals: L the
 * scratch's size, L+8 the route, L+16 the ids, L+24 statuses, L+32 validator (64), L+96 epoch,
 * slot, index and present, L+128 the slot, L+136 replay, then the status.
 */
LOCAL_FUNCTION lantern_node_api_rerun
    ENTER 144
    mov     x22, x0
    str     x1, [sp, #(L + 128)]
    str     x2, [sp, #(L + 136)]
    ldr     x27, [x22, #NodeApi_connection]
    ldr     x25, [x22, #NodeApi_flags]
    ldr     x28, [x22, #NodeApi_op]
    tbz     x25, #5, 1f                     /* API_STREAM_GONE: the entry ends, its ids with it */
    mov     x0, x22
    bl      lantern_node_api_end
    b       99f
1:  ldr     x9, [x22, #NodeApi_data]        /* its ids, statuses and validator_id go to the answer */
    str     x9, [sp, #(L + 16)]
    ldr     x9, [x22, #(NodeApi_cursor + 32)]
    str     x9, [sp, #(L + 24)]
    add     x0, sp, #(L + 32)
    add     x1, x22, #(NodeApi_cursor + 40)
    mov     x2, #64
    bl      lantern_copy
    add     x0, sp, #(L + 96)
    add     x1, x22, #(NodeApi_cursor + 104)
    mov     x2, #32
    bl      lantern_copy
    ldr     x9, [x23]                       /* the ApiView, then an ApiRoute, at the end of scratch */
    str     x9, [sp, #L]
    MOVQ    x10, ApiView__size + API_ROUTE_FIXED
    sub     x9, x9, x10
    str     x9, [x23]
    add     x26, x23, x9
    mov     x0, x26
    bl      lantern_node_api_view
    MOVQ    x9, ApiView__size
    add     x0, x26, x9
    str     x0, [sp, #(L + 8)]
    mov     x1, #API_ROUTE_FIXED
    bl      lantern_zero
    ldr     x0, [sp, #(L + 8)]
    mov     x9, #API_ROUTE_FIXED
    str     x9, [x0]
    str     x28, [x0, #ApiRoute_op]
    tst     x25, #API_STREAM_SSZ
    mov     x9, #API_TYPE_SSZ
    mov     x10, #API_TYPE_JSON
    csel    x9, x9, x10, ne
    str     x9, [x0, #ApiRoute_response]
    ldr     x9, [sp, #(L + 24)]
    str     x9, [x0, #ApiRoute_statuses]
    add     x0, x0, #ApiRoute_validator
    add     x1, sp, #(L + 32)
    mov     x2, #64
    bl      lantern_copy
    ldr     x0, [sp, #(L + 8)]
    ldp     x9, x10, [sp, #(L + 96)]
    str     x9, [x0, #ApiRoute_epoch]
    str     x10, [x0, #ApiRoute_slot]
    ldp     x9, x10, [sp, #(L + 112)]
    str     x9, [x0, #ApiRoute_index]
    str     x10, [x0, #ApiRoute_present]
    mov     x9, #API_ID_SLOT
    str     x9, [x0, #ApiRoute_id_kind]
    ldr     x9, [sp, #(L + 128)]
    str     x9, [x0, #ApiRoute_id_slot]
    mov     x2, #404
    cmn     x9, #1
    b.eq    70f
    ldr     x9, [sp, #(L + 136)]
    STQ     x9, x26, ApiView_look_replay
    mov     x1, x26
    bl      lantern_node_api_state
    mov     x2, x0
    cmp     x0, #1
    b.ne    70f
    ldr     x9, [x22, #NodeApi_flags]       /* the replay: the entry waits */
    orr     x9, x9, #API_STREAM_REPLAY
    str     x9, [x22, #NodeApi_flags]
    ldr     x9, [sp, #(L + 128)]
    str     x9, [x22, #(NodeApi_cursor + API_REPLAY_SLOT)]
    b       90f
70: cmp     x28, #API_OP_GET_ATTESTER_DUTIES    /* getAttesterDuties with no state: 400 */
    b.ne    707f
    cmp     x2, #404
    mov     x9, #400
    csel    x2, x9, x2, eq
707: str    x2, [sp, #(L + 136)]
    and     x9, x25, #~API_STREAM_OWN       /* the entry ends; it owns no bytes */
    str     x9, [x22, #NodeApi_flags]
    mov     x0, x22
    bl      lantern_node_api_end
    ldr     x2, [sp, #(L + 136)]
    cbnz    x2, 80f
    ldr     x9, [sp, #(L + 16)]             /* the ids go to the answer */
    str     x9, [x26, #ApiView_look_data]
    str     xzr, [sp, #(L + 16)]
    mov     x0, x27
    ldr     x1, [sp, #(L + 8)]
    and     x2, x25, #(API_STREAM_CLOSE | API_STREAM_HTTP10)
    mov     x3, x26
    bl      lantern_node_api_state_answer
    mov     x2, x0
    cbz     x0, 90f
80: ldr     x1, [sp, #(L + 16)]             /* ids no answer took: they go */
    cbz     x1, 82f
    str     x2, [sp, #(L + 24)]
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
    ldr     x2, [sp, #(L + 24)]
82: mov     x0, x27                         /* an error: with close, or keep-alive for HTTP/1.0 */
    mov     x1, #0
    mov     x3, #API_BODY_ERROR
    and     x4, x25, #API_R_CLOSE
    cbnz    x4, 81f
    tst     x25, #API_STREAM_HTTP10
    mov     x9, #API_R_KEEP
    csel    x4, x9, xzr, ne
81: bl      lantern_node_api_send
90: ldr     x9, [sp, #L]
    str     x9, [x23]
99: LEAVE 144
END_FUNCTION lantern_node_api_rerun

/*
 * L2: (data x0, slot x1): the copy of the replay in flight crosses the fork boundaries to the slot
 * x1, then a NODE_WORK_REPLAY of it with the block's bytes x0 (node.md, the replay). x21 the data,
 * x25 the slot.
 */
LOCAL_FUNCTION lantern_node_replay_block
    ENTER 0
    mov     x21, x0
    mov     x25, x1
    LDQ     x0, x19, Node_replay_copy
    ldr     x1, [x19, #Node_anchor_state_id]
    LDQ     x2, x19, Node_replay_copy_slot
    mov     x3, x25
    bl      lantern_node_cross
    STQ     x0, x19, Node_replay_copy
    STQ     x25, x19, Node_replay_copy_slot
    mov     x1, x0
    mov     x0, #NODE_WORK_REPLAY
    mov     x2, #0
    mov     x3, x21
    mov     x4, #0
    mov     x5, #0
    bl      lantern_node_work
    LEAVE 0
END_FUNCTION lantern_node_replay_block

/*
 * L2: the replay in flight queues its next blocks (node.md, the replay): at most NODE_REPLAY_CHUNK,
 * the first always and the others while the actions have room for 1024 bytes more; the Db's blocks
 * below db_next_slot, then the NodeBlock path from replay_root, a list at the end of scratch. Once
 * it is queued whole, replay_state takes the copy and the entries that wait run again; a block it
 * cannot find ends it, and they run again with no replay. x21 an entry, x22 the entries left, x25
 * the next slot, x26 the block's slot, x27 the blocks queued, x28 a block's data, then the path's
 * count. Locals: L the scratch's size, L+8 the path list, L+16 replay.
 */
LOCAL_FUNCTION lantern_node_replay_due
    ENTER 32
    LDQ     x9, x19, Node_replay_copy
    cbz     x9, 99f
    LDQ     x25, x19, Node_replay_next
    LDQ     x26, x19, Node_replay_slot
    mov     x27, #0
    ldr     x9, [x23]
    str     x9, [sp, #L]
    LDQ     x9, x19, Node_replay_loading    /* a load out: later; a failed one: no replay */
    cbz     x9, 1f
    cmp     x9, #2
    b.ne    99f
    STQ     xzr, x19, Node_replay_loading
    b       60f
1:  cmp     x25, x26
    b.hi    50f
    ldr     x9, [x19, #Node_flags]          /* the Db's blocks, below db_next_slot */
    tst     x9, #NODE_FLAG_DB
    b.eq    10f
    LDQ     x9, x19, Node_db_next_slot
    cmp     x25, x9
    b.hs    10f
    mov     x0, x25
    bl      lantern_node_db_block
    cbz     x0, 3f
    mov     x28, x0
    cmp     x27, #NODE_REPLAY_CHUNK
    b.hs    40f
    cbz     x27, 2f
    mov     x0, #1024
    bl      lantern_node_room
    cbz     x0, 40f
2:  mov     x0, x28
    mov     x1, x25
    bl      lantern_node_replay_block
    add     x27, x27, #1
3:  add     x25, x25, #1
    b       1b
10: ADDQ    x0, x19, Node_replay_root       /* the NodeBlock path from the replay's block, down to the next slot */
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    60f
    ldr     x9, [x23]
    ldr     x10, [x19, #(Node_blocks + 8)]
    lsl     x10, x10, #3
    subs    x11, x9, x10
    b.lo    40f
    str     x11, [x23]
    add     x9, x23, x11
    str     x9, [sp, #(L + 8)]
    mov     x28, #0
    mov     x0, x1
11: ldr     x9, [x0, #NodeBlock_slot]
    cmp     x9, x25
    b.lo    14f
    ldr     x10, [x0, #NodeBlock_data_id]   /* a block of the path with no bytes: none */
    cbz     x10, 60f
    ldr     x10, [x19, #(Node_blocks + 8)]
    cmp     x28, x10
    b.hs    60f
    ldr     x10, [sp, #(L + 8)]
    str     x0, [x10, x28, lsl #3]
    add     x28, x28, #1
    add     x0, x0, #NodeBlock_parent_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    14f
    mov     x0, x1
    b       11b
14: cbz     x28, 15f                        /* from the lowest */
    cmp     x27, #NODE_REPLAY_CHUNK
    b.hs    40f
    cbz     x27, 16f
    mov     x0, #1024
    bl      lantern_node_room
    cbz     x0, 40f
16: sub     x28, x28, #1
    ldr     x10, [sp, #(L + 8)]
    ldr     x9, [x10, x28, lsl #3]
    ldr     x0, [x9, #NodeBlock_data_id]
    ldr     x1, [x9, #NodeBlock_slot]
    add     x25, x1, #1
    bl      lantern_node_replay_block
    add     x27, x27, #1
    b       14b
15: add     x25, x26, #1                    /* the path's last: the replay's block */
50: LDQ     x9, x19, Node_replay_copy       /* queued whole: its state */
    STQ     x9, x19, Node_replay_state
    STQ     xzr, x19, Node_replay_copy
    STQ     x25, x19, Node_replay_next
    mov     x9, #1
    b       70f
40: STQ     x25, x19, Node_replay_next      /* the rest in a later step */
    b       90f
60: LDQ     x1, x19, Node_replay_copy       /* a block it cannot find: no replay */
    mov     x0, #NODE_ACT_STATE_FREE
    mov     x2, #0
    bl      lantern_node_ids
    STQ     xzr, x19, Node_replay_copy
    ADDQ    x0, x19, Node_replay_root
    mov     x1, #32
    bl      lantern_zero
    mov     x9, #0
70: str     x9, [sp, #(L + 16)]             /* the entries that wait run again */
    ldr     x9, [sp, #L]
    str     x9, [x23]
    PART    x21, x22, x19, Node_api
71: cbz     x22, 99f
    ldr     x9, [x21, #NodeApi_connection]
    cbz     x9, 72f
    ldr     x9, [x21, #NodeApi_flags]
    tst     x9, #API_STREAM_REPLAY
    b.eq    72f
    and     x9, x9, #~API_STREAM_REPLAY
    str     x9, [x21, #NodeApi_flags]
    mov     x0, x21
    ldr     x1, [x21, #(NodeApi_cursor + API_REPLAY_SLOT)]
    ldr     x2, [sp, #(L + 16)]
    bl      lantern_node_api_rerun
72: add     x21, x21, #NodeApi__mem
    sub     x22, x22, #1
    b       71b
90: ldr     x9, [sp, #L]
    str     x9, [x23]
99: LEAVE 32
END_FUNCTION lantern_node_replay_due

/*
 * (node, work, state_a, scratch, event) -> status: a NODE_WORK_API_LOOKUP of lantern_node_run
 * (node.md): at NodeEvent_index of the event, the slot whose state on the chain of state_a has the
 * root of the NodeApi entry at the work's arg, or 2^64 - 1. x19 the node, x21 the work, x22 the
 * state, x23 the event, x24 the root, x25 the slot, x26 the lowest slot.
 */
LOCAL_FUNCTION lantern_node_api_lookup_run
    ENTER 0
    mov     x19, x0
    mov     x21, x1
    mov     x22, x2
    mov     x23, x4
    mov     x9, #-1
    str     x9, [x23, #NodeEvent_index]
    cbz     x22, 98f
    ldr     x9, [x21, #NodeAction_arg]
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    90f
    mov     x12, #NodeApi__mem
    madd    x10, x9, x12, x10
    ldr     x11, [x10, #NodeApi_flags]
    tst     x11, #API_STREAM_LOOKUP
    b.eq    90f
    add     x24, x10, #NodeApi_cursor
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* the state's own root */
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    mov     x0, x22
    LDQ     x1, x19, Node_config + CONFIG_STATE_CACHE
    mov     x2, x3
    add     x3, x23, #NodeEvent_root
    FORK_CALL state_root
    cbnz    x0, 97f
    ldr     x25, [x22, #NODE_STATE_SLOT]
    add     x0, x23, #NodeEvent_root
    mov     x1, x24
    bl      lantern_node_api_same_root
    cbnz    x0, 80f
    subs    x26, x25, #SLOTS_PER_HISTORICAL_ROOT    /* then its state_roots, from the slot below it down */
    csel    x26, xzr, x26, lo
1:  cmp     x25, x26
    b.ls    90f
    sub     x25, x25, #1
    and     x9, x25, #(SLOTS_PER_HISTORICAL_ROOT - 1)
    ADDQ    x0, x22, NODE_STATE_STATE_ROOTS
    add     x0, x0, x9, lsl #5
    mov     x1, x24
    bl      lantern_node_api_same_root
    cbz     x0, 1b
80: str     x25, [x23, #NodeEvent_index]
90: mov     x0, #LANTERN_OK
    LEAVE 0
97: cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    96f
    mov     x9, #LANTERN_INVALID_ENCODING   /* a state lantern_state_root does not take */
    str     x9, [x23, #NodeEvent_result]
    b       90f
96: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
98: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 0
END_FUNCTION lantern_node_api_lookup_run

/* L0: x0 = 1 when the 32 bytes at x0 and x1 are the same, else 0. Uses x9-x12. */
LOCAL_FUNCTION lantern_node_api_same_root
    UNWIND_END_PROLOGUE
    ldp     x9, x10, [x0]
    ldp     x11, x12, [x1]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    8f
    ldp     x9, x10, [x0, #16]
    ldp     x11, x12, [x1, #16]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    cset    x0, eq
    ret
8:  mov     x0, #0
    ret
END_FUNCTION lantern_node_api_same_root

/* ---------------------------------------------------------------- Streams (node.md, NodeApi) */

/* L0: x0 = the free NodeApi entries of the node x19: the capacity past the count, and the free ones below it. Uses x9-x12, x16. */
LOCAL_FUNCTION lantern_node_api_free
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_api
    LDQ     x11, x19, Node_pool
    LDQ     x12, x19, Node_api
    sub     x11, x11, x12
    mov     x12, #NodeApi__mem
    udiv    x0, x11, x12
    sub     x0, x0, x10
1:  cbz     x10, 9f
    ldr     x11, [x9, #NodeApi_connection]
    cmp     x11, #0
    cinc    x0, x0, eq
    add     x9, x9, #NodeApi__mem
    sub     x10, x10, #1
    b       1b
9:  ret
END_FUNCTION lantern_node_api_free

/* L0: x0 = the index of the NodeApi entry of the connection x0, or 2^64 - 1; x1 = the entry. Uses x9-x12, x16. */
LOCAL_FUNCTION lantern_node_api_find
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_api
    mov     x11, #0
    cbz     x0, 3f
1:  cmp     x11, x10
    b.hs    3f
    ldr     x12, [x9, #NodeApi_connection]
    cmp     x12, x0
    b.eq    4f
    add     x9, x9, #NodeApi__mem
    add     x11, x11, #1
    b       1b
3:  mov     x0, #-1
    ret
4:  mov     x0, x11
    mov     x1, x9
    ret
END_FUNCTION lantern_node_api_find

/*
 * L2: (connection x0, route x1, flags x2, view x3) -> x0: produceBlockV3 (node.md, Block
 * production): a NodeApi entry in NODE_PRODUCE_STATE that owns the state of the view, a copy at
 * the slot, with the request in its cursor, and a PRODUCE_CHECK work of it; 0 once it started,
 * else the status of the error to answer. x21 the entry, x22 its index, x25 the route, x26 the
 * view, x27 the connection, x28 the flags.
 */
LOCAL_FUNCTION lantern_node_api_produce
    ENTER 0
    mov     x27, x0
    mov     x25, x1
    mov     x28, x2
    mov     x26, x3
    ldr     x9, [x25, #ApiRoute_response]   /* SSZ, else JSON */
    cmp     x9, #API_TYPE_SSZ
    b.ne    1f
    orr     x28, x28, #API_STREAM_SSZ
1:  ldr     x9, [x26, #ApiView_look_copy]   /* the state: a copy at the slot; busy with its check */
    cbz     x9, 8f
    orr     x28, x28, #API_STREAM_OWN_STATE
    orr     x28, x28, #API_STREAM_BUSY
    bl      lantern_node_api_new
    mov     x22, x0
    mov     x21, x1
    mov     x0, x21
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    str     x27, [x21, #NodeApi_connection]
    mov     x9, #API_OP_PRODUCE_BLOCK_V3
    str     x9, [x21, #NodeApi_op]
    str     x28, [x21, #NodeApi_flags]
    ldr     x9, [x26, #ApiView_look_state]
    str     x9, [x21, #NodeApi_state]
    ldr     x0, [x25, #ApiRoute_slot]
    str     x0, [x21, #NodeApi_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    str     x0, [x21, #NodeApi_fork]
    mov     x9, #NODE_PRODUCE_STATE
    str     x9, [x21, #NodeApi_member]
    add     x0, x21, #NodeApi_cursor        /* the request: randao_reveal, graffiti, the skip flag */
    add     x1, x25, #ApiRoute_randao_reveal
    mov     x2, #96
    bl      lantern_copy
    ldr     x9, [x25, #ApiRoute_present]
    tbz     x9, #API_PARAM_GRAFFITI, 2f
    add     x0, x21, #(NodeApi_cursor + 96)
    add     x1, x25, #ApiRoute_graffiti
    bl      lantern_copy_root
2:  ldr     x9, [x25, #ApiRoute_present]
    ubfx    x9, x9, #API_PARAM_SKIP_RANDAO_VERIFICATION, #1
    str     x9, [x21, #(NodeApi_cursor + 128)]
    mov     x9, #100                        /* builder_boost_factor: 100 without it */
    ldr     x10, [x25, #ApiRoute_present]
    tbz     x10, #API_PARAM_BUILDER_BOOST_FACTOR, 3f
    ldr     x9, [x25, #ApiRoute_builder_boost_factor]
3:  str     x9, [x21, #(NodeApi_cursor + PRODUCE_BOOST)]
    mov     x0, #NODE_WORK_PRODUCE_CHECK
    ldr     x1, [x21, #NodeApi_state]
    mov     x2, #0
    mov     x3, #0
    mov     x4, x22
    mov     x5, #0
    bl      lantern_node_work
    mov     x0, #0
    LEAVE 0
8:  mov     x0, #500
    LEAVE 0
END_FUNCTION lantern_node_api_produce

/*
 * L2: the NODE_EV_WORK_DONE x0 of a work of block production (node.md, Block production): the
 * produceBlockV3 entry at its target goes on, or answers its error. x21 the event, x22 the entry,
 * x25 the result.
 */
LOCAL_FUNCTION lantern_node_produce_done
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_target]
    PART    x22, x10, x19, Node_api
    cmp     x9, x10
    b.hs    9f
    mov     x11, #NodeApi__mem
    madd    x22, x9, x11, x22
    ldr     x9, [x22, #NodeApi_connection]  /* an entry still there */
    cbz     x9, 9f
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3
    b.ne    9f
    ldr     x25, [x21, #NodeEvent_result]
    ldr     x9, [x22, #NodeApi_flags]       /* its work is done */
    and     x9, x9, #~API_STREAM_BUSY
    str     x9, [x22, #NodeApi_flags]
    ldr     x9, [x21, #NodeAction_work_kind]
    cmp     x9, #NODE_WORK_PRODUCE_FOLD     /* a fold: the pool entry's bytes, when they left the pool meanwhile */
    b.ne    2f
    ldr     x9, [x22, #NodeApi_flags]
    tbz     x9, #16, 1f                     /* API_STREAM_PRODUCE_OWN */
    and     x9, x9, #~API_STREAM_PRODUCE_OWN
    str     x9, [x22, #NodeApi_flags]
    ldr     x1, [x22, #NodeApi_root]
    str     xzr, [x22, #NodeApi_root]
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
1:  str     xzr, [x22, #NodeApi_root]
2:  ldr     x9, [x22, #NodeApi_flags]       /* the connection closed meanwhile: the entry ends */
    tbz     x9, #5, 3f                      /* API_STREAM_GONE */
    mov     x0, x22
    bl      lantern_node_produce_release
    mov     x0, x22
    bl      lantern_node_api_end
    LEAVE 0
3:  ldr     x9, [x21, #NodeAction_work_kind]
    cmp     x9, #NODE_WORK_PRODUCE_CHECK
    b.ne    20f
    mov     x1, #400                        /* the check: 400 for the reveal, 500 for another */
    cmp     x25, #LANTERN_INVALID_RANDAO_REVEAL
    b.eq    8f
    mov     x1, #500
    cbnz    x25, 8f
    ldr     x0, [x22, #NodeApi_slot]        /* from bellatrix with a head of a payload: the engine's payload first */
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    cmp     x0, #FORK_BELLATRIX
    b.lo    10f
    add     x0, x19, #Node_head_root
    bl      lantern_node_store_find
    cmn     x0, #1
    b.eq    10f
    ldp     x9, x10, [x1, #BlockNode_block_hash]
    ldp     x11, x12, [x1, #(BlockNode_block_hash + 16)]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbz     x9, 10f
    mov     x9, #NODE_PRODUCE_PAYLOAD
    str     x9, [x22, #NodeApi_member]
    add     x2, x1, #BlockNode_block_hash   /* with a builder: its getHeader */
    mov     x0, x22
    mov     x1, x21
    bl      lantern_node_produce_header
    LEAVE 0
10: mov     x9, #NODE_PRODUCE_FOLD
    str     x9, [x22, #NodeApi_member]
    str     xzr, [x22, #NodeApi_filter_slot]
    mov     x0, x22
    bl      lantern_node_produce_next
    LEAVE 0
20: cmp     x9, #NODE_WORK_PRODUCE_FOLD     /* the draft holds the entry, or the rules left it out: the next */
    b.ne    25f
    mov     x0, x22
    bl      lantern_node_produce_next
    LEAVE 0
25: cmp     x9, #NODE_WORK_PRODUCE_ETH1     /* PRODUCE_ETH1: the snapshot goes; then the header call's wait, at the quiet point */
    b.ne    30f
    ldr     x1, [x22, #(NodeApi_cursor + PRODUCE_ETH1_SNAP)]
    str     xzr, [x22, #(NodeApi_cursor + PRODUCE_ETH1_SNAP)]
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
    mov     x1, #500
    cbnz    x25, 8f
    mov     x9, #NODE_PRODUCE_BID
    str     x9, [x22, #NodeApi_member]
    LEAVE 0
30: cmp     x9, #NODE_WORK_PRODUCE_BID      /* PRODUCE_BID: the answer goes, a valid bid stays; then the build */
    b.ne    31f
    ldr     x1, [x22, #(NodeApi_cursor + PRODUCE_BID)]
    str     xzr, [x22, #(NodeApi_cursor + PRODUCE_BID)]
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
    cbnz    x25, 32f
    add     x0, x21, #NodeEvent_chunk
    bl      lantern_node_put
    str     x0, [x22, #(NodeApi_cursor + PRODUCE_BID)]
32: mov     x0, x22
    bl      lantern_node_produce_build
    LEAVE 0
31: mov     x1, #500                        /* PRODUCE_BLOCK: the block's bytes, answered as a block's */
    cbnz    x25, 8f
    mov     x0, x22
    bl      lantern_node_produce_release
    add     x0, x21, #NodeEvent_chunk
    bl      lantern_node_put
    str     x0, [x22, #NodeApi_data]
    ldr     x9, [x22, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_OWN
    ldr     x10, [x21, #NodeEvent_checkpoint]   /* a blinded block */
    cbz     x10, 33f
    orr     x9, x9, #API_STREAM_PRODUCE_BLINDED
33: str     x9, [x22, #NodeApi_flags]
    add     x0, x22, #NodeApi_root          /* the values: execution_payload_value at root, consensus_block_value at filter_slot */
    add     x1, x21, #NodeEvent_root
    bl      lantern_copy_root
    ldr     x9, [x21, #NodeEvent_index]
    str     x9, [x22, #NodeApi_filter_slot]
    add     x0, x22, #NodeApi_cursor        /* the request goes: the cursor is the answer's JsonCursor */
    mov     x1, #(NodeApi_slot - NodeApi_cursor)
    bl      lantern_zero
    mov     x0, x22
    bl      lantern_node_produce_answer
    LEAVE 0
8:  mov     x0, x22
    bl      lantern_node_produce_fail
9:  LEAVE 0
END_FUNCTION lantern_node_produce_done

/* L1: the answer of the produceBlockV3 entry x0, whose block's bytes are its data: its first chunk. Uses x9-x12. */
LOCAL_FUNCTION lantern_node_produce_answer
    FRAME 0
    mov     x1, x0
    PART    x9, x10, x19, Node_api
    sub     x0, x1, x9
    mov     x11, #NodeApi__mem
    udiv    x0, x0, x11
    bl      lantern_node_api_chunk_work
    UNFRAME 0
END_FUNCTION lantern_node_produce_answer

/*
 * L2: the next work of the produceBlockV3 entry x0 in NODE_PRODUCE_FOLD: a PRODUCE_FOLD of the
 * next kept pool entry of the kind at cursor + 144 from index filter_slot, the kinds in the order
 * of api_produce_kinds; after the last, NODE_PRODUCE_BUILD and its PRODUCE_BLOCK. x21 the entry,
 * x22 its index, x25 a pool entry, x26 the pool index, x27 the kind's index, x28 its topic.
 */
LOCAL_FUNCTION lantern_node_produce_next
    ENTER 0
    mov     x21, x0
    PART    x9, x10, x19, Node_api
    sub     x22, x21, x9
    mov     x11, #NodeApi__mem
    udiv    x22, x22, x11
    ldr     x9, [x21, #NodeApi_flags]       /* busy with its next work */
    orr     x9, x9, #API_STREAM_BUSY
    str     x9, [x21, #NodeApi_flags]
    ldr     x9, [x21, #NodeApi_data]        /* the draft, before the first fold: a zeroed buffer */
    cbnz    x9, 11f
    mov     x0, #NODE_ACT_BYTES_NEW
    mov     x1, #NODE_ACT_BYTES_NEW_SIZE
    bl      lantern_node_act
    mov     x25, x0
    bl      lantern_node_new_id
    str     x0, [x25, #16]
    str     x0, [x21, #NodeApi_data]
    MOVQ    x9, ProduceDraft__size + 24
    str     x9, [x25, #24]
11: ldr     x26, [x21, #NodeApi_filter_slot]
    ldr     x27, [x21, #(NodeApi_cursor + 144)]  /* the kind: its index in api_produce_kinds */
1:  cmp     x27, #API_PRODUCE_KINDS
    b.hs    5f
    ADDRESS x9, api_produce_kinds
    ldrb    w28, [x9, x27]
2:  PART    x9, x10, x19, Node_pool
    cmp     x26, x10
    b.hs    3f
    mov     x11, #NodePool__mem
    madd    x25, x26, x11, x9
    add     x26, x26, #1
    ldr     x9, [x25, #NodePool_topic]
    cmp     x9, x28
    b.ne    2b
    ldr     x9, [x25, #NodePool_state]
    cmp     x9, #NODE_POOL_KEPT
    b.ne    2b
    str     x26, [x21, #NodeApi_filter_slot]
    str     x27, [x21, #(NodeApi_cursor + 144)]
    ldr     x9, [x25, #NodePool_data_id]
    str     x9, [x21, #NodeApi_root]
    ldr     x5, [x25, #NodePool_topic]  /* arg: the topic, the fork << 8, the member << 16 */
    ldr     x9, [x25, #NodePool_fork]
    orr     x5, x5, x9, lsl #8
    ldr     x9, [x25, #NodePool_member]
    orr     x5, x5, x9, lsl #16
    mov     x0, #NODE_WORK_PRODUCE_FOLD
    ldr     x1, [x21, #NodeApi_state]
    ldr     x2, [x25, #NodePool_data_id]
    ldr     x3, [x21, #NodeApi_data]
    mov     x4, x22
    bl      lantern_node_work
    LEAVE 0
3:  add     x27, x27, #1                    /* the next kind, from the pool's first entry */
    mov     x26, #0
    b       1b
5:  mov     x9, #NODE_PRODUCE_ETH1          /* after the last fold: the eth1 vote and deposits from the follower's snapshot */
    str     x9, [x21, #NodeApi_member]
    bl      lantern_node_eth1_snapshot
    str     x0, [x21, #(NodeApi_cursor + PRODUCE_ETH1_SNAP)]
    mov     x2, x0
    mov     x0, #NODE_WORK_PRODUCE_ETH1
    ldr     x1, [x21, #NodeApi_state]
    ldr     x3, [x21, #NodeApi_data]
    mov     x4, x22
    mov     x5, #0
    bl      lantern_node_work
    LEAVE 0
END_FUNCTION lantern_node_produce_next

/*
 * L2: the produceBlockV3 entry x0 in NODE_PRODUCE_BID with no call in flight goes on (node.md,
 * Block production): with the builder's answer at PRODUCE_BID a PRODUCE_BID work of it, else the
 * build. x21 the entry, x22 its index.
 */
LOCAL_FUNCTION lantern_node_produce_bid_go
    ENTER 0
    mov     x21, x0
    PART    x9, x10, x19, Node_api
    sub     x22, x21, x9
    mov     x11, #NodeApi__mem
    udiv    x22, x22, x11
    ldr     x3, [x21, #(NodeApi_cursor + PRODUCE_BID)]
    cbz     x3, 5f
    ldr     x9, [x21, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_BUSY
    str     x9, [x21, #NodeApi_flags]
    mov     x0, #NODE_WORK_PRODUCE_BID
    ldr     x1, [x21, #NodeApi_state]
    mov     x2, #0
    mov     x4, x22
    mov     x5, #0
    bl      lantern_node_work
    LEAVE 0
5:  mov     x0, x21
    bl      lantern_node_produce_build
    LEAVE 0
END_FUNCTION lantern_node_produce_bid_go

/*
 * L2: the build of the produceBlockV3 entry x0 (node.md, Block production): NODE_PRODUCE_BUILD and
 * its PRODUCE_BLOCK of the copy, the engine's result, the draft and the bid at PRODUCE_BID as
 * state_c. x21 the entry, x22 its index.
 */
LOCAL_FUNCTION lantern_node_produce_build
    ENTER 0
    mov     x21, x0
    PART    x9, x10, x19, Node_api
    sub     x22, x21, x9
    mov     x11, #NodeApi__mem
    udiv    x22, x22, x11
    ldr     x9, [x21, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_BUSY
    str     x9, [x21, #NodeApi_flags]
    mov     x9, #NODE_PRODUCE_BUILD
    str     x9, [x21, #NodeApi_member]
    mov     x0, #NODE_WORK_PRODUCE_BLOCK
    ldr     x1, [x21, #NodeApi_state]
    ldr     x2, [x21, #NodeApi_filter_index]
    ldr     x3, [x21, #NodeApi_data]
    mov     x4, x22
    mov     x5, #0
    bl      lantern_node_work
    ldr     x9, [x21, #(NodeApi_cursor + PRODUCE_BID)]
    str     x9, [x0, #NodeAction_state_c]
    LEAVE 0
END_FUNCTION lantern_node_produce_build

/*
 * L1: at a quiet point (node.md, Block production, NODE_PRODUCE_BID): each produceBlockV3 entry
 * waiting for its bid, with no work in flight: a header call in flight past
 * BUILDER_PROPOSAL_DELAY_TOLERANCE_MS answers no entry; with no call in flight, the entry goes on
 * while the actions have room for two works. x19 the node, x24 the actions; x21 an entry, x22 its
 * index, x26 the count.
 */
LOCAL_FUNCTION lantern_node_produce_due
    ENTER 0
    PART    x21, x26, x19, Node_api
    mov     x22, #0
1:  cmp     x22, x26
    b.hs    9f
    ldr     x9, [x21, #NodeApi_connection]
    cbz     x9, 2f
    ldr     x9, [x21, #NodeApi_op]
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3
    b.ne    2f
    ldr     x9, [x21, #NodeApi_member]
    cmp     x9, #NODE_PRODUCE_BID
    b.ne    2f
    ldr     x9, [x21, #NodeApi_flags]
    tbnz    x9, #4, 2f                      /* API_STREAM_BUSY: its bid's check */
    ldr     x9, [x21, #(NodeApi_cursor + PRODUCE_CALL)]
    cbz     x9, 3f
    sub     x9, x9, #1                      /* the call in flight: late at its time + the tolerance */
    ADDQ    x10, x19, Node_builder_calls
    mov     x11, #NODE_BUILDER_CALL_SIZE
    madd    x10, x9, x11, x10
    ldr     x11, [x10, #16]
    add     x11, x11, #BUILDER_PROPOSAL_DELAY_TOLERANCE_MS
    ldr     x12, [x19, #Node_time_ms]
    cmp     x12, x11
    b.lo    2f
    mov     x11, #-1
    str     x11, [x10, #8]
    str     xzr, [x21, #(NodeApi_cursor + PRODUCE_CALL)]
3:  mov     x0, #(2 * NODE_ACT_WORK_SIZE)
    bl      lantern_node_room
    cbz     x0, 9f
    mov     x0, x21
    bl      lantern_node_produce_bid_go
2:  add     x21, x21, #NodeApi__mem
    add     x22, x22, #1
    b       1b
9:  LEAVE 0
END_FUNCTION lantern_node_produce_due

/* L1: the draft and the engine's result of the produceBlockV3 entry x0 go. Locals: L the entry. */
LOCAL_FUNCTION lantern_node_produce_release
    FRAME 16
    str     x0, [sp, #16]
    ldr     x1, [x0, #NodeApi_data]         /* each field cleared first: lantern_node_ids leaves an entry's own bytes to it */
    str     xzr, [x0, #NodeApi_data]
    cbz     x1, 1f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
1:  ldr     x0, [sp, #16]
    ldr     x1, [x0, #NodeApi_filter_index]
    str     xzr, [x0, #NodeApi_filter_index]
    cbz     x1, 2f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
2:  ldr     x0, [sp, #16]                   /* the eth1 snapshot of a work in flight */
    ldr     x1, [x0, #(NodeApi_cursor + PRODUCE_ETH1_SNAP)]
    str     xzr, [x0, #(NodeApi_cursor + PRODUCE_ETH1_SNAP)]
    cbz     x1, 21f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
21: ldr     x0, [sp, #16]                   /* the builder's answer or bid */
    ldr     x1, [x0, #(NodeApi_cursor + PRODUCE_BID)]
    str     xzr, [x0, #(NodeApi_cursor + PRODUCE_BID)]
    cbz     x1, 3f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
3:  ldr     x0, [sp, #16]                   /* its header call in flight answers no entry */
    ldr     x9, [x0, #(NodeApi_cursor + PRODUCE_CALL)]
    str     xzr, [x0, #(NodeApi_cursor + PRODUCE_CALL)]
    cbz     x9, 4f
    sub     x9, x9, #1
    ADDQ    x10, x19, Node_builder_calls
    mov     x11, #NODE_BUILDER_CALL_SIZE
    madd    x10, x9, x11, x10
    mov     x11, #-1
    str     x11, [x10, #8]
4:  UNFRAME 16
END_FUNCTION lantern_node_produce_release

/*
 * L2: the error x1 to the produceBlockV3 entry x0, then its end: its draft and engine result go,
 * and its state with API_STREAM_OWN_STATE. Locals: L the entry.
 */
LOCAL_FUNCTION lantern_node_produce_fail
    FRAME 16
    str     x0, [sp, #16]
    mov     x2, x1
    ldr     x9, [x0, #NodeApi_flags]
    tbnz    x9, #5, 2f                      /* API_STREAM_GONE: the connection closed, no answer */
    ldr     x0, [x0, #NodeApi_connection]
    mov     x1, #0
    mov     x3, #API_BODY_ERROR
    and     x4, x9, #API_R_CLOSE            /* API_STREAM_CLOSE is API_R_CLOSE; HTTP/1.0 kept open says so */
    cbnz    x4, 1f
    tst     x9, #API_STREAM_HTTP10
    mov     x10, #API_R_KEEP
    csel    x4, x10, xzr, ne
1:  bl      lantern_node_api_send
2:  ldr     x0, [sp, #16]
    bl      lantern_node_produce_release
    ldr     x0, [sp, #16]
    bl      lantern_node_api_end
    UNFRAME 16
END_FUNCTION lantern_node_produce_fail

/*
 * L2: (connection x0, route x1, flags x2, request x3) -> x0: publishBlockV2 (node.md, Block
 * publishing): a NodeApi entry in NODE_PUBLISH_DECODE, the body's bytes as its data, and a
 * PUBLISH_DECODE work of them; 0 once it started, else the status of the error to answer. x21 the
 * entry, x22 its index, x25 the route, x26 the request, x27 the connection, x28 the flags.
 * Locals: L a ByteList view of the body.
 */
LOCAL_FUNCTION lantern_node_api_publish
    ENTER 32
    mov     x27, x0
    mov     x25, x1
    mov     x28, x2
    mov     x26, x3
    ldp     x10, x11, [x26, #HttpRequest_body]  /* a body of no bytes: 400 */
    cbz     x11, 8f
    add     x10, x26, x10
    add     x12, sp, #L
    sub     x13, x10, x12
    stp     x11, x13, [x12]
    str     x11, [x12, #16]
    bl      lantern_node_api_new
    mov     x22, x0
    mov     x21, x1
    mov     x0, x21
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    str     x27, [x21, #NodeApi_connection]
    mov     x9, #API_OP_PUBLISH_BLOCK_V2
    str     x9, [x21, #NodeApi_op]
    orr     x9, x28, #API_STREAM_BUSY       /* busy with its decode */
    str     x9, [x21, #NodeApi_flags]
    ldr     x9, [x25, #ApiRoute_consensus_version]
    str     x9, [x21, #NodeApi_fork]
    mov     x9, #NODE_PUBLISH_DECODE
    str     x9, [x21, #NodeApi_member]
    ldr     x9, [x25, #ApiRoute_broadcast_validation]   /* the level, and 1 for a JSON body */
    str     x9, [x21, #NodeApi_cursor]
    ldr     x9, [x25, #ApiRoute_body]
    cmp     x9, #API_TYPE_SSZ
    cset    x10, ne
    str     x10, [x21, #(NodeApi_cursor + 24)]
    ldr     x9, [x25, #ApiRoute_op]         /* publishBlindedBlockV2 from bellatrix: a blinded block */
    cmp     x9, #API_OP_PUBLISH_BLINDED_BLOCK_V2
    cset    x9, eq
    ldr     x10, [x25, #ApiRoute_consensus_version]
    cmp     x10, #FORK_BELLATRIX
    csel    x9, xzr, x9, lo
    str     x9, [x21, #(NodeApi_cursor + PUBLISH_BLINDED)]
    add     x0, sp, #L
    bl      lantern_node_put
    str     x0, [x21, #NodeApi_data]
    mov     x3, x0
    mov     x0, #NODE_WORK_PUBLISH_DECODE
    mov     x1, #0
    mov     x2, #0
    mov     x4, x22
    ldr     x5, [x21, #NodeApi_fork]
    ldr     x9, [x21, #(NodeApi_cursor + 24)]
    eor     x9, x9, #1
    orr     x5, x5, x9, lsl #8
    ldr     x9, [x21, #(NodeApi_cursor + PUBLISH_BLINDED)]
    orr     x5, x5, x9, lsl #9
    bl      lantern_node_work
    mov     x0, #0
    LEAVE 32
8:  mov     x0, #400
    LEAVE 32
END_FUNCTION lantern_node_api_publish

/*
 * L2: the NODE_EV_WORK_DONE x0 of a work of block publishing (node.md, Block publishing): the
 * publishBlockV2 entry at its target goes on, or answers. x21 the event, x22 the entry, x25 the
 * result, x26 the kind, x27 the block's bytes in the event.
 */
LOCAL_FUNCTION lantern_node_publish_done
    ENTER 16
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_target]
    cmn     x9, #1                          /* a sidecar of the reconstruction */
    b.ne    100f
    bl      lantern_node_recon_sidecar_done
    LEAVE 16
100: PART   x22, x10, x19, Node_api
    cmp     x9, x10
    b.hs    99f
    mov     x11, #NodeApi__mem
    madd    x22, x9, x11, x22
    ldr     x9, [x22, #NodeApi_connection]  /* an entry still there */
    cbz     x9, 99f
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_PUBLISH_BLOCK_V2
    b.ne    99f
    ldr     x9, [x22, #NodeApi_flags]       /* its work is done; the connection closed meanwhile: the entry ends, */
    and     x9, x9, #~API_STREAM_BUSY       /* but after a check that passed, or a sidecar, the publish goes on unanswered */
    str     x9, [x22, #NodeApi_flags]
    tbz     x9, #5, 1f
    ldr     x10, [x21, #NodeAction_work_kind]
    cmp     x10, #NODE_WORK_PUBLISH_CHECK
    b.lo    2f
    b.hi    1f
    ldr     x10, [x21, #NodeEvent_result]
    cbz     x10, 1f
2:  mov     x0, x22
    bl      lantern_node_publish_end
    LEAVE 16
1:  ldr     x25, [x21, #NodeEvent_result]
    ldr     x26, [x21, #NodeAction_work_kind]
    cmp     x26, #NODE_WORK_PUBLISH_SIDECAR /* a sidecar past the last, or one that is not there: the sidecars end */
    b.ne    12f
    cbz     x25, 12f
    str     xzr, [x22, #(NodeApi_cursor + 40)]
    mov     x0, x22
    bl      lantern_node_publish_drop
    LEAVE 16
12: mov     x1, #400                        /* a check that fails: 400 */
    cbnz    x25, 90f
    add     x27, x21, #NodeEvent_chunk
    cmp     x26, #NODE_WORK_PUBLISH_DECODE
    b.ne    20f
    mov     x0, x27                         /* DECODE: the block's bytes, root, slot, blob count, parent */
    bl      lantern_node_put
    str     x0, [x22, #NodeApi_filter_slot]
    add     x0, x22, #NodeApi_root
    add     x1, x21, #NodeEvent_root
    bl      lantern_copy_root
    ldr     x0, [x21, #NodeEvent_index]
    str     x0, [x22, #NodeApi_slot]
    ldr     x9, [x21, #NodeEvent_checkpoint]
    str     x9, [x22, #(NodeApi_cursor + 16)]
    ldr     x9, [x27, #8]
    add     x9, x27, x9
    add     x0, x22, #(NodeApi_cursor + 32)
    add     x1, x9, #116
    bl      lantern_copy_root
    ldr     x0, [x22, #NodeApi_slot]        /* a slot of another fork than consensus_version's: 400 */
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    ldr     x9, [x22, #NodeApi_fork]
    mov     x1, #400
    cmp     x0, x9
    b.ne    90f
    add     x0, x22, #NodeApi_root          /* a block the node holds: 200 */
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    11f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_INVALID
    mov     x1, #200
    b.ne    90f
11: ldr     x9, [x22, #(NodeApi_cursor + PUBLISH_BLINDED)]   /* a blinded block: no sidecars */
    cbnz    x9, 30f
    ldr     x9, [x22, #(NodeApi_cursor + 16)]   /* with blobs: the sidecars, else the check */
    cbz     x9, 30f
    mov     x0, x22
    bl      lantern_node_publish_sidecars_work
    LEAVE 16
20: cmp     x26, #NODE_WORK_PUBLISH_SIDECARS    /* SIDECARS: the check */
    b.eq    30f
    cmp     x26, #NODE_WORK_PUBLISH_SIDECAR
    b.ne    22f
    mov     x0, x22                         /* SIDECAR: it goes out and stays, then the next */
    mov     x1, x21
    bl      lantern_node_publish_sidecar_done
    LEAVE 16
22: cmp     x26, #NODE_WORK_PUBLISH_CHECK
    b.ne    99f
    ldr     x9, [x22, #(NodeApi_cursor + PUBLISH_BLINDED)]   /* a blinded block: to the builder */
    cbz     x9, 25f
    mov     x0, x22
    mov     x1, x27
    bl      lantern_node_publish_submit
    cbz     x0, 99f
    mov     x1, x0
    b       90f
25: bl      lantern_node_new_block                  /* CHECK: the block's NodeBlock, before the publish */
    str     x0, [sp, #L]
    add     x0, x1, #NodeBlock_root
    add     x9, x22, #NodeApi_root
    COPY32  x0, x9
    add     x0, x1, #NodeBlock_parent_root
    add     x9, x22, #(NodeApi_cursor + 32)
    COPY32  x0, x9
    ldr     x9, [x22, #NodeApi_slot]
    str     x9, [x1, #NodeBlock_slot]
    ldr     x9, [x22, #NodeApi_filter_slot]
    str     x9, [x1, #NodeBlock_data_id]
    str     xzr, [x22, #NodeApi_filter_slot]
    mov     x9, #NODE_BLOCK_WAITING
    str     x9, [x1, #NodeBlock_status]
    mov     x9, #1
    str     x9, [x1, #NodeBlock_data_available]
    ldr     x9, [x22, #(NodeApi_cursor + 16)]
    str     x9, [x1, #NodeBlock_blobs]
    ldr     x9, [x27, #16]
    str     x9, [x1, #NodeBlock_length]
    mov     x0, #API_TOPIC_BLOCK_GOSSIP     /* its block_gossip event: its checks passed */
    add     x1, x22, #NodeApi_root
    ldr     x2, [x22, #NodeApi_slot]
    mov     x3, #0
    bl      lantern_node_api_root_event
    ldr     x9, [x19, #Node_flags]          /* subscribed: the block out on beacon_block */
    tbz     x9, #2, 21f
    mov     x0, #GOSSIP_BEACON_BLOCK
    mov     x1, x27
    mov     x2, #0
    bl      lantern_node_publish
21: mov     x9, #NODE_PUBLISH_IMPORT        /* the import, the sidecars one at a time, then the answer */
    str     x9, [x22, #NodeApi_member]
    ldr     x9, [x22, #NodeApi_filter_index]
    cbz     x9, 23f
    str     xzr, [x22, #(NodeApi_cursor + 40)]
    mov     x0, x22
    bl      lantern_node_publish_sidecar_work
    b       24f
23: mov     x0, x22
    bl      lantern_node_publish_drop
24: ldr     x0, [sp, #L]
    bl      lantern_node_try_import
    LEAVE 16
30: mov     x0, x22                         /* the check */
    bl      lantern_node_publish_check_work
    cbz     x0, 99f
    mov     x1, x0
90: mov     x0, x22
    bl      lantern_node_publish_answer
99: LEAVE 16
END_FUNCTION lantern_node_publish_done

/*
 * L1: the PUBLISH_SIDECARS of the publishBlockV2 entry x0 (node.md, NODE_PUBLISH_SIDECARS): a
 * BYTES_NEW of the sidecars' room, its id the entry's filter_index, then the work. Locals: the
 * entry, the room, the action.
 */
LOCAL_FUNCTION lantern_node_publish_sidecars_work
    FRAME 32
    str     x0, [sp, #16]
    ldr     x9, [x0, #(NodeApi_cursor + 16)]    /* the blob count */
    ldr     x10, [x0, #NodeApi_fork]
    cmp     x10, #FORK_FULU
    b.hs    1f
    MOVQ    x11, PUB_BLOB_SIDECAR + 24      /* deneb and electra: a BlobSidecar for each blob */
    mul     x11, x9, x11
    b       2f
1:  MOVQ    x11, PUB_CELL_BYTES + 96        /* fulu: NUMBER_OF_COLUMNS column sidecars of the count */
    MOVQ    x12, PUB_COLUMN_FIXED + 24 + 7
    madd    x11, x9, x11, x12
    and     x11, x11, #~7
    mov     x12, #NUMBER_OF_COLUMNS
    mul     x11, x11, x12
2:  add     x11, x11, #24
    str     x11, [sp, #24]
    mov     x0, #NODE_ACT_BYTES_NEW
    mov     x1, #NODE_ACT_BYTES_NEW_SIZE
    bl      lantern_node_act
    str     x0, [sp, #32]
    bl      lantern_node_new_id
    ldr     x9, [sp, #32]
    str     x0, [x9, #16]
    ldr     x10, [sp, #24]
    str     x10, [x9, #24]
    ldr     x9, [sp, #16]
    str     x0, [x9, #NodeApi_filter_index]
    mov     x10, #NODE_PUBLISH_SIDECARS
    str     x10, [x9, #NodeApi_member]
    ldr     x10, [x9, #NodeApi_flags]
    orr     x10, x10, #API_STREAM_BUSY
    str     x10, [x9, #NodeApi_flags]
    mov     x2, x0                          /* the work: the sidecars as state_b, the body as data */
    ldr     x3, [x9, #NodeApi_data]
    PART    x10, x11, x19, Node_api
    sub     x4, x9, x10
    mov     x11, #NodeApi__mem
    udiv    x4, x4, x11
    ldr     x5, [x9, #NodeApi_fork]
    ldr     x10, [x9, #(NodeApi_cursor + 24)]   /* 2^8 for SSZ */
    eor     x10, x10, #1
    orr     x5, x5, x10, lsl #8
    mov     x0, #NODE_WORK_PUBLISH_SIDECARS
    mov     x1, #0
    bl      lantern_node_work
    UNFRAME 32
END_FUNCTION lantern_node_publish_sidecars_work

/*
 * L1: the PUBLISH_SIDECAR of the next sidecar (cursor + 40) of the publishBlockV2 entry x0 in
 * NODE_PUBLISH_IMPORT. Locals: the entry.
 */
LOCAL_FUNCTION lantern_node_publish_sidecar_work
    FRAME 16
    str     x0, [sp, #16]
    ldr     x10, [x0, #NodeApi_flags]
    orr     x10, x10, #API_STREAM_BUSY
    str     x10, [x0, #NodeApi_flags]
    ldr     x2, [x0, #NodeApi_filter_index]
    PART    x10, x11, x19, Node_api
    sub     x4, x0, x10
    mov     x11, #NodeApi__mem
    udiv    x4, x4, x11
    ldr     x5, [x0, #(NodeApi_cursor + 40)]
    mov     x0, #NODE_WORK_PUBLISH_SIDECAR
    mov     x1, #0
    mov     x3, #0
    bl      lantern_node_work
    UNFRAME 16
END_FUNCTION lantern_node_publish_sidecar_work

/*
 * L2: the WORK_DONE x0 of a PUBLISH_SIDECAR of the reconstruction (node.md): recon_state 2; a
 * valid one stays as a NodeBlob when the node lacks it, and goes out on its subnet's topic with
 * NODE_FLAG_SUBSCRIBED, a column of columns and recon_slot above F's slot. x22 the event, x25 the
 * sidecar's ByteList.
 */
LOCAL_FUNCTION lantern_node_recon_sidecar_done
    ENTER 0
    mov     x22, x0
    mov     x9, #2
    STQ     x9, x19, Node_recon_state
    ldr     x9, [x22, #NodeEvent_result]
    cbnz    x9, 9f
    add     x25, x22, #NodeEvent_chunk
    add     x0, x22, #NodeEvent_root
    ldr     x1, [x22, #NodeEvent_index]
    bl      lantern_node_blob_held
    cbnz    x0, 3f
    mov     x0, x25
    bl      lantern_node_put
    mov     x26, x0
    bl      lantern_node_new_blob
    add     x0, x1, #NodeBlob_block_root
    add     x9, x22, #NodeEvent_root
    COPY32  x0, x9
    ldr     x9, [x22, #NodeEvent_index]
    str     x9, [x1, #NodeBlob_index]
    ldr     x9, [x22, #NodeEvent_checkpoint]
    str     x9, [x1, #NodeBlob_slot]
    str     x26, [x1, #NodeBlob_data_id]
    mov     x9, #NODE_BLOB_VALID
    str     x9, [x1, #NodeBlob_status]
    ldr     x9, [x25, #16]
    str     x9, [x1, #NodeBlob_length]
    add     x0, x22, #NodeEvent_root
    bl      lantern_node_blob_added
3:  ldr     x9, [x19, #Node_flags]          /* subscribed: out on its subnet's topic */
    tbz     x9, #2, 9f
    ldr     x0, [x22, #NodeEvent_index]
    bl      lantern_node_sampled
    cbz     x0, 9f
    ldr     x9, [x20, #Store_finalized_checkpoint]
    mov     x10, #SLOTS_PER_EPOCH
    mul     x9, x9, x10
    LDQ     x10, x19, Node_recon_slot
    cmp     x10, x9
    b.ls    9f
    LDQ     x12, x19, Node_config + CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT
    cbz     x12, 9f
    ldr     x10, [x22, #NodeEvent_index]
    udiv    x13, x10, x12
    msub    x2, x13, x12, x10
    mov     x0, #GOSSIP_DATA_COLUMN_SIDECAR
    mov     x1, x25
    bl      lantern_node_publish
9:  LEAVE 0
END_FUNCTION lantern_node_recon_sidecar_done

/*
 * L2: the WORK_DONE x1 of a valid PUBLISH_SIDECAR of the publishBlockV2 entry x0: the sidecar
 * stays as a NodeBlob when the node keeps it (each blob sidecar; the column sidecars it samples),
 * goes out on its subnet's topic with NODE_FLAG_SUBSCRIBED, then the next. x21 the entry, x22 the
 * event, x25 the sidecar's ByteList, x26 its id. Step code keeps x23 and x24.
 */
LOCAL_FUNCTION lantern_node_publish_sidecar_done
    ENTER 0
    mov     x21, x0
    mov     x22, x1
    mov     x26, #0
    add     x25, x22, #NodeEvent_chunk
    ldr     x9, [x21, #NodeApi_fork]
    cmp     x9, #FORK_FULU
    b.lo    1f
    ldr     x0, [x22, #NodeEvent_index]     /* a column the node samples */
    bl      lantern_node_sampled
    cbz     x0, 3f
1:  add     x0, x22, #NodeEvent_root        /* one the node does not hold yet */
    ldr     x1, [x22, #NodeEvent_index]
    bl      lantern_node_blob_held
    cbnz    x0, 3f
    mov     x0, x25
    bl      lantern_node_put
    mov     x26, x0
    bl      lantern_node_new_blob
    add     x0, x1, #NodeBlob_block_root
    add     x9, x22, #NodeEvent_root
    COPY32  x0, x9
    ldr     x9, [x22, #NodeEvent_index]
    str     x9, [x1, #NodeBlob_index]
    ldr     x9, [x22, #NodeEvent_checkpoint]
    str     x9, [x1, #NodeBlob_slot]
    str     x26, [x1, #NodeBlob_data_id]
    mov     x9, #NODE_BLOB_VALID
    str     x9, [x1, #NodeBlob_status]
    ldr     x9, [x25, #16]
    str     x9, [x1, #NodeBlob_length]
    add     x0, x22, #NodeEvent_root
    bl      lantern_node_blob_added
3:  ldr     x9, [x21, #NodeApi_fork]        /* its event: of its NodeBlob's bytes, else of a copy for the work */
    mov     x27, #API_TOPIC_BLOB_SIDECAR
    mov     x10, #API_TOPIC_DATA_COLUMN_SIDECAR
    cmp     x9, #FORK_FULU
    csel    x27, x10, x27, hs
    mov     x0, x27
    bl      lantern_node_api_subscribed
    cbz     x0, 39f
    mov     x28, x26
    cbnz    x28, 38f
    mov     x0, x25
    bl      lantern_node_put
    mov     x28, x0
38: mov     x0, #NODE_WORK_API_EVENT
    mov     x1, #0
    mov     x2, #0
    mov     x3, x28
    mov     x4, #0
    ldr     x5, [x21, #NodeApi_fork]
    lsl     x5, x5, #16
    orr     x5, x5, x27
    bl      lantern_node_work
    cmp     x28, x26
    b.eq    39f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x1, x28
    mov     x2, #0
    bl      lantern_node_ids
39: ldr     x9, [x19, #Node_flags]          /* subscribed: out on its subnet's topic */
    tbz     x9, #2, 4f
    ldr     x10, [x22, #NodeEvent_index]
    ldr     x9, [x21, #NodeApi_fork]
    add     x11, x19, #Node_config
    cmp     x9, #FORK_FULU
    b.lo    31f
    mov     x0, #GOSSIP_DATA_COLUMN_SIDECAR
    ldr     x12, [x11, #CONFIG_DATA_COLUMN_SIDECAR_SUBNET_COUNT]
    b       33f
31: mov     x0, #GOSSIP_BLOB_SIDECAR
    cmp     x9, #FORK_ELECTRA
    b.lo    32f
    LDQ     x12, x11, CONFIG_BLOB_SIDECAR_SUBNET_COUNT_ELECTRA
    b       33f
32: LDQ     x12, x11, CONFIG_BLOB_SIDECAR_SUBNET_COUNT
33: cbz     x12, 4f
    udiv    x13, x10, x12
    msub    x2, x13, x12, x10
    mov     x1, x25
    bl      lantern_node_publish
4:  ldr     x9, [x21, #(NodeApi_cursor + 40)]   /* the next sidecar; after the last, the body and the sidecars go */
    add     x9, x9, #1
    str     x9, [x21, #(NodeApi_cursor + 40)]
    ldr     x10, [x21, #(NodeApi_cursor + 16)]
    ldr     x11, [x21, #NodeApi_fork]
    cmp     x11, #FORK_FULU
    mov     x11, #NUMBER_OF_COLUMNS
    csel    x10, x11, x10, hs
    mov     x0, x21
    cmp     x9, x10
    b.hs    5f
    bl      lantern_node_publish_sidecar_work
    LEAVE 0
5:  bl      lantern_node_publish_drop
    LEAVE 0
END_FUNCTION lantern_node_publish_sidecar_done

/*
 * L2: the PUBLISH_CHECK of the publishBlockV2 entry x0 (node.md, NODE_PUBLISH_CHECK): x0 = 0 once
 * it went, else 400 with no post-state of the parent, or 500 with no head post-state. x21 the
 * entry, x22 the parent's entry, x25 the copy, x26 the head's state id, x27 the copy's slot, x28
 * the parent's fork.
 */
LOCAL_FUNCTION lantern_node_publish_check_work
    ENTER 0
    mov     x21, x0
    add     x0, x19, #Node_head_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x26, [x1, #NodeBlock_state_id]
    cbz     x26, 9f
    add     x0, x21, #(NodeApi_cursor + 32)
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    8f
    mov     x22, x1
    ldr     x9, [x22, #NodeBlock_state_id]
    cbz     x9, 8f
    mov     x9, #NODE_PUBLISH_CHECK
    str     x9, [x21, #NodeApi_member]
    ldr     x9, [x21, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_BUSY
    str     x9, [x21, #NodeApi_flags]
    bl      lantern_node_new_id                     /* the copy, across the fork boundaries to the slot */
    mov     x25, x0
    mov     x2, x0
    mov     x0, #NODE_ACT_STATE_COPY
    ldr     x1, [x22, #NodeBlock_state_id]
    bl      lantern_node_ids
    mov     x0, x25
    ldr     x1, [x22, #NodeBlock_state_id]
    ldr     x2, [x22, #NodeBlock_slot]
    ldr     x3, [x21, #NodeApi_slot]
    bl      lantern_node_cross
    mov     x25, x0
    ldr     x0, [x22, #NodeBlock_slot]      /* the copy's slot: the parent's, or the first of the block's fork after an upgrade */
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x28, x0
    ldr     x0, [x21, #NodeApi_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    ldr     x27, [x22, #NodeBlock_slot]
    cmp     x0, x28
    b.ls    1f
    add     x9, x19, #Node_config
    add     x9, x9, x0, lsl #4
    ldr     x9, [x9]
    mov     x10, #SLOTS_PER_EPOCH
    mul     x9, x9, x10
    cmp     x9, x27
    csel    x27, x9, x27, hi
1:  ldr     x5, [x21, #NodeApi_slot]        /* then process_slots to the block's slot, as a lookup's */
    cmp     x5, x27
    b.ls    2f
    mov     x0, #NODE_WORK_SLOTS
    mov     x1, x25
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    bl      lantern_node_work
2:  PART    x9, x10, x19, Node_api
    sub     x4, x21, x9
    mov     x10, #NodeApi__mem
    udiv    x4, x4, x10
    mov     x0, #NODE_WORK_PUBLISH_CHECK
    mov     x1, x25
    ldr     x2, [x21, #NodeApi_filter_index]
    ldr     x3, [x21, #NodeApi_filter_slot]
    ldr     x5, [x21, #NodeApi_cursor]
    ldr     x9, [x21, #(NodeApi_cursor + PUBLISH_BLINDED)]   /* a blinded block's check */
    orr     x5, x5, x9, lsl #8
    bl      lantern_node_work
    str     x26, [x0, #NodeAction_state_c]
    mov     x0, #NODE_ACT_STATE_FREE
    mov     x1, x25
    mov     x2, #0
    bl      lantern_node_ids
    mov     x0, #0
    LEAVE 0
8:  mov     x0, #400
    LEAVE 0
9:  mov     x0, #500
    LEAVE 0
END_FUNCTION lantern_node_publish_check_work

/* L1: the ids of the publishBlockV2 entry x0 but the block's bytes go: its body and sidecars. Locals: the entry. */
LOCAL_FUNCTION lantern_node_publish_drop
    FRAME 16
    str     x0, [sp, #16]
    ldr     x1, [x0, #NodeApi_data]         /* each field cleared first: lantern_node_ids leaves an entry's own bytes to it */
    str     xzr, [x0, #NodeApi_data]
    cbz     x1, 1f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
1:  ldr     x0, [sp, #16]
    ldr     x1, [x0, #NodeApi_filter_index]
    str     xzr, [x0, #NodeApi_filter_index]
    cbz     x1, 2f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
2:  UNFRAME 16
END_FUNCTION lantern_node_publish_drop

/* L1: the end of the publishBlockV2 entry x0, its ids with it; its builder call in flight answers no entry. Locals: the entry. */
LOCAL_FUNCTION lantern_node_publish_end
    FRAME 16
    str     x0, [sp, #16]
    ldr     x9, [x0, #(NodeApi_cursor + PUBLISH_CALL)]
    str     xzr, [x0, #(NodeApi_cursor + PUBLISH_CALL)]
    cbz     x9, 1f
    sub     x9, x9, #1
    ADDQ    x10, x19, Node_builder_calls
    mov     x11, #NODE_BUILDER_CALL_SIZE
    madd    x10, x9, x11, x10
    mov     x11, #-1
    str     x11, [x10, #8]
1:  ldr     x0, [sp, #16]
    bl      lantern_node_publish_drop
    ldr     x0, [sp, #16]
    ldr     x1, [x0, #NodeApi_filter_slot]
    str     xzr, [x0, #NodeApi_filter_slot]
    cbz     x1, 1f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      lantern_node_ids
1:  ldr     x0, [sp, #16]
    bl      lantern_node_api_end
    UNFRAME 16
END_FUNCTION lantern_node_publish_end

/*
 * L2: the answer x1 (200, 202, or an error) of the publishBlockV2 entry x0, then its end; with
 * API_STREAM_GONE no answer. Locals: the entry.
 */
LOCAL_FUNCTION lantern_node_publish_answer
    FRAME 16
    str     x0, [sp, #16]
    mov     x2, x1
    ldr     x9, [x0, #NodeApi_flags]
    tbnz    x9, #5, 2f                      /* API_STREAM_GONE: the connection closed, no answer */
    ldr     x0, [x0, #NodeApi_connection]
    mov     x1, #0
    mov     x3, #0                          /* 200 and 202: no body */
    cmp     x2, #400
    mov     x10, #API_BODY_ERROR
    csel    x3, x10, x3, hs
    and     x4, x9, #API_R_CLOSE            /* API_STREAM_CLOSE is API_R_CLOSE; HTTP/1.0 kept open says so */
    cbnz    x4, 1f
    tst     x9, #API_STREAM_HTTP10
    mov     x10, #API_R_KEEP
    csel    x4, x10, xzr, ne
1:  bl      lantern_node_api_send
2:  ldr     x0, [sp, #16]
    bl      lantern_node_publish_end
    UNFRAME 16
END_FUNCTION lantern_node_publish_answer

/*
 * L1: after the head (node.md, NODE_PUBLISH_IMPORT): each publishBlockV2 entry whose block's import
 * ended answers, 200 for a block the node imported, 202 for another. x21 an entry, x22 the count.
 */
LOCAL_FUNCTION lantern_node_publish_poll
    ENTER 0
    PART    x21, x22, x19, Node_api
1:  cbz     x22, 9f
    ldr     x9, [x21, #NodeApi_connection]
    cbz     x9, 2f
    ldr     x9, [x21, #NodeApi_op]
    cmp     x9, #API_OP_PUBLISH_BLOCK_V2
    b.ne    2f
    ldr     x9, [x21, #NodeApi_member]
    cmp     x9, #NODE_PUBLISH_IMPORT
    b.ne    2f
    ldr     x9, [x21, #NodeApi_flags]
    tbnz    x9, #4, 2f                      /* API_STREAM_BUSY: a work of it in flight */
    add     x0, x21, #NodeApi_root
    bl      lantern_node_find_block
    mov     x2, #202
    cmn     x0, #1
    b.eq    3f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_INVALID
    b.eq    3f
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    2f
    mov     x2, #200
3:  mov     x0, x21
    mov     x1, x2
    bl      lantern_node_publish_answer
2:  add     x21, x21, #NodeApi__mem
    sub     x22, x22, #1
    b       1b
9:  LEAVE 0
END_FUNCTION lantern_node_publish_poll

/* L0: x0 = the count of the publishBlockV2 entries. Uses x9-x12. */
LOCAL_FUNCTION lantern_node_api_publish_count
    UNWIND_END_PROLOGUE
    mov     x0, #0
    PART    x9, x10, x19, Node_api
1:  cbz     x10, 9f
    ldr     x11, [x9, #NodeApi_connection]
    ldr     x12, [x9, #NodeApi_op]
    cmp     x12, #API_OP_PUBLISH_BLOCK_V2
    ccmp    x11, #0, #4, eq
    cinc    x0, x0, ne
    add     x9, x9, #NodeApi__mem
    sub     x10, x10, #1
    b       1b
9:  ret
END_FUNCTION lantern_node_api_publish_count

/* L0: x0 = the index of a free NodeApi entry (the first free, else the next; the step checked one is free), x1 = the entry. Uses x9-x12, x16. */
LOCAL_FUNCTION lantern_node_api_new
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_api
    mov     x11, #0
1:  cmp     x11, x10
    b.hs    2f
    ldr     x12, [x9, #NodeApi_connection]
    cbz     x12, 3f
    add     x9, x9, #NodeApi__mem
    add     x11, x11, #1
    b       1b
2:  add     x10, x10, #1
    STQ     x10, x19, Node_api + 8
3:  mov     x0, x11
    mov     x1, x9
    ret
END_FUNCTION lantern_node_api_new

/*
 * L1: the end of the stream of the NodeApi entry x0: the entry is free, the api part's count drops
 * past the free entries at its end; with API_STREAM_OWN, a BYTES_FREE of its data, which lantern_node_ids
 * gives to another entry that sends the same bytes. Locals: L data, L+8 flags.
 */
LOCAL_FUNCTION lantern_node_api_end
    FRAME 32
    ldp     x9, x10, [x0, #NodeApi_flags]
    stp     x10, x9, [sp, #16]
    ldr     x9, [x0, #NodeApi_state]
    str     x9, [sp, #32]
    str     xzr, [x0, #NodeApi_connection]
    PART    x9, x10, x19, Node_api
1:  cbz     x10, 2f
    sub     x11, x10, #1
    mov     x12, #NodeApi__mem
    madd    x12, x11, x12, x9
    ldr     x12, [x12, #NodeApi_connection]
    cbnz    x12, 2f
    mov     x10, x11
    b       1b
2:  STQ     x10, x19, Node_api + 8
    ldr     x9, [sp, #24]
    tbz     x9, #3, 8f                      /* API_STREAM_OWN */
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [sp, #16]
    mov     x2, #0
    bl      lantern_node_ids
8:  ldr     x9, [sp, #24]
    tbz     x9, #12, 9f                     /* API_STREAM_OWN_STATE */
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [sp, #32]
    mov     x2, #0
    bl      lantern_node_ids
9:  UNFRAME 32
END_FUNCTION lantern_node_api_end

/* L1: a NODE_WORK_API_CHUNK of the NodeApi entry x1 at index x0, which takes API_STREAM_BUSY. */
LOCAL_FUNCTION lantern_node_api_chunk_work
    FRAME 0
    ldr     x9, [x1, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_BUSY
    str     x9, [x1, #NodeApi_flags]
    mov     x5, x0
    ldr     x3, [x1, #NodeApi_data]
    ldr     x4, [x1, #NodeApi_connection]
    ldr     x1, [x1, #NodeApi_state]        /* a validator stream's state */
    mov     x0, #NODE_WORK_API_CHUNK
    mov     x2, #0
    bl      lantern_node_work
    UNFRAME 0
END_FUNCTION lantern_node_api_chunk_work

/* L1: NODE_EV_API_SENT of the connection x0: an event stream's sent is 0; another stream's next chunk, unless one is queued. */
LOCAL_FUNCTION lantern_node_api_sent
    FRAME 0
    bl      lantern_node_api_find
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeApi_op]
    cmp     x9, #API_OP_EVENTSTREAM
    b.ne    1f
    str     xzr, [x1, #NodeApi_sent]
    b       9f
1:  ldr     x9, [x1, #NodeApi_flags]
    tbnz    x9, #4, 9f                      /* API_STREAM_BUSY */
    bl      lantern_node_api_chunk_work
9:  UNFRAME 0
END_FUNCTION lantern_node_api_sent

/* ---------------------------------------------------------------- Events (beacon-api.md, eventstream) */

/*
 * L1: (out x0, answer flags x1) -> x0: the head of an eventstream answer into the ByteList out, its
 * count set; LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL. The writer's registers.
 */
LOCAL_FUNCTION lantern_api_sse_head
    ENTER 0
    mov     x23, x0
    mov     x28, x1
    mov     x25, #1
    mov     x27, #0
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    API_LIT api_ev_head
    tbnz    x28, #1, 1f                     /* API_ANSWER_HTTP10: closed after the body */
    API_LIT api_ev_chunked
    tbz     x28, #0, 2f                     /* API_ANSWER_CLOSE */
1:  API_LIT api_ev_close
2:  API_LIT api_crlf
    cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_api_sse_head

/*
 * L1: (view x0, out x1, topic x2) -> x0: the text of the event of the topic, from the view's event
 * fields, into the ByteList out, its count set; LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL. The
 * writer's registers; x28 the topic.
 */
LOCAL_FUNCTION lantern_api_event_text
    ENTER 0
    mov     x22, x0
    mov     x23, x1
    mov     x28, x2
    mov     x25, #1
    mov     x27, #0
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    API_LIT api_ev_event
    cmp     x28, #API_TOPIC_HEAD
    b.ne    13f
    API_LIT api_ev_t_head
    b       3f
13: cmp     x28, #API_TOPIC_HEAD_V2
    b.ne    1f
    /* head_v2: {"version":…,"data":{"slot":…,"block":…,"state":…,"payload_status":"full","epoch_transition":…,"current_epoch_dependent_root":…,"next_epoch_dependent_root":…,"execution_optimistic":…}} */
    API_LIT api_ev_t_head_v2
    API_LIT api_ev_data
    API_LIT api_pa_version
    ldr     x0, [x22, #ApiView_fork]
    bl      lantern_api_fork_name
    API_LIT api_ev_v2_slot
    ldr     x0, [x22, #ApiView_event_slot]
    bl      lantern_api_qdec
    API_LIT api_ev_block
    add     x0, x22, #ApiView_event_block
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_ev_state
    add     x0, x22, #ApiView_event_state
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_ev_full
    API_LIT api_ev_transition
    ldr     x0, [x22, #ApiView_event_flags]
    and     x0, x0, #1
    bl      lantern_api_bool
    API_LIT api_ev_current_epoch
    add     x0, x22, #ApiView_event_previous
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_ev_next_epoch
    add     x0, x22, #ApiView_event_current
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_u_optimistic
    ldr     x0, [x22, #ApiView_event_flags]
    ubfx    x0, x0, #1, #1
    bl      lantern_api_bool
    API_LIT api_end1
    b       61f
1:  cmp     x28, #API_TOPIC_BLOCK
    b.ne    11f
    API_LIT api_ev_t_block
    b       3f
11: cmp     x28, #API_TOPIC_BLOCK_GOSSIP
    b.ne    12f
    API_LIT api_ev_t_block_gossip
    b       3f
12: cmp     x28, #API_TOPIC_CHAIN_REORG
    b.ne    2f
    API_LIT api_ev_t_reorg
    b       3f
2:  API_LIT api_ev_t_finalized
3:  API_LIT api_ev_data
    cmp     x28, #API_TOPIC_FINALIZED_CHECKPOINT
    b.eq    5f
    cmp     x28, #API_TOPIC_CHAIN_REORG
    b.eq    7f
    /* block, block_gossip and head: {"slot":…,"block":… */
    API_LIT api_ev_slot
    ldr     x0, [x22, #ApiView_event_slot]
    bl      lantern_api_qdec
    API_LIT api_ev_block
    add     x0, x22, #ApiView_event_block
    mov     x1, #32
    bl      lantern_api_qhex
    cmp     x28, #API_TOPIC_BLOCK_GOSSIP
    b.eq    61f
    cmp     x28, #API_TOPIC_HEAD
    b.ne    6f
    /* head: state, epoch_transition and the dependent roots */
    API_LIT api_ev_state
    add     x0, x22, #ApiView_event_state
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_ev_transition
    ldr     x0, [x22, #ApiView_event_flags]
    and     x0, x0, #1
    bl      lantern_api_bool
    API_LIT api_ev_previous
    add     x0, x22, #ApiView_event_previous
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_ev_current
    add     x0, x22, #ApiView_event_current
    mov     x1, #32
    bl      lantern_api_qhex
    b       6f
    /* finalized_checkpoint: {"block":…,"state":…,"epoch":… */
5:  API_LIT api_ev_block1
    add     x0, x22, #ApiView_event_block
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_ev_state
    add     x0, x22, #ApiView_event_state
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_k_epoch
    ldr     x0, [x22, #ApiView_event_epoch]
    bl      lantern_api_qdec
    b       6f
    /* chain_reorg: {"slot":…,"depth":…,"old_head_block":…,"new_head_block":…,"old_head_state":…,"new_head_state":…,"epoch":… */
7:  API_LIT api_ev_slot
    ldr     x0, [x22, #ApiView_event_slot]
    bl      lantern_api_qdec
    API_LIT api_cr_depth
    ldr     x0, [x22, #ApiView_event_epoch]
    bl      lantern_api_qdec
    API_LIT api_cr_old_block
    add     x0, x22, #ApiView_event_old_block
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_cr_new_block
    add     x0, x22, #ApiView_event_block
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_cr_old_state
    add     x0, x22, #ApiView_event_old_state
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_cr_new_state
    add     x0, x22, #ApiView_event_state
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_k_epoch
    ldr     x0, [x22, #ApiView_event_slot]
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x0, x0, x9
    bl      lantern_api_qdec
6:  API_LIT api_u_optimistic
    ldr     x0, [x22, #ApiView_event_flags]
    ubfx    x0, x0, #1, #1
    bl      lantern_api_bool
61: API_LIT api_ev_end
    cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_api_event_text

/*
 * L1: (out x0, topic x1, kind x2, ssz x3, cursor x4; the fork in x15) -> x0: the text of the event of
 * an operation topic (beacon-api.md, eventstream): event: <topic> LF data: <lantern_node_json of the
 * kind and the ssz> LF LF, into the ByteList out, its count set; LANTERN_OK, LANTERN_BUFFER_TOO_SMALL,
 * or LANTERN_INVALID_ENCODING. The writer's registers; x19 the kind, x20 the ssz, x21 the cursor,
 * x22 the fork, x23 out, x28 the topic.
 */
LOCAL_FUNCTION lantern_api_op_event_text
    ENTER 0
    mov     x23, x0
    mov     x28, x1
    mov     x19, x2
    mov     x20, x3
    mov     x21, x4
    mov     x22, x15
    mov     x25, #1
    mov     x27, #0
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    API_LIT api_ev_event
    cmp     x28, #API_TOPIC_ATTESTATION
    b.ne    1f
    API_LIT api_ev_t_attestation
    b       7f
1:  cmp     x28, #API_TOPIC_SINGLE_ATTESTATION
    b.ne    2f
    API_LIT api_ev_t_single
    b       7f
2:  cmp     x28, #API_TOPIC_VOLUNTARY_EXIT
    b.ne    3f
    API_LIT api_ev_t_exit
    b       7f
3:  cmp     x28, #API_TOPIC_BLS_TO_EXECUTION_CHANGE
    b.ne    4f
    API_LIT api_ev_t_bls
    b       7f
4:  cmp     x28, #API_TOPIC_PROPOSER_SLASHING
    b.ne    5f
    API_LIT api_ev_t_proposer
    b       7f
5:  cmp     x28, #API_TOPIC_ATTESTER_SLASHING
    b.ne    6f
    API_LIT api_ev_t_attester
    b       7f
6:  API_LIT api_ev_t_contribution
7:  API_LIT api_ev_data
    cbnz    x27, 9f
    add     x9, x23, #24                    /* the JSON after the bytes so far */
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, x21
    mov     x1, #JSON_CURSOR_SIZE
    bl      lantern_zero
    mov     x15, x22
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x23
    FORK_CALL node_json
    cmp     x0, #LANTERN_JSON_MORE          /* the text passes the event's room */
    b.eq    9f
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    9f
    cbnz    x0, 8f
    ldr     x9, [x23, #16]
    add     x24, x23, #24
    add     x24, x24, x9
    API_LIT api_ev_lf2
    cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
8:  mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION lantern_api_op_event_text

/*
 * L1: (out x0, state x1, attributes x2, proposer x3, head root x4; the fork in x15) -> x0: the text
 * of the payload_attributes event (beacon-api.md, eventstream) of a preparation: event:
 * payload_attributes LF data: {"version":…,"data":{…}} LF LF, into the ByteList out, its count
 * set; LANTERN_OK or LANTERN_BUFFER_TOO_SMALL. The writer's registers; x19 the attributes, x20 the
 * state, x21 the fork, x22 the head root, x23 out, x28 the proposer. Locals: L the parent's block
 * number and hash (40), L+40 a withdrawal's index.
 */
LOCAL_FUNCTION lantern_api_payload_event_text
    ENTER 48
    mov     x23, x0
    mov     x20, x1
    mov     x19, x2
    mov     x28, x3
    mov     x22, x4
    mov     x21, x15
    mov     x0, x20                         /* the parent's block number and hash */
    add     x1, sp, #L
    FORK_CALL node_payload_parent
    cbnz    x0, 9f
    mov     x25, #1
    mov     x27, #0
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    API_LIT api_ev_event
    API_LIT api_ev_t_payload
    API_LIT api_ev_data
    API_LIT api_pa_version
    mov     x0, x21
    bl      lantern_api_fork_name
    API_LIT api_pa_proposer
    mov     x0, x28
    bl      lantern_api_qdec
    API_LIT api_pa_slot
    ldr     x0, [x20, #NODE_STATE_SLOT]
    bl      lantern_api_qdec
    API_LIT api_pa_number
    ldr     x0, [sp, #L]
    bl      lantern_api_qdec
    API_LIT api_pa_root
    mov     x0, x22
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_pa_hash
    add     x0, sp, #(L + 8)
    mov     x1, #32
    bl      lantern_api_qhex
    /* the PayloadAttributes (engine-api.md) */
    API_LIT api_pa_time
    ldr     x0, [x19]
    bl      lantern_api_qdec
    API_LIT api_pa_randao
    add     x0, x19, #8
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_pa_fee
    add     x0, x19, #40
    mov     x1, #20
    bl      lantern_api_qhex
    cmp     x21, #FORK_CAPELLA              /* from capella, the withdrawals: each 44 SSZ bytes */
    b.lo    3f
    API_LIT api_pa_withdrawals
    str     xzr, [sp, #(L + 40)]
1:  ldr     x9, [sp, #(L + 40)]
    ldr     x10, [x19, #96]
    cmp     x9, x10
    b.hs    2f
    cbz     x9, 11f
    API_LIT api_p_comma
11: ldr     x9, [sp, #(L + 40)]
    mov     x10, #44
    madd    x9, x9, x10, x19
    add     x9, x9, #104
    str     x9, [sp, #(L + 32)]
    API_LIT api_pa_index
    ldr     x9, [sp, #(L + 32)]
    ldr     x0, [x9]
    bl      lantern_api_qdec
    API_LIT api_u_index
    ldr     x9, [sp, #(L + 32)]
    ldr     x0, [x9, #8]
    bl      lantern_api_qdec
    API_LIT api_pa_address
    ldr     x9, [sp, #(L + 32)]
    add     x0, x9, #16
    mov     x1, #20
    bl      lantern_api_qhex
    API_LIT api_pa_amount
    ldr     x9, [sp, #(L + 32)]
    ldr     x0, [x9, #36]
    bl      lantern_api_qdec
    API_LIT api_end1
    ldr     x9, [sp, #(L + 40)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 40)]
    b       1b
2:  API_LIT api_p_rbracket
3:  cmp     x21, #FORK_DENEB                /* from deneb, the parent beacon block root */
    b.lo    4f
    API_LIT api_pa_parent
    add     x0, x19, #64
    mov     x1, #32
    bl      lantern_api_qhex
4:  API_LIT api_pa_end
    cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 48
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 48
END_FUNCTION lantern_api_payload_event_text

/*
 * L1: (out x0, topic x1, ssz x2, scratch x3; the fork in x15) -> x0: the text of the event of a
 * sidecar topic (beacon-api.md, eventstream): event: <topic> LF data: {"block_root":…,"index":…,
 * "slot":…,…} LF LF, from the sidecar's bytes, into the ByteList out, its count set; LANTERN_OK,
 * LANTERN_BUFFER_TOO_SMALL, or LANTERN_INVALID_ENCODING. The writer's registers; x19 the bytes,
 * x20 their count, x21 the fork, x23 out, x28 the topic. Locals: L the block root, L+32 a versioned
 * hash, L+64 a ByteList of a commitment (24 + 48), L+136 a commitment's index.
 */
LOCAL_FUNCTION lantern_api_sidecar_event_text
    ENTER 144
    mov     x23, x0
    mov     x28, x1
    mov     x21, x15
    ldr     x9, [x2, #8]
    add     x19, x2, x9
    ldr     x20, [x2, #16]
    mov     x0, x2                          /* block_root: lantern_node_sidecar_root */
    mov     x1, x3
    add     x2, sp, #L
    FORK_CALL node_sidecar_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    9f
    cbnz    x0, 8f
    mov     x25, #1
    mov     x27, #0
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    API_LIT api_ev_event
    cmp     x28, #API_TOPIC_BLOB_SIDECAR
    b.ne    1f
    API_LIT api_ev_t_blob
    b       2f
1:  API_LIT api_ev_t_column
2:  API_LIT api_ev_data
    API_LIT api_sc_root
    add     x0, sp, #L
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_sc_index
    ldr     x0, [x19]
    bl      lantern_api_qdec
    API_LIT api_c_slot
    cmp     x28, #API_TOPIC_BLOB_SIDECAR
    b.ne    4f
    MOVQ    x9, 8 + PUB_BLOB_BYTES + 96     /* a BlobSidecar: the header's slot, the commitment, its versioned hash */
    ldr     x0, [x19, x9]
    bl      lantern_api_qdec
    API_LIT api_sc_commitment
    MOVQ    x9, 8 + PUB_BLOB_BYTES
    add     x0, x19, x9
    mov     x1, #48
    bl      lantern_api_qhex
    API_LIT api_sc_hash
    add     x0, sp, #(L + 88)
    MOVQ    x9, 8 + PUB_BLOB_BYTES
    add     x1, x19, x9
    mov     x2, #48
    bl      lantern_copy
    mov     x9, #72
    mov     x10, #24
    mov     x11, #48
    add     x12, sp, #(L + 64)
    stp     x9, x10, [x12]
    str     x11, [x12, #16]
    add     x0, sp, #(L + 64)
    add     x1, sp, #(L + 32)
    CALL_GLOBAL crypto_sha256
    cbnz    x0, 8f
    mov     w9, #VERSIONED_HASH_VERSION_KZG
    strb    w9, [sp, #(L + 32)]
    add     x0, sp, #(L + 32)
    mov     x1, #32
    bl      lantern_api_qhex
    API_LIT api_end1
    b       7f
4:  ldr     x0, [x19, #20]                  /* a DataColumnSidecar: the header's slot, then the commitments */
    bl      lantern_api_qdec
    API_LIT api_sc_commitments
    ldr     w9, [x19, #12]
    ldr     w10, [x19, #16]
    cmp     x9, x10
    b.hi    8f
    cmp     x10, x20
    b.hi    8f
    sub     x10, x10, x9
    mov     x11, #48
    udiv    x12, x10, x11
    msub    x13, x12, x11, x10
    cbnz    x13, 8f
    str     xzr, [sp, #(L + 136)]
5:  ldr     x10, [sp, #(L + 136)]
    ldr     w9, [x19, #12]
    ldr     w11, [x19, #16]
    sub     x11, x11, x9
    lsr     x11, x11, #4                    /* the count: the bytes over 48 */
    mov     x12, #3
    udiv    x11, x11, x12
    cmp     x10, x11
    b.hs    6f
    cbz     x10, 51f
    API_LIT api_p_comma
51: ldr     x10, [sp, #(L + 136)]
    ldr     w9, [x19, #12]
    mov     x11, #48
    madd    x0, x10, x11, x9
    add     x0, x19, x0
    mov     x1, #48
    bl      lantern_api_qhex
    ldr     x10, [sp, #(L + 136)]
    add     x10, x10, #1
    str     x10, [sp, #(L + 136)]
    b       5b
6:  API_LIT api_v_end
7:  API_LIT api_ev_lf2
    cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 144
8:  mov     x0, #LANTERN_INVALID_ENCODING
    LEAVE 144
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 144
END_FUNCTION lantern_api_sidecar_event_text

/*
 * L1: the event of a valid operation of the gossip topic x0, its bytes x1, of the fork x2 (node.md,
 * The events): a NODE_WORK_API_EVENT of its event topic when an entry has the topic. Locals: the
 * bytes, the work's arg.
 */
LOCAL_FUNCTION lantern_node_op_event
    FRAME 16
    str     x1, [sp, #16]
    mov     x9, #API_TOPIC_VOLUNTARY_EXIT
    cmp     x0, #GOSSIP_VOLUNTARY_EXIT
    b.eq    1f
    mov     x9, #API_TOPIC_BLS_TO_EXECUTION_CHANGE
    cmp     x0, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    b.eq    1f
    mov     x9, #API_TOPIC_PROPOSER_SLASHING
    cmp     x0, #GOSSIP_PROPOSER_SLASHING
    b.eq    1f
    mov     x9, #API_TOPIC_ATTESTER_SLASHING
    cmp     x0, #GOSSIP_ATTESTER_SLASHING
    b.eq    1f
    mov     x9, #API_TOPIC_CONTRIBUTION_AND_PROOF
    cmp     x0, #GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    b.eq    1f
    mov     x9, #API_TOPIC_BLOB_SIDECAR
    cmp     x0, #GOSSIP_BLOB_SIDECAR
    b.eq    1f
    mov     x9, #API_TOPIC_DATA_COLUMN_SIDECAR
    cmp     x0, #GOSSIP_DATA_COLUMN_SIDECAR
    b.eq    1f
    cmp     x0, #GOSSIP_BEACON_ATTESTATION
    b.ne    9f
    mov     x9, #API_TOPIC_ATTESTATION      /* beacon_attestation: SingleAttestation from electra */
    mov     x10, #API_TOPIC_SINGLE_ATTESTATION
    cmp     x2, #FORK_ELECTRA
    csel    x9, x10, x9, hs
1:  orr     x9, x9, x2, lsl #16
    str     x9, [sp, #24]
    and     x0, x9, #255
    bl      lantern_node_api_subscribed
    cbz     x0, 9f
    mov     x0, #NODE_WORK_API_EVENT
    mov     x1, #0
    mov     x2, #0
    ldr     x3, [sp, #16]
    mov     x4, #0
    ldr     x5, [sp, #24]
    bl      lantern_node_work
9:  UNFRAME 16
END_FUNCTION lantern_node_op_event

/* L0: x0 = 1 when a NodeApi entry of eventstream has the topic x0, else 0. Uses x9-x13. */
LOCAL_FUNCTION lantern_node_api_subscribed
    UNWIND_END_PROLOGUE
    PART    x9, x10, x19, Node_api
1:  cbz     x10, 8f
    ldr     x11, [x9, #NodeApi_connection]
    cbz     x11, 2f
    ldr     x11, [x9, #NodeApi_op]
    cmp     x11, #API_OP_EVENTSTREAM
    b.ne    2f
    ldr     x11, [x9, #NodeApi_cursor]
    lsr     x11, x11, x0
    tbnz    x11, #0, 9f
2:  add     x9, x9, #NodeApi__mem
    sub     x10, x10, #1
    b       1b
8:  mov     x0, #0
    ret
9:  mov     x0, #1
    ret
END_FUNCTION lantern_node_api_subscribed

/* L0: x0 = the NodeApi entries of eventstream. Uses x9-x12. */
LOCAL_FUNCTION lantern_node_api_event_count
    UNWIND_END_PROLOGUE
    mov     x0, #0
    PART    x9, x10, x19, Node_api
1:  cbz     x10, 9f
    ldr     x11, [x9, #NodeApi_connection]
    ldr     x12, [x9, #NodeApi_op]
    cmp     x12, #API_OP_EVENTSTREAM
    ccmp    x11, #0, #4, eq
    cinc    x0, x0, ne
    add     x9, x9, #NodeApi__mem
    sub     x10, x10, #1
    b       1b
9:  ret
END_FUNCTION lantern_node_api_event_count

/*
 * L1: eventstream of the connection x0 with the route x1 and the answer flags x2 (node.md,
 * NODE_EV_API): a NodeApi entry of the route's topics, and a SEND of the head with last 0, its
 * bytes the entry's sent. Locals: L the entry, L+8 the action.
 */
LOCAL_FUNCTION lantern_node_api_subscribe
    ENTER 16
    mov     x21, x0
    mov     x22, x1
    mov     x25, x2
    bl      lantern_node_api_new
    str     x1, [sp, #L]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x1, [sp, #L]
    str     x21, [x1, #NodeApi_connection]
    mov     x9, #API_OP_EVENTSTREAM
    str     x9, [x1, #NodeApi_op]
    mov     x9, #API_STREAM_STARTED
    tbnz    x25, #1, 1f                     /* API_ANSWER_HTTP10 */
    orr     x9, x9, #API_STREAM_CHUNKED
    tbz     x25, #0, 2f                     /* API_ANSWER_CLOSE */
    orr     x9, x9, #API_STREAM_CLOSE
    b       2f
1:  orr     x9, x9, #(API_STREAM_CLOSE | API_STREAM_HTTP10)
2:  str     x9, [x1, #NodeApi_flags]
    ldr     x9, [x22, #ApiRoute_topics]
    str     x9, [x1, #NodeApi_cursor]
    mov     x0, #NODE_ACT_API_SEND          /* the head: 56 + 128 bytes of room */
    mov     x1, #(56 + 128)
    bl      lantern_node_act
    str     x0, [sp, #(L + 8)]
    add     x0, x0, #16
    mov     x1, #(56 + 128 - 16)
    bl      lantern_zero
    ldr     x0, [sp, #(L + 8)]
    str     x21, [x0, #16]
    mov     x9, #(128 + 24)
    str     x9, [x0, #32]
    add     x0, x0, #32
    mov     x1, x25
    bl      lantern_api_sse_head
    ldr     x0, [sp, #(L + 8)]
    ldr     x9, [x0, #48]
    ldr     x1, [sp, #L]
    str     x9, [x1, #NodeApi_sent]
    LEAVE 16
END_FUNCTION lantern_node_api_subscribe

/*
 * L1: the event text of the ByteList x0, of the topic x1, to each NodeApi entry of eventstream of
 * the topic (node.md, The events): a SEND of it, in one chunk with API_STREAM_CHUNKED, its bytes
 * added to the entry's sent; an entry whose sent would pass NODE_API_CHUNK gets a CLOSE and ends.
 * x21 the text, x22 the topic, x25 the entry, x26 its index, x27 the bytes sent, x28 the action.
 */
LOCAL_FUNCTION lantern_node_api_events
    ENTER 0
    mov     x21, x0
    mov     x22, x1
    mov     x26, #0
1:  PART    x9, x10, x19, Node_api
    cmp     x26, x10
    b.hs    9f
    mov     x11, #NodeApi__mem
    madd    x25, x26, x11, x9
    ldr     x9, [x25, #NodeApi_connection]
    cbz     x9, 8f
    ldr     x9, [x25, #NodeApi_op]
    cmp     x9, #API_OP_EVENTSTREAM
    b.ne    8f
    ldr     x9, [x25, #NodeApi_cursor]
    lsr     x9, x9, x22
    tbz     x9, #0, 8f
    ldr     x27, [x21, #16]
    ldr     x9, [x25, #NodeApi_flags]
    tst     x9, #API_STREAM_CHUNKED
    add     x10, x27, #8                    /* a chunk: 4 hex digits, CRLF, the text, CRLF */
    csel    x27, x10, x27, ne
    ldr     x9, [x25, #NodeApi_sent]
    add     x9, x9, x27
    mov     x10, #NODE_API_CHUNK
    cmp     x9, x10
    b.hi    5f
    str     x9, [x25, #NodeApi_sent]
    add     x1, x27, #(56 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_API_SEND
    bl      lantern_node_act
    mov     x28, x0
    add     x0, x28, #16
    ldr     x1, [x28]
    sub     x1, x1, #16
    bl      lantern_zero
    ldr     x9, [x25, #NodeApi_connection]
    str     x9, [x28, #16]
    ldr     x9, [x28]
    sub     x9, x9, #32
    mov     x10, #24
    stp     x9, x10, [x28, #32]
    str     x27, [x28, #48]
    add     x0, x28, #56
    ldr     x9, [x25, #NodeApi_flags]
    tbz     x9, #7, 3f                      /* API_STREAM_CHUNKED: the size in 4 lower case hex digits, CRLF */
    ldr     x10, [x21, #16]
    mov     x11, #12
2:  lsr     x12, x10, x11
    and     x12, x12, #15
    cmp     x12, #10
    add     x13, x12, #0x30
    add     x12, x12, #(0x61 - 10)
    csel    x12, x13, x12, lo
    strb    w12, [x0], #1
    subs    x11, x11, #4
    b.pl    2b
    mov     w12, #0x0a0d
    strh    w12, [x0], #2
3:  add     x1, x21, #24
    ldr     x2, [x21, #16]
    bl      lantern_copy
    ldr     x9, [x25, #NodeApi_flags]
    tbz     x9, #7, 8f
    ldr     x9, [x21, #16]                  /* and CRLF after the text */
    add     x9, x9, x28
    mov     w12, #0x0a0d
    strh    w12, [x9, #(56 + 6)]
    b       8f
5:  mov     x0, #NODE_ACT_API_CLOSE         /* the stream falls behind: a CLOSE, and it ends */
    mov     x1, #NODE_ACT_API_CLOSE_SIZE
    bl      lantern_node_act
    ldr     x9, [x25, #NodeApi_connection]
    str     x9, [x0, #16]
    mov     x0, x25
    bl      lantern_node_api_end
8:  add     x26, x26, #1
    b       1b
9:  LEAVE 0
END_FUNCTION lantern_node_api_events

/* L1: the block event of the NodeBlock entry x0 (node.md, The events): its slot and root, execution_optimistic from its payload status. */
LOCAL_FUNCTION lantern_node_api_block_event
    FRAME 0
    ldr     x9, [x0, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x3, eq
    lsl     x3, x3, #1
    ldr     x2, [x0, #NodeBlock_slot]
    add     x1, x0, #NodeBlock_root
    mov     x0, #API_TOPIC_BLOCK
    bl      lantern_node_api_root_event
    UNFRAME 0
END_FUNCTION lantern_node_api_block_event

/*
 * L1: the event of the topic x0 (block or block_gossip) of the block root x1 and slot x2, with the
 * values x3 (node.md, The events), with an entry of the topic: its text in a ByteList at the end of
 * scratch, after the ApiView of its values. x21 the root, x22 the view, x26 the ByteList, x25 the
 * topic, x27 the slot, x28 the values. Locals: L the scratch's size.
 */
LOCAL_FUNCTION lantern_node_api_root_event
    ENTER 16
    mov     x25, x0
    mov     x21, x1
    mov     x27, x2
    mov     x28, x3
    bl      lantern_node_api_subscribed
    cbz     x0, 9f
    ldr     x9, [x23]
    str     x9, [sp, #L]
    MOVQ    x10, ApiView__size + 1024
    subs    x9, x9, x10
    b.lo    9f
    str     x9, [x23]
    add     x22, x23, x9
    ADDQ    x26, x22, ApiView__size
    mov     x9, #1024
    mov     x10, #24
    stp     x9, x10, [x26]
    str     xzr, [x26, #16]
    str     x27, [x22, #ApiView_event_slot]
    add     x0, x22, #ApiView_event_block
    mov     x1, x21
    bl      lantern_copy_root
    str     x28, [x22, #ApiView_event_flags]
    mov     x0, x22
    mov     x1, x26
    mov     x2, x25
    bl      lantern_api_event_text
    cbnz    x0, 8f
    mov     x0, x26
    mov     x1, x25
    bl      lantern_node_api_events
8:  ldr     x9, [sp, #L]
    str     x9, [x23]
9:  LEAVE 16
END_FUNCTION lantern_node_api_root_event

/*
 * L1: the head and finalized_checkpoint events at a quiet point (node.md, The events): with no
 * block vote queued, a head other than event_head, then a finalized epoch above event_epoch; each
 * a NODE_WORK_API_EVENT when an entry has its topic. x21 the block, x22 the values.
 */
.if API_TOPIC_HEAD
.error "node_api_head_events: the arg of a head event takes API_TOPIC_HEAD as 0"
.endif
LOCAL_FUNCTION lantern_node_api_head_events
    ENTER 0
    LDQ     x9, x19, Node_event_votes
    cbnz    x9, 9f
    add     x0, x19, #Node_head_root
    ADDQ    x1, x19, Node_event_head
    ldp     x9, x10, [x0]
    ldp     x11, x12, [x1]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    1f
    ldp     x9, x10, [x0, #16]
    ldp     x11, x12, [x1, #16]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.eq    5f
1:  bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    5f
    mov     x21, x1
    mov     x0, #NODE_WORK_LC_HEAD          /* the light client data first */
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    mov     x5, #0
    bl      lantern_node_work
    mov     x9, #NODE_LC_ID
    str     x9, [x0, #NodeAction_state_c]
    ldr     x9, [x21, #NodeBlock_slot]      /* epoch_transition, execution_optimistic */
    LDQ     x10, x19, Node_event_slot
    mov     x11, #SLOTS_PER_EPOCH
    udiv    x12, x9, x11
    udiv    x13, x10, x11
    cmp     x12, x13
    cset    x22, hi
    ldr     x10, [x21, #NodeBlock_payload_status]
    cmp     x10, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x10, eq
    orr     x22, x22, x10, lsl #1
    mov     x0, #API_TOPIC_CHAIN_REORG      /* chain_reorg, before the head event: the new head's chain lacks the old head */
    bl      lantern_node_api_subscribed
    cbz     x0, 12f
    ldr     x9, [x21, #NodeBlock_state_id]
    cbz     x9, 12f
    ADDQ    x0, x19, Node_event_head
    mov     x1, x21
    bl      lantern_node_api_reorg
    cmn     x0, #1
    b.eq    12f
    ldr     x3, [x1, #NodeBlock_data_id]
    cbz     x3, 12f
    lsl     x5, x0, #16
    and     x9, x22, #2
    orr     x5, x5, x9, lsl #8
    add     x5, x5, #API_TOPIC_CHAIN_REORG
    mov     x0, #NODE_WORK_API_EVENT
    ldr     x1, [x21, #NodeBlock_state_id]
    mov     x2, #0
    mov     x4, #0
    bl      lantern_node_work
12: ldr     x9, [x21, #NodeBlock_slot]
    STQ     x9, x19, Node_event_slot
    ADDQ    x0, x19, Node_event_head
    add     x1, x21, #NodeBlock_root
    bl      lantern_copy_root
    ldr     x0, [x21, #NodeBlock_state_id]  /* the pool's checks at the new head */
    bl      lantern_node_pool_checks
    mov     x0, #API_TOPIC_HEAD
    bl      lantern_node_api_subscribed
    cbz     x0, 13f
    ldr     x1, [x21, #NodeBlock_state_id]
    cbz     x1, 5f
    mov     x0, #NODE_WORK_API_EVENT
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    lsl     x5, x22, #8                     /* API_TOPIC_HEAD is 0 */
    bl      lantern_node_work
13: mov     x0, #API_TOPIC_HEAD_V2          /* head_v2: the same values, its own text */
    bl      lantern_node_api_subscribed
    cbz     x0, 5f
    ldr     x1, [x21, #NodeBlock_state_id]
    cbz     x1, 5f
    mov     x0, #NODE_WORK_API_EVENT
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    lsl     x5, x22, #8
    add     x5, x5, #API_TOPIC_HEAD_V2
    bl      lantern_node_work
5:  ldr     x9, [x20, #Store_finalized_checkpoint]
    LDQ     x10, x19, Node_event_epoch
    cmp     x9, x10
    b.ls    9f
    STQ     x9, x19, Node_event_epoch
    mov     x0, #API_TOPIC_FINALIZED_CHECKPOINT
    bl      lantern_node_api_subscribed
    cbz     x0, 9f
    add     x0, x20, #(Store_finalized_checkpoint + 8)
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    ldr     x5, [x20, #Store_finalized_checkpoint]
    lsl     x5, x5, #16
    orr     x5, x5, x9, lsl #9
    add     x5, x5, #API_TOPIC_FINALIZED_CHECKPOINT
    ldr     x3, [x1, #NodeBlock_data_id]    /* the block's bytes, else its post-state */
    ldr     x1, [x1, #NodeBlock_state_id]
    cmp     x3, #0
    csel    x1, x1, xzr, eq
    orr     x9, x1, x3
    cbz     x9, 9f
    mov     x0, #NODE_WORK_API_EVENT
    mov     x2, #0
    mov     x4, #0
    bl      lantern_node_work
9:  LEAVE 0
END_FUNCTION lantern_node_api_head_events

/*
 * L1: (old head root x0, new head entry x1) -> x0: the depth of the reorg from the old head to the
 * new (node.md, The events: chain_reorg), or 2^64 - 1 with none: the new head's chain has the old
 * head below the new head's slot, or a walk meets no common block; x1 the old head's entry. The walk
 * by parent_root from both, the one at the higher slot first. x21 the old head's entry, x22 the new
 * head's, x25 the old chain's block, x26 the new chain's, x27 and x28 the blocks each walk left last.
 */
LOCAL_FUNCTION lantern_node_api_reorg
    ENTER 0
    mov     x22, x1
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    8f
    mov     x21, x1
    mov     x25, x21
    mov     x26, x22
    mov     x27, #0
    mov     x28, #0
1:  ldp     x9, x10, [x25]                  /* the same block: the common one */
    ldp     x11, x12, [x26]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.ne    2f
    ldp     x9, x10, [x25, #16]
    ldp     x11, x12, [x26, #16]
    cmp     x9, x11
    ccmp    x10, x12, #0, eq
    b.eq    4f
2:  ldr     x9, [x25, #NodeBlock_slot]
    ldr     x10, [x26, #NodeBlock_slot]
    cmp     x9, x10
    b.lo    3f
    mov     x27, x25                        /* the old chain's block, a step down */
    add     x0, x25, #NodeBlock_parent_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    8f
    mov     x25, x1
    b       1b
3:  mov     x28, x26                        /* the new chain's block, a step down */
    add     x0, x26, #NodeBlock_parent_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    8f
    mov     x26, x1
    b       1b
4:  ldr     x9, [x21, #NodeBlock_slot]      /* the old head common, below the new head's slot: no reorg */
    ldr     x10, [x22, #NodeBlock_slot]
    cmp     x25, x21
    ccmp    x9, x10, #2, eq
    b.lo    8f
    cmp     x9, x10                         /* the lowest of the two heads' slots and the slot before each chain's first block after it */
    csel    x11, x9, x10, lo
    cbz     x27, 5f
    ldr     x12, [x27, #NodeBlock_slot]
    sub     x12, x12, #1
    cmp     x12, x11
    csel    x11, x12, x11, lo
5:  cbz     x28, 6f
    ldr     x12, [x28, #NodeBlock_slot]
    sub     x12, x12, #1
    cmp     x12, x11
    csel    x11, x12, x11, lo
6:  sub     x0, x9, x11
    mov     x1, x21
    LEAVE 0
8:  mov     x0, #-1
    LEAVE 0
END_FUNCTION lantern_node_api_reorg

/* L1: NODE_EV_WORK_DONE x0 of a NODE_WORK_API_EVENT: LANTERN_VALID, its text to the entries of its topic. */
LOCAL_FUNCTION lantern_node_api_event_done
    FRAME 0
    ldr     x9, [x0, #NodeEvent_result]
    cbnz    x9, 9f
    ldr     x1, [x0, #NodeAction_arg]
    and     x1, x1, #255
    add     x0, x0, #NodeEvent_chunk
    bl      lantern_node_api_events
9:  UNFRAME 0
END_FUNCTION lantern_node_api_event_done

/* L1: NODE_EV_API_CLOSED of the connection x0: its stream ends, or with a chunk or work queued takes API_STREAM_GONE. Locals: L the entry. */
LOCAL_FUNCTION lantern_node_api_closed
    FRAME 16
    bl      lantern_node_api_find
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeApi_flags]
    tbz     x9, #4, 1f
    orr     x9, x9, #API_STREAM_GONE
    str     x9, [x1, #NodeApi_flags]
    b       9f
1:  str     x1, [sp, #16]
    ldr     x9, [x1, #NodeApi_op]           /* a produceBlockV3: its draft and engine result go too */
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3
    b.ne    3f
    mov     x0, x1
    bl      lantern_node_produce_release
2:  ldr     x0, [sp, #16]
    bl      lantern_node_api_end
9:  UNFRAME 16
3:  cmp     x9, #API_OP_PUBLISH_BLOCK_V2    /* a publishBlockV2: its ids; in NODE_PUBLISH_IMPORT it goes on unanswered */
    b.ne    2b
    ldr     x10, [x1, #NodeApi_member]
    cmp     x10, #NODE_PUBLISH_IMPORT
    b.ne    4f
    ldr     x9, [x1, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_GONE
    str     x9, [x1, #NodeApi_flags]
    UNFRAME 16
4:  mov     x0, x1
    bl      lantern_node_publish_end
    UNFRAME 16
END_FUNCTION lantern_node_api_closed

/*
 * L2: (connection x0, route x1, flags x2, view x3) -> x0: a stream of getBlockV2, getStateV2 or a validator operation of
 * the lookup in the view (node.md, NODE_EV_API): 0 once it started, else the status of the error to
 * answer. flags: API_STREAM_CLOSE and API_STREAM_HTTP10. x19 the node, x24 the actions. x21 the
 * data, x25 the route, x26 the view, x27 the connection, x28 the flags. Locals: L the entry's
 * index, L+8 the entry.
 */
LOCAL_FUNCTION lantern_node_api_stream
    ENTER 32
    str     xzr, [sp, #(L + 16)]
    mov     x27, x0
    mov     x25, x1
    mov     x28, x2
    mov     x26, x3
    ldr     x9, [x25, #ApiRoute_response]   /* SSZ, else JSON; the values of the JSON */
    cmp     x9, #API_TYPE_SSZ
    b.ne    1f
    orr     x28, x28, #API_STREAM_SSZ
1:  ldr     x9, [x26, #ApiView_is_optimistic]
    cbz     x9, 2f
    orr     x28, x28, #API_STREAM_OPTIMISTIC
2:  LDQ     x9, x26, ApiView_head_finalized
    cbz     x9, 3f
    orr     x28, x28, #API_STREAM_FINALIZED
3:  ldr     x9, [x25, #ApiRoute_op]
    cmp     x9, #API_OP_GET_STATE_V2
    b.eq    5f
    cmp     x9, #API_OP_GET_BLOCK_V2
    b.eq    4f
    cmp     x9, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    b.eq    4f
    cmp     x9, #API_OP_GET_BLINDED_BLOCK
    b.eq    4f
    ldr     x21, [x26, #ApiView_look_data]  /* a validator stream: its ids, and its state */
    cbz     x21, 31f
    orr     x28, x28, #API_STREAM_OWN
31: ldr     x9, [x26, #ApiView_look_copy]
    cbz     x9, 32f
    orr     x28, x28, #API_STREAM_OWN_STATE
32: ldr     x9, [x26, #ApiView_look_state]
    str     x9, [sp, #(L + 16)]
    ldr     x9, [x25, #ApiRoute_op]         /* getEpochCommittees: its epoch, else 400 and no stream */
    cmp     x9, #API_OP_GET_EPOCH_COMMITTEES
    b.ne    34f
    mov     x0, x25
    mov     x1, x26
    bl      lantern_node_api_committees_check
    str     x0, [sp, #(L + 24)]
    cmn     x0, #1
    b.ne    6f
    b       331f
34: sub     x10, x9, #API_OP_GET_PENDING_CONSOLIDATIONS /* the pending lists: 400 for a state before electra, and no stream */
    cmp     x10, #2
    b.hi    6f
    ldr     x0, [x26, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    cmp     x0, #FORK_ELECTRA
    b.hs    6f
331: ldr    x9, [x26, #ApiView_look_copy]
    cbz     x9, 33f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x26, #ApiView_look_state]
    mov     x2, #0
    bl      lantern_node_ids
33: mov     x0, #400
    LEAVE 32
4:  ldr     x21, [x26, #ApiView_look_data]  /* getBlockV2: the block's bytes */
    cbz     x21, 80f
    b       6f
5:  bl      lantern_node_new_id                     /* getStateV2: the state's SSZ bytes, as a new id the stream owns */
    mov     x21, x0
    mov     x0, #NODE_ACT_STATE_BYTES
    mov     x1, #NODE_ACT_STATE_BYTES_SIZE
    bl      lantern_node_act
    ldr     x9, [x26, #ApiView_look_state]
    stp     x9, x21, [x0, #16]
    orr     x28, x28, #API_STREAM_OWN
    ldr     x9, [x26, #ApiView_look_copy]   /* a copy goes after its bytes */
    cbz     x9, 6f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x26, #ApiView_look_state]
    mov     x2, #0
    bl      lantern_node_ids
6:  bl      lantern_node_api_new                    /* the entry */
    stp     x0, x1, [sp, #L]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x0, [x26, #ApiView_head_slot]
    ldr     x1, [sp, #(L + 8)]
    str     x0, [x1, #NodeApi_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    ldr     x1, [sp, #(L + 8)]
    str     x0, [x1, #NodeApi_fork]
    str     x27, [x1, #NodeApi_connection]
    ldr     x9, [x25, #ApiRoute_op]
    str     x9, [x1, #NodeApi_op]
    stp     x28, x21, [x1, #NodeApi_flags]
    ldr     x9, [sp, #(L + 16)]             /* a validator stream: its state and status bits */
    str     x9, [x1, #NodeApi_state]
    ldr     x9, [x25, #ApiRoute_statuses]
    str     x9, [x1, #NodeApi_statuses]
    ldr     x9, [x25, #ApiRoute_op]         /* getEpochCommittees: its cursor */
    cmp     x9, #API_OP_GET_EPOCH_COMMITTEES
    b.ne    7f
    mov     x0, x1
    mov     x1, x25
    ldr     x2, [sp, #(L + 24)]
    bl      lantern_node_api_committees_cursor
7:  ldp     x0, x1, [sp, #L]
    bl      lantern_node_api_chunk_work
    mov     x0, #0
    LEAVE 32
80: mov     x0, #404
    LEAVE 32
END_FUNCTION lantern_node_api_stream

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_CHUNK (node.md, lantern_node_step). x19 the
 * node, x24 the actions. x21 the event, x22 the entry, x23 the action, x25 the flags.
 */
LOCAL_FUNCTION lantern_node_api_chunk_done
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_arg]
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    99f
    mov     x12, #NodeApi__mem
    madd    x22, x9, x12, x10
    ldr     x9, [x22, #NodeApi_connection]
    cbz     x9, 99f
    ldr     x10, [x21, #NodeAction_target]
    cmp     x9, x10
    b.ne    99f
    ldr     x25, [x22, #NodeApi_flags]
    and     x25, x25, #~API_STREAM_BUSY
    str     x25, [x22, #NodeApi_flags]
    tbnz    x25, #5, 90f                    /* API_STREAM_GONE: the stream ends */
    ldr     x10, [x21, #NodeEvent_result]
    cbnz    x10, 50f
    ldr     x9, [x21, #NodeEvent_api]       /* valid: the entry takes sent, flags and cursor */
    str     x9, [x22, #NodeApi_sent]
    ldr     x9, [x21, #(NodeEvent_api + 8)]
    and     x9, x9, #~(API_STREAM_BUSY | API_STREAM_OWN)
    and     x10, x25, #API_STREAM_OWN
    orr     x25, x9, x10
    str     x25, [x22, #NodeApi_flags]
    add     x0, x22, #NodeApi_cursor
    add     x1, x21, #(NodeEvent_api + 16)
    mov     x2, #JSON_CURSOR_SIZE
    bl      lantern_copy
    tbz     x25, #14, 1f                    /* API_STREAM_ITEM_DONE: the pool stream's next entry, getBlockHeaders' next item */
    and     x25, x25, #~API_STREAM_ITEM_DONE
    str     x25, [x22, #NodeApi_flags]
    mov     x0, x22
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_GET_BLOCK_HEADERS
    b.ne    2f
    ldr     x1, [x22, #NodeApi_slot]
    add     x1, x1, #1
    bl      lantern_node_headers_next
    b       3f
2:  cmp     x9, #API_OP_GET_BLOBS          /* the blob stream: its next sidecar or cell */
    b.ne    21f
    bl      lantern_node_blob_advance
    b       3f
21: cmp     x9, #API_OP_GET_BLOB_SIDECARS   /* a sidecar stream: its sidecar from member + 1 on */
    b.eq    4f
    cmp     x9, #API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    b.ne    5f
4:  ldr     x1, [x22, #NodeApi_member]
    add     x1, x1, #1
    bl      lantern_node_sidecar_next
    b       3f
5:  bl      lantern_node_api_pool_advance
3:  ldr     x25, [x22, #NodeApi_flags]
1:  tbz     x25, #15, 11f                   /* API_STREAM_FOLD: no send, and the next chunk at once */
    tbnz    x25, #10, 11f                   /* the error that ends it goes */
    ldr     x9, [x22, #NodeApi_data]
    cbnz    x9, 12f                         /* a fold */
    ldr     x9, [x21, #(NodeEvent_api_bytes + 16)]
    cbnz    x9, 14f                         /* the Attestation's bytes */
    ldr     x9, [x22, #(NodeApi_cursor + 32)]   /* the fold's end: optimistic for a NOT_VALIDATED block */
    cbz     x9, 12f
    add     x0, x22, #(NodeApi_cursor + 48 + 16)    /* the aggregate's data.beacon_block_root, a contribution's at byte 0 */
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    add     x9, x22, #NodeApi_cursor
    csel    x0, x9, x0, eq
    bl      lantern_node_store_find
    cmn     x0, #1
    b.eq    12f
    ldr     x9, [x1, #BlockNode_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    b.ne    12f
    orr     x25, x25, #API_STREAM_OPTIMISTIC
    str     x25, [x22, #NodeApi_flags]
    b       12f
14: add     x0, x21, #NodeEvent_api_bytes   /* they become the stream's own data; the answer from sent 0 */
    bl      lantern_node_put
    str     x0, [x22, #NodeApi_data]
    and     x25, x25, #~API_STREAM_FOLD
    orr     x25, x25, #API_STREAM_OWN
    str     x25, [x22, #NodeApi_flags]
    str     xzr, [x22, #NodeApi_sent]
    add     x0, x22, #NodeApi_cursor
    mov     x1, #JSON_CURSOR_SIZE
    bl      lantern_zero
12: ldr     x0, [x21, #NodeAction_arg]
    mov     x1, x22
    bl      lantern_node_api_chunk_work
    b       99f
11: ldr     x9, [x21, #(NodeEvent_api_bytes + 16)]  /* the chunk in a SEND */
    add     x1, x9, #(56 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_API_SEND
    bl      lantern_node_act
    mov     x23, x0
    ldr     x9, [x22, #NodeApi_connection]
    ubfx    x10, x25, #10, #1               /* last: API_STREAM_DONE */
    stp     x9, x10, [x23, #16]
    ldr     x9, [x23]
    sub     x9, x9, #32
    mov     x10, #24
    stp     x9, x10, [x23, #32]
    ldr     x2, [x21, #(NodeEvent_api_bytes + 16)]
    str     x2, [x23, #48]
    add     x0, x23, #56
    ldr     x9, [x21, #(NodeEvent_api_bytes + 8)]
    add     x1, x21, #NodeEvent_api_bytes
    add     x1, x1, x9
    bl      lantern_copy
    ldr     x9, [x23, #48]                  /* zero bytes to the size */
    add     x0, x23, #56
    add     x0, x0, x9
    ldr     x10, [x23]
    sub     x1, x10, #56
    sub     x1, x1, x9
    bl      lantern_zero
    tbz     x25, #10, 99f                   /* not the last: the next chunk at the next API_SENT */
    tbz     x25, #0, 90f                    /* API_STREAM_CLOSE: a CLOSE after it */
    b       60f
50: tbnz    x25, #6, 60f                    /* another result: before API_STREAM_STARTED the error 500, after it a CLOSE */
    ldr     x0, [x22, #NodeApi_connection]
    mov     x1, #0
    mov     x2, #500
    mov     x3, #API_BODY_ERROR
    and     x4, x25, #API_R_CLOSE           /* API_STREAM_CLOSE is API_R_CLOSE; HTTP/1.0 kept open says so */
    cbnz    x4, 51f
    tst     x25, #API_STREAM_HTTP10
    mov     x9, #API_R_KEEP
    csel    x4, x9, xzr, ne
51: bl      lantern_node_api_send
    b       90f
60: mov     x0, #NODE_ACT_API_CLOSE
    mov     x1, #NODE_ACT_API_CLOSE_SIZE
    bl      lantern_node_act
    ldr     x9, [x22, #NodeApi_connection]
    str     x9, [x0, #16]
90: mov     x0, x22
    bl      lantern_node_api_end
99: LEAVE 0
END_FUNCTION lantern_node_api_chunk_done

/* L1: the name of the fork x0 joins the response. */
LOCAL_FUNCTION lantern_api_fork_name
    FRAME 0
    ADDRESS x9, api_forks
    add     x9, x9, x0, lsl #4
    ldrb    w1, [x9], #1
    mov     x0, x9
    bl      lantern_api_put
    UNFRAME 0
END_FUNCTION lantern_api_fork_name

/*
 * L1: the head of a streamed answer (beacon-api.md, Common rules) for the flags at
 * NodeEvent_api + 8 of the event x23 and the fork of the entry x22: with Content-Length x0, or
 * for x0 = 2^64 - 1 Transfer-Encoding: chunked when API_STREAM_CHUNKED is set, else neither.
 * Locals: x0.
 */
LOCAL_FUNCTION lantern_api_stream_head
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_ok
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #2, 1f
    API_LIT api_octet
    b       2f
1:  API_LIT api_type
2:  ldr     x9, [x22, #NodeApi_op]          /* Eth-Consensus-Version: of getBlockV2 and getStateV2 */
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3
    b.eq    23f
    cmp     x9, #API_OP_GET_BLOCK_V2
    b.eq    21f
    cmp     x9, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    b.eq    21f
    cmp     x9, #API_OP_GET_BLINDED_BLOCK
    b.eq    21f
    cmp     x9, #API_OP_GET_STATE_V2
    b.eq    21f
    cmp     x9, #API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    b.eq    21f
    cmp     x9, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.eq    21f
    cmp     x9, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.eq    21f
    cmp     x9, #API_OP_GET_BLOB_SIDECARS
    b.eq    21f
    cmp     x9, #API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    b.eq    21f
    sub     x10, x9, #API_OP_GET_PENDING_CONSOLIDATIONS    /* and of the pending lists */
    cmp     x10, #2
    b.hi    22f
21: API_LIT api_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      lantern_api_fork_name
    API_LIT api_crlf
    b       22f
    /* produceBlockV3: and its three headers */
23: API_LIT api_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      lantern_api_fork_name
    API_LIT api_crlf
    ldr     x9, [x22, #NodeApi_flags]       /* blinded with API_STREAM_PRODUCE_BLINDED */
    tbnz    x9, #19, 231f
    API_LIT api_h_blinded
    b       232f
231: API_LIT api_h_blinded_true
232: add    x0, x22, #NodeApi_root
    bl      lantern_api_dec256
    API_LIT api_h_block_value
    ldr     x0, [x22, #NodeApi_filter_slot]
    bl      lantern_api_wei
    API_LIT api_crlf
22: ldr     x0, [sp, #16]
    cmn     x0, #1
    b.eq    3f
    API_LIT api_length
    ldr     x0, [sp, #16]
    bl      lantern_api_dec
    API_LIT api_crlf
    b       4f
3:  ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #7, 4f
    API_LIT api_chunked
4:  ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #0, 5f
    API_LIT api_close
    b       6f
5:  tbz     x9, #1, 6f
    API_LIT api_keep
6:  API_LIT api_crlf
    UNFRAME 16
END_FUNCTION lantern_api_stream_head

/* L0: the 4 lower case hex digits of x0 at x1. Uses x9, x10. */
LOCAL_FUNCTION lantern_api_hex4
    UNWIND_END_PROLOGUE
    ADDRESS x9, api_hex
    ubfx    x10, x0, #12, #4
    ldrb    w10, [x9, x10]
    strb    w10, [x1]
    ubfx    x10, x0, #8, #4
    ldrb    w10, [x9, x10]
    strb    w10, [x1, #1]
    ubfx    x10, x0, #4, #4
    ldrb    w10, [x9, x10]
    strb    w10, [x1, #2]
    and     x10, x0, #15
    ldrb    w10, [x9, x10]
    strb    w10, [x1, #3]
    ret
END_FUNCTION lantern_api_hex4

/*
 * L1: the JSON of the entry x22's SSZ bytes x21 from the cursor at NodeEvent_api + 16 of the event
 * x23, at the writer's cursor x24 up to x26 less a byte, through the event's ByteList at
 * NodeEvent_api_bytes whose bytes start at x28; then } once it is whole. x0 = 1 when whole, 0
 * when more is to come, 2 for bytes that are no encoding.
 */
LOCAL_FUNCTION lantern_api_stream_json
    FRAME 0
    ldr     x9, [x22, #NodeApi_op]          /* the validator streams: their items */
    cmp     x9, #API_OP_GET_POOL_VOLUNTARY_EXITS
    b.eq    4f
    cmp     x9, #API_OP_GET_POOL_PROPOSER_SLASHINGS
    b.eq    4f
    cmp     x9, #API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    b.eq    4f
    cmp     x9, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.eq    4f
    cmp     x9, #API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES
    b.ne    3f
4:  bl      lantern_api_pool_json
    UNFRAME 0
3:  cmp     x9, #API_OP_GET_BLOCK_HEADERS
    b.ne    32f
    bl      lantern_api_headers_json
    UNFRAME 0
32: cmp     x9, #API_OP_GET_BLOBS
    b.ne    35f
    bl      lantern_api_blob_body
    UNFRAME 0
35: cmp     x9, #API_OP_GET_BLOB_SIDECARS
    b.eq    33f
    cmp     x9, #API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    b.ne    34f
33: bl      lantern_api_sidecar_body
    UNFRAME 0
34: sub     x10, x9, #API_OP_GET_PENDING_CONSOLIDATIONS /* the pending streams: their items */
    cmp     x10, #2
    b.hi    31f
    bl      lantern_api_pending_json
    UNFRAME 0
31: cmp     x9, #API_OP_GET_BLOCK_V2
    b.eq    1f
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3
    b.eq    1f
    cmp     x9, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.eq    1f
    cmp     x9, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    b.eq    1f
    cmp     x9, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_BLINDED_BLOCK
    b.eq    1f
    cmp     x9, #API_OP_GET_STATE_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_ATTESTATIONS_REWARDS
    b.eq    35f
    cmp     x9, #API_OP_GET_EPOCH_COMMITTEES
    b.eq    2f
    bl      lantern_api_validators_json
    UNFRAME 0
35: bl      lantern_api_rewards_json
    UNFRAME 0
2:  bl      lantern_api_committees_json
    UNFRAME 0
1:  add     x9, x23, #NodeEvent_api_bytes   /* the ByteList: its room to x26 - 1, its bytes to x24 */
    sub     x10, x26, #1
    sub     x10, x10, x9
    mov     x11, #24
    stp     x10, x11, [x9]
    sub     x10, x24, x28
    str     x10, [x9, #16]
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_GET_STATE_V2
    cset    x0, eq                          /* NODE_JSON_STATE, else NODE_JSON_BLOCK; NODE_JSON_ATTESTATIONS of a block's */
    cmp     x9, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    mov     x10, #NODE_JSON_ATTESTATIONS
    csel    x0, x10, x0, eq
    cmp     x9, #API_OP_GET_BLINDED_BLOCK
    mov     x10, #NODE_JSON_BLINDED_BLOCK
    csel    x0, x10, x0, eq
    cmp     x9, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    mov     x10, #NODE_JSON_ATTESTATION
    csel    x0, x10, x0, eq
    cmp     x9, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    mov     x10, #NODE_JSON_SYNC_CONTRIBUTION
    csel    x0, x10, x0, eq
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3    /* produceBlockV3: the block, from deneb its BlockContents */
    b.ne    11f
    mov     x0, #NODE_JSON_BEACON_BLOCK
    ldr     x10, [x22, #NodeApi_fork]
    cmp     x10, #FORK_DENEB
    mov     x10, #NODE_JSON_BLOCK_CONTENTS
    csel    x0, x10, x0, hs
    ldr     x10, [x22, #NodeApi_flags]      /* a blinded block: its BlindedBeaconBlock */
    tst     x10, #API_STREAM_PRODUCE_BLINDED
    mov     x10, #NODE_JSON_BLINDED_BEACON_BLOCK
    csel    x0, x10, x0, ne
11: mov     x1, x21
    add     x2, x23, #(NodeEvent_api + 16)
    add     x3, x23, #NodeEvent_api_bytes
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_json
    ldr     x9, [x23, #(NodeEvent_api_bytes + 16)]
    add     x24, x28, x9
    cmp     x0, #LANTERN_JSON_MORE
    b.eq    8f
    cbnz    x0, 7f
    API_LIT api_end1
    mov     x0, #1
    UNFRAME 0
7:  mov     x0, #2
    UNFRAME 0
8:  mov     x0, #0
    UNFRAME 0
END_FUNCTION lantern_api_stream_json

/*
 * (node, work, data, scratch, event, room, state_a) -> status: a NODE_WORK_API_CHUNK of
 * lantern_node_run (node.md): the next chunk of the NodeApi entry at the work's arg, from the SSZ
 * bytes in data, or for a validator stream from state_a and the ids in data, at NodeEvent_api of
 * the event, whose buffer has room bytes. x19 the node, x20 state_a, x21 data, x22 the entry, x23
 * the event; the writer's x24-x27 (lantern_api_put); x28 where the chunk's bytes start. Locals: L the end
 * of the chunk's room, L+8 the SSZ bytes, L+16 their count, L+24 the body's start, L+32 the head's
 * bytes, L+40 1 for a validator stream, L+48 the scratch.
 */
LOCAL_FUNCTION lantern_node_api_chunk_run
    ENTER 64
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x23, x4
    str     x3, [sp, #(L + 48)]
    ldr     x9, [x20, #NodeAction_arg]      /* the entry */
    mov     x20, x6                         /* x20: the state of a validator stream */
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    98f
    mov     x12, #NodeApi__mem
    madd    x22, x9, x12, x10
    ldr     x9, [x22, #NodeApi_connection]
    cbz     x9, 98f
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_GET_BLOCK_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_BLINDED_BLOCK
    b.eq    1f
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3
    b.eq    1f
    cmp     x9, #API_OP_GET_STATE_V2
    b.eq    1f
    mov     x10, x9                         /* a pool stream (3): data 0 at its end */
    mov     x9, #3
    cmp     x10, #API_OP_GET_POOL_VOLUNTARY_EXITS
    b.eq    2f
    cmp     x10, #API_OP_GET_POOL_PROPOSER_SLASHINGS
    b.eq    2f
    cmp     x10, #API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    b.eq    2f
    cmp     x10, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.eq    2f
    cmp     x10, #API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES
    b.eq    2f
    mov     x9, #7                          /* getAggregatedAttestationV2 and produceSyncCommitteeContribution (7): their fold, then their answer */
    cmp     x10, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.eq    2f
    cmp     x10, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    b.eq    2f
    mov     x9, #6                          /* a sidecar stream (6), and the blob stream: data 0 at its end */
    cmp     x10, #API_OP_GET_BLOB_SIDECARS
    b.eq    2f
    cmp     x10, #API_OP_GET_BLOBS
    b.eq    2f
    cmp     x10, #API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    b.eq    2f
    mov     x9, #5                          /* getBlockHeaders (5): an item of data or state, none at its end */
    cmp     x10, #API_OP_GET_BLOCK_HEADERS
    b.eq    2f
    mov     x9, x10
    sub     x11, x9, #API_OP_GET_PENDING_CONSOLIDATIONS /* a pending stream (4): a state */
    cmp     x11, #2
    b.hi    241f
    cbz     x20, 98f
    mov     x9, #4
    b       2f
241: cmp    x9, #API_OP_GET_ATTESTATIONS_REWARDS    /* getAttestationsRewards: as a validator stream (1), of a state */
    b.ne    243f
    cbz     x20, 98f
    mov     x9, #1
    b       2f
243: sub    x10, x9, #API_OP_GET_STATE_VALIDATORS   /* a validator stream (1) or getEpochCommittees (2): a state */
    cmp     x10, #(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS)
    b.hi    98f
    cmp     x9, #API_OP_GET_STATE_VALIDATOR
    b.eq    98f
    cbz     x20, 98f
    cmp     x9, #API_OP_GET_EPOCH_COMMITTEES
    mov     x9, #1
    mov     x10, #2
    csel    x9, x10, x9, eq
    b       2f
1:  cbz     x21, 98f
    mov     x9, #0
2:  str     x9, [sp, #(L + 40)]
    mov     x9, #(NodeEvent_api_bytes + 24) /* the chunk's room: at most NODE_API_CHUNK */
    subs    x10, x5, x9
    b.lo    97f
    and     x10, x10, #~7
    MOVQ    x11, NODE_API_CHUNK
    cmp     x10, x11
    csel    x10, x11, x10, hi
    ldr     x9, [x22, #NodeApi_flags]
    tst     x9, #API_STREAM_STARTED
    mov     x11, #NODE_API_FIRST_ROOM
    mov     x12, #64
    csel    x11, x12, x11, ne
    ldr     x12, [sp, #(L + 40)]            /* a validator stream: an item in every chunk */
    cbz     x12, 3f
    cmp     x12, #3
    b.eq    3f
    cmp     x12, #7
    b.eq    3f
    mov     x11, #NODE_API_FIRST_ROOM
3:  cmp     x10, x11
    b.lo    97f
    add     x28, x23, #(NodeEvent_api_bytes + 24)
    add     x9, x28, x10
    str     x9, [sp, #L]
    ldr     x9, [sp, #(L + 40)]
    cbz     x9, 4f
    cmp     x9, #3
    b.eq    5f
    cmp     x9, #5
    b.eq    5f
    cmp     x9, #6
    b.eq    5f
    cmp     x9, #7
    b.eq    5f
    ldr     x11, [x20, #NODE_STATE_SLOT]    /* the state at the entry's slot */
    ldr     x12, [x22, #NodeApi_slot]
    cmp     x11, x12
    b.ne    95f
    b       5f
4:  ldr     x9, [x21, #8]                   /* the SSZ bytes */
    add     x9, x21, x9
    ldr     x10, [x21, #16]
    stp     x9, x10, [sp, #(L + 8)]
    ldr     x11, [x22, #NodeApi_op]         /* their slot: a state's at byte 40, a signed block's at 100 */
    cmp     x11, #API_OP_PRODUCE_BLOCK_V3
    b.eq    41f
    cmp     x11, #API_OP_GET_STATE_V2
    mov     x11, #40
    mov     x12, #100
    csel    x11, x11, x12, eq
    b       42f
41: mov     x11, #0                         /* produceBlockV3: a block's at 0, from deneb at the BlockContents' offset of its block */
    ldr     x12, [x22, #NodeApi_flags]      /* a blinded block's at 0 */
    tbnz    x12, #19, 42f
    ldr     x12, [x22, #NodeApi_fork]
    cmp     x12, #FORK_DENEB
    b.lo    42f
    cmp     x10, #4
    b.lo    96f
    ldr     w11, [x9]
42: add     x12, x11, #8
    cmp     x10, x12
    b.lo    96f
    ldr     x11, [x9, x11]
    ldr     x12, [x22, #NodeApi_slot]
    cmp     x11, x12
    b.ne    96f
    ldr     x13, [x22, #NodeApi_op]         /* getBlockAttestationsV2: the body's attestations, a ByteList at the end of scratch */
    cmp     x13, #API_OP_GET_BLINDED_BLOCK
    b.eq    52f
    cmp     x13, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    b.ne    5f
    ldp     x9, x10, [sp, #(L + 8)]
    ldr     w11, [x9]                       /* the message */
    add     x12, x11, #84
    cmp     x12, x10
    b.hi    96f
    add     x12, x9, x11
    ldr     w13, [x12, #80]                 /* its body */
    add     x11, x11, x13
    add     x12, x11, #216
    cmp     x12, x10
    b.hi    96f
    add     x12, x9, x11
    ldr     w13, [x12, #208]                /* the list: from attestations to deposits */
    ldr     w14, [x12, #212]
    cmp     x13, x14
    b.hi    96f
    add     x14, x11, x14
    cmp     x14, x10
    b.hi    96f
    add     x13, x11, x13
    sub     x14, x14, x13
    ldr     x25, [sp, #(L + 48)]            /* its bytes copied into a ByteList at the end of scratch */
    ldr     x12, [x25]
    add     x11, x14, #(24 + 7)
    and     x11, x11, #~7
    cmp     x12, x11
    b.lo    97f
    sub     x12, x12, x11
    add     x25, x25, x12
    mov     x10, #24
    stp     x11, x10, [x25]
    str     x14, [x25, #16]
    add     x0, x25, #24
    add     x1, x9, x13
    mov     x2, x14
    bl      lantern_copy
    mov     x21, x25
    b       5f
52: ldr     x25, [sp, #(L + 48)]            /* getBlindedBlock: lantern_node_blinded_block into a ByteList at the end of scratch, then its bytes */
    ldr     x12, [x25]
    ldr     x10, [sp, #(L + 16)]
    add     x11, x10, #(24 + 1024 + 7)
    and     x11, x11, #~7
    add     x13, x11, #64
    cmp     x12, x13
    b.lo    97f
    sub     x12, x12, x11
    str     x12, [x25]
    add     x2, x25, x12
    str     x11, [x2]
    mov     x0, x21
    mov     x1, x25
    mov     x21, x2
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_blinded_block
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    97f
    cbnz    x0, 96f
    ldr     x9, [x21, #8]
    add     x9, x21, x9
    ldr     x10, [x21, #16]
    stp     x9, x10, [sp, #(L + 8)]
5:  ldr     x9, [x22, #NodeApi_sent]        /* the entry's sent, flags and cursor go on in the event */
    str     x9, [x23, #NodeEvent_api]
    ldr     x9, [x22, #NodeApi_flags]
    str     x9, [x23, #(NodeEvent_api + 8)]
    add     x0, x23, #(NodeEvent_api + 16)
    add     x1, x22, #NodeApi_cursor
    mov     x2, #JSON_CURSOR_SIZE
    bl      lantern_copy
    mov     x24, x28                        /* the writer */
    mov     x25, #1
    ldr     x26, [sp, #L]
    mov     x27, #0
    ldr     x9, [sp, #(L + 40)]             /* a validator stream: its selection; getEpochCommittees its count */
    cbz     x9, 6f
    cmp     x9, #3
    b.eq    66f
    cmp     x9, #4
    b.eq    67f
    cmp     x9, #5
    b.eq    68f
    cmp     x9, #6
    b.eq    6f
    cmp     x9, #7
    b.eq    69f
    ldr     x0, [sp, #(L + 48)]
    cmp     x9, #2
    b.eq    63f
    bl      lantern_node_api_validators_prep
    cbnz    x0, 97f
    ldr     x9, [x22, #NodeApi_op]          /* getAttestationsRewards: the scratch after the bitmap, at +592 of the cursor */
    cmp     x9, #API_OP_GET_ATTESTATIONS_REWARDS
    b.ne    6f
    ldr     x0, [sp, #(L + 48)]
    LDQ     x10, x20, NODE_STATE_VALIDATORS + 8
    add     x10, x10, #63
    lsr     x10, x10, #6
    lsl     x10, x10, #3
    add     x10, x10, #16
    ldr     x11, [x0]
    subs    x11, x11, x10
    b.lo    97f
    add     x12, x0, x10
    str     x11, [x12]
    add     x13, x23, #(NodeEvent_api + 16)
    str     x12, [x13, #592]
    b       6f
66: cbz     x21, 6f                         /* getPoolAttestationsV2 from electra: the Attestation of a SingleAttestation */
    ldr     x9, [x22, #NodeApi_op]
    cmp     x9, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.ne    6f
    ldr     x9, [x22, #NodeApi_sent]
    cmp     x9, #FORK_ELECTRA
    b.lo    6f
    ldr     x0, [sp, #(L + 48)]
    mov     x1, x21
    ldr     x2, [x22, #NodeApi_member]
    bl      lantern_node_pool_attestation
    cmp     x0, #1
    b.eq    96f
    b.hi    97f
    mov     x21, x1
    b       6f
69: ldr     x9, [x23, #(NodeEvent_api + 8)] /* getAggregatedAttestationV2 */
    tbz     x9, #15, 693f
    cbz     x21, 691f
    ldr     x0, [sp, #(L + 48)]             /* a fold of the entry: no bytes */
    ldr     x10, [x22, #NodeApi_op]
    cmp     x10, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    b.eq    694f
    bl      lantern_node_api_fold
    b       695f
694: bl     lantern_node_api_sync_fold
695: cmp    x0, #1
    b.eq    96f
    b.hi    97f
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #API_STREAM_ITEM_DONE
    str     x9, [x23, #(NodeEvent_api + 8)]
    b       80f
691: mov    x10, #404                       /* the fold's end: none 404, optimistic 503, else the Attestation's bytes */
    ldr     x11, [x23, #(NodeEvent_api + 16 + 32)]
    cbz     x11, 692f
    mov     x10, #503
    tbnz    x9, #8, 692f
    mov     x0, x28
    ldr     x10, [x22, #NodeApi_op]
    cmp     x10, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    b.eq    696f
    bl      lantern_node_api_aggregate
    b       697f
696: bl     lantern_node_api_contribution
697: cbnz   x0, 96f
    add     x24, x28, x1
    b       80f
692: str    x10, [sp, #(L + 32)]
    b       641f
693: cbz    x21, 96f                        /* the answer: from the Attestation's bytes */
    ldr     x9, [x21, #8]
    add     x9, x21, x9
    ldr     x10, [x21, #16]
    stp     x9, x10, [sp, #(L + 8)]
    b       6f
67: mov     x0, x20                         /* a pending stream: its items; for SSZ their bytes and their count */
    ldr     x9, [x22, #NodeApi_op]
    sub     x1, x9, #API_OP_GET_PENDING_DEPOSITS
    cmp     x9, #API_OP_GET_PENDING_CONSOLIDATIONS
    mov     x10, #2
    csel    x1, x10, x1, eq
    add     x2, sp, #(L + 8)
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_pending
    cbnz    x0, 96f
    ldp     x9, x10, [sp, #(L + 16)]
    mul     x9, x9, x10
    str     x9, [sp, #(L + 16)]
    b       6f
68: orr     x9, x21, x20                    /* getBlockHeaders: an item's header at the end of scratch, x21 its address */
    cbz     x9, 6f
    ldr     x25, [sp, #(L + 48)]
    ldr     x12, [x25]
    cmp     x12, #(208 + 64)
    b.lo    97f
    sub     x12, x12, #208
    str     x12, [x25]
    add     x27, x25, x12
    cbz     x21, 681f
    ldr     x9, [x21, #16]                  /* of the bytes: lantern_node_block_header of the fork of their slot */
    cmp     x9, #108
    b.lo    96f
    ldr     x9, [x21, #8]
    add     x9, x21, x9
    ldr     x0, [x9, #100]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    mov     x0, x21
    mov     x1, x25
    mov     x2, x27
    FORK_CALL node_block_header
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    97f
    cbnz    x0, 96f
    b       683f
681: ldr    x9, [x20, #NODE_STATE_HEADER]   /* of the post-state: its latest_block_header, a zero signature */
    str     x9, [x27]
    add     x0, x27, #8
    add     x1, x20, #(NODE_STATE_HEADER + 8)
    mov     x2, #(112 - 8)
    bl      lantern_copy
    add     x0, x27, #112
    mov     x1, #96
    bl      lantern_zero
    ldp     x9, x10, [x27, #48]
    ldp     x11, x12, [x27, #64]
    orr     x9, x9, x10
    orr     x11, x11, x12
    orr     x9, x9, x11
    cbnz    x9, 683f
    ldr     x0, [x20, #NODE_STATE_SLOT]     /* a zero state_root: the state's root */
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    mov     x0, x20
    LDQ     x1, x19, Node_config + CONFIG_STATE_CACHE
    mov     x2, x25
    add     x3, x27, #48
    FORK_CALL state_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    97f
    cbnz    x0, 96f
683: mov    x21, x27
    mov     x25, #1                         /* the writer's x25 and x27 again */
    mov     x27, #0
    b       6f
63: bl      lantern_node_api_committees_prep
    cmp     x0, #400
    b.eq    64f
    cbnz    x0, 97f
    b       6f
64: mov     x9, #400                        /* an index past the count: the error 400 is the answer */
    str     x9, [sp, #(L + 32)]
641: add    x1, x23, #NodeEvent_api_bytes   /* the error of L + 32 is the answer */
    ldr     x9, [sp, #L]
    sub     x9, x9, x1
    str     x9, [x1]
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    and     x4, x9, #API_R_CLOSE
    cbnz    x4, 65f
    tst     x9, #API_STREAM_HTTP10
    mov     x10, #API_R_KEEP
    csel    x4, x10, xzr, ne
65: mov     x0, #0
    ldr     x2, [sp, #(L + 32)]
    mov     x3, #API_BODY_ERROR
    bl      lantern_api_respond
    cbnz    x0, 97f
    ldr     x9, [x23, #(NodeEvent_api_bytes + 16)]
    add     x24, x28, x9
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #API_STREAM_STARTED
    orr     x9, x9, #API_STREAM_DONE
    str     x9, [x23, #(NodeEvent_api + 8)]
    b       80f
6:  ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #2, 30f
    ldr     x10, [sp, #(L + 40)]
    cmp     x10, #6                         /* a sidecar stream: SSZ as a JSON answer */
    b.eq    30f
    cmp     x10, #4                         /* a pending stream: its SSZ bytes as getStateV2's */
    b.eq    601f
    cmp     x10, #7                         /* getAggregatedAttestationV2: the Attestation's SSZ bytes */
    b.eq    601f
    cbnz    x10, 60f
601: tbnz   x9, #6, 11f                     /* SSZ: the head first, with Content-Length */
    ldr     x0, [sp, #(L + 16)]
    bl      lantern_api_stream_head
11: ldp     x1, x10, [sp, #(L + 8)]         /* then the bytes from sent, as many as fit */
    ldr     x9, [x23, #NodeEvent_api]
    sub     x2, x10, x9
    sub     x11, x26, x24
    cmp     x2, x11
    csel    x2, x11, x2, hi
    add     x1, x1, x9
    add     x9, x9, x2
    str     x9, [x23, #NodeEvent_api]
    mov     x0, x24
    add     x24, x24, x2
    bl      lantern_copy
    ldr     x9, [x23, #NodeEvent_api]
    ldr     x10, [sp, #(L + 16)]
    ldr     x11, [x23, #(NodeEvent_api + 8)]
    orr     x11, x11, #API_STREAM_STARTED
    cmp     x9, x10
    b.ne    12f
    orr     x11, x11, #API_STREAM_DONE
12: str     x11, [x23, #(NodeEvent_api + 8)]
    b       80f
60: tbnz    x9, #6, 61f                     /* the identities as SSZ: Content-Length of 64 bytes each */
    add     x9, x23, #(NodeEvent_api + 16)
    ldr     x0, [x9, #40]
    lsl     x0, x0, #6
    bl      lantern_api_stream_head
61: bl      lantern_api_validators_json
    ldr     x11, [x23, #(NodeEvent_api + 8)]
    orr     x11, x11, #API_STREAM_STARTED
    cbz     x0, 62f
    orr     x11, x11, #API_STREAM_DONE
62: str     x11, [x23, #(NodeEvent_api + 8)]
    b       80f
30: tbnz    x9, #6, 40f                     /* JSON, the first chunk: the body after room for the head */
    add     x24, x28, #API_HEAD_ROOM
    ldr     x10, [x22, #NodeApi_op]
    cmp     x10, #API_OP_PRODUCE_BLOCK_V3
    b.ne    301f
    add     x24, x24, #API_PRODUCE_HEAD_ROOM
301: str    x24, [sp, #(L + 24)]
    ldr     x9, [sp, #L]
    sub     x26, x9, #7                     /* room for CRLF and the last chunk */
    ldr     x9, [sp, #(L + 40)]
    cbz     x9, 35f
    cmp     x9, #6                          /* a sidecar stream: as JSON the pending streams' head; as SSZ none */
    b.ne    393f
    ldr     x10, [x23, #(NodeEvent_api + 8)]
    tbnz    x10, #2, 36f
    ldr     x10, [x22, #NodeApi_op]          /* getBlobs: as the validator streams */
    cmp     x10, #API_OP_GET_BLOBS
    b.eq    37f
    b       392f
393: cmp    x9, #4
    b.eq    392f
    cmp     x9, #7                          /* getAggregatedAttestationV2: {"version":"<fork>","data": */
    b.ne    394f
    ldr     x10, [x22, #NodeApi_op]
    cmp     x10, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    b.ne    395f
    /* produceSyncCommitteeContribution: {"data": */
    API_LIT api_pe_data
    b       36f
395: API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      lantern_api_fork_name
    API_LIT api_g_data
    b       36f
394: cmp    x9, #3
    b.ne    37f                             /* getBlockHeaders: as the validator streams */
    ldr     x9, [x22, #NodeApi_op]          /* a pool stream: {"data":[, the V2 GETs {"version":"<fork>","data":[ */
    cmp     x9, #API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    b.eq    39f
    cmp     x9, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.ne    38f
39:
    API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      lantern_api_fork_name
    API_LIT api_p_version
    b       36f
38: API_LIT api_p_data
    b       36f
    /* the validator streams: {"execution_optimistic":…,"finalized":…,"data":[ */
37: API_LIT api_v_open
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #8, #1
    bl      lantern_api_bool
    API_LIT api_x_finalized
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #9, #1
    bl      lantern_api_bool
    ldr     x9, [x22, #NodeApi_op]          /* getAttestationsRewards: ,"data":{"ideal_rewards":[ */
    cmp     x9, #API_OP_GET_ATTESTATIONS_REWARDS
    b.ne    371f
    API_LIT api_ar_open
    b       36f
371: API_LIT api_v_list
    b       36f
    /* the pending streams: {"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[ */
392: API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      lantern_api_fork_name
    API_LIT api_j_optimistic
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #8, #1
    bl      lantern_api_bool
    API_LIT api_x_finalized
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #9, #1
    bl      lantern_api_bool
    API_LIT api_v_list
    b       36f
    /* {"version":"<fork>","execution_optimistic":…,"finalized":…,"data": */
35: ldr     x9, [x22, #NodeApi_op]          /* produceBlockV3: {"version":…,"execution_payload_blinded":false,…,"data": */
    cmp     x9, #API_OP_PRODUCE_BLOCK_V3
    b.ne    351f
    API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      lantern_api_fork_name
    ldr     x9, [x22, #NodeApi_flags]       /* blinded with API_STREAM_PRODUCE_BLINDED */
    tbnz    x9, #19, 3521f
    API_LIT api_pb_head
    b       3522f
3521: API_LIT api_pb_head_true
3522: add   x0, x22, #NodeApi_root
    bl      lantern_api_dec256
    API_LIT api_pb_block_value
    ldr     x0, [x22, #NodeApi_filter_slot]
    bl      lantern_api_wei
    API_LIT api_g_data
    b       36f
351: API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      lantern_api_fork_name
    API_LIT api_j_optimistic
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #8, #1
    bl      lantern_api_bool
    API_LIT api_x_finalized
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #9, #1
    bl      lantern_api_bool
    API_LIT api_j_data
36: bl      lantern_api_stream_json
    cmp     x0, #3
    b.eq    97f
    cmp     x0, #2
    b.eq    96f
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #API_STREAM_STARTED
    mov     x10, #-1                        /* not whole: chunked, or for HTTP/1.0 no length and a close */
    cbz     x0, 31f
    orr     x9, x9, #API_STREAM_DONE        /* whole: Content-Length */
    ldr     x10, [sp, #(L + 24)]
    sub     x10, x24, x10
    b       33f
31: tst     x9, #API_STREAM_HTTP10
    b.eq    32f
    orr     x9, x9, #API_STREAM_CLOSE
    b       33f
32: orr     x9, x9, #API_STREAM_CHUNKED
33: str     x9, [x23, #(NodeEvent_api + 8)]
    str     x10, [sp, #(L + 32)]
    ldr     x9, [sp, #(L + 24)]             /* the body's bytes */
    sub     x9, x24, x9
    str     x9, [sp, #(L + 16)]
    mov     x25, #0                         /* the head's bytes: a pass that counts */
    mov     x24, #0
    ldr     x0, [sp, #(L + 32)]
    bl      lantern_api_stream_head
    add     x0, x28, x24                    /* the body after the head, and a size line when chunked */
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tst     x9, #API_STREAM_CHUNKED
    add     x10, x0, #6
    csel    x0, x10, x0, ne
    ldr     x1, [sp, #(L + 24)]
    ldr     x2, [sp, #(L + 16)]
    add     x9, x0, x2
    str     x9, [sp, #(L + 24)]             /* now the body's end */
    bl      lantern_copy
    mov     x25, #1                         /* the head */
    mov     x24, x28
    ldr     x26, [sp, #L]
    ldr     x0, [sp, #(L + 32)]
    bl      lantern_api_stream_head
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #7, 34f
    ldr     x0, [sp, #(L + 16)]             /* chunked: the size line, then CRLF after the bytes */
    mov     x1, x24
    bl      lantern_api_hex4
    mov     w9, #0x0a0d
    strh    w9, [x24, #4]
    ldr     x24, [sp, #(L + 24)]
    API_LIT api_crlf
    b       80f
34: ldr     x24, [sp, #(L + 24)]
    b       80f
40: tbz     x9, #7, 45f                     /* JSON, a later chunk; chunked: a size line, the bytes, CRLF */
    add     x24, x28, #6
    ldr     x9, [sp, #L]
    sub     x26, x9, #7
    bl      lantern_api_stream_json
    cmp     x0, #3
    b.eq    97f
    cmp     x0, #2
    b.eq    96f
    str     x0, [sp, #(L + 32)]
    sub     x9, x24, x28                    /* no bytes: no chunk of them, the last chunk alone */
    cmp     x9, #6
    b.ne    41f
    mov     x24, x28
    ldr     x26, [sp, #L]
    cbz     x0, 80f
    API_LIT api_last_chunk
    b       44f
41: sub     x0, x24, x28
    sub     x0, x0, #6
    mov     x1, x28
    bl      lantern_api_hex4
    mov     w9, #0x0a0d
    strh    w9, [x28, #4]
    ldr     x26, [sp, #L]
    API_LIT api_crlf
    ldr     x9, [sp, #(L + 32)]
    cbz     x9, 80f
    API_LIT api_last_chunk
    b       44f
45: bl      lantern_api_stream_json                 /* HTTP/1.0: the bytes alone */
    cmp     x0, #3
    b.eq    97f
    cmp     x0, #2
    b.eq    96f
    cbz     x0, 80f
44: ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #API_STREAM_DONE
    str     x9, [x23, #(NodeEvent_api + 8)]
80: sub     x9, x24, x28                    /* the chunk's ByteList; the event's size covers it */
    add     x10, x9, #(24 + 7)
    and     x10, x10, #~7
    add     x11, x23, #NodeEvent_api_bytes
    mov     x12, #24
    stp     x10, x12, [x11]
    str     x9, [x11, #16]
    add     x12, x10, #NodeEvent_api_bytes
    str     x12, [x23]
    mov     x0, x24
    sub     x1, x10, #24
    sub     x1, x1, x9
    bl      lantern_zero
    mov     x0, #LANTERN_OK
    LEAVE 64
95: mov     x9, #LANTERN_INVALID_SLOT       /* a state at another slot */
    b       94f
96: mov     x9, #LANTERN_INVALID_ENCODING   /* bytes that are no encoding of the type */
94: str     x9, [x23, #NodeEvent_result]
    mov     x9, #NODE_EV_WORK_DONE_SIZE
    str     x9, [x23]
    mov     x0, #LANTERN_OK
    LEAVE 64
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 64
98: mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 64
END_FUNCTION lantern_node_api_chunk_run

/* ------------------------------------------------------------ The pools (beacon-api.md, node.md) */

/*
 * L1: (scratch x0, the ByteList x1 of a SingleAttestation, member x2) -> x0: the electra Attestation
 * of it as a ByteList at the end of scratch, at x1 (node.md, NODE_WORK_API_CHUNK, the pool streams):
 * aggregation_bits of the length member / 2^16 with the bit of the place member % 2^16, data,
 * signature, committee_bits with the bit of committee_index. x0 = 0; 1 for bytes of another size,
 * a place not below the length, a length above MAX_VALIDATORS_PER_COMMITTEE or a committee_index
 * not below MAX_COMMITTEES_PER_SLOT; 2 for a scratch without NODE_POOL_ATTESTATION_ROOM bytes.
 * Locals: the ByteList, the SingleAttestation, the committee index, the place, the length.
 */
LOCAL_FUNCTION lantern_node_pool_attestation
    FRAME 48
    ldr     x9, [x1, #16]
    cmp     x9, #240
    b.ne    81f
    ldr     x9, [x1, #8]
    add     x10, x1, x9
    ldr     x11, [x10]
    cmp     x11, #MAX_COMMITTEES_PER_SLOT
    b.hs    81f
    and     x12, x2, #0xffff
    lsr     x13, x2, #16
    cmp     x13, #MAX_VALIDATORS_PER_COMMITTEE
    b.hi    81f
    cmp     x12, x13
    b.hs    81f
    ldr     x14, [x0]
    cmp     x14, #NODE_POOL_ATTESTATION_ROOM
    b.lo    82f
    add     x15, x0, x14
    sub     x15, x15, #NODE_POOL_ATTESTATION_ROOM
    str     x15, [sp, #16]
    stp     x10, x11, [sp, #24]
    stp     x12, x13, [sp, #40]
    add     x0, x15, #24
    mov     x1, #(NODE_POOL_ATTESTATION_ROOM - 24)
    bl      lantern_zero
    ldr     x15, [sp, #16]                  /* its head: size, offset 24, count */
    mov     x9, #NODE_POOL_ATTESTATION_ROOM
    mov     x10, #24
    stp     x9, x10, [x15]
    ldr     x13, [sp, #48]
    lsr     x9, x13, #3
    add     x9, x9, #(NODE_POOL_ATTESTATION_FIXED + 1)
    str     x9, [x15, #16]
    mov     x9, #NODE_POOL_ATTESTATION_FIXED    /* the offset of aggregation_bits, data and signature */
    str     w9, [x15, #24]
    add     x0, x15, #28
    ldr     x1, [sp, #24]
    add     x1, x1, #16
    mov     x2, #(128 + 96)
    bl      lantern_copy
    ldr     x15, [sp, #16]
    add     x9, x15, #(24 + 4 + 128 + 96)   /* committee_bits */
    ldr     x11, [sp, #32]
    lsr     x10, x11, #3
    and     x11, x11, #7
    mov     x12, #1
    lsl     x12, x12, x11
    strb    w12, [x9, x10]
    add     x9, x15, #(24 + NODE_POOL_ATTESTATION_FIXED)    /* aggregation_bits: the place, then the length's bit */
    ldp     x12, x13, [sp, #40]
    lsr     x10, x12, #3
    and     x11, x12, #7
    mov     x14, #1
    lsl     x14, x14, x11
    ldrb    w11, [x9, x10]
    orr     w11, w11, w14
    strb    w11, [x9, x10]
    lsr     x10, x13, #3
    and     x11, x13, #7
    mov     x14, #1
    lsl     x14, x14, x11
    ldrb    w11, [x9, x10]
    orr     w11, w11, w14
    strb    w11, [x9, x10]
    ldr     x1, [sp, #16]
    mov     x0, #0
    UNFRAME 48
81: mov     x0, #1
    UNFRAME 48
82: mov     x0, #2
    UNFRAME 48
END_FUNCTION lantern_node_pool_attestation

/* L1: x0 = the new id of a NODE_ACT_BYTES_PUT of the 8 bytes at x0. Locals: a ByteList head whose offset reaches them. */
LOCAL_FUNCTION lantern_node_api_put8
    FRAME 32
    add     x9, sp, #16
    sub     x10, x0, x9
    mov     x11, #8
    stp     x11, x10, [x9]
    str     x11, [x9, #16]
    mov     x0, x9
    bl      lantern_node_put
    UNFRAME 32
END_FUNCTION lantern_node_api_put8

/* L0: x0 = the gossip topic of the pool POST x0, or 0. Uses x9. */
LOCAL_FUNCTION lantern_node_submit_topic
    UNWIND_END_PROLOGUE
    mov     x9, x0
    mov     x0, #GOSSIP_VOLUNTARY_EXIT
    cmp     x9, #API_OP_SUBMIT_POOL_VOLUNTARY_EXIT
    b.eq    9f
    mov     x0, #GOSSIP_PROPOSER_SLASHING
    cmp     x9, #API_OP_SUBMIT_POOL_PROPOSER_SLASHINGS
    b.eq    9f
    mov     x0, #GOSSIP_ATTESTER_SLASHING
    cmp     x9, #API_OP_SUBMIT_POOL_ATTESTER_SLASHINGS_V2
    b.eq    9f
    mov     x0, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    cmp     x9, #API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    b.eq    9f
    mov     x0, #GOSSIP_BEACON_ATTESTATION
    cmp     x9, #API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    b.eq    9f
    mov     x0, #GOSSIP_BEACON_AGGREGATE_AND_PROOF
    cmp     x9, #API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2
    b.eq    9f
    mov     x0, #GOSSIP_SYNC_COMMITTEE
    cmp     x9, #API_OP_SUBMIT_POOL_SYNC_COMMITTEE_SIGNATURES
    b.eq    9f
    mov     x0, #GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF
    cmp     x9, #API_OP_PUBLISH_CONTRIBUTION_AND_PROOFS
    b.eq    9f
    mov     x0, #0
9:  ret
END_FUNCTION lantern_node_submit_topic

/* L0: x0 = the lantern_node_json kind of the pool operation of the gossip topic x0. Uses x9. */
LOCAL_FUNCTION lantern_node_pool_kind
    UNWIND_END_PROLOGUE
    cmp     x0, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    mov     x9, #NODE_JSON_BLS_CHANGE
    sub     x0, x0, #(GOSSIP_VOLUNTARY_EXIT - NODE_JSON_EXIT)
    csel    x0, x9, x0, eq
    ret
END_FUNCTION lantern_node_pool_kind
.if GOSSIP_PROPOSER_SLASHING - GOSSIP_VOLUNTARY_EXIT != NODE_JSON_PROPOSER_SLASHING - NODE_JSON_EXIT || GOSSIP_ATTESTER_SLASHING - GOSSIP_VOLUNTARY_EXIT != NODE_JSON_ATTESTER_SLASHING - NODE_JSON_EXIT
.error "node_pool_kind: the kinds follow the topics"
.endif

/*
 * L0: x0 = the index of the first pool entry from the index x0 that the pool stream x1 answers
 * (node.md, NODE_EV_API): of its topic; for getPoolAttesterSlashingsV2 and getPoolAttestationsV2
 * of the type of its fork, and for getPoolAttestationsV2 of its filters; else 2^64 - 1. x1 = the
 * entry. Uses x2, x9-x14.
 */
LOCAL_FUNCTION lantern_node_pool_next
    UNWIND_END_PROLOGUE
    ldr     x10, [x1, #NodeApi_op]
    mov     x9, #GOSSIP_VOLUNTARY_EXIT
    cmp     x10, #API_OP_GET_POOL_VOLUNTARY_EXITS
    b.eq    1f
    mov     x9, #GOSSIP_PROPOSER_SLASHING
    cmp     x10, #API_OP_GET_POOL_PROPOSER_SLASHINGS
    b.eq    1f
    mov     x9, #GOSSIP_ATTESTER_SLASHING
    cmp     x10, #API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    b.eq    1f
    mov     x9, #GOSSIP_BEACON_ATTESTATION
    cmp     x10, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.eq    1f
    cmp     x10, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.eq    1f
    mov     x9, #GOSSIP_SYNC_COMMITTEE
    cmp     x10, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    b.eq    1f
    mov     x9, #GOSSIP_BLS_TO_EXECUTION_CHANGE
1:  ldr     x13, [x1, #NodeApi_filter_slot]
    ldr     x14, [x1, #NodeApi_filter_index]
    ldr     x2, [x1, #NodeApi_fork]
    cmp     x2, #FORK_ELECTRA
    cset    x2, hs
    PART    x10, x11, x19, Node_pool
    mov     x12, #NodePool__mem
    madd    x10, x0, x12, x10
2:  cmp     x0, x11
    b.hs    8f
    ldr     x12, [x10, #NodePool_topic]
    cmp     x12, x9
    b.ne    3f
    cmp     x9, #GOSSIP_ATTESTER_SLASHING
    b.eq    21f
    cmp     x9, #GOSSIP_SYNC_COMMITTEE
    b.eq    22f
    cmp     x9, #GOSSIP_BEACON_ATTESTATION
    b.ne    4f
    ldr     x12, [x10, #NodePool_slot]      /* an attestation: of the filters */
    cmn     x13, #1
    b.eq    20f
    cmp     x12, x13
    b.ne    3f
20: ldr     x12, [x10, #NodePool_index]
    cmn     x14, #1
    b.eq    21f
    cmp     x12, x14
    b.ne    3f
21: ldr     x12, [x10, #NodePool_fork]
    cmp     x12, #FORK_ELECTRA
    cset    x12, hs
    cmp     x12, x2
    b.eq    4f
3:  add     x10, x10, #NodePool__mem
    add     x0, x0, #1
    b       2b
22: ldr     x12, [x10, #NodePool_slot]      /* a sync message: of the slot, valid on the subnet */
    cmp     x12, x13
    b.ne    3b
    ldr     x12, [x10, #NodePool_index]
    lsr     x12, x12, x14
    tbz     x12, #0, 3b
4:  mov     x1, x10
    ret
8:  mov     x0, #-1
    ret
END_FUNCTION lantern_node_pool_next

/*
 * L1: (connection x0, route x1, flags x2, view x3): a stream of a pool GET (node.md, NODE_EV_API):
 * fork the store's, the filters of getPoolAttestationsV2; slot the first entry it answers, data
 * its bytes, sent its fork, member its member; data 0 with none. flags: API_STREAM_CLOSE and
 * API_STREAM_HTTP10. Locals: the connection, the route, the flags, the fork, the entry's index
 * and address.
 */
LOCAL_FUNCTION lantern_node_api_pool_stream
    FRAME 48
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    ldr     x9, [x3, #ApiView_fork]
    str     x9, [sp, #40]
    bl      lantern_node_api_new
    stp     x0, x1, [sp, #48]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x1, [sp, #56]
    ldp     x9, x10, [sp, #16]
    str     x9, [x1, #NodeApi_connection]
    ldr     x11, [x10, #ApiRoute_op]
    str     x11, [x1, #NodeApi_op]
    ldr     x9, [sp, #32]
    str     x9, [x1, #NodeApi_flags]
    ldr     x2, [sp, #40]
    str     x2, [x1, #NodeApi_fork]
    mov     x12, #-1                        /* the filters: getPoolAttestationsV2's slot and committee_index */
    mov     x13, #-1
    cmp     x11, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.eq    21f
    cmp     x11, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    b.eq    23f
    cmp     x11, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.ne    2f
    ldr     x9, [x1, #NodeApi_flags]        /* getAggregatedAttestationV2: a fold, SSZ, attestation_data_root in cursor */
    orr     x9, x9, #API_STREAM_FOLD
    ldr     x14, [x10, #ApiRoute_response]
    cmp     x14, #API_TYPE_SSZ
    orr     x14, x9, #API_STREAM_SSZ
    csel    x9, x14, x9, eq
    str     x9, [x1, #NodeApi_flags]
    add     x14, x10, #ApiRoute_root
    ldp     x15, x9, [x14]
    stp     x15, x9, [x1, #NodeApi_cursor]
    ldp     x15, x9, [x14, #16]
    stp     x15, x9, [x1, #(NodeApi_cursor + 16)]
21: ldr     x9, [x10, #ApiRoute_present]
    ldr     x14, [x10, #ApiRoute_slot]
    tst     x9, #(1 << API_PARAM_SLOT)
    csel    x12, x14, x12, ne
    ldr     x14, [x10, #ApiRoute_committee_index]
    tst     x9, #(1 << API_PARAM_COMMITTEE_INDEX)
    csel    x13, x14, x13, ne
2:  str     x12, [x1, #NodeApi_filter_slot]
    str     x13, [x1, #NodeApi_filter_index]
24: mov     x0, #0
    bl      lantern_node_pool_next
    ldr     x9, [sp, #56]
    cmn     x0, #1
    b.eq    1f
    str     x0, [x9, #NodeApi_slot]
    ldr     x10, [x1, #NodePool_data_id]
    str     x10, [x9, #NodeApi_data]
    ldr     x10, [x1, #NodePool_fork]
    str     x10, [x9, #NodeApi_sent]
    ldr     x10, [x1, #NodePool_member]
    str     x10, [x9, #NodeApi_member]
3:  ldp     x0, x1, [sp, #48]
    bl      lantern_node_api_chunk_work
    mov     x0, #0
    UNFRAME 48
1:  ldr     x10, [x9, #NodeApi_op]          /* none: the folds 404, and no stream */
    cmp     x10, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    mov     x11, #API_OP_PRODUCE_SYNC_COMMITTEE_CONTRIBUTION
    ccmp    x10, x11, #4, ne
    b.ne    3b
    mov     x0, x9
    bl      lantern_node_api_end
    mov     x0, #404
    UNFRAME 48
23: ldr     x9, [x10, #ApiRoute_subcommittee_index] /* produceSyncCommitteeContribution: a fold of slot and subcommittee_index, */
    cmp     x9, #SYNC_COMMITTEE_SUBNET_COUNT        /* beacon_block_root in cursor, the head's post-state; 400, 500 */
    b.hs    25f
    str     x9, [x1, #NodeApi_filter_index]
    ldr     x9, [x10, #ApiRoute_slot]
    str     x9, [x1, #NodeApi_filter_slot]
    ldr     x9, [x1, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_FOLD
    str     x9, [x1, #NodeApi_flags]
    add     x14, x10, #ApiRoute_root
    ldp     x15, x9, [x14]
    stp     x15, x9, [x1, #NodeApi_cursor]
    ldp     x15, x9, [x14, #16]
    stp     x15, x9, [x1, #(NodeApi_cursor + 16)]
    add     x0, x19, #Node_head_root
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    26f
    ldr     x9, [x1, #NodeBlock_state_id]
    cbz     x9, 26f
    ldr     x1, [sp, #56]
    str     x9, [x1, #NodeApi_state]
    b       24b
25: ldr     x0, [sp, #56]
    bl      lantern_node_api_end
    mov     x0, #400
    UNFRAME 48
26: ldr     x0, [sp, #56]
    bl      lantern_node_api_end
    mov     x0, #500
    UNFRAME 48
END_FUNCTION lantern_node_api_pool_stream

/*
 * L1: the item of the getBlockHeaders stream x0 at or after the position x1 (node.md, NODE_EV_API, an
 * item of getBlockHeaders): position 0 the Db's block of the query, i + 1 the NodeBlock at index i.
 * Its slot (the position), data, state, member (1 on the chain, + 2 optimistic, + 4 finalized) and
 * its root at byte 0 of cursor; x0 = 1, or 0 with data and state 0 for none. x21 the entry, x22 the
 * position, x23 the slot of the query or 2^64 - 1, x24 the address of its parent_root or 0, x25 a
 * NodeBlock index, x26 a slot or an entry, x27 the member. Locals: L a slot.
 */
LOCAL_FUNCTION lantern_node_headers_next
    ENTER 16
    mov     x21, x0
    mov     x22, x1
    ldr     x23, [x21, #NodeApi_filter_slot]
    ldr     x9, [x21, #(NodeApi_cursor + 64)]
    add     x24, x21, #(NodeApi_cursor + 32)
    cmp     x9, #0
    csel    x24, x24, xzr, ne
    cbnz    x22, 20f
    ldr     x9, [x19, #Node_flags]          /* position 0: with NODE_FLAG_DB, the Db's block of the query */
    tst     x9, #NODE_FLAG_DB
    b.eq    19f
    cbz     x24, 15f
    mov     x0, x24                         /* with parent_root: its slot r, of the node's imported block on the chain, else of the Db */
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    11f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    11f
    mov     x25, x1
    mov     x0, x1
    bl      lantern_node_api_on_chain
    cbz     x0, 19f
    ldr     x26, [x25, #NodeBlock_slot]
    b       12f
11: ldr     x0, [x19, #Node_db]
    add     x0, x19, x0
    mov     x1, x24
    add     x2, sp, #L
    bl      lantern_db_find_root
    ldr     x26, [sp, #L]
    cmn     x26, #1
    b.eq    19f
12: add     x26, x26, #1                    /* the first slot above r whose block is in the Db, below the chain the node keeps */
    cmp     x26, x23
    b.hi    19f                             /* with slot: at most slot */
    mov     x0, x26
    bl      lantern_node_api_below
    cmn     x0, #1
    b.ne    19f
    mov     x0, x26
    bl      lantern_node_db_slot
    cbz     x0, 12b
    cmn     x23, #1
    b.eq    16f
    cmp     x26, x23
    b.ne    19f
    b       16f
15: mov     x26, x23                        /* slot alone: the Db's block of slot, below the chain the node keeps */
    mov     x0, x26
    bl      lantern_node_api_below
    cmn     x0, #1
    b.ne    19f
    mov     x0, x26
    bl      lantern_node_db_slot
    cbz     x0, 19f
16: mov     x1, x0                          /* the Db's block of slot x26: its DbSlot x0, the root at 0 */
    add     x0, x21, #NodeApi_cursor
    bl      lantern_copy_root
    mov     x0, x26
    bl      lantern_node_db_block
    str     x0, [x21, #NodeApi_data]
    str     xzr, [x21, #NodeApi_state]
    str     xzr, [x21, #NodeApi_slot]
    mov     x0, x26
    bl      lantern_node_api_final_block
    lsl     x27, x0, #2
    orr     x27, x27, #1                    /* on the chain, not optimistic */
    str     x27, [x21, #NodeApi_member]
    mov     x0, #1
    LEAVE 16
19: mov     x22, #1
20: PART    x10, x11, x19, Node_blocks      /* the node's imported blocks from the index x22 - 1 */
    sub     x25, x22, #1
    cmp     x25, x11
    b.hs    29f
    mov     x12, #NodeBlock__mem
    madd    x26, x25, x12, x10
    ldr     x9, [x26, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    28f
    cmn     x23, #1
    b.eq    22f
    ldr     x9, [x26, #NodeBlock_slot]
    cmp     x9, x23
    b.ne    28f
22: cbz     x24, 23f
    add     x9, x26, #NodeBlock_parent_root
    NE32    x9, x24, 28f
23: ldr     x0, [x26, #NodeBlock_data_id]   /* its bytes, else its Db record, else its post-state */
    cbnz    x0, 24f
    mov     x0, x26
    bl      lantern_node_api_db_ref
24: str     x0, [x21, #NodeApi_data]
    mov     x9, #0
    cbnz    x0, 25f
    ldr     x9, [x26, #NodeBlock_state_id]
    cbz     x9, 28f                         /* neither: left out */
25: str     x9, [x21, #NodeApi_state]
    str     x22, [x21, #NodeApi_slot]
    add     x0, x21, #NodeApi_cursor
    mov     x1, x26
    bl      lantern_copy_root
    ldr     x9, [x26, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x27, eq
    lsl     x27, x27, #1
    mov     x0, x26
    bl      lantern_node_api_on_chain
    orr     x27, x27, x0
    cbz     x0, 26f
    ldr     x0, [x26, #NodeBlock_slot]
    bl      lantern_node_api_final_block
    orr     x27, x27, x0, lsl #2
26: str     x27, [x21, #NodeApi_member]
    mov     x0, #1
    LEAVE 16
28: add     x22, x22, #1
    b       20b
29: str     xzr, [x21, #NodeApi_data]
    str     xzr, [x21, #NodeApi_state]
    mov     x0, #0
    LEAVE 16
END_FUNCTION lantern_node_headers_next

/*
 * L1: (connection x0, route x1, flags x2): the getBlockHeaders stream of the route's query (node.md,
 * NODE_EV_API): filter_slot its slot, the head's slot with neither slot nor parent_root, else
 * 2^64 - 1; its parent_root at byte 32 of cursor and 1 at byte 64; API_STREAM_OPTIMISTIC and
 * API_STREAM_FINALIZED of all its items; then its first item and a NODE_WORK_API_CHUNK. Locals: the
 * connection, the route, the flags, the entry's index and address, the position.
 */
LOCAL_FUNCTION lantern_node_api_headers_stream
    FRAME 48
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    bl      lantern_node_api_new
    stp     x0, x1, [sp, #40]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x1, [sp, #48]
    ldp     x9, x10, [sp, #16]
    str     x9, [x1, #NodeApi_connection]
    mov     x9, #API_OP_GET_BLOCK_HEADERS
    str     x9, [x1, #NodeApi_op]
    ldr     x9, [x10, #ApiRoute_present]
    mov     x12, #-1
    tst     x9, #(1 << API_PARAM_PARENT_ROOT)
    b.eq    1f
    add     x0, x1, #(NodeApi_cursor + 32)
    add     x1, x10, #ApiRoute_root
    bl      lantern_copy_root
    ldr     x1, [sp, #48]
    mov     x9, #1
    str     x9, [x1, #(NodeApi_cursor + 64)]
    mov     x12, #-1
    b       2f
1:  add     x0, x19, #Node_head_root        /* neither: the head's slot */
    bl      lantern_node_find_block
    mov     x12, #-1
    cmn     x0, #1
    b.eq    2f
    ldr     x12, [x1, #NodeBlock_slot]
2:  ldp     x9, x10, [sp, #16]
    ldr     x11, [x10, #ApiRoute_present]
    ldr     x13, [x10, #ApiRoute_slot]
    tst     x11, #(1 << API_PARAM_SLOT)
    csel    x12, x13, x12, ne
    ldr     x1, [sp, #48]
    str     x12, [x1, #NodeApi_filter_slot]
    mov     x9, #API_STREAM_FINALIZED       /* the flags of all items: optimistic of any, finalized of each, and of some */
    ldr     x10, [sp, #32]
    orr     x9, x9, x10
    str     x9, [x1, #NodeApi_flags]
    str     xzr, [sp, #56]
    mov     x9, #0                          /* the items */
    str     x9, [sp, #24]
3:  ldr     x0, [sp, #48]
    ldr     x1, [sp, #56]
    bl      lantern_node_headers_next
    ldr     x1, [sp, #48]
    cbz     x0, 5f
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    ldr     x10, [x1, #NodeApi_member]
    ldr     x11, [x1, #NodeApi_flags]
    tst     x10, #2
    orr     x12, x11, #API_STREAM_OPTIMISTIC
    csel    x11, x12, x11, ne
    tst     x10, #4
    and     x12, x11, #~API_STREAM_FINALIZED
    csel    x11, x12, x11, eq
    str     x11, [x1, #NodeApi_flags]
    ldr     x9, [x1, #NodeApi_slot]
    add     x9, x9, #1
    str     x9, [sp, #56]
    b       3b
5:  ldr     x9, [sp, #24]
    cbnz    x9, 6f
    ldr     x11, [x1, #NodeApi_flags]
    and     x11, x11, #~API_STREAM_FINALIZED
    str     x11, [x1, #NodeApi_flags]
6:  ldr     x0, [sp, #48]                   /* the first item */
    mov     x1, #0
    bl      lantern_node_headers_next
    ldp     x0, x1, [sp, #40]
    bl      lantern_node_api_chunk_work
    UNFRAME 48
END_FUNCTION lantern_node_api_headers_stream

/*
 * L1: x0 = the data of the sidecar of index x2 of the block of the root at x0 and the slot x1, as a
 * sidecar stream finds it (node.md): the NODE_BLOB_VALID entry's bytes, else with NODE_FLAG_DB the
 * NODE_DB_REF of the Db's record; 0 with none. Locals: the slot, the index.
 */
LOCAL_FUNCTION lantern_node_sidecar_of
    FRAME 16
    stp     x1, x2, [sp, #16]
    mov     x1, x2
    bl      lantern_node_blob_held
    cbz     x0, 1f
    ldr     x0, [x0, #NodeBlob_data_id]
    UNFRAME 16
1:  ldr     x9, [x19, #Node_flags]
    tst     x9, #NODE_FLAG_DB
    b.eq    9f
    ldp     x0, x1, [sp, #16]
    bl      lantern_node_db_sidecar
    UNFRAME 16
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION lantern_node_sidecar_of

/*
 * L1: (connection x0, route x1, flags x2, view x3) -> x0: the blob stream of the block of the
 * view (node.md, NODE_EV_API, the blob stream): 0, or 404 for a fulu block of which the node holds
 * a column sidecar but not one of each of the first NUMBER_OF_COLUMNS / 2 columns. Locals: the
 * connection, the route, the flags, the view, the fork, the entry's index and address, a column,
 * the count of the first half's columns held, 1 with any held, a ByteList head (24).
 */
LOCAL_FUNCTION lantern_node_api_blob_stream
    FRAME 112
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    ldr     x0, [x3, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    str     x0, [sp, #48]
    stp     xzr, xzr, [sp, #80]
    cmp     x0, #FORK_FULU
    b.lo    2f
    str     xzr, [sp, #72]
1:  ldr     x2, [sp, #72]                   /* fulu: the columns the node holds */
    cmp     x2, #NUMBER_OF_COLUMNS
    b.hs    11f
    ldr     x3, [sp, #40]
    add     x0, x3, #ApiView_head_root
    ldr     x1, [x3, #ApiView_head_slot]
    bl      lantern_node_sidecar_of
    ldr     x2, [sp, #72]
    add     x9, x2, #1
    str     x9, [sp, #72]
    cbz     x0, 1b
    mov     x9, #1
    str     x9, [sp, #88]
    cmp     x2, #(NUMBER_OF_COLUMNS / 2)
    b.hs    1b
    ldr     x9, [sp, #80]
    add     x9, x9, #1
    str     x9, [sp, #80]
    b       1b
11: ldp     x9, x10, [sp, #80]
    cmp     x9, #(NUMBER_OF_COLUMNS / 2)
    b.eq    2f
    cbnz    x10, 8f                         /* some, but not each of the first half: 404 */
2:  bl      lantern_node_api_new
    stp     x0, x1, [sp, #56]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x1, [sp, #64]
    ldp     x9, x10, [sp, #16]
    str     x9, [x1, #NodeApi_connection]
    ldr     x11, [x10, #ApiRoute_op]
    str     x11, [x1, #NodeApi_op]
    ldr     x9, [sp, #32]                   /* the answer flags, SSZ, and the block's values */
    ldr     x11, [x10, #ApiRoute_response]
    cmp     x11, #API_TYPE_SSZ
    orr     x11, x9, #API_STREAM_SSZ
    csel    x9, x11, x9, eq
    ldr     x12, [sp, #40]
    ldr     x11, [x12, #ApiView_is_optimistic]
    cbz     x11, 3f
    orr     x9, x9, #API_STREAM_OPTIMISTIC
3:  LDQ     x11, x12, ApiView_head_finalized
    cbz     x11, 4f
    orr     x9, x9, #API_STREAM_FINALIZED
4:  str     x9, [x1, #NodeApi_flags]
    ldr     x9, [sp, #48]
    str     x9, [x1, #NodeApi_fork]
    ldr     x9, [x12, #ApiView_head_slot]
    str     x9, [x1, #NodeApi_slot]
    add     x0, x1, #NodeApi_root
    add     x1, x12, #ApiView_head_root
    bl      lantern_copy_root
    ldr     x10, [sp, #24]                  /* the versioned hashes: a BYTES_PUT of them, as the entry's state */
    ldr     x9, [x10, #ApiRoute_present]
    tst     x9, #(1 << API_PARAM_VERSIONED_HASHES)
    b.eq    5f
    ldp     x11, x12, [x10, #ApiRoute_list]
    add     x11, x10, x11
    lsl     x12, x12, #5
    add     x13, sp, #96                    /* a ByteList head whose offset reaches the items */
    sub     x14, x11, x13
    stp     x12, x14, [x13]
    str     x12, [x13, #16]
    mov     x0, x13
    bl      lantern_node_put
    ldr     x1, [sp, #64]
    str     x0, [x1, #NodeApi_state]
    ldr     x9, [x1, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_OWN_STATE
    str     x9, [x1, #NodeApi_flags]
5:  ldr     x1, [sp, #64]                   /* the first item */
    ldr     x9, [sp, #48]
    cmp     x9, #FORK_DENEB
    b.lo    7f
    cmp     x9, #FORK_FULU
    b.hs    6f
    mov     x9, #-1                         /* deneb and electra: every sidecar */
    str     x9, [x1, #NodeApi_filter_slot]
    str     x9, [x1, #NodeApi_filter_index]
    mov     x0, x1
    mov     x1, #0
    bl      lantern_node_sidecar_next
    b       7f
6:  ldr     x9, [sp, #80]                   /* fulu: blob 0 and column 0 with the first half; else none */
    cmp     x9, #(NUMBER_OF_COLUMNS / 2)
    b.ne    7f
    add     x0, x1, #NodeApi_root
    ldr     x1, [x1, #NodeApi_slot]
    mov     x2, #0
    bl      lantern_node_sidecar_of
    ldr     x1, [sp, #64]
    str     x0, [x1, #NodeApi_data]
7:  ldp     x0, x1, [sp, #56]
    bl      lantern_node_api_chunk_work
    mov     x0, #0
    UNFRAME 112
8:  mov     x0, #404
    UNFRAME 112
END_FUNCTION lantern_node_api_blob_stream

/*
 * L1: the blob stream x0 after a chunk that ended its item (node.md, NODE_EV_API, the blob stream):
 * deneb and electra the sidecar from member + 1 on; fulu the next cell, of blob filter_slot + 1
 * and column 0 after API_STREAM_BLOB_SKIP or the first half's last column, else of column member
 * + 1, with sent 0. API_STREAM_BLOB_SKIP clears. x21 the entry.
 */
LOCAL_FUNCTION lantern_node_blob_advance
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #NodeApi_flags]
    and     x10, x9, #~API_STREAM_BLOB_SKIP
    str     x10, [x21, #NodeApi_flags]
    ldr     x10, [x21, #NodeApi_fork]
    cmp     x10, #FORK_FULU
    b.hs    1f
    ldr     x1, [x21, #NodeApi_member]
    add     x1, x1, #1
    bl      lantern_node_sidecar_next
    LEAVE 0
1:  ldr     x10, [x21, #NodeApi_member]
    ldr     x11, [x21, #NodeApi_filter_slot]
    add     x10, x10, #1
    tst     x9, #API_STREAM_BLOB_SKIP
    b.ne    2f
    cmp     x10, #(NUMBER_OF_COLUMNS / 2)
    b.lo    3f
2:  add     x11, x11, #1
    mov     x10, #0
3:  str     x10, [x21, #NodeApi_member]
    str     x11, [x21, #NodeApi_filter_slot]
    str     xzr, [x21, #NodeApi_sent]
    add     x0, x21, #NodeApi_root
    ldr     x1, [x21, #NodeApi_slot]
    mov     x2, x10
    bl      lantern_node_sidecar_of
    str     x0, [x21, #NodeApi_data]
    LEAVE 0
END_FUNCTION lantern_node_blob_advance

/*
 * L1: x0 = 1 when kzg_commitment_to_versioned_hash of the 48-byte commitment at x0 (deneb
 * beacon-chain.md: VERSIONED_HASH_VERSION_KZG, then the last 31 bytes of its sha256) is one of the
 * Root items of the ByteList x20, else 0. Locals: a ByteList of the commitment (72), the hash (32).
 */
LOCAL_FUNCTION lantern_api_blob_wanted
    FRAME 112
    add     x9, sp, #16
    mov     x10, #72
    mov     x11, #24
    stp     x10, x11, [x9]
    mov     x10, #48
    str     x10, [x9, #16]
    mov     x1, x0
    add     x0, sp, #40
    mov     x2, #48
    bl      lantern_copy
    add     x0, sp, #16
    add     x1, sp, #88
    CALL_GLOBAL crypto_sha256
    mov     w9, #VERSIONED_HASH_VERSION_KZG
    strb    w9, [sp, #88]
    ldr     x9, [x20, #8]                   /* the items */
    add     x10, x20, x9
    ldr     x11, [x20, #16]
    lsr     x11, x11, #5
1:  cbz     x11, 8f
    ldp     x12, x13, [x10]
    ldp     x14, x15, [sp, #88]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    2f
    ldp     x12, x13, [x10, #16]
    ldp     x14, x15, [sp, #104]
    cmp     x12, x14
    ccmp    x13, x15, #0, eq
    b.ne    2f
    mov     x0, #1
    UNFRAME 112
2:  add     x10, x10, #32
    sub     x11, x11, #1
    b       1b
8:  mov     x0, #0
    UNFRAME 112
END_FUNCTION lantern_api_blob_wanted

/*
 * L1: the blob stream's body, as lantern_api_stream_json (node.md, NODE_WORK_API_CHUNK, the blob stream):
 * with the sidecar x21 and the versioned hashes x20 (or 0), the bytes of its blob, or of its cell,
 * from sent (NodeEvent_api), as many as fit, as JSON in lower case hex; with x21 = 0, or a blob past
 * the last, ]} as JSON. x0 = 1 when the answer is whole, 0 when more is to come, 2 for bytes that
 * are no encoding. Locals: sp+16 the piece's bytes, sp+24 their count, sp+32 1 at a blob's first
 * piece, sp+40 1 at its last.
 */
LOCAL_FUNCTION lantern_api_blob_body
    FRAME 32
    cbz     x21, 90f
    ldr     x9, [x21, #8]
    add     x10, x21, x9                    /* the sidecar's SSZ bytes, x11 of them */
    ldr     x11, [x21, #16]
    ldr     x12, [x22, #NodeApi_fork]
    cmp     x12, #FORK_FULU
    b.hs    20f
    MOVQ    x12, (8 + PUB_BLOB_BYTES + 48)  /* deneb and electra: index, blob, kzg_commitment, ... */
    cmp     x11, x12
    b.lo    92f
    add     x9, x10, #8
    MOVQ    x13, PUB_BLOB_BYTES
    stp     x9, x13, [sp, #16]
    mov     x9, #1
    stp     x9, x9, [sp, #32]
    ldr     x9, [x23, #NodeEvent_api]       /* at the blob's start, with hashes: its versioned hash */
    cbnz    x9, 30f
    cbz     x20, 30f
    MOVQ    x9, (8 + PUB_BLOB_BYTES)
    add     x0, x10, x9
    bl      lantern_api_blob_wanted
    cbnz    x0, 30f
    b       88f
20: cmp     x11, #PUB_COLUMN_FIXED          /* fulu: a DataColumnSidecar; the offsets of column, kzg_commitments, kzg_proofs */
    b.lo    92f
    ldr     w12, [x10, #8]
    ldr     w13, [x10, #12]
    ldr     w14, [x10, #16]
    cmp     x12, x13
    b.hi    92f
    cmp     x13, x14
    b.hi    92f
    cmp     x14, x11
    b.hi    92f
    ldr     x7, [x22, #NodeApi_filter_slot] /* b */
    ldr     x6, [x22, #NodeApi_member]      /* c */
    ldr     x5, [x23, #NodeEvent_api]
    orr     x4, x6, x5
    cbnz    x4, 22f
    sub     x9, x14, x13                    /* at the blob's start: past the last commitment, the end */
    mov     x8, #48
    udiv    x9, x9, x8
    cmp     x7, x9
    b.hs    90f
    cbz     x20, 22f
    madd    x9, x7, x8, x13                 /* with hashes: the versioned hash of commitment b */
    add     x0, x10, x9
    bl      lantern_api_blob_wanted
    cbz     x0, 87f
    ldr     x9, [x21, #8]
    add     x10, x21, x9
    ldr     w12, [x10, #8]
    ldr     w13, [x10, #12]
    ldr     x7, [x22, #NodeApi_filter_slot]
    ldr     x6, [x22, #NodeApi_member]
22: sub     x15, x13, x12                   /* cell b of the column */
    MOVQ    x8, PUB_CELL_BYTES
    udiv    x15, x15, x8
    cmp     x7, x15
    b.hs    92f
    madd    x9, x7, x8, x12
    add     x9, x10, x9
    stp     x9, x8, [sp, #16]
    cmp     x6, #0
    cset    x9, eq
    cmp     x6, #(NUMBER_OF_COLUMNS / 2 - 1)
    cset    x13, eq
    stp     x9, x13, [sp, #32]
30: ldr     x9, [x23, #NodeEvent_api]       /* the piece from sent */
    ldr     x10, [x23, #(NodeEvent_api + 8)]
    tbnz    x10, #2, 40f
    cbnz    x9, 32f                         /* JSON: at a blob's start , and "0x */
    ldr     x11, [sp, #32]
    cbz     x11, 32f
    sub     x12, x26, x24
    cmp     x12, #8
    b.lo    89f
    tbz     x10, #13, 31f
    API_LIT api_p_comma
31: API_LIT api_blob_open
32: ldp     x1, x2, [sp, #16]               /* the hex of the bytes from sent, as many as fit before a " */
    ldr     x9, [x23, #NodeEvent_api]
    sub     x2, x2, x9
    sub     x12, x26, x24
    subs    x12, x12, #1
    b.ls    89f
    lsr     x12, x12, #1
    cmp     x2, x12
    csel    x2, x12, x2, hi
    add     x1, x1, x9
    add     x9, x9, x2
    str     x9, [x23, #NodeEvent_api]
33: cbz     x2, 34f
    ldrb    w9, [x1], #1
    lsr     w10, w9, #4
    and     w11, w9, #15
    add     w10, w10, #0x30
    cmp     w10, #0x39
    b.ls    331f
    add     w10, w10, #39
331: add    w11, w11, #0x30
    cmp     w11, #0x39
    b.ls    332f
    add     w11, w11, #39
332: strb   w10, [x24], #1
    strb    w11, [x24], #1
    sub     x2, x2, #1
    b       33b
34: ldr     x9, [x23, #NodeEvent_api]       /* the piece's end: " after a blob's last byte */
    ldr     x10, [sp, #24]
    cmp     x9, x10
    b.ne    89f
    ldr     x11, [sp, #40]
    cbz     x11, 88f
    API_LIT api_quote
    b       86f
40: ldp     x1, x2, [sp, #16]               /* SSZ: the bytes from sent, as many as fit */
    sub     x2, x2, x9
    sub     x12, x26, x24
    cmp     x2, x12
    csel    x2, x12, x2, hi
    add     x1, x1, x9
    add     x9, x9, x2
    str     x9, [x23, #NodeEvent_api]
    mov     x0, x24
    add     x24, x24, x2
    bl      lantern_copy
    ldr     x9, [x23, #NodeEvent_api]
    ldr     x10, [sp, #24]
    cmp     x9, x10
    b.ne    89f
    ldr     x11, [sp, #40]
    cbz     x11, 88f
86: ldr     x9, [x23, #(NodeEvent_api + 8)] /* a blob's end */
    orr     x9, x9, #API_STREAM_ITEMS
    str     x9, [x23, #(NodeEvent_api + 8)]
88: ldr     x9, [x23, #(NodeEvent_api + 8)] /* the piece is done */
    orr     x9, x9, #API_STREAM_ITEM_DONE
    str     x9, [x23, #(NodeEvent_api + 8)]
89: mov     x0, #0
    UNFRAME 32
87: ldr     x9, [x23, #(NodeEvent_api + 8)] /* a blob not wanted: skip it */
    orr     x9, x9, #API_STREAM_ITEM_DONE
    orr     x9, x9, #API_STREAM_BLOB_SKIP
    str     x9, [x23, #(NodeEvent_api + 8)]
    b       89b
90: ldr     x9, [x23, #(NodeEvent_api + 8)] /* the end: ]} as JSON */
    tbnz    x9, #2, 91f
    sub     x12, x26, x24
    cmp     x12, #2
    b.lo    89b
    API_LIT api_v_end
91: mov     x0, #1
    UNFRAME 32
92: mov     x0, #2
    UNFRAME 32
END_FUNCTION lantern_api_blob_body

/*
 * L1: the sidecar of the sidecar stream x0 from the index x1 on (node.md, NODE_EV_API, a sidecar of a
 * sidecar stream): member, data, sent 0 and cursor zero; x0 = 1, or 0 with data 0 for none. x21 the
 * entry, x22 the index.
 */
LOCAL_FUNCTION lantern_node_sidecar_next
    ENTER 0
    mov     x21, x0
    mov     x22, x1
1:  cmp     x22, #128
    b.hs    8f
    ldr     x9, [x21, #NodeApi_filter_slot]
    mov     x10, x22
    cmp     x22, #64
    b.lo    2f
    ldr     x9, [x21, #NodeApi_filter_index]
    sub     x10, x22, #64
2:  lsr     x9, x9, x10
    tbz     x9, #0, 7f
    add     x0, x21, #NodeApi_root          /* the node's NODE_BLOB_VALID entry, else the Db's record */
    mov     x1, x22
    bl      lantern_node_blob_held
    cbz     x0, 3f
    ldr     x0, [x0, #NodeBlob_data_id]
    b       5f
3:  ldr     x9, [x19, #Node_flags]
    tst     x9, #NODE_FLAG_DB
    b.eq    7f
    ldr     x0, [x21, #NodeApi_slot]
    mov     x1, x22
    bl      lantern_node_db_sidecar
    cbz     x0, 7f
5:  str     x0, [x21, #NodeApi_data]
    str     x22, [x21, #NodeApi_member]
    str     xzr, [x21, #NodeApi_sent]
    add     x0, x21, #NodeApi_cursor
    mov     x1, #JSON_CURSOR_SIZE
    bl      lantern_zero
    mov     x0, #1
    LEAVE 0
7:  add     x22, x22, #1
    b       1b
8:  str     xzr, [x21, #NodeApi_data]
    mov     x0, #0
    LEAVE 0
END_FUNCTION lantern_node_sidecar_next

/*
 * L1: (connection x0, route x1, flags x2, view x3) -> x0: the sidecar stream of the block of the
 * view (node.md, NODE_EV_API): 0, or 400 for a block whose slot's fork is not the operation's.
 * Locals: the connection, the route, the flags, the view, the fork, the entry's index and address.
 */
LOCAL_FUNCTION lantern_node_api_sidecar_stream
    FRAME 64
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    ldr     x0, [x3, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    str     x0, [sp, #48]
    ldr     x9, [sp, #24]
    ldr     x9, [x9, #ApiRoute_op]
    cmp     x9, #API_OP_GET_BLOB_SIDECARS
    b.ne    1f
    cmp     x0, #FORK_DENEB                 /* getBlobSidecars: deneb and electra */
    b.lo    8f
    cmp     x0, #FORK_FULU
    b.hs    8f
    b       2f
1:  cmp     x0, #FORK_FULU                  /* getDebugDataColumnSidecars: fulu and later */
    b.lo    8f
2:  bl      lantern_node_api_new
    stp     x0, x1, [sp, #56]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x1, [sp, #64]
    ldp     x9, x10, [sp, #16]
    str     x9, [x1, #NodeApi_connection]
    ldr     x11, [x10, #ApiRoute_op]
    str     x11, [x1, #NodeApi_op]
    ldr     x9, [sp, #32]                   /* the answer flags, SSZ, and the block's values */
    ldr     x11, [x10, #ApiRoute_response]
    cmp     x11, #API_TYPE_SSZ
    orr     x11, x9, #API_STREAM_SSZ
    csel    x9, x11, x9, eq
    ldr     x12, [sp, #40]
    ldr     x11, [x12, #ApiView_is_optimistic]
    cbz     x11, 3f
    orr     x9, x9, #API_STREAM_OPTIMISTIC
3:  LDQ     x11, x12, ApiView_head_finalized
    cbz     x11, 4f
    orr     x9, x9, #API_STREAM_FINALIZED
4:  str     x9, [x1, #NodeApi_flags]
    ldr     x9, [sp, #48]
    str     x9, [x1, #NodeApi_fork]
    ldr     x9, [x12, #ApiView_head_slot]
    str     x9, [x1, #NodeApi_slot]
    add     x0, x1, #NodeApi_root
    add     x1, x12, #ApiView_head_root
    bl      lantern_copy_root
    ldr     x1, [sp, #64]
    mov     x12, #-1                        /* the indices: their bits, all with none */
    mov     x13, #-1
    ldr     x10, [sp, #24]
    ldr     x9, [x10, #ApiRoute_present]
    tst     x9, #(1 << API_PARAM_INDICES)
    b.eq    6f
    mov     x12, #0
    mov     x13, #0
    PART    x14, x15, x10, ApiRoute_list
5:  cbz     x15, 6f
    ldr     x9, [x14], #8
    sub     x15, x15, #1
    cmp     x9, #128
    b.hs    5b
    mov     x11, #1
    cmp     x9, #64
    b.hs    51f
    lsl     x11, x11, x9
    orr     x12, x12, x11
    b       5b
51: sub     x9, x9, #64
    lsl     x11, x11, x9
    orr     x13, x13, x11
    b       5b
6:  str     x12, [x1, #NodeApi_filter_slot]
    str     x13, [x1, #NodeApi_filter_index]
    mov     x0, x1
    mov     x1, #0
    bl      lantern_node_sidecar_next
    ldp     x0, x1, [sp, #56]
    bl      lantern_node_api_chunk_work
    mov     x0, #0
    UNFRAME 64
8:  mov     x0, #400
    UNFRAME 64
END_FUNCTION lantern_node_api_sidecar_stream

/*
 * L1: a sidecar stream's body, as lantern_api_stream_json (node.md, NODE_WORK_API_CHUNK, the sidecar
 * streams): with the bytes x21, as JSON the JSON of the sidecar from the cursor at NodeEvent_api + 16
 * by lantern_node_json of the entry's fork and the kind of the operation, after , when
 * API_STREAM_ITEMS is set and the cursor is at its start; as SSZ its bytes from sent (NodeEvent_api),
 * as many as fit; at the sidecar's end API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With
 * x21 = 0: ]} as JSON, nothing as SSZ. x0 = 1 when the answer is whole, 0 when more is to come, 2
 * for bytes that are no encoding.
 */
LOCAL_FUNCTION lantern_api_sidecar_body
    FRAME 0
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    cbnz    x21, 1f
    tbnz    x9, #2, 9f                      /* SSZ: nothing more */
    API_LIT api_v_end
9:  mov     x0, #1
    UNFRAME 0
1:  tbz     x9, #2, 3f
    ldr     x9, [x21, #8]                   /* SSZ: the bytes from sent, as many as fit */
    add     x1, x21, x9
    ldr     x10, [x21, #16]
    ldr     x11, [x23, #NodeEvent_api]
    sub     x2, x10, x11
    sub     x12, x26, x24
    cmp     x2, x12
    csel    x2, x12, x2, hi
    add     x1, x1, x11
    add     x11, x11, x2
    str     x11, [x23, #NodeEvent_api]
    mov     x0, x24
    add     x24, x24, x2
    bl      lantern_copy
    ldr     x11, [x23, #NodeEvent_api]
    ldr     x10, [x21, #16]
    cmp     x11, x10
    b.ne    2f
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #(API_STREAM_ITEMS | API_STREAM_ITEM_DONE)
    str     x9, [x23, #(NodeEvent_api + 8)]
2:  mov     x0, #0
    UNFRAME 0
3:  ldr     x9, [x23, #(NodeEvent_api + 16)]    /* JSON: the cursor's depth, 0 before the first byte */
    cbnz    x9, 4f
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #13, 4f
    API_LIT api_p_comma
4:  ldr     x9, [x22, #NodeApi_op]
    mov     x0, #NODE_JSON_BLOB_SIDECAR
    cmp     x9, #API_OP_GET_BLOB_SIDECARS
    b.eq    5f
    mov     x0, #NODE_JSON_DATA_COLUMN_SIDECAR
5:  add     x9, x23, #NodeEvent_api_bytes   /* the ByteList: its room to x26 - 1, its bytes to x24 */
    sub     x10, x26, #1
    sub     x10, x10, x9
    mov     x11, #24
    stp     x10, x11, [x9]
    sub     x10, x24, x28
    str     x10, [x9, #16]
    mov     x1, x21
    add     x2, x23, #(NodeEvent_api + 16)
    add     x3, x23, #NodeEvent_api_bytes
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_json
    ldr     x9, [x23, #(NodeEvent_api_bytes + 16)]
    add     x24, x28, x9
    cmp     x0, #LANTERN_JSON_MORE
    b.eq    8f
    cbnz    x0, 7f
    ldr     x9, [x23, #(NodeEvent_api + 8)] /* whole: the sidecar is done */
    orr     x9, x9, #(API_STREAM_ITEMS | API_STREAM_ITEM_DONE)
    str     x9, [x23, #(NodeEvent_api + 8)]
8:  mov     x0, #0
    UNFRAME 0
7:  mov     x0, #2
    UNFRAME 0
END_FUNCTION lantern_api_sidecar_body

/*
 * L1: the pool stream of the NodeApi entry x0 goes to its next entry after slot (node.md,
 * NODE_WORK_API_CHUNK): its slot, data, sent and member, a zero cursor; data 0 with none. Bytes it owned
 * get a NODE_ACT_BYTES_FREE, and API_STREAM_OWN clears. Locals: the entry, the old data, the flags.
 */
LOCAL_FUNCTION lantern_node_api_pool_advance
    FRAME 32
    str     x0, [sp, #16]
    ldr     x9, [x0, #NodeApi_data]
    ldr     x10, [x0, #NodeApi_flags]
    stp     x9, x10, [sp, #24]
    ldr     x9, [x0, #NodeApi_slot]
    mov     x1, x0
    add     x0, x9, #1
    bl      lantern_node_pool_next
    ldr     x9, [sp, #16]
    mov     x10, #0
    cmn     x0, #1
    b.eq    1f
    str     x0, [x9, #NodeApi_slot]
    ldr     x11, [x1, #NodePool_fork]
    str     x11, [x9, #NodeApi_sent]
    ldr     x11, [x1, #NodePool_member]
    str     x11, [x9, #NodeApi_member]
    ldr     x10, [x1, #NodePool_data_id]
1:  str     x10, [x9, #NodeApi_data]
    ldr     x10, [x9, #NodeApi_flags]
    and     x10, x10, #~API_STREAM_OWN
    str     x10, [x9, #NodeApi_flags]
    tbnz    x10, #15, 2f                    /* API_STREAM_FOLD: the cursor holds the aggregate */
    add     x0, x9, #NodeApi_cursor
    mov     x1, #JSON_CURSOR_SIZE
    bl      lantern_zero
2:  ldr     x10, [sp, #32]
    tbz     x10, #3, 9f                     /* API_STREAM_OWN: the old bytes go */
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [sp, #24]
    mov     x2, #0
    bl      lantern_node_ids
9:  UNFRAME 32
END_FUNCTION lantern_node_api_pool_advance

/*
 * L1: a pool stream's JSON, as lantern_api_stream_json: with the bytes x21, the JSON of the pool entry
 * from the cursor at NodeEvent_api + 16, by lantern_node_json of the fork in sent (NodeEvent_api)
 * and the kind of the GET, after , when API_STREAM_ITEMS is set and the cursor is at its start;
 * once whole, API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With x21 = 0: ]}. x0 = 1
 * when the answer is whole, 0 when more is to come, 2 for bytes that are no encoding.
 */
LOCAL_FUNCTION lantern_api_pool_json
    FRAME 0
    cbnz    x21, 1f
    API_LIT api_v_end
    mov     x0, #1
    UNFRAME 0
1:  ldr     x9, [x23, #(NodeEvent_api + 16)]    /* the cursor's depth: 0 before the first byte */
    cbnz    x9, 2f
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #13, 2f
    API_LIT api_p_comma
2:  ldr     x9, [x22, #NodeApi_op]          /* the kind of the GET's operation */
    mov     x0, #NODE_JSON_EXIT
    cmp     x9, #API_OP_GET_POOL_VOLUNTARY_EXITS
    b.eq    3f
    mov     x0, #NODE_JSON_PROPOSER_SLASHING
    cmp     x9, #API_OP_GET_POOL_PROPOSER_SLASHINGS
    b.eq    3f
    mov     x0, #NODE_JSON_ATTESTER_SLASHING
    cmp     x9, #API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    b.eq    3f
    mov     x0, #NODE_JSON_ATTESTATION
    cmp     x9, #API_OP_GET_POOL_ATTESTATIONS_V2
    b.eq    3f
    mov     x0, #NODE_JSON_BLS_CHANGE
3:  add     x9, x23, #NodeEvent_api_bytes   /* the ByteList: its room to x26 - 1, its bytes to x24 */
    sub     x10, x26, #1
    sub     x10, x10, x9
    mov     x11, #24
    stp     x10, x11, [x9]
    sub     x10, x24, x28
    str     x10, [x9, #16]
    mov     x1, x21
    add     x2, x23, #(NodeEvent_api + 16)
    add     x3, x23, #NodeEvent_api_bytes
    ldr     x15, [x23, #NodeEvent_api]
    FORK_CALL node_json
    ldr     x9, [x23, #(NodeEvent_api_bytes + 16)]
    add     x24, x28, x9
    cmp     x0, #LANTERN_JSON_MORE
    b.eq    8f
    cbnz    x0, 7f
    ldr     x9, [x23, #(NodeEvent_api + 8)] /* whole: the entry is done */
    orr     x9, x9, #(API_STREAM_ITEMS | API_STREAM_ITEM_DONE)
    str     x9, [x23, #(NodeEvent_api + 8)]
8:  mov     x0, #0
    UNFRAME 0
7:  mov     x0, #2
    UNFRAME 0
END_FUNCTION lantern_api_pool_json

/*
 * L1: (scratch x0) -> x0: the pool entry's bytes x21 folded into the aggregate in the cursor at
 * NodeEvent_api + 16 of the event x23 (node.md, getAggregatedAttestationV2), x22 the entry: of the
 * fork in sent a SingleAttestation (place and length from member) or an Attestation (place its bit,
 * length that of its bits); with data of the root at byte 0, a place not taken, and the length of
 * the aggregate, its bit at byte 272 and its signature added at byte 176 by crypto_bls_aggregate;
 * the first gives the length (40), data (48) and signature; byte 32 counts them. x0 = 0; 1 for
 * bytes that are no attestation or a signature crypto_bls_aggregate rejects; 2 for a short scratch.
 * Locals: scratch, data, signature, length, place, the root (then the list).
 */
LOCAL_FUNCTION lantern_node_api_fold
    FRAME 80
    str     x0, [sp, #16]
    ldr     x9, [x21, #8]
    add     x9, x21, x9                     /* the bytes and their count */
    ldr     x10, [x21, #16]
    ldr     x11, [x22, #NodeApi_sent]
    cmp     x11, #FORK_ELECTRA
    b.lo    1f
    cmp     x10, #240                       /* a SingleAttestation: data at 16, signature at 144 */
    b.ne    71f
    add     x12, x9, #16
    add     x13, x9, #144
    ldr     x14, [x22, #NodeApi_member]
    and     x15, x14, #0xffff
    lsr     x14, x14, #16
    b       3f
1:  cmp     x10, #(228 + 1)                 /* an Attestation: offset 228, data at 4, signature at 132, its bits */
    b.lo    71f
    MOVQ    x11, 228 + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1
    cmp     x10, x11
    b.hi    71f
    ldr     w11, [x9]
    cmp     x11, #228
    b.ne    71f
    add     x12, x9, #4
    add     x13, x9, #132
    add     x1, x9, #228
    sub     x2, x10, #229                   /* the last byte: its highest bit is the length's */
    ldrb    w3, [x1, x2]
    cbz     w3, 71f
    clz     w3, w3
    mov     w4, #31
    sub     w3, w4, w3
    add     x14, x3, x2, lsl #3
    mov     x15, #0                         /* the place: the first bit set */
2:  cmp     x15, x14
    b.hs    71f
    lsr     x3, x15, #3
    ldrb    w3, [x1, x3]
    and     x4, x15, #7
    lsr     w3, w3, w4
    tbnz    w3, #0, 3f
    add     x15, x15, #1
    b       2b
3:  MOVQ    x9, MAX_VALIDATORS_PER_COMMITTEE
    cmp     x14, x9
    b.hi    71f
    cmp     x15, x14
    b.hs    71f
    stp     x12, x13, [sp, #24]
    stp     x14, x15, [sp, #40]
    mov     x0, x12                         /* the root of its data: that of the cursor, else not in the aggregate */
    ldr     x1, [sp, #16]
    add     x2, sp, #56
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_data_root
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    72f
    cbnz    x0, 71f
    add     x9, x23, #(NodeEvent_api + 16)
    ldp     x10, x11, [sp, #56]
    ldp     x12, x13, [x9]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    70f
    ldp     x10, x11, [sp, #72]
    ldp     x12, x13, [x9, #16]
    cmp     x10, x12
    ccmp    x11, x13, #0, eq
    b.ne    70f
    ldp     x14, x15, [sp, #40]
    ldr     x10, [x9, #32]
    cbnz    x10, 4f
    str     x14, [x9, #40]                  /* the first: its length, data and signature */
    add     x0, x9, #48
    ldr     x1, [sp, #24]
    mov     x2, #128
    bl      lantern_copy
    add     x0, x23, #(NodeEvent_api + 16 + 176)
    ldr     x1, [sp, #32]
    mov     x2, #96
    bl      lantern_copy
    b       6f
4:  ldr     x11, [x9, #40]                  /* a later one: the same length, a place not taken */
    cmp     x11, x14
    b.ne    70f
    add     x11, x9, #272
    lsr     x12, x15, #3
    ldrb    w12, [x11, x12]
    and     x13, x15, #7
    lsr     w12, w12, w13
    tbnz    w12, #0, 70f
    ldr     x0, [sp, #16]                   /* the two signatures: a BlsSignatureList at the end of scratch */
    ldr     x10, [x0]
    cmp     x10, #(24 + 2 * 96 + 8)
    b.lo    72f
    sub     x10, x10, #(24 + 2 * 96)
    and     x10, x10, #~7
    add     x10, x0, x10
    str     x10, [sp, #56]
    mov     x11, #(24 + 2 * 96)
    mov     x12, #24
    stp     x11, x12, [x10]
    mov     x11, #2
    str     x11, [x10, #16]
    add     x0, x10, #24
    add     x1, x23, #(NodeEvent_api + 16 + 176)
    mov     x2, #96
    bl      lantern_copy
    ldr     x10, [sp, #56]
    add     x0, x10, #(24 + 96)
    ldr     x1, [sp, #32]
    mov     x2, #96
    bl      lantern_copy
    ldr     x0, [sp, #56]
    add     x1, x23, #(NodeEvent_api + 16 + 176)
    CALL_GLOBAL crypto_bls_aggregate
    cbnz    x0, 71f
6:  add     x9, x23, #(NodeEvent_api + 16)  /* its place's bit; one more */
    ldr     x15, [sp, #48]
    add     x11, x9, #272
    lsr     x12, x15, #3
    ldrb    w13, [x11, x12]
    and     x14, x15, #7
    mov     x10, #1
    lsl     x10, x10, x14
    orr     w13, w13, w10
    strb    w13, [x11, x12]
    ldr     x10, [x9, #32]
    add     x10, x10, #1
    str     x10, [x9, #32]
70: mov     x0, #0
    UNFRAME 80
71: mov     x0, #1
    UNFRAME 80
72: mov     x0, #2
    UNFRAME 80
END_FUNCTION lantern_node_api_fold
.if MAX_VALIDATORS_PER_COMMITTEE > 2048 || 48 + 128 + 96 + 2048 / 8 > JSON_CURSOR_SIZE
.error "node_api_fold: the aggregate's bits fit the cursor from byte 272"
.endif

.set API_SYNC_SUBCOMMITTEE_SIZE, SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT

/*
 * L1: (scratch x0) -> x0: the pool entry's bytes x21, a SyncCommitteeMessage, folded into the
 * contribution in the cursor at NodeEvent_api + 16 of the event x23 (node.md,
 * produceSyncCommitteeContribution), x22 the entry, x20 the head's post-state: with the
 * beacon_block_root at byte 0, and none of its places in the subcommittee filter_index
 * (lantern_node_sync_positions of the fork `fork`) set in the bits at byte 144, each of them is
 * set and its signature added at byte 48 once for each (crypto_bls_aggregate); byte 32 counts
 * them. x0 = 0; 1 for bytes of another size, no state, or a signature crypto_bls_aggregate
 * rejects; 2 for a short scratch. Locals: scratch, the bytes, the places (SYNC_COMMITTEE_SIZE / 8
 * bytes), the subcommittee's places, the place, the list.
 */
LOCAL_FUNCTION lantern_node_api_sync_fold
    FRAME 128
    str     x0, [sp, #16]
    ldr     x9, [x21, #16]
    cmp     x9, #144
    b.ne    71f
    cbz     x20, 71f
    ldr     x9, [x21, #8]
    add     x9, x21, x9
    str     x9, [sp, #24]
    add     x10, x23, #(NodeEvent_api + 16)  /* its beacon_block_root: the contribution's, else not in it */
    ldp     x11, x12, [x9, #8]
    ldp     x13, x14, [x10]
    cmp     x11, x13
    ccmp    x12, x14, #0, eq
    b.ne    70f
    ldp     x11, x12, [x9, #24]
    ldp     x13, x14, [x10, #16]
    cmp     x11, x13
    ccmp    x12, x14, #0, eq
    b.ne    70f
    mov     x0, x20                         /* its places */
    ldr     x1, [x9, #40]
    add     x2, sp, #32
    ldr     x15, [x22, #NodeApi_fork]
    FORK_CALL node_sync_positions
    cbnz    x0, 71f
    ldr     x9, [x22, #NodeApi_filter_index]    /* those of the subcommittee: none taken, one at least */
    mov     x10, #(API_SYNC_SUBCOMMITTEE_SIZE / 8)
    mul     x9, x9, x10
    add     x9, x9, #32
    add     x9, sp, x9
    str     x9, [sp, #96]
    add     x12, x23, #(NodeEvent_api + 16 + 144)
    mov     x10, #0
    mov     x13, #0
1:  cmp     x10, #(API_SYNC_SUBCOMMITTEE_SIZE / 8)
    b.hs    2f
    ldrb    w11, [x9, x10]
    ldrb    w14, [x12, x10]
    tst     w11, w14
    b.ne    70f
    orr     x13, x13, x11
    add     x10, x10, #1
    b       1b
2:  cbz     x13, 70f
    str     xzr, [sp, #104]
3:  ldr     x10, [sp, #104]                 /* each place: its bit, its signature once more */
    cmp     x10, #API_SYNC_SUBCOMMITTEE_SIZE
    b.hs    70f
    ldr     x9, [sp, #96]
    lsr     x11, x10, #3
    ldrb    w11, [x9, x11]
    and     x12, x10, #7
    lsr     w11, w11, w12
    tbz     w11, #0, 6f
    add     x12, x23, #(NodeEvent_api + 16 + 144)
    lsr     x11, x10, #3
    ldrb    w13, [x12, x11]
    and     x14, x10, #7
    mov     x15, #1
    lsl     x15, x15, x14
    orr     w13, w13, w15
    strb    w13, [x12, x11]
    ldr     x9, [x23, #(NodeEvent_api + 16 + 32)]
    cbnz    x9, 4f
    add     x0, x23, #(NodeEvent_api + 16 + 48) /* the first: its signature */
    ldr     x1, [sp, #24]
    add     x1, x1, #48
    mov     x2, #96
    bl      lantern_copy
    b       5f
4:  ldr     x0, [sp, #16]                   /* else the two signatures: a BlsSignatureList at the end of scratch */
    ldr     x10, [x0]
    cmp     x10, #(24 + 2 * 96 + 8)
    b.lo    72f
    sub     x10, x10, #(24 + 2 * 96)
    and     x10, x10, #~7
    add     x10, x0, x10
    str     x10, [sp, #112]
    mov     x11, #(24 + 2 * 96)
    mov     x12, #24
    stp     x11, x12, [x10]
    mov     x11, #2
    str     x11, [x10, #16]
    add     x0, x10, #24
    add     x1, x23, #(NodeEvent_api + 16 + 48)
    mov     x2, #96
    bl      lantern_copy
    ldr     x10, [sp, #112]
    add     x0, x10, #(24 + 96)
    ldr     x1, [sp, #24]
    add     x1, x1, #48
    mov     x2, #96
    bl      lantern_copy
    ldr     x0, [sp, #112]
    add     x1, x23, #(NodeEvent_api + 16 + 48)
    CALL_GLOBAL crypto_bls_aggregate
    cbnz    x0, 71f
5:  ldr     x9, [x23, #(NodeEvent_api + 16 + 32)]
    add     x9, x9, #1
    str     x9, [x23, #(NodeEvent_api + 16 + 32)]
6:  ldr     x10, [sp, #104]
    add     x10, x10, #1
    str     x10, [sp, #104]
    b       3b
70: mov     x0, #0
    UNFRAME 128
71: mov     x0, #1
    UNFRAME 128
72: mov     x0, #2
    UNFRAME 128
END_FUNCTION lantern_node_api_sync_fold
.if SYNC_COMMITTEE_SIZE / 8 > 64 || API_SYNC_SUBCOMMITTEE_SIZE % 8 || 144 + API_SYNC_SUBCOMMITTEE_SIZE / 8 > JSON_CURSOR_SIZE
.error "node_api_sync_fold: the places fit its locals, a subcommittee's places are whole bytes"
.endif

/*
 * L1: (out x0) -> x0: the contribution in the cursor at NodeEvent_api + 16 of the event x23 as
 * the SSZ bytes of a SyncCommitteeContribution at out, x1 their count (node.md,
 * produceSyncCommitteeContribution): slot filter_slot, the beacon_block_root, subcommittee_index
 * filter_index of the entry x22, the bits, the signature. x0 = 0.
 */
LOCAL_FUNCTION lantern_node_api_contribution
    FRAME 16
    str     x0, [sp, #16]
    ldr     x9, [x22, #NodeApi_filter_slot]
    str     x9, [x0]
    add     x0, x0, #8
    add     x1, x23, #(NodeEvent_api + 16)
    mov     x2, #32
    bl      lantern_copy
    ldr     x0, [sp, #16]
    ldr     x9, [x22, #NodeApi_filter_index]
    str     x9, [x0, #40]
    add     x0, x0, #48
    add     x1, x23, #(NodeEvent_api + 16 + 144)
    mov     x2, #(API_SYNC_SUBCOMMITTEE_SIZE / 8)
    bl      lantern_copy
    ldr     x0, [sp, #16]
    add     x0, x0, #(48 + API_SYNC_SUBCOMMITTEE_SIZE / 8)
    add     x1, x23, #(NodeEvent_api + 16 + 48)
    mov     x2, #96
    bl      lantern_copy
    mov     x1, #(48 + API_SYNC_SUBCOMMITTEE_SIZE / 8 + 96)
    mov     x0, #0
    UNFRAME 16
END_FUNCTION lantern_node_api_contribution

/*
 * L1: (out x0) -> x0: the aggregate in the cursor at NodeEvent_api + 16 of the event x23 as the
 * SSZ bytes of the Attestation of the fork of the entry x22 at out, x1 their count (node.md,
 * getAggregatedAttestationV2): aggregation_bits of the cursor's length with its bits, data,
 * signature; from electra committee_bits with the bit of filter_index. x0 = 0; 1 for a committee
 * index not below MAX_COMMITTEES_PER_SLOT. Locals: out, the fixed part's size, the count.
 */
LOCAL_FUNCTION lantern_node_api_aggregate
    FRAME 32
    str     x0, [sp, #16]
    mov     x9, #228                        /* the fixed part: 228 bytes, from electra with committee_bits */
    ldr     x10, [x22, #NodeApi_fork]
    cmp     x10, #FORK_ELECTRA
    mov     x11, #NODE_POOL_ATTESTATION_FIXED
    csel    x9, x11, x9, hs
    ldr     x13, [x23, #(NodeEvent_api + 16 + 40)]  /* the bits' bytes, with the length's bit */
    lsr     x14, x13, #3
    add     x14, x14, #1
    add     x10, x9, x14
    stp     x9, x10, [sp, #24]
    mov     x1, x10
    bl      lantern_zero
    ldp     x0, x9, [sp, #16]
    str     w9, [x0]                        /* the offset of aggregation_bits, data and signature */
    add     x0, x0, #4
    add     x1, x23, #(NodeEvent_api + 16 + 48)
    mov     x2, #(128 + 96)
    bl      lantern_copy
    ldp     x15, x9, [sp, #16]
    cmp     x9, #228
    b.eq    1f
    ldr     x10, [x22, #NodeApi_filter_index]   /* committee_bits */
    cmp     x10, #MAX_COMMITTEES_PER_SLOT
    b.hs    71f
    add     x11, x15, #228
    lsr     x12, x10, #3
    and     x13, x10, #7
    mov     x14, #1
    lsl     x14, x14, x13
    strb    w14, [x11, x12]
1:  add     x0, x15, x9                     /* the bits, then the length's bit */
    add     x1, x23, #(NodeEvent_api + 16 + 272)
    ldr     x13, [x23, #(NodeEvent_api + 16 + 40)]
    add     x2, x13, #7
    lsr     x2, x2, #3
    bl      lantern_copy
    ldp     x15, x9, [sp, #16]
    add     x11, x15, x9
    ldr     x13, [x23, #(NodeEvent_api + 16 + 40)]
    lsr     x12, x13, #3
    and     x13, x13, #7
    mov     x14, #1
    lsl     x14, x14, x13
    ldrb    w10, [x11, x12]
    orr     w10, w10, w14
    strb    w10, [x11, x12]
    ldr     x1, [sp, #32]
    mov     x0, #0
    UNFRAME 32
71: mov     x0, #1
    UNFRAME 32
END_FUNCTION lantern_node_api_aggregate
.if NODE_API_FIRST_ROOM < API_HEAD_ROOM + NODE_POOL_ATTESTATION_FIXED + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1
.error "node_api_aggregate: an Attestation of one committee fits the first chunk"
.endif

/*
 * L1: the failures of the event x22 of a NODE_WORK_API_SUBMIT: {"index":<i>,"message":"REJECT"}
 * for each record of LANTERN_GOSSIP_REJECT, with , between, then ]}. Locals: the record, its
 * index, the failures written.
 */
LOCAL_FUNCTION lantern_api_failures
    FRAME 32
    add     x10, x22, #NodeEvent_chunk
    ldr     x9, [x10, #8]
    add     x9, x10, x9
    stp     x9, xzr, [sp, #16]
    str     xzr, [sp, #32]
1:  ldr     x10, [sp, #24]
    ldr     x11, [x22, #NodeEvent_index]
    cmp     x10, x11
    b.hs    9f
    ldr     x9, [sp, #16]
    ldr     x12, [x9]
    cmp     x12, #LANTERN_GOSSIP_REJECT
    b.ne    3f
    ldr     x12, [sp, #32]
    cbz     x12, 2f
    API_LIT api_p_comma
2:  API_LIT api_f_index
    ldr     x0, [sp, #24]
    bl      lantern_api_dec
    API_LIT api_f_reject
    ldr     x12, [sp, #32]
    add     x12, x12, #1
    str     x12, [sp, #32]
3:  ldr     x9, [sp, #16]                   /* the next record: its code, its subnet, then its ByteList */
    ldr     x12, [x9, #16]
    add     x9, x9, #16
    add     x9, x9, x12
    str     x9, [sp, #16]
    ldr     x10, [sp, #24]
    add     x10, x10, #1
    str     x10, [sp, #24]
    b       1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION lantern_api_failures

/*
 * L1: (connection x0, route x1, flags x2, request x3, view x4) -> x0: a pool POST (node.md,
 * NODE_EV_API): a NODE_ACT_BYTES_PUT of the body and a NODE_WORK_API_SUBMIT; 0 once queued, else
 * the status of the error to answer. Locals: the connection, the flags, the route, the view, the
 * head's post-state, a ByteList head whose offset reaches the body.
 */
LOCAL_FUNCTION lantern_node_api_submit
    FRAME 80
    stp     x0, x2, [sp, #16]
    stp     x1, x4, [sp, #32]
    ldr     x9, [x1, #ApiRoute_body]        /* an SSZ body: an answer flag */
    cmp     x9, #API_TYPE_SSZ
    b.ne    11f
    orr     x2, x2, #API_ANSWER_SSZ
    str     x2, [sp, #24]
11: ldr     x9, [x1, #ApiRoute_op]          /* the AttesterSlashing, attestation or aggregate type of the store's fork */
    mov     x10, #API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    cmp     x9, #API_OP_SUBMIT_POOL_ATTESTER_SLASHINGS_V2
    ccmp    x9, x10, #4, ne
    mov     x10, #API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2
    ccmp    x9, x10, #4, ne
    b.ne    1f
    ldr     x10, [x1, #ApiRoute_consensus_version]
    ldr     x11, [x4, #ApiView_fork]
    cmp     x10, #FORK_ELECTRA
    cset    x10, hs
    cmp     x11, #FORK_ELECTRA
    cset    x11, hs
    cmp     x10, x11
    b.ne    80f
1:  ldp     x10, x11, [x3, #HttpRequest_body]   /* a body of no bytes: 400 */
    cbz     x11, 80f
    add     x10, x3, x10
    add     x12, sp, #64
    sub     x13, x10, x12
    stp     x11, x13, [x12]
    str     x11, [x12, #16]
    add     x0, x19, #Node_head_root        /* the head's post-state, else 500 */
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    81f
    ldr     x9, [x1, #NodeBlock_state_id]
    cbz     x9, 81f
    str     x9, [sp, #48]
    add     x0, sp, #64
    bl      lantern_node_put
    mov     x3, x0
    mov     x0, #NODE_WORK_API_SUBMIT
    ldr     x1, [sp, #48]
    mov     x2, #0
    ldr     x4, [sp, #16]
    ldr     x9, [sp, #32]
    ldr     x5, [x9, #ApiRoute_op]
    ldr     x10, [sp, #24]
    orr     x5, x5, x10, lsl #8
    ldr     x10, [sp, #40]
    ldr     x10, [x10, #ApiView_fork]
    orr     x5, x5, x10, lsl #16
    bl      lantern_node_work
    mov     x0, #0
    UNFRAME 80
80: mov     x0, #400
    UNFRAME 80
81: mov     x0, #500
    UNFRAME 80
END_FUNCTION lantern_node_api_submit

/*
 * L0: x0 = 0 when the NODE_EV_WORK_DONE x0 of x1 bytes of a valid NODE_WORK_API_SUBMIT holds its
 * records inside it (node.md): a ByteList at NodeEvent_chunk of offset 24, and NodeEvent_index
 * records in its bytes, each a code and a ByteList of offset 24 whose size is a multiple of 8;
 * else 1. Uses x9-x15.
 */
LOCAL_FUNCTION lantern_node_submit_check
    UNWIND_END_PROLOGUE
    cmp     x1, #(NodeEvent_chunk + 24)
    b.lo    8f
    add     x9, x0, #NodeEvent_chunk
    ldp     x10, x11, [x9, #8]
    cmp     x10, #24
    b.ne    8f
    sub     x12, x1, #(NodeEvent_chunk + 24)
    cmp     x11, x12
    b.hi    8f
    add     x12, x9, #24                    /* the first record, and the end */
    add     x13, x12, x11
    ldr     x14, [x0, #NodeEvent_index]
1:  cbz     x14, 7f
    sub     x15, x13, x12
    cmp     x15, #40
    b.lo    8f
    ldp     x9, x10, [x12, #16]             /* size, offset of its ByteList after the code and the subnet */
    cmp     x10, #24
    b.ne    8f
    cmp     x9, #24
    b.lo    8f
    tst     x9, #7
    b.ne    8f
    sub     x15, x15, #16
    cmp     x9, x15
    b.hi    8f
    ldr     x10, [x12, #32]
    sub     x15, x9, #24
    cmp     x10, x15
    b.hi    8f
    add     x12, x12, #16
    add     x12, x12, x9
    sub     x14, x14, #1
    b       1b
7:  mov     x0, #0
    ret
8:  mov     x0, #1
    ret
END_FUNCTION lantern_node_submit_check

/*
 * L1: the ProposerPreparation at x0 (beacon-api.md, prepareBeaconProposer): the NodeProposer of its
 * validator_index takes its fee_recipient and the store x20's epoch + 3 as until_epoch; with none,
 * the first entry whose until_epoch is at most that epoch, else a new one when the part has room;
 * else none. Locals: the item, the epoch.
 */
LOCAL_FUNCTION lantern_node_proposer_put
    FRAME 16
    str     x0, [sp, #16]
    mov     x0, x20
    bl      lantern_node_store_slot
    mov     x9, #SLOTS_PER_EPOCH
    udiv    x0, x0, x9
    str     x0, [sp, #24]
    ldr     x13, [sp, #16]
    ldr     x14, [x13]                      /* validator_index */
    PART    x9, x10, x19, Node_proposers
    mov     x11, #0
    mov     x15, #0                         /* the first free entry, or 0 */
1:  cmp     x11, x10
    b.hs    3f
    ldr     x12, [x9, #NodeProposer_validator_index]
    cmp     x12, x14
    b.eq    5f
    cbnz    x15, 2f
    ldr     x12, [x9, #NodeProposer_until_epoch]
    cmp     x12, x0
    b.hi    2f
    ldr     x12, [x9, #NodeProposer_registered]
    cbnz    x12, 2f
    mov     x15, x9
2:  add     x9, x9, #NodeProposer__mem
    add     x11, x11, #1
    b       1b
3:  mov     x9, x15                         /* none of its index: a free entry, else a new one */
    cbnz    x9, 5f
    LDQ     x12, x19, Node_proposers        /* the capacity: up to the next part */
    LDQ     x13, x19, Node_p2p_out
    sub     x13, x13, x12
    mov     x12, #NodeProposer__mem
    udiv    x13, x13, x12
    cmp     x10, x13
    b.hs    9f
    PART    x9, x11, x19, Node_proposers
    mov     x12, #NodeProposer__mem
    madd    x9, x10, x12, x9
    add     x10, x10, #1
    STQ     x10, x19, Node_proposers + 8
    str     xzr, [x9, #NodeProposer_registered]     /* a new entry: no registration */
5:  str     x14, [x9, #NodeProposer_validator_index]
    ldr     x0, [sp, #24]
    add     x0, x0, #3
    str     x0, [x9, #NodeProposer_until_epoch]
    add     x0, x9, #NodeProposer_fee_recipient
    ldr     x1, [sp, #16]
    add     x1, x1, #8
    mov     x2, #20
    bl      lantern_copy
9:  UNFRAME 16
END_FUNCTION lantern_node_proposer_put

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_SUBMIT (node.md, lantern_node_step): the body's
 * bytes go; each valid operation joins the pool, goes out on its topic with NODE_FLAG_SUBSCRIBED,
 * and an attester slashing to fork choice; then the answer to the connection. x19 the node, x20
 * the store, x23 the scratch, x24 the actions. x21 the event, x22 the record, x25 the failures, x26
 * the topic, x27 the new id, x28 the answer's flags. Locals: L 1 when the pool keeps it, L+8 the
 * records left, L+16 a sync message's subnet.
 */
LOCAL_FUNCTION lantern_node_api_submit_done
    ENTER 32
    mov     x21, x0
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [x21, #NodeAction_data]
    mov     x2, #0
    bl      lantern_node_ids
    ldr     x9, [x21, #NodeAction_arg]      /* the answer's flags: API_STREAM_CLOSE (1), API_STREAM_HTTP10 (2) */
    ubfx    x10, x9, #8, #8
    mov     x28, #API_R_CLOSE
    tbnz    x10, #0, 1f
    tst     x10, #API_STREAM_HTTP10
    mov     x11, #API_R_KEEP
    csel    x28, x11, xzr, ne
1:  and     x0, x9, #255
    bl      lantern_node_submit_topic
    mov     x26, x0
    ldr     x9, [x21, #NodeEvent_result]
    cbnz    x9, 80f
    mov     x25, #0
    ldr     x9, [x21, #NodeEvent_index]
    str     x9, [sp, #(L + 8)]
    add     x9, x21, #NodeEvent_chunk
    ldr     x10, [x9, #8]
    add     x22, x9, x10
2:  ldr     x9, [sp, #(L + 8)]
    cbz     x9, 70f
    ldr     x9, [x22]                       /* its code */
    cmp     x9, #LANTERN_GOSSIP_REJECT
    cinc    x25, x25, eq
    cbnz    x9, 6f
    cbz     x26, 40f                        /* no topic: a subscription */
    add     x0, x22, #16                    /* valid: its bytes to a new id, kept by the pool when it has room */
    bl      lantern_node_put
    mov     x27, x0
    mov     x0, x26                         /* its event (node.md, The events), before its bytes go */
    mov     x1, x27
    ldr     x2, [x21, #NodeAction_arg]
    lsr     x2, x2, #16
    bl      lantern_node_op_event
    cmp     x26, #GOSSIP_BEACON_ATTESTATION /* the metrics (metrics.md): an attestation that goes out */
    cset    x9, eq
    LDQ     x10, x19, Node_metrics + NodeMetrics_attestations_published
    add     x10, x10, x9
    STQ     x10, x19, Node_metrics + NodeMetrics_attestations_published
    mov     x4, #0                          /* an attestation: its slot and committee index, its member */
    mov     x5, #0
    ldr     x6, [x22, #8]
    lsr     x6, x6, #32
    cmp     x26, #GOSSIP_SYNC_COMMITTEE     /* a sync message: its slot, its subnets */
    b.ne    23f
    ldr     x9, [x22, #24]
    add     x9, x22, x9
    ldr     x4, [x9, #16]
    ldr     w5, [x22, #8]
    mov     x6, #0
    b       22f
23: cmp     x26, #GOSSIP_BEACON_ATTESTATION
    b.ne    22f
    ldr     x9, [x22, #24]
    add     x9, x22, x9
    add     x9, x9, #16
    ldr     x10, [x21, #NodeAction_arg]
    lsr     x10, x10, #16
    cmp     x10, #FORK_ELECTRA
    b.hs    21f
    ldr     x4, [x9, #4]                    /* Attestation: data.slot at 4, data.index at 12 */
    ldr     x5, [x9, #12]
    b       22f
21: ldr     x4, [x9, #16]                   /* SingleAttestation: committee_index at 0, data.slot at 16 */
    ldr     x5, [x9]
22: mov     x0, x26
    mov     x1, x27
    ldr     x2, [x22, #32]
    ldr     x3, [x21, #NodeAction_arg]
    lsr     x3, x3, #16
    bl      lantern_node_pool_add
    str     x0, [sp, #L]
    ldr     x9, [x19, #Node_flags]
    tbz     x9, #2, 3f                      /* NODE_FLAG_SUBSCRIBED: out on its topic, an attestation on its subnet */
    cmp     x26, #GOSSIP_SYNC_COMMITTEE
    b.eq    24f
    mov     x0, x26
    add     x1, x22, #16
    ldr     w2, [x22, #8]
    bl      lantern_node_publish
    b       3f
24: str     xzr, [sp, #(L + 16)]            /* a sync message: on each of its subnets */
25: ldr     x2, [sp, #(L + 16)]
    cmp     x2, #SYNC_COMMITTEE_SUBNET_COUNT
    b.hs    3f
    ldr     w9, [x22, #8]
    lsr     x9, x9, x2
    tbz     x9, #0, 26f
    mov     x0, x26
    add     x1, x22, #16
    bl      lantern_node_publish
26: ldr     x9, [sp, #(L + 16)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 16)]
    b       25b
3:  cmp     x26, #GOSSIP_ATTESTER_SLASHING  /* an attester slashing: on_attester_slashing with the justified root's state */
    b.ne    4f
    add     x0, x20, #(Store_justified_checkpoint + 8)
    bl      lantern_node_find_block
    cmn     x0, #1
    b.eq    4f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    4f
    ldr     x1, [x1, #NodeBlock_state_id]
    cbz     x1, 4f
    mov     x0, #NODE_WORK_ATTESTER_SLASHING
    mov     x2, #0
    mov     x3, x27
    mov     x4, #0
    mov     x5, #0
    bl      lantern_node_work
    b       6f
4:  ldr     x9, [sp, #L]                    /* bytes no entry keeps and no work reads go */
    cbnz    x9, 6f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x1, x27
    mov     x2, #0
    bl      lantern_node_ids
6:  ldr     x9, [x22, #16]
    add     x22, x22, #16
    add     x22, x22, x9
    ldr     x9, [sp, #(L + 8)]
    sub     x9, x9, #1
    str     x9, [sp, #(L + 8)]
    b       2b
40: ldr     x9, [x22, #24]                  /* a subscription: an aggregator's subnet kept to its slot, sync subnets to an epoch */
    add     x9, x22, x9
    add     x9, x9, #16
    ldr     x10, [x21, #NodeAction_arg]
    and     x10, x10, #255
    cmp     x10, #API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS
    b.eq    42f
    cmp     x10, #API_OP_PREPARE_BEACON_PROPOSER
    b.eq    45f
    cmp     x10, #API_OP_REGISTER_VALIDATOR
    b.eq    46f
    ldrb    w10, [x9, #32]                  /* is_aggregator: subnet_until of compute_subnet_for_attestation, the slot + 1 at least */
    cbz     w10, 6b
    ldr     x11, [x9, #24]
    ldr     x12, [x9, #16]
    ldr     x13, [x9, #8]
    and     x14, x11, #(SLOTS_PER_EPOCH - 1)
    madd    x12, x12, x14, x13
    and     x12, x12, #(ATTESTATION_SUBNET_COUNT - 1)
    add     x11, x11, #1
    ADDQ    x13, x19, Node_subnet_until
    ldr     x14, [x13, x12, lsl #3]
    cmp     x11, x14
    csel    x11, x11, x14, hi
    str     x11, [x13, x12, lsl #3]
    b       6b
42: ldur    x11, [x9, #12]                  /* until_epoch: sync_until of the subnet of each index, that epoch at least */
    ldr     w12, [x9, #8]
    ldr     x13, [x22, #32]
    sub     x13, x13, x12
    add     x14, x9, x12
    ADDQ    x15, x19, Node_sync_until
43: cbz     x13, 6b
    ldr     x10, [x14], #8
    mov     x12, #(SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT)
    udiv    x10, x10, x12
    ldr     x12, [x15, x10, lsl #3]
    cmp     x11, x12
    csel    x12, x11, x12, hi
    str     x12, [x15, x10, lsl #3]
    sub     x13, x13, #8
    b       43b
45: mov     x0, x9                          /* a fee recipient: through the store's epoch + 2 */
    bl      lantern_node_proposer_put
    b       6b
46: add     x0, x22, #16                    /* a registration: its validator's NodeProposer entry */
    ldr     x1, [x22, #8]
    bl      lantern_node_registration_put
    b       6b
70: ldr     x9, [x21, #NodeAction_arg]      /* registerValidator: the builder's call, then the answer */
    and     x9, x9, #255
    cmp     x9, #API_OP_REGISTER_VALIDATOR
    b.ne    701f
    bl      lantern_node_builder_register
701: ldr    x0, [x21, #NodeAction_target]   /* the answer: 200, or 400 with the failures */
    cbz     x25, 71f
    ldr     x9, [x21, #NodeAction_arg]      /* a list: the failures */
    and     x9, x9, #255
    mov     x10, #API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    cmp     x9, #API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    ccmp    x9, x10, #4, ne
    mov     x10, #API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2
    ccmp    x9, x10, #4, ne
    mov     x10, #API_OP_SUBMIT_POOL_SYNC_COMMITTEE_SIGNATURES
    ccmp    x9, x10, #4, ne
    mov     x10, #API_OP_PUBLISH_CONTRIBUTION_AND_PROOFS
    ccmp    x9, x10, #4, ne
    b.ne    80f
    mov     x1, x21
    mov     x2, #400
    mov     x3, #API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    mov     x4, x28
    bl      lantern_node_api_send
    LEAVE 32
71: mov     x1, #0
    mov     x2, #200
    mov     x3, #0
    mov     x4, x28
    bl      lantern_node_api_send
    LEAVE 32
80: ldr     x0, [x21, #NodeAction_target]
    mov     x1, #0
    mov     x2, #400
    mov     x3, #API_BODY_ERROR
    mov     x4, x28
    bl      lantern_node_api_send
    LEAVE 32
END_FUNCTION lantern_node_api_submit_done

/*
 * L2: the publish of the SSZ bytes of the ByteList x1 on the gossip topic x0 of the subnet x2 (node.md, the
 * publish): a LIBP2P_EVENT_PUBLISH at the end of p2p_out; none when it does not fit. Its data
 * compresses in place, its ByteList head in the 24 bytes before the data. x21 the bytes, x22 the
 * event, x25 the topic's length, x26 the data's offset in the event, x27 the event's room.
 * Locals: L a GossipTopic, L+24 the topic's ByteList (24 + 128), L+176 a size, L+184 the
 * message-id (24).
 */
LOCAL_FUNCTION lantern_node_publish
    ENTER 208
    mov     x21, x1
    ldr     w9, [x19, #Node_fork_digest]
    str     x9, [sp, #(L + GossipTopic_fork_digest)]
    stp     x0, x2, [sp, #(L + GossipTopic_name)]
    mov     x9, #(24 + 128)
    mov     x10, #24
    stp     x9, x10, [sp, #(L + 24)]
    str     xzr, [sp, #(L + 40)]
    add     x0, sp, #L
    add     x1, sp, #(L + 24)
    bl      lantern_gossip_topic
    cbnz    x0, 9f
    ldr     x25, [sp, #(L + 40)]
    add     x26, x25, #(LIBP2P_EV_PUB_TOPIC + 7)
    and     x26, x26, #~7
    mov     x0, x21
    add     x1, sp, #(L + 176)
    CALL_GLOBAL snappy_compress_size
    cbnz    x0, 9f
    ldr     x9, [sp, #(L + 176)]            /* the room: the data's offset, then at most size - 24 bytes */
    sub     x9, x9, #24
    add     x27, x26, x9
    add     x27, x27, #7
    and     x27, x27, #~7
    mov     x0, x27
    bl      lantern_node_out
    cbz     x0, 9f
    mov     x22, x0
    add     x2, x22, x26                    /* the data's ByteList head before it: its room to the event's end */
    sub     x2, x2, #24
    sub     x9, x27, x26
    add     x9, x9, #24
    str     x9, [x2]
    mov     x0, x21
    mov     x1, x23
    CALL_GLOBAL snappy_compress
    cbnz    x0, 8f
    mov     x0, x20                         /* the message-id: of the fork of the store's slot */
    bl      lantern_node_store_slot
    add     x1, x19, #Node_config
    bl      lantern_node_fork
    mov     x15, x0
    add     x0, sp, #(L + 24)
    add     x1, x22, x26
    sub     x1, x1, #24
    add     x2, x19, #Node_config
    mov     x3, x23
    add     x4, sp, #(L + 184)
    FORK_CALL compute_message_id
    cbnz    x0, 8f
    add     x9, x22, x26                    /* the data's length; the event to its bytes */
    ldur    x21, [x9, #-8]
    add     x12, x26, x21
    add     x12, x12, #7
    and     x12, x12, #~7
    ldr     x13, [x19, #Node_p2p_out]
    add     x13, x19, x13
    ldr     x14, [x13, #16]
    sub     x14, x14, x27
    add     x14, x14, x12
    str     x14, [x13, #16]
    mov     x27, x12
    mov     x10, #LIBP2P_EVENT_PUBLISH
    stp     x12, x10, [x22]
    mov     x10, #20
    str     x10, [x22, #LIBP2P_EV_PUB_ID_LEN]
    stp     xzr, xzr, [x22, #(LIBP2P_EV_PUB_ID + 16)]
    add     x0, x22, #LIBP2P_EV_PUB_ID
    add     x1, sp, #(L + 184)
    mov     x2, #20
    bl      lantern_copy
    str     x25, [x22, #LIBP2P_EV_PUB_TOPIC_LEN]
    str     x21, [x22, #LIBP2P_EV_PUB_DATA_LEN]
    add     x0, x22, #LIBP2P_EV_PUB_TOPIC
    add     x1, sp, #(L + 48)
    mov     x2, x25
    bl      lantern_copy
    add     x0, x22, #LIBP2P_EV_PUB_TOPIC   /* zero bytes after the topic and after the data */
    add     x0, x0, x25
    sub     x1, x26, #LIBP2P_EV_PUB_TOPIC
    sub     x1, x1, x25
    bl      lantern_zero
    add     x0, x22, x26
    add     x0, x0, x21
    sub     x1, x27, x26
    sub     x1, x1, x21
    bl      lantern_zero
9:  LEAVE 208
8:  ldr     x13, [x19, #Node_p2p_out]       /* no publish: the room goes back */
    add     x13, x19, x13
    ldr     x14, [x13, #16]
    sub     x14, x14, x27
    str     x14, [x13, #16]
    LEAVE 208
END_FUNCTION lantern_node_publish

/*
 * L1: (text x0 to x1, kind x2, fork x3, fault x4) -> x0: the JSON text decoded by lantern_node_json_decode
 * into the record at x27 of lantern_node_api_submit_run (x24 its scratch, x26 the event's end): code and
 * subnet 0, then a ByteList of the SSZ bytes, its size to a multiple of 8; x27 then the next record. x0 = 0,
 * 1 for a text that is no such value, 2 for too little room. Locals: a ByteList head of the text.
 */
LOCAL_FUNCTION lantern_node_submit_decode
    FRAME 32
    add     x9, sp, #16
    sub     x10, x0, x9
    sub     x11, x1, x0
    stp     x11, x10, [x9]
    str     x11, [x9, #16]
    add     x10, x27, #40
    cmp     x10, x26
    b.hi    8f
    sub     x10, x26, x27
    sub     x10, x10, #16
    str     x10, [x27, #16]
    mov     x15, x3
    mov     x0, x2
    mov     x1, x9
    mov     x2, x24
    add     x3, x27, #16
    FORK_CALL node_json_decode
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    8f
    cbnz    x0, 7f
    ldr     x10, [x27, #32]                 /* its size: the bytes to a multiple of 8, zero after them */
    add     x9, x10, #(24 + 7)
    and     x9, x9, #~7
    str     x9, [x27, #16]
    stp     xzr, xzr, [x27]
    add     x0, x27, #40
    add     x0, x0, x10
    sub     x1, x9, #24
    sub     x1, x1, x10
    bl      lantern_zero
    ldr     x9, [x27, #16]
    add     x27, x27, #16
    add     x27, x27, x9
    mov     x0, #0
    UNFRAME 32
7:  mov     x0, #1
    UNFRAME 32
8:  mov     x0, #2
    UNFRAME 32
END_FUNCTION lantern_node_submit_decode

/*
 * L1: (bytes x0, length x1) -> x0: the bytes as the record at x27 of lantern_node_api_submit_run (x26 the
 * event's end): code and subnet 0, then a ByteList of them, its size to a multiple of 8; x27 then
 * the next record. x0 = 0, or 2 for too little room. Locals: the record's size, the length.
 */
LOCAL_FUNCTION lantern_node_submit_copy
    FRAME 16
    add     x9, x1, #(16 + 24 + 7)
    and     x9, x9, #~7
    add     x10, x27, x9
    cmp     x10, x26
    b.hi    8f
    stp     x9, x1, [sp, #16]
    stp     xzr, xzr, [x27]
    sub     x11, x9, #16
    mov     x12, #24
    stp     x11, x12, [x27, #16]
    str     x1, [x27, #32]
    mov     x2, x1
    mov     x1, x0
    add     x0, x27, #40
    bl      lantern_copy
    ldp     x9, x10, [sp, #16]
    add     x0, x27, #40
    add     x0, x0, x10
    sub     x1, x9, #40
    sub     x1, x1, x10
    bl      lantern_zero
    ldr     x9, [sp, #16]
    add     x27, x27, x9
    mov     x0, #0
    UNFRAME 16
8:  mov     x0, #2
    UNFRAME 16
END_FUNCTION lantern_node_submit_copy

/*
 * (node x0, store x1, seen x2, work x3, state_a x4, data x5, scratch x6, event x7, room x8) -> status:
 * a NODE_WORK_API_SUBMIT of lantern_node_run (node.md): the operations of the body decoded as
 * records at NodeEvent_chunk of the event, then each checked by lantern_node_gossip of the fork
 * arg / 2^16 with seen. x19 node, x20 store, x21 work, x22 state_a, x23 data, x24 scratch, x25
 * event, x26 the event's end, x27 the next record, x28 the text's end, then the records left.
 * Locals: L seen, L+8 the kind, L+16 the topic, L+24 the fork, L+32 the operations, L+40 1 for
 * a list, L+48 where the text goes on, L+56 an item's start, L+64 a NodeGossip, L+152 a JsonFault,
 * L+280 a root, L+312 an index.
 */
LOCAL_FUNCTION lantern_node_api_submit_run
    ENTER 320
    mov     x19, x0
    mov     x20, x1
    str     x2, [sp, #L]
    mov     x21, x3
    mov     x22, x4
    mov     x23, x5
    mov     x24, x6
    mov     x25, x7
    add     x26, x7, x8
    ldr     x9, [x21, #NodeAction_arg]      /* the operation's kind and topic; the fork */
    lsr     x10, x9, #16
    cmp     x10, #FORK_FULU
    b.hi    98f
    str     x10, [sp, #(L + 24)]
    and     x0, x9, #255
    mov     x10, #API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    cmp     x0, #API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    ccmp    x0, x10, #4, ne
    mov     x10, #API_OP_PUBLISH_AGGREGATE_AND_PROOFS_V2
    ccmp    x0, x10, #4, ne
    mov     x10, #API_OP_SUBMIT_POOL_SYNC_COMMITTEE_SIGNATURES
    ccmp    x0, x10, #4, ne
    mov     x10, #API_OP_PUBLISH_CONTRIBUTION_AND_PROOFS
    ccmp    x0, x10, #4, ne
    mov     x10, #API_OP_PREPARE_BEACON_COMMITTEE_SUBNET
    ccmp    x0, x10, #4, ne
    mov     x10, #API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS
    ccmp    x0, x10, #4, ne
    mov     x10, #API_OP_PREPARE_BEACON_PROPOSER
    ccmp    x0, x10, #4, ne
    mov     x10, #API_OP_REGISTER_VALIDATOR
    ccmp    x0, x10, #4, ne
    cset    x9, eq
    str     x9, [sp, #(L + 40)]
    bl      lantern_node_submit_topic
    str     x0, [sp, #(L + 16)]
    cbnz    x0, 15f
    ldr     x9, [x21, #NodeAction_arg]      /* no topic: a subscription's type, else no such work */
    and     x9, x9, #255
    mov     x0, #NODE_JSON_COMMITTEE_SUBSCRIPTION
    cmp     x9, #API_OP_PREPARE_BEACON_COMMITTEE_SUBNET
    b.eq    13f
    mov     x0, #NODE_JSON_SYNC_SUBSCRIPTION
    cmp     x9, #API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS
    b.eq    13f
    mov     x0, #NODE_JSON_PROPOSER_PREPARATION
    cmp     x9, #API_OP_PREPARE_BEACON_PROPOSER
    b.eq    13f
    mov     x0, #NODE_JSON_VALIDATOR_REGISTRATION
    cmp     x9, #API_OP_REGISTER_VALIDATOR
    b.eq    13f
    b       98f
15:
    cmp     x0, #GOSSIP_BEACON_AGGREGATE_AND_PROOF  /* an aggregate: SignedAggregateAndProof */
    mov     x9, #NODE_JSON_AGGREGATE_AND_PROOF
    b.eq    14f
    cmp     x0, #GOSSIP_SYNC_COMMITTEE      /* a sync message: SyncCommitteeMessage */
    mov     x9, #NODE_JSON_SYNC_COMMITTEE_MESSAGE
    b.eq    14f
    cmp     x0, #GOSSIP_SYNC_COMMITTEE_CONTRIBUTION_AND_PROOF  /* a contribution: SignedContributionAndProof */
    mov     x9, #NODE_JSON_CONTRIBUTION_AND_PROOF
    b.eq    14f
    cmp     x0, #GOSSIP_BEACON_ATTESTATION  /* an attestation: of the fork's type */
    b.ne    12f
    ldr     x9, [sp, #(L + 24)]
    cmp     x9, #FORK_ELECTRA
    mov     x0, #NODE_JSON_ATTESTATION
    mov     x10, #NODE_JSON_SINGLE_ATTESTATION
    csel    x0, x10, x0, hs
    b       13f
12: bl      lantern_node_pool_kind
    b       13f
14: mov     x0, x9
13: str     x0, [sp, #(L + 8)]
    cbz     x22, 98f
    cbz     x23, 98f
    add     x9, x25, #NodeEvent_chunk       /* the records' ByteList */
    add     x10, x9, #24
    cmp     x10, x26
    b.hi    97f
    sub     x11, x26, x9
    mov     x12, #24
    stp     x11, x12, [x9]
    str     xzr, [x9, #16]
    mov     x27, x10
    str     xzr, [sp, #(L + 32)]
    ldp     x9, x10, [x23, #8]              /* the text */
    add     x0, x23, x9
    add     x28, x0, x10
    ldr     x9, [x21, #NodeAction_arg]      /* an SSZ body: the list's items */
    ubfx    x9, x9, #8, #8
    tbnz    x9, #2, 40f
    ldr     x9, [sp, #(L + 40)]
    cbnz    x9, 20f
    mov     x1, x28                         /* one operation: the whole text */
    ldp     x2, x3, [sp, #(L + 8)]
    ldr     x3, [sp, #(L + 24)]
    add     x4, sp, #(L + 152)
    bl      lantern_node_submit_decode
    cmp     x0, #1
    b.eq    90f
    b.hi    97f
    mov     x9, #1
    str     x9, [sp, #(L + 32)]
    b       30f
20: ldr     x9, [sp, #(L + 16)]             /* a JSON array; of BLS changes from capella */
    cmp     x9, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    b.ne    201f
    ldr     x9, [sp, #(L + 24)]
    cmp     x9, #FORK_CAPELLA
    b.lo    90f
201:
    bl      lantern_submit_ws
    cmp     x0, x28
    b.hs    90f
    ldrb    w9, [x0]
    cmp     w9, #'['
    b.ne    90f
    add     x0, x0, #1
    bl      lantern_submit_ws
    cmp     x0, x28
    b.hs    90f
    ldrb    w9, [x0]
    cmp     w9, #']'
    b.ne    23f
    add     x0, x0, #1
    b       28f
23: str     x0, [sp, #(L + 56)]             /* an item: to a , or ] outside strings, arrays and objects */
    mov     x10, #0
24: cmp     x0, x28
    b.hs    90f
    ldrb    w9, [x0]
    cmp     w9, #'"'
    b.ne    25f
253: add    x0, x0, #1
    cmp     x0, x28
    b.hs    90f
    ldrb    w9, [x0]
    cmp     w9, #'\\'
    b.ne    252f
    add     x0, x0, #1
    b       253b
252: cmp    w9, #'"'
    b.ne    253b
    add     x0, x0, #1
    b       24b
25: cmp     w9, #'{'
    b.eq    251f
    cmp     w9, #'['
    b.ne    26f
251:
    add     x10, x10, #1
    add     x0, x0, #1
    b       24b
26: cmp     w9, #'}'
    b.eq    261f
    cmp     w9, #']'
    b.ne    27f
261:
    cbz     x10, 271f
    sub     x10, x10, #1
    add     x0, x0, #1
    b       24b
27: cmp     w9, #','
    b.ne    272f
    cbz     x10, 271f
272: add    x0, x0, #1
    b       24b
271: str    x0, [sp, #(L + 48)]
    mov     x1, x0
    ldr     x0, [sp, #(L + 56)]
    ldr     x2, [sp, #(L + 8)]
    ldr     x3, [sp, #(L + 24)]
    add     x4, sp, #(L + 152)
    bl      lantern_node_submit_decode
    cmp     x0, #1
    b.eq    90f
    b.hi    97f
    ldr     x9, [sp, #(L + 32)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 32)]
    ldr     x0, [sp, #(L + 48)]
    ldrb    w9, [x0]
    add     x0, x0, #1
    cmp     w9, #','
    b.eq    23b
    cmp     w9, #']'
    b.ne    90f
28: bl      lantern_submit_ws                       /* then only white space */
    cmp     x0, x28
    b.ne    90f
    b       30f
40: sub     x10, x28, x0                    /* SSZ: attestations from electra items of 240 bytes */
    ldr     x9, [x21, #NodeAction_arg]      /* registrations: items of 180 bytes */
    and     x9, x9, #255
    cmp     x9, #API_OP_REGISTER_VALIDATOR
    b.eq    46f
    ldr     x9, [sp, #(L + 16)]
    cmp     x9, #GOSSIP_BEACON_AGGREGATE_AND_PROOF
    b.eq    42f
    ldr     x9, [sp, #(L + 24)]
    cmp     x9, #FORK_ELECTRA
    b.lo    42f
    mov     x11, #240
    udiv    x12, x10, x11
    msub    x13, x12, x11, x10
    cbnz    x13, 90f
    stp     x0, x12, [sp, #(L + 48)]
41: ldp     x0, x12, [sp, #(L + 48)]
    cbz     x12, 30f
    mov     x1, #240
    bl      lantern_node_submit_copy
    cbnz    x0, 97f
    ldp     x0, x12, [sp, #(L + 48)]
    add     x0, x0, #240
    sub     x12, x12, #1
    stp     x0, x12, [sp, #(L + 48)]
    ldr     x9, [sp, #(L + 32)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 32)]
    b       41b
46: mov     x11, #180                       /* registrations: SignedValidatorRegistrationV1 items */
    udiv    x12, x10, x11
    msub    x13, x12, x11, x10
    cbnz    x13, 90f
    stp     x0, x12, [sp, #(L + 48)]
47: ldp     x0, x12, [sp, #(L + 48)]
    cbz     x12, 30f
    mov     x1, #180
    bl      lantern_node_submit_copy
    cbnz    x0, 97f
    ldp     x0, x12, [sp, #(L + 48)]
    add     x0, x0, #180
    sub     x12, x12, #1
    stp     x0, x12, [sp, #(L + 48)]
    ldr     x9, [sp, #(L + 32)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 32)]
    b       47b
42: cbz     x10, 30f                        /* before electra, and aggregates: the items of the 4-byte offsets */
    cmp     x10, #4
    b.lo    90f
    ldr     w11, [x0]
    cbz     x11, 90f
    tst     x11, #3
    b.ne    90f
    cmp     x11, x10
    b.hi    90f
    lsr     x12, x11, #2
    str     x0, [sp, #(L + 48)]
    str     x12, [sp, #(L + 312)]
    str     xzr, [sp, #(L + 56)]
43: ldr     x0, [sp, #(L + 48)]             /* the next item: from its offset to the next, or to the end */
    ldr     x13, [sp, #(L + 56)]
    ldr     x12, [sp, #(L + 312)]
    cmp     x13, x12
    b.hs    30f
    ldr     w14, [x0, x13, lsl #2]
    add     x15, x13, #1
    sub     x9, x28, x0
    cmp     x15, x12
    b.hs    44f
    ldr     w9, [x0, x15, lsl #2]
44: cmp     x14, x9
    b.hi    90f
    sub     x10, x28, x0
    cmp     x9, x10
    b.hi    90f
    add     x0, x0, x14
    sub     x1, x9, x14
    bl      lantern_node_submit_copy
    cbnz    x0, 97f
    ldr     x13, [sp, #(L + 56)]
    add     x13, x13, #1
    str     x13, [sp, #(L + 56)]
    ldr     x9, [sp, #(L + 32)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 32)]
    b       43b
30: add     x9, x25, #NodeEvent_chunk       /* the records: their bytes, their count */
    sub     x10, x27, x9
    str     x10, [x9]
    sub     x10, x10, #24
    str     x10, [x9, #16]
    ldr     x10, [sp, #(L + 32)]
    str     x10, [x25, #NodeEvent_index]
    sub     x9, x27, x25
    str     x9, [x25]
    ldr     x9, [sp, #(L + 16)]             /* the subscriptions: their checks, no gossip validation */
    cbz     x9, 50f
    ldr     x9, [sp, #L]                    /* seen has a key free for each operation, for a sync message one a subnet */
    ldp     x10, x11, [x9, #Seen_keys]
    ldr     x12, [x9, #Seen_bits]
    sub     x12, x12, x10
    lsr     x12, x12, #5
    sub     x12, x12, x11
    ldr     x10, [sp, #(L + 32)]
    ldr     x13, [sp, #(L + 16)]
    cmp     x13, #GOSSIP_SYNC_COMMITTEE
    mov     x13, #SYNC_COMMITTEE_SUBNET_COUNT
    mul     x13, x10, x13
    csel    x10, x13, x10, eq
    cmp     x12, x10
    b.lo    97f
    ldr     x9, [sp, #L]                    /* the NodeGossip of the operations */
    str     x9, [sp, #(L + 64 + NodeGossip_seen)]
    str     x20, [sp, #(L + 64 + NodeGossip_store)]
    ldr     x9, [x19, #Node_time_ms]
    str     x9, [sp, #(L + 64 + NodeGossip_time_ms)]
    ldr     x9, [sp, #(L + 16)]
    str     x9, [sp, #(L + 64 + NodeGossip_topic)]
    str     xzr, [sp, #(L + 64 + NodeGossip_subnet)]
    str     x22, [sp, #(L + 64 + NodeGossip_head)]
    str     xzr, [sp, #(L + 64 + NodeGossip_proposer)]
    str     xzr, [sp, #(L + 64 + NodeGossip_justified)]
    str     xzr, [sp, #(L + 64 + NodeGossip_settings)]
    add     x9, x19, #Node_config
    str     x9, [sp, #(L + 64 + NodeGossip_config)]
    add     x27, x25, #(NodeEvent_chunk + 24)
    ldr     x28, [sp, #(L + 32)]
31: cbz     x28, 39f
    str     xzr, [x27, #8]                  /* the subnet: 0, but an attestation's */
    ldr     x9, [sp, #(L + 16)]
    cmp     x9, #GOSSIP_SYNC_COMMITTEE
    b.eq    36f
    cmp     x9, #GOSSIP_BEACON_ATTESTATION
    b.ne    33f
    ldr     x10, [x27, #32]
    add     x11, x27, #40
    ldr     x12, [sp, #(L + 24)]
    cmp     x12, #FORK_ELECTRA
    b.lo    32f
    cmp     x10, #240                       /* a SingleAttestation: committee_index 0, data.slot 16, data.target.epoch 104 */
    b.lo    33f
    ldr     x13, [x11]
    ldr     x14, [x11, #16]
    ldr     x9, [x11, #104]
    b       34f
32: cmp     x10, #228                       /* an Attestation: data.slot 4, data.index 12, data.target.epoch 92 */
    b.lo    33f
    ldur    x14, [x11, #4]
    ldur    x13, [x11, #12]
    ldur    x9, [x11, #92]
34: stp     x13, x14, [sp, #(L + 48)]
    str     x9, [sp, #(L + 280)]
    mov     x0, x22
    add     x1, sp, #(L + 280)
    LDQ     x2, x19, Node_config + CONFIG_COMMITTEE_CACHE
    mov     x3, x24
    add     x4, sp, #(L + 312)
    ldr     x15, [sp, #(L + 24)]
    FORK_CALL get_committee_count_per_slot
    cbnz    x0, 33f
    ldr     x9, [sp, #(L + 312)]            /* compute_subnet_for_attestation */
    ldp     x13, x14, [sp, #(L + 48)]
    and     x14, x14, #(SLOTS_PER_EPOCH - 1)
    madd    x9, x9, x14, x13
    LDQ     x10, x19, Node_config + CONFIG_ATTESTATION_SUBNET_COUNT
    cbz     x10, 33f
    udiv    x11, x9, x10
    msub    x9, x11, x10, x9
    str     x9, [x27, #8]
33: ldr     x9, [x27, #8]
    str     x9, [sp, #(L + 64 + NodeGossip_subnet)]
    ldr     x15, [sp, #(L + 24)]
    add     x0, sp, #(L + 64)
    add     x1, x27, #16
    mov     x2, x24
    mov     x3, x27
    add     x4, sp, #(L + 280)
    add     x5, sp, #(L + 312)
    FORK_CALL node_gossip
    cbnz    x0, 99f
    ldr     x9, [sp, #(L + 16)]             /* a valid attestation: its member, 2^32 times, with the subnet */
    cmp     x9, #GOSSIP_BEACON_ATTESTATION
    b.ne    35f
    ldr     x9, [x27]
    cbnz    x9, 35f
    ldr     x9, [sp, #(L + 280 + 16)]
    ldr     x10, [x27, #8]
    orr     x10, x10, x9, lsl #32
    str     x10, [x27, #8]
35: ldr     x9, [x27, #16]
    add     x27, x27, #16
    add     x27, x27, x9
    sub     x28, x28, #1
    b       31b
36: mov     x0, x22                         /* a sync message: its check on each subnet of compute_subnets_for_sync_committee */
    ldr     x9, [x27, #32]
    mov     x1, #-1
    cmp     x9, #144
    b.ne    361f
    ldr     x1, [x27, #(40 + 40)]           /* validator_index */
361: add    x2, sp, #(L + 48)
    ldr     x15, [sp, #(L + 24)]
    FORK_CALL node_sync_subnets
    cbnz    x0, 99f
    stp     xzr, xzr, [sp, #(L + 152)]      /* the valid subnets, a reject */
    str     xzr, [sp, #(L + 168)]           /* the subnet */
    ldr     x9, [sp, #(L + 48)]
    cbnz    x9, 37f
    mov     x9, #1                          /* none: the check on subnet 0, which it fails */
    str     x9, [sp, #(L + 48)]
37: ldr     x10, [sp, #(L + 168)]
    cmp     x10, #SYNC_COMMITTEE_SUBNET_COUNT
    b.hs    38f
    ldr     x9, [sp, #(L + 48)]
    lsr     x9, x9, x10
    tbz     x9, #0, 371f
    str     x10, [sp, #(L + 64 + NodeGossip_subnet)]
    ldr     x15, [sp, #(L + 24)]
    add     x0, sp, #(L + 64)
    add     x1, x27, #16
    mov     x2, x24
    mov     x3, x27
    add     x4, sp, #(L + 280)
    add     x5, sp, #(L + 312)
    FORK_CALL node_gossip
    cbnz    x0, 99f
    ldr     x9, [x27]
    ldr     x10, [sp, #(L + 168)]
    cbnz    x9, 372f
    ldr     x11, [sp, #(L + 152)]           /* valid: its bit */
    mov     x12, #1
    lsl     x12, x12, x10
    orr     x11, x11, x12
    str     x11, [sp, #(L + 152)]
    b       371f
372: cmp    x9, #LANTERN_GOSSIP_REJECT
    b.ne    371f
    str     x9, [sp, #(L + 160)]
371: ldr    x10, [sp, #(L + 168)]
    add     x10, x10, #1
    str     x10, [sp, #(L + 168)]
    b       37b
38: ldp     x9, x10, [sp, #(L + 152)]       /* valid on a subnet; else a reject; else the last code */
    str     x9, [x27, #8]
    cbz     x9, 381f
    str     xzr, [x27]
    b       35b
381: cbz    x10, 35b
    str     x10, [x27]
    b       35b
39: mov     x0, #LANTERN_OK
    LEAVE 320
50: add     x27, x25, #(NodeEvent_chunk + 24)   /* each subscription valid, else the result LANTERN_INVALID_ENCODING */
    ldr     x28, [sp, #(L + 32)]
    ldr     x9, [x21, #NodeAction_arg]      /* registrations: 180 bytes each, IGNORE until found eligible */
    and     x9, x9, #255
    cmp     x9, #API_OP_REGISTER_VALIDATOR
    b.eq    60f
51: cbz     x28, 39b
    stp     xzr, xzr, [x27]
    ldr     x10, [x27, #32]
    add     x11, x27, #40
    ldr     x9, [x21, #NodeAction_arg]
    and     x9, x9, #255
    cmp     x9, #API_OP_PREPARE_SYNC_COMMITTEE_SUBNETS
    b.eq    53f
    cmp     x9, #API_OP_PREPARE_BEACON_PROPOSER
    b.ne    55f
    cmp     x10, #28                        /* ProposerPreparation: its 28 bytes */
    b.ne    90f
    b       54f
55: cmp     x10, #33                        /* BeaconCommitteeSubscription: committees_at_slot 1 to MAX_COMMITTEES_PER_SLOT, committee_index below it */
    b.ne    90f
    ldr     x12, [x11, #16]
    cbz     x12, 90f
    cmp     x12, #MAX_COMMITTEES_PER_SLOT
    b.hi    90f
    ldr     x13, [x11, #8]
    cmp     x13, x12
    b.hs    90f
    b       54f
53: cmp     x10, #20                        /* SyncCommitteeSubscription: offset 20, indices below SYNC_COMMITTEE_SIZE */
    b.lo    90f
    ldr     w12, [x11, #8]
    cmp     x12, #20
    b.ne    90f
    sub     x13, x10, #20
    tst     x13, #7
    b.ne    90f
    add     x14, x11, #20
52: cbz     x13, 54f
    ldr     x15, [x14], #8
    cmp     x15, #SYNC_COMMITTEE_SIZE
    b.hs    90f
    sub     x13, x13, #8
    b       52b
54: ldr     x9, [x27, #16]
    add     x27, x27, #16
    add     x27, x27, x9
    sub     x28, x28, #1
    b       51b
60: mov     x9, x27
    mov     x10, x28
61: cbz     x10, 62f
    ldr     x11, [x9, #32]
    cmp     x11, #180
    b.ne    90f
    mov     x11, #LANTERN_GOSSIP_IGNORE
    stp     x11, xzr, [x9]
    ldr     x11, [x9, #16]
    add     x9, x9, #16
    add     x9, x9, x11
    sub     x10, x10, #1
    b       61b
62: cbz     x28, 39b
    mov     x0, x22                         /* one scan of the state's validators */
    mov     x1, x27
    mov     x2, x28
    mov     x3, x24
    bl      lantern_node_registrations_find
    cbnz    x0, 97f
    b       39b
90: mov     x9, #LANTERN_INVALID_ENCODING   /* a body that is no such text */
    str     x9, [x25, #NodeEvent_result]
    mov     x9, #NODE_EV_WORK_DONE_SIZE
    str     x9, [x25]
    mov     x0, #LANTERN_OK
    LEAVE 320
97: mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 320
98: mov     x0, #LANTERN_INVALID_EVENT
99: LEAVE 320
END_FUNCTION lantern_node_api_submit_run

/* L0: x0 = x0 past the JSON white space (space, tab, LF, CR) before x28. Uses x9. */
LOCAL_FUNCTION lantern_submit_ws
    UNWIND_END_PROLOGUE
1:  cmp     x0, x28
    b.hs    9f
    ldrb    w9, [x0]
    cmp     w9, #' '
    ccmp    w9, #9, #4, ne
    ccmp    w9, #10, #4, ne
    ccmp    w9, #13, #4, ne
    b.ne    9f
    add     x0, x0, #1
    b       1b
9:  ret
END_FUNCTION lantern_submit_ws

    RODATA
    .p2align 3
node_api_rooms:                             /* the room of each text of an ApiIdentity, then 0 */
    .quad 64, 512, 128, 128, 64, 0
