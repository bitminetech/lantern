/*
 * The Beacon API answers of the node, RISC-V: in the common object. Requirements:
 * docs/reference/beacon-api.md (Common rules) and docs/reference/node.md (NODE_EV_API).
 *
 * The writer: s6 the cursor, s7 the pass (0 counts the bytes, 1 writes them), s8 the end of the
 * room, s9 1 when the room ran out, s4 the ApiView, s10 the body kind. The writer's functions
 * keep s4 and s6-s10 for it; only api_respond calls them.
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
    ADDRESS a0, \label
    li      a1, \label\()_len
    call    api_put
.endm

/* The a1 bytes at a0 join the response; the first pass only counts them. Uses t0, t1, a0, a1. */
LOCAL_FUNCTION api_put
    UNWIND_END_PROLOGUE
    beqz    s7, 2f
    add     t0, s6, a1
    bgtu    t0, s8, 3f
1:  beqz    a1, 9f
    lbu     t1, 0(a0)
    sb      t1, 0(s6)
    addi    a0, a0, 1
    addi    s6, s6, 1
    addi    a1, a1, -1
    j       1b
2:  add     s6, s6, a1
9:  ret
3:  li      s9, 1
    ret
END_FUNCTION api_put

/* The decimal digits of a0 join the response. Locals: the digits, from the end. */
LOCAL_FUNCTION api_dec
    FRAME 32
    addi    t2, sp, 32
    li      t3, 10
1:  remu    t4, a0, t3
    divu    a0, a0, t3
    addi    t4, t4, 0x30
    addi    t2, t2, -1
    sb      t4, 0(t2)
    bnez    a0, 1b
    mv      a0, t2
    addi    a1, sp, 32
    sub     a1, a1, t2
    call    api_put
    UNFRAME 32
END_FUNCTION api_dec

/* The decimal digits of a0, in quotes. Locals: a0. */
LOCAL_FUNCTION api_qdec
    FRAME 16
    sd      a0, 0(sp)
    API_LIT api_quote
    ld      a0, 0(sp)
    call    api_dec
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_qdec

/* "0x" and the lower case hex of the a1 bytes at a0, in quotes. Locals: a0, a1, then 2 digits. */
LOCAL_FUNCTION api_qhex
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    API_LIT api_quote
    API_LIT api_0x
1:  ld      a1, 8(sp)
    beqz    a1, 2f
    ld      a0, 0(sp)
    lbu     t2, 0(a0)
    addi    a0, a0, 1
    addi    a1, a1, -1
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    ADDRESS t3, api_hex
    srli    t4, t2, 4
    add     t4, t3, t4
    lbu     t4, 0(t4)
    sb      t4, 16(sp)
    andi    t4, t2, 15
    add     t4, t3, t4
    lbu     t4, 0(t4)
    sb      t4, 17(sp)
    addi    a0, sp, 16
    li      a1, 2
    call    api_put
    j       1b
2:  API_LIT api_quote
    UNFRAME 32
END_FUNCTION api_qhex

/* The text at a0 (its length, then its bytes), in quotes. Locals: a0. */
LOCAL_FUNCTION api_text
    FRAME 16
    sd      a0, 0(sp)
    API_LIT api_quote
    ld      t2, 0(sp)
    ld      a1, 0(t2)
    addi    a0, t2, 8
    call    api_put
    API_LIT api_quote
    UNFRAME 16
END_FUNCTION api_text

/* true when a0 is not 0, else false. */
LOCAL_FUNCTION api_bool
    FRAME 0
    beqz    a0, 1f
    API_LIT api_true
    UNFRAME 0
1:  API_LIT api_false
    UNFRAME 0
END_FUNCTION api_bool

/* A Checkpoint of the view at a0: {"epoch":…,"root":…}. Locals: a0. */
LOCAL_FUNCTION api_checkpoint
    FRAME 16
    sd      a0, 0(sp)
    API_LIT api_f_epoch
    ld      t2, 0(sp)
    ld      a0, 0(t2)
    call    api_qdec
    API_LIT api_f_root
    ld      a0, 0(sp)
    addi    a0, a0, 8
    li      a1, 32
    call    api_qhex
    API_LIT api_end1
    UNFRAME 16
END_FUNCTION api_checkpoint

/* a0 = the api_codes entry of the status a0, or 0. Uses t0-t2. */
LOCAL_FUNCTION api_code
    UNWIND_END_PROLOGUE
    ADDRESS t0, api_codes
    ADDRESS t1, api_codes_end
1:  bgeu    t0, t1, 2f
    ld      t2, 0(t0)
    beq     t2, a0, 3f
    addi    t0, t0, API_CODE_ENTRY
    j       1b
2:  li      a0, 0
    ret
3:  mv      a0, t0
    ret
END_FUNCTION api_code

/* The text of the api_codes entry a0 at its byte a1 (8 the reason, 24 the message), or none for no entry. */
LOCAL_FUNCTION api_code_text
    FRAME 0
    beqz    a0, 9f
    add     t0, a0, a1
    ld      t1, 0(t0)
    ld      a1, 8(t0)
    ADDRESS a0, api_texts
    add     a0, a0, t1
    call    api_put
9:  UNFRAME 0
END_FUNCTION api_code_text

/*
 * The body of the kind s10 for the view s4: an error body of the status at (a0), or the JSON of
 * an operation (beacon-api.md, Common rules). Locals: a0.
 */
/* The decimal digits of the Uint256 at a0, little endian, in quotes. Locals: its eight 32-bit words, then the text from its end. */
LOCAL_FUNCTION api_qdec256
    FRAME 128
    ld      t0, 0(a0)
    sd      t0, 0(sp)
    ld      t0, 8(a0)
    sd      t0, 8(sp)
    ld      t0, 16(a0)
    sd      t0, 16(sp)
    ld      t0, 24(a0)
    sd      t0, 24(sp)
    addi    t2, sp, 127                     # the closing quote, then the digits backwards
    li      t0, 0x22
    sb      t0, 0(t2)
    li      t3, 10
1:  li      t4, 0                           # divide by 10, from the top word down
    li      t5, 28                          # the word's offset
    li      a2, 0                           # any word not zero
2:  add     a1, sp, t5
    lwu     t0, 0(a1)
    slli    t4, t4, 32
    or      t0, t0, t4
    divu    t1, t0, t3
    remu    t4, t0, t3
    sw      t1, 0(a1)
    or      a2, a2, t1
    addi    t5, t5, -4
    bgez    t5, 2b
    addi    t4, t4, 0x30
    addi    t2, t2, -1
    sb      t4, 0(t2)
    bnez    a2, 1b
    addi    t2, t2, -1
    li      t0, 0x22
    sb      t0, 0(t2)
    mv      a0, t2
    addi    a1, sp, 128
    sub     a1, a1, t2
    call    api_put
    UNFRAME 128
END_FUNCTION api_qdec256

/*
 * The body of getSpec (beacon-api.md, Common rules): each key of API_SPEC_KEYS, with the config
 * of the view s4. Locals: the record, an index, 32 bytes of a value, a count.
 */
LOCAL_FUNCTION api_spec
    FRAME 64
    ADDRESS t0, api_spec_keys
    sd      t0, 0(sp)
    API_LIT api_p_open
    j       2f
1:  ld      t0, 0(sp)                       # the next record
    addi    t0, t0, API_SPEC_BYTES
    sd      t0, 0(sp)
    ADDRESS t1, api_spec_keys_end
    bgeu    t0, t1, 9f
    API_LIT api_p_next
2:  ld      t0, 0(sp)                       # "<name>":
    ld      a1, 0(t0)
    addi    a0, t0, 24
    call    api_put
    API_LIT api_p_key
    ld      t0, 0(sp)
    ld      t1, 8(t0)                       # the kind, the value
    ld      a0, 16(t0)
    srli    t2, t1, 8                       # the kind's arg
    andi    t1, t1, 255
    sd      a0, 16(sp)                      # the value's bytes, then zero bytes
    sd      zero, 24(sp)
    sd      zero, 32(sp)
    sd      zero, 40(sp)
    sd      t2, 48(sp)
    li      t0, SPEC_NUMBER
    bne     t1, t0, 3f
    call    api_qdec
    j       1b
3:  li      t0, SPEC_HEX
    bne     t1, t0, 4f
    addi    a0, sp, 16
    mv      a1, t2
    call    api_qhex
    j       1b
4:  li      t0, SPEC_TEXT
    bne     t1, t0, 5f
    API_LIT api_quote
    addi    a0, sp, 16
    ld      a1, 48(sp)
    call    api_put
    API_LIT api_quote
    j       1b
5:  li      t0, SPEC_LIST
    bne     t1, t0, 6f
    API_LIT api_p_lbracket
    sd      zero, 8(sp)
51: ld      t0, 8(sp)
    ld      t1, 48(sp)
    bgeu    t0, t1, 52f
    beqz    t0, 53f
    API_LIT api_p_comma
53: ld      t0, 8(sp)
    add     t1, sp, t0
    lbu     a0, 16(t1)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    call    api_qdec
    j       51b
52: API_LIT api_p_rbracket
    j       1b
6:  ld      t0, ApiView_config(s4)          # the config's field
    add     a0, t0, a0
    li      t0, SPEC_SECONDS
    bne     t1, t0, 7f
    ld      a0, 0(a0)
    li      t0, 1000
    divu    a0, a0, t0
    call    api_qdec
    j       1b
7:  li      t0, SPEC_CONFIG
    bne     t1, t0, 8f
    li      t0, CONFIG_KIND_U64
    bne     t2, t0, 71f
    ld      a0, 0(a0)
    call    api_qdec
    j       1b
71: li      t0, CONFIG_KIND_UINT256
    bne     t2, t0, 72f
    call    api_qdec256
    j       1b
72: li      t0, CONFIG_KIND_TEXT
    bne     t2, t0, 73f
    call    api_text                        # in quotes
    j       1b
73: li      a1, 4                           # Version: 4 bytes; Hash32: 32; Address: 20
    li      t0, CONFIG_KIND_HASH32
    bne     t2, t0, 74f
    li      a1, 32
74: li      t0, CONFIG_KIND_ADDRESS
    bne     t2, t0, 75f
    li      a1, 20
75: call    api_qhex
    j       1b
    # SPEC_SCHEDULE: [{"EPOCH":…,"MAX_BLOBS_PER_BLOCK":…},…]
8:  API_LIT api_p_lbracket
    sd      zero, 8(sp)
81: ld      t0, 8(sp)
    ld      t1, ApiView_config(s4)
    ld      t1, CONFIG_BLOB_SCHEDULE_COUNT(t1)
    bgeu    t0, t1, 82f
    beqz    t0, 83f
    API_LIT api_p_comma
83: API_LIT api_p_epoch
    ld      t0, 8(sp)
    slli    t0, t0, 4
    ld      t1, ApiView_config(s4)
    add     t0, t0, t1
    ld      a0, CONFIG_BLOB_SCHEDULE(t0)
    call    api_qdec
    API_LIT api_p_max
    ld      t0, 8(sp)
    slli    t0, t0, 4
    ld      t1, ApiView_config(s4)
    add     t0, t0, t1
    ld      a0, (CONFIG_BLOB_SCHEDULE + 8)(t0)
    call    api_qdec
    API_LIT api_end1
    ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    j       81b
82: API_LIT api_p_rbracket
    j       1b
9:  API_LIT api_end2
    UNFRAME 64
END_FUNCTION api_spec

/*
 * The body of getForkSchedule (beacon-api.md, Common rules), with the config of the view s4:
 * phase0, then each fork to fulu whose epoch is below 2^64 - 1. Locals: the fork, the previous
 * version, the version, the epoch.
 */
LOCAL_FUNCTION api_fork_schedule
    FRAME 32
    API_LIT api_o_open
    ld      t0, ApiView_config(s4)
    ld      t0, CONFIG_GENESIS_FORK_VERSION(t0)
    sd      zero, 0(sp)
    sd      t0, 8(sp)
    sd      t0, 16(sp)
    sd      zero, 24(sp)
    j       2f
1:  ld      t0, 0(sp)                       # the next fork: its version at 16 * fork - 8, its epoch at 16 * fork
    addi    t0, t0, 1
    sd      t0, 0(sp)
    li      t1, FORK_FULU
    bgtu    t0, t1, 9f
    slli    t0, t0, 4
    ld      t1, ApiView_config(s4)
    add     t0, t0, t1
    ld      t1, -8(t0)
    ld      t2, 0(t0)
    li      t3, -1
    beq     t2, t3, 1b
    sd      t1, 16(sp)
    sd      t2, 24(sp)
    API_LIT api_p_comma
    # {"previous_version":…,"current_version":…,"epoch":…}
2:  API_LIT api_o_entry
    addi    a0, sp, 8
    li      a1, 4
    call    api_qhex
    API_LIT api_k_current
    addi    a0, sp, 16
    li      a1, 4
    call    api_qhex
    API_LIT api_k_epoch
    ld      a0, 24(sp)
    call    api_qdec
    API_LIT api_end1
    ld      t0, 16(sp)                      # the next fork's previous version
    sd      t0, 8(sp)
    j       1b
9:  API_LIT api_o_end
    UNFRAME 32
END_FUNCTION api_fork_schedule

/* ---------------------------------------------------------------- Validators (beacon-api.md, Common rules) */

.set API_ITEM_MAX, 576                      # the most bytes of an item and its comma

/* a0 = the API_STATUS_* of the validator at a0 at the epoch a1. A leaf. Uses t0-t3. */
LOCAL_FUNCTION api_validator_status
    UNWIND_END_PROLOGUE
    ld      t0, NODE_VALIDATOR_WITHDRAWABLE(a0)
    bgtu    t0, a1, 1f
    ld      t0, NODE_VALIDATOR_EFFECTIVE_BALANCE(a0)
    li      a0, API_STATUS_WITHDRAWAL_POSSIBLE
    bnez    t0, 9f
    li      a0, API_STATUS_WITHDRAWAL_DONE
    ret
1:  lbu     t2, NODE_VALIDATOR_SLASHED(a0)
    ld      t1, NODE_VALIDATOR_EXIT(a0)
    bgtu    t1, a1, 2f
    li      a0, API_STATUS_EXITED_UNSLASHED
    beqz    t2, 9f
    li      a0, API_STATUS_EXITED_SLASHED
    ret
2:  ld      t0, NODE_VALIDATOR_ACTIVATION(a0)
    bgtu    t0, a1, 4f
    li      t3, -1                          # active: exiting with an exit epoch below FAR_FUTURE_EPOCH
    li      a0, API_STATUS_ACTIVE_ONGOING
    beq     t1, t3, 9f
    li      a0, API_STATUS_ACTIVE_EXITING
    beqz    t2, 9f
    li      a0, API_STATUS_ACTIVE_SLASHED
    ret
4:  ld      t0, NODE_VALIDATOR_ELIGIBILITY(a0)
    li      t3, -1
    li      a0, API_STATUS_PENDING_QUEUED
    bne     t0, t3, 9f
    li      a0, API_STATUS_PENDING_INITIALIZED
9:  ret
END_FUNCTION api_validator_status

/*
 * The item of the validator a1 of the state a0: a2 0 for getStateValidators, 1 for the balances,
 * 2 for the identities, 3 for their SSZ (64 bytes). Locals: the validator, the index, the kind, the
 * balance, the epoch, then an SSZ item at 48.
 */
LOCAL_FUNCTION api_validator_item
    FRAME 112
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    PART    t0, t1, a0, NODE_STATE_BALANCES
    slli    t2, a1, 3
    add     t0, t0, t2
    ld      t0, 0(t0)
    sd      t0, 24(sp)
    ld      t0, NODE_STATE_SLOT(a0)
    li      t1, SLOTS_PER_EPOCH
    divu    t0, t0, t1
    sd      t0, 32(sp)
    PART    t0, t1, a0, NODE_STATE_VALIDATORS
    slli    t2, a1, 7                       # NODE_VALIDATOR_MEM
    add     t0, t0, t2
    sd      t0, 0(sp)
    li      t1, 3
    bne     a2, t1, 1f
    sd      a1, 48(sp)                      # SSZ: index, pubkey, activation_epoch
    addi    a0, sp, 56
    mv      a1, t0
    li      a2, 48
    call    lantern_copy
    ld      t0, 0(sp)
    ld      t0, NODE_VALIDATOR_ACTIVATION(t0)
    sd      t0, 104(sp)
    addi    a0, sp, 48
    li      a1, 64
    call    api_put
    UNFRAME 112
1:  API_LIT api_v_index
    ld      a0, 8(sp)
    call    api_qdec
    ld      t0, 16(sp)
    li      t1, 2
    beq     t0, t1, 2f
    API_LIT api_v_balance
    ld      a0, 24(sp)
    call    api_qdec
    ld      t0, 16(sp)
    bnez    t0, 9f
    API_LIT api_v_status
    ld      a0, 0(sp)
    ld      a1, 32(sp)
    call    api_validator_status
    ADDRESS t0, api_v_statuses
    li      t1, 24
    mul     t1, a0, t1
    add     t0, t0, t1
    lbu     a1, 0(t0)
    addi    a0, t0, 1
    call    api_put
    API_LIT api_v_validator
    ld      a0, 0(sp)
    li      a1, 48
    call    api_qhex
    API_LIT api_v_credentials
    ld      a0, 0(sp)
    addi    a0, a0, NODE_VALIDATOR_CREDENTIALS
    li      a1, 32
    call    api_qhex
    API_LIT api_v_effective
    ld      t0, 0(sp)
    ld      a0, NODE_VALIDATOR_EFFECTIVE_BALANCE(t0)
    call    api_qdec
    API_LIT api_v_slashed
    ld      t0, 0(sp)
    lbu     a0, NODE_VALIDATOR_SLASHED(t0)
    call    api_bool
    API_LIT api_v_eligibility
    ld      t0, 0(sp)
    ld      a0, NODE_VALIDATOR_ELIGIBILITY(t0)
    call    api_qdec
    API_LIT api_v_activation
    ld      t0, 0(sp)
    ld      a0, NODE_VALIDATOR_ACTIVATION(t0)
    call    api_qdec
    API_LIT api_v_exit
    ld      t0, 0(sp)
    ld      a0, NODE_VALIDATOR_EXIT(t0)
    call    api_qdec
    API_LIT api_v_withdrawable
    ld      t0, 0(sp)
    ld      a0, NODE_VALIDATOR_WITHDRAWABLE(t0)
    call    api_qdec
    API_LIT api_end2
    UNFRAME 112
    # identities
2:  API_LIT api_v_pubkey
    ld      a0, 0(sp)
    li      a1, 48
    call    api_qhex
    API_LIT api_v_activation
    ld      t0, 0(sp)
    ld      a0, NODE_VALIDATOR_ACTIVATION(t0)
    call    api_qdec
9:  API_LIT api_end1
    UNFRAME 112
END_FUNCTION api_validator_item

/* a0 = the index of the validator of the ValidatorRef in the ByteList a1 in the state a0, or 2^64 - 1. A leaf. Uses t0-t6, a1, a7. */
LOCAL_FUNCTION node_api_find_validator
    UNWIND_END_PROLOGUE
    ld      t0, 16(a1)
    li      t1, 64
    bne     t0, t1, 8f
    ld      t0, 8(a1)
    add     a1, a1, t0
    PART    t2, t3, a0, NODE_STATE_VALIDATORS
    ld      t0, 0(a1)
    li      t1, API_VALIDATOR_INDEX
    bne     t0, t1, 2f
    ld      a0, 8(a1)
    bgeu    a0, t3, 8f
    ret
2:  li      a0, 0
3:  bgeu    a0, t3, 8f
    li      t4, 0
31: add     t5, t2, t4
    ld      t5, 0(t5)
    add     t6, a1, t4
    ld      t6, ValidatorRef_pubkey(t6)
    bne     t5, t6, 4f
    addi    t4, t4, 8
    li      t0, 48
    bltu    t4, t0, 31b
    ret
4:  addi    t2, t2, NODE_VALIDATOR_MEM
    addi    a0, a0, 1
    j       3b
8:  li      a0, -1
    ret
END_FUNCTION node_api_find_validator

/*
 * The selection of a chunk of a validator stream (node.md, NODE_WORK_API_CHUNK), at the cursor at
 * NodeEvent_api + 16 of the event s5: +16 a bitmap, in the scratch a0, of the validators of the
 * state a1 that the ValidatorRef items of data a2 name (0 with no data); +24 the epoch of the
 * state's slot; +40 the count of the validators selected. a0 = 0, or LANTERN_BUFFER_TOO_SMALL.
 * Locals: the scratch's next byte, its end, the validators, their count, the items, their count, the
 * table of the public keys, its mask.
 */
LOCAL_FUNCTION node_api_validators_prep
    FRAME 64
    ld      t0, 0(a0)
    add     t0, a0, t0
    addi    t1, a0, 16
    sd      t1, 0(sp)
    sd      t0, 8(sp)
    ld      t0, NODE_STATE_SLOT(a1)         # the epoch
    li      t1, SLOTS_PER_EPOCH
    divu    t0, t0, t1
    sd      t0, (NodeEvent_api + 16 + 24)(s5)
    PART    t0, t1, a1, NODE_STATE_VALIDATORS
    sd      t0, 16(sp)
    sd      t1, 24(sp)
    sd      t1, (NodeEvent_api + 16 + 40)(s5)   # no items: every validator
    sd      zero, (NodeEvent_api + 16 + 16)(s5)
    beqz    a2, 90f
    ld      t0, 8(a2)                       # the items
    add     t0, a2, t0
    sd      t0, 32(sp)
    ld      t0, 16(a2)
    srli    t0, t0, 6
    sd      t0, 40(sp)
    ld      a1, 24(sp)                      # the bitmap: a bit for each validator
    addi    a1, a1, 63
    srli    a1, a1, 6
    slli    a1, a1, 3
    ld      a0, 0(sp)
    add     t0, a0, a1
    ld      t1, 8(sp)
    bgtu    t0, t1, 97f
    sd      t0, 0(sp)
    sd      a0, (NodeEvent_api + 16 + 16)(s5)
    call    lantern_zero
    ld      t4, (NodeEvent_api + 16 + 16)(s5)   # index items: their bits; then count the public keys
    ld      t0, 32(sp)
    ld      t1, 40(sp)
    ld      t2, 24(sp)
    li      t3, 0
1:  beqz    t1, 3f
    ld      t5, 0(t0)
    li      t6, API_VALIDATOR_INDEX
    bne     t5, t6, 2f
    ld      t5, 8(t0)
    bgeu    t5, t2, 21f
    srli    t6, t5, 6
    slli    t6, t6, 3
    add     t6, t4, t6
    ld      a0, 0(t6)
    li      a1, 1
    sll     a1, a1, t5
    or      a0, a0, a1
    sd      a0, 0(t6)
    j       21f
2:  addi    t3, t3, 1
21: addi    t0, t0, 64
    addi    t1, t1, -1
    j       1b
3:  beqz    t3, 80f
    slli    t3, t3, 1                       # the table: the least power of two at least twice the keys
    li      t0, 1
31: bgeu    t0, t3, 32f
    slli    t0, t0, 1
    j       31b
32: addi    t1, t0, -1
    sd      t1, 56(sp)
    ld      a0, 0(sp)
    slli    a1, t0, 3
    add     t0, a0, a1
    ld      t1, 8(sp)
    bgtu    t0, t1, 97f
    sd      a0, 48(sp)
    call    lantern_zero
    ld      t0, 32(sp)                      # each public key item: its number + 1, at bytes 8 to 16 of the key
    ld      t1, 40(sp)
    ld      t2, 48(sp)
    ld      t3, 56(sp)
    li      t4, 0
4:  bgeu    t4, t1, 5f
    ld      t5, 0(t0)
    li      t6, API_VALIDATOR_PUBKEY
    bne     t5, t6, 42f
    ld      t5, (ValidatorRef_pubkey + 8)(t0)
41: and     t5, t5, t3
    slli    t6, t5, 3
    add     t6, t2, t6
    ld      a0, 0(t6)
    beqz    a0, 43f
    addi    t5, t5, 1
    j       41b
43: addi    a0, t4, 1
    sd      a0, 0(t6)
42: addi    t0, t0, 64
    addi    t4, t4, 1
    j       4b
5:  ld      t0, 16(sp)                      # each validator whose key the table holds: its bit
    li      t1, 0
    ld      t4, (NodeEvent_api + 16 + 16)(s5)
    ld      a3, 24(sp)
51: bgeu    t1, a3, 80f
    ld      t5, 8(t0)
52: and     t5, t5, t3
    slli    t6, t5, 3
    add     t6, t2, t6
    ld      a0, 0(t6)
    beqz    a0, 59f
    addi    a0, a0, -1
    slli    a0, a0, 6
    ld      a1, 32(sp)
    add     a0, a1, a0
    addi    a0, a0, ValidatorRef_pubkey
    li      a1, 0
53: add     a2, t0, a1
    ld      a2, 0(a2)
    add     a4, a0, a1
    ld      a4, 0(a4)
    bne     a2, a4, 58f
    addi    a1, a1, 8
    li      a2, 48
    bltu    a1, a2, 53b
    srli    a2, t1, 6
    slli    a2, a2, 3
    add     a2, t4, a2
    ld      a4, 0(a2)
    li      a5, 1
    sll     a5, a5, t1
    or      a4, a4, a5
    sd      a4, 0(a2)
    j       59f
58: addi    t5, t5, 1
    j       52b
59: addi    t0, t0, NODE_VALIDATOR_MEM
    addi    t1, t1, 1
    j       51b
80: ld      t0, 24(sp)                      # the count: the bits set
    addi    t0, t0, 63
    srli    t0, t0, 6
    ld      t1, (NodeEvent_api + 16 + 16)(s5)
    li      t2, 0
81: beqz    t0, 83f
    ld      t3, 0(t1)
    addi    t1, t1, 8
82: beqz    t3, 84f
    addi    t4, t3, -1
    and     t3, t3, t4
    addi    t2, t2, 1
    j       82b
84: addi    t0, t0, -1
    j       81b
83: sd      t2, (NodeEvent_api + 16 + 40)(s5)
90: li      a0, 0
    UNFRAME 64
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 64
END_FUNCTION node_api_validators_prep

/*
 * The items of the pending stream of the entry s4, of the state s3 (node.md, NODE_WORK_API_CHUNK),
 * from the index at NodeEvent_api + 16 of the event s5, at the writer's cursor s6 up to s8, with ,
 * between; then ]} once they are all written. a0 = 1 when whole, 0 when more is to come, 2 when the
 * state has no such list. Locals: lantern_node_pending's out, the kind.
 */
LOCAL_FUNCTION api_pending_json
    FRAME 32
    ld      t0, NodeApi_op(s4)              # the kind: 0 deposits, 1 partial withdrawals, 2 consolidations
    addi    a1, t0, -API_OP_GET_PENDING_DEPOSITS
    li      t1, API_OP_GET_PENDING_CONSOLIDATIONS
    bne     t0, t1, 1f
    li      a1, 2
1:  sd      a1, 24(sp)
    mv      a0, s3
    mv      a2, sp
    ld      t6, NodeApi_fork(s4)
    FORK_CALL node_pending
    bnez    a0, 7f
2:  ld      t0, (NodeEvent_api + 16)(s5)
    ld      t1, 8(sp)
    bgeu    t0, t1, 8f
    sub     t2, s8, s6                      # room for one more item
    li      t3, API_ITEM_MAX
    bltu    t2, t3, 9f
    beqz    t0, 3f
    API_LIT api_p_comma
3:  ld      t0, (NodeEvent_api + 16)(s5)
    ld      t1, 16(sp)
    mul     t0, t0, t1
    ld      t1, 0(sp)
    add     a0, t1, t0
    ld      a1, 24(sp)
    call    api_pending_item
    ld      t0, (NodeEvent_api + 16)(s5)
    addi    t0, t0, 1
    sd      t0, (NodeEvent_api + 16)(s5)
    j       2b
8:  API_LIT api_v_end
    li      a0, 1
    UNFRAME 32
9:  li      a0, 0
    UNFRAME 32
7:  li      a0, 2
    UNFRAME 32
END_FUNCTION api_pending_json

/*
 * The JSON of the pending item at a0 of the kind a1 (lantern_node_pending): a PendingDeposit, a
 * PendingPartialWithdrawal or a PendingConsolidation, from its SSZ fields. Locals: the item.
 */
LOCAL_FUNCTION api_pending_item
    FRAME 16
    sd      a0, 0(sp)
    li      t0, 1
    beq     a1, t0, 20f
    bgtu    a1, t0, 30f
    # {"pubkey":…,"withdrawal_credentials":…,"amount":…,"signature":…,"slot":…}
    API_LIT api_q_pubkey
    ld      a0, 0(sp)
    li      a1, 48
    call    api_qhex
    API_LIT api_q_credentials
    ld      a0, 0(sp)
    addi    a0, a0, 48
    li      a1, 32
    call    api_qhex
    API_LIT api_q_amount
    ld      t0, 0(sp)
    ld      a0, 80(t0)
    call    api_qdec
    API_LIT api_q_signature
    ld      a0, 0(sp)
    addi    a0, a0, 88
    li      a1, 96
    call    api_qhex
    API_LIT api_q_slot
    ld      t0, 0(sp)
    ld      a0, 184(t0)
    call    api_qdec
    j       9f
    # {"validator_index":…,"amount":…,"withdrawable_epoch":…}
20: API_LIT api_q_validator
    ld      t0, 0(sp)
    ld      a0, 0(t0)
    call    api_qdec
    API_LIT api_q_amount
    ld      t0, 0(sp)
    ld      a0, 8(t0)
    call    api_qdec
    API_LIT api_q_withdrawable
    ld      t0, 0(sp)
    ld      a0, 16(t0)
    call    api_qdec
    j       9f
    # {"source_index":…,"target_index":…}
30: API_LIT api_q_source
    ld      t0, 0(sp)
    ld      a0, 0(t0)
    call    api_qdec
    API_LIT api_q_target
    ld      t0, 0(sp)
    ld      a0, 8(t0)
    call    api_qdec
9:  API_LIT api_end1
    UNFRAME 16
END_FUNCTION api_pending_item

/*
 * The items of the validator stream of the entry s4, of the state s3, from the cursor at
 * NodeEvent_api + 16 of the event s5 (+0 the next index, +8 the status bits, +16 the bitmap, +24
 * the epoch, +32 the items written), at the writer's cursor s6 up to s8; then ]} for JSON once they
 * are all written. a0 = 1 when whole, else 0. Locals: the kind, the validators' count.
 */
LOCAL_FUNCTION api_validators_json
    FRAME 32
    li      t0, 0                           # the kind: 0, 1 the balances, 2 the identities, 3 their SSZ
    ld      t1, NodeApi_op(s4)
    li      t2, API_OP_GET_STATE_VALIDATOR_BALANCES
    beq     t1, t2, 11f
    li      t2, API_OP_POST_STATE_VALIDATOR_BALANCES
    bne     t1, t2, 12f
11: li      t0, 1
12: li      t2, API_OP_POST_STATE_VALIDATOR_IDENTITIES
    bne     t1, t2, 13f
    li      t0, 2
    ld      t2, NodeApi_flags(s4)
    andi    t2, t2, API_STREAM_SSZ
    beqz    t2, 13f
    li      t0, 3
13: sd      t0, 0(sp)
    LDQ     t0, s3, NODE_STATE_VALIDATORS + 8
    sd      t0, 8(sp)
2:  ld      t1, (NodeEvent_api + 16)(s5)
    ld      t0, 8(sp)
    bgeu    t1, t0, 8f
    ld      t2, (NodeEvent_api + 16 + 16)(s5)   # with a bitmap: the next validator it names
    beqz    t2, 3f
    srli    t3, t1, 6
    slli    t3, t3, 3
    add     t3, t2, t3
    ld      t3, 0(t3)
    srl     t3, t3, t1
    bnez    t3, 21f
    addi    t1, t1, 64
    andi    t1, t1, -64
    sd      t1, (NodeEvent_api + 16)(s5)
    j       2b
21: li      t4, 0                           # its lowest set bit
22: andi    t5, t3, 1
    bnez    t5, 23f
    srli    t3, t3, 1
    addi    t4, t4, 1
    j       22b
23: add     t1, t1, t4
    sd      t1, (NodeEvent_api + 16)(s5)
3:  ld      t2, (NodeEvent_api + 16 + 8)(s5)    # with status bits: its status has its bit
    beqz    t2, 4f
    PART    t3, t4, s3, NODE_STATE_VALIDATORS
    slli    t5, t1, 7
    add     a0, t3, t5
    ld      a1, (NodeEvent_api + 16 + 24)(s5)
    call    api_validator_status
    ld      t2, (NodeEvent_api + 16 + 8)(s5)
    srl     t2, t2, a0
    andi    t2, t2, 1
    bnez    t2, 4f
    ld      t1, (NodeEvent_api + 16)(s5)
    addi    t1, t1, 1
    sd      t1, (NodeEvent_api + 16)(s5)
    j       2b
4:  sub     t0, s8, s6                      # room for one more item
    li      t1, API_ITEM_MAX
    bltu    t0, t1, 9f
    ld      t0, 0(sp)
    li      t1, 3
    beq     t0, t1, 5f
    ld      t0, (NodeEvent_api + 16 + 32)(s5)
    beqz    t0, 5f
    API_LIT api_p_comma
5:  ld      t0, (NodeEvent_api + 16 + 32)(s5)
    addi    t0, t0, 1
    sd      t0, (NodeEvent_api + 16 + 32)(s5)
    mv      a0, s3
    ld      a1, (NodeEvent_api + 16)(s5)
    ld      a2, 0(sp)
    call    api_validator_item
    ld      t1, (NodeEvent_api + 16)(s5)
    addi    t1, t1, 1
    sd      t1, (NodeEvent_api + 16)(s5)
    j       2b
8:  ld      t0, 0(sp)                       # all: ]} for JSON
    li      t1, 3
    beq     t0, t1, 81f
    sub     t0, s8, s6
    li      t1, 2
    bltu    t0, t1, 9f
    API_LIT api_v_end
81: li      a0, 1
    UNFRAME 32
9:  li      a0, 0
    UNFRAME 32
END_FUNCTION api_validators_json

/*
 * a0 = the epoch of getEpochCommittees of the route a0 and the state of the view a1 (beacon-api.md,
 * Common rules), or 2^64 - 1 for 400: an epoch above the state's + 1, one whose seed's RANDAO mix the
 * state no longer holds, or a slot of another epoch. A leaf. Uses t0-t4.
 */
LOCAL_FUNCTION node_api_committees_check
    UNWIND_END_PROLOGUE
    ld      t0, ApiView_head_slot(a1)       # the state's epoch at t0, the epoch at t1
    li      t2, SLOTS_PER_EPOCH
    divu    t0, t0, t2
    mv      t1, t0
    ld      t3, ApiRoute_present(a0)
    srli    t4, t3, API_PARAM_EPOCH
    andi    t4, t4, 1
    beqz    t4, 1f
    ld      t1, ApiRoute_epoch(a0)
1:  addi    t2, t0, 1                       # at most the state's epoch + 1
    bgtu    t1, t2, 8f
    li      t4, EPOCHS_PER_HISTORICAL_VECTOR    # epoch - MIN_SEED_LOOKAHEAD - 1 at least epoch + 1 - EPOCHS_PER_HISTORICAL_VECTOR, each 0 when below
    bltu    t2, t4, 11f
    sub     t2, t2, t4
    j       12f
11: li      t2, 0
12: li      t4, MIN_SEED_LOOKAHEAD + 1
    bltu    t1, t4, 13f
    sub     t4, t1, t4
    j       14f
13: li      t4, 0
14: bltu    t4, t2, 8f
    srli    t4, t3, API_PARAM_SLOT          # a slot of the epoch
    andi    t4, t4, 1
    beqz    t4, 2f
    ld      t4, ApiRoute_slot(a0)
    li      t2, SLOTS_PER_EPOCH
    divu    t4, t4, t2
    bne     t4, t1, 8f
2:  mv      a0, t1
    ret
8:  li      a0, -1
    ret
END_FUNCTION node_api_committees_check

/*
 * The cursor of the getEpochCommittees stream of the entry a0, for the route a1 and the epoch a2
 * (node.md, NODE_EV_API): the first slot at 0, the first index at 8, the epoch at 24, the slot and
 * the index asked at 40 and 48 (2^64 - 1 for none). A leaf. Uses t0-t3.
 */
LOCAL_FUNCTION node_api_committees_cursor
    UNWIND_END_PROLOGUE
    sd      a2, (NodeApi_cursor + 24)(a0)
    li      t0, SLOTS_PER_EPOCH
    mul     t0, a2, t0
    li      t1, -1
    ld      t2, ApiRoute_present(a1)
    srli    t3, t2, API_PARAM_SLOT
    andi    t3, t3, 1
    beqz    t3, 1f
    ld      t0, ApiRoute_slot(a1)
    mv      t1, t0
1:  sd      t0, NodeApi_cursor(a0)
    sd      t1, (NodeApi_cursor + 40)(a0)
    li      t0, 0
    li      t1, -1
    srli    t3, t2, API_PARAM_INDEX
    andi    t3, t3, 1
    beqz    t3, 2f
    ld      t0, ApiRoute_index(a1)
    mv      t1, t0
2:  sd      t0, (NodeApi_cursor + 8)(a0)
    sd      t1, (NodeApi_cursor + 48)(a0)
    ret
END_FUNCTION node_api_committees_cursor

/*
 * A chunk's start of a getEpochCommittees stream (node.md, NODE_WORK_API_CHUNK), at the cursor at
 * NodeEvent_api + 16 of the event s5: +56 get_committee_count_per_slot of the state a1 at the epoch
 * at +24; +72 the scratch a0 and +80 the CommitteeCache of the node a2, for api_committees_json. a0 =
 * 0; 400 for an index asked at or past the count, in the first chunk; LANTERN_BUFFER_TOO_SMALL for a
 * scratch with no room for a committee and lantern_get_beacon_committee; else the status of the
 * count. Locals: the epoch, the count, the state.
 */
LOCAL_FUNCTION node_api_committees_prep
    FRAME 32
    sd      a0, (NodeEvent_api + 16 + 72)(s5)
    sd      a1, 16(sp)
    ld      t0, (NodeEvent_api + 16 + 24)(s5)
    sd      t0, 0(sp)
    mv      a3, a0
    mv      a0, a1
    mv      a1, sp
    LDQ     a2, a2, Node_config + CONFIG_COMMITTEE_CACHE
    sd      a2, (NodeEvent_api + 16 + 80)(s5)
    addi    a4, sp, 8
    ld      t6, NodeApi_fork(s4)
    FORK_CALL get_committee_count_per_slot
    bnez    a0, 9f
    ld      t0, 8(sp)                       # the count
    sd      t0, (NodeEvent_api + 16 + 56)(s5)
    ld      t1, 16(sp)                      # the scratch: 16, a committee's list, then S(2)
    LDQ     t1, t1, NODE_STATE_VALIDATORS + 8
    li      t2, SLOTS_PER_EPOCH
    mul     t2, t0, t2
    divu    t2, t1, t2
    addi    t2, t2, 1
    slli    t2, t2, 3
    addi    t2, t2, (16 + LIST_FIXED)
    slli    t1, t1, 3
    addi    t1, t1, LIST_FIXED
    slli    t1, t1, 1
    add     t2, t2, t1
    li      t1, LANTERN_SCRATCH_FIXED
    add     t2, t2, t1
    ld      t1, (NodeEvent_api + 16 + 72)(s5)
    ld      t1, 0(t1)
    bltu    t1, t2, 97f
    ld      t1, (NodeEvent_api + 8)(s5)     # the first chunk: an index at or past the count, 400
    andi    t1, t1, API_STREAM_STARTED
    bnez    t1, 8f
    ld      t1, (NodeEvent_api + 16 + 48)(s5)
    li      t2, -1
    beq     t1, t2, 8f
    bltu    t1, t0, 8f
    li      a0, 400
    UNFRAME 32
8:  li      a0, 0
9:  UNFRAME 32
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    UNFRAME 32
END_FUNCTION node_api_committees_prep

/*
 * The items of the getEpochCommittees stream of the entry s4, of the state s3, from the cursor at
 * NodeEvent_api + 16 of the event s5 (+0 the slot, +8 the index, +16 the member, +24 the epoch, +32
 * the items written, +40 and +48 the slot and the index asked or 2^64 - 1, +56 the committees per
 * slot, +64 1 within an item, +72 the scratch, +80 the CommitteeCache), at the writer's cursor s6 up
 * to s8; then ]} once they are all written. a0 = 1 when whole, 0 when more is to come, 2 when a
 * committee fails. Locals: the slot, the index, the committee's list.
 */
LOCAL_FUNCTION api_committees_json
    FRAME 32
1:  ld      t0, (NodeEvent_api + 16)(s5)    # the slot and the index
    ld      t1, (NodeEvent_api + 16 + 8)(s5)
    ld      t2, (NodeEvent_api + 16 + 40)(s5)   # the last slot: the one asked, else the epoch's last
    li      t3, -1
    bne     t2, t3, 2f
    ld      t2, (NodeEvent_api + 16 + 24)(s5)
    addi    t2, t2, 1
    li      t4, SLOTS_PER_EPOCH
    mul     t2, t2, t4
    addi    t2, t2, -1
2:  bgtu    t0, t2, 8f
    ld      t2, (NodeEvent_api + 16 + 48)(s5)   # the end of the indices: past the one asked, else the count
    ld      t4, (NodeEvent_api + 16 + 56)(s5)
    beq     t2, t3, 21f
    addi    t4, t2, 1
21: bltu    t1, t4, 3f
    addi    t0, t0, 1                       # the slot's committees are written: the next slot
    li      t1, 0
    beq     t2, t3, 22f
    mv      t1, t2
22: sd      t0, (NodeEvent_api + 16)(s5)
    sd      t1, (NodeEvent_api + 16 + 8)(s5)
    j       1b
3:  ld      t2, (NodeEvent_api + 16 + 64)(s5)
    bnez    t2, 4f
    sub     t2, s8, s6                      # the item's head: {"index":…,"slot":…,"validators":[
    li      t3, 80
    bltu    t2, t3, 9f
    ld      t2, (NodeEvent_api + 16 + 32)(s5)
    beqz    t2, 31f
    API_LIT api_p_comma
31: ld      t2, (NodeEvent_api + 16 + 32)(s5)
    addi    t2, t2, 1
    sd      t2, (NodeEvent_api + 16 + 32)(s5)
    li      t2, 1
    sd      t2, (NodeEvent_api + 16 + 64)(s5)
    sd      zero, (NodeEvent_api + 16 + 16)(s5)
    API_LIT api_v_index
    ld      a0, (NodeEvent_api + 16 + 8)(s5)
    call    api_qdec
    API_LIT api_c_slot
    ld      a0, (NodeEvent_api + 16)(s5)
    call    api_qdec
    API_LIT api_c_validators
4:  ld      t0, (NodeEvent_api + 16)(s5)    # the committee, in a list after 16 bytes of the scratch
    sd      t0, 0(sp)
    ld      t0, (NodeEvent_api + 16 + 8)(s5)
    sd      t0, 8(sp)
    LDQ     t0, s3, NODE_STATE_VALIDATORS + 8
    ld      t1, (NodeEvent_api + 16 + 56)(s5)
    li      t2, SLOTS_PER_EPOCH
    mul     t1, t1, t2
    divu    t0, t0, t1
    addi    t0, t0, 1
    slli    t0, t0, 3
    addi    t0, t0, LIST_FIXED
    ld      t1, (NodeEvent_api + 16 + 72)(s5)
    addi    t2, t1, 16
    sd      t0, 0(t2)
    li      t3, LIST_FIXED
    sd      t3, LIST_OFFSET(t2)
    sd      zero, LIST_COUNT(t2)
    sd      t2, 16(sp)
    addi    t3, t0, 16
    add     a4, t1, t3
    ld      t4, 0(t1)
    sub     t4, t4, t3
    sd      t4, 0(a4)
    mv      a0, s3
    mv      a1, sp
    addi    a2, sp, 8
    ld      a3, (NodeEvent_api + 16 + 80)(s5)
    mv      a5, t2
    ld      t6, NodeApi_fork(s4)
    FORK_CALL get_beacon_committee
    bnez    a0, 7f
41: ld      t0, (NodeEvent_api + 16 + 16)(s5)   # its members from the one at +16
    ld      t1, 16(sp)
    ld      t2, LIST_COUNT(t1)
    bgeu    t0, t2, 5f
    sub     t2, s8, s6
    li      t3, 24
    bltu    t2, t3, 9f
    beqz    t0, 42f
    API_LIT api_p_comma
42: ld      t0, (NodeEvent_api + 16 + 16)(s5)
    ld      t1, 16(sp)
    slli    t2, t0, 3
    add     t1, t1, t2
    ld      a0, LIST_FIXED(t1)
    addi    t0, t0, 1
    sd      t0, (NodeEvent_api + 16 + 16)(s5)
    call    api_qdec
    j       41b
5:  sub     t2, s8, s6                      # the item's end: ]}
    li      t3, 2
    bltu    t2, t3, 9f
    API_LIT api_v_end
    sd      zero, (NodeEvent_api + 16 + 64)(s5)
    ld      t1, (NodeEvent_api + 16 + 8)(s5)
    addi    t1, t1, 1
    sd      t1, (NodeEvent_api + 16 + 8)(s5)
    j       1b
7:  li      a0, 2
    UNFRAME 32
8:  sub     t2, s8, s6                      # all: ]}
    li      t3, 2
    bltu    t2, t3, 9f
    API_LIT api_v_end
    li      a0, 1
    UNFRAME 32
9:  li      a0, 0
    UNFRAME 32
END_FUNCTION api_committees_json

/*
 * a0 = the new id of a NODE_ACT_BYTES_PUT of the ValidatorRef items of the validator operation of
 * the route a0 (getStateValidator: its validator_id), or 0 with none (node.md, NODE_EV_API).
 * Locals: a ByteList head whose offset reaches the items.
 */
LOCAL_FUNCTION node_api_ids
    FRAME 32
    ld      t0, ApiRoute_op(a0)
    li      t1, API_OP_GET_STATE_VALIDATOR
    bne     t0, t1, 1f
    addi    t0, a0, ApiRoute_validator
    li      t1, 64
    j       2f
1:  ld      t0, ApiRoute_list(a0)
    add     t0, a0, t0
    ld      t1, (ApiRoute_list + 8)(a0)
    slli    t1, t1, 6
    bnez    t1, 2f
    li      a0, 0
    UNFRAME 32
2:  sub     t0, t0, sp
    sd      t1, 0(sp)
    sd      t0, 8(sp)
    sd      t1, 16(sp)
    mv      a0, sp
    call    node_put
    UNFRAME 32
END_FUNCTION node_api_ids

LOCAL_FUNCTION api_body
    FRAME 16
    sd      a0, 0(sp)
    li      t0, API_BODY_ERROR
    bne     s10, t0, 1f
    # {"code":<n>,"message":"<m>"}
    API_LIT api_e_code
    ld      t0, 0(sp)
    ld      a0, 0(t0)
    call    api_dec
    API_LIT api_e_message
    ld      t0, 0(sp)
    ld      a0, 0(t0)
    call    api_code
    li      a1, 24
    call    api_code_text
    API_LIT api_e_end
    UNFRAME 16
1:  li      t0, API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    bne     s10, t0, 11f
    # {"code":400,"message":"BAD_REQUEST","failures":[…]}: s4 the event of the work
    API_LIT api_e_code
    ld      t0, 0(sp)
    ld      a0, 0(t0)
    call    api_dec
    API_LIT api_e_message
    ld      t0, 0(sp)
    ld      a0, 0(t0)
    call    api_code
    li      a1, 24
    call    api_code_text
    API_LIT api_f_list
    call    api_failures
    UNFRAME 16
11: li      t0, API_OP_GET_PEERS
    bne     s10, t0, 116f
    call    api_peers_body
    UNFRAME 16
116: li     t0, API_OP_GET_PEER
    bne     s10, t0, 117f
    API_LIT api_pe_data
    LDQ     a0, s4, ApiView_peer
    call    api_peer_item
    API_LIT api_end1
    UNFRAME 16
117: li     t0, API_OP_GET_DEBUG_CHAIN_HEADS_V2
    bne     s10, t0, 110f
    call    api_heads_body
    UNFRAME 16
110: li     t0, API_OP_GET_DEBUG_FORK_CHOICE
    bne     s10, t0, 115f
    call    api_fork_choice_body
    UNFRAME 16
115: li     t0, API_OP_GET_STATE_RANDAO
    beq     s10, t0, 113f
    li      t0, API_OP_GET_EPOCH_SYNC_COMMITTEES
    beq     s10, t0, 113f
    li      t0, API_OP_GET_PROPOSER_LOOKAHEAD
    bne     s10, t0, 114f
113: ld     a0, 0(sp)                       # the state reads
    call    api_state_read_body
    UNFRAME 16
114: li     t0, API_OP_PRODUCE_ATTESTATION_DATA
    bne     s10, t0, 12f
    ld      t0, 0(sp)                       # SSZ: its 128 bytes
    ld      t0, 8(t0)
    andi    t0, t0, API_R_SSZ
    beqz    t0, 13f
    ADDQ    a0, s4, ApiView_att
    li      a1, 128
    call    api_put
    UNFRAME 16
    # {"data":{"slot":…,"index":…,"beacon_block_root":…,"source":…,"target":…}}
13: API_LIT api_a_slot
    LDQ     a0, s4, ApiView_att
    call    api_qdec
    API_LIT api_a_index
    LDQ     a0, s4, ApiView_att + 8
    call    api_qdec
    API_LIT api_a_root
    ADDQ    a0, s4, ApiView_att + 16
    li      a1, 32
    call    api_qhex
    API_LIT api_a_source
    ADDQ    a0, s4, ApiView_att + 48
    call    api_checkpoint
    API_LIT api_a_target
    ADDQ    a0, s4, ApiView_att + 88
    call    api_checkpoint
    API_LIT api_end2
    UNFRAME 16
12: li      t0, API_OP_GET_NETWORK_IDENTITY
    bne     s10, t0, 2f
    API_LIT api_i_peer_id
    addi    a0, s4, ApiView_peer_id
    call    api_text
    API_LIT api_i_enr
    addi    a0, s4, ApiView_enr
    call    api_text
    API_LIT api_i_p2p
    ld      t0, ApiView_p2p_address(s4)
    beqz    t0, 14f
    addi    a0, s4, ApiView_p2p_address
    call    api_text
14: API_LIT api_i_discovery
    ld      t0, ApiView_discovery_address(s4)
    beqz    t0, 15f
    addi    a0, s4, ApiView_discovery_address
    call    api_text
15: API_LIT api_i_seq
    ld      a0, ApiView_seq_number(s4)
    call    api_qdec
    API_LIT api_i_attnets
    addi    a0, s4, ApiView_attnets
    li      a1, 8
    call    api_qhex
    ld      t0, ApiView_fork(s4)
    li      t1, FORK_ALTAIR
    bltu    t0, t1, 16f
    API_LIT api_i_syncnets
    addi    a0, s4, ApiView_syncnets
    li      a1, 1
    call    api_qhex
    ld      t0, ApiView_fork(s4)
    li      t1, FORK_FULU
    bltu    t0, t1, 16f
    API_LIT api_i_cgc
    ld      a0, ApiView_custody_group_count(s4)
    call    api_qdec
16: API_LIT api_end3
    UNFRAME 16
2:  li      t0, API_OP_GET_NODE_VERSION
    bne     s10, t0, 3f
    API_LIT api_v_version
    addi    a0, s4, ApiView_version
    call    api_text
    API_LIT api_end2
    UNFRAME 16
3:  li      t0, API_OP_GET_SYNCING_STATUS
    bne     s10, t0, 4f
    API_LIT api_s_head
    ld      a0, ApiView_head_slot(s4)
    call    api_qdec
    API_LIT api_s_distance
    ld      t0, ApiView_current_slot(s4)
    ld      t1, ApiView_head_slot(s4)
    li      a0, 0
    bltu    t0, t1, 31f
    sub     a0, t0, t1
31: call    api_qdec
    API_LIT api_s_syncing
    ld      a0, ApiView_is_syncing(s4)
    call    api_bool
    API_LIT api_s_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_s_offline
    ld      a0, ApiView_el_offline(s4)
    call    api_bool
    API_LIT api_end2
    UNFRAME 16
4:  li      t0, API_OP_GET_PEER_COUNT
    bne     s10, t0, 5f
    API_LIT api_c_connected
    ld      a0, ApiView_peers(s4)
    call    api_qdec
    API_LIT api_c_end
    UNFRAME 16
5:  li      t0, API_OP_GET_GENESIS
    bne     s10, t0, 6f
    API_LIT api_g_time
    ld      a0, ApiView_genesis_time(s4)
    call    api_qdec
    API_LIT api_g_root
    addi    a0, s4, ApiView_genesis_validators_root
    li      a1, 32
    call    api_qhex
    API_LIT api_g_version
    addi    a0, s4, ApiView_genesis_fork_version
    li      a1, 4
    call    api_qhex
    API_LIT api_end2
    UNFRAME 16
6:  li      t0, API_OP_GET_BLOCK_HEADER
    bne     s10, t0, 7f
    API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, ApiView_head_finalized(s4)
    call    api_bool
    API_LIT api_x_data
    API_LIT api_h_root
    addi    a0, s4, ApiView_head_root
    li      a1, 32
    call    api_qhex
    ld      a0, ApiView_head_slot(s4)
    addi    a1, s4, ApiView_proposer_index
    ld      a2, ApiView_canonical(s4)
    call    api_header_json
    API_LIT api_end3
    UNFRAME 16
7:  li      t0, API_OP_GET_STATE_FINALITY_CHECKPOINTS
    bne     s10, t0, 9f
    API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, ApiView_head_finalized(s4)
    call    api_bool
    API_LIT api_x_data
    API_LIT api_f_previous
    addi    a0, s4, ApiView_previous_justified
    call    api_checkpoint
    API_LIT api_f_current
    addi    a0, s4, ApiView_current_justified
    call    api_checkpoint
    API_LIT api_f_finalized
    addi    a0, s4, ApiView_finalized
    call    api_checkpoint
    API_LIT api_end2
    UNFRAME 16
9:  li      t0, API_OP_GET_BLOCK_ROOT       # getBlockRoot, getStateRoot: {"execution_optimistic":…,"finalized":…,"data":{"root":…}}
    beq     s10, t0, 10f
    li      t0, API_OP_GET_STATE_ROOT
    beq     s10, t0, 10f
    li      t0, API_OP_GET_STATE_FORK
    bne     s10, t0, 12f
10: API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, ApiView_head_finalized(s4)
    call    api_bool
    API_LIT api_x_data
    li      t0, API_OP_GET_STATE_FORK
    beq     s10, t0, 11f
    API_LIT api_h_root
    addi    a0, s4, ApiView_head_root
    li      a1, 32
    call    api_qhex
    API_LIT api_end2
    UNFRAME 16
    # getStateFork: {"previous_version":…,"current_version":…,"epoch":…}
11: API_LIT api_k_previous
    addi    a0, s4, ApiView_state_fork
    li      a1, 4
    call    api_qhex
    API_LIT api_k_current
    addi    a0, s4, (ApiView_state_fork + 4)
    li      a1, 4
    call    api_qhex
    API_LIT api_k_epoch
    ld      a0, (ApiView_state_fork + 8)(s4)
    call    api_qdec
    API_LIT api_end2
    UNFRAME 16
12: li      t0, API_OP_GET_SPEC
    bne     s10, t0, 13f
    call    api_spec
    UNFRAME 16
13: li      t0, API_OP_GET_FORK_SCHEDULE
    bne     s10, t0, 17f
    call    api_fork_schedule
    UNFRAME 16
17: li      t0, API_OP_GET_DEPOSIT_CONTRACT  # {"data":{"chain_id":…,"address":…}}
    bne     s10, t0, 18f
    API_LIT api_d_chain
    ld      t0, ApiView_config(s4)
    ld      a0, CONFIG_DEPOSIT_CHAIN_ID(t0)
    call    api_qdec
    API_LIT api_d_address
    ld      t0, ApiView_config(s4)
    addi    a0, t0, CONFIG_DEPOSIT_CONTRACT_ADDRESS
    li      a1, 20
    call    api_qhex
    API_LIT api_end2
    UNFRAME 16
18: li      t0, API_OP_GET_STATE_VALIDATOR   # {"execution_optimistic":…,"finalized":…,"data":<item>}
    bne     s10, t0, 19f
    API_LIT api_v_open
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, ApiView_head_finalized(s4)
    call    api_bool
    API_LIT api_v_data
    ld      a0, ApiView_val_state(s4)
    ld      a1, ApiView_val_index(s4)
    li      a2, 0
    call    api_validator_item
    API_LIT api_end1
    UNFRAME 16
    # getProposerDuties: {"dependent_root":…,"execution_optimistic":…,"data":[{"pubkey":…,"validator_index":…,"slot":…},…]}
19: li      t0, API_OP_GET_PROPOSER_DUTIES
    bne     s10, t0, 18f
    API_LIT api_u_root
    addi    a0, s4, ApiView_duties
    li      a1, 32
    call    api_qhex
    API_LIT api_u_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_v_list
    sd      zero, 8(sp)                     # the slot's place in the epoch
20: ld      t0, 8(sp)
    li      t1, SLOTS_PER_EPOCH
    bgeu    t0, t1, 21f
    beqz    t0, 22f
    API_LIT api_p_comma
22: API_LIT api_u_pubkey
    ld      a0, ApiView_val_state(s4)
    PART    t0, t1, a0, NODE_STATE_VALIDATORS
    ld      t2, 8(sp)
    slli    t2, t2, 3
    add     t2, t2, s4
    ld      t2, (ApiView_duties + 32)(t2)
    slli    t2, t2, 7                       # NODE_VALIDATOR_MEM: the pubkey first
    add     a0, t0, t2
    li      a1, 48
    call    api_qhex
    API_LIT api_u_index
    ld      t2, 8(sp)
    slli    t2, t2, 3
    add     t2, t2, s4
    ld      a0, (ApiView_duties + 32)(t2)
    call    api_qdec
    API_LIT api_c_slot
    ld      t0, ApiView_val_state(s4)
    ld      a0, NODE_STATE_SLOT(t0)
    ld      t1, 8(sp)
    add     a0, a0, t1
    call    api_qdec
    API_LIT api_end1
    ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    j       20b
21: API_LIT api_v_end
    UNFRAME 16
18: li      t0, API_OP_GET_SYNC_COMMITTEE_DUTIES
    bne     s10, t0, 181f
    call    api_sync_duties_body
    UNFRAME 16
181: li     t0, API_OP_GET_ATTESTER_DUTIES
    bne     s10, t0, 99f
    call    api_duties_json
99: UNFRAME 16
END_FUNCTION api_body

/*
 * The JSON of getAttesterDuties from the view s4: {"dependent_root":…,"execution_optimistic":…,
 * "data":[{"pubkey":…,…,"slot":…},…]}, an item for each record with an assignment. Locals: a
 * record's place, the items written, the record.
 */
LOCAL_FUNCTION api_duties_json
    FRAME 32
    API_LIT api_u_root
    LDQ     a0, s4, ApiView_ad_out
    li      a1, 32
    call    api_qhex
    API_LIT api_u_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_v_list
    sd      zero, 0(sp)
    sd      zero, 8(sp)
1:  ld      t0, 0(sp)
    LDQ     t1, s4, ApiView_ad_count
    bgeu    t0, t1, 9f
    li      t1, 48
    mul     t0, t0, t1
    LDQ     t1, s4, ApiView_ad_out
    add     t0, t0, t1
    addi    t0, t0, 40
    sd      t0, 16(sp)
    ld      t1, 0(t0)
    beqz    t1, 8f
    ld      t1, 8(sp)
    beqz    t1, 2f
    API_LIT api_p_comma
2:  ld      t1, 8(sp)
    addi    t1, t1, 1
    sd      t1, 8(sp)
    API_LIT api_u_pubkey
    ld      t2, ApiView_val_state(s4)
    PART    t0, t1, t2, NODE_STATE_VALIDATORS
    ld      t1, 16(sp)
    ld      t1, 40(t1)
    slli    t1, t1, 7                       # NODE_VALIDATOR_MEM: the pubkey first
    add     a0, t0, t1
    li      a1, 48
    call    api_qhex
    API_LIT api_u_index
    ld      t0, 16(sp)
    ld      a0, 40(t0)
    call    api_qdec
    API_LIT api_t_committee_index
    ld      t0, 16(sp)
    ld      a0, 16(t0)
    call    api_qdec
    API_LIT api_t_committee_length
    ld      t0, 16(sp)
    ld      a0, 24(t0)
    call    api_qdec
    API_LIT api_t_committees_at_slot
    LDQ     t0, s4, ApiView_ad_out
    ld      a0, 32(t0)
    call    api_qdec
    API_LIT api_t_validator_committee_index
    ld      t0, 16(sp)
    ld      a0, 32(t0)
    call    api_qdec
    API_LIT api_c_slot
    ld      t0, 16(sp)
    ld      a0, 8(t0)
    call    api_qdec
    API_LIT api_end1
8:  ld      t0, 0(sp)
    addi    t0, t0, 1
    sd      t0, 0(sp)
    j       1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION api_duties_json

/*
 * L1: the body of getDebugChainHeadsV2 (beacon-api.md): {"data":[{"root":…,"slot":…,"execution_optimistic":…},…]}
 * of the store nodes at ApiView_val_state of the view s4 whose byte at ApiView_heads is 0. Locals: the
 * index, 1 once an item is written, the node.
 */
LOCAL_FUNCTION api_heads_body
    FRAME 32
    API_LIT api_p_data
    sd      zero, 0(sp)
    sd      zero, 8(sp)
1:  ld      t0, ApiView_val_state(s4)
    ld      t1, (Store_blocks + 8)(t0)
    ld      t2, 0(sp)
    bgeu    t2, t1, 9f
    LDQ     t3, s4, ApiView_heads
    add     t3, t3, t2
    lbu     t3, 0(t3)
    bnez    t3, 8f
    ld      t0, 8(sp)
    beqz    t0, 2f
    API_LIT api_p_comma
2:  li      t0, 1
    sd      t0, 8(sp)
    API_LIT api_ch_root
    ld      t0, ApiView_val_state(s4)
    ld      t1, Store_blocks(t0)
    add     t1, t0, t1
    ld      t2, 0(sp)
    li      t3, BlockNode__mem
    mul     t2, t2, t3
    add     a0, t1, t2
    sd      a0, 16(sp)
    li      a1, 32
    call    api_qhex
    API_LIT api_q_slot
    ld      t0, 16(sp)
    ld      a0, BlockNode_slot(t0)
    call    api_qdec
    API_LIT api_ch_optimistic
    ld      t0, 16(sp)
    ld      t0, BlockNode_payload_status(t0)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    a0, t0
    call    api_bool
    API_LIT api_end1
8:  ld      t0, 0(sp)
    addi    t0, t0, 1
    sd      t0, 0(sp)
    j       1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION api_heads_body

/*
 * L1: the body of getDebugForkChoice (beacon-api.md): {"justified_checkpoint":…,"finalized_checkpoint":…,
 * "fork_choice_nodes":[…]} of the store at ApiView_val_state of the view s4, each node's weight at
 * ApiView_weights. Locals: the index, the node.
 */
LOCAL_FUNCTION api_fork_choice_body
    FRAME 16
    API_LIT api_fc_justified
    ld      a0, ApiView_val_state(s4)
    addi    a0, a0, Store_justified_checkpoint
    call    api_checkpoint
    API_LIT api_fc_finalized
    ld      a0, ApiView_val_state(s4)
    addi    a0, a0, Store_finalized_checkpoint
    call    api_checkpoint
    API_LIT api_fc_nodes
    sd      zero, 0(sp)
1:  ld      t0, ApiView_val_state(s4)
    ld      t1, (Store_blocks + 8)(t0)
    ld      t2, 0(sp)
    bgeu    t2, t1, 9f
    beqz    t2, 2f
    API_LIT api_p_comma
2:  ld      t0, ApiView_val_state(s4)
    ld      t1, Store_blocks(t0)
    add     t1, t0, t1
    ld      t2, 0(sp)
    li      t3, BlockNode__mem
    mul     t2, t2, t3
    add     t1, t1, t2
    sd      t1, 8(sp)
    API_LIT api_fc_slot
    ld      t0, 8(sp)
    ld      a0, BlockNode_slot(t0)
    call    api_qdec
    API_LIT api_fc_block_root
    ld      a0, 8(sp)
    li      a1, 32
    call    api_qhex
    API_LIT api_h_parent
    ld      a0, 8(sp)
    addi    a0, a0, BlockNode_parent_root
    li      a1, 32
    call    api_qhex
    API_LIT api_fc_justified_epoch
    ld      t0, 8(sp)
    ld      a0, BlockNode_justified_checkpoint(t0)   # its epoch, the Checkpoint's first field
    call    api_qdec
    API_LIT api_fc_finalized_epoch
    ld      t0, 8(sp)
    ld      a0, BlockNode_finalized_epoch(t0)
    call    api_qdec
    API_LIT api_fc_weight
    LDQ     t0, s4, ApiView_weights
    ld      t1, 0(sp)
    slli    t1, t1, 3
    add     t0, t0, t1
    ld      a0, 0(t0)
    call    api_qdec
    API_LIT api_fc_validity
    ld      t0, 8(sp)
    ld      t0, BlockNode_payload_status(t0)
    li      t1, PAYLOAD_STATUS_NOT_VALIDATED
    beq     t0, t1, 3f
    li      t1, PAYLOAD_STATUS_INVALIDATED
    beq     t0, t1, 4f
    API_LIT api_fc_valid
    j       5f
3:  API_LIT api_fc_optimistic
    j       5f
4:  API_LIT api_fc_invalid
5:  API_LIT api_fc_hash
    ld      a0, 8(sp)
    addi    a0, a0, BlockNode_block_hash
    li      a1, 32
    call    api_qhex
    API_LIT api_end1
    ld      t0, 0(sp)
    addi    t0, t0, 1
    sd      t0, 0(sp)
    j       1b
9:  API_LIT api_v_end
    UNFRAME 16
END_FUNCTION api_fork_choice_body

# ,"canonical":…,"header":{"message":{"slot":…,"proposer_index":…,"parent_root":…,"state_root":…,"body_root":…},"signature":…
# of the slot a0, canonical a2, and at a1 the header's proposer_index, parent_root, state_root,
# body_root and signature, in that order. Locals: a0, a1, a2.
LOCAL_FUNCTION api_header_json
    FRAME 32
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    API_LIT api_h_canonical
    ld      a0, 16(sp)
    call    api_bool
    API_LIT api_h_slot
    ld      a0, 0(sp)
    call    api_qdec
    API_LIT api_h_proposer
    ld      t0, 8(sp)
    ld      a0, 0(t0)
    call    api_qdec
    API_LIT api_h_parent
    ld      a0, 8(sp)
    addi    a0, a0, ApiView_parent_root - ApiView_proposer_index
    li      a1, 32
    call    api_qhex
    API_LIT api_h_state
    ld      a0, 8(sp)
    addi    a0, a0, ApiView_state_root - ApiView_proposer_index
    li      a1, 32
    call    api_qhex
    API_LIT api_h_body
    ld      a0, 8(sp)
    addi    a0, a0, ApiView_body_root - ApiView_proposer_index
    li      a1, 32
    call    api_qhex
    API_LIT api_h_signature
    ld      a0, 8(sp)
    addi    a0, a0, ApiView_signature - ApiView_proposer_index
    li      a1, 96
    call    api_qhex
    UNFRAME 32
END_FUNCTION api_header_json
.if ApiView_parent_root - ApiView_proposer_index != 8 || ApiView_state_root - ApiView_proposer_index != 40 || ApiView_body_root - ApiView_proposer_index != 72 || ApiView_signature - ApiView_proposer_index != 104
.error "api_header_json reads the fields of a SignedBeaconBlockHeader after its slot"
.endif

# getBlockHeaders' JSON, as api_stream_json: with s3, the address of an item's header (its slot,
# then the fields api_header_json reads), the item {"root":…,"canonical":…,"header":…}, its root at
# byte 0 of the entry s4's cursor and canonical bit 0 of its member, after , when API_STREAM_ITEMS
# is set; then API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event s5. With s3 = 0: ]}. a0 = 1
# when the answer is whole, else 0.
LOCAL_FUNCTION api_headers_json
    FRAME 0
    bnez    s3, 1f
    API_LIT api_v_end
    li      a0, 1
    UNFRAME 0
1:  ld      t0, (NodeEvent_api + 8)(s5)
    li      t1, API_STREAM_ITEMS
    and     t0, t0, t1
    beqz    t0, 2f
    API_LIT api_p_comma
2:  API_LIT api_ch_root
    addi    a0, s4, NodeApi_cursor
    li      a1, 32
    call    api_qhex
    ld      a0, 0(s3)
    addi    a1, s3, 8
    ld      a2, NodeApi_member(s4)
    andi    a2, a2, 1
    call    api_header_json
    API_LIT api_end2
    ld      t0, (NodeEvent_api + 8)(s5)
    li      t1, API_STREAM_ITEMS | API_STREAM_ITEM_DONE
    or      t0, t0, t1
    sd      t0, (NodeEvent_api + 8)(s5)
    li      a0, 0
    UNFRAME 0
END_FUNCTION api_headers_json

/*
 * L2: a0 = the base58btc text of the a1 bytes at a0 (at most 48), written at a2: a 1 for each
 * leading zero byte, then the digits. a3: a work area of 72 bytes. s2 the bytes, s3 their count,
 * s4 the text, s5 the work area, s6 the leading zero bytes.
 */
LOCAL_FUNCTION api_base58
    ENTER 0
    mv      s2, a0
    mv      s3, a1
    mv      s4, a2
    mv      s5, a3
    li      s6, 0                           # the leading zero bytes
1:  bgeu    s6, s3, 2f
    add     t0, s2, s6
    lbu     t0, 0(t0)
    bnez    t0, 2f
    addi    s6, s6, 1
    j       1b
2:  li      t1, 0                           # the digits so far, least significant at s5 + 71
    mv      t2, s6
    li      a4, 58
3:  bgeu    t2, s3, 6f                      # each byte: digits * 256 + byte
    add     t3, s2, t2
    lbu     t3, 0(t3)
    li      t4, 0
4:  bgeu    t4, t1, 5f
    li      t0, 71
    sub     t0, t0, t4
    add     t0, s5, t0
    lbu     t5, 0(t0)
    slli    t5, t5, 8
    add     t3, t3, t5
    remu    t5, t3, a4
    divu    t3, t3, a4
    sb      t5, 0(t0)
    addi    t4, t4, 1
    j       4b
5:  beqz    t3, 51f
    remu    t5, t3, a4
    divu    t3, t3, a4
    li      t0, 71
    sub     t0, t0, t1
    add     t0, s5, t0
    sb      t5, 0(t0)
    addi    t1, t1, 1
    j       5b
51: addi    t2, t2, 1
    j       3b
6:  li      a0, 0                           # the text: the ones, then the digits
    ADDRESS t3, api_base58_digits
7:  beqz    s6, 8f
    lbu     t0, 0(t3)
    add     t4, s4, a0
    sb      t0, 0(t4)
    addi    a0, a0, 1
    addi    s6, s6, -1
    j       7b
8:  beqz    t1, 9f
    li      t0, 72
    sub     t0, t0, t1
    add     t0, s5, t0
    lbu     t0, 0(t0)
    add     t0, t3, t0
    lbu     t0, 0(t0)
    add     t4, s4, a0
    sb      t0, 0(t4)
    addi    a0, a0, 1
    addi    t1, t1, -1
    j       8b
9:  LEAVE 0
END_FUNCTION api_base58

# A peer of getPeers and getPeer (beacon-api.md): {"peer_id":…,"enr":null,"last_seen_p2p_address":…,
# "state":"connected","direction":…} of the NodePeer a0. Locals: the peer, the text's length, an
# index, the text (72 bytes), base58's work area (72 bytes).
LOCAL_FUNCTION api_peer_item
    FRAME 176
    sd      a0, 0(sp)
    addi    a0, a0, NodePeer_id
    ld      t0, 0(sp)
    ld      a1, NodePeer_id_len(t0)
    addi    a2, sp, 24
    addi    a3, sp, 96
    call    api_base58
    sd      a0, 8(sp)
    API_LIT api_pe_open
    addi    a0, sp, 24
    ld      a1, 8(sp)
    call    api_put
    API_LIT api_pe_enr
    ld      t0, 0(sp)
    ld      t1, NodePeer_address(t0)        # the family
    li      t2, 6
    beq     t1, t2, 3f
    # IPv4: 4 bytes in decimal, . between
    API_LIT api_pe_ip4
    sd      zero, 16(sp)
1:  ld      t0, 0(sp)
    ld      t1, 16(sp)
    add     t0, t0, t1
    lbu     a0, (NodePeer_address + 16)(t0)
    call    api_dec
    ld      t1, 16(sp)
    addi    t1, t1, 1
    sd      t1, 16(sp)
    li      t2, 4
    bgeu    t1, t2, 5f
    API_LIT api_pe_dot
    j       1b
    # IPv6: 8 groups of 16 bits, lower case hex with no leading zeros, : between
3:  API_LIT api_pe_ip6
    sd      zero, 16(sp)
4:  ld      t0, 0(sp)
    ld      t1, 16(sp)
    slli    t1, t1, 1
    add     t0, t0, t1
    lbu     t2, (NodePeer_address + 16)(t0)
    lbu     t3, (NodePeer_address + 17)(t0)
    slli    t2, t2, 8
    or      a0, t2, t3
    call    api_hex16
    ld      t1, 16(sp)
    addi    t1, t1, 1
    sd      t1, 16(sp)
    li      t2, 8
    bgeu    t1, t2, 5f
    API_LIT api_pe_colon
    j       4b
5:  ld      t0, 0(sp)                       # the transport and its port
    ld      t1, NodePeer_transport(t0)
    li      t2, LIBP2P_QUIC
    beq     t1, t2, 6f
    API_LIT api_pe_tcp
    ld      t0, 0(sp)
    ld      a0, (NodePeer_address + 8)(t0)
    call    api_dec
    j       7f
6:  API_LIT api_pe_udp
    ld      t0, 0(sp)
    ld      a0, (NodePeer_address + 8)(t0)
    call    api_dec
    API_LIT api_pe_quic
7:  API_LIT api_pe_p2p
    addi    a0, sp, 24
    ld      a1, 8(sp)
    call    api_put
    API_LIT api_pe_state
    ld      t0, 0(sp)
    ld      t1, NodePeer_direction(t0)
    li      t2, LIBP2P_OUTBOUND
    beq     t1, t2, 8f
    API_LIT api_pe_inbound
    UNFRAME 176
8:  API_LIT api_pe_outbound
    UNFRAME 176
END_FUNCTION api_peer_item

# The lower case hex digits of the 16 bits a0, with no leading zeros, join the response. Locals: a0, a shift.
LOCAL_FUNCTION api_hex16
    FRAME 16
    sd      a0, 0(sp)
    li      t1, 12
1:  beqz    t1, 2f                          # the leading zero digits but the last
    srl     t2, a0, t1
    bnez    t2, 2f
    addi    t1, t1, -4
    j       1b
2:  sd      t1, 8(sp)
3:  ld      t0, 0(sp)
    ld      t1, 8(sp)
    srl     t0, t0, t1
    andi    t0, t0, 15
    ADDRESS a0, api_hex
    add     a0, a0, t0
    li      a1, 1
    call    api_put
    ld      t1, 8(sp)
    beqz    t1, 9f
    addi    t1, t1, -4
    sd      t1, 8(sp)
    j       3b
9:  UNFRAME 16
END_FUNCTION api_hex16

# getPeers' body (beacon-api.md): {"data":[<peer>,…],"meta":{"count":…}} of the NodePeers of the
# Node at ApiView_node of the view s4 whose state and direction are in the sets at
# ApiView_peer_states and ApiView_peer_directions. Locals: the index, the count, the peer.
LOCAL_FUNCTION api_peers_body
    FRAME 32
    API_LIT api_p_data
    sd      zero, 0(sp)
    sd      zero, 8(sp)
1:  LDQ     t3, s4, ApiView_node
    PART    t0, t1, t3, Node_peers
    ld      t2, 0(sp)
    bgeu    t2, t1, 9f
    li      t4, NodePeer__mem
    mul     t4, t2, t4
    add     a0, t0, t4
    addi    t2, t2, 1
    sd      t2, 0(sp)
    LDQ     t0, s4, ApiView_peer_states     # connected
    andi    t0, t0, 1 << API_PEER_CONNECTED
    beqz    t0, 1b
    ld      t1, NodePeer_direction(a0)
    LDQ     t0, s4, ApiView_peer_directions
    srl     t0, t0, t1
    andi    t0, t0, 1
    beqz    t0, 1b
    sd      a0, 16(sp)
    ld      t0, 8(sp)
    beqz    t0, 2f
    API_LIT api_p_comma
2:  ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    ld      a0, 16(sp)
    call    api_peer_item
    j       1b
9:  API_LIT api_pe_meta
    ld      a0, 8(sp)
    call    api_dec
    API_LIT api_end2
    UNFRAME 32
END_FUNCTION api_peers_body
.if API_DIRECTION_INBOUND != LIBP2P_INBOUND || API_DIRECTION_OUTBOUND != LIBP2P_OUTBOUND
.error "api_peers_body: the direction bits are the libp2p directions"
.endif

# (route a0) -> a0: the NodePeer whose peer ID's base58btc text is the route's peer_id, or 0. s1 the
# node. Locals: the route, the index, the text (72 bytes), base58's work area (72 bytes).
LOCAL_FUNCTION node_api_find_peer
    FRAME 176
    sd      a0, 0(sp)
    sd      zero, 8(sp)
1:  PART    t0, t1, s1, Node_peers
    ld      t2, 8(sp)
    bgeu    t2, t1, 8f
    li      t3, NodePeer__mem
    mul     t3, t2, t3
    add     t3, t0, t3
    addi    t2, t2, 1
    sd      t2, 8(sp)
    addi    a0, t3, NodePeer_id
    ld      a1, NodePeer_id_len(t3)
    addi    a2, sp, 24
    addi    a3, sp, 96
    call    api_base58
    ld      t0, 0(sp)
    PART    t1, t2, t0, ApiRoute_peer_id
    bne     a0, t2, 1b
    li      t3, 0
2:  bgeu    t3, t2, 3f
    add     t4, sp, t3
    lbu     t4, 24(t4)
    add     t5, t1, t3
    lbu     t5, 0(t5)
    bne     t4, t5, 1b
    addi    t3, t3, 1
    j       2b
3:  PART    t0, t1, s1, Node_peers          # that peer
    ld      t2, 8(sp)
    addi    t2, t2, -1
    li      t3, NodePeer__mem
    mul     t3, t2, t3
    add     a0, t0, t3
    UNFRAME 176
8:  li      a0, 0
    UNFRAME 176
END_FUNCTION node_api_find_peer

/*
 * The body of getSyncCommitteeDuties (beacon-api.md): {"execution_optimistic":…,"data":[{"pubkey":…,
 * "validator_index":…,"validator_sync_committee_indices":[…]},…]} of the ValidatorRef items at
 * ApiView_sd_ids of the view s4, each by its places in the committee at ApiView_sync_out, the pubkeys
 * those of the state at ApiView_val_state. Locals: the item's index, the items written, the
 * validator, the place, its places written.
 */
LOCAL_FUNCTION api_sync_duties_body
    FRAME 48
    API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_v_list
    sd      zero, 0(sp)
    sd      zero, 8(sp)
1:  LDQ     t0, s4, ApiView_sd_ids          # each item: a validator index the state has
    ld      t1, 16(t0)
    srli    t1, t1, 6
    ld      t2, 0(sp)
    bgeu    t2, t1, 9f
    addi    t3, t2, 1
    sd      t3, 0(sp)
    ld      t1, 8(t0)
    add     t1, t0, t1
    slli    t2, t2, 6
    add     t1, t1, t2
    ld      t2, 8(t1)
    sd      t2, 16(sp)
    ld      t0, ApiView_val_state(s4)
    PART    t3, t1, t0, NODE_STATE_VALIDATORS
    bgeu    t2, t1, 1b
    sd      zero, 24(sp)                    # its places in the committee
    sd      zero, 32(sp)
2:  ld      t1, 24(sp)
    li      t2, SYNC_COMMITTEE_SIZE
    bgeu    t1, t2, 7f
    addi    t2, t1, 1
    sd      t2, 24(sp)
    LDQ     t0, s4, ApiView_sync_out
    slli    t1, t1, 3
    add     t0, t0, t1
    ld      t0, 0(t0)
    ld      t1, 16(sp)
    bne     t0, t1, 2b
    ld      t0, 32(sp)
    bnez    t0, 5f
    ld      t0, 8(sp)                       # the first place: the item's head
    beqz    t0, 3f
    API_LIT api_p_comma
3:  ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    API_LIT api_u_pubkey
    ld      t0, ApiView_val_state(s4)
    PART    a0, t1, t0, NODE_STATE_VALIDATORS
    ld      t1, 16(sp)
    slli    t1, t1, 7                       # NODE_VALIDATOR_MEM: the pubkey first
    add     a0, a0, t1
    li      a1, 48
    call    api_qhex
    API_LIT api_u_index
    ld      a0, 16(sp)
    call    api_qdec
    API_LIT api_sd_indices
    j       6f
5:  API_LIT api_p_comma
6:  ld      t0, 32(sp)
    addi    t0, t0, 1
    sd      t0, 32(sp)
    ld      a0, 24(sp)
    addi    a0, a0, -1
    call    api_qdec
    j       2b
7:  ld      t0, 32(sp)                      # places written: the item's end
    beqz    t0, 1b
    API_LIT api_v_end
    j       1b
9:  API_LIT api_v_end
    UNFRAME 48
END_FUNCTION api_sync_duties_body
.if NODE_VALIDATOR_MEM != 128
.error "api_sync_duties_body reads a pubkey at index * 128"
.endif

/*
 * The bodies of getStateRandao, getEpochSyncCommittees and getProposerLookahead (beacon-api.md), as
 * api_body: a0 its locals (flags at 8), s10 the kind, s4 the view. Locals: those, an index.
 */
LOCAL_FUNCTION api_state_read_body
    FRAME 16
    sd      a0, 0(sp)
    li      t0, API_OP_GET_PROPOSER_LOOKAHEAD
    beq     s10, t0, 30f
    # {"execution_optimistic":…,"finalized":…,"data":{
    API_LIT api_x_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, ApiView_head_finalized(s4)
    call    api_bool
    API_LIT api_x_data
    li      t0, API_OP_GET_STATE_RANDAO
    bne     s10, t0, 10f
    # "randao":…}}
    API_LIT api_r_randao
    ADDQ    a0, s4, ApiView_randao
    li      a1, 32
    call    api_qhex
    API_LIT api_end2
    UNFRAME 16
    # "validators":[…],"validator_aggregates":[[…],…]}}
10: API_LIT api_s_validators
    sd      zero, 8(sp)
11: ld      t0, 8(sp)
    li      t1, SYNC_COMMITTEE_SIZE
    bgeu    t0, t1, 13f
    beqz    t0, 12f
    API_LIT api_p_comma
12: ld      t0, 8(sp)
    LDQ     t1, s4, ApiView_sync_out
    slli    t0, t0, 3
    add     t1, t1, t0
    ld      a0, 0(t1)
    call    api_qdec
    ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    j       11b
13: API_LIT api_s_aggregates
    sd      zero, 8(sp)
14: ld      t0, 8(sp)
    li      t1, SYNC_COMMITTEE_SIZE
    bgeu    t0, t1, 18f
    andi    t1, t0, SYNC_COMMITTEE_SIZE / SYNC_COMMITTEE_SUBNET_COUNT - 1
    bnez    t1, 16f
    beqz    t0, 15f
    API_LIT api_p_rbracket
    API_LIT api_p_comma
15: API_LIT api_p_lbracket
    j       17f
16: API_LIT api_p_comma
17: ld      t0, 8(sp)
    LDQ     t1, s4, ApiView_sync_out
    slli    t0, t0, 3
    add     t1, t1, t0
    ld      a0, 0(t1)
    call    api_qdec
    ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    j       14b
18: API_LIT api_p_rbracket
    API_LIT api_s_end
    UNFRAME 16
30: ld      t0, 0(sp)                       # getProposerLookahead: SSZ, its bytes
    ld      t0, 8(t0)
    andi    t0, t0, API_R_SSZ
    beqz    t0, 31f
    ADDQ    a0, s4, ApiView_lookahead
    li      a1, 8 * API_LOOKAHEAD_SLOTS
    call    api_put
    UNFRAME 16
    # {"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[…]}
31: API_LIT api_j_version
    ld      a0, ApiView_fork(s4)
    call    api_fork_name
    API_LIT api_j_optimistic
    ld      a0, ApiView_is_optimistic(s4)
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, ApiView_head_finalized(s4)
    call    api_bool
    API_LIT api_v_list
    sd      zero, 8(sp)
32: ld      t0, 8(sp)
    li      t1, API_LOOKAHEAD_SLOTS
    bgeu    t0, t1, 34f
    beqz    t0, 33f
    API_LIT api_p_comma
33: ld      t0, 8(sp)
    ADDQ    t1, s4, ApiView_lookahead
    slli    t0, t0, 3
    add     t1, t1, t0
    ld      a0, 0(t1)
    call    api_qdec
    ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    j       32b
34: API_LIT api_v_end
    UNFRAME 16
END_FUNCTION api_state_read_body

/*
 * (view a0, out a1, status a2, body a3, flags a4) -> a0: the HTTP response of beacon-api.md,
 * Common rules, into the ByteList out, its count set: the status line, its fields, then the body
 * of the kind body (0 none, API_BODY_ERROR, or an API_OP_*) from the ApiView view. flags:
 * API_R_CLOSE, API_R_KEEP, API_R_NO_REASON, and the allow bits from bit 8. a0 = LANTERN_OK, or
 * LANTERN_BUFFER_TOO_SMALL when out has too little room. s5 out. Locals: L status, L+8 flags,
 * L+16 the body's bytes.
 */
LOCAL_FUNCTION api_respond
    ENTER 32
    mv      s4, a0
    mv      s5, a1
    sd      a2, (L + 0)(sp)
    sd      a4, (L + 8)(sp)
    mv      s10, a3
    li      s7, 0                           # the body's bytes
    li      s6, 0
    li      s9, 0
    beqz    s10, 1f
    addi    a0, sp, L
    call    api_body
1:  sd      s6, (L + 16)(sp)
    li      s7, 1                           # the response
    addi    s6, s5, 24
    ld      t0, 0(s5)
    add     s8, s5, t0
    # HTTP/1.1 <code> <reason> CRLF
    API_LIT api_http
    ld      a0, (L + 0)(sp)
    call    api_dec
    API_LIT api_sp
    ld      t0, (L + 8)(sp)
    andi    t0, t0, API_R_NO_REASON
    bnez    t0, 2f
    ld      a0, (L + 0)(sp)
    call    api_code
    li      a1, 8
    call    api_code_text
2:  API_LIT api_crlf
    ld      t0, (L + 16)(sp)
    beqz    t0, 3f
    ld      t0, (L + 8)(sp)
    andi    t0, t0, API_R_SSZ
    bnez    t0, 21f
    API_LIT api_type
    j       22f
21: API_LIT api_octet
22: ld      t0, (L + 8)(sp)                 # API_R_VERSION: Eth-Consensus-Version of the view's fork
    andi    t0, t0, API_R_VERSION
    beqz    t0, 3f
    API_LIT api_version
    ld      a0, ApiView_fork(s4)
    call    api_fork_name
    API_LIT api_crlf
3:  API_LIT api_length
    ld      a0, (L + 16)(sp)
    call    api_dec
    API_LIT api_crlf
    ld      t0, (L + 0)(sp)
    li      t1, 405
    bne     t0, t1, 5f
    # Allow: GET, POST or GET, POST
    API_LIT api_allow
    ld      t0, (L + 8)(sp)
    andi    t0, t0, 0x100
    beqz    t0, 4f
    API_LIT api_get
    ld      t0, (L + 8)(sp)
    andi    t0, t0, 0x200
    beqz    t0, 41f
    API_LIT api_comma
4:  ld      t0, (L + 8)(sp)
    andi    t0, t0, 0x200
    beqz    t0, 41f
    API_LIT api_post
41: API_LIT api_crlf
5:  ld      t0, (L + 8)(sp)
    andi    t1, t0, API_R_CLOSE
    beqz    t1, 6f
    API_LIT api_close
    j       7f
6:  andi    t1, t0, API_R_KEEP
    beqz    t1, 7f
    API_LIT api_keep
7:  API_LIT api_crlf
    beqz    s10, 8f
    addi    a0, sp, L
    call    api_body
8:  bnez    s9, 9f
    addi    t0, s5, 24
    sub     t0, s6, t0
    li      t1, 24
    sd      t1, 8(s5)
    sd      t0, 16(s5)
    li      a0, LANTERN_OK
    LEAVE 32
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION api_respond

/*
 * The values of the ApiView a0 that the node, s1, and the store, s2, give (beacon-api.md, Common
 * rules); the header and the checkpoints zero. Locals: the view.
 */
LOCAL_FUNCTION node_api_view
    FRAME 16
    sd      a0, 0(sp)
    li      a1, ApiView__size
    call    lantern_zero
    ld      a0, 0(sp)
    ld      t0, Store_genesis_time_ms(s2)
    li      t1, 1000
    divu    t0, t0, t1
    sd      t0, ApiView_genesis_time(a0)
    addi    t0, a0, ApiView_genesis_validators_root
    addi    t1, s1, Node_genesis_validators_root
    COPY32  t0, t1
    LDQ     t0, s1, Node_config + CONFIG_GENESIS_FORK_VERSION
    sd      t0, ApiView_genesis_fork_version(a0)
    addi    t0, s1, Node_config
    sd      t0, ApiView_config(a0)
    addi    a0, s1, Node_head_root          # the head
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 1f
    ld      a0, 0(sp)
    ld      t0, NodeBlock_slot(a1)
    sd      t0, ApiView_head_slot(a0)
    ld      t0, NodeBlock_payload_status(a1)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t0, t0
    sd      t0, ApiView_is_optimistic(a0)
    addi    t0, a0, ApiView_head_root
    COPY32  t0, a1
1:  mv      a0, s2                          # the clock, sync, peers, MetaData
    call    node_store_slot
    ld      t3, 0(sp)
    sd      a0, ApiView_current_slot(t3)
    addi    a1, s1, Node_config
    call    node_fork
    ld      t3, 0(sp)
    sd      a0, ApiView_fork(t3)
    ld      t0, Node_flags(s1)
    srli    t1, t0, 3                       # NODE_FLAG_SYNCING
    andi    t1, t1, 1
    sd      t1, ApiView_is_syncing(t3)
    srli    t1, t0, 9                       # NODE_FLAG_EL_OFFLINE
    andi    t1, t1, 1
    sd      t1, ApiView_el_offline(t3)
    ld      t0, (Node_peers + 8)(s1)
    sd      t0, ApiView_peers(t3)
    ld      t0, Node_metadata_seq(s1)
    sd      t0, ApiView_seq_number(t3)
    ld      t0, Node_attnets(s1)
    sd      t0, ApiView_attnets(t3)
    LDQ     t0, s1, Node_config + CONFIG_CUSTODY_REQUIREMENT
    sd      t0, ApiView_custody_group_count(t3)
    addi    a0, t3, ApiView_peer_id         # the identity's texts
    ADDQ    a1, s1, Node_api_identity
    li      a2, API_IDENTITY_SIZE
    call    lantern_copy
    ld      a0, 0(sp)
    call    api_view_finalized
    UNFRAME 16
END_FUNCTION node_api_view

/* ApiView_head_finalized of the view a0: 1 when its head_root is the root of the store s2's finalized checkpoint. Uses t0-t2, a6, a7. */
LOCAL_FUNCTION api_view_finalized
    UNWIND_END_PROLOGUE
    addi    t0, a0, ApiView_head_root
    addi    t1, s2, (Store_finalized_checkpoint + 8)
    li      t2, 0
    NE32    t0, t1, 1f
    li      t2, 1
1:  sd      t2, ApiView_head_finalized(a0)
    ret
END_FUNCTION api_view_finalized

/*
 * One NODE_ACT_API_SEND of the connection a0, with last 1, at the end of the actions s6: the
 * response of api_respond with the view a1, the status a2, the body a3 and the flags a4; when it
 * does not fit, the error 500. With API_R_CLOSE, then a NODE_ACT_API_CLOSE. Locals: the
 * connection, the flags, the action, its size.
 */
LOCAL_FUNCTION node_api_send
    FRAME 32
    sd      a0, 0(sp)
    sd      a4, 8(sp)
    ld      t0, 8(s6)                       # the action, and the room after it
    ld      t1, 16(s6)
    add     t2, s6, t0
    add     t2, t2, t1
    sd      t2, 16(sp)
    ld      t3, 0(s6)
    sub     t3, t3, t0
    sub     t3, t3, t1
    addi    t3, t3, -32
    andi    t3, t3, -8
    sd      t3, 32(t2)                      # its ByteList at 32
    mv      a0, a1
    addi    a1, t2, 32
    call    api_respond
    beqz    a0, 1f
    li      a0, 0                           # no room: the error 500
    ld      a1, 16(sp)
    addi    a1, a1, 32
    li      a2, 500
    li      a3, API_BODY_ERROR
    ld      a4, 8(sp)
    andi    a4, a4, (API_R_CLOSE | API_R_KEEP)
    call    api_respond
1:  ld      t2, 16(sp)
    ld      t0, 48(t2)                      # the count; the size to a multiple of 8, zero bytes after
    addi    t1, t0, (56 + 7)
    andi    t1, t1, -8
    sd      t1, 24(sp)
    add     a0, t2, t0
    addi    a0, a0, 56
    addi    a1, t1, -56
    sub     a1, a1, t0
    call    lantern_zero
    ld      t2, 16(sp)
    ld      t1, 24(sp)
    sd      t1, 0(t2)
    li      t0, NODE_ACT_API_SEND
    sd      t0, 8(t2)
    ld      t0, 0(sp)
    sd      t0, 16(t2)
    li      t0, 1
    sd      t0, 24(t2)
    addi    t0, t1, -32
    sd      t0, 32(t2)
    ld      t0, 16(s6)
    add     t0, t0, t1
    sd      t0, 16(s6)
    ld      t0, 8(sp)
    andi    t0, t0, API_R_CLOSE
    beqz    t0, 9f
    li      a0, NODE_ACT_API_CLOSE
    li      a1, NODE_ACT_API_CLOSE_SIZE
    call    node_act
    ld      t0, 0(sp)
    sd      t0, 16(a0)
9:  UNFRAME 32
END_FUNCTION node_api_send

/*
 * The NODE_EV_API or NODE_EV_API_IDENTITY a0, whose ByteList at 24 is inside it (node.md,
 * NodeEvent): a0 = 0 when it keeps its rules, else 1; a1 = the scratch it needs. Uses t0-t6.
 */
LOCAL_FUNCTION node_api_check
    UNWIND_END_PROLOGUE
    ld      t0, 8(a0)
    ld      t1, (NodeEvent_bytes + 16)(a0)  # the count
    addi    t2, a0, (NodeEvent_bytes + 24)  # the bytes
    li      t3, NODE_EV_API_IDENTITY
    bne     t0, t3, 5f
    li      t3, API_IDENTITY_SIZE           # IDENTITY: each text in its room, its bytes 0x21 to 0x7e but " and \
    bne     t1, t3, 8f
    ADDRESS t3, node_api_rooms
1:  ld      t4, 0(t3)
    addi    t3, t3, 8
    beqz    t4, 4f
    ld      t5, 0(t2)
    addi    t2, t2, 8
    bgtu    t5, t4, 8f
    li      t6, 0
2:  bgeu    t6, t5, 3f
    add     t0, t2, t6
    lbu     t0, 0(t0)
    addi    t1, t0, -0x21
    li      a1, (0x7e - 0x21)
    bgtu    t1, a1, 8f
    li      a1, 0x22
    beq     t0, a1, 8f
    li      a1, 0x5c
    beq     t0, a1, 8f
    addi    t6, t6, 1
    j       2b
3:  add     t2, t2, t4
    j       1b
4:  li      a0, 0
    li      a1, 0
    ret
5:  ld      t3, 16(a0)                      # API: a connection, not 0
    beqz    t3, 8f
    li      t3, HTTP_REQUEST_FIXED          # an HttpRequest of the count's size
    bltu    t1, t3, 8f
    andi    t3, t1, 7
    bnez    t3, 8f
    ld      t3, HttpRequest_size(t2)
    bne     t3, t1, 8f
    ld      t3, HttpRequest_status(t2)
    bnez    t3, 7f
    li      t4, HttpRequest_path            # with status 0, each part inside
6:  li      t3, HTTP_REQUEST_FIXED
    bgeu    t4, t3, 7f
    add     t3, t2, t4
    ld      t5, 0(t3)
    ld      t6, 8(t3)
    bgtu    t5, t1, 8f
    sub     t5, t1, t5
    bgtu    t6, t5, 8f
    addi    t4, t4, 16
    j       6b
7:  li      a1, NODE_API_SCRATCH
    ld      t3, HttpRequest_status(t2)
    bnez    t3, 71f
    ld      t3, (HttpRequest_query + 8)(t2)
    slli    t3, t3, 2
    add     a1, a1, t3
    ld      t3, (HttpRequest_body + 8)(t2)  # 16 bytes per byte of the body: its ids
    slli    t3, t3, 4
    add     a1, a1, t3
71: li      a0, 0
    ret
8:  li      a0, 1
    li      a1, 0
    ret
END_FUNCTION node_api_check

/* a0 = the NODE_DB_REF of the Db's record of the block at a0, or 0. Locals: the slot. */
LOCAL_FUNCTION node_api_db_ref
    FRAME 16
    ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 9f
    mv      a1, a0
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    mv      a2, sp
    call    lantern_db_find_root
    ld      a0, 0(sp)
    li      t0, -1
    beq     a0, t0, 9f
    call    node_db_block
    UNFRAME 16
9:  li      a0, 0
    UNFRAME 16
END_FUNCTION node_api_db_ref

/*
 * The answer to the NODE_EV_API a0 (node.md, lantern_node_step): s1 the node, s2 the store, s5
 * the scratch, s6 the actions. s3 the event, s4 its HttpRequest, s7 the ApiRoute, s8 the ApiView,
 * s9 the connection, s10 the flags of api_respond. Locals: L the scratch's size.
 */
LOCAL_FUNCTION node_api_event
    ENTER 16
    mv      s3, a0
    ld      s9, 16(s3)
    ld      t0, (NodeEvent_bytes + 8)(s3)
    addi    s4, s3, NodeEvent_bytes
    add     s4, s4, t0
    li      s10, 0                          # close after a fault or with close; HTTP/1.0 kept open says so
    ld      t0, HttpRequest_status(s4)
    ld      t1, HttpRequest_close(s4)
    or      t0, t0, t1
    beqz    t0, 1f
    li      s10, API_R_CLOSE
    j       2f
1:  ld      t0, HttpRequest_version(s4)
    li      t1, 10
    bne     t0, t1, 2f
    li      s10, API_R_KEEP
2:  ld      t0, 0(s5)                       # the ApiView, then the ApiRoute, at the end of scratch
    sd      t0, (L + 0)(sp)
    mv      a0, s3
    call    node_api_check
    ld      t0, (L + 0)(sp)
    sub     t0, t0, a1
    sd      t0, 0(s5)
    add     s8, s5, t0
    ADDQ    s7, s8, ApiView__size
    li      t0, ApiView__size
    sub     t0, a1, t0
    sd      t0, 0(s7)
    mv      a0, s8
    call    node_api_view
    ld      a2, HttpRequest_status(s4)      # a fault of the request: its status
    bnez    a2, 80f
    mv      a0, s4
    mv      a1, s7
    call    lantern_api_route
    li      t0, LANTERN_INVALID_ROUTE
    bne     a0, t0, 3f
    ld      a2, ApiRoute_status(s7)
    ld      t0, ApiRoute_allow(s7)
    slli    t0, t0, 8
    or      s10, s10, t0
    j       80f
3:  li      a2, 500
    bnez    a0, 80f
    ld      a3, ApiRoute_op(s7)
    li      a2, 200
    li      t0, API_OP_GET_HEALTH
    bne     a3, t0, 4f
    ld      t0, ApiView_is_syncing(s8)      # health: 200, else 206 or syncing_status
    ld      t1, ApiView_is_optimistic(s8)
    or      t0, t0, t1
    ld      t1, ApiView_el_offline(s8)
    or      t0, t0, t1
    li      a3, 0
    beqz    t0, 81f
    li      a2, 206
    ld      t0, ApiRoute_present(s7)
    srli    t0, t0, API_PARAM_SYNCING_STATUS
    andi    t0, t0, 1
    beqz    t0, 81f
    ld      a2, ApiRoute_syncing_status(s7)
    ori     s10, s10, API_R_NO_REASON
    j       81f
4:  li      t0, API_OP_GET_NETWORK_IDENTITY
    beq     a3, t0, 81f
    li      t0, API_OP_GET_NODE_VERSION
    beq     a3, t0, 81f
    li      t0, API_OP_GET_SYNCING_STATUS
    beq     a3, t0, 81f
    li      t0, API_OP_GET_PEER_COUNT
    beq     a3, t0, 81f
    li      t0, API_OP_GET_PEERS
    beq     a3, t0, 56f
    li      t0, API_OP_GET_PEER
    beq     a3, t0, 55f
    li      t0, API_OP_GET_GENESIS
    beq     a3, t0, 81f
    li      t0, API_OP_GET_FORK_SCHEDULE
    beq     a3, t0, 81f
    li      t0, API_OP_GET_DEPOSIT_CONTRACT
    beq     a3, t0, 81f
    li      a2, 404
    andi    s3, s10, API_R_CLOSE            # s3: the answer flags of a work or a stream
    snez    s3, s3
    ld      t0, HttpRequest_version(s4)
    addi    t0, t0, -10
    seqz    t0, t0
    slli    t0, t0, 1
    or      s3, s3, t0
    li      t0, API_OP_GET_BLOCK_ROOT
    beq     a3, t0, 65f
    li      t0, API_OP_GET_BLOCK_HEADER
    beq     a3, t0, 65f
    li      t0, API_OP_GET_BLOCK_V2
    beq     a3, t0, 65f
    li      t0, API_OP_GET_BLOCK_ATTESTATIONS_V2
    beq     a3, t0, 65f
    li      t0, API_OP_GET_BLINDED_BLOCK
    beq     a3, t0, 65f
    li      t0, API_OP_GET_BLOB_SIDECARS
    beq     a3, t0, 65f
    li      t0, API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    beq     a3, t0, 65f
    li      t0, API_OP_GET_STATE_ROOT
    beq     a3, t0, 66f
    li      t0, API_OP_GET_STATE_FORK
    beq     a3, t0, 66f
    li      t0, API_OP_GET_STATE_FINALITY_CHECKPOINTS
    beq     a3, t0, 66f
    li      t0, API_OP_GET_STATE_RANDAO
    beq     a3, t0, 66f
    li      t0, API_OP_GET_EPOCH_SYNC_COMMITTEES
    beq     a3, t0, 66f
    li      t0, API_OP_GET_PROPOSER_LOOKAHEAD
    beq     a3, t0, 66f
    addi    t1, a3, -API_OP_GET_PENDING_CONSOLIDATIONS
    li      t0, 2
    bleu    t1, t0, 66f
    li      t0, API_OP_GET_SPEC
    beq     a3, t0, 67f
    li      t0, API_OP_GET_DEBUG_CHAIN_HEADS_V2
    beq     a3, t0, 67f
    li      t0, API_OP_GET_DEBUG_FORK_CHOICE
    beq     a3, t0, 67f
    li      t0, API_OP_GET_BLOCK_HEADERS
    beq     a3, t0, 57f
    li      t0, API_OP_GET_PROPOSER_DUTIES
    beq     a3, t0, 63f
    li      t0, API_OP_PRODUCE_ATTESTATION_DATA
    beq     a3, t0, 59f
    li      t0, API_OP_GET_ATTESTER_DUTIES
    beq     a3, t0, 58f
    li      t0, API_OP_GET_SYNC_COMMITTEE_DUTIES
    beq     a3, t0, 53f
    li      t0, API_OP_EVENTSTREAM
    beq     a3, t0, 61f
    li      t0, API_OP_GET_POOL_VOLUNTARY_EXITS
    beq     a3, t0, 68f
    li      t0, API_OP_GET_POOL_PROPOSER_SLASHINGS
    beq     a3, t0, 68f
    li      t0, API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    beq     a3, t0, 68f
    li      t0, API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES
    beq     a3, t0, 68f
    li      t0, API_OP_GET_POOL_ATTESTATIONS_V2
    beq     a3, t0, 68f
    mv      a0, a3
    call    node_submit_topic
    bnez    a0, 60f
    addi    t0, a3, -API_OP_GET_STATE_VALIDATORS   # the six validator operations and getEpochCommittees: a state
    li      t1, API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS
    bleu    t0, t1, 66f
    li      t0, API_OP_GET_STATE_V2
    bne     a3, t0, 7f
66: ld      t0, ApiRoute_id_kind(s7)        # a state root: a work finds its slot first
    li      t1, API_ID_ROOT
    bne     t0, t1, 69f
    mv      a0, s9
    mv      a1, s7
    mv      a2, s3
    call    node_api_lookup
    mv      a2, a0
    bnez    a0, 80f
    j       90f
69: mv      a0, s7                          # a state: its lookup, then the state at its slot
    mv      a1, s8
    call    node_api_state
    mv      a2, a0
    bnez    a0, 80f
    mv      a0, s8
    call    node_api_advance
    ld      t0, ApiRoute_op(s7)
    li      t1, API_OP_GET_STATE_V2
    beq     t0, t1, 64f
    addi    t1, t0, -API_OP_GET_PENDING_CONSOLIDATIONS  # the pending lists: a stream of the state, no data
    li      t2, 2
    bgtu    t1, t2, 695f
    sd      zero, ApiView_look_data(s8)
    j       64f
695: li     t1, API_OP_GET_STATE_RANDAO     # getStateRandao, getEpochSyncCommittees: the epoch in the work's data
    beq     t0, t1, 692f
    li      t1, API_OP_GET_EPOCH_SYNC_COMMITTEES
    beq     t0, t1, 692f
    li      t1, API_OP_GET_PROPOSER_LOOKAHEAD   # getProposerLookahead: SSZ, an answer flag
    bne     t0, t1, 693f
    ld      t1, ApiRoute_response(s7)
    li      t2, API_TYPE_SSZ
    bne     t1, t2, 67f
    ori     s3, s3, API_ANSWER_SSZ
    j       67f
692: ld     t1, ApiRoute_present(s7)
    andi    t1, t1, (1 << API_PARAM_EPOCH)
    bnez    t1, 694f
    li      t1, -1
    sd      t1, ApiRoute_epoch(s7)
694: addi   a0, s7, ApiRoute_epoch
    call    node_api_put8
    sd      a0, ApiView_look_data(s8)
    j       67f
693: addi   t0, t0, -API_OP_GET_STATE_VALIDATORS
    li      t1, API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS
    bgtu    t0, t1, 67f
    mv      a0, s7                          # the validator operations: their ids; getStateValidator a work, the others a stream
    call    node_api_ids
    sd      a0, ApiView_look_data(s8)
    ld      t0, ApiRoute_op(s7)
    li      t1, API_OP_GET_STATE_VALIDATOR
    bne     t0, t1, 64f
    j       67f
53: li      a2, 503                         # getSyncCommitteeDuties: 503 while syncing; 400 past the next period, with no index or a key
    ld      t0, ApiView_is_syncing(s8)
    bnez    t0, 80f
    li      a2, 400
    ld      t0, ApiRoute_list(s7)
    ld      t1, (ApiRoute_list + 8)(s7)
    beqz    t1, 80f
    add     t0, s7, t0
531: ld     t2, 0(t0)
    li      t3, API_VALIDATOR_INDEX
    bne     t2, t3, 80f
    addi    t0, t0, 64
    addi    t1, t1, -1
    bnez    t1, 531b
    mv      a0, s2
    call    node_store_slot
    li      t1, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    divu    t0, a0, t1
    addi    t0, t0, 1
    ld      t2, ApiRoute_epoch(s7)
    li      t1, EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    divu    t2, t2, t1
    li      a2, 400
    bgtu    t2, t0, 80f
    sd      t2, (L + 8)(sp)                 # the epoch's period
    addi    a0, s1, Node_head_root          # the head's post-state, of altair on, at the epoch's period or the one before
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 532f
    ld      a0, NodeBlock_slot(a1)
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_ALTAIR
    bltu    a0, t0, 532f
    addi    a0, s1, Node_head_root
    call    node_find_block
    ld      t0, NodeBlock_slot(a1)
    li      t1, SLOTS_PER_EPOCH * EPOCHS_PER_SYNC_COMMITTEE_PERIOD
    divu    t0, t0, t1
    ld      t2, (L + 8)(sp)
    bltu    t2, t0, 532f
    sub     t2, t2, t0
    li      t1, 1
    bgtu    t2, t1, 532f
    sd      t2, (L + 8)(sp)                 # 1: the next period
    li      t0, API_ID_HEAD
    sd      t0, ApiRoute_id_kind(s7)
    mv      a0, s7
    mv      a1, s8
    call    node_api_state
    li      a2, 400
    bnez    a0, 80f
    ld      t0, (L + 8)(sp)
    STQ     t0, s8, ApiView_next_period
    mv      a0, s7                          # its ids in the work's data
    call    node_api_ids
    sd      a0, ApiView_look_data(s8)
    j       67f
532: mv     a0, s2                          # else the state of the epoch's first slot, as getAttesterDuties
    call    node_store_slot
    ld      t2, ApiRoute_epoch(s7)
    li      t1, SLOTS_PER_EPOCH
    j       583f
58: li      a2, 503                         # getAttesterDuties: 503 while syncing; 400 past the next epoch, with no index or a key
    ld      t0, ApiView_is_syncing(s8)
    bnez    t0, 80f
    li      a2, 400
    ld      t0, ApiRoute_list(s7)
    ld      t1, (ApiRoute_list + 8)(s7)
    beqz    t1, 80f
    add     t0, s7, t0
581: ld     t2, 0(t0)
    li      t3, API_VALIDATOR_INDEX
    bne     t2, t3, 80f
    addi    t0, t0, 64
    addi    t1, t1, -1
    bnez    t1, 581b
    mv      a0, s2
    call    node_store_slot
    li      t1, SLOTS_PER_EPOCH
    divu    t0, a0, t1
    addi    t0, t0, 1
    ld      t2, ApiRoute_epoch(s7)
    li      a2, 400
    bgtu    t2, t0, 80f
583: mul    t2, t2, t1                      # the state of the first slot, as getProposerDuties; none: 400
    sd      t2, ApiRoute_id_slot(s7)
    li      t0, API_ID_SLOT
    bleu    t2, a0, 582f
    li      t0, API_ID_HEAD
582: sd     t0, ApiRoute_id_kind(s7)
    mv      a0, s7
    mv      a1, s8
    call    node_api_state
    li      a2, 400
    bnez    a0, 80f
    ld      t0, ApiRoute_id_slot(s7)
    sd      t0, ApiView_head_slot(s8)
    mv      a0, s8
    call    node_api_advance
    mv      a0, s7                          # its ids in the work's data
    call    node_api_ids
    sd      a0, ApiView_look_data(s8)
    j       67f
59: li      a2, 503                         # produceAttestationData: 503 while syncing; 400 past the store's slot
    ld      t0, ApiView_is_syncing(s8)
    bnez    t0, 80f
    mv      a0, s2
    call    node_store_slot
    ld      t1, ApiRoute_slot(s7)
    li      a2, 400
    bgtu    t1, a0, 80f
    li      t0, API_ID_SLOT                 # the state of the slot, as a state_id of it; none: 400
    sd      t0, ApiRoute_id_kind(s7)
    sd      t1, ApiRoute_id_slot(s7)
    mv      a0, s7
    mv      a1, s8
    call    node_api_state
    li      a2, 400
    bnez    a0, 80f
    li      a2, 503                         # an optimistic block: 503
    ld      t0, ApiView_is_optimistic(s8)
    bnez    t0, 80f
    mv      a0, s8
    call    node_api_advance
    addi    a0, s7, ApiRoute_committee_index    # its committee index in the work's data
    call    node_api_put8
    sd      a0, ApiView_look_data(s8)
    ld      t0, ApiRoute_response(s7)       # SSZ: an answer flag
    li      t1, API_TYPE_SSZ
    bne     t0, t1, 67f
    ori     s3, s3, API_ANSWER_SSZ
    j       67f
56: ld      t0, ApiRoute_present(s7)        # getPeers: its state and direction sets, all bits with none
    li      t1, -1
    li      t2, 1 << API_PARAM_STATE
    and     t2, t0, t2
    beqz    t2, 561f
    ld      t1, ApiRoute_peer_states(s7)
561: STQ    t1, s8, ApiView_peer_states
    li      t1, -1
    li      t2, 1 << API_PARAM_DIRECTION
    and     t2, t0, t2
    beqz    t2, 562f
    ld      t1, ApiRoute_peer_directions(s7)
562: STQ    t1, s8, ApiView_peer_directions
    STQ     s1, s8, ApiView_node
    li      a2, 200
    li      a3, API_OP_GET_PEERS
    j       81f
55: mv      a0, s7                          # getPeer: the peer of its peer_id, else 404
    call    node_api_find_peer
    li      a2, 404
    beqz    a0, 80f
    STQ     a0, s8, ApiView_peer
    li      a2, 200
    li      a3, API_OP_GET_PEER
    j       81f
57: mv      a0, s9                          # getBlockHeaders: a stream of the blocks of its query
    mv      a1, s7
    mv      a2, s3
    call    node_api_headers_stream
    j       90f
68: mv      a0, s9                          # a pool GET: a stream of the pool
    mv      a1, s7
    mv      a2, s3
    mv      a3, s8
    call    node_api_pool_stream
    j       90f
60: mv      a0, s9                          # a pool POST: a work checks its operations
    mv      a1, s7
    mv      a2, s3
    mv      a3, s4
    mv      a4, s8
    call    node_api_submit
    mv      a2, a0
    bnez    a0, 80f
    j       90f
61: mv      a0, s9                          # eventstream: an entry, and the head
    mv      a1, s7
    mv      a2, s3
    call    node_api_subscribe
    j       90f
63: li      a2, 503                         # getProposerDuties: 503 while syncing; 400 past the next epoch
    ld      t0, ApiView_is_syncing(s8)
    bnez    t0, 80f
    mv      a0, s2
    call    node_store_slot
    li      t1, SLOTS_PER_EPOCH
    divu    t0, a0, t1
    addi    t0, t0, 1
    ld      t2, ApiRoute_epoch(s7)
    li      a2, 400
    bgtu    t2, t0, 80f
    mul     t2, t2, t1                      # the first slot: as a state_id of it; past the store's slot, the head's post-state
    sd      t2, ApiRoute_id_slot(s7)
    li      t0, API_ID_SLOT
    bleu    t2, a0, 62f
    li      t0, API_ID_HEAD
62: sd      t0, ApiRoute_id_kind(s7)
    mv      a0, s7
    mv      a1, s8
    call    node_api_state
    mv      a2, a0
    bnez    a0, 80f
    ld      t0, ApiRoute_id_slot(s7)        # brought to the first slot
    sd      t0, ApiView_head_slot(s8)
    mv      a0, s8
    call    node_api_advance
    j       67f
65: mv      a0, s7                          # a block: its lookup
    mv      a1, s8
    call    node_api_block
    mv      a2, a0
    bnez    a0, 80f
    ld      a3, ApiRoute_op(s7)
    li      a2, 200
    li      t0, API_OP_GET_BLOCK_ROOT       # getBlockRoot: the answer at once
    beq     a3, t0, 81f
    li      t0, API_OP_GET_BLOCK_V2
    beq     a3, t0, 64f
    li      t0, API_OP_GET_BLOCK_ATTESTATIONS_V2
    beq     a3, t0, 64f
    li      t0, API_OP_GET_BLINDED_BLOCK
    beq     a3, t0, 64f
    li      t0, API_OP_GET_BLOB_SIDECARS
    beq     a3, t0, 54f
    li      t0, API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    beq     a3, t0, 54f
67: ld      a0, ApiRoute_op(s7)             # a work
    mv      a1, s9
    mv      a2, s3
    mv      a3, s8
    call    node_api_encode
    mv      a2, a0
    bnez    a0, 80f
    j       90f
54: mv      a0, s9                          # a sidecar stream of the block
    mv      a1, s7
    mv      a2, s3
    mv      a3, s8
    call    node_api_sidecar_stream
    beqz    a0, 90f
    mv      a2, a0
    j       80f
64: mv      a0, s9                          # a stream of the answer
    mv      a1, s7
    mv      a2, s3
    mv      a3, s8
    call    node_api_stream
    beqz    a0, 90f
    mv      a2, a0
    j       80f
7:  li      a2, 501                         # another operation
80: li      a3, API_BODY_ERROR
81: mv      a0, s9
    mv      a1, s8
    mv      a4, s10
    call    node_api_send
90: ld      t0, (L + 0)(sp)
    sd      t0, 0(s5)
    LEAVE 16
END_FUNCTION node_api_event

/*
 * The NODE_EV_WORK_DONE a0 of a NODE_WORK_API_ENCODE (node.md, lantern_node_step): its response
 * to the connection, or the error 500. s1 the node, s6 the actions. s3 the event, s4 the action,
 * s7 the flags.
 */
LOCAL_FUNCTION node_api_done
    ENTER 0
    mv      s3, a0
    ld      t0, NodeAction_arg(s3)          # getStateValidator: its ids go; produceAttestationData its index
    andi    t0, t0, 255
    li      t1, API_OP_GET_STATE_VALIDATOR
    beq     t0, t1, 3f
    li      t1, API_OP_PRODUCE_ATTESTATION_DATA
    beq     t0, t1, 3f
    li      t1, API_OP_GET_STATE_RANDAO
    beq     t0, t1, 3f
    li      t1, API_OP_GET_EPOCH_SYNC_COMMITTEES
    beq     t0, t1, 3f
    li      t1, API_OP_GET_SYNC_COMMITTEE_DUTIES
    beq     t0, t1, 3f
    li      t1, API_OP_GET_ATTESTER_DUTIES
    bne     t0, t1, 2f
3:  ld      a1, NodeAction_data(s3)
    beqz    a1, 2f
    li      a0, NODE_ACT_BYTES_FREE
    li      a2, 0
    call    node_ids
2:  ld      t0, NodeAction_arg(s3)
    srli    t0, t0, 8
    andi    t0, t0, 255
    andi    s7, t0, API_ANSWER_CLOSE        # API_R_CLOSE, or API_R_KEEP for HTTP/1.0 kept open
    bnez    s7, 1f
    andi    t1, t0, API_ANSWER_HTTP10
    beqz    t1, 1f
    li      s7, API_R_KEEP
1:  ld      t0, NodeEvent_result(s3)
    bnez    t0, 5f
    ld      a1, (NodeEvent_chunk + 16)(s3)  # the chunk's bytes in a SEND
    addi    a1, a1, (56 + 7)
    andi    a1, a1, -8
    li      a0, NODE_ACT_API_SEND
    call    node_act
    mv      s4, a0
    ld      t0, NodeAction_target(s3)
    sd      t0, 16(s4)
    li      t0, 1
    sd      t0, 24(s4)
    ld      t0, 0(s4)
    addi    t0, t0, -32
    sd      t0, 32(s4)
    li      t0, 24
    sd      t0, 40(s4)
    ld      a2, (NodeEvent_chunk + 16)(s3)
    sd      a2, 48(s4)
    addi    a0, s4, 56
    ld      t0, (NodeEvent_chunk + 8)(s3)
    addi    a1, s3, NodeEvent_chunk
    add     a1, a1, t0
    call    lantern_copy
    ld      t0, 48(s4)                      # zero bytes to the size
    addi    a0, s4, 56
    add     a0, a0, t0
    ld      a1, 0(s4)
    addi    a1, a1, -56
    sub     a1, a1, t0
    call    lantern_zero
    andi    t0, s7, API_R_CLOSE
    beqz    t0, 9f
    li      a0, NODE_ACT_API_CLOSE
    li      a1, NODE_ACT_API_CLOSE_SIZE
    call    node_act
    ld      t0, NodeAction_target(s3)
    sd      t0, 16(a0)
    LEAVE 0
5:  ld      a0, NodeAction_target(s3)       # not valid: the error 500
    li      a1, 0
    li      a2, 500
    li      a3, API_BODY_ERROR
    mv      a4, s7
    call    node_api_send
9:  LEAVE 0
END_FUNCTION node_api_done

/*
 * (node, store, work, state_a, data, scratch, event, room) -> a0: a NODE_WORK_API_ENCODE of
 * lantern_node_run (node.md): the response at NodeEvent_chunk of the event, whose buffer has room
 * bytes. s1 the node, s2 the store, s3 the work, s4 state_a, s5 data, s6 the scratch, s7 the
 * event, s8 the ApiView at the end of scratch, s9 the operation, s10 the room. Locals: L the
 * scratch's size, L+8 the fork, L+16 a Result, L+24 a blob count.
 */
LOCAL_FUNCTION node_api_run
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      s7, a6
    mv      s10, a7
    ld      t0, NodeAction_arg(s3)          # the operation; a block index past the blocks part
    andi    s9, t0, 255
    srli    t1, t0, 24
    li      t2, API_OP_GET_BLOCK_HEADER
    bne     s9, t2, 1f
    ld      t2, (Node_blocks + 8)(s1)
    bgtu    t1, t2, 8f
    bnez    s5, 2f                          # a header: bytes, or a block of the node with a post-state
    beqz    t1, 8f
    beqz    s4, 8f
    j       2f
1:  li      t2, API_OP_GET_SPEC             # getSpec, getDebugChainHeadsV2, getDebugForkChoice: no state
    beq     s9, t2, 2f
    li      t2, API_OP_GET_DEBUG_CHAIN_HEADS_V2
    beq     s9, t2, 2f
    li      t2, API_OP_GET_DEBUG_FORK_CHOICE
    beq     s9, t2, 2f
    beqz    s4, 8f                          # a state's answer: a state
    li      t2, API_OP_GET_STATE_FINALITY_CHECKPOINTS
    beq     s9, t2, 2f
    li      t2, API_OP_GET_STATE_VALIDATOR
    beq     s9, t2, 2f
    li      t2, API_OP_GET_STATE_ROOT
    beq     s9, t2, 2f
    li      t2, API_OP_GET_PROPOSER_DUTIES
    beq     s9, t2, 2f
    li      t2, API_OP_PRODUCE_ATTESTATION_DATA
    beq     s9, t2, 2f
    li      t2, API_OP_GET_ATTESTER_DUTIES
    beq     s9, t2, 2f
    li      t2, API_OP_GET_SYNC_COMMITTEE_DUTIES
    beq     s9, t2, 2f
    li      t2, API_OP_GET_STATE_RANDAO
    beq     s9, t2, 2f
    li      t2, API_OP_GET_EPOCH_SYNC_COMMITTEES
    beq     s9, t2, 2f
    li      t2, API_OP_GET_PROPOSER_LOOKAHEAD
    beq     s9, t2, 2f
    li      t2, API_OP_GET_STATE_FORK
    bne     s9, t2, 8f
2:  ld      t0, 0(s6)                       # the ApiView at the end of scratch, with the work's values
    sd      t0, (L + 0)(sp)
    li      t1, ApiView__size
    bltu    t0, t1, 7f
    sub     t0, t0, t1
    sd      t0, 0(s6)
    add     s8, s6, t0
    mv      a0, s8
    call    node_api_view
    ld      t0, NodeAction_arg(s3)
    srli    t1, t0, 16
    andi    t1, t1, 1
    sd      t1, ApiView_canonical(s8)
    srli    t1, t0, 17
    andi    t1, t1, 1
    sd      t1, ApiView_head_finalized(s8)
    srli    t1, t0, 18
    andi    t1, t1, 1
    sd      t1, ApiView_is_optimistic(s8)
    STQ     zero, s8, ApiView_status
    li      t2, API_OP_GET_BLOCK_HEADER
    beq     s9, t2, 3f
    li      t2, API_OP_GET_SPEC
    beq     s9, t2, 5f
    li      t2, API_OP_GET_DEBUG_CHAIN_HEADS_V2
    beq     s9, t2, 29f
    li      t2, API_OP_GET_DEBUG_FORK_CHOICE
    beq     s9, t2, 28f
    srli    t0, t0, 24                      # a state at the work's slot, else the work that brought it there failed
    ld      a0, NODE_STATE_SLOT(s4)
    bne     a0, t0, 42f
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    li      t0, API_OP_GET_STATE_VALIDATOR
    bne     s9, t0, 271f
    mv      a0, s4                          # getStateValidator: the validator of its ids
    mv      a1, s5
    beqz    a1, 8f
    call    node_api_find_validator
    sd      s4, ApiView_val_state(s8)
    sd      a0, ApiView_val_index(s8)
    j       5f
271: li     t0, API_OP_GET_STATE_RANDAO     # getStateRandao: lantern_node_randao of the epoch in data
    bne     s9, t0, 272f
    beqz    s5, 41f
    ld      t0, 16(s5)
    li      t1, 8
    bltu    t0, t1, 41f
    ld      t0, 8(s5)
    add     t0, s5, t0
    ld      a1, 0(t0)
    mv      a0, s4
    ADDQ    a2, s8, ApiView_randao
    FORK_CALL node_randao
    j       275f
272: li     t0, API_OP_GET_EPOCH_SYNC_COMMITTEES    # lantern_node_sync_committee of the epoch in data, its out at the end of scratch
    bne     s9, t0, 274f
    beqz    s5, 41f
    ld      t0, 16(s5)
    li      t1, 8
    bltu    t0, t1, 41f
    ld      t0, 8(s5)
    add     t0, s5, t0
    ld      a1, 0(t0)
    ld      t0, 0(s6)
    li      t1, 8 * SYNC_COMMITTEE_SIZE
    bltu    t0, t1, 71f
    sub     t0, t0, t1
    sd      t0, 0(s6)
    add     a3, s6, t0
    STQ     a3, s8, ApiView_sync_out
    mv      a0, s4
    mv      a2, s6
    FORK_CALL node_sync_committee
    j       275f
274: li     t0, API_OP_GET_SYNC_COMMITTEE_DUTIES    # lantern_node_sync_committee of the state's epoch, or of the next period's
    bne     s9, t0, 273f
    beqz    s5, 41f
    STQ     s5, s8, ApiView_sd_ids
    sd      s4, ApiView_val_state(s8)
    ld      a1, NODE_STATE_SLOT(s4)
    li      t0, SLOTS_PER_EPOCH
    divu    a1, a1, t0
    ld      t0, NodeAction_arg(s3)
    li      t1, API_VALUE_NEXT_PERIOD << 16
    and     t0, t0, t1
    beqz    t0, 2741f
    addi    a1, a1, EPOCHS_PER_SYNC_COMMITTEE_PERIOD
2741: ld    t0, 0(s6)
    li      t1, 8 * SYNC_COMMITTEE_SIZE
    bltu    t0, t1, 71f
    sub     t0, t0, t1
    sd      t0, 0(s6)
    add     a3, s6, t0
    STQ     a3, s8, ApiView_sync_out
    mv      a0, s4
    mv      a2, s6
    FORK_CALL node_sync_committee
    j       275f
273: li     t0, API_OP_GET_PROPOSER_LOOKAHEAD       # lantern_node_proposer_lookahead; the version the state's fork
    bne     s9, t0, 20f
    sd      t6, ApiView_fork(s8)
    mv      a0, s4
    ADDQ    a1, s8, ApiView_lookahead
    FORK_CALL node_proposer_lookahead
275: li     t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    li      t0, LANTERN_NO_STATE_ANSWER     # no answer in the state: 400
    bne     a0, t0, 276f
    li      t0, 400
    STQ     t0, s8, ApiView_status
    j       5f
276: beqz   a0, 5f
    sd      a0, NodeEvent_result(s7)
    j       9f
20: li      t0, API_OP_PRODUCE_ATTESTATION_DATA
    bne     s9, t0, 25f
    beqz    s5, 41f                         # produceAttestationData: lantern_node_attestation_data, its index in data
    ld      t0, 16(s5)
    li      t1, 8
    bltu    t0, t1, 41f
    ld      t0, 8(s5)
    add     t0, s5, t0
    ld      a2, 0(t0)
    mv      a0, s4
    addi    a1, s1, Node_config
    mv      a3, s6
    ADDQ    a4, s8, ApiView_att
    FORK_CALL node_attestation_data
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    beqz    a0, 5f
    sd      a0, NodeEvent_result(s7)
    j       9f
25: li      t0, API_OP_GET_ATTESTER_DUTIES
    bne     s9, t0, 26f
    beqz    s5, 41f                         # getAttesterDuties: lantern_node_attester_duties of its ids, its out at the end of scratch
    ld      t0, 16(s5)
    srli    t0, t0, 6
    STQ     t0, s8, ApiView_ad_count
    li      t1, 48
    mul     t0, t0, t1
    addi    t0, t0, 40
    ld      t1, 0(s6)
    bltu    t1, t0, 71f
    sub     t1, t1, t0
    sd      t1, 0(s6)
    add     a4, s6, t1
    STQ     a4, s8, ApiView_ad_out
    mv      a0, s4
    addi    a1, s1, Node_config
    mv      a2, s5
    mv      a3, s6
    FORK_CALL node_attester_duties
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    beqz    a0, 24f
    sd      a0, NodeEvent_result(s7)
    j       9f
26: li      t0, API_OP_GET_PROPOSER_DUTIES
    bne     s9, t0, 23f
    mv      a0, s4                          # getProposerDuties: lantern_node_proposers
    addi    a1, s1, Node_config
    mv      a2, s6
    addi    a3, s8, ApiView_duties
    FORK_CALL node_proposers
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    beqz    a0, 24f
    sd      a0, NodeEvent_result(s7)
    j       9f
24: sd      s4, ApiView_val_state(s8)
    j       5f
23: li      t0, API_OP_GET_STATE_FINALITY_CHECKPOINTS
    bne     s9, t0, 21f
    mv      a0, s4                          # finality_checkpoints
    addi    a1, s8, ApiView_previous_justified
    FORK_CALL node_state_checkpoints
    j       5f
21: li      t0, API_OP_GET_STATE_FORK
    bne     s9, t0, 22f
    addi    a0, s8, ApiView_state_fork      # fork
    addi    a1, s4, NODE_STATE_FORK
    li      a2, 16
    call    lantern_copy
    j       5f
22: mv      a0, s4                          # root
    LDQ     a1, s1, Node_config + CONFIG_STATE_CACHE
    mv      a2, s6
    addi    a3, s8, ApiView_head_root
    FORK_CALL state_root
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    bnez    a0, 41f
    j       5f
3:  beqz    s5, 33f
    ld      t0, 16(s5)                      # header: of the bytes, at the fork of their slot
    li      t1, (100 + 84)
    bltu    t0, t1, 41f
    ld      t0, 8(s5)
    add     t0, s5, t0
    lwu     a0, 100(t0)
    lwu     t1, 104(t0)
    slli    t1, t1, 32
    or      a0, a0, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    sd      a0, (L + 8)(sp)
    mv      a0, s5
    mv      a1, s6
    addi    a2, s8, (ApiView_proposer_index - 8)    # the header's slot lands on the root's last 8 bytes
    FORK_CALL node_block_header
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    bnez    a0, 41f
    ld      t0, (ApiView_proposer_index - 8)(s8)
    sd      t0, ApiView_head_slot(s8)
    ld      t0, NodeAction_arg(s3)          # the root: the node's block's, else of the bytes
    srli    t0, t0, 24
    bnez    t0, 34f
    ld      t6, (L + 8)(sp)
    mv      a0, s5
    mv      a1, s6
    addi    a2, s8, ApiView_head_root
    addi    a3, sp, (L + 16)
    addi    a4, sp, (L + 24)
    FORK_CALL node_block_root
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    bnez    a0, 41f
    ld      t0, (L + 16)(sp)
    bnez    t0, 41f
    j       5f
33: addi    a0, s8, ApiView_proposer_index  # no bytes: the state's latest_block_header, a zero signature
    addi    a1, s4, (NODE_STATE_HEADER + 8)
    li      a2, (112 - 8)
    call    lantern_copy
    ld      t0, NODE_STATE_HEADER(s4)
    sd      t0, ApiView_head_slot(s8)
    ld      t0, ApiView_state_root(s8)
    ld      t1, (ApiView_state_root + 8)(s8)
    or      t0, t0, t1
    ld      t1, (ApiView_state_root + 16)(s8)
    or      t0, t0, t1
    ld      t1, (ApiView_state_root + 24)(s8)
    or      t0, t0, t1
    bnez    t0, 34f
    ld      a0, NODE_STATE_SLOT(s4)         # a zero state_root: the state's root
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s4
    LDQ     a1, s1, Node_config + CONFIG_STATE_CACHE
    mv      a2, s6
    addi    a3, s8, ApiView_state_root
    FORK_CALL state_root
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    bnez    a0, 41f
34: ld      t0, NodeAction_arg(s3)          # the root of the node's block, index - 1
    srli    t0, t0, 24
    beqz    t0, 5f
    addi    t0, t0, -1
    li      t1, NodeBlock__mem
    mul     t0, t0, t1
    PART    t1, t2, s1, Node_blocks
    add     t0, t1, t0
    addi    t1, s8, ApiView_head_root
    COPY32  t1, t0
5:  ld      t0, NodeAction_arg(s3)          # the response, in the event
    srli    t0, t0, 8
    andi    t0, t0, 255
    andi    a4, t0, API_ANSWER_CLOSE
    bnez    a4, 51f
    andi    t1, t0, API_ANSWER_HTTP10
    beqz    t1, 51f
    li      a4, API_R_KEEP
51: andi    t1, t0, API_ANSWER_SSZ          # SSZ: API_R_SSZ
    beqz    t1, 53f
    ori     a4, a4, API_R_SSZ
53: addi    t0, s10, -NodeEvent_chunk
    andi    t0, t0, -8
    li      t1, 24
    bltu    t0, t1, 71f
    sd      t0, NodeEvent_chunk(s7)
    mv      a0, s8
    addi    a1, s7, NodeEvent_chunk
    li      a2, 200
    mv      a3, s9
    li      t0, API_OP_GET_STATE_VALIDATOR  # no such validator: 404
    bne     s9, t0, 52f
    ld      t0, ApiView_val_index(s8)
    li      t1, -1
    bne     t0, t1, 52f
    li      a2, 404
    li      a3, API_BODY_ERROR
52: LDQ     t0, s8, ApiView_status          # an error status of the work
    beqz    t0, 54f
    mv      a2, t0
    li      a3, API_BODY_ERROR
    andi    a4, a4, ~API_R_SSZ
    j       56f
54: li      t0, API_OP_GET_PROPOSER_LOOKAHEAD   # Eth-Consensus-Version of getProposerLookahead
    bne     s9, t0, 56f
    ori     a4, a4, API_R_VERSION
56: call    api_respond
    bnez    a0, 71f
    ld      t0, (NodeEvent_chunk + 16)(s7)  # the event's size covers the chunk
    addi    t0, t0, (NodeEvent_chunk + 24 + 7)
    andi    t0, t0, -8
    sd      t0, 0(s7)
    addi    t0, t0, -NodeEvent_chunk
    sd      t0, NodeEvent_chunk(s7)
    j       9f
    # getDebugChainHeadsV2: a byte for each store node at the end of scratch, 1 when it is out of the tree, 2 when a node not out has it as parent
29: ld      t0, Store_blocks(s2)
    add     t0, s2, t0
    ld      t1, (Store_blocks + 8)(s2)
    addi    t2, t1, 7
    andi    t2, t2, -8
    ld      t3, 0(s6)
    bltu    t3, t2, 71f
    sub     t3, t3, t2
    sd      t3, 0(s6)
    add     t3, s6, t3
    STQ     t3, s8, ApiView_heads
    sd      s2, ApiView_val_state(s8)
    li      t2, 0
291: bgeu   t2, t1, 5b
    li      t4, BlockNode__mem
    mul     t4, t2, t4
    add     t4, t0, t4
    ld      t5, BlockNode_payload_status(t4)
    addi    t5, t5, -PAYLOAD_STATUS_INVALIDATED
    seqz    t5, t5
    ld      t6, BlockNode_parent(t4)
    bgeu    t6, t1, 293f
    add     t6, t3, t6
    lbu     a0, 0(t6)
    andi    a0, a0, 1
    or      t5, t5, a0
    bnez    t5, 293f
    lbu     a0, 0(t6)
    ori     a0, a0, 2
    sb      a0, 0(t6)
293: add    a0, t3, t2
    sb      t5, 0(a0)
    addi    t2, t2, 1
    j       291b
    # getDebugForkChoice: lantern_node_weights of the fork of the head's slot into the end of scratch; a failure, the error 500
28: ld      t1, (Store_blocks + 8)(s2)
    slli    t1, t1, 3
    ld      t0, 0(s6)
    bltu    t0, t1, 71f
    sub     t0, t0, t1
    sd      t0, 0(s6)
    add     t0, s6, t0
    STQ     t0, s8, ApiView_weights
    sd      s2, ApiView_val_state(s8)
    ld      a0, ApiView_head_slot(s8)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s2
    mv      a1, s6
    LDQ     a2, s8, ApiView_weights
    FORK_CALL node_weights
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    beqz    a0, 5b
    li      t0, 500
    STQ     t0, s8, ApiView_status
    j       5b
42: li      t0, LANTERN_INVALID_SLOT
    sd      t0, NodeEvent_result(s7)
    j       9f
41: li      t0, LANTERN_INVALID_ENCODING
    sd      t0, NodeEvent_result(s7)
9:  ld      t0, (L + 0)(sp)
    sd      t0, 0(s6)
    li      a0, LANTERN_OK
    LEAVE 32
8:  li      a0, LANTERN_INVALID_EVENT
    LEAVE 32
71: ld      t0, (L + 0)(sp)
    sd      t0, 0(s6)
7:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION node_api_run

/* ---------------------------------------------------------------- Lookup (beacon-api.md, Common rules) */

/* a0 = the NodeBlock index of the imported parent of the entry a0, or 2^64 - 1; a1 = its entry. Uses t0-t2, a6, a7. */
LOCAL_FUNCTION node_api_parent
    FRAME 0
    addi    a0, a0, NodeBlock_parent_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      t1, NodeBlock_status(a1)
    li      t2, NODE_BLOCK_IMPORTED
    beq     t1, t2, 9f
    li      a0, -1
9:  UNFRAME 0
END_FUNCTION node_api_parent

/*
 * The block of the chain at or below the slot a0: a0 = its NodeBlock index, a1 = its entry; or
 * a0 = 2^64 - 1 when the lowest block of the chain the node keeps, a1 (0 with no head), is above
 * the slot. Locals: the slot, an entry.
 */
LOCAL_FUNCTION node_api_below
    FRAME 16
    sd      a0, 0(sp)
    addi    a0, s1, Node_head_root
    call    node_find_block
    li      t0, -1
    bne     a0, t0, 1f
    li      a1, 0
    UNFRAME 16
1:  ld      t0, NodeBlock_slot(a1)
    ld      t1, 0(sp)
    bleu    t0, t1, 9f
    sd      a1, 8(sp)
    mv      a0, a1
    call    node_api_parent
    li      t0, -1
    bne     a0, t0, 1b
    ld      a1, 8(sp)
9:  UNFRAME 16
END_FUNCTION node_api_below

/* a0 = 1 when the block entry a0 is on the chain, else 0. Locals: the entry. */
LOCAL_FUNCTION node_api_on_chain
    FRAME 16
    sd      a0, 0(sp)
    ld      a0, NodeBlock_slot(a0)
    call    node_api_below
    li      t0, -1
    beq     a0, t0, 8f
    ld      t0, 0(sp)
    sub     t0, a1, t0
    seqz    a0, t0
    UNFRAME 16
8:  li      a0, 0
    UNFRAME 16
END_FUNCTION node_api_on_chain

/* a0 = 1 when the slot a0 is at most that of the block of the store's finalized root, else 0. Locals: a0. */
LOCAL_FUNCTION node_api_final_block
    FRAME 16
    sd      a0, 0(sp)
    call    node_f_slot
    li      t0, -1
    beq     a0, t0, 8f
    ld      t0, 0(sp)
    sltu    a0, a0, t0
    xori    a0, a0, 1
    UNFRAME 16
8:  li      a0, 0
    UNFRAME 16
END_FUNCTION node_api_final_block

/*
 * The block of the block_id of the ApiRoute a0 into the ApiView a1 (beacon-api.md, Common rules):
 * head_root, head_slot, canonical, head_finalized, is_optimistic, look_index, look_data, and for a
 * block the node keeps look_state and look_state_slot. a0 = 0, or 404 for none. s1 the node, s2
 * the store. s3 the route, s4 the view, s7 the entry, s8 the slot. Locals: L the Db's slot.
 */
LOCAL_FUNCTION node_api_block
    ENTER 16
    mv      s3, a0
    mv      s4, a1
    li      t0, -1
    sd      t0, ApiView_look_index(s4)
    sd      zero, ApiView_look_data(s4)
    sd      zero, ApiView_look_state(s4)
    sd      zero, ApiView_look_copy(s4)
    ld      t1, ApiRoute_id_kind(s3)
    addi    a0, s1, Node_head_root          # head
    li      t0, API_ID_HEAD
    beq     t1, t0, 4f
    addi    a0, s2, (Store_finalized_checkpoint + 8)    # finalized
    li      t0, API_ID_FINALIZED
    beq     t1, t0, 4f
    li      t0, API_ID_ROOT
    bne     t1, t0, 3f
    addi    a0, s3, ApiRoute_id_root        # a root: the node's imported block, else the Db's
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 1f
    ld      t1, NodeBlock_status(a1)
    li      t2, NODE_BLOCK_IMPORTED
    beq     t1, t2, 5f
1:  ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 80f
    ld      a0, Node_db(s1)
    add     a0, s1, a0
    addi    a1, s3, ApiRoute_id_root
    addi    a2, sp, L
    call    lantern_db_find_root
    ld      s8, L(sp)
    li      t0, -1
    beq     s8, t0, 80f
    addi    a0, s3, ApiRoute_id_root
    j       6f
3:  li      s8, 0                           # genesis: the slot 0; a slot
    li      t0, API_ID_SLOT
    bne     t1, t0, 31f
    ld      s8, ApiRoute_id_slot(s3)
31: mv      a0, s8
    call    node_api_below
    li      t0, -1
    beq     a0, t0, 32f
    ld      t0, NodeBlock_slot(a1)
    bne     t0, s8, 80f                     # an empty slot, or past the head
    j       5f
32: ld      t0, Node_flags(s1)              # below the chain's blocks the node keeps: the Db's
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 80f
    mv      a0, s8
    call    node_db_slot
    beqz    a0, 80f
    j       6f                              # DbSlot_root is at 0
4:  call    node_find_block                 # head, finalized: the block of that root
    li      t0, -1
    beq     a0, t0, 80f
5:  mv      s7, a1                          # a block the node keeps
    sd      a0, ApiView_look_index(s4)
    addi    t0, s4, ApiView_head_root
    COPY32  t0, s7
    ld      s8, NodeBlock_slot(s7)
    sd      s8, ApiView_head_slot(s4)
    sd      s8, ApiView_look_state_slot(s4)
    ld      t0, NodeBlock_payload_status(s7)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t0, t0
    sd      t0, ApiView_is_optimistic(s4)
    ld      t0, NodeBlock_state_id(s7)
    sd      t0, ApiView_look_state(s4)
    ld      a0, NodeBlock_data_id(s7)
    bnez    a0, 51f
    mv      a0, s7
    call    node_api_db_ref
51: sd      a0, ApiView_look_data(s4)
    mv      a0, s7
    call    node_api_on_chain
    sd      a0, ApiView_canonical(s4)
    beqz    a0, 52f
    mv      a0, s8
    call    node_api_final_block
52: sd      a0, ApiView_head_finalized(s4)
    li      a0, 0
    LEAVE 16
6:  addi    t0, s4, ApiView_head_root       # a block of the Db: its root at a0, its slot s8
    COPY32  t0, a0
    sd      s8, ApiView_head_slot(s4)
    sd      zero, ApiView_is_optimistic(s4)
    li      t0, 1
    sd      t0, ApiView_canonical(s4)
    mv      a0, s8
    call    node_db_block
    sd      a0, ApiView_look_data(s4)
    mv      a0, s8
    call    node_api_final_block
    sd      a0, ApiView_head_finalized(s4)
    li      a0, 0
    LEAVE 16
80: li      a0, 404
    LEAVE 16
END_FUNCTION node_api_block

/*
 * The state of the state_id of the ApiRoute a0 into the ApiView a1 (beacon-api.md, Common rules):
 * look_state, a state the node keeps, at look_state_slot; head_slot the slot it goes to;
 * head_finalized and is_optimistic. a0 = 0, or 404 for none. s1 the node, s2 the store, s5 the
 * scratch, s6 the actions. s3 the route, s4 the view, s7 the block's entry, s8 the slot, s9 the
 * checkpoint.
 */
LOCAL_FUNCTION node_api_state
    ENTER 0
    mv      s3, a0
    mv      s4, a1
    sd      zero, ApiView_look_state(s4)
    sd      zero, ApiView_look_copy(s4)
    li      t0, -1
    sd      t0, ApiView_look_index(s4)
    ld      t1, ApiRoute_id_kind(s3)
    li      t0, API_ID_HEAD
    bne     t1, t0, 1f
    addi    a0, s1, Node_head_root          # head: its post-state at its slot
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 80f
    ld      s8, NodeBlock_slot(a1)
    j       5f
1:  addi    s9, s2, Store_finalized_checkpoint
    li      t0, API_ID_FINALIZED
    beq     t1, t0, 2f
    addi    s9, s2, Store_justified_checkpoint
    li      t0, API_ID_JUSTIFIED
    bne     t1, t0, 3f
2:  ld      s8, 0(s9)                       # a checkpoint: at the first slot of its epoch
    li      t0, SLOTS_PER_EPOCH
    mul     s8, s8, t0
    addi    a0, s9, 8                       # the optimistic status of its block
    call    node_find_block
    li      t1, 0
    li      t0, -1
    beq     a0, t0, 21f
    ld      t1, NodeBlock_payload_status(a1)
    addi    t1, t1, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t1, t1
21: sd      t1, ApiView_is_optimistic(s4)
    ld      a0, 0(s9)                       # its NodeCheckpoint's state, else its block's post-state
    addi    a1, s9, 8
    call    node_find_checkpoint
    li      t0, -1
    beq     a0, t0, 22f
    ld      t0, NodeCheckpoint_state_id(a1)
    beqz    t0, 22f
    sd      t0, ApiView_look_state(s4)
    sd      s8, ApiView_look_state_slot(s4)
    j       7f
22: addi    a0, s9, 8
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 80f
    j       5f
3:  li      t0, API_ID_ROOT                 # a state root: none in this version
    beq     t1, t0, 80f
    li      s8, 0                           # genesis: the slot 0; a slot, at most the store's
    li      t0, API_ID_SLOT
    bne     t1, t0, 31f
    ld      s8, ApiRoute_id_slot(s3)
31: mv      a0, s2
    call    node_store_slot
    bgtu    s8, a0, 80f
    mv      a0, s8
    call    node_api_below
    li      t0, -1
    beq     a0, t0, 80f
5:  mv      s7, a1                          # the block's post-state, again when the node let it go
    ld      t0, NodeBlock_payload_status(s7)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t0, t0
    sd      t0, ApiView_is_optimistic(s4)
    ld      a0, NodeBlock_state_id(s7)
    bnez    a0, 6f
    call    node_f_slot
    li      t0, -1
    beq     a0, t0, 80f
    ld      t0, NodeBlock_slot(s7)
    bleu    t0, a0, 80f
    mv      a0, s7
    call    node_rebuild
    beqz    a0, 80f
6:  sd      a0, ApiView_look_state(s4)
    ld      t0, NodeBlock_slot(s7)
    sd      t0, ApiView_look_state_slot(s4)
7:  sd      s8, ApiView_head_slot(s4)       # finalized: at most the first slot of the finalized epoch
    ld      t0, Store_finalized_checkpoint(s2)
    li      t1, SLOTS_PER_EPOCH
    mul     t0, t0, t1
    sltu    t0, t0, s8
    xori    t0, t0, 1
    sd      t0, ApiView_head_finalized(s4)
    li      a0, 0
    LEAVE 0
80: li      a0, 404
    LEAVE 0
END_FUNCTION node_api_state

/*
 * The state of the ApiView a0 at its slot (node.md, NODE_EV_API): when head_slot is past
 * look_state_slot, a STATE_COPY of look_state, the copy across the fork boundaries to head_slot,
 * and a SLOTS work of it to head_slot when it is below it; look_state is the copy, look_copy 1.
 * s3 the view, s4 the copy, s7 the copy's slot, s8 the fork of look_state_slot.
 */
LOCAL_FUNCTION node_api_advance
    ENTER 0
    mv      s3, a0
    ld      t0, ApiView_look_state_slot(s3)
    ld      t1, ApiView_head_slot(s3)
    bleu    t1, t0, 9f
    call    node_new_id
    mv      s4, a0
    mv      a2, a0
    li      a0, NODE_ACT_STATE_COPY
    ld      a1, ApiView_look_state(s3)
    call    node_ids
    mv      a0, s4
    ld      a1, ApiView_look_state(s3)
    ld      a2, ApiView_look_state_slot(s3)
    ld      a3, ApiView_head_slot(s3)
    call    node_cross
    mv      s4, a0
    ld      s7, ApiView_look_state_slot(s3) # the copy's slot: the first of the target's fork, when it crossed one
    mv      a0, s7
    addi    a1, s1, Node_config
    call    node_fork
    mv      s8, a0
    ld      a0, ApiView_head_slot(s3)
    addi    a1, s1, Node_config
    call    node_fork
    bleu    a0, s8, 1f
    slli    t0, a0, 4
    add     t0, s1, t0
    LDQ     t0, t0, Node_config
    li      t1, SLOTS_PER_EPOCH
    mul     t0, t0, t1
    bleu    t0, s7, 1f
    mv      s7, t0
1:  ld      a5, ApiView_head_slot(s3)
    bleu    a5, s7, 2f
    li      a0, NODE_WORK_SLOTS
    mv      a1, s4
    li      a2, 0
    li      a3, 0
    li      a4, 0
    call    node_work
2:  sd      s4, ApiView_look_state(s3)
    li      t0, 1
    sd      t0, ApiView_look_copy(s3)
9:  LEAVE 0
END_FUNCTION node_api_advance

/*
 * A NODE_WORK_API_ENCODE of the operation a0 for the connection a1 with the answer flags a2, from
 * the lookup in the ApiView a3 (node.md, NODE_EV_API); then a STATE_FREE of the state when it is a
 * copy. a0 = 0, or 404 for a header with neither bytes nor a post-state. Locals: the view.
 */
LOCAL_FUNCTION node_api_encode
    FRAME 16
    sd      a3, 0(sp)
    ld      t0, ApiView_canonical(a3)
    ld      t1, ApiView_head_finalized(a3)
    slli    t1, t1, 1
    or      t0, t0, t1
    ld      t1, ApiView_is_optimistic(a3)
    slli    t1, t1, 2
    or      t0, t0, t1
    LDQ     t1, a3, ApiView_next_period     # API_VALUE_NEXT_PERIOD
    slli    t1, t1, 3
    or      t0, t0, t1
    slli    t0, t0, 16
    slli    a2, a2, 8
    or      a5, a0, a2
    mv      a4, a1
    li      t1, API_OP_GET_SPEC             # getSpec, getDebugChainHeadsV2: no state, no bytes, no values
    beq     a0, t1, 5f
    li      t1, API_OP_GET_DEBUG_CHAIN_HEADS_V2
    beq     a0, t1, 5f
    li      t1, API_OP_GET_DEBUG_FORK_CHOICE
    bne     a0, t1, 1f
5:  li      a1, 0
    li      a3, 0
    j       3f
1:  or      a5, a5, t0
    li      t0, API_OP_GET_BLOCK_HEADER
    bne     a0, t0, 2f
    ld      t0, ApiView_look_index(a3)      # getBlockHeader: the block's index + 1, its bytes or post-state
    addi    t0, t0, 1
    slli    t0, t0, 24
    or      a5, a5, t0
    li      a1, 0
    ld      a3, ApiView_look_data(a3)
    bnez    a3, 3f
    ld      t0, 0(sp)
    ld      a1, ApiView_look_state(t0)
    bnez    a1, 3f
    li      a0, 404
    UNFRAME 16
2:  ld      t0, ApiView_head_slot(a3)       # the others: the state at its slot; getStateValidator its ids
    slli    t0, t0, 24
    or      a5, a5, t0
    ld      a1, ApiView_look_state(a3)
    ld      t0, ApiView_look_data(a3)
    li      a3, 0
    li      t1, API_OP_GET_STATE_VALIDATOR
    beq     a0, t1, 4f
    li      t1, API_OP_PRODUCE_ATTESTATION_DATA
    beq     a0, t1, 4f
    li      t1, API_OP_GET_STATE_RANDAO
    beq     a0, t1, 4f
    li      t1, API_OP_GET_EPOCH_SYNC_COMMITTEES
    beq     a0, t1, 4f
    li      t1, API_OP_GET_SYNC_COMMITTEE_DUTIES
    beq     a0, t1, 4f
    li      t1, API_OP_GET_ATTESTER_DUTIES
    bne     a0, t1, 3f
4:  mv      a3, t0
3:  li      a0, NODE_WORK_API_ENCODE
    li      a2, 0
    call    node_work
    ld      t0, 0(sp)                       # a copy goes after the work
    ld      t1, ApiView_look_copy(t0)
    beqz    t1, 9f
    li      a0, NODE_ACT_STATE_FREE
    ld      a1, ApiView_look_state(t0)
    li      a2, 0
    call    node_ids
9:  li      a0, 0
    UNFRAME 16
END_FUNCTION node_api_encode

/*
 * (connection a0, route a1, answer flags a2) -> a0: a state_id of a root (node.md, NODE_EV_API): a
 * NodeApi entry with API_STREAM_LOOKUP and a NODE_WORK_API_LOOKUP with the head's post-state; 0,
 * or 404 with no head post-state. s1 the node, s6 the actions. s3 the route, s7 the flags, s8 the
 * head's post-state, s9 the connection. Locals: L the entry's index.
 */
LOCAL_FUNCTION node_api_lookup
    ENTER 16
    mv      s9, a0
    mv      s3, a1
    li      t0, API_STREAM_LOOKUP | API_STREAM_BUSY
    or      s7, a2, t0
    ld      t0, ApiRoute_response(s3)
    li      t1, API_TYPE_SSZ
    bne     t0, t1, 1f
    ori     s7, s7, API_STREAM_SSZ
1:  addi    a0, s1, Node_head_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 80f
    ld      s8, NodeBlock_state_id(a1)
    beqz    s8, 80f
    call    node_api_new
    sd      a0, L(sp)
    mv      s4, a1
    mv      a0, a1
    li      a1, NodeApi__mem
    call    lantern_zero
    sd      s9, NodeApi_connection(s4)
    ld      t0, ApiRoute_op(s3)
    sd      t0, NodeApi_op(s4)
    sd      s7, NodeApi_flags(s4)
    addi    t0, s4, NodeApi_cursor
    addi    t1, s3, ApiRoute_id_root
    COPY32  t0, t1
    ld      t0, ApiRoute_op(s3)             # the validator operations and getEpochCommittees: statuses, validator_id, epoch, slot, index, present and ids
    addi    t0, t0, -API_OP_GET_STATE_VALIDATORS
    li      t1, API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS
    bgtu    t0, t1, 2f
    ld      t0, ApiRoute_statuses(s3)
    sd      t0, (NodeApi_cursor + 32)(s4)
    ld      t0, ApiRoute_epoch(s3)
    sd      t0, (NodeApi_cursor + 104)(s4)
    ld      t0, ApiRoute_slot(s3)
    sd      t0, (NodeApi_cursor + 112)(s4)
    ld      t0, ApiRoute_index(s3)
    sd      t0, (NodeApi_cursor + 120)(s4)
    ld      t0, ApiRoute_present(s3)
    sd      t0, (NodeApi_cursor + 128)(s4)
    addi    a0, s4, (NodeApi_cursor + 40)
    addi    a1, s3, ApiRoute_validator
    li      a2, 64
    call    lantern_copy
    mv      a0, s3
    call    node_api_ids
    sd      a0, NodeApi_data(s4)
    beqz    a0, 2f
    ld      t0, NodeApi_flags(s4)
    ori     t0, t0, API_STREAM_OWN
    sd      t0, NodeApi_flags(s4)
2:  li      a0, NODE_WORK_API_LOOKUP
    mv      a1, s8
    li      a2, 0
    li      a3, 0
    mv      a4, s9
    ld      a5, L(sp)
    call    node_work
    li      a0, 0
    LEAVE 16
80: li      a0, 404
    LEAVE 16
END_FUNCTION node_api_lookup

/*
 * The NODE_EV_WORK_DONE a0 of a NODE_WORK_API_LOOKUP (node.md, lantern_node_step): the entry ends;
 * the answer for the state_id of the slot found, or 404. s1 the node, s2 the store, s5 the scratch,
 * s6 the actions. s3 the event, s4 the route, s7 the flags, s8 the view, s9 the connection, s10 the
 * operation. Locals: L the scratch's size.
 */
LOCAL_FUNCTION node_api_lookup_done
    ENTER 128
    mv      s3, a0
    ld      t0, NodeAction_arg(s3)
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 99f
    li      t2, NodeApi__mem
    mul     t0, t0, t2
    add     a0, t1, t0
    ld      s9, NodeApi_connection(a0)
    beqz    s9, 99f
    ld      t0, NodeAction_target(s3)
    bne     s9, t0, 99f
    ld      s7, NodeApi_flags(a0)
    li      t0, API_STREAM_LOOKUP
    and     t0, s7, t0
    beqz    t0, 99f
    ld      s10, NodeApi_op(a0)
    andi    t0, s7, API_STREAM_GONE
    beqz    t0, 1f
    call    node_api_end                    # API_STREAM_GONE: the entry ends, its ids with it
    j       99f
1:  ld      t0, NodeApi_data(a0)            # its ids, statuses and validator_id go to the answer
    sd      t0, (L + 16)(sp)
    ld      t0, (NodeApi_cursor + 32)(a0)
    sd      t0, (L + 24)(sp)
    mv      s4, a0
    addi    a0, sp, (L + 32)
    addi    a1, s4, (NodeApi_cursor + 40)
    li      a2, 64
    call    lantern_copy
    addi    a0, sp, (L + 96)
    addi    a1, s4, (NodeApi_cursor + 104)
    li      a2, 32
    call    lantern_copy
    mv      a0, s4
    andi    t0, s7, ~API_STREAM_OWN         # the entry ends; it owns no bytes
    sd      t0, NodeApi_flags(a0)
    call    node_api_end
    ld      t0, 0(s5)                       # the ApiView, then an ApiRoute, at the end of scratch
    sd      t0, L(sp)
    li      t1, ApiView__size + API_ROUTE_FIXED
    sub     t0, t0, t1
    sd      t0, 0(s5)
    add     s8, s5, t0
    mv      a0, s8
    call    node_api_view
    li      t0, ApiView__size
    add     s4, s8, t0
    mv      a0, s4
    li      a1, API_ROUTE_FIXED
    call    lantern_zero
    li      t0, API_ROUTE_FIXED
    sd      t0, 0(s4)
    sd      s10, ApiRoute_op(s4)
    li      t0, API_TYPE_JSON
    andi    t1, s7, API_STREAM_SSZ
    beqz    t1, 1f
    li      t0, API_TYPE_SSZ
1:  sd      t0, ApiRoute_response(s4)
    ld      t0, (L + 24)(sp)
    sd      t0, ApiRoute_statuses(s4)
    addi    a0, s4, ApiRoute_validator
    addi    a1, sp, (L + 32)
    li      a2, 64
    call    lantern_copy
    ld      t0, (L + 96)(sp)
    sd      t0, ApiRoute_epoch(s4)
    ld      t0, (L + 104)(sp)
    sd      t0, ApiRoute_slot(s4)
    ld      t0, (L + 112)(sp)
    sd      t0, ApiRoute_index(s4)
    ld      t0, (L + 120)(sp)
    sd      t0, ApiRoute_present(s4)
    li      t0, API_ID_SLOT
    sd      t0, ApiRoute_id_kind(s4)
    ld      t0, NodeEvent_index(s3)
    sd      t0, ApiRoute_id_slot(s4)
    li      a2, 404
    li      t1, -1
    beq     t0, t1, 80f
    mv      a0, s4
    mv      a1, s8
    call    node_api_state
    mv      a2, a0
    bnez    a0, 80f
    mv      a0, s8
    call    node_api_advance
    andi    a2, s7, (API_STREAM_CLOSE | API_STREAM_HTTP10)
    ld      t0, (L + 16)(sp)                # the ids go to the answer
    sd      t0, ApiView_look_data(s8)
    sd      zero, (L + 16)(sp)
    li      t0, API_OP_GET_STATE_V2
    beq     s10, t0, 3f
    li      t0, API_OP_GET_STATE_VALIDATOR
    beq     s10, t0, 2f
    addi    t0, s10, -API_OP_GET_STATE_VALIDATORS
    li      t1, API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS
    bgtu    t0, t1, 2f
3:  mv      a0, s9                          # getStateV2, the validator streams and getEpochCommittees: a stream
    mv      a1, s4
    mv      a3, s8
    call    node_api_stream
    mv      a2, a0
    bnez    a0, 80f
    j       90f
2:  mv      a0, s10                         # the others: a work
    mv      a1, s9
    mv      a3, s8
    call    node_api_encode
    mv      a2, a0
    beqz    a0, 90f
80: ld      a1, (L + 16)(sp)                # ids no answer took: they go
    beqz    a1, 82f
    sd      a2, (L + 24)(sp)
    li      a0, NODE_ACT_BYTES_FREE
    li      a2, 0
    call    node_ids
    ld      a2, (L + 24)(sp)
82: mv      a0, s9                          # an error: with close, or keep-alive for HTTP/1.0
    li      a1, 0
    li      a3, API_BODY_ERROR
    andi    a4, s7, API_R_CLOSE
    bnez    a4, 81f
    andi    t0, s7, API_STREAM_HTTP10
    beqz    t0, 81f
    li      a4, API_R_KEEP
81: call    node_api_send
90: ld      t0, L(sp)
    sd      t0, 0(s5)
99: LEAVE 128
END_FUNCTION node_api_lookup_done

/*
 * (node a0, work a1, state_a a2, scratch a3, event a4) -> a0: a NODE_WORK_API_LOOKUP of
 * lantern_node_run (node.md): at NodeEvent_index of the event, the slot whose state on the chain of
 * state_a has the root of the NodeApi entry at the work's arg, or 2^64 - 1. s1 the node, s3 the
 * state, s4 the event, s5 the root, s7 the slot, s8 the lowest slot.
 */
LOCAL_FUNCTION node_api_lookup_run
    ENTER 0
    mv      s1, a0
    mv      s3, a2
    mv      s4, a4
    li      t0, -1
    sd      t0, NodeEvent_index(s4)
    beqz    s3, 98f
    ld      t0, NodeAction_arg(a1)
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 90f
    li      t2, NodeApi__mem
    mul     t0, t0, t2
    add     t1, t1, t0
    ld      t0, NodeApi_flags(t1)
    li      t2, API_STREAM_LOOKUP
    and     t0, t0, t2
    beqz    t0, 90f
    addi    s5, t1, NodeApi_cursor
    mv      s8, a3
    ld      a0, NODE_STATE_SLOT(s3)         # the state's own root
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s3
    LDQ     a1, s1, Node_config + CONFIG_STATE_CACHE
    mv      a2, s8
    addi    a3, s4, NodeEvent_root
    FORK_CALL state_root
    bnez    a0, 97f
    ld      s7, NODE_STATE_SLOT(s3)
    addi    t0, s4, NodeEvent_root
    NE32    t0, s5, 1f
    j       80f
1:  li      t0, SLOTS_PER_HISTORICAL_ROOT   # then its state_roots, from the slot below it down
    li      s8, 0
    bltu    s7, t0, 3f
    sub     s8, s7, t0
3:  bleu    s7, s8, 90f
    addi    s7, s7, -1
    li      t0, SLOTS_PER_HISTORICAL_ROOT - 1
    and     t0, s7, t0
    slli    t0, t0, 5
    li      t1, NODE_STATE_STATE_ROOTS
    add     t0, t0, t1
    add     t0, s3, t0
    NE32    t0, s5, 3b
80: sd      s7, NodeEvent_index(s4)
90: li      a0, LANTERN_OK
    LEAVE 0
97: li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 96f
    li      t0, LANTERN_INVALID_ENCODING    # a state lantern_state_root does not take
    sd      t0, NodeEvent_result(s4)
    j       90f
96: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
98: li      a0, LANTERN_INVALID_EVENT
    LEAVE 0
END_FUNCTION node_api_lookup_run

/* ---------------------------------------------------------------- Streams (node.md, NodeApi) */

/* a0 = the free NodeApi entries of the node s1: the capacity past the count, and the free ones below it. Uses t0-t3, a7. */
LOCAL_FUNCTION node_api_free
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_api
    LDQ     t2, s1, Node_pool
    LDQ     t3, s1, Node_api
    sub     t2, t2, t3
    li      t3, NodeApi__mem
    divu    a0, t2, t3
    sub     a0, a0, t1
1:  beqz    t1, 9f
    ld      t2, NodeApi_connection(t0)
    bnez    t2, 2f
    addi    a0, a0, 1
2:  addi    t0, t0, NodeApi__mem
    addi    t1, t1, -1
    j       1b
9:  ret
END_FUNCTION node_api_free

/* a0 = the index of the NodeApi entry of the connection a0, or 2^64 - 1; a1 = the entry. Uses t0-t3, a7. */
LOCAL_FUNCTION node_api_find
    UNWIND_END_PROLOGUE
    PART    a1, t1, s1, Node_api
    li      t0, 0
    beqz    a0, 3f
1:  bgeu    t0, t1, 3f
    ld      t2, NodeApi_connection(a1)
    beq     t2, a0, 4f
    addi    a1, a1, NodeApi__mem
    addi    t0, t0, 1
    j       1b
3:  li      a0, -1
    ret
4:  mv      a0, t0
    ret
END_FUNCTION node_api_find

/* a0 = the index of a free NodeApi entry (the first free, else the next; the step checked one is free), a1 = the entry. Uses t0-t2, a7. */
LOCAL_FUNCTION node_api_new
    UNWIND_END_PROLOGUE
    PART    a1, t1, s1, Node_api
    li      t0, 0
1:  bgeu    t0, t1, 2f
    ld      t2, NodeApi_connection(a1)
    beqz    t2, 3f
    addi    a1, a1, NodeApi__mem
    addi    t0, t0, 1
    j       1b
2:  addi    t1, t1, 1
    STQ     t1, s1, Node_api + 8
3:  mv      a0, t0
    ret
END_FUNCTION node_api_new

/*
 * The end of the stream of the NodeApi entry a0: the entry is free, the api part's count drops
 * past the free entries at its end; with API_STREAM_OWN, a BYTES_FREE of its data, which node_ids
 * gives to another entry that sends the same bytes. Uses t0-t3, a0-a2, a7.
 */
LOCAL_FUNCTION node_api_end
    FRAME 16
    sd      zero, NodeApi_connection(a0)
    sd      a0, 0(sp)
    PART    t0, t1, s1, Node_api
    li      t3, NodeApi__mem
1:  beqz    t1, 2f
    addi    t2, t1, -1
    mul     t2, t2, t3
    add     t2, t0, t2
    ld      t2, NodeApi_connection(t2)
    bnez    t2, 2f
    addi    t1, t1, -1
    j       1b
2:  STQ     t1, s1, Node_api + 8
    ld      a0, 0(sp)
    ld      t0, NodeApi_flags(a0)
    andi    t0, t0, API_STREAM_OWN
    beqz    t0, 8f
    ld      a1, NodeApi_data(a0)
    li      a0, NODE_ACT_BYTES_FREE
    li      a2, 0
    call    node_ids
8:  ld      a0, 0(sp)
    ld      t0, NodeApi_flags(a0)
    srli    t0, t0, 12                      # API_STREAM_OWN_STATE
    andi    t0, t0, 1
    beqz    t0, 9f
    ld      a1, NodeApi_state(a0)
    li      a0, NODE_ACT_STATE_FREE
    li      a2, 0
    call    node_ids
9:  UNFRAME 16
END_FUNCTION node_api_end

/* A NODE_WORK_API_CHUNK of the NodeApi entry a1 at index a0, which takes API_STREAM_BUSY. */
LOCAL_FUNCTION node_api_chunk_work
    UNWIND_END_PROLOGUE
    ld      t0, NodeApi_flags(a1)
    ori     t0, t0, API_STREAM_BUSY
    sd      t0, NodeApi_flags(a1)
    mv      a5, a0
    ld      a3, NodeApi_data(a1)
    ld      a4, NodeApi_connection(a1)
    ld      a1, NodeApi_state(a1)           # a validator stream's state
    li      a0, NODE_WORK_API_CHUNK
    li      a2, 0
    j       node_work
END_FUNCTION node_api_chunk_work

/* NODE_EV_API_SENT of the connection a0: the next chunk of its stream, unless one is queued. */
LOCAL_FUNCTION node_api_sent
    FRAME 0
    call    node_api_find
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, NodeApi_op(a1)              # an event stream: its sent is 0
    li      t1, API_OP_EVENTSTREAM
    bne     t0, t1, 1f
    sd      zero, NodeApi_sent(a1)
    j       9f
1:  ld      t0, NodeApi_flags(a1)
    andi    t0, t0, API_STREAM_BUSY
    bnez    t0, 9f
    call    node_api_chunk_work
9:  UNFRAME 0
END_FUNCTION node_api_sent

# ---------------------------------------------------------------- Events (beacon-api.md, eventstream)

/*
 * (out a0, answer flags a1) -> a0: the head of an eventstream answer into the ByteList out, its
 * count set; LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL. The writer's registers; s5 out. Locals: L the flags.
 */
LOCAL_FUNCTION api_sse_head
    ENTER 16
    mv      s5, a0
    sd      a1, L(sp)
    li      s7, 1
    li      s9, 0
    addi    s6, s5, 24
    ld      t0, 0(s5)
    add     s8, s5, t0
    API_LIT api_ev_head
    ld      t0, L(sp)
    andi    t0, t0, API_ANSWER_HTTP10
    bnez    t0, 1f
    API_LIT api_ev_chunked
    ld      t0, L(sp)
    andi    t0, t0, API_ANSWER_CLOSE
    beqz    t0, 2f
1:  API_LIT api_ev_close
2:  API_LIT api_crlf
    bnez    s9, 9f
    addi    t0, s5, 24
    sub     t0, s6, t0
    li      t1, 24
    sd      t1, 8(s5)
    sd      t0, 16(s5)
    li      a0, LANTERN_OK
    LEAVE 16
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 16
END_FUNCTION api_sse_head

/*
 * (view a0, out a1, topic a2) -> a0: the text of the event of the topic, from the view's event
 * fields, into the ByteList out, its count set; LANTERN_OK, or LANTERN_BUFFER_TOO_SMALL. The
 * writer's registers; s5 out, s10 the topic.
 */
LOCAL_FUNCTION api_event_text
    ENTER 0
    mv      s4, a0
    mv      s5, a1
    mv      s10, a2
    li      s7, 1
    li      s9, 0
    addi    s6, s5, 24
    ld      t0, 0(s5)
    add     s8, s5, t0
    API_LIT api_ev_event
    li      t0, API_TOPIC_HEAD
    bne     s10, t0, 1f
    API_LIT api_ev_t_head
    j       3f
1:  li      t0, API_TOPIC_BLOCK
    bne     s10, t0, 2f
    API_LIT api_ev_t_block
    j       3f
2:  API_LIT api_ev_t_finalized
3:  API_LIT api_ev_data
    li      t0, API_TOPIC_FINALIZED_CHECKPOINT
    beq     s10, t0, 5f
    # block and head: {"slot":…,"block":…
    API_LIT api_ev_slot
    ld      a0, ApiView_event_slot(s4)
    call    api_qdec
    API_LIT api_ev_block
    addi    a0, s4, ApiView_event_block
    li      a1, 32
    call    api_qhex
    li      t0, API_TOPIC_HEAD
    bne     s10, t0, 6f
    # head: state, epoch_transition and the dependent roots
    API_LIT api_ev_state
    addi    a0, s4, ApiView_event_state
    li      a1, 32
    call    api_qhex
    API_LIT api_ev_transition
    ld      a0, ApiView_event_flags(s4)
    andi    a0, a0, 1
    call    api_bool
    API_LIT api_ev_previous
    addi    a0, s4, ApiView_event_previous
    li      a1, 32
    call    api_qhex
    API_LIT api_ev_current
    addi    a0, s4, ApiView_event_current
    li      a1, 32
    call    api_qhex
    j       6f
    # finalized_checkpoint: {"block":…,"state":…,"epoch":…
5:  API_LIT api_ev_block1
    addi    a0, s4, ApiView_event_block
    li      a1, 32
    call    api_qhex
    API_LIT api_ev_state
    addi    a0, s4, ApiView_event_state
    li      a1, 32
    call    api_qhex
    API_LIT api_k_epoch
    ld      a0, ApiView_event_epoch(s4)
    call    api_qdec
6:  API_LIT api_u_optimistic
    ld      a0, ApiView_event_flags(s4)
    srli    a0, a0, 1
    andi    a0, a0, 1
    call    api_bool
    API_LIT api_ev_end
    bnez    s9, 9f
    addi    t0, s5, 24
    sub     t0, s6, t0
    li      t1, 24
    sd      t1, 8(s5)
    sd      t0, 16(s5)
    li      a0, LANTERN_OK
    LEAVE 0
9:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 0
END_FUNCTION api_event_text

/* a0 = 1 when a NodeApi entry of eventstream has the topic a0, else 0. Uses t0-t3, a7. */
LOCAL_FUNCTION node_api_subscribed
    UNWIND_END_PROLOGUE
    PART    t0, t1, s1, Node_api
1:  beqz    t1, 8f
    ld      t2, NodeApi_connection(t0)
    beqz    t2, 2f
    ld      t2, NodeApi_op(t0)
    li      t3, API_OP_EVENTSTREAM
    bne     t2, t3, 2f
    ld      t2, NodeApi_cursor(t0)
    srl     t2, t2, a0
    andi    t2, t2, 1
    bnez    t2, 9f
2:  addi    t0, t0, NodeApi__mem
    addi    t1, t1, -1
    j       1b
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION node_api_subscribed

/* a0 = the NodeApi entries of eventstream. Uses t0-t3, a7. */
LOCAL_FUNCTION node_api_event_count
    UNWIND_END_PROLOGUE
    li      a0, 0
    PART    t0, t1, s1, Node_api
1:  beqz    t1, 9f
    ld      t2, NodeApi_connection(t0)
    beqz    t2, 2f
    ld      t2, NodeApi_op(t0)
    li      t3, API_OP_EVENTSTREAM
    bne     t2, t3, 2f
    addi    a0, a0, 1
2:  addi    t0, t0, NodeApi__mem
    addi    t1, t1, -1
    j       1b
9:  ret
END_FUNCTION node_api_event_count

/*
 * eventstream of the connection a0 with the route a1 and the answer flags a2 (node.md, NODE_EV_API):
 * a NodeApi entry of the route's topics, and a SEND of the head with last 0, its bytes the entry's
 * sent. s3 the connection, s4 the route, s7 the entry, s8 the action. Locals: L the flags.
 */
LOCAL_FUNCTION node_api_subscribe
    ENTER 16
    mv      s3, a0
    mv      s4, a1
    sd      a2, L(sp)
    call    node_api_new
    mv      s7, a1
    mv      a0, s7
    li      a1, NodeApi__mem
    call    lantern_zero
    sd      s3, NodeApi_connection(s7)
    li      t0, API_OP_EVENTSTREAM
    sd      t0, NodeApi_op(s7)
    li      t1, API_STREAM_STARTED
    ld      t2, L(sp)
    andi    t0, t2, API_ANSWER_HTTP10
    bnez    t0, 1f
    ori     t1, t1, API_STREAM_CHUNKED
    andi    t0, t2, API_ANSWER_CLOSE
    beqz    t0, 2f
    ori     t1, t1, API_STREAM_CLOSE
    j       2f
1:  ori     t1, t1, API_STREAM_CLOSE | API_STREAM_HTTP10
2:  sd      t1, NodeApi_flags(s7)
    ld      t0, ApiRoute_topics(s4)
    sd      t0, NodeApi_cursor(s7)
    li      a0, NODE_ACT_API_SEND           # the head: 56 + 128 bytes of room
    li      a1, 56 + 128
    call    node_act
    mv      s8, a0
    addi    a0, s8, 16
    li      a1, 56 + 128 - 16
    call    lantern_zero
    sd      s3, 16(s8)
    li      t0, 128 + 24
    sd      t0, 32(s8)
    addi    a0, s8, 32
    ld      a1, L(sp)
    call    api_sse_head
    ld      t0, 48(s8)
    sd      t0, NodeApi_sent(s7)
    LEAVE 16
END_FUNCTION node_api_subscribe

/*
 * The event text of the ByteList a0, of the topic a1, to each NodeApi entry of eventstream of the
 * topic (node.md, The events): a SEND of it, in one chunk with API_STREAM_CHUNKED, its bytes added
 * to the entry's sent; an entry whose sent would pass NODE_API_CHUNK gets a CLOSE and ends. s3 the
 * text, s4 the topic, s7 the index, s8 the entry, s9 the bytes sent, s10 the action.
 */
LOCAL_FUNCTION node_api_events
    ENTER 0
    mv      s3, a0
    mv      s4, a1
    li      s7, 0
1:  PART    t0, t1, s1, Node_api
    bgeu    s7, t1, 9f
    li      t2, NodeApi__mem
    mul     t2, t2, s7
    add     s8, t0, t2
    ld      t0, NodeApi_connection(s8)
    beqz    t0, 8f
    ld      t0, NodeApi_op(s8)
    li      t1, API_OP_EVENTSTREAM
    bne     t0, t1, 8f
    ld      t0, NodeApi_cursor(s8)
    srl     t0, t0, s4
    andi    t0, t0, 1
    beqz    t0, 8f
    ld      s9, 16(s3)
    ld      t0, NodeApi_flags(s8)
    andi    t0, t0, API_STREAM_CHUNKED
    beqz    t0, 2f
    addi    s9, s9, 8                       # a chunk: 4 hex digits, CRLF, the text, CRLF
2:  ld      t0, NodeApi_sent(s8)
    add     t0, t0, s9
    li      t1, NODE_API_CHUNK
    bgtu    t0, t1, 5f
    sd      t0, NodeApi_sent(s8)
    addi    a1, s9, 56 + 7
    andi    a1, a1, -8
    li      a0, NODE_ACT_API_SEND
    call    node_act
    mv      s10, a0
    addi    a0, s10, 16
    ld      a1, 0(s10)
    addi    a1, a1, -16
    call    lantern_zero
    ld      t0, NodeApi_connection(s8)
    sd      t0, 16(s10)
    ld      t0, 0(s10)
    addi    t0, t0, -32
    sd      t0, 32(s10)
    li      t0, 24
    sd      t0, 40(s10)
    sd      s9, 48(s10)
    addi    a0, s10, 56
    ld      t0, NodeApi_flags(s8)
    andi    t0, t0, API_STREAM_CHUNKED
    beqz    t0, 3f
    ld      t1, 16(s3)                      # the size in 4 lower case hex digits, CRLF
    li      t2, 12
4:  srl     t3, t1, t2
    andi    t3, t3, 15
    li      t4, 10
    bltu    t3, t4, 41f
    addi    t3, t3, 0x61 - 10 - 0x30
41: addi    t3, t3, 0x30
    sb      t3, 0(a0)
    addi    a0, a0, 1
    addi    t2, t2, -4
    bgez    t2, 4b
    li      t3, 0x0d
    sb      t3, 0(a0)
    li      t3, 0x0a
    sb      t3, 1(a0)
    addi    a0, a0, 2
3:  addi    a1, s3, 24
    ld      a2, 16(s3)
    call    lantern_copy
    ld      t0, NodeApi_flags(s8)
    andi    t0, t0, API_STREAM_CHUNKED
    beqz    t0, 8f
    ld      t0, 16(s3)                      # and CRLF after the text
    add     t0, t0, s10
    li      t1, 0x0d
    sb      t1, 56 + 6(t0)
    li      t1, 0x0a
    sb      t1, 56 + 7(t0)
    j       8f
5:  li      a0, NODE_ACT_API_CLOSE          # the stream falls behind: a CLOSE, and it ends
    li      a1, NODE_ACT_API_CLOSE_SIZE
    call    node_act
    ld      t0, NodeApi_connection(s8)
    sd      t0, 16(a0)
    mv      a0, s8
    call    node_api_end
8:  addi    s7, s7, 1
    j       1b
9:  LEAVE 0
END_FUNCTION node_api_events

/*
 * The block event of the NodeBlock entry a0 (node.md, The events), with an entry of the topic: its
 * text in a ByteList at the end of scratch, after the ApiView of its values. s3 the block, s4 the
 * view, s7 the ByteList. Locals: L the scratch's size.
 */
LOCAL_FUNCTION node_api_block_event
    ENTER 16
    mv      s3, a0
    li      a0, API_TOPIC_BLOCK
    call    node_api_subscribed
    beqz    a0, 9f
    ld      t0, 0(s5)
    sd      t0, L(sp)
    li      t1, ApiView__size + 1024
    bltu    t0, t1, 9f
    sub     t0, t0, t1
    sd      t0, 0(s5)
    add     s4, s5, t0
    li      t1, ApiView__size
    add     s7, s4, t1
    li      t0, 1024
    sd      t0, 0(s7)
    li      t0, 24
    sd      t0, 8(s7)
    sd      zero, 16(s7)
    ld      t0, NodeBlock_slot(s3)
    sd      t0, ApiView_event_slot(s4)
    addi    t0, s4, ApiView_event_block
    COPY32  t0, s3
    ld      t0, NodeBlock_payload_status(s3)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t0, t0
    slli    t0, t0, 1
    sd      t0, ApiView_event_flags(s4)
    mv      a0, s4
    mv      a1, s7
    li      a2, API_TOPIC_BLOCK
    call    api_event_text
    bnez    a0, 8f
    mv      a0, s7
    li      a1, API_TOPIC_BLOCK
    call    node_api_events
8:  ld      t0, L(sp)
    sd      t0, 0(s5)
9:  LEAVE 16
END_FUNCTION node_api_block_event

/*
 * The head and finalized_checkpoint events at a quiet point (node.md, The events): with no block
 * vote queued, a head other than event_head, then a finalized epoch above event_epoch; each a
 * NODE_WORK_API_EVENT when an entry has its topic. s3 the block, s4 the values.
 */
.if API_TOPIC_HEAD
.error "node_api_head_events: the arg of a head event takes API_TOPIC_HEAD as 0"
.endif
LOCAL_FUNCTION node_api_head_events
    ENTER 0
    LDQ     t0, s1, Node_event_votes
    bnez    t0, 9f
    ADDQ    t1, s1, Node_event_head
    li      t4, 0
0:  add     t2, s1, t4
    ld      t2, Node_head_root(t2)
    add     t3, t1, t4
    ld      t3, 0(t3)
    bne     t2, t3, 1f
    addi    t4, t4, 8
    li      t0, 32
    bltu    t4, t0, 0b
    j       5f
1:  addi    a0, s1, Node_head_root
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 5f
    mv      s3, a1
    ld      t0, NodeBlock_slot(s3)          # epoch_transition, execution_optimistic
    li      t1, SLOTS_PER_EPOCH
    divu    t2, t0, t1
    LDQ     t3, s1, Node_event_slot
    divu    t3, t3, t1
    sltu    s4, t3, t2
    ld      t4, NodeBlock_payload_status(s3)
    addi    t4, t4, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t4, t4
    slli    t4, t4, 1
    or      s4, s4, t4
    STQ     t0, s1, Node_event_slot
    ADDQ    t0, s1, Node_event_head
    COPY32  t0, s3
    ld      a0, NodeBlock_state_id(s3)      # the pool's checks at the new head
    call    node_pool_checks
    li      a0, API_TOPIC_HEAD
    call    node_api_subscribed
    beqz    a0, 5f
    ld      a1, NodeBlock_state_id(s3)
    beqz    a1, 5f
    li      a0, NODE_WORK_API_EVENT
    li      a2, 0
    li      a3, 0
    li      a4, 0
    slli    a5, s4, 8                       # API_TOPIC_HEAD is 0
    call    node_work
5:  ld      t0, Store_finalized_checkpoint(s2)
    LDQ     t1, s1, Node_event_epoch
    bleu    t0, t1, 9f
    STQ     t0, s1, Node_event_epoch
    li      a0, API_TOPIC_FINALIZED_CHECKPOINT
    call    node_api_subscribed
    beqz    a0, 9f
    addi    a0, s2, Store_finalized_checkpoint + 8
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, NodeBlock_payload_status(a1)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    t0, t0
    slli    t0, t0, 9
    ld      a5, Store_finalized_checkpoint(s2)
    slli    a5, a5, 16
    or      a5, a5, t0
    addi    a5, a5, API_TOPIC_FINALIZED_CHECKPOINT
    ld      a3, NodeBlock_data_id(a1)       # the block's bytes, else its post-state
    ld      t2, NodeBlock_state_id(a1)
    beqz    a3, 6f
    li      t2, 0
6:  or      t0, a3, t2
    beqz    t0, 9f
    mv      a1, t2
    li      a0, NODE_WORK_API_EVENT
    li      a2, 0
    li      a4, 0
    call    node_work
9:  LEAVE 0
END_FUNCTION node_api_head_events

/* NODE_EV_WORK_DONE a0 of a NODE_WORK_API_EVENT: LANTERN_VALID, its text to the entries of its topic. */
LOCAL_FUNCTION node_api_event_done
    FRAME 0
    ld      t0, NodeEvent_result(a0)
    bnez    t0, 9f
    ld      a1, NodeAction_arg(a0)
    andi    a1, a1, 255
    addi    a0, a0, NodeEvent_chunk
    call    node_api_events
9:  UNFRAME 0
END_FUNCTION node_api_event_done

/*
 * (node a0, work a1, state_a a2, data a3, scratch a4, event a5, room a6) -> a0: a NODE_WORK_API_EVENT
 * of lantern_node_run (node.md): the event's text at NodeEvent_chunk of the event. s1 the node, s2
 * the work, s3 state_a, s4 data, s5 the scratch, s6 the event, s7 the ApiView at the end of
 * scratch, s8 the topic, s9 the room. Locals: L the scratch's size, L+8 a Result, L+16 a blob count.
 */
LOCAL_FUNCTION node_api_event_run
    ENTER 32
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    mv      s6, a5
    mv      s9, a6
    ld      t0, NodeAction_arg(s2)
    andi    s8, t0, 255
    ld      t0, 0(s5)                       # the ApiView at the end of scratch, with the work's values
    sd      t0, L(sp)
    li      t1, ApiView__size
    bltu    t0, t1, 7f
    sub     t0, t0, t1
    sd      t0, 0(s5)
    add     s7, s5, t0
    ld      t0, NodeAction_arg(s2)
    srli    t1, t0, 8
    andi    t1, t1, 255
    sd      t1, ApiView_event_flags(s7)
    srli    t1, t0, 16
    sd      t1, ApiView_event_epoch(s7)
    li      t0, API_TOPIC_HEAD
    beq     s8, t0, 1f
    li      t0, API_TOPIC_FINALIZED_CHECKPOINT
    bne     s8, t0, 8f
    bnez    s4, 3f
1:  beqz    s3, 8f                          # of a post-state: lantern_node_event_roots
    ld      a0, NODE_STATE_SLOT(s3)
    sd      a0, ApiView_event_slot(s7)
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s3
    addi    a1, s1, Node_config
    mv      a2, s5
    addi    a3, s7, ApiView_event_block
    FORK_CALL node_event_roots
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    beqz    a0, 5f
    sd      a0, NodeEvent_result(s6)
    j       9f
3:  ld      t0, 16(s4)                      # of a block's bytes: its state_root and its root
    li      t1, 100 + 84
    bltu    t0, t1, 41f
    ld      t0, 8(s4)
    add     t0, s4, t0
    addi    a1, t0, 100 + 48
    addi    a0, s7, ApiView_event_state
    li      a2, 32
    call    lantern_copy
    ld      t0, 8(s4)
    add     t0, s4, t0
    lwu     a0, 100(t0)
    lwu     t1, 104(t0)
    slli    t1, t1, 32
    or      a0, a0, t1
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s4
    mv      a1, s5
    addi    a2, s7, ApiView_event_block
    addi    a3, sp, L + 8
    addi    a4, sp, L + 16
    FORK_CALL node_block_root
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 71f
    bnez    a0, 41f
    ld      t0, (L + 8)(sp)
    bnez    t0, 41f
5:  addi    t0, s9, -NodeEvent_chunk        # the text, in the event
    andi    t0, t0, -8
    li      t1, 24
    bltu    t0, t1, 71f
    sd      t0, NodeEvent_chunk(s6)
    mv      a0, s7
    addi    a1, s6, NodeEvent_chunk
    mv      a2, s8
    call    api_event_text
    bnez    a0, 71f
    ld      t0, (NodeEvent_chunk + 16)(s6)  # the event's size covers the text
    addi    t0, t0, NodeEvent_chunk + 24 + 7
    andi    t0, t0, -8
    sd      t0, 0(s6)
    addi    t0, t0, -NodeEvent_chunk
    sd      t0, NodeEvent_chunk(s6)
    j       9f
41: li      t0, LANTERN_INVALID_ENCODING
    sd      t0, NodeEvent_result(s6)
9:  ld      t0, L(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 32
8:  ld      t0, L(sp)
    sd      t0, 0(s5)
    li      a0, LANTERN_INVALID_EVENT
    LEAVE 32
71: ld      t0, L(sp)
    sd      t0, 0(s5)
7:  li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 32
END_FUNCTION node_api_event_run

/* NODE_EV_API_CLOSED of the connection a0: its stream ends, or with a chunk queued takes API_STREAM_GONE. */
LOCAL_FUNCTION node_api_closed
    FRAME 0
    call    node_api_find
    li      t0, -1
    beq     a0, t0, 9f
    ld      t0, NodeApi_flags(a1)
    andi    t1, t0, API_STREAM_BUSY
    beqz    t1, 1f
    ori     t0, t0, API_STREAM_GONE
    sd      t0, NodeApi_flags(a1)
    j       9f
1:  mv      a0, a1
    call    node_api_end
9:  UNFRAME 0
END_FUNCTION node_api_closed

/*
 * (connection a0, route a1, flags a2, view a3) -> a0: a stream of getBlockV2, getStateV2 or a validator operation of the
 * lookup in the view (node.md, NODE_EV_API): 0 once it started, else the status of the error to
 * answer. flags: API_STREAM_CLOSE and API_STREAM_HTTP10. s1 the node, s6 the actions. s3 the data,
 * s7 the route, s8 the view, s9 the connection, s10 the flags. Locals: L the entry's index, L+8 the
 * entry.
 */
LOCAL_FUNCTION node_api_stream
    ENTER 32
    sd      zero, (L + 16)(sp)
    mv      s9, a0
    mv      s7, a1
    mv      s10, a2
    mv      s8, a3
    ld      t0, ApiRoute_response(s7)       # SSZ, else JSON; the values of the JSON
    li      t1, API_TYPE_SSZ
    bne     t0, t1, 1f
    ori     s10, s10, API_STREAM_SSZ
1:  ld      t0, ApiView_is_optimistic(s8)
    beqz    t0, 2f
    ori     s10, s10, API_STREAM_OPTIMISTIC
2:  ld      t0, ApiView_head_finalized(s8)
    beqz    t0, 3f
    ori     s10, s10, API_STREAM_FINALIZED
3:  ld      t0, ApiRoute_op(s7)
    li      t1, API_OP_GET_STATE_V2
    beq     t0, t1, 5f
    li      t1, API_OP_GET_BLOCK_V2
    beq     t0, t1, 4f
    li      t1, API_OP_GET_BLOCK_ATTESTATIONS_V2
    beq     t0, t1, 4f
    li      t1, API_OP_GET_BLINDED_BLOCK
    beq     t0, t1, 4f
    ld      s3, ApiView_look_data(s8)       # a validator stream: its ids, and its state
    beqz    s3, 31f
    ori     s10, s10, API_STREAM_OWN
31: ld      t0, ApiView_look_copy(s8)
    beqz    t0, 32f
    li      t0, API_STREAM_OWN_STATE
    or      s10, s10, t0
32: ld      t0, ApiView_look_state(s8)
    sd      t0, (L + 16)(sp)
    ld      t0, ApiRoute_op(s7)             # getEpochCommittees: its epoch, else 400 and no stream
    li      t1, API_OP_GET_EPOCH_COMMITTEES
    bne     t0, t1, 34f
    mv      a0, s7
    mv      a1, s8
    call    node_api_committees_check
    sd      a0, (L + 24)(sp)
    li      t0, -1
    bne     a0, t0, 6f
    j       331f
34: addi    t1, t0, -API_OP_GET_PENDING_CONSOLIDATIONS  # the pending lists: 400 for a state before electra, and no stream
    li      t2, 2
    bgtu    t1, t2, 6f
    ld      a0, ApiView_head_slot(s8)
    addi    a1, s1, Node_config
    call    node_fork
    li      t0, FORK_ELECTRA
    bgeu    a0, t0, 6f
331: ld     t0, ApiView_look_copy(s8)
    beqz    t0, 33f
    li      a0, NODE_ACT_STATE_FREE
    ld      a1, ApiView_look_state(s8)
    li      a2, 0
    call    node_ids
33: li      a0, 400
    LEAVE 32
4:  ld      s3, ApiView_look_data(s8)       # getBlockV2: the block's bytes
    beqz    s3, 80f
    j       6f
5:  call    node_new_id                     # getStateV2: the state's SSZ bytes, as a new id the stream owns
    mv      s3, a0
    li      a0, NODE_ACT_STATE_BYTES
    li      a1, NODE_ACT_STATE_BYTES_SIZE
    call    node_act
    ld      t0, ApiView_look_state(s8)
    sd      t0, 16(a0)
    sd      s3, 24(a0)
    ori     s10, s10, API_STREAM_OWN
    ld      t0, ApiView_look_copy(s8)       # a copy goes after its bytes
    beqz    t0, 6f
    li      a0, NODE_ACT_STATE_FREE
    ld      a1, ApiView_look_state(s8)
    li      a2, 0
    call    node_ids
6:  call    node_api_new                    # the entry
    sd      a0, (L + 0)(sp)
    sd      a1, (L + 8)(sp)
    mv      a0, a1
    li      a1, NodeApi__mem
    call    lantern_zero
    ld      a0, ApiView_head_slot(s8)
    ld      a1, (L + 8)(sp)
    sd      a0, NodeApi_slot(a1)
    addi    a1, s1, Node_config
    call    node_fork
    ld      a1, (L + 8)(sp)
    sd      a0, NodeApi_fork(a1)
    sd      s9, NodeApi_connection(a1)
    ld      t0, ApiRoute_op(s7)
    sd      t0, NodeApi_op(a1)
    sd      s10, NodeApi_flags(a1)
    sd      s3, NodeApi_data(a1)
    ld      t0, (L + 16)(sp)                # a validator stream: its state and status bits
    sd      t0, NodeApi_state(a1)
    ld      t0, ApiRoute_statuses(s7)
    sd      t0, NodeApi_statuses(a1)
    ld      t0, ApiRoute_op(s7)             # getEpochCommittees: its cursor
    li      t1, API_OP_GET_EPOCH_COMMITTEES
    bne     t0, t1, 7f
    mv      a0, a1
    mv      a1, s7
    ld      a2, (L + 24)(sp)
    call    node_api_committees_cursor
7:  ld      a0, (L + 0)(sp)
    ld      a1, (L + 8)(sp)
    call    node_api_chunk_work
    li      a0, 0
    LEAVE 32
80: li      a0, 404
    LEAVE 32
END_FUNCTION node_api_stream

/*
 * The NODE_EV_WORK_DONE a0 of a NODE_WORK_API_CHUNK (node.md, lantern_node_step). s1 the node,
 * s6 the actions. s3 the event, s4 the entry, s7 the action, s8 the flags.
 */
LOCAL_FUNCTION node_api_chunk_done
    ENTER 0
    mv      s3, a0
    ld      t0, NodeAction_arg(s3)
    PART    t1, t2, s1, Node_api
    bgeu    t0, t2, 99f
    li      t3, NodeApi__mem
    mul     t0, t0, t3
    add     s4, t1, t0
    ld      t0, NodeApi_connection(s4)
    beqz    t0, 99f
    ld      t1, NodeAction_target(s3)
    bne     t0, t1, 99f
    ld      s8, NodeApi_flags(s4)
    andi    s8, s8, ~API_STREAM_BUSY
    sd      s8, NodeApi_flags(s4)
    andi    t0, s8, API_STREAM_GONE
    bnez    t0, 90f                         # API_STREAM_GONE: the stream ends
    ld      t0, NodeEvent_result(s3)
    bnez    t0, 50f
    ld      t0, NodeEvent_api(s3)           # valid: the entry takes sent, flags and cursor
    sd      t0, NodeApi_sent(s4)
    ld      t0, (NodeEvent_api + 8)(s3)
    andi    t0, t0, ~(API_STREAM_BUSY | API_STREAM_OWN)
    andi    t1, s8, API_STREAM_OWN
    or      s8, t0, t1
    sd      s8, NodeApi_flags(s4)
    addi    a0, s4, NodeApi_cursor
    addi    a1, s3, (NodeEvent_api + 16)
    li      a2, JSON_CURSOR_SIZE
    call    lantern_copy
    li      t0, API_STREAM_ITEM_DONE        # API_STREAM_ITEM_DONE: the pool stream's next entry
    and     t0, s8, t0
    beqz    t0, 1f
    li      t0, ~API_STREAM_ITEM_DONE
    and     s8, s8, t0
    sd      s8, NodeApi_flags(s4)
    mv      a0, s4
    ld      t0, NodeApi_op(s4)              # getBlockHeaders: its next item
    li      t1, API_OP_GET_BLOCK_HEADERS
    bne     t0, t1, 2f
    ld      a1, NodeApi_slot(s4)
    addi    a1, a1, 1
    call    node_headers_next
    j       3f
2:  li      t1, API_OP_GET_BLOB_SIDECARS    # a sidecar stream: its sidecar from member + 1 on
    beq     t0, t1, 4f
    li      t1, API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    bne     t0, t1, 5f
4:  ld      a1, NodeApi_member(s4)
    addi    a1, a1, 1
    call    node_sidecar_next
    j       3f
5:  call    node_api_pool_advance
3:  ld      s8, NodeApi_flags(s4)
1:  ld      a1, (NodeEvent_api_bytes + 16)(s3)  # the chunk in a SEND
    addi    a1, a1, (56 + 7)
    andi    a1, a1, -8
    li      a0, NODE_ACT_API_SEND
    call    node_act
    mv      s7, a0
    ld      t0, NodeApi_connection(s4)
    sd      t0, 16(s7)
    srli    t0, s8, 10                      # last: API_STREAM_DONE
    andi    t0, t0, 1
    sd      t0, 24(s7)
    ld      t0, 0(s7)
    addi    t0, t0, -32
    sd      t0, 32(s7)
    li      t0, 24
    sd      t0, 40(s7)
    ld      a2, (NodeEvent_api_bytes + 16)(s3)
    sd      a2, 48(s7)
    addi    a0, s7, 56
    ld      t0, (NodeEvent_api_bytes + 8)(s3)
    addi    a1, s3, NodeEvent_api_bytes
    add     a1, a1, t0
    call    lantern_copy
    ld      t0, 48(s7)                      # zero bytes to the size
    addi    a0, s7, 56
    add     a0, a0, t0
    ld      a1, 0(s7)
    addi    a1, a1, -56
    sub     a1, a1, t0
    call    lantern_zero
    srli    t0, s8, 10                      # not the last: the next chunk at the next API_SENT
    andi    t0, t0, 1
    beqz    t0, 99f
    andi    t0, s8, API_STREAM_CLOSE
    beqz    t0, 90f
    j       60f
50: andi    t0, s8, API_STREAM_STARTED      # another result: before API_STREAM_STARTED the error 500, after it a CLOSE
    bnez    t0, 60f
    ld      a0, NodeApi_connection(s4)
    li      a1, 0
    li      a2, 500
    li      a3, API_BODY_ERROR
    andi    a4, s8, API_R_CLOSE             # API_STREAM_CLOSE is API_R_CLOSE; HTTP/1.0 kept open says so
    bnez    a4, 51f
    andi    t0, s8, API_STREAM_HTTP10
    beqz    t0, 51f
    li      a4, API_R_KEEP
51: call    node_api_send
    j       90f
60: li      a0, NODE_ACT_API_CLOSE
    li      a1, NODE_ACT_API_CLOSE_SIZE
    call    node_act
    ld      t0, NodeApi_connection(s4)
    sd      t0, 16(a0)
90: mv      a0, s4
    call    node_api_end
99: LEAVE 0
END_FUNCTION node_api_chunk_done

/* The name of the fork a0 joins the response. */
LOCAL_FUNCTION api_fork_name
    UNWIND_END_PROLOGUE
    ADDRESS t0, api_forks
    slli    a0, a0, 4
    add     a0, t0, a0
    lbu     a1, 0(a0)
    addi    a0, a0, 1
    j       api_put
END_FUNCTION api_fork_name

/*
 * The head of a streamed answer (beacon-api.md, Common rules) for the flags at NodeEvent_api + 8
 * of the event s5 and the fork of the entry s4: with Content-Length a0, or for a0 = 2^64 - 1
 * Transfer-Encoding: chunked when API_STREAM_CHUNKED is set, else neither. Locals: a0.
 */
LOCAL_FUNCTION api_stream_head
    FRAME 16
    sd      a0, 0(sp)
    API_LIT api_ok
    ld      t0, (NodeEvent_api + 8)(s5)
    andi    t0, t0, API_STREAM_SSZ
    beqz    t0, 1f
    API_LIT api_octet
    j       2f
1:  API_LIT api_type
2:  ld      t0, NodeApi_op(s4)              # Eth-Consensus-Version: of getBlockV2 and getStateV2
    li      t1, API_OP_GET_BLOCK_V2
    beq     t0, t1, 21f
    li      t1, API_OP_GET_BLOCK_ATTESTATIONS_V2
    beq     t0, t1, 21f
    li      t1, API_OP_GET_BLINDED_BLOCK
    beq     t0, t1, 21f
    li      t1, API_OP_GET_STATE_V2
    beq     t0, t1, 21f
    li      t1, API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    beq     t0, t1, 21f
    li      t1, API_OP_GET_POOL_ATTESTATIONS_V2
    beq     t0, t1, 21f
    li      t1, API_OP_GET_BLOB_SIDECARS
    beq     t0, t1, 21f
    li      t1, API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    beq     t0, t1, 21f
    addi    t1, t0, -API_OP_GET_PENDING_CONSOLIDATIONS  # and of the pending lists
    li      t2, 2
    bgtu    t1, t2, 22f
21: API_LIT api_version
    ld      a0, NodeApi_fork(s4)
    call    api_fork_name
    API_LIT api_crlf
22: ld      a0, 0(sp)
    li      t0, -1
    beq     a0, t0, 3f
    API_LIT api_length
    ld      a0, 0(sp)
    call    api_dec
    API_LIT api_crlf
    j       4f
3:  ld      t0, (NodeEvent_api + 8)(s5)
    andi    t0, t0, API_STREAM_CHUNKED
    beqz    t0, 4f
    API_LIT api_chunked
4:  ld      t0, (NodeEvent_api + 8)(s5)
    andi    t1, t0, API_STREAM_CLOSE
    beqz    t1, 5f
    API_LIT api_close
    j       6f
5:  andi    t1, t0, API_STREAM_HTTP10
    beqz    t1, 6f
    API_LIT api_keep
6:  API_LIT api_crlf
    UNFRAME 16
END_FUNCTION api_stream_head

/* The 4 lower case hex digits of a0 at a1. Uses t0-t2, a0, a2. */
LOCAL_FUNCTION api_hex4
    UNWIND_END_PROLOGUE
    ADDRESS t0, api_hex
    li      t2, 3
1:  andi    t1, a0, 15
    add     t1, t0, t1
    lbu     t1, 0(t1)
    add     a2, a1, t2
    sb      t1, 0(a2)
    srli    a0, a0, 4
    addi    t2, t2, -1
    bgez    t2, 1b
    ret
END_FUNCTION api_hex4

/*
 * The JSON of the entry s4's SSZ bytes s3 from the cursor at NodeEvent_api + 16 of the event s5,
 * at the writer's cursor s6 up to s8 less a byte, through the event's ByteList at
 * NodeEvent_api_bytes whose bytes start at s10; then } once it is whole. a0 = 1 when whole, 0
 * when more is to come, 2 for bytes that are no encoding.
 */
LOCAL_FUNCTION api_stream_json
    FRAME 0
    ld      t0, NodeApi_op(s4)              # a pool stream: its entries
    li      t1, API_OP_GET_POOL_VOLUNTARY_EXITS
    beq     t0, t1, 4f
    li      t1, API_OP_GET_POOL_PROPOSER_SLASHINGS
    beq     t0, t1, 4f
    li      t1, API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    beq     t0, t1, 4f
    li      t1, API_OP_GET_POOL_ATTESTATIONS_V2
    beq     t0, t1, 4f
    li      t1, API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES
    bne     t0, t1, 3f
4:  call    api_pool_json
    UNFRAME 0
3:  ld      t0, NodeApi_op(s4)
    li      t1, API_OP_GET_BLOCK_HEADERS
    bne     t0, t1, 32f
    call    api_headers_json
    UNFRAME 0
32: ld      t0, NodeApi_op(s4)
    li      t1, API_OP_GET_BLOB_SIDECARS
    beq     t0, t1, 33f
    li      t1, API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    bne     t0, t1, 34f
33: call    api_sidecar_body
    UNFRAME 0
34: ld      t0, NodeApi_op(s4)              # the pending streams: their items, of the state s3
    addi    t1, t0, -API_OP_GET_PENDING_CONSOLIDATIONS
    li      t2, 2
    bgtu    t1, t2, 31f
    call    api_pending_json
    UNFRAME 0
31: ld      t0, NodeApi_op(s4)              # the validator streams: their items, of the state s3
    li      t1, API_OP_GET_BLOCK_V2
    beq     t0, t1, 1f
    li      t1, API_OP_GET_BLOCK_ATTESTATIONS_V2
    beq     t0, t1, 1f
    li      t1, API_OP_GET_BLINDED_BLOCK
    beq     t0, t1, 1f
    li      t1, API_OP_GET_STATE_V2
    beq     t0, t1, 1f
    li      t1, API_OP_GET_EPOCH_COMMITTEES
    beq     t0, t1, 2f
    call    api_validators_json
    UNFRAME 0
2:  call    api_committees_json
    UNFRAME 0
1:  addi    t0, s5, NodeEvent_api_bytes     # the ByteList: its room to s8 - 1, its bytes to s6
    addi    t1, s8, -1
    sub     t1, t1, t0
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    sub     t1, s6, s10
    sd      t1, 16(t0)
    ld      t1, NodeApi_op(s4)
    addi    t1, t1, -API_OP_GET_STATE_V2
    seqz    a0, t1                          # NODE_JSON_STATE, else NODE_JSON_BLOCK; NODE_JSON_ATTESTATIONS of a block's
    ld      t1, NodeApi_op(s4)
    li      t2, API_OP_GET_BLOCK_ATTESTATIONS_V2
    bne     t1, t2, 121f
    li      a0, NODE_JSON_ATTESTATIONS
121: li     t2, API_OP_GET_BLINDED_BLOCK
    bne     t1, t2, 122f
    li      a0, NODE_JSON_BLINDED_BLOCK
122:
    mv      a1, s3
    addi    a2, s5, (NodeEvent_api + 16)
    addi    a3, s5, NodeEvent_api_bytes
    ld      t6, NodeApi_fork(s4)
    FORK_CALL node_json
    ld      t0, (NodeEvent_api_bytes + 16)(s5)
    add     s6, s10, t0
    li      t0, LANTERN_JSON_MORE
    beq     a0, t0, 8f
    bnez    a0, 7f
    API_LIT api_end1
    li      a0, 1
    UNFRAME 0
7:  li      a0, 2
    UNFRAME 0
8:  li      a0, 0
    UNFRAME 0
END_FUNCTION api_stream_json

/*
 * (node a0, work a1, data a2, scratch a3, event a4, room a5, state_a a6) -> a0: a
 * NODE_WORK_API_CHUNK of lantern_node_run (node.md): the next chunk of the NodeApi entry at the
 * work's arg, from the SSZ bytes in data, or for a validator stream from state_a and the ids in
 * data, at NodeEvent_api of the event, whose buffer has room bytes. s3 data (a validator stream's
 * state once its selection is made), s4 the entry, s5 the event; the writer's s6-s9 (api_put); s10
 * where the chunk's bytes start. Locals: L the end of the chunk's room, L+8 the SSZ bytes, L+16
 * their count, L+24 the body's start, L+32 the head's bytes, L+40 1 for a validator stream, L+48
 * state_a, L+56 the scratch.
 */
LOCAL_FUNCTION node_api_chunk_run
    ENTER 80
    mv      s3, a2
    mv      s5, a4
    sd      a6, (L + 48)(sp)
    sd      a3, (L + 56)(sp)
    sd      a0, (L + 64)(sp)
    ld      t0, NodeAction_arg(a1)          # the entry
    PART    t1, t2, a0, Node_api
    bgeu    t0, t2, 98f
    li      t3, NodeApi__mem
    mul     t0, t0, t3
    add     s4, t1, t0
    ld      t0, NodeApi_connection(s4)
    beqz    t0, 98f
    ld      t0, NodeApi_op(s4)
    li      t1, API_OP_GET_BLOCK_V2
    beq     t0, t1, 1f
    li      t1, API_OP_GET_BLOCK_ATTESTATIONS_V2
    beq     t0, t1, 1f
    li      t1, API_OP_GET_BLINDED_BLOCK
    beq     t0, t1, 1f
    li      t1, API_OP_GET_STATE_V2
    beq     t0, t1, 1f
    li      t2, 3                           # a pool stream (3): data 0 at its end
    li      t1, API_OP_GET_POOL_VOLUNTARY_EXITS
    beq     t0, t1, 103f
    li      t1, API_OP_GET_POOL_PROPOSER_SLASHINGS
    beq     t0, t1, 103f
    li      t1, API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    beq     t0, t1, 103f
    li      t1, API_OP_GET_POOL_ATTESTATIONS_V2
    beq     t0, t1, 103f
    li      t1, API_OP_GET_POOL_BLS_TO_EXECUTION_CHANGES
    beq     t0, t1, 103f
    li      t2, 6                           # a sidecar stream (6): data 0 at its end
    li      t1, API_OP_GET_BLOB_SIDECARS
    beq     t0, t1, 103f
    li      t1, API_OP_GET_DEBUG_DATA_COLUMN_SIDECARS
    beq     t0, t1, 103f
    li      t2, 5                           # getBlockHeaders (5): an item of data or state, none at its end
    li      t1, API_OP_GET_BLOCK_HEADERS
    beq     t0, t1, 103f
    addi    t1, t0, -API_OP_GET_PENDING_CONSOLIDATIONS  # a pending stream (4): a state
    li      t2, 2
    bgtu    t1, t2, 104f
    ld      t2, (L + 48)(sp)
    beqz    t2, 98f
    li      t2, 4
    j       103f
104: li     t1, API_OP_GET_STATE_VALIDATOR  # a validator stream: a state
    beq     t0, t1, 98f
    addi    t0, t0, -API_OP_GET_STATE_VALIDATORS
    li      t1, API_OP_GET_EPOCH_COMMITTEES - API_OP_GET_STATE_VALIDATORS
    bgtu    t0, t1, 98f
    ld      t2, (L + 48)(sp)
    beqz    t2, 98f
    li      t2, 1                           # a validator stream (1) or getEpochCommittees (2)
    bne     t0, t1, 103f
    li      t2, 2
103: sd     t2, (L + 40)(sp)
    j       101f
1:  beqz    s3, 98f
    sd      zero, (L + 40)(sp)
101: li     t0, NodeEvent_api_bytes + 24    # the chunk's room: at most NODE_API_CHUNK
    bltu    a5, t0, 97f
    sub     t0, a5, t0
    andi    t0, t0, -8
    li      t1, NODE_API_CHUNK
    bleu    t0, t1, 2f
    mv      t0, t1
2:  ld      t2, NodeApi_flags(s4)
    andi    t2, t2, API_STREAM_STARTED
    li      t1, NODE_API_FIRST_ROOM
    beqz    t2, 3f
    ld      t2, (L + 40)(sp)                # a validator stream: an item in every chunk
    beqz    t2, 104f
    li      t3, 3
    bne     t2, t3, 3f
104: li     t1, 64
3:  bltu    t0, t1, 97f
    addi    s10, s5, (NodeEvent_api_bytes + 24)
    add     t0, s10, t0
    sd      t0, (L + 0)(sp)
    ld      t1, (L + 40)(sp)
    beqz    t1, 102f
    li      t2, 3
    beq     t1, t2, 5f
    li      t2, 5
    beq     t1, t2, 5f
    li      t2, 6
    beq     t1, t2, 5f
    ld      t1, (L + 48)(sp)                # the state at the entry's slot
    ld      t1, NODE_STATE_SLOT(t1)
    ld      t2, NodeApi_slot(s4)
    bne     t1, t2, 95f
    j       5f
102: ld     t0, 8(s3)                       # the SSZ bytes
    add     t0, s3, t0
    sd      t0, (L + 8)(sp)
    ld      t0, 16(s3)
    sd      t0, (L + 16)(sp)
    li      t1, 40                          # their slot: a state's at byte 40, a block's at 100
    ld      t2, NodeApi_op(s4)
    li      t3, API_OP_GET_STATE_V2
    beq     t2, t3, 4f
    li      t1, 100
4:  addi    t2, t1, 8
    bltu    t0, t2, 96f
    ld      t2, (L + 8)(sp)
    add     t2, t2, t1
    lwu     t3, 0(t2)
    lwu     t2, 4(t2)
    slli    t2, t2, 32
    or      t2, t2, t3
    ld      t3, NodeApi_slot(s4)
    bne     t2, t3, 96f
    ld      t0, NodeApi_op(s4)              # getBlockAttestationsV2: the body's attestations, a ByteList at the end of scratch
    li      t1, API_OP_GET_BLINDED_BLOCK
    beq     t0, t1, 52f
    li      t1, API_OP_GET_BLOCK_ATTESTATIONS_V2
    bne     t0, t1, 5f
    ld      t4, (L + 8)(sp)
    ld      t5, (L + 16)(sp)
    lwu     t0, 0(t4)                       # the message
    addi    t1, t0, 84
    bgtu    t1, t5, 96f
    add     t1, t4, t0
    lwu     t2, 80(t1)                      # its body
    add     t0, t0, t2
    addi    t1, t0, 216
    bgtu    t1, t5, 96f
    add     t1, t4, t0
    lwu     t2, 208(t1)                     # the list: from attestations to deposits
    lwu     t3, 212(t1)
    bgtu    t2, t3, 96f
    add     t3, t0, t3
    bgtu    t3, t5, 96f
    add     t2, t0, t2
    sub     t3, t3, t2
    ld      t1, (L + 56)(sp)                # its bytes copied into a ByteList at the end of scratch
    ld      t0, 0(t1)
    addi    t5, t3, 24 + 7
    andi    t5, t5, -8
    bltu    t0, t5, 97f
    sub     t0, t0, t5
    add     t1, t1, t0
    sd      t5, 0(t1)
    li      t0, 24
    sd      t0, 8(t1)
    sd      t3, 16(t1)
    mv      s3, t1
    addi    a0, t1, 24
    add     a1, t4, t2
    mv      a2, t3
    call    lantern_copy
    j       5f
52: ld      a1, (L + 56)(sp)                # getBlindedBlock: lantern_node_blinded_block into a ByteList at the end of scratch, then its bytes
    ld      t0, 0(a1)
    ld      t1, (L + 16)(sp)
    addi    t1, t1, 24 + 1024 + 7
    andi    t1, t1, -8
    addi    t2, t1, 64
    bltu    t0, t2, 97f
    sub     t0, t0, t1
    sd      t0, 0(a1)
    add     a2, a1, t0
    sd      t1, 0(a2)
    mv      a0, s3
    mv      s3, a2
    ld      t6, NodeApi_fork(s4)
    FORK_CALL node_blinded_block
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 97f
    bnez    a0, 96f
    ld      t0, 8(s3)
    add     t0, s3, t0
    sd      t0, (L + 8)(sp)
    ld      t0, 16(s3)
    sd      t0, (L + 16)(sp)
5:  ld      t0, NodeApi_sent(s4)            # the entry's sent, flags and cursor go on in the event
    sd      t0, NodeEvent_api(s5)
    ld      t0, NodeApi_flags(s4)
    sd      t0, (NodeEvent_api + 8)(s5)
    addi    a0, s5, (NodeEvent_api + 16)
    addi    a1, s4, NodeApi_cursor
    li      a2, JSON_CURSOR_SIZE
    call    lantern_copy
    mv      s6, s10                         # the writer
    li      s7, 1
    ld      s8, (L + 0)(sp)
    li      s9, 0
    ld      t0, (L + 40)(sp)                # a validator stream: its selection; getEpochCommittees its count; then api_stream_json reads the state
    beqz    t0, 6f
    li      t1, 3
    beq     t0, t1, 67f
    li      t1, 4
    beq     t0, t1, 68f
    li      t1, 5
    beq     t0, t1, 69f
    li      t1, 6
    beq     t0, t1, 6f
    ld      a0, (L + 56)(sp)
    ld      a1, (L + 48)(sp)
    li      t1, 2
    beq     t0, t1, 63f
    mv      a2, s3
    call    node_api_validators_prep
    bnez    a0, 97f
    j       66f
68: ld      t0, NodeApi_op(s4)              # a pending stream: its items; for SSZ their bytes and their count
    addi    a1, t0, -API_OP_GET_PENDING_DEPOSITS
    li      t1, API_OP_GET_PENDING_CONSOLIDATIONS
    bne     t0, t1, 681f
    li      a1, 2
681: ld     a0, (L + 48)(sp)
    addi    a2, sp, L + 8
    ld      t6, NodeApi_fork(s4)
    FORK_CALL node_pending
    bnez    a0, 96f
    ld      t0, (L + 16)(sp)
    ld      t1, (L + 24)(sp)
    mul     t0, t0, t1
    sd      t0, (L + 16)(sp)
    ld      s3, (L + 48)(sp)                # the state is what api_stream_json reads
    j       6f
69: ld      t0, (L + 48)(sp)                # getBlockHeaders: an item's header at the end of scratch, s3 its address
    or      t0, t0, s3
    beqz    t0, 6f
    ld      t1, (L + 56)(sp)
    ld      t2, 0(t1)
    li      t3, 208 + 64
    bltu    t2, t3, 97f
    addi    t2, t2, -208
    sd      t2, 0(t1)
    add     t2, t1, t2
    sd      t2, (L + 32)(sp)
    beqz    s3, 691f
    ld      t0, 16(s3)                      # of the bytes: lantern_node_block_header of the fork of their slot
    li      t1, 108
    bltu    t0, t1, 96f
    ld      t0, 8(s3)
    add     t0, s3, t0
    ld      a0, 100(t0)
    ld      a1, (L + 64)(sp)
    addi    a1, a1, Node_config
    call    node_fork
    mv      t6, a0
    mv      a0, s3
    ld      a1, (L + 56)(sp)
    ld      a2, (L + 32)(sp)
    FORK_CALL node_block_header
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 97f
    bnez    a0, 96f
    j       693f
691: ld     a1, (L + 48)(sp)                # of the post-state: its latest_block_header, a zero signature
    ld      a0, (L + 32)(sp)
    ld      t0, NODE_STATE_HEADER(a1)
    sd      t0, 0(a0)
    addi    a0, a0, 8
    addi    a1, a1, NODE_STATE_HEADER + 8
    li      a2, 112 - 8
    call    lantern_copy
    ld      a0, (L + 32)(sp)
    addi    a0, a0, 112
    li      a1, 96
    call    lantern_zero
    ld      t0, (L + 32)(sp)
    ld      t1, 48(t0)
    ld      t2, 56(t0)
    or      t1, t1, t2
    ld      t2, 64(t0)
    or      t1, t1, t2
    ld      t2, 72(t0)
    or      t1, t1, t2
    bnez    t1, 693f
    ld      t0, (L + 48)(sp)                # a zero state_root: the state's root
    ld      a0, NODE_STATE_SLOT(t0)
    ld      a1, (L + 64)(sp)
    addi    a1, a1, Node_config
    call    node_fork
    mv      t6, a0
    ld      a0, (L + 48)(sp)
    ld      t0, (L + 64)(sp)
    LDQ     a1, t0, Node_config + CONFIG_STATE_CACHE
    ld      a2, (L + 56)(sp)
    ld      a3, (L + 32)(sp)
    addi    a3, a3, 48
    FORK_CALL state_root
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 97f
    bnez    a0, 96f
693: ld     s3, (L + 32)(sp)
    j       6f
63: ld      a2, (L + 64)(sp)
    call    node_api_committees_prep
    li      t0, 400
    beq     a0, t0, 64f
    bnez    a0, 97f
66: ld      s3, (L + 48)(sp)
    j       6f
67: beqz    s3, 6f                          # getPoolAttestationsV2 from electra: the Attestation of a SingleAttestation
    ld      t0, NodeApi_op(s4)
    li      t1, API_OP_GET_POOL_ATTESTATIONS_V2
    bne     t0, t1, 6f
    ld      t0, NodeApi_sent(s4)
    li      t1, FORK_ELECTRA
    bltu    t0, t1, 6f
    ld      a0, (L + 56)(sp)
    mv      a1, s3
    ld      a2, NodeApi_member(s4)
    call    node_pool_attestation
    li      t0, 1
    beq     a0, t0, 96f
    bgtu    a0, t0, 97f
    mv      s3, a1
    j       6f
64: addi    a1, s5, NodeEvent_api_bytes     # an index past the count: the error 400 is the answer
    ld      t0, (L + 0)(sp)
    sub     t0, t0, a1
    sd      t0, 0(a1)
    ld      t0, (NodeEvent_api + 8)(s5)
    andi    a4, t0, API_R_CLOSE
    bnez    a4, 65f
    andi    t1, t0, API_STREAM_HTTP10
    beqz    t1, 65f
    li      a4, API_R_KEEP
65: li      a0, 0
    li      a2, 400
    li      a3, API_BODY_ERROR
    call    api_respond
    bnez    a0, 97f
    ld      t0, (NodeEvent_api_bytes + 16)(s5)
    add     s6, s10, t0
    ld      t0, (NodeEvent_api + 8)(s5)
    ori     t0, t0, (API_STREAM_STARTED | API_STREAM_DONE)
    sd      t0, (NodeEvent_api + 8)(s5)
    j       80f
6:  ld      t0, (NodeEvent_api + 8)(s5)
    andi    t1, t0, API_STREAM_SSZ
    beqz    t1, 30f
    ld      t2, (L + 40)(sp)
    li      t3, 6                           # a sidecar stream: SSZ as a JSON answer
    beq     t2, t3, 30f
    li      t3, 4                           # a pending stream: its SSZ bytes as getStateV2's
    beq     t2, t3, 601f
    bnez    t2, 60f
601: andi   t1, t0, API_STREAM_STARTED
    bnez    t1, 11f
    ld      a0, (L + 16)(sp)                # SSZ: the head first, with Content-Length
    call    api_stream_head
11: ld      a2, (L + 16)(sp)                # then the bytes from sent, as many as fit
    ld      t0, NodeEvent_api(s5)
    sub     a2, a2, t0
    sub     t1, s8, s6
    bleu    a2, t1, 12f
    mv      a2, t1
12: ld      a1, (L + 8)(sp)
    add     a1, a1, t0
    add     t0, t0, a2
    sd      t0, NodeEvent_api(s5)
    mv      a0, s6
    add     s6, s6, a2
    call    lantern_copy
    ld      t0, (NodeEvent_api + 8)(s5)
    ori     t0, t0, API_STREAM_STARTED
    ld      t1, NodeEvent_api(s5)
    ld      t2, (L + 16)(sp)
    bne     t1, t2, 13f
    ori     t0, t0, API_STREAM_DONE
13: sd      t0, (NodeEvent_api + 8)(s5)
    j       80f
60: andi    t1, t0, API_STREAM_STARTED      # the identities as SSZ: Content-Length of 64 bytes each
    bnez    t1, 61f
    ld      a0, (NodeEvent_api + 16 + 40)(s5)
    slli    a0, a0, 6
    call    api_stream_head
61: call    api_validators_json
    ld      t0, (NodeEvent_api + 8)(s5)
    ori     t0, t0, API_STREAM_STARTED
    beqz    a0, 62f
    ori     t0, t0, API_STREAM_DONE
62: sd      t0, (NodeEvent_api + 8)(s5)
    j       80f
30: andi    t1, t0, API_STREAM_STARTED      # JSON, the first chunk: the body after room for the head
    bnez    t1, 40f
    addi    s6, s10, API_HEAD_ROOM
    sd      s6, (L + 24)(sp)
    ld      s8, (L + 0)(sp)
    addi    s8, s8, -7                      # room for CRLF and the last chunk
    ld      t0, (L + 40)(sp)
    beqz    t0, 35f
    li      t1, 6                           # a sidecar stream: as JSON the pending streams' head; as SSZ none
    bne     t0, t1, 393f
    ld      t2, (NodeEvent_api + 8)(s5)
    andi    t2, t2, API_STREAM_SSZ
    bnez    t2, 36f
    j       392f
393: li     t1, 4
    beq     t0, t1, 392f
    li      t1, 3
    bne     t0, t1, 38f
    ld      t0, NodeApi_op(s4)              # a pool stream: {"data":[, the V2 GETs {"version":"<fork>","data":[
    li      t1, API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    beq     t0, t1, 391f
    li      t1, API_OP_GET_POOL_ATTESTATIONS_V2
    bne     t0, t1, 39f
391: API_LIT api_j_version
    ld      a0, NodeApi_fork(s4)
    call    api_fork_name
    API_LIT api_p_version
    j       36f
39: API_LIT api_p_data
    j       36f
    /* the validator streams: {"execution_optimistic":…,"finalized":…,"data":[ */
38: API_LIT api_v_open
    ld      a0, (NodeEvent_api + 8)(s5)
    srli    a0, a0, 8
    andi    a0, a0, 1
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, (NodeEvent_api + 8)(s5)
    srli    a0, a0, 9
    andi    a0, a0, 1
    call    api_bool
    API_LIT api_v_list
    j       36f
    /* the pending streams: {"version":"<fork>","execution_optimistic":…,"finalized":…,"data":[ */
392: API_LIT api_j_version
    ld      a0, NodeApi_fork(s4)
    call    api_fork_name
    API_LIT api_j_optimistic
    ld      a0, (NodeEvent_api + 8)(s5)
    srli    a0, a0, 8
    andi    a0, a0, 1
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, (NodeEvent_api + 8)(s5)
    srli    a0, a0, 9
    andi    a0, a0, 1
    call    api_bool
    API_LIT api_v_list
    j       36f
    /* {"version":"<fork>","execution_optimistic":…,"finalized":…,"data": */
35: API_LIT api_j_version
    ld      a0, NodeApi_fork(s4)
    call    api_fork_name
    API_LIT api_j_optimistic
    ld      a0, (NodeEvent_api + 8)(s5)
    srli    a0, a0, 8
    andi    a0, a0, 1
    call    api_bool
    API_LIT api_x_finalized
    ld      a0, (NodeEvent_api + 8)(s5)
    srli    a0, a0, 9
    andi    a0, a0, 1
    call    api_bool
    API_LIT api_j_data
36: call    api_stream_json
    li      t0, 2
    beq     a0, t0, 96f
    ld      t0, (NodeEvent_api + 8)(s5)
    ori     t0, t0, API_STREAM_STARTED
    li      t1, -1                          # not whole: chunked, or for HTTP/1.0 no length and a close
    beqz    a0, 31f
    ori     t0, t0, API_STREAM_DONE         # whole: Content-Length
    ld      t1, (L + 24)(sp)
    sub     t1, s6, t1
    j       33f
31: andi    t2, t0, API_STREAM_HTTP10
    beqz    t2, 32f
    ori     t0, t0, API_STREAM_CLOSE
    j       33f
32: ori     t0, t0, API_STREAM_CHUNKED
33: sd      t0, (NodeEvent_api + 8)(s5)
    sd      t1, (L + 32)(sp)
    ld      t0, (L + 24)(sp)                # the body's bytes
    sub     t0, s6, t0
    sd      t0, (L + 16)(sp)
    li      s7, 0                           # the head's bytes: a pass that counts
    li      s6, 0
    ld      a0, (L + 32)(sp)
    call    api_stream_head
    add     a0, s10, s6                     # the body after the head, and a size line when chunked
    ld      t0, (NodeEvent_api + 8)(s5)
    andi    t0, t0, API_STREAM_CHUNKED
    beqz    t0, 34f
    addi    a0, a0, 6
34: ld      a1, (L + 24)(sp)
    ld      a2, (L + 16)(sp)
    add     t0, a0, a2
    sd      t0, (L + 24)(sp)                # now the body's end
    call    lantern_copy
    li      s7, 1                           # the head
    mv      s6, s10
    ld      s8, (L + 0)(sp)
    ld      a0, (L + 32)(sp)
    call    api_stream_head
    ld      t0, (NodeEvent_api + 8)(s5)
    andi    t0, t0, API_STREAM_CHUNKED
    beqz    t0, 37f
    ld      a0, (L + 16)(sp)                # chunked: the size line, then CRLF after the bytes
    mv      a1, s6
    call    api_hex4
    li      t0, 0x0d
    sb      t0, 4(s6)
    li      t0, 0x0a
    sb      t0, 5(s6)
    ld      s6, (L + 24)(sp)
    API_LIT api_crlf
    j       80f
37: ld      s6, (L + 24)(sp)
    j       80f
40: andi    t1, t0, API_STREAM_CHUNKED      # JSON, a later chunk; chunked: a size line, the bytes, CRLF
    beqz    t1, 45f
    addi    s6, s10, 6
    ld      s8, (L + 0)(sp)
    addi    s8, s8, -7
    call    api_stream_json
    li      t0, 2
    beq     a0, t0, 96f
    sd      a0, (L + 32)(sp)
    sub     t0, s6, s10                     # no bytes: no chunk of them, the last chunk alone
    li      t1, 6
    bne     t0, t1, 41f
    mv      s6, s10
    ld      s8, (L + 0)(sp)
    beqz    a0, 80f
    API_LIT api_last_chunk
    j       44f
41: sub     a0, s6, s10
    addi    a0, a0, -6
    mv      a1, s10
    call    api_hex4
    li      t0, 0x0d
    sb      t0, 4(s10)
    li      t0, 0x0a
    sb      t0, 5(s10)
    ld      s8, (L + 0)(sp)
    API_LIT api_crlf
    ld      t0, (L + 32)(sp)
    beqz    t0, 80f
    API_LIT api_last_chunk
    j       44f
45: call    api_stream_json                 # HTTP/1.0: the bytes alone
    li      t0, 2
    beq     a0, t0, 96f
    beqz    a0, 80f
44: ld      t0, (NodeEvent_api + 8)(s5)
    ori     t0, t0, API_STREAM_DONE
    sd      t0, (NodeEvent_api + 8)(s5)
80: sub     t0, s6, s10                     # the chunk's ByteList; the event's size covers it
    addi    t1, t0, (24 + 7)
    andi    t1, t1, -8
    sd      t1, NodeEvent_api_bytes(s5)
    li      t2, 24
    sd      t2, (NodeEvent_api_bytes + 8)(s5)
    sd      t0, (NodeEvent_api_bytes + 16)(s5)
    addi    t2, t1, NodeEvent_api_bytes
    sd      t2, 0(s5)
    mv      a0, s6
    addi    a1, t1, -24
    sub     a1, a1, t0
    call    lantern_zero
    li      a0, LANTERN_OK
    LEAVE 80
95: li      t0, LANTERN_INVALID_SLOT        # a state at another slot
    j       94f
96: li      t0, LANTERN_INVALID_ENCODING    # bytes that are no encoding of the type
94: sd      t0, NodeEvent_result(s5)
    li      t0, NODE_EV_WORK_DONE_SIZE
    sd      t0, 0(s5)
    li      a0, LANTERN_OK
    LEAVE 80
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 80
98: li      a0, LANTERN_INVALID_EVENT
    LEAVE 80
END_FUNCTION node_api_chunk_run

# ---------------------------------------------------------------- The pools (beacon-api.md, node.md)

/*
 * (scratch a0, the ByteList a1 of a SingleAttestation, member a2) -> a0: the electra Attestation
 * of it as a ByteList at the end of scratch, at a1 (node.md, NODE_WORK_API_CHUNK, the pool
 * streams): aggregation_bits of the length member / 2^16 with the bit of the place member % 2^16,
 * data, signature, committee_bits with the bit of committee_index. a0 = 0; 1 for bytes of another
 * size, a place not below the length, a length above MAX_VALIDATORS_PER_COMMITTEE or a
 * committee_index not below MAX_COMMITTEES_PER_SLOT; 2 for a scratch without
 * NODE_POOL_ATTESTATION_ROOM bytes. Locals: the ByteList, the SingleAttestation, the committee
 * index, the place, the length.
 */
LOCAL_FUNCTION node_pool_attestation
    FRAME 48
    ld      t0, 16(a1)
    li      t1, 240
    bne     t0, t1, 81f
    ld      t0, 8(a1)
    add     t0, a1, t0
    ld      t1, 0(t0)
    li      t2, MAX_COMMITTEES_PER_SLOT
    bgeu    t1, t2, 81f
    slli    t2, a2, 48
    srli    t2, t2, 48
    srli    t3, a2, 16
    li      t4, MAX_VALIDATORS_PER_COMMITTEE
    bgtu    t3, t4, 81f
    bgeu    t2, t3, 81f
    ld      t4, 0(a0)
    li      t5, NODE_POOL_ATTESTATION_ROOM
    bltu    t4, t5, 82f
    add     t4, a0, t4
    sub     t4, t4, t5
    sd      t4, 0(sp)
    sd      t0, 8(sp)
    sd      t1, 16(sp)
    sd      t2, 24(sp)
    sd      t3, 32(sp)
    addi    a0, t4, 24
    li      a1, NODE_POOL_ATTESTATION_ROOM - 24
    call    lantern_zero
    ld      t4, 0(sp)                       # its head: size, offset 24, count
    li      t0, NODE_POOL_ATTESTATION_ROOM
    sd      t0, 0(t4)
    li      t0, 24
    sd      t0, 8(t4)
    ld      t0, 32(sp)
    srli    t0, t0, 3
    addi    t0, t0, NODE_POOL_ATTESTATION_FIXED + 1
    sd      t0, 16(t4)
    li      t0, NODE_POOL_ATTESTATION_FIXED # the offset of aggregation_bits, data and signature
    sw      t0, 24(t4)
    addi    a0, t4, 28
    ld      a1, 8(sp)
    addi    a1, a1, 16
    li      a2, 128 + 96
    call    lantern_copy
    ld      t4, 0(sp)
    ld      t1, 16(sp)                      # committee_bits
    srli    t0, t1, 3
    andi    t1, t1, 7
    li      t2, 1
    sll     t2, t2, t1
    add     t0, t4, t0
    sb      t2, (24 + 4 + 128 + 96)(t0)
    addi    t4, t4, 24 + NODE_POOL_ATTESTATION_FIXED    # aggregation_bits: the place, then the length's bit
    ld      t1, 24(sp)
    srli    t0, t1, 3
    andi    t1, t1, 7
    li      t2, 1
    sll     t2, t2, t1
    add     t0, t4, t0
    lbu     t3, 0(t0)
    or      t3, t3, t2
    sb      t3, 0(t0)
    ld      t1, 32(sp)
    srli    t0, t1, 3
    andi    t1, t1, 7
    li      t2, 1
    sll     t2, t2, t1
    add     t0, t4, t0
    lbu     t3, 0(t0)
    or      t3, t3, t2
    sb      t3, 0(t0)
    ld      a1, 0(sp)
    li      a0, 0
    UNFRAME 48
81: li      a0, 1
    UNFRAME 48
82: li      a0, 2
    UNFRAME 48
END_FUNCTION node_pool_attestation

/* a0 = the new id of a NODE_ACT_BYTES_PUT of the 8 bytes at a0. Locals: a ByteList head whose offset reaches them. */
LOCAL_FUNCTION node_api_put8
    FRAME 32
    sub     t0, a0, sp
    li      t1, 8
    sd      t1, 0(sp)
    sd      t0, 8(sp)
    sd      t1, 16(sp)
    mv      a0, sp
    call    node_put
    UNFRAME 32
END_FUNCTION node_api_put8

/* a0 = the gossip topic of the pool POST a0, or 0. Uses t0, t1. */
LOCAL_FUNCTION node_submit_topic
    UNWIND_END_PROLOGUE
    mv      t0, a0
    li      a0, GOSSIP_VOLUNTARY_EXIT
    li      t1, API_OP_SUBMIT_POOL_VOLUNTARY_EXIT
    beq     t0, t1, 9f
    li      a0, GOSSIP_PROPOSER_SLASHING
    li      t1, API_OP_SUBMIT_POOL_PROPOSER_SLASHINGS
    beq     t0, t1, 9f
    li      a0, GOSSIP_ATTESTER_SLASHING
    li      t1, API_OP_SUBMIT_POOL_ATTESTER_SLASHINGS_V2
    beq     t0, t1, 9f
    li      a0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    li      t1, API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    beq     t0, t1, 9f
    li      a0, GOSSIP_BEACON_ATTESTATION
    li      t1, API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    beq     t0, t1, 9f
    li      a0, 0
9:  ret
END_FUNCTION node_submit_topic

/* a0 = the lantern_node_json kind of the pool operation of the gossip topic a0. Uses t0. */
LOCAL_FUNCTION node_pool_kind
    UNWIND_END_PROLOGUE
    li      t0, GOSSIP_BLS_TO_EXECUTION_CHANGE
    beq     a0, t0, 1f
    addi    a0, a0, -(GOSSIP_VOLUNTARY_EXIT - NODE_JSON_EXIT)
    ret
1:  li      a0, NODE_JSON_BLS_CHANGE
    ret
END_FUNCTION node_pool_kind
.if GOSSIP_PROPOSER_SLASHING - GOSSIP_VOLUNTARY_EXIT != NODE_JSON_PROPOSER_SLASHING - NODE_JSON_EXIT || GOSSIP_ATTESTER_SLASHING - GOSSIP_VOLUNTARY_EXIT != NODE_JSON_ATTESTER_SLASHING - NODE_JSON_EXIT
.error "node_pool_kind: the kinds follow the topics"
.endif

/*
 * a0 = the index of the first pool entry from the index a0 that the pool stream a1 answers
 * (node.md, NODE_EV_API): of its topic; for getPoolAttesterSlashingsV2 and getPoolAttestationsV2
 * of the type of its fork, and for getPoolAttestationsV2 of its filters; else 2^64 - 1. a1 = the
 * entry. s1 the node. Uses t0-t6, a7.
 */
LOCAL_FUNCTION node_pool_next
    UNWIND_END_PROLOGUE
    ld      t5, NodeApi_op(a1)
    li      t0, GOSSIP_VOLUNTARY_EXIT
    li      t1, API_OP_GET_POOL_VOLUNTARY_EXITS
    beq     t5, t1, 1f
    li      t0, GOSSIP_PROPOSER_SLASHING
    li      t1, API_OP_GET_POOL_PROPOSER_SLASHINGS
    beq     t5, t1, 1f
    li      t0, GOSSIP_ATTESTER_SLASHING
    li      t1, API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    beq     t5, t1, 1f
    li      t0, GOSSIP_BEACON_ATTESTATION
    li      t1, API_OP_GET_POOL_ATTESTATIONS_V2
    beq     t5, t1, 1f
    li      t0, GOSSIP_BLS_TO_EXECUTION_CHANGE
1:  ld      t5, NodeApi_filter_slot(a1)
    ld      t6, NodeApi_filter_index(a1)
    ld      t4, NodeApi_fork(a1)
    li      t1, FORK_ELECTRA
    sltu    t4, t4, t1
    xori    t4, t4, 1
    PART    t1, t2, s1, Node_pool
    li      t3, NodePool__mem
    mul     t3, a0, t3
    add     t1, t1, t3
2:  bgeu    a0, t2, 8f
    ld      t3, NodePool_topic(t1)
    bne     t3, t0, 3f
    li      t3, GOSSIP_ATTESTER_SLASHING
    beq     t0, t3, 21f
    li      t3, GOSSIP_BEACON_ATTESTATION
    bne     t0, t3, 4f
    li      a7, -1                          # an attestation: of the filters
    beq     t5, a7, 20f
    ld      t3, NodePool_slot(t1)
    bne     t3, t5, 3f
20: beq     t6, a7, 21f
    ld      t3, NodePool_index(t1)
    bne     t3, t6, 3f
21: ld      t3, NodePool_fork(t1)
    li      a7, FORK_ELECTRA
    sltu    t3, t3, a7
    xori    t3, t3, 1
    beq     t3, t4, 4f
3:  addi    t1, t1, NodePool__mem
    addi    a0, a0, 1
    j       2b
4:  mv      a1, t1
    ret
8:  li      a0, -1
    ret
END_FUNCTION node_pool_next

/*
 * (connection a0, route a1, flags a2, view a3): a stream of a pool GET (node.md, NODE_EV_API):
 * fork the store's, the filters of getPoolAttestationsV2; slot the first entry it answers, data
 * its bytes, sent its fork, member its member; data 0 with none. flags: API_STREAM_CLOSE and API_STREAM_HTTP10. Locals: the connection, the route, the
 * flags, the fork, the entry's index and address.
 */
LOCAL_FUNCTION node_api_pool_stream
    FRAME 48
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    ld      t0, ApiView_fork(a3)
    sd      t0, 24(sp)
    call    node_api_new
    sd      a0, 32(sp)
    sd      a1, 40(sp)
    mv      a0, a1
    li      a1, NodeApi__mem
    call    lantern_zero
    ld      t0, 40(sp)
    ld      t1, 0(sp)
    sd      t1, NodeApi_connection(t0)
    ld      t1, 8(sp)
    ld      a1, ApiRoute_op(t1)
    sd      a1, NodeApi_op(t0)
    ld      t1, 16(sp)
    sd      t1, NodeApi_flags(t0)
    ld      a2, 24(sp)
    sd      a2, NodeApi_fork(t0)
    li      t2, -1                          # the filters: getPoolAttestationsV2's slot and committee_index
    li      t3, -1
    li      t4, API_OP_GET_POOL_ATTESTATIONS_V2
    bne     a1, t4, 2f
    ld      t1, 8(sp)
    ld      t4, ApiRoute_present(t1)
    andi    t5, t4, (1 << API_PARAM_SLOT)
    beqz    t5, 3f
    ld      t2, ApiRoute_slot(t1)
3:  li      t5, (1 << API_PARAM_COMMITTEE_INDEX)
    and     t5, t4, t5
    beqz    t5, 2f
    ld      t3, ApiRoute_committee_index(t1)
2:  sd      t2, NodeApi_filter_slot(t0)
    sd      t3, NodeApi_filter_index(t0)
    li      a0, 0
    mv      a1, t0
    call    node_pool_next
    ld      t0, 40(sp)
    li      t1, -1
    beq     a0, t1, 1f
    sd      a0, NodeApi_slot(t0)
    ld      t1, NodePool_data_id(a1)
    sd      t1, NodeApi_data(t0)
    ld      t1, NodePool_fork(a1)
    sd      t1, NodeApi_sent(t0)
    ld      t1, NodePool_member(a1)
    sd      t1, NodeApi_member(t0)
1:  ld      a0, 32(sp)
    ld      a1, 40(sp)
    call    node_api_chunk_work
    UNFRAME 48
END_FUNCTION node_api_pool_stream

/*
 * The item of the getBlockHeaders stream a0 at or after the position a1 (node.md, NODE_EV_API, an
 * item of getBlockHeaders): position 0 the Db's block of the query, i + 1 the NodeBlock at index i.
 * Its slot (the position), data, state, member (1 on the chain, + 2 optimistic, + 4 finalized) and
 * its root at byte 0 of cursor; a0 = 1, or 0 with data and state 0 for none. s1 the node, s2 the
 * store. s9 the entry, s3 the position, s4 the slot of the query or 2^64 - 1, s5 the address of its parent_root
 * or 0, s6 a slot or a NodeBlock entry, s7 the member. Locals: L a slot.
 */
LOCAL_FUNCTION node_headers_next
    ENTER 16
    mv      s9, a0
    mv      s3, a1
    ld      s4, NodeApi_filter_slot(s9)
    ld      t0, (NodeApi_cursor + 64)(s9)
    addi    s5, s9, NodeApi_cursor + 32
    bnez    t0, 1f
    li      s5, 0
1:  bnez    s3, 20f
    ld      t0, Node_flags(s1)              # position 0: with NODE_FLAG_DB, the Db's block of the query
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 19f
    beqz    s5, 15f
    mv      a0, s5                          # with parent_root: its slot r, of the node's imported block on the chain, else of the Db
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 11f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 11f
    mv      s6, a1
    mv      a0, a1
    call    node_api_on_chain
    beqz    a0, 19f
    ld      s6, NodeBlock_slot(s6)
    j       12f
11: ld      a0, Node_db(s1)
    add     a0, s1, a0
    mv      a1, s5
    addi    a2, sp, L
    call    lantern_db_find_root
    ld      s6, L(sp)
    li      t0, -1
    beq     s6, t0, 19f
12: addi    s6, s6, 1                       # the first slot above r whose block is in the Db, below the chain the node keeps
    bgtu    s6, s4, 19f                     # with slot: at most slot
    mv      a0, s6
    call    node_api_below
    li      t0, -1
    bne     a0, t0, 19f
    mv      a0, s6
    call    node_db_slot
    beqz    a0, 12b
    li      t0, -1
    beq     s4, t0, 16f
    bne     s6, s4, 19f
    j       16f
15: mv      s6, s4                          # slot alone: the Db's block of slot, below the chain the node keeps
    mv      a0, s6
    call    node_api_below
    li      t0, -1
    bne     a0, t0, 19f
    mv      a0, s6
    call    node_db_slot
    beqz    a0, 19f
16: addi    t0, s9, NodeApi_cursor          # the Db's block of slot s6: its DbSlot a0, the root at 0
    COPY32  t0, a0
    mv      a0, s6
    call    node_db_block
    sd      a0, NodeApi_data(s9)
    sd      zero, NodeApi_state(s9)
    sd      zero, NodeApi_slot(s9)
    mv      a0, s6
    call    node_api_final_block
    slli    s7, a0, 2
    ori     s7, s7, 1                       # on the chain, not optimistic
    sd      s7, NodeApi_member(s9)
    li      a0, 1
    LEAVE 16
19: li      s3, 1
20: PART    t0, t1, s1, Node_blocks         # the node's imported blocks from the index s3 - 1
    addi    t2, s3, -1
    bgeu    t2, t1, 29f
    li      t3, NodeBlock__mem
    mul     t2, t2, t3
    add     s6, t0, t2
    ld      t0, NodeBlock_status(s6)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 28f
    li      t0, -1
    beq     s4, t0, 22f
    ld      t0, NodeBlock_slot(s6)
    bne     t0, s4, 28f
22: beqz    s5, 23f
    addi    t0, s6, NodeBlock_parent_root
    NE32    t0, s5, 28f
23: ld      a0, NodeBlock_data_id(s6)       # its bytes, else its Db record, else its post-state
    bnez    a0, 24f
    mv      a0, s6
    call    node_api_db_ref
24: sd      a0, NodeApi_data(s9)
    li      t0, 0
    bnez    a0, 25f
    ld      t0, NodeBlock_state_id(s6)
    beqz    t0, 28f                         # neither: left out
25: sd      t0, NodeApi_state(s9)
    sd      s3, NodeApi_slot(s9)
    addi    t0, s9, NodeApi_cursor
    COPY32  t0, s6
    ld      t0, NodeBlock_payload_status(s6)
    addi    t0, t0, -PAYLOAD_STATUS_NOT_VALIDATED
    seqz    s7, t0
    slli    s7, s7, 1
    mv      a0, s6
    call    node_api_on_chain
    or      s7, s7, a0
    beqz    a0, 26f
    ld      a0, NodeBlock_slot(s6)
    call    node_api_final_block
    slli    a0, a0, 2
    or      s7, s7, a0
26: sd      s7, NodeApi_member(s9)
    li      a0, 1
    LEAVE 16
28: addi    s3, s3, 1
    j       20b
29: sd      zero, NodeApi_data(s9)
    sd      zero, NodeApi_state(s9)
    li      a0, 0
    LEAVE 16
END_FUNCTION node_headers_next

/*
 * (connection a0, route a1, flags a2): the getBlockHeaders stream of the route's query (node.md,
 * NODE_EV_API): filter_slot its slot, the head's slot with neither slot nor parent_root, else
 * 2^64 - 1; its parent_root at byte 32 of cursor and 1 at byte 64; API_STREAM_OPTIMISTIC and
 * API_STREAM_FINALIZED of all its items; then its first item and a NODE_WORK_API_CHUNK. s1 the
 * node. Locals: the connection, the route then the items, the flags, the entry's index and address,
 * the position.
 */
LOCAL_FUNCTION node_api_headers_stream
    FRAME 48
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    call    node_api_new
    sd      a0, 24(sp)
    sd      a1, 32(sp)
    mv      a0, a1
    li      a1, NodeApi__mem
    call    lantern_zero
    ld      a1, 32(sp)
    ld      t0, 0(sp)
    sd      t0, NodeApi_connection(a1)
    li      t0, API_OP_GET_BLOCK_HEADERS
    sd      t0, NodeApi_op(a1)
    ld      t1, 8(sp)
    ld      t0, ApiRoute_present(t1)
    li      t2, 1 << API_PARAM_PARENT_ROOT
    and     t0, t0, t2
    beqz    t0, 1f
    addi    a0, a1, NodeApi_cursor + 32
    addi    t2, t1, ApiRoute_root
    COPY32  a0, t2
    ld      a1, 32(sp)
    li      t0, 1
    sd      t0, (NodeApi_cursor + 64)(a1)
    li      t0, -1
    sd      t0, NodeApi_filter_slot(a1)
    j       2f
1:  addi    a0, s1, Node_head_root          # neither: the head's slot
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 11f
    ld      t0, NodeBlock_slot(a1)
11: ld      a1, 32(sp)
    sd      t0, NodeApi_filter_slot(a1)
2:  ld      t1, 8(sp)
    ld      t0, ApiRoute_present(t1)
    andi    t0, t0, 1 << API_PARAM_SLOT
    beqz    t0, 3f
    ld      t0, ApiRoute_slot(t1)
    sd      t0, NodeApi_filter_slot(a1)
3:  ld      t0, 16(sp)                      # the flags of all items: optimistic of any, finalized of each, and of some
    ori     t0, t0, API_STREAM_FINALIZED
    sd      t0, NodeApi_flags(a1)
    sd      zero, 8(sp)
    sd      zero, 40(sp)
4:  ld      a0, 32(sp)
    ld      a1, 40(sp)
    call    node_headers_next
    ld      a1, 32(sp)
    beqz    a0, 5f
    ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    ld      t0, NodeApi_member(a1)
    ld      t1, NodeApi_flags(a1)
    andi    t2, t0, 2
    beqz    t2, 41f
    ori     t1, t1, API_STREAM_OPTIMISTIC
41: andi    t2, t0, 4
    bnez    t2, 42f
    andi    t1, t1, ~API_STREAM_FINALIZED
42: sd      t1, NodeApi_flags(a1)
    ld      t0, NodeApi_slot(a1)
    addi    t0, t0, 1
    sd      t0, 40(sp)
    j       4b
5:  ld      t0, 8(sp)
    bnez    t0, 6f
    ld      t1, NodeApi_flags(a1)
    andi    t1, t1, ~API_STREAM_FINALIZED
    sd      t1, NodeApi_flags(a1)
6:  ld      a0, 32(sp)                      # the first item
    li      a1, 0
    call    node_headers_next
    ld      a0, 24(sp)
    ld      a1, 32(sp)
    call    node_api_chunk_work
    UNFRAME 48
END_FUNCTION node_api_headers_stream

/*
 * The sidecar of the sidecar stream a0 from the index a1 on (node.md, NODE_EV_API, a sidecar of a
 * sidecar stream): member, data, sent 0 and cursor zero; a0 = 1, or 0 with data 0 for none. s1 the
 * node. s9 the entry, s3 the index.
 */
LOCAL_FUNCTION node_sidecar_next
    ENTER 0
    mv      s9, a0
    mv      s3, a1
1:  li      t0, 128
    bgeu    s3, t0, 8f
    ld      t0, NodeApi_filter_slot(s9)
    mv      t1, s3
    li      t2, 64
    bltu    s3, t2, 2f
    ld      t0, NodeApi_filter_index(s9)
    addi    t1, s3, -64
2:  srl     t0, t0, t1
    andi    t0, t0, 1
    beqz    t0, 7f
    addi    a0, s9, NodeApi_root            # the node's NODE_BLOB_VALID entry, else the Db's record
    mv      a1, s3
    call    node_blob_held
    beqz    a0, 3f
    ld      a0, NodeBlob_data_id(a0)
    j       5f
3:  ld      t0, Node_flags(s1)
    andi    t0, t0, NODE_FLAG_DB
    beqz    t0, 7f
    ld      a0, NodeApi_slot(s9)
    mv      a1, s3
    call    node_db_sidecar
    beqz    a0, 7f
5:  sd      a0, NodeApi_data(s9)
    sd      s3, NodeApi_member(s9)
    sd      zero, NodeApi_sent(s9)
    addi    a0, s9, NodeApi_cursor
    li      a1, JSON_CURSOR_SIZE
    call    lantern_zero
    li      a0, 1
    LEAVE 0
7:  addi    s3, s3, 1
    j       1b
8:  sd      zero, NodeApi_data(s9)
    li      a0, 0
    LEAVE 0
END_FUNCTION node_sidecar_next

/*
 * (connection a0, route a1, flags a2, view a3) -> a0: the sidecar stream of the block of the view
 * (node.md, NODE_EV_API): 0, or 400 for a block whose slot's fork is not the operation's. s1 the
 * node. Locals: the connection, the route, the flags, the view, the fork, the entry's index and
 * address.
 */
LOCAL_FUNCTION node_api_sidecar_stream
    FRAME 64
    sd      a0, 0(sp)
    sd      a1, 8(sp)
    sd      a2, 16(sp)
    sd      a3, 24(sp)
    ld      a0, ApiView_head_slot(a3)
    addi    a1, s1, Node_config
    call    node_fork
    sd      a0, 32(sp)
    ld      t0, 8(sp)
    ld      t0, ApiRoute_op(t0)
    li      t1, API_OP_GET_BLOB_SIDECARS
    bne     t0, t1, 1f
    li      t1, FORK_DENEB                  # getBlobSidecars: deneb and electra
    bltu    a0, t1, 8f
    li      t1, FORK_FULU
    bgeu    a0, t1, 8f
    j       2f
1:  li      t1, FORK_FULU                   # getDebugDataColumnSidecars: fulu and later
    bltu    a0, t1, 8f
2:  call    node_api_new
    sd      a0, 40(sp)
    sd      a1, 48(sp)
    mv      a0, a1
    li      a1, NodeApi__mem
    call    lantern_zero
    ld      a1, 48(sp)
    ld      t0, 0(sp)
    sd      t0, NodeApi_connection(a1)
    ld      t2, 8(sp)
    ld      t0, ApiRoute_op(t2)
    sd      t0, NodeApi_op(a1)
    ld      t0, 16(sp)                      # the answer flags, SSZ, and the block's values
    ld      t1, ApiRoute_response(t2)
    li      t3, API_TYPE_SSZ
    bne     t1, t3, 3f
    ori     t0, t0, API_STREAM_SSZ
3:  ld      t3, 24(sp)
    ld      t1, ApiView_is_optimistic(t3)
    beqz    t1, 31f
    ori     t0, t0, API_STREAM_OPTIMISTIC
31: LDQ     t1, t3, ApiView_head_finalized
    beqz    t1, 32f
    ori     t0, t0, API_STREAM_FINALIZED
32: sd      t0, NodeApi_flags(a1)
    ld      t0, 32(sp)
    sd      t0, NodeApi_fork(a1)
    ld      t0, ApiView_head_slot(t3)
    sd      t0, NodeApi_slot(a1)
    addi    t0, a1, NodeApi_root
    addi    t1, t3, ApiView_head_root
    COPY32  t0, t1
    li      t4, -1                          # the indices: their bits, all with none
    li      t5, -1
    ld      t2, 8(sp)
    ld      t0, ApiRoute_present(t2)
    li      t1, 1 << API_PARAM_INDICES
    and     t0, t0, t1
    beqz    t0, 6f
    li      t4, 0
    li      t5, 0
    PART    a2, a3, t2, ApiRoute_list
5:  beqz    a3, 6f
    ld      t0, 0(a2)
    addi    a2, a2, 8
    addi    a3, a3, -1
    li      t1, 128
    bgeu    t0, t1, 5b
    li      t1, 1
    li      t3, 64
    bgeu    t0, t3, 51f
    sll     t1, t1, t0
    or      t4, t4, t1
    j       5b
51: addi    t0, t0, -64
    sll     t1, t1, t0
    or      t5, t5, t1
    j       5b
6:  sd      t4, NodeApi_filter_slot(a1)
    sd      t5, NodeApi_filter_index(a1)
    mv      a0, a1
    li      a1, 0
    call    node_sidecar_next
    ld      a0, 40(sp)
    ld      a1, 48(sp)
    call    node_api_chunk_work
    li      a0, 0
    UNFRAME 64
8:  li      a0, 400
    UNFRAME 64
END_FUNCTION node_api_sidecar_stream

/*
 * A sidecar stream's body, as api_stream_json (node.md, NODE_WORK_API_CHUNK, the sidecar streams):
 * with the bytes s3, as JSON the JSON of the sidecar from the cursor at NodeEvent_api + 16 by
 * lantern_node_json of the entry's fork and the kind of the operation, after , when API_STREAM_ITEMS
 * is set and the cursor is at its start; as SSZ its bytes from sent (NodeEvent_api), as many as fit;
 * at the sidecar's end API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With s3 = 0: ]} as
 * JSON, nothing as SSZ. a0 = 1 when the answer is whole, 0 when more is to come, 2 for bytes that
 * are no encoding.
 */
LOCAL_FUNCTION api_sidecar_body
    FRAME 0
    ld      t0, (NodeEvent_api + 8)(s5)
    bnez    s3, 1f
    andi    t1, t0, API_STREAM_SSZ
    bnez    t1, 9f
    API_LIT api_v_end
9:  li      a0, 1
    UNFRAME 0
1:  andi    t1, t0, API_STREAM_SSZ
    beqz    t1, 3f
    ld      t0, 8(s3)                       # SSZ: the bytes from sent, as many as fit
    add     a1, s3, t0
    ld      t1, 16(s3)
    ld      t2, NodeEvent_api(s5)
    sub     a2, t1, t2
    sub     t3, s8, s6
    bleu    a2, t3, 11f
    mv      a2, t3
11: add     a1, a1, t2
    add     t2, t2, a2
    sd      t2, NodeEvent_api(s5)
    mv      a0, s6
    add     s6, s6, a2
    call    lantern_copy
    ld      t2, NodeEvent_api(s5)
    ld      t1, 16(s3)
    bne     t2, t1, 2f
    ld      t0, (NodeEvent_api + 8)(s5)
    li      t1, API_STREAM_ITEMS | API_STREAM_ITEM_DONE
    or      t0, t0, t1
    sd      t0, (NodeEvent_api + 8)(s5)
2:  li      a0, 0
    UNFRAME 0
3:  ld      t0, (NodeEvent_api + 16)(s5)    # JSON: the cursor's depth, 0 before the first byte
    bnez    t0, 4f
    ld      t0, (NodeEvent_api + 8)(s5)
    li      t1, API_STREAM_ITEMS
    and     t0, t0, t1
    beqz    t0, 4f
    API_LIT api_p_comma
4:  ld      t0, NodeApi_op(s4)
    li      a0, NODE_JSON_BLOB_SIDECAR
    li      t1, API_OP_GET_BLOB_SIDECARS
    beq     t0, t1, 5f
    li      a0, NODE_JSON_DATA_COLUMN_SIDECAR
5:  addi    t0, s5, NodeEvent_api_bytes     # the ByteList: its room to s8 - 1, its bytes to s6
    addi    t1, s8, -1
    sub     t1, t1, t0
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    sub     t1, s6, s10
    sd      t1, 16(t0)
    mv      a1, s3
    addi    a2, s5, (NodeEvent_api + 16)
    addi    a3, s5, NodeEvent_api_bytes
    ld      t6, NodeApi_fork(s4)
    FORK_CALL node_json
    ld      t0, (NodeEvent_api_bytes + 16)(s5)
    add     s6, s10, t0
    li      t0, LANTERN_JSON_MORE
    beq     a0, t0, 8f
    bnez    a0, 7f
    ld      t0, (NodeEvent_api + 8)(s5)
    li      t1, API_STREAM_ITEMS | API_STREAM_ITEM_DONE
    or      t0, t0, t1
    sd      t0, (NodeEvent_api + 8)(s5)
8:  li      a0, 0
    UNFRAME 0
7:  li      a0, 2
    UNFRAME 0
END_FUNCTION api_sidecar_body

/*
 * The pool stream of the NodeApi entry a0 goes to its next entry after slot (node.md,
 * NODE_WORK_API_CHUNK): its slot, data, sent and member, a zero cursor; data 0 with none. Bytes it owned
 * get a NODE_ACT_BYTES_FREE, and API_STREAM_OWN clears. Locals: the entry, the old data, the flags.
 */
LOCAL_FUNCTION node_api_pool_advance
    FRAME 32
    sd      a0, 0(sp)
    ld      t0, NodeApi_data(a0)
    sd      t0, 8(sp)
    ld      t0, NodeApi_flags(a0)
    sd      t0, 16(sp)
    mv      a1, a0
    ld      t0, NodeApi_slot(a0)
    addi    a0, t0, 1
    call    node_pool_next
    ld      t0, 0(sp)
    li      t2, 0
    li      t1, -1
    beq     a0, t1, 1f
    sd      a0, NodeApi_slot(t0)
    ld      t1, NodePool_fork(a1)
    sd      t1, NodeApi_sent(t0)
    ld      t1, NodePool_member(a1)
    sd      t1, NodeApi_member(t0)
    ld      t2, NodePool_data_id(a1)
1:  sd      t2, NodeApi_data(t0)
    ld      t1, NodeApi_flags(t0)
    andi    t1, t1, ~API_STREAM_OWN
    sd      t1, NodeApi_flags(t0)
    addi    a0, t0, NodeApi_cursor
    li      a1, JSON_CURSOR_SIZE
    call    lantern_zero
    ld      t0, 16(sp)                      # API_STREAM_OWN: the old bytes go
    andi    t0, t0, API_STREAM_OWN
    beqz    t0, 9f
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, 8(sp)
    li      a2, 0
    call    node_ids
9:  UNFRAME 32
END_FUNCTION node_api_pool_advance

/*
 * A pool stream's JSON, as api_stream_json: with the bytes s3, the JSON of the pool entry from
 * the cursor at NodeEvent_api + 16, by lantern_node_json of the fork in sent (NodeEvent_api) and
 * the kind of the GET, after , when API_STREAM_ITEMS is set and the cursor is at its start; once
 * whole, API_STREAM_ITEMS and API_STREAM_ITEM_DONE in the event. With s3 = 0: ]}. a0 = 1 when the
 * answer is whole, 0 when more is to come, 2 for bytes that are no encoding.
 */
LOCAL_FUNCTION api_pool_json
    FRAME 0
    bnez    s3, 1f
    API_LIT api_v_end
    li      a0, 1
    UNFRAME 0
1:  ld      t0, (NodeEvent_api + 16)(s5)    # the cursor's depth: 0 before the first byte
    bnez    t0, 2f
    ld      t0, (NodeEvent_api + 8)(s5)
    li      t1, API_STREAM_ITEMS
    and     t0, t0, t1
    beqz    t0, 2f
    API_LIT api_p_comma
2:  ld      t0, NodeApi_op(s4)              # the kind of the GET's operation
    li      a0, NODE_JSON_EXIT
    li      t1, API_OP_GET_POOL_VOLUNTARY_EXITS
    beq     t0, t1, 3f
    li      a0, NODE_JSON_PROPOSER_SLASHING
    li      t1, API_OP_GET_POOL_PROPOSER_SLASHINGS
    beq     t0, t1, 3f
    li      a0, NODE_JSON_ATTESTER_SLASHING
    li      t1, API_OP_GET_POOL_ATTESTER_SLASHINGS_V2
    beq     t0, t1, 3f
    li      a0, NODE_JSON_ATTESTATION
    li      t1, API_OP_GET_POOL_ATTESTATIONS_V2
    beq     t0, t1, 3f
    li      a0, NODE_JSON_BLS_CHANGE
3:  addi    t0, s5, NodeEvent_api_bytes     # the ByteList: its room to s8 - 1, its bytes to s6
    addi    t1, s8, -1
    sub     t1, t1, t0
    sd      t1, 0(t0)
    li      t1, 24
    sd      t1, 8(t0)
    sub     t1, s6, s10
    sd      t1, 16(t0)
    mv      a1, s3
    addi    a2, s5, (NodeEvent_api + 16)
    addi    a3, s5, NodeEvent_api_bytes
    ld      t6, NodeEvent_api(s5)
    FORK_CALL node_json
    ld      t0, (NodeEvent_api_bytes + 16)(s5)
    add     s6, s10, t0
    li      t0, LANTERN_JSON_MORE
    beq     a0, t0, 8f
    bnez    a0, 7f
    ld      t0, (NodeEvent_api + 8)(s5)     # whole: the entry is done
    li      t1, API_STREAM_ITEMS | API_STREAM_ITEM_DONE
    or      t0, t0, t1
    sd      t0, (NodeEvent_api + 8)(s5)
8:  li      a0, 0
    UNFRAME 0
7:  li      a0, 2
    UNFRAME 0
END_FUNCTION api_pool_json

/*
 * The failures of the event s4 of a NODE_WORK_API_SUBMIT: {"index":<i>,"message":"REJECT"} for
 * each record of LANTERN_GOSSIP_REJECT, with , between, then ]}. Locals: the record, its index,
 * the failures written.
 */
LOCAL_FUNCTION api_failures
    FRAME 32
    ld      t0, (NodeEvent_chunk + 8)(s4)
    addi    t1, s4, NodeEvent_chunk
    add     t0, t1, t0
    sd      t0, 0(sp)
    sd      zero, 8(sp)
    sd      zero, 16(sp)
1:  ld      t0, 8(sp)
    ld      t1, NodeEvent_index(s4)
    bgeu    t0, t1, 9f
    ld      t0, 0(sp)
    ld      t1, 0(t0)
    li      t2, LANTERN_GOSSIP_REJECT
    bne     t1, t2, 3f
    ld      t0, 16(sp)
    beqz    t0, 2f
    API_LIT api_p_comma
2:  API_LIT api_f_index
    ld      a0, 8(sp)
    call    api_dec
    API_LIT api_f_reject
    ld      t0, 16(sp)
    addi    t0, t0, 1
    sd      t0, 16(sp)
3:  ld      t0, 0(sp)                       # the next record: its code, its subnet, then its ByteList
    ld      t1, 16(t0)
    addi    t0, t0, 16
    add     t0, t0, t1
    sd      t0, 0(sp)
    ld      t0, 8(sp)
    addi    t0, t0, 1
    sd      t0, 8(sp)
    j       1b
9:  API_LIT api_v_end
    UNFRAME 32
END_FUNCTION api_failures

/*
 * (connection a0, route a1, flags a2, request a3, view a4) -> a0: a pool POST (node.md,
 * NODE_EV_API): a NODE_ACT_BYTES_PUT of the body and a NODE_WORK_API_SUBMIT; 0 once queued, else
 * the status of the error to answer. Locals: the connection, the flags, the route, the view, the
 * head's post-state, a ByteList head whose offset reaches the body.
 */
LOCAL_FUNCTION node_api_submit
    FRAME 64
    sd      a0, 0(sp)
    sd      a2, 8(sp)
    sd      a1, 16(sp)
    sd      a4, 24(sp)
    ld      t0, ApiRoute_body(a1)           # an SSZ body: an answer flag
    li      t1, API_TYPE_SSZ
    bne     t0, t1, 11f
    ori     a2, a2, API_ANSWER_SSZ
    sd      a2, 8(sp)
11: ld      t0, ApiRoute_op(a1)             # the AttesterSlashing or attestation type of the store's fork
    li      t1, API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    beq     t0, t1, 12f
    li      t1, API_OP_SUBMIT_POOL_ATTESTER_SLASHINGS_V2
    bne     t0, t1, 1f
12:
    li      t2, FORK_ELECTRA
    ld      t0, ApiRoute_consensus_version(a1)
    sltu    t0, t0, t2
    ld      t1, ApiView_fork(a4)
    sltu    t1, t1, t2
    bne     t0, t1, 80f
1:  ld      t0, (HttpRequest_body + 8)(a3)  # a body of no bytes: 400
    beqz    t0, 80f
    ld      t1, HttpRequest_body(a3)
    add     t1, a3, t1
    addi    t2, sp, 40
    sub     t1, t1, t2
    sd      t0, 40(sp)
    sd      t1, 48(sp)
    sd      t0, 56(sp)
    addi    a0, s1, Node_head_root          # the head's post-state, else 500
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 81f
    ld      t0, NodeBlock_state_id(a1)
    beqz    t0, 81f
    sd      t0, 32(sp)
    addi    a0, sp, 40
    call    node_put
    mv      a3, a0
    li      a0, NODE_WORK_API_SUBMIT
    ld      a1, 32(sp)
    li      a2, 0
    ld      a4, 0(sp)
    ld      t0, 16(sp)
    ld      a5, ApiRoute_op(t0)
    ld      t0, 8(sp)
    slli    t0, t0, 8
    or      a5, a5, t0
    ld      t0, 24(sp)
    ld      t0, ApiView_fork(t0)
    slli    t0, t0, 16
    or      a5, a5, t0
    call    node_work
    li      a0, 0
    UNFRAME 64
80: li      a0, 400
    UNFRAME 64
81: li      a0, 500
    UNFRAME 64
END_FUNCTION node_api_submit

/*
 * a0 = 0 when the NODE_EV_WORK_DONE a0 of a1 bytes of a valid NODE_WORK_API_SUBMIT holds its
 * records inside it (node.md): a ByteList at NodeEvent_chunk of offset 24, and NodeEvent_index
 * records in its bytes, each a code and a ByteList of offset 24 whose size is a multiple of 8;
 * else 1. Uses a1-a6.
 */
LOCAL_FUNCTION node_submit_check
    UNWIND_END_PROLOGUE
    li      a2, NodeEvent_chunk + 24
    bltu    a1, a2, 8f
    ld      a2, (NodeEvent_chunk + 8)(a0)
    li      a3, 24
    bne     a2, a3, 8f
    ld      a2, (NodeEvent_chunk + 16)(a0)
    addi    a3, a1, -(NodeEvent_chunk + 24)
    bgtu    a2, a3, 8f
    addi    a3, a0, NodeEvent_chunk + 24    # the first record, and the end
    add     a4, a3, a2
    ld      a5, NodeEvent_index(a0)
1:  beqz    a5, 7f
    sub     a6, a4, a3
    li      a2, 40
    bltu    a6, a2, 8f
    addi    a6, a6, -16
    ld      a2, 16(a3)                      # size, offset, count of its ByteList, after the code and the subnet
    bgtu    a2, a6, 8f
    li      a1, 24
    bltu    a2, a1, 8f
    andi    a6, a2, 7
    bnez    a6, 8f
    ld      a6, 24(a3)
    bne     a6, a1, 8f
    ld      a6, 32(a3)
    addi    a1, a2, -24
    bgtu    a6, a1, 8f
    addi    a3, a3, 16
    add     a3, a3, a2
    addi    a5, a5, -1
    j       1b
7:  li      a0, 0
    ret
8:  li      a0, 1
    ret
END_FUNCTION node_submit_check

/*
 * The NODE_EV_WORK_DONE a0 of a NODE_WORK_API_SUBMIT (node.md, lantern_node_step): the body's
 * bytes go; each valid operation joins the pool, goes out on its topic with NODE_FLAG_SUBSCRIBED,
 * and an attester slashing to fork choice; then the answer to the connection. s1 the node, s2 the
 * store, s6 the actions. s3 the event, s4 the record, s7 the records left, s8 the failures, s9 the
 * topic, s10 the new id. Locals: L 1 when the pool keeps it, L+8 the answer's flags.
 */
LOCAL_FUNCTION node_api_submit_done
    ENTER 16
    mv      s3, a0
    li      a0, NODE_ACT_BYTES_FREE
    ld      a1, NodeAction_data(s3)
    li      a2, 0
    call    node_ids
    ld      t0, NodeAction_arg(s3)          # the answer's flags: API_STREAM_CLOSE (1), API_STREAM_HTTP10 (2)
    srli    t0, t0, 8
    li      t1, API_R_CLOSE
    andi    t2, t0, API_STREAM_CLOSE
    bnez    t2, 1f
    li      t1, 0
    andi    t2, t0, API_STREAM_HTTP10
    beqz    t2, 1f
    li      t1, API_R_KEEP
1:  sd      t1, (L + 8)(sp)
    ld      a0, NodeAction_arg(s3)
    andi    a0, a0, 255
    call    node_submit_topic
    mv      s9, a0
    ld      t0, NodeEvent_result(s3)
    bnez    t0, 80f
    li      s8, 0
    ld      s7, NodeEvent_index(s3)
    ld      t0, (NodeEvent_chunk + 8)(s3)
    addi    s4, s3, NodeEvent_chunk
    add     s4, s4, t0
2:  beqz    s7, 70f
    ld      t0, 0(s4)                       # its code
    li      t1, LANTERN_GOSSIP_REJECT
    bne     t0, t1, 21f
    addi    s8, s8, 1
21: bnez    t0, 6f
    addi    a0, s4, 16                      # valid: its bytes to a new id, kept by the pool when it has room
    call    node_put
    mv      s10, a0
    li      a4, 0                           # an attestation: its slot and committee index, its member
    li      a5, 0
    ld      a6, 8(s4)
    srli    a6, a6, 32
    li      t1, GOSSIP_BEACON_ATTESTATION
    bne     s9, t1, 22f
    ld      t0, 24(s4)
    add     t0, s4, t0
    addi    t0, t0, 16
    ld      t1, NodeAction_arg(s3)
    srli    t1, t1, 16
    li      t2, FORK_ELECTRA
    bgeu    t1, t2, 23f
    LDU64   a4, t0, 4, t1                   # Attestation: data.slot at 4, data.index at 12
    LDU64   a5, t0, 12, t1
    j       22f
23: ld      a4, 16(t0)                      # SingleAttestation: committee_index at 0, data.slot at 16
    ld      a5, 0(t0)
22: mv      a0, s9
    mv      a1, s10
    ld      a2, 32(s4)
    ld      a3, NodeAction_arg(s3)
    srli    a3, a3, 16
    call    node_pool_add
    sd      a0, (L + 0)(sp)
    ld      t0, Node_flags(s1)              # NODE_FLAG_SUBSCRIBED: out on its topic, an attestation on its subnet
    andi    t0, t0, NODE_FLAG_SUBSCRIBED
    beqz    t0, 3f
    mv      a0, s9
    addi    a1, s4, 16
    lwu     a2, 8(s4)
    call    node_publish
3:  li      t0, GOSSIP_ATTESTER_SLASHING    # an attester slashing: on_attester_slashing with the justified root's state
    bne     s9, t0, 4f
    addi    a0, s2, Store_justified_checkpoint + 8
    call    node_find_block
    li      t0, -1
    beq     a0, t0, 4f
    ld      t0, NodeBlock_status(a1)
    li      t1, NODE_BLOCK_IMPORTED
    bne     t0, t1, 4f
    ld      a1, NodeBlock_state_id(a1)
    beqz    a1, 4f
    li      a0, NODE_WORK_ATTESTER_SLASHING
    li      a2, 0
    mv      a3, s10
    li      a4, 0
    li      a5, 0
    call    node_work
    j       6f
4:  ld      t0, (L + 0)(sp)                 # bytes no entry keeps and no work reads go
    bnez    t0, 6f
    li      a0, NODE_ACT_BYTES_FREE
    mv      a1, s10
    li      a2, 0
    call    node_ids
6:  ld      t0, 16(s4)
    addi    s4, s4, 16
    add     s4, s4, t0
    addi    s7, s7, -1
    j       2b
70: ld      a0, NodeAction_target(s3)       # the answer: 200, or 400 with the failures
    beqz    s8, 71f
    ld      t0, NodeAction_arg(s3)          # a list: the failures
    andi    t0, t0, 255
    li      t1, API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    beq     t0, t1, 72f
    li      t1, API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    bne     t0, t1, 80f
72: mv      a1, s3
    li      a2, 400
    li      a3, API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    ld      a4, (L + 8)(sp)
    call    node_api_send
    LEAVE 16
71: li      a1, 0
    li      a2, 200
    li      a3, 0
    ld      a4, (L + 8)(sp)
    call    node_api_send
    LEAVE 16
80: ld      a0, NodeAction_target(s3)
    li      a1, 0
    li      a2, 400
    li      a3, API_BODY_ERROR
    ld      a4, (L + 8)(sp)
    call    node_api_send
    LEAVE 16
END_FUNCTION node_api_submit_done

/*
 * The publish of the SSZ bytes of the ByteList a1 on the gossip topic a0 of the subnet a2 (node.md, the publish):
 * a LIBP2P_EVENT_PUBLISH at the end of p2p_out; none when it does not fit. Its data compresses in
 * place, its ByteList head in the 24 bytes before the data. s1 the node, s2 the store, s5 the
 * scratch. s3 the bytes, then the data's length; s4 the event, s7 the topic's length, s8 the
 * data's offset in the event, s9 the event's room. Locals: L a GossipTopic, L+24 the topic's
 * ByteList (24 + 128), L+176 a size, L+184 the message-id (24).
 */
LOCAL_FUNCTION node_publish
    ENTER 208
    mv      s3, a1
    lwu     t0, Node_fork_digest(s1)
    sd      t0, (L + GossipTopic_fork_digest)(sp)
    sd      a0, (L + GossipTopic_name)(sp)
    sd      a2, (L + GossipTopic_subnet_id)(sp)
    li      t0, 24 + 128
    sd      t0, (L + 24)(sp)
    li      t0, 24
    sd      t0, (L + 32)(sp)
    sd      zero, (L + 40)(sp)
    addi    a0, sp, L
    addi    a1, sp, L + 24
    call    lantern_gossip_topic
    bnez    a0, 9f
    ld      s7, (L + 40)(sp)
    addi    s8, s7, LIBP2P_EV_PUB_TOPIC + 7
    andi    s8, s8, -8
    mv      a0, s3
    addi    a1, sp, L + 176
    CALL_GLOBAL snappy_compress_size
    bnez    a0, 9f
    ld      t0, (L + 176)(sp)               # the room: the data's offset, then at most size - 24 bytes
    addi    t0, t0, -24
    add     t0, t0, s8
    addi    t0, t0, 7
    andi    s9, t0, -8
    mv      a0, s9
    call    node_out
    beqz    a0, 9f
    mv      s4, a0
    add     a2, s4, s8                      # the data's ByteList head before it: its room to the event's end
    addi    a2, a2, -24
    sub     t0, s9, s8
    addi    t0, t0, 24
    sd      t0, 0(a2)
    mv      a0, s3
    mv      a1, s5
    CALL_GLOBAL snappy_compress
    bnez    a0, 8f
    mv      a0, s2                          # the message-id: of the fork of the store's slot
    call    node_store_slot
    addi    a1, s1, Node_config
    call    node_fork
    mv      t6, a0
    addi    a0, sp, L + 24
    add     a1, s4, s8
    addi    a1, a1, -24
    addi    a2, s1, Node_config
    mv      a3, s5
    addi    a4, sp, L + 184
    FORK_CALL compute_message_id
    bnez    a0, 8f
    add     t0, s4, s8                      # the data's length; the event to its bytes
    ld      s3, -8(t0)
    add     t0, s8, s3
    addi    t0, t0, 7
    andi    t0, t0, -8
    ld      t1, Node_p2p_out(s1)
    add     t1, s1, t1
    ld      t2, 16(t1)
    sub     t2, t2, s9
    add     t2, t2, t0
    sd      t2, 16(t1)
    mv      s9, t0
    sd      t0, 0(s4)
    li      t0, LIBP2P_EVENT_PUBLISH
    sd      t0, 8(s4)
    li      t0, 20
    sd      t0, LIBP2P_EV_PUB_ID_LEN(s4)
    sd      zero, (LIBP2P_EV_PUB_ID + 16)(s4)
    sd      zero, (LIBP2P_EV_PUB_ID + 24)(s4)
    addi    a0, s4, LIBP2P_EV_PUB_ID
    addi    a1, sp, L + 184
    li      a2, 20
    call    lantern_copy
    sd      s7, LIBP2P_EV_PUB_TOPIC_LEN(s4)
    sd      s3, LIBP2P_EV_PUB_DATA_LEN(s4)
    addi    a0, s4, LIBP2P_EV_PUB_TOPIC
    addi    a1, sp, L + 48
    mv      a2, s7
    call    lantern_copy
    addi    a0, s4, LIBP2P_EV_PUB_TOPIC     # zero bytes after the topic and after the data
    add     a0, a0, s7
    addi    a1, s8, -LIBP2P_EV_PUB_TOPIC
    sub     a1, a1, s7
    call    lantern_zero
    add     a0, s4, s8
    add     a0, a0, s3
    sub     a1, s9, s8
    sub     a1, a1, s3
    call    lantern_zero
9:  LEAVE 208
8:  ld      t1, Node_p2p_out(s1)            # no publish: the room goes back
    add     t1, s1, t1
    ld      t2, 16(t1)
    sub     t2, t2, s9
    sd      t2, 16(t1)
    LEAVE 208
END_FUNCTION node_publish

/*
 * (text a0 to a1, kind a2, fork a3, fault a4, record a5, the event's end a6) -> a0: the JSON text
 * decoded by lantern_node_json_decode into the record a5 (s6 the scratch of
 * node_api_submit_run): code and subnet 0, then a ByteList of the SSZ bytes, its size to a multiple of 8;
 * a1 the next record. a0 = 0, 1 for a text that is no such value, 2 for too little room.
 * Locals: a ByteList head of the text, the record.
 */
LOCAL_FUNCTION node_submit_decode
    FRAME 32
    sd      a5, 24(sp)
    sub     a1, a1, a0
    sd      a1, 0(sp)
    sub     t0, a0, sp
    sd      t0, 8(sp)
    sd      a1, 16(sp)
    addi    t0, a5, 40
    bgtu    t0, a6, 8f
    sub     t0, a6, a5
    addi    t0, t0, -16
    sd      t0, 16(a5)
    mv      t6, a3
    mv      a0, a2
    mv      a1, sp
    mv      a2, s6
    addi    a3, a5, 16
    FORK_CALL node_json_decode
    li      t0, LANTERN_BUFFER_TOO_SMALL
    beq     a0, t0, 8f
    bnez    a0, 7f
    ld      a5, 24(sp)                      # its size: the bytes to a multiple of 8, zero after them
    ld      t1, 32(a5)
    addi    t0, t1, 24 + 7
    andi    t0, t0, -8
    sd      t0, 16(a5)
    sd      zero, 0(a5)
    sd      zero, 8(a5)
    addi    a0, a5, 40
    add     a0, a0, t1
    addi    a1, t0, -24
    sub     a1, a1, t1
    call    lantern_zero
    ld      a5, 24(sp)
    ld      t0, 16(a5)
    addi    a1, a5, 16
    add     a1, a1, t0
    li      a0, 0
    UNFRAME 32
7:  li      a0, 1
    UNFRAME 32
8:  li      a0, 2
    UNFRAME 32
END_FUNCTION node_submit_decode

/*
 * (bytes a0, length a1, record a5, the event's end a6) -> a0: the bytes as the record a5 of
 * node_api_submit_run: code and subnet 0, then a ByteList of them, its size to a multiple of 8;
 * a1 the next record. a0 = 0, or 2 for too little room. Locals: the record, its size, the length.
 */
LOCAL_FUNCTION node_submit_copy
    FRAME 32
    addi    t0, a1, 16 + 24 + 7
    andi    t0, t0, -8
    add     t1, a5, t0
    bgtu    t1, a6, 8f
    sd      a5, 0(sp)
    sd      t0, 8(sp)
    sd      a1, 16(sp)
    sd      zero, 0(a5)
    sd      zero, 8(a5)
    addi    t1, t0, -16
    sd      t1, 16(a5)
    li      t1, 24
    sd      t1, 24(a5)
    sd      a1, 32(a5)
    mv      a2, a1
    mv      a1, a0
    addi    a0, a5, 40
    call    lantern_copy
    ld      a5, 0(sp)
    ld      t1, 16(sp)
    addi    a0, a5, 40
    add     a0, a0, t1
    ld      a1, 8(sp)
    addi    a1, a1, -40
    sub     a1, a1, t1
    call    lantern_zero
    ld      a1, 0(sp)
    ld      t0, 8(sp)
    add     a1, a1, t0
    li      a0, 0
    UNFRAME 32
8:  li      a0, 2
    UNFRAME 32
END_FUNCTION node_submit_copy

/*
 * (node a0, store a1, seen a2, work a3, state_a a4, data a5, scratch a6, event a7, room t0) -> a0:
 * a NODE_WORK_API_SUBMIT of lantern_node_run (node.md): the operations of the body decoded as
 * records at NodeEvent_chunk of the event, then each checked by lantern_node_gossip of the fork
 * arg / 2^16 with seen. s1 node, s2 store, s3 work, s4 state_a, s5 data, s6 scratch, s7 the event,
 * s8 its end, s9 the next record, s10 the text's end, then the records left. Locals: L seen, L+8
 * the kind, L+16 the topic, L+24 the fork, L+32 the operations, L+40 1 for a list, L+48 where the
 * text goes on, L+56 an item's start, L+64 a NodeGossip, L+144 a JsonFault, L+272 a root, L+304
 * an index.
 */
LOCAL_FUNCTION node_api_submit_run
    ENTER 320
    mv      s1, a0
    mv      s2, a1
    sd      a2, (L + 0)(sp)
    mv      s3, a3
    mv      s4, a4
    mv      s5, a5
    mv      s6, a6
    mv      s7, a7
    add     s8, a7, t0
    ld      t0, NodeAction_arg(s3)          # the operation's kind and topic; the fork
    srli    t1, t0, 16
    li      t2, FORK_FULU
    bgtu    t1, t2, 98f
    sd      t1, (L + 24)(sp)
    andi    a0, t0, 255
    li      t2, API_OP_SUBMIT_POOL_BLS_TO_EXECUTION_CHANGE
    sub     t2, a0, t2
    seqz    t2, t2
    li      t3, API_OP_SUBMIT_POOL_ATTESTATIONS_V2
    sub     t3, a0, t3
    seqz    t3, t3
    or      t2, t2, t3
    sd      t2, (L + 40)(sp)
    call    node_submit_topic
    beqz    a0, 98f
    sd      a0, (L + 16)(sp)
    li      t0, GOSSIP_BEACON_ATTESTATION   # an attestation: of the fork's type
    bne     a0, t0, 12f
    ld      t0, (L + 24)(sp)
    li      t1, FORK_ELECTRA
    li      a0, NODE_JSON_ATTESTATION
    bltu    t0, t1, 13f
    li      a0, NODE_JSON_SINGLE_ATTESTATION
    j       13f
12: call    node_pool_kind
13: sd      a0, (L + 8)(sp)
    beqz    s4, 98f
    beqz    s5, 98f
    addi    t0, s7, NodeEvent_chunk         # the records' ByteList
    addi    t1, t0, 24
    bgtu    t1, s8, 97f
    sub     t2, s8, t0
    sd      t2, 0(t0)
    li      t2, 24
    sd      t2, 8(t0)
    sd      zero, 16(t0)
    mv      s9, t1
    sd      zero, (L + 32)(sp)
    ld      t0, 8(s5)                       # the text
    add     a0, s5, t0
    ld      t1, 16(s5)
    add     s10, a0, t1
    ld      t0, NodeAction_arg(s3)          # an SSZ body: the list's items
    srli    t0, t0, 8
    andi    t0, t0, API_ANSWER_SSZ
    bnez    t0, 40f
    ld      t0, (L + 40)(sp)
    bnez    t0, 20f
    mv      a1, s10                         # one operation: the whole text
    ld      a2, (L + 8)(sp)
    ld      a3, (L + 24)(sp)
    addi    a4, sp, L + 144
    mv      a5, s9
    mv      a6, s8
    call    node_submit_decode
    li      t0, 1
    beq     a0, t0, 90f
    bgtu    a0, t0, 97f
    mv      s9, a1
    li      t0, 1
    sd      t0, (L + 32)(sp)
    j       30f
20: ld      t0, (L + 16)(sp)                # a JSON array; of BLS changes from capella
    li      t1, GOSSIP_BLS_TO_EXECUTION_CHANGE
    bne     t0, t1, 201f
    ld      t0, (L + 24)(sp)
    li      t1, FORK_CAPELLA
    bltu    t0, t1, 90f
201:
    call    submit_ws
    bgeu    a0, s10, 90f
    lbu     t0, 0(a0)
    li      t1, '['
    bne     t0, t1, 90f
    addi    a0, a0, 1
    call    submit_ws
    bgeu    a0, s10, 90f
    lbu     t0, 0(a0)
    li      t1, ']'
    bne     t0, t1, 23f
    addi    a0, a0, 1
    j       28f
23: sd      a0, (L + 56)(sp)                # an item: to a , or ] outside strings, arrays and objects
    li      t2, 0
24: bgeu    a0, s10, 90f
    lbu     t0, 0(a0)
    li      t1, '"'
    bne     t0, t1, 25f
253: addi   a0, a0, 1
    bgeu    a0, s10, 90f
    lbu     t0, 0(a0)
    li      t1, '\\'
    bne     t0, t1, 252f
    addi    a0, a0, 1
    j       253b
252: li     t1, '"'
    bne     t0, t1, 253b
    addi    a0, a0, 1
    j       24b
25: li      t1, '{'
    beq     t0, t1, 251f
    li      t1, '['
    bne     t0, t1, 26f
251: addi   t2, t2, 1
    addi    a0, a0, 1
    j       24b
26: li      t1, '}'
    beq     t0, t1, 261f
    li      t1, ']'
    bne     t0, t1, 27f
261: beqz   t2, 271f
    addi    t2, t2, -1
    addi    a0, a0, 1
    j       24b
27: li      t1, ','
    bne     t0, t1, 272f
    beqz    t2, 271f
272: addi   a0, a0, 1
    j       24b
271: sd     a0, (L + 48)(sp)
    mv      a1, a0
    ld      a0, (L + 56)(sp)
    ld      a2, (L + 8)(sp)
    ld      a3, (L + 24)(sp)
    addi    a4, sp, L + 144
    mv      a5, s9
    mv      a6, s8
    call    node_submit_decode
    li      t0, 1
    beq     a0, t0, 90f
    bgtu    a0, t0, 97f
    mv      s9, a1
    ld      t0, (L + 32)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 32)(sp)
    ld      a0, (L + 48)(sp)
    lbu     t0, 0(a0)
    addi    a0, a0, 1
    li      t1, ','
    beq     t0, t1, 23b
    li      t1, ']'
    bne     t0, t1, 90f
28: call    submit_ws                       # then only white space
    bne     a0, s10, 90f
    j       30f
40: sd      a0, (L + 48)(sp)                # SSZ: from electra items of 240 bytes
    sub     t0, s10, a0
    ld      t1, (L + 24)(sp)
    li      t2, FORK_ELECTRA
    bltu    t1, t2, 42f
    li      t1, 240
    divu    t2, t0, t1
    mul     t3, t2, t1
    bne     t3, t0, 90f
    sd      t2, (L + 56)(sp)
41: ld      t2, (L + 56)(sp)
    beqz    t2, 30f
    ld      a0, (L + 48)(sp)
    li      a1, 240
    mv      a5, s9
    mv      a6, s8
    call    node_submit_copy
    bnez    a0, 97f
    mv      s9, a1
    ld      t0, (L + 48)(sp)
    addi    t0, t0, 240
    sd      t0, (L + 48)(sp)
    ld      t0, (L + 56)(sp)
    addi    t0, t0, -1
    sd      t0, (L + 56)(sp)
    ld      t0, (L + 32)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 32)(sp)
    j       41b
42: beqz    t0, 30f                         # before electra: the items of the 4-byte offsets
    li      t1, 4
    bltu    t0, t1, 90f
    lwu     t1, 0(a0)
    beqz    t1, 90f
    andi    t2, t1, 3
    bnez    t2, 90f
    bgtu    t1, t0, 90f
    srli    t1, t1, 2
    sd      t1, (L + 304)(sp)
    sd      zero, (L + 56)(sp)
43: ld      t3, (L + 56)(sp)
    ld      t1, (L + 304)(sp)
    bgeu    t3, t1, 30f
    ld      a0, (L + 48)(sp)
    slli    t2, t3, 2
    add     t2, a0, t2
    lwu     t4, 0(t2)
    sub     t5, s10, a0
    addi    t3, t3, 1
    bgeu    t3, t1, 44f
    lwu     t5, 4(t2)
44: bgtu    t4, t5, 90f
    sub     t2, s10, a0
    bgtu    t5, t2, 90f
    add     a0, a0, t4
    sub     a1, t5, t4
    mv      a5, s9
    mv      a6, s8
    call    node_submit_copy
    bnez    a0, 97f
    mv      s9, a1
    ld      t0, (L + 56)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 56)(sp)
    ld      t0, (L + 32)(sp)
    addi    t0, t0, 1
    sd      t0, (L + 32)(sp)
    j       43b
30: sub     t0, s9, s7                      # the records: their bytes, their count
    sd      t0, 0(s7)
    addi    t0, t0, -NodeEvent_chunk
    sd      t0, NodeEvent_chunk(s7)
    addi    t0, t0, -24
    sd      t0, (NodeEvent_chunk + 16)(s7)
    ld      t0, (L + 32)(sp)
    sd      t0, NodeEvent_index(s7)
    ld      t1, (L + 0)(sp)                 # seen has a key free for each operation
    ld      t2, Seen_bits(t1)
    ld      t3, Seen_keys(t1)
    sub     t2, t2, t3
    srli    t2, t2, 5
    ld      t3, (Seen_keys + 8)(t1)
    sub     t2, t2, t3
    bltu    t2, t0, 97f
    ld      t0, (L + 0)(sp)                 # the NodeGossip of the operations
    sd      t0, (L + 64 + NodeGossip_seen)(sp)
    sd      s2, (L + 64 + NodeGossip_store)(sp)
    ld      t0, Node_time_ms(s1)
    sd      t0, (L + 64 + NodeGossip_time_ms)(sp)
    ld      t0, (L + 16)(sp)
    sd      t0, (L + 64 + NodeGossip_topic)(sp)
    sd      zero, (L + 64 + NodeGossip_subnet)(sp)
    sd      s4, (L + 64 + NodeGossip_head)(sp)
    sd      zero, (L + 64 + NodeGossip_proposer)(sp)
    sd      zero, (L + 64 + NodeGossip_justified)(sp)
    sd      zero, (L + 64 + NodeGossip_settings)(sp)
    addi    t0, s1, Node_config
    sd      t0, (L + 64 + NodeGossip_config)(sp)
    addi    s9, s7, NodeEvent_chunk + 24
    ld      s10, (L + 32)(sp)
31: beqz    s10, 39f
    sd      zero, 8(s9)                     # the subnet: 0, but an attestation's
    ld      t0, (L + 16)(sp)
    li      t1, GOSSIP_BEACON_ATTESTATION
    bne     t0, t1, 33f
    ld      t0, 32(s9)
    addi    t2, s9, 40
    ld      t1, (L + 24)(sp)
    li      t3, FORK_ELECTRA
    bltu    t1, t3, 32f
    li      t1, 240                         # a SingleAttestation: committee_index 0, data.slot 16, data.target.epoch 104
    bltu    t0, t1, 33f
    ld      t3, 0(t2)
    ld      t4, 16(t2)
    ld      t5, 104(t2)
    j       34f
32: li      t1, 228                         # an Attestation: data.slot 4, data.index 12, data.target.epoch 92
    bltu    t0, t1, 33f
    LDU64   t4, t2, 4, t1
    LDU64   t3, t2, 12, t1
    LDU64   t5, t2, 92, t1
34: sd      t3, (L + 48)(sp)
    sd      t4, (L + 56)(sp)
    sd      t5, (L + 272)(sp)
    mv      a0, s4
    addi    a1, sp, L + 272
    LDQ     a2, s1, Node_config + CONFIG_COMMITTEE_CACHE
    mv      a3, s6
    addi    a4, sp, L + 304
    ld      t6, (L + 24)(sp)
    FORK_CALL get_committee_count_per_slot
    bnez    a0, 33f
    ld      t0, (L + 304)(sp)               # compute_subnet_for_attestation
    ld      t4, (L + 56)(sp)
    andi    t4, t4, SLOTS_PER_EPOCH - 1
    mul     t0, t0, t4
    ld      t3, (L + 48)(sp)
    add     t0, t0, t3
    LDQ     t1, s1, Node_config + CONFIG_ATTESTATION_SUBNET_COUNT
    beqz    t1, 33f
    remu    t0, t0, t1
    sd      t0, 8(s9)
33: ld      t0, 8(s9)
    sd      t0, (L + 64 + NodeGossip_subnet)(sp)
    ld      t6, (L + 24)(sp)
    addi    a0, sp, L + 64
    addi    a1, s9, 16
    mv      a2, s6
    mv      a3, s9
    addi    a4, sp, L + 272
    addi    a5, sp, L + 304
    FORK_CALL node_gossip
    bnez    a0, 99f
    ld      t0, (L + 16)(sp)                # a valid attestation: its member, 2^32 times, with the subnet
    li      t1, GOSSIP_BEACON_ATTESTATION
    bne     t0, t1, 35f
    ld      t0, 0(s9)
    bnez    t0, 35f
    ld      t0, (L + 272 + 16)(sp)
    slli    t0, t0, 32
    ld      t1, 8(s9)
    or      t1, t1, t0
    sd      t1, 8(s9)
35: ld      t0, 16(s9)
    addi    s9, s9, 16
    add     s9, s9, t0
    addi    s10, s10, -1
    j       31b
39: li      a0, LANTERN_OK
    LEAVE 320
90: li      t0, LANTERN_INVALID_ENCODING    # a body that is no such text
    sd      t0, NodeEvent_result(s7)
    li      t0, NODE_EV_WORK_DONE_SIZE
    sd      t0, 0(s7)
    li      a0, LANTERN_OK
    LEAVE 320
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 320
98: li      a0, LANTERN_INVALID_EVENT
99: LEAVE 320
END_FUNCTION node_api_submit_run

/* a0 = a0 past the JSON white space (space, tab, LF, CR) before s10. Uses t0, t1. */
LOCAL_FUNCTION submit_ws
    UNWIND_END_PROLOGUE
1:  bgeu    a0, s10, 9f
    lbu     t0, 0(a0)
    li      t1, ' '
    beq     t0, t1, 2f
    li      t1, 9
    beq     t0, t1, 2f
    li      t1, 10
    beq     t0, t1, 2f
    li      t1, 13
    bne     t0, t1, 9f
2:  addi    a0, a0, 1
    j       1b
9:  ret
END_FUNCTION submit_ws

    RODATA
    .p2align 3
node_api_rooms:                             # the room of each text of an ApiIdentity, then 0
    .quad 64, 512, 128, 128, 64, 0
