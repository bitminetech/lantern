/*
 * The Beacon API answers of the node, ARM64: in the common object. Requirements:
 * docs/reference/beacon-api.md (Common rules) and docs/reference/node.md (NODE_EV_API).
 *
 * The writer: x24 the cursor, x25 the pass (0 counts the bytes, 1 writes them), x26 the end of
 * the room, x27 1 when the room ran out, x22 the ApiView, x28 the body kind. The writer's
 * functions keep x22 and x24-x28 for it; only api_respond calls them.
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
    bl      api_put
.endm

/* L0: the x1 bytes at x0 join the response; the first pass only counts them. Uses x0, x1, x9, x10. */
LOCAL_FUNCTION api_put
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
END_FUNCTION api_put

/* L1: the decimal digits of x0 join the response. Locals: the digits, from the end. */
LOCAL_FUNCTION api_dec
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
    bl      api_put
    UNFRAME 32
END_FUNCTION api_dec

/* L1: the decimal digits of x0, in quotes. Locals: x0. */
LOCAL_FUNCTION api_qdec
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_quote
    ldr     x0, [sp, #16]
    bl      api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_qdec

/* L1: "0x" and the lower case hex of the x1 bytes at x0, in quotes. Locals: x0, x1, then 2 digits. */
LOCAL_FUNCTION api_qhex
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
    bl      api_put
    b       1b
2:  API_LIT api_quote
    UNFRAME 32
END_FUNCTION api_qhex

/* L1: the text at x0 (its length, then its bytes), in quotes. Locals: x0. */
LOCAL_FUNCTION api_text
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_quote
    ldr     x9, [sp, #16]
    ldr     x1, [x9]
    add     x0, x9, #8
    bl      api_put
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_text

/* L1: true when x0 is not 0, else false. */
LOCAL_FUNCTION api_bool
    FRAME 0
    cbz     x0, 1f
    API_LIT api_true
    UNFRAME 0
1:  API_LIT api_false
    UNFRAME 0
END_FUNCTION api_bool

/* L1: a Checkpoint of the view at x0: {"epoch":…,"root":…}. Locals: x0. */
LOCAL_FUNCTION api_checkpoint
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_f_epoch
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_qdec
    API_LIT api_f_root
    ldr     x0, [sp, #16]
    add     x0, x0, #8
    mov     x1, #32
    bl      api_qhex
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION api_checkpoint

/* L0: x0 = the api_codes entry of the status x0, or 0. Uses x9-x11. */
LOCAL_FUNCTION api_code
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
END_FUNCTION api_code

/* L1: the text of the api_codes entry x0 at its byte x1 (8 the reason, 24 the message), or none for no entry. */
LOCAL_FUNCTION api_code_text
    FRAME 0
    cbz     x0, 9f
    add     x9, x0, x1
    ldp     x10, x1, [x9]
    ADDRESS x0, api_texts
    add     x0, x0, x10
    bl      api_put
9:  UNFRAME 0
END_FUNCTION api_code_text

/* L1: the decimal digits of the Uint256 at x0, little endian, in quotes. Locals: its eight 32-bit words, then the text from its end. */
LOCAL_FUNCTION api_qdec256
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
    bl      api_put
    UNFRAME 128
END_FUNCTION api_qdec256

/*
 * L2: the body of getSpec (beacon-api.md, Common rules): each key of API_SPEC_KEYS, with the
 * config of the view x22. Locals: L the record, L+8 an index, L+16 32 bytes of a value, L+48 a count.
 */
LOCAL_FUNCTION api_spec
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
    bl      api_put
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
    bl      api_qdec
    b       1b
3:  cmp     x10, #SPEC_HEX
    b.ne    4f
    add     x0, sp, #32
    mov     x1, x12
    bl      api_qhex
    b       1b
4:  cmp     x10, #SPEC_TEXT
    b.ne    5f
    API_LIT api_quote
    add     x0, sp, #32
    ldr     x1, [sp, #64]
    bl      api_put
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
    bl      api_qdec
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
    bl      api_qdec
    b       1b
7:  cmp     x10, #SPEC_CONFIG
    b.ne    8f
    cmp     x12, #CONFIG_KIND_U64
    b.ne    71f
    ldr     x0, [x0]
    bl      api_qdec
    b       1b
71: cmp     x12, #CONFIG_KIND_UINT256
    b.ne    72f
    bl      api_qdec256
    b       1b
72: cmp     x12, #CONFIG_KIND_TEXT
    b.ne    73f
    bl      api_text                        /* in quotes */
    b       1b
73: mov     x1, #4                          /* Version: 4 bytes; Hash32: 32; Address: 20 */
    cmp     x12, #CONFIG_KIND_HASH32
    mov     x9, #32
    csel    x1, x9, x1, eq
    cmp     x12, #CONFIG_KIND_ADDRESS
    mov     x9, #20
    csel    x1, x9, x1, eq
    bl      api_qhex
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
    bl      api_qdec
    API_LIT api_p_max
    ldr     x9, [sp, #24]
    ldr     x11, [x22, #ApiView_config]
    add     x11, x11, #(CONFIG_BLOB_SCHEDULE + 8)
    add     x11, x11, x9, lsl #4
    ldr     x0, [x11]
    bl      api_qdec
    API_LIT api_end1
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       81b
82: API_LIT api_p_rbracket
    b       1b
9:  API_LIT api_end2
    UNFRAME 64
END_FUNCTION api_spec

/*
 * L2: the body of getForkSchedule (beacon-api.md, Common rules), with the config of the view x22:
 * phase0, then each fork to fulu whose epoch is below 2^64 - 1. Locals: L the fork, L+8 the
 * previous version, L+16 the version, L+24 the epoch.
 */
LOCAL_FUNCTION api_fork_schedule
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
    bl      api_qhex
    API_LIT api_k_current
    add     x0, sp, #32
    mov     x1, #4
    bl      api_qhex
    API_LIT api_k_epoch
    ldr     x0, [sp, #40]
    bl      api_qdec
    API_LIT api_end1
    ldr     x9, [sp, #32]                   /* the next fork's previous version */
    str     x9, [sp, #24]
    b       1b
9:  API_LIT api_o_end
    UNFRAME 32
END_FUNCTION api_fork_schedule

/* ---------------------------------------------------------------- Validators (beacon-api.md, Common rules) */

.set API_ITEM_MAX, 576                      /* the most bytes of an item and its comma */

/* L0: x0 = the API_STATUS_* of the validator at x0 at the epoch x1. A leaf. Uses x9-x12. */
LOCAL_FUNCTION api_validator_status
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
END_FUNCTION api_validator_status

/*
 * L1: the item of the validator x1 of the state x0: x2 0 for getStateValidators, 1 for the
 * balances, 2 for the identities, 3 for their SSZ (64 bytes). Locals: L the validator, L+8 the
 * index, L+16 the kind, L+24 the balance, L+32 the epoch, L+48 an SSZ item.
 */
LOCAL_FUNCTION api_validator_item
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
    bl      api_put
    UNFRAME 112
1:  API_LIT api_v_index
    ldr     x0, [sp, #24]
    bl      api_qdec
    ldr     x9, [sp, #32]
    cmp     x9, #2
    b.eq    2f
    API_LIT api_v_balance
    ldr     x0, [sp, #40]
    bl      api_qdec
    ldr     x9, [sp, #32]
    cbnz    x9, 9f
    API_LIT api_v_status
    ldr     x0, [sp, #16]
    ldr     x1, [sp, #48]
    bl      api_validator_status
    ADDRESS x9, api_v_statuses
    mov     x10, #24
    madd    x9, x0, x10, x9
    ldrb    w1, [x9], #1
    mov     x0, x9
    bl      api_put
    API_LIT api_v_validator
    ldr     x0, [sp, #16]
    mov     x1, #48
    bl      api_qhex
    API_LIT api_v_credentials
    ldr     x0, [sp, #16]
    add     x0, x0, #NODE_VALIDATOR_CREDENTIALS
    mov     x1, #32
    bl      api_qhex
    API_LIT api_v_effective
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_EFFECTIVE_BALANCE]
    bl      api_qdec
    API_LIT api_v_slashed
    ldr     x9, [sp, #16]
    ldrb    w0, [x9, #NODE_VALIDATOR_SLASHED]
    bl      api_bool
    API_LIT api_v_eligibility
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_ELIGIBILITY]
    bl      api_qdec
    API_LIT api_v_activation
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_ACTIVATION]
    bl      api_qdec
    API_LIT api_v_exit
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_EXIT]
    bl      api_qdec
    API_LIT api_v_withdrawable
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_WITHDRAWABLE]
    bl      api_qdec
    API_LIT api_end2
    UNFRAME 112
    /* identities */
2:  API_LIT api_v_pubkey
    ldr     x0, [sp, #16]
    mov     x1, #48
    bl      api_qhex
    API_LIT api_v_activation
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #NODE_VALIDATOR_ACTIVATION]
    bl      api_qdec
9:  API_LIT api_end1
    UNFRAME 112
END_FUNCTION api_validator_item

/* L0: x0 = the index of the validator of the ValidatorRef in the ByteList x1 in the state x0, or 2^64 - 1. A leaf. Uses x0-x5, x9-x16. */
LOCAL_FUNCTION node_api_find_validator
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
END_FUNCTION node_api_find_validator

/*
 * L1: the selection of a chunk of a validator stream (node.md, NODE_WORK_API_CHUNK), at the cursor
 * at NodeEvent_api + 16 of the event x23: +16 a bitmap, in the scratch x0, of the validators of the
 * state x20 that the ValidatorRef items of data x21 name (0 with no data); +24 the epoch of the
 * state's slot; +40 the count of the validators selected. x0 = 0, or LANTERN_BUFFER_TOO_SMALL.
 * Locals: L the scratch's next byte, L+8 its end, L+16 the validators, L+24 their count, L+32 the
 * items, L+40 their count, L+48 the table of the public keys, L+56 its mask.
 */
LOCAL_FUNCTION node_api_validators_prep
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
END_FUNCTION node_api_validators_prep

/*
 * L1: the items of the pending stream of the entry x22, of the state x20 (node.md,
 * NODE_WORK_API_CHUNK), from the index at NodeEvent_api + 16 of the event x23, at the writer's
 * cursor x24 up to x26, with , between; then ]} once they are all written. x0 = 1 when whole, 0
 * when more is to come, 2 when the state has no such list. Locals: L the cursor, L+8
 * lantern_node_pending's out, L+32 the kind.
 */
LOCAL_FUNCTION api_pending_json
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
    bl      api_pending_item
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
END_FUNCTION api_pending_json

/*
 * L1: the JSON of the pending item at x0 of the kind x1 (lantern_node_pending): a PendingDeposit,
 * a PendingPartialWithdrawal or a PendingConsolidation, from its SSZ fields. Locals: the item.
 */
LOCAL_FUNCTION api_pending_item
    FRAME 16
    str     x0, [sp, #16]
    cmp     x1, #1
    b.eq    20f
    b.hi    30f
    /* {"pubkey":…,"withdrawal_credentials":…,"amount":…,"signature":…,"slot":…} */
    API_LIT api_q_pubkey
    ldr     x0, [sp, #16]
    mov     x1, #48
    bl      api_qhex
    API_LIT api_q_credentials
    ldr     x0, [sp, #16]
    add     x0, x0, #48
    mov     x1, #32
    bl      api_qhex
    API_LIT api_q_amount
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #80]
    bl      api_qdec
    API_LIT api_q_signature
    ldr     x0, [sp, #16]
    add     x0, x0, #88
    mov     x1, #96
    bl      api_qhex
    API_LIT api_q_slot
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #184]
    bl      api_qdec
    b       9f
    /* {"validator_index":…,"amount":…,"withdrawable_epoch":…} */
20: API_LIT api_q_validator
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_qdec
    API_LIT api_q_amount
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #8]
    bl      api_qdec
    API_LIT api_q_withdrawable
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #16]
    bl      api_qdec
    b       9f
    /* {"source_index":…,"target_index":…} */
30: API_LIT api_q_source
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_qdec
    API_LIT api_q_target
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #8]
    bl      api_qdec
9:  API_LIT api_end1
    UNFRAME 16
END_FUNCTION api_pending_item

/*
 * L1: the items of the validator stream of the entry x22, of the state x20, from the cursor at
 * NodeEvent_api + 16 of the event x23 (+0 the next index, +8 the status bits, +16 the bitmap,
 * +24 the epoch, +32 the items written), at the writer's cursor x24 up to x26; then ]} for JSON
 * once they are all written. x0 = 1 when whole, else 0. Locals: L the cursor, L+8 the kind of
 * the items, L+16 the validators' count.
 */
LOCAL_FUNCTION api_validators_json
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
    bl      api_validator_status
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
    bl      api_validator_item
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
END_FUNCTION api_validators_json

/*
 * L0: x0 = the epoch of getEpochCommittees of the route x0 and the state of the view x1 (beacon-api.md,
 * Common rules), or 2^64 - 1 for 400: an epoch above the state's + 1, one whose seed's RANDAO mix the
 * state no longer holds, or a slot of another epoch. A leaf. Uses x9-x13.
 */
LOCAL_FUNCTION node_api_committees_check
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
END_FUNCTION node_api_committees_check

/*
 * L0: the cursor of the getEpochCommittees stream of the entry x0, for the route x1 and the epoch x2
 * (node.md, NODE_EV_API): the first slot at 0, the first index at 8, the epoch at 24, the slot and
 * the index asked at 40 and 48 (2^64 - 1 for none). A leaf. Uses x9-x12.
 */
LOCAL_FUNCTION node_api_committees_cursor
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
END_FUNCTION node_api_committees_cursor

/*
 * L1: a chunk's start of a getEpochCommittees stream (node.md, NODE_WORK_API_CHUNK), at the cursor at
 * NodeEvent_api + 16 of the event x23: +56 get_committee_count_per_slot of the state x20 at the epoch
 * at +24; +72 the scratch x0, for api_committees_json. x0 = 0; 400 for an index asked at or past the
 * count, in the first chunk; LANTERN_BUFFER_TOO_SMALL for a scratch with no room for a committee and
 * lantern_get_beacon_committee; else the status of the count. Locals: L the epoch, L+8 the count.
 */
LOCAL_FUNCTION node_api_committees_prep
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
END_FUNCTION node_api_committees_prep

/*
 * L1: the items of the getEpochCommittees stream of the entry x22, of the state x20, from the cursor
 * at NodeEvent_api + 16 of the event x23 (+0 the slot, +8 the index, +16 the member, +24 the epoch,
 * +32 the items written, +40 and +48 the slot and the index asked or 2^64 - 1, +56 the committees per
 * slot, +64 1 within an item, +72 the scratch), at the writer's cursor x24 up to x26; then ]} once
 * they are all written. x0 = 1 when whole, 0 when more is to come, 2 when a committee fails.
 * Locals: L the cursor, L+8 the slot, L+16 the index, L+24 the committee's list.
 */
LOCAL_FUNCTION api_committees_json
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
    bl      api_qdec
    API_LIT api_c_slot
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_qdec
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
    bl      api_qdec
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
END_FUNCTION api_committees_json

/*
 * L1: the ids of the validator operation of the route x0 (node.md, NODE_EV_API): x0 = the new id
 * of a NODE_ACT_BYTES_PUT of its ValidatorRef items (getStateValidator: its validator_id), or 0
 * with none. Locals: a ByteList head whose offset reaches the items.
 */
LOCAL_FUNCTION node_api_ids
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
    bl      node_put
9:  UNFRAME 32
END_FUNCTION node_api_ids

/*
 * L1: the body of the kind x28 for the view x22: an error body of the status at [x0], or the
 * JSON of an operation (beacon-api.md, Common rules). Locals: x0.
 */
LOCAL_FUNCTION api_body
    FRAME 16
    str     x0, [sp, #16]
    cmp     x28, #API_BODY_ERROR
    b.ne    1f
    /* {"code":<n>,"message":"<m>"} */
    API_LIT api_e_code
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_dec
    API_LIT api_e_message
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_code
    mov     x1, #24
    bl      api_code_text
    API_LIT api_e_end
    UNFRAME 16
1:  cmp     x28, #API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    b.ne    11f
    /* {"code":400,"message":"BAD_REQUEST","failures":[…]}: x22 the event of the work */
    API_LIT api_e_code
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_dec
    API_LIT api_e_message
    ldr     x9, [sp, #16]
    ldr     x0, [x9]
    bl      api_code
    mov     x1, #24
    bl      api_code_text
    API_LIT api_f_list
    bl      api_failures
    UNFRAME 16
11: cmp     x28, #API_OP_GET_PEERS
    b.ne    116f
    bl      api_peers_body
    UNFRAME 16
116: cmp    x28, #API_OP_GET_PEER
    b.ne    117f
    API_LIT api_pe_data
    ldr     x0, [x22, #ApiView_peer]
    bl      api_peer_item
    API_LIT api_end1
    UNFRAME 16
117: cmp    x28, #API_OP_GET_DEBUG_CHAIN_HEADS_V2
    b.ne    110f
    bl      api_heads_body
    UNFRAME 16
110: cmp    x28, #API_OP_GET_DEBUG_FORK_CHOICE
    b.ne    115f
    bl      api_fork_choice_body
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
    bl      api_state_read_body
    UNFRAME 16
114: ldr    x9, [sp, #16]                   /* SSZ: its 128 bytes */
    ldr     x9, [x9, #8]
    tbz     x9, #3, 13f
    ADDQ    x0, x22, ApiView_att
    mov     x1, #128
    bl      api_put
    UNFRAME 16
    /* {"data":{"slot":…,"index":…,"beacon_block_root":…,"source":…,"target":…}} */
13: API_LIT api_a_slot
    LDQ     x0, x22, ApiView_att
    bl      api_qdec
    API_LIT api_a_index
    LDQ     x0, x22, ApiView_att + 8
    bl      api_qdec
    API_LIT api_a_root
    ADDQ    x0, x22, ApiView_att + 16
    mov     x1, #32
    bl      api_qhex
    API_LIT api_a_source
    ADDQ    x0, x22, ApiView_att + 48
    bl      api_checkpoint
    API_LIT api_a_target
    ADDQ    x0, x22, ApiView_att + 88
    bl      api_checkpoint
    API_LIT api_end2
    UNFRAME 16
12: cmp     x28, #API_OP_GET_NETWORK_IDENTITY
    b.ne    2f
    API_LIT api_i_peer_id
    add     x0, x22, #ApiView_peer_id
    bl      api_text
    API_LIT api_i_enr
    add     x0, x22, #ApiView_enr
    bl      api_text
    API_LIT api_i_p2p
    ldr     x9, [x22, #ApiView_p2p_address]
    cbz     x9, 14f
    add     x0, x22, #ApiView_p2p_address
    bl      api_text
14: API_LIT api_i_discovery
    ldr     x9, [x22, #ApiView_discovery_address]
    cbz     x9, 15f
    add     x0, x22, #ApiView_discovery_address
    bl      api_text
15: API_LIT api_i_seq
    ldr     x0, [x22, #ApiView_seq_number]
    bl      api_qdec
    API_LIT api_i_attnets
    add     x0, x22, #ApiView_attnets
    mov     x1, #8
    bl      api_qhex
    ldr     x9, [x22, #ApiView_fork]
    cmp     x9, #FORK_ALTAIR
    b.lo    16f
    API_LIT api_i_syncnets
    add     x0, x22, #ApiView_syncnets
    mov     x1, #1
    bl      api_qhex
    ldr     x9, [x22, #ApiView_fork]
    cmp     x9, #FORK_FULU
    b.lo    16f
    API_LIT api_i_cgc
    ldr     x0, [x22, #ApiView_custody_group_count]
    bl      api_qdec
16: API_LIT api_end3
    UNFRAME 16
2:  cmp     x28, #API_OP_GET_NODE_VERSION
    b.ne    3f
    API_LIT api_v_version
    add     x0, x22, #ApiView_version
    bl      api_text
    API_LIT api_end2
    UNFRAME 16
3:  cmp     x28, #API_OP_GET_SYNCING_STATUS
    b.ne    4f
    API_LIT api_s_head
    ldr     x0, [x22, #ApiView_head_slot]
    bl      api_qdec
    API_LIT api_s_distance
    ldr     x9, [x22, #ApiView_current_slot]
    ldr     x10, [x22, #ApiView_head_slot]
    subs    x0, x9, x10
    csel    x0, xzr, x0, lo
    bl      api_qdec
    API_LIT api_s_syncing
    ldr     x0, [x22, #ApiView_is_syncing]
    bl      api_bool
    API_LIT api_s_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_s_offline
    ldr     x0, [x22, #ApiView_el_offline]
    bl      api_bool
    API_LIT api_end2
    UNFRAME 16
4:  cmp     x28, #API_OP_GET_PEER_COUNT
    b.ne    5f
    API_LIT api_c_connected
    ldr     x0, [x22, #ApiView_peers]
    bl      api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  cmp     x28, #API_OP_GET_GENESIS
    b.ne    6f
    API_LIT api_g_time
    ldr     x0, [x22, #ApiView_genesis_time]
    bl      api_qdec
    API_LIT api_g_root
    add     x0, x22, #ApiView_genesis_validators_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_g_version
    add     x0, x22, #ApiView_genesis_fork_version
    mov     x1, #4
    bl      api_qhex
    API_LIT api_end2
    UNFRAME 16
6:  cmp     x28, #API_OP_GET_BLOCK_HEADER
    b.ne    7f
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
    API_LIT api_x_data
    API_LIT api_h_root
    add     x0, x22, #ApiView_head_root
    mov     x1, #32
    bl      api_qhex
    ldr     x0, [x22, #ApiView_head_slot]
    add     x1, x22, #ApiView_proposer_index
    ldr     x2, [x22, #ApiView_canonical]
    bl      api_header_json
    API_LIT api_end3
    UNFRAME 16
7:  cmp     x28, #API_OP_GET_STATE_FINALITY_CHECKPOINTS
    b.ne    9f
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
    API_LIT api_x_data
    API_LIT api_f_previous
    add     x0, x22, #ApiView_previous_justified
    bl      api_checkpoint
    API_LIT api_f_current
    add     x0, x22, #ApiView_current_justified
    bl      api_checkpoint
    API_LIT api_f_finalized
    add     x0, x22, #ApiView_finalized
    bl      api_checkpoint
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
    bl      api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
    API_LIT api_x_data
    cmp     x28, #API_OP_GET_STATE_FORK
    b.eq    11f
    API_LIT api_h_root
    add     x0, x22, #ApiView_head_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_end2
    UNFRAME 16
    /* getStateFork: {"previous_version":…,"current_version":…,"epoch":…} */
11: API_LIT api_k_previous
    ADDQ    x0, x22, ApiView_state_fork
    mov     x1, #4
    bl      api_qhex
    API_LIT api_k_current
    ADDQ    x0, x22, ApiView_state_fork + 4
    mov     x1, #4
    bl      api_qhex
    API_LIT api_k_epoch
    LDQ     x0, x22, ApiView_state_fork + 8
    bl      api_qdec
    API_LIT api_end2
    UNFRAME 16
12: cmp     x28, #API_OP_GET_SPEC
    b.ne    13f
    bl      api_spec
    UNFRAME 16
13: cmp     x28, #API_OP_GET_FORK_SCHEDULE
    b.ne    17f
    bl      api_fork_schedule
    UNFRAME 16
17: cmp     x28, #API_OP_GET_DEPOSIT_CONTRACT   /* {"data":{"chain_id":…,"address":…}} */
    b.ne    18f
    API_LIT api_d_chain
    ldr     x9, [x22, #ApiView_config]
    LDQ     x0, x9, CONFIG_DEPOSIT_CHAIN_ID
    bl      api_qdec
    API_LIT api_d_address
    ldr     x9, [x22, #ApiView_config]
    ADDQ    x0, x9, CONFIG_DEPOSIT_CONTRACT_ADDRESS
    mov     x1, #20
    bl      api_qhex
    API_LIT api_end2
    UNFRAME 16
18: cmp     x28, #API_OP_GET_STATE_VALIDATOR    /* {"execution_optimistic":…,"finalized":…,"data":<item>} */
    b.ne    19f
    API_LIT api_v_open
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
    API_LIT api_v_data
    ldr     x0, [x22, #ApiView_val_state]
    ldr     x1, [x22, #ApiView_val_index]
    mov     x2, #0
    bl      api_validator_item
    API_LIT api_end1
    UNFRAME 16
    /* getProposerDuties: {"dependent_root":…,"execution_optimistic":…,"data":[{"pubkey":…,"validator_index":…,"slot":…},…]} */
19: cmp     x28, #API_OP_GET_PROPOSER_DUTIES
    b.ne    18f
    API_LIT api_u_root
    add     x0, x22, #ApiView_duties
    mov     x1, #32
    bl      api_qhex
    API_LIT api_u_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_v_list
    str     xzr, [sp, #24]
20: ldr     x9, [sp, #24]
    cmp     x9, #SLOTS_PER_EPOCH
    b.hs    21f
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
    bl      api_qhex
    API_LIT api_u_index
    ldr     x9, [sp, #24]
    add     x10, x22, #(ApiView_duties + 32)
    ldr     x0, [x10, x9, lsl #3]
    bl      api_qdec
    API_LIT api_c_slot
    ldr     x9, [x22, #ApiView_val_state]
    ldr     x0, [x9, #NODE_STATE_SLOT]
    ldr     x9, [sp, #24]
    add     x0, x0, x9
    bl      api_qdec
    API_LIT api_end1
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       20b
21: API_LIT api_v_end
    UNFRAME 16
    /* {"dependent_root":…,"execution_optimistic":…,"data":[{"pubkey":…,…,"slot":…},…]}, x21 the items written */
18: cmp     x28, #API_OP_GET_SYNC_COMMITTEE_DUTIES
    b.ne    181f
    bl      api_sync_duties_body
    UNFRAME 16
181: cmp    x28, #API_OP_GET_ATTESTER_DUTIES
    b.ne    99f
    API_LIT api_u_root
    LDQ     x0, x22, ApiView_ad_out
    mov     x1, #32
    bl      api_qhex
    API_LIT api_u_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
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
    bl      api_qhex
    API_LIT api_u_index
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #40]
    bl      api_qdec
    API_LIT api_t_committee_index
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #16]
    bl      api_qdec
    API_LIT api_t_committee_length
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #24]
    bl      api_qdec
    API_LIT api_t_committees_at_slot
    LDQ     x9, x22, ApiView_ad_out
    ldr     x0, [x9, #32]
    bl      api_qdec
    API_LIT api_t_validator_committee_index
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #32]
    bl      api_qdec
    API_LIT api_c_slot
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #8]
    bl      api_qdec
    API_LIT api_end1
15: ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       17b
16: API_LIT api_v_end
99: UNFRAME 16
END_FUNCTION api_body

/*
 * L1: the body of getSyncCommitteeDuties (beacon-api.md): {"execution_optimistic":…,"data":[{"pubkey":…,
 * "validator_index":…,"validator_sync_committee_indices":[…]},…]} of the ValidatorRef items at
 * ApiView_sd_ids of the view x22, each by its places in the committee at ApiView_sync_out, the
 * pubkeys those of the state at ApiView_val_state. Locals: the item's index, the items written,
 * the validator, the place, its places written.
 */
LOCAL_FUNCTION api_sync_duties_body
    FRAME 48
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
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
    bl      api_qhex
    API_LIT api_u_index
    ldr     x0, [sp, #32]
    bl      api_qdec
    API_LIT api_sd_indices
    b       6f
5:  API_LIT api_p_comma
6:  ldr     x9, [sp, #48]
    add     x9, x9, #1
    str     x9, [sp, #48]
    ldr     x0, [sp, #40]
    sub     x0, x0, #1
    bl      api_qdec
    b       2b
7:  ldr     x9, [sp, #48]                   /* places written: the item's end */
    cbz     x9, 1b
    API_LIT api_v_end
    b       1b
9:  API_LIT api_v_end
    UNFRAME 48
END_FUNCTION api_sync_duties_body
.if NODE_VALIDATOR_MEM != 128
.error "api_sync_duties_body reads a pubkey at index * 128"
.endif

/*
 * L1: the body of getDebugChainHeadsV2 (beacon-api.md): {"data":[{"root":…,"slot":…,"execution_optimistic":…},…]}
 * of the store nodes at ApiView_val_state of the view x22 whose byte at ApiView_heads is 0. Locals: the
 * index, 1 once an item is written, the node.
 */
LOCAL_FUNCTION api_heads_body
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
    bl      api_qhex
    API_LIT api_q_slot
    ldr     x0, [sp, #32]
    ldr     x0, [x0, #BlockNode_slot]
    bl      api_qdec
    API_LIT api_ch_optimistic
    ldr     x0, [sp, #32]
    ldr     x0, [x0, #BlockNode_payload_status]
    cmp     x0, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x0, eq
    bl      api_bool
    API_LIT api_end1
8:  ldr     x11, [sp, #16]
    add     x11, x11, #1
    str     x11, [sp, #16]
    b       1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION api_heads_body

/*
 * L1: the body of getDebugForkChoice (beacon-api.md): {"justified_checkpoint":…,"finalized_checkpoint":…,
 * "fork_choice_nodes":[…]} of the store at ApiView_val_state of the view x22, each node's weight at
 * ApiView_weights. Locals: the index, the node.
 */
LOCAL_FUNCTION api_fork_choice_body
    FRAME 16
    API_LIT api_fc_justified
    ldr     x0, [x22, #ApiView_val_state]
    add     x0, x0, #Store_justified_checkpoint
    bl      api_checkpoint
    API_LIT api_fc_finalized
    ldr     x0, [x22, #ApiView_val_state]
    add     x0, x0, #Store_finalized_checkpoint
    bl      api_checkpoint
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
    bl      api_qdec
    API_LIT api_fc_block_root
    ldr     x0, [sp, #24]
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_parent
    ldr     x0, [sp, #24]
    add     x0, x0, #BlockNode_parent_root
    mov     x1, #32
    bl      api_qhex
    API_LIT api_fc_justified_epoch
    ldr     x0, [sp, #24]
    ldr     x0, [x0, #BlockNode_justified_checkpoint]   /* its epoch, the Checkpoint's first field */
    bl      api_qdec
    API_LIT api_fc_finalized_epoch
    ldr     x0, [sp, #24]
    ldr     x0, [x0, #BlockNode_finalized_epoch]
    bl      api_qdec
    API_LIT api_fc_weight
    LDQ     x9, x22, ApiView_weights
    ldr     x11, [sp, #16]
    ldr     x0, [x9, x11, lsl #3]
    bl      api_qdec
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
    bl      api_qhex
    API_LIT api_end1
    ldr     x11, [sp, #16]
    add     x11, x11, #1
    str     x11, [sp, #16]
    b       1b
9:  API_LIT api_v_end
    UNFRAME 16
END_FUNCTION api_fork_choice_body

/*
 * L1: ,"canonical":…,"header":{"message":{"slot":…,"proposer_index":…,"parent_root":…,"state_root":…,"body_root":…},"signature":…
 * of the slot x0, canonical x2, and at x1 the header's proposer_index, parent_root, state_root,
 * body_root and signature, in that order. Locals: x0, x1, x2.
 */
LOCAL_FUNCTION api_header_json
    FRAME 32
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    API_LIT api_h_canonical
    ldr     x0, [sp, #32]
    bl      api_bool
    API_LIT api_h_slot
    ldr     x0, [sp, #16]
    bl      api_qdec
    API_LIT api_h_proposer
    ldr     x9, [sp, #24]
    ldr     x0, [x9]
    bl      api_qdec
    API_LIT api_h_parent
    ldr     x0, [sp, #24]
    add     x0, x0, #(ApiView_parent_root - ApiView_proposer_index)
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_state
    ldr     x0, [sp, #24]
    add     x0, x0, #(ApiView_state_root - ApiView_proposer_index)
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_body
    ldr     x0, [sp, #24]
    add     x0, x0, #(ApiView_body_root - ApiView_proposer_index)
    mov     x1, #32
    bl      api_qhex
    API_LIT api_h_signature
    ldr     x0, [sp, #24]
    add     x0, x0, #(ApiView_signature - ApiView_proposer_index)
    mov     x1, #96
    bl      api_qhex
    UNFRAME 32
END_FUNCTION api_header_json
.if ApiView_parent_root - ApiView_proposer_index != 8 || ApiView_state_root - ApiView_proposer_index != 40 || ApiView_body_root - ApiView_proposer_index != 72 || ApiView_signature - ApiView_proposer_index != 104
.error "api_header_json reads the fields of a SignedBeaconBlockHeader after its slot"
.endif

/*
 * L1: getBlockHeaders' JSON, as api_stream_json: with x21, the address of an item's header (its
 * slot, then the fields api_header_json reads), the item {"root":…,"canonical":…,"header":…}, its
 * root at byte 0 of the entry x22's cursor and canonical bit 0 of its member, after , when
 * API_STREAM_ITEMS is set; then API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With x21 = 0:
 * ]}. x0 = 1 when the answer is whole, else 0.
 */
LOCAL_FUNCTION api_headers_json
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
    bl      api_qhex
    ldr     x0, [x21]
    add     x1, x21, #8
    ldr     x2, [x22, #NodeApi_member]
    and     x2, x2, #1
    bl      api_header_json
    API_LIT api_end2
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    orr     x9, x9, #(API_STREAM_ITEMS | API_STREAM_ITEM_DONE)
    str     x9, [x23, #(NodeEvent_api + 8)]
    mov     x0, #0
    UNFRAME 0
END_FUNCTION api_headers_json

/*
 * L0: x0 = the base58btc text of the x1 bytes at x0 (at most 48), written at x2: a 1 for each
 * leading zero byte, then the digits. x3: a work area of 72 bytes. Uses x4, x9-x15.
 */
LOCAL_FUNCTION api_base58
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
END_FUNCTION api_base58

/*
 * L1: a peer of getPeers and getPeer (beacon-api.md): {"peer_id":…,"enr":null,"last_seen_p2p_address":…,
 * "state":"connected","direction":…} of the NodePeer x0. Locals: the peer, the text's length, an
 * index, the text (72 bytes), base58's work area (72 bytes).
 */
LOCAL_FUNCTION api_peer_item
    FRAME 176
    str     x0, [sp, #16]
    add     x0, x0, #NodePeer_id
    ldr     x9, [sp, #16]
    ldr     x1, [x9, #NodePeer_id_len]
    add     x2, sp, #40
    add     x3, sp, #112
    bl      api_base58
    str     x0, [sp, #24]
    API_LIT api_pe_open
    add     x0, sp, #40
    ldr     x1, [sp, #24]
    bl      api_put
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
    bl      api_dec
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
    bl      api_hex16
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
    bl      api_dec
    b       7f
6:  API_LIT api_pe_udp
    ldr     x9, [sp, #16]
    ldr     x0, [x9, #(NodePeer_address + 8)]
    bl      api_dec
    API_LIT api_pe_quic
7:  API_LIT api_pe_p2p
    add     x0, sp, #40
    ldr     x1, [sp, #24]
    bl      api_put
    API_LIT api_pe_state
    ldr     x9, [sp, #16]
    ldr     x10, [x9, #NodePeer_direction]
    cmp     x10, #LIBP2P_OUTBOUND
    b.eq    8f
    API_LIT api_pe_inbound
    UNFRAME 176
8:  API_LIT api_pe_outbound
    UNFRAME 176
END_FUNCTION api_peer_item

/* L1: the lower case hex digits of the 16 bits x0, with no leading zeros, join the response. Locals: x0, a shift. */
LOCAL_FUNCTION api_hex16
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
    bl      api_put
    ldr     x9, [sp, #24]
    cbz     x9, 9f
    sub     x9, x9, #4
    str     x9, [sp, #24]
    b       3b
9:  UNFRAME 16
END_FUNCTION api_hex16

/*
 * L1: getPeers' body (beacon-api.md): {"data":[<peer>,…],"meta":{"count":…}} of the NodePeers of the
 * Node at ApiView_node of the view x22 whose state and direction are in the sets at
 * ApiView_peer_states and ApiView_peer_directions. Locals: the index, the count, the peer.
 */
LOCAL_FUNCTION api_peers_body
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
    bl      api_peer_item
    b       1b
9:  API_LIT api_pe_meta
    ldr     x0, [sp, #24]
    bl      api_dec
    API_LIT api_end2
    UNFRAME 32
END_FUNCTION api_peers_body
.if API_DIRECTION_INBOUND != LIBP2P_INBOUND || API_DIRECTION_OUTBOUND != LIBP2P_OUTBOUND
.error "api_peers_body: the direction bits are the libp2p directions"
.endif

/*
 * L1: (route x0) -> x0: the NodePeer whose peer ID's base58btc text is the route's peer_id, or 0.
 * Locals: the route, the index, the text (72 bytes), base58's work area (72 bytes).
 */
LOCAL_FUNCTION node_api_find_peer
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
    bl      api_base58
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
END_FUNCTION node_api_find_peer

/*
 * L1: the bodies of getStateRandao, getEpochSyncCommittees and getProposerLookahead (beacon-api.md),
 * as api_body: x22 the view, the local at x0 + 8 the flags. Locals: an index.
 */
LOCAL_FUNCTION api_state_read_body
    FRAME 16
    str     x0, [sp, #16]
    cmp     x28, #API_OP_GET_PROPOSER_LOOKAHEAD
    b.eq    30f
    /* {"execution_optimistic":…,"finalized":…,"data":{ */
    API_LIT api_x_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
    API_LIT api_x_data
    cmp     x28, #API_OP_GET_STATE_RANDAO
    b.ne    10f
    /* "randao":…}} */
    API_LIT api_r_randao
    ADDQ    x0, x22, ApiView_randao
    mov     x1, #32
    bl      api_qhex
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
    bl      api_qdec
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
    bl      api_qdec
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
    bl      api_put
    UNFRAME 16
    /* {"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[…]} */
31: API_LIT api_j_version
    ldr     x0, [x22, #ApiView_fork]
    bl      api_fork_name
    API_LIT api_j_optimistic
    ldr     x0, [x22, #ApiView_is_optimistic]
    bl      api_bool
    API_LIT api_x_finalized
    LDQ     x0, x22, ApiView_head_finalized
    bl      api_bool
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
    bl      api_qdec
    ldr     x9, [sp, #24]
    add     x9, x9, #1
    str     x9, [sp, #24]
    b       32b
34: API_LIT api_v_end
    UNFRAME 16
END_FUNCTION api_state_read_body
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
LOCAL_FUNCTION api_respond
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
    bl      api_body
1:  str     x24, [sp, #(L + 16)]
    mov     x25, #1                         /* the response */
    add     x24, x23, #24
    ldr     x9, [x23]
    add     x26, x23, x9
    /* HTTP/1.1 <code> <reason> CRLF */
    API_LIT api_http
    ldr     x0, [sp, #L]
    bl      api_dec
    API_LIT api_sp
    ldr     x9, [sp, #(L + 8)]
    tbnz    x9, #2, 2f
    ldr     x0, [sp, #L]
    bl      api_code
    mov     x1, #8
    bl      api_code_text
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
    bl      api_fork_name
    API_LIT api_crlf
3:  API_LIT api_length
    ldr     x0, [sp, #(L + 16)]
    bl      api_dec
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
    bl      api_body
8:  cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 32
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION api_respond

/*
 * L1: the values of the ApiView x0 that the node, x19, and the store, x20, give (beacon-api.md,
 * Common rules); the header and the checkpoints zero. Locals: L the view.
 */
LOCAL_FUNCTION node_api_view
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
    bl      node_find_block
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
    bl      node_store_slot
    ldr     x9, [sp, #16]
    str     x0, [x9, #ApiView_current_slot]
    add     x1, x19, #Node_config
    bl      node_fork
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
    LDQ     x10, x19, Node_config + CONFIG_CUSTODY_REQUIREMENT
    str     x10, [x9, #ApiView_custody_group_count]
    add     x0, x9, #ApiView_peer_id        /* the identity's texts */
    ADDQ    x1, x19, Node_api_identity
    mov     x2, #API_IDENTITY_SIZE
    bl      lantern_copy
    ldr     x0, [sp, #16]
    bl      api_view_finalized
    UNFRAME 16
END_FUNCTION node_api_view

/* L0: ApiView_head_finalized of the view x0: 1 when its head_root is the root of the store x20's finalized checkpoint. Uses x9-x16. */
LOCAL_FUNCTION api_view_finalized
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
END_FUNCTION api_view_finalized

/* L0: the 32 bytes at x1 to x0. Uses x16, x17. */
LOCAL_FUNCTION lantern_copy_root
    UNWIND_END_PROLOGUE
    COPY32  x0, x1
    ret
END_FUNCTION lantern_copy_root

/*
 * L1: one NODE_ACT_API_SEND of the connection x0, with last 1, at the end of the actions x24: the
 * response of api_respond with the view x1, the status x2, the body x3 and the flags x4; when it
 * does not fit, the error 500. With API_R_CLOSE, then a NODE_ACT_API_CLOSE. Locals: L the
 * connection, L+8 the flags, L+16 the action.
 */
LOCAL_FUNCTION node_api_send
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
    bl      api_respond
    cbz     x0, 1f
    mov     x0, #0                          /* no room: the error 500 */
    ldr     x1, [sp, #32]
    add     x1, x1, #32
    mov     x2, #500
    mov     x3, #API_BODY_ERROR
    ldr     x4, [sp, #24]
    and     x4, x4, #(API_R_CLOSE | API_R_KEEP)
    bl      api_respond
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
    bl      node_act
    ldr     x9, [sp, #16]
    str     x9, [x0, #16]
9:  UNFRAME 48
END_FUNCTION node_api_send

/*
 * L0: the NODE_EV_API or NODE_EV_API_IDENTITY x0 of size x1, whose ByteList at 24 is inside it
 * (node.md, NodeEvent): x0 = 0 when it keeps its rules, else 1; x1 = the scratch it needs. Uses
 * x9-x15.
 */
LOCAL_FUNCTION node_api_check
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
END_FUNCTION node_api_check

/* L0: x0 = the NODE_DB_REF of the Db's record of the block at x0, or 0. Uses x9-x13, and the stack. */
LOCAL_FUNCTION node_api_db_ref
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
    bl      node_db_block
    UNFRAME 16
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION node_api_db_ref

/*
 * L2: the answer to the NODE_EV_API x0 (node.md, lantern_node_step): x19 the node, x20 the store,
 * x23 the scratch, x24 the actions. x21 the event, x22 its HttpRequest, x25 the ApiRoute, x26 the
 * ApiView, x27 the connection, x28 the flags of api_respond. Locals: L the scratch's size.
 */
LOCAL_FUNCTION node_api_event
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
    bl      node_api_check
    ldr     x9, [sp, #L]
    sub     x9, x9, x1
    str     x9, [x23]
    add     x26, x23, x9
    add     x25, x26, #ApiView__size
    MOVQ    x9, ApiView__size
    sub     x9, x1, x9
    str     x9, [x25]
    mov     x0, x26
    bl      node_api_view
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
    cmp     x3, #API_OP_PRODUCE_ATTESTATION_DATA
    b.eq    59f
    cmp     x3, #API_OP_GET_ATTESTER_DUTIES
    b.eq    58f
    cmp     x3, #API_OP_GET_SYNC_COMMITTEE_DUTIES
    b.eq    53f
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
    mov     x0, x3
    bl      node_submit_topic
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
    bl      node_api_lookup
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
69: mov     x0, x25                         /* a state: its lookup, then the state at its slot */
    mov     x1, x26
    bl      node_api_state
    mov     x2, x0
    cbnz    x0, 80f
    mov     x0, x26
    bl      node_api_advance
    ldr     x0, [x25, #ApiRoute_op]
    cmp     x0, #API_OP_GET_STATE_V2
    b.eq    64f
    sub     x9, x0, #API_OP_GET_PENDING_CONSOLIDATIONS  /* the pending lists: a stream of the state, no data */
    cmp     x9, #2
    b.hi    695f
    str     xzr, [x26, #ApiView_look_data]
    b       64f
695: cmp    x0, #API_OP_GET_STATE_RANDAO    /* getStateRandao, getEpochSyncCommittees: the epoch in the work's data */
    ccmp    x0, #API_OP_GET_EPOCH_SYNC_COMMITTEES, #4, ne
    b.ne    691f
    ldr     x9, [x25, #ApiRoute_present]
    tbnz    x9, #API_PARAM_EPOCH, 692f
    mov     x10, #-1
    str     x10, [x25, #ApiRoute_epoch]
692: add    x0, x25, #ApiRoute_epoch
    bl      node_api_put8
    str     x0, [x26, #ApiView_look_data]
    b       67f
691: cmp    x0, #API_OP_GET_PROPOSER_LOOKAHEAD  /* getProposerLookahead: SSZ, an answer flag */
    b.ne    693f
    ldr     x9, [x25, #ApiRoute_response]
    cmp     x9, #API_TYPE_SSZ
    b.ne    67f
    orr     x21, x21, #API_ANSWER_SSZ
    b       67f
693: sub    x9, x0, #API_OP_GET_STATE_VALIDATORS
    cmp     x9, #(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS)
    b.hi    67f
    mov     x0, x25                         /* the validator operations: their ids; getStateValidator a work, the others a stream */
    bl      node_api_ids
    str     x0, [x26, #ApiView_look_data]
    ldr     x0, [x25, #ApiRoute_op]
    cmp     x0, #API_OP_GET_STATE_VALIDATOR
    b.ne    64f
    b       67f
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
    bl      node_store_slot
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
    bl      node_find_block
    cmn     x0, #1
    b.eq    532f
    ldr     x0, [x1, #NodeBlock_slot]
    add     x1, x19, #Node_config
    bl      node_fork
    cmp     x0, #FORK_ALTAIR
    b.lo    532f
    add     x0, x19, #Node_head_root
    bl      node_find_block
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
    bl      node_api_state
    mov     x2, #400
    cbnz    x0, 80f
    ldr     x9, [sp, #(L + 8)]
    STQ     x9, x26, ApiView_next_period
    mov     x0, x25                         /* its ids in the work's data */
    bl      node_api_ids
    str     x0, [x26, #ApiView_look_data]
    b       67f
532: mov    x0, x20                         /* else the state of the epoch's first slot, as getAttesterDuties */
    bl      node_store_slot
    ldr     x10, [x25, #ApiRoute_epoch]
    mov     x11, #SLOTS_PER_EPOCH
    b       583f
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
    bl      node_store_slot
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
    mov     x0, x25
    mov     x1, x26
    bl      node_api_state
    mov     x2, #400
    cbnz    x0, 80f
    ldr     x9, [x25, #ApiRoute_id_slot]
    str     x9, [x26, #ApiView_head_slot]
    mov     x0, x26
    bl      node_api_advance
    mov     x0, x25                         /* its ids in the work's data */
    bl      node_api_ids
    str     x0, [x26, #ApiView_look_data]
    b       67f
59: mov     x2, #503                        /* produceAttestationData: 503 while syncing; 400 past the store's slot */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x0, x20
    bl      node_store_slot
    ldr     x10, [x25, #ApiRoute_slot]
    mov     x2, #400
    cmp     x10, x0
    b.hi    80f
    mov     x9, #API_ID_SLOT                /* the state of the slot, as a state_id of it; none: 400 */
    stp     x9, x10, [x25, #ApiRoute_id_kind]
    mov     x0, x25
    mov     x1, x26
    bl      node_api_state
    mov     x2, #400
    cbnz    x0, 80f
    mov     x2, #503                        /* an optimistic block: 503 */
    ldr     x9, [x26, #ApiView_is_optimistic]
    cbnz    x9, 80f
    mov     x0, x26
    bl      node_api_advance
    add     x0, x25, #ApiRoute_committee_index  /* its committee index in the work's data */
    bl      node_api_put8
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
    bl      node_api_find_peer
    mov     x2, #404
    cbz     x0, 80f
    str     x0, [x26, #ApiView_peer]
    mov     x2, #200
    mov     x3, #API_OP_GET_PEER
    b       81f
57: mov     x0, x27                         /* getBlockHeaders: a stream of the blocks of its query */
    mov     x1, x25
    mov     x2, x21
    bl      node_api_headers_stream
    b       90f
68: mov     x0, x27                         /* a pool GET: a stream of the pool; getAggregatedAttestationV2 with none 404 */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      node_api_pool_stream
    cbz     x0, 90f
    mov     x2, x0
    b       80f
60: mov     x0, x27                         /* a pool POST: a work checks its operations */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x22
    mov     x4, x26
    bl      node_api_submit
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
61: mov     x0, x27                         /* eventstream: an entry, and the head */
    mov     x1, x25
    mov     x2, x21
    bl      node_api_subscribe
    b       90f
63: mov     x2, #503                        /* getProposerDuties: 503 while syncing; 400 past the next epoch */
    ldr     x9, [x26, #ApiView_is_syncing]
    cbnz    x9, 80f
    mov     x0, x20
    bl      node_store_slot
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
    mov     x0, x25
    mov     x1, x26
    bl      node_api_state
    mov     x2, x0
    cbnz    x0, 80f
    ldr     x9, [x25, #ApiRoute_id_slot]    /* brought to the first slot */
    str     x9, [x26, #ApiView_head_slot]
    mov     x0, x26
    bl      node_api_advance
    b       67f
65: mov     x0, x25                         /* a block: its lookup */
    mov     x1, x26
    bl      node_api_block
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
67: ldr     x0, [x25, #ApiRoute_op]         /* a work */
    mov     x1, x27
    mov     x2, x21
    mov     x3, x26
    bl      node_api_encode
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
54: mov     x0, x27                         /* a sidecar stream of the block */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      node_api_sidecar_stream
    cbz     x0, 90f
    mov     x2, x0
    b       80f
64: mov     x0, x27                         /* a stream of the answer */
    mov     x1, x25
    mov     x2, x21
    mov     x3, x26
    bl      node_api_stream
    cbz     x0, 90f
    mov     x2, x0
    b       80f
7:  mov     x2, #501                        /* another operation */
80: mov     x3, #API_BODY_ERROR
81: mov     x0, x27
    mov     x1, x26
    mov     x4, x28
    bl      node_api_send
90: ldr     x9, [sp, #L]
    str     x9, [x23]
    LEAVE 16
END_FUNCTION node_api_event

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_ENCODE (node.md, lantern_node_step): its
 * response to the connection, or the error 500. x19 the node, x24 the actions. x21 the event,
 * x22 the action, x23 the response's bytes, x25 the flags.
 */
LOCAL_FUNCTION node_api_done
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_arg]
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
    b.ne    2f
    ldr     x1, [x21, #NodeAction_data]
    cbz     x1, 2f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      node_ids
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
    bl      node_act
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
    bl      node_act
    ldr     x9, [x21, #NodeAction_target]
    str     x9, [x0, #16]
    LEAVE 0
5:  ldr     x0, [x21, #NodeAction_target]   /* not valid: the error 500 */
    mov     x1, #0
    mov     x2, #500
    mov     x3, #API_BODY_ERROR
    mov     x4, x25
    bl      node_api_send
9:  LEAVE 0
END_FUNCTION node_api_done

/*
 * (node, store, work, state_a, data, scratch, event, room) -> status: a NODE_WORK_API_ENCODE of
 * lantern_node_run (node.md): the response at NodeEvent_chunk of the event, whose buffer has room
 * bytes. x19 the node, x20 the store, x21 the work, x22 state_a, x23 data, x24 the scratch, x25
 * the event, x26 the ApiView at the end of scratch, x27 the operation, x28 the room. Locals: L the
 * scratch's size, L+8 a kept word, L+16 a Result, L+24 a blob count.
 */
LOCAL_FUNCTION node_api_run
    ENTER 32
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
    bl      node_api_view
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
    cmp     x27, #API_OP_GET_SPEC
    b.eq    5f
    cmp     x27, #API_OP_GET_DEBUG_CHAIN_HEADS_V2
    b.eq    29f
    cmp     x27, #API_OP_GET_DEBUG_FORK_CHOICE
    b.eq    28f
    ldr     x0, [x22, #NODE_STATE_SLOT]     /* a state at the work's slot, else the work that brought it there failed */
    lsr     x9, x9, #24
    cmp     x0, x9
    b.ne    42f
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
    cmp     x27, #API_OP_GET_STATE_VALIDATOR
    b.ne    271f
    mov     x0, x22                         /* getStateValidator: the validator of its ids */
    mov     x1, x23
    cbz     x1, 8f
    bl      node_api_find_validator
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
    b.ne    26f
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
26: cmp     x27, #API_OP_GET_PROPOSER_DUTIES
    b.ne    23f
    mov     x0, x22                         /* getProposerDuties: lantern_node_proposers */
    add     x1, x19, #Node_config
    mov     x2, x24
    add     x3, x26, #ApiView_duties
    FORK_CALL node_proposers
    cmp     x0, #LANTERN_BUFFER_TOO_SMALL
    b.eq    71f
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
    bl      node_fork
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
    bl      node_fork
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
53: cmp     x27, #API_OP_GET_PROPOSER_LOOKAHEAD /* Eth-Consensus-Version of getProposerLookahead */
    b.ne    54f
    orr     x4, x4, #API_R_VERSION
54: bl      api_respond
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
    bl      node_fork
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
    LEAVE 32
8:  mov     x0, #LANTERN_INVALID_EVENT
    LEAVE 32
71: ldr     x9, [sp, #L]
    str     x9, [x24]
7:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION node_api_run

/*
 * (node, work, state_a, data, scratch, event, room) -> status: a NODE_WORK_API_EVENT of
 * lantern_node_run (node.md): the event's text at NodeEvent_chunk of the event, whose buffer has
 * room bytes. x19 the node, x21 the work, x22 state_a, x23 data, x24 the scratch, x25 the event,
 * x26 the ApiView at the end of scratch, x27 the topic, x28 the room. Locals: L the scratch's
 * size, L+8 a Result, L+16 a blob count.
 */
LOCAL_FUNCTION node_api_event_run
    ENTER 32
    mov     x19, x0
    mov     x21, x1
    mov     x22, x2
    mov     x23, x3
    mov     x24, x4
    mov     x25, x5
    mov     x28, x6
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
    cmp     x27, #API_TOPIC_FINALIZED_CHECKPOINT
    b.ne    8f
    cbnz    x23, 3f
1:  cbz     x22, 8f                         /* of a post-state: lantern_node_event_roots */
    ldr     x0, [x22, #NODE_STATE_SLOT]
    str     x0, [x26, #ApiView_event_slot]
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x15, x0
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
    bl      node_fork
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
    bl      api_event_text
    cbnz    x0, 71f
    ldr     x9, [x25, #(NodeEvent_chunk + 16)]  /* the event's size covers the text */
    add     x9, x9, #(NodeEvent_chunk + 24 + 7)
    and     x9, x9, #~7
    str     x9, [x25]
    sub     x9, x9, #NodeEvent_chunk
    str     x9, [x25, #NodeEvent_chunk]
    b       9f
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
END_FUNCTION node_api_event_run

/* ---------------------------------------------------------------- Lookup (beacon-api.md, Common rules) */

/* L1: x0 = the NodeBlock index of the imported parent of the entry x0, or 2^64 - 1; x1 = its entry. Uses x9-x15. */
LOCAL_FUNCTION node_api_parent
    FRAME 0
    add     x0, x0, #NodeBlock_parent_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.eq    9f
    mov     x0, #-1
9:  UNFRAME 0
END_FUNCTION node_api_parent

/*
 * L1: the block of the chain at or below the slot x0: x0 = its NodeBlock index, x1 = its entry; or
 * x0 = 2^64 - 1 when the lowest block of the chain the node keeps, x1 (0 with no head), is above
 * the slot. Locals: L the slot, L+8 an entry.
 */
LOCAL_FUNCTION node_api_below
    FRAME 32
    str     x0, [sp, #16]
    add     x0, x19, #Node_head_root
    bl      node_find_block
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
    bl      node_api_parent
    cmn     x0, #1
    b.ne    1b
    ldr     x1, [sp, #24]
9:  UNFRAME 32
END_FUNCTION node_api_below

/* L1: x0 = 1 when the block entry x0 is on the chain, else 0. Locals: L the entry. */
LOCAL_FUNCTION node_api_on_chain
    FRAME 16
    str     x0, [sp, #16]
    ldr     x0, [x0, #NodeBlock_slot]
    bl      node_api_below
    cmn     x0, #1
    b.eq    8f
    ldr     x9, [sp, #16]
    cmp     x1, x9
    cset    x0, eq
    UNFRAME 16
8:  mov     x0, #0
    UNFRAME 16
END_FUNCTION node_api_on_chain

/* L1: x0 = 1 when the slot x0 is at most that of the block of the store's finalized root, else 0. Locals: x0. */
LOCAL_FUNCTION node_api_final_block
    FRAME 16
    str     x0, [sp, #16]
    bl      node_f_slot
    ldr     x9, [sp, #16]
    cmn     x0, #1
    b.eq    8f
    cmp     x9, x0
    cset    x0, ls
    UNFRAME 16
8:  mov     x0, #0
    UNFRAME 16
END_FUNCTION node_api_final_block

/*
 * L2: the block of the block_id of the ApiRoute x0 into the ApiView x1 (beacon-api.md, Common
 * rules): head_root, head_slot, canonical, head_finalized, is_optimistic, look_index, look_data,
 * and for a block the node keeps look_state and look_state_slot. x0 = 0, or 404 for none. x21 the
 * route, x22 the view, x25 the entry, x26 the slot. Locals: L the Db's slot.
 */
LOCAL_FUNCTION node_api_block
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
    bl      node_find_block
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
    bl      node_api_below
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
    bl      node_db_slot
    cbz     x0, 80f
    b       6f                              /* DbSlot_root is at 0 */
4:  bl      node_find_block                 /* head, finalized: the block of that root */
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
    bl      node_api_db_ref
51: str     x0, [x22, #ApiView_look_data]
    mov     x0, x25
    bl      node_api_on_chain
    str     x0, [x22, #ApiView_canonical]
    cbz     x0, 52f
    mov     x0, x26
    bl      node_api_final_block
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
    bl      node_db_block
    str     x0, [x22, #ApiView_look_data]
    mov     x0, x26
    bl      node_api_final_block
    STQ     x0, x22, ApiView_head_finalized
    mov     x0, #0
    LEAVE 16
80: mov     x0, #404
    LEAVE 16
END_FUNCTION node_api_block

/*
 * L2: the state of the state_id of the ApiRoute x0 into the ApiView x1 (beacon-api.md, Common
 * rules): look_state, a state the node keeps, at look_state_slot; head_slot the slot it goes to;
 * head_finalized and is_optimistic. x0 = 0, or 404 for none. x21 the route, x22 the view, x25 the
 * block's entry, x26 the slot, x27 the checkpoint.
 */
LOCAL_FUNCTION node_api_state
    ENTER 0
    mov     x21, x0
    mov     x22, x1
    str     xzr, [x22, #ApiView_look_state]
    str     xzr, [x22, #ApiView_look_copy]
    mov     x9, #-1
    str     x9, [x22, #ApiView_look_index]
    ldr     x9, [x21, #ApiRoute_id_kind]
    cmp     x9, #API_ID_HEAD
    b.ne    1f
    add     x0, x19, #Node_head_root        /* head: its post-state at its slot */
    bl      node_find_block
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
    bl      node_find_block                 /* the optimistic status of its block */
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
    bl      node_find_checkpoint
    cmn     x0, #1
    b.eq    22f
    ldr     x9, [x1, #NodeCheckpoint_state_id]
    cbz     x9, 22f
    str     x9, [x22, #ApiView_look_state]
    str     x26, [x22, #ApiView_look_state_slot]
    b       7f
22: add     x0, x27, #8
    bl      node_find_block
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
    bl      node_store_slot
    cmp     x26, x0
    b.hi    80f
    mov     x0, x26
    bl      node_api_below
    cmn     x0, #1
    b.eq    80f
5:  mov     x25, x1                         /* the block's post-state, again when the node let it go */
    ldr     x9, [x25, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    str     x9, [x22, #ApiView_is_optimistic]
    ldr     x0, [x25, #NodeBlock_state_id]
    cbnz    x0, 6f
    bl      node_f_slot
    ldr     x9, [x25, #NodeBlock_slot]
    cmn     x0, #1
    b.eq    80f
    cmp     x9, x0
    b.ls    80f
    mov     x0, x25
    bl      node_rebuild
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
    LEAVE 0
80: mov     x0, #404
    LEAVE 0
END_FUNCTION node_api_state

/*
 * L2: the state of the ApiView x0 at its slot (node.md, NODE_EV_API): when head_slot is past
 * look_state_slot, a STATE_COPY of look_state, the copy across the fork boundaries to head_slot,
 * and a SLOTS work of it to head_slot when it is below it; look_state is the copy, look_copy 1.
 * x21 the view, x22 the copy, x25 the copy's slot.
 */
LOCAL_FUNCTION node_api_advance
    ENTER 0
    mov     x21, x0
    ldr     x9, [x21, #ApiView_look_state_slot]
    ldr     x10, [x21, #ApiView_head_slot]
    cmp     x10, x9
    b.ls    9f
    bl      node_new_id
    mov     x22, x0
    mov     x2, x0
    mov     x0, #NODE_ACT_STATE_COPY
    ldr     x1, [x21, #ApiView_look_state]
    bl      node_ids
    mov     x0, x22
    ldr     x1, [x21, #ApiView_look_state]
    ldr     x2, [x21, #ApiView_look_state_slot]
    ldr     x3, [x21, #ApiView_head_slot]
    bl      node_cross
    mov     x22, x0
    ldr     x25, [x21, #ApiView_look_state_slot]    /* the copy's slot: the first of the target's fork, when it crossed one */
    mov     x0, x25
    add     x1, x19, #Node_config
    bl      node_fork
    mov     x26, x0
    ldr     x0, [x21, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      node_fork
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
    bl      node_work
2:  str     x22, [x21, #ApiView_look_state]
    mov     x9, #1
    str     x9, [x21, #ApiView_look_copy]
9:  LEAVE 0
END_FUNCTION node_api_advance

/*
 * L1: a NODE_WORK_API_ENCODE of the operation x0 for the connection x1 with the answer flags x2,
 * from the lookup in the ApiView x3 (node.md, NODE_EV_API); then a STATE_FREE of the state when it
 * is a copy. x0 = 0, or 404 for a header with neither bytes nor a post-state. Locals: L the view.
 */
LOCAL_FUNCTION node_api_encode
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
    ldr     x9, [x3, #ApiView_look_data]
    csel    x3, x9, xzr, eq
3:  mov     x0, #NODE_WORK_API_ENCODE
    mov     x2, #0
    bl      node_work
    ldr     x9, [sp, #16]                   /* a copy goes after the work */
    ldr     x10, [x9, #ApiView_look_copy]
    cbz     x10, 9f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x9, #ApiView_look_state]
    mov     x2, #0
    bl      node_ids
9:  mov     x0, #0
    UNFRAME 16
END_FUNCTION node_api_encode

/*
 * L2: (connection x0, route x1, answer flags x2) -> x0: a state_id of a root (node.md, NODE_EV_API):
 * a NodeApi entry with API_STREAM_LOOKUP and a NODE_WORK_API_LOOKUP with the head's post-state;
 * 0, or 404 with no head post-state. x21 the route, x25 the flags, x27 the connection. Locals: L
 * the entry's index, L+8 the entry.
 */
LOCAL_FUNCTION node_api_lookup
    ENTER 16
    mov     x27, x0
    mov     x21, x1
    orr     x25, x2, #API_STREAM_LOOKUP
    orr     x25, x25, #API_STREAM_BUSY
    ldr     x9, [x21, #ApiRoute_response]
    cmp     x9, #API_TYPE_SSZ
    b.ne    1f
    orr     x25, x25, #API_STREAM_SSZ
1:  add     x0, x19, #Node_head_root
    bl      node_find_block
    cmn     x0, #1
    b.eq    80f
    ldr     x9, [x1, #NodeBlock_state_id]
    cbz     x9, 80f
    bl      node_api_new
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
    ldr     x9, [x21, #ApiRoute_op]         /* the validator operations and getEpochCommittees: statuses, validator_id, epoch, slot, index, present and ids */
    sub     x9, x9, #API_OP_GET_STATE_VALIDATORS
    cmp     x9, #(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS)
    b.hi    2f
    ldr     x1, [sp, #(L + 8)]
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
    mov     x0, x21
    bl      node_api_ids
    ldr     x1, [sp, #(L + 8)]
    str     x0, [x1, #NodeApi_data]
    cbz     x0, 2f
    ldr     x9, [x1, #NodeApi_flags]
    orr     x9, x9, #API_STREAM_OWN
    str     x9, [x1, #NodeApi_flags]
2:  add     x0, x19, #Node_head_root
    bl      node_find_block
    ldr     x1, [x1, #NodeBlock_state_id]
    mov     x0, #NODE_WORK_API_LOOKUP
    mov     x2, #0
    mov     x3, #0
    mov     x4, x27
    ldr     x5, [sp, #L]
    bl      node_work
    mov     x0, #0
    LEAVE 16
80: mov     x0, #404
    LEAVE 16
END_FUNCTION node_api_lookup

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_LOOKUP (node.md, lantern_node_step): the entry
 * ends; the answer for the state_id of the slot found, or 404. x19 the node, x20 the store, x23 the
 * scratch, x24 the actions. x21 the event, x22 the entry, x25 the flags, x26 the view, x27 the
 * connection, x28 the operation. Locals: L the scratch's size, L+8 the route.
 */
LOCAL_FUNCTION node_api_lookup_done
    ENTER 128
    mov     x21, x0
    ldr     x9, [x21, #NodeAction_arg]
    PART    x10, x11, x19, Node_api
    cmp     x9, x11
    b.hs    99f
    mov     x12, #NodeApi__mem
    madd    x22, x9, x12, x10
    ldr     x27, [x22, #NodeApi_connection]
    cbz     x27, 99f
    ldr     x10, [x21, #NodeAction_target]
    cmp     x27, x10
    b.ne    99f
    ldr     x25, [x22, #NodeApi_flags]
    tst     x25, #API_STREAM_LOOKUP
    b.eq    99f
    ldr     x28, [x22, #NodeApi_op]
    tbz     x25, #5, 1f                     /* API_STREAM_GONE: the entry ends, its ids with it */
    mov     x0, x22
    bl      node_api_end
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
    and     x9, x25, #~API_STREAM_OWN       /* the entry ends; it owns no bytes */
    str     x9, [x22, #NodeApi_flags]
    mov     x0, x22
    bl      node_api_end
    ldr     x9, [x23]                       /* the ApiView, then an ApiRoute, at the end of scratch */
    str     x9, [sp, #L]
    MOVQ    x10, ApiView__size + API_ROUTE_FIXED
    sub     x9, x9, x10
    str     x9, [x23]
    add     x26, x23, x9
    mov     x0, x26
    bl      node_api_view
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
    ldr     x9, [x21, #NodeEvent_index]
    str     x9, [x0, #ApiRoute_id_slot]
    mov     x2, #404
    cmn     x9, #1
    b.eq    80f
    mov     x1, x26
    bl      node_api_state
    mov     x2, x0
    cbnz    x0, 80f
    mov     x0, x26
    bl      node_api_advance
    and     x2, x25, #(API_STREAM_CLOSE | API_STREAM_HTTP10)
    ldr     x9, [sp, #(L + 16)]             /* the ids go to the answer */
    str     x9, [x26, #ApiView_look_data]
    str     xzr, [sp, #(L + 16)]
    cmp     x28, #API_OP_GET_STATE_V2
    b.eq    2f
    cmp     x28, #API_OP_GET_STATE_VALIDATOR
    b.eq    1f
    sub     x9, x28, #API_OP_GET_STATE_VALIDATORS
    cmp     x9, #(API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS)
    b.hi    1f
2:  mov     x0, x27                         /* getStateV2, the validator streams and getEpochCommittees: a stream */
    ldr     x1, [sp, #(L + 8)]
    mov     x3, x26
    bl      node_api_stream
    mov     x2, x0
    cbnz    x0, 80f
    b       90f
1:  mov     x0, x28                         /* the others: a work */
    mov     x1, x27
    mov     x3, x26
    bl      node_api_encode
    mov     x2, x0
    cbz     x0, 90f
80: ldr     x1, [sp, #(L + 16)]             /* ids no answer took: they go */
    cbz     x1, 82f
    str     x2, [sp, #(L + 24)]
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x2, #0
    bl      node_ids
    ldr     x2, [sp, #(L + 24)]
82: mov     x0, x27                         /* an error: with close, or keep-alive for HTTP/1.0 */
    mov     x1, #0
    mov     x3, #API_BODY_ERROR
    and     x4, x25, #API_R_CLOSE
    cbnz    x4, 81f
    tst     x25, #API_STREAM_HTTP10
    mov     x9, #API_R_KEEP
    csel    x4, x9, xzr, ne
81: bl      node_api_send
90: ldr     x9, [sp, #L]
    str     x9, [x23]
99: LEAVE 128
END_FUNCTION node_api_lookup_done

/*
 * (node, work, state_a, scratch, event) -> status: a NODE_WORK_API_LOOKUP of lantern_node_run
 * (node.md): at NodeEvent_index of the event, the slot whose state on the chain of state_a has the
 * root of the NodeApi entry at the work's arg, or 2^64 - 1. x19 the node, x21 the work, x22 the
 * state, x23 the event, x24 the root, x25 the slot, x26 the lowest slot.
 */
LOCAL_FUNCTION node_api_lookup_run
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
    bl      node_fork
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
    bl      node_api_same_root
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
    bl      node_api_same_root
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
END_FUNCTION node_api_lookup_run

/* L0: x0 = 1 when the 32 bytes at x0 and x1 are the same, else 0. Uses x9-x12. */
LOCAL_FUNCTION node_api_same_root
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
END_FUNCTION node_api_same_root

/* ---------------------------------------------------------------- Streams (node.md, NodeApi) */

/* L0: x0 = the free NodeApi entries of the node x19: the capacity past the count, and the free ones below it. Uses x9-x12, x16. */
LOCAL_FUNCTION node_api_free
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
END_FUNCTION node_api_free

/* L0: x0 = the index of the NodeApi entry of the connection x0, or 2^64 - 1; x1 = the entry. Uses x9-x12, x16. */
LOCAL_FUNCTION node_api_find
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
END_FUNCTION node_api_find

/* L0: x0 = the index of a free NodeApi entry (the first free, else the next; the step checked one is free), x1 = the entry. Uses x9-x12, x16. */
LOCAL_FUNCTION node_api_new
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
END_FUNCTION node_api_new

/*
 * L1: the end of the stream of the NodeApi entry x0: the entry is free, the api part's count drops
 * past the free entries at its end; with API_STREAM_OWN, a BYTES_FREE of its data, which node_ids
 * gives to another entry that sends the same bytes. Locals: L data, L+8 flags.
 */
LOCAL_FUNCTION node_api_end
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
    bl      node_ids
8:  ldr     x9, [sp, #24]
    tbz     x9, #12, 9f                     /* API_STREAM_OWN_STATE */
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [sp, #32]
    mov     x2, #0
    bl      node_ids
9:  UNFRAME 32
END_FUNCTION node_api_end

/* L1: a NODE_WORK_API_CHUNK of the NodeApi entry x1 at index x0, which takes API_STREAM_BUSY. */
LOCAL_FUNCTION node_api_chunk_work
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
    bl      node_work
    UNFRAME 0
END_FUNCTION node_api_chunk_work

/* L1: NODE_EV_API_SENT of the connection x0: an event stream's sent is 0; another stream's next chunk, unless one is queued. */
LOCAL_FUNCTION node_api_sent
    FRAME 0
    bl      node_api_find
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeApi_op]
    cmp     x9, #API_OP_EVENTSTREAM
    b.ne    1f
    str     xzr, [x1, #NodeApi_sent]
    b       9f
1:  ldr     x9, [x1, #NodeApi_flags]
    tbnz    x9, #4, 9f                      /* API_STREAM_BUSY */
    bl      node_api_chunk_work
9:  UNFRAME 0
END_FUNCTION node_api_sent

/* ---------------------------------------------------------------- Events (beacon-api.md, eventstream) */

/*
 * L1: (out x0, answer flags x1) -> x0: the head of an eventstream answer into the ByteList out, its
 * count set; LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL. The writer's registers.
 */
LOCAL_FUNCTION api_sse_head
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
END_FUNCTION api_sse_head

/*
 * L1: (view x0, out x1, topic x2) -> x0: the text of the event of the topic, from the view's event
 * fields, into the ByteList out, its count set; LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL. The
 * writer's registers; x28 the topic.
 */
LOCAL_FUNCTION api_event_text
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
    b.ne    1f
    API_LIT api_ev_t_head
    b       3f
1:  cmp     x28, #API_TOPIC_BLOCK
    b.ne    2f
    API_LIT api_ev_t_block
    b       3f
2:  API_LIT api_ev_t_finalized
3:  API_LIT api_ev_data
    cmp     x28, #API_TOPIC_FINALIZED_CHECKPOINT
    b.eq    5f
    /* block and head: {"slot":…,"block":… */
    API_LIT api_ev_slot
    ldr     x0, [x22, #ApiView_event_slot]
    bl      api_qdec
    API_LIT api_ev_block
    add     x0, x22, #ApiView_event_block
    mov     x1, #32
    bl      api_qhex
    cmp     x28, #API_TOPIC_HEAD
    b.ne    6f
    /* head: state, epoch_transition and the dependent roots */
    API_LIT api_ev_state
    add     x0, x22, #ApiView_event_state
    mov     x1, #32
    bl      api_qhex
    API_LIT api_ev_transition
    ldr     x0, [x22, #ApiView_event_flags]
    and     x0, x0, #1
    bl      api_bool
    API_LIT api_ev_previous
    add     x0, x22, #ApiView_event_previous
    mov     x1, #32
    bl      api_qhex
    API_LIT api_ev_current
    add     x0, x22, #ApiView_event_current
    mov     x1, #32
    bl      api_qhex
    b       6f
    /* finalized_checkpoint: {"block":…,"state":…,"epoch":… */
5:  API_LIT api_ev_block1
    add     x0, x22, #ApiView_event_block
    mov     x1, #32
    bl      api_qhex
    API_LIT api_ev_state
    add     x0, x22, #ApiView_event_state
    mov     x1, #32
    bl      api_qhex
    API_LIT api_k_epoch
    ldr     x0, [x22, #ApiView_event_epoch]
    bl      api_qdec
6:  API_LIT api_u_optimistic
    ldr     x0, [x22, #ApiView_event_flags]
    ubfx    x0, x0, #1, #1
    bl      api_bool
    API_LIT api_ev_end
    cbnz    x27, 9f
    add     x9, x23, #24
    sub     x9, x24, x9
    mov     x10, #24
    stp     x10, x9, [x23, #8]
    mov     x0, #LANTERN_OK
    LEAVE 0
9:  mov     x0, #LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION api_event_text

/* L0: x0 = 1 when a NodeApi entry of eventstream has the topic x0, else 0. Uses x9-x13. */
LOCAL_FUNCTION node_api_subscribed
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
END_FUNCTION node_api_subscribed

/* L0: x0 = the NodeApi entries of eventstream. Uses x9-x12. */
LOCAL_FUNCTION node_api_event_count
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
END_FUNCTION node_api_event_count

/*
 * L1: eventstream of the connection x0 with the route x1 and the answer flags x2 (node.md,
 * NODE_EV_API): a NodeApi entry of the route's topics, and a SEND of the head with last 0, its
 * bytes the entry's sent. Locals: L the entry, L+8 the action.
 */
LOCAL_FUNCTION node_api_subscribe
    ENTER 16
    mov     x21, x0
    mov     x22, x1
    mov     x25, x2
    bl      node_api_new
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
    bl      node_act
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
    bl      api_sse_head
    ldr     x0, [sp, #(L + 8)]
    ldr     x9, [x0, #48]
    ldr     x1, [sp, #L]
    str     x9, [x1, #NodeApi_sent]
    LEAVE 16
END_FUNCTION node_api_subscribe

/*
 * L1: the event text of the ByteList x0, of the topic x1, to each NodeApi entry of eventstream of
 * the topic (node.md, The events): a SEND of it, in one chunk with API_STREAM_CHUNKED, its bytes
 * added to the entry's sent; an entry whose sent would pass NODE_API_CHUNK gets a CLOSE and ends.
 * x21 the text, x22 the topic, x25 the entry, x26 its index, x27 the bytes sent, x28 the action.
 */
LOCAL_FUNCTION node_api_events
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
    bl      node_act
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
    bl      node_act
    ldr     x9, [x25, #NodeApi_connection]
    str     x9, [x0, #16]
    mov     x0, x25
    bl      node_api_end
8:  add     x26, x26, #1
    b       1b
9:  LEAVE 0
END_FUNCTION node_api_events

/*
 * L1: the block event of the NodeBlock entry x0 (node.md, The events), with an entry of the topic:
 * its text in a ByteList at the end of scratch, after the ApiView of its values. x21 the block, x22
 * the view, x26 the ByteList. Locals: L the scratch's size.
 */
LOCAL_FUNCTION node_api_block_event
    ENTER 16
    mov     x21, x0
    mov     x0, #API_TOPIC_BLOCK
    bl      node_api_subscribed
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
    ldr     x9, [x21, #NodeBlock_slot]
    str     x9, [x22, #ApiView_event_slot]
    add     x0, x22, #ApiView_event_block
    add     x1, x21, #NodeBlock_root
    bl      lantern_copy_root
    ldr     x9, [x21, #NodeBlock_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    cset    x9, eq
    lsl     x9, x9, #1
    str     x9, [x22, #ApiView_event_flags]
    mov     x0, x22
    mov     x1, x26
    mov     x2, #API_TOPIC_BLOCK
    bl      api_event_text
    cbnz    x0, 8f
    mov     x0, x26
    mov     x1, #API_TOPIC_BLOCK
    bl      node_api_events
8:  ldr     x9, [sp, #L]
    str     x9, [x23]
9:  LEAVE 16
END_FUNCTION node_api_block_event

/*
 * L1: the head and finalized_checkpoint events at a quiet point (node.md, The events): with no
 * block vote queued, a head other than event_head, then a finalized epoch above event_epoch; each
 * a NODE_WORK_API_EVENT when an entry has its topic. x21 the block, x22 the values.
 */
.if API_TOPIC_HEAD
.error "node_api_head_events: the arg of a head event takes API_TOPIC_HEAD as 0"
.endif
LOCAL_FUNCTION node_api_head_events
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
1:  bl      node_find_block
    cmn     x0, #1
    b.eq    5f
    mov     x21, x1
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
    STQ     x9, x19, Node_event_slot
    ADDQ    x0, x19, Node_event_head
    add     x1, x21, #NodeBlock_root
    bl      lantern_copy_root
    ldr     x0, [x21, #NodeBlock_state_id]  /* the pool's checks at the new head */
    bl      node_pool_checks
    mov     x0, #API_TOPIC_HEAD
    bl      node_api_subscribed
    cbz     x0, 5f
    ldr     x1, [x21, #NodeBlock_state_id]
    cbz     x1, 5f
    mov     x0, #NODE_WORK_API_EVENT
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    lsl     x5, x22, #8                     /* API_TOPIC_HEAD is 0 */
    bl      node_work
5:  ldr     x9, [x20, #Store_finalized_checkpoint]
    LDQ     x10, x19, Node_event_epoch
    cmp     x9, x10
    b.ls    9f
    STQ     x9, x19, Node_event_epoch
    mov     x0, #API_TOPIC_FINALIZED_CHECKPOINT
    bl      node_api_subscribed
    cbz     x0, 9f
    add     x0, x20, #(Store_finalized_checkpoint + 8)
    bl      node_find_block
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
    bl      node_work
9:  LEAVE 0
END_FUNCTION node_api_head_events

/* L1: NODE_EV_WORK_DONE x0 of a NODE_WORK_API_EVENT: LANTERN_VALID, its text to the entries of its topic. */
LOCAL_FUNCTION node_api_event_done
    FRAME 0
    ldr     x9, [x0, #NodeEvent_result]
    cbnz    x9, 9f
    ldr     x1, [x0, #NodeAction_arg]
    and     x1, x1, #255
    add     x0, x0, #NodeEvent_chunk
    bl      node_api_events
9:  UNFRAME 0
END_FUNCTION node_api_event_done

/* L1: NODE_EV_API_CLOSED of the connection x0: its stream ends, or with a chunk queued takes API_STREAM_GONE. */
LOCAL_FUNCTION node_api_closed
    FRAME 0
    bl      node_api_find
    cmn     x0, #1
    b.eq    9f
    ldr     x9, [x1, #NodeApi_flags]
    tbz     x9, #4, 1f
    orr     x9, x9, #API_STREAM_GONE
    str     x9, [x1, #NodeApi_flags]
    b       9f
1:  mov     x0, x1
    bl      node_api_end
9:  UNFRAME 0
END_FUNCTION node_api_closed

/*
 * L2: (connection x0, route x1, flags x2, view x3) -> x0: a stream of getBlockV2, getStateV2 or a validator operation of
 * the lookup in the view (node.md, NODE_EV_API): 0 once it started, else the status of the error to
 * answer. flags: API_STREAM_CLOSE and API_STREAM_HTTP10. x19 the node, x24 the actions. x21 the
 * data, x25 the route, x26 the view, x27 the connection, x28 the flags. Locals: L the entry's
 * index, L+8 the entry.
 */
LOCAL_FUNCTION node_api_stream
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
    bl      node_api_committees_check
    str     x0, [sp, #(L + 24)]
    cmn     x0, #1
    b.ne    6f
    b       331f
34: sub     x10, x9, #API_OP_GET_PENDING_CONSOLIDATIONS /* the pending lists: 400 for a state before electra, and no stream */
    cmp     x10, #2
    b.hi    6f
    ldr     x0, [x26, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      node_fork
    cmp     x0, #FORK_ELECTRA
    b.hs    6f
331: ldr    x9, [x26, #ApiView_look_copy]
    cbz     x9, 33f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x26, #ApiView_look_state]
    mov     x2, #0
    bl      node_ids
33: mov     x0, #400
    LEAVE 32
4:  ldr     x21, [x26, #ApiView_look_data]  /* getBlockV2: the block's bytes */
    cbz     x21, 80f
    b       6f
5:  bl      node_new_id                     /* getStateV2: the state's SSZ bytes, as a new id the stream owns */
    mov     x21, x0
    mov     x0, #NODE_ACT_STATE_BYTES
    mov     x1, #NODE_ACT_STATE_BYTES_SIZE
    bl      node_act
    ldr     x9, [x26, #ApiView_look_state]
    stp     x9, x21, [x0, #16]
    orr     x28, x28, #API_STREAM_OWN
    ldr     x9, [x26, #ApiView_look_copy]   /* a copy goes after its bytes */
    cbz     x9, 6f
    mov     x0, #NODE_ACT_STATE_FREE
    ldr     x1, [x26, #ApiView_look_state]
    mov     x2, #0
    bl      node_ids
6:  bl      node_api_new                    /* the entry */
    stp     x0, x1, [sp, #L]
    mov     x0, x1
    mov     x1, #NodeApi__mem
    bl      lantern_zero
    ldr     x0, [x26, #ApiView_head_slot]
    ldr     x1, [sp, #(L + 8)]
    str     x0, [x1, #NodeApi_slot]
    add     x1, x19, #Node_config
    bl      node_fork
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
    bl      node_api_committees_cursor
7:  ldp     x0, x1, [sp, #L]
    bl      node_api_chunk_work
    mov     x0, #0
    LEAVE 32
80: mov     x0, #404
    LEAVE 32
END_FUNCTION node_api_stream

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_CHUNK (node.md, lantern_node_step). x19 the
 * node, x24 the actions. x21 the event, x22 the entry, x23 the action, x25 the flags.
 */
LOCAL_FUNCTION node_api_chunk_done
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
    bl      node_headers_next
    b       3f
2:  cmp     x9, #API_OP_GET_BLOB_SIDECARS   /* a sidecar stream: its sidecar from member + 1 on */
    b.eq    4f
    cmp     x9, #API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    b.ne    5f
4:  ldr     x1, [x22, #NodeApi_member]
    add     x1, x1, #1
    bl      node_sidecar_next
    b       3f
5:  bl      node_api_pool_advance
3:  ldr     x25, [x22, #NodeApi_flags]
1:  tbz     x25, #15, 11f                   /* API_STREAM_FOLD: no send, and the next chunk at once */
    tbnz    x25, #10, 11f                   /* the error that ends it goes */
    ldr     x9, [x22, #NodeApi_data]
    cbnz    x9, 12f                         /* a fold */
    ldr     x9, [x21, #(NodeEvent_api_bytes + 16)]
    cbnz    x9, 14f                         /* the Attestation's bytes */
    ldr     x9, [x22, #(NodeApi_cursor + 32)]   /* the fold's end: optimistic for a NOT_VALIDATED block */
    cbz     x9, 12f
    add     x0, x22, #(NodeApi_cursor + 48 + 16)
    bl      node_store_find
    cmn     x0, #1
    b.eq    12f
    ldr     x9, [x1, #BlockNode_payload_status]
    cmp     x9, #PAYLOAD_STATUS_NOT_VALIDATED
    b.ne    12f
    orr     x25, x25, #API_STREAM_OPTIMISTIC
    str     x25, [x22, #NodeApi_flags]
    b       12f
14: add     x0, x21, #NodeEvent_api_bytes   /* they become the stream's own data; the answer from sent 0 */
    bl      node_put
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
    bl      node_api_chunk_work
    b       99f
11: ldr     x9, [x21, #(NodeEvent_api_bytes + 16)]  /* the chunk in a SEND */
    add     x1, x9, #(56 + 7)
    and     x1, x1, #~7
    mov     x0, #NODE_ACT_API_SEND
    bl      node_act
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
51: bl      node_api_send
    b       90f
60: mov     x0, #NODE_ACT_API_CLOSE
    mov     x1, #NODE_ACT_API_CLOSE_SIZE
    bl      node_act
    ldr     x9, [x22, #NodeApi_connection]
    str     x9, [x0, #16]
90: mov     x0, x22
    bl      node_api_end
99: LEAVE 0
END_FUNCTION node_api_chunk_done

/* L1: the name of the fork x0 joins the response. */
LOCAL_FUNCTION api_fork_name
    FRAME 0
    ADDRESS x9, api_forks
    add     x9, x9, x0, lsl #4
    ldrb    w1, [x9], #1
    mov     x0, x9
    bl      api_put
    UNFRAME 0
END_FUNCTION api_fork_name

/*
 * L1: the head of a streamed answer (beacon-api.md, Common rules) for the flags at
 * NodeEvent_api + 8 of the event x23 and the fork of the entry x22: with Content-Length x0, or
 * for x0 = 2^64 - 1 Transfer-Encoding: chunked when API_STREAM_CHUNKED is set, else neither.
 * Locals: x0.
 */
LOCAL_FUNCTION api_stream_head
    FRAME 16
    str     x0, [sp, #16]
    API_LIT api_ok
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #2, 1f
    API_LIT api_octet
    b       2f
1:  API_LIT api_type
2:  ldr     x9, [x22, #NodeApi_op]          /* Eth-Consensus-Version: of getBlockV2 and getStateV2 */
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
    bl      api_fork_name
    API_LIT api_crlf
22: ldr     x0, [sp, #16]
    cmn     x0, #1
    b.eq    3f
    API_LIT api_length
    ldr     x0, [sp, #16]
    bl      api_dec
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
END_FUNCTION api_stream_head

/* L0: the 4 lower case hex digits of x0 at x1. Uses x9, x10. */
LOCAL_FUNCTION api_hex4
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
END_FUNCTION api_hex4

/*
 * L1: the JSON of the entry x22's SSZ bytes x21 from the cursor at NodeEvent_api + 16 of the event
 * x23, at the writer's cursor x24 up to x26 less a byte, through the event's ByteList at
 * NodeEvent_api_bytes whose bytes start at x28; then } once it is whole. x0 = 1 when whole, 0
 * when more is to come, 2 for bytes that are no encoding.
 */
LOCAL_FUNCTION api_stream_json
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
4:  bl      api_pool_json
    UNFRAME 0
3:  cmp     x9, #API_OP_GET_BLOCK_HEADERS
    b.ne    32f
    bl      api_headers_json
    UNFRAME 0
32: cmp     x9, #API_OP_GET_BLOB_SIDECARS
    b.eq    33f
    cmp     x9, #API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    b.ne    34f
33: bl      api_sidecar_body
    UNFRAME 0
34: sub     x10, x9, #API_OP_GET_PENDING_CONSOLIDATIONS /* the pending streams: their items */
    cmp     x10, #2
    b.hi    31f
    bl      api_pending_json
    UNFRAME 0
31: cmp     x9, #API_OP_GET_BLOCK_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_BLOCK_ATTESTATIONS_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_BLINDED_BLOCK
    b.eq    1f
    cmp     x9, #API_OP_GET_STATE_V2
    b.eq    1f
    cmp     x9, #API_OP_GET_EPOCH_COMMITTEES
    b.eq    2f
    bl      api_validators_json
    UNFRAME 0
2:  bl      api_committees_json
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
    API_LIT api_end1
    mov     x0, #1
    UNFRAME 0
7:  mov     x0, #2
    UNFRAME 0
8:  mov     x0, #0
    UNFRAME 0
END_FUNCTION api_stream_json

/*
 * (node, work, data, scratch, event, room, state_a) -> status: a NODE_WORK_API_CHUNK of
 * lantern_node_run (node.md): the next chunk of the NodeApi entry at the work's arg, from the SSZ
 * bytes in data, or for a validator stream from state_a and the ids in data, at NodeEvent_api of
 * the event, whose buffer has room bytes. x19 the node, x20 state_a, x21 data, x22 the entry, x23
 * the event; the writer's x24-x27 (api_put); x28 where the chunk's bytes start. Locals: L the end
 * of the chunk's room, L+8 the SSZ bytes, L+16 their count, L+24 the body's start, L+32 the head's
 * bytes, L+40 1 for a validator stream, L+48 the scratch.
 */
LOCAL_FUNCTION node_api_chunk_run
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
    mov     x9, #7                          /* getAggregatedAttestationV2 (7): its fold, then its answer */
    cmp     x10, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.eq    2f
    mov     x9, #6                          /* a sidecar stream (6): data 0 at its end */
    cmp     x10, #API_OP_GET_BLOB_SIDECARS
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
241: sub    x10, x9, #API_OP_GET_STATE_VALIDATORS   /* a validator stream (1) or getEpochCommittees (2): a state */
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
    ldr     x11, [x22, #NodeApi_op]         /* their slot: a state's at byte 40, a block's at 100 */
    cmp     x11, #API_OP_GET_STATE_V2
    mov     x11, #40
    mov     x12, #100
    csel    x11, x11, x12, eq
    add     x12, x11, #8
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
    bl      node_api_validators_prep
    cbnz    x0, 97f
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
    bl      node_pool_attestation
    cmp     x0, #1
    b.eq    96f
    b.hi    97f
    mov     x21, x1
    b       6f
69: ldr     x9, [x23, #(NodeEvent_api + 8)] /* getAggregatedAttestationV2 */
    tbz     x9, #15, 693f
    cbz     x21, 691f
    ldr     x0, [sp, #(L + 48)]             /* a fold of the entry: no bytes */
    bl      node_api_fold
    cmp     x0, #1
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
    bl      node_api_aggregate
    cbnz    x0, 96f
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
    bl      node_fork
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
    bl      node_fork
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
63: bl      node_api_committees_prep
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
    bl      api_respond
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
    bl      api_stream_head
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
    bl      api_stream_head
61: bl      api_validators_json
    ldr     x11, [x23, #(NodeEvent_api + 8)]
    orr     x11, x11, #API_STREAM_STARTED
    cbz     x0, 62f
    orr     x11, x11, #API_STREAM_DONE
62: str     x11, [x23, #(NodeEvent_api + 8)]
    b       80f
30: tbnz    x9, #6, 40f                     /* JSON, the first chunk: the body after room for the head */
    add     x24, x28, #API_HEAD_ROOM
    str     x24, [sp, #(L + 24)]
    ldr     x9, [sp, #L]
    sub     x26, x9, #7                     /* room for CRLF and the last chunk */
    ldr     x9, [sp, #(L + 40)]
    cbz     x9, 35f
    cmp     x9, #6                          /* a sidecar stream: as JSON the pending streams' head; as SSZ none */
    b.ne    393f
    ldr     x10, [x23, #(NodeEvent_api + 8)]
    tbnz    x10, #2, 36f
    b       392f
393: cmp    x9, #4
    b.eq    392f
    cmp     x9, #7                          /* getAggregatedAttestationV2: {"version":"<fork>","data": */
    b.ne    394f
    API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      api_fork_name
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
    bl      api_fork_name
    API_LIT api_p_version
    b       36f
38: API_LIT api_p_data
    b       36f
    /* the validator streams: {"execution_optimistic":…,"finalized":…,"data":[ */
37: API_LIT api_v_open
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #8, #1
    bl      api_bool
    API_LIT api_x_finalized
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #9, #1
    bl      api_bool
    API_LIT api_v_list
    b       36f
    /* the pending streams: {"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[ */
392: API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      api_fork_name
    API_LIT api_j_optimistic
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #8, #1
    bl      api_bool
    API_LIT api_x_finalized
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #9, #1
    bl      api_bool
    API_LIT api_v_list
    b       36f
    /* {"version":"<fork>","execution_optimistic":…,"finalized":…,"data": */
35: API_LIT api_j_version
    ldr     x0, [x22, #NodeApi_fork]
    bl      api_fork_name
    API_LIT api_j_optimistic
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #8, #1
    bl      api_bool
    API_LIT api_x_finalized
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    ubfx    x0, x9, #9, #1
    bl      api_bool
    API_LIT api_j_data
36: bl      api_stream_json
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
    bl      api_stream_head
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
    bl      api_stream_head
    ldr     x9, [x23, #(NodeEvent_api + 8)]
    tbz     x9, #7, 34f
    ldr     x0, [sp, #(L + 16)]             /* chunked: the size line, then CRLF after the bytes */
    mov     x1, x24
    bl      api_hex4
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
    bl      api_stream_json
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
    bl      api_hex4
    mov     w9, #0x0a0d
    strh    w9, [x28, #4]
    ldr     x26, [sp, #L]
    API_LIT api_crlf
    ldr     x9, [sp, #(L + 32)]
    cbz     x9, 80f
    API_LIT api_last_chunk
    b       44f
45: bl      api_stream_json                 /* HTTP/1.0: the bytes alone */
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
END_FUNCTION node_api_chunk_run

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
LOCAL_FUNCTION node_pool_attestation
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
END_FUNCTION node_pool_attestation

/* L1: x0 = the new id of a NODE_ACT_BYTES_PUT of the 8 bytes at x0. Locals: a ByteList head whose offset reaches them. */
LOCAL_FUNCTION node_api_put8
    FRAME 32
    add     x9, sp, #16
    sub     x10, x0, x9
    mov     x11, #8
    stp     x11, x10, [x9]
    str     x11, [x9, #16]
    mov     x0, x9
    bl      node_put
    UNFRAME 32
END_FUNCTION node_api_put8

/* L0: x0 = the gossip topic of the pool POST x0, or 0. Uses x9. */
LOCAL_FUNCTION node_submit_topic
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
    mov     x0, #0
9:  ret
END_FUNCTION node_submit_topic

/* L0: x0 = the lantern_node_json kind of the pool operation of the gossip topic x0. Uses x9. */
LOCAL_FUNCTION node_pool_kind
    UNWIND_END_PROLOGUE
    cmp     x0, #GOSSIP_BLS_TO_EXECUTION_CHANGE
    mov     x9, #NODE_JSON_BLS_CHANGE
    sub     x0, x0, #(GOSSIP_VOLUNTARY_EXIT - NODE_JSON_EXIT)
    csel    x0, x9, x0, eq
    ret
END_FUNCTION node_pool_kind
.if GOSSIP_PROPOSER_SLASHING - GOSSIP_VOLUNTARY_EXIT != NODE_JSON_PROPOSER_SLASHING - NODE_JSON_EXIT || GOSSIP_ATTESTER_SLASHING - GOSSIP_VOLUNTARY_EXIT != NODE_JSON_ATTESTER_SLASHING - NODE_JSON_EXIT
.error "node_pool_kind: the kinds follow the topics"
.endif

/*
 * L0: x0 = the index of the first pool entry from the index x0 that the pool stream x1 answers
 * (node.md, NODE_EV_API): of its topic; for getPoolAttesterSlashingsV2 and getPoolAttestationsV2
 * of the type of its fork, and for getPoolAttestationsV2 of its filters; else 2^64 - 1. x1 = the
 * entry. Uses x2, x9-x14.
 */
LOCAL_FUNCTION node_pool_next
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
4:  mov     x1, x10
    ret
8:  mov     x0, #-1
    ret
END_FUNCTION node_pool_next

/*
 * L1: (connection x0, route x1, flags x2, view x3): a stream of a pool GET (node.md, NODE_EV_API):
 * fork the store's, the filters of getPoolAttestationsV2; slot the first entry it answers, data
 * its bytes, sent its fork, member its member; data 0 with none. flags: API_STREAM_CLOSE and
 * API_STREAM_HTTP10. Locals: the connection, the route, the flags, the fork, the entry's index
 * and address.
 */
LOCAL_FUNCTION node_api_pool_stream
    FRAME 48
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    ldr     x9, [x3, #ApiView_fork]
    str     x9, [sp, #40]
    bl      node_api_new
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
    mov     x0, #0
    bl      node_pool_next
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
    bl      node_api_chunk_work
    mov     x0, #0
    UNFRAME 48
1:  ldr     x10, [x9, #NodeApi_op]          /* none: getAggregatedAttestationV2 404, and no stream */
    cmp     x10, #API_OP_GET_AGGREGATED_ATTESTATION_V2
    b.ne    3b
    mov     x0, x9
    bl      node_api_end
    mov     x0, #404
    UNFRAME 48
END_FUNCTION node_api_pool_stream

/*
 * L1: the item of the getBlockHeaders stream x0 at or after the position x1 (node.md, NODE_EV_API, an
 * item of getBlockHeaders): position 0 the Db's block of the query, i + 1 the NodeBlock at index i.
 * Its slot (the position), data, state, member (1 on the chain, + 2 optimistic, + 4 finalized) and
 * its root at byte 0 of cursor; x0 = 1, or 0 with data and state 0 for none. x21 the entry, x22 the
 * position, x23 the slot of the query or 2^64 - 1, x24 the address of its parent_root or 0, x25 a
 * NodeBlock index, x26 a slot or an entry, x27 the member. Locals: L a slot.
 */
LOCAL_FUNCTION node_headers_next
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
    bl      node_find_block
    cmn     x0, #1
    b.eq    11f
    ldr     x9, [x1, #NodeBlock_status]
    cmp     x9, #NODE_BLOCK_IMPORTED
    b.ne    11f
    mov     x25, x1
    mov     x0, x1
    bl      node_api_on_chain
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
    bl      node_api_below
    cmn     x0, #1
    b.ne    19f
    mov     x0, x26
    bl      node_db_slot
    cbz     x0, 12b
    cmn     x23, #1
    b.eq    16f
    cmp     x26, x23
    b.ne    19f
    b       16f
15: mov     x26, x23                        /* slot alone: the Db's block of slot, below the chain the node keeps */
    mov     x0, x26
    bl      node_api_below
    cmn     x0, #1
    b.ne    19f
    mov     x0, x26
    bl      node_db_slot
    cbz     x0, 19f
16: mov     x1, x0                          /* the Db's block of slot x26: its DbSlot x0, the root at 0 */
    add     x0, x21, #NodeApi_cursor
    bl      lantern_copy_root
    mov     x0, x26
    bl      node_db_block
    str     x0, [x21, #NodeApi_data]
    str     xzr, [x21, #NodeApi_state]
    str     xzr, [x21, #NodeApi_slot]
    mov     x0, x26
    bl      node_api_final_block
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
    bl      node_api_db_ref
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
    bl      node_api_on_chain
    orr     x27, x27, x0
    cbz     x0, 26f
    ldr     x0, [x26, #NodeBlock_slot]
    bl      node_api_final_block
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
END_FUNCTION node_headers_next

/*
 * L1: (connection x0, route x1, flags x2): the getBlockHeaders stream of the route's query (node.md,
 * NODE_EV_API): filter_slot its slot, the head's slot with neither slot nor parent_root, else
 * 2^64 - 1; its parent_root at byte 32 of cursor and 1 at byte 64; API_STREAM_OPTIMISTIC and
 * API_STREAM_FINALIZED of all its items; then its first item and a NODE_WORK_API_CHUNK. Locals: the
 * connection, the route, the flags, the entry's index and address, the position.
 */
LOCAL_FUNCTION node_api_headers_stream
    FRAME 48
    stp     x0, x1, [sp, #16]
    str     x2, [sp, #32]
    bl      node_api_new
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
    bl      node_find_block
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
    bl      node_headers_next
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
    bl      node_headers_next
    ldp     x0, x1, [sp, #40]
    bl      node_api_chunk_work
    UNFRAME 48
END_FUNCTION node_api_headers_stream

/*
 * L1: the sidecar of the sidecar stream x0 from the index x1 on (node.md, NODE_EV_API, a sidecar of a
 * sidecar stream): member, data, sent 0 and cursor zero; x0 = 1, or 0 with data 0 for none. x21 the
 * entry, x22 the index.
 */
LOCAL_FUNCTION node_sidecar_next
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
    bl      node_blob_held
    cbz     x0, 3f
    ldr     x0, [x0, #NodeBlob_data_id]
    b       5f
3:  ldr     x9, [x19, #Node_flags]
    tst     x9, #NODE_FLAG_DB
    b.eq    7f
    ldr     x0, [x21, #NodeApi_slot]
    mov     x1, x22
    bl      node_db_sidecar
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
END_FUNCTION node_sidecar_next

/*
 * L1: (connection x0, route x1, flags x2, view x3) -> x0: the sidecar stream of the block of the
 * view (node.md, NODE_EV_API): 0, or 400 for a block whose slot's fork is not the operation's.
 * Locals: the connection, the route, the flags, the view, the fork, the entry's index and address.
 */
LOCAL_FUNCTION node_api_sidecar_stream
    FRAME 64
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    ldr     x0, [x3, #ApiView_head_slot]
    add     x1, x19, #Node_config
    bl      node_fork
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
2:  bl      node_api_new
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
    bl      node_sidecar_next
    ldp     x0, x1, [sp, #56]
    bl      node_api_chunk_work
    mov     x0, #0
    UNFRAME 64
8:  mov     x0, #400
    UNFRAME 64
END_FUNCTION node_api_sidecar_stream

/*
 * L1: a sidecar stream's body, as api_stream_json (node.md, NODE_WORK_API_CHUNK, the sidecar
 * streams): with the bytes x21, as JSON the JSON of the sidecar from the cursor at NodeEvent_api + 16
 * by lantern_node_json of the entry's fork and the kind of the operation, after , when
 * API_STREAM_ITEMS is set and the cursor is at its start; as SSZ its bytes from sent (NodeEvent_api),
 * as many as fit; at the sidecar's end API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With
 * x21 = 0: ]} as JSON, nothing as SSZ. x0 = 1 when the answer is whole, 0 when more is to come, 2
 * for bytes that are no encoding.
 */
LOCAL_FUNCTION api_sidecar_body
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
END_FUNCTION api_sidecar_body

/*
 * L1: the pool stream of the NodeApi entry x0 goes to its next entry after slot (node.md,
 * NODE_WORK_API_CHUNK): its slot, data, sent and member, a zero cursor; data 0 with none. Bytes it owned
 * get a NODE_ACT_BYTES_FREE, and API_STREAM_OWN clears. Locals: the entry, the old data, the flags.
 */
LOCAL_FUNCTION node_api_pool_advance
    FRAME 32
    str     x0, [sp, #16]
    ldr     x9, [x0, #NodeApi_data]
    ldr     x10, [x0, #NodeApi_flags]
    stp     x9, x10, [sp, #24]
    ldr     x9, [x0, #NodeApi_slot]
    mov     x1, x0
    add     x0, x9, #1
    bl      node_pool_next
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
    bl      node_ids
9:  UNFRAME 32
END_FUNCTION node_api_pool_advance

/*
 * L1: a pool stream's JSON, as api_stream_json: with the bytes x21, the JSON of the pool entry
 * from the cursor at NodeEvent_api + 16, by lantern_node_json of the fork in sent (NodeEvent_api)
 * and the kind of the GET, after , when API_STREAM_ITEMS is set and the cursor is at its start;
 * once whole, API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With x21 = 0: ]}. x0 = 1
 * when the answer is whole, 0 when more is to come, 2 for bytes that are no encoding.
 */
LOCAL_FUNCTION api_pool_json
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
END_FUNCTION api_pool_json

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
LOCAL_FUNCTION node_api_fold
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
END_FUNCTION node_api_fold
.if MAX_VALIDATORS_PER_COMMITTEE > 2048 || 48 + 128 + 96 + 2048 / 8 > JSON_CURSOR_SIZE
.error "node_api_fold: the aggregate's bits fit the cursor from byte 272"
.endif

/*
 * L1: (out x0) -> x0: the aggregate in the cursor at NodeEvent_api + 16 of the event x23 as the
 * SSZ bytes of the Attestation of the fork of the entry x22 at out, x1 their count (node.md,
 * getAggregatedAttestationV2): aggregation_bits of the cursor's length with its bits, data,
 * signature; from electra committee_bits with the bit of filter_index. x0 = 0; 1 for a committee
 * index not below MAX_COMMITTEES_PER_SLOT. Locals: out, the fixed part's size, the count.
 */
LOCAL_FUNCTION node_api_aggregate
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
END_FUNCTION node_api_aggregate
.if NODE_API_FIRST_ROOM < API_HEAD_ROOM + NODE_POOL_ATTESTATION_FIXED + MAX_VALIDATORS_PER_COMMITTEE / 8 + 1
.error "node_api_aggregate: an Attestation of one committee fits the first chunk"
.endif

/*
 * L1: the failures of the event x22 of a NODE_WORK_API_SUBMIT: {"index":<i>,"message":"REJECT"}
 * for each record of LANTERN_GOSSIP_REJECT, with , between, then ]}. Locals: the record, its
 * index, the failures written.
 */
LOCAL_FUNCTION api_failures
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
    bl      api_dec
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
END_FUNCTION api_failures

/*
 * L1: (connection x0, route x1, flags x2, request x3, view x4) -> x0: a pool POST (node.md,
 * NODE_EV_API): a NODE_ACT_BYTES_PUT of the body and a NODE_WORK_API_SUBMIT; 0 once queued, else
 * the status of the error to answer. Locals: the connection, the flags, the route, the view, the
 * head's post-state, a ByteList head whose offset reaches the body.
 */
LOCAL_FUNCTION node_api_submit
    FRAME 80
    stp     x0, x2, [sp, #16]
    stp     x1, x4, [sp, #32]
    ldr     x9, [x1, #ApiRoute_body]        /* an SSZ body: an answer flag */
    cmp     x9, #API_TYPE_SSZ
    b.ne    11f
    orr     x2, x2, #API_ANSWER_SSZ
    str     x2, [sp, #24]
11: ldr     x9, [x1, #ApiRoute_op]          /* the AttesterSlashing or attestation type of the store's fork */
    mov     x10, #API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    cmp     x9, #API_OP_SUBMIT_POOL_ATTESTER_SLASHINGS_V2
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
    bl      node_find_block
    cmn     x0, #1
    b.eq    81f
    ldr     x9, [x1, #NodeBlock_state_id]
    cbz     x9, 81f
    str     x9, [sp, #48]
    add     x0, sp, #64
    bl      node_put
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
    bl      node_work
    mov     x0, #0
    UNFRAME 80
80: mov     x0, #400
    UNFRAME 80
81: mov     x0, #500
    UNFRAME 80
END_FUNCTION node_api_submit

/*
 * L0: x0 = 0 when the NODE_EV_WORK_DONE x0 of x1 bytes of a valid NODE_WORK_API_SUBMIT holds its
 * records inside it (node.md): a ByteList at NodeEvent_chunk of offset 24, and NodeEvent_index
 * records in its bytes, each a code and a ByteList of offset 24 whose size is a multiple of 8;
 * else 1. Uses x9-x15.
 */
LOCAL_FUNCTION node_submit_check
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
END_FUNCTION node_submit_check

/*
 * L2: the NODE_EV_WORK_DONE x0 of a NODE_WORK_API_SUBMIT (node.md, lantern_node_step): the body's
 * bytes go; each valid operation joins the pool, goes out on its topic with NODE_FLAG_SUBSCRIBED,
 * and an attester slashing to fork choice; then the answer to the connection. x19 the node, x20
 * the store, x23 the scratch, x24 the actions. x21 the event, x22 the record, x25 the failures, x26
 * the topic, x27 the new id, x28 the answer's flags. Locals: L 1 when the pool keeps it, L+8 the
 * records left.
 */
LOCAL_FUNCTION node_api_submit_done
    ENTER 16
    mov     x21, x0
    mov     x0, #NODE_ACT_BYTES_FREE
    ldr     x1, [x21, #NodeAction_data]
    mov     x2, #0
    bl      node_ids
    ldr     x9, [x21, #NodeAction_arg]      /* the answer's flags: API_STREAM_CLOSE (1), API_STREAM_HTTP10 (2) */
    ubfx    x10, x9, #8, #8
    mov     x28, #API_R_CLOSE
    tbnz    x10, #0, 1f
    tst     x10, #API_STREAM_HTTP10
    mov     x11, #API_R_KEEP
    csel    x28, x11, xzr, ne
1:  and     x0, x9, #255
    bl      node_submit_topic
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
    add     x0, x22, #16                    /* valid: its bytes to a new id, kept by the pool when it has room */
    bl      node_put
    mov     x27, x0
    mov     x4, #0                          /* an attestation: its slot and committee index, its member */
    mov     x5, #0
    ldr     x6, [x22, #8]
    lsr     x6, x6, #32
    cmp     x26, #GOSSIP_BEACON_ATTESTATION
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
    bl      node_pool_add
    str     x0, [sp, #L]
    ldr     x9, [x19, #Node_flags]
    tbz     x9, #2, 3f                      /* NODE_FLAG_SUBSCRIBED: out on its topic, an attestation on its subnet */
    mov     x0, x26
    add     x1, x22, #16
    ldr     w2, [x22, #8]
    bl      node_publish
3:  cmp     x26, #GOSSIP_ATTESTER_SLASHING  /* an attester slashing: on_attester_slashing with the justified root's state */
    b.ne    4f
    add     x0, x20, #(Store_justified_checkpoint + 8)
    bl      node_find_block
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
    bl      node_work
    b       6f
4:  ldr     x9, [sp, #L]                    /* bytes no entry keeps and no work reads go */
    cbnz    x9, 6f
    mov     x0, #NODE_ACT_BYTES_FREE
    mov     x1, x27
    mov     x2, #0
    bl      node_ids
6:  ldr     x9, [x22, #16]
    add     x22, x22, #16
    add     x22, x22, x9
    ldr     x9, [sp, #(L + 8)]
    sub     x9, x9, #1
    str     x9, [sp, #(L + 8)]
    b       2b
70: ldr     x0, [x21, #NodeAction_target]   /* the answer: 200, or 400 with the failures */
    cbz     x25, 71f
    ldr     x9, [x21, #NodeAction_arg]      /* a list: the failures */
    and     x9, x9, #255
    mov     x10, #API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    cmp     x9, #API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    ccmp    x9, x10, #4, ne
    b.ne    80f
    mov     x1, x21
    mov     x2, #400
    mov     x3, #API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    mov     x4, x28
    bl      node_api_send
    LEAVE 16
71: mov     x1, #0
    mov     x2, #200
    mov     x3, #0
    mov     x4, x28
    bl      node_api_send
    LEAVE 16
80: ldr     x0, [x21, #NodeAction_target]
    mov     x1, #0
    mov     x2, #400
    mov     x3, #API_BODY_ERROR
    mov     x4, x28
    bl      node_api_send
    LEAVE 16
END_FUNCTION node_api_submit_done

/*
 * L2: the publish of the SSZ bytes of the ByteList x1 on the gossip topic x0 of the subnet x2 (node.md, the
 * publish): a LIBP2P_EVENT_PUBLISH at the end of p2p_out; none when it does not fit. Its data
 * compresses in place, its ByteList head in the 24 bytes before the data. x21 the bytes, x22 the
 * event, x25 the topic's length, x26 the data's offset in the event, x27 the event's room.
 * Locals: L a GossipTopic, L+24 the topic's ByteList (24 + 128), L+176 a size, L+184 the
 * message-id (24).
 */
LOCAL_FUNCTION node_publish
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
    bl      node_out
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
    bl      node_store_slot
    add     x1, x19, #Node_config
    bl      node_fork
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
END_FUNCTION node_publish

/*
 * L1: (text x0 to x1, kind x2, fork x3, fault x4) -> x0: the JSON text decoded by lantern_node_json_decode
 * into the record at x27 of node_api_submit_run (x24 its scratch, x26 the event's end): code and
 * subnet 0, then a ByteList of the SSZ bytes, its size to a multiple of 8; x27 then the next record. x0 = 0,
 * 1 for a text that is no such value, 2 for too little room. Locals: a ByteList head of the text.
 */
LOCAL_FUNCTION node_submit_decode
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
END_FUNCTION node_submit_decode

/*
 * L1: (bytes x0, length x1) -> x0: the bytes as the record at x27 of node_api_submit_run (x26 the
 * event's end): code and subnet 0, then a ByteList of them, its size to a multiple of 8; x27 then
 * the next record. x0 = 0, or 2 for too little room. Locals: the record's size, the length.
 */
LOCAL_FUNCTION node_submit_copy
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
END_FUNCTION node_submit_copy

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
LOCAL_FUNCTION node_api_submit_run
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
    cset    x9, eq
    str     x9, [sp, #(L + 40)]
    bl      node_submit_topic
    cbz     x0, 98f
    str     x0, [sp, #(L + 16)]
    cmp     x0, #GOSSIP_BEACON_ATTESTATION  /* an attestation: of the fork's type */
    b.ne    12f
    ldr     x9, [sp, #(L + 24)]
    cmp     x9, #FORK_ELECTRA
    mov     x0, #NODE_JSON_ATTESTATION
    mov     x10, #NODE_JSON_SINGLE_ATTESTATION
    csel    x0, x10, x0, hs
    b       13f
12: bl      node_pool_kind
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
    bl      node_submit_decode
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
    bl      submit_ws
    cmp     x0, x28
    b.hs    90f
    ldrb    w9, [x0]
    cmp     w9, #'['
    b.ne    90f
    add     x0, x0, #1
    bl      submit_ws
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
    bl      node_submit_decode
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
28: bl      submit_ws                       /* then only white space */
    cmp     x0, x28
    b.ne    90f
    b       30f
40: sub     x10, x28, x0                    /* SSZ: from electra items of 240 bytes */
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
    bl      node_submit_copy
    cbnz    x0, 97f
    ldp     x0, x12, [sp, #(L + 48)]
    add     x0, x0, #240
    sub     x12, x12, #1
    stp     x0, x12, [sp, #(L + 48)]
    ldr     x9, [sp, #(L + 32)]
    add     x9, x9, #1
    str     x9, [sp, #(L + 32)]
    b       41b
42: cbz     x10, 30f                        /* before electra: the items of the 4-byte offsets */
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
    bl      node_submit_copy
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
    ldr     x9, [sp, #L]                    /* seen has a key free for each operation */
    ldp     x10, x11, [x9, #Seen_keys]
    ldr     x12, [x9, #Seen_bits]
    sub     x12, x12, x10
    lsr     x12, x12, #5
    sub     x12, x12, x11
    ldr     x10, [sp, #(L + 32)]
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
39: mov     x0, #LANTERN_OK
    LEAVE 320
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
END_FUNCTION node_api_submit_run

/* L0: x0 = x0 past the JSON white space (space, tab, LF, CR) before x28. Uses x9. */
LOCAL_FUNCTION submit_ws
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
END_FUNCTION submit_ws

    RODATA
    .p2align 3
node_api_rooms:                             /* the room of each text of an ApiIdentity, then 0 */
    .quad 64, 512, 128, 128, 64, 0
